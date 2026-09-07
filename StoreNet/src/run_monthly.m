function run = run_monthly(options)
%RUN_MONTHLY Run the paper's four sampled days per month on public 2020 data.
%   RUN = RUN_MONTHLY() evaluates days 1, 2, 15, and 16 of every month at
%   hourly resolution for all five published strategies. A rejected date is
%   retained as five explicit status rows; it is never replaced by a nearby
%   date. Caller-provided Dates support focused reruns and unit tests.

arguments
    options.Dates datetime = NaT(0, 1)
    options.QualityMode (1, 1) string {mustBeMember(options.QualityMode, ...
        ["release_literal", "short_gap_only", "exclude_flagged_pv"])} = ...
        "exclude_flagged_pv"
    options.DataRoot (1, 1) string = ""
    options.OutputRoot (1, 1) string = ""
    options.RunId (1, 1) string = ""
    options.ConfigOverrides (1, 1) struct = struct
    options.DataProvider (1, 1) function_handle = @load_storenet_day
    options.Solver (1, 1) function_handle = @solve_storenet
end

sourceFolder = fileparts(mfilename("fullpath"));
if isempty(options.Dates)
    options.Dates = defaultMonthlyDates();
end
sampleDates = unique(dateshift(options.Dates(:), "start", "day"), "sorted");
if isempty(sampleDates)
    error("StoreNet:NoMonthlyDates", "Dates must contain at least one day.");
end
if strlength(options.OutputRoot) == 0
    options.OutputRoot = string(fullfile(sourceFolder, "..", "results"));
end
if strlength(options.RunId) == 0
    options.RunId = "monthly_2020_" + ...
        string(datetime("now"), "yyyyMMdd_HHmmss_SSS");
end
runDirectory = prepareRunDirectory(options.OutputRoot, options.RunId);
metricsPath = fullfile(runDirectory, "monthly_metrics.csv");
qualityPath = fullfile(runDirectory, "monthly_quality_status.csv");
summaryPath = fullfile(runDirectory, "monthly_summary.csv");
checkpointPath = fullfile(runDirectory, "monthly_checkpoint.csv");

config = storenet_config(IntervalMinutes=60, DataRoot=options.DataRoot, ...
    QualityMode=options.QualityMode);
config = applyOverrides(config, options.ConfigOverrides);
strategies = ["SH_BM", "VPP_BM", "PS", "PSDT", "LL"];
rows = repmat(emptyMonthlyRow(), 0, 1);
qualityRecords = repmat(emptyQualityRecord(), 0, 1);

for dateIndex = 1:numel(sampleDates)
    day = sampleDates(dateIndex);
    try
        [data, dataMeta] = callDataProvider(options.DataProvider, day, ...
            options.DataRoot, 60, options.QualityMode);
        if metadataRejected(dataMeta)
            rejectionMessage = qualityRejectionMessage(day, ...
                options.QualityMode, dataMeta);
            qualityRecords(end + 1, 1) = qualityRecord(day, ...
                "quality_rejected", "StoreNet:QualityRejected", ...
                rejectionMessage, dataMeta); %#ok<AGROW>
            for strategyIndex = 1:numel(strategies)
                rows(end + 1, 1) = monthlyRow(day, ...
                    strategies(strategyIndex), "quality_rejected", ...
                    "StoreNet:QualityRejected", rejectionMessage, 0, ...
                    config, struct, struct); %#ok<AGROW>
            end
            writeMonthlyCheckpoint(runDirectory, rows, qualityRecords, ...
                strategies, numel(sampleDates), false);
            continue
        end
        data = normalizeExperimentData(data);
        qualityRecords(end + 1, 1) = qualityRecord(day, "passed", "", "", ...
            dataMeta); %#ok<AGROW>
    catch exception
        rejectionStatus = classifyDataFailure(exception);
        qualityRecords(end + 1, 1) = qualityRecord(day, rejectionStatus, ...
            string(exception.identifier), string(exception.message), struct); %#ok<AGROW>
        for strategyIndex = 1:numel(strategies)
            rows(end + 1, 1) = monthlyRow(day, strategies(strategyIndex), ...
                rejectionStatus, string(exception.identifier), ...
                string(exception.message), 0, config, struct, struct); %#ok<AGROW>
        end
        writeMonthlyCheckpoint(runDirectory, rows, qualityRecords, ...
            strategies, numel(sampleDates), false);
        continue
    end

    for strategyIndex = 1:numel(strategies)
        strategy = strategies(strategyIndex);
        started = tic;
        try
            [solution, metrics] = options.Solver(data, config, strategy);
            rows(end + 1, 1) = monthlyRow(day, strategy, "ok", "", "", ...
                toc(started), config, metrics, solution); %#ok<AGROW>
        catch exception
            rows(end + 1, 1) = monthlyRow(day, strategy, "failed", ...
                string(exception.identifier), string(exception.message), ...
                toc(started), config, struct, struct); %#ok<AGROW>
        end
        writeMonthlyCheckpoint(runDirectory, rows, qualityRecords, ...
            strategies, numel(sampleDates), false);
    end
end

[metricsTable, qualityTable, summaryTable] = writeMonthlyCheckpoint( ...
    runDirectory, rows, qualityRecords, strategies, numel(sampleDates), true);

runInfo = struct;
runInfo.runType = "monthly_structural_replication";
runInfo.runId = options.RunId;
runInfo.days = string(sampleDates, "yyyy-MM-dd");
runInfo.defaultSamplingRule = "days 1, 2, 15, and 16 of each 2020 month";
runInfo.missingPaperPeriod = ...
    "Public release starts in 2020; July-December 2019 is unavailable.";
runInfo.qualityMode = options.QualityMode;
runInfo.intervalMinutes = 60;
runInfo.intervalConvention = "hourly energy summed from minute Wh; interval-end labels";
runInfo.checkpointPolicy = ...
    "CSV tables and completion counts are rewritten after each strategy row";
runInfo.strategies = strategies;
runInfo.configuration = config;
runInfo.statuses = metricsTable(:, ["Day", "Strategy", "Status", ...
    "ErrorIdentifier", "ErrorMessage", "WallTimeSeconds"]);
runInfo.qualityStatuses = qualityTable;
[manifest, manifestPath] = write_run_manifest(runDirectory, runInfo);

run = struct;
run.runDirectory = runDirectory;
run.metricsPath = metricsPath;
run.qualityPath = qualityPath;
run.summaryPath = summaryPath;
run.checkpointPath = checkpointPath;
run.manifestPath = manifestPath;
run.metricsTable = metricsTable;
run.qualityTable = qualityTable;
run.summaryTable = summaryTable;
run.configuration = config;
run.manifest = manifest;
end

function dates = defaultMonthlyDates()
monthStarts = datetime(2020, (1:12).', 1);
offsets = caldays([0, 1, 14, 15]);
dates = sort(reshape(monthStarts + offsets, [], 1));
end

function [metricsTable, qualityTable, summaryTable] = ...
        writeMonthlyCheckpoint(runDirectory, rows, qualityRecords, ...
        strategies, requestedDays, isFinal)
metricsTable = struct2table(rows);
qualityTable = struct2table(qualityRecords);
summaryTable = summarizeMonthly(metricsTable, strategies);
writeTableAtomic(metricsTable, fullfile(runDirectory, "monthly_metrics.csv"));
writeTableAtomic(qualityTable, ...
    fullfile(runDirectory, "monthly_quality_status.csv"));
writeTableAtomic(summaryTable, fullfile(runDirectory, "monthly_summary.csv"));

checkpoint = table(height(metricsTable), requestedDays * numel(strategies), ...
    height(qualityTable), requestedDays, logical(isFinal), ...
    VariableNames=["CompletedMetricRows", "ExpectedMetricRows", ...
    "CompletedQualityDays", "ExpectedQualityDays", "IsFinal"]);
writeTableAtomic(checkpoint, fullfile(runDirectory, "monthly_checkpoint.csv"));
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

function summary = summarizeMonthly(metrics, strategies)
rows = repmat(emptySummaryRow(), numel(strategies), 1);
for strategyIndex = 1:numel(strategies)
    strategy = strategies(strategyIndex);
    selected = metrics.Strategy == strategy & metrics.Status == "ok";
    rows(strategyIndex).Strategy = strategy;
    rows(strategyIndex).SuccessfulDays = nnz(selected);
    rows(strategyIndex).RequestedDays = nnz(metrics.Strategy == strategy);
    rows(strategyIndex).MeanSavingsPercent = mean( ...
        metrics.SavingsPercent(selected), "omitnan");
    rows(strategyIndex).MeanPeakImportKW = mean( ...
        metrics.PeakImportKW(selected), "omitnan");
    rows(strategyIndex).MeanOptimizedBillEUR = mean( ...
        metrics.OptimizedBillEUR(selected), "omitnan");
end
summary = struct2table(rows);
end

function row = emptySummaryRow()
row = struct("Strategy", "", "SuccessfulDays", 0, "RequestedDays", 0, ...
    "MeanSavingsPercent", NaN, "MeanPeakImportKW", NaN, ...
    "MeanOptimizedBillEUR", NaN);
end

function record = qualityRecord(day, status, identifier, message, metadata)
record = emptyQualityRecord();
record.Day = day;
record.Status = status;
record.ErrorIdentifier = identifier;
record.ErrorMessage = message;
record.IsComplete = logicalMetadata(metadata, "isComplete");
record.IsFullyObserved = logicalMetadata(metadata, "isFullyObserved");
record.QualityPassed = logicalMetadata(metadata, "qualityPassed");
record.QualityReasons = stringMetadata(metadata, "qualityReasons");
record.PvLongWindowAnomaly = logicalMetadata(metadata, "pvLongWindowAnomaly");
record.PvWindowHours = numericMetadata(metadata, "pvWindowHours");
record.AstronomicalDayLengthHours = numericMetadata(metadata, ...
    "astronomicalDayLengthHours");
record.MaximumMissingStatusRunMinutes = maximumMetadata(metadata, ...
    "longestMissingStatusRunByHome");
end

function record = emptyQualityRecord()
record = struct("Day", NaT, "Status", "", "ErrorIdentifier", "", ...
    "ErrorMessage", "", "IsComplete", false, "IsFullyObserved", false, ...
    "QualityPassed", false, "QualityReasons", "", ...
    "PvLongWindowAnomaly", false, "PvWindowHours", NaN, ...
    "AstronomicalDayLengthHours", NaN, ...
    "MaximumMissingStatusRunMinutes", NaN);
end

function value = logicalMetadata(metadata, field)
if isfield(metadata, field) && isscalar(metadata.(field))
    value = logical(metadata.(field));
else
    value = false;
end
end

function value = stringMetadata(metadata, field)
if isfield(metadata, field) && ~isempty(metadata.(field))
    value = strjoin(string(metadata.(field)), "; ");
else
    value = "";
end
end

function value = numericMetadata(metadata, field)
if isfield(metadata, field) && isscalar(metadata.(field))
    value = double(metadata.(field));
else
    value = NaN;
end
end

function value = maximumMetadata(metadata, field)
if isfield(metadata, field) && ~isempty(metadata.(field))
    value = max(double(metadata.(field)));
else
    value = NaN;
end
end

function status = classifyDataFailure(exception)
identifier = string(exception.identifier);
message = string(exception.message);
isQuality = contains(identifier, ["Quality", "Incomplete", "Flagged"], ...
    IgnoreCase=true) || contains(message, ["quality", "observation gate", ...
    "flagged PV"], IgnoreCase=true);
if isQuality
    status = "quality_rejected";
else
    status = "data_failed";
end
end

function row = monthlyRow(day, strategy, status, errorIdentifier, ...
        errorMessage, wallTimeSeconds, config, metrics, solution)
row = emptyMonthlyRow();
row.Day = day;
row.Strategy = strategy;
row.Status = status;
row.ErrorIdentifier = errorIdentifier;
row.ErrorMessage = errorMessage;
row.WallTimeSeconds = wallTimeSeconds;
row.BatteryCapacityKWh = double(config.batteryCapacityKWh);
row.BatteryPowerKW = double(config.batteryPowerKW);
row.BaselineBillEUR = explicitBaselineMetric(metrics, ...
    "PaperLoadOnlyBaseline", "billEUR", "baselineBillEUR");
row.SavingsEUR = explicitBaselineMetric(metrics, ...
    "PaperLoadOnlyBaseline", "savingsEUR", "savingsEUR");
row.SavingsPercent = explicitBaselineMetric(metrics, ...
    "PaperLoadOnlyBaseline", "savingsPercent", "savingsPercent");
row.BaselinePeakImportKW = explicitBaselineMetric(metrics, ...
    "PaperLoadOnlyBaseline", "peakImportKW", "baselinePeakImportKW");
metricFields = ["optimizedBillEUR", "peakImportKW", ...
    "daytimePeakImportKW", "importSpreadKW", "totalGridImportKWh", ...
    "totalBatteryThroughputKWh", "energyBalanceResidualKW", ...
    "terminalSocErrorKWh", "simultaneousChargeDischargeKW"];
rowFields = ["OptimizedBillEUR", "PeakImportKW", ...
    "DaytimePeakImportKW", "ImportSpreadKW", "TotalGridImportKWh", ...
    "TotalBatteryThroughputKWh", "EnergyBalanceResidualKW", ...
    "TerminalSocErrorKWh", "SimultaneousChargeDischargeKW"];
for fieldIndex = 1:numel(metricFields)
    if isfield(metrics, metricFields(fieldIndex))
        row.(rowFields(fieldIndex)) = double(metrics.(metricFields(fieldIndex)));
    end
end
if isfield(solution, "exitFlags") && ~isempty(solution.exitFlags)
    row.MinimumExitFlag = min(double(solution.exitFlags));
end
end

function value = explicitBaselineMetric(metrics, baselineName, fieldName, ...
        legacyFieldName)
value = NaN;
if isstruct(metrics) && isfield(metrics, baselineName) && ...
        isstruct(metrics.(baselineName)) && ...
        isfield(metrics.(baselineName), fieldName)
    value = double(metrics.(baselineName).(fieldName));
elseif isstruct(metrics) && isfield(metrics, legacyFieldName)
    value = double(metrics.(legacyFieldName));
end
end

function row = emptyMonthlyRow()
row = struct;
row.Day = NaT;
row.Strategy = "";
row.Status = "";
row.ErrorIdentifier = "";
row.ErrorMessage = "";
row.WallTimeSeconds = NaN;
row.BatteryCapacityKWh = NaN;
row.BatteryPowerKW = NaN;
row.BaselineBillEUR = NaN;
row.OptimizedBillEUR = NaN;
row.SavingsEUR = NaN;
row.SavingsPercent = NaN;
row.BaselinePeakImportKW = NaN;
row.PeakImportKW = NaN;
row.DaytimePeakImportKW = NaN;
row.ImportSpreadKW = NaN;
row.TotalGridImportKWh = NaN;
row.TotalBatteryThroughputKWh = NaN;
row.EnergyBalanceResidualKW = NaN;
row.TerminalSocErrorKWh = NaN;
row.SimultaneousChargeDischargeKW = NaN;
row.MinimumExitFlag = NaN;
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
if isfolder(directory) && ~isempty(dir(fullfile(directory, "*")))
    error("StoreNet:RunDirectoryExists", ...
        "Refusing to overwrite nonempty run directory: %s", directory);
end
if ~isfolder(directory)
    mkdir(directory);
end
end

function config = applyOverrides(config, overrides)
fields = string(fieldnames(overrides));
for fieldIndex = 1:numel(fields)
    field = fields(fieldIndex);
    config.(field) = overrides.(field);
end
end

function [data, meta] = callDataProvider(provider, day, dataRoot, ...
        intervalMinutes, qualityMode)
try
    [data, meta] = provider(day, DataRoot=dataRoot, ...
        IntervalMinutes=intervalMinutes, QualityMode=qualityMode);
catch exception
    legacyMode = legacyQualityMode(qualityMode);
    if legacyMode == qualityMode || ~isArgumentValidationFailure(exception)
        rethrow(exception)
    end
    [data, meta] = provider(day, DataRoot=dataRoot, ...
        IntervalMinutes=intervalMinutes, QualityMode=legacyMode);
end
end

function tf = metadataRejected(meta)
tf = isfield(meta, "qualityPassed") && ~logical(meta.qualityPassed);
end

function message = qualityRejectionMessage(day, qualityMode, meta)
reasons = "quality contract returned false";
if isfield(meta, "qualityReasons") && ~isempty(meta.qualityReasons)
    reasons = strjoin(string(meta.qualityReasons), "; ");
end
message = "Day " + string(day, "yyyy-MM-dd") + " fails " + ...
    qualityMode + ": " + reasons + ".";
end

function mode = legacyQualityMode(mode)
if mode == "release_literal"
    mode = "report";
else
    mode = "strict";
end
end

function tf = isArgumentValidationFailure(exception)
identifier = string(exception.identifier);
message = string(exception.message);
tf = contains(identifier, "validation", IgnoreCase=true) || ...
    contains(identifier, "invalidType", IgnoreCase=true) || ...
    contains(message, "must be a member", IgnoreCase=true) || ...
    contains(message, "QualityMode", IgnoreCase=true) && ...
    contains(message, "accepted", IgnoreCase=true);
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
end
