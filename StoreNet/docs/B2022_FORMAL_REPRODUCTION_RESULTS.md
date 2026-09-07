# B2022-IR-v1 正式復現結果

本報告整理 StoreNet 公開資料上的同源獨立復現。不主張 exact replication，不主張復原未公開的原始 typical day、九個 PV 住戶身分或 proprietary SB-SC controller。

## 正式狀態

- 正式結果根：`results/b2022_ir_v1_formal`
- 正式凍結 tag：`bahloul-vpp-formal-v1`
- Post-solve acceptance：R1--R8 全部 `PASS`
- 凍結矩陣：typical 10 列、Figure 7 81 列、Table I 15 列、monthly daily 240 列、monthly aggregate 60 列
- `SCIENTIFIC_ARTIFACT_MANIFEST.sha256`：120/120 驗證通過；manifest SHA-256 為 `082feeeb726429d80b0624f19078bc540674c94d396ea107dfeb1908cf80ec68`
- `RESULT_MANIFEST.sha256`：123/123 驗證通過；manifest SHA-256 為 `23ba52933409e41a59e3bd26d19d0460f939535e6e2e0d636f0f86bda08e3d48`

## 對照邊界與原因碼

下列百分比均以 `PaperLoadOnlyBaseline` 為分母，差異為「本地值 − 論文值」，單位是百分點（pp）。原因碼表示差異的事前已知解讀邊界，不把它們冒充為已識別的單一因果歸因。

- `P`：公開復現邊界。本地使用 2020-08-24 proxy day、公開 20 homes/10 PV、DC-SOURCE 與 `xi=0.07`；論文原 typical day 與原九個 PV 身分未公開。
- `S`：策略細節邊界。SH-BM 包含 Eq. 16 intended-model repair；PS、PSDT、LL 的論文式子有字面歧義，本地使用事前凍結的 intended-model 與 `primary -> bill -> throughput` tie-break；不以接近論文數字調參。
- `O`：Observed SB-SC 邊界。本地直接使用發布的 `FromGrid/FeedIn/Charge/Discharge`，是 same-system observed proxy，不是 proprietary controller 或原圖 trace 的重建。

## Figure 5：論文值／本地值／差異／原因

| Strategy | 論文 (%) | 本地 (%) | 差異 (pp) | 原因 |
|---|---:|---:|---:|---|
| SH-BM | 36.41 | 38.4003 | +1.9903 | P+S |
| VPP-BM | 45.83 | 46.6664 | +0.8364 | P |
| PS | 15.30 | 20.7443 | +5.4443 | P+S |
| PSDT | 43.63 | 46.6664 | +3.0364 | P+S |
| LL | 15.39 | 20.7443 | +5.3543 | P+S |
| SB-SC | 23.72 | 15.8214 | -7.8986 | P+O |

論文 Figure 5 的 VPP-BM 標示為 45.83%，Table I nominal 為 45.85%；這 0.02 pp 是原文內部差異，本專案不調參消除。詳細來源與全精度數值見 `results/b2022_ir_v1_formal/b2022_typical_v1_20200824/figure5_target_comparison.csv`。

## Table I：論文值／本地值／差異／原因

| Budget | Strategy | 論文 (%) | 本地 (%) | 差異 (pp) | 原因 |
|---|---|---:|---:|---:|---|
| NOMINAL | SH-BM | 36.41 | 38.4003 | +1.9903 | P+S |
| NOMINAL | VPP-BM | 45.85 | 46.6664 | +0.8164 | P |
| NOMINAL | PS | 15.30 | 20.7443 | +5.4443 | P+S |
| NOMINAL | PSDT | 43.63 | 46.6664 | +3.0364 | P+S |
| NOMINAL | LL | 15.39 | 20.7443 | +5.3543 | P+S |
| POWER-20 | SH-BM | 26.76 | 31.2160 | +4.4560 | P+S |
| POWER-20 | VPP-BM | 43.42 | 43.0625 | -0.3575 | P |
| POWER-20 | PS | 15.30 | 20.7035 | +5.4035 | P+S |
| POWER-20 | PSDT | 24.17 | 43.0625 | +18.8925 | P+S |
| POWER-20 | LL | 15.25 | 20.7035 | +5.4535 | P+S |
| CAPACITY-20 | SH-BM | 16.18 | 20.0048 | +3.8248 | P+S |
| CAPACITY-20 | VPP-BM | 26.45 | 25.4596 | -0.9904 | P |
| CAPACITY-20 | PS | 15.33 | 22.5862 | +7.2562 | P+S |
| CAPACITY-20 | PSDT | 18.04 | 25.3848 | +7.3448 | P+S |
| CAPACITY-20 | LL | 14.86 | 15.4506 | +0.5906 | P+S |

VPP-BM 的三個 Table I 點位與論文相差均小於 1 pp，支持保留既有核心 MILP。其餘策略的差異不作為調參目標。全精度數值見 `results/b2022_ir_v1_formal/b2022_sensitivity_v1_20200824/table_i_target_vs_local.csv`。

## Figure 7 方向性結果

- 主網格為事前凍結的 capacity/power `0.2:0.1:1.0`，共 81 格；論文的精確 grid 未公開，因此不報告 exact surface replication。
- 本地平均 capacity range 為 20.7386 pp，power range 為 1.3827 pp，支持論文「capacity 影響大於 power」的方向性主張。
- 本地最大 savings 為 46.6664%，位於 capacity=1、power=1；論文提及區域 capacity 0.7--0.8/power 0.2--0.3 的本地平均為 43.9811%，本地最大值不在該區域。

## Monthly 離線重分組與限制

- 公開資料只有 2020；2020-01--06 是論文期間 overlap，2020-07--12 是公開資料外推，不補造 2019。論文沒有表列可作 exact acceptance 的 12 個 monthly bar 數值，因此不虛構逐月差異。
- 240 個 day-strategy cells 中：224 `ok`、1 個保留原始 `failed`、15 個 `quality_rejected`。品質拒絕以整天五策略原子化處理。
- 2020-01-01 因 20 戶公開資料不完整而拒絕；2020-12-15 與 2020-12-16 因 H14 不完整而拒絕。
- 2020-08-16 的 LL 保留既有 throughput-stage optimization failure，沒有靜默改寫或重解；因此 2020-08 LL 以 3 個有效日聚合，其他四策略為 4 個有效日。
- 月度 savings 以每月有效日的 summed costs ratio 計算，不把 daily percentages 直接平均當作主指標。

## 驗證與 post-solve 處理

正式求解後，第一次 acceptance 只在 R3 與 R6 拒絕。R3 的 6 個超限全在 `7.9e-15`--`7.0e-14`，為 objective expression 與離線重算的加總順序 roundoff；最終 evaluator 只加入 `1e-12 * scale` arithmetic slack，不改 `1e-7` lexicographic allowance、solver、MILP 或 dispatch。R6 是 evaluator 期待 `MODEL_STRUCTURAL_PROXY`，而既有 profile producer 使用 `STRUCTURAL_PROXY` 的字彙不一致；最終驗收對齊既有 producer 字彙。

修正後的定向回歸同時證明 `5e-13` roundoff 可通過、`1e-9` 實質超限仍失敗；完整 `TestBahloulAcceptanceV1` 為 20/20 通過，兩個變更檔的 MATLAB Code Analyzer 為 0 issue。最終 acceptance 是針對原 120 項 scientific artifacts 離線重跑，沒有重新求解或改寫科學數值。
