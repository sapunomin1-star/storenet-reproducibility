classdef TestBahloulAcceptanceV1 < matlab.unittest.TestCase
    %TESTBAHLOULACCEPTANCEV1 Synthetic fail-closed R1--R8 tests.

    properties
        FormalRoot
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
        function createFormalRoot(testCase)
            testCase.FormalRoot = string(tempname);
            mkdir(testCase.FormalRoot);
            testCase.addTeardown(@() rmdir(testCase.FormalRoot, "s"));
        end
    end

    methods (Test)
        function testCompleteSyntheticFixturePasses(testCase)
            createCompleteFixture(testCase.FormalRoot);

            acceptance = evaluate_bahloul_acceptance_v1( ...
                testCase.FormalRoot);
            disp(acceptance.ruleTable(:, ["RuleId", "Status", "Observed", "Details"]));
            disp(acceptance.caseTable);

            testCase.verifyEqual(acceptance.overallStatus, "PASS");
            testCase.verifyTrue(acceptance.allRulesPassed);
            testCase.verifyEqual(acceptance.ruleTable.Status, ...
                repmat("PASS", 8, 1));
            testCase.verifyEqual(nnz(acceptance.caseTable.CriticalArtifact), 25);
            testCase.verifyTrue(all(acceptance.caseTable.R1Pass));
            testCase.verifyTrue(all(acceptance.caseTable.R2Pass));
            testCase.verifyTrue(all(acceptance.caseTable.R3Pass));
            testCase.verifyTrue(all(acceptance.caseTable.R5Pass));
            testCase.verifyTrue(all(acceptance.caseTable.IdentityPass));
            testCase.verifyTrue(isfile(acceptance.csvPath));
            testCase.verifyTrue(isfile(acceptance.jsonPath));
            json = jsondecode(fileread(acceptance.jsonPath));
            testCase.verifyEqual(string(json.overallStatus), "PASS");
        end

        function testTamperedArtifactFailsClosed(testCase)
            artifacts = createCompleteFixture(testCase.FormalRoot);
            appendByte(artifacts.solutionPath);

            acceptance = evaluate_bahloul_acceptance_v1( ...
                testCase.FormalRoot);

            testCase.verifyEqual(acceptance.overallStatus, "FAIL");
            testCase.verifyEqual(ruleStatus(acceptance, "R1"), "FAIL");
            testCase.verifyEqual(ruleStatus(acceptance, "R2"), "FAIL");
            testCase.verifyEqual(ruleStatus(acceptance, "R3"), "FAIL");
            testCase.verifyEqual(ruleStatus(acceptance, "R5"), "FAIL");
            testCase.verifyEqual(ruleStatus(acceptance, "R7"), "FAIL");
            testCase.verifyTrue(any(contains( ...
                acceptance.caseTable.ErrorIdentifier, "ChecksumMismatch")));
        end

        function testMissingMonthlyRowDoesNotShrinkDenominator(testCase)
            createCompleteFixture(testCase.FormalRoot);
            dailyPath = fullfile(testCase.FormalRoot, "monthly", ...
                "daily_metrics.csv");
            daily = readtable(dailyPath, Delimiter=",", TextType="string");
            daily(end, :) = [];
            writetable(daily, dailyPath);
            writeScientificManifest(testCase.FormalRoot);

            acceptance = evaluate_bahloul_acceptance_v1( ...
                testCase.FormalRoot);

            testCase.verifyEqual(ruleStatus(acceptance, "R4"), "FAIL");
            testCase.verifyEqual(ruleStatus(acceptance, "R7"), "PASS");
            r4 = acceptance.ruleTable(acceptance.ruleTable.RuleId == "R4", :);
            testCase.verifyThat(r4.Observed, ...
                matlab.unittest.constraints.ContainsSubstring("239"));
        end

        function testCanonicalCohortMismatchFailsR4(testCase)
            createCompleteFixture(testCase.FormalRoot);
            path = fullfile(testCase.FormalRoot, "sensitivity", ...
                "bahloul_sensitivity_long.csv");
            value = readtable(path, Delimiter=",", TextType="string");
            value.CohortId(2) = "WRONG_COHORT";
            writetable(value, path);
            writeScientificManifest(testCase.FormalRoot);

            acceptance = evaluate_bahloul_acceptance_v1( ...
                testCase.FormalRoot);

            testCase.verifyEqual(ruleStatus(acceptance, "R4"), "FAIL");
            testCase.verifyEqual(ruleStatus(acceptance, "R7"), "PASS");
        end

        function testCsvScalarMutationFailsR5Join(testCase)
            createCompleteFixture(testCase.FormalRoot);
            path = fullfile(testCase.FormalRoot, "typical", ...
                "typical_metrics.csv");
            value = readtable(path, Delimiter=",", TextType="string");
            selected = value.Status == "ok" & ...
                value.ResultKind == "MODEL_STRUCTURAL_PROXY";
            value.OptimizedBillEUR(selected) = ...
                value.OptimizedBillEUR(selected) + 1;
            writetable(value, path);
            writeScientificManifest(testCase.FormalRoot);

            acceptance = evaluate_bahloul_acceptance_v1( ...
                testCase.FormalRoot);

            testCase.verifyEqual(ruleStatus(acceptance, "R4"), "PASS");
            testCase.verifyEqual(ruleStatus(acceptance, "R5"), "FAIL");
            testCase.verifyEqual(ruleStatus(acceptance, "R7"), "PASS");
        end

        function testRootManifestIdentityMismatchFailsR4(testCase)
            createCompleteFixture(testCase.FormalRoot);
            path = fullfile(testCase.FormalRoot, "manifest.json");
            manifest = jsondecode(fileread(path));
            manifest.contracts.data.contractSha256 = repmat('9', 1, 64);
            writeJson(path, manifest);
            writeScientificManifest(testCase.FormalRoot);

            acceptance = evaluate_bahloul_acceptance_v1( ...
                testCase.FormalRoot);

            testCase.verifyEqual(ruleStatus(acceptance, "R4"), "FAIL");
            testCase.verifyEqual(ruleStatus(acceptance, "R7"), "PASS");
        end

        function testQualityRejectedRowRequiresReason(testCase)
            createCompleteFixture(testCase.FormalRoot);
            path = fullfile(testCase.FormalRoot, "monthly", ...
                "daily_metrics.csv");
            value = readtable(path, Delimiter=",", TextType="string");
            value.ErrorMessage(1) = "";
            writetable(value, path);
            writeScientificManifest(testCase.FormalRoot);

            acceptance = evaluate_bahloul_acceptance_v1( ...
                testCase.FormalRoot);

            testCase.verifyEqual(ruleStatus(acceptance, "R4"), "FAIL");
            testCase.verifyEqual(ruleStatus(acceptance, "R7"), "PASS");
        end

        function testCriticalQualityRejectionCannotPass(testCase)
            createCompleteFixture(testCase.FormalRoot);
            path = fullfile(testCase.FormalRoot, "sensitivity", ...
                "bahloul_sensitivity_long.csv");
            value = readtable(path, Delimiter=",", TextType="string");
            value.Status(1) = "quality_rejected";
            value.ErrorIdentifier(1) = "StoreNet:QualityRejected";
            value.ErrorMessage(1) = "synthetic critical rejection";
            writetable(value, path);
            writeScientificManifest(testCase.FormalRoot);

            acceptance = evaluate_bahloul_acceptance_v1( ...
                testCase.FormalRoot);

            testCase.verifyEqual(ruleStatus(acceptance, "R4"), "FAIL");
            testCase.verifyEqual(ruleStatus(acceptance, "R7"), "PASS");
        end

        function testMonthlySolverFailureWithReasonIsRegrouped(testCase)
            createCompleteFixture(testCase.FormalRoot);
            path = fullfile(testCase.FormalRoot, "monthly", ...
                "daily_metrics.csv");
            value = readtable(path, Delimiter=",", TextType="string");
            selected = value.Day == value.Day(1);
            value.Status(selected) = "failed";
            value.ErrorIdentifier(selected) = "StoreNet:OptimizationFailed";
            value.ErrorMessage(selected) = ...
                "synthetic retained solver failure";
            writetable(value, path);
            writeScientificManifest(testCase.FormalRoot);

            acceptance = evaluate_bahloul_acceptance_v1( ...
                testCase.FormalRoot);

            testCase.verifyEqual(ruleStatus(acceptance, "R4"), "PASS");
            testCase.verifyEqual(ruleStatus(acceptance, "R7"), "PASS");
        end

        function testObservedCsvMutationFailsR5(testCase)
            createCompleteFixture(testCase.FormalRoot);
            path = fullfile(testCase.FormalRoot, "typical", ...
                "typical_metrics.csv");
            value = readtable(path, Delimiter=",", TextType="string");
            selected = value.ResultKind == "OBSERVED_RELEASE_PROXY";
            value.ObservedBillEUR(selected) = value.ObservedBillEUR(selected) + 1;
            writetable(value, path);
            writeScientificManifest(testCase.FormalRoot);

            acceptance = evaluate_bahloul_acceptance_v1( ...
                testCase.FormalRoot);

            testCase.verifyEqual(ruleStatus(acceptance, "R5"), "FAIL");
            testCase.verifyEqual(ruleStatus(acceptance, "R7"), "PASS");
        end

        function testObservedPersistedProfileMutationFailsR5(testCase)
            artifacts = createCompleteFixture(testCase.FormalRoot);
            rewriteSolutionArtifact(testCase.FormalRoot, ...
                artifacts.observedSolutionPath, "observed_profile");
            writeScientificManifest(testCase.FormalRoot);

            acceptance = evaluate_bahloul_acceptance_v1( ...
                testCase.FormalRoot);

            testCase.verifyEqual(ruleStatus(acceptance, "R5"), "FAIL");
            testCase.verifyEqual(ruleStatus(acceptance, "R7"), "PASS");
        end

        function testTableINonfiniteLocalValueFailsR6(testCase)
            createCompleteFixture(testCase.FormalRoot);
            path = fullfile(testCase.FormalRoot, "sensitivity", ...
                "table_i_target_vs_local.csv");
            value = readtable(path, Delimiter=",", TextType="string");
            value.LocalPaperSavingsPercent(1) = NaN;
            writetable(value, path);
            writeScientificManifest(testCase.FormalRoot);

            acceptance = evaluate_bahloul_acceptance_v1( ...
                testCase.FormalRoot);

            testCase.verifyEqual(ruleStatus(acceptance, "R6"), "FAIL");
            testCase.verifyEqual(ruleStatus(acceptance, "R7"), "PASS");
        end

        function testMonthlyAggregateMutationFailsR4(testCase)
            createCompleteFixture(testCase.FormalRoot);
            path = fullfile(testCase.FormalRoot, "monthly", ...
                "monthly_metrics.csv");
            value = readtable(path, Delimiter=",", TextType="string");
            value.ValidDays(1) = value.ValidDays(1) + 1;
            writetable(value, path);
            writeScientificManifest(testCase.FormalRoot);

            acceptance = evaluate_bahloul_acceptance_v1( ...
                testCase.FormalRoot);

            testCase.verifyEqual(ruleStatus(acceptance, "R4"), "FAIL");
            testCase.verifyEqual(ruleStatus(acceptance, "R7"), "PASS");
        end

        function testOfflineMonthlyProfilesMayBeEmpty(testCase)
            createCompleteFixture(testCase.FormalRoot);
            path = fullfile(testCase.FormalRoot, "monthly", ...
                "monthly_mean_profiles.csv");
            value = readtable(path, Delimiter=",", TextType="string");
            value(1:height(value), :) = [];
            writetable(value, path);
            writeScientificManifest(testCase.FormalRoot);

            acceptance = evaluate_bahloul_acceptance_v1( ...
                testCase.FormalRoot);

            testCase.verifyEqual(ruleStatus(acceptance, "R6"), "PASS");
            testCase.verifyEqual(ruleStatus(acceptance, "R7"), "PASS");
        end

        function testUnlockedObjectiveStagesFailR3(testCase)
            artifacts = createCompleteFixture(testCase.FormalRoot);
            rewriteSolutionArtifact(testCase.FormalRoot, ...
                artifacts.solutionPath, "unlock_stages");
            writeScientificManifest(testCase.FormalRoot);

            acceptance = evaluate_bahloul_acceptance_v1( ...
                testCase.FormalRoot);

            testCase.verifyEqual(ruleStatus(acceptance, "R3"), "FAIL");
            testCase.verifyEqual(ruleStatus(acceptance, "R7"), "PASS");
        end

        function testLockedStageRoundoffPassesR3(testCase)
            artifacts = createCompleteFixture(testCase.FormalRoot);
            rewriteSolutionArtifact(testCase.FormalRoot, ...
                artifacts.solutionPath, "locked_stage_roundoff");
            writeScientificManifest(testCase.FormalRoot);

            acceptance = evaluate_bahloul_acceptance_v1( ...
                testCase.FormalRoot);

            testCase.verifyEqual(ruleStatus(acceptance, "R3"), "PASS");
            testCase.verifyEqual(ruleStatus(acceptance, "R7"), "PASS");
        end

        function testMaterialLockedStageViolationFailsR3(testCase)
            artifacts = createCompleteFixture(testCase.FormalRoot);
            rewriteSolutionArtifact(testCase.FormalRoot, ...
                artifacts.solutionPath, "locked_stage_violation");
            writeScientificManifest(testCase.FormalRoot);

            acceptance = evaluate_bahloul_acceptance_v1( ...
                testCase.FormalRoot);

            testCase.verifyEqual(ruleStatus(acceptance, "R3"), "FAIL");
            testCase.verifyEqual(ruleStatus(acceptance, "R7"), "PASS");
        end

        function testNegativeFlowFailsR2(testCase)
            artifacts = createCompleteFixture(testCase.FormalRoot);
            rewriteSolutionArtifact(testCase.FormalRoot, ...
                artifacts.solutionPath, "negative_flow");
            writeScientificManifest(testCase.FormalRoot);

            acceptance = evaluate_bahloul_acceptance_v1( ...
                testCase.FormalRoot);

            testCase.verifyEqual(ruleStatus(acceptance, "R2"), "FAIL");
            testCase.verifyEqual(ruleStatus(acceptance, "R7"), "PASS");
        end

        function testEffectivePowerRatioMismatchFailsR4(testCase)
            artifacts = createCompleteFixture(testCase.FormalRoot);
            rewriteInputArtifact(testCase.FormalRoot, artifacts.inputsPath, ...
                "wrong_power");
            writeScientificManifest(testCase.FormalRoot);

            acceptance = evaluate_bahloul_acceptance_v1( ...
                testCase.FormalRoot);

            testCase.verifyEqual(ruleStatus(acceptance, "R4"), "FAIL");
            testCase.verifyEqual(ruleStatus(acceptance, "R7"), "PASS");
        end

        function testInvalidPngFailsR6SchemaGate(testCase)
            createCompleteFixture(testCase.FormalRoot);
            path = fullfile(testCase.FormalRoot, "typical", ...
                "figure5_proxy.png");
            writeBytes(path, uint8([137, 80, 78, 71]));
            writeScientificManifest(testCase.FormalRoot);

            acceptance = evaluate_bahloul_acceptance_v1( ...
                testCase.FormalRoot);

            testCase.verifyEqual(ruleStatus(acceptance, "R6"), "FAIL");
            testCase.verifyEqual(ruleStatus(acceptance, "R7"), "PASS");
        end
    end
end

function status = ruleStatus(acceptance, ruleId)
selected = acceptance.ruleTable.RuleId == ruleId;
assert(nnz(selected) == 1, "Synthetic acceptance rule is not unique.");
status = acceptance.ruleTable.Status(selected);
end

function artifacts = createCompleteFixture(root)
folders = ["typical", "sensitivity", "monthly", "evidence"];
for folderIndex = 1:numel(folders)
    mkdir(fullfile(root, folders(folderIndex)));
end
truth = writeFormalTruthFixture(root);

typical = makeTypicalTable(truth);
modelRows = find(typical.ResultKind == "MODEL_STRUCTURAL_PROXY");
artifacts = struct;
for modelIndex = 1:numel(modelRows)
    rowIndex = modelRows(modelIndex);
    [data, config, caseMeta, solution] = makeArtifactCase( ...
        typical(rowIndex, :), truth);
    metrics = evaluate_storenet(data, config, solution);
    caseArtifacts = write_bahloul_case_artifacts( ...
        fullfile(root, "typical", "cases", ...
        compose("case_%03d", modelIndex)), data, config, caseMeta, ...
        solution, metrics);
    typical = populateSuccessfulTypical(typical, rowIndex, metrics, ...
        solution, caseArtifacts);
    if modelIndex == 1
        artifacts = caseArtifacts;
    end
end
observedRows = find(typical.ResultKind == "OBSERVED_RELEASE_PROXY");
for observedIndex = 1:numel(observedRows)
    rowIndex = observedRows(observedIndex);
    [data, config, caseMeta, metrics, profiles] = ...
        makeObservedArtifactCase(typical(rowIndex, :), truth);
    observedArtifacts = write_bahloul_observed_artifacts( ...
        fullfile(root, "typical", "observed_cases", ...
        compose("case_%03d", observedIndex)), data, config, caseMeta, ...
        metrics, profiles);
    typical = populateSuccessfulObservedTypical(typical, rowIndex, ...
        metrics, observedArtifacts);
    if observedIndex == 1
        artifacts.observedSolutionPath = observedArtifacts.solutionPath;
    end
end

sensitivity = makeSensitivityTable(truth);
for rowIndex = 1:height(sensitivity)
    [data, config, caseMeta, solution] = makeArtifactCase( ...
        sensitivity(rowIndex, :), truth);
    metrics = evaluate_storenet(data, config, solution);
    caseArtifacts = struct;
    if sensitivity.ExperimentId(rowIndex) == "TABLE_I"
        caseArtifacts = write_bahloul_case_artifacts( ...
            fullfile(root, "sensitivity", "cases", ...
            sensitivity.CaseId(rowIndex)), data, config, caseMeta, ...
            solution, metrics);
    end
    sensitivity = populateSuccessfulSensitivity(sensitivity, rowIndex, ...
        config, metrics, solution, caseArtifacts);
end
daily = makeDailyTable(truth);
monthly = makeMonthlyTable(truth, daily);
writetable(typical, fullfile(root, "typical", "typical_metrics.csv"));
writetable(sensitivity, fullfile(root, "sensitivity", ...
    "bahloul_sensitivity_long.csv"));
writetable(daily, fullfile(root, "monthly", "daily_metrics.csv"));
writetable(monthly, fullfile(root, "monthly", "monthly_metrics.csv"));

writePaperOutputs(root, sensitivity);
writeInterpretation(fullfile(root, "SCIENTIFIC_INTERPRETATION.md"));
writeScientificManifest(root);
end

function truth = writeFormalTruthFixture(root)
artifactId = ["FIG5_PROFILE"; "FIG5_SAVINGS"; "TABLE_I"];
sha256 = [string(repmat('c', 1, 64)); ...
    string(repmat('d', 1, 64)); string(repmat('f', 1, 64))];
reference = table(artifactId, sha256, ...
    VariableNames=["ArtifactId", "Sha256"]);
referencePath = fullfile(root, "evidence", ...
    "B2022_REFERENCE_MANIFEST.csv");
writetable(reference, referencePath);

truth = struct;
truth.DataContractId = "SR2020-IR-v2";
truth.DataContractSha256 = string(repmat('a', 1, 64));
truth.DataContractGitCommit = string(repmat('e', 1, 40));
truth.ModelContractId = "B2022-IR-v1";
truth.ModelContractSha256 = string(repmat('b', 1, 64));
truth.ReferenceManifestSha256 = sha256FileForTest(referencePath);
truth.ReferenceIds = artifactId;
truth.ReferenceHashes = sha256;
truth.TypicalDay = datetime(2020, 8, 24);
truth.QualityMode = "release_literal";

dataContract = struct("contractId", truth.DataContractId, ...
    "contractSha256", truth.DataContractSha256, ...
    "gitCommit", truth.DataContractGitCommit);
modelContract = struct("contractId", truth.ModelContractId, ...
    "contractSha256", truth.ModelContractSha256);
manifest = struct("schemaVersion", "StoreNet-run-manifest-v2", ...
    "formalMode", true, ...
    "contracts", struct("data", dataContract, "model", modelContract), ...
    "references", struct("referenceManifestSha256", ...
    truth.ReferenceManifestSha256), ...
    "experiment", struct("typicalDay", "2020-08-24", ...
    "qualityMode", truth.QualityMode));
writeJson(fullfile(root, "manifest.json"), manifest);
end

function value = makeTypicalTable(truth)
value = coreRows("B2022_TYPICAL_V1", truth.TypicalDay, ...
    truth.QualityMode);
directional = ["DC_XI007_H19", "AC_XI007_H20", "DC_XI000_H20"];
selected = value.ScenarioId == "DC_XI007_H20" | ...
    (value.Strategy == "VPP_BM" & ismember(value.ScenarioId, directional)) | ...
    value.Strategy == "SB_SC";
value = value(selected, :);
value.ResultKind = repmat("MODEL_STRUCTURAL_PROXY", height(value), 1);
value.ResultKind(value.Strategy == "SB_SC") = "OBSERVED_RELEASE_PROXY";
value = addRejectedStatus(value);
value = addCommonArtifactColumns(value);
value = addTypicalMetricColumns(value);
end

function value = makeDailyTable(truth)
base = coreRows("B2022_MONTHLY_V1", truth.TypicalDay, ...
    truth.QualityMode);
base = base(base.ScenarioId == "DC_XI007_H20" & ...
    base.Strategy ~= "SB_SC", :);
dates = monthlyDays();
[dateIndex, rowIndex] = ndgrid(1:numel(dates), 1:height(base));
value = base(rowIndex(:), :);
value.Day = dates(dateIndex(:));
value.YearMonth = dateshift(value.Day, "start", "month");
value.RecordType = repmat("optimized", height(value), 1);
value = addRejectedStatus(value);
value = addCommonArtifactColumns(value);
value = addDailyMetricColumns(value);
end

function value = makeMonthlyTable(truth, daily)
base = coreRows("B2022_MONTHLY_V1", truth.TypicalDay, ...
    truth.QualityMode);
base = base(base.ScenarioId == "DC_XI007_H20" & ...
    base.Strategy ~= "SB_SC", :);
months = datetime(2020, (1:12).', 1);
[monthIndex, rowIndex] = ndgrid(1:numel(months), 1:height(base));
value = base(rowIndex(:), :);
value.YearMonth = months(monthIndex(:));
value.Day = [];
value = movevars(value, "YearMonth", "Before", 1);
value.PaperPeriodRelation = repmat("2020-07--12_extrapolation", ...
    height(value), 1);
value.PaperPeriodRelation(year(value.YearMonth) == 2020 & ...
    month(value.YearMonth) <= 6) = "2020-01--06_overlap";
value.PublicReleaseAvailability = repmat( ...
    "available_from_public_release", height(value), 1);
value.CandidateDays = repmat(4, height(value), 1);
value.RequestedDays = repmat(4, height(value), 1);
value.ValidDays = zeros(height(value), 1);
value.FailedOrRejectedDays = repmat(4, height(value), 1);
value.UnavailableCandidateDays = zeros(height(value), 1);
value = addMonthlyMetricColumns(value);
value = populateRejectedMonthlyAggregation(value, daily);
end

function value = makeSensitivityTable(truth)
scenarios = bahloul_scenarios("CORE_SIX");
ratios = (2:10).' ./ 10;
[capacityIndex, powerIndex] = ndgrid(1:9, 1:9);
capacityRatio = ratios(capacityIndex(:));
powerRatio = ratios(powerIndex(:));
scenarioIndex = ones(numel(capacityRatio), 1);
nFigure = numel(scenarioIndex);
figureRows = stableRows(truth.TypicalDay, "FIGURE_7", ...
    truth.QualityMode, repmat("VPP_BM", nFigure, 1), ...
    scenarios(1, :), scenarioIndex, capacityRatio, powerRatio);
figureRows.CaseId = compose("figure7_c%03d_p%03d_%s_VPP_BM", ...
    round(100 .* capacityRatio), round(100 .* powerRatio), ...
    figureRows.ScenarioId);
figureRows.BudgetId = repmat("GRID", nFigure, 1);
figureRows.SensitivityRole = scenarios.SensitivityRole(scenarioIndex);

budgetId = ["NOMINAL"; "POWER_20"; "CAPACITY_20"];
capacity = [1; 1; 0.2];
power = [1; 0.2; 1];
strategies = ["SH_BM"; "VPP_BM"; "PS"; "PSDT"; "LL"];
[budgetIndex, strategyIndex] = ndgrid(1:3, 1:5);
budgetIndex = budgetIndex(:);
strategyIndex = strategyIndex(:);
scenarioIndex = ones(numel(budgetIndex), 1);
selectedBudget = budgetId(budgetIndex);
selectedStrategy = strategies(strategyIndex);
tableRows = stableRows(truth.TypicalDay, "TABLE_I", ...
    truth.QualityMode, selectedStrategy, scenarios, scenarioIndex, ...
    capacity(budgetIndex), power(budgetIndex));
tableRows.CaseId = compose("tablei_%s_%s_%s", lower(selectedBudget), ...
    tableRows.ScenarioId, selectedStrategy);
tableRows.BudgetId = selectedBudget;
tableRows.SensitivityRole = scenarios.SensitivityRole(scenarioIndex);
value = [figureRows; tableRows];
value = addRejectedStatus(value);
value = addCommonArtifactColumns(value);
value = addSensitivityMetricColumns(value);
end

function value = coreRows(experimentId, day, qualityMode)
scenarios = bahloul_scenarios("CORE_SIX");
strategies = ["SH_BM"; "VPP_BM"; "PS"; "PSDT"; "LL"];
[scenarioIndex, strategyIndex] = ndgrid(1:6, 1:5);
scenarioIndex = scenarioIndex(:);
strategyIndex = strategyIndex(:);
value = stableRows(day, experimentId, qualityMode, ...
    strategies(strategyIndex), scenarios, scenarioIndex, ...
    ones(30, 1), ones(30, 1));
observed = table(repmat(day, 2, 1), repmat(string(experimentId), 2, 1), ...
    repmat(string(qualityMode), 2, 1), repmat("SB_SC", 2, 1), ...
    ["H20_PV10"; "H19_EXCL_H4_PV9"], ...
    repmat("OBSERVED_RELEASE_FIELDS", 2, 1), nan(2, 1), ...
    nan(2, 1), nan(2, 1), repmat("OBSERVED_RELEASE_PAIR", 2, 1), ...
    ["OBSERVED_RELEASE_H20_PV10"; ...
    "OBSERVED_RELEASE_H19_EXCL_H4_PV9"], ...
    VariableNames=value.Properties.VariableNames);
value = [value; observed];
end

function value = stableRows(day, experimentId, qualityMode, strategy, ...
        scenarios, scenarioIndex, capacityRatio, powerRatio)
n = numel(scenarioIndex);
value = table(repmat(day, n, 1), repmat(string(experimentId), n, 1), ...
    repmat(string(qualityMode), n, 1), string(strategy(:)), ...
    scenarios.CohortId(scenarioIndex), ...
    scenarios.PvBoundaryId(scenarioIndex), ...
    scenarios.TransferLossFraction(scenarioIndex), ...
    double(capacityRatio(:)), double(powerRatio(:)), ...
    scenarios.PairId(scenarioIndex), scenarios.ScenarioId(scenarioIndex), ...
    VariableNames=["Day", "ExperimentId", "QualityMode", "Strategy", ...
    "CohortId", "PvBoundaryId", "TransferLossFraction", ...
    "CapacityRatio", "PowerRatio", "PairId", "ScenarioId"]);
end

function value = addRejectedStatus(value)
value.Status = repmat("quality_rejected", height(value), 1);
value.ErrorIdentifier = repmat("StoreNet:QualityRejected", height(value), 1);
value.ErrorMessage = repmat("synthetic fixed row was quality rejected", ...
    height(value), 1);
end

function value = addCommonArtifactColumns(value)
n = height(value);
value.InputsPath = repmat("", n, 1);
value.InputsSha256 = repmat("", n, 1);
value.SolutionPath = repmat("", n, 1);
value.SolutionSha256 = repmat("", n, 1);
end

function value = addTypicalMetricColumns(value)
names = ["PaperLoadOnlyBaselineBillEUR", ...
    "PaperSavingsPercentDenominatorIsZero", ...
    "PaperLoadOnlySavingsEUR", "PaperLoadOnlySavingsPercent", ...
    "OriginalLoadPeakKW", "OriginalLoadDaytimePeakKW", ...
    "PvSelfNoBatteryBaselineBillEUR", ...
    "EngineeringSavingsPercentDenominatorIsZero", ...
    "EngineeringSavingsEUR", "EngineeringSavingsPercent", ...
    "PvSelfNoBatteryPeakKW", "OptimizedBillEUR", ...
    "OptimizedPeakImportKW", "OptimizedDaytimePeakImportKW", ...
    "OptimizedImportSpreadKW", "TotalGridImportKWh", ...
    "TotalBatteryThroughputKWh", "TotalCurtailedPvKWh", ...
    "TotalSharedExportKWh", "EnergyBalanceResidualKW", ...
    "PvAllocationResidualKW", "HomeBalanceResidualKW", ...
    "BatteryDynamicsResidualKW", "AggregateImportResidualKW", ...
    "ChargeConversionResidualKW", "DischargeConversionResidualKW", ...
    "InitialSocErrorKWh", "TerminalSocErrorKWh", ...
    "SocBoundViolationKWh", "ChargePowerViolationKW", ...
    "DischargePowerViolationKW", ...
    "AggregateImportNonnegativeViolationKW", ...
    "SimultaneousChargeDischargeKW", ...
    "SimultaneousChargeDischargeCount", ...
    "MaximumLexicographicViolation", "StageCount", ...
    "MinimumExitFlag", "MaximumRelativeMipGap"];
names = [names, "ObservedReleasePvSelfNoBatteryBaselineBillEUR", ...
    "ObservedReleaseEngineeringSavingsEUR", ...
    "ObservedReleaseEngineeringSavingsPercent", ...
    "ObservedReleaseEngineeringSavingsPercentDenominatorIsZero", ...
    "ObservedBillEUR", "ObservedPeakImportKW", ...
    "ObservedDaytimePeakImportKW", "ObservedImportSpreadKW", ...
    "TotalFeedInKWh"];
for fieldIndex = 1:numel(names)
    value.(names(fieldIndex)) = nan(height(value), 1);
end
end

function value = addDailyMetricColumns(value)
names = ["PaperLoadOnlyBaselineBillEUR", ...
    "PaperSavingsPercentDenominatorIsZero", ...
    "PaperLoadOnlySavingsEUR", "PaperLoadOnlySavingsPercent", ...
    "PvSelfNoBatteryBaselineBillEUR", ...
    "EngineeringSavingsPercentDenominatorIsZero", ...
    "PaperLoadOnlyPeakKW", "PaperLoadOnlyDaytimePeakKW", ...
    "PvSelfNoBatterySavingsEUR", "PvSelfNoBatterySavingsPercent", ...
    "PvSelfNoBatteryPeakKW", "PvSelfNoBatteryDaytimePeakKW", ...
    "OptimizedBillEUR", "OutcomePeakImportKW", ...
    "OutcomeDaytimePeakImportKW", "TotalGridImportKWh", ...
    "TotalBatteryThroughputKWh", "TotalCurtailedPvKWh", ...
    "TotalSharedExportKWh", "EnergyBalanceResidualKW", ...
    "PvAllocationResidualKW", "HomeBalanceResidualKW", ...
    "BatteryDynamicsResidualKW", "AggregateImportResidualKW", ...
    "ChargeConversionResidualKW", "DischargeConversionResidualKW", ...
    "InitialSocErrorKWh", "TerminalSocErrorKWh", ...
    "SocBoundViolationKWh", "ChargePowerViolationKW", ...
    "DischargePowerViolationKW", ...
    "AggregateImportNonnegativeViolationKW", ...
    "SimultaneousChargeDischargeKW", ...
    "SimultaneousChargeDischargeCount", ...
    "MaximumLexicographicViolation", "ObjectiveStageCount", ...
    "MinimumExitFlag", "MaximumRelativeGap"];
value = addNumericColumns(value, names);
end

function value = addSensitivityMetricColumns(value)
names = ["BatteryCapacityKWh", "BatteryPowerKW", ...
    "PaperLoadOnlyBaselineBillEUR", ...
    "PaperLoadOnlyBaselinePeakImportKW", ...
    "PaperLoadOnlyBaselineDaytimePeakImportKW", ...
    "PaperLoadOnlySavingsEUR", "PaperLoadOnlySavingsPercent", ...
    "PaperSavingsPercentDenominatorIsZero", ...
    "PvSelfNoBatteryBaselineBillEUR", ...
    "PvSelfNoBatteryBaselinePeakImportKW", ...
    "PvSelfNoBatteryBaselineDaytimePeakImportKW", ...
    "PvSelfNoBatterySavingsEUR", "PvSelfNoBatterySavingsPercent", ...
    "EngineeringSavingsPercentDenominatorIsZero", ...
    "OptimizedBillEUR", "PeakImportKW", "DaytimePeakImportKW", ...
    "ImportSpreadKW", "TotalGridImportKWh", ...
    "TotalBatteryThroughputKWh", "TotalCurtailedPvKWh", ...
    "TotalSharedExportKWh", "EnergyBalanceResidualKW", ...
    "PvAllocationResidualKW", "HomeBalanceResidualKW", ...
    "BatteryDynamicsResidualKW", "AggregateImportResidualKW", ...
    "ChargeConversionResidualKW", "DischargeConversionResidualKW", ...
    "InitialSocErrorKWh", "TerminalSocErrorKWh", ...
    "SocBoundViolationKWh", "ChargePowerViolationKW", ...
    "DischargePowerViolationKW", ...
    "AggregateImportNonnegativeViolationKW", ...
    "SimultaneousChargeDischargeKW", ...
    "SimultaneousChargeDischargeCount", ...
    "MaximumLexicographicViolation", "StageCount", ...
    "MinimumStageExitFlag", "MaximumStageRelativeGap"];
value = addNumericColumns(value, names);
value.StageNames = repmat("", height(value), 1);
end

function value = addMonthlyMetricColumns(value)
names = ["MeanDailyPaperLoadOnlyBaselineBillEUR", ...
    "MeanDailyPaperLoadOnlySavingsEUR", ...
    "MeanDailyPaperLoadOnlySavingsPercent", ...
    "MeanDailyPvSelfNoBatteryBaselineBillEUR", ...
    "MeanDailyPvSelfNoBatterySavingsEUR", ...
    "MeanDailyPvSelfNoBatterySavingsPercent", ...
    "SumPaperLoadOnlyBaselineBillEUR", ...
    "SumPvSelfNoBatteryBaselineBillEUR", "SumOptimizedBillEUR", ...
    "RatioOfSummedCostsPaperLoadOnlySavingsPercent", ...
    "RatioOfSummedCostsPaperLoadOnlySavingsPercentDenominatorIsZero", ...
    "RatioOfSummedCostsPvSelfNoBatterySavingsPercent", ...
    "MeanDailyPaperLoadOnlyPeakKW", ...
    "MeanDailyPvSelfNoBatteryPeakKW", ...
    "MeanDailyOutcomePeakImportKW"];
value = addNumericColumns(value, names);
end

function value = addNumericColumns(value, names)
for fieldIndex = 1:numel(names)
    value.(names(fieldIndex)) = nan(height(value), 1);
end
end

function value = populateRejectedMonthlyAggregation(value, daily)
dailyMonths = dateshift(daily.Day, "start", "month");
for rowIndex = 1:height(value)
    selected = dailyMonths == value.YearMonth(rowIndex) & ...
        daily.ScenarioId == value.ScenarioId(rowIndex) & ...
        daily.Strategy == value.Strategy(rowIndex);
    valid = selected & daily.Status == "ok";
    value.CandidateDays(rowIndex) = nnz(selected);
    value.RequestedDays(rowIndex) = nnz(selected);
    value.ValidDays(rowIndex) = nnz(valid);
    value.FailedOrRejectedDays(rowIndex) = nnz(selected & ~valid);
end
end

function value = populateSuccessfulTypical(value, rowIndex, metrics, ...
        solution, artifacts)
value.Status(rowIndex) = "ok";
value.ErrorIdentifier(rowIndex) = "";
value.ErrorMessage(rowIndex) = "";
value.InputsPath(rowIndex) = artifacts.inputsPath;
value.InputsSha256(rowIndex) = artifacts.inputsSha256;
value.SolutionPath(rowIndex) = artifacts.solutionPath;
value.SolutionSha256(rowIndex) = artifacts.solutionSha256;
paper = metrics.PaperLoadOnlyBaseline;
pvSelf = metrics.PvSelfNoBatteryBaseline;
value.PaperLoadOnlyBaselineBillEUR(rowIndex) = paper.billEUR;
value.PaperSavingsPercentDenominatorIsZero(rowIndex) = ...
    double(paper.savingsPercentDenominatorIsZero);
value.PaperLoadOnlySavingsEUR(rowIndex) = paper.savingsEUR;
value.PaperLoadOnlySavingsPercent(rowIndex) = paper.savingsPercent;
value.OriginalLoadPeakKW(rowIndex) = paper.peakImportKW;
value.OriginalLoadDaytimePeakKW(rowIndex) = paper.daytimePeakImportKW;
value.PvSelfNoBatteryBaselineBillEUR(rowIndex) = pvSelf.billEUR;
value.EngineeringSavingsPercentDenominatorIsZero(rowIndex) = ...
    double(pvSelf.savingsPercentDenominatorIsZero);
value.EngineeringSavingsEUR(rowIndex) = pvSelf.savingsEUR;
value.EngineeringSavingsPercent(rowIndex) = pvSelf.savingsPercent;
value.PvSelfNoBatteryPeakKW(rowIndex) = pvSelf.peakImportKW;
value.OptimizedBillEUR(rowIndex) = metrics.optimizedBillEUR;
value.OptimizedPeakImportKW(rowIndex) = metrics.peakImportKW;
value.OptimizedDaytimePeakImportKW(rowIndex) = ...
    metrics.daytimePeakImportKW;
value.OptimizedImportSpreadKW(rowIndex) = metrics.importSpreadKW;
scalarNames = ["totalGridImportKWh", "totalBatteryThroughputKWh", ...
    "totalCurtailedPvKWh", "totalSharedExportKWh", ...
    "energyBalanceResidualKW", "pvAllocationResidualKW", ...
    "homeBalanceResidualKW", "batteryDynamicsResidualKW", ...
    "aggregateImportResidualKW", "chargeConversionResidualKW", ...
    "dischargeConversionResidualKW", "initialSocErrorKWh", ...
    "terminalSocErrorKWh", "socBoundViolationKWh", ...
    "chargePowerViolationKW", "dischargePowerViolationKW", ...
    "aggregateImportNonnegativeViolationKW", ...
    "simultaneousChargeDischargeKW", ...
    "simultaneousChargeDischargeCount", ...
    "maximumLexicographicViolation"];
columnNames = ["TotalGridImportKWh", "TotalBatteryThroughputKWh", ...
    "TotalCurtailedPvKWh", "TotalSharedExportKWh", ...
    "EnergyBalanceResidualKW", "PvAllocationResidualKW", ...
    "HomeBalanceResidualKW", "BatteryDynamicsResidualKW", ...
    "AggregateImportResidualKW", "ChargeConversionResidualKW", ...
    "DischargeConversionResidualKW", "InitialSocErrorKWh", ...
    "TerminalSocErrorKWh", "SocBoundViolationKWh", ...
    "ChargePowerViolationKW", "DischargePowerViolationKW", ...
    "AggregateImportNonnegativeViolationKW", ...
    "SimultaneousChargeDischargeKW", ...
    "SimultaneousChargeDischargeCount", ...
    "MaximumLexicographicViolation"];
for fieldIndex = 1:numel(scalarNames)
    value.(columnNames(fieldIndex))(rowIndex) = metrics.(scalarNames(fieldIndex));
end
value.StageCount(rowIndex) = numel(solution.objectiveStages);
value.MinimumExitFlag(rowIndex) = min([solution.objectiveStages.exitFlag]);
value.MaximumRelativeMipGap(rowIndex) = ...
    max([solution.objectiveStages.relativeGap]);
end

function value = populateSuccessfulObservedTypical(value, rowIndex, ...
        metrics, artifacts)
value.Status(rowIndex) = "ok";
value.ErrorIdentifier(rowIndex) = "";
value.ErrorMessage(rowIndex) = "";
value.InputsPath(rowIndex) = artifacts.inputsPath;
value.InputsSha256(rowIndex) = artifacts.inputsSha256;
value.SolutionPath(rowIndex) = artifacts.solutionPath;
value.SolutionSha256(rowIndex) = artifacts.solutionSha256;
columns = ["PaperLoadOnlyBaselineBillEUR", ...
    "PaperLoadOnlySavingsEUR", "PaperLoadOnlySavingsPercent", ...
    "PaperSavingsPercentDenominatorIsZero", "OriginalLoadPeakKW", ...
    "OriginalLoadDaytimePeakKW", ...
    "ObservedReleasePvSelfNoBatteryBaselineBillEUR", ...
    "ObservedReleaseEngineeringSavingsEUR", ...
    "ObservedReleaseEngineeringSavingsPercent", ...
    "ObservedReleaseEngineeringSavingsPercentDenominatorIsZero", ...
    "ObservedBillEUR", "ObservedPeakImportKW", ...
    "ObservedDaytimePeakImportKW", "ObservedImportSpreadKW", ...
    "TotalGridImportKWh", "TotalBatteryThroughputKWh", ...
    "TotalFeedInKWh"];
fields = ["paperLoadOnlyBaselineBillEUR", "paperLoadOnlySavingsEUR", ...
    "paperLoadOnlySavingsPercent", ...
    "paperLoadOnlySavingsPercentDenominatorIsZero", ...
    "paperLoadOnlyPeakKW", "paperLoadOnlyDaytimePeakKW", ...
    "observedReleasePvSelfNoBatteryBaselineBillEUR", ...
    "observedReleaseEngineeringSavingsEUR", ...
    "observedReleaseEngineeringSavingsPercent", ...
    "observedReleaseEngineeringSavingsPercentDenominatorIsZero", ...
    "observedBillEUR", "observedPeakImportKW", ...
    "observedDaytimePeakImportKW", "observedImportSpreadKW", ...
    "observedGridImportKWh", "releaseBatteryThroughputKWh", ...
    "totalFeedInKWh"];
for fieldIndex = 1:numel(columns)
    value.(columns(fieldIndex))(rowIndex) = double(metrics.(fields(fieldIndex)));
end
end

function value = populateSuccessfulSensitivity(value, rowIndex, config, ...
        metrics, solution, artifacts)
value.Status(rowIndex) = "ok";
value.ErrorIdentifier(rowIndex) = "";
value.ErrorMessage(rowIndex) = "";
value.BatteryCapacityKWh(rowIndex) = config.batteryCapacityKWh;
value.BatteryPowerKW(rowIndex) = config.batteryPowerKW;
paper = metrics.PaperLoadOnlyBaseline;
pvSelf = metrics.PvSelfNoBatteryBaseline;
value.PaperLoadOnlyBaselineBillEUR(rowIndex) = paper.billEUR;
value.PaperLoadOnlyBaselinePeakImportKW(rowIndex) = paper.peakImportKW;
value.PaperLoadOnlyBaselineDaytimePeakImportKW(rowIndex) = ...
    paper.daytimePeakImportKW;
value.PaperLoadOnlySavingsEUR(rowIndex) = paper.savingsEUR;
value.PaperLoadOnlySavingsPercent(rowIndex) = paper.savingsPercent;
value.PaperSavingsPercentDenominatorIsZero(rowIndex) = ...
    double(paper.savingsPercentDenominatorIsZero);
value.PvSelfNoBatteryBaselineBillEUR(rowIndex) = pvSelf.billEUR;
value.PvSelfNoBatteryBaselinePeakImportKW(rowIndex) = pvSelf.peakImportKW;
value.PvSelfNoBatteryBaselineDaytimePeakImportKW(rowIndex) = ...
    pvSelf.daytimePeakImportKW;
value.PvSelfNoBatterySavingsEUR(rowIndex) = pvSelf.savingsEUR;
value.PvSelfNoBatterySavingsPercent(rowIndex) = pvSelf.savingsPercent;
value.EngineeringSavingsPercentDenominatorIsZero(rowIndex) = ...
    double(pvSelf.savingsPercentDenominatorIsZero);
columns = ["OptimizedBillEUR", "PeakImportKW", "DaytimePeakImportKW", ...
    "ImportSpreadKW", "TotalGridImportKWh", ...
    "TotalBatteryThroughputKWh", "TotalCurtailedPvKWh", ...
    "TotalSharedExportKWh", "EnergyBalanceResidualKW", ...
    "PvAllocationResidualKW", "HomeBalanceResidualKW", ...
    "BatteryDynamicsResidualKW", "AggregateImportResidualKW", ...
    "ChargeConversionResidualKW", "DischargeConversionResidualKW", ...
    "InitialSocErrorKWh", "TerminalSocErrorKWh", ...
    "SocBoundViolationKWh", "ChargePowerViolationKW", ...
    "DischargePowerViolationKW", ...
    "AggregateImportNonnegativeViolationKW", ...
    "SimultaneousChargeDischargeKW", ...
    "SimultaneousChargeDischargeCount", ...
    "MaximumLexicographicViolation"];
fields = ["optimizedBillEUR", "peakImportKW", "daytimePeakImportKW", ...
    "importSpreadKW", "totalGridImportKWh", ...
    "totalBatteryThroughputKWh", "totalCurtailedPvKWh", ...
    "totalSharedExportKWh", "energyBalanceResidualKW", ...
    "pvAllocationResidualKW", "homeBalanceResidualKW", ...
    "batteryDynamicsResidualKW", "aggregateImportResidualKW", ...
    "chargeConversionResidualKW", "dischargeConversionResidualKW", ...
    "initialSocErrorKWh", "terminalSocErrorKWh", ...
    "socBoundViolationKWh", "chargePowerViolationKW", ...
    "dischargePowerViolationKW", ...
    "aggregateImportNonnegativeViolationKW", ...
    "simultaneousChargeDischargeKW", ...
    "simultaneousChargeDischargeCount", ...
    "maximumLexicographicViolation"];
for fieldIndex = 1:numel(columns)
    value.(columns(fieldIndex))(rowIndex) = double(metrics.(fields(fieldIndex)));
end
stages = solution.objectiveStages(:);
value.StageCount(rowIndex) = numel(stages);
value.MinimumStageExitFlag(rowIndex) = min([stages.exitFlag]);
value.MaximumStageRelativeGap(rowIndex) = max([stages.relativeGap]);
value.StageNames(rowIndex) = strjoin(string({stages.name}).', "|");
if ~isempty(fieldnames(artifacts))
    value.InputsPath(rowIndex) = artifacts.inputsPath;
    value.InputsSha256(rowIndex) = artifacts.inputsSha256;
    value.SolutionPath(rowIndex) = artifacts.solutionPath;
    value.SolutionSha256(rowIndex) = artifacts.solutionSha256;
end
end

function [data, config, caseMeta, metrics, profiles] = ...
        makeObservedArtifactCase(row, truth)
if row.CohortId == "H20_PV10"
    houseNumbers = 1:20;
    pvHomeCount = 10;
else
    houseNumbers = [1:3, 5:20];
    pvHomeCount = 9;
end
n = numel(houseNumbers);
data = struct;
data.time = truth.TypicalDay + hours([11; 12]);
data.dtHours = 1;
data.houseIds = compose("H%d", houseNumbers);
data.loadKW = repmat([1; 2], 1, n);
data.pvKW = repmat([0.2; 0], 1, n);
data.releasedPvKW = data.pvKW;
data.fromGridKW = repmat([0.8; 1.8], 1, n);
data.feedInKW = repmat([0.05; 0], 1, n);
data.chargeKW = zeros(2, n);
data.dischargeKW = zeros(2, n);
data.observationMask = true(2, 1);
data.interpolationMask = false(2, 1);

config = struct("nightPrice", 0.091, "dayPrice", 0.194, ...
    "dayStartHour", 10, "dayEndHour", 22, "etaPvAC", 0.95, ...
    "transferLossFraction", 0.07, "xi", 0.07, ...
    "pvBoundaryId", "DC_SOURCE");
caseMeta = struct("experimentId", row.ExperimentId, ...
    "day", row.Day, "strategy", "SB_SC", ...
    "scenarioId", row.ScenarioId, "pairId", row.PairId, ...
    "cohortId", row.CohortId, "pvBoundaryId", row.PvBoundaryId, ...
    "qualityMode", row.QualityMode, "houseCount", n, ...
    "pvHomeCount", pvHomeCount, "h4MaskAffected", false, ...
    "observationMask", data.observationMask, ...
    "interpolationMask", data.interpolationMask, ...
    "dataContractId", truth.DataContractId, ...
    "dataContractSha256", truth.DataContractSha256, ...
    "dataContractGitCommit", truth.DataContractGitCommit, ...
    "modelContractId", truth.ModelContractId, ...
    "modelContractSha256", truth.ModelContractSha256, ...
    "referenceIds", truth.ReferenceIds, ...
    "referenceHashes", truth.ReferenceHashes, ...
    "referenceManifestSha256", truth.ReferenceManifestSha256, ...
    "dataProviderProvenance", struct("name", "syntheticProvider"));
[data, config, caseMeta] = prepare_observed_sbsc_case( ...
    data, config, caseMeta);
[metrics, profiles] = evaluate_observed_sbsc(data, config);
end

function [data, config, caseMeta, solution] = makeArtifactCase(row, truth)
data = struct;
data.time = truth.TypicalDay + hours([11; 12]);
data.dtHours = 1;
data.houseIds = "H1";
data.loadKW = [1; 2];
data.pvKW = [0.2; 0];
data.releasedPvKW = data.pvKW;
data.observationMask = true(2, 1);
data.interpolationMask = false(2, 1);

config = struct;
config.etaPvAC = 0.95;
config.etaPvDC = 0.95;
config.etaBatteryCharge = 0.95;
config.etaBatteryDischarge = 0.95;
config.transferLossFraction = row.TransferLossFraction;
config.xi = row.TransferLossFraction;
config.pvBoundaryId = row.PvBoundaryId;
config.capacityRatio = row.CapacityRatio;
config.powerRatio = row.PowerRatio;
config.selfDischargeKW = 0;
config.batteryCapacityKWh = 10 .* row.CapacityRatio;
config.batteryPowerKW = 3.3 .* row.PowerRatio;
config.socInitialFraction = 0.1;
config.socMinFraction = 0.1;
config.socMaxFraction = 0.9;
config.socTerminalFraction = 0.1;
config.constraintTolerance = 1e-8;
config.lexicographicTolerance = 1e-7;
config.nightPrice = 0.091;
config.dayPrice = 0.194;
config.dayStartHour = 10;
config.dayEndHour = 22;

caseMeta = struct;
caseMeta.experimentId = row.ExperimentId;
if ismember("CaseId", string(row.Properties.VariableNames))
    caseMeta.caseId = row.CaseId;
end
caseMeta.day = row.Day;
caseMeta.scenarioId = row.ScenarioId;
caseMeta.pairId = row.PairId;
caseMeta.strategy = row.Strategy;
caseMeta.cohortId = row.CohortId;
caseMeta.pvBoundaryId = row.PvBoundaryId;
caseMeta.h4MaskAffected = false;
caseMeta.qualityMode = row.QualityMode;
caseMeta.capacityRatio = row.CapacityRatio;
caseMeta.powerRatio = row.PowerRatio;
caseMeta.transferLossFraction = row.TransferLossFraction;
caseMeta.xi = row.TransferLossFraction;
caseMeta.dataContractId = truth.DataContractId;
caseMeta.dataContractSha256 = truth.DataContractSha256;
caseMeta.dataContractGitCommit = truth.DataContractGitCommit;
caseMeta.modelContractId = truth.ModelContractId;
caseMeta.modelContractSha256 = truth.ModelContractSha256;
caseMeta.referenceIds = truth.ReferenceIds;
caseMeta.referenceHashes = truth.ReferenceHashes;
caseMeta.referenceManifestSha256 = truth.ReferenceManifestSha256;
caseMeta.solverProvenance = struct("name", "syntheticSolver");
caseMeta.dataProviderProvenance = struct("name", "syntheticProvider");

zeroFlow = zeros(2, 1);
solution = struct;
solution.strategy = row.Strategy;
solution.pvToHomeKW = zeroFlow;
solution.pvToBatteryKW = zeroFlow;
solution.pvToGridKW = zeroFlow;
solution.pvCurtailKW = data.pvKW;
solution.gridToHomeKW = data.loadKW;
solution.gridToBatteryKW = zeroFlow;
solution.batteryToHomeKW = zeroFlow;
solution.batteryToGridKW = zeroFlow;
solution.socKWh = repmat(config.socInitialFraction .* ...
    config.batteryCapacityKWh, 3, 1);
solution.chargeOn = zeroFlow;
solution.dischargeOn = zeroFlow;
solution.batteryChargeKW = zeroFlow;
solution.batteryDischargeKW = zeroFlow;
solution.aggregateImportKW = data.loadKW;
solution.objectiveStages = struct([]);
metrics = evaluate_storenet(data, config, solution);
solution.objectiveStages = syntheticStages(row.Strategy, metrics, ...
    config.lexicographicTolerance);
solution.exitFlags = ones(1, numel(solution.objectiveStages));
end

function stages = syntheticStages(strategy, metrics, tolerance)
switch string(strategy)
    case {"SH_BM", "VPP_BM", "IMPROVED_PEAK_GUARD"}
        names = ["billEUR"; "batteryThroughputKWh"];
        values = [metrics.optimizedBillEUR; metrics.totalBatteryThroughputKWh];
    case "PS"
        names = ["systemPeakKW"; "billEUR"; "batteryThroughputKWh"];
        values = [metrics.peakImportKW; metrics.optimizedBillEUR; ...
            metrics.totalBatteryThroughputKWh];
    case "PSDT"
        names = ["daytimePeakKW"; "billEUR"; "batteryThroughputKWh"];
        values = [metrics.daytimePeakImportKW; metrics.optimizedBillEUR; ...
            metrics.totalBatteryThroughputKWh];
    case "LL"
        names = ["importSpreadKW"; "billEUR"; "batteryThroughputKWh"];
        values = [metrics.importSpreadKW; metrics.optimizedBillEUR; ...
            metrics.totalBatteryThroughputKWh];
    otherwise
        error("StoreNet:InvalidSyntheticStrategy", ...
            "Unknown synthetic strategy: %s", strategy);
end
stages = repmat(stageRecord("", NaN, NaN, false, NaN), ...
    numel(names), 1);
for stageIndex = 1:numel(names)
    locked = stageIndex < numel(names);
    allowance = NaN;
    if locked
        allowance = tolerance .* max(1, abs(values(stageIndex)));
    end
    stages(stageIndex) = stageRecord(names(stageIndex), ...
        values(stageIndex), allowance, locked, values(stageIndex));
end
end

function stage = stageRecord(name, value, allowance, locked, finalValue)
stage = struct(name=name, value=value, solverObjective=value, ...
    exitFlag=1, relativeGap=0, allowance=allowance, ...
    lockedInLaterStage=locked, finalRecomputedValue=finalValue, ...
    message="synthetic optimal");
end

function dates = monthlyDays()
dates = NaT(48, 1);
sampleDays = [1, 2, 15, 16];
rowIndex = 0;
for monthIndex = 1:12
    for sampleIndex = 1:numel(sampleDays)
        rowIndex = rowIndex + 1;
        dates(rowIndex) = datetime(2020, monthIndex, ...
            sampleDays(sampleIndex));
    end
end
end

function writePaperOutputs(root, sensitivity)
strategies = ["SH_BM"; "VPP_BM"; "PS"; "PSDT"; "LL"; "SB_SC"];
profiles = table(repmat(datetime(2020, 8, 24, 0, 30, 0), 6, 1), ...
    repmat(datetime(2020, 8, 24, 0, 0, 0), 6, 1), ...
    [repmat("DC_XI007_H20", 5, 1); "OBSERVED_RELEASE_H20_PV10"], ...
    repmat("H20_PV10", 6, 1), ...
    [repmat("DC_SOURCE", 5, 1); "OBSERVED_RELEASE_FIELDS"], ...
    [repmat(0.07, 5, 1); NaN], strategies, ...
    [repmat("STRUCTURAL_PROXY", 5, 1); ...
    "OBSERVED_RELEASE_PROXY"], ones(6, 1), ones(6, 1), ...
    ones(6, 1), zeros(6, 1), zeros(6, 1), ...
    VariableNames=["TimeEnd", "IntervalStart", "ScenarioId", ...
    "CohortId", "PvBoundaryId", "TransferLossFraction", "Strategy", ...
    "ProfileKind", "LoadKW", "PvKW", "GridKW", "BatteryKW", ...
    "FeedInKW"]);
writetable(profiles, fullfile(root, "typical", "figure5_profiles.csv"));
comparison = table(strategies, nan(6, 1), nan(6, 1), nan(6, 1), ...
    repmat("quality_rejected", 6, 1), repmat("synthetic reference", 6, 1), ...
    VariableNames=["Strategy", "PaperPrintedSavingsPercent", ...
    "LocalPaperLoadOnlySavingsPercent", "DifferencePercentagePoints", ...
    "LocalStatus", "SourceNote"]);
writetable(comparison, fullfile(root, "typical", ...
    "figure5_target_comparison.csv"));

monthlyProfiles = table(datetime(2020, 8, 1), "DC_XI007_H20", ...
    "DC_XI007", "H20_PV10", "DC_SOURCE", 0.07, "VPP_BM", ...
    "optimized", 1, 1, 1, 1, 1, ...
    VariableNames=["YearMonth", "ScenarioId", "PairId", "CohortId", ...
    "PvBoundaryId", "TransferLossFraction", "Strategy", "ProfileType", ...
    "IntervalIndex", "IntervalEndHour", "MeanOriginalLoadKW", ...
    "MeanGridImportKW", "ValidProfileDays"]);
writetable(monthlyProfiles, fullfile(root, "monthly", ...
    "monthly_mean_profiles.csv"));

tableI = sensitivity(sensitivity.ExperimentId == "TABLE_I", ...
    ["CaseId", "Day", "BudgetId", "Strategy", "ScenarioId", ...
    "PairId", "CohortId", "PvBoundaryId", "TransferLossFraction", ...
    "SensitivityRole", "CapacityRatio", "PowerRatio", "Status"]);
tableI.PaperTargetSavingsPercent = zeros(height(tableI), 1);
tableI.LocalPaperSavingsPercent = sensitivity.PaperLoadOnlySavingsPercent( ...
    sensitivity.ExperimentId == "TABLE_I");
tableI.DifferencePercentagePoints = tableI.LocalPaperSavingsPercent - ...
    tableI.PaperTargetSavingsPercent;
writetable(tableI, fullfile(root, "sensitivity", ...
    "table_i_target_vs_local.csv"));

writeValidPng(fullfile(root, "typical", "figure5_proxy.png"));
writeValidPng(fullfile(root, "monthly", "figure6_proxy.png"));
writeValidPng(fullfile(root, "sensitivity", ...
    "figure7_primary_h4_surface.png"));
end

function writeValidPng(path)
imwrite(uint8(zeros(2, 2, 3)), path, "png");
end

function writeInterpretation(path)
writeText(path, ["# Scientific interpretation", ...
    "These outputs are a PROXY based on the public release.", ...
    "They are NOT EXACT reproductions of undisclosed dashboard traces.", ...
    "There was NO POST-SOLVE TUNING against paper targets."]);
end

function writeScientificManifest(root)
manifestPath = string(fullfile(root, ...
    "SCIENTIFIC_ARTIFACT_MANIFEST.sha256"));
if isfile(manifestPath)
    delete(manifestPath);
end
files = dir(fullfile(root, "**", "*"));
files = files(~[files.isdir]);
paths = strings(numel(files), 1);
for fileIndex = 1:numel(files)
    paths(fileIndex) = string(fullfile(files(fileIndex).folder, ...
        files(fileIndex).name));
end
paths = unique(paths, "sorted");
lines = strings(numel(paths), 1);
for pathIndex = 1:numel(paths)
    relative = extractAfter(paths(pathIndex), strlength(root) + 1);
    relative = replace(relative, "\", "/");
    lines(pathIndex) = sha256FileForTest(paths(pathIndex)) + ...
        "  " + relative;
end
writeText(manifestPath, lines);
end

function writeJson(path, value)
writeText(path, string(jsonencode(value, PrettyPrint=true)));
end

function writeText(path, lines)
fileId = fopen(path, "wt", "n", "UTF-8");
assert(fileId >= 0, "Synthetic fixture could not create text output.");
cleaner = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s\n", lines);
clear cleaner
end

function writeBytes(path, bytes)
fileId = fopen(path, "wb");
assert(fileId >= 0, "Synthetic fixture could not create binary output.");
cleaner = onCleanup(@() fclose(fileId));
fwrite(fileId, bytes, "uint8");
clear cleaner
end

function hash = sha256FileForTest(path)
hash = storenetio.hashFile(path);
end

function rewriteSolutionArtifact(root, path, mutation)
loaded = load(path, "solutionEvidence");
solutionEvidence = loaded.solutionEvidence;
switch string(mutation)
    case "observed_profile"
        solutionEvidence.profiles.GridImportKW(1) = ...
            solutionEvidence.profiles.GridImportKW(1) + 1;
    case "unlock_stages"
        for stageIndex = 1:numel(solutionEvidence.solution.objectiveStages)
            solutionEvidence.solution.objectiveStages( ...
                stageIndex).lockedInLaterStage = false;
        end
    case "locked_stage_roundoff"
        stageIndex = firstLockedStage( ...
            solutionEvidence.solution.objectiveStages);
        stage = solutionEvidence.solution.objectiveStages(stageIndex);
        solutionEvidence.solution.objectiveStages(stageIndex). ...
            finalRecomputedValue = stage.value + stage.allowance + 5e-13;
    case "locked_stage_violation"
        stageIndex = firstLockedStage( ...
            solutionEvidence.solution.objectiveStages);
        stage = solutionEvidence.solution.objectiveStages(stageIndex);
        solutionEvidence.solution.objectiveStages(stageIndex). ...
            finalRecomputedValue = stage.value + stage.allowance + 1e-9;
    case "negative_flow"
        solution = solutionEvidence.solution;
        delta = 0.5;
        inputFile = dir(fullfile(fileparts(path), "inputs_*.mat"));
        assert(isscalar(inputFile), "Synthetic artifact input is not unique.");
        input = load(fullfile(inputFile.folder, inputFile.name), ...
            "inputEvidence");
        eta = input.inputEvidence.config.etaPvAC;
        solution.pvToHomeKW(1) = solution.pvToHomeKW(1) + delta;
        solution.pvCurtailKW(1) = solution.pvCurtailKW(1) - delta ./ eta;
        solution.gridToHomeKW(1) = solution.gridToHomeKW(1) - delta;
        solution.aggregateImportKW(1) = ...
            solution.aggregateImportKW(1) - delta;
        solutionEvidence.solution = solution;
    otherwise
        error("StoreNet:InvalidSyntheticMutation", ...
            "Unknown synthetic solution mutation: %s", mutation);
end
save(path, "solutionEvidence", "-v7");
newHash = sha256FileForTest(path);
newPath = fullfile(fileparts(path), "solution_" + newHash + ".mat");
movefile(path, newPath);
updateArtifactReferences(root, path, newPath, newHash, "Solution");
end

function stageIndex = firstLockedStage(stages)
stageIndex = find([stages.lockedInLaterStage], 1, "first");
assert(~isempty(stageIndex), "Synthetic artifact has no locked stage.");
end

function rewriteInputArtifact(root, path, mutation)
loaded = load(path, "inputEvidence");
inputEvidence = loaded.inputEvidence;
switch string(mutation)
    case "wrong_power"
        inputEvidence.config.batteryPowerKW = ...
            2 .* inputEvidence.config.batteryPowerKW;
    otherwise
        error("StoreNet:InvalidSyntheticMutation", ...
            "Unknown synthetic input mutation: %s", mutation);
end
save(path, "inputEvidence", "-v7");
newHash = sha256FileForTest(path);
newPath = fullfile(fileparts(path), "inputs_" + newHash + ".mat");
movefile(path, newPath);
updateArtifactReferences(root, path, newPath, newHash, "Inputs");
end

function updateArtifactReferences(root, oldPath, newPath, hash, prefix)
files = dir(fullfile(root, "**", "*.csv"));
pathColumn = prefix + "Path";
hashColumn = prefix + "Sha256";
for fileIndex = 1:numel(files)
    csvPath = fullfile(files(fileIndex).folder, files(fileIndex).name);
    value = readtable(csvPath, Delimiter=",", TextType="string", ...
        VariableNamingRule="preserve");
    variables = string(value.Properties.VariableNames);
    if ~all(ismember([pathColumn, hashColumn], variables))
        continue
    end
    selected = string(value.(pathColumn)) == string(oldPath);
    if any(selected)
        value.(pathColumn)(selected) = string(newPath);
        value.(hashColumn)(selected) = hash;
        writetable(value, csvPath);
    end
end
end

function appendByte(path)
fileId = fopen(path, "ab");
assert(fileId >= 0, "Synthetic fixture could not open artifact.");
cleaner = onCleanup(@() fclose(fileId));
fwrite(fileId, uint8(0), "uint8");
clear cleaner
end

