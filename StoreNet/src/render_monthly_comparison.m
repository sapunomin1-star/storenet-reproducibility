function report = render_monthly_comparison(literalDirectory, excludeDirectory, options)
%RENDER_MONTHLY_COMPARISON Compare literal and quality-aware monthly runs.
%   REPORT = RENDER_MONTHLY_COMPARISON(LITERALDIR, EXCLUDEDIR) reads the
%   monthly summary, quality-status, and metric CSV files from two completed
%   runs. It validates the fixed five-strategy contract and writes aligned
%   comparison tables, a publication-ready figure, and a provenance manifest
%   into a new run directory.

arguments
    literalDirectory (1, 1) string
    excludeDirectory (1, 1) string
    options.OutputRoot (1, 1) string = ""
    options.RunId (1, 1) string = ""
    options.FigureVisible (1, 1) logical = false
end

sourceFolder = fileparts(mfilename("fullpath"));
if strlength(options.OutputRoot) == 0
    options.OutputRoot = string(fullfile(sourceFolder, "..", "results"));
end
if strlength(options.RunId) == 0
    options.RunId = "monthly_comparison_" + ...
        string(datetime("now"), "yyyyMMdd_HHmmss_SSS");
end

strategies = ["SH_BM", "VPP_BM", "PS", "PSDT", "LL"];
literal = readMonthlyRun(literalDirectory, "release_literal", strategies);
excluded = readMonthlyRun(excludeDirectory, "exclude_flagged_pv", strategies);
runDirectory = prepareRunDirectory(options.OutputRoot, options.RunId);

strategyComparison = buildStrategyComparison(literal.summary, ...
    excluded.summary, strategies);
qualityComparison = buildQualityComparison(literal, excluded);
strategyPath = fullfile(runDirectory, "strategy_comparison.csv");
qualityPath = fullfile(runDirectory, "quality_comparison.csv");
figurePath = fullfile(runDirectory, "monthly_comparison.png");
writetable(strategyComparison, strategyPath);
writetable(qualityComparison, qualityPath);
writeComparisonFigure(figurePath, strategyComparison, qualityComparison, ...
    options.FigureVisible);

runInfo = struct;
runInfo.runType = "monthly_quality_mode_comparison";
runInfo.runId = options.RunId;
runInfo.literalDirectory = literalDirectory;
runInfo.excludeDirectory = excludeDirectory;
runInfo.literalMode = "release_literal";
runInfo.excludeMode = "exclude_flagged_pv";
runInfo.strategies = strategies;
runInfo.sourceFiles = struct( ...
    "summary", "monthly_summary.csv", ...
    "quality", "monthly_quality_status.csv", ...
    "metrics", "monthly_metrics.csv");
runInfo.strategyComparison = strategyComparison;
runInfo.qualityComparison = qualityComparison;
[manifest, manifestPath] = write_run_manifest(runDirectory, runInfo);

report = struct;
report.runDirectory = runDirectory;
report.strategyPath = strategyPath;
report.qualityPath = qualityPath;
report.figurePath = figurePath;
report.manifestPath = manifestPath;
report.strategyComparison = strategyComparison;
report.qualityComparison = qualityComparison;
report.manifest = manifest;
end

function monthly = readMonthlyRun(directory, mode, expectedStrategies)
if ~isfolder(directory)
    error("StoreNet:MissingMonthlyRun", ...
        "Monthly %s directory does not exist: %s", mode, directory);
end
summaryPath = fullfile(directory, "monthly_summary.csv");
qualityPath = fullfile(directory, "monthly_quality_status.csv");
metricsPath = fullfile(directory, "monthly_metrics.csv");
requireFile(summaryPath);
requireFile(qualityPath);
requireFile(metricsPath);

summary = readtable(summaryPath, TextType="string");
quality = readtable(qualityPath, TextType="string");
metrics = readtable(metricsPath, TextType="string");
requireColumns(summary, ["Strategy", "SuccessfulDays", ...
    "MeanSavingsPercent", "MeanPeakImportKW"], summaryPath);
requireColumns(quality, ["Day", "Status"], qualityPath);
requireColumns(metrics, ["Day", "Strategy", "Status"], metricsPath);

summary.Strategy = string(summary.Strategy);
metrics.Strategy = string(metrics.Strategy);
validateStrategies(summary.Strategy, expectedStrategies, summaryPath, true);
validateStrategies(metrics.Strategy, expectedStrategies, metricsPath, false);
[~, locations] = ismember(expectedStrategies, summary.Strategy);
summary = summary(locations, :);

monthly = struct;
monthly.mode = mode;
monthly.directory = directory;
monthly.summary = summary;
monthly.quality = quality;
monthly.metrics = metrics;
end

function requireFile(path)
if ~isfile(path)
    error("StoreNet:MissingMonthlyFile", ...
        "Required monthly reporting file is missing: %s", path);
end
end

function requireColumns(value, required, path)
available = string(value.Properties.VariableNames);
missing = required(~ismember(required, available));
if ~isempty(missing)
    error("StoreNet:InvalidMonthlyReportingFile", ...
        "File %s is missing required column(s): %s.", ...
        path, strjoin(missing, ", "));
end
end

function validateStrategies(values, expected, path, requireSingleRow)
values = string(values(:));
observed = unique(values, "stable");
hasExactSet = numel(observed) == numel(expected) && ...
    all(ismember(expected, observed)) && all(ismember(observed, expected));
hasSingleRows = ~requireSingleRow || ...
    (numel(values) == numel(expected) && numel(unique(values)) == numel(expected));
if ~hasExactSet || ~hasSingleRows
    error("StoreNet:InvalidReportingStrategies", ...
        "File %s must contain exactly the fixed strategies: %s.", ...
        path, strjoin(expected, ", "));
end
end

function comparison = buildStrategyComparison(literal, excluded, strategies)
literalSuccessfulDays = double(literal.SuccessfulDays);
excludeSuccessfulDays = double(excluded.SuccessfulDays);
literalMeanSavingsPercent = double(literal.MeanSavingsPercent);
excludeMeanSavingsPercent = double(excluded.MeanSavingsPercent);
literalMeanPeakImportKW = double(literal.MeanPeakImportKW);
excludeMeanPeakImportKW = double(excluded.MeanPeakImportKW);
comparison = table(strategies(:), literalSuccessfulDays, ...
    excludeSuccessfulDays, literalMeanSavingsPercent, ...
    excludeMeanSavingsPercent, literalMeanPeakImportKW, ...
    excludeMeanPeakImportKW, ...
    excludeMeanSavingsPercent - literalMeanSavingsPercent, ...
    excludeMeanPeakImportKW - literalMeanPeakImportKW, ...
    VariableNames=["Strategy", "LiteralSuccessfulDays", ...
    "ExcludeSuccessfulDays", "LiteralMeanSavingsPercent", ...
    "ExcludeMeanSavingsPercent", "LiteralMeanPeakImportKW", ...
    "ExcludeMeanPeakImportKW", "SavingsDifferencePercentagePoints", ...
    "PeakDifferenceKW"]);
end

function comparison = buildQualityComparison(literal, excluded)
mode = [literal.mode; excluded.mode];
requestedDays = [height(literal.quality); height(excluded.quality)];
passedDays = [countStatus(literal.quality.Status, "passed"); ...
    countStatus(excluded.quality.Status, "passed")];
rejectedDays = requestedDays - passedDays;
solverFailedRows = [countStatus(literal.metrics.Status, "failed"); ...
    countStatus(excluded.metrics.Status, "failed")];
comparison = table(mode, requestedDays, passedDays, rejectedDays, ...
    solverFailedRows, VariableNames=["Mode", "RequestedDays", ...
    "PassedDays", "RejectedDays", "SolverFailedRows"]);
end

function count = countStatus(values, expected)
count = nnz(lower(strtrim(string(values))) == lower(expected));
end

function writeComparisonFigure(path, strategy, quality, visible)
visibility = "off";
if visible
    visibility = "on";
end
figureHandle = figure(Visible=visibility, Color="w", ...
    Position=[100, 100, 1400, 850]);
cleaner = onCleanup(@() close(figureHandle));
layout = tiledlayout(figureHandle, 2, 2, Padding="compact", ...
    TileSpacing="compact");
modeNames = ["Release literal", "Exclude flagged PV"];
strategyLabels = replace(strategy.Strategy, "_", "-");

savingsAxes = nexttile(layout);
savingsBars = bar(savingsAxes, ...
    [strategy.LiteralMeanSavingsPercent, ...
    strategy.ExcludeMeanSavingsPercent], "grouped");
setComparisonBarColors(savingsBars);
savingsAxes.XTick = 1:height(strategy);
savingsAxes.XTickLabel = strategyLabels;
ylabel(savingsAxes, "Mean bill savings (%)");
title(savingsAxes, "Monthly mean savings");
grid(savingsAxes, "on");
savingsLegend = legend(savingsAxes, modeNames, ...
    Location="northoutside", Orientation="horizontal");
applyPublicationAxesStyle(savingsAxes);
applyPublicationLegendStyle(savingsLegend);

peakAxes = nexttile(layout);
peakBars = bar(peakAxes, [strategy.LiteralMeanPeakImportKW, ...
    strategy.ExcludeMeanPeakImportKW], "grouped");
setComparisonBarColors(peakBars);
peakAxes.XTick = 1:height(strategy);
peakAxes.XTickLabel = strategyLabels;
ylabel(peakAxes, "Mean peak import (kW)");
title(peakAxes, "Monthly mean peak import");
grid(peakAxes, "on");
peakLegend = legend(peakAxes, modeNames, ...
    Location="northoutside", Orientation="horizontal");
applyPublicationAxesStyle(peakAxes);
applyPublicationLegendStyle(peakLegend);

successAxes = nexttile(layout);
successBars = bar(successAxes, [strategy.LiteralSuccessfulDays, ...
    strategy.ExcludeSuccessfulDays], "grouped");
setComparisonBarColors(successBars);
successAxes.XTick = 1:height(strategy);
successAxes.XTickLabel = strategyLabels;
ylabel(successAxes, "Successful solver days");
title(successAxes, "Usable strategy-day results");
grid(successAxes, "on");
addUpperMargin(successAxes, [strategy.LiteralSuccessfulDays; ...
    strategy.ExcludeSuccessfulDays]);
successLegend = legend(successAxes, modeNames, ...
    Location="northoutside", Orientation="horizontal");
applyPublicationAxesStyle(successAxes);
applyPublicationLegendStyle(successLegend);

qualityAxes = nexttile(layout);
qualityBars = bar(qualityAxes, [quality.PassedDays, quality.RejectedDays, ...
    quality.SolverFailedRows], "grouped");
qualityBars(1).FaceColor = [0.20, 0.60, 0.40];
qualityBars(2).FaceColor = [0.85, 0.33, 0.10];
qualityBars(3).FaceColor = [0.49, 0.18, 0.56];
qualityAxes.XTick = 1:height(quality);
qualityAxes.XTickLabel = modeNames;
ylabel(qualityAxes, "Count");
title(qualityAxes, "Quality and solver status");
grid(qualityAxes, "on");
addUpperMargin(qualityAxes, [quality.PassedDays; quality.RejectedDays; ...
    quality.SolverFailedRows]);
qualityLegend = legend(qualityAxes, ...
    ["Passed days", "Rejected days", "Failed solver rows"], ...
    Location="northoutside", Orientation="horizontal");
applyPublicationAxesStyle(qualityAxes);
applyPublicationLegendStyle(qualityLegend);

exportgraphics(figureHandle, path, Resolution=300, BackgroundColor="white");
end

function addUpperMargin(axesHandle, values)
upperValue = max(double(values), [], "all");
if isfinite(upperValue) && upperValue > 0
    ylim(axesHandle, [0, 1.10 * upperValue]);
end
end

function setComparisonBarColors(barHandles)
barHandles(1).FaceColor = [0.00, 0.45, 0.74];
barHandles(2).FaceColor = [0.85, 0.33, 0.10];
end

function applyPublicationAxesStyle(axesHandle)
darkColor = [0.12, 0.14, 0.16];
gridColor = [0.68, 0.71, 0.74];
set(axesHandle, Color="w", XColor=darkColor, YColor=darkColor, ...
    ZColor=darkColor, GridColor=gridColor, GridAlpha=0.35, ...
    MinorGridColor=gridColor, MinorGridAlpha=0.20, ...
    FontName="Helvetica", FontSize=10, LineWidth=0.8, ...
    Box="on", Layer="top");
axesHandle.Title.Color = darkColor;
axesHandle.XLabel.Color = darkColor;
axesHandle.YLabel.Color = darkColor;
end

function applyPublicationLegendStyle(legendHandle)
set(legendHandle, Color="w", TextColor=[0.12, 0.14, 0.16], ...
    EdgeColor=[0.68, 0.71, 0.74], FontName="Helvetica", FontSize=9);
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
if isfolder(directory)
    contents = dir(directory);
    contents = contents(~ismember(string({contents.name}), [".", ".."])) ;
    if ~isempty(contents)
        error("StoreNet:RunDirectoryExists", ...
            "Refusing to overwrite nonempty run directory: %s", directory);
    end
else
    mkdir(directory);
end
end
