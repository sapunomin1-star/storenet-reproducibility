function [solution, metrics] = solve_storenet(data, config, strategy)
%SOLVE_STORENET Solve the intended StoreNet residential VPP model.
%   SOLUTION = SOLVE_STORENET(DATA, CONFIG, STRATEGY) solves one horizon for
%   SH_BM, VPP_BM, PS, PSDT, LL, or IMPROVED_PEAK_GUARD. Public StoreNet
%   production is treated as DC-available PV power. AC and DC conversion
%   efficiencies are therefore explicit in the allocation constraints.
%
%   Improvement v2 (ADR-002) adds two purely additive strategies that leave
%   every existing strategy path untouched:
%     VPP_BM_PEAK_LEX      bill -> all-day aggregate peak -> throughput.
%                          Stage one is the identical VPP_BM bill problem;
%                          the peak stage only chooses among bill-optimal
%                          dispatches, so its peak reduction is bill-free.
%     VPP_BM_DEMAND_CHARGE (bill + demandChargeEURPerKW * peak) -> throughput.
%                          A weighted-sum tariff view of the same trade-off;
%                          CONFIG.demandChargeEURPerKW is required.
%
%   [SOLUTION, METRICS] also returns the independently recomputed metrics
%   produced by EVALUATE_STORENET.

arguments
    data (1, 1) struct
    config (1, 1) struct
    strategy (1, 1) string
end

validateInputs(data, config);
strategy = normalizeStrategy(strategy);

time = data.time(:);
loadKW = double(data.loadKW);
pvKW = double(data.pvKW);
dtHours = double(data.dtHours);
[intervalCount, houseCount] = size(loadKW);

pricePerKWh = tariffForTime(time, dtHours, config);
dayMask = daytimeMask(time, dtHours, config);
if strategy == "PSDT" && ~any(dayMask)
    error("StoreNet:NoDaytimeIntervals", ...
        "PSDT requires at least one interval inside the configured daytime window.");
end

pvToHomeKW = optimvar("pvToHomeKW", intervalCount, houseCount, ...
    "LowerBound", 0);
pvToBatteryKW = optimvar("pvToBatteryKW", intervalCount, houseCount, ...
    "LowerBound", 0);
pvToGridKW = optimvar("pvToGridKW", intervalCount, houseCount, ...
    "LowerBound", 0);
pvCurtailKW = optimvar("pvCurtailKW", intervalCount, houseCount, ...
    "LowerBound", 0);
gridToHomeKW = optimvar("gridToHomeKW", intervalCount, houseCount, ...
    "LowerBound", 0);
gridToBatteryKW = optimvar("gridToBatteryKW", intervalCount, houseCount, ...
    "LowerBound", 0);
batteryToHomeKW = optimvar("batteryToHomeKW", intervalCount, houseCount, ...
    "LowerBound", 0);
batteryToGridKW = optimvar("batteryToGridKW", intervalCount, houseCount, ...
    "LowerBound", 0);
socKWh = optimvar("socKWh", intervalCount + 1, houseCount, ...
    "LowerBound", config.socMinFraction * config.batteryCapacityKWh, ...
    "UpperBound", config.socMaxFraction * config.batteryCapacityKWh);
chargeOn = optimvar("chargeOn", intervalCount, houseCount, "Type", "integer", ...
    "LowerBound", 0, "UpperBound", 1);
dischargeOn = optimvar("dischargeOn", intervalCount, houseCount, "Type", "integer", ...
    "LowerBound", 0, "UpperBound", 1);

chargePowerKW = config.etaBatteryCharge .* gridToBatteryKW + pvToBatteryKW;
dischargePowerKW = (batteryToHomeKW + batteryToGridKW) ./ ...
    config.etaBatteryDischarge;
aggregateImportKW = sum(gridToHomeKW + gridToBatteryKW - ...
    (1 - config.transferLossFraction) .* (pvToGridKW + batteryToGridKW), 2);
billExpression = dtHours .* sum(pricePerKWh .* aggregateImportKW);
throughputExpression = dtHours .* sum(chargePowerKW + dischargePowerKW, "all");

problem = optimproblem("ObjectiveSense", "minimize");
problem.Constraints.pvAllocation = ...
    pvToHomeKW ./ config.etaPvAC + pvToGridKW ./ config.etaPvAC + ...
    pvToBatteryKW ./ config.etaPvDC + pvCurtailKW == pvKW;
problem.Constraints.homeBalance = ...
    gridToHomeKW + pvToHomeKW + batteryToHomeKW == loadKW;
problem.Constraints.socInitial = socKWh(1, :) == ...
    config.socInitialFraction * config.batteryCapacityKWh;
explicitSelfDischargeKW = getOptionalField(config, "selfDischargeKW", 0);
problem.Constraints.socDynamics = socKWh(2:end, :) == socKWh(1:end-1, :) + ...
    dtHours .* (chargePowerKW - dischargePowerKW - explicitSelfDischargeKW);
terminalFraction = getOptionalField(config, "socTerminalFraction", ...
    config.socInitialFraction);
problem.Constraints.socTerminal = socKWh(end, :) == ...
    terminalFraction * config.batteryCapacityKWh;
problem.Constraints.chargePowerLimit = chargePowerKW <= ...
    config.batteryPowerKW .* chargeOn;
problem.Constraints.dischargePowerLimit = dischargePowerKW <= ...
    config.batteryPowerKW .* dischargeOn;
problem.Constraints.chargeDischargeExclusion = chargeOn + dischargeOn <= 1;
problem.Constraints.aggregateImportNonnegative = aggregateImportKW >= 0;

if strategy == "SH_BM"
    problem.Constraints.noPvSharing = pvToGridKW == 0;
    problem.Constraints.noBatterySharing = batteryToGridKW == 0;
elseif strategy == "IMPROVED_PEAK_GUARD"
    importCapKW = validateImportCap(config, intervalCount);
    problem.Constraints.aggregateImportCap = aggregateImportKW <= importCapKW;
end

options = makeSolverOptions(config);
stageRecords = emptyStageRecords();
solverOutputs = cell(0, 1);

switch strategy
    case {"SH_BM", "VPP_BM", "IMPROVED_PEAK_GUARD"}
        [stageOneSolution, billValue, exitFlag, output] = solveStage(problem, ...
            billExpression, options, "bill");
        stageRecords(end + 1) = makeStageRecord("billEUR", billValue, billValue, ...
            exitFlag, output);
        solverOutputs{end + 1, 1} = output;
        stageRecords(end).allowance = lexicographicAllowance(billValue, config);
        stageRecords(end).lockedInLaterStage = true;
        problem.Constraints.billLexicographic = billExpression <= ...
            billValue + stageRecords(end).allowance;
        throughputWeight = getOptionalField(config, "throughputWeight", 1);
        [rawSolution, weightedThroughput, exitFlag, output] = solveStage(problem, ...
            throughputWeight .* throughputExpression, options, ...
            "throughput after bill");
        physicalThroughput = weightedThroughput ./ throughputWeight;
        stageRecords(end + 1) = makeStageRecord("batteryThroughputKWh", ...
            physicalThroughput, weightedThroughput, exitFlag, output);
        solverOutputs{end + 1, 1} = output;
        validateIntermediateSolution(stageOneSolution);

    case "VPP_BM_PEAK_LEX"
        % Stage one is bit-for-bit the VPP_BM bill problem; the peak
        % variable is only introduced afterwards so the bill optimum is the
        % same optimum VPP_BM reports.
        [stageOneSolution, billValue, exitFlag, output] = solveStage(problem, ...
            billExpression, options, "bill");
        stageRecords(end + 1) = makeStageRecord("billEUR", billValue, billValue, ...
            exitFlag, output);
        solverOutputs{end + 1, 1} = output;
        stageRecords(end).allowance = lexicographicAllowance(billValue, config);
        stageRecords(end).lockedInLaterStage = true;
        problem.Constraints.billLexicographic = billExpression <= ...
            billValue + stageRecords(end).allowance;
        systemPeakKW = optimvar("systemPeakKW", 1, "LowerBound", 0);
        problem.Constraints.systemPeak = aggregateImportKW <= systemPeakKW;
        [stageTwoSolution, peakValue, exitFlag, output] = solveStage(problem, ...
            systemPeakKW, options, "system peak after bill");
        stageRecords(end + 1) = makeStageRecord("systemPeakKW", peakValue, ...
            peakValue, exitFlag, output);
        solverOutputs{end + 1, 1} = output;
        stageRecords(end).allowance = ...
            lexicographicAllowance(peakValue, config);
        stageRecords(end).lockedInLaterStage = true;
        problem.Constraints.systemPeakLexicographic = systemPeakKW <= ...
            peakValue + stageRecords(end).allowance;
        throughputWeight = getOptionalField(config, "throughputWeight", 1);
        [rawSolution, weightedThroughput, exitFlag, output] = solveStage(problem, ...
            throughputWeight .* throughputExpression, options, ...
            "throughput after bill and system peak");
        physicalThroughput = weightedThroughput ./ throughputWeight;
        stageRecords(end + 1) = makeStageRecord("batteryThroughputKWh", ...
            physicalThroughput, weightedThroughput, exitFlag, output);
        solverOutputs{end + 1, 1} = output;
        validateWarmSolutions(stageOneSolution, stageTwoSolution);

    case "VPP_BM_DEMAND_CHARGE"
        demandChargeEURPerKW = validateDemandCharge(config);
        systemPeakKW = optimvar("systemPeakKW", 1, "LowerBound", 0);
        problem.Constraints.systemPeak = aggregateImportKW <= systemPeakKW;
        weightedExpression = billExpression + ...
            demandChargeEURPerKW .* systemPeakKW;
        [stageOneSolution, weightedValue, exitFlag, output] = solveStage(problem, ...
            weightedExpression, options, "bill plus demand charge");
        stageRecords(end + 1) = makeStageRecord("billPlusDemandChargeEUR", ...
            weightedValue, weightedValue, exitFlag, output);
        solverOutputs{end + 1, 1} = output;
        stageRecords(end).allowance = ...
            lexicographicAllowance(weightedValue, config);
        stageRecords(end).lockedInLaterStage = true;
        problem.Constraints.demandChargeLexicographic = weightedExpression <= ...
            weightedValue + stageRecords(end).allowance;
        throughputWeight = getOptionalField(config, "throughputWeight", 1);
        [rawSolution, weightedThroughput, exitFlag, output] = solveStage(problem, ...
            throughputWeight .* throughputExpression, options, ...
            "throughput after bill plus demand charge");
        physicalThroughput = weightedThroughput ./ throughputWeight;
        stageRecords(end + 1) = makeStageRecord("batteryThroughputKWh", ...
            physicalThroughput, weightedThroughput, exitFlag, output);
        solverOutputs{end + 1, 1} = output;
        validateIntermediateSolution(stageOneSolution);

    case "PS"
        systemPeakKW = optimvar("systemPeakKW", 1, "LowerBound", 0);
        problem.Constraints.systemPeak = aggregateImportKW <= systemPeakKW;
        [stageOneSolution, primaryValue, exitFlag, output] = solveStage(problem, ...
            systemPeakKW, options, "system peak");
        stageRecords(end + 1) = makeStageRecord("systemPeakKW", primaryValue, ...
            primaryValue, exitFlag, output);
        solverOutputs{end + 1, 1} = output;
        stageRecords(end).allowance = ...
            lexicographicAllowance(primaryValue, config);
        stageRecords(end).lockedInLaterStage = true;
        problem.Constraints.systemPeakLexicographic = systemPeakKW <= ...
            primaryValue + stageRecords(end).allowance;
        [stageTwoSolution, billValue, exitFlag, output] = solveStage(problem, ...
            billExpression, options, "bill after system peak");
        stageRecords(end + 1) = makeStageRecord("billEUR", billValue, ...
            billValue, exitFlag, output);
        solverOutputs{end + 1, 1} = output;
        stageRecords(end).allowance = lexicographicAllowance(billValue, config);
        stageRecords(end).lockedInLaterStage = true;
        problem.Constraints.billLexicographic = billExpression <= ...
            billValue + stageRecords(end).allowance;
        throughputWeight = getOptionalField(config, "throughputWeight", 1);
        [rawSolution, weightedThroughput, exitFlag, output] = solveStage(problem, ...
            throughputWeight .* throughputExpression, options, ...
            "throughput after system peak and bill");
        physicalThroughput = weightedThroughput ./ throughputWeight;
        stageRecords(end + 1) = makeStageRecord("batteryThroughputKWh", ...
            physicalThroughput, weightedThroughput, exitFlag, output);
        solverOutputs{end + 1, 1} = output;
        validateWarmSolutions(stageOneSolution, stageTwoSolution);

    case "PSDT"
        daytimePeakKW = optimvar("daytimePeakKW", 1, "LowerBound", 0);
        problem.Constraints.daytimePeak = aggregateImportKW(dayMask) <= daytimePeakKW;
        [stageOneSolution, primaryValue, exitFlag, output] = solveStage(problem, ...
            daytimePeakKW, options, "daytime peak");
        stageRecords(end + 1) = makeStageRecord("daytimePeakKW", primaryValue, ...
            primaryValue, exitFlag, output);
        solverOutputs{end + 1, 1} = output;
        stageRecords(end).allowance = ...
            lexicographicAllowance(primaryValue, config);
        stageRecords(end).lockedInLaterStage = true;
        problem.Constraints.daytimePeakLexicographic = daytimePeakKW <= ...
            primaryValue + stageRecords(end).allowance;
        [stageTwoSolution, billValue, exitFlag, output] = solveStage(problem, ...
            billExpression, options, "bill after daytime peak");
        stageRecords(end + 1) = makeStageRecord("billEUR", billValue, ...
            billValue, exitFlag, output);
        solverOutputs{end + 1, 1} = output;
        stageRecords(end).allowance = lexicographicAllowance(billValue, config);
        stageRecords(end).lockedInLaterStage = true;
        problem.Constraints.billLexicographic = billExpression <= ...
            billValue + stageRecords(end).allowance;
        throughputWeight = getOptionalField(config, "throughputWeight", 1);
        [rawSolution, weightedThroughput, exitFlag, output] = solveStage(problem, ...
            throughputWeight .* throughputExpression, options, ...
            "throughput after daytime peak and bill");
        physicalThroughput = weightedThroughput ./ throughputWeight;
        stageRecords(end + 1) = makeStageRecord("batteryThroughputKWh", ...
            physicalThroughput, weightedThroughput, exitFlag, output);
        solverOutputs{end + 1, 1} = output;
        validateWarmSolutions(stageOneSolution, stageTwoSolution);

    case "LL"
        maximumImportKW = optimvar("maximumImportKW", 1, "LowerBound", 0);
        minimumImportKW = optimvar("minimumImportKW", 1, "LowerBound", 0);
        importSpreadKW = maximumImportKW - minimumImportKW;
        problem.Constraints.maximumImport = aggregateImportKW <= maximumImportKW;
        problem.Constraints.minimumImport = aggregateImportKW >= minimumImportKW;
        [stageOneSolution, primaryValue, exitFlag, output] = solveStage(problem, ...
            importSpreadKW, options, "import spread");
        stageRecords(end + 1) = makeStageRecord("importSpreadKW", primaryValue, ...
            primaryValue, exitFlag, output);
        solverOutputs{end + 1, 1} = output;
        stageRecords(end).allowance = ...
            lexicographicAllowance(primaryValue, config);
        stageRecords(end).lockedInLaterStage = true;
        problem.Constraints.importSpreadLexicographic = importSpreadKW <= ...
            primaryValue + stageRecords(end).allowance;
        [stageTwoSolution, billValue, exitFlag, output] = solveStage(problem, ...
            billExpression, options, "bill after import spread");
        stageRecords(end + 1) = makeStageRecord("billEUR", billValue, ...
            billValue, exitFlag, output);
        solverOutputs{end + 1, 1} = output;
        stageRecords(end).allowance = lexicographicAllowance(billValue, config);
        stageRecords(end).lockedInLaterStage = true;
        problem.Constraints.billLexicographic = billExpression <= ...
            billValue + stageRecords(end).allowance;
        throughputWeight = getOptionalField(config, "throughputWeight", 1);
        [rawSolution, weightedThroughput, exitFlag, output] = solveStage(problem, ...
            throughputWeight .* throughputExpression, options, ...
            "throughput after import spread and bill");
        physicalThroughput = weightedThroughput ./ throughputWeight;
        stageRecords(end + 1) = makeStageRecord("batteryThroughputKWh", ...
            physicalThroughput, weightedThroughput, exitFlag, output);
        solverOutputs{end + 1, 1} = output;
        validateWarmSolutions(stageOneSolution, stageTwoSolution);
end

solution = packageSolution(rawSolution, data, config, strategy, pricePerKWh, ...
    stageRecords, solverOutputs);
metrics = evaluate_storenet(data, config, solution);
solution.objectiveStages = finalizeStageRecords( ...
    solution.objectiveStages, metrics, config);
solution.metrics = metrics;
end

function solution = packageSolution(raw, data, config, strategy, pricePerKWh, ...
        stageRecords, solverOutputs)
solution = struct;
solution.strategy = strategy;
solution.time = data.time(:);
solution.intervalStartTime = data.time(:) - hours(double(data.dtHours));
solution.houseIds = string(data.houseIds(:)).';
solution.dtHours = double(data.dtHours);
solution.pvToHomeKW = raw.pvToHomeKW;
solution.pvToBatteryKW = raw.pvToBatteryKW;
solution.pvToGridKW = raw.pvToGridKW;
solution.pvCurtailKW = raw.pvCurtailKW;
solution.gridToHomeKW = raw.gridToHomeKW;
solution.gridToBatteryKW = raw.gridToBatteryKW;
solution.batteryToHomeKW = raw.batteryToHomeKW;
solution.batteryToGridKW = raw.batteryToGridKW;
solution.socKWh = raw.socKWh;
solution.socFraction = raw.socKWh ./ config.batteryCapacityKWh;
solution.chargeOn = raw.chargeOn;
solution.dischargeOn = raw.dischargeOn;
solution.batteryChargeKW = config.etaBatteryCharge .* raw.gridToBatteryKW + ...
    raw.pvToBatteryKW;
solution.batteryDischargeKW = (raw.batteryToHomeKW + raw.batteryToGridKW) ./ ...
    config.etaBatteryDischarge;
solution.aggregateImportKW = sum(raw.gridToHomeKW + raw.gridToBatteryKW - ...
    (1 - config.transferLossFraction) .* ...
    (raw.pvToGridKW + raw.batteryToGridKW), 2);
solution.pricePerKWh = pricePerKWh;
solution.demandChargeEURPerKW = double(getOptionalField(config, ...
    "demandChargeEURPerKW", NaN));
solution.objectiveStages = stageRecords;
solution.exitFlags = [stageRecords.exitFlag];
solution.solverOutputs = solverOutputs;
end

function [rawSolution, fval, exitFlag, output] = solveStage(problem, objective, ...
        options, stageDescription)
problem.Objective = objective;
[rawSolution, fval, exitFlag, output] = solve(problem, "Options", options);
if exitFlag <= 0 || isempty(fieldnames(rawSolution))
    error("StoreNet:OptimizationFailed", ...
        "Optimization failed during %s (exit flag %g).", stageDescription, exitFlag);
end
end

function record = makeStageRecord(name, physicalValue, solverObjective, ...
        exitFlag, output)
record = struct;
record.name = string(name);
record.value = double(physicalValue);
record.solverObjective = double(solverObjective);
record.exitFlag = double(exitFlag);
record.relativeGap = outputFieldOrNaN(output, "relativegap");
record.allowance = NaN;
record.lockedInLaterStage = false;
record.finalRecomputedValue = NaN;
record.message = string(outputFieldOrDefault(output, "message", ""));
end

function records = emptyStageRecords()
records = struct("name", {}, "value", {}, "solverObjective", {}, ...
    "exitFlag", {}, "relativeGap", {}, "allowance", {}, ...
    "lockedInLaterStage", {}, "finalRecomputedValue", {}, "message", {});
end

function records = finalizeStageRecords(records, metrics, config)
for stageIndex = 1:numel(records)
    switch string(records(stageIndex).name)
        case "billEUR"
            value = metrics.optimizedBillEUR;
        case "billPlusDemandChargeEUR"
            value = metrics.optimizedBillEUR + ...
                double(getOptionalField(config, "demandChargeEURPerKW", NaN)) .* ...
                metrics.peakImportKW;
        case "systemPeakKW"
            value = metrics.peakImportKW;
        case "daytimePeakKW"
            value = metrics.daytimePeakImportKW;
        case "importSpreadKW"
            value = metrics.importSpreadKW;
        case "batteryThroughputKWh"
            value = metrics.totalBatteryThroughputKWh;
        otherwise
            value = NaN;
    end
    records(stageIndex).finalRecomputedValue = double(value);
end
end

function value = outputFieldOrNaN(output, fieldName)
value = outputFieldOrDefault(output, fieldName, NaN);
if ~isnumeric(value) || ~isscalar(value)
    value = NaN;
end
end

function value = outputFieldOrDefault(output, fieldName, defaultValue)
if isfield(output, fieldName)
    value = output.(fieldName);
else
    value = defaultValue;
end
end

function allowance = lexicographicAllowance(value, config)
allowance = config.lexicographicTolerance .* max(1, abs(double(value)));
end

function options = makeSolverOptions(config)
options = optimoptions("intlinprog", "Display", "off", ...
    "RelativeGapTolerance", config.mipRelativeGap, ...
    "ConstraintTolerance", config.constraintTolerance);
if isfield(config, "maxSolverTimeSeconds")
    options.MaxTime = config.maxSolverTimeSeconds;
end
if isfield(config, "solverDisplay")
    options.Display = config.solverDisplay;
end
end

function demandCharge = validateDemandCharge(config)
if ~isfield(config, "demandChargeEURPerKW")
    error("StoreNet:MissingDemandCharge", ...
        "VPP_BM_DEMAND_CHARGE requires config.demandChargeEURPerKW.");
end
demandCharge = double(config.demandChargeEURPerKW);
validateattributes(demandCharge, {'double'}, ...
    {'scalar', 'real', 'finite', 'nonnegative'}, mfilename, ...
    "config.demandChargeEURPerKW");
end

function cap = validateImportCap(config, intervalCount)
if ~isfield(config, "aggregateImportCapKW")
    error("StoreNet:MissingImportCap", ...
        "IMPROVED_PEAK_GUARD requires config.aggregateImportCapKW.");
end
cap = double(config.aggregateImportCapKW);
validateattributes(cap, {'double'}, {'real', 'finite', 'nonnegative'}, ...
    mfilename, "config.aggregateImportCapKW");
if isscalar(cap)
    cap = repmat(cap, intervalCount, 1);
elseif isvector(cap) && numel(cap) == intervalCount
    cap = cap(:);
else
    error("StoreNet:InvalidImportCap", ...
        "aggregateImportCapKW must be scalar or have one value per interval.");
end
end

function price = tariffForTime(time, dtHours, config)
dayMask = daytimeMask(time, dtHours, config);
price = repmat(double(config.nightPrice), numel(time), 1);
price(dayMask) = double(config.dayPrice);
end

function mask = daytimeMask(intervalEndTime, dtHours, config)
intervalStartTime = intervalEndTime - hours(dtHours);
mask = hour(intervalStartTime) >= config.dayStartHour & ...
    hour(intervalStartTime) < config.dayEndHour;
end

function strategy = normalizeStrategy(strategy)
strategy = upper(replace(strtrim(strategy), "-", "_"));
allowed = ["SH_BM", "VPP_BM", "PS", "PSDT", "LL", ...
    "IMPROVED_PEAK_GUARD", "VPP_BM_PEAK_LEX", "VPP_BM_DEMAND_CHARGE"];
if ~any(strategy == allowed)
    error("StoreNet:UnknownStrategy", ...
        "Unknown strategy '%s'. Expected one of: %s.", strategy, ...
        strjoin(allowed, ", "));
end
end

function validateInputs(data, config)
requiredData = ["time", "loadKW", "pvKW", "dtHours", "houseIds"];
requiredConfig = ["batteryCapacityKWh", "batteryPowerKW", ...
    "socInitialFraction", "socMinFraction", "socMaxFraction", ...
    "etaPvAC", "etaPvDC", "etaBatteryCharge", "etaBatteryDischarge", ...
    "transferLossFraction", "dayStartHour", "dayEndHour", ...
    "nightPrice", "dayPrice", "mipRelativeGap", ...
    "constraintTolerance", "lexicographicTolerance"];
assertFields(data, requiredData, "data");
assertFields(config, requiredConfig, "config");

if ~isdatetime(data.time) || ~iscolumn(data.time) || isempty(data.time)
    error("StoreNet:InvalidData", "data.time must be a nonempty datetime column.");
end
validateIntervalEndTime(data.time, data.dtHours);
if ~isnumeric(data.loadKW) || ~isnumeric(data.pvKW) || ...
        ~isequal(size(data.loadKW), size(data.pvKW)) || ...
        size(data.loadKW, 1) ~= numel(data.time)
    error("StoreNet:InvalidData", ...
        "loadKW and pvKW must be numeric K-by-N arrays aligned with data.time.");
end
if any(~isfinite(data.loadKW), "all") || any(~isfinite(data.pvKW), "all") || ...
        any(data.loadKW < 0, "all") || any(data.pvKW < 0, "all")
    error("StoreNet:InvalidData", ...
        "loadKW and pvKW must contain finite, nonnegative values.");
end
if numel(data.houseIds) ~= size(data.loadKW, 2)
    error("StoreNet:InvalidData", "houseIds must contain one identifier per house.");
end
validateattributes(double(data.dtHours), {'double'}, ...
    {'scalar', 'real', 'finite', 'positive'}, mfilename, "data.dtHours");

positiveFields = ["batteryCapacityKWh", "etaPvAC", "etaPvDC", ...
    "etaBatteryCharge", "etaBatteryDischarge", "dayPrice", ...
    "nightPrice", "mipRelativeGap", "constraintTolerance", ...
    "lexicographicTolerance"];
nonnegativeFields = ["batteryPowerKW", "transferLossFraction"];
fractionFields = ["socInitialFraction", "socMinFraction", ...
    "socMaxFraction", "etaPvAC", "etaPvDC", "etaBatteryCharge", ...
    "etaBatteryDischarge"];
validateScalarFields(config, positiveFields, "positive");
validateScalarFields(config, nonnegativeFields, "nonnegative");
validateScalarFields(config, fractionFields, "fraction");
if config.transferLossFraction >= 1 || config.socMinFraction > config.socInitialFraction || ...
        config.socInitialFraction > config.socMaxFraction
    error("StoreNet:InvalidConfig", ...
        "Loss and state-of-charge fractions are inconsistent.");
end
if config.dayStartHour < 0 || config.dayStartHour >= 24 || ...
        config.dayEndHour <= 0 || config.dayEndHour > 24 || ...
        config.dayStartHour >= config.dayEndHour
    error("StoreNet:InvalidConfig", "The daytime window must lie inside one day.");
end
if isfield(config, "socTerminalFraction") && ...
        (config.socTerminalFraction < config.socMinFraction || ...
        config.socTerminalFraction > config.socMaxFraction)
    error("StoreNet:InvalidConfig", ...
        "socTerminalFraction must lie inside the configured SoC bounds.");
end
if isfield(config, "throughputWeight") && ...
        (~isnumeric(config.throughputWeight) || ~isscalar(config.throughputWeight) || ...
        ~isfinite(config.throughputWeight) || config.throughputWeight <= 0)
    error("StoreNet:InvalidConfig", "throughputWeight must be positive and finite.");
end
end

function assertFields(value, requiredFields, valueName)
missing = requiredFields(~isfield(value, cellstr(requiredFields)));
if ~isempty(missing)
    error("StoreNet:MissingField", "%s is missing required fields: %s.", ...
        valueName, strjoin(missing, ", "));
end
end

function validateScalarFields(config, fieldNames, validationKind)
values = arrayfun(@(name) double(config.(name)), fieldNames);
if any(~isfinite(values)) || any(arrayfun(@(name) ~isscalar(config.(name)), fieldNames))
    error("StoreNet:InvalidConfig", "Configuration values must be finite scalars.");
end
if validationKind == "positive" && any(values <= 0)
    error("StoreNet:InvalidConfig", "Positive configuration values must exceed zero.");
elseif validationKind == "nonnegative" && any(values < 0)
    error("StoreNet:InvalidConfig", "Nonnegative configuration values cannot be negative.");
elseif validationKind == "fraction" && any(values <= 0 | values > 1)
    error("StoreNet:InvalidConfig", "Efficiency and SoC fractions must lie in (0, 1].");
end
end

function value = getOptionalField(config, fieldName, defaultValue)
if isfield(config, fieldName)
    value = config.(fieldName);
else
    value = defaultValue;
end
end

function validateWarmSolutions(stageOneSolution, stageTwoSolution)
% Keep intermediate solutions live until packaging; this also guards against
% unexpected solver API changes that return empty solutions with success flags.
if isempty(fieldnames(stageOneSolution)) || isempty(fieldnames(stageTwoSolution))
    error("StoreNet:OptimizationFailed", ...
        "A lexicographic intermediate stage did not return a solution.");
end
end

function validateIntermediateSolution(intermediateSolution)
if isempty(fieldnames(intermediateSolution))
    error("StoreNet:OptimizationFailed", ...
        "An intermediate stage did not return a solution.");
end
end

function validateIntervalEndTime(intervalEndTime, dtHours)
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
