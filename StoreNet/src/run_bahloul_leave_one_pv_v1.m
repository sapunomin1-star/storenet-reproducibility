function run = run_bahloul_leave_one_pv_v1(day, options)
%RUN_BAHLOUL_LEAVE_ONE_PV_V1 Run the frozen unknown-9-PV sensitivity.
%   The runner keeps all 20 homes and batteries, uses nominal VPP_BM with
%   DC_SOURCE and xi=0.07, and sets one of the ten released PV homes' model
%   PV to zero in each of ten preregistered cases. One full-PV reference is
%   run separately and is not counted among the ten leave-one-PV cases.

arguments
    day (1, 1) datetime = datetime(2020, 8, 24)
    options.QualityMode (1, 1) string {mustBeMember(options.QualityMode, ...
        ["release_literal", "short_gap_only", "exclude_flagged_pv"])} = ...
        "exclude_flagged_pv"
    options.DataRoot (1, 1) string = ""
    options.OutputRoot (1, 1) string = ""
    options.RunId (1, 1) string = ""
    options.H4DiagnosticsPath (1, 1) string = ""
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
    options.RunId = "bahloul_leave_one_pv_v1_" + ...
        string(day, "yyyyMMdd") + "_" + ...
        string(datetime("now"), "yyyyMMdd_HHmmss_SSS");
end

runDirectory = prepareRunDirectory(options.OutputRoot, options.RunId);
metricsPath = string(fullfile(runDirectory, "leave_one_pv_metrics.csv"));
comparisonPath = string(fullfile(runDirectory, ...
    "leave_one_pv_vs_full.csv"));
figurePath = string(fullfile(runDirectory, "leave_one_pv_sensitivity.png"));

primaryScenario = frozenPrimaryScenario();
removedPvHomes = ["H1", "H2", "H3", "H4", "H5", ...
    "H7", "H10", "H11", "H13", "H17"];
specifications = buildCaseSpecifications(day, options.QualityMode, ...
    primaryScenario, removedPvHomes);

baseConfig = storenet_config(IntervalMinutes=30, ...
    DataRoot=options.DataRoot, QualityMode=options.QualityMode);
baseConfig = applyOverrides(baseConfig, options.ConfigOverrides);
[releaseData, dataMeta, dataStatus, dataIdentifier, dataMessage] = ...
    loadExperimentData(options.DataProvider, day, options.DataRoot, ...
    options.QualityMode);

rows = repmat(emptyMetricRow(), height(specifications), 1);
for caseIndex = 1:height(specifications)
    specification = specifications(caseIndex, :);
    row = metricRowFromSpecification(specification, day, ...
        options.QualityMode, runDirectory);
    if dataStatus ~= "ok"
        row.Status = dataStatus;
        row.ErrorIdentifier = dataIdentifier;
        row.ErrorMessage = dataMessage;
        rows(caseIndex) = row;
        continue
    end

    started = tic;
    try
        config = baseConfig;
        config.capacityRatio = 1;
        config.powerRatio = 1;
        config.scenarioId = specification.ScenarioId;
        config.pairId = specification.PairId;
        config.sensitivityRole = specification.SensitivityRole;
        config.removedPvHomeId = specification.RemovedPvHomeId;
        [caseData, caseConfig, caseMeta] = prepare_bahloul_case( ...
            releaseData, config, CohortId=specification.CohortId, ...
            PvBoundaryId=specification.PvBoundaryId, ...
            TransferLossFraction=specification.TransferLossFraction, ...
            H4DiagnosticsPath=options.H4DiagnosticsPath, ...
            DataMeta=dataMeta, Provenance=options.Provenance);
        validateFrozenReleasePvHomes(caseData, caseConfig, removedPvHomes);
        [caseData, caseConfig, caseMeta] = configurePvIdentityCase( ...
            caseData, caseConfig, caseMeta, specification, removedPvHomes);
        row = addPreparedEvidence(row, caseData, caseConfig, caseMeta);

        [solution, metrics] = options.Solver(caseData, caseConfig, "VPP_BM");
        row = addMetricsAndStages(row, metrics, solution);
        artifacts = write_bahloul_case_artifacts(row.CaseDirectory, ...
            caseData, caseConfig, caseMeta, solution, metrics);
        row = addArtifactPaths(row, artifacts);
        row.Status = "ok";
    catch exception
        row.Status = "failed";
        row.ErrorIdentifier = string(exception.identifier);
        row.ErrorMessage = string(exception.message);
    end
    row.WallTimeSeconds = toc(started);
    rows(caseIndex) = row;
end

metricsTable = struct2table(rows);
comparisonTable = compareWithFullPv(metricsTable);
writetable(metricsTable, metricsPath);
writetable(comparisonTable, comparisonPath);
writeSensitivityFigure(figurePath, comparisonTable, options.FigureVisible);

run = struct;
run.runType = "B2022-IR-v1_leave_one_pv";
run.day = day;
run.runId = options.RunId;
run.runDirectory = runDirectory;
run.metricsPath = metricsPath;
run.comparisonPath = comparisonPath;
run.figurePath = figurePath;
run.metricsTable = metricsTable;
run.comparisonTable = comparisonTable;
run.specifications = specifications;
run.removedPvHomes = removedPvHomes;
run.dataMeta = dataMeta;
end

function scenario = frozenPrimaryScenario()
scenarios = bahloul_scenarios("FIGURE7_PAIR");
selected = scenarios.IsPrimary;
if nnz(selected) ~= 1
    error("StoreNet:InvalidBahloulScenarioMatrix", ...
        "FIGURE7_PAIR must contain exactly one primary scenario.");
end
scenario = scenarios(selected, :);
if scenario.CohortId ~= "H20_PV10" || ...
        scenario.PvBoundaryId ~= "DC_SOURCE" || ...
        abs(scenario.TransferLossFraction - 0.07) > 1e-12
    error("StoreNet:InvalidLeaveOnePvScenario", ...
        "Leave-one-PV requires H20_PV10, DC_SOURCE, and xi=0.07.");
end
end

function specifications = buildCaseSpecifications(day, qualityMode, scenario, ...
        removedPvHomes)
rowCount = numel(removedPvHomes) + 1;
caseId = ["reference_full_pv"; "leave_one_pv_" + removedPvHomes(:)];
sensitivityRole = ["REFERENCE_FULL_PV"; ...
    repmat("LEAVE_ONE_PV", numel(removedPvHomes), 1)];
removedPvHomeId = [""; removedPvHomes(:)];
isLeaveOnePv = [false; true(numel(removedPvHomes), 1)];
scenarioId = ["DC_XI007_H20_FULL_PV"; ...
    "DC_XI007_H20_MINUS_" + removedPvHomes(:)];
pairId = repmat("DC_XI007_H20_PV_IDENTITY", rowCount, 1);
cohortId = repmat(scenario.CohortId, rowCount, 1);
pvBoundaryId = repmat(scenario.PvBoundaryId, rowCount, 1);
transferLossFraction = repmat(scenario.TransferLossFraction, rowCount, 1);
caseKey = strings(rowCount, 1);
for rowIndex = 1:rowCount
    caseKey(rowIndex) = stableCaseKey(day, qualityMode, caseId(rowIndex), ...
        sensitivityRole(rowIndex), removedPvHomeId(rowIndex), ...
        cohortId(rowIndex), pvBoundaryId(rowIndex), ...
        transferLossFraction(rowIndex), pairId(rowIndex));
end
specifications = table(caseId, caseKey, scenarioId, pairId, ...
    sensitivityRole, isLeaveOnePv, removedPvHomeId, cohortId, ...
    pvBoundaryId, transferLossFraction, ...
    VariableNames=["CaseId", "CaseKey", "ScenarioId", "PairId", ...
    "SensitivityRole", "IsLeaveOnePv", "RemovedPvHomeId", ...
    "CohortId", "PvBoundaryId", "TransferLossFraction"]);
end

function key = stableCaseKey(day, qualityMode, caseId, sensitivityRole, ...
        removedPvHomeId, cohortId, pvBoundaryId, xi, pairId)
removed = removedPvHomeId;
if strlength(removed) == 0
    removed = "NONE";
end
key = strjoin(["experiment=B2022_LEAVE_ONE_PV_V1", ...
    "date=" + string(day, "yyyy-MM-dd"), "quality=" + qualityMode, ...
    "strategy=VPP_BM", "cohort=" + cohortId, ...
    "pvBoundary=" + pvBoundaryId, "xi=" + compose("%.2f", xi), ...
    "capacityRatio=1.0", "powerRatio=1.0", "pairId=" + pairId, ...
    "role=" + sensitivityRole, "removedPv=" + removed, ...
    "caseId=" + caseId], "|");
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

function validateFrozenReleasePvHomes(data, config, expectedHomes)
if numel(data.houseIds) ~= 20 || config.nHomes ~= 20
    error("StoreNet:InvalidLeaveOnePvCohort", ...
        "Leave-one-PV cases require exactly 20 homes and 20 batteries.");
end
actualHomes = sort(string(config.pvHomes(:)));
if ~isequal(actualHomes, sort(expectedHomes(:)))
    error("StoreNet:InvalidLeaveOnePvHomes", ...
        "Released PV homes do not match the frozen ten-home list.");
end
end

function [data, config, meta] = configurePvIdentityCase(data, config, meta, ...
        specification, expectedHomes)
releasedPvKW = double(data.releasedPvKW);
releasePvMask = logical(config.pvHomeMask);
meta.releasePvHomeCount = nnz(releasePvMask);
meta.removedPvHomeId = specification.RemovedPvHomeId;
meta.sensitivityRole = specification.SensitivityRole;
meta.scenarioId = specification.ScenarioId;
meta.pairId = specification.PairId;
meta.caseId = specification.CaseId;
meta.caseKey = specification.CaseKey;
meta.experimentId = "B2022_LEAVE_ONE_PV_V1";
meta.dateOrPeriod = meta.day;
meta.qualityMode = string(config.qualityMode);
meta.strategy = "VPP_BM";
meta.capacityRatio = 1;
meta.powerRatio = 1;
meta.releasedPvHomes = expectedHomes;
config.removedPvHomeId = specification.RemovedPvHomeId;
config.sensitivityRole = specification.SensitivityRole;
config.scenarioId = specification.ScenarioId;
config.pairId = specification.PairId;

if specification.IsLeaveOnePv
    removedIndex = find(data.houseIds == specification.RemovedPvHomeId);
    if ~isscalar(removedIndex) || ~releasePvMask(removedIndex)
        error("StoreNet:InvalidRemovedPvHome", ...
            "Removed PV home must identify one frozen released PV column.");
    end
    data.pvKW(:, removedIndex) = 0;
    if isfield(data, "pvKWh")
        data.pvKWh(:, removedIndex) = 0;
    end
    if isfield(data, "pvHomeMask")
        data.pvHomeMask(removedIndex) = false;
    end
    config.pvHomeMask(removedIndex) = false;
    config.pvHomes = data.houseIds(config.pvHomeMask);
end

meta.activePvHomeCount = nnz(config.pvHomeMask);
meta.pvHomeCount = meta.activePvHomeCount;
meta.releasedPvPreserved = isequaln(double(data.releasedPvKW), releasedPvKW);
meta.removedModelPvMaxAbsKW = NaN;
meta.removedReleasedPvMaxKW = NaN;
if specification.IsLeaveOnePv
    removedIndex = find(data.houseIds == specification.RemovedPvHomeId);
    meta.removedModelPvMaxAbsKW = max(abs(data.pvKW(:, removedIndex)), [], "all");
    meta.removedReleasedPvMaxKW = max(data.releasedPvKW(:, removedIndex), ...
        [], "all");
end
end

function row = metricRowFromSpecification(specification, day, qualityMode, ...
        runDirectory)
row = emptyMetricRow();
row.Day = day;
row.ExperimentId = "B2022_LEAVE_ONE_PV_V1";
row.CaseId = specification.CaseId;
row.CaseKey = specification.CaseKey;
row.ScenarioId = specification.ScenarioId;
row.PairId = specification.PairId;
row.SensitivityRole = specification.SensitivityRole;
row.IsLeaveOnePv = specification.IsLeaveOnePv;
row.RemovedPvHomeId = specification.RemovedPvHomeId;
row.CohortId = specification.CohortId;
row.PvBoundaryId = specification.PvBoundaryId;
row.TransferLossFraction = specification.TransferLossFraction;
row.QualityMode = qualityMode;
row.Strategy = "VPP_BM";
row.CapacityRatio = 1;
row.PowerRatio = 1;
row.CaseDirectory = string(fullfile(runDirectory, "cases", ...
    specification.CaseId));
end

function row = addPreparedEvidence(row, data, config, meta)
row.HouseCount = double(meta.houseCount);
row.BatteryCount = double(config.nHomes);
row.ReleasePvHomeCount = double(meta.releasePvHomeCount);
row.ActivePvHomeCount = double(meta.activePvHomeCount);
row.H4MaskAffected = double(meta.h4MaskAffected);
row.H4AlignmentCategory = string(meta.h4AlignmentCategory);
row.ReleasedPvPreserved = logical(meta.releasedPvPreserved);
row.RemovedModelPvMaxAbsKW = double(meta.removedModelPvMaxAbsKW);
row.RemovedReleasedPvMaxKW = double(meta.removedReleasedPvMaxKW);
row.BatteryCapacityKWhPerHome = double(config.batteryCapacityKWh);
row.BatteryPowerKWPerHome = double(config.batteryPowerKW);
row.ModelPvEnergyKWh = double(data.dtHours) .* sum(data.pvKW, "all");
row.ReleasedPvEnergyKWh = double(data.dtHours) .* ...
    sum(data.releasedPvKW, "all");
end

function row = addMetricsAndStages(row, metrics, solution)
paper = metrics.PaperLoadOnlyBaseline;
pvSelf = metrics.PvSelfNoBatteryBaseline;
row.PaperLoadOnlyBaselineBillEUR = double(paper.billEUR);
row.PaperLoadOnlySavingsEUR = double(paper.savingsEUR);
row.PaperLoadOnlySavingsPercent = double(paper.savingsPercent);
row.PaperSavingsPercentDenominatorIsZero = double( ...
    paper.savingsPercentDenominatorIsZero);
row.OriginalLoadPeakKW = double(paper.peakImportKW);
row.OriginalLoadDaytimePeakKW = double(paper.daytimePeakImportKW);
row.PvSelfNoBatteryBaselineBillEUR = double(pvSelf.billEUR);
row.EngineeringSavingsEUR = double(pvSelf.savingsEUR);
row.EngineeringSavingsPercent = double(pvSelf.savingsPercent);
row.EngineeringSavingsPercentDenominatorIsZero = double( ...
    pvSelf.savingsPercentDenominatorIsZero);
row.PvSelfNoBatteryPeakKW = double(pvSelf.peakImportKW);
row.PvSelfNoBatteryDaytimePeakKW = double(pvSelf.daytimePeakImportKW);
row.OptimizedBillEUR = requiredMetric(metrics, "optimizedBillEUR");
row.OptimizedPeakImportKW = requiredMetric(metrics, "peakImportKW");
row.OptimizedDaytimePeakImportKW = requiredMetric(metrics, ...
    "daytimePeakImportKW");
row.OptimizedImportSpreadKW = requiredMetric(metrics, "importSpreadKW");
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
        "Successful leave-one-PV cases require objectiveStages evidence.");
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

function row = emptyMetricRow()
row = struct;
row.Day = NaT;
row.ExperimentId = "";
row.CaseId = "";
row.CaseKey = "";
row.ScenarioId = "";
row.PairId = "";
row.SensitivityRole = "";
row.IsLeaveOnePv = false;
row.RemovedPvHomeId = "";
row.CohortId = "";
row.HouseCount = NaN;
row.BatteryCount = NaN;
row.ReleasePvHomeCount = NaN;
row.ActivePvHomeCount = NaN;
row.H4MaskAffected = NaN;
row.H4AlignmentCategory = "";
row.PvBoundaryId = "";
row.TransferLossFraction = NaN;
row.QualityMode = "";
row.Strategy = "";
row.CapacityRatio = NaN;
row.PowerRatio = NaN;
row.BatteryCapacityKWhPerHome = NaN;
row.BatteryPowerKWPerHome = NaN;
row.ReleasedPvPreserved = false;
row.RemovedModelPvMaxAbsKW = NaN;
row.RemovedReleasedPvMaxKW = NaN;
row.ModelPvEnergyKWh = NaN;
row.ReleasedPvEnergyKWh = NaN;
row.Status = "not_run";
row.ErrorIdentifier = "";
row.ErrorMessage = "";
row.WallTimeSeconds = NaN;
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
row.PvSelfNoBatteryDaytimePeakKW = NaN;
row.OptimizedBillEUR = NaN;
row.OptimizedPeakImportKW = NaN;
row.OptimizedDaytimePeakImportKW = NaN;
row.OptimizedImportSpreadKW = NaN;
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

function comparison = compareWithFullPv(metrics)
reference = metrics(metrics.SensitivityRole == "REFERENCE_FULL_PV", :);
leaveOne = metrics(metrics.SensitivityRole == "LEAVE_ONE_PV", :);
if height(reference) ~= 1 || height(leaveOne) ~= 10
    error("StoreNet:IncompleteLeaveOnePvMatrix", ...
        "Expected one full-PV reference and ten leave-one-PV rows.");
end
comparison = leaveOne(:, ["CaseId", "CaseKey", "RemovedPvHomeId", ...
    "Status", "ErrorIdentifier", "ErrorMessage", "HouseCount", ...
    "BatteryCount", "ReleasePvHomeCount", "ActivePvHomeCount", ...
    "H4MaskAffected", "CohortId", "PvBoundaryId", ...
    "TransferLossFraction"]);
comparison.ReferenceCaseId = repmat(reference.CaseId, height(leaveOne), 1);
comparison.ReferenceStatus = repmat(reference.Status, height(leaveOne), 1);
comparison.ReferencePaperSavingsPercent = repmat( ...
    reference.PaperLoadOnlySavingsPercent, height(leaveOne), 1);
comparison.LeaveOnePaperSavingsPercent = ...
    leaveOne.PaperLoadOnlySavingsPercent;
comparison.DeltaPaperSavingsPercentagePoints = ...
    comparison.LeaveOnePaperSavingsPercent - ...
    comparison.ReferencePaperSavingsPercent;
comparison.ReferenceOptimizedBillEUR = repmat( ...
    reference.OptimizedBillEUR, height(leaveOne), 1);
comparison.LeaveOneOptimizedBillEUR = leaveOne.OptimizedBillEUR;
comparison.DeltaOptimizedBillEUR = comparison.LeaveOneOptimizedBillEUR - ...
    comparison.ReferenceOptimizedBillEUR;
comparison.ReferencePeakImportKW = repmat( ...
    reference.OptimizedPeakImportKW, height(leaveOne), 1);
comparison.LeaveOnePeakImportKW = leaveOne.OptimizedPeakImportKW;
comparison.DeltaPeakImportKW = comparison.LeaveOnePeakImportKW - ...
    comparison.ReferencePeakImportKW;
end

function writeSensitivityFigure(path, comparison, visible)
visibility = "off";
if visible
    visibility = "on";
end
figureHandle = figure(Visible=visibility, Color="w", ...
    Position=[100, 100, 1300, 700]);
cleaner = onCleanup(@() close(figureHandle));
layout = tiledlayout(figureHandle, 2, 1, Padding="compact", ...
    TileSpacing="compact");
labels = categorical(comparison.RemovedPvHomeId, ...
    comparison.RemovedPvHomeId, Ordinal=true);

topAxes = nexttile(layout);
bar(topAxes, labels, comparison.DeltaPaperSavingsPercentagePoints, ...
    FaceColor=[0.20, 0.55, 0.80]);
yline(topAxes, 0, "k-");
ylabel(topAxes, "Delta savings (percentage points)");
title(topAxes, "Leave-one-PV vs full-PV nominal VPP-BM");
grid(topAxes, "on");

bottomAxes = nexttile(layout);
bar(bottomAxes, labels, comparison.DeltaPeakImportKW, ...
    FaceColor=[0.85, 0.40, 0.25]);
yline(bottomAxes, 0, "k-");
xlabel(bottomAxes, "Model PV set to zero");
ylabel(bottomAxes, "Delta peak import (kW)");
grid(bottomAxes, "on");

exportgraphics(figureHandle, path, Resolution=300, BackgroundColor="white");
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
