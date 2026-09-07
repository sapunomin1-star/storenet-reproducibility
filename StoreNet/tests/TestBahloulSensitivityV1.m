classdef TestBahloulSensitivityV1 < matlab.unittest.TestCase
    %TESTBAHLOULSENSITIVITYV1 Tests frozen Figure 7 and Table I orchestration.

    properties
        OutputRoot
        DiagnosticsPath
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
        function createTemporaryWorkspace(testCase)
            testCase.OutputRoot = string(tempname);
            mkdir(testCase.OutputRoot);
            testCase.addTeardown(@() rmdir(testCase.OutputRoot, "s"));
            testCase.DiagnosticsPath = fullfile(testCase.OutputRoot, "h4.csv");
            writeDiagnostics(testCase.DiagnosticsPath);
            resetSensitivitySolverCounter();
            testCase.addTeardown(@resetSensitivitySolverCounter);
        end
    end

    methods (Test)
        function testWritesFrozenMatricesAndArtifacts(testCase)
            run = run_bahloul_sensitivity_v1(datetime(2020, 8, 24), ...
                OutputRoot=testCase.OutputRoot, RunId="unit", ...
                H4DiagnosticsPath=testCase.DiagnosticsPath, ...
                DataProvider=@mockDataProvider, Solver=@mockSolver, ...
                FigureVisible=false);
            figureRows = run.longTable( ...
                run.longTable.ExperimentId == "FIGURE_7", :);
            tableRows = run.longTable( ...
                run.longTable.ExperimentId == "TABLE_I", :);
            budgetCounts = sort(groupcounts(tableRows.BudgetId));
            requiredColumns = ["PaperLoadOnlyBaselineBillEUR", ...
                "PvSelfNoBatteryBaselineBillEUR", "EnergyBalanceResidualKW", ...
                "SocBoundViolationKWh", "StageExitFlags", ...
                "StageRelativeGaps", "H4MaskAffected"];
            nominalVppPrimary = run.tableIComparison.BudgetId == "NOMINAL" & ...
                run.tableIComparison.Strategy == "VPP_BM" & ...
                run.tableIComparison.IsPrimary;

            testCase.verifyEqual(height(run.longTable), 96);
            testCase.verifyEqual(height(figureRows), 81);
            testCase.verifyEqual(unique(figureRows.CapacityRatio), ...
                ((2:10) ./ 10).', AbsTol=1e-12);
            testCase.verifyEqual(unique(figureRows.PowerRatio), ...
                ((2:10) ./ 10).', AbsTol=1e-12);
            testCase.verifyEqual(unique(figureRows.Strategy), "VPP_BM");
            testCase.verifyEqual(unique(figureRows.ScenarioId), ...
                "DC_XI007_H20");
            testCase.verifyEqual(unique(figureRows.CohortId), "H20_PV10");
            testCase.verifyTrue(all(figureRows.IsPrimary));
            testCase.verifyEqual(height(tableRows), 15);
            testCase.verifyEqual(unique(tableRows.ScenarioId), ...
                "DC_XI007_H20");
            testCase.verifyEqual(budgetCounts, 5 .* ones(3, 1));
            testCase.verifyEqual(nnz(tableRows.IsPrimary), 15);
            testCase.verifyEqual(sort(unique(tableRows.BudgetId)), ...
                sort(["NOMINAL"; "POWER_20"; "CAPACITY_20"]));
            testCase.verifyEqual(run.longTable.Status, repmat("ok", 96, 1));
            testCase.verifyTrue(all(ismember(requiredColumns, ...
                string(run.longTable.Properties.VariableNames))));
            testCase.verifyEqual(figureRows.InputsPath, repmat("", 81, 1));
            testCase.verifyEqual(figureRows.SolutionPath, repmat("", 81, 1));
            testCase.verifyEqual(figureRows.CaseDirectory, repmat("", 81, 1));
            testCase.verifyTrue(all(isfile(tableRows.InputsPath)));
            testCase.verifyTrue(all(isfile(tableRows.SolutionPath)));
            testCase.verifyTrue(all(isfile(tableRows.StagesPath)));
            testCase.verifyTrue(all(isfile(tableRows.MetricsPath)));
            testCase.verifyEqual(height(run.tableIComparison), 15);
            testCase.verifyEqual(height(run.figure7Trend), 1);
            testCase.verifyEqual(run.figure7Trend.SensitivityRole, "PRIMARY");
            testCase.verifyEqual( ...
                run.tableIComparison.PaperTargetSavingsPercent( ...
                nominalVppPrimary), 45.85, AbsTol=1e-12);
            testCase.verifyTrue(isfile(run.longPath));
            testCase.verifyTrue(isfile(run.tableIPath));
            testCase.verifyTrue(isfile(run.figure7Path));
            checkpoint = readtable(run.longPath);
            testCase.verifyEqual(height(checkpoint), 96);
            testCase.verifyEqual(sensitivitySolverCallCount(), 96);
        end

        function testReusesValidatedLegacyFiveByFiveGrid(testCase)
            testFolder = fileparts(mfilename("fullpath"));
            legacyPath = fullfile(fileparts(testFolder), "results", ...
                "sensitivity_20200824_vppbm", "sensitivity.csv");
            run = run_bahloul_sensitivity_v1(datetime(2020, 8, 24), ...
                OutputRoot=testCase.OutputRoot, RunId="legacy_reuse", ...
                QualityMode="release_literal", ...
                H4DiagnosticsPath=testCase.DiagnosticsPath, ...
                ReuseFigure7Csv=legacyPath, ...
                DataProvider=@legacyCompatibleDataProvider, ...
                Solver=@mockSolver, ...
                FigureVisible=false);
            figureRows = run.longTable( ...
                run.longTable.ExperimentId == "FIGURE_7", :);
            nominal = figureRows.CapacityRatio == 1 & ...
                figureRows.PowerRatio == 1;
            legacyRatios = (2:2:10) ./ 10;
            legacyCells = ismembertol(figureRows.CapacityRatio, ...
                legacyRatios, 1e-12) & ...
                ismembertol(figureRows.PowerRatio, legacyRatios, 1e-12);

            testCase.verifyEqual(sensitivitySolverCallCount(), 56 + 15);
            testCase.verifyEqual(nnz(legacyCells), 25);
            testCase.verifyEqual( ...
                figureRows.PaperLoadOnlyBaselineBillEUR(nominal), ...
                36.671172405, AbsTol=1e-12);
            testCase.verifyEqual(figureRows.OptimizedBillEUR(nominal), ...
                19.558045178632, AbsTol=1e-12);
            expectedSavings = 100 .* ...
                (36.671172405 - 19.558045178632) ./ 36.671172405;
            testCase.verifyEqual( ...
                figureRows.PaperLoadOnlySavingsPercent(nominal), ...
                expectedSavings, AbsTol=1e-12);
            testCase.verifyEqual( ...
                figureRows.PvSelfNoBatteryBaselineBillEUR(nominal), ...
                33.29714113, AbsTol=1e-12);
            testCase.verifyEqual(figureRows.InputsPath, repmat("", 81, 1));
            testCase.verifyEqual(figureRows.SolutionPath, repmat("", 81, 1));
        end

        function testRefusesNonemptyRunDirectory(testCase)
            runDirectory = fullfile(testCase.OutputRoot, "existing");
            mkdir(runDirectory);
            writelines("do not overwrite", fullfile(runDirectory, "marker.txt"));
            operation = @() run_bahloul_sensitivity_v1( ...
                datetime(2020, 8, 24), OutputRoot=testCase.OutputRoot, ...
                RunId="existing", H4DiagnosticsPath=testCase.DiagnosticsPath, ...
                DataProvider=@mockDataProvider, Solver=@mockSolver);

            testCase.verifyError(operation, "StoreNet:RunDirectoryExists");
        end
    end
end

function writeDiagnostics(path)
diagnostics = table("2020-08-24", "same_date_plus60_core", ...
    VariableNames=["Date", "AlignmentCategory"]);
writetable(diagnostics, path);
end

function [data, meta] = mockDataProvider(day, options)
arguments
    day (1, 1) datetime
    options.DataRoot (1, 1) string = ""
    options.IntervalMinutes (1, 1) double = 30
    options.QualityMode (1, 1) string = "exclude_flagged_pv"
end

data = struct;
data.day = dateshift(day, "start", "day");
data.time = data.day + minutes(options.IntervalMinutes .* (1:2).');
data.dtHours = options.IntervalMinutes ./ 60;
data.houseIds = compose("H%d", 1:20);
data.homeNames = data.houseIds;
data.loadKW = ones(2, 20);
data.pvKW = zeros(2, 20);
pvHomes = [1, 2, 3, 4, 5, 7, 10, 11, 13, 17];
data.pvKW(:, pvHomes) = 0.5;
data.pvHomeMask = any(data.pvKW > 0, 1);
meta = struct("qualityPassed", true, "qualityReasons", strings(0, 1));
end

function [data, meta] = legacyCompatibleDataProvider(day, options)
arguments
    day (1, 1) datetime
    options.DataRoot (1, 1) string = ""
    options.IntervalMinutes (1, 1) double = 30
    options.QualityMode (1, 1) string = "exclude_flagged_pv"
end
testFolder = fileparts(mfilename("fullpath"));
profilePath = fullfile(fileparts(testFolder), "results", ...
    "baseline_typical_20200824_v2", "profiles.csv");
profiles = readtable(profilePath, TextType="string");
aggregateLoadKW = double(profiles.AggregateLoadKW);
pvSelfImportKW = double(profiles.NoBatteryPvSelfImportKW);
data = struct;
data.day = dateshift(day, "start", "day");
data.time = datetime(string(profiles.Time), ...
    InputFormat="dd-MMM-yyyy HH:mm:ss", Locale="en_US");
data.dtHours = options.IntervalMinutes ./ 60;
data.houseIds = compose("H%d", 1:20);
data.homeNames = data.houseIds;
data.loadKW = zeros(numel(data.time), 20);
data.loadKW(:, 1) = aggregateLoadKW;
data.pvKW = zeros(size(data.loadKW));
data.pvKW(:, 1) = (aggregateLoadKW - pvSelfImportKW) ./ 0.95;
data.pvHomeMask = ismember(1:20, [1, 2, 3, 4, 5, 7, 10, 11, 13, 17]);
meta = struct("qualityPassed", true, "qualityReasons", strings(0, 1));
end

function [solution, metrics] = mockSolver(data, config, strategy)
incrementSensitivitySolverCounter();
strategyAdjustment = strategyValue(strategy);
cohortAdjustment = 0.1 .* (numel(data.houseIds) == 19);
savingsPercent = 30 + 5 .* config.capacityRatio + ...
    2 .* config.powerRatio + strategyAdjustment - cohortAdjustment;
paperBillEUR = 100;
optimizedBillEUR = paperBillEUR .* (1 - savingsPercent ./ 100);
pvSelfBillEUR = 80;

paper = baselineMetrics("paper", paperBillEUR, optimizedBillEUR, 20);
pvSelf = baselineMetrics("pv-self", pvSelfBillEUR, optimizedBillEUR, 15);
metrics = completeMetrics(paper, pvSelf, optimizedBillEUR);
solution = struct;
solution.aggregateImportKW = [10; 9];
solution.objectiveStages = struct("name", "billEUR", ...
    "value", optimizedBillEUR, "solverObjective", optimizedBillEUR, ...
    "exitFlag", 1, "relativeGap", 1e-6, "message", "mock");
end

function value = strategyValue(strategy)
switch strategy
    case "SH_BM"
        value = 1;
    case "VPP_BM"
        value = 5;
    case "PS"
        value = -1;
    case "PSDT"
        value = 3;
    case "LL"
        value = -2;
    otherwise
        error("StoreNet:UnknownMockStrategy", "Unknown strategy: %s", strategy);
end
end

function baseline = baselineMetrics(definition, billEUR, optimizedBillEUR, peakKW)
baseline = struct;
baseline.definition = definition;
baseline.billEUR = billEUR;
baseline.peakImportKW = peakKW;
baseline.daytimePeakImportKW = peakKW - 1;
baseline.savingsEUR = billEUR - optimizedBillEUR;
baseline.savingsPercent = 100 .* baseline.savingsEUR ./ billEUR;
baseline.savingsPercentDenominatorIsZero = false;
end

function metrics = completeMetrics(paper, pvSelf, optimizedBillEUR)
metrics = struct;
metrics.PaperLoadOnlyBaseline = paper;
metrics.PvSelfNoBatteryBaseline = pvSelf;
metrics.optimizedBillEUR = optimizedBillEUR;
metrics.peakImportKW = 10;
metrics.daytimePeakImportKW = 9;
metrics.importSpreadKW = 1;
metrics.totalGridImportKWh = 9.5;
metrics.totalBatteryThroughputKWh = 2;
metrics.totalCurtailedPvKWh = 0.5;
metrics.totalSharedExportKWh = 1;
metrics.energyBalanceResidualKW = 0;
metrics.pvAllocationResidualKW = 0;
metrics.homeBalanceResidualKW = 0;
metrics.batteryDynamicsResidualKW = 0;
metrics.aggregateImportResidualKW = 0;
metrics.chargeConversionResidualKW = 0;
metrics.dischargeConversionResidualKW = 0;
metrics.initialSocErrorKWh = 0;
metrics.terminalSocErrorKWh = 0;
metrics.socBoundViolationKWh = 0;
metrics.chargePowerViolationKW = 0;
metrics.dischargePowerViolationKW = 0;
metrics.aggregateImportNonnegativeViolationKW = 0;
metrics.simultaneousChargeDischargeKW = 0;
metrics.simultaneousChargeDischargeCount = 0;
metrics.maximumLexicographicViolation = 0;
end

function resetSensitivitySolverCounter()
setappdata(groot, "BahloulSensitivitySolverCalls", 0);
end

function incrementSensitivitySolverCounter()
setappdata(groot, "BahloulSensitivitySolverCalls", ...
    sensitivitySolverCallCount() + 1);
end

function count = sensitivitySolverCallCount()
if isappdata(groot, "BahloulSensitivitySolverCalls")
    count = getappdata(groot, "BahloulSensitivitySolverCalls");
else
    count = 0;
end
end
