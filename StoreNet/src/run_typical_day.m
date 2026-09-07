function run = run_typical_day(day, options)
%RUN_TYPICAL_DAY Run the five paper baselines, then the peak-guard improvement.
%   RUN = RUN_TYPICAL_DAY() uses the frozen 2020-08-24 public-data proxy at
%   30-minute resolution. The five baseline strategies always execute before
%   IMPROVED_PEAK_GUARD. The improvement cap is the no-battery, household PV
%   self-consumption baseline peak, fixed before any optimization.

arguments
    day (1, 1) datetime = datetime(2020, 8, 24)
    options.IntervalMinutes (1, 1) double {mustBeMember(options.IntervalMinutes, 30)} = 30
    options.QualityMode (1, 1) string {mustBeMember(options.QualityMode, ...
        ["release_literal", "short_gap_only", "exclude_flagged_pv"])} = ...
        "exclude_flagged_pv"
    options.DataRoot (1, 1) string = ""
    options.OutputRoot (1, 1) string = ""
    options.RunId (1, 1) string = ""
    options.ConfigOverrides (1, 1) struct = struct
    options.DataProvider (1, 1) function_handle = @load_storenet_day
    options.Solver (1, 1) function_handle = @solve_storenet
    options.FigureVisible (1, 1) logical = false
end

day = dateshift(day, "start", "day");
sourceFolder = fileparts(mfilename("fullpath"));
if strlength(options.OutputRoot) == 0
    options.OutputRoot = string(fullfile(sourceFolder, "..", "results"));
end
if strlength(options.RunId) == 0
    options.RunId = "typical_" + string(day, "yyyyMMdd") + "_" + ...
        string(datetime("now"), "yyyyMMdd_HHmmss_SSS");
end
runDirectory = prepareRunDirectory(options.OutputRoot, options.RunId);

[data, dataMeta] = callDataProvider(options.DataProvider, day, ...
    options.DataRoot, options.IntervalMinutes, options.QualityMode);
data = normalizeExperimentData(data);
config = storenet_config(IntervalMinutes=options.IntervalMinutes, ...
    DataRoot=options.DataRoot, QualityMode=options.QualityMode);
config = applyOverrides(config, options.ConfigOverrides);

baselineStrategies = ["SH_BM", "VPP_BM", "PS", "PSDT", "LL"];
allStrategies = [baselineStrategies, "IMPROVED_PEAK_GUARD"];
rows = repmat(emptyMetricRow(), 0, 1);
solutions = cell(numel(allStrategies), 1);
profiles = baseProfiles(data, config);
baselineSucceeded = true;
improvementCapKW = NaN;

for strategyIndex = 1:numel(baselineStrategies)
    strategy = baselineStrategies(strategyIndex);
    started = tic;
    try
        [solution, metrics] = options.Solver(data, config, strategy);
        wallTimeSeconds = toc(started);
        solutions{strategyIndex} = solution;
        rows(end + 1, 1) = metricRow(day, strategy, "baseline", "ok", ...
            "", "", wallTimeSeconds, config, NaN, metrics, solution); %#ok<AGROW>
        profiles.(profileVariable(strategy)) = solution.aggregateImportKW(:);
        if strategyIndex == 1
            improvementCapKW = explicitBaselineMetric(metrics, ...
                "PvSelfNoBatteryBaseline", "peakImportKW", ...
                "baselinePeakImportKW");
        end
    catch exception
        wallTimeSeconds = toc(started);
        baselineSucceeded = false;
        rows(end + 1, 1) = metricRow(day, strategy, "baseline", "failed", ...
            string(exception.identifier), string(exception.message), ...
            wallTimeSeconds, config, NaN, struct, struct); %#ok<AGROW>
        profiles.(profileVariable(strategy)) = nan(height(profiles), 1);
    end
end

improvedIndex = numel(allStrategies);
if baselineSucceeded && isfinite(improvementCapKW)
    improvedConfig = config;
    improvedConfig.aggregateImportCapKW = improvementCapKW;
    started = tic;
    try
        [solution, metrics] = options.Solver(data, improvedConfig, ...
            "IMPROVED_PEAK_GUARD");
        wallTimeSeconds = toc(started);
        solutions{improvedIndex} = solution;
        rows(end + 1, 1) = metricRow(day, "IMPROVED_PEAK_GUARD", ...
            "improvement", "ok", "", "", wallTimeSeconds, improvedConfig, ...
            improvementCapKW, metrics, solution);
        profiles.(profileVariable("IMPROVED_PEAK_GUARD")) = ...
            solution.aggregateImportKW(:);
    catch exception
        wallTimeSeconds = toc(started);
        rows(end + 1, 1) = metricRow(day, "IMPROVED_PEAK_GUARD", ...
            "improvement", "failed", string(exception.identifier), ...
            string(exception.message), wallTimeSeconds, improvedConfig, ...
            improvementCapKW, struct, struct);
        profiles.(profileVariable("IMPROVED_PEAK_GUARD")) = ...
            nan(height(profiles), 1);
    end
else
    if baselineSucceeded
        skipIdentifier = "StoreNet:MissingBaselinePeak";
        skipMessage = "First baseline metrics did not provide a finite baselinePeakImportKW.";
    else
        skipIdentifier = "StoreNet:BaselineFailure";
        skipMessage = "Improvement was not run because at least one baseline failed.";
    end
    rows(end + 1, 1) = metricRow(day, "IMPROVED_PEAK_GUARD", ...
        "improvement", "skipped_baseline_failure", ...
        skipIdentifier, skipMessage, ...
        0, config, improvementCapKW, struct, struct);
    profiles.(profileVariable("IMPROVED_PEAK_GUARD")) = ...
        nan(height(profiles), 1);
end

metricsTable = struct2table(rows);
metricsPath = fullfile(runDirectory, "metrics.csv");
profilesPath = fullfile(runDirectory, "profiles.csv");
figurePath = fullfile(runDirectory, "typical_day.png");
writetable(metricsTable, metricsPath);
writetable(profiles, profilesPath);
writeTypicalFigure(figurePath, day, profiles, metricsTable, allStrategies, ...
    options.FigureVisible);

runInfo = struct;
runInfo.runType = "typical_day";
runInfo.runId = options.RunId;
runInfo.days = string(day, "yyyy-MM-dd");
runInfo.qualityMode = options.QualityMode;
runInfo.intervalMinutes = options.IntervalMinutes;
runInfo.intervalConvention = metadataField(dataMeta, ...
    "intervalConvention", "interval-end labels");
runInfo.baselineStrategies = baselineStrategies;
runInfo.improvementStrategy = "IMPROVED_PEAK_GUARD";
runInfo.improvementExecutedAfterBaselines = true;
runInfo.improvementCapDefinition = ...
    "peak of no-battery household PV-self-consumption baseline";
runInfo.improvementCapKW = improvementCapKW;
runInfo.configuration = config;
runInfo.qualitySummary = qualitySummary(dataMeta);
runInfo.statuses = metricsTable(:, ["Day", "Strategy", "Phase", "Status", ...
    "ErrorIdentifier", "ErrorMessage", "WallTimeSeconds"]);
[manifest, manifestPath] = write_run_manifest(runDirectory, runInfo);

run = struct;
run.day = day;
run.runDirectory = runDirectory;
run.metricsPath = metricsPath;
run.profilesPath = profilesPath;
run.figurePath = figurePath;
run.manifestPath = manifestPath;
run.metricsTable = metricsTable;
run.profilesTable = profiles;
run.solutions = solutions;
run.configuration = config;
run.dataMeta = dataMeta;
run.manifest = manifest;
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

function profiles = baseProfiles(data, config)
aggregateLoadKW = sum(double(data.loadKW), 2);
aggregatePvKW = sum(double(data.pvKW), 2);
pvToHomeKW = min(double(data.loadKW), config.etaPvAC .* double(data.pvKW));
noBatteryImportKW = sum(double(data.loadKW) - pvToHomeKW, 2);
profiles = table(data.time(:), aggregateLoadKW, aggregatePvKW, ...
    noBatteryImportKW, VariableNames=["Time", "AggregateLoadKW", ...
    "AggregatePvKW", "NoBatteryPvSelfImportKW"]);
end

function writeTypicalFigure(path, day, profiles, metrics, strategies, visible)
visibility = "off";
if visible
    visibility = "on";
end
figureHandle = figure(Visible=visibility, Color="w", ...
    Position=[100, 100, 1400, 850]);
cleaner = onCleanup(@() close(figureHandle));
layout = tiledlayout(figureHandle, 2, 2, Padding="compact", ...
    TileSpacing="compact");

topAxes = nexttile(layout, [1, 2]);
plot(topAxes, profiles.Time, profiles.AggregateLoadKW, LineWidth=1.8, ...
    Color=[0.0000, 0.4470, 0.7410]);
hold(topAxes, "on");
plot(topAxes, profiles.Time, profiles.AggregatePvKW, LineWidth=1.8, ...
    Color=[0.8500, 0.3250, 0.0980]);
plot(topAxes, profiles.Time, profiles.NoBatteryPvSelfImportKW, ...
    LineWidth=1.5, LineStyle="--", Color=[0.20, 0.20, 0.20]);
hold(topAxes, "off");
grid(topAxes, "on");
ylabel(topAxes, "Power (kW)");
title(topAxes, "StoreNet public-data proxy: " + string(day, "yyyy-MM-dd"));
topLegend = legend(topAxes, ["Load", "PV", "No-battery import"], ...
    Location="northoutside", Orientation="horizontal");
applyPublicationAxesStyle(topAxes);
applyPublicationLegendStyle(topLegend);

profileAxes = nexttile(layout);
colororder(profileAxes, lines(numel(strategies)));
hold(profileAxes, "on");
for strategyIndex = 1:numel(strategies)
    variable = profileVariable(strategies(strategyIndex));
    plot(profileAxes, profiles.Time, profiles.(variable), LineWidth=1.2, ...
        DisplayName=strategies(strategyIndex));
end
hold(profileAxes, "off");
grid(profileAxes, "on");
ylabel(profileAxes, "Aggregate import (kW)");
title(profileAxes, "Optimized import profiles");
profileLegend = legend(profileAxes, Location="best", Interpreter="none");
applyPublicationAxesStyle(profileAxes);
applyPublicationLegendStyle(profileLegend);

metricAxes = nexttile(layout);
yyaxis(metricAxes, "left");
bar(metricAxes, 1:height(metrics), metrics.SavingsPercent, FaceAlpha=0.85, ...
    FaceColor=[0.20, 0.60, 0.40], EdgeColor=[0.12, 0.35, 0.24]);
ylabel(metricAxes, "Bill savings (%)");
yyaxis(metricAxes, "right");
plot(metricAxes, 1:height(metrics), metrics.PeakImportKW, "o-", ...
    LineWidth=1.6, Color=[0.72, 0.22, 0.18], ...
    MarkerFaceColor=[0.72, 0.22, 0.18], MarkerEdgeColor="w");
ylabel(metricAxes, "Peak import (kW)");
grid(metricAxes, "on");
metricAxes.XTick = 1:height(metrics);
metricAxes.XTickLabel = replace(metrics.Strategy, "_", "-");
metricAxes.XTickLabelRotation = 25;
title(metricAxes, "Cost and peak comparison");
metricLegend = legend(metricAxes, ["Bill savings", "Peak import"], ...
    Location="northoutside", Orientation="horizontal");
applyPublicationAxesStyle(metricAxes);
applyPublicationLegendStyle(metricLegend);

exportgraphics(figureHandle, path, Resolution=300, BackgroundColor="white");
end

function applyPublicationAxesStyle(axesHandle)
darkColor = [0.12, 0.14, 0.16];
gridColor = [0.68, 0.71, 0.74];
set(axesHandle, Color="w", XColor=darkColor, ZColor=darkColor, ...
    GridColor=gridColor, GridAlpha=0.35, ...
    MinorGridColor=gridColor, MinorGridAlpha=0.20, ...
    FontName="Helvetica", FontSize=10, LineWidth=0.8, ...
    Box="on", Layer="top");
axesHandle.Title.Color = darkColor;
axesHandle.XLabel.Color = darkColor;
for rulerIndex = 1:numel(axesHandle.YAxis)
    axesHandle.YAxis(rulerIndex).Color = darkColor;
    axesHandle.YAxis(rulerIndex).Label.Color = darkColor;
end
end

function applyPublicationLegendStyle(legendHandle)
set(legendHandle, Color="w", TextColor=[0.12, 0.14, 0.16], ...
    EdgeColor=[0.68, 0.71, 0.74], FontName="Helvetica", FontSize=9);
end

function variable = profileVariable(strategy)
variable = matlab.lang.makeValidName("Import_" + strategy + "_KW");
end

function row = metricRow(day, strategy, phase, status, errorIdentifier, ...
        errorMessage, wallTimeSeconds, config, importCapKW, metrics, solution)
row = emptyMetricRow();
row.Day = day;
row.Strategy = strategy;
row.Phase = phase;
row.Status = status;
row.ErrorIdentifier = errorIdentifier;
row.ErrorMessage = errorMessage;
row.WallTimeSeconds = wallTimeSeconds;
row.BatteryCapacityKWh = double(config.batteryCapacityKWh);
row.BatteryPowerKW = double(config.batteryPowerKW);
row.ImportCapKW = double(importCapKW);
row.BaselineBillEUR = explicitBaselineMetric(metrics, ...
    "PaperLoadOnlyBaseline", "billEUR", "baselineBillEUR");
row.SavingsEUR = explicitBaselineMetric(metrics, ...
    "PaperLoadOnlyBaseline", "savingsEUR", "savingsEUR");
row.SavingsPercent = explicitBaselineMetric(metrics, ...
    "PaperLoadOnlyBaseline", "savingsPercent", "savingsPercent");
row.BaselinePeakImportKW = explicitBaselineMetric(metrics, ...
    "PaperLoadOnlyBaseline", "peakImportKW", "baselinePeakImportKW");
metricFields = ["optimizedBillEUR", "peakImportKW", ...
    "daytimePeakImportKW", "importSpreadKW", "totalGridImportKWh", ...
    "totalBatteryThroughputKWh", "totalCurtailedPvKWh", ...
    "totalSharedExportKWh", "energyBalanceResidualKW", ...
    "terminalSocErrorKWh", "simultaneousChargeDischargeKW"];
rowFields = ["OptimizedBillEUR", "PeakImportKW", ...
    "DaytimePeakImportKW", "ImportSpreadKW", "TotalGridImportKWh", ...
    "TotalBatteryThroughputKWh", "TotalCurtailedPvKWh", ...
    "TotalSharedExportKWh", "EnergyBalanceResidualKW", ...
    "TerminalSocErrorKWh", "SimultaneousChargeDischargeKW"];
for fieldIndex = 1:numel(metricFields)
    if isfield(metrics, metricFields(fieldIndex))
        row.(rowFields(fieldIndex)) = double(metrics.(metricFields(fieldIndex)));
    end
end
if isfield(solution, "exitFlags") && ~isempty(solution.exitFlags)
    row.MinimumExitFlag = min(double(solution.exitFlags));
end
end

function value = explicitBaselineMetric(metrics, baselineName, fieldName, ...
        legacyFieldName)
value = NaN;
if isstruct(metrics) && isfield(metrics, baselineName) && ...
        isstruct(metrics.(baselineName)) && ...
        isfield(metrics.(baselineName), fieldName)
    value = double(metrics.(baselineName).(fieldName));
elseif isstruct(metrics) && isfield(metrics, legacyFieldName)
    value = double(metrics.(legacyFieldName));
end
end

function row = emptyMetricRow()
row = struct;
row.Day = NaT;
row.Strategy = "";
row.Phase = "";
row.Status = "";
row.ErrorIdentifier = "";
row.ErrorMessage = "";
row.WallTimeSeconds = NaN;
row.BatteryCapacityKWh = NaN;
row.BatteryPowerKW = NaN;
row.ImportCapKW = NaN;
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
row.MinimumExitFlag = NaN;
end

function config = applyOverrides(config, overrides)
fields = string(fieldnames(overrides));
for fieldIndex = 1:numel(fields)
    field = fields(fieldIndex);
    config.(field) = overrides.(field);
end
end

function [data, meta] = callDataProvider(provider, day, dataRoot, ...
        intervalMinutes, qualityMode)
try
    [data, meta] = provider(day, DataRoot=dataRoot, ...
        IntervalMinutes=intervalMinutes, QualityMode=qualityMode);
catch exception
    legacyMode = legacyQualityMode(qualityMode);
    if legacyMode == qualityMode || ~isArgumentValidationFailure(exception)
        rethrow(exception)
    end
    [data, meta] = provider(day, DataRoot=dataRoot, ...
        IntervalMinutes=intervalMinutes, QualityMode=legacyMode);
end
enforceQualityMetadata(meta, day, qualityMode);
end

function enforceQualityMetadata(meta, day, qualityMode)
if isfield(meta, "qualityPassed") && ~logical(meta.qualityPassed)
    reasons = "quality contract returned false";
    if isfield(meta, "qualityReasons") && ~isempty(meta.qualityReasons)
        reasons = strjoin(string(meta.qualityReasons), "; ");
    end
    error("StoreNet:QualityRejected", "Day %s fails %s: %s.", ...
        string(day, "yyyy-MM-dd"), qualityMode, reasons);
end
end

function mode = legacyQualityMode(mode)
if mode == "release_literal"
    mode = "report";
else
    mode = "strict";
end
end

function tf = isArgumentValidationFailure(exception)
identifier = string(exception.identifier);
message = string(exception.message);
tf = contains(identifier, "validation", IgnoreCase=true) || ...
    contains(identifier, "invalidType", IgnoreCase=true) || ...
    contains(message, "must be a member", IgnoreCase=true) || ...
    contains(message, "QualityMode", IgnoreCase=true) && ...
    contains(message, "accepted", IgnoreCase=true);
end

function data = normalizeExperimentData(data)
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
        "Data provider output is missing field(s): %s.", strjoin(missing, ", "));
end
data.time = data.time(:);
end

function value = metadataField(metadata, field, defaultValue)
if isfield(metadata, field)
    value = metadata.(field);
else
    value = defaultValue;
end
end

function summary = qualitySummary(metadata)
summary = struct;
summary.qualityPassed = metadataField(metadata, "qualityPassed", true);
summary.qualityReasons = metadataField(metadata, "qualityReasons", strings(0, 1));
summary.isComplete = metadataField(metadata, "isComplete", true);
summary.isFullyObserved = metadataField(metadata, "isFullyObserved", true);
summary.pvLongWindowAnomaly = metadataField(metadata, ...
    "pvLongWindowAnomaly", false);
summary.pvWindowHours = metadataField(metadata, "pvWindowHours", NaN);
summary.astronomicalDayLengthHours = metadataField(metadata, ...
    "astronomicalDayLengthHours", NaN);
summary.maximumMissingStatusRunMinutes = maxMetadataVector(metadata, ...
    "longestMissingStatusRunByHome");
end

function value = maxMetadataVector(metadata, field)
if isfield(metadata, field) && ~isempty(metadata.(field))
    value = max(double(metadata.(field)));
else
    value = NaN;
end
end
