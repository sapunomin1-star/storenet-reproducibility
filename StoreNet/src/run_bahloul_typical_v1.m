function run = run_bahloul_typical_v1(day, options)
%RUN_BAHLOUL_TYPICAL_V1 Run the frozen B2022-IR-v1 typical-day matrix.
%   The output is a StoreNet-public-release structural proxy. It is not the
%   authors' undisclosed dashboard trace or proprietary SB-SC controller.

arguments
    day (1, 1) datetime = datetime(2020, 8, 24)
    options.IntervalMinutes (1, 1) double ...
        {mustBeMember(options.IntervalMinutes, 30)} = 30
    options.QualityMode (1, 1) string {mustBeMember(options.QualityMode, ...
        ["release_literal", "short_gap_only", "exclude_flagged_pv"])} = ...
        "exclude_flagged_pv"
    options.DataRoot (1, 1) string = ""
    options.OutputRoot (1, 1) string = ""
    options.RunId (1, 1) string = ""
    options.ConfigOverrides (1, 1) struct = struct
    options.H4DiagnosticsPath (1, 1) string = ""
    options.ReferenceSavingsFile (1, 1) string = ""
    options.Provenance (1, 1) struct = struct
    options.DataProvider (1, 1) function_handle = @load_storenet_day
    options.Solver (1, 1) function_handle = @solve_storenet
    options.FigureVisible (1, 1) logical = false
    options.PersistSolutions (1, 1) logical = true
end

day = dateshift(day, "start", "day");
sourceFolder = string(fileparts(mfilename("fullpath")));
if strlength(options.OutputRoot) == 0
    options.OutputRoot = fullfile(sourceFolder, "..", "results");
end
if strlength(options.RunId) == 0
    options.RunId = "b2022_typical_" + string(day, "yyyyMMdd") + "_" + ...
        string(datetime("now"), "yyyyMMdd_HHmmss_SSS");
end
if strlength(options.ReferenceSavingsFile) == 0
    options.ReferenceSavingsFile = fullfile(sourceFolder, "..", ...
        "reference", "fig5_savings.csv");
end
runDirectory = prepareRunDirectory(options.OutputRoot, options.RunId);

[data, dataMeta] = callDataProvider(options.DataProvider, day, ...
    options.DataRoot, options.IntervalMinutes, options.QualityMode);
data = normalizeData(data);
enforceQuality(dataMeta, day, options.QualityMode);
baseConfig = storenet_config(IntervalMinutes=options.IntervalMinutes, ...
    DataRoot=options.DataRoot, QualityMode=options.QualityMode);
baseConfig = applyOverrides(baseConfig, options.ConfigOverrides);

allScenarios = bahloul_scenarios("CORE_SIX");
plannedScenarioIds = ["DC_XI007_H20", "DC_XI007_H19", ...
    "AC_XI007_H20", "DC_XI000_H20"];
scenarios = allScenarios(ismember(allScenarios.ScenarioId, ...
    plannedScenarioIds), :);
strategies = ["SH_BM", "VPP_BM", "PS", "PSDT", "LL"];
modelRowCount = numel(strategies) + height(scenarios) - 1;
rows = repmat(emptyMetricRow(), modelRowCount + 2, 1);
rowIndex = 0;
profileTables = cell(numel(strategies) + 1, 1);
profileIndex = 0;
solutions = cell(height(scenarios), numel(strategies));

for scenarioIndex = 1:height(scenarios)
    scenario = scenarios(scenarioIndex, :);
    scenarioStrategies = plannedTypicalStrategies(scenario, strategies);
    try
        [caseData, caseConfig, caseMeta] = prepare_bahloul_case(data, ...
            baseConfig, CohortId=scenario.CohortId, ...
            PvBoundaryId=scenario.PvBoundaryId, ...
            TransferLossFraction=scenario.TransferLossFraction, ...
            H4DiagnosticsPath=options.H4DiagnosticsPath, ...
            DataMeta=dataMeta, Provenance=options.Provenance);
        caseMeta = addScenarioMetadata(caseMeta, scenario, ...
            options.QualityMode, options.RunId);
    catch exception
        for strategy = scenarioStrategies
            rowIndex = rowIndex + 1;
            rows(rowIndex, 1) = failureRow(day, scenario, strategy, ...
                options.QualityMode, exception, 0);
        end
        continue
    end

    for scenarioStrategyIndex = 1:numel(scenarioStrategies)
        strategy = scenarioStrategies(scenarioStrategyIndex);
        strategyIndex = find(strategies == strategy, 1, "first");
        started = tic;
        try
            [solution, metrics] = options.Solver(caseData, caseConfig, strategy);
            wallTimeSeconds = toc(started);
            solutions{scenarioIndex, strategyIndex} = solution;
            artifacts = struct;
            if options.PersistSolutions
                caseDirectory = fullfile(runDirectory, "cases", ...
                    scenario.ScenarioId, strategy);
                artifactMeta = caseMeta;
                artifactMeta.strategy = strategy;
                artifactMeta.caseId = scenario.ScenarioId + "_" + strategy;
                artifacts = write_bahloul_case_artifacts( ...
                    caseDirectory, caseData, ...
                    caseConfig, artifactMeta, solution, metrics);
            end
            rowIndex = rowIndex + 1;
            row = modelMetricRow(day, scenario, strategy, ...
                options.QualityMode, caseMeta, caseConfig, metrics, ...
                solution, wallTimeSeconds);
            row = addModelArtifactEvidence(row, artifacts);
            rows(rowIndex, 1) = row;
            if scenario.IsPrimary
                profileIndex = profileIndex + 1;
                profileTables{profileIndex, 1} = modelProfileTable( ...
                    caseData, caseConfig, scenario, strategy, solution);
            end
        catch exception
            wallTimeSeconds = toc(started);
            rowIndex = rowIndex + 1;
            rows(rowIndex, 1) = failureRow(day, scenario, strategy, ...
                options.QualityMode, exception, wallTimeSeconds);
            if scenario.IsPrimary
                profileIndex = profileIndex + 1;
                profileTables{profileIndex, 1} = failedProfileTable( ...
                    caseData, caseConfig, scenario, strategy);
            end
        end
    end
end

observedScenarios = scenarios(scenarios.PairId == "DC_XI007", :);
observedSolutions = cell(height(observedScenarios), 1);
for observedIndex = 1:height(observedScenarios)
    scenario = observedScenarios(observedIndex, :);
    try
        [caseData, caseConfig, caseMeta] = prepare_bahloul_case(data, ...
            baseConfig, CohortId=scenario.CohortId, ...
            PvBoundaryId="DC_SOURCE", TransferLossFraction=0.07, ...
            H4DiagnosticsPath=options.H4DiagnosticsPath, ...
            DataMeta=dataMeta, Provenance=options.Provenance);
        caseMeta = addScenarioMetadata(caseMeta, scenario, ...
            options.QualityMode, options.RunId);
        [caseData, caseConfig, caseMeta] = prepare_observed_sbsc_case( ...
            caseData, caseConfig, caseMeta);
        started = tic;
        [metrics, profiles] = evaluate_observed_sbsc(caseData, caseConfig);
        wallTimeSeconds = toc(started);
        observedSolutions{observedIndex} = struct("metrics", metrics, ...
            "profiles", profiles);
        artifacts = struct;
        if options.PersistSolutions
            caseDirectory = fullfile(runDirectory, "observed_cases", ...
                scenario.CohortId, "SB_SC");
            artifactMeta = caseMeta;
            artifactMeta.strategy = "SB_SC";
            artifactMeta.caseId = caseMeta.scenarioId + "_SB_SC";
            artifacts = write_bahloul_observed_artifacts( ...
                caseDirectory, caseData, ...
                caseConfig, artifactMeta, metrics, profiles);
        end
        rowIndex = rowIndex + 1;
        row = observedMetricRow(day, scenario, ...
            options.QualityMode, caseMeta, metrics, wallTimeSeconds);
        row = addObservedArtifactEvidence(row, artifacts);
        rows(rowIndex, 1) = row;
        if scenario.CohortId == "H20_PV10"
            profileIndex = profileIndex + 1;
            profileTables{profileIndex, 1} = observedProfileTable( ...
                caseData, caseMeta, profiles);
        end
    catch exception
        rowIndex = rowIndex + 1;
        rows(rowIndex, 1) = failureRow(day, scenario, "SB_SC", ...
            options.QualityMode, exception, 0, "OBSERVED_RELEASE_PROXY");
    end
end

metricsTable = struct2table(rows(1:rowIndex));
profileTables = profileTables(1:profileIndex);
profilesTable = concatenateTables(profileTables, emptyProfileTable());
comparisonTable = makeTargetComparison(metricsTable, ...
    options.ReferenceSavingsFile);

metricsPath = fullfile(runDirectory, "typical_metrics.csv");
profilesPath = fullfile(runDirectory, "figure5_profiles.csv");
comparisonPath = fullfile(runDirectory, ...
    "figure5_target_comparison.csv");
figurePath = fullfile(runDirectory, "figure5_proxy.png");
writetable(metricsTable, metricsPath);
writetable(profilesTable, profilesPath);
writetable(comparisonTable, comparisonPath);
writeFigure5(figurePath, day, profilesTable, comparisonTable, ...
    options.FigureVisible);

run = struct;
run.runType = "B2022_TYPICAL_V1";
run.modelContractId = "B2022-IR-v1";
run.runId = options.RunId;
run.day = day;
run.runDirectory = string(runDirectory);
run.metricsPath = string(metricsPath);
run.profilesPath = string(profilesPath);
run.comparisonPath = string(comparisonPath);
run.figurePath = string(figurePath);
run.metricsTable = metricsTable;
run.profilesTable = profilesTable;
run.comparisonTable = comparisonTable;
run.scenarios = scenarios;
run.solutions = solutions;
run.observedSolutions = observedSolutions;
run.configuration = baseConfig;
run.dataMeta = dataMeta;
end

function strategies = plannedTypicalStrategies(scenario, allStrategies)
if logical(scenario.IsPrimary)
    strategies = allStrategies;
else
    strategies = "VPP_BM";
end
end

function caseMeta = addScenarioMetadata(caseMeta, scenario, qualityMode, runId)
caseMeta.experimentId = "B2022_TYPICAL_V1";
caseMeta.runId = runId;
caseMeta.scenarioId = scenario.ScenarioId;
caseMeta.pairId = scenario.PairId;
caseMeta.sensitivityRole = scenario.SensitivityRole;
caseMeta.qualityMode = qualityMode;
caseMeta.capacityRatio = 1;
caseMeta.powerRatio = 1;
end

function row = modelMetricRow(day, scenario, strategy, qualityMode, ...
        caseMeta, config, metrics, solution, wallTimeSeconds)
row = baseMetricRow(day, scenario, strategy, qualityMode, ...
    "MODEL_STRUCTURAL_PROXY");
row.Status = "ok";
row.WallTimeSeconds = wallTimeSeconds;
row.HouseCount = caseMeta.houseCount;
row.PvHomeCount = caseMeta.pvHomeCount;
row.H4MaskAffected = double(caseMeta.h4MaskAffected);
row.H4AlignmentCategory = caseMeta.h4AlignmentCategory;
row.BatteryCapacityKWhPerHome = double(config.batteryCapacityKWh);
row.BatteryPowerKWPerHome = double(config.batteryPowerKW);
row.PaperLoadOnlyBaselineBillEUR = metrics.PaperLoadOnlyBaseline.billEUR;
row.PaperLoadOnlySavingsEUR = metrics.PaperLoadOnlyBaseline.savingsEUR;
row.PaperLoadOnlySavingsPercent = ...
    metrics.PaperLoadOnlyBaseline.savingsPercent;
row.PaperSavingsPercentDenominatorIsZero = double( ...
    metrics.PaperLoadOnlyBaseline.savingsPercentDenominatorIsZero);
row.OriginalLoadPeakKW = metrics.PaperLoadOnlyBaseline.peakImportKW;
row.OriginalLoadDaytimePeakKW = ...
    metrics.PaperLoadOnlyBaseline.daytimePeakImportKW;
row.PvSelfNoBatteryBaselineBillEUR = ...
    metrics.PvSelfNoBatteryBaseline.billEUR;
row.EngineeringSavingsEUR = metrics.PvSelfNoBatteryBaseline.savingsEUR;
row.EngineeringSavingsPercent = ...
    metrics.PvSelfNoBatteryBaseline.savingsPercent;
row.EngineeringSavingsPercentDenominatorIsZero = double( ...
    metrics.PvSelfNoBatteryBaseline.savingsPercentDenominatorIsZero);
row.PvSelfNoBatteryPeakKW = ...
    metrics.PvSelfNoBatteryBaseline.peakImportKW;
row.OptimizedBillEUR = metrics.optimizedBillEUR;
row.OptimizedPeakImportKW = metrics.peakImportKW;
row.OptimizedDaytimePeakImportKW = metrics.daytimePeakImportKW;
row.OptimizedImportSpreadKW = metrics.importSpreadKW;
row.TotalGridImportKWh = metrics.totalGridImportKWh;
row.TotalBatteryThroughputKWh = metrics.totalBatteryThroughputKWh;
row.TotalCurtailedPvKWh = metrics.totalCurtailedPvKWh;
row.TotalSharedExportKWh = metrics.totalSharedExportKWh;
row.EnergyBalanceResidualKW = metrics.energyBalanceResidualKW;
row.PvAllocationResidualKW = metrics.pvAllocationResidualKW;
row.HomeBalanceResidualKW = metrics.homeBalanceResidualKW;
row.BatteryDynamicsResidualKW = metrics.batteryDynamicsResidualKW;
row.AggregateImportResidualKW = metrics.aggregateImportResidualKW;
row.ChargeConversionResidualKW = metrics.chargeConversionResidualKW;
row.DischargeConversionResidualKW = ...
    metrics.dischargeConversionResidualKW;
row.InitialSocErrorKWh = metrics.initialSocErrorKWh;
row.TerminalSocErrorKWh = metrics.terminalSocErrorKWh;
row.SocBoundViolationKWh = metrics.socBoundViolationKWh;
row.ChargePowerViolationKW = metrics.chargePowerViolationKW;
row.DischargePowerViolationKW = metrics.dischargePowerViolationKW;
row.AggregateImportNonnegativeViolationKW = ...
    metrics.aggregateImportNonnegativeViolationKW;
row.SimultaneousChargeDischargeKW = ...
    metrics.simultaneousChargeDischargeKW;
row.SimultaneousChargeDischargeCount = ...
    metrics.simultaneousChargeDischargeCount;
row.MaximumLexicographicViolation = ...
    metrics.maximumLexicographicViolation;
[row.MinimumExitFlag, row.MaximumRelativeMipGap, row.StageCount] = ...
    stageSummary(solution);
end

function row = observedMetricRow(day, scenario, qualityMode, caseMeta, ...
        metrics, wallTimeSeconds)
row = baseMetricRow(day, scenario, "SB_SC", qualityMode, ...
    "OBSERVED_RELEASE_PROXY");
row.ScenarioId = caseMeta.scenarioId;
row.PairId = caseMeta.pairId;
row.SensitivityRole = caseMeta.sensitivityRole;
row.PvBoundaryId = caseMeta.pvBoundaryId;
row.TransferLossFraction = caseMeta.transferLossFraction;
row.CapacityRatio = caseMeta.capacityRatio;
row.PowerRatio = caseMeta.powerRatio;
row.Status = "ok";
row.WallTimeSeconds = wallTimeSeconds;
row.HouseCount = caseMeta.houseCount;
row.PvHomeCount = caseMeta.pvHomeCount;
row.H4MaskAffected = double(caseMeta.h4MaskAffected);
row.H4AlignmentCategory = caseMeta.h4AlignmentCategory;
row.PaperLoadOnlyBaselineBillEUR = ...
    metrics.paperLoadOnlyBaselineBillEUR;
row.PaperLoadOnlySavingsEUR = metrics.paperLoadOnlySavingsEUR;
row.PaperLoadOnlySavingsPercent = metrics.paperLoadOnlySavingsPercent;
row.PaperSavingsPercentDenominatorIsZero = double( ...
    metrics.paperLoadOnlySavingsPercentDenominatorIsZero);
row.OriginalLoadPeakKW = metrics.paperLoadOnlyPeakKW;
row.OriginalLoadDaytimePeakKW = metrics.paperLoadOnlyDaytimePeakKW;
row.ObservedReleasePvSelfNoBatteryBaselineBillEUR = ...
    metrics.observedReleasePvSelfNoBatteryBaselineBillEUR;
row.ObservedReleaseEngineeringSavingsEUR = ...
    metrics.observedReleaseEngineeringSavingsEUR;
row.ObservedReleaseEngineeringSavingsPercent = ...
    metrics.observedReleaseEngineeringSavingsPercent;
row.ObservedReleaseEngineeringSavingsPercentDenominatorIsZero = double( ...
    metrics.observedReleaseEngineeringSavingsPercentDenominatorIsZero);
row.ObservedBillEUR = metrics.observedBillEUR;
row.ObservedPeakImportKW = metrics.observedPeakImportKW;
row.ObservedDaytimePeakImportKW = metrics.observedDaytimePeakImportKW;
row.ObservedImportSpreadKW = metrics.observedImportSpreadKW;
row.TotalGridImportKWh = metrics.observedGridImportKWh;
row.TotalBatteryThroughputKWh = metrics.releaseBatteryThroughputKWh;
row.TotalFeedInKWh = metrics.totalFeedInKWh;
end

function row = addModelArtifactEvidence(row, artifacts)
if isempty(fieldnames(artifacts))
    return
end
row.InputsPath = artifacts.inputsPath;
row.InputsSha256 = artifacts.inputsSha256;
row.SolutionPath = artifacts.solutionPath;
row.SolutionSha256 = artifacts.solutionSha256;
row.StagesPath = artifacts.stagesPath;
row.MetricsPath = artifacts.metricsPath;
end

function row = addObservedArtifactEvidence(row, artifacts)
if isempty(fieldnames(artifacts))
    return
end
row.InputsPath = artifacts.inputsPath;
row.InputsSha256 = artifacts.inputsSha256;
row.SolutionPath = artifacts.solutionPath;
row.SolutionSha256 = artifacts.solutionSha256;
row.ObservedProfilesPath = artifacts.profilesPath;
row.ObservedProfilesSha256 = artifacts.profilesSha256;
row.MetricsPath = artifacts.metricsPath;
row.MetricsSha256 = artifacts.metricsSha256;
end

function row = failureRow(day, scenario, strategy, qualityMode, exception, ...
        wallTimeSeconds, resultKind)
if nargin < 7
    resultKind = "MODEL_STRUCTURAL_PROXY";
end
row = baseMetricRow(day, scenario, strategy, qualityMode, resultKind);
row.Status = "failed";
row.ErrorIdentifier = string(exception.identifier);
row.ErrorMessage = string(exception.message);
row.WallTimeSeconds = wallTimeSeconds;
if resultKind == "OBSERVED_RELEASE_PROXY"
    row.ScenarioId = "OBSERVED_RELEASE_" + scenario.CohortId;
    row.PairId = "OBSERVED_RELEASE_PAIR";
    row.SensitivityRole = observedSensitivityRole(scenario.CohortId);
    row.PvBoundaryId = "OBSERVED_RELEASE_FIELDS";
    row.TransferLossFraction = NaN;
    row.CapacityRatio = NaN;
    row.PowerRatio = NaN;
end
end

function role = observedSensitivityRole(cohortId)
if string(cohortId) == "H20_PV10"
    role = "OBSERVED_PRIMARY";
else
    role = "OBSERVED_H4_PAIR";
end
end

function row = baseMetricRow(day, scenario, strategy, qualityMode, resultKind)
row = emptyMetricRow();
row.Day = day;
row.ExperimentId = "B2022_TYPICAL_V1";
row.ScenarioId = scenario.ScenarioId;
row.PairId = scenario.PairId;
row.SensitivityRole = scenario.SensitivityRole;
row.CohortId = scenario.CohortId;
row.PvBoundaryId = scenario.PvBoundaryId;
row.TransferLossFraction = scenario.TransferLossFraction;
row.QualityMode = qualityMode;
row.Strategy = strategy;
row.ResultKind = resultKind;
end

function row = emptyMetricRow()
row = struct;
row.Day = NaT;
row.ExperimentId = "";
row.ScenarioId = "";
row.PairId = "";
row.SensitivityRole = "";
row.CohortId = "";
row.HouseCount = NaN;
row.PvHomeCount = NaN;
row.H4MaskAffected = NaN;
row.H4AlignmentCategory = "";
row.PvBoundaryId = "";
row.TransferLossFraction = NaN;
row.QualityMode = "";
row.Strategy = "";
row.ResultKind = "";
row.Status = "";
row.ErrorIdentifier = "";
row.ErrorMessage = "";
row.WallTimeSeconds = NaN;
row.CapacityRatio = 1;
row.PowerRatio = 1;
row.BatteryCapacityKWhPerHome = NaN;
row.BatteryPowerKWPerHome = NaN;
row.PaperLoadOnlyBaselineBillEUR = NaN;
row.PaperLoadOnlySavingsEUR = NaN;
row.PaperLoadOnlySavingsPercent = NaN;
row.PaperSavingsPercentDenominatorIsZero = NaN;
row.OriginalLoadPeakKW = NaN;
row.OriginalLoadDaytimePeakKW = NaN;
row.PvSelfNoBatteryBaselineBillEUR = NaN;
row.EngineeringSavingsEUR = NaN;
row.EngineeringSavingsPercent = NaN;
row.EngineeringSavingsPercentDenominatorIsZero = NaN;
row.PvSelfNoBatteryPeakKW = NaN;
row.OptimizedBillEUR = NaN;
row.OptimizedPeakImportKW = NaN;
row.OptimizedDaytimePeakImportKW = NaN;
row.OptimizedImportSpreadKW = NaN;
row.ObservedReleasePvSelfNoBatteryBaselineBillEUR = NaN;
row.ObservedReleaseEngineeringSavingsEUR = NaN;
row.ObservedReleaseEngineeringSavingsPercent = NaN;
row.ObservedReleaseEngineeringSavingsPercentDenominatorIsZero = NaN;
row.ObservedBillEUR = NaN;
row.ObservedPeakImportKW = NaN;
row.ObservedDaytimePeakImportKW = NaN;
row.ObservedImportSpreadKW = NaN;
row.TotalGridImportKWh = NaN;
row.TotalBatteryThroughputKWh = NaN;
row.TotalCurtailedPvKWh = NaN;
row.TotalSharedExportKWh = NaN;
row.TotalFeedInKWh = NaN;
row.EnergyBalanceResidualKW = NaN;
row.PvAllocationResidualKW = NaN;
row.HomeBalanceResidualKW = NaN;
row.BatteryDynamicsResidualKW = NaN;
row.AggregateImportResidualKW = NaN;
row.ChargeConversionResidualKW = NaN;
row.DischargeConversionResidualKW = NaN;
row.InitialSocErrorKWh = NaN;
row.TerminalSocErrorKWh = NaN;
row.SocBoundViolationKWh = NaN;
row.ChargePowerViolationKW = NaN;
row.DischargePowerViolationKW = NaN;
row.AggregateImportNonnegativeViolationKW = NaN;
row.SimultaneousChargeDischargeKW = NaN;
row.SimultaneousChargeDischargeCount = NaN;
row.MaximumLexicographicViolation = NaN;
row.MinimumExitFlag = NaN;
row.MaximumRelativeMipGap = NaN;
row.StageCount = NaN;
row.InputsPath = "";
row.InputsSha256 = "";
row.SolutionPath = "";
row.SolutionSha256 = "";
row.StagesPath = "";
row.MetricsPath = "";
row.MetricsSha256 = "";
row.ObservedProfilesPath = "";
row.ObservedProfilesSha256 = "";
end

function [minimumExitFlag, maximumGap, stageCount] = stageSummary(solution)
minimumExitFlag = NaN;
maximumGap = NaN;
stageCount = 0;
if isfield(solution, "objectiveStages") && ~isempty(solution.objectiveStages)
    stages = solution.objectiveStages(:);
    stageCount = numel(stages);
    minimumExitFlag = min(double([stages.exitFlag]));
    maximumGap = max(double([stages.relativeGap]));
elseif isfield(solution, "exitFlags") && ~isempty(solution.exitFlags)
    minimumExitFlag = min(double(solution.exitFlags));
end
end

function profiles = modelProfileTable(data, config, scenario, strategy, solution)
timeEnd = data.time(:);
profiles = profileIdentityTable(timeEnd, scenario.ScenarioId, ...
    scenario.CohortId, scenario.PvBoundaryId, ...
    scenario.TransferLossFraction, strategy, "STRUCTURAL_PROXY", ...
    double(data.dtHours));
profiles.LoadKW = sum(double(data.loadKW), 2);
profiles.PvKW = config.etaPvAC .* sum(double(data.pvKW), 2);
profiles.GridKW = double(solution.aggregateImportKW(:));
profiles.BatteryKW = sum(double(solution.batteryDischargeKW) - ...
    double(solution.batteryChargeKW), 2);
profiles.FeedInKW = nan(height(profiles), 1);
end

function profiles = failedProfileTable(data, config, scenario, strategy)
profiles = profileIdentityTable(data.time(:), scenario.ScenarioId, ...
    scenario.CohortId, scenario.PvBoundaryId, ...
    scenario.TransferLossFraction, strategy, "FAILED_MODEL", ...
    double(data.dtHours));
profiles.LoadKW = sum(double(data.loadKW), 2);
profiles.PvKW = config.etaPvAC .* sum(double(data.pvKW), 2);
end

function output = observedProfileTable(data, caseMeta, observed)
output = profileIdentityTable(observed.TimeEnd, ...
    caseMeta.scenarioId, caseMeta.cohortId, ...
    caseMeta.pvBoundaryId, caseMeta.transferLossFraction, "SB_SC", ...
    "OBSERVED_RELEASE_PROXY", double(data.dtHours));
output.LoadKW = observed.LoadKW;
output.PvKW = observed.ObservedReleasedPvKW;
output.GridKW = observed.GridImportKW;
output.BatteryKW = observed.ReleaseBatterySignedKW;
output.FeedInKW = observed.FeedInKW;
end

function profiles = profileIdentityTable(timeEnd, scenarioId, cohortId, ...
        pvBoundaryId, xi, strategy, profileKind, dtHours)
n = numel(timeEnd);
profiles = table(timeEnd(:), timeEnd(:) - hours(dtHours), ...
    repmat(string(scenarioId), n, 1), repmat(string(cohortId), n, 1), ...
    repmat(string(pvBoundaryId), n, 1), repmat(double(xi), n, 1), ...
    repmat(string(strategy), n, 1), repmat(string(profileKind), n, 1), ...
    nan(n, 1), nan(n, 1), nan(n, 1), nan(n, 1), nan(n, 1), ...
    VariableNames=["TimeEnd", "IntervalStart", "ScenarioId", ...
    "CohortId", "PvBoundaryId", "TransferLossFraction", ...
    "Strategy", "ProfileKind", "LoadKW", "PvKW", "GridKW", ...
    "BatteryKW", "FeedInKW"]);
end

function profiles = emptyProfileTable()
profiles = profileIdentityTable(NaT(0, 1), "", "", "", NaN, "", ...
    "", 0.5);
end

function output = concatenateTables(tables, emptyValue)
if isempty(tables)
    output = emptyValue;
else
    output = vertcat(tables{:});
end
end

function comparison = makeTargetComparison(metrics, referencePath)
if ~isfile(referencePath)
    error("StoreNet:MissingBahloulReference", ...
        "Figure 5 reference is missing: %s", referencePath);
end
reference = readtable(referencePath, TextType="string", ...
    VariableNamingRule="preserve");
strategy = string(reference.strategy);
paperPrintedSavingsPercent = double(reference.savings_percent);
sourceNote = string(reference.source_note);
localPaperLoadOnlySavingsPercent = nan(height(reference), 1);
localStatus = repmat("missing", height(reference), 1);
for rowIndex = 1:height(reference)
    selected = metrics.Strategy == strategy(rowIndex) & ...
        metrics.CohortId == "H20_PV10" & ...
        ((metrics.ScenarioId == "DC_XI007_H20") | ...
        (metrics.ScenarioId == "OBSERVED_RELEASE_H20_PV10"));
    if nnz(selected) == 1
        localPaperLoadOnlySavingsPercent(rowIndex) = ...
            metrics.PaperLoadOnlySavingsPercent(selected);
        localStatus(rowIndex) = metrics.Status(selected);
    end
end
differencePercentagePoints = localPaperLoadOnlySavingsPercent - ...
    paperPrintedSavingsPercent;
comparison = table(strategy, paperPrintedSavingsPercent, ...
    localPaperLoadOnlySavingsPercent, differencePercentagePoints, ...
    localStatus, sourceNote, VariableNames=["Strategy", ...
    "PaperPrintedSavingsPercent", "LocalPaperLoadOnlySavingsPercent", ...
    "DifferencePercentagePoints", "LocalStatus", "SourceNote"]);
end

function writeFigure5(path, day, profiles, comparison, visible)
visibility = "off";
if visible
    visibility = "on";
end
strategies = ["SH_BM", "VPP_BM", "PS", "PSDT", "LL", "SB_SC"];
figureHandle = figure(Visible=visibility, Color="w", ...
    Position=[100, 100, 1500, 1050]);
cleaner = onCleanup(@() close(figureHandle));
layout = tiledlayout(figureHandle, 3, 2, Padding="compact", ...
    TileSpacing="compact");
for strategyIndex = 1:numel(strategies)
    strategy = strategies(strategyIndex);
    axesHandle = nexttile(layout);
    selected = profiles.Strategy == strategy;
    if any(selected)
        subset = profiles(selected, :);
        plot(axesHandle, subset.TimeEnd, subset.LoadKW, LineWidth=1.4, ...
            DisplayName="Load");
        hold(axesHandle, "on");
        plot(axesHandle, subset.TimeEnd, subset.PvKW, LineWidth=1.4, ...
            DisplayName="PV");
        plot(axesHandle, subset.TimeEnd, subset.GridKW, LineWidth=1.4, ...
            DisplayName="Grid import");
        plot(axesHandle, subset.TimeEnd, subset.BatteryKW, LineWidth=1.2, ...
            DisplayName="Battery (+ discharge)");
        hold(axesHandle, "off");
    end
    grid(axesHandle, "on");
    ylabel(axesHandle, "Power (kW)");
    targetRow = comparison.Strategy == strategy;
    local = NaN;
    target = NaN;
    if any(targetRow)
        local = comparison.LocalPaperLoadOnlySavingsPercent(targetRow);
        target = comparison.PaperPrintedSavingsPercent(targetRow);
    end
    title(axesHandle, sprintf("%s | local %.2f%%, paper %.2f%%", ...
        strategy, local, target), Interpreter="none");
    if strategyIndex == 1
        legend(axesHandle, Location="best");
    end
end
title(layout, "B2022 Figure 5 structural/observed proxies: " + ...
    string(day, "yyyy-MM-dd") + " (not an exact dashboard trace)");
exportgraphics(figureHandle, path, Resolution=220, BackgroundColor="white");
end

function directory = prepareRunDirectory(outputRoot, runId)
if any(contains(runId, ["/", "\\"])) || contains(runId, "..")
    error("StoreNet:InvalidRunId", ...
        "RunId must be a simple directory name without separators or '..'.");
end
if ~isfolder(outputRoot)
    mkdir(outputRoot);
end
directory = string(fullfile(outputRoot, runId));
if isfolder(directory) && hasMaterialEntries(directory)
    error("StoreNet:RunDirectoryExists", ...
        "Refusing to overwrite nonempty run directory: %s", directory);
end
if ~isfolder(directory)
    mkdir(directory);
end
end

function tf = hasMaterialEntries(directory)
entries = dir(directory);
names = string({entries.name});
tf = any(~ismember(names, [".", ".."]) & ~startsWith(names, ".nfs"));
end

function [data, meta] = callDataProvider(provider, day, dataRoot, ...
        intervalMinutes, qualityMode)
[data, meta] = provider(day, DataRoot=dataRoot, ...
    IntervalMinutes=intervalMinutes, QualityMode=qualityMode);
end

function enforceQuality(meta, day, qualityMode)
if isfield(meta, "qualityPassed") && ~logical(meta.qualityPassed)
    reasons = "quality contract returned false";
    if isfield(meta, "qualityReasons") && ~isempty(meta.qualityReasons)
        reasons = strjoin(string(meta.qualityReasons), "; ");
    end
    error("StoreNet:QualityRejected", "Day %s fails %s: %s.", ...
        string(day, "yyyy-MM-dd"), qualityMode, reasons);
end
end

function data = normalizeData(data)
if ~isfield(data, "time") && isfield(data, "timeEnd")
    data.time = data.timeEnd;
end
if ~isfield(data, "houseIds") && isfield(data, "homeNames")
    data.houseIds = data.homeNames;
end
required = ["time", "loadKW", "pvKW", "dtHours", "houseIds"];
missing = required(~isfield(data, cellstr(required)));
if ~isempty(missing)
    error("StoreNet:InvalidExperimentData", ...
        "Data provider output is missing field(s): %s.", ...
        strjoin(missing, ", "));
end
data.time = data.time(:);
end

function config = applyOverrides(config, overrides)
fields = string(fieldnames(overrides));
for fieldIndex = 1:numel(fields)
    field = fields(fieldIndex);
    config.(field) = overrides.(field);
end
end
