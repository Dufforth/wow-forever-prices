"""Routes from RestedXP's guide chain: catalog/rxp_chain.py (guide -> events) and catalog/route_from_rxp.py (events -> rows)."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "catalog"))
from route_from_rxp import rows_from_events  # noqa: E402
from route_model import Goal, Quest  # noqa: E402
from rxp_chain import MAIN, chain, events, parts  # noqa: E402

GUIDES = """
RXPGuides.RegisterGuide([[
#group RestedXP Forever Guide (H)
#name 1-6 Durotar
#next 6-10 Durotar
step
.goto 1411/1,100.0,200.0
.accept 1 >> Accept one
step << Tauren
.goto 1411/1,500.0,500.0
.accept 9
step
.goto 1411/1,150.0,250.0
.complete 1,2
step
.dungeon RFC
.goto 1411/1,10.0,10.0
.accept 8
]])
RXPGuides.RegisterGuide([[
#group RestedXP Forever Guide (H)
#name 6-10 Durotar
#next 10-12 Tirisfal << Undead
#next 10-12 Durotar
step
.xp 7
step
.goto 1411/1,100.0,200.0
.turnin 1
.turnin 77
step
.fly Orgrimmar
step
.goto 1411/1,900.0,900.0
.home
step
.goto 1411/1,900.0,900.0
.home
step
.accept 5
]])
RXPGuides.RegisterGuide([[
#group RestedXP Forever Guide (H)
#name 10-12 Durotar
step
.goto 1411/1,1.0,1.0
.accept 2
]])
"""
ME = {"Horde", "Orc", "Warrior"}


def where(point):
    return ("Durotar", point[1] / 10, point[2] / 10) if point else None


def quest(qid, goals=2):
    return Quest(qid, f"Q{qid}", 5, 1, (1, 200.0, 100.0), "Giver", (1, 200.0, 100.0), "Taker",
                 [Goal("kill", f"Boar{i}", (1, 300.0 + i, 300.0), 4, 5) for i in range(goals)], 500)


class ChainTest(unittest.TestCase):
    def setUp(self):
        self.known = parts([GUIDES])

    def test_follows_next_for_me(self):
        self.assertEqual(chain(self.known, MAIN, "1-6 Durotar", ME), ["1-6 Durotar", "6-10 Durotar", "10-12 Durotar"])

    def test_events(self):
        found, level = events(self.known[(MAIN, "1-6 Durotar")][1], 1, ME)
        self.assertEqual([e[:3] for e in found], [["accept", 1, 0], ["complete", 1, 2]])  # no Tauren step, no dungeon step
        self.assertEqual(found[0][3:], [1, 200.0, 100.0, 1])
        with_dungeons, _ = events(self.known[(MAIN, "1-6 Durotar")][1], 1, ME, dungeons=True)
        self.assertIn(["accept", 8, 0], [e[:3] for e in with_dungeons])
        later, level = events(self.known[(MAIN, "6-10 Durotar")][1], 6, ME)
        self.assertEqual(level, 7)
        self.assertEqual([e[0] for e in later], ["turnin", "turnin", "fly", "home", "home", "accept"])


class RowsTest(unittest.TestCase):
    def test_rows(self):
        known = parts([GUIDES])
        ev = []
        for name, lv in (("1-6 Durotar", 1), ("6-10 Durotar", 6)):
            ev += events(known[(MAIN, name)][1], lv, ME)[0]
        nowhere = quest(5)
        nowhere.start = None                             # started by a looted item; the guide step has no point
        rows, stats = rows_from_events(ev, {1: quest(1), 5: nowhere}, where)
        self.assertEqual(stats["no_place"], 1)
        self.assertNotIn(5, [r[1] for r in rows])
        self.assertEqual(sum(1 for r in rows if r[0] == "home"), 1)  # said twice in a row, kept once
        kinds = [(r[0], r[1], r[7]) for r in rows]
        # objective 1 was never named by the guide: no step of its own (gathered along the way), only counted
        self.assertEqual(kinds[:3], [("accept", 1, 0), ("do", 1, 2), ("turnin", 1, 0)])
        self.assertEqual(stats["unnamed_objectives"], 1)
        self.assertEqual(rows[0][3:5], [20.0, 10.0])     # RestedXP's own point (world 200, 100), not our data's
        self.assertEqual(stats["unknown"], 1)            # quest 77 isn't in our data
        self.assertEqual(rows[0][6], 'Accept "Q1" from Giver')
        fly = [r for r in rows if r[0] == "fly"][0]
        self.assertEqual(fly[8], ["Durotar", 90.0, 90.0])  # lands where the next point is
        self.assertEqual(rows[-1][0], "home")
        self.assertEqual(rows[-1][5], 7)                 # level after ".xp 7"


if __name__ == "__main__":
    unittest.main()
