classdef TestCrossEnvironmentData < matlab.unittest.TestCase
    %TESTCROSSENVIRONMENTDATA Ausgrid adapter and selection contracts.

    properties (SetAccess = private)
        FixtureRoot
        ValidFixture
        BadQualityFixture
        MissingRequiredFixture
        DuplicateRequiredFixture
        DuplicateOptionalFixture
        NegativeFixture
        MissingIntervalFixture
    end

    methods (TestClassSetup)
        function createAusgridFixtures(testCase)
            import matlab.unittest.fixtures.PathFixture
            testFolder = fileparts(mfilename("fullpath"));
            projectRoot = fileparts(testFolder);
            testCase.applyFixture(PathFixture(fullfile(projectRoot, "src")));
            testCase.applyFixture(PathFixture(fullfile(testFolder, "helpers")));

            testCase.FixtureRoot = string(tempname);
            mkdir(testCase.FixtureRoot);
            testCase.addTeardown(@() rmdir(testCase.FixtureRoot, "s"));
            testCase.ValidFixture = writeAusgridFixture(fullfile( ...
                testCase.FixtureRoot, "valid"), Mode="valid");
            testCase.BadQualityFixture = writeAusgridFixture(fullfile( ...
                testCase.FixtureRoot, "bad-quality"), Mode="bad-quality");
            testCase.MissingRequiredFixture = writeAusgridFixture(fullfile( ...
                testCase.FixtureRoot, "missing-required"), ...
                Mode="missing-required");
            testCase.DuplicateRequiredFixture = writeAusgridFixture(fullfile( ...
                testCase.FixtureRoot, "duplicate-required"), ...
                Mode="duplicate-required");
            testCase.DuplicateOptionalFixture = writeAusgridFixture(fullfile( ...
                testCase.FixtureRoot, "duplicate-optional"), ...
                Mode="duplicate-optional");
            testCase.NegativeFixture = writeAusgridFixture(fullfile( ...
                testCase.FixtureRoot, "negative"), Mode="negative");
            testCase.MissingIntervalFixture = writeAusgridFixture(fullfile( ...
                testCase.FixtureRoot, "missing-interval"), ...
                Mode="missing-interval");
        end
    end

    methods (Test, TestTags = "Unit")
        function testSpecSupportsPositionalAndNamedPath(testCase)
            positional = crossenv.loadAusgridSpec( ...
                testCase.ValidFixture.SpecPath);
            named = crossenv.loadAusgridSpec( ...
                SpecPath=testCase.ValidFixture.SpecPath);

            testCase.verifyEqual(positional.specPath, named.specPath);
            testCase.verifyEqual(positional.analysisCustomerIds, [101, 102]);
            testCase.verifyEqual(positional.dtHours, 0.5, AbsTol=1e-12);
            testCase.verifyEqual(positional.analysisStartDay, ...
                datetime(2012, 7, 1));
            testCase.verifyEqual(positional.analysisEndDay, ...
                datetime(2013, 6, 30));
            testCase.verifyTrue(positional.pvIsAC);
            testCase.verifyEqual(positional.pvMeasurementBasis, ...
                "inverter-AC");
        end

        function testCanonicalShapeUnitsControlledLoadAndTime(testCase)
            spec = crossenv.loadAusgridSpec( ...
                testCase.ValidFixture.SpecPath);
            yearData = crossenv.adapters.readAusgridYear(spec, ...
                SourceFile=testCase.ValidFixture.SourceFile, ...
                VerifySha256=false);
            [data, meta] = crossenv.adapters.loadAusgridDay( ...
                datetime(2012, 7, 1), spec, ...
                SourceFile=testCase.ValidFixture.SourceFile, ...
                VerifySha256=false);

            testCase.verifySize(yearData.days, [365, 1]);
            testCase.verifySize(yearData.loadKW, [48, 2, 365]);
            testCase.verifySize(yearData.pvKW, [48, 2, 365]);
            testCase.verifyEqual(yearData.customerIds, [101, 102]);
            testCase.verifyEqual(yearData.houseIds, ["AUS101", "AUS102"]);
            testCase.verifyEqual(yearData.generatorCapacityKW, [3.5, 4], ...
                AbsTol=1e-12);
            testCase.verifyEqual(yearData.source.sourceRowCount, 1825);
            testCase.verifyFalse(yearData.source.sha256Verified);
            testCase.verifyTrue(all(yearData.qualityPassed));
            testCase.verifyEqual(data.loadKW(:, 1), 1.5 * ones(48, 1), ...
                AbsTol=1e-12);
            testCase.verifyEqual(data.loadKW(:, 2), ones(48, 1), ...
                AbsTol=1e-12);
            testCase.verifyEqual(data.pvKW, 0.2 * ones(48, 2), ...
                AbsTol=1e-12);
            testCase.verifyEqual(data.time([1, end]), ...
                [datetime(2012, 7, 1, 0, 30, 0); datetime(2012, 7, 2)]);
            testCase.verifyEqual(data.time, data.timeEnd);
            testCase.verifyEqual(data.dtHours, 0.5, AbsTol=1e-12);
            testCase.verifyTrue(data.validForOptimization);
            testCase.verifyTrue(meta.qualityPassed);
            testCase.verifyTrue(meta.pvIsAC);
            testCase.verifyEqual(meta.etaPvAC, 1, AbsTol=1e-12);
        end

        function testNonblankRowQualityRejectsWholeDay(testCase)
            spec = crossenv.loadAusgridSpec( ...
                testCase.BadQualityFixture.SpecPath);
            yearData = crossenv.adapters.readAusgridYear(spec, ...
                VerifySha256=false);
            [data, meta] = crossenv.adapters.loadAusgridDay( ...
                testCase.BadQualityFixture.TargetDay, spec, ...
                VerifySha256=false);

            testCase.verifyEqual(nnz(yearData.qualityPassed), 364);
            testCase.verifyFalse(data.validForOptimization);
            testCase.verifyFalse(meta.qualityPassed);
            testCase.verifySubstring(meta.rejectionReasons, ...
                "row_quality=NA");
        end

        function testMissingRequiredCategoryIsNotZeroFilled(testCase)
            spec = crossenv.loadAusgridSpec( ...
                testCase.MissingRequiredFixture.SpecPath);
            [data, meta] = crossenv.adapters.loadAusgridDay( ...
                testCase.MissingRequiredFixture.TargetDay, spec, ...
                VerifySha256=false);

            testCase.verifyFalse(data.validForOptimization);
            testCase.verifyTrue(all(isnan(data.pvKW(:, 2))));
            testCase.verifySubstring(meta.rejectionReasons, ...
                "category=GG,reason=missing_required");
        end

        function testDuplicateRequiredCategoryRejectsDay(testCase)
            spec = crossenv.loadAusgridSpec( ...
                testCase.DuplicateRequiredFixture.SpecPath);
            [data, meta] = crossenv.adapters.loadAusgridDay( ...
                testCase.DuplicateRequiredFixture.TargetDay, spec, ...
                VerifySha256=false);

            testCase.verifyFalse(data.validForOptimization);
            testCase.verifySubstring(meta.rejectionReasons, ...
                "category=GC,reason=duplicate_required");
        end

        function testDuplicateOptionalControlledLoadRejectsDay(testCase)
            spec = crossenv.loadAusgridSpec( ...
                testCase.DuplicateOptionalFixture.SpecPath);
            [data, meta] = crossenv.adapters.loadAusgridDay( ...
                testCase.DuplicateOptionalFixture.TargetDay, spec, ...
                VerifySha256=false);

            testCase.verifyFalse(data.validForOptimization);
            testCase.verifySubstring(meta.rejectionReasons, ...
                "category=CL,reason=duplicate_optional");
        end

        function testNegativeIntervalRejectsDay(testCase)
            spec = crossenv.loadAusgridSpec( ...
                testCase.NegativeFixture.SpecPath);
            [data, meta] = crossenv.adapters.loadAusgridDay( ...
                testCase.NegativeFixture.TargetDay, spec, ...
                VerifySha256=false);

            testCase.verifyFalse(data.validForOptimization);
            testCase.verifyEqual(data.pvKW(1, 1), -0.2, AbsTol=1e-12);
            testCase.verifySubstring(meta.rejectionReasons, ...
                "reason=negative_interval");
        end

        function testMissingIntervalRejectsDayWithoutImputation(testCase)
            spec = crossenv.loadAusgridSpec( ...
                testCase.MissingIntervalFixture.SpecPath);
            [data, meta] = crossenv.adapters.loadAusgridDay( ...
                testCase.MissingIntervalFixture.TargetDay, spec, ...
                VerifySha256=false);

            testCase.verifyFalse(data.validForOptimization);
            testCase.verifyTrue(isnan(data.pvKW(7, 1)));
            testCase.verifySubstring(meta.rejectionReasons, ...
                "reason=nonfinite_interval");
        end

        function testAuditReturnsExactContractFields(testCase)
            spec = crossenv.loadAusgridSpec( ...
                testCase.BadQualityFixture.SpecPath);
            yearData = crossenv.adapters.readAusgridYear(spec, ...
                VerifySha256=false);
            audit = crossenv.auditAusgridYear(yearData);

            testCase.verifyEqual(string(fieldnames(audit)), ...
                ["sourceRowCount"; "houseCount"; "calendarDayCount"; ...
                "validDayCount"; "rejectedDayCount"; "rejectedDays"; ...
                "rejectionReasons"]);
            testCase.verifyEqual(audit.sourceRowCount, 1825);
            testCase.verifyEqual(audit.houseCount, 2);
            testCase.verifyEqual(audit.calendarDayCount, 365);
            testCase.verifyEqual(audit.validDayCount, 364);
            testCase.verifyEqual(audit.rejectedDayCount, 1);
            testCase.verifyEqual(audit.rejectedDays, ...
                testCase.BadQualityFixture.TargetDay);
            testCase.verifySubstring(audit.rejectionReasons, ...
                "row_quality=NA");
        end

        function testMonthlySelectionUsesZeroMadAndEarliestTie(testCase)
            spec = crossenv.loadAusgridSpec( ...
                testCase.ValidFixture.SpecPath);
            yearData = crossenv.adapters.readAusgridYear(spec, ...
                VerifySha256=false);
            [selection, ranking] = crossenv.selectMonthlyDays(yearData);
            expectedDays = datetime( ...
                [2013 * ones(1, 6), 2012 * ones(1, 6)], 1:12, 1).';
            expectedCounts = [31; 28; 31; 30; 31; 30; ...
                31; 31; 30; 31; 30; 31];

            testCase.verifyEqual(string(selection.Properties.VariableNames), ...
                ["Month", "Day", "Score", "CandidateCount"]);
            testCase.verifyEqual(string(ranking.Properties.VariableNames), ...
                ["Month", "Day", "Score", "Selected"]);
            testCase.verifyEqual(selection.Month, (1:12).');
            testCase.verifyEqual(selection.Day, expectedDays);
            testCase.verifyEqual(selection.Score, zeros(12, 1), ...
                AbsTol=1e-12);
            testCase.verifyEqual(selection.CandidateCount, expectedCounts);
            testCase.verifyEqual(height(ranking), 365);
            testCase.verifyEqual(nnz(ranking.Selected), 12);
            testCase.verifyEqual(ranking.Score, zeros(365, 1), ...
                AbsTol=1e-12);
        end
    end

    methods (Test, TestTags = ["Integration", "Slow"])
        function testActualReleaseCountsAndMonthlySelections(testCase)
            spec = crossenv.loadAusgridSpec();
            yearData = crossenv.adapters.readAusgridYear(spec);
            audit = crossenv.auditAusgridYear(yearData);
            [selection, ranking] = crossenv.selectMonthlyDays(yearData);
            expectedRejectedDays = datetime( ...
                [2013, 2013, 2013, 2013, 2013, 2013], ...
                [1, 1, 1, 4, 4, 4], [9, 10, 31, 16, 17, 26]).';
            expectedSelectedDays = datetime( ...
                [2013 * ones(1, 6), 2012 * ones(1, 6)], 1:12, ...
                [21, 15, 12, 28, 21, 5, 3, 17, 6, 19, 12, 21]).';

            testCase.verifyEqual(audit.sourceRowCount, 268557);
            testCase.verifyEqual(audit.houseCount, 53);
            testCase.verifyEqual(audit.calendarDayCount, 365);
            testCase.verifyEqual(audit.validDayCount, 359);
            testCase.verifyEqual(audit.rejectedDayCount, 6);
            testCase.verifyEqual(audit.rejectedDays, expectedRejectedDays);
            testCase.verifyEqual(selection.Month, (1:12).');
            testCase.verifyEqual(selection.Day, expectedSelectedDays);
            testCase.verifyEqual(height(ranking), 359);
            testCase.verifyEqual(nnz(ranking.Selected), 12);
            testCase.verifyTrue(yearData.source.sha256Verified);
            testCase.verifyEqual(yearData.source.sourceSha256, ...
                lower(string(spec.sourceFileSha256)));
        end
    end
end
