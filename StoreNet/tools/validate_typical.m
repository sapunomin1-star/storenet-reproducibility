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
columns = ["OptimizedBillEUR", "OptimizedPeakImportKW", "PaperLoadOnlySavingsPercent"];
for column = columns
    difference = abs(actual.(column) - expected.(column));
    allowance = 1e-5 + 1e-6*abs(expected.(column));
    assert(all(difference <= allowance | (isnan(actual.(column)) & isnan(expected.(column)))), ...
        "Representative-day metric differs from the published reference: %s", column);
end
assert(isfile('StoreNet/results/方法論文代表日/圖15_方法論文代表日結果.png'));
fprintf('Representative-day entry: all ten scenarios match the reference.\n');
close all;
