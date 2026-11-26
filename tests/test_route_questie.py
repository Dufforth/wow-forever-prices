"""Forever's own quests from Questie's Forever database (QuestieDB, GPL-3.0): decoding and conversion to route quests."""
import base64
import json
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "catalog"))
import route_questie as rq  # noqa: E402
from route_forever import load_questie, to_quest  # noqa: E402

ZONES = {10: "The Barrens", 11: "The Barrens", 20: "Riverglades"}
BOXES = {"The Barrens": (0.0, 0.0, 1000.0, 1000.0, 1), "Riverglades": (0.0, 0.0, 1000.0, 1000.0, 0)}


def db(quests):
    """A tiny decoded database: one giver, one target, one item dropped by the target."""
    return {
        "quest": {k: v for k, v in quests.items()},
        "npc": {100: {1: "Krom'rosh", 13: "H", 7: {20: [[59.4, 45.6]]}},
                200: {1: "Farmhand", 4: 36, 5: 37, 7: {20: [[40.0, 40.0], [41.0, 41.0], [42.0, 40.0], [90.0, 90.0]]}},
                300: {1: "Elite Brute", 4: 38, 5: 38, 6: 1, 7: {20: [[30.0, 30.0]]}}},
        "object": {}, "item": {500: {1: "Feed Satchel", 2: [200]}},
    }


QUEST = {1: "A Message in Blood", 4: 35, 5: 36, 6: 8589934770, 17: 20, 2: [[100]], 3: [[100]],
         8: ["Slay 12 Meadowsbrook Farmhands, then return to Krom'rosh."], 10: [[[200, "Meadowsbrook Farmhand", 0]]]}


class CborTest(unittest.TestCase):
    def test_reads_the_baked_values(self):
        # {1: "Ab", 2: [1, -2, 300]} and a compressed list
        raw = bytes([0xa2, 0x01, 0x62, 0x41, 0x62, 0x02, 0x83, 0x01, 0x21, 0x19, 0x01, 0x2c])
        self.assertEqual(rq.cbor(raw), {1: "Ab", 2: [1, -2, 300]})
        packed = base64.b64encode(zlib.compress(bytes([0x82, 0x05, 0x06]))).decode()
        self.assertEqual(rq.decode(packed, compressed=True), [5, 6])

    def test_reads_chunked_metadata(self):
        meta = {"X-Quest-IDS": "~2~", "X-Quest-IDS-1": "ab", "X-Quest-IDS-2": "cd", "X-One": "xy"}
        self.assertEqual(rq.stored(meta, "X-Quest-IDS"), "abcd")
        self.assertEqual(rq.stored(meta, "X-One"), "xy")


class CountTest(unittest.TestCase):
    def test_count_from_the_objective_text(self):
        self.assertEqual(rq.count_in(["Slay 12 Meadowsbrook Farmhands, then return."], "Meadowsbrook Farmhand"), 12)
        self.assertEqual(rq.count_in(["Steal 6 Feed Satchels from the farm."], "Feed Satchel"), 6)

    def test_no_number_means_none(self):
        self.assertIsNone(rq.count_in(["Find the grave's missing contents."], "Grave Dirt"))


class SpotsTest(unittest.TestCase):
    def test_keeps_the_densest_group(self):
        spots = rq.densest([("Riverglades", 40, 40), ("Riverglades", 41, 41), ("Riverglades", 42, 40), ("Riverglades", 90, 90)])
        self.assertEqual(len(spots), 3)
        self.assertNotIn(("Riverglades", 90, 90), spots)


class RowsTest(unittest.TestCase):
    def test_a_kill_quest_becomes_a_route_row(self):
        rows = rq.rows(db({93786: QUEST}), ZONES, {93786: (36, 2800)})
        self.assertEqual(len(rows), 1)
        r = rows[0]
        self.assertEqual((r["id"], r["level"], r["min_level"], r["xp"], r["races"] & 178), (93786, 36, 35, 2800, 178))
        self.assertEqual(r["giver"], {"name": "Krom'rosh", "zone": "Riverglades", "x": 59.4, "y": 45.6})
        o = r["objectives"][0]
        self.assertEqual((o["kind"], o["count"], o["mobLevel"], len(o["spots"])), ("monster", 12, 36.5, 3))

    def test_an_item_objective_is_looted_where_its_droppers_are(self):
        q = {**QUEST, **{8: ["Steal 6 Feed Satchels."], 10: {3: [[500, None, 0]]}}}
        o = rq.rows(db({93787: q}), ZONES, {})[0]["objectives"][0]
        self.assertEqual((o["kind"], o["text"], o["count"], o["source"]), ("item", "Feed Satchel", 6, "Farmhand"))

    def test_an_objective_with_no_place_borrows_the_others(self):
        q = {**QUEST, **{10: {1: [[200, None, 0]], 3: [[501, None, 0]]}}}
        data = db({1: q})
        data["item"][501] = {1: "Lost Satchel", 3: [999]}  # dropped by an object QuestieDB doesn't have
        objs = rq.rows(data, ZONES, {})[0]["objectives"]
        self.assertEqual(objs[1]["spots"], objs[0]["spots"])
        self.assertTrue(objs[1]["guessed"])
        self.assertTrue(to_quest(rq.rows(data, ZONES, {})[0], BOXES).goals[1].guessed)

    def test_a_quest_with_an_unplaced_objective_stays_out_of_the_route(self):
        q = {**QUEST, **{10: {3: [[501, None, 0]]}}}
        data = db({1: q})
        data["item"][501] = {1: "Lost Satchel"}
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "q.json"
            path.write_text(json.dumps({"quests": rq.rows(data, ZONES, {})}), encoding="utf-8")
            self.assertEqual(load_questie(path, BOXES), [])

    def test_elite_targets_make_a_group_quest(self):
        q = {**QUEST, **{10: [[[300, None, 0]]]}}
        r = rq.rows(db({1: q}), ZONES, {})[0]
        self.assertEqual(r["kind"], "group")
        self.assertTrue(r["objectives"][0]["elite"])

    def test_profession_class_repeatable_and_item_started_quests_are_left_out(self):
        cases = [{**QUEST, **{18: [164, 100]}}, {**QUEST, **{24: 1}}, {**QUEST, **{2: [None, None, [500]]}}]
        for i, q in enumerate(cases):
            self.assertEqual(rq.rows(db({i + 1: q}), ZONES, {}), [], i)

    def test_work_with_no_objectives_in_the_data_is_left_out(self):
        # 2026-11-16: 29 route quests (war effort, books, reputation) had work in their text and no objectives: free experience.
        work = {**QUEST, **{8: ["Acquire 15 Silithus Venom Samples and 20 gold and bring them to Jarl."], 10: None}}
        talk = {**QUEST, **{8: ["Speak with Magar in Orgrimmar."], 10: None}}
        delivery = {**QUEST, **{8: ["Bring the letter to Magar in Orgrimmar."], 10: None, 11: 777}}  # the giver hands it over
        self.assertEqual([r["id"] for r in rq.rows(db({1: work, 2: talk, 3: delivery}), ZONES, {})], [2, 3])

    def test_chain_links(self):
        q = {**QUEST, **{13: [93700], 22: 93790, 16: [93999]}}
        r = rq.rows(db({93786: q}), ZONES, {})[0]
        self.assertEqual((r["prev"], r["next"], r["exclusive"]), (93700, 93790, 93786))

    def test_scaling_quests_use_their_required_level(self):
        q = {**QUEST, **{5: -1, 4: 30}}
        self.assertEqual(rq.rows(db({1: q}), ZONES, {})[0]["level"], 30)


class LoadQuestieTest(unittest.TestCase):
    def test_rows_become_route_quests_with_their_links(self):
        row = rq.rows(db({93786: {**QUEST, **{13: [93700], 22: 93790}}}), ZONES, {93786: (36, 2800)})[0]
        q = to_quest(row, BOXES)
        self.assertEqual((q.level, q.min_level, q.xp, q.prev, q.next_in_chain), (36, 35, 2800, 93700, 93790))
        self.assertEqual((q.goals[0].count, q.goals[0].mob_level), (12, 36.5))
        self.assertEqual(q.goals[0].point[0], 0)

    def test_horde_only_and_known_ids_skipped(self):
        alliance = {**QUEST, **{6: 4294967373}}
        rows = rq.rows(db({1: QUEST, 2: alliance, 3: QUEST}), ZONES, {})
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "q.json"
            path.write_text(json.dumps({"quests": rows}), encoding="utf-8")
            out = load_questie(path, BOXES, known_ids={3})
        self.assertEqual([q.id for q in out], [1])
        self.assertTrue(out[0].races & 2)

    def test_missing_file_gives_nothing(self):
        self.assertEqual(load_questie(Path("nope.json"), BOXES), [])


class NewZonesTest(unittest.TestCase):
    def test_the_horde_plan_takes_forevers_new_zones(self):
        from build_route import horde_plan
        plan = horde_plan("Durotar")
        self.assertTrue(plan.allows("Riverglades", 40))
        self.assertTrue(plan.allows("Shen'dralas", 37))
        self.assertTrue(plan.allows("Mount Hyjal", 57))
        self.assertFalse(plan.allows("Mount Hyjal", 40))


if __name__ == "__main__":
    unittest.main()
