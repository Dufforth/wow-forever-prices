import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "catalog"))
import build_farm  # noqa: E402


def loot(*rows):
    """rows: (entry, item, chance, group, min/ref, max)."""
    keys = ("entry", "item", "ChanceOrQuestChance", "groupid", "mincountOrRef", "maxcount")
    return build_farm.loot_index([dict(zip(keys, map(str, r))) for r in rows])


class FarmTest(unittest.TestCase):
    def test_parse_values_handles_quotes_and_nulls(self):
        rows = build_farm.parse_values("(1,'Hogger''s Claw',NULL,-2.5),(2,'A \\'b\\'',3,4)")
        self.assertEqual(rows, [["1", "Hogger's Claw", None, "-2.5"], ["2", "A 'b'", "3", "4"]])

    def test_read_dump_keeps_columns_and_rows(self):
        dump = "CREATE TABLE `creature` (\n  `guid` int,\n  `id` int\n) ENGINE=x;\nINSERT INTO `creature` VALUES (1,448),(2,6);\n"
        tables = build_farm.read_dump(dump, ("creature",))
        self.assertEqual(build_farm.as_dicts(tables["creature"]), [{"guid": "1", "id": "448"}, {"guid": "2", "id": "6"}])

    def test_plain_chance_and_average_count(self):
        out = build_farm.expected_items(1, loot((1, 100, 40, 0, 1, 3)), {})
        self.assertAlmostEqual(out[100][0], 0.4)
        self.assertAlmostEqual(out[100][1], 0.8)  # 40% x 2 on average

    def test_quest_only_drops_are_left_out(self):
        self.assertEqual(build_farm.expected_items(1, loot((1, 100, -80, 0, 1, 1)), {}), {})

    def test_group_entries_without_chance_share_what_is_left(self):
        creature = loot((1, 100, 40, 1, 1, 1), (1, 101, 0, 1, 1, 1), (1, 102, 0, 1, 1, 1))
        out = build_farm.expected_items(1, creature, {})
        self.assertAlmostEqual(out[100][0], 0.4)
        self.assertAlmostEqual(out[101][0], 0.3)
        self.assertAlmostEqual(out[102][0], 0.3)

    def test_references_multiply_through(self):
        creature = loot((1, 0, 50, 0, -9, 2))  # 50% to roll list 9, twice
        reference = loot((9, 200, 20, 0, 1, 1))
        out = build_farm.expected_items(1, creature, reference)
        self.assertAlmostEqual(out[200][1], 0.5 * 2 * 0.2)

    def test_overlapping_zones_follow_nearby_known_spots(self):
        ui = [{"ID": "1", "Name_lang": "West", "Type": "3"}, {"ID": "2", "Name_lang": "East", "Type": "3"}]
        box = lambda ui_id, x0, y0, x1, y1: {"UiMapID": ui_id, "MapID": "0", "Region_0": x0, "Region_1": y0, "Region_3": x1, "Region_4": y1}
        assignments = [box("1", 0, 0, 1000, 1000), box("2", 0, 0, 1000, 600)]
        labelled = [(0, 500, 900, "West", 10), (0, 520, 880, "West", 10), (0, 510, 860, "West", 10)]
        find = build_farm.zone_finder(assignments, ui, {}, labelled)
        self.assertEqual(find(0, 500, 590)[0], "West")  # inside both maps, nearer West's known spots
        self.assertEqual(find(0, 500, 590, 50)[0], "East")  # a level 50 monster can't be in a level 10 zone


if __name__ == "__main__":
    unittest.main()
