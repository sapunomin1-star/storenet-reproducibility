#!/usr/bin/env python3
"""Render improvement-v2 figures from frontier summary CSVs only.

Every figure is drawn from CSV files written by run_bahloul_frontier_v1.m
and summarize_bahloul_frontier_v1.m; nothing is solved here. Usage:

    python src/render_frontier_figures.py \
        --typical results/bahloul_vpp_improvement_v2_frontier/storenet_typical_20200824 \
        --monthly results/bahloul_vpp_improvement_v2_frontier/storenet_monthly_2020 \
        --output results/bahloul_vpp_improvement_v2_frontier/figures
"""
from __future__ import annotations

import argparse
import csv
import math
import os
from collections import defaultdict

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

COLORS = {
    "vpp": "#C0392B",
    "lex": "#1F77B4",
    "guard": "#2CA02C",
    "ps": "#7F7F7F",
    "frontier": "#1F77B4",
    "tariff": "#FF7F0E",
    "load": "#333333",
    "p0": "#8E44AD",
}


def read_csv(path):
    if not os.path.exists(path):
        return []
    with open(path, newline="") as handle:
        return list(csv.DictReader(handle))


def num(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return math.nan


def is_true(value):
    return str(value).strip().lower() in {"1", "true"}


def finite(values):
    return [v for v in values if not math.isnan(v)]


def style_axes(ax):
    ax.grid(True, alpha=0.3, linewidth=0.6)
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)


def figure_typical_frontier(typical_dir, output):
    frontier = [r for r in read_csv(os.path.join(typical_dir, "frontier_daily.csv"))
                if is_true(r["Feasible"])]
    anchors = read_csv(os.path.join(typical_dir, "anchor_comparison.csv"))
    tariff = [r for r in read_csv(os.path.join(typical_dir, "tariff_daily.csv"))
              if is_true(r["Feasible"])]
    if not frontier or not anchors:
        return None
    anchor = anchors[0]
    fig, ax = plt.subplots(figsize=(7.2, 4.6))
    peaks = [num(r["PeakKW"]) for r in frontier]
    bills = [num(r["BillEUR"]) for r in frontier]
    order = sorted(range(len(peaks)), key=lambda i: peaks[i])
    ax.plot([peaks[i] for i in order], [bills[i] for i in order], "-o",
            color=COLORS["frontier"], markersize=4, linewidth=1.4,
            label="ε-constraint frontier (cap = r·P0)")
    knee = [r for r in frontier if is_true(r["IsKnee"])]
    if knee:
        ax.plot(num(knee[0]["PeakKW"]), num(knee[0]["BillEUR"]), "D",
                color="black", markersize=8, markerfacecolor="none",
                label=f"knee (r = {num(knee[0]['CapRatio']):.2f})")
    ax.plot(num(anchor["VppPeakKW"]), num(anchor["VppBillEUR"]), "s",
            color=COLORS["vpp"], markersize=9, label="VPP-BM (paper)")
    ax.plot(num(anchor["LexPeakKW"]), num(anchor["LexBillEUR"]), "^",
            color=COLORS["lex"], markersize=10,
            label="VPP-BM + peak tie-break (bill-free)")
    guard = [r for r in frontier if abs(num(r["CapRatio"]) - 1) < 1e-9]
    if guard:
        ax.plot(num(guard[0]["PeakKW"]), num(guard[0]["BillEUR"]), "o",
                color=COLORS["guard"], markersize=9, label="Peak Guard v1 (r = 1)")
    if not math.isnan(num(anchor.get("PsPeakKW", "nan"))):
        ax.plot(num(anchor["PsPeakKW"]), num(anchor["PsBillEUR"]), "v",
                color=COLORS["ps"], markersize=9, label="PS (paper)")
    if tariff:
        ax.scatter([num(r["PeakKW"]) for r in tariff],
                   [num(r["BillEUR"]) for r in tariff], marker="x", s=55,
                   color=COLORS["tariff"], zorder=5,
                   label="demand-charge sweep (λ)")
        clusters = defaultdict(list)
        for r in tariff:
            key = (round(num(r["PeakKW"]), 3), round(num(r["BillEUR"]), 3))
            clusters[key].append(num(r["DemandChargeEURPerKW"]))
        for (peak, bill), charges in clusters.items():
            charges = sorted(charges)
            if len(charges) == 1:
                text = f"λ={charges[0]:g}"
            else:
                text = f"λ={charges[0]:g}…{charges[-1]:g}"
            ax.annotate(text, (peak, bill), textcoords="offset points",
                        xytext=(6, 4), fontsize=7, color=COLORS["tariff"])
    ax.axvline(num(anchor["P0KW"]), color=COLORS["p0"], linestyle="--",
               linewidth=1, label=f"P0 = {num(anchor['P0KW']):.2f} kW")
    ax.set_xlabel("All-day aggregate import peak (kW)")
    ax.set_ylabel("Daily community bill (EUR)")
    ax.set_title(f"Bill–peak trade-off, StoreNet public data, {anchor['Day']} (30 min)")
    style_axes(ax)
    ax.legend(fontsize=7.5, loc="upper right")
    fig.tight_layout()
    path = os.path.join(output, "fig1_typical_frontier.png")
    fig.savefig(path, dpi=200)
    plt.close(fig)
    return path


def figure_typical_profiles(typical_dir, output):
    profiles = read_csv(os.path.join(typical_dir, "profiles.csv"))
    anchors = read_csv(os.path.join(typical_dir, "anchor_comparison.csv"))
    if not profiles or not anchors:
        return None
    anchor = anchors[0]
    series = defaultdict(list)
    for r in profiles:
        series[r["CaseId"]].append(r)
    wanted = [
        ("ANCHOR_VPP_BM", "VPP-BM (paper)", COLORS["vpp"], "-"),
        ("ANCHOR_VPP_BM_PEAK_LEX", "VPP-BM + peak tie-break", COLORS["lex"], "-"),
        ("FRONTIER_R1.000", "Peak Guard v1 (cap = P0)", COLORS["guard"], "-"),
        ("ANCHOR_PS", "PS (paper)", COLORS["ps"], "-"),
    ]
    fig, ax = plt.subplots(figsize=(8.4, 4.4))
    base = series.get("ANCHOR_VPP_BM") or next(iter(series.values()))
    hours = [num(r["IntervalIndex"]) * 24 / len(base) for r in base]
    ax.step(hours, [num(r["AggregateLoadKW"]) for r in base], where="pre",
            color=COLORS["load"], linewidth=1.2, linestyle=":",
            label="original aggregate load")
    for case_id, label, color, style in wanted:
        rows = series.get(case_id)
        if not rows:
            continue
        ax.step(hours, [num(r["AggregateImportKW"]) for r in rows], where="pre",
                color=color, linewidth=1.5, linestyle=style, label=label)
    ax.axhline(num(anchor["P0KW"]), color=COLORS["p0"], linestyle="--",
               linewidth=1, label="P0 (no-battery peak)")
    ax.axvspan(10, 22, color="#F2C14E", alpha=0.12, lw=0, label="day tariff 10:00–22:00")
    ax.set_xlim(0, 24)
    ax.set_xticks(range(0, 25, 2))
    ax.set_xlabel("Hour of day (interval end)")
    ax.set_ylabel("Aggregate grid import (kW)")
    ax.set_title(f"Aggregate import profiles, {anchor['Day']}")
    style_axes(ax)
    ax.legend(fontsize=7.5, ncol=2, loc="upper right")
    fig.tight_layout()
    path = os.path.join(output, "fig2_typical_profiles.png")
    fig.savefig(path, dpi=200)
    plt.close(fig)
    return path


def figure_monthly_frontier(monthly_dir, output):
    summary = read_csv(os.path.join(monthly_dir, "frontier_summary.csv"))
    if not summary:
        return None
    summary = sorted(summary, key=lambda r: num(r["CapRatio"]), reverse=True)
    ratios = [num(r["CapRatio"]) for r in summary]
    sacrifice = [num(r["AggregatedPaperSavingsSacrificePP"]) for r in summary]
    feasible = [num(r["FeasibleDays"]) for r in summary]
    planned = [num(r["PlannedDays"]) for r in summary]
    fig, ax1 = plt.subplots(figsize=(7.2, 4.4))
    ax1.plot(ratios, sacrifice, "-o", color=COLORS["frontier"], linewidth=1.5,
             label="summed-cost paper-savings sacrifice vs VPP-BM (pp)")
    for r, s, f, p in zip(ratios, sacrifice, feasible, planned):
        if not math.isnan(s):
            ax1.annotate(f"{int(f)}/{int(p)} d", (r, s), textcoords="offset points",
                         xytext=(0, 7), fontsize=7, ha="center")
    ax1.set_xlabel("Cap ratio r (cap = r · P0 of each day)")
    ax1.set_ylabel("Savings sacrifice (percentage points)")
    ax1.invert_xaxis()
    style_axes(ax1)
    ax2 = ax1.twinx()
    ax2.plot(ratios, [num(r["MeanPeakKW"]) for r in summary], "--s",
             color=COLORS["guard"], linewidth=1.2, markersize=4,
             label="mean all-day peak of feasible days (kW)")
    ax2.set_ylabel("Mean all-day peak (kW)")
    ax2.spines["top"].set_visible(False)
    lines = ax1.get_legend_handles_labels()
    lines2 = ax2.get_legend_handles_labels()
    ax1.legend(lines[0] + lines2[0], lines[1] + lines2[1], fontsize=7.5,
               loc="center left")
    ax1.set_title("Monthly frontier across 2020 public days (60 min)")
    fig.tight_layout()
    path = os.path.join(output, "fig3_monthly_frontier.png")
    fig.savefig(path, dpi=200)
    plt.close(fig)
    return path


def figure_monthly_free_peak(monthly_dir, output):
    anchors = read_csv(os.path.join(monthly_dir, "anchor_comparison.csv"))
    if not anchors:
        return None
    anchors = sorted(anchors, key=lambda r: r["Day"])
    days = [r["Day"][5:] for r in anchors]
    vpp = [num(r["VppPeakKW"]) for r in anchors]
    lex = [num(r["LexPeakKW"]) for r in anchors]
    p0 = [num(r["P0KW"]) for r in anchors]
    ps = [num(r["PsPeakKW"]) for r in anchors]
    x = list(range(len(days)))
    fig, ax = plt.subplots(figsize=(10.5, 4.4))
    ax.bar([i - 0.2 for i in x], vpp, width=0.4, color=COLORS["vpp"], alpha=0.85,
           label="VPP-BM all-day peak")
    ax.bar([i + 0.2 for i in x], lex, width=0.4, color=COLORS["lex"], alpha=0.85,
           label="VPP-BM + peak tie-break (same bill)")
    ax.plot(x, p0, "_", color=COLORS["p0"], markersize=12, markeredgewidth=2,
            label="P0 (no-battery peak)")
    if finite(ps):
        ax.plot(x, ps, "_", color=COLORS["ps"], markersize=12, markeredgewidth=2,
                label="PS peak (floor)")
    ax.set_xticks(x)
    ax.set_xticklabels(days, rotation=90, fontsize=7)
    ax.set_ylabel("All-day aggregate import peak (kW)")
    ax.set_title("Bill-free peak reduction on the 2020 monthly days")
    style_axes(ax)
    ax.legend(fontsize=8, ncol=4, loc="upper left")
    fig.tight_layout()
    path = os.path.join(output, "fig4_monthly_free_peak.png")
    fig.savefig(path, dpi=200)
    plt.close(fig)
    return path


def figure_tariff(typical_dir, monthly_dir, output):
    typical = [r for r in read_csv(os.path.join(typical_dir, "tariff_daily.csv"))
               if is_true(r["Feasible"])]
    monthly = read_csv(os.path.join(monthly_dir, "tariff_summary.csv"))
    if not typical and not monthly:
        return None
    fig, ax = plt.subplots(figsize=(7.2, 4.4))
    if typical:
        typical = sorted(typical, key=lambda r: num(r["DemandChargeEURPerKW"]))
        ax.plot([num(r["DemandChargeEURPerKW"]) for r in typical],
                [num(r["PeakRatioToP0"]) for r in typical], "-o",
                color=COLORS["tariff"], label="typical day 2020-08-24: peak / P0")
    if monthly:
        monthly = sorted(monthly, key=lambda r: num(r["DemandChargeEURPerKW"]))
        ax.plot([num(r["DemandChargeEURPerKW"]) for r in monthly],
                [num(r["MeanPeakRatioToP0"]) for r in monthly], "-s",
                color=COLORS["lex"], label="monthly days: mean peak / P0")
        ax.plot([num(r["DemandChargeEURPerKW"]) for r in monthly],
                [num(r["MaxPeakRatioToP0"]) for r in monthly], "--^",
                color=COLORS["lex"], alpha=0.6, label="monthly days: max peak / P0")
    ax.axhline(1.0, color=COLORS["p0"], linestyle="--", linewidth=1,
               label="peak = P0 (Peak Guard cap)")
    ax.set_xscale("log")
    ax.set_xlabel("Demand charge λ (EUR per kW of daily peak)")
    ax.set_ylabel("Resulting peak relative to P0")
    ax.set_title("What demand charge makes a bill-minimising aggregator avoid the new peak?")
    style_axes(ax)
    ax.legend(fontsize=7.5)
    fig.tight_layout()
    path = os.path.join(output, "fig5_demand_charge.png")
    fig.savefig(path, dpi=200)
    plt.close(fig)
    return path


def figure_efficiency(typical_dir, output):
    rows = read_csv(os.path.join(typical_dir, "efficiency_comparison.csv"))
    rows = [r for r in rows if r["Status"] in ("ok", "time_limited")]
    if not rows:
        return None
    labels = {
        "SH_BM": "SH-BM", "VPP_BM": "VPP-BM", "VPP_BM_PEAK_LEX": "VPP-BM+peak",
        "PS": "PS", "PSDT": "PSDT", "LL": "LL", "IMPROVED_PEAK_GUARD": "Peak Guard",
    }
    names = [labels.get(r["Strategy"], r["Strategy"]) for r in rows]
    nominal = [num(r["NominalPaperSavingsPercent"]) for r in rows]
    measured = [num(r["PaperSavingsPercent"]) for r in rows]
    x = list(range(len(rows)))
    fig, ax = plt.subplots(figsize=(7.6, 4.2))
    ax.bar([i - 0.2 for i in x], nominal, width=0.4, color="#BBBBBB",
           label="paper parameters (η = 0.95 / 0.95, RTE 90.3%)")
    ax.bar([i + 0.2 for i in x], measured, width=0.4, color=COLORS["lex"],
           label=f"measured calibration (η = {num(rows[0]['EtaBattery']):.4f}, RTE 71.7%)")
    for i, (n, m) in enumerate(zip(nominal, measured)):
        if not math.isnan(n) and not math.isnan(m):
            ax.annotate(f"−{n - m:.1f} pp", (i + 0.2, m), textcoords="offset points",
                        xytext=(0, 3), ha="center", fontsize=7.5)
    ax.set_xticks(x)
    ax.set_xticklabels(names)
    ax.set_ylabel("Paper-baseline savings (%)")
    ax.set_ylim(0, max(finite(nominal + measured)) * 1.3)
    ax.set_title(f"Savings under measured battery efficiency, {rows[0]['Day']}")
    style_axes(ax)
    ax.legend(fontsize=7.5, loc="upper left")
    fig.tight_layout()
    path = os.path.join(output, "fig6_efficiency_recalibration.png")
    fig.savefig(path, dpi=200)
    plt.close(fig)
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--typical", required=True)
    parser.add_argument("--monthly", default="")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    os.makedirs(args.output, exist_ok=True)
    produced = [
        figure_typical_frontier(args.typical, args.output),
        figure_typical_profiles(args.typical, args.output),
        figure_efficiency(args.typical, args.output),
    ]
    if args.monthly:
        produced += [
            figure_monthly_frontier(args.monthly, args.output),
            figure_monthly_free_peak(args.monthly, args.output),
        ]
    produced.append(figure_tariff(args.typical, args.monthly, args.output))
    for path in produced:
        if path:
            print(path)


if __name__ == "__main__":
    main()
