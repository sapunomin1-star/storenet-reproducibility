classdef TestBahloulBaselines < matlab.unittest.TestCase
    %TESTBAHLOULBASELINES Contract tests for the two Bahloul bill baselines.

    methods (TestClassSetup)
        function addSourceFolder(testCase)
            testFolder = fileparts(mfilename("fullpath"));
            sourceFolder = fullfile(fileparts(testFolder), "src");
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                sourceFolder));
        end
    end

    methods (Test)
        function testKnownDualBaselineValues(testCase)
            time = [datetime(2020, 1, 1, 9, 0, 0); ...
                datetime(2020, 1, 1, 9, 30, 0)];
            loadKW = [2, 1; 4, 1];
            pvKW = [2, 0; 4, 2];
            [data, config, solution] = makeNoBatteryCase(time, loadKW, pvKW);

            metrics = evaluate_storenet(data, config, solution);

            testCase.verifyEqual(metrics.PaperLoadOnlyBaseline.billEUR, ...
                0.4, AbsTol=1e-12);
            testCase.verifyEqual(metrics.PaperLoadOnlyBaseline.savingsEUR, ...
                0.2, AbsTol=1e-12);
            testCase.verifyEqual(metrics.PaperLoadOnlyBaseline.savingsPercent, ...
                50, AbsTol=1e-12);
            testCase.verifyEqual(metrics.PaperLoadOnlyBaseline.peakImportKW, ...
                5, AbsTol=1e-12);
            testCase.verifyTrue(isnan( ...
                metrics.PaperLoadOnlyBaseline.daytimePeakImportKW));
            testCase.verifyEqual(metrics.PvSelfNoBatteryBaseline.billEUR, ...
                0.2, AbsTol=1e-12);
            testCase.verifyEqual(metrics.PvSelfNoBatteryBaseline.savingsEUR, ...
                0, AbsTol=1e-12);
            testCase.verifyEqual(metrics.PvSelfNoBatteryBaseline.savingsPercent, ...
                0, AbsTol=1e-12);
            testCase.verifyEqual(metrics.PvSelfNoBatteryBaseline.peakImportKW, ...
                2, AbsTol=1e-12);
        end

        function testTariffUsesIntervalStartAtTen(testCase)
            time = [datetime(2020, 1, 1, 10, 0, 0); ...
                datetime(2020, 1, 1, 10, 30, 0)];
            loadKW = [2; 2];
            pvKW = zeros(2, 1);
            [data, config, solution] = makeNoBatteryCase(time, loadKW, pvKW);

            metrics = evaluate_storenet(data, config, solution);

            testCase.verifyEqual(metrics.PaperLoadOnlyBaseline.billEUR, ...
                0.3, AbsTol=1e-12);
            testCase.verifyEqual(metrics.PvSelfNoBatteryBaseline.billEUR, ...
                0.3, AbsTol=1e-12);
            testCase.verifyEqual( ...
                metrics.PaperLoadOnlyBaseline.daytimePeakImportKW, ...
                2, AbsTol=1e-12);
        end

        function testZeroDenominatorsReturnNaN(testCase)
            time = datetime(2020, 1, 1, 12, 0, 0);
            loadKW = zeros(1, 2);
            pvKW = [2, 0];
            [data, config, solution] = makeNoBatteryCase(time, loadKW, pvKW);

            metrics = evaluate_storenet(data, config, solution);

            testCase.verifyEqual(metrics.PaperLoadOnlyBaseline.billEUR, ...
                0, AbsTol=1e-12);
            testCase.verifyEqual(metrics.PaperLoadOnlyBaseline.savingsEUR, ...
                0, AbsTol=1e-12);
            testCase.verifyTrue(isnan( ...
                metrics.PaperLoadOnlyBaseline.savingsPercent));
            testCase.verifyTrue(metrics.PaperLoadOnlyBaseline. ...
                savingsPercentDenominatorIsZero);
            testCase.verifyEqual(metrics.PvSelfNoBatteryBaseline.billEUR, ...
                0, AbsTol=1e-12);
            testCase.verifyEqual(metrics.PvSelfNoBatteryBaseline.savingsEUR, ...
                0, AbsTol=1e-12);
            testCase.verifyTrue(isnan( ...
                metrics.PvSelfNoBatteryBaseline.savingsPercent));
            testCase.verifyTrue(metrics.PvSelfNoBatteryBaseline. ...
                savingsPercentDenominatorIsZero);
        end

        function testPvSelfBaselineClipsExcessPvAtZeroImport(testCase)
            time = datetime(2020, 1, 1, 12, 0, 0);
            loadKW = [1, 1];
            pvKW = [10, 0];
            [data, config, solution] = makeNoBatteryCase(time, loadKW, pvKW);

            metrics = evaluate_storenet(data, config, solution);

            testCase.verifyEqual(metrics.PaperLoadOnlyBaseline.billEUR, ...
                0.2, AbsTol=1e-12);
            testCase.verifyEqual(metrics.PaperLoadOnlyBaseline.peakImportKW, ...
                2, AbsTol=1e-12);
            testCase.verifyEqual(metrics.PvSelfNoBatteryBaseline.billEUR, ...
                0.1, AbsTol=1e-12);
            testCase.verifyEqual(metrics.PvSelfNoBatteryBaseline.peakImportKW, ...
                1, AbsTol=1e-12);
            testCase.verifyGreaterThanOrEqual( ...
                metrics.PvSelfNoBatteryBaseline.billEUR, 0);
        end

        function testDeprecatedAliasesTargetPvSelfBaseline(testCase)
            time = datetime(2020, 1, 1, 12, 0, 0);
            loadKW = [2, 1];
            pvKW = [2, 0];
            [data, config, solution] = makeNoBatteryCase(time, loadKW, pvKW);

            metrics = evaluate_storenet(data, config, solution);

            testCase.verifyEqual(metrics.deprecatedBaselineAliasTarget, ...
                "PvSelfNoBatteryBaseline");
            testCase.verifyThat(metrics.baselineDefinition, ...
                matlab.unittest.constraints.ContainsSubstring("DEPRECATED"));
            testCase.verifyEqual(metrics.baselineBillEUR, ...
                metrics.PvSelfNoBatteryBaseline.billEUR, AbsTol=1e-12);
            testCase.verifyEqual(metrics.baselinePeakImportKW, ...
                metrics.PvSelfNoBatteryBaseline.peakImportKW, AbsTol=1e-12);
            testCase.verifyEqual(metrics.baselineDaytimePeakImportKW, ...
                metrics.PvSelfNoBatteryBaseline.daytimePeakImportKW, ...
                AbsTol=1e-12);
            testCase.verifyEqual(metrics.savingsEUR, ...
                metrics.PvSelfNoBatteryBaseline.savingsEUR, AbsTol=1e-12);
            testCase.verifyEqual(metrics.savingsPercent, ...
                metrics.PvSelfNoBatteryBaseline.savingsPercent, AbsTol=1e-12);
        end
    end
end

function [data, config, solution] = makeNoBatteryCase(time, loadKW, pvKW)
config = makeConfig;
data = struct;
data.time = time(:);
data.loadKW = double(loadKW);
data.pvKW = double(pvKW);
data.dtHours = 0.5;

pvToHomeKW = min(data.loadKW, config.etaPvAC .* data.pvKW);
pvCurtailKW = data.pvKW - pvToHomeKW ./ config.etaPvAC;
gridToHomeKW = data.loadKW - pvToHomeKW;
[intervalCount, houseCount] = size(data.loadKW);
zeroFlow = zeros(intervalCount, houseCount);
initialEnergyKWh = config.socInitialFraction * config.batteryCapacityKWh;

solution = struct;
solution.pvToHomeKW = pvToHomeKW;
solution.pvToBatteryKW = zeroFlow;
solution.pvToGridKW = zeroFlow;
solution.pvCurtailKW = pvCurtailKW;
solution.gridToHomeKW = gridToHomeKW;
solution.gridToBatteryKW = zeroFlow;
solution.batteryToHomeKW = zeroFlow;
solution.batteryToGridKW = zeroFlow;
solution.socKWh = initialEnergyKWh .* ones(intervalCount + 1, houseCount);
solution.batteryChargeKW = zeroFlow;
solution.batteryDischargeKW = zeroFlow;
solution.aggregateImportKW = sum(gridToHomeKW, 2);
end

function config = makeConfig
config = struct;
config.etaPvAC = 0.5;
config.etaPvDC = 0.5;
config.etaBatteryCharge = 0.95;
config.etaBatteryDischarge = 0.95;
config.transferLossFraction = 0.07;
config.batteryCapacityKWh = 10;
config.batteryPowerKW = 3.3;
config.socInitialFraction = 0.1;
config.socMinFraction = 0.1;
config.socMaxFraction = 0.9;
config.socTerminalFraction = 0.1;
config.nightPrice = 0.1;
config.dayPrice = 0.2;
config.dayStartHour = 10;
config.dayEndHour = 22;
config.constraintTolerance = 1e-8;
end
