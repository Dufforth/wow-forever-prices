"""Reading quests for the route (catalog/route_data.py) from small made-up database tables."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "catalog"))
from route_data import QuestRepository, nearest_cluster, spread_out  # noqa: E402
from build_farm import SKIP_TITLE  # noqa: E402


def t(columns, *rows):
    return (columns, [list(r) for r in rows])


QUEST_COLS = ["entry", "Title", "QuestLevel", "MinLevel", "RequiredRaces", "RequiredClasses", "RequiredSkill", "Type", "SpecialFlags",
              "PrevQuestId", "NextQuestInChain", "ExclusiveGroup", "RewMoneyMaxLevel", "LimitTime", "SrcItemId"] + \
             [f"ReqCreatureOrGOId{k}" for k in range(1, 5)] + [f"ReqCreatureOrGOCount{k}" for k in range(1, 5)] + \
             [f"ReqItemId{k}" for k in range(1, 5)] + [f"ReqItemCount{k}" for k in range(1, 5)] + [f"RewChoiceItemId{k}" for k in range(1, 7)]


def qrow(entry, title, level=5, races=0, kill=0, kill_count=0, item=0, item_count=0, classes=0, kind=0, prev=0, money=600):
    return [entry, title, level, level - 2, races, classes, 0, kind, 0, prev, 0, 0, money, 0, 0,
            kill, 0, 0, 0, kill_count, 0, 0, 0, item, 0, 0, 0, item_count, 0, 0, 0, 0, 0, 0, 0, 0, 0]


def tables():
    return {
        "quest_template": t(QUEST_COLS,
                            qrow(1, "Kill boars", kill=100, kill_count=8),
                            qrow(2, "Bring tusks", item=500, item_count=5),
                            qrow(3, "Alliance errand"),
                            qrow(4, "Lost letter"),
                            qrow(5, "Nowhere to go", kill=999, kill_count=3),
                            qrow(6, "Torn page")),
        "creature_template": t(["Entry", "Name", "MinLevel", "MaxLevel", "Faction", "LootId"],
                               [10, "Horde Giver", 30, 30, 85, 0], [11, "Alliance Giver", 30, 30, 12, 0],
                               [100, "Boar", 5, 6, 7, 100], [101, "Old Tusker", 7, 7, 7, 101]),
        "creature": t(["id", "map", "position_x", "position_y"],
                      [10, 1, 0, 0], [11, 1, 0, 0],
                      [100, 1, 200, 0], [100, 1, 210, 10], [100, 1, 3000, 0],  # boars near the giver, and one far away
                      [101, 1, 205, 5]),  # one rare boar among them
        "creature_loot_template": t(["entry", "item", "ChanceOrQuestChance", "groupid", "mincountOrRef", "maxcount"],
                                    [100, 500, -25, 0, 1, 1],   # a quest-only drop, 25%
                                    [101, 500, -100, 0, 1, 1],  # the rare one always drops it
                                    [100, 600, 10, 0, 1, 1],    # boars drop the letter that starts quest 4
                                    [100, 700, 1, 0, 1, 1]),    # and, rarely, a page that starts quest 6
        "creature_questrelation": t(["id", "quest"], [10, 1], [10, 2], [11, 3], [10, 5]),
        "creature_involvedrelation": t(["id", "quest"], [10, 1], [10, 2], [11, 3], [10, 4], [10, 5], [10, 6]),
        "gameobject_questrelation": t(["id", "quest"]),
        "gameobject_involvedrelation": t(["id", "quest"]),
        "gameobject": t(["id", "map", "position_x", "position_y"]),
        "gameobject_template": t(["entry", "name", "type", "data1"]),
        "gameobject_loot_template": t(["entry", "item"]),
        "areatrigger_involvedrelation": t(["id", "quest"]),
        "item_template": t(["entry", "name", "startquest"], [500, "Boar Tusk", 0], [600, "Old Letter", 4], [700, "Torn Page", 6]),
    }


def side(faction):
    return {85: "H", 12: "A"}.get(faction, "")


class NearestClusterTest(unittest.TestCase):
    def test_the_group_nearest_the_anchor(self):
        points = [(1, 200, 0), (1, 210, 10), (1, 3000, 0)]
        self.assertEqual(nearest_cluster(points, anchor=(1, 0, 0), radius=250), (1, 205, 5))

    def test_nothing_to_place(self):
        self.assertIsNone(nearest_cluster([], anchor=(1, 0, 0), radius=250))


class QuestRepositoryTest(unittest.TestCase):
    def setUp(self):
        self.quests = {q.id: q for q in QuestRepository(tables(), npc_side=side).load()}

    def test_a_kill_quest_goes_to_the_monsters_near_the_giver(self):
        q = self.quests[1]
        self.assertEqual((q.start, q.start_name, q.end_name), ((1, 0, 0), "Horde Giver", "Horde Giver"))
        g = q.goals[0]
        self.assertEqual((g.kind, g.name, g.count, g.point), ("kill", "Boar", 8, (1, 205, 5)))
        self.assertEqual(q.xp, 1000)  # 600 at level 60 = 60% of the experience

    def test_an_item_quest_counts_the_kills_it_takes(self):
        g = self.quests[2].goals[0]
        self.assertEqual((g.kind, g.name, g.count), ("collect", "Boar Tusk", 20))  # 5 tusks at 25%
        self.assertEqual(g.source, "Boar", "the common monster at that spot, not the rare one")

    def test_alliance_quests_are_left_out(self):
        self.assertNotIn(3, self.quests)

    def test_a_quest_started_by_a_dropped_item_starts_where_it_drops(self):
        # User (2026-11-13): quests from dropped items are part of the guide: loot the item, then start it.
        q = self.quests[4]
        self.assertEqual((q.start, q.start_item, q.start_name), ((1, 205, 5), 600, "Boar"), "the boars near its turn-in")
        self.assertEqual(q.start_drop, ("Old Letter", "Boar", 10.0))

    def test_a_drop_too_rare_to_farm_is_not_a_step(self):
        q = self.quests[6]
        self.assertEqual((q.start, q.start_drop), (None, ()))

    def test_objectives_with_no_place_go_to_the_giver_flagged(self):
        # 2026-11-14: dropping them lost whole chains (Echeyakee and the four quests after it).
        q = self.quests[5]
        self.assertEqual(q.goals[0].point, q.start)
        self.assertTrue(q.goals[0].guessed)

    def test_placed_objectives_are_not_flagged(self):
        self.assertFalse(self.quests[1].goals[0].guessed)


if __name__ == "__main__":
    unittest.main()


class SpreadOutTest(unittest.TestCase):
    """User (2026-11-13): monsters like zhevras or raptors are all over the map; their quests are done
    while going to other quests, not as a stop of their own."""

    def test_all_over_the_map(self):
        points = [(1, x * 300.0, y * 300.0) for x in range(8) for y in range(8)]  # 64 spawns, 2 km across
        self.assertTrue(spread_out(points, (1, 0.0, 0.0)))

    def test_one_camp(self):
        points = [(1, 1000 + x * 20.0, 1000 + y * 20.0) for x in range(8) for y in range(8)]
        self.assertFalse(spread_out(points, (1, 1070.0, 1070.0)))

    def test_too_few_to_meet_on_the_way(self):
        points = [(1, x * 400.0, 0.0) for x in range(10)]
        self.assertFalse(spread_out(points, (1, 0.0, 0.0)))

    def test_other_maps_do_not_count(self):
        points = [(0, x * 300.0, y * 300.0) for x in range(8) for y in range(8)] + [(1, 5.0, 5.0)]
        self.assertFalse(spread_out(points, (1, 0.0, 0.0)))


class PlaceholderTitleTest(unittest.TestCase):
    """The Onyxia attunement's 'The Testament of Rexxar' and 'The Test of Skulls' were dropped as test quests."""

    def test_real_quests_with_test_in_the_name_are_kept(self):
        for title in ("The Testament of Rexxar", "The Test of Skulls, Scryer", "A Test of Faith"):
            self.assertIsNone(SKIP_TITLE.search(title), title)

    def test_placeholders_are_dropped(self):
        for title in ("Test Quest", "TEST", "zzOld", "[PH] Thing", "Deprecated quest", "Quest Test"):
            self.assertIsNotNone(SKIP_TITLE.search(title), title)



class LoopPointsTest(unittest.TestCase):
    """Kill-area loops (user, 2026-11-14): spots to circle through where the monsters spawn."""

    def test_spots_in_walking_order_from_the_objective(self):
        from route_data import loop_points
        camps = [(1, 0, 0), (1, 200, 0), (1, 200, 200)]
        spawns = [(m, x + dx, y + dy) for m, x, y in camps for dx, dy in ((0, 0), (5, 5), (-5, 3))]
        loop = loop_points(spawns, (1, 0, 0))
        self.assertEqual(len(loop), 3)
        self.assertLess(abs(loop[0][1]) + abs(loop[0][2]), 20)  # starts at the objective's camp
        self.assertGreater(loop[1][1], 150)

    def test_too_few_spawns_no_loop(self):
        from route_data import loop_points
        self.assertEqual(loop_points([(1, 0, 0), (1, 5, 5)], (1, 0, 0)), [])

    def test_far_spawns_ignored(self):
        from route_data import loop_points
        spawns = [(1, 0, 0)] * 3 + [(1, 5000, 0)] * 5
        self.assertEqual(loop_points(spawns, (1, 0, 0)), [])
