classdef TestBahloulFrontierV1 < matlab.unittest.TestCase
    %TESTBAHLOULFRONTIERV1 Minimal numerical guards for improvement v2.
    %   Covers the two additive strategies (bill-lexicographic peak and
    %   demand charge), their offline recomputability, and the frontier
    %   runner's checkpoint/resume plumbing on a synthetic release day.

    properties
        TemporaryRoot
    end

    methods (TestClassSetup)
        function addProjectSource(testCase)
            testFolder = fileparts(mfilename("fullpath"));
            sourceFolder = fullfile(fileparts(testFolder), "src");
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                sourceFolder));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testFolder, "helpers")));
        end
    end

    methods (TestMethodSetup)
        function createTemporaryRoot(testCase)
            testCase.TemporaryRoot = string(tempname);
            mkdir(testCase.TemporaryRoot);
            testCase.addTeardown(@() rmdir(testCase.TemporaryRoot, "s"));
        end
    end

    methods (Test)
        function testPeakLexKeepsBillAndNeverRaisesPeak(testCase)
            [data, config] = makeArbitrageFixture();

            vpp = solve_storenet(data, config, "VPP_BM");
            lex = solve_storenet(data, config, "VPP_BM_PEAK_LEX");
            ps = solve_storenet(data, config, "PS");

            allowance = config.lexicographicTolerance * ...
                max(1, abs(vpp.metrics.optimizedBillEUR)) + 1e-9;
            testCase.verifyEqual(lex.metrics.optimizedBillEUR, ...
                vpp.metrics.optimizedBillEUR, AbsTol=allowance);
            testCase.verifyLessThanOrEqual(lex.metrics.peakImportKW, ...
                vpp.metrics.peakImportKW + 1e-7);
            testCase.verifyLessThan(lex.metrics.peakImportKW, ...
                vpp.metrics.peakImportKW - 0.5, ...
                "Synthetic arbitrage day must expose bill-free peak slack.");
            testCase.verifyGreaterThanOrEqual(lex.metrics.peakImportKW, ...
                ps.metrics.peakImportKW - 1e-6, ...
                "PS is the global peak floor; the bill-locked peak cannot beat it.");
            testCase.verifyEqual(string({lex.objectiveStages.name}), ...
                ["billEUR", "systemPeakKW", "batteryThroughputKWh"]);
            testCase.verifyLessThanOrEqual( ...
                lex.metrics.maximumLexicographicViolation, 1e-7);
            testCase.verifyEqual(lex.metrics.terminalSocErrorKWh, 0, AbsTol=1e-7);
            testCase.verifyEqual(lex.metrics.energyBalanceResidualKW, 0, ...
                AbsTol=1e-7);
            testCase.verifyEqual(lex.metrics.simultaneousChargeDischargeKW, 0, ...
                AbsTol=1e-7);
        end

        function testDemandChargeBracketsBillAndPeakExtremes(testCase)
            [data, config] = makeArbitrageFixture();
            vpp = solve_storenet(data, config, "VPP_BM");
            ps = solve_storenet(data, config, "PS");

            zeroConfig = config;
            zeroConfig.demandChargeEURPerKW = 0;
            zero = solve_storenet(data, zeroConfig, "VPP_BM_DEMAND_CHARGE");
            heavyConfig = config;
            heavyConfig.demandChargeEURPerKW = 1000;
            heavy = solve_storenet(data, heavyConfig, "VPP_BM_DEMAND_CHARGE");

            allowance = config.lexicographicTolerance * ...
                max(1, abs(vpp.metrics.optimizedBillEUR)) + 1e-9;
            testCase.verifyEqual(zero.metrics.optimizedBillEUR, ...
                vpp.metrics.optimizedBillEUR, AbsTol=allowance);
            testCase.verifyEqual(heavy.metrics.peakImportKW, ...
                ps.metrics.peakImportKW, AbsTol=1e-5);
            testCase.verifyEqual(string({heavy.objectiveStages.name}), ...
                ["billPlusDemandChargeEUR", "batteryThroughputKWh"]);
            testCase.verifyEqual(heavy.objectiveStages(1).finalRecomputedValue, ...
                heavy.metrics.optimizedBillEUR + ...
                1000 * heavy.metrics.peakImportKW, RelTol=1e-9);
            testCase.verifyLessThanOrEqual( ...
                heavy.metrics.maximumLexicographicViolation, 1e-7);
            testCase.verifyEqual(heavy.demandChargeEURPerKW, 1000);
        end

        function testDemandChargeIsOfflineRecomputableAndFailsClosed(testCase)
            [data, config] = makeArbitrageFixture();
            config.demandChargeEURPerKW = 0.5;
            solution = solve_storenet(data, config, "VPP_BM_DEMAND_CHARGE");

            recomputed = evaluate_storenet(data, config, solution);
            stripped = rmfield(solution, "demandChargeEURPerKW");
            failedClosed = evaluate_storenet(data, config, stripped);

            testCase.verifyLessThanOrEqual( ...
                recomputed.maximumLexicographicViolation, 1e-7);
            testCase.verifyEqual(failedClosed.maximumLexicographicViolation, Inf);
        end

        function testDemandChargeRequiresExplicitConfiguration(testCase)
            [data, config] = makeArbitrageFixture();
            invoke = @() solve_storenet(data, config, "VPP_BM_DEMAND_CHARGE");
            testCase.verifyError(invoke, "StoreNet:MissingDemandCharge");
        end

        function testRunnerCheckpointsAndResumesWithoutResolving(testCase)
            day = datetime(2020, 8, 24);
            dataRoot = fullfile(testCase.TemporaryRoot, "raw");
            makeSyntheticData(dataRoot, day, "complete");
            outputDirectory = fullfile(testCase.TemporaryRoot, "run");
            counter = SolverCallCounter();

            first = run_bahloul_frontier_v1(Dates=day, IntervalMinutes=60, ...
                DataRoot=dataRoot, OutputDirectory=outputDirectory, ...
                AnchorStrategies=["VPP_BM", "VPP_BM_PEAK_LEX"], ...
                CapRatios=[2, 1], DemandCharges=0.1, ...
                BatteryEfficiencies=[], PersistSolutions=false, ...
                Solver=@counter.solve);
            firstCalls = counter.Calls;
            second = run_bahloul_frontier_v1(Dates=day, IntervalMinutes=60, ...
                DataRoot=dataRoot, OutputDirectory=outputDirectory, ...
                AnchorStrategies=["VPP_BM", "VPP_BM_PEAK_LEX"], ...
                CapRatios=[2, 1], DemandCharges=0.1, ...
                BatteryEfficiencies=[], PersistSolutions=false, ...
                Solver=@counter.solve);

            testCase.verifyEqual(firstCalls, 5);
            testCase.verifyEqual(counter.Calls, 5, ...
                "Resume must not re-solve completed cases.");
            testCase.verifyEqual(height(first.strategyMetrics), 5);
            testCase.verifyEqual(height(second.strategyMetrics), 5);
            testCase.verifyTrue(all(first.strategyMetrics.Status == "ok"));
            testCase.verifyTrue(first.checkpoint.IsFinal);
            testCase.verifyTrue(second.checkpoint.IsFinal);
            capRows = first.strategyMetrics(first.strategyMetrics.CaseKind == ...
                "frontier", :);
            testCase.verifyEqual(capRows.CapKW, ...
                capRows.CapRatio .* capRows.PvSelfNoBatteryPeakKW, RelTol=1e-12);
            testCase.verifyTrue(all(capRows.AllDayPeakKW <= capRows.CapKW + 1e-6));
            testCase.verifyTrue(isfile(fullfile(outputDirectory, ...
                "strategy_metrics.csv")));
            testCase.verifyTrue(isfile(fullfile(outputDirectory, "profiles.csv")));
            testCase.verifyTrue(isfile(fullfile(outputDirectory, "manifest.json")));
        end
    end
end

function [data, config] = makeArbitrageFixture()
% Three homes, hourly, flat night load and a higher daytime load with an
% evening spike; one home has midday PV. Batteries can only lower the bill by
% charging at night, which creates the synchronised-charging peak that the
% bill-lexicographic peak stage must be able to spread at zero cost.
config = storenet_config(IntervalMinutes=60, QualityMode="release_literal");
config.maxSolverTimeSeconds = 60;
day = datetime(2020, 8, 24);
time = (day + hours(1):hours(1):day + hours(24)).';
intervalStartHour = hour(time - hours(1));
dayMask = intervalStartHour >= config.dayStartHour & ...
    intervalStartHour < config.dayEndHour;
houseIds = ["H1", "H2", "H3"];
loadKW = ones(numel(time), numel(houseIds));
loadKW(dayMask, :) = 2.0;
loadKW(intervalStartHour == 18, 1) = 6.0;
pvKW = zeros(numel(time), numel(houseIds));
pvKW(intervalStartHour >= 11 & intervalStartHour < 15, 1) = 2.0;
data = struct;
data.day = day;
data.time = time;
data.loadKW = loadKW;
data.pvKW = pvKW;
data.dtHours = 1;
data.houseIds = houseIds;
end
