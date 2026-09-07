"""圖 7：每戶用電加總，以及社區用電與日均氣溫；保留 a、b 兩面板。"""
from _common import DATA, REFERENCE, core, output_run


def main():
    inputs = [DATA / f"{house}_Wh.csv" for house in core.HOUSE_IDS]
    inputs += [DATA / "weather.csv", REFERENCE / "data_paper_claims.json",
               REFERENCE / "data_paper_fig7_annual_consumption.csv"]
    note = (
        "圖 7(a) 沿用公開檔加總，平均約 5,003.11 kWh，不等於每戶完整的 2020 年用電。"
        "圖 7(b) 為方便對照論文，保留作者的每日平均算法；"
        "其數值實際是 Wh/min，原論文標成 kWh/day 有誤。"
        "圖中的相關關係是社區用電與日平均氣溫；正確每日 kWh 另存於 CSV。"
    )
    with output_run("圖07_用電量與氣溫", inputs, __file__, note) as output:
        energy = core.load_energy_summary(DATA)
        weather = core.load_weather_daily(DATA)
        legacy = core.merge_daily_with_weather(energy.legacy_daily, weather)
        corrected = core.merge_daily_with_weather(energy.corrected_daily, weather)
        paper = core.pd.read_csv(REFERENCE / "data_paper_fig7_annual_consumption.csv")
        paper.attrs["caption_mean"] = float(
            core.load_claims(REFERENCE)["figure7"]["paper_caption_mean_annual_kwh"]
        )
        energy.totals_kwh.to_csv(output / "圖07a_每戶用電加總.csv", index=False)
        legacy.to_csv(output / "圖07b_作者算法與日均氣溫.csv")
        corrected.to_csv(output / "圖07b_正確每日用電與日均氣溫.csv")
        core.render_figure7(energy.totals_kwh, legacy, paper, output / "圖07_用電量與氣溫.png")


if __name__ == "__main__":
    main()
