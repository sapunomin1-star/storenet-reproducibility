function [data, meta] = loadAusgridDay(day, spec, options)
%LOADAUSGRIDDAY Load one canonical Ausgrid community day.
%   [DATA,META] = crossenv.adapters.loadAusgridDay(DAY,SPEC) returns 48
%   half-hour interval-end load/PV samples.  Rejected days remain
%   inspectable and are marked DATA.validForOptimization=false; this
%   adapter never sends data to a solver and never imputes a rejected day.

arguments
    day (1, 1) datetime
    spec (1, 1) struct
    options.SourceFile (1, 1) string = ""
    options.VerifySha256 (1, 1) logical = true
end

day = dateshift(day, "start", "day");
sourceFile = resolvedSourceFile(spec, options.SourceFile);
fileInfo = dir(sourceFile);
if isempty(fileInfo)
    error("crossenv:loadAusgridDay:MissingSourceFile", ...
        "Ausgrid source CSV is missing: %s", sourceFile);
end
cacheKey = sourceFile + "|" + string(fileInfo.bytes) + "|" + ...
    string(sprintf("%.15g", fileInfo.datenum)) + "|" + ...
    strjoin(string(spec.analysisCustomerIds(:).'), ",") + "|" + ...
    string(spec.analysisStartDay, "yyyy-MM-dd") + "|" + ...
    string(spec.analysisEndDay, "yyyy-MM-dd") + "|" + ...
    string(sprintf("%.15g", double(spec.dtHours))) + "|" + ...
    lower(string(spec.sourceFileSha256)) + "|" + ...
    string(options.VerifySha256);

persistent cachedKey cachedYear
if isempty(cachedKey) || cachedKey ~= cacheKey
    cachedYear = crossenv.adapters.readAusgridYear(spec, ...
        SourceFile=sourceFile, VerifySha256=options.VerifySha256);
    cachedKey = cacheKey;
end

dayIndex = find(cachedYear.days == day, 1, "first");
if isempty(dayIndex)
    error("crossenv:loadAusgridDay:DayOutsideRelease", ...
        "Day %s is outside the frozen Ausgrid release.", ...
        string(day, "yyyy-MM-dd"));
end

timeEnd = (day + minutes(cachedYear.intervalMinutes): ...
    minutes(cachedYear.intervalMinutes):day + days(1)).';
loadKW = cachedYear.loadKW(:, :, dayIndex);
pvKW = cachedYear.pvKW(:, :, dayIndex);
qualityPassed = cachedYear.qualityPassed(dayIndex);
rejectionReasons = cachedYear.rejectionReasons(dayIndex);

data = struct;
data.day = day;
data.time = timeEnd;
data.timeEnd = timeEnd;
data.loadKW = loadKW;
data.pvKW = pvKW;
data.loadKWh = loadKW * cachedYear.dtHours;
data.pvKWh = pvKW * cachedYear.dtHours;
data.dtHours = cachedYear.dtHours;
data.intervalMinutes = cachedYear.intervalMinutes;
data.customerIds = cachedYear.customerIds;
data.houseIds = cachedYear.houseIds;
data.generatorCapacityKW = cachedYear.generatorCapacityKW;
data.validForOptimization = qualityPassed;

meta = struct;
meta.qualityPassed = qualityPassed;
meta.rejectionReasons = rejectionReasons;
meta.qualityReasons = rejectionReasons;
meta.source = cachedYear.source;
meta.sourceProvenance = cachedYear.source;
meta.intervalConvention = ...
    "interval ends; calendar day D uses (D 00:00, D+1 00:00]";
meta.pvMeasurementBasis = cachedYear.source.pvMeasurementBasis;
meta.pvIsAC = cachedYear.source.pvIsAC;
meta.etaPvAC = double(spec.fixedPolicyTransfer.etaPvAC);
end

function sourceFile = resolvedSourceFile(spec, sourceFileOption)
if strlength(sourceFileOption) == 0
    if ~isfield(spec, "sourceFilePath")
        error("crossenv:loadAusgridDay:InvalidSpec", ...
            "SPEC must be loaded with crossenv.loadAusgridSpec.");
    end
    sourceFile = string(spec.sourceFilePath);
elseif isAbsolutePath(sourceFileOption)
    sourceFile = sourceFileOption;
else
    sourceFile = string(fullfile(pwd, sourceFileOption));
end
end

function tf = isAbsolutePath(pathValue)
pathValue = string(pathValue);
tf = startsWith(pathValue, filesep) || ...
    ~isempty(regexp(pathValue, "^[A-Za-z]:[\\/]", "once"));
end
