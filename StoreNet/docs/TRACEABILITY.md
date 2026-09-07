# Equation-to-code traceability

This matrix maps Bahloul et al. (2022) to the intended-model implementation. Line numbers are intentionally not frozen; constraint and metric names are the stable identifiers.

All Figure 5/6/7 references in this file mean Bahloul et al. (2022), not the Trivedi data-paper figures.

| Paper item | Intended interpretation | Implementation | Verification | Departure recorded |
|---|---|---|---|---|
| Eq. (1) | Generated PV = used PV + curtailed PV | `solve_storenet`: `pvAllocation`, `pvCurtailKW` | `energyBalanceResidualKW`, PV allocation tests | Curtailment is explicit rather than an unnamed `PF` remainder |
| Eq. (2) | Used PV cannot exceed available PV | Equality allocation plus nonnegative curtailment | `pvAllocationResidualKW` | Equivalent linear form |
| Eq. (3) | PV source is divided among AC home/grid and DC battery paths with converter losses | `pvToHomeKW/etaPvAC + pvToGridKW/etaPvAC + pvToBatteryKW/etaPvDC` | Synthetic sharing and balance tests | Public Production is provisionally treated as DC-available; AC-boundary sensitivity is separate |
| Eq. (4) | Battery-side charging power from grid and PV | `chargePowerKW` | `chargeConversionResidualKW` | None beyond explicit units |
| Eq. (5) | Battery-side discharge supplies AC home/grid after efficiency | `dischargePowerKW` | `dischargeConversionResidualKW` | None beyond explicit units |
| Eq. (6) | Charge power bound controlled by binary | `chargePowerLimit` | `chargePowerViolationKW` | Strict `<` changed to `<=`; minimum is 0 |
| Eq. (7) | Discharge power bound controlled by binary | `dischargePowerLimit` | `dischargePowerViolationKW` | Strict `<` changed to `<=`; minimum is 0 |
| Eq. (8) | A battery cannot charge and discharge in one interval | `chargeDischargeExclusion` | `simultaneousChargeDischargeKW`; model test | Binary variables retained even where LP often gives a complementary solution |
| Eq. (9) | Intertemporal stored-energy balance | `socDynamics` in kWh | `batteryDynamicsResidualKW`; terminal/dynamics test | Index corrected from `k` to `t`; kW·h is not added directly to percent SoC; unpublished self-discharge set to 0 |
| Eq. (10) | Energy/SoC bounds | `socKWh` lower/upper bounds | `socBoundViolationKWh` | Strict inequalities changed to inclusive bounds |
| Eq. (11) | Home load supplied by grid, PV and battery | `homeBalance` | `homeBalanceResidualKW` | None |
| Eq. (12) | PV-to-home plus battery-to-home cannot exceed load | Implied by `homeBalance` and nonnegative `gridToHomeKW` | Balance tests | Redundant inequality omitted without changing feasible set |
| Eq. (13) | Aggregate VPP import net of shared PV/battery export | `aggregateImportKW` expression | `aggregateImportResidualKW` | `xi=0.07` is explicitly treated as a dimensionless transfer-loss assumption despite the appendix's `7%/day` wording |
| Eq. (14) | Community cannot be a net exporter | `aggregateImportNonnegative` | `aggregateImportNonnegativeViolationKW` | Strict `>` changed to `>=` |
| Eq. (15) | End-of-horizon SoC returns to its target | `socTerminal` | `terminalSocErrorKWh` | Ambiguous three-index notation replaced by one end state per home |
| Eq. (16) | SH-BM minimizes the sum of individual imported-energy bills | `SH_BM`, no sharing, `billExpression` | no-sharing test and bill metrics | Missing PV-to-home term restored through the full home balance; `dtHours` added |
| Eq. (17) | VPP-BM minimizes community bill with sharing | `VPP_BM`, `billExpression` | sharing-reduces-bill synthetic test | `dtHours` added; throughput is a locked-bill tie-break only |
| Eq. (18) | PS minimizes the full-day maximum VPP import | `systemPeakKW` primary stage | stage-1 value versus `peakImportKW` | Deterministic bill and throughput stages added after locking the primary optimum |
| Eq. (19) | Every interval lies below the PS maximum | `systemPeak` | PS lexicographic test | Strict `>` changed to `>=` equivalent bound |
| Eq. (20) | PSDT minimizes daytime peak | `daytimePeakKW` primary stage | stage-1 value versus `daytimePeakImportKW` | Day is `[10:00,22:00)` and is evaluated from interval start |
| Eq. (21) | Each daytime interval lies below the daytime maximum | `daytimePeak` | PSDT lexicographic test | Strict `>` changed to inclusive bound |
| Eq. (22) | Daytime VPP demand uses the aggregate import expression | `aggregateImportKW(dayMask)` | tariff/daytime boundary test | Reuses one audited aggregate expression instead of duplicating it |
| Eq. (23) | LL minimizes maximum minus minimum import | `importSpreadKW` primary stage | stage-1 value versus `importSpreadKW` metric | Deterministic bill and throughput stages added after locking spread |
| Eq. (24) | Minimum variable lies below every import interval | `minimumImport` | LL lexicographic test | Strict `<` changed to `<=` equivalent bound |

## Data-to-model traceability

| Public field | Role | Transformation | Not used as an exogenous counterfactual input |
|---|---|---|---|
| `Consumption(Wh)` | Home load | Sum exact one-minute interval energy, divide by 1000 and `dtHours` | — |
| `Production(Wh)` | Available PV | Same Wh→kWh→kW conversion | — |
| `Hn_W` status | Observation/interpolation mask | An interval is observed only when both adjacent W status endpoints are 1 | — |
| `Charge(Wh)`, `Discharge(Wh)` | Measured SB-SC behavior / audit | Aggregate for observational comparison only | Never constrains proposed MILP strategies |
| `From grid(Wh)`, `Feed-in(Wh)` | Measured bill/balance audit | Aggregate with interval-end convention | Never substituted for counterfactual grid decisions |
| `State of Charge(%)` | Observed-system diagnostic | Take interval-end state, never sum | Never fixes optimized SoC trajectory |

## Result traceability

| Paper result | Local reference | Local experiment | Claim level |
|---|---|---|---|
| Figure 5 printed savings | `reference/fig5_savings.csv` | `run_typical_day` | Independent 2020 proxy; date is not claimed identical |
| Figure 5 load/PV shape | `reference/paper_fig5_profile_digitized.csv` | `select_typical_day` | Exogenous-only date ranking |
| Figure 6 monthly design | Paper days 1, 2, 15, 16 | `run_monthly` | Structural 2020 replication; 2019 months unavailable |
| Table I | `reference/table_i.csv` | typical-day and sensitivity outputs | Comparison with explicit input mismatch |
| Figure 7 | Textual ratio range; exact grid unpublished | `run_sensitivity` with declared grid | Redefined sensitivity, not exact digit-for-digit reproduction |
| SB-SC | Figure 5/Table I printed values and measured public flows | observational benchmark only | Algorithm cannot be reproduced because it is proprietary |
