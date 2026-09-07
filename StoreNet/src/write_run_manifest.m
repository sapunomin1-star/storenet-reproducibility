function [manifest, manifestPath] = write_run_manifest(outputDirectory, runInfo, options)
%WRITE_RUN_MANIFEST Write machine-readable provenance for one experiment.
%   MANIFEST = WRITE_RUN_MANIFEST(DIR, RUNINFO) preserves the legacy v1
%   manifest contract used by existing runners.
%
%   MANIFEST = WRITE_RUN_MANIFEST(..., FormalMode=true, ...) writes a v2
%   manifest and fails closed unless the caller supplies both data/model
%   contract identifiers and hashes, actual solver/provider provenance, a
%   clean Git preflight that includes untracked files, and a release manifest
%   containing exactly the expected number of files whose checksums all pass.
%   Formal preflight completes before this function creates DIR.

arguments
    outputDirectory (1, 1) string
    runInfo (1, 1) struct
    options.RepositoryRoot (1, 1) string = ""
    options.ReleaseManifestPath (1, 1) string = ""
    options.FileName (1, 1) string = "manifest.json"
    options.FormalMode (1, 1) logical = false
    options.DataContractId (1, 1) string = ""
    options.DataContractSha256 (1, 1) string = ""
    options.DataContractGitCommit (1, 1) string = ""
    options.ModelContractId (1, 1) string = ""
    options.ModelContractSha256 (1, 1) string = ""
    options.ReferenceManifestSha256 (1, 1) string = ""
    options.SolverProvenance (1, 1) struct = struct
    options.DataProviderProvenance (1, 1) struct = struct
    options.GitPreflight (1, 1) struct = struct
end

sourceFolder = fileparts(mfilename("fullpath"));
if strlength(options.RepositoryRoot) == 0
    options.RepositoryRoot = discoverRepositoryRoot(sourceFolder);
end
if strlength(options.ReleaseManifestPath) == 0
    options.ReleaseManifestPath = string(fullfile(sourceFolder, "..", ...
        "data", "RELEASE_MANIFEST.sha256"));
end

if options.FormalMode
    dataContract = contractProvenance(options.DataContractId, ...
        options.DataContractSha256, "data");
    dataContract.gitCommit = validatedGitCommit( ...
        options.DataContractGitCommit, "data contract");
    modelContract = contractProvenance(options.ModelContractId, ...
        options.ModelContractSha256, "model");
    referenceManifestSha256 = validatedSha256( ...
        options.ReferenceManifestSha256, "reference manifest");
    solver = explicitSolverProvenance(options.SolverProvenance);
    dataProvider = explicitDataProviderProvenance( ...
        options.DataProviderProvenance);
    code = formalGitProvenance(options.RepositoryRoot, ...
        options.GitPreflight, outputDirectory);
    release = verifiedReleaseProvenance(options.ReleaseManifestPath, ...
        options.RepositoryRoot, 46);
else
    code = gitProvenance(options.RepositoryRoot);
    solver = solverProvenance();
    release = releaseProvenance(options.ReleaseManifestPath);
end

manifest = struct;
nowUtc = datetime("now", TimeZone="UTC", ...
    Format="yyyy-MM-dd'T'HH:mm:ss.SSSXXX");
if options.FormalMode
    manifest.schemaVersion = "StoreNet-run-manifest-v2";
    manifest.formalMode = true;
else
    manifest.schemaVersion = "StoreNet-run-manifest-v1";
end
manifest.createdAtUtc = string(nowUtc);
manifest.experiment = runInfo;
manifest.code = code;
manifest.runtime = matlabProvenance();
manifest.solver = solver;
if options.FormalMode
    manifest.dataProvider = dataProvider;
    manifest.contracts = struct("data", dataContract, "model", modelContract);
    manifest.references = struct("referenceManifestSha256", ...
        referenceManifestSha256);
    manifest.artifactClosure = struct( ...
        "policy", "SCIENTIFIC_ARTIFACT_MANIFEST.sha256 closes preregistered " + ...
        "scientific artifacts before acceptance; RESULT_MANIFEST.sha256 " + ...
        "then closes that manifest, acceptance reports, and every other " + ...
        "result artifact while excluding only itself", ...
        "resultManifestHashStoredInRunManifest", false);
end
manifest.release = release;
manifest = makeJsonSafe(manifest);

if ~isfolder(outputDirectory)
    mkdir(outputDirectory);
end
manifestPath = fullfile(outputDirectory, options.FileName);
temporaryPath = string(tempname(outputDirectory)) + ".json";
fileId = fopen(temporaryPath, "wt", "n", "UTF-8");
if fileId < 0
    error("StoreNet:ManifestWriteFailed", ...
        "Unable to open temporary manifest for writing: %s", temporaryPath);
end
cleaner = onCleanup(@() closeIfOpen(fileId));
encoded = jsonencode(manifest, PrettyPrint=true);
fprintf(fileId, "%s\n", encoded);
clear cleaner
movefile(temporaryPath, manifestPath, "f");
end

function commit = validatedGitCommit(commit, label)
commit = lower(strip(string(commit)));
if isempty(regexp(char(commit), '^[0-9a-f]{40}$', 'once'))
    error("StoreNet:MissingFormalProvenance", ...
        "Formal mode requires a 40-hex %s Git commit.", label);
end
end

function hash = validatedSha256(hash, label)
hash = lower(strip(string(hash)));
if isempty(regexp(char(hash), '^[0-9a-f]{64}$', 'once'))
    error("StoreNet:MissingFormalProvenance", ...
        "Formal mode requires a 64-hex %s SHA-256.", label);
end
end

function provenance = contractProvenance(contractId, contractSha256, kind)
contractId = strip(string(contractId));
contractSha256 = lower(strip(string(contractSha256)));
if strlength(contractId) == 0 || strlength(contractSha256) == 0
    error("StoreNet:MissingFormalProvenance", ...
        "Formal mode requires explicit %s contract ID and SHA-256.", kind);
end
if isempty(regexp(char(contractSha256), '^[0-9a-f]{64}$', 'once'))
    error("StoreNet:InvalidContractSha256", ...
        "The %s contract SHA-256 must contain exactly 64 hexadecimal characters.", ...
        kind);
end
provenance = struct("contractId", contractId, ...
    "contractSha256", contractSha256);
end

function provenance = explicitSolverProvenance(provenance)
required = ["name", "interface", "version"];
validateExplicitProvenance(provenance, required, "solver");
provenance.name = strip(string(provenance.name));
provenance.interface = strip(string(provenance.interface));
provenance.version = strip(string(provenance.version));
end

function provenance = explicitDataProviderProvenance(provenance)
required = "name";
validateExplicitProvenance(provenance, required, "data provider");
provenance.name = strip(string(provenance.name));
end

function validateExplicitProvenance(provenance, required, label)
missing = required(~isfield(provenance, cellstr(required)));
if ~isempty(missing)
    error("StoreNet:MissingFormalProvenance", ...
        "Formal mode requires explicit %s provenance field(s): %s.", ...
        label, strjoin(missing, ", "));
end
for fieldIndex = 1:numel(required)
    value = string(provenance.(required(fieldIndex)));
    if ~isscalar(value) || ismissing(value) || strlength(strip(value)) == 0
        error("StoreNet:MissingFormalProvenance", ...
            "Formal %s provenance field '%s' must be a nonempty scalar.", ...
            label, required(fieldIndex));
    end
end
end

function provenance = formalGitProvenance(repositoryRoot, supplied, ...
        outputDirectory)
if isempty(fieldnames(supplied))
    if isfolder(outputDirectory)
        error("StoreNet:GitPreflightTooLate", ...
            "Automatic formal Git preflight requires an output directory " + ...
            "that does not exist yet; otherwise supply a caller-captured " + ...
            "pre-output GitPreflight.");
    end
    provenance = captureFormalGitPreflight(repositoryRoot);
else
    provenance = supplied;
    provenance.preflightSource = "caller-supplied-pre-output";
    if ~isfield(provenance, "repositoryRoot")
        provenance.repositoryRoot = repositoryRoot;
    end
end

required = ["commit", "statusAvailable", "isClean", ...
    "untrackedFilesIncluded", "capturedBeforeOutputDirectory"];
missing = required(~isfield(provenance, cellstr(required)));
if ~isempty(missing)
    error("StoreNet:GitPreflightIncomplete", ...
        "Formal Git preflight is missing field(s): %s.", strjoin(missing, ", "));
end
validateattributes(provenance.statusAvailable, {'logical', 'numeric'}, ...
    {'scalar'}, mfilename, "GitPreflight.statusAvailable");
validateattributes(provenance.isClean, {'logical', 'numeric'}, ...
    {'scalar'}, mfilename, "GitPreflight.isClean");
validateattributes(provenance.untrackedFilesIncluded, {'logical', 'numeric'}, ...
    {'scalar'}, mfilename, "GitPreflight.untrackedFilesIncluded");
validateattributes(provenance.capturedBeforeOutputDirectory, ...
    {'logical', 'numeric'}, {'scalar'}, mfilename, ...
    "GitPreflight.capturedBeforeOutputDirectory");

provenance.statusAvailable = logical(provenance.statusAvailable);
provenance.isClean = logical(provenance.isClean);
provenance.untrackedFilesIncluded = logical( ...
    provenance.untrackedFilesIncluded);
provenance.capturedBeforeOutputDirectory = logical( ...
    provenance.capturedBeforeOutputDirectory);
reportedRoot = normalizedPath(provenance.repositoryRoot);
expectedRoot = normalizedPath(repositoryRoot);
if reportedRoot ~= expectedRoot
    error("StoreNet:GitPreflightRepositoryMismatch", ...
        "Git preflight repository '%s' does not match '%s'.", ...
        reportedRoot, expectedRoot);
end
provenance.repositoryRoot = expectedRoot;
provenance.commit = strip(string(provenance.commit));
if ~provenance.statusAvailable
    error("StoreNet:GitPreflightUnavailable", ...
        "Formal mode requires an available Git status preflight.");
end
if ~provenance.untrackedFilesIncluded || ...
        ~provenance.capturedBeforeOutputDirectory
    error("StoreNet:GitPreflightIncomplete", ...
        "Formal Git preflight must include untracked files and must be " + ...
        "captured before creating the output directory.");
end
if ismissing(provenance.commit) || strlength(provenance.commit) == 0 || ...
        provenance.commit == "unavailable"
    error("StoreNet:GitPreflightIncomplete", ...
        "Formal Git preflight must record the resolved commit.");
end
if ~provenance.isClean
    error("StoreNet:DirtyRepository", ...
        "Formal mode refuses to run from a dirty Git worktree.");
end
if isfield(provenance, "statusPorcelain") && ...
        strlength(strip(strjoin(string(provenance.statusPorcelain), newline))) > 0
    error("StoreNet:DirtyRepository", ...
        "Git preflight reports a clean tree but contains porcelain status output.");
end
provenance.workingTreeDirty = false;
provenance.untrackedFilesExcluded = false;
provenance.statusScope = "tracked and untracked files";
end

function provenance = captureFormalGitPreflight(repositoryRoot)
provenance = struct;
provenance.repositoryRoot = repositoryRoot;
[rootStatus, rootText] = runCommand("git -C " + ...
    shellQuote(repositoryRoot) + " rev-parse --show-toplevel");
[commitStatus, commitText] = runCommand("git -C " + ...
    shellQuote(repositoryRoot) + " rev-parse HEAD");
[dirtyStatus, dirtyText] = runCommand("git -C " + ...
    shellQuote(repositoryRoot) + ...
    " status --porcelain --untracked-files=all");
if rootStatus == 0
    provenance.repositoryRoot = strtrim(rootText);
end
if commitStatus == 0
    provenance.commit = strtrim(commitText);
else
    provenance.commit = "unavailable";
end
provenance.statusAvailable = dirtyStatus == 0;
provenance.isClean = dirtyStatus == 0 && ...
    strlength(strtrim(dirtyText)) == 0;
provenance.untrackedFilesIncluded = true;
provenance.capturedBeforeOutputDirectory = true;
provenance.statusPorcelain = strtrim(dirtyText);
provenance.preflightSource = "write_run_manifest-pre-output";
provenance.capturedAtUtc = string(datetime("now", TimeZone="UTC", ...
    Format="yyyy-MM-dd'T'HH:mm:ss.SSSXXX"));
end

function provenance = gitProvenance(repositoryRoot)
provenance = struct;
provenance.repositoryRoot = repositoryRoot;
[rootStatus, rootText] = runCommand("git -C " + shellQuote(repositoryRoot) + ...
    " rev-parse --show-toplevel");
[commitStatus, commitText] = runCommand("git -C " + shellQuote(repositoryRoot) + ...
    " rev-parse HEAD");
[dirtyStatus, dirtyText] = runCommand("git -C " + shellQuote(repositoryRoot) + ...
    " status --porcelain --untracked-files=no");
if rootStatus == 0
    provenance.repositoryRoot = strtrim(rootText);
end
if commitStatus == 0
    provenance.commit = strtrim(commitText);
else
    provenance.commit = "unavailable";
end
provenance.trackedFilesDirty = ...
    dirtyStatus ~= 0 || strlength(strtrim(dirtyText)) > 0;
provenance.statusAvailable = dirtyStatus == 0;
provenance.untrackedFilesExcluded = true;
provenance.statusScope = ...
    "tracked files only; generated and other untracked files are excluded";
end

function provenance = matlabProvenance()
provenance = struct;
provenance.version = string(version);
provenance.release = string(version("-release"));
provenance.computer = string(computer);
end

function provenance = solverProvenance()
provenance = struct;
provenance.name = "intlinprog";
provenance.interface = "MATLAB problem-based optimization";
optimizationToolbox = ver("optim");
if isempty(optimizationToolbox)
    provenance.toolboxVersion = "unavailable";
else
    provenance.toolboxVersion = string(optimizationToolbox(1).Version);
end
end

function provenance = verifiedReleaseProvenance(releaseManifestPath, ...
        repositoryRoot, expectedFileCount)
provenance = releaseProvenance(releaseManifestPath);
if ~provenance.manifestExists
    error("StoreNet:ReleaseManifestMissing", ...
        "Formal mode requires the release manifest: %s", releaseManifestPath);
end
if provenance.manifestSha256 == "unavailable"
    error("StoreNet:ReleaseManifestHashFailed", ...
        "Unable to hash release manifest: %s", releaseManifestPath);
end

[entries, paths] = readReleaseManifestEntries(releaseManifestPath);
manifestFileCount = numel(entries);
if manifestFileCount ~= expectedFileCount
    error("StoreNet:ReleaseManifestCountMismatch", ...
        "Formal release manifest contains %d files; expected exactly %d.", ...
        manifestFileCount, expectedFileCount);
end

command = "storenetio.verifyManifest";
[status, output] = storenetio.verifyManifest(repositoryRoot, releaseManifestPath);
outputLines = splitlines(string(output));
outputLines = strip(outputLines(strlength(strip(outputLines)) > 0));
records = releaseVerificationRecords(paths, outputLines);
recordStatuses = string({records.status});
passedCount = nnz(recordStatuses == "passed");
checkedCount = nnz(string({records.rawLine}) ~= "");

verification = struct;
verification.command = command;
verification.commandExitStatus = double(status);
verification.expectedFileCount = double(expectedFileCount);
verification.manifestFileCount = double(manifestFileCount);
verification.checkedFileCount = double(checkedCount);
verification.passedFileCount = double(passedCount);
verification.failedFileCount = double(manifestFileCount - passedCount);
verification.allPassed = status == 0 && ...
    passedCount == expectedFileCount && checkedCount == expectedFileCount;
verification.perFile = records;
verification.rawOutput = strtrim(string(output));
provenance.verification = verification;

if ~verification.allPassed
    error("StoreNet:ReleaseChecksumVerificationFailed", ...
        "Release checksum verification failed (exit %d, %d/%d passed).", ...
        status, passedCount, expectedFileCount);
end
end

function [entries, paths] = readReleaseManifestEntries(path)
lines = strip(readlines(path));
active = strlength(lines) > 0 & ~startsWith(lines, "#");
entries = lines(active);
paths = strings(numel(entries), 1);
for entryIndex = 1:numel(entries)
    tokens = regexp(char(entries(entryIndex)), ...
        '^([0-9A-Fa-f]{64})\s+\*?(.*)$', 'tokens', 'once');
    if isempty(tokens) || strlength(strip(string(tokens{2}))) == 0
        error("StoreNet:InvalidReleaseManifest", ...
            "Invalid SHA-256 manifest entry: %s", entries(entryIndex));
    end
    paths(entryIndex) = string(tokens{2});
end
end

function records = releaseVerificationRecords(paths, outputLines)
records = repmat(struct("path", "", "status", "failed", "rawLine", ""), ...
    numel(paths), 1);
for pathIndex = 1:numel(paths)
    expectedSuccess = paths(pathIndex) + ": OK";
    matched = find(outputLines == expectedSuccess, 1, "first");
    records(pathIndex).path = paths(pathIndex);
    if ~isempty(matched)
        records(pathIndex).status = "passed";
        records(pathIndex).rawLine = outputLines(matched);
    else
        suffixMatch = endsWith(outputLines, paths(pathIndex) + ": FAILED") | ...
            contains(outputLines, paths(pathIndex) + ": ");
        failureIndex = find(suffixMatch, 1, "first");
        if ~isempty(failureIndex)
            records(pathIndex).rawLine = outputLines(failureIndex);
        end
    end
end
end

function provenance = releaseProvenance(releaseManifestPath)
provenance = struct;
provenance.manifestPath = releaseManifestPath;
provenance.manifestExists = isfile(releaseManifestPath);
provenance.manifestSha256 = "unavailable";
if provenance.manifestExists
    provenance.manifestSha256 = sha256File(releaseManifestPath);
end
end

function value = sha256File(path)
value = "unavailable";
if isfile(path)
    value = storenetio.hashFile(path);
end
end

function root = discoverRepositoryRoot(startFolder)
[status, output] = runCommand("git -C " + shellQuote(startFolder) + ...
    " rev-parse --show-toplevel");
if status == 0
    root = strtrim(output);
else
    root = string(fullfile(startFolder, ".."));
end
end

function resolved = normalizedPath(path)
resolved = strip(string(path));
end

function [status, output] = runCommand(command)
[status, rawOutput] = system(command);
output = string(rawOutput);
end

function quoted = shellQuote(value)
quoted = storenetio.shellQuote(value);
end

function value = makeJsonSafe(value)
if istable(value)
    value = table2struct(value);
elseif isdatetime(value) || isduration(value) || isa(value, "calendarDuration")
    value = string(value);
elseif isa(value, "function_handle")
    value = string(func2str(value));
elseif iscategorical(value)
    value = string(value);
end

if isstruct(value)
    fields = string(fieldnames(value));
    for elementIndex = 1:numel(value)
        for fieldIndex = 1:numel(fields)
            field = fields(fieldIndex);
            value(elementIndex).(field) = makeJsonSafe(value(elementIndex).(field));
        end
    end
elseif iscell(value)
    for cellIndex = 1:numel(value)
        value{cellIndex} = makeJsonSafe(value{cellIndex});
    end
end
end

function closeIfOpen(fileId)
if fileId >= 0
    fclose(fileId);
end
end
