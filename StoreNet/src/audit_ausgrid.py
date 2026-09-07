#!/usr/bin/env python3
"""Independently audit and select days from the Ausgrid 2012-2013 file.

This checker intentionally uses only the Python standard library.  It is not
called by the MATLAB optimization pipeline; its output is compared with that
pipeline as an implementation-independent data-contract check.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import statistics
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any


INTERVAL_COUNT = 48
REQUIRED_CATEGORIES = ("GC", "GG")
OPTIONAL_CATEGORIES = ("CL",)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def median_absolute_deviation(values: list[float], center: float) -> float:
    return statistics.median(abs(value - center) for value in values)


def date_range(first: date, last: date) -> list[date]:
    return [first + timedelta(days=offset) for offset in range((last - first).days + 1)]


def load_rows(source: Path, customer_ids: set[int]) -> tuple[int, dict[Any, list[dict[str, Any]]], date, date]:
    selected: dict[Any, list[dict[str, Any]]] = defaultdict(list)
    row_count = 0
    first_day: date | None = None
    last_day: date | None = None

    with source.open("r", encoding="utf-8-sig", newline="") as stream:
        next(stream)
        reader = csv.DictReader(stream)
        interval_names = list(reader.fieldnames or [])[5:53]
        if len(interval_names) != INTERVAL_COUNT:
            raise ValueError(f"Expected 48 interval fields, found {len(interval_names)}")

        for row in reader:
            row_count += 1
            day = datetime.strptime(row["date"], "%d/%m/%Y").date()
            first_day = day if first_day is None else min(first_day, day)
            last_day = day if last_day is None else max(last_day, day)
            customer = int(row["Customer"])
            if customer not in customer_ids:
                continue
            values: list[float] = []
            parse_error = False
            for field in interval_names:
                try:
                    values.append(float(row[field]))
                except (TypeError, ValueError):
                    parse_error = True
                    values.append(math.nan)
            selected[(day, customer)].append(
                {
                    "category": row["Consumption Category"].strip(),
                    "quality": (row.get("Row Quality") or "").strip(),
                    "values": values,
                    "parse_error": parse_error,
                }
            )

    if first_day is None or last_day is None:
        raise ValueError("Source contains no data rows")
    return row_count, selected, first_day, last_day


def build_day_profiles(
    rows: dict[Any, list[dict[str, Any]]],
    days: list[date],
    customer_ids: list[int],
) -> tuple[dict[date, list[float]], dict[date, list[str]]]:
    profiles: dict[date, list[float]] = {}
    rejected: dict[date, list[str]] = {}

    for day in days:
        aggregate_load = [0.0] * INTERVAL_COUNT
        aggregate_pv = [0.0] * INTERVAL_COUNT
        reasons: set[str] = set()
        for customer in customer_ids:
            category_rows: dict[str, list[dict[str, Any]]] = defaultdict(list)
            for row in rows.get((day, customer), []):
                category_rows[row["category"]].append(row)

            for category in REQUIRED_CATEGORIES:
                if len(category_rows[category]) != 1:
                    reasons.add(f"{category.lower()}_count")
            for category in OPTIONAL_CATEGORIES:
                if len(category_rows[category]) > 1:
                    reasons.add(f"{category.lower()}_count")

            relevant = [
                row
                for category in REQUIRED_CATEGORIES + OPTIONAL_CATEGORIES
                for row in category_rows[category]
            ]
            if any(row["quality"] for row in relevant):
                reasons.add("row_quality")
            if any(row["parse_error"] for row in relevant):
                reasons.add("non_numeric")
            if any(
                not math.isfinite(value)
                for row in relevant
                for value in row["values"]
            ):
                reasons.add("non_finite")
            if any(value < 0 for row in relevant for value in row["values"]):
                reasons.add("negative")

            if reasons:
                continue
            gc = category_rows["GC"][0]["values"]
            gg = category_rows["GG"][0]["values"]
            cl = category_rows["CL"][0]["values"] if category_rows["CL"] else [0.0] * INTERVAL_COUNT
            aggregate_load = [value + gc[index] + cl[index] for index, value in enumerate(aggregate_load)]
            aggregate_pv = [value + gg[index] for index, value in enumerate(aggregate_pv)]

        if reasons:
            rejected[day] = sorted(reasons)
        else:
            profiles[day] = aggregate_load + aggregate_pv

    return profiles, rejected


def select_monthly_days(profiles: dict[date, list[float]]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    selection: list[dict[str, Any]] = []
    ranking: list[dict[str, Any]] = []
    by_month: dict[int, list[date]] = defaultdict(list)
    for day in profiles:
        by_month[day.month].append(day)

    for month in range(1, 13):
        candidates = sorted(by_month[month])
        if not candidates:
            raise ValueError(f"No valid candidate days for month {month}")
        columns = list(zip(*(profiles[day] for day in candidates)))
        centers = [statistics.median(column) for column in columns]
        scales = [median_absolute_deviation(list(column), center) for column, center in zip(columns, centers)]
        scales = [scale if scale != 0 else 1.0 for scale in scales]

        scores: list[tuple[float, date]] = []
        for day in candidates:
            squared = [
                ((value - center) / scale) ** 2
                for value, center, scale in zip(profiles[day], centers, scales)
            ]
            scores.append((math.sqrt(sum(squared) / len(squared)), day))
        scores.sort(key=lambda item: (item[0], item[1]))
        selected_score, selected_day = scores[0]
        selection.append(
            {
                "month": month,
                "day": selected_day.isoformat(),
                "score": selected_score,
                "candidateCount": len(candidates),
            }
        )
        for score, day in scores:
            ranking.append(
                {
                    "month": month,
                    "day": day.isoformat(),
                    "score": score,
                    "selected": day == selected_day,
                }
            )
    return selection, ranking


def audit(spec_path: Path, source_path: Path) -> dict[str, Any]:
    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    customer_ids = [int(value) for value in spec["analysisCustomerIds"]]
    interval_hours = float(spec["sourceIntervalMinutes"]) / 60.0
    if not math.isfinite(interval_hours) or interval_hours <= 0:
        raise ValueError("sourceIntervalMinutes must define a positive interval")
    actual_hash = sha256(source_path)
    if actual_hash != spec["sourceFileSha256"]:
        raise ValueError(
            f"SHA-256 mismatch: expected {spec['sourceFileSha256']}, got {actual_hash}"
        )

    row_count, rows, first_day, last_day = load_rows(source_path, set(customer_ids))
    days = date_range(first_day, last_day)
    profiles, rejected = build_day_profiles(rows, days, customer_ids)
    power_profiles = {
        day: [energy / interval_hours for energy in profile]
        for day, profile in profiles.items()
    }
    selection, ranking = select_monthly_days(power_profiles)
    reason_counts = Counter(reason for reasons in rejected.values() for reason in reasons)

    return {
        "schemaVersion": "StoreNet-independent-Ausgrid-audit-v1",
        "specPath": str(spec_path.resolve()),
        "sourcePath": str(source_path.resolve()),
        "sourceFileSha256": actual_hash,
        "selectionFeatureUnit": "kW",
        "sourceIntervalHours": interval_hours,
        "sourceRowCount": row_count,
        "houseCount": len(customer_ids),
        "calendarDayCount": len(days),
        "validDayCount": len(profiles),
        "rejectedDayCount": len(rejected),
        "rejectedDays": [day.isoformat() for day in sorted(rejected)],
        "rejectionReasonCounts": dict(sorted(reason_counts.items())),
        "selection": selection,
        "rankingRowCount": len(ranking),
    }


def parse_args() -> argparse.Namespace:
    project_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--spec",
        type=Path,
        default=project_root / "config" / "crossenv" / "ausgrid_2012_2013.json",
    )
    parser.add_argument(
        "--source",
        type=Path,
        default=project_root
        / "data"
        / "external"
        / "ausgrid"
        / "raw"
        / "extracted"
        / "Solar home 2012-2013.csv",
    )
    parser.add_argument("--output", type=Path)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    report = audit(args.spec, args.source)
    encoded = json.dumps(report, indent=2, sort_keys=True)
    if args.output:
        args.output.write_text(encoded + "\n", encoding="utf-8")
    else:
        print(encoded)


if __name__ == "__main__":
    main()
