classdef TestBahloulMonthlyV1 < matlab.unittest.TestCase
    %TESTBAHLOULMONTHLYV1 Contract tests for the B2022 monthly runner.

    properties
        OutputRoot
        H4DiagnosticsPath
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
            testCase.H4DiagnosticsPath = string(fullfile( ...
                testCase.OutputRoot, "h4_daily.csv"));
            writeH4Diagnostics(testCase.H4DiagnosticsPath);
            resetProviderCounter();
            testCase.addTeardown(@resetProviderCounter);
        end
    end

    methods (Test)
        function testAggregatesPrimaryScenarioAndPersistsEvidence(testCase)
            dates = [datetime(2020, 1, 1); datetime(2020, 1, 8); ...
                datetime(2020, 2, 1)];
            run = run_bahloul_monthly_v1(Dates=dates, ...
                OutputRoot=testCase.OutputRoot, RunId="monthly_contract", ...
                H4DiagnosticsPath=testCase.H4DiagnosticsPath, ...
                DataProvider=@monthlyDataProvider, ...
                Solver=@monthlySolver, FigureVisible=false, ...
                PersistSolutions=true);

            testCase.verifyEqual(providerCallCount(), numel(dates));
            testCase.verifyEqual(height(run.dailyMetrics), 5 * numel(dates));
            testCase.verifyFalse(any(run.dailyMetrics.Strategy == "SB_SC"));
            testCase.verifyEqual(unique(run.dailyMetrics.ScenarioId), ...
                "DC_XI007_H20");
            testCase.verifyEqual(groupcounts(run.dailyMetrics.Strategy), ...
                numel(dates) .* ones(5, 1));
            testCase.verifyEqual(height(run.monthlyMetrics), 2 * 5);
            testCase.verifyTrue(isfile(run.dailyMetricsPath));
            testCase.verifyTrue(isfile(run.monthlyMetricsPath));
            testCase.verifyTrue(isfile(run.monthlyProfilesPath));
            testCase.verifyTrue(isfile(run.figurePath));

            testCase.verifyEqual(unique(run.dailyMetrics.CohortId), "H20_PV10");
            testCase.verifyEqual(unique(run.dailyMetrics.HouseCount), 20);
            testCase.verifyEqual(unique(run.dailyMetrics.PvHomeCount), 10);

            januaryVpp = run.monthlyMetrics.YearMonth == ...
                datetime(2020, 1, 1) & ...
                run.monthlyMetrics.ScenarioId == "DC_XI007_H20" & ...
                run.monthlyMetrics.Strategy == "VPP_BM";
            testCase.verifyEqual(nnz(januaryVpp), 1);
            testCase.verifyEqual( ...
                run.monthlyMetrics.MeanDailyPaperLoadOnlySavingsPercent( ...
                januaryVpp), 20, AbsTol=1e-12);
            testCase.verifyEqual( ...
                run.monthlyMetrics.RatioOfSummedCostsPaperLoadOnlySavingsPercent( ...
                januaryVpp), 100 * 70 / 300, AbsTol=1e-12);
            testCase.verifyEqual( ...
                run.monthlyMetrics.RatioOfSummedCostsPvSelfNoBatterySavingsPercent( ...
                januaryVpp), 100 * 10 / 240, AbsTol=1e-12);
            testCase.verifyEqual( ...
                run.monthlyMetrics.MeanDailyOutcomePeakImportKW(januaryVpp), ...
                40, AbsTol=1e-12);
            testCase.verifyEqual( ...
                run.monthlyMetrics.PeakOfMeanProfileImportKW(januaryVpp), ...
                20, AbsTol=1e-12);
            testCase.verifyEqual(run.monthlyMetrics.ValidDays(januaryVpp), 2);
            testCase.verifyEqual(run.monthlyMetrics.RequestedDays(januaryVpp), 2);
            failed = run.dailyMetrics.Day == datetime(2020, 1, 8) & ...
                run.dailyMetrics.ScenarioId == "DC_XI007_H20" & ...
                run.dailyMetrics.Strategy == "LL";
            testCase.verifyEqual(nnz(failed), 1);
            testCase.verifyEqual(run.dailyMetrics.Status(failed), "failed");
            testCase.verifyEqual(run.dailyMetrics.ErrorIdentifier(failed), ...
                "StoreNet:SyntheticMonthlyFailure");
            failedSummary = run.monthlyMetrics.YearMonth == ...
                datetime(2020, 1, 1) & ...
                run.monthlyMetrics.ScenarioId == "DC_XI007_H20" & ...
                run.monthlyMetrics.Strategy == "LL";
            testCase.verifyEqual(run.monthlyMetrics.RequestedDays( ...
                failedSummary), 2);
            testCase.verifyEqual(run.monthlyMetrics.ValidDays( ...
                failedSummary), 1);

            modelEvidence = dir(fullfile(run.runDirectory, "cases", ...
                "2020-01-01", "DC_XI007_H20", "VPP_BM", ...
                "inputs_*.mat"));
            testCase.verifyEqual(numel(modelEvidence), 1);
            testCase.verifyFalse(any(string( ...
                run.dailyMetrics.Properties.VariableNames) == "Savings"));
            testCase.verifyFalse(any(string( ...
                run.monthlyMetrics.Properties.VariableNames) == "Savings"));
        end

        function testQualityRejectionRetainsAllExpectedRows(testCase)
            dates = [datetime(2020, 3, 1); datetime(2020, 3, 8)];
            run = run_bahloul_monthly_v1(Dates=dates, ...
                OutputRoot=testCase.OutputRoot, RunId="monthly_rejection", ...
                H4DiagnosticsPath=testCase.H4DiagnosticsPath, ...
                DataProvider=@rejectingMonthlyDataProvider, ...
                Solver=@monthlySolver, FigureVisible=false, ...
                PersistSolutions=false);

            rejected = run.dailyMetrics.Day == datetime(2020, 3, 1);
            accepted = run.dailyMetrics.Day == datetime(2020, 3, 8);
            testCase.verifyEqual(providerCallCount(), 2);
            testCase.verifyEqual(nnz(rejected), 5);
            testCase.verifyEqual(nnz(accepted), 5);
            testCase.verifyEqual(run.dailyMetrics.Status(rejected), ...
                repmat("quality_rejected", 5, 1));
            testCase.verifyEqual(run.dailyMetrics.ErrorIdentifier(rejected), ...
                repmat("StoreNet:QualityRejected", 5, 1));
            testCase.verifyEqual(nnz(run.dailyMetrics.Status(accepted) == "ok"), ...
                5);

            summary = run.monthlyMetrics.ScenarioId == "DC_XI007_H20" & ...
                run.monthlyMetrics.Strategy == "SH_BM" & ...
                run.monthlyMetrics.YearMonth == datetime(2020, 3, 1);
            testCase.verifyEqual(run.monthlyMetrics.RequestedDays(summary), 2);
            testCase.verifyEqual(run.monthlyMetrics.ValidDays(summary), 1);
            testCase.verifyEqual(run.monthlyMetrics.FailedOrRejectedDays( ...
                summary), 1);
        end

        function testDefaultGridAndPaperPeriodBoundaries(testCase)
            run = run_bahloul_monthly_v1( ...
                OutputRoot=testCase.OutputRoot, RunId="monthly_default", ...
                H4DiagnosticsPath=testCase.H4DiagnosticsPath, ...
                DataProvider=@rejectingAllMonthlyDataProvider, ...
                Solver=@monthlySolver, FigureVisible=false, ...
                PersistSolutions=false);

            testCase.verifyEqual(providerCallCount(), 48);
            testCase.verifyEqual(numel(run.sampleDates), 48);
            testCase.verifyEqual(unique(day(run.sampleDates)).', ...
                [1, 2, 15, 16]);
            testCase.verifyEqual(run.sampleDates(1), datetime(2020, 1, 1));
            testCase.verifyEqual(run.sampleDates(end), datetime(2020, 12, 16));
            testCase.verifyEqual(height(run.dailyMetrics), 48 * 5);
            testCase.verifyEqual(height(run.monthlyMetrics), 12 * 5);
            testCase.verifyTrue(all(year(run.monthlyMetrics.YearMonth) == 2020));

            overlap = run.monthlyMetrics.PaperPeriodRelation == ...
                "2020-01--06_overlap";
            extrapolation = run.monthlyMetrics.PaperPeriodRelation == ...
                "2020-07--12_extrapolation";
            testCase.verifyEqual(nnz(overlap), 6 * 5);
            testCase.verifyEqual(nnz(extrapolation), 6 * 5);
            testCase.verifyEqual( ...
                run.monthlyMetrics.PublicReleaseAvailability( ...
                overlap | extrapolation), ...
                repmat("available_from_public_release", 12 * 5, 1));
            testCase.verifyEqual(run.monthlyMetrics.CandidateDays, ...
                4 * ones(12 * 5, 1));
            testCase.verifyEqual(run.monthlyMetrics.UnavailableCandidateDays, ...
                zeros(12 * 5, 1));
        end
    end
end

function writeH4Diagnostics(path)
dates = ["2020-01-01"; "2020-01-08"; "2020-02-01"; ...
    "2020-03-01"; "2020-03-08"];
alignmentCategory = ["unaffected_same0"; "affected_mismatch"; ...
    "affected_mismatch"; "affected_mismatch"; "affected_mismatch"];
diagnostics = table(dates, alignmentCategory, ...
    VariableNames=["Date", "AlignmentCategory"]);
writetable(diagnostics, path);
end

function [data, meta] = monthlyDataProvider(calendarDay, options)
arguments
    calendarDay (1, 1) datetime
    options.DataRoot (1, 1) string = ""
    options.IntervalMinutes (1, 1) double = 60
    options.QualityMode (1, 1) string = "exclude_flagged_pv"
end
incrementProviderCounter();
calendarDay = dateshift(calendarDay, "start", "day");
houseIds = compose("H%d", 1:20);
pvHomeNumbers = [1, 2, 3, 4, 5, 7, 10, 11, 13, 17];
pvHomeMask = ismember(1:20, pvHomeNumbers);
aggregateLoadKW = [50; 60; 70; 80] + day(calendarDay);
aggregatePvKW = [0; 10; 20; 0];
loadKW = repmat(aggregateLoadKW ./ 20, 1, 20);
pvKW = zeros(4, 20);
pvKW(:, pvHomeMask) = repmat(aggregatePvKW ./ nnz(pvHomeMask), ...
    1, nnz(pvHomeMask));
fromGridKW = max(loadKW - 0.95 .* pvKW, 0);
zerosKW = zeros(size(loadKW));

data = struct;
data.day = calendarDay;
data.time = calendarDay + hours((1:4).');
data.timeEnd = data.time;
data.dtHours = options.IntervalMinutes / 60;
data.intervalMinutes = options.IntervalMinutes;
data.houseIds = houseIds;
data.homeNames = houseIds;
data.pvHomeMask = pvHomeMask;
data.loadKW = loadKW;
data.pvKW = pvKW;
data.loadKWh = loadKW .* data.dtHours;
data.pvKWh = pvKW .* data.dtHours;
data.fromGridKW = fromGridKW;
data.fromGridKWh = fromGridKW .* data.dtHours;
data.chargeKW = zerosKW;
data.dischargeKW = zerosKW;
data.feedInKW = zerosKW;
data.chargeKWh = zerosKW;
data.dischargeKWh = zerosKW;
data.feedInKWh = zerosKW;
data.socFraction = 0.1 .* ones(size(loadKW));
data.validForOptimization = true;

meta = struct;
meta.qualityPassed = true;
meta.qualityReasons = strings(0, 1);
meta.intervalConvention = "synthetic interval-end labels";
end

function [data, meta] = rejectingMonthlyDataProvider(calendarDay, options)
arguments
    calendarDay (1, 1) datetime
    options.DataRoot (1, 1) string = ""
    options.IntervalMinutes (1, 1) double = 60
    options.QualityMode (1, 1) string = "exclude_flagged_pv"
end
[data, meta] = monthlyDataProvider(calendarDay, ...
    DataRoot=options.DataRoot, IntervalMinutes=options.IntervalMinutes, ...
    QualityMode=options.QualityMode);
if day(calendarDay) == 1
    meta.qualityPassed = false;
    meta.qualityReasons = "synthetic monthly rejection";
    data.validForOptimization = false;
end
end

function [data, meta] = rejectingAllMonthlyDataProvider(calendarDay, options)
arguments
    calendarDay (1, 1) datetime
    options.DataRoot (1, 1) string = ""
    options.IntervalMinutes (1, 1) double = 60
    options.QualityMode (1, 1) string = "exclude_flagged_pv"
end
[data, meta] = monthlyDataProvider(calendarDay, ...
    DataRoot=options.DataRoot, IntervalMinutes=options.IntervalMinutes, ...
    QualityMode=options.QualityMode);
meta.qualityPassed = false;
meta.qualityReasons = "synthetic all-days rejection";
data.validForOptimization = false;
end

function [solution, metrics] = monthlySolver(data, config, strategy)
if data.day == datetime(2020, 1, 8) && ...
        string(config.scenarioId) == "DC_XI007_H20" && strategy == "LL"
    error("StoreNet:SyntheticMonthlyFailure", ...
        "Synthetic solver failure retained by the monthly runner.");
end

switch day(data.day)
    case 1
        paperSavingsPercent = 10;
        aggregateImportKW = [40; 0; 0; 0];
    case 8
        paperSavingsPercent = 30;
        aggregateImportKW = [0; 40; 0; 0];
    otherwise
        paperSavingsPercent = 20;
        aggregateImportKW = [10; 20; 30; 40];
end
if month(data.day) == 1 && day(data.day) == 1
    paperBillEUR = 100;
elseif month(data.day) == 1 && day(data.day) == 8
    paperBillEUR = 200;
else
    paperBillEUR = 300;
end
optimizedBillEUR = paperBillEUR * (1 - paperSavingsPercent / 100);
pvSelfBillEUR = 0.8 * paperBillEUR;
paperPeakKW = max(sum(double(data.loadKW), 2));

paperBaseline = struct( ...
    definition="synthetic load-only baseline", ...
    billEUR=paperBillEUR, peakImportKW=paperPeakKW, ...
    daytimePeakImportKW=paperPeakKW, ...
    savingsEUR=paperBillEUR - optimizedBillEUR, ...
    savingsPercent=paperSavingsPercent, ...
    savingsPercentDenominatorIsZero=false);
pvSelfBaseline = struct( ...
    definition="synthetic PV-self baseline", ...
    billEUR=pvSelfBillEUR, peakImportKW=0.8 * paperPeakKW, ...
    daytimePeakImportKW=0.8 * paperPeakKW, ...
    savingsEUR=pvSelfBillEUR - optimizedBillEUR, ...
    savingsPercent=100 * (pvSelfBillEUR - optimizedBillEUR) / pvSelfBillEUR, ...
    savingsPercentDenominatorIsZero=false);
metrics = struct;
metrics.PaperLoadOnlyBaseline = paperBaseline;
metrics.PvSelfNoBatteryBaseline = pvSelfBaseline;
metrics.optimizedBillEUR = optimizedBillEUR;
metrics.peakImportKW = max(aggregateImportKW);
metrics.daytimePeakImportKW = metrics.peakImportKW;
metrics.totalGridImportKWh = data.dtHours * sum(aggregateImportKW);
metrics.totalBatteryThroughputKWh = 0;
metrics.totalCurtailedPvKWh = 0;
metrics.totalSharedExportKWh = 0;
metrics.energyBalanceResidualKW = 0;

stage = struct(name="cost", value=optimizedBillEUR, ...
    solverObjective=optimizedBillEUR, exitFlag=1, relativeGap=0, ...
    message="synthetic optimal");
solution = struct;
solution.strategy = strategy;
solution.aggregateImportKW = aggregateImportKW;
solution.objectiveStages = stage;
solution.exitFlags = 1;
end

function resetProviderCounter()
setappdata(groot, "BahloulMonthlyProviderCalls", 0);
end

function incrementProviderCounter()
setappdata(groot, "BahloulMonthlyProviderCalls", providerCallCount() + 1);
end

function count = providerCallCount()
if isappdata(groot, "BahloulMonthlyProviderCalls")
    count = getappdata(groot, "BahloulMonthlyProviderCalls");
else
    count = 0;
end
end
