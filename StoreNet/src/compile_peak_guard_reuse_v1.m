function run = compile_peak_guard_reuse_v1(mode, options)
%COMPILE_PEAK_GUARD_REUSE_V1 Reformat existing typical or Ausgrid evidence.
%   This function never invokes an optimizer. STORENET_TYPICAL verifies and
%   combines the frozen formal VPP-BM artifact with the existing Peak Guard
%   metrics/profile. AUSGRID reads the frozen no-161 result and recomputes
%   only the load-only paper baseline from the released input.

arguments
    mode (1, 1) string {mustBeMember(mode, ...
        ["storenet_typical", "ausgrid"])}
    options.OutputRoot (1, 1) string = ""
    options.FormalTypicalDirectory (1, 1) string = ""
    options.FormalTypicalMetricsPath (1, 1) string = ""
    options.FormalTypicalProfilesPath (1, 1) string = ""
    options.ExistingTypicalDirectory (1, 1) string = ""
    options.AusgridResultDirectory (1, 1) string = ""
    options.AusgridSpecPath (1, 1) string = ""
end

sourceFolder = string(fileparts(mfilename("fullpath")));
projectFolder = string(fullfile(sourceFolder, ".."));
options = applyDefaultPaths(options, projectFolder);
if strlength(options.OutputRoot) == 0
    options.OutputRoot = fullfile(projectFolder, "results", ...
        "bahloul_vpp_improvement_v1");
end

switch mode
    case "storenet_typical"
        run = compileStoreNetTypical(options);
    case "ausgrid"
        run = compileAusgrid(options);
end
end

function options = applyDefaultPaths(options, projectFolder)
formalTypicalRoot = fullfile(projectFolder, "results", ...
    "b2022_ir_v1_formal", "b2022_typical_v1_20200824");
if strlength(options.FormalTypicalDirectory) == 0
    options.FormalTypicalDirectory = fullfile(formalTypicalRoot, "cases", ...
        "DC_XI007_H20", "VPP_BM");
end
if strlength(options.FormalTypicalMetricsPath) == 0
    options.FormalTypicalMetricsPath = fullfile(formalTypicalRoot, ...
        "typical_metrics.csv");
end
if strlength(options.FormalTypicalProfilesPath) == 0
    options.FormalTypicalProfilesPath = fullfile(formalTypicalRoot, ...
        "figure5_profiles.csv");
end
if strlength(options.ExistingTypicalDirectory) == 0
    options.ExistingTypicalDirectory = fullfile(projectFolder, "results", ...
        "baseline_typical_20200824_v2");
end
if strlength(options.AusgridResultDirectory) == 0
    options.AusgridResultDirectory = fullfile(projectFolder, "results", ...
        "external_sensitivity_ausgrid_exclude_customer161_v1");
end
if strlength(options.AusgridSpecPath) == 0
    options.AusgridSpecPath = fullfile(projectFolder, "config", ...
        "crossenv", ...
        "ausgrid_2012_2013_exclude_customer161_sensitivity.json");
end
end

function run = compileStoreNetTypical(options)
requiredPaths = [options.FormalTypicalMetricsPath, ...
    options.FormalTypicalProfilesPath, ...
    fullfile(options.ExistingTypicalDirectory, "metrics.csv"), ...
    fullfile(options.ExistingTypicalDirectory, "profiles.csv"), ...
    fullfile(options.ExistingTypicalDirectory, "manifest.json")];
assertFilesExist(requiredPaths);
if ~isfolder(options.FormalTypicalDirectory)
    error("StoreNet:MissingFormalTypicalArtifact", ...
        "Formal typical case directory is missing: %s", ...
        options.FormalTypicalDirectory);
end

[vppMetrics, evidence] = ...
    reevaluate_bahloul_artifact(options.FormalTypicalDirectory);
formalMetrics = readMetricsTable(options.FormalTypicalMetricsPath);
formalVpp = selectFormalTypicalVpp(formalMetrics);
if abs(double(formalVpp.OptimizedBillEUR) - vppMetrics.optimizedBillEUR) > ...
        1e-10
    error("StoreNet:FormalTypicalMetricMismatch", ...
        "Formal typical CSV and its content-addressed VPP artifact differ.");
end
existingMetrics = readMetricsTable(fullfile( ...
    options.ExistingTypicalDirectory, "metrics.csv"));
existingMetrics.Strategy = string(existingMetrics.Strategy);
legacyVpp = existingMetrics(existingMetrics.Strategy == "VPP_BM", :);
peakGuard = existingMetrics( ...
    existingMetrics.Strategy == "IMPROVED_PEAK_GUARD", :);
if height(legacyVpp) ~= 1 || height(peakGuard) ~= 1 || ...
        string(legacyVpp.Status) ~= "ok" || string(peakGuard.Status) ~= "ok"
    error("StoreNet:InvalidExistingTypicalPeakGuard", ...
        "Existing typical evidence requires one successful VPP and guard row.");
end

manifest = jsondecode(fileread(fullfile( ...
    options.ExistingTypicalDirectory, "manifest.json")));
frozenCapKW = double(vppMetrics.PvSelfNoBatteryBaseline.peakImportKW);
if abs(double(manifest.experiment.improvementCapKW) - frozenCapKW) > 1e-10 || ...
        abs(double(peakGuard.ImportCapKW) - frozenCapKW) > 1e-10 || ...
        double(manifest.experiment.configuration.nHomes) ~= 20 || ...
        nnz(logical(manifest.experiment.configuration.pvHomeMask)) ~= 10 || ...
        abs(double(manifest.experiment.configuration.transferLossFraction) ...
        - 0.07) > 1e-12
    error("StoreNet:ExistingTypicalCapMismatch", ...
        "Existing typical guard does not use the frozen 20/10 PV-self cap.");
end

[metricMaximumDifference, metricCount] = ...
    verifyExistingTypicalVpp(vppMetrics, legacyVpp);
[profileComparison, profileMaximumDifference, pvMaximumDifference] = ...
    verifyAndBuildTypicalProfiles(options, frozenCapKW);

rows = repmat(emptyMetricRow(), 2, 1);
rows(1) = evaluatedMetricRow("StoreNet", datetime(2020, 8, 24), ...
    "VPP_BM", vppMetrics, frozenCapKW, 30, 20, 10, "DC_SOURCE", ...
    0.07, options.FormalTypicalDirectory, true);
rows(1).MinimumExitFlag = minimumExitFlag(evidence.solution);
rows(1).MaximumRelativeMipGap = maximumRelativeMipGap(evidence.solution);
rows(1).StageCount = objectiveStageCount(evidence.solution);
rows(2) = legacyPeakGuardRow(peakGuard, ...
    vppMetrics.PaperLoadOnlyBaseline, frozenCapKW, ...
    options.ExistingTypicalDirectory);
strategyMetrics = struct2table(rows);
pairComparison = make_peak_guard_pair_comparison(strategyMetrics);
summary = summarizePairs(strategyMetrics, pairComparison);
verification = table(metricCount, metricMaximumDifference, ...
    profileMaximumDifference, pvMaximumDifference, ...
    abs(double(manifest.experiment.improvementCapKW) - frozenCapKW), ...
    VariableNames=["ComparedVppMetricCount", ...
    "MaximumVppMetricAbsoluteDifference", ...
    "MaximumVppProfileAbsoluteDifferenceKW", ...
    "MaximumPvAvailableAbsoluteDifferenceKW", ...
    "PeakGuardCapAbsoluteDifferenceKW"]);

outputDirectory = fullfile(options.OutputRoot, "storenet_typical");
prepareOutputDirectory(outputDirectory);
paths = comparisonPaths(outputDirectory);
writeTableAtomic(strategyMetrics, paths.strategyMetrics);
writeTableAtomic(pairComparison, paths.pairComparison);
writeTableAtomic(summary, paths.summary);
writeTableAtomic(profileComparison, fullfile(outputDirectory, ...
    "profile_comparison.csv"));
writeTableAtomic(verification, fullfile(outputDirectory, ...
    "reuse_verification.csv"));

run = struct;
run.mode = "storenet_typical";
run.outputDirectory = outputDirectory;
run.strategyMetrics = strategyMetrics;
run.pairComparison = pairComparison;
run.summary = summary;
run.profileComparison = profileComparison;
run.verification = verification;
run.solverInvoked = false;
end

function formalVpp = selectFormalTypicalVpp(formalMetrics)
required = ["Day", "ScenarioId", "CohortId", "PvBoundaryId", ...
    "TransferLossFraction", "Strategy", "Status", "HouseCount", ...
    "PvHomeCount", "OptimizedBillEUR"];
assertTableVariables(formalMetrics, required, "formal typical metrics");
selected = string(formalMetrics.ScenarioId) == "DC_XI007_H20" & ...
    string(formalMetrics.CohortId) == "H20_PV10" & ...
    string(formalMetrics.PvBoundaryId) == "DC_SOURCE" & ...
    abs(double(formalMetrics.TransferLossFraction) - 0.07) <= 1e-12 & ...
    string(formalMetrics.Strategy) == "VPP_BM" & ...
    string(formalMetrics.Status) == "ok";
formalVpp = formalMetrics(selected, :);
if height(formalVpp) ~= 1 || double(formalVpp.HouseCount) ~= 20 || ...
        double(formalVpp.PvHomeCount) ~= 10
    error("StoreNet:InvalidFormalTypicalVpp", ...
        "Expected one formal 20-home/10-PV DC VPP-BM row.");
end
end

function [maximumDifference, metricCount] = ...
        verifyExistingTypicalVpp(metrics, legacyVpp)
formalValues = [metrics.PvSelfNoBatteryBaseline.billEUR, ...
    metrics.optimizedBillEUR, metrics.PvSelfNoBatteryBaseline.savingsEUR, ...
    metrics.PvSelfNoBatteryBaseline.savingsPercent, ...
    metrics.PvSelfNoBatteryBaseline.peakImportKW, metrics.peakImportKW, ...
    metrics.daytimePeakImportKW, metrics.importSpreadKW, ...
    metrics.totalGridImportKWh, metrics.totalBatteryThroughputKWh, ...
    metrics.totalCurtailedPvKWh, metrics.totalSharedExportKWh, ...
    metrics.energyBalanceResidualKW, metrics.terminalSocErrorKWh, ...
    metrics.simultaneousChargeDischargeKW];
legacyValues = [legacyVpp.BaselineBillEUR, legacyVpp.OptimizedBillEUR, ...
    legacyVpp.SavingsEUR, legacyVpp.SavingsPercent, ...
    legacyVpp.BaselinePeakImportKW, legacyVpp.PeakImportKW, ...
    legacyVpp.DaytimePeakImportKW, legacyVpp.ImportSpreadKW, ...
    legacyVpp.TotalGridImportKWh, legacyVpp.TotalBatteryThroughputKWh, ...
    legacyVpp.TotalCurtailedPvKWh, legacyVpp.TotalSharedExportKWh, ...
    legacyVpp.EnergyBalanceResidualKW, legacyVpp.TerminalSocErrorKWh, ...
    legacyVpp.SimultaneousChargeDischargeKW];
maximumDifference = max(abs(double(formalValues) - double(legacyValues)));
metricCount = numel(formalValues);
if maximumDifference > 1e-10
    error("StoreNet:ExistingTypicalVppMismatch", ...
        "Existing typical VPP metrics differ from the frozen formal artifact.");
end
end

function [profiles, maximumDifference, pvMaximumDifference] = ...
        verifyAndBuildTypicalProfiles(options, frozenCapKW)
formalProfiles = readMetricsTable(options.FormalTypicalProfilesPath);
existingProfiles = readMetricsTable(fullfile( ...
    options.ExistingTypicalDirectory, "profiles.csv"));
assertTableVariables(formalProfiles, ["TimeEnd", "ScenarioId", ...
    "Strategy", "LoadKW", "PvKW", "GridKW"], "formal profiles");
assertTableVariables(existingProfiles, ["Time", "AggregateLoadKW", ...
    "AggregatePvKW", "NoBatteryPvSelfImportKW", ...
    "Import_VPP_BM_KW", "Import_IMPROVED_PEAK_GUARD_KW"], ...
    "existing typical profiles");
formalProfiles.TimeEnd = normalizeTime(formalProfiles.TimeEnd);
existingProfiles.Time = normalizeTime(existingProfiles.Time);
formalVpp = formalProfiles( ...
    string(formalProfiles.ScenarioId) == "DC_XI007_H20" & ...
    string(formalProfiles.Strategy) == "VPP_BM", :);
if height(formalVpp) ~= height(existingProfiles) || ...
        any(formalVpp.TimeEnd ~= existingProfiles.Time)
    error("StoreNet:ExistingTypicalProfileGridMismatch", ...
        "Existing and formal typical VPP profiles are not aligned.");
end
maximumDifference = max(abs(double(formalVpp.GridKW) - ...
    double(existingProfiles.Import_VPP_BM_KW)));
loadDifference = max(abs(double(formalVpp.LoadKW) - ...
    double(existingProfiles.AggregateLoadKW)));
pvMaximumDifference = max(abs(double(formalVpp.PvKW) - ...
    0.95 .* double(existingProfiles.AggregatePvKW)));
if max([maximumDifference, loadDifference, pvMaximumDifference]) > 1e-10
    error("StoreNet:ExistingTypicalProfileMismatch", ...
        "Existing typical profile is not numerically identical to formal VPP.");
end
profiles = table(existingProfiles.Time, ...
    double(existingProfiles.AggregateLoadKW), ...
    0.95 .* double(existingProfiles.AggregatePvKW), ...
    double(existingProfiles.NoBatteryPvSelfImportKW), ...
    double(existingProfiles.Import_VPP_BM_KW), ...
    double(existingProfiles.Import_IMPROVED_PEAK_GUARD_KW), ...
    repmat(frozenCapKW, height(existingProfiles), 1), ...
    VariableNames=["TimeEnd", "AggregateLoadKW", "PvAvailableACKW", ...
    "PvSelfNoBatteryImportKW", "VppImportKW", ...
    "PeakGuardImportKW", "PeakGuardCapKW"]);
end

function row = legacyPeakGuardRow(legacy, paperBaseline, capKW, sourceDirectory)
row = emptyMetricRow();
row.Dataset = "StoreNet";
row.Day = datetime(2020, 8, 24);
row.Sequence = 2;
row.Strategy = "IMPROVED_PEAK_GUARD";
row.Status = "ok";
row.SourceEvidence = sourceDirectory + ...
    "/metrics.csv;/profiles.csv;/manifest.json";
row.ReusedWithoutSolve = true;
row.IntervalMinutes = 30;
row.HouseCount = 20;
row.PvHomeCount = 10;
row.PvBoundaryId = "DC_SOURCE";
row.TransferLossFraction = 0.07;
row.BatteryCapacityKWhPerHome = double(legacy.BatteryCapacityKWh);
row.BatteryPowerKWPerHome = double(legacy.BatteryPowerKW);
row.PeakGuardCapKW = capKW;
row.PaperLoadOnlyBaselineBillEUR = double(paperBaseline.billEUR);
row.PaperSavingsPercent = safeSavingsPercent( ...
    paperBaseline.billEUR, double(legacy.OptimizedBillEUR));
row.PvSelfNoBatteryBaselineBillEUR = double(legacy.BaselineBillEUR);
row.EngineeringSavingsPercent = double(legacy.SavingsPercent);
row.OriginalLoadPeakKW = double(paperBaseline.peakImportKW);
row.PvSelfNoBatteryPeakKW = double(legacy.BaselinePeakImportKW);
row.OptimizedBillEUR = double(legacy.OptimizedBillEUR);
row.AllDayPeakKW = double(legacy.PeakImportKW);
row.DaytimePeakKW = double(legacy.DaytimePeakImportKW);
row.LoadRangeKW = double(legacy.ImportSpreadKW);
row.TotalGridImportKWh = double(legacy.TotalGridImportKWh);
row.BatteryThroughputKWh = double(legacy.TotalBatteryThroughputKWh);
row.PvCurtailmentKWh = double(legacy.TotalCurtailedPvKWh);
row.EnergyBalanceResidualKW = double(legacy.EnergyBalanceResidualKW);
row.TerminalSocErrorKWh = double(legacy.TerminalSocErrorKWh);
row.SimultaneousChargeDischargeKW = ...
    double(legacy.SimultaneousChargeDischargeKW);
row.MinimumExitFlag = double(legacy.MinimumExitFlag);
row.PeakExcessOverCapKW = row.AllDayPeakKW - capKW;
row.CapViolationKW = max(0, row.PeakExcessOverCapKW);
end

function run = compileAusgrid(options)
requiredPaths = [fullfile(options.AusgridResultDirectory, ...
    "primary_metrics.csv"), ...
    fullfile(options.AusgridResultDirectory, "manifest.json"), ...
    fullfile(options.AusgridResultDirectory, "selection.csv"), ...
    fullfile(options.AusgridResultDirectory, "RESULT_MANIFEST.sha256"), ...
    options.AusgridSpecPath];
assertFilesExist(requiredPaths);
primary = readMetricsTable(fullfile(options.AusgridResultDirectory, ...
    "primary_metrics.csv"));
primary.Strategy = string(primary.Strategy);
primary.Status = string(primary.Status);
selected = primary.Experiment == "primary" & ...
    ismember(primary.Strategy, ["VPP_BM", "IMPROVED_PEAK_GUARD"]);
primary = primary(selected, :);
if height(primary) ~= 24 || any(primary.Status ~= "ok")
    error("StoreNet:InvalidAusgridReusePanel", ...
        "Ausgrid reuse requires 24 successful paired primary rows.");
end

manifest = jsondecode(fileread(fullfile( ...
    options.AusgridResultDirectory, "manifest.json")));
config = manifest.experiment.configuration;
if double(config.nHomes) ~= 52 || nnz(logical(config.pvHomeMask)) ~= 52 || ...
        abs(double(config.etaPvAC) - 1) > 1e-12 || ...
        abs(double(config.transferLossFraction) - 0.07) > 1e-12
    error("StoreNet:AusgridConfigurationMismatch", ...
        "Ausgrid no-161 result no longer matches the frozen 52-home policy.");
end
spec = crossenv.loadAusgridSpec(options.AusgridSpecPath);
yearData = crossenv.adapters.readAusgridYear(spec, ...
    SourceFile=string(manifest.experiment.sourceFile), VerifySha256=true);

rows = repmat(emptyMetricRow(), height(primary), 1);
maximumEngineeringBillDifference = 0;
maximumP0Difference = 0;
for rowIndex = 1:height(primary)
    source = primary(rowIndex, :);
    dayIndex = find(yearData.days == source.Day, 1, "first");
    if isempty(dayIndex) || ~logical(yearData.qualityPassed(dayIndex))
        error("StoreNet:AusgridSelectedDayMismatch", ...
            "Ausgrid selected day is absent or rejected: %s", ...
            string(source.Day, "yyyy-MM-dd"));
    end
    loadKW = double(yearData.loadKW(:, :, dayIndex));
    pvKW = double(yearData.pvKW(:, :, dayIndex));
    baselines = ausgridBaselines(source.Day, loadKW, pvKW, config, ...
        double(yearData.dtHours));
    maximumEngineeringBillDifference = max( ...
        maximumEngineeringBillDifference, ...
        abs(baselines.pvSelfBillEUR - double(source.BaselineBillEUR)));
    maximumP0Difference = max(maximumP0Difference, ...
        abs(baselines.pvSelfPeakKW - double(source.P0KW)));
    if maximumEngineeringBillDifference > 1e-9 || ...
            maximumP0Difference > 1e-9
        error("StoreNet:AusgridBaselineMismatch", ...
            "Offline Ausgrid baselines do not match frozen primary metrics.");
    end
    row = emptyMetricRow();
    row.Dataset = "Ausgrid-no-161";
    row.Day = source.Day;
    row.Sequence = double(source.Sequence) - 1;
    row.Strategy = string(source.Strategy);
    row.Status = string(source.Status);
    row.SourceEvidence = options.AusgridResultDirectory + ...
        "/primary_metrics.csv;/manifest.json";
    row.ReusedWithoutSolve = true;
    row.WallTimeSeconds = double(source.WallTimeSeconds);
    row.IntervalMinutes = 30;
    row.HouseCount = 52;
    row.PvHomeCount = 52;
    row.PvBoundaryId = "INVERTER_AC_GROSS";
    row.TransferLossFraction = double(config.transferLossFraction);
    row.BatteryCapacityKWhPerHome = double(config.batteryCapacityKWh);
    row.BatteryPowerKWPerHome = double(config.batteryPowerKW);
    row.PeakGuardCapKW = double(source.P0KW);
    row.PaperLoadOnlyBaselineBillEUR = baselines.paperBillEUR;
    row.PaperSavingsPercent = safeSavingsPercent( ...
        baselines.paperBillEUR, double(source.OptimizedBillEUR));
    row.PvSelfNoBatteryBaselineBillEUR = double(source.BaselineBillEUR);
    row.EngineeringSavingsPercent = double(source.SavingsPercent);
    row.OriginalLoadPeakKW = baselines.paperPeakKW;
    row.PvSelfNoBatteryPeakKW = double(source.P0KW);
    row.OptimizedBillEUR = double(source.OptimizedBillEUR);
    row.AllDayPeakKW = double(source.PeakImportKW);
    row.DaytimePeakKW = double(source.DaytimePeakImportKW);
    row.LoadRangeKW = double(source.ImportSpreadKW);
    row.TotalGridImportKWh = double(source.TotalGridImportKWh);
    row.BatteryThroughputKWh = double(source.TotalBatteryThroughputKWh);
    row.PvCurtailmentKWh = double(source.TotalCurtailedPvKWh);
    row.EnergyBalanceResidualKW = double(source.EnergyBalanceResidualKW);
    row.TerminalSocErrorKWh = double(source.TerminalSocErrorKWh);
    row.SimultaneousChargeDischargeKW = ...
        double(source.SimultaneousChargeDischargeKW);
    row.MinimumExitFlag = double(source.MinimumExitFlag);
    row.PeakExcessOverCapKW = row.AllDayPeakKW - row.PeakGuardCapKW;
    if row.Strategy == "IMPROVED_PEAK_GUARD"
        row.CapViolationKW = max(0, row.PeakExcessOverCapKW);
    end
    rows(rowIndex, 1) = row;
end

strategyMetrics = struct2table(rows);
strategyMetrics = sortrows(strategyMetrics, ["Day", "Sequence"]);
pairComparison = make_peak_guard_pair_comparison(strategyMetrics);
summary = summarizePairs(strategyMetrics, pairComparison);
verification = table(height(pairComparison), ...
    maximumEngineeringBillDifference, maximumP0Difference, ...
    string(yearData.source.sourceSha256), ...
    VariableNames=["PairedDateCount", ...
    "MaximumPvSelfBaselineBillAbsoluteDifference", ...
    "MaximumP0AbsoluteDifferenceKW", "SourceSha256"]);

outputDirectory = fullfile(options.OutputRoot, "ausgrid_no161");
prepareOutputDirectory(outputDirectory);
paths = comparisonPaths(outputDirectory);
writeTableAtomic(strategyMetrics, paths.strategyMetrics);
writeTableAtomic(pairComparison, paths.pairComparison);
writeTableAtomic(summary, paths.summary);
writeTableAtomic(verification, fullfile(outputDirectory, ...
    "reuse_verification.csv"));

run = struct;
run.mode = "ausgrid";
run.outputDirectory = outputDirectory;
run.strategyMetrics = strategyMetrics;
run.pairComparison = pairComparison;
run.summary = summary;
run.verification = verification;
run.solverInvoked = false;
end

function baseline = ausgridBaselines(day, loadKW, pvKW, config, dtHours)
timeEnd = (day + minutes(30):minutes(30):day + days(1)).';
intervalStart = timeEnd - hours(dtHours);
dayMask = hour(intervalStart) >= double(config.dayStartHour) & ...
    hour(intervalStart) < double(config.dayEndHour);
price = repmat(double(config.nightPrice), numel(timeEnd), 1);
price(dayMask) = double(config.dayPrice);
paperImportKW = sum(loadKW, 2);
pvSelfImportKW = sum(loadKW - min(loadKW, ...
    double(config.etaPvAC) .* pvKW), 2);
baseline = struct;
baseline.paperBillEUR = dtHours .* sum(price .* paperImportKW);
baseline.paperPeakKW = max(paperImportKW);
baseline.pvSelfBillEUR = dtHours .* sum(price .* pvSelfImportKW);
baseline.pvSelfPeakKW = max(pvSelfImportKW);
end

function row = evaluatedMetricRow(dataset, day, strategy, metrics, capKW, ...
        intervalMinutes, houseCount, pvHomeCount, boundary, xi, source, reused)
row = emptyMetricRow();
row.Dataset = dataset;
row.Day = day;
row.Sequence = 1;
row.Strategy = strategy;
row.Status = "ok";
row.SourceEvidence = source;
row.ReusedWithoutSolve = reused;
row.IntervalMinutes = intervalMinutes;
row.HouseCount = houseCount;
row.PvHomeCount = pvHomeCount;
row.PvBoundaryId = boundary;
row.TransferLossFraction = xi;
row.BatteryCapacityKWhPerHome = 10;
row.BatteryPowerKWPerHome = 3.3;
row.PeakGuardCapKW = capKW;
row.PaperLoadOnlyBaselineBillEUR = metrics.PaperLoadOnlyBaseline.billEUR;
row.PaperSavingsPercent = metrics.PaperLoadOnlyBaseline.savingsPercent;
row.PvSelfNoBatteryBaselineBillEUR = ...
    metrics.PvSelfNoBatteryBaseline.billEUR;
row.EngineeringSavingsPercent = ...
    metrics.PvSelfNoBatteryBaseline.savingsPercent;
row.OriginalLoadPeakKW = metrics.PaperLoadOnlyBaseline.peakImportKW;
row.PvSelfNoBatteryPeakKW = ...
    metrics.PvSelfNoBatteryBaseline.peakImportKW;
row.OptimizedBillEUR = metrics.optimizedBillEUR;
row.AllDayPeakKW = metrics.peakImportKW;
row.DaytimePeakKW = metrics.daytimePeakImportKW;
row.LoadRangeKW = metrics.importSpreadKW;
row.TotalGridImportKWh = metrics.totalGridImportKWh;
row.BatteryThroughputKWh = metrics.totalBatteryThroughputKWh;
row.PvCurtailmentKWh = metrics.totalCurtailedPvKWh;
row.EnergyBalanceResidualKW = metrics.energyBalanceResidualKW;
row.PvAllocationResidualKW = metrics.pvAllocationResidualKW;
row.HomeBalanceResidualKW = metrics.homeBalanceResidualKW;
row.BatteryDynamicsResidualKW = metrics.batteryDynamicsResidualKW;
row.AggregateImportResidualKW = metrics.aggregateImportResidualKW;
row.ChargeConversionResidualKW = metrics.chargeConversionResidualKW;
row.DischargeConversionResidualKW = metrics.dischargeConversionResidualKW;
row.InitialSocErrorKWh = metrics.initialSocErrorKWh;
row.TerminalSocErrorKWh = metrics.terminalSocErrorKWh;
row.SocBoundViolationKWh = metrics.socBoundViolationKWh;
row.ChargePowerViolationKW = metrics.chargePowerViolationKW;
row.DischargePowerViolationKW = metrics.dischargePowerViolationKW;
row.AggregateImportNonnegativeViolationKW = ...
    metrics.aggregateImportNonnegativeViolationKW;
row.SimultaneousChargeDischargeKW = ...
    metrics.simultaneousChargeDischargeKW;
row.MaximumLexicographicViolation = metrics.maximumLexicographicViolation;
row.PeakExcessOverCapKW = row.AllDayPeakKW - capKW;
end

function value = safeSavingsPercent(baselineBill, optimizedBill)
if abs(baselineBill) <= eps(max(1, abs(baselineBill)))
    value = NaN;
else
    value = 100 .* (baselineBill - optimizedBill) ./ baselineBill;
end
end

function paths = comparisonPaths(directory)
paths = struct;
paths.strategyMetrics = string(fullfile(directory, "strategy_metrics.csv"));
paths.pairComparison = string(fullfile(directory, "paired_comparison.csv"));
paths.summary = string(fullfile(directory, "summary.csv"));
end

function summary = summarizePairs(strategyMetrics, pairs)
vpp = strategyMetrics.Strategy == "VPP_BM" & ...
    strategyMetrics.Status == "ok";
peakGuard = strategyMetrics.Strategy == "IMPROVED_PEAK_GUARD" & ...
    strategyMetrics.Status == "ok";
summary = table(string(pairs.Dataset(1)), height(pairs), ...
    nnz(pairs.VppCreatesNewPeak), nnz(pairs.PeakGuardCapSatisfied), ...
    mean(pairs.PeakReductionKW), median(pairs.PeakReductionKW), ...
    max(pairs.PeakReductionKW), mean(pairs.PeakReductionPercent), ...
    mean(pairs.BillPenaltyEUR), max(abs(pairs.BillPenaltyEUR)), ...
    mean(pairs.PaperSavingsSacrificePercentagePoints), ...
    median(pairs.PaperSavingsSacrificePercentagePoints), ...
    mean(pairs.EngineeringSavingsSacrificePercentagePoints), ...
    median(pairs.EngineeringSavingsSacrificePercentagePoints), ...
    mean(pairs.DaytimePeakChangeKW), mean(pairs.LoadRangeReductionKW), ...
    mean(pairs.GridImportChangeKWh), ...
    mean(pairs.BatteryThroughputChangeKWh), ...
    mean(pairs.PvCurtailmentChangeKWh, "omitmissing"), ...
    max(strategyMetrics.EnergyBalanceResidualKW(vpp), [], "omitnan"), ...
    max(strategyMetrics.EnergyBalanceResidualKW(peakGuard), [], "omitnan"), ...
    max(strategyMetrics.TerminalSocErrorKWh(vpp), [], "omitnan"), ...
    max(strategyMetrics.TerminalSocErrorKWh(peakGuard), [], "omitnan"), ...
    max(strategyMetrics.SimultaneousChargeDischargeKW(vpp), [], "omitnan"), ...
    max(strategyMetrics.SimultaneousChargeDischargeKW(peakGuard), [], ...
        "omitnan"), ...
    VariableNames=["Dataset", "PairedDates", "VppNewPeakDates", ...
    "PeakGuardCapPassDates", "MeanPeakReductionKW", ...
    "MedianPeakReductionKW", "MaximumPeakReductionKW", ...
    "MeanPeakReductionPercent", "MeanBillPenaltyEUR", ...
    "MaximumAbsoluteBillPenaltyEUR", "MeanPaperSavingsSacrificePP", ...
    "MedianPaperSavingsSacrificePP", ...
    "MeanEngineeringSavingsSacrificePP", ...
    "MedianEngineeringSavingsSacrificePP", "MeanDaytimePeakChangeKW", ...
    "MeanLoadRangeReductionKW", "MeanGridImportChangeKWh", ...
    "MeanBatteryThroughputChangeKWh", "MeanPvCurtailmentChangeKWh", ...
    "MaximumVppEnergyBalanceResidualKW", ...
    "MaximumPeakGuardEnergyBalanceResidualKW", ...
    "MaximumVppTerminalSocErrorKWh", ...
    "MaximumPeakGuardTerminalSocErrorKWh", ...
    "MaximumVppSimultaneousChargeDischargeKW", ...
    "MaximumPeakGuardSimultaneousChargeDischargeKW"]);
end

function prepareOutputDirectory(directory)
if ~isfolder(directory)
    mkdir(directory);
end
end

function value = readMetricsTable(path)
value = readtable(path, TextType="string", VariableNamingRule="preserve");
if ismember("Day", string(value.Properties.VariableNames))
    value.Day = normalizeDay(value.Day);
end
end

function days = normalizeDay(values)
if isdatetime(values)
    days = dateshift(values, "start", "day");
    return
end
try
    days = datetime(string(values), InputFormat="dd-MMM-uuuu");
catch
    days = datetime(string(values));
end
days = dateshift(days, "start", "day");
end

function times = normalizeTime(values)
if isdatetime(values)
    times = values;
    return
end
try
    times = datetime(string(values), InputFormat="dd-MMM-uuuu HH:mm:ss");
catch
    times = datetime(string(values));
end
end

function assertFilesExist(paths)
for pathIndex = 1:numel(paths)
    if ~isfile(paths(pathIndex))
        error("StoreNet:MissingPeakGuardReuseInput", ...
            "Required reuse input does not exist: %s", paths(pathIndex));
    end
end
end

function assertTableVariables(value, required, description)
missing = required(~ismember(required, ...
    string(value.Properties.VariableNames)));
if ~isempty(missing)
    error("StoreNet:InvalidPeakGuardReuseTable", ...
        "%s is missing variable(s): %s.", description, ...
        strjoin(missing, ", "));
end
end

function writeTableAtomic(value, path)
[directory, ~, extension] = fileparts(path);
temporaryPath = string(tempname(directory)) + extension;
cleaner = onCleanup(@() deleteIfPresent(temporaryPath));
writetable(value, temporaryPath);
movefile(temporaryPath, path, "f");
clear cleaner
end

function deleteIfPresent(path)
if isfile(path)
    delete(path);
end
end

function flag = minimumExitFlag(solution)
flag = NaN;
if isfield(solution, "exitFlags") && ~isempty(solution.exitFlags)
    flag = min(double(solution.exitFlags(:)));
end
end

function gap = maximumRelativeMipGap(solution)
gap = NaN;
if ~isfield(solution, "solverOutputs") || isempty(solution.solverOutputs)
    return
end
values = nan(numel(solution.solverOutputs), 1);
for outputIndex = 1:numel(solution.solverOutputs)
    output = solution.solverOutputs{outputIndex};
    if isstruct(output) && isfield(output, "relativegap")
        values(outputIndex) = double(output.relativegap);
    elseif isstruct(output) && isfield(output, "relativeGap")
        values(outputIndex) = double(output.relativeGap);
    end
end
gap = max(values, [], "omitnan");
end

function count = objectiveStageCount(solution)
count = NaN;
if isfield(solution, "objectiveStages")
    count = numel(solution.objectiveStages);
end
end

function row = emptyMetricRow()
row = struct( ...
    "Dataset", "", "Day", NaT, "Sequence", NaN, "Strategy", "", ...
    "Status", "", "ErrorIdentifier", "", "ErrorMessage", "", ...
    "SourceEvidence", "", "ReusedWithoutSolve", false, ...
    "WallTimeSeconds", NaN, "IntervalMinutes", NaN, ...
    "HouseCount", NaN, "PvHomeCount", NaN, "PvBoundaryId", "", ...
    "TransferLossFraction", NaN, ...
    "BatteryCapacityKWhPerHome", NaN, ...
    "BatteryPowerKWPerHome", NaN, "PeakGuardCapKW", NaN, ...
    "PaperLoadOnlyBaselineBillEUR", NaN, ...
    "PaperSavingsPercent", NaN, ...
    "PvSelfNoBatteryBaselineBillEUR", NaN, ...
    "EngineeringSavingsPercent", NaN, "OriginalLoadPeakKW", NaN, ...
    "PvSelfNoBatteryPeakKW", NaN, "OptimizedBillEUR", NaN, ...
    "AllDayPeakKW", NaN, "DaytimePeakKW", NaN, "LoadRangeKW", NaN, ...
    "TotalGridImportKWh", NaN, "BatteryThroughputKWh", NaN, ...
    "PvCurtailmentKWh", NaN, "EnergyBalanceResidualKW", NaN, ...
    "PvAllocationResidualKW", NaN, "HomeBalanceResidualKW", NaN, ...
    "BatteryDynamicsResidualKW", NaN, ...
    "AggregateImportResidualKW", NaN, ...
    "ChargeConversionResidualKW", NaN, ...
    "DischargeConversionResidualKW", NaN, "InitialSocErrorKWh", NaN, ...
    "TerminalSocErrorKWh", NaN, "SocBoundViolationKWh", NaN, ...
    "ChargePowerViolationKW", NaN, "DischargePowerViolationKW", NaN, ...
    "AggregateImportNonnegativeViolationKW", NaN, ...
    "SimultaneousChargeDischargeKW", NaN, ...
    "MaximumLexicographicViolation", NaN, "MinimumExitFlag", NaN, ...
    "MaximumRelativeMipGap", NaN, "StageCount", NaN, ...
    "PeakExcessOverCapKW", NaN, "CapViolationKW", NaN, ...
    "ArtifactDirectory", "");
end
