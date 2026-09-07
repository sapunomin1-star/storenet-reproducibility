#!/usr/bin/env python3
"""Reproduce and audit Figures 5-10 of Trivedi et al. (2024).

The released author scripts are notebook-style files with absolute Windows
paths and several scientifically material ambiguities.  This module leaves
those files immutable and implements two explicitly separated views:

* ``paper_legacy`` follows the published plotting logic where it can be
  recovered from the release, including the Figure 7(b) daily-mean unit bug.
* ``unit_corrected`` uses timestamps and converts summed Wh to kWh/day.

Figure 10 is not fabricated.  The public release lacks the paper-specific
network model, 55-house mapping, optimisation code, and node-by-hour voltages;
the pipeline therefore emits a reproducibility-boundary artifact instead of a
synthetic surface that could be mistaken for the published result.
"""

from __future__ import annotations

import argparse
import ctypes
import errno
import hashlib
import json
import os
import platform
import re
import subprocess
import tempfile
import textwrap
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import matplotlib

matplotlib.use("Agg")
import matplotlib.dates as mdates
import matplotlib.pyplot as plt
from matplotlib.colors import LogNorm
from matplotlib.gridspec import GridSpec
from matplotlib.ticker import MaxNLocator
import numpy as np
import pandas as pd


PROJECT = Path(__file__).resolve().parents[1]
REPOSITORY = PROJECT.parent
DEFAULT_DATA_DIR = PROJECT / "data" / "raw"
DEFAULT_REFERENCE_DIR = PROJECT / "reference"
DEFAULT_OUTPUT_DIR = PROJECT / "results" / "data_paper_figures_5_10_v2"
CONTRACT_PATH = PROJECT / "docs" / "REPRODUCTION_CONTRACT.md"
DATA_PAPER_AUDIT_PATH = PROJECT / "docs" / "DATA_PAPER_FIGURES_5_10.md"
CONTRACT_ID = "SR2020-IR-v2"
FIGURE6_NORMATIVE_SIDECARS = [
    "figure6_all_house_metrics.csv",
    "figure6_h4_daily_diagnostics.csv",
    "figure6_h4_monthly_summary.csv",
    "figure6_h4_alignment_summary.csv",
    "figure6_h4_anomaly_segments.csv",
    "figure6_h4_date_transpose_diagnostics.csv",
    "figure6_h4_cross_house_controls.csv",
    "figure6_h4_wh_balance.json",
]
FIGURE6_PUBLISHED_AXIS_LIMITS_W = {
    "Production": 2600.0,
    "Consumption": 13000.0,
}
FIGURE6_PUBLISHED_TICKS_W = {
    "Production": np.arange(0.0, 2500.0 + 1.0, 500.0),
    "Consumption": np.arange(0.0, 12000.0 + 1.0, 2000.0),
}
MIN_DAILY_LAG_FINITE_POINTS = 60
MAPPED_W_STATUS_SCOPE = "source_and_mapped_target_w_status_both_endpoints"
MAPPED_W_STATUS_SCOPE_DESCRIPTION = (
    "finite mapped W/Wh pairs requiring the released W-status observation proxy at "
    "both endpoints on both the source W timestamps and mapped-target Wh timestamps; "
    "W status is not proof of Wh ground truth"
)
SOURCE_PDF = REPOSITORY / (
    "Ireland0_Comprehensive Dataset on Electrical Load Profiles for Energy "
    "Community in Ireland.pdf"
)
HOUSE_IDS = [f"H{i}" for i in range(1, 21)]
PV_PAPER_ORDER = ["H10", "H11", "H13", "H17", "H1", "H2", "H3", "H4", "H5", "H7"]
ENERGY_FLOWS = ["Production(Wh)", "Consumption(Wh)", "Feed-in(Wh)", "From grid(Wh)"]
WEEK_START = pd.Timestamp("2020-12-07 00:00:00")
WEEK_END = pd.Timestamp("2020-12-14 00:00:00")
CALENDAR_START = pd.Timestamp("2020-01-01 00:00:00")
CALENDAR_END = pd.Timestamp("2021-01-01 00:00:00")
PIPELINE_VERSION = "2.0.0"
FLOW_TO_KWH = {
    "Production(Wh)": "ProductionKWh",
    "Consumption(Wh)": "ConsumptionKWh",
    "Feed-in(Wh)": "FeedInKWh",
    "From grid(Wh)": "FromGridKWh",
}
ENGLISH_MONTHS = [
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
]


@dataclass(frozen=True)
class EnergySummary:
    totals_kwh: pd.DataFrame
    legacy_daily: pd.DataFrame
    corrected_daily: pd.DataFrame
    timestamp_coverage: pd.DataFrame


@dataclass(frozen=True)
class Figure6Audit:
    """Machine-readable evidence supporting the released-data Figure 6 audit.

    ``h4_joined`` preserves the v1 pointwise H4 view used by the plot.  The
    remaining tables make the v2 diagnosis explicit instead of treating one
    annual Pearson coefficient as sufficient evidence.
    """

    h4_joined: pd.DataFrame
    all_house_metrics: pd.DataFrame
    h4_daily_diagnostics: pd.DataFrame
    h4_monthly_summary: pd.DataFrame
    h4_alignment_summary: pd.DataFrame
    h4_anomaly_segments: pd.DataFrame
    h4_date_transpose_diagnostics: pd.DataFrame
    h4_cross_house_controls: pd.DataFrame
    h4_wh_balance: dict[str, object]


def sha256_file(path: Path, chunk_size: int = 2**20) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(chunk_size):
            digest.update(chunk)
    return digest.hexdigest()


def md5_file(path: Path, chunk_size: int = 2**20) -> str:
    """Return the legacy digest published by Figshare for integrity comparison."""

    digest = hashlib.md5()
    with path.open("rb") as stream:
        while chunk := stream.read(chunk_size):
            digest.update(chunk)
    return digest.hexdigest()


def git_capture(*args: str) -> str:
    try:
        return subprocess.check_output(
            ["git", "-C", str(REPOSITORY), *args], text=True, stderr=subprocess.DEVNULL
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        return "unavailable"


def parse_contract_id(contract_path: Path) -> str:
    """Read the canonical contract ID and reject ambiguous/missing declarations."""

    matches = re.findall(
        r"^\s*契約 ID：`([^`]+)`\s*$",
        contract_path.read_text(encoding="utf-8"),
        flags=re.MULTILINE,
    )
    if len(matches) != 1:
        raise RuntimeError(
            f"Expected exactly one canonical contract ID declaration in {contract_path}; "
            f"found {len(matches)}"
        )
    return matches[0]


def require_contract_matches_pipeline(contract_path: Path = CONTRACT_PATH) -> str:
    observed = parse_contract_id(contract_path)
    if observed != CONTRACT_ID:
        raise RuntimeError(
            f"Pipeline contract ID {CONTRACT_ID} does not match {contract_path}: {observed}"
        )
    return observed


def require_clean_tree_for_formal_publish(output_dir: Path) -> None:
    """Fail closed only for the canonical formal output, not temporary test runs."""

    if output_dir.resolve() != DEFAULT_OUTPUT_DIR.resolve():
        return
    status = git_capture("status", "--porcelain")
    if status == "unavailable":
        raise RuntimeError("Cannot verify a clean Git tree for formal v2 publication")
    if status:
        raise RuntimeError(
            "Formal v2 publication requires a clean Git tree; commit or stash changes first"
        )


def read_selected_csv(path: Path, columns: Iterable[str], parse_dates: bool = True) -> pd.DataFrame:
    wanted = set(columns)
    frame = pd.read_csv(path, usecols=lambda name: name.strip() in wanted)
    frame = frame.rename(columns=lambda name: name.strip())
    missing = wanted.difference(frame.columns)
    if missing:
        raise ValueError(f"{path} is missing required columns: {sorted(missing)}")
    if parse_dates and "date" in frame:
        frame["date"] = pd.to_datetime(frame["date"], errors="raise")
    return frame[list(columns)]


def expected_release_paths(repository: Path) -> set[str]:
    data_root = DEFAULT_DATA_DIR.resolve()
    expected_files = [
        *(data_root / f"{house}_{unit}.csv" for house in HOUSE_IDS for unit in ("W", "Wh")),
        data_root / "weather.csv",
        data_root / "README.md",
        data_root / "setup.py",
        data_root / "data_processing.py",
        data_root / "energy plots.py",
        data_root / "power plots.py",
    ]
    return {str(path.relative_to(repository.resolve())) for path in expected_files}


def verify_release_manifest(manifest_path: Path, repository: Path) -> list[dict[str, object]]:
    repository = repository.resolve()
    checks: list[dict[str, object]] = []
    seen: set[str] = set()
    for raw_line in manifest_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        expected, relative = line.split(maxsplit=1)
        relative = relative.strip()
        relative_path = Path(relative)
        if relative_path.is_absolute() or ".." in relative_path.parts:
            raise RuntimeError(f"Release manifest contains an unsafe path: {relative}")
        if relative in seen:
            raise RuntimeError(f"Release manifest contains a duplicate path: {relative}")
        seen.add(relative)
        path = (repository / relative_path).resolve()
        try:
            path.relative_to(repository)
        except ValueError as error:
            raise RuntimeError(f"Release manifest path escapes repository: {relative}") from error
        observed = sha256_file(path) if path.is_file() else None
        checks.append(
            {
                "path": relative,
                "bytes": path.stat().st_size if path.is_file() else None,
                "expected_sha256": expected,
                "observed_sha256": observed,
                "passed": observed == expected,
            }
        )
    expected_paths = expected_release_paths(repository)
    if seen != expected_paths:
        missing = sorted(expected_paths - seen)
        extra = sorted(seen - expected_paths)
        raise RuntimeError(f"Release inventory mismatch; missing={missing}, extra={extra}")
    if len(checks) != 46 or not all(item["passed"] for item in checks):
        failed = [item["path"] for item in checks if not item["passed"]]
        raise RuntimeError(f"Release integrity failed; entries={len(checks)}, failed={failed}")
    return checks


def verify_figshare_inventory(inventory_path: Path, data_dir: Path) -> list[dict[str, object]]:
    required = {
        "ArticleID",
        "ArticleDOI",
        "ArticleVersion",
        "FileID",
        "FileName",
        "Bytes",
        "OfficialMD5",
        "DownloadURL",
    }
    inventory = pd.read_csv(inventory_path, dtype={"OfficialMD5": str})
    missing_columns = required.difference(inventory.columns)
    if missing_columns:
        raise RuntimeError(f"Figshare inventory missing columns: {sorted(missing_columns)}")
    names = inventory["FileName"].astype(str)
    if names.duplicated().any():
        raise RuntimeError("Figshare inventory contains duplicate file names")
    for name in names:
        path_name = Path(name)
        if path_name.is_absolute() or path_name.name != name or ".." in path_name.parts:
            raise RuntimeError(f"Figshare inventory contains an unsafe file name: {name}")
    expected_names = {Path(path).name for path in expected_release_paths(REPOSITORY)}
    observed_names = set(names)
    if observed_names != expected_names or len(inventory) != 46:
        raise RuntimeError(
            "Figshare inventory mismatch; "
            f"missing={sorted(expected_names - observed_names)}, "
            f"extra={sorted(observed_names - expected_names)}"
        )
    if not inventory["ArticleVersion"].eq(1).all():
        raise RuntimeError("Figshare inventory contains a non-v1 article")

    checks: list[dict[str, object]] = []
    for row in inventory.itertuples(index=False):
        path = data_dir / row.FileName
        observed_size = path.stat().st_size if path.is_file() else None
        observed_md5 = md5_file(path) if path.is_file() else None
        passed = observed_size == int(row.Bytes) and observed_md5 == row.OfficialMD5
        checks.append(
            {
                "article_id": int(row.ArticleID),
                "article_doi": row.ArticleDOI,
                "article_version": int(row.ArticleVersion),
                "file_id": int(row.FileID),
                "file_name": row.FileName,
                "official_bytes": int(row.Bytes),
                "observed_bytes": observed_size,
                "official_md5": row.OfficialMD5,
                "observed_md5": observed_md5,
                "download_url": row.DownloadURL,
                "passed": passed,
            }
        )
    if not all(item["passed"] for item in checks):
        failed = [item["file_name"] for item in checks if not item["passed"]]
        raise RuntimeError(f"Figshare inventory integrity failed: {failed}")
    return checks


def require_official_input_roots(data_dir: Path, reference_dir: Path) -> None:
    if data_dir.resolve() != DEFAULT_DATA_DIR.resolve():
        raise ValueError(
            f"This audited pipeline only accepts the verified Figshare v1 root: {DEFAULT_DATA_DIR}"
        )
    if reference_dir.resolve() != DEFAULT_REFERENCE_DIR.resolve():
        raise ValueError(
            f"This audited pipeline only accepts the versioned reference root: {DEFAULT_REFERENCE_DIR}"
        )


def publish_directory_no_replace(stage: Path, target: Path) -> None:
    """Atomically publish a directory while refusing every existing target."""

    if target.exists() or target.is_symlink():
        raise FileExistsError(f"Output already exists: {target}")
    if platform.system() == "Darwin":
        libc = ctypes.CDLL(None, use_errno=True)
        renamex = libc.renamex_np
        renamex.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
        renamex.restype = ctypes.c_int
        if renamex(os.fsencode(stage), os.fsencode(target), 0x00000004) == 0:
            return
        error_number = ctypes.get_errno()
        if error_number in (errno.EEXIST, errno.ENOTEMPTY):
            raise FileExistsError(f"Output appeared during publish: {target}")
        raise OSError(error_number, os.strerror(error_number), str(target))

    lock_path = target.parent / f".{target.name}.publish.lock"
    try:
        descriptor = os.open(lock_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError as error:
        raise FileExistsError(f"Another publisher holds the output lock: {lock_path}") from error
    try:
        os.close(descriptor)
        if target.exists() or target.is_symlink():
            raise FileExistsError(f"Output appeared during publish: {target}")
        os.rename(stage, target)
    finally:
        lock_path.unlink(missing_ok=True)


def load_claims(reference_dir: Path) -> dict[str, object]:
    return json.loads((reference_dir / "data_paper_claims.json").read_text(encoding="utf-8"))


def load_figure5(data_dir: Path, reference_dir: Path) -> tuple[pd.DataFrame, np.ndarray]:
    statuses: list[np.ndarray] = []
    rows: list[dict[str, object]] = []
    max_rows = 0
    raw: dict[str, tuple[pd.DataFrame, np.ndarray]] = {}
    for house in HOUSE_IDS:
        status_column = f"{house}_W"
        frame = read_selected_csv(data_dir / f"{house}_W.csv", ["date", status_column])
        status = pd.to_numeric(frame[status_column], errors="coerce").eq(1).to_numpy(dtype=np.uint8)
        raw[house] = (frame, status)
        max_rows = max(max_rows, len(frame))

    paper = pd.read_csv(reference_dir / "data_paper_fig5_availability.csv").set_index("HouseID")
    for house in HOUSE_IDS:
        frame, status = raw[house]
        padded = np.zeros(max_rows, dtype=np.uint8)
        padded[: len(status)] = status
        statuses.append(padded)
        reproduced = 100.0 * float(status.sum()) / max_rows
        paper_value = float(paper.loc[house, "PaperAvailablePercent"])
        rows.append(
            {
                "HouseID": house,
                "RowsInFile": len(frame),
                "PlotDenominatorRows": max_rows,
                "AvailableRows": int(status.sum()),
                "MissingRowsOnPlotGrid": int(max_rows - status.sum()),
                "ReproducedAvailablePercent": reproduced,
                "PaperAvailablePercent": paper_value,
                "RoundedMatch": round(reproduced, 2) == round(paper_value, 2),
                "StartTimestamp": str(frame["date"].iloc[0]),
                "EndTimestamp": str(frame["date"].iloc[-1]),
            }
        )
    return pd.DataFrame(rows), np.vstack(statuses)


def render_figure5(summary: pd.DataFrame, matrix: np.ndarray, path: Path) -> None:
    fig = plt.figure(figsize=(15.5, 7.2), constrained_layout=True)
    grid = GridSpec(1, 3, figure=fig, width_ratios=[1.9, 9.5, 0.35])
    ax_bar = fig.add_subplot(grid[0, 0])
    ax_heat = fig.add_subplot(grid[0, 1])
    ax_cbar = fig.add_subplot(grid[0, 2])

    colours = plt.cm.Spectral(np.linspace(0.12, 0.88, len(HOUSE_IDS)))
    y = np.arange(len(HOUSE_IDS))
    ax_bar.barh(y, np.ones(len(y)), color=colours, edgecolor="white", height=0.93)
    for index, value in enumerate(summary["ReproducedAvailablePercent"]):
        ax_bar.text(0.5, index, f"{value:.2f}%", ha="center", va="center", fontsize=8.5)
    ax_bar.set_xlim(0, 1)
    ax_bar.set_ylim(len(y) - 0.5, -0.5)
    ax_bar.set_xticks([])
    ax_bar.set_yticks([])
    ax_bar.set_title("Available data", fontsize=11, pad=8)
    for spine in ax_bar.spines.values():
        spine.set_color("0.35")

    image = ax_heat.imshow(matrix, aspect="auto", interpolation="nearest", cmap="YlGnBu", vmin=0, vmax=1)
    ax_heat.set_yticks(y, HOUSE_IDS)
    ax_heat.set_ylim(len(y) - 0.5, -0.5)
    start = pd.Timestamp("2020-01-01 01:00:00")
    ticks = pd.date_range("2020-01-02", "2020-12-28", freq="10D")
    positions = ((ticks - start) / pd.Timedelta(minutes=1)).to_numpy()
    keep = (positions >= 0) & (positions < matrix.shape[1])
    ax_heat.set_xticks(positions[keep], [stamp.strftime("%b-%d-%Y") for stamp in ticks[keep]])
    ax_heat.xaxis.tick_top()
    ax_heat.tick_params(axis="x", labelrotation=90, labelsize=6)
    ax_heat.tick_params(axis="y", labelsize=9)
    colourbar = fig.colorbar(image, cax=ax_cbar)
    colourbar.set_label("Available data", fontsize=9)
    colourbar.set_ticks([0, 0.2, 0.4, 0.6, 0.8, 1.0])
    fig.suptitle("Figure 5 reproduction - household measurement availability", fontsize=14)
    fig.savefig(path, dpi=300, bbox_inches="tight", facecolor="white")
    plt.close(fig)


def _validate_figure6_timestamps(frame: pd.DataFrame, path: Path) -> None:
    if frame["date"].duplicated().any():
        raise RuntimeError(f"Figure 6 input contains duplicate timestamps: {path}")
    if not frame["date"].is_monotonic_increasing:
        raise RuntimeError(f"Figure 6 input timestamps are not monotonic: {path}")


def _read_figure6_stream(
    path: Path,
    columns: list[str],
    *,
    require_extra_index: bool = False,
) -> pd.DataFrame:
    """Read one W/Wh stream and fail closed on audit-critical schema changes."""

    wanted = set(columns)
    if require_extra_index:
        wanted.add("Unnamed: 6")
    frame = pd.read_csv(path, usecols=lambda name: name.strip() in wanted)
    frame = frame.rename(columns=lambda name: name.strip())
    missing = wanted.difference(frame.columns)
    if missing:
        raise RuntimeError(f"Figure 6 input {path} is missing columns: {sorted(missing)}")
    frame["date"] = pd.to_datetime(frame["date"], errors="raise")
    _validate_figure6_timestamps(frame, path)
    for column in wanted.difference({"date"}):
        frame[column] = pd.to_numeric(frame[column], errors="coerce")
    return frame


def _load_figure6_house(
    data_dir: Path,
    house: str,
    *,
    require_extra_index: bool = False,
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    status_column = f"{house}_W"
    power_columns = ["date", "Production(W)", "Consumption(W)", status_column]
    energy_columns = ["date", "Production(Wh)", "Consumption(Wh)"]
    power = _read_figure6_stream(
        data_dir / f"{house}_W.csv",
        power_columns,
        require_extra_index=require_extra_index,
    ).set_index("date")
    energy = _read_figure6_stream(
        data_dir / f"{house}_Wh.csv", energy_columns
    ).set_index("date")
    previous_status_observed = power[status_column].shift(1).eq(1)
    previous_minute_contiguous = power.index.to_series().diff().eq(pd.Timedelta(minutes=1))
    power["ObservedBothEndpoints"] = (
        power[status_column].eq(1)
        & previous_status_observed
        & previous_minute_contiguous
    )
    joined = power[
        ["Production(W)", "Consumption(W)", status_column, "ObservedBothEndpoints"]
    ].join(energy, how="inner")
    joined["ProductionEquivalent(W)"] = joined["Production(Wh)"] * 60.0
    joined["ConsumptionEquivalent(W)"] = joined["Consumption(Wh)"] * 60.0
    return power, energy, joined


def load_figure6_author_legacy(data_dir: Path, house: str) -> pd.DataFrame:
    """Apply the released author's Figure 6 preprocessing to one public pair."""

    def preprocess(path: Path) -> pd.DataFrame:
        frame = pd.read_csv(path).rename(columns=lambda name: name.strip())
        frame["date"] = pd.to_datetime(frame["date"], errors="raise")
        frame = frame.resample("min", on="date").min(numeric_only=True)
        after_nan = frame.isna().shift(1, fill_value=False)
        return frame.mask(after_nan).ffill()

    energy = preprocess(data_dir / f"{house}_Wh.csv")
    power = preprocess(data_dir / f"{house}_W.csv")
    joined = pd.concat(
        [
            power[["Production(W)", "Consumption(W)"]],
            energy[["Production(Wh)", "Consumption(Wh)"]],
        ],
        axis=1,
    ).iloc[1:]
    joined[["Production(Wh)", "Consumption(Wh)"]] = (
        joined[["Production(Wh)", "Consumption(Wh)"]] * 60.0
    ).round(1)
    return joined


def _pair_metrics(measured: np.ndarray, equivalent: np.ndarray) -> dict[str, object]:
    measured = np.asarray(measured, dtype=float)
    equivalent = np.asarray(equivalent, dtype=float)
    finite = np.isfinite(measured) & np.isfinite(equivalent)
    measured = measured[finite]
    equivalent = equivalent[finite]
    count = len(measured)
    if count == 0:
        return {
            "MatchedFinitePoints": 0,
            "PearsonR": np.nan,
            "RMSE_W": np.nan,
            "MAE_W": np.nan,
            "P99AbsoluteError_W": np.nan,
            "MaximumAbsoluteError_W": np.nan,
            "FractionWithin0p5W": np.nan,
            "RoundingAgreementFraction": np.nan,
            "ExactEqualityFraction": np.nan,
            "EquivalentOnMeasuredSlope": np.nan,
            "EquivalentOnMeasuredIntercept_W": np.nan,
        }

    error = equivalent - measured
    measured_variance = float(np.var(measured))
    equivalent_variance = float(np.var(equivalent))
    pearson = np.nan
    slope = np.nan
    intercept = np.nan
    if count >= 2 and measured_variance > 0.0 and equivalent_variance > 0.0:
        measured_centred = measured - float(np.mean(measured))
        equivalent_centred = equivalent - float(np.mean(equivalent))
        covariance_sum = float(np.dot(measured_centred, equivalent_centred))
        measured_square_sum = float(np.dot(measured_centred, measured_centred))
        equivalent_square_sum = float(np.dot(equivalent_centred, equivalent_centred))
        pearson = covariance_sum / np.sqrt(measured_square_sum * equivalent_square_sum)
        slope = covariance_sum / measured_square_sum
        intercept = float(np.mean(equivalent)) - slope * float(np.mean(measured))

    rounding_fraction = float(np.mean(np.abs(error) <= 0.5))
    return {
        "MatchedFinitePoints": count,
        "PearsonR": float(pearson),
        "RMSE_W": float(np.sqrt(np.mean(np.square(error)))),
        "MAE_W": float(np.mean(np.abs(error))),
        "P99AbsoluteError_W": float(np.quantile(np.abs(error), 0.99)),
        "MaximumAbsoluteError_W": float(np.max(np.abs(error))),
        "FractionWithin0p5W": rounding_fraction,
        # The explicit name is retained beside the v1-compatible column.
        "RoundingAgreementFraction": rounding_fraction,
        "ExactEqualityFraction": float(np.mean(np.isclose(error, 0.0, rtol=0.0, atol=1e-12))),
        "EquivalentOnMeasuredSlope": float(slope),
        "EquivalentOnMeasuredIntercept_W": float(intercept),
    }


def _signal_metric_row(
    joined: pd.DataFrame,
    house: str,
    signal: str,
    comparison_scope: str,
) -> dict[str, object]:
    if comparison_scope == "finite_release_same_timestamp":
        selected = joined
        scope_description = (
            "finite released values at identical published timestamps; continuity with v1"
        )
    elif comparison_scope == "observed_both_endpoints":
        selected = joined.loc[joined["ObservedBothEndpoints"]]
        scope_description = (
            "finite released values at identical timestamps, restricted to W status(t-1)==1 "
            "and status(t)==1 on a contiguous minute grid; status is only a released-data "
            "observation proxy"
        )
    else:
        raise ValueError(f"Unknown Figure 6 comparison scope: {comparison_scope}")
    measured = selected[f"{signal}(W)"].to_numpy(dtype=float)
    equivalent = selected[f"{signal}Equivalent(W)"].to_numpy(dtype=float)
    metrics = _pair_metrics(measured, equivalent)
    finite_measured = measured[np.isfinite(measured)]
    finite_equivalent = equivalent[np.isfinite(equivalent)]
    signal_available = bool(
        (finite_measured.size and np.max(np.abs(finite_measured)) > 0.0)
        or (finite_equivalent.size and np.max(np.abs(finite_equivalent)) > 0.0)
    )
    pearson = float(metrics["PearsonR"])
    pass_threshold: object
    if comparison_scope == "observed_both_endpoints":
        consistency_pass = bool(
            np.isfinite(pearson)
            and pearson >= 0.99999
            and float(metrics["P99AbsoluteError_W"]) <= 0.200000001
            and float(metrics["FractionWithin0p5W"]) >= 0.99999
        )
        gate_definition = (
            "PearsonR>=0.99999 and P99AbsoluteError_W<=0.200000001 and "
            "FractionWithin0p5W>=0.99999"
        )
    else:
        consistency_pass = bool(np.isfinite(pearson) and pearson > 0.99)
        gate_definition = "PearsonR>0.99 (v1 continuity scope)"
    if not signal_available:
        pass_threshold = pd.NA
        status = "not_applicable_zero_signal"
    elif np.isfinite(pearson):
        pass_threshold = consistency_pass
        status = "pass" if pass_threshold else "fail"
    else:
        pass_threshold = False
        status = "fail_undefined_correlation"
    return {
        "HouseID": house,
        "Signal": signal,
        "ComparisonScope": comparison_scope,
        "SignalAvailable": signal_available,
        **metrics,
        "ConsistencyThresholdPearsonR": (
            0.99999 if comparison_scope == "observed_both_endpoints" else 0.99
        ),
        "ConsistencyPass": pass_threshold,
        "ConsistencyGateDefinition": gate_definition,
        "ComparisonStatus": status,
        "PaperPearsonR": 1.0,
        "PaperClaimReproduced": bool(
            signal_available
            and np.isfinite(pearson)
            and pearson >= 0.99999
            and float(metrics["P99AbsoluteError_W"]) <= 0.200000001
            and float(metrics["FractionWithin0p5W"]) >= 0.99999
        ),
        "PaperRoundedOneDecimal": bool(np.isfinite(pearson) and round(pearson, 1) == 1.0),
        "PairingScope": scope_description,
    }


def load_figure6(data_dir: Path) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Return the v1-compatible H4 pointwise view, with expanded equality metrics."""

    _, _, joined = _load_figure6_house(data_dir, "H4")
    rows = [
        _signal_metric_row(joined, "H4", signal, "finite_release_same_timestamp")
        for signal in ("Production", "Consumption")
    ]
    return joined, pd.DataFrame(rows)


def _best_daily_lag_metrics(
    power: pd.Series,
    equivalent: pd.Series,
    day: pd.Timestamp,
    maximum_lag_minutes: int = 1440,
) -> dict[str, object]:
    """Find the Pearson-maximising Wh timestamp offset over an explicit lag range.

    A positive offset means comparing ``W(t)`` with ``60*Wh(t + offset)``.
    Pairwise finite sums are evaluated for every integer offset without filling
    missing measurements.  Ties prefer the smallest absolute offset and then
    the smaller signed offset.
    """

    def unavailable(status: str) -> dict[str, object]:
        return {
            "LagSearchMinimumMinutes": -maximum_lag_minutes,
            "LagSearchMaximumMinutes": maximum_lag_minutes,
            "LagMinimumFinitePoints": MIN_DAILY_LAG_FINITE_POINTS,
            "BestLagDiagnosticStatus": status,
            "BestWhTimestampOffsetMinutes": pd.NA,
            "BestLagAtSearchBoundary": pd.NA,
            "BestLagMatchedFinitePoints": pd.NA,
            "BestLagPearsonR": np.nan,
            "BestLagRMSE_W": np.nan,
            "BestLagMAE_W": np.nan,
            "BestLagP99AbsoluteError_W": np.nan,
            "BestLagEquivalentOnMeasuredSlope": np.nan,
            "BestLagEquivalentOnMeasuredIntercept_W": np.nan,
            "BestLagPassR0p99": pd.NA,
        }

    power_grid = pd.date_range(day, periods=1440, freq="min")
    energy_grid = pd.date_range(
        day - pd.Timedelta(minutes=maximum_lag_minutes),
        periods=1440 + 2 * maximum_lag_minutes,
        freq="min",
    )
    x = power.reindex(power_grid).to_numpy(dtype=float)
    y = equivalent.reindex(energy_grid).to_numpy(dtype=float)
    if int(np.isfinite(x).sum()) < MIN_DAILY_LAG_FINITE_POINTS:
        return unavailable("too_sparse_power_day")
    x_mask = np.isfinite(x).astype(float)
    y_mask = np.isfinite(y).astype(float)
    x_filled = np.nan_to_num(x, nan=0.0)
    y_filled = np.nan_to_num(y, nan=0.0)

    def sliding_dot(long: np.ndarray, short: np.ndarray) -> np.ndarray:
        """FFT equivalent of ``np.correlate(long, short, 'valid')``."""

        convolution_length = len(long) + len(short) - 1
        transform_length = 1 << (convolution_length - 1).bit_length()
        convolution = np.fft.irfft(
            np.fft.rfft(long, transform_length)
            * np.fft.rfft(short[::-1], transform_length),
            transform_length,
        )[:convolution_length]
        return convolution[len(short) - 1 : len(long)]

    count = sliding_dot(y_mask, x_mask)
    sum_x = sliding_dot(y_mask, x_filled)
    sum_y = sliding_dot(y_filled, x_mask)
    sum_x2 = sliding_dot(y_mask, np.square(x_filled))
    sum_y2 = sliding_dot(np.square(y_filled), x_mask)
    sum_xy = sliding_dot(y_filled, x_filled)
    with np.errstate(divide="ignore", invalid="ignore"):
        covariance = sum_xy - sum_x * sum_y / count
        variance_x = sum_x2 - np.square(sum_x) / count
        variance_y = sum_y2 - np.square(sum_y) / count
        # FFT round-off can leave a tiny positive variance for an exactly
        # constant all-zero PV day.  Scale-aware tolerances prevent those rows
        # from becoming spurious high-correlation candidates.
        tolerance_x = 1e-10 * np.maximum.reduce(
            [np.abs(sum_x2), np.abs(np.square(sum_x) / count), np.ones_like(count)]
        )
        tolerance_y = 1e-10 * np.maximum.reduce(
            [np.abs(sum_y2), np.abs(np.square(sum_y) / count), np.ones_like(count)]
        )
        denominator = np.sqrt(np.maximum(variance_x, 0.0) * np.maximum(variance_y, 0.0))
        correlation = covariance / denominator
    correlation[
        (count < MIN_DAILY_LAG_FINITE_POINTS)
        | (variance_x <= tolerance_x)
        | (variance_y <= tolerance_y)
        | (denominator <= 0.0)
    ] = np.nan
    correlation = np.clip(correlation, -1.0, 1.0)
    if not np.isfinite(correlation).any():
        return unavailable("no_eligible_finite_variance_candidate")

    best_value = float(np.nanmax(correlation))
    candidates = np.flatnonzero(np.isclose(correlation, best_value, rtol=0.0, atol=1e-12))
    candidate_lags = candidates - maximum_lag_minutes
    ordering = np.lexsort((candidate_lags, np.abs(candidate_lags)))
    best_index = int(candidates[ordering[0]])
    best_lag = best_index - maximum_lag_minutes
    best_equivalent = equivalent.reindex(
        power_grid + pd.Timedelta(minutes=best_lag)
    ).to_numpy(dtype=float)
    equality = _pair_metrics(x, best_equivalent)
    if (
        int(equality["MatchedFinitePoints"]) < MIN_DAILY_LAG_FINITE_POINTS
        or not np.isfinite(float(equality["PearsonR"]))
    ):
        return unavailable("final_candidate_nonfinite_or_too_sparse")
    return {
        "LagSearchMinimumMinutes": -maximum_lag_minutes,
        "LagSearchMaximumMinutes": maximum_lag_minutes,
        "LagMinimumFinitePoints": MIN_DAILY_LAG_FINITE_POINTS,
        "BestLagDiagnosticStatus": "ok",
        "BestWhTimestampOffsetMinutes": best_lag,
        "BestLagAtSearchBoundary": abs(best_lag) == maximum_lag_minutes,
        "BestLagMatchedFinitePoints": int(equality["MatchedFinitePoints"]),
        "BestLagPearsonR": float(equality["PearsonR"]),
        "BestLagRMSE_W": float(equality["RMSE_W"]),
        "BestLagMAE_W": float(equality["MAE_W"]),
        "BestLagP99AbsoluteError_W": float(equality["P99AbsoluteError_W"]),
        "BestLagEquivalentOnMeasuredSlope": float(equality["EquivalentOnMeasuredSlope"]),
        "BestLagEquivalentOnMeasuredIntercept_W": float(
            equality["EquivalentOnMeasuredIntercept_W"]
        ),
        "BestLagPassR0p99": bool(float(equality["PearsonR"]) > 0.99),
    }


def _h4_daily_diagnostics(
    power: pd.DataFrame,
    energy: pd.DataFrame,
    joined: pd.DataFrame,
) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    extra_present = power["Unnamed: 6"].notna()
    for day in pd.date_range("2020-01-01", "2020-12-31", freq="D"):
        end = day + pd.Timedelta(days=1)
        day_joined = joined.loc[(joined.index >= day) & (joined.index < end)]
        marker = extra_present.loc[(extra_present.index >= day) & (extra_present.index < end)]
        for signal in ("Production", "Consumption"):
            same = _pair_metrics(
                day_joined[f"{signal}(W)"].to_numpy(dtype=float),
                day_joined[f"{signal}Equivalent(W)"].to_numpy(dtype=float),
            )
            lag = _best_daily_lag_metrics(
                power[f"{signal}(W)"],
                energy[f"{signal}(Wh)"] * 60.0,
                day,
            )
            rows.append(
                {
                    "Date": day.date().isoformat(),
                    "Signal": signal,
                    "SameTimestampMatchedFinitePoints": int(same["MatchedFinitePoints"]),
                    "SameTimestampPearsonR": same["PearsonR"],
                    "SameTimestampRMSE_W": same["RMSE_W"],
                    "SameTimestampMAE_W": same["MAE_W"],
                    "SameTimestampP99AbsoluteError_W": same["P99AbsoluteError_W"],
                    "SameTimestampRoundingAgreementFraction": same[
                        "RoundingAgreementFraction"
                    ],
                    "SameTimestampEquivalentOnMeasuredSlope": same[
                        "EquivalentOnMeasuredSlope"
                    ],
                    "SameTimestampEquivalentOnMeasuredIntercept_W": same[
                        "EquivalentOnMeasuredIntercept_W"
                    ],
                    "SameTimestampPassR0p99": bool(
                        np.isfinite(float(same["PearsonR"]))
                        and float(same["PearsonR"]) > 0.99
                    ),
                    "Unnamed6PresentRows": int(marker.sum()),
                    "Unnamed6AbsentRows": int((~marker).sum()),
                    "Unnamed6PresentFraction": float(marker.mean()) if len(marker) else np.nan,
                    **lag,
                }
            )
    return pd.DataFrame(rows)


def _mapped_observed_day_pair(
    power: pd.DataFrame,
    energy: pd.DataFrame,
    power_day: pd.Timestamp,
    energy_day: pd.Timestamp | None,
    signal: str,
    offset_minutes: int,
    periods: int,
) -> tuple[np.ndarray, np.ndarray, dict[str, object]]:
    if energy_day is None:
        empty = np.array([], dtype=float)
        return empty, empty, _pair_metrics(empty, empty)
    power_grid = pd.date_range(power_day, periods=periods, freq="min")
    energy_grid = (
        energy_day
        + (power_grid - power_day)
        + pd.Timedelta(minutes=offset_minutes)
    )
    return _mapped_observed_pair(power, energy, power_grid, energy_grid, signal)


def _mapped_observed_pair(
    power: pd.DataFrame,
    energy: pd.DataFrame,
    power_grid: pd.DatetimeIndex,
    energy_grid: pd.DatetimeIndex,
    signal: str,
) -> tuple[np.ndarray, np.ndarray, dict[str, object]]:
    """Compare a mapped pair only where both W-status endpoint proxies hold.

    The Wh stream has no status column of its own.  Its mapped-target eligibility is
    therefore proxied by the corresponding W stream's ``ObservedBothEndpoints`` at
    ``energy_grid``.  Requiring both source and mapped-target proxies prevents a valid
    source minute from silently admitting a mapped Wh minute adjacent to a release gap.
    """

    if len(power_grid) != len(energy_grid):
        raise ValueError("Mapped Figure 6 grids must have equal lengths")
    measured = power[f"{signal}(W)"].reindex(power_grid).to_numpy(dtype=float)
    equivalent = (
        (energy[f"{signal}(Wh)"] * 60.0)
        .reindex(energy_grid)
        .to_numpy(dtype=float)
    )
    source_observed = power["ObservedBothEndpoints"].reindex(
        power_grid, fill_value=False
    ).to_numpy(dtype=bool)
    mapped_target_observed = power["ObservedBothEndpoints"].reindex(
        energy_grid, fill_value=False
    ).to_numpy(dtype=bool)
    observed = source_observed & mapped_target_observed
    measured = measured.copy()
    equivalent = equivalent.copy()
    measured[~observed] = np.nan
    equivalent[~observed] = np.nan
    finite = np.isfinite(measured) & np.isfinite(equivalent)
    return measured[finite], equivalent[finite], _pair_metrics(measured, equivalent)


def _h4_alignment_diagnostics(
    power: pd.DataFrame,
    energy: pd.DataFrame,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Classify all 366 H4 dates with frozen rule-based mappings and boundaries."""

    detail_rows: list[dict[str, object]] = []
    raw_pairs: dict[tuple[str, str], list[tuple[np.ndarray, np.ndarray]]] = {}
    candidate_raw_pairs: dict[
        tuple[str, str, str], list[tuple[np.ndarray, np.ndarray]]
    ] = {}
    marker = power["Unnamed: 6"].notna()

    def metric_pass(metrics: dict[str, object]) -> bool:
        value = float(metrics["PearsonR"])
        return bool(
            int(metrics["MatchedFinitePoints"]) >= MIN_DAILY_LAG_FINITE_POINTS
            and np.isfinite(value)
            and value > 0.99
        )

    for day in pd.date_range("2020-01-01", "2020-12-31", freq="D"):
        day_grid = pd.date_range(day, periods=1440, freq="min")
        affected = bool(marker.reindex(day_grid, fill_value=False).any())
        try:
            transposed_day: pd.Timestamp | None = pd.Timestamp(2020, day.day, day.month)
        except ValueError:
            transposed_day = None

        candidates: dict[str, dict[str, tuple[np.ndarray, np.ndarray, dict[str, object]]]] = {
            "same_date_0": {},
            "same_date_plus60_core": {},
            "same_date_plus60_continuous24h": {},
            "transpose_plus60_core": {},
            "transpose_plus60_continuous24h": {},
        }
        for signal in ("Production", "Consumption"):
            candidates["same_date_0"][signal] = _mapped_observed_day_pair(
                power, energy, day, day, signal, 0, 1440
            )
            candidates["same_date_plus60_core"][signal] = _mapped_observed_day_pair(
                power, energy, day, day, signal, 60, 1380
            )
            candidates["same_date_plus60_continuous24h"][signal] = (
                _mapped_observed_day_pair(power, energy, day, day, signal, 60, 1440)
            )
            candidates["transpose_plus60_core"][signal] = _mapped_observed_day_pair(
                power, energy, day, transposed_day, signal, 60, 1380
            )
            candidates["transpose_plus60_continuous24h"][signal] = (
                _mapped_observed_day_pair(
                    power, energy, day, transposed_day, signal, 60, 1440
                )
            )

        plus60_both_pass = all(
            metric_pass(candidates["same_date_plus60_core"][signal][2])
            for signal in ("Production", "Consumption")
        )
        transpose_both_pass = all(
            metric_pass(candidates["transpose_plus60_core"][signal][2])
            for signal in ("Production", "Consumption")
        )
        same0_both_pass = all(
            metric_pass(candidates["same_date_0"][signal][2])
            for signal in ("Production", "Consumption")
        )
        no_finite_w_pairs = all(
            int(candidates["same_date_0"][signal][2]["MatchedFinitePoints"]) == 0
            for signal in ("Production", "Consumption")
        )
        if not affected and no_finite_w_pairs:
            category = "unassessable_no_finite_W_pairs"
            selected_mapping = None
        elif not affected and same0_both_pass:
            category = "unaffected_same0"
            selected_mapping: str | None = "same_date_0"
        elif (
            2 <= day.month <= 8
            and 2 <= day.day <= 8
            and day.month == day.day
            and transpose_both_pass
        ):
            category = "diagonal_identity_plus60_control"
            selected_mapping = "transpose_plus60_core"
        elif (
            2 <= day.month <= 8
            and 2 <= day.day <= 8
            and day.month != day.day
            and transpose_both_pass
        ):
            category = "actual_transpose_plus60_core"
            selected_mapping = "transpose_plus60_core"
        elif plus60_both_pass:
            category = "same_date_plus60_core"
            selected_mapping = "same_date_plus60_core"
        else:
            category = "unresolved"
            selected_mapping = None

        for signal in ("Production", "Consumption"):
            selected_metrics = (
                candidates[selected_mapping][signal][2]
                if selected_mapping is not None
                else _pair_metrics(np.array([]), np.array([]))
            )
            if selected_mapping is not None:
                raw_pairs.setdefault((category, signal), []).append(
                    (
                        candidates[selected_mapping][signal][0],
                        candidates[selected_mapping][signal][1],
                    )
                )
            for candidate_name, by_signal in candidates.items():
                candidate_raw_pairs.setdefault(
                    (category, signal, candidate_name), []
                ).append((by_signal[signal][0], by_signal[signal][1]))
            row: dict[str, object] = {
                "Date": day.date().isoformat(),
                "Signal": signal,
                "AlignmentCategory": category,
                "AlignmentRule": "frozen_rule_based_v2",
                "AlignmentAffectedByUnnamed6": affected,
                "AlignmentSelectedMapping": selected_mapping or "none",
                "MappedComparisonScope": MAPPED_W_STATUS_SCOPE,
                "MappedComparisonScopeDescription": MAPPED_W_STATUS_SCOPE_DESCRIPTION,
                "AlignmentPassMinimumFinitePoints": MIN_DAILY_LAG_FINITE_POINTS,
                "AlignmentSelectedMatchedFinitePoints": int(
                    selected_metrics["MatchedFinitePoints"]
                ),
                "AlignmentSelectedPearsonR": selected_metrics["PearsonR"],
                "AlignmentSelectedRMSE_W": selected_metrics["RMSE_W"],
                "AlignmentSelectedMAE_W": selected_metrics["MAE_W"],
                "AlignmentSelectedP99AbsoluteError_W": selected_metrics[
                    "P99AbsoluteError_W"
                ],
                "AlignmentSelectedPassR0p99": metric_pass(selected_metrics),
            }
            for mapping, (_, _, metrics) in (
                (name, candidates[name][signal]) for name in candidates
            ):
                prefix = {
                    "same_date_0": "CandidateSameDate0",
                    "same_date_plus60_core": "CandidateSameDatePlus60Core",
                    "same_date_plus60_continuous24h": (
                        "CandidateSameDatePlus60Continuous24h"
                    ),
                    "transpose_plus60_core": "CandidateTransposePlus60Core",
                    "transpose_plus60_continuous24h": (
                        "CandidateTransposePlus60Continuous24h"
                    ),
                }[mapping]
                row[f"{prefix}MatchedFinitePoints"] = int(metrics["MatchedFinitePoints"])
                row[f"{prefix}PearsonR"] = metrics["PearsonR"]
                row[f"{prefix}PassR0p99"] = metric_pass(metrics)
            detail_rows.append(row)

    detail = pd.DataFrame(detail_rows)
    summary_rows: list[dict[str, object]] = []
    selected_mapping_by_category = {
        "unaffected_same0": "same_date_0",
        "unassessable_no_finite_W_pairs": "none",
        "same_date_plus60_core": "same_date_plus60_core",
        "actual_transpose_plus60_core": "transpose_plus60_core",
        "diagonal_identity_plus60_control": "transpose_plus60_core",
        "unresolved": "none",
    }
    for category in selected_mapping_by_category:
        for signal in ("Production", "Consumption"):
            selected = detail.loc[
                detail["AlignmentCategory"].eq(category) & detail["Signal"].eq(signal)
            ]
            pieces = raw_pairs.get((category, signal), [])
            if pieces:
                aggregate = _pair_metrics(
                    np.concatenate([piece[0] for piece in pieces]),
                    np.concatenate([piece[1] for piece in pieces]),
                )
            else:
                aggregate = _pair_metrics(np.array([]), np.array([]))
            continuous_pieces = candidate_raw_pairs.get(
                (category, signal, "same_date_plus60_continuous24h"), []
            )
            continuous_aggregate = (
                _pair_metrics(
                    np.concatenate([piece[0] for piece in continuous_pieces]),
                    np.concatenate([piece[1] for piece in continuous_pieces]),
                )
                if continuous_pieces
                else _pair_metrics(np.array([]), np.array([]))
            )
            continuous_failures = selected.loc[
                ~selected["CandidateSameDatePlus60Continuous24hPassR0p99"], "Date"
            ].tolist()
            summary_rows.append(
                {
                    "AlignmentCategory": category,
                    "Signal": signal,
                    "CalendarDays": int(selected["Date"].nunique()),
                    "SelectedMapping": selected_mapping_by_category[category],
                    "MappedComparisonScope": MAPPED_W_STATUS_SCOPE,
                    "MappedComparisonScopeDescription": MAPPED_W_STATUS_SCOPE_DESCRIPTION,
                    "PassMinimumFinitePoints": MIN_DAILY_LAG_FINITE_POINTS,
                    "SelectedMatchedFinitePoints": int(aggregate["MatchedFinitePoints"]),
                    "SelectedAggregatePearsonR": aggregate["PearsonR"],
                    "SelectedAggregateRMSE_W": aggregate["RMSE_W"],
                    "SelectedAggregateMAE_W": aggregate["MAE_W"],
                    "SelectedAggregateP99AbsoluteError_W": aggregate[
                        "P99AbsoluteError_W"
                    ],
                    "SelectedAggregateRoundingAgreementFraction": aggregate[
                        "RoundingAgreementFraction"
                    ],
                    "SelectedAggregateEquivalentOnMeasuredSlope": aggregate[
                        "EquivalentOnMeasuredSlope"
                    ],
                    "SelectedAggregateEquivalentOnMeasuredIntercept_W": aggregate[
                        "EquivalentOnMeasuredIntercept_W"
                    ],
                    "SelectedDaysPassR0p99": int(
                        selected["AlignmentSelectedPassR0p99"].sum()
                    ),
                    "SameDate0DaysPassR0p99": int(
                        selected["CandidateSameDate0PassR0p99"].sum()
                    ),
                    "SameDatePlus60CoreDaysPassR0p99": int(
                        selected["CandidateSameDatePlus60CorePassR0p99"].sum()
                    ),
                    "SameDatePlus60Continuous24hDaysPassR0p99": int(
                        selected[
                            "CandidateSameDatePlus60Continuous24hPassR0p99"
                        ].sum()
                    ),
                    "SameDatePlus60Continuous24hFailureDates": ";".join(
                        continuous_failures
                    ),
                    "SameDatePlus60Continuous24hMatchedFinitePoints": int(
                        continuous_aggregate["MatchedFinitePoints"]
                    ),
                    "SameDatePlus60Continuous24hAggregatePearsonR": (
                        continuous_aggregate["PearsonR"]
                    ),
                    "TransposePlus60CoreDaysPassR0p99": int(
                        selected["CandidateTransposePlus60CorePassR0p99"].sum()
                    ),
                    "TransposePlus60Continuous24hDaysPassR0p99": int(
                        selected[
                            "CandidateTransposePlus60Continuous24hPassR0p99"
                        ].sum()
                    ),
                    "BoundaryPolicy": (
                        "same_date_0 uses 1440 labels; +60 core uses W 00:00-22:59 "
                        "and target Wh 01:00-23:59; continuous24h uses all 1440 W labels "
                        "and crosses the target-day boundary; every mapping requires the "
                        "W-status both-endpoint proxy on source and mapped-target timestamps"
                    ),
                }
            )
    return detail, pd.DataFrame(summary_rows)


def _h4_monthly_summary(joined: pd.DataFrame, daily: pd.DataFrame) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    index_2020 = joined.loc[
        (joined.index >= CALENDAR_START) & (joined.index < CALENDAR_END)
    ]
    daily_work = daily.copy()
    daily_work["Month"] = pd.to_datetime(daily_work["Date"]).dt.strftime("%Y-%m")
    for month in pd.period_range("2020-01", "2020-12", freq="M"):
        month_label = str(month)
        month_joined = index_2020.loc[index_2020.index.to_period("M") == month]
        for signal in ("Production", "Consumption"):
            pooled = _pair_metrics(
                month_joined[f"{signal}(W)"].to_numpy(dtype=float),
                month_joined[f"{signal}Equivalent(W)"].to_numpy(dtype=float),
            )
            selected = daily_work.loc[
                daily_work["Month"].eq(month_label) & daily_work["Signal"].eq(signal)
            ]
            valid_same = selected["SameTimestampPearsonR"].dropna()
            valid_lag = selected["BestLagPearsonR"].dropna()
            valid_offsets = selected.loc[
                selected["BestLagPearsonR"].notna(), "BestWhTimestampOffsetMinutes"
            ].dropna().astype(int)
            mode_offset: object = pd.NA
            if not valid_offsets.empty:
                counts = valid_offsets.value_counts()
                maximum_count = int(counts.max())
                modes = counts.loc[counts.eq(maximum_count)].index.to_numpy(dtype=int)
                mode_offset = int(modes[np.lexsort((modes, np.abs(modes)))[0]])
            rows.append(
                {
                    "Month": month_label,
                    "Signal": signal,
                    "CalendarDays": int(len(selected)),
                    "DaysWithDefinedSameTimestampPearsonR": int(len(valid_same)),
                    "DaysSameTimestampPassR0p99": int(selected["SameTimestampPassR0p99"].sum()),
                    "MedianDailySameTimestampPearsonR": float(valid_same.median())
                    if len(valid_same)
                    else np.nan,
                    "PooledSameTimestampMatchedFinitePoints": int(
                        pooled["MatchedFinitePoints"]
                    ),
                    "PooledSameTimestampPearsonR": pooled["PearsonR"],
                    "PooledSameTimestampRMSE_W": pooled["RMSE_W"],
                    "PooledSameTimestampMAE_W": pooled["MAE_W"],
                    "PooledSameTimestampP99AbsoluteError_W": pooled[
                        "P99AbsoluteError_W"
                    ],
                    "DaysWithDefinedBestLagPearsonR": int(len(valid_lag)),
                    "DaysBestLagPassR0p99": int(selected["BestLagPassR0p99"].sum()),
                    "MedianDailyBestLagPearsonR": float(valid_lag.median())
                    if len(valid_lag)
                    else np.nan,
                    "MedianBestWhTimestampOffsetMinutes": float(valid_offsets.median())
                    if len(valid_offsets)
                    else np.nan,
                    "ModeBestWhTimestampOffsetMinutes": mode_offset,
                    "ModeBestWhTimestampOffsetDays": maximum_count if len(valid_offsets) else 0,
                    "LagSearchMinimumMinutes": -1440,
                    "LagSearchMaximumMinutes": 1440,
                    "Unnamed6PresentRows": int(
                        selected.drop_duplicates("Date")["Unnamed6PresentRows"].sum()
                    ),
                    "Unnamed6AbsentRows": int(
                        selected.drop_duplicates("Date")["Unnamed6AbsentRows"].sum()
                    ),
                }
            )
    return pd.DataFrame(rows)


def _h4_anomaly_segments(power: pd.DataFrame, joined: pd.DataFrame) -> pd.DataFrame:
    finite_marker = power.loc[power["Unnamed: 6"].notna(), ["Unnamed: 6"]].copy()
    if finite_marker.empty:
        raise RuntimeError("H4_W.csv has no finite Unnamed: 6 forensic index values")
    # A forensic block follows the embedded index-like values, not every blank
    # measurement hole inside a block.  A new block starts only when adjacent
    # finite marker values cease incrementing by exactly one.
    block_id = finite_marker["Unnamed: 6"].diff().ne(1.0).cumsum()
    marker_present = power["Unnamed: 6"].notna().reindex(joined.index, fill_value=False)
    populated = joined.loc[marker_present]
    blank = joined.loc[~marker_present]
    populated_production = _pair_metrics(
        populated["Production(W)"].to_numpy(dtype=float),
        populated["ProductionEquivalent(W)"].to_numpy(dtype=float),
    )
    populated_consumption = _pair_metrics(
        populated["Consumption(W)"].to_numpy(dtype=float),
        populated["ConsumptionEquivalent(W)"].to_numpy(dtype=float),
    )
    blank_production = _pair_metrics(
        blank["Production(W)"].to_numpy(dtype=float),
        blank["ProductionEquivalent(W)"].to_numpy(dtype=float),
    )
    blank_consumption = _pair_metrics(
        blank["Consumption(W)"].to_numpy(dtype=float),
        blank["ConsumptionEquivalent(W)"].to_numpy(dtype=float),
    )

    rows: list[dict[str, object]] = []
    for identifier, positions in block_id.groupby(block_id).groups.items():
        block = finite_marker.loc[positions]
        start = block.index[0]
        end = block.index[-1]
        calendar_span_rows = int((end - start) / pd.Timedelta(minutes=1)) + 1
        paired = joined.loc[(joined.index >= start) & (joined.index <= end)]
        production = _pair_metrics(
            paired["Production(W)"].to_numpy(dtype=float),
            paired["ProductionEquivalent(W)"].to_numpy(dtype=float),
        )
        consumption = _pair_metrics(
            paired["Consumption(W)"].to_numpy(dtype=float),
            paired["ConsumptionEquivalent(W)"].to_numpy(dtype=float),
        )
        rows.append(
            {
                "BlockID": int(identifier),
                "StartTimestamp": str(start),
                "EndTimestampInclusive": str(end),
                "PopulatedRows": int(len(block)),
                "CalendarSpanRows": calendar_span_rows,
                "BlankWithinSpan": calendar_span_rows - int(len(block)),
                "AffectedDays": int(block.index.normalize().nunique()),
                "IndexFirst": float(block["Unnamed: 6"].iloc[0]),
                "IndexLast": float(block["Unnamed: 6"].iloc[-1]),
                "IndexValuesSequentialWithinBlock": bool(
                    block["Unnamed: 6"].diff().dropna().eq(1.0).all()
                ),
                "BlockProductionSameTimestampPearsonR": production["PearsonR"],
                "BlockConsumptionSameTimestampPearsonR": consumption["PearsonR"],
                "AllPopulatedRowsProductionPearsonR": populated_production["PearsonR"],
                "AllPopulatedRowsConsumptionPearsonR": populated_consumption["PearsonR"],
                "AllBlankRowsProductionPearsonR": blank_production["PearsonR"],
                "AllBlankRowsConsumptionPearsonR": blank_consumption["PearsonR"],
                "Interpretation": (
                    "finite Unnamed: 6 index-like sequence; blank holes inside the calendar "
                    "span do not split the block"
                ),
            }
        )
    return pd.DataFrame(rows)


def _h4_date_transpose_diagnostics(
    power: pd.DataFrame,
    energy: pd.DataFrame,
) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    aggregate_pairs: dict[tuple[str, str], tuple[list[np.ndarray], list[np.ndarray]]] = {}
    offset = pd.Timedelta(minutes=60)
    policies = [
        (
            "within_target_day_core",
            1380,
            "W 00:00-22:59; Wh transposed target date 01:00-23:59",
            False,
        ),
        (
            "continuous_24h",
            1440,
            "W 00:00-23:59; Wh transposed target 01:00 through next date 00:59",
            True,
        ),
    ]
    for policy, periods, window_definition, crosses_next_day in policies:
        for month in range(2, 9):
            for day_of_month in range(2, 9):
                power_day = pd.Timestamp(2020, month, day_of_month)
                energy_day = pd.Timestamp(2020, day_of_month, month)
                power_grid = pd.date_range(power_day, periods=periods, freq="min")
                energy_grid = energy_day + (power_grid - power_day) + offset
                for signal in ("Production", "Consumption"):
                    measured, equivalent, metrics = _mapped_observed_pair(
                        power,
                        energy,
                        power_grid,
                        energy_grid,
                        signal,
                    )
                    key = (policy, signal)
                    if key not in aggregate_pairs:
                        aggregate_pairs[key] = ([], [])
                    aggregate_pairs[key][0].append(measured)
                    aggregate_pairs[key][1].append(equivalent)
                    rows.append(
                        {
                            "WindowPolicy": policy,
                            "WindowDefinition": window_definition,
                            "WindowCrossesNextTargetDay": crosses_next_day,
                            "WDate": power_day.date().isoformat(),
                            "WhDateAfterDayMonthTranspose": energy_day.date().isoformat(),
                            "DateActuallyChanges": power_day != energy_day,
                            "DateMappingType": (
                                "actual_month_day_transpose"
                                if power_day != energy_day
                                else "diagonal_identity_control"
                            ),
                            "WhTimestampOffsetMinutes": 60,
                            "Signal": signal,
                            "ComparisonScope": MAPPED_W_STATUS_SCOPE,
                            "ComparisonScopeDescription": (
                                MAPPED_W_STATUS_SCOPE_DESCRIPTION
                            ),
                            "PassMinimumFinitePoints": MIN_DAILY_LAG_FINITE_POINTS,
                            **metrics,
                            "PassR0p99": bool(
                                int(metrics["MatchedFinitePoints"])
                                >= MIN_DAILY_LAG_FINITE_POINTS
                                and np.isfinite(float(metrics["PearsonR"]))
                                and float(metrics["PearsonR"]) > 0.99
                            ),
                            "CohortDefinition": (
                                "2020 dates with W month and day both in 2..8; compare with Wh "
                                "after transposing month/day and adding 60 minutes"
                            ),
                        }
                    )
    result = pd.DataFrame(rows)
    for (policy, signal), (measured_parts, equivalent_parts) in aggregate_pairs.items():
        aggregate = _pair_metrics(
            np.concatenate(measured_parts), np.concatenate(equivalent_parts)
        )
        selected = result["WindowPolicy"].eq(policy) & result["Signal"].eq(signal)
        result.loc[selected, "PolicySignalAggregateMatchedFinitePoints"] = int(
            aggregate["MatchedFinitePoints"]
        )
        result.loc[selected, "PolicySignalAggregatePearsonR"] = float(
            aggregate["PearsonR"]
        )
        result.loc[selected, "PolicySignalDaysPassR0p99"] = int(
            result.loc[selected, "PassR0p99"].sum()
        )
        result.loc[selected, "PolicySignalCohortDays"] = int(
            result.loc[selected, "WDate"].nunique()
        )
    return result


def _cross_house_control_rows(
    h4_power: pd.DataFrame,
    h4_energy: pd.DataFrame,
    other_house: str,
    other_power: pd.DataFrame,
    other_energy: pd.DataFrame,
) -> list[dict[str, object]]:
    start = pd.Timestamp("2020-02-01 00:00:00")
    end = pd.Timestamp("2020-09-01 00:00:00")
    specifications = [
        (
            "H4_W_vs_other_house_Wh",
            h4_power["Consumption(W)"],
            other_energy["Consumption(Wh)"] * 60.0,
            h4_power["ObservedBothEndpoints"],
            other_power["ObservedBothEndpoints"],
        ),
        (
            "other_house_W_vs_H4_Wh",
            other_power["Consumption(W)"],
            h4_energy["Consumption(Wh)"] * 60.0,
            other_power["ObservedBothEndpoints"],
            h4_power["ObservedBothEndpoints"],
        ),
    ]
    rows: list[dict[str, object]] = []
    for direction, measured, equivalent, measured_observed, equivalent_observed in specifications:
        pair = pd.concat(
            [
                measured.rename("Measured"),
                equivalent.rename("Equivalent"),
                measured_observed.rename("MeasuredObservedBothEndpoints"),
                equivalent_observed.rename("EquivalentObservedBothEndpoints"),
            ],
            axis=1,
            join="inner",
        )
        pair = pair.loc[(pair.index >= start) & (pair.index < end)]
        for comparison_scope in (
            "finite_release_same_timestamp",
            "observed_both_endpoints",
        ):
            selected = (
                pair
                if comparison_scope == "finite_release_same_timestamp"
                else pair.loc[
                    pair["MeasuredObservedBothEndpoints"].fillna(False)
                    & pair["EquivalentObservedBothEndpoints"].fillna(False)
                    & (pair.index >= start + pd.Timedelta(minutes=1))
                ]
            )
            metrics = _pair_metrics(
                selected["Measured"].to_numpy(dtype=float),
                selected["Equivalent"].to_numpy(dtype=float),
            )
            rows.append(
                {
                    "Direction": direction,
                    "OtherHouseID": other_house,
                    "Signal": "Consumption",
                    "ComparisonScope": comparison_scope,
                    "ScopeStartInclusive": str(start),
                    "ScopeEndExclusive": str(end),
                    "WhTimestampOffsetMinutes": 0,
                    **metrics,
                    "AbsolutePearsonRBelow0p11": bool(
                        abs(float(metrics["PearsonR"])) < 0.11
                    ),
                    "InterpretationLimit": (
                        "same-timestamp consumption control only; does not exclude every "
                        "possible cross-house or preprocessing defect"
                    ),
                }
            )
    return rows


def _h4_wh_balance(data_dir: Path) -> dict[str, object]:
    columns = [
        "date",
        "Discharge(Wh)",
        "Charge(Wh)",
        "Production(Wh)",
        "Consumption(Wh)",
        "Feed-in(Wh)",
        "From grid(Wh)",
    ]
    frame = read_selected_csv(data_dir / "H4_Wh.csv", columns)
    residual = (
        frame["From grid(Wh)"]
        + frame["Production(Wh)"]
        + frame["Discharge(Wh)"]
        - frame["Consumption(Wh)"]
        - frame["Charge(Wh)"]
        - frame["Feed-in(Wh)"]
    ).to_numpy(dtype=float)
    residual = residual[np.isfinite(residual)]
    absolute = np.abs(residual)
    return {
        "Equation": (
            "FromGrid(Wh) + Production(Wh) + Discharge(Wh) - Consumption(Wh) "
            "- Charge(Wh) - FeedIn(Wh)"
        ),
        "FiniteRows": int(len(residual)),
        "MeanResidualWh": float(np.mean(residual)),
        "MeanAbsoluteResidualWh": float(np.mean(absolute)),
        "MaximumAbsoluteResidualWh": float(np.max(absolute)),
        "RowsAbsoluteResidualAbove1eMinus9Wh": int(np.sum(absolute > 1e-9)),
        "Classification": "internal_consistency_support_only_not_root_cause_proof",
        "Caveat": (
            "A balanced processed Wh table supports internal consistency, but does not "
            "prove that Wh is raw ground truth or that W alone caused the mismatch."
        ),
    }


def load_figure6_audit(data_dir: Path) -> Figure6Audit:
    """Build the complete v2 Figure 6 audit from immutable released CSV files."""

    h4_power, h4_energy, h4_joined = _load_figure6_house(
        data_dir, "H4", require_extra_index=True
    )
    all_house_rows: list[dict[str, object]] = []
    cross_house_rows: list[dict[str, object]] = []
    for house in HOUSE_IDS:
        if house == "H4":
            power, energy, joined = h4_power, h4_energy, h4_joined
        else:
            power, energy, joined = _load_figure6_house(data_dir, house)
        for signal in ("Production", "Consumption"):
            for comparison_scope in (
                "finite_release_same_timestamp",
                "observed_both_endpoints",
            ):
                all_house_rows.append(
                    _signal_metric_row(joined, house, signal, comparison_scope)
                )
        if house != "H4":
            cross_house_rows.extend(
                _cross_house_control_rows(h4_power, h4_energy, house, power, energy)
            )

    all_house = pd.DataFrame(all_house_rows)
    all_house["HouseOrder"] = all_house["HouseID"].str.removeprefix("H").astype(int)
    all_house = all_house.sort_values(
        ["HouseOrder", "Signal", "ComparisonScope"]
    ).drop(
        columns="HouseOrder"
    ).reset_index(drop=True)
    daily = _h4_daily_diagnostics(h4_power, h4_energy, h4_joined)
    alignment_detail, alignment_summary = _h4_alignment_diagnostics(
        h4_power, h4_energy
    )
    daily = daily.merge(
        alignment_detail,
        on=["Date", "Signal"],
        how="left",
        validate="one_to_one",
    )
    if daily["AlignmentCategory"].isna().any():
        raise RuntimeError("H4 daily alignment classification is incomplete")
    return Figure6Audit(
        h4_joined=h4_joined,
        all_house_metrics=all_house,
        h4_daily_diagnostics=daily,
        h4_monthly_summary=_h4_monthly_summary(h4_joined, daily),
        h4_alignment_summary=alignment_summary,
        h4_anomaly_segments=_h4_anomaly_segments(h4_power, h4_joined),
        h4_date_transpose_diagnostics=_h4_date_transpose_diagnostics(
            h4_power, h4_energy
        ),
        h4_cross_house_controls=pd.DataFrame(cross_house_rows),
        h4_wh_balance=_h4_wh_balance(data_dir),
    )


def render_figure6(
    joined: pd.DataFrame,
    path: Path,
    *,
    axis_limits_w: dict[str, float] | None = None,
    title: str = "Figure 6 released-data audit - H4 power and one-minute energy consistency",
    signals: tuple[str, ...] = ("Production", "Consumption"),
    count_vmax: float | None = None,
) -> None:
    fig, axes_grid = plt.subplots(
        1,
        len(signals),
        figsize=(7.25 * len(signals), 6.2),
        squeeze=False,
    )
    axes = axes_grid.ravel()
    for ax, signal in zip(axes, signals):
        paired = joined[[f"{signal}(W)", f"{signal}Equivalent(W)"]].dropna()
        measured = paired[f"{signal}(W)"].to_numpy(dtype=float)
        equivalent = paired[f"{signal}Equivalent(W)"].to_numpy(dtype=float)
        data_upper = max(float(np.max(measured)), float(np.max(equivalent)))
        upper = (
            float(axis_limits_w[signal])
            if axis_limits_w is not None
            else data_upper
        )
        visible = (
            (measured >= 0.0)
            & (measured <= upper)
            & (equivalent >= 0.0)
            & (equivalent <= upper)
        )
        hb = ax.hexbin(
            measured[visible],
            equivalent[visible],
            gridsize=50,
            mincnt=1,
            cmap="inferno",
            norm=LogNorm(vmin=1.0, vmax=count_vmax),
            extent=(0.0, upper, 0.0, upper),
        )
        ax.set_xlim(0, upper)
        ax.set_ylim(0, upper)
        if axis_limits_w is not None:
            ticks = FIGURE6_PUBLISHED_TICKS_W[signal]
            ax.set_xticks(ticks)
            ax.set_yticks(ticks)
        ax.set_facecolor("black")
        ax.set_xlabel(f"Measured Power ({signal} (W))")
        ax.set_ylabel(f"Energy-equivalent power ({signal}, W)")
        colourbar = fig.colorbar(hb, ax=ax)
        if count_vmax is not None:
            colourbar.set_ticks([1, 10, 100, 1_000, 10_000, 100_000])
        colourbar.set_label("Counts (log scale)")
    fig.suptitle(title, fontsize=14)
    fig.tight_layout()
    fig.savefig(path, dpi=300, bbox_inches="tight", facecolor="white")
    plt.close(fig)


def render_figure6_author_legacy(
    joined: pd.DataFrame,
    path: Path,
    *,
    signals: tuple[str, ...] = ("Production", "Consumption"),
) -> None:
    """Render with the author's Figure 6 hexbin, limits, labels, and layout."""

    fig, axes_grid = plt.subplots(
        ncols=len(signals),
        sharey=False,
        figsize=(8.0 * len(signals), 8.0),
        dpi=300,
        squeeze=False,
    )
    axes = axes_grid.ravel()
    for index, (axis, signal) in enumerate(zip(axes, signals)):
        paired = joined[[f"{signal}(W)", f"{signal}(Wh)"]].dropna()
        measured = paired[f"{signal}(W)"]
        equivalent = paired[f"{signal}(Wh)"]
        hexbin = axis.hexbin(
            measured,
            equivalent,
            gridsize=50,
            bins="log",
            cmap="inferno",
        )
        axis.set(
            xlim=(float(measured.min()), float(measured.max())),
            ylim=(float(equivalent.min()), float(equivalent.max())),
        )
        axis.set_facecolor("black")
        axis.tick_params(axis="both", which="major", labelsize=14)
        axis.tick_params(axis="both", which="minor", labelsize=14)
        axis.set_ylabel(
            f"Measured Energy ({signal} (Wh)/h in W)",
            fontsize=16.0,
        )
        axis.set_xlabel(
            f"Measured Power ({signal} (W) in W)",
            fontsize=16.0,
        )
        colourbar = fig.colorbar(hexbin, ax=axis)
        if signal == "Consumption" or (len(signals) == 1 and index == 0):
            colourbar.set_label("Counts at log10(N)")
    fig.savefig(path, dpi=300, facecolor="white")
    plt.close(fig)


def render_figure6_all_house_consistency(metrics: pd.DataFrame, path: Path) -> None:
    """Render the all-house comparison directly from its exported sidecar table."""

    fig, axes = plt.subplots(2, 1, figsize=(14.5, 9.2), sharex=True, constrained_layout=True)
    house_positions = np.arange(len(HOUSE_IDS))
    scope_styles = {
        "finite_release_same_timestamp": (-0.13, "o", "released finite"),
        "observed_both_endpoints": (0.13, "^", "status(t-1)=status(t)=1"),
    }
    for axis, signal in zip(axes, ("Production", "Consumption")):
        for scope, (offset, marker, label) in scope_styles.items():
            selected = metrics.loc[
                metrics["Signal"].eq(signal) & metrics["ComparisonScope"].eq(scope)
            ].set_index("HouseID").reindex(HOUSE_IDS)
            values = selected["PearsonR"].to_numpy(dtype=float)
            colours = np.where(np.array(HOUSE_IDS) == "H4", "#c62828", "#1769aa")
            axis.scatter(
                house_positions + offset,
                values,
                marker=marker,
                s=52,
                c=colours,
                edgecolors="white",
                linewidths=0.6,
                label=label,
                zorder=3,
            )
        axis.axhline(0.99, color="#d97706", linestyle="--", linewidth=1.2, label="r = 0.99")
        axis.axvspan(2.55, 3.45, color="#c62828", alpha=0.08)
        axis.set_ylim(0.45, 1.01)
        axis.set_ylabel("Same-timestamp Pearson r")
        axis.set_title(f"{signal}: H4 is the sole active-signal full-year outlier")
        axis.grid(True, axis="y", color="0.88", linewidth=0.7)
        axis.legend(loc="lower right", ncol=3, fontsize=8.5)
    axes[-1].set_xticks(house_positions, HOUSE_IDS)
    axes[-1].set_xlabel("Household")
    fig.suptitle(
        "Figure 6 v2 audit - all-house W versus 60 x Wh consistency",
        fontsize=14,
    )
    fig.savefig(path, dpi=300, bbox_inches="tight", facecolor="white")
    plt.close(fig)


def render_figure6_h4_temporal_diagnostics(
    daily: pd.DataFrame,
    blocks: pd.DataFrame,
    transpose: pd.DataFrame,
    path: Path,
) -> None:
    """Render H4 timing evidence only from the three exported sidecar tables."""

    daily_plot = daily.copy()
    daily_plot["Date"] = pd.to_datetime(daily_plot["Date"], errors="raise")
    fig, axes = plt.subplots(2, 1, figsize=(15, 9.3), sharex=True, constrained_layout=True)
    colours = {"Production": "#2a9d8f", "Consumption": "#3f51b5"}
    for block in blocks.itertuples(index=False):
        start = pd.Timestamp(block.StartTimestamp).normalize()
        end = pd.Timestamp(block.EndTimestampInclusive).normalize() + pd.Timedelta(days=1)
        for axis in axes:
            axis.axvspan(start, end, color="#ef5350", alpha=0.055, linewidth=0)

    for signal, colour in colours.items():
        selected = daily_plot.loc[daily_plot["Signal"].eq(signal)]
        axes[0].plot(
            selected["Date"],
            selected["SameTimestampPearsonR"],
            marker=".",
            markersize=3,
            linewidth=0.75,
            color=colour,
            label=signal,
        )
        valid_lag = selected.loc[selected["BestLagPearsonR"] > 0.99]
        axes[1].scatter(
            valid_lag["Date"],
            valid_lag["BestWhTimestampOffsetMinutes"],
            s=10,
            color=colour,
            alpha=0.8,
            label=f"{signal}, best r > 0.99",
        )

    axes[0].axhline(0.99, color="#d97706", linestyle="--", linewidth=1.1)
    axes[0].set_ylim(-0.08, 1.03)
    axes[0].set_ylabel("Daily same-timestamp r")
    axes[0].set_title("Daily same-timestamp agreement; pale red spans are 20 index-like H4 blocks")
    axes[0].legend(loc="lower right")
    axes[1].axhline(0, color="0.35", linewidth=0.8)
    axes[1].axhline(60, color="#d97706", linestyle="--", linewidth=1.2, label="+60 min")
    axes[1].set_ylim(-90, 150)
    axes[1].set_ylabel("Best Wh timestamp offset (min)")
    axes[1].set_xlabel("Published W date (2020)")
    axes[1].set_title("Daily +/-1440 min search; only high-correlation solutions shown")
    axes[1].legend(loc="upper right", ncol=2, fontsize=8.5)
    for axis in axes:
        axis.grid(True, color="0.88", linewidth=0.7)
        axis.xaxis.set_major_locator(mdates.MonthLocator())
        axis.xaxis.set_major_formatter(mdates.DateFormatter("%Y-%m"))

    policy_counts = (
        transpose.groupby(["WindowPolicy", "Signal"], sort=False)["PassR0p99"]
        .sum()
        .astype(int)
    )
    core_text = (
        "transpose grid +60 min (42 actual + 7 identity controls): core window "
        f"P {policy_counts.get(('within_target_day_core', 'Production'), 0)}/49, "
        f"C {policy_counts.get(('within_target_day_core', 'Consumption'), 0)}/49; "
        "continuous 24 h "
        f"P {policy_counts.get(('continuous_24h', 'Production'), 0)}/49, "
        f"C {policy_counts.get(('continuous_24h', 'Consumption'), 0)}/49"
    )
    fig.suptitle(f"Figure 6 v2 H4 temporal diagnostics\n{core_text}", fontsize=13.5)
    fig.savefig(path, dpi=300, bbox_inches="tight", facecolor="white")
    plt.close(fig)


def load_energy_summary(data_dir: Path) -> EnergySummary:
    totals: dict[str, dict[str, float]] = {}
    row_consumption: list[np.ndarray] = []
    timestamp_grid = pd.date_range(CALENDAR_START, CALENDAR_END, freq="min", inclusive="left")
    aggregate_wh = np.zeros(len(timestamp_grid), dtype=float)
    coverage_homes = np.zeros(len(timestamp_grid), dtype=np.int16)

    for house in HOUSE_IDS:
        frame = read_selected_csv(data_dir / f"{house}_Wh.csv", ["date", *ENERGY_FLOWS])
        for column in ENERGY_FLOWS:
            frame[column] = pd.to_numeric(frame[column], errors="coerce")
        calendar_frame = frame.loc[
            (frame["date"] >= CALENDAR_START) & (frame["date"] < CALENDAR_END)
        ]
        totals[house] = {}
        for column in ENERGY_FLOWS:
            output_name = FLOW_TO_KWH[column]
            totals[house][f"PaperLegacy{output_name}"] = float(
                frame[column].sum(skipna=True) / 1000.0
            )
            totals[house][f"Calendar2020{output_name}"] = float(
                calendar_frame[column].sum(skipna=True) / 1000.0
            )
        totals[house].update(
            {
                "ReleasedRows": int(len(frame)),
                "ReleaseStartTimestamp": str(frame["date"].min()),
                "ReleaseEndTimestamp": str(frame["date"].max()),
            }
        )
        consumption = frame["Consumption(Wh)"].to_numpy(dtype=float)
        row_consumption.append(consumption)

        series = pd.Series(consumption, index=frame["date"])
        aligned = series.reindex(timestamp_grid)
        finite = aligned.notna().to_numpy()
        aggregate_wh += aligned.fillna(0.0).to_numpy(dtype=float)
        coverage_homes += finite.astype(np.int16)

    max_rows = max(map(len, row_consumption))
    legacy_aggregate = np.zeros(max_rows, dtype=float)
    legacy_coverage = np.zeros(max_rows, dtype=np.int16)
    for values in row_consumption:
        finite = np.isfinite(values)
        legacy_aggregate[: len(values)] += np.nan_to_num(values, nan=0.0)
        legacy_coverage[: len(values)] += finite.astype(np.int16)
    artificial_dates = pd.date_range("2020-01-01 00:00:00", periods=max_rows, freq="min")
    legacy_minute = pd.DataFrame(
        {
            "LegacyMeanInputWh": legacy_aggregate,
            "HomesPresent": legacy_coverage,
        },
        index=artificial_dates,
    )
    legacy_daily = legacy_minute.resample("D").agg(
        LegacyMeanWhPerMinute=("LegacyMeanInputWh", "mean"),
        MinimumHomesPresent=("HomesPresent", "min"),
        Minutes=("HomesPresent", "size"),
    )
    legacy_daily.index.name = "Date"

    timestamp_minute = pd.DataFrame(
        {"AggregateConsumptionWh": aggregate_wh, "HomesPresent": coverage_homes},
        index=timestamp_grid,
    )
    corrected_daily = timestamp_minute.resample("D").agg(
        ReleasedProcessedConsumptionKWh=(
            "AggregateConsumptionWh", lambda values: values.sum() / 1000.0
        ),
        MinimumHomesPresent=("HomesPresent", "min"),
        MaximumHomesPresent=("HomesPresent", "max"),
        Minutes=("HomesPresent", "size"),
    )
    corrected_daily["ReleasedGridComplete"] = (
        corrected_daily["MinimumHomesPresent"].eq(len(HOUSE_IDS))
        & corrected_daily["MaximumHomesPresent"].eq(len(HOUSE_IDS))
        & corrected_daily["Minutes"].eq(1440)
    )
    corrected_daily["ReleasedGridCompleteConsumptionKWh"] = corrected_daily[
        "ReleasedProcessedConsumptionKWh"
    ].where(corrected_daily["ReleasedGridComplete"])
    corrected_daily.index.name = "Date"
    timestamp_coverage = timestamp_minute.resample("D").agg(
        MinimumHomesPresent=("HomesPresent", "min"),
        MaximumHomesPresent=("HomesPresent", "max"),
        MeanHomesPresent=("HomesPresent", "mean"),
        Minutes=("HomesPresent", "size"),
    )
    timestamp_coverage.index.name = "Date"

    totals_frame = pd.DataFrame.from_dict(totals, orient="index")
    totals_frame.index.name = "HouseID"
    totals_frame = totals_frame.loc[HOUSE_IDS].reset_index()
    totals_frame["ReleaseIntervalComplete"] = (
        totals_frame["ReleasedRows"].eq(totals_frame["ReleasedRows"].max())
        & totals_frame["ReleaseStartTimestamp"].eq(totals_frame["ReleaseStartTimestamp"].min())
        & totals_frame["ReleaseEndTimestamp"].eq(totals_frame["ReleaseEndTimestamp"].max())
    )
    return EnergySummary(totals_frame, legacy_daily, corrected_daily, timestamp_coverage)


def load_weather_daily(data_dir: Path) -> pd.Series:
    weather = pd.read_csv(data_dir / "weather.csv", usecols=["date", "drybulb"])
    weather["date"] = pd.to_datetime(weather["date"], dayfirst=True, errors="raise")
    weather["drybulb"] = pd.to_numeric(weather["drybulb"], errors="coerce")
    return weather.set_index("date")["drybulb"].resample("D").mean().rename("AmbientTemperatureC")


def merge_daily_with_weather(daily: pd.DataFrame, weather: pd.Series) -> pd.DataFrame:
    merged = daily.join(weather, how="inner").dropna(subset=["AmbientTemperatureC"])
    merged.index.name = "Date"
    return merged


def render_figure7(
    totals: pd.DataFrame,
    legacy_weather: pd.DataFrame,
    paper_annual: pd.DataFrame,
    path: Path,
) -> None:
    fig = plt.figure(figsize=(15, 11.5), constrained_layout=True)
    grid = GridSpec(2, 1, figure=fig, height_ratios=[1, 1.5])
    ax_bar = fig.add_subplot(grid[0, 0])
    colours = plt.cm.YlGnBu(np.linspace(0.08, 0.95, len(HOUSE_IDS)))
    values = (
        totals.set_index("HouseID")
        .loc[HOUSE_IDS, "PaperLegacyConsumptionKWh"]
        .to_numpy()
    )
    bars = ax_bar.bar(HOUSE_IDS, values, color=colours, edgecolor="white")
    for bar, value in zip(bars, values):
        ax_bar.text(bar.get_x() + bar.get_width() / 2, value + 55, f"{value:.1f}", ha="center", fontsize=8)
    ax_bar.set_ylabel("Annual energy consumption (kWh/annum)")
    ax_bar.set_xlabel("House ID")
    ax_bar.set_ylim(0, max(values) * 1.12)
    recomputed_mean = float(values.mean())
    caption_mean = float(paper_annual.attrs["caption_mean"])
    ax_bar.set_title(
        f"(a) Paper-legacy full-release household totals - bars mean {recomputed_mean:.2f} kWh; "
        f"paper caption says {caption_mean:.2f} kWh"
    )

    ax_energy = fig.add_subplot(grid[1, 0])
    dates = legacy_weather.index
    energy = legacy_weather["LegacyMeanWhPerMinute"]
    temperature = legacy_weather["AmbientTemperatureC"]
    ax_energy.fill_between(dates, energy, color="blue", alpha=0.4, label="Consumption")
    ax_energy.set_xlabel("Date")
    ax_energy.set_ylabel("Consumption (paper label: kWh/day)")
    ax_energy.grid(True, color="0.8", linewidth=0.7)
    ax_energy.xaxis.set_major_locator(mdates.MonthLocator(interval=2))
    ax_energy.xaxis.set_major_formatter(mdates.DateFormatter("%Y-%m"))
    ax_temp = ax_energy.twinx()
    ax_temp.plot(dates, temperature, color="tab:red", linewidth=1.2, label="Ambient Temperature")
    ax_temp.set_ylabel("Temperature (degrees C)")
    ax_temp.set_ylim(bottom=0)
    handles1, labels1 = ax_energy.get_legend_handles_labels()
    handles2, labels2 = ax_temp.get_legend_handles_labels()
    ax_energy.legend(handles1 + handles2, labels1 + labels2, loc="upper left")
    ax_energy.set_title("(b) Daily Energy Consumption and Ambient Temperature - paper legacy calculation")
    fig.suptitle("Figure 7 reproduction", fontsize=15)
    fig.savefig(path, dpi=300, bbox_inches="tight", facecolor="white")
    plt.close(fig)


def render_figure7_corrected(
    legacy_weather: pd.DataFrame, corrected_weather: pd.DataFrame, path: Path
) -> None:
    fig, axes = plt.subplots(2, 1, figsize=(13.5, 8.5), sharex=True, constrained_layout=True)
    axes[0].fill_between(
        legacy_weather.index,
        legacy_weather["LegacyMeanWhPerMinute"],
        color="#5965e8",
        alpha=0.65,
    )
    axes[0].set_ylabel("Mean aggregate Wh/min")
    axes[0].set_title("Published-code quantity (incorrectly labelled kWh/day in the paper)")
    axes[1].plot(
        corrected_weather.index,
        corrected_weather["ReleasedProcessedConsumptionKWh"],
        color="0.55",
        linewidth=0.8,
        label="Available released processed series",
    )
    axes[1].fill_between(
        corrected_weather.index,
        corrected_weather["ReleasedGridCompleteConsumptionKWh"],
        color="#179c78",
        alpha=0.72,
        label="20-home released-grid-complete days",
    )
    axes[1].set_ylabel("Aggregate kWh/day")
    complete_days = int(corrected_weather["ReleasedGridComplete"].sum())
    axes[1].set_title(
        f"Timestamp-aware sum / 1000; {complete_days} days have 20 finite released processed series"
    )
    axes[1].set_xlabel("Date")
    axes[1].legend(loc="upper left")
    for ax in axes:
        ax.grid(True, color="0.85", linewidth=0.7)
    axes[1].xaxis.set_major_locator(mdates.MonthLocator(interval=2))
    axes[1].xaxis.set_major_formatter(mdates.DateFormatter("%Y-%m"))
    fig.suptitle("Figure 7(b) audit - legacy quantity versus corrected daily energy", fontsize=14)
    fig.savefig(path, dpi=300, bbox_inches="tight", facecolor="white")
    plt.close(fig)


def close_polar(values: np.ndarray, labels: list[str]) -> tuple[np.ndarray, np.ndarray, list[str]]:
    angles = np.linspace(0, 2 * np.pi, len(labels), endpoint=False)
    return np.append(angles, angles[0]), np.append(values, values[0]), labels + [labels[0]]


def render_figure8(totals: pd.DataFrame, path: Path) -> None:
    indexed = totals.set_index("HouseID")
    panels = [
        ("PaperLegacyProductionKWh", "Production (kWh)", "skyblue", "gray"),
        ("PaperLegacyConsumptionKWh", "Consumption (kWh)", "lightslategray", "lightcoral"),
        ("PaperLegacyFeedInKWh", "Energy feed to utility grid (kWh)", "peru", "orangered"),
        ("PaperLegacyFromGridKWh", "Energy from utility grid (kWh)", "steelblue", "mediumpurple"),
    ]
    fig, axes = plt.subplots(2, 2, figsize=(13.5, 11), subplot_kw={"projection": "polar"})
    for ax, (column, title, fill, line) in zip(axes.flat, panels):
        values = indexed.loc[PV_PAPER_ORDER, column].to_numpy(dtype=float)
        angles, closed, _ = close_polar(values, PV_PAPER_ORDER)
        ax.plot(angles, closed, color=line, linewidth=1.8, marker="o", markersize=3.5)
        ax.fill(angles, closed, color=fill, alpha=0.88)
        ax.set_xticks(angles[:-1], PV_PAPER_ORDER)
        ax.set_rlabel_position(5)
        ax.yaxis.set_major_locator(MaxNLocator(nbins=5))
        ax.tick_params(axis="y", labelsize=8, pad=2)
        ax.set_title(title, pad=18, fontsize=12, fontweight="bold")
        ax.grid(color="white", linewidth=0.9)
        ax.set_facecolor("#eaf1fa")
    fig.suptitle(
        "Figure 8 reproduction - paper-legacy full-release energy profiles of PV houses",
        fontsize=15,
    )
    fig.tight_layout()
    fig.savefig(path, dpi=300, bbox_inches="tight", facecolor="white")
    plt.close(fig)


def load_figure9(data_dir: Path) -> tuple[pd.DataFrame, dict[str, object]]:
    columns = [
        "date",
        "Discharge(Wh)",
        "Charge(Wh)",
        "Production(Wh)",
        "Consumption(Wh)",
        "Feed-in(Wh)",
        "From grid(Wh)",
        "State of Charge(%)",
    ]
    frame = read_selected_csv(data_dir / "H4_Wh.csv", columns)
    dt_hours = frame["date"].diff().dt.total_seconds().div(3600.0)
    flow_columns = [column for column in columns if column.endswith("(Wh)")]
    for column in flow_columns:
        frame[column.replace("(Wh)", "(W)")] = pd.to_numeric(frame[column], errors="coerce").div(dt_hours)
    week = frame.loc[(frame["date"] >= WEEK_START) & (frame["date"] < WEEK_END)].copy()
    expected_index = pd.date_range(WEEK_START, WEEK_END, freq="min", inclusive="left")
    actual_index = pd.DatetimeIndex(week["date"])
    unique_actual = actual_index.drop_duplicates()
    exact_sequence = actual_index.equals(expected_index)
    flow_w_columns = [column.replace("(Wh)", "(W)") for column in flow_columns]
    nonfinite_derived_rows = int(
        (~np.isfinite(week[flow_w_columns].to_numpy(dtype=float))).any(axis=1).sum()
    )
    balance = (
        week["From grid(Wh)"]
        + week["Production(Wh)"]
        + week["Discharge(Wh)"]
        - week["Consumption(Wh)"]
        - week["Charge(Wh)"]
        - week["Feed-in(Wh)"]
    )
    metrics: dict[str, object] = {
        "Start": str(week["date"].min()),
        "End": str(week["date"].max()),
        "Rows": int(len(week)),
        "DuplicateTimestamps": int(week["date"].duplicated().sum()),
        "MissingMinutes": int(len(expected_index.difference(unique_actual))),
        "UnexpectedTimestamps": int(len(unique_actual.difference(expected_index))),
        "TimestampSequenceExact": bool(exact_sequence),
        "TimestampsMonotonicIncreasing": bool(actual_index.is_monotonic_increasing),
        "NonfiniteDerivedPowerRows": nonfinite_derived_rows,
        "MaximumAbsoluteBalanceResidualWh": float(balance.abs().max()),
        "MaximumStateOfChargePercent": float(week["State of Charge(%)"].max()),
        "MinimumStateOfChargePercent": float(week["State of Charge(%)"].min()),
    }
    for signal in ("Production", "Consumption", "From grid", "Feed-in", "Charge", "Discharge"):
        metrics[f"Maximum{signal.replace(' ', '')}W"] = float(week[f"{signal}(W)"].max())
    daily = week.set_index("date").resample("D")[["Production(Wh)", "Consumption(Wh)", "Feed-in(Wh)", "From grid(Wh)"]].sum() / 1000.0
    metrics["DailyEnergyKWh"] = {
        str(day.date()): {column.replace("(Wh)", "KWh"): float(value) for column, value in row.items()}
        for day, row in daily.iterrows()
    }
    return week, metrics


def render_figure9(week: pd.DataFrame, path: Path) -> None:
    panels = [
        ("Production(W)", "Production (W)", "mediumseagreen"),
        ("Consumption(W)", "Consumption (W)", "purple"),
        ("From grid(W)", "From grid (W)", "gray"),
        ("Feed-in(W)", "Feed-in (W)", "plum"),
        ("Charge(W)", "Charge (W)", "green"),
        ("Discharge(W)", "Discharge (W)", "orange"),
        ("State of Charge(%)", "State of Charge (%)", "magenta"),
    ]
    fig, axes = plt.subplots(7, 1, figsize=(15, 10.5), sharex=True, constrained_layout=True)
    dates = week["date"]
    for ax, (column, label, colour) in zip(axes, panels):
        values = pd.to_numeric(week[column], errors="coerce").to_numpy(dtype=float)
        ax.fill_between(dates, values, 0, color=colour, alpha=0.95, linewidth=0.25)
        ax.plot(dates, values, color=colour, linewidth=0.35)
        ax.legend([label], loc="upper left", frameon=False, fontsize=9)
        ax.margins(x=0)
    ticks = pd.date_range(WEEK_START, WEEK_END, freq="D", inclusive="left")
    axes[-1].set_xticks(
        ticks,
        [f"{day.day:02d}\n{ENGLISH_MONTHS[day.month - 1]}\n{day.year}" for day in ticks],
    )
    axes[-1].set_xlabel("Date (07/12/2020 to 13/12/2020)")
    fig.supylabel('Power profiles for house ID "H4"')
    fig.suptitle("Figure 9 reproduction - H4 one-week power and battery operation", fontsize=14)
    fig.savefig(path, dpi=300, bbox_inches="tight", facecolor="white")
    plt.close(fig)


def render_figure10_boundary(path: Path) -> None:
    fig, ax = plt.subplots(figsize=(14, 8.2))
    ax.axis("off")
    ax.text(
        0.5,
        0.94,
        "Figure 10 audit - exact surface cannot be regenerated from the released StoreNet data",
        ha="center",
        va="top",
        fontsize=16,
        fontweight="bold",
    )
    ax.text(
        0.5,
        0.875,
        "Published Figure 10 is a reprint of Saif et al. (2023), Figure 13 (DOI 10.1016/j.egyr.2023.05.005)",
        ha="center",
        va="top",
        fontsize=11.5,
    )
    public = [
        "IEEE European LV feeder: 55 single-phase customers; public stock model",
        "Phase allocation: A/B/C = 21/19/15 customers",
        "Flat/SToU tariffs, 10 kWh / 3.3 kW battery structure, and VUF definition",
        "Likely representative days: 16 Jan 2020 and 21 Jun 2020 (context inference)",
    ]
    missing = [
        "Modified 350 kVA paper-specific circuit and exact transformer/source settings",
        "Mapping/scaling of 20 load and 10 PV profiles onto 55 customer nodes",
        "Per-house PV sizes, power factor, loss weight, optimisation code and tie handling",
        "55 x 24 node phasors or VUF matrices used for the published surfaces",
    ]
    boxes = [
        (0.04, 0.18, 0.43, 0.58, "Public structural inputs", public, "#e7f6ec", "#237a3b"),
        (0.53, 0.18, 0.43, 0.58, "Missing exact-reproduction inputs", missing, "#fff0e5", "#b64b15"),
    ]
    for x, y, width, height, title, items, face, edge in boxes:
        patch = plt.Rectangle((x, y), width, height, transform=ax.transAxes, facecolor=face, edgecolor=edge, linewidth=2)
        ax.add_patch(patch)
        ax.text(x + 0.02, y + height - 0.05, title, transform=ax.transAxes, fontsize=13, fontweight="bold", color=edge)
        cursor = y + height - 0.13
        for item in items:
            wrapped = textwrap.fill(item, width=49, subsequent_indent="  ")
            ax.text(
                x + 0.03,
                cursor,
                f"- {wrapped}",
                transform=ax.transAxes,
                fontsize=9.2,
                va="top",
                linespacing=1.25,
            )
            cursor -= 0.125
    ax.text(
        0.5,
        0.095,
        "Classification: STRUCTURAL ONLY / POINTWISE EXACT REPRODUCTION NOT SUPPORTED",
        ha="center",
        va="center",
        fontsize=14,
        fontweight="bold",
        color="#9b1c1c",
    )
    ax.text(
        0.5,
        0.045,
        "No synthetic VUF surface is shown: doing so would create new assumptions and could be mistaken for the paper result.",
        ha="center",
        va="center",
        fontsize=10.5,
    )
    fig.savefig(path, dpi=300, bbox_inches="tight", facecolor="white")
    plt.close(fig)


def validation_row(
    figure: str,
    check: str,
    expected: object,
    observed: object,
    status: str,
    note: str,
) -> dict[str, object]:
    return {
        "Figure": figure,
        "Check": check,
        "Expected": expected,
        "Observed": observed,
        "Status": status,
        "Note": note,
    }


def make_readme(summary: dict[str, object]) -> str:
    statuses = summary["figure_status"]
    return f"""# Scientific Data Figures 5-10 reproduction

This directory is generated from the 46-file Figshare v1 release.  The source
files passed SHA-256 verification before plotting.  A visual match is never used
as the sole acceptance criterion; CSV/JSON evidence is saved beside every plot.

| Figure | Result | Meaning |
|---|---|---|
| 5 | {statuses['5']} | Status-field availability for the 20 released W files. |
| 6 | {statuses['6']} | The 20-house audit supports general W/Wh consistency, isolates H4 as the released-data outlier, and provides time/date assembly evidence. |
| 7(a) | {statuses['7a']} | All 20 printed bars match; the caption mean conflicts with their arithmetic mean. |
| 7(b) | {statuses['7b']} | Legacy curve/r reproduced, but its published kWh/day unit is wrong; processed-series correction included. |
| 8 | {statuses['8']} | Paper-legacy and strict calendar-2020 PV-house totals are both exported. |
| 9 | {statuses['9']} | H4 7-13 Dec one-minute profiles reproduced; daily evidence is exported. |
| 10 | {statuses['10']} | Reprinted network-study surface lacks public pointwise inputs; boundary artifact only. |

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
"""


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def generate(data_dir: Path, reference_dir: Path, output_dir: Path) -> dict[str, object]:
    require_official_input_roots(data_dir, reference_dir)
    contract_id = require_contract_matches_pipeline()
    require_clean_tree_for_formal_publish(output_dir)
    if output_dir.exists() or output_dir.is_symlink():
        raise FileExistsError(f"Output already exists; choose a new run directory: {output_dir}")
    output_dir.parent.mkdir(parents=True, exist_ok=True)
    manifest_path = PROJECT / "data" / "RELEASE_MANIFEST.sha256"
    release_checks = verify_release_manifest(manifest_path, REPOSITORY)
    figshare_inventory_path = reference_dir / "figshare_v1_inventory.csv"
    figshare_checks = verify_figshare_inventory(figshare_inventory_path, data_dir)
    claims = load_claims(reference_dir)
    pipeline_files = [
        Path(__file__).resolve(),
        PROJECT / "tests" / "test_data_paper_figures.py",
        PROJECT / "requirements-figures.txt",
        CONTRACT_PATH,
        DATA_PAPER_AUDIT_PATH,
        reference_dir / "data_paper_claims.json",
        reference_dir / "data_paper_fig5_availability.csv",
        reference_dir / "data_paper_fig7_annual_consumption.csv",
        figshare_inventory_path,
    ]
    provenance = {
        "pipeline_version": PIPELINE_VERSION,
        "contractId": contract_id,
        "contractSha256": sha256_file(CONTRACT_PATH),
        "git_commit": git_capture("rev-parse", "HEAD"),
        "git_status_before_run": git_capture("status", "--porcelain"),
        "resolved_paths": {
            "data_dir": str(data_dir.resolve()),
            "reference_dir": str(reference_dir.resolve()),
            "output_dir": str(output_dir.resolve()),
            "source_pdf": str(SOURCE_PDF.resolve()),
        },
        "python": platform.python_version(),
        "platform": platform.platform(),
        "numpy": np.__version__,
        "pandas": pd.__version__,
        "matplotlib": matplotlib.__version__,
        "timestamp_basis": "timezone unknown; naive timestamps preserved exactly as published",
        "analysis_intervals": {
            "paper_legacy_annual": (
                "all released rows per household; endpoints and row counts are saved in sidecars; "
                "many files extend through 2021-01-01 00:59"
            ),
            "unit_corrected_daily": (
                "2020-01-01 00:00 inclusive to 2021-01-01 00:00 exclusive; "
                "released processed values, not raw-observation completeness"
            ),
            "figure9": "2020-12-07 00:00 inclusive to 2020-12-14 00:00 exclusive",
            "figure6_cross_house_control": (
                "2020-02-01 00:00 inclusive to 2020-09-01 00:00 exclusive; "
                "same-timestamp Consumption only"
            ),
            "figure6_daily_lag_search": (
                "calendar 2020; integer Wh timestamp offsets from -1440 to +1440 minutes"
            ),
        },
        "data_manifest_sha256": sha256_file(manifest_path),
        "source_pdf_sha256": sha256_file(SOURCE_PDF) if SOURCE_PDF.is_file() else None,
        "pipeline_file_sha256": {
            str(path.relative_to(REPOSITORY)): sha256_file(path) for path in pipeline_files
        },
        "verified_release_file_count": len(release_checks),
        "verified_figshare_inventory_file_count": len(figshare_checks),
    }

    with tempfile.TemporaryDirectory(prefix=f".{output_dir.name}.staging-", dir=output_dir.parent) as temp:
        stage = Path(temp)
        validation: list[dict[str, object]] = []

        fig5, availability_matrix = load_figure5(data_dir, reference_dir)
        fig5.to_csv(stage / "figure5_availability.csv", index=False)
        render_figure5(fig5, availability_matrix, stage / "figure5_data_availability.png")
        validation.append(
            validation_row(
                "5",
                "20 published availability percentages after two-decimal rounding",
                "20/20",
                f"{int(fig5['RoundedMatch'].sum())}/20",
                "pass" if bool(fig5["RoundedMatch"].all()) else "fail",
                "Author plotting denominator is 527040 rows; paper text states 527039.",
            )
        )

        fig6 = load_figure6_audit(data_dir)
        fig6_metrics = fig6.all_house_metrics
        fig6_metrics.to_csv(stage / "figure6_all_house_metrics.csv", index=False)
        fig6.h4_daily_diagnostics.to_csv(
            stage / "figure6_h4_daily_diagnostics.csv", index=False
        )
        fig6.h4_monthly_summary.to_csv(
            stage / "figure6_h4_monthly_summary.csv", index=False
        )
        fig6.h4_alignment_summary.to_csv(
            stage / "figure6_h4_alignment_summary.csv", index=False
        )
        fig6.h4_anomaly_segments.to_csv(
            stage / "figure6_h4_anomaly_segments.csv", index=False
        )
        fig6.h4_date_transpose_diagnostics.to_csv(
            stage / "figure6_h4_date_transpose_diagnostics.csv", index=False
        )
        fig6.h4_cross_house_controls.to_csv(
            stage / "figure6_h4_cross_house_controls.csv", index=False
        )
        write_json(stage / "figure6_h4_wh_balance.json", fig6.h4_wh_balance)
        render_figure6(fig6.h4_joined, stage / "figure6_power_energy_consistency.png")
        render_figure6_all_house_consistency(
            fig6.all_house_metrics, stage / "figure6_all_house_consistency.png"
        )
        render_figure6_h4_temporal_diagnostics(
            fig6.h4_daily_diagnostics,
            fig6.h4_anomaly_segments,
            fig6.h4_date_transpose_diagnostics,
            stage / "figure6_h4_temporal_diagnostics.png",
        )
        h4_metrics = fig6_metrics.loc[
            fig6_metrics["HouseID"].eq("H4")
            & fig6_metrics["ComparisonScope"].eq("finite_release_same_timestamp")
        ]
        for row in h4_metrics.itertuples(index=False):
            validation.append(
                validation_row(
                    "6",
                    f"H4 {row.Signal} same-timestamp Pearson correlation",
                    1.0,
                    row.PearsonR,
                    "expected_limitation" if not row.PaperClaimReproduced else "pass",
                    (
                        "The public H4 pair cannot reproduce the published pointwise panel; "
                        "v2 sidecars diagnose release-time date/offset assembly evidence."
                    ),
                )
            )
        scope_counts: dict[str, dict[str, object]] = {}
        for comparison_scope in (
            "finite_release_same_timestamp",
            "observed_both_endpoints",
        ):
            scope_frame = fig6_metrics.loc[
                fig6_metrics["ComparisonScope"].eq(comparison_scope)
            ]
            consumption_metrics = scope_frame.loc[
                scope_frame["Signal"].eq("Consumption")
            ]
            production_metrics = scope_frame.loc[
                scope_frame["Signal"].eq("Production")
                & scope_frame["SignalAvailable"]
            ]
            unavailable_production = scope_frame.loc[
                scope_frame["Signal"].eq("Production")
                & ~scope_frame["SignalAvailable"]
            ]
            scope_counts[comparison_scope] = {
                "consumption_passes": int(
                    consumption_metrics["ConsistencyPass"].eq(True).sum()
                ),
                "consumption_available": int(len(consumption_metrics)),
                "production_passes": int(
                    production_metrics["ConsistencyPass"].eq(True).sum()
                ),
                "production_available": int(len(production_metrics)),
                "consumption_house_ids": sorted(consumption_metrics["HouseID"].tolist()),
                "consumption_failed_house_ids": sorted(
                    consumption_metrics.loc[
                        ~consumption_metrics["ConsistencyPass"].eq(True), "HouseID"
                    ].tolist()
                ),
                "production_available_house_ids": sorted(
                    production_metrics["HouseID"].tolist()
                ),
                "production_failed_house_ids": sorted(
                    production_metrics.loc[
                        ~production_metrics["ConsistencyPass"].eq(True), "HouseID"
                    ].tolist()
                ),
                "production_unavailable_house_ids": sorted(
                    unavailable_production["HouseID"].tolist()
                ),
            }
        transpose_core = fig6.h4_date_transpose_diagnostics.loc[
            fig6.h4_date_transpose_diagnostics["WindowPolicy"].eq(
                "within_target_day_core"
            )
        ]
        transpose_continuous = fig6.h4_date_transpose_diagnostics.loc[
            fig6.h4_date_transpose_diagnostics["WindowPolicy"].eq("continuous_24h")
        ]
        core_production_passes = int(
            transpose_core.loc[transpose_core["Signal"].eq("Production"), "PassR0p99"].sum()
        )
        core_consumption_passes = int(
            transpose_core.loc[transpose_core["Signal"].eq("Consumption"), "PassR0p99"].sum()
        )
        continuous_production_passes = int(
            transpose_continuous.loc[
                transpose_continuous["Signal"].eq("Production"), "PassR0p99"
            ].sum()
        )
        continuous_consumption = transpose_continuous.loc[
            transpose_continuous["Signal"].eq("Consumption")
        ]
        continuous_consumption_passes = int(continuous_consumption["PassR0p99"].sum())
        transpose_all_days_sufficient = bool(
            fig6.h4_date_transpose_diagnostics["MatchedFinitePoints"]
            .ge(MIN_DAILY_LAG_FINITE_POINTS)
            .all()
        )
        continuous_consumption_aggregate_r = float(
            continuous_consumption["PolicySignalAggregatePearsonR"].iloc[0]
        )
        extra_present_rows = int(fig6.h4_anomaly_segments["PopulatedRows"].sum())
        extra_affected_days = int(fig6.h4_anomaly_segments["AffectedDays"].sum())
        cross_house_max_absolute_r = float(
            fig6.h4_cross_house_controls["PearsonR"].abs().max()
        )
        cross_house_max_by_scope = {
            scope: float(group["PearsonR"].abs().max())
            for scope, group in fig6.h4_cross_house_controls.groupby("ComparisonScope")
        }
        expected_cross_keys = {
            (house, direction, scope)
            for house in HOUSE_IDS
            if house != "H4"
            for direction in (
                "H4_W_vs_other_house_Wh",
                "other_house_W_vs_H4_Wh",
            )
            for scope in (
                "finite_release_same_timestamp",
                "observed_both_endpoints",
            )
        }
        observed_cross_keys = set(
            fig6.h4_cross_house_controls[
                ["OtherHouseID", "Direction", "ComparisonScope"]
            ].itertuples(index=False, name=None)
        )
        cross_house_keys_exact = observed_cross_keys == expected_cross_keys
        cross_house_all_finite = bool(
            np.isfinite(fig6.h4_cross_house_controls["PearsonR"].to_numpy(dtype=float)).all()
        )
        alignment_days = {
            row.AlignmentCategory: int(row.CalendarDays)
            for row in fig6.h4_alignment_summary.loc[
                fig6.h4_alignment_summary["Signal"].eq("Consumption")
            ].itertuples(index=False)
        }
        alignment_daily = fig6.h4_daily_diagnostics.loc[
            fig6.h4_daily_diagnostics["Signal"].eq("Consumption")
        ].copy()
        alignment_date_sets = {
            category: set(
                alignment_daily.loc[
                    alignment_daily["AlignmentCategory"].eq(category), "Date"
                ].tolist()
            )
            for category in alignment_days
        }
        unassessable_alignment_dates = alignment_date_sets.get(
            "unassessable_no_finite_W_pairs", set()
        )
        core_aligned_dates = set().union(
            alignment_date_sets.get("same_date_plus60_core", set()),
            alignment_date_sets.get("actual_transpose_plus60_core", set()),
            alignment_date_sets.get("diagonal_identity_plus60_control", set()),
        )
        unresolved_alignment_dates = alignment_date_sets.get("unresolved", set())
        marker_affected_dates = set(
            alignment_daily.loc[
                alignment_daily["AlignmentAffectedByUnnamed6"], "Date"
            ].tolist()
        )
        marker_alignment_partition_exact = bool(
            len(marker_affected_dates) == 219
            and len(core_aligned_dates) == 184
            and len(unresolved_alignment_dates) == 35
            and marker_affected_dates
            == core_aligned_dates.union(unresolved_alignment_dates)
            and marker_affected_dates.isdisjoint(
                alignment_date_sets.get("unaffected_same0", set())
                | unassessable_alignment_dates
            )
        )
        unresolved_alignment = fig6.h4_alignment_summary.loc[
            fig6.h4_alignment_summary["AlignmentCategory"].eq("unresolved")
        ]
        unresolved_candidates_all_zero = bool(
            unresolved_alignment[
                [
                    "SameDate0DaysPassR0p99",
                    "SameDatePlus60CoreDaysPassR0p99",
                    "TransposePlus60CoreDaysPassR0p99",
                ]
            ].eq(0).all().all()
        )
        clean_alignment_categories = [
            "unaffected_same0",
            "same_date_plus60_core",
            "actual_transpose_plus60_core",
            "diagonal_identity_plus60_control",
        ]
        clean_alignment = fig6.h4_alignment_summary.loc[
            fig6.h4_alignment_summary["AlignmentCategory"].isin(
                clean_alignment_categories
            )
        ]
        clean_alignment_evidence_complete = bool(
            clean_alignment["SelectedMatchedFinitePoints"].gt(0).all()
            and np.isfinite(
                clean_alignment["SelectedAggregatePearsonR"].to_numpy(dtype=float)
            ).all()
            and clean_alignment["SelectedDaysPassR0p99"]
            .eq(clean_alignment["CalendarDays"])
            .all()
        )
        same60_alignment = fig6.h4_alignment_summary.loc[
            fig6.h4_alignment_summary["AlignmentCategory"].eq(
                "same_date_plus60_core"
            )
        ]
        same60_consumption = same60_alignment.loc[
            same60_alignment["Signal"].eq("Consumption")
        ].iloc[0]
        same60_continuous_failure_dates = {
            date
            for date in str(
                same60_consumption["SameDatePlus60Continuous24hFailureDates"]
            ).split(";")
            if date
        }
        figure6_validation_rows: list[dict[str, object]] = []
        for comparison_scope, counts in scope_counts.items():
            scope_gate_label = (
                "joint r/error/rounding gate"
                if comparison_scope == "observed_both_endpoints"
                else "same-timestamp Pearson r > 0.99 continuity gate"
            )
            figure6_validation_rows.extend(
                [
                validation_row(
                    "6",
                    (
                        f"all-house Consumption streams passing {scope_gate_label} "
                        f"({comparison_scope})"
                    ),
                    "19/20",
                    f"{counts['consumption_passes']}/{counts['consumption_available']}",
                    "pass"
                    if counts["consumption_passes"] == 19
                    and counts["consumption_available"] == 20
                    and counts["consumption_house_ids"] == sorted(HOUSE_IDS)
                    and counts["consumption_failed_house_ids"] == ["H4"]
                    else "fail",
                    "H4 is the sole full-year outlier.",
                ),
                validation_row(
                    "6",
                    (
                        f"PV Production streams passing {scope_gate_label} "
                        f"({comparison_scope})"
                    ),
                    "9/10",
                    f"{counts['production_passes']}/{counts['production_available']}",
                    "pass"
                    if counts["production_passes"] == 9
                    and counts["production_available"] == 10
                    and counts["production_available_house_ids"]
                    == sorted(PV_PAPER_ORDER)
                    and counts["production_failed_house_ids"] == ["H4"]
                    and counts["production_unavailable_house_ids"]
                    == sorted(set(HOUSE_IDS) - set(PV_PAPER_ORDER))
                    else "fail",
                    "The ten zero-production houses are explicitly marked not applicable.",
                ),
                ]
            )
        figure6_validation_rows.extend(
            [
                validation_row(
                    "6",
                    "H4 W extra-index finite rows",
                    "20 blocks / 314742 rows / 219 affected days",
                    (
                        f"{len(fig6.h4_anomaly_segments)} blocks / {extra_present_rows} rows / "
                        f"{extra_affected_days} affected days"
                    ),
                    "pass"
                    if len(fig6.h4_anomaly_segments) == 20
                    and extra_present_rows == 314742
                    and extra_affected_days == 219
                    else "fail",
                    "Blocks split when adjacent finite Unnamed: 6 values do not increment by one.",
                ),
                validation_row(
                    "6",
                    (
                        "H4 date-transpose within-target-day core controls passing "
                        "N>=60 and r > 0.99"
                    ),
                    "42 actual transposes + 7 diagonal identity controls; both signals 49/49",
                    f"Production {core_production_passes}/49; Consumption {core_consumption_passes}/49",
                    "pass"
                    if core_production_passes == 49 and core_consumption_passes == 49
                    else "fail",
                    "W 00:00-22:59 maps to transposed Wh date 01:00-23:59 at +60 min.",
                ),
                validation_row(
                    "6",
                    (
                        "H4 date-transpose continuous-24h controls passing "
                        "N>=60 and r > 0.99"
                    ),
                    (
                        "same source-and-mapped-target W-status proxy scope; "
                        "Production 49/49; Consumption 29/49"
                    ),
                    (
                        f"Production {continuous_production_passes}/49; "
                        f"Consumption {continuous_consumption_passes}/49; "
                        f"aggregate r={continuous_consumption_aggregate_r:.9f}"
                    ),
                    "pass"
                    if continuous_production_passes == 49
                    and continuous_consumption_passes == 29
                    and transpose_all_days_sufficient
                    and transpose_continuous["ComparisonScope"]
                    .eq(MAPPED_W_STATUS_SCOPE)
                    .all()
                    else "fail",
                    "The explicit boundary-crossing policy prevents a cherry-picked window claim.",
                ),
                validation_row(
                    "6",
                    "maximum absolute cross-house control Pearson correlation",
                    "<0.11",
                    json.dumps(cross_house_max_by_scope, sort_keys=True),
                    "pass"
                    if cross_house_keys_exact
                    and cross_house_all_finite
                    and cross_house_max_absolute_r < 0.11
                    else "fail",
                    (
                        "Scope is Consumption, same timestamps, 2020-02-01 through "
                        "2020-09-01, and 19 other houses in both directions."
                    ),
                ),
                validation_row(
                    "6",
                    "H4 frozen rule-based daily alignment classification",
                    (
                        "146 unaffected / 1 unassessable / 135 same-date +60 core / "
                        "42 actual transpose +60 core / 7 diagonal controls / 35 unresolved"
                    ),
                    json.dumps(alignment_days, sort_keys=True),
                    "pass"
                    if alignment_days
                    == {
                        "unaffected_same0": 146,
                        "unassessable_no_finite_W_pairs": 1,
                        "same_date_plus60_core": 135,
                        "actual_transpose_plus60_core": 42,
                        "diagonal_identity_plus60_control": 7,
                        "unresolved": 35,
                    }
                    and unresolved_candidates_all_zero
                    and clean_alignment_evidence_complete
                    else "fail",
                    (
                        "The unresolved category has zero r>0.99 days under same-date 0, "
                        "same-date +60, and date-transpose +60 candidates for both signals."
                    ),
                ),
                validation_row(
                    "6",
                    "H4 affected same-date +60 core versus continuous-24h boundary check",
                    (
                        "Consumption core 135/135; continuous 131/135; failures "
                        "2020-05-31,2020-06-30,2020-07-31,2020-08-31"
                    ),
                    (
                        f"core {int(same60_consumption['SelectedDaysPassR0p99'])}/135; "
                        "continuous "
                        f"{int(same60_consumption['SameDatePlus60Continuous24hDaysPassR0p99'])}/135; "
                        f"failures {sorted(same60_continuous_failure_dates)}"
                    ),
                    "pass"
                    if int(same60_consumption["SelectedDaysPassR0p99"]) == 135
                    and int(
                        same60_consumption[
                            "SameDatePlus60Continuous24hDaysPassR0p99"
                        ]
                    )
                    == 131
                    and same60_continuous_failure_dates
                    == {
                        "2020-05-31",
                        "2020-06-30",
                        "2020-07-31",
                        "2020-08-31",
                    }
                    else "fail",
                    (
                        "The 184 affected aligned dates are core-window evidence only; "
                        "they are not claimed as full-day repairs."
                    ),
                ),
                validation_row(
                    "6",
                    "H4 Wh finite-row energy-balance residual",
                    "526979 internally balanced processed rows",
                    fig6.h4_wh_balance["FiniteRows"],
                    "supporting_evidence",
                    "Internal consistency is not proof that Wh is raw truth or W is the sole defect.",
                ),
            ]
        )
        validation.extend(figure6_validation_rows)

        energy = load_energy_summary(data_dir)
        weather = load_weather_daily(data_dir)
        legacy_weather = merge_daily_with_weather(energy.legacy_daily, weather)
        corrected_weather = merge_daily_with_weather(energy.corrected_daily, weather)
        paper_annual = pd.read_csv(reference_dir / "data_paper_fig7_annual_consumption.csv")
        paper_annual.attrs["caption_mean"] = float(claims["figure7"]["paper_caption_mean_annual_kwh"])
        annual = energy.totals_kwh[
            [
                "HouseID",
                "PaperLegacyConsumptionKWh",
                "Calendar2020ConsumptionKWh",
                "ReleasedRows",
                "ReleaseStartTimestamp",
                "ReleaseEndTimestamp",
                "ReleaseIntervalComplete",
            ]
        ].merge(paper_annual, on="HouseID")
        annual = annual.rename(
            columns={"PaperLegacyConsumptionKWh": "PaperLegacyReproducedConsumptionKWh"}
        )
        annual["RoundedMatch"] = annual["PaperLegacyReproducedConsumptionKWh"].round(1).eq(
            annual["PaperAnnualConsumptionKWh"].round(1)
        )
        annual.to_csv(stage / "figure7_annual_consumption.csv", index=False)
        legacy_weather.reset_index().to_csv(stage / "figure7b_paper_legacy_daily.csv", index=False)
        corrected_weather.reset_index().to_csv(stage / "figure7b_unit_corrected_daily.csv", index=False)
        energy.timestamp_coverage.reset_index().to_csv(stage / "figure7b_timestamp_coverage.csv", index=False)
        render_figure7(
            energy.totals_kwh,
            legacy_weather,
            paper_annual,
            stage / "figure7_annual_and_temperature.png",
        )
        render_figure7_corrected(
            legacy_weather,
            corrected_weather,
            stage / "figure7b_unit_corrected_comparison.png",
        )
        reproduced_mean = float(annual["PaperLegacyReproducedConsumptionKWh"].mean())
        calendar_2020_mean = float(annual["Calendar2020ConsumptionKWh"].mean())
        caption_mean = float(claims["figure7"]["paper_caption_mean_annual_kwh"])
        legacy_r = float(legacy_weather[["LegacyMeanWhPerMinute", "AmbientTemperatureC"]].corr().iloc[0, 1])
        corrected_r = float(
            corrected_weather[["ReleasedGridCompleteConsumptionKWh", "AmbientTemperatureC"]]
            .corr()
            .iloc[0, 1]
        )
        complete_days = int(corrected_weather["ReleasedGridComplete"].sum())
        validation.extend(
            [
                validation_row(
                    "7a",
                    "20 annual bar labels after one-decimal rounding",
                    "20/20",
                    f"{int(annual['RoundedMatch'].sum())}/20",
                    "pass" if bool(annual["RoundedMatch"].all()) else "fail",
                    "Direct sums of released Consumption(Wh).",
                ),
                validation_row(
                    "7a",
                    "Calendar-2020 mean after excluding 2021-01-01 rows",
                    "informational",
                    calendar_2020_mean,
                    "corrected_companion",
                    "H14 remains a partial-year release; no missing tail is fabricated or annualised.",
                ),
                validation_row(
                    "7a",
                    "Mean annual consumption stated in caption",
                    caption_mean,
                    reproduced_mean,
                    "paper_internal_conflict",
                    "The arithmetic mean of the 20 published bars is 5003.11 kWh, not 5025.64 kWh.",
                ),
                validation_row(
                    "7b",
                    "Paper Pearson correlation rounded to two decimals",
                    -0.31,
                    legacy_r,
                    "pass" if round(legacy_r, 2) == -0.31 else "fail",
                    "This reproduces the legacy daily mean quantity, not a correctly converted daily kWh total.",
                ),
                validation_row(
                    "7b",
                    "Released-grid-complete 20-home days",
                    345,
                    complete_days,
                    "pass" if complete_days == 345 else "fail",
                    "Means finite processed values for all houses, not complete raw observations; interpolation masks are unpublished.",
                ),
                validation_row(
                    "7b",
                    "Released-grid-complete timestamp-aware Pearson correlation",
                    "informational",
                    corrected_r,
                    "corrected_companion",
                    "Daily sum of processed Wh divided by 1000, restricted to 20 finite released series.",
                ),
            ]
        )

        pv_totals = energy.totals_kwh.set_index("HouseID").loc[PV_PAPER_ORDER].reset_index()
        pv_totals.to_csv(stage / "figure8_pv_annual_totals.csv", index=False)
        render_figure8(energy.totals_kwh, stage / "figure8_pv_annual_profiles.png")
        production = pv_totals["PaperLegacyProductionKWh"]
        detected_pv = set(
            energy.totals_kwh.loc[
                energy.totals_kwh["PaperLegacyProductionKWh"] > 1.0, "HouseID"
            ]
        )
        pv_cohort_match = detected_pv == set(PV_PAPER_ORDER)
        validation.extend(
            [
                validation_row(
                    "8",
                    "PV-house cohort",
                    ",".join(PV_PAPER_ORDER),
                    ",".join(pv_totals["HouseID"]),
                    "pass" if pv_cohort_match else "fail",
                    "House IDs are joined explicitly in paper order; filesystem order is never used.",
                ),
                validation_row(
                    "8",
                    "Paper text says every PV house produces 1800-2000 kWh",
                    "[1800, 2000] kWh",
                    f"[{production.min():.3f}, {production.max():.3f}] kWh",
                    "paper_internal_conflict",
                    "The released data and plotted radar include values outside the textual range.",
                ),
            ]
        )

        week, fig9_metrics = load_figure9(data_dir)
        week.to_csv(stage / "figure9_h4_week_profiles.csv", index=False)
        write_json(stage / "figure9_metrics.json", fig9_metrics)
        render_figure9(week, stage / "figure9_h4_week.png")
        validation.append(
            validation_row(
                "9",
                "One complete ISO week 50 at one-minute resolution",
                10080,
                fig9_metrics["Rows"],
                "pass"
                if fig9_metrics["TimestampSequenceExact"]
                and fig9_metrics["DuplicateTimestamps"] == 0
                and fig9_metrics["MissingMinutes"] == 0
                and fig9_metrics["UnexpectedTimestamps"] == 0
                and fig9_metrics["NonfiniteDerivedPowerRows"] == 0
                else "fail",
                "07 Dec through 13 Dec 2020 inclusive.",
            )
        )

        figure10_requirements = pd.DataFrame(
            [
                ("IEEE European LV stock feeder", "public", "Official IEEE test-feeder ZIP"),
                ("55-customer phase allocation", "public", "A/B/C = 21/19/15"),
                ("LEM tariffs and VUF definition", "public", "Energy Reports methods"),
                ("Modified 350 kVA paper circuit", "missing", "No exact OpenDSS model published"),
                ("20/10 profiles mapped to 55 nodes", "missing", "No mapping/scaling table published"),
                ("Optimisation code and solver tie handling", "missing", "No MATLAB/YALMIP code published"),
                ("55 x 24 voltage phasors or VUF matrix", "missing", "Only raster surface is published"),
            ],
            columns=["Requirement", "Availability", "Evidence"],
        )
        figure10_requirements.to_csv(stage / "figure10_requirements.csv", index=False)
        render_figure10_boundary(stage / "figure10_reproducibility_boundary.png")
        validation.append(
            validation_row(
                "10",
                "Pointwise voltage-unbalance surface",
                "55 customers x 24 hours x 2 scenarios",
                "No public matrix or exact paper-specific model",
                "expected_limitation",
                "Figure is reprinted from Saif et al. (2023) Figure 13; structural inputs are only partially public.",
            )
        )

        required_gates = {
            "figure5_published_percentages": bool(fig5["RoundedMatch"].all()),
            "figure6_all_house_both_scopes": all(
                counts["consumption_passes"] == 19
                and counts["consumption_available"] == 20
                and counts["production_passes"] == 9
                and counts["production_available"] == 10
                and counts["consumption_house_ids"] == sorted(HOUSE_IDS)
                and counts["consumption_failed_house_ids"] == ["H4"]
                and counts["production_available_house_ids"]
                == sorted(PV_PAPER_ORDER)
                and counts["production_failed_house_ids"] == ["H4"]
                and counts["production_unavailable_house_ids"]
                == sorted(set(HOUSE_IDS) - set(PV_PAPER_ORDER))
                for counts in scope_counts.values()
            ),
            "figure6_h4_forensic_blocks": len(fig6.h4_anomaly_segments) == 20
            and extra_present_rows == 314742
            and extra_affected_days == 219,
            "figure6_h4_date_transpose_policies": core_production_passes == 49
            and core_consumption_passes == 49
            and continuous_production_passes == 49
            and continuous_consumption_passes == 29
            and transpose_all_days_sufficient
            and fig6.h4_date_transpose_diagnostics["ComparisonScope"]
            .eq(MAPPED_W_STATUS_SCOPE)
            .all(),
            "figure6_h4_daily_alignment_classification": alignment_days
            == {
                "unaffected_same0": 146,
                "unassessable_no_finite_W_pairs": 1,
                "same_date_plus60_core": 135,
                "actual_transpose_plus60_core": 42,
                "diagonal_identity_plus60_control": 7,
                "unresolved": 35,
            }
            and unresolved_candidates_all_zero
            and clean_alignment_evidence_complete
            and int(same60_consumption["SelectedDaysPassR0p99"]) == 135
            and int(
                same60_consumption["SameDatePlus60Continuous24hDaysPassR0p99"]
            )
            == 131
            and same60_continuous_failure_dates
            == {"2020-05-31", "2020-06-30", "2020-07-31", "2020-08-31"}
            and unassessable_alignment_dates == {"2020-02-29"}
            and marker_alignment_partition_exact,
            "figure6_cross_house_scope_control": len(fig6.h4_cross_house_controls) == 76
            and cross_house_keys_exact
            and cross_house_all_finite
            and cross_house_max_absolute_r < 0.11,
            "figure6_h4_wh_internal_balance": fig6.h4_wh_balance["FiniteRows"] == 526979
            and fig6.h4_wh_balance["RowsAbsoluteResidualAbove1eMinus9Wh"] == 689
            and abs(float(fig6.h4_wh_balance["MaximumAbsoluteResidualWh"]) - 45.68)
            < 1e-12,
            "figure6_normative_sidecars_present": all(
                (stage / name).is_file() for name in FIGURE6_NORMATIVE_SIDECARS
            ),
            "figure7a_published_bars": bool(annual["RoundedMatch"].all()),
            "figure7b_legacy_correlation": round(legacy_r, 2) == -0.31,
            "figure7b_released_grid_complete_days": complete_days == 345,
            "figure8_pv_cohort": pv_cohort_match,
            "figure9_exact_minute_sequence": bool(fig9_metrics["TimestampSequenceExact"])
            and fig9_metrics["DuplicateTimestamps"] == 0
            and fig9_metrics["MissingMinutes"] == 0
            and fig9_metrics["UnexpectedTimestamps"] == 0
            and fig9_metrics["NonfiniteDerivedPowerRows"] == 0,
        }
        required_gates = {
            name: bool(passed) for name, passed in required_gates.items()
        }
        validation_frame = pd.DataFrame(validation)
        validation_frame.to_csv(stage / "validation.csv", index=False)
        failed_gates = [name for name, passed in required_gates.items() if not passed]
        if failed_gates:
            raise RuntimeError(f"Required figure acceptance gates failed: {failed_gates}")
        figure_status = {
            "5": "exact numeric reproduction" if required_gates["figure5_published_percentages"] else "gate failed",
            "6": (
                "general W/Wh consistency supported; H4 public release has diagnosed "
                "time/date assembly evidence, while the published H4 panel remains unreproduced"
                if required_gates["figure6_all_house_both_scopes"]
                and required_gates["figure6_h4_forensic_blocks"]
                and required_gates["figure6_h4_date_transpose_policies"]
                and required_gates["figure6_h4_daily_alignment_classification"]
                and required_gates["figure6_cross_house_scope_control"]
                and required_gates["figure6_h4_wh_internal_balance"]
                and required_gates["figure6_normative_sidecars_present"]
                else "gate failed"
            ),
            "7a": "bar values exact; caption mean conflicts" if required_gates["figure7a_published_bars"] else "gate failed",
            "7b": "legacy trend reproduced; released-grid-complete unit correction supplied"
            if required_gates["figure7b_legacy_correlation"]
            and required_gates["figure7b_released_grid_complete_days"]
            else "gate failed",
            "8": "released-data totals reproduced; textual range conflicts"
            if required_gates["figure8_pv_cohort"]
            else "gate failed",
            "9": "released-data week reproduced"
            if required_gates["figure9_exact_minute_sequence"]
            else "gate failed",
            "10": "structural only; exact inputs unpublished",
        }
        figure6_audit_schema = {
            "schema_version": "2.0.0",
            "comparison_scopes": {
                "finite_release_same_timestamp": (
                    "finite released pairs at identical published timestamps"
                ),
                "observed_both_endpoints": (
                    "finite pairs with released W status(t-1)==status(t)==1; status is an "
                    "observation proxy, not proof of Wh ground truth"
                ),
            },
            "daily_lag_sign": (
                "positive L compares W(t) with 60*Wh(t+L); integer L in [-1440,+1440]"
            ),
            "daily_lag_minimum_finite_points": MIN_DAILY_LAG_FINITE_POINTS,
            "daily_lag_interpretation": (
                "diagnostic_only: lag search characterises release alignment and is not a "
                "repair, imputation rule, or data-acceptance gate"
            ),
            "mapped_comparison_scope": {
                "name": MAPPED_W_STATUS_SCOPE,
                "description": MAPPED_W_STATUS_SCOPE_DESCRIPTION,
            },
            "alignment_boundary_policy": (
                "same-date zero-offset uses 1440 labels; +60 core mappings use 1380 labels; "
                "same-date and transpose continuous-24h diagnostics use 1440 labels and are "
                "exported separately under the same source-and-mapped-target W-status proxy "
                "scope"
            ),
            "alignment_rule": "frozen_rule_based_v2",
            "alignment_candidate_pass_rule": (
                "MatchedFinitePoints>=60 and PearsonR>0.99 for both signals"
            ),
            "date_transpose_pass_rule": (
                "MatchedFinitePoints>=60 and PearsonR>0.99 under the mapped comparison scope"
            ),
            "alignment_category_days": alignment_days,
            "unaffected_alignment_days": int(alignment_days.get("unaffected_same0", 0)),
            "unassessable_no_finite_W_pair_days": int(
                alignment_days.get("unassessable_no_finite_W_pairs", 0)
            ),
            "affected_core_aligned_days": int(
                alignment_days.get("same_date_plus60_core", 0)
                + alignment_days.get("actual_transpose_plus60_core", 0)
                + alignment_days.get("diagonal_identity_plus60_control", 0)
            ),
            "affected_unresolved_days": int(alignment_days.get("unresolved", 0)),
            "affected_core_alignment_caveat": (
                "184 dates pass frozen within-target-day core checks; this is not a claim "
                "that their full 24-hour boundaries are solved or repaired"
            ),
            "forensic_block_definition": (
                "finite Unnamed: 6 rows split when adjacent finite index values differ by "
                "anything other than +1"
            ),
            "forensic_blocks": int(len(fig6.h4_anomaly_segments)),
            "sidecars": FIGURE6_NORMATIVE_SIDECARS,
        }
        summary = {
            "contractId": contract_id,
            "figure_status": figure_status,
            "figure6_audit_schema": figure6_audit_schema,
            "key_metrics": {
                "figure5_rounded_matches": int(fig5["RoundedMatch"].sum()),
                "figure6_h4_finite_release_production_pearson": float(
                    h4_metrics.loc[h4_metrics.Signal == "Production", "PearsonR"].iloc[0]
                ),
                "figure6_h4_finite_release_consumption_pearson": float(
                    h4_metrics.loc[h4_metrics.Signal == "Consumption", "PearsonR"].iloc[0]
                ),
                "figure6_scope_pass_counts": scope_counts,
                "figure6_h4_best_lag_60min_days": {
                    signal: int(
                        fig6.h4_daily_diagnostics.loc[
                            fig6.h4_daily_diagnostics["Signal"].eq(signal),
                            "BestWhTimestampOffsetMinutes",
                        ].eq(60).sum()
                    )
                    for signal in ("Production", "Consumption")
                },
                "figure6_h4_unnamed6_blocks": int(len(fig6.h4_anomaly_segments)),
                "figure6_h4_unnamed6_populated_rows": extra_present_rows,
                "figure6_h4_unnamed6_affected_days": extra_affected_days,
                "figure6_h4_date_transpose_core_passes": {
                    "Production": core_production_passes,
                    "Consumption": core_consumption_passes,
                },
                "figure6_h4_date_transpose_continuous_passes": {
                    "Production": continuous_production_passes,
                    "Consumption": continuous_consumption_passes,
                },
                "figure6_h4_date_transpose_continuous_consumption_aggregate_pearson": (
                    continuous_consumption_aggregate_r
                ),
                "figure6_h4_same_date_plus60_consumption": {
                    "core_days_pass_r0p99": int(
                        same60_consumption["SelectedDaysPassR0p99"]
                    ),
                    "continuous_24h_days_pass_r0p99": int(
                        same60_consumption[
                            "SameDatePlus60Continuous24hDaysPassR0p99"
                        ]
                    ),
                    "continuous_24h_failure_dates": sorted(
                        same60_continuous_failure_dates
                    ),
                },
                "figure6_h4_alignment_category_days": alignment_days,
                "figure6_h4_unresolved_all_candidate_pass_counts_zero": (
                    unresolved_candidates_all_zero
                ),
                "figure6_cross_house_max_absolute_pearson": cross_house_max_absolute_r,
                "figure6_cross_house_max_absolute_pearson_by_scope": (
                    cross_house_max_by_scope
                ),
                "figure6_h4_wh_balance": fig6.h4_wh_balance,
                "figure7a_recomputed_mean_kwh": reproduced_mean,
                "figure7a_calendar_2020_mean_kwh": calendar_2020_mean,
                "figure7a_paper_caption_mean_kwh": caption_mean,
                "figure7b_legacy_pearson": legacy_r,
                "figure7b_released_grid_complete_days": complete_days,
                "figure7b_released_grid_complete_pearson": corrected_r,
                "figure9_rows": int(fig9_metrics["Rows"]),
                "figure9_max_balance_residual_wh": float(fig9_metrics["MaximumAbsoluteBalanceResidualWh"]),
            },
            "required_gates": required_gates,
            "claims": claims,
        }
        write_json(stage / "summary.json", summary)
        (stage / "README.md").write_text(make_readme(summary), encoding="utf-8")

        artifact_hashes = {
            path.name: sha256_file(path)
            for path in sorted(stage.iterdir())
            if path.is_file()
        }
        manifest = {
            "run_id": output_dir.name,
            "pipeline": "Scientific Data Figures 5-10 reproduction and audit",
            "provenance": provenance,
            "verified_release_files": release_checks,
            "verified_figshare_inventory_files": figshare_checks,
            "artifact_sha256": artifact_hashes,
            "figure_status": figure_status,
            "required_gates": required_gates,
            "figure6_audit_schema": figure6_audit_schema,
        }
        write_json(stage / "manifest.json", manifest)
        checksum_lines = [
            f"{sha256_file(path)}  {path.name}"
            for path in sorted(stage.iterdir())
            if path.is_file()
        ]
        (stage / "RESULT_MANIFEST.sha256").write_text("\n".join(checksum_lines) + "\n", encoding="utf-8")

        publish_directory_no_replace(stage, output_dir)
    return summary


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    summary = generate(DEFAULT_DATA_DIR, DEFAULT_REFERENCE_DIR, args.output_dir.resolve())
    print(json.dumps(summary["figure_status"], ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
