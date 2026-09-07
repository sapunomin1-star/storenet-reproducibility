"""圖 5：20 戶的資料可用率。只計算、輸出這張圖。"""
from _common import DATA, REFERENCE, core, output_run


def main():
    inputs = [DATA / f"{house}_W.csv" for house in core.HOUSE_IDS]
    inputs.append(REFERENCE / "data_paper_fig5_availability.csv")
    note = "圖 5：20 戶的資料可用率；百分比可與論文標示的小數點後兩位核對。"
    with output_run("圖05_資料可用率", inputs, __file__, note) as output:
        summary, matrix = core.load_figure5(DATA, REFERENCE)
        if not summary["RoundedMatch"].all():
            raise ValueError("資料可用率與論文參考值不符，請查看輸入資料。")
        summary.to_csv(output / "圖05_資料可用率.csv", index=False)
        core.render_figure5(summary, matrix, output / "圖05_資料可用率.png")


if __name__ == "__main__":
    main()
