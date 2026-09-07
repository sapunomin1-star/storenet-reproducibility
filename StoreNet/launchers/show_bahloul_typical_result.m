function summary = show_bahloul_typical_result(resultDirectory)
%SHOW_BAHLOUL_TYPICAL_RESULT 顯示代表日既有結果，不重新求解。
arguments
    resultDirectory (1, 1) string
end

metrics = readtable(fullfile(resultDirectory, 'typical_metrics.csv'), ...
    TextType="string", VariableNamingRule="preserve");
bill = metrics.OptimizedBillEUR;
peak = metrics.OptimizedPeakImportKW;
observed = metrics.Strategy == "SB_SC";
bill(observed) = metrics.ObservedBillEUR(observed);
peak(observed) = metrics.ObservedPeakImportKW(observed);
summary = table(metrics.ScenarioId, metrics.Strategy, metrics.HouseCount, ...
    bill, peak, metrics.PaperLoadOnlySavingsPercent, metrics.Status, ...
    VariableNames=["情境", "策略", "住戶數", "電費_歐元", "尖峰_kW", ...
    "相對純用電基準省錢率_百分比", "狀態"]);
fprintf('\n代表日結果摘要（SB_SC 為實測資料，其餘為模型結果）\n');
disp(summary);
failed = metrics.Status ~= "ok";
if any(failed)
    fprintf(2, '注意：%d 個案例未成功，請檢查完整結果表中的錯誤欄位。\n', ...
        nnz(failed));
else
    fprintf('全部 %d 個案例的狀態皆為 ok。\n', height(metrics));
end
fprintf('結果資料夾：%s\n', resultDirectory);
fprintf('完整數字：%s\n', fullfile(resultDirectory, 'typical_metrics.csv'));

% 用本次 CSV 重畫報告版圖15，並保留可縮放的 MATLAB 圖窗。
[~, figurePath] = render_bahloul_typical_report(resultDirectory);
fprintf('報告版圖15：%s\n', figurePath);
end
