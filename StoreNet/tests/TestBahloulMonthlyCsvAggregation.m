classdef TestBahloulMonthlyCsvAggregation < matlab.unittest.TestCase
    %TESTBAHLOULMONTHLYCSVAGGREGATION Offline regrouping of saved daily CSVs.

    properties
        TemporaryFolder
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
        function createTemporaryFolder(testCase)
            testCase.TemporaryFolder = string(tempname);
            mkdir(testCase.TemporaryFolder);
            testCase.addTeardown(@() rmdir(testCase.TemporaryFolder, "s"));
        end
    end

    methods (Test)
        function testUsesExplicitPaperBaselineWithoutReadingRelease(testCase)
            inputPath = fullfile(testCase.TemporaryFolder, "daily.csv");
            outputPath = fullfile(testCase.TemporaryFolder, "monthly.csv");
            daily = explicitPaperDailyTable();
            writetable(daily, inputPath);

            [monthly, normalizedDaily] = aggregate_bahloul_monthly_csv( ...
                inputPath, ...
                OutputPath=outputPath, DataProvider=@unexpectedDataProvider);
            vpp = monthly(monthly.Strategy == "VPP_BM", :);

            testCase.verifyEqual(height(monthly), 2);
            testCase.verifyEqual(height(vpp), 1);
            testCase.verifyEqual(vpp.YearMonth, datetime(2020, 1, 1));
            testCase.verifyEqual(vpp.RequestedDays, 3);
            testCase.verifyEqual(vpp.ValidDays, 2);
            testCase.verifyEqual(vpp.FailedOrRejectedDays, 1);
            testCase.verifyEqual( ...
                vpp.MeanDailyPaperLoadOnlyBaselineBillEUR, 15, ...
                AbsTol=1e-12);
            testCase.verifyEqual(vpp.MeanDailyPaperLoadOnlySavingsEUR, 7, ...
                AbsTol=1e-12);
            testCase.verifyEqual( ...
                vpp.MeanDailyPaperLoadOnlySavingsPercent, 45, ...
                AbsTol=1e-12);
            testCase.verifyEqual(vpp.SumPaperLoadOnlyBaselineBillEUR, 30, ...
                AbsTol=1e-12);
            testCase.verifyEqual(vpp.SumOptimizedBillEUR, 16, ...
                AbsTol=1e-12);
            testCase.verifyEqual( ...
                vpp.RatioOfSummedCostsPaperLoadOnlySavingsPercent, ...
                100 * 14 / 30, AbsTol=1e-12);
            testCase.verifyEqual( ...
                vpp.MeanDailyPvSelfNoBatteryBaselineBillEUR, 12, ...
                AbsTol=1e-12);
            testCase.verifyEqual(vpp.MeanDailyOutcomePeakImportKW, 4.5, ...
                AbsTol=1e-12);
            testCase.verifyEqual(vpp.PaperLoadOnlyBaselineSource, ...
                "daily_csv:PaperLoadOnlyBaselineBillEUR");
            testCase.verifyEqual(normalizedDaily.YearMonth, ...
                repmat(datetime(2020, 1, 1), height(normalizedDaily), 1));
            testCase.verifyEqual( ...
                normalizedDaily.PaperLoadOnlySavingsEUR([1, 2, 4]), ...
                [4; 10; 2]);
            testCase.verifyTrue(isnan( ...
                normalizedDaily.PaperLoadOnlySavingsEUR(3)));
            testCase.verifyEqual( ...
                normalizedDaily.PvSelfNoBatterySavingsEUR([1, 2, 4]), ...
                [2; 6; 0]);
            testCase.verifyTrue(isnan( ...
                normalizedDaily.PvSelfNoBatterySavingsEUR(3)));
            testCase.verifyEqual( ...
                normalizedDaily.PaperLoadOnlyBaselineSource, ...
                repmat("daily_csv:PaperLoadOnlyBaselineBillEUR", 4, 1));
            testCase.verifyTrue(isfile(outputPath));
        end

        function testLegacyBaselineStaysPvSelfAndPaperBillIsRecomputed(testCase)
            inputPath = fullfile(testCase.TemporaryFolder, ...
                "monthly_metrics.csv");
            manifestPath = fullfile(testCase.TemporaryFolder, "manifest.json");
            writetable(legacyDailyTable(), inputPath);
            writeLegacyManifest(manifestPath);

            [monthly, normalizedDaily] = ...
                aggregate_bahloul_monthly_csv(inputPath, ...
                ManifestPath=manifestPath, ...
                DataProvider=@legacyLoadDataProvider);
            vpp = monthly(monthly.Strategy == "VPP_BM", :);

            testCase.verifyEqual(height(monthly), 2);
            testCase.verifyEqual(vpp.MeanDailyPaperLoadOnlyBaselineBillEUR, ...
                4.5, AbsTol=1e-12);
            testCase.verifyEqual(vpp.SumPaperLoadOnlyBaselineBillEUR, 9, ...
                AbsTol=1e-12);
            testCase.verifyEqual( ...
                vpp.MeanDailyPaperLoadOnlySavingsPercent, 50, ...
                AbsTol=1e-12);
            testCase.verifyEqual( ...
                vpp.RatioOfSummedCostsPaperLoadOnlySavingsPercent, 50, ...
                AbsTol=1e-12);
            testCase.verifyEqual( ...
                vpp.MeanDailyPvSelfNoBatteryBaselineBillEUR, 3, ...
                AbsTol=1e-12);
            testCase.verifyEqual( ...
                vpp.RatioOfSummedCostsPvSelfNoBatterySavingsPercent, 25, ...
                AbsTol=1e-12);
            testCase.verifyEqual(vpp.PaperLoadOnlyBaselineSource, ...
                "offline_recomputed:legacyLoadDataProvider");
            testCase.verifyEqual(vpp.PvSelfNoBatteryBaselineSource, ...
                "daily_csv:BaselineBillEUR (legacy PV-self)");
            testCase.verifyEqual( ...
                normalizedDaily.PaperLoadOnlyBaselineBillEUR, ...
                [3; 3; 6; 6], AbsTol=1e-12);
            testCase.verifyEqual( ...
                normalizedDaily.PaperLoadOnlyPeakKW, ...
                [1; 1; 2; 2], AbsTol=1e-12);
            testCase.verifyEqual( ...
                normalizedDaily.PaperLoadOnlyDaytimePeakKW, ...
                [1; 1; 2; 2], AbsTol=1e-12);
            testCase.verifyEqual( ...
                normalizedDaily.PvSelfNoBatteryBaselineBillEUR, ...
                normalizedDaily.BaselineBillEUR, AbsTol=1e-12);
            testCase.verifyEqual( ...
                normalizedDaily.PaperLoadOnlySavingsEUR, ...
                [1.5; 1.2; 3; 2.4], AbsTol=1e-12);
            testCase.verifyEqual( ...
                normalizedDaily.PvSelfNoBatteryBaselineSource, ...
                repmat("daily_csv:BaselineBillEUR (legacy PV-self)", 4, 1));
        end

        function testLegacyCsvWithoutManifestFailsClearly(testCase)
            inputPath = fullfile(testCase.TemporaryFolder, ...
                "monthly_metrics.csv");
            writetable(legacyDailyTable(), inputPath);

            operation = @() aggregate_bahloul_monthly_csv(inputPath, ...
                DataProvider=@legacyLoadDataProvider);

            testCase.verifyError(operation, ...
                "StoreNet:PaperBaselineUnavailable");
        end

        function testPrimaryTwelveMonthMatrixRegroupsToSixtyRows(testCase)
            inputPath = fullfile(testCase.TemporaryFolder, "daily.csv");
            writetable(primaryTwelveMonthDailyTable(), inputPath);

            [monthly, normalizedDaily] = ...
                aggregate_bahloul_monthly_csv(inputPath, ...
                DataProvider=@unexpectedDataProvider);

            testCase.verifyEqual(height(normalizedDaily), 48 * 5);
            testCase.verifyEqual(height(monthly), 12 * 5);
            testCase.verifyEqual(numel(unique(monthly.YearMonth)), 12);
            testCase.verifyEqual(numel(unique(monthly.Strategy)), 5);
            testCase.verifyEqual(monthly.RequestedDays, ...
                4 .* ones(12 * 5, 1));
            testCase.verifyEqual(monthly.ValidDays, ...
                3 .* ones(12 * 5, 1));
            testCase.verifyEqual(monthly.FailedOrRejectedDays, ...
                ones(12 * 5, 1));
        end
    end
end

function daily = explicitPaperDailyTable()
Day = [datetime(2020, 1, 2); datetime(2020, 1, 15); ...
    datetime(2020, 1, 16); datetime(2020, 1, 2)];
Strategy = ["VPP_BM"; "VPP_BM"; "VPP_BM"; "SH_BM"];
Status = ["ok"; "ok"; "failed"; "ok"];
PaperLoadOnlyBaselineBillEUR = [10; 20; NaN; 10];
PvSelfNoBatteryBaselineBillEUR = [8; 16; NaN; 8];
OptimizedBillEUR = [6; 10; NaN; 8];
PeakImportKW = [4; 5; NaN; 6];
daily = table(Day, Strategy, Status, PaperLoadOnlyBaselineBillEUR, ...
    PvSelfNoBatteryBaselineBillEUR, OptimizedBillEUR, PeakImportKW);
end

function daily = legacyDailyTable()
Day = [datetime(2020, 1, 2); datetime(2020, 1, 2); ...
    datetime(2020, 1, 15); datetime(2020, 1, 15)];
Strategy = ["VPP_BM"; "SH_BM"; "VPP_BM"; "SH_BM"];
Status = repmat("ok", 4, 1);
BaselineBillEUR = [2; 2; 4; 4];
OptimizedBillEUR = [1.5; 1.8; 3; 3.6];
PeakImportKW = [4; 5; 6; 7];
daily = table(Day, Strategy, Status, BaselineBillEUR, ...
    OptimizedBillEUR, PeakImportKW);
end

function daily = primaryTwelveMonthDailyTable()
strategies = ["SH_BM", "VPP_BM", "PS", "PSDT", "LL"];
sampleDays = [1, 2, 15, 16];
rowCount = 12 * numel(sampleDays) * numel(strategies);
Day = NaT(rowCount, 1);
Strategy = strings(rowCount, 1);
Status = strings(rowCount, 1);
PaperLoadOnlyBaselineBillEUR = nan(rowCount, 1);
PvSelfNoBatteryBaselineBillEUR = nan(rowCount, 1);
OptimizedBillEUR = nan(rowCount, 1);
PeakImportKW = nan(rowCount, 1);
rowIndex = 0;
for monthIndex = 1:12
    for sampleDay = sampleDays
        for strategy = strategies
            rowIndex = rowIndex + 1;
            Day(rowIndex) = datetime(2020, monthIndex, sampleDay);
            Strategy(rowIndex) = strategy;
            if sampleDay == 1
                Status(rowIndex) = "quality_rejected";
            else
                Status(rowIndex) = "ok";
                PaperLoadOnlyBaselineBillEUR(rowIndex) = 100 + monthIndex;
                PvSelfNoBatteryBaselineBillEUR(rowIndex) = 80 + monthIndex;
                OptimizedBillEUR(rowIndex) = 0.75 * (100 + monthIndex);
                PeakImportKW(rowIndex) = 10 + monthIndex;
            end
        end
    end
end
daily = table(Day, Strategy, Status, PaperLoadOnlyBaselineBillEUR, ...
    PvSelfNoBatteryBaselineBillEUR, OptimizedBillEUR, PeakImportKW);
end

function writeLegacyManifest(path)
configuration = struct(intervalMinutes=60, qualityMode="release_literal", ...
    dataRoot="unused-by-fixture", nightPrice=1, dayPrice=2, ...
    dayStartHour=10, dayEndHour=22);
manifest = struct(experiment=struct(configuration=configuration));
fileId = fopen(path, "wt", "n", "UTF-8");
assert(fileId >= 0, "Synthetic manifest could not be opened.");
cleaner = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s\n", jsonencode(manifest));
clear cleaner
end

function [data, meta] = legacyLoadDataProvider(calendarDay, options)
arguments
    calendarDay (1, 1) datetime
    options.DataRoot (1, 1) string = ""
    options.IntervalMinutes (1, 1) double = 60
    options.QualityMode (1, 1) string = "release_literal"
end
if options.IntervalMinutes ~= 60 || options.QualityMode ~= "release_literal"
    error("StoreNet:UnexpectedOfflineSettings", ...
        "Legacy manifest settings were not passed to the data provider.");
end
loadLevel = 1;
if calendarDay == datetime(2020, 1, 15)
    loadLevel = 2;
end
data = struct;
data.time = calendarDay + hours([10; 11]);
data.dtHours = 1;
data.loadKW = loadLevel .* ones(2, 1);
data.requestedDataRoot = options.DataRoot;
meta = struct(qualityPassed=true);
end

function varargout = unexpectedDataProvider(varargin)
varargout = cell(1, nargout); %#ok<NASGU>
error("StoreNet:UnexpectedDataProvider", ...
    "Explicit paper baseline rows must not reload public data.");
end
