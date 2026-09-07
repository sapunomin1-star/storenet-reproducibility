function [caseData, caseConfig, caseMeta] = prepare_bahloul_case(data, config, options)
%PREPARE_BAHLOUL_CASE Apply a frozen B2022 cohort and PV-boundary scenario.
%   This function never edits the release. It creates an in-memory case for
%   either the public 20-home cohort or the paired 19-home H4 exclusion and
%   records whether the requested calendar day intersects the frozen H4 mask.

arguments
    data (1, 1) struct
    config (1, 1) struct
    options.CohortId (1, 1) string {mustBeMember(options.CohortId, ...
        ["H20_PV10", "H19_EXCL_H4_PV9", ...
        "PUBLIC_20", "EXCLUDE_H4_19"])} = "H20_PV10"
    options.PvBoundaryId (1, 1) string {mustBeMember(options.PvBoundaryId, ...
        ["DC_SOURCE", "AC_METER_RECONSTRUCTED_DC"])} = "DC_SOURCE"
    options.TransferLossFraction (1, 1) double ...
        {mustBeFinite, mustBeNonnegative, mustBeLessThanOrEqual(options.TransferLossFraction, 1)} = 0.07
    options.H4DiagnosticsPath (1, 1) string = ""
    options.RequireH4Status (1, 1) logical = true
    options.DataMeta (1, 1) struct = struct
    options.Provenance (1, 1) struct = struct
end

requiredData = ["time", "loadKW", "pvKW", "dtHours", "houseIds"];
missingData = requiredData(~isfield(data, cellstr(requiredData)));
if ~isempty(missingData)
    error("StoreNet:InvalidBahloulData", ...
        "Bahloul case data is missing field(s): %s.", strjoin(missingData, ", "));
end
requiredConfig = ["etaPvAC", "transferLossFraction"];
missingConfig = requiredConfig(~isfield(config, cellstr(requiredConfig)));
if ~isempty(missingConfig)
    error("StoreNet:InvalidBahloulConfig", ...
        "Bahloul config is missing field(s): %s.", strjoin(missingConfig, ", "));
end

caseData = data;
caseConfig = config;
cohortId = canonicalCohortId(options.CohortId);
caseData.time = caseData.time(:);
caseData.houseIds = string(caseData.houseIds(:)).';
releasedPvKW = double(caseData.pvKW);
caseData.releasedPvKW = releasedPvKW;

switch options.PvBoundaryId
    case "DC_SOURCE"
        modelPvKW = releasedPvKW;
    case "AC_METER_RECONSTRUCTED_DC"
        modelPvKW = releasedPvKW ./ double(config.etaPvAC);
end
caseData.pvKW = modelPvKW;
if isfield(caseData, "pvKWh")
    caseData.releasedPvKWh = double(caseData.pvKWh);
    caseData.pvKWh = caseData.pvKW .* double(caseData.dtHours);
end

homeMask = true(1, numel(caseData.houseIds));
if cohortId == "H19_EXCL_H4_PV9"
    h4Index = find(caseData.houseIds == "H4");
    if ~isscalar(h4Index)
        error("StoreNet:MissingH4", ...
            "EXCLUDE_H4_19 requires exactly one H4 column.");
    end
    homeMask(h4Index) = false;
end
caseData = subsetHomeFields(caseData, homeMask);
caseData.houseIds = caseData.houseIds(homeMask);
if isfield(caseData, "homeNames")
    caseData.homeNames = string(caseData.homeNames(homeMask));
end

if isfield(config, "homes")
    caseConfig.homes = string(config.homes(homeMask));
else
    caseConfig.homes = caseData.houseIds;
end
caseConfig.nHomes = nnz(homeMask);
if isfield(config, "pvHomeMask")
    caseConfig.pvHomeMask = logical(config.pvHomeMask(homeMask));
elseif isfield(caseData, "pvHomeMask")
    caseConfig.pvHomeMask = logical(caseData.pvHomeMask);
else
    caseConfig.pvHomeMask = any(caseData.releasedPvKW > 0, 1);
end
caseConfig.pvHomes = caseData.houseIds(caseConfig.pvHomeMask);
caseConfig.transferLossFraction = options.TransferLossFraction;
caseConfig.pvBoundaryId = options.PvBoundaryId;
caseConfig.cohortId = cohortId;
caseConfig.selfDischargeKW = 0;

day = inferCaseDay(caseData);
[h4Affected, h4Category] = lookupH4Status(day, options.H4DiagnosticsPath, ...
    options.RequireH4Status);

caseMeta = struct;
caseMeta.day = day;
caseMeta.cohortId = cohortId;
caseMeta.houseIds = caseData.houseIds;
caseMeta.houseCount = numel(caseData.houseIds);
caseMeta.pvHomeCount = nnz(caseConfig.pvHomeMask);
caseMeta.excludedHomes = string(data.houseIds(~homeMask));
caseMeta.pvBoundaryId = options.PvBoundaryId;
caseMeta.transferLossFraction = options.TransferLossFraction;
caseMeta.h4MaskAffected = h4Affected;
caseMeta.h4AlignmentCategory = h4Category;
caseMeta.h4InputWasShiftedOrRepaired = false;
caseMeta.releasedPvPreserved = true;
caseMeta.cohortMask = logical(homeMask);
caseMeta = attachQualityEvidence(caseMeta, options.DataMeta, homeMask);
caseMeta = attachProvenance(caseMeta, options.Provenance);
end

function meta = attachQualityEvidence(meta, dataMeta, homeMask)
if isempty(fieldnames(dataMeta))
    return
end
meta.dataMeta = dataMeta;
if isfield(dataMeta, "qualityMode")
    meta.qualityMode = string(dataMeta.qualityMode);
end
if isfield(dataMeta, "binObserved")
    observed = logical(dataMeta.binObserved);
    if size(observed, 2) == numel(homeMask)
        meta.observationMask = observed(:, homeMask);
    end
end
if isfield(dataMeta, "binComplete")
    complete = logical(dataMeta.binComplete);
    if size(complete, 2) == numel(homeMask)
        complete = complete(:, homeMask);
        if isfield(meta, "observationMask") && ...
                isequal(size(meta.observationMask), size(complete))
            meta.interpolationMask = complete & ~meta.observationMask;
        else
            meta.interpolationMask = false(size(complete));
        end
    end
end
end

function meta = attachProvenance(meta, provenance)
allowed = ["dataContractId", "dataContractSha256", ...
    "dataContractGitCommit", "modelContractId", ...
    "modelContractSha256", "referenceIds", "referenceHashes", ...
    "referenceManifestSha256", "solverProvenance", ...
    "dataProviderProvenance"];
fields = string(fieldnames(provenance));
unexpected = fields(~ismember(fields, allowed));
if ~isempty(unexpected)
    error("StoreNet:InvalidBahloulProvenance", ...
        "Unexpected case provenance field(s): %s.", ...
        strjoin(unexpected, ", "));
end
for fieldIndex = 1:numel(fields)
    field = fields(fieldIndex);
    meta.(field) = provenance.(field);
end
end

function cohortId = canonicalCohortId(requestedId)
switch requestedId
    case {"H20_PV10", "PUBLIC_20"}
        cohortId = "H20_PV10";
    case {"H19_EXCL_H4_PV9", "EXCLUDE_H4_19"}
        cohortId = "H19_EXCL_H4_PV9";
end
end

function data = subsetHomeFields(data, homeMask)
fieldNames = ["loadKW", "pvKW", "releasedPvKW", "dischargeKWh", ...
    "chargeKWh", "pvKWh", "releasedPvKWh", "loadKWh", "feedInKWh", ...
    "fromGridKWh", "socFraction", "dischargeKW", "chargeKW", ...
    "feedInKW", "fromGridKW", "balanceResidualKWh", "pvHomeMask"];
for fieldIndex = 1:numel(fieldNames)
    field = fieldNames(fieldIndex);
    if ~isfield(data, field)
        continue
    end
    value = data.(field);
    if isvector(value) && numel(value) == numel(homeMask)
        data.(field) = value(homeMask);
    elseif ismatrix(value) && size(value, 2) == numel(homeMask)
        data.(field) = value(:, homeMask);
    else
        error("StoreNet:InvalidBahloulHomeField", ...
            "Field %s cannot be aligned to the household cohort.", field);
    end
end
end

function day = inferCaseDay(data)
if isfield(data, "day") && isdatetime(data.day) && isscalar(data.day)
    day = dateshift(data.day, "start", "day");
else
    day = dateshift(data.time(1) - hours(double(data.dtHours)), ...
        "start", "day");
end
end

function [affected, category] = lookupH4Status(day, path, required)
if strlength(path) == 0
    sourceFolder = fileparts(mfilename("fullpath"));
    path = string(fullfile(sourceFolder, "..", "results", ...
        "data_paper_figures_5_10_v2", ...
        "figure6_h4_daily_diagnostics.csv"));
end
if ~isfile(path)
    if required
        error("StoreNet:MissingH4Diagnostics", ...
            "Frozen H4 diagnostics are missing: %s", path);
    end
    affected = NaN;
    category = "unavailable";
    return
end

diagnostics = readtable(path, TextType="string");
requiredColumns = ["Date", "AlignmentCategory"];
if ~all(ismember(requiredColumns, string(diagnostics.Properties.VariableNames)))
    error("StoreNet:InvalidH4Diagnostics", ...
        "H4 diagnostics must contain Date and AlignmentCategory.");
end
if isdatetime(diagnostics.Date)
    diagnosticDates = dateshift(diagnostics.Date, "start", "day");
else
    diagnosticDates = datetime(string(diagnostics.Date), ...
        InputFormat="yyyy-MM-dd");
end
selected = diagnosticDates == day;
if ~any(selected)
    if required
        error("StoreNet:MissingH4Day", ...
            "H4 diagnostics do not contain %s.", string(day, "yyyy-MM-dd"));
    end
    affected = NaN;
    category = "unavailable";
    return
end
categories = unique(diagnostics.AlignmentCategory(selected));
if numel(categories) ~= 1
    error("StoreNet:AmbiguousH4Day", ...
        "H4 diagnostics contain inconsistent categories for %s.", ...
        string(day, "yyyy-MM-dd"));
end
category = categories;
affected = category ~= "unaffected_same0";
end
