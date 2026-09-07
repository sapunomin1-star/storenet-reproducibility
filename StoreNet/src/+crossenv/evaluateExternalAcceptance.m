function report = evaluateExternalAcceptance(primary, frontier, tolerances)
%EVALUATEEXTERNALACCEPTANCE Apply the frozen cross-environment acceptance gate.
%   REPORT = crossenv.evaluateExternalAcceptance(PRIMARY, FRONTIER,
%   TOLERANCES) evaluates already-computed result tables. This function is
%   deliberately post hoc: it does not solve, repair, filter, or impute any
%   result.
%
%   PRIMARY must contain these variables:
%     Month, Day, Strategy, Status, EffectiveCapKW, PeakImportKW,
%     SavingsPercent, EnergyBalanceResidualKW, TerminalSocErrorKWh,
%     SimultaneousChargeDischargeKW, MinimumExitFlag.
%
%   FRONTIER must contain the PRIMARY variables and additionally:
%     Alpha, RequestedCapKW, OptimizedBillEUR.
%
%   TOLERANCES is a scalar structure with finite, nonnegative scalar fields:
%     capKW, energyBalanceResidualKW, terminalSocErrorKWh,
%     simultaneousChargeDischargeKW, peakMonotonicKW, billMonotonicEUR,
%     alpha, minimumExitFlag.
%
%   The gate fails closed. A malformed or incomplete input produces a report
%   whose overallCrossEnvironmentRobust field is false and whose
%   failureReasons field explains which evidence was not demonstrated.

requiredPrimary = ["Month", "Day", "Strategy", "Status", ...
    "EffectiveCapKW", "PeakImportKW", "SavingsPercent", ...
    "EnergyBalanceResidualKW", "TerminalSocErrorKWh", ...
    "SimultaneousChargeDischargeKW", "MinimumExitFlag"];
requiredFrontier = [requiredPrimary, "Alpha", "RequestedCapKW", ...
    "OptimizedBillEUR"];

criteria = initializeCriteria();
statistics = initializeStatistics(primary, frontier);
failureReasons = strings(0, 1);

[criteria.tolerancesValid, checkedTolerances, toleranceMessage] = ...
    validateTolerances(tolerances);
if ~criteria.tolerancesValid
    failureReasons(end + 1, 1) = toleranceMessage;
end

[criteria.primarySchemaValid, missingPrimary] = ...
    validateTableSchema(primary, requiredPrimary);
if ~criteria.primarySchemaValid
    failureReasons(end + 1, 1) = schemaFailureMessage( ...
        "primary", missingPrimary, istable(primary));
end

[criteria.frontierSchemaValid, missingFrontier] = ...
    validateTableSchema(frontier, requiredFrontier);
if ~criteria.frontierSchemaValid
    failureReasons(end + 1, 1) = schemaFailureMessage( ...
        "frontier", missingFrontier, istable(frontier));
end

if criteria.tolerancesValid && criteria.primarySchemaValid
    [primaryCriteria, statistics] = evaluatePrimary( ...
        primary, checkedTolerances, statistics);
    criteria.primaryPanelComplete = primaryCriteria.panelComplete;
    criteria.primaryAllRowsFeasible = primaryCriteria.allRowsFeasible;
    criteria.peakGuardCapCompliant = primaryCriteria.capCompliant;
    criteria.peakGuardMedianSavingsPositive = ...
        primaryCriteria.medianSavingsPositive;
    criteria.peakGuardQ1SavingsPositive = ...
        primaryCriteria.q1SavingsPositive;
    criteria.pairedMedianPeakDeltaNegative = ...
        primaryCriteria.pairedMedianPeakDeltaNegative;
end

if criteria.tolerancesValid && criteria.frontierSchemaValid
    [frontierCriteria, statistics] = evaluateFrontier( ...
        frontier, checkedTolerances, statistics);
    criteria.frontierPanelComplete = frontierCriteria.panelComplete;
    criteria.frontierAllRowsFeasible = frontierCriteria.allRowsFeasible;
    criteria.frontierRequestedCapsTighten = ...
        frontierCriteria.requestedCapsTighten;
    criteria.frontierPeakMonotonic = frontierCriteria.peakMonotonic;
    criteria.frontierBillMonotonic = frontierCriteria.billMonotonic;
end

failureReasons = appendCriterionFailures(failureReasons, criteria);
failureReasons = unique(failureReasons, "stable");

criterionValues = struct2cell(criteria);
report = struct;
report.criteria = criteria;
report.statistics = statistics;
report.failureReasons = failureReasons;
report.overallCrossEnvironmentRobust = all(cellfun( ...
    @(value) islogical(value) && isscalar(value) && value, ...
    criterionValues));
end

function criteria = initializeCriteria()
criteria = struct;
criteria.tolerancesValid = false;
criteria.primarySchemaValid = false;
criteria.primaryPanelComplete = false;
criteria.primaryAllRowsFeasible = false;
criteria.peakGuardCapCompliant = false;
criteria.peakGuardMedianSavingsPositive = false;
criteria.peakGuardQ1SavingsPositive = false;
criteria.pairedMedianPeakDeltaNegative = false;
criteria.frontierSchemaValid = false;
criteria.frontierPanelComplete = false;
criteria.frontierAllRowsFeasible = false;
criteria.frontierRequestedCapsTighten = false;
criteria.frontierPeakMonotonic = false;
criteria.frontierBillMonotonic = false;
end

function statistics = initializeStatistics(primary, frontier)
statistics = struct;
statistics.primaryRowCount = tableHeightOrZero(primary);
statistics.primaryMonthCount = 0;
statistics.peakGuardRowCount = 0;
statistics.peakGuardCapPassCount = 0;
statistics.peakGuardMedianSavingsPercent = NaN;
statistics.peakGuardQ1SavingsPercent = NaN;
statistics.pairedMonthCount = 0;
statistics.pairedMedianPeakDeltaKW = NaN;
statistics.frontierRowCount = tableHeightOrZero(frontier);
statistics.frontierMonthCount = 0;
statistics.frontierPeakCapPassCount = 0;
statistics.frontierComparisonCount = 0;
statistics.frontierRequestedCapMonotonicPassCount = 0;
statistics.frontierPeakMonotonicPassCount = 0;
statistics.frontierBillMonotonicPassCount = 0;
statistics.frontierMaximumRequestedCapIncreaseKW = NaN;
statistics.frontierMaximumPeakIncreaseKW = NaN;
statistics.frontierMaximumBillDecreaseEUR = NaN;
end

function count = tableHeightOrZero(value)
if istable(value)
    count = height(value);
else
    count = 0;
end
end

function [valid, checked, message] = validateTolerances(tolerances)
fieldNames = ["capKW", "energyBalanceResidualKW", ...
    "terminalSocErrorKWh", "simultaneousChargeDischargeKW", ...
    "peakMonotonicKW", "billMonotonicEUR", "alpha", ...
    "minimumExitFlag"];
checked = struct;
message = "";
valid = isstruct(tolerances) && isscalar(tolerances);
if ~valid
    message = "tolerances must be a scalar structure.";
    return
end

missing = fieldNames(~isfield(tolerances, cellstr(fieldNames)));
if ~isempty(missing)
    valid = false;
    message = "tolerances is missing required field(s): " + ...
        strjoin(missing, ", ") + ".";
    return
end

for index = 1:numel(fieldNames)
    name = fieldNames(index);
    value = tolerances.(name);
    if ~(isnumeric(value) && isreal(value) && isscalar(value) && ...
            isfinite(value) && value >= 0)
        valid = false;
        message = "tolerances." + name + ...
            " must be a finite, nonnegative numeric scalar.";
        return
    end
    checked.(name) = double(value);
end
end

function [valid, missing] = validateTableSchema(value, requiredVariables)
if ~istable(value)
    valid = false;
    missing = requiredVariables;
    return
end
available = string(value.Properties.VariableNames);
missing = requiredVariables(~ismember(requiredVariables, available));
valid = isempty(missing);
end

function message = schemaFailureMessage(label, missing, isTable)
if ~isTable
    message = label + " must be a table.";
elseif isempty(missing)
    message = label + " does not satisfy the required schema.";
else
    message = label + " is missing required variable(s): " + ...
        strjoin(missing, ", ") + ".";
end
end

function [criteria, statistics] = evaluatePrimary(primary, tolerances, statistics)
criteria = struct("panelComplete", false, "allRowsFeasible", false, ...
    "capCompliant", false, "medianSavingsPositive", false, ...
    "q1SavingsPositive", false, ...
    "pairedMedianPeakDeltaNegative", false);

[monthValid, monthValues] = finiteNumericColumn(primary, "Month");
[strategyValid, strategies] = textColumn(primary, "Strategy");
[statusValid, statuses] = textColumn(primary, "Status");
[dayValid, dayKeys, dayMonths] = dayColumn(primary, "Day");

if monthValid
    validCalendarMonths = monthValues == fix(monthValues) & ...
        monthValues >= 1 & monthValues <= 12;
    if all(validCalendarMonths)
        statistics.primaryMonthCount = numel(unique(monthValues));
    end
else
    validCalendarMonths = false(height(primary), 1);
end

expectedStrategies = ["SH_BM"; "VPP_BM"; "IMPROVED_PEAK_GUARD"];
panelReady = monthValid && strategyValid && dayValid && ...
    all(validCalendarMonths) && height(primary) == 36;
if panelReady
    criteria.panelComplete = primaryPanelIsComplete( ...
        monthValues, dayKeys, dayMonths, strategies, expectedStrategies);
end

numericNames = ["PeakImportKW", "SavingsPercent", ...
    "EnergyBalanceResidualKW", "TerminalSocErrorKWh", ...
    "SimultaneousChargeDischargeKW", "MinimumExitFlag"];
[numericValid, numericValues] = finiteNumericColumns(primary, numericNames);

allRowsStatusOk = statusValid && all(lower(strtrim(statuses)) == "ok");
physicalValuesOk = false;
if numericValid
    peak = numericValues.PeakImportKW;
    residual = numericValues.EnergyBalanceResidualKW;
    terminalError = numericValues.TerminalSocErrorKWh;
    simultaneous = numericValues.SimultaneousChargeDischargeKW;
    exitFlag = numericValues.MinimumExitFlag;
    physicalValuesOk = all(peak >= -tolerances.capKW) && ...
        all(abs(residual) <= tolerances.energyBalanceResidualKW) && ...
        all(abs(terminalError) <= tolerances.terminalSocErrorKWh) && ...
        all(simultaneous >= -tolerances.simultaneousChargeDischargeKW) && ...
        all(simultaneous <= tolerances.simultaneousChargeDischargeKW) && ...
        all(exitFlag >= tolerances.minimumExitFlag);
end
criteria.allRowsFeasible = monthValid && all(validCalendarMonths) && ...
    strategyValid && dayValid && allRowsStatusOk && numericValid && ...
    physicalValuesOk;

if criteria.panelComplete && numericValid
    peakGuardRows = strategies == "IMPROVED_PEAK_GUARD";
    vppRows = strategies == "VPP_BM";
    statistics.peakGuardRowCount = nnz(peakGuardRows);

    [effectiveCapValid, effectiveCap] = finiteNumericColumn( ...
        primary, "EffectiveCapKW", peakGuardRows);
    if effectiveCapValid
        capPass = effectiveCap >= -tolerances.capKW & ...
            numericValues.PeakImportKW(peakGuardRows) <= ...
            effectiveCap + tolerances.capKW;
        statistics.peakGuardCapPassCount = nnz(capPass);
        criteria.capCompliant = numel(capPass) == 12 && all(capPass);
    end

    peakGuardSavings = numericValues.SavingsPercent(peakGuardRows);
    statistics.peakGuardMedianSavingsPercent = median(peakGuardSavings);
    statistics.peakGuardQ1SavingsPercent = quantile(peakGuardSavings, 0.25);
    criteria.medianSavingsPositive = ...
        statistics.peakGuardMedianSavingsPercent > 0;
    criteria.q1SavingsPositive = statistics.peakGuardQ1SavingsPercent > 0;

    peakDeltas = pairedPeakDeltas(monthValues, ...
        numericValues.PeakImportKW, peakGuardRows, vppRows);
    statistics.pairedMonthCount = numel(peakDeltas);
    statistics.pairedMedianPeakDeltaKW = median(peakDeltas);
    criteria.pairedMedianPeakDeltaNegative = numel(peakDeltas) == 12 && ...
        statistics.pairedMedianPeakDeltaKW < 0;
end
end

function complete = primaryPanelIsComplete(monthValues, dayKeys, dayMonths, ...
        strategies, expectedStrategies)
complete = numel(unique(monthValues)) == 12 && ...
    all(ismember(strategies, expectedStrategies));
for monthIndex = 1:12
    monthRows = monthValues == monthIndex;
    complete = complete && nnz(monthRows) == numel(expectedStrategies) && ...
        isscalar(unique(dayKeys(monthRows)));
    if all(~isnan(dayMonths(monthRows)))
        complete = complete && all(dayMonths(monthRows) == monthIndex);
    end
    for strategyIndex = 1:numel(expectedStrategies)
        complete = complete && nnz(monthRows & ...
            strategies == expectedStrategies(strategyIndex)) == 1;
    end
end
end

function deltas = pairedPeakDeltas(monthValues, peaks, peakGuardRows, vppRows)
deltas = NaN(12, 1);
for monthIndex = 1:12
    guardRow = monthValues == monthIndex & peakGuardRows;
    vppRow = monthValues == monthIndex & vppRows;
    deltas(monthIndex) = peaks(guardRow) - peaks(vppRow);
end
end

function [criteria, statistics] = evaluateFrontier(frontier, tolerances, statistics)
criteria = struct("panelComplete", false, "allRowsFeasible", false, ...
    "requestedCapsTighten", false, "peakMonotonic", false, ...
    "billMonotonic", false);

[monthValid, monthValues] = finiteNumericColumn(frontier, "Month");
[strategyValid, strategies] = textColumn(frontier, "Strategy");
[statusValid, statuses] = textColumn(frontier, "Status");
[dayValid, dayKeys, dayMonths] = dayColumn(frontier, "Day");
[alphaValid, alphaValues] = finiteNumericColumn(frontier, "Alpha");

if monthValid
    validCalendarMonths = monthValues == fix(monthValues) & ...
        monthValues >= 1 & monthValues <= 12;
    if all(validCalendarMonths)
        statistics.frontierMonthCount = numel(unique(monthValues));
    end
else
    validCalendarMonths = false(height(frontier), 1);
end

alphaTargets = [1; 0.75; 0.5; 0.25; 0];
alphaIndex = zeros(height(frontier), 1);
alphaMatches = false(height(frontier), 1);
if alphaValid
    [alphaDistance, alphaIndex] = min( ...
        abs(alphaValues - alphaTargets.'), [], 2);
    alphaMatches = alphaDistance <= tolerances.alpha;
end

panelReady = monthValid && strategyValid && dayValid && alphaValid && ...
    all(validCalendarMonths) && height(frontier) == 20 && ...
    all(alphaMatches) && all(strategies == "IMPROVED_PEAK_GUARD");
if panelReady
    criteria.panelComplete = frontierPanelIsComplete(monthValues, ...
        dayKeys, dayMonths, alphaIndex, numel(alphaTargets));
end

numericNames = ["EffectiveCapKW", "PeakImportKW", "SavingsPercent", ...
    "EnergyBalanceResidualKW", "TerminalSocErrorKWh", ...
    "SimultaneousChargeDischargeKW", "MinimumExitFlag", "Alpha", ...
    "RequestedCapKW", "OptimizedBillEUR"];
[numericValid, numericValues] = finiteNumericColumns(frontier, numericNames);
allRowsStatusOk = statusValid && all(lower(strtrim(statuses)) == "ok");
physicalValuesOk = false;
if numericValid
    effectiveCap = numericValues.EffectiveCapKW;
    peak = numericValues.PeakImportKW;
    requestedCap = numericValues.RequestedCapKW;
    simultaneous = numericValues.SimultaneousChargeDischargeKW;
    capPass = peak <= effectiveCap + tolerances.capKW;
    statistics.frontierPeakCapPassCount = nnz(capPass);
    physicalValuesOk = all(effectiveCap >= -tolerances.capKW) && ...
        all(peak >= -tolerances.capKW) && ...
        all(requestedCap >= -tolerances.capKW) && all(capPass) && ...
        all(abs(numericValues.EnergyBalanceResidualKW) <= ...
            tolerances.energyBalanceResidualKW) && ...
        all(abs(numericValues.TerminalSocErrorKWh) <= ...
            tolerances.terminalSocErrorKWh) && ...
        all(simultaneous >= -tolerances.simultaneousChargeDischargeKW) && ...
        all(simultaneous <= tolerances.simultaneousChargeDischargeKW) && ...
        all(numericValues.MinimumExitFlag >= tolerances.minimumExitFlag);
end
criteria.allRowsFeasible = monthValid && all(validCalendarMonths) && ...
    strategyValid && dayValid && alphaValid && allRowsStatusOk && ...
    numericValid && physicalValuesOk;

if criteria.panelComplete && numericValid
    [requestedCapDiffs, peakDiffs, billDiffs] = frontierDifferences( ...
        monthValues, alphaIndex, numericValues.RequestedCapKW, ...
        numericValues.PeakImportKW, numericValues.OptimizedBillEUR);
    statistics.frontierComparisonCount = numel(peakDiffs);
    statistics.frontierRequestedCapMonotonicPassCount = nnz( ...
        requestedCapDiffs <= tolerances.capKW);
    statistics.frontierPeakMonotonicPassCount = nnz( ...
        peakDiffs <= tolerances.peakMonotonicKW);
    statistics.frontierBillMonotonicPassCount = nnz( ...
        billDiffs >= -tolerances.billMonotonicEUR);
    statistics.frontierMaximumRequestedCapIncreaseKW = ...
        max(requestedCapDiffs);
    statistics.frontierMaximumPeakIncreaseKW = max(peakDiffs);
    statistics.frontierMaximumBillDecreaseEUR = max(0, max(-billDiffs));

    criteria.requestedCapsTighten = all( ...
        requestedCapDiffs <= tolerances.capKW);
    criteria.peakMonotonic = all( ...
        peakDiffs <= tolerances.peakMonotonicKW);
    criteria.billMonotonic = all( ...
        billDiffs >= -tolerances.billMonotonicEUR);
end
end

function complete = frontierPanelIsComplete(monthValues, dayKeys, ...
        dayMonths, alphaIndex, targetCount)
monthList = unique(monthValues);
complete = isequal(monthList(:), [3; 6; 9; 12]);
for monthPosition = 1:numel(monthList)
    monthValue = monthList(monthPosition);
    monthRows = monthValues == monthValue;
    complete = complete && nnz(monthRows) == targetCount && ...
        isscalar(unique(dayKeys(monthRows)));
    if all(~isnan(dayMonths(monthRows)))
        complete = complete && all(dayMonths(monthRows) == monthValue);
    end
    for alphaPosition = 1:targetCount
        complete = complete && nnz(monthRows & ...
            alphaIndex == alphaPosition) == 1;
    end
end
end

function [capDiffs, peakDiffs, billDiffs] = frontierDifferences( ...
        monthValues, alphaIndex, requestedCaps, peaks, bills)
monthList = unique(monthValues);
comparisonCount = numel(monthList) * 4;
capDiffs = NaN(comparisonCount, 1);
peakDiffs = NaN(comparisonCount, 1);
billDiffs = NaN(comparisonCount, 1);
outputRows = 1:4;
for monthPosition = 1:numel(monthList)
    monthValue = monthList(monthPosition);
    orderedRows = NaN(5, 1);
    for alphaPosition = 1:5
        orderedRows(alphaPosition) = find(monthValues == monthValue & ...
            alphaIndex == alphaPosition, 1, "first");
    end
    capDiffs(outputRows) = diff(requestedCaps(orderedRows));
    peakDiffs(outputRows) = diff(peaks(orderedRows));
    billDiffs(outputRows) = diff(bills(orderedRows));
    outputRows = outputRows + 4;
end
end

function [valid, values] = finiteNumericColumn(inputTable, name, rows)
if nargin < 3
    rows = true(height(inputTable), 1);
end
rawValues = inputTable.(name);
valid = isnumeric(rawValues) && isreal(rawValues) && ...
    isvector(rawValues) && numel(rawValues) == height(inputTable);
if valid
    values = double(rawValues(:));
    values = values(rows);
    valid = all(isfinite(values));
else
    values = NaN(nnz(rows), 1);
end
end

function [valid, values] = finiteNumericColumns(inputTable, names)
valid = true;
values = struct;
for index = 1:numel(names)
    name = names(index);
    [columnValid, columnValues] = finiteNumericColumn(inputTable, name);
    valid = valid && columnValid;
    values.(name) = columnValues;
end
end

function [valid, values] = textColumn(inputTable, name)
rawValues = inputTable.(name);
try
    values = string(rawValues);
    values = values(:);
    valid = numel(values) == height(inputTable) && ...
        all(~ismissing(values)) && all(strlength(strtrim(values)) > 0);
catch
    values = strings(height(inputTable), 1);
    valid = false;
end
end

function [valid, keys, calendarMonths] = dayColumn(inputTable, name)
rawValues = inputTable.(name);
calendarMonths = NaN(height(inputTable), 1);
try
    if isdatetime(rawValues)
        valid = isvector(rawValues) && numel(rawValues) == height(inputTable) && ...
            all(~isnat(rawValues));
        keys = string(rawValues(:), "yyyy-MM-dd'T'HH:mm:ss.SSS");
        calendarMonths = month(rawValues(:));
    elseif isnumeric(rawValues)
        valid = isreal(rawValues) && isvector(rawValues) && ...
            numel(rawValues) == height(inputTable) && ...
            all(isfinite(rawValues));
        keys = compose("%.17g", double(rawValues(:)));
    else
        keys = string(rawValues);
        keys = keys(:);
        valid = numel(keys) == height(inputTable) && ...
            all(~ismissing(keys)) && all(strlength(strtrim(keys)) > 0);
    end
catch
    valid = false;
    keys = strings(height(inputTable), 1);
end
end

function reasons = appendCriterionFailures(reasons, criteria)
if ~criteria.primaryPanelComplete
    reasons(end + 1, 1) = "primary panel must contain exactly one " + ...
        "SH_BM, VPP_BM, and IMPROVED_PEAK_GUARD row for the same day " + ...
        "in each of months 1 through 12 (36 rows total).";
end
if ~criteria.primaryAllRowsFeasible
    reasons(end + 1, 1) = "primary rows did not all have Status=ok, " + ...
        "finite required metrics, acceptable residuals, terminal SoC, " + ...
        "simultaneous charge/discharge, and exit flags.";
end
if ~criteria.peakGuardCapCompliant
    reasons(end + 1, 1) = "Peak Guard did not satisfy PeakImportKW <= " + ...
        "EffectiveCapKW + capKW in all 12 months.";
end
if ~criteria.peakGuardMedianSavingsPositive
    reasons(end + 1, 1) = ...
        "Peak Guard median SavingsPercent was not strictly positive.";
end
if ~criteria.peakGuardQ1SavingsPositive
    reasons(end + 1, 1) = ...
        "Peak Guard first-quartile SavingsPercent was not strictly positive.";
end
if ~criteria.pairedMedianPeakDeltaNegative
    reasons(end + 1, 1) = "The paired median of Peak Guard minus VPP_BM " + ...
        "PeakImportKW was not strictly negative across 12 months.";
end
if ~criteria.frontierPanelComplete
    reasons(end + 1, 1) = "frontier must contain exactly months " + ...
        "[3, 6, 9, 12], with Strategy=IMPROVED_PEAK_GUARD and one " + ...
        "same-day row at each Alpha=[1, 0.75, 0.5, 0.25, 0] per month.";
end
if ~criteria.frontierAllRowsFeasible
    reasons(end + 1, 1) = "frontier rows did not all have Status=ok, " + ...
        "finite required metrics, cap compliance, acceptable residuals, " + ...
        "terminal SoC, simultaneous charge/discharge, and exit flags.";
end
if ~criteria.frontierRequestedCapsTighten
    reasons(end + 1, 1) = "RequestedCapKW increased beyond capKW while " + ...
        "Alpha moved from 1 toward 0.";
end
if ~criteria.frontierPeakMonotonic
    reasons(end + 1, 1) = "PeakImportKW increased beyond peakMonotonicKW " + ...
        "while Alpha moved from 1 toward 0.";
end
if ~criteria.frontierBillMonotonic
    reasons(end + 1, 1) = "OptimizedBillEUR decreased by more than " + ...
        "billMonotonicEUR while Alpha moved from 1 toward 0.";
end
end
