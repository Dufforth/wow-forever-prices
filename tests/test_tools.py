import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import build_addon_zip  # noqa: E402
import build_addon_prices  # noqa: E402
import build_addon_crafts  # noqa: E402
import install_addon  # noqa: E402

NAME = "DufforthTweaksHelper"


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
        self.assertRegex(toc, r"(?m)^## Title: Dufforth Tweaks Helper\s*$")
        self.assertIn("INV_Misc_QuestionMark", toc)
        self.assertRegex(toc, rf"(?m)^## SavedVariables: {NAME}DB\s*$")
        self.assertRegex(toc, r"(?m)^## Interface: \d+")

    def test_no_old_name_left_in_the_addon(self):
        for path in (ROOT / f"addon/{NAME}").iterdir():
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("Gathering Tracker", text, path.name)
            self.assertNotIn("TentTimer", text, path.name)
            self.assertNotIn("Scanner", text, path.name)
            self.assertNotIn("/ahscan", text, path.name)


class AddonPriceTests(unittest.TestCase):
    def test_keeps_listed_wanted_items_only_and_writes_lua(self):
        items = {"10940": [80, 95, 10, 0, 0, 0], "10938": [100, None, 3, 0, 0, 0], "11083": [500, 540, 0, 0, 0, 0], "2589": [10, 12, 99, 0, 0, 0]}
        self.assertEqual(build_addon_prices.prices_for(items, [10940, 10938, 11083]), {10940: 95, 10938: 100})
        text = build_addon_prices.lua({"forever.normal.horde.us": {10940: 95}, "forever.rp.horde.us": {}}, 123)
        self.assertIn('DufforthTweaksHelperPrices = { at = 123,', text)
        self.assertIn('["forever.normal.horde.us"] = { [10940]=95 },', text)
        self.assertNotIn("forever.rp.horde.us", text)
        self.assertIn("DufforthTweaksHelperNoDE = { [11287]=true }", build_addon_prices.lua({}, 1, [11287]))

    def test_wants_every_material_and_the_gear_list(self):
        ids = build_addon_prices.wanted_ids()
        self.assertIn(20725, ids)
        self.assertGreater(len(ids), 1000)


class AddonCraftsTests(unittest.TestCase):
    def test_lists_gear_recipes_with_vendor_prices_and_material_recipes(self):
        catalog = {"items": {
            "1": {"n": "Linen Cloth", "q": 1, "cl": 7},
            "2": {"n": "Thread", "q": 1, "cl": 7, "v": 1, "buy": 10},
            "3": {"n": "Bolt", "q": 1, "cl": 7},
            "900": {"n": 'Green "Robe"', "q": 2, "il": 30, "cl": 4, "inv": 20},
            "901": {"n": "Green Shirt", "q": 2, "il": 30, "cl": 4, "inv": 4},
            "902": {"n": "Wand", "q": 2, "il": 20, "cl": 2, "inv": 26, "nd": 1},
        }, "recipes": [
            {"s": 10, "p": "Tailoring", "sk": 50, "o": ["trainer"], "i": 900, "c": 1, "r": [[3, 2], [2, 1]]},
            {"s": 11, "p": "Tailoring", "sk": 60, "o": ["trainer"], "i": 901, "c": 1, "r": [[3, 1]]},
            {"s": 12, "p": "Enchanting", "sk": 10, "o": ["trainer"], "i": 902, "c": 1, "r": [[1, 1]]},
            {"s": 13, "p": "Tailoring", "sk": 1, "o": ["trainer"], "i": 3, "c": 1, "r": [[1, 2]]},
        ], "noDisenchant": [902]}
        text, gear, materials, vendor = build_addon_crafts.lua(catalog)
        self.assertEqual((gear, materials, vendor), (1, 1, 1))
        self.assertIn('{ 10, 9, 50, 900, 1, 2, 30, 4, 0, "Green \\"Robe\\"", { 3, 2, 2, 1 } },', text)
        self.assertIn("[3] = { 1, { 1, 2 } },", text)
        self.assertIn("DufforthTweaksHelperVendor = { [2]=10 }", text)
        self.assertEqual(build_addon_crafts.reagent_ids(catalog), ([1, 2, 3], [900]))

    def test_prices_cover_every_crafting_material(self):
        reagents, products = build_addon_crafts.reagent_ids(build_addon_crafts.load_catalog())
        ids = set(build_addon_prices.wanted_ids())
        self.assertTrue(set(reagents) <= ids and set(products) <= ids)


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
            stale = Path(game) / "Interface/AddOns" / NAME / "Stale.lua"
            stale.parent.mkdir(parents=True, exist_ok=True)
            stale.write_text("old", encoding="utf-8")
            target, moved = install_addon.install(game)
            self.assertEqual(moved, 1)
            self.assertTrue((target / "Core.lua").exists())
            self.assertFalse(stale.exists(), "files gone from the project are removed")
            self.assertFalse((game / "Interface/AddOns/TentTimer").exists())
            self.assertIn(f'{NAME}DB = {{\n["nodes"] = {{ ["swapSeconds"] = 7 }}', (saved / f"{NAME}.lua").read_text())
            self.assertTrue((saved / "TentTimer.lua").exists(), "the old settings stay as a backup")

    def test_moves_dufforth_ah_scanner_settings_first(self):
        with tempfile.TemporaryDirectory() as folder:
            game, saved = self.game(folder)
            (game / "Interface/AddOns/DufforthAHScanner").mkdir(parents=True)
            (saved / "DufforthAHScanner.lua").write_text('DufforthAHScannerDB = {\n["nodes"] = { ["size"] = 12 },\n}\n')
            _, moved = install_addon.install(game)
            self.assertEqual(moved, 1)
            self.assertFalse((game / "Interface/AddOns/DufforthAHScanner").exists())
            self.assertIn(f'{NAME}DB = {{\n["nodes"] = {{ ["size"] = 12 }}', (saved / f"{NAME}.lua").read_text())

    def test_never_overwrites_settings_already_moved(self):
        with tempfile.TemporaryDirectory() as folder:
            game, saved = self.game(folder)
            (saved / f"{NAME}.lua").write_text("newer")
            _, moved = install_addon.install(game)
            self.assertEqual(moved, 0)
            self.assertEqual((saved / f"{NAME}.lua").read_text(), "newer")


if __name__ == "__main__":
    unittest.main()


try:
    import lupa  # noqa: F401
    HAVE_LUPA = True
except ImportError:  # CI runs these before installing lupa; the addon step covers it then
    HAVE_LUPA = False


@unittest.skipUnless(HAVE_LUPA, "needs lupa")
class WarriorHistoryTests(unittest.TestCase):
    SAVED = """DufforthTweaksHelperDB = { warrior = {
      macros = { "/startattack\\n/cast Heroic Strike" },
      fights = {
        { at = 100, seconds = 12.5, zone = "The Barrens", character = "Duff-Realm", macro = 1, casts = { "1.0 Heroic Strike r0" } },
        { at = 200, seconds = 8, zone = "The Barrens", character = "Duff-Realm", macro = 1, casts = {} },
      } } }"""

    def setUp(self):
        import archive_warrior_fights
        self.tool = archive_warrior_fights
        self.folder = tempfile.TemporaryDirectory()
        base = Path(self.folder.name)
        self.game = base / "game"
        saved = self.game / "WTF" / "Account" / "123#1" / "SavedVariables"
        saved.mkdir(parents=True)
        self.saved = saved / "DufforthTweaksHelper.lua"
        self.saved.write_text(self.SAVED, encoding="utf-8")
        self.history = base / "history" / "fights.jsonl"

    def tearDown(self):
        self.folder.cleanup()

    def records(self):
        return [json.loads(line) for line in self.history.read_text(encoding="utf-8").splitlines()]

    def test_copies_every_fight_with_its_macro_text(self):
        self.assertEqual(self.tool.archive(str(self.game), self.history), (2, 2))
        first = self.records()[0]
        self.assertEqual(first["account"], "123#1")
        self.assertEqual(first["macro"], "/startattack\n/cast Heroic Strike")
        self.assertEqual(first["fight"]["casts"], ["1.0 Heroic Strike r0"])

    def test_each_fight_carries_its_gear_set(self):
        self.saved.write_text(self.SAVED.replace(
            "macros = {", 'gear = { { key = "k1", level = 25, stats = { strength = 60 } } },\n      macros = {').replace(
            "macro = 1, casts = {}", "macro = 1, gear = 1, casts = {}"), encoding="utf-8")
        self.tool.archive(str(self.game), self.history)
        records = self.records()
        self.assertNotIn("gear", records[0])
        self.assertEqual(records[1]["gear"]["stats"]["strength"], 60)

    def test_running_again_adds_only_new_fights_and_keeps_old_ones(self):
        self.tool.archive(str(self.game), self.history)
        self.assertEqual(self.tool.archive(str(self.game), self.history), (0, 2))
        # The game dropped the oldest fight and logged a new one: the old one stays in the history.
        self.saved.write_text(self.SAVED.replace("at = 100", "at = 300"), encoding="utf-8")
        self.assertEqual(self.tool.archive(str(self.game), self.history), (1, 3))
        self.assertEqual(sorted(r["fight"]["at"] for r in self.records()), [100, 200, 300])
