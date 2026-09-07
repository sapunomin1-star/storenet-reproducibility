# Bahloul VPP 論文—程式—參數—可復現性重審

**審查日期：** 2026-09-01  
**審查基線：** Git commit `f342259`；checkpoint tag `pre-bahloul-v2-audit`  
**論文來源：** [Bahloul et al. (2022) 本地 PDF](<../../02_Role_of_Aggregator_in_Coordinating_Residential_Virtual_Power_Plant_in_StoreNet__A_Pilot_Project_Case_Study (1).pdf>)  
**審查範圍：** Bahloul et al. (2022) 的 Equations (1)--(24)、Figures 5--7、Table I，以及現有 StoreNet MATLAB 實作、測試、manifest 與歷史結果  
**本輪限制：** 只讀論文、程式、資料與既有成果；沒有修改求解器、沒有重新最佳化、沒有覆寫任何結果  
**准入結論：** `HOLD — NOT READY FOR FORMAL RE-SOLVE`

## 1. 結論先行

現有 MATLAB 核心可被接受為一個**論文意圖模型原型**：PV 分流、電池轉換、SoC、住戶平衡、VPP aggregate import 與五種主要目標，大致忠實地實作了論文可合理推斷的模型；對嚴格不等式、SoC 量綱與退化最優解所做的修正也有科學理由。

但目前不能直接把它重新求解並稱為正式復現。最重要的問題不是 MILP 主體，而是：

1. 現行 `SavingsPercent` 使用錯誤的比較基準；
2. Figure 5、Figure 6、Figure 7／Table I 的實驗與輸出尚未完整對齊論文；
3. 公開的 measured SB-SC 尚未納入正式觀察基準；
4. `SR2020-IR-v2` 規定的 20／19 戶配對、H4 旗標、AC/DC 與 `xi` 敏感度尚未落到 runner；
5. 現有成果沒有保存足夠的逐戶決策變數與 checksum closure，無法只靠 artifacts 獨立重算所有可行性主張。

因此，這輪審查的決策是：**先修正實驗契約與證據鏈，再求解；不得沿用現有 pipeline 直接產生新的正式數值。**

### 判定標記

| 標記 | 意義 |
|---|---|
| `MATCH` | 論文與程式在可觀察結構上相符 |
| `EQUIVALENT` | 寫法不同，但由其他限制與非負域可推得同一可行集合 |
| `INTENT_REPAIR` | 論文字面有矛盾、量綱錯誤或不可實作處；程式採明示修復 |
| `ASSUMPTION` | 論文未公開或語意歧義；必須由專案凍結並做敏感度 |
| `MISSING` | runner、成果欄位、比較列或測試尚未具備 |
| `BLOCKER` | 在正式重新求解前必須處理 |

## 2. 已確認的重大差異：savings baseline

論文 Section III **直接明示 Figure 6 的 monthly saving** 相對於 initial/original load demand，且沒有 PV 與 ES contribution。Figure 6 的 peak 圖另列 Original Load，但原文沒有給 peak-reduction 百分比公式。本專案把同一 load-only saving 定義延伸至 Figure 5、Figure 7 與 Table I；這是高可信但仍屬明示推論的統一口徑，依據是 Table I nominal 與 Figure 5 的數字幾乎完全一致。現行 `evaluate_storenet.m:35--38,82--89` 則先扣除每戶可直接自用的 PV，使用「PV self-consumption、無電池、無 VPP sharing」作基準。

這不改變五種策略已算出的 dispatch，卻會系統性改變 Figure 5、Figure 6、Figure 7 與 Table I 的 savings。以既有 2020-08-24 成果做**純重算、不重新求解**：

| 策略 | 現行 PV-self baseline (%) | 論文 load-only baseline (%) |
|---|---:|---:|
| SH-BM | 32.158 | 38.400 |
| VPP-BM | 41.262 | 46.666 |
| PS | 12.713 | 20.744 |
| PSDT | 41.262 | 46.666 |
| LL | 12.713 | 20.744 |

同一日的基準電費由 EUR 33.297141（PV-self）變成 EUR 36.671172（load-only）。這項差異已由既有 `profiles.csv` 與 interval-start tariff 重新計算確認。

後續固定採用**雙基準、不同欄名**：

- `PaperLoadOnlyBaseline`：原始 aggregate load，不扣 PV、不含電池；只用它計算與 Bahloul Figures 5--7／Table I 對照的 savings 與 Original Load peak。
- `PvSelfNoBatteryBaseline`：允許每戶 PV 直接自用，但無電池、無分享；保留作「電池／聚合額外價值」與 Peak Guard cap 的工程指標。

不得再用單一 `BaselineBillEUR` 或 `SavingsPercent` 混合兩個問題。

## 3. Equations (1)--(24) 完整對照

論文頁碼以 PDF 頁面計：Eqs. (1)--(3) 在 PDF 4--5，Eqs. (4)--(15) 在 PDF 5，Eqs. (16)--(24) 在 PDF 6。程式行號以審查基線 `f342259` 為準。

| Eq. | 論文定義 | 程式位置／寫法 | 參數或自主解讀 | 判定與可復現性 |
|---:|---|---|---|---|
| 1 | 可用 PV = 採用 PV + 未採用 PV | `solve_storenet.m:33--40,66--68`；所有路徑加 `pvCurtailKW` 等於 `pvKW` | `pvKW` 視為可用源端功率 | `MATCH`；顯式 curtailment 使分配閉合 |
| 2 | 採用 PV 不超過可用 PV | 同一 PV equality，加上所有變數非負 | Eq. 2 在 Eq. 1 與非負域下冗餘 | `EQUIVALENT`；不需再加重複限制 |
| 3 | 採用 PV 分至 home／grid／battery，含 PV 的 DC/AC 與 DC/DC 轉換效率 | `solve_storenet.m:66--68` | 主情境把公開 `Production` 視為 DC-available；必做 AC-available 敏感度 | 結構 `MATCH`；量測邊界為 `ASSUMPTION/BLOCKER` |
| 4 | battery-side charging = AC grid charge 經效率 + DC PV charge | `solve_storenet.m:57` | `etaBatteryCharge=0.95`；PV-to-battery 依 `etaPvDC` 在 Eq. 3 換算 | `MATCH` |
| 5 | battery-side discharge = AC home/grid output 除放電效率 | `solve_storenet.m:58--59` | `etaBatteryDischarge=0.95` | `MATCH` |
| 6 | charging min/max 與 binary | `solve_storenet.m:52--53,79--80` | 論文 min=0，嚴格 `<` 會導致 binary=0 時不可行；改成 `<=` | `INTENT_REPAIR`；必要且可驗證 |
| 7 | discharging min/max 與 binary | `solve_storenet.m:54--55,81--82` | 同 Eq. 6 | `INTENT_REPAIR` |
| 8 | 不得同時充放電 | `solve_storenet.m:83` | binary `chargeOn + dischargeOn <= 1` | `MATCH` |
| 9 | 跨期 SoC 動態，含 self-discharge | `solve_storenet.m:49--51,71--74` | 改用 kWh state；修正論文累加索引；未公布 `P_SD` 固定為 0 | 量綱 `INTENT_REPAIR`；`P_SD=0` 為 `ASSUMPTION`，manifest 尚未顯式存欄 |
| 10 | SoC 下／上界 | `solve_storenet.m:49--51` | 10 kWh 電池的 10%--90%，即 1--9 kWh；嚴格界改 inclusive | `INTENT_REPAIR`；否則與 Eq. 15 的 10% terminal 衝突 |
| 11 | 本戶 load = grid + PV + battery 供應 | `solve_storenet.m:69--70` | 三個來源均非負 | `MATCH` |
| 12 | PV-to-home + battery-to-home 不超過 load | 由 `homeBalance` 與非負 `gridToHomeKW` 推得 | 不允許本戶反向過供 | `EQUIVALENT` |
| 13 | aggregate VPP import，分享輸出乘 `(1-xi)` | `solve_storenet.m:60--61,232--234` | `xi=0.07` 解讀為無因次 transfer-loss fraction；另做 `xi=0` | 代數 `MATCH`；`xi` 語意為 `ASSUMPTION/BLOCKER`；模型只有 aggregate accounting，沒有節點配對／潮流 |
| 14 | aggregate import 不得為負 | `solve_storenet.m:84` | FIT=0、VPP 不對外淨輸出 | `MATCH` |
| 15 | horizon 間 terminal SoC 相等；Appendix 指定 10% | `solve_storenet.m:71--78` | initial／terminal 均 1 kWh | `MATCH`；採 inclusive bound 解決論文字面衝突 |
| 16 | SH-BM：各戶獨立最小電費 | `solve_storenet.m:86--88,98--114`；禁止 PV／battery 分享後最小 aggregate bill | 聯合問題因零分享可分離；實際 grid import objective 補回論文疑漏的 PV-to-home；成本乘 `dt` | `INTENT_REPAIR`；主目標可接受，另加 throughput tie-break |
| 17 | VPP-BM：共享 DER 後最小 aggregate bill | `solve_storenet.m:60--63,98--114` | 成本補乘 `dt`；先 bill、後 throughput | 主目標 `MATCH`；第二階段是 `ASSUMPTION` |
| 18 | PS：最小全天 maximum import | `solve_storenet.m:117--123` | 第一階段只最小 peak | `MATCH` |
| 19 | 各 interval import 不超過 maximum | `solve_storenet.m:118--126` | 嚴格不等式改 inclusive；鎖住 peak 後依序最小 bill、throughput | 限制 `INTENT_REPAIR`；tie-break 為 `ASSUMPTION` |
| 20 | PSDT：最小日間 maximum import | `solve_storenet.m:144--150` | 日間固定為 interval start 落在 `[10:00,22:00)` | 第一階段 `MATCH`；邊界為凍結解讀 |
| 21 | 日間 interval 不超過 daytime maximum | `solve_storenet.m:145--153` | 嚴格不等式改 inclusive | `INTENT_REPAIR` |
| 22 | 以 daytime indicator 選取日間 import | `solve_storenet.m:26--30,316--325` | Wh 標籤為 interval end，費率／日間判定使用 interval start | `EQUIVALENT`；時間契約已明示 |
| 23 | LL：最小全天 max(import)-min(import) | `solve_storenet.m:171--180` | 第一階段最小 spread | `MATCH` |
| 24 | minimum 不高於所有 interval import | `solve_storenet.m:172--190` | 嚴格不等式改 inclusive；之後最小 bill、throughput | 限制 `INTENT_REPAIR`；tie-break 為 `ASSUMPTION` |

### 方程層整體判定

- **通過：** 核心 intended-model 的數學結構可保留。
- **不得冒稱逐字復現：** Eq. 6、7、9、10、16、19、21、24 必須修復論文字面問題；PS、PSDT、LL 的次要目標亦為本專案選擇。
- **仍需敏感度：** `Production` 的 AC/DC 邊界、`xi=0.07/0`。
- **物理邊界：** Eq. 13 只表達 aggregate energy accounting，不包含 feeder node、相別、線路容量、電壓或戶間逐筆配對；因此通過 Eq. 13 不等於配電網安全。

## 4. 參數與資料口徑對照

| 項目 | 論文 | 現有程式 | 審查決定 |
|---|---|---|---|
| 住戶／電池 | 20 戶、20 顆 | `storenet_config.m:43--44` 固定 20 戶 | 主分析 20 戶；H4 敏感度為 19 戶，不能冒稱論文 cohort |
| PV 戶 | 9 戶、每戶 2.4 kW；身份未公開 | `storenet_config.m:45--47` 為公開版 10 個 PV 戶 | 20戶／10PV 是公開資料主情境；19戶／9PV 僅是排除 H4；另做 10 組保留 20 戶的 leave-one-PV-out，評估未知 9-PV 身分 |
| 電池容量／功率 | 10 kWh／3.3 kW | `storenet_config.m:73--74` | `MATCH` |
| 充電／放電功率界 | 兩者均為 0--3.3 kW | `solve_storenet.m:79--82` | inclusive bounds；分別作用於 battery-side charge／discharge power |
| 四個效率 | 全部 0.95 | `storenet_config.m:68--71` | `MATCH` |
| SoC | initial/min/terminal 10%，max 90% | `storenet_config.m:75--78` | 以 1--9 kWh state 實作 |
| Self-discharge | 公式有符號，無數值 | 程式未列該項 | 固定 0，並在 config／manifest 顯式保存 |
| `xi` | Appendix 寫 `7%/day`；Eq. 13 像無因次 grid-loss coefficient | `transferLossFraction=0.07` | 主情境視為無因次 0.07；必要敏感度 `xi=0`；不得稱為已知線路損失或每日自放電 |
| 電價 | night 0.091、day 0.194 EUR/kWh | `storenet_config.m:79--80` | `MATCH` |
| 日間 | 10:00--22:00 | `storenet_config.m:82--83` | interval start 位於 `[10:00,22:00)` |
| FIT／外部輸出 | FIT=0；aggregate export 禁止 | `feedInPrice=0`、Eq. 14 | `MATCH`；目前 `feedInPrice` 不直接進 objective |
| 時間標籤 | 未公開 | loader 採 Wh interval-end；日 D 為 `(D 00:00,D+1 00:00]` | 沿用 `SR2020-IR-v2`；不做 timezone localization 或全體平移 |
| Figure 5 解析度 | 30 min | `run_typical_day.m:9--13` | `MATCH` |
| Figure 6 解析度／抽樣 | 1 h；每月 1、2、15、16 日 | `run_monthly.m:42--45,140--143` | 抽樣日規則與解析度 `MATCH`；資料期間只有 2020-01--06 與論文重疊，彙總輸出亦尚未對齊 |
| Figure 7 解析度 | 30 min | `run_sensitivity.m:9--15` | `MATCH` |
| 研究期間 | 2019-07 至 2020-06 | 公開 release 只有 2020 | 只宣告同源獨立復現；2020-01--06 為重疊窗口，其餘 2020 月份為外推檢查，不補造 2019 資料 |
| Typical day | 日期未公開 | 2020-08-24 外生曲線距離 proxy | 保留 proxy 標籤；不得稱作者日期 |
| Solver／容差 | 未公開 | `intlinprog`；gap `1e-6`、constraint `1e-8`、lexicographic `1e-7` | 專案假設；正式 manifest 必須記錄實際 provider／solver，不能硬編宣稱 |
| Capacity／power ratio | 精確分配規則與網格未公開 | 每戶容量與功率同比縮放 | 保留此定義；必須標成 redefined sensitivity |
| Savings baseline | Figure 6 monthly saving 明示為 original load、無 PV、無 ES；Figure 5／7／Table I 未逐項重述 | 目前是 PV self-use、無 battery | `BLOCKER`；統一採雙基準並分欄，且將跨圖沿用標成專案推論 |
| 月平均 | 論文未說明運算順序 | 目前跨所有成功日 pooled mean | 每月先算每日指標再算 arithmetic mean；另報 ratio-of-summed-costs 與 peak-of-mean-profile 作歧義敏感度 |

## 5. Figures 5--7 與 Table I 的實際覆蓋

| 論文項目 | 論文驗收資訊 | 現有實作／成果 | 判定 | 正式重跑前要補 |
|---|---|---|---|---|
| Figure 5 | Typical day、30 min；SH 36.41%、VPP 45.83%、PS 15.30%、PSDT 43.63%、LL 15.39%、SB-SC 23.72% | `run_typical_day` 持久化 aggregate Load、PV、PV-self/no-battery import 與各策略 aggregate import；完整 solution 只在函式回傳記憶體中，沒有 durable flows／SoC；也沒有 SB-SC，圖不是論文六 panel | `MISSING/BLOCKER` | 雙 baseline；加入 public-release same-system observed SB-SC proxy；依 A06 的固定邊界保存／畫出 Load、PV、Grid、Battery；逐點曲線只能標結構性 proxy |
| Figure 6 | 2019-07--2020-06；每月四日、1 h；monthly saving 與 peak | `run_monthly` 的抽樣規則與解析度相符，但只跑 2020；每日 rows 可由既有 `monthly_metrics.csv` 再分月，正式 `summarizeMonthly` 卻把所有日合成每策略一列，且沒有 SB-SC／Original Load | `MISSING/BLOCKER` | 產生正式 12-month summary／圖、有效日數、缺月旗標、SB-SC、Original Load；Jan--Jun overlap 與 Jul--Dec 2020 外推分開解讀 |
| Figure 7 | VPP-BM capacity/power sensitivity；正文特別提到 capacity 0.7--0.8、power 0.2--0.3 | 現有 5×5 grid 為 `[.2,.4,.6,.8,1]`，缺 .3/.7；只有 heatmap；本地最大在 1/1 | `PARTIAL` | 求解前固定 capacity、power 都為 `0.2:0.1:1.0` 的 9×9 grid；輸出 surface 與 target-vs-local trend；不以調參追逐 46% |
| Table I reduced budgets | 五策略在 20% power、20% capacity、nominal 下的 savings | 目前 reduced-budget runner 只跑 VPP-BM | `MISSING/BLOCKER` | SH-BM、VPP-BM、PS、PSDT、LL 全部三情境；SB-SC 只在可觀察 nominal／annual 欄 |
| SB-SC | 商業控制器不可取得；論文使用現場輸出 | loader 已讀 Charge、Discharge、From grid、Feed-in、SoC，但 runners 未使用 | `OBSERVATIONAL_ONLY/MISSING` | 從公開量測計算 public-release same-system observed SB-SC proxy 的 bill、saving、peak 與曲線；不得宣稱是原圖 trace 或重建控制演算法 |

論文 Figure 5 的 VPP-BM 標示為 45.83%，Table I nominal 為 45.85%；這 0.02 percentage-point 是原文內部差異，不應由本專案挑參數消除。

### 論文數值錨點

| 情境 | SH-BM | VPP-BM | PS | PSDT | LL | SB-SC |
|---|---:|---:|---:|---:|---:|---:|
| Table I：20% power | 26.76 | 43.42 | 15.30 | 24.17 | 15.25 | — |
| Table I：20% capacity | 16.18 | 26.45 | 15.33 | 18.04 | 14.86 | — |
| Table I：nominal | 36.41 | 45.85 | 15.30 | 43.63 | 15.39 | 23.72 |
| Table I：annual average | 31.89 | 39.358 | 13.16 | 36.90 | 0.54 | 17.59 |

Figure 6 的精確 12 個月 bar heights 與 peak values 沒有表列，只能估讀，不能設成 exact numeric acceptance threshold。可正式檢查的論文趨勢為：saving 大致 `VPP-BM > PSDT > SH-BM > SB-SC > PS > LL`；SB-SC 約 16%--19%，VPP-BM 約 37%--42%，且 PS／LL 的 peak 最低。Figure 7 可檢查的主要主張是 capacity budget 對 saving 的影響高於 power budget，以及正文所述約 capacity 0.7--0.8、power 0.2--0.3 的區域。正文稱範圍為 20%--100%，圖軸卻顯示 0--1；精確求解 grid 與 step 都未公開，所以本專案事前固定的 `0.2:0.1:1.0` 仍只能稱 redefined sensitivity，不能稱 paper-exact surface。

### 不重求解即可保留的歷史證據

現有 VPP-BM sensitivity CSV 已保存 optimized bill。只把同一 dispatch 改用 `PaperLoadOnlyBaseline` 分母，可得到：

| VPP-BM 情境 | pre-v2 歷史重算 (%) | 論文 Table I (%) | 差值（百分點） |
|---|---:|---:|---:|
| 20% power | 43.0625 | 43.42 | -0.3575 |
| 20% capacity | 25.4596 | 26.45 | -0.9904 |
| nominal | 46.6664 | 45.85 | +0.8164 |

這三點顯示現有 intended-model 與論文量級相近，是值得保留的 pre-v2 證據；但它們仍使用 proxy day、20/10 cohort、單一 DC/`xi=.07` 假設與 v1 manifest，所以不能升格成正式結果，也不能據此反向挑選假設。

## 6. 程式品質、測試與 artifacts 證據

### 已通過

- 本輪互動式 MATLAB Code Analyzer 只讀檢查涵蓋 15 個檔案：`storenet_config.m`、`load_storenet_day.m`、`solve_storenet.m`、`evaluate_storenet.m`、`select_typical_day.m`、`run_typical_day.m`、`run_monthly.m`、`run_sensitivity.m`、`write_run_manifest.m`、`audit_storenet_release.m`、`render_monthly_comparison.m`、`TestStoreNetData.m`、`TestStoreNetModel.m`、`TestStoreNetExperiments.m`、`TestStoreNetReporting.m`；均為 **0 issue**。這是本輪 review 證據，尚未取代正式 CI log。
- 現有測試已涵蓋 PV／home／battery balance、SoC dynamics、terminal state、充放電互斥、sharing、tariff 邊界、五策略基本 orchestration 與 lexicographic primary objective。
- 本輪 live runtime 的只讀查核為 MATLAB R2026b prerelease Update 1 與 Optimization Toolbox 26.2；正式重跑仍須把當次實際版本寫入 manifest。
- runner 拒絕覆寫非空 run directory；歷史 results 與 data-paper v2 成果本輪均未變動。

上述 Code Analyzer 與 live-runtime 結果目前只存在於本輪審查紀錄；進入正式 pre-solve gate 時，必須另存 machine-readable `review_preflight.json`（檔案清單、analyzer issue count、MATLAB／toolbox 版本與執行時間）並納入成果 checksum。

### 尚未通過

- `TestStoreNetModel.m:54` 的五策略共同測試把 battery power 設為 0，沒有驗證 PS／PSDT／LL 的實際電池調度。
- 沒有 load-only paper baseline、雙 baseline 命名與分母測試。
- 沒有 Figure 6 的 12-month grouping、樣本數、SB-SC／Original Load series 測試。
- 沒有 Table I 五策略 reduced-budget、20／19 H4 pair、AC/DC、`xi=0` 測試。
- 沒有直接 assert `socBoundViolationKWh`、charge/discharge power violation、aggregate nonnegative violation，以及最終解對每個 lexicographic primary optimum 的保持程度。
- 沒有 no-PV、same-price、zero-denominator、30/60-min `dt` scaling、H4-mask flag 推導的邊界測試。
- `write_run_manifest.m:86--95` 固定寫 solver=`intlinprog`，但 runners 可注入任意 solver／data provider；mock run 可能留下錯誤 provenance。
- `write_run_manifest.m:98--110` 只 hash `RELEASE_MANIFEST.sha256` 清單本身，沒有在執行時驗證清單中的 46 個資料檔為 46/46 通過。
- Git dirty 檢查排除 untracked files；目前 Bahloul Ireland 的 typical／monthly／sensitivity 成果沒有 `RESULT_MANIFEST.sha256`。兩個 Ausgrid 目錄雖已有 result checksum，仍是 pre-v2 且沒有逐戶 solution evidence。
- 代表日成果沒有持久化逐戶 flows、SoC、binaries、每個 lexicographic stage 的完整記錄與 MIP gaps；也沒有把 `timeEnd`、`intervalStart`、`dt`、`houseIds`、`loadKW`、原始與模型化 `pvKW`、price/day mask、完整 config、quality/cohort/H4 mask 與 reference hash 封裝成 content-addressed input。現有 residual／SoC／paper-baseline 主張無法只靠成果檔完整獨立重算。
- Monthly／sensitivity CSV 缺少部分 curtailment、shared export、SoC bound／power violation、H4 mask、pair ID、contract／reference hash 等必要欄位。

因此，名稱含 `_v2` 的既有 VPP run 仍然只是 **pre-`SR2020-IR-v2` 歷史結果**，不能因目錄名稱升格為正式 v2 證據。

2020-08-24 在 H4 v2 sidecar 中屬 `same_date_plus60_core` affected day；所以既有 typical-day 與 sensitivity artifacts 尤其不能省略 20／19 paired rerun。

### 既有成果 provenance inventory

| 成果群組 | Manifest／commit | Result checksum | 證據定位 |
|---|---|---|---|
| `typical_day_selection_2020` | v1／`24e7c10aae1c` | 無 | 代表日 ranking 歷史證據；reference hash 不完整 |
| `baseline_typical_20200824`、`_v2` | v1／`d6d2f507e02f`、`173d8147b2ca` | 無 | proxy-day 歷史結果；`_v2` 只是名稱，不是契約 v2 |
| `sensitivity_20200824_vppbm` | v1／`173d8147b2ca` | 無 | VPP-BM 5×5 歷史 grid；可純重算 load-only savings |
| `monthly_2020_release_literal_q1/q2` | v1／`f89a4d4627bb` | 無 | 分段日列；不是完整正式年度成果 |
| `monthly_2020_*_bounded60` | v1／`24e7c10aae1c` | 無 | 完整日列／pooled summary 歷史證據；缺新 baseline 與正式分月輸出 |
| `monthly_comparison_2020`、`_v2` | v1／`ffc13152a221`、`d14e64dee9df` | 無 | 比較品質模式，不是 Bahloul Figure 6 |
| 兩個 Ausgrid external runs | v1／`f602e77c3972`、`7bf3bf51d8ce` | 有 | 可保留的外部歷史證據，但不具 Bahloul v2 solution closure |
| `monthly_2020_release_literal`、`monthly_2020_release_literal_q3` | 無；空目錄 | 無 | 非證據，禁止列入完成數 |

### 早期 Python prototype 的處置

- `quicklook.py:10--20` 其實使用正確的論文 load-only baseline，並曾以 measured `From grid` 計算 SB-SC-like 指標；這證明正確概念在早期探索中出現過，但後來沒有進入正式 MATLAB evaluator／runner。
- `prep_30min.py:7,14,20` 以 interval-start 年網格重建資料，對 energy 使用 `resample().sum().reindex(...).fillna(0)`，對 SoC 使用 `ffill().fillna(0)`。缺資料會被靜默改成零，且時間慣例與 `SR2020-IR-v2` 的 interval-end 契約不同。
- 因此 `prep_30min.py`、`quicklook.py` 與其 `.npz` 只能作 exploratory prototype；正式 VPP v2 不得讀取該 `.npz`，也不得用它的數值通過驗收。

## 7. 自主假設台帳（後續直接採用）

以下決定不再等待老師先確認；它們必須在下一版 VPP contract、程式、manifest 與報告中以相同 ID 引用。

| ID | 凍結決定 | 必要查核／標籤 |
|---|---|---|
| `A00_AUTHORITY` | 新的 `B2022-IR-v1` 是 post-audit VPP 模型／實驗的唯一權威；它只 normatively incorporate `SR2020-IR-v2@f342259` 的不可變資料、時間、品質與 H4 條款，並明文 supersede 其 VPP 參數／baseline／manifest 條款 | Manifest 分開保存 `dataContractId/Sha256` 與 `modelContractId/Sha256`；不得讓兩份互斥 baseline 同時有效，也不得改寫已凍結的 data-paper snapshot |
| `A01_SCOPE` | 所有本地結果稱「同源公開資料上的獨立復現／重新定義實驗」，不稱 exact replication | 報告固定揭露典型日、期間、PV cohort、SB-SC 與 solver 缺口 |
| `A02_PERIOD` | 主資料為公開 2020；Figure 6 只有 2020-01--06 與論文期間重疊 | 不補造 2019；重疊窗口與 2020 全年分開表列 |
| `A03_COHORT` | 主情境 20戶／20電池／10PV；H4 資料品質敏感度 19戶／19電池／9PV | 19/9 不得冒充論文的 20/20/9；另做 10 組 leave-one-PV-out 保持 20 戶，檢查未知 9-PV 身分 |
| `A04_TIME` | Wh 為 interval-end；費率與 daytime 以 interval start 判斷；`[10:00,22:00)` 為 day | 不做 timezone localization、DST 修補或全體平移 |
| `A05_BASELINES` | 同時保存 `PaperLoadOnlyBaseline` 與 `PvSelfNoBatteryBaseline` | 論文 discrepancy 只用前者；Peak Guard 與工程增益可用後者；欄名不得混用 |
| `A06_PV_BOUNDARY` | `DC_SOURCE` 主情境令 released Production = `PVGenDC`，沿用現有 Eq. 3；`AC_METER_RECONSTRUCTED_DC` 敏感度令 `PVGenDC = released Production / etaPvAC`，再使用完全相同的 Eq. 3，不另改拓樸 | 結果不得以「較接近論文」決定哪個是真值。Figure 5 proxy 固定畫：Load=`sum(loadKW)`；PV=`etaPvAC*sum(PVGenDC)`；Grid=`aggregateImportKW`（正為 import）；Battery=`sum(dischargePowerKW-chargePowerKW)`（DC-side，正為 discharge）並在圖說標明邊界 |
| `A07_XI` | `xi=0.07` 視為無因次分享損失；`xi=0` 為必要敏感度 | 不稱已知 feeder loss，不隨 30/60 min 任意縮放 |
| `A08_SELF_DISCHARGE` | `P_SD=0` | config、manifest 顯式保存；不可把 `xi` 當 self-discharge |
| `A09_INEQUALITIES` | 所有 strict inequalities 改成 inclusive | 記為論文意圖修復，不偽稱 literal equation |
| `A10_SOC` | SoC 使用 kWh；10 kWh 電池為 1--9 kWh，initial／terminal 1 kWh | 保存最大 dynamics、bound 與 terminal residual |
| `A11_TIE_BREAK` | Bill models：bill→throughput；PS/PSDT/LL：primary→bill→throughput | 每階段 optimum、allowance、exit flag、MIP gap 全部保存 |
| `A12_SH_OBJECTIVE` | SH-BM 禁止分享，objective 用實際 grid import 並乘 `dt` | 視為修復 Eq. 16 疑漏 PV-to-home，而非偷偷改模型 |
| `A13_TYPICAL_DAY` | 代表日由事先固定的 Figure 5 Load/PV 曲線距離選取 | 不看最佳化 savings 挑日；保存 reference hash 與 ranking |
| `A14_SBSC` | SB-SC 只作 public-release same-system observed proxy | 不擬合或反推 proprietary controller；不稱論文原日期／原 9-PV cohort 的 exact trace |
| `A15_MONTHLY` | 主值為每月每日指標的 arithmetic mean | 同時輸出 ratio-of-summed-costs／peak-of-mean-profile，量化原文 aggregation 歧義 |
| `A16_BUDGET_RATIO` | Capacity／power ratio 對每戶電池同比縮放；Figure 7 在求解前固定兩軸皆為 `0.2:0.1:1.0`，共 9×9 | 標成 redefined sensitivity；不得看結果後增刪 grid 點 |
| `A17_NETWORK_SCOPE` | Eq. 13 是 aggregate accounting，不是 feeder power flow | 不用 aggregate peak reduction 宣稱電壓／VUF／線路安全 |
| `A18_H4` | 20戶主結果必須與同日同設定 19戶排除 H4 成對 | 保存 pair ID、H4 mask affected flag；不修補或平移 H4 Wh |
| `A19_PROVENANCE` | 正式入口在建立 output dir 前 fail closed：執行 `shasum -c` 並保存 46/46 逐檔結果與 exit status；Git 檢查包含 untracked files；reference manifest 至少涵蓋 Figure 5 digitized profile、Figure 5 savings、Table I 與其來源／數位化規格；結果清單封存所有 artifacts | 實際 solver／provider 必須從執行路徑記錄，不得硬編；run manifest 保存兩份 contract hash 與 reference-manifest hash；`RESULT_MANIFEST.sha256` 單向雜湊 run manifest 與全部 artifacts，但排除自己，避免循環 |
| `A20_NO_TUNING` | 不以接近 Figure 5／Table I 百分比為調參準則 | 只報 target-vs-local discrepancy 與方向性趨勢 |
| `A21_SCENARIO_MATRIX` | Typical／monthly／Table-I 五策略固定跑六格：`DC/.07/20`、`DC/.07/19`、`AC/.07/20`、`AC/.07/19`、`DC/0/20`、`DC/0/19`；這是 two one-factor sensitivities，各 20 戶結果都有 H4 pair；`AC/0` interaction 非必要探索 | Figure 7 的 9×9 surface 固定跑 `DC/.07` 的 20／19 pair；10 組 leave-one-PV-out 只跑 typical-day nominal VPP-BM、20戶、`DC/.07`；observed SB-SC 只跑 20／19，不套 `xi` 或 AC/DC 模型假設 |
| `A22_DURABLE_SCHEMA` | 每個 day/cohort/boundary/xi/strategy 保存 content-addressed `inputs.mat` 與 `solution.mat`，另輸出 long-form metrics/stages CSV | Inputs 至少含 timeEnd/start、dt、houseIds、load、released/model PV、price/dayMask、config、quality/cohort/H4 mask；solution 至少含八種 flows、curtailment、SoC、binaries、stage objectives/gaps/allowances，足以離線重算 |

## 8. 兩層驗收 gate

將「能否開始正式求解」與「求解後結果能否發布」分開，避免用尚未求解才可能產生的圖與數值作為 pre-solve 條件。

### 8.1 Pre-solve admission

| Gate | 正式資料求解前的必要條件 | 目前狀態 |
|---|---|---|
| P1 Documentary mapping | Eqs. (1)--(24)、參數、修復與未知均逐項登錄 | `PASS — documentary only` |
| P2 Normative authority | `B2022-IR-v1` 明文 supersede 舊 VPP 條款，並定義 data/model 雙 contract ID 與 hash | `FAIL — BLOCKER` |
| P3 Boundary definitions | A05、A06、A15、A16、A21、A22 全部落成唯一可執行 schema | `FAIL — BLOCKER` |
| P4 Dual baseline | load-only 與 PV-self/no-battery 各自具獨立欄位、公式與 tests | `FAIL — BLOCKER` |
| P5 Cohort／scenario runner | 六格固定 scenario matrix、20/19 pair、pair ID、H4 flag 與 leave-one-PV scope 已實作 | `FAIL — BLOCKER` |
| P6 Provenance preflight | 建 output 前驗證 46/46；Git 包含 untracked；contract/reference hashes；記錄實際 solver/provider；持久化 analyzer/runtime preflight log | `FAIL — BLOCKER` |
| P7 Durable schema | Inputs 與完整 solution 可持久化，且獨立 evaluator 可在不呼叫 solver 下重算全部 metrics | `FAIL — BLOCKER` |
| P8 Fixture acceptance | 雙 baseline、有效電池調度、邊界、cohort、manifest fail-closed、月度與 Table I orchestration tests 全通過 | `FAIL — BLOCKER` |
| P9 Historical protection | 新 run ID、拒絕覆寫、不 retrofit pre-v2 artifacts | `PASS` |

**Pre-solve 決定：** P2--P8 尚未通過，因此現在不准許對正式公開資料重新求解。這不禁止為完成 P8 而執行小型 synthetic／fixture solver tests。

### 8.2 Post-solve result acceptance

以下條件只有在 pre-solve 全通過並產生新成果後才檢查；目前一律記為 `NOT RUN`，不是 pre-solve failure。

| Gate | 新成果的接受條件 | 目前狀態 |
|---|---|---|
| R1 Solver completion | 每個 lexicographic stage `exitFlag>0`，且 finite relative MIP gap `<=1e-6` | `NOT RUN` |
| R2 Physical feasibility | equality residual、SoC initial/terminal/bound、charge/discharge power、aggregate nonnegative 與 simultaneous charge/discharge violation 均 `<=1e-7`，單位依欄位為 kW 或 kWh | `NOT RUN` |
| R3 Lexicographic preservation | 最終解重算的每個已鎖 primary objective 不超過該 stage optimum 加 `1e-7*max(1,abs(optimum))` | `NOT RUN` |
| R4 Scenario completeness | A21 規定的 typical／monthly／Table-I 六格、Figure 7 20/19 surface、10 個 leave-one-PV-out 與 observed SB-SC 20/19 無缺列 | `NOT RUN` |
| R5 Offline recomputation | 只讀 `inputs.mat`／`solution.mat`／config 即可重算 bills、雙 savings、peaks、flows 與全部 residual；與報告值差異不超過 `1e-9*max(1,abs(value))` | `NOT RUN` |
| R6 Paper-facing outputs | Figure 5 proxy、Figure 6 monthly、Figure 7 surface、Table I target-vs-local 與所有 unavailable／proxy 標籤齊全 | `NOT RUN` |
| R7 Artifact closure | `RESULT_MANIFEST.sha256` 涵蓋 inputs、solutions、CSV、JSON、figures、preflight log 與 run manifest，但排除清單自己；checksum verification 100% 通過 | `NOT RUN` |
| R8 Scientific interpretation | 不設任意接近論文百分比門檻、不依結果挑日或調參；差異按預先登錄因素解讀 | `NOT RUN` |

只有 R1--R8 全部通過，新批次才可稱 `B2022-IR-v1 accepted independent reproduction`。

## 9. 下一個實作批次的固定順序

1. 建立 `B2022-IR-v1`，逐條列出從 `SR2020-IR-v2@f342259` 納入的不可變資料／時間／品質／H4 規則，並明文取代其 VPP baseline、參數、實驗與 manifest 條款。後續 manifest 同時保存 data-contract 與 model-contract 的 ID/hash；舊 data-paper snapshot 不修改。
2. 先以 tests 定義雙 baseline、A06 AC 重建方程、Figure 5 曲線邊界、六格 scenario keys、20/19 pairing、H4 flag、9×9 grid、durable schema 與 provenance fail-closed 行為。
3. 實作雙 baseline、cohort/scenario runner、逐檔 checksum、reference manifest、實際 solver/provider provenance、`inputs.mat`／`solution.mat` 與獨立 evaluator。
4. 加入 public-release same-system observed SB-SC proxy，完成 Figure 5 與 Figure 6 的正式輸出器。
5. 完成 Figure 7 固定 9×9 grid 與 Table I 五策略 reduced-budget orchestration。
6. 執行 synthetic／fixture acceptance tests；P1--P9 全通過後建立 clean Git checkpoint。
7. 最後才對正式公開資料建立全新 run directories 並重新求解；通過 R1--R8 後封存 result checksums、commit 與 release tag。舊結果只保留為歷史比較。

這個順序表示：我們已自行完成資料與模型假設的決策，不需要等待老師先核准；但「自行決定」不等於跳過可重現性 gate。
