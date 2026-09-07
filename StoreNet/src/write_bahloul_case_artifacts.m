function artifacts = write_bahloul_case_artifacts(caseDirectory, data, config, ...
        caseMeta, solution, metrics)
%WRITE_BAHLOUL_CASE_ARTIFACTS Persist a self-contained optimization case.
%   The MAT artifacts are named from the SHA-256 of their final bytes. The
%   digest is intentionally kept outside each MAT file to avoid a checksum
%   cycle. Existing nonempty case directories are never overwritten.

arguments
    caseDirectory (1, 1) string
    data (1, 1) struct
    config (1, 1) struct
    caseMeta (1, 1) struct
    solution (1, 1) struct
    metrics (1, 1) struct
end

directoryAlreadyExisted = isfolder(caseDirectory);
if directoryAlreadyExisted && hasMaterialEntries(caseDirectory)
    error("StoreNet:BahloulCaseDirectoryExists", ...
        "Refusing to overwrite nonempty case directory: %s", caseDirectory);
end
if ~directoryAlreadyExisted
    mkdir(caseDirectory);
end

temporaryInputsPath = string(tempname(caseDirectory)) + ".mat";
temporarySolutionPath = string(tempname(caseDirectory)) + ".mat";
stagesPath = string(fullfile(caseDirectory, "stages.csv"));
metricsPath = string(fullfile(caseDirectory, "metrics.json"));
createdPaths = strings(0, 1);

try
    inputEvidence = makeInputEvidence(data, config, caseMeta);
    formalMetrics = removeDeprecatedMetricAliases(metrics);
    formalSolution = solution;
    if isfield(formalSolution, "metrics")
        formalSolution.metrics = formalMetrics;
    end
    solutionEvidence = makeSolutionEvidence(formalSolution, formalMetrics, config, ...
        caseMeta);

    save(temporaryInputsPath, "inputEvidence", "-v7");
    save(temporarySolutionPath, "solutionEvidence", "-v7");
    inputsSha256 = sha256File(temporaryInputsPath);
    solutionSha256 = sha256File(temporarySolutionPath);
    inputsPath = string(fullfile(caseDirectory, ...
        "inputs_" + inputsSha256 + ".mat"));
    solutionPath = string(fullfile(caseDirectory, ...
        "solution_" + solutionSha256 + ".mat"));
    refuseExistingTarget(inputsPath);
    refuseExistingTarget(solutionPath);
    moveArtifact(temporaryInputsPath, inputsPath);
    createdPaths(end + 1, 1) = inputsPath;
    moveArtifact(temporarySolutionPath, solutionPath);
    createdPaths(end + 1, 1) = solutionPath;

    stages = stageTable(solution, config);
    writetable(stages, stagesPath);
    createdPaths(end + 1, 1) = stagesPath;
    writeJson(metricsPath, formalMetrics);
catch exception
    deleteIfPresent(temporaryInputsPath);
    deleteIfPresent(temporarySolutionPath);
    deleteCreatedPaths(createdPaths);
    removeNewEmptyDirectory(caseDirectory, directoryAlreadyExisted);
    rethrow(exception)
end

artifacts = struct;
artifacts.inputsPath = inputsPath;
artifacts.inputsSha256 = inputsSha256;
artifacts.solutionPath = solutionPath;
artifacts.solutionSha256 = solutionSha256;
artifacts.stagesPath = stagesPath;
artifacts.metricsPath = metricsPath;
end

function metrics = removeDeprecatedMetricAliases(metrics)
deprecated = ["baselineDefinition", "deprecatedBaselineAliasTarget", ...
    "baselineBillEUR", "baselinePeakImportKW", ...
    "baselineDaytimePeakImportKW", "savingsEUR", "savingsPercent"];
present = deprecated(isfield(metrics, cellstr(deprecated)));
if ~isempty(present)
    metrics = rmfield(metrics, cellstr(present));
end
end

function inputEvidence = makeInputEvidence(data, config, caseMeta)
timeEnd = data.time(:);
intervalStart = timeEnd - hours(double(data.dtHours));
dayMask = hour(intervalStart) >= config.dayStartHour & ...
    hour(intervalStart) < config.dayEndHour;
pricePerKWh = repmat(double(config.nightPrice), numel(timeEnd), 1);
pricePerKWh(dayMask) = double(config.dayPrice);

releasedPvKW = double(data.pvKW);
if isfield(data, "releasedPvKW")
    releasedPvKW = double(data.releasedPvKW);
end
pvGenDC = double(data.pvKW);
pvAvailableAC = double(config.etaPvAC) .* pvGenDC;

[qualityMode, qualityAvailable, qualitySource] = resolveField( ...
    {caseMeta, config, data}, ["caseMeta", "config", "data"], ...
    ["qualityMode", "qualityModeRequested"], "unavailable");
[observationMask, observationAvailable, observationSource] = resolveField( ...
    evidenceSources(data, caseMeta, config), ...
    evidenceSourceNames(caseMeta), ...
    ["observationMask", "observedMask", "binObserved", ...
    "minuteObserved"], logical.empty(0, 0));
[interpolationMask, interpolationAvailable, interpolationSource] = ...
    resolveField(evidenceSources(data, caseMeta, config), ...
    evidenceSourceNames(caseMeta), ...
    ["interpolationMask", "interpolatedMask"], logical.empty(0, 0));
[cohortMask, cohortAvailable, cohortSource] = resolveField( ...
    evidenceSources(data, caseMeta, config), ...
    evidenceSourceNames(caseMeta), "cohortMask", logical.empty(0, 0));
if ~cohortAvailable
    cohortMask = ismember(compose("H%d", 1:20), string(data.houseIds(:)).');
    cohortAvailable = true;
    cohortSource = "derived:houseIds";
end
[h4MaskAffected, h4AffectedAvailable, h4AffectedSource] = resolveField( ...
    {caseMeta, config, data}, ["caseMeta", "config", "data"], ...
    "h4MaskAffected", NaN);
[h4Mask, h4MaskAvailable, h4MaskSource] = resolveField( ...
    evidenceSources(data, caseMeta, config), ...
    evidenceSourceNames(caseMeta), "h4Mask", logical.empty(0, 0));
if ~h4MaskAvailable && h4AffectedAvailable && ...
        isscalar(h4MaskAffected) && ~isnan(double(h4MaskAffected))
    h4Mask = repmat(logical(h4MaskAffected), numel(timeEnd), 1);
    h4MaskAvailable = true;
    h4MaskSource = "derived:caseMeta.h4MaskAffected";
end

inputEvidence = struct;
inputEvidence.schemaVersion = "B2022-input-evidence-v2";
inputEvidence.timeEnd = timeEnd;
inputEvidence.intervalStart = intervalStart;
inputEvidence.dtHours = double(data.dtHours);
inputEvidence.houseIds = string(data.houseIds(:)).';
inputEvidence.loadKW = double(data.loadKW);
inputEvidence.releasedPvKW = releasedPvKW;
inputEvidence.PVGenDC = pvGenDC;
inputEvidence.pvAvailableAC = pvAvailableAC;
inputEvidence.modelPvAvailableKW = pvGenDC;
inputEvidence.pricePerKWh = pricePerKWh;
inputEvidence.dayMask = logical(dayMask);
inputEvidence.qualityMode = string(qualityMode);
inputEvidence.observationMask = logical(observationMask);
inputEvidence.interpolationMask = logical(interpolationMask);
inputEvidence.cohortMask = logical(cohortMask);
inputEvidence.h4Mask = logical(h4Mask);
inputEvidence.h4MaskAffected = h4MaskAffected;
inputEvidence.maskAvailability = struct( ...
    "qualityMode", availabilityRecord(qualityAvailable, qualitySource), ...
    "observationMask", availabilityRecord(observationAvailable, ...
    observationSource), ...
    "interpolationMask", availabilityRecord(interpolationAvailable, ...
    interpolationSource), ...
    "cohortMask", availabilityRecord(cohortAvailable, cohortSource), ...
    "h4Mask", availabilityRecord(h4MaskAvailable, h4MaskSource), ...
    "h4MaskAffected", availabilityRecord(h4AffectedAvailable, ...
    h4AffectedSource));
inputEvidence.identity = makeCaseIdentity(data, config, caseMeta);
inputEvidence.data = data;
inputEvidence.config = config;
inputEvidence.caseMeta = caseMeta;
end

function sources = evidenceSources(data, caseMeta, config)
sources = {data, caseMeta, config};
if isfield(caseMeta, "dataMeta") && isstruct(caseMeta.dataMeta) && ...
        isscalar(caseMeta.dataMeta)
    sources{end + 1} = caseMeta.dataMeta;
end
end

function names = evidenceSourceNames(caseMeta)
names = ["data", "caseMeta", "config"];
if isfield(caseMeta, "dataMeta") && isstruct(caseMeta.dataMeta) && ...
        isscalar(caseMeta.dataMeta)
    names(end + 1) = "caseMeta.dataMeta";
end
end

function identity = makeCaseIdentity(data, config, caseMeta)
sources = {caseMeta, config, data};
sourceNames = ["caseMeta", "config", "data"];
identity = struct;
identity.experimentId = identityField(sources, sourceNames, ...
    "experimentId", "unavailable");
identity.caseId = identityField(sources, sourceNames, ...
    "caseId", "unavailable");
identity.dateOrPeriod = identityField(sources, sourceNames, ...
    ["day", "dateOrPeriod"], "unavailable");
identity.qualityMode = identityField(sources, sourceNames, ...
    ["qualityMode", "qualityModeRequested"], "unavailable");
identity.strategy = identityField(sources, sourceNames, ...
    "strategy", "unavailable");
identity.cohortId = identityField(sources, sourceNames, ...
    "cohortId", "unavailable");
identity.capacityRatio = identityField(sources, sourceNames, ...
    "capacityRatio", NaN);
identity.powerRatio = identityField(sources, sourceNames, ...
    "powerRatio", NaN);
identity.pvBoundaryId = identityField(sources, sourceNames, ...
    "pvBoundaryId", "unavailable");
identity.xi = identityField(sources, sourceNames, ...
    ["xi", "transferLossFraction"], NaN);
identity.pairId = identityField(sources, sourceNames, ...
    "pairId", "unavailable");
identity.scenarioId = identityField(sources, sourceNames, ...
    "scenarioId", "unavailable");
identity.referenceIds = identityField(sources, sourceNames, ...
    ["referenceIds", "referenceId"], strings(0, 1));
identity.referenceHashes = identityField(sources, sourceNames, ...
    ["referenceHashes", "referenceHash", "referenceManifestSha256"], ...
    strings(0, 1));
identity.dataContractId = identityField(sources, sourceNames, ...
    "dataContractId", "unavailable");
identity.dataContractSha256 = identityField(sources, sourceNames, ...
    "dataContractSha256", "unavailable");
identity.dataContractGitCommit = identityField(sources, sourceNames, ...
    "dataContractGitCommit", "unavailable");
identity.modelContractId = identityField(sources, sourceNames, ...
    "modelContractId", "unavailable");
identity.modelContractSha256 = identityField(sources, sourceNames, ...
    "modelContractSha256", "unavailable");
identity.referenceManifestSha256 = identityField(sources, sourceNames, ...
    "referenceManifestSha256", "unavailable");
end

function item = identityField(sources, sourceNames, fieldNames, defaultValue)
[value, available, source] = resolveField(sources, sourceNames, ...
    fieldNames, defaultValue);
item = struct("value", value, "available", available, "source", source);
end

function record = availabilityRecord(available, source)
record = struct("available", logical(available), "source", string(source));
if available
    record.reason = "";
else
    record.reason = "not_provided_by_caller";
end
end

function solutionEvidence = makeSolutionEvidence(solution, metrics, config, ...
        caseMeta)
solutionEvidence = struct;
solutionEvidence.schemaVersion = "B2022-solution-evidence-v2";
solutionEvidence.solution = solution;
solutionEvidence.metrics = metrics;
solutionEvidence.stages = normalizedStages(solution, config);

flowNames = ["pvToHomeKW", "pvToBatteryKW", "pvToGridKW", ...
    "pvCurtailKW", "gridToHomeKW", "gridToBatteryKW", ...
    "batteryToHomeKW", "batteryToGridKW"];
availability = struct;
for fieldIndex = 1:numel(flowNames)
    fieldName = flowNames(fieldIndex);
    [value, available] = solutionField(solution, fieldName, []);
    solutionEvidence.(fieldName) = value;
    availability.(fieldName) = logical(available);
end
[chargePower, chargeAvailable] = solutionField(solution, ...
    ["chargePowerKW", "batteryChargeKW"], []);
[dischargePower, dischargeAvailable] = solutionField(solution, ...
    ["dischargePowerKW", "batteryDischargeKW"], []);
solutionEvidence.chargePowerKW = chargePower;
solutionEvidence.dischargePowerKW = dischargePower;
availability.chargePowerKW = logical(chargeAvailable);
availability.dischargePowerKW = logical(dischargeAvailable);
remainingNames = ["aggregateImportKW", "socKWh", "chargeOn", ...
    "dischargeOn"];
for fieldIndex = 1:numel(remainingNames)
    fieldName = remainingNames(fieldIndex);
    [value, available] = solutionField(solution, fieldName, []);
    solutionEvidence.(fieldName) = value;
    availability.(fieldName) = logical(available);
end
solutionEvidence.fieldAvailability = availability;
solutionEvidence.provenance = makeSolutionProvenance(solution, config, ...
    caseMeta);
end

function provenance = makeSolutionProvenance(solution, config, caseMeta)
sources = {solution, caseMeta, config};
sourceNames = ["solution", "caseMeta", "config"];
[solver, solverAvailable, solverSource] = resolveField(sources, ...
    sourceNames, ["solverProvenance", "solver"], struct);
[provider, providerAvailable, providerSource] = resolveField(sources, ...
    sourceNames, ["dataProviderProvenance", "providerProvenance", ...
    "provider"], struct);
provenance = struct;
provenance.solver = solver;
provenance.provider = provider;
provenance.runtime = runtimeProvenance();
provenance.availability = struct( ...
    "solver", availabilityRecord(solverAvailable, solverSource), ...
    "provider", availabilityRecord(providerAvailable, providerSource), ...
    "runtime", availabilityRecord(true, "writer_runtime"));
end

function runtime = runtimeProvenance()
runtime = struct;
runtime.matlabVersion = string(version);
runtime.matlabRelease = string(version("-release"));
runtime.computer = string(computer);
runtime.timestampUtc = datetime("now", TimeZone="UTC", ...
    Format="yyyy-MM-dd'T'HH:mm:ss.SSSXXX");
optimizationInfo = ver("optim");
if isempty(optimizationInfo)
    runtime.optimizationToolboxVersion = "unavailable";
else
    runtime.optimizationToolboxVersion = string(optimizationInfo(1).Version);
end
end

function stages = normalizedStages(solution, config)
if ~isfield(solution, "objectiveStages") || isempty(solution.objectiveStages)
    stages = struct("name", {}, "value", {}, "solverObjective", {}, ...
        "allowance", {}, "allowanceApplied", {}, "exitFlag", {}, ...
        "relativeGap", {}, "finalRecomputedValue", {}, "message", {});
    return
end
records = solution.objectiveStages(:);
stages = repmat(struct("name", "", "value", NaN, ...
    "solverObjective", NaN, "allowance", NaN, ...
    "allowanceApplied", false, "exitFlag", NaN, ...
    "relativeGap", NaN, "finalRecomputedValue", NaN, ...
    "message", ""), numel(records), 1);
for stageIndex = 1:numel(records)
    record = records(stageIndex);
    stages(stageIndex).name = string(optionalStructField(record, "name", ""));
    stages(stageIndex).value = double(optionalStructField(record, ...
        "value", NaN));
    stages(stageIndex).solverObjective = double(optionalStructField( ...
        record, "solverObjective", NaN));
    stages(stageIndex).allowance = stageAllowance(record, config, ...
        stages(stageIndex).value);
    stages(stageIndex).allowanceApplied = logical(optionalStructField( ...
        record, "lockedInLaterStage", stageIndex < numel(records)));
    stages(stageIndex).exitFlag = double(optionalStructField(record, ...
        "exitFlag", NaN));
    stages(stageIndex).relativeGap = double(optionalStructField(record, ...
        "relativeGap", NaN));
    stages(stageIndex).finalRecomputedValue = double(optionalStructField( ...
        record, "finalRecomputedValue", NaN));
    stages(stageIndex).message = string(optionalStructField(record, ...
        "message", ""));
end
end

function allowance = stageAllowance(record, config, value)
if isfield(record, "allowance")
    allowance = double(record.allowance);
elseif isfield(config, "lexicographicTolerance") && isfinite(value)
    allowance = double(config.lexicographicTolerance) .* max(1, abs(value));
else
    allowance = NaN;
end
end

function value = optionalStructField(container, fieldName, defaultValue)
value = defaultValue;
if isfield(container, fieldName)
    value = container.(fieldName);
end
end

function [value, available] = solutionField(solution, fieldNames, defaultValue)
fieldNames = string(fieldNames);
value = defaultValue;
available = false;
for fieldIndex = 1:numel(fieldNames)
    fieldName = fieldNames(fieldIndex);
    if isfield(solution, fieldName)
        value = solution.(fieldName);
        available = true;
        return
    end
end
end

function [value, available, source] = resolveField(sources, sourceNames, ...
        fieldNames, defaultValue)
fieldNames = string(fieldNames);
value = defaultValue;
available = false;
source = "unavailable";
for sourceIndex = 1:numel(sources)
    container = sources{sourceIndex};
    for fieldIndex = 1:numel(fieldNames)
        fieldName = fieldNames(fieldIndex);
        if isfield(container, fieldName)
            value = container.(fieldName);
            available = true;
            source = sourceNames(sourceIndex) + "." + fieldName;
            return
        end
    end
end
end

function tf = hasMaterialEntries(directory)
entries = dir(directory);
names = string({entries.name});
tf = any(~ismember(names, [".", ".."]) & ~startsWith(names, ".nfs"));
end

function stages = stageTable(solution, config)
records = normalizedStages(solution, config);
if isempty(records)
    stages = table(strings(0, 1), zeros(0, 1), zeros(0, 1), ...
        zeros(0, 1), false(0, 1), zeros(0, 1), zeros(0, 1), ...
        zeros(0, 1), strings(0, 1), VariableNames=["Name", "Value", ...
        "SolverObjective", "Allowance", "AllowanceApplied", ...
        "ExitFlag", "RelativeGap", "FinalRecomputedValue", "Message"]);
    return
end
stages = struct2table(records);
stages.Properties.VariableNames = ["Name", "Value", "SolverObjective", ...
    "Allowance", "AllowanceApplied", "ExitFlag", "RelativeGap", ...
    "FinalRecomputedValue", "Message"];
end

function hash = sha256File(path)
hash = storenetio.hashFile(path);
end

function refuseExistingTarget(path)
if isfile(path) || isfolder(path)
    error("StoreNet:BahloulArtifactExists", ...
        "Refusing to overwrite content-addressed artifact: %s", path);
end
end

function moveArtifact(source, destination)
[moved, message] = movefile(source, destination);
if ~moved
    error("StoreNet:BahloulArtifactWriteFailed", ...
        "Cannot promote artifact %s: %s", destination, message);
end
end

function writeJson(path, value)
temporaryPath = string(tempname(fileparts(path))) + ".json";
fileId = fopen(temporaryPath, "wt", "n", "UTF-8");
if fileId < 0
    error("StoreNet:BahloulArtifactWriteFailed", ...
        "Cannot open temporary JSON file: %s", temporaryPath);
end
try
    fprintf(fileId, "%s\n", jsonencode(makeJsonSafe(value), PrettyPrint=true));
    fclose(fileId);
    fileId = -1;
    refuseExistingTarget(path);
    moveArtifact(temporaryPath, path);
catch exception
    closeAndDelete(fileId, temporaryPath);
    rethrow(exception)
end
end

function value = makeJsonSafe(value)
if isdatetime(value) || isduration(value) || isa(value, "calendarDuration")
    value = string(value);
elseif istable(value)
    value = table2struct(value);
elseif isa(value, "function_handle")
    value = string(func2str(value));
end
if isstruct(value)
    fields = string(fieldnames(value));
    for elementIndex = 1:numel(value)
        for fieldIndex = 1:numel(fields)
            field = fields(fieldIndex);
            value(elementIndex).(field) = makeJsonSafe(value(elementIndex).(field));
        end
    end
elseif iscell(value)
    for cellIndex = 1:numel(value)
        value{cellIndex} = makeJsonSafe(value{cellIndex});
    end
end
end

function closeAndDelete(fileId, path)
if fileId >= 0
    fclose(fileId);
end
deleteIfPresent(path);
end

function deleteCreatedPaths(paths)
for pathIndex = 1:numel(paths)
    deleteIfPresent(paths(pathIndex));
end
end

function deleteIfPresent(path)
if isfile(path)
    delete(path);
end
end

function removeNewEmptyDirectory(directory, directoryAlreadyExisted)
if ~directoryAlreadyExisted && isfolder(directory) && ...
        ~hasMaterialEntries(directory)
    rmdir(directory);
end
end
