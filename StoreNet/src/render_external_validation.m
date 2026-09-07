function artifacts = render_external_validation(resultDirectory, options)
%RENDER_EXTERNAL_VALIDATION Summarize and plot an audited external run.
%   ARTIFACTS = RENDER_EXTERNAL_VALIDATION(RESULTDIRECTORY) reads the
%   primary, PS-reference, and epsilon-frontier CSV files produced by
%   RUN_EXTERNAL_VALIDATION. It writes two descriptive summary tables and
%   one publication-style PNG without changing any solver result.

arguments
    resultDirectory (1, 1) string
    options.FigureVisible (1, 1) logical = false
    options.FigureFileName (1, 1) string = "external_validation.png"
    options.Overwrite (1, 1) logical = false
end

if ~isfolder(resultDirectory)
    error("StoreNet:MissingExternalResultDirectory", ...
        "External result directory is missing: %s", resultDirectory);
end
validateSimpleFileName(options.FigureFileName);

primary = readRequiredTable(resultDirectory, "primary_metrics.csv");
frontierReference = readRequiredTable(resultDirectory, ...
    "frontier_reference_metrics.csv");
frontier = readRequiredTable(resultDirectory, "frontier_metrics.csv");
homeCount = readRequiredHomeCount(resultDirectory);
validateResultTables(primary, frontierReference, frontier);

strategySummary = summarizeStrategies(primary);
frontierSummary = summarizeFrontiers(frontierReference, frontier);
assertFiniteSummary(strategySummary, "strategy summary");
assertFiniteSummary(frontierSummary, "frontier summary");
strategySummaryPath = fullfile(resultDirectory, "strategy_summary.csv");
frontierSummaryPath = fullfile(resultDirectory, "frontier_summary.csv");
figurePath = fullfile(resultDirectory, options.FigureFileName);
targetPaths = [strategySummaryPath, frontierSummaryPath, figurePath];
assertTargetsAvailable(targetPaths, options.Overwrite);

stagingDirectory = string(tempname(resultDirectory));
mkdir(stagingDirectory);
stagingCleaner = onCleanup(@() removeDirectoryIfPresent(stagingDirectory));
stagedPaths = [fullfile(stagingDirectory, "strategy_summary.csv"), ...
    fullfile(stagingDirectory, "frontier_summary.csv"), ...
    fullfile(stagingDirectory, "external_validation.png")];
writetable(strategySummary, stagedPaths(1));
writetable(frontierSummary, stagedPaths(2));
writeExternalFigure(stagedPaths(3), primary, frontier, ...
    options.FigureVisible, homeCount);
assertStagedArtifacts(stagedPaths);
publishArtifacts(stagedPaths, targetPaths, options.Overwrite);
clear stagingCleaner

artifacts = struct;
artifacts.strategySummaryPath = strategySummaryPath;
artifacts.frontierSummaryPath = frontierSummaryPath;
artifacts.figurePath = figurePath;
artifacts.strategySummary = strategySummary;
artifacts.frontierSummary = frontierSummary;
end

function validateSimpleFileName(fileName)
if strlength(fileName) == 0 || any(contains(fileName, ["/", "\\"])) || ...
        contains(fileName, "..") || ~endsWith(lower(fileName), ".png")
    error("StoreNet:InvalidExternalFigureName", ...
        "FigureFileName must be a simple PNG file name.");
end
end

function value = readRequiredTable(directory, fileName)
path = fullfile(directory, fileName);
if ~isfile(path)
    error("StoreNet:MissingExternalResultFile", ...
        "Required external result file is missing: %s", path);
end
value = readtable(path, TextType="string");
end

function homeCount = readRequiredHomeCount(directory)
path = fullfile(directory, "manifest.json");
if ~isfile(path)
    error("StoreNet:MissingExternalResultFile", ...
        "Required external result file is missing: %s", path);
end
try
    manifest = jsondecode(fileread(path));
    homeCount = double(manifest.experiment.configuration.nHomes);
catch exception
    error("StoreNet:InvalidExternalManifest", ...
        "Cannot read experiment.configuration.nHomes from %s: %s", ...
        path, exception.message);
end
if ~isscalar(homeCount) || ~isfinite(homeCount) || homeCount < 1 || ...
        homeCount ~= floor(homeCount)
    error("StoreNet:InvalidExternalManifest", ...
        "The external manifest nHomes value must be a positive integer.");
end
end

function validateResultTables(primary, frontierReference, frontier)
requiredPrimary = ["Month", "Day", "Strategy", "Status", ...
    "SavingsPercent", "PeakImportKW", "P0KW"];
requiredFrontierReference = ["Month", "Day", "Strategy", "Status", ...
    "P0KW", "PeakImportKW"];
requiredFrontier = ["Month", "Day", "Strategy", "Status", "Alpha", ...
    "PeakImportKW", "OptimizedBillEUR", "SavingsPercent", "P0KW"];
assertVariables(primary, requiredPrimary, "primary_metrics.csv");
assertVariables(frontierReference, requiredFrontierReference, ...
    "frontier_reference_metrics.csv");
assertVariables(frontier, requiredFrontier, "frontier_metrics.csv");
assertNumericVariables(primary, ...
    ["Month", "SavingsPercent", "PeakImportKW", "P0KW"], ...
    "primary_metrics.csv");
assertNumericVariables(frontierReference, ...
    ["Month", "P0KW", "PeakImportKW"], ...
    "frontier_reference_metrics.csv");
assertNumericVariables(frontier, ...
    ["Month", "Alpha", "PeakImportKW", "OptimizedBillEUR", ...
    "SavingsPercent", "P0KW"], "frontier_metrics.csv");
assertStringVariables(primary, ["Strategy", "Status"], ...
    "primary_metrics.csv");
assertStringVariables(frontierReference, ["Strategy", "Status"], ...
    "frontier_reference_metrics.csv");
assertStringVariables(frontier, ["Strategy", "Status"], ...
    "frontier_metrics.csv");
assertDatetimeVariable(primary, "Day", "primary_metrics.csv");
assertDatetimeVariable(frontierReference, "Day", ...
    "frontier_reference_metrics.csv");
assertDatetimeVariable(frontier, "Day", "frontier_metrics.csv");

expectedStrategies = ["SH_BM"; "VPP_BM"; "IMPROVED_PEAK_GUARD"];
primaryPanel = groupsummary(primary, ["Month", "Strategy"]);
validPrimary = height(primary) == 36 && all(primary.Status == "ok") && ...
    isequal(sort(unique(primary.Month)), (1:12).') && ...
    isequal(sort(unique(primary.Strategy)), sort(expectedStrategies)) && ...
    height(primaryPanel) == 36 && all(primaryPanel.GroupCount == 1);
validReference = height(frontierReference) == 4 && ...
    all(frontierReference.Status == "ok") && ...
    all(frontierReference.Strategy == "PS") && ...
    isequal(sort(frontierReference.Month), [3; 6; 9; 12]);
frontierPanel = groupsummary(frontier, ["Month", "Alpha"]);
actualFrontierGrid = sortrows(frontier(:, ["Month", "Alpha"]), ...
    ["Month", "Alpha"]);
expectedFrontierGrid = table(repelem([3; 6; 9; 12], 5), ...
    repmat([0; 0.25; 0.5; 0.75; 1], 4, 1), ...
    VariableNames=["Month", "Alpha"]);
validFrontier = height(frontier) == 20 && all(frontier.Status == "ok") && ...
    all(frontier.Strategy == "IMPROVED_PEAK_GUARD") && ...
    isequal(sort(unique(frontier.Month)), [3; 6; 9; 12]) && ...
    height(frontierPanel) == 20 && all(frontierPanel.GroupCount == 1) && ...
    isequal(actualFrontierGrid, expectedFrontierGrid);
if ~(validPrimary && validReference && validFrontier)
    error("StoreNet:InvalidExternalResultPanel", ...
        "External result tables do not contain the audited 36 + 4 + 20 ok-row panels.");
end

numericValues = [primary.SavingsPercent; primary.PeakImportKW; primary.P0KW; ...
    frontierReference.P0KW; frontierReference.PeakImportKW; ...
    frontier.Alpha; frontier.PeakImportKW; frontier.OptimizedBillEUR; ...
    frontier.SavingsPercent; frontier.P0KW];
if any(~isfinite(numericValues)) || any(primary.P0KW <= 0) || ...
        any(frontierReference.P0KW <= 0) || any(frontier.P0KW <= 0) || ...
        any(primary.PeakImportKW < 0) || ...
        any(frontierReference.PeakImportKW < 0) || ...
        any(frontier.PeakImportKW < 0) || ...
        any(frontier.OptimizedBillEUR <= 0)
    error("StoreNet:InvalidExternalResultValues", ...
        "External result tables contain nonfinite or nonpositive required values.");
end
if ~hasConsistentDaysAndBaselines(primary, frontierReference, frontier)
    error("StoreNet:InvalidExternalResultPanel", ...
        "External result tables do not share consistent dates and P0 baselines.");
end
end

function assertVariables(value, required, fileName)
missing = required(~ismember(required, string(value.Properties.VariableNames)));
if ~isempty(missing)
    error("StoreNet:InvalidExternalResultSchema", ...
        "%s is missing variable(s): %s.", fileName, strjoin(missing, ", "));
end
end

function assertNumericVariables(value, required, fileName)
for variableIndex = 1:numel(required)
    variableName = required(variableIndex);
    column = value.(variableName);
    if ~isnumeric(column) || ~isreal(column) || ~iscolumn(column)
        error("StoreNet:InvalidExternalResultSchema", ...
            "%s variable %s must be a real numeric column.", ...
            fileName, variableName);
    end
end
end

function assertStringVariables(value, required, fileName)
for variableIndex = 1:numel(required)
    variableName = required(variableIndex);
    if ~isstring(value.(variableName)) || ~iscolumn(value.(variableName))
        error("StoreNet:InvalidExternalResultSchema", ...
            "%s variable %s must be a string column.", ...
            fileName, variableName);
    end
end
end

function assertDatetimeVariable(value, required, fileName)
if ~isdatetime(value.(required)) || ~iscolumn(value.(required)) || ...
        any(isnat(value.(required)))
    error("StoreNet:InvalidExternalResultSchema", ...
        "%s variable %s must be a finite datetime column.", ...
        fileName, required);
end
end

function consistent = hasConsistentDaysAndBaselines( ...
        primary, frontierReference, frontier)
toleranceKW = 1e-6;
consistent = true;
for monthNumber = 1:12
    primaryRows = primary(primary.Month == monthNumber, :);
    consistent = consistent && isscalar(unique(primaryRows.Day)) && ...
        all(month(primaryRows.Day) == monthNumber) && ...
        max(primaryRows.P0KW) - min(primaryRows.P0KW) <= toleranceKW;
end
frontierMonths = [3, 6, 9, 12];
for monthIndex = 1:numel(frontierMonths)
    monthNumber = frontierMonths(monthIndex);
    primaryRows = primary(primary.Month == monthNumber, :);
    referenceRows = frontierReference( ...
        frontierReference.Month == monthNumber, :);
    frontierRows = frontier(frontier.Month == monthNumber, :);
    combinedDays = [primaryRows.Day; referenceRows.Day; frontierRows.Day];
    combinedP0KW = [primaryRows.P0KW; referenceRows.P0KW; ...
        frontierRows.P0KW];
    consistent = consistent && isscalar(unique(combinedDays)) && ...
        all(month(combinedDays) == monthNumber) && ...
        max(combinedP0KW) - min(combinedP0KW) <= toleranceKW;
end
end

function summary = summarizeStrategies(primary)
strategies = ["SH_BM"; "VPP_BM"; "IMPROVED_PEAK_GUARD"];
medianSavings = nan(3, 1);
firstQuartileSavings = nan(3, 1);
minimumSavings = nan(3, 1);
maximumSavings = nan(3, 1);
medianPeakRatio = nan(3, 1);
maximumPeakRatio = nan(3, 1);
monthsAboveP0 = zeros(3, 1);
for strategyIndex = 1:numel(strategies)
    rows = primary(primary.Strategy == strategies(strategyIndex), :);
    savings = rows.SavingsPercent;
    peakRatio = rows.PeakImportKW ./ rows.P0KW;
    medianSavings(strategyIndex) = median(savings);
    firstQuartileSavings(strategyIndex) = quantile(savings, 0.25);
    minimumSavings(strategyIndex) = min(savings);
    maximumSavings(strategyIndex) = max(savings);
    medianPeakRatio(strategyIndex) = median(peakRatio);
    maximumPeakRatio(strategyIndex) = max(peakRatio);
    monthsAboveP0(strategyIndex) = nnz(peakRatio > 1 + 1e-6);
end
summary = table(strategies, medianSavings, firstQuartileSavings, ...
    minimumSavings, maximumSavings, medianPeakRatio, maximumPeakRatio, ...
    monthsAboveP0, VariableNames=["Strategy", "MedianSavingsPercent", ...
    "FirstQuartileSavingsPercent", "MinimumSavingsPercent", ...
    "MaximumSavingsPercent", "MedianPeakRatioToP0", ...
    "MaximumPeakRatioToP0", "MonthsAboveP0"]);
end

function summary = summarizeFrontiers(reference, frontier)
months = [3; 6; 9; 12];
p0KW = nan(4, 1);
pminKW = nan(4, 1);
technicalPeakReduction = nan(4, 1);
alpha1Bill = nan(4, 1);
alpha0Bill = nan(4, 1);
billPremium = nan(4, 1);
alpha1Savings = nan(4, 1);
alpha0Savings = nan(4, 1);
savingsChange = nan(4, 1);
for monthIndex = 1:numel(months)
    monthNumber = months(monthIndex);
    referenceRow = reference(reference.Month == monthNumber, :);
    alpha1 = frontier(frontier.Month == monthNumber & frontier.Alpha == 1, :);
    alpha0 = frontier(frontier.Month == monthNumber & frontier.Alpha == 0, :);
    p0KW(monthIndex) = referenceRow.P0KW;
    pminKW(monthIndex) = referenceRow.PeakImportKW;
    technicalPeakReduction(monthIndex) = 100 * ...
        (p0KW(monthIndex) - pminKW(monthIndex)) / p0KW(monthIndex);
    alpha1Bill(monthIndex) = alpha1.OptimizedBillEUR;
    alpha0Bill(monthIndex) = alpha0.OptimizedBillEUR;
    billPremium(monthIndex) = 100 * ...
        (alpha0Bill(monthIndex) / alpha1Bill(monthIndex) - 1);
    alpha1Savings(monthIndex) = alpha1.SavingsPercent;
    alpha0Savings(monthIndex) = alpha0.SavingsPercent;
    savingsChange(monthIndex) = ...
        alpha0Savings(monthIndex) - alpha1Savings(monthIndex);
end
summary = table(months, p0KW, pminKW, technicalPeakReduction, ...
    alpha1Bill, alpha0Bill, billPremium, alpha1Savings, alpha0Savings, ...
    savingsChange, VariableNames=["Month", "P0KW", "PminKW", ...
    "TechnicalPeakReductionPercent", "Alpha1BillEUR", "Alpha0BillEUR", ...
    "Alpha0BillPremiumPercent", "Alpha1SavingsPercent", ...
    "Alpha0SavingsPercent", "SavingsChangePercentagePoints"]);
end

function assertFiniteSummary(summary, name)
numericNames = string(summary.Properties.VariableNames( ...
    varfun(@isnumeric, summary, OutputFormat="uniform")));
for variableIndex = 1:numel(numericNames)
    if any(~isfinite(summary.(numericNames(variableIndex))))
        error("StoreNet:InvalidExternalSummary", ...
            "The %s contains a nonfinite %s value.", ...
            name, numericNames(variableIndex));
    end
end
end

function writeExternalFigure(path, primary, frontier, visible, homeCount)
visibility = "off";
if visible
    visibility = "on";
end
figureHandle = figure(Visible=visibility, Color="w", ...
    Position=[100, 100, 1450, 900]);
cleaner = onCleanup(@() closeIfValid(figureHandle));
layout = tiledlayout(figureHandle, 2, 2, Padding="compact", ...
    TileSpacing="compact");
strategies = ["SH_BM", "VPP_BM", "IMPROVED_PEAK_GUARD"];
labels = ["SH-BM", "VPP-BM", "Peak Guard"];
colors = [0.20, 0.45, 0.75; 0.86, 0.37, 0.15; 0.16, 0.62, 0.42];
lineStyles = ["-", "-", "--"];
markers = ["o", "s", "d"];

savingsAxes = nexttile(layout);
hold(savingsAxes, "on");
for strategyIndex = 1:numel(strategies)
    rows = sortrows(primary(primary.Strategy == strategies(strategyIndex), :), ...
        "Month");
    plot(savingsAxes, rows.Month, rows.SavingsPercent, ...
        LineStyle=lineStyles(strategyIndex), ...
        Marker=markers(strategyIndex), ...
        Color=colors(strategyIndex, :), LineWidth=1.7, MarkerSize=5, ...
        DisplayName=labels(strategyIndex));
end
hold(savingsAxes, "off");
formatMonthlyAxes(savingsAxes, "Bill savings (%)", ...
    "Monthly fixed-policy savings");
legend(savingsAxes, Location="best", Box="on");

peakAxes = nexttile(layout);
hold(peakAxes, "on");
for strategyIndex = 1:numel(strategies)
    rows = sortrows(primary(primary.Strategy == strategies(strategyIndex), :), ...
        "Month");
    plot(peakAxes, rows.Month, rows.PeakImportKW ./ rows.P0KW, ...
        LineStyle=lineStyles(strategyIndex), ...
        Marker=markers(strategyIndex), ...
        Color=colors(strategyIndex, :), LineWidth=1.7, MarkerSize=5, ...
        DisplayName=labels(strategyIndex));
end
yline(peakAxes, 1, "--", "No-battery P0", Color=[0.25, 0.25, 0.25], ...
    HandleVisibility="off");
hold(peakAxes, "off");
formatMonthlyAxes(peakAxes, "Peak import / P0", ...
    "Peak relative to no-battery baseline");
legend(peakAxes, Location="best", Box="on");

frontierAxes = nexttile(layout, [1, 2]);
monthList = [3, 6, 9, 12];
monthLabels = ["March", "June", "September", "December"];
frontierColors = lines(numel(monthList));
hold(frontierAxes, "on");
for monthIndex = 1:numel(monthList)
    rows = frontier(frontier.Month == monthList(monthIndex), :);
    rows = sortrows(rows, "Alpha", "descend");
    referenceBill = rows.OptimizedBillEUR(rows.Alpha == 1);
    peakReduction = 100 * (rows.P0KW - rows.PeakImportKW) ./ rows.P0KW;
    billPremium = 100 * (rows.OptimizedBillEUR ./ referenceBill - 1);
    plot(frontierAxes, peakReduction, billPremium, "o-", ...
        Color=frontierColors(monthIndex, :), LineWidth=1.8, MarkerSize=6, ...
        DisplayName=monthLabels(monthIndex));
end
hold(frontierAxes, "off");
grid(frontierAxes, "on");
xlabel(frontierAxes, "Peak reduction from P0 (%)");
ylabel(frontierAxes, "Bill premium versus alpha=1 (%)");
title(frontierAxes, "Seasonal epsilon-constraint trade-off");
legend(frontierAxes, Location="best", Box="on");
applyAxesStyle(frontierAxes);
title(layout, sprintf( ...
    "Ausgrid external validation: %d homes, fixed StoreNet policy", ...
    homeCount), ...
    FontWeight="bold", FontSize=15);

[directory, ~, extension] = fileparts(path);
temporaryPath = string(tempname(directory)) + extension;
temporaryCleaner = onCleanup(@() deleteIfPresent(temporaryPath));
exportgraphics(figureHandle, temporaryPath, Resolution=300, ...
    BackgroundColor="white");
movefile(temporaryPath, path, "f");
clear temporaryCleaner cleaner
end

function formatMonthlyAxes(axesHandle, yLabelText, titleText)
grid(axesHandle, "on");
xlim(axesHandle, [0.5, 12.5]);
xticks(axesHandle, 1:12);
xlabel(axesHandle, "Calendar month");
ylabel(axesHandle, yLabelText);
title(axesHandle, titleText);
applyAxesStyle(axesHandle);
end

function applyAxesStyle(axesHandle)
set(axesHandle, Color="w", XColor=[0.12, 0.14, 0.16], ...
    YColor=[0.12, 0.14, 0.16], GridColor=[0.68, 0.71, 0.74], ...
    GridAlpha=0.35, FontName="Helvetica", FontSize=10, ...
    LineWidth=0.8, Box="on", Layer="top");
end

function assertTargetsAvailable(paths, overwrite)
if any(isfolder(paths))
    error("StoreNet:ExternalArtifactPathConflict", ...
        "An external-validation artifact target is an existing directory.");
end
if ~overwrite && any(isfile(paths))
    error("StoreNet:ExternalArtifactExists", ...
        "Refusing to overwrite an existing external-validation artifact.");
end
end

function assertStagedArtifacts(paths)
for pathIndex = 1:numel(paths)
    information = dir(paths(pathIndex));
    if ~isfile(paths(pathIndex)) || isempty(information) || ...
            information.bytes < 1
        error("StoreNet:InvalidStagedExternalArtifact", ...
            "A staged external-validation artifact is missing or empty: %s", ...
            paths(pathIndex));
    end
end
end

function publishArtifacts(stagedPaths, targetPaths, overwrite)
targetDirectory = string(fileparts(targetPaths(1)));
backupDirectory = string(tempname(targetDirectory));
mkdir(backupDirectory);
backupPaths = fullfile(backupDirectory, ...
    "artifact_" + string(1:numel(targetPaths)));
backedUp = false(size(targetPaths));
published = false(size(targetPaths));
try
    for pathIndex = 1:numel(targetPaths)
        rejectDirectoryTarget(targetPaths(pathIndex));
        if isfile(targetPaths(pathIndex))
            if ~overwrite
                error("StoreNet:ExternalArtifactExists", ...
                    "An external-validation artifact appeared during publication.");
            end
            moveArtifact(targetPaths(pathIndex), backupPaths(pathIndex));
            backedUp(pathIndex) = true;
        end
    end
    for pathIndex = 1:numel(targetPaths)
        rejectDirectoryTarget(targetPaths(pathIndex));
        moveArtifact(stagedPaths(pathIndex), targetPaths(pathIndex));
        published(pathIndex) = true;
    end
catch exception
    rollbackComplete = rollbackArtifacts( ...
        targetPaths, backupPaths, published, backedUp);
    if rollbackComplete
        removeDirectoryIfPresent(backupDirectory);
    else
        warning("StoreNet:ExternalArtifactBackupPreserved", ...
            "Rollback was incomplete; backups are preserved in %s.", ...
            backupDirectory);
    end
    rethrow(exception)
end
removeDirectoryIfPresent(backupDirectory);
end

function moveArtifact(source, destination)
[status, message] = movefile(source, destination);
if ~status
    error("StoreNet:ExternalArtifactPublishFailed", ...
        "Cannot publish external-validation artifact %s: %s", ...
        destination, message);
end
if ~isfile(destination) || isfolder(destination)
    recoverArtifactMovedIntoDirectory(source, destination);
    error("StoreNet:ExternalArtifactPublishFailed", ...
        "Artifact destination is not a regular file after publication: %s", ...
        destination);
end
end

function rejectDirectoryTarget(path)
if isfolder(path)
    error("StoreNet:ExternalArtifactPathConflict", ...
        "An external-validation artifact target became a directory: %s", ...
        path);
end
end

function recoverArtifactMovedIntoDirectory(source, destination)
if ~isfolder(destination)
    return
end
[~, name, extension] = fileparts(source);
nestedPath = fullfile(destination, name + extension);
if isfile(nestedPath) && ~isfile(source)
    [recovered, message] = movefile(nestedPath, source);
    if ~recovered
        warning("StoreNet:ExternalArtifactRecoveryFailed", ...
            "A staged artifact remains at %s after a target-path race: %s", ...
            nestedPath, message);
    end
end
end

function complete = rollbackArtifacts( ...
        targetPaths, backupPaths, published, backedUp)
complete = true;
for pathIndex = numel(targetPaths):-1:1
    if published(pathIndex) && isfile(targetPaths(pathIndex))
        try
            delete(targetPaths(pathIndex));
        catch exception
            complete = false;
            warning("StoreNet:ExternalArtifactRollbackFailed", ...
                "Cannot remove newly published %s during rollback: %s", ...
                targetPaths(pathIndex), exception.message);
        end
    end
end
for pathIndex = numel(targetPaths):-1:1
    if backedUp(pathIndex)
        if ~isfile(backupPaths(pathIndex))
            complete = false;
            warning("StoreNet:ExternalArtifactRollbackFailed", ...
                "Expected rollback backup is missing: %s", ...
                backupPaths(pathIndex));
        elseif isfolder(targetPaths(pathIndex)) || ...
                isfile(targetPaths(pathIndex))
            complete = false;
            warning("StoreNet:ExternalArtifactRollbackFailed", ...
                "Cannot restore %s because the target path is occupied; " + ...
                "the backup is preserved at %s.", ...
                targetPaths(pathIndex), backupPaths(pathIndex));
        else
            [restored, message] = movefile( ...
                backupPaths(pathIndex), targetPaths(pathIndex));
            validDestination = restored && ...
                isfile(targetPaths(pathIndex)) && ...
                ~isfolder(targetPaths(pathIndex));
            if ~validDestination
                recoverArtifactMovedIntoDirectory( ...
                    backupPaths(pathIndex), targetPaths(pathIndex));
                complete = false;
                warning("StoreNet:ExternalArtifactRollbackFailed", ...
                    "Cannot restore %s after publication failure: %s", ...
                    targetPaths(pathIndex), message);
            end
        end
    end
end
end

function closeIfValid(figureHandle)
if isgraphics(figureHandle)
    close(figureHandle);
end
end

function removeDirectoryIfPresent(path)
if isfolder(path)
    rmdir(path, "s");
end
end

function deleteIfPresent(path)
if isfile(path)
    delete(path);
end
end
