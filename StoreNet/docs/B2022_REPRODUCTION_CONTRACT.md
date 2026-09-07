# Bahloul 2022 VPP 獨立復現契約

契約 ID：`B2022-IR-v1`

狀態：`normative model/experiment contract`；在本文件第 11 節的 pre-solve gates 全數通過前，正式公開資料求解維持 `HOLD`

資料契約：`SR2020-IR-v2`

資料契約固定 SHA-256：`9aaa09b56dfeaef27dba26289be445dff40492bf7a2340da5fe36d1a016ea3ca`

資料契約來源 commit：`f342259e06e86c2379de9ac51c6963805a41da39`

目的：依 Bahloul et al. (2022) 的 Equations (1)--(24)、Figures 5--7 與 Table I，在 StoreNet 2020 公開發布資料上執行可追溯的同源獨立復現、資料邊界敏感度與 H4 成對敏感度。本契約不宣稱取得論文原始 2019--2020 dashboard、原始 9-PV cohort、未公開 typical day 或 proprietary SB-SC controller。

## 1. 規範權威與 supersession

### 1.1 兩份契約的責任邊界

本文件是 post-audit Bahloul VPP 模型、實驗、指標、provenance 與驗收的唯一規範來源。它不改寫已凍結的 `REPRODUCTION_CONTRACT.md`，而是以固定 ID、hash 與 commit 納入其中的資料層規則。

| `SR2020-IR-v2` 條款 | `B2022-IR-v1` 的處置 |
|---|---|
| 第 1 節不可變來源 | 規範納入：processed release 不可改寫；Consumption/Production 是反事實模型外生輸入；其餘量測流量只作稽核或 observed SB-SC proxy |
| 第 2 節時間與單位 | 規範納入：Wh interval-end、日界、Wh 聚合、kW 換算、30/60 分鐘區間數、wall-clock 與 tariff interval-start 規則 |
| 第 3 節品質模式與 H4 判定 | 規範納入：三個 quality modes、不可隱式補零、H4 八份 sidecar、diagnostic-only 邊界與未修補 Wh 採用政策 |
| 第 4--8 節 VPP 參數、模型、策略、baseline、指標與實驗 | **由本文件完整 supersede**；Bahloul 正式新批次只讀本文件，不可同時套用舊第 7 節的單一 PV-self baseline |
| 第 9 節資料 checksum 與 Trivedi Figure 6 data gate | 規範納入；仍須 46/46 與八份 sidecar 完整通過 |
| 第 9 節 VPP 單一 `contractId/contractSha256`、模型驗收與 H4 pairing | **由本文件的雙 contract provenance、pre-solve 與 post-solve gates supersede** |

若兩份文件衝突：資料來源、timestamp、單位、quality mask 與 H4 diagnostic 的問題以 `SR2020-IR-v2` 為準；Bahloul 模型、baseline、實驗矩陣、結果 schema、manifest 與發布資格以 `B2022-IR-v1` 為準。

這項 supersession 不追溯變更 Trivedi Figures 5--10 的成果、manifest 或 contract hash，也不將任何 pre-v2 VPP 目錄 retrofit 成正式結果。

### 1.2 雙 contract hashes

每個 Bahloul 正式 run manifest 必須分別保存下列欄位，不得再以單一泛稱 `contractId` 或 `contractSha256` 代替：

| Manifest 欄位 | 必要值／計算規則 |
|---|---|
| `dataContractId` | `SR2020-IR-v2` |
| `dataContractSha256` | 執行時對 `docs/REPRODUCTION_CONTRACT.md` 精確 bytes 計算；必須等於本文件頁首固定值 |
| `dataContractGitCommit` | `f342259e06e86c2379de9ac51c6963805a41da39` |
| `modelContractId` | `B2022-IR-v1` |
| `modelContractSha256` | 執行時對本文件精確 bytes 計算，不把 hash 寫回本文件以避免 self-reference |
| `referenceManifestSha256` | 執行時對第 10.2 節 reference manifest 精確 bytes 計算 |

任一 ID 缺漏、hash 不符、以檔名代替內容 hash，或執行後才修改契約者，該 run 一律不具 `B2022-IR-v1` 資格。

本節落實 `A00_AUTHORITY`。

## 2. 可宣稱範圍、期間與資料採用

### 2.1 結果用語

- 所有 Ireland 本地結果只能稱為「StoreNet 公開資料上的同源獨立復現」或「重新定義實驗」。
- 不得稱 `exact replication`、作者原始 dashboard 復現、原始 9-PV cohort 復現或原始 SB-SC controller 復現。
- 每份報告固定揭露：公開資料期間、典型日並非作者日期、20/10 與論文 20/9 的 cohort 差異、SB-SC 只為 observed proxy、solver/version 未由論文公布。

### 2.2 期間

- 正式輸入只使用公開 2020 release，不補造 2019 資料。
- Bahloul Figure 6 的論文期間為 2019-07 至 2020-06；本地結果須將 `2020-01--06 overlap` 與 `2020-07--12 extrapolation` 分開表列。
- 2019-07--12 必須標成 `unavailable_from_public_release`，不得以 2020 同月替代而不標示。

### 2.3 時間、品質與 H4

- `timeEnd` 是 Wh interval-end；`intervalStart=timeEnd-dtHours`。日 D 為 `(D 00:00,D+1 00:00]`。
- 費率與 PSDT daytime mask 以 `intervalStart` 判定；daytime 固定為 `[10:00,22:00)`。
- 不做 timezone localization、DST 修補、全體平移、H4 日期交換或 H4 `+60 min` 修復。
- 正式科學主結果使用 `exclude_flagged_pv`；`release_literal` 與 `short_gap_only` 若執行，必須分開標記，不可替換不利結果。
- 每個 20 戶 model result 都必須有同日、同品質模式、同模型設定的 19 戶排除 H4 pair；每列保存 `pairId` 與 `h4MaskAffected`。
- H4 mask 與 affected 判定只能來自 `SR2020-IR-v2` 的規範 sidecars，不得在 runner 寫月份捷徑。

本節落實 `A01_SCOPE`、`A02_PERIOD`、`A04_TIME` 與 `A18_H4`。

## 3. Cohort 與固定參數

### 3.1 Cohort IDs

| `cohortId` | Houses | Batteries | Active PV | 用途 |
|---|---:|---:|---:|---|
| `H20_PV10` | 20 | 20 | 10 | 公開資料主情境 |
| `H19_EXCL_H4_PV9` | 19 | 19 | 9 | 排除 H4 的資料品質敏感度；不是論文原 20/20/9 cohort |

公開 release 的 PV 戶固定為 `H1,H2,H3,H4,H5,H7,H10,H11,H13,H17`。另外十組 leave-one-PV-out 保留 20 戶負載與 20 顆電池，只把其中一個 PV 戶的 model PV 設為 0；它們只量化論文未公布 9-PV 身分的不確定性，不得與 `H19_EXCL_H4_PV9` 混稱。

### 3.2 物理與經濟參數

| 參數 | 固定值 | 規範解讀 |
|---|---:|---|
| Battery capacity | 10 kWh/house | 每戶同比設定 |
| Charge DC lower/upper | 0 / 3.3 kW | inclusive bound |
| Discharge DC lower/upper | 0 / 3.3 kW | inclusive bound |
| Initial/minimum/terminal energy | 1 kWh | 10% of 10 kWh |
| Maximum energy | 9 kWh | 90% of 10 kWh |
| `etaPvAC` | 0.95 | PV DC/AC conversion |
| `etaPvDC` | 0.95 | PV DC/DC conversion |
| `etaBatteryCharge` | 0.95 | grid AC to battery-side DC |
| `etaBatteryDischarge` | 0.95 | battery-side DC to AC output |
| `xi` main/sensitivity | 0.07 / 0 | 0.07 視為無因次 sharing loss，不稱已知 feeder loss，也不依 timestep 縮放 |
| `P_SD` | 0 | 論文未公布；不得把 `xi` 當 self-discharge |
| Night/day tariff | 0.091 / 0.194 EUR/kWh | day 由 interval-start `[10:00,22:00)` 判定 |
| FIT | 0 EUR/kWh | aggregate external export 仍受禁止 |
| Forecast | perfect foresight | 離線比較使用 released measured inputs，不重建 forecast error |

本節落實 `A03_COHORT`、`A07_XI` 與 `A08_SELF_DISCHARGE`。

## 4. PV 量測邊界與共同 AC/DC 方程

令 `releasedProductionKW(i,t)` 為依資料契約聚合後的公開 Production，`PVGenDC(i,t)` 為模型 Eq. (1)--(3) 的 source-side DC available power。所有 model flow 均非負。

### 4.1 固定邊界情境

```text
DC_SOURCE:
    PVGenDC = releasedProductionKW

AC_METER_RECONSTRUCTED_DC:
    PVGenDC = releasedProductionKW / etaPvAC
```

兩個情境之後都使用完全相同的拓樸與 Eq. (3)；AC 敏感度只重建 source boundary，不得另改效率或 flow constraints：

```text
PVGenDC = pvToHomeAC / etaPvAC
        + pvToGridAC / etaPvAC
        + pvToBatteryDC / etaPvDC
        + pvCurtailDC
```

因此：

```text
pvAvailableAC = etaPvAC * PVGenDC
```

- `DC_SOURCE` 是主情境。
- `AC_METER_RECONSTRUCTED_DC` 是必要敏感度。
- 不得因某一邊界較接近 Figure 5 或 Table I 就事後改稱真值。
- 公開 Production 的真實 AC/DC measurement point 未揭露；兩個情境都必須標成專案假設。

本節落實 `A06_PV_BOUNDARY`。

## 5. Intended-model、修復與目標順序

### 5.1 共同關係

每戶、每時段至少包含以下八個非負欄位：`pvToHomeKW`、`pvToBatteryKW`、`pvToGridKW`、`pvCurtailKW`、`gridToHomeKW`、`gridToBatteryKW`、`batteryToHomeKW`、`batteryToGridKW`。

```text
chargePowerKW    = etaBatteryCharge * gridToBatteryKW + pvToBatteryKW
dischargePowerKW = (batteryToHomeKW + batteryToGridKW) / etaBatteryDischarge

gridToHomeKW + pvToHomeKW + batteryToHomeKW = loadKW

socKWh(t+1) = socKWh(t)
            + dtHours * (chargePowerKW - dischargePowerKW - P_SD)

aggregateImportKW = sum_i(gridToHomeKW + gridToBatteryKW
                    - (1-xi)*(pvToGridKW+batteryToGridKW))
aggregateImportKW >= 0
```

SoC、charge/discharge power 與 binary constraints 依第 3.2 節參數；`chargeOn+dischargeOn<=1`。論文所有 strict inequalities 一律改為 inclusive `<=`／`>=`，並以 `INTENT_REPAIR` 記錄。SoC 使用 kWh，修正論文 Eq. (9) 的 index/量綱問題。

Eq. (13) 只表示 aggregate energy accounting；它沒有 feeder node、相別、電壓、VUF、線路／變壓器限制或戶間逐筆配對。任何 aggregate peak 結果都不得解讀為配電網安全證明。

### 5.2 五個 paper strategies

| Strategy | 第一階段 | 後續固定 tie-break |
|---|---|---|
| `SH_BM` | 禁止 `pvToGridKW`、`batteryToGridKW`；以實際 grid import 乘 `dtHours` 最小化 aggregate bill | 鎖 bill 後最小 throughput |
| `VPP_BM` | 允許 sharing；最小化 aggregate bill | 鎖 bill 後最小 throughput |
| `PS` | 最小化全天 maximum aggregate import | 鎖 peak，最小 bill；再鎖 bill，最小 throughput |
| `PSDT` | 最小化 daytime maximum aggregate import | 鎖 daytime peak，最小 bill；再鎖 bill，最小 throughput |
| `LL` | 最小化 `max(import)-min(import)` | 鎖 spread，最小 bill；再鎖 bill，最小 throughput |

SH-BM 使用實際 grid import 並乘 `dtHours`，明示為修復論文 Eq. (16) 疑漏 `PV-to-home`，不是 literal equation。每個 lexicographic stage 均須保存 optimum、allowance、exit flag、relative MIP gap 與最終重算值。

`IMPROVED_PEAK_GUARD` 不屬 Figures 5--7／Table I baseline，只有在本契約基準結果接受後才能另立改進實驗；不得占用 A21 paper scenario matrix 的 strategy 欄。

本節落實 `A09_INEQUALITIES`、`A10_SOC`、`A11_TIE_BREAK`、`A12_SH_OBJECTIVE` 與 `A17_NETWORK_SCOPE`。

## 6. 雙 baseline 與指標

令 `L(i,t)=loadKW(i,t)`、`A(i,t)=etaPvAC*PVGenDC(i,t)`、`price(t)` 為 interval-start tariff。

### 6.1 `PaperLoadOnlyBaseline`

```text
PaperLoadOnlyImportKW(t) = sum_i L(i,t)
PaperLoadOnlyBillEUR = sum_t price(t) * PaperLoadOnlyImportKW(t) * dtHours
PaperSavingsEUR = PaperLoadOnlyBillEUR - StrategyBillEUR
PaperSavingsPercent = 100 * PaperSavingsEUR / PaperLoadOnlyBillEUR
OriginalLoadPeakKW = max_t PaperLoadOnlyImportKW(t)
OriginalLoadDaytimePeakKW = max_{t in day} PaperLoadOnlyImportKW(t)
```

這是 Bahloul paper-facing discrepancy 的唯一 saving baseline。Figure 6 monthly saving 由原文明示使用 load-only baseline；Figure 5、Figure 7 與 Table I 沿用此 baseline 是因 Table I nominal 與 Figure 5 一致而凍結的高可信專案推論。論文沒有給 peak-reduction percentage 公式；若本專案另算 peak reduction，欄名必須為 `ProjectPeakReductionPercent`，不得稱 paper-exact metric。

### 6.2 `PvSelfNoBatteryBaseline`

```text
PvSelfToHomeKW(i,t) = min(L(i,t), A(i,t))
PvSelfNoBatteryImportKW(t) = sum_i(L(i,t)-PvSelfToHomeKW(i,t))
PvSelfNoBatteryBillEUR = sum_t price(t) * PvSelfNoBatteryImportKW(t) * dtHours
EngineeringSavingsEUR = PvSelfNoBatteryBillEUR - StrategyBillEUR
EngineeringSavingsPercent = 100 * EngineeringSavingsEUR / PvSelfNoBatteryBillEUR
```

此 baseline 只回答 battery／aggregation 相對於 local PV self-consumption 的額外工程價值，亦可用於後續 Peak Guard cap；不得拿它與論文 Figure 5--7／Table I saving 百分比直接比較。

兩個 denominator 若為 0，百分比必須是 `NaN` 並輸出明確 flag，不得回傳 0 或 Inf。正式 schema 禁止未限定語義的 `BaselineBillEUR`、`BaselinePeakImportKW` 或 `SavingsPercent`；所有欄位必須帶 `Paper`、`PvSelf`、`Engineering` 或 `Observed` 前綴。

### 6.3 Observed SB-SC 的 baseline 邊界

Observed SB-SC 不套 `xi` 或 model AC/DC 情境。其 paper-facing saving 使用同一 `PaperLoadOnlyBaseline`；如報 engineering comparison，必須另名為 `ObservedReleasePvSelfNoBatteryBaseline`，以發布版 Consumption/Production 直接計算，不得與 model-boundary 的 `PvSelfNoBatteryBaseline` 共用欄名。

本節落實 `A05_BASELINES`。

## 7. Figure 5 曲線與 observed SB-SC

### 7.1 Model proxy 六-panel 中的四條曲線

每個 30 分鐘 interval 依下式產生，保留 `timeEnd` 與 `intervalStart`；圖的資料點以 `timeEnd` 對應該結束區間：

```text
LoadKW    = sum_i loadKW
PvKW      = etaPvAC * sum_i PVGenDC
GridKW    = aggregateImportKW                 # 正值為 import
BatteryKW = sum_i(dischargePowerKW-chargePowerKW)  # DC-side，正值為 discharge
```

圖例與 caption 必須標示：`structural proxy`、PV boundary ID、Battery 為 DC-side、正號為 discharge。論文沒有揭露 Figure 5 Battery/PV 的 AC/DC measurement point，因此不得把逐點差異解讀為 solver 錯誤或以 boundary 調參配圖。

### 7.2 Public-release same-system observed SB-SC proxy

SB-SC 不建模、不反推 proprietary controller。observed panel 由發布欄位直接聚合：

```text
ObservedLoadKW      = sum_i ConsumptionWh / (1000*dtHours)
ObservedPvKW        = sum_i ProductionWh  / (1000*dtHours)
ObservedGridImportKW= sum_i FromGridWh    / (1000*dtHours)
ObservedFeedInKW    = sum_i FeedInWh       / (1000*dtHours)
ObservedBatteryKW   = sum_i(DischargeWh-ChargeWh) / (1000*dtHours)
```

Figure 5 的 observed `Grid` 固定畫 `ObservedGridImportKW`；`ObservedFeedInKW` 另存為診斷欄。zero FIT 帳單只計 `ObservedGridImportKW`，不把 feed-in 當負成本。所有欄位須標成 release-side observation，不能稱原 paper date、原 9-PV cohort 或 exact trace。

### 7.3 Typical-day selection

- 先凍結 digitized Bahloul Figure 5 Load/PV reference、數位化規格、距離函數與 reference hash，再對品質合格候選日排名。
- selector 只能使用外生 Load/PV 曲線；不得讀取任何最佳化 bill、saving、peak 或 strategy output。
- 保存完整 ranking、tie rule、chosen date 與 reference hash。日期只稱 `proxy typical day`。

本節落實 `A06_PV_BOUNDARY`、`A13_TYPICAL_DAY` 與 `A14_SBSC`。

## 8. Figure 6、Figure 7 與 Table I

### 8.1 Figure 6 monthly

- 解析度 1 小時，每月候選日固定為 1、2、15、16 日；每個日 horizon 為 24 個 intervals。
- 主 monthly 值先對每個有效日獨立計算指標，再於 month/strategy/scenario/cohort 內取 arithmetic mean。
- 同時輸出 `ratioOfSummedCosts` 與 `peakOfMeanProfile`，只作 aggregation ambiguity sensitivity。
- 每月保存 candidate、accepted、rejected 日數與 rejection reasons；缺月不補零。
- `2020-01--06 overlap`、`2020-07--12 extrapolation` 與 `2019-07--12 unavailable` 分開輸出。
- Original Load 與 public-release observed SB-SC proxy 必須與五個 model strategies 同表；論文未表列的精確月 bar heights 不設 numeric pass threshold。

### 8.2 Figure 7 redefined sensitivity

- Capacity ratio 與 power ratio 都在求解前固定為 `0.2:0.1:1.0`，共 9×9。
- ratio 對每戶電池同比縮放；capacity 同時縮放 capacity、SoC min/max/initial/terminal 的 kWh 值，power 同時縮放 charge/discharge upper bounds。
- Figure 7 只跑第 9.2 節規定的 `DC_SOURCE/xi=0.07`、VPP-BM、20/19 pair。
- 輸出完整 surface 與 paper target-vs-local trend。它只能稱 `redefined sensitivity`；正文的 20%--100% 與圖軸 0--1 衝突，不推定未公開原始 grid。

### 8.3 Table I cases

五個 model strategies 都必須執行：

| `budgetCase` | Capacity ratio | Power ratio |
|---|---:|---:|
| `NOMINAL` | 1.0 | 1.0 |
| `POWER_20` | 1.0 | 0.2 |
| `CAPACITY_20` | 0.2 | 1.0 |

SB-SC 沒有反事實 capacity/power budget，只在 observed nominal/monthly annual 欄出現；reduced-budget 欄必須是 `not_applicable`，不得填 0。

本節落實 `A15_MONTHLY` 與 `A16_BUDGET_RATIO`。

## 9. 固定 scenario matrix

### 9.1 Stable keys

每列 modeled result 的唯一 key 至少包含：

```text
experimentId | dateOrPeriod | qualityMode | strategy | cohortId |
pvBoundaryId | xi | capacityRatio | powerRatio | pairId
```

`pairId` 必須在 20/19 pair 間相同，且不得包含 cohortId。所有 key 在求解前生成；缺列不得於報告階段靜默丟棄。

### 9.2 Typical／monthly／Table-I 的必要六格

五個 paper strategies 固定跑下列六格；它們是兩個 one-factor sensitivities，不是完整 2×2 interaction：

| Canonical scenario key | `pvBoundaryId` | `xi` | `cohortId` |
|---|---|---:|---|
| `DC_XI007_H20` | `DC_SOURCE` | 0.07 | `H20_PV10` |
| `DC_XI007_H19` | `DC_SOURCE` | 0.07 | `H19_EXCL_H4_PV9` |
| `AC_XI007_H20` | `AC_METER_RECONSTRUCTED_DC` | 0.07 | `H20_PV10` |
| `AC_XI007_H19` | `AC_METER_RECONSTRUCTED_DC` | 0.07 | `H19_EXCL_H4_PV9` |
| `DC_XI000_H20` | `DC_SOURCE` | 0 | `H20_PV10` |
| `DC_XI000_H19` | `DC_SOURCE` | 0 | `H19_EXCL_H4_PV9` |

`AC/xi=0` interaction 不屬接受條件；若另跑，必須標 `exploratory=true` 並與必要矩陣分表。

### 9.3 其他必要情境

- Figure 7：9×9、VPP-BM、`DC_SOURCE/xi=0.07` 的 `H20_PV10`／`H19_EXCL_H4_PV9` pair。
- Unknown 9-PV identity：十組 leave-one-PV-out，只跑 proxy typical-day、nominal VPP-BM、20 homes/20 batteries、`DC_SOURCE/xi=0.07`。
- Observed SB-SC：只跑 20/19 cohort 的 typical/monthly observation；`pvBoundaryId=OBSERVED_RELEASE_FIELDS`、`xi=NA`，不展開六格 model matrix。

本節落實 `A21_SCENARIO_MATRIX`。

## 10. Provenance、reference 與 durable evidence

### 10.1 Fail-closed preflight

正式入口在建立或命名最終 output directory 前，必須在暫存 staging 區完成：

1. 對 `data/RELEASE_MANIFEST.sha256` 執行逐檔 `shasum -c`，要求 46/46、保存每檔結果與 process exit status；
2. 驗證 `SR2020-IR-v2` 的八份 Figure 6 sidecars／manifest closure；
3. Git status 同時檢查 tracked modifications 與 untracked files，要求 clean；
4. 計算並驗證 data/model contract hashes 與 reference-manifest hash；
5. 記錄執行路徑實際使用的 provider、solver、MATLAB、Optimization Toolbox、tolerances 與時間；不得由固定字串冒充；
6. 執行並保存 machine-readable `review_preflight.json`，包含 analyzer file list、issue count、runtime versions、所有 gate 結果與 timestamp。

任一步驟失敗都不得建立／promote 正式 run directory。暫存失敗輸出只能標為 diagnostic，不得進入正式 results inventory。

### 10.2 Reference manifest

reference manifest 至少涵蓋：

- digitized Bahloul Figure 5 Load/PV profiles；
- digitization method、axis calibration、units、sample count 與 unavailable boundaries；
- Figure 5 六個 printed savings；
- Table I 全部 printed targets；
- 本地 PDF 的 source hash／page locator；
- 每個 reference artifact 的 SHA-256。

reference 只用於事前選日及事後 discrepancy；不得用於求解後調參或挑日。

### 10.3 Content-addressed inputs／solutions

每個 day/cohort/boundary/xi/strategy 保存獨立 `inputs_<sha256>.mat` 與 `solution_<sha256>.mat`；檔名 hash 必須等於檔案 bytes 的 SHA-256，scenario row 保存兩者 hash。

`inputs` 至少包含：

- `timeEnd`、`intervalStart`、`dtHours`；
- `houseIds`、load、released Production、model `PVGenDC` 與 `pvAvailableAC`；
- price、dayMask、完整 config；
- quality mode、observation/interpolation masks、cohort mask、H4 mask 與 `h4MaskAffected`；
- capacity/power ratios、PV boundary、xi、pair/scenario/reference IDs 與 hashes。

`solution` 至少包含：

- 第 5.1 節八個 flow arrays；
- `chargePowerKW`、`dischargePowerKW`、`aggregateImportKW`；
- `socKWh`、`chargeOn`、`dischargeOn`；
- 每個 stage 的 objective、solver objective、allowance、exit flag、relative MIP gap 與 message；
- solver/provider/runtime provenance。

另輸出 long-form metrics CSV、stages CSV、scenario inventory 與 pair differences。獨立 evaluator 必須只讀 inputs/solution/config 即可重算雙 bills/savings、peaks、energy、flows、curtailment、throughput、所有 equality residual、SoC/power/nonnegative violations 與 lexicographic preservation，不得呼叫 solver。

### 10.4 Result checksum closure

為避免 acceptance report 宣稱驗證一份又包含自己的 manifest 所造成的循環 hash，正式批次使用二層 closure：

1. `SCIENTIFIC_ARTIFACT_MANIFEST.sha256` 在 post-solve acceptance 前產生，涵蓋 run manifest、reference link、preflight、inputs、solutions、CSV、JSON、figures 與 logs，並排除自己；R7 直接驗證此層。
2. acceptance CSV/JSON 寫入後，再產生最終 `RESULT_MANIFEST.sha256`；它涵蓋第一層 manifest、acceptance reports 與所有其他正式 artifacts，只排除 `RESULT_MANIFEST.sha256` 自己。

兩層 checksum verification 都必須 100% 通過；run manifest 不得反向儲存未產生的最終 manifest hash。

本節落實 `A19_PROVENANCE` 與 `A22_DURABLE_SCHEMA`。

## 11. Pre-solve admission gates

建立本文件只完成 documentary authority；只有 P1--P9 全部 `PASS` 才可對正式公開資料求解。為完成測試而跑的小型 synthetic／fixture solver 不受此限制。

| Gate | 必要條件 |
|---|---|
| `P1_DOCUMENTARY_MAPPING` | Eqs. (1)--(24)、Appendix 參數、intent repairs、未知與 paper numeric anchors 均逐項登錄 |
| `P2_NORMATIVE_AUTHORITY` | 本文件 supersession 生效；data/model contract IDs 與兩個 runtime hashes 均可驗證 |
| `P3_BOUNDARY_SCHEMA` | 雙 baseline、兩個 PV boundary、Figure 5 curves、monthly aggregation、9×9 ratio grid、六格 keys 與 durable schema 均只有一個可執行定義 |
| `P4_DUAL_BASELINE_TESTS` | Paper load-only 與 model-boundary PV-self/no-battery 具獨立欄位、分母與 zero-denominator tests；禁止 generic savings 欄 |
| `P5_COHORT_SCENARIO_RUNNER` | 六格矩陣、20/19 pair、pair ID、H4 flag、Figure 7 pair、leave-one-PV 與 observed scopes 已由 fixture inventory 證明無缺列 |
| `P6_PROVENANCE_PREFLIGHT` | 46/46、八份 sidecars、clean Git including untracked、contract/reference hashes、actual solver/provider 與 `review_preflight.json` 全部 fail-closed |
| `P7_DURABLE_SCHEMA` | fixture inputs/solutions 完整保存，offline evaluator 不呼叫 solver即可重算全部 metrics 與 violations |
| `P8_FIXTURE_ACCEPTANCE` | 雙 baseline、有效電池調度、AC reconstruction、xi、30/60-min scaling、no-PV、same-price、zero denominator、H4 pair、monthly 與 Table-I orchestration tests 全通過 |
| `P9_HISTORICAL_PROTECTION` | 新 run ID、拒絕覆寫、未 retrofit pre-v2 artifacts；正式 output 尚未提前建立 |

Pre-solve report 必須保存每個 gate 的 `status`、machine evidence path/hash 與 failure reason。任一非 `PASS` 時，入口應在求解正式資料前停止。

## 12. Post-solve result acceptance gates

R1--R8 只在 pre-solve admission 通過並產生新成果後檢查；未執行時記 `NOT_RUN`，不能記成 `PASS`。

R1--R3 只適用於 modeled optimization cases；observed SB-SC 明示 `solverInvoked=false`，不得偽造 solver stage，但仍必須通過 R4 的固定 key／artifact 一對一完整性、R5 的獨立離線重算、R6--R8。

| Gate | 接受條件 |
|---|---|
| `R1_SOLVER_COMPLETION` | 每個 lexicographic stage `exitFlag>0` 且 finite relative MIP gap `<=1e-6` |
| `R2_PHYSICAL_FEASIBILITY` | equality residual、SoC initial/terminal/dynamics/bound、charge/discharge power、aggregate nonnegative 與 simultaneous charge/discharge violation 全部 `<=1e-7`，依欄位保存 kW/kWh 單位 |
| `R3_LEXICOGRAPHIC_PRESERVATION` | 最終解重算的每個已鎖 primary objective `<=stageOptimum + 1e-7*max(1,abs(stageOptimum))` |
| `R4_SCENARIO_COMPLETENESS` | Typical/monthly/Table-I 六格、Figure 7 20/19 surfaces、十組 leave-one-PV-out 與 observed SB-SC 20/19 無缺列；不可用失敗列靜默縮小分母 |
| `R5_OFFLINE_RECOMPUTATION` | offline evaluator 與報告的每個 finite scalar 差異 `<=1e-9*max(1,abs(value))`；不呼叫 solver |
| `R6_PAPER_FACING_OUTPUTS` | Figure 5 structural proxy、Figure 6 monthly、Figure 7 redefined surface、Table I target-vs-local 與 unavailable/proxy/boundary/cohort 標籤齊全 |
| `R7_ARTIFACT_CLOSURE` | 第 10.4 節第一層 scientific artifacts 全數入列，`SCIENTIFIC_ARTIFACT_MANIFEST.sha256` 驗證 100% 通過；最終 `RESULT_MANIFEST.sha256` 由 formal orchestrator 在 acceptance 後再驗證 100% |
| `R8_SCIENTIFIC_INTERPRETATION` | 不設任意接近 paper savings 的 pass threshold，不依結果挑日、增刪 grid 或調參；差異只按事前登錄因素解讀 |

只有 R1--R8 全部 `PASS`，該批次才可稱：

```text
B2022-IR-v1 accepted independent reproduction on the StoreNet public release
```

通過只代表本契約下的模型、資料與證據鏈完整，不代表原 paper dashboard 的 exact numeric replication，也不代表 feeder power-flow safety。

## 13. No-tuning 與報告義務

- Figure 5／Table I printed savings、Figure 6 reported ranges 與 Figure 7 qualitative optimum region只作事後 discrepancy anchors。
- 不以接近 36.41%、45.83/45.85%、15.30%、43.63%、15.39% 或 23.72% 作調參準則。
- 不以 paper target 選 typical day、PV boundary、xi、cohort、quality mode、solver tolerance 或 lexicographic order。
- 報告同時呈現不利差異、solver failures、unavailable months 與 rejected days；不得只保留接近論文的結果。
- 任何新增改進模型另立 contract/version，先完成本契約五策略 baseline；`IMPROVED_PEAK_GUARD`、feeder model 與 Figure 10-S 均不屬本契約的 paper-reproduction acceptance matrix。

本節落實 `A20_NO_TUNING`。

## 14. 假設 ID 覆蓋表

| ID | 本文件規範位置 |
|---|---|
| `A00_AUTHORITY` | 第 1 節：權威、supersession、雙 contract hashes |
| `A01_SCOPE` | 第 2.1 節：允許的結果用語與固定揭露 |
| `A02_PERIOD` | 第 2.2、8.1 節：2020、overlap/extrapolation/unavailable |
| `A03_COHORT` | 第 3.1、9.3 節：20/10、19/9、十組 leave-one-PV |
| `A04_TIME` | 第 2.3 節：interval-end、interval-start tariff/day mask |
| `A05_BASELINES` | 第 6 節：雙 baseline、唯一欄名與公式 |
| `A06_PV_BOUNDARY` | 第 4、7.1 節：DC/AC reconstruction 方程與 Figure 5 curves |
| `A07_XI` | 第 3.2、9.2 節：0.07/0 one-factor sensitivity |
| `A08_SELF_DISCHARGE` | 第 3.2、5.1 節：`P_SD=0` |
| `A09_INEQUALITIES` | 第 5.1 節：strict 改 inclusive |
| `A10_SOC` | 第 3.2、5.1 節：kWh state、1--9 kWh、terminal |
| `A11_TIE_BREAK` | 第 5.2、12 節：lexicographic order 與 preservation |
| `A12_SH_OBJECTIVE` | 第 5.2 節：禁止 sharing、實際 import、`dtHours` |
| `A13_TYPICAL_DAY` | 第 7.3、10.2 節：外生 selector 與 reference hash |
| `A14_SBSC` | 第 6.3、7.2、9.3 節：observed-only proxy |
| `A15_MONTHLY` | 第 8.1 節：daily arithmetic mean 與 ambiguity outputs |
| `A16_BUDGET_RATIO` | 第 8.2--8.3 節：per-house scaling、9×9 與 Table I cases |
| `A17_NETWORK_SCOPE` | 第 5.1、12 節：aggregate accounting 限制 |
| `A18_H4` | 第 2.3、9 節：20/19 pairs、mask、禁止修補 |
| `A19_PROVENANCE` | 第 1.2、10、11 節：hashes、fail-closed、closure |
| `A20_NO_TUNING` | 第 13 節：paper targets 只作事後 anchors |
| `A21_SCENARIO_MATRIX` | 第 9、12 節：六格、Figure 7、leave-one-PV、SB-SC |
| `A22_DURABLE_SCHEMA` | 第 10.3、11--12 節：content-addressed evidence 與 offline evaluator |
