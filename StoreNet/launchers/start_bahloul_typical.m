%% 方法論文代表日策略復現：按上方「執行」即可
% 復現報告使用的 2020-08-24、30 分鐘資料與 release_literal 品質模式。
% 執行時會列出目前策略；完成後顯示結果表與報告版圖15，並保留結果位置。
% 結果固定在 results/方法論文代表日；成功重跑後更新同一份。

storenetDay = datetime(2020, 8, 24);
storenetProject = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(storenetProject, 'src'));
addpath(fullfile(storenetProject, 'launchers'));
storenetStarted = tic;

fprintf('\n方法論文代表日策略復現\n');
fprintf('日期：%s；每 30 分鐘一格；使用報告的公開資料模式。\n', ...
    string(storenetDay, 'yyyy-MM-dd'));
fprintf('開始讀取 20 戶資料，接著計算 8 個最佳化案例與 2 個實測案例。\n');
fprintf('通常需要數分鐘；下方會列出目前正在計算的策略。\n\n');
drawnow;

[storenetRun, storenetSummary] = runLatestTypical(storenetProject, storenetDay);

fprintf('\n計算流程結束，共 %.1f 秒。\n', toc(storenetStarted));
fprintf('工作區的 storenetRun 保留完整結果；storenetSummary 是中文摘要表。\n');

function [run, summary] = runLatestTypical(projectRoot, day)
% 每次只保留一份最新結果；若執行失敗，還原上次成功的結果。
arguments
    projectRoot (1, 1) string
    day (1, 1) datetime
end
resultDirectory = fullfile(projectRoot, 'results', '方法論文代表日');
backupDirectory = string(tempname);
hadPreviousResult = isfolder(resultDirectory);
if hadPreviousResult
    movefile(resultDirectory, backupDirectory);
end
try
    run = run_bahloul_typical_v1(day, QualityMode="release_literal", ...
        OutputRoot=fullfile(projectRoot, 'results'), RunId="方法論文代表日", ...
        PersistSolutions=false, Solver=@solveWithChineseProgress);
    metrics = readtable(fullfile(resultDirectory, 'typical_metrics.csv'), TextType="string");
    assert(all(metrics.Status == "ok"), '部分案例未成功，請查看命令視窗。');
    summary = show_bahloul_typical_result(run.runDirectory);
catch exception
    if isfolder(resultDirectory)
        rmdir(resultDirectory, 's');
    end
    if hadPreviousResult
        movefile(backupDirectory, resultDirectory);
    end
    rethrow(exception);
end
if hadPreviousResult
    rmdir(backupDirectory, 's');
end
end

function [solution, metrics] = solveWithChineseProgress(data, config, strategy)
% 保持原始求解器與模型設定，只加上可見的進度訊息。
fprintf('[%s] 正在求解：%s（%d 戶）……\n', ...
    string(datetime('now'), 'HH:mm:ss'), strategy, config.nHomes);
drawnow;
caseStarted = tic;
try
    [solution, metrics] = solve_storenet(data, config, strategy);
    fprintf('  求解器已返回：%.1f 秒，電費 %.4f 歐元，尖峰 %.4f kW。\n', ...
        toc(caseStarted), metrics.optimizedBillEUR, metrics.peakImportKW);
catch exception
    fprintf(2, '  此案例求解失敗：%s\n', exception.message);
    rethrow(exception);
end
drawnow;
end
