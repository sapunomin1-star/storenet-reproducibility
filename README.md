# StoreNet 論文包：從這裡開始

本包整理 StoreNet 資料論文、方法論文及後續策略模擬，提供原文、中文研究報告、計算程式和已完成的結果。**第一次來，可以先看報告；想重跑時，照操作步驟即可，不用修改程式檔。**

**[下載程式與報告 ZIP](https://github.com/sapunomin1-star/storenet-reproducibility/archive/refs/heads/main.zip)** · **[大型資料下載](02_中文程式導覽/02_資料下載與來源.md)** · **[Mac／Windows 操作](02_中文程式導覽/01_Mac與Windows操作.md)**

閱讀順序：**選要看的內容 → 開啟圖片或報告 → 需要重算再下載資料並執行。**

## 1. 看報告、找原文與資料

| 想找什麼 | 點這裡 |
|---|---|
| 完整研究內容、公式與結論 | [研究報告 PDF](00_報告_StoreNet_研究報告.pdf) |
| 兩篇論文原文、資料下載來源 | [論文與來源資料夾](01_論文/) |
| 愛爾蘭 20 戶原始資料 | [StoreNet 資料下載](02_中文程式導覽/02_資料下載與來源.md)：W 是功率，Wh 是每分鐘能量；weather 是氣象資料 |
| 澳洲用電與太陽能原始資料 | [Ausgrid 下載與放置方式](02_中文程式導覽/02_資料下載與來源.md) |
| 電壓不平衡模擬使用的電網 | [電網資料](StoreNet/data/external/ieee_european_lv/) |

## 2. 找圖片、數值和對應程式

PNG 是圖片；CSV 是數值表，可用 Excel 開啟。「程式」連結可查原始碼；「執行步驟」提供可複製的指令。

| 想找的圖／分析 | 程式與執行步驟 | 圖片與數值在哪裡 |
|---|---|---|
| 資料論文圖 5：資料可用率 | [Python 程式](StoreNet/src/data_paper_figures/figure05_availability.py) · [執行步驟](02_中文程式導覽/01_Mac與Windows操作.md#data-figures) | [開啟結果](StoreNet/results/data_paper_by_figure/圖05_資料可用率/) |
| 資料論文圖 6：功率與能量一致性 | [Python 程式](StoreNet/src/data_paper_figures/figure06_consistency.py) · [執行步驟](02_中文程式導覽/01_Mac與Windows操作.md#data-figures) | [開啟結果](StoreNet/results/data_paper_by_figure/圖06_功率與能量一致性/) |
| 資料論文圖 7：用電量與氣溫 | [Python 程式](StoreNet/src/data_paper_figures/figure07_consumption_temperature.py) · [執行步驟](02_中文程式導覽/01_Mac與Windows操作.md#data-figures) | [開啟結果](StoreNet/results/data_paper_by_figure/圖07_用電量與氣溫/) |
| 資料論文圖 8：太陽能住戶能源流向 | [Python 程式](StoreNet/src/data_paper_figures/figure08_pv_flows.py) · [執行步驟](02_中文程式導覽/01_Mac與Windows操作.md#data-figures) | [開啟結果](StoreNet/results/data_paper_by_figure/圖08_太陽能住戶能源流向/) |
| 資料論文圖 9：一週電池與電力運作 | [Python 程式](StoreNet/src/data_paper_figures/figure09_battery_week.py) · [執行步驟](02_中文程式導覽/01_Mac與Windows操作.md#data-figures) | [開啟結果](StoreNet/results/data_paper_by_figure/圖09_一週電池與電力運作/) |
| 類似資料論文圖 10：電壓不平衡模擬 | [Python 程式](StoreNet/src/simulate_figure10s_grid.py) · [執行步驟](02_中文程式導覽/01_Mac與Windows操作.md#data-figures) | [開啟結果](StoreNet/results/figure10_grid/) |
| 方法論文圖 5：代表日策略（報告圖 15） | [MATLAB 程式](StoreNet/launchers/start_bahloul_typical.m) · [執行步驟](02_中文程式導覽/01_Mac與Windows操作.md#method-figures) | [開啟結果](StoreNet/results/方法論文代表日/) |
| 方法論文圖 6：月度比較（報告圖 17） | [MATLAB 程式](StoreNet/src/run_bahloul_monthly_v1.m) · [執行步驟](02_中文程式導覽/01_Mac與Windows操作.md#method-figures) | [已算好的結果](StoreNet/results/b2022_ir_v1_formal/b2022_monthly_v1_2020/) |
| 方法論文圖 7、表 I：容量與功率（報告圖 19） | [MATLAB 程式](StoreNet/src/run_bahloul_sensitivity_v1.m) · [執行步驟](02_中文程式導覽/01_Mac與Windows操作.md#method-figures) | [已算好的結果](StoreNet/results/b2022_ir_v1_formal/b2022_sensitivity_v1_20200824/) |
| 降低尖峰的改進策略（報告圖 21、22） | [計算說明](02_中文程式導覽/01_Mac與Windows操作.md#improvement) | [代表日數值](StoreNet/results/bahloul_vpp_improvement_v1/storenet_typical/)／[月度數值](StoreNet/results/bahloul_vpp_improvement_v1/storenet_monthly/)；圖片見研究報告 |
| 澳洲資料驗證（報告圖 23） | [MATLAB 繪圖程式](StoreNet/src/render_external_validation.m) · [執行步驟](02_中文程式導覽/01_Mac與Windows操作.md#improvement) | [開啟結果](StoreNet/results/external_sensitivity_ausgrid_exclude_customer161_v1/) |
| 電費、尖峰、電價與效率比較（報告圖 24～29） | [Python 繪圖程式](StoreNet/src/render_frontier_figures.py) · [執行步驟](02_中文程式導覽/01_Mac與Windows操作.md#improvement) | [六張圖片](StoreNet/results/bahloul_vpp_improvement_v2_frontier/figures/)／[數值](StoreNet/results/bahloul_vpp_improvement_v2_frontier/) |

資料論文圖 6 使用公開 H4 資料檢查；圖 10 是另建電網的模擬。論文圖號與本報告圖號不同，可用 [報告圖表對照](02_中文程式導覽/00_執行指令與檔案說明.md#report-index) 查找其餘圖、表。

## 3. 需要操作或查檔案時

| 需要什麼 | 點這裡 |
|---|---|
| 用中文用途找程式 | [程式用途索引](02_中文程式導覽/00_執行指令與檔案說明.md#programs) |
| 複製執行指令、查重跑後的輸出位置 | [Mac／Windows 執行說明](02_中文程式導覽/01_Mac與Windows操作.md) |
| 知道某支程式、某個檔案做什麼 | [程式用途](02_中文程式導覽/00_執行指令與檔案說明.md#programs)／[資料檔內容](02_中文程式導覽/00_執行指令與檔案說明.md#data-files)／[結果檔內容](02_中文程式導覽/00_執行指令與檔案說明.md#result-files) |
| 把這份論文包搬到另一台電腦執行 | [環境設定](02_中文程式導覽/01_Mac與Windows操作.md#prepare) |

資料論文圖 5～10、方法論文代表日重跑後會更新同一個結果資料夾。方法論文月度、容量功率的重跑位置另外寫在執行步驟中。

[來源與授權](THIRD_PARTY_NOTICES.md) · [系統測試](https://github.com/sapunomin1-star/storenet-reproducibility/actions)
