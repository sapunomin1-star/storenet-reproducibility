classdef TestStoreNetExperiments < matlab.unittest.TestCase
    %TESTSTORENETEXPERIMENTS Fast contract tests for experiment orchestration.

    properties
        OutputRoot
        ReferenceFile
    end

    methods (TestClassSetup)
        function addProjectFolders(testCase)
            testFolder = fileparts(mfilename("fullpath"));
            sourceFolder = fullfile(fileparts(testFolder), "src");
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                sourceFolder));
        end
    end

    methods (TestMethodSetup)
        function createTemporaryWorkspace(testCase)
            testCase.OutputRoot = string(tempname);
            mkdir(testCase.OutputRoot);
            testCase.addTeardown(@() rmdir(testCase.OutputRoot, "s"));
            testCase.ReferenceFile = fullfile(testCase.OutputRoot, ...
                "figure5_reference.csv");
            writeSyntheticReference(testCase.ReferenceFile);
        end
    end

    methods (Test)
        function testTypicalDayRanksBeforeQualityGate(testCase)
            candidates = datetime(2020, 1, 1:3);

            [selectedDay, ranking] = select_typical_day( ...
                CandidateDates=candidates, ...
                ReferenceFile=testCase.ReferenceFile, ...
                QualityMode="exclude_flagged_pv", ...
                DataProvider=@experimentDataProvider);

            testCase.verifyEqual(selectedDay, datetime(2020, 1, 2));
            testCase.verifyEqual(ranking.Score, [0; 0.1; 0.2], ...
                AbsTol=1e-12);
            testCase.verifyEqual(ranking.QualityStatus, ...
                ["quality_rejected"; "passed"; "passed"]);
            testCase.verifyEqual(ranking.Selected, [false; true; false]);
            testCase.verifyThat(ranking.QualityMessage(1), ...
                matlab.unittest.constraints.ContainsSubstring( ...
                "synthetic canonical rejection"));
        end

        function testTypicalRunWritesBaselinesThenImprovement(testCase)
            run = run_typical_day(datetime(2020, 1, 2), ...
                OutputRoot=testCase.OutputRoot, RunId="typical_unit", ...
                QualityMode="exclude_flagged_pv", ...
                DataProvider=@experimentDataProvider, ...
                Solver=@experimentSolver, FigureVisible=false);

            testCase.verifyEqual(run.metricsTable.Strategy, ...
                ["SH_BM"; "VPP_BM"; "PS"; "PSDT"; "LL"; ...
                "IMPROVED_PEAK_GUARD"]);
            testCase.verifyEqual(run.metricsTable.Phase, ...
                [repmat("baseline", 5, 1); "improvement"]);
            testCase.verifyEqual(run.metricsTable.Status, repmat("ok", 6, 1));
            testCase.verifyEqual(run.metricsTable.ImportCapKW(end), 7.25, ...
                AbsTol=1e-12);
            testCase.verifyEqual(run.metricsTable.BaselineBillEUR, ...
                25 .* ones(6, 1), AbsTol=1e-12);
            testCase.verifyEqual(run.metricsTable.BaselinePeakImportKW, ...
                9.5 .* ones(6, 1), AbsTol=1e-12);
            testCase.verifyEqual(run.metricsTable.SavingsPercent(1), ...
                100 .* (25 - 19.75) ./ 25, AbsTol=1e-12);
            testCase.verifyLessThanOrEqual( ...
                run.metricsTable.PeakImportKW(end), 7.25 + 1e-12);
            testCase.verifyTrue(isfile(run.metricsPath));
            testCase.verifyTrue(isfile(run.profilesPath));
            testCase.verifyTrue(isfile(run.figurePath));
            testCase.verifyTrue(isfile(run.manifestPath));
            testCase.verifyEqual(run.manifest.experiment.improvementCapKW, ...
                7.25, AbsTol=1e-12);
            testCase.verifyTrue( ...
                run.manifest.experiment.improvementExecutedAfterBaselines);
        end

        function testMonthlyRetainsCanonicalFalseAsStatusRows(testCase)
            sampleDates = datetime(2020, 1, 1:2);

            run = run_monthly(Dates=sampleDates, ...
                OutputRoot=testCase.OutputRoot, RunId="monthly_unit", ...
                QualityMode="short_gap_only", ...
                DataProvider=@experimentDataProvider, ...
                Solver=@experimentSolver);

            rejectedRows = run.metricsTable.Day == datetime(2020, 1, 1);
            passingRows = run.metricsTable.Day == datetime(2020, 1, 2);
            testCase.verifyEqual(height(run.metricsTable), 10);
            testCase.verifyEqual(run.metricsTable.Status(rejectedRows), ...
                repmat("quality_rejected", 5, 1));
            testCase.verifyEqual(run.metricsTable.Status(passingRows), ...
                repmat("ok", 5, 1));
            testCase.verifyEqual(run.metricsTable.ErrorIdentifier(rejectedRows), ...
                repmat("StoreNet:QualityRejected", 5, 1));
            testCase.verifyEqual(run.summaryTable.SuccessfulDays, ones(5, 1));
            testCase.verifyTrue(isfile(run.qualityPath));
            testCase.verifyTrue(isfile(run.checkpointPath));
            checkpoint = readtable(run.checkpointPath);
            testCase.verifyEqual(checkpoint.IsFinal, 1);
            testCase.verifyEqual(checkpoint.CompletedMetricRows, 10);
            testCase.verifyEqual(checkpoint.ExpectedMetricRows, 10);
            testCase.verifyTrue(isfile(run.manifestPath));
        end

        function testMonthlyBuildsDefaultSamplingGrid(testCase)
            run = run_monthly( ...
                OutputRoot=testCase.OutputRoot, RunId="monthly_default_unit", ...
                QualityMode="release_literal", ...
                DataProvider=@experimentDataProvider, ...
                Solver=@experimentSolver);

            testCase.verifyEqual(height(run.qualityTable), 48);
            testCase.verifyEqual(height(run.metricsTable), 48 * 5);
            testCase.verifyEqual(run.qualityTable.Day(1), datetime(2020, 1, 1));
            testCase.verifyEqual(run.qualityTable.Day(end), datetime(2020, 12, 16));
            testCase.verifyEqual(unique(day(run.qualityTable.Day)).', ...
                [1, 2, 15, 16]);
            testCase.verifyEqual(nnz(run.metricsTable.Status == "failed"), 5);
            testCase.verifyEqual(nnz(run.metricsTable.Status == "ok"), 47 * 5);
            testCase.verifyEqual(run.metricsTable.ErrorIdentifier(1:5), ...
                repmat("StoreNet:RejectedDataReachedSolver", 5, 1));
            checkpoint = readtable(run.checkpointPath);
            testCase.verifyEqual(checkpoint.CompletedQualityDays, 48);
            testCase.verifyEqual(checkpoint.ExpectedQualityDays, 48);
            testCase.verifyEqual(checkpoint.IsFinal, 1);
        end

        function testSensitivityScalesPhysicalRatingsAndFractions(testCase)
            run = run_sensitivity(datetime(2020, 1, 2), ...
                CapacityRatios=[0.5, 1], PowerRatios=[0.25, 1], ...
                OutputRoot=testCase.OutputRoot, RunId="sensitivity_unit", ...
                QualityMode="short_gap_only", ...
                DataProvider=@experimentDataProvider, ...
                Solver=@experimentSolver, FigureVisible=false);

            testCase.verifyEqual(run.sensitivityTable.BatteryCapacityKWh, ...
                [5; 5; 10; 10], AbsTol=1e-12);
            testCase.verifyEqual(run.sensitivityTable.BatteryPowerKW, ...
                [0.825; 3.3; 0.825; 3.3], AbsTol=1e-12);
            testCase.verifyEqual(run.sensitivityTable.InitialEnergyKWh, ...
                [0.5; 0.5; 1; 1], AbsTol=1e-12);
            testCase.verifyEqual(run.sensitivityTable.MinimumEnergyKWh, ...
                [0.5; 0.5; 1; 1], AbsTol=1e-12);
            testCase.verifyEqual(run.sensitivityTable.MaximumEnergyKWh, ...
                [4.5; 4.5; 9; 9], AbsTol=1e-12);
            testCase.verifyEqual(run.sensitivityTable.TerminalEnergyKWh, ...
                [0.5; 0.5; 1; 1], AbsTol=1e-12);
            testCase.verifyEqual(run.sensitivityTable.Status, repmat("ok", 4, 1));
            testCase.verifyTrue(isfile(run.metricsPath));
            testCase.verifyTrue(isfile(run.figurePath));
        end

        function testSensitivityRejectsNonpositiveGrid(testCase)
            invoke = @() run_sensitivity(datetime(2020, 1, 2), ...
                CapacityRatios=[0, 1], OutputRoot=testCase.OutputRoot, ...
                RunId="invalid_grid", DataProvider=@experimentDataProvider, ...
                Solver=@experimentSolver);

            testCase.verifyError(invoke, "StoreNet:InvalidSensitivityGrid");
        end
    end
end

function writeSyntheticReference(path)
interval_end_hour = (0.5:0.5:2).';
load_kw = [4; 6; 8; 10];
pv_kw = [0; 2; 4; 0];
reading_uncertainty_kw = 0.5 * ones(4, 1);
reference = table(interval_end_hour, load_kw, pv_kw, ...
    reading_uncertainty_kw);
writetable(reference, path);
end

function [data, meta] = experimentDataProvider(day, options)
arguments
    day (1, 1) datetime
    options.DataRoot (1, 1) string = ""
    options.IntervalMinutes (1, 1) double = 30
    options.QualityMode (1, 1) string = "short_gap_only"
end

day = dateshift(day, "start", "day");
if day == datetime(2020, 1, 1)
    loadOffsetKW = 0;
elseif day == datetime(2020, 1, 2)
    loadOffsetKW = 2;
else
    loadOffsetKW = 4;
end
aggregateLoadKW = [4; 6; 8; 10] + loadOffsetKW;
aggregatePvKW = [0; 2; 4; 0];
data = struct;
data.day = day;
data.time = day + minutes(options.IntervalMinutes .* (1:4).');
data.loadKW = [0.5 .* aggregateLoadKW, 0.5 .* aggregateLoadKW];
data.pvKW = [aggregatePvKW, zeros(4, 1)];
data.dtHours = options.IntervalMinutes / 60;
data.houseIds = ["H1", "H2"];

meta = struct;
meta.qualityPassed = ~(day == datetime(2020, 1, 1) && ...
    options.QualityMode ~= "release_literal" && options.QualityMode ~= "report");
meta.qualityReasons = strings(0, 1);
if ~meta.qualityPassed
    meta.qualityReasons = "synthetic canonical rejection";
end
meta.isComplete = true;
meta.isFullyObserved = meta.qualityPassed;
meta.pvLongWindowAnomaly = false;
meta.pvWindowHours = 1.5;
meta.astronomicalDayLengthHours = 8;
meta.longestMissingStatusRunByHome = [0, double(~meta.qualityPassed) * 3];
meta.intervalConvention = "synthetic interval-end labels";
end

function [solution, metrics] = experimentSolver(data, config, strategy)
if data.day == datetime(2020, 1, 1)
    error("StoreNet:RejectedDataReachedSolver", ...
        "A quality-rejected day reached the solver.");
end
switch strategy
    case "SH_BM"
        reductionKW = 0.25;
    case "VPP_BM"
        reductionKW = 0.75;
    case "PS"
        reductionKW = 1.25;
    case "PSDT"
        reductionKW = 1.0;
    case "LL"
        reductionKW = 1.5;
    case "IMPROVED_PEAK_GUARD"
        reductionKW = 0.5;
    otherwise
        error("StoreNet:UnknownSyntheticStrategy", ...
            "Synthetic experiment solver does not support strategy '%s'.", ...
            strategy);
end
aggregateLoadKW = sum(double(data.loadKW), 2);
aggregatePvKW = sum(double(data.pvKW), 2);
aggregateImportKW = max(aggregateLoadKW - aggregatePvKW - reductionKW, 0);
if strategy == "IMPROVED_PEAK_GUARD"
    aggregateImportKW = min(aggregateImportKW, config.aggregateImportCapKW);
end

baselineBillEUR = 20;
optimizedBillEUR = baselineBillEUR - reductionKW;
metrics = struct;
metrics.baselineBillEUR = baselineBillEUR;
metrics.optimizedBillEUR = optimizedBillEUR;
metrics.savingsEUR = baselineBillEUR - optimizedBillEUR;
metrics.savingsPercent = 100 * metrics.savingsEUR / baselineBillEUR;
metrics.baselinePeakImportKW = 7.25;
metrics.peakImportKW = max(aggregateImportKW);
metrics.daytimePeakImportKW = metrics.peakImportKW;
metrics.importSpreadKW = max(aggregateImportKW) - min(aggregateImportKW);
metrics.totalGridImportKWh = data.dtHours * sum(aggregateImportKW);
metrics.totalBatteryThroughputKWh = reductionKW;
metrics.totalCurtailedPvKWh = 0;
metrics.totalSharedExportKWh = reductionKW;
metrics.energyBalanceResidualKW = 0;
metrics.terminalSocErrorKWh = 0;
metrics.simultaneousChargeDischargeKW = 0;
metrics.PaperLoadOnlyBaseline = struct( ...
    "billEUR", 25, ...
    "peakImportKW", 9.5, ...
    "savingsEUR", 25 - optimizedBillEUR, ...
    "savingsPercent", 100 .* (25 - optimizedBillEUR) ./ 25);
metrics.PvSelfNoBatteryBaseline = struct( ...
    "billEUR", baselineBillEUR, ...
    "peakImportKW", metrics.baselinePeakImportKW, ...
    "savingsEUR", metrics.savingsEUR, ...
    "savingsPercent", metrics.savingsPercent);

solution = struct;
solution.aggregateImportKW = aggregateImportKW;
solution.exitFlags = 1;
solution.metrics = metrics;
end
