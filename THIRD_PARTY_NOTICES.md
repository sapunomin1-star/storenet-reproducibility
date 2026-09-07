# 授權與引用

本專案新增的 Python／MATLAB 程式及操作文件採用 [MIT 授權](LICENSE)。本專案不是原論文作者的官方程式；下列原始論文、資料及電網檔案各自沿用來源授權。

| 內容 | 來源與授權 | 本包的處理方式 |
|---|---|---|
| StoreNet 原始資料與作者隨附程式，共 46 檔 | [Figshare v1](https://doi.org/10.6084/m9.figshare.c.6829134.v1)，CC0 1.0 | 原樣提供資料包；逐項授權於 2026-09-07 核對，記錄見 [來源授權清單](StoreNet/reference/figshare_licenses.json) |
| Trivedi 等人的 2024 資料論文 | [論文頁](https://doi.org/10.1038/s41597-024-03454-2)，CC BY 4.0 | 保留作者與完整來源；論文內另行標示的第三方素材依其標示 |
| Bahloul 等人的 2022 方法論文 | [論文頁](https://doi.org/10.1109/TSTE.2022.3187217)，附檔標示 CC BY 4.0 | 保留原文 PDF、作者與授權標示 |
| Ausgrid Solar Home Electricity Data | Ausgrid，CC BY 3.0 Australia；下載管道是 [Pierre Haessig 封存](https://pierreh.eu/ausgrid-solar-data/) | 從封存下載原始 ZIP，保留原始說明 PDF；這是第三方保存副本 |
| OpenDSS 格式的歐洲低壓電網 | Electric Power Research Institute，BSD 類型授權 | 保留 [原始授權全文](StoreNet/data/external/ieee_european_lv/LICENSE.txt)及[取得版本](StoreNet/data/external/ieee_european_lv/來源紀錄.json) |
| IEEE 原始核對 CSV | [IEEE PES AMPS 原始庫](https://github.com/ieee-pes-amps/dtf-dev)，檢查時 LICENSE.md 仍為 TBD | 不收進本庫或 Releases；下載程式從已記錄的原始版本取得 |

本包的研究報告及自製結果圖以 CC BY 4.0 分享；其中引用的論文圖表與第三方內容保留原作者權利及各自的授權。本包的重畫、翻譯、數值修正和獨立模擬由報告與圖說說明，不能視為原作者背書。

CC BY 的使用者須標明作者、來源與授權，並註明修改。授權全文：[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)、[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)、[CC BY 3.0 AU](https://creativecommons.org/licenses/by/3.0/au/)。

引用研究結果時，請同時引用相關原論文及本復現包的 GitHub 版本。StoreNet 研究作者包括 Shafi Khadem、Rohit Trivedi、Mohamed Bahloul 及共同作者；完整書目見 [論文與資料來源](01_論文/論文與資料來源.md)。

Python 套件、MATLAB 和 Optimization Toolbox 各有其原始授權；本專案不附帶 MATLAB 軟體或授權。
