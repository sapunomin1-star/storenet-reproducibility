# 計畫：Bahloul VPP 改進二版——帳單／尖峰前緣與需量電價（2026-09-03）

依 [ADR-002](decisions/ADR-002-bill-peak-frontier-and-tariff.md) 凍結的定義執行。所有新結果寫入 `results/bahloul_vpp_improvement_v2_frontier/`，凍結目錄一律唯讀。

## 目標與完成標準

在不改動核心 MILP 假設的前提下，回答四個可驗證的問題：

1. VPP-BM 的 cobra 尖峰有多少是「零代價」可消除的（`VPP_BM_PEAK_LEX` 的尖峰與帳單，典型日＋45 個月度日）。
2. 帳單—尖峰 Pareto 前緣長什麼樣：各 cap 比例的電費代價、邊際成本、膝點；Peak Guard（r=1）落在前緣哪裡。
3. 需量電價 λ 要多高，純經濟的聚合商才會自己把尖峰壓回 P0 以下；加權法的點是否落在前緣上。
4. 以實測效率 0.7173 校準後，論文五策略與新策略的省錢率各降多少。

完成標準：全部規劃案例有狀態（ok／infeasible／time_limited／failed），VPP-BM 與 r=1 重解與凍結值一致（≤1e-6），數值殘差 ≤1e-9，新測試與既有 `TestStoreNetModel` 通過，結果文件與圖表落地，commit＋tag。

## 非目標

- 見 ADR-002「非目標」。不碰 formal／Peak Guard 凍結目錄，不做潮流，不做預測。

## 階段

1. **決策與計畫落地** → 產出：ADR-002、本檔 → 驗證：檔案存在、網格已固定。
2. **模型增量**：`solve_storenet.m` 新增 `VPP_BM_PEAK_LEX`、`VPP_BM_DEMAND_CHARGE`（純新增分支；既有六策略程式路徑不動）；`evaluate_storenet.m` 讓需量電價階段可離線重算 → 產出：程式＋`tests/TestBahloulFrontierV1.m` → 驗證：`runtests` 新測試全綠，且 `TestStoreNetModel`、`TestPeakGuardImprovementV1` 回歸全綠。
3. **典型日**：`run_bahloul_frontier_v1.m`（可續跑、逐案 checkpoint）在 2020-08-24／30 分鐘跑錨點（VPP-BM、PEAK_LEX、PS）、18 個 r、8 個 λ、效率敏感度 7 案 → 驗證：VPP-BM 帳單／尖峰對凍結值 ≤1e-6；r=1 對 Peak Guard 帳單 ≤1e-6；所有 ok 案例殘差 ≤1e-9、終端 SoC 誤差 0、無同時充放電。
4. **月度批次**：45 日／60 分鐘：錨點 3 案＋9 個 r＋5 個 λ，單一 MATLAB 串行、逐案 checkpoint → 驗證：45/45 日完成；VPP-BM 與 PS 對 formal 日值 ≤1e-6；狀態統計。
5. **離線彙總與圖**：`summarize_bahloul_frontier_v1.m`（不重解）＋ Python 圖 → 驗證：彙總數值可由 `strategy_metrics.csv` 重算；r=1 列與 `bahloul_vpp_improvement_v1` 的 Peak Guard 月度 summed-cost 犧牲一致。
6. **交付**：`docs/B2022_FRONTIER_TARIFF_IMPROVEMENT_RESULTS.md`（數字 SSOT）、`results/README.md` 索引、HANDOFF 更新、記憶、commit＋tag `bahloul-vpp-frontier-v2`。

## 執行狀態（2026-09-04 收尾）

| 階段 | 狀態 | 證據 |
|---|---|---|
| 1 決策與計畫 | 完成 | ADR-002、本檔 |
| 2 模型增量＋測試 | 完成 | `TestBahloulFrontierV1` 5/5；全套 MATLAB 173/173；Code Analyzer 0 issue |
| 3 典型日 | 完成 | 39/39 `ok`；一致性 6/6 相對誤差 0；`storenet_typical_20200824/` |
| 4 月度批次 | 完成 | 816 案＝714 `ok`／51 `infeasible`（r ≤ 0.7）／51 `quality_rejected`；一致性 135/135；`storenet_monthly_2020/` |
| 5 彙總與圖 | 完成 | `summarize_bahloul_frontier_v1.m` 八份 CSV；`figures/fig1–fig6` |
| 6 交付 | 完成 | `docs/B2022_FRONTIER_TARIFF_IMPROVEMENT_RESULTS.md`、`docs/PROFESSOR_IMPROVEMENT_V2_SUMMARY.md`、`results/README.md`、HANDOFF、commit＋tag `bahloul-vpp-frontier-v2` |

## 風險與回退

- 緊 cap 的 MILP 在 60 秒內未證明最優 → 標 `time_limited`，不延長時間、不排除；典型日不設時間上限。
- `intlinprog` 對不可行回 −2 → 記 `infeasible`；若出現其他負 exit flag → 記 `failed` 並保留訊息。
- MATLAB 長批次中斷 → 以 `Resume=true` 重新呼叫 runner，跳過已完成案例。
- 若任何一致性閘門失敗（VPP-BM 對凍結值 >1e-6）→ 停止，不發布結果，先找環境差異。

## 使用者已拍板的決定（紅線）

- 教授指示三段式：先深度理解、完整復現、再找改進點；復現基準（formal、Peak Guard）已凍結，改進結果必須與基準成對呈現。
- 使用者 2026-09-03 指示：不要照抄既有研究，依自己的判斷做出更好的研究——本計畫據此以 ADR-002 的 B＋D 取代原手冊的「主攻網路約束」，理由已記錄。
