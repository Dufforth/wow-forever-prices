import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "catalog"))
from route_model import Goal, Quest  # noqa: E402
from route_zones import hinted_where, quest_zone_hints  # noqa: E402

# Two zone maps that overlap: West covers x 0-1000, East x 600-2000 (world yards, map 1).
BOXES = {"West": (0.0, 0.0, 1000.0, 1000.0, 1), "East": (600.0, 0.0, 2000.0, 1000.0, 1)}


def plain_where(point):
    return ("East", 50.0, 50.0) if point and point[1] >= 600 else ("West", 50.0, 50.0)


class QuestZoneTest(unittest.TestCase):
    """A quest's objective in the overlap of two zone maps belongs to the quest's own zone (user, 2026-11-14: Harpy
    Raiders, a Barrens quest, was put on the Stonetalon map and the guide sent them flying to Stonetalon)."""

    def quest(self, point, loop=()):
        return Quest(id=867, title="Harpy Raiders", level=15, min_level=12, start=(1, 100.0, 100.0), start_name="Darsok",
                     end=(1, 100.0, 100.0), end_name="Darsok", goals=[Goal("collect", "Witchwing Talon", point, loop=list(loop))])

    def test_a_spot_in_the_overlap_takes_the_quests_zone(self):
        q = self.quest((1, 800.0, 400.0), loop=[(1, 850.0, 450.0)])
        where = hinted_where(plain_where, BOXES, quest_zone_hints([q], {867: "West"}))
        zone, x, y = where((1, 800.0, 400.0))
        self.assertEqual(zone, "West")
        self.assertAlmostEqual(x, 60.0)  # (1000 - 400) / 1000
        self.assertAlmostEqual(y, 20.0)  # (1000 - 800) / 1000
        self.assertEqual(where((1, 850.0, 450.0))[0], "West")  # its loop spots too

    def test_a_spot_outside_the_quests_zone_keeps_its_own(self):
        q = self.quest((1, 1500.0, 400.0))
        where = hinted_where(plain_where, BOXES, quest_zone_hints([q], {867: "West"}))
        self.assertEqual(where((1, 1500.0, 400.0))[0], "East")

    def test_other_points_are_untouched(self):
        where = hinted_where(plain_where, BOXES, {})
        self.assertEqual(where((1, 800.0, 400.0))[0], "East")
        self.assertIsNone(hinted_where(lambda p: None, BOXES, {})(None))


if __name__ == "__main__":
    unittest.main()
