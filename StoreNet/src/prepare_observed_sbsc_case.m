function [observedData, observedConfig, observedMeta] = ...
        prepare_observed_sbsc_case(data, config, caseMeta)
%PREPARE_OBSERVED_SBSC_CASE Freeze the release-side observation boundary.
%   Observed SB-SC uses the released Consumption/Production and measured
%   flow fields directly. It is neither an AC/DC model-boundary scenario nor
%   a sharing-loss scenario, so etaPvAC and xi are retained only as unused
%   source-config provenance and are never applied to observed quantities.

arguments
    data (1, 1) struct
    config (1, 1) struct
    caseMeta (1, 1) struct
end

requiredData = ["time", "loadKW", "pvKW", "fromGridKW", ...
    "feedInKW", "chargeKW", "dischargeKW", "dtHours", "houseIds"];
missingData = requiredData(~isfield(data, cellstr(requiredData)));
if ~isempty(missingData)
    error("StoreNet:InvalidObservedSbscData", ...
        "Observed SB-SC data is missing field(s): %s.", ...
        strjoin(missingData, ", "));
end
if ~isfield(caseMeta, "cohortId")
    error("StoreNet:InvalidObservedSbscMetadata", ...
        "Observed SB-SC metadata requires cohortId.");
end
validateDirectReleaseData(data);
validateObservedCohort(data.houseIds, caseMeta);

observedData = data;
releasedProductionKW = double(data.pvKW);
if isfield(data, "releasedPvKW")
    releasedProductionKW = double(data.releasedPvKW);
end
if ~isequal(size(releasedProductionKW), size(data.loadKW)) || ...
        any(~isfinite(releasedProductionKW), "all")
    error("StoreNet:InvalidObservedSbscData", ...
        "Released Production must be finite and aligned with loadKW.");
end
observedData.pvKW = releasedProductionKW;
observedData.releasedPvKW = releasedProductionKW;
if isfield(data, "releasedPvKWh")
    observedData.pvKWh = double(data.releasedPvKWh);
    observedData.releasedPvKWh = double(data.releasedPvKWh);
elseif isfield(data, "pvKWh")
    observedData.pvKWh = releasedProductionKW .* double(data.dtHours);
    observedData.releasedPvKWh = observedData.pvKWh;
end
observedData.observationBoundaryId = "OBSERVED_RELEASE_FIELDS";

observedConfig = config;
observedConfig.pvBoundaryId = "OBSERVED_RELEASE_FIELDS";
observedConfig.transferLossFraction = NaN;
observedConfig.xi = NaN;
observedConfig.capacityRatio = NaN;
observedConfig.powerRatio = NaN;
observedConfig.observedPvEfficiencyApplied = false;
observedConfig.observedSharingLossApplied = false;
observedConfig.observationDefinition = ...
    "direct released Consumption/Production/FromGrid/FeedIn/Charge/Discharge fields";

observedMeta = caseMeta;
observedMeta = preserveSourceIdentity(observedMeta, config, caseMeta);
cohortId = string(caseMeta.cohortId);
observedMeta.scenarioId = "OBSERVED_RELEASE_" + cohortId;
observedMeta.pairId = "OBSERVED_RELEASE_PAIR";
observedMeta.sensitivityRole = observedSensitivityRole(cohortId);
observedMeta.isPrimary = cohortId == "H20_PV10";
observedMeta.pvBoundaryId = "OBSERVED_RELEASE_FIELDS";
observedMeta.transferLossFraction = NaN;
observedMeta.xi = NaN;
observedMeta.capacityRatio = NaN;
observedMeta.powerRatio = NaN;
observedMeta.strategy = "SB_SC";
observedMeta.resultKind = "OBSERVED_RELEASE_PROXY";
observedMeta.observedPvEfficiencyApplied = false;
observedMeta.observedSharingLossApplied = false;
observedMeta.observationDefinition = observedConfig.observationDefinition;
observedConfig.scenarioId = observedMeta.scenarioId;
observedConfig.pairId = observedMeta.pairId;
observedConfig.sensitivityRole = observedMeta.sensitivityRole;
observedConfig.cohortId = cohortId;
end

function meta = preserveSourceIdentity(meta, config, caseMeta)
if ~isfield(meta, "sourceModelScenarioId") && ...
        isfield(caseMeta, "scenarioId") && ...
        string(caseMeta.scenarioId) ~= "OBSERVED_RELEASE_" + ...
        string(caseMeta.cohortId)
    meta.sourceModelScenarioId = string(caseMeta.scenarioId);
end
if ~isfield(meta, "sourceModelPairId") && isfield(caseMeta, "pairId") && ...
        string(caseMeta.pairId) ~= "OBSERVED_RELEASE_PAIR"
    meta.sourceModelPairId = string(caseMeta.pairId);
end
if ~isfield(meta, "sourceModelPvBoundaryId") && ...
        isfield(config, "pvBoundaryId") && ...
        string(config.pvBoundaryId) ~= "OBSERVED_RELEASE_FIELDS"
    meta.sourceModelPvBoundaryId = string(config.pvBoundaryId);
end
if ~isfield(meta, "sourceModelTransferLossFraction") && ...
        isfield(config, "transferLossFraction") && ...
        isfinite(double(config.transferLossFraction))
    meta.sourceModelTransferLossFraction = ...
        double(config.transferLossFraction);
end
end

function role = observedSensitivityRole(cohortId)
switch cohortId
    case "H20_PV10"
        role = "OBSERVED_PRIMARY";
    case "H19_EXCL_H4_PV9"
        role = "OBSERVED_H4_PAIR";
    otherwise
        error("StoreNet:InvalidObservedSbscMetadata", ...
            "Unsupported observed cohortId: %s.", cohortId);
end
end

function validateDirectReleaseData(data)
timeEnd = data.time(:);
houseIds = string(data.houseIds(:)).';
dtHours = double(data.dtHours);
if ~isdatetime(timeEnd) || isempty(timeEnd) || ~isscalar(dtHours) || ...
        ~isfinite(dtHours) || dtHours <= 0 || isempty(houseIds) || ...
        any(ismissing(houseIds)) || any(strlength(strip(houseIds)) == 0) || ...
        numel(unique(houseIds)) ~= numel(houseIds)
    error("StoreNet:InvalidObservedSbscData", ...
        "Observed time, dtHours, and unique houseIds must be well formed.");
end
expectedSize = [numel(timeEnd), numel(houseIds)];
fields = ["loadKW", "fromGridKW", "feedInKW", "chargeKW", ...
    "dischargeKW"];
for fieldIndex = 1:numel(fields)
    values = double(data.(fields(fieldIndex)));
    if ~isequal(size(values), expectedSize) || any(~isfinite(values), "all")
        error("StoreNet:InvalidObservedSbscData", ...
            "%s must be finite and aligned with time and houseIds.", ...
            fields(fieldIndex));
    end
end
end

function validateObservedCohort(houseIds, caseMeta)
cohortId = string(caseMeta.cohortId);
switch cohortId
    case "H20_PV10"
        expectedIds = compose("H%d", 1:20);
    case "H19_EXCL_H4_PV9"
        expectedIds = compose("H%d", [1:3, 5:20]);
    otherwise
        error("StoreNet:InvalidObservedSbscMetadata", ...
            "Unsupported observed cohortId: %s.", cohortId);
end
actualIds = string(houseIds(:)).';
if ~isequal(actualIds, expectedIds)
    error("StoreNet:InvalidObservedSbscMetadata", ...
        "Observed cohort %s does not match its declared houseIds.", cohortId);
end
if isfield(caseMeta, "houseCount") && ...
        (~isnumeric(caseMeta.houseCount) || ~isscalar(caseMeta.houseCount) || ...
        double(caseMeta.houseCount) ~= numel(expectedIds))
    error("StoreNet:InvalidObservedSbscMetadata", ...
        "Observed cohort %s disagrees with caseMeta.houseCount.", cohortId);
end
end
