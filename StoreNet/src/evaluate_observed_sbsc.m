function [metrics, profiles] = evaluate_observed_sbsc(data, config)
%EVALUATE_OBSERVED_SBSC Evaluate the released same-system SB-SC proxy.
%   This function describes measured release outputs only. It does not infer
%   or reconstruct the proprietary Sonnen controller.

arguments
    data (1, 1) struct
    config (1, 1) struct
end

required = ["time", "loadKW", "pvKW", "fromGridKW", "feedInKW", ...
    "chargeKW", "dischargeKW", "dtHours", "houseIds"];
missing = required(~isfield(data, cellstr(required)));
if ~isempty(missing)
    error("StoreNet:InvalidObservedSbscData", ...
        "Observed SB-SC data is missing field(s): %s.", strjoin(missing, ", "));
end

timeEnd = data.time(:);
dtHours = double(data.dtHours);
loadKW = double(data.loadKW);
fromGridKW = double(data.fromGridKW);
houseIds = string(data.houseIds(:)).';
validateObservationGrid(timeEnd, dtHours, houseIds);
validateAlignedFinite(loadKW, fromGridKW, timeEnd, houseIds);
pricePerKWh = priceForIntervals(timeEnd, dtHours, config);
dayMask = daytimeIntervals(timeEnd, dtHours, config);

aggregateLoadKW = sum(loadKW, 2);
aggregateGridImportKW = sum(fromGridKW, 2);
paperLoadOnlyBillEUR = dtHours .* sum(pricePerKWh .* aggregateLoadKW);
observedBillEUR = dtHours .* sum(pricePerKWh .* aggregateGridImportKW);

releasedPvKW = releasedPv(data);
validateAlignedFinite(loadKW, releasedPvKW, timeEnd, houseIds);
aggregateReleasedPvKW = sum(releasedPvKW, 2);
releasePvSelfImportKW = sum(loadKW - min(loadKW, releasedPvKW), 2);
observedReleasePvSelfNoBatteryBillEUR = ...
    dtHours .* sum(pricePerKWh .* releasePvSelfImportKW);

chargeKW = double(data.chargeKW);
dischargeKW = double(data.dischargeKW);
validateAlignedFinite(loadKW, chargeKW, timeEnd, houseIds);
validateAlignedFinite(loadKW, dischargeKW, timeEnd, houseIds);
releaseBatterySignedKW = sum(dischargeKW - chargeKW, 2);
releaseBatteryThroughputKWh = dtHours .* sum(chargeKW + dischargeKW, "all");

feedInKW = double(data.feedInKW);
validateAlignedFinite(loadKW, feedInKW, timeEnd, houseIds);
aggregateFeedInKW = sum(feedInKW, 2);
totalFeedInKWh = dtHours .* sum(feedInKW, "all");

metrics = struct;
metrics.strategy = "SB_SC_OBSERVED_PROXY";
metrics.observationDefinition = ...
    "public-release same-system observed proxy; proprietary control not reconstructed";
metrics.pvBoundaryId = "OBSERVED_RELEASE_FIELDS";
metrics.transferLossFraction = NaN;
metrics.xi = NaN;
metrics.pvEfficiencyApplied = false;
metrics.sharingLossApplied = false;
metrics.paperLoadOnlyBaselineBillEUR = double(paperLoadOnlyBillEUR);
metrics.observedReleasePvSelfNoBatteryBaselineBillEUR = ...
    double(observedReleasePvSelfNoBatteryBillEUR);
metrics.observedBillEUR = double(observedBillEUR);
metrics.paperLoadOnlySavingsEUR = double(paperLoadOnlyBillEUR - observedBillEUR);
metrics.paperLoadOnlySavingsPercentDenominatorIsZero = ...
    isZeroDenominator(paperLoadOnlyBillEUR);
metrics.paperLoadOnlySavingsPercent = safePercent( ...
    paperLoadOnlyBillEUR - observedBillEUR, paperLoadOnlyBillEUR);
metrics.observedReleaseEngineeringSavingsEUR = double( ...
    observedReleasePvSelfNoBatteryBillEUR - observedBillEUR);
metrics.observedReleaseEngineeringSavingsPercentDenominatorIsZero = ...
    isZeroDenominator(observedReleasePvSelfNoBatteryBillEUR);
metrics.observedReleaseEngineeringSavingsPercent = safePercent( ...
    observedReleasePvSelfNoBatteryBillEUR - observedBillEUR, ...
    observedReleasePvSelfNoBatteryBillEUR);
metrics.paperLoadOnlyPeakKW = max(aggregateLoadKW);
metrics.paperLoadOnlyDaytimePeakKW = maxOrNaN(aggregateLoadKW(dayMask));
metrics.observedPeakImportKW = max(aggregateGridImportKW);
metrics.observedDaytimePeakImportKW = maxOrNaN(aggregateGridImportKW(dayMask));
metrics.observedImportSpreadKW = max(aggregateGridImportKW) - ...
    min(aggregateGridImportKW);
metrics.observedGridImportKWh = dtHours .* sum(aggregateGridImportKW);
metrics.releaseBatteryThroughputKWh = releaseBatteryThroughputKWh;
metrics.totalFeedInKWh = totalFeedInKWh;

profiles = table(timeEnd, aggregateLoadKW, aggregateReleasedPvKW, ...
    aggregateGridImportKW, releaseBatterySignedKW, aggregateFeedInKW, ...
    VariableNames=["TimeEnd", "LoadKW", "ObservedReleasedPvKW", ...
    "GridImportKW", "ReleaseBatterySignedKW", "FeedInKW"]);
end

function releasedPvKW = releasedPv(data)
if isfield(data, "releasedPvKW")
    releasedPvKW = double(data.releasedPvKW);
else
    releasedPvKW = double(data.pvKW);
end
if ~isequal(size(releasedPvKW), size(data.loadKW)) || ...
        any(~isfinite(releasedPvKW), "all")
    error("StoreNet:InvalidObservedSbscData", ...
        "Released PV must be finite and aligned with loadKW.");
end
end

function validateAlignedFinite(first, second, time, houseIds)
if ~isequal(size(first), size(second)) || size(first, 1) ~= numel(time) || ...
        size(first, 2) ~= numel(houseIds) || ...
        any(~isfinite(first), "all") || any(~isfinite(second), "all")
    error("StoreNet:InvalidObservedSbscData", ...
        "Observed arrays must be finite and aligned with time.");
end
end

function validateObservationGrid(timeEnd, dtHours, houseIds)
if ~isdatetime(timeEnd) || isempty(timeEnd) || ~isscalar(dtHours) || ...
        ~isfinite(dtHours) || dtHours <= 0 || isempty(houseIds) || ...
        any(ismissing(houseIds)) || any(strlength(strip(houseIds)) == 0) || ...
        numel(unique(houseIds)) ~= numel(houseIds)
    error("StoreNet:InvalidObservedSbscData", ...
        "Observed time, dtHours, and unique houseIds must be well formed.");
end
end

function price = priceForIntervals(timeEnd, dtHours, config)
mask = daytimeIntervals(timeEnd, dtHours, config);
price = repmat(double(config.nightPrice), numel(timeEnd), 1);
price(mask) = double(config.dayPrice);
end

function mask = daytimeIntervals(timeEnd, dtHours, config)
intervalStart = timeEnd - hours(dtHours);
mask = hour(intervalStart) >= config.dayStartHour & ...
    hour(intervalStart) < config.dayEndHour;
end

function percentage = safePercent(numerator, denominator)
if isZeroDenominator(denominator)
    percentage = NaN;
else
    percentage = 100 .* numerator ./ denominator;
end
end

function tf = isZeroDenominator(value)
tf = abs(value) <= eps(max(1, abs(value)));
end

function value = maxOrNaN(values)
if isempty(values)
    value = NaN;
else
    value = max(values);
end
end
