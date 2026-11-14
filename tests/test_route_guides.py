"""Questline guides (catalog/route_guides.py): attunement chains from the quest data and the hand-made
Cozy Sleeping Bag guide. User (2026-11-13): 'add other guides so we can choose important questlines like
cozy sleeping bag, or attunement quest guides'."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "catalog"))
from route_guides import COZY_SLEEPING_BAG, chain, chain_steps  # noqa: E402
from route_model import Goal, Quest  # noqa: E402


def where(point):
    return ("Badlands", point[1] / 10, point[2] / 10) if point and point[0] == 0 else None


def quest(qid, prev=0, nxt=0, goals=()):
    return Quest(id=qid, title=f"Q{qid}", level=60, min_level=55, start=(0, 100, 100), start_name="Giver",
                 end=(0, 200, 200), end_name="Ender", goals=list(goals), prev=prev, next_in_chain=nxt)


class ChainTest(unittest.TestCase):
    def test_follows_next_quest_then_quests_that_need_it(self):
        quests = {1: quest(1, nxt=2), 2: quest(2, prev=1), 3: quest(3, prev=2), 9: quest(9)}
        self.assertEqual([q.id for q in chain(quests, 1)], [1, 2, 3])

    def test_an_explicit_order_for_quests_done_side_by_side(self):
        quests = {1: quest(1), 2: quest(2, prev=1), 3: quest(3, prev=1), 4: quest(4, prev=3)}
        self.assertEqual([q.id for q in chain(quests, [1, 2, 3, 4, 99])], [1, 2, 3, 4], "a list is followed as given; missing ids skipped")

    def test_an_objective_with_no_place(self):
        q = quest(1, goals=[Goal("kill", "Somebody", None, 1)])
        self.assertEqual(chain_steps([q], where)[1][2:5], ["Place not in the data", None, None])

    def test_stops_at_a_missing_quest_and_never_loops(self):
        quests = {1: quest(1, nxt=2), 2: quest(2, nxt=1)}
        self.assertEqual([q.id for q in chain(quests, 1)], [1, 2])

    def test_steps_pick_up_do_turn_in(self):
        q = quest(1, goals=[Goal("kill", "Dragon", (0, 300, 300), 1)])
        steps = chain_steps([q], where)
        self.assertEqual([s[0] for s in steps], ["accept", "do", "turnin"])
        self.assertEqual(steps[0][:6], ["accept", 1, "Badlands", 10.0, 10.0, 55])
        self.assertEqual(steps[1][7], 1, "the objective index")

    def test_a_place_in_a_dungeon_is_unknown_not_an_error(self):
        q = quest(1, goals=[Goal("kill", "Boss", (229, 1, 1), 1)])
        self.assertEqual(chain_steps([q], where)[1][2:5], ["Inside the dungeon", None, None])


class CozySleepingBagTest(unittest.TestCase):
    def test_the_horde_chain_in_order(self):
        steps, quests = COZY_SLEEPING_BAG["steps"], COZY_SLEEPING_BAG["quests"]
        self.assertEqual(steps[0][2], "The Barrens")
        self.assertEqual([s[1] for s in steps if s[0] == "accept"], [79007, 79192, 79980, 79974, 79975, 79976])
        for s in steps:
            self.assertIn(s[1], quests, "every step's quest is described")
        self.assertIn("Cozy Sleeping Bag", COZY_SLEEPING_BAG["note"])

    def test_places_without_published_coordinates_have_none(self):
        stonetalon = [s for s in COZY_SLEEPING_BAG["steps"] if s[2] == "Stonetalon Mountains"]
        self.assertTrue(stonetalon and all(s[3] is None for s in stonetalon), "no guessed coordinates")


if __name__ == "__main__":
    unittest.main()
