# Scientific Data 論文 Figure 5-10 復現與驗證

稽核日期：2026-09-01

資料論文：Trivedi et al., *Comprehensive Dataset on Electrical Load Profiles for Energy Community in Ireland*

論文 DOI：[`10.1038/s41597-024-03454-2`](https://doi.org/10.1038/s41597-024-03454-2)

資料 DOI：[`10.6084/m9.figshare.c.6829134.v1`](https://doi.org/10.6084/m9.figshare.c.6829134.v1)

v2 正式產物（僅在目錄內 manifest、checksum 與全部 required gates 通過時有效）：[`results/data_paper_figures_5_10_v2`](../results/data_paper_figures_5_10_v2/)

v1 provenance（保留、不覆寫）：[`results/data_paper_figures_5_10_v1`](../results/data_paper_figures_5_10_v1/)，Git tag `data-paper-figures-5-10-v1`

本文所有 Figure 5--10 均指 **Trivedi et al. (2024) 資料論文**。Bahloul et al. (2022) VPP 方法論文的同號圖一律寫成「Bahloul Figure 5/6」，不得混稱。

## 1. 結論

這次工作不是只追求圖片外觀，而是逐圖保存輸入、計算、數值 sidecar 與可重現性判定。正式結論如下：

| 圖 | 結論 | 可安全主張 |
|---|---|---|
| Figure 5 | **數值精確復現** | 20/20 戶 availability 百分比在論文顯示精度下完全一致 |
| Figure 6 | **發布資料的一般一致性獲強力支持；已刊 H4 圖仍不能逐點復現** | Consumption 19/20 戶、PV Production 9/10 戶達 `r>0.99`；唯一例外 H4 有可定位的時間組裝缺陷 |
| Figure 7(a) | **20 根柱值精確復現，但論文 caption 自相矛盾** | 柱值平均是 `5003.11253`，不是 caption 的 `5025.64 kWh/戶` |
| Figure 7(b) | **legacy 曲線與 `r=-0.31` 可復現，但單位錯** | 趨勢仍為負相關；原圖不能解讀為真正 `kWh/day` |
| Figure 8 | **公開 Wh 資料可復現** | 10 個 PV 戶的四類年度能量流可重算；正文所稱 production 全在 1800-2000 kWh 不成立 |
| Figure 9 | **公開 Wh 資料可復現** | H4 的 2020-12-07 至 12-13 共 10,080 分鐘完整存在，能量平衡殘差可量化 |
| Figure 10 | **只能做結構性追溯，不能逐點復現** | 圖是另一篇網路研究的結果重刊；公開 StoreNet CSV 不含 node voltage/VUF matrix，`Figure 10-S` 延後併入網路約束改進 |

因此，老師要求的「先確認資料內容與結果是否一致」已有明確答案：**本地 46/46 檔案與 Figshare v1 官方發布清單一致，且 Figure 6 的資料集層級一致性可確認；但這不等於每條 time series 或 raw truth 完整。已刊 H4 Figure 6、Figure 7 caption/單位與 Figure 10 仍有公開資料邊界，不可硬調到看似一致。**

## 2. 共用資料與方法

正式流程先以 [`RELEASE_MANIFEST.sha256`](../data/RELEASE_MANIFEST.sha256) 驗證 46 個 Figshare v1 檔案，46/46 通過後才讀取資料。作者原始程式不被修改；新流程由 [`reproduce_data_paper_figures.py`](../src/reproduce_data_paper_figures.py) 以 headless 模式產生固定名稱的 PNG、CSV、JSON 與 manifest。v2 manifest 必須記錄 `contractId=SR2020-IR-v2` 與執行時 [`REPRODUCTION_CONTRACT.md`](REPRODUCTION_CONTRACT.md) 的 SHA-256；v1 產物維持原 provenance，不追溯改寫。

作者程式中可重現的「已刊邏輯」稱為 `paper_legacy`；時間、單位或統計修正後的結果稱為 `unit_corrected`。兩者分開輸出，不以修正版覆蓋原圖，也不以原圖錯誤取代科學數值。`paper_legacy` 年度值使用各戶全部 released rows；嚴格 `calendar_2020` 則只使用 `[2020-01-01 00:00, 2021-01-01 00:00)`，兩種期間不可混稱。

## 3. Figure 5：住戶量測資料可用性

### 圖的意義

每列代表一戶，深藍代表該分鐘的 W status 為 1，白色代表 status 缺失或檔案沒有該列。左側百分比衡量資料覆蓋率，可用來判斷哪些住戶／期間適合後續模型。

### 復現方式

讀取 20 個 `Hn_W.csv` 的 `date` 與同名 `Hn_W` status 欄，依作者畫圖行為放到 527,040 列的共同 plot grid。可用率為：

`available status rows / 527040 x 100%`。

20 個論文百分比全部在小數點後兩位一致。H10 有 2,317 個 unavailable plot-grid rows，也與論文文字一致。

### 發現的差異

- 論文文字把總筆數寫成 527,039；作者 Figure 5 程式的共同 DataFrame 長度實際為 527,040。兩種分母不影響已刊兩位小數，但 provenance 不同。
- 論文稱缺值通常只連續 1-2 分鐘，但 released status 可重現 H4/H13 的 1,440 分鐘、H16 的 7,978 分鐘，以及 H14 含檔尾的 28,860 分鐘長缺口。
- 圖上白帶受像素壓縮影響；視覺寬度不能替代 gap-run 數值。

## 4. Figure 6：W 與 Wh 的內部一致性

### 圖的意義

一分鐘能量乘以 60 應等於同分鐘等效平均功率；若兩種量測一致，hexbin 應集中在 `y=x`。hexagon 顏色代表落入該 bin 的資料點數，顏色才使用對數尺度。

### 全戶 released-data audit

正式稽核以相同 published timestamp label 比較 `W` 與 `60*Wh`。這是檢查兩個發布串流的標籤／數值是否對得上；[`REPRODUCTION_CONTRACT.md`](REPRODUCTION_CONTRACT.md) 將 Wh timestamp 定義為區間終點，是聚合契約，兩者並不矛盾，也不能因 H4 的診斷結果把所有住戶整體平移。

全戶表同時保存兩種比較口徑：`finite_release_same_timestamp` 使用相同 timestamp 的有限發布值；`observed_both_endpoints` 另要求連續分鐘網格且 W status `t-1` 與 `t` 都為 1。後者只是 W-status proxy-observed，不是 Wh raw truth 證明。兩種口徑均得到下表的相同戶數與唯一例外；嚴格的 `observed_both_endpoints` gate 不是只看 correlation，而是同時要求 `r>=0.99999`、P99 absolute error `<=0.200000001 W`、以及至少 99.999% 配對點誤差在 `0.5 W` 內。

| 檢查 | 兩種口徑通過戶數 | 唯一未通過戶 |
|---|---:|---|
| Consumption，20 戶 | **19/20** | H4 |
| Production，10 個實際 PV 戶 | **9/10** | H4 |

其餘住戶為 `r≈1`，不是數學上的逐點完全相等；論文顯示的 `1.0` 可能包含顯示精度的四捨五入。v1 已正確保留「公開 H4 pair 不能重現已刊 H4 圖」的限制；v2 新增全戶及雙口徑證據，因此可再主張：**一般發布資料一致性獲得強力支持，但論文所選 H4 的已刊圖仍不能由公開 pair 逐點復現。** v2 不追溯修改 v1 產物或其 provenance。

### H4 的直接比較與缺陷定位

以 released H4 同 timestamp 的有限值比較：

| 訊號 | 配對點數 | Pearson r | RMSE (W) | 99th-percentile absolute error (W) |
|---|---:|---:|---:|---:|
| Production | 524,470 | `0.73217169` | `300.425` | `1424` |
| Consumption | 524,470 | `0.52194577` | `1236.967` | `4702` |

逐日及跨日期診斷進一步確認：

- H4 的部分日塊存在約 **60 分鐘**的位移；程式固定把正 offset 定義為比較 `W(t)` 與 `60*Wh(t+offset)`，不把它改寫成全資料平移規則。
- 凍結規則將 366 日分成：146 日 `unaffected_same0`、1 日 `unassessable_no_finite_W_pairs`（2020-02-29）、135 日 `same_date_plus60_core`、42 日 `actual_transpose_plus60_core`、7 日 `diagonal_identity_plus60_control`、35 日 `unresolved`。42 個 actual transpose 才是真正交換 `DD/MM` 與 `MM/DD`；7 個月日相同日期只是 identity controls，不能算成 49 個實際轉置。
- `+60 min` 與轉置分類只用目標日內 23 小時 core 視窗；184 個 core-aligned 日不等於完整 24 小時已修復。同日期 `+60 min` 的 Consumption 在連續 24 小時檢查只有 131/135 日通過，失敗日為 2020-05-31、06-30、07-31、08-31。49 個日期轉置／identity controls 同時要求 source 與 mapped target 兩側的 W-status proxy-observed endpoints；core 的 Production 與 Consumption 都是 49/49，連續 24 小時則為 Production 49/49、Consumption 29/49。這些操作是缺陷診斷，不是核准後的資料修補。
- 每日 lag search 至少需要 60 個有限配對點且兩側變異非零；不符合時 offset、相關係數與 pass 欄明示為 NA，不讓稀疏日或全零 PV 日產生看似有效的最佳 lag。
- `H4_W.csv` 比其他戶多出 `Unnamed: 6`；共有 314,742 個索引狀非空值。它與日期組裝異常並存，但沒有上游處理紀錄，不能把相關性寫成已證實的單一成因。
- 限定 2--8 月、Consumption、同 timestamp 的跨戶控制皆低於 `0.11`，排除了最直接的「整段同 timestamp 串到另一公開住戶」解釋；這不等於排除所有上游混檔或組裝形式。

異常不是「2--8 月全部無效、1 月及 9--12 月全部正常」：全年有交錯的正常／異常日期區塊，35 日仍 unresolved，日期轉置也可能造成碰撞。若把診斷 mapping 直接當成修復，會產生 timestamp 重複／缺口，因此機器可讀 mask 與 segment 才是規範來源，不得在報告或 loader 另寫粗略月份規則：

- `figure6_all_house_metrics.csv`：20 戶同 timestamp 指標；
- `figure6_h4_daily_diagnostics.csv`：H4 每日 lag 與相關診斷；
- `figure6_h4_monthly_summary.csv`：逐日統計的月度摘要，不能誤讀成 pooled-month correlation；
- `figure6_h4_alignment_summary.csv`：六類凍結規則、core 與連續 24 小時邊界結果；
- `figure6_h4_anomaly_segments.csv`：正式異常 mask／連續區段；
- `figure6_h4_date_transpose_diagnostics.csv`：日期轉置控制；
- `figure6_h4_cross_house_controls.csv`：跨戶負控制；
- `figure6_h4_wh_balance.json`：Wh 發布欄位的內部平衡證據與限制。

H4 Wh 的全年分鐘平衡殘差平均絕對值為約 `0.0009306 Wh`、最大絕對值為 `45.68 Wh`。這支持 Wh 各流量欄在 processed release 內部高度自洽，但不證明 Wh 是 raw ground truth，也不能因此斷言一定是 W 感測器損壞。

作者 Figure 6 程式明確讀取未公開的 `original data/.../90962_2020_{W,Wh}.csv`，而不是目前 deposit 的扁平化 H4 processed pair。因此未公開原始 pair 仍是逐點重畫已刊 H4 hexbin 的必要來源；缺檔已不再阻擋資料集層級的一致性判斷，卻仍阻擋該圖的精確復現。診斷結果也不應反過來斷言作者未公開檔必然錯。

### 圖說／程式差異

- caption 稱 x/y 軸也是 log 且有灰色虛線；已刊圖包含 0、作者程式沒有 `set_xscale`/`set_yscale`，也沒有畫 `y=x`。
- 程式只有 `hexbin(..., bins='log')`，也就是 count colour 使用 log。
- Wh 乘 60 後單位已是 W-equivalent，不應繼續把 y 軸解讀為 Wh。

## 5. Figure 7：年度用電與氣溫

### Figure 7(a)

每戶 `Consumption(Wh)` 依作者程式對全 released file 加總後除以 1000。20 根柱的一位小數標籤全部精確復現，合計 `100,062.25055 kWh`，平均 `5003.1125275 kWh/戶`。

論文 caption 與正文寫 `5025.64 kWh/戶`，但這不是 20 個已刊柱值的平均，也不能由 Figshare v1 重算，因此是論文內部差異，不應把程式調成 5025.64。

另須注意多數檔案延伸至 2021-01-01 00:59，所以 legacy 柱值包含新年度最初 60 分鐘；嚴格 calendar-2020 合計／平均是 `100,048.04326`／`5002.402163 kWh`。例如 H10 legacy 比 calendar-2020 多 `1.33687 kWh`。同時 H14 在 2020-12-11 23:59 結束；其 `5294.417925 kWh` 仍是 partial-year release，不得靜默補尾或年化。正式 sidecar 並列兩種 total、每戶起迄 timestamp、row count 與 `ReleaseIntervalComplete`。

### Figure 7(b)

此圖用來描述聚合用電與日均氣溫的季節性反向關係。作者程式實際做法是：

1. 每分鐘先加總 20 戶 `Consumption(Wh)`；
2. 依人工建立、由 2020-01-01 00:00 開始的 row-index 日期取 daily **mean**；
3. 未做 daily sum，也未除以 1000，卻把 y 軸標成 `kWh/day`。

| 版本 | 量 | 平均 | 最大 | 與日均溫 Pearson r |
|---|---|---:|---:|---:|
| `paper_legacy` | aggregate Wh/min 的 daily mean | `189.8575` | `305.5854` | `-0.314131` |
| `released_processed` | 當日所有 finite processed Wh 的 timestamp-aware sum/1000 | `273.3553 kWh/day` | `439.9071 kWh/day` | `-0.310518` |
| `released_grid_complete20` | 僅 20 戶 processed series、1440 分鐘皆 finite 的 daily sum/1000 | `268.2050 kWh/day` | `390.3099 kWh/day` | `-0.233946` |

`released_grid_complete20` 共有 345 日（2020-01-02 至 2020-12-11）。2020-01-01 缺少開頭分鐘，H14 在 12/11 後結束，因此這些 released-grid 不完整日不進入 20 戶推論；圖中另以灰線保留所有 finite processed series 的 aggregate 供診斷。這裡的「finite」不代表原始觀測完整：Wh 已被作者插值，且 observation/imputation mask 未公開，例如 H10 2020-01-02 的兩個原始缺點在 processed Wh 中仍為有限值。負相關方向保留，但 released-grid-complete 樣本的相關係數約 `-0.234`，弱於 legacy 的 `-0.31`。原圖的 y 軸量綱與幅度錯誤，不能直接引用為每日 kWh。

## 6. Figure 8：PV 家戶年度能量流

### 圖的意義

四個雷達圖分別比較 10 個 PV 戶的 annual production、consumption、feed-in 與 from-grid。它揭示不同住戶的需求規模、自用程度及對電網的依賴。

PV cohort 為 `H1,H2,H3,H4,H5,H7,H10,H11,H13,H17`；正式圖保持論文順序 `H10,H11,H13,H17,H1,H2,H3,H4,H5,H7`。例如 H4：

- Production `1864.890715 kWh`
- Consumption `7875.426460 kWh`
- Feed-in `160.623200 kWh`
- From grid `6609.861200 kWh`

資料支持論文對 H4「高需求、低 export、高 grid import」的解讀。但 10 戶 production 真實範圍為 `1747.548-2084.449 kWh`，不是正文所稱全部在 `1800-2000 kWh`。

輸出的 numerical sidecar 以 `PaperLegacyProductionKWh`／`Calendar2020ProductionKWh` 等成對欄位命名，其他 flow 亦同，避免把已除以 1000 的數字誤讀為 Wh，也避免把 full-release legacy total 誤稱為嚴格 calendar-2020。正式雷達圖為了核對論文，使用 paper-legacy 欄；calendar-2020 companion 保存在同一 CSV。

## 7. Figure 9：H4 一週電池與電力交換

### 圖的意義

七個共用時間軸面板顯示 PV、負載、grid import/export、charge/discharge 與 SoC，能直接檢查住宅能源平衡和電池運作時段。

正式範圍為 2020-12-07 00:00 至 2020-12-13 23:59，共 10,080 個唯一的一分鐘 timestamp，無缺分鐘。Wh 除以相鄰 timestamp 的小時差轉為 W；正確平衡式為：

`from_grid + production + discharge = consumption + charge + feed_in`。

本週最大絕對 residual 為 `0.43 Wh`。12/11、12/12、12/13 的 grid import 分別約 `25.560`、`25.990`、`34.904 kWh/day`，支持低 PV 日需增加電網輸入的解讀。

論文文字稱 12/8 高 PV、低 consumption 後有明顯 feed-in；released data 的 12/8 production/consumption 分別約 11.933/11.789 kWh，feed-in 只有 0.023 kWh。明顯 feed-in 是 12/7 的 4.090 kWh，已刊圖也把主要 feed-in 畫在 12/7，故正文日期疑似晚寫一天。

## 8. Figure 10：LEM 情境下的 voltage unbalance

Figure 10 不是資料論文作者繪圖程式的一部分，而是 Saif et al. (2023), *Energy Reports*，DOI [`10.1016/j.egyr.2023.05.005`](https://doi.org/10.1016/j.egyr.2023.05.005) 的 Figure 13 重刊。

可公開取得的只有結構層資訊：IEEE European LV stock feeder、55 個單相客戶的 A/B/C 分配、部分 tariff/ESS 設定及 VUF 定義。逐點重現仍缺：

- 修改後 350 kVA paper-specific OpenDSS circuit；
- 20 戶 load／10 戶 PV 映射或縮放至 55 nodes 的規則；
- 每戶 PV、power factor、loss weight、LEM/SO optimization code 與 solver tie handling；
- 55 x 24 node phasors 或 VUF matrices。

原研究的 data-availability statement 是 data available on request。IEEE stock transformer 與論文修改版也不相同。因此正式分類為 **STRUCTURAL ONLY / POINTWISE EXACT NOT REPRODUCIBLE**；本專案不生成一張加入任意假設的 surface 冒充原圖。

這項結論本身已完成老師要求的公開資料一致性／可復現性判斷，資料採用 gate 不以另畫替代 surface 為前提。規劃中的 `Figure 10-S` 延後至配電網路約束改進，與 feeder、住戶映射、變壓器容量及不平衡潮流模型共用同一套基礎建設；完成後只能稱為**獨立可行性／敏感度模擬**，不能稱為已刊 Figure 10 復現。

## 9. 資料採用判斷

這批公開資料適合：

- 經品質旗標篩選後的 household load/PV/energy-storage 描述；
- Trivedi Figure 5、7(a)、8、9 的 processed-release 重現；
- Trivedi Figure 6 的資料集層級 `W`／`60*Wh` 一致性判斷（Consumption 19/20、PV Production 9/10 通過 `r>0.99`），並將 H4 明列為發布檔時間組裝例外；
- 後續 VPP 方法的同源獨立實驗。

它不適合直接用來主張：

- 作者 raw logger 與 raw-to-processed pipeline 已完整驗證；
- 已逐點重現 Trivedi Figure 6 的 H4 `r=1.0` hexbin，或每一戶皆精確 `r=1.0`；
- H4 的 Wh 已證實為 ground truth、W 已證實為唯一損壞來源，或粗略的 2--8 月可以取代正式 anomaly mask；
- H14 的 partial-year total 是完整 annual total；
- Trivedi Figure 10 的 voltage/VUF 已重現；
- 所有 Wh 插值點都是真實量測。

因此下一篇 VPP 論文可以使用這批資料，但必須沿用 [`REPRODUCTION_CONTRACT.md`](REPRODUCTION_CONTRACT.md) 的品質模式與「同源獨立復現」用語，不能冒充作者未公開的原始期間與網路模型。主分析保留未平移、未交換日期的 released H4 Wh；每個 20 戶正式結果必須成對提供同設定的 19 戶排除 H4 敏感度。W status 只是 processed-release observation proxy，不能替代未公開的 Wh 原始觀測／插值 mask。

資料論文 gate 以 v2 八份 Figure 6 sidecar 全數存在、列入 manifest/checksum 並通過驗證為完成條件；VPP v2 結果則另須通過 H4-excluded 成對敏感度。這裡是本文件的「資料採用判斷」第 9 節，不是 `REPRODUCTION_CONTRACT.md` 的第 9 節；後者定義的是正式驗收門檻。

## 10. 重跑

```bash
cd "/Users/guichenxiang/Desktop/電力專案"
uv venv StoreNet/.venv-figures --python /usr/bin/python3
uv pip install --python StoreNet/.venv-figures/bin/python -r StoreNet/requirements-figures.txt
StoreNet/.venv-figures/bin/python -m unittest -v StoreNet/tests/test_data_paper_figures.py
StoreNet/.venv-figures/bin/python StoreNet/src/reproduce_data_paper_figures.py \
  --output-dir StoreNet/results/<new_run_id>
```

輸出目錄若已存在，流程會 fail closed，不會覆寫既有正式證據。
