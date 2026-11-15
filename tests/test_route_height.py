import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "catalog"))
from route_height import Heights  # noqa: E402

# The Crossroads (user, 2026-11-14): Darsok Swiftdagger on top of the tower at z 128, the ground around at about 96.
SPAWNS = [(1, 0.0, 0.0, 128.0)] + [(1, 5.0 * k, 3.0, 96.0 + (k % 3)) for k in range(1, 8)] + [(1, 2.0, 2.0, 127.9)]


class HeightTest(unittest.TestCase):
    def test_an_npc_on_a_tower_is_high_above_the_ground(self):
        self.assertEqual(Heights(SPAWNS).lift((1, 0.0, 0.0)), 32)

    def test_an_npc_on_the_ground_has_no_lift(self):
        self.assertEqual(Heights(SPAWNS).lift((1, 15.0, 3.0)), 0)

    def test_below_the_ground_is_negative(self):
        spawns = [(0, 0.0, 0.0, 40.0)] + [(0, 6.0 * k, 0.0, 60.0) for k in range(1, 6)]
        self.assertEqual(Heights(spawns).lift((0, 0.0, 0.0)), -20)

    def test_unknown_or_alone_is_zero(self):
        h = Heights(SPAWNS)
        self.assertEqual(h.lift((1, 900.0, 900.0)), 0)
        self.assertEqual(h.lift(None), 0)


if __name__ == "__main__":
    unittest.main()
