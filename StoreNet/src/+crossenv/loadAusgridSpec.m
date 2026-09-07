function spec = loadAusgridSpec(specPathArgument, options)
%LOADAUSGRIDSPEC Load and validate the frozen Ausgrid data specification.
%   SPEC = crossenv.loadAusgridSpec() loads the repository specification.
%   SPEC = crossenv.loadAusgridSpec(SPECPATH) also accepts a positional
%   path.  The equivalent name-value form is
%   crossenv.loadAusgridSpec(SpecPath=SPECPATH).

arguments
    specPathArgument (1, 1) string = ""
    options.SpecPath (1, 1) string = ""
end

if strlength(specPathArgument) > 0 && strlength(options.SpecPath) > 0
    error("crossenv:loadAusgridSpec:AmbiguousSpecPath", ...
        "Specify the Ausgrid specification path once, not twice.");
end

packageFolder = fileparts(mfilename("fullpath"));
projectRoot = fileparts(fileparts(packageFolder));
specPath = specPathArgument;
if strlength(options.SpecPath) > 0
    specPath = options.SpecPath;
end
if strlength(specPath) == 0
    specPath = string(fullfile(projectRoot, "config", "crossenv", ...
        "ausgrid_2012_2013.json"));
end
specPath = string(char(javaFreeAbsolutePath(specPath)));

if ~isfile(specPath)
    error("crossenv:loadAusgridSpec:MissingSpec", ...
        "Ausgrid specification is missing: %s", specPath);
end

try
    spec = jsondecode(fileread(specPath));
catch exception
    error("crossenv:loadAusgridSpec:InvalidJson", ...
        "Cannot parse Ausgrid specification %s: %s", ...
        specPath, exception.message);
end

requiredFields = ["schemaVersion", "datasetId", "officialMetadataUrl", ...
    "archiveUrl", "archiveLicense", "releaseManifestPath", ...
    "sourceFile", "sourceFileSha256", "sourceIntervalMinutes", ...
    "timestampBasis", "energyUnit", "loadDefinition", "pvDefinition", ...
    "analysisCustomerIds", "qualityContract", "fixedPolicyTransfer", ...
    "primarySelection"];
missingFields = requiredFields(~isfield(spec, cellstr(requiredFields)));
if ~isempty(missingFields)
    error("crossenv:loadAusgridSpec:MissingField", ...
        "Ausgrid specification is missing field(s): %s.", ...
        strjoin(missingFields, ", "));
end

spec.analysisCustomerIds = double(spec.analysisCustomerIds(:).');
validateCustomerIds(spec.analysisCustomerIds);
if isfield(spec, "publishedCleanCustomerIds")
    spec.publishedCleanCustomerIds = ...
        double(spec.publishedCleanCustomerIds(:).');
end
if isfield(spec, "excludedCustomerIds")
    spec.excludedCustomerIds = double(spec.excludedCustomerIds(:).');
end

requiredCategories = upper(string( ...
    spec.qualityContract.requiredCategories(:).'));
optionalCategories = upper(string( ...
    spec.qualityContract.optionalCategories(:).'));
if ~isequal(sort(requiredCategories), ["GC", "GG"]) || ...
        ~isequal(optionalCategories, "CL")
    error("crossenv:loadAusgridSpec:InvalidQualityContract", ...
        "The frozen Ausgrid contract requires GC and GG exactly once " + ...
        "and permits CL at most once.");
end
if string(spec.qualityContract.acceptedRowQuality) ~= "blank only" || ...
        string(spec.qualityContract.imputation) ~= "none"
    error("crossenv:loadAusgridSpec:InvalidQualityContract", ...
        "The frozen Ausgrid contract accepts blank Row Quality only " + ...
        "and performs no imputation.");
end

intervalMinutes = double(spec.sourceIntervalMinutes);
if ~isscalar(intervalMinutes) || ~isfinite(intervalMinutes) || ...
        intervalMinutes ~= 30
    error("crossenv:loadAusgridSpec:InvalidInterval", ...
        "Ausgrid sourceIntervalMinutes must equal 30.");
end
if double(spec.fixedPolicyTransfer.etaPvAC) ~= 1
    error("crossenv:loadAusgridSpec:InvalidPvBasis", ...
        "Inverter-AC GG data requires fixedPolicyTransfer.etaPvAC = 1.");
end

[analysisStartDay, analysisEndDay] = parseReleaseYear(spec.datasetId);
sourceFilePath = resolveSourcePath(specPath, projectRoot, spec.sourceFile);
manifestPath = resolveManifestPath(projectRoot, spec.releaseManifestPath);

spec.specPath = specPath;
spec.projectRoot = string(projectRoot);
spec.sourceFilePath = sourceFilePath;
spec.releaseManifestFullPath = manifestPath;
spec.intervalMinutes = intervalMinutes;
spec.dtHours = intervalMinutes / 60;
spec.analysisStartDay = analysisStartDay;
spec.analysisEndDay = analysisEndDay;
spec.pvMeasurementBasis = "inverter-AC";
spec.pvIsAC = true;
end

function validateCustomerIds(customerIds)
valid = ~isempty(customerIds) && all(isfinite(customerIds)) && ...
    all(customerIds > 0) && all(customerIds == floor(customerIds)) && ...
    numel(unique(customerIds)) == numel(customerIds);
if ~valid
    error("crossenv:loadAusgridSpec:InvalidCustomerIds", ...
        "analysisCustomerIds must be unique positive integers.");
end
end

function [startDay, endDay] = parseReleaseYear(datasetId)
tokens = regexp(string(datasetId), "(\d{4})-(\d{4})$", ...
    "tokens", "once");
if isempty(tokens)
    error("crossenv:loadAusgridSpec:InvalidDatasetId", ...
        "datasetId must end with the Ausgrid release years YYYY-YYYY.");
end
startYear = str2double(tokens{1});
endYear = str2double(tokens{2});
if endYear ~= startYear + 1
    error("crossenv:loadAusgridSpec:InvalidDatasetId", ...
        "Ausgrid release years must be consecutive.");
end
startDay = datetime(startYear, 7, 1);
endDay = datetime(endYear, 6, 30);
end

function sourcePath = resolveSourcePath(specPath, projectRoot, sourceFile)
sourceFile = string(sourceFile);
if isAbsolutePath(sourceFile)
    sourcePath = sourceFile;
    return
end

besideSpec = string(fullfile(fileparts(specPath), sourceFile));
repositoryDefault = string(fullfile(projectRoot, "data", "external", ...
    "ausgrid", "raw", "extracted", sourceFile));
if isfile(besideSpec)
    sourcePath = besideSpec;
else
    sourcePath = repositoryDefault;
end
sourcePath = javaFreeAbsolutePath(sourcePath);
end

function manifestPath = resolveManifestPath(projectRoot, manifestReference)
manifestReference = replace(string(manifestReference), "\\", "/");
if startsWith(manifestReference, "StoreNet/")
    manifestReference = extractAfter(manifestReference, "StoreNet/");
end
if isAbsolutePath(manifestReference)
    manifestPath = manifestReference;
else
    manifestPath = string(fullfile(projectRoot, manifestReference));
end
manifestPath = javaFreeAbsolutePath(manifestPath);
end

function tf = isAbsolutePath(pathValue)
pathValue = string(pathValue);
tf = startsWith(pathValue, filesep) || ...
    ~isempty(regexp(pathValue, "^[A-Za-z]:[\\/]", "once"));
end

function absolutePath = javaFreeAbsolutePath(pathValue)
pathValue = string(pathValue);
if isAbsolutePath(pathValue)
    absolutePath = pathValue;
else
    absolutePath = string(fullfile(pwd, pathValue));
end
end
