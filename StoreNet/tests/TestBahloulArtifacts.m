classdef TestBahloulArtifacts < matlab.unittest.TestCase
    %TESTBAHLOULARTIFACTS Tests durable, solver-free case reevaluation.

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
        function testWritesByteAddressedV2AndReevaluatesOffline(testCase)
            [data, config, caseMeta, solution] = makeTrivialCase();
            expected = evaluate_storenet(data, config, solution);
            persistedMetrics = expected;
            persistedMetrics.optimizedBillEUR = -999;
            caseDirectory = fullfile(testCase.OutputRoot, "case");

            artifacts = write_bahloul_case_artifacts(caseDirectory, ...
                data, config, caseMeta, solution, persistedMetrics);
            [actual, evidence] = reevaluate_bahloul_artifact(caseDirectory);
            inputFile = load(artifacts.inputsPath, "inputEvidence");
            solutionFile = load(artifacts.solutionPath, "solutionEvidence");

            testCase.verifyTrue(isfile(artifacts.inputsPath));
            testCase.verifyTrue(isfile(artifacts.solutionPath));
            testCase.verifyTrue(isfile(artifacts.stagesPath));
            testCase.verifyTrue(isfile(artifacts.metricsPath));
            testCase.verifyMatches(filenameOnly(artifacts.inputsPath), ...
                "^inputs_[0-9a-f]{64}\.mat$");
            testCase.verifyMatches(filenameOnly(artifacts.solutionPath), ...
                "^solution_[0-9a-f]{64}\.mat$");
            testCase.verifyEqual(artifacts.inputsSha256, ...
                sha256FileForTest(artifacts.inputsPath));
            testCase.verifyEqual(artifacts.solutionSha256, ...
                sha256FileForTest(artifacts.solutionPath));
            testCase.verifyEqual(hashFromFilename(artifacts.inputsPath), ...
                artifacts.inputsSha256);
            testCase.verifyEqual(hashFromFilename(artifacts.solutionPath), ...
                artifacts.solutionSha256);
            testCase.verifyEqual(actual.optimizedBillEUR, ...
                expected.optimizedBillEUR, AbsTol=1e-12);
            testCase.verifyEqual(actual.PaperLoadOnlyBaseline.savingsPercent, ...
                expected.PaperLoadOnlyBaseline.savingsPercent, AbsTol=1e-12);
            testCase.verifyEqual(evidence.persistedMetrics.optimizedBillEUR, ...
                -999);
            testCase.verifyFalse(evidence.legacyLayout);
            testCase.verifyEqual(inputFile.inputEvidence.schemaVersion, ...
                "B2022-input-evidence-v2");
            testCase.verifyEqual(inputFile.inputEvidence.pvAvailableAC, ...
                config.etaPvAC .* data.pvKW, AbsTol=1e-12);
            testCase.verifyEqual(inputFile.inputEvidence.releasedPvKW, ...
                data.releasedPvKW);
            testCase.verifyEqual(inputFile.inputEvidence.PVGenDC, data.pvKW);
            testCase.verifyEqual(inputFile.inputEvidence.observationMask, ...
                data.observationMask);
            testCase.verifyEqual(inputFile.inputEvidence.interpolationMask, ...
                data.interpolationMask);
            testCase.verifyEqual(inputFile.inputEvidence.cohortMask, ...
                [true, false(1, 19)]);
            testCase.verifyEqual(inputFile.inputEvidence.h4Mask, false(2, 1));
            testCase.verifyEqual(inputFile.inputEvidence.config, config);
            testCase.verifyEqual(inputFile.inputEvidence.caseMeta, caseMeta);
            testCase.verifyTrue(inputFile.inputEvidence.identity. ...
                dataContractId.available);
            testCase.verifyEqual(inputFile.inputEvidence.identity. ...
                modelContractId.value, "B2022-IR-v1");
            testCase.verifyEqual(inputFile.inputEvidence.identity. ...
                referenceManifestSha256.value, repmat("d", 1, 64));
            testCase.verifyEqual(solutionFile.solutionEvidence.solution, ...
                solution);
            testCase.verifyEqual( ...
                solutionFile.solutionEvidence.metrics.optimizedBillEUR, ...
                persistedMetrics.optimizedBillEUR);
            deprecated = ["baselineDefinition", ...
                "deprecatedBaselineAliasTarget", "baselineBillEUR", ...
                "baselinePeakImportKW", "baselineDaytimePeakImportKW", ...
                "savingsEUR", "savingsPercent"];
            testCase.verifyFalse(any(isfield( ...
                solutionFile.solutionEvidence.metrics, ...
                cellstr(deprecated))));
            metricsJson = jsondecode(fileread(artifacts.metricsPath));
            testCase.verifyFalse(any(isfield(metricsJson, ...
                cellstr(deprecated))));
            testCase.verifyEqual( ...
                solutionFile.solutionEvidence.chargePowerKW, ...
                solution.batteryChargeKW);
            testCase.verifyEqual( ...
                solutionFile.solutionEvidence.stages.allowance, 1e-7, ...
                AbsTol=1e-15);
            testCase.verifyTrue( ...
                solutionFile.solutionEvidence.provenance.availability.solver.available);
            testCase.verifyTrue( ...
                solutionFile.solutionEvidence.provenance.availability.provider.available);
        end

        function testRecordsUnavailableMasksExplicitly(testCase)
            [data, config, caseMeta, solution] = makeTrivialCase();
            data = rmfield(data, ["observationMask", "interpolationMask"]);
            metrics = evaluate_storenet(data, config, solution);
            caseDirectory = fullfile(testCase.OutputRoot, "case");

            artifacts = write_bahloul_case_artifacts(caseDirectory, data, ...
                config, caseMeta, solution, metrics);
            inputFile = load(artifacts.inputsPath, "inputEvidence");

            testCase.verifyEmpty(inputFile.inputEvidence.observationMask);
            testCase.verifyEmpty(inputFile.inputEvidence.interpolationMask);
            testCase.verifyFalse(inputFile.inputEvidence.maskAvailability. ...
                observationMask.available);
            testCase.verifyFalse(inputFile.inputEvidence.maskAvailability. ...
                interpolationMask.available);
            testCase.verifyEqual(inputFile.inputEvidence.maskAvailability. ...
                observationMask.reason, "not_provided_by_caller");
        end

        function testRejectsTamperedContentBeforeLoading(testCase)
            [data, config, caseMeta, solution] = makeTrivialCase();
            metrics = evaluate_storenet(data, config, solution);
            caseDirectory = fullfile(testCase.OutputRoot, "case");
            artifacts = write_bahloul_case_artifacts(caseDirectory, data, ...
                config, caseMeta, solution, metrics);
            appendByte(artifacts.inputsPath);

            operation = @() reevaluate_bahloul_artifact(caseDirectory);

            testCase.verifyError(operation, ...
                "StoreNet:BahloulArtifactChecksumMismatch");
        end

        function testRejectsAmbiguousContentAddressedPair(testCase)
            [data, config, caseMeta, solution] = makeTrivialCase();
            metrics = evaluate_storenet(data, config, solution);
            caseDirectory = fullfile(testCase.OutputRoot, "case");
            artifacts = write_bahloul_case_artifacts(caseDirectory, data, ...
                config, caseMeta, solution, metrics);
            duplicatePath = fullfile(caseDirectory, ...
                "inputs_" + string(repmat('0', 1, 64)) + ".mat");
            copyfile(artifacts.inputsPath, duplicatePath);

            operation = @() reevaluate_bahloul_artifact(caseDirectory);

            testCase.verifyError(operation, ...
                "StoreNet:AmbiguousBahloulArtifact");
        end

        function testAcceptsOnlyUnambiguousLegacyPair(testCase)
            [data, config, caseMeta, solution] = makeTrivialCase();
            expected = evaluate_storenet(data, config, solution);
            caseDirectory = fullfile(testCase.OutputRoot, "case");
            artifacts = write_bahloul_case_artifacts(caseDirectory, data, ...
                config, caseMeta, solution, expected);
            movefile(artifacts.inputsPath, fullfile(caseDirectory, "inputs.mat"));
            movefile(artifacts.solutionPath, ...
                fullfile(caseDirectory, "solution.mat"));

            [actual, evidence] = reevaluate_bahloul_artifact(caseDirectory);

            testCase.verifyTrue(evidence.legacyLayout);
            testCase.verifyEqual(actual.optimizedBillEUR, ...
                expected.optimizedBillEUR, AbsTol=1e-12);
            testCase.verifyEqual(strlength(evidence.inputsSha256), 64);
            testCase.verifyEqual(strlength(evidence.solutionSha256), 64);
        end

        function testRejectsMixedLegacyAndContentAddressedLayout(testCase)
            [data, config, caseMeta, solution] = makeTrivialCase();
            metrics = evaluate_storenet(data, config, solution);
            caseDirectory = fullfile(testCase.OutputRoot, "case");
            artifacts = write_bahloul_case_artifacts(caseDirectory, data, ...
                config, caseMeta, solution, metrics);
            copyfile(artifacts.inputsPath, fullfile(caseDirectory, "inputs.mat"));

            operation = @() reevaluate_bahloul_artifact(caseDirectory);

            testCase.verifyError(operation, ...
                "StoreNet:AmbiguousBahloulArtifact");
        end

        function testRefusesToOverwriteCaseDirectory(testCase)
            [data, config, caseMeta, solution] = makeTrivialCase();
            metrics = evaluate_storenet(data, config, solution);
            caseDirectory = fullfile(testCase.OutputRoot, "case");
            write_bahloul_case_artifacts(caseDirectory, data, config, ...
                caseMeta, solution, metrics);

            operation = @() write_bahloul_case_artifacts( ...
                caseDirectory, data, config, caseMeta, solution, metrics);

            testCase.verifyError(operation, ...
                "StoreNet:BahloulCaseDirectoryExists");
        end
    end
end

function [data, config, caseMeta, solution] = makeTrivialCase()
day = datetime(2020, 1, 2);
data = struct;
data.time = day + hours([1; 2]);
data.dtHours = 1;
data.houseIds = "H1";
data.loadKW = [1; 2];
data.pvKW = [0.2; 0];
data.releasedPvKW = [0.2; 0];
data.observationMask = true(2, 1);
data.interpolationMask = false(2, 1);

config = struct;
config.etaPvAC = 0.95;
config.etaPvDC = 0.95;
config.etaBatteryCharge = 0.95;
config.etaBatteryDischarge = 0.95;
config.transferLossFraction = 0.07;
config.batteryCapacityKWh = 10;
config.batteryPowerKW = 3.3;
config.socInitialFraction = 0.1;
config.socMinFraction = 0.1;
config.socMaxFraction = 0.9;
config.socTerminalFraction = 0.1;
config.constraintTolerance = 1e-8;
config.lexicographicTolerance = 1e-7;
config.nightPrice = 0.091;
config.dayPrice = 0.194;
config.dayStartHour = 10;
config.dayEndHour = 22;

caseMeta = struct;
caseMeta.scenarioId = "UNIT";
caseMeta.pairId = "UNIT_PAIR";
caseMeta.cohortId = "H20_PV10";
caseMeta.pvBoundaryId = "DC_SOURCE";
caseMeta.h4MaskAffected = false;
caseMeta.qualityMode = "short_gap_only";
caseMeta.capacityRatio = 1;
caseMeta.powerRatio = 1;
caseMeta.referenceId = "FIG5";
caseMeta.referenceHash = repmat("a", 1, 64);
caseMeta.dataContractId = "SR2020-IR-v2";
caseMeta.dataContractSha256 = repmat("b", 1, 64);
caseMeta.dataContractGitCommit = repmat("c", 1, 40);
caseMeta.modelContractId = "B2022-IR-v1";
caseMeta.modelContractSha256 = repmat("e", 1, 64);
caseMeta.referenceManifestSha256 = repmat("d", 1, 64);
caseMeta.solverProvenance = struct("name", "fixtureSolver", ...
    "version", "1");
caseMeta.dataProviderProvenance = struct("name", "fixtureProvider", ...
    "version", "1");

zeroFlow = zeros(2, 1);
solution = struct;
solution.pvToHomeKW = zeroFlow;
solution.pvToBatteryKW = zeroFlow;
solution.pvToGridKW = zeroFlow;
solution.pvCurtailKW = data.pvKW;
solution.gridToHomeKW = data.loadKW;
solution.gridToBatteryKW = zeroFlow;
solution.batteryToHomeKW = zeroFlow;
solution.batteryToGridKW = zeroFlow;
solution.socKWh = ones(3, 1);
solution.chargeOn = zeroFlow;
solution.dischargeOn = zeroFlow;
solution.batteryChargeKW = zeroFlow;
solution.batteryDischargeKW = zeroFlow;
solution.aggregateImportKW = data.loadKW;
solution.objectiveStages = struct("name", "billEUR", "value", 0.273, ...
    "solverObjective", 0.273, "exitFlag", 1, "relativeGap", 0, ...
    "message", "synthetic");
end

function name = filenameOnly(path)
[~, stem, extension] = fileparts(path);
name = string(stem) + string(extension);
end

function hash = hashFromFilename(path)
[~, stem] = fileparts(path);
parts = split(string(stem), "_");
hash = parts(end);
end

function hash = sha256FileForTest(path)
hash = storenetio.hashFile(path);
end

function appendByte(path)
fileId = fopen(path, "ab");
assert(fileId >= 0, "Test fixture could not open artifact.");
cleaner = onCleanup(@() fclose(fileId));
fwrite(fileId, uint8(0), "uint8");
clear cleaner
end

