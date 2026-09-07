classdef TestBahloulFormalV1 < matlab.unittest.TestCase
    %TESTBAHLOULFORMALV1 Synthetic tests for the formal orchestrator.

    properties
        Fixture
    end

    methods (TestClassSetup)
        function addSourceFolder(testCase)
            testFolder = fileparts(mfilename("fullpath"));
            sourceFolder = fullfile(fileparts(testFolder), "src");
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                sourceFolder));
        end
    end

    methods (TestMethodSetup)
        function createFixture(testCase)
            testCase.Fixture = createFormalFixture();
            testCase.addTeardown(@() removeFixture( ...
                testCase.Fixture.root));
        end
    end

    methods (Test)
        function testPreflightFailureNeverCreatesFormalRoot(testCase)
            invoke = @() invokeFormal(testCase.Fixture, ...
                @failingPreflight, false);

            testCase.verifyError(invoke, ...
                "StoreNet:BahloulPreflightFailed");
            testCase.verifyFalse(isfolder(testCase.Fixture.formalRoot));
            testCase.verifyTrue(isfile(fullfile( ...
                testCase.Fixture.stagingRoot, ...
                "review_preflight.json")));
        end

        function testMissingMonthlyReuseSourceFailsBeforePreflight(testCase)
            delete(testCase.Fixture.existingDailyMetricsPath);
            invoke = @() invokeFormal(testCase.Fixture, ...
                @passingPreflight, false);

            testCase.verifyError(invoke, ...
                "StoreNet:FormalInputBindingMissing");
            testCase.verifyFalse(isfolder(testCase.Fixture.formalRoot));
            testCase.verifyFalse(isfile(fullfile( ...
                testCase.Fixture.stagingRoot, ...
                "review_preflight.json")));
        end

        function testSuccessfulRunIsOrderedClosedAndProvenanced(testCase)
            run = invokeFormal(testCase.Fixture, @passingPreflight, false);
            order = readCallOrder(run.formalRoot);
            childDirectories = expectedChildDirectories(run.formalRoot);
            manifest = jsondecode(fileread(run.manifestPath));
            closurePaths = readClosurePaths(run.closure.manifestPath);
            scientificClosurePaths = readClosurePaths( ...
                run.scientificClosure.manifestPath);
            expectedPaths = recursiveFixtureFiles(run.formalRoot);

            testCase.verifyTrue(run.preflight.formalOutputWasAbsent);
            testCase.verifyEqual(order, ...
                ["TYPICAL"; "MONTHLY"; "SENSITIVITY"]);
            testCase.verifyTrue(all(isfolder(childDirectories)));
            testCase.verifyEqual(string(struct2cell(run.childRunIds)), ...
                ["b2022_typical_v1_20200824"; ...
                 "b2022_monthly_v1_2020"; ...
                 "b2022_sensitivity_v1_20200824"]);
            testCase.verifyEqual(run.children.typical.day, ...
                datetime(2020, 8, 24));
            testCase.verifyEqual(run.children.typical.intervalMinutes, 30);
            testCase.verifyEqual(run.children.typical.qualityMode, ...
                "release_literal");
            testCase.verifyEqual(run.children.monthly.qualityMode, ...
                "release_literal");
            testCase.verifyEqual( ...
                run.children.monthly.existingDailyMetricsPath, ...
                run.monthlyDailyMetricsEvidencePath);
            testCase.verifyEqual( ...
                run.children.monthly.existingDailyManifestPath, ...
                run.monthlyDailyManifestEvidencePath);
            testCase.verifyEqual(run.children.sensitivity.day, ...
                datetime(2020, 8, 24));
            testCase.verifyEqual(run.children.sensitivity.reuseFigure7Csv, ...
                testCase.Fixture.figure7ReuseCsv);
            testCase.verifyEqual( ...
                run.children.typical.provenance, run.caseProvenance);
            testCase.verifyEqual( ...
                run.children.monthly.provenance, run.caseProvenance);
            testCase.verifyEqual( ...
                run.children.sensitivity.provenance, run.caseProvenance);
            testCase.verifyEqual( ...
                run.caseProvenance.solverProvenance.name, ...
                "mockFormalSolver");
            testCase.verifyEqual( ...
                run.caseProvenance.dataProviderProvenance.name, ...
                "mockFormalDataProvider");
            testCase.verifyTrue(isfile(run.preflightEvidencePath));
            testCase.verifyTrue(isfile(run.referenceEvidencePath));
            testCase.verifyTrue(isfile(run.figure7ReuseEvidencePath));
            testCase.verifyTrue(isfile( ...
                run.figure7ReuseManifestEvidencePath));
            testCase.verifyTrue(isfile( ...
                run.monthlyDailyMetricsEvidencePath));
            testCase.verifyTrue(isfile( ...
                run.monthlyDailyManifestEvidencePath));
            testCase.verifyEqual(fileread( ...
                run.monthlyDailyMetricsEvidencePath), ...
                fileread(testCase.Fixture.existingDailyMetricsPath));
            testCase.verifyEqual(fileread( ...
                run.monthlyDailyManifestEvidencePath), ...
                fileread(testCase.Fixture.existingDailyManifestPath));
            testCase.verifyEqual(run.existingDailyMetricsPath, ...
                testCase.Fixture.existingDailyMetricsPath);
            testCase.verifyEqual(run.existingDailyManifestPath, ...
                testCase.Fixture.existingDailyManifestPath);
            testCase.verifyTrue(isfile(run.interpretationPath));
            interpretation = lower(fileread(run.interpretationPath));
            testCase.verifyTrue(contains(interpretation, "proxy"));
            testCase.verifyTrue(contains(interpretation, "not exact"));
            testCase.verifyTrue(contains(interpretation, ...
                "no post-solve tuning"));
            testCase.verifyTrue(run.acceptance.allRulesPassed);
            testCase.verifyEqual(string(manifest.schemaVersion), ...
                "StoreNet-run-manifest-v2");
            testCase.verifyTrue(manifest.formalMode);
            testCase.verifyEqual(string( ...
                manifest.contracts.data.contractId), "SR2020-IR-v2");
            testCase.verifyEqual(string( ...
                manifest.contracts.model.contractId), "B2022-IR-v1");
            testCase.verifyEqual(string(manifest.contracts.data.gitCommit), ...
                string(repmat('d', 1, 40)));
            testCase.verifyEqual(string(manifest.solver.name), ...
                "mockFormalSolver");
            testCase.verifyEqual(string(manifest.dataProvider.name), ...
                "mockFormalDataProvider");
            testCase.verifyEqual(string( ...
                manifest.experiment.existingDailyMetricsPath), ...
                testCase.Fixture.existingDailyMetricsPath);
            testCase.verifyEqual(string( ...
                manifest.experiment.existingDailyManifestPath), ...
                testCase.Fixture.existingDailyManifestPath);
            testCase.verifyEqual(string( ...
                manifest.experiment.monthlyDailyMetricsEvidencePath), ...
                run.monthlyDailyMetricsEvidencePath);
            testCase.verifyEqual(string( ...
                manifest.experiment.monthlyDailyManifestEvidencePath), ...
                run.monthlyDailyManifestEvidencePath);
            testCase.verifyFalse( ...
                manifest.artifactClosure.resultManifestHashStoredInRunManifest);
            testCase.verifyFalse(contains(fileread(run.manifestPath), ...
                "resultManifestSha256"));
            testCase.verifyTrue(run.closure.verificationPassed);
            testCase.verifyTrue(run.scientificClosure.verificationPassed);
            testCase.verifyEqual(run.closure.verificationExitStatus, 0);
            testCase.verifyEqual(closurePaths, sort(closurePaths));
            testCase.verifyFalse(any(closurePaths == ...
                "RESULT_MANIFEST.sha256"));
            testCase.verifyEqual(closurePaths, expectedPaths);
            testCase.verifyTrue(any(closurePaths == ...
                "evidence/monthly_daily_metrics_source.csv"));
            testCase.verifyTrue(any(closurePaths == ...
                "evidence/monthly_daily_manifest.json"));
            testCase.verifyFalse(any(scientificClosurePaths == ...
                "SCIENTIFIC_ARTIFACT_MANIFEST.sha256"));
            testCase.verifyFalse(any(ismember(scientificClosurePaths, ...
                ["postsolve_acceptance.csv", ...
                "postsolve_acceptance.json", "RESULT_MANIFEST.sha256"])));
            writelines("tampered acceptance", run.acceptance.csvPath);
            [tamperStatus, ~] = storenetio.verifyManifest( ...
                run.closure.rootDirectory, run.closure.manifestPath);
            testCase.verifyNotEqual(tamperStatus, 0, ...
                "Final closure must detect acceptance-report tampering.");
        end

        function testExistingFormalRootIsRejectedBeforePreflight(testCase)
            mkdir(testCase.Fixture.formalRoot);
            invoke = @() invokeFormal(testCase.Fixture, ...
                @passingPreflight, false);

            testCase.verifyError(invoke, "StoreNet:FormalOutputExists");
            testCase.verifyFalse(isfile(fullfile( ...
                testCase.Fixture.stagingRoot, ...
                "review_preflight.json")));
        end

        function testNoncanonicalCallbacksAreRejectedBeforePreflight(testCase)
            invoke = @() invokeFormal(testCase.Fixture, ...
                @passingPreflight, true);

            testCase.verifyError(invoke, ...
                "StoreNet:NoncanonicalFormalCallback");
            testCase.verifyFalse(isfolder(testCase.Fixture.formalRoot));
            testCase.verifyFalse(isfile(fullfile( ...
                testCase.Fixture.stagingRoot, ...
                "review_preflight.json")));
        end
    end
end

function run = invokeFormal(fixture, preflightRunner, enforceCanonical)
run = run_bahloul_formal_v1( ...
    RepositoryRoot=fixture.root, FormalRoot=fixture.formalRoot, ...
    StagingRoot=fixture.stagingRoot, DataRoot=fixture.dataRoot, ...
    H4DiagnosticsPath=fixture.h4DiagnosticsPath, ...
    DataContractPath=fixture.dataContractPath, ...
    ModelContractPath=fixture.modelContractPath, ...
    ReferenceManifestPath=fixture.referenceManifestPath, ...
    ReleaseManifestPath=fixture.releaseManifestPath, ...
    Figure6EvidenceDirectory=fixture.figure6EvidenceDirectory, ...
    Figure7ReuseCsv=fixture.figure7ReuseCsv, ...
    Figure7ReuseManifestPath=fixture.figure7ReuseManifestPath, ...
    PreflightRunner=preflightRunner, ...
    TypicalRunner=@mockTypicalRunner, ...
    MonthlyRunner=@mockMonthlyRunner, ...
    SensitivityRunner=@mockSensitivityRunner, ...
    AcceptanceEvaluator=@mockPassingAcceptance, ...
    Solver=@mockFormalSolver, ...
    DataProvider=@mockFormalDataProvider, ...
    EnforceCanonicalCallbacks=enforceCanonical);
end

function acceptance = mockPassingAcceptance(formalRoot)
csvPath = string(fullfile(formalRoot, "postsolve_acceptance.csv"));
jsonPath = string(fullfile(formalRoot, "postsolve_acceptance.json"));
writetable(table("R1", "PASS", VariableNames=["RuleId", "Status"]), ...
    csvPath);
acceptance = struct("allRulesPassed", true, "overallStatus", "PASS", ...
    "csvPath", csvPath, "jsonPath", jsonPath);
writelines(jsonencode(acceptance, PrettyPrint=true), jsonPath);
end

function report = passingPreflight(options)
arguments
    options.RepositoryRoot (1, 1) string
    options.ReportPath (1, 1) string
    options.FormalOutputPath (1, 1) string
    options.DataContractPath (1, 1) string
    options.ModelContractPath (1, 1) string
    options.ReferenceManifestPath (1, 1) string
    options.ReleaseManifestPath (1, 1) string
    options.Figure6EvidenceDirectory (1, 1) string
    options.ThrowOnFailure (1, 1) logical
    options.Solver (1, 1) function_handle
    options.DataProvider (1, 1) function_handle
end
report = writeMockPreflight(options, true);
end

function report = failingPreflight(options)
arguments
    options.RepositoryRoot (1, 1) string
    options.ReportPath (1, 1) string
    options.FormalOutputPath (1, 1) string
    options.DataContractPath (1, 1) string
    options.ModelContractPath (1, 1) string
    options.ReferenceManifestPath (1, 1) string
    options.ReleaseManifestPath (1, 1) string
    options.Figure6EvidenceDirectory (1, 1) string
    options.ThrowOnFailure (1, 1) logical
    options.Solver (1, 1) function_handle
    options.DataProvider (1, 1) function_handle
end
report = writeMockPreflight(options, false);
end

function report = writeMockPreflight(options, allPassed)
report = struct;
report.schemaVersion = "B2022-review-preflight-v1";
report.allPassed = allPassed;
report.formalOutputWasAbsent = ~isfolder(options.FormalOutputPath) && ...
    ~isfile(options.FormalOutputPath);
report.contracts = struct( ...
    "dataContractId", "SR2020-IR-v2", ...
    "dataContractSha256", sha256FixtureFile(options.DataContractPath), ...
    "dataContractGitCommit", string(repmat('d', 1, 40)), ...
    "modelContractId", "B2022-IR-v1", ...
    "modelContractSha256", sha256FixtureFile(options.ModelContractPath));
report.references = struct("manifestSha256", ...
    sha256FixtureFile(options.ReferenceManifestPath));
report.gitPreflight = struct( ...
    "repositoryRoot", options.RepositoryRoot, ...
    "commit", string(repmat('c', 1, 40)), ...
    "statusAvailable", true, "isClean", true, ...
    "untrackedFilesIncluded", true, ...
    "capturedBeforeOutputDirectory", true, ...
    "statusPorcelain", "");
report.runtime = struct("solverFunction", ...
    string(func2str(options.Solver)), "dataProviderFunction", ...
    string(func2str(options.DataProvider)));
report.reportPath = options.ReportPath;
folder = fileparts(options.ReportPath);
mkdir(folder);
writelines(jsonencode(report, PrettyPrint=true), options.ReportPath);
report.reportSha256 = sha256FixtureFile(options.ReportPath);
end

function run = mockTypicalRunner(day, options)
arguments
    day (1, 1) datetime
    options.IntervalMinutes (1, 1) double
    options.QualityMode (1, 1) string
    options.DataRoot (1, 1) string
    options.OutputRoot (1, 1) string
    options.RunId (1, 1) string
    options.H4DiagnosticsPath (1, 1) string
    options.DataProvider (1, 1) function_handle
    options.Solver (1, 1) function_handle
    options.FigureVisible (1, 1) logical
    options.PersistSolutions (1, 1) logical
    options.Provenance (1, 1) struct
end
run = writeMockChild(options.OutputRoot, options.RunId, "TYPICAL");
run.day = day;
run.intervalMinutes = options.IntervalMinutes;
run.qualityMode = options.QualityMode;
run.h4DiagnosticsPath = options.H4DiagnosticsPath;
run.solver = string(func2str(options.Solver));
run.dataProvider = string(func2str(options.DataProvider));
run.provenance = options.Provenance;
end

function run = mockMonthlyRunner(options)
arguments
    options.QualityMode (1, 1) string
    options.DataRoot (1, 1) string
    options.OutputRoot (1, 1) string
    options.RunId (1, 1) string
    options.H4DiagnosticsPath (1, 1) string
    options.DataProvider (1, 1) function_handle
    options.Solver (1, 1) function_handle
    options.FigureVisible (1, 1) logical
    options.PersistSolutions (1, 1) logical
    options.ExistingDailyMetricsPath (1, 1) string
    options.ExistingDailyManifestPath (1, 1) string
    options.Provenance (1, 1) struct
end
run = writeMockChild(options.OutputRoot, options.RunId, "MONTHLY");
run.qualityMode = options.QualityMode;
run.h4DiagnosticsPath = options.H4DiagnosticsPath;
run.existingDailyMetricsPath = options.ExistingDailyMetricsPath;
run.existingDailyManifestPath = options.ExistingDailyManifestPath;
run.provenance = options.Provenance;
end

function run = mockSensitivityRunner(day, options)
arguments
    day (1, 1) datetime
    options.QualityMode (1, 1) string
    options.DataRoot (1, 1) string
    options.OutputRoot (1, 1) string
    options.RunId (1, 1) string
    options.H4DiagnosticsPath (1, 1) string
    options.ReuseFigure7Csv (1, 1) string
    options.DataProvider (1, 1) function_handle
    options.Solver (1, 1) function_handle
    options.FigureVisible (1, 1) logical
    options.Provenance (1, 1) struct
end
run = writeMockChild(options.OutputRoot, options.RunId, "SENSITIVITY");
run.day = day;
run.qualityMode = options.QualityMode;
run.h4DiagnosticsPath = options.H4DiagnosticsPath;
run.reuseFigure7Csv = options.ReuseFigure7Csv;
run.provenance = options.Provenance;
end

function run = writeMockChild(outputRoot, runId, label)
appendCallOrder(outputRoot, label);
runDirectory = string(fullfile(outputRoot, runId));
mkdir(runDirectory);
artifactPath = string(fullfile(runDirectory, "mock_artifact.txt"));
writelines(label, artifactPath);
run = struct("runDirectory", runDirectory, "artifactPath", artifactPath);
end

function appendCallOrder(outputRoot, label)
path = fullfile(outputRoot, "mock_call_order.txt");
fileId = fopen(path, "at", "n", "UTF-8");
assert(fileId >= 0, "TestBahloulFormalV1:OrderLogFailed", ...
    "Unable to open mock call-order log.");
cleaner = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s\n", label);
clear cleaner
end

function mockFormalSolver(varargin)
error("TestBahloulFormalV1:UnexpectedSolverCall", ...
    "The formal solver must not run in an orchestration unit test.");
end

function mockFormalDataProvider(varargin)
error("TestBahloulFormalV1:UnexpectedProviderCall", ...
    "The formal data provider must not run in an orchestration unit test.");
end

function fixture = createFormalFixture()
root = string(tempname);
mkdir(root);
storeNetRoot = fullfile(root, "StoreNet");
dataRoot = fullfile(storeNetRoot, "data", "raw");
docsRoot = fullfile(storeNetRoot, "docs");
referenceRoot = fullfile(storeNetRoot, "reference");
figureRoot = fullfile(storeNetRoot, "results", ...
    "data_paper_figures_5_10_v2");
figure7ReuseRoot = fullfile(storeNetRoot, "results", ...
    "sensitivity_20200824_vppbm");
monthlyReuseRoot = fullfile(storeNetRoot, "results", ...
    "monthly_2020_release_literal_bounded60");
mkdir(dataRoot);
mkdir(docsRoot);
mkdir(referenceRoot);
mkdir(figureRoot);
mkdir(figure7ReuseRoot);
mkdir(monthlyReuseRoot);

dataContractPath = string(fullfile(docsRoot, ...
    "REPRODUCTION_CONTRACT.md"));
modelContractPath = string(fullfile(docsRoot, ...
    "B2022_REPRODUCTION_CONTRACT.md"));
referenceManifestPath = string(fullfile(referenceRoot, ...
    "B2022_REFERENCE_MANIFEST.csv"));
h4DiagnosticsPath = string(fullfile(figureRoot, ...
    "figure6_h4_daily_diagnostics.csv"));
writelines("SR2020-IR-v2 fixture", dataContractPath);
writelines("B2022-IR-v1 fixture", modelContractPath);
writelines("ArtifactId,Sha256" + newline + "FIXTURE," + ...
    sha256FixtureFile(dataContractPath), referenceManifestPath);
writelines("Date,AlignmentCategory" + newline + ...
    "2020-08-24,same_date_plus60_core", h4DiagnosticsPath);
figure7ReuseCsv = string(fullfile(figure7ReuseRoot, "sensitivity.csv"));
figure7ReuseManifestPath = string(fullfile(figure7ReuseRoot, "manifest.json"));
writelines("fixture figure 7 reuse", figure7ReuseCsv);
writelines('{"fixture":true}', figure7ReuseManifestPath);
existingDailyMetricsPath = string(fullfile(monthlyReuseRoot, ...
    "monthly_metrics.csv"));
existingDailyManifestPath = string(fullfile(monthlyReuseRoot, ...
    "manifest.json"));
writelines("Day,Strategy,Status", existingDailyMetricsPath);
writelines('{"experiment":{"qualityMode":"release_literal"}}', ...
    existingDailyManifestPath);

releaseManifestPath = createReleaseFixture(root, dataRoot);
fixture = struct;
fixture.root = root;
fixture.formalRoot = string(fullfile(storeNetRoot, "results", ...
    "formal_fixture"));
fixture.stagingRoot = string(fullfile(storeNetRoot, "tmp", ...
    "formal_preflight"));
fixture.dataRoot = string(dataRoot);
fixture.h4DiagnosticsPath = h4DiagnosticsPath;
fixture.dataContractPath = dataContractPath;
fixture.modelContractPath = modelContractPath;
fixture.referenceManifestPath = referenceManifestPath;
fixture.releaseManifestPath = releaseManifestPath;
fixture.figure6EvidenceDirectory = string(figureRoot);
fixture.figure7ReuseCsv = figure7ReuseCsv;
fixture.figure7ReuseManifestPath = figure7ReuseManifestPath;
fixture.existingDailyMetricsPath = existingDailyMetricsPath;
fixture.existingDailyManifestPath = existingDailyManifestPath;
end

function manifestPath = createReleaseFixture(repositoryRoot, dataRoot)
fileCount = 46;
files = strings(fileCount, 1);
for fileIndex = 1:fileCount
    files(fileIndex) = fullfile(dataRoot, ...
        "release_" + compose("%02d", fileIndex) + ".csv");
    writelines("fixture " + fileIndex, files(fileIndex));
end
manifestPath = string(fullfile(repositoryRoot, "StoreNet", "data", ...
    "RELEASE_MANIFEST.sha256"));
relative = replace(files, repositoryRoot + filesep, "");
lines = strings(fileCount + 1, 1);
lines(1) = "# Synthetic formal-orchestrator release fixture";
for fileIndex = 1:fileCount
    lines(fileIndex + 1) = sha256FixtureFile(files(fileIndex)) + ...
        "  " + relative(fileIndex);
end
writelines(lines, manifestPath);
end

function order = readCallOrder(formalRoot)
order = strip(readlines(fullfile(formalRoot, "mock_call_order.txt")));
order = order(strlength(order) > 0);
end

function directories = expectedChildDirectories(formalRoot)
ids = ["b2022_typical_v1_20200824"; "b2022_monthly_v1_2020"; ...
    "b2022_sensitivity_v1_20200824"];
directories = fullfile(formalRoot, ids);
end

function paths = readClosurePaths(manifestPath)
lines = strip(readlines(manifestPath));
lines = lines(strlength(lines) > 0);
paths = extractAfter(lines, 66);
end

function paths = recursiveFixtureFiles(root)
entries = dir(fullfile(root, "**", "*"));
entries = entries(~[entries.isdir]);
absolute = string(fullfile({entries.folder}, {entries.name})).';
prefix = string(root) + filesep;
paths = replace(extractAfter(absolute, strlength(prefix)), filesep, "/");
paths(paths == "RESULT_MANIFEST.sha256") = [];
paths = sort(paths);
end

function hash = sha256FixtureFile(path)
hash = storenetio.hashFile(path);
end

function removeFixture(root)
if isfolder(root)
    rmdir(root, "s");
end
end
