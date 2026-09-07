# Scientific Data Figures 5-10 reproduction

This directory is generated from the 46-file Figshare v1 release.  The source
files passed SHA-256 verification before plotting.  A visual match is never used
as the sole acceptance criterion; CSV/JSON evidence is saved beside every plot.

| Figure | Result | Meaning |
|---|---|---|
| 5 | exact numeric reproduction | Status-field availability for the 20 released W files. |
| 6 | general W/Wh consistency supported; H4 public release has diagnosed time/date assembly evidence, while the published H4 panel remains unreproduced | The 20-house audit supports general W/Wh consistency, isolates H4 as the released-data outlier, and provides time/date assembly evidence. |
| 7(a) | bar values exact; caption mean conflicts | All 20 printed bars match; the caption mean conflicts with their arithmetic mean. |
| 7(b) | legacy trend reproduced; released-grid-complete unit correction supplied | Legacy curve/r reproduced, but its published kWh/day unit is wrong; processed-series correction included. |
| 8 | released-data totals reproduced; textual range conflicts | Paper-legacy and strict calendar-2020 PV-house totals are both exported. |
| 9 | released-data week reproduced | H4 7-13 Dec one-minute profiles reproduced; daily evidence is exported. |
| 10 | structural only; exact inputs unpublished | Reprinted network-study surface lacks public pointwise inputs; boundary artifact only. |

## Files

- `figure5_data_availability.png` and `figure5_availability.csv`
- `figure6_power_energy_consistency.png` and `figure6_all_house_metrics.csv`
- `figure6_all_house_consistency.png` and `figure6_h4_temporal_diagnostics.png`
- `figure6_h4_daily_diagnostics.csv`, `figure6_h4_monthly_summary.csv`, and
  `figure6_h4_alignment_summary.csv`, plus `figure6_h4_anomaly_segments.csv`
- `figure6_h4_date_transpose_diagnostics.csv`,
  `figure6_h4_cross_house_controls.csv`, and `figure6_h4_wh_balance.json`
- `figure7_annual_and_temperature.png`, the unit-corrected companion, and daily/annual CSVs
- `figure8_pv_annual_profiles.png` and `figure8_pv_annual_totals.csv`
- `figure9_h4_week.png`, its minute-level CSV, and `figure9_metrics.json`
- `figure10_reproducibility_boundary.png` and `figure10_requirements.csv`
- `validation.csv`, `summary.json`, `manifest.json`, and `RESULT_MANIFEST.sha256`

The original author scripts remain unchanged under `data/raw/`; this pipeline
replaces hard-coded Windows paths and records deviations rather than concealing
them.

`ReleasedGridComplete` means that all 20 processed Wh series contain finite
values on that minute grid.  It does not establish raw-observation completeness,
because the release has interpolated values but no observation/imputation mask.

For Figure 6, a positive `BestWhTimestampOffsetMinutes` means that `W(t)` is
compared with `60*Wh(t + offset)`.  The lag and date-transpose diagnostics are
evidence about the released H4 file assembly; they do not repair or overwrite
the release, and they cannot substitute for the unpublished 90962 source pair.

`manifest.json` hashes every science artifact that existed before the manifest
was written.  `RESULT_MANIFEST.sha256` then hashes those artifacts plus the
manifest itself, excluding only its own checksum file.  Verify it from this
directory with `shasum -a 256 -c RESULT_MANIFEST.sha256`.
