function acceptance = evaluate_bahloul_acceptance_v1(formalRoot)
%EVALUATE_BAHLOUL_ACCEPTANCE_V1 Apply the B2022 R1--R8 post-solve gates.
%   Every missing, malformed, nonfinite, or out-of-tolerance item is a FAIL.
%   SCIENTIFIC_INTERPRETATION.md must contain the case-insensitive fixed
%   disclosures "PROXY", "NOT EXACT", and "NO POST-SOLVE TUNING".

arguments
    formalRoot (1, 1) string
end

if ~isfolder(formalRoot)
    error("StoreNet:MissingBahloulFormalRoot", ...
        "Formal result root does not exist: %s", formalRoot);
end
formalRoot = canonicalFolder(formalRoot);
csvPath = string(fullfile(formalRoot, "postsolve_acceptance.csv"));
jsonPath = string(fullfile(formalRoot, "postsolve_acceptance.json"));

[truth, truthPass, truthDetails] = auditFormalTruth(formalRoot);
[caseTable, inventory] = auditCases(formalRoot, truth);
rules = repmat(emptyRule(), 8, 1);
rules(1) = caseRule("R1", "Solver convergence", caseTable, ...
    "R1Pass", inventory, "exitFlag > 0; finite relativeGap <= 1e-6");
rules(2) = caseRule("R2", "Physical feasibility", caseTable, ...
    "R2Pass", inventory, ...
    "all equality, SoC, power, nonnegative, and simultaneous metrics <= 1e-7");
rules(3) = caseRule("R3", "Lexicographic preservation", caseTable, ...
    "R3Pass", inventory, ...
    "every locked stage final value <= value + allowance");
try
    [matrixPass, r4Observed, r4Details, reports] = ...
        auditFixedMatrices(formalRoot, truth);
    [coveragePass, reportMetricPass, coverageObserved, ...
        coverageDetails] = auditReportedArtifacts(formalRoot, reports, ...
        caseTable, truth);
catch exception
    matrixPass = false;
    coveragePass = false;
    reportMetricPass = false;
    r4Observed = "audit error";
    r4Details = string(exception.identifier) + ": " + ...
        string(exception.message);
    coverageObserved = "audit error";
    coverageDetails = r4Details;
end
criticalCases = caseTable.CriticalArtifact;
identityPass = any(criticalCases) && ...
    all(caseTable.IdentityPass(criticalCases));
r4Pass = matrixPass && coveragePass && identityPass && truthPass;
r4Observed = r4Observed + compose("; provenanceIdentityPassed=%d/%d", ...
    nnz(caseTable.IdentityPass & criticalCases), nnz(criticalCases)) + "; " + ...
    coverageObserved;
if ~truthPass
    r4Details = appendDetail(r4Details, truthDetails);
end
if ~identityPass
    r4Details = appendDetail(r4Details, ...
        "one or more input identity records disagree with the root manifest/reference inventory");
end
r4Details = appendDetail(r4Details, coverageDetails);
rules(4) = makeRule("R4", "Frozen matrix completeness", r4Pass, ...
    "typical=10; sensitivity=81+15; monthlyDaily=48*5; monthly=12*5", ...
    r4Observed, r4Details);

artifactMetricPass = inventory.pairingPassed && any(criticalCases) && ...
    all(caseTable.R5Pass(criticalCases));
r5Pass = artifactMetricPass && coveragePass && reportMetricPass;
r5Observed = compose("cases=%d; artifactMetricFailures=%d; %s", ...
    nnz(criticalCases), nnz(criticalCases & ~caseTable.R5Pass), ...
    coverageObserved);
r5Details = failureCaseSummary(caseTable(criticalCases, :), "R5Pass");
r5Details = appendDetail(r5Details, coverageDetails);
rules(5) = makeRule("R5", "Independent artifact reevaluation", r5Pass, ...
    "each successful model row uniquely joins content-addressed evidence; " + ...
    "MAT and CSV finite scalars agree at 1e-9 scale", ...
    r5Observed, r5Details);
try
    [r6Pass, r6Observed, r6Details] = auditPaperOutputs(formalRoot);
catch exception
    r6Pass = false;
    r6Observed = "audit error";
    r6Details = string(exception.identifier) + ": " + ...
        string(exception.message);
end
rules(6) = makeRule("R6", "Paper-facing outputs", r6Pass, ...
    "Figure 5/6/7, Table I, profiles and comparisons", ...
    r6Observed, r6Details);
try
    [r7Pass, r7Observed, r7Details] = auditResultManifest(formalRoot);
catch exception
    r7Pass = false;
    r7Observed = "audit error";
    r7Details = string(exception.identifier) + ": " + ...
        string(exception.message);
end
rules(7) = makeRule("R7", "Result checksum closure", r7Pass, ...
    "SCIENTIFIC_ARTIFACT_MANIFEST.sha256 excludes itself and verifies 100%", ...
    r7Observed, r7Details);
try
    [r8Pass, r8Observed, r8Details] = auditInterpretation(formalRoot);
catch exception
    r8Pass = false;
    r8Observed = "audit error";
    r8Details = string(exception.identifier) + ": " + ...
        string(exception.message);
end
rules(8) = makeRule("R8", "Scientific interpretation", r8Pass, ...
    "fixed disclosures: PROXY; NOT EXACT; NO POST-SOLVE TUNING", ...
    r8Observed, r8Details);

ruleTable = struct2table(rules);
overallPass = all(ruleTable.Status == "PASS");
overallStatus = "FAIL";
if overallPass
    overallStatus = "PASS";
end

acceptance = struct;
acceptance.schemaVersion = "B2022-postsolve-acceptance-v1";
acceptance.contractId = "B2022-IR-v1";
acceptance.formalRoot = formalRoot;
acceptance.generatedAtUtc = string(datetime("now", TimeZone="UTC", ...
    Format="yyyy-MM-dd'T'HH:mm:ss.SSSXXX"));
acceptance.overallStatus = overallStatus;
acceptance.allRulesPassed = overallPass;
acceptance.ruleTable = ruleTable;
acceptance.caseTable = caseTable;
acceptance.inventory = inventory;
acceptance.disclosureRequirements = ...
    ["PROXY", "NOT EXACT", "NO POST-SOLVE TUNING"];
acceptance.csvPath = csvPath;
acceptance.jsonPath = jsonPath;

writeTableAtomic(ruleTable, csvPath);
writeJsonAtomic(acceptance, jsonPath);
end

function [truth, passed, details] = auditFormalTruth(formalRoot)
truth = struct(DataContractId="", DataContractSha256="", ...
    DataContractGitCommit="", ModelContractId="", ...
    ModelContractSha256="", ReferenceManifestSha256="", ...
    ReferenceIds=strings(0, 1), ReferenceHashes=strings(0, 1), ...
    TypicalDay=NaT, QualityMode="");
passed = false;
manifestPath = string(fullfile(formalRoot, "manifest.json"));
referencePath = string(fullfile(formalRoot, "evidence", ...
    "B2022_REFERENCE_MANIFEST.csv"));
if ~isfile(manifestPath) || ~isfile(referencePath)
    details = "root manifest.json and evidence/B2022_REFERENCE_MANIFEST.csv are required";
    return
end
try
    manifest = jsondecode(fileread(manifestPath));
    requiredManifest = isfield(manifest, "schemaVersion") && ...
        string(manifest.schemaVersion) == "StoreNet-run-manifest-v2" && ...
        isfield(manifest, "formalMode") && logical(manifest.formalMode) && ...
        isfield(manifest, "contracts") && ...
        isfield(manifest.contracts, "data") && ...
        isfield(manifest.contracts, "model") && ...
        isfield(manifest, "references") && ...
        isfield(manifest, "experiment");
    if ~requiredManifest
        details = "manifest.json is not a formal StoreNet-run-manifest-v2";
        return
    end
    truth.DataContractId = scalarText(manifest.contracts.data, ...
        "contractId");
    truth.DataContractSha256 = lower(scalarText( ...
        manifest.contracts.data, "contractSha256"));
    truth.DataContractGitCommit = lower(scalarText( ...
        manifest.contracts.data, "gitCommit"));
    truth.ModelContractId = scalarText(manifest.contracts.model, ...
        "contractId");
    truth.ModelContractSha256 = lower(scalarText( ...
        manifest.contracts.model, "contractSha256"));
    truth.ReferenceManifestSha256 = lower(scalarText( ...
        manifest.references, "referenceManifestSha256"));
    truth.TypicalDay = datetime(scalarText(manifest.experiment, ...
        "typicalDay"), InputFormat="yyyy-MM-dd");
    truth.QualityMode = scalarText(manifest.experiment, "qualityMode");
    references = readtable(referencePath, Delimiter=",", ...
        TextType="string", VariableNamingRule="preserve");
    requireColumns(references, ["ArtifactId", "Sha256"], ...
        "B2022_REFERENCE_MANIFEST.csv");
    truth.ReferenceIds = strip(string(references.ArtifactId(:)));
    truth.ReferenceHashes = lower(strip(string(references.Sha256(:))));
    wellFormed = truth.DataContractId == "SR2020-IR-v2" && ...
        truth.ModelContractId == "B2022-IR-v1" && ...
        truth.QualityMode == "release_literal" && ...
        truth.TypicalDay == datetime(2020, 8, 24) && ...
        isSha256(truth.DataContractSha256) && ...
        isSha256(truth.ModelContractSha256) && ...
        isGitCommit(truth.DataContractGitCommit) && ...
        isSha256(truth.ReferenceManifestSha256) && ...
        ~isempty(truth.ReferenceIds) && ...
        numel(unique(truth.ReferenceIds)) == numel(truth.ReferenceIds) && ...
        all(arrayfun(@isSha256, truth.ReferenceHashes));
    referenceHashPassed = sha256File(referencePath) == ...
        truth.ReferenceManifestSha256;
    passed = wellFormed && referenceHashPassed;
    details = compose("manifest=%d; referenceInventory=%d; referenceHash=%d", ...
        wellFormed, numel(truth.ReferenceIds), referenceHashPassed);
catch exception
    details = string(exception.identifier) + ": " + ...
        string(exception.message);
end
end

function value = scalarText(container, field)
if ~isstruct(container) || ~isfield(container, field)
    error("StoreNet:MissingAcceptanceTruth", ...
        "Formal manifest is missing field '%s'.", field);
end
value = strip(string(container.(field)));
if ~isscalar(value) || ismissing(value) || strlength(value) == 0
    error("StoreNet:InvalidAcceptanceTruth", ...
        "Formal manifest field '%s' must be a nonempty scalar.", field);
end
end

function passed = isSha256(value)
passed = isscalar(value) && ~ismissing(value) && ...
    ~isempty(regexp(char(value), '^[0-9a-f]{64}$', 'once'));
end

function passed = isGitCommit(value)
passed = isscalar(value) && ~ismissing(value) && ...
    ~isempty(regexp(char(value), '^[0-9a-f]{40}$', 'once'));
end

function [caseTable, inventory] = auditCases(formalRoot, truth)
solutionFiles = recursiveFiles(formalRoot, "solution_*.mat");
inputFiles = recursiveFiles(formalRoot, "inputs_*.mat");
solutionDirectories = fileDirectories(solutionFiles);
inputDirectories = fileDirectories(inputFiles);
caseDirectories = unique([solutionDirectories; inputDirectories], "sorted");
rows = repmat(emptyCaseRow(), numel(caseDirectories), 1);

for caseIndex = 1:numel(caseDirectories)
    caseDirectory = caseDirectories(caseIndex);
    localSolutions = solutionFiles(solutionDirectories == caseDirectory);
    localInputs = inputFiles(inputDirectories == caseDirectory);
    row = emptyCaseRow();
    row.CaseDirectory = relativePath(formalRoot, caseDirectory);
    row.InputCount = numel(localInputs);
    row.SolutionCount = numel(localSolutions);
    if isscalar(localInputs)
        row.InputsPath = relativePath(formalRoot, fullPath(localInputs));
    end
    if isscalar(localSolutions)
        row.SolutionPath = relativePath(formalRoot, fullPath(localSolutions));
    end
    if numel(localInputs) ~= 1 || numel(localSolutions) ~= 1
        row.ErrorIdentifier = "StoreNet:IncompleteBahloulArtifact";
        row.ErrorMessage = "Each case requires exactly one content-addressed " + ...
            "input and solution file.";
        rows(caseIndex) = row;
        continue
    end
    try
        effectiveSolution = struct;
        [schema, inputEvidence] = inputEvidenceSchema(fullPath(localInputs));
        [experimentId, experimentAvailable] = identityValue( ...
            inputEvidence.identity, "experimentId");
        row.ExperimentId = strip(string(experimentId));
        row.CriticalArtifact = experimentAvailable && ismember( ...
            row.ExperimentId, ["B2022_TYPICAL_V1", "TABLE_I"]);
        if schema == "B2022-observed-input-evidence-v2"
            row.ArtifactKind = "observed";
            [recomputedMetrics, recomputedProfiles, evidence] = ...
                reevaluate_bahloul_observed_artifact(caseDirectory);
            row.R1Pass = true;
            row.R1Details = "not applicable to observed proxy";
            row.R2Pass = true;
            row.R2Details = "not applicable to observed proxy";
            row.R3Pass = true;
            row.R3Details = "not applicable to observed proxy";
            [metricPassed, row.MaximumScaledMetricDifference, ...
                metricDetails] = auditObservedMetricAgreement( ...
                recomputedMetrics, evidence.persistedMetrics);
            [profilePassed, profileDetails] = ...
                auditObservedProfileAgreement(recomputedProfiles, ...
                evidence.persistedProfiles);
            row.R5Pass = metricPassed && profilePassed;
            row.R5Details = metricDetails + "; " + profileDetails;
        else
            row.ArtifactKind = "model";
            [recomputedMetrics, evidence] = ...
                reevaluate_bahloul_artifact(caseDirectory);
            effectiveSolution = evidence.solution;
            strategy = effectiveStrategy(evidence.input, evidence.solution);
            [row.R1Pass, row.MaximumRelativeGap, row.R1Details] = ...
                auditStages(evidence.solution);
            [row.R2Pass, row.MaximumPhysicalViolation, row.R2Details] = ...
                auditPhysicalMetrics(recomputedMetrics, evidence.solution, ...
                strategy);
            [row.R3Pass, row.MaximumLockedStageViolation, row.R3Details] = ...
                auditLockedStages(evidence.solution, recomputedMetrics, ...
                evidence.input.config, strategy);
            [row.R5Pass, row.MaximumScaledMetricDifference, row.R5Details] = ...
                auditMetricAgreement(recomputedMetrics, ...
                evidence.persistedMetrics);
        end
        row.ReevaluationStatus = "ok";
        [provenancePassed, provenanceDetails] = ...
            auditInputIdentity(evidence.input, truth);
        [bindingPassed, bindingDetails] = auditEffectiveCaseBinding( ...
            evidence.input, effectiveSolution, row.ArtifactKind);
        row.IdentityPass = provenancePassed && bindingPassed;
        row.IdentityDetails = provenanceDetails + "; " + bindingDetails;
    catch exception
        row.ErrorIdentifier = string(exception.identifier);
        row.ErrorMessage = string(getReport(exception, "extended", ...
            "hyperlinks", "off"));
        row.R1Details = "artifact reevaluation failed";
        row.R2Details = "artifact reevaluation failed";
        row.R3Details = "artifact reevaluation failed";
        row.R5Details = "artifact reevaluation failed";
    end
    rows(caseIndex) = row;
end

if isempty(rows)
    caseTable = struct2table(emptyCaseRow());
    caseTable(1, :) = [];
else
    caseTable = struct2table(rows);
end
inventory = struct;
inventory.solutionFileCount = numel(solutionFiles);
inventory.inputFileCount = numel(inputFiles);
inventory.caseDirectoryCount = numel(caseDirectories);
critical = caseTable.CriticalArtifact;
inventory.criticalCaseDirectoryCount = nnz(critical);
inventory.pairingPassed = any(critical) && ...
    all(caseTable.InputCount(critical) == 1 & ...
    caseTable.SolutionCount(critical) == 1);
end

function row = emptyCaseRow()
row = struct(CaseDirectory="", InputsPath="", SolutionPath="", ...
    InputCount=0, SolutionCount=0, ArtifactKind="unknown", ...
    ExperimentId="", CriticalArtifact=false, ...
    ReevaluationStatus="failed", ...
    ErrorIdentifier="", ErrorMessage="", R1Pass=false, ...
    MaximumRelativeGap=NaN, R1Details="not evaluated", R2Pass=false, ...
    MaximumPhysicalViolation=NaN, R2Details="not evaluated", ...
    R3Pass=false, MaximumLockedStageViolation=NaN, ...
    R3Details="not evaluated", R5Pass=false, ...
    MaximumScaledMetricDifference=NaN, R5Details="not evaluated", ...
    IdentityPass=false, IdentityDetails="not evaluated");
end

function [schema, inputEvidence] = inputEvidenceSchema(path)
loaded = load(path, "inputEvidence");
if ~isfield(loaded, "inputEvidence") || ...
        ~isstruct(loaded.inputEvidence) || ...
        ~isfield(loaded.inputEvidence, "schemaVersion")
    error("StoreNet:InvalidBahloulArtifact", ...
        "Input artifact lacks inputEvidence.schemaVersion.");
end
inputEvidence = loaded.inputEvidence;
schema = string(inputEvidence.schemaVersion);
if ~ismember(schema, ["B2022-input-evidence-v2", ...
        "B2022-observed-input-evidence-v2"])
    error("StoreNet:InvalidBahloulArtifact", ...
        "Unsupported input evidence schema: %s", schema);
end
end

function [passed, details] = auditInputIdentity(inputEvidence, truth)
passed = false;
details = "input identity missing";
if ~isstruct(inputEvidence) || ~isfield(inputEvidence, "identity") || ...
        ~isstruct(inputEvidence.identity) || ...
        ~isscalar(inputEvidence.identity)
    return
end
identity = inputEvidence.identity;
required = ["dataContractId", "dataContractSha256", ...
    "dataContractGitCommit", "modelContractId", "modelContractSha256", ...
    "referenceIds", "referenceHashes", "referenceManifestSha256"];
missing = required(~isfield(identity, cellstr(required)));
if ~isempty(missing)
    details = "identity missing: " + strjoin(missing, ",");
    return
end
for fieldIndex = 1:numel(required)
    record = identity.(required(fieldIndex));
    if ~isstruct(record) || ~isscalar(record) || ...
            ~isfield(record, "available") || ...
            ~isscalar(record.available) || ~logical(record.available)
        details = "identity field unavailable: " + required(fieldIndex);
        return
    end
end
actual = struct;
for fieldIndex = 1:numel(required)
    actual.(required(fieldIndex)) = identity.(required(fieldIndex)).value;
end
scalarMatches = isequal(strip(string(actual.dataContractId)), ...
    truth.DataContractId) && ...
    isequal(lower(strip(string(actual.dataContractSha256))), ...
    truth.DataContractSha256) && ...
    isequal(lower(strip(string(actual.dataContractGitCommit))), ...
    truth.DataContractGitCommit) && ...
    isequal(strip(string(actual.modelContractId)), truth.ModelContractId) && ...
    isequal(lower(strip(string(actual.modelContractSha256))), ...
    truth.ModelContractSha256) && ...
    isequal(lower(strip(string(actual.referenceManifestSha256))), ...
    truth.ReferenceManifestSha256);
actualIds = strip(string(actual.referenceIds(:)));
actualHashes = lower(strip(string(actual.referenceHashes(:))));
referenceMatches = isequal(actualIds, truth.ReferenceIds) && ...
    isequal(actualHashes, truth.ReferenceHashes);
passed = scalarMatches && referenceMatches;
details = compose("rootScalarMatch=%d; referenceInventoryMatch=%d", ...
    scalarMatches, referenceMatches);
end

function strategy = effectiveStrategy(inputEvidence, solution)
[strategy, available] = identityValue(inputEvidence.identity, "strategy");
strategy = strip(string(strategy));
if ~available || ~isscalar(strategy) || strlength(strategy) == 0 || ...
        ~isfield(solution, "strategy") || ...
        ~isscalar(string(solution.strategy)) || ...
        strip(string(solution.strategy)) ~= strategy
    error("StoreNet:AcceptanceStrategyBindingMismatch", ...
        "Model solution.strategy must equal the available input identity strategy.");
end
end

function [passed, details] = auditEffectiveCaseBinding( ...
        inputEvidence, solution, artifactKind)
passed = false;
details = "effective case binding unavailable";
if ~isstruct(inputEvidence) || ~isfield(inputEvidence, "identity") || ...
        ~isfield(inputEvidence, "config") || ...
        ~isstruct(inputEvidence.config) || ~isscalar(inputEvidence.config)
    return
end
identity = inputEvidence.identity;
config = inputEvidence.config;
[strategy, strategyAvailable] = identityValue(identity, "strategy");
[xi, xiAvailable] = identityValue(identity, "xi");
[capacityRatio, capacityAvailable] = identityValue(identity, "capacityRatio");
[powerRatio, powerAvailable] = identityValue(identity, "powerRatio");
strategy = strip(string(strategy));
if artifactKind == "observed"
    boundaryPassed = isfield(config, "pvBoundaryId") && ...
        string(config.pvBoundaryId) == "OBSERVED_RELEASE_FIELDS";
    xiPassed = xiAvailable && isnumeric(xi) && isscalar(xi) && isnan(xi) && ...
        hasNaNConfigScalar(config, "xi") && ...
        hasNaNConfigScalar(config, "transferLossFraction");
    passed = strategyAvailable && strategy == "SB_SC" && ...
        boundaryPassed && xiPassed;
    details = compose("observedStrategy=%d; boundary=%d; xiNaN=%d", ...
        strategyAvailable && strategy == "SB_SC", boundaryPassed, xiPassed);
    return
end
requiredConfig = ["batteryCapacityKWh", "batteryPowerKW", ...
    "transferLossFraction"];
if ~all(isfield(config, cellstr(requiredConfig))) || ...
        ~strategyAvailable || ~xiAvailable || ~capacityAvailable || ...
        ~powerAvailable
    details = "model identity/config lacks strategy, xi, or battery ratios";
    return
end
identityNumeric = isnumeric(capacityRatio) && isscalar(capacityRatio) && ...
    isnumeric(powerRatio) && isscalar(powerRatio) && ...
    isnumeric(xi) && isscalar(xi);
configNumeric = isnumeric(config.batteryCapacityKWh) && ...
    isscalar(config.batteryCapacityKWh) && ...
    isnumeric(config.batteryPowerKW) && isscalar(config.batteryPowerKW) && ...
    isnumeric(config.transferLossFraction) && ...
    isscalar(config.transferLossFraction);
if ~(identityNumeric && configNumeric)
    details = "model identity/config ratings and xi must be numeric scalars";
    return
end
capacityRatio = double(capacityRatio);
powerRatio = double(powerRatio);
xi = double(xi);
actualCapacity = double(config.batteryCapacityKWh);
actualPower = double(config.batteryPowerKW);
actualXi = double(config.transferLossFraction);
expectedCapacity = 10 .* capacityRatio;
expectedPower = 3.3 .* powerRatio;
numericInputs = [capacityRatio, powerRatio, xi, actualCapacity, ...
    actualPower, actualXi];
if ~all(isfinite(numericInputs)) || any([capacityRatio, powerRatio] <= 0)
    details = "model identity/config contains nonfinite or nonpositive values";
    return
end
capacityPassed = scalarWithin(actualCapacity, expectedCapacity, 1e-12);
powerPassed = scalarWithin(actualPower, expectedPower, 1e-12);
xiPassed = scalarWithin(actualXi, xi, 1e-12);
strategyPassed = isstruct(solution) && isfield(solution, "strategy") && ...
    isscalar(string(solution.strategy)) && ...
    strip(string(solution.strategy)) == strategy;
passed = capacityPassed && powerPassed && xiPassed && strategyPassed;
details = compose("strategy=%d; capacityRatio=%d; powerRatio=%d; xi=%d", ...
    strategyPassed, capacityPassed, powerPassed, xiPassed);
end

function passed = hasNaNConfigScalar(config, field)
passed = isfield(config, field) && isnumeric(config.(field)) && ...
    isscalar(config.(field)) && isnan(double(config.(field)));
end

function passed = scalarWithin(actual, expected, tolerance)
passed = isscalar(actual) && isscalar(expected) && isfinite(actual) && ...
    isfinite(expected) && abs(actual - expected) <= tolerance * ...
    max([1, abs(actual), abs(expected)]);
end

function [passed, maximumGap, details] = auditStages(solution)
passed = false;
maximumGap = NaN;
details = "objectiveStages missing";
required = ["exitFlag", "relativeGap"];
if ~isstruct(solution) || ~isfield(solution, "objectiveStages") || ...
        isempty(solution.objectiveStages)
    return
end
stages = solution.objectiveStages(:);
if ~all(isfield(stages, cellstr(required)))
    details = "objectiveStages lacks exitFlag or relativeGap";
    return
end
exitFlags = double([stages.exitFlag]);
relativeGaps = double([stages.relativeGap]);
if numel(exitFlags) ~= numel(stages) || ...
        numel(relativeGaps) ~= numel(stages)
    details = "objectiveStages fields are not scalar";
    return
end
finiteGaps = relativeGaps(isfinite(relativeGaps));
if ~isempty(finiteGaps)
    maximumGap = max(finiteGaps);
end
passed = all(isfinite(exitFlags) & exitFlags > 0) && ...
    all(isfinite(relativeGaps) & relativeGaps >= 0 & ...
    relativeGaps <= 1e-6);
details = compose("stages=%d; minExitFlag=%.17g; maxRelativeGap=%.17g", ...
    numel(stages), min(exitFlags), maximumGap);
end

function [passed, maximumViolation, details] = auditPhysicalMetrics( ...
        metrics, solution, strategy)
names = ["energyBalanceResidualKW", "pvAllocationResidualKW", ...
    "homeBalanceResidualKW", "batteryDynamicsResidualKW", ...
    "aggregateImportResidualKW", "chargeConversionResidualKW", ...
    "dischargeConversionResidualKW", "initialSocErrorKWh", ...
    "terminalSocErrorKWh", "socBoundViolationKWh", ...
    "chargePowerViolationKW", "dischargePowerViolationKW", ...
    "aggregateImportNonnegativeViolationKW", ...
    "simultaneousChargeDischargeKW"];
values = nan(numel(names), 1);
for fieldIndex = 1:numel(names)
    if ~isfield(metrics, names(fieldIndex)) || ...
            ~isnumeric(metrics.(names(fieldIndex))) || ...
            ~isscalar(metrics.(names(fieldIndex)))
        passed = false;
        maximumViolation = NaN;
        details = "missing/non-scalar metric: " + names(fieldIndex);
        return
    end
    values(fieldIndex) = abs(double(metrics.(names(fieldIndex))));
end
flowNames = ["pvToHomeKW", "pvToBatteryKW", "pvToGridKW", ...
    "pvCurtailKW", "gridToHomeKW", "gridToBatteryKW", ...
    "batteryToHomeKW", "batteryToGridKW"];
negativeFlowViolation = 0;
for fieldIndex = 1:numel(flowNames)
    field = flowNames(fieldIndex);
    if ~isfield(solution, field) || ~isnumeric(solution.(field)) || ...
            isempty(solution.(field)) || ...
            any(~isfinite(double(solution.(field))), "all")
        passed = false;
        maximumViolation = NaN;
        details = "missing/nonfinite solution flow: " + field;
        return
    end
    flow = double(solution.(field));
    negativeFlowViolation = max(negativeFlowViolation, ...
        max([0; -flow(:)]));
end
sharingViolation = 0;
if strategy == "SH_BM"
    sharingViolation = max(abs([double(solution.pvToGridKW(:)); ...
        double(solution.batteryToGridKW(:))]));
end
maximumViolation = max([values; negativeFlowViolation; sharingViolation]);
passed = all(isfinite(values)) && isfinite(negativeFlowViolation) && ...
    isfinite(sharingViolation) && maximumViolation <= 1e-7;
details = compose("metrics=%d; maximumViolation=%.17g; " + ...
    "negativeFlowViolation=%.17g; sharingViolation=%.17g", ...
    numel(names), maximumViolation, negativeFlowViolation, sharingViolation);
end

function [passed, maximumViolation, details] = auditLockedStages( ...
        solution, metrics, config, strategy)
passed = false;
maximumViolation = NaN;
details = "objectiveStages missing";
if ~isstruct(solution) || ~isfield(solution, "objectiveStages") || ...
        isempty(solution.objectiveStages)
    return
end
stages = solution.objectiveStages(:);
expectedNames = expectedStageNames(strategy);
if numel(stages) ~= numel(expectedNames) || ...
        ~isfield(stages, "name") || ...
        ~isequal(string({stages.name}).', expectedNames)
    details = "objective stage sequence disagrees with strategy " + strategy;
    return
end
if ~isfield(stages, "lockedInLaterStage") || ...
        numel([stages.lockedInLaterStage]) ~= numel(stages)
    details = "objective stages lack scalar lockedInLaterStage flags";
    return
end
lockedValues = double([stages.lockedInLaterStage]).';
if any(~ismember(lockedValues, [0, 1]))
    details = "objective stage lock flags must be logical scalars";
    return
end
locked = logical(lockedValues);
expectedLocked = true(numel(stages), 1);
expectedLocked(end) = false;
if ~isequal(locked, expectedLocked)
    details = "objective stage lock pattern disagrees with strategy " + strategy;
    return
end
if ~isfield(config, "lexicographicTolerance") || ...
        ~isnumeric(config.lexicographicTolerance) || ...
        ~isscalar(config.lexicographicTolerance) || ...
        ~isfinite(config.lexicographicTolerance) || ...
        config.lexicographicTolerance < 0
    details = "config.lexicographicTolerance is unavailable or invalid";
    return
end
violations = zeros(0, 1);
for stageIndex = reshape(find(locked), 1, [])
    stage = stages(stageIndex);
    value = numericStructField(stage, "value");
    allowance = numericStructField(stage, "allowance");
    expectedAllowance = double(config.lexicographicTolerance) * ...
        max(1, abs(value));
    finalValue = numericStructField(stage, "finalRecomputedValue");
    if ~isfinite(finalValue) && isfield(stage, "name")
        finalValue = metricForStage(metrics, string(stage.name));
    end
    allowanceScale = max([1, abs(allowance), abs(expectedAllowance)]);
    allowanceMatches = isfinite(allowance) && ...
        abs(allowance - expectedAllowance) <= 1e-12 * allowanceScale;
    if ~isfinite(value) || ~isfinite(allowance) || allowance < 0 || ...
            ~isfinite(finalValue) || ~allowanceMatches
        details = "locked stage has missing value, allowance, or final value";
        return
    end
    valueScale = max([1, abs(value), abs(finalValue)]);
    scaleSlack = max(10 * eps(valueScale), 1e-12 * valueScale);
    violations(end + 1, 1) = max(0, ...
        finalValue - value - allowance - scaleSlack); %#ok<AGROW>
end
if isempty(violations)
    maximumViolation = 0;
else
    maximumViolation = max(violations);
end
passed = all(violations <= 0);
details = compose("lockedStages=%d; maximumViolation=%.17g", ...
    nnz(locked), maximumViolation);
end

function names = expectedStageNames(strategy)
switch strategy
    case {"SH_BM", "VPP_BM", "IMPROVED_PEAK_GUARD"}
        names = ["billEUR"; "batteryThroughputKWh"];
    case "PS"
        names = ["systemPeakKW"; "billEUR"; "batteryThroughputKWh"];
    case "PSDT"
        names = ["daytimePeakKW"; "billEUR"; "batteryThroughputKWh"];
    case "LL"
        names = ["importSpreadKW"; "billEUR"; "batteryThroughputKWh"];
    otherwise
        error("StoreNet:UnknownAcceptanceStrategy", ...
            "Unknown model strategy '%s'.", strategy);
end
end

function value = metricForStage(metrics, name)
switch name
    case "billEUR"
        value = nestedOrNaN(metrics, "optimizedBillEUR");
    case "systemPeakKW"
        value = nestedOrNaN(metrics, "peakImportKW");
    case "daytimePeakKW"
        value = nestedOrNaN(metrics, "daytimePeakImportKW");
    case "importSpreadKW"
        value = nestedOrNaN(metrics, "importSpreadKW");
    case "batteryThroughputKWh"
        value = nestedOrNaN(metrics, "totalBatteryThroughputKWh");
    otherwise
        value = NaN;
end
end

function [passed, maximumDifference, details] = auditMetricAgreement( ...
        recomputed, persisted)
paths = [ ...
    "PaperLoadOnlyBaseline.billEUR", ...
    "PaperLoadOnlyBaseline.peakImportKW", ...
    "PaperLoadOnlyBaseline.daytimePeakImportKW", ...
    "PaperLoadOnlyBaseline.savingsEUR", ...
    "PaperLoadOnlyBaseline.savingsPercent", ...
    "PaperLoadOnlyBaseline.savingsPercentDenominatorIsZero", ...
    "PvSelfNoBatteryBaseline.billEUR", ...
    "PvSelfNoBatteryBaseline.peakImportKW", ...
    "PvSelfNoBatteryBaseline.daytimePeakImportKW", ...
    "PvSelfNoBatteryBaseline.savingsEUR", ...
    "PvSelfNoBatteryBaseline.savingsPercent", ...
    "PvSelfNoBatteryBaseline.savingsPercentDenominatorIsZero", ...
    "optimizedBillEUR", "peakImportKW", "daytimePeakImportKW", ...
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
scaledDifferences = nan(numel(paths), 1);
for pathIndex = 1:numel(paths)
    actual = nestedOrNaN(recomputed, split(paths(pathIndex), "."));
    saved = nestedOrNaN(persisted, split(paths(pathIndex), "."));
    if isnan(actual) && isnan(saved)
        scaledDifferences(pathIndex) = 0;
        continue
    end
    if ~isfinite(actual) || ~isfinite(saved)
        passed = false;
        maximumDifference = NaN;
        details = "missing/nonfinite scalar metric: " + paths(pathIndex);
        return
    end
    scale = max([1, abs(actual), abs(saved)]);
    scaledDifferences(pathIndex) = abs(actual - saved) / scale;
end
maximumDifference = max(scaledDifferences);
passed = maximumDifference <= 1e-9;
details = compose("metrics=%d; maximumScaledDifference=%.17g", ...
    numel(paths), maximumDifference);
end

function [passed, maximumDifference, details] = ...
        auditObservedMetricAgreement(recomputed, persisted)
paths = ["paperLoadOnlyBaselineBillEUR", ...
    "paperLoadOnlySavingsEUR", "paperLoadOnlySavingsPercent", ...
    "paperLoadOnlySavingsPercentDenominatorIsZero", ...
    "observedReleasePvSelfNoBatteryBaselineBillEUR", ...
    "observedReleaseEngineeringSavingsEUR", ...
    "observedReleaseEngineeringSavingsPercent", ...
    "observedReleaseEngineeringSavingsPercentDenominatorIsZero", ...
    "observedBillEUR", "paperLoadOnlyPeakKW", ...
    "paperLoadOnlyDaytimePeakKW", "observedPeakImportKW", ...
    "observedDaytimePeakImportKW", "observedImportSpreadKW", ...
    "observedGridImportKWh", "releaseBatteryThroughputKWh", ...
    "totalFeedInKWh"];
[passed, maximumDifference, details] = auditScalarPaths( ...
    recomputed, persisted, paths);
end

function [passed, details] = auditObservedProfileAgreement(recomputed, persisted)
passed = istable(recomputed) && istable(persisted) && ...
    isequaln(recomputed, persisted);
if passed
    details = compose("observedProfiles=%d rows agree", height(recomputed));
else
    details = "persisted observed profiles disagree with offline reevaluation";
end
end

function [passed, maximumDifference, details] = auditScalarPaths( ...
        recomputed, persisted, paths)
scaledDifferences = nan(numel(paths), 1);
for pathIndex = 1:numel(paths)
    actual = nestedOrNaN(recomputed, split(paths(pathIndex), "."));
    saved = nestedOrNaN(persisted, split(paths(pathIndex), "."));
    [equal, scaledDifferences(pathIndex)] = scalarAgreement(actual, saved);
    if ~equal
        passed = false;
        maximumDifference = scaledDifferences(pathIndex);
        details = "missing/nonmatching scalar metric: " + paths(pathIndex);
        return
    end
end
maximumDifference = max(scaledDifferences);
passed = maximumDifference <= 1e-9;
details = compose("metrics=%d; maximumScaledDifference=%.17g", ...
    numel(paths), maximumDifference);
end

function value = nestedOrNaN(container, path)
value = NaN;
current = container;
for pathIndex = 1:numel(path)
    field = path(pathIndex);
    if ~isstruct(current) || ~isscalar(current) || ~isfield(current, field)
        return
    end
    current = current.(field);
end
if (isnumeric(current) || islogical(current)) && isscalar(current)
    value = double(current);
end
end

function value = numericStructField(container, field)
value = NaN;
if isfield(container, field) && isnumeric(container.(field)) && ...
        isscalar(container.(field))
    value = double(container.(field));
end
end

function rule = caseRule(ruleId, name, cases, passField, inventory, expected)
applicable = cases.CriticalArtifact & cases.ArtifactKind == "model";
casePasses = cases.(passField);
passed = inventory.pairingPassed && any(applicable) && ...
    all(casePasses(applicable));
failedCount = nnz(applicable) - nnz(casePasses(applicable));
observed = compose("modeledCases=%d; observedCases=%d; failed=%d; inputs=%d; solutions=%d", ...
    nnz(applicable), nnz(cases.ArtifactKind == "observed"), failedCount, ...
    inventory.inputFileCount, ...
    inventory.solutionFileCount);
details = failureCaseSummary(cases(applicable, :), passField);
if ~inventory.pairingPassed
    details = appendDetail(details, ...
        "content-addressed input/solution pairing is incomplete or empty");
end
rule = makeRule(ruleId, name, passed, expected, observed, details);
end

function details = failureCaseSummary(cases, passField)
if isempty(cases)
    details = "no content-addressed cases found";
    return
end
failed = find(~cases.(passField));
if isempty(failed)
    details = "all discovered cases passed";
    return
end
shown = failed(1:min(10, numel(failed)));
items = cases.CaseDirectory(shown) + ": " + ...
    cases.ErrorIdentifier(shown) + " " + cases.ErrorMessage(shown);
details = strjoin(items, " | ");
if numel(failed) > numel(shown)
    details = details + compose(" | plus %d additional failed cases", ...
        numel(failed) - numel(shown));
end
end

function [passed, observed, details, reports] = auditFixedMatrices( ...
        formalRoot, truth)
requiredNames = ["typical_metrics.csv", ...
    "bahloul_sensitivity_long.csv", "daily_metrics.csv", ...
    "monthly_metrics.csv"];
tables = cell(numel(requiredNames), 1);
issues = strings(0, 1);
for fileIndex = 1:numel(requiredNames)
    [path, located, locationDetail] = locateUniqueFile( ...
        formalRoot, requiredNames(fileIndex));
    if ~located
        issues(end + 1, 1) = locationDetail; %#ok<AGROW>
        continue
    end
    try
        tables{fileIndex} = readtable(path, Delimiter=",", TextType="string", ...
            VariableNamingRule="preserve");
    catch exception
        issues(end + 1, 1) = requiredNames(fileIndex) + ...
            " unreadable: " + string(exception.message); %#ok<AGROW>
    end
end
if ~isempty(issues)
    passed = false;
    observed = "required tables unavailable";
    details = strjoin(issues, " | ");
    reports = struct;
    return
end

typical = tables{1};
sensitivity = tables{2};
daily = tables{3};
monthly = tables{4};
[typicalPass, typicalDetail] = auditCanonicalTable(typical, ...
    expectedTypical(truth), stableKeyNames("typical"), ...
    "typical_metrics.csv", true);
[sensitivityPass, sensitivityDetail] = auditCanonicalTable(sensitivity, ...
    expectedSensitivity(truth), stableKeyNames("sensitivity"), ...
    "bahloul_sensitivity_long.csv", true);
[monthlyDailyPass, monthlyDailyDetail] = auditCanonicalTable(daily, ...
    expectedMonthlyDaily(truth), stableKeyNames("daily"), ...
    "daily_metrics.csv", true);
[monthlyPass, monthlyDetail] = auditCanonicalTable(monthly, ...
    expectedMonthlyAggregate(truth), stableKeyNames("monthly"), ...
    "monthly_metrics.csv", false);
[criticalStatusPass, criticalStatusDetail] = ...
    auditCriticalStatuses(typical, sensitivity);
[monthlyStatusPass, monthlyStatusDetail] = ...
    auditMonthlyDailyStatuses(daily);
[aggregationPass, aggregationDetail] = ...
    auditMonthlyAggregation(daily, monthly);
[checkpointPass, checkpointDetail] = auditBatchCheckpoints(sensitivity);
[labelPass, labelDetail] = auditMatrixLabels(typical, sensitivity, ...
    daily, monthly);
passed = typicalPass && sensitivityPass && monthlyDailyPass && ...
    monthlyPass && criticalStatusPass && monthlyStatusPass && ...
    aggregationPass && checkpointPass && labelPass;
observed = compose("typical=%d; sensitivity=%d; monthlyDaily=%d; monthly=%d", ...
    height(typical), height(sensitivity), height(daily), height(monthly));
details = strjoin([typicalDetail, sensitivityDetail, monthlyDailyDetail, ...
    monthlyDetail, criticalStatusDetail, monthlyStatusDetail, ...
    aggregationDetail, checkpointDetail, labelDetail], " | ");
reports = struct("typical", typical, "sensitivity", sensitivity, ...
    "daily", daily, "monthly", monthly);
end

function [passed, details] = auditCanonicalTable(value, expected, keyNames, ...
        label, requireStatus)
variables = string(value.Properties.VariableNames);
missingKeys = keyNames(~ismember(keyNames, variables));
passed = height(value) == height(expected) && isempty(missingKeys);
details = compose("%s rows=%d/%d", label, height(value), height(expected));
if ~isempty(missingKeys)
    details = appendDetail(details, "missing keys: " + ...
        strjoin(missingKeys, ","));
else
    actualKeys = canonicalRowKeys(value, keyNames);
    expectedKeys = canonicalRowKeys(expected, keyNames);
    duplicatePass = numel(unique(actualKeys)) == numel(actualKeys);
    setPass = isequal(sort(actualKeys), sort(expectedKeys));
    passed = passed && duplicatePass && setPass;
    if ~duplicatePass
        details = appendDetail(details, "duplicate frozen keys");
    end
    if ~setPass
        details = appendDetail(details, keySetDifference(actualKeys, ...
            expectedKeys));
    end
end
if requireStatus
    [statusPass, statusDetail] = auditFixedStatuses(value);
    passed = passed && statusPass;
    if ~statusPass
        details = appendDetail(details, statusDetail);
    end
end
end

function [passed, details] = auditFixedStatuses(value)
variables = string(value.Properties.VariableNames);
required = ["Status", "ErrorIdentifier", "ErrorMessage"];
missing = required(~ismember(required, variables));
if ~isempty(missing)
    passed = false;
    details = "status schema missing: " + strjoin(missing, ",");
    return
end
status = strip(string(value.Status));
allowed = ismember(status, ["ok", "quality_rejected", "failed"]);
rejected = status == "quality_rejected";
failed = status == "failed";
hasReason = strlength(strip(string(value.ErrorIdentifier))) > 0 & ...
    strlength(strip(string(value.ErrorMessage))) > 0;
nonOk = status ~= "ok";
passed = all(allowed) && all(hasReason(nonOk));
details = compose("ok=%d; qualityRejected=%d; failed=%d; invalid=%d; nonOkWithoutReason=%d", ...
    nnz(status == "ok"), nnz(rejected), nnz(failed), nnz(~allowed), ...
    nnz(nonOk & ~hasReason));
end

function [passed, details] = auditCriticalStatuses(typical, sensitivity)
typicalStatus = strip(string(typical.Status));
sensitivityStatus = strip(string(sensitivity.Status));
passed = all(typicalStatus == "ok") && all(sensitivityStatus == "ok");
details = compose("critical status ok typical=%d/%d; sensitivity=%d/%d", ...
    nnz(typicalStatus == "ok"), height(typical), ...
    nnz(sensitivityStatus == "ok"), height(sensitivity));
end

function [passed, details] = auditMonthlyDailyStatuses(daily)
requireColumns(daily, ["Day", "Status", "ErrorIdentifier", ...
    "ErrorMessage"], "daily_metrics.csv");
days = unique(dateVector(daily.Day), "sorted");
issues = strings(0, 1);
rejectedDayCount = 0;
failedCellCount = 0;
for dayIndex = 1:numel(days)
    selected = dateVector(daily.Day) == days(dayIndex);
    status = strip(string(daily.Status(selected)));
    if nnz(selected) ~= 5
        issues(end + 1, 1) = "monthly day does not have five strategies: " + ...
            string(days(dayIndex), "yyyy-MM-dd"); %#ok<AGROW>
        continue
    end
    hasQualityRejection = any(status == "quality_rejected");
    wholeDayQualityRejection = all(status == "quality_rejected") && ...
        all(strip(string(daily.ErrorIdentifier(selected))) == ...
        "StoreNet:QualityRejected");
    if hasQualityRejection && ~wholeDayQualityRejection
        issues(end + 1, 1) = ...
            "quality rejection is not an atomic five-strategy day: " + ...
            string(days(dayIndex), "yyyy-MM-dd"); %#ok<AGROW>
    elseif wholeDayQualityRejection
        rejectedDayCount = rejectedDayCount + 1;
    end
    failedCellCount = failedCellCount + nnz(status == "failed");
end
passed = numel(days) == 48 && isempty(issues);
details = compose("monthlyDays=%d/48; rejectedWholeDays=%d; failedCells=%d; %s", ...
    numel(days), rejectedDayCount, failedCellCount, issueSummary(issues));
end

function [passed, details] = auditBatchCheckpoints(sensitivity)
issues = strings(0, 1);
required = ["BatteryCapacityKWh", "BatteryPowerKW", ...
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
    "TotalBatteryThroughputKWh", "EnergyBalanceResidualKW", ...
    "TerminalSocErrorKWh", "SimultaneousChargeDischargeKW", ...
    "MinimumStageExitFlag"];
try
    requireColumns(sensitivity, required, "bahloul_sensitivity_long.csv");
catch exception
    passed = false;
    details = string(exception.message);
    return
end
figureRows = find(string(sensitivity.ExperimentId) == "FIGURE_7");
for rowIndex = reshape(figureRows, 1, [])
    row = sensitivity(rowIndex, :);
    expectedCapacity = 10 .* double(row.CapacityRatio);
    expectedPower = 3.3 .* double(row.PowerRatio);
    passedRow = finiteRowScalars(row, required) && ...
        scalarWithin(double(row.BatteryCapacityKWh), ...
        expectedCapacity, 1e-12) && ...
        scalarWithin(double(row.BatteryPowerKW), expectedPower, 1e-12) && ...
        abs(double(row.EnergyBalanceResidualKW)) <= 1e-7 && ...
        abs(double(row.TerminalSocErrorKWh)) <= 1e-7 && ...
        abs(double(row.SimultaneousChargeDischargeKW)) <= 1e-7 && ...
        double(row.MinimumStageExitFlag) > 0;
    if ~passedRow
        issues(end + 1, 1) = compose( ...
            "Figure 7 row %d has invalid config/persisted checkpoint", ...
            rowIndex); %#ok<AGROW>
    end
end
passed = isempty(issues);
details = issueSummary(issues);
end

function passed = finiteRowScalars(row, columns)
passed = true;
for columnIndex = 1:numel(columns)
    value = row.(columns(columnIndex));
    if ~isnumeric(value) && ~islogical(value)
        passed = false;
        return
    end
    value = double(value);
    if ~isscalar(value) || ~isfinite(value)
        passed = false;
        return
    end
end
end

function [passed, details] = auditMonthlyAggregation(daily, monthly)
requiredDaily = ["YearMonth", "ScenarioId", "Strategy", "Status", ...
    "PaperLoadOnlyBaselineBillEUR", "PaperLoadOnlySavingsEUR", ...
    "PaperLoadOnlySavingsPercent", ...
    "PvSelfNoBatteryBaselineBillEUR", "PvSelfNoBatterySavingsEUR", ...
    "PvSelfNoBatterySavingsPercent", "OptimizedBillEUR", ...
    "PaperLoadOnlyPeakKW", "PvSelfNoBatteryPeakKW", ...
    "OutcomePeakImportKW"];
requiredMonthly = ["YearMonth", "ScenarioId", "Strategy", ...
    "PaperPeriodRelation", "PublicReleaseAvailability", ...
    "CandidateDays", "RequestedDays", "ValidDays", ...
    "FailedOrRejectedDays", "UnavailableCandidateDays", ...
    "MeanDailyPaperLoadOnlyBaselineBillEUR", ...
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
try
    requireColumns(daily, requiredDaily, "daily_metrics.csv");
    requireColumns(monthly, requiredMonthly, "monthly_metrics.csv");
catch exception
    passed = false;
    details = string(exception.message);
    return
end
dailyMonths = dateshift(dateVector(daily.YearMonth), "start", "month");
monthlyMonths = dateshift(dateVector(monthly.YearMonth), "start", "month");
meanPairs = { ...
    "MeanDailyPaperLoadOnlyBaselineBillEUR", "PaperLoadOnlyBaselineBillEUR"; ...
    "MeanDailyPaperLoadOnlySavingsEUR", "PaperLoadOnlySavingsEUR"; ...
    "MeanDailyPaperLoadOnlySavingsPercent", "PaperLoadOnlySavingsPercent"; ...
    "MeanDailyPvSelfNoBatteryBaselineBillEUR", "PvSelfNoBatteryBaselineBillEUR"; ...
    "MeanDailyPvSelfNoBatterySavingsEUR", "PvSelfNoBatterySavingsEUR"; ...
    "MeanDailyPvSelfNoBatterySavingsPercent", "PvSelfNoBatterySavingsPercent"; ...
    "MeanDailyPaperLoadOnlyPeakKW", "PaperLoadOnlyPeakKW"; ...
    "MeanDailyPvSelfNoBatteryPeakKW", "PvSelfNoBatteryPeakKW"; ...
    "MeanDailyOutcomePeakImportKW", "OutcomePeakImportKW"};
sumPairs = { ...
    "SumPaperLoadOnlyBaselineBillEUR", "PaperLoadOnlyBaselineBillEUR"; ...
    "SumPvSelfNoBatteryBaselineBillEUR", "PvSelfNoBatteryBaselineBillEUR"; ...
    "SumOptimizedBillEUR", "OptimizedBillEUR"};
issues = strings(0, 1);
for rowIndex = 1:height(monthly)
    selected = dailyMonths == monthlyMonths(rowIndex) & ...
        string(daily.ScenarioId) == string(monthly.ScenarioId(rowIndex)) & ...
        string(daily.Strategy) == string(monthly.Strategy(rowIndex));
    valid = selected & strip(string(daily.Status)) == "ok";
    requested = nnz(selected);
    validDays = nnz(valid);
    finiteDailyPassed = true;
    for validIndex = reshape(find(valid), 1, [])
        finiteDailyPassed = finiteDailyPassed && finiteRowScalars( ...
            daily(validIndex, :), requiredDaily(5:end));
    end
    countPassed = requested == 4 && ...
        scalarAgreementPassed(monthly.CandidateDays(rowIndex), 4) && ...
        scalarAgreementPassed(monthly.RequestedDays(rowIndex), 4) && ...
        scalarAgreementPassed(monthly.ValidDays(rowIndex), validDays) && ...
        scalarAgreementPassed(monthly.FailedOrRejectedDays(rowIndex), ...
        4 - validDays) && ...
        scalarAgreementPassed(monthly.UnavailableCandidateDays(rowIndex), 0);
    relation = "2020-07--12_extrapolation";
    if month(monthlyMonths(rowIndex)) <= 6
        relation = "2020-01--06_overlap";
    end
    labelPassed = string(monthly.PaperPeriodRelation(rowIndex)) == relation && ...
        string(monthly.PublicReleaseAvailability(rowIndex)) == ...
        "available_from_public_release";
    numericPassed = true;
    for pairIndex = 1:size(meanPairs, 1)
        expected = meanFiniteOrNaN(daily.(meanPairs{pairIndex, 2})(valid));
        numericPassed = numericPassed && scalarAgreementPassed( ...
            monthly.(meanPairs{pairIndex, 1})(rowIndex), expected);
    end
    for pairIndex = 1:size(sumPairs, 1)
        expected = sumFiniteOrNaN(daily.(sumPairs{pairIndex, 2})(valid));
        numericPassed = numericPassed && scalarAgreementPassed( ...
            monthly.(sumPairs{pairIndex, 1})(rowIndex), expected);
    end
    paperSum = sumFiniteOrNaN(daily.PaperLoadOnlyBaselineBillEUR(valid));
    pvSelfSum = sumFiniteOrNaN(daily.PvSelfNoBatteryBaselineBillEUR(valid));
    optimizedSum = sumFiniteOrNaN(daily.OptimizedBillEUR(valid));
    paperRatio = safePercentValue(paperSum - optimizedSum, paperSum);
    pvSelfRatio = safePercentValue(pvSelfSum - optimizedSum, pvSelfSum);
    numericPassed = numericPassed && scalarAgreementPassed( ...
        monthly.RatioOfSummedCostsPaperLoadOnlySavingsPercent(rowIndex), ...
        paperRatio) && scalarAgreementPassed( ...
        monthly.RatioOfSummedCostsPaperLoadOnlySavingsPercentDenominatorIsZero(rowIndex), ...
        denominatorFlagValue(paperSum)) && scalarAgreementPassed( ...
        monthly.RatioOfSummedCostsPvSelfNoBatterySavingsPercent(rowIndex), ...
        pvSelfRatio);
    if ~(countPassed && labelPassed && finiteDailyPassed && numericPassed)
        issues(end + 1, 1) = compose( ...
            "monthly row %d disagrees with daily regrouping", rowIndex); %#ok<AGROW>
    end
end
passed = isempty(issues);
details = issueSummary(issues);
end

function passed = scalarAgreementPassed(actual, expected)
[passed, ~] = scalarAgreement(double(actual), double(expected));
end

function value = meanFiniteOrNaN(values)
values = double(values);
values = values(isfinite(values));
if isempty(values)
    value = NaN;
else
    value = mean(values);
end
end

function value = sumFiniteOrNaN(values)
values = double(values);
values = values(isfinite(values));
if isempty(values)
    value = NaN;
else
    value = sum(values);
end
end

function value = safePercentValue(numerator, denominator)
if ~isfinite(numerator) || ~isfinite(denominator) || ...
        abs(denominator) <= eps(max(1, abs(denominator)))
    value = NaN;
else
    value = 100 .* numerator ./ denominator;
end
end

function value = denominatorFlagValue(denominator)
if ~isfinite(denominator)
    value = NaN;
else
    value = double(abs(denominator) <= eps(max(1, abs(denominator))));
end
end

function names = stableKeyNames(kind)
common = ["ExperimentId", "QualityMode", "Strategy", "CohortId", ...
    "PvBoundaryId", "TransferLossFraction", "CapacityRatio", ...
    "PowerRatio", "PairId", "ScenarioId"];
switch kind
    case "typical"
        names = ["Day", common];
    case "daily"
        names = ["Day", common];
    case "monthly"
        names = ["YearMonth", "Strategy", "CohortId", "PvBoundaryId", ...
            "TransferLossFraction", "PairId", "ScenarioId"];
    case "sensitivity"
        names = ["Day", common, "CaseId", "BudgetId", ...
            "SensitivityRole"];
    otherwise
        error("StoreNet:UnknownAcceptanceMatrix", ...
            "Unknown acceptance matrix '%s'.", kind);
end
end

function expected = expectedTypical(truth)
expected = coreStableRows("B2022_TYPICAL_V1", truth.TypicalDay, ...
    truth.QualityMode);
directional = ["DC_XI007_H19", "AC_XI007_H20", "DC_XI000_H20"];
selected = expected.ScenarioId == "DC_XI007_H20" | ...
    (expected.Strategy == "VPP_BM" & ...
    ismember(expected.ScenarioId, directional)) | ...
    expected.Strategy == "SB_SC";
expected = expected(selected, :);
end

function expected = expectedMonthlyDaily(truth)
base = coreStableRows("B2022_MONTHLY_V1", truth.TypicalDay, ...
    truth.QualityMode);
base = base(base.ScenarioId == "DC_XI007_H20" & ...
    base.Strategy ~= "SB_SC", :);
dates = frozenMonthlyDays();
[dateIndex, rowIndex] = ndgrid(1:numel(dates), 1:height(base));
expected = base(rowIndex(:), :);
expected.Day = dates(dateIndex(:));
end

function expected = expectedMonthlyAggregate(truth)
base = coreStableRows("B2022_MONTHLY_V1", truth.TypicalDay, ...
    truth.QualityMode);
base = base(base.ScenarioId == "DC_XI007_H20" & ...
    base.Strategy ~= "SB_SC", :);
months = datetime(2020, (1:12).', 1);
[monthIndex, rowIndex] = ndgrid(1:numel(months), 1:height(base));
expected = base(rowIndex(:), :);
expected.YearMonth = months(monthIndex(:));
expected.Day = [];
expected = movevars(expected, "YearMonth", "Before", 1);
end

function expected = coreStableRows(experimentId, calendarDay, qualityMode)
scenarios = canonicalCoreScenarios();
strategies = ["SH_BM"; "VPP_BM"; "PS"; "PSDT"; "LL"];
[scenarioIndex, strategyIndex] = ndgrid(1:height(scenarios), ...
    1:numel(strategies));
scenarioIndex = scenarioIndex(:);
strategyIndex = strategyIndex(:);
n = numel(scenarioIndex);
expected = table(repmat(calendarDay, n, 1), ...
    repmat(string(experimentId), n, 1), ...
    repmat(string(qualityMode), n, 1), strategies(strategyIndex), ...
    scenarios.CohortId(scenarioIndex), ...
    scenarios.PvBoundaryId(scenarioIndex), ...
    scenarios.TransferLossFraction(scenarioIndex), ones(n, 1), ...
    ones(n, 1), scenarios.PairId(scenarioIndex), ...
    scenarios.ScenarioId(scenarioIndex), ...
    VariableNames=["Day", "ExperimentId", "QualityMode", "Strategy", ...
    "CohortId", "PvBoundaryId", "TransferLossFraction", ...
    "CapacityRatio", "PowerRatio", "PairId", "ScenarioId"]);
observed = table(repmat(calendarDay, 2, 1), ...
    repmat(string(experimentId), 2, 1), ...
    repmat(string(qualityMode), 2, 1), repmat("SB_SC", 2, 1), ...
    ["H20_PV10"; "H19_EXCL_H4_PV9"], ...
    repmat("OBSERVED_RELEASE_FIELDS", 2, 1), nan(2, 1), ...
    nan(2, 1), nan(2, 1), repmat("OBSERVED_RELEASE_PAIR", 2, 1), ...
    ["OBSERVED_RELEASE_H20_PV10"; ...
    "OBSERVED_RELEASE_H19_EXCL_H4_PV9"], ...
    VariableNames=expected.Properties.VariableNames);
expected = [expected; observed];
end

function scenarios = canonicalCoreScenarios()
scenarios = table( ...
    ["DC_XI007_H20"; "DC_XI007_H19"; "AC_XI007_H20"; ...
    "AC_XI007_H19"; "DC_XI000_H20"; "DC_XI000_H19"], ...
    ["DC_XI007"; "DC_XI007"; "AC_XI007"; "AC_XI007"; ...
    "DC_XI000"; "DC_XI000"], ...
    ["DC_SOURCE"; "DC_SOURCE"; "AC_METER_RECONSTRUCTED_DC"; ...
    "AC_METER_RECONSTRUCTED_DC"; "DC_SOURCE"; "DC_SOURCE"], ...
    [0.07; 0.07; 0.07; 0.07; 0; 0], ...
    ["H20_PV10"; "H19_EXCL_H4_PV9"; "H20_PV10"; ...
    "H19_EXCL_H4_PV9"; "H20_PV10"; "H19_EXCL_H4_PV9"], ...
    ["PRIMARY"; "H4_PAIR"; "PV_BOUNDARY"; ...
    "PV_BOUNDARY_H4_PAIR"; "XI_ZERO"; "XI_ZERO_H4_PAIR"], ...
    VariableNames=["ScenarioId", "PairId", "PvBoundaryId", ...
    "TransferLossFraction", "CohortId", "SensitivityRole"]);
end

function expected = expectedSensitivity(truth)
scenarios = canonicalCoreScenarios();
ratios = (2:10).' ./ 10;
[capacityIndex, powerIndex] = ndgrid( ...
    1:numel(ratios), 1:numel(ratios));
capacityRatio = ratios(capacityIndex(:));
powerRatio = ratios(powerIndex(:));
scenarioIndex = ones(numel(capacityRatio), 1);
nFigure = numel(scenarioIndex);
caseId = compose("figure7_c%03d_p%03d_%s_VPP_BM", ...
    round(100 .* capacityRatio), round(100 .* powerRatio), ...
    scenarios.ScenarioId(scenarioIndex));
figureRows = table(repmat(truth.TypicalDay, nFigure, 1), ...
    repmat("FIGURE_7", nFigure, 1), ...
    repmat(truth.QualityMode, nFigure, 1), ...
    repmat("VPP_BM", nFigure, 1), scenarios.CohortId(scenarioIndex), ...
    scenarios.PvBoundaryId(scenarioIndex), ...
    scenarios.TransferLossFraction(scenarioIndex), capacityRatio, ...
    powerRatio, scenarios.PairId(scenarioIndex), ...
    scenarios.ScenarioId(scenarioIndex), caseId, repmat("GRID", nFigure, 1), ...
    scenarios.SensitivityRole(scenarioIndex), ...
    VariableNames=["Day", "ExperimentId", "QualityMode", "Strategy", ...
    "CohortId", "PvBoundaryId", "TransferLossFraction", ...
    "CapacityRatio", "PowerRatio", "PairId", "ScenarioId", ...
    "CaseId", "BudgetId", "SensitivityRole"]);

budgetId = ["NOMINAL"; "POWER_20"; "CAPACITY_20"];
budgetCapacity = [1; 1; 0.2];
budgetPower = [1; 0.2; 1];
strategies = ["SH_BM"; "VPP_BM"; "PS"; "PSDT"; "LL"];
[budgetIndex, strategyIndex] = ndgrid(1:3, 1:5);
budgetIndex = budgetIndex(:);
strategyIndex = strategyIndex(:);
scenarioIndex = ones(numel(budgetIndex), 1);
selectedBudget = budgetId(budgetIndex);
selectedStrategy = strategies(strategyIndex);
capacityRatio = budgetCapacity(budgetIndex);
powerRatio = budgetPower(budgetIndex);
nTable = numel(scenarioIndex);
caseId = compose("tablei_%s_%s_%s", lower(selectedBudget), ...
    scenarios.ScenarioId(scenarioIndex), selectedStrategy);
tableRows = table(repmat(truth.TypicalDay, nTable, 1), ...
    repmat("TABLE_I", nTable, 1), ...
    repmat(truth.QualityMode, nTable, 1), selectedStrategy, ...
    scenarios.CohortId(scenarioIndex), ...
    scenarios.PvBoundaryId(scenarioIndex), ...
    scenarios.TransferLossFraction(scenarioIndex), capacityRatio, ...
    powerRatio, scenarios.PairId(scenarioIndex), ...
    scenarios.ScenarioId(scenarioIndex), caseId, selectedBudget, ...
    scenarios.SensitivityRole(scenarioIndex), ...
    VariableNames=figureRows.Properties.VariableNames);
expected = [figureRows; tableRows];
end

function dates = frozenMonthlyDays()
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

function keys = canonicalRowKeys(value, names)
keys = repmat("", height(value), 1);
for fieldIndex = 1:numel(names)
    field = names(fieldIndex);
    keys = keys + "|" + field + "=" + canonicalColumn(value.(field));
end
end

function values = canonicalColumn(values)
if isdatetime(values)
    values = string(values(:), "yyyy-MM-dd");
elseif isnumeric(values)
    source = double(values(:));
    values = compose("%.17g", source);
    values(isnan(source)) = "NA";
elseif islogical(values)
    values = string(double(values(:)));
else
    values = strip(string(values(:)));
    values(ismissing(values)) = "<missing>";
end
end

function details = keySetDifference(actual, expected)
missing = setdiff(expected, actual);
extra = setdiff(actual, expected);
details = compose("canonical key mismatch; missing=%d; extra=%d", ...
    numel(missing), numel(extra));
if ~isempty(missing)
    details = appendDetail(details, "firstMissing=" + missing(1));
end
if ~isempty(extra)
    details = appendDetail(details, "firstExtra=" + extra(1));
end
end

function [passed, details] = auditMatrixLabels(typical, sensitivity, ...
        daily, monthly)
issues = strings(0, 1);
issues = [issues; requireLabelColumn(typical, "ResultKind", ...
    ["MODEL_STRUCTURAL_PROXY", "OBSERVED_RELEASE_PROXY"], ...
    "typical")];
issues = [issues; requireLabelColumn(daily, "RecordType", ...
    "optimized", "monthly daily")];
issues = [issues; requireLabelColumn(sensitivity, "SensitivityRole", ...
    "PRIMARY", "sensitivity")];
if height(monthly) ~= 60 || ...
        any(year(dateVector(monthly.YearMonth)) ~= 2020)
    issues(end + 1, 1) = ...
        "monthly_metrics.csv must contain only 12 public-2020 months x 5 strategies";
end
passed = isempty(issues);
if passed
    details = "matrix labels and public-2020 monthly scope are canonical";
else
    details = strjoin(issues, "; ");
end
end

function issues = requireLabelColumn(value, name, allowed, label)
issues = strings(0, 1);
if ~ismember(name, string(value.Properties.VariableNames))
    issues = label + " missing label column " + name;
    return
end
actual = unique(strip(string(value.(name))));
if ~all(ismember(actual, allowed)) || ~all(ismember(allowed, actual))
    issues = label + " has invalid/incomplete " + name + " labels";
end
end

function values = dateVector(values)
if isdatetime(values)
    values = values(:);
    return
end
try
    values = datetime(string(values(:)));
catch
    error("StoreNet:InvalidAcceptanceDate", ...
        "A required date column cannot be parsed.");
end
if any(isnat(values))
    error("StoreNet:InvalidAcceptanceDate", ...
        "A required date column contains NaT.");
end
end

function [coveragePassed, metricPassed, observed, details] = ...
        auditReportedArtifacts(formalRoot, reports, caseTable, truth)
descriptors = { ...
    struct("Name", "typical", "Kind", "typical", ...
    "Table", reports.typical), ...
    struct("Name", "sensitivity", "Kind", "sensitivity", ...
    "Table", reports.sensitivity)};
reportedPairs = strings(0, 1);
coverageIssues = strings(0, 1);
metricIssues = strings(0, 1);
successfulCount = 0;
for descriptorIndex = 1:numel(descriptors)
    descriptor = descriptors{descriptorIndex};
    value = descriptor.Table;
    [modelSelected, observedSelected] = fullArtifactMasks( ...
        value, descriptor.Kind);
    rowIndices = find(modelSelected);
    for selectedIndex = 1:numel(rowIndices)
        rowIndex = rowIndices(selectedIndex);
        successfulCount = successfulCount + 1;
        try
            [pairKey, recomputed, evidence, identityPassed, ...
                identityDetail] = auditReportedArtifactReference( ...
                formalRoot, value(rowIndex, :), truth);
            reportedPairs(end + 1, 1) = pairKey; %#ok<AGROW>
            if ~identityPassed
                coverageIssues(end + 1, 1) = descriptor.Name + ...
                    compose(" row %d identity: ", rowIndex) + ...
                    identityDetail; %#ok<AGROW>
            end
            [rowMetricPass, rowMetricDetail] = ...
                auditCsvMetricAgreement(value(rowIndex, :), recomputed, ...
                evidence.solution, descriptor.Kind);
            if ~rowMetricPass
                metricIssues(end + 1, 1) = descriptor.Name + ...
                    compose(" row %d metrics: ", rowIndex) + ...
                    rowMetricDetail; %#ok<AGROW>
            end
        catch exception
            coverageIssues(end + 1, 1) = descriptor.Name + ...
                compose(" row %d artifact: ", rowIndex) + ...
                string(exception.identifier) + ": " + ...
                string(exception.message); %#ok<AGROW>
        end
    end
    rowIndices = find(observedSelected);
    for selectedIndex = 1:numel(rowIndices)
        rowIndex = rowIndices(selectedIndex);
        successfulCount = successfulCount + 1;
        try
            [pairKey, recomputed, identityPassed, identityDetail] = ...
                auditReportedObservedArtifactReference( ...
                formalRoot, value(rowIndex, :), truth);
            reportedPairs(end + 1, 1) = pairKey; %#ok<AGROW>
            if ~identityPassed
                coverageIssues(end + 1, 1) = descriptor.Name + ...
                    compose(" observed row %d identity: ", rowIndex) + ...
                    identityDetail; %#ok<AGROW>
            end
            [rowMetricPass, rowMetricDetail] = ...
                auditObservedCsvMetricAgreement(value(rowIndex, :), ...
                recomputed, descriptor.Kind);
            if ~rowMetricPass
                metricIssues(end + 1, 1) = descriptor.Name + ...
                    compose(" observed row %d: ", rowIndex) + ...
                    rowMetricDetail; %#ok<AGROW>
            end
        catch exception
            coverageIssues(end + 1, 1) = descriptor.Name + ...
                compose(" observed row %d artifact: ", rowIndex) + ...
                string(exception.identifier) + ": " + ...
                string(exception.message); %#ok<AGROW>
        end
    end
end

duplicateCount = numel(reportedPairs) - numel(unique(reportedPairs));
if duplicateCount > 0
    coverageIssues(end + 1, 1) = compose( ...
        "successful model rows reuse %d artifact pair(s)", duplicateCount);
end
criticalCases = caseTable.CriticalArtifact;
discoveredPairs = caseTable.InputsPath(criticalCases) + "|" + ...
    caseTable.SolutionPath(criticalCases);
setMatch = isequal(sort(unique(reportedPairs)), sort(unique(discoveredPairs)));
if ~setMatch
    coverageIssues(end + 1, 1) = compose( ...
        "reported/discovered artifact set mismatch (reported=%d, discovered=%d)", ...
        numel(unique(reportedPairs)), numel(unique(discoveredPairs)));
end
coveragePassed = successfulCount > 0 && isempty(coverageIssues) && ...
    duplicateCount == 0 && setMatch;
metricPassed = successfulCount > 0 && isempty(metricIssues);
observed = compose("fullArtifactRows=%d; reportedPairs=%d; discoveredPairs=%d", ...
    successfulCount, numel(reportedPairs), numel(discoveredPairs));
details = "coverage=" + issueSummary(coverageIssues) + ...
    "; csvMetrics=" + issueSummary(metricIssues);
end

function [modelSelected, observedSelected] = fullArtifactMasks(value, kind)
requireColumns(value, "Status", kind + " report");
statusOk = strip(string(value.Status)) == "ok";
observedSelected = false(height(value), 1);
switch kind
    case "typical"
        requireColumns(value, "ResultKind", "typical report");
        modelSelected = statusOk & ...
            string(value.ResultKind) == "MODEL_STRUCTURAL_PROXY";
        observedSelected = statusOk & ...
            string(value.ResultKind) == "OBSERVED_RELEASE_PROXY";
    case "sensitivity"
        requireColumns(value, "ExperimentId", "sensitivity report");
        modelSelected = statusOk & string(value.ExperimentId) == "TABLE_I";
    otherwise
        error("StoreNet:UnknownAcceptanceArtifactReport", ...
            "Unknown full-artifact report kind '%s'.", kind);
end
end

function [pairKey, recomputed, evidence, identityPassed, identityDetail] = ...
        auditReportedArtifactReference(formalRoot, row, truth)
[inputsPath, solutionPath, inputsDirectory, pairKey] = ...
    validateReportedArtifactPair(formalRoot, row);
[recomputed, evidence] = reevaluate_bahloul_artifact(inputsDirectory);
if string(evidence.inputsPath) ~= inputsPath || ...
        string(evidence.solutionPath) ~= solutionPath
    error("StoreNet:ReportedArtifactPairMismatch", ...
        "Offline evaluator resolved a different artifact pair.");
end
[provenancePassed, provenanceDetail] = ...
    auditInputIdentity(evidence.input, truth);
[casePassed, caseDetail] = auditCaseIdentity(evidence.input, row);
identityPassed = provenancePassed && casePassed;
identityDetail = provenanceDetail + "; " + caseDetail;
end

function [pairKey, recomputed, identityPassed, identityDetail] = ...
        auditReportedObservedArtifactReference( ...
        formalRoot, row, truth)
[inputsPath, solutionPath, inputsDirectory, pairKey] = ...
    validateReportedArtifactPair(formalRoot, row);
[recomputed, ~, evidence] = ...
    reevaluate_bahloul_observed_artifact(inputsDirectory);
if string(evidence.inputsPath) ~= inputsPath || ...
        string(evidence.solutionPath) ~= solutionPath
    error("StoreNet:ReportedArtifactPairMismatch", ...
        "Observed offline evaluator resolved a different artifact pair.");
end
[provenancePassed, provenanceDetail] = ...
    auditInputIdentity(evidence.input, truth);
[casePassed, caseDetail] = auditCaseIdentity(evidence.input, row);
identityPassed = provenancePassed && casePassed;
identityDetail = provenanceDetail + "; " + caseDetail;
end

function [inputsPath, solutionPath, inputsDirectory, pairKey] = ...
        validateReportedArtifactPair(formalRoot, row)
required = ["InputsPath", "InputsSha256", "SolutionPath", ...
    "SolutionSha256"];
requireColumns(row, required, "successful model row");
inputsHash = lower(strip(string(row.InputsSha256)));
solutionHash = lower(strip(string(row.SolutionSha256)));
if ~isSha256(inputsHash) || ~isSha256(solutionHash)
    error("StoreNet:InvalidReportedArtifactHash", ...
        "Reported artifact hashes must be 64 lowercase hexadecimal characters.");
end
inputsPath = resolveFormalFile(formalRoot, string(row.InputsPath));
solutionPath = resolveFormalFile(formalRoot, string(row.SolutionPath));
if sha256File(inputsPath) ~= inputsHash || ...
        sha256File(solutionPath) ~= solutionHash
    error("StoreNet:ReportedArtifactHashMismatch", ...
        "Reported input/solution hashes disagree with file bytes.");
end
[~, inputsName] = fileparts(inputsPath);
[~, solutionName] = fileparts(solutionPath);
if inputsName ~= "inputs_" + inputsHash || ...
        solutionName ~= "solution_" + solutionHash
    error("StoreNet:ReportedArtifactNameMismatch", ...
        "Reported content hashes do not match artifact filenames.");
end
inputsDirectory = string(fileparts(inputsPath));
solutionDirectory = string(fileparts(solutionPath));
if inputsDirectory ~= solutionDirectory
    error("StoreNet:ReportedArtifactPairMismatch", ...
        "Reported input and solution files are not in the same case directory.");
end
pairKey = relativePath(formalRoot, inputsPath) + "|" + ...
    relativePath(formalRoot, solutionPath);
end

function path = resolveFormalFile(formalRoot, reported)
reported = strip(reported);
if ~isscalar(reported) || ismissing(reported) || strlength(reported) == 0
    error("StoreNet:MissingReportedArtifactPath", ...
        "A successful model row has an empty artifact path.");
end
isAbsolute = startsWith(reported, filesep) || ...
    ~isempty(regexp(char(reported), '^[A-Za-z]:[\\/]', 'once'));
if isAbsolute
    candidate = reported;
else
    candidate = string(fullfile(formalRoot, replace(reported, "/", filesep)));
end
if ~isfile(candidate)
    error("StoreNet:MissingReportedArtifact", ...
        "Reported artifact does not exist: %s", candidate);
end
directory = canonicalFolder(string(fileparts(candidate)));
path = string(fullfile(directory, string(extractAfter(candidate, ...
    strlength(string(fileparts(candidate))) + 1))));
rootPrefix = formalRoot + string(filesep);
if ~startsWith(path, rootPrefix)
    error("StoreNet:ArtifactOutsideFormalRoot", ...
        "Reported artifact resolves outside the formal root: %s", path);
end
end

function [passed, details] = auditCaseIdentity(inputEvidence, row)
if ~isstruct(inputEvidence) || ~isfield(inputEvidence, "identity")
    passed = false;
    details = "case identity missing";
    return
end
identity = inputEvidence.identity;
pairs = { ...
    "ExperimentId", "experimentId", "text"; ...
    "Day", "dateOrPeriod", "date"; ...
    "QualityMode", "qualityMode", "text"; ...
    "Strategy", "strategy", "text"; ...
    "CohortId", "cohortId", "text"; ...
    "CapacityRatio", "capacityRatio", "numeric"; ...
    "PowerRatio", "powerRatio", "numeric"; ...
    "PvBoundaryId", "pvBoundaryId", "text"; ...
    "TransferLossFraction", "xi", "numeric"; ...
    "PairId", "pairId", "text"; ...
    "ScenarioId", "scenarioId", "text"; ...
    "CaseId", "caseId", "text"};
issues = strings(0, 1);
variables = string(row.Properties.VariableNames);
for pairIndex = 1:size(pairs, 1)
    column = string(pairs{pairIndex, 1});
    field = string(pairs{pairIndex, 2});
    kind = string(pairs{pairIndex, 3});
    if ~ismember(column, variables)
        continue
    end
    expected = row.(column);
    if kind == "text" && strlength(strip(string(expected))) == 0
        continue
    end
    [actual, available] = identityValue(identity, field);
    if ~available || ~identityScalarEqual(actual, expected, kind)
        issues(end + 1, 1) = column + "!=identity." + field; %#ok<AGROW>
    end
end
passed = isempty(issues);
details = issueSummary(issues);
end

function [value, available] = identityValue(identity, field)
value = [];
available = false;
if ~isstruct(identity) || ~isfield(identity, field)
    return
end
record = identity.(field);
if ~isstruct(record) || ~isscalar(record) || ...
        ~isfield(record, "available") || ~logical(record.available) || ...
        ~isfield(record, "value")
    return
end
value = record.value;
available = true;
end

function passed = identityScalarEqual(actual, expected, kind)
switch kind
    case "date"
        try
            passed = isequal(dateVector(actual), dateVector(expected));
        catch
            passed = false;
        end
    case "numeric"
        actual = double(actual);
        expected = double(expected);
        passed = isscalar(actual) && isscalar(expected) && ...
            ((isnan(actual) && isnan(expected)) || ...
            (isfinite(actual) && isfinite(expected) && ...
            abs(actual - expected) <= 1e-12 * ...
            max([1, abs(actual), abs(expected)])));
    otherwise
        actual = strip(string(actual));
        expected = strip(string(expected));
        passed = isscalar(actual) && isscalar(expected) && actual == expected;
end
end

function [passed, details] = auditCsvMetricAgreement(row, metrics, solution, kind)
[columns, paths] = metricMapping(kind);
variables = string(row.Properties.VariableNames);
missing = columns(~ismember(columns, variables));
if ~isempty(missing)
    passed = false;
    details = "missing report scalar(s): " + strjoin(missing, ",");
    return
end
maximumDifference = 0;
issues = strings(0, 1);
for metricIndex = 1:numel(columns)
    actual = reportSourceValue(metrics, solution, paths(metricIndex));
    reported = double(row.(columns(metricIndex)));
    if ~isscalar(reported)
        issues(end + 1, 1) = columns(metricIndex) + " is not scalar"; %#ok<AGROW>
        continue
    end
    [equal, scaledDifference] = scalarAgreement(actual, reported);
    maximumDifference = max(maximumDifference, scaledDifference);
    if ~equal
        issues(end + 1, 1) = columns(metricIndex) + ...
            compose(" diff=%.17g", scaledDifference); %#ok<AGROW>
    end
end
passed = isempty(issues);
details = compose("metrics=%d; maximumScaledDifference=%.17g; %s", ...
    numel(columns), maximumDifference, issueSummary(issues));
end

function [passed, details] = auditObservedCsvMetricAgreement(row, metrics, kind)
if kind ~= "typical"
    error("StoreNet:UnknownObservedAcceptanceMetricSchema", ...
        "Unknown observed report schema '%s'.", kind);
end
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
paths = ["paperLoadOnlyBaselineBillEUR", "paperLoadOnlySavingsEUR", ...
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
requireColumns(row, columns, "successful observed row");
issues = strings(0, 1);
maximumDifference = 0;
for metricIndex = 1:numel(columns)
    expected = nestedOrNaN(metrics, paths(metricIndex));
    reported = double(row.(columns(metricIndex)));
    [equal, difference] = scalarAgreement(expected, reported);
    maximumDifference = max(maximumDifference, difference);
    if ~equal
        issues(end + 1, 1) = columns(metricIndex) + ...
            compose(" diff=%.17g", difference); %#ok<AGROW>
    end
end
passed = isempty(issues);
details = compose("metrics=%d; maximumScaledDifference=%.17g; %s", ...
    numel(columns), maximumDifference, issueSummary(issues));
end

function [columns, paths] = metricMapping(kind)
baseColumns = ["PaperLoadOnlyBaselineBillEUR", ...
    "PaperSavingsPercentDenominatorIsZero", ...
    "PaperLoadOnlySavingsEUR", "PaperLoadOnlySavingsPercent", ...
    "PvSelfNoBatteryBaselineBillEUR", ...
    "EngineeringSavingsPercentDenominatorIsZero"];
basePaths = ["PaperLoadOnlyBaseline.billEUR", ...
    "PaperLoadOnlyBaseline.savingsPercentDenominatorIsZero", ...
    "PaperLoadOnlyBaseline.savingsEUR", ...
    "PaperLoadOnlyBaseline.savingsPercent", ...
    "PvSelfNoBatteryBaseline.billEUR", ...
    "PvSelfNoBatteryBaseline.savingsPercentDenominatorIsZero"];
residualColumns = ["TotalGridImportKWh", "TotalBatteryThroughputKWh", ...
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
residualPaths = ["totalGridImportKWh", "totalBatteryThroughputKWh", ...
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
switch kind
    case "typical"
        columns = [baseColumns, "OriginalLoadPeakKW", ...
            "OriginalLoadDaytimePeakKW", "EngineeringSavingsEUR", ...
            "EngineeringSavingsPercent", "PvSelfNoBatteryPeakKW"];
        paths = [basePaths, "PaperLoadOnlyBaseline.peakImportKW", ...
            "PaperLoadOnlyBaseline.daytimePeakImportKW", ...
            "PvSelfNoBatteryBaseline.savingsEUR", ...
            "PvSelfNoBatteryBaseline.savingsPercent", ...
            "PvSelfNoBatteryBaseline.peakImportKW"];
        columns = [columns, "OptimizedBillEUR", ...
            "OptimizedPeakImportKW", "OptimizedDaytimePeakImportKW", ...
            "OptimizedImportSpreadKW", residualColumns, "StageCount", ...
            "MinimumStageExitFlag", "MaximumStageRelativeGap"];
        paths = [paths, "optimizedBillEUR", "peakImportKW", ...
            "daytimePeakImportKW", "importSpreadKW", residualPaths, ...
            "@StageCount", "@MinimumExitFlag", "@MaximumRelativeGap"];
        columns(end-1:end) = ["MinimumExitFlag", ...
            "MaximumRelativeMipGap"];
    case "sensitivity"
        columns = [baseColumns, ...
            "PaperLoadOnlyBaselinePeakImportKW", ...
            "PaperLoadOnlyBaselineDaytimePeakImportKW", ...
            "PvSelfNoBatterySavingsEUR", ...
            "PvSelfNoBatterySavingsPercent", ...
            "PvSelfNoBatteryBaselinePeakImportKW", ...
            "PvSelfNoBatteryBaselineDaytimePeakImportKW", ...
            "OptimizedBillEUR", "PeakImportKW", "DaytimePeakImportKW", ...
            "ImportSpreadKW", residualColumns, "StageCount", ...
            "MinimumStageExitFlag", "MaximumStageRelativeGap"];
        paths = [basePaths, "PaperLoadOnlyBaseline.peakImportKW", ...
            "PaperLoadOnlyBaseline.daytimePeakImportKW", ...
            "PvSelfNoBatteryBaseline.savingsEUR", ...
            "PvSelfNoBatteryBaseline.savingsPercent", ...
            "PvSelfNoBatteryBaseline.peakImportKW", ...
            "PvSelfNoBatteryBaseline.daytimePeakImportKW", ...
            "optimizedBillEUR", "peakImportKW", "daytimePeakImportKW", ...
            "importSpreadKW", residualPaths, "@StageCount", ...
            "@MinimumExitFlag", "@MaximumRelativeGap"];
    otherwise
        error("StoreNet:UnknownAcceptanceMetricSchema", ...
            "Unknown metric schema '%s'.", kind);
end
end

function value = reportSourceValue(metrics, solution, path)
switch path
    case "@StageCount"
        value = numel(solution.objectiveStages);
    case "@MinimumExitFlag"
        value = min(double([solution.objectiveStages.exitFlag]));
    case "@MaximumRelativeGap"
        value = max(double([solution.objectiveStages.relativeGap]));
    otherwise
        value = nestedOrNaN(metrics, split(path, "."));
end
end

function [passed, scaledDifference] = scalarAgreement(actual, reported)
if isnan(actual) && isnan(reported)
    passed = true;
    scaledDifference = 0;
elseif ~isfinite(actual) || ~isfinite(reported)
    passed = false;
    scaledDifference = Inf;
else
    scale = max([1, abs(actual), abs(reported)]);
    scaledDifference = abs(actual - reported) ./ scale;
    passed = scaledDifference <= 1e-9;
end
end

function requireColumns(value, required, label)
required = string(required);
variables = string(value.Properties.VariableNames);
missing = required(~ismember(required, variables));
if ~isempty(missing)
    error("StoreNet:MissingAcceptanceColumn", ...
        "%s is missing column(s): %s", label, strjoin(missing, ", "));
end
end

function summary = issueSummary(issues)
if isempty(issues)
    summary = "none";
    return
end
shown = issues(1:min(5, numel(issues)));
summary = strjoin(shown, " | ");
if numel(issues) > numel(shown)
    summary = summary + compose(" | plus %d additional issue(s)", ...
        numel(issues) - numel(shown));
end
end

function [passed, observed, details] = auditPaperOutputs(formalRoot)
requiredNames = ["figure5_proxy.png", "figure5_profiles.csv", ...
    "figure5_target_comparison.csv", "figure6_proxy.png", ...
    "monthly_mean_profiles.csv", ...
    "figure7_primary_h4_surface.png", ...
    "bahloul_sensitivity_long.csv", "table_i_target_vs_local.csv"];
issues = strings(0, 1);
paths = struct;
for fileIndex = 1:numel(requiredNames)
    [path, located, locationDetail] = locateUniqueFile( ...
        formalRoot, requiredNames(fileIndex));
    if ~located
        issues(end + 1, 1) = locationDetail; %#ok<AGROW>
    elseif fileSize(path) <= 0
        issues(end + 1, 1) = requiredNames(fileIndex) + ...
            " is empty"; %#ok<AGROW>
    else
        paths.(matlab.lang.makeValidName(requiredNames(fileIndex))) = path;
    end
end
if isempty(issues)
    pngNames = ["figure5_proxy.png", "figure6_proxy.png", ...
        "figure7_primary_h4_surface.png"];
    for pngIndex = 1:numel(pngNames)
        path = paths.(matlab.lang.makeValidName(pngNames(pngIndex)));
        try
            info = imfinfo(path);
            valid = ~isempty(info) && all([info.Width] > 0) && ...
                all([info.Height] > 0) && ...
                all(strcmpi(string({info.Format}), "png"));
            if ~valid
                issues(end + 1, 1) = pngNames(pngIndex) + ...
                    " is not a valid nonzero PNG"; %#ok<AGROW>
            end
        catch exception
            issues(end + 1, 1) = pngNames(pngIndex) + ...
                " PNG decode failed: " + string(exception.message); %#ok<AGROW>
        end
    end
    issues = [issues; auditFigure5Outputs(paths)];
    issues = [issues; auditMonthlyOutput(paths)];
    issues = [issues; auditTableIOutput(paths)];
end
passed = isempty(issues);
observed = compose("required=%d; issues=%d", ...
    numel(requiredNames), numel(issues));
details = issueSummary(issues);
end

function issues = auditFigure5Outputs(paths)
issues = strings(0, 1);
try
    profiles = readtable(paths.figure5_profiles_csv, Delimiter=",", ...
        TextType="string", VariableNamingRule="preserve");
    required = ["TimeEnd", "IntervalStart", "ScenarioId", "CohortId", ...
        "PvBoundaryId", "TransferLossFraction", "Strategy", ...
        "ProfileKind", "LoadKW", "PvKW", "GridKW", "BatteryKW", ...
        "FeedInKW"];
    requireColumns(profiles, required, "figure5_profiles.csv");
    kinds = unique(string(profiles.ProfileKind));
    strategies = unique(string(profiles.Strategy));
    labelPass = all(ismember(["STRUCTURAL_PROXY", ...
        "OBSERVED_RELEASE_PROXY"], kinds)) && ...
        all(ismember(["SH_BM", "VPP_BM", "PS", "PSDT", "LL", ...
        "SB_SC"], strategies)) && ...
        any(string(profiles.CohortId) == "H20_PV10") && ...
        any(string(profiles.PvBoundaryId) == "DC_SOURCE") && ...
        any(string(profiles.PvBoundaryId) == "OBSERVED_RELEASE_FIELDS");
    if ~labelPass
        issues(end + 1, 1) = ...
            "figure5_profiles.csv lacks structural/observed, strategy, cohort, or boundary labels";
    end
catch exception
    issues(end + 1, 1) = "figure5_profiles.csv: " + ...
        string(exception.message);
end
try
    comparison = readtable(paths.figure5_target_comparison_csv, ...
        Delimiter=",", TextType="string", VariableNamingRule="preserve");
    required = ["Strategy", "PaperPrintedSavingsPercent", ...
        "LocalPaperLoadOnlySavingsPercent", "DifferencePercentagePoints", ...
        "LocalStatus", "SourceNote"];
    requireColumns(comparison, required, "figure5_target_comparison.csv");
    strategies = ["SH_BM", "VPP_BM", "PS", "PSDT", "LL", "SB_SC"];
    labelPass = height(comparison) == 6 && ...
        isequal(sort(string(comparison.Strategy)), sort(strategies.')) && ...
        all(strlength(strip(string(comparison.SourceNote))) > 0);
    if ~labelPass
        issues(end + 1, 1) = ...
            "figure5_target_comparison.csv lacks six strategy/source labels";
    end
catch exception
    issues(end + 1, 1) = "figure5_target_comparison.csv: " + ...
        string(exception.message);
end
end

function issues = auditMonthlyOutput(paths)
issues = strings(0, 1);
try
    profiles = readtable(paths.monthly_mean_profiles_csv, Delimiter=",", ...
        TextType="string", VariableNamingRule="preserve");
    required = ["YearMonth", "ScenarioId", "PairId", "CohortId", ...
        "PvBoundaryId", "TransferLossFraction", "Strategy", ...
        "ProfileType", "IntervalIndex", "IntervalEndHour", ...
        "MeanOriginalLoadKW", "MeanGridImportKW", "ValidProfileDays"];
    requireColumns(profiles, required, "monthly_mean_profiles.csv");
    labelPass = isempty(profiles) || ...
        (all(string(profiles.CohortId) == "H20_PV10") && ...
        all(string(profiles.PvBoundaryId) == "DC_SOURCE") && ...
        all(contains(lower(string(profiles.ProfileType)), "optimized")));
    if ~labelPass
        issues(end + 1, 1) = ...
            "monthly_mean_profiles.csv lacks cohort/boundary/proxy profile labels";
    end
catch exception
    issues(end + 1, 1) = "monthly_mean_profiles.csv: " + ...
        string(exception.message);
end
end

function issues = auditTableIOutput(paths)
issues = strings(0, 1);
try
    value = readtable(paths.table_i_target_vs_local_csv, Delimiter=",", ...
        TextType="string", VariableNamingRule="preserve");
    sensitivity = readtable(paths.bahloul_sensitivity_long_csv, ...
        Delimiter=",", TextType="string", VariableNamingRule="preserve");
    required = ["CaseId", "Day", "BudgetId", "Strategy", ...
        "ScenarioId", "PairId", "CohortId", "PvBoundaryId", ...
        "TransferLossFraction", "SensitivityRole", "CapacityRatio", ...
        "PowerRatio", "Status", "PaperTargetSavingsPercent", ...
        "LocalPaperSavingsPercent", "DifferencePercentagePoints"];
    requireColumns(value, required, "table_i_target_vs_local.csv");
    requireColumns(sensitivity, ["CaseId", "ExperimentId", "Status", ...
        "PaperLoadOnlySavingsPercent"], "bahloul_sensitivity_long.csv");
    labelPass = height(value) == 15 && ...
        all(ismember(["NOMINAL", "POWER_20", "CAPACITY_20"], ...
        unique(string(value.BudgetId)))) && ...
        all(ismember(["SH_BM", "VPP_BM", "PS", "PSDT", "LL"], ...
        unique(string(value.Strategy)))) && ...
        all(string(value.CohortId) == "H20_PV10") && ...
        all(string(value.ScenarioId) == "DC_XI007_H20") && ...
        all(string(value.PvBoundaryId) == "DC_SOURCE") && ...
        all(string(value.Status) == "ok") && ...
        numel(unique(string(value.CaseId))) == 15;
    if ~labelPass
        issues(end + 1, 1) = ...
            "table_i_target_vs_local.csv lacks the 15 successful primary target/local rows";
    else
        tableRows = sensitivity(string(sensitivity.ExperimentId) == ...
            "TABLE_I", :);
        for rowIndex = 1:height(value)
            selected = string(tableRows.CaseId) == string(value.CaseId(rowIndex));
            numericValues = [double(value.PaperTargetSavingsPercent(rowIndex)), ...
                double(value.LocalPaperSavingsPercent(rowIndex)), ...
                double(value.DifferencePercentagePoints(rowIndex))];
            if nnz(selected) ~= 1 || any(~isfinite(numericValues)) || ...
                    string(tableRows.Status(selected)) ~= "ok" || ...
                    ~scalarAgreementPassed(numericValues(2), ...
                    double(tableRows.PaperLoadOnlySavingsPercent(selected))) || ...
                    ~scalarAgreementPassed(numericValues(3), ...
                    numericValues(2) - numericValues(1))
                issues(end + 1, 1) = compose( ...
                    "Table I row %d has nonfinite or inconsistent values", ...
                    rowIndex); %#ok<AGROW>
            end
        end
    end
catch exception
    issues(end + 1, 1) = "table_i_target_vs_local.csv: " + ...
        string(exception.message);
end
end

function [passed, observed, details] = auditResultManifest(formalRoot)
manifestName = "SCIENTIFIC_ARTIFACT_MANIFEST.sha256";
manifestPath = string(fullfile(formalRoot, manifestName));
passed = false;
observed = "manifest missing";
details = manifestName + " must be at the formal root";
if ~isfile(manifestPath)
    return
end
lines = readlines(manifestPath);
lines = strip(lines);
lines = lines(strlength(lines) > 0);
if isempty(lines)
    observed = "entries=0";
    details = manifestName + " is empty";
    return
end
listedPaths = strings(numel(lines), 1);
hashes = strings(numel(lines), 1);
for lineIndex = 1:numel(lines)
    match = regexp(char(lines(lineIndex)), ...
        '^([0-9a-fA-F]{64})[ \t]+\*?(.+)$', 'tokens', 'once');
    if isempty(match)
        observed = compose("entries=%d", numel(lines));
        details = compose("malformed checksum line %d", lineIndex);
        return
    end
    hashes(lineIndex) = lower(string(match{1}));
    listedPaths(lineIndex) = normalizeRelativePath(string(match{2}));
end
excluded = manifestName;
if any(ismember(listedPaths, excluded))
    observed = compose("entries=%d", numel(lines));
    details = "scientific checksum manifest lists itself";
    return
end
if numel(unique(listedPaths)) ~= numel(listedPaths)
    observed = compose("entries=%d", numel(lines));
    details = "checksum manifest contains duplicate paths";
    return
end
for pathIndex = 1:numel(listedPaths)
    relative = listedPaths(pathIndex);
    if ~isSafeRelativePath(relative)
        observed = compose("entries=%d", numel(lines));
        details = "unsafe checksum path: " + relative;
        return
    end
    path = string(fullfile(formalRoot, replace(relative, "/", filesep)));
    if ~isfile(path)
        observed = compose("entries=%d", numel(lines));
        details = "checksum target missing: " + relative;
        return
    end
    if sha256File(path) ~= hashes(pathIndex)
        observed = compose("entries=%d", numel(lines));
        details = "checksum mismatch: " + relative;
        return
    end
end
actualPaths = formalFilesForClosure(formalRoot, excluded);
if ~isequal(sort(actualPaths), sort(listedPaths))
    missingFromManifest = setdiff(actualPaths, listedPaths);
    extraInManifest = setdiff(listedPaths, actualPaths);
    observed = compose("entries=%d; actual=%d", numel(lines), ...
        numel(actualPaths));
    details = "checksum closure mismatch; unlisted=" + ...
        strjoin(missingFromManifest, ",") + "; extra=" + ...
        strjoin(extraInManifest, ",");
    return
end
passed = true;
observed = compose("verified=%d/%d", numel(lines), numel(lines));
details = "all preregistered scientific artifacts are listed and verified";
end

function paths = formalFilesForClosure(formalRoot, excluded)
files = recursiveFiles(formalRoot, "*");
files = files(~[files.isdir]);
paths = strings(numel(files), 1);
for fileIndex = 1:numel(files)
    paths(fileIndex) = normalizeRelativePath(relativePath( ...
        formalRoot, fullPath(files(fileIndex))));
end
paths = unique(paths(~ismember(paths, excluded)), "sorted");
end

function [passed, observed, details] = auditInterpretation(formalRoot)
path = string(fullfile(formalRoot, "SCIENTIFIC_INTERPRETATION.md"));
required = ["proxy", "not exact", "no post-solve tuning"];
if ~isfile(path)
    passed = false;
    observed = "file missing";
    details = "SCIENTIFIC_INTERPRETATION.md is required at formal root";
    return
end
content = lower(string(fileread(path)));
found = false(size(required));
for requirementIndex = 1:numel(required)
    found(requirementIndex) = contains(content, required(requirementIndex));
end
passed = all(found);
observed = "found=" + strjoin(required(found), ",") + ...
    "; missing=" + strjoin(required(~found), ",");
if passed
    details = "all fixed proxy/non-exact/no-tuning disclosures are present";
else
    details = "missing fixed disclosure(s): " + ...
        strjoin(required(~found), ",");
end
end

function rule = makeRule(ruleId, name, passed, expected, observed, details)
status = "FAIL";
if passed
    status = "PASS";
end
rule = emptyRule();
rule.RuleId = ruleId;
rule.Name = name;
rule.Status = status;
rule.Expected = expected;
rule.Observed = observed;
rule.Details = details;
end

function rule = emptyRule()
rule = struct(RuleId="", Name="", Status="FAIL", Expected="", ...
    Observed="", Details="");
end

function [path, passed, details] = locateUniqueFile(root, name)
matches = recursiveFiles(root, name);
if isempty(matches)
    path = "";
    passed = false;
    details = name + " missing";
elseif numel(matches) > 1
    path = "";
    passed = false;
    details = compose("%s duplicated (%d copies)", name, numel(matches));
else
    path = fullPath(matches);
    passed = true;
    details = "";
end
end

function files = recursiveFiles(root, pattern)
files = dir(fullfile(root, "**", pattern));
rootMatches = dir(fullfile(root, pattern));
if ~isempty(rootMatches)
    recursivePaths = strings(numel(files), 1);
    for fileIndex = 1:numel(files)
        recursivePaths(fileIndex) = fullPath(files(fileIndex));
    end
    for matchIndex = 1:numel(rootMatches)
        candidatePath = fullPath(rootMatches(matchIndex));
        if ~any(recursivePaths == candidatePath)
            files(end + 1, 1) = rootMatches(matchIndex); %#ok<AGROW>
        end
    end
end
end

function directories = fileDirectories(files)
directories = strings(numel(files), 1);
for fileIndex = 1:numel(files)
    directories(fileIndex) = string(files(fileIndex).folder);
end
end

function path = fullPath(file)
path = string(fullfile(file.folder, file.name));
end

function path = canonicalFolder(path)
original = pwd;
cleaner = onCleanup(@() cd(original));
cd(path);
path = string(pwd);
clear cleaner
end

function relative = relativePath(root, path)
rootPrefix = root + string(filesep);
if path == root
    relative = ".";
elseif startsWith(path, rootPrefix)
    relative = extractAfter(path, strlength(rootPrefix));
else
    relative = path;
end
relative = normalizeRelativePath(relative);
end

function path = normalizeRelativePath(path)
path = replace(strip(string(path)), "\", "/");
while startsWith(path, "./")
    path = extractAfter(path, 2);
end
end

function passed = isSafeRelativePath(path)
parts = split(path, "/");
passed = strlength(path) > 0 && ~startsWith(path, "/") && ...
    ~any(parts == "..") && ~any(parts == "") && ...
    isempty(regexp(char(path), '^[A-Za-z]:', 'once'));
end

function bytes = fileSize(path)
info = dir(path);
if isempty(info)
    bytes = -1;
else
    bytes = info(1).bytes;
end
end

function hash = sha256File(path)
hash = storenetio.hashFile(path);
end

function detail = appendDetail(detail, addition)
if strlength(detail) == 0
    detail = addition;
else
    detail = detail + "; " + addition;
end
end

function writeTableAtomic(value, path)
temporaryPath = string(tempname(fileparts(path))) + ".csv";
cleaner = onCleanup(@() deleteIfPresent(temporaryPath));
writetable(value, temporaryPath);
movefile(temporaryPath, path, "f");
clear cleaner
end

function writeJsonAtomic(value, path)
temporaryPath = string(tempname(fileparts(path))) + ".json";
fileId = fopen(temporaryPath, "wt", "n", "UTF-8");
if fileId < 0
    error("StoreNet:BahloulAcceptanceWriteFailed", ...
        "Cannot create post-solve JSON output.");
end
try
    jsonValue = struct;
    jsonValue.schemaVersion = value.schemaVersion;
    jsonValue.contractId = value.contractId;
    jsonValue.formalRoot = value.formalRoot;
    jsonValue.generatedAtUtc = value.generatedAtUtc;
    jsonValue.overallStatus = value.overallStatus;
    jsonValue.allRulesPassed = value.allRulesPassed;
    jsonValue.rules = table2struct(value.ruleTable);
    jsonValue.cases = table2struct(value.caseTable);
    jsonValue.inventory = value.inventory;
    jsonValue.disclosureRequirements = value.disclosureRequirements;
    fprintf(fileId, "%s\n", jsonencode(jsonValue, PrettyPrint=true));
    fclose(fileId);
    fileId = -1;
    movefile(temporaryPath, path, "f");
catch exception
    if fileId >= 0
        fclose(fileId);
    end
    rethrow(exception)
end
end

function deleteIfPresent(path)
if isfile(path)
    delete(path);
end
end
