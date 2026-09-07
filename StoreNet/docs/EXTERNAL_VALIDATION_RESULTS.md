# StoreNet 跨環境驗證、模型選擇與資料雙重檢查

## 結論先行

主實驗通過事前凍結的全部驗收門檻：在 Ausgrid 2012–2013 的 53 戶固定 cohort、12 個 outcome-independent 月代表日上，36/36 個 primary、4/4 個 PS reference 與 20/20 個 epsilon-frontier 求解列均為 `ok`；`overallCrossEnvironmentRobust=true`。

這支持一個有限但重要的結論：固定 StoreNet 電池與價格政策不重新調參時，`IMPROVED_PEAK_GUARD` 在不同國家、不同住宅 load/PV 分布下，仍能把 aggregate import 約束在無電池基準尖峰 `P0` 內，並保留正的固定政策帳單節省。

它不構成「所有環境普遍有效」、澳洲歷史帳單、閉迴路部署或配電網安全證明。正式主張應寫成：

> 在事前凍結的 fixed-policy、perfect-foresight、無配電網模型之反事實設定下，StoreNet 與 Peak Guard 在 Ausgrid 53 戶 cohort 的 12 個事前代表日通過第一階段跨資料分布數值門檻；排除 Customer 161 的 post-hoc 52 戶敏感度亦通過，但仍只是一個外部資料集與一個 cohort family 的證據。

## 1. 為何先選 Ausgrid，而不是直接換成更複雜模型

[Ausgrid 資料論文](https://www.tandfonline.com/doi/abs/10.1080/14786451.2015.1100196)提供 300 個去識別 solar customers、3 年、30 分鐘解析度、分開量測的住宅負載與 gross PV；[澳洲政府 metadata](https://data.gov.au/data/en/dataset/nsw-solar-home-electricty-data)仍保留官方資料說明與 CC BY 3.0 AU 授權。這是目前最接近 StoreNet solver 所需 `load + PV` 邊界、又能跨國測試的公開論文級資料。

本輪先保留原 MILP、storage 與 tariff policy，改資料 adapter；唯一 measurement-boundary normalization 是因 Ausgrid `GG` 已為 inverter-AC，將 `etaPvAC` 設為 1，避免重複扣轉換損失。理由是先回答最小且可識別的問題：「原模型與 Peak Guard 是否能在另一種 load/PV 分布下工作？」若同時改成 DRL、MPC、不同 tariff 與不同電池，成功或失敗都無法歸因。

### 1.1 已篩選的其他論文級資料

| 資料 | 規模與訊號 | 判斷 | 本輪處置 |
|---|---|---|---|
| [Ausgrid](https://www.tandfonline.com/doi/abs/10.1080/14786451.2015.1100196) | 300 戶、3 年、30 min；load 與 gross PV 分開 | 與現有 solver 輸入最接近，戶數足以做 community counterfactual | 正式外部驗證已完成 |
| [Dingle 2026](https://www.nature.com/articles/s41597-026-07186-3) | 愛爾蘭 4 戶；grid/PV、電池、EV、熱泵與 tariff；battery/heat-pump telemetry 只涵蓋最後約 6–8 個月 | 同國家且有完整設備組合，適合有限重疊期 telemetry sanity check；戶數小、設備邊界不同 | 第二階段優先候選 |
| [PTProsumer](https://www.nature.com/articles/s41597-025-06118-x) | Madeira 24 prosumers、最高 1 s、3 個月至 5 年以上，約 38.9 億點 | 高解析與長期性很強；net-load 重建、異質場域與資料量需要獨立 adapter/cache | 第二階段 seasonal/OOD 候選 |
| [HEMStoEC](https://doi.org/10.1038/s41597-024-03184-5) | 葡萄牙 4 戶、2020–2023；只有 TH1 同時有 PV、11.5 kWh battery 與 inverter/SoC telemetry | TH1 可做實體 battery/SoC sanity check，但只是單戶；四戶共同重疊期也只有 2021-11 至 2022-07 | 先做單戶、有限重疊期 telemetry check |

這些資料不是拿來「挑一個容易過的環境」。Ausgrid 先執行是因為輸入邊界最接近；Dingle／HEMStoEC 則保留給需要實體 battery truth 的不同問題。

## 2. 「更好的模型」判斷

### 2.1 本輪採用：epsilon-constraint MILP

主模型保持原 StoreNet MILP，另以 PS 求得技術最低尖峰 `Pmin`，對四個季節月固定求解：

```text
cap(alpha) = Pmin + alpha * (P0 - Pmin)
alpha      = 1, 0.75, 0.5, 0.25, 0
```

這是成本—尖峰的 epsilon-constraint sweep。它的優點是：

- 與原模型共享同一物理邊界，結果差異可歸因於 cap。
- 每個點都是可審計的 MILP，不需要訓練資料或 reward tuning。
- 可直接顯示季節異質性，不把一個任意加權係數冒充普遍最佳解。
- 有 community-storage 多目標 MILP 的方法學先例；例如 [Applied Energy 的 CES 研究](https://doi.org/10.1016/j.apenergy.2019.01.227)以 operation cost 與 CO2 建 Pareto frontier，另用 grid absorption/injection bounds 定義 peak-shaving 情境。其目標與本案 bill–peak epsilon-frontier 不同，不能當成相同 benchmark。

注意：五個 alpha 不保證五個嚴格不同的 Pareto-optimal 點。主實驗的 3 月部分點等價，9 月因 `P0=Pmin` 而五點退化成同一點。

### 2.2 尚不能宣稱較好的候選

| 模型類型 | 論文證據 | 可能優點 | 為何本輪不直接替換 |
|---|---|---|---|
| DRL（DQN/DDPG/TD3） | [Applied Energy 2024](https://doi.org/10.1016/j.apenergy.2024.123163)在不確定 load/PV/price 下比較多種 DRL 與 rule control | 可做線上控制、免每日 MILP | 任務、價格與評估基準不同；需要 train/validation/OOD 切分與多 seed，論文百分比不能直接對比本專案 |
| Hybrid heuristic + RL | [Applied Energy 2024](https://doi.org/10.1016/j.apenergy.2023.122244)報告在 residential BTM PV-battery 上優於多個 RL、rule 與 stochastic baseline | 可降低純 RL 訓練不穩定 | 仍需重建其 state/action/reward 與 utility policy；不是相同 StoreNet community sharing 問題 |
| Robust／stochastic optimization | [Applied Energy 的 smart-home aggregator robust optimization](https://doi.org/10.1016/j.apenergy.2018.07.120)納入 price、PV、load 不確定性與 nonlinear battery aging | 對 forecast error、market participation 與退化更接近部署 | 現有實驗是 perfect foresight；先建立 chronological、leakage-free forecast baseline 與事前校準的 forecast-error scenarios／uncertainty sets 才能公平比較 |
| MARL/value stacking | [Applied Energy 2026](https://doi.org/10.1016/j.apenergy.2026.127967)使用 200 戶澳洲 load/PV profiles 模擬、假想 8 kWh/4 kW 電池，並混用 PJM frequency regulation 與 Pennsylvania tariff | 可擴展偏好一致性與多服務 | 它改變市場、設備、服務與目標，不是同一 peak/bill KPI，也不是公平性外部實證；適合作為後續研究問題 |

因此目前最準確的判斷不是「MILP 一定優於 DRL」，而是：epsilon-constraint MILP 是本輪最可識別、可重現的改進。Head-to-head 時，所有模型需共用 chronological split、tariff、物理限制與 peak KPI；learning models 另需多 seed，MILP／MPC／robust models 則需報 forecast/scenario 或 uncertainty-set sensitivity、solver gap 與 runtime。

## 3. Ausgrid 資料契約與 provenance

### 3.1 原始語義

- 每列含 48 個半小時 energy 值，單位是 `kWh/interval`；模型先除以 `0.5 h` 轉成平均 `kW`。
- `GC` 是一般用電且排除 PV／controlled load；`CL` 是 off-peak controlled load；`GG` 是 separately metered gross PV。
- canonical `load = GC + optional CL`，`PV = GG`；不是 net load，也不是 grid import。
- `Row Quality` 空白表示該列為 meter actual；非空列會使整個 community-day 被拒絕，不插值。
- 48 個時間標籤按 release 的 Sydney local wall clock 與 interval-end 語義處理；沒有 UTC offset，不能重建真實 DST 23/25 小時日。
- `GG` 已是 inverter-AC gross generation，因此固定 `etaPvAC=1.0`，避免重複扣 inverter loss。

官方 notes 與實際 v2 CSV 有兩處 schema 差異：notes 把 `Postcode`／`Generator Capacity` 欄序寫反，日期格式寫為 `DDMMMYYYY`；實際 CSV header 與日期為 `Generator Capacity`、`Postcode` 及 `d/MM/yyyy`。adapter 按實檔 header 與實際日期解析，不按 notes 的示意順序硬編碼。

### 3.2 檔案與獨立稽核

- 年度 CSV SHA-256：`e4be46b3c9991c65735a9545319a2f1c33be8e639c75a17a88e0323a8e5098be`。
- 本次使用 2026 preservation mirror；兩份本地 archive copies 的 CSV 與 notes PDF 已逐位元一致，但 repo 沒有保存第二份 archive 的來源 URL／取得日期，因此不能把它們稱為兩條可重現的獨立來源，也不能寫成「2026 直接從舊 Ausgrid 官網下載」。
- raw 年度檔共 268,557 rows。
- MATLAB 與只使用 Python 標準庫的獨立 parser 對 source hash、日數、拒絕日、代表日與候選數一致；主實驗 selector score 最大差 `2.22e-15`，52 戶敏感度最大差 `2.89e-15`。

### 3.3 Cohort 與 Customer 161 限制

資料論文指出 2012–2013 單年有 187 戶可進 year-specific clean set。本專案依論文提供的三年 clean 54 戶清單，再於最佳化前排除缺少 81 天 GC/GG 的 Customer 2，得到事前固定 53 戶。這是保守 cohort，不是一般澳洲住宅的隨機代表樣本。

主實驗有 359 日「通過凍結契約」、6 日因 `row_quality` 拒絕。這不能寫成 359 個「完整實測總負載日」：Customer 161 在 `2013-02-01` 至 `2013-03-31` 沒有 CL rows，2 月與 3 月代表日位於其中；凍結契約把 optional CL 缺列解讀為 0。為避免只用文字淡化此問題，另做了完整排除 Customer 161 的 52 戶 post-hoc sensitivity，結果見第 6 節。

## 4. 預註冊實驗設計

### 4.1 固定政策

每戶假想配置 10 kWh／3.3 kW 電池；charge/discharge efficiency 0.95，sharing loss 0.07。價格沿用 StoreNet：night 0.091、day 0.194、day window 10:00–22:00、FIT=0。

CSV 中的 `EUR` 是既有 evaluator schema 的固定比較單位，不是 2012–2013 NSW tariff、FIT 或澳洲住戶歷史帳單。

### 4.2 外生代表日

對每個通過契約的日期，先跨戶加總成 48 點 load 與 48 點 PV，共 96 維；逐月用 coordinate-wise median/MAD 標準化，zero MAD 改為 1，再以到逐維 median profile 的 RMS 距離選最中央日，同分取較早日期。ranking 不含 solver、bill、saving、dispatch 或 peak outcome。

### 4.3 面板與驗收

- Primary：12 月 × `SH_BM`、`VPP_BM`、`IMPROVED_PEAK_GUARD` = 36 列。
- Reference：3、6、9、12 月各一個 PS = 4 列。
- Frontier：4 月 × 5 alpha = 20 列。
- 獨立 evaluator 由 solution flows 重算 bill、peak、balance、terminal SoC 與 simultaneous charge/discharge，不採信 solver wrapper 回報的 metrics。
- Gate 是 fail closed：列數／schema、所有列可行、Peak Guard cap、median/Q1 savings、paired median peak、frontier requested cap／peak／bill 單調性均須通過。

正式主 run 的 solver code commit 為 `f602e77c39725f20ef7d2468ab8e7ca614748cf2` 且 tracked tree clean；Python kWh→kW 稽核修正在 `6d3bf32`。敏感度 run 的 clean code commit 為 `7bf3bf51d8ce8a71cbb1dd06642a579790fcbdaf`。

## 5. 53 戶主實驗結果

### 5.1 Primary 策略摘要

| 策略 | Median savings | Q1 savings | Median peak/P0 | Max peak/P0 | 超過 P0 月數 |
|---|---:|---:|---:|---:|---:|
| SH-BM | 45.6127% | 37.0284% | 1.5930 | 2.0119 | 9/12 |
| VPP-BM | 60.8286% | 47.5110% | 1.0219 | 2.3205 | 6/12 |
| Peak Guard | 60.8286% | 47.5110% | 1.0000 | 1.0000 | 0/12 |

Peak Guard 與 VPP-BM 的 bill 最大差約 `6.0e-13` schema currency unit，可視為數值等價；但它不是逐月 pointwise dominance：相對 VPP peak 為 6 個月份較低、5 個月份相同、1 個月份較高。唯一較高的是 1 月，高 `1.292 kW`，但仍低於 `P0`。paired median peak delta 為 `-1.293915 kW`。

最極端的成本-only VPP 是 6 月：`207.482 kW`，對照無電池 `P0=89.412 kW`，即 `2.3205×`。Peak Guard 把它限制回 `89.412 kW`，且該月主 cap 下的 bill 與 VPP 數值相同。

### 5.2 季節 epsilon-frontier

| 月份 | P0 | Pmin | 技術可降幅 | alpha=0 相對 alpha=1 bill premium | Savings 變化 |
|---|---:|---:|---:|---:|---:|
| 3 月 | 53.152 kW | 42.915 kW | 19.259% | 0.086% | -0.0278 pp |
| 6 月 | 89.412 kW | 64.304 kW | 28.081% | 13.696% | -8.7425 pp |
| 9 月 | 61.610 kW | 61.610 kW | 0% | 約 0% | 約 0 pp |
| 12 月 | 59.776 kW | 45.581 kW | 23.747% | 0.114% | -0.0598 pp |

20/20 frontier 點通過 cap；16/16 相鄰 requested-cap、peak 與 bill monotonic comparisons 通過。結論是明確的季節異質性：3 月、12 月有近乎免費的額外削峰，6 月代價高，9 月沒有技術 peak range。因此不能從四天挑出一個「全年最佳 alpha」。

### 5.3 數值與物理檢查

- 全 60 列最大模型內部 energy-balance residual：`7.0679e-12 kW`，門檻 `1e-6 kW`。
- terminal SoC error：0。
- simultaneous charge/discharge：0。
- minimum exit flag：1。
- 總 wall time：`1151.04 s`；最長單列約 `56.93 s`。

## 6. 排除 Customer 161 的 52 戶 post-hoc sensitivity

這一輪不修改主實驗，也不重新定義其事前通過門檻。它只回答：把 CL-gap 戶完全排除後，結論是否消失？同一 selector 在 52 戶上重算，因此 1 月由 `2013-01-21` 改為 `2013-01-25`，6 月由 `2013-06-05` 改為 `2013-06-26`；其餘 10 個月相同，包含 CL-gap 內的 2 月與 3 月。

| 指標 | 53 戶主實驗 | 52 戶 sensitivity | 判讀 |
|---|---:|---:|---|
| Contract-pass days | 359 | 360 | 移除 Customer 161 後少一個 row-quality rejection |
| Solver rows | 60/60 ok | 60/60 ok | 可行性未依賴 Customer 161 |
| Peak Guard cap | 12/12 | 12/12 | 核心 safety constraint 保持 |
| Peak Guard median savings | 60.8286% | 60.5393% | -0.2893 pp |
| Peak Guard Q1 savings | 47.5110% | 47.2240% | -0.2870 pp |
| Paired median PG−VPP peak | -1.2939 kW | -0.8933 kW | 仍為改善，但幅度較小 |
| VPP／Peak Guard 超過 P0 | 6/12／0/12 | 6/12／0/12 | 結構結論不變 |
| Frontier monotonic | 16/16 | 16/16 | 結果保持 |

在相同日期的兩個直接敏感月：

- 2 月 Peak Guard savings 改變 `-0.7765 pp`，peak 改變 `-0.200 kW`。
- 3 月 Peak Guard savings 改變 `+0.1051 pp`，peak 改變 `-0.176 kW`；alpha=0 bill premium 由 `0.0862%` 變為 `0.0886%`。

因此，排除整個 Customer 161 後，headline gates 仍然通過；這降低了結論完全依賴該戶的疑慮，但沒有重建未知 CL，也不能驗證「缺失 CL 等於 0」本身正確。主 run 的 359 日仍必須稱為「通過凍結契約」，不能改寫成所有 load components 完整觀測；52 戶結果也必須標示 post-hoc，不能冒充事前分析。

## 7. 與愛爾蘭 StoreNet 結果的比較

愛爾蘭公開版代表日中，VPP-BM savings 為 `41.2621%`，peak 為 `75.5008 kW`，對無電池 `P0=17.9362 kW` 約 `4.21×`；Peak Guard 把 peak 降回 `P0`，但 savings 降到 `38.2196%`，代價 `3.0425 pp`。

Ausgrid 主實驗的 Peak Guard median savings 是 `60.8286%`，且對 VPP-BM 沒有可量測 bill penalty；VPP 最大 peak/P0 為 `2.3205×`。這顯示 safety cap 可移植，但成本代價依環境／季節而變。

兩者的 savings 絕對值不能做國家績效排名：戶數（20 vs 53）、PV adoption、日期、價格與 cohort 均不同，Ausgrid 又沿用 StoreNet 假想價格。

## 8. 可宣稱與不可宣稱

### 可宣稱

- 固定 StoreNet policy 不重新調參，在一個澳洲實測 load/PV dataset 上仍能產生物理可行排程。
- Peak Guard 在主 run 與 no-161 sensitivity 均 12/12 遵守 ex-ante `P0` cap。
- 成本-only VPP 在兩輪均有 6/12 月超過 `P0`，故夜間新尖峰不是只出現在愛爾蘭代表日。
- Epsilon sweep 顯示成本—尖峰 trade-off 有明顯季節異質性。

### 不可宣稱

- 澳洲住戶實際可省約 60%；這只是固定 StoreNet 價格下的 schema-unit counterfactual。
- 已驗證全澳洲、全年或所有住宅；只有 solar-adopter cohort 與每月一個 central day。
- aggregate cap 等於配電安全；資料沒有 feeder topology、phase、voltage、thermal limit 或背景負載。
- 已驗證閉迴路控制；目前仍是 perfect foresight、每日 terminal SoC，沒有 forecast error、rolling horizon 或跨日狀態。
- 已驗證實體電池效果；Ausgrid 沒有 battery/SoC/control truth，10 kWh／3.3 kW 是反事實配置。
- Peak Guard 在每月逐點支配 VPP；主 run 有一個月 peak 較高，雖仍在 `P0` 內。

## 9. 後續優先順序

1. 用 Dingle 2026 的有限重疊期或 HEMStoEC 的 TH1 單戶 battery/SoC telemetry 做「假想 dispatch 對實體控制」sanity check。
2. 建立 day-ahead load/PV forecast 與 rolling-horizon baseline，再比較 deterministic MILP、robust MILP、MPC 與 DRL。
3. 所有 learning model 固定 chronological train/validation/test、至少多 seed，並同時報 bill、peak/P0、cap violation、battery throughput、runtime 與 OOD degradation。
4. 取得 feeder topology 後才加入 voltage／thermal constraints；在此前只稱 aggregate peak proxy。
5. 擴展 cohort bootstrap 或多個隨機社群，報 confidence interval，而不是只靠一個 central-day panel。

## 10. 重跑與正式輸出

主 run：`results/external_validation_ausgrid_2012_2013_v1/`。

Post-hoc sensitivity：`results/external_sensitivity_ausgrid_exclude_customer161_v1/`。

從專案上層 `/Users/guichenxiang/Desktop/電力專案` 執行，使用新的 `RunId`，不要覆寫正式目錄：

```bash
shasum -a 256 -c StoreNet/data/AUSGRID_MANIFEST.sha256
python3 StoreNet/src/audit_ausgrid.py --output independent_data_audit.json
/Applications/MATLAB_R2026b.app/bin/matlab -batch \
  'addpath("StoreNet/src"); run_external_validation(RunId="rerun_external_main")'

python3 StoreNet/src/audit_ausgrid.py \
  --spec StoreNet/config/crossenv/ausgrid_2012_2013_exclude_customer161_sensitivity.json \
  --output independent_data_audit_no161.json
/Applications/MATLAB_R2026b.app/bin/matlab -batch \
  'addpath("StoreNet/src"); run_external_validation( ...
  SpecPath="StoreNet/config/crossenv/ausgrid_2012_2013_exclude_customer161_sensitivity.json", ...
  RunId="rerun_external_no161")'
```

結果轉譯器會先驗證 36+4+20 panel、日期、`P0`、型別、固定 alpha grid 與 manifest home count，三件 artifact 全部 stage 成功後才發布；失敗時 rollback：

```bash
/Applications/MATLAB_R2026b.app/bin/matlab -batch \
  'addpath("StoreNet/src"); render_external_validation( ...
  "StoreNet/results/rerun_external_main", FigureVisible=false)'
```

原始復現仍由 tag `reproduction-v1.0` 保留；外部 protocol 與 code 分別由 `external-validation-protocol-v1`、`external-validation-code-v1` 保留。正式結果需與同目錄 manifest、summary、selection、獨立 audit 與 SHA-256 result manifest 一起引用。
