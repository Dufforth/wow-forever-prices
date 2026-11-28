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
step
#optional
.goto 1411/1,20.0,20.0
.turnin 3
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
        # no Tauren step, no dungeon step; RestedXP's #optional steps are kept like any other
        self.assertEqual([e[:3] for e in found], [["accept", 1, 0], ["complete", 1, 2], ["turnin", 3, 0]])
        self.assertEqual(found[0][3:], [1, 200.0, 100.0, 1])
        with_dungeons, _ = events(self.known[(MAIN, "1-6 Durotar")][1], 1, ME, dungeons=True)
        self.assertIn(["accept", 8, 0], [e[:3] for e in with_dungeons])
        later, level = events(self.known[(MAIN, "6-10 Durotar")][1], 6, ME)
        self.assertEqual(level, 7)
        self.assertEqual([e[0] for e in later], ["turnin", "turnin", "fly", "home", "home", "accept"])


KINDS = {"accept": "accept", "complete": "do", "turnin": "turnin"}


def same_steps(rows, events):
    """(kind, quest, objective) of each row against each RestedXP event, one to one."""
    return [(r[0], r[1], r[7]) for r in rows] == [expected(e) for e in events]


def expected(e):
    """A guide event as our row's (kind, quest, objective); ".turnin 788,2" names a reward: never picked for you."""
    return (KINDS.get(e[0], e[0]), e[1], e[2] if e[0] == "complete" else 0)


class RowsTest(unittest.TestCase):
    """Every route follows RestedXP exactly (user, 2026-11-26): one row per guide event, in its order, nothing added,
    nothing left out."""

    def setUp(self):
        known = parts([GUIDES])
        self.ev = []
        for name, lv in (("1-6 Durotar", 1), ("6-10 Durotar", 6)):
            self.ev += events(known[(MAIN, name)][1], lv, ME)[0]
        self.nowhere = quest(5)
        self.nowhere.start = None                         # started by a looted item; the guide step has no point
        self.stubs = []

        def stub(qid, level):
            q = Quest(qid, f"Quest {qid}", level, 1, None, "", None, "", [])
            self.stubs.append(qid)
            return q
        self.rows, self.stats = rows_from_events(self.ev, {1: quest(1), 3: quest(3), 5: self.nowhere}, where, stub)

    def test_one_row_per_event_in_order(self):
        self.assertTrue(same_steps(self.rows, self.ev), [(r[0], r[1], r[7]) for r in self.rows])

    def test_unknown_quest_kept_as_text(self):
        self.assertEqual(self.stubs, [77])               # quest 77 isn't in our data: a stub, the step stays
        self.assertEqual(self.stats["unknown"], 1)
        row = [r for r in self.rows if r[1] == 77][0]
        self.assertEqual(row[6], 'Turn in "Quest 77"')

    def test_no_point_no_waypoint(self):
        accept5 = [r for r in self.rows if r[0] == "accept" and r[1] == 5][0]
        self.assertEqual(accept5[3:5], [None, None])     # no guide point: no waypoint, not our data's place
        self.assertEqual(accept5[2], "Durotar")          # zone carried from the step before
        self.assertEqual(self.stats["no_place"], 1)

    def test_places_and_texts(self):
        self.assertEqual(self.rows[0][3:5], [20.0, 10.0])  # RestedXP's own point (world 200, 100), not our data's
        self.assertEqual(self.rows[0][6], 'Accept "Q1" from Giver')
        fly = [r for r in self.rows if r[0] == "fly"][0]
        self.assertEqual(fly[8], ["Durotar", 90.0, 90.0])  # lands where the next point is
        self.assertEqual(sum(1 for r in self.rows if r[0] == "home"), 2)  # said twice: twice, like the guide
        self.assertEqual(self.rows[-1][5], 7)            # level after ".xp 7"


class BuiltRoutesFollowRestedXP(unittest.TestCase):
    """The built routes (catalog/route.json) against the parsed RestedXP steps (catalog/rxp_routes.json): one step
    record per RestedXP step, and each step's quest lines as rows, in order (user, 2026-11-27: "at 100%")."""

    QUEST = {"accept": "accept", "turnin": "turnin", "complete": "do"}

    def test_every_route_matches_its_steps(self):
        import json
        root = Path(__file__).resolve().parents[1] / "catalog"
        chains = json.loads((root / "rxp_routes.json").read_text(encoding="utf-8"))["routes"]
        built = json.loads((root / "route.json").read_text(encoding="utf-8"))
        names = {f"{start}{' (dungeons)' if kind == 'dungeons' else ''}": c for start, cs in chains.items() for kind, c in cs.items()}
        self.assertEqual(sorted(n for n in built["routes"] if not built["routes"][n].get("guide")), sorted(names))
        for name, c in names.items():
            route = built["routes"][name]
            rows, recs, steps = route["steps"], route["rx"], c["steps"]
            self.assertEqual(len(recs), len(steps), name)
            self.assertEqual(route["parts"], c["parts"], name)
            by_step = {}
            for r in rows:
                by_step.setdefault(r[10], []).append((r[0], r[1], r[7] if r[0] == "do" else 0))
            for n, (rec, st) in enumerate(zip(recs, steps), 1):
                self.assertEqual(rec["p"], st["p"], f"{name} step {n}")
                want = [(self.QUEST[e[0]], abs(int(e[1][0])), int(e[1][1]) if e[0] == "complete" and len(e[1]) > 1 else 0)
                        for e in st["e"] if e[0] in self.QUEST]
                got = [x for x in by_step.get(n, []) if x[0] in ("accept", "turnin", "do")]
                self.assertEqual(got, want, f"{name} step {n}")
                if got:
                    self.assertTrue(rec["a"] <= rec["b"] and all(rows[k - 1][10] == n for k in range(rec["a"], rec["b"] + 1)), f"{name} step {n}")
            for r in rows:
                self.assertIn(str(r[1]), built["quests"] if r[1] else {"0": 0}, f"{name}: quest {r[1]} has no data")
            self.assertTrue(built.get("spirit"), "Spirit Healers")


if __name__ == "__main__":
    unittest.main()
