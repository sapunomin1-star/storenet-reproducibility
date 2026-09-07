%% CI: run the actual representative-day entry point and compare its metrics.
validationRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
cd(validationRoot);
addpath('StoreNet/src', 'StoreNet/launchers');
run('StoreNet/launchers/start_bahloul_typical.m');
actual = readtable('StoreNet/results/方法論文代表日/typical_metrics.csv', TextType="string");
expected = readtable('StoreNet/results/b2022_ir_v1_formal/b2022_typical_v1_20200824/typical_metrics.csv', TextType="string");
actual = sortrows(actual, ["ScenarioId", "Strategy"]);
expected = sortrows(expected, ["ScenarioId", "Strategy"]);
assert(height(actual) == 10 && all(actual.Status == "ok"));
assert(isequal(actual.ScenarioId, expected.ScenarioId));
assert(isequal(actual.Strategy, expected.Strategy));
% Equal-cost dispatches need not have equal unconstrained peaks. Compare the
% actual objectives, observed data, and feasibility, rather than an arbitrary
% member of the optimal set selected by a particular solver version.
columns = ["OptimizedBillEUR", "PaperLoadOnlySavingsPercent", ...
    "TotalBatteryThroughputKWh", "ObservedBillEUR", "ObservedPeakImportKW"];
for column = columns
    difference = abs(actual.(column) - expected.(column));
    allowance = 1e-5 + 1e-6*abs(expected.(column));
    assert(all(difference <= allowance | (isnan(actual.(column)) & isnan(expected.(column)))), ...
        "Representative-day metric differs from the published reference: %s", column);
end
strategies = ["PS", "PSDT", "LL"];
objectives = ["OptimizedPeakImportKW", "OptimizedDaytimePeakImportKW", ...
    "OptimizedImportSpreadKW"];
for index = 1:numel(strategies)
    selected = actual.Strategy == strategies(index);
    column = objectives(index);
    difference = abs(actual.(column)(selected) - expected.(column)(selected));
    allowance = 1e-5 + 1e-6*abs(expected.(column)(selected));
    assert(all(isfinite(difference) & difference <= allowance), ...
        "Representative-day strategy objective differs: %s", strategies(index));
end
modelRows = actual.Strategy ~= "SB_SC";
residuals = ["EnergyBalanceResidualKW", "PvAllocationResidualKW", ...
    "HomeBalanceResidualKW", "BatteryDynamicsResidualKW", ...
    "AggregateImportResidualKW", "ChargeConversionResidualKW", ...
    "DischargeConversionResidualKW", "InitialSocErrorKWh", "TerminalSocErrorKWh", ...
    "SocBoundViolationKWh", "ChargePowerViolationKW", "DischargePowerViolationKW", ...
    "AggregateImportNonnegativeViolationKW", "SimultaneousChargeDischargeKW", ...
    "MaximumLexicographicViolation"];
values = actual{modelRows, residuals};
assert(all(isfinite(values) & abs(values) <= 1e-6, "all"), ...
    'Representative-day power balance, battery limits, or objective locks failed.');
assert(all(actual.MinimumExitFlag(modelRows) > 0));
assert(isequal(actual.StageCount(modelRows), expected.StageCount(modelRows)));
disp(actual(:, ["ScenarioId", "Strategy", "OptimizedBillEUR", "OptimizedPeakImportKW"]));
assert(isfile('StoreNet/results/方法論文代表日/圖15_方法論文代表日結果.png'));
fprintf('Representative day: ten scenarios passed objective and feasibility checks.\n');
close all;
