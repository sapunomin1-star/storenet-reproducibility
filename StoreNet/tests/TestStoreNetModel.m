classdef TestStoreNetModel < matlab.unittest.TestCase
    %TESTSTORENETMODEL Contract tests for the StoreNet optimization API.

    properties
        Config
        Data
    end

    methods (TestClassSetup)
        function addSourceFolder(~)
            testFolder = fileparts(mfilename("fullpath"));
            addpath(fullfile(fileparts(testFolder), "src"));
        end
    end

    methods (TestMethodSetup)
        function createFixtures(testCase)
            testCase.Config = makeTestConfig();
            testCase.Data = makeSharingData();
        end
    end

    methods (Test)
        function testVppSharingReducesBillWithoutBattery(testCase)
            config = testCase.Config;
            config.batteryPowerKW = 0;

            shSolution = solve_storenet(testCase.Data, config, "SH_BM");
            vppSolution = solve_storenet(testCase.Data, config, "VPP_BM");

            testCase.verifyLessThan(vppSolution.metrics.optimizedBillEUR, ...
                shSolution.metrics.optimizedBillEUR);
            testCase.verifyEqual(shSolution.metrics.totalSharedExportKWh, 0, ...
                "AbsTol", 1e-8);
            testCase.verifyGreaterThan(vppSolution.metrics.totalSharedExportKWh, 0);
        end

        function testBatteryHonorsDynamicsTerminalAndMutualExclusion(testCase)
            data = makeArbitrageData();

            solution = solve_storenet(data, testCase.Config, "VPP_BM");

            testCase.verifyEqual(solution.metrics.terminalSocErrorKWh, 0, ...
                "AbsTol", 1e-7);
            testCase.verifyEqual(solution.metrics.energyBalanceResidualKW, 0, ...
                "AbsTol", 1e-7);
            testCase.verifyEqual( ...
                solution.metrics.simultaneousChargeDischargeKW, 0, ...
                "AbsTol", 1e-7);
            testCase.verifyLessThan(solution.metrics.optimizedBillEUR, ...
                solution.metrics.baselineBillEUR);
        end

        function testFivePublishedStrategiesSolveFeasibly(testCase)
            config = testCase.Config;
            config.batteryPowerKW = 0;
            names = {"SH_BM", "VPP_BM", "PS", "PSDT", "LL"};

            solutions = cellfun(@(name) solve_storenet( ...
                testCase.Data, config, name), names, "UniformOutput", false);
            minimumExitFlags = cellfun(@(value) min(value.exitFlags), solutions);
            residuals = cellfun(@(value) ...
                value.metrics.energyBalanceResidualKW, solutions);
            stageCounts = cellfun(@(value) ...
                numel(value.objectiveStages), solutions);
            tolerance = config.lexicographicTolerance + ...
                config.constraintTolerance;

            testCase.verifyGreaterThan(min(minimumExitFlags), 0);
            testCase.verifyEqual(residuals, zeros(size(residuals)), ...
                "AbsTol", 1e-7);
            testCase.verifyEqual(stageCounts, [2, 2, 3, 3, 3]);
            testCase.verifyLessThanOrEqual(solutions{3}.metrics.peakImportKW, ...
                solutions{3}.objectiveStages(1).value + tolerance);
            testCase.verifyLessThanOrEqual( ...
                solutions{4}.metrics.daytimePeakImportKW, ...
                solutions{4}.objectiveStages(1).value + tolerance);
            testCase.verifyLessThanOrEqual(solutions{5}.metrics.importSpreadKW, ...
                solutions{5}.objectiveStages(1).value + tolerance);
            for solutionIndex = 1:numel(solutions)
                stages = solutions{solutionIndex}.objectiveStages;
                testCase.verifyTrue(isfield(stages, "allowance") && ...
                    isfield(stages, "lockedInLaterStage") && ...
                    isfield(stages, "finalRecomputedValue"));
                testCase.verifyTrue(all(isfinite( ...
                    [stages.finalRecomputedValue])));
                testCase.verifyLessThanOrEqual( ...
                    solutions{solutionIndex}.metrics. ...
                    maximumLexicographicViolation, 1e-7);
                locked = [stages.lockedInLaterStage];
                testCase.verifyTrue(all(isfinite([stages(locked).allowance])));
            end
        end

        function testImprovedPeakGuardEnforcesConfiguredCap(testCase)
            data = makePeakGuardData();
            config = testCase.Config;
            config.aggregateImportCapKW = 3;

            solution = solve_storenet(data, config, "IMPROVED_PEAK_GUARD");

            testCase.verifyLessThanOrEqual(solution.metrics.peakImportKW, ...
                config.aggregateImportCapKW + 1e-7);
            testCase.verifyEqual(solution.metrics.terminalSocErrorKWh, 0, ...
                "AbsTol", 1e-7);
            testCase.verifyEqual(numel(solution.objectiveStages), 2);
            testCase.verifyTrue(isfinite(solution.metrics.baselinePeakImportKW));
            testCase.verifyTrue(isfinite( ...
                solution.metrics.baselineDaytimePeakImportKW));
        end

        function testEvaluateDetectsAlteredTerminalState(testCase)
            config = testCase.Config;
            config.batteryPowerKW = 0;
            solution = solve_storenet(testCase.Data, config, "VPP_BM");
            solution.socKWh(end, 1) = solution.socKWh(end, 1) + 0.25;

            metrics = evaluate_storenet(testCase.Data, config, solution);

            testCase.verifyEqual(metrics.terminalSocErrorKWh, 0.25, ...
                "AbsTol", 1e-12);
            testCase.verifyGreaterThan(metrics.energyBalanceResidualKW, 0);
        end

        function testEvaluateDetectsAlteredPackagedCharge(testCase)
            config = testCase.Config;
            config.batteryPowerKW = 0;
            solution = solve_storenet(testCase.Data, config, "VPP_BM");
            solution.batteryChargeKW(1, 1) = ...
                solution.batteryChargeKW(1, 1) + 0.25;

            metrics = evaluate_storenet(testCase.Data, config, solution);

            testCase.verifyEqual(metrics.chargeConversionResidualKW, 0.25, ...
                "AbsTol", 1e-12);
            testCase.verifyEqual(metrics.batteryDynamicsResidualKW, 0, ...
                "AbsTol", 1e-8);
            testCase.verifyEqual(metrics.energyBalanceResidualKW, 0.25, ...
                "AbsTol", 1e-12);
        end

        function testIntervalEndTariffBoundaries(testCase)
            data = makeTariffBoundaryData();
            config = testCase.Config;
            config.batteryPowerKW = 0;

            solution = solve_storenet(data, config, "SH_BM");
            boundaryPrices = solution.pricePerKWh([1, 2, 25, 26]);

            testCase.verifyEqual(boundaryPrices, ...
                [config.nightPrice; config.dayPrice; ...
                config.dayPrice; config.nightPrice], "AbsTol", 1e-12);
        end

        function testNonuniformAndNonincreasingTimeAreRejected(testCase)
            nonuniformData = testCase.Data;
            nonuniformData.time(3) = nonuniformData.time(3) + minutes(1);
            nonincreasingData = testCase.Data;
            nonincreasingData.time(3) = nonincreasingData.time(2);

            testCase.verifyError(@() solve_storenet(nonuniformData, ...
                testCase.Config, "VPP_BM"), "StoreNet:InvalidData");
            testCase.verifyError(@() solve_storenet(nonincreasingData, ...
                testCase.Config, "VPP_BM"), "StoreNet:InvalidData");
        end

        function testNegativeLoadIsRejected(testCase)
            badData = testCase.Data;
            badData.loadKW(1, 1) = -1;

            testCase.verifyError(@() solve_storenet( ...
                badData, testCase.Config, "VPP_BM"), "StoreNet:InvalidData");
        end
    end
end

function config = makeTestConfig()
config = struct;
config.batteryCapacityKWh = 10;
config.batteryPowerKW = 3.3;
config.socInitialFraction = 0.1;
config.socMinFraction = 0.1;
config.socMaxFraction = 0.9;
config.etaPvAC = 0.95;
config.etaPvDC = 0.95;
config.etaBatteryCharge = 0.95;
config.etaBatteryDischarge = 0.95;
config.transferLossFraction = 0.07;
config.dayStartHour = 10;
config.dayEndHour = 22;
config.nightPrice = 0.091;
config.dayPrice = 0.194;
config.mipRelativeGap = 1e-8;
config.constraintTolerance = 1e-8;
config.lexicographicTolerance = 1e-7;
config.throughputWeight = 1;
end

function data = makeSharingData()
data = struct;
data.time = datetime(2020, 1, 1, 9, 30, 0) + minutes((0:30:90).');
data.loadKW = [0, 1; 0, 1; 0, 3; 0, 3];
data.pvKW = [0, 0; 0, 0; 4, 0; 4, 0];
data.dtHours = 0.5;
data.houseIds = ["H1", "H2"];
end

function data = makeArbitrageData()
data = struct;
data.time = datetime(2020, 1, 1, 9, 30, 0) + minutes((0:30:90).');
data.loadKW = [0; 0; 2; 2];
data.pvKW = zeros(4, 1);
data.dtHours = 0.5;
data.houseIds = "H1";
end

function data = makePeakGuardData()
data = struct;
data.time = datetime(2020, 1, 1, 9, 30, 0) + minutes((0:30:90).');
data.loadKW = [0; 0; 4; 4];
data.pvKW = zeros(4, 1);
data.dtHours = 0.5;
data.houseIds = "H1";
end

function data = makeTariffBoundaryData()
data = struct;
data.time = datetime(2020, 1, 1, 10, 0, 0) + minutes((0:30:750).');
data.loadKW = zeros(numel(data.time), 1);
data.pvKW = zeros(numel(data.time), 1);
data.dtHours = 0.5;
data.houseIds = "H1";
end
