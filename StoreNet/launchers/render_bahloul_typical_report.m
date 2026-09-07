function [resultFigure, figurePath] = render_bahloul_typical_report(resultDirectory)
%RENDER_BAHLOUL_TYPICAL_REPORT 依報告圖15的配色與座標重畫代表日結果。
% 直接讀取本次計算的 CSV；電池曲線僅在顯示時轉為「充電為正」。
% 不更動原始 CSV、求解模型、電費或省錢率。
arguments
    resultDirectory (1, 1) string
end

profiles = readtable(fullfile(resultDirectory, 'figure5_profiles.csv'), ...
    TextType="string", VariableNamingRule="preserve");
metrics = readtable(fullfile(resultDirectory, 'typical_metrics.csv'), ...
    TextType="string", VariableNamingRule="preserve");
if ~isdatetime(profiles.TimeEnd)
    profiles.TimeEnd = datetime(profiles.TimeEnd, ...
        InputFormat='dd-MMM-yyyy HH:mm:ss', Locale='en_US');
end
strategies = ["SH_BM", "VPP_BM", "PS", "PSDT", "LL", "SB_SC"];
plotDay = dateshift(min(profiles.TimeEnd), 'start', 'day');

resultFigure = figure(Name='方法論文代表日策略復現｜報告版圖15', ...
    NumberTitle='off', Color='w', Visible='on', ...
    Position=[100, 80, 1100, 960]);
% 指定本圖樣式，避免 MATLAB 深色主題改變匯出的背景與文字顏色。
if isprop(resultFigure, 'Theme')
    resultFigure.Theme = 'light';
end
layout = tiledlayout(resultFigure, 3, 2, ...
    TileSpacing='compact', Padding='compact');
layout.OuterPosition = [0.04, 0.065, 0.94, 0.84];
annotation(resultFigure, 'textbox', [0.055, 0.928, 0.93, 0.055], ...
    String='方法論文 Figure 5 我們的代表日結果', ...
    EdgeColor='none', Color='k', FontName='PingFang TC', ...
    FontSize=22, FontWeight='bold', Interpreter='none');

for index = 1:numel(strategies)
    strategy = strategies(index);
    subset = profiles(profiles.Strategy == strategy & ...
        profiles.CohortId == "H20_PV10", :);
    subset = sortrows(subset, 'TimeEnd');
    metricRow = metrics(metrics.Strategy == strategy & ...
        metrics.CohortId == "H20_PV10" & ...
        (metrics.ScenarioId == "DC_XI007_H20" | ...
        metrics.ScenarioId == "OBSERVED_RELEASE_H20_PV10"), :);
    if height(subset) ~= 48 || height(metricRow) ~= 1
        error('StoreNet:InvalidReportFigureInput', ...
            '%s 必須有 48 個半小時區間及一列主情境指標。', strategy);
    end
    timeHours = hours(subset.TimeEnd - plotDay);
    axesHandle = nexttile(layout);
    set(axesHandle, Color='w', XColor='k', YColor='k', ...
        FontName='Arial', FontSize=13, GridColor=[0.8, 0.8, 0.8], ...
        GridAlpha=0.35, Box='off');
    hold(axesHandle, 'on');
    plot(axesHandle, timeHours, subset.LoadKW, ...
        Color=[0.1216, 0.4667, 0.7059], LineWidth=1.4, DisplayName='Load');
    plot(axesHandle, timeHours, subset.GridKW, ...
        Color=[0.8392, 0.1529, 0.1569], LineWidth=1.4, DisplayName='Grid');
    plot(axesHandle, timeHours, -subset.BatteryKW, ...
        Color=[0.1725, 0.6275, 0.1725], LineWidth=1.4, ...
        DisplayName='Battery (+charge)');
    plot(axesHandle, timeHours, subset.PvKW, ...
        Color=[0.9, 0.7, 0], LineWidth=1.4, DisplayName='PV');
    hold(axesHandle, 'off');
    xlim(axesHandle, [0, 24]);
    xticks(axesHandle, 0:4:24);
    ylim(axesHandle, [-25, 82]);
    yticks(axesHandle, -20:20:80);
    grid(axesHandle, 'on');
    if mod(index, 2) == 1
        ylabel(axesHandle, 'Power (kW)', Color='k');
    else
        yticklabels(axesHandle, {});
    end
    if index >= 5
        xlabel(axesHandle, 'Hour of day', Color='k');
    else
        xticklabels(axesHandle, {});
    end
    if metricRow.Status == "ok"
        titleText = sprintf('%s   %.2f%%', replace(strategy, '_', '-'), ...
            metricRow.PaperLoadOnlySavingsPercent);
    else
        titleText = sprintf('%s   FAILED', replace(strategy, '_', '-'));
    end
    title(axesHandle, titleText, Color='k', FontWeight='normal', ...
        FontSize=15, Interpreter='none');
    if index == 1
        legendHandle = legend(axesHandle, Location='northwest', ...
            NumColumns=2, FontSize=11, TextColor='k', Color='w', ...
            EdgeColor=[0.75, 0.75, 0.75], Interpreter='none');
        legendHandle.AutoUpdate = 'off';
    end
end
annotation(resultFigure, 'textbox', [0.055, 0.005, 0.93, 0.043], ...
    String=string(plotDay, 'yyyy年M月d日') + ...
        '｜綠線以充電為正；SB-SC 為實測結果。來源：本次結果 CSV。', ...
    EdgeColor='none', Color=[0.25, 0.25, 0.25], ...
    FontName='PingFang TC', FontSize=11, Interpreter='none');
figurePath = fullfile(resultDirectory, '圖15_方法論文代表日結果.png');
exportgraphics(resultFigure, figurePath, Resolution=220, BackgroundColor='white');
drawnow;
end
