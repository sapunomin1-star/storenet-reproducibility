"""圖 6：H4 功率 W 與每分鐘能量 Wh × 60 的一致性。"""
from _common import DATA, core, output_run


def main():
    inputs = [DATA / "H4_W.csv", DATA / "H4_Wh.csv"]
    note = (
        "圖 6：依相同時間標籤比較 H4 的 W 與 Wh × 60。"
        "公開 H4 檔案存在時間組裝問題，因此這張圖是公開資料的檢查結果，"
        "不能逐點重現論文使用未公開原始檔所畫的圖。"
    )
    with output_run("圖06_功率與能量一致性", inputs, __file__, note) as output:
        joined, metrics = core.load_figure6(DATA)
        metrics.to_csv(output / "圖06_相關係數與誤差.csv", index=False)
        core.render_figure6(joined, output / "圖06_功率與能量一致性.png")


if __name__ == "__main__":
    main()
