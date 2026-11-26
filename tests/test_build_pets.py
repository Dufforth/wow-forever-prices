"""catalog/build_pets.py: family modifiers (swapped damage/armor columns) and tameable beasts with their places."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "catalog"))
from build_pets import beasts, family_stats, lua_text  # noqa: E402


class PetsTest(unittest.TestCase):
    def test_family_stats_swap(self):
        rows = [{"family": "2", "healthModifier": "0.98", "damageModifier": "1", "armorModifier": "1.1"},
                {"family": "99", "healthModifier": "1", "damageModifier": "1", "armorModifier": "1"}]
        self.assertEqual(family_stats(rows), {2: (0.98, 1.1, 1.0)})  # cats: +10% damage, as in the game

    def test_beasts(self):
        templates = [
            {"Entry": "1", "Name": "Broken Tooth", "Family": "2", "CreatureTypeFlags": "1", "MinLevel": "37", "MaxLevel": "37",
             "MeleeBaseAttackTime": "1000", "Rank": "4"},
            {"Entry": "2", "Name": "Not Tameable", "Family": "2", "CreatureTypeFlags": "0", "MinLevel": "5", "MaxLevel": "5",
             "MeleeBaseAttackTime": "2000", "Rank": "0"},
            {"Entry": "3", "Name": "In A Dungeon", "Family": "2", "CreatureTypeFlags": "1", "MinLevel": "5", "MaxLevel": "5",
             "MeleeBaseAttackTime": "2000", "Rank": "0"},
        ]
        spawns = [{"id": "1", "map": "0", "position_x": "1", "position_y": "2"}, {"id": "1", "map": "0", "position_x": "3", "position_y": "4"},
                  {"id": "3", "map": "36", "position_x": "1", "position_y": "1"}]
        where = lambda p: ("Badlands", 59.7, 29.4) if p[0] == 0 else None  # noqa: E731
        rows = beasts(templates, spawns, where)
        self.assertEqual(rows, [("Broken Tooth", 2, 37, 37, "Badlands", 59.7, 29.4, 1000, 4)])
        text = lua_text({2: "Cat"}, {2: (0.98, 1.1, 1.0)}, rows, "abcdef0123456")
        self.assertIn('[2] = { "Cat", 0.98, 1.1, 1.0 }', text)
        self.assertIn('{ "Broken Tooth", 2, 37, 37, "Badlands", 59.7, 29.4, 1000, 4 }', text)


if __name__ == "__main__":
    unittest.main()
