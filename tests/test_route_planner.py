"""The leveling route planner (catalog/route_planner.py), on a small made-up world.

Map 0, positions in yards. Zones: x < 1000 is "Start Vale", x >= 1000 is "Far Hills".
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "catalog"))
from route_model import Goal, Quest  # noqa: E402
from route_planner import (Eligibility, HubScorer, RoutePlanner, TravelModel, XpModel, ZonePlan)  # noqa: E402

ORC = 2


def where(point):
    m, x, y = point
    return ("Start Vale" if x < 1000 else "Far Hills"), round(x / 20, 1), round(y / 20, 1)


def quest(qid, level=1, start=(0, 0, 0), end=None, goals=(), **kw):
    return Quest(id=qid, title=f"Q{qid}", level=level, min_level=kw.pop("min_level", max(1, level - 3)), start=start,
                 start_name="Giver", end=end or start, end_name="Ender", goals=list(goals), xp=kw.pop("xp", 500), **kw)


def kill(point, count=5, mob_level=1, name="Boar"):
    return Goal(kind="kill", name=name, point=point, count=count, mob_level=mob_level)


def planner(quests, **kw):
    return RoutePlanner(quests, where=where, eligibility=Eligibility(), xp=XpModel(), travel=TravelModel(), scorer=HubScorer(), **kw)


def kinds(steps):
    return [(s.kind, s.quest) for s in steps]


class WorthTest(unittest.TestCase):
    """User (2026-11-13): the main guide is for fast leveling: skip quests with low experience and long walks."""

    def test_a_poor_quest_far_away_is_left_out(self):
        quests = [quest(1, goals=[kill((0, 100, 0), count=3)], xp=800),
                  quest(2, goals=[kill((0, 3000, 0), count=10)], xp=50)]
        steps, _ = planner(quests).plan(start=(0, 0, 0), race_bit=ORC, max_level=2)
        self.assertIn(("accept", 1), kinds(steps))
        self.assertNotIn(("accept", 2), kinds(steps))

    def test_a_poor_quest_that_opens_a_chain_is_kept(self):
        quests = [quest(1, goals=[kill((0, 100, 0), count=3)], xp=800),
                  quest(2, goals=[kill((0, 3000, 0), count=10)], xp=50, next_in_chain=3),
                  quest(3, start=(0, 0, 0), xp=900, prev=2)]
        steps, _ = planner(quests).plan(start=(0, 0, 0), race_bit=ORC, max_level=3)
        self.assertIn(("accept", 2), kinds(steps))


class DroppedItemQuestTest(unittest.TestCase):
    """User (2026-11-13): get the item while doing quests there, start its quest, do it."""

    def test_started_while_working_near_the_drop(self):
        boars = (0, 300, 0)
        quests = [quest(1, goals=[kill(boars)], xp=800),
                  quest(2, start=boars, end=(0, 0, 0), start_item=900, start_drop=("Old Letter", "Boar", 25.0), xp=700)]
        steps, _ = planner(quests).plan(start=(0, 0, 0), race_bit=ORC, max_level=2)
        self.assertIn(("accept", 2), kinds(steps))
        accept = next(s for s in steps if (s.kind, s.quest) == ("accept", 2))
        self.assertIn("Loot Old Letter from Boar", accept.text)
        self.assertLess(kinds(steps).index(("do", 1)), kinds(steps).index(("accept", 2)) + 2, "while at the boars")

    def test_a_drop_alone_never_pulls_the_route_away(self):
        quests = [quest(1, xp=300), quest(2, start=(0, 900, 0), start_item=900, start_drop=("Old Letter", "Boar", 25.0), xp=5000)]
        steps, _ = planner(quests).plan(start=(0, 0, 0), race_bit=ORC, max_level=2)
        self.assertNotIn(("accept", 2), kinds(steps))


class XpModelTest(unittest.TestCase):
    def test_quests_give_full_experience_up_to_five_levels_below_you(self):
        xp = XpModel()
        self.assertEqual(xp.quest_xp(1000, quest_level=10, player_level=15), 1000)
        self.assertEqual(xp.quest_xp(1000, quest_level=10, player_level=16), 800)
        self.assertEqual(xp.quest_xp(1000, quest_level=10, player_level=25), 100)

    def test_kills_of_gray_monsters_give_nothing(self):
        xp = XpModel()
        self.assertGreater(xp.kill_xp(player_level=10, mob_level=10), 0)
        self.assertEqual(xp.kill_xp(player_level=20, mob_level=10), 0)

    def test_levels_up_and_keeps_the_rest(self):
        xp = XpModel()
        level, rest = xp.add(level=1, current=300, gained=200)  # level 1 needs 400
        self.assertEqual((level, rest), (2, 100))


class TravelModelTest(unittest.TestCase):
    def test_running_and_riding(self):
        t = TravelModel()
        self.assertAlmostEqual(t.seconds((0, 0, 0), (0, 70, 0), level=10), 10)
        self.assertLess(t.seconds((0, 0, 0), (0, 700, 0), level=40), t.seconds((0, 0, 0), (0, 700, 0), level=39))

    def test_another_continent_costs_a_ship_ride(self):
        self.assertGreaterEqual(TravelModel().seconds((0, 0, 0), (1, 0, 0), level=20), TravelModel.SHIP)


class EligibilityTest(unittest.TestCase):
    def setUp(self):
        self.e = Eligibility()

    def ok(self, q, level=5, done=(), active=(), race=ORC, groups=None):
        return self.e.available(q, level=level, done=set(done), active=set(active), race_bit=race, groups=groups or {})

    def test_level_window(self):
        self.assertTrue(self.ok(quest(1, level=7, min_level=5)))
        self.assertFalse(self.ok(quest(1, level=9, min_level=5)), "more than 3 levels above you")
        self.assertFalse(self.ok(quest(1, level=7, min_level=6)), "below the quest's minimum level")
        self.assertTrue(self.ok(quest(1, level=2), level=8), "green quests still give most of their experience")
        self.assertFalse(self.ok(quest(1, level=1), level=8), "more than 6 levels below you")

    def test_race_class_and_kinds_left_out_of_the_main_route(self):
        self.assertFalse(self.ok(quest(1, races=16)), "Undead only")
        self.assertTrue(self.ok(quest(1, races=2 | 128)))
        self.assertFalse(self.ok(quest(1, classes=1)), "class quests are offered separately")
        self.assertFalse(self.ok(quest(1, kind="dungeon")))
        self.assertFalse(self.ok(quest(1, level=5, kind="group"), level=6), "an elite quest at your level needs a group")
        self.assertTrue(self.ok(quest(1, level=5, kind="group"), level=8), "3 levels above it, it's soloable")
        self.assertFalse(self.ok(quest(1, start_item=5)), "item-started quests are offered separately")

    def test_chains_and_exclusive_groups(self):
        self.assertFalse(self.ok(quest(2, prev=1)))
        self.assertTrue(self.ok(quest(2, prev=1), done={1}))
        self.assertTrue(self.ok(quest(2, prev=-1), active={1}), "needs quest 1 in your log")
        self.assertFalse(self.ok(quest(3, exclusive=7), done={4}, groups={7: [3, 4]}), "one quest of the group")

    def test_quests_that_send_you_far_away_are_left_out(self):
        self.assertFalse(self.ok(quest(1, goals=[kill((0, 3500, 0))])), "an objective 3500 yards from the giver")
        self.assertFalse(self.ok(quest(1, goals=[kill((1, 0, 0))])), "an objective on another continent")
        self.assertTrue(self.ok(quest(1, end=(1, 0, 0))), "a delivery to another continent: done when the route goes there")
        self.assertTrue(self.ok(quest(1, goals=[kill((0, 2500, 0))])), "big zones: up to 3000 yards")
        self.assertTrue(self.ok(quest(1, end=(0, 9000, 0))), "a delivery far away on the same continent is fine")

    def test_done_or_active_quests_aren_t_taken_again(self):
        self.assertFalse(self.ok(quest(1), done={1}))
        self.assertFalse(self.ok(quest(1), active={1}))


class HubScorerTest(unittest.TestCase):
    def test_the_same_experience_closer_wins(self):
        s, t = HubScorer(), TravelModel()
        near = [quest(1, start=(0, 100, 0), goals=[kill((0, 150, 0))])]
        far = [quest(2, start=(0, 900, 0), goals=[kill((0, 950, 0))])]
        here = (0, 0, 0)
        self.assertGreater(s.value(near, here, (0, 100, 0), level=1, xp=XpModel(), travel=t),
                           s.value(far, here, (0, 900, 0), level=1, xp=XpModel(), travel=t))


class ZonePlanTest(unittest.TestCase):
    def test_zones_fit_their_level_band_and_cities_always_fit(self):
        plan = ZonePlan([(1, 9, ["Start Vale"]), (10, 20, ["Far Hills", "Mid Woods"])], cities={"Big City"})
        self.assertTrue(plan.allows("Start Vale", 5))
        self.assertFalse(plan.allows("Far Hills", 5))
        self.assertTrue(plan.allows("Far Hills", 12))
        self.assertTrue(plan.allows("Big City", 3))
        self.assertTrue(ZonePlan([]).allows("Anywhere", 30), "no plan: every zone fits")


class RoutePlannerTest(unittest.TestCase):
    def test_takes_every_quest_at_the_hub_then_does_the_nearest_objective_first(self):
        qs = [quest(1, goals=[kill((0, 300, 0))]), quest(2, goals=[kill((0, 100, 0))])]
        steps, _ = planner(qs).plan(start=(0, 0, 0), race_bit=ORC, max_level=2)
        self.assertEqual(kinds(steps)[:4], [("accept", 1), ("accept", 2), ("do", 2), ("do", 1)])

    def test_each_objective_step_says_which_objective_it_is(self):
        qs = [quest(1, goals=[kill((0, 300, 0), name="Wolf"), kill((0, 100, 0), name="Boar")])]
        steps, _ = planner(qs).plan(start=(0, 0, 0), race_bit=ORC, max_level=2)
        do = [(s.quest, s.goal) for s in steps if s.kind == "do"]
        self.assertEqual(do, [(1, 2), (1, 1)], "the boar (2nd objective) is nearer, then the wolf (1st)")

    def test_turns_finished_quests_in_together(self):
        qs = [quest(1, goals=[kill((0, 100, 0))]), quest(2, goals=[kill((0, 120, 0))])]
        steps, _ = planner(qs).plan(start=(0, 0, 0), race_bit=ORC, max_level=3)
        self.assertEqual([k for k in kinds(steps) if k[0] == "turnin"], [("turnin", 1), ("turnin", 2)])

    def test_takes_the_follow_up_right_away(self):
        qs = [quest(1, goals=[kill((0, 100, 0))]), quest(2, prev=1, goals=[kill((0, 200, 0))])]
        steps, _ = planner(qs).plan(start=(0, 0, 0), race_bit=ORC, max_level=3)
        k = kinds(steps)
        self.assertEqual(k[k.index(("turnin", 1)) + 1], ("accept", 2))

    def test_a_turn_in_on_the_way_comes_before_a_far_objective(self):
        qs = [quest(1, goals=[kill((0, 50, 0))], end=(0, 60, 0)), quest(2, goals=[kill((0, 900, 0))])]
        steps, _ = planner(qs).plan(start=(0, 0, 0), race_bit=ORC, max_level=3)
        k = kinds(steps)
        self.assertLess(k.index(("turnin", 1)), k.index(("do", 2)))

    def test_leaves_out_other_races_quests(self):
        qs = [quest(1, goals=[kill((0, 100, 0))]), quest(2, races=16, goals=[kill((0, 100, 0))])]
        steps, _ = planner(qs).plan(start=(0, 0, 0), race_bit=ORC, max_level=2)
        self.assertNotIn(2, {s.quest for s in steps})

    def test_says_when_to_go_to_another_zone(self):
        qs = [quest(1, xp=300, goals=[kill((0, 100, 0))]), quest(2, level=1, start=(0, 1500, 0), goals=[kill((0, 1550, 0))], xp=300)]
        steps, _ = planner(qs).plan(start=(0, 0, 0), race_bit=ORC, max_level=3)
        travel = [s for s in steps if s.kind == "travel"]
        self.assertTrue(travel and travel[0].zone == "Far Hills" and "Far Hills" in travel[0].text)

    def test_stays_in_its_zone_unless_another_is_clearly_better(self):
        # After the first quest: a hub in this zone (900 yards) and a slightly richer one just over the
        # border in Far Hills (1100 yards). Changing zones costs loading, flying or boats.
        qs = [quest(1, xp=300, goals=[kill((0, 50, 0))]),
              quest(2, start=(0, 900, 0), xp=400, goals=[kill((0, 950, 0))]),
              quest(3, start=(0, 1100, 0), xp=450, goals=[kill((0, 1150, 0))])]
        steps, _ = planner(qs).plan(start=(0, 0, 0), race_bit=ORC, max_level=3)
        accepted = [s.quest for s in steps if s.kind == "accept"]
        self.assertEqual(accepted[:2], [1, 2], accepted)

    def test_never_more_than_twenty_quests_in_the_log(self):
        qs = [quest(i, goals=[kill((0, 500 + i, 0))]) for i in range(1, 30)]
        p = planner(qs)
        steps, _ = p.plan(start=(0, 0, 0), race_bit=ORC, max_level=2)
        self.assertLessEqual(p.most_active, 20)

    def test_every_step_knows_its_level_and_place(self):
        qs = [quest(1, goals=[kill((0, 100, 0))], xp=1000)]
        steps, final = planner(qs).plan(start=(0, 0, 0), race_bit=ORC, max_level=3)
        self.assertTrue(all(s.zone == "Start Vale" and s.level >= 1 for s in steps if s.kind != "grind"))
        self.assertGreaterEqual(final.level, 2, "1000 experience is more than level 1 needs")

    def test_finishes_its_zone_before_moving_to_a_slightly_better_one(self):
        # Start Vale has three hubs left; Far Hills has one hub that's a bit better on its own.
        qs = [quest(1, xp=300, goals=[kill((0, 40, 0))]),
              quest(2, start=(0, 400, 0), xp=300, goals=[kill((0, 450, 0))]),
              quest(3, start=(0, 700, 0), xp=330, goals=[kill((0, 750, 0))]),
              quest(4, start=(0, 1050, 0), xp=900, goals=[kill((0, 1100, 0))])]
        steps, _ = planner(qs).plan(start=(0, 0, 0), race_bit=ORC, max_level=5)
        accepted = [s.quest for s in steps if s.kind == "accept"]
        self.assertEqual(accepted, [1, 2, 3, 4], accepted)

    def test_leaves_a_zone_that_is_worth_much_less_than_another(self):
        # After quest 1, Start Vale only has a poor hub left; Far Hills has a rich one.
        qs = [quest(1, xp=300, goals=[kill((0, 40, 0))]),
              quest(2, start=(0, 600, 0), xp=20, goals=[kill((0, 650, 0), count=1)]),
              quest(3, start=(0, 1200, 0), xp=1500, goals=[kill((0, 1250, 0))])]
        steps, _ = planner(qs).plan(start=(0, 0, 0), race_bit=ORC, max_level=4)
        accepted = [s.quest for s in steps if s.kind == "accept"]
        self.assertEqual(accepted[:2], [1, 3], accepted)

    def test_picks_the_next_zone_by_everything_it_offers(self):
        # Start Vale is done after quest 1. Far Hills (same continent) has three good hubs; the other
        # continent has one hub that's richer on its own. A boat trip for one hub isn't worth it.
        def w(point):
            m, x, y = point
            return ("Overseas" if m == 1 else "Start Vale" if x < 1000 else "Far Hills"), 0, 0
        qs = [quest(1, xp=300, goals=[kill((0, 40, 0))]),
              quest(2, start=(0, 1300, 0), xp=500, goals=[kill((0, 1350, 0))]),
              quest(3, start=(0, 1600, 0), xp=500, goals=[kill((0, 1650, 0))]),
              quest(4, start=(0, 1900, 0), xp=500, goals=[kill((0, 1950, 0))]),
              quest(5, start=(1, 0, 0), xp=1100, goals=[kill((1, 50, 0))])]
        p = RoutePlanner(qs, where=w, eligibility=Eligibility(), xp=XpModel(), travel=TravelModel(), scorer=HubScorer())
        steps, _ = p.plan(start=(0, 0, 0), race_bit=ORC, max_level=6)
        accepted = [s.quest for s in steps if s.kind == "accept"]
        self.assertEqual(accepted[1], 2, accepted)

    def test_follows_the_zone_plan_and_falls_back_when_its_zones_run_dry(self):
        # Far Hills is planned for levels 1-9 here; Start Vale isn't, even though we start there.
        qs = [quest(1, xp=300, goals=[kill((0, 40, 0))]),
              quest(2, start=(0, 1300, 0), xp=300, goals=[kill((0, 1350, 0))])]
        plan = ZonePlan([(1, 9, ["Far Hills"])])
        steps, _ = planner(qs, zone_plan=plan).plan(start=(0, 0, 0), race_bit=ORC, max_level=4)
        accepted = [s.quest for s in steps if s.kind == "accept"]
        self.assertEqual(accepted[0], 2, "the planned zone first")
        self.assertIn(1, accepted, "then the rest rather than grinding")

    def test_stays_on_its_continent_unless_the_other_is_clearly_better(self):
        # After Start Vale: Far Hills (same continent) is good; Overseas is a bit better even after the boat.
        def w(point):
            m, x, y = point
            return ("Overseas" if m == 1 else "Start Vale" if x < 1000 else "Far Hills"), 0, 0
        qs = [quest(1, xp=300, goals=[kill((0, 40, 0))]),
              quest(2, start=(0, 1500, 0), xp=600, goals=[kill((0, 1550, 0))]),
              quest(3, start=(1, 0, 0), xp=1500, goals=[kill((1, 50, 0))])]
        p = RoutePlanner(qs, where=w, eligibility=Eligibility(), xp=XpModel(), travel=TravelModel(), scorer=HubScorer())
        steps, _ = p.plan(start=(0, 0, 0), race_bit=ORC, max_level=6)
        accepted = [s.quest for s in steps if s.kind == "accept"]
        self.assertEqual(accepted[1], 2, accepted)

    def test_grinds_here_rather_than_sailing_for_a_poor_hub(self):
        # Level 10, nothing left at home; one small quest across the sea. Killing monsters here pays more.
        def w(point):
            m, x, y = point
            return ("Overseas" if m == 1 else "Start Vale"), 0, 0
        qs = [quest(1, level=10, min_level=10, start=(1, 0, 0), xp=150, goals=[kill((1, 50, 0), mob_level=10)])]
        p = RoutePlanner(qs, where=w, eligibility=Eligibility(), xp=XpModel(), travel=TravelModel(), scorer=HubScorer())
        p.start_level = 10
        steps, _ = p.plan(start=(0, 0, 0), race_bit=ORC, max_level=11)
        self.assertEqual(steps[0].kind, "grind", [s.text for s in steps[:3]])

    def test_sails_for_a_rich_hub(self):
        def w(point):
            m, x, y = point
            return ("Overseas" if m == 1 else "Start Vale"), 0, 0
        qs = [quest(i, level=10, min_level=10, start=(1, 0, 0), xp=3000, goals=[kill((1, 50, 0), mob_level=10)]) for i in range(1, 6)]
        p = RoutePlanner(qs, where=w, eligibility=Eligibility(), xp=XpModel(), travel=TravelModel(), scorer=HubScorer())
        p.start_level = 10
        steps, _ = p.plan(start=(0, 0, 0), race_bit=ORC, max_level=11)
        self.assertEqual(steps[0].kind, "travel", [s.text for s in steps[:3]])

    def test_a_far_delivery_waits_while_this_zone_still_has_quests(self):
        # Quest 1 is turned in far away in Far Hills; quest 2's hub is right here in Start Vale.
        qs = [quest(1, end=(0, 1800, 0), xp=200, goals=[kill((0, 60, 0))]),
              quest(2, start=(0, 300, 0), xp=200, prev=0, min_level=1, goals=[kill((0, 350, 0))])]
        steps, _ = planner(qs).plan(start=(0, 0, 0), race_bit=ORC, max_level=3)
        k = kinds(steps)
        self.assertLess(k.index(("accept", 2)), k.index(("turnin", 1)), k)

    def test_before_grinding_it_tries_quests_a_bit_above_you(self):
        qs = [quest(1, level=5, min_level=1, goals=[kill((0, 100, 0))])]
        steps, _ = planner(qs).plan(start=(0, 0, 0), race_bit=ORC, max_level=2)
        self.assertEqual(steps[0].kind, "accept", "level 1 with a level 5 quest (4 above): take it rather than grind")

    def test_with_nothing_to_do_it_says_to_grind(self):
        steps, final = planner([]).plan(start=(0, 0, 0), race_bit=ORC, max_level=2)
        self.assertEqual(steps[0].kind, "grind")
        self.assertEqual(final.level, 2)


if __name__ == "__main__":
    unittest.main()


class HordePlanTest(unittest.TestCase):
    def test_each_start_has_its_zone_then_shared_bands(self):
        import build_route
        undead = build_route.horde_plan("Tirisfal Glades")
        self.assertTrue(undead.allows("Tirisfal Glades", 5))
        self.assertTrue(undead.allows("Silverpine Forest", 12))
        self.assertFalse(undead.allows("Durotar", 5), "another race's start zone")
        tauren = build_route.horde_plan("Mulgore")
        self.assertTrue(tauren.allows("The Barrens", 14))
        self.assertTrue(tauren.allows("Thunder Bluff", 30), "cities always fit")
        self.assertFalse(tauren.allows("Tanaris", 20), "too early for Tanaris")
        self.assertTrue(tauren.allows("Tanaris", 44))


class ShortcutsTest(unittest.TestCase):
    """Flights and the hearthstone (2026-11-14: RestedXP flies and hearths, and runs a third less)."""

    def test_flies_when_both_flight_paths_are_known_and_it_saves_time(self):
        from route_planner import Shortcuts
        s = Shortcuts(flights=[("A", (1, 0, 0)), ("B", (1, 5000, 0))])
        s.learn((1, 0, 0)); s.learn((1, 5000, 0))
        way = s.best((1, 0, 0), (1, 5000, 0), 5000 / 7, 0)
        self.assertEqual(way[0], "fly")

    def test_walks_without_the_flight_path(self):
        from route_planner import Shortcuts
        s = Shortcuts(flights=[("A", (1, 0, 0)), ("B", (1, 5000, 0))])
        s.learn((1, 0, 0))
        self.assertEqual(s.best((1, 0, 0), (1, 5000, 0), 5000 / 7, 0)[0], "walk")

    def test_hearthstone_when_ready_and_home_is_near_the_target(self):
        from route_planner import Shortcuts
        s = Shortcuts(inns=[("Inn", (1, 3000, 0))])
        s.home = s.inns[0]
        self.assertEqual(s.best((1, 0, 0), (1, 3050, 0), 3050 / 7, now=0)[0], "hearth")
        s.ready_at = 100
        self.assertEqual(s.best((1, 0, 0), (1, 3050, 0), 3050 / 7, now=50)[0], "walk")  # on cooldown
