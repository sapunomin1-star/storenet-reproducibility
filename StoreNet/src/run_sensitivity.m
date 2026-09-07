function run = run_sensitivity(day, options)
%RUN_SENSITIVITY Evaluate a declared capacity/power ratio grid with VPP-BM.
%   RUN = RUN_SENSITIVITY() uses the frozen typical day and the explicitly
%   declared 0.2:0.2:1 ratios. Capacity ratios scale physical kWh first;
%   initial, minimum, maximum, and terminal energies then follow their fixed
%   fractions of that scaled capacity. Power ratios directly scale kW.

arguments
    day (1, 1) datetime = datetime(2020, 8, 24)
    options.CapacityRatios (1, :) double = [0.2, 0.4, 0.6, 0.8, 1]
    options.PowerRatios (1, :) double = [0.2, 0.4, 0.6, 0.8, 1]
    options.IntervalMinutes (1, 1) double {mustBeMember(options.IntervalMinutes, [30, 60])} = 30
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

validateRatioGrid(options.CapacityRatios, "CapacityRatios");
validateRatioGrid(options.PowerRatios, "PowerRatios");
capacityRatios = unique(options.CapacityRatios, "stable");
powerRatios = unique(options.PowerRatios, "stable");
day = dateshift(day, "start", "day");
sourceFolder = fileparts(mfilename("fullpath"));
if strlength(options.OutputRoot) == 0
    options.OutputRoot = string(fullfile(sourceFolder, "..", "results"));
end
if strlength(options.RunId) == 0
    options.RunId = "sensitivity_" + string(day, "yyyyMMdd") + "_" + ...
        string(datetime("now"), "yyyyMMdd_HHmmss_SSS");
end
runDirectory = prepareRunDirectory(options.OutputRoot, options.RunId);

nominalConfig = storenet_config(IntervalMinutes=options.IntervalMinutes, ...
    DataRoot=options.DataRoot, QualityMode=options.QualityMode);
nominalConfig = applyOverrides(nominalConfig, options.ConfigOverrides);
nominalCapacityKWh = double(nominalConfig.batteryCapacityKWh);
nominalPowerKW = double(nominalConfig.batteryPowerKW);
rows = repmat(emptySensitivityRow(), 0, 1);

try
    [data, dataMeta] = callDataProvider(options.DataProvider, day, ...
        options.DataRoot, options.IntervalMinutes, options.QualityMode);
    if metadataRejected(dataMeta)
        dataStatus = "quality_rejected";
        dataIdentifier = "StoreNet:QualityRejected";
        dataMessage = qualityRejectionMessage(day, options.QualityMode, dataMeta);
    else
        data = normalizeExperimentData(data);
        dataStatus = "ok";
        dataIdentifier = "";
        dataMessage = "";
    end
catch exception
    data = struct;
    dataMeta = struct;
    dataStatus = "quality_rejected";
    if ~contains(string(exception.identifier), ...
            ["Quality", "Incomplete", "Flagged"], IgnoreCase=true)
        dataStatus = "data_failed";
    end
    dataIdentifier = string(exception.identifier);
    dataMessage = string(exception.message);
end

for capacityIndex = 1:numel(capacityRatios)
    for powerIndex = 1:numel(powerRatios)
        capacityRatio = capacityRatios(capacityIndex);
        powerRatio = powerRatios(powerIndex);
        config = nominalConfig;
        config.batteryCapacityKWh = nominalCapacityKWh * capacityRatio;
        config.batteryPowerKW = nominalPowerKW * powerRatio;
        if dataStatus ~= "ok"
            rows(end + 1, 1) = sensitivityRow(day, capacityRatio, ...
                powerRatio, config, dataStatus, dataIdentifier, dataMessage, ...
                0, struct, struct); %#ok<AGROW>
            continue
        end
        started = tic;
        try
            [solution, metrics] = options.Solver(data, config, "VPP_BM");
            rows(end + 1, 1) = sensitivityRow(day, capacityRatio, ...
                powerRatio, config, "ok", "", "", toc(started), ...
                metrics, solution); %#ok<AGROW>
        catch exception
            rows(end + 1, 1) = sensitivityRow(day, capacityRatio, ...
                powerRatio, config, "failed", string(exception.identifier), ...
                string(exception.message), toc(started), struct, struct); %#ok<AGROW>
        end
    end
end

sensitivityTable = struct2table(rows);
metricsPath = fullfile(runDirectory, "sensitivity.csv");
figurePath = fullfile(runDirectory, "sensitivity.png");
writetable(sensitivityTable, metricsPath);
writeSensitivityFigure(figurePath, sensitivityTable, capacityRatios, ...
    powerRatios, options.FigureVisible);

runInfo = struct;
runInfo.runType = "capacity_power_sensitivity";
runInfo.runId = options.RunId;
runInfo.days = string(day, "yyyy-MM-dd");
runInfo.qualityMode = options.QualityMode;
runInfo.intervalMinutes = options.IntervalMinutes;
runInfo.intervalConvention = metadataField(dataMeta, ...
    "intervalConvention", "interval-end labels");
runInfo.strategy = "VPP_BM";
runInfo.capacityRatios = capacityRatios;
runInfo.powerRatios = powerRatios;
runInfo.scalingDefinition = [ ...
    "batteryCapacityKWh = nominal capacity * capacity ratio; ", ...
    "SoC endpoints/bounds retain fractions of scaled capacity; ", ...
    "batteryPowerKW = nominal power * power ratio"];
runInfo.nominalConfiguration = nominalConfig;
runInfo.qualitySummary = qualitySummary(dataMeta);
runInfo.statuses = sensitivityTable(:, ["Day", "CapacityRatio", ...
    "PowerRatio", "Status", "ErrorIdentifier", "ErrorMessage", ...
    "WallTimeSeconds"]);
[manifest, manifestPath] = write_run_manifest(runDirectory, runInfo);

run = struct;
run.day = day;
run.runDirectory = runDirectory;
run.metricsPath = metricsPath;
run.figurePath = figurePath;
run.manifestPath = manifestPath;
run.sensitivityTable = sensitivityTable;
run.nominalConfiguration = nominalConfig;
run.dataMeta = dataMeta;
run.manifest = manifest;
end

function validateRatioGrid(values, name)
if isempty(values) || any(~isfinite(values)) || any(values <= 0)
    error("StoreNet:InvalidSensitivityGrid", ...
        "%s must contain finite positive ratios.", name);
end
end

function row = sensitivityRow(day, capacityRatio, powerRatio, config, ...
        status, identifier, message, wallTimeSeconds, metrics, solution)
row = emptySensitivityRow();
row.Day = day;
row.CapacityRatio = capacityRatio;
row.PowerRatio = powerRatio;
row.Status = status;
row.ErrorIdentifier = identifier;
row.ErrorMessage = message;
row.WallTimeSeconds = wallTimeSeconds;
row.BatteryCapacityKWh = double(config.batteryCapacityKWh);
row.BatteryPowerKW = double(config.batteryPowerKW);
row.InitialEnergyKWh = double(config.socInitialFraction) * ...
    double(config.batteryCapacityKWh);
row.MinimumEnergyKWh = double(config.socMinFraction) * ...
    double(config.batteryCapacityKWh);
row.MaximumEnergyKWh = double(config.socMaxFraction) * ...
    double(config.batteryCapacityKWh);
terminalFraction = config.socInitialFraction;
if isfield(config, "socTerminalFraction")
    terminalFraction = config.socTerminalFraction;
end
row.TerminalEnergyKWh = double(terminalFraction) * ...
    double(config.batteryCapacityKWh);
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
    "totalBatteryThroughputKWh", "energyBalanceResidualKW", ...
    "terminalSocErrorKWh", "simultaneousChargeDischargeKW"];
rowFields = ["OptimizedBillEUR", "PeakImportKW", ...
    "DaytimePeakImportKW", "ImportSpreadKW", "TotalGridImportKWh", ...
    "TotalBatteryThroughputKWh", "EnergyBalanceResidualKW", ...
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

function row = emptySensitivityRow()
row = struct;
row.Day = NaT;
row.CapacityRatio = NaN;
row.PowerRatio = NaN;
row.Status = "";
row.ErrorIdentifier = "";
row.ErrorMessage = "";
row.WallTimeSeconds = NaN;
row.BatteryCapacityKWh = NaN;
row.BatteryPowerKW = NaN;
row.InitialEnergyKWh = NaN;
row.MinimumEnergyKWh = NaN;
row.MaximumEnergyKWh = NaN;
row.TerminalEnergyKWh = NaN;
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
row.EnergyBalanceResidualKW = NaN;
row.TerminalSocErrorKWh = NaN;
row.SimultaneousChargeDischargeKW = NaN;
row.MinimumExitFlag = NaN;
end

function writeSensitivityFigure(path, metrics, capacityRatios, powerRatios, visible)
visibility = "off";
if visible
    visibility = "on";
end
figureHandle = figure(Visible=visibility, Color="w", ...
    Position=[100, 100, 1200, 500]);
cleaner = onCleanup(@() close(figureHandle));
layout = tiledlayout(figureHandle, 1, 2, Padding="compact", ...
    TileSpacing="compact");
colormap(figureHandle, parula(256));
savings = reshape(metrics.SavingsPercent, numel(powerRatios), ...
    numel(capacityRatios)).';
peaks = reshape(metrics.PeakImportKW, numel(powerRatios), ...
    numel(capacityRatios)).';

savingsAxes = nexttile(layout);
imagesc(savingsAxes, powerRatios, capacityRatios, savings);
set(savingsAxes, YDir="normal");
savingsColorbar = colorbar(savingsAxes);
xlabel(savingsAxes, "Power ratio");
ylabel(savingsAxes, "Capacity ratio");
title(savingsAxes, "VPP-BM bill savings (%)");
savingsAxes.XTick = powerRatios;
savingsAxes.YTick = capacityRatios;
grid(savingsAxes, "on");
applyPublicationAxesStyle(savingsAxes);
applyPublicationColorbarStyle(savingsColorbar);

peakAxes = nexttile(layout);
imagesc(peakAxes, powerRatios, capacityRatios, peaks);
set(peakAxes, YDir="normal");
peakColorbar = colorbar(peakAxes);
xlabel(peakAxes, "Power ratio");
ylabel(peakAxes, "Capacity ratio");
title(peakAxes, "VPP-BM peak import (kW)");
peakAxes.XTick = powerRatios;
peakAxes.YTick = capacityRatios;
grid(peakAxes, "on");
applyPublicationAxesStyle(peakAxes);
applyPublicationColorbarStyle(peakColorbar);

exportgraphics(figureHandle, path, Resolution=300, BackgroundColor="white");
end

function applyPublicationAxesStyle(axesHandle)
darkColor = [0.12, 0.14, 0.16];
gridColor = [0.68, 0.71, 0.74];
set(axesHandle, Color="w", XColor=darkColor, YColor=darkColor, ...
    ZColor=darkColor, GridColor=gridColor, GridAlpha=0.30, ...
    MinorGridColor=gridColor, MinorGridAlpha=0.18, ...
    FontName="Helvetica", FontSize=10, LineWidth=0.8, ...
    Box="on", Layer="top");
axesHandle.Title.Color = darkColor;
axesHandle.XLabel.Color = darkColor;
axesHandle.YLabel.Color = darkColor;
end

function applyPublicationColorbarStyle(colorbarHandle)
set(colorbarHandle, Color=[0.12, 0.14, 0.16], ...
    FontName="Helvetica", FontSize=9, LineWidth=0.8);
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
end

function tf = metadataRejected(meta)
tf = isfield(meta, "qualityPassed") && ~logical(meta.qualityPassed);
end

function message = qualityRejectionMessage(day, qualityMode, meta)
reasons = "quality contract returned false";
if isfield(meta, "qualityReasons") && ~isempty(meta.qualityReasons)
    reasons = strjoin(string(meta.qualityReasons), "; ");
end
message = "Day " + string(day, "yyyy-MM-dd") + " fails " + ...
    qualityMode + ": " + reasons + ".";
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
summary.qualityPassed = metadataField(metadata, "qualityPassed", false);
summary.qualityReasons = metadataField(metadata, "qualityReasons", strings(0, 1));
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
