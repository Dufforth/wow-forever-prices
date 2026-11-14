"""Forever's own quests recorded in game: import and conversion to route quests."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "catalog"))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from import_recorded_quests import merge_records  # noqa: E402
from route_forever import to_quest  # noqa: E402

BOXES = {"The Barrens": (0.0, 0.0, 1000.0, 1000.0, 1)}
ROW = {"id": 97253, "title": "Parts and Pieces", "level": 15, "xp": 1450,
       "giver": {"name": "Giver", "zone": "The Barrens", "x": 40, "y": 60},
       "turnIn": {"name": "Ender", "zone": "The Barrens", "x": 40, "y": 60},
       "objectives": [{"text": "8 Gear Parts", "kind": "item", "count": 8, "spots": [["The Barrens", 50, 60], ["The Barrens", 60, 60]]}]}


class ToQuestTest(unittest.TestCase):
    def test_a_recorded_quest_becomes_a_route_quest(self):
        q = to_quest(ROW, BOXES)
        self.assertEqual((q.id, q.title, q.xp, q.start_name, q.end_name), (97253, "Parts and Pieces", 1450, "Giver", "Ender"))
        g = q.goals[0]
        self.assertEqual((g.kind, g.count, g.guessed), ("collect", 8, False))
        self.assertAlmostEqual(g.point[2], 1000 - 0.55 * 1000)  # middle of the spots (x 50 and 60 -> 55%)

    def test_no_spots_means_a_guessed_place(self):
        row = dict(ROW, objectives=[{"text": "Talk", "kind": "event", "count": 1, "spots": []}])
        self.assertTrue(to_quest(row, BOXES).goals[0].guessed)

    def test_not_handed_in_yet_is_left_out(self):
        self.assertIsNone(to_quest(dict(ROW, turnIn={}), BOXES))


class MergeRecordsTest(unittest.TestCase):
    def test_keeps_the_most_complete_record(self):
        partial = dict(ROW, turnIn={})
        self.assertEqual(merge_records([partial], [ROW]), [ROW])
        self.assertEqual(merge_records([ROW], [partial]), [ROW])

    def test_sorted_by_id(self):
        self.assertEqual([r["id"] for r in merge_records([dict(ROW, id=9)], [dict(ROW, id=3)])], [3, 9])


if __name__ == "__main__":
    unittest.main()


class RestedXPForeverTest(unittest.TestCase):
    """Forever's own quests placed with RestedXP's Forever guides (CC BY-NC-SA 4.0)."""

    def test_world_places_and_horde_only(self):
        import json
        import tempfile
        from route_forever import load_rxp
        rows = {"quests": [
            {"id": 97001, "title": "Horde one", "level": 24, "side": "H", "giver": {"world": [1, -600.0, -4250.0], "name": "Gornek"},
             "turnIn": {"world": [1, -600.0, -4250.0], "name": "Gornek"},
             "objectives": [{"text": "Boar", "kind": "monster", "count": 1, "spots": [[1, -500.0, -4200.0]]}]},
            {"id": 97002, "title": "Alliance one", "level": 24, "side": "A", "giver": {"world": [0, 1, 1]}, "turnIn": {"world": [0, 1, 1]}},
            {"id": 97003, "title": "Dungeon part", "level": 0, "side": "H", "giver": {"world": [1, 1, 1]}, "turnIn": {"world": [1, 1, 1]}},
        ]}
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "f.json"
            p.write_text(json.dumps(rows), encoding="utf-8")
            qs = load_rxp(p, {}, (), {25: 2000})
        self.assertEqual([q.id for q in qs], [97001])
        q = qs[0]
        self.assertEqual((q.level, q.xp, q.start, q.start_name), (25, 2000, (1, -600.0, -4250.0), "Gornek"))
        self.assertEqual(q.goals[0].point, (1, -500.0, -4200.0))
        self.assertTrue(q.races & 2)


class ExtractorRulesTest(unittest.TestCase):
    def test_step_side_and_part_level(self):
        from extract_rxp_forever import part_level, step_side, world
        self.assertEqual(step_side("step << Orc Warrior", "both"), "H")
        self.assertEqual(step_side("step << Human", "both"), "A")
        self.assertEqual(step_side("step", "H"), "H")
        self.assertEqual(part_level("#name 22-24 Hillsbrad\n"), 22)
        self.assertEqual(part_level("#name 101 Ragefire Chasm\n"), 0)
        self.assertEqual(world("1", "-4251.46", "-607.35"), [1, -607.4, -4251.5])  # <world y>,<world x> -> (x, y)
