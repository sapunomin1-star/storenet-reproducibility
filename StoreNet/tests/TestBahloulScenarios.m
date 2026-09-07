classdef TestBahloulScenarios < matlab.unittest.TestCase
    %TESTBAHLOULSCENARIOS Tests the preregistered scenario matrices.

    methods (TestClassSetup)
        function addSourceFolder(testCase)
            testFolder = fileparts(mfilename("fullpath"));
            sourceFolder = fullfile(fileparts(testFolder), "src");
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                sourceFolder));
        end
    end

    methods (Test)
        function testCoreMatrixHasThreeCompletePairs(testCase)
            scenarios = bahloul_scenarios("CORE_SIX");

            pairCounts = groupcounts(scenarios.PairId);

            testCase.verifyEqual(height(scenarios), 6);
            testCase.verifyEqual(pairCounts, 2 * ones(3, 1));
            testCase.verifyEqual(nnz(scenarios.CohortId == "H20_PV10"), 3);
            testCase.verifyEqual(nnz(scenarios.CohortId == ...
                "H19_EXCL_H4_PV9"), 3);
            testCase.verifyEqual(nnz(scenarios.IsPrimary), 1);
        end

        function testFigureSevenMatrixIsOnlyFrozenDcPair(testCase)
            scenarios = bahloul_scenarios("FIGURE7_PAIR");

            testCase.verifyEqual(height(scenarios), 2);
            testCase.verifyEqual(scenarios.PvBoundaryId, ...
                repmat("DC_SOURCE", 2, 1));
            testCase.verifyEqual(scenarios.TransferLossFraction, [0.07; 0.07], ...
                AbsTol=1e-12);
            testCase.verifyEqual(scenarios.CohortId, ...
                ["H20_PV10"; "H19_EXCL_H4_PV9"]);
        end
    end
end
