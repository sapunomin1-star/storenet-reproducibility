# Mac 與 Windows 操作

[回首頁](../README.md) · [下載來源與手動放置方式](02_資料下載與來源.md) · [檔案用途索引](00_執行指令與檔案說明.md)

**使用者不需要修改程式檔。** 只需安裝環境、下載資料，再複製要執行的指令。已附上的 PDF、PNG、CSV 可以直接閱讀。

<a id="prepare"></a>

## 1. 第一次使用：下載並解壓縮

下載 [程式與報告 ZIP](https://github.com/sapunomin1-star/storenet-reproducibility/archive/refs/heads/main.zip)，解壓縮整個資料夾。以下稱最外層、有 README.md 的資料夾為「專案資料夾」。保留裡面的資料夾結構。

只看報告不需要安裝任何程式。重新計算時需要：

- **Python 3.12，64 位元**：資料下載、資料論文各圖和電網模擬。[Python 下載](https://www.python.org/downloads/)
- **MATLAB R2026a 或更新版本及 Optimization Toolbox**：方法論文和澳洲電池策略最佳化。
- 首次下載需連線；全部原始資料解壓後約 1.2 GB，建議預留至少 4 GB 空間給環境、暫存與結果。

<a id="mac"></a>

## 2A. Mac：安裝 Python 環境與下載資料

1. 開啟「終端機」。輸入 `cd `（後面留一個空白），把專案資料夾拖進視窗，再按 Enter。終端機就會切到正確位置。
2. 依序複製下面三行。只需要建立一次環境。

```bash
python3.12 -m venv StoreNet/.venv-grid
StoreNet/.venv-grid/bin/python -m pip install -r StoreNet/requirements-grid.txt
StoreNet/.venv-grid/bin/python StoreNet/tools/download_data.py
```

如果找不到 `python3.12`，先確認安裝的是 Python 3.12。原 Mac 已有環境時，可以直接執行第三行下載資料。

<a id="windows"></a>

## 2B. Windows：安裝 Python 環境與下載資料

1. 安裝 Python 3.12（含 Python Launcher）。
   建議把解壓後的專案資料夾放在較短的路徑，例如 `C:\StoreNet`，避免完整研究結果的多層檔名超過 Windows 路徑限制。
2. 開啟已解壓的專案資料夾，在檔案總管的位址列輸入 `powershell` 並按 Enter。
3. 依序複製下面三行。不需要管理員權限，也不需要執行 Activate.ps1。

```powershell
py -3.12 -m venv StoreNet\.venv-grid
.\StoreNet\.venv-grid\Scripts\python.exe -m pip install -r StoreNet\requirements-grid.txt
.\StoreNet\.venv-grid\Scripts\python.exe StoreNet\tools\download_data.py
```

如果找不到 `py`，重新開啟 PowerShell；仍找不到時，確認已安裝 Python Launcher。不要把 Mac 的 `.venv-grid` 複製到 Windows，請在 Windows 建立新環境。

下載程式會自動放好 StoreNet、Ausgrid 和電網資料。再次執行會略過已有的正確檔案。若網路中斷，重新執行同一行即可。

<a id="data-figures"></a>

## 3. 資料論文圖 5～10：挑一行執行

每行各產生一張圖。在專案資料夾的終端機／PowerShell 執行。

**Mac**

```bash
# 圖 5：資料可用率
StoreNet/.venv-grid/bin/python StoreNet/src/data_paper_figures/figure05_availability.py
# 圖 6：功率與能量一致性
StoreNet/.venv-grid/bin/python StoreNet/src/data_paper_figures/figure06_consistency.py
# 圖 7：用電量與氣溫
StoreNet/.venv-grid/bin/python StoreNet/src/data_paper_figures/figure07_consumption_temperature.py
# 圖 8：太陽能住戶能源流向
StoreNet/.venv-grid/bin/python StoreNet/src/data_paper_figures/figure08_pv_flows.py
# 圖 9：一週電池與電力運作
StoreNet/.venv-grid/bin/python StoreNet/src/data_paper_figures/figure09_battery_week.py
# 圖 10：電壓不平衡模擬
StoreNet/.venv-grid/bin/python StoreNet/src/simulate_figure10s_grid.py
```

**Windows**

```powershell
# 圖 5：資料可用率
.\StoreNet\.venv-grid\Scripts\python.exe StoreNet\src\data_paper_figures\figure05_availability.py
# 圖 6：功率與能量一致性
.\StoreNet\.venv-grid\Scripts\python.exe StoreNet\src\data_paper_figures\figure06_consistency.py
# 圖 7：用電量與氣溫
.\StoreNet\.venv-grid\Scripts\python.exe StoreNet\src\data_paper_figures\figure07_consumption_temperature.py
# 圖 8：太陽能住戶能源流向
.\StoreNet\.venv-grid\Scripts\python.exe StoreNet\src\data_paper_figures\figure08_pv_flows.py
# 圖 9：一週電池與電力運作
.\StoreNet\.venv-grid\Scripts\python.exe StoreNet\src\data_paper_figures\figure09_battery_week.py
# 圖 10：電壓不平衡模擬
.\StoreNet\.venv-grid\Scripts\python.exe StoreNet\src\simulate_figure10s_grid.py
```

圖 5～9 的 PNG 和 CSV 在 `StoreNet/results/data_paper_by_figure/` 各中文圖名資料夾。圖 10 在 `StoreNet/results/figure10_grid/`。程式會印出完整位置；重跑更新同名結果。Python 不會另外開啟 MATLAB，完成後直接打開 PNG。

圖 6 是公開 H4 資料的檢查；圖 10 是類似原論文的獨立模擬。圖 7 同時保留作者算法與修正後的數值；修正不代表原圖可逐點復現。

<a id="method-figures"></a>

## 4. 方法論文：Mac、Windows 使用同一組 MATLAB 指令

開啟 MATLAB，將「目前資料夾／Current Folder」切到專案最外層。可以按資料夾選擇按鈕選取，無須把電腦路徑寫進程式。在「命令視窗／Command Window」輸入：

```matlab
addpath('StoreNet/src', 'StoreNet/launchers');
```

再選要計算的一項：

| 內容 | 在 MATLAB 命令視窗執行 | 重跑後的資料夾 |
|---|---|---|
| 代表日，報告圖 15 | `run('StoreNet/launchers/start_bahloul_typical.m')` | `StoreNet/results/方法論文代表日/` |
| 月度比較，報告圖 17 | `run_bahloul_monthly_v1(QualityMode="release_literal", RunId="方法論文月度")` | `StoreNet/results/方法論文月度/` |
| 容量與功率，報告圖 19、Table I | `run_bahloul_sensitivity_v1(datetime(2020,8,24), QualityMode="release_literal", RunId="方法論文容量功率")` | `StoreNet/results/方法論文容量功率/` |

代表日完成後會顯示圖與摘要，並儲存 `圖15_方法論文代表日結果.png`、`typical_metrics.csv` 和 `figure5_profiles.csv`。這個入口每次更新同一份結果；計算失敗會保留前一次成功的結果。

月度圖片是 `figure6_proxy.png`；容量功率圖片是 `figure7_primary_h4_surface.png`。這兩種完整計算較久，而且原始程式要求新的結果資料夾。再次計算時，可先移開先前自行產生的同名資料夾，或在指令的 `RunId` 改一個名稱。**不需要修改程式檔。** 首頁提供的「已算好的結果」是報告使用的既有結果，與上述重跑位置分開保存。

<a id="improvement"></a>

## 5. 重畫改進策略與澳洲驗證

報告圖 24～29 使用已附的 CSV 重畫。只需安裝 Python 套件，不必重新下載原始資料或求解。

**Mac**

```bash
StoreNet/.venv-grid/bin/python StoreNet/src/render_frontier_figures.py --typical StoreNet/results/bahloul_vpp_improvement_v2_frontier/storenet_typical_20200824 --monthly StoreNet/results/bahloul_vpp_improvement_v2_frontier/storenet_monthly_2020 --output StoreNet/results/bahloul_vpp_improvement_v2_frontier/figures
```

**Windows**

```powershell
.\StoreNet\.venv-grid\Scripts\python.exe StoreNet/src/render_frontier_figures.py --typical StoreNet/results/bahloul_vpp_improvement_v2_frontier/storenet_typical_20200824 --monthly StoreNet/results/bahloul_vpp_improvement_v2_frontier/storenet_monthly_2020 --output StoreNet/results/bahloul_vpp_improvement_v2_frontier/figures
```

六張圖放在 `StoreNet/results/bahloul_vpp_improvement_v2_frontier/figures/`。報告圖 23 在 MATLAB 執行：

```matlab
render_external_validation("StoreNet/results/external_sensitivity_ausgrid_exclude_customer161_v1", Overwrite=true);
```

圖片是 `StoreNet/results/external_sensitivity_ausgrid_exclude_customer161_v1/external_validation.png`。報告圖 21、22 的數值已附，排版圖片保存在報告 PDF。

需要從頭重算改進策略、澳洲驗證或完整資料檢查時，請看 [完整計算指令](00_執行指令與檔案說明.md#advanced)。這些工作通常比單張圖慢。

## 6. 遇到問題先看這裡

| 畫面或問題 | 處理方式 |
|---|---|
| 找不到 H1_Wh.csv 等資料檔 | 先執行第 2 節的資料下載指令 |
| 找不到 Python 套件 | 用同一個 `.venv-grid` 的 Python 重做安裝套件那一行 |
| MATLAB 找不到函式 | 先選專案最外層，再執行 `addpath` 指令 |
| MATLAB 缺少 `intlinprog` 或 Optimization Toolbox | 安裝並啟用 Optimization Toolbox；只有 MATLAB 主程式不夠 |
| 執行後沒跳出圖片視窗 | Python 會直接存檔，按終端機印出的路徑開啟 PNG |
| Windows 無法使用原 Mac 的中文捷徑 | 使用 README 的程式連結與本頁指令；公開版不依賴 Finder 捷徑 |
| CSV 在 Excel 顯示亂碼 | 用 Excel「資料 → 從文字/CSV」，選 UTF-8 編碼匯入 |
| 圖 10 中文出現方框 | 使用有繁體中文字型的系統；Windows 可用微軟正黑體，Mac 可用蘋方 |
| 下載失敗 | 重新執行；也可依 [資料下載頁](02_資料下載與來源.md) 手動下載到指定位置 |

近期系統測試與範圍見 [GitHub Actions](https://github.com/sapunomin1-star/storenet-reproducibility/actions)。完整年度、月度和所有敏感度組合的求解時間會依硬體而異。
