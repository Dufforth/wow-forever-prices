import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import build_addon_zip  # noqa: E402
import build_watch_list  # noqa: E402
import install_addon  # noqa: E402

NAME = "DufforthAHScanner"


class AddonZipTests(unittest.TestCase):
    def test_zip_unpacks_as_one_folder_with_every_file_the_toc_lists(self):
        with tempfile.TemporaryDirectory() as folder:
            out = build_addon_zip.build(folder)
            with zipfile.ZipFile(out) as archive:
                names = set(archive.namelist())
                toc = archive.read(f"{NAME}/{NAME}.toc").decode("utf-8")
        self.assertTrue(all(name.startswith(f"{NAME}/") for name in names))
        listed = [line.strip() for line in toc.splitlines() if line.strip() and not line.startswith("##")]
        self.assertTrue(listed)
        for name in listed:
            self.assertIn(f"{NAME}/{name}", names)

    def test_download_names_and_latest_file_agree_with_the_version(self):
        with tempfile.TemporaryDirectory() as folder:
            build_addon_zip.build(folder)
            latest = json.loads((Path(folder) / "latest.json").read_text())
            self.assertEqual(latest["version"], build_addon_zip.version())
            self.assertEqual(latest["file"], f"{NAME}-{latest['version']}.zip")
            self.assertTrue((Path(folder) / latest["file"]).exists())
            self.assertTrue((Path(folder) / f"{NAME}.zip").exists())

    def test_toc_has_the_new_name_and_saves_under_it(self):
        toc = (ROOT / f"addon/{NAME}/{NAME}.toc").read_text(encoding="utf-8")
        self.assertRegex(toc, r"(?m)^## Title: Dufforth AH Scanner\s*$")
        self.assertRegex(toc, rf"(?m)^## SavedVariables: {NAME}DB\s*$")
        self.assertRegex(toc, r"(?m)^## Interface: \d+")

    def test_no_old_name_left_in_the_addon(self):
        for path in (ROOT / f"addon/{NAME}").iterdir():
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("Gathering Tracker", text, path.name)
            self.assertNotIn("TentTimer", text, path.name)


class WatchListTests(unittest.TestCase):
    def test_picks_traded_uncommon_crafted_gear_only(self):
        catalog = {
            "recipes": [{"i": 1}, {"i": 2}, {"i": 3}, {"i": 5}],
            "items": {"1": {"cl": 4, "q": 2}, "2": {"cl": 2, "q": 2}, "3": {"cl": 4, "q": 3}, "4": {"cl": 4, "q": 2}, "5": {"cl": 7, "q": 1}},
        }
        houses = [
            {"1": [0, 0, 5, 0, 0, 0, 1], "2": [0, 0, 1, 0, 0, 0, 0], "3": [0, 0, 99, 0, 0, 0, 9], "4": [0, 0, 99, 0, 0, 0, 9], "5": [0, 0, 99, 0, 0, 0, 9]},
            {"2": [0, 0, 30, 0, 0, 0, 0]},
        ]
        self.assertEqual(build_watch_list.pick(catalog, houses), [2, 1])
        self.assertEqual(build_watch_list.pick(catalog, houses, 1), [2])


class InstallTests(unittest.TestCase):
    def game(self, folder):
        game = Path(folder)
        (game / "Interface/AddOns/TentTimer").mkdir(parents=True)
        (game / "Interface/AddOns/TentTimer/Scan.lua").write_text("old")
        saved = game / "WTF/Account/123#1/SavedVariables"
        saved.mkdir(parents=True)
        (saved / "TentTimer.lua").write_text('TentTimerDB = {\n["nodes"] = { ["swapSeconds"] = 7 },\n}\n')
        return game, saved

    def test_replaces_the_old_folder_and_moves_settings(self):
        with tempfile.TemporaryDirectory() as folder:
            game, saved = self.game(folder)
            target, moved = install_addon.install(game)
            self.assertEqual(moved, 1)
            self.assertTrue((target / "Scan.lua").exists())
            self.assertFalse((game / "Interface/AddOns/TentTimer").exists())
            self.assertIn(f'{NAME}DB = {{\n["nodes"] = {{ ["swapSeconds"] = 7 }}', (saved / f"{NAME}.lua").read_text())
            self.assertTrue((saved / "TentTimer.lua").exists(), "the old settings stay as a backup")

    def test_never_overwrites_settings_already_moved(self):
        with tempfile.TemporaryDirectory() as folder:
            game, saved = self.game(folder)
            (saved / f"{NAME}.lua").write_text("newer")
            _, moved = install_addon.install(game)
            self.assertEqual(moved, 0)
            self.assertEqual((saved / f"{NAME}.lua").read_text(), "newer")


if __name__ == "__main__":
    unittest.main()
