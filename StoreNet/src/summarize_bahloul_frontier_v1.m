function summary = summarize_bahloul_frontier_v1(runDirectory, options)
%SUMMARIZE_BAHLOUL_FRONTIER_V1 Offline aggregation of a frontier run.
%   SUMMARY = SUMMARIZE_BAHLOUL_FRONTIER_V1(DIR) reads strategy_metrics.csv
%   written by RUN_BAHLOUL_FRONTIER_V1 and derives, without any solver call:
%     consistency_checks.csv        re-solved VPP_BM/PS/SH_BM/PSDT/LL and
%                                   ratio-1 Peak Guard versus frozen values
%     anchor_comparison.csv         bill-free peak reduction per day
%     frontier_daily.csv            bill/peak frontier per day and ratio,
%                                   marginal cost and pre-registered knee
%     frontier_summary.csv          summed-cost frontier across days
%     tariff_daily.csv              demand-charge sweep per day and charge
%     tariff_summary.csv            demand-charge sweep across days
%     minimum_demand_charge.csv     smallest grid charge that keeps the
%                                   peak at or below P0 on each day
%     efficiency_comparison.csv     nominal versus recalibrated efficiency
%   Frozen reference files are read only for comparison; nothing is solved
%   and nothing outside DIR (or OutputDirectory) is written.

arguments
    runDirectory (1, 1) string
    options.OutputDirectory (1, 1) string = ""
    options.FormalTypicalMetricsPath (1, 1) string = ""
    options.FormalMonthlyMetricsPath (1, 1) string = ""
    options.PeakGuardMetricsPath (1, 1) string = ""
    options.ConsistencyRelativeTolerance (1, 1) double = 1e-6
end

if strlength(options.OutputDirectory) == 0
    options.OutputDirectory = runDirectory;
end
if ~isfolder(options.OutputDirectory)
    mkdir(options.OutputDirectory);
end
metrics = readMetrics(fullfile(runDirectory, "strategy_metrics.csv"));
references = loadReferences(options);

summary = struct;
summary.runDirectory = runDirectory;
summary.consistency = consistencyChecks(metrics, references, ...
    options.ConsistencyRelativeTolerance);
summary.anchors = anchorComparison(metrics);
summary.frontierDaily = frontierDaily(metrics, summary.anchors);
summary.frontierSummary = frontierSummary(summary.frontierDaily, ...
    summary.anchors);
summary.tariffDaily = tariffDaily(metrics, summary.anchors, ...
    summary.frontierDaily);
summary.tariffSummary = tariffSummary(summary.tariffDaily);
summary.minimumDemandCharge = minimumDemandCharge(summary.tariffDaily);
summary.efficiency = efficiencyComparison(metrics);

writeIfAny(summary.consistency, options.OutputDirectory, ...
    "consistency_checks.csv");
writeIfAny(summary.anchors, options.OutputDirectory, ...
    "anchor_comparison.csv");
writeIfAny(summary.frontierDaily, options.OutputDirectory, ...
    "frontier_daily.csv");
writeIfAny(summary.frontierSummary, options.OutputDirectory, ...
    "frontier_summary.csv");
writeIfAny(summary.tariffDaily, options.OutputDirectory, ...
    "tariff_daily.csv");
writeIfAny(summary.tariffSummary, options.OutputDirectory, ...
    "tariff_summary.csv");
writeIfAny(summary.minimumDemandCharge, options.OutputDirectory, ...
    "minimum_demand_charge.csv");
writeIfAny(summary.efficiency, options.OutputDirectory, ...
    "efficiency_comparison.csv");
end

%% ----------------------------------------------------------------------
function metrics = readMetrics(path)
if ~isfile(path)
    error("StoreNet:MissingFrontierMetrics", ...
        "Frontier metrics not found: %s", path);
end
metrics = readtable(path, TextType="string", DatetimeType="text");
for name = ["Day", "CaseId", "CaseKind", "Strategy", "Status"]
    metrics.(name) = string(metrics.(name));
end
end

function references = loadReferences(options)
references = struct;
references.typical = table;
references.monthly = table;
references.peakGuard = table;
if strlength(options.FormalTypicalMetricsPath) > 0
    typical = readtable(options.FormalTypicalMetricsPath, ...
        TextType="string", DatetimeType="text");
    typical = typical(string(typical.ScenarioId) == "DC_XI007_H20" & ...
        string(typical.ResultKind) == "MODEL_STRUCTURAL_PROXY", :);
    references.typical = table(normalizeDay(typical.Day), ...
        string(typical.Strategy), string(typical.Status), ...
        double(typical.OptimizedBillEUR), ...
        double(typical.OptimizedPeakImportKW), ...
        VariableNames=["Day", "Strategy", "Status", "BillEUR", "PeakKW"]);
end
if strlength(options.FormalMonthlyMetricsPath) > 0
    monthly = readtable(options.FormalMonthlyMetricsPath, ...
        TextType="string", DatetimeType="text");
    monthly = monthly(string(monthly.ScenarioId) == "DC_XI007_H20", :);
    references.monthly = table(normalizeDay(monthly.Day), ...
        string(monthly.Strategy), string(monthly.Status), ...
        double(monthly.OptimizedBillEUR), ...
        double(monthly.OutcomePeakImportKW), ...
        VariableNames=["Day", "Strategy", "Status", "BillEUR", "PeakKW"]);
end
if strlength(options.PeakGuardMetricsPath) > 0
    guard = readtable(options.PeakGuardMetricsPath, ...
        TextType="string", DatetimeType="text");
    guard = guard(string(guard.Strategy) == "IMPROVED_PEAK_GUARD", :);
    references.peakGuard = table(normalizeDay(guard.Day), ...
        string(guard.Status), double(guard.OptimizedBillEUR), ...
        double(guard.AllDayPeakKW), double(guard.PeakGuardCapKW), ...
        VariableNames=["Day", "Status", "BillEUR", "PeakKW", "CapKW"]);
end
end

function days = normalizeDay(values)
values = string(values);
days = strings(size(values));
for index = 1:numel(values)
    parsed = NaT;
    for format = ["dd-MMM-yyyy", "yyyy-MM-dd"]
        try
            parsed = datetime(values(index), InputFormat=format);
        catch
            continue
        end
        if ~isnat(parsed)
            break
        end
    end
    if isnat(parsed)
        error("StoreNet:UnparsableReferenceDay", ...
            "Cannot parse reference day '%s'.", values(index));
    end
    days(index) = string(parsed, "yyyy-MM-dd");
end
end

%% ----------------------------------------------------------------------
function checks = consistencyChecks(metrics, references, tolerance)
rows = emptyCheckRows();
anchors = metrics(metrics.CaseKind == "anchor" & metrics.Status == "ok", :);
for index = 1:height(anchors)
    day = anchors.Day(index);
    strategy = anchors.Strategy(index);
    reference = selectReference(references, day, strategy);
    if isempty(reference)
        continue
    end
    rows(end + 1, 1) = checkRow(day, strategy, "formal", ...
        anchors.OptimizedBillEUR(index), reference.BillEUR, ...
        anchors.AllDayPeakKW(index), reference.PeakKW, tolerance); %#ok<AGROW>
end
guards = metrics(metrics.CaseKind == "frontier" & ...
    abs(metrics.CapRatio - 1) < 1e-12 & metrics.Status == "ok", :);
if ~isempty(references.peakGuard)
    for index = 1:height(guards)
        day = guards.Day(index);
        reference = references.peakGuard(references.peakGuard.Day == day & ...
            references.peakGuard.Status == "ok", :);
        if height(reference) ~= 1
            continue
        end
        rows(end + 1, 1) = checkRow(day, "IMPROVED_PEAK_GUARD", ...
            "peak_guard_v1", guards.OptimizedBillEUR(index), ...
            reference.BillEUR, guards.AllDayPeakKW(index), ...
            reference.PeakKW, tolerance); %#ok<AGROW>
        capDifference = abs(guards.CapKW(index) - reference.CapKW);
        rows(end).CapDifferenceKW = capDifference;
        rows(end).Passed = rows(end).Passed && capDifference <= 1e-9;
    end
end
checks = struct2table(rows);
end

function reference = selectReference(references, day, strategy)
reference = table;
for name = ["typical", "monthly"]
    candidate = references.(name);
    if isempty(candidate)
        continue
    end
    selected = candidate(candidate.Day == day & ...
        candidate.Strategy == strategy & candidate.Status == "ok", :);
    if height(selected) == 1
        reference = selected;
        return
    end
end
end

function rows = emptyCheckRows()
rows = repmat(checkRow("", "", "", NaN, NaN, NaN, NaN, NaN), 0, 1);
end

function row = checkRow(day, strategy, referenceKind, bill, referenceBill, ...
        peak, referencePeak, tolerance)
row = struct;
row.Day = string(day);
row.Strategy = string(strategy);
row.ReferenceKind = string(referenceKind);
row.BillEUR = bill;
row.ReferenceBillEUR = referenceBill;
row.BillRelativeDifference = relativeDifference(bill, referenceBill);
row.PeakKW = peak;
row.ReferencePeakKW = referencePeak;
row.PeakRelativeDifference = relativeDifference(peak, referencePeak);
row.CapDifferenceKW = NaN;
row.Tolerance = tolerance;
row.Passed = row.BillRelativeDifference <= tolerance & ...
    row.PeakRelativeDifference <= tolerance;
end

function value = relativeDifference(candidate, reference)
value = abs(candidate - reference) ./ max(1, abs(reference));
end

%% ----------------------------------------------------------------------
function anchors = anchorComparison(metrics)
days = unique(metrics.Day, "stable");
rows = repmat(emptyAnchorRow(), 0, 1);
for index = 1:numel(days)
    day = days(index);
    vpp = pickCase(metrics, day, "ANCHOR_VPP_BM");
    lex = pickCase(metrics, day, "ANCHOR_VPP_BM_PEAK_LEX");
    ps = pickCase(metrics, day, "ANCHOR_PS");
    if isempty(vpp) || isempty(lex)
        continue
    end
    row = emptyAnchorRow();
    row.Day = day;
    row.OriginalLoadPeakKW = vpp.OriginalLoadPeakKW;
    row.P0KW = vpp.PvSelfNoBatteryPeakKW;
    row.PaperLoadOnlyBaselineBillEUR = vpp.PaperLoadOnlyBaselineBillEUR;
    row.PvSelfNoBatteryBaselineBillEUR = vpp.PvSelfNoBatteryBaselineBillEUR;
    row.VppBillEUR = vpp.OptimizedBillEUR;
    row.VppPeakKW = vpp.AllDayPeakKW;
    row.VppNightPeakKW = vpp.NightPeakKW;
    row.VppDaytimePeakKW = vpp.DaytimePeakKW;
    row.VppPaperSavingsPercent = vpp.PaperSavingsPercent;
    row.VppThroughputKWh = vpp.BatteryThroughputKWh;
    row.LexBillEUR = lex.OptimizedBillEUR;
    row.LexPeakKW = lex.AllDayPeakKW;
    row.LexNightPeakKW = lex.NightPeakKW;
    row.LexDaytimePeakKW = lex.DaytimePeakKW;
    row.LexPaperSavingsPercent = lex.PaperSavingsPercent;
    row.LexThroughputKWh = lex.BatteryThroughputKWh;
    row.LexStatus = lex.Status;
    row.BillDifferenceLexMinusVppEUR = lex.OptimizedBillEUR - ...
        vpp.OptimizedBillEUR;
    row.BillDifferenceWithinAllowance = ...
        abs(row.BillDifferenceLexMinusVppEUR) <= ...
        1e-7 * max(1, abs(vpp.OptimizedBillEUR)) + 1e-9;
    row.FreePeakReductionKW = vpp.AllDayPeakKW - lex.AllDayPeakKW;
    row.FreePeakReductionPercent = 100 * row.FreePeakReductionKW / ...
        vpp.AllDayPeakKW;
    row.VppPeakExcessOverP0KW = vpp.AllDayPeakKW - row.P0KW;
    row.LexPeakExcessOverP0KW = lex.AllDayPeakKW - row.P0KW;
    row.LexPeakRatioToP0 = lex.AllDayPeakKW / row.P0KW;
    row.LexPeakAtOrBelowP0 = lex.AllDayPeakKW <= row.P0KW + 1e-6;
    row.FreeShareOfExcessOverP0Percent = 100 * row.FreePeakReductionKW / ...
        max(row.VppPeakExcessOverP0KW, eps);
    if ~isempty(ps)
        row.PsBillEUR = ps.OptimizedBillEUR;
        row.PsPeakKW = ps.AllDayPeakKW;
        row.PsPaperSavingsPercent = ps.PaperSavingsPercent;
        row.TotalReduciblePeakKW = vpp.AllDayPeakKW - ps.AllDayPeakKW;
        row.FreeShareOfReduciblePeakPercent = 100 * ...
            row.FreePeakReductionKW / max(row.TotalReduciblePeakKW, eps);
        row.PsBillPenaltyEUR = ps.OptimizedBillEUR - vpp.OptimizedBillEUR;
    end
    rows(end + 1, 1) = row; %#ok<AGROW>
end
anchors = struct2table(rows);
end

function row = emptyAnchorRow()
row = struct("Day", "", "OriginalLoadPeakKW", NaN, "P0KW", NaN, ...
    "PaperLoadOnlyBaselineBillEUR", NaN, ...
    "PvSelfNoBatteryBaselineBillEUR", NaN, ...
    "VppBillEUR", NaN, "VppPeakKW", NaN, "VppNightPeakKW", NaN, ...
    "VppDaytimePeakKW", NaN, "VppPaperSavingsPercent", NaN, ...
    "VppThroughputKWh", NaN, "LexBillEUR", NaN, "LexPeakKW", NaN, ...
    "LexNightPeakKW", NaN, "LexDaytimePeakKW", NaN, ...
    "LexPaperSavingsPercent", NaN, "LexThroughputKWh", NaN, ...
    "LexStatus", "", "BillDifferenceLexMinusVppEUR", NaN, ...
    "BillDifferenceWithinAllowance", false, "FreePeakReductionKW", NaN, ...
    "FreePeakReductionPercent", NaN, "VppPeakExcessOverP0KW", NaN, ...
    "LexPeakExcessOverP0KW", NaN, "LexPeakRatioToP0", NaN, ...
    "LexPeakAtOrBelowP0", false, "FreeShareOfExcessOverP0Percent", NaN, ...
    "PsBillEUR", NaN, "PsPeakKW", NaN, "PsPaperSavingsPercent", NaN, ...
    "TotalReduciblePeakKW", NaN, "FreeShareOfReduciblePeakPercent", NaN, ...
    "PsBillPenaltyEUR", NaN);
end

function selected = pickCase(metrics, day, caseId)
selected = metrics(metrics.Day == day & metrics.CaseId == caseId & ...
    ismember(metrics.Status, ["ok", "time_limited"]), :);
if height(selected) ~= 1
    selected = table;
end
end

%% ----------------------------------------------------------------------
function daily = frontierDaily(metrics, anchors)
frontier = metrics(metrics.CaseKind == "frontier", :);
frontier = sortrows(frontier, ["Day", "CapRatio"], ["ascend", "descend"]);
rows = repmat(emptyFrontierRow(), 0, 1);
days = unique(frontier.Day, "stable");
for dayIndex = 1:numel(days)
    day = days(dayIndex);
    anchor = anchors(anchors.Day == day, :);
    dayRows = frontier(frontier.Day == day, :);
    dayRecords = repmat(emptyFrontierRow(), height(dayRows), 1);
    for index = 1:height(dayRows)
        source = dayRows(index, :);
        record = emptyFrontierRow();
        record.Day = day;
        record.CapRatio = source.CapRatio;
        record.CapKW = source.CapKW;
        record.Status = source.Status;
        record.Feasible = ismember(source.Status, ["ok", "time_limited"]);
        record.MaximumRelativeMipGapPercent = ...
            source.MaximumRelativeMipGapPercent;
        record.WallTimeSeconds = source.WallTimeSeconds;
        if record.Feasible
            record.BillEUR = source.OptimizedBillEUR;
            record.PeakKW = source.AllDayPeakKW;
            record.NightPeakKW = source.NightPeakKW;
            record.DaytimePeakKW = source.DaytimePeakKW;
            record.PaperSavingsPercent = source.PaperSavingsPercent;
            record.EngineeringSavingsPercent = ...
                source.EngineeringSavingsPercent;
            record.BatteryThroughputKWh = source.BatteryThroughputKWh;
            record.CapViolationKW = source.CapViolationKW;
            record.EnergyBalanceResidualKW = source.EnergyBalanceResidualKW;
            record.TerminalSocErrorKWh = source.TerminalSocErrorKWh;
            if ~isempty(anchor)
                record.BillPenaltyVsVppEUR = record.BillEUR - anchor.VppBillEUR;
                record.BillPenaltyPercentOfVpp = 100 * ...
                    record.BillPenaltyVsVppEUR / anchor.VppBillEUR;
                record.PaperSavingsSacrificePP = ...
                    anchor.VppPaperSavingsPercent - record.PaperSavingsPercent;
                record.PeakReductionVsVppKW = anchor.VppPeakKW - record.PeakKW;
                record.PeakReductionVsVppPercent = 100 * ...
                    record.PeakReductionVsVppKW / anchor.VppPeakKW;
                record.PeakReductionVsLexKW = anchor.LexPeakKW - record.PeakKW;
                record.BillPenaltyVsLexEUR = record.BillEUR - anchor.LexBillEUR;
            end
        end
        dayRecords(index) = record;
    end
    dayRecords = marginalCosts(dayRecords);
    dayRecords = markKnee(dayRecords);
    rows = [rows; dayRecords]; %#ok<AGROW>
end
daily = struct2table(rows);
end

function row = emptyFrontierRow()
row = struct("Day", "", "CapRatio", NaN, "CapKW", NaN, "Status", "", ...
    "Feasible", false, "BillEUR", NaN, "PeakKW", NaN, "NightPeakKW", NaN, ...
    "DaytimePeakKW", NaN, "PaperSavingsPercent", NaN, ...
    "EngineeringSavingsPercent", NaN, "BatteryThroughputKWh", NaN, ...
    "CapViolationKW", NaN, "BillPenaltyVsVppEUR", NaN, ...
    "BillPenaltyPercentOfVpp", NaN, "PaperSavingsSacrificePP", NaN, ...
    "PeakReductionVsVppKW", NaN, "PeakReductionVsVppPercent", NaN, ...
    "PeakReductionVsLexKW", NaN, "BillPenaltyVsLexEUR", NaN, ...
    "MarginalCostEURPerKW", NaN, "MarginalCostReferenceRatio", NaN, ...
    "IsKnee", false, "KneeChordDistance", NaN, ...
    "MaximumRelativeMipGapPercent", NaN, "WallTimeSeconds", NaN, ...
    "EnergyBalanceResidualKW", NaN, "TerminalSocErrorKWh", NaN);
end

function records = marginalCosts(records)
% Marginal cost of tightening the cap from the next looser feasible ratio
% to this ratio: (bill_here - bill_looser) / (peak_looser - peak_here).
% Time-limited points are excluded as references and as targets.
feasibleIndex = find([records.Feasible] & [records.Status] == "ok");
for position = 2:numel(feasibleIndex)
    here = feasibleIndex(position);
    looser = feasibleIndex(position - 1);
    peakDrop = records(looser).PeakKW - records(here).PeakKW;
    billRise = records(here).BillEUR - records(looser).BillEUR;
    if peakDrop > 1e-9
        records(here).MarginalCostEURPerKW = billRise / peakDrop;
        records(here).MarginalCostReferenceRatio = records(looser).CapRatio;
    end
end
end

function records = markKnee(records)
% Pre-registered knee (ADR-002 item 6): normalise feasible (peak, bill)
% points to [0,1] on both axes and take the point with the largest
% perpendicular distance to the chord joining the two extreme points.
feasibleIndex = find([records.Feasible]);
if numel(feasibleIndex) < 3
    return
end
peak = [records(feasibleIndex).PeakKW];
bill = [records(feasibleIndex).BillEUR];
if max(peak) - min(peak) <= 1e-9 || max(bill) - min(bill) <= 1e-9
    return
end
x = (peak - min(peak)) / (max(peak) - min(peak));
y = (bill - min(bill)) / (max(bill) - min(bill));
[~, first] = max(x);
[~, last] = min(x);
lineVector = [x(last) - x(first), y(last) - y(first)];
lineNorm = norm(lineVector);
distance = abs(lineVector(1) .* (y(first) - y) - ...
    lineVector(2) .* (x(first) - x)) ./ lineNorm;
[~, kneePosition] = max(distance);
for position = 1:numel(feasibleIndex)
    records(feasibleIndex(position)).KneeChordDistance = distance(position);
end
records(feasibleIndex(kneePosition)).IsKnee = true;
end

function summaryTable = frontierSummary(daily, anchors)
ratios = unique(daily.CapRatio);
ratios = sort(ratios, "descend");
rows = repmat(emptyFrontierSummaryRow(), numel(ratios), 1);
for index = 1:numel(ratios)
    ratio = ratios(index);
    selected = daily(abs(daily.CapRatio - ratio) < 1e-12, :);
    feasible = selected(selected.Feasible, :);
    row = emptyFrontierSummaryRow();
    row.CapRatio = ratio;
    row.PlannedDays = height(selected);
    row.FeasibleDays = height(feasible);
    row.InfeasibleDays = nnz(selected.Status == "infeasible");
    row.TimeLimitedDays = nnz(selected.Status == "time_limited");
    row.FailedDays = nnz(selected.Status == "failed");
    row.AllDaysFeasible = row.FeasibleDays == row.PlannedDays && ...
        row.PlannedDays > 0;
    if height(feasible) > 0
        anchorRows = anchors(ismember(anchors.Day, feasible.Day), :);
        row.SummedVppBillEUR = sum(anchorRows.VppBillEUR);
        row.SummedBillEUR = sum(feasible.BillEUR);
        row.SummedBillPenaltyEUR = row.SummedBillEUR - row.SummedVppBillEUR;
        row.SummedBillPenaltyPercentOfVpp = 100 * ...
            row.SummedBillPenaltyEUR / row.SummedVppBillEUR;
        summedBaseline = sum(anchorRows.PaperLoadOnlyBaselineBillEUR);
        row.AggregatedVppPaperSavingsPercent = 100 * ...
            (summedBaseline - row.SummedVppBillEUR) / summedBaseline;
        row.AggregatedPaperSavingsPercent = 100 * ...
            (summedBaseline - row.SummedBillEUR) / summedBaseline;
        row.AggregatedPaperSavingsSacrificePP = ...
            row.AggregatedVppPaperSavingsPercent - ...
            row.AggregatedPaperSavingsPercent;
        row.MeanDailyPaperSavingsSacrificePP = ...
            mean(feasible.PaperSavingsSacrificePP);
        row.MedianDailyPaperSavingsSacrificePP = ...
            median(feasible.PaperSavingsSacrificePP);
        row.MeanCapKW = mean(feasible.CapKW);
        row.MeanPeakKW = mean(feasible.PeakKW);
        row.MeanVppPeakKW = mean(anchorRows.VppPeakKW);
        row.MeanPeakReductionVsVppKW = mean(feasible.PeakReductionVsVppKW);
        row.MeanPeakReductionVsVppPercent = ...
            mean(feasible.PeakReductionVsVppPercent);
        row.DaysWithZeroPenalty = nnz(abs(feasible.BillPenaltyVsVppEUR) <= ...
            1e-6);
        marginal = feasible.MarginalCostEURPerKW(isfinite( ...
            feasible.MarginalCostEURPerKW));
        if ~isempty(marginal)
            row.MeanMarginalCostEURPerKW = mean(marginal);
            row.MedianMarginalCostEURPerKW = median(marginal);
            row.MaxMarginalCostEURPerKW = max(marginal);
        end
        row.KneeDays = nnz(feasible.IsKnee);
    end
    rows(index) = row;
end
summaryTable = struct2table(rows);
end

function row = emptyFrontierSummaryRow()
row = struct("CapRatio", NaN, "PlannedDays", 0, "FeasibleDays", 0, ...
    "InfeasibleDays", 0, "TimeLimitedDays", 0, "FailedDays", 0, ...
    "AllDaysFeasible", false, "SummedVppBillEUR", NaN, ...
    "SummedBillEUR", NaN, "SummedBillPenaltyEUR", NaN, ...
    "SummedBillPenaltyPercentOfVpp", NaN, ...
    "AggregatedVppPaperSavingsPercent", NaN, ...
    "AggregatedPaperSavingsPercent", NaN, ...
    "AggregatedPaperSavingsSacrificePP", NaN, ...
    "MeanDailyPaperSavingsSacrificePP", NaN, ...
    "MedianDailyPaperSavingsSacrificePP", NaN, "MeanCapKW", NaN, ...
    "MeanPeakKW", NaN, "MeanVppPeakKW", NaN, ...
    "MeanPeakReductionVsVppKW", NaN, "MeanPeakReductionVsVppPercent", NaN, ...
    "DaysWithZeroPenalty", 0, "MeanMarginalCostEURPerKW", NaN, ...
    "MedianMarginalCostEURPerKW", NaN, "MaxMarginalCostEURPerKW", NaN, ...
    "KneeDays", 0);
end

%% ----------------------------------------------------------------------
function daily = tariffDaily(metrics, anchors, frontier)
tariff = metrics(metrics.CaseKind == "tariff", :);
tariff = sortrows(tariff, ["Day", "DemandChargeEURPerKW"]);
rows = repmat(emptyTariffRow(), height(tariff), 1);
for index = 1:height(tariff)
    source = tariff(index, :);
    row = emptyTariffRow();
    row.Day = source.Day;
    row.DemandChargeEURPerKW = source.DemandChargeEURPerKW;
    row.Status = source.Status;
    row.Feasible = ismember(source.Status, ["ok", "time_limited"]);
    anchor = anchors(anchors.Day == source.Day, :);
    if ~isempty(anchor)
        row.P0KW = anchor.P0KW;
    end
    if row.Feasible
        row.BillEUR = source.OptimizedBillEUR;
        row.PeakKW = source.AllDayPeakKW;
        row.NightPeakKW = source.NightPeakKW;
        row.ObjectiveWithDemandChargeEUR = source.ObjectiveWithDemandChargeEUR;
        row.PaperSavingsPercent = source.PaperSavingsPercent;
        row.MaximumRelativeMipGapPercent = ...
            source.MaximumRelativeMipGapPercent;
        if ~isempty(anchor)
            row.BillPenaltyVsVppEUR = row.BillEUR - anchor.VppBillEUR;
            row.PaperSavingsSacrificePP = anchor.VppPaperSavingsPercent - ...
                row.PaperSavingsPercent;
            row.PeakReductionVsVppKW = anchor.VppPeakKW - row.PeakKW;
            row.PeakRatioToP0 = row.PeakKW / anchor.P0KW;
            row.PeakAtOrBelowP0 = row.PeakKW <= anchor.P0KW + 1e-6;
            row.PeakAtOrBelowLex = row.PeakKW <= anchor.LexPeakKW + 1e-6;
            row.VppTotalCostUnderTariffEUR = anchor.VppBillEUR + ...
                row.DemandChargeEURPerKW * anchor.VppPeakKW;
            row.TotalCostSavingVsVppUnderTariffEUR = ...
                row.VppTotalCostUnderTariffEUR - ...
                row.ObjectiveWithDemandChargeEUR;
        end
        row = frontierLowerBoundGap(row, frontier);
    end
    rows(index) = row;
end
daily = struct2table(rows);
end

function row = frontierLowerBoundGap(row, frontier)
% Any dispatch with peak p costs at least the epsilon-frontier bill at the
% smallest cap that is >= p. A negative gap beyond tolerance would mean the
% two experiments disagree; a gap near zero means the weighted-sum point is
% a supported frontier point.
dayFrontier = frontier(frontier.Day == row.Day & frontier.Feasible & ...
    frontier.CapKW >= row.PeakKW - 1e-6, :);
if isempty(dayFrontier)
    return
end
[~, tightest] = min(dayFrontier.CapKW);
row.FrontierLowerBoundCapRatio = dayFrontier.CapRatio(tightest);
row.FrontierLowerBoundBillEUR = dayFrontier.BillEUR(tightest);
row.GapAboveFrontierLowerBoundEUR = row.BillEUR - ...
    row.FrontierLowerBoundBillEUR;
row.ConsistentWithFrontier = row.GapAboveFrontierLowerBoundEUR >= ...
    -1e-6 * max(1, abs(row.FrontierLowerBoundBillEUR));
end

function row = emptyTariffRow()
row = struct("Day", "", "DemandChargeEURPerKW", NaN, "Status", "", ...
    "Feasible", false, "P0KW", NaN, "BillEUR", NaN, "PeakKW", NaN, ...
    "NightPeakKW", NaN, "ObjectiveWithDemandChargeEUR", NaN, ...
    "PaperSavingsPercent", NaN, "BillPenaltyVsVppEUR", NaN, ...
    "PaperSavingsSacrificePP", NaN, "PeakReductionVsVppKW", NaN, ...
    "PeakRatioToP0", NaN, "PeakAtOrBelowP0", false, ...
    "PeakAtOrBelowLex", false, "VppTotalCostUnderTariffEUR", NaN, ...
    "TotalCostSavingVsVppUnderTariffEUR", NaN, ...
    "FrontierLowerBoundCapRatio", NaN, "FrontierLowerBoundBillEUR", NaN, ...
    "GapAboveFrontierLowerBoundEUR", NaN, "ConsistentWithFrontier", false, ...
    "MaximumRelativeMipGapPercent", NaN);
end

function summaryTable = tariffSummary(daily)
charges = unique(daily.DemandChargeEURPerKW);
rows = repmat(emptyTariffSummaryRow(), numel(charges), 1);
for index = 1:numel(charges)
    charge = charges(index);
    selected = daily(abs(daily.DemandChargeEURPerKW - charge) < 1e-12, :);
    feasible = selected(selected.Feasible, :);
    row = emptyTariffSummaryRow();
    row.DemandChargeEURPerKW = charge;
    row.PlannedDays = height(selected);
    row.FeasibleDays = height(feasible);
    if height(feasible) > 0
        row.DaysPeakAtOrBelowP0 = nnz(feasible.PeakAtOrBelowP0);
        row.DaysPeakAtOrBelowLex = nnz(feasible.PeakAtOrBelowLex);
        row.MeanPeakKW = mean(feasible.PeakKW);
        row.MeanPeakRatioToP0 = mean(feasible.PeakRatioToP0);
        row.MaxPeakRatioToP0 = max(feasible.PeakRatioToP0);
        row.MeanPeakReductionVsVppKW = mean(feasible.PeakReductionVsVppKW);
        row.SummedBillPenaltyVsVppEUR = sum(feasible.BillPenaltyVsVppEUR);
        row.MeanBillPenaltyVsVppEUR = mean(feasible.BillPenaltyVsVppEUR);
        row.MeanPaperSavingsSacrificePP = mean(feasible.PaperSavingsSacrificePP);
        row.MeanTotalCostSavingVsVppUnderTariffEUR = ...
            mean(feasible.TotalCostSavingVsVppUnderTariffEUR);
        row.DaysConsistentWithFrontier = nnz(feasible.ConsistentWithFrontier);
        row.MaxGapAboveFrontierLowerBoundEUR = ...
            max(feasible.GapAboveFrontierLowerBoundEUR, [], "omitnan");
    end
    rows(index) = row;
end
summaryTable = struct2table(rows);
end

function row = emptyTariffSummaryRow()
row = struct("DemandChargeEURPerKW", NaN, "PlannedDays", 0, ...
    "FeasibleDays", 0, "DaysPeakAtOrBelowP0", 0, "DaysPeakAtOrBelowLex", 0, ...
    "MeanPeakKW", NaN, "MeanPeakRatioToP0", NaN, "MaxPeakRatioToP0", NaN, ...
    "MeanPeakReductionVsVppKW", NaN, "SummedBillPenaltyVsVppEUR", NaN, ...
    "MeanBillPenaltyVsVppEUR", NaN, "MeanPaperSavingsSacrificePP", NaN, ...
    "MeanTotalCostSavingVsVppUnderTariffEUR", NaN, ...
    "DaysConsistentWithFrontier", 0, ...
    "MaxGapAboveFrontierLowerBoundEUR", NaN);
end

function minimum = minimumDemandCharge(daily)
days = unique(daily.Day, "stable");
rows = repmat(struct("Day", "", "MinimumChargeForP0EURPerKW", NaN, ...
    "PeakAtMinimumChargeKW", NaN, "BillPenaltyAtMinimumChargeEUR", NaN, ...
    "P0KW", NaN, "LargestChargeTested", NaN, "P0ReachedWithinGrid", false), ...
    numel(days), 1);
for index = 1:numel(days)
    selected = daily(daily.Day == days(index) & daily.Feasible, :);
    selected = sortrows(selected, "DemandChargeEURPerKW");
    rows(index).Day = days(index);
    if isempty(selected)
        continue
    end
    rows(index).P0KW = selected.P0KW(1);
    rows(index).LargestChargeTested = max(selected.DemandChargeEURPerKW);
    hit = find(selected.PeakAtOrBelowP0, 1, "first");
    if ~isempty(hit)
        rows(index).MinimumChargeForP0EURPerKW = ...
            selected.DemandChargeEURPerKW(hit);
        rows(index).PeakAtMinimumChargeKW = selected.PeakKW(hit);
        rows(index).BillPenaltyAtMinimumChargeEUR = ...
            selected.BillPenaltyVsVppEUR(hit);
        rows(index).P0ReachedWithinGrid = true;
    end
end
minimum = struct2table(rows);
end

%% ----------------------------------------------------------------------
function comparison = efficiencyComparison(metrics)
efficiency = metrics(metrics.CaseKind == "efficiency", :);
rows = repmat(emptyEfficiencyRow(), 0, 1);
for index = 1:height(efficiency)
    source = efficiency(index, :);
    nominal = nominalCounterpart(metrics, source);
    row = emptyEfficiencyRow();
    row.Day = source.Day;
    row.Strategy = source.Strategy;
    row.EtaBattery = source.EtaBatteryCharge;
    row.RoundTripEfficiency = source.EtaBatteryCharge * ...
        source.EtaBatteryDischarge;
    row.Status = source.Status;
    if ismember(source.Status, ["ok", "time_limited"])
        row.BillEUR = source.OptimizedBillEUR;
        row.PaperSavingsPercent = source.PaperSavingsPercent;
        row.EngineeringSavingsPercent = source.EngineeringSavingsPercent;
        row.PeakKW = source.AllDayPeakKW;
        row.BatteryThroughputKWh = source.BatteryThroughputKWh;
    end
    if ~isempty(nominal)
        row.NominalCaseId = nominal.CaseId;
        row.NominalBillEUR = nominal.OptimizedBillEUR;
        row.NominalPaperSavingsPercent = nominal.PaperSavingsPercent;
        row.NominalEngineeringSavingsPercent = ...
            nominal.EngineeringSavingsPercent;
        row.NominalPeakKW = nominal.AllDayPeakKW;
        row.NominalBatteryThroughputKWh = nominal.BatteryThroughputKWh;
        row.BillIncreaseEUR = row.BillEUR - row.NominalBillEUR;
        row.PaperSavingsDropPP = row.NominalPaperSavingsPercent - ...
            row.PaperSavingsPercent;
        row.EngineeringSavingsDropPP = ...
            row.NominalEngineeringSavingsPercent - ...
            row.EngineeringSavingsPercent;
        row.PeakChangeKW = row.PeakKW - row.NominalPeakKW;
        row.ThroughputChangeKWh = row.BatteryThroughputKWh - ...
            row.NominalBatteryThroughputKWh;
    end
    rows(end + 1, 1) = row; %#ok<AGROW>
end
comparison = struct2table(rows);
end

function nominal = nominalCounterpart(metrics, source)
if source.Strategy == "IMPROVED_PEAK_GUARD"
    caseId = "FRONTIER_R1.000";
else
    caseId = "ANCHOR_" + source.Strategy;
end
nominal = pickCase(metrics, source.Day, caseId);
end

function row = emptyEfficiencyRow()
row = struct("Day", "", "Strategy", "", "EtaBattery", NaN, ...
    "RoundTripEfficiency", NaN, "Status", "", "BillEUR", NaN, ...
    "PaperSavingsPercent", NaN, "EngineeringSavingsPercent", NaN, ...
    "PeakKW", NaN, "BatteryThroughputKWh", NaN, "NominalCaseId", "", ...
    "NominalBillEUR", NaN, "NominalPaperSavingsPercent", NaN, ...
    "NominalEngineeringSavingsPercent", NaN, "NominalPeakKW", NaN, ...
    "NominalBatteryThroughputKWh", NaN, "BillIncreaseEUR", NaN, ...
    "PaperSavingsDropPP", NaN, "EngineeringSavingsDropPP", NaN, ...
    "PeakChangeKW", NaN, "ThroughputChangeKWh", NaN);
end

%% ----------------------------------------------------------------------
function writeIfAny(value, directory, fileName)
if isempty(value) || height(value) == 0
    return
end
path = fullfile(directory, fileName);
temporaryPath = regexprep(path, "\.csv$", ".tmp.csv");
writetable(value, temporaryPath);
movefile(temporaryPath, path, "f");
end
