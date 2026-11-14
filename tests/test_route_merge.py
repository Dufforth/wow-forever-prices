"""One stop per NPC visit (catalog/route_merge.py)."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "catalog"))
from route_merge import merge_talks, stops  # noqa: E402
from route_model import Quest  # noqa: E402


def quest(qid, giver="Gornek", ender="Gornek", prev=0, min_level=1, **kw):
    return Quest(qid, f"Q{qid}", 5, min_level, (1, 0, 0), giver, (1, 0, 0), ender, prev=prev, **kw)


def step(kind, qid, zone="Durotar", level=5):
    return [kind, qid, zone, 40, 60, level, "", 0]


class MergeTalksTest(unittest.TestCase):
    def test_pick_up_moves_to_the_earlier_visit(self):
        quests = [quest(1), quest(2), quest(3, giver="Other", ender="Other")]
        route = [step("turnin", 1), step("accept", 3), step("do", 3), step("accept", 2)]
        out = merge_talks(route, quests)
        self.assertEqual([s[:2] for s in out], [["turnin", 1], ["accept", 2], ["accept", 3], ["do", 3]])
        self.assertLess(stops(out, quests), stops(route, quests))

    def test_never_before_its_earlier_quest(self):
        quests = [quest(1), quest(2, prev=1), quest(3, giver="Other")]
        route = [step("accept", 1), step("accept", 3), step("turnin", 1), step("do", 3), step("accept", 2)]
        out = merge_talks(route, quests)
        self.assertLess([s[:2] for s in out].index(["turnin", 1]), [s[:2] for s in out].index(["accept", 2]))

    def test_not_across_a_zone_change(self):
        quests = [quest(1), quest(2), quest(3, giver="Other")]
        route = [step("turnin", 1), step("accept", 3, zone="The Barrens"), step("accept", 2)]
        self.assertEqual(merge_talks(route, quests), route)

    def test_not_below_its_level(self):
        quests = [quest(1), quest(2, min_level=8), quest(3, giver="Other")]
        route = [step("turnin", 1, level=5), step("accept", 3), step("accept", 2, level=8)]
        self.assertEqual([s[1] for s in merge_talks(route, quests)], [1, 3, 2])

    def test_timed_quests_stay(self):
        quests = [quest(1), quest(2, timed=True), quest(3, giver="Other")]
        route = [step("turnin", 1), step("accept", 3), step("accept", 2)]
        self.assertEqual([s[1] for s in merge_talks(route, quests)], [1, 3, 2])


if __name__ == "__main__":
    unittest.main()
