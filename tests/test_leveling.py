import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "catalog"))
import build_addon_leveling  # noqa: E402
import build_leveling_sources  # noqa: E402

SOURCES = {"gray": {"1": 60, "2": 90, "3": 0, "4": 120, "5": 50}, "trainers": {"2": [[0, 50, 30]]}, "vendors": {"900": [[0, 400, 1]]},
           "npcs": [["Trainer", "", "H", "Orgrimmar", 50.0, 40.0]]}
CATALOG = {
    "items": {"10": {"n": "Bolt", "sell": 3}, "900": {"n": "Pattern: Vest"}},
    "recipes": [
        {"s": 1, "n": "Bolt", "p": "Tailoring", "sk": 1, "y": 30, "o": ["trainer"], "i": 10, "c": 1, "r": [[2589, 2]]},
        {"s": 2, "n": "Shirt", "p": "Tailoring", "sk": 30, "y": 60, "o": ["trainer"], "i": 11, "c": 1, "r": [[2589, 3]]},
        {"s": 3, "n": "No skill", "p": "Tailoring", "sk": 1, "y": 0, "o": ["trainer"], "i": 12, "c": 1, "r": []},
        {"s": 4, "n": "Vest", "p": "Tailoring", "sk": 80, "y": 90, "o": ["vendor"], "i": 13, "c": 1, "r": [[2589, 4]], "ri": 900},
        {"s": 5, "n": "Mystery", "p": "Tailoring", "sk": 0, "y": 40, "o": ["unknown"], "i": 14, "c": 2, "r": [[2589, 1]]},
        {"s": 6, "n": "Fishing thing", "p": "Fishing", "sk": 1, "y": 10, "o": ["trainer"], "i": 15, "c": 1, "r": []},
    ],
}


class LevelingDataTests(unittest.TestCase):
    def rows(self):
        return {r["name"]: r for r in build_addon_leveling.recipe_rows(CATALOG, SOURCES)}

    def test_how_to_learn(self):
        rows = self.rows()
        self.assertEqual(rows["Bolt"]["how"], "s")  # skill 1 trainer recipe with no trainer found: comes with the profession
        self.assertEqual(rows["Shirt"]["how"], "t")
        self.assertEqual(rows["Vest"]["how"], "v")
        self.assertEqual(rows["Mystery"]["how"], "?")

    def test_rows_without_skill_or_profession_are_left_out(self):
        rows = self.rows()
        self.assertNotIn("No skill", rows)
        self.assertNotIn("Fishing thing", rows)

    def test_colors_are_kept_in_order(self):
        mystery = self.rows()["Mystery"]
        self.assertEqual((mystery["learn"], mystery["yellow"], mystery["gray"]), (1, 40, 50))
        self.assertEqual(self.rows()["Bolt"]["sell"], 3)

    def test_lua_lists_recipes_npcs_trainers_and_vendors(self):
        text = build_addon_leveling.lua(CATALOG, SOURCES)
        self.assertIn('{2,9,30,60,90,11,1,0,"Shirt","t",0,{2589,3}},', text)
        self.assertIn('{"Trainer","","H","Orgrimmar",50.0,40.0},', text)
        self.assertIn("[2]={1,50,30},", text)  # npc numbers start at 1 in Lua
        self.assertIn("[900]={1,400,1},", text)

    def test_leveling_ids_include_recipe_items(self):
        ids = build_addon_leveling.leveling_ids(CATALOG, SOURCES)
        self.assertIn(900, ids)
        self.assertIn(2589, ids)
        self.assertIn(13, ids)


class SideTests(unittest.TestCase):
    def test_faction_sides(self):
        side = build_leveling_sources.side_of
        self.assertEqual(side({"FactionGroup": "3", "FriendGroup": "2", "EnemyGroup": "12"}), "A")
        self.assertEqual(side({"FactionGroup": "5", "FriendGroup": "4", "EnemyGroup": "10"}), "H")
        self.assertEqual(side({"FactionGroup": "0", "FriendGroup": "0", "EnemyGroup": "0"}), "")
        self.assertEqual(side(None), "")


if __name__ == "__main__":
    unittest.main()
