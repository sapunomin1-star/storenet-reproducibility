function cfg = storenet_config(options)
%STORENET_CONFIG Canonical parameters and data conventions for replication.
%   CFG = STORENET_CONFIG() returns the paper parameters together with the
%   immutable Figshare processed-release location and quality-gate defaults.
%
%   Name-value options:
%     IntervalMinutes - Exact aggregation interval, either 30 or 60 minutes.
%     DataRoot        - Folder containing H1_W.csv ... H20_Wh.csv.
%     DataMode        - Must remain "processed-release" for this replication.
%     QualityMode     - Frozen data contracts:
%                         "release_literal" accepts physically complete,
%                           finite release values and exposes all flags.
%                         "short_gap_only" additionally limits raw missing
%                           W-status runs to 2 min and fraction to 0.005.
%                         "exclude_flagged_pv" adds the PV-window audit.
%                       Compatibility aliases map "report" to
%                       "release_literal" and "strict" to "short_gap_only";
%                       the strict alias also throws when its gate fails.

arguments
    options.IntervalMinutes (1, 1) double {mustBeMember(options.IntervalMinutes, [30, 60])} = 30
    options.DataRoot (1, 1) string = ""
    options.DataMode (1, 1) string {mustBeMember(options.DataMode, "processed-release")} = "processed-release"
    options.QualityMode (1, 1) string {mustBeMember(options.QualityMode, ...
        ["release_literal", "short_gap_only", "exclude_flagged_pv", ...
        "strict", "report"])} = "short_gap_only"
end

if strlength(options.DataRoot) == 0
    sourceFolder = fileparts(mfilename("fullpath"));
    options.DataRoot = string(fullfile(sourceFolder, "..", "data", "raw"));
end

cfg = struct;
cfg.releaseName = "StoreNet Figshare processed release";
cfg.releaseIsImmutable = true;
cfg.dataMode = options.DataMode;
cfg.dataRoot = options.DataRoot;
cfg.timestampBasis = "naive local wall-clock (timezone is not encoded)";
cfg.whTimestampConvention = ...
    "interval end; calendar day D uses (D 00:00, D+1 00:00]";

cfg.homes = compose("H%d", 1:20);
cfg.nHomes = numel(cfg.homes);
cfg.pvHomes = ["H1", "H2", "H3", "H4", "H5", ...
    "H7", "H10", "H11", "H13", "H17"];
cfg.pvHomeMask = ismember(cfg.homes, cfg.pvHomes);

cfg.intervalMinutes = options.IntervalMinutes;
cfg.dtHours = options.IntervalMinutes / 60;
cfg.qualityModeRequested = options.QualityMode;
if options.QualityMode == "strict"
    cfg.qualityMode = "short_gap_only";
elseif options.QualityMode == "report"
    cfg.qualityMode = "release_literal";
else
    cfg.qualityMode = options.QualityMode;
end
cfg.throwOnQualityFailure = options.QualityMode == "strict";
cfg.quality.maxPhysicalMissingMinuteFraction = 0;
cfg.quality.maxMissingStatusRunMinutes = 2;
cfg.quality.maxMissingStatusFraction = 0.005;
cfg.quality.pvActiveFractionOfDailyMaximum = 0.05;
cfg.quality.pvWindowToleranceHours = 0.5;
cfg.quality.dingleLatitudeDegrees = 52.14;

% Canonical parameters reported by Bahloul et al. (2022).
cfg.etaPvAC = 0.95;
cfg.etaPvDC = 0.95;
cfg.etaBatteryCharge = 0.95;
cfg.etaBatteryDischarge = 0.95;
cfg.transferLossFraction = 0.07;
cfg.selfDischargeKW = 0;
cfg.batteryCapacityKWh = 10;
cfg.batteryPowerKW = 3.3;
cfg.socInitialFraction = 0.10;
cfg.socMinFraction = 0.10;
cfg.socMaxFraction = 0.90;
cfg.socTerminalFraction = 0.10;
cfg.nightPrice = 0.091;
cfg.dayPrice = 0.194;
cfg.feedInPrice = 0;
cfg.dayStartHour = 10;
cfg.dayEndHour = 22;

% Solver tolerances are replication choices because the article does not
% report a solver/version/tolerance tuple.
cfg.mipRelativeGap = 1e-6;
cfg.constraintTolerance = 1e-8;
cfg.lexicographicTolerance = 1e-7;
end
