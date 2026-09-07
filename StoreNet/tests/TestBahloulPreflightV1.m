classdef TestBahloulPreflightV1 < matlab.unittest.TestCase
    %TESTBAHLOULPREFLIGHTV1 Tests fail-closed pre-solve evidence capture.

    properties
        OutputRoot
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
        function makeOutputRoot(testCase)
            testCase.OutputRoot = string(tempname);
            mkdir(testCase.OutputRoot);
            testCase.addTeardown(@() rmdir(testCase.OutputRoot, "s"));
        end
    end

    methods (Test)
        function testCapturesImmutableEvidenceWithoutCreatingFormalOutput(testCase)
            repositoryRoot = string(fileparts(fileparts( ...
                fileparts(mfilename("fullpath")))));
            reportPath = fullfile(testCase.OutputRoot, ...
                "review_preflight.json");
            formalOutput = fullfile(testCase.OutputRoot, "formal_never_create");

            report = run_bahloul_preflight_v1( ...
                RepositoryRoot=repositoryRoot, ReportPath=reportPath, ...
                FormalOutputPath=formalOutput, RunAnalyzer=false, ...
                RunTests=false, RequireCleanGit=false, ...
                ThrowOnFailure=false);

            statuses = string({report.gates.status});
            expectedRunners = fullfile(repositoryRoot, "StoreNet", "src", ...
                ["run_bahloul_typical_v1.m"; ...
                "run_bahloul_monthly_v1.m"; ...
                "run_bahloul_sensitivity_v1.m"]);
            testCase.verifyTrue(report.release.allPassed);
            testCase.verifyTrue(report.figure6Evidence.allPassed);
            testCase.verifyTrue(report.references.allPassed);
            testCase.verifyEqual(report.implementation.scenarioRunners(:), ...
                expectedRunners);
            testCase.verifyEqual(report.analyzer.fileCount, 19);
            testCase.verifyEqual(report.tests.fileCount, 13);
            testCase.verifyEqual(report.gates(5).machineEvidence, ...
                "typical/monthly/sensitivity fixture inventories");
            testCase.verifyEqual(statuses(1:3), repmat("PASS", 1, 3));
            testCase.verifyEqual(statuses(4), "FAIL");
            testCase.verifyEqual(statuses(8), "FAIL");
            testCase.verifyEqual(statuses(9), "PASS");
            testCase.verifyFalse(report.allPassed);
            testCase.verifyFalse(isfolder(formalOutput));
            testCase.verifyTrue(isfile(reportPath));
            testCase.verifyEqual(strlength(report.reportSha256), 64);
        end
    end
end
