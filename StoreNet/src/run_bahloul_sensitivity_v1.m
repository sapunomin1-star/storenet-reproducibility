function run = run_bahloul_sensitivity_v1(day, options)
%RUN_BAHLOUL_SENSITIVITY_V1 Run frozen Figure 7 and Table I experiments.
%   Figure 7 uses the preregistered 0.2:0.1:1.0 capacity/power grid for
%   VPP_BM in the primary H20_PV10 scenario. Table I evaluates nominal,
%   20%-power, and 20%-capacity budgets for five primary-scenario strategies.

arguments
    day (1, 1) datetime = datetime(2020, 8, 24)
    options.QualityMode (1, 1) string {mustBeMember(options.QualityMode, ...
        ["release_literal", "short_gap_only", "exclude_flagged_pv"])} = ...
        "exclude_flagged_pv"
    options.DataRoot (1, 1) string = ""
    options.OutputRoot (1, 1) string = ""
    options.RunId (1, 1) string = ""
    options.H4DiagnosticsPath (1, 1) string = ""
    options.TableIReferenceFile (1, 1) string = ""
    options.ReuseFigure7Csv (1, 1) string = ""
    options.ConfigOverrides (1, 1) struct = struct
    options.Provenance (1, 1) struct = struct
    options.DataProvider (1, 1) function_handle = @load_storenet_day
    options.Solver (1, 1) function_handle = @solve_storenet
    options.FigureVisible (1, 1) logical = false
end

day = dateshift(day, "start", "day");
sourceFolder = fileparts(mfilename("fullpath"));
if strlength(options.OutputRoot) == 0
    options.OutputRoot = string(fullfile(sourceFolder, "..", "results"));
end
if strlength(options.RunId) == 0
    options.RunId = "bahloul_sensitivity_v1_" + ...
        string(day, "yyyyMMdd") + "_" + ...
        string(datetime("now"), "yyyyMMdd_HHmmss_SSS");
end
if strlength(options.TableIReferenceFile) == 0
    options.TableIReferenceFile = string(fullfile(sourceFolder, "..", ...
        "reference", "table_i.csv"));
end

tableITargets = readTableITargets(options.TableIReferenceFile);
runDirectory = prepareRunDirectory(options.OutputRoot, options.RunId);
longPath = fullfile(runDirectory, "bahloul_sensitivity_long.csv");
tableIPath = fullfile(runDirectory, "table_i_target_vs_local.csv");
figure7Path = fullfile(runDirectory, "figure7_primary_h4_surface.png");
figure7TrendPath = fullfile(runDirectory, "figure7_trend_summary.csv");

capacityRatios = (2:10) ./ 10;
powerRatios = (2:10) ./ 10;
caseSpecifications = [buildFigureSevenCases(capacityRatios, powerRatios); ...
    buildTableICases()];

nominalConfig = storenet_config(IntervalMinutes=30, ...
    DataRoot=options.DataRoot, QualityMode=options.QualityMode);
nominalConfig = applyOverrides(nominalConfig, options.ConfigOverrides);
nominalCapacityKWh = double(nominalConfig.batteryCapacityKWh);
nominalPowerKW = double(nominalConfig.batteryPowerKW);
[baseData, dataMeta, dataStatus, dataIdentifier, dataMessage] = ...
    loadExperimentData(options.DataProvider, day, options.DataRoot, ...
    options.QualityMode);
[reusableFigureSeven, reusableBaselines] = loadLegacyFigureSevenRows( ...
    options.ReuseFigure7Csv, day, nominalConfig, ...
    options.QualityMode, options.ConfigOverrides, baseData, dataStatus);

rows = repmat(emptyResultRow(), height(caseSpecifications), 1);
for caseIndex = 1:height(caseSpecifications)
    specification = caseSpecifications(caseIndex, :);
    row = resultRowFromSpecification(specification, day, ...
        options.QualityMode, runDirectory);
    if specification.ExperimentId == "FIGURE_7"
        row.CaseDirectory = "";
    end
    if dataStatus ~= "ok"
        row.Status = dataStatus;
        row.ErrorIdentifier = dataIdentifier;
        row.ErrorMessage = dataMessage;
        rows(caseIndex) = row;
        writeSensitivityCheckpoint(rows, caseIndex, longPath);
        continue
    end

    started = tic;
    try
        config = nominalConfig;
        config.batteryCapacityKWh = nominalCapacityKWh .* ...
            specification.CapacityRatio;
        config.batteryPowerKW = nominalPowerKW .* ...
            specification.PowerRatio;
        config.capacityRatio = specification.CapacityRatio;
        config.powerRatio = specification.PowerRatio;
        config.scenarioId = specification.ScenarioId;
        config.pairId = specification.PairId;

        [caseData, caseConfig, caseMeta] = prepare_bahloul_case( ...
            baseData, config, CohortId=specification.CohortId, ...
            PvBoundaryId=specification.PvBoundaryId, ...
            TransferLossFraction=specification.TransferLossFraction, ...
            H4DiagnosticsPath=options.H4DiagnosticsPath, ...
            DataMeta=dataMeta, Provenance=options.Provenance);
        caseMeta = enrichCaseMeta(caseMeta, specification, day, ...
            options.QualityMode);
        row = addPreparedCase(row, caseConfig, caseMeta);

        [row, reused] = applyLegacyFigureSevenRow(row, specification, ...
            reusableFigureSeven, reusableBaselines);
        if reused
            rows(caseIndex) = row;
            writeSensitivityCheckpoint(rows, caseIndex, longPath);
            continue
        end

        [solution, metrics] = options.Solver( ...
            caseData, caseConfig, specification.Strategy);
        row = addSuccessfulMetrics(row, metrics, solution);
        if specification.ExperimentId == "TABLE_I"
            artifacts = write_bahloul_case_artifacts(row.CaseDirectory, ...
                caseData, caseConfig, caseMeta, solution, metrics);
            row = addArtifactPaths(row, artifacts);
        end
        row.Status = "ok";
    catch exception
        row.Status = "failed";
        row.ErrorIdentifier = string(exception.identifier);
        row.ErrorMessage = string(exception.message);
    end
    row.WallTimeSeconds = toc(started);
    rows(caseIndex) = row;
    writeSensitivityCheckpoint(rows, caseIndex, longPath);
end

longTable = struct2table(rows);
tableIComparison = buildTableIComparison(longTable, tableITargets);
figure7Trend = buildFigureSevenTrend(longTable, capacityRatios, powerRatios);
writeSensitivityCheckpoint(rows, height(caseSpecifications), longPath);
writetable(tableIComparison, tableIPath);
writetable(figure7Trend, figure7TrendPath);
writeFigureSevenSurface(figure7Path, longTable, capacityRatios, ...
    powerRatios, options.FigureVisible);

run = struct;
run.day = day;
run.runDirectory = runDirectory;
run.longPath = string(longPath);
run.tableIPath = string(tableIPath);
run.figure7Path = string(figure7Path);
run.figure7TrendPath = string(figure7TrendPath);
run.longTable = longTable;
run.tableIComparison = tableIComparison;
run.figure7Trend = figure7Trend;
run.figure7CapacityRatios = capacityRatios;
run.figure7PowerRatios = powerRatios;
run.dataMeta = dataMeta;
end

function trend = buildFigureSevenTrend(longTable, capacityRatios, powerRatios)
roles = "PRIMARY";
rows = repmat(struct("SensitivityRole", "", ...
    "PaperClaimCapacityMoreInfluentialThanPower", true, ...
    "PaperMentionedCapacityRegion", "0.7--0.8", ...
    "PaperMentionedPowerRegion", "0.2--0.3", ...
    "LocalMeanCapacityRangePercentagePoints", NaN, ...
    "LocalMeanPowerRangePercentagePoints", NaN, ...
    "LocalSupportsCapacityInfluenceClaim", false, ...
    "LocalMaximumCapacityRatio", NaN, ...
    "LocalMaximumPowerRatio", NaN, ...
    "LocalMaximumPaperLoadOnlySavingsPercent", NaN, ...
    "LocalMeanSavingsInPaperMentionedRegionPercent", NaN, ...
    "LocalMaximumInsidePaperMentionedRegion", false), numel(roles), 1);
figureRows = longTable(longTable.ExperimentId == "FIGURE_7", :);
for roleIndex = 1:numel(roles)
    values = surfaceMatrix(figureRows, roles(roleIndex), ...
        capacityRatios, powerRatios);
    rows(roleIndex).SensitivityRole = roles(roleIndex);
    if any(isfinite(values), "all")
        capacityRanges = max(values, [], 1, "omitnan") - ...
            min(values, [], 1, "omitnan");
        powerRanges = max(values, [], 2, "omitnan") - ...
            min(values, [], 2, "omitnan");
        rows(roleIndex).LocalMeanCapacityRangePercentagePoints = ...
            mean(capacityRanges, "omitnan");
        rows(roleIndex).LocalMeanPowerRangePercentagePoints = ...
            mean(powerRanges, "omitnan");
        rows(roleIndex).LocalSupportsCapacityInfluenceClaim = ...
            rows(roleIndex).LocalMeanCapacityRangePercentagePoints > ...
            rows(roleIndex).LocalMeanPowerRangePercentagePoints;
        [maximumSaving, linearIndex] = max(values, [], "all", ...
            "linear", "omitnan");
        [capacityIndex, powerIndex] = ind2sub(size(values), linearIndex);
        rows(roleIndex).LocalMaximumCapacityRatio = ...
            capacityRatios(capacityIndex);
        rows(roleIndex).LocalMaximumPowerRatio = powerRatios(powerIndex);
        rows(roleIndex).LocalMaximumPaperLoadOnlySavingsPercent = ...
            maximumSaving;
        regionCapacity = capacityRatios >= 0.7 & capacityRatios <= 0.8;
        regionPower = powerRatios >= 0.2 & powerRatios <= 0.3;
        regionValues = values(regionCapacity, regionPower);
        rows(roleIndex).LocalMeanSavingsInPaperMentionedRegionPercent = ...
            mean(regionValues, "all", "omitnan");
        rows(roleIndex).LocalMaximumInsidePaperMentionedRegion = ...
            regionCapacity(capacityIndex) && regionPower(powerIndex);
    end
end
trend = struct2table(rows);
end

function specifications = buildFigureSevenCases(capacityRatios, powerRatios)
scenarios = primaryScenario();
[capacityIndex, powerIndex, scenarioIndex] = ndgrid( ...
    1:numel(capacityRatios), 1:numel(powerRatios), 1:height(scenarios));
capacityRatio = reshape(capacityRatios(capacityIndex(:)), [], 1);
powerRatio = reshape(powerRatios(powerIndex(:)), [], 1);
scenarioIndex = scenarioIndex(:);
caseId = compose("figure7_c%03d_p%03d_%s_VPP_BM", ...
    round(100 .* capacityRatio), round(100 .* powerRatio), ...
    scenarios.ScenarioId(scenarioIndex));
specifications = specificationTable("FIGURE_7", caseId, "GRID", ...
    repmat("VPP_BM", numel(caseId), 1), capacityRatio, powerRatio, ...
    scenarios, scenarioIndex);
end

function specifications = buildTableICases()
scenarios = primaryScenario();
budgetId = ["NOMINAL"; "POWER_20"; "CAPACITY_20"];
capacityRatios = [1; 1; 0.2];
powerRatios = [1; 0.2; 1];
strategies = ["SH_BM"; "VPP_BM"; "PS"; "PSDT"; "LL"];
[budgetIndex, strategyIndex, scenarioIndex] = ndgrid( ...
    1:numel(budgetId), 1:numel(strategies), 1:height(scenarios));
budgetIndex = budgetIndex(:);
strategyIndex = strategyIndex(:);
scenarioIndex = scenarioIndex(:);
selectedBudget = budgetId(budgetIndex);
selectedStrategy = strategies(strategyIndex);
capacityRatio = capacityRatios(budgetIndex);
powerRatio = powerRatios(budgetIndex);
caseId = compose("tablei_%s_%s_%s", lower(selectedBudget), ...
    scenarios.ScenarioId(scenarioIndex), selectedStrategy);
specifications = specificationTable("TABLE_I", caseId, selectedBudget, ...
    selectedStrategy, capacityRatio, powerRatio, scenarios, scenarioIndex);
end

function scenario = primaryScenario()
scenarios = bahloul_scenarios("CORE_SIX");
scenario = scenarios(scenarios.ScenarioId == "DC_XI007_H20", :);
if height(scenario) ~= 1
    error("StoreNet:InvalidPrimaryScenario", ...
        "Expected exactly one DC_XI007_H20 primary scenario.");
end
end

function [reusable, baselines] = loadLegacyFigureSevenRows(path, day, ...
        nominalConfig, qualityMode, configOverrides, ...
        baseData, dataStatus)
reusable = table;
baselines = struct;
if strlength(path) == 0
    return
end
if ~isempty(fieldnames(configOverrides))
    error("StoreNet:UnsafeFigure7Reuse", ...
        "Figure 7 reuse is disabled when ConfigOverrides are present.");
end
if ~ismember(qualityMode, ["exclude_flagged_pv", "release_literal"])
    error("StoreNet:UnsafeFigure7Reuse", ...
        "The fixed legacy Figure 7 CSV requires release_literal or exclude_flagged_pv.");
end
if dataStatus ~= "ok"
    error("StoreNet:UnavailableFigure7ReuseData", ...
        "Current base data must pass before legacy Figure 7 rows are reused.");
end
if ~isfile(path)
    error("StoreNet:MissingFigure7ReuseCsv", ...
        "Figure 7 reuse CSV is missing: %s", path);
end

reusable = readtable(path, TextType="string", ...
    VariableNamingRule="preserve");
required = ["Day", "CapacityRatio", "PowerRatio", "Status", ...
    "WallTimeSeconds", "BatteryCapacityKWh", "BatteryPowerKW", ...
    "BaselineBillEUR", "OptimizedBillEUR", "BaselinePeakImportKW", ...
    "PeakImportKW", "DaytimePeakImportKW", "ImportSpreadKW", ...
    "TotalGridImportKWh", "TotalBatteryThroughputKWh", ...
    "EnergyBalanceResidualKW", "TerminalSocErrorKWh", ...
    "SimultaneousChargeDischargeKW", "MinimumExitFlag"];
missing = required(~ismember(required, ...
    string(reusable.Properties.VariableNames)));
if ~isempty(missing)
    error("StoreNet:InvalidFigure7ReuseCsv", ...
        "Legacy Figure 7 CSV is missing column(s): %s", ...
        strjoin(missing, ", "));
end
if any(string(reusable.Status) ~= "ok")
    error("StoreNet:InvalidFigure7ReuseStatus", ...
        "Only successful legacy Figure 7 cells can be reused.");
end
reuseDays = parseReuseDays(reusable.Day);
if any(reuseDays ~= day)
    error("StoreNet:Figure7ReuseIdentityMismatch", ...
        "Legacy Figure 7 rows must all match the requested day.");
end

capacityRatio = double(reusable.CapacityRatio);
powerRatio = double(reusable.PowerRatio);
legacyRatios = (2:2:10) ./ 10;
keys = unique(reusable(:, ["CapacityRatio", "PowerRatio"]), "rows");
if height(reusable) ~= 25 || height(keys) ~= 25 || ...
        ~all(ismembertol(capacityRatio, legacyRatios, 1e-12)) || ...
        ~all(ismembertol(powerRatio, legacyRatios, 1e-12))
    error("StoreNet:InvalidFigure7ReuseGrid", ...
        "Legacy Figure 7 reuse must be the fixed 5-by-5 ratio subset.");
end
expectedCapacity = double(nominalConfig.batteryCapacityKWh) .* capacityRatio;
expectedPower = double(nominalConfig.batteryPowerKW) .* powerRatio;
if any(abs(double(reusable.BatteryCapacityKWh) - expectedCapacity) > 1e-10) || ...
        any(abs(double(reusable.BatteryPowerKW) - expectedPower) > 1e-10)
    error("StoreNet:Figure7ReuseIdentityMismatch", ...
        "Legacy ratings do not match the current nominal configuration.");
end
numericEvidence = [double(reusable.BaselineBillEUR), ...
    double(reusable.OptimizedBillEUR), double(reusable.BaselinePeakImportKW), ...
    double(reusable.PeakImportKW), double(reusable.DaytimePeakImportKW), ...
    double(reusable.ImportSpreadKW), double(reusable.TotalGridImportKWh), ...
    double(reusable.TotalBatteryThroughputKWh), ...
    double(reusable.EnergyBalanceResidualKW), ...
    double(reusable.TerminalSocErrorKWh), ...
    double(reusable.SimultaneousChargeDischargeKW), ...
    double(reusable.MinimumExitFlag), double(reusable.WallTimeSeconds), ...
    double(reusable.BatteryCapacityKWh), ...
    double(reusable.BatteryPowerKW)];
if any(~isfinite(numericEvidence), "all")
    error("StoreNet:InvalidFigure7ReuseMetrics", ...
        "Every mapped legacy Figure 7 metric must be finite.");
end
residualEvidence = [double(reusable.EnergyBalanceResidualKW), ...
    double(reusable.TerminalSocErrorKWh), ...
    double(reusable.SimultaneousChargeDischargeKW)];
if any(double(reusable.MinimumExitFlag) <= 0) || ...
        any(abs(residualEvidence) > double(nominalConfig.constraintTolerance), ...
        "all") || any(double(reusable.WallTimeSeconds) < 0) || ...
        any(double(reusable.OptimizedBillEUR) < 0) || ...
        any(double(reusable.PeakImportKW) < 0) || ...
        any(double(reusable.DaytimePeakImportKW) < 0) || ...
        any(double(reusable.ImportSpreadKW) < 0) || ...
        any(double(reusable.TotalGridImportKWh) < 0) || ...
        any(double(reusable.TotalBatteryThroughputKWh) < 0)
    error("StoreNet:InvalidFigure7ReuseMetrics", ...
        "Legacy Figure 7 cells must be converged, physical, and within tolerance.");
end

baselines = recomputeReuseBaselines(baseData, nominalConfig);
if any(abs(double(reusable.BaselineBillEUR) - ...
        baselines.PvSelfNoBatteryBillEUR) > 1e-8) || ...
        any(abs(double(reusable.BaselinePeakImportKW) - ...
        baselines.PvSelfNoBatteryPeakKW) > 1e-8)
    error("StoreNet:Figure7ReuseIdentityMismatch", ...
        "Legacy PV-self baseline does not match the current base data.");
end
end

function days = parseReuseDays(values)
if isdatetime(values)
    days = dateshift(values, "start", "day");
else
    try
        days = dateshift(datetime(string(values), Locale="en_US"), ...
            "start", "day");
    catch exception
        error("StoreNet:InvalidFigure7ReuseDay", ...
            "Cannot parse legacy Figure 7 Day values: %s", exception.message);
    end
end
if any(isnat(days))
    error("StoreNet:InvalidFigure7ReuseDay", ...
        "Legacy Figure 7 Day values must be finite dates.");
end
end

function baselines = recomputeReuseBaselines(data, config)
loadKW = double(data.loadKW);
pvKW = double(data.pvKW);
timeEnd = data.time(:);
dtHours = double(data.dtHours);
if ~isscalar(dtHours) || ~isfinite(dtHours) || dtHours <= 0 || ...
        size(loadKW, 1) ~= numel(timeEnd) || ...
        ~isequal(size(loadKW), size(pvKW)) || ...
        any(~isfinite(loadKW), "all") || any(~isfinite(pvKW), "all")
    error("StoreNet:InvalidFigure7ReuseData", ...
        "Current load/PV data cannot support offline baseline recomputation.");
end
intervalStart = timeEnd - hours(dtHours);
dayMask = hour(intervalStart) >= config.dayStartHour & ...
    hour(intervalStart) < config.dayEndHour;
if ~any(dayMask)
    error("StoreNet:InvalidFigure7ReuseData", ...
        "Current base data has no configured daytime interval.");
end
pricePerKWh = repmat(double(config.nightPrice), numel(timeEnd), 1);
pricePerKWh(dayMask) = double(config.dayPrice);
paperImportKW = sum(loadKW, 2);
pvSelfImportKW = sum(loadKW - min(loadKW, ...
    double(config.etaPvAC) .* pvKW), 2);

baselines = struct;
baselines.PaperLoadOnlyBillEUR = ...
    dtHours .* sum(pricePerKWh .* paperImportKW);
baselines.PaperLoadOnlyPeakKW = max(paperImportKW);
baselines.PaperLoadOnlyDaytimePeakKW = max(paperImportKW(dayMask));
baselines.PvSelfNoBatteryBillEUR = ...
    dtHours .* sum(pricePerKWh .* pvSelfImportKW);
baselines.PvSelfNoBatteryPeakKW = max(pvSelfImportKW);
baselines.PvSelfNoBatteryDaytimePeakKW = max(pvSelfImportKW(dayMask));
values = cell2mat(struct2cell(baselines));
if any(~isfinite(values)) || any([baselines.PaperLoadOnlyBillEUR, ...
        baselines.PvSelfNoBatteryBillEUR] <= 0)
    error("StoreNet:InvalidFigure7ReuseData", ...
        "Recomputed legacy-reuse baselines must be finite and positive.");
end
end

function [row, reused] = applyLegacyFigureSevenRow(row, specification, ...
        reusable, baselines)
reused = false;
if specification.ExperimentId ~= "FIGURE_7" || isempty(reusable)
    return
end
selected = abs(double(reusable.CapacityRatio) - ...
        specification.CapacityRatio) <= 1e-12 & ...
    abs(double(reusable.PowerRatio) - specification.PowerRatio) <= 1e-12;
if ~any(selected)
    return
end
source = reusable(find(selected, 1, "first"), :);
row.Status = "ok";
row.WallTimeSeconds = double(source.WallTimeSeconds);
row.PaperLoadOnlyBaselineBillEUR = baselines.PaperLoadOnlyBillEUR;
row.PaperLoadOnlyBaselinePeakImportKW = baselines.PaperLoadOnlyPeakKW;
row.PaperLoadOnlyBaselineDaytimePeakImportKW = ...
    baselines.PaperLoadOnlyDaytimePeakKW;
row.OptimizedBillEUR = double(source.OptimizedBillEUR);
row.PaperLoadOnlySavingsEUR = ...
    row.PaperLoadOnlyBaselineBillEUR - row.OptimizedBillEUR;
row.PaperLoadOnlySavingsPercent = 100 .* row.PaperLoadOnlySavingsEUR ./ ...
    row.PaperLoadOnlyBaselineBillEUR;
row.PaperSavingsPercentDenominatorIsZero = 0;
row.PvSelfNoBatteryBaselineBillEUR = ...
    baselines.PvSelfNoBatteryBillEUR;
row.PvSelfNoBatteryBaselinePeakImportKW = ...
    baselines.PvSelfNoBatteryPeakKW;
row.PvSelfNoBatteryBaselineDaytimePeakImportKW = ...
    baselines.PvSelfNoBatteryDaytimePeakKW;
row.PvSelfNoBatterySavingsEUR = ...
    row.PvSelfNoBatteryBaselineBillEUR - row.OptimizedBillEUR;
row.PvSelfNoBatterySavingsPercent = 100 .* ...
    row.PvSelfNoBatterySavingsEUR ./ row.PvSelfNoBatteryBaselineBillEUR;
row.EngineeringSavingsPercentDenominatorIsZero = 0;
row.PeakImportKW = double(source.PeakImportKW);
row.DaytimePeakImportKW = double(source.DaytimePeakImportKW);
row.ImportSpreadKW = double(source.ImportSpreadKW);
row.TotalGridImportKWh = double(source.TotalGridImportKWh);
row.TotalBatteryThroughputKWh = double(source.TotalBatteryThroughputKWh);
row.EnergyBalanceResidualKW = double(source.EnergyBalanceResidualKW);
row.TerminalSocErrorKWh = double(source.TerminalSocErrorKWh);
row.SimultaneousChargeDischargeKW = ...
    double(source.SimultaneousChargeDischargeKW);
row.MinimumStageExitFlag = double(source.MinimumExitFlag);
reused = true;
end
function specifications = specificationTable(experimentId, caseId, budgetId, ...
        strategy, capacityRatio, powerRatio, scenarios, scenarioIndex)
rowCount = numel(caseId);
experimentId = repmat(string(experimentId), rowCount, 1);
caseId = string(caseId(:));
budgetId = string(budgetId(:));
if isscalar(budgetId)
    budgetId = repmat(budgetId, rowCount, 1);
end
strategy = string(strategy(:));
scenarioId = scenarios.ScenarioId(scenarioIndex);
pairId = scenarios.PairId(scenarioIndex);
cohortId = scenarios.CohortId(scenarioIndex);
pvBoundaryId = scenarios.PvBoundaryId(scenarioIndex);
transferLossFraction = scenarios.TransferLossFraction(scenarioIndex);
sensitivityRole = scenarios.SensitivityRole(scenarioIndex);
isPrimary = scenarios.IsPrimary(scenarioIndex);
specifications = table(experimentId, caseId, budgetId, strategy, ...
    scenarioId, pairId, cohortId, pvBoundaryId, transferLossFraction, ...
    sensitivityRole, isPrimary, capacityRatio, powerRatio, ...
    VariableNames=["ExperimentId", "CaseId", "BudgetId", "Strategy", ...
    "ScenarioId", "PairId", "CohortId", "PvBoundaryId", ...
    "TransferLossFraction", "SensitivityRole", "IsPrimary", ...
    "CapacityRatio", "PowerRatio"]);
end

function [data, meta, status, identifier, message] = loadExperimentData( ...
        provider, day, dataRoot, qualityMode)
try
    [data, meta] = provider(day, DataRoot=dataRoot, IntervalMinutes=30, ...
        QualityMode=qualityMode);
    data = normalizeExperimentData(data);
    if metadataRejected(meta)
        status = "quality_rejected";
        identifier = "StoreNet:QualityRejected";
        message = qualityMessage(meta);
    else
        status = "ok";
        identifier = "";
        message = "";
    end
catch exception
    data = struct;
    meta = struct;
    status = "data_failed";
    identifier = string(exception.identifier);
    message = string(exception.message);
end
end

function data = normalizeExperimentData(data)
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
        "Data provider output is missing field(s): %s.", strjoin(missing, ", "));
end
data.time = data.time(:);
data.houseIds = string(data.houseIds(:)).';
end

function rejected = metadataRejected(meta)
rejected = isfield(meta, "qualityPassed") && ...
    isscalar(meta.qualityPassed) && ~logical(meta.qualityPassed);
end

function message = qualityMessage(meta)
message = "Data provider rejected the requested quality mode.";
if isfield(meta, "qualityReasons") && ~isempty(meta.qualityReasons)
    message = strjoin(string(meta.qualityReasons), "; ");
end
end

function meta = enrichCaseMeta(meta, specification, day, qualityMode)
meta.experimentId = specification.ExperimentId;
meta.caseId = specification.CaseId;
meta.budgetId = specification.BudgetId;
meta.strategy = specification.Strategy;
meta.scenarioId = specification.ScenarioId;
meta.pairId = specification.PairId;
meta.sensitivityRole = specification.SensitivityRole;
meta.isPrimary = specification.IsPrimary;
meta.capacityRatio = specification.CapacityRatio;
meta.powerRatio = specification.PowerRatio;
meta.dateOrPeriod = day;
meta.qualityMode = qualityMode;
end

function row = resultRowFromSpecification(specification, day, qualityMode, ...
        runDirectory)
row = emptyResultRow();
row.ExperimentId = specification.ExperimentId;
row.CaseId = specification.CaseId;
row.Day = day;
row.BudgetId = specification.BudgetId;
row.Strategy = specification.Strategy;
row.ScenarioId = specification.ScenarioId;
row.PairId = specification.PairId;
row.CohortId = specification.CohortId;
row.PvBoundaryId = specification.PvBoundaryId;
row.TransferLossFraction = specification.TransferLossFraction;
row.SensitivityRole = specification.SensitivityRole;
row.IsPrimary = specification.IsPrimary;
row.CapacityRatio = specification.CapacityRatio;
row.PowerRatio = specification.PowerRatio;
row.QualityMode = qualityMode;
row.CaseDirectory = string(fullfile(runDirectory, "cases", ...
    specification.CaseId));
end

function row = addPreparedCase(row, config, meta)
row.HouseCount = double(meta.houseCount);
row.PvHomeCount = double(meta.pvHomeCount);
row.H4MaskAffected = double(meta.h4MaskAffected);
row.H4AlignmentCategory = string(meta.h4AlignmentCategory);
row.BatteryCapacityKWh = double(config.batteryCapacityKWh);
row.BatteryPowerKW = double(config.batteryPowerKW);
row.SelfDischargeKW = double(config.selfDischargeKW);
end

function row = addSuccessfulMetrics(row, metrics, solution)
paper = metrics.PaperLoadOnlyBaseline;
pvSelf = metrics.PvSelfNoBatteryBaseline;
row.PaperLoadOnlyBaselineBillEUR = double(paper.billEUR);
row.PaperLoadOnlyBaselinePeakImportKW = double(paper.peakImportKW);
row.PaperLoadOnlyBaselineDaytimePeakImportKW = ...
    double(paper.daytimePeakImportKW);
row.PaperLoadOnlySavingsEUR = double(paper.savingsEUR);
row.PaperLoadOnlySavingsPercent = double(paper.savingsPercent);
row.PaperSavingsPercentDenominatorIsZero = double( ...
    paper.savingsPercentDenominatorIsZero);
row.PvSelfNoBatteryBaselineBillEUR = double(pvSelf.billEUR);
row.PvSelfNoBatteryBaselinePeakImportKW = double(pvSelf.peakImportKW);
row.PvSelfNoBatteryBaselineDaytimePeakImportKW = ...
    double(pvSelf.daytimePeakImportKW);
row.PvSelfNoBatterySavingsEUR = double(pvSelf.savingsEUR);
row.PvSelfNoBatterySavingsPercent = double(pvSelf.savingsPercent);
row.EngineeringSavingsPercentDenominatorIsZero = double( ...
    pvSelf.savingsPercentDenominatorIsZero);
row.OptimizedBillEUR = requiredMetric(metrics, "optimizedBillEUR");
row.PeakImportKW = requiredMetric(metrics, "peakImportKW");
row.DaytimePeakImportKW = requiredMetric(metrics, "daytimePeakImportKW");
row.ImportSpreadKW = requiredMetric(metrics, "importSpreadKW");
row.TotalGridImportKWh = requiredMetric(metrics, "totalGridImportKWh");
row.TotalBatteryThroughputKWh = requiredMetric(metrics, ...
    "totalBatteryThroughputKWh");
row.TotalCurtailedPvKWh = requiredMetric(metrics, "totalCurtailedPvKWh");
row.TotalSharedExportKWh = requiredMetric(metrics, "totalSharedExportKWh");
row.EnergyBalanceResidualKW = requiredMetric(metrics, ...
    "energyBalanceResidualKW");
row.PvAllocationResidualKW = requiredMetric(metrics, ...
    "pvAllocationResidualKW");
row.HomeBalanceResidualKW = requiredMetric(metrics, "homeBalanceResidualKW");
row.BatteryDynamicsResidualKW = requiredMetric(metrics, ...
    "batteryDynamicsResidualKW");
row.AggregateImportResidualKW = requiredMetric(metrics, ...
    "aggregateImportResidualKW");
row.ChargeConversionResidualKW = requiredMetric(metrics, ...
    "chargeConversionResidualKW");
row.DischargeConversionResidualKW = requiredMetric(metrics, ...
    "dischargeConversionResidualKW");
row.InitialSocErrorKWh = requiredMetric(metrics, "initialSocErrorKWh");
row.TerminalSocErrorKWh = requiredMetric(metrics, "terminalSocErrorKWh");
row.SocBoundViolationKWh = requiredMetric(metrics, "socBoundViolationKWh");
row.ChargePowerViolationKW = requiredMetric(metrics, ...
    "chargePowerViolationKW");
row.DischargePowerViolationKW = requiredMetric(metrics, ...
    "dischargePowerViolationKW");
row.AggregateImportNonnegativeViolationKW = requiredMetric(metrics, ...
    "aggregateImportNonnegativeViolationKW");
row.SimultaneousChargeDischargeKW = requiredMetric(metrics, ...
    "simultaneousChargeDischargeKW");
row.SimultaneousChargeDischargeCount = requiredMetric(metrics, ...
    "simultaneousChargeDischargeCount");
row.MaximumLexicographicViolation = requiredMetric(metrics, ...
    "maximumLexicographicViolation");
row = addStageSummary(row, solution);
end

function value = requiredMetric(metrics, name)
if ~isfield(metrics, name) || ~isnumeric(metrics.(name)) || ...
        ~isscalar(metrics.(name))
    error("StoreNet:MissingBahloulMetric", ...
        "Required scalar metric is missing or invalid: %s", name);
end
value = double(metrics.(name));
end

function row = addStageSummary(row, solution)
requiredFields = ["name", "value", "solverObjective", "exitFlag", ...
    "relativeGap"];
if ~isfield(solution, "objectiveStages") || isempty(solution.objectiveStages)
    error("StoreNet:MissingBahloulStages", ...
        "Successful Bahloul cases require objectiveStages evidence.");
end
stages = solution.objectiveStages(:);
missing = requiredFields(~isfield(stages, cellstr(requiredFields)));
if ~isempty(missing)
    error("StoreNet:MissingBahloulStages", ...
        "objectiveStages is missing field(s): %s", strjoin(missing, ", "));
end
values = [stages.value].';
exitFlags = [stages.exitFlag].';
relativeGaps = [stages.relativeGap].';
row.StageCount = numel(stages);
row.MinimumStageExitFlag = min(double(exitFlags));
row.MaximumStageRelativeGap = max(double(relativeGaps));
row.StageNames = strjoin(string({stages.name}).', "|");
row.StageValues = joinNumeric(values);
row.StageExitFlags = joinNumeric(exitFlags);
row.StageRelativeGaps = joinNumeric(relativeGaps);
end

function value = joinNumeric(values)
value = strjoin(compose("%.17g", double(values(:))), "|");
end

function row = addArtifactPaths(row, artifacts)
row.InputsPath = artifacts.inputsPath;
row.InputsSha256 = artifacts.inputsSha256;
row.SolutionPath = artifacts.solutionPath;
row.SolutionSha256 = artifacts.solutionSha256;
row.StagesPath = artifacts.stagesPath;
row.MetricsPath = artifacts.metricsPath;
end

function row = emptyResultRow()
row = struct;
row.ExperimentId = "";
row.CaseId = "";
row.Day = NaT;
row.BudgetId = "";
row.Strategy = "";
row.ScenarioId = "";
row.PairId = "";
row.CohortId = "";
row.PvBoundaryId = "";
row.TransferLossFraction = NaN;
row.SensitivityRole = "";
row.IsPrimary = false;
row.CapacityRatio = NaN;
row.PowerRatio = NaN;
row.QualityMode = "";
row.BatteryCapacityKWh = NaN;
row.BatteryPowerKW = NaN;
row.SelfDischargeKW = NaN;
row.HouseCount = NaN;
row.PvHomeCount = NaN;
row.H4MaskAffected = NaN;
row.H4AlignmentCategory = "";
row.Status = "not_run";
row.ErrorIdentifier = "";
row.ErrorMessage = "";
row.WallTimeSeconds = NaN;
row.PaperLoadOnlyBaselineBillEUR = NaN;
row.PaperLoadOnlyBaselinePeakImportKW = NaN;
row.PaperLoadOnlyBaselineDaytimePeakImportKW = NaN;
row.PaperLoadOnlySavingsEUR = NaN;
row.PaperLoadOnlySavingsPercent = NaN;
row.PaperSavingsPercentDenominatorIsZero = NaN;
row.PvSelfNoBatteryBaselineBillEUR = NaN;
row.PvSelfNoBatteryBaselinePeakImportKW = NaN;
row.PvSelfNoBatteryBaselineDaytimePeakImportKW = NaN;
row.PvSelfNoBatterySavingsEUR = NaN;
row.PvSelfNoBatterySavingsPercent = NaN;
row.EngineeringSavingsPercentDenominatorIsZero = NaN;
row.OptimizedBillEUR = NaN;
row.PeakImportKW = NaN;
row.DaytimePeakImportKW = NaN;
row.ImportSpreadKW = NaN;
row.TotalGridImportKWh = NaN;
row.TotalBatteryThroughputKWh = NaN;
row.TotalCurtailedPvKWh = NaN;
row.TotalSharedExportKWh = NaN;
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
row.StageCount = NaN;
row.MinimumStageExitFlag = NaN;
row.MaximumStageRelativeGap = NaN;
row.StageNames = "";
row.StageValues = "";
row.StageExitFlags = "";
row.StageRelativeGaps = "";
row.CaseDirectory = "";
row.InputsPath = "";
row.InputsSha256 = "";
row.SolutionPath = "";
row.SolutionSha256 = "";
row.StagesPath = "";
row.MetricsPath = "";
end

function targets = readTableITargets(path)
if ~isfile(path)
    error("StoreNet:MissingTableIReference", ...
        "Table I reference is missing: %s", path);
end
targets = readtable(path, TextType="string", VariableNamingRule="preserve");
required = ["scenario", "SH_BM", "VPP_BM", "PS", "PSDT", "LL"];
missing = required(~ismember(required, ...
    string(targets.Properties.VariableNames)));
if ~isempty(missing)
    error("StoreNet:InvalidTableIReference", ...
        "Table I reference is missing column(s): %s", strjoin(missing, ", "));
end
end

function comparison = buildTableIComparison(longTable, targets)
selected = longTable.ExperimentId == "TABLE_I";
local = longTable(selected, :);
targetSavings = nan(height(local), 1);
for rowIndex = 1:height(local)
    referenceScenario = tableIReferenceScenario(local.BudgetId(rowIndex));
    referenceRow = string(targets.scenario) == referenceScenario;
    if nnz(referenceRow) ~= 1
        error("StoreNet:InvalidTableIReference", ...
            "Table I reference must contain exactly one %s row.", ...
            referenceScenario);
    end
    values = targets.(char(local.Strategy(rowIndex)));
    targetSavings(rowIndex) = double(values(referenceRow));
end

comparisonVariables = ["CaseId", "Day", "BudgetId", "Strategy", ...
    "ScenarioId", "PairId", "CohortId", "PvBoundaryId", ...
    "TransferLossFraction", "SensitivityRole", "IsPrimary", ...
    "CapacityRatio", "PowerRatio", "Status", "ErrorIdentifier", ...
    "ErrorMessage"];
comparison = local(:, comparisonVariables);
comparison.PaperTargetSavingsPercent = targetSavings;
comparison.LocalPaperSavingsPercent = local.PaperLoadOnlySavingsPercent;
comparison.DifferencePercentagePoints = ...
    comparison.LocalPaperSavingsPercent - targetSavings;
comparison.PaperLoadOnlyBaselineBillEUR = ...
    local.PaperLoadOnlyBaselineBillEUR;
comparison.OptimizedBillEUR = local.OptimizedBillEUR;
end

function scenario = tableIReferenceScenario(budgetId)
switch budgetId
    case "NOMINAL"
        scenario = "nominal";
    case "POWER_20"
        scenario = "20_percent_power";
    case "CAPACITY_20"
        scenario = "20_percent_capacity";
    otherwise
        error("StoreNet:UnknownTableIBudget", ...
            "Unknown Table I budget: %s", budgetId);
end
end

function writeFigureSevenSurface(path, longTable, capacityRatios, ...
        powerRatios, visible)
figureRows = longTable(longTable.ExperimentId == "FIGURE_7", :);
primary = surfaceMatrix(figureRows, "PRIMARY", capacityRatios, powerRatios);
visibility = "off";
if visible
    visibility = "on";
end
figureHandle = figure(Visible=visibility, Color="w", ...
    Position=[100, 100, 760, 620]);
cleaner = onCleanup(@() close(figureHandle));
layout = tiledlayout(figureHandle, 1, 1, Padding="compact", ...
    TileSpacing="compact");
writeSurfaceTile(nexttile(layout), powerRatios, capacityRatios, primary, ...
    "H20_PV10 primary");
title(layout, "Bahloul Figure 7 independent proxy", FontWeight="bold");
exportgraphics(figureHandle, path, Resolution=300, BackgroundColor="white");
end

function writeSensitivityCheckpoint(rows, completedCount, path)
checkpoint = struct2table(rows(1:completedCount));
checkpointFolder = fileparts(path);
temporaryPath = string(tempname(checkpointFolder)) + ".csv";
cleaner = onCleanup(@() deleteTemporaryCheckpoint(temporaryPath));
writetable(checkpoint, temporaryPath);
[moved, message] = movefile(temporaryPath, path, "f");
if ~moved
    error("StoreNet:SensitivityCheckpointWriteFailed", ...
        "Cannot atomically replace sensitivity checkpoint: %s", message);
end
end

function deleteTemporaryCheckpoint(path)
if isfile(path)
    delete(path);
end
end

function values = surfaceMatrix(rows, sensitivityRole, capacityRatios, powerRatios)
values = nan(numel(capacityRatios), numel(powerRatios));
for capacityIndex = 1:numel(capacityRatios)
    for powerIndex = 1:numel(powerRatios)
        selected = rows.SensitivityRole == sensitivityRole & ...
            abs(rows.CapacityRatio - capacityRatios(capacityIndex)) < 1e-12 & ...
            abs(rows.PowerRatio - powerRatios(powerIndex)) < 1e-12 & ...
            rows.Status == "ok";
        if nnz(selected) == 1
            values(capacityIndex, powerIndex) = ...
                rows.PaperLoadOnlySavingsPercent(selected);
        end
    end
end
end

function writeSurfaceTile(axesHandle, powerRatios, capacityRatios, values, titleText)
surf(axesHandle, powerRatios, capacityRatios, values, EdgeColor=[0.25, 0.25, 0.25]);
xlabel(axesHandle, "Power ratio");
ylabel(axesHandle, "Capacity ratio");
zlabel(axesHandle, "Paper-load-only savings (%)");
title(axesHandle, titleText);
grid(axesHandle, "on");
view(axesHandle, 42, 28);
colorbar(axesHandle);
end

function config = applyOverrides(config, overrides)
fields = string(fieldnames(overrides));
for fieldIndex = 1:numel(fields)
    field = fields(fieldIndex);
    config.(field) = overrides.(field);
end
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
