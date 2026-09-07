classdef TestCrossEnvironmentExperiment < matlab.unittest.TestCase
    %TESTCROSSENVIRONMENTEXPERIMENT Fast orchestration contract tests.

    properties (SetAccess = private)
        WorkspaceRoot
        OutputRoot
        SpecPath
        SourceFile
        ManifestPath
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
            testCase.WorkspaceRoot = string(tempname);
            testCase.OutputRoot = fullfile(testCase.WorkspaceRoot, "results");
            testCase.SpecPath = fullfile(testCase.WorkspaceRoot, "spec.json");
            testCase.SourceFile = fullfile(testCase.WorkspaceRoot, "source.csv");
            testCase.ManifestPath = fullfile(testCase.WorkspaceRoot, ...
                "AUSGRID_MANIFEST.sha256");
            mkdir(testCase.WorkspaceRoot);
            mkdir(testCase.OutputRoot);
            testCase.addTeardown(@() rmdir(testCase.WorkspaceRoot, "s"));
            writelines("mock-source", testCase.SourceFile);
            writelines("aaaaaaaa mock-source.csv", testCase.ManifestPath);
            writeMockSpec(testCase.SpecPath, testCase.ManifestPath);
        end
    end

    methods (Test)
        function testSelectionIsExogenousAndStrategyOrderIsFrozen(testCase)
            run = runMockExperiment(testCase, "selection_order", ...
                @orderRecordingMockSolver, @orderCheckingMockSelector);

            expectedDays = datetime(2012, (1:12).', 15);
            expectedStrategies = repmat( ...
                ["SH_BM"; "VPP_BM"; "IMPROVED_PEAK_GUARD"], 12, 1);
            testCase.verifyEqual(run.selection.Day, expectedDays);
            testCase.verifyEqual(run.primaryMetrics.Strategy, expectedStrategies);
            testCase.verifyEqual(run.primaryMetrics.Sequence, ...
                repmat((1:3).', 12, 1));
            testCase.verifyEqual(run.manifest.experiment. ...
                selectionUsesOptimizationOutcomes, false);
            testCase.verifyTrue(isfile(run.selectionPath));
            testCase.verifyTrue(isfile(run.rankingPath));
        end

        function testFrontierUsesFrozenCapFormulaAndSeparateReferences(testCase)
            run = runMockExperiment(testCase, "frontier_caps", ...
                @mockSolver, @mockSelector);

            marchReference = run.frontierReferenceMetrics( ...
                run.frontierReferenceMetrics.Month == 3, :);
            march = run.frontierMetrics(run.frontierMetrics.Month == 3, :);
            expectedAlpha = [1; 0.75; 0.5; 0.25; 0];
            expectedRequested = marchReference.PeakImportKW + expectedAlpha .* ...
                (march.P0KW - marchReference.PeakImportKW);
            expectedEffective = expectedRequested;
            expectedEffective(end) = expectedEffective(end) + 1e-6;
            testCase.verifyEqual(height(run.frontierReferenceMetrics), 4);
            testCase.verifyEqual(marchReference.PminKW, ...
                marchReference.PeakImportKW, AbsTol=1e-12);
            testCase.verifyEqual(height(run.frontierMetrics), 20);
            testCase.verifyEqual(march.Alpha, expectedAlpha, AbsTol=1e-12);
            testCase.verifyEqual(march.Sequence, (2:6).');
            testCase.verifyEqual(march.RequestedCapKW, expectedRequested, ...
                AbsTol=1e-12);
            testCase.verifyEqual(march.EffectiveCapKW, expectedEffective, ...
                AbsTol=1e-12);
            testCase.verifyEqual(march.Status, repmat("ok", 5, 1));
            testCase.verifyTrue(isfile(run.frontierReferenceMetricsPath));
        end

        function testAcPolicyAndIndependentEvaluatorAreApplied(testCase)
            run = runMockExperiment(testCase, "independent_evaluation", ...
                @mockSolver, @mockSelector);

            testCase.verifyEqual(run.configuration.etaPvAC, 1, AbsTol=1e-12);
            testCase.verifyEqual(run.configuration.dataMode, ...
                "external-fixed-policy-transfer");
            testCase.verifyEqual(run.configuration.dataRoot, ...
                string(fileparts(testCase.SourceFile)));
            testCase.verifyEqual(run.configuration.nHomes, 1);
            testCase.verifyEqual(run.configuration.homes, "AUS13");
            testCase.verifyEqual(run.fixedPolicyOverrides.etaPvAC, 1, ...
                AbsTol=1e-12);
            testCase.verifyEqual(run.primaryMetrics.Status, repmat("ok", 36, 1));
            testCase.verifyGreaterThan(run.primaryMetrics.BaselineBillEUR, ...
                zeros(36, 1));
            testCase.verifyNotEqual(run.primaryMetrics.BaselineBillEUR, ...
                -999 * ones(36, 1));
            testCase.verifyEqual(run.manifest.experiment.independentEvaluator, ...
                "evaluate_storenet");
        end

        function testNonfiniteEvaluatedMetricsFailClosed(testCase)
            run = runMockExperiment(testCase, "nonfinite_metrics", ...
                @nonfiniteMockSolver, @mockSelector);

            testCase.verifyEqual(run.primaryMetrics.Status, ...
                repmat("acceptance_failed", 36, 1));
            testCase.verifyFalse(run.summary.overallCrossEnvironmentRobust);
            testCase.verifyFalse(run.summary.criteria.primaryAllRowsFeasible);
        end

        function testSolverFailureRetainsRowsAndSelectedDays(testCase)
            run = runMockExperiment(testCase, "retained_failure", ...
                @vppFailingMockSolver, @mockSelector);

            failedRows = run.primaryMetrics.Strategy == "VPP_BM";
            testCase.verifyEqual(height(run.primaryMetrics), 36);
            testCase.verifyEqual(run.primaryMetrics.Status(failedRows), ...
                repmat("failed", 12, 1));
            testCase.verifyEqual(run.primaryMetrics.Day(failedRows), ...
                datetime(2012, (1:12).', 15));
            testCase.verifyEqual(run.selection.Day, datetime(2012, (1:12).', 15));
        end

        function testNonemptyRunDirectoryIsRejected(testCase)
            existingDirectory = fullfile(testCase.OutputRoot, "existing");
            mkdir(existingDirectory);
            writelines("do-not-overwrite", fullfile(existingDirectory, "marker.txt"));

            operation = @() runMockExperiment(testCase, "existing", ...
                @mockSolver, @mockSelector);

            testCase.verifyError(operation, "StoreNet:RunDirectoryExists");
            testCase.verifyEqual(string(strtrim(fileread(fullfile( ...
                existingDirectory, "marker.txt")))), "do-not-overwrite");
        end

        function testManifestAndCheckpointCaptureExternalProvenance(testCase)
            run = runMockExperiment(testCase, "provenance", ...
                @mockSolver, @mockSelector);
            manifest = jsondecode(fileread(run.manifestPath));
            checkpoint = readtable(run.checkpointPath);

            testCase.verifyEqual(string(manifest.experiment.dataset.datasetId), ...
                "mock-ausgrid-2012-2013");
            testCase.verifyEqual(string( ...
                manifest.experiment.dataset.datasetPaperDoi), ...
                "10.1080/14786451.2015.1100196");
            testCase.verifyEqual(string(manifest.experiment.pvMeasurementBasis), ...
                "inverter-AC");
            testCase.verifyEqual(manifest.experiment.source.sourceSha256, ...
                repmat('b', 1, 64));
            testCase.verifyEqual(manifest.experiment. ...
                normalizedConfigOverrides.etaPvAC, 1, AbsTol=1e-12);
            testCase.verifyEqual(manifest.experiment.gateTolerances.capKW, ...
                1e-6, AbsTol=1e-15);
            finiteBills = run.frontierMetrics.OptimizedBillEUR(isfinite( ...
                run.frontierMetrics.OptimizedBillEUR));
            expectedBillTolerance = 2 * (run.configuration.mipRelativeGap + ...
                run.configuration.lexicographicTolerance) * ...
                max(1, max(abs(finiteBills)));
            testCase.verifyEqual(run.gateTolerances.billMonotonicEUR, ...
                expectedBillTolerance, AbsTol=1e-15);
            testCase.verifyEqual( ...
                manifest.experiment.gateTolerances.billMonotonicEUR, ...
                expectedBillTolerance, AbsTol=1e-15);
            testCase.verifyEqual(string(manifest.release.manifestPath), ...
                testCase.ManifestPath);
            testCase.verifyTrue(manifest.release.manifestExists);
            testCase.verifyEqual(checkpoint.CompletedPrimaryRows, 36);
            testCase.verifyEqual(checkpoint.CompletedFrontierReferenceRows, 4);
            testCase.verifyEqual(checkpoint.CompletedFrontierRows, 20);
            testCase.verifyEqual(checkpoint.IsFinal, 1);
            testCase.verifyGreaterThanOrEqual( ...
                run.primaryMetrics.WallTimeSeconds, zeros(36, 1));
            testCase.verifyEqual(run.primaryMetrics.ExitFlags, ...
                repmat("1;1", 36, 1));
        end

        function testExternalRendererCreatesSummariesAndFigure(testCase)
            run = runMockExperiment(testCase, "rendered", ...
                @mockSolver, @mockSelector);

            artifacts = render_external_validation(run.runDirectory, ...
                FigureVisible=false);

            testCase.verifyTrue(isfile(artifacts.figurePath));
            testCase.verifyTrue(isfile(artifacts.strategySummaryPath));
            testCase.verifyTrue(isfile(artifacts.frontierSummaryPath));
            testCase.verifyEqual(height(artifacts.strategySummary), 3);
            testCase.verifyEqual(height(artifacts.frontierSummary), 4);
            testCase.verifyEqual(artifacts.strategySummary.Strategy, ...
                ["SH_BM"; "VPP_BM"; "IMPROVED_PEAK_GUARD"]);
            testCase.verifyEqual( ...
                artifacts.strategySummary.MedianSavingsPercent, ...
                zeros(3, 1), AbsTol=1e-12);
            testCase.verifyEqual( ...
                artifacts.strategySummary.MaximumPeakRatioToP0, ...
                ones(3, 1), AbsTol=1e-12);
        end

        function testExternalRendererRefusesOverwrite(testCase)
            run = runMockExperiment(testCase, "render_no_overwrite", ...
                @mockSolver, @mockSelector);
            render_external_validation(run.runDirectory, FigureVisible=false);

            operation = @() render_external_validation(run.runDirectory, ...
                FigureVisible=false);

            testCase.verifyError(operation, "StoreNet:ExternalArtifactExists");
        end

        function testExternalRendererRejectsChangedFrontierGrid(testCase)
            run = runMockExperiment(testCase, "render_changed_grid", ...
                @mockSolver, @mockSelector);
            frontier = readtable(run.frontierMetricsPath, TextType="string");
            frontier.Alpha(1) = 0.6;
            writetable(frontier, run.frontierMetricsPath);

            operation = @() render_external_validation(run.runDirectory, ...
                FigureVisible=false);

            testCase.verifyError(operation, ...
                "StoreNet:InvalidExternalResultPanel");
        end

        function testExternalRendererRejectsDirectoryTarget(testCase)
            run = runMockExperiment(testCase, "render_directory_target", ...
                @mockSolver, @mockSelector);
            mkdir(fullfile(run.runDirectory, "external_validation.png"));

            operation = @() render_external_validation(run.runDirectory, ...
                FigureVisible=false);

            testCase.verifyError(operation, ...
                "StoreNet:ExternalArtifactPathConflict");
            testCase.verifyFalse(isfile(fullfile( ...
                run.runDirectory, "strategy_summary.csv")));
            testCase.verifyFalse(isfile(fullfile( ...
                run.runDirectory, "frontier_summary.csv")));
        end

        function testExternalRendererRejectsZeroReferenceP0(testCase)
            run = runMockExperiment(testCase, "render_zero_reference", ...
                @mockSolver, @mockSelector);
            reference = readtable(run.frontierReferenceMetricsPath, ...
                TextType="string");
            reference.P0KW(1) = 0;
            writetable(reference, run.frontierReferenceMetricsPath);

            operation = @() render_external_validation(run.runDirectory, ...
                FigureVisible=false);

            testCase.verifyError(operation, ...
                "StoreNet:InvalidExternalResultValues");
        end

        function testExternalRendererRejectsDayOutsideLabeledMonth(testCase)
            run = runMockExperiment(testCase, "render_wrong_day_month", ...
                @mockSolver, @mockSelector);
            primary = readtable(run.primaryMetricsPath, TextType="string");
            primary.Day(primary.Month == 1) = datetime(2012, 2, 15);
            writetable(primary, run.primaryMetricsPath);

            operation = @() render_external_validation(run.runDirectory, ...
                FigureVisible=false);

            testCase.verifyError(operation, ...
                "StoreNet:InvalidExternalResultPanel");
        end

        function testExternalRendererRollsBackFailedPublication(testCase)
            run = runMockExperiment(testCase, "render_publish_failure", ...
                @mockSolver, @mockSelector);
            tooLongName = string(repmat('x', 1, 300)) + ".png";

            operation = @() render_external_validation(run.runDirectory, ...
                FigureVisible=false, FigureFileName=tooLongName);

            testCase.verifyError(operation, ...
                "StoreNet:ExternalArtifactPublishFailed");
            testCase.verifyFalse(isfile(fullfile( ...
                run.runDirectory, "strategy_summary.csv")));
            testCase.verifyFalse(isfile(fullfile( ...
                run.runDirectory, "frontier_summary.csv")));
        end
    end
end

function run = runMockExperiment(testCase, runId, solver, selector)
setappdata(0, "StoreNetExternalSolverCalled", false);
cleaner = onCleanup(@() removeOrderProbe());
run = run_external_validation( ...
    SpecPath=testCase.SpecPath, SourceFile=testCase.SourceFile, ...
    OutputRoot=testCase.OutputRoot, RunId=runId, Solver=solver, ...
    FigureVisible=false, VerifySha256=true, ...
    SpecLoader=@mockSpecLoader, YearReader=@mockYearReader, ...
    DayProvider=@mockDayProvider, DaySelector=selector);
clear cleaner
end

function removeOrderProbe()
if isappdata(0, "StoreNetExternalSolverCalled")
    rmappdata(0, "StoreNetExternalSolverCalled");
end
end

function writeMockSpec(path, manifestPath)
policy = struct;
policy.batteryCapacityKWhPerHome = 10;
policy.batteryPowerKWPerHome = 3.3;
policy.etaPvAC = 1;
policy.etaPvDC = 0.95;
policy.etaBatteryCharge = 0.95;
policy.etaBatteryDischarge = 0.95;
policy.transferLossFraction = 0.07;
policy.nightPrice = 0.091;
policy.dayPrice = 0.194;
policy.dayStartHour = 10;
policy.dayEndHour = 22;
policy.feedInPrice = 0;

tolerances = struct;
tolerances.energyBalanceResidualKW = 1e-6;
tolerances.terminalSocErrorKWh = 1e-6;
tolerances.simultaneousChargeDischargeKW = 1e-7;
tolerances.peakCapViolationKW = 1e-6;

spec = struct;
spec.schemaVersion = "StoreNet-cross-environment-spec-v1";
spec.datasetId = "mock-ausgrid-2012-2013";
spec.title = "Mock Ausgrid fixture";
spec.datasetPaperDoi = "10.1080/14786451.2015.1100196";
spec.officialMetadataUrl = "https://example.invalid/metadata";
spec.archiveUrl = "https://example.invalid/archive";
spec.archiveLicense = "CC BY 3.0 AU";
spec.releaseManifestFullPath = manifestPath;
spec.sourceFileSha256 = repmat('b', 1, 64);
spec.sourceIntervalMinutes = 30;
spec.energyUnit = "kWh per 30-minute interval";
spec.timestampBasis = "naive Sydney local wall clock; interval-end";
spec.loadDefinition = "GC + optional CL";
spec.pvDefinition = "GG; inverter-AC gross generation";
spec.pvMeasurementBasis = "inverter-AC";
spec.pvIsAC = true;
spec.analysisCustomerIds = 13;
spec.fixedPolicyTransfer = policy;
spec.primaryStrategies = ["SH_BM", "VPP_BM", "IMPROVED_PEAK_GUARD"];
spec.frontierMonths = [3, 6, 9, 12];
spec.frontierCapFractionsFromMinimumToBaseline = [1, 0.75, 0.5, 0.25, 0];
spec.acceptanceTolerances = tolerances;
writelines(jsonencode(spec, PrettyPrint=true), path);
end

function spec = mockSpecLoader(path)
spec = jsondecode(fileread(path));
spec.pvMeasurementBasis = string(spec.pvMeasurementBasis);
end

function yearData = mockYearReader(spec, options)
arguments
    spec (1, 1) struct
    options.SourceFile (1, 1) string = ""
    options.VerifySha256 (1, 1) logical = true
end
yearData = struct;
yearData.days = datetime(2012, (1:12).', 15);
yearData.source = struct;
yearData.source.sourceFile = options.SourceFile;
yearData.source.sourceSha256 = string(spec.sourceFileSha256);
yearData.source.sha256Verified = options.VerifySha256;
yearData.source.datasetId = string(spec.datasetId);
yearData.source.pvMeasurementBasis = "inverter-AC";
yearData.source.pvIsAC = true;
end

function [selection, ranking] = mockSelector(~)
days = datetime(2012, (1:12).', 15);
monthNumber = (1:12).';
score = 0.01 * monthNumber;
candidateCount = 20 * ones(12, 1);
selection = table(monthNumber, days, score, candidateCount, ...
    VariableNames=["Month", "Day", "Score", "CandidateCount"]);
selected = true(12, 1);
ranking = table(monthNumber, days, score, selected, ...
    VariableNames=["Month", "Day", "Score", "Selected"]);
end

function [selection, ranking] = orderCheckingMockSelector(yearData)
if getappdata(0, "StoreNetExternalSolverCalled")
    error("StoreNet:OutcomeBasedSelection", ...
        "The solver ran before exogenous day selection was frozen.");
end
[selection, ranking] = mockSelector(yearData);
end

function [data, metadata] = mockDayProvider(day, spec, options)
arguments
    day (1, 1) datetime
    spec (1, 1) struct
    options.SourceFile (1, 1) string = ""
end
data = struct;
data.day = dateshift(day, "start", "day");
data.time = data.day + minutes((30:30:120).');
data.timeEnd = data.time;
data.loadKW = [0; 0; 2; 2];
data.pvKW = zeros(4, 1);
data.loadKWh = 0.5 .* data.loadKW;
data.pvKWh = 0.5 .* data.pvKW;
data.dtHours = 0.5;
data.intervalMinutes = 30;
data.customerIds = 13;
data.houseIds = "A13";
data.validForOptimization = true;
metadata = struct;
metadata.qualityPassed = true;
metadata.rejectionReasons = "";
metadata.intervalConvention = "mock interval-end labels";
metadata.pvMeasurementBasis = "inverter-AC";
metadata.pvIsAC = true;
metadata.source = struct("sourceFile", options.SourceFile, ...
    "datasetId", string(spec.datasetId));
end

function [solution, reportedMetrics] = orderRecordingMockSolver(data, config, strategy)
setappdata(0, "StoreNetExternalSolverCalled", true);
[solution, reportedMetrics] = mockSolver(data, config, strategy);
end

function [solution, reportedMetrics] = vppFailingMockSolver(data, config, strategy)
if strategy == "VPP_BM"
    error("StoreNet:MockSolverFailure", "Synthetic VPP failure.");
end
[solution, reportedMetrics] = mockSolver(data, config, strategy);
end

function [solution, reportedMetrics] = nonfiniteMockSolver(data, config, strategy)
[solution, reportedMetrics] = mockSolver(data, config, strategy);
solution.aggregateImportKW(1) = NaN;
end

function [solution, reportedMetrics] = mockSolver(data, config, strategy)
intervalCount = size(data.loadKW, 1);
houseCount = size(data.loadKW, 2);
internalShiftKW = mockInternalShift(data, config, strategy);
chargeKW = [internalShiftKW; internalShiftKW; 0; 0];
dischargeKW = [0; 0; internalShiftKW; internalShiftKW];
gridToBatteryKW = chargeKW ./ config.etaBatteryCharge;
batteryToHomeKW = dischargeKW .* config.etaBatteryDischarge;
gridToHomeKW = data.loadKW - batteryToHomeKW;
zerosFlow = zeros(intervalCount, houseCount);

socKWh = zeros(intervalCount + 1, houseCount);
socKWh(1, :) = config.socInitialFraction * config.batteryCapacityKWh;
for intervalIndex = 1:intervalCount
    socKWh(intervalIndex + 1, :) = socKWh(intervalIndex, :) + ...
        data.dtHours .* (chargeKW(intervalIndex, :) - ...
        dischargeKW(intervalIndex, :));
end

solution = struct;
solution.pvToHomeKW = zerosFlow;
solution.pvToBatteryKW = zerosFlow;
solution.pvToGridKW = zerosFlow;
solution.pvCurtailKW = zerosFlow;
solution.gridToHomeKW = gridToHomeKW;
solution.gridToBatteryKW = gridToBatteryKW;
solution.batteryToHomeKW = batteryToHomeKW;
solution.batteryToGridKW = zerosFlow;
solution.socKWh = socKWh;
solution.batteryChargeKW = chargeKW;
solution.batteryDischargeKW = dischargeKW;
solution.aggregateImportKW = sum(gridToHomeKW + gridToBatteryKW, 2);
solution.exitFlags = [1, 1];
reportedMetrics = struct("baselineBillEUR", -999, ...
    "optimizedBillEUR", -999, "peakImportKW", -999);
end

function shiftKW = mockInternalShift(data, config, strategy)
peakLoadKW = max(data.loadKW, [], "all");
if strategy == "PS"
    shiftKW = peakLoadKW / ...
        (1 / config.etaBatteryCharge + config.etaBatteryDischarge);
elseif strategy == "IMPROVED_PEAK_GUARD"
    shiftKW = max(0, ...
        (peakLoadKW - config.aggregateImportCapKW) / ...
        config.etaBatteryDischarge);
else
    shiftKW = 0;
end
end
