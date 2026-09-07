function yearData = readAusgridYear(spec, options)
%READAUSGRIDYEAR Read one frozen Ausgrid release into canonical arrays.
%   YEAR = crossenv.adapters.readAusgridYear(SPEC) returns 365 calendar
%   days with 48 interval-end samples per day for the preregistered cohort.
%   GC plus optional CL forms load; GG is inverter-AC gross PV.  A whole
%   community day is rejected when any cohort row violates the frozen
%   quality contract.  No missing value is imputed or replaced with zero,
%   except that an absent optional CL category has its contractual value 0.

arguments
    spec (1, 1) struct
    options.SourceFile (1, 1) string = ""
    options.VerifySha256 (1, 1) logical = true
end

validateSpecFields(spec);
sourceFile = resolveSourceFile(spec, options.SourceFile);
if ~isfile(sourceFile)
    error("crossenv:readAusgridYear:MissingSourceFile", ...
        "Ausgrid source CSV is missing: %s", sourceFile);
end

expectedSha256 = lower(string(spec.sourceFileSha256));
sourceSha256 = "";
if options.VerifySha256
    if isempty(regexp(expectedSha256, "^[0-9a-f]{64}$", "once"))
        error("crossenv:readAusgridYear:MissingExpectedSha256", ...
            "SPEC.sourceFileSha256 must contain a 64-digit SHA-256 hash.");
    end
    sourceSha256 = sha256File(sourceFile);
    if sourceSha256 ~= expectedSha256
        error("crossenv:readAusgridYear:Sha256Mismatch", ...
            "SHA-256 mismatch for %s. Expected %s, observed %s.", ...
            sourceFile, expectedSha256, sourceSha256);
    end
end

[raw, intervalNames] = readSourceTable(sourceFile);
sourceRowCount = height(raw);
customer = double(raw{:, 1});
generatorCapacity = double(raw{:, 2});
category = upper(strtrim(string(raw{:, 4})));
dateText = strtrim(string(raw{:, 5}));
intervalKWh = double(raw{:, 6:53});
rowQuality = string(raw{:, 54});

try
    rawDay = datetime(dateText, InputFormat="d/MM/yyyy");
catch exception
    error("crossenv:readAusgridYear:InvalidDate", ...
        "Cannot parse an Ausgrid date using d/MM/yyyy: %s", ...
        exception.message);
end

daysInYear = (spec.analysisStartDay:caldays(1):spec.analysisEndDay).';
customerIds = double(spec.analysisCustomerIds(:).');
nDays = numel(daysInYear);
nHomes = numel(customerIds);
nIntervals = numel(intervalNames);
if nDays ~= 365 || nIntervals ~= 48
    error("crossenv:readAusgridYear:InvalidReleaseShape", ...
        "The frozen release must contain 365 days and 48 intervals.");
end

[isCohortCustomer, customerIndex] = ismember(customer, customerIds);
dayIndex = round(days(rawDay - spec.analysisStartDay)) + 1;
dateIsInRange = ~isnat(rawDay) & dayIndex >= 1 & dayIndex <= nDays & ...
    rawDay == spec.analysisStartDay + caldays(dayIndex - 1);
if any(isCohortCustomer & ~dateIsInRange)
    error("crossenv:readAusgridYear:DateOutsideRelease", ...
        "A cohort row has a malformed date or lies outside the release year.");
end

gcKWh = nan(nIntervals, nHomes, nDays);
ggKWh = nan(nIntervals, nHomes, nDays);
clKWh = zeros(nIntervals, nHomes, nDays);
gcCount = zeros(nDays, nHomes, "uint8");
ggCount = zeros(nDays, nHomes, "uint8");
clCount = zeros(nDays, nHomes, "uint8");
generatorCapacityKW = nan(1, nHomes);
rejectionReasons = strings(nDays, 1);

relevantRows = find(isCohortCustomer & dateIsInRange).';
for rowIndex = relevantRows
    homeIndex = customerIndex(rowIndex);
    releaseDayIndex = dayIndex(rowIndex);
    rowCategory = category(rowIndex);
    rowValues = intervalKWh(rowIndex, :).';

    if isnan(generatorCapacityKW(homeIndex)) && ...
            isfinite(generatorCapacity(rowIndex))
        generatorCapacityKW(homeIndex) = generatorCapacity(rowIndex);
    end

    switch rowCategory
        case "GC"
            gcCount(releaseDayIndex, homeIndex) = ...
                gcCount(releaseDayIndex, homeIndex) + 1;
            if gcCount(releaseDayIndex, homeIndex) == 1
                gcKWh(:, homeIndex, releaseDayIndex) = rowValues;
            end
        case "GG"
            ggCount(releaseDayIndex, homeIndex) = ...
                ggCount(releaseDayIndex, homeIndex) + 1;
            if ggCount(releaseDayIndex, homeIndex) == 1
                ggKWh(:, homeIndex, releaseDayIndex) = rowValues;
            end
        case "CL"
            clCount(releaseDayIndex, homeIndex) = ...
                clCount(releaseDayIndex, homeIndex) + 1;
            if clCount(releaseDayIndex, homeIndex) == 1
                clKWh(:, homeIndex, releaseDayIndex) = rowValues;
            end
        otherwise
            rejectionReasons(releaseDayIndex) = appendReason( ...
                rejectionReasons(releaseDayIndex), composeReason( ...
                customer(rowIndex), rowCategory, "unexpected_category"));
    end

    qualityIsBlank = ismissing(rowQuality(rowIndex)) || ...
        strlength(strtrim(rowQuality(rowIndex))) == 0;
    if ~qualityIsBlank
        rejectionReasons(releaseDayIndex) = appendReason( ...
            rejectionReasons(releaseDayIndex), composeReason( ...
            customer(rowIndex), rowCategory, ...
            "row_quality=" + strtrim(rowQuality(rowIndex))));
    end
    if any(~isfinite(rowValues))
        rejectionReasons(releaseDayIndex) = appendReason( ...
            rejectionReasons(releaseDayIndex), composeReason( ...
            customer(rowIndex), rowCategory, "nonfinite_interval"));
    end
    if any(rowValues < 0)
        rejectionReasons(releaseDayIndex) = appendReason( ...
            rejectionReasons(releaseDayIndex), composeReason( ...
            customer(rowIndex), rowCategory, "negative_interval"));
    end
end

for releaseDayIndex = 1:nDays
    for homeIndex = 1:nHomes
        rejectionReasons(releaseDayIndex) = appendCategoryCountReasons( ...
            rejectionReasons(releaseDayIndex), ...
            customerIds(homeIndex), gcCount(releaseDayIndex, homeIndex), ...
            ggCount(releaseDayIndex, homeIndex), ...
            clCount(releaseDayIndex, homeIndex));
    end
end

loadKWh = gcKWh + clKWh;
pvKWh = ggKWh;
qualityPassed = strlength(rejectionReasons) == 0;
dtHours = double(spec.dtHours);

source = struct;
source.sourceFile = sourceFile;
source.sourceSha256 = sourceSha256;
source.expectedSha256 = expectedSha256;
source.sha256Verified = options.VerifySha256;
source.datasetId = string(spec.datasetId);
source.officialMetadataUrl = string(spec.officialMetadataUrl);
source.archiveUrl = string(spec.archiveUrl);
source.archiveLicense = string(spec.archiveLicense);
source.sourceRowCount = sourceRowCount;
source.energyUnit = string(spec.energyUnit);
source.timestampBasis = string(spec.timestampBasis);
source.loadDefinition = string(spec.loadDefinition);
source.pvDefinition = string(spec.pvDefinition);
source.pvMeasurementBasis = string(spec.pvMeasurementBasis);
source.pvIsAC = logical(spec.pvIsAC);

yearData = struct;
yearData.days = daysInYear;
yearData.loadKW = loadKWh / dtHours;
yearData.pvKW = pvKWh / dtHours;
yearData.qualityPassed = qualityPassed;
yearData.rejectionReasons = rejectionReasons;
yearData.customerIds = customerIds;
yearData.houseIds = "AUS" + string(customerIds);
yearData.generatorCapacityKW = generatorCapacityKW;
yearData.dtHours = dtHours;
yearData.intervalMinutes = double(spec.intervalMinutes);
yearData.validForOptimization = qualityPassed;
yearData.source = source;
yearData.sourceProvenance = source;
end

function validateSpecFields(spec)
required = ["sourceFilePath", "sourceFileSha256", ...
    "analysisCustomerIds", "analysisStartDay", "analysisEndDay", ...
    "dtHours", "intervalMinutes", "datasetId", "officialMetadataUrl", ...
    "archiveUrl", "archiveLicense", "energyUnit", "timestampBasis", ...
    "loadDefinition", "pvDefinition", "pvMeasurementBasis", "pvIsAC"];
missing = required(~isfield(spec, cellstr(required)));
if ~isempty(missing)
    error("crossenv:readAusgridYear:InvalidSpec", ...
        "SPEC is missing field(s): %s. Load it with " + ...
        "crossenv.loadAusgridSpec.", strjoin(missing, ", "));
end
end

function sourceFile = resolveSourceFile(spec, sourceFileOption)
sourceFile = sourceFileOption;
if strlength(sourceFile) == 0
    sourceFile = string(spec.sourceFilePath);
elseif ~isAbsolutePath(sourceFile)
    sourceFile = string(fullfile(pwd, sourceFile));
end
end

function tf = isAbsolutePath(pathValue)
pathValue = string(pathValue);
tf = startsWith(pathValue, filesep) || ...
    ~isempty(regexp(pathValue, "^[A-Za-z]:[\\/]", "once"));
end

function [raw, intervalNames] = readSourceTable(sourceFile)
try
    importOptions = detectImportOptions(sourceFile, ...
        NumHeaderLines=1, VariableNamingRule="preserve");
catch exception
    error("crossenv:readAusgridYear:UnreadableSource", ...
        "Cannot inspect Ausgrid CSV %s: %s", sourceFile, exception.message);
end

intervalNames = expectedIntervalNames();
expectedNames = ["Customer", "Generator Capacity", "Postcode", ...
    "Consumption Category", "date", intervalNames, "Row Quality"];
observedNames = string(importOptions.VariableNames);
if ~isequal(observedNames, expectedNames)
    error("crossenv:readAusgridYear:InvalidColumns", ...
        "Ausgrid CSV must have the exact metadata, 48 interval, and " + ...
        "Row Quality columns from the release.");
end

numericNames = observedNames([1, 2, 6:53]);
textNames = observedNames([3, 4, 5, 54]);
importOptions = setvartype(importOptions, numericNames, "double");
importOptions = setvartype(importOptions, textNames, "string");
importOptions = setvaropts(importOptions, "Row Quality", ...
    TreatAsMissing={});
try
    raw = readtable(sourceFile, importOptions);
catch exception
    error("crossenv:readAusgridYear:UnreadableSource", ...
        "Cannot read Ausgrid CSV %s: %s", sourceFile, exception.message);
end
end

function names = expectedIntervalNames()
names = strings(1, 48);
for intervalIndex = 1:48
    endMinutes = 30 * intervalIndex;
    hourValue = mod(floor(endMinutes / 60), 24);
    minuteValue = mod(endMinutes, 60);
    names(intervalIndex) = string(sprintf("%d:%02d", ...
        hourValue, minuteValue));
end
end

function combined = appendCategoryCountReasons(combined, customerId, ...
        gcCount, ggCount, clCount)
if gcCount == 0
    combined = appendReason(combined, ...
        composeReason(customerId, "GC", "missing_required"));
elseif gcCount > 1
    combined = appendReason(combined, ...
        composeReason(customerId, "GC", "duplicate_required"));
end
if ggCount == 0
    combined = appendReason(combined, ...
        composeReason(customerId, "GG", "missing_required"));
elseif ggCount > 1
    combined = appendReason(combined, ...
        composeReason(customerId, "GG", "duplicate_required"));
end
if clCount > 1
    combined = appendReason(combined, ...
        composeReason(customerId, "CL", "duplicate_optional"));
end
end

function reason = composeReason(customerId, category, condition)
reason = "customer=" + string(customerId) + ",category=" + ...
    string(category) + ",reason=" + string(condition);
end

function combined = appendReason(existing, addition)
if strlength(existing) == 0
    combined = addition;
else
    combined = existing + "; " + addition;
end
end

function digest = sha256File(path)
digest = storenetio.hashFile(path);
end

