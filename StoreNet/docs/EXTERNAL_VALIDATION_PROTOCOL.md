# StoreNet 外部效度與模型改進預註冊

狀態：**在查看任何 Ausgrid 最佳化結果前凍結**。

來源說明勘誤（2026-09-05）：第 2.1 節原「雙來源位元比對」無法由已保存的取得紀錄支持，改為兩份本地副本的一致性檢查；第二份副本的網址與日期仍缺失。此勘誤不更動研究問題、資料選取或實驗判準。詳見 [來源核對](../../01_論文/Ausgrid_資料取得來源核對_2026-09-05.md)。

## 1. 研究問題

本階段不重寫已封存的 StoreNet 復現，也不以另一個資料集重新調參。問題分成三個：

1. 原始 `VPP_BM` 與 `IMPROVED_PEAK_GUARD` 能否在澳洲住宅 load/PV 分布上產生可行、物理一致的排程？
2. Peak Guard 是否在每個事前選定月份都把 aggregate import 限制在無電池 PV-self-consumption 基準峰值內，同時保留正的帳單節省？
3. 單一 hard cap 是否掩蓋成本–尖峰折衷？以事前固定的 ε-constraint cap grid 形成 Pareto frontier 回答，不按結果移動網格。

`reproduction-v1.0` 保持不動；所有新增內容位於 `external-validation` 分支。

## 2. 文獻與資料集篩選

### 2.1 資料集

| 資料集 | 優點 | 主要限制 | 本階段判斷 |
|---|---|---|---|
| [Ausgrid Solar Home](https://data.gov.au/data/en/dataset/nsw-solar-home-electricty-data) / [Ratnam et al.](https://doi.org/10.1080/14786451.2015.1100196) | 300 戶、三年、30 分鐘、gross load 與 gross PV 分開實測 | 舊官方下載失效；solar adopters 非全住宅代表樣本 | **主 benchmark**；最接近 canonical input；兩份本地副本的年度 CSV 與說明 PDF 一致，第二份取得來源未記錄 |
| [PTProsumer, Madeira](https://www.nature.com/articles/s41597-025-06118-x) | 24 prosumers、1 秒、跨國島嶼環境、獨立 PV meter | 約 38.9 億點；主電表是 net-load，需符號重建；各站 coverage 不同 | 第二階段最強 cross-country extension；本輪不以大下載拖延首個外部結論 |
| [Dingle Ambassadors 2026](https://www.nature.com/articles/s41597-026-07186-3) | 4 戶、PV／電池／EV／熱泵／電價，同為 Dingle 但獨立專案 | 同國不是地理外推；既有電池動作若未完整移除會 double count | 適合作物理資料流 double-check，不作本輪主要外部績效證據 |
| [HEMStoEC](https://www.nature.com/articles/s41597-024-03184-5) | TH1 有實測 PV、11.5 kWh 電池、SoC 與高解析電力 | 四戶中只有 TH1 有完整 PV+battery；資料約 31 GB | 未來電池方程 sanity check |
| [OPSD CoSSMic](https://data.open-power-system-data.org/household_data/2020-04-15/) | 德國、多解析度、部分住戶有 PV／export | 只有 3–4 個可重建 PV 住宅；官方處理含線性／前日補值 | 小樣本 fallback，不作首選 |
| [Pecan Street Dataport](https://www.pecanstreet.org/access/) | 大量美國住宅、PV 與細分負載 | 完整存取需帳號／DUA，商業情境可能付費 | 不符合無障礙公開復現首輪 |

### 2.2 更強模型

沒有一個模型在所有 KPI 上絕對「更好」。成本-only dispatch 可能把低價充電同步成新尖峰；外部 peak 或 network value 必須顯式進入問題。Forrester 等人的大樣本住宅研究亦指出，私人帳單價值不必然轉成電網價值（[iScience / open artifacts](https://escholarship.org/uc/item/2h73w8kj)）。

本階段選擇 **ε-constraint peak frontier**，原因是：

- 不需要額外預測、網路拓撲或市場投標資料；
- 完全沿用已測試的 MILP 物理限制；
- cap 是可審計的物理量，不依賴任意 cost/peak 加權；
- 多目標 community-storage 文獻已用 MILP／Pareto frontier 顯示 arbitrage 與 peak shaving 的折衷（[Applied Energy 2019, DOI 10.1016/j.apenergy.2019.01.227](https://doi.org/10.1016/j.apenergy.2019.01.227)）。

下列方法保留到後續，不能在缺少輸入時冒充已驗證改進：

- 線性 throughput/degradation cost：可做敏感度，但單一真實退化係數未識別。
- max-min individual-rational bill allocation：適合公平性，但先與物理 dispatch 分開。
- rolling MPC／scenario MPC：需要凍結 forecast baseline 與 closed-loop 評估；不能拿 perfect foresight 數值直接比較。
- network-constrained OPF、DRO market bidding、DRL：目前資料沒有 feeder topology、投標規則或足夠訓練／評估契約。

## 3. 凍結資料契約

完整規格在 [`ausgrid_2012_2013.json`](../config/crossenv/ausgrid_2012_2013.json)，資料卡在 [`AUSGRID_DATASET_CARD.md`](./AUSGRID_DATASET_CARD.md)。重點為：

- 使用論文 clean cohort，事前排除有 81 天缺列的 Customer 2，固定 53 戶。
- `load = GC + optional CL`，`PV = GG`。
- 只接受空白 `Row Quality`；不插值、不補 0，任一戶不合格即拒絕整日。
- 30 分鐘 kWh 轉成平均 kW；時間一律為 interval-end naive local wall clock。
- `GG` 是 AC gross PV，因此 `etaPvAC=1.0`；其餘為固定 StoreNet policy transfer。

## 4. 事前選日

主結果每個 calendar month 選一個 robust central day，共 12 日：

1. 只在通過資料契約的日子中選擇。
2. 對每一天建立 96 維向量：48 個 aggregate load + 48 個 aggregate PV。
3. 在該月內對每一維以 median 與 MAD 標準化；MAD 為 0 的維度以 1 代替。
4. 計算候選日到 component-wise median profile 的均方根距離。
5. 選最小分數；同分取最早日期。

選擇函式不得呼叫 solver，也不得讀取任何 savings／peak 結果。March、June、September、December 的四個月代表日另用於季節 frontier。

## 5. 實驗

### 5.1 Primary fixed-policy transfer

每個月代表日依固定順序執行：

1. `SH_BM`
2. `VPP_BM`
3. `IMPROVED_PEAK_GUARD`，cap 在最佳化前由無電池 PV-self-consumption 基準峰值決定

所有策略使用每戶 10 kWh／3.3 kW、相同初末 SoC、零 FIT 與 StoreNet 兩段價。報告的 EUR 欄名只是既有 evaluator schema；它代表固定價格下的比較單位，不是歷史澳洲帳單。

### 5.2 Seasonal ε-frontier

先以 `PS` 求可達最低 aggregate peak `P_min`，以無電池基準取得 `P_0`。對每個季節代表日固定求解：

`cap(alpha) = P_min + alpha * (P_0 - P_min)`，其中 `alpha = [1, 0.75, 0.5, 0.25, 0]`。

每一點都以 `IMPROVED_PEAK_GUARD` 在 cap 下最小化 bill，再以 throughput 作 lexicographic tie-break。若 `alpha=0` 因數值容差不可行，只能使用預先凍結的 `1e-6 kW` feasibility allowance，且 manifest 必須同時保存 requested 與 effective cap；不能移動其他網格點。

## 6. KPI 與判定

每個成功列至少保存：bill、savings%、aggregate peak、daytime peak、import spread、grid import、shared export、curtailment、battery throughput、solver exit flag、wall time、能量平衡殘差、terminal SoC 誤差與 simultaneous charge/discharge。

數值驗收：

- `energyBalanceResidualKW <= 1e-6`
- `terminalSocErrorKWh <= 1e-6`
- `simultaneousChargeDischargeKW <= 1e-7`
- `peakImportKW <= effectiveCapKW + 1e-6`
- solver exit flags 全部大於 0

只有同時符合下列條件，才稱第一階段「跨環境穩健」：

1. 12/12 月代表日的三個 primary strategies 均數值可行；
2. Peak Guard 12/12 都不超過事前無電池 peak cap；
3. Peak Guard savings 的 median 與第一四分位數都大於 0（至少約四分之三月份為正）；
4. Peak Guard 相對 VPP_BM 的 paired median peak change 為負；
5. 四個季節 frontier 的 peak 隨 cap 收緊不增加，bill 不出現超過數值容差的反向改善。

若未通過，結果仍保留並報告，不改日子、cohort、cap 或參數來挽救結論。即使通過，也只能主張「固定政策、完美預見、無網路模型下的資料分布外推」，不能主張澳洲實際市場、閉迴路控制或配電安全已驗證。

## 7. 測試與 Git 門檻

- 新增 class-based MATLAB unit／integration tests；測試方法內不放條件分支。
- 真實資料 slow test 必須重現 53 戶、359 通過日與 6 個拒絕日。
- 新舊測試全通過後，對所有 `.m` 執行 MATLAB Code Analyzer。
- 每一階段以獨立 Git commit 保存；正式外部結果使用新 tag，不移動 `reproduction-v1.0`。
