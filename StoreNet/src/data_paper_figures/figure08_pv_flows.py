"""圖 8：10 個太陽能住戶的發電、用電、售電與購電雷達圖。"""
from _common import DATA, core, output_run


def main():
    inputs = [DATA / f"{house}_Wh.csv" for house in core.HOUSE_IDS]
    note = (
        "圖 8：四個雷達圖顯示 10 個太陽能住戶的能量流向。"
        "繪圖沿用論文的公開檔加總；CSV 同時保留嚴格限定 2020 年的加總。"
    )
    with output_run("圖08_太陽能住戶能源流向", inputs, __file__, note) as output:
        energy = core.load_energy_summary(DATA)
        totals = energy.totals_kwh.set_index("HouseID").loc[core.PV_PAPER_ORDER].reset_index()
        totals.to_csv(output / "圖08_太陽能住戶能源流向.csv", index=False)
        core.render_figure8(energy.totals_kwh, output / "圖08_太陽能住戶能源流向.png")


if __name__ == "__main__":
    main()
