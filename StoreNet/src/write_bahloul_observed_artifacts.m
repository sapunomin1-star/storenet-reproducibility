function artifacts = write_bahloul_observed_artifacts(caseDirectory, data, ...
        config, caseMeta, metrics, profiles)
%WRITE_BAHLOUL_OBSERVED_ARTIFACTS Persist an observed SB-SC proxy case.
%   Inputs and solution-like observations are independently content
%   addressed from their final MAT-file bytes. The MAT payloads do not
%   contain their own hashes, avoiding a checksum cycle.

arguments
    caseDirectory (1, 1) string
    data (1, 1) struct
    config (1, 1) struct
    caseMeta (1, 1) struct
    metrics (1, 1) struct
    profiles table
end

[observedData, observedConfig, observedMeta] = ...
    prepare_observed_sbsc_case(data, config, caseMeta);
[canonicalMetrics, canonicalProfiles] = evaluate_observed_sbsc( ...
    observedData, observedConfig);
if ~isequaln(metrics, canonicalMetrics)
    error("StoreNet:ObservedBahloulMetricMismatch", ...
        "Observed metrics must equal a direct-release offline reevaluation.");
end
if ~isequaln(profiles, canonicalProfiles)
    error("StoreNet:ObservedBahloulProfileMismatch", ...
        "Observed profiles must equal a direct-release offline reevaluation.");
end
metrics = canonicalMetrics;
profiles = canonicalProfiles;

directoryAlreadyExisted = isfolder(caseDirectory);
if directoryAlreadyExisted && hasMaterialEntries(caseDirectory)
    error("StoreNet:BahloulCaseDirectoryExists", ...
        "Refusing to overwrite nonempty case directory: %s", caseDirectory);
end
if ~directoryAlreadyExisted
    mkdir(caseDirectory);
end
temporaryInputsPath = string(tempname(caseDirectory)) + ".mat";
temporarySolutionPath = string(tempname(caseDirectory)) + ".mat";
profilesPath = string(fullfile(caseDirectory, "profiles.csv"));
metricsPath = string(fullfile(caseDirectory, "metrics.json"));
createdPaths = strings(0, 1);

try
    inputEvidence = makeInputEvidence(observedData, observedConfig, ...
        observedMeta);
    solutionEvidence = makeSolutionEvidence(metrics, profiles, observedMeta);
    save(temporaryInputsPath, "inputEvidence", "-v7");
    save(temporarySolutionPath, "solutionEvidence", "-v7");
    inputsSha256 = sha256File(temporaryInputsPath);
    solutionSha256 = sha256File(temporarySolutionPath);
    inputsPath = string(fullfile(caseDirectory, ...
        "inputs_" + inputsSha256 + ".mat"));
    solutionPath = string(fullfile(caseDirectory, ...
        "solution_" + solutionSha256 + ".mat"));
    refuseExistingTarget(inputsPath);
    refuseExistingTarget(solutionPath);
    moveArtifact(temporaryInputsPath, inputsPath);
    createdPaths(end + 1, 1) = inputsPath;
    moveArtifact(temporarySolutionPath, solutionPath);
    createdPaths(end + 1, 1) = solutionPath;
    writetable(profiles, profilesPath);
    createdPaths(end + 1, 1) = profilesPath;
    writeJson(metricsPath, metrics);
catch exception
    deleteIfPresent(temporaryInputsPath);
    deleteIfPresent(temporarySolutionPath);
    deleteCreatedPaths(createdPaths);
    removeNewEmptyDirectory(caseDirectory, directoryAlreadyExisted);
    rethrow(exception)
end

artifacts = struct;
artifacts.inputsPath = inputsPath;
artifacts.inputsSha256 = inputsSha256;
artifacts.solutionPath = solutionPath;
artifacts.solutionSha256 = solutionSha256;
artifacts.profilesPath = profilesPath;
artifacts.profilesSha256 = sha256File(profilesPath);
artifacts.metricsPath = metricsPath;
artifacts.metricsSha256 = sha256File(metricsPath);
end

function evidence = makeInputEvidence(data, config, caseMeta)
timeEnd = data.time(:);
dtHours = double(data.dtHours);
intervalStart = timeEnd - hours(dtHours);
dayMask = hour(intervalStart) >= config.dayStartHour & ...
    hour(intervalStart) < config.dayEndHour;
pricePerKWh = repmat(double(config.nightPrice), numel(timeEnd), 1);
pricePerKWh(dayMask) = double(config.dayPrice);

evidence = struct;
evidence.schemaVersion = "B2022-observed-input-evidence-v2";
evidence.observationDefinition = config.observationDefinition;
evidence.timeEnd = timeEnd;
evidence.intervalStart = intervalStart;
evidence.dtHours = dtHours;
evidence.houseIds = string(data.houseIds(:)).';
evidence.observedLoadKW = double(data.loadKW);
evidence.observedProductionKW = double(data.releasedPvKW);
evidence.observedGridImportKW = double(data.fromGridKW);
evidence.observedFeedInKW = optionalNumericField(data, "feedInKW");
evidence.observedChargeKW = optionalNumericField(data, "chargeKW");
evidence.observedDischargeKW = optionalNumericField(data, "dischargeKW");
evidence.pricePerKWh = pricePerKWh;
evidence.dayMask = logical(dayMask);
evidence.qualityMode = optionalStringField(caseMeta, "qualityMode", ...
    "unavailable");
evidence.observationMask = optionalLogicalField(caseMeta, ...
    "observationMask");
evidence.interpolationMask = optionalLogicalField(caseMeta, ...
    "interpolationMask");
evidence.cohortMask = optionalLogicalField(caseMeta, "cohortMask");
evidence.h4MaskAffected = optionalScalarField(caseMeta, ...
    "h4MaskAffected", NaN);
evidence.h4Mask = observedH4Mask(caseMeta, numel(timeEnd));
evidence.maskAvailability = makeMaskAvailability(caseMeta);
evidence.identity = makeObservedIdentity(caseMeta);
evidence.data = data;
evidence.config = config;
evidence.caseMeta = caseMeta;
end

function evidence = makeSolutionEvidence(metrics, profiles, caseMeta)
evidence = struct;
evidence.schemaVersion = "B2022-observed-solution-evidence-v2";
evidence.observationDefinition = caseMeta.observationDefinition;
evidence.identity = makeObservedIdentity(caseMeta);
evidence.solverInvoked = false;
evidence.profiles = profiles;
evidence.metrics = metrics;
evidence.solutionLike = struct( ...
    "timeEnd", profiles.TimeEnd(:), ...
    "observedLoadKW", double(profiles.LoadKW), ...
    "observedProductionKW", double(profiles.ObservedReleasedPvKW), ...
    "observedGridImportKW", double(profiles.GridImportKW), ...
    "observedBatteryKW", double(profiles.ReleaseBatterySignedKW), ...
    "observedFeedInKW", double(profiles.FeedInKW));
evidence.provenance = observedProvenance(caseMeta);
end

function provenance = observedProvenance(caseMeta)
provenance = struct;
provenance.solver = struct("applicable", false, ...
    "reason", "observed release fields; no solver invoked");
provenance.provider = optionalStructField(caseMeta, ...
    "dataProviderProvenance");
provenance.runtime = struct( ...
    "matlabVersion", string(version), ...
    "matlabRelease", string(version("-release")), ...
    "computer", string(computer), ...
    "timestampUtc", datetime("now", TimeZone="UTC", ...
    Format="yyyy-MM-dd'T'HH:mm:ss.SSSXXX"));
end

function identity = makeObservedIdentity(caseMeta)
identity = struct;
identity.experimentId = identityRecordAny(caseMeta, "experimentId");
identity.caseId = identityRecordAny(caseMeta, "caseId");
identity.dateOrPeriod = identityRecordAny(caseMeta, ...
    ["day", "dateOrPeriod"]);
identity.qualityMode = identityRecordAny(caseMeta, "qualityMode");
identity.strategy = identityRecordAny(caseMeta, "strategy");
identity.cohortId = identityRecordAny(caseMeta, "cohortId");
identity.capacityRatio = identityRecordAny(caseMeta, "capacityRatio", NaN);
identity.powerRatio = identityRecordAny(caseMeta, "powerRatio", NaN);
identity.pvBoundaryId = identityRecordAny(caseMeta, "pvBoundaryId");
identity.xi = identityRecordAny(caseMeta, ...
    ["xi", "transferLossFraction"], NaN);
identity.pairId = identityRecordAny(caseMeta, "pairId");
identity.scenarioId = identityRecordAny(caseMeta, "scenarioId");
identity.dataContractId = identityRecord(caseMeta, "dataContractId");
identity.dataContractSha256 = identityRecord(caseMeta, ...
    "dataContractSha256");
identity.dataContractGitCommit = identityRecord(caseMeta, ...
    "dataContractGitCommit");
identity.modelContractId = identityRecord(caseMeta, "modelContractId");
identity.modelContractSha256 = identityRecord(caseMeta, ...
    "modelContractSha256");
identity.referenceIds = identityRecord(caseMeta, "referenceIds");
identity.referenceHashes = identityRecord(caseMeta, "referenceHashes");
identity.referenceManifestSha256 = identityRecord(caseMeta, ...
    "referenceManifestSha256");
end

function record = identityRecord(caseMeta, fieldName)
record = identityRecordAny(caseMeta, string(fieldName));
end

function record = identityRecordAny(caseMeta, fieldNames, defaultValue)
if nargin < 3
    defaultValue = "unavailable";
end
fieldNames = string(fieldNames);
available = false;
value = defaultValue;
source = "unavailable";
for fieldIndex = 1:numel(fieldNames)
    fieldName = fieldNames(fieldIndex);
    if isfield(caseMeta, fieldName)
        available = true;
        value = caseMeta.(fieldName);
        source = "caseMeta." + fieldName;
        break
    end
end
record = struct("value", value, "available", logical(available), ...
    "source", source);
end

function availability = makeMaskAvailability(caseMeta)
fields = ["observationMask", "interpolationMask", "cohortMask", ...
    "h4MaskAffected"];
availability = struct;
for fieldIndex = 1:numel(fields)
    field = fields(fieldIndex);
    present = isfield(caseMeta, field);
    reason = "";
    if ~present
        reason = "not_provided_by_caller";
    end
    availability.(field) = struct("available", present, ...
        "source", "caseMeta." + field, "reason", reason);
end
availability.h4Mask = struct("available", ...
    availability.h4MaskAffected.available, ...
    "source", "derived:caseMeta.h4MaskAffected", ...
    "reason", availability.h4MaskAffected.reason);
end

function mask = observedH4Mask(caseMeta, intervalCount)
mask = logical.empty(0, 0);
if isfield(caseMeta, "h4MaskAffected") && ...
        isscalar(caseMeta.h4MaskAffected) && ...
        ~isnan(double(caseMeta.h4MaskAffected))
    mask = repmat(logical(caseMeta.h4MaskAffected), intervalCount, 1);
end
end

function value = optionalNumericField(container, fieldName)
value = [];
if isfield(container, fieldName)
    value = double(container.(fieldName));
end
end

function value = optionalLogicalField(container, fieldName)
value = logical.empty(0, 0);
if isfield(container, fieldName)
    value = logical(container.(fieldName));
end
end

function value = optionalStringField(container, fieldName, defaultValue)
value = string(defaultValue);
if isfield(container, fieldName)
    value = string(container.(fieldName));
end
end

function value = optionalScalarField(container, fieldName, defaultValue)
value = defaultValue;
if isfield(container, fieldName)
    value = container.(fieldName);
end
end

function value = optionalStructField(container, fieldName)
value = struct;
if isfield(container, fieldName) && isstruct(container.(fieldName))
    value = container.(fieldName);
end
end

function hash = sha256File(path)
hash = storenetio.hashFile(path);
end

function tf = hasMaterialEntries(directory)
entries = dir(directory);
names = string({entries.name});
tf = any(~ismember(names, [".", ".."]) & ~startsWith(names, ".nfs"));
end

function refuseExistingTarget(path)
if isfile(path) || isfolder(path)
    error("StoreNet:BahloulArtifactExists", ...
        "Refusing to overwrite observed artifact: %s", path);
end
end

function moveArtifact(source, destination)
[moved, message] = movefile(source, destination);
if ~moved
    error("StoreNet:BahloulArtifactWriteFailed", ...
        "Cannot promote observed artifact %s: %s", destination, message);
end
end

function writeJson(path, value)
temporaryPath = string(tempname(fileparts(path))) + ".json";
fileId = fopen(temporaryPath, "wt", "n", "UTF-8");
if fileId < 0
    error("StoreNet:BahloulArtifactWriteFailed", ...
        "Cannot open temporary JSON file: %s", temporaryPath);
end
try
    fprintf(fileId, "%s\n", jsonencode(value, PrettyPrint=true));
    fclose(fileId);
    fileId = -1;
    refuseExistingTarget(path);
    moveArtifact(temporaryPath, path);
catch exception
    if fileId >= 0
        fclose(fileId);
    end
    deleteIfPresent(temporaryPath);
    rethrow(exception)
end
end

function deleteCreatedPaths(paths)
for pathIndex = 1:numel(paths)
    deleteIfPresent(paths(pathIndex));
end
end

function deleteIfPresent(path)
if isfile(path)
    delete(path);
end
end

function removeNewEmptyDirectory(directory, directoryAlreadyExisted)
if ~directoryAlreadyExisted && isfolder(directory) && ...
        ~hasMaterialEntries(directory)
    rmdir(directory);
end
end
