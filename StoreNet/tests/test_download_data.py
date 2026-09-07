"""Downloader protects existing data and rejects damaged download contents."""
import hashlib
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from download_data import download, extract_member


class DownloadDataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "來源 bytes.bin"
        self.source.write_bytes(b"original\x00\xff\r\n")
        self.expected = hashlib.sha256(self.source.read_bytes()).hexdigest()
        self.target = self.root / "output/資料 bytes.bin"

    def test_download_preserves_binary_bytes(self):
        download(self.source.as_uri(), self.target, self.expected)
        self.assertEqual(self.target.read_bytes(), self.source.read_bytes())

    def test_already_correct_file_skips_network(self):
        download(self.source.as_uri(), self.target, self.expected)
        download("https://invalid.invalid/should-not-connect", self.target, self.expected)
        self.assertEqual(self.target.read_bytes(), self.source.read_bytes())

    def test_damaged_download_never_publishes(self):
        with self.assertRaises(ValueError):
            download(self.source.as_uri(), self.target, "0" * 64)
        self.assertFalse(self.target.exists())
        self.assertEqual(list(self.target.parent.iterdir()), [])

    def test_existing_modified_file_is_retained(self):
        self.target.parent.mkdir()
        self.target.write_bytes(b"user-edited")
        with self.assertRaises(ValueError):
            download(self.source.as_uri(), self.target, self.expected)
        self.assertEqual(self.target.read_bytes(), b"user-edited")

    def test_extract_only_selected_file(self):
        path = self.root / "data.zip"
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("expected/file.bin", self.source.read_bytes())
            archive.writestr("../unrequested.txt", "must not be extracted")
        with zipfile.ZipFile(path) as archive:
            extract_member(archive, "expected/file.bin", self.target, self.expected)
        self.assertEqual(self.target.read_bytes(), self.source.read_bytes())
        self.assertFalse((self.root / "unrequested.txt").exists())


if __name__ == "__main__":
    unittest.main()
