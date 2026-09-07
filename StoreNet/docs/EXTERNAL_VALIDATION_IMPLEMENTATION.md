# Ausgrid 外部驗證實作契約

本文件補充 [`EXTERNAL_VALIDATION_PROTOCOL.md`](./EXTERNAL_VALIDATION_PROTOCOL.md) 的程式邊界與輸出格式。它在正式 Ausgrid 最佳化前寫成，不包含也不依賴任何 savings、bill 或 peak 結果。

## 1. 元件與信任邊界

| 元件 | 責任 | 明確不做的事 |
|---|---|---|
| `crossenv.loadAusgridSpec` | 載入並驗證固定 JSON、解析 repo 內路徑 | 不讀數據、不選日、不求解 |
| `crossenv.adapters.readAusgridYear` | 驗 SHA-256、解析年度 CSV、執行 quality contract | 不插值、不按結果排除戶或日 |
| `crossenv.selectMonthlyDays` | 僅由 aggregate load/PV 曲線選 12 個 robust-central days | 不呼叫 solver、不讀 bill/savings/peak |
| `solve_storenet` | 依指定策略解原有 StoreNet MILP | 不決定 cohort、日期或通過門檻 |
| `evaluate_storenet` | 由公開 solution flows 重新計算物理殘差與 KPI | 不採信 solver wrapper 自報的 metrics |
| `crossenv.evaluateExternalAcceptance` | 對已完成表格執行 fail-closed 預註冊判定 | 不修補、過濾或重跑失敗列 |
| `audit_ausgrid.py` | 用 Python 標準庫獨立重算資料品質與選日 | 不被 MATLAB runner 呼叫、不參與正式求解 |

主 runner 是 [`run_external_validation.m`](../src/run_external_validation.m)。跨環境程式位於 [`+crossenv`](../src/+crossenv/) package；已封存的 StoreNet loader、核心 solver 與 evaluator 不因外部資料而改寫。

## 2. 資料轉換

年度 adapter 只接受 JSON 內固定的 53 戶。對每一戶、每一日：

- `GC` 與 `GG` 必須各恰有一列；`CL` 可有零或一列。
- 相關列的 `Row Quality` 必須空白；48 個值必須有限且非負。
- `loadKWh = GC + CL`，不存在的 optional `CL` 依欄位定義為 0。
- `pvKWh = GG`；30 分鐘能量除以 `0.5 h` 後才成為平均 `kW`。
- 任一戶違約即拒絕整個 community-day，資料仍可檢查但 `validForOptimization=false`。

canonical 日資料只向 solver 暴露 `time`、`loadKW`、`pvKW`、`dtHours` 與 `houseIds`。時間為 48 個 interval-end naive local timestamps，最後一點是次日 `00:00`。

`GG` 已在 inverter 後量測，因此 fixed-policy transfer 必須設定 `etaPvAC=1.0`；否則會重複扣除 AC 轉換效率。PV-to-battery 路徑仍沿用 `etaPvDC=0.95`。

## 3. 外生選日

`selectMonthlyDays` 對每個合格日先跨 53 戶加總，形成 48 點 load 加 48 點 PV 的 96 維向量。每月各維用 median 與未縮放 median absolute deviation 標準化；零 MAD 改為 1。分數是到 component-wise median profile 的 RMS 距離，同分取較早日期。

`selection.csv` 必須恰有 12 列且月份為 1–12；`ranking.csv` 必須恰標 12 個 `Selected=true`。runner 也拒絕含 `saving`、`bill`、`dispatch`、`solver` 或 `outcome` 欄名的 ranking，作為額外的防洩漏檢查。

## 4. 求解與獨立評估

Primary 每月固定依序執行 `SH_BM`、`VPP_BM`、`IMPROVED_PEAK_GUARD`。Peak Guard 的 `P0` 直接由當日 load/PV 與無電池 household self-consumption 計算，先於任何該策略求解。

四個季節月份另先執行 `PS`，取得 `Pmin`；其後 5 個 `alpha` 點均使用預註冊公式。`PS` 的四列參考值保存於 `frontier_reference_metrics.csv`，不混入恰有 20 列的 `frontier_metrics.csv`。

runner 忽略 solver 的第二輸出 metrics，對每一個 solution 重新呼叫 `evaluate_storenet`。只有 evaluator 殘差、terminal SoC、同時充放電、cap 與 solution exit flags 全部通過，列狀態才是 `ok`。

## 5. 數值單調容差

物理 cap 與殘差門檻直接使用固定 JSON。frontier bill 是 solver 目標值，需把相對 MIP gap 與相對 lexicographic allowance 換成同單位的絕對比較容差。事前固定公式為：

```text
billMonotonicEUR = 2 * (mipRelativeGap + lexicographicTolerance)
                   * max(1, max(abs(finite frontier bill)))
```

係數 2 同時涵蓋相鄰兩次獨立 MILP 解的容差方向；這個值只用於判斷數值級反向差異，不改 cap、目標或任何 solution。實際 scale 與換算後數值必須寫入 manifest。

## 6. 中斷恢復與 provenance

每完成一個 primary、`PS` reference 或 frontier 點，runner 以 temporary-file + atomic move 更新：

- `primary_metrics.csv`
- `frontier_reference_metrics.csv`
- `frontier_metrics.csv`
- `external_validation_checkpoint.csv`

非空 `RunId` 目錄一律拒絕覆寫。正式 manifest 必須記錄 source/spec hash、論文 DOI、PV basis、normalized overrides、selection、solver/runtime、每列狀態、固定與尺度化容差，以及執行時 Git commit/dirty state。

## 7. 獨立資料稽核

從 repo 根目錄執行：

```bash
python3 StoreNet/src/audit_ausgrid.py --output independent_data_audit.json
```

正式執行前，Python 與 MATLAB 必須對 source SHA-256、raw row count、戶數、合格/拒絕日數、拒絕日期與 12 個代表日一致；分數允許的差異僅限浮點顯示精度。這是不同語言、不同 parser 的交叉檢查，不是第二份模型績效估計。
