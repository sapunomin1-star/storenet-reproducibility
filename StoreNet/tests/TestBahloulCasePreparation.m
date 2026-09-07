classdef TestBahloulCasePreparation < matlab.unittest.TestCase
    %TESTBAHLOULCASEPREPARATION Tests frozen cohort and boundary scenarios.

    properties
        DiagnosticsPath
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
        function createDiagnostics(testCase)
            temporaryFolder = string(tempname);
            mkdir(temporaryFolder);
            testCase.addTeardown(@() rmdir(temporaryFolder, "s"));
            testCase.DiagnosticsPath = fullfile(temporaryFolder, "h4.csv");
            diagnostics = table( ...
                ["2020-01-02"; "2020-01-02"; "2020-08-24"; "2020-08-24"], ...
                ["Consumption"; "Production"; "Consumption"; "Production"], ...
                ["unaffected_same0"; "unaffected_same0"; ...
                "same_date_plus60_core"; "same_date_plus60_core"], ...
                VariableNames=["Date", "Signal", "AlignmentCategory"]);
            writetable(diagnostics, testCase.DiagnosticsPath);
        end
    end

    methods (Test)
        function testPublicDcScenarioPreservesReleasedPv(testCase)
            data = makeCaseData(datetime(2020, 1, 2));
            config = makeCaseConfig();

            [actual, actualConfig, meta] = prepare_bahloul_case(data, config, ...
                CohortId="H20_PV10", PvBoundaryId="DC_SOURCE", ...
                TransferLossFraction=0.07, ...
                H4DiagnosticsPath=testCase.DiagnosticsPath);

            testCase.verifyEqual(actual.pvKW, data.pvKW, AbsTol=1e-12);
            testCase.verifyEqual(actual.releasedPvKW, data.pvKW, AbsTol=1e-12);
            testCase.verifyEqual(meta.houseCount, 20);
            testCase.verifyEqual(meta.pvHomeCount, 10);
            testCase.verifyFalse(meta.h4MaskAffected);
            testCase.verifyEqual(actualConfig.transferLossFraction, 0.07, ...
                AbsTol=1e-12);
        end

        function testAcBoundaryReconstructsDcSource(testCase)
            data = makeCaseData(datetime(2020, 1, 2));
            config = makeCaseConfig();

            [actual, actualConfig] = prepare_bahloul_case(data, config, ...
                PvBoundaryId="AC_METER_RECONSTRUCTED_DC", ...
                H4DiagnosticsPath=testCase.DiagnosticsPath);

            testCase.verifyEqual(actual.pvKW, ...
                data.pvKW ./ config.etaPvAC, AbsTol=1e-12);
            testCase.verifyEqual(actual.releasedPvKW, data.pvKW, AbsTol=1e-12);
            testCase.verifyEqual(actualConfig.pvBoundaryId, ...
                "AC_METER_RECONSTRUCTED_DC");
        end

        function testH4PairRemovesOnlyH4(testCase)
            data = makeCaseData(datetime(2020, 8, 24));
            config = makeCaseConfig();

            [actual, actualConfig, meta] = prepare_bahloul_case(data, config, ...
                CohortId="H19_EXCL_H4_PV9", ...
                H4DiagnosticsPath=testCase.DiagnosticsPath);

            testCase.verifySize(actual.loadKW, [4, 19]);
            testCase.verifyFalse(any(actual.houseIds == "H4"));
            testCase.verifyEqual(actualConfig.nHomes, 19);
            testCase.verifyEqual(meta.pvHomeCount, 9);
            testCase.verifyEqual(meta.excludedHomes, "H4");
            testCase.verifyTrue(meta.h4MaskAffected);
            testCase.verifyFalse(meta.h4InputWasShiftedOrRepaired);
        end

        function testMissingRequiredH4DateFailsClosed(testCase)
            data = makeCaseData(datetime(2020, 2, 2));
            config = makeCaseConfig();

            operation = @() prepare_bahloul_case(data, config, ...
                H4DiagnosticsPath=testCase.DiagnosticsPath);

            testCase.verifyError(operation, "StoreNet:MissingH4Day");
        end

        function testCarriesSubsetQualityMasksAndFormalProvenance(testCase)
            data = makeCaseData(datetime(2020, 8, 24));
            config = makeCaseConfig();
            dataMeta = struct;
            dataMeta.qualityMode = "exclude_flagged_pv";
            dataMeta.binComplete = true(4, 20);
            dataMeta.binObserved = true(4, 20);
            dataMeta.binObserved(1, 4) = false;
            provenance = struct( ...
                "dataContractId", "SR2020-IR-v2", ...
                "dataContractSha256", repmat("a", 1, 64), ...
                "dataContractGitCommit", repmat("b", 1, 40), ...
                "modelContractId", "B2022-IR-v1", ...
                "modelContractSha256", repmat("c", 1, 64), ...
                "referenceManifestSha256", repmat("d", 1, 64));

            [~, ~, meta] = prepare_bahloul_case(data, config, ...
                CohortId="H19_EXCL_H4_PV9", ...
                H4DiagnosticsPath=testCase.DiagnosticsPath, ...
                DataMeta=dataMeta, Provenance=provenance);

            testCase.verifySize(meta.observationMask, [4, 19]);
            testCase.verifyFalse(any(meta.interpolationMask, "all"));
            testCase.verifyEqual(meta.cohortMask(4), false);
            testCase.verifyEqual(meta.dataContractId, "SR2020-IR-v2");
            testCase.verifyEqual(meta.referenceManifestSha256, ...
                repmat("d", 1, 64));
        end
    end
end

function data = makeCaseData(day)
data = struct;
data.day = day;
data.time = day + minutes((30:30:120).');
data.dtHours = 0.5;
data.houseIds = compose("H%d", 1:20);
data.homeNames = data.houseIds;
data.loadKW = repmat(1:20, 4, 1);
data.pvKW = zeros(4, 20);
data.pvKW(:, [1, 2, 3, 4, 5, 7, 10, 11, 13, 17]) = 0.95;
data.pvKWh = data.pvKW .* data.dtHours;
data.pvHomeMask = any(data.pvKW > 0, 1);
end

function config = makeCaseConfig()
config = struct;
config.homes = compose("H%d", 1:20);
config.nHomes = 20;
config.pvHomeMask = ismember(config.homes, ...
    ["H1", "H2", "H3", "H4", "H5", "H7", "H10", "H11", "H13", "H17"]);
config.pvHomes = config.homes(config.pvHomeMask);
config.etaPvAC = 0.95;
config.transferLossFraction = 0.07;
end
