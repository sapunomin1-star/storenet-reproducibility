function [monthly, daily] = aggregate_bahloul_monthly_csv(dailyMetricsPath, options)
%AGGREGATE_BAHLOUL_MONTHLY_CSV Regroup saved daily metrics without solving.
%   MONTHLY = AGGREGATE_BAHLOUL_MONTHLY_CSV(DAILYMETRICSPATH) groups the
%   saved rows by calendar month and strategy. Explicit
%   PaperLoadOnlyBaselineBillEUR values are reused when present. For legacy
%   StoreNet CSV files, BaselineBillEUR is retained only as the PV-self,
%   no-battery baseline; the paper load-only bill and peaks are recomputed
%   from the public load data and the saved run manifest tariff without
%   invoking a solver.
%   [MONTHLY, DAILY] also returns the normalized daily rows with explicit
%   paper-load-only and PV-self-no-battery baseline, savings, percentage,
%   and source columns. The second output lets an offline runner reuse the
%   same resolved daily values without reading data or recomputing them.
%
%   Name-value options:
%     OutputPath   - Optional CSV destination for the regrouped table.
%     ManifestPath - Legacy run manifest. Defaults to manifest.json beside
%                    DAILYMETRICSPATH and is unused for explicit paper rows.
%     DataRoot     - Optional override for the manifest's public data root.
%     DataProvider - Offline public-data reader; defaults to
%                    load_storenet_day.

%   The aggregation matches run_bahloul_monthly_v1: daily arithmetic means
%   are reported alongside the ratio computed from summed daily costs.

arguments
    dailyMetricsPath (1, 1) string
    options.OutputPath (1, 1) string = ""
    options.ManifestPath (1, 1) string = ""
    options.DataRoot (1, 1) string = ""
    options.DataProvider (1, 1) function_handle = @load_storenet_day
end

if ~isfile(dailyMetricsPath)
    error("StoreNet:MonthlyCsvNotFound", ...
        "Daily metrics CSV does not exist: %s", dailyMetricsPath);
end

daily = readtable(dailyMetricsPath, TextType="string");
daily = normalizeDailyTable(daily);
[paperBillEUR, paperPeakKW, paperDaytimePeakKW, paperSource] = ...
    resolvePaperBaseline( ...
    daily, dailyMetricsPath, options);
[pvSelfBillEUR, pvSelfSource] = resolvePvSelfBaseline(daily);
daily.PaperLoadOnlyBaselineBillEUR = paperBillEUR;
daily.PaperLoadOnlyPeakKW = paperPeakKW;
daily.PaperLoadOnlyDaytimePeakKW = paperDaytimePeakKW;
daily.PvSelfNoBatteryBaselineBillEUR = pvSelfBillEUR;
daily.PaperLoadOnlyBaselineSource = repmat(paperSource, height(daily), 1);
daily.PvSelfNoBatteryBaselineSource = repmat(pvSelfSource, height(daily), 1);
daily.PaperLoadOnlySavingsEUR = paperBillEUR - daily.OptimizedBillEUR;
daily.PaperLoadOnlySavingsPercent = safePercent( ...
    daily.PaperLoadOnlySavingsEUR, paperBillEUR);
daily.PvSelfNoBatterySavingsEUR = pvSelfBillEUR - daily.OptimizedBillEUR;
daily.PvSelfNoBatterySavingsPercent = safePercent( ...
    daily.PvSelfNoBatterySavingsEUR, pvSelfBillEUR);
validateSuccessfulRows(daily, pvSelfSource);

keys = unique(daily(:, ["YearMonth", "Strategy"]), "rows", "stable");
rows = repmat(emptyMonthlyRow(), height(keys), 1);
for keyIndex = 1:height(keys)
    selected = daily.YearMonth == keys.YearMonth(keyIndex) & ...
        daily.Strategy == keys.Strategy(keyIndex);
    valid = selected & daily.Status == "ok";
    row = emptyMonthlyRow();
    row.YearMonth = keys.YearMonth(keyIndex);
    row.Strategy = keys.Strategy(keyIndex);
    row.PaperLoadOnlyBaselineSource = paperSource;
    row.PvSelfNoBatteryBaselineSource = pvSelfSource;
    row.RequestedDays = numel(unique(daily.Day(selected)));
    row.CandidateDays = row.RequestedDays;
    row.ValidDays = numel(unique(daily.Day(valid)));
    row.FailedOrRejectedDays = row.RequestedDays - row.ValidDays;
    row.UnavailableCandidateDays = 0;
    row.PaperPeriodRelation = periodRelation(row.YearMonth);
    row.PublicReleaseAvailability = "available_from_public_release";
    row.MeanDailyPaperLoadOnlyBaselineBillEUR = meanOrNaN( ...
        daily.PaperLoadOnlyBaselineBillEUR(valid));
    row.MeanDailyPaperLoadOnlySavingsEUR = meanOrNaN( ...
        daily.PaperLoadOnlySavingsEUR(valid));
    row.MeanDailyPaperLoadOnlySavingsPercent = meanOrNaN( ...
        daily.PaperLoadOnlySavingsPercent(valid));
    row.MeanDailyPvSelfNoBatteryBaselineBillEUR = meanOrNaN( ...
        daily.PvSelfNoBatteryBaselineBillEUR(valid));
    row.MeanDailyPvSelfNoBatterySavingsEUR = meanOrNaN( ...
        daily.PvSelfNoBatterySavingsEUR(valid));
    row.MeanDailyPvSelfNoBatterySavingsPercent = meanOrNaN( ...
        daily.PvSelfNoBatterySavingsPercent(valid));
    row.SumPaperLoadOnlyBaselineBillEUR = sumOrNaN( ...
        daily.PaperLoadOnlyBaselineBillEUR(valid));
    row.SumPvSelfNoBatteryBaselineBillEUR = sumOrNaN( ...
        daily.PvSelfNoBatteryBaselineBillEUR(valid));
    row.SumOptimizedBillEUR = sumOrNaN(daily.OptimizedBillEUR(valid));
    row.RatioOfSummedCostsPaperLoadOnlySavingsPercent = safePercent( ...
        row.SumPaperLoadOnlyBaselineBillEUR - row.SumOptimizedBillEUR, ...
        row.SumPaperLoadOnlyBaselineBillEUR);
    row.RatioOfSummedCostsPaperLoadOnlySavingsPercentDenominatorIsZero = ...
        denominatorFlag(row.SumPaperLoadOnlyBaselineBillEUR);
    row.RatioOfSummedCostsPvSelfNoBatterySavingsPercent = safePercent( ...
        row.SumPvSelfNoBatteryBaselineBillEUR - row.SumOptimizedBillEUR, ...
        row.SumPvSelfNoBatteryBaselineBillEUR);
    row.MeanDailyOutcomePeakImportKW = meanOrNaN( ...
        daily.OutcomePeakImportKW(valid));
    rows(keyIndex) = row;
end
monthly = struct2table(rows);
monthly = sortrows(monthly, ["YearMonth", "Strategy"]);
monthly.YearMonth.Format = "yyyy-MM";

if strlength(options.OutputPath) > 0
    outputFolder = string(fileparts(options.OutputPath));
    if strlength(outputFolder) > 0 && ~isfolder(outputFolder)
        mkdir(outputFolder);
    end
    writetable(monthly, options.OutputPath);
end
end

function daily = normalizeDailyTable(daily)
required = ["Day", "Strategy", "Status", "OptimizedBillEUR"];
variables = string(daily.Properties.VariableNames);
missing = required(~ismember(required, variables));
if ~isempty(missing)
    error("StoreNet:MonthlyCsvMissingColumn", ...
        "Daily metrics CSV is missing column(s): %s.", strjoin(missing, ", "));
end
if isempty(daily)
    error("StoreNet:InvalidMonthlyCsv", ...
        "Daily metrics CSV must contain at least one row.");
end

daily.Day = normalizeDay(daily.Day);
daily.YearMonth = dateshift(daily.Day, "start", "month");
daily.Strategy = strip(string(daily.Strategy));
daily.Status = strip(string(daily.Status));
daily.OptimizedBillEUR = numericColumn(daily, "OptimizedBillEUR");
if any(strlength(daily.Strategy) == 0) || any(strlength(daily.Status) == 0)
    error("StoreNet:InvalidMonthlyCsv", ...
        "Strategy and Status must be nonempty for every daily row.");
end

keys = daily(:, ["Day", "Strategy"]);
if height(unique(keys, "rows")) ~= height(keys)
    error("StoreNet:InvalidMonthlyCsv", ...
        "Daily metrics CSV contains duplicate Day/Strategy rows.");
end

if ismember("OutcomePeakImportKW", variables)
    outcomePeakImportKW = numericColumn(daily, "OutcomePeakImportKW");
elseif ismember("PeakImportKW", variables)
    outcomePeakImportKW = numericColumn(daily, "PeakImportKW");
else
    outcomePeakImportKW = nan(height(daily), 1);
end
daily.OutcomePeakImportKW = outcomePeakImportKW;
end

function day = normalizeDay(value)
if isdatetime(value)
    day = value(:);
else
    try
        day = datetime(string(value(:)), Locale="en_US");
    catch exception
        error("StoreNet:InvalidMonthlyCsv", ...
            "Day cannot be parsed as a calendar date (%s): %s", ...
            exception.identifier, exception.message);
    end
end
if any(isnat(day))
    error("StoreNet:InvalidMonthlyCsv", ...
        "Day must contain a finite calendar date in every row.");
end
day = dateshift(day, "start", "day");
end

function values = numericColumn(daily, name)
candidate = daily.(name);
if ~isnumeric(candidate) && ~islogical(candidate)
    error("StoreNet:InvalidMonthlyCsv", ...
        "Column %s must be numeric.", name);
end
values = double(candidate(:));
end

function [paperBillEUR, paperPeakKW, paperDaytimePeakKW, source] = ...
        resolvePaperBaseline( ...
        daily, dailyMetricsPath, options)
variables = string(daily.Properties.VariableNames);
if ismember("PaperLoadOnlyBaselineBillEUR", variables)
    paperBillEUR = numericColumn(daily, ...
        "PaperLoadOnlyBaselineBillEUR");
    paperPeakKW = optionalNumericColumn(daily, ...
        "PaperLoadOnlyPeakKW");
    paperDaytimePeakKW = optionalNumericColumn(daily, ...
        "PaperLoadOnlyDaytimePeakKW");
    source = "daily_csv:PaperLoadOnlyBaselineBillEUR";
    return
end

paperBillEUR = nan(height(daily), 1);
paperPeakKW = nan(height(daily), 1);
paperDaytimePeakKW = nan(height(daily), 1);
successfulDays = unique(daily.Day(daily.Status == "ok"), "sorted");
if isempty(successfulDays)
    source = "not_required:no_successful_rows";
    return
end
settings = legacyRecomputeSettings(dailyMetricsPath, options);
dailyBills = nan(numel(successfulDays), 1);
dailyPeaks = nan(numel(successfulDays), 1);
dailyDaytimePeaks = nan(numel(successfulDays), 1);
for dayIndex = 1:numel(successfulDays)
    calendarDay = successfulDays(dayIndex);
    try
        [data, meta] = options.DataProvider(calendarDay, ...
            DataRoot=settings.dataRoot, ...
            IntervalMinutes=settings.intervalMinutes, ...
            QualityMode=settings.qualityMode);
        validateProviderQuality(data, meta, calendarDay);
        [dailyBills(dayIndex), dailyPeaks(dayIndex), ...
            dailyDaytimePeaks(dayIndex)] = loadOnlyBaseline( ...
            data, settings, calendarDay);
    catch exception
        error("StoreNet:PaperBaselineUnavailable", ...
            "Cannot recompute paper load-only baseline for %s (%s): %s", ...
            string(calendarDay, "yyyy-MM-dd"), exception.identifier, ...
            exception.message);
    end
end
for dayIndex = 1:numel(successfulDays)
    paperBillEUR(daily.Day == successfulDays(dayIndex)) = ...
        dailyBills(dayIndex);
    paperPeakKW(daily.Day == successfulDays(dayIndex)) = ...
        dailyPeaks(dayIndex);
    paperDaytimePeakKW(daily.Day == successfulDays(dayIndex)) = ...
        dailyDaytimePeaks(dayIndex);
end
source = "offline_recomputed:" + string(func2str(options.DataProvider));
end

function values = optionalNumericColumn(daily, name)
if ismember(name, string(daily.Properties.VariableNames))
    values = numericColumn(daily, name);
else
    values = nan(height(daily), 1);
end
end

function settings = legacyRecomputeSettings(dailyMetricsPath, options)
manifestPath = options.ManifestPath;
if strlength(manifestPath) == 0
    manifestPath = string(fullfile(fileparts(dailyMetricsPath), ...
        "manifest.json"));
end
if ~isfile(manifestPath)
    error("StoreNet:PaperBaselineUnavailable", ...
        "Legacy CSV has no explicit paper baseline and its run manifest is missing: %s", ...
        manifestPath);
end
try
    manifest = jsondecode(fileread(manifestPath));
catch exception
    error("StoreNet:PaperBaselineUnavailable", ...
        "Cannot read legacy run manifest %s (%s): %s", manifestPath, ...
        exception.identifier, exception.message);
end
if ~isfield(manifest, "experiment") || ...
        ~isfield(manifest.experiment, "configuration")
    error("StoreNet:PaperBaselineUnavailable", ...
        "Legacy run manifest has no experiment.configuration: %s", ...
        manifestPath);
end
configuration = manifest.experiment.configuration;
required = ["intervalMinutes", "nightPrice", "dayPrice", ...
    "dayStartHour", "dayEndHour"];
missing = required(~isfield(configuration, cellstr(required)));
if ~isempty(missing)
    error("StoreNet:PaperBaselineUnavailable", ...
        "Legacy run manifest is missing tariff field(s): %s.", ...
        strjoin(missing, ", "));
end

settings = struct;
settings.intervalMinutes = double(configuration.intervalMinutes);
settings.nightPrice = double(configuration.nightPrice);
settings.dayPrice = double(configuration.dayPrice);
settings.dayStartHour = double(configuration.dayStartHour);
settings.dayEndHour = double(configuration.dayEndHour);
if isfield(configuration, "qualityMode")
    settings.qualityMode = string(configuration.qualityMode);
elseif isfield(manifest.experiment, "qualityMode")
    settings.qualityMode = string(manifest.experiment.qualityMode);
else
    error("StoreNet:PaperBaselineUnavailable", ...
        "Legacy run manifest has no qualityMode: %s", manifestPath);
end
settings.dataRoot = options.DataRoot;
if strlength(settings.dataRoot) == 0 && isfield(configuration, "dataRoot")
    settings.dataRoot = string(configuration.dataRoot);
end

numericSettings = [settings.intervalMinutes, settings.nightPrice, ...
    settings.dayPrice, settings.dayStartHour, settings.dayEndHour];
if any(~isfinite(numericSettings)) || ...
        ~ismember(settings.intervalMinutes, [30, 60]) || ...
        settings.nightPrice < 0 || settings.dayPrice < 0 || ...
        settings.dayStartHour < 0 || settings.dayEndHour > 24 || ...
        settings.dayStartHour >= settings.dayEndHour || ...
        strlength(settings.qualityMode) == 0
    error("StoreNet:PaperBaselineUnavailable", ...
        "Legacy run manifest contains invalid interval, tariff, or quality settings: %s", ...
        manifestPath);
end
end

function validateProviderQuality(data, meta, calendarDay)
if isstruct(meta) && isfield(meta, "qualityPassed")
    passed = logical(meta.qualityPassed);
    if ~isscalar(passed) || ~passed
        error("StoreNet:OfflineDataRejected", ...
            "Public data reader rejected %s.", ...
            string(calendarDay, "yyyy-MM-dd"));
    end
elseif isstruct(data) && isfield(data, "validForOptimization")
    passed = logical(data.validForOptimization);
    if ~isscalar(passed) || ~passed
        error("StoreNet:OfflineDataRejected", ...
            "Public data reader rejected %s.", ...
            string(calendarDay, "yyyy-MM-dd"));
    end
end
end

function [billEUR, peakKW, daytimePeakKW] = loadOnlyBaseline( ...
        data, settings, calendarDay)
if ~isstruct(data) || ~isfield(data, "loadKW") || ...
        ~isfield(data, "dtHours") || ...
        (~isfield(data, "time") && ~isfield(data, "timeEnd"))
    error("StoreNet:InvalidOfflineData", ...
        "Public data reader did not return time, loadKW, and dtHours.");
end
if isfield(data, "time")
    timeEnd = data.time(:);
else
    timeEnd = data.timeEnd(:);
end
loadKW = double(data.loadKW);
dtHours = double(data.dtHours);
if ~isdatetime(timeEnd) || isempty(timeEnd) || ...
        ~isnumeric(loadKW) || size(loadKW, 1) ~= numel(timeEnd) || ...
        any(~isfinite(loadKW), "all") || any(loadKW < 0, "all") || ...
        ~isscalar(dtHours) || ~isfinite(dtHours) || dtHours <= 0 || ...
        abs(dtHours - settings.intervalMinutes / 60) > 1e-12
    error("StoreNet:InvalidOfflineData", ...
        "Public load data must be finite, nonnegative, aligned, and use the manifest interval.");
end
inferredDay = dateshift(timeEnd(1) - hours(dtHours), "start", "day");
if inferredDay ~= dateshift(calendarDay, "start", "day")
    error("StoreNet:InvalidOfflineData", ...
        "Public load data is not aligned with requested day %s.", ...
        string(calendarDay, "yyyy-MM-dd"));
end

intervalStart = timeEnd - hours(dtHours);
dayMask = hour(intervalStart) >= settings.dayStartHour & ...
    hour(intervalStart) < settings.dayEndHour;
if ~any(dayMask)
    error("StoreNet:InvalidOfflineData", ...
        "Public load data has no interval inside the manifest daytime window.");
end
pricePerKWh = repmat(settings.nightPrice, numel(timeEnd), 1);
pricePerKWh(dayMask) = settings.dayPrice;
paperImportKW = sum(loadKW, 2);
billEUR = dtHours .* sum(pricePerKWh .* paperImportKW, "all");
peakKW = max(paperImportKW);
daytimePeakKW = max(paperImportKW(dayMask));
baselineValues = [billEUR, peakKW, daytimePeakKW];
if any(~isfinite(baselineValues)) || any(baselineValues < 0)
    error("StoreNet:InvalidOfflineData", ...
        "Recomputed paper load-only bill and peaks must be finite nonnegative scalars.");
end
end

function [pvSelfBillEUR, source] = resolvePvSelfBaseline(daily)
variables = string(daily.Properties.VariableNames);
if ismember("PvSelfNoBatteryBaselineBillEUR", variables)
    pvSelfBillEUR = numericColumn(daily, ...
        "PvSelfNoBatteryBaselineBillEUR");
    source = "daily_csv:PvSelfNoBatteryBaselineBillEUR";
elseif ismember("BaselineBillEUR", variables)
    pvSelfBillEUR = numericColumn(daily, "BaselineBillEUR");
    source = "daily_csv:BaselineBillEUR (legacy PV-self)";
else
    pvSelfBillEUR = nan(height(daily), 1);
    source = "unavailable";
end
end

function validateSuccessfulRows(daily, pvSelfSource)
successful = daily.Status == "ok";
if any(~isfinite(daily.OptimizedBillEUR(successful))) || ...
        any(~isfinite(daily.PaperLoadOnlyBaselineBillEUR(successful)))
    error("StoreNet:InvalidMonthlyCsv", ...
        "Successful rows require finite optimized and paper load-only bills.");
end
if pvSelfSource ~= "unavailable" && ...
        any(~isfinite(daily.PvSelfNoBatteryBaselineBillEUR(successful)))
    error("StoreNet:InvalidMonthlyCsv", ...
        "Successful rows require a finite available PV-self baseline bill.");
end
end

function row = emptyMonthlyRow()
row = struct(YearMonth=NaT, Strategy="", ...
    PaperLoadOnlyBaselineSource="", PvSelfNoBatteryBaselineSource="", ...
    PaperPeriodRelation="", PublicReleaseAvailability="", ...
    CandidateDays=NaN, RequestedDays=NaN, ValidDays=NaN, ...
    FailedOrRejectedDays=NaN, UnavailableCandidateDays=NaN, ...
    MeanDailyPaperLoadOnlyBaselineBillEUR=NaN, ...
    MeanDailyPaperLoadOnlySavingsEUR=NaN, ...
    MeanDailyPaperLoadOnlySavingsPercent=NaN, ...
    MeanDailyPvSelfNoBatteryBaselineBillEUR=NaN, ...
    MeanDailyPvSelfNoBatterySavingsEUR=NaN, ...
    MeanDailyPvSelfNoBatterySavingsPercent=NaN, ...
    SumPaperLoadOnlyBaselineBillEUR=NaN, ...
    SumPvSelfNoBatteryBaselineBillEUR=NaN, ...
    SumOptimizedBillEUR=NaN, ...
    RatioOfSummedCostsPaperLoadOnlySavingsPercent=NaN, ...
    RatioOfSummedCostsPaperLoadOnlySavingsPercentDenominatorIsZero=NaN, ...
    RatioOfSummedCostsPvSelfNoBatterySavingsPercent=NaN, ...
    MeanDailyOutcomePeakImportKW=NaN);
end

function relation = periodRelation(yearMonth)
if year(yearMonth) == 2020 && month(yearMonth) <= 6
    relation = "2020-01--06_overlap";
elseif year(yearMonth) == 2020
    relation = "2020-07--12_extrapolation";
else
    relation = "outside_frozen_period";
end
end

function value = meanOrNaN(values)
finiteValues = values(isfinite(values));
if isempty(finiteValues)
    value = NaN;
else
    value = mean(finiteValues);
end
end

function value = sumOrNaN(values)
finiteValues = values(isfinite(values));
if isempty(finiteValues)
    value = NaN;
else
    value = sum(finiteValues);
end
end

function percentage = safePercent(numerator, denominator)
percentage = nan(size(numerator));
usable = isfinite(numerator) & isfinite(denominator) & ...
    abs(denominator) > eps(max(1, abs(denominator)));
percentage(usable) = 100 .* numerator(usable) ./ denominator(usable);
end

function flag = denominatorFlag(denominator)
if ~isfinite(denominator)
    flag = NaN;
else
    flag = double(abs(denominator) <= eps(max(1, abs(denominator))));
end
end
