"""下載原始資料到固定位置；僅使用 Python 標準函式庫。"""
import argparse
import concurrent.futures
import csv
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import time
import urllib.error
import urllib.request
import zipfile

PACKAGE = Path(__file__).resolve().parents[2]
PROJECT = PACKAGE / "StoreNet"


def digest(path, algorithm="sha256"):
    result = hashlib.new(algorithm)
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def matches(path, expected, algorithm="sha256"):
    return path.is_file() and digest(path, algorithm) == expected


def check_existing(path, expected, algorithm="sha256"):
    if not path.exists():
        return False
    if matches(path, expected, algorithm):
        return True
    raise ValueError(f"已有檔案與指定版本不同，請先移開再重試：{path}")


def download(url, destination, expected, algorithm="sha256"):
    """Verify before publishing; partial downloads never replace a valid file."""
    if check_existing(destination, expected, algorithm):
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    for attempt in range(3):
        descriptor, name = tempfile.mkstemp(prefix=".download-", dir=destination.parent)
        temporary = Path(name)
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "StoreNet-reproducibility/1.0"})
            with os.fdopen(descriptor, "wb") as output:
                with urllib.request.urlopen(request, timeout=90) as response:
                    shutil.copyfileobj(response, output, length=1024 * 1024)
            if digest(temporary, algorithm) != expected:
                raise ValueError(f"下載內容與指定版本不同：{url}")
            os.replace(temporary, destination)
            return
        except (urllib.error.URLError, TimeoutError, OSError):
            if attempt == 2:
                raise
            time.sleep(2 * (attempt + 1))
        finally:
            temporary.unlink(missing_ok=True)


def extract_member(archive, member, destination, expected, algorithm="sha256"):
    """Extract one explicitly selected member, never arbitrary ZIP paths."""
    if check_existing(destination, expected, algorithm):
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, name = tempfile.mkstemp(prefix=".extract-", dir=destination.parent)
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, "wb") as output, archive.open(member) as source:
            shutil.copyfileobj(source, output, length=1024 * 1024)
        if digest(temporary, algorithm) != expected:
            raise ValueError(f"壓縮包中的檔案與指定版本不同：{member}")
        os.replace(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)


def storenet(destination, source, config):
    with (PROJECT / "reference/figshare_v1_inventory.csv").open(encoding="utf-8") as stream:
        rows = list(csv.DictReader(stream))
    missing = [row for row in rows if not check_existing(
        destination / "StoreNet/data/raw" / row["FileName"], row["OfficialMD5"], "md5")]
    if not missing:
        print("StoreNet：46 個檔案已齊全。", flush=True)
        return
    if source == "release":
        archive_path = destination / ".downloads/storenet-data-v1.zip"
        print("下載 StoreNet 資料包……", flush=True)
        try:
            download(config["release_url"], archive_path, config["release_sha256"])
        except (urllib.error.URLError, TimeoutError, OSError):
            print("資料包連線失敗，改從 Figshare 逐檔下載。", flush=True)
            source = "upstream"
        else:
            with zipfile.ZipFile(archive_path) as archive:
                for row in missing:
                    relative = "StoreNet/data/raw/" + row["FileName"]
                    extract_member(archive, relative, destination / relative, row["OfficialMD5"], "md5")
    if source == "upstream":
        def fetch(row):
            download(row["DownloadURL"], destination / "StoreNet/data/raw" / row["FileName"], row["OfficialMD5"], "md5")
            print("已下載：" + row["FileName"], flush=True)
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(fetch, missing))
    print("StoreNet：46 個指定版本檔案已完成。", flush=True)


def ausgrid(destination, config):
    entries = {}
    for line in (PROJECT / "data/AUSGRID_MANIFEST.sha256").read_text(encoding="utf-8").splitlines():
        expected, relative = line.split(maxsplit=1)
        entries[relative] = expected
    archive_relative = next(name for name in entries if name.endswith(".zip"))
    archive_path = destination / archive_relative
    print("準備 Ausgrid 2012–2013 資料……", flush=True)
    download(config["ausgrid_url"], archive_path, entries[archive_relative])
    with zipfile.ZipFile(archive_path) as archive:
        for relative, expected in entries.items():
            if relative == archive_relative:
                continue
            basename = Path(relative).name
            candidates = [name for name in archive.namelist() if Path(name).name == basename]
            if len(candidates) != 1:
                raise ValueError(f"Ausgrid 壓縮包內無法唯一找到：{basename}")
            extract_member(archive, candidates[0], destination / relative, expected)
    print("Ausgrid：CSV 與原始欄位說明已完成。", flush=True)


def grid(destination):
    # The IEEE primary CSV license remains unspecified; download from upstream
    # instead of redistributing these files in this repository or its Releases.
    relative = Path("StoreNet/data/external/ieee_european_lv")
    for subdirectory in [Path(), Path("ieee_primary_csv")]:
        record_path = PACKAGE / relative / subdirectory / "來源紀錄.json"
        record = json.loads(record_path.read_text(encoding="utf-8"))
        for entry in record["files"]:
            download(entry["url"], destination / relative / subdirectory / entry["file"], entry["sha256"])
    print("電網：原始來源的指定版本已完成。", flush=True)


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset", choices=["all", "storenet", "ausgrid", "grid"], default="all")
    parser.add_argument("--source", choices=["release", "upstream"], default="release")
    parser.add_argument("--destination", type=Path, default=PACKAGE, help="復現包根目錄；一般使用者不需設定")
    args = parser.parse_args()
    config = json.loads((PROJECT / "config/downloads.json").read_text(encoding="utf-8"))
    destination = args.destination.resolve()
    try:
        if args.dataset in ("all", "storenet"):
            storenet(destination, args.source, config)
        if args.dataset in ("all", "ausgrid"):
            ausgrid(destination, config)
        if args.dataset in ("all", "grid"):
            grid(destination)
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        parser.exit(1, f"資料尚未準備完成：{error}\n可重新執行；已完成且正確的檔案會保留。\n")
    print(f"完成。資料位置：{destination / 'StoreNet/data'}", flush=True)


if __name__ == "__main__":
    main()
