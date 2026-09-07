classdef TestBahloulTypicalV1 < matlab.unittest.TestCase
    %TESTBAHLOULTYPICALV1 Fast orchestration tests for the frozen runner.

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
        function makeTemporaryWorkspace(testCase)
            testCase.OutputRoot = string(tempname);
            mkdir(testCase.OutputRoot);
            testCase.addTeardown(@() rmdir(testCase.OutputRoot, "s"));
            testCase.DiagnosticsPath = fullfile(testCase.OutputRoot, "h4.csv");
            diagnostics = table("2020-08-24", ...
                "same_date_plus60_core", ...
                VariableNames=["Date", "AlignmentCategory"]);
            writetable(diagnostics, testCase.DiagnosticsPath);
        end
    end

    methods (Test)
        function testWritesPlannedMatrixObservedPairAndFigure(testCase)
            run = run_bahloul_typical_v1(datetime(2020, 8, 24), ...
                OutputRoot=testCase.OutputRoot, RunId="typical_fixture", ...
                H4DiagnosticsPath=testCase.DiagnosticsPath, ...
                DataProvider=@typicalDataProvider, ...
                Solver=@typicalSolver, FigureVisible=false);

            modelRows = run.metricsTable.ResultKind == ...
                "MODEL_STRUCTURAL_PROXY";
            observedRows = run.metricsTable.ResultKind == ...
                "OBSERVED_RELEASE_PROXY";
            actualModelKeys = sortrows(run.metricsTable(modelRows, ...
                ["ScenarioId", "Strategy"]), ["ScenarioId", "Strategy"]);
            expectedModelKeys = table( ...
                ["DC_XI007_H20"; "DC_XI007_H20"; "DC_XI007_H20"; ...
                "DC_XI007_H20"; "DC_XI007_H20"; "DC_XI007_H19"; ...
                "AC_XI007_H20"; "DC_XI000_H20"], ...
                ["SH_BM"; "VPP_BM"; "PS"; "PSDT"; "LL"; ...
                "VPP_BM"; "VPP_BM"; "VPP_BM"], ...
                VariableNames=["ScenarioId", "Strategy"]);
            expectedModelKeys = sortrows(expectedModelKeys, ...
                ["ScenarioId", "Strategy"]);
            testCase.verifyEqual(height(run.metricsTable), 10);
            testCase.verifyEqual(nnz(modelRows), 8);
            testCase.verifyEqual(nnz(observedRows), 2);
            testCase.verifyEqual(actualModelKeys, expectedModelKeys);
            testCase.verifyEqual(run.metricsTable.ScenarioId(observedRows), ...
                ["OBSERVED_RELEASE_H20_PV10"; ...
                "OBSERVED_RELEASE_H19_EXCL_H4_PV9"]);
            testCase.verifyEqual(run.metricsTable.PairId(observedRows), ...
                repmat("OBSERVED_RELEASE_PAIR", 2, 1));
            testCase.verifyEqual(run.metricsTable.PvBoundaryId(observedRows), ...
                repmat("OBSERVED_RELEASE_FIELDS", 2, 1));
            testCase.verifyTrue(all(isnan( ...
                run.metricsTable.TransferLossFraction(observedRows))));
            testCase.verifyTrue(all(isnan( ...
                run.metricsTable.CapacityRatio(observedRows))));
            testCase.verifyEqual( ...
                run.metricsTable.PaperSavingsPercentDenominatorIsZero( ...
                observedRows), zeros(2, 1));
            testCase.verifyEqual(run.metricsTable. ...
                ObservedReleaseEngineeringSavingsPercentDenominatorIsZero( ...
                observedRows), zeros(2, 1));
            testCase.verifyEqual(run.metricsTable.Status, repmat("ok", 10, 1));
            testCase.verifyEqual(nnz(run.metricsTable.CohortId == ...
                "H19_EXCL_H4_PV9"), 2);
            testCase.verifyEqual(unique(run.metricsTable.HouseCount( ...
                run.metricsTable.CohortId == "H19_EXCL_H4_PV9")), 19);
            testCase.verifyEqual(unique(run.metricsTable.PvHomeCount( ...
                run.metricsTable.CohortId == "H19_EXCL_H4_PV9")), 9);
            testCase.verifyEqual(height(run.profilesTable), 6 * 4);
            testCase.verifyEqual(unique(run.profilesTable.Strategy), ...
                ["LL"; "PS"; "PSDT"; "SB_SC"; "SH_BM"; "VPP_BM"]);
            testCase.verifyTrue(isfile(run.metricsPath));
            testCase.verifyTrue(isfile(run.profilesPath));
            testCase.verifyTrue(isfile(run.comparisonPath));
            testCase.verifyTrue(isfile(run.figurePath));
            testCase.verifyTrue(all(isfile(run.metricsTable.InputsPath)));
            testCase.verifyTrue(all(isfile(run.metricsTable.SolutionPath)));
            inputs = dir(fullfile(run.runDirectory, "cases", ...
                "DC_XI007_H20", "VPP_BM", "inputs_*.mat"));
            testCase.verifyEqual(numel(inputs), 1);
            observedCaseDirectory = fullfile(run.runDirectory, ...
                "observed_cases", "H20_PV10", "SB_SC");
            observedInputs = dir(fullfile(observedCaseDirectory, ...
                "inputs_*.mat"));
            observedSolutions = dir(fullfile(observedCaseDirectory, ...
                "solution_*.mat"));
            [observedMetrics, observedProfiles, observedEvidence] = ...
                reevaluate_bahloul_observed_artifact(observedCaseDirectory);
            testCase.verifyEqual(numel(observedInputs), 1);
            testCase.verifyEqual(numel(observedSolutions), 1);
            testCase.verifyTrue(isfile(fullfile(observedCaseDirectory, ...
                "profiles.csv")));
            testCase.verifyEqual(observedMetrics.observedBillEUR, ...
                observedEvidence.persistedMetrics.observedBillEUR, ...
                AbsTol=1e-12);
            testCase.verifyEqual(observedProfiles, ...
                observedEvidence.persistedProfiles);
            testCase.verifyTrue(all(strlength( ...
                run.metricsTable.SolutionSha256(observedRows)) == 64));

            modelProfile = run.profilesTable.Strategy == "VPP_BM";
            observedProfile = run.profilesTable.Strategy == "SB_SC";
            testCase.verifyEqual(run.profilesTable.PvKW(modelProfile), ...
                repmat(0.95, 4, 1), AbsTol=1e-12);
            testCase.verifyEqual(run.profilesTable.PvKW(observedProfile), ...
                ones(4, 1), AbsTol=1e-12);
            testCase.verifyEqual(run.comparisonTable.Strategy, ...
                ["SH_BM"; "VPP_BM"; "PS"; "PSDT"; "LL"; "SB_SC"]);
        end

        function testRetainsOnlyPlannedSolverFailureRow(testCase)
            run = run_bahloul_typical_v1(datetime(2020, 8, 24), ...
                OutputRoot=testCase.OutputRoot, RunId="typical_failure", ...
                H4DiagnosticsPath=testCase.DiagnosticsPath, ...
                DataProvider=@typicalDataProvider, ...
                Solver=@failingTypicalSolver, FigureVisible=false, ...
                PersistSolutions=false);

            failed = run.metricsTable.Status == "failed";
            testCase.verifyEqual(nnz(failed), 1);
            testCase.verifyEqual(run.metricsTable.Strategy(failed), ...
                "LL");
            testCase.verifyEqual(run.metricsTable.ErrorIdentifier(failed), ...
                "StoreNet:SyntheticFailure");
            testCase.verifyEqual(run.metricsTable.ScenarioId(failed), ...
                "DC_XI007_H20");
            testCase.verifyEqual(height(run.metricsTable), 10);
        end
    end
end

function [data, meta] = typicalDataProvider(day, options)
arguments
    day (1, 1) datetime
    options.DataRoot (1, 1) string = ""
    options.IntervalMinutes (1, 1) double = 30
    options.QualityMode (1, 1) string = "exclude_flagged_pv"
end
day = dateshift(day, "start", "day");
nIntervals = 4;
nHomes = 20;
pvMask = ismember(1:nHomes, [1, 2, 3, 4, 5, 7, 10, 11, 13, 17]);
data = struct;
data.day = day;
data.time = day + minutes(options.IntervalMinutes .* (1:nIntervals).');
data.dtHours = options.IntervalMinutes / 60;
data.houseIds = compose("H%d", 1:nHomes);
data.homeNames = data.houseIds;
data.pvHomeMask = pvMask;
data.loadKW = ones(nIntervals, nHomes);
data.pvKW = zeros(nIntervals, nHomes);
data.pvKW(:, pvMask) = 0.1;
data.pvKWh = data.pvKW .* data.dtHours;
data.fromGridKW = data.loadKW - min(data.loadKW, 0.95 .* data.pvKW);
data.fromGridKWh = data.fromGridKW .* data.dtHours;
data.chargeKW = zeros(nIntervals, nHomes);
data.dischargeKW = zeros(nIntervals, nHomes);
data.feedInKW = zeros(nIntervals, nHomes);
data.chargeKWh = data.chargeKW .* data.dtHours;
data.dischargeKWh = data.dischargeKW .* data.dtHours;
data.feedInKWh = data.feedInKW .* data.dtHours;
meta = struct("qualityPassed", true, "qualityReasons", strings(0, 1), ...
    "isComplete", true, "isFullyObserved", true);
end

function [solution, metrics] = typicalSolver(data, config, strategy)
nIntervals = size(data.loadKW, 1);
nHomes = size(data.loadKW, 2);
zeroFlow = zeros(nIntervals, nHomes);
solution = struct;
solution.strategy = string(strategy);
solution.pvToHomeKW = zeroFlow;
solution.pvToBatteryKW = zeroFlow;
solution.pvToGridKW = zeroFlow;
solution.pvCurtailKW = data.pvKW;
solution.gridToHomeKW = data.loadKW;
solution.gridToBatteryKW = zeroFlow;
solution.batteryToHomeKW = zeroFlow;
solution.batteryToGridKW = zeroFlow;
solution.socKWh = repmat(config.socInitialFraction .* ...
    config.batteryCapacityKWh, nIntervals + 1, nHomes);
solution.chargeOn = zeroFlow;
solution.dischargeOn = zeroFlow;
solution.batteryChargeKW = zeroFlow;
solution.batteryDischargeKW = zeroFlow;
solution.aggregateImportKW = sum(data.loadKW, 2);
solution.objectiveStages = struct("name", "synthetic", "value", 1, ...
    "solverObjective", 1, "exitFlag", 1, "relativeGap", 0, ...
    "message", "fixture");
solution.exitFlags = 1;
metrics = evaluate_storenet(data, config, solution);
solution.metrics = metrics;
end

function [solution, metrics] = failingTypicalSolver(data, config, strategy)
if string(strategy) == "LL"
    error("StoreNet:SyntheticFailure", "Synthetic LL failure.");
end
[solution, metrics] = typicalSolver(data, config, strategy);
end
