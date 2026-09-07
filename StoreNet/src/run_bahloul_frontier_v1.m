function run = run_bahloul_frontier_v1(options)
%RUN_BAHLOUL_FRONTIER_V1 Bill/peak frontier, bill-free peak and tariff sweep.
%   Improvement v2 (docs/decisions/ADR-002). For every requested public
%   StoreNet day the runner solves, on the frozen B2022-IR-v1 primary case
%   (20 homes/10 PV, DC_SOURCE, xi=0.07, release_literal):
%     anchor      the AnchorStrategies at nominal parameters;
%     frontier    IMPROVED_PEAK_GUARD with cap = CapRatio * P0, where P0 is
%                 the PV-self/no-battery aggregate peak of that day;
%     tariff      VPP_BM_DEMAND_CHARGE for every DemandCharges value;
%     efficiency  the EfficiencyStrategies with etaBatteryCharge =
%                 etaBatteryDischarge = each BatteryEfficiencies value
%                 (IMPROVED_PEAK_GUARD uses CapRatio 1).
%   Every case is checkpointed to strategy_metrics.csv and profiles.csv the
%   moment it finishes; calling again with Resume=true skips finished cases.
%   Infeasible caps are recorded as "infeasible" and never retried with a
%   different cap. Frozen result directories are neither read for solving
%   nor written.

arguments
    options.Dates (:, 1) datetime = datetime(2020, 8, 24)
    options.IntervalMinutes (1, 1) double ...
        {mustBeMember(options.IntervalMinutes, [30, 60])} = 30
    options.CapRatios (1, :) double {mustBePositive} = ...
        [3, 2.5, 2, 1.75, 1.5, 1.25, 1.1, 1, 0.95, 0.9, 0.85, 0.8, ...
        0.75, 0.7, 0.65, 0.6, 0.55, 0.5]
    options.DemandCharges (1, :) double {mustBeNonnegative} = ...
        [0.02, 0.05, 0.1, 0.2, 0.3, 0.5, 1, 2]
    options.BatteryEfficiencies (1, :) double = double.empty(1, 0)
    options.AnchorStrategies (1, :) string = ...
        ["VPP_BM", "VPP_BM_PEAK_LEX", "PS"]
    options.EfficiencyStrategies (1, :) string = ["SH_BM", "VPP_BM", ...
        "VPP_BM_PEAK_LEX", "PS", "PSDT", "LL", "IMPROVED_PEAK_GUARD"]
    options.DataRoot (1, 1) string = ""
    options.OutputDirectory (1, 1) string = ""
    options.RunId (1, 1) string = ""
    options.ConfigOverrides (1, 1) struct = struct
    options.PersistSolutions (1, 1) logical = true
    options.PersistFrontierSolutions (1, 1) logical = false
    options.Resume (1, 1) logical = true
    options.DataProvider (1, 1) function_handle = @load_storenet_day
    options.Solver (1, 1) function_handle = @solve_storenet
end

sourceFolder = string(fileparts(mfilename("fullpath")));
projectFolder = string(fullfile(sourceFolder, ".."));
if strlength(options.DataRoot) == 0
    options.DataRoot = string(fullfile(projectFolder, "data", "raw"));
end
if strlength(options.RunId) == 0
    options.RunId = "frontier_" + string(datetime("now"), "yyyyMMdd_HHmmss");
end
if strlength(options.OutputDirectory) == 0
    options.OutputDirectory = string(fullfile(projectFolder, "results", ...
        "bahloul_vpp_improvement_v2_frontier", options.RunId));
end
validateStrategyLists(options);
if any(options.BatteryEfficiencies <= 0 | options.BatteryEfficiencies > 1)
    error("StoreNet:InvalidFrontierEfficiency", ...
        "BatteryEfficiencies must lie in (0, 1].");
end

paths = outputPaths(options.OutputDirectory);
prepareOutputDirectory(options.OutputDirectory, options.Resume);
metricsTable = loadExistingMetrics(paths.metrics, options.Resume);
profiles = loadExistingProfiles(paths.profiles, options.Resume);
plan = planCases(options);
days = unique(dateshift(options.Dates(:), "start", "day"));
plannedCaseCount = numel(days) * height(plan);
runStarted = tic;

for dayIndex = 1:numel(days)
    calendarDay = days(dayIndex);
    dayString = string(calendarDay, "yyyy-MM-dd");
    pending = ~casesFinished(metricsTable, dayString, plan.CaseId);
    if ~any(pending)
        continue
    end

    [data, dataMeta, loadStatus, loadException] = loadPublicDay( ...
        options.DataProvider, calendarDay, options.DataRoot, ...
        options.IntervalMinutes);
    if loadStatus ~= "ok"
        for caseIndex = find(pending).'
            row = skippedRow(dayString, plan(caseIndex, :), options, ...
                loadStatus, loadException);
            metricsTable = appendRow(metricsTable, row);
        end
        writeCheckpoint(paths, metricsTable, profiles, options, ...
            plannedCaseCount, false);
        continue
    end

    baseConfig = storenet_config(IntervalMinutes=options.IntervalMinutes, ...
        DataRoot=options.DataRoot, QualityMode="release_literal");
    baseConfig = applyOverrides(baseConfig, options.ConfigOverrides);
    [caseData, caseConfig, caseMeta] = prepare_bahloul_case(data, ...
        baseConfig, CohortId="H20_PV10", PvBoundaryId="DC_SOURCE", ...
        TransferLossFraction=0.07, DataMeta=dataMeta);
    baseline = computeBaselines(caseData, caseConfig);

    for caseIndex = find(pending).'
        planned = plan(caseIndex, :);
        config = configureCase(caseConfig, planned, baseline);
        started = tic;
        try
            [solution, metrics] = options.Solver(caseData, config, ...
                planned.Strategy);
            wallTimeSeconds = toc(started);
            row = successRow(dayString, planned, options, caseMeta, ...
                config, baseline, solution, metrics, wallTimeSeconds);
            profiles = [profiles; profileRows(dayString, planned.CaseId, ...
                caseData, config, solution, row.CapKW)]; %#ok<AGROW>
            if shouldPersist(planned, options)
                artifacts = persistCase(options.OutputDirectory, dayString, ...
                    planned, caseData, config, caseMeta, solution, metrics);
                row.ArtifactDirectory = artifacts.directory;
                row.InputsSha256 = artifacts.inputsSha256;
                row.SolutionSha256 = artifacts.solutionSha256;
            end
        catch exception
            wallTimeSeconds = toc(started);
            row = failureRow(dayString, planned, options, caseMeta, ...
                config, baseline, exception, wallTimeSeconds);
        end
        metricsTable = appendRow(metricsTable, row);
        writeCheckpoint(paths, metricsTable, profiles, options, ...
            plannedCaseCount, false);
    end
end

checkpoint = writeCheckpoint(paths, metricsTable, profiles, options, ...
    plannedCaseCount, true);
manifestPath = writeManifest(options, paths, days, plan, metricsTable, ...
    toc(runStarted));

run = struct;
run.outputDirectory = options.OutputDirectory;
run.runId = options.RunId;
run.strategyMetrics = metricsTable;
run.profiles = profiles;
run.plan = plan;
run.checkpoint = checkpoint;
run.manifestPath = manifestPath;
run.metricsPath = paths.metrics;
run.profilesPath = paths.profiles;
end

%% ----------------------------------------------------------------------
function validateStrategyLists(options)
allowed = ["SH_BM", "VPP_BM", "PS", "PSDT", "LL", ...
    "IMPROVED_PEAK_GUARD", "VPP_BM_PEAK_LEX", "VPP_BM_DEMAND_CHARGE"];
anchorBad = options.AnchorStrategies(~ismember(options.AnchorStrategies, ...
    allowed) | ismember(options.AnchorStrategies, ...
    ["IMPROVED_PEAK_GUARD", "VPP_BM_DEMAND_CHARGE"]));
if ~isempty(anchorBad)
    error("StoreNet:InvalidFrontierAnchor", ...
        "Anchor strategies must be parameter-free strategies; got %s.", ...
        strjoin(anchorBad, ", "));
end
efficiencyBad = options.EfficiencyStrategies(~ismember( ...
    options.EfficiencyStrategies, allowed) | ...
    options.EfficiencyStrategies == "VPP_BM_DEMAND_CHARGE");
if ~isempty(efficiencyBad)
    error("StoreNet:InvalidFrontierEfficiencyStrategy", ...
        "Unsupported efficiency strategy: %s.", strjoin(efficiencyBad, ", "));
end
end

function plan = planCases(options)
caseId = strings(0, 1); caseKind = strings(0, 1); strategy = strings(0, 1);
capRatio = zeros(0, 1); demandCharge = zeros(0, 1); eta = zeros(0, 1);
for name = options.AnchorStrategies
    caseId(end + 1, 1) = "ANCHOR_" + name; %#ok<AGROW>
    caseKind(end + 1, 1) = "anchor"; %#ok<AGROW>
    strategy(end + 1, 1) = name; %#ok<AGROW>
    capRatio(end + 1, 1) = NaN; %#ok<AGROW>
    demandCharge(end + 1, 1) = NaN; %#ok<AGROW>
    eta(end + 1, 1) = NaN; %#ok<AGROW>
end
for ratio = options.CapRatios
    caseId(end + 1, 1) = "FRONTIER_R" + sprintf("%.3f", ratio); %#ok<AGROW>
    caseKind(end + 1, 1) = "frontier"; %#ok<AGROW>
    strategy(end + 1, 1) = "IMPROVED_PEAK_GUARD"; %#ok<AGROW>
    capRatio(end + 1, 1) = ratio; %#ok<AGROW>
    demandCharge(end + 1, 1) = NaN; %#ok<AGROW>
    eta(end + 1, 1) = NaN; %#ok<AGROW>
end
for charge = options.DemandCharges
    caseId(end + 1, 1) = "TARIFF_L" + sprintf("%.3f", charge); %#ok<AGROW>
    caseKind(end + 1, 1) = "tariff"; %#ok<AGROW>
    strategy(end + 1, 1) = "VPP_BM_DEMAND_CHARGE"; %#ok<AGROW>
    capRatio(end + 1, 1) = NaN; %#ok<AGROW>
    demandCharge(end + 1, 1) = charge; %#ok<AGROW>
    eta(end + 1, 1) = NaN; %#ok<AGROW>
end
for efficiency = options.BatteryEfficiencies
    for name = options.EfficiencyStrategies
        caseId(end + 1, 1) = "ETA" + sprintf("%.4f", efficiency) + ...
            "_" + name; %#ok<AGROW>
        caseKind(end + 1, 1) = "efficiency"; %#ok<AGROW>
        strategy(end + 1, 1) = name; %#ok<AGROW>
        if name == "IMPROVED_PEAK_GUARD"
            capRatio(end + 1, 1) = 1; %#ok<AGROW>
        else
            capRatio(end + 1, 1) = NaN; %#ok<AGROW>
        end
        demandCharge(end + 1, 1) = NaN; %#ok<AGROW>
        eta(end + 1, 1) = efficiency; %#ok<AGROW>
    end
end
if numel(unique(caseId)) ~= numel(caseId)
    error("StoreNet:DuplicateFrontierCase", ...
        "Planned case identifiers must be unique.");
end
plan = table(caseId, caseKind, strategy, capRatio, demandCharge, eta, ...
    VariableNames=["CaseId", "CaseKind", "Strategy", "CapRatio", ...
    "DemandChargeEURPerKW", "EtaBattery"]);
end

function config = configureCase(caseConfig, planned, baseline)
config = caseConfig;
if isfinite(planned.EtaBattery)
    config.etaBatteryCharge = planned.EtaBattery;
    config.etaBatteryDischarge = planned.EtaBattery;
end
if planned.Strategy == "IMPROVED_PEAK_GUARD"
    config.aggregateImportCapKW = planned.CapRatio .* baseline.pvSelfPeakKW;
end
if planned.Strategy == "VPP_BM_DEMAND_CHARGE"
    config.demandChargeEURPerKW = planned.DemandChargeEURPerKW;
end
end

function tf = shouldPersist(planned, options)
switch planned.CaseKind
    case {"anchor", "efficiency"}
        tf = options.PersistSolutions;
    otherwise
        tf = options.PersistFrontierSolutions;
end
end

%% ----------------------------------------------------------------------
function [data, meta, status, exception] = loadPublicDay(provider, ...
        calendarDay, dataRoot, intervalMinutes)
data = struct; meta = struct; exception = [];
try
    [data, meta] = provider(calendarDay, DataRoot=dataRoot, ...
        IntervalMinutes=intervalMinutes, QualityMode="release_literal");
catch loadException
    status = "data_error";
    exception = loadException;
    return
end
if isfield(meta, "qualityPassed") && ~logical(meta.qualityPassed)
    status = "quality_rejected";
    reasons = "";
    if isfield(meta, "qualityReasons")
        reasons = strjoin(string(meta.qualityReasons), ";");
    end
    exception = MException("StoreNet:QualityRejected", ...
        "Day %s fails release_literal: %s", ...
        string(calendarDay, "yyyy-MM-dd"), reasons);
    return
end
status = "ok";
end

function baseline = computeBaselines(data, config)
dtHours = double(data.dtHours);
timeEnd = data.time(:);
intervalStart = timeEnd - hours(dtHours);
dayMask = hour(intervalStart) >= config.dayStartHour & ...
    hour(intervalStart) < config.dayEndHour;
price = repmat(double(config.nightPrice), numel(timeEnd), 1);
price(dayMask) = double(config.dayPrice);
loadKW = double(data.loadKW);
pvKW = double(data.pvKW);
paperImportKW = sum(loadKW, 2);
pvSelfImportKW = sum(loadKW - min(loadKW, config.etaPvAC .* pvKW), 2);
baseline = struct;
baseline.dayMask = dayMask;
baseline.paperBillEUR = dtHours .* sum(price .* paperImportKW);
baseline.paperPeakKW = max(paperImportKW);
baseline.pvSelfBillEUR = dtHours .* sum(price .* pvSelfImportKW);
baseline.pvSelfPeakKW = max(pvSelfImportKW);
baseline.pvSelfDaytimePeakKW = maxOrNaN(pvSelfImportKW(dayMask));
baseline.pvSelfNightPeakKW = maxOrNaN(pvSelfImportKW(~dayMask));
end

function config = applyOverrides(config, overrides)
fields = string(fieldnames(overrides));
for fieldIndex = 1:numel(fields)
    config.(fields(fieldIndex)) = overrides.(fields(fieldIndex));
end
end

%% ----------------------------------------------------------------------
function row = emptyRow()
row = struct( ...
    "Dataset", "StoreNet", "Day", "", "CaseId", "", "CaseKind", "", ...
    "Strategy", "", "Status", "", "ErrorIdentifier", "", ...
    "ErrorMessage", "", "CapRatio", NaN, "CapKW", NaN, ...
    "DemandChargeEURPerKW", NaN, "EtaBatteryCharge", NaN, ...
    "EtaBatteryDischarge", NaN, "WallTimeSeconds", NaN, ...
    "IntervalMinutes", NaN, "HouseCount", NaN, "PvHomeCount", NaN, ...
    "PvBoundaryId", "", "TransferLossFraction", NaN, ...
    "H4MaskAffected", NaN, "BatteryCapacityKWhPerHome", NaN, ...
    "BatteryPowerKWPerHome", NaN, "MaxSolverTimeSeconds", NaN, ...
    "PaperLoadOnlyBaselineBillEUR", NaN, "PaperSavingsPercent", NaN, ...
    "PvSelfNoBatteryBaselineBillEUR", NaN, ...
    "EngineeringSavingsPercent", NaN, "OriginalLoadPeakKW", NaN, ...
    "PvSelfNoBatteryPeakKW", NaN, "PvSelfNoBatteryDaytimePeakKW", NaN, ...
    "PvSelfNoBatteryNightPeakKW", NaN, "OptimizedBillEUR", NaN, ...
    "AllDayPeakKW", NaN, "DaytimePeakKW", NaN, "NightPeakKW", NaN, ...
    "LoadRangeKW", NaN, "TotalGridImportKWh", NaN, ...
    "BatteryThroughputKWh", NaN, "PvCurtailmentKWh", NaN, ...
    "SharedExportKWh", NaN, "ObjectiveWithDemandChargeEUR", NaN, ...
    "PeakExcessOverCapKW", NaN, "CapViolationKW", NaN, ...
    "EnergyBalanceResidualKW", NaN, "PvAllocationResidualKW", NaN, ...
    "HomeBalanceResidualKW", NaN, "BatteryDynamicsResidualKW", NaN, ...
    "AggregateImportResidualKW", NaN, "InitialSocErrorKWh", NaN, ...
    "TerminalSocErrorKWh", NaN, "SocBoundViolationKWh", NaN, ...
    "ChargePowerViolationKW", NaN, "DischargePowerViolationKW", NaN, ...
    "AggregateImportNonnegativeViolationKW", NaN, ...
    "SimultaneousChargeDischargeKW", NaN, ...
    "MaximumLexicographicViolation", NaN, "MinimumExitFlag", NaN, ...
    "MaximumRelativeMipGapPercent", NaN, "StageCount", NaN, ...
    "StageOneName", "", "StageOneValue", NaN, ...
    "ArtifactDirectory", "", "InputsSha256", "", "SolutionSha256", "");
end

function row = baseRow(dayString, planned, options)
row = emptyRow();
row.Day = dayString;
row.CaseId = planned.CaseId;
row.CaseKind = planned.CaseKind;
row.Strategy = planned.Strategy;
row.CapRatio = planned.CapRatio;
row.DemandChargeEURPerKW = planned.DemandChargeEURPerKW;
row.IntervalMinutes = options.IntervalMinutes;
row.PvBoundaryId = "DC_SOURCE";
row.TransferLossFraction = 0.07;
end

function row = describeCase(row, caseMeta, config, baseline)
row.HouseCount = double(caseMeta.houseCount);
row.PvHomeCount = double(caseMeta.pvHomeCount);
row.H4MaskAffected = double(caseMeta.h4MaskAffected);
row.EtaBatteryCharge = double(config.etaBatteryCharge);
row.EtaBatteryDischarge = double(config.etaBatteryDischarge);
row.BatteryCapacityKWhPerHome = double(config.batteryCapacityKWh);
row.BatteryPowerKWPerHome = double(config.batteryPowerKW);
if isfield(config, "maxSolverTimeSeconds")
    row.MaxSolverTimeSeconds = double(config.maxSolverTimeSeconds);
end
if isfield(config, "aggregateImportCapKW")
    row.CapKW = double(config.aggregateImportCapKW);
end
row.PaperLoadOnlyBaselineBillEUR = baseline.paperBillEUR;
row.PvSelfNoBatteryBaselineBillEUR = baseline.pvSelfBillEUR;
row.OriginalLoadPeakKW = baseline.paperPeakKW;
row.PvSelfNoBatteryPeakKW = baseline.pvSelfPeakKW;
row.PvSelfNoBatteryDaytimePeakKW = baseline.pvSelfDaytimePeakKW;
row.PvSelfNoBatteryNightPeakKW = baseline.pvSelfNightPeakKW;
end

function row = successRow(dayString, planned, options, caseMeta, config, ...
        baseline, solution, metrics, wallTimeSeconds)
row = baseRow(dayString, planned, options);
row = describeCase(row, caseMeta, config, baseline);
row.Status = successStatus(solution);
row.WallTimeSeconds = wallTimeSeconds;
row.PaperSavingsPercent = metrics.PaperLoadOnlyBaseline.savingsPercent;
row.EngineeringSavingsPercent = metrics.PvSelfNoBatteryBaseline.savingsPercent;
row.OptimizedBillEUR = metrics.optimizedBillEUR;
row.AllDayPeakKW = metrics.peakImportKW;
row.DaytimePeakKW = metrics.daytimePeakImportKW;
importKW = double(solution.aggregateImportKW(:));
row.NightPeakKW = maxOrNaN(importKW(~baseline.dayMask));
row.LoadRangeKW = metrics.importSpreadKW;
row.TotalGridImportKWh = metrics.totalGridImportKWh;
row.BatteryThroughputKWh = metrics.totalBatteryThroughputKWh;
row.PvCurtailmentKWh = metrics.totalCurtailedPvKWh;
row.SharedExportKWh = metrics.totalSharedExportKWh;
if isfinite(row.DemandChargeEURPerKW)
    row.ObjectiveWithDemandChargeEUR = metrics.optimizedBillEUR + ...
        row.DemandChargeEURPerKW .* metrics.peakImportKW;
end
if isfinite(row.CapKW)
    row.PeakExcessOverCapKW = row.AllDayPeakKW - row.CapKW;
    row.CapViolationKW = max(0, row.PeakExcessOverCapKW);
end
row.EnergyBalanceResidualKW = metrics.energyBalanceResidualKW;
row.PvAllocationResidualKW = metrics.pvAllocationResidualKW;
row.HomeBalanceResidualKW = metrics.homeBalanceResidualKW;
row.BatteryDynamicsResidualKW = metrics.batteryDynamicsResidualKW;
row.AggregateImportResidualKW = metrics.aggregateImportResidualKW;
row.InitialSocErrorKWh = metrics.initialSocErrorKWh;
row.TerminalSocErrorKWh = metrics.terminalSocErrorKWh;
row.SocBoundViolationKWh = metrics.socBoundViolationKWh;
row.ChargePowerViolationKW = metrics.chargePowerViolationKW;
row.DischargePowerViolationKW = metrics.dischargePowerViolationKW;
row.AggregateImportNonnegativeViolationKW = ...
    metrics.aggregateImportNonnegativeViolationKW;
row.SimultaneousChargeDischargeKW = metrics.simultaneousChargeDischargeKW;
row.MaximumLexicographicViolation = metrics.maximumLexicographicViolation;
row.MinimumExitFlag = min(double(solution.exitFlags(:)));
row.MaximumRelativeMipGapPercent = maximumRelativeGap(solution);
row.StageCount = numel(solution.objectiveStages);
row.StageOneName = string(solution.objectiveStages(1).name);
row.StageOneValue = double(solution.objectiveStages(1).value);
end

function status = successStatus(solution)
flags = double(solution.exitFlags(:));
if any(flags == 2)
    status = "time_limited";
else
    status = "ok";
end
end

function row = failureRow(dayString, planned, options, caseMeta, config, ...
        baseline, exception, wallTimeSeconds)
row = baseRow(dayString, planned, options);
row = describeCase(row, caseMeta, config, baseline);
row.WallTimeSeconds = wallTimeSeconds;
row.ErrorIdentifier = string(exception.identifier);
row.ErrorMessage = string(exception.message);
row.Status = failureStatus(exception);
end

function status = failureStatus(exception)
status = "failed";
token = regexp(string(exception.message), "exit flag (-?\d+)", ...
    "tokens", "once");
if string(exception.identifier) == "StoreNet:OptimizationFailed" && ...
        ~isempty(token) && str2double(token{1}) == -2
    status = "infeasible";
end
end

function row = skippedRow(dayString, planned, options, status, exception)
row = baseRow(dayString, planned, options);
row.Status = status;
row.WallTimeSeconds = 0;
if ~isempty(exception)
    row.ErrorIdentifier = string(exception.identifier);
    row.ErrorMessage = string(exception.message);
end
end

function gap = maximumRelativeGap(solution)
gap = NaN;
if ~isfield(solution, "solverOutputs")
    return
end
values = nan(numel(solution.solverOutputs), 1);
for outputIndex = 1:numel(solution.solverOutputs)
    output = solution.solverOutputs{outputIndex};
    if isstruct(output) && isfield(output, "relativegap")
        values(outputIndex) = double(output.relativegap);
    end
end
if any(isfinite(values))
    gap = max(values, [], "omitnan");
end
end

function value = maxOrNaN(values)
if isempty(values)
    value = NaN;
else
    value = max(values);
end
end

%% ----------------------------------------------------------------------
function rows = profileRows(dayString, caseId, caseData, config, solution, ...
        capKW)
timeEnd = caseData.time(:);
n = numel(timeEnd);
day = repmat(dayString, n, 1);
caseIds = repmat(caseId, n, 1);
intervalEnd = string(timeEnd, "yyyy-MM-dd HH:mm:ss");
intervalIndex = (1:n).';
aggregateLoadKW = sum(double(caseData.loadKW), 2);
pvAvailableACKW = double(config.etaPvAC) .* sum(double(caseData.pvKW), 2);
batteryNetDischargeKW = sum(double(solution.batteryDischargeKW) - ...
    double(solution.batteryChargeKW), 2);
aggregateImportKW = double(solution.aggregateImportKW(:));
capColumn = repmat(double(capKW), n, 1);
rows = table(day, caseIds, intervalEnd, intervalIndex, aggregateLoadKW, ...
    pvAvailableACKW, batteryNetDischargeKW, aggregateImportKW, capColumn, ...
    VariableNames=["Day", "CaseId", "IntervalEnd", "IntervalIndex", ...
    "AggregateLoadKW", "PvAvailableACKW", "BatteryNetDischargeKW", ...
    "AggregateImportKW", "CapKW"]);
end

function artifacts = persistCase(outputDirectory, dayString, planned, ...
        caseData, config, caseMeta, solution, metrics)
caseDirectory = string(fullfile(outputDirectory, "cases", dayString, ...
    planned.CaseId));
artifactMeta = caseMeta;
artifactMeta.experimentId = "B2022_FRONTIER_V1";
artifactMeta.strategy = planned.Strategy;
artifactMeta.caseId = planned.CaseId;
artifactMeta.caseKind = planned.CaseKind;
artifactMeta.capRatio = planned.CapRatio;
artifactMeta.demandChargeEURPerKW = planned.DemandChargeEURPerKW;
artifactMeta.etaBattery = planned.EtaBattery;
artifactMeta.qualityMode = "release_literal";
written = write_bahloul_case_artifacts(caseDirectory, caseData, config, ...
    artifactMeta, solution, metrics);
artifacts = struct;
artifacts.directory = caseDirectory;
artifacts.inputsSha256 = string(written.inputsSha256);
artifacts.solutionSha256 = string(written.solutionSha256);
end

%% ----------------------------------------------------------------------
function paths = outputPaths(directory)
paths = struct;
paths.directory = directory;
paths.metrics = string(fullfile(directory, "strategy_metrics.csv"));
paths.profiles = string(fullfile(directory, "profiles.csv"));
paths.checkpoint = string(fullfile(directory, "checkpoint.csv"));
paths.plan = string(fullfile(directory, "planned_cases.csv"));
end

function prepareOutputDirectory(directory, resume)
if isfolder(directory)
    entries = dir(directory);
    entries = entries(~ismember({entries.name}, {'.', '..', '.DS_Store'}));
    if ~isempty(entries) && ~resume
        error("StoreNet:FrontierOutputExists", ...
            "Refusing to overwrite nonempty output directory: %s", directory);
    end
else
    mkdir(directory);
end
end

function metricsTable = loadExistingMetrics(path, resume)
metricsTable = struct2table(emptyRow());
metricsTable(1, :) = [];
if ~resume || ~isfile(path)
    return
end
existing = readtable(path, TextType="string", DatetimeType="text");
template = emptyRow();
fields = string(fieldnames(template));
for rowIndex = 1:height(existing)
    row = template;
    for field = fields.'
        if ~ismember(field, string(existing.Properties.VariableNames))
            continue
        end
        value = existing.(field)(rowIndex);
        if isstring(template.(field))
            value = string(value);
            if ismissing(value)
                value = "";
            end
            row.(field) = value;
        else
            row.(field) = double(value);
        end
    end
    metricsTable = [metricsTable; struct2table(row)]; %#ok<AGROW>
end
end

function profiles = loadExistingProfiles(path, resume)
profiles = table(strings(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    VariableNames=["Day", "CaseId", "IntervalEnd", "IntervalIndex", ...
    "AggregateLoadKW", "PvAvailableACKW", "BatteryNetDischargeKW", ...
    "AggregateImportKW", "CapKW"]);
if ~resume || ~isfile(path)
    return
end
existing = readtable(path, TextType="string", DatetimeType="text");
existing.Day = string(existing.Day);
existing.CaseId = string(existing.CaseId);
existing.IntervalEnd = string(existing.IntervalEnd);
profiles = existing(:, profiles.Properties.VariableNames);
end

function finished = casesFinished(metricsTable, dayString, caseIds)
doneStatuses = ["ok", "infeasible", "time_limited", "quality_rejected"];
finished = false(numel(caseIds), 1);
if height(metricsTable) == 0
    return
end
for caseIndex = 1:numel(caseIds)
    finished(caseIndex) = any(metricsTable.Day == dayString & ...
        metricsTable.CaseId == caseIds(caseIndex) & ...
        ismember(metricsTable.Status, doneStatuses));
end
end

function metricsTable = appendRow(metricsTable, row)
% A failed row that is retried replaces its earlier failed record.
if height(metricsTable) > 0
    stale = metricsTable.Day == row.Day & metricsTable.CaseId == row.CaseId;
    metricsTable(stale, :) = [];
end
metricsTable = [metricsTable; struct2table(row)];
end

function checkpoint = writeCheckpoint(paths, metricsTable, profiles, ...
        options, plannedCaseCount, isFinal)
writeTableAtomic(metricsTable, paths.metrics);
writeTableAtomic(profiles, paths.profiles);
statuses = string(metricsTable.Status);
checkpoint = struct;
checkpoint.RunId = options.RunId;
checkpoint.PlannedCases = plannedCaseCount;
checkpoint.Ok = nnz(statuses == "ok");
checkpoint.Infeasible = nnz(statuses == "infeasible");
checkpoint.TimeLimited = nnz(statuses == "time_limited");
checkpoint.Failed = nnz(statuses == "failed" | statuses == "data_error");
checkpoint.QualityRejected = nnz(statuses == "quality_rejected");
checkpoint.Completed = checkpoint.Ok + checkpoint.Infeasible + ...
    checkpoint.TimeLimited + checkpoint.QualityRejected;
checkpoint.Remaining = plannedCaseCount - checkpoint.Completed;
checkpoint.IsFinal = isFinal && checkpoint.Remaining == 0;
writeTableAtomic(struct2table(checkpoint), paths.checkpoint);
end

function writeTableAtomic(value, path)
temporaryPath = regexprep(path, "\.csv$", ".tmp.csv");
writetable(value, temporaryPath);
movefile(temporaryPath, path, "f");
end

function manifestPath = writeManifest(options, paths, days, plan, ...
        metricsTable, elapsedSeconds)
writeTableAtomic(plan, paths.plan);
runInfo = struct;
runInfo.runType = "bahloul_frontier_v1";
runInfo.runId = options.RunId;
runInfo.decisionRecord = "docs/decisions/ADR-002-bill-peak-frontier-and-tariff.md";
runInfo.days = string(days, "yyyy-MM-dd");
runInfo.qualityMode = "release_literal";
runInfo.intervalMinutes = options.IntervalMinutes;
runInfo.cohortId = "H20_PV10";
runInfo.pvBoundaryId = "DC_SOURCE";
runInfo.transferLossFraction = 0.07;
runInfo.capDefinition = "CapRatio times the PV-self/no-battery aggregate import peak of the same day";
runInfo.capRatios = options.CapRatios;
runInfo.demandChargesEURPerKW = options.DemandCharges;
runInfo.batteryEfficiencies = options.BatteryEfficiencies;
runInfo.anchorStrategies = options.AnchorStrategies;
runInfo.efficiencyStrategies = options.EfficiencyStrategies;
runInfo.configOverrides = options.ConfigOverrides;
runInfo.persistSolutions = options.PersistSolutions;
runInfo.persistFrontierSolutions = options.PersistFrontierSolutions;
runInfo.elapsedSeconds = elapsedSeconds;
runInfo.statuses = metricsTable(:, ["Day", "CaseId", "Strategy", ...
    "Status", "ErrorIdentifier", "WallTimeSeconds"]);
[~, manifestPath] = write_run_manifest(options.OutputDirectory, runInfo);
end
