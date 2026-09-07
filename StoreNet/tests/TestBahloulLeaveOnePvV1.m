classdef TestBahloulLeaveOnePvV1 < matlab.unittest.TestCase
    %TESTBAHLOULLEAVEONEPVV1 Tests the frozen unknown-9-PV experiment.

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
        end
    end

    methods (Test)
        function testRunsTenDistinctRemovedPvCasesAndReference(testCase)
            run = run_bahloul_leave_one_pv_v1(datetime(2020, 8, 24), ...
                OutputRoot=testCase.OutputRoot, RunId="leave_one", ...
                H4DiagnosticsPath=testCase.DiagnosticsPath, ...
                DataProvider=@leaveOneDataProvider, ...
                Solver=@leaveOneSolver, FigureVisible=false);
            leaveRows = run.metricsTable.IsLeaveOnePv;
            referenceRows = ~run.metricsTable.IsLeaveOnePv;
            h4Removed = run.metricsTable.RemovedPvHomeId == "H4";
            h4Input = load(run.metricsTable.InputsPath(h4Removed), ...
                "inputEvidence");
            h4Column = h4Input.inputEvidence.houseIds == "H4";
            expectedRemoved = ["H1"; "H2"; "H3"; "H4"; "H5"; ...
                "H7"; "H10"; "H11"; "H13"; "H17"];

            testCase.verifyEqual(height(run.metricsTable), 11);
            testCase.verifyEqual(nnz(leaveRows), 10);
            testCase.verifyEqual(nnz(referenceRows), 1);
            testCase.verifyEqual(run.metricsTable.SensitivityRole(referenceRows), ...
                "REFERENCE_FULL_PV");
            testCase.verifyEqual(run.metricsTable.RemovedPvHomeId(leaveRows), ...
                expectedRemoved);
            testCase.verifyEqual(numel(unique( ...
                run.metricsTable.RemovedPvHomeId(leaveRows))), 10);
            testCase.verifyEqual(run.metricsTable.CohortId, ...
                repmat("H20_PV10", 11, 1));
            testCase.verifyFalse(any(run.metricsTable.CohortId == ...
                "H19_EXCL_H4_PV9"));
            testCase.verifyEqual(run.metricsTable.HouseCount, ...
                20 .* ones(11, 1));
            testCase.verifyEqual(run.metricsTable.BatteryCount, ...
                20 .* ones(11, 1));
            testCase.verifyEqual(run.metricsTable.ReleasePvHomeCount, ...
                10 .* ones(11, 1));
            testCase.verifyEqual(run.metricsTable.ActivePvHomeCount(leaveRows), ...
                9 .* ones(10, 1));
            testCase.verifyEqual(run.metricsTable.ActivePvHomeCount(referenceRows), 10);
            testCase.verifyEqual(run.metricsTable.PvBoundaryId, ...
                repmat("DC_SOURCE", 11, 1));
            testCase.verifyEqual(run.metricsTable.TransferLossFraction, ...
                0.07 .* ones(11, 1), AbsTol=1e-12);
            testCase.verifyEqual(run.metricsTable.Strategy, ...
                repmat("VPP_BM", 11, 1));
            testCase.verifyEqual(run.metricsTable.Status, repmat("ok", 11, 1));
            testCase.verifyTrue(all(run.metricsTable.ReleasedPvPreserved));
            testCase.verifyEqual(run.metricsTable.RemovedModelPvMaxAbsKW(leaveRows), ...
                zeros(10, 1), AbsTol=1e-12);
            testCase.verifyTrue(all( ...
                run.metricsTable.RemovedReleasedPvMaxKW(leaveRows) > 0));
            testCase.verifyEqual(numel(h4Input.inputEvidence.houseIds), 20);
            testCase.verifyTrue(any(h4Column));
            testCase.verifyEqual(h4Input.inputEvidence.modelPvAvailableKW(:, h4Column), ...
                zeros(4, 1), AbsTol=1e-12);
            testCase.verifyGreaterThan( ...
                max(h4Input.inputEvidence.releasedPvKW(:, h4Column)), 0);
            testCase.verifyEqual(h4Input.inputEvidence.config.nHomes, 20);
            testCase.verifyEqual( ...
                h4Input.inputEvidence.caseMeta.activePvHomeCount, 9);
            testCase.verifyTrue(all(isfile(run.metricsTable.InputsPath)));
            testCase.verifyTrue(all(isfile(run.metricsTable.SolutionPath)));
            testCase.verifyTrue(all(isfile(run.metricsTable.StagesPath)));
            testCase.verifyTrue(all(isfile(run.metricsTable.MetricsPath)));
            testCase.verifyEqual(height(run.comparisonTable), 10);
            testCase.verifyTrue(isfile(run.metricsPath));
            testCase.verifyTrue(isfile(run.comparisonPath));
            testCase.verifyTrue(isfile(run.figurePath));
        end

        function testRetainsFailedRemovedPvRowWithoutArtifact(testCase)
            run = run_bahloul_leave_one_pv_v1(datetime(2020, 8, 24), ...
                OutputRoot=testCase.OutputRoot, RunId="leave_one_failure", ...
                H4DiagnosticsPath=testCase.DiagnosticsPath, ...
                DataProvider=@leaveOneDataProvider, ...
                Solver=@failingLeaveOneSolver, FigureVisible=false);
            failed = run.metricsTable.Status == "failed";
            failedRow = run.metricsTable(failed, :);

            testCase.verifyEqual(height(run.metricsTable), 11);
            testCase.verifyEqual(nnz(run.metricsTable.IsLeaveOnePv), 10);
            testCase.verifyEqual(nnz(failed), 1);
            testCase.verifyEqual(failedRow.RemovedPvHomeId, "H4");
            testCase.verifyEqual(failedRow.HouseCount, 20);
            testCase.verifyEqual(failedRow.BatteryCount, 20);
            testCase.verifyEqual(failedRow.ActivePvHomeCount, 9);
            testCase.verifyEqual(failedRow.CohortId, "H20_PV10");
            testCase.verifyEqual(failedRow.ErrorIdentifier, ...
                "StoreNet:SyntheticRemovedPvFailure");
            testCase.verifyEqual(failedRow.InputsPath, "");
            testCase.verifyFalse(isfolder(failedRow.CaseDirectory));
            testCase.verifyEqual(height(run.comparisonTable), 10);
            testCase.verifyEqual(nnz(run.comparisonTable.Status == "failed"), 1);
            testCase.verifyTrue(isfile(run.metricsPath));
        end
    end
end

function writeDiagnostics(path)
diagnostics = table("2020-08-24", "same_date_plus60_core", ...
    VariableNames=["Date", "AlignmentCategory"]);
writetable(diagnostics, path);
end

function [data, meta] = leaveOneDataProvider(day, options)
arguments
    day (1, 1) datetime
    options.DataRoot (1, 1) string = ""
    options.IntervalMinutes (1, 1) double = 30
    options.QualityMode (1, 1) string = "exclude_flagged_pv"
end
day = dateshift(day, "start", "day");
nIntervals = 4;
nHomes = 20;
pvHomes = [1, 2, 3, 4, 5, 7, 10, 11, 13, 17];
data = struct;
data.day = day;
data.time = day + minutes(options.IntervalMinutes .* (1:nIntervals).');
data.dtHours = options.IntervalMinutes ./ 60;
data.houseIds = compose("H%d", 1:nHomes);
data.homeNames = data.houseIds;
data.loadKW = ones(nIntervals, nHomes);
data.pvKW = zeros(nIntervals, nHomes);
data.pvKW(:, pvHomes) = 0.2;
data.pvKWh = data.pvKW .* data.dtHours;
data.pvHomeMask = any(data.pvKW > 0, 1);
meta = struct("qualityPassed", true, "qualityReasons", strings(0, 1));
end

function [solution, metrics] = leaveOneSolver(data, config, strategy)
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
solution.objectiveStages = struct("name", "billEUR", "value", 1, ...
    "solverObjective", 1, "exitFlag", 1, "relativeGap", 0, ...
    "message", "fixture");
solution.exitFlags = 1;
metrics = evaluate_storenet(data, config, solution);
solution.metrics = metrics;
end

function [solution, metrics] = failingLeaveOneSolver(data, config, strategy)
if config.removedPvHomeId == "H4"
    error("StoreNet:SyntheticRemovedPvFailure", ...
        "Synthetic failure for the H4 leave-one-PV case.");
end
[solution, metrics] = leaveOneSolver(data, config, strategy);
end
