function report = audit_storenet_release(options)
%AUDIT_STORENET_RELEASE Audit provenance-relevant release quality markers.
%   REPORT = AUDIT_STORENET_RELEASE() scans the immutable processed release.
%   The W-file status field is the observation mask: blank status identifies
%   author-interpolated power rows. An affected Wh interval is marked when
%   either of its W endpoints is unobserved, intentionally including the
%   first interval after a status gap.

arguments
    options.DataRoot (1, 1) string = ""
end

cfg = storenet_config(DataRoot=options.DataRoot, QualityMode="report");
mustBeFolder(cfg.dataRoot);
nHomes = cfg.nHomes;
expectedWEnd = datetime(2021, 1, 1, 0, 59, 0);

wRows = zeros(nHomes, 1);
whRows = zeros(nHomes, 1);
wStart = NaT(nHomes, 1);
wEnd = NaT(nHomes, 1);
whStart = NaT(nHomes, 1);
whEnd = NaT(nHomes, 1);
missingStatusRows = zeros(nHomes, 1);
interpolatedIntervals = zeros(nHomes, 1);
longestMissingStatusMinutes = zeros(nHomes, 1);
longestMissingStatusStart = NaT(nHomes, 1);
longestMissingStatusEnd = NaT(nHomes, 1);
extraWColumnCount = zeros(nHomes, 1);
extraWColumnNames = strings(nHomes, 1);
tailMissingMinutes = zeros(nHomes, 1);

standardWColumns = ["date", "Discharge(W)", "Charge(W)", ...
    "Production(W)", "Consumption(W)", "State of Charge(%)"];

for homeIndex = 1:nHomes
    home = cfg.homes(homeIndex);
    wFile = fullfile(cfg.dataRoot, home + "_W.csv");
    whFile = fullfile(cfg.dataRoot, home + "_Wh.csv");
    [wTime, status, wHeaders] = readAuditColumns( ...
        wFile, ["date", home + "_W"]);
    [whTime, ~] = readAuditColumns(whFile, "date");

    observed = status == 1;
    intervalObserved = observed(1:end-1) & observed(2:end);
    [runLength, runStart, runEnd] = longestFalseRun(observed, wTime);
    normalizedWHeaders = strtrim(wHeaders);
    expectedHeaders = [standardWColumns, home + "_W"];
    extraHeaders = normalizedWHeaders(~ismember(normalizedWHeaders, expectedHeaders));

    wRows(homeIndex) = numel(wTime);
    whRows(homeIndex) = numel(whTime);
    wStart(homeIndex) = wTime(1);
    wEnd(homeIndex) = wTime(end);
    whStart(homeIndex) = whTime(1);
    whEnd(homeIndex) = whTime(end);
    missingStatusRows(homeIndex) = sum(~observed);
    interpolatedIntervals(homeIndex) = sum(~intervalObserved);
    longestMissingStatusMinutes(homeIndex) = runLength;
    longestMissingStatusStart(homeIndex) = runStart;
    longestMissingStatusEnd(homeIndex) = runEnd;
    extraWColumnCount(homeIndex) = numel(extraHeaders);
    extraWColumnNames(homeIndex) = strjoin(extraHeaders, ";");
    tailMissingMinutes(homeIndex) = max(0, round(minutes(expectedWEnd - wTime(end))));
end

summary = table(cfg.homes.', wRows, whRows, wStart, wEnd, whStart, whEnd, ...
    missingStatusRows, interpolatedIntervals, longestMissingStatusMinutes, ...
    longestMissingStatusStart, longestMissingStatusEnd, ...
    extraWColumnCount, extraWColumnNames, tailMissingMinutes, ...
    tailMissingMinutes > 0, ...
    VariableNames=["Home", "WRows", "WhRows", "WStart", "WEnd", ...
    "WhStart", "WhEnd", "MissingStatusRows", "InterpolatedIntervals", ...
    "LongestMissingStatusMinutes", "LongestMissingStatusStart", ...
    "LongestMissingStatusEnd", "ExtraWColumnCount", "ExtraWColumnNames", ...
    "TailMissingMinutes", "HasTailTruncation"]);

h4 = summary(summary.Home == "H4", :);
h14 = summary(summary.Home == "H14", :);
h16 = summary(summary.Home == "H16", :);
knownIssues = table( ...
    ["H4_W_EXTRA_COLUMN"; "H14_TAIL_TRUNCATION"; "H16_LONG_STATUS_GAP"], ...
    ["H4"; "H14"; "H16"], ...
    [NaT; h14.WEnd + minutes(1); h16.LongestMissingStatusStart], ...
    [NaT; expectedWEnd; h16.LongestMissingStatusEnd], ...
    [h4.ExtraWColumnCount; h14.TailMissingMinutes; ...
    h16.LongestMissingStatusMinutes], ...
    ["Unnamed: 6 is populated for many rows; H4 W/Wh measurements are inconsistent"; ...
    "Release ends before the community observation window"; ...
    "Status mask exposes a multi-day author-interpolated block"], ...
    VariableNames=["Code", "Home", "Start", "End", "Count", "Detail"]);

report = struct;
report.releaseName = cfg.releaseName;
report.releaseIsImmutable = cfg.releaseIsImmutable;
report.dataMode = cfg.dataMode;
report.dataRoot = cfg.dataRoot;
report.observationMaskRule = ...
    "Wh interval is observed only when both adjacent W status endpoints equal 1";
report.postGapBoundaryIsMarked = true;
report.expectedWEnd = expectedWEnd;
report.summary = summary;
report.knownIssues = knownIssues;
end

function [time, values, headers] = readAuditColumns(file, desiredColumns)
if ~isfile(file)
    error("audit_storenet_release:MissingReleaseFile", ...
        "Required release file is missing: %s", file);
end

fileId = fopen(file, "rt");
if fileId < 0
    error("audit_storenet_release:UnreadableReleaseFile", ...
        "Cannot open release file: %s", file);
end
cleaner = onCleanup(@() fclose(fileId));
headers = split(string(fgetl(fileId)), ",").';

opts = detectImportOptions(file, Delimiter=",", VariableNamingRule="preserve");
optionNames = string(opts.VariableNames);
normalizedOptionNames = strtrim(optionNames);
[found, locations] = ismember(desiredColumns, normalizedOptionNames);
if ~all(found)
    missing = desiredColumns(~found);
    error("audit_storenet_release:MissingColumn", ...
        "File %s is missing required column(s): %s", ...
        file, strjoin(missing, ", "));
end

selectedNames = optionNames(locations);
opts.SelectedVariableNames = cellstr(selectedNames);
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
end

function [longestLength, longestStart, longestEnd] = longestFalseRun(observed, time)
missing = ~observed;
edges = diff([false; missing; false]);
starts = find(edges == 1);
ends = find(edges == -1) - 1;
lengths = ends - starts + 1;
if isempty(lengths)
    longestLength = 0;
    longestStart = NaT;
    longestEnd = NaT;
    return
end
[longestLength, location] = max(lengths);
longestStart = time(starts(location));
longestEnd = time(ends(location));
end
