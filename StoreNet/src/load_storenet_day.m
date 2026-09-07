function [data, meta] = load_storenet_day(day, options)
%LOAD_STORENET_DAY Load one exact calendar day from the StoreNet release.
%   DATA = LOAD_STORENET_DAY(DAY) reads the immutable processed-release Wh
%   files and returns interval energy and mean power for all 20 homes. Wh
%   timestamps are interval ends: day D therefore uses (D 00:00,D+1 00:00].
%
%   [DATA,META] = LOAD_STORENET_DAY(...,QualityMode=MODE) evaluates one of
%   the frozen contracts "release_literal", "short_gap_only" (default), or
%   "exclude_flagged_pv". Canonical modes return META.qualityPassed and do
%   not hide rejected values. The compatibility aliases are "report" ->
%   "release_literal" and "strict" -> "short_gap_only"; only the strict
%   alias throws on failure. Physical gaps produce NaN aggregates and are
%   never silently filled with zero.

arguments
    day (1, 1) datetime
    options.DataRoot (1, 1) string = ""
    options.IntervalMinutes (1, 1) double {mustBeMember(options.IntervalMinutes, [30, 60])} = 30
    options.QualityMode (1, 1) string {mustBeMember(options.QualityMode, ...
        ["release_literal", "short_gap_only", "exclude_flagged_pv", ...
        "strict", "report"])} = "short_gap_only"
end

day = dateshift(day, "start", "day");
cfg = storenet_config( ...
    IntervalMinutes=options.IntervalMinutes, ...
    DataRoot=options.DataRoot, ...
    QualityMode=options.QualityMode);

mustBeFolder(cfg.dataRoot);

nMinutes = 24 * 60;
nBins = nMinutes / cfg.intervalMinutes;
nHomes = cfg.nHomes;
dayEnd = day + days(1);
expectedWTime = (day:minutes(1):dayEnd).';
expectedWhTime = (day + minutes(1):minutes(1):dayEnd).';
timeEnd = (day + minutes(cfg.intervalMinutes): ...
    minutes(cfg.intervalMinutes):dayEnd).';

minuteDischargeWh = nan(nMinutes, nHomes);
minuteChargeWh = nan(nMinutes, nHomes);
minuteProductionWh = nan(nMinutes, nHomes);
minuteConsumptionWh = nan(nMinutes, nHomes);
minuteFeedInWh = nan(nMinutes, nHomes);
minuteFromGridWh = nan(nMinutes, nHomes);
minuteSocPercent = nan(nMinutes, nHomes);
minuteComplete = false(nMinutes, nHomes);
minuteObserved = false(nMinutes, nHomes);
duplicateTimestamp = false(1, nHomes);
missingStatusRows = zeros(1, nHomes);
missingStatusFraction = zeros(1, nHomes);
longestMissingStatusRun = zeros(1, nHomes);
extraWColumnCount = zeros(1, nHomes);
extraWColumnNames = strings(1, nHomes);

whColumns = ["date", "Discharge(Wh)", "Charge(Wh)", ...
    "Production(Wh)", "Consumption(Wh)", "Feed-in(Wh)", ...
    "From grid(Wh)", "State of Charge(%)"];
standardWColumns = ["date", "Discharge(W)", "Charge(W)", ...
    "Production(W)", "Consumption(W)", "State of Charge(%)"];

for homeIndex = 1:nHomes
    home = cfg.homes(homeIndex);
    wFile = fullfile(cfg.dataRoot, home + "_W.csv");
    whFile = fullfile(cfg.dataRoot, home + "_Wh.csv");

    [wTime, wValues, wHeaders] = readReleaseSlice( ...
        wFile, ["date", home + "_W"], day, dayEnd);
    [whTime, whValues] = readReleaseSlice( ...
        whFile, whColumns, day + minutes(1), dayEnd);

    [wStatus, wPresent, wDuplicate] = regridValues( ...
        wTime, wValues(:, 1), expectedWTime);
    [wh, whPresent, whDuplicate] = regridValues( ...
        whTime, whValues, expectedWhTime);

    wObserved = wPresent & (wStatus == 1);
    whFinite = whPresent & all(isfinite(wh), 2);
    endpointPresent = wPresent(1:end-1) & wPresent(2:end);
    endpointObserved = wObserved(1:end-1) & wObserved(2:end);

    minuteComplete(:, homeIndex) = whFinite & endpointPresent;
    minuteObserved(:, homeIndex) = ...
        minuteComplete(:, homeIndex) & endpointObserved;
    duplicateTimestamp(homeIndex) = wDuplicate | whDuplicate;
    missingStatusRows(homeIndex) = sum(~wObserved);
    missingStatusFraction(homeIndex) = ...
        missingStatusRows(homeIndex) / numel(expectedWTime);
    longestMissingStatusRun(homeIndex) = longestFalseRun(wObserved);

    minuteDischargeWh(:, homeIndex) = wh(:, 1);
    minuteChargeWh(:, homeIndex) = wh(:, 2);
    minuteProductionWh(:, homeIndex) = wh(:, 3);
    minuteConsumptionWh(:, homeIndex) = wh(:, 4);
    minuteFeedInWh(:, homeIndex) = wh(:, 5);
    minuteFromGridWh(:, homeIndex) = wh(:, 6);
    minuteSocPercent(:, homeIndex) = wh(:, 7);

    normalizedWHeaders = strtrim(wHeaders);
    expectedWHeaders = [standardWColumns, home + "_W"];
    extra = normalizedWHeaders(~ismember(normalizedWHeaders, expectedWHeaders));
    extraWColumnCount(homeIndex) = numel(extra);
    extraWColumnNames(homeIndex) = strjoin(extra, ";");
end

binComplete = aggregateMask(minuteComplete, cfg.intervalMinutes);
binObserved = aggregateMask(minuteObserved, cfg.intervalMinutes);

data = struct;
data.day = day;
data.intervalMinutes = cfg.intervalMinutes;
data.dtHours = cfg.dtHours;
data.timeEnd = timeEnd;
data.time = data.timeEnd;
data.homeNames = cfg.homes;
data.houseIds = data.homeNames;
data.pvHomeMask = cfg.pvHomeMask;
data.dischargeKWh = aggregateEnergy(minuteDischargeWh, cfg.intervalMinutes);
data.chargeKWh = aggregateEnergy(minuteChargeWh, cfg.intervalMinutes);
data.pvKWh = aggregateEnergy(minuteProductionWh, cfg.intervalMinutes);
data.loadKWh = aggregateEnergy(minuteConsumptionWh, cfg.intervalMinutes);
data.feedInKWh = aggregateEnergy(minuteFeedInWh, cfg.intervalMinutes);
data.fromGridKWh = aggregateEnergy(minuteFromGridWh, cfg.intervalMinutes);
data.socFraction = minuteSocPercent(cfg.intervalMinutes: ...
    cfg.intervalMinutes:nMinutes, :) / 100;
data.dischargeKW = data.dischargeKWh / cfg.dtHours;
data.chargeKW = data.chargeKWh / cfg.dtHours;
data.pvKW = data.pvKWh / cfg.dtHours;
data.loadKW = data.loadKWh / cfg.dtHours;
data.feedInKW = data.feedInKWh / cfg.dtHours;
data.fromGridKW = data.fromGridKWh / cfg.dtHours;
data.balanceResidualKWh = data.fromGridKWh + data.pvKWh + ...
    data.dischargeKWh - data.loadKWh - data.chargeKWh - data.feedInKWh;

missingMinutes = sum(~minuteComplete, 1);
interpolatedMinutes = sum(minuteComplete & ~minuteObserved, 1);
missingBins = sum(~binComplete, 1);
interpolatedBins = sum(binComplete & ~binObserved, 1);
[pvWindowHours, astronomicalDayLengthHours, pvLongWindowAnomaly] = ...
    auditPvWindow(day, expectedWhTime, ...
    minuteProductionWh(:, cfg.pvHomeMask), cfg.quality);

physicalCompleteByHome = all(minuteComplete, 1);
statusRunPassedByHome = longestMissingStatusRun <= ...
    cfg.quality.maxMissingStatusRunMinutes;
statusFractionPassedByHome = missingStatusFraction <= ...
    cfg.quality.maxMissingStatusFraction;
[qualityPassed, qualityReasons] = evaluateQualityContract( ...
    cfg.qualityMode, cfg.homes, physicalCompleteByHome, ...
    duplicateTimestamp, statusRunPassedByHome, ...
    statusFractionPassedByHome, pvLongWindowAnomaly, cfg.quality);

meta = struct;
meta.dataMode = cfg.dataMode;
meta.releaseIsImmutable = cfg.releaseIsImmutable;
meta.qualityMode = cfg.qualityMode;
meta.qualityModeRequested = cfg.qualityModeRequested;
meta.intervalConvention = cfg.whTimestampConvention;
meta.minuteTimeEnd = expectedWhTime;
meta.minuteComplete = minuteComplete;
meta.minuteObserved = minuteObserved;
meta.binComplete = binComplete;
meta.binObserved = binObserved;
meta.duplicateTimestampByHome = duplicateTimestamp;
meta.missingStatusRowsByHome = missingStatusRows;
meta.missingStatusFractionByHome = missingStatusFraction;
meta.longestMissingStatusRunByHome = longestMissingStatusRun;
meta.missingMinutesByHome = missingMinutes;
meta.interpolatedMinutesByHome = interpolatedMinutes;
meta.missingBinsByHome = missingBins;
meta.interpolatedBinsByHome = interpolatedBins;
meta.isComplete = all(minuteComplete, "all") && ~any(duplicateTimestamp);
meta.isFullyObserved = all(minuteObserved, "all") && ~any(duplicateTimestamp);
meta.pvWindowHours = pvWindowHours;
meta.astronomicalDayLengthHours = astronomicalDayLengthHours;
meta.pvLongWindowAnomaly = pvLongWindowAnomaly;
meta.qualityPassed = qualityPassed;
meta.qualityReasons = qualityReasons;
meta.qualityTable = table(cfg.homes.', missingMinutes.', ...
    interpolatedMinutes.', missingBins.', interpolatedBins.', ...
    missingStatusRows.', missingStatusFraction.', ...
    longestMissingStatusRun.', duplicateTimestamp.', ...
    physicalCompleteByHome.', statusRunPassedByHome.', ...
    statusFractionPassedByHome.', extraWColumnCount.', ...
    extraWColumnNames.', ...
    VariableNames=["Home", "MissingMinutes", "InterpolatedMinutes", ...
    "MissingBins", "InterpolatedBins", "MissingStatusRows", ...
    "MissingStatusFraction", "LongestMissingStatusRun", ...
    "HasDuplicateTimestamp", "PhysicalComplete", "StatusRunPassed", ...
    "StatusFractionPassed", ...
    "ExtraWColumnCount", "ExtraWColumnNames"]);
data.validForOptimization = qualityPassed;

if cfg.throwOnQualityFailure && ~qualityPassed
    messageText = "Day %s fails short_gap_only: %s. " + ...
        "Use a canonical mode to inspect META.qualityReasons without throwing.";
    error("load_storenet_day:IncompleteDay", ...
        messageText, ...
        string(day, "yyyy-MM-dd"), strjoin(qualityReasons, "; "));
end

assert(size(data.loadKW, 1) == nBins, ...
    "load_storenet_day:InternalAggregationError", ...
    "Unexpected number of aggregate bins.");
end

function [time, values, headers] = readReleaseSlice(file, desiredColumns, ...
        requestedStart, requestedEnd)
if ~isfile(file)
    error("load_storenet_day:MissingReleaseFile", ...
        "Required release file is missing: %s", file);
end

[headers, firstTime, lastTime] = inspectCsvBounds(file);
normalizedHeaders = strtrim(headers);
[found, ~] = ismember(desiredColumns, normalizedHeaders);
if ~all(found)
    missing = desiredColumns(~found);
    error("load_storenet_day:MissingColumn", ...
        "File %s is missing required column(s): %s", ...
        file, strjoin(missing, ", "));
end

readStart = max(requestedStart, firstTime);
readEnd = min(requestedEnd, lastTime);
if readStart > readEnd
    time = NaT(0, 1);
    values = nan(0, numel(desiredColumns) - 1);
    return
end

startOffset = round(minutes(readStart - firstTime));
endOffset = round(minutes(readEnd - firstTime));
opts = detectImportOptions(file, Delimiter=",", VariableNamingRule="preserve");
optionNames = string(opts.VariableNames);
normalizedOptionNames = strtrim(optionNames);
[optionFound, optionLocations] = ismember(desiredColumns, normalizedOptionNames);
if ~all(optionFound)
    error("load_storenet_day:ImportColumnMismatch", ...
        "MATLAB import options could not preserve required columns in %s.", file);
end

selectedNames = optionNames(optionLocations);
opts.SelectedVariableNames = cellstr(selectedNames);
opts.DataLines = [2 + startOffset, 2 + endOffset];
opts = setvartype(opts, cellstr(selectedNames(1)), "string");
opts = setvartype(opts, cellstr(selectedNames(2:end)), "double");
raw = readtable(file, opts);
rawNames = string(raw.Properties.VariableNames);
normalizedRawNames = strtrim(rawNames);
[~, rawLocations] = ismember(desiredColumns, normalizedRawNames);

time = datetime(string(raw{:, rawLocations(1)}), ...
    InputFormat="yyyy-MM-dd HH:mm:ss");
values = nan(height(raw), numel(desiredColumns) - 1);
for columnIndex = 2:numel(desiredColumns)
    values(:, columnIndex - 1) = double(raw{:, rawLocations(columnIndex)});
end

insideRequestedRange = time >= requestedStart & time <= requestedEnd;
time = time(insideRequestedRange);
values = values(insideRequestedRange, :);
end

function [headers, firstTime, lastTime] = inspectCsvBounds(file)
fileId = fopen(file, "rt");
if fileId < 0
    error("load_storenet_day:UnreadableReleaseFile", ...
        "Cannot open release file: %s", file);
end
cleaner = onCleanup(@() fclose(fileId));
headerLine = fgetl(fileId);
firstLine = fgetl(fileId);
headers = split(string(headerLine), ",").';
firstFields = split(string(firstLine), ",");
firstTime = datetime(firstFields(1), InputFormat="yyyy-MM-dd HH:mm:ss");

fseek(fileId, 0, "eof");
fileBytes = ftell(fileId);
tailBytes = min(fileBytes, 8192);
fseek(fileId, -tailBytes, "eof");
tailText = string(fread(fileId, tailBytes, "*char").');
tailLines = splitlines(tailText);
tailLines = tailLines(strlength(strtrim(tailLines)) > 0);
lastFields = split(tailLines(end), ",");
lastTime = datetime(lastFields(1), InputFormat="yyyy-MM-dd HH:mm:ss");
end

function [gridValues, present, hasDuplicate] = regridValues(time, values, grid)
[uniqueTime, uniqueLocations] = unique(time, "stable");
hasDuplicate = numel(uniqueTime) ~= numel(time);
uniqueValues = values(uniqueLocations, :);
[present, sourceLocations] = ismember(grid, uniqueTime);
gridValues = nan(numel(grid), size(values, 2));
gridValues(present, :) = uniqueValues(sourceLocations(present), :);
end

function energyKWh = aggregateEnergy(minuteWh, intervalMinutes)
nBins = size(minuteWh, 1) / intervalMinutes;
nHomes = size(minuteWh, 2);
energyKWh = nan(nBins, nHomes);
for homeIndex = 1:nHomes
    blocks = reshape(minuteWh(:, homeIndex), intervalMinutes, nBins);
    energyKWh(:, homeIndex) = sum(blocks, 1).' / 1000;
end
end

function binMask = aggregateMask(minuteMask, intervalMinutes)
nBins = size(minuteMask, 1) / intervalMinutes;
nHomes = size(minuteMask, 2);
binMask = false(nBins, nHomes);
for homeIndex = 1:nHomes
    blocks = reshape(minuteMask(:, homeIndex), intervalMinutes, nBins);
    binMask(:, homeIndex) = all(blocks, 1).';
end
end

function longestLength = longestFalseRun(observed)
missing = ~observed;
edges = diff([false; missing; false]);
starts = find(edges == 1);
ends = find(edges == -1) - 1;
if isempty(starts)
    longestLength = 0;
else
    longestLength = max(ends - starts + 1);
end
end

function [pvWindowHours, astronomicalDayLengthHours, anomaly] = ...
        auditPvWindow(calendarDay, minuteTimeEnd, pvMinuteWh, quality)
dayOfYear = day(calendarDay, "dayofyear");
latitudeRadians = deg2rad(quality.dingleLatitudeDegrees);
declinationRadians = deg2rad(23.44) * ...
    sin(2 * pi * (284 + double(dayOfYear)) / 365);
acosArgument = -tan(latitudeRadians) * tan(declinationRadians);
acosArgument = min(1, max(-1, acosArgument));
astronomicalDayLengthHours = 24 * acos(acosArgument) / pi;

aggregatePvWh = sum(pvMinuteWh, 2);
if ~all(isfinite(aggregatePvWh))
    pvWindowHours = NaN;
    anomaly = false;
    return
end

dailyMaximum = max(aggregatePvWh);
if dailyMaximum <= 0
    pvWindowHours = 0;
    anomaly = false;
    return
end

active = aggregatePvWh > ...
    quality.pvActiveFractionOfDailyMaximum * dailyMaximum;
firstActive = find(active, 1, "first");
lastActive = find(active, 1, "last");
pvWindowHours = (minutes(minuteTimeEnd(lastActive) - ...
    minuteTimeEnd(firstActive)) + 1) / 60;
anomaly = pvWindowHours > astronomicalDayLengthHours + ...
    quality.pvWindowToleranceHours;
end

function [passed, reasons] = evaluateQualityContract(qualityMode, homes, ...
        physicalCompleteByHome, duplicateTimestamp, statusRunPassedByHome, ...
        statusFractionPassedByHome, pvLongWindowAnomaly, quality)
reasons = strings(0, 1);
if ~all(physicalCompleteByHome)
    reasons(end + 1, 1) = "physical_incomplete:" + ...
        strjoin(homes(~physicalCompleteByHome), ",");
end
if any(duplicateTimestamp)
    reasons(end + 1, 1) = "duplicate_timestamp:" + ...
        strjoin(homes(duplicateTimestamp), ",");
end

if qualityMode ~= "release_literal"
    if ~all(statusRunPassedByHome)
        reasons(end + 1, 1) = "status_run_exceeds_" + ...
            quality.maxMissingStatusRunMinutes + "min:" + ...
            strjoin(homes(~statusRunPassedByHome), ",");
    end
    if ~all(statusFractionPassedByHome)
        reasons(end + 1, 1) = "status_fraction_exceeds_" + ...
            quality.maxMissingStatusFraction + ":" + ...
            strjoin(homes(~statusFractionPassedByHome), ",");
    end
end

if qualityMode == "exclude_flagged_pv" && pvLongWindowAnomaly
    reasons(end + 1, 1) = ...
        "pv_window_exceeds_astronomical_day_length_plus_0.5h";
end
passed = isempty(reasons);
end
