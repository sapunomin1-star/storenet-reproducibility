# StoreNet 2020 獨立復現契約

契約 ID：`SR2020-IR-v2`

狀態：`SR2020-IR-v2 contract frozen`；資料論文稽核與 VPP v2 結果須分別通過本文件第 9 節才能稱為正式結果

目的：重建 Bahloul et al. (2022) 五種策略的「論文意圖模型」，並在可取得的 2020 StoreNet 公開資料上作可重跑的獨立驗證。

### 版本來源

- 資料論文 Figure 5--10 的 v1 稽核快照保留在 Git tag `data-paper-figures-5-10-v1`；其他 pre-v2 VPP／外部驗證批次則依各自 manifest 與 Git commit 保存，不能用這個 tag 概括。v2 不追溯改名、覆寫或重新解讀既有產物；其 manifest 在 `contractId`/`contractSha256` 欄位引入前建立，不事後補欄或 retrofit 冒充 v2。
- v2 納入 Trivedi et al. (2024) Figure 5--10 資料論文稽核，特別是 Figure 6 的全戶一致性結果與 H4 時間組裝缺陷；模型方程與既有固定參數未因這次稽核而暗改。
- 自 v2 起，每個正式結果 manifest 必須保存 `contractId="SR2020-IR-v2"` 與執行當下本文件的 `contractSha256`。缺欄、雜湊不符或只引用檔名者，均不得標成 v2 正式結果。

### 圖號用語

- `Trivedi Figure 5--10` 或 `資料論文 Figure 5--10`：指 2024 *Scientific Data* 資料論文。
- `Bahloul Figure 5/6` 或 `VPP 論文 Figure 5/6`：指 2022 *IEEE TSTE* 方法論文。
- 後續文件與圖說不得只寫「Figure 5」或「Figure 6」而不標作者／論文，以免把兩篇論文的驗收標的混在一起。

## 1. 不可變來源

- `data/raw` 雖沿用既有目錄名，語義固定為 **immutable processed Figshare release**。
- 程式不得改寫其中任何檔案；每次正式重跑前以 `data/RELEASE_MANIFEST.sha256` 驗證。
- Consumption、Production 是 counterfactual optimization 的外生輸入。
- measured Charge、Discharge、From grid、Feed-in、SoC 只用於資料稽核與 SB-SC-like observed benchmark，不進入五種最佳化策略的限制式。
- W 數值不進入 VPP 最佳化；W status 只作為 processed release 的 observation proxy。公開資料沒有逐筆 Wh 原始觀測／插值 mask，因此 `status=1` 不得被寫成 Wh 真值證明，H4 更必須遵守第 3 節的例外政策。

## 2. 時間與單位

- Wh 檔是每分鐘區間能量；timestamp 視為**區間終點**。日 D 使用 `(D 00:00, D+1 00:00]`。
- Trivedi Figure 6 的 released-data 稽核另以「相同 timestamp label」比較 `W` 與 `60*Wh`，這是檢驗兩個發布串流標籤是否一致，不會把 Wh 的區間終點改成區間起點，也不表示聚合時應將全體資料平移一分鐘或一小時。H4 的位移／日期轉置只作缺陷診斷，不套用成全資料修復規則。
- 聚合採加總 Wh；轉為 kWh 後，再除以 `dtHours` 得到 MILP 的 kW。禁止對 Wh 取平均並當功率。
- 30 分鐘實驗使用 48 個區間；月度結構性復現使用 1 小時、24 個區間。
- household 時間暫以未附 timezone 的 Europe/Dublin wall-clock label 處理。因發布版已抹平 DST，不進行會憑空創造重複／缺失 timestamp 的 timezone localization。
- 日間電價區間為 `[10:00, 22:00)`；其他區間為夜間。因 timestamp 是區間終點，費率由 `timestamp-dtHours` 的區間起點判定；例如 10:00 結束的區間仍為夜價，22:00 結束的區間仍為日價。
- 帳單：`sum(priceEURPerKWh .* importKW .* dtHours)`。

## 3. 品質模式

每個聚合日均回傳 observation/interpolation mask、各戶缺值比例與最大連續缺口。

- `release_literal`：使用發布 Wh 值，包括作者插值，但完整報告品質旗標。只用來比對作者發布版行為。
- `short_gap_only`：只允許每戶每個外生欄位連續缺口不超過 2 分鐘，且當日插值比例不超過 0.5%；超過即拒絕求解。
- `exclude_flagged_pv`：在 `short_gap_only` 上再排除超天文日長門檻的 PV 異常日。這是主要科學分析模式。

缺列、檔尾或讀取失敗不得轉為 0。依本契約的區間終點日界，涵蓋 H14 的完整日自 2020-12-11 起必須拒絕（該日缺少終點 `2020-12-12 00:00`）。

### 3.1 Trivedi Figure 6 的凍結判定

- 全戶表保留 `finite_release_same_timestamp` 與 `observed_both_endpoints` 兩種口徑。後者只在 W status `t-1` 與 `t` 都為 1 時納入 Wh(t)，但 status 仍只是 observation proxy。兩種口徑的 Consumption 均有 **19/20 戶**、有 PV Production 均有 **9/10 戶**通過，兩項唯一例外均為 H4。`observed_both_endpoints` 主 gate 同時檢查 correlation、P99 誤差與 rounding agreement，不以 Pearson `r` 單獨充當相等證明。
- H4 同 timestamp 全年結果為 Consumption `r=0.52194577`、Production `r=0.73217169`。擴大診斷顯示其異常含約 60 分鐘位移、部分 `DD/MM` 與 `MM/DD` 日期轉置，以及 `H4_W.csv` 額外 `Unnamed: 6` 欄的 314,742 個索引狀非空值。這些是發布檔的時間／組裝缺陷證據，不足以指定上游軟體或責任來源。
- H4 每日 lag search 只在至少 60 個有限配對點且兩側變異非零時回報最佳 offset；否則 lag、相關係數與 pass 欄都必須是 NA。日期／offset mapping 的 proxy-observed 比較必須同時要求 source W timestamp 與 mapped target Wh timestamp 所對應的 W status endpoints 有效。這些門檻只定義診斷資格，不是資料修復或 VPP 輸入篩選。
- H4 不是可用「2--8 月全壞、其他月份全好」概括的連續區間。凍結規則分類 366 個日期為：146 日 `unaffected_same0`、1 日 `unassessable_no_finite_W_pairs`（2020-02-29）、135 日 `same_date_plus60_core`、42 日 `actual_transpose_plus60_core`、7 日 `diagonal_identity_plus60_control` 與 35 日 `unresolved`。三個可對齊類別共 184 日只通過「目標日內 23 小時 core」檢查，不代表完整 24 小時邊界已解決；其中同日期 `+60 min` 的 Consumption 連續 24 小時檢查為 131/135 日通過，2020-05-31、06-30、07-31、08-31 失敗。日期轉置的 49 日則包含 42 個實際換日與 7 個月日相同的 identity controls。這些全是 diagnostic-only，不是核准的資料修復；正式 mask／segment 的唯一規範來源是 v2 八份 sidecar，不得在 loader 另寫手工月份規則。
- H4 Wh 欄的全年分鐘平衡殘差平均絕對值約 `0.0009306 Wh`、最大絕對值 `45.68 Wh`，只支持「Wh 各流量欄在發布版內部高度自洽」。它不能證明 Wh 是未受影響的原始真值，也不能單憑此結果斷言一定是 W 感測器損壞。
- 未公開 `90962_2020_{W,Wh}.csv` 仍是逐點重畫論文 H4 hexbin 的必要來源；缺檔不再阻擋資料集層級一致性判斷，但仍阻擋該張已刊圖的精確復現。

### 3.2 H4 的 VPP 採用政策

- 主分析使用**未做日期交換或時間平移的 released H4 Wh**，並將 H4 稱為內部自洽的 processed input，不稱為已確認 ground truth。
- W status 仍可依既有規則提供一般 observation proxy；落在上述 H4 規範 mask 的區段，不得把該 proxy 宣稱為可靠的 Wh 原始觀測證明。每個正式結果必須輸出是否受 H4 mask 影響的旗標。
- 每個 20 戶正式 VPP 情境均須以完全相同日期、參數、品質模式與求解設定，成對執行「排除 H4 的 19 戶敏感度」，並報告 bill、savings、peak、daytime peak、load range、import energy、curtailment 與 throughput 的差異。未完成這組敏感度，不得通過 v2 驗收。
- 不因粗略月份標籤刪除 H4，也不以診斷所得的位移／轉置資料取代主輸入；若研究要提出 H4 修復版，必須另立資料版本與獨立敏感度，不得覆寫 released-data 結果。

## 4. 固定系統參數

| 參數 | 基準值 | 來源／解讀 |
|---|---:|---|
| Houses | 20 主分析；19 戶排除 H4 敏感度 | 公開資料與 VPP 論文；v2 強制成對比較 |
| PV houses | 10；排除 H4 的 19 戶成對敏感度自然剩 9 個 PV 戶 | 不另挑一組未公布的 9 戶 cohort，也不冒充論文原 9 戶身分 |
| Battery capacity | 10 kWh/house | 論文附錄 |
| Charge/discharge power | 3.3 kW/house | 論文附錄 |
| Initial/minimum/terminal energy | 1 kWh | 10% of 10 kWh |
| Maximum energy | 9 kWh | 90% of 10 kWh |
| PV AC/DC and battery efficiencies | 0.95 each | 論文附錄 |
| Transfer loss | 0.07 | 將論文矛盾的 `7%/day` 明示解讀為無因次 loss；另跑 0 |
| Self-discharge | 0 | 論文未給 `P_SD`，不得自行代入 7% |
| Night/day tariff | 0.091 / 0.194 EUR/kWh | 論文附錄，day 10:00–22:00 |
| FIT | 0 | 論文設定 |
| Forecast | perfect foresight | 對應論文離線比較 |

公開 Production 的 AC/DC 量測邊界沒有證明。主復現依論文式 (1)–(3) 暫視為 DC available power；必須另跑「視為 AC available」的量測邊界敏感度，兩者不得混成同一結果。

## 5. 決策變數與共同限制

每戶、每時段明示：PV→home、PV→battery、PV→grid、grid→home、grid→battery、battery→home、battery→grid、PV curtailment、charge/discharge DC power、energy state、charge/discharge binary。共同限制為：

1. PV 分流加 curtailment等於 available PV，並套用相應 converter efficiency；
2. house load 由 grid、PV、battery 供應；
3. charge/discharge 與 AC/DC flow 一致；
4. `E(k)=E(k-1)+dt*(PchargeDC-PdischargeDC)`；
5. `1 <= E(k) <= 9 kWh`，開頭與結尾均為 1 kWh；
6. `PchargeDC <= 3.3*xCharge`、`PdischargeDC <= 3.3*xDischarge`、`xCharge+xDischarge <= 1`；
7. aggregate VPP import 每時段非負，zero FIT 下不允許社區淨輸出；
8. 所有流量非負。

模型限制殘差、SoC 終點與互斥均用數值容差判斷，不用浮點數精確等號當測試。

## 6. 六個求解情境

- `SH_BM`：禁止 PV／battery 對社區輸出，各戶 bill 的總和最小。
- `VPP_BM`：允許虛擬分享，社區總 bill 最小。
- `PS`：第一階段最小化 24 小時 aggregate import peak。
- `PSDT`：第一階段只最小化 10:00–22:00 peak。
- `LL`：第一階段最小化全日 `max(import)-min(import)`。
- `IMPROVED_PEAK_GUARD`：**完成五種基準後才啟用**；在 aggregate import 不超過預先宣告 cap 的條件下最小化 bill，用於避免 VPP-BM 產生新夜間尖峰。

PS、PSDT、LL 的後續階段固定為：

1. 鎖住第一階段主目標於 `optimum + lexicographicTolerance`；
2. 最小化帳單；
3. 鎖住帳單後最小化總充放電 throughput。

第三階段是確定性／退化處理，不宣稱是原論文公式。所有報告同時保存第一階段 optimum，避免次目標悄悄改變原研究問題。

SH-BM、VPP-BM 與 `IMPROVED_PEAK_GUARD` 也可能因平坦夜價或零價 PV curtailment 出現多個同 bill 解；它們先鎖住最低 bill，再以第二階段最小化 throughput。這同樣是可重現性 tie-break，不改變論文的主要經濟目標。

## 7. 基準與指標

無電池基準採各戶 PV 優先供本戶、無跨戶分享、無 FIT；同時另報 aggregate PV sharing 的純 PV 上界，兩者不得混用。

每次求解至少保存：`contractId`、`contractSha256`、solver/版本、exit flag、MIP gap、wall time、日期、資料模式、household cohort、H4 mask 影響旗標、PV 戶設定、AC/DC 假設、容量與功率 ratio、bill、savings、peak、daytime peak、load range、import energy、curtailment、battery throughput、最大平衡殘差、最大 SoC 違規、最大同時充放電量。20 戶主分析與 19 戶排除 H4 敏感度必須能由 manifest 中的共同 experiment/pair ID 對應，不得事後人工配對。

## 8. 實驗順序

1. 先完成 Trivedi 資料論文 Figure 5--10 稽核；其中 Figure 6 的八份 v2 sidecar 通過第 9 節 gate 後，才能接受資料採用判斷。
2. 合成 1--2 戶案例：單位、流向、SoC、互斥、sharing、terminal state。
3. 無電池／無 PV／相同價格等邊界案例。
4. 典型日：先用數位化 **Bahloul Figure 5** 的外生 load/PV 曲線定義距離函數，再排名日期；不得看最佳化 savings 後挑日。
5. 2020 可得月份的 1、2、15、16 日，以 1 小時作 **Bahloul Figure 6** 的結構性復現；2019 缺月明列 unavailable。
6. 對同一預先選定日作 capacity/power sensitivity；論文未公布網格，因此本專案網格只能標成重新定義的實驗。
7. 基準凍結後才跑 `IMPROVED_PEAK_GUARD`，與 VPP-BM 成對比較成本與尖峰。
8. Trivedi Figure 10 的 `Figure 10-S` 不在資料採用或 v2 基準的關鍵路徑；待建立配電網路約束改進時共用同一套 feeder、映射與潮流基礎建設。任何 `Figure 10-S` 必須標成獨立可行性／敏感度模擬，不得稱為已刊 Figure 10 復現。

PV 異常日先跑 literal，後跑品質排除版本；不可只替換不利日期。

## 9. 驗收門檻

- 資料 SHA-256：46/46 通過。
- Trivedi Figure 6 v2 gate：正式目錄必須同時包含 `figure6_all_house_metrics.csv`、`figure6_h4_daily_diagnostics.csv`、`figure6_h4_monthly_summary.csv`、`figure6_h4_alignment_summary.csv`、`figure6_h4_anomaly_segments.csv`、`figure6_h4_date_transpose_diagnostics.csv`、`figure6_h4_cross_house_controls.csv` 與 `figure6_h4_wh_balance.json`，且全數列入結果 manifest／checksum。缺任一檔不得宣告 data-paper audit 或資料採用 gate 完成。
- 聚合日：區間數、單位、時間端點與品質旗標測試通過；沒有任何隱式補零。
- 合成模型：每種策略 solver 成功，最大 equality residual `<=1e-7`，SoC/功率違規 `<=1e-7`，同時充放電 `<=1e-7 kW`。
- terminal SoC 在 `1e-7 kWh` 內回到目標。
- 詞典式第二／三階段不得讓第一階段主目標惡化超過固定容差。
- 每個正式 20 戶 VPP 結果均有同設定的 19 戶排除 H4 敏感度，並完整報告第 3.2 節指標差異；這是 v2 接受條件，不是選配附錄。
- 正式結果必須能由單一入口重跑，並輸出機器可讀 CSV/JSON 與圖。
- 正式 manifest 的 `contractId` 必須為 `SR2020-IR-v2`，`contractSha256` 必須與執行時本文件雜湊相同；v1 結果維持 v1 provenance，不得事後補欄冒充 v2。
- 與 Table I 數值不一致時，先歸因資料期間、PV 戶、典型日、量測邊界、xi、退化解或未公開 SB-SC；不得以挑日期／改參數硬配數值。
