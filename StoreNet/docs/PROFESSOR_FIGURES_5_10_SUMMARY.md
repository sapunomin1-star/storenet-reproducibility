# 給老師的資料論文 Figure 5--10 確認摘要

資料論文：Trivedi et al. (2024), *Scientific Data*，DOI [`10.1038/s41597-024-03454-2`](https://doi.org/10.1038/s41597-024-03454-2)

公開資料：Figshare v1，DOI [`10.6084/m9.figshare.c.6829134.v1`](https://doi.org/10.6084/m9.figshare.c.6829134.v1)

正式圖與數值 sidecar（以目錄內 manifest、checksum 與 required gates 為準）：[`results/data_paper_figures_5_10_v2`](../results/data_paper_figures_5_10_v2/)

> 本頁的 Figure 5--10 均指 Trivedi 資料論文；後續 Bahloul VPP 方法論文的同號圖會明寫作者名稱，避免混淆。

| 圖 | 代表意義 | 公開資料確認結果 | 主要限制 | 資料採用決定 |
|---|---|---|---|---|
| Figure 5 | 20 戶每分鐘 W status 可用率與缺口 | **精確復現**；20/20 戶百分比在論文顯示精度下一致 | 發布 status 有 1,440--7,978 分鐘長缺口，H14 另有檔尾截斷 | 保留 status 作 processed-release 品質 proxy；長缺口日依契約排除，不把 Wh 有值視為原始觀測完整 |
| Figure 6 | `W` 與一分鐘 `Wh*60` 的一致性 | **整體主張獲強力支持**；有限發布值及 W-status proxy-observed 兩種口徑均為 Consumption 19/20、PV Production 9/10 戶通過，唯一例外都是 H4 | H4 有 146 日在本次 alignment 稽核列為 `unaffected_same0`、1 日不可評估、135 日同日期 +60 分鐘 core、42 日實際月日轉置 +60 分鐘 core、7 日 identity controls、35 日 unresolved；core 對齊不代表完整 24 小時修復，且未公開 90962 原始 pair | 主分析可用未修補 released Wh，但 H4 不稱 ground truth；每個 20 戶 VPP 結果強制加做排除 H4 的 19 戶敏感度 |
| Figure 7 | (a) 各戶年度用電；(b) 社區用電與氣溫關係 | (a) 20 根柱值精確復現；(b) legacy 曲線與負相關方向可復現 | (a) 已刊柱平均 `5003.11`，與 caption `5025.64` 不符；(b) 作者取 daily mean 卻標 `kWh/day` | legacy 值只用於核圖；科學分析使用 timestamp-aware daily sum、正確 kWh 單位與完整日篩選 |
| Figure 8 | 10 個 PV 戶的 production、consumption、feed-in、from-grid 年度差異 | **可由公開 Wh 重算**；H4 高需求、低 export 的解讀成立 | Production 實際範圍 `1747.548--2084.449 kWh`，並非正文所稱全部 1800--2000；公開版有 10 個 PV 戶，VPP 論文則稱 9 戶 | 主分析採公開 10 戶；排除 H4 的成對 19 戶敏感度自然剩 9 個 PV 戶，但不冒充原論文未公布的 9 戶身分 |
| Figure 9 | H4 一週 PV、負載、電網、電池與 SoC 流向 | **可復現**；12/7--12/13 共 10,080 分鐘完整，週內能量平衡可量化 | 正文把明顯 feed-in 寫成 12/8，但 released data 與已刊圖均指向 12/7 | 用於量測流向與平衡稽核；measured battery flows 不固定後續反事實 VPP 決策 |
| Figure 10 | LEM 情境的節點 voltage unbalance surface | **只能結構性追溯**；確認是 Saif et al. (2023) Figure 13 重刊 | 缺修改後 feeder、55-node 映射、phasor/VUF matrix 與完整最佳化設定，不能逐點復現 | 不製造任意 surface 冒充復現；`Figure 10-S` 延後併入網路約束改進，僅稱獨立可行性／敏感度模擬 |

## 圖檔位置

- Figure 5：[`figure5_data_availability.png`](../results/data_paper_figures_5_10_v2/figure5_data_availability.png)
- Figure 6：[`figure6_power_energy_consistency.png`](../results/data_paper_figures_5_10_v2/figure6_power_energy_consistency.png)；全戶證據 [`figure6_all_house_consistency.png`](../results/data_paper_figures_5_10_v2/figure6_all_house_consistency.png)；H4 時間診斷 [`figure6_h4_temporal_diagnostics.png`](../results/data_paper_figures_5_10_v2/figure6_h4_temporal_diagnostics.png)
- Figure 7：[`figure7_annual_and_temperature.png`](../results/data_paper_figures_5_10_v2/figure7_annual_and_temperature.png)；單位修正版 [`figure7b_unit_corrected_comparison.png`](../results/data_paper_figures_5_10_v2/figure7b_unit_corrected_comparison.png)
- Figure 8：[`figure8_pv_annual_profiles.png`](../results/data_paper_figures_5_10_v2/figure8_pv_annual_profiles.png)
- Figure 9：[`figure9_h4_week.png`](../results/data_paper_figures_5_10_v2/figure9_h4_week.png)
- Figure 10：[`figure10_reproducibility_boundary.png`](../results/data_paper_figures_5_10_v2/figure10_reproducibility_boundary.png)，這是公開可復現邊界圖，不是任意假設的替代 surface。

## 建議給老師的結論

本地 46/46 檔案已確認與 Figshare v1 官方發布清單一致，Figure 5--9 足以界定資料內容、可重現部分與品質限制；Figure 10 的不可逐點復現也已由缺少的網路輸入清楚說明。這不代表上游 raw data 或每條 time series 完整。因此建議在 [`SR2020-IR-v2`](REPRODUCTION_CONTRACT.md) 條件下採用這批 processed release，接著進行 Bahloul VPP 方法的同源獨立復現，不宣稱取得作者未公開的原始期間或網路模型。

正式 gate 如下：

1. Figure 6 的八份機器可讀 sidecar 必須全部存在並列入 v2 manifest/checksum，且全部 required gates 通過，才能標記資料論文稽核完成。
2. 老師確認上述資料採用邊界後，再進入 VPP 正式結果重審。
3. VPP v2 驗收必須同時提供 20 戶主分析與 19 戶排除 H4 敏感度；`Figure 10-S` 不在這個 gate 的關鍵路徑。

完整逐圖依據與重跑方式見 [`DATA_PAPER_FIGURES_5_10.md`](DATA_PAPER_FIGURES_5_10.md)。
