# Paper reference values

`B2022_REFERENCE_MANIFEST.csv` freezes the content hashes, paper locators,
units, sample counts, unavailable boundaries, and extraction methods used by
the `B2022-IR-v1` pre-solve gate. The manifest intentionally does not hash
itself; its own runtime hash is stored in each formal run manifest.

These files are transcriptions or digitizations from Bahloul et al. (2022), not outputs of this project.

- `fig5_savings.csv`: percentages printed in Figure 5. The paper text gives VPP-BM as 45.83%; Table I gives 45.85% for the nominal row. Both are retained rather than silently reconciled.
- `table_i.csv`: Table I values as printed.
- `paper_fig5_profile_digitized.csv`: the common blue Load and yellow PV curves sampled from Figure 5 at 30-minute endpoints. Page 7 of the local PDF was rasterized at 300 dpi; MATLAB line colors were isolated inside the plot rectangle and mapped using the 0/20/40 kW grid lines. Values are rounded to 0.01 kW, but their scientific reading uncertainty is approximately ±0.5 kW. The two false yellow pixels caused by the legend after sunset were rejected as plot-overlay artifacts.

The following references belong to Trivedi et al. (2024), the Scientific Data
descriptor, rather than to the 2022 VPP-method paper above:

- `data_paper_fig5_availability.csv`: the 20 percentages printed beside the
  published Figure 5 heatmap. They are transcription targets, not replacement
  measurements.
- `data_paper_fig7_annual_consumption.csv`: the 20 one-decimal bar labels in
  Figure 7(a). Their arithmetic mean is 5003.11 kWh, which conflicts with the
  5025.64 kWh stated in the caption and body; both values remain visible in the
  audit rather than being silently reconciled.
- `data_paper_claims.json`: machine-readable claims and disclosed figure
  settings used by the Figure 5-10 validation pipeline. It explicitly separates
  printed claims from behaviour recoverable from the released plotting code.
- `figshare_v1_inventory.csv`: 2026-09-01 snapshot of the 46 official Figshare
  v1 article/file records, including article and file IDs, bytes, official MD5,
  and stable download URLs. The pipeline checks this inventory and the local
  SHA-256 release manifest independently before generating any figure.

The digitized profile is used only to rank candidate public-data dates from exogenous load/PV shapes. Optimization savings are never used in date selection.
