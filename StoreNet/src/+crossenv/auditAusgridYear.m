function summary = auditAusgridYear(yearData)
%AUDITAUSGRIDYEAR Summarize the frozen Ausgrid quality gate.
%   SUMMARY = crossenv.auditAusgridYear(YEARDATA) reports source rows,
%   cohort size, calendar coverage, and whole-community day rejections.

requiredFields = ["days", "qualityPassed", "rejectionReasons", ...
    "houseIds", "source"];
missingFields = requiredFields(~isfield(yearData, cellstr(requiredFields)));
if ~isempty(missingFields)
    error("crossenv:auditAusgridYear:InvalidYearData", ...
        "YEARDATA is missing field(s): %s.", ...
        strjoin(missingFields, ", "));
end
if ~isfield(yearData.source, "sourceRowCount")
    error("crossenv:auditAusgridYear:MissingSourceRowCount", ...
        "YEARDATA.source.sourceRowCount is required for the audit.");
end

releaseDays = yearData.days(:);
qualityPassed = logical(yearData.qualityPassed(:));
rejectionReasons = string(yearData.rejectionReasons(:));
if numel(qualityPassed) ~= numel(releaseDays) || ...
        numel(rejectionReasons) ~= numel(releaseDays)
    error("crossenv:auditAusgridYear:InvalidYearData", ...
        "Day, quality, and rejection-reason vectors must have equal length.");
end

rejectedMask = ~qualityPassed;
summary = struct;
summary.sourceRowCount = double(yearData.source.sourceRowCount);
summary.houseCount = numel(yearData.houseIds);
summary.calendarDayCount = numel(releaseDays);
summary.validDayCount = nnz(qualityPassed);
summary.rejectedDayCount = nnz(rejectedMask);
summary.rejectedDays = releaseDays(rejectedMask);
summary.rejectionReasons = rejectionReasons(rejectedMask);
end
