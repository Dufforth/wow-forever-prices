"""RestedXP's Forever leveling guide as scored steps (catalog/rxp_route.py), for the 1-60 scorecard."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "catalog"))
from route_model import Goal, Quest  # noqa: E402
from route_score import score  # noqa: E402
from rxp_route import BANDS, band_table, for_me, parse_guide  # noqa: E402

ME = {"Horde", "Orc", "Warrior"}

GUIDE = """
RXPGuides.RegisterGuide([[
#group RestedXP Forever Guide (H)
#name 22-24 Hillsbrad
#next 24-26 Southern Barrens/Stonetalon
step
.goto 1420/0,100.0,200.0
.turnin 440 >> Turn in The Engraved Ring
.accept 441 >> Accept Raleigh
step << Mage
.goto 1420/0,900.0,900.0
.train 3563 >> Train Teleport
step
#optional
.goto 1420/0,800.0,800.0
.accept 441 >> Accept Raleigh
step
.goto 1420/0,100.0,500.0
.complete 441,1
step
.goto 1420/0,700.0,700.0
.accept 996 >> Accept a dungeon quest
.dungeon WC
step
.goto 1420/0,100.0,500.0
.accept 995 >> Accept the no-dungeon version
.dungeon !WC
step
.xp 23 >> Grind to 23
step
#completewith next
.goto 1420/0,100.0,500.0
.turnin 440 >> Turn in The Engraved Ring again (a repeat of the first step)
step
.fly Orgrimmar >> Fly to Orgrimmar
step
.goto 1411/1,10.0,20.0
.turnin 441 >> Turn in Raleigh
]])
RXPGuides.RegisterGuide([[
#group RestedXP Forever Guide (A) << Alliance
#group RestedXP Forever Guide (H) << Horde
#name 9-13 Zephras Isle
step
.goto 1420/0,7.0,7.0
.accept 997
]])
RXPGuides.RegisterGuide([[
#group RestedXP Forever Dungeon Guide (H)
#name 22-24 Hillsbrad
step
.goto 1420/0,5.0,5.0
.accept 999
]])
RXPGuides.RegisterGuide([[
#group RestedXP Forever Guide (A)
#name 21-23 Ashenvale
step
.goto 1440/1,5.0,5.0
.accept 998
]])
"""


class ForMeTest(unittest.TestCase):
    def test_tags(self):
        self.assertTrue(for_me("", ME))
        self.assertTrue(for_me("Horde", ME))
        self.assertTrue(for_me("Warrior", ME))
        self.assertTrue(for_me("Orc Warrior", ME))
        self.assertFalse(for_me("Mage", ME))
        self.assertFalse(for_me("Horde Shaman", ME))
        self.assertFalse(for_me("!Warrior", ME))
        self.assertTrue(for_me("!Hunter", ME))
        self.assertTrue(for_me("Mage/Warrior", ME))
        self.assertFalse(for_me("Alliance/!Horde", ME))
        self.assertFalse(for_me("Skyborne", ME))       # Forever's Zephras Isle start, not an orc
        self.assertTrue(for_me("!Skyborne", ME))
        self.assertFalse(for_me("Tauren", ME))


class ParseTest(unittest.TestCase):
    def setUp(self):
        self.steps = parse_guide(GUIDE, "RestedXP Forever Guide (H)", ME)

    def test_only_the_main_horde_guide_and_my_steps(self):
        qids = {s[1] for s in self.steps}
        self.assertNotIn(999, qids)   # dungeon guide
        self.assertNotIn(998, qids)   # Alliance guide
        self.assertNotIn(997, qids)   # Zephras Isle start (Skyborne only, levels 1-13)
        self.assertNotIn(996, qids)   # ".dungeon WC": only with that dungeon picked
        self.assertIn(995, qids)      # ".dungeon !WC": the dungeons-off step
        self.assertFalse(any(s[3] == 900.0 for s in self.steps if isinstance(s[2], int)))  # Mage step
        self.assertFalse(any(s[3] == 800.0 for s in self.steps if isinstance(s[2], int)))  # #optional step

    def test_points_levels_and_kinds(self):
        kinds = [(s[0], s[1]) for s in self.steps]
        self.assertEqual(kinds[:3], [("turnin", 440), ("accept", 441), ("complete", 441)])
        self.assertEqual(self.steps[0][2:6], [0, 200.0, 100.0, 22])      # continent, world x, world y (swapped), level
        self.assertEqual(self.steps[-1][5], 23)                          # after ".xp 23"
        fly = [s for s in self.steps if s[0] == "fly"][0]
        self.assertEqual(fly[8], [1, 20.0, 10.0])                       # lands where the next step is
        self.assertEqual(self.steps[-1][:2], ["turnin", 441])
        self.assertEqual(sum(1 for s in self.steps if s[:2] == ["turnin", 440]), 1)  # repeats count once


def quest(qid, xp):
    return Quest(qid, "Q", 30, 25, (0, 0, 0), "A", (0, 0, 0), "A", [Goal("kill", "Boar", (0, 0, 0), 2, 30)], xp)


class ScoreWorldPointsTest(unittest.TestCase):
    def test_world_point_steps_are_scored(self):
        steps = [["accept", 1, 0, 0.0, 0.0, 30, ""], ["turnin", 1, 0, 0.0, 700.0, 30, ""]]
        s = score(steps, {1: quest(1, 1000)}, {}, target=31, start=30)
        self.assertEqual(s["quests"], 1)
        self.assertAlmostEqual(s["run_km"], round(700 / 1093.6, 1))

    def test_band_table(self):
        ours = [["turnin", 1, 0, 0.0, 0.0, 25, ""], ["turnin", 2, 0, 0.0, 100.0, 45, ""]]
        theirs = [["turnin", 1, 0, 0.0, 0.0, 26, ""]]
        rows = band_table(ours, theirs, {1: quest(1, 500), 2: quest(2, 500)}, {})
        self.assertEqual([r["band"] for r in rows], [f"{a}-{b}" for a, b in BANDS] + ["22-60"])
        first = rows[0]
        self.assertEqual(first["ours"]["quests"], 1)
        self.assertEqual(first["rxp"]["quests"], 1)
        self.assertIn("faster", first)
        self.assertEqual(first["need_xp"], sum(__import__("route_score").XP_TABLE[21:29]))
        # paced hours: the band's experience at each route's own pace
        self.assertGreater(first["ours"]["xp_per_hour"], 0)
        self.assertAlmostEqual(first["ours"]["paced_hours"], first["need_xp"] / first["ours"]["xp_per_hour"], delta=0.05)


if __name__ == "__main__":
    unittest.main()
