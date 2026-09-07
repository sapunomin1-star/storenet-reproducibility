function report = run_bahloul_preflight_v1(options)
%RUN_BAHLOUL_PREFLIGHT_V1 Evaluate B2022-IR-v1 pre-solve gates P1--P9.
%   This function writes only a staging review_preflight.json. It never
%   creates the requested formal result directory and never calls the model
%   solver or loads a scientific day from the release.

arguments
    options.RepositoryRoot (1, 1) string = ""
    options.ReportPath (1, 1) string = ""
    options.FormalOutputPath (1, 1) string = ""
    options.DataContractPath (1, 1) string = ""
    options.ModelContractPath (1, 1) string = ""
    options.ReferenceManifestPath (1, 1) string = ""
    options.ReleaseManifestPath (1, 1) string = ""
    options.Figure6EvidenceDirectory (1, 1) string = ""
    options.ExpectedReleaseFileCount (1, 1) double ...
        {mustBeInteger, mustBePositive} = 46
    options.ExpectedDataContractSha256 (1, 1) string = ...
        "9aaa09b56dfeaef27dba26289be445dff40492bf7a2340da5fe36d1a016ea3ca"
    options.AnalyzerFiles string = strings(0, 1)
    options.TestFiles string = strings(0, 1)
    options.RunAnalyzer (1, 1) logical = true
    options.RunTests (1, 1) logical = true
    options.RequireCleanGit (1, 1) logical = true
    options.ThrowOnFailure (1, 1) logical = true
    options.Solver (1, 1) function_handle = @solve_storenet
    options.DataProvider (1, 1) function_handle = @load_storenet_day
end

sourceFolder = string(fileparts(mfilename("fullpath")));
if strlength(options.RepositoryRoot) == 0
    options.RepositoryRoot = discoverRepositoryRoot(sourceFolder);
end
root = canonicalPath(options.RepositoryRoot);
if strlength(options.ReportPath) == 0
    options.ReportPath = fullfile(root, "StoreNet", "tmp", ...
        "b2022_preflight", "review_preflight.json");
end
if strlength(options.FormalOutputPath) == 0
    options.FormalOutputPath = fullfile(root, "StoreNet", "results", ...
        "b2022_ir_v1_formal");
end
if strlength(options.DataContractPath) == 0
    options.DataContractPath = fullfile(root, "StoreNet", "docs", ...
        "REPRODUCTION_CONTRACT.md");
end
if strlength(options.ModelContractPath) == 0
    options.ModelContractPath = fullfile(root, "StoreNet", "docs", ...
        "B2022_REPRODUCTION_CONTRACT.md");
end
if strlength(options.ReferenceManifestPath) == 0
    options.ReferenceManifestPath = fullfile(root, "StoreNet", ...
        "reference", "B2022_REFERENCE_MANIFEST.csv");
end
if strlength(options.ReleaseManifestPath) == 0
    options.ReleaseManifestPath = fullfile(root, "StoreNet", "data", ...
        "RELEASE_MANIFEST.sha256");
end
if strlength(options.Figure6EvidenceDirectory) == 0
    options.Figure6EvidenceDirectory = fullfile(root, "StoreNet", ...
        "results", "data_paper_figures_5_10_v2");
end
if isempty(options.AnalyzerFiles)
    options.AnalyzerFiles = defaultAnalyzerFiles(root);
end
if isempty(options.TestFiles)
    options.TestFiles = defaultTestFiles(root);
end

capturedAt = datetime("now", TimeZone="UTC", ...
    Format="yyyy-MM-dd'T'HH:mm:ss.SSSXXX");
formalOutputAbsent = ~isfolder(options.FormalOutputPath) && ...
    ~isfile(options.FormalOutputPath);
git = captureGit(root);
contracts = inspectContracts(options.DataContractPath, ...
    options.ModelContractPath, options.ExpectedDataContractSha256);
references = inspectReferenceManifest(root, ...
    options.ReferenceManifestPath);
release = inspectRelease(root, options.ReleaseManifestPath, ...
    options.ExpectedReleaseFileCount);
figure6 = inspectFigure6Evidence(options.Figure6EvidenceDirectory);
runtime = inspectRuntime(options.Solver, options.DataProvider);
implementation = inspectImplementation(root);
analysis = inspectAnalyzer(options.AnalyzerFiles, options.RunAnalyzer);
tests = inspectTests(options.TestFiles, options.RunTests);

gates = repmat(emptyGate(), 9, 1);
gates(1) = makeGate("P1_DOCUMENTARY_MAPPING", ...
    references.allPassed && implementation.mappingPresent, ...
    "reference manifest and formula-code audit", ...
    failureUnless(references.allPassed && implementation.mappingPresent, ...
    "Reference manifest or formula-code audit is incomplete."));
gates(2) = makeGate("P2_NORMATIVE_AUTHORITY", contracts.allPassed, ...
    "runtime contract hashes", failureUnless(contracts.allPassed, ...
    contracts.failureReason));
gates(3) = makeGate("P3_BOUNDARY_SCHEMA", ...
    implementation.schemaFilesPresent, ...
    "canonical scenario/case/evaluator implementations", ...
    failureUnless(implementation.schemaFilesPresent, ...
    "One or more boundary-schema implementation files are missing."));
gates(4) = makeGate("P4_DUAL_BASELINE_TESTS", ...
    tests.ran && tests.allPassed && tests.hasBaselineTest, ...
    "TestBahloulBaselines", failureUnless(tests.ran && ...
    tests.allPassed && tests.hasBaselineTest, ...
    "Dual-baseline tests did not run cleanly."));
gates(5) = makeGate("P5_COHORT_SCENARIO_RUNNER", ...
    implementation.scenarioRunnersPresent && tests.ran && ...
    tests.allPassed && tests.hasOrchestrationTests, ...
    "typical/monthly/sensitivity fixture inventories", ...
    failureUnless(implementation.scenarioRunnersPresent && tests.ran && ...
    tests.allPassed && tests.hasOrchestrationTests, ...
    "Scenario runners or their fixture inventories are incomplete."));
p6Passed = release.allPassed && figure6.allPassed && references.allPassed && ...
    contracts.allPassed && git.statusAvailable && ...
    (~options.RequireCleanGit || git.isClean) && analysis.ran && ...
    analysis.issueCount == 0 && runtime.allPassed;
gates(6) = makeGate("P6_PROVENANCE_PREFLIGHT", p6Passed, ...
    "embedded release/sidecar/git/hash/runtime/analyzer evidence", ...
    failureUnless(p6Passed, ...
    "At least one provenance preflight component failed."));
gates(7) = makeGate("P7_DURABLE_SCHEMA", ...
    implementation.durableSchemaPresent && tests.ran && ...
    tests.allPassed && tests.hasArtifactTest, ...
    "content-addressed artifact and offline-evaluator tests", ...
    failureUnless(implementation.durableSchemaPresent && tests.ran && ...
    tests.allPassed && tests.hasArtifactTest, ...
    "Durable artifact schema was not accepted."));
gates(8) = makeGate("P8_FIXTURE_ACCEPTANCE", ...
    tests.ran && tests.allPassed, "all preregistered fixture tests", ...
    failureUnless(tests.ran && tests.allPassed, ...
    "One or more fixture tests failed or were not run."));
gates(9) = makeGate("P9_HISTORICAL_PROTECTION", formalOutputAbsent, ...
    "formal output path absent before solve", ...
    failureUnless(formalOutputAbsent, ...
    "Formal output path already exists; overwrite is forbidden."));

report = struct;
report.schemaVersion = "B2022-review-preflight-v1";
report.dataContractId = "SR2020-IR-v2";
report.modelContractId = "B2022-IR-v1";
report.capturedAtUtc = string(capturedAt);
report.repositoryRoot = root;
report.formalOutputPath = options.FormalOutputPath;
report.formalOutputWasAbsent = formalOutputAbsent;
report.gitPreflight = git;
report.contracts = contracts;
report.references = references;
report.release = release;
report.figure6Evidence = figure6;
report.runtime = runtime;
report.implementation = implementation;
report.analyzer = analysis;
report.tests = tests;
report.gates = gates;
report.allPassed = all(string({gates.status}) == "PASS");
writeJson(options.ReportPath, report);
report.reportPath = options.ReportPath;
report.reportSha256 = hashFile(options.ReportPath);

if options.ThrowOnFailure && ~report.allPassed
    failedNames = string({gates(string({gates.status}) ~= "PASS").gateId});
    error("StoreNet:BahloulPreflightFailed", ...
        "B2022 pre-solve admission failed: %s. Evidence: %s", ...
        strjoin(failedNames, ", "), options.ReportPath);
end
end

function files = defaultAnalyzerFiles(root)
names = ["bahloul_scenarios.m", "evaluate_observed_sbsc.m", ...
    "evaluate_bahloul_acceptance_v1.m", "evaluate_storenet.m", ...
    "prepare_bahloul_case.m", "prepare_observed_sbsc_case.m", ...
    "reevaluate_bahloul_artifact.m", ...
    "reevaluate_bahloul_observed_artifact.m", ...
    "run_bahloul_typical_v1.m", ...
    "run_bahloul_monthly_v1.m", "run_bahloul_sensitivity_v1.m", ...
    "run_bahloul_preflight_v1.m", "run_bahloul_formal_v1.m", ...
    "solve_storenet.m", ...
    "storenet_config.m", "write_bahloul_case_artifacts.m", ...
    "write_bahloul_observed_artifacts.m", ...
    "write_result_manifest_sha256.m", "write_run_manifest.m"];
files = fullfile(root, "StoreNet", "src", names).';
end

function files = defaultTestFiles(root)
folder = fullfile(root, "StoreNet", "tests");
names = ["TestBahloulAcceptanceV1.m", "TestBahloulArtifacts.m", ...
    "TestBahloulBaselines.m", ...
    "TestBahloulCasePreparation.m", "TestBahloulFormalV1.m", ...
    "TestBahloulMonthlyV1.m", ...
    "TestBahloulPreflightV1.m", ...
    "TestBahloulProvenance.m", ...
    "TestBahloulScenarios.m", "TestBahloulSensitivityV1.m", ...
    "TestBahloulTypicalV1.m", "TestObservedSbsc.m", ...
    "TestStoreNetModel.m"];
files = fullfile(folder, names).';
end

function result = inspectContracts(dataPath, modelPath, expectedDataHash)
result = struct;
result.dataContractPath = dataPath;
result.modelContractPath = modelPath;
result.dataContractId = "SR2020-IR-v2";
result.modelContractId = "B2022-IR-v1";
result.dataContractGitCommit = ...
    "f342259e06e86c2379de9ac51c6963805a41da39";
result.dataContractSha256 = hashFileOrUnavailable(dataPath);
result.modelContractSha256 = hashFileOrUnavailable(modelPath);
result.expectedDataContractSha256 = lower(expectedDataHash);
result.dataHashPassed = result.dataContractSha256 == ...
    result.expectedDataContractSha256;
result.modelHashPassed = isSha256(result.modelContractSha256);
result.idsPresent = contains(readTextOrEmpty(dataPath), ...
    result.dataContractId) && contains(readTextOrEmpty(modelPath), ...
    result.modelContractId);
result.allPassed = result.dataHashPassed && result.modelHashPassed && ...
    result.idsPresent;
result.failureReason = "";
if ~result.allPassed
    result.failureReason = "Contract ID or runtime content hash mismatch.";
end
end

function result = inspectReferenceManifest(root, manifestPath)
result = struct("manifestPath", manifestPath, ...
    "manifestSha256", hashFileOrUnavailable(manifestPath), ...
    "entryCount", 0, "passedCount", 0, "allPassed", false, ...
    "entries", struct([]));
if ~isfile(manifestPath)
    return
end
manifest = readtable(manifestPath, Delimiter=",", TextType="string", ...
    VariableNamingRule="preserve");
required = ["ArtifactId", "RepositoryRelativePath", "Sha256", "Role", ...
    "PaperLocator", "Method"];
if ~all(ismember(required, string(manifest.Properties.VariableNames)))
    return
end
entries = repmat(struct("artifactId", "", "path", "", ...
    "expectedSha256", "", "observedSha256", "", "passed", false), ...
    height(manifest), 1);
for rowIndex = 1:height(manifest)
    path = fullfile(root, manifest.RepositoryRelativePath(rowIndex));
    observed = hashFileOrUnavailable(path);
    expected = lower(manifest.Sha256(rowIndex));
    entries(rowIndex) = struct("artifactId", ...
        manifest.ArtifactId(rowIndex), "path", string(path), ...
        "expectedSha256", expected, "observedSha256", observed, ...
        "passed", observed == expected);
end
result.entryCount = height(manifest);
result.passedCount = nnz([entries.passed]);
result.entries = entries;
result.allPassed = result.entryCount >= 5 && ...
    result.passedCount == result.entryCount && ...
    any(manifest.ArtifactId == "FIG5_PROFILE") && ...
    any(manifest.ArtifactId == "FIG5_SAVINGS") && ...
    any(manifest.ArtifactId == "TABLE_I_TARGETS") && ...
    any(manifest.ArtifactId == "SOURCE_PDF") && ...
    any(manifest.ArtifactId == "FORMULA_CODE_AUDIT") && ...
    any(manifest.ArtifactId == "TYPICAL_DAY_DECISION") && ...
    any(manifest.ArtifactId == "TYPICAL_DAY_RANKING") && ...
    any(manifest.ArtifactId == "TYPICAL_DAY_PROVENANCE");
end

function result = inspectRelease(root, manifestPath, expectedCount)
result = struct("manifestPath", manifestPath, ...
    "manifestSha256", hashFileOrUnavailable(manifestPath), ...
    "expectedFileCount", expectedCount, "manifestFileCount", 0, ...
    "commandExitStatus", NaN, "passedFileCount", 0, ...
    "allPassed", false, "rawOutput", "");
if ~isfile(manifestPath)
    return
end
lines = strip(readlines(manifestPath));
entries = lines(strlength(lines) > 0 & ~startsWith(lines, "#"));
result.manifestFileCount = numel(entries);
command = "storenetio.verifyManifest";
[status, output] = storenetio.verifyManifest(root, manifestPath);
result.command = command;
result.commandExitStatus = double(status);
result.rawOutput = string(strtrim(output));
result.passedFileCount = nnz(endsWith(strip(splitlines(string(output))), ...
    ": OK"));
result.allPassed = status == 0 && ...
    result.manifestFileCount == expectedCount && ...
    result.passedFileCount == expectedCount;
end

function result = inspectFigure6Evidence(directory)
required = ["figure6_all_house_metrics.csv", ...
    "figure6_h4_daily_diagnostics.csv", ...
    "figure6_h4_monthly_summary.csv", ...
    "figure6_h4_alignment_summary.csv", ...
    "figure6_h4_anomaly_segments.csv", ...
    "figure6_h4_date_transpose_diagnostics.csv", ...
    "figure6_h4_cross_house_controls.csv", ...
    "figure6_h4_wh_balance.json"];
present = isfile(fullfile(directory, required));
manifestPath = fullfile(directory, "RESULT_MANIFEST.sha256");
listed = false(size(required));
if isfile(manifestPath)
    manifestText = readTextOrEmpty(manifestPath);
    for fileIndex = 1:numel(required)
        listed(fileIndex) = contains(manifestText, required(fileIndex));
    end
    command = "storenetio.verifyManifest";
    [status, output] = storenetio.verifyManifest(directory, manifestPath);
else
    command = "";
    status = 1;
    output = "RESULT_MANIFEST.sha256 is missing";
end
result = struct;
result.directory = directory;
result.requiredFiles = required;
result.present = present;
result.listedInResultManifest = listed;
result.resultManifestPath = manifestPath;
result.resultManifestSha256 = hashFileOrUnavailable(manifestPath);
result.verificationCommand = command;
result.commandExitStatus = double(status);
result.rawOutput = string(strtrim(output));
result.allPassed = all(present) && all(listed) && status == 0;
end

function result = inspectRuntime(solver, provider)
optimizationToolbox = ver("optim");
result = struct;
result.matlabVersion = string(version);
result.matlabRelease = string(version("-release"));
result.computer = string(computer);
result.solverFunction = string(func2str(solver));
result.dataProviderFunction = string(func2str(provider));
result.optimizationToolboxAvailable = ~isempty(optimizationToolbox);
if isempty(optimizationToolbox)
    result.optimizationToolboxVersion = "unavailable";
else
    result.optimizationToolboxVersion = ...
        string(optimizationToolbox(1).Version);
end
result.mipRelativeGap = 1e-6;
result.constraintTolerance = 1e-8;
result.lexicographicTolerance = 1e-7;
result.allPassed = strlength(result.solverFunction) > 0 && ...
    strlength(result.dataProviderFunction) > 0 && ...
    result.optimizationToolboxAvailable;
end

function result = inspectImplementation(root)
src = fullfile(root, "StoreNet", "src");
docs = fullfile(root, "StoreNet", "docs");
schemaNames = ["bahloul_scenarios.m", "evaluate_storenet.m", ...
    "evaluate_observed_sbsc.m", "prepare_bahloul_case.m", ...
    "prepare_observed_sbsc_case.m"];
runnerNames = ["run_bahloul_typical_v1.m", ...
    "run_bahloul_monthly_v1.m", "run_bahloul_sensitivity_v1.m"];
durableNames = ["write_bahloul_case_artifacts.m", ...
    "reevaluate_bahloul_artifact.m", ...
    "write_bahloul_observed_artifacts.m", ...
    "reevaluate_bahloul_observed_artifact.m"];
result = struct;
result.mappingPresent = isfile(fullfile(docs, ...
    "BAHLOUL_VPP_REPRODUCIBILITY_AUDIT.md"));
result.schemaFiles = fullfile(src, schemaNames);
result.schemaFilesPresent = all(isfile(result.schemaFiles));
result.scenarioRunners = fullfile(src, runnerNames);
result.scenarioRunnersPresent = all(isfile(result.scenarioRunners));
result.durableSchemaFiles = fullfile(src, durableNames);
result.durableSchemaPresent = all(isfile(result.durableSchemaFiles));
end

function result = inspectAnalyzer(files, enabled)
files = string(files(:));
result = struct("ran", false, "fileCount", numel(files), ...
    "issueCount", NaN, "missingFiles", files(~isfile(files)), ...
    "files", struct([]));
if ~enabled || ~isempty(result.missingFiles)
    return
end
records = repmat(struct("path", "", "issueCount", 0, ...
    "issues", struct([])), numel(files), 1);
totalIssues = 0;
for fileIndex = 1:numel(files)
    issues = checkcode(files(fileIndex), "-struct");
    records(fileIndex).path = files(fileIndex);
    records(fileIndex).issueCount = numel(issues);
    records(fileIndex).issues = issues;
    totalIssues = totalIssues + numel(issues);
end
result.ran = true;
result.issueCount = totalIssues;
result.files = records;
end

function result = inspectTests(files, enabled)
files = string(files(:));
result = struct("ran", false, "fileCount", numel(files), ...
    "missingFiles", files(~isfile(files)), "resultCount", 0, ...
    "passedCount", 0, "failedCount", 0, "incompleteCount", 0, ...
    "allPassed", false, "hasBaselineTest", false, ...
    "hasArtifactTest", false, "hasOrchestrationTests", false, ...
    "results", struct([]));
if ~enabled || ~isempty(result.missingFiles)
    return
end
testResults = runtests(cellstr(files));
records = repmat(struct("name", "", "passed", false, "failed", false, ...
    "incomplete", false, "durationSeconds", NaN), numel(testResults), 1);
for resultIndex = 1:numel(testResults)
    records(resultIndex).name = string(testResults(resultIndex).Name);
    records(resultIndex).passed = testResults(resultIndex).Passed;
    records(resultIndex).failed = testResults(resultIndex).Failed;
    records(resultIndex).incomplete = testResults(resultIndex).Incomplete;
    records(resultIndex).durationSeconds = ...
        seconds(testResults(resultIndex).Duration);
end
fileNames = string(files);
result.ran = true;
result.resultCount = numel(testResults);
result.passedCount = nnz([records.passed]);
result.failedCount = nnz([records.failed]);
result.incompleteCount = nnz([records.incomplete]);
result.allPassed = result.resultCount > 0 && ...
    result.passedCount == result.resultCount;
result.hasBaselineTest = any(endsWith(fileNames, ...
    "TestBahloulBaselines.m"));
result.hasArtifactTest = any(endsWith(fileNames, ...
    "TestBahloulArtifacts.m"));
requiredOrchestration = ["TestBahloulTypicalV1.m", ...
    "TestBahloulMonthlyV1.m", "TestBahloulSensitivityV1.m"];
result.hasOrchestrationTests = all(arrayfun(@(name) ...
    any(endsWith(fileNames, name)), requiredOrchestration));
result.results = records;
end

function git = captureGit(root)
[rootStatus, rootOutput] = system("git -C " + shellQuote(root) + ...
    " rev-parse --show-toplevel");
[commitStatus, commitOutput] = system("git -C " + shellQuote(root) + ...
    " rev-parse HEAD");
[statusCode, statusOutput] = system("git -C " + shellQuote(root) + ...
    " status --porcelain --untracked-files=all");
git = struct;
git.repositoryRoot = string(strtrim(rootOutput));
git.commit = string(strtrim(commitOutput));
git.statusAvailable = rootStatus == 0 && commitStatus == 0 && ...
    statusCode == 0;
git.statusPorcelain = string(strtrim(statusOutput));
git.isClean = git.statusAvailable && strlength(git.statusPorcelain) == 0;
git.untrackedFilesIncluded = true;
git.capturedBeforeOutputDirectory = true;
git.capturedAtUtc = string(datetime("now", TimeZone="UTC", ...
    Format="yyyy-MM-dd'T'HH:mm:ss.SSSXXX"));
end

function gate = makeGate(id, passed, evidence, reason)
gate = emptyGate();
gate.gateId = id;
if passed
    gate.status = "PASS";
else
    gate.status = "FAIL";
end
gate.machineEvidence = evidence;
gate.failureReason = reason;
end

function gate = emptyGate()
gate = struct("gateId", "", "status", "", ...
    "machineEvidence", "", "failureReason", "");
end

function reason = failureUnless(passed, failureReason)
if passed
    reason = "";
else
    reason = string(failureReason);
end
end

function writeJson(path, value)
folder = fileparts(path);
if ~isfolder(folder)
    mkdir(folder);
end
if isfile(path)
    error("StoreNet:PreflightReportExists", ...
        "Refusing to overwrite preflight report: %s", path);
end
temporaryPath = string(tempname(folder)) + ".json";
fileId = fopen(temporaryPath, "wt", "n", "UTF-8");
if fileId < 0
    error("StoreNet:PreflightWriteFailed", ...
        "Cannot create preflight JSON: %s", temporaryPath);
end
try
    fprintf(fileId, "%s\n", jsonencode(makeJsonSafe(value), ...
        PrettyPrint=true));
    fclose(fileId);
    fileId = -1;
    movefile(temporaryPath, path, "f");
catch exception
    if fileId >= 0
        fclose(fileId);
    end
    if isfile(temporaryPath)
        delete(temporaryPath);
    end
    rethrow(exception)
end
end

function value = makeJsonSafe(value)
if isdatetime(value) || isduration(value) || isa(value, "calendarDuration")
    value = string(value);
elseif istable(value)
    value = table2struct(value);
elseif isa(value, "function_handle")
    value = string(func2str(value));
end
if isstruct(value)
    fields = string(fieldnames(value));
    for valueIndex = 1:numel(value)
        for fieldIndex = 1:numel(fields)
            field = fields(fieldIndex);
            value(valueIndex).(field) = ...
                makeJsonSafe(value(valueIndex).(field));
        end
    end
elseif iscell(value)
    for valueIndex = 1:numel(value)
        value{valueIndex} = makeJsonSafe(value{valueIndex});
    end
end
end

function hash = hashFileOrUnavailable(path)
if isfile(path)
    hash = hashFile(path);
else
    hash = "unavailable";
end
end

function hash = hashFile(path)
hash = storenetio.hashFile(path);
end

function tf = isSha256(value)
tf = ~isempty(regexp(char(value), '^[0-9a-f]{64}$', 'once'));
end

function text = readTextOrEmpty(path)
if isfile(path)
    text = string(fileread(path));
else
    text = "";
end
end

function path = canonicalPath(path)
if ~isfolder(path)
    error("StoreNet:InvalidRepositoryRoot", "Cannot resolve repository root: %s", path);
end
previousFolder = pwd;
cleanup = onCleanup(@() cd(previousFolder));
cd(path);
path = string(pwd);
end

function root = discoverRepositoryRoot(startPath)
[status, output] = system("git -C " + shellQuote(startPath) + ...
    " rev-parse --show-toplevel");
if status ~= 0
    error("StoreNet:RepositoryNotFound", ...
        "Unable to discover the Git repository from %s.", startPath);
end
root = string(strtrim(output));
end

function quoted = shellQuote(value)
quoted = storenetio.shellQuote(value);
end
