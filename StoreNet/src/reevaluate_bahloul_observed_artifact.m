function [metrics, profiles, evidence] = ...
        reevaluate_bahloul_observed_artifact(caseDirectory)
%REEVALUATE_BAHLOUL_OBSERVED_ARTIFACT Recompute observed metrics offline.
%   Exactly one inputs_<sha256>.mat and one solution_<sha256>.mat are
%   required. Both hashes are verified before either payload is loaded.
%   No solver is called.

arguments
    caseDirectory (1, 1) string
end

[inputsPath, solutionPath, inputsSha256, solutionSha256] = ...
    discoverEvidenceFiles(caseDirectory);
inputFile = load(inputsPath, "inputEvidence");
solutionFile = load(solutionPath, "solutionEvidence");
if ~isfield(inputFile, "inputEvidence") || ...
        ~isfield(solutionFile, "solutionEvidence")
    error("StoreNet:InvalidObservedBahloulArtifact", ...
        "Observed evidence MAT files lack the required structs.");
end

inputEvidence = inputFile.inputEvidence;
solutionEvidence = solutionFile.solutionEvidence;
validateObservedEvidence(inputEvidence, solutionEvidence);
evaluationData = evaluationDataFromEvidence(inputEvidence);
[metrics, profiles] = evaluate_observed_sbsc(evaluationData, ...
    inputEvidence.config);

evidence = struct;
evidence.input = inputEvidence;
evidence.solutionEvidence = solutionEvidence;
evidence.persistedMetrics = solutionEvidence.metrics;
evidence.persistedProfiles = solutionEvidence.profiles;
evidence.inputsPath = inputsPath;
evidence.inputsSha256 = inputsSha256;
evidence.solutionPath = solutionPath;
evidence.solutionSha256 = solutionSha256;
evidence.solverInvoked = false;
end

function [inputsPath, solutionPath, inputsSha256, solutionSha256] = ...
        discoverEvidenceFiles(caseDirectory)
inputCandidates = dir(fullfile(caseDirectory, "inputs_*.mat"));
solutionCandidates = dir(fullfile(caseDirectory, "solution_*.mat"));
legacyPresent = isfile(fullfile(caseDirectory, "inputs.mat")) || ...
    isfile(fullfile(caseDirectory, "solution.mat"));
if numel(inputCandidates) > 1 || numel(solutionCandidates) > 1 || ...
        legacyPresent
    error("StoreNet:AmbiguousObservedBahloulArtifact", ...
        "Observed case directory has multiple or mixed evidence layouts: %s", ...
        caseDirectory);
end
if numel(inputCandidates) ~= 1 || numel(solutionCandidates) ~= 1
    error("StoreNet:IncompleteObservedBahloulArtifact", ...
        "Observed case requires exactly one content-addressed input and " + ...
        "solution-like MAT file: %s", caseDirectory);
end
inputsPath = string(fullfile(inputCandidates.folder, inputCandidates.name));
solutionPath = string(fullfile(solutionCandidates.folder, ...
    solutionCandidates.name));
inputsSha256 = filenameHash(inputsPath, "inputs");
solutionSha256 = filenameHash(solutionPath, "solution");
verifyFileHash(inputsPath, inputsSha256);
verifyFileHash(solutionPath, solutionSha256);
end

function hash = filenameHash(path, prefix)
[~, name] = fileparts(path);
match = regexp(char(name), ...
    ['^' char(prefix) '_([0-9a-f]{64})$'], 'tokens', 'once');
if isempty(match)
    error("StoreNet:InvalidObservedBahloulArtifactName", ...
        "Observed content-addressed artifact has invalid filename: %s", path);
end
hash = string(match{1});
end

function verifyFileHash(path, expectedHash)
actualHash = sha256File(path);
if actualHash ~= expectedHash
    error("StoreNet:ObservedBahloulArtifactChecksumMismatch", ...
        "Observed artifact SHA-256 mismatch for %s.", path);
end
end

function validateObservedEvidence(inputEvidence, solutionEvidence)
requiredInput = ["schemaVersion", "data", "config", "caseMeta", ...
    "timeEnd", "intervalStart", "dtHours", "houseIds", ...
    "observedLoadKW", "observedProductionKW", ...
    "observedGridImportKW", "observedFeedInKW", "observedChargeKW", ...
    "observedDischargeKW", "pricePerKWh", "dayMask", "identity"];
requiredSolution = ["schemaVersion", "profiles", "metrics", ...
    "solutionLike", "identity", "solverInvoked"];
missingInput = requiredInput(~isfield(inputEvidence, cellstr(requiredInput)));
missingSolution = requiredSolution(~isfield(solutionEvidence, ...
    cellstr(requiredSolution)));
validSchemas = isfield(inputEvidence, "schemaVersion") && ...
    string(inputEvidence.schemaVersion) == ...
    "B2022-observed-input-evidence-v2" && ...
    isfield(solutionEvidence, "schemaVersion") && ...
    string(solutionEvidence.schemaVersion) == ...
    "B2022-observed-solution-evidence-v2";
if ~isempty(missingInput) || ~isempty(missingSolution) || ~validSchemas
    error("StoreNet:InvalidObservedBahloulArtifact", ...
        "Observed artifact does not satisfy the B2022 v2 evidence schema.");
end
config = inputEvidence.config;
meta = inputEvidence.caseMeta;
boundaryValid = isfield(config, "pvBoundaryId") && ...
    string(config.pvBoundaryId) == "OBSERVED_RELEASE_FIELDS" && ...
    isfield(meta, "pvBoundaryId") && ...
    string(meta.pvBoundaryId) == "OBSERVED_RELEASE_FIELDS";
xiValid = hasNaNScalar(config, "xi") && ...
    hasNaNScalar(config, "transferLossFraction") && ...
    hasNaNScalar(meta, "xi") && ...
    hasNaNScalar(meta, "transferLossFraction");
if ~boundaryValid || ~xiValid || logical(solutionEvidence.solverInvoked)
    error("StoreNet:InvalidObservedBahloulBoundary", ...
        "Observed evidence must use OBSERVED_RELEASE_FIELDS, xi=NaN, " + ...
        "and solverInvoked=false.");
end
end

function data = evaluationDataFromEvidence(inputEvidence)
data = inputEvidence.data;
data.time = inputEvidence.timeEnd(:);
data.dtHours = double(inputEvidence.dtHours);
data.houseIds = string(inputEvidence.houseIds(:)).';
data.loadKW = double(inputEvidence.observedLoadKW);
data.pvKW = double(inputEvidence.observedProductionKW);
data.releasedPvKW = double(inputEvidence.observedProductionKW);
data.fromGridKW = double(inputEvidence.observedGridImportKW);
data.feedInKW = double(inputEvidence.observedFeedInKW);
data.chargeKW = double(inputEvidence.observedChargeKW);
data.dischargeKW = double(inputEvidence.observedDischargeKW);
end

function tf = hasNaNScalar(container, fieldName)
tf = isfield(container, fieldName) && isnumeric(container.(fieldName)) && ...
    isscalar(container.(fieldName)) && isnan(double(container.(fieldName)));
end

function hash = sha256File(path)
hash = storenetio.hashFile(path);
end

