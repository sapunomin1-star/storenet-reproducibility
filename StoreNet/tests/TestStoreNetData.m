classdef TestStoreNetData < matlab.unittest.TestCase
    %TESTSTORENETDATA Unit and release-integration tests for data ingestion.

    properties (SetAccess = private)
        FixtureRoot
        CompleteRoot
        StatusGapRoot
        MissingWhRoot
        Day
    end

    methods (TestClassSetup)
        function createReleaseShapedFixtures(testCase)
            import matlab.unittest.fixtures.PathFixture
            testFolder = fileparts(mfilename("fullpath"));
            projectRoot = fileparts(testFolder);
            testCase.applyFixture(PathFixture(fullfile(projectRoot, "src")));
            testCase.applyFixture(PathFixture(fullfile(testFolder, "helpers")));

            testCase.FixtureRoot = string(tempname);
            testCase.CompleteRoot = fullfile(testCase.FixtureRoot, "complete");
            testCase.StatusGapRoot = fullfile(testCase.FixtureRoot, "status-gap");
            testCase.MissingWhRoot = fullfile(testCase.FixtureRoot, "missing-wh");
            testCase.Day = datetime(2020, 1, 2);
            mkdir(testCase.FixtureRoot);
            testCase.addTeardown(@() rmdir(testCase.FixtureRoot, "s"));

            makeSyntheticData(testCase.CompleteRoot, testCase.Day, "complete");
            makeSyntheticData(testCase.StatusGapRoot, testCase.Day, "status-gap");
            makeSyntheticData(testCase.MissingWhRoot, testCase.Day, "missing-wh");
        end
    end

    methods (Test, TestTags = "Unit")
        function testCanonicalPaperParameters(testCase)
            cfg = storenet_config(DataRoot=testCase.CompleteRoot, ...
                IntervalMinutes=60, QualityMode="report");
            defaultCfg = storenet_config(DataRoot=testCase.CompleteRoot);

            testCase.verifyEqual(cfg.nHomes, 20);
            testCase.verifyEqual(cfg.pvHomes, ...
                ["H1", "H2", "H3", "H4", "H5", ...
                "H7", "H10", "H11", "H13", "H17"]);
            testCase.verifyEqual([cfg.etaPvAC, cfg.etaPvDC, ...
                cfg.etaBatteryCharge, cfg.etaBatteryDischarge], ...
                0.95 * ones(1, 4), AbsTol=1e-12);
            testCase.verifyEqual([cfg.batteryCapacityKWh, ...
                cfg.batteryPowerKW], [10, 3.3], AbsTol=1e-12);
            testCase.verifyEqual([cfg.socInitialFraction, ...
                cfg.socMinFraction, cfg.socMaxFraction], ...
                [0.1, 0.1, 0.9], AbsTol=1e-12);
            testCase.verifyEqual([cfg.nightPrice, cfg.dayPrice], ...
                [0.091, 0.194], AbsTol=1e-12);
            testCase.verifyEqual(cfg.intervalMinutes, 60);
            testCase.verifyEqual(cfg.dtHours, 1, AbsTol=1e-12);
            testCase.verifyEqual(cfg.qualityModeRequested, "report");
            testCase.verifyEqual(cfg.qualityMode, "release_literal");
            testCase.verifyEqual(cfg.quality.maxMissingStatusRunMinutes, 2);
            testCase.verifyEqual(cfg.quality.maxMissingStatusFraction, ...
                0.005, AbsTol=1e-12);
            testCase.verifyEqual(defaultCfg.qualityMode, "short_gap_only");
        end

        function testThirtyMinuteAggregationUsesIntervalEndLabels(testCase)
            [data, meta] = load_storenet_day(testCase.Day, ...
                DataRoot=testCase.CompleteRoot, IntervalMinutes=30);

            testCase.verifySize(data.loadKW, [48, 20]);
            testCase.verifyEqual(data.timeEnd([1, end]), ...
                [testCase.Day + minutes(30); testCase.Day + days(1)]);
            testCase.verifyEqual(data.loadKWh(:, 1), ...
                0.3 * ones(48, 1), AbsTol=1e-12);
            testCase.verifyEqual(data.loadKW(:, 1), ...
                0.6 * ones(48, 1), AbsTol=1e-12);
            testCase.verifyEqual(data.pvKW(:, 1), ...
                0.3 * ones(48, 1), AbsTol=1e-12);
            testCase.verifyEqual(data.pvKW(:, 6), ...
                zeros(48, 1), AbsTol=1e-12);
            testCase.verifyTrue(meta.isComplete);
            testCase.verifyTrue(meta.isFullyObserved);
            testCase.verifyTrue(meta.qualityPassed);
            testCase.verifyEqual(data.time, data.timeEnd);
            testCase.verifyEqual(data.houseIds, data.homeNames);
            testCase.verifySubstring(meta.intervalConvention, ...
                "(D 00:00, D+1 00:00]");
        end

        function testSixtyMinuteWhToMeanPowerConversion(testCase)
            data = load_storenet_day(testCase.Day, ...
                DataRoot=testCase.CompleteRoot, IntervalMinutes=60);

            testCase.verifySize(data.loadKW, [24, 20]);
            testCase.verifyEqual(data.loadKWh(:, 1), ...
                0.6 * ones(24, 1), AbsTol=1e-12);
            testCase.verifyEqual(data.loadKW(:, 1), ...
                0.6 * ones(24, 1), AbsTol=1e-12);
            testCase.verifyEqual(data.pvKWh(:, 1), ...
                0.3 * ones(24, 1), AbsTol=1e-12);
            testCase.verifyEqual(data.timeEnd(end), testCase.Day + days(1));
        end

        function testShortGapContractAcceptsOneMinuteStatusGap(testCase)
            [data, meta] = load_storenet_day(testCase.Day, ...
                DataRoot=testCase.StatusGapRoot, ...
                QualityMode="short_gap_only");

            testCase.verifyTrue(meta.qualityPassed);
            testCase.verifyEqual(meta.longestMissingStatusRunByHome(1), 1);
            testCase.verifyEqual(meta.missingStatusFractionByHome(1), ...
                1 / 1441, AbsTol=1e-12);
            testCase.verifyTrue(data.validForOptimization);
        end

        function testReportModeMarksGapAndPostGapBoundary(testCase)
            [data, meta] = load_storenet_day(testCase.Day, ...
                DataRoot=testCase.StatusGapRoot, QualityMode="report");

            testCase.verifyTrue(all(meta.binComplete(:, 1)));
            testCase.verifyFalse(meta.binObserved(24, 1));
            testCase.verifyFalse(meta.binObserved(25, 1));
            testCase.verifyEqual(meta.interpolatedMinutesByHome(1), 2);
            testCase.verifyEqual(data.loadKW([24, 25], 1), ...
                [0.6; 0.6], AbsTol=1e-12);
            testCase.verifyEqual(meta.qualityMode, "release_literal");
            testCase.verifyTrue(meta.qualityPassed);
            testCase.verifyTrue(data.validForOptimization);
        end

        function testMissingWhFailsStrictGate(testCase)
            operation = @() load_storenet_day(testCase.Day, ...
                DataRoot=testCase.MissingWhRoot, QualityMode="strict");

            testCase.verifyError(operation, ...
                "load_storenet_day:IncompleteDay");
        end

        function testReportModeLeavesIncompleteBinAsNaN(testCase)
            [data, meta] = load_storenet_day(testCase.Day, ...
                DataRoot=testCase.MissingWhRoot, QualityMode="report");

            testCase.verifyFalse(meta.binComplete(25, 1));
            testCase.verifyTrue(isnan(data.loadKW(25, 1)));
            testCase.verifyNotEqual(data.loadKW(25, 1), 0);
            testCase.verifyEqual(data.loadKW(25, 2), 0.6, AbsTol=1e-12);
            testCase.verifyEqual(meta.missingMinutesByHome(1), 1);
            testCase.verifyFalse(meta.qualityPassed);
            testCase.verifyFalse(data.validForOptimization);
        end

        function testExcludeFlaggedPvRejectsLongGenerationWindow(testCase)
            [data, meta] = load_storenet_day(testCase.Day, ...
                DataRoot=testCase.CompleteRoot, ...
                QualityMode="exclude_flagged_pv");

            testCase.verifyEqual(meta.pvWindowHours, 24, AbsTol=1e-12);
            testCase.verifyTrue(meta.pvLongWindowAnomaly);
            testCase.verifyGreaterThan(meta.pvWindowHours, ...
                meta.astronomicalDayLengthHours + 0.5);
            testCase.verifyFalse(meta.qualityPassed);
            testCase.verifySubstring(meta.qualityReasons(1), ...
                "pv_window_exceeds");
            testCase.verifyFalse(data.validForOptimization);
        end
    end

    methods (Test, TestTags = ["Integration", "Slow"])
        function testKnownReleaseQualityMarkers(testCase)
            testFolder = fileparts(mfilename("fullpath"));
            projectRoot = fileparts(testFolder);
            releaseRoot = fullfile(projectRoot, "data", "raw");

            report = audit_storenet_release(DataRoot=releaseRoot);
            h4 = report.summary(report.summary.Home == "H4", :);
            h14 = report.summary(report.summary.Home == "H14", :);
            h16 = report.summary(report.summary.Home == "H16", :);

            testCase.verifyEqual(h4.ExtraWColumnCount, 1);
            testCase.verifyEqual(h4.ExtraWColumnNames, "Unnamed: 6");
            testCase.verifyTrue(h14.HasTailTruncation);
            testCase.verifyEqual(h14.WEnd, ...
                datetime(2020, 12, 11, 23, 59, 0));
            testCase.verifyGreaterThan(h14.TailMissingMinutes, 20 * 24 * 60);
            testCase.verifyEqual(h16.LongestMissingStatusMinutes, 7978);
            testCase.verifyEqual(h16.LongestMissingStatusStart, ...
                datetime(2020, 11, 13, 0, 0, 0));
            testCase.verifyEqual(h16.LongestMissingStatusEnd, ...
                datetime(2020, 11, 18, 12, 57, 0));
            testCase.verifyGreaterThan(h16.InterpolatedIntervals, ...
                h16.MissingStatusRows);
            testCase.verifyEqual(report.knownIssues.Code, ...
                ["H4_W_EXTRA_COLUMN"; "H14_TAIL_TRUNCATION"; ...
                "H16_LONG_STATUS_GAP"]);
            testCase.verifySubstring(report.knownIssues.Detail(1), ...
                "populated for many rows");
            testCase.verifyTrue(report.postGapBoundaryIsMarked);
        end

        function testFrozenShortGapContractOnReleaseDates(testCase)
            testFolder = fileparts(mfilename("fullpath"));
            projectRoot = fileparts(testFolder);
            releaseRoot = fullfile(projectRoot, "data", "raw");

            [augustData, augustMeta] = load_storenet_day( ...
                datetime(2020, 8, 24), DataRoot=releaseRoot, ...
                QualityMode="short_gap_only");
            [juneData, juneMeta] = load_storenet_day( ...
                datetime(2020, 6, 10), DataRoot=releaseRoot, ...
                QualityMode="short_gap_only");
            [decemberData, decemberMeta] = load_storenet_day( ...
                datetime(2020, 12, 5), DataRoot=releaseRoot, ...
                QualityMode="exclude_flagged_pv");

            testCase.verifyTrue(augustMeta.qualityPassed);
            testCase.verifyTrue(augustData.validForOptimization);
            testCase.verifyEqual(augustMeta.longestMissingStatusRunByHome(1), 2);
            testCase.verifyFalse(juneMeta.qualityPassed);
            testCase.verifyFalse(juneData.validForOptimization);
            testCase.verifyEqual(juneMeta.longestMissingStatusRunByHome(19), 3);
            testCase.verifyTrue(any(contains(juneMeta.qualityReasons, "H19")));
            testCase.verifyTrue(any(contains(juneMeta.qualityReasons, ...
                "status_run_exceeds_2min")));
            testCase.verifyTrue(decemberMeta.pvLongWindowAnomaly);
            testCase.verifyGreaterThan(decemberMeta.pvWindowHours, ...
                decemberMeta.astronomicalDayLengthHours + 0.5);
            testCase.verifyFalse(decemberMeta.qualityPassed);
            testCase.verifyFalse(decemberData.validForOptimization);
        end
    end
end
