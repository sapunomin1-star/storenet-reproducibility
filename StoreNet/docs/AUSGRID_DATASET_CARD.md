# Ausgrid 2012–2013 外部驗證資料卡

## 來源與用途

本資料卡只界定 StoreNet 模型的外部效度測試，不把澳洲資料冒充 StoreNet 原論文輸入。首選年度為 2012-07-01 至 2013-06-30，理由是它提供 300 戶、每戶獨立量測的住宅負載與 gross PV，解析度同為 30 分鐘，能在不反推淨電表組成的情況下重播同一個虛擬電池控制問題。

- 資料論文：Ratnam, Weller, Kellett and Murray, “Residential load and rooftop PV generation: an Australian distribution network dataset,” *International Journal of Sustainable Energy*, DOI [10.1080/14786451.2015.1100196](https://doi.org/10.1080/14786451.2015.1100196)。
- 官方 metadata：[Data.gov.au: Solar Home Electricity Data](https://data.gov.au/data/en/dataset/nsw-solar-home-electricty-data)。
- 原始授權：Creative Commons Attribution 3.0 Australia。
- 目前可取得封存：[Pierre Haessig 的資料說明頁](https://pierreh.eu/ausgrid-solar-data/)於 2026 年 5 月補上自行保存的副本：[Ausgrid archive copy](https://pierreh.eu/downloads/Ausgrid_solar_home_data.zip)。封存內含 Ausgrid 2014 官方說明 PDF、三個年度 CSV 與來源說明。

Ausgrid 舊官網的原始下載連結目前已失效，因此不能把「仍有官方 metadata」寫成「官方原檔目前可直接下載」。本專案保留 Pierre Haessig 的封存 ZIP，以及計算用的 2012–2013 CSV 和官方說明 PDF。2026-09-06 整理時，已確認另一份本地 ZIP 的年度 CSV 與說明 PDF 內容相同，並移除該重複 ZIP。另一份 ZIP 缺少取得來源紀錄，因此不把這次比對稱為兩條獨立來源驗證。背景完整性清單見 [`AUSGRID_MANIFEST.sha256`](../data/AUSGRID_MANIFEST.sha256)。

## 取得管道補充核對（2026-09-05）

使用者確認所指管道為 [Pierre Haessig 的資料封存頁](https://pierreh.eu/ausgrid-solar-data/)。該頁的 2026 年 5 月更新與 5 月 27 日作者回覆明確說明舊官網已無資料，並提供自架 ZIP。此頁應與 ZIP 直連一併引用，讓讀者看得到副本來源說明。

- 本次舊 Ausgrid 資料頁回傳 HTTP 404；Pierre Haessig 封存網址可讀得 ZIP 開頭。官方資料目錄仍可讀得 HTML，但不代表官方原檔下載恢復。
- [Ratnam 作者的 ResearchGate 頁面](https://www.researchgate.net/publication/296112744_httpwwwausgridcomauCommonAbout-usCorporate-informationData-to-shareSolar-household-dataaspx)另列有 2012–2013 ZIP 附件。這次只確認頁面與附件紀錄，尚未完成附件下載與本地雜湊比對，因此不能回填成第二份 ZIP 的歷史取得來源。
- 本次再次確認兩份本地 ZIP 內年度 CSV 與原始說明 PDF 的 SHA-256 分別一致。外部驗證預註冊中較強的「雙來源」表述已加註勘誤。
- 完整的取得層次、檢查限制與建議引用文字見 [來源核對](../../01_論文/Ausgrid_資料取得來源核對_2026-09-05.md)。

## 欄位與時間契約

Ausgrid 官方說明將 48 個數值欄定義為每半小時的能量 `kWh`，時間標籤為區間結束時刻：`0:30` 代表 `(00:00,00:30]`，最後的 `0:00` 代表 `(23:30,24:00]`。資料在夏季使用 daylight-saving local time，但每日仍以 48 個位置發布，沒有 UTC offset；因此 adapter 保存「naive Sydney local wall clock」語意，不虛構可追溯的 UTC 時間。

每戶每日的 canonical 輸入為：

- `loadKWh = GC + CL`；凍結 adapter 把不存在的 `CL` 行解讀為該戶該日沒有 controlled-load tariff，取 0。Customer 161 的連續 59 日缺列顯示原始資料無法區分「真無 CL」與「CL 未發布」，因此另做整戶排除敏感度，不能把此規則寫成已驗證的量測事實。
- `pvKWh = GG`；它是與住宅負載分開、在逆變器後量測的 gross AC generation。
- `loadKW = loadKWh / 0.5`，`pvKW = pvKWh / 0.5`。
- `Row Quality` 必須為空白；`NA` 表示至少一個值是估算或替代值，整個 community-day 拒絕。
- 不補 0、不插值；缺少 `GC`／`GG`、重複 category、非有限值或負值都拒絕。

## 事前固定 cohort

資料論文公開 54 個跨三年沒有負載／PV 異常的 clean customers。Customer 2 在 2012-10-12 至 2012-12-31 缺少 `GC` 與 `GG`；為保留完整季節覆蓋，於任何最佳化前排除 Customer 2，留下 53 戶。這不是按 savings、peak 或 solver 成功率選戶。

在 53 戶 cohort 上，2012–2013 年共有 359 個通過凍結契約的日子；六個被拒絕日期為：

`2013-01-09`, `2013-01-10`, `2013-01-31`, `2013-04-16`, `2013-04-17`, `2013-04-26`。

這裡的 359 日只表示通過凍結的 `GC`／`GG` + optional-`CL` 契約，不表示所有負載 component 都完整觀測。Customer 161 在 `2013-02-01` 至 `2013-03-31` 沒有 `CL` rows；排除整戶後的 52 戶 post-hoc sensitivity 仍通過 headline gates，但這不會反向證明缺失 `CL=0`。

## 模型映射

主分析是 fixed-policy transfer：電池、分享損失與兩段電價沿用 StoreNet，使差異主要反映氣候與住戶行為，而不是政策參數同時改變。它是反事實控制實驗，不能解讀為 2012–2013 澳洲實際帳單。

因 `GG` 是 inverter-AC，使用 `etaPvAC=1.0`，避免把已完成的逆變轉換再扣一次；PV→電池路徑保留 `etaPvDC=0.95` 作 AC-coupled charging conversion。其餘主要參數為每戶 10 kWh／3.3 kW、充放電效率 0.95、分享損失 0.07、零 FIT。

模型仍不包含配電潮流、電壓、線路容量、澳洲 FIT、異質電池或預測誤差；外部驗證通過不等於這些環節已驗證。

## 已知代表性限制

- 300 戶是 solar adopters，並非 Ausgrid 全體住宅的統計代表樣本。
- 沒有住戶人口、設備、PV orientation 或 feeder topology。
- clean cohort 是保守品質子集，可能降低真實部署中的缺失與故障風險。
- 日期跨越 daylight saving，但發布格式不足以重建真實 23／25 小時日。
- 固定 StoreNet tariff 只隔離資料分布變化，不是 local-policy validation。
