"""圖 9：H4 在 2020 年 12 月 7～13 日的電力與電池運作。"""
from _common import DATA, core, output_run


def main():
    note = "圖 9：H4 一週的太陽能、用電、電網交換、電池充放電與電量，共 10,080 分鐘。"
    with output_run("圖09_一週電池與電力運作", [DATA / "H4_Wh.csv"], __file__, note) as output:
        week, metrics = core.load_figure9(DATA)
        if not metrics["TimestampSequenceExact"] or metrics["NonfiniteDerivedPowerRows"]:
            raise ValueError("H4 指定週的時間或功率資料不完整。")
        week.to_csv(output / "圖09_每分鐘資料.csv", index=False)
        core.write_json(output / "圖09_能量平衡與摘要.json", metrics)
        core.render_figure9(week, output / "圖09_一週電池與電力運作.png")


if __name__ == "__main__":
    main()
