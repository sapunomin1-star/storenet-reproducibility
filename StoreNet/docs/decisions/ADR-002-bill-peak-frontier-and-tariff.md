# ADR-002：改進方向二版——帳單／尖峰 Pareto 前緣、零代價尖峰抑制與需量電價等價（2026-09-03）

Status: accepted for improvement v2（求解前凍結）
Decision date: 2026-09-03

## 背景

Bahloul et al. (2022) 的五個策略是五個極端點：VPP-BM 省錢最多（本地復現 46.67%），但把 20 顆電池在夜間同步充電，聚合尖峰從原始 18.87 kW 變成 75.50 kW（cobra 效應）；PS／LL 把尖峰壓到 8.50 kW，省錢率卻只剩 20.74%。論文結論第 5 點自己寫了「further work deserves the development of improved control strategies to maintain the benefits of consumers, aggregators and network operators in one frame」，並建議設計「a novel consumption tariff scheme … awards or penalties based on network requirement compliances」，但沒有做。

既有改進 Peak Guard（tag `bahloul-vpp-peak-guard-v1`）在 VPP-BM 上加一條固定的全天進口上限（cap＝PV 自用／無電池的聚合尖峰 P0），典型日尖峰 −76.24%、電費 +1.013 EUR／日；月度 45 日平均犧牲 6.02 pp。它證明「加一條 cap 有效」，但只回答了一個點：cap 為什麼是 P0？多壓 1 kW 要多付多少錢？哪一段是免費的？DSO 要開多高的需量電價，經濟導向的聚合商才會自己避開新尖峰？這些都是 Peak Guard 沒有回答、而論文明確點名的問題。

手冊 §7 與執行計畫 §9 原本建議主攻「LV 變壓器網路約束」。本輪重新審視資料論文 Fig. 2：參與戶大多各自掛在一顆 5／15／33／50 kVA 變壓器下（只有 H1+H7、H8+H9+H10 共用），且每顆變壓器還供應數量未知的非參與戶；公開資料沒有非參與戶負載，也沒有饋線阻抗。在這種資料條件下，任何變壓器負載或電壓限制都要靠未公開的假設補齊，結果無法被獨立驗證。因此本輪不做網路潮流，把「網路友善」保持在論文自己的口徑：聚合進口尖峰。

## 選項

- A：LV 變壓器／潮流約束。新穎但非參與戶負載與饋線參數不在公開資料內，結論會建立在無法核實的假設上。
- B：把 Peak Guard 從單點推廣成完整的帳單—尖峰 Pareto 前緣（ε-constraint），加上一個「先省錢、再壓尖峰」的字典序策略找出零代價的尖峰抑制量，並用加權法（需量電價）證明前緣與電價設計的等價。全部只用既有的 MILP 與聚合口徑，可獨立驗證。
- C：滾動預測 MPC。重要但需要預測模型與逐時重解，工作量大且是「評估論文上界」而非「更好的策略」。
- D：實測效率重新校準（71.73% 對模型 90.25%）。門檻最低、一定有結果，但單獨做只是敏感度。

## 決定與理由

主線採 B，副線採 D 的典型日版本；A 與 C 列為未來工作。

理由：B 直接回答論文自己留下的兩個問題（一個框架內兼顧三方；電價設計），把既有 Peak Guard 變成前緣上的一個點而不是取代它；所有新結果都與凍結的 formal／Peak Guard 基準成對呈現。D 用的是資料論文（第一篇）自己公開的量測，成本極低，且能量化「論文所有省錢率是樂觀上界」這個事實。

## 求解前凍結的定義（不得依結果回調）

固定口徑全部沿用 `B2022-IR-v1`：StoreNet 公開 2020 資料、20 homes／10 PV、`DC_SOURCE`、`xi=0.07`、每戶 10 kWh／3.3 kW、效率 0.95、SoC 10%–90%、初始／終端 10%、夜／日電價 0.091／0.194 EUR/kWh、日間 10:00–22:00、FIT=0。典型日 2020-08-24（30 分鐘）；月度沿用 Peak Guard 已配對的 45 個 2020 日（60 分鐘、`release_literal`、solver 60 秒上限）。

1. **P0**：每日的 PV 自用／無電池聚合進口尖峰（formal 的 `PvSelfNoBatteryPeakKW`），與 Peak Guard 的 cap 相同。
2. **新策略 `VPP_BM_PEAK_LEX`（bill → peak → throughput）**：第一階段最小化帳單；第二階段在帳單鎖定（既有 `lexicographicTolerance` 規則）下最小化全天聚合進口最大值；第三階段鎖定前兩者後最小化電池 throughput。它的帳單依構造等於 VPP-BM 的最佳帳單，因此 `VPP-BM 尖峰 − PEAK_LEX 尖峰` 定義為**零代價尖峰抑制量**。
3. **ε 前緣**：對比例 r，使用既有 `IMPROVED_PEAK_GUARD`，cap＝r·P0。典型日 r ∈ {3.0, 2.5, 2.0, 1.75, 1.5, 1.25, 1.1, 1.0, 0.95, 0.9, 0.85, 0.8, 0.75, 0.7, 0.65, 0.6, 0.55, 0.5}；月度 r ∈ {2.0, 1.5, 1.25, 1.0, 0.9, 0.8, 0.7, 0.6, 0.5}。不可行（intlinprog exit flag −2）記為 `infeasible`，不換 cap 重試。r＝1.0 必須重現凍結的 Peak Guard 帳單（相對誤差 ≤ 1e-6），作為一致性閘門。
4. **需量電價策略 `VPP_BM_DEMAND_CHARGE`**：第一階段最小化 `bill + λ·max_k import_k`（λ 單位 EUR/kW/日），第二階段鎖定後最小化 throughput。典型日 λ ∈ {0.02, 0.05, 0.1, 0.2, 0.3, 0.5, 1, 2}；月度 λ ∈ {0.05, 0.1, 0.2, 0.5, 1.0}。判讀口徑：每日「使尖峰 ≤ P0 的最小 λ」與各 λ 下的 (bill, peak) 是否落在 ε 前緣上（加權法只能取得 supported points，位於前緣上方的差距如實報告）。
5. **邊際成本（影子價格估計）**：相鄰兩個可行 r 之間的 `Δbill / Δpeak`（EUR/kW）；不對 MILP 宣稱精確對偶值。
6. **膝點**：在 (peak, bill) 平面上，把可行前緣點在 x、y 各自正規化到 [0,1] 後，取到「兩端點連線」距離最大的點（最大弦距法）。這是事前固定的機械規則，不是看圖挑選。
7. **實測效率敏感度（副線，典型日）**：由公開 Wh 檔 2020 全年 20 戶 `Charge/Discharge` 加總得到的有效往返效率 30153.2／42035.5＝0.7173（含待機與自放電；逐戶 0.588–0.757）。模型設 `etaBatteryCharge = etaBatteryDischarge = sqrt(0.7173) = 0.8469`，其餘不變；策略：SH-BM、VPP-BM、VPP_BM_PEAK_LEX、PS、PSDT、LL、Peak Guard(r=1)。只報「論文參數 vs 實測校準」的成對差異，不宣稱這是電芯效率。
8. **月度彙總**：主口徑為各 r 下「該 r 全部可行之日」的 summed-cost 犧牲（與 formal／Peak Guard 一致）；另報逐日百分點平均與可行日數。零代價抑制量以 45 日逐日成對報告。
9. **VPP-BM 與 PS 在本輪重新求解**（典型日與 45 日），並與凍結 formal 值比對（帳單、尖峰相對誤差 ≤ 1e-6）；這是環境一致性檢查，不覆寫任何凍結目錄。

## 非目標

- 不做配電潮流、變壓器或電壓限制；「尖峰」始終指聚合進口。
- 不做預測誤差／滾動 MPC、電池老化成本、饋網電價、DS3 服務。
- 不重跑、不修改 `results/b2022_ir_v1_formal` 與 `results/bahloul_vpp_improvement_v1`。
- 不改 cohort、PV 邊界、`xi`、電價或 SoC 規則；不以任何新結果回調上述網格。

## 代價／風險

- 加權法在 MILP 上可能漏掉非 supported 的前緣點；用 ε 前緣為主、λ 掃描為輔。
- 月度 60 秒 solver 上限在緊 cap 下可能提前停止；gap > 1e-4 的點標記 `time_limited`，不納入邊際成本計算但保留在表中。
- 「零代價」依賴字典序容差 1e-7；報告時同時給出兩策略帳單差的實際數值。

## 何時重新檢視

- 若取得非參與戶負載或饋線模型，A（網路約束）應重新排入。
- 若使用者要求把改進推向論文投稿，C（預測不確定性）是下一個必補的缺口。
