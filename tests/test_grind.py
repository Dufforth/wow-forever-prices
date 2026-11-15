import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "catalog"))
import build_grind as bg  # noqa: E402


def spawn(entry, x, y, level=10, respawn=300, m=0):
    return {"entry": entry, "map": m, "x": x, "y": y, "level": level, "respawn": respawn}


class ClusterTest(unittest.TestCase):
    def test_close_spawns_join_and_far_ones_split(self):
        spawns = [spawn(1, i * 20, 0) for i in range(10)] + [spawn(1, 5000 + i * 20, 0) for i in range(10)]
        clusters = bg.clusters(spawns)
        self.assertEqual(sorted(len(c) for c in clusters), [10, 10])

    def test_levels_far_apart_do_not_join(self):
        spawns = [spawn(1, i * 20, 0, level=10) for i in range(8)] + [spawn(2, i * 20, 10, level=16) for i in range(8)]
        self.assertEqual(sorted(len(c) for c in bg.clusters(spawns)), [8, 8])

    def test_no_chain_across_many_levels(self):
        spawns = [spawn(1, i * 20, 0, level=6 + i) for i in range(12)]
        for c in bg.clusters(spawns):
            levels = [s["level"] for s in c]
            self.assertLess(max(levels) - min(levels), bg.LEVEL_BAND)

    def test_other_maps_do_not_join(self):
        spawns = [spawn(1, i * 20, 0) for i in range(8)] + [spawn(1, i * 20, 0, m=1) for i in range(8)]
        self.assertEqual(len(bg.clusters(spawns)), 2)

    def test_a_huge_area_is_cut_into_tiles(self):
        spawns = [spawn(1, i * 30, 0) for i in range(100)]  # a 3000 yard line
        clusters = bg.clusters(spawns)
        self.assertGreater(len(clusters), 3)
        for c in clusters:
            xs = [s["x"] for s in c]
            self.assertLessEqual(max(xs) - min(xs), bg.TILE)

    def test_nearest_neighbour_distance(self):
        self.assertAlmostEqual(bg.nearest_gap([spawn(1, i * 25, 0) for i in range(6)]), 25)

    def test_centre_is_the_spawn_with_most_neighbours(self):
        c = [spawn(1, 0, 0), spawn(1, 20, 0), spawn(1, 40, 0), spawn(1, 30, 10), spawn(1, 900, 0)]
        self.assertIn(bg.centre(c)["x"], (20, 30))


class FlagsTest(unittest.TestCase):
    def test_mage_class_is_a_caster(self):
        self.assertTrue(bg.mob_flags({"UnitClass": "8", "Rank": "0"}, [], set()) & bg.CASTER)

    def test_cast_of_a_bolt_makes_a_caster(self):
        f = bg.mob_flags({"UnitClass": "1", "Rank": "0"}, ["Shadow Bolt"], set())
        self.assertTrue(f & bg.CASTER)

    def test_heal_and_flee(self):
        f = bg.mob_flags({"UnitClass": "2", "Rank": "0"}, ["Holy Light"], {"flee"})
        self.assertTrue(f & bg.HEALER)
        self.assertTrue(f & bg.FLEES)
        self.assertFalse(f & bg.CASTER)

    def test_melee_buffs_are_not_casting(self):
        self.assertEqual(bg.mob_flags({"UnitClass": "1", "Rank": "0"}, ["Thrash", "Battle Shout"], set()), 0)

    def test_elite_rank(self):
        self.assertTrue(bg.mob_flags({"UnitClass": "1", "Rank": "1"}, [], set()) & bg.ELITE)
        self.assertFalse(bg.mob_flags({"UnitClass": "1", "Rank": "4"}, [], set()) & bg.ELITE)


class ValueTest(unittest.TestCase):
    def test_grays_go_to_vendor_and_good_drops_are_kept_apart(self):
        items = {10: {"Quality": "0", "SellPrice": "25", "bonding": "0"},
                 20: {"Quality": "1", "SellPrice": "5", "bonding": "0"},
                 30: {"Quality": "2", "SellPrice": "300", "bonding": "2"},
                 40: {"Quality": "1", "SellPrice": "0", "bonding": "4"}}  # quest item
        drops = {10: (0.5, 0.5), 20: (0.4, 0.8), 30: (0.01, 0.01), 40: (0.9, 0.9)}
        vendor, notable = bg.loot_value(drops, items, coin=10)
        # Coin 10 + gray 0.5 x 25; the trade good and the green are notable (their AH price decides at runtime).
        self.assertAlmostEqual(vendor, 10 + 12.5)
        self.assertEqual([n[0] for n in notable], [20, 30])

    def test_bound_items_count_at_vendor_price(self):
        items = {50: {"Quality": "2", "SellPrice": "100", "bonding": "1"}}
        vendor, notable = bg.loot_value({50: (0.1, 0.1)}, items, coin=0)
        self.assertAlmostEqual(vendor, 10)
        self.assertEqual(notable, [])


class MobTest(unittest.TestCase):
    def test_a_monster_row_has_its_look_and_value(self):
        t = {"Name": "Mottled Boar", "MinLevel": "1", "MaxLevel": "2", "ModelId1": "0", "ModelId2": "381",
             "CreatureType": "1", "Family": "5"}
        row = bg.mob_summary(t, bg.FLEES, 12.34, [[117, 0.2]])
        self.assertEqual(row, ["Mottled Boar", 1, 2, 381, 1, 5, bg.FLEES, 12.3, [[117, 0.2]]])
        self.assertEqual(len(row), len(bg.MOB_COLUMNS))


class AttackableTest(unittest.TestCase):
    def test_vendors_critters_and_town_npcs_are_left_out(self):
        factions = {1: {"FactionGroup": "0", "FriendGroup": "0", "EnemyGroup": "1"},
                    2: {"FactionGroup": "4", "FriendGroup": "4", "EnemyGroup": "1"}}
        base = {"NpcFlags": "0", "CreatureType": "1", "UnitFlags": "0", "Faction": "1", "MinLevel": "10", "ExperienceMultiplier": "1"}
        self.assertTrue(bg.attackable(base, factions))
        self.assertFalse(bg.attackable(dict(base, NpcFlags="128"), factions))
        self.assertFalse(bg.attackable(dict(base, CreatureType="8"), factions))
        self.assertFalse(bg.attackable(dict(base, Faction="2"), factions))
        self.assertFalse(bg.attackable(dict(base, UnitFlags="2"), factions))
        self.assertFalse(bg.attackable(dict(base, ExtraFlags="1024"), factions))  # Booty Bay Bruiser


if __name__ == "__main__":
    unittest.main()
