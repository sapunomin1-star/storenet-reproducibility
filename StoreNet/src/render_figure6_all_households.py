#!/usr/bin/env python3
"""Pool every released household into one author-style Figure 6 graphic."""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd

import reproduce_data_paper_figures as figures


DEFAULT_OUTPUT_PATH = (
    figures.PROJECT / "results" / "figure6_all_households_published_scale.png"
)
PV_HOUSES = set(figures.PV_PAPER_ORDER)


def render_combined(output_path: Path) -> Path:
    production_w: list[np.ndarray] = []
    production_equivalent: list[np.ndarray] = []
    consumption_w: list[np.ndarray] = []
    consumption_equivalent: list[np.ndarray] = []

    for house in figures.HOUSE_IDS:
        joined = figures.load_figure6_author_legacy(figures.DEFAULT_DATA_DIR, house)
        consumption_w.append(joined["Consumption(W)"].to_numpy(dtype=float))
        consumption_equivalent.append(joined["Consumption(Wh)"].to_numpy(dtype=float))
        if house in PV_HOUSES:
            production_w.append(joined["Production(W)"].to_numpy(dtype=float))
            production_equivalent.append(joined["Production(Wh)"].to_numpy(dtype=float))

    production_count = sum(values.size for values in production_w)
    consumption_count = sum(values.size for values in consumption_w)
    combined_size = max(production_count, consumption_count)
    combined = pd.DataFrame(index=np.arange(combined_size))
    combined.loc[: production_count - 1, "Production(W)"] = np.concatenate(production_w)
    combined.loc[: production_count - 1, "ProductionEquivalent(W)"] = np.concatenate(
        production_equivalent
    )
    combined.loc[: consumption_count - 1, "Consumption(W)"] = np.concatenate(
        consumption_w
    )
    combined.loc[: consumption_count - 1, "ConsumptionEquivalent(W)"] = np.concatenate(
        consumption_equivalent
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    figures.render_figure6(
        combined,
        output_path,
        axis_limits_w=figures.FIGURE6_PUBLISHED_AXIS_LIMITS_W,
        title="Figure 6 public households - published axis ranges",
        count_vmax=300_000.0,
    )
    return output_path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_PATH)
    return parser.parse_args()


if __name__ == "__main__":
    arguments = parse_args()
    print(render_combined(arguments.output.resolve()))
