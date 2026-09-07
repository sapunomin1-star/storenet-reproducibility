"""逐圖入口的共用檔案處理；計算公式仍沿用原復現程式。"""
from contextlib import contextmanager
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import platform
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src"))
import reproduce_data_paper_figures as core

DATA = ROOT / "data" / "raw"
REFERENCE = ROOT / "reference"


@contextmanager
def output_run(name, inputs, entry, note):
    """先完成一張圖，再更新它的固定結果資料夾；失敗時保留上次結果。"""
    print(f"開始：{name}。正在核對並讀取公開資料。", flush=True)
    manifest = ROOT / "data" / "RELEASE_MANIFEST.sha256"
    expected = {}
    for line in manifest.read_text(encoding="utf-8").splitlines():
        if line.strip() and not line.startswith("#"):
            digest, relative = line.split(maxsplit=1)
            expected[(ROOT.parent / relative.strip()).resolve()] = digest
    hashes = {}
    for path in inputs:
        digest = core.sha256_file(path)
        if path.parent == DATA and expected.get(path.resolve()) != digest:
            raise ValueError(f"公開資料與原始雜湊不符：{path.name}")
        hashes[str(path.relative_to(ROOT))] = digest

    destination = ROOT / "results" / "data_paper_by_figure" / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=f".{name}-", dir=destination.parent) as temporary:
        stage = Path(temporary)
        print("正在計算並繪製這一張圖……", flush=True)
        yield stage
        (stage / "00_結果說明.md").write_text(
            f"# {name}\n\n{note}\n\n"
            "由公開 CSV 重新計算；公式與共用繪圖函式沿用 reproduce_data_paper_figures.py。\n"
            "這是單張圖的執行結果；完整資料稽核仍見原有正式結果資料夾。\n"
            "再次執行會更新這個資料夾中的同一版結果。\n",
            encoding="utf-8",
        )
        record = {
            "figure": name,
            "completed_utc": datetime.now(timezone.utc).isoformat(),
            "note": note,
            "input_sha256": hashes,
            "code_sha256": {
                str(path.relative_to(ROOT)): core.sha256_file(path)
                for path in (Path(entry).resolve(), Path(__file__).resolve(), Path(core.__file__).resolve())
            },
            "python": platform.python_version(),
            "numpy": core.np.__version__,
            "pandas": core.pd.__version__,
            "matplotlib": core.matplotlib.__version__,
            "output_sha256": {path.name: core.sha256_file(path) for path in sorted(stage.iterdir())},
        }
        (stage / "執行紀錄.json").write_text(
            json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        destination.mkdir(exist_ok=True)
        for path in list(stage.iterdir()):
            # 保存一般檔案，讓 Windows 解壓縮後可直接開啟，不需要連結權限。
            os.replace(path, destination / path.name)
        for filename, expected in record["output_sha256"].items():
            if core.sha256_file(destination / filename) != expected:
                raise RuntimeError(f"結果尚未完整寫入：{destination / filename}")
    print(f"{note}\n完成。結果資料夾：\n{destination}", flush=True)
