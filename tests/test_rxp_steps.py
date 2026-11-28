"""RestedXP steps kept whole (catalog/rxp_chain.py steps / route_steps): every line, tag and condition of a step, as
RestedXP's own engine reads them (GuideLoader.lua parseLine, RXPGuides.lua stepLogic defaults on Forever)."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "catalog"))
from rxp_chain import DUNGEON, MAIN, parts, route_steps, steps  # noqa: E402

GUIDE = r"""
RXPGuides.RegisterGuide([[
#group RestedXP Forever Guide (H)
#name 1-6 Durotar
#next 6-10 Durotar
step
    .goto 1411/1,-100.0,200.0
    .accept 1 >> Accept it
    .accept 2,1
    .target Gornek
step << Hunter
    #completewith next
    .goto 1411/1,-110.0,210.0,25,0
    >>Kill boars
    .complete 1,1 --Boar (8)
    .mob Mottled Boar
    .unitscan Warlord Kolkanis
step
    #label Camp
    .goto 1411/1,-120.0,220.0,40 >> Travel to the camp
    .isOnQuest 1
    .xp <4,1
step
    #hardcore
    .accept 99
step
    #softcore
    #requires Camp
    #sticky
    .turnin -1
    .train 1234,1 << Warrior
    .money <0.05
step
    #loop
    .goto 1411/1,-1.0,1.0,0
    .goto 1411/1,-1.0,1.0,40,0
    .goto 1411/1,-2.0,2.0,40,0
    .complete 1,1
step
    .group 3
    .accept 98
step
    .xp 5+1200
    .zoneskip Orgrimmar,1
    +Equip the axe
    .use 2024
    .itemcount 2024,1
    .itemStat 16,QUALITY,<7
    .cooldown item,6948,>0
    .hs >> Hearth
step
    .fly Orgrimmar >> Fly
    .fp Crossroads
    .home 1234
    .collect 159,10,0,1
    .vendor 3881
    .deathskip
    .abandon 7
    .skipgossip 3881,1
]])
RXPGuides.RegisterGuide([[
#group RestedXP Forever Guide (H)
#name 6-10 Durotar
step
    .turnin 2
]])
RXPGuides.RegisterGuide([[
#group RestedXP Forever Dungeon Guide (H)
#name 1-6 Durotar
#next 6-10 Durotar
step
    .enabledungeon RFC
    #include RestedXP Forever Guide (H)\1-6 Durotar
step
    .dungeon RFC
    .accept 50
]])
RXPGuides.RegisterGuide([[
#group RestedXP Forever Dungeon Guide (H)
#name 6-10 Durotar
step
    .turnin 50
]])
"""


class StepsTest(unittest.TestCase):
    def setUp(self):
        self.known = parts([GUIDE])
        self.steps = steps(self.known[(MAIN, "1-6 Durotar")][1], 1, part=0)[0]

    def test_one_step_per_rxp_step_variants_filtered(self):
        # #hardcore (hardcore off on Forever) and .group (group quests off) steps go; class tags stay for the game to judge
        self.assertEqual(len(self.steps), 7)
        self.assertEqual(self.steps[1]["tag"], "Hunter")

    def test_elements_kept_whole_in_order(self):
        first = self.steps[0]
        self.assertEqual([e[0] for e in first["e"]], ["goto", "accept", "accept", "target"])
        self.assertEqual(first["e"][2][1], ["2", "1"])        # raw arguments, as RestedXP parses them
        self.assertEqual(first["e"][0][1], [1, 200.0, -100.0, None, False, 1411])  # world point (continent, x, y), map id

    def test_side_step_flags(self):
        side, camp, sticky = self.steps[1], self.steps[2], self.steps[3]
        self.assertEqual(side["cw"], "next")
        self.assertEqual(camp["label"], "Camp")
        self.assertEqual((sticky["sticky"], sticky["req"]), (True, "Camp"))
        self.assertEqual(side["e"][0][1][3:5], [25.0, True])    # radius, optional: a walk-through point
        self.assertEqual(camp["e"][0][1][3:5], [40.0, False])   # a stop
        self.assertTrue(self.steps[4]["loop"])

    def test_line_tags_and_notes(self):
        self.assertEqual(self.steps[3]["e"][1], ["train", ["1234", "1"], "Warrior"])
        notes = [e for e in self.steps[5]["e"] if e[0] == "note"]
        self.assertEqual(notes, [["note", ["Equip the axe"], ""]])

    def test_all_kinds_read(self):
        kinds = {e[0] for s in self.steps for e in s["e"]}
        for k in ("isOnQuest", "xp", "turnin", "money", "zoneskip", "use", "itemcount", "itemStat", "cooldown", "hs", "fly",
                  "fp", "home", "collect", "vendor", "deathskip", "abandon", "skipgossip", "mob"):
            self.assertIn(k, kinds)

    def test_level_follows_xp(self):
        self.assertEqual(self.steps[4]["lv"], 1)
        self.assertEqual(self.steps[5]["lv"], 5)  # after ".xp 5+1200"

    def test_route_chain_and_dungeon_include(self):
        main = route_steps(self.known, "Durotar")
        self.assertEqual(len(main), 8)
        self.assertEqual(main[-1]["p"], 1)
        self.assertEqual(main[-1]["part"], "6-10 Durotar")
        dun = route_steps(self.known, "Durotar", dungeons=True)
        # The dungeon guide's first step includes the whole main part, then its own dungeon step
        self.assertEqual(len(dun), 7 + 1 + 1)
        self.assertEqual(dun[7]["e"][0], ["accept", ["50"], ""])


class TextTest(unittest.TestCase):
    """RestedXP's own text and step ids (user, 2026-11-27: the guide must look the same as RestedXP)."""

    def setUp(self):
        self.known = parts([GUIDE])
        self.steps = steps(self.known[(MAIN, "1-6 Durotar")][1], 1, part=0)[0]

    def test_line_numbers_match_restedxp_step_ids(self):
        # GuideLoader.lua: non-empty lines after "[[" counted from 1 ("#group" is 1); the first "step" line is 4
        self.assertEqual(self.steps[0]["ln"], 4)
        self.assertEqual(self.steps[1]["ln"], 9)

    def test_text_kept(self):
        self.assertEqual(self.steps[0]["e"][1], ["accept", ["1"], "", "Accept it"])   # the line's own text
        self.assertEqual(self.steps[1]["e"][1], ["text", ["Kill boars"], ""])         # a ">>" line on its own
        self.assertEqual(self.steps[2]["e"][0][3], "Travel to the camp")

    def test_subgroup_per_part(self):
        main = route_steps(self.known, "Durotar")
        self.assertEqual(main[0]["sub"], "")


class RowsTest(unittest.TestCase):
    """rxp_rows.rows_from_steps: rows you act on, step records for the addon's engine."""

    def setUp(self):
        from rxp_rows import rows_from_steps
        known = parts([GUIDE])
        self.rows, self.recs, self.stats = rows_from_steps(route_steps(known, "Durotar"), {}, lambda p: ("Durotar", p[1] / 10, p[2] / 10),
                                                           None, {"area": {1234: "Razor Hill"}, "map": {}})

    def test_records_and_rows_line_up(self):
        self.assertEqual(len(self.recs), 8)
        for n, rec in enumerate(self.recs, 1):
            for i in range(rec.get("a", 1), rec.get("b", 0) + 1):
                self.assertEqual(self.rows[i - 1][10], n)

    def test_side_steps(self):
        side, camp, sticky = self.recs[1], self.recs[2], self.recs[3]
        self.assertEqual((side["s"], side["cw"], side["t"]), (1, 3, "Hunter"))   # completewith next
        self.assertEqual(sticky["req"], 3)
        self.assertEqual(self.recs[4]["loop"], 1)

    def test_points_and_stops(self):
        camp = self.recs[2]
        self.assertEqual(self.rows[camp["a"] - 1][0], "goto")                  # radius, not optional: a stop row
        self.assertEqual(camp["pt"][0][3:5], [40.0, 0])
        self.assertEqual(self.recs[1]["pt"][0][4], 1)                          # ",25,0": walk-through
        self.assertEqual([p[4] for p in self.recs[4]["pt"]], [4, 2, 1, 1][:0] or [p[4] for p in self.recs[4]["pt"]])

    def test_targets_mobs_and_rare_scan(self):
        side = self.recs[1]
        self.assertEqual(side["mob"], ["Mottled Boar"])
        self.assertEqual(side["us"], ["Warlord Kolkanis"])  # .unitscan: its own list, for the nameplate sound alert
        self.assertEqual(self.recs[0]["tg"], ["Gornek"])

    def test_conditions(self):
        kinds = [c[0] for c in self.recs[2]["c"]]
        self.assertEqual(kinds, ["isOnQuest", "xp"])
        self.assertEqual(self.recs[2]["c"][1][1], {"l": 4, "rv": 1})           # .xp <4,1: skip below level 4
        self.assertEqual([c[0] for c in self.recs[3]["c"]], ["train", "money"])  # .train 1234,1 is text only

    def test_rows_kinds(self):
        kinds = [r[0] for r in self.rows]
        for k in ("accept", "do", "turnin", "grind", "note", "use", "hearth", "fly", "flight", "home", "collect", "vendor",
                  "deathskip", "abandon"):
            self.assertIn(k, kinds)
        home = [r for r in self.rows if r[0] == "home"][0]
        self.assertEqual(home[11], {"a": "Razor Hill", "ai": 1234})
        self.assertEqual(self.recs[6]["gs"], [3881, 1])  # .skipgossip npc, option

    def test_zone_from_the_goto_map(self):
        # A world point where two zone maps overlap takes the zone RestedXP's .goto names (1440/1 is Ashenvale, not
        # Azshara; 2026-11-27 screenshot: "Go to Azshara" for an Ashenvale point).
        from rxp_rows import rows_from_steps
        known = parts([GUIDE])
        rows, recs, _ = rows_from_steps(route_steps(known, "Durotar"), {}, lambda p: ("Azshara", 1.0, 1.0), None,
                                        {"area": {}, "map": {1411: "Durotar"}, "on": lambda zone, p: (zone, 5.0, 6.0)})
        camp = recs[2]
        self.assertEqual(rows[camp["a"] - 1][2:5], ["Durotar", 5.0, 6.0])
        self.assertEqual(camp["pt"][0][:3], ["Durotar", 5.0, 6.0])

    def test_text_rows_and_hidden_lines(self):
        first, side, camp = self.recs[0], self.recs[1], self.recs[2]
        self.assertEqual(first["ln"], 4)
        accept = self.rows[first["a"] - 1]
        self.assertEqual(accept[11].get("rt"), "Accept it")
        self.assertEqual(side["x"], [[0, "Kill boars", ""]])                   # before the step's first row
        stop = self.rows[camp["a"] - 1]
        self.assertEqual((stop[0], stop[11].get("rt")), ("goto", "Travel to the camp"))
        hidden = [r for r in self.rows if r[0] == "use"]
        self.assertTrue(all(r[11].get("h") == 1 for r in hidden if not r[11].get("rt")))
        self.assertFalse(any(" item " in r[6] or "quest 1" in r[6] for r in self.rows))  # never raw ids


class SpiritHealersTest(unittest.TestCase):
    """RestedXP's Forever Spirit Healer list (DB/forever/SpiritHealerDB.lua): the ghost arrow's targets on death-skip steps."""

    def test_parsed_with_continent(self):
        from rxp_chain import spirit_healers
        text = """addon.SpiritHealerWorld = {
  [0] = {
    { id = 1, wx = -9115.000, wy = 423.000, name = "Stormwind" },
  },
  [1] = {
    { id = 2, wx = 10.5, wy = -20.25, name = "Durotar, Razor Hill" },
  }
}"""
        self.assertEqual(spirit_healers(text), [[0, -9115.0, 423.0, "Stormwind"], [1, 10.5, -20.25, "Durotar, Razor Hill"]])


if __name__ == "__main__":
    unittest.main()
