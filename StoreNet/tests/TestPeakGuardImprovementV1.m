classdef TestPeakGuardImprovementV1 < matlab.unittest.TestCase
    %TESTPEAKGUARDIMPROVEMENTV1 Minimal numerical guards for the comparison.

    properties
        TemporaryRoot
    end

    methods (TestClassSetup)
        function addProjectSource(testCase)
            testFolder = fileparts(mfilename("fullpath"));
            sourceFolder = fullfile(fileparts(testFolder), "src");
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                sourceFolder));
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
        function testPairKeepsPaperAndEngineeringSavingsSeparate(testCase)
            metrics = syntheticPairMetrics();

            comparison = make_peak_guard_pair_comparison(metrics);

            testCase.verifyEqual(comparison.BillPenaltyEUR, 1, ...
                AbsTol=1e-12);
            testCase.verifyEqual( ...
                comparison.PaperSavingsSacrificePercentagePoints, 5, ...
                AbsTol=1e-12);
            testCase.verifyEqual( ...
                comparison.EngineeringSavingsSacrificePercentagePoints, 10, ...
                AbsTol=1e-12);
            testCase.verifyEqual(comparison.PeakReductionKW, 12, ...
                AbsTol=1e-12);
            testCase.verifyTrue(comparison.VppCreatesNewPeak);
            testCase.verifyTrue(comparison.PeakGuardCapSatisfied);
        end

        function testMonthlyRunnerSolvesOnlyFrozenPeakGuard(testCase)
            fixture = writeMonthlyFixture(testCase.TemporaryRoot, false);

            run = run_bahloul_peak_guard_monthly_v1( ...
                Dates=fixture.day, ...
                FormalDailyMetricsPath=fixture.formalDailyPath, ...
                FormalSourceMetricsPath=fixture.formalSourcePath, ...
                FormalSourceManifestPath=fixture.formalManifestPath, ...
                DataRoot=testCase.TemporaryRoot, ...
                OutputDirectory=fixture.outputDirectory, ...
                DataProvider=@peakGuardDataProvider, ...
                Solver=@peakGuardOnlySolver, PersistSolutions=false);

            guard = run.strategyMetrics.Strategy == ...
                "IMPROVED_PEAK_GUARD";
            testCase.verifyEqual(nnz(guard), 1);
            testCase.verifyEqual(run.strategyMetrics.PeakGuardCapKW(guard), ...
                fixture.capKW, AbsTol=1e-12);
            testCase.verifyEqual(run.strategyMetrics.Status(guard), "ok");
            testCase.verifyEqual(run.checkpoint.CompletedPeakGuardRows, 1);
            testCase.verifyEqual(run.checkpoint.ExpectedPeakGuardRows, 1);
            testCase.verifyTrue(run.checkpoint.IsFinal);
            testCase.verifyTrue(run.formalVppWasReusedWithoutSolve);
        end

        function testBaselineMismatchStopsBeforeSolver(testCase)
            fixture = writeMonthlyFixture(testCase.TemporaryRoot, true);
            invoke = @() run_bahloul_peak_guard_monthly_v1( ...
                Dates=fixture.day, ...
                FormalDailyMetricsPath=fixture.formalDailyPath, ...
                FormalSourceMetricsPath=fixture.formalSourcePath, ...
                FormalSourceManifestPath=fixture.formalManifestPath, ...
                DataRoot=testCase.TemporaryRoot, ...
                OutputDirectory=fixture.outputDirectory, ...
                DataProvider=@peakGuardDataProvider, ...
                Solver=@solverMustNotBeCalled, PersistSolutions=false);

            testCase.verifyError(invoke, ...
                "StoreNet:PeakGuardMonthlyIncomplete");
            checkpoint = readtable(fullfile(fixture.outputDirectory, ...
                "strategy_metrics.csv"), TextType="string");
            failed = checkpoint.Strategy == "IMPROVED_PEAK_GUARD";
            testCase.verifyEqual(checkpoint.ErrorIdentifier(failed), ...
                "StoreNet:FormalBaselineMismatch");
        end
    end
end

function metrics = syntheticPairMetrics()
dataset = ["synthetic"; "synthetic"];
day = repmat(datetime(2020, 8, 24), 2, 1);
strategy = ["VPP_BM"; "IMPROVED_PEAK_GUARD"];
status = ["ok"; "ok"];
peakGuardCapKW = [8; 8];
paperSavingsPercent = [50; 45];
engineeringSavingsPercent = [40; 30];
optimizedBillEUR = [10; 11];
allDayPeakKW = [20; 8];
daytimePeakKW = [2; 3];
loadRangeKW = [20; 8];
totalGridImportKWh = [100; 99];
batteryThroughputKWh = [80; 70];
pvCurtailmentKWh = [0; 0];
energyBalanceResidualKW = [1e-12; 2e-12];
terminalSocErrorKWh = [0; 0];
simultaneousChargeDischargeKW = [0; 0];
metrics = table(dataset, day, strategy, status, peakGuardCapKW, ...
    paperSavingsPercent, engineeringSavingsPercent, optimizedBillEUR, ...
    allDayPeakKW, daytimePeakKW, loadRangeKW, totalGridImportKWh, ...
    batteryThroughputKWh, pvCurtailmentKWh, energyBalanceResidualKW, ...
    terminalSocErrorKWh, simultaneousChargeDischargeKW, ...
    VariableNames=["Dataset", "Day", "Strategy", "Status", ...
    "PeakGuardCapKW", "PaperSavingsPercent", ...
    "EngineeringSavingsPercent", "OptimizedBillEUR", "AllDayPeakKW", ...
    "DaytimePeakKW", "LoadRangeKW", "TotalGridImportKWh", ...
    "BatteryThroughputKWh", "PvCurtailmentKWh", ...
    "EnergyBalanceResidualKW", "TerminalSocErrorKWh", ...
    "SimultaneousChargeDischargeKW"]);
end

function fixture = writeMonthlyFixture(root, perturbCap)
day = datetime(2020, 8, 24);
data = makeMonthlyData(day);
config = storenet_config(IntervalMinutes=60, DataRoot=root, ...
    QualityMode="release_literal");
config.maxSolverTimeSeconds = 60;
solution = noBatterySolution(data, config);
metrics = evaluate_storenet(data, config, solution);
capKW = metrics.PvSelfNoBatteryBaseline.peakImportKW;
formalCapKW = capKW + double(perturbCap);

row = struct;
row.Day = day;
row.ScenarioId = "DC_XI007_H20";
row.CohortId = "H20_PV10";
row.IsPrimary = true;
row.PvBoundaryId = "DC_SOURCE";
row.TransferLossFraction = 0.07;
row.QualityMode = "release_literal";
row.Strategy = "VPP_BM";
row.Status = "ok";
row.HouseCount = 20;
row.PvHomeCount = 10;
row.PaperLoadOnlyBaselineBillEUR = metrics.PaperLoadOnlyBaseline.billEUR;
row.PaperLoadOnlySavingsPercent = ...
    metrics.PaperLoadOnlyBaseline.savingsPercent;
row.PaperLoadOnlyPeakKW = metrics.PaperLoadOnlyBaseline.peakImportKW;
row.PaperLoadOnlyDaytimePeakKW = ...
    metrics.PaperLoadOnlyBaseline.daytimePeakImportKW;
row.PvSelfNoBatteryBaselineBillEUR = ...
    metrics.PvSelfNoBatteryBaseline.billEUR;
row.PvSelfNoBatterySavingsPercent = ...
    metrics.PvSelfNoBatteryBaseline.savingsPercent;
row.PvSelfNoBatteryPeakKW = formalCapKW;
row.PvSelfNoBatteryDaytimePeakKW = ...
    metrics.PvSelfNoBatteryBaseline.daytimePeakImportKW;
row.OptimizedBillEUR = metrics.optimizedBillEUR;
row.OutcomePeakImportKW = metrics.peakImportKW;
row.OutcomeDaytimePeakImportKW = metrics.daytimePeakImportKW;
row.TotalGridImportKWh = metrics.totalGridImportKWh;
row.TotalBatteryThroughputKWh = metrics.totalBatteryThroughputKWh;
row.TotalCurtailedPvKWh = NaN;
row.EnergyBalanceResidualKW = metrics.energyBalanceResidualKW;
row.TerminalSocErrorKWh = metrics.terminalSocErrorKWh;
row.SimultaneousChargeDischargeKW = ...
    metrics.simultaneousChargeDischargeKW;
row.MinimumExitFlag = 1;
formalDaily = struct2table(row);
formalDailyPath = string(fullfile(root, "formal_daily.csv"));
writetable(formalDaily, formalDailyPath);

formalSource = table(day, "VPP_BM", metrics.importSpreadKW, ...
    VariableNames=["Day", "Strategy", "ImportSpreadKW"]);
formalSourcePath = string(fullfile(root, "formal_source.csv"));
writetable(formalSource, formalSourcePath);

manifest = struct;
manifest.experiment = struct("qualityMode", "release_literal", ...
    "intervalMinutes", 60, "configuration", config);
formalManifestPath = string(fullfile(root, "formal_manifest.json"));
writelines(string(jsonencode(manifest)), formalManifestPath);

fixture = struct;
fixture.day = day;
fixture.capKW = capKW;
fixture.formalDailyPath = formalDailyPath;
fixture.formalSourcePath = formalSourcePath;
fixture.formalManifestPath = formalManifestPath;
fixture.outputDirectory = string(fullfile(root, "output"));
end

function [data, meta] = peakGuardDataProvider(day, options)
arguments
    day (1, 1) datetime
    options.DataRoot (1, 1) string = ""
    options.IntervalMinutes (1, 1) double = 60
    options.QualityMode (1, 1) string = "release_literal"
end
data = makeMonthlyData(day);
meta = struct("qualityPassed", true, "qualityMode", options.QualityMode);
end

function data = makeMonthlyData(day)
day = dateshift(day, "start", "day");
houseIds = compose("H%d", 1:20);
pvHomeNumbers = [1, 2, 3, 4, 5, 7, 10, 11, 13, 17];
pvHomeMask = ismember(1:20, pvHomeNumbers);
loadKW = ones(24, 20);
pvKW = zeros(24, 20);
pvKW(11:16, pvHomeMask) = 0.5;
data = struct;
data.day = day;
data.time = day + hours((1:24).');
data.timeEnd = data.time;
data.dtHours = 1;
data.intervalMinutes = 60;
data.houseIds = houseIds;
data.homeNames = houseIds;
data.pvHomeMask = pvHomeMask;
data.loadKW = loadKW;
data.pvKW = pvKW;
data.loadKWh = loadKW;
data.pvKWh = pvKW;
end

function [solution, metrics] = peakGuardOnlySolver(data, config, strategy)
if strategy ~= "IMPROVED_PEAK_GUARD"
    error("StoreNet:UnexpectedStrategySolve", ...
        "Only IMPROVED_PEAK_GUARD may be solved.");
end
solution = noBatterySolution(data, config);
expectedCapKW = max(solution.aggregateImportKW);
if abs(double(config.aggregateImportCapKW) - expectedCapKW) > 1e-12
    error("StoreNet:SyntheticCapMismatch", ...
        "Runner did not pass the PV-self/no-battery peak cap.");
end
metrics = evaluate_storenet(data, config, solution);
end

function [solution, metrics] = solverMustNotBeCalled(varargin)
solution = struct;
metrics = struct;
throwUnexpectedSolverCall();
end

function throwUnexpectedSolverCall()
error("StoreNet:SolverShouldNotBeCalled", ...
    "Baseline mismatch must stop before invoking a solver.");
end

function solution = noBatterySolution(data, config)
loadKW = double(data.loadKW);
pvKW = double(data.pvKW);
pvToHomeKW = min(loadKW, config.etaPvAC .* pvKW);
zerosKW = zeros(size(loadKW));
solution = struct;
solution.pvToHomeKW = pvToHomeKW;
solution.pvToBatteryKW = zerosKW;
solution.pvToGridKW = zerosKW;
solution.pvCurtailKW = pvKW - pvToHomeKW ./ config.etaPvAC;
solution.gridToHomeKW = loadKW - pvToHomeKW;
solution.gridToBatteryKW = zerosKW;
solution.batteryToHomeKW = zerosKW;
solution.batteryToGridKW = zerosKW;
solution.socKWh = repmat(config.socInitialFraction .* ...
    config.batteryCapacityKWh, size(loadKW, 1) + 1, size(loadKW, 2));
solution.batteryChargeKW = zerosKW;
solution.batteryDischargeKW = zerosKW;
solution.aggregateImportKW = sum(solution.gridToHomeKW, 2);
solution.chargeOn = zerosKW;
solution.dischargeOn = zerosKW;
solution.exitFlags = [1; 1];
solution.objectiveStages = struct.empty(0, 1);
solution.solverOutputs = cell(0, 1);
end
