"""Golden-data tests for the Scientific Data Figure 5-10 audit."""

from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from unittest import mock
from pathlib import Path

import numpy as np
import pandas as pd


PROJECT = Path(__file__).resolve().parents[1]
REPOSITORY = PROJECT.parent
sys.path.insert(0, str(PROJECT / "src"))

import reproduce_data_paper_figures as figures  # noqa: E402


class TestDataPaperFigureReproduction(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.data_dir = PROJECT / "data" / "raw"
        cls.reference_dir = PROJECT / "reference"
        cls.energy = figures.load_energy_summary(cls.data_dir)
        cls.weather = figures.load_weather_daily(cls.data_dir)
        cls._figure6_audit = None

    @classmethod
    def figure6_audit(cls) -> figures.Figure6Audit:
        if cls._figure6_audit is None:
            cls._figure6_audit = figures.load_figure6_audit(cls.data_dir)
        return cls._figure6_audit

    def test_official_release_manifest_has_46_matching_files(self) -> None:
        checks = figures.verify_release_manifest(
            PROJECT / "data" / "RELEASE_MANIFEST.sha256", REPOSITORY
        )
        self.assertEqual(len(checks), 46)
        self.assertEqual(len({item["path"] for item in checks}), 46)
        self.assertTrue(all(item["passed"] for item in checks))
        figshare = figures.verify_figshare_inventory(
            self.reference_dir / "figshare_v1_inventory.csv", self.data_dir
        )
        self.assertEqual(len(figshare), 46)
        self.assertTrue(all(item["passed"] for item in figshare))

    def test_release_manifest_rejects_duplicates_and_unsafe_paths(self) -> None:
        manifest = PROJECT / "data" / "RELEASE_MANIFEST.sha256"
        first = next(
            line
            for line in manifest.read_text(encoding="utf-8").splitlines()
            if line and not line.startswith("#")
        )
        with tempfile.TemporaryDirectory() as temporary:
            duplicate = Path(temporary) / "duplicate.sha256"
            duplicate.write_text("\n".join([first] * 46) + "\n", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "duplicate path"):
                figures.verify_release_manifest(duplicate, REPOSITORY)
            unsafe = Path(temporary) / "unsafe.sha256"
            digest = first.split(maxsplit=1)[0]
            unsafe.write_text(f"{digest}  ../outside.csv\n", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "unsafe path"):
                figures.verify_release_manifest(unsafe, REPOSITORY)

    def test_contract_id_text_matches_pipeline_and_fails_closed(self) -> None:
        self.assertEqual(figures.parse_contract_id(figures.CONTRACT_PATH), figures.CONTRACT_ID)
        self.assertEqual(figures.require_contract_matches_pipeline(), figures.CONTRACT_ID)
        with tempfile.TemporaryDirectory() as temporary:
            mismatch = Path(temporary) / "contract.md"
            mismatch.write_text("契約 ID：`SR2020-IR-wrong`\n", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "does not match"):
                figures.require_contract_matches_pipeline(mismatch)
            ambiguous = Path(temporary) / "ambiguous.md"
            ambiguous.write_text(
                "契約 ID：`SR2020-IR-v2`\n契約 ID：`SR2020-IR-v2`\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(RuntimeError, "exactly one"):
                figures.parse_contract_id(ambiguous)

    def test_formal_default_publish_requires_clean_tree_only(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            with mock.patch.object(figures, "git_capture", return_value=" M dirty.txt"):
                figures.require_clean_tree_for_formal_publish(Path(temporary) / "test-output")
                with self.assertRaisesRegex(RuntimeError, "clean Git tree"):
                    figures.require_clean_tree_for_formal_publish(figures.DEFAULT_OUTPUT_DIR)
            with mock.patch.object(figures, "git_capture", return_value=""):
                figures.require_clean_tree_for_formal_publish(figures.DEFAULT_OUTPUT_DIR)
            with mock.patch.object(figures, "git_capture", return_value="unavailable"):
                with self.assertRaisesRegex(RuntimeError, "Cannot verify"):
                    figures.require_clean_tree_for_formal_publish(figures.DEFAULT_OUTPUT_DIR)

    def test_figure5_all_published_percentages_match_rounding(self) -> None:
        summary, matrix = figures.load_figure5(self.data_dir, self.reference_dir)
        self.assertEqual(matrix.shape, (20, 527040))
        self.assertTrue(summary["RoundedMatch"].all())
        h10 = summary.set_index("HouseID").loc["H10"]
        self.assertEqual(int(h10["AvailableRows"]), 524723)
        self.assertEqual(int(h10["MissingRowsOnPlotGrid"]), 2317)
        self.assertAlmostEqual(float(h10["ReproducedAvailablePercent"]), 99.56037, places=5)

    def test_figure6_public_h4_pair_does_not_support_paper_r_equals_one(self) -> None:
        _, metrics = figures.load_figure6(self.data_dir)
        indexed = metrics.set_index("Signal")
        self.assertAlmostEqual(float(indexed.loc["Production", "PearsonR"]), 0.7321716905, places=8)
        self.assertAlmostEqual(float(indexed.loc["Consumption", "PearsonR"]), 0.5219457715, places=8)
        self.assertFalse(bool(indexed["PaperClaimReproduced"].any()))

    def test_figure6_all_house_dual_scope_and_equality_metrics(self) -> None:
        metrics = self.figure6_audit().all_house_metrics
        self.assertEqual(len(metrics), 80)
        self.assertEqual(
            set(metrics["ComparisonScope"]),
            {"finite_release_same_timestamp", "observed_both_endpoints"},
        )
        self.assertEqual(
            metrics.groupby(["ComparisonScope", "Signal"]).size().to_dict(),
            {
                ("finite_release_same_timestamp", "Consumption"): 20,
                ("finite_release_same_timestamp", "Production"): 20,
                ("observed_both_endpoints", "Consumption"): 20,
                ("observed_both_endpoints", "Production"): 20,
            },
        )
        for scope, selected in metrics.groupby("ComparisonScope"):
            consumption = selected.loc[selected["Signal"].eq("Consumption")]
            production = selected.loc[
                selected["Signal"].eq("Production") & selected["SignalAvailable"]
            ]
            unavailable_production = selected.loc[
                selected["Signal"].eq("Production") & ~selected["SignalAvailable"]
            ]
            self.assertEqual(set(consumption["HouseID"]), set(figures.HOUSE_IDS), scope)
            self.assertEqual(int(consumption["ConsistencyPass"].eq(True).sum()), 19, scope)
            self.assertEqual(
                set(
                    consumption.loc[
                        ~consumption["ConsistencyPass"].eq(True), "HouseID"
                    ]
                ),
                {"H4"},
                scope,
            )
            self.assertEqual(len(production), 10, scope)
            self.assertEqual(set(production["HouseID"]), set(figures.PV_PAPER_ORDER), scope)
            self.assertEqual(int(production["ConsistencyPass"].eq(True).sum()), 9, scope)
            self.assertEqual(
                set(
                    production.loc[
                        ~production["ConsistencyPass"].eq(True), "HouseID"
                    ]
                ),
                {"H4"},
                scope,
            )
            self.assertEqual(
                set(unavailable_production["HouseID"]),
                set(figures.HOUSE_IDS) - set(figures.PV_PAPER_ORDER),
                scope,
            )

        observed = metrics.loc[metrics["ComparisonScope"].eq("observed_both_endpoints")]
        h4 = observed.set_index(["HouseID", "Signal"])
        self.assertEqual(int(h4.loc[("H4", "Production"), "MatchedFinitePoints"]), 523946)
        self.assertEqual(int(h4.loc[("H4", "Consumption"), "MatchedFinitePoints"]), 523946)
        self.assertAlmostEqual(
            float(h4.loc[("H4", "Production"), "PearsonR"]), 0.732165067152, places=11
        )
        self.assertAlmostEqual(
            float(h4.loc[("H4", "Consumption"), "PearsonR"]), 0.521932340331, places=11
        )
        active_non_h4 = observed.loc[
            observed["SignalAvailable"] & ~observed["HouseID"].eq("H4")
        ]
        self.assertGreaterEqual(
            float(active_non_h4["PearsonR"].min()), 0.999999877648 - 1e-12
        )
        self.assertLessEqual(
            float(active_non_h4["P99AbsoluteError_W"].max()), 0.2000000000003
        )
        self.assertGreaterEqual(
            float(active_non_h4["FractionWithin0p5W"].min()), 0.999996176259
        )
        for column in (
            "RMSE_W",
            "MAE_W",
            "P99AbsoluteError_W",
            "EquivalentOnMeasuredSlope",
            "EquivalentOnMeasuredIntercept_W",
            "RoundingAgreementFraction",
        ):
            self.assertIn(column, metrics.columns)

    def test_figure6_h4_daily_monthly_lag_and_alignment_goldens(self) -> None:
        audit = self.figure6_audit()
        daily = audit.h4_daily_diagnostics
        self.assertEqual(len(daily), 732)
        self.assertTrue(daily["LagSearchMinimumMinutes"].eq(-1440).all())
        self.assertTrue(daily["LagSearchMaximumMinutes"].eq(1440).all())
        lag60 = daily.groupby("Signal")["BestWhTimestampOffsetMinutes"].apply(
            lambda values: int(values.eq(60).sum())
        )
        self.assertEqual(int(lag60["Production"]), 141)
        self.assertEqual(int(lag60["Consumption"]), 142)
        self.assertEqual(
            int(daily["BestLagPearsonR"].notna().sum()),
            int(daily["BestWhTimestampOffsetMinutes"].notna().sum()),
        )
        self.assertTrue(
            daily.loc[
                daily["BestLagPearsonR"].isna(), "BestWhTimestampOffsetMinutes"
            ].isna().all()
        )

        monthly = audit.h4_monthly_summary.set_index(["Month", "Signal"])
        expected_consumption_medians = {
            "2020-01": 0.995117,
            "2020-02": 0.105560,
            "2020-03": 0.145798,
            "2020-04": 0.121261,
            "2020-05": 0.078722,
            "2020-06": 0.104736,
            "2020-07": 0.142437,
            "2020-08": 0.110671,
            "2020-09": 0.999897,
            "2020-10": 0.999822,
            "2020-11": 0.999915,
            "2020-12": 0.999924,
        }
        for month, expected in expected_consumption_medians.items():
            self.assertAlmostEqual(
                float(monthly.loc[(month, "Consumption"), "MedianDailySameTimestampPearsonR"]),
                expected,
                places=6,
            )

        alignment = audit.h4_alignment_summary.set_index(["AlignmentCategory", "Signal"])
        expected_days = {
            "unaffected_same0": 146,
            "unassessable_no_finite_W_pairs": 1,
            "same_date_plus60_core": 135,
            "actual_transpose_plus60_core": 42,
            "diagonal_identity_plus60_control": 7,
            "unresolved": 35,
        }
        for category, days in expected_days.items():
            self.assertEqual(
                int(alignment.loc[(category, "Consumption"), "CalendarDays"]), days
            )
        goldens = {
            ("unaffected_same0", "Production"): (209457, 0.999999936730),
            ("unaffected_same0", "Consumption"): (209457, 0.999999992460),
            ("same_date_plus60_core", "Production"): (185206, 0.999999969728953),
            ("same_date_plus60_core", "Consumption"): (185206, 0.999999989933569),
        }
        for key, (points, pearson) in goldens.items():
            self.assertEqual(int(alignment.loc[key, "SelectedMatchedFinitePoints"]), points)
            self.assertAlmostEqual(
                float(alignment.loc[key, "SelectedAggregatePearsonR"]), pearson, places=11
            )
        unresolved = alignment.loc["unresolved"]
        self.assertTrue(
            unresolved[
                [
                    "SameDate0DaysPassR0p99",
                    "SameDatePlus60CoreDaysPassR0p99",
                    "TransposePlus60CoreDaysPassR0p99",
                ]
            ].eq(0).all().all()
        )
        clean_categories = {
            "unaffected_same0",
            "same_date_plus60_core",
            "actual_transpose_plus60_core",
            "diagonal_identity_plus60_control",
        }
        clean = audit.h4_alignment_summary.loc[
            audit.h4_alignment_summary["AlignmentCategory"].isin(clean_categories)
        ]
        self.assertTrue(clean["MappedComparisonScope"].eq(figures.MAPPED_W_STATUS_SCOPE).all())
        self.assertTrue(clean["SelectedMatchedFinitePoints"].gt(0).all())
        self.assertTrue(np.isfinite(clean["SelectedAggregatePearsonR"]).all())
        self.assertTrue(clean["SelectedDaysPassR0p99"].eq(clean["CalendarDays"]).all())
        unassessable = alignment.loc["unassessable_no_finite_W_pairs"]
        self.assertTrue(unassessable["SelectedMatchedFinitePoints"].eq(0).all())
        self.assertTrue(unassessable["SelectedAggregatePearsonR"].isna().all())
        self.assertEqual(
            sum(expected_days[name] for name in clean_categories if name != "unaffected_same0"),
            184,
        )
        same60_consumption = alignment.loc[("same_date_plus60_core", "Consumption")]
        self.assertEqual(int(same60_consumption["SelectedDaysPassR0p99"]), 135)
        self.assertEqual(
            int(
                same60_consumption[
                    "SameDatePlus60Continuous24hMatchedFinitePoints"
                ]
            ),
            193240,
        )
        self.assertEqual(
            int(same60_consumption["SameDatePlus60Continuous24hDaysPassR0p99"]),
            131,
        )
        self.assertEqual(
            set(same60_consumption["SameDatePlus60Continuous24hFailureDates"].split(";")),
            {"2020-05-31", "2020-06-30", "2020-07-31", "2020-08-31"},
        )
        daily_once = daily.loc[daily["Signal"].eq("Consumption")]
        self.assertEqual(
            set(
                daily_once.loc[
                    daily_once["AlignmentCategory"].eq(
                        "unassessable_no_finite_W_pairs"
                    ),
                    "Date",
                ]
            ),
            {"2020-02-29"},
        )
        affected = set(
            daily_once.loc[daily_once["AlignmentAffectedByUnnamed6"], "Date"]
        )
        core_aligned = set(
            daily_once.loc[
                daily_once["AlignmentCategory"].isin(
                    {
                        "same_date_plus60_core",
                        "actual_transpose_plus60_core",
                        "diagonal_identity_plus60_control",
                    }
                ),
                "Date",
            ]
        )
        unresolved_dates = set(
            daily_once.loc[
                daily_once["AlignmentCategory"].eq("unresolved"), "Date"
            ]
        )
        self.assertEqual(len(affected), 219)
        self.assertEqual(len(core_aligned), 184)
        self.assertEqual(len(unresolved_dates), 35)
        self.assertEqual(affected, core_aligned | unresolved_dates)
        for prefix in (
            "CandidateSameDate0",
            "CandidateSameDatePlus60Core",
            "CandidateSameDatePlus60Continuous24h",
            "CandidateTransposePlus60Core",
            "CandidateTransposePlus60Continuous24h",
        ):
            passing = daily.loc[daily[f"{prefix}PassR0p99"]]
            self.assertTrue(
                passing[f"{prefix}MatchedFinitePoints"]
                .ge(figures.MIN_DAILY_LAG_FINITE_POINTS)
                .all(),
                prefix,
            )

    def test_figure6_h4_forensic_blocks_transpose_cross_house_and_balance(self) -> None:
        audit = self.figure6_audit()
        blocks = audit.h4_anomaly_segments
        self.assertEqual(len(blocks), 20)
        self.assertEqual(int(blocks["PopulatedRows"].sum()), 314742)
        self.assertEqual(int(blocks["AffectedDays"].sum()), 219)
        self.assertTrue(blocks["IndexValuesSequentialWithinBlock"].all())
        self.assertEqual(str(blocks.iloc[0]["StartTimestamp"]), "2020-01-02 00:00:00")
        self.assertEqual(str(blocks.iloc[-1]["EndTimestampInclusive"]), "2020-12-08 23:59:00")

        transpose = audit.h4_date_transpose_diagnostics
        self.assertEqual(len(transpose), 196)
        self.assertTrue(
            transpose["ComparisonScope"]
            .eq(figures.MAPPED_W_STATUS_SCOPE)
            .all()
        )
        self.assertTrue(
            transpose["ComparisonScopeDescription"]
            .str.contains("source W timestamps and mapped-target Wh timestamps", regex=False)
            .all()
        )
        self.assertTrue(
            transpose["PassMinimumFinitePoints"]
            .eq(figures.MIN_DAILY_LAG_FINITE_POINTS)
            .all()
        )
        self.assertTrue(
            transpose["MatchedFinitePoints"]
            .ge(figures.MIN_DAILY_LAG_FINITE_POINTS)
            .all()
        )
        for policy in ("within_target_day_core", "continuous_24h"):
            policy_rows = transpose.loc[transpose["WindowPolicy"].eq(policy)]
            self.assertEqual(
                policy_rows.groupby("DateMappingType")["WDate"].nunique().to_dict(),
                {"actual_month_day_transpose": 42, "diagonal_identity_control": 7},
            )
        grouped = transpose.groupby(["WindowPolicy", "Signal"])
        self.assertEqual(
            grouped["PassR0p99"].sum().astype(int).to_dict(),
            {
                ("continuous_24h", "Consumption"): 29,
                ("continuous_24h", "Production"): 49,
                ("within_target_day_core", "Consumption"): 49,
                ("within_target_day_core", "Production"): 49,
            },
        )
        core = transpose.loc[transpose["WindowPolicy"].eq("within_target_day_core")]
        self.assertLessEqual(int(core["MatchedFinitePoints"].max()), 1380)
        core_aggregate = core.groupby("Signal")["PolicySignalAggregatePearsonR"].first()
        core_points = core.groupby("Signal")[
            "PolicySignalAggregateMatchedFinitePoints"
        ].first()
        self.assertEqual(core_points.astype(int).to_dict(), {"Consumption": 67360, "Production": 67360})
        # Reduction order differs across BLAS/platforms by about 1e-13.
        # Keep an absolute 1e-12 tolerance, far below the 0.99 decision threshold.
        self.assertAlmostEqual(
            float(core_aggregate["Production"]), 0.999999972619431, delta=1e-12
        )
        self.assertAlmostEqual(
            float(core_aggregate["Consumption"]), 0.999999991013640, delta=1e-12
        )
        continuous_consumption = transpose.loc[
            transpose["WindowPolicy"].eq("continuous_24h")
            & transpose["Signal"].eq("Consumption"),
            "PolicySignalAggregatePearsonR",
        ].iloc[0]
        continuous_points = transpose.loc[
            transpose["WindowPolicy"].eq("continuous_24h")
        ].groupby("Signal")["PolicySignalAggregateMatchedFinitePoints"].first()
        self.assertEqual(
            continuous_points.astype(int).to_dict(),
            {"Consumption": 70300, "Production": 70300},
        )
        self.assertGreater(float(continuous_consumption), 0.989)
        self.assertLess(float(continuous_consumption), 0.990)

        controls = audit.h4_cross_house_controls
        self.assertEqual(len(controls), 76)
        expected_keys = {
            (house, direction, scope)
            for house in figures.HOUSE_IDS
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
        self.assertEqual(
            set(
                controls[
                    ["OtherHouseID", "Direction", "ComparisonScope"]
                ].itertuples(index=False, name=None)
            ),
            expected_keys,
        )
        self.assertTrue(np.isfinite(controls["PearsonR"]).all())
        maxima = controls.groupby("ComparisonScope")["PearsonR"].apply(
            lambda values: float(values.abs().max())
        )
        self.assertAlmostEqual(
            maxima["finite_release_same_timestamp"], 0.105878623925, places=11
        )
        self.assertAlmostEqual(maxima["observed_both_endpoints"], 0.107059710501, places=11)
        self.assertTrue(controls["AbsolutePearsonRBelow0p11"].all())
        self.assertTrue(controls["ScopeStartInclusive"].eq("2020-02-01 00:00:00").all())
        self.assertTrue(controls["ScopeEndExclusive"].eq("2020-09-01 00:00:00").all())

        balance = audit.h4_wh_balance
        self.assertEqual(balance["FiniteRows"], 526979)
        self.assertAlmostEqual(balance["MeanResidualWh"], 0.000930587366859, places=15)
        self.assertAlmostEqual(balance["MeanAbsoluteResidualWh"], 0.000930587366860, places=15)
        self.assertAlmostEqual(balance["MaximumAbsoluteResidualWh"], 45.68, places=12)
        self.assertEqual(balance["RowsAbsoluteResidualAbove1eMinus9Wh"], 689)
        self.assertEqual(
            balance["Classification"],
            "internal_consistency_support_only_not_root_cause_proof",
        )

    def test_figure6_fft_lag_search_matches_finite_pair_brute_force(self) -> None:
        day = pd.Timestamp("2020-01-02")
        grid = pd.date_range(day, periods=1440, freq="min")
        values = np.sin(np.arange(1440) * 0.071) + np.cos(np.arange(1440) * 0.013)
        values[::13] = np.nan
        power = pd.Series(values, index=grid)
        equivalent = pd.Series(values, index=grid + pd.Timedelta(minutes=2))
        equivalent.iloc[::11] = np.nan
        observed = figures._best_daily_lag_metrics(
            power, equivalent, day, maximum_lag_minutes=5
        )
        brute: list[tuple[int, float]] = []
        for lag in range(-5, 6):
            candidate = equivalent.reindex(
                grid + pd.Timedelta(minutes=lag)
            ).to_numpy(dtype=float)
            metrics = figures._pair_metrics(values, candidate)
            brute.append((lag, float(metrics["PearsonR"])))
        finite = [(lag, value) for lag, value in brute if np.isfinite(value)]
        expected_value = max(value for _, value in finite)
        expected_lags = [lag for lag, value in finite if abs(value - expected_value) <= 1e-12]
        expected_lag = sorted(expected_lags, key=lambda lag: (abs(lag), lag))[0]
        self.assertEqual(observed["BestWhTimestampOffsetMinutes"], expected_lag)
        self.assertEqual(expected_lag, 2)
        self.assertAlmostEqual(observed["BestLagPearsonR"], expected_value, places=12)

    def test_figure6_lag_search_returns_na_for_sparse_or_constant_days(self) -> None:
        day = pd.Timestamp("2020-01-02")
        grid = pd.date_range(day, periods=1440, freq="min")
        constant = pd.Series(np.ones(1440), index=grid)
        constant_result = figures._best_daily_lag_metrics(
            constant, constant, day, maximum_lag_minutes=5
        )
        self.assertEqual(
            constant_result["BestLagDiagnosticStatus"],
            "no_eligible_finite_variance_candidate",
        )

        sparse_values = np.full(1440, np.nan)
        sparse_values[:10] = np.arange(10, dtype=float)
        sparse = pd.Series(sparse_values, index=grid)
        sparse_result = figures._best_daily_lag_metrics(
            sparse,
            pd.Series(sparse_values, index=grid + pd.Timedelta(minutes=2)),
            day,
            maximum_lag_minutes=5,
        )
        self.assertEqual(sparse_result["BestLagDiagnosticStatus"], "too_sparse_power_day")
        for result in (constant_result, sparse_result):
            for field in (
                "BestWhTimestampOffsetMinutes",
                "BestLagAtSearchBoundary",
                "BestLagMatchedFinitePoints",
                "BestLagPearsonR",
                "BestLagRMSE_W",
                "BestLagMAE_W",
                "BestLagP99AbsoluteError_W",
                "BestLagPassR0p99",
            ):
                self.assertTrue(pd.isna(result[field]), (field, result[field]))

    def test_figure6_mapped_pair_requires_target_w_status_proxy(self) -> None:
        source_day = pd.Timestamp("2020-01-01")
        target_day = pd.Timestamp("2020-01-02")
        source_grid = pd.date_range(source_day, periods=3, freq="min")
        target_grid = pd.date_range(target_day, periods=3, freq="min")
        power = pd.DataFrame(
            {
                "Production(W)": [10.0, 20.0, 30.0, np.nan, np.nan],
                "ObservedBothEndpoints": [True, True, True, True, True],
            },
            index=source_grid.append(target_grid[[0, 2]]),
        )
        energy = pd.DataFrame(
            {"Production(Wh)": np.array([10.0, 20.0, 30.0]) / 60.0},
            index=target_grid,
        )
        measured, equivalent, metrics = figures._mapped_observed_pair(
            power, energy, source_grid, target_grid, "Production"
        )
        np.testing.assert_array_equal(measured, np.array([10.0, 30.0]))
        np.testing.assert_allclose(equivalent, np.array([10.0, 30.0]))
        self.assertEqual(int(metrics["MatchedFinitePoints"]), 2)

    def test_figure6_forensic_schema_fails_closed_without_extra_index(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "H4_W.csv"
            pd.DataFrame(
                {
                    "date": ["2020-01-01 00:00:00", "2020-01-01 00:01:00"],
                    "Production(W)": [0.0, 1.0],
                    "Consumption(W)": [1.0, 2.0],
                }
            ).to_csv(path, index=False)
            with self.assertRaisesRegex(RuntimeError, "Unnamed: 6"):
                figures._read_figure6_stream(
                    path,
                    ["date", "Production(W)", "Consumption(W)"],
                    require_extra_index=True,
                )

    def test_figure7a_bars_match_but_caption_mean_does_not(self) -> None:
        paper = pd.read_csv(self.reference_dir / "data_paper_fig7_annual_consumption.csv")
        actual = self.energy.totals_kwh[
            ["HouseID", "PaperLegacyConsumptionKWh", "Calendar2020ConsumptionKWh"]
        ].merge(paper, on="HouseID")
        self.assertTrue(
            actual["PaperLegacyConsumptionKWh"]
            .round(1)
            .eq(actual["PaperAnnualConsumptionKWh"].round(1))
            .all()
        )
        mean = float(actual["PaperLegacyConsumptionKWh"].mean())
        self.assertAlmostEqual(mean, 5003.1125275, places=7)
        self.assertNotAlmostEqual(mean, 5025.64, places=2)
        h10 = actual.set_index("HouseID").loc["H10"]
        self.assertGreater(
            float(h10["PaperLegacyConsumptionKWh"]),
            float(h10["Calendar2020ConsumptionKWh"]),
        )
        h14 = self.energy.totals_kwh.set_index("HouseID").loc["H14"]
        self.assertEqual(h14["ReleaseEndTimestamp"], "2020-12-11 23:59:00")
        self.assertFalse(bool(h14["ReleaseIntervalComplete"]))

    def test_figure7b_legacy_and_corrected_quantities_are_separate(self) -> None:
        legacy = figures.merge_daily_with_weather(self.energy.legacy_daily, self.weather)
        corrected = figures.merge_daily_with_weather(self.energy.corrected_daily, self.weather)
        legacy_r = float(legacy[["LegacyMeanWhPerMinute", "AmbientTemperatureC"]].corr().iloc[0, 1])
        corrected_r = float(
            corrected[["ReleasedGridCompleteConsumptionKWh", "AmbientTemperatureC"]]
            .corr()
            .iloc[0, 1]
        )
        self.assertEqual(len(legacy), 366)
        self.assertEqual(round(legacy_r, 2), -0.31)
        self.assertAlmostEqual(legacy_r, -0.3141307092, places=8)
        self.assertEqual(int(corrected["ReleasedGridComplete"].sum()), 345)
        self.assertAlmostEqual(corrected_r, -0.2339460505, places=8)
        self.assertAlmostEqual(float(legacy["LegacyMeanWhPerMinute"].max()), 305.5854, places=3)
        self.assertAlmostEqual(
            float(corrected["ReleasedGridCompleteConsumptionKWh"].max()),
            390.30987,
            places=6,
        )

    def test_figure8_pv_cohort_and_h4_anchors(self) -> None:
        indexed = self.energy.totals_kwh.set_index("HouseID")
        detected = indexed.index[indexed["PaperLegacyProductionKWh"] > 1.0].tolist()
        self.assertEqual(set(detected), set(figures.PV_PAPER_ORDER))
        self.assertAlmostEqual(
            float(indexed.loc["H4", "PaperLegacyProductionKWh"]), 1864.890715, places=6
        )
        self.assertAlmostEqual(
            float(indexed.loc["H4", "PaperLegacyConsumptionKWh"]), 7875.42646, places=5
        )
        self.assertAlmostEqual(
            float(indexed.loc["H4", "PaperLegacyFromGridKWh"]), 6609.8612, places=6
        )

    def test_figure9_week_is_complete_and_balanced_with_feed_in(self) -> None:
        week, metrics = figures.load_figure9(self.data_dir)
        self.assertEqual(len(week), 10080)
        self.assertEqual(metrics["DuplicateTimestamps"], 0)
        self.assertEqual(metrics["MissingMinutes"], 0)
        self.assertEqual(metrics["UnexpectedTimestamps"], 0)
        self.assertEqual(metrics["NonfiniteDerivedPowerRows"], 0)
        self.assertTrue(metrics["TimestampSequenceExact"])
        self.assertLessEqual(float(metrics["MaximumAbsoluteBalanceResidualWh"]), 0.43 + 1e-12)
        self.assertEqual(str(week["date"].iloc[0]), "2020-12-07 00:00:00")
        self.assertEqual(str(week["date"].iloc[-1]), "2020-12-13 23:59:00")

    def test_figure10_is_fail_closed_without_exact_inputs(self) -> None:
        claims = figures.load_claims(self.reference_dir)
        self.assertEqual(
            claims["figure10"]["classification"],
            "structural_only_exact_inputs_unpublished",
        )

    def test_publish_refuses_existing_directory_file_and_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for target_kind in ("directory", "file", "symlink"):
                stage = root / f"stage-{target_kind}"
                stage.mkdir()
                target = root / f"target-{target_kind}"
                if target_kind == "directory":
                    target.mkdir()
                elif target_kind == "file":
                    target.write_text("occupied", encoding="utf-8")
                else:
                    try:
                        target.symlink_to(root / "missing-target")
                    except OSError as error:
                        if os.name == "nt" and getattr(error, "winerror", None) == 1314:
                            # Windows without link privilege still checks files/directories.
                            continue
                        raise
                with self.assertRaises(FileExistsError):
                    figures.publish_directory_no_replace(stage, target)
                self.assertTrue(stage.is_dir())

    def test_generate_writes_closed_manifest_and_kwh_schema(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "figure-audit"
            summary = figures.generate(self.data_dir, self.reference_dir, output)
            self.assertTrue(all(summary["required_gates"].values()))
            self.assertTrue(
                all(type(value) is bool for value in summary["required_gates"].values())
            )
            self.assertEqual(summary["contractId"], "SR2020-IR-v2")
            manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["provenance"]["contractId"], "SR2020-IR-v2")
            self.assertEqual(
                manifest["provenance"]["contractSha256"],
                figures.sha256_file(figures.CONTRACT_PATH),
            )
            self.assertEqual(manifest["provenance"]["verified_release_file_count"], 46)
            self.assertEqual(
                manifest["provenance"]["verified_figshare_inventory_file_count"], 46
            )
            self.assertEqual(len(manifest["verified_release_files"]), 46)
            self.assertEqual(len(manifest["verified_figshare_inventory_files"]), 46)
            self.assertNotIn("manifest.json", manifest["artifact_sha256"])
            self.assertNotIn("RESULT_MANIFEST.sha256", manifest["artifact_sha256"])
            schema = manifest["figure6_audit_schema"]
            self.assertEqual(schema["alignment_rule"], "frozen_rule_based_v2")
            self.assertEqual(schema["daily_lag_minimum_finite_points"], 60)
            self.assertIn("diagnostic_only", schema["daily_lag_interpretation"])
            self.assertEqual(
                schema["date_transpose_pass_rule"],
                (
                    "MatchedFinitePoints>=60 and PearsonR>0.99 under the mapped "
                    "comparison scope"
                ),
            )
            self.assertEqual(
                schema["mapped_comparison_scope"]["name"],
                figures.MAPPED_W_STATUS_SCOPE,
            )
            self.assertEqual(schema["unaffected_alignment_days"], 146)
            self.assertEqual(schema["unassessable_no_finite_W_pair_days"], 1)
            self.assertEqual(schema["affected_core_aligned_days"], 184)
            self.assertEqual(schema["affected_unresolved_days"], 35)
            self.assertEqual(schema["forensic_blocks"], 20)
            self.assertEqual(
                set(schema["comparison_scopes"]),
                {"finite_release_same_timestamp", "observed_both_endpoints"},
            )
            self.assertEqual(set(schema["sidecars"]), set(figures.FIGURE6_NORMATIVE_SIDECARS))
            same60 = summary["key_metrics"][
                "figure6_h4_same_date_plus60_consumption"
            ]
            self.assertEqual(
                same60,
                {
                    "core_days_pass_r0p99": 135,
                    "continuous_24h_days_pass_r0p99": 131,
                    "continuous_24h_failure_dates": [
                        "2020-05-31",
                        "2020-06-30",
                        "2020-07-31",
                        "2020-08-31",
                    ],
                },
            )
            for name in figures.FIGURE6_NORMATIVE_SIDECARS:
                self.assertTrue((output / name).is_file(), name)
                self.assertIn(name, manifest["artifact_sha256"])
            expected_artifacts = {
                path.name
                for path in output.iterdir()
                if path.is_file()
                and path.name not in {"manifest.json", "RESULT_MANIFEST.sha256"}
            }
            self.assertEqual(set(manifest["artifact_sha256"]), expected_artifacts)
            for name, expected in manifest["artifact_sha256"].items():
                self.assertEqual(figures.sha256_file(output / name), expected, name)
            self.assertTrue((output / "figure6_all_house_consistency.png").is_file())
            self.assertTrue((output / "figure6_h4_temporal_diagnostics.png").is_file())
            all_house = pd.read_csv(output / "figure6_all_house_metrics.csv")
            self.assertEqual(len(all_house), 80)
            self.assertEqual(
                set(all_house["ComparisonScope"]),
                {"finite_release_same_timestamp", "observed_both_endpoints"},
            )
            result_manifest_entries = {}
            for line in (output / "RESULT_MANIFEST.sha256").read_text(encoding="utf-8").splitlines():
                expected, name = line.split(maxsplit=1)
                self.assertNotIn(name, result_manifest_entries)
                result_manifest_entries[name] = expected
                self.assertEqual(figures.sha256_file(output / name), expected)
            self.assertEqual(
                set(result_manifest_entries),
                {
                    path.name
                    for path in output.iterdir()
                    if path.is_file() and path.name != "RESULT_MANIFEST.sha256"
                },
            )
            pv = pd.read_csv(output / "figure8_pv_annual_totals.csv")
            self.assertIn("PaperLegacyProductionKWh", pv.columns)
            self.assertIn("Calendar2020ProductionKWh", pv.columns)
            self.assertNotIn("Production(Wh)", pv.columns)
            coverage = pd.read_csv(output / "figure7b_timestamp_coverage.csv")
            self.assertEqual(coverage.columns[0], "Date")
            with self.assertRaises(FileExistsError):
                figures.generate(self.data_dir, self.reference_dir, output)

    def test_generate_rejects_unverified_custom_data_root(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaisesRegex(ValueError, "verified Figshare v1 root"):
                figures.generate(Path(temporary), self.reference_dir, Path(temporary) / "out")


if __name__ == "__main__":
    unittest.main()
