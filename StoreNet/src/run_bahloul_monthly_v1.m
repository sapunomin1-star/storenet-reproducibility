function run = run_bahloul_monthly_v1(options)
%RUN_BAHLOUL_MONTHLY_V1 Run the frozen B2022-IR-v1 monthly experiment.
%   In solve mode, each requested day is loaded exactly once at hourly
%   resolution. Every primary-scenario strategy result is retained,
%   including data-quality, case-preparation, solver, and artifact failures.
%   ExistingDailyMetricsPath and ExistingDailyManifestPath select an
%   offline-reuse branch that maps saved primary daily rows into the same
%   output schema and does not invoke the solver.

arguments
    options.Dates datetime = NaT(0, 1)
    options.DataRoot (1, 1) string = ""
    options.OutputRoot (1, 1) string = ""
    options.RunId (1, 1) string = ""
    options.QualityMode (1, 1) string {mustBeMember(options.QualityMode, ...
        ["release_literal", "short_gap_only", "exclude_flagged_pv"])} = ...
        "exclude_flagged_pv"
    options.H4DiagnosticsPath (1, 1) string = ""
    options.Provenance (1, 1) struct = struct
    options.DataProvider (1, 1) function_handle = @load_storenet_day
    options.Solver (1, 1) function_handle = @solve_storenet
    options.FigureVisible (1, 1) logical = false
    options.PersistSolutions (1, 1) logical = true
    options.ExistingDailyMetricsPath (1, 1) string = ""
    options.ExistingDailyManifestPath (1, 1) string = ""
end

sourceFolder = fileparts(mfilename("fullpath"));
reuseExistingDaily = existingDailyReuseRequested(options);
if isempty(options.Dates)
    options.Dates = defaultMonthlyDates();
end
sampleDates = unique(dateshift(options.Dates(:), "start", "day"), "sorted");
if isempty(sampleDates) || any(isnat(sampleDates))
    error("StoreNet:NoBahloulMonthlyDates", ...
        "Dates must contain at least one finite calendar day.");
end
if any(year(sampleDates) ~= 2020)
    error("StoreNet:InvalidBahloulMonthlyPeriod", ...
        "B2022-IR-v1 monthly rows are restricted to the public 2020 release.");
end
if strlength(options.OutputRoot) == 0
    options.OutputRoot = string(fullfile(sourceFolder, "..", "results"));
end
if strlength(options.RunId) == 0
    options.RunId = "bahloul_monthly_v1_" + ...
        string(datetime("now"), "yyyyMMdd_HHmmss_SSS");
end

offlineDaily = table;
if reuseExistingDaily
    validateExistingDailyQualityMode( ...
        options.ExistingDailyManifestPath, options.QualityMode);
    [~, offlineDaily] = aggregate_bahloul_monthly_csv( ...
        options.ExistingDailyMetricsPath, ...
        ManifestPath=options.ExistingDailyManifestPath, ...
        DataRoot=options.DataRoot, DataProvider=options.DataProvider);
    validateExistingDailyDates(offlineDaily, sampleDates);
end

runDirectory = prepareRunDirectory(options.OutputRoot, options.RunId);
dailyMetricsPath = string(fullfile(runDirectory, "daily_metrics.csv"));
monthlyMetricsPath = string(fullfile(runDirectory, "monthly_metrics.csv"));
monthlyProfilesPath = string(fullfile(runDirectory, ...
    "monthly_mean_profiles.csv"));
figurePath = string(fullfile(runDirectory, "figure6_proxy.png"));

baseConfig = storenet_config(IntervalMinutes=60, ...
    DataRoot=options.DataRoot, QualityMode=options.QualityMode);
scenarios = primaryMonthlyScenario();
strategies = ["SH_BM", "VPP_BM", "PS", "PSDT", "LL"];
dailyRows = repmat(emptyDailyRow(), 0, 1);
profileRows = repmat(emptyProfileRow(), 0, 1);

if reuseExistingDaily
    dailyRows = mapExistingDailyRows(offlineDaily, scenarios, strategies, ...
        options.QualityMode);
else
for dateIndex = 1:numel(sampleDates)
    calendarDay = sampleDates(dateIndex);
    try
        [releaseData, dataMeta] = callDataProvider(options.DataProvider, ...
            calendarDay, options.DataRoot, options.QualityMode);
        if metadataRejected(dataMeta, releaseData)
            message = qualityRejectionMessage(calendarDay, dataMeta);
            dailyRows = appendRejectedDay(dailyRows, calendarDay, ...
                scenarios, strategies, options.QualityMode, ...
                "quality_rejected", "StoreNet:QualityRejected", message);
            writeDailyCheckpoint(dailyRows, dailyMetricsPath);
            continue
        end
    catch exception
        dailyRows = appendRejectedDay(dailyRows, calendarDay, ...
            scenarios, strategies, options.QualityMode, ...
            "data_failed", string(exception.identifier), ...
            string(exception.message));
        writeDailyCheckpoint(dailyRows, dailyMetricsPath);
        continue
    end

    for scenarioIndex = 1:height(scenarios)
        scenario = scenarios(scenarioIndex, :);
        try
            [caseData, caseConfig, caseMeta] = prepare_bahloul_case( ...
                releaseData, baseConfig, CohortId=scenario.CohortId, ...
                PvBoundaryId=scenario.PvBoundaryId, ...
                TransferLossFraction=scenario.TransferLossFraction, ...
                H4DiagnosticsPath=options.H4DiagnosticsPath, ...
                DataMeta=dataMeta, Provenance=options.Provenance);
            [caseConfig, caseMeta] = annotateCase(caseConfig, caseMeta, ...
                scenario, options.RunId);
        catch exception
            dailyRows = appendScenarioFailures(dailyRows, calendarDay, ...
                scenario, strategies, options.QualityMode, "case_rejected", ...
                string(exception.identifier), string(exception.message));
            writeDailyCheckpoint(dailyRows, dailyMetricsPath);
            continue
        end

        originalLoadKW = sum(double(caseData.loadKW), 2);
        profileRows = appendProfileRows(profileRows, calendarDay, ...
            scenario, caseMeta, "ORIGINAL_LOAD", "baseline", ...
            caseData.time(:), originalLoadKW, originalLoadKW);

        for strategyIndex = 1:numel(strategies)
            strategy = strategies(strategyIndex);
            started = tic;
            try
                [solution, metrics] = options.Solver( ...
                    caseData, caseConfig, strategy);
                aggregateImportKW = validateSolutionProfile( ...
                    solution, caseData.time);
                artifactDirectory = "";
                artifacts = struct;
                if options.PersistSolutions
                    artifactDirectory = caseArtifactDirectory(runDirectory, ...
                        calendarDay, scenario.ScenarioId, strategy);
                    artifactMeta = caseMeta;
                    artifactMeta.strategy = strategy;
                    artifactMeta.caseId = monthlyCaseId(calendarDay, ...
                        scenario.ScenarioId, strategy);
                    artifactMeta.dateOrPeriod = calendarDay;
                    artifacts = write_bahloul_case_artifacts( ...
                        artifactDirectory, ...
                        caseData, caseConfig, artifactMeta, solution, metrics);
                end
                row = optimizedDailyRow( ...
                    calendarDay, scenario, caseMeta, strategy, "ok", ...
                    "", "", toc(started), artifactDirectory, ...
                    metrics, solution);
                row = addModelArtifactEvidence(row, artifacts);
                dailyRows(end + 1, 1) = row; %#ok<AGROW>
                profileRows = appendProfileRows(profileRows, calendarDay, ...
                    scenario, caseMeta, strategy, "optimized", ...
                    caseData.time(:), originalLoadKW, aggregateImportKW);
            catch exception
                dailyRows(end + 1, 1) = optimizedDailyRow( ...
                    calendarDay, scenario, caseMeta, strategy, "failed", ...
                    string(exception.identifier), string(exception.message), ...
                    toc(started), "", struct, struct); %#ok<AGROW>
            end
            writeDailyCheckpoint(dailyRows, dailyMetricsPath);
        end

    end
end
end

dailyMetrics = struct2table(dailyRows);
writetable(dailyMetrics, dailyMetricsPath);
[monthlyMeanProfiles, rawProfiles] = aggregateMonthlyProfiles(profileRows);
monthlyMetrics = aggregateMonthlyMetrics(dailyMetrics, monthlyMeanProfiles);
writetable(monthlyMetrics, monthlyMetricsPath);
writetable(monthlyMeanProfiles, monthlyProfilesPath);
writeFigure6Proxy(figurePath, monthlyMetrics, monthlyMeanProfiles, ...
    scenarios, strategies, options.FigureVisible);

run = struct;
run.runType = "B2022-IR-v1_monthly";
run.runId = options.RunId;
run.runDirectory = runDirectory;
run.dailyMetricsPath = dailyMetricsPath;
run.monthlyMetricsPath = monthlyMetricsPath;
run.monthlyProfilesPath = monthlyProfilesPath;
run.figurePath = figurePath;
run.sampleDates = sampleDates;
run.dailyMetrics = dailyMetrics;
run.monthlyMetrics = monthlyMetrics;
run.monthlyMeanProfiles = monthlyMeanProfiles;
run.rawProfiles = rawProfiles;
run.scenarios = scenarios;
run.strategies = strategies;
run.configuration = baseConfig;
run.qualityMode = options.QualityMode;
run.persistSolutions = options.PersistSolutions && ~reuseExistingDaily;
run.reusedExistingDailyMetrics = reuseExistingDaily;
run.existingDailyMetricsPath = options.ExistingDailyMetricsPath;
run.existingDailyManifestPath = options.ExistingDailyManifestPath;
end

function dates = defaultMonthlyDates()
monthStarts = datetime(2020, (1:12).', 1);
sampleDays = [1, 2, 15, 16];
dates = NaT(numel(monthStarts) * numel(sampleDays), 1);
rowIndex = 0;
for monthIndex = 1:numel(monthStarts)
    for dayIndex = 1:numel(sampleDays)
        rowIndex = rowIndex + 1;
        dates(rowIndex) = datetime(2020, month(monthStarts(monthIndex)), ...
            sampleDays(dayIndex));
    end
end
end

function scenario = primaryMonthlyScenario()
scenarios = bahloul_scenarios("CORE_SIX");
scenario = scenarios(scenarios.ScenarioId == "DC_XI007_H20", :);
if height(scenario) ~= 1
    error("StoreNet:InvalidPrimaryScenario", ...
        "Expected exactly one DC_XI007_H20 monthly scenario.");
end
end

function reuse = existingDailyReuseRequested(options)
metricsProvided = strlength(options.ExistingDailyMetricsPath) > 0;
manifestProvided = strlength(options.ExistingDailyManifestPath) > 0;
if xor(metricsProvided, manifestProvided)
    error("StoreNet:IncompleteExistingDailySource", ...
        "ExistingDailyMetricsPath and ExistingDailyManifestPath must " + ...
        "both be provided for offline reuse.");
end
reuse = metricsProvided;
end

function validateExistingDailyQualityMode(manifestPath, expectedQualityMode)
if ~isfile(manifestPath)
    error("StoreNet:ExistingDailyManifestNotFound", ...
        "Existing daily manifest does not exist: %s", manifestPath);
end
try
    manifest = jsondecode(fileread(manifestPath));
catch exception
    error("StoreNet:InvalidExistingDailyManifest", ...
        "Cannot read existing daily manifest %s (%s): %s", ...
        manifestPath, exception.identifier, exception.message);
end
if ~isstruct(manifest) || ~isfield(manifest, "experiment") || ...
        ~isstruct(manifest.experiment) || ...
        ~isfield(manifest.experiment, "qualityMode")
    error("StoreNet:InvalidExistingDailyManifest", ...
        "Existing daily manifest has no experiment.qualityMode: %s", ...
        manifestPath);
end
sourceQualityMode = strip(string(manifest.experiment.qualityMode));
if ~isscalar(sourceQualityMode) || ismissing(sourceQualityMode) || ...
        strlength(sourceQualityMode) == 0
    error("StoreNet:InvalidExistingDailyManifest", ...
        "Existing daily manifest qualityMode must be a nonempty scalar: %s", ...
        manifestPath);
end
if sourceQualityMode ~= expectedQualityMode
    error("StoreNet:ExistingDailyQualityModeMismatch", ...
        "Runner QualityMode '%s' does not match existing daily manifest " + ...
        "experiment.qualityMode '%s'.", ...
        expectedQualityMode, sourceQualityMode);
end
end

function validateExistingDailyDates(daily, expectedDates)
sourceDates = unique(daily.Day, "sorted");
if numel(sourceDates) ~= numel(expectedDates) || ...
        any(sourceDates ~= expectedDates)
    error("StoreNet:ExistingDailyDateMismatch", ...
        "Existing daily CSV dates must exactly match Dates " + ...
        "(%d source dates, %d requested dates).", ...
        numel(sourceDates), numel(expectedDates));
end
end

function rows = mapExistingDailyRows(daily, scenarios, strategies, qualityMode)
validateExistingDailyStrategyGrid(daily, strategies);
scenario = scenarios(1, :);
rows = repmat(emptyDailyRow(), height(daily), 1);
for rowIndex = 1:height(daily)
    calendarDay = daily.Day(rowIndex);
    meta = expectedCaseMeta(calendarDay, scenario, qualityMode);
    row = baseDailyRow(calendarDay, scenario, meta, ...
        daily.Strategy(rowIndex), "optimized", daily.Status(rowIndex), ...
        offlineTextValue(daily, "ErrorIdentifier", rowIndex, ""), ...
        offlineTextValue(daily, "ErrorMessage", rowIndex, ""), ...
        offlineNumericValue(daily, "WallTimeSeconds", rowIndex, NaN), "");
    row = copyExistingDailyMetrics(row, daily, rowIndex);
    rows(rowIndex, 1) = row;
end
end

function validateExistingDailyStrategyGrid(daily, strategies)
expectedStrategies = sort(strategies(:));
sourceStrategies = sort(unique(daily.Strategy));
if numel(sourceStrategies) ~= numel(expectedStrategies) || ...
        any(sourceStrategies ~= expectedStrategies)
    error("StoreNet:InvalidExistingDailyStrategyGrid", ...
        "Existing daily CSV must contain exactly the five frozen strategies.");
end
sourceDates = unique(daily.Day, "sorted");
for dateIndex = 1:numel(sourceDates)
    selected = daily.Day == sourceDates(dateIndex);
    dayStrategies = sort(daily.Strategy(selected));
    if numel(dayStrategies) ~= numel(expectedStrategies) || ...
            any(dayStrategies ~= expectedStrategies)
        error("StoreNet:InvalidExistingDailyStrategyGrid", ...
            "Existing daily CSV does not contain one complete strategy block for %s.", ...
            string(sourceDates(dateIndex), "yyyy-MM-dd"));
    end
end
end

function row = copyExistingDailyMetrics(row, daily, rowIndex)
metricNames = [ ...
    "PaperLoadOnlyBaselineBillEUR", "PaperLoadOnlySavingsEUR", ...
    "PaperLoadOnlySavingsPercent", "PaperLoadOnlyPeakKW", ...
    "PaperSavingsPercentDenominatorIsZero", ...
    "PaperLoadOnlyDaytimePeakKW", ...
    "PvSelfNoBatteryBaselineBillEUR", "PvSelfNoBatterySavingsEUR", ...
    "PvSelfNoBatterySavingsPercent", "PvSelfNoBatteryPeakKW", ...
    "EngineeringSavingsPercentDenominatorIsZero", ...
    "PvSelfNoBatteryDaytimePeakKW", "OptimizedBillEUR", ...
    "OutcomePeakImportKW", "OutcomeDaytimePeakImportKW", ...
    "TotalGridImportKWh", "TotalBatteryThroughputKWh", ...
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
    "MaximumLexicographicViolation", "MinimumExitFlag", ...
    "MaximumRelativeGap", "ObjectiveStageCount"];
variables = string(daily.Properties.VariableNames);
for metricName = metricNames(ismember(metricNames, variables))
    row.(metricName) = offlineNumericValue( ...
        daily, metricName, rowIndex, NaN);
end
if ~ismember("PvSelfNoBatteryPeakKW", variables) && ...
        ismember("BaselinePeakImportKW", variables)
    row.PvSelfNoBatteryPeakKW = offlineNumericValue( ...
        daily, "BaselinePeakImportKW", rowIndex, NaN);
end
if ~ismember("OutcomeDaytimePeakImportKW", variables) && ...
        ismember("DaytimePeakImportKW", variables)
    row.OutcomeDaytimePeakImportKW = offlineNumericValue( ...
        daily, "DaytimePeakImportKW", rowIndex, NaN);
end
if ~ismember("PaperSavingsPercentDenominatorIsZero", variables)
    row.PaperSavingsPercentDenominatorIsZero = ...
        denominatorFlag(row.PaperLoadOnlyBaselineBillEUR);
end
if ~ismember("EngineeringSavingsPercentDenominatorIsZero", variables)
    row.EngineeringSavingsPercentDenominatorIsZero = ...
        denominatorFlag(row.PvSelfNoBatteryBaselineBillEUR);
end
end

function value = offlineTextValue(daily, name, rowIndex, defaultValue)
variables = string(daily.Properties.VariableNames);
if ~ismember(name, variables)
    value = defaultValue;
    return
end
value = string(daily.(name)(rowIndex));
if ismissing(value)
    value = defaultValue;
end
end

function value = offlineNumericValue(daily, name, rowIndex, defaultValue)
variables = string(daily.Properties.VariableNames);
if ~ismember(name, variables)
    value = defaultValue;
    return
end
column = daily.(name);
if ~isnumeric(column) && ~islogical(column)
    error("StoreNet:InvalidExistingDailyMetric", ...
        "Existing daily column %s must be numeric.", name);
end
value = double(column(rowIndex));
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
if isfolder(directory) && hasMaterialEntries(directory)
    error("StoreNet:RunDirectoryExists", ...
        "Refusing to overwrite nonempty run directory: %s", directory);
end
if ~isfolder(directory)
    mkdir(directory);
end
end

function tf = hasMaterialEntries(directory)
entries = dir(directory);
names = string({entries.name});
tf = any(~ismember(names, [".", ".."]) & ~startsWith(names, ".nfs"));
end

function [data, meta] = callDataProvider(provider, calendarDay, dataRoot, ...
        qualityMode)
[data, meta] = provider(calendarDay, DataRoot=dataRoot, ...
    IntervalMinutes=60, QualityMode=qualityMode);
end

function tf = metadataRejected(meta, data)
tf = false;
if isstruct(meta) && isfield(meta, "qualityPassed")
    tf = ~logical(meta.qualityPassed);
elseif isstruct(data) && isfield(data, "validForOptimization")
    tf = ~logical(data.validForOptimization);
end
end

function message = qualityRejectionMessage(calendarDay, meta)
reasons = "quality contract returned false";
if isstruct(meta) && isfield(meta, "qualityReasons") && ...
        ~isempty(meta.qualityReasons)
    reasons = strjoin(string(meta.qualityReasons), "; ");
end
message = "Day " + string(calendarDay, "yyyy-MM-dd") + ...
    " was rejected: " + reasons;
end

function [config, meta] = annotateCase(config, meta, scenario, runId)
config.experimentId = "B2022_MONTHLY_V1";
config.scenarioId = scenario.ScenarioId;
config.pairId = scenario.PairId;
config.sensitivityRole = scenario.SensitivityRole;
config.capacityRatio = 1;
config.powerRatio = 1;
meta.experimentId = "B2022_MONTHLY_V1";
meta.scenarioId = scenario.ScenarioId;
meta.pairId = scenario.PairId;
meta.sensitivityRole = scenario.SensitivityRole;
meta.isPrimary = scenario.IsPrimary;
meta.runId = runId;
meta.qualityMode = string(config.qualityMode);
meta.capacityRatio = 1;
meta.powerRatio = 1;
meta.dateOrPeriod = meta.day;
end

function path = caseArtifactDirectory(runDirectory, calendarDay, scenarioId, ...
        strategy)
path = string(fullfile(runDirectory, "cases", ...
    string(calendarDay, "yyyy-MM-dd"), scenarioId, strategy));
end

function aggregateImportKW = validateSolutionProfile(solution, timeEnd)
if ~isstruct(solution) || ~isfield(solution, "aggregateImportKW")
    error("StoreNet:MissingAggregateImportProfile", ...
        "The solver result does not contain aggregateImportKW.");
end
aggregateImportKW = double(solution.aggregateImportKW(:));
if numel(aggregateImportKW) ~= numel(timeEnd) || ...
        any(~isfinite(aggregateImportKW))
    error("StoreNet:InvalidAggregateImportProfile", ...
        "aggregateImportKW must be finite and aligned with the case time grid.");
end
end

function rows = appendRejectedDay(rows, calendarDay, scenarios, strategies, ...
        qualityMode, status, identifier, message)
for scenarioIndex = 1:height(scenarios)
    scenario = scenarios(scenarioIndex, :);
    rows = appendScenarioFailures(rows, calendarDay, scenario, strategies, ...
        qualityMode, status, identifier, message);
end
end

function rows = appendScenarioFailures(rows, calendarDay, scenario, ...
        strategies, qualityMode, status, identifier, message)
meta = expectedCaseMeta(calendarDay, scenario, qualityMode);
for strategyIndex = 1:numel(strategies)
    rows(end + 1, 1) = optimizedDailyRow(calendarDay, scenario, meta, ...
        strategies(strategyIndex), status, identifier, message, 0, "", ...
        struct, struct); %#ok<AGROW>
end
end

function meta = expectedCaseMeta(calendarDay, scenario, qualityMode)
meta = struct;
meta.day = calendarDay;
meta.dateOrPeriod = calendarDay;
meta.experimentId = "B2022_MONTHLY_V1";
meta.qualityMode = qualityMode;
meta.capacityRatio = 1;
meta.powerRatio = 1;
meta.cohortId = scenario.CohortId;
meta.houseCount = 20;
meta.pvHomeCount = 10;
if scenario.CohortId == "H19_EXCL_H4_PV9"
    meta.houseCount = 19;
    meta.pvHomeCount = 9;
end
meta.h4MaskAffected = NaN;
meta.h4AlignmentCategory = "unavailable";
end

function row = optimizedDailyRow(calendarDay, scenario, meta, strategy, ...
        status, identifier, message, wallTimeSeconds, artifactDirectory, ...
        metrics, solution)
row = baseDailyRow(calendarDay, scenario, meta, strategy, "optimized", ...
    status, identifier, message, wallTimeSeconds, artifactDirectory);
if status ~= "ok"
    return
end
row.PaperLoadOnlyBaselineBillEUR = nestedMetric(metrics, ...
    "PaperLoadOnlyBaseline", "billEUR");
row.PaperLoadOnlySavingsEUR = nestedMetric(metrics, ...
    "PaperLoadOnlyBaseline", "savingsEUR");
row.PaperLoadOnlySavingsPercent = nestedMetric(metrics, ...
    "PaperLoadOnlyBaseline", "savingsPercent");
row.PaperSavingsPercentDenominatorIsZero = nestedMetric(metrics, ...
    "PaperLoadOnlyBaseline", "savingsPercentDenominatorIsZero");
row.PaperLoadOnlyPeakKW = nestedMetric(metrics, ...
    "PaperLoadOnlyBaseline", "peakImportKW");
row.PaperLoadOnlyDaytimePeakKW = nestedMetric(metrics, ...
    "PaperLoadOnlyBaseline", "daytimePeakImportKW");
row.PvSelfNoBatteryBaselineBillEUR = nestedMetric(metrics, ...
    "PvSelfNoBatteryBaseline", "billEUR");
row.PvSelfNoBatterySavingsEUR = nestedMetric(metrics, ...
    "PvSelfNoBatteryBaseline", "savingsEUR");
row.PvSelfNoBatterySavingsPercent = nestedMetric(metrics, ...
    "PvSelfNoBatteryBaseline", "savingsPercent");
row.EngineeringSavingsPercentDenominatorIsZero = nestedMetric(metrics, ...
    "PvSelfNoBatteryBaseline", "savingsPercentDenominatorIsZero");
row.PvSelfNoBatteryPeakKW = nestedMetric(metrics, ...
    "PvSelfNoBatteryBaseline", "peakImportKW");
row.PvSelfNoBatteryDaytimePeakKW = nestedMetric(metrics, ...
    "PvSelfNoBatteryBaseline", "daytimePeakImportKW");
row.OptimizedBillEUR = scalarMetric(metrics, "optimizedBillEUR");
row.OutcomePeakImportKW = scalarMetric(metrics, "peakImportKW");
row.OutcomeDaytimePeakImportKW = scalarMetric(metrics, ...
    "daytimePeakImportKW");
row.TotalGridImportKWh = scalarMetric(metrics, "totalGridImportKWh");
row.TotalBatteryThroughputKWh = scalarMetric(metrics, ...
    "totalBatteryThroughputKWh");
row.TotalCurtailedPvKWh = scalarMetric(metrics, "totalCurtailedPvKWh");
row.TotalSharedExportKWh = scalarMetric(metrics, "totalSharedExportKWh");
row.EnergyBalanceResidualKW = scalarMetric(metrics, ...
    "energyBalanceResidualKW");
row.PvAllocationResidualKW = scalarMetric(metrics, ...
    "pvAllocationResidualKW");
row.HomeBalanceResidualKW = scalarMetric(metrics, ...
    "homeBalanceResidualKW");
row.BatteryDynamicsResidualKW = scalarMetric(metrics, ...
    "batteryDynamicsResidualKW");
row.AggregateImportResidualKW = scalarMetric(metrics, ...
    "aggregateImportResidualKW");
row.ChargeConversionResidualKW = scalarMetric(metrics, ...
    "chargeConversionResidualKW");
row.DischargeConversionResidualKW = scalarMetric(metrics, ...
    "dischargeConversionResidualKW");
row.InitialSocErrorKWh = scalarMetric(metrics, "initialSocErrorKWh");
row.TerminalSocErrorKWh = scalarMetric(metrics, "terminalSocErrorKWh");
row.SocBoundViolationKWh = scalarMetric(metrics, "socBoundViolationKWh");
row.ChargePowerViolationKW = scalarMetric(metrics, ...
    "chargePowerViolationKW");
row.DischargePowerViolationKW = scalarMetric(metrics, ...
    "dischargePowerViolationKW");
row.AggregateImportNonnegativeViolationKW = scalarMetric(metrics, ...
    "aggregateImportNonnegativeViolationKW");
row.SimultaneousChargeDischargeKW = scalarMetric(metrics, ...
    "simultaneousChargeDischargeKW");
row.SimultaneousChargeDischargeCount = scalarMetric(metrics, ...
    "simultaneousChargeDischargeCount");
row.MaximumLexicographicViolation = scalarMetric(metrics, ...
    "maximumLexicographicViolation");
row.MinimumExitFlag = minimumExitFlag(solution);
row.MaximumRelativeGap = maximumRelativeGap(solution);
row.ObjectiveStageCount = objectiveStageCount(solution);
end

function row = baseDailyRow(calendarDay, scenario, meta, strategy, ...
        recordType, status, identifier, message, wallTimeSeconds, ...
        artifactDirectory)
row = emptyDailyRow();
row.Day = calendarDay;
row.YearMonth = dateshift(calendarDay, "start", "month");
row.ExperimentId = "B2022_MONTHLY_V1";
row.CaseId = monthlyCaseId(calendarDay, scenario.ScenarioId, strategy);
row.ScenarioId = scenario.ScenarioId;
row.PairId = scenario.PairId;
row.CohortId = scenario.CohortId;
row.SensitivityRole = scenario.SensitivityRole;
row.IsPrimary = logical(scenario.IsPrimary);
row.PvBoundaryId = scenario.PvBoundaryId;
row.TransferLossFraction = double(scenario.TransferLossFraction);
row.QualityMode = string(meta.qualityMode);
row.CapacityRatio = 1;
row.PowerRatio = 1;
row.HouseCount = double(meta.houseCount);
row.PvHomeCount = double(meta.pvHomeCount);
row.H4MaskAffected = double(meta.h4MaskAffected);
row.H4AlignmentCategory = string(meta.h4AlignmentCategory);
row.Strategy = strategy;
row.RecordType = recordType;
row.Status = status;
row.ErrorIdentifier = identifier;
row.ErrorMessage = message;
row.WallTimeSeconds = wallTimeSeconds;
row.ArtifactDirectory = artifactDirectory;
end

function row = addModelArtifactEvidence(row, artifacts)
if isempty(fieldnames(artifacts))
    return
end
row.InputsPath = artifacts.inputsPath;
row.InputsSha256 = artifacts.inputsSha256;
row.SolutionPath = artifacts.solutionPath;
row.SolutionSha256 = artifacts.solutionSha256;
row.StagesPath = artifacts.stagesPath;
row.MetricsPath = artifacts.metricsPath;
end

function row = emptyDailyRow()
row = struct( ...
    Day=NaT, YearMonth=NaT, ExperimentId="", CaseId="", ...
    ScenarioId="", PairId="", CohortId="", ...
    SensitivityRole="", IsPrimary=false, PvBoundaryId="", ...
    TransferLossFraction=NaN, QualityMode="", CapacityRatio=NaN, ...
    PowerRatio=NaN, HouseCount=NaN, PvHomeCount=NaN, ...
    H4MaskAffected=NaN, H4AlignmentCategory="", Strategy="", ...
    RecordType="", Status="", ErrorIdentifier="", ErrorMessage="", ...
    WallTimeSeconds=NaN, ArtifactDirectory="", ...
    PaperLoadOnlyBaselineBillEUR=NaN, PaperLoadOnlySavingsEUR=NaN, ...
    PaperLoadOnlySavingsPercent=NaN, PaperLoadOnlyPeakKW=NaN, ...
    PaperSavingsPercentDenominatorIsZero=NaN, ...
    PaperLoadOnlyDaytimePeakKW=NaN, ...
    PvSelfNoBatteryBaselineBillEUR=NaN, ...
    PvSelfNoBatterySavingsEUR=NaN, ...
    PvSelfNoBatterySavingsPercent=NaN, PvSelfNoBatteryPeakKW=NaN, ...
    EngineeringSavingsPercentDenominatorIsZero=NaN, ...
    PvSelfNoBatteryDaytimePeakKW=NaN, ...
    ObservedReleasePvSelfNoBatteryBaselineBillEUR=NaN, ...
    ObservedReleaseEngineeringSavingsEUR=NaN, ...
    ObservedReleaseEngineeringSavingsPercent=NaN, ...
    ObservedReleaseEngineeringSavingsPercentDenominatorIsZero=NaN, ...
    OptimizedBillEUR=NaN, ObservedBillEUR=NaN, OutcomePeakImportKW=NaN, ...
    OutcomeDaytimePeakImportKW=NaN, TotalGridImportKWh=NaN, ...
    TotalBatteryThroughputKWh=NaN, TotalCurtailedPvKWh=NaN, ...
    TotalSharedExportKWh=NaN, EnergyBalanceResidualKW=NaN, ...
    PvAllocationResidualKW=NaN, HomeBalanceResidualKW=NaN, ...
    BatteryDynamicsResidualKW=NaN, AggregateImportResidualKW=NaN, ...
    ChargeConversionResidualKW=NaN, ...
    DischargeConversionResidualKW=NaN, InitialSocErrorKWh=NaN, ...
    TerminalSocErrorKWh=NaN, SocBoundViolationKWh=NaN, ...
    ChargePowerViolationKW=NaN, DischargePowerViolationKW=NaN, ...
    AggregateImportNonnegativeViolationKW=NaN, ...
    SimultaneousChargeDischargeKW=NaN, ...
    SimultaneousChargeDischargeCount=NaN, ...
    MaximumLexicographicViolation=NaN, ...
    MinimumExitFlag=NaN, MaximumRelativeGap=NaN, ...
    ObjectiveStageCount=NaN, InputsPath="", InputsSha256="", ...
    SolutionPath="", SolutionSha256="", StagesPath="", ...
    MetricsPath="", MetricsSha256="", ObservedProfilesPath="", ...
    ObservedProfilesSha256="");
end

function value = monthlyCaseId(calendarDay, scenarioId, strategy)
value = "MONTHLY_" + string(calendarDay, "yyyyMMdd") + "_" + ...
    string(scenarioId) + "_" + string(strategy);
end

function value = nestedMetric(metrics, group, field)
value = NaN;
if isstruct(metrics) && isfield(metrics, group)
    nested = metrics.(group);
    if isstruct(nested) && isfield(nested, field)
        candidate = double(nested.(field));
        if isscalar(candidate)
            value = candidate;
        end
    end
end
end

function value = scalarMetric(metrics, field)
value = NaN;
if isstruct(metrics) && isfield(metrics, field)
    candidate = double(metrics.(field));
    if isscalar(candidate)
        value = candidate;
    end
end
end

function value = minimumExitFlag(solution)
value = NaN;
if isstruct(solution) && isfield(solution, "exitFlags") && ...
        ~isempty(solution.exitFlags)
    value = min(double(solution.exitFlags));
end
end

function value = maximumRelativeGap(solution)
value = NaN;
if ~isstruct(solution) || ~isfield(solution, "objectiveStages") || ...
        isempty(solution.objectiveStages)
    return
end
if isfield(solution.objectiveStages, "relativeGap")
    gaps = double([solution.objectiveStages.relativeGap]);
    finiteGaps = gaps(isfinite(gaps));
    if ~isempty(finiteGaps)
        value = max(finiteGaps);
    end
end
end

function value = objectiveStageCount(solution)
value = NaN;
if isstruct(solution) && isfield(solution, "objectiveStages")
    value = numel(solution.objectiveStages);
end
end

function rows = appendProfileRows(rows, calendarDay, scenario, meta, ...
        strategy, profileType, timeEnd, originalLoadKW, gridImportKW)
timeEnd = timeEnd(:);
originalLoadKW = double(originalLoadKW(:));
gridImportKW = double(gridImportKW(:));
if numel(timeEnd) ~= numel(originalLoadKW) || ...
        numel(timeEnd) ~= numel(gridImportKW) || ...
        any(~isfinite(originalLoadKW)) || any(~isfinite(gridImportKW))
    error("StoreNet:InvalidMonthlyProfile", ...
        "Monthly profile arrays must be finite and aligned.");
end
for intervalIndex = 1:numel(timeEnd)
    row = emptyProfileRow();
    row.Day = calendarDay;
    row.YearMonth = dateshift(calendarDay, "start", "month");
    row.ScenarioId = scenario.ScenarioId;
    row.PairId = scenario.PairId;
    row.CohortId = scenario.CohortId;
    row.SensitivityRole = scenario.SensitivityRole;
    row.IsPrimary = logical(scenario.IsPrimary);
    row.PvBoundaryId = scenario.PvBoundaryId;
    row.TransferLossFraction = double(scenario.TransferLossFraction);
    row.HouseCount = double(meta.houseCount);
    row.PvHomeCount = double(meta.pvHomeCount);
    row.Strategy = strategy;
    row.ProfileType = profileType;
    row.IntervalIndex = intervalIndex;
    row.IntervalEndHour = hours(timeofday(timeEnd(intervalIndex)));
    row.OriginalLoadKW = originalLoadKW(intervalIndex);
    row.GridImportKW = gridImportKW(intervalIndex);
    rows(end + 1, 1) = row; %#ok<AGROW>
end
end

function row = emptyProfileRow()
row = struct(Day=NaT, YearMonth=NaT, ScenarioId="", PairId="", ...
    CohortId="", SensitivityRole="", IsPrimary=false, ...
    PvBoundaryId="", TransferLossFraction=NaN, HouseCount=NaN, ...
    PvHomeCount=NaN, Strategy="", ProfileType="", IntervalIndex=NaN, ...
    IntervalEndHour=NaN, OriginalLoadKW=NaN, GridImportKW=NaN);
end

function writeDailyCheckpoint(rows, path)
if isempty(rows)
    return
end
writetable(struct2table(rows), path);
end

function [monthlyProfiles, rawProfiles] = aggregateMonthlyProfiles(rows)
summaryRows = repmat(emptyMonthlyProfileRow(), 0, 1);
if isempty(rows)
    rawProfiles = struct2table(emptyProfileRow());
    rawProfiles(1, :) = [];
    monthlyProfiles = struct2table(emptyMonthlyProfileRow());
    monthlyProfiles(1, :) = [];
    return
end
rawProfiles = struct2table(rows);
keys = unique(rawProfiles(:, ["YearMonth", "ScenarioId", "Strategy"]), ...
    "rows", "stable");
for keyIndex = 1:height(keys)
    keyMask = rawProfiles.YearMonth == keys.YearMonth(keyIndex) & ...
        rawProfiles.ScenarioId == keys.ScenarioId(keyIndex) & ...
        rawProfiles.Strategy == keys.Strategy(keyIndex);
    intervalIndices = unique(rawProfiles.IntervalIndex(keyMask), "sorted");
    for intervalIndex = reshape(intervalIndices, 1, [])
        selected = find(keyMask & rawProfiles.IntervalIndex == intervalIndex);
        first = selected(1);
        row = emptyMonthlyProfileRow();
        row.YearMonth = keys.YearMonth(keyIndex);
        row.ScenarioId = keys.ScenarioId(keyIndex);
        row.PairId = rawProfiles.PairId(first);
        row.CohortId = rawProfiles.CohortId(first);
        row.SensitivityRole = rawProfiles.SensitivityRole(first);
        row.IsPrimary = rawProfiles.IsPrimary(first);
        row.PvBoundaryId = rawProfiles.PvBoundaryId(first);
        row.TransferLossFraction = rawProfiles.TransferLossFraction(first);
        row.HouseCount = rawProfiles.HouseCount(first);
        row.PvHomeCount = rawProfiles.PvHomeCount(first);
        row.Strategy = keys.Strategy(keyIndex);
        row.ProfileType = rawProfiles.ProfileType(first);
        row.IntervalIndex = intervalIndex;
        row.IntervalEndHour = mean(rawProfiles.IntervalEndHour(selected));
        row.MeanOriginalLoadKW = mean(rawProfiles.OriginalLoadKW(selected));
        row.MeanGridImportKW = mean(rawProfiles.GridImportKW(selected));
        row.ValidProfileDays = numel(unique(rawProfiles.Day(selected)));
        summaryRows(end + 1, 1) = row; %#ok<AGROW>
    end
end
monthlyProfiles = struct2table(summaryRows);
end

function row = emptyMonthlyProfileRow()
row = struct(YearMonth=NaT, ScenarioId="", PairId="", CohortId="", ...
    SensitivityRole="", IsPrimary=false, PvBoundaryId="", ...
    TransferLossFraction=NaN, HouseCount=NaN, PvHomeCount=NaN, ...
    Strategy="", ProfileType="", IntervalIndex=NaN, ...
    IntervalEndHour=NaN, MeanOriginalLoadKW=NaN, ...
    MeanGridImportKW=NaN, ValidProfileDays=NaN);
end

function monthly = aggregateMonthlyMetrics(daily, profiles)
rows = repmat(emptyMonthlyMetricRow(), 0, 1);
keys = unique(daily(:, ["YearMonth", "ScenarioId", "Strategy"]), ...
    "rows", "stable");
for keyIndex = 1:height(keys)
    selected = daily.YearMonth == keys.YearMonth(keyIndex) & ...
        daily.ScenarioId == keys.ScenarioId(keyIndex) & ...
        daily.Strategy == keys.Strategy(keyIndex);
    valid = selected & daily.Status == "ok";
    first = find(selected, 1, "first");
    row = emptyMonthlyMetricRow();
    row.YearMonth = keys.YearMonth(keyIndex);
    row.ScenarioId = keys.ScenarioId(keyIndex);
    row.PairId = daily.PairId(first);
    row.CohortId = daily.CohortId(first);
    row.SensitivityRole = daily.SensitivityRole(first);
    row.IsPrimary = daily.IsPrimary(first);
    row.PvBoundaryId = daily.PvBoundaryId(first);
    row.TransferLossFraction = daily.TransferLossFraction(first);
    row.HouseCount = daily.HouseCount(first);
    row.PvHomeCount = daily.PvHomeCount(first);
    row.Strategy = keys.Strategy(keyIndex);
    row.PaperPeriodRelation = periodRelation(row.YearMonth);
    row.PublicReleaseAvailability = "available_from_public_release";
    row.RequestedDays = numel(unique(daily.Day(selected)));
    row.CandidateDays = row.RequestedDays;
    row.ValidDays = numel(unique(daily.Day(valid)));
    row.FailedOrRejectedDays = row.RequestedDays - row.ValidDays;
    row.UnavailableCandidateDays = 0;
    row.MeanDailyPaperLoadOnlyBaselineBillEUR = ...
        meanOrNaN(daily.PaperLoadOnlyBaselineBillEUR(valid));
    row.MeanDailyPaperLoadOnlySavingsEUR = ...
        meanOrNaN(daily.PaperLoadOnlySavingsEUR(valid));
    row.MeanDailyPaperLoadOnlySavingsPercent = ...
        meanOrNaN(daily.PaperLoadOnlySavingsPercent(valid));
    row.MeanDailyPvSelfNoBatteryBaselineBillEUR = ...
        meanOrNaN(daily.PvSelfNoBatteryBaselineBillEUR(valid));
    row.MeanDailyPvSelfNoBatterySavingsEUR = ...
        meanOrNaN(daily.PvSelfNoBatterySavingsEUR(valid));
    row.MeanDailyPvSelfNoBatterySavingsPercent = ...
        meanOrNaN(daily.PvSelfNoBatterySavingsPercent(valid));
    row.SumPaperLoadOnlyBaselineBillEUR = ...
        sumOrNaN(daily.PaperLoadOnlyBaselineBillEUR(valid));
    row.SumPvSelfNoBatteryBaselineBillEUR = ...
        sumOrNaN(daily.PvSelfNoBatteryBaselineBillEUR(valid));
    row.SumOptimizedBillEUR = sumOrNaN(daily.OptimizedBillEUR(valid));
    row.SumObservedBillEUR = sumOrNaN(daily.ObservedBillEUR(valid));
    outcomeBillSum = row.SumOptimizedBillEUR;
    if row.Strategy == "SB_SC"
        outcomeBillSum = row.SumObservedBillEUR;
    end
    row.RatioOfSummedCostsPaperLoadOnlySavingsPercent = safePercent( ...
        row.SumPaperLoadOnlyBaselineBillEUR - ...
        outcomeBillSum, ...
        row.SumPaperLoadOnlyBaselineBillEUR);
    row.RatioOfSummedCostsPaperLoadOnlySavingsPercentDenominatorIsZero = ...
        denominatorFlag(row.SumPaperLoadOnlyBaselineBillEUR);
    row.RatioOfSummedCostsPvSelfNoBatterySavingsPercent = safePercent( ...
        row.SumPvSelfNoBatteryBaselineBillEUR - ...
        outcomeBillSum, ...
        row.SumPvSelfNoBatteryBaselineBillEUR);
    row.MeanDailyObservedReleasePvSelfNoBatteryBaselineBillEUR = ...
        meanOrNaN(daily. ...
        ObservedReleasePvSelfNoBatteryBaselineBillEUR(valid));
    row.MeanDailyObservedReleaseEngineeringSavingsEUR = ...
        meanOrNaN(daily.ObservedReleaseEngineeringSavingsEUR(valid));
    row.MeanDailyObservedReleaseEngineeringSavingsPercent = ...
        meanOrNaN(daily.ObservedReleaseEngineeringSavingsPercent(valid));
    row.SumObservedReleasePvSelfNoBatteryBaselineBillEUR = ...
        sumOrNaN(daily. ...
        ObservedReleasePvSelfNoBatteryBaselineBillEUR(valid));
    row.RatioOfSummedCostsObservedReleaseEngineeringSavingsPercent = ...
        safePercent(row. ...
        SumObservedReleasePvSelfNoBatteryBaselineBillEUR - outcomeBillSum, ...
        row.SumObservedReleasePvSelfNoBatteryBaselineBillEUR);
    row.RatioOfSummedCostsObservedReleaseEngineeringSavingsPercentDenominatorIsZero = ...
        denominatorFlag( ...
        row.SumObservedReleasePvSelfNoBatteryBaselineBillEUR);
    row.MeanDailyPaperLoadOnlyPeakKW = ...
        meanOrNaN(daily.PaperLoadOnlyPeakKW(valid));
    row.MeanDailyPvSelfNoBatteryPeakKW = ...
        meanOrNaN(daily.PvSelfNoBatteryPeakKW(valid));
    row.MeanDailyOutcomePeakImportKW = ...
        meanOrNaN(daily.OutcomePeakImportKW(valid));
    if ~isempty(profiles)
        profileMask = profiles.YearMonth == row.YearMonth & ...
            profiles.ScenarioId == row.ScenarioId & ...
            profiles.Strategy == row.Strategy;
        row.PeakOfMeanProfileImportKW = ...
            maxOrNaN(profiles.MeanGridImportKW(profileMask));
        row.PeakOfMeanProfileOriginalLoadKW = ...
            maxOrNaN(profiles.MeanOriginalLoadKW(profileMask));
    end
    rows(end + 1, 1) = row; %#ok<AGROW>
end
monthly = struct2table(rows);
end

function relation = periodRelation(yearMonth)
if year(yearMonth) == 2020 && month(yearMonth) <= 6
    relation = "2020-01--06_overlap";
elseif year(yearMonth) == 2020
    relation = "2020-07--12_extrapolation";
else
    relation = "outside_frozen_period";
end
end

function row = emptyMonthlyMetricRow()
row = struct(YearMonth=NaT, ScenarioId="", PairId="", CohortId="", ...
    SensitivityRole="", IsPrimary=false, PvBoundaryId="", ...
    TransferLossFraction=NaN, HouseCount=NaN, PvHomeCount=NaN, ...
    Strategy="", PaperPeriodRelation="", ...
    PublicReleaseAvailability="", CandidateDays=NaN, ...
    RequestedDays=NaN, ValidDays=NaN, FailedOrRejectedDays=NaN, ...
    UnavailableCandidateDays=NaN, ...
    MeanDailyPaperLoadOnlyBaselineBillEUR=NaN, ...
    MeanDailyPaperLoadOnlySavingsEUR=NaN, ...
    MeanDailyPaperLoadOnlySavingsPercent=NaN, ...
    MeanDailyPvSelfNoBatteryBaselineBillEUR=NaN, ...
    MeanDailyPvSelfNoBatterySavingsEUR=NaN, ...
    MeanDailyPvSelfNoBatterySavingsPercent=NaN, ...
    MeanDailyObservedReleasePvSelfNoBatteryBaselineBillEUR=NaN, ...
    MeanDailyObservedReleaseEngineeringSavingsEUR=NaN, ...
    MeanDailyObservedReleaseEngineeringSavingsPercent=NaN, ...
    SumPaperLoadOnlyBaselineBillEUR=NaN, ...
    SumPvSelfNoBatteryBaselineBillEUR=NaN, ...
    SumObservedReleasePvSelfNoBatteryBaselineBillEUR=NaN, ...
    SumOptimizedBillEUR=NaN, SumObservedBillEUR=NaN, ...
    RatioOfSummedCostsPaperLoadOnlySavingsPercent=NaN, ...
    RatioOfSummedCostsPaperLoadOnlySavingsPercentDenominatorIsZero=NaN, ...
    RatioOfSummedCostsPvSelfNoBatterySavingsPercent=NaN, ...
    RatioOfSummedCostsObservedReleaseEngineeringSavingsPercent=NaN, ...
    RatioOfSummedCostsObservedReleaseEngineeringSavingsPercentDenominatorIsZero=NaN, ...
    MeanDailyPaperLoadOnlyPeakKW=NaN, ...
    MeanDailyPvSelfNoBatteryPeakKW=NaN, ...
    MeanDailyOutcomePeakImportKW=NaN, ...
    PeakOfMeanProfileImportKW=NaN, ...
    PeakOfMeanProfileOriginalLoadKW=NaN);
end

function value = meanOrNaN(values)
finiteValues = values(isfinite(values));
if isempty(finiteValues)
    value = NaN;
else
    value = mean(finiteValues);
end
end

function value = sumOrNaN(values)
finiteValues = values(isfinite(values));
if isempty(finiteValues)
    value = NaN;
else
    value = sum(finiteValues);
end
end

function percentage = safePercent(numerator, denominator)
if ~isfinite(numerator) || ~isfinite(denominator) || ...
        abs(denominator) <= eps(max(1, abs(denominator)))
    percentage = NaN;
else
    percentage = 100 .* numerator ./ denominator;
end
end

function flag = denominatorFlag(denominator)
if ~isfinite(denominator)
    flag = NaN;
else
    flag = double(abs(denominator) <= eps(max(1, abs(denominator))));
end
end

function value = maxOrNaN(values)
finiteValues = values(isfinite(values));
if isempty(finiteValues)
    value = NaN;
else
    value = max(finiteValues);
end
end

function writeFigure6Proxy(path, monthly, profiles, scenarios, strategies, ...
        visible)
primaryId = scenarios.ScenarioId(scenarios.IsPrimary);
if ~isscalar(primaryId)
    error("StoreNet:InvalidPrimaryScenario", ...
        "The monthly matrix must contain exactly one primary scenario.");
end
months = unique(monthly.YearMonth(monthly.ScenarioId == primaryId), "sorted");
allStrategies = strategies;
visibility = "off";
if visible
    visibility = "on";
end
figureHandle = figure(Visible=visibility, Color="w", ...
    Position=[100, 100, 1350, 850]);
cleaner = onCleanup(@() close(figureHandle));
layout = tiledlayout(figureHandle, 2, 1, Padding="compact", ...
    TileSpacing="compact");

savingsAxes = nexttile(layout);
hold(savingsAxes, "on");
for strategyIndex = 1:numel(allStrategies)
    seriesScenarioId = primaryId;
    values = monthlySeries(monthly, months, seriesScenarioId, ...
        allStrategies(strategyIndex), ...
        "MeanDailyPaperLoadOnlySavingsPercent");
    plot(savingsAxes, months, values, "o-", LineWidth=1.35, ...
        DisplayName=allStrategies(strategyIndex));
end
hold(savingsAxes, "off");
grid(savingsAxes, "on");
ylabel(savingsAxes, "Mean daily savings vs load-only (%)");
title(savingsAxes, ...
    "B2022-IR-v1 Figure 6 proxy: explicit load-only baseline");
legend(savingsAxes, Location="eastoutside", Interpreter="none");

peakAxes = nexttile(layout);
hold(peakAxes, "on");
for strategyIndex = 1:numel(allStrategies)
    seriesScenarioId = primaryId;
    values = monthlySeries(monthly, months, seriesScenarioId, ...
        allStrategies(strategyIndex), "PeakOfMeanProfileImportKW");
    plot(peakAxes, months, values, "o-", LineWidth=1.35, ...
        DisplayName=allStrategies(strategyIndex));
end
originalLoadPeak = originalLoadSeries(profiles, months, primaryId);
plot(peakAxes, months, originalLoadPeak, "k--", LineWidth=1.8, ...
    DisplayName="Original Load");
hold(peakAxes, "off");
grid(peakAxes, "on");
ylabel(peakAxes, "Peak of monthly mean profile (kW)");
xlabel(peakAxes, "Month");
title(peakAxes, "Import peak and original-load reference");
legend(peakAxes, Location="eastoutside", Interpreter="none");

exportgraphics(figureHandle, path, Resolution=250, ...
    BackgroundColor="white");
end

function values = monthlySeries(monthly, months, scenarioId, strategy, field)
values = nan(size(months));
for monthIndex = 1:numel(months)
    selected = monthly.YearMonth == months(monthIndex) & ...
        monthly.ScenarioId == scenarioId & monthly.Strategy == strategy;
    if nnz(selected) == 1
        values(monthIndex) = monthly.(field)(selected);
    end
end
end

function values = originalLoadSeries(profiles, months, scenarioId)
values = nan(size(months));
if isempty(profiles)
    return
end
for monthIndex = 1:numel(months)
    selected = profiles.YearMonth == months(monthIndex) & ...
        profiles.ScenarioId == scenarioId & ...
        profiles.Strategy == "ORIGINAL_LOAD";
    values(monthIndex) = maxOrNaN(profiles.MeanOriginalLoadKW(selected));
end
end
