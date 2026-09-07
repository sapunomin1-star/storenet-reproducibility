function [metrics, evidence] = reevaluate_bahloul_artifact(caseDirectory)
%REEVALUATE_BAHLOUL_ARTIFACT Recompute metrics without invoking a solver.
%   Content-addressed MAT files are verified against their filename hashes
%   before loading. A fixed-name v1/v2 pair is accepted only as an explicit,
%   unambiguous legacy layout.

arguments
    caseDirectory (1, 1) string
end

[inputsPath, solutionPath, legacyLayout, inputsSha256, ...
    solutionSha256] = discoverEvidenceFiles(caseDirectory);
inputFile = load(inputsPath, "inputEvidence");
solutionFile = load(solutionPath, "solutionEvidence");
if ~isfield(inputFile, "inputEvidence") || ...
        ~isfield(solutionFile, "solutionEvidence")
    error("StoreNet:InvalidBahloulArtifact", ...
        "Evidence MAT files do not contain the required structs.");
end

inputEvidence = inputFile.inputEvidence;
solutionEvidence = solutionFile.solutionEvidence;
validateEvidenceSchema(inputEvidence, solutionEvidence, legacyLayout);
evaluationData = evaluationDataFromEvidence(inputEvidence, legacyLayout);
metrics = evaluate_storenet(evaluationData, inputEvidence.config, ...
    solutionEvidence.solution);

evidence = struct;
evidence.input = inputEvidence;
evidence.solution = solutionEvidence.solution;
evidence.solutionEvidence = solutionEvidence;
evidence.persistedMetrics = solutionEvidence.metrics;
evidence.inputsPath = inputsPath;
evidence.inputsSha256 = inputsSha256;
evidence.solutionPath = solutionPath;
evidence.solutionSha256 = solutionSha256;
evidence.legacyLayout = legacyLayout;
end

function [inputsPath, solutionPath, legacyLayout, inputsSha256, ...
        solutionSha256] = discoverEvidenceFiles(caseDirectory)
inputCandidates = dir(fullfile(caseDirectory, "inputs_*.mat"));
solutionCandidates = dir(fullfile(caseDirectory, "solution_*.mat"));
legacyInputsPath = string(fullfile(caseDirectory, "inputs.mat"));
legacySolutionPath = string(fullfile(caseDirectory, "solution.mat"));
hasLegacyInputs = isfile(legacyInputsPath);
hasLegacySolution = isfile(legacySolutionPath);
hasContentAddressed = ~isempty(inputCandidates) || ~isempty(solutionCandidates);
hasLegacy = hasLegacyInputs || hasLegacySolution;

if hasContentAddressed
    rejectAmbiguousLayout(inputCandidates, solutionCandidates, hasLegacy, ...
        caseDirectory);
    if numel(inputCandidates) ~= 1 || numel(solutionCandidates) ~= 1
        error("StoreNet:IncompleteBahloulArtifact", ...
            "Case directory requires one inputs_<sha256>.mat and one " + ...
            "solution_<sha256>.mat: %s", caseDirectory);
    end
    inputsPath = candidatePath(inputCandidates);
    solutionPath = candidatePath(solutionCandidates);
    inputsSha256 = filenameHash(inputsPath, "inputs");
    solutionSha256 = filenameHash(solutionPath, "solution");
    verifyFileHash(inputsPath, inputsSha256);
    verifyFileHash(solutionPath, solutionSha256);
    legacyLayout = false;
    return
end

if ~hasLegacyInputs || ~hasLegacySolution
    error("StoreNet:IncompleteBahloulArtifact", ...
        "Case directory contains neither a complete content-addressed " + ...
        "pair nor an unambiguous inputs.mat/solution.mat legacy pair: %s", ...
        caseDirectory);
end
inputsPath = legacyInputsPath;
solutionPath = legacySolutionPath;
inputsSha256 = sha256File(inputsPath);
solutionSha256 = sha256File(solutionPath);
legacyLayout = true;
end

function rejectAmbiguousLayout(inputCandidates, solutionCandidates, ...
        hasLegacy, caseDirectory)
if numel(inputCandidates) > 1 || numel(solutionCandidates) > 1 || hasLegacy
    error("StoreNet:AmbiguousBahloulArtifact", ...
        "Case directory has multiple or mixed evidence layouts: %s", ...
        caseDirectory);
end
end

function path = candidatePath(candidate)
path = string(fullfile(candidate.folder, candidate.name));
end

function expectedHash = filenameHash(path, prefix)
[~, name] = fileparts(path);
match = regexp(char(name), ...
    ['^' char(prefix) '_([0-9a-f]{64})$'], 'tokens', 'once');
if isempty(match)
    error("StoreNet:InvalidBahloulArtifactName", ...
        "Content-addressed artifact has an invalid filename: %s", path);
end
expectedHash = string(match{1});
end

function verifyFileHash(path, expectedHash)
actualHash = sha256File(path);
if actualHash ~= expectedHash
    error("StoreNet:BahloulArtifactChecksumMismatch", ...
        "Artifact SHA-256 mismatch for %s (expected %s, actual %s).", ...
        path, expectedHash, actualHash);
end
end

function validateEvidenceSchema(inputEvidence, solutionEvidence, legacyLayout)
requiredInputFields = ["data", "config", "caseMeta"];
requiredSolutionFields = ["solution", "metrics"];
missingInput = requiredInputFields(~isfield(inputEvidence, ...
    cellstr(requiredInputFields)));
missingSolution = requiredSolutionFields(~isfield(solutionEvidence, ...
    cellstr(requiredSolutionFields)));
if ~isempty(missingInput) || ~isempty(missingSolution)
    error("StoreNet:InvalidBahloulArtifact", ...
        "Evidence structs are missing required fields.");
end
if ~legacyLayout
    requiredV2Fields = ["schemaVersion", "timeEnd", "intervalStart", ...
        "dtHours", "houseIds", "loadKW", "releasedPvKW", "PVGenDC", ...
        "pvAvailableAC", "pricePerKWh", "dayMask", "qualityMode", ...
        "observationMask", "interpolationMask", "cohortMask", ...
        "h4Mask", "h4MaskAffected", "maskAvailability", "identity"];
    missingV2 = requiredV2Fields(~isfield(inputEvidence, ...
        cellstr(requiredV2Fields)));
    validSchemas = isfield(inputEvidence, "schemaVersion") && ...
        string(inputEvidence.schemaVersion) == "B2022-input-evidence-v2" && ...
        isfield(solutionEvidence, "schemaVersion") && ...
        string(solutionEvidence.schemaVersion) == ...
        "B2022-solution-evidence-v2";
    if ~isempty(missingV2) || ~validSchemas
        error("StoreNet:InvalidBahloulArtifact", ...
            "Content-addressed evidence must satisfy the B2022 v2 schema.");
    end
end
end

function data = evaluationDataFromEvidence(inputEvidence, legacyLayout)
data = inputEvidence.data;
if legacyLayout && ~isfield(inputEvidence, "PVGenDC")
    return
end
data.time = inputEvidence.timeEnd(:);
data.dtHours = double(inputEvidence.dtHours);
data.houseIds = string(inputEvidence.houseIds(:)).';
data.loadKW = double(inputEvidence.loadKW);
data.pvKW = double(inputEvidence.PVGenDC);
data.releasedPvKW = double(inputEvidence.releasedPvKW);
end

function hash = sha256File(path)
hash = storenetio.hashFile(path);
end

