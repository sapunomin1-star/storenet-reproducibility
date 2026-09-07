function metrics = evaluate_storenet(data, config, solution)
%EVALUATE_STORENET Independently evaluate a StoreNet optimization result.
%   METRICS = EVALUATE_STORENET(DATA, CONFIG, SOLUTION) recomputes bills,
%   peaks, constraint residuals, terminal state of charge, and simultaneous
%   charge/discharge from the public solution fields. Two explicitly named
%   baselines are returned: PaperLoadOnlyBaseline uses the original load with
%   no PV or battery contribution; PvSelfNoBatteryBaseline allows household
%   PV self-consumption but no battery or VPP sharing.

arguments
    data (1, 1) struct
    config (1, 1) struct
    solution (1, 1) struct
end

requiredSolutionFields = ["pvToHomeKW", "pvToBatteryKW", "pvToGridKW", ...
    "pvCurtailKW", "gridToHomeKW", "gridToBatteryKW", ...
    "batteryToHomeKW", "batteryToGridKW", "socKWh", ...
    "batteryChargeKW", "batteryDischargeKW", "aggregateImportKW"];
missing = requiredSolutionFields(~isfield(solution, cellstr(requiredSolutionFields)));
if ~isempty(missing)
    error("StoreNet:InvalidSolution", "Solution is missing fields: %s.", ...
        strjoin(missing, ", "));
end

time = data.time(:);
loadKW = double(data.loadKW);
pvKW = double(data.pvKW);
dtHours = double(data.dtHours);
validateIntervalEndTime(time, dtHours);
intervalStartTime = time - hours(dtHours);
dayMask = hour(intervalStartTime) >= config.dayStartHour & ...
    hour(intervalStartTime) < config.dayEndHour;
pricePerKWh = repmat(double(config.nightPrice), numel(time), 1);
pricePerKWh(dayMask) = double(config.dayPrice);

pvACAvailableKW = config.etaPvAC .* pvKW;
pvSelfToHomeKW = min(loadKW, pvACAvailableKW);
paperLoadOnlyImportKW = sum(loadKW, 2);
pvSelfNoBatteryImportKW = sum(loadKW - pvSelfToHomeKW, 2);
aggregateImportKW = double(solution.aggregateImportKW(:));
optimizedBillEUR = dtHours .* sum(pricePerKWh .* aggregateImportKW);
paperLoadOnlyBaseline = makeBaselineMetrics( ...
    "Original aggregate load; no PV, no battery, no VPP sharing", ...
    paperLoadOnlyImportKW, pricePerKWh, dayMask, dtHours, optimizedBillEUR);
pvSelfNoBatteryBaseline = makeBaselineMetrics( ...
    "Household PV self-consumption; no battery, no VPP sharing", ...
    pvSelfNoBatteryImportKW, pricePerKWh, dayMask, dtHours, optimizedBillEUR);

pvResidualKW = pvKW - (solution.pvToHomeKW ./ config.etaPvAC + ...
    solution.pvToGridKW ./ config.etaPvAC + ...
    solution.pvToBatteryKW ./ config.etaPvDC + solution.pvCurtailKW);
homeResidualKW = loadKW - (solution.gridToHomeKW + ...
    solution.pvToHomeKW + solution.batteryToHomeKW);
chargePowerRecomputedKW = config.etaBatteryCharge .* ...
    solution.gridToBatteryKW + solution.pvToBatteryKW;
dischargePowerRecomputedKW = (solution.batteryToHomeKW + ...
    solution.batteryToGridKW) ./ config.etaBatteryDischarge;
chargeConversionResidualKW = solution.batteryChargeKW - ...
    chargePowerRecomputedKW;
dischargeConversionResidualKW = solution.batteryDischargeKW - ...
    dischargePowerRecomputedKW;
batteryResidualKW = (solution.socKWh(2:end, :) - ...
    solution.socKWh(1:end-1, :)) ./ dtHours - ...
    (chargePowerRecomputedKW - dischargePowerRecomputedKW - ...
    optionalScalar(config, "selfDischargeKW", 0));
aggregateImportRecomputedKW = sum(solution.gridToHomeKW + ...
    solution.gridToBatteryKW - (1 - config.transferLossFraction) .* ...
    (solution.pvToGridKW + solution.batteryToGridKW), 2);
aggregateResidualKW = aggregateImportKW - aggregateImportRecomputedKW;

initialEnergyKWh = config.socInitialFraction * config.batteryCapacityKWh;
terminalFraction = config.socInitialFraction;
if isfield(config, "socTerminalFraction")
    terminalFraction = config.socTerminalFraction;
end
terminalEnergyKWh = terminalFraction * config.batteryCapacityKWh;
simultaneousPowerKW = min(chargePowerRecomputedKW, ...
    dischargePowerRecomputedKW);
socMinimumKWh = config.socMinFraction * config.batteryCapacityKWh;
socMaximumKWh = config.socMaxFraction * config.batteryCapacityKWh;
socBoundViolationKWh = max([0; socMinimumKWh - solution.socKWh(:); ...
    solution.socKWh(:) - socMaximumKWh]);
chargePowerViolationKW = max([0; ...
    chargePowerRecomputedKW(:) - config.batteryPowerKW]);
dischargePowerViolationKW = max([0; ...
    dischargePowerRecomputedKW(:) - config.batteryPowerKW]);
aggregateImportNonnegativeViolationKW = max([0; -aggregateImportKW]);

metrics = struct;
metrics.PaperLoadOnlyBaseline = paperLoadOnlyBaseline;
metrics.PvSelfNoBatteryBaseline = pvSelfNoBatteryBaseline;
metrics.optimizedBillEUR = double(optimizedBillEUR);
% Deprecated compatibility aliases. Existing runners historically used the
% PV-self/no-battery baseline; keep that meaning until they migrate to the
% explicitly named nested fields above.
metrics.baselineDefinition = ...
    "DEPRECATED alias of PvSelfNoBatteryBaseline";
metrics.deprecatedBaselineAliasTarget = "PvSelfNoBatteryBaseline";
metrics.baselineBillEUR = pvSelfNoBatteryBaseline.billEUR;
metrics.baselinePeakImportKW = pvSelfNoBatteryBaseline.peakImportKW;
metrics.baselineDaytimePeakImportKW = ...
    pvSelfNoBatteryBaseline.daytimePeakImportKW;
metrics.savingsEUR = pvSelfNoBatteryBaseline.savingsEUR;
metrics.savingsPercent = pvSelfNoBatteryBaseline.savingsPercent;
metrics.peakImportKW = max(aggregateImportKW);
metrics.daytimePeakImportKW = maxOrNaN(aggregateImportKW(dayMask));
metrics.importSpreadKW = max(aggregateImportKW) - min(aggregateImportKW);
metrics.totalGridImportKWh = dtHours .* sum(aggregateImportKW);
metrics.totalBatteryThroughputKWh = dtHours .* sum( ...
    chargePowerRecomputedKW + dischargePowerRecomputedKW, "all");
metrics.totalCurtailedPvKWh = dtHours .* sum(solution.pvCurtailKW, "all");
metrics.totalSharedExportKWh = dtHours .* sum( ...
    solution.pvToGridKW + solution.batteryToGridKW, "all");
metrics.energyBalanceResidualKW = max(abs([pvResidualKW(:); ...
    homeResidualKW(:); batteryResidualKW(:); aggregateResidualKW(:); ...
    chargeConversionResidualKW(:); dischargeConversionResidualKW(:)]));
metrics.pvAllocationResidualKW = max(abs(pvResidualKW), [], "all");
metrics.homeBalanceResidualKW = max(abs(homeResidualKW), [], "all");
metrics.batteryDynamicsResidualKW = max(abs(batteryResidualKW), [], "all");
metrics.aggregateImportResidualKW = max(abs(aggregateResidualKW), [], "all");
metrics.chargeConversionResidualKW = max(abs(chargeConversionResidualKW), ...
    [], "all");
metrics.dischargeConversionResidualKW = max(abs( ...
    dischargeConversionResidualKW), [], "all");
metrics.initialSocErrorKWh = max(abs(solution.socKWh(1, :) - initialEnergyKWh));
metrics.terminalSocErrorKWh = max(abs(solution.socKWh(end, :) - terminalEnergyKWh));
metrics.socBoundViolationKWh = socBoundViolationKWh;
metrics.chargePowerViolationKW = chargePowerViolationKW;
metrics.dischargePowerViolationKW = dischargePowerViolationKW;
metrics.aggregateImportNonnegativeViolationKW = ...
    aggregateImportNonnegativeViolationKW;
metrics.simultaneousChargeDischargeKW = max(simultaneousPowerKW, [], "all");
metrics.simultaneousChargeDischargeCount = nnz( ...
    simultaneousPowerKW > config.constraintTolerance);
[metrics.lexicographicPreservationViolation, ...
    metrics.maximumLexicographicViolation] = lexicographicViolations( ...
    solution, metrics);
end

function [violations, maximumViolation] = lexicographicViolations(solution, metrics)
violations = zeros(0, 1);
if ~isfield(solution, "objectiveStages") || isempty(solution.objectiveStages)
    maximumViolation = NaN;
    return
end
stages = solution.objectiveStages(:);
violations = nan(numel(stages), 1);
violationIndex = 0;
for stageIndex = 1:numel(stages)
    if ~isfield(stages, "lockedInLaterStage") || ...
            ~logical(stages(stageIndex).lockedInLaterStage)
        continue
    end
    if ~isfield(stages, "allowance") || ...
            ~isfinite(stages(stageIndex).allowance)
        violationIndex = violationIndex + 1;
        violations(violationIndex, 1) = Inf;
        continue
    end
    finalValue = metricForStage(metrics, string(stages(stageIndex).name), ...
        solution);
    violationIndex = violationIndex + 1;
    violations(violationIndex, 1) = max(0, finalValue - ...
        (double(stages(stageIndex).value) + ...
        double(stages(stageIndex).allowance)));
end
violations = violations(1:violationIndex);
if isempty(violations)
    maximumViolation = 0;
else
    maximumViolation = max(violations);
end
end

function value = metricForStage(metrics, name, solution)
switch name
    case "billEUR"
        value = metrics.optimizedBillEUR;
    case "billPlusDemandChargeEUR"
        % The weighted tariff stage is recomputed from the public solution
        % fields and the demand charge the solution was produced with. A
        % missing charge fails closed (Inf) like an unknown stage name.
        demandCharge = NaN;
        if isfield(solution, "demandChargeEURPerKW")
            demandCharge = double(solution.demandChargeEURPerKW);
        end
        if isscalar(demandCharge) && isfinite(demandCharge)
            value = metrics.optimizedBillEUR + ...
                demandCharge .* metrics.peakImportKW;
        else
            value = Inf;
        end
    case "systemPeakKW"
        value = metrics.peakImportKW;
    case "daytimePeakKW"
        value = metrics.daytimePeakImportKW;
    case "importSpreadKW"
        value = metrics.importSpreadKW;
    case "batteryThroughputKWh"
        value = metrics.totalBatteryThroughputKWh;
    otherwise
        value = Inf;
end
end

function value = optionalScalar(structure, field, defaultValue)
if isfield(structure, field)
    value = double(structure.(field));
else
    value = double(defaultValue);
end
end

function baseline = makeBaselineMetrics(definition, importKW, pricePerKWh, ...
        dayMask, dtHours, optimizedBillEUR)
billEUR = dtHours .* sum(pricePerKWh .* importKW);
savingsEUR = billEUR - optimizedBillEUR;
baseline = struct;
baseline.definition = string(definition);
baseline.billEUR = double(billEUR);
baseline.peakImportKW = max(importKW);
baseline.daytimePeakImportKW = maxOrNaN(importKW(dayMask));
baseline.savingsEUR = double(savingsEUR);
baseline.savingsPercent = safePercent(savingsEUR, billEUR);
baseline.savingsPercentDenominatorIsZero = (billEUR == 0);
end

function validateIntervalEndTime(intervalEndTime, dtHours)
if ~isdatetime(intervalEndTime) || ~iscolumn(intervalEndTime) || ...
        isempty(intervalEndTime)
    error("StoreNet:InvalidData", ...
        "data.time must be a nonempty datetime column of interval ends.");
end
stepSeconds = seconds(diff(intervalEndTime));
expectedSeconds = double(dtHours) * 3600;
toleranceSeconds = max(1e-9, expectedSeconds * 1e-10);
if any(stepSeconds <= 0)
    error("StoreNet:InvalidData", ...
        "data.time must be strictly increasing interval-end timestamps.");
end
if any(abs(stepSeconds - expectedSeconds) > toleranceSeconds)
    error("StoreNet:InvalidData", ...
        "data.time must be equally spaced and agree with data.dtHours.");
end
end

function percentage = safePercent(numerator, denominator)
if abs(denominator) <= eps(max(1, abs(denominator)))
    percentage = NaN;
else
    percentage = 100 .* numerator ./ denominator;
end
end

function value = maxOrNaN(values)
if isempty(values)
    value = NaN;
else
    value = max(values);
end
end
