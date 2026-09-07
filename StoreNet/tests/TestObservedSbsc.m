classdef TestObservedSbsc < matlab.unittest.TestCase
    %TESTOBSERVEDSBSC Tests the measured same-system observational proxy.

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
        function createOutputRoot(testCase)
            testCase.OutputRoot = string(tempname);
            mkdir(testCase.OutputRoot);
            testCase.addTeardown(@() rmdir(testCase.OutputRoot, "s"));
        end
    end

    methods (Test)
        function testUsesReleasedProductionWithoutEtaOrXi(testCase)
            [data, config] = makeObservedCase();

            [metrics, profiles] = evaluate_observed_sbsc(data, config);

            testCase.verifyEqual(metrics.paperLoadOnlyBaselineBillEUR, ...
                0.285, AbsTol=1e-12);
            testCase.verifyEqual( ...
                metrics.observedReleasePvSelfNoBatteryBaselineBillEUR, ...
                0.21375, AbsTol=1e-12);
            testCase.verifyEqual(metrics.observedBillEUR, 0.16525, ...
                AbsTol=1e-12);
            testCase.verifyEqual(metrics.paperLoadOnlySavingsPercent, ...
                42.017543859649116, ...
                AbsTol=1e-12);
            testCase.verifyEqual( ...
                metrics.observedReleaseEngineeringSavingsPercent, ...
                22.690058479532158, ...
                AbsTol=1e-12);
            testCase.verifyEqual(profiles.ObservedReleasedPvKW, [0.5; 0.5], ...
                AbsTol=1e-12);
            testCase.verifyEqual(profiles.ReleaseBatterySignedKW, [-0.3; 0.4], ...
                AbsTol=1e-12);
            testCase.verifyEqual(metrics.releaseBatteryThroughputKWh, 0.55, ...
                AbsTol=1e-12);
            testCase.verifyEqual(profiles.FeedInKW, [0.2; 0.3], ...
                AbsTol=1e-12);
            testCase.verifyEqual(metrics.totalFeedInKWh, 0.25, AbsTol=1e-12);
            testCase.verifyEqual(metrics.pvBoundaryId, ...
                "OBSERVED_RELEASE_FIELDS");
            testCase.verifyFalse(metrics.pvEfficiencyApplied);
            testCase.verifyFalse(metrics.sharingLossApplied);
            testCase.verifyTrue(isnan(metrics.xi));
            testCase.verifyFalse( ...
                metrics.paperLoadOnlySavingsPercentDenominatorIsZero);
            testCase.verifyFalse( ...
                metrics. ...
                observedReleaseEngineeringSavingsPercentDenominatorIsZero);
        end

        function testZeroDenominatorsReturnNaNAndExplicitFlags(testCase)
            [data, config] = makeObservedCase();
            data.loadKW(:) = 0;
            data.pvKW(:) = 0;
            data.releasedPvKW(:) = 0;
            data.fromGridKW(:) = 0;
            data.chargeKW(:) = 0;
            data.dischargeKW(:) = 0;

            metrics = evaluate_observed_sbsc(data, config);

            testCase.verifyTrue(isnan( ...
                metrics.paperLoadOnlySavingsPercent));
            testCase.verifyTrue(isnan( ...
                metrics.observedReleaseEngineeringSavingsPercent));
            testCase.verifyTrue( ...
                metrics.paperLoadOnlySavingsPercentDenominatorIsZero);
            testCase.verifyTrue( ...
                metrics. ...
                observedReleaseEngineeringSavingsPercentDenominatorIsZero);
        end

        function testEtaBoundaryAndXiCannotChangeObservedBaseline(testCase)
            [data, config] = makeObservedCase();
            [expected, expectedProfiles] = evaluate_observed_sbsc(data, config);
            changedConfig = config;
            changedConfig.etaPvAC = 0.01;
            changedConfig.pvBoundaryId = "AC_METER_RECONSTRUCTED_DC";
            changedConfig.transferLossFraction = 0.99;
            changedConfig.xi = 0.42;

            [actual, actualProfiles] = evaluate_observed_sbsc( ...
                data, changedConfig);

            testCase.verifyEqual(actual, expected);
            testCase.verifyEqual(actualProfiles, expectedProfiles);
        end

        function testPreparesObservedLabelsAndDirectReleaseData(testCase)
            [data, config, caseMeta] = makeObservedCase();

            [actualData, actualConfig, actualMeta] = ...
                prepare_observed_sbsc_case(data, config, caseMeta);

            testCase.verifyEqual(actualData.pvKW, data.releasedPvKW);
            testCase.verifyEqual(actualConfig.pvBoundaryId, ...
                "OBSERVED_RELEASE_FIELDS");
            testCase.verifyTrue(isnan(actualConfig.transferLossFraction));
            testCase.verifyTrue(isnan(actualConfig.xi));
            testCase.verifyEqual(actualMeta.scenarioId, ...
                "OBSERVED_RELEASE_H20_PV10");
            testCase.verifyEqual(actualMeta.pairId, ...
                "OBSERVED_RELEASE_PAIR");
            testCase.verifyEqual(actualMeta.sensitivityRole, ...
                "OBSERVED_PRIMARY");
            testCase.verifyEqual(actualMeta.pvBoundaryId, ...
                "OBSERVED_RELEASE_FIELDS");
            testCase.verifyTrue(isnan(actualMeta.transferLossFraction));
            testCase.verifyTrue(isnan(actualMeta.xi));
            testCase.verifyFalse(actualMeta.observedPvEfficiencyApplied);
            testCase.verifyFalse(actualMeta.observedSharingLossApplied);
        end

        function testWritesContentAddressedEvidenceAndReevaluatesOffline(testCase)
            [data, config, caseMeta] = makeObservedCase();
            [expected, profiles] = evaluate_observed_sbsc(data, config);
            caseDirectory = fullfile(testCase.OutputRoot, "observed_case");

            artifacts = write_bahloul_observed_artifacts(caseDirectory, ...
                data, config, caseMeta, expected, profiles);
            [actual, actualProfiles, evidence] = ...
                reevaluate_bahloul_observed_artifact(caseDirectory);
            inputFile = load(artifacts.inputsPath, "inputEvidence");
            solutionFile = load(artifacts.solutionPath, "solutionEvidence");

            testCase.verifyMatches(filenameOnly(artifacts.inputsPath), ...
                "^inputs_[0-9a-f]{64}\.mat$");
            testCase.verifyMatches(filenameOnly(artifacts.solutionPath), ...
                "^solution_[0-9a-f]{64}\.mat$");
            testCase.verifyEqual(artifacts.inputsSha256, ...
                sha256FileForTest(artifacts.inputsPath));
            testCase.verifyEqual(artifacts.solutionSha256, ...
                sha256FileForTest(artifacts.solutionPath));
            testCase.verifyEqual(actual.observedBillEUR, ...
                expected.observedBillEUR, AbsTol=1e-12);
            testCase.verifyEqual(actualProfiles, profiles);
            testCase.verifyEqual(evidence.persistedMetrics, expected);
            testCase.verifyFalse(evidence.solverInvoked);
            testCase.verifyEqual(inputFile.inputEvidence.config.pvBoundaryId, ...
                "OBSERVED_RELEASE_FIELDS");
            testCase.verifyTrue(isnan( ...
                inputFile.inputEvidence.config.transferLossFraction));
            testCase.verifyTrue(isnan(inputFile.inputEvidence.config.xi));
            testCase.verifyEqual( ...
                inputFile.inputEvidence.caseMeta.pvBoundaryId, ...
                "OBSERVED_RELEASE_FIELDS");
            testCase.verifyEqual( ...
                inputFile.inputEvidence.identity.experimentId.value, ...
                "B2022_TYPICAL_V1");
            testCase.verifyEqual( ...
                inputFile.inputEvidence.identity.caseId.value, ...
                "OBSERVED_RELEASE_H20_PV10_SB_SC");
            testCase.verifyEqual( ...
                inputFile.inputEvidence.identity.dataContractGitCommit.value, ...
                repmat("e", 1, 40));
            testCase.verifyTrue(isnan( ...
                inputFile.inputEvidence.identity.xi.value));
            testCase.verifyEqual(inputFile.inputEvidence.data.pvKW, ...
                data.releasedPvKW);
            testCase.verifyEqual(solutionFile.solutionEvidence.metrics, ...
                expected);
            testCase.verifyEqual(solutionFile.solutionEvidence.profiles, ...
                profiles);
            testCase.verifyEqual( ...
                solutionFile.solutionEvidence.identity.scenarioId.value, ...
                "OBSERVED_RELEASE_H20_PV10");
            testCase.verifyFalse(solutionFile.solutionEvidence.solverInvoked);
        end

        function testRejectsTamperedObservedSolution(testCase)
            [data, config, caseMeta] = makeObservedCase();
            [metrics, profiles] = evaluate_observed_sbsc(data, config);
            caseDirectory = fullfile(testCase.OutputRoot, "observed_case");
            artifacts = write_bahloul_observed_artifacts(caseDirectory, ...
                data, config, caseMeta, metrics, profiles);
            appendByte(artifacts.solutionPath);

            operation = @() reevaluate_bahloul_observed_artifact(caseDirectory);

            testCase.verifyError(operation, ...
                "StoreNet:ObservedBahloulArtifactChecksumMismatch");
        end

        function testObservedWriterRefusesOverwrite(testCase)
            [data, config, caseMeta] = makeObservedCase();
            [metrics, profiles] = evaluate_observed_sbsc(data, config);
            caseDirectory = fullfile(testCase.OutputRoot, "observed_case");
            write_bahloul_observed_artifacts(caseDirectory, data, config, ...
                caseMeta, metrics, profiles);

            operation = @() write_bahloul_observed_artifacts( ...
                caseDirectory, data, config, caseMeta, metrics, profiles);

            testCase.verifyError(operation, ...
                "StoreNet:BahloulCaseDirectoryExists");
        end

        function testObservedWriterRejectsNoncanonicalMetrics(testCase)
            [data, config, caseMeta] = makeObservedCase();
            [metrics, profiles] = evaluate_observed_sbsc(data, config);
            metrics.observedBillEUR = -999;
            caseDirectory = fullfile(testCase.OutputRoot, "observed_case");

            operation = @() write_bahloul_observed_artifacts( ...
                caseDirectory, data, config, caseMeta, metrics, profiles);

            testCase.verifyError(operation, ...
                "StoreNet:ObservedBahloulMetricMismatch");
        end

        function testRequiresAllReleasedFlowFields(testCase)
            [data, config] = makeObservedCase();
            missingFeedIn = rmfield(data, "feedInKW");
            missingCharge = rmfield(data, "chargeKW");
            missingDischarge = rmfield(data, "dischargeKW");

            testCase.verifyError(@() evaluate_observed_sbsc( ...
                missingFeedIn, config), "StoreNet:InvalidObservedSbscData");
            testCase.verifyError(@() evaluate_observed_sbsc( ...
                missingCharge, config), "StoreNet:InvalidObservedSbscData");
            testCase.verifyError(@() evaluate_observed_sbsc( ...
                missingDischarge, config), "StoreNet:InvalidObservedSbscData");
        end

        function testRejectsMismatchedReleasedFlowCohort(testCase)
            [data, config] = makeObservedCase();
            data.chargeKW = data.chargeKW(:, 1:19);

            operation = @() evaluate_observed_sbsc(data, config);

            testCase.verifyError(operation, ...
                "StoreNet:InvalidObservedSbscData");
        end

        function testRejectsMislabeledObservedCohort(testCase)
            [data, config, caseMeta] = makeObservedCase();
            caseMeta.cohortId = "H19_EXCL_H4_PV9";

            operation = @() prepare_observed_sbsc_case( ...
                data, config, caseMeta);

            testCase.verifyError(operation, ...
                "StoreNet:InvalidObservedSbscMetadata");
        end

        function testRejectsMissingMeasuredGrid(testCase)
            [data, config] = makeObservedCase();
            data = rmfield(data, "fromGridKW");

            operation = @() evaluate_observed_sbsc(data, config);

            testCase.verifyError(operation, ...
                "StoreNet:InvalidObservedSbscData");
        end
    end
end

function [data, config, caseMeta] = makeObservedCase()
day = datetime(2020, 1, 2);
data = struct;
data.time = day + hours(10) + minutes([0; 30]);
data.dtHours = 0.5;
data.houseIds = compose("H%d", 1:20);
data.loadKW = zeros(2, 20);
data.loadKW(:, 1) = [2; 2];
data.pvKW = zeros(2, 20);
data.pvKW(:, 1) = [20; 20];
data.releasedPvKW = zeros(2, 20);
data.releasedPvKW(:, 1) = [0.5; 0.5];
data.fromGridKW = zeros(2, 20);
data.fromGridKW(:, 1) = [1.5; 1];
data.chargeKW = zeros(2, 20);
data.chargeKW(:, 1) = [0.4; 0.1];
data.dischargeKW = zeros(2, 20);
data.dischargeKW(:, 1) = [0.1; 0.5];
data.feedInKW = zeros(2, 20);
data.feedInKW(:, 1) = [0.2; 0.3];

config = struct;
config.etaPvAC = 0.95;
config.pvBoundaryId = "DC_SOURCE";
config.transferLossFraction = 0.07;
config.nightPrice = 0.091;
config.dayPrice = 0.194;
config.dayStartHour = 10;
config.dayEndHour = 22;

caseMeta = struct;
caseMeta.day = day;
caseMeta.dateOrPeriod = day;
caseMeta.experimentId = "B2022_TYPICAL_V1";
caseMeta.caseId = "OBSERVED_RELEASE_H20_PV10_SB_SC";
caseMeta.strategy = "SB_SC";
caseMeta.scenarioId = "DC_XI007_H20";
caseMeta.pairId = "DC_XI007";
caseMeta.sensitivityRole = "PRIMARY";
caseMeta.cohortId = "H20_PV10";
caseMeta.houseCount = 20;
caseMeta.pvHomeCount = 10;
caseMeta.pvBoundaryId = "DC_SOURCE";
caseMeta.transferLossFraction = 0.07;
caseMeta.h4MaskAffected = false;
caseMeta.cohortMask = [true, false(1, 19)];
caseMeta.qualityMode = "short_gap_only";
caseMeta.observationMask = true(2, 1);
caseMeta.interpolationMask = false(2, 1);
caseMeta.dataContractId = "SR2020-IR-v2";
caseMeta.dataContractSha256 = repmat("a", 1, 64);
caseMeta.dataContractGitCommit = repmat("e", 1, 40);
caseMeta.modelContractId = "B2022-IR-v1";
caseMeta.modelContractSha256 = repmat("b", 1, 64);
caseMeta.referenceIds = "FIG5";
caseMeta.referenceHashes = repmat("c", 1, 64);
caseMeta.referenceManifestSha256 = repmat("d", 1, 64);
caseMeta.dataProviderProvenance = struct("name", "fixtureProvider", ...
    "version", "1");
end

function name = filenameOnly(path)
[~, stem, extension] = fileparts(path);
name = string(stem) + string(extension);
end

function hash = sha256FileForTest(path)
hash = storenetio.hashFile(path);
end

function appendByte(path)
fileId = fopen(path, "ab");
assert(fileId >= 0, "Test fixture could not open observed artifact.");
cleaner = onCleanup(@() fclose(fileId));
fwrite(fileId, uint8(0), "uint8");
clear cleaner
end

