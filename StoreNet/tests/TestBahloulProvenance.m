classdef TestBahloulProvenance < matlab.unittest.TestCase
    %TESTBAHLOULPROVENANCE Contract tests for formal Bahloul provenance.

    properties
        FixtureRoot
        OutputDirectory
        ReleaseManifestPath
        ReleaseFiles
        GitPreflight
        RunInfo
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
            testCase.FixtureRoot = string(tempname);
            mkdir(testCase.FixtureRoot);
            testCase.addTeardown(@() removeFixtureRoot(testCase.FixtureRoot));
            testCase.OutputDirectory = fullfile(testCase.FixtureRoot, "output");
            [testCase.ReleaseManifestPath, testCase.ReleaseFiles] = ...
                createReleaseFixture(testCase.FixtureRoot, 46);
            testCase.GitPreflight = cleanGitPreflight(testCase.FixtureRoot);
            testCase.RunInfo = struct("runType", "provenance_fixture", ...
                "runId", "formal_fixture");
        end
    end

    methods (Test)
        function testLegacyCallRemainsVersionOne(testCase)
            [manifest, manifestPath] = write_run_manifest( ...
                testCase.OutputDirectory, testCase.RunInfo, ...
                RepositoryRoot=testCase.FixtureRoot, ...
                ReleaseManifestPath=testCase.ReleaseManifestPath);

            testCase.verifyEqual(manifest.schemaVersion, ...
                "StoreNet-run-manifest-v1");
            testCase.verifyFalse(isfield(manifest, "contracts"));
            testCase.verifyFalse(isfield(manifest, "dataProvider"));
            testCase.verifyTrue(isfile(manifestPath));
        end

        function testFormalManifestRecordsVerifiedProvenance(testCase)
            [manifest, manifestPath] = writeFormalManifest(testCase, ...
                testCase.ReleaseManifestPath, testCase.GitPreflight);
            persisted = jsondecode(fileread(manifestPath));

            testCase.verifyEqual(manifest.schemaVersion, ...
                "StoreNet-run-manifest-v2");
            testCase.verifyEqual(manifest.contracts.data.contractId, ...
                "SR2020-IR-v2");
            testCase.verifyEqual(manifest.contracts.model.contractId, ...
                "B2022-IR-v1");
            testCase.verifyEqual(manifest.contracts.data.gitCommit, ...
                string(repmat('d', 1, 40)));
            testCase.verifyEqual( ...
                manifest.references.referenceManifestSha256, ...
                string(repmat('e', 1, 64)));
            testCase.verifyEqual(manifest.solver.name, "fixtureSolver");
            testCase.verifyEqual(manifest.dataProvider.name, "fixtureProvider");
            testCase.verifyTrue(manifest.code.untrackedFilesIncluded);
            testCase.verifyTrue(manifest.code.capturedBeforeOutputDirectory);
            testCase.verifyTrue(manifest.release.verification.allPassed);
            testCase.verifyEqual( ...
                manifest.release.verification.manifestFileCount, 46);
            testCase.verifyEqual( ...
                manifest.release.verification.checkedFileCount, 46);
            testCase.verifyEqual( ...
                manifest.release.verification.passedFileCount, 46);
            testCase.verifyEqual(numel( ...
                manifest.release.verification.perFile), 46);
            testCase.verifyFalse( ...
                manifest.artifactClosure.resultManifestHashStoredInRunManifest);
            testCase.verifyFalse(contains(fileread(manifestPath), ...
                "resultManifestSha256"));
            testCase.verifyEqual(persisted.schemaVersion, ...
                'StoreNet-run-manifest-v2');
        end

        function testFormalModeRejectsChecksumMismatchBeforeOutput(testCase)
            writelines("tampered after manifest creation", ...
                testCase.ReleaseFiles(1));
            invoke = @() writeFormalManifest(testCase, ...
                testCase.ReleaseManifestPath, testCase.GitPreflight);

            testCase.verifyError(invoke, ...
                "StoreNet:ReleaseChecksumVerificationFailed");
            testCase.verifyFalse(isfolder(testCase.OutputDirectory));
        end

        function testFormalModeRequiresExactlyFortySixFiles(testCase)
            shortManifestPath = fullfile(testCase.FixtureRoot, ...
                "release-45.sha256");
            writeReleaseManifest(shortManifestPath, ...
                testCase.ReleaseFiles(1:45), testCase.FixtureRoot);
            invoke = @() writeFormalManifest(testCase, shortManifestPath, ...
                testCase.GitPreflight);

            testCase.verifyError(invoke, ...
                "StoreNet:ReleaseManifestCountMismatch");
            testCase.verifyFalse(isfolder(testCase.OutputDirectory));
        end

        function testFormalModeRejectsDirtyCallerPreflight(testCase)
            dirtyPreflight = testCase.GitPreflight;
            dirtyPreflight.isClean = false;
            dirtyPreflight.statusPorcelain = "?? untracked-input.m";
            invoke = @() writeFormalManifest(testCase, ...
                testCase.ReleaseManifestPath, dirtyPreflight);

            testCase.verifyError(invoke, "StoreNet:DirtyRepository");
            testCase.verifyFalse(isfolder(testCase.OutputDirectory));
        end

        function testFormalModeRequiresUntrackedFilesInPreflight(testCase)
            incompletePreflight = testCase.GitPreflight;
            incompletePreflight.untrackedFilesIncluded = false;
            invoke = @() writeFormalManifest(testCase, ...
                testCase.ReleaseManifestPath, incompletePreflight);

            testCase.verifyError(invoke, "StoreNet:GitPreflightIncomplete");
            testCase.verifyFalse(isfolder(testCase.OutputDirectory));
        end

        function testFormalModeRejectsPreflightFromAnotherRepository(testCase)
            mismatchedPreflight = testCase.GitPreflight;
            mismatchedPreflight.repositoryRoot = fullfile( ...
                testCase.FixtureRoot, "another-repository");
            invoke = @() writeFormalManifest(testCase, ...
                testCase.ReleaseManifestPath, mismatchedPreflight);

            testCase.verifyError(invoke, ...
                "StoreNet:GitPreflightRepositoryMismatch");
            testCase.verifyFalse(isfolder(testCase.OutputDirectory));
        end

        function testAutomaticPreflightRequiresUncreatedOutput(testCase)
            mkdir(testCase.OutputDirectory);
            invoke = @() writeFormalManifest(testCase, ...
                testCase.ReleaseManifestPath, struct);

            testCase.verifyError(invoke, "StoreNet:GitPreflightTooLate");
        end

        function testFormalModeRequiresExplicitContracts(testCase)
            invoke = @() write_run_manifest(testCase.OutputDirectory, ...
                testCase.RunInfo, FormalMode=true, ...
                RepositoryRoot=testCase.FixtureRoot, ...
                ReleaseManifestPath=testCase.ReleaseManifestPath);

            testCase.verifyError(invoke, ...
                "StoreNet:MissingFormalProvenance");
            testCase.verifyFalse(isfolder(testCase.OutputDirectory));
        end
    end
end

function [manifest, manifestPath] = writeFormalManifest(testCase, ...
        releaseManifestPath, gitPreflight)
solver = struct("name", "fixtureSolver", "interface", ...
    "injected test interface", "version", "1.0");
provider = struct("name", "fixtureProvider", "version", "1.0");
[manifest, manifestPath] = write_run_manifest(testCase.OutputDirectory, ...
    testCase.RunInfo, FormalMode=true, ...
    RepositoryRoot=testCase.FixtureRoot, ...
    ReleaseManifestPath=releaseManifestPath, ...
    DataContractId="SR2020-IR-v2", ...
    DataContractSha256=string(repmat('a', 1, 64)), ...
    DataContractGitCommit=string(repmat('d', 1, 40)), ...
    ModelContractId="B2022-IR-v1", ...
    ModelContractSha256=string(repmat('b', 1, 64)), ...
    ReferenceManifestSha256=string(repmat('e', 1, 64)), ...
    SolverProvenance=solver, DataProviderProvenance=provider, ...
    GitPreflight=gitPreflight);
end

function [manifestPath, files] = createReleaseFixture(root, fileCount)
releaseDirectory = fullfile(root, "release");
mkdir(releaseDirectory);
files = strings(fileCount, 1);
for fileIndex = 1:fileCount
    files(fileIndex) = fullfile(releaseDirectory, ...
        "release_file_" + compose("%02d", fileIndex) + ".txt");
    writelines("fixture " + fileIndex, files(fileIndex));
end
manifestPath = fullfile(root, "RELEASE_MANIFEST.sha256");
writeReleaseManifest(manifestPath, files, root);
end

function writeReleaseManifest(manifestPath, files, repositoryRoot)
lines = strings(numel(files) + 1, 1);
lines(1) = "# Synthetic 46-file release manifest for provenance tests.";
relativeFiles = replace(files, string(repositoryRoot) + filesep, "");
for fileIndex = 1:numel(files)
    digest = storenetio.hashFile(files(fileIndex));
    lines(fileIndex + 1) = digest + "  " + relativeFiles(fileIndex);
end
writelines(lines, manifestPath);
end

function preflight = cleanGitPreflight(repositoryRoot)
preflight = struct;
preflight.repositoryRoot = repositoryRoot;
preflight.commit = string(repmat('c', 1, 40));
preflight.statusAvailable = true;
preflight.isClean = true;
preflight.untrackedFilesIncluded = true;
preflight.capturedBeforeOutputDirectory = true;
preflight.statusPorcelain = "";
preflight.capturedAtUtc = "2026-09-01T00:00:00.000Z";
end

function removeFixtureRoot(root)
if isfolder(root)
    rmdir(root, "s");
end
end
