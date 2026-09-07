function [selection, ranking] = selectMonthlyDays(yearData)
%SELECTMONTHLYDAYS Select one preregistered robust-central day per month.
%   [SELECTION,RANKING] = crossenv.selectMonthlyDays(YEARDATA) uses only
%   quality-passed input profiles.  Each day's 96 features are its 48-point
%   aggregate load followed by its 48-point aggregate PV.  Features are
%   standardized coordinate-wise by the within-month median and unscaled
%   median absolute deviation (zero MAD is replaced with one).  The score
%   is RMS standardized distance to the monthly median.  Equal scores are
%   resolved by the earliest calendar date.  No solver or outcome is read.

requiredFields = ["days", "loadKW", "pvKW", "qualityPassed"];
missingFields = requiredFields(~isfield(yearData, cellstr(requiredFields)));
if ~isempty(missingFields)
    error("crossenv:selectMonthlyDays:InvalidYearData", ...
        "YEARDATA is missing field(s): %s.", ...
        strjoin(missingFields, ", "));
end

releaseDays = yearData.days(:);
qualityPassed = logical(yearData.qualityPassed(:));
nDays = numel(releaseDays);
if size(yearData.loadKW, 1) ~= 48 || size(yearData.pvKW, 1) ~= 48 || ...
        size(yearData.loadKW, 3) ~= nDays || ...
        size(yearData.pvKW, 3) ~= nDays || ...
        size(yearData.loadKW, 2) ~= size(yearData.pvKW, 2) || ...
        numel(qualityPassed) ~= nDays
    error("crossenv:selectMonthlyDays:InvalidYearShape", ...
        "YEARDATA must provide matched 48-by-N-by-day load/PV arrays.");
end

passedIndices = find(qualityPassed);
if isempty(passedIndices)
    error("crossenv:selectMonthlyDays:NoPassingDays", ...
        "No Ausgrid day passes the frozen quality contract.");
end

aggregateLoadKW = squeeze(sum(yearData.loadKW, 2));
aggregatePvKW = squeeze(sum(yearData.pvKW, 2));
features = [aggregateLoadKW(:, passedIndices).', ...
    aggregatePvKW(:, passedIndices).'];
if any(~isfinite(features), "all") || any(features < 0, "all")
    error("crossenv:selectMonthlyDays:InvalidPassingProfile", ...
        "Every quality-passed aggregate load/PV value must be finite " + ...
        "and nonnegative.");
end

passedDays = releaseDays(passedIndices);
passedMonths = month(passedDays);
scores = nan(numel(passedDays), 1);
selectedDays = NaT(12, 1);
selectedScores = nan(12, 1);
candidateCounts = zeros(12, 1);

for monthValue = 1:12
    candidateRows = find(passedMonths == monthValue);
    if isempty(candidateRows)
        error("crossenv:selectMonthlyDays:MissingMonth", ...
            "Calendar month %d has no quality-passed candidate day.", ...
            monthValue);
    end
    monthlyFeatures = features(candidateRows, :);
    center = median(monthlyFeatures, 1);
    featureMad = median(abs(monthlyFeatures - center), 1);
    featureMad(featureMad == 0) = 1;
    standardized = (monthlyFeatures - center) ./ featureMad;
    monthlyScores = sqrt(mean(standardized .^ 2, 2));
    scores(candidateRows) = monthlyScores;

    ordered = table(monthlyScores, passedDays(candidateRows), ...
        VariableNames=["Score", "Day"]);
    ordered = sortrows(ordered, ["Score", "Day"], ...
        ["ascend", "ascend"]);
    selectedDays(monthValue) = ordered.Day(1);
    selectedScores(monthValue) = ordered.Score(1);
    candidateCounts(monthValue) = numel(candidateRows);
end

monthColumn = (1:12).';
selection = table(monthColumn, selectedDays, selectedScores, ...
    candidateCounts, VariableNames=["Month", "Day", "Score", ...
    "CandidateCount"]);

selected = ismember(passedDays, selectedDays);
ranking = table(passedMonths, passedDays, scores, selected, ...
    VariableNames=["Month", "Day", "Score", "Selected"]);
ranking = sortrows(ranking, ["Month", "Score", "Day"], ...
    ["ascend", "ascend", "ascend"]);
end
