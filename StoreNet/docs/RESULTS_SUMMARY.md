# StoreNet pre-SR2020-IR-v2 歷史結果摘要

- 摘要日期：2026-09-01
- 方法論文：Bahloul et al. (2022), DOI `10.1109/TSTE.2022.3187217`
- 資料來源：StoreNet Figshare processed release v1
- 求解環境：MATLAB R2026b Prerelease Update 1、`intlinprog`
- 教授版交付：[DOCX](../report/StoreNet_復現與改進報告_教授版.docx)、[PDF](../report/StoreNet_復現與改進報告_教授版.pdf)
- 跨環境延伸：[EXTERNAL_VALIDATION_RESULTS.md](./EXTERNAL_VALIDATION_RESULTS.md)

> 本文件保存契約 v2 凍結前的 VPP 數值，不是目前的 v2 正式摘要；其 Figure 5／6／7 均指 Bahloul et al. (2022)。這些批次尚缺 `contractId`／`contractSha256` 與 20 戶／排除 H4 之 19 戶成對敏感度。

## 1. Claim boundary

這批結果是 **StoreNet 2020 公開資料上的結構性獨立復現**，不是原論文的數值級復現，也不應稱為 paper-equivalent。

本專案可主張：

- 本地 46 個 Figshare 發布項目的完整性已驗證；
- 經差異修正的論文意圖模型、五種策略與本專案改進策略均可重跑；
- 代表日由外生 load／PV 曲線形狀預先選定，沒有用最佳化後 savings 挑日；
- 所有成功求解列都有機器可讀輸出、solver 狀態與模型內部殘差。

本專案不能主張：

- Figure 5 的 2020-08-24 就是作者未公布的典型日；
- 2020 月度平均等同論文 2019-07 至 2020-06 的 Figure 6／annual average；
- 公開版 10 個 PV 戶等同論文未公布身分的 9 個 PV 戶；
- 已重建未公開的 SB-SC 商業控制器、作者 solver/tie-break 或 Figure 7 原始網格；
- aggregate peak 結果等同配電潮流、電壓或變壓器安全驗證。

公式與參數差異的逐項說明見 [MODEL_DISCREPANCY_REPORT.md](./MODEL_DISCREPANCY_REPORT.md)，方程到程式的映射見 [TRACEABILITY.md](./TRACEABILITY.md)。

## 2. 正式輸出索引

| 實驗 | 主要輸出 | Provenance |
|---|---|---|
| 2020 代表日選擇 | [ranking.csv](../results/typical_day_selection_2020/ranking.csv) | [manifest.json](../results/typical_day_selection_2020/manifest.json) |
| 代表日五基準與改進 | [metrics.csv](../results/baseline_typical_20200824_v2/metrics.csv)、[profiles.csv](../results/baseline_typical_20200824_v2/profiles.csv)、[typical_day.png](../results/baseline_typical_20200824_v2/typical_day.png) | [manifest.json](../results/baseline_typical_20200824_v2/manifest.json) |
| VPP-BM 容量／功率敏感度 | [sensitivity.csv](../results/sensitivity_20200824_vppbm/sensitivity.csv)、[sensitivity.png](../results/sensitivity_20200824_vppbm/sensitivity.png) | [manifest.json](../results/sensitivity_20200824_vppbm/manifest.json) |
| 月度 `release_literal` | [monthly_summary.csv](../results/monthly_2020_release_literal_bounded60/monthly_summary.csv)、[monthly_metrics.csv](../results/monthly_2020_release_literal_bounded60/monthly_metrics.csv)、[monthly_quality_status.csv](../results/monthly_2020_release_literal_bounded60/monthly_quality_status.csv)、[monthly_checkpoint.csv](../results/monthly_2020_release_literal_bounded60/monthly_checkpoint.csv) | [manifest.json](../results/monthly_2020_release_literal_bounded60/manifest.json) |
| 月度 `exclude_flagged_pv` | [monthly_summary.csv](../results/monthly_2020_exclude_flagged_pv_bounded60/monthly_summary.csv)、[monthly_metrics.csv](../results/monthly_2020_exclude_flagged_pv_bounded60/monthly_metrics.csv)、[monthly_quality_status.csv](../results/monthly_2020_exclude_flagged_pv_bounded60/monthly_quality_status.csv)、[monthly_checkpoint.csv](../results/monthly_2020_exclude_flagged_pv_bounded60/monthly_checkpoint.csv) | [manifest.json](../results/monthly_2020_exclude_flagged_pv_bounded60/manifest.json) |
| 月度兩品質模式比較 | [strategy_comparison.csv](../results/monthly_comparison_2020_v2/strategy_comparison.csv)、[quality_comparison.csv](../results/monthly_comparison_2020_v2/quality_comparison.csv)、[monthly_comparison.png](../results/monthly_comparison_2020_v2/monthly_comparison.png) | [manifest.json](../results/monthly_comparison_2020_v2/manifest.json) |
| Ausgrid 53 戶預註冊外部驗證 | [primary_metrics.csv](../results/external_validation_ausgrid_2012_2013_v1/primary_metrics.csv)、[frontier_metrics.csv](../results/external_validation_ausgrid_2012_2013_v1/frontier_metrics.csv)、[external_validation.png](../results/external_validation_ausgrid_2012_2013_v1/external_validation.png) | [manifest.json](../results/external_validation_ausgrid_2012_2013_v1/manifest.json)、[summary.json](../results/external_validation_ausgrid_2012_2013_v1/summary.json) |
| Ausgrid 排除 Customer 161 post-hoc sensitivity | [primary_metrics.csv](../results/external_sensitivity_ausgrid_exclude_customer161_v1/primary_metrics.csv)、[frontier_metrics.csv](../results/external_sensitivity_ausgrid_exclude_customer161_v1/frontier_metrics.csv)、[external_validation.png](../results/external_sensitivity_ausgrid_exclude_customer161_v1/external_validation.png) | [manifest.json](../results/external_sensitivity_ausgrid_exclude_customer161_v1/manifest.json)、[summary.json](../results/external_sensitivity_ausgrid_exclude_customer161_v1/summary.json) |

各 manifest 保存執行時的 Git commit、資料 manifest hash、MATLAB／solver 版本、設定、狀態與時間。正式執行時 `trackedFilesDirty=false`；結果目錄本身依專案政策不納入 tracked-files dirty 判定。

正式引用請使用 `baseline_typical_20200824_v2`、兩個 `*_bounded60` 月度目錄與 `monthly_comparison_2020_v2`。不含這些後綴的舊版目錄與季度切片只保留作歷程或診斷。

## 3. 代表日選擇

正式 MATLAB 流程直接由 immutable CSV 重算 2020-01-01 至 2020-12-10 的 345 個候選日，只使用數位化 Figure 5 的 aggregate load／PV 曲線距離：

```text
score = sqrt(mean(((load-referenceLoad)/20)^2 + ((pv-referencePv)/10)^2))
```

- 345 個候選日中，87 日通過 `exclude_flagged_pv`，且只有一列標為 selected；
- 排名第一的 2020-06-10：score `0.227437099056766`，但 H19 有超過 2 分鐘的 status gap，因此拒絕；
- 第一個通過日為 **2020-08-24**：score `0.242266698119992`；
- 該日 aggregate load `237.371525 kWh`、PV `39.003295 kWh`；
- load peak `18.87078 kW`、半小時 PV peak `7.16826 kW`；
- PV window `11.75 h`，未超過約 `13.8073 h` 的天文日長門檻；最大 status gap 為 2 分鐘。

因此，2020-08-24 是公開資料 proxy day，不是對作者未公開日期的識別。

## 4. 代表日五種基準與改進

條件：2020-08-24、30 分鐘、20 戶、公開版 10 個 PV 戶、`exclude_flagged_pv`。無電池基準為各戶 PV 自用、無跨戶分享、無 FIT：

- baseline bill：`33.29714113 EUR/day`
- baseline aggregate peak：`17.9361625 kW`

下表以 6 位小數呈現；完整精度以正式 [metrics.csv](../results/baseline_typical_20200824_v2/metrics.csv) 為準。

| 策略 | Phase | Optimized bill (EUR) | Savings (EUR) | Savings (%) | Peak (kW) | Daytime peak (kW) | Throughput (kWh) |
|---|---|---:|---:|---:|---:|---:|---:|
| SH-BM | baseline | 22.589328 | 10.707813 | 32.158356 | 55.681739 | 10.011200 | 211.456323 |
| VPP-BM | baseline | 19.558045 | 13.739096 | 41.262089 | 75.500784 | `6.72e-15` | 244.671415 |
| PS | baseline | 29.063987 | 4.233154 | 12.713265 | 8.498242 | 8.498242 | 90.335021 |
| PSDT | baseline | 19.558045 | 13.739096 | 41.262089 | 75.500784 | `1.78e-15` | 244.671415 |
| LL | baseline | 29.063988 | 4.233153 | 12.713262 | 8.498242 | 8.498242 | 90.334342 |
| IMPROVED_PEAK_GUARD | improvement | 20.571101 | 12.726040 | 38.219617 | 17.936163 | 7.208451 | 217.875128 |

主要解讀：

1. VPP-BM 與 PSDT 在此日給出最低帳單，但將充電集中到夜間，aggregate peak 升到 `75.500784 kW`。日間 peak 近零不代表全天尖峰被控制。
2. PS 與 LL 將 peak 降到約 `8.498242 kW`，但 savings 降到約 `12.713%`。
3. SH-BM 也產生 `55.681739 kW` 尖峰，顯示只有個別帳單目標仍可能造成跨戶同步充電。

### 4.1 改進策略的精確成對比較

`IMPROVED_PEAK_GUARD` 的 cap 在任何改進求解前固定為無電池基準尖峰 `17.9361625 kW`。它不是論文策略，也不是配電潮流限制。

| 指標 | VPP-BM | Peak guard | Peak guard − VPP-BM |
|---|---:|---:|---:|
| Bill (EUR/day) | 19.5580451786320 | 20.5711012198149 | +1.0130560411829 |
| Savings (%) | 41.2620888313724 | 38.2196172953695 | -3.0424715360029 pp |
| Peak (kW) | 75.5007842105263 | 17.9361625000000 | -57.5646217105263 |
| Daytime peak (kW) | `6.7168492989822e-15` | 7.2084505000000 | +7.2084505000000 |
| Grid import (kWh) | 214.923573391560 | 212.657449236159 | -2.266124155401 |
| Battery throughput (kWh) | 244.671414653528 | 217.875128316187 | -26.796286337341 |
| Shared export (kWh) | 32.7784615091966 | 20.0494539750684 | -12.7290075341282 |

換算後，peak guard 以 bill 增加 `5.179741%`、savings 減少 `3.042472` 個百分點為代價，將 VPP-BM peak 降低 `76.243740%`，並把 peak 限制在未安裝電池的 PV-self-consumption 基準內。這是一個明確的成本—尖峰折衷，而不是全面支配 VPP-BM。

## 5. VPP-BM 容量／功率敏感度

敏感度在同一代表日與品質模式下使用預先宣告的 5×5 grid：capacity ratio 與 power ratio 均為 `0.2, 0.4, 0.6, 0.8, 1.0`。容量會先縮放實體 kWh，SoC 起終點與上下界維持相同比例；功率直接縮放 3.3 kW。25/25 組合均成功。

| Capacity ratio | Savings 範圍（跨 power ratios） | Peak 範圍（kW） |
|---:|---:|---:|
| 0.2 | 17.876571%–17.906387% | 22.775237–63.462101 |
| 0.4 | 25.962394%–26.185849% | 24.095497–66.554121 |
| 0.6 | 33.885309%–34.293382% | 24.398037–70.311964 |
| 0.8 | 37.283420%–41.007332% | 24.398037–74.006375 |
| 1.0 | 37.292968%–41.262089% | 24.398037–75.500784 |

趨勢與限制：

- savings 主要隨容量增加；低容量時，提高功率幾乎不增加 savings，卻會顯著提高排程尖峰。
- 在 nominal capacity 下，power ratio 由 0.4 增至 1.0，savings 只從 `41.096667%` 增至 `41.262089%`（+`0.165422` pp），peak 卻由 `35.457140` 增至 `75.500784 kW`（+`40.043644 kW`）。
- 25 個無尖峰限制的 VPP-BM 組合中，最低 peak 仍為 `22.775237 kW`，高於無電池基準的 `17.936163 kW`；單靠縮小容量／功率沒有在這個 grid 內消除新尖峰。
- nominal 1.0／1.0 組合得到最高 savings `41.262089%`，同時也得到最高 peak `75.500784 kW`；最低 0.2／0.2 組合為 savings `17.876571%`、peak `22.775237 kW`。

這是本專案重新定義的敏感度實驗。原論文未公布 Figure 7 的精確 grid，因此不可稱為逐點重現 Figure 7。

## 6. 2020 月度結構性復現

兩個月度 run 都使用 2020 每月第 1、2、15、16 日，共 48 個請求日；每個通過日以 1 小時解析度求解五種策略。平均只使用 `Status=ok` 的列，被品質拒絕或求解失敗的列不以鄰近日替換，也不當作 0。

### 6.1 月度 summary

| 品質模式 | 策略 | 成功日／48 | Mean savings (%) | Mean peak (kW) | Mean optimized bill (EUR) |
|---|---|---:|---:|---:|---:|
| `release_literal` | SH-BM | 45 | 28.279663 | 61.956256 | 29.164273 |
| `release_literal` | VPP-BM | 45 | 37.107141 | 67.180288 | 25.790061 |
| `release_literal` | PS | 45 | 12.530304 | 11.268922 | 35.723820 |
| `release_literal` | PSDT | 45 | 37.106429 | 64.605260 | 25.790445 |
| `release_literal` | LL | 44 | 6.968826 | 11.275720 | 37.374211 |
| `exclude_flagged_pv` | SH-BM | 27 | 27.152947 | 64.094785 | 30.485742 |
| `exclude_flagged_pv` | VPP-BM | 27 | 35.786397 | 70.506104 | 26.948830 |
| `exclude_flagged_pv` | PS | 27 | 9.620869 | 11.570519 | 37.784632 |
| `exclude_flagged_pv` | PSDT | 27 | 35.785210 | 68.351293 | 26.949470 |
| `exclude_flagged_pv` | LL | 27 | 6.889071 | 11.570518 | 38.669655 |

兩種模式使用不同成功日集合，因此表中差值不是 matched-day 因果效果。共同的結構趨勢是：帳單型 SH/VPP/PSDT savings 較高但 aggregate peak 大；PS/LL 壓低 peak，但 mean savings 較低。

### 6.2 品質數量

| 項目 | `release_literal` | `exclude_flagged_pv` |
|---|---:|---:|
| 請求日 | 48 | 48 |
| Physical complete | 45 | 45 |
| Fully observed | 0 | 0 |
| Quality passed | 45 | 27 |
| Quality rejected | 3 | 21 |
| 含 physical incomplete reason | 3 | 3 |
| 含 status run >2 min reason | 0 | 20 |
| 含 status fraction >0.5% reason | 0 | 8 |
| PV long-window anomaly flag | 3 | 3 |
| 因 PV long-window anomaly 被拒 | 0 | 3 |
| 成功策略列 | 224 | 135 |
| 品質拒絕策略列 | 15 | 105 |
| 求解失敗策略列 | 1 | 0 |

品質原因會重疊，不能將原因列直接相加成拒絕日數。

- `release_literal` 只因 physical incompleteness 拒絕 2020-01-01、2020-12-15、2020-12-16；三個 PV 長窗異常日仍保留並標旗。
- `exclude_flagged_pv` 共拒絕 21 日；詳細日期與原因以各自的 `monthly_quality_status.csv` 為準。
- `Fully observed=0` 反映發布版 status/interpolation 記錄，不代表 48 日全都 physical incomplete；45 日仍有完整分鐘列。

### 6.3 唯一 timeout

所有正式 monthly runs 中唯一非品質拒絕的失敗為：

```text
Day: 2020-08-16
Strategy: LL
Mode: release_literal
Stage: throughput after import spread and bill
Exit flag: 0
Configured solver time bound: 60 s
Measured wall time: 62.119216 s
```

該列保留為 `failed`，沒有把部分解當成正式結果，因此 `release_literal` 的 LL summary 使用 44 日，而其他策略使用 45 日。相同日期在 `exclude_flagged_pv` 因 H16 status gap 先被品質拒絕，沒有進入求解。timeout 可能隨硬體、solver 版本或 branch-and-bound 路徑改變；manifest 已保存本次環境，不應將缺少的 LL 列改填為 0。

## 7. 數值殘差與驗收

| 輸出 | 成功列 | 最大 `EnergyBalanceResidualKW` | 最大 terminal SoC error | 最大同時充放電 | Minimum exit flag |
|---|---:|---:|---:|---:|---:|
| 代表日五基準＋改進 | 6 | `7.74491581978509e-13` | 0 | 0 | 1 |
| 代表日 sensitivity | 25 | `7.09280587479474e-13` | 0 | 0 | 1 |
| 月度 `release_literal` | 224 | `4.20208312590375e-12` | 0 | 0 | 1 |
| 月度 `exclude_flagged_pv` | 135 | `4.20208312590375e-12` | 0 | 0 | 1 |

所有成功列的最大內部平衡殘差為 `4.2021e-12 kW`，遠低於專案 `1e-7` 的模型驗收門檻。這只驗證最佳化模型內部的 PV 分流、住宅平衡、電池動態、轉換與 aggregate import 一致性；它不是原始感測資料的量測平衡準確率。

唯一 timeout 列沒有成功解與殘差數值，因此不納入上表。

## 8. 最小重跑命令

以下命令從 `/Users/guichenxiang/Desktop/電力專案` 執行。請使用新的 `RunId`，不要覆寫上述正式輸出。

先驗證 immutable release：

```bash
shasum -a 256 -c StoreNet/data/RELEASE_MANIFEST.sha256
```

重算代表日排名並顯示 selected row：

```bash
/Applications/MATLAB_R2026b.app/bin/matlab -batch 'addpath("StoreNet/src"); [d,r]=select_typical_day(); disp(d); disp(r(r.Selected,:))'
```

重跑代表日與敏感度：

```bash
/Applications/MATLAB_R2026b.app/bin/matlab -batch 'addpath("StoreNet/src"); run_typical_day(datetime(2020,8,24),QualityMode="exclude_flagged_pv",RunId="rerun_typical_20200824")'
/Applications/MATLAB_R2026b.app/bin/matlab -batch 'addpath("StoreNet/src"); run_sensitivity(datetime(2020,8,24),QualityMode="exclude_flagged_pv",RunId="rerun_sensitivity_20200824_vppbm")'
```

重跑兩個 60 秒上限的月度模式：

```bash
/Applications/MATLAB_R2026b.app/bin/matlab -batch 'addpath("StoreNet/src"); c=struct("maxSolverTimeSeconds",60); run_monthly(QualityMode="release_literal",RunId="rerun_monthly_2020_release_literal_bounded60",ConfigOverrides=c)'
/Applications/MATLAB_R2026b.app/bin/matlab -batch 'addpath("StoreNet/src"); c=struct("maxSolverTimeSeconds",60); run_monthly(QualityMode="exclude_flagged_pv",RunId="rerun_monthly_2020_exclude_flagged_pv_bounded60",ConfigOverrides=c)'
```

兩個月度重跑完成後，重建比較圖表：

```bash
/Applications/MATLAB_R2026b.app/bin/matlab -batch 'addpath("StoreNet/src"); render_monthly_comparison("StoreNet/results/rerun_monthly_2020_release_literal_bounded60","StoreNet/results/rerun_monthly_2020_exclude_flagged_pv_bounded60",RunId="rerun_monthly_comparison_2020")'
```

重跑測試：

```bash
/Applications/MATLAB_R2026b.app/bin/matlab -batch 'addpath("StoreNet/src"); result=runtests("StoreNet/tests"); assert(all([result.Passed]))'
```

月度求解較耗時；程式會在每個策略列後更新 checkpoint。重跑結果應以新 manifest 內的 Git commit、runtime、solver 與狀態解讀，不應只比較四捨五入後的 summary。
