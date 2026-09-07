function run = run_external_validation(options)
%RUN_EXTERNAL_VALIDATION Run the preregistered Ausgrid transfer experiment.
%   RUN = RUN_EXTERNAL_VALIDATION(...) selects one representative day per
%   calendar month without using optimization outcomes, executes the frozen
%   primary strategy order, and evaluates a seasonal epsilon-constraint
%   frontier. Every solver output is independently checked by
%   EVALUATE_STORENET before it is accepted.

arguments
    options.SpecPath (1, 1) string = ""
    options.SourceFile (1, 1) string = ""
    options.OutputRoot (1, 1) string = ""
    options.RunId (1, 1) string = ""
    options.Solver (1, 1) function_handle = @solve_storenet
    options.FigureVisible (1, 1) logical = false
    options.VerifySha256 (1, 1) logical = true
    options.SpecLoader (1, 1) function_handle = ...
        @(varargin) crossenv.loadAusgridSpec(varargin{:})
    options.YearReader (1, 1) function_handle = ...
        @(varargin) crossenv.adapters.readAusgridYear(varargin{:})
    options.DayProvider (1, 1) function_handle = ...
        @(varargin) crossenv.adapters.loadAusgridDay(varargin{:})
    options.DaySelector (1, 1) function_handle = ...
        @(varargin) crossenv.selectMonthlyDays(varargin{:})
    options.AcceptanceEvaluator (1, 1) function_handle = ...
        @(varargin) crossenv.evaluateExternalAcceptance(varargin{:})
end

sourceFolder = string(fileparts(mfilename("fullpath")));
repositoryRoot = string(fullfile(sourceFolder, "..", ".."));
if strlength(options.SpecPath) == 0
    options.SpecPath = string(fullfile(sourceFolder, "..", "config", ...
        "crossenv", "ausgrid_2012_2013.json"));
end
if strlength(options.OutputRoot) == 0
    options.OutputRoot = string(fullfile(sourceFolder, "..", "results"));
end
if strlength(options.RunId) == 0
    options.RunId = "external_validation_ausgrid_" + ...
        string(datetime("now"), "yyyyMMdd_HHmmss_SSS");
end
runDirectory = prepareRunDirectory(options.OutputRoot, options.RunId);

spec = callSpecLoader(options.SpecLoader, options.SpecPath);
sourceFile = resolveSourceFile(options.SourceFile, spec);
yearData = options.YearReader(spec, SourceFile=sourceFile, ...
    VerifySha256=options.VerifySha256);
[selection, ranking] = options.DaySelector(yearData);
[selection, ranking] = validateSelection(selection, ranking);

selectionPath = fullfile(runDirectory, "selection.csv");
rankingPath = fullfile(runDirectory, "ranking.csv");
writetable(selection, selectionPath);
writetable(ranking, rankingPath);

[config, fixedPolicyOverrides] = makeFixedPolicyConfig(spec, sourceFile);
tolerances = acceptanceTolerances(spec);
gateTolerances = makeGateTolerances(tolerances, config);
primaryStrategies = ["SH_BM", "VPP_BM", "IMPROVED_PEAK_GUARD"];
frontierMonths = [3, 6, 9, 12];
frontierAlphas = [1, 0.75, 0.5, 0.25, 0];
minimumPeakAllowanceKW = 1e-6;
validateFrozenProtocol(spec, primaryStrategies, frontierMonths, frontierAlphas);

primaryRows = repmat(emptyMetricRow(), 0, 1);
frontierReferenceRows = repmat(emptyMetricRow(), 0, 1);
frontierRows = repmat(emptyMetricRow(), 0, 1);
selectedData = cell(12, 1);
selectedMetadata = cell(12, 1);
dataStates = repmat(emptyDataState(), 12, 1);
baselinePeakKW = nan(12, 1);

for selectionIndex = 1:height(selection)
    monthNumber = double(selection.Month(selectionIndex));
    selectedDay = selection.Day(selectionIndex);
    try
        [data, metadata] = options.DayProvider(selectedDay, spec, ...
            SourceFile=sourceFile);
        data = normalizeCanonicalData(data);
        enforceProviderQuality(data, metadata, selectedDay);
        selectedData{monthNumber} = data;
        selectedMetadata{monthNumber} = metadata;
        dataStates(monthNumber) = passedDataState();
        baselinePeakKW(monthNumber) = noBatteryBaselinePeak(data, config);
    catch exception
        dataStates(monthNumber) = failedDataState(exception);
    end

    if dataStates(monthNumber).status ~= "ok"
        for strategyIndex = 1:numel(primaryStrategies)
            primaryRows(end + 1, 1) = failureMetricRow( ...
                "primary", monthNumber, selectedDay, strategyIndex, ...
                primaryStrategies(strategyIndex), NaN, NaN, NaN, NaN, NaN, ...
                dataStates(monthNumber).status, ...
                dataStates(monthNumber).identifier, ...
                dataStates(monthNumber).message); %#ok<AGROW>
            writeExternalCheckpoint(runDirectory, primaryRows, ...
                frontierReferenceRows, frontierRows, false);
        end
        continue
    end

    data = selectedData{monthNumber};
    p0KW = baselinePeakKW(monthNumber);
    for strategyIndex = 1:numel(primaryStrategies)
        strategy = primaryStrategies(strategyIndex);
        strategyConfig = config;
        requestedCapKW = NaN;
        effectiveCapKW = NaN;
        if strategy == "IMPROVED_PEAK_GUARD"
            requestedCapKW = p0KW;
            effectiveCapKW = p0KW;
            strategyConfig.aggregateImportCapKW = effectiveCapKW;
        end
        [row, ~] = executeAndEvaluate(options.Solver, data, strategyConfig, ...
            strategy, tolerances, "primary", monthNumber, selectedDay, ...
            strategyIndex, NaN, requestedCapKW, effectiveCapKW, p0KW, NaN);
        primaryRows(end + 1, 1) = row; %#ok<AGROW>
        writeExternalCheckpoint(runDirectory, primaryRows, ...
            frontierReferenceRows, frontierRows, false);
    end
end

for frontierIndex = 1:numel(frontierMonths)
    monthNumber = frontierMonths(frontierIndex);
    selectedDay = selection.Day(selection.Month == monthNumber);
    state = dataStates(monthNumber);
    p0KW = baselinePeakKW(monthNumber);
    if state.status ~= "ok"
        frontierReferenceRows(end + 1, 1) = failureMetricRow( ...
            "frontier_ps_reference", monthNumber, selectedDay, 1, "PS", ...
            NaN, NaN, NaN, p0KW, NaN, state.status, state.identifier, ...
            state.message); %#ok<AGROW>
        writeExternalCheckpoint(runDirectory, primaryRows, ...
            frontierReferenceRows, frontierRows, false);
        skippedRows = makeSkippedFrontierRows(monthNumber, ...
            selectedDay, frontierAlphas, p0KW, NaN, state.identifier, state.message);
        for skippedIndex = 1:numel(skippedRows)
            frontierRows(end + 1, 1) = skippedRows(skippedIndex); %#ok<AGROW>
            writeExternalCheckpoint(runDirectory, primaryRows, ...
                frontierReferenceRows, frontierRows, false);
        end
        continue
    end

    data = selectedData{monthNumber};
    [psRow, ~] = executeAndEvaluate(options.Solver, data, config, "PS", ...
        tolerances, "frontier_ps_reference", monthNumber, selectedDay, 1, ...
        NaN, NaN, NaN, p0KW, NaN);
    frontierReferenceRows(end + 1, 1) = psRow; %#ok<AGROW>
    writeExternalCheckpoint(runDirectory, primaryRows, ...
        frontierReferenceRows, frontierRows, false);
    if psRow.Status ~= "ok"
        skippedRows = makeSkippedFrontierRows(monthNumber, ...
            selectedDay, frontierAlphas, p0KW, NaN, psRow.ErrorIdentifier, ...
            psRow.ErrorMessage);
        for skippedIndex = 1:numel(skippedRows)
            frontierRows(end + 1, 1) = skippedRows(skippedIndex); %#ok<AGROW>
            writeExternalCheckpoint(runDirectory, primaryRows, ...
                frontierReferenceRows, frontierRows, false);
        end
        continue
    end

    pminKW = psRow.PeakImportKW;
    frontierReferenceRows(end).PminKW = pminKW;
    writeExternalCheckpoint(runDirectory, primaryRows, ...
        frontierReferenceRows, frontierRows, false);
    if pminKW > p0KW + tolerances.peakCapViolationKW
        identifier = "StoreNet:InvalidFrontierReference";
        message = "PS peak exceeds the ex-ante no-battery baseline peak.";
        skippedRows = makeSkippedFrontierRows(monthNumber, ...
            selectedDay, frontierAlphas, p0KW, pminKW, identifier, message);
        for skippedIndex = 1:numel(skippedRows)
            frontierRows(end + 1, 1) = skippedRows(skippedIndex); %#ok<AGROW>
            writeExternalCheckpoint(runDirectory, primaryRows, ...
                frontierReferenceRows, frontierRows, false);
        end
        continue
    end

    for alphaIndex = 1:numel(frontierAlphas)
        alpha = frontierAlphas(alphaIndex);
        requestedCapKW = pminKW + alpha * (p0KW - pminKW);
        effectiveCapKW = requestedCapKW;
        if alpha == 0
            effectiveCapKW = requestedCapKW + minimumPeakAllowanceKW;
        end
        frontierConfig = config;
        frontierConfig.aggregateImportCapKW = effectiveCapKW;
        [row, ~] = executeAndEvaluate(options.Solver, data, frontierConfig, ...
            "IMPROVED_PEAK_GUARD", tolerances, "frontier", monthNumber, ...
            selectedDay, alphaIndex + 1, alpha, requestedCapKW, ...
            effectiveCapKW, p0KW, pminKW);
        frontierRows(end + 1, 1) = row; %#ok<AGROW>
        writeExternalCheckpoint(runDirectory, primaryRows, ...
            frontierReferenceRows, frontierRows, false);
    end
end

[primaryMetrics, frontierReferenceMetrics, frontierMetrics] = ...
    writeExternalCheckpoint(runDirectory, primaryRows, frontierReferenceRows, ...
    frontierRows, false);
gateTolerances.billMonotonicEUR = scaledBillMonotonicTolerance( ...
    frontierMetrics, config);
primaryMetricsPath = fullfile(runDirectory, "primary_metrics.csv");
frontierReferenceMetricsPath = fullfile(runDirectory, ...
    "frontier_reference_metrics.csv");
frontierMetricsPath = fullfile(runDirectory, "frontier_metrics.csv");
checkpointPath = fullfile(runDirectory, "external_validation_checkpoint.csv");

summary = options.AcceptanceEvaluator(primaryMetrics, frontierMetrics, ...
    gateTolerances);
if ~isstruct(summary) || ~isscalar(summary)
    error("StoreNet:InvalidExternalAcceptanceReport", ...
        "The external acceptance evaluator must return a scalar struct.");
end
summaryPath = fullfile(runDirectory, "summary.json");
writeJson(summaryPath, summary);

releaseManifestPath = resolveReleaseManifest(spec, repositoryRoot);
if ~isfile(releaseManifestPath)
    error("StoreNet:MissingExternalManifest", ...
        "The external data manifest is missing: %s", releaseManifestPath);
end
runInfo = makeRunInfo(options, spec, options.SpecPath, sourceFile, yearData, ...
    selection, config, fixedPolicyOverrides, tolerances, gateTolerances, ...
    primaryStrategies, ...
    frontierMonths, frontierAlphas, minimumPeakAllowanceKW, primaryMetrics, ...
    frontierReferenceMetrics, frontierMetrics, summary);
[manifest, manifestPath] = write_run_manifest(runDirectory, runInfo, ...
    RepositoryRoot=repositoryRoot, ReleaseManifestPath=releaseManifestPath);
writeExternalCheckpoint(runDirectory, primaryRows, frontierReferenceRows, ...
    frontierRows, true);

run = struct;
run.runDirectory = runDirectory;
run.selectionPath = selectionPath;
run.rankingPath = rankingPath;
run.primaryMetricsPath = primaryMetricsPath;
run.frontierReferenceMetricsPath = frontierReferenceMetricsPath;
run.frontierMetricsPath = frontierMetricsPath;
run.checkpointPath = checkpointPath;
run.summaryPath = summaryPath;
run.manifestPath = manifestPath;
run.selection = selection;
run.ranking = ranking;
run.primaryMetrics = primaryMetrics;
run.frontierReferenceMetrics = frontierReferenceMetrics;
run.frontierMetrics = frontierMetrics;
run.configuration = config;
run.fixedPolicyOverrides = fixedPolicyOverrides;
run.gateTolerances = gateTolerances;
run.spec = spec;
run.summary = summary;
run.manifest = manifest;
run.selectedMetadata = selectedMetadata;
end

function directory = prepareRunDirectory(outputRoot, runId)
if any(contains(runId, ["/", "\\"])) || contains(runId, "..")
    error("StoreNet:InvalidRunId", ...
        "RunId must be a simple directory name without separators or '..'.");
end
if ~isfolder(outputRoot)
    mkdir(outputRoot);
end
directory = string(fullfile(outputRoot, runId));
if isfolder(directory) && ~isempty(dir(fullfile(directory, "*")))
    error("StoreNet:RunDirectoryExists", ...
        "Refusing to overwrite nonempty run directory: %s", directory);
end
if ~isfolder(directory)
    mkdir(directory);
end
end

function spec = callSpecLoader(loader, specPath)
try
    spec = loader(specPath);
catch exception
    if ~isArgumentValidationFailure(exception)
        rethrow(exception)
    end
    spec = loader(SpecPath=specPath);
end
if ~isstruct(spec) || ~isscalar(spec)
    error("StoreNet:InvalidExternalSpec", ...
        "The external dataset specification must be a scalar struct.");
end
end

function tf = isArgumentValidationFailure(exception)
identifier = string(exception.identifier);
message = string(exception.message);
tf = contains(identifier, "validation", IgnoreCase=true) || ...
    contains(identifier, "invalidType", IgnoreCase=true) || ...
    contains(identifier, "TooManyInputs", IgnoreCase=true) || ...
    contains(message, "unrecognized", IgnoreCase=true) || ...
    contains(message, "name-value", IgnoreCase=true);
end

function sourceFile = resolveSourceFile(requestedSourceFile, spec)
sourceFile = requestedSourceFile;
if strlength(sourceFile) == 0 && isfield(spec, "sourceFilePath")
    sourceFile = string(spec.sourceFilePath);
elseif strlength(sourceFile) == 0 && isfield(spec, "sourceFile")
    sourceFile = string(spec.sourceFile);
end
if strlength(sourceFile) > 0 && ~isAbsolutePath(sourceFile)
    sourceFile = string(fullfile(pwd, sourceFile));
end
end

function [selection, ranking] = validateSelection(selection, ranking)
if ~istable(selection) || ~istable(ranking)
    error("StoreNet:InvalidExternalSelection", ...
        "The day selector must return selection and ranking tables.");
end
requiredSelection = ["Month", "Day", "Score", "CandidateCount"];
requiredRanking = ["Month", "Day", "Score", "Selected"];
assertTableVariables(selection, requiredSelection, "selection");
assertTableVariables(ranking, requiredRanking, "ranking");
selection = sortrows(selection, "Month", "ascend");
expectedMonths = (1:12).';
if height(selection) ~= 12 || ...
        ~isequal(double(selection.Month(:)), expectedMonths) || ...
        ~isdatetime(selection.Day) || ...
        any(month(selection.Day) ~= double(selection.Month))
    error("StoreNet:InvalidExternalSelection", ...
        "Selection must contain exactly one datetime row for each calendar month.");
end
if any(~isfinite(double(selection.Score))) || ...
        any(double(selection.CandidateCount) < 1)
    error("StoreNet:InvalidExternalSelection", ...
        "Selection scores and candidate counts must be finite and valid.");
end
forbiddenTokens = ["saving", "bill", "dispatch", "solver", "outcome"];
rankingNames = lower(string(ranking.Properties.VariableNames));
if any(contains(rankingNames, forbiddenTokens), "all")
    error("StoreNet:OutcomeBasedSelection", ...
        "Ranking contains optimization-outcome columns and is not exogenous.");
end
ranking = sortrows(ranking, ["Month", "Score", "Day"], ...
    ["ascend", "ascend", "ascend"]);
selectedRankingDays = ranking.Day(logical(ranking.Selected));
if numel(selectedRankingDays) ~= 12 || ...
        ~isequal(sort(selectedRankingDays), sort(selection.Day))
    error("StoreNet:InvalidExternalSelection", ...
        "Ranking.Selected must identify the same twelve days as selection.");
end
end

function assertTableVariables(value, required, name)
missing = required(~ismember(required, string(value.Properties.VariableNames)));
if ~isempty(missing)
    error("StoreNet:InvalidExternalSelection", ...
        "%s is missing required variable(s): %s.", name, strjoin(missing, ", "));
end
end

function [config, overrides] = makeFixedPolicyConfig(spec, sourceFile)
if ~isfield(spec, "fixedPolicyTransfer") || ...
        ~isstruct(spec.fixedPolicyTransfer)
    error("StoreNet:InvalidExternalSpec", ...
        "The specification is missing fixedPolicyTransfer.");
end
policy = spec.fixedPolicyTransfer;
config = storenet_config(IntervalMinutes=30, QualityMode="release_literal");
config.releaseName = string(spec.datasetId);
config.releaseIsImmutable = true;
config.dataMode = "external-fixed-policy-transfer";
config.dataRoot = string(fileparts(sourceFile));
config.timestampBasis = stringFieldOrDefault(spec, "timestampBasis", ...
    "naive Sydney local wall clock; interval-end");
config.qualityModeRequested = "ausgrid_blank_only_no_imputation";
config.qualityMode = config.qualityModeRequested;
if isfield(spec, "analysisCustomerIds")
    config.homes = "AUS" + string(spec.analysisCustomerIds(:)).';
    config.nHomes = numel(config.homes);
    config.pvHomes = config.homes;
    config.pvHomeMask = true(size(config.homes));
end
overrides = struct;
overrides.batteryCapacityKWh = requiredPolicyValue( ...
    policy, "batteryCapacityKWhPerHome");
overrides.batteryPowerKW = requiredPolicyValue( ...
    policy, "batteryPowerKWPerHome");
directFields = ["etaPvAC", "etaPvDC", "etaBatteryCharge", ...
    "etaBatteryDischarge", "transferLossFraction", "nightPrice", ...
    "dayPrice", "dayStartHour", "dayEndHour", "feedInPrice"];
for fieldIndex = 1:numel(directFields)
    field = directFields(fieldIndex);
    overrides.(field) = requiredPolicyValue(policy, field);
end
overrideFields = string(fieldnames(overrides));
for fieldIndex = 1:numel(overrideFields)
    field = overrideFields(fieldIndex);
    config.(field) = overrides.(field);
end
if ~isAcPvSpec(spec) || abs(double(config.etaPvAC) - 1) > 1e-12
    error("StoreNet:InvalidExternalSpec", ...
        "Ausgrid GG must be declared inverter-AC and fixedPolicyTransfer.etaPvAC must equal 1.");
end
end

function value = requiredPolicyValue(policy, field)
if ~isfield(policy, field)
    error("StoreNet:InvalidExternalSpec", ...
        "fixedPolicyTransfer is missing '%s'.", field);
end
value = double(policy.(field));
if ~isscalar(value) || ~isfinite(value)
    error("StoreNet:InvalidExternalSpec", ...
        "fixedPolicyTransfer.%s must be a finite scalar.", field);
end
end

function tf = isAcPvSpec(spec)
tf = isfield(spec, "pvIsAC") && logical(spec.pvIsAC);
if ~tf && isfield(spec, "pvMeasurementBasis")
    tf = contains(string(spec.pvMeasurementBasis), "AC", IgnoreCase=true);
end
if ~tf && isfield(spec, "pvDefinition")
    tf = contains(string(spec.pvDefinition), "inverter-AC", IgnoreCase=true);
end
end

function tolerances = acceptanceTolerances(spec)
if ~isfield(spec, "acceptanceTolerances") || ...
        ~isstruct(spec.acceptanceTolerances)
    error("StoreNet:InvalidExternalSpec", ...
        "The specification is missing acceptanceTolerances.");
end
raw = spec.acceptanceTolerances;
fields = ["energyBalanceResidualKW", "terminalSocErrorKWh", ...
    "simultaneousChargeDischargeKW", "peakCapViolationKW"];
tolerances = struct;
for fieldIndex = 1:numel(fields)
    field = fields(fieldIndex);
    if ~isfield(raw, field)
        error("StoreNet:InvalidExternalSpec", ...
            "acceptanceTolerances is missing '%s'.", field);
    end
    value = double(raw.(field));
    if ~isscalar(value) || ~isfinite(value) || value < 0
        error("StoreNet:InvalidExternalSpec", ...
            "acceptanceTolerances.%s must be finite and nonnegative.", field);
    end
    tolerances.(field) = value;
end
end

function gate = makeGateTolerances(tolerances, config)
gate = struct;
gate.capKW = tolerances.peakCapViolationKW;
gate.energyBalanceResidualKW = tolerances.energyBalanceResidualKW;
gate.terminalSocErrorKWh = tolerances.terminalSocErrorKWh;
gate.simultaneousChargeDischargeKW = ...
    tolerances.simultaneousChargeDischargeKW;
gate.peakMonotonicKW = tolerances.peakCapViolationKW;
gate.billMonotonicEUR = 2 * (double(config.mipRelativeGap) + ...
    double(config.lexicographicTolerance));
gate.alpha = 1e-12;
gate.minimumExitFlag = 1;
end

function toleranceEUR = scaledBillMonotonicTolerance(frontier, config)
finiteBills = double(frontier.OptimizedBillEUR( ...
    isfinite(frontier.OptimizedBillEUR)));
billScaleEUR = 1;
if ~isempty(finiteBills)
    billScaleEUR = max(1, max(abs(finiteBills)));
end
toleranceEUR = 2 * (double(config.mipRelativeGap) + ...
    double(config.lexicographicTolerance)) * billScaleEUR;
end

function validateFrozenProtocol(spec, strategies, months, alphas)
if isfield(spec, "primaryStrategies") && ...
        ~isequal(string(spec.primaryStrategies(:)).', strategies)
    error("StoreNet:ProtocolMismatch", ...
        "The specification primary strategy order differs from the frozen runner.");
end
if isfield(spec, "frontierMonths") && ...
        ~isequal(double(spec.frontierMonths(:)).', months)
    error("StoreNet:ProtocolMismatch", ...
        "The specification frontier months differ from the frozen runner.");
end
if isfield(spec, "frontierCapFractionsFromMinimumToBaseline") && ...
        ~isequal(double(spec.frontierCapFractionsFromMinimumToBaseline(:)).', alphas)
    error("StoreNet:ProtocolMismatch", ...
        "The specification frontier alpha grid differs from the frozen runner.");
end
end

function data = normalizeCanonicalData(data)
if ~isfield(data, "time") && isfield(data, "timeEnd")
    data.time = data.timeEnd;
end
if ~isfield(data, "houseIds") && isfield(data, "homeNames")
    data.houseIds = data.homeNames;
end
required = ["time", "loadKW", "pvKW", "dtHours", "houseIds"];
missing = required(~isfield(data, cellstr(required)));
if ~isempty(missing)
    error("StoreNet:InvalidExperimentData", ...
        "Day provider output is missing field(s): %s.", strjoin(missing, ", "));
end
data.time = data.time(:);
end

function enforceProviderQuality(data, metadata, selectedDay)
qualityPassed = true;
if isfield(metadata, "qualityPassed")
    qualityPassed = logical(metadata.qualityPassed);
end
if isfield(data, "validForOptimization")
    qualityPassed = qualityPassed && logical(data.validForOptimization);
end
if ~qualityPassed
    reasons = providerRejectionReasons(metadata);
    error("StoreNet:QualityRejected", "Day %s is quality-rejected: %s.", ...
        string(selectedDay, "yyyy-MM-dd"), reasons);
end
end

function reasons = providerRejectionReasons(metadata)
reasons = "quality contract returned false";
if isfield(metadata, "rejectionReasons") && ...
        strlength(string(metadata.rejectionReasons)) > 0
    reasons = strjoin(string(metadata.rejectionReasons), "; ");
elseif isfield(metadata, "qualityReasons") && ...
        ~isempty(metadata.qualityReasons)
    reasons = strjoin(string(metadata.qualityReasons), "; ");
end
end

function peakKW = noBatteryBaselinePeak(data, config)
pvToHomeKW = min(double(data.loadKW), ...
    double(config.etaPvAC) .* double(data.pvKW));
baselineImportKW = sum(double(data.loadKW) - pvToHomeKW, 2);
peakKW = max(baselineImportKW);
if ~isscalar(peakKW) || ~isfinite(peakKW) || peakKW < 0
    error("StoreNet:InvalidBaselinePeak", ...
        "The ex-ante no-battery baseline peak is invalid.");
end
end

function [row, solution] = executeAndEvaluate(solver, data, config, strategy, ...
        tolerances, experiment, monthNumber, selectedDay, sequence, alpha, ...
        requestedCapKW, effectiveCapKW, p0KW, pminKW)
started = tic;
solution = struct;
try
    [solution, ~] = solver(data, config, strategy);
    metrics = evaluate_storenet(data, config, solution);
    wallTimeSeconds = toc(started);
    [accepted, acceptanceMessage] = evaluateAcceptance( ...
        metrics, solution, effectiveCapKW, tolerances);
    row = successfulMetricRow(experiment, monthNumber, selectedDay, ...
        sequence, strategy, alpha, requestedCapKW, effectiveCapKW, p0KW, ...
        pminKW, wallTimeSeconds, accepted, acceptanceMessage, metrics, solution);
catch exception
    row = failureMetricRow(experiment, monthNumber, selectedDay, sequence, ...
        strategy, alpha, requestedCapKW, effectiveCapKW, p0KW, pminKW, ...
        "failed", string(exception.identifier), string(exception.message));
    row.WallTimeSeconds = toc(started);
end
end

function [accepted, message] = evaluateAcceptance(metrics, solution, capKW, tolerances)
reasons = strings(0, 1);
if ~hasFiniteSolutionFlows(solution)
    reasons(end + 1, 1) = "nonfinite_solution_flow";
end
if ~isfinite(metrics.energyBalanceResidualKW) || ...
        abs(metrics.energyBalanceResidualKW) > ...
        tolerances.energyBalanceResidualKW
    reasons(end + 1, 1) = "energy_balance_residual";
end
if ~isfinite(metrics.terminalSocErrorKWh) || ...
        abs(metrics.terminalSocErrorKWh) > tolerances.terminalSocErrorKWh
    reasons(end + 1, 1) = "terminal_soc_error";
end
if ~isfinite(metrics.simultaneousChargeDischargeKW) || ...
        metrics.simultaneousChargeDischargeKW < 0 || ...
        metrics.simultaneousChargeDischargeKW > ...
        tolerances.simultaneousChargeDischargeKW
    reasons(end + 1, 1) = "simultaneous_charge_discharge";
end
if isfinite(capKW) && ...
        (~isfinite(metrics.peakImportKW) || ...
        metrics.peakImportKW > capKW + tolerances.peakCapViolationKW)
    reasons(end + 1, 1) = "peak_cap_violation";
end
exitFlags = solutionExitFlags(solution);
if isempty(exitFlags) || any(~isfinite(exitFlags)) || any(exitFlags <= 0)
    reasons(end + 1, 1) = "solver_exit_flag";
end
accepted = isempty(reasons);
message = strjoin(reasons, ";");
end

function tf = hasFiniteSolutionFlows(solution)
requiredFields = ["pvToHomeKW", "pvToBatteryKW", "pvToGridKW", ...
    "pvCurtailKW", "gridToHomeKW", "gridToBatteryKW", ...
    "batteryToHomeKW", "batteryToGridKW", "socKWh", ...
    "batteryChargeKW", "batteryDischargeKW", "aggregateImportKW"];
tf = isstruct(solution) && isscalar(solution) && ...
    all(isfield(solution, cellstr(requiredFields)));
if ~tf
    return
end
for fieldIndex = 1:numel(requiredFields)
    values = solution.(requiredFields(fieldIndex));
    tf = tf && isnumeric(values) && isreal(values) && ...
        ~isempty(values) && all(isfinite(values), "all");
end
end

function row = successfulMetricRow(experiment, monthNumber, selectedDay, ...
        sequence, strategy, alpha, requestedCapKW, effectiveCapKW, p0KW, ...
        pminKW, wallTimeSeconds, accepted, acceptanceMessage, metrics, solution)
row = emptyMetricRow();
row.Experiment = experiment;
row.Month = monthNumber;
row.Day = selectedDay;
row.Sequence = sequence;
row.Strategy = strategy;
row.Alpha = alpha;
row.RequestedCapKW = requestedCapKW;
row.EffectiveCapKW = effectiveCapKW;
row.P0KW = p0KW;
row.PminKW = pminKW;
row.WallTimeSeconds = wallTimeSeconds;
row.AcceptancePassed = accepted;
row.AcceptanceMessage = acceptanceMessage;
if accepted
    row.Status = "ok";
else
    row.Status = "acceptance_failed";
    row.ErrorIdentifier = "StoreNet:ExternalAcceptanceFailed";
    row.ErrorMessage = acceptanceMessage;
end
metricFields = ["baselineBillEUR", "optimizedBillEUR", "savingsEUR", ...
    "savingsPercent", "baselinePeakImportKW", "peakImportKW", ...
    "daytimePeakImportKW", "importSpreadKW", "totalGridImportKWh", ...
    "totalBatteryThroughputKWh", "totalCurtailedPvKWh", ...
    "totalSharedExportKWh", "energyBalanceResidualKW", ...
    "terminalSocErrorKWh", "simultaneousChargeDischargeKW"];
rowFields = ["BaselineBillEUR", "OptimizedBillEUR", "SavingsEUR", ...
    "SavingsPercent", "BaselinePeakImportKW", "PeakImportKW", ...
    "DaytimePeakImportKW", "ImportSpreadKW", "TotalGridImportKWh", ...
    "TotalBatteryThroughputKWh", "TotalCurtailedPvKWh", ...
    "TotalSharedExportKWh", "EnergyBalanceResidualKW", ...
    "TerminalSocErrorKWh", "SimultaneousChargeDischargeKW"];
for fieldIndex = 1:numel(metricFields)
    if isfield(metrics, metricFields(fieldIndex))
        row.(rowFields(fieldIndex)) = double(metrics.(metricFields(fieldIndex)));
    end
end
exitFlags = solutionExitFlags(solution);
row.ExitFlags = strjoin(string(exitFlags), ";");
if ~isempty(exitFlags)
    row.MinimumExitFlag = min(exitFlags);
end
end

function row = failureMetricRow(experiment, monthNumber, selectedDay, ...
        sequence, strategy, alpha, requestedCapKW, effectiveCapKW, p0KW, ...
        pminKW, status, identifier, message)
row = emptyMetricRow();
row.Experiment = experiment;
row.Month = monthNumber;
row.Day = selectedDay;
row.Sequence = sequence;
row.Strategy = strategy;
row.Alpha = alpha;
row.RequestedCapKW = requestedCapKW;
row.EffectiveCapKW = effectiveCapKW;
row.P0KW = p0KW;
row.PminKW = pminKW;
row.Status = status;
row.ErrorIdentifier = identifier;
row.ErrorMessage = message;
row.AcceptancePassed = false;
end

function row = emptyMetricRow()
row = struct;
row.Experiment = "";
row.Month = NaN;
row.Day = NaT;
row.Sequence = NaN;
row.Strategy = "";
row.Alpha = NaN;
row.RequestedCapKW = NaN;
row.EffectiveCapKW = NaN;
row.P0KW = NaN;
row.PminKW = NaN;
row.Status = "";
row.ErrorIdentifier = "";
row.ErrorMessage = "";
row.WallTimeSeconds = NaN;
row.AcceptancePassed = false;
row.AcceptanceMessage = "";
row.BaselineBillEUR = NaN;
row.OptimizedBillEUR = NaN;
row.SavingsEUR = NaN;
row.SavingsPercent = NaN;
row.BaselinePeakImportKW = NaN;
row.PeakImportKW = NaN;
row.DaytimePeakImportKW = NaN;
row.ImportSpreadKW = NaN;
row.TotalGridImportKWh = NaN;
row.TotalBatteryThroughputKWh = NaN;
row.TotalCurtailedPvKWh = NaN;
row.TotalSharedExportKWh = NaN;
row.EnergyBalanceResidualKW = NaN;
row.TerminalSocErrorKWh = NaN;
row.SimultaneousChargeDischargeKW = NaN;
row.ExitFlags = "";
row.MinimumExitFlag = NaN;
end

function flags = solutionExitFlags(solution)
flags = zeros(0, 1);
if isfield(solution, "exitFlags")
    flags = double(solution.exitFlags(:));
end
end

function rows = makeSkippedFrontierRows(monthNumber, selectedDay, ...
        alphas, p0KW, pminKW, referenceIdentifier, referenceMessage)
rows = repmat(emptyMetricRow(), numel(alphas), 1);
for alphaIndex = 1:numel(alphas)
    message = "Frontier point skipped because the PS/data reference failed: " + ...
        referenceIdentifier + ": " + referenceMessage;
    rows(alphaIndex) = failureMetricRow("frontier", monthNumber, ...
        selectedDay, alphaIndex + 1, "IMPROVED_PEAK_GUARD", ...
        alphas(alphaIndex), NaN, NaN, p0KW, pminKW, ...
        "skipped_reference_failure", "StoreNet:FrontierReferenceFailure", ...
        message);
end
end

function [primary, frontierReference, frontier] = writeExternalCheckpoint( ...
        runDirectory, primaryRows, frontierReferenceRows, frontierRows, isFinal)
primary = struct2table(primaryRows);
frontierReference = struct2table(frontierReferenceRows);
frontier = struct2table(frontierRows);
writeTableAtomic(primary, fullfile(runDirectory, "primary_metrics.csv"));
writeTableAtomic(frontierReference, ...
    fullfile(runDirectory, "frontier_reference_metrics.csv"));
writeTableAtomic(frontier, fullfile(runDirectory, "frontier_metrics.csv"));
checkpoint = table(height(primary), 36, height(frontierReference), 4, ...
    height(frontier), 20, logical(isFinal), ...
    VariableNames=["CompletedPrimaryRows", "ExpectedPrimaryRows", ...
    "CompletedFrontierReferenceRows", "ExpectedFrontierReferenceRows", ...
    "CompletedFrontierRows", "ExpectedFrontierRows", "IsFinal"]);
writeTableAtomic(checkpoint, fullfile(runDirectory, ...
    "external_validation_checkpoint.csv"));
end

function writeTableAtomic(value, path)
[directory, ~, extension] = fileparts(path);
temporaryPath = string(tempname(directory)) + extension;
cleaner = onCleanup(@() deleteIfPresent(temporaryPath));
writetable(value, temporaryPath);
movefile(temporaryPath, path, "f");
clear cleaner
end

function deleteIfPresent(path)
if isfile(path)
    delete(path);
end
end

function state = emptyDataState()
state = struct("status", "not_loaded", "identifier", "", "message", "");
end

function state = passedDataState()
state = struct("status", "ok", "identifier", "", "message", "");
end

function state = failedDataState(exception)
status = "data_failed";
identifier = string(exception.identifier);
if contains(identifier, ["Quality", "Incomplete", "Flagged"], IgnoreCase=true)
    status = "quality_rejected";
end
state = struct("status", status, "identifier", identifier, ...
    "message", string(exception.message));
end

function path = resolveReleaseManifest(spec, repositoryRoot)
if isfield(spec, "releaseManifestFullPath")
    path = string(spec.releaseManifestFullPath);
elseif isfield(spec, "releaseManifestPath")
    path = string(spec.releaseManifestPath);
    if ~isAbsolutePath(path)
        path = string(fullfile(repositoryRoot, path));
    end
else
    path = string(fullfile(repositoryRoot, "StoreNet", "data", ...
        "AUSGRID_MANIFEST.sha256"));
end
end

function tf = isAbsolutePath(path)
path = string(path);
tf = startsWith(path, filesep) || ...
    ~isempty(regexp(path, '^[A-Za-z]:[\\/]', 'once'));
end

function runInfo = makeRunInfo(options, spec, specPath, sourceFile, yearData, ...
        selection, config, overrides, tolerances, gateTolerances, ...
        primaryStrategies, frontierMonths, frontierAlphas, allowanceKW, ...
        primary, frontierReference, frontier, summary)
runInfo = struct;
runInfo.runType = "cross_environment_external_validation";
runInfo.runId = options.RunId;
runInfo.dataset = datasetProvenance(spec);
runInfo.specPath = specPath;
runInfo.specSha256 = fileSha256(specPath);
runInfo.sourceFile = sourceFile;
runInfo.source = structFieldOrDefault(yearData, "source", struct);
runInfo.verifySha256Requested = options.VerifySha256;
runInfo.pvMeasurementBasis = stringFieldOrDefault(spec, ...
    "pvMeasurementBasis", "inverter-AC");
runInfo.pvIsAC = logicalFieldOrDefault(spec, "pvIsAC", true);
runInfo.fixedPolicyTransfer = spec.fixedPolicyTransfer;
runInfo.normalizedConfigOverrides = overrides;
runInfo.configuration = config;
runInfo.acceptanceTolerances = tolerances;
runInfo.gateTolerances = gateTolerances;
runInfo.selectionUsesOptimizationOutcomes = false;
runInfo.selection = selection;
runInfo.primaryStrategyOrder = primaryStrategies;
runInfo.frontierMonths = frontierMonths;
runInfo.frontierAlphas = frontierAlphas;
runInfo.minimumPeakFeasibilityAllowanceKW = allowanceKW;
runInfo.solverHandle = string(func2str(options.Solver));
runInfo.independentEvaluator = "evaluate_storenet";
runInfo.figureVisible = options.FigureVisible;
runInfo.primaryStatuses = primary(:, ["Month", "Day", "Sequence", ...
    "Strategy", "Status", "ErrorIdentifier", "ErrorMessage", ...
    "WallTimeSeconds", "ExitFlags", "MinimumExitFlag", ...
    "AcceptancePassed"]);
runInfo.frontierReferenceStatuses = frontierReference(:, ["Month", "Day", ...
    "Sequence", "Strategy", "Status", "ErrorIdentifier", "ErrorMessage", ...
    "WallTimeSeconds", "ExitFlags", "MinimumExitFlag", ...
    "AcceptancePassed"]);
runInfo.frontierStatuses = frontier(:, ["Month", "Day", "Sequence", ...
    "Strategy", "Alpha", "RequestedCapKW", "EffectiveCapKW", ...
    "Status", "ErrorIdentifier", "ErrorMessage", "WallTimeSeconds", ...
    "ExitFlags", "MinimumExitFlag", "AcceptancePassed"]);
runInfo.summary = summary;
end

function provenance = datasetProvenance(spec)
provenance = struct;
fields = ["schemaVersion", "datasetId", "title", "datasetPaperDoi", ...
    "officialMetadataUrl", "archiveUrl", "archiveLicense", ...
    "sourceFileSha256", "energyUnit", "timestampBasis", ...
    "loadDefinition", "pvDefinition"];
for fieldIndex = 1:numel(fields)
    field = fields(fieldIndex);
    if isfield(spec, field)
        provenance.(field) = spec.(field);
    end
end
end

function value = structFieldOrDefault(source, field, defaultValue)
if isstruct(source) && isfield(source, field)
    value = source.(field);
else
    value = defaultValue;
end
end

function value = stringFieldOrDefault(source, field, defaultValue)
value = string(structFieldOrDefault(source, field, defaultValue));
end

function value = logicalFieldOrDefault(source, field, defaultValue)
value = logical(structFieldOrDefault(source, field, defaultValue));
end

function value = fileSha256(path)
value = "unavailable";
if isfile(path)
    value = storenetio.hashFile(path);
end
end

function writeJson(path, value)
fileId = fopen(path, "wt", "n", "UTF-8");
if fileId < 0
    error("StoreNet:ExternalSummaryWriteFailed", ...
        "Unable to open summary for writing: %s", path);
end
cleaner = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s\n", jsonencode(value, PrettyPrint=true));
clear cleaner
end
