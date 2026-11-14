"""Class quests inserted where the route passes their giver (catalog/route_class.py)."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "catalog"))
from route_class import insert_class_quests  # noqa: E402
from route_model import Goal, Quest  # noqa: E402


def where(p):
    return ("Durotar", p[1] / 100, p[2] / 100) if p else None


def quest(qid, start, classes=0, min_level=1, prev=0, goal=None):
    goals = [Goal("kill", "Boar", goal or start, 3, 5)]
    return Quest(qid, f"Q{qid}", 5, min_level, start, "Trainer", start, "Trainer", goals, classes=classes, prev=prev)


class InsertClassQuestsTest(unittest.TestCase):
    def setUp(self):
        self.near = quest(1, (1, 0, 0))
        self.route = [["accept", 1, "Durotar", 0, 0, 5, "", 0, None], ["turnin", 1, "Durotar", 0, 0, 6, "", 0, None]]

    def test_inserted_after_the_step_near_the_giver(self):
        warrior = quest(50, (1, 100, 0), classes=1)
        out = insert_class_quests(self.route, [self.near, warrior], where, 2)
        self.assertEqual([s[:2] for s in out][:4], [["accept", 1], ["accept", 50], ["do", 50], ["turnin", 50]])

    def test_far_givers_are_left_as_errands(self):
        far = quest(51, (1, 9000, 0), classes=1)
        self.assertEqual(len(insert_class_quests(self.route, [self.near, far], where, 2)), 2)

    def test_follow_up_after_its_earlier_quest(self):
        a, b = quest(50, (1, 100, 0), classes=1), quest(52, (1, 100, 0), classes=1, prev=50)
        ids = [s[1] for s in insert_class_quests(self.route, [self.near, a, b], where, 2)]
        self.assertLess(max(i for i, q in enumerate(ids) if q == 50), ids.index(52))

    def test_other_race_quests_skipped(self):
        tauren = quest(53, (1, 100, 0), classes=1)
        tauren.races = 32
        self.assertEqual(len(insert_class_quests(self.route, [self.near, tauren], where, 2)), 2)


if __name__ == "__main__":
    unittest.main()
