# ADR-001: Bahloul Figure 5 typical-day selection

Status: accepted for the independent replication  
Decision date: 2026-08-31

## Context

Bahloul et al. call Figure 5 a typical day but do not publish its date. Choosing a 2020 date after seeing optimization savings would make the comparison circular.

## Decision

The paper's common blue Load and yellow PV curves were digitized before solving any strategy and stored in `reference/paper_fig5_profile_digitized.csv`. For every public-data date with 48 half-hour intervals, define

```text
score = sqrt(mean(((load - paperLoad)/20)^2 + ((pv - paperPv)/10)^2))
```

where load and PV are aggregate kW. Rank by ascending score, then apply the frozen `short_gap_only` and PV-physics quality rules. Do not include bills, savings, battery behavior or strategy outputs in the score.

The first exploratory calculation placed 2020-06-10 first and 2020-08-24 second. The formal MATLAB pipeline subsequently recomputed all 345 candidates directly from the immutable CSVs, without optimization metrics. The machine-readable result is saved in [`results/typical_day_selection_2020/ranking.csv`](../../results/typical_day_selection_2020/ranking.csv), with provenance in its [`manifest.json`](../../results/typical_day_selection_2020/manifest.json).

The formal score for 2020-06-10 is `0.22744`, but H19 contains a three-minute observation gap, exceeding the frozen two-minute limit. The next-ranked passing date is **2020-08-24**, with formal score `0.2422667`: 237.372 kWh load, 39.003 kWh PV, 18.871 kW load peak and 7.168 kW half-hour PV peak. Its aggregate one-minute PV window is 11.75 h versus an approximate 13.81 h astronomical day length, so it is not a long-window PV anomaly. Across the 345 dates, 87 passed `exclude_flagged_pv`; 2020-08-24 is the unique selected row.

The formal MATLAB values supersede the exploratory scores. The selection rule, the exclusion of 2020-06-10 and the prohibition on using optimization outcomes were fixed before this recomputation.

## Consequences

- 2020-08-24 is a defensible public-data proxy, not a claim that it is the authors' unpublished day.
- Bahloul Figure 5 printed savings remain reference values only; numerical mismatch is reported and attributed rather than tuned away.
- Literal-release and quality-aware runs use the same selected date so quality processing is not allowed to choose a more favorable result.
