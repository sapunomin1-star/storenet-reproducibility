# StoreNet 資料稽核報告

稽核日期：2026-09-01  

適用契約：`SR2020-IR-v2`；既有 VPP 結果須另通過 H4-excluded 成對敏感度才能升格為 v2

資料版本：Figshare collection v1，DOI [`10.6084/m9.figshare.c.6829134.v1`](https://doi.org/10.6084/m9.figshare.c.6829134.v1)

## 1. 結論摘要

1. 本地 46 個 StoreNet 發布檔與 Figshare v1 官方項目的檔名、byte size 與 MD5 比對結果為 46/46 一致；本 repo 保存的 SHA-256 manifest 亦於本次稽核 46/46 通過。這證明本地複本與所對應的公開發布版一致。
2. `data/raw` 的目錄名稱不等於資料語義。其內容是作者已重採樣、改名並對部分缺口線性插值的 **processed Figshare release**，不是 battery logger 原始檔。
3. 公開發布版有可重現的資料問題：H4 額外欄位與 W/Wh 不一致、H14 提前截止、H16 多日插值、插值期間同時充放電、timezone/DST 不明，以及多個 PV 超長發電時間窗日期。
4. 這些問題不是本地搬運損壞；但 hash 一致也不能證明數值是未處理的實際物理量測。
5. 本專案因此定位為「使用 2020 公開發布版的同源獨立復現」，不宣稱數值級精確重現 2022 VPP 論文的 Figure 5、Figure 6、Table I 或 Figure 7。

## 2. 資料來源與完整性驗證

### 2.1 來源鏈

| 層級 | 來源 | 本專案用途 |
|---|---|---|
| 資料論文 | Trivedi et al., *Scientific Data* (2024), DOI [`10.1038/s41597-024-03454-2`](https://doi.org/10.1038/s41597-024-03454-2) | 資料集結構、20 戶系統與發布處理說明 |
| 公開資料 | Figshare collection v1 | 2020 年一分鐘 W/Wh 住戶檔與氣象檔 |
| 方法論文 | Bahloul et al., *IEEE TSTE* (2022), DOI [`10.1109/TSTE.2022.3187217`](https://doi.org/10.1109/TSTE.2022.3187217) | 虛擬電廠策略、參數與比較架構 |
| 本地不可變複本 | `data/raw` | 只讀輸入；目錄名稱沿用既有路徑，語義固定為 processed release |

2022 方法論文早於 2024 資料論文，使用的是 StoreNet 專案當時內部量測，不能反向說成「2022 論文直接使用後來發布的 Figshare 版」。兩者同屬 Dingle StoreNet 專案，但期間與配置不完全相同。

### 2.2 46 檔驗證

發布內容共 46 檔：

- 20 戶 `Hn_W.csv` 與 20 戶 `Hn_Wh.csv`，共 40 檔；
- `weather.csv` 1 檔；
- `README.md` 1 檔；
- 作者提供的 Python/安裝程式 4 檔。

驗證分為兩層：

1. **官方對應**：本地 46 檔與 Figshare API 提供的檔名、byte size 及 MD5 逐檔比對，結果無 missing、extra 或 mismatch。
2. **本地基線**：[`data/RELEASE_MANIFEST.sha256`](../data/RELEASE_MANIFEST.sha256) 記錄上述 46 檔的 SHA-256。2026-09-01 從專案上層目錄執行以下指令，46/46 均回報 `OK`：

```bash
shasum -a 256 -c StoreNet/data/RELEASE_MANIFEST.sha256
```

SHA-256 manifest 是實作前的本地不可變基線；Figshare MD5 比對才是「與官方發布項目相同」的外部證據。兩者用途不同，不應混為同一種保證。

## 3. Processed release 不是 raw data

`Hn_W.csv` 與 `Hn_Wh.csv` 是已處理的一分鐘規則網格。`Hn_W` 欄位中的空白 status 可重現作者插值位置；Wh 數值則已經存在於這些位置。因此：

- 有數值不等於有真實觀測；
- 不可用 `isfinite(Wh)` 取代 W status 品質遮罩；
- Wh timestamp 視為一分鐘區間終點，日 D 必須使用 `(D 00:00, D+1 00:00]`；
- 一個 Wh 區間只有在前後兩個 W status 端點均為 1 時才標記為 **W-status proxy-observed**，所以缺口後的第一個邊界區間也會被標記；這只是發布資料 observation proxy，不是 Wh raw truth 證明；
- 聚合必須加總 Wh，先轉 kWh，再除以 `dtHours` 得到 kW；
- 任何缺列、檔尾或非有限值都不得補 0。

無法從公開版回建的上游內容包含 battery-ID 原始資料夾、12 個原始月氣象檔、原始 figures 資料夾與完整可執行的 raw-to-processed 環境。所以本專案可驗證發布版的處理痕跡，但不能審計每一步上游變換或還原未插值量測。

## 4. 已確認的資料問題

| 項目 | 可重現證據 | 研究影響 | 本專案處置 |
|---|---|---|---|
| H4 額外欄位與 W/Wh 不一致 | `H4_W.csv` 多出 `Unnamed: 6`；314,742 個索引狀非空值依相鄰值是否連續分成 20 blocks，合計涉及 219 affected days。雙訊號診斷支持部分同日期 `+60 min`、部分 `DD/MM`↔`MM/DD` 後 `+60 min`，但仍有 35 日 unresolved | 不能把額外欄位當成空白裝飾欄，也不能把粗略月份範圍或 23 小時 core 對齊當成完整 24 小時修復；W 數值亦不能證明 H4 Wh 的 raw truth | 依欄名只讀所需欄位；凍結規則、mask、segments 與 boundary controls 由 Figure 6 v2 sidecars 保存；主輸入不平移、不交換日期，且正式 20 戶 VPP 結果強制配對 19 戶排除 H4 敏感度 |
| H14 檔尾截斷 | W/Wh 均於 2020-12-11 23:59 結束 | 其後日期並非零負載，而是無資料；依區間終點規則，12 月 11 日的完整日亦缺少終點 `2020-12-12 00:00` | 對 2020-12-11 完整日及其後涵蓋 H14 的日期設 `qualityPassed=false`，聚合值保持 `NaN`，不進入正式求解 |
| H16 長缺口插值 | W status 最長空白段為 2020-11-13 00:00 至 2020-11-18 12:57，共 7,978 分鐘；Wh 仍有已插值數值 | 若用於預測訓練，長段雙向線性插值會帶來 look-ahead leakage；也不能當成實際控制軌跡 | `short_gap_only` 與 `exclude_flagged_pv` 拒絕此類日期；`release_literal` 只可用於發布版行為比對 |
| 同時充電與放電 | Wh 發布版有 5,914 個分鐘列同時 `Charge(Wh)>0` 且 `Discharge(Wh)>0`；其中約 98.8% 落在 W availability/status 缺口所影響的區間 | 兩者在時間上高度重合，因此這些列不可直接解讀為真實控制動作；此結果不足以證明處理機制或每一列的成因 | measured Charge/Discharge 只作觀測稽核或 SB-SC-like benchmark；不限制反事實 MILP。模型內充放電另以 binary 互斥 |
| 能量平衡殘差 | 正確分鐘平衡為 `From grid + Production + Discharge - Consumption - Charge - Feed-in`；全戶只有 99.4185% 列的絕對殘差小於 0.5 Wh，最大 90 Wh | 發布數值不應被宣稱為 99.9% 的完美物理平衡 | 量測殘差保存為品質指標；MILP 自身的方程殘差則依數值容差驗證 |
| timezone 與 DST | household 與 weather timestamp 均沒有 timezone metadata；住戶 PV 的秋季太陽時間位移支持 household 近似當地 wall-clock，weather 並未顯示相同位移 | 這只是時基推論，不是上游時鐘設定的證明；兩類資料直接合併可能有一小時偏移 | household timestamp 以未附 timezone 的 Europe/Dublin wall-clock label 處理；發布版已是連續一分鐘網格，不再 localization 以免虛構 DST 重複／缺失分鐘 |
| PV 超長發電時間窗 | 以 Dingle 緯度 52.14°、aggregate PV 高於當日最大值 5% 的首末時間定義發電窗；窗長超過天文日長 0.5 h 的日期約 50 日，涉及約 16.1% 發布 PV 能量 | 冬季有明顯不合天文條件的長窗；可標記異常，但沒有上游紀錄不能指定是 timestamp、欄位串接、累加或其他單一原因 | `exclude_flagged_pv` 在短缺口門檻之上排除；同一日仍可用 literal 模式留存對照 |

## 5. 品質模式與驗收規則

[`src/load_storenet_day.m`](../src/load_storenet_day.m) 對每日回傳 physical-completeness、observation/interpolation mask、每戶 status 缺口比例、最長連續缺口、PV 時間窗與 `qualityReasons`。三種凍結模式為：

status 缺口比例以當日預期的 1,441 個 W 端點（`D 00:00` 至 `D+1 00:00`，含首尾）為分母，最長缺口依連續空白 status 端點數計算。PV 時間窗為 aggregate PV 超過當日最大值 5% 的第一至最後一分鐘區間（含首尾）。天文日長使用緯度 `52.14°`、日序 `n` 與 `δ=23.44°·sin(2π(284+n)/365)`，再以 `24/π·acos(-tan(φ)tan(δ))` 計算。

| 模式 | 驗收條件 | 允許的說法 |
|---|---|---|
| `release_literal` | Wh/W timestamp 物理完整、所需 Wh 值有限且無重複 timestamp；允許作者插值 status，但必須顯示旗標 | 使用公開發布值的 literal 對照；不等於 raw 或 ground truth |
| `short_gap_only` | 在 literal 條件上，每戶當日 raw W-status 最長連續缺口 `<=2` 分鐘，且缺失 status 比例 `<=0.005` | 符合凍結短缺口規則的發布版日 |
| `exclude_flagged_pv` | 在 `short_gap_only` 上，再要求 PV generation window `<= astronomical day length + 0.5 h` | 本專案主要科學分析模式 |

`strict` 只是相容別名，對應 `short_gap_only` 並在失敗時拋出錯誤；`report` 對應 `release_literal`。正式結果應保存 canonical mode，不以別名取代科學條件。

已固定的整合測試案例：

- 2020-08-24 通過既有 `short_gap_only`，但它受 Figure 6 v2 的 H4 規範 mask 影響；20 戶 VPP 結果仍須同設定配對排除 H4 的 19 戶敏感度，不能只憑舊品質 gate 升格為 v2；
- 2020-06-10 因 H19 有 3 分鐘連續 status 缺口而不通過；
- 2020-12-05 因 PV 發電窗超過當日天文日長加 0.5 h，不通過 `exclude_flagged_pv`。

`qualityPassed=true` 只表示該日通過當前契約的機器可驗證條件，不是對上游感測器正確性或物理真值的認證。

## 6. 資料在模型中的邊界

- `Consumption(Wh)` 與 `Production(Wh)` 是五種反事實最佳化策略的外生輸入。
- `Charge(Wh)`、`Discharge(Wh)`、`From grid(Wh)`、`Feed-in(Wh)` 與量測 `State of Charge(%)` 只用於資料稽核與觀測 benchmark，不得固定 MILP 的反事實決策。
- `State of Charge(%)` 取聚合區間終點值，不加總。
- 公開 `Production` 的 AC/DC 量測邊界無法由發布檔證明；論文意圖基準與 AC-available 敏感度必須分開報告。
- 公開資料有 10 個 PV 戶：H1、H2、H3、H4、H5、H7、H10、H11、H13、H17；2022 論文述及 9 戶 PV，但未公布身分。不得把公開版 10 戶結果冒充原始 9 戶結果。

## 7. 可復現性邊界

| 主張 | 狀態 | 原因 |
|---|---|---|
| 本地公開發布檔完整性 | **可完全驗證** | 官方 MD5 對應與本地 SHA-256 基線均為 46/46 |
| 發布版的時間、單位、status mask 與品質門檻 | **可復現** | 已編碼於 loader/audit 並有合成及真實資料測試 |
| Trivedi Figure 6 的 processed-release 資料集層級一致性 | **可驗證，H4 為唯一例外** | 雙比較口徑均為 Consumption 19/20、PV Production 9/10 通過；八份 v2 sidecar 保存 H4 的分類、邊界與負控制 |
| 作者 raw-to-processed pipeline | **不可完成** | raw battery-ID 與完整上游環境未發布 |
| 五種策略的論文意圖模型 | **可復現** | 方程解讀、單位修正、容差與 tie-break 均留痕 |
| 2020 公開資料策略比較 | **可復現** | 應稱 StoreNet 2020 independent replication |
| Bahloul Figure 5 / Table I 數值級精確重現 | **不可證實** | 典型日、原 9 PV 戶身分、ratio 實作與 solver 細節未公布 |
| Bahloul Figure 6 全年數值級重現 | **不可完成** | 方法論文使用 2019-07 至 2020-06，公開版缺 2019 下半年；不得與 Trivedi Figure 6 的 W/Wh 稽核混稱 |
| SB-SC 商業控制演算法 | **不可完成** | 演算法為未公開 IP；公開量測只能作觀測 benchmark |
| H4、DST 與 PV 異常的上游根因 | **無法由公開檔判定** | 缺原始 logger、timezone 與處理紀錄 |

## 8. 可重跑驗證入口

- 發布檔 SHA-256：[`data/RELEASE_MANIFEST.sha256`](../data/RELEASE_MANIFEST.sha256)
- 全發布資料稽核：[`src/audit_storenet_release.m`](../src/audit_storenet_release.m)
- 單日載入與品質契約：[`src/load_storenet_day.m`](../src/load_storenet_day.m)
- 資料層測試：[`tests/TestStoreNetData.m`](../tests/TestStoreNetData.m)
- 不可變契約：[`docs/REPRODUCTION_CONTRACT.md`](REPRODUCTION_CONTRACT.md)
- 方程與資料欄位追溯：[`docs/TRACEABILITY.md`](TRACEABILITY.md)

2026-09-01 使用 MATLAB 測試入口重跑資料層測試，結果 10/10 通過，包含 H4/H14/H16 發布問題、時間終點、缺值不補零、品質模式及上述三個真實日期驗收。

## 9. 報告用語原則

後續報告可使用「本地公開檔集合與官方發布清單一致」、「通過指定品質契約」或「2020 同源獨立復現」；不應只寫語意不明的「發布版完整」，也不應使用「原始量測已完全驗證」、「已精確重現原論文數值」、「異常成因已確定」或「hash 通過即代表物理真實」。
