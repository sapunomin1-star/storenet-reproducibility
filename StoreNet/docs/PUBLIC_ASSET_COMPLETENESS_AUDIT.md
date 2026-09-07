# 作者公開資料與程式完整性稽核

稽核日期：2026-09-01

本文件的 Figure 5--10 均指 Trivedi et al. (2024) 資料論文；Bahloul 方法論文圖號會明寫作者。

## 結論

**我們沒有漏下載目前 Figshare 公開集合中的檔案。** 本地 46/46 檔與官方 collection v1 的 filenames、bytes、MD5 一致，本地 SHA-256 亦全部通過。但官方 deposit 本身沒有包含論文文字所描述的完整 `original data/`、`processed_data/`、`figures/` 目錄與全部上游程式輸入。

換句話說，「本地下載不完整」與「作者公開內容不足」必須分開：前者已排除，後者確實存在。

## 1. Figshare 官方集合

- Collection：[`10.6084/m9.figshare.c.6829134.v1`](https://doi.org/10.6084/m9.figshare.c.6829134.v1)
- [官方 collection 頁](https://springernature.figshare.com/collections/Comprehensive_Dataset_on_Electrical_Load_Profiles_for_Energy_Community_in_Ireland/6829134)
- Collection versions API 只有 v1；46 個 article 亦各只有 v1。
- 共 46 個 items、46 個檔案，總大小 `1,107,613,821 bytes`。
- 構成：20 W CSV、20 Wh CSV、weather CSV、README、setup、data processing、energy plots、power plots。
- 官方 article license 為 CC0。README 同時放置 MIT/GPL/AGPL badge 但沒有 LICENSE，不能用 badges 覆蓋 deposit 的正式授權 metadata。
- 官方 article DOI/version、file ID、bytes、MD5 與下載 URL 已凍結於 [`figshare_v1_inventory.csv`](../reference/figshare_v1_inventory.csv)；流程逐檔比對 local bytes/MD5，並另外比對 SHA-256 manifest。

本地 manifest：[`RELEASE_MANIFEST.sha256`](../data/RELEASE_MANIFEST.sha256)。

## 2. 論文提到但 deposit 未提供的內容

資料論文的 Data Records／Table 4 描述 `original data/`、`processed_data/` 與 `figures/`。實際 Figshare collection 是扁平化的 processed files，缺少：

- 20 組原 battery ID 檔，例如 Figure 6 指定的：
  - `original data/energy/90962_2020_Wh.csv`
  - `original data/power/90962_2020_W.csv`
- Figure 7(b) 指定的 `copy_resample_experiment/energy/`。
- 12 個原始 monthly weather 檔、測站 ID、下載時 checksum 與完整轉換紀錄。
- 原始 `figures/` 輸出與 Figure 5／7 的合成步驟。
- Figure 10 的 OpenDSS/MATLAB/YALMIP 模型、profile mapping 與 voltage/VUF matrices。

上述檔案不是本地下載失敗；它們沒有出現在 Figshare v1 的 46 個官方 articles 中。

## 3. 作者 GitHub 與其他官方來源

- 發布 README 指向 `https://github.com/Rohit-Trivedi/nat-data`，但 2026-09-01 為 404；GitHub user API 顯示 0 public repositories，因而無法稽核 branches、tags、releases 或 commit history。這只能證明目前不可公開取得，不能證明該 repo 從未存在。
- Nature/PMC 的 Code availability 只指回資料 repository，沒有額外 supplementary code package。
- 以精確論文標題、paper DOI 與 collection DOI 查詢 Zenodo 官方 API，沒有匹配紀錄。
- [UCC institutional record](https://research.ucc.ie/en/publications/comprehensive-dataset-on-electrical-load-profiles-for-energy-comm/)只有書目與 DOI，沒有另一份附件。
- Figure 10 的來源研究可由 [TU Dublin 正式紀錄](https://arrow.tudublin.ie/engscheleart2/361/)取得全文；資料聲明是 available on request，沒有公開 pointwise outputs。
- [IEEE 官方 European LV test feeder](https://cmte.ieee.org/pes-testfeeders/resources/)可下載 stock model，但它不是作者修改後 350 kVA paper-specific circuit。

## 4. 對研究的影響

| 工作 | 判定 |
|---|---|
| 驗證我們是否完整下載公開 v1 | 完成，46/46 |
| 由 processed release 重現 Figure 5、7(a)、8、9 | 可行 |
| 重現 Figure 7(b) 已刊曲線 | 可行，但須揭露單位錯誤 |
| 驗證 Figure 6 的 processed-release 資料集層級 W/Wh 一致性 | 可行；雙比較口徑均為 Consumption 19/20、PV Production 9/10 通過，唯一例外 H4 |
| 逐點重現已刊 Figure 6 的 H4 `90962` panel／原始 `r=1.0` | 不可由公開 v1 完成；作者程式指定的原始 pair 未發布 |
| 從 raw battery logger 重跑全部 preprocessing | 不可完成 |
| 精確重現 Figure 10 | 不可完成；只能結構性追溯 |

若要把**已刊 H4 Figure 6 panel**或 Figure 10 升格為 numerical/exact reproduction，需要向作者索取：原始 90962 W/Wh pair、完整 raw-to-processed folder、Figure 10 修改後 circuit、55-node profile mapping、optimizer code 與 node-by-hour voltage/VUF arrays。缺少 90962 pair 不再阻擋 processed release 的資料集層級一致性判斷，但仍阻擋那張已刊 H4 圖的逐點復現。
