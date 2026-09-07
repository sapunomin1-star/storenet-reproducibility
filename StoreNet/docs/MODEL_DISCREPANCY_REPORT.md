# StoreNet 模型差異與獨立復現報告

- 日期：2026-09-01
- 方法論文：Bahloul et al. (2022), DOI `10.1109/TSTE.2022.3187217`
- 公開資料論文：Trivedi et al. (2024), DOI `10.1038/s41597-024-03454-2`

本文件未另標「資料論文」的 Figure 5／6／7 均指 **Bahloul et al. (2022)**；Trivedi 圖號一律明寫作者名稱。

## 1. 報告定位與結論

本專案已完成下列兩件不同層次的工作：

1. 依照 2022 VPP 論文的方程結構，建立可執行、可測試且單位一致的「論文意圖模型」；
2. 在 2020 StoreNet Figshare 公開發布版上，完成五種論文策略的可重跑獨立比較，並在基準凍結後評估一個尖峰保護改進策略。

本報告**不宣稱 paper-equivalent、作者程式重建或原始數值精確復現**。2022 論文使用的是 2019-07 至 2020-06 的內部資料；2024 才發布的資料只有 2020 年，且住戶 PV 配置、典型日、商業控制器、求解器細節與部分參數定義均不完整。現階段最嚴謹的說法是：

> 在來源完整性已驗證的 2020 公開資料上，完成具差異留痕的 StoreNet VPP intended-model independent replication；Bahloul Figure 5、Figure 6、Table I 與 Figure 7 的數值級重現仍不可證實。

本報告的逐項依據可回查：

- [方程—程式追溯矩陣](./TRACEABILITY.md)
- [凍結的復現契約](./REPRODUCTION_CONTRACT.md)
- [資料與方法稽核](./AUDIT_AND_SCOPE.md)
- [代表日選擇決策](./decisions/ADR-001-typical-day-selection.md)
- [代表日全年度選擇排名](../results/typical_day_selection_2020/ranking.csv)
- [代表日機器可讀結果](../results/baseline_typical_20200824_v2/metrics.csv)
- [代表日執行 manifest](../results/baseline_typical_20200824_v2/manifest.json)

## 2. 兩篇論文與公開資料的關係

兩篇論文都來自愛爾蘭 Dingle Peninsula 的 StoreNet 示範案，也都描述 20 戶住宅與每戶 10 kWh／3.3 kW Sonnen 電池；但這不表示 2022 論文直接使用了目前公開的 2024 Figshare 檔案。

| 項目 | 2022 VPP 方法論文 | 2024 公開資料／本地發布版 | 對復現的影響 |
|---|---|---|---|
| 期間 | 2019-07 至 2020-06 | 2020-01 至 2020-12 | 缺少 2019 下半年，Bahloul Figure 6 的完整年度窗口不存在 |
| PV 戶數 | 9 戶 | 實際 10 戶有非零 PV | 原 9 戶身分未公布，無法建立相同配置 |
| PV 規模 | 論文稱每戶約 2.4 kW | 資料論文稱 2.0–2.2 kWp；README 又稱 2.4 kW | 容量與量測邊界無法完全對齊 |
| 資料狀態 | 研究團隊當時的內部量測 | 已重採樣、改名並部分插值的 processed release | 可驗證發布版，不能重建作者完整 raw-to-processed 鏈 |
| 控制器 | 含未公開的 Sonnen SB-SC | 只有量測輸出 | 可作觀察基準，不能重建演算法 |

本地 46 個發布項目已與 Figshare v1 的檔名、大小與官方 MD5 完整核對，另保存 SHA-256 manifest。這證明本地副本沒有搬運損壞，但不代表上游原始 logger 資料或作者處理環境已公開。

## 3. 方程歧義、修正與本專案解讀

### 3.1 共同能量模型

| 論文項目 | 原式歧義或問題 | 本專案的明確解讀 | 性質 |
|---|---|---|---|
| Eq. (1)–(2) PV 使用量 | 未被使用的 PV 去向沒有完整命名 | 顯式加入 `pvCurtailKW`，使可用 PV 等於各流向加棄光 | 等價線性化與可稽核化 |
| Eq. (3) PV AC/DC 分流 | 公開 `Production` 的實際量測邊界未證明 | 主分析暫視為 DC available：`PVhome/etaPvAC + PVgrid/etaPvAC + PVbattery/etaPvDC + curtailment = PVavailable` | 必要假設；AC available 必須另作敏感度 |
| Eq. (4)–(5) 充放電轉換 | 變數所在 AC/DC 邊界不夠直觀 | 充電與放電均轉成 battery-side DC power，再更新儲能量 | 明確化單位與轉換位置 |
| Eq. (6)–(7) 功率上下界 | 使用嚴格 `<`；當 binary 為 0 時會導致 `0 < P < 0` | 改為 inclusive `<=`，最小充／放電功率設為 0 | 使模型閉合且可求解 |
| Eq. (8) 互斥 | 同一時段不可充放電的意圖清楚 | 保留每戶、每時段 charge/discharge binary，限制兩者和不超過 1 | 直接實作 |
| Eq. (9) SoC 動態 | 求和索引寫成 `k`；把功率時間量直接加到百分比 SoC；`P_SD` 無數值 | 狀態改用 kWh：`E(t+1)=E(t)+dt*(PchargeDC-PdischargeDC)`；self-discharge 基準設 0 | 維度修正與未公開參數處置 |
| Eq. (10) SoC 範圍 | 使用嚴格不等式 | 以 1–9 kWh inclusive bounds 表示 10%–90% | 數值可行化 |
| Eq. (11)–(12) 住宅平衡 | Eq. (12) 可由完整平衡與流量非負推出 | 保留完整 home balance；不重複加入冗餘式 | 不改變可行集合 |
| Eq. (13) VPP aggregate import | `xi` 在正文像戶間傳輸損失，附錄卻標成 `7%/day` | 基準將 `xi=0.07` 明示視為無因次 transfer-loss 假設；另規劃 `xi=0` 敏感度 | 非唯一解讀，不冒充物理定論 |
| Eq. (14) 社區淨輸出 | 使用嚴格正值限制 | 改為 aggregate import `>=0`；FIT=0 時不允許社區淨輸出 | 邊界修正 |
| Eq. (15) 終端 SoC | 三索引記號不清楚 | 每戶最後一個狀態回到 1 kWh，與起始狀態相同 | 明確化 horizon 邊界 |

模型中使用的主要彙總式為：

```text
aggregateImport(t)
  = sum_h[gridToHome + gridToBattery
          - (1-xi)*(pvToGrid + batteryToGrid)]
  >= 0
```

所有帳單均使用：

```text
bill = sum_t price(t) * aggregateImport(t) * dtHours
```

論文目標式未明寫的 `dtHours` 已補上；固定時間步下雖不改變最優解排序，但會決定帳單是否具有正確的 euro 單位。

### 3.2 各策略目標式

| 論文項目 | 問題或歧義 | 本專案實作 |
|---|---|---|
| Eq. (16), SH-BM | 目標式漏列 PV-to-home，與住宅能量平衡及文字意圖不一致 | 由完整 home balance 恢復 PV 自用；禁止 PV／battery 對社區輸出；最小化各戶帳單總和 |
| Eq. (17), VPP-BM | 帳單缺少 `dt`；相同夜價與零價棄光會產生許多同成本解 | 允許社區虛擬分享；先求最低 bill，鎖住 bill 後最小化 battery throughput |
| Eq. (18)–(19), PS | 對 maximum 的嚴格界線不可直接實作；最小尖峰後仍有大量等價解 | 第一階段最小化全天 aggregate peak；第二階段鎖 peak 後最小 bill；第三階段鎖 bill 後最小 throughput |
| Eq. (20)–(22), PSDT | 日間時間邊界與 timestamp 端點未完整說明；主目標以外的行為不唯一 | 第一階段最小化 `[10:00,22:00)` peak，其後依序最小 bill、throughput |
| Eq. (23)–(24), LL | maximum／minimum 界線使用嚴格不等式；spread 最優解不唯一 | 第一階段最小化全天 `max(import)-min(import)`，其後依序最小 bill、throughput |

詞典序後續階段是本專案的確定性與退化解處置，**不是原論文新增公式**。第一階段 optimum 會獨立保存，後續階段不得讓原主目標惡化超過固定容差。

SH-BM、VPP-BM 的 throughput 次目標可以排除無謂的電池循環，但在同一平價時段內仍可能存在「相同 bill、相同 throughput、不同充電時點」的等價排程。因此，非主目標的瞬時尖峰不應被解讀為論文唯一預測；正式 manifest 會保存 solver、版本、容差與執行狀態。

## 4. 參數與時間解讀

| 參數 | 本專案基準 | 歧義處置 |
|---|---:|---|
| Houses | 20 | 與兩篇論文一致 |
| PV houses | 公開資料的 10 戶 | 另做 9 戶敏感度才可比較，不指定成作者未公開的 9 戶 |
| Battery capacity | 10 kWh／戶 | 論文附錄值 |
| Charge/discharge power | 3.3 kW／戶 | 限制 battery-side DC power |
| Initial/minimum/terminal energy | 1 kWh | 10% of 10 kWh |
| Maximum energy | 9 kWh | 90% of 10 kWh |
| PV AC、PV DC、battery charge/discharge efficiency | 各 0.95 | 不把發布資料的年度 discharge/charge 比率 71.7% 當成單向電池效率 |
| Transfer loss `xi` | 0.07 | 暫作無因次共享損失，不能解讀為已知線路損失或每日自放電 |
| Self-discharge | 0 | `P_SD` 未給值，不用 `xi` 代替 |
| Night/day tariff | 0.091／0.194 EUR/kWh | 日間 `[10:00,22:00)`；FIT=0 |
| Forecast | perfect foresight | 對應論文離線比較實際採用量測輸入的做法，不代表部署時預測能力 |

Wh 檔的 timestamp 依資料契約視為**區間終點**。費率與 PSDT 日間遮罩以 `timestamp-dtHours` 的區間起點判斷：

- 10:00 結束的半小時區間仍用夜價；
- 10:30 結束的區間開始用日價；
- 22:00 結束的區間仍用日價；
- 22:30 結束的區間回到夜價。

住戶 timestamp 沒有 timezone metadata，發布版連續一分鐘網格也已抹平 DST 的缺少／重複分鐘，因此目前保留為 Europe/Dublin naive wall-clock label，不擅自 timezone-localize。

## 5. 為何無法宣稱精確復現原論文

| 缺口 | 受影響結果 | 為何不能用調參補救 |
|---|---|---|
| Bahloul Figure 5 典型日日期未公布 | Bahloul Figure 5、Table I nominal | 看過 savings 後挑日會形成循環選擇與結果導向偏誤 |
| 原 9 個 PV 戶身分未公布，公開版有 10 戶 | 所有策略、Table I | 任意刪除一戶會改變共享量與尖峰，不能冒充作者配置 |
| 2019-07 至 2019-12 未公開 | Bahloul Figure 6 年度平均 | 公開 2020 資料無法補造缺失的半年 |
| SB-SC 商業控制器演算法未公開 | Bahloul Figure 5f、Table I SB-SC | 量測 Charge/Discharge 只能描述輸出，不能反推出唯一控制規則 |
| `Production` AC/DC 量測邊界不明 | PV 分流、效率與 savings | DC 與 AC 解讀都需明示為敏感度，不能選較接近論文者當真值 |
| `xi`、`P_SD` 與容量／功率 ratio 實作不完整 | Table I、Bahloul Figure 7 | 多種合理解讀會產生不同可行集合 |
| Bahloul Figure 7 精確 sensitivity grid 未公布 | Bahloul Figure 7 | 本專案宣告的 grid 只能是重新定義實驗，不是逐點重畫 |
| solver、容差、tie-break 未公布 | PS、PSDT、LL 及平價時段排程 | 等價最優解可能有相同主目標、不同帳單或尖峰 |
| 公開版已插值且上游原始檔未發布 | 資料品質與 SB-SC 行為 | 無法還原插值前的控制動作；缺值也不能合理視為 0 |
| 配電圖缺線阻、相別、距離、電壓與背景負載 | feeder／voltage claim | 只能研究 aggregate peak 或 headroom proxy，不能宣稱完成潮流分析 |

因此各論文結果的本地 claim level 固定如下：

| 論文結果 | 本專案可做的工作 | 可接受說法 |
|---|---|---|
| Bahloul Figure 5 | 以外生曲線形狀選 2020 proxy day，再跑五策略 | 代表日結構性、獨立比較 |
| Bahloul Figure 6 | 對 2020 可得月份的 1、2、15、16 日跑一小時模型 | 2020 結構性復現；不是原年度復現 |
| Table I | 將公開資料結果與印刷值並列並歸因差異 | discrepancy comparison |
| Bahloul Figure 7 | 使用預先宣告的 capacity/power grid | redefined sensitivity experiment |
| SB-SC | 稽核量測輸出 | observational benchmark only |

## 6. 代表日的預先選擇與品質

論文只稱 Bahloul Figure 5 為 typical day，未給日期。本專案先數位化 Bahloul Figure 5 的共同 load／PV 曲線，再以外生曲線距離排名所有 2020 日期；排名過程不使用任何最佳化後的 bill、savings 或 battery behavior。

- 初步第一名 2020-06-10 因 H19 有 3 分鐘連續觀察缺口，超過凍結的 2 分鐘門檻而排除；
- 下一個通過日為 **2020-08-24**，作為公開資料 proxy day；
- 237.372 kWh aggregate load、39.003 kWh PV、18.871 kW load peak、7.168 kW 半小時 PV peak；
- PV 活躍窗 11.75 小時，未超過約 13.81 小時天文日長，未被標為長窗異常；
- 執行模式為 `exclude_flagged_pv`，30 分鐘、48 個區間、20 戶與公開版 10 個 PV 戶。

這個日期是可辯護的替代案例，不是作者未公開典型日的識別結果。

## 7. 五種基準策略結果

無電池比較基準定義為：各戶 PV 優先供本戶、無跨戶分享、無 FIT。2020-08-24 的共同基準為：

- 基準帳單：EUR 33.2971／day；
- 基準 aggregate import peak：17.9362 kW。

下表中的論文 savings 是 Bahloul Figure 5 印刷標籤，只作參考；本地差值不作 paper-equivalence 驗收。

| 策略 | Bahloul Figure 5 savings (%) | 本地 savings (%) | 差值 (百分點) | 本地 bill (EUR) | 全日 peak (kW) | 日間 peak (kW) | Battery throughput (kWh) |
|---|---:|---:|---:|---:|---:|---:|---:|
| SH-BM | 36.41 | 32.158 | -4.252 | 22.589 | 55.682 | 10.011 | 211.456 |
| VPP-BM | 45.83 | 41.262 | -4.568 | 19.558 | 75.501 | 約 0 | 244.671 |
| PS | 15.30 | 12.713 | -2.587 | 29.064 | 8.498 | 8.498 | 90.335 |
| PSDT | 43.63 | 41.262 | -2.368 | 19.558 | 75.501 | 約 0 | 244.671 |
| LL | 15.39 | 12.713 | -2.677 | 29.064 | 8.498 | 8.498 | 90.334 |

補充說明：Table I nominal 的 VPP-BM 為 45.85%，與 Bahloul Figure 5 的 45.83% 本身有 0.02 個百分點差異。本地比較表採 Bahloul Figure 5 標籤。

結果應從目標函數解讀，而不是只看 savings：

1. **SH-BM 與 VPP-BM 降低帳單，但不抑制 aggregate peak。** 平坦夜價讓多戶電池可在同一便宜區間充電，代表日尖峰分別升至 55.68 與 75.50 kW；這不是電壓或變壓器安全的證明。
2. **VPP-BM 與 PSDT 在此案例得到相同 bill 與排程指標。** PSDT 可把日間 peak 壓到近零，但把能量移到夜間；這是此資料與參數下的結果，不表示兩個數學問題普遍等價。
3. **PS 與 LL 犧牲部分 savings 換取平滑。** 兩者將 peak 降到約 8.50 kW；LL spread 約 `1.0e-7 kW`，PS 的 spread 約 `1.33e-5 kW`。
4. **本地 savings 全部比 Bahloul Figure 5 低約 2.37–4.57 個百分點。** 差異可能同時來自日期、資料期間、PV 戶配置、PV 邊界、`xi`、插值與退化解；現有證據不足以把差異唯一分配給某一項。

五種基準的 solver status 均為成功，minimum exit flag 為 1；最大模型平衡殘差不超過約 `7.8e-13 kW`，終端 SoC 誤差與同時充放電量為 0。這證明本地模型在數值上滿足自身契約，不證明它與未公開的作者程式逐項相同。

## 8. 改進策略：IMPROVED_PEAK_GUARD

### 8.1 設計

改進策略只在五種論文基準完成並凍結後執行。它保留 VPP-BM 的帳單最小化主目標，但新增：

```text
aggregateImport(t) <= predeclaredCap
```

代表日的 cap 在求解前固定為「無電池、各戶 PV 自用、無分享」的基準尖峰，即 **17.9362 kW**。先用結果反推一個有利 cap 會造成後驗調參，因此不允許。

求解時先在 cap 內最小化 bill，再鎖住 bill 並最小化 battery throughput；後者只作退化解處置。

`IMPROVED_PEAK_GUARD` 是本專案提出的成本—尖峰折衷，**不是 2022 論文第六種策略，也不是 feeder power-flow constraint**。

### 8.2 與 VPP-BM 的成對比較

| 指標 | VPP-BM | IMPROVED_PEAK_GUARD | 改變 |
|---|---:|---:|---:|
| Optimized bill (EUR/day) | 19.558 | 20.571 | +1.013 EUR（+5.180%） |
| Savings versus no-battery baseline | 41.262% | 38.220% | -3.042 個百分點 |
| Aggregate peak | 75.501 kW | 17.936 kW | -57.565 kW（-76.244%） |
| Daytime peak | 約 0 kW | 7.208 kW | 上升，但仍低於固定 cap |
| Battery throughput | 244.671 kWh | 217.875 kWh | -26.796 kWh（-10.952%） |

此改進不是所有指標都占優：它以每日約 EUR 1.01 的額外成本、3.04 個百分點的 savings 減少，換取不超過無電池基準尖峰的排程。其價值在於揭示原 VPP-BM 經濟目標的盲點，並把尖峰風險改成顯式、可預先宣告及可驗證的限制。

仍需保留兩個邊界：

1. cap 作用於 20 戶的 aggregate proxy，沒有背景負載、相別、線路或變壓器電氣參數，因此不能推論電壓合格或實體饋線安全；
2. 目前只展示一個預先選定代表日，後續必須在品質合格的多日／月份與 AC/DC、`xi`、PV 戶配置敏感度下檢查結論是否穩健。

## 9. 可對外使用的結論措辭

建議在論文、簡報或向教授報告時使用：

> 我們先驗證 StoreNet Figshare v1 的發布完整性，再針對 Bahloul et al. (2022) 的維度錯誤、嚴格不等式、未定義參數與退化最佳解建立具追溯性的論文意圖模型。五種策略已在預先選定的 2020 公開資料代表日完成可重跑獨立復現；由於原典型日、2019 半年資料、9 個 PV 戶身分、SB-SC 控制器及 solver 設定未公開，本結果不宣稱精確重現作者數值。代表日顯示純帳單型 VPP-BM 可能製造新夜間尖峰；預先固定於無電池基準尖峰的 peak-guard 改進可將尖峰降低 76.24%，代價是 savings 減少 3.04 個百分點。

不應使用「已完整複製原論文所有 Figure／Table」、「證明與作者模型相同」或「已完成實體配電網潮流」等說法。
