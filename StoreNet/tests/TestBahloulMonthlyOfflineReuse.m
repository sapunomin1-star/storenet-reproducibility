classdef TestBahloulMonthlyOfflineReuse < matlab.unittest.TestCase
    %TESTBAHLOULMONTHLYOFFLINEREUSE Saved daily metrics bypass all solves.

    properties
        TemporaryFolder
        DailyMetricsPath
        DailyManifestPath
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
        function createOfflineSource(testCase)
            testCase.TemporaryFolder = string(tempname);
            mkdir(testCase.TemporaryFolder);
            testCase.addTeardown(@() rmdir(testCase.TemporaryFolder, "s"));
            testCase.DailyMetricsPath = string(fullfile( ...
                testCase.TemporaryFolder, "source_daily_metrics.csv"));
            testCase.DailyManifestPath = string(fullfile( ...
                testCase.TemporaryFolder, "source_manifest.json"));
            writetable(offlineDailyFixture(), testCase.DailyMetricsPath);
            writeOfflineManifest(testCase.DailyManifestPath, ...
                "release_literal");
        end
    end

    methods (Test)
        function testOfflineReuseBypassesSolverAndWritesFrozenShape(testCase)
            run = run_bahloul_monthly_v1( ...
                OutputRoot=testCase.TemporaryFolder, ...
                RunId="offline_reuse", QualityMode="release_literal", ...
                ExistingDailyMetricsPath=testCase.DailyMetricsPath, ...
                ExistingDailyManifestPath=testCase.DailyManifestPath, ...
                DataProvider=@unexpectedOfflineDataProvider, ...
                Solver=@unexpectedOfflineSolver, ...
                FigureVisible=false, PersistSolutions=true);
            januaryVpp = run.monthlyMetrics.YearMonth == ...
                datetime(2020, 1, 1) & ...
                run.monthlyMetrics.Strategy == "VPP_BM";
            januarySecondVpp = run.dailyMetrics.Day == ...
                datetime(2020, 1, 2) & ...
                run.dailyMetrics.Strategy == "VPP_BM";
            januaryRejected = run.dailyMetrics.Day == ...
                datetime(2020, 1, 1);
            artifactPaths = [run.dailyMetrics.ArtifactDirectory, ...
                run.dailyMetrics.InputsPath, run.dailyMetrics.SolutionPath, ...
                run.dailyMetrics.StagesPath, run.dailyMetrics.MetricsPath, ...
                run.dailyMetrics.ObservedProfilesPath];

            testCase.verifyTrue(run.reusedExistingDailyMetrics);
            testCase.verifyFalse(run.persistSolutions);
            testCase.verifyEqual(run.existingDailyMetricsPath, ...
                testCase.DailyMetricsPath);
            testCase.verifyEqual(run.existingDailyManifestPath, ...
                testCase.DailyManifestPath);
            testCase.verifyEqual(height(run.dailyMetrics), 48 * 5);
            testCase.verifyEqual(height(run.monthlyMetrics), 12 * 5);
            testCase.verifyEqual(numel(run.sampleDates), 48);
            testCase.verifyEqual(unique(run.dailyMetrics.ScenarioId), ...
                "DC_XI007_H20");
            testCase.verifyEqual(unique(run.dailyMetrics.QualityMode), ...
                "release_literal");
            testCase.verifyEqual(nnz(januaryRejected), 5);
            testCase.verifyEqual( ...
                run.dailyMetrics.Status(januaryRejected), ...
                repmat("quality_rejected", 5, 1));
            testCase.verifyEqual( ...
                run.dailyMetrics.ErrorIdentifier(januaryRejected), ...
                repmat("StoreNet:QualityRejected", 5, 1));
            testCase.verifyEqual(nnz(januarySecondVpp), 1);
            testCase.verifyEqual( ...
                run.dailyMetrics.PaperLoadOnlyBaselineBillEUR( ...
                januarySecondVpp), 101, AbsTol=1e-12);
            testCase.verifyEqual( ...
                run.dailyMetrics.PaperLoadOnlySavingsEUR(januarySecondVpp), ...
                25.25, AbsTol=1e-12);
            testCase.verifyEqual( ...
                run.dailyMetrics.PaperLoadOnlySavingsPercent( ...
                januarySecondVpp), 25, AbsTol=1e-12);
            testCase.verifyEqual( ...
                run.dailyMetrics.PaperLoadOnlyPeakKW(januarySecondVpp), ...
                91, AbsTol=1e-12);
            testCase.verifyEqual( ...
                run.dailyMetrics.PaperLoadOnlyDaytimePeakKW( ...
                januarySecondVpp), 71, AbsTol=1e-12);
            testCase.verifyEqual( ...
                run.dailyMetrics.PvSelfNoBatteryBaselineBillEUR( ...
                januarySecondVpp), 80.8, AbsTol=1e-12);
            testCase.verifyEqual( ...
                run.dailyMetrics.PvSelfNoBatterySavingsPercent( ...
                januarySecondVpp), 6.25, AbsTol=1e-12);
            testCase.verifyEqual( ...
                run.dailyMetrics.PvSelfNoBatteryPeakKW(januarySecondVpp), ...
                81, AbsTol=1e-12);
            testCase.verifyEqual( ...
                run.dailyMetrics.OutcomePeakImportKW(januarySecondVpp), ...
                61, AbsTol=1e-12);
            testCase.verifyEqual( ...
                run.dailyMetrics.WallTimeSeconds(januarySecondVpp), ...
                0.07, AbsTol=1e-12);
            testCase.verifyEqual(nnz(januaryVpp), 1);
            testCase.verifyEqual(run.monthlyMetrics.RequestedDays( ...
                januaryVpp), 4);
            testCase.verifyEqual(run.monthlyMetrics.ValidDays(januaryVpp), 3);
            testCase.verifyEqual( ...
                run.monthlyMetrics.MeanDailyPaperLoadOnlyBaselineBillEUR( ...
                januaryVpp), 101, AbsTol=1e-12);
            testCase.verifyEqual( ...
                run.monthlyMetrics.RatioOfSummedCostsPaperLoadOnlySavingsPercent( ...
                januaryVpp), 25, AbsTol=1e-12);
            testCase.verifyEqual( ...
                run.monthlyMetrics.MeanDailyPaperLoadOnlyPeakKW( ...
                januaryVpp), 91, AbsTol=1e-12);
            testCase.verifyTrue(isnan( ...
                run.monthlyMetrics.PeakOfMeanProfileImportKW(januaryVpp)));
            testCase.verifyEmpty(run.monthlyMeanProfiles);
            testCase.verifyEmpty(run.rawProfiles);
            testCase.verifyTrue(all(strlength(artifactPaths) == 0, "all"));
            testCase.verifyTrue(isfile(run.dailyMetricsPath));
            testCase.verifyTrue(isfile(run.monthlyMetricsPath));
            testCase.verifyTrue(isfile(run.monthlyProfilesPath));
            testCase.verifyTrue(isfile(run.figurePath));
        end

        function testQualityModeMustMatchSourceManifest(testCase)
            operation = @() run_bahloul_monthly_v1( ...
                OutputRoot=testCase.TemporaryFolder, ...
                RunId="offline_quality_mismatch", ...
                QualityMode="short_gap_only", ...
                ExistingDailyMetricsPath=testCase.DailyMetricsPath, ...
                ExistingDailyManifestPath=testCase.DailyManifestPath, ...
                Solver=@unexpectedOfflineSolver, FigureVisible=false);

            testCase.verifyError(operation, ...
                "StoreNet:ExistingDailyQualityModeMismatch");
        end
    end
end

function daily = offlineDailyFixture()
strategies = ["SH_BM", "VPP_BM", "PS", "PSDT", "LL"];
sampleDays = [1, 2, 15, 16];
rowCount = 12 * numel(sampleDays) * numel(strategies);
Day = NaT(rowCount, 1);
Strategy = strings(rowCount, 1);
Status = strings(rowCount, 1);
ErrorIdentifier = strings(rowCount, 1);
ErrorMessage = strings(rowCount, 1);
WallTimeSeconds = nan(rowCount, 1);
PaperLoadOnlyBaselineBillEUR = nan(rowCount, 1);
PaperLoadOnlyPeakKW = nan(rowCount, 1);
PaperLoadOnlyDaytimePeakKW = nan(rowCount, 1);
BaselineBillEUR = nan(rowCount, 1);
OptimizedBillEUR = nan(rowCount, 1);
SavingsEUR = nan(rowCount, 1);
SavingsPercent = nan(rowCount, 1);
BaselinePeakImportKW = nan(rowCount, 1);
PeakImportKW = nan(rowCount, 1);
DaytimePeakImportKW = nan(rowCount, 1);
TotalGridImportKWh = nan(rowCount, 1);
TotalBatteryThroughputKWh = nan(rowCount, 1);
EnergyBalanceResidualKW = nan(rowCount, 1);
TerminalSocErrorKWh = nan(rowCount, 1);
SimultaneousChargeDischargeKW = nan(rowCount, 1);
MinimumExitFlag = nan(rowCount, 1);
rowIndex = 0;
for monthIndex = 1:12
    for sampleDay = sampleDays
        for strategy = strategies
            rowIndex = rowIndex + 1;
            Day(rowIndex) = datetime(2020, monthIndex, sampleDay);
            Strategy(rowIndex) = strategy;
            WallTimeSeconds(rowIndex) = rowIndex / 100;
            if sampleDay == 1
                Status(rowIndex) = "quality_rejected";
                ErrorIdentifier(rowIndex) = "StoreNet:QualityRejected";
                ErrorMessage(rowIndex) = "synthetic full-day rejection";
                continue
            end
            Status(rowIndex) = "ok";
            paperBill = 100 + monthIndex;
            pvSelfBill = 0.8 * paperBill;
            optimizedBill = 0.75 * paperBill;
            PaperLoadOnlyBaselineBillEUR(rowIndex) = paperBill;
            PaperLoadOnlyPeakKW(rowIndex) = 90 + monthIndex;
            PaperLoadOnlyDaytimePeakKW(rowIndex) = 70 + monthIndex;
            BaselineBillEUR(rowIndex) = pvSelfBill;
            OptimizedBillEUR(rowIndex) = optimizedBill;
            SavingsEUR(rowIndex) = pvSelfBill - optimizedBill;
            SavingsPercent(rowIndex) = 100 * ...
                SavingsEUR(rowIndex) / pvSelfBill;
            BaselinePeakImportKW(rowIndex) = 80 + monthIndex;
            PeakImportKW(rowIndex) = 60 + monthIndex;
            DaytimePeakImportKW(rowIndex) = 50 + monthIndex;
            TotalGridImportKWh(rowIndex) = 200 + monthIndex;
            TotalBatteryThroughputKWh(rowIndex) = 20 + monthIndex;
            EnergyBalanceResidualKW(rowIndex) = 1e-12;
            TerminalSocErrorKWh(rowIndex) = 0;
            SimultaneousChargeDischargeKW(rowIndex) = 0;
            MinimumExitFlag(rowIndex) = 1;
        end
    end
end
daily = table(Day, Strategy, Status, ErrorIdentifier, ErrorMessage, ...
    WallTimeSeconds, PaperLoadOnlyBaselineBillEUR, BaselineBillEUR, ...
    PaperLoadOnlyPeakKW, PaperLoadOnlyDaytimePeakKW, ...
    OptimizedBillEUR, SavingsEUR, SavingsPercent, ...
    BaselinePeakImportKW, PeakImportKW, DaytimePeakImportKW, ...
    TotalGridImportKWh, TotalBatteryThroughputKWh, ...
    EnergyBalanceResidualKW, TerminalSocErrorKWh, ...
    SimultaneousChargeDischargeKW, MinimumExitFlag);
end

function writeOfflineManifest(path, qualityMode)
manifest = struct(experiment=struct(qualityMode=qualityMode));
fileId = fopen(path, "wt", "n", "UTF-8");
assert(fileId >= 0, "Synthetic offline manifest could not be opened.");
cleaner = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s\n", jsonencode(manifest));
clear cleaner
end

function varargout = unexpectedOfflineDataProvider(varargin)
varargout = cell(1, nargout); %#ok<NASGU>
error("StoreNet:UnexpectedOfflineDataProvider", ...
    "Explicit paper baseline rows must not reload source data.");
end

function varargout = unexpectedOfflineSolver(varargin)
varargout = cell(1, nargout); %#ok<NASGU>
error("StoreNet:UnexpectedOfflineSolver", ...
    "Offline daily reuse must not invoke the solver.");
end
