function run = run_bahloul_peak_guard_monthly_v1(options)
%RUN_BAHLOUL_PEAK_GUARD_MONTHLY_V1 Fill only the missing monthly guard cases.
%   Formal VPP-BM rows are reused from the frozen B2022 result. For each
%   formally available date, the public input is reloaded and its two
%   baselines are checked against the frozen row before the existing
%   IMPROVED_PEAK_GUARD strategy is solved. No VPP-BM case is re-solved.

arguments
    options.Dates datetime = NaT(0, 1)
    options.FormalDailyMetricsPath (1, 1) string = ""
    options.FormalSourceMetricsPath (1, 1) string = ""
    options.FormalSourceManifestPath (1, 1) string = ""
    options.DataRoot (1, 1) string = ""
    options.OutputDirectory (1, 1) string = ""
    options.DataProvider (1, 1) function_handle = @load_storenet_day
    options.Solver (1, 1) function_handle = @solve_storenet
    options.PersistSolutions (1, 1) logical = true
    options.Resume (1, 1) logical = true
end

sourceFolder = string(fileparts(mfilename("fullpath")));
projectFolder = string(fullfile(sourceFolder, ".."));
options = applyDefaultPaths(options, projectFolder);
validateInputFiles(options);

formalDaily = readMetricsTable(options.FormalDailyMetricsPath);
formalSource = readMetricsTable(options.FormalSourceMetricsPath);
formalVpp = selectFormalVppRows(formalDaily, options.Dates);
formalVppRows = makeFormalVppRows(formalVpp, formalSource, ...
    options.FormalDailyMetricsPath, options.FormalSourceMetricsPath);
eligibleDates = formalVpp.Day(formalVpp.Status == "ok");

frozenConfig = loadFrozenConfig(options.FormalSourceManifestPath, ...
    options.DataRoot);
prepareOutputDirectory(options.OutputDirectory, options.Resume);
paths = outputPaths(options.OutputDirectory);
peakGuardRows = loadExistingPeakGuardRows(paths.strategyMetrics, ...
    formalVpp.Day, options.Resume);
peakGuardRows = addUnavailableRows(peakGuardRows, formalVpp);
writeCheckpointOutputs(formalVppRows, peakGuardRows, paths, ...
    eligibleDates, formalVpp, false);

for dateIndex = 1:numel(eligibleDates)
    calendarDay = eligibleDates(dateIndex);
    completed = false;
    if ~isempty(peakGuardRows)
        completed = any([peakGuardRows.Day].' == calendarDay & ...
            string({peakGuardRows.Status}).' == "ok");
    end
    if completed
        continue
    end
    peakGuardRows = removeDateRows(peakGuardRows, calendarDay);
    formalRow = formalVpp(formalVpp.Day == calendarDay, :);
    caseDirectory = peakGuardCaseDirectory(options.OutputDirectory, ...
        calendarDay);
    try
        if hasMaterialEntries(caseDirectory)
            [metrics, evidence] = reevaluate_bahloul_artifact(caseDirectory);
            validateRecoveredArtifact(evidence, formalRow);
            row = evaluatedMetricRow(calendarDay, metrics, ...
                evidence.solution, formalRow.PvSelfNoBatteryPeakKW, 0, ...
                caseDirectory, true);
        else
            [data, dataMeta] = callDataProvider(options.DataProvider, ...
                calendarDay, options.DataRoot);
            validateLoadedData(data, dataMeta, calendarDay, frozenConfig);
            validateFrozenBaselines(data, frozenConfig, formalRow);

            peakGuardConfig = frozenConfig;
            peakGuardConfig.aggregateImportCapKW = ...
                double(formalRow.PvSelfNoBatteryPeakKW);
            peakGuardConfig.pvBoundaryId = "DC_SOURCE";
            peakGuardConfig.cohortId = "H20_PV10";
            started = tic;
            [solution, solverMetrics] = options.Solver(data, ...
                peakGuardConfig, "IMPROVED_PEAK_GUARD");
            wallTimeSeconds = toc(started);
            metrics = evaluate_storenet(data, peakGuardConfig, solution);
            validateSolverEvaluation(solverMetrics, metrics);
            validatePeakGuardResult(metrics, peakGuardConfig);

            artifactDirectory = "";
            if options.PersistSolutions
                caseMeta = monthlyCaseMetadata(data, dataMeta, calendarDay);
                caseMeta.strategy = "IMPROVED_PEAK_GUARD";
                caseMeta.caseId = "B2022_PEAK_GUARD_MONTHLY_V1_" + ...
                    string(calendarDay, "yyyyMMdd");
                write_bahloul_case_artifacts(caseDirectory, data, ...
                    peakGuardConfig, caseMeta, solution, metrics);
                artifactDirectory = caseDirectory;
            end
            row = evaluatedMetricRow(calendarDay, metrics, solution, ...
                peakGuardConfig.aggregateImportCapKW, wallTimeSeconds, ...
                artifactDirectory, false);
        end
    catch exception
        row = failureMetricRow(calendarDay, ...
            double(formalRow.PvSelfNoBatteryPeakKW), exception);
    end
    row.Dataset = "StoreNet";
    row.Day = calendarDay;
    row.Sequence = 2;
    row.Strategy = "IMPROVED_PEAK_GUARD";
    peakGuardRows(end + 1, 1) = row; %#ok<AGROW>
    writeCheckpointOutputs(formalVppRows, peakGuardRows, paths, ...
        eligibleDates, formalVpp, false);
end

[strategyMetrics, pairComparison, checkpoint] = writeCheckpointOutputs( ...
    formalVppRows, peakGuardRows, paths, eligibleDates, formalVpp, true);
if ~logical(checkpoint.IsFinal)
    failedRows = strategyMetrics.Strategy == "IMPROVED_PEAK_GUARD" & ...
        strategyMetrics.Status == "failed";
    failedDates = string(strategyMetrics.Day(failedRows), "yyyy-MM-dd");
    error("StoreNet:PeakGuardMonthlyIncomplete", ...
        "Peak Guard monthly run is incomplete. Failed date(s): %s.", ...
        strjoin(failedDates, ", "));
end
monthlySummary = summarizeMonthlyPairs(strategyMetrics, pairComparison);
writeTableAtomic(monthlySummary, paths.monthlySummary);
residualSummary = summarizePeakGuardResiduals(strategyMetrics);
writeTableAtomic(residualSummary, paths.residualSummary);

run = struct;
run.runDirectory = options.OutputDirectory;
run.strategyMetricsPath = paths.strategyMetrics;
run.pairComparisonPath = paths.pairComparison;
run.checkpointPath = paths.checkpoint;
run.monthlySummaryPath = paths.monthlySummary;
run.residualSummaryPath = paths.residualSummary;
run.strategyMetrics = strategyMetrics;
run.pairComparison = pairComparison;
run.checkpoint = checkpoint;
run.monthlySummary = monthlySummary;
run.residualSummary = residualSummary;
run.formalVppWasReusedWithoutSolve = true;
run.peakGuardSolvedDateCount = height(pairComparison);
run.configuration = frozenConfig;
end

function options = applyDefaultPaths(options, projectFolder)
formalRoot = fullfile(projectFolder, "results", "b2022_ir_v1_formal");
if strlength(options.FormalDailyMetricsPath) == 0
    options.FormalDailyMetricsPath = fullfile(formalRoot, ...
        "b2022_monthly_v1_2020", "daily_metrics.csv");
end
if strlength(options.FormalSourceMetricsPath) == 0
    options.FormalSourceMetricsPath = fullfile(formalRoot, "evidence", ...
        "monthly_daily_metrics_source.csv");
end
if strlength(options.FormalSourceManifestPath) == 0
    options.FormalSourceManifestPath = fullfile(formalRoot, "evidence", ...
        "monthly_daily_manifest.json");
end
if strlength(options.DataRoot) == 0
    options.DataRoot = fullfile(projectFolder, "data", "raw");
end
if strlength(options.OutputDirectory) == 0
    options.OutputDirectory = fullfile(projectFolder, "results", ...
        "bahloul_vpp_improvement_v1", "storenet_monthly");
end
end

function validateInputFiles(options)
paths = [options.FormalDailyMetricsPath, ...
    options.FormalSourceMetricsPath, options.FormalSourceManifestPath];
for pathIndex = 1:numel(paths)
    if ~isfile(paths(pathIndex))
        error("StoreNet:MissingPeakGuardInput", ...
            "Required frozen input does not exist: %s", paths(pathIndex));
    end
end
if ~isfolder(options.DataRoot)
    error("StoreNet:MissingPeakGuardDataRoot", ...
        "StoreNet data root does not exist: %s", options.DataRoot);
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
textValues = string(values);
try
    days = datetime(textValues, InputFormat="dd-MMM-uuuu");
catch
    days = datetime(textValues);
end
days = dateshift(days, "start", "day");
end

function formalVpp = selectFormalVppRows(formalDaily, requestedDates)
required = ["Day", "ScenarioId", "CohortId", "IsPrimary", ...
    "PvBoundaryId", "TransferLossFraction", "QualityMode", "Strategy", ...
    "Status", "HouseCount", "PvHomeCount", ...
    "PaperLoadOnlyBaselineBillEUR", "PaperLoadOnlySavingsPercent", ...
    "PaperLoadOnlyPeakKW", "PaperLoadOnlyDaytimePeakKW", ...
    "PvSelfNoBatteryBaselineBillEUR", ...
    "PvSelfNoBatterySavingsPercent", "PvSelfNoBatteryPeakKW", ...
    "PvSelfNoBatteryDaytimePeakKW", "OptimizedBillEUR", ...
    "OutcomePeakImportKW", "OutcomeDaytimePeakImportKW", ...
    "TotalGridImportKWh", "TotalBatteryThroughputKWh", ...
    "TotalCurtailedPvKWh", "EnergyBalanceResidualKW", ...
    "TerminalSocErrorKWh", "SimultaneousChargeDischargeKW", ...
    "MinimumExitFlag"];
assertTableVariables(formalDaily, required, "formal daily metrics");
formalDaily.Strategy = string(formalDaily.Strategy);
formalDaily.Status = string(formalDaily.Status);
selected = formalDaily.Strategy == "VPP_BM" & ...
    string(formalDaily.ScenarioId) == "DC_XI007_H20" & ...
    string(formalDaily.CohortId) == "H20_PV10" & ...
    logical(formalDaily.IsPrimary) & ...
    string(formalDaily.PvBoundaryId) == "DC_SOURCE" & ...
    abs(double(formalDaily.TransferLossFraction) - 0.07) <= 1e-12 & ...
    string(formalDaily.QualityMode) == "release_literal";
formalVpp = formalDaily(selected, :);
if isempty(formalVpp)
    error("StoreNet:MissingFormalVppRows", ...
        "No frozen DC_XI007_H20 monthly VPP_BM rows were found.");
end
if ~isempty(requestedDates)
    requestedDates = unique(dateshift(requestedDates(:), ...
        "start", "day"), "sorted");
    formalVpp = formalVpp(ismember(formalVpp.Day, requestedDates), :);
    if height(formalVpp) ~= numel(requestedDates)
        error("StoreNet:MissingRequestedFormalDate", ...
            "Every requested date must have one frozen VPP_BM row.");
    end
end
formalVpp = sortrows(formalVpp, "Day");
if numel(unique(formalVpp.Day)) ~= height(formalVpp)
    error("StoreNet:DuplicateFormalVppDate", ...
        "Frozen VPP_BM rows must contain one row per date.");
end
end

function rows = makeFormalVppRows(formalVpp, sourceMetrics, formalPath, ...
        sourcePath)
assertTableVariables(sourceMetrics, ["Day", "Strategy", "ImportSpreadKW"], ...
    "formal source metrics");
sourceMetrics.Strategy = string(sourceMetrics.Strategy);
sourceVpp = sourceMetrics(sourceMetrics.Strategy == "VPP_BM", :);
rows = repmat(emptyMetricRow(), height(formalVpp), 1);
for rowIndex = 1:height(formalVpp)
    formalRow = formalVpp(rowIndex, :);
    sourceRow = sourceVpp(sourceVpp.Day == formalRow.Day, :);
    if height(sourceRow) ~= 1
        error("StoreNet:MissingFormalLoadRange", ...
            "Expected one frozen source VPP_BM row for %s.", ...
            string(formalRow.Day, "yyyy-MM-dd"));
    end
    row = emptyMetricRow();
    row.Dataset = "StoreNet";
    row.Day = formalRow.Day;
    row.Sequence = 1;
    row.Strategy = "VPP_BM";
    row.Status = string(formalRow.Status);
    row.SourceEvidence = formalPath + ";" + sourcePath;
    row.ReusedWithoutSolve = true;
    row.IntervalMinutes = 60;
    row.HouseCount = double(formalRow.HouseCount);
    row.PvHomeCount = double(formalRow.PvHomeCount);
    row.PvBoundaryId = "DC_SOURCE";
    row.TransferLossFraction = double(formalRow.TransferLossFraction);
    row.BatteryCapacityKWhPerHome = 10;
    row.BatteryPowerKWPerHome = 3.3;
    row.PeakGuardCapKW = double(formalRow.PvSelfNoBatteryPeakKW);
    row.PaperLoadOnlyBaselineBillEUR = ...
        double(formalRow.PaperLoadOnlyBaselineBillEUR);
    row.PaperSavingsPercent = ...
        double(formalRow.PaperLoadOnlySavingsPercent);
    row.PvSelfNoBatteryBaselineBillEUR = ...
        double(formalRow.PvSelfNoBatteryBaselineBillEUR);
    row.EngineeringSavingsPercent = ...
        double(formalRow.PvSelfNoBatterySavingsPercent);
    row.OriginalLoadPeakKW = double(formalRow.PaperLoadOnlyPeakKW);
    row.PvSelfNoBatteryPeakKW = ...
        double(formalRow.PvSelfNoBatteryPeakKW);
    row.OptimizedBillEUR = double(formalRow.OptimizedBillEUR);
    row.AllDayPeakKW = double(formalRow.OutcomePeakImportKW);
    row.DaytimePeakKW = double(formalRow.OutcomeDaytimePeakImportKW);
    row.LoadRangeKW = double(sourceRow.ImportSpreadKW);
    row.TotalGridImportKWh = double(formalRow.TotalGridImportKWh);
    row.BatteryThroughputKWh = ...
        double(formalRow.TotalBatteryThroughputKWh);
    row.PvCurtailmentKWh = double(formalRow.TotalCurtailedPvKWh);
    row.EnergyBalanceResidualKW = ...
        double(formalRow.EnergyBalanceResidualKW);
    row.TerminalSocErrorKWh = double(formalRow.TerminalSocErrorKWh);
    row.SimultaneousChargeDischargeKW = ...
        double(formalRow.SimultaneousChargeDischargeKW);
    row.MinimumExitFlag = double(formalRow.MinimumExitFlag);
    row.PeakExcessOverCapKW = row.AllDayPeakKW - row.PeakGuardCapKW;
    rows(rowIndex, 1) = row;
end
end

function config = loadFrozenConfig(manifestPath, dataRoot)
manifest = jsondecode(fileread(manifestPath));
if ~isfield(manifest, "experiment") || ...
        ~isfield(manifest.experiment, "configuration")
    error("StoreNet:InvalidFormalSourceManifest", ...
        "Formal source manifest has no experiment.configuration.");
end
if string(manifest.experiment.qualityMode) ~= "release_literal" || ...
        double(manifest.experiment.intervalMinutes) ~= 60
    error("StoreNet:FormalSourceManifestMismatch", ...
        "Formal monthly source must be 60-minute release_literal data.");
end
frozen = manifest.experiment.configuration;
config = storenet_config(IntervalMinutes=60, DataRoot=dataRoot, ...
    QualityMode="release_literal");
numericFields = ["etaPvAC", "etaPvDC", "etaBatteryCharge", ...
    "etaBatteryDischarge", "transferLossFraction", ...
    "batteryCapacityKWh", "batteryPowerKW", "socInitialFraction", ...
    "socMinFraction", "socMaxFraction", "socTerminalFraction", ...
    "nightPrice", "dayPrice", "feedInPrice", "dayStartHour", ...
    "dayEndHour", "mipRelativeGap", "constraintTolerance", ...
    "lexicographicTolerance"];
for fieldIndex = 1:numel(numericFields)
    field = numericFields(fieldIndex);
    if ~isfield(frozen, field) || ...
            abs(double(config.(field)) - double(frozen.(field))) > 1e-12
        error("StoreNet:FormalConfigurationMismatch", ...
            "Current canonical config does not match frozen field %s.", field);
    end
end
config.maxSolverTimeSeconds = double(frozen.maxSolverTimeSeconds);
if config.maxSolverTimeSeconds ~= 60 || config.nHomes ~= 20 || ...
        nnz(config.pvHomeMask) ~= 10
    error("StoreNet:FormalConfigurationMismatch", ...
        "Frozen monthly policy must remain 20 homes/10 PV and 60 seconds.");
end
end

function prepareOutputDirectory(directory, resume)
if isfolder(directory)
    if hasMaterialEntries(directory) && ~resume
        error("StoreNet:PeakGuardOutputExists", ...
            "Refusing to overwrite nonempty output directory: %s", directory);
    end
else
    mkdir(directory);
end
end

function paths = outputPaths(directory)
paths = struct;
paths.strategyMetrics = string(fullfile(directory, "strategy_metrics.csv"));
paths.pairComparison = string(fullfile(directory, "paired_comparison.csv"));
paths.checkpoint = string(fullfile(directory, "checkpoint.csv"));
paths.monthlySummary = string(fullfile(directory, "monthly_summary.csv"));
paths.residualSummary = string(fullfile(directory, "residual_summary.csv"));
end

function rows = loadExistingPeakGuardRows(path, requestedDates, resume)
rows = repmat(emptyMetricRow(), 0, 1);
if ~resume || ~isfile(path)
    return
end
existing = readMetricsTable(path);
assertTableVariables(existing, ["Day", "Strategy", "Status"], ...
    "existing Peak Guard checkpoint");
existing.Strategy = string(existing.Strategy);
selected = existing.Strategy == "IMPROVED_PEAK_GUARD" & ...
    ismember(existing.Day, requestedDates);
existing = existing(selected, :);
if numel(unique(existing.Day)) ~= height(existing)
    error("StoreNet:DuplicatePeakGuardCheckpoint", ...
        "Existing checkpoint has duplicate Peak Guard dates.");
end
if ~isempty(existing)
    rows = repmat(emptyMetricRow(), height(existing), 1);
    for rowIndex = 1:height(existing)
        rows(rowIndex, 1) = normalizedExistingRow(existing, rowIndex);
    end
end
end

function row = normalizedExistingRow(existing, rowIndex)
row = emptyMetricRow();
fields = string(fieldnames(row));
variables = string(existing.Properties.VariableNames);
for fieldIndex = 1:numel(fields)
    field = fields(fieldIndex);
    if ~ismember(field, variables)
        continue
    end
    value = existing.(field)(rowIndex);
    defaultValue = row.(field);
    if isstring(defaultValue)
        row.(field) = string(value);
    elseif isdatetime(defaultValue)
        row.(field) = normalizeDay(value);
    elseif islogical(defaultValue)
        row.(field) = logical(value);
    else
        row.(field) = double(value);
    end
end
end

function rows = addUnavailableRows(rows, formalVpp)
unavailable = formalVpp.Status ~= "ok";
for rowIndex = find(unavailable).'
    calendarDay = formalVpp.Day(rowIndex);
    rows = removeDateRows(rows, calendarDay);
    row = emptyMetricRow();
    row.Dataset = "StoreNet";
    row.Day = calendarDay;
    row.Sequence = 2;
    row.Strategy = "IMPROVED_PEAK_GUARD";
    row.Status = "skipped_formal_unavailable";
    row.SourceEvidence = "formal VPP_BM status=" + ...
        string(formalVpp.Status(rowIndex));
    row.ReusedWithoutSolve = true;
    row.IntervalMinutes = 60;
    row.HouseCount = 20;
    row.PvHomeCount = 10;
    row.PvBoundaryId = "DC_SOURCE";
    row.TransferLossFraction = 0.07;
    row.BatteryCapacityKWhPerHome = 10;
    row.BatteryPowerKWPerHome = 3.3;
    rows(end + 1, 1) = row; %#ok<AGROW>
end
end

function rows = removeDateRows(rows, calendarDay)
if isempty(rows)
    rows = rows(:);
    return
end
rows([rows.Day].' == calendarDay) = [];
rows = rows(:);
end

function directory = peakGuardCaseDirectory(outputDirectory, calendarDay)
directory = string(fullfile(outputDirectory, "cases", ...
    string(calendarDay, "yyyy-MM-dd"), "IMPROVED_PEAK_GUARD"));
end

function tf = hasMaterialEntries(directory)
if ~isfolder(directory)
    tf = false;
    return
end
entries = dir(directory);
names = string({entries.name});
tf = any(~ismember(names, [".", ".."]) & ~startsWith(names, ".nfs"));
end

function validateRecoveredArtifact(evidence, formalRow)
config = evidence.input.config;
required = ["aggregateImportCapKW", "transferLossFraction", ...
    "batteryCapacityKWh", "batteryPowerKW", "pvBoundaryId", "cohortId"];
missing = required(~isfield(config, cellstr(required)));
if ~isempty(missing)
    error("StoreNet:InvalidRecoveredPeakGuard", ...
        "Recovered Peak Guard config is missing: %s.", strjoin(missing, ", "));
end
expectedCapKW = double(formalRow.PvSelfNoBatteryPeakKW);
if abs(double(config.aggregateImportCapKW) - expectedCapKW) > ...
        1e-10 * max(1, abs(expectedCapKW)) || ...
        abs(double(config.transferLossFraction) - 0.07) > 1e-12 || ...
        double(config.batteryCapacityKWh) ~= 10 || ...
        double(config.batteryPowerKW) ~= 3.3 || ...
        string(config.pvBoundaryId) ~= "DC_SOURCE" || ...
        string(config.cohortId) ~= "H20_PV10"
    error("StoreNet:RecoveredPeakGuardMismatch", ...
        "Recovered artifact does not match the frozen monthly case.");
end
end

function [data, meta] = callDataProvider(provider, calendarDay, dataRoot)
[data, meta] = provider(calendarDay, DataRoot=dataRoot, ...
    IntervalMinutes=60, QualityMode="release_literal");
end

function validateLoadedData(data, meta, calendarDay, config)
required = ["time", "loadKW", "pvKW", "dtHours", "houseIds"];
missing = required(~isfield(data, cellstr(required)));
if ~isempty(missing)
    error("StoreNet:InvalidPeakGuardData", ...
        "Loaded StoreNet day is missing: %s.", strjoin(missing, ", "));
end
if isfield(meta, "qualityPassed") && ~logical(meta.qualityPassed)
    error("StoreNet:PeakGuardQualityRejected", ...
        "Frozen available date %s failed release_literal on reload.", ...
        string(calendarDay, "yyyy-MM-dd"));
end
expectedHomes = compose("H%d", 1:20);
if double(data.dtHours) ~= 1 || size(data.loadKW, 1) ~= 24 || ...
        size(data.loadKW, 2) ~= 20 || ...
        ~isequal(string(data.houseIds(:)).', expectedHomes) || ...
        numel(data.time) ~= 24 || ...
        dateshift(data.time(1) - hours(1), "start", "day") ~= calendarDay
    error("StoreNet:PeakGuardDataIdentityMismatch", ...
        "Reloaded day does not match the frozen 24x20 hourly identity.");
end
pvMask = any(double(data.pvKW) ~= 0, 1);
if isfield(data, "pvHomeMask")
    pvMask = logical(data.pvHomeMask);
end
if nnz(pvMask) ~= 10 || nnz(config.pvHomeMask) ~= 10
    error("StoreNet:PeakGuardCohortMismatch", ...
        "Peak Guard requires the frozen 20-home/10-PV cohort.");
end
end

function validateFrozenBaselines(data, config, formalRow)
baseline = computeBaselines(data, config);
checks = [ ...
    baseline.paperBillEUR, double(formalRow.PaperLoadOnlyBaselineBillEUR); ...
    baseline.paperPeakKW, double(formalRow.PaperLoadOnlyPeakKW); ...
    baseline.paperDaytimePeakKW, ...
        double(formalRow.PaperLoadOnlyDaytimePeakKW); ...
    baseline.pvSelfBillEUR, ...
        double(formalRow.PvSelfNoBatteryBaselineBillEUR); ...
    baseline.pvSelfPeakKW, double(formalRow.PvSelfNoBatteryPeakKW); ...
    baseline.pvSelfDaytimePeakKW, ...
        double(formalRow.PvSelfNoBatteryDaytimePeakKW)];
for checkIndex = 1:size(checks, 1)
    if ~isfinite(checks(checkIndex, 2))
        continue
    end
    tolerance = 1e-9 .* max(1, abs(checks(checkIndex, 2)));
    difference = abs(checks(checkIndex, 1) - checks(checkIndex, 2));
    if ~isfinite(checks(checkIndex, 1)) || ...
            any(difference > tolerance, "all")
        error("StoreNet:FormalBaselineMismatch", ...
            "Reloaded input does not reproduce frozen baseline check %d.", ...
            checkIndex);
    end
end
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
baseline.paperBillEUR = dtHours .* sum(price .* paperImportKW);
baseline.paperPeakKW = max(paperImportKW);
baseline.paperDaytimePeakKW = max(paperImportKW(dayMask));
baseline.pvSelfBillEUR = dtHours .* sum(price .* pvSelfImportKW);
baseline.pvSelfPeakKW = max(pvSelfImportKW);
baseline.pvSelfDaytimePeakKW = max(pvSelfImportKW(dayMask));
end

function validateSolverEvaluation(solverMetrics, evaluatedMetrics)
if ~isstruct(solverMetrics) || ...
        ~isfield(solverMetrics, "optimizedBillEUR") || ...
        ~isfield(solverMetrics, "peakImportKW")
    error("StoreNet:InvalidPeakGuardSolverMetrics", ...
        "Peak Guard solver did not return independently checkable metrics.");
end
values = [double(solverMetrics.optimizedBillEUR), ...
    double(evaluatedMetrics.optimizedBillEUR); ...
    double(solverMetrics.peakImportKW), double(evaluatedMetrics.peakImportKW)];
for rowIndex = 1:size(values, 1)
    tolerance = 1e-9 .* max(1, abs(values(rowIndex, 2)));
    difference = abs(values(rowIndex, 1) - values(rowIndex, 2));
    if any(~isfinite(values(rowIndex, :))) || ...
            any(difference > tolerance, "all")
        error("StoreNet:PeakGuardEvaluationMismatch", ...
            "Solver and independent evaluation disagree on metric %d.", ...
            rowIndex);
    end
end
end

function validatePeakGuardResult(metrics, config)
capKW = double(config.aggregateImportCapKW);
if metrics.peakImportKW > capKW + 1e-6 || ...
        metrics.energyBalanceResidualKW > 1e-6 || ...
        metrics.terminalSocErrorKWh > 1e-6 || ...
        metrics.simultaneousChargeDischargeKW > 1e-7
    error("StoreNet:InvalidPeakGuardNumerics", ...
        "Peak Guard result violates cap or retained numerical checks.");
end
end

function meta = monthlyCaseMetadata(data, dataMeta, calendarDay)
meta = struct;
meta.day = calendarDay;
meta.dateOrPeriod = calendarDay;
meta.experimentId = "B2022_PEAK_GUARD_MONTHLY_V1";
meta.runId = "bahloul_vpp_improvement_v1";
meta.scenarioId = "DC_XI007_H20";
meta.pairId = "DC_XI007";
meta.sensitivityRole = "PRIMARY";
meta.qualityMode = "release_literal";
meta.capacityRatio = 1;
meta.powerRatio = 1;
meta.cohortId = "H20_PV10";
meta.houseIds = string(data.houseIds(:)).';
meta.houseCount = 20;
meta.pvHomeCount = 10;
meta.excludedHomes = strings(0, 1);
meta.pvBoundaryId = "DC_SOURCE";
meta.transferLossFraction = 0.07;
meta.releasedPvPreserved = true;
meta.cohortMask = true(1, 20);
meta.dataMeta = dataMeta;
end

function row = evaluatedMetricRow(calendarDay, metrics, solution, capKW, ...
        wallTimeSeconds, artifactDirectory, reused)
row = emptyMetricRow();
row.Dataset = "StoreNet";
row.Day = calendarDay;
row.Sequence = 2;
row.Strategy = "IMPROVED_PEAK_GUARD";
row.Status = "ok";
row.SourceEvidence = "new Peak Guard dispatch from frozen monthly input";
row.ReusedWithoutSolve = reused;
row.WallTimeSeconds = wallTimeSeconds;
row.IntervalMinutes = 60;
row.HouseCount = 20;
row.PvHomeCount = 10;
row.PvBoundaryId = "DC_SOURCE";
row.TransferLossFraction = 0.07;
row.BatteryCapacityKWhPerHome = 10;
row.BatteryPowerKWPerHome = 3.3;
row.PeakGuardCapKW = double(capKW);
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
row.MinimumExitFlag = minimumExitFlag(solution);
row.MaximumRelativeMipGap = maximumRelativeMipGap(solution);
row.StageCount = objectiveStageCount(solution);
row.PeakExcessOverCapKW = row.AllDayPeakKW - row.PeakGuardCapKW;
row.CapViolationKW = max(0, row.PeakExcessOverCapKW);
row.ArtifactDirectory = artifactDirectory;
end

function row = failureMetricRow(calendarDay, capKW, exception)
row = emptyMetricRow();
row.Dataset = "StoreNet";
row.Day = calendarDay;
row.Sequence = 2;
row.Strategy = "IMPROVED_PEAK_GUARD";
row.Status = "failed";
row.ErrorIdentifier = string(exception.identifier);
row.ErrorMessage = string(exception.message);
row.SourceEvidence = "new Peak Guard attempt from frozen monthly input";
row.IntervalMinutes = 60;
row.HouseCount = 20;
row.PvHomeCount = 10;
row.PvBoundaryId = "DC_SOURCE";
row.TransferLossFraction = 0.07;
row.BatteryCapacityKWhPerHome = 10;
row.BatteryPowerKWPerHome = 3.3;
row.PeakGuardCapKW = capKW;
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
if isempty(gap)
    gap = NaN;
end
end

function count = objectiveStageCount(solution)
count = NaN;
if isfield(solution, "objectiveStages")
    count = numel(solution.objectiveStages);
end
end

function [strategyMetrics, pairComparison, checkpoint] = ...
        writeCheckpointOutputs(formalRows, peakGuardRows, paths, ...
        eligibleDates, formalVpp, requestFinal)
allRows = [formalRows; peakGuardRows];
strategyMetrics = metricRowsToTable(allRows);
strategyMetrics.Strategy = [repmat("VPP_BM", numel(formalRows), 1); ...
    repmat("IMPROVED_PEAK_GUARD", numel(peakGuardRows), 1)];
strategyMetrics.Sequence = [ones(numel(formalRows), 1); ...
    2 .* ones(numel(peakGuardRows), 1)];
strategyMetrics = sortrows(strategyMetrics, ["Day", "Sequence"]);
pairComparison = make_peak_guard_pair_comparison(strategyMetrics);
completed = nnz(strategyMetrics.Strategy == "IMPROVED_PEAK_GUARD" & ...
    strategyMetrics.Status == "ok" & ...
    ismember(strategyMetrics.Day, eligibleDates));
failed = nnz(strategyMetrics.Strategy == "IMPROVED_PEAK_GUARD" & ...
    strategyMetrics.Status == "failed");
skipped = nnz(formalVpp.Status ~= "ok");
isFinal = logical(requestFinal && completed == numel(eligibleDates) && ...
    failed == 0 && height(pairComparison) == numel(eligibleDates));
checkpoint = table(height(formalVpp), numel(eligibleDates), completed, ...
    skipped, failed, isFinal, ...
    VariableNames=["FormalVppRows", "ExpectedPeakGuardRows", ...
    "CompletedPeakGuardRows", "SkippedUnavailableDates", ...
    "FailedPeakGuardRows", "IsFinal"]);
writeTableAtomic(strategyMetrics, paths.strategyMetrics);
writeTableAtomic(pairComparison, paths.pairComparison);
writeTableAtomic(checkpoint, paths.checkpoint);
end

function value = metricRowsToTable(rows)
template = emptyMetricRow();
value = struct2table(repmat(template, numel(rows), 1));
fields = string(fieldnames(template));
for rowIndex = 1:numel(rows)
    for fieldIndex = 1:numel(fields)
        field = fields(fieldIndex);
        item = rows(rowIndex).(field);
        while iscell(item) && isscalar(item)
            item = item{1};
        end
        defaultItem = template.(field);
        if isstring(defaultItem)
            item = string(item);
        elseif isdatetime(defaultItem)
            item = normalizeDay(item);
        elseif islogical(defaultItem)
            item = logical(item);
        else
            item = double(item);
        end
        if ~isscalar(item)
            error("StoreNet:InvalidPeakGuardMetricRow", ...
                "Metric row %d field %s must be scalar (class %s, size %s).", ...
                rowIndex, field, class(item), mat2str(size(item)));
        end
        value.(field)(rowIndex) = item;
    end
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

function summary = summarizeMonthlyPairs(strategyMetrics, pairs)
periods = unique(dateshift(pairs.Day, "start", "month"), "sorted");
labels = [string(periods, "yyyy-MM"); "ALL"];
rows = repmat(emptyMonthlySummaryRow(), numel(labels), 1);
for rowIndex = 1:numel(labels)
    if labels(rowIndex) == "ALL"
        selected = true(height(pairs), 1);
    else
        selected = dateshift(pairs.Day, "start", "month") == ...
            periods(rowIndex);
    end
    subset = pairs(selected, :);
    metricSubset = strategyMetrics( ...
        ismember(strategyMetrics.Day, subset.Day) & ...
        strategyMetrics.Status == "ok", :);
    vpp = metricSubset(metricSubset.Strategy == "VPP_BM", :);
    peakGuard = metricSubset( ...
        metricSubset.Strategy == "IMPROVED_PEAK_GUARD", :);
    row = emptyMonthlySummaryRow();
    row.Period = labels(rowIndex);
    row.PairedDays = height(subset);
    row.VppNewPeakDays = nnz(subset.VppCreatesNewPeak);
    row.PeakGuardCapPassDays = nnz(subset.PeakGuardCapSatisfied);
    row.MeanVppBillEUR = mean(subset.VppBillEUR);
    row.MeanPeakGuardBillEUR = mean(subset.PeakGuardBillEUR);
    row.MeanBillPenaltyEUR = mean(subset.BillPenaltyEUR);
    row.MedianBillPenaltyEUR = median(subset.BillPenaltyEUR);
    row.SummedVppBillEUR = sum(subset.VppBillEUR);
    row.SummedPeakGuardBillEUR = sum(subset.PeakGuardBillEUR);
    row.SummedBillPenaltyEUR = sum(subset.BillPenaltyEUR);
    row.AggregatedVppPaperSavingsPercent = savingsFromSummedBills( ...
        vpp.PaperLoadOnlyBaselineBillEUR, vpp.OptimizedBillEUR);
    row.AggregatedPeakGuardPaperSavingsPercent = ...
        savingsFromSummedBills(peakGuard.PaperLoadOnlyBaselineBillEUR, ...
        peakGuard.OptimizedBillEUR);
    row.AggregatedPaperSavingsSacrificePercentagePoints = ...
        row.AggregatedVppPaperSavingsPercent - ...
        row.AggregatedPeakGuardPaperSavingsPercent;
    row.AggregatedVppEngineeringSavingsPercent = ...
        savingsFromSummedBills(vpp.PvSelfNoBatteryBaselineBillEUR, ...
        vpp.OptimizedBillEUR);
    row.AggregatedPeakGuardEngineeringSavingsPercent = ...
        savingsFromSummedBills( ...
        peakGuard.PvSelfNoBatteryBaselineBillEUR, ...
        peakGuard.OptimizedBillEUR);
    row.AggregatedEngineeringSavingsSacrificePercentagePoints = ...
        row.AggregatedVppEngineeringSavingsPercent - ...
        row.AggregatedPeakGuardEngineeringSavingsPercent;
    row.MeanPaperSavingsSacrificePercentagePoints = mean( ...
        subset.PaperSavingsSacrificePercentagePoints);
    row.MedianPaperSavingsSacrificePercentagePoints = median( ...
        subset.PaperSavingsSacrificePercentagePoints);
    row.MeanEngineeringSavingsSacrificePercentagePoints = mean( ...
        subset.EngineeringSavingsSacrificePercentagePoints);
    row.MedianEngineeringSavingsSacrificePercentagePoints = median( ...
        subset.EngineeringSavingsSacrificePercentagePoints);
    row.MeanVppAllDayPeakKW = mean(subset.VppAllDayPeakKW);
    row.MeanPeakGuardAllDayPeakKW = mean(subset.PeakGuardAllDayPeakKW);
    row.MeanPeakReductionKW = mean(subset.PeakReductionKW);
    row.MedianPeakReductionKW = median(subset.PeakReductionKW);
    row.MeanPeakReductionPercent = mean(subset.PeakReductionPercent);
    row.MeanDaytimePeakChangeKW = mean(subset.DaytimePeakChangeKW);
    row.MeanLoadRangeReductionKW = mean(subset.LoadRangeReductionKW);
    row.MeanGridImportChangeKWh = mean(subset.GridImportChangeKWh);
    row.MeanBatteryThroughputChangeKWh = mean( ...
        subset.BatteryThroughputChangeKWh);
    row.MeanPvCurtailmentChangeKWh = mean( ...
        subset.PvCurtailmentChangeKWh, "omitmissing");
    row.MeanPeakGuardPvCurtailmentKWh = mean( ...
        subset.PeakGuardPvCurtailmentKWh);
    row.MaximumPeakGuardPvCurtailmentKWh = max( ...
        subset.PeakGuardPvCurtailmentKWh);
    row.MaximumPeakGuardCapViolationKW = max( ...
        subset.PeakGuardCapViolationKW);
    rows(rowIndex, 1) = row;
end
summary = struct2table(rows);
end

function row = emptyMonthlySummaryRow()
row = struct("Period", "", "PairedDays", 0, "VppNewPeakDays", 0, ...
    "PeakGuardCapPassDays", 0, "MeanVppBillEUR", NaN, ...
    "MeanPeakGuardBillEUR", NaN, "MeanBillPenaltyEUR", NaN, ...
    "MedianBillPenaltyEUR", NaN, "SummedVppBillEUR", NaN, ...
    "SummedPeakGuardBillEUR", NaN, "SummedBillPenaltyEUR", NaN, ...
    "AggregatedVppPaperSavingsPercent", NaN, ...
    "AggregatedPeakGuardPaperSavingsPercent", NaN, ...
    "AggregatedPaperSavingsSacrificePercentagePoints", NaN, ...
    "AggregatedVppEngineeringSavingsPercent", NaN, ...
    "AggregatedPeakGuardEngineeringSavingsPercent", NaN, ...
    "AggregatedEngineeringSavingsSacrificePercentagePoints", NaN, ...
    "MeanPaperSavingsSacrificePercentagePoints", NaN, ...
    "MedianPaperSavingsSacrificePercentagePoints", NaN, ...
    "MeanEngineeringSavingsSacrificePercentagePoints", NaN, ...
    "MedianEngineeringSavingsSacrificePercentagePoints", NaN, ...
    "MeanVppAllDayPeakKW", NaN, "MeanPeakGuardAllDayPeakKW", NaN, ...
    "MeanPeakReductionKW", NaN, "MedianPeakReductionKW", NaN, ...
    "MeanPeakReductionPercent", NaN, "MeanDaytimePeakChangeKW", NaN, ...
    "MeanLoadRangeReductionKW", NaN, "MeanGridImportChangeKWh", NaN, ...
    "MeanBatteryThroughputChangeKWh", NaN, ...
    "MeanPvCurtailmentChangeKWh", NaN, ...
    "MeanPeakGuardPvCurtailmentKWh", NaN, ...
    "MaximumPeakGuardPvCurtailmentKWh", NaN, ...
    "MaximumPeakGuardCapViolationKW", NaN);
end

function value = savingsFromSummedBills(baselineBills, optimizedBills)
baseline = sum(double(baselineBills));
optimized = sum(double(optimizedBills));
if abs(baseline) <= eps(max(1, abs(baseline)))
    value = NaN;
else
    value = 100 .* (baseline - optimized) ./ baseline;
end
end

function summary = summarizePeakGuardResiduals(strategyMetrics)
peakGuard = strategyMetrics.Strategy == "IMPROVED_PEAK_GUARD" & ...
    strategyMetrics.Status == "ok";
names = ["EnergyBalanceResidualKW"; "PvAllocationResidualKW"; ...
    "HomeBalanceResidualKW"; "BatteryDynamicsResidualKW"; ...
    "AggregateImportResidualKW"; "ChargeConversionResidualKW"; ...
    "DischargeConversionResidualKW"; "InitialSocErrorKWh"; ...
    "TerminalSocErrorKWh"; "SocBoundViolationKWh"; ...
    "ChargePowerViolationKW"; "DischargePowerViolationKW"; ...
    "AggregateImportNonnegativeViolationKW"; ...
    "SimultaneousChargeDischargeKW"; "MaximumLexicographicViolation"];
units = [repmat("kW", 7, 1); repmat("kWh", 3, 1); ...
    repmat("kW", 4, 1); "objective units"];
maximum = nan(numel(names), 1);
for metricIndex = 1:numel(names)
    maximum(metricIndex) = max( ...
        strategyMetrics.(names(metricIndex))(peakGuard), [], "omitnan");
end
summary = table(names, units, maximum, ...
    VariableNames=["ResidualOrViolation", "Unit", "Maximum"]);
end

function deleteIfPresent(path)
if isfile(path)
    delete(path);
end
end

function assertTableVariables(value, required, description)
missing = required(~ismember(required, ...
    string(value.Properties.VariableNames)));
if ~isempty(missing)
    error("StoreNet:InvalidPeakGuardTable", ...
        "%s is missing variable(s): %s.", description, ...
        strjoin(missing, ", "));
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
