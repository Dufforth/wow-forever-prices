import re
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import build_addon_zip  # noqa: E402


class AddonZipTests(unittest.TestCase):
    def test_zip_unpacks_as_one_folder_with_every_file_the_toc_lists(self):
        with tempfile.TemporaryDirectory() as folder:
            out = build_addon_zip.build(Path(folder) / "downloads" / "GatheringTracker.zip")
            with zipfile.ZipFile(out) as archive:
                names = set(archive.namelist())
                toc = archive.read("TentTimer/TentTimer.toc").decode("utf-8")
        self.assertTrue(all(name.startswith("TentTimer/") for name in names))
        listed = [line.strip() for line in toc.splitlines() if line.strip() and not line.startswith("##")]
        self.assertTrue(listed)
        for name in listed:
            self.assertIn(f"TentTimer/{name}", names)

    def test_toc_saves_data_under_the_name_the_page_reads(self):
        toc = (ROOT / "addon/TentTimer/TentTimer.toc").read_text(encoding="utf-8")
        self.assertRegex(toc, r"(?m)^## SavedVariables: TentTimerDB\s*$")
        self.assertRegex(toc, r"(?m)^## Interface: \d+")
        self.assertIsNone(re.search(r"[A-Z]:\\", toc))


if __name__ == "__main__":
    unittest.main()
