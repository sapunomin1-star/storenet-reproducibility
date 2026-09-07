"""CI：重跑六個 Python 入口，並核對數值與潮流結果。"""
import json
import argparse
import os
from pathlib import Path
import subprocess
import sys

import pandas as pd
from pandas.testing import assert_frame_equal
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
RESULTS = ROOT / "StoreNet/results"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()
    environment = dict(os.environ, PYTHONUTF8="1", PYTHONIOENCODING="utf-8")
    entries = [
        "data_paper_figures/figure05_availability.py",
        "data_paper_figures/figure06_consistency.py",
        "data_paper_figures/figure07_consumption_temperature.py",
        "data_paper_figures/figure08_pv_flows.py",
        "data_paper_figures/figure09_battery_week.py",
        "simulate_figure10s_grid.py",
    ]
    for entry in ([] if args.check_only else entries):
        subprocess.run([sys.executable, str(ROOT / "StoreNet/src" / entry)], cwd=ROOT,
                       env=environment, check=True, timeout=600)
    reference = RESULTS / "data_paper_figures_5_10_v2"
    output = RESULTS / "data_paper_by_figure"
    comparisons = [
        ("圖05_資料可用率/圖05_資料可用率.csv", "figure5_availability.csv"),
        ("圖07_用電量與氣溫/圖07b_作者算法與日均氣溫.csv", "figure7b_paper_legacy_daily.csv"),
        ("圖07_用電量與氣溫/圖07b_正確每日用電與日均氣溫.csv", "figure7b_unit_corrected_daily.csv"),
        ("圖08_太陽能住戶能源流向/圖08_太陽能住戶能源流向.csv", "figure8_pv_annual_totals.csv"),
        ("圖09_一週電池與電力運作/圖09_每分鐘資料.csv", "figure9_h4_week_profiles.csv"),
    ]
    for actual, expected in comparisons:
        assert_frame_equal(pd.read_csv(output / actual), pd.read_csv(reference / expected),
                           check_dtype=False, check_exact=False, rtol=1e-10, atol=1e-9)
    metrics = pd.read_csv(reference / "figure6_all_house_metrics.csv")
    expected = metrics.loc[metrics.HouseID.eq("H4") & metrics.ComparisonScope.eq("finite_release_same_timestamp")]
    actual = pd.read_csv(output / "圖06_功率與能量一致性/圖06_相關係數與誤差.csv")
    assert_frame_equal(actual.sort_values("Signal").reset_index(drop=True),
                       expected.sort_values("Signal").reset_index(drop=True),
                       check_dtype=False, check_exact=False, rtol=1e-10, atol=1e-9)
    actual = pd.read_csv(output / "圖07_用電量與氣溫/圖07a_每戶用電加總.csv")
    expected = pd.read_csv(reference / "figure7_annual_consumption.csv").rename(
        columns={"PaperLegacyReproducedConsumptionKWh": "PaperLegacyConsumptionKWh"})
    columns = [c for c in expected if c in actual]
    assert_frame_equal(actual[columns], expected[columns], check_dtype=False,
                       check_exact=False, rtol=1e-10, atol=1e-9)
    validation = json.loads((RESULTS / "figure10_grid/驗證結果.json").read_text(encoding="utf-8"))
    assert validation["AllConverged"] and validation["PowerFlows"] == 48
    assert validation["MaxPowerBalanceResidualKW"] < 1e-3
    assert validation["MaxLPResidual"] < 1e-6
    assert validation["MaxSimultaneousChargeDischargeKW"] < 1e-6
    for folder in [output, RESULTS / "figure10_grid"]:
        for image in folder.rglob("*.png"):
            with Image.open(image) as picture:
                picture.verify()
    print("Six figure entry points passed; numerical references and 48 power flows verified.")


if __name__ == "__main__":
    main()
