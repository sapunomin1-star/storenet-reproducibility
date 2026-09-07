classdef TestCrossEnvironmentAcceptance < matlab.unittest.TestCase
    %TESTCROSSENVIRONMENTACCEPTANCE Fail-closed acceptance-gate tests.

    properties (TestParameter)
        PrimaryFeasibilityFailure = struct( ...
            "nonfinitePeak", struct( ...
                "Variable", "PeakImportKW", "Value", NaN), ...
            "energyResidual", struct( ...
                "Variable", "EnergyBalanceResidualKW", "Value", 1e-3), ...
            "terminalSoc", struct( ...
                "Variable", "TerminalSocErrorKWh", "Value", -1e-3), ...
            "simultaneousOperation", struct( ...
                "Variable", "SimultaneousChargeDischargeKW", ...
                "Value", 1e-3), ...
            "exitFlag", struct( ...
                "Variable", "MinimumExitFlag", "Value", 0))

        FrontierFeasibilityFailure = struct( ...
            "nonfiniteBill", struct( ...
                "Variable", "OptimizedBillEUR", "Value", Inf), ...
            "energyResidual", struct( ...
                "Variable", "EnergyBalanceResidualKW", "Value", 1e-3), ...
            "terminalSoc", struct( ...
                "Variable", "TerminalSocErrorKWh", "Value", 1e-3), ...
            "simultaneousOperation", struct( ...
                "Variable", "SimultaneousChargeDischargeKW", ...
                "Value", 1e-3), ...
            "exitFlag", struct( ...
                "Variable", "MinimumExitFlag", "Value", 0))
    end

    methods (TestClassSetup)
        function addSourceFolder(testCase)
            testFolder = fileparts(mfilename("fullpath"));
            sourceFolder = fullfile(fileparts(testFolder), "src");
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                sourceFolder));
        end
    end

    methods (Test)
        function testAcceptsCompleteRobustEvidence(testCase)
            [primary, frontier, tolerances] = passingInputs();

            report = crossenv.evaluateExternalAcceptance( ...
                primary, frontier, tolerances);

            testCase.verifyTrue(report.overallCrossEnvironmentRobust);
            testCase.verifyTrue(all(cell2mat(struct2cell(report.criteria))));
            testCase.verifyEmpty(report.failureReasons);
            testCase.verifyEqual(report.statistics.primaryRowCount, 36);
            testCase.verifyEqual(report.statistics.peakGuardCapPassCount, 12);
            testCase.verifyEqual(report.statistics.frontierRowCount, 20);
            testCase.verifyEqual(report.statistics.frontierMonthCount, 4);
            testCase.verifyEqual(report.statistics.frontierComparisonCount, 16);
            testCase.verifyEqual( ...
                report.statistics.frontierMaximumBillDecreaseEUR, 0);
        end

        function testRejectsMissingToleranceField(testCase)
            [primary, frontier, tolerances] = passingInputs();
            tolerances = rmfield(tolerances, "capKW");

            report = crossenv.evaluateExternalAcceptance( ...
                primary, frontier, tolerances);

            testCase.verifyFalse(report.criteria.tolerancesValid);
            testCase.verifyFalse(report.overallCrossEnvironmentRobust);
            testCase.verifyTrue(any(contains( ...
                report.failureReasons, "missing required field")));
        end

        function testRejectsMissingPrimaryVariable(testCase)
            [primary, frontier, tolerances] = passingInputs();
            primary.Month = [];

            report = crossenv.evaluateExternalAcceptance( ...
                primary, frontier, tolerances);

            testCase.verifyFalse(report.criteria.primarySchemaValid);
            testCase.verifyFalse(report.overallCrossEnvironmentRobust);
            testCase.verifyTrue(any(contains(report.failureReasons, "Month")));
        end

        function testRejectsMissingPrimaryRow(testCase)
            [primary, frontier, tolerances] = passingInputs();
            primary(1, :) = [];

            report = crossenv.evaluateExternalAcceptance( ...
                primary, frontier, tolerances);

            testCase.verifyFalse(report.criteria.primaryPanelComplete);
            testCase.verifyEqual(report.statistics.primaryRowCount, 35);
            testCase.verifyFalse(report.overallCrossEnvironmentRobust);
        end

        function testRejectsDuplicatePrimaryStrategy(testCase)
            [primary, frontier, tolerances] = passingInputs();
            primary.Strategy(2) = primary.Strategy(1);

            report = crossenv.evaluateExternalAcceptance( ...
                primary, frontier, tolerances);

            testCase.verifyFalse(report.criteria.primaryPanelComplete);
            testCase.verifyFalse(report.overallCrossEnvironmentRobust);
        end

        function testRejectsMismatchedPrimaryDay(testCase)
            [primary, frontier, tolerances] = passingInputs();
            primary.Day(2) = primary.Day(2) + days(1);

            report = crossenv.evaluateExternalAcceptance( ...
                primary, frontier, tolerances);

            testCase.verifyFalse(report.criteria.primaryPanelComplete);
            testCase.verifyFalse(report.overallCrossEnvironmentRobust);
        end

        function testRejectsNonOkPrimaryStatus(testCase)
            [primary, frontier, tolerances] = passingInputs();
            primary.Status(1) = "failed";

            report = crossenv.evaluateExternalAcceptance( ...
                primary, frontier, tolerances);

            testCase.verifyFalse(report.criteria.primaryAllRowsFeasible);
            testCase.verifyFalse(report.overallCrossEnvironmentRobust);
        end

        function testRejectsPrimaryNumericalFailure( ...
                testCase, PrimaryFeasibilityFailure)
            [primary, frontier, tolerances] = passingInputs();
            primary = setTableValue(primary, ...
                PrimaryFeasibilityFailure.Variable, 1, ...
                PrimaryFeasibilityFailure.Value);

            report = crossenv.evaluateExternalAcceptance( ...
                primary, frontier, tolerances);

            testCase.verifyFalse(report.criteria.primaryAllRowsFeasible);
            testCase.verifyFalse(report.overallCrossEnvironmentRobust);
        end

        function testRejectsPeakGuardCapViolation(testCase)
            [primary, frontier, tolerances] = passingInputs();
            primary.PeakImportKW(3) = primary.EffectiveCapKW(3) + 0.1;

            report = crossenv.evaluateExternalAcceptance( ...
                primary, frontier, tolerances);

            testCase.verifyFalse(report.criteria.peakGuardCapCompliant);
            testCase.verifyEqual(report.statistics.peakGuardCapPassCount, 11);
            testCase.verifyFalse(report.overallCrossEnvironmentRobust);
        end

        function testRejectsNonpositivePeakGuardMedianSavings(testCase)
            [primary, frontier, tolerances] = passingInputs();
            primary = setPeakGuardSavings(primary, zeros(12, 1));

            report = crossenv.evaluateExternalAcceptance( ...
                primary, frontier, tolerances);

            testCase.verifyFalse( ...
                report.criteria.peakGuardMedianSavingsPositive);
            testCase.verifyFalse(report.overallCrossEnvironmentRobust);
        end

        function testRejectsNonpositivePeakGuardFirstQuartile(testCase)
            [primary, frontier, tolerances] = passingInputs();
            primary = setPeakGuardSavings(primary, [-ones(4, 1); ones(8, 1)]);

            report = crossenv.evaluateExternalAcceptance( ...
                primary, frontier, tolerances);

            testCase.verifyTrue( ...
                report.criteria.peakGuardMedianSavingsPositive);
            testCase.verifyFalse(report.criteria.peakGuardQ1SavingsPositive);
            testCase.verifyFalse(report.overallCrossEnvironmentRobust);
        end

        function testRejectsNonnegativePairedPeakDelta(testCase)
            [primary, frontier, tolerances] = passingInputs();
            primary = equalizeGuardAndVppPeaks(primary);

            report = crossenv.evaluateExternalAcceptance( ...
                primary, frontier, tolerances);

            testCase.verifyEqual( ...
                report.statistics.pairedMedianPeakDeltaKW, 0);
            testCase.verifyFalse( ...
                report.criteria.pairedMedianPeakDeltaNegative);
            testCase.verifyFalse(report.overallCrossEnvironmentRobust);
        end

        function testRejectsMissingFrontierAlphaRow(testCase)
            [primary, frontier, tolerances] = passingInputs();
            frontier(3, :) = [];

            report = crossenv.evaluateExternalAcceptance( ...
                primary, frontier, tolerances);

            testCase.verifyFalse(report.criteria.frontierPanelComplete);
            testCase.verifyEqual(report.statistics.frontierRowCount, 19);
            testCase.verifyFalse(report.overallCrossEnvironmentRobust);
        end

        function testRejectsDuplicateFrontierAlpha(testCase)
            [primary, frontier, tolerances] = passingInputs();
            frontier.Alpha(3) = frontier.Alpha(2);

            report = crossenv.evaluateExternalAcceptance( ...
                primary, frontier, tolerances);

            testCase.verifyFalse(report.criteria.frontierPanelComplete);
            testCase.verifyFalse(report.overallCrossEnvironmentRobust);
        end

        function testRejectsUnregisteredFrontierMonths(testCase)
            [primary, frontier, tolerances] = passingInputs();
            frontier = replaceFrontierMonth(frontier, 12, 11);

            report = crossenv.evaluateExternalAcceptance( ...
                primary, frontier, tolerances);

            testCase.verifyEqual(report.statistics.frontierMonthCount, 4);
            testCase.verifyFalse(report.criteria.frontierPanelComplete);
            testCase.verifyFalse(report.overallCrossEnvironmentRobust);
        end

        function testRejectsFrontierStrategyMismatch(testCase)
            [primary, frontier, tolerances] = passingInputs();
            frontier.Strategy(1) = "VPP_BM";

            report = crossenv.evaluateExternalAcceptance( ...
                primary, frontier, tolerances);

            testCase.verifyFalse(report.criteria.frontierPanelComplete);
            testCase.verifyFalse(report.overallCrossEnvironmentRobust);
        end

        function testRejectsNonOkFrontierStatus(testCase)
            [primary, frontier, tolerances] = passingInputs();
            frontier.Status(1) = "failed";

            report = crossenv.evaluateExternalAcceptance( ...
                primary, frontier, tolerances);

            testCase.verifyFalse(report.criteria.frontierAllRowsFeasible);
            testCase.verifyFalse(report.overallCrossEnvironmentRobust);
        end

        function testRejectsFrontierNumericalFailure( ...
                testCase, FrontierFeasibilityFailure)
            [primary, frontier, tolerances] = passingInputs();
            frontier = setTableValue(frontier, ...
                FrontierFeasibilityFailure.Variable, 1, ...
                FrontierFeasibilityFailure.Value);

            report = crossenv.evaluateExternalAcceptance( ...
                primary, frontier, tolerances);

            testCase.verifyFalse(report.criteria.frontierAllRowsFeasible);
            testCase.verifyFalse(report.overallCrossEnvironmentRobust);
        end

        function testRejectsFrontierCapViolation(testCase)
            [primary, frontier, tolerances] = passingInputs();
            frontier.PeakImportKW(1) = frontier.EffectiveCapKW(1) + 0.1;

            report = crossenv.evaluateExternalAcceptance( ...
                primary, frontier, tolerances);

            testCase.verifyFalse(report.criteria.frontierAllRowsFeasible);
            testCase.verifyEqual( ...
                report.statistics.frontierPeakCapPassCount, 19);
            testCase.verifyFalse(report.overallCrossEnvironmentRobust);
        end

        function testRejectsFrontierRequestedCapIncrease(testCase)
            [primary, frontier, tolerances] = passingInputs();
            frontier.RequestedCapKW(2:3) = [5; 6];

            report = crossenv.evaluateExternalAcceptance( ...
                primary, frontier, tolerances);

            testCase.verifyFalse( ...
                report.criteria.frontierRequestedCapsTighten);
            testCase.verifyFalse(report.overallCrossEnvironmentRobust);
        end

        function testRejectsFrontierPeakIncrease(testCase)
            [primary, frontier, tolerances] = passingInputs();
            frontier.PeakImportKW(2:3) = [5; 5.5];

            report = crossenv.evaluateExternalAcceptance( ...
                primary, frontier, tolerances);

            testCase.verifyTrue(report.criteria.frontierAllRowsFeasible);
            testCase.verifyFalse(report.criteria.frontierPeakMonotonic);
            testCase.verifyFalse(report.overallCrossEnvironmentRobust);
        end

        function testRejectsFrontierBillDecrease(testCase)
            [primary, frontier, tolerances] = passingInputs();
            frontier.OptimizedBillEUR(3) = 9;

            report = crossenv.evaluateExternalAcceptance( ...
                primary, frontier, tolerances);

            testCase.verifyTrue(report.criteria.frontierAllRowsFeasible);
            testCase.verifyFalse(report.criteria.frontierBillMonotonic);
            testCase.verifyEqual( ...
                report.statistics.frontierMaximumBillDecreaseEUR, 2);
            testCase.verifyFalse(report.overallCrossEnvironmentRobust);
        end
    end
end

function [primary, frontier, tolerances] = passingInputs()
strategies = repmat(["SH_BM"; "VPP_BM"; ...
    "IMPROVED_PEAK_GUARD"], 12, 1);
primaryMonths = repelem((1:12).', 3);
primaryDays = datetime(repmat(2024, 12, 1), (1:12).', ...
    repmat(15, 12, 1));
primaryDays = repelem(primaryDays, 3);
primaryStatus = repmat("ok", 36, 1);
primaryEffectiveCap = NaN(36, 1);
primaryEffectiveCap(strategies == "IMPROVED_PEAK_GUARD") = 6;
primaryPeak = repmat([10; 8; 6], 12, 1);
primarySavings = repmat([1; 4; 3], 12, 1);
primaryResidual = zeros(36, 1);
primaryTerminalError = zeros(36, 1);
primarySimultaneous = zeros(36, 1);
primaryExitFlag = ones(36, 1);
primary = table(primaryMonths, primaryDays, strategies, primaryStatus, ...
    primaryEffectiveCap, primaryPeak, primarySavings, primaryResidual, ...
    primaryTerminalError, primarySimultaneous, primaryExitFlag, ...
    VariableNames=["Month", "Day", "Strategy", "Status", ...
    "EffectiveCapKW", "PeakImportKW", "SavingsPercent", ...
    "EnergyBalanceResidualKW", "TerminalSocErrorKWh", ...
    "SimultaneousChargeDischargeKW", "MinimumExitFlag"]);

registeredMonths = [3; 6; 9; 12];
frontierMonths = repelem(registeredMonths, 5);
frontierBaseDays = datetime(repmat(2024, 4, 1), registeredMonths, ...
    repmat(15, 4, 1));
frontierDays = repelem(frontierBaseDays, 5);
frontierStrategies = repmat("IMPROVED_PEAK_GUARD", 20, 1);
frontierStatus = repmat("ok", 20, 1);
frontierAlpha = repmat([1; 0.75; 0.5; 0.25; 0], 4, 1);
frontierRequestedCap = repmat([10; 8; 6; 4; 2], 4, 1);
frontierEffectiveCap = frontierRequestedCap;
frontierPeak = repmat([9; 7; 5; 3; 1], 4, 1);
frontierSavings = repmat([4; 3.5; 3; 2.5; 2], 4, 1);
frontierResidual = zeros(20, 1);
frontierTerminalError = zeros(20, 1);
frontierSimultaneous = zeros(20, 1);
frontierExitFlag = ones(20, 1);
frontierBill = repmat([10; 11; 12; 13; 14], 4, 1);
frontier = table(frontierMonths, frontierDays, frontierStrategies, ...
    frontierStatus, frontierEffectiveCap, frontierPeak, frontierSavings, ...
    frontierResidual, frontierTerminalError, frontierSimultaneous, ...
    frontierExitFlag, frontierAlpha, frontierRequestedCap, frontierBill, ...
    VariableNames=["Month", "Day", "Strategy", "Status", ...
    "EffectiveCapKW", "PeakImportKW", "SavingsPercent", ...
    "EnergyBalanceResidualKW", "TerminalSocErrorKWh", ...
    "SimultaneousChargeDischargeKW", "MinimumExitFlag", "Alpha", ...
    "RequestedCapKW", "OptimizedBillEUR"]);

tolerances = struct;
tolerances.capKW = 1e-8;
tolerances.energyBalanceResidualKW = 1e-8;
tolerances.terminalSocErrorKWh = 1e-8;
tolerances.simultaneousChargeDischargeKW = 1e-8;
tolerances.peakMonotonicKW = 1e-8;
tolerances.billMonotonicEUR = 1e-8;
tolerances.alpha = 1e-10;
tolerances.minimumExitFlag = 1;
end

function outputTable = setTableValue(inputTable, variable, row, value)
outputTable = inputTable;
values = outputTable.(variable);
values(row) = value;
outputTable.(variable) = values;
end

function primary = setPeakGuardSavings(primary, savings)
peakGuardRows = primary.Strategy == "IMPROVED_PEAK_GUARD";
primary.SavingsPercent(peakGuardRows) = savings;
end

function primary = equalizeGuardAndVppPeaks(primary)
peakGuardRows = primary.Strategy == "IMPROVED_PEAK_GUARD";
vppRows = primary.Strategy == "VPP_BM";
primary.PeakImportKW(peakGuardRows) = primary.PeakImportKW(vppRows);
primary.EffectiveCapKW(peakGuardRows) = primary.PeakImportKW(vppRows);
end

function frontier = replaceFrontierMonth(frontier, oldMonth, newMonth)
rows = frontier.Month == oldMonth;
frontier.Month(rows) = newMonth;
frontier.Day(rows) = datetime(2024, newMonth, 15);
end
