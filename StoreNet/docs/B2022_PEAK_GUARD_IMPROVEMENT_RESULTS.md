# Bahloul VPP Peak Guard 改進比較結果

本報告只處理「完工交接 → improvement 分支 → Peak Guard 比較 → Ausgrid double-check」。不重跑或擴張 formal R1--R8，不改寫核心 MILP，也不重新研究 H4、Figure 5--10、九個 PV 身分或 SB-SC controller。

## 狀態與不可變基準

- 凍結 formal commit：`1f1b42199c737b959f051f94303e0e7364f6863a`
- 凍結 annotated tag：`bahloul-vpp-formal-v1`
- 完工交接純文件 commit：`aa9fef91e49049634a5f710981baa3b7fbe32f24`
- Improvement 分支：`bahloul-vpp-improvement-v1`
- Improvement annotated tag：`bahloul-vpp-peak-guard-v1`
- 新結果根：`results/bahloul_vpp_improvement_v1`

`results/b2022_ir_v1_formal` 未改動，`bahloul-vpp-formal-v1^{}` 仍指向 `1f1b421`。

## 固定比較口徑

StoreNet 兩策略使用相同資料、日期、20 homes/10 PV、`DC_SOURCE`、`xi=0.07`、每戶 10 kWh/3.3 kW 電池、0.95 充放電效率、0.091/0.194 EUR/kWh 夜/日電價、FIT=0 與相同 SoC 邊界。Typical proxy day 是 2020-08-24（30 分鐘）；monthly 延用 formal evidence 的 2020 候選日與 60 分鐘 `release_literal` 設定。

Peak Guard cap 在每日求解前固定為：

`max_t aggregate(PV-self / no-battery grid import)`

每日直接使用 formal `PvSelfNoBatteryPeakKW`，並在 solver 前重算兩種 baseline 進行數值核對；沒有依結果重調 cap。指標定義為：

- `PaperSavingsPercent = (load-only baseline bill - strategy bill) / load-only baseline bill`
- `EngineeringSavingsPercent = (PV-self/no-battery baseline bill - strategy bill) / PV-self/no-battery baseline bill`
- bill penalty = Peak Guard bill - VPP-BM bill
- savings sacrifice = VPP-BM savings - Peak Guard savings（百分點，pp）
- peak reduction = VPP-BM all-day peak - Peak Guard all-day peak

Monthly 主 savings 數字先加總各有效日的 baseline bill 與 strategy bill 再計算，與 formal monthly 口徑一致；CSV 也另保留逐日百分比的平均與中位數。

## 執行與重用

- StoreNet typical：不求解。重用凍結 formal VPP-BM 與既有 Peak Guard CSV/profile；15 項 VPP 指標最大差 `3.13e-13`，48 點 VPP profile 差為 0，PV 可用量最大差 `8.88e-16 kW`，cap 差為 0。
- StoreNet monthly：48 個 formal VPP-BM 日中 45 日可用；`2020-01-01`、`2020-12-15`、`2020-12-16` 保留 quality rejection。只串行求解 45 個缺少的 `IMPROVED_PEAK_GUARD`，單一 MATLAB 工作階段限制為單線執行，每案 checkpoint。最終 45/45 完成、0 failed、checkpoint `IsFinal=1`。
- Ausgrid：不求解。只重整 `results/external_sensitivity_ausgrid_exclude_customer161_v1` 的 12 個事前選定代表日；既有 result manifest 12/12 通過，raw source SHA-256 為 `e4be46b3c9991c65735a9545319a2f1c33be8e639c75a17a88e0323a8e5098be`。

StoreNet monthly 保存 45 組 content-addressed inputs/solution MAT（共 90 檔）、metrics 與 stages；90 個檔名 hash 均與檔案 SHA-256 一致。45 組 artifact 全數離線重評，cap 差為 0，CSV 與重評指標最大絕對差 `5.12e-13`。沒有建立新 acceptance、schema 或 manifest 系統。

## 主要結果

| 資料組 | 配對日 | VPP-BM 形成新尖峰 | Peak Guard 通過固定 cap | 平均全天 peak：VPP → PG (kW) | 平均 peak 降幅 | bill 代價 | Paper savings 犧牲 | Engineering savings 犧牲 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| StoreNet typical 2020-08-24 | 1 | 1/1 | 1/1 | 75.5008 → 17.9362 | 57.5646 kW（76.2437%） | +1.0131 EUR/day | 2.7625 pp | 3.0425 pp |
| StoreNet monthly | 45 | 45/45 | 45/45 | 67.1803 → 20.0587 | 47.1216 kW（69.0988%） | 平均 +2.6282 EUR/day | 6.0244 pp | 6.5456 pp |
| Ausgrid no-161 | 12 | 6/12 | 12/12 | 92.1988 → 64.9930 | 27.2058 kW（17.9709%） | 最大絕對差 `2.98e-13` | 數值上 0 pp | 數值上 0 pp |

StoreNet monthly 的 savings 犧牲為 summed-cost 主口徑。若改看 45 個逐日百分點差的算術平均，Paper/Engineering 分別為 6.1621/6.6821 pp；37/45 日有正 bill 代價，8/45 日在 `1e-9` 容差內等價。Peak 降幅在 45/45 日均為正，範圍 11.8013--65.7725 kW（44.6615%--79.8299%）。

Ausgrid 的效果集中在原 VPP-BM 會形成新尖峰的日期：中位降幅 0.8933 kW，最大降幅 121.2605 kW。2013-06-26 的 cap 為 87.3220 kW，VPP-BM 為 208.5825 kW，Peak Guard 回到 87.3220 kW。

## 其他工程指標

下表的變化均為 Peak Guard - VPP-BM；load range 列則為 VPP-BM - Peak Guard，正值代表縮小。

| 資料組 | daytime peak 變化 (kW) | load range 縮小 (kW) | grid import 變化 (kWh) | battery throughput 變化 (kWh) | PV curtailment |
|---|---:|---:|---:|---:|---|
| StoreNet typical | +7.2085 | 57.5646 | -2.2661 | -26.7963 | 兩策略均 0 |
| StoreNet monthly（逐日平均） | +6.2499 | 47.1319 | -4.6888 | -59.7550 | Peak Guard 45/45 日為 0；formal VPP 欄位未保存 |
| Ausgrid no-161（逐日平均） | +0.2778 | 27.2058 | 數值上 0 | 數值上 0 | 平均 +0.00585 kWh；個別等價最優解可不同 |

Peak Guard 的主要作用是消除全天同步充電尖峰，不是最小化 daytime peak。StoreNet monthly 中 daytime peak 在 38/45 日上升、1/45 日下降、6/45 日數值上不變；這是在全天 cap 下重新分配 import 的結果。

## 數值殘差與證據邊界

- Typical energy-balance residual：VPP-BM `3.18e-14 kW`，Peak Guard `6.22e-15 kW`；兩者 terminal SoC 與 simultaneous charge/discharge 為 0。
- Monthly formal VPP-BM 可比較的最大 energy-balance residual 為 `3.15e-13 kW`，terminal SoC 與 simultaneous charge/discharge 為 0。Peak Guard 完整細分殘差/違規最大約 `1.4e-13`，cap 超越最大 `4.62e-14 kW`。
- Ausgrid 既有共同殘差的最大 energy-balance residual 為 `1.48e-12 kW`，terminal SoC 與 simultaneous charge/discharge 為 0，cap 超越最大約 `1e-13 kW`。
- Formal monthly VPP-BM 未保存 curtailment 與所有細分限制式 residual；Ausgrid 目錄也沒有 dispatch/MAT。這些欄位保持 `NA`，不為補欄而重解 VPP-BM。

## 回答四個問題

1. **Peak Guard 是否顯著降低新尖峰：** 是，在工程尺度上幅度大而一致；本報告沒有主張做過統計顯著性檢定。StoreNet typical 降低 76.24%，monthly 45/45 日都把 VPP-BM 新尖峰壓回事前 cap，平均降低 69.10%。
2. **犧牲多少 savings：** Typical 增加 1.0131 EUR/day，Paper/Engineering 犧牲 2.7625/3.0425 pp。Monthly 平均增加 2.6282 EUR/day，summed-cost Paper/Engineering 犧牲 6.0244/6.5456 pp。
3. **StoreNet monthly 與 Ausgrid 方向是否一致：** 一致。Ausgrid 的 VPP-BM 在 6/12 日形成新尖峰，Peak Guard 為 0/12，且 bill/savings 代價在數值容差內為零。這是外部方向性 double-check，不是用 Ausgrid 調整 StoreNet cap。
4. **哪些差異來自資料集：** Ausgrid 是 52 homes/52 PV、30 分鐘、inverter-AC gross PV（`etaPvAC=1`）與澳洲 2012--2013 profile；StoreNet 是 20 homes/10 PV、DC-source 與 2020 profile。不同 PV 滲透率、量測邊界、時間解析度、地區/年份與 load/PV 形狀，決定了可否在相同最低 bill 解集內滿足 cap。Ausgrid 幾乎零代價反映等價最優解的時間彈性，不是 Peak Guard 經過反向調參。

最後，Ausgrid 沿用 StoreNet tariff 作為策略比較單位，不代表歷史澳洲帳單；Peak Guard cap 也是 aggregate import 上限，不是 feeder power-flow 或電壓限制。

## 結果索引

- `results/bahloul_vpp_improvement_v1/storenet_typical/summary.csv`
- `results/bahloul_vpp_improvement_v1/storenet_typical/paired_comparison.csv`
- `results/bahloul_vpp_improvement_v1/storenet_monthly/monthly_summary.csv`
- `results/bahloul_vpp_improvement_v1/storenet_monthly/paired_comparison.csv`
- `results/bahloul_vpp_improvement_v1/storenet_monthly/residual_summary.csv`
- `results/bahloul_vpp_improvement_v1/storenet_monthly/checkpoint.csv`
- `results/bahloul_vpp_improvement_v1/ausgrid_no161/summary.csv`
- `results/bahloul_vpp_improvement_v1/ausgrid_no161/paired_comparison.csv`
