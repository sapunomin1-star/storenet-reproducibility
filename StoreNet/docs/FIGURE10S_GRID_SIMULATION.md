# 圖 10 電壓不平衡模擬：使用方式

執行程式是 `src/simulate_figure10s_grid.py`。完整指令見 [Mac／Windows 執行說明](../../02_中文程式導覽/01_Mac與Windows操作.md#data-figures) 的圖 10。

結果固定保存在 `results/figure10_grid/`，重跑更新同一版。圖片是 `圖10_電壓不平衡模擬.png`，數值在同資料夾的 CSV。

這是公開饋線加上 StoreNet 曲線的**獨立模擬**，不是作者未公開模型的逐點復現。冬日固定電價、夏日日夜電價同時改變兩個因素，不能用這兩圖單獨判斷電價效果。詳細假設及來源保存在結果說明與 `config/figure10s_grid.json`。

## 程式與環境

- `src/simulate_figure10s_grid.py`：資料整理、社區電池排程、三相潮流及繪圖。
- `.venv-grid`：本包繪圖與電網模擬使用的 Python 環境。
- `requirements-grid.txt`：本次成功執行環境的版本清單。

若搬到另一台電腦，依上述 Mac／Windows 操作說明建立環境並下載資料。

首次讀取 20 戶檔案後會建立每小時快取；每次重跑仍核對原始檔 SHA-256，來源改變會重建快取。重跑不需要下載資料。

## 結果核對

「三相電壓與VUF.csv」包含每個客戶位置、每小時的 A/B/C 複數電壓、接入相與 VUF。公式採 `100 × abs(Vnegative) / abs(Vpositive)`，並和 OpenDSS 序分量交叉核對。「電池排程.csv」保存 AC 側充放電和電量起訖；「驗證結果.json」保存潮流收斂、能量平衡與充放電互斥檢查。

電池排程是線性規劃：最低社區淨買電成本，滿足逐時能量平衡、充放電功率、SOC 及相同起訖 SOC；次目標在 1e-7 歐元最優成本容許差內減少吞吐量。解後檢查無同時充放電。此版沒有雙邊 P2P 交易與電網約束；電網損失在後續潮流中計算。

公開饋線的原始下載檔、來源版本與雜湊在 `data/external/ieee_european_lv/`。不執行原版 Master.dss 的全年模式，改由本版程式載入線路並逐小時指定 StoreNet 淨功率。
