"""The route scorecard (catalog/route_score.py)."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "catalog"))
from route_model import Goal, Quest  # noqa: E402
from route_score import score, world  # noqa: E402

# A 1000 x 1000 yard zone on map 1.
BOXES = {"Durotar": (0.0, 0.0, 1000.0, 1000.0, 1)}


def quest(qid, xp=1000, kills=0):
    goals = [Goal("kill", "Boar", (1, 0, 0), kills, 5)] if kills else []
    return Quest(qid, "Q", 5, 1, (1, 0, 0), "A", (1, 0, 0), "A", goals, xp)


class ScoreTest(unittest.TestCase):
    def test_world_point_from_zone_percent(self):
        self.assertEqual(world(BOXES, "Durotar", 0, 0), (1, 1000.0, 1000.0))
        self.assertEqual(world(BOXES, "Durotar", 100, 100), (1, 0.0, 0.0))

    def test_running_talks_and_kills(self):
        quests = {1: quest(1, kills=3)}
        steps = [["accept", 1, "Durotar", 0, 0, 5, ""], ["turnin", 1, "Durotar", 0, 70, 5, ""]]
        s = score(steps, quests, BOXES, target=6)
        self.assertEqual(s["quests"], 1)
        self.assertAlmostEqual(s["run_km"], round(700 / 1093.6, 1))
        self.assertEqual(s["xp"], 1000 + 3 * 70)

    def test_a_flight_is_faster_than_running(self):
        quests = {}
        run = [["accept", 0, "Durotar", 0, 0, 5, ""], ["accept", 0, "Durotar", 100, 100, 5, ""]]
        fly = [["accept", 0, "Durotar", 0, 0, 5, ""], ["fly", 0, "Durotar", 0, 0, 5, "", 0, ["Durotar", 100, 100]],
               ["accept", 0, "Durotar", 100, 100, 5, ""]]
        big = {"Durotar": (0.0, 0.0, 20000.0, 20000.0, 1)}
        self.assertLess(score(fly, quests, big, 6)["hours"], score(run, quests, big, 6)["hours"])
        self.assertEqual(score(fly, quests, big, 6)["flights"], 1)

    def test_shortfall_is_ground(self):
        self.assertGreater(score([], {}, BOXES, target=3)["grind_hours"], 0)


if __name__ == "__main__":
    unittest.main()
