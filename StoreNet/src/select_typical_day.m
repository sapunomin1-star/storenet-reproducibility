function [selectedDay, ranking] = select_typical_day(options)
%SELECT_TYPICAL_DAY Select a public-data proxy for the unpublished Fig. 5 day.
%   [DAY,RANKING] = SELECT_TYPICAL_DAY() ranks candidate dates only by the
%   frozen digitized aggregate load/PV curves. Optimization results are never
%   evaluated by this function. Dates are ranked first; the first date that
%   passes the requested data-quality gate is selected.

arguments
    options.CandidateDates datetime = datetime(2020, 1, 1):caldays(1):datetime(2020, 12, 10)
    options.ReferenceFile (1, 1) string = ""
    options.DataRoot (1, 1) string = ""
    options.QualityMode (1, 1) string {mustBeMember(options.QualityMode, ...
        ["release_literal", "short_gap_only", "exclude_flagged_pv"])} = ...
        "exclude_flagged_pv"
    options.DataProvider (1, 1) function_handle = @load_storenet_day
end

sourceFolder = fileparts(mfilename("fullpath"));
if strlength(options.ReferenceFile) == 0
    options.ReferenceFile = string(fullfile(sourceFolder, "..", "reference", ...
        "paper_fig5_profile_digitized.csv"));
end
if ~isfile(options.ReferenceFile)
    error("StoreNet:MissingFigure5Reference", ...
        "Digitized Figure 5 reference is missing: %s", options.ReferenceFile);
end

reference = readtable(options.ReferenceFile, VariableNamingRule="preserve");
requiredReferenceColumns = ["load_kw", "pv_kw"];
missingReferenceColumns = requiredReferenceColumns(~ismember( ...
    requiredReferenceColumns, string(reference.Properties.VariableNames)));
if ~isempty(missingReferenceColumns)
    error("StoreNet:InvalidFigure5Reference", ...
        "Figure 5 reference is missing column(s): %s.", ...
        strjoin(missingReferenceColumns, ", "));
end
referenceLoadKW = double(reference.load_kw(:));
referencePvKW = double(reference.pv_kw(:));
if isempty(referenceLoadKW) || any(~isfinite(referenceLoadKW)) || ...
        any(~isfinite(referencePvKW))
    error("StoreNet:InvalidFigure5Reference", ...
        "Figure 5 load/PV reference values must be finite and nonempty.");
end

candidateDates = unique(dateshift(options.CandidateDates(:), "start", "day"), ...
    "sorted");
if isempty(candidateDates)
    error("StoreNet:NoTypicalDayCandidates", ...
        "CandidateDates must contain at least one date.");
end

nCandidates = numel(candidateDates);
score = inf(nCandidates, 1);
qualityPassed = false(nCandidates, 1);
qualityStatus = repmat("not_evaluated", nCandidates, 1);
qualityMessage = strings(nCandidates, 1);
loadEnergyKWh = nan(nCandidates, 1);
pvEnergyKWh = nan(nCandidates, 1);
loadPeakKW = nan(nCandidates, 1);
pvPeakKW = nan(nCandidates, 1);

for dateIndex = 1:nCandidates
    day = candidateDates(dateIndex);
    try
        [scoreData, ~] = callDataProvider(options.DataProvider, day, ...
            options.DataRoot, "release_literal");
        scoreData = normalizeExperimentData(scoreData);
        aggregateLoadKW = sum(double(scoreData.loadKW), 2);
        aggregatePvKW = sum(double(scoreData.pvKW), 2);
        if numel(aggregateLoadKW) ~= numel(referenceLoadKW)
            error("StoreNet:Figure5LengthMismatch", ...
                "Date %s has %d intervals; Figure 5 reference has %d.", ...
                string(day, "yyyy-MM-dd"), numel(aggregateLoadKW), ...
                numel(referenceLoadKW));
        end
        score(dateIndex) = sqrt(mean( ...
            ((aggregateLoadKW - referenceLoadKW) ./ 20).^2 + ...
            ((aggregatePvKW - referencePvKW) ./ 10).^2));
        loadEnergyKWh(dateIndex) = scoreData.dtHours * sum(aggregateLoadKW);
        pvEnergyKWh(dateIndex) = scoreData.dtHours * sum(aggregatePvKW);
        loadPeakKW(dateIndex) = max(aggregateLoadKW);
        pvPeakKW(dateIndex) = max(aggregatePvKW);
    catch exception
        qualityStatus(dateIndex) = "score_unavailable";
        qualityMessage(dateIndex) = string(exception.identifier) + ": " + ...
            string(exception.message);
        continue
    end

    try
        callDataProvider(options.DataProvider, day, options.DataRoot, ...
            options.QualityMode);
        qualityPassed(dateIndex) = true;
        qualityStatus(dateIndex) = "passed";
        qualityMessage(dateIndex) = "";
    catch exception
        qualityStatus(dateIndex) = "quality_rejected";
        qualityMessage(dateIndex) = string(exception.identifier) + ": " + ...
            string(exception.message);
    end
end

ranking = table(candidateDates, score, qualityPassed, qualityStatus, ...
    qualityMessage, loadEnergyKWh, pvEnergyKWh, loadPeakKW, pvPeakKW, ...
    VariableNames=["Day", "Score", "QualityPassed", "QualityStatus", ...
    "QualityMessage", "LoadEnergyKWh", "PvEnergyKWh", "LoadPeakKW", ...
    "PvPeakKW"]);
ranking = sortrows(ranking, ["Score", "Day"], ["ascend", "ascend"]);
ranking.Selected = false(height(ranking), 1);
selectedLocation = find(ranking.QualityPassed & isfinite(ranking.Score), 1, "first");
if isempty(selectedLocation)
    error("StoreNet:NoPassingTypicalDay", ...
        "No candidate date has both a finite Figure 5 score and a passing quality gate.");
end
ranking.Selected(selectedLocation) = true;
selectedDay = ranking.Day(selectedLocation);
end

function [data, meta] = callDataProvider(provider, day, dataRoot, qualityMode)
try
    [data, meta] = provider(day, DataRoot=dataRoot, IntervalMinutes=30, ...
        QualityMode=qualityMode);
catch exception
    legacyMode = legacyQualityMode(qualityMode);
    if legacyMode == qualityMode || ~isArgumentValidationFailure(exception)
        rethrow(exception)
    end
    [data, meta] = provider(day, DataRoot=dataRoot, IntervalMinutes=30, ...
        QualityMode=legacyMode);
end
enforceQualityMetadata(meta, day, qualityMode);
end

function enforceQualityMetadata(meta, day, qualityMode)
if isfield(meta, "qualityPassed") && ~logical(meta.qualityPassed)
    reasons = "quality contract returned false";
    if isfield(meta, "qualityReasons") && ~isempty(meta.qualityReasons)
        reasons = strjoin(string(meta.qualityReasons), "; ");
    end
    error("StoreNet:QualityRejected", "Day %s fails %s: %s.", ...
        string(day, "yyyy-MM-dd"), qualityMode, reasons);
end
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
