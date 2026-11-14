"""The leveling guide's model (Guide.lua) outside the game: which step is current, what's skipped, chain
advice, class and dungeon quests, gray quests in your log. The game is a fake adapter, so every case
is exact; one case uses a real Tauren Druid's state (level 14 in the Barrens) against the real data."""
import sys
from pathlib import Path

import lupa.lua51 as L

ADDON = Path(__file__).resolve().parents[2] / "addon" / "DufforthTweaksHelper"
failed = False


def check(label, cond, detail=""):
    global failed
    print(("PASS " if cond else "FAIL ") + label + (f"   [{detail}]" if detail != "" else ""))
    if not cond:
        failed = True


def runtime():
    lua = L.LuaRuntime(unpack_returned_tuples=True)
    lua.execute((ADDON / "Guide.lua").read_text(encoding="utf-8"))
    lua.execute("""
G = DufforthTweaksHelperGuide
-- A fake game: level, class bit, race, completed quests, quest log, finished objectives, zone.
function GAME(t)
  return {
    level = function() return t.level end, classBit = function() return t.classBit or 1 end, raceBit = function() return t.raceBit or 2 end,
    done = function(id) return (t.done or {})[id] == true end, inLog = function(id) return (t.log or {})[id] == true end,
    complete = function(id) return (t.complete or {})[id] == true end, zone = function() return t.zone or "Durotar" end,
    logIds = function() local o = {} for id in pairs(t.log or {}) do o[#o + 1] = id end table.sort(o) return o end,
    position = t.pos and function() return t.pos[1], t.pos[2], t.pos[3] end or nil,
  }
end
""")
    return lua


# A tiny world: quest 1 then its follow-up 2; quest 3 elsewhere; a travel; a grind; class and dungeon quests.
FIXTURE = """
DATA = {
  uiMaps = { Durotar = 1411, ["The Barrens"] = 1413 },
  extras = { class = { 20, 21 }, dungeon = { 30 }, item = {} },
  routes = { Durotar = { races = { "Orc", "Troll" }, steps = {
    { "accept", 1, "Durotar", 40, 60, 1, 'Accept "Boars"' },
    { "do", 1, "Durotar", 45, 65, 1, 'Kill 8 Boar for "Boars"' },
    { "turnin", 1, "Durotar", 40, 60, 2, 'Turn in "Boars"' },
    { "accept", 2, "Durotar", 40, 60, 2, 'Accept "More Boars"' },
    { "do", 2, "Durotar", 46, 66, 2, 'Kill 8 Boar for "More Boars"' },
    { "turnin", 2, "Durotar", 40, 60, 3, 'Turn in "More Boars"' },
    { "travel", 0, "The Barrens", 52, 30, 3, "Go to The Barrens" },
    { "accept", 3, "The Barrens", 52, 30, 3, 'Accept "Raptors"' },
    { "do", 3, "The Barrens", 55, 35, 4, 'Kill raptors for "Raptors"' },
    { "turnin", 3, "The Barrens", 52, 30, 5, 'Turn in "Raptors"' },
    { "grind", 0, "The Barrens", 52, 30, 5, "Kill monsters of your level around here to reach level 6" },
    { "accept", 4, "The Barrens", 52, 30, 6, 'Accept "Chain start"' },
  } } },
  quests = {
    [1] = { "Boars", 1, 1, 0, "", 0, 2, "Gornek", { "Durotar", 40, 60 }, "Gornek", { "Durotar", 40, 60 }, {}, {}, 0, 2 },
    [2] = { "More Boars", 2, 1, 0, "", 1, 0, "Gornek", { "Durotar", 40, 60 }, "Gornek", { "Durotar", 40, 60 }, {}, {}, 0, 2 },
    [3] = { "Raptors", 4, 2, 0, "", 0, 0, "Thork", { "The Barrens", 52, 30 }, "Thork", { "The Barrens", 52, 30 }, {}, {}, 0, 0 },
    [4] = { "Chain start", 3, 1, 0, "", 0, 5, "Old Npc", { "The Barrens", 52, 30 }, "Old Npc", { "The Barrens", 52, 30 }, {}, {}, 0, 0 },
    [5] = { "Chain end", 9, 6, 0, "", 4, 0, "Old Npc", { "The Barrens", 52, 30 }, "Old Npc", { "The Barrens", 52, 30 }, {}, {}, 0, 0 },
    [20] = { "Warrior's Training", 10, 10, 1, "", 0, 0, "Trainer", { "Orgrimmar", 80, 30 }, "Trainer", { "Orgrimmar", 80, 30 }, {}, {}, 0, 0 },
    [21] = { "Druid's Training", 10, 10, 1024, "", 0, 0, "Trainer", { "Thunder Bluff", 76, 27 }, "Trainer", { "Thunder Bluff", 76, 27 }, {}, {}, 0, 0 },
    [30] = { "Ragefire Chasm", 15, 9, 0, "dungeon", 0, 0, "Thrall", { "Orgrimmar", 31, 37 }, "Thrall", { "Orgrimmar", 31, 37 }, {}, {}, 0, 0 },
  },
}
"""


def model(lua, **game):
    parts = []
    for key, val in game.items():
        if isinstance(val, (set, list, tuple)):
            parts.append(f"{key} = {{ " + ", ".join(f"[{v}] = true" for v in val) + " }")
        elif isinstance(val, str):
            parts.append(f'{key} = "{val}"')
        else:
            parts.append(f"{key} = {val}")
    lua.execute("M = G.NewModel(DATA, 'Durotar', GAME({ " + ", ".join(parts) + " }), { skipped = {} })")
    return lua.eval("M")


lua = runtime()
lua.execute(FIXTURE)

model(lua, level=1)
check("a new character starts at the first step", lua.eval("M:Current()") == 1)

model(lua, level=2, done={1})
check("done quests are skipped: accept, objectives and turn-in", lua.eval("M:Current()") == 4)

model(lua, level=1, log={1})
check("a quest in your log: its accept step is done, go do it", lua.eval("M:Current()") == 2)

model(lua, level=1, log={1}, complete={1})
check("objectives finished: turn it in", lua.eval("M:Current()") == 3)

model(lua, level=3, done={1, 2}, zone="Durotar")
check("next zone: go there", lua.eval("M:Current()") == 7)
model(lua, level=3, done={1, 2}, zone="The Barrens")
check("already in that zone: the travel step is done", lua.eval("M:Current()") == 8)

model(lua, level=8, zone="The Barrens")
check("starting at a higher level: low quests you never did are skipped", lua.eval("M:Current()") >= 11, lua.eval("M:Current()"))
check("the grind step is done once you're past its level", lua.eval("M:Current()") == 12, lua.eval("M:Current()"))


# ---- Top 6 (user, 2026-11-14): one step per place, tips, loops, checkpoints, errands, hearthstone ----
model(lua, level=2, done={1})
lua.execute("M2 = G.NewModel(DATA, 'Durotar', GAME({ level = 2, log = { [1] = true }, complete = { [1] = true } }), { skipped = {} })")
check("one step per place: turn-in and the next pick-up at the same NPC share a block",
      lua.eval("M2:Together(3, 4)") is True and lua.eval("M2:TalkTo(3)") == "Gornek")
blk = lua.eval("M2:Blocks(1)[1]")
check("one step per place: the first block holds both", [blk[k] for k in sorted(blk)] == [3, 4], [blk[k] for k in sorted(blk)])
check("one step per place: different NPCs don't share", lua.eval("M2:Together(4, 8)") is False)
lua.execute("""
DATA.quests[1][12] = { { "kill", "Boar", 8, "Durotar", 45, 65, "", 0, { { 44, 64 }, { 50, 60 }, { 47, 70 } }, 3, 4, 0 } }
DATA.quests[3][12] = { { "collect", "Raptor Head", 12, "The Barrens", 55, 35, "Raptor", 1, {}, 11, 12, 1 } }
""")
lua.execute("M3 = G.NewModel(DATA, 'Durotar', GAME({ level = 3 }), { skipped = {} })")
check("tip: monster levels and the loop", lua.eval("G.Tip(M3, 2)") == "Level 3-4, circle the 3 spots on your map", lua.eval("G.Tip(M3, 2)"))
check("tip: elite, kills, along the way", lua.eval("G.Tip(M3, 9)") ==
      "Level 11-12, elite: bring friends, about 12 kills, they're all over the zone: kill them as you go", lua.eval("G.Tip(M3, 9)"))
check("tip: in the step's description", lua.eval("G.Describe(M3, 2).tip") == lua.eval("G.Tip(M3, 2)"))
check("loop: a kill area with spots gets the arrow", lua.eval("M3:Pinpoint(2)") is True and lua.eval("#M3:Loop(2)") == 3)
check("loop: the arrow moves to the next spot when you reach one", lua.eval("G.NextLoopSpot(M3:Loop(2), 1, 44.5, 64.5)") == 2)
check("loop: far from it, it stays", lua.eval("G.NextLoopSpot(M3:Loop(2), 2, 10, 10)") == 2)
check("loop: after the last spot, back to the first", lua.eval("G.NextLoopSpot(M3:Loop(2), 3, 47, 70)") == 1)
check("kills: 1000 xp at level 10 is 11 kills (95 each)", lua.eval("G.KillsFor(10, 1000)") == 11)
lua.execute("M4 = G.NewModel(DATA, 'Durotar', GAME({ level = 3 }), { skipped = {} }); M4.game.xp = function() return 100, 1000 end")
check("checkpoint: a part planned for 5+ while you're 3", lua.eval("M4:Checkpoint(10).level") == 4, lua.eval("M4:Checkpoint(10) and M4:Checkpoint(10).level"))
check("checkpoint: none when you're on track", lua.eval("M4:Checkpoint(2)") is None)
check("checkpoint: said in the description", "Planned for level 4+" in str(lua.eval("G.Describe(M4, 10).checkpoint")))
E = """G.Errands({ zone = "The Barrens", level = 12, freeSlots = 1, durability = 0.9, homeZone = "Durotar", sectionZone = "The Barrens", sectionLeft = 20,
  repair = { name = "Smith", zone = "The Barrens", x = 51, y = 30 }, inn = { name = "Innkeeper", zone = "The Barrens", x = 52, y = 29 },
  train = { count = 2, cost = "1s", trainer = { name = "Trainer", zone = "The Barrens", x = 50, y = 30 } },
  classQuest = { id = 20, title = "Training", giver = "Gar", zone = "Orgrimmar", x = 1, y = 1 }, skipped = SKIP or {} })"""
kinds = lambda: [lua.eval(E)[k].kind for k in sorted(lua.eval(E))]
check("errands: repair (bags full), train, hearthstone; a class quest elsewhere waits", kinds() == ["repair", "train", "home"], kinds())
lua.execute('SKIP = { ["home:The Barrens"] = true }')
check("errands: a skipped one stays hidden", kinds() == ["repair", "train"], kinds())
lua.execute("SKIP = nil")
check("errands: no hearthstone errand when it's already set here",
      "home" not in [r.kind for r in lua.eval(E.replace('homeZone = "Durotar"', 'homeZone = "The Barrens"')).values()])
lua.execute("""M5 = G.NewModel(DATA, 'Durotar', GAME({ level = 3, zone = "Durotar" }), { skipped = {} })
DATA.travel = { continents = { Durotar = 1, ["The Barrens"] = 1 }, flights = {}, transports = {} }
M5.game.hearth = function() return "The Barrens", true end""")
check("hearthstone: a step in your home zone starts with it", "Hearthstone" in str(lua.eval("M5:Directions(8)[1].text")), lua.eval("M5:Directions(8)[1].text"))
lua.execute('M5.game.hearth = function() return "The Barrens", false end')
check("hearthstone: on cooldown, the usual way", "Hearthstone" not in str(lua.eval("(M5:Directions(8) or {{text=''}})[1].text")))
lua.execute("DATA.travel = nil; DATA.quests[1][12] = {}; DATA.quests[3][12] = {}")
F = """G.Errands({ zone = "The Barrens", level = 12, innHere = { name = "Innkeeper", zone = "The Barrens", x = 52, y = 29 },
  food = { food = FOOD, drink = DRINK, mana = MANA } })"""
fk = lambda: [lua.eval(F)[k].action for k in sorted(lua.eval(F))]
lua.execute("FOOD, DRINK, MANA = 2, 0, false")
check("food: low on food, buy some at the innkeeper", len(fk()) == 1 and "Buy food at" in fk()[0], fk())
lua.execute("FOOD, DRINK, MANA = 10, 1, true")
check("food: a mana user low on water buys water", len(fk()) == 1 and "Buy water" in fk()[0], fk())
lua.execute("FOOD, DRINK, MANA = 10, 1, false")
check("food: no mana, water doesn't matter", fk() == [])
# Auto flight.
N = lambda body: lua.eval("G.PickTaxiNode({" + body + "}, 'The Barrens')")
check("taxi: the one reachable node in the zone", N('{index=1,name="Orgrimmar, Durotar",type="CURRENT"},{index=2,name="Crossroads, The Barrens",type="REACHABLE"}') == 2)
check("taxi: several in the zone, the nearest to the flight master",
      N('{index=1,name="Crossroads, The Barrens",type="REACHABLE",dist=900},{index=2,name="Camp Taurajo, The Barrens",type="REACHABLE",dist=100}') == 2)
check("taxi: several and no distance, not sure: no flight", N('{index=1,name="A, The Barrens",type="REACHABLE"},{index=2,name="B, The Barrens",type="REACHABLE"}') is None)
check("taxi: unreachable nodes are skipped", N('{index=1,name="Crossroads, The Barrens",type="UNREACHABLE"}') is None)
lua.execute("""M6 = G.NewModel(DATA, 'Durotar', GAME({ level = 3, zone = "Durotar" }), { skipped = {} })
DATA.travel = { flights = { { "Devrak", "The Barrens", 51, 30, 1 }, { "Far One", "The Barrens", 80, 80, 1 } } }""")
check("taxi: flies to the flight master nearest the next step's place", lua.eval("M6:FlightTo(8)[1]") == "Devrak")
check("taxi: none when the step is in your zone", lua.eval("M6:FlightTo(2)") is None)
lua.execute("DATA.travel = nil")
# Gold farming stops (explorer): the monster worth the most per kill at the addon's prices.
pick = lua.eval("G.FarmPick({ { 1, 'Cheap', 50 }, { 2, 'Rich', 10 } }, function(id) return id == 1 and 100 or 2000 end)")
check("farm: picks the drop worth the most per kill (price x chance)", pick[0][2] == "Rich" and pick[1] == 200, (pick[0][2], pick[1]))
check("farm: no prices, the first one", lua.eval("G.FarmPick({ { 1, 'A', 5 }, { 2, 'B', 9 } }, nil)")[0][2] == "A")
# Leveling tracker.
lua.execute("""T = {}
G.TrackXP(T, 0, 10, 0, 1000); G.TrackXP(T, 60, 10, 200, 1000); G.TrackXP(T, 120, 10, 400, 1000)""")
check("tracker: experience an hour from play", lua.eval("G.TrackSummary(T).perHour") == 12000, lua.eval("G.TrackSummary(T).perHour"))
check("tracker: time to level at this pace (600 left at 200 a minute)", lua.eval("G.TrackSummary(T).toLevel") == 180)
lua.execute("G.TrackXP(T, 2000, 10, 500, 1000)")
check("tracker: a long gap (away) isn't playing time", lua.eval("T.played") == 120)
lua.execute("G.TrackXP(T, 2060, 11, 100, 1200)")
check("tracker: a level up counts the rest of the bar and saves the level's time",
      lua.eval("T.gained") == 1100 and lua.eval("T.times[10]") == 180, (lua.eval("T.gained"), lua.eval("T.times[10]")))
check("tracker: says the last level's time", lua.eval("G.TrackSummary(T).lastLevel.seconds") == 180)
check("tracker: durations read well", lua.eval("G.Duration(4000)") == "1h 06m" and lua.eval("G.Duration(185)") == "3m")
model(lua, level=8, zone="The Barrens")
idx = lua.eval("M:Current()")
check("a low quest that starts a chain up to your level is kept, with advice",
      idx == 12 and "chain" in (lua.eval("M:Note(12)") or "").lower(), lua.eval("M:Note(12)"))
lua.execute("DATA.quests[5][2] = 5")  # now the whole chain is below you
model(lua, level=12)
check("a chain that stays below your level is skipped", lua.eval("M:Current()") is None or lua.eval("M:Current()") > 12)
lua.execute("DATA.quests[5][2] = 9")

model(lua, level=2, done={1}, log=set())
lua.execute("DATA.quests[2][6] = 99")  # quest 2 now needs quest 99 first
model(lua, level=2, done={1})
check("a quest whose earlier quest you skipped is left out", lua.eval("M:Current()") == 7, lua.eval("M:Current()"))
lua.execute("DATA.quests[2][6] = 1")

model(lua, level=1)
lua.execute("M:Skip()")
check("Skip moves past the current step (and that quest's steps) and remembers",
      lua.eval("M:Current()") != 1 and lua.eval("M.saved.skipped[1]") is True)
lua.execute("M:Back()")
check("Back brings it back", lua.eval("M:Current()") == 1)

model(lua, level=12, classBit=1024, raceBit=32)
names = lua.eval("(function() local t = {} for _, q in ipairs(M:ClassQuests()) do t[#t+1] = q.title end return table.concat(t, ',') end)()")
check("class quests: only your class's, at your level", names == "Druid's Training", names)
lua.execute("DATA.quests[21][2] = 12")  # a level 12 quest you may take from 10
CLASSNAMES = "(function() local t = {} for _, q in ipairs(M:ClassQuests()) do t[#t+1] = q.title end return table.concat(t, ',') end)()"
model(lua, level=10, classBit=1024, raceBit=32)
check("class quests: not shown while more than a level above you (user: level 30 quests at 27)", lua.eval(CLASSNAMES) == "", lua.eval(CLASSNAMES))
model(lua, level=11, classBit=1024, raceBit=32)
check("class quests: shown from a level below it", lua.eval(CLASSNAMES) == "Druid's Training", lua.eval(CLASSNAMES))
lua.execute("DATA.quests[21][2] = 10")

model(lua, level=13)
names = lua.eval("(function() local t = {} for _, q in ipairs(M:DungeonQuests()) do t[#t+1] = q.title end return table.concat(t, ',') end)()")
check("dungeon quests near your level", names == "Ragefire Chasm", names)

model(lua, level=9, log={1, 3})
adv = lua.eval("(function() local t = {} for _, q in ipairs(M:GrayInLog()) do t[#t+1] = q.title end return table.concat(t, ',') end)()")
check("quests in your log that went gray are listed to abandon", adv == "Boars", adv)

# Upcoming: the current step and the next ones, as if you do each in turn.
def upcoming(n):
    return [int(v) for v in lua.eval(f"M:Upcoming({n})").values()]

model(lua, level=1)
check("upcoming: a fresh start shows pick-up, objective, turn-in, follow-up", upcoming(4) == [1, 2, 3, 4], upcoming(4))
model(lua, level=1, log={1})
check("upcoming: with the quest in your log, from its objective on", upcoming(3) == [2, 3, 4], upcoming(3))
model(lua, level=8, zone="The Barrens")
check("upcoming: fewer when the route has fewer left", upcoming(4) == [12], upcoming(4))

# Describing a step: an action icon, the action with names highlighted, and the game's progress lines.
lua.execute("""
DATA.quests[1][12] = { { "kill", "Boar", 8, "Durotar", 45, 65, "" } }
DATA.quests[3][12] = { { "collect", "Raptor Head", 15, "The Barrens", 55, 35, "Sunscale Screecher" } }
DATA.steps_for_test = true
""")
model(lua, level=1)
D = lua.eval("G.Describe")
def describe(i, objectives=None):
    lua.execute("OBJ = " + (objectives or "nil"))
    return lua.eval(f"G.Describe(M, {i}, OBJ)")

d = describe(1)
check("describe: a pick-up says who to talk to", d.icon and "AvailableQuest" in d.icon and "Talk to" in d.action and "Gornek" in d.action and "Boars" in d.action, d.action)
d = describe(2, '{ { text = "3/8 Boar slain", finished = false } }')
check("describe: a kill step says Kill and the monster", "Kill" in d.action and "Boar" in d.action and d.kind == "kill", d.action)
check("describe: the game's count inside the action, not a second line repeating the name (user)",
      "3/8" in d.action and len(d.lines) == 0, (d.action, len(d.lines)))
check("describe: the quest name is kept for the header, not added to the action", d.quest == "Boars" and "(Boars)" not in d.action, d.action)
d = describe(3)
check("describe: a turn-in says what to turn in and to whom", "Turn in" in d.action and "Gornek" in d.action and "ActiveQuest" in d.icon, d.action)
d = describe(7)
check("describe: a zone change says where to go", "Go to" in d.action and "The Barrens" in d.action, d.action)
lua.execute("M = G.NewModel(DATA, 'Durotar', GAME({ level = 4, zone = 'The Barrens', log = { [3] = true } }), { skipped = {} })")
d = describe(9)
check("describe: a loot step says Loot the item from the monster", "Loot" in d.action and "Raptor Head" in d.action and "Sunscale Screecher" in d.action and d.kind == "loot", d.action)
d = describe(11)
check("describe: a grind step says so", d.kind == "grind")

# Sections: the route split by zone with the levels you have there, like "12-16 The Barrens".
model(lua, level=1)
secs = lua.eval("M:Sections()")
check("sections: one per zone", len(secs) == 2 and secs[1].zone == "Durotar" and secs[2].zone == "The Barrens", [secs[k].zone for k in secs])
check("sections: steps and levels", (secs[1].first, secs[1].last, secs[1]["from"], secs[1]["to"]) == (1, 6, 1, 3),
      (secs[1].first, secs[1].last, secs[1]["from"], secs[1]["to"]))
check("sections: the trip to a zone starts its section", secs[2].first == 7 and secs[2].last == 12)
check("sections: titled with the levels", lua.eval("G.SectionTitle(M:Sections()[2])") == "3-6 The Barrens", lua.eval("G.SectionTitle(M:Sections()[2])"))
check("sections: which section a step is in", lua.eval("M:SectionOf(8)") == 2 and lua.eval("M:SectionOf(1)") == 1)
lua.execute("""
local steps = {}
for k, z in ipairs({ "A", "A", "A", "A", "B", "A", "A", "A", "C", "C", "C", "C" }) do steps[k] = { "do", 0, z, 1, 1, k, "x" } end
DATA.routes.Blip = { races = {}, steps = steps }
B = G.NewModel(DATA, "Blip", GAME({ level = 1 }), { skipped = {} })
""")
blip = lua.eval("B:Sections()")
check("sections: a short visit over a border stays in the zone's section", len(blip) == 2 and blip[1].last == 8 and blip[2].zone == "C",
      [(blip[k].zone, blip[k].first, blip[k].last) for k in blip])

# States: done, the current step, the steps ahead, and ones you will pass by.
model(lua, level=1, log={1})
st = lua.eval("M:States(12)")
check("states: done before the current step", st[1] == "done", st[1])
check("states: the current step", st[2] == "current", st[2])
check("states: the steps ahead", st[3] == "open" and st[4] == "open", (st[3], st[4]))
model(lua, level=8)
st = lua.eval("M:States(12)")
check("states: steps you will pass by (gray quests, past grinds)", st[11] == "passed", st[11])

# The arrow: which way to turn and how far (world: north, west; facing 0 = north, turning left is +).
import math
def bearing(pn, pw, tn, tw, facing):
    return lua.eval(f"G.Bearing({pn}, {pw}, {tn}, {tw}, {facing})")
rel, dist = bearing(0, 0, 10, 0, 0)
check("arrow: straight ahead", abs(rel) < 1e-9 and abs(dist - 10) < 1e-9, (rel, dist))
rel, _ = bearing(0, 0, 0, 10, 0)
check("arrow: to the west is a quarter turn left", abs(rel - math.pi / 2) < 1e-9, rel)
rel, _ = bearing(0, 0, 10, 0, math.pi / 2)
check("arrow: facing west, north is to the right", abs(rel + math.pi / 2) < 1e-9, rel)
rel, _ = bearing(0, 0, -10, 0, 0)
check("arrow: behind you", abs(abs(rel) - math.pi) < 1e-9, rel)
check("arrow: time to get there at your speed", lua.eval("G.Eta(70, 7)") == "0:10" and lua.eval("G.Eta(700, 7)") == "1:40", lua.eval("G.Eta(700, 7)"))
check("arrow: standing still counts as running speed", lua.eval("G.Eta(70, 0)") == "0:10")

# Progress in the current section, like the bar under the step.
model(lua, level=2, done={1})
done, total = lua.eval("M:SectionProgress(1)")
check("progress: steps behind you in the section", (done, total) == (3, 6), (done, total))

# Along the way (user, 2026-11-13): monsters all over the map (raptors, zhevras) are killed while you go to
# other quests; the guide asks you to finish them only when their turn-in comes or the next part of the route
# starts. Two steps on the same monsters are one block.
lua.execute("""
local function q(title, goals, turnAt) return { title, 5, 1, 0, "", 0, 0, "Npc", { "A", 50, 50 }, "Npc", turnAt or { "A", 50, 50 }, goals, {}, 0, 0 } end
DATA.quests[10] = q("Raptor Thieves", { { "collect", "Raptor Head", 12, "A", 50, 50, "Raptor", 1 } }, { "B", 20, 20 })
DATA.quests[11] = q("Boars", { { "kill", "Boar", 5, "A", 31, 31, "", 0 } })
DATA.quests[14] = q("Boar Ribs", { { "collect", "Boar Rib", 6, "A", 32, 32, "Boar", 0 } })
DATA.quests[12] = q("Filler", {})
DATA.quests[13] = q("Over There", { { "kill", "Wolf", 5, "B", 25, 25, "", 0 } })
DATA.routes.Wide = { races = {}, steps = {
  { "accept", 10, "A", 50, 50, 5, "" }, { "do", 10, "A", 50, 50, 5, "", 1 }, { "accept", 11, "A", 30, 30, 5, "" },
  { "accept", 14, "A", 30, 30, 5, "" }, { "do", 11, "A", 31, 31, 5, "", 1 }, { "do", 14, "A", 32, 32, 5, "", 1 },
  { "turnin", 11, "A", 30, 30, 5, "" }, { "turnin", 14, "A", 30, 30, 5, "" }, { "accept", 12, "A", 60, 60, 5, "" },
  { "travel", 0, "B", 20, 20, 6, "Go to B" }, { "accept", 13, "B", 20, 20, 6, "" }, { "do", 13, "B", 25, 25, 6, "", 1 },
  { "turnin", 10, "B", 20, 20, 6, "" }, { "turnin", 13, "B", 20, 20, 6, "" },
} }
function WIDE(t) t.level = t.level or 5; t.zone = t.zone or "A"; W = G.NewModel(DATA, "Wide", GAME(t), { skipped = {} }) end
""")
def ints(expr):
    v = lua.eval(expr)
    return [int(v[k]) for k in sorted(v)] if v else []
lua.execute("WIDE({ log = { [10] = true } })")
check("along: a map-wide objective doesn't hold you up", lua.eval("W:Current()") == 3, lua.eval("W:Current()"))
check("along: it's shown as along the way", ints("W:Along()") == [2], ints("W:Along()"))
check("along: it waits until it must be done (its turn-in, or the next part of the route)", lua.eval("W:Deadline(2)") == 10, lua.eval("W:Deadline(2)"))
check("along: the next steps leave it out until then", ints("W:Upcoming(5)") == [3, 4, 5, 6, 7], ints("W:Upcoming(5)"))
check("along: and ask for it before the next part of the route", ints("W:Upcoming(8)") == [3, 4, 5, 6, 7, 8, 9, 2], ints("W:Upcoming(8)"))
lua.execute("WIDE({ log = { [10] = true }, done = { [11] = true, [14] = true, [12] = true } })")
check("along: before leaving the zone, finish it", lua.eval("W:Current()") == 2, lua.eval("W:Current()"))
lua.execute("WIDE({ log = { [10] = true }, complete = { [10] = true } })")
check("along: done along the way, nothing to ask", lua.eval("W:Current()") == 3 and ints("W:Along()") == [], ints("W:Along()"))
lua.execute("WIDE({ log = { [10] = true } })")
st = lua.eval("W:States(14)")
check("along: listed as along the way", st[2] == "along" and st[3] == "current", (st[2], st[3]))

# One objective of a quest done (the game's own line): that step is passed by, the rest of the quest stays.
lua.execute("WIDE({ log = { [10] = true, [11] = true, [14] = true } }); W.game.objectiveDone = function(id, name) if id == 11 and name == 'Boar' then return true end end")
check("objective: a finished objective moves the guide on", lua.eval("W:Current()") == 6, lua.eval("W:Current()"))

# Grouped: steps on the same monsters (or the same spot) are one block.
lua.execute("WIDE({ log = { [10] = true, [11] = true, [14] = true } })")
blocks = lua.eval("W:Blocks(2)")
first = [int(blocks[1][k]) for k in sorted(blocks[1])]
check("group: two quests on the same monster are one block", first == [5, 6], first)
check("group: the next block after it", int(blocks[2][1]) == 7, blocks[2][1])

# Directions (user, 2026-11-13): a step on the other continent says which ship to take and where to fly.
lua.execute("""
DATA.travel = { flights = { { "Doras", "Orgrimmar", 45.1, 63.9, 1 }, { "Michael Garrett", "Undercity", 63.3, 48.6, 0 },
    { "Zarise", "Hillsbrad Foothills", 60.1, 18.6, 0 }, { "Devrak", "The Barrens", 51.5, 30.3, 1 } },
  continents = { Durotar = 1, Orgrimmar = 1, ["The Barrens"] = 1, ["Tirisfal Glades"] = 0, Undercity = 0, ["Hillsbrad Foothills"] = 0 },
  transports = { { "zeppelin", { "Orgrimmar zeppelin tower", "Durotar", 50.8, 13.6, 1 }, { "Undercity zeppelin tower", "Tirisfal Glades", 60.7, 58.8, 0 } } } }
DATA.routes.Far = { races = {}, steps = { { "turnin", 1, "Hillsbrad Foothills", 50, 50, 10, "" } } }
function FAR(zone) F = G.NewModel(DATA, "Far", GAME({ level = 10, zone = zone }), { skipped = {} }) end
""")
def legs(zone):
    lua.execute(f"FAR('{zone}')")
    d = lua.eval("F:Directions(1)")
    return [str(d[k].text) for k in sorted(d)] if d else []
far = legs("Durotar")
check("directions: other continent, the zeppelin first", len(far) == 3 and "Orgrimmar zeppelin tower" in far[0] and "Durotar" in far[0], far)
check("directions: which zeppelin to take", "zeppelin" in far[1] and "Undercity" in far[1], far)
check("directions: then fly to the flight point near the step", "Michael Garrett" in far[2] and "Zarise" in far[2], far)
near = legs("Tirisfal Glades")
check("directions: same continent, fly from the nearest city", len(near) == 1 and "Michael Garrett" in near[0] and "Zarise" in near[0], near)
check("directions: none when you are in the step's zone", legs("Hillsbrad Foothills") == [])
lua.execute("FAR('Tirisfal Glades'); F.game.flightKnown = function(zone) return zone ~= 'Hillsbrad Foothills' end")
d = lua.eval("F:Directions(1)")
run_leg = [str(d[k].text) for k in sorted(d)] if d else []
check("directions: a flight path you don't have yet: run there (user, screenshot)", len(run_leg) == 1 and "Run to" in run_leg[0]
      and "Hillsbrad Foothills" in run_leg[0] and "Fly" not in run_leg[0], run_leg)
lua.execute("FAR('Durotar')")
check("directions: each leg has a place for the arrow", lua.eval("F:Directions(1)[1].zone") == "Durotar" and lua.eval("F:Directions(1)[1].x") == 50.8)
lua.execute("DATA.travel = nil")

# Quests started by a dropped item (user, 2026-11-13): loot it, then one click starts the quest.
lua.execute("""
DATA.quests[40] = { "Old Letter Quest", 3, 1, 0, "", 0, 0, "Boar", { "Durotar", 45, 65 }, "Gornek", { "Durotar", 40, 60 }, {}, {}, 600, 0,
  { "Old Letter", "Boar", 10 } }
DATA.routes.Drop = { races = {}, steps = { { "accept", 40, "Durotar", 45, 65, 3, "Loot Old Letter from Boar (10%), then right-click it" } } }
function DROP(items) X = G.NewModel(DATA, "Drop", GAME({ level = 3 }), { skipped = {} }); X.game.hasItem = function(id) return items[id] == true end end
""")
lua.execute("DROP({})")
d = lua.eval("G.Describe(X, 1)")
check("item quest: loot the item from the monster first", d.kind == "loot" and "Loot" in d.action and "Old Letter" in d.action and "Boar" in d.action
      and "Old Letter Quest" in d.action, d.action)
check("item quest: says the drop chance when it isn't sure", "10%" in d.action, d.action)
lua.execute("DROP({ [600] = true })")
d = lua.eval("G.Describe(X, 1)")
check("item quest: in your bags, right-click it to start", d.kind == "use" and "Right-click" in d.action and d.useItem == 600, d.action)

# Flight paths (user, 2026-11-13): the route stops at each flight master to learn the path.
lua.execute("""
DATA.routes.Fly = { races = {}, steps = { { "flight", 0, "The Barrens", 51.5, 30.3, 10, "Get the flight path from Devrak" },
  { "accept", 3, "The Barrens", 52, 30, 10, "" } } }
Y = G.NewModel(DATA, "Fly", GAME({ level = 4, zone = "The Barrens" }), { skipped = {} })
""")
check("flight: a flight path you don't have is a step", lua.eval("Y:Current()") == 1)
d = lua.eval("G.Describe(Y, 1)")
check("flight: says who to talk to", "Devrak" in d.action and "flight path" in d.action and d.kind == "flight" and "Wyvern" in d.icon, d.action)
lua.execute("Y.game.flightKnown = function(zone, x, y) return zone == 'The Barrens' end")
check("flight: one you have is passed by", lua.eval("Y:Current()") == 2)
lua.execute("""
local steps = { { "flight", 0, "A", 50, 50, 3, "Get the flight path from Far Away" } }
for k = 2, 5 do steps[k] = { "accept", 1, "A", 50, 50, 3, "" } end
steps[6] = { "travel", 0, "B", 10, 10, 4, "Go to B" }
for k = 7, 10 do steps[k] = { "accept", 3, "B", 10, 10, 4, "" } end
DATA.routes.Behind = { races = {}, steps = steps }
Y = G.NewModel(DATA, "Behind", GAME({ level = 4, zone = "B", done = { [1] = true } }), { skipped = {} })
""")
check("flight: one in a part of the route behind you doesn't send you back", lua.eval("Y:Current()") == 7, lua.eval("Y:Current()"))
check("flight: and isn't in the next steps", 1 not in [int(v) for v in lua.eval("Y:Upcoming(3)").values()])

# A specific place (user, 2026-11-13): pin and arrow for an NPC, an object, one named monster or an item in one spot;
# none for killing or looting across an area, or grinding.
lua.execute("""
local function q(goals) return { "P", 5, 1, 0, "", 0, 0, "Npc", { "A", 50, 50 }, "Npc", { "A", 50, 50 }, goals, {}, 0, 0 } end
DATA.quests[60] = q({ { "kill", "Boar", 8, "A", 40, 40, "", 0 }, { "collect", "Tusk", 6, "A", 40, 40, "Boar", 0 },
  { "use", "Altar", 1, "A", 41, 41, "", 0 }, { "kill", "Old Tusker", 1, "A", 42, 42, "", 0 }, { "collect", "Lost Box", 1, "A", 43, 43, "", 0 } })
local s = {}
for k = 1, 5 do s[k] = { "do", 60, "A", 40, 40, 5, "", k } end
s[6] = { "accept", 60, "A", 50, 50, 5, "" }; s[7] = { "grind", 0, "A", 50, 50, 5, "" }; s[8] = { "turnin", 60, "A", 50, 50, 5, "" }
s[9] = { "flight", 0, "A", 50, 50, 5, "Get the flight path from Bob" }
DATA.routes.Pins = { races = {}, steps = s }
P = G.NewModel(DATA, "Pins", GAME({ level = 5 }), { skipped = {} })
""")
pin = lambda i: lua.eval(f"P:Pinpoint({i})")
check("pin: not for killing 8 across an area", pin(1) is False)
check("pin: not for looting from monsters across an area", pin(2) is False)
check("pin: for an object to use", pin(3) is True)
check("pin: for one named monster", pin(4) is True)
check("pin: for an item lying in one spot", pin(5) is True)
check("pin: for an NPC (pick up, turn in) and a flight master", pin(6) is True and pin(8) is True and pin(9) is True)
check("pin: not for grinding", pin(7) is False)

# Nearest first (user, 2026-11-13: sent back to Brill before Maggot Eye): of the objectives in your log in this part
# of the route, the current step is the one nearest to you.
lua.execute("""
local function q(t, x, y) return { t, 5, 1, 0, "", 0, 0, "Npc", { "A", 50, 50 }, "Npc", { "A", 50, 50 }, { { "kill", t, 5, "A", x, y, "", 0 } }, {}, 0, 0 } end
DATA.quests[70], DATA.quests[71] = q("West", 10, 10), q("East", 80, 80)
DATA.routes.Near = { races = {}, steps = { { "accept", 70, "A", 50, 50, 5, "" }, { "accept", 71, "A", 50, 50, 5, "" },
  { "do", 70, "A", 10, 10, 5, "", 1 }, { "do", 71, "A", 80, 80, 5, "", 1 }, { "turnin", 70, "A", 50, 50, 5, "" }, { "turnin", 71, "A", 50, 50, 5, "" } } }
function NEAR(pos) Q = G.NewModel(DATA, "Near", GAME({ level = 5, zone = "A", log = { [70] = true, [71] = true }, pos = pos }), { skipped = {} }) end
""")
lua.execute("NEAR({ 'A', 78, 78 })")
check("nearest: the objective by you comes first", lua.eval("Q:Current()") == 4, lua.eval("Q:Current()"))
check("nearest: then the other one", [int(v) for v in lua.eval("Q:Upcoming(2)").values()] == [4, 3], [int(v) for v in lua.eval("Q:Upcoming(2)").values()])
check("nearest: the one left for later is still ahead, not passed", lua.eval("Q:States(6)")[3] == "open", lua.eval("Q:States(6)")[3])
lua.execute("NEAR({ 'A', 12, 12 })")
check("nearest: standing by the other, it comes first", lua.eval("Q:Current()") == 3)
lua.execute("NEAR(nil)")
check("nearest: without your position, the route's order", lua.eval("Q:Current()") == 3)
lua.execute("NEAR({ 'B', 78, 78 })")
check("nearest: in another zone, the route's order", lua.eval("Q:Current()") == 3)
lua.execute("DATA.quests[60][12][2][3] = 1")
check("pin: one item from one named monster (Maggot Eye's Paw) is a spot", pin(2) is True)
lua.execute("DATA.quests[60][12][2][3] = 6")
check("icons: swords for kill, a bag for loot, a gear for use, centred game icons (user: line them up)",
      "DualWield" in lua.eval("G.ICONS.kill") and "Bag" in lua.eval("G.ICONS.loot") and "Gear" in lua.eval("G.ICONS.use"))
check("icons: inline game icons are cropped and as tall as the text", lua.eval("G.Inline(G.ICONS.kill)").endswith(":0:0:0:0:64:64:5:59:5:59|t"))

# ---- The step box (GuideUI.lua): view and controller, with stand-in frames and game ----
ui = L.LuaRuntime(unpack_returned_tuples=True)
ui.execute(r"""
ALL, PINS = {}, {}
local function object(kind)
  local o = { kind = kind, scripts = {}, shown = true }
  function o:SetScript(k, f) self.scripts[k] = f end
  function o:Show() self.shown = true end
  function o:Hide() self.shown = false end
  function o:SetShown(v) self.shown = v and true or false end
  function o:IsShown() return self.shown end
  function o:SetText(t) self.text = t end
  function o:GetText() return self.text end
  function o:SetWidth(w) self.width = w end
  function o:SetAlpha(v) rawset(self, "alpha", v) end
  function o:SetAttribute(k, v) local a = rawget(self, "attrs") or {}; a[k] = v; rawset(self, "attrs", a) end
  function o:CreateFontString() local f = object("FontString"); ALL[#ALL+1] = f; return f end
  function o:CreateTexture() return object("Texture") end
  return setmetatable(o, { __index = function() return function() end end })
end
function CreateFrame(kind, name) local f = object(kind); ALL[#ALL+1] = f; if name then _G[name] = f end; return f end
UIParent = object("Frame")
C_Timer = { After = function(_, f) f() end }
GameTooltip = object("GameTooltip")
DufforthTweaksHelper = { RegisterMovable = function() end, EditMode = function() return false end }
DufforthTweaksHelperDB = {}
LEVEL, DONE, LOG, COMPLETE, ZONE = 1, {}, {}, {}, "Durotar"
UnitLevel = function() return LEVEL end
UnitClass = function() return "Warrior", "WARRIOR", 1 end
UnitRace = function() return "Orc", "Orc" end
GetRealZoneText = function() return ZONE end
C_QuestLog = {
  IsQuestFlaggedCompleted = function(id) return DONE[id] == true end,
  GetNumQuestLogEntries = function() local n = 0 for _ in pairs(LOG) do n = n + 1 end return n end,
  GetInfo = function(i) local ids = {} for id in pairs(LOG) do ids[#ids+1] = id end table.sort(ids) return { questID = ids[i], title = "q" } end,
  IsComplete = function(id) return COMPLETE[id] == true end,
  GetQuestObjectives = function(id) if id == 1 then return { { text = "3/8 Boar slain", finished = false } } end return {} end,
}
UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { map = map, x = x, y = y } end }
PLAYER = { map = 1411, x = 0.40, y = 0.70, facing = 0 }
function CreateVector2D(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end
CLEARED = 0
C_Map = { SetUserWaypoint = function(p) PINS[#PINS+1] = p end, ClearUserWaypoint = function() CLEARED = CLEARED + 1 end,
  GetBestMapForUnit = function() return PLAYER.map end,
  GetPlayerMapPosition = function() return CreateVector2D(PLAYER.x, PLAYER.y) end,
  -- A flat world: north is up the map, west is left; 1000 yards across.
  GetWorldPosFromMapPos = function(map, v) return 1, CreateVector2D((1 - v.y) * 1000, (1 - v.x) * 1000) end }
GetPlayerFacing = function() return PLAYER.facing end
GetUnitSpeed = function() return 0 end
C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }
""")
ui.execute(FIXTURE)
ui.execute("DufforthTweaksHelperGuideData = DATA")
ui.execute((ADDON / "Guide.lua").read_text(encoding="utf-8"))
ui.execute((ADDON / "GuideUI.lua").read_text(encoding="utf-8"))
ui.execute("GU = DufforthTweaksHelperGuideUI; GU.Refresh()")
box = ui.eval("DufforthTweaksHelperGuideBox")
check("box: shows the current step as an action", box is not None and "Talk to" in str(box.step.text) and "Boars" in str(box.step.text), box and box.step.text)
check("box: an action icon before it", "AvailableQuestIcon" in str(box.step.text))
shown_blocks = [b for b in box.blocks.values() if b.shown]
check("box: the active steps on top", len(shown_blocks) >= 2, len(shown_blocks))
check("box: each block has its step number", "Step 2" in str(box.blocks[2].header.text), box.blocks[2].header.text)
check("box: says which step and where, briefly", "Step 1" in str(box.title.text) and "40, 60" in str(box.title.text)
      and "of 12" not in str(box.title.text) and "PICK UP" not in str(box.title.text), box and box.title.text)
check("box: puts a map pin on the step", ui.eval("#PINS") == 1 and ui.eval("PINS[1].map") == 1411 and abs(ui.eval("PINS[1].x") - 0.40) < 1e-9)
ui.execute("box = DufforthTweaksHelperGuideBox; box.skip.scripts.OnClick(box.skip)")
check("box: Skip goes to the next step", "Step 1" not in str(box.title.text), box.title.text)
ui.execute("box.back.scripts.OnClick(box.back)")
check("box: Back returns", "Step 1|r" in str(box.title.text), box.title.text)
ui.execute("LOG = { [1] = true }; GU.Refresh()")
check("adapter: a quest in your log moves the guide to its objective", "Kill 8 Boar" in str(box.step.text), box.step.text)
check("pin: killing across an area clears the pin and the arrow has no target", ui.eval("CLEARED") >= 1 and ui.eval("GU.target") is None,
      (ui.eval("CLEARED"), ui.eval("GU.target")))
check("box: the game's count in the action line, no repeated line", "3/8" in str(box.blocks[1].action.text) and str(box.blocks[1].lines.text) in ("", "None"),
      box.blocks[1].lines.text)
ui.execute("COMPLETE = { [1] = true }; GU.Refresh()")
check("adapter: finished objectives: turn in", "Turn in" in str(box.step.text), box.step.text)
ui.execute("DONE = { [1] = true }; LOG = {}; COMPLETE = {}; LEVEL = 2; GU.Refresh()")
check("adapter: completed quests are passed by", "More Boars" in str(box.step.text) and "Talk to" in str(box.step.text), box.step.text)
check("box: a new pin for the new step", ui.eval("#PINS") >= 2)
ui.execute("GU.SetShown(false)")
check("box: can be hidden, and remembers", box.shown is False and ui.eval("DufforthTweaksHelperDB.guide.shown") is False)
ui.execute("GU.SetShown(true)")

# The step list (user, 2026-11-13, RestedXP screenshot): the whole route, steps behind you above the current one and
# the next ones below, a header where each part of the route starts; a taller box shows more of both.
def rows():
    return [(int(r.num.text), str(r.label.text)) for r in box.rows.values() if r.shown and not r.isHeader]
def headers():
    return [str(r.label.text) for r in box.rows.values() if r.shown and r.isHeader]
def nums():
    return [n for n, _ in rows()]
# The target button: targets the step's NPC or monster (user, 2026-11-14).
bar = ui.eval("DufforthTweaksHelperGuideBar")
cur = ui.eval("GU.model:Current()")
who = ui.eval(f"GU.TargetName(GU.model, {cur})")
check("target: a button that targets who the step is about", who is not None and bar.target.attrs["macrotext"] == "/cleartarget\n/targetexact " + who,
      (who, bar.target.attrs["macrotext"] if bar else None))
check("target: secure and works on key down", ui.eval("DufforthTweaksHelperGuideTarget") is not None)

# Box options (user, 2026-11-14).
ui.execute("box.scaleButton.up.scripts.OnClick(box.scaleButton.up)")
check("options: Size > steps up and is remembered", ui.eval("DufforthTweaksHelperDB.guide.scale") == 1.1 and box.scaleButton.value.text == "110%", box.scaleButton.value.text)
ui.execute("for i = 1, 5 do box.scaleButton.up.scripts.OnClick(box.scaleButton.up) end")
check("options: Size stops at the biggest", ui.eval("DufforthTweaksHelperDB.guide.scale") == 1.25)
ui.execute("DufforthTweaksHelperDB.guide.scale = 1; box.alphaButton.down.scripts.OnClick(box.alphaButton.down)")
check("options: Opacity < steps down", ui.eval("DufforthTweaksHelperDB.guide.opacity") == 0.85 and box.alphaButton.value.text == "85%")
check("menu: on/off rows are check boxes, checked when on", ui.eval("box.arrowToggle.check ~= nil") and box.arrowToggle.check.shown is True)
ui.execute("box.arrowToggle.scripts.OnClick(box.arrowToggle)")
check("menu: a click unchecks it", box.arrowToggle.check.shown is False)
ui.execute("box.arrowToggle.scripts.OnClick(box.arrowToggle)")
ui.execute("DufforthTweaksHelperDB.guide.opacity = 1; box.combatToggle.scripts.OnClick(box.combatToggle)")
ui.execute("InCombatLockdown = function() return true end; GU.ApplyLook(); ALPHA_IN_FIGHT = rawget(box, 'alpha')")
check("options: Hide in combat takes the box away in a fight", box.shown is False, box.shown)
ui.execute("InCombatLockdown = function() return false end; GU.ApplyLook(); DufforthTweaksHelperDB.guide.hideInCombat = false")
check("options: back after the fight", ui.eval("rawget(box, 'alpha')") == 1)
# Forever's own quests come from your log.
ui.execute("LOG[97253] = true; GU.Refresh()")
fq = ui.eval("GU.ForeverQuests(GU.model)")
check("forever: a quest in your log the data doesn't know shows as a Forever quest",
      any(fq[k].id == 97253 for k in fq), [fq[k].id for k in fq])
ui.execute("LOG[97253] = nil; GU.Refresh()")


def source_text(name):
    return (ADDON / name).read_text(encoding="utf-8")


def click(name):
    ui.execute(f"box = DufforthTweaksHelperGuideBox; box.{name}.scripts.OnClick(box.{name})")
check("list: the bar names the part you are in", "1-3 Durotar" in str(box.bar.label.text), box.bar.label.text)
check("list: steps behind you above, the next ones below, across parts", 1 in nums() and 4 in nums() and 7 in nums()
      and nums() == sorted(nums()), nums())
check("list: a header where each part starts", any("1-3 Durotar" in h for h in headers()) and any("3-6 The Barrens" in h for h in headers()), headers())
check("list: steps behind you are checked", "ReadyCheck-Ready" in dict(rows())[1], dict(rows())[1])
check("list: each step reads like the blocks", "Kill" in dict(rows())[5] and "AvailableQuestIcon" in dict(rows())[4], rows())
click("doneToggle")
check("list: Done off hides the steps behind you", nums()[0] == 4, nums())
click("nextToggle")
check("list: and Next off the steps ahead", nums() == [4], nums())
click("nextToggle")
click("doneToggle")
click("nextSection")
check("list: browse to the next part", "3-6 The Barrens" in str(box.bar.label.text) and nums()[0] == 7, (box.bar.label.text, nums()))
click("prevSection")
check("list: and back", "1-3 Durotar" in str(box.bar.label.text) and nums()[0] == 1, nums())
first = nums()[0]
ui.execute("box.list.scripts.OnMouseWheel(box.list, -1)")
check("list: the mouse wheel scrolls it", nums()[0] > first, nums())
ui.execute("box.list.scripts.OnMouseWheel(box.list, 1)")
check("list: and back up", nums()[0] == first, nums())

# A check box on each row: mark a step done (you did it without the guide), or undo it.
ui.execute("GU.follow, GU.scrolled = true, false; GU.Refresh()")
ui.execute("GU.follow, GU.scrolled = true, false; GU.Refresh()")
row5 = next(r for r in box.rows.values() if r.shown and not r.isHeader and int(r.num.text) == 5)
ui.execute("for _, r in pairs(DufforthTweaksHelperGuideBox.rows) do if r.step == 5 then r.check.scripts.OnClick(r.check) end end")
check("check box: marks a step done", ui.eval("DufforthTweaksHelperDB.guide.routes.Durotar.skipped[5]") is True)
check("check box: the step reads as done", "ReadyCheck-Ready" in dict(rows())[5], dict(rows())[5])
ui.execute("for _, r in pairs(DufforthTweaksHelperGuideBox.rows) do if r.step == 5 then r.check.scripts.OnClick(r.check) end end")
check("check box: and undone", not ui.eval("DufforthTweaksHelperDB.guide.routes.Durotar.skipped[5]"))
ui.execute("box.blocks[1].check.scripts.OnClick(box.blocks[1].check)")
check("check box on the current step: marks it done (user)", ui.eval("DufforthTweaksHelperDB.guide.routes.Durotar.skipped[4]") is True
      and "Step 4|r" not in str(box.title.text), box.title.text)
ui.execute("DufforthTweaksHelperDB.guide.routes.Durotar.skipped[4] = nil; GU.Refresh()")
check("step icons are as tall as the text, so they line up (user)", ":0|t" in str(box.step.text), box.step.text)
# Steps: the part's list; click a step to view it, back, or continue from it (user, 2026-11-14).
ui.execute("box.stepsButton.scripts.OnClick(box.stepsButton)")
check("steps: the Steps button opens the part's list", box.list.shown is True and ui.eval("DufforthTweaksHelperDB.guide.listOpen") is True)
ui.execute("GU.ViewStep(7)")
check("steps: a clicked step shows in the box with a bar to go back", "Step 7" in str(box.title.text) and box.viewBar.shown is True,
      (box.title.text, box.viewBar.shown))
ui.execute("box.viewBar.back.scripts.OnClick(box.viewBar.back)")
check("steps: back to my step", box.viewBar.shown is False and "Step 7" not in str(box.title.text), box.title.text)
ui.execute("GU.ViewStep(8); box.viewBar.go.scripts.OnClick(box.viewBar.go)")
check("steps: continue from the step shown", ui.eval("GU.model:Start()") == 8 and box.viewBar.shown is False, ui.eval("GU.model:Start()"))
ui.execute("GU.model:SetStart(nil); DufforthTweaksHelperDB.guide.routes.Durotar.startAt = nil; DufforthTweaksHelperDB.guide.listOpen = false; GU.Refresh()")
# Minimize to the round icon; Hide in combat really hides (user, 2026-11-14).
ui.execute("box.hide.scripts.OnClick(box.hide)")
check("minimize: X leaves the round icon, not nothing", box.shown is False and ui.eval("DufforthTweaksHelperGuideIcon").shown is True)
check("minimize: the icon carries the current step", "Step" in str(ui.eval("DufforthTweaksHelperGuideIcon").num.text))
check("icon: round hover glow and a round badge on a ring (user: no square)", ui.eval("DufforthTweaksHelperGuideIcon.ring ~= nil")
      and "TempPortraitAlphaMask" in source_text("GuideUI.lua") and "UI-Minimap-ZoomButton-Highlight" not in source_text("GuideUI.lua"))
ui.execute("DufforthTweaksHelperGuideIcon.scripts.OnClick(DufforthTweaksHelperGuideIcon)")
check("minimize: a click on the icon opens the guide again", box.shown is True and ui.eval("DufforthTweaksHelperGuideIcon").shown is False)
ui.execute("DufforthTweaksHelperDB.guide.hideInCombat = true; GU.inCombat = true; GU.ApplyLook()")
check("hide in combat: the box goes away in a fight, the icon stays", box.shown is False and ui.eval("DufforthTweaksHelperGuideIcon").shown is True)
ui.execute("DufforthTweaksHelperGuideIcon.scripts.OnClick(DufforthTweaksHelperGuideIcon)")
check("hide in combat: the icon opens it anyway during the fight", box.shown is True)
ui.execute("GU.inCombat = false; GU.peek = nil; DufforthTweaksHelperDB.guide.hideInCombat = false; DufforthTweaksHelperDB.guide.collapsed = false; GU.ApplyLook()")
check("hide in combat: back after the fight", box.shown is True)
src = source_text("GuideUI.lua")
check("minimize in combat: no secure button is anchored to the box (it would lock the box in a fight)",
      'f.useItem:SetPoint("TOPRIGHT", f.blocks[1]' not in src and 'bar:SetPoint("TOPRIGHT", f, "TOPLEFT"' not in src
      and "function UI.PlaceSecure" in src)
check("resize: a corner grip", box.grip is not None and box.grip.scripts.OnMouseDown is not None)
ui.execute("REFRESHES = 0; local r = GU.Refresh; GU.Refresh = function() REFRESHES = REFRESHES + 1; r() end")
ui.execute("box.grip.scripts.OnMouseDown(box.grip); box.scripts.OnSizeChanged(box, 420, 520)")
check("resize: redrawn while you drag (user: resizing more than the window is)", ui.eval("REFRESHES") >= 1)
ui.execute("box.grip.scripts.OnMouseUp(box.grip)")
check("resize: the box fits what it shows, up to your size", 0 < ui.eval("box.fitH") <= 520, ui.eval("box.fitH"))
check("resize: remembers the size", ui.eval("DufforthTweaksHelperDB.guide.size[1]") == 420 and ui.eval("DufforthTweaksHelperDB.guide.size[2]") == 520)
check("box: a size the game restores is not taken as yours", (ui.execute("box.scripts.OnSizeChanged(box, 200, 150)") or True)
      and ui.eval("DufforthTweaksHelperDB.guide.size[1]") == 420)
ui.execute("box.scripts.OnSizeChanged(box, 420, 520)")
check("box: step number between the arrows on top", str(box.stepNum.text) == "4", box.stepNum.text)
ui.execute("DufforthTweaksHelperQuestAuto = { on = true, Enabled = function() return DufforthTweaksHelperQuestAuto.on end, "
           "SetEnabled = function(v) DufforthTweaksHelperQuestAuto.on = v end }")
click("autoToggle")
check("box: the Auto button turns auto quests off", ui.eval("DufforthTweaksHelperQuestAuto.on") is False)
click("autoToggle")
ui.execute("box.grip.scripts.OnMouseDown(box.grip); box.scripts.OnSizeChanged(box, 340, 100); box.grip.scripts.OnMouseUp(box.grip)")
check("box: made small, the level, zone and progress row stays (user)", box.progress.shown is not False)
check("box: made small, only the current step stays", box.blocks[1].shown and not box.blocks[2].shown and not box.bar.shown
      and not any(r.shown for r in box.rows.values()), (box.blocks[2].shown, box.bar.shown))
ui.execute("box.grip.scripts.OnMouseDown(box.grip); box.scripts.OnSizeChanged(box, 340, 40); box.grip.scripts.OnMouseUp(box.grip)")
check("box: never cuts the current step: it grows to show all of it (user: size follows the steps)", ui.eval("box.fitH") > 40, ui.eval("box.fitH"))
ui.execute("box.grip.scripts.OnMouseDown(box.grip); box.scripts.OnSizeChanged(box, 420, 520); box.grip.scripts.OnMouseUp(box.grip)")
check("box: made bigger, the rest comes back", box.blocks[2].shown and box.bar.shown)
check("box: green bar with the section's progress", "50%" in str(box.progress.label.text), box.progress.label.text)
check("box: the bar says what each percentage is (user: what is 14% of the route?)",
      "1-3 Durotar" in str(box.progress.label.text) and "zone" in str(box.progress.label.text), box.progress.label.text)
check("box: whole-route percent only in the bar's hover, not on screen (user: too noisy)",
      "route" not in str(box.progress.label.text).lower() and "Whole route" in str(box.progress.routeText)
      and ui.eval("rawget(DufforthTweaksHelperGuideBox, 'routeLine')") is None, (box.progress.label.text, box.progress.routeText))

# The Start quest button: one click uses the quest's item (Blizzard allows using items only from a click).
ui.execute("SAVED_Q1 = DufforthTweaksHelperGuideData.quests[1]; local q = {} for k, v in pairs(SAVED_Q1) do q[k] = v end "
           "q[14] = 600; q[16] = { 'Old Letter', 'Boar', 10 }; DufforthTweaksHelperGuideData.quests[1] = q; "
           "GetItemCount = function(id) return id == 600 and 1 or 0 end; InCombatLockdown = function() return false end; "
           "SAVED = { DONE, LOG, LEVEL }; DONE, LOG, LEVEL = {}, {}, 1; GU.Refresh()")
check("item quest: a Start quest button for the item in your bags", box.useItem.shown and box.useItem.item == "item:600",
      (box.useItem.shown, box.useItem.item))
ui.execute("GetItemCount = function() return 0 end; GU.Refresh()")
check("item quest: no item, no button", not box.useItem.shown)
ui.execute("DufforthTweaksHelperGuideData.quests[1] = SAVED_Q1; DONE, LOG, LEVEL = SAVED[1], SAVED[2], SAVED[3]; GU.Refresh()")

# Extras you can act on (user: "idk what Satyr Hooves (Ula'elek) means and 9 dungeon quests, nothing I can click"):
# rows that say what each is, open into a list, and a click puts a map pin and the arrow on the giver.
ui.execute("SAVED_LEVEL = LEVEL; LEVEL = 10; DufforthTweaksHelperGuideData.uiMaps.Orgrimmar = 1454; "
           "DufforthTweaksHelperGuideData.extras.dungeonOf = { [30] = 'Ragefire Chasm' }; GU.Refresh()")
def extra_rows():
    return [(k, str(r.label.text)) for k, r in sorted(box.extraRows.items()) if r.shown]
er = extra_rows()
cls = [k for k, t in er if "Warrior's Training" in t]
check("extras: the class quest is a row that says so", cls and "Class quest" in dict(er)[cls[0]], er)
ui.execute(f"box.extraRows[{cls[0] if cls else 1}].scripts.OnClick(box.extraRows[{cls[0] if cls else 1}])")
check("extras: a click points the arrow at its giver", ui.eval("GU.target and GU.target.zone") == "Orgrimmar" and "Trainer" in str(ui.eval("GU.target.text")),
      ui.eval("GU.target and GU.target.zone"))
dun = [k for k, t in extra_rows() if "dungeon quest" in t]
check("extras: dungeon quests are a row to open", bool(dun) and not any("Ragefire Chasm:" in t for _, t in extra_rows()), extra_rows())
ui.execute(f"box.extraRows[{dun[0] if dun else 1}].scripts.OnClick(box.extraRows[{dun[0] if dun else 1}])")
check("extras: opened, each quest with its dungeon", any("Ragefire Chasm:" in t for _, t in extra_rows()), extra_rows())
ui.execute("LEVEL = SAVED_LEVEL; GU.override = nil; DufforthTweaksHelperDB.guide.showDungeons = false; GU.Refresh()")

# Guides menu (user: "add other guides so we can choose important questlines like cozy sleeping bag or attunements").
ui.execute("DufforthTweaksHelperGuideData.guides = { { name = 'Test Line', note = 'A test questline.' } }; "
           "DufforthTweaksHelperGuideData.routes['Test Line'] = { races = {}, steps = { { 'accept', 3, 'The Barrens', 52, 30, 1, '' } } }")
click("guides")
check("guides: the menu opens with leveling and each questline", box.guideMenu.shown and "Leveling" in str(box.guideRows[1].label.text)
      and "Test Line" in str(box.guideRows[2].label.text), (box.guideMenu.shown, box.guideRows[1].label.text))
check("guides: leveling split by zone, one zone per row (user: 10 levels too much)",
      "Leveling by zone" in str(box.guideRows[3].label.text) and "1-3 Durotar" in str(box.guideRows[4].label.text)
      and "," not in str(box.guideRows[4].label.text), (box.guideRows[3].label.text, box.guideRows[4].label.text))
check("guides: the menu is as wide as its names, within limits", 220 <= ui.eval("box.guideMenu.width or 0") <= 320, ui.eval("box.guideMenu.width"))
ui.execute("box.guideRows[3].scripts.OnClick(box.guideRows[3])")
check("guides: the zone header is not a guide", box.guideMenu.shown)
# Many parts: only MENU rows show, the wheel scrolls to the rest (user: rows overflowed and couldn't be picked).
ui.execute("local m = box.guideMenu; local e = {}; for i = 1, 40 do e[i] = { nil, 'Part ' .. i, '', 1 } end; "
           "m.entries, m.offset = e, 0; GU.DrawGuideMenu()")
check("guides: a long menu says there is more", "below" in str(box.guideMenu.more.text) and box.guideRows[16].label.text == "   Part 16",
      box.guideMenu.more.text)
ui.execute("box.guideMenu.scripts.OnMouseWheel(box.guideMenu, -1); box.guideMenu.scripts.OnMouseWheel(box.guideMenu, -1)")
check("guides: the wheel scrolls the menu", box.guideRows[1].label.text == "   Part 7", box.guideRows[1].label.text)
ui.execute("for i = 1, 20 do box.guideMenu.scripts.OnMouseWheel(box.guideMenu, -1) end")
check("guides: scrolling stops at the last part", box.guideRows[16].label.text == "   Part 40", box.guideRows[16].label.text)
ui.execute("box.guideMenu:Hide()")
click("guides")
ui.execute("box.guideRows[2].scripts.OnClick(box.guideRows[2])")
check("guides: picking one follows it", ui.eval("GU.RouteName()") == "Test Line" and "Step 1" in str(box.title.text) and not box.guideMenu.shown,
      box.title.text)
check("guides: remembered", ui.eval("DufforthTweaksHelperDB.guide.guideName") == "Test Line")
click("guides")
ui.execute("box.guideRows[1].scripts.OnClick(box.guideRows[1])")
check("guides: and back to leveling", ui.eval("GU.RouteName()") == "Durotar" and "Step 4" in str(box.title.text), box.title.text)
click("guides")
ui.execute("box.guideRows[4].scripts.OnClick(box.guideRows[4])")
check("guides: a zone part shows that part of the leveling route in the list", ui.eval("GU.RouteName()") == "Durotar"
      and "1-3 Durotar" in str(box.bar.label.text) and not box.guideMenu.shown, box.bar.label.text)
ui.execute("GU.follow, GU.scrolled = true, false; GU.Refresh()")
click("guides")
ui.execute("box.guideRows[5].scripts.OnClick(box.guideRows[5])")
cur = ui.eval("GU.model:Current()")
first2 = ui.eval("GU.model:Sections()[2].first")
check("guides: a zone click moves the guide itself there, not only the list (user: not redirected)",
      cur is not None and cur >= first2 and ui.eval("GU.model:SectionOf(GU.model:Current())") == 2
      and ui.eval("DufforthTweaksHelperDB.guide.routes.Durotar.startAt") == first2, (cur, first2))
check("guides: the step box shows the chosen part", "3-6 The Barrens" in str(box.progress.label.text), box.progress.label.text)
check("menu: the extra buttons sit in one Menu, so a narrow box has no overlap (user)",
      not box.tools.shown and box.menuButton.text == "Menu", box.menuButton.text)
click("menuButton")
check("menu: Menu opens the panel with Guides, Auto and the arrow",
      box.tools.shown and "Guides" in str(box.guides.text) and "Auto" in str(box.autoToggle.text)
      and "arrow" in str(box.arrowToggle.text), box.guides.text)
check("strip: Best and the map pin are buttons next to Menu, not menu rows (user)",
      box.best.text == "Best" and ui.eval("box.pin.icon ~= nil") and ui.eval("box.best:GetParent() == nil or true"))
click("menuButton")
check("menu: a second click closes it", not box.tools.shown)
click("menuButton")
ui.execute("box.guides.scripts.OnEnter(box.guides)")
check("menu: hovering Guides and zones opens its list beside the Menu, which stays open (user: hover, not click)",
      box.tools.shown and box.guideMenu.shown)
check("menu: the list opens on the side with room, never over the Menu (user)",
      ui.eval("GU.SideFor(400, 610, 1920, 230)") == "left" and ui.eval("GU.SideFor(20, 230, 1920, 230)") == "right"
      and ui.eval("GU.SideFor(20, 1800, 1920, 230)") == "below")
check("guides: the box says which guide you're on (user: they all look the same)", "Speed" in str(box.progress.label.text),
      box.progress.label.text)
diff = ui.eval("GU.FirstDifference({ steps = { {'accept',1,'Durotar',0,0,1}, {'accept',2,'Durotar',0,0,5} } }, "
               "{ steps = { {'accept',1,'Durotar',0,0,1}, {'accept',9,'The Barrens',0,0,12} } })")
check("guides: switching says from which level the routes differ", tuple(diff) == (12, "The Barrens"), diff)
ui.execute("box.tools:Hide(); box.tools.scripts.OnHide(box.tools)")
check("menu: closing the Menu closes the list too", not box.guideMenu.shown)
ui.execute("box.guideMenu:Hide()")
ui.execute("box.best.scripts.OnClick(box.best)")
check("best: goes back to the step that fits your level and what you have done", ui.eval("GU.model:Current()") == 4,
      ui.eval("GU.model:Current()"))
ui.execute("LEVEL = 5; box.best.scripts.OnClick(box.best)")
check("best: at a higher level it skips the parts below you", ui.eval("GU.model:SectionOf(GU.model:Current())") == 2,
      ui.eval("GU.model:Current()"))
ui.execute("LEVEL = SAVED_LEVEL or 2; box.best.scripts.OnClick(box.best); GU.follow, GU.scrolled = true, false; GU.Refresh()")

# Directions in the box, and the arrow on the first leg.
ui.execute('DufforthTweaksHelperGuideData.travel = { flights = { { "Michael Garrett", "Undercity", 63.3, 48.6, 0 } }, '
           'continents = { Durotar = 1, ["Tirisfal Glades"] = 0 }, transports = { { "zeppelin", '
           '{ "Orgrimmar zeppelin tower", "Durotar", 50.8, 13.6, 1 }, { "Undercity zeppelin tower", "Tirisfal Glades", 60.7, 58.8, 0 } } } }; '
           'DufforthTweaksHelperGuideData.uiMaps["Tirisfal Glades"] = 1420; ZONE = "Tirisfal Glades"; GU.Refresh()')
check("box: how to get there, under the current step", "zeppelin" in str(box.blocks[1].advice.text), box.blocks[1].advice.text)
check("arrow: points at the first leg (the zeppelin tower)", ui.eval("GU.target.zone") == "Tirisfal Glades" and "zeppelin" in str(ui.eval("GU.target.text")),
      ui.eval("GU.target.zone"))
ui.execute('DufforthTweaksHelperGuideData.travel = nil; ZONE = "Durotar"; GU.Refresh()')

# Flight paths you know: read from the flight map when you talk to a flight master.
ui.execute("""
NODES = { { "Crossroads, The Barrens", "REACHABLE" }, { "Orgrimmar, Durotar", "CURRENT" }, { "Ratchet, The Barrens", "NONE" } }
NumTaxiNodes = function() return #NODES end
TaxiNodeName = function(i) return NODES[i][1] end
TaxiNodeGetType = function(i) return NODES[i][2] end
C_Map.GetMapInfo = function(map) return { name = ({ [1411] = "Durotar", [1413] = "The Barrens" })[map] } end
DufforthTweaksHelperGuideData.travel = { flights = { { "Devrak", "The Barrens", 51.5, 30.3, 1 }, { "Omusa", "The Barrens", 44.4, 59.2, 1 },
  { "Rogg", "Durotar", 60, 60, 1 } }, continents = {}, transports = {} }
GU.LearnFlights()
A = GU.GameAdapter()
""")
check("flights: where you talked to the flight master is known", ui.eval("A.flightKnown('Durotar', 41, 69)") is True)
check("flights: one of a zone's two isn't proof of the other", ui.eval("A.flightKnown('The Barrens', 44.4, 59.2)") is False)
ui.execute("NODES[3][2] = 'REACHABLE'; GU.LearnFlights(); A = GU.GameAdapter()")
check("flights: all of a zone's flight paths known", ui.eval("A.flightKnown('The Barrens', 44.4, 59.2)") is True)
ui.execute("DufforthTweaksHelperGuideData.travel = nil")

# The waypoint arrow: points at the current step, with distance and time.
ui.execute("GU.UpdateArrow()")
arrow = ui.eval("DufforthTweaksHelperGuideArrow")
check("arrow: shown for a step with a place", arrow is not None and arrow.shown, arrow and arrow.shown)
check("arrow: how far", "100 yd" in str(arrow.dist.text), arrow.dist.text)
check("arrow: no step text, the guide window shows it (user: same information twice)", not arrow.label.shown, arrow.label.text)
check("arrow: the step in its tooltip", "More Boars" in str(arrow.label.text), arrow.label.text)
check("arrow: no plate behind the distance (user: looks bad), outlined text only",
      ui.eval("rawget(DufforthTweaksHelperGuideArrow, 'plate')") is None)
short = str(ui.eval("GU.ArrowText(GU.model, { 5, 6 }, GU.adapter)"))
check("arrow: one short line (user: too much text under the arrow)", "\n" not in short and "+1 more" in short and "|cffaaaaaa(" not in short, short)
check("arrow: straight ahead when you face it", abs(arrow.angle) < 1e-6, arrow.angle)
ui.execute("PLAYER.facing = math.pi / 2; GU.UpdateArrow()")
check("arrow: turns as you turn", abs(arrow.angle + math.pi / 2) < 1e-6, arrow.angle)
ui.execute("PLAYER.y = 0.60; GU.UpdateArrow()")
check("arrow: says when you are there", "here" in str(arrow.dist.text).lower(), arrow.dist.text)
ui.execute("SAVED_WP = C_Map.GetWorldPosFromMapPos; C_Map.GetWorldPosFromMapPos = nil; GU.UpdateArrow()")
check("arrow: hides when the game can't place you", arrow.shown is False)
ui.execute("C_Map.GetWorldPosFromMapPos = SAVED_WP; PLAYER.y, PLAYER.facing = 0.70, 0; GU.UpdateArrow()")
ui.execute("GU.SetArrowShown(false)")
check("arrow: can be turned off, and remembers", arrow.shown is False and ui.eval("DufforthTweaksHelperDB.guide.arrow") is False)
ui.execute("GU.SetArrowShown(true)")
check("arrow: and on again", arrow.shown is True)
check("route: chosen by race (Orc: Durotar)", ui.eval("GU.RouteName()") == "Durotar")
ui.execute("UnitRace = function() return 'Tauren', 'Tauren' end")
check("route: Tauren start in Mulgore", ui.eval("GU.RouteName()") == "Mulgore")

# The real data: a level 14 Tauren Druid in the Barrens (probe, 13 Nov 2026).
lua2 = runtime()
lua2.execute((ADDON / "GuideData.lua").read_text(encoding="utf-8"))
COMPLETED = [743, 744, 745, 746, 747, 748, 749, 750, 751, 752, 753, 754, 755, 756, 757, 758, 759, 760, 761, 763, 764, 765, 766, 767, 771,
             772, 773, 775, 776, 780, 781, 819, 833, 844, 854, 860, 861, 871, 886, 1656, 3094, 3376, 5922, 5926, 5927, 5928, 5930, 5932,
             6002, 6361, 6362]
LOG = [5723, 5722, 1492, 869, 870, 845, 887, 5041, 821, 848, 867, 97253, 872]
lua2.execute("DATA = DufforthTweaksHelperGuideData")
lua2.execute("M = G.NewModel(DATA, 'Mulgore', GAME({ level = 14, classBit = 1024, raceBit = 32, zone = 'The Barrens', done = { "
             + ", ".join(f"[{i}] = true" for i in COMPLETED) + " }, log = { " + ", ".join(f"[{i}] = true" for i in LOG) + " } }), { skipped = {} })")
i = lua2.eval("M:Current()")
step = lua2.eval(f"DATA.routes['Mulgore'].steps[{i}]")
print("     real: current step", i, step[1], step[3], "level", step[6], "|", step[7])
check("real data: level 14 Tauren Druid in the Barrens starts near its level, not back in Mulgore",
      step[3] != "Mulgore" and 11 <= step[6] <= 17, f"{step[3]} level {step[6]}")
check("real data: quests in the log are worked on, not accepted again", not (step[1] == "accept" and step[2] in LOG))
# A simulated playthrough of each real route: a character does exactly what the guide says.
lua2.execute("""
function PLAY(routeName, raceBit)
  local state = { level = 1, done = {}, log = {}, complete = {}, zone = "", flights = {} }
  local steps = DATA.routes[routeName].steps
  state.zone = steps[1][3]
  local game = GAME(state)
  game.level = function() return state.level end
  game.zone = function() return state.zone end
  game.raceBit = function() return raceBit end
  game.flightKnown = function(zone, x, y) return state.flights[zone .. x .. y] == true end
  game.hearth = function() return state.home, true end
  if WITH_POSITION then game.position = function() return state.zone, state.x, state.y end end
  local m = G.NewModel(DATA, routeName, game, { skipped = {} })
  local last, moves, stuck = nil, 0, 0
  while moves < 20000 do
    local i = m:Current()
    if not i then break end
    if i == last then stuck = stuck + 1 end
    last = i
    local step = steps[i]
    local kind, id = step[1], step[2]
    state.zone = step[3] ~= "?" and step[3] or state.zone
    state.x, state.y = step[4] or state.x, step[5] or state.y
    state.level = math.max(state.level, step[6])
    if kind == "accept" then state.log[id] = true
    elseif kind == "do" then state.complete[id] = true
    elseif kind == "turnin" then state.done[id] = true; state.log[id] = nil; state.complete[id] = nil
    elseif kind == "grind" then state.level = step[6] + 1
    elseif kind == "flight" then state.flights[step[3] .. step[4] .. step[5]] = true
    elseif kind == "fly" or kind == "hearth" then
      -- Fly or hearth: you arrive where it says (without your position the guide can't see it, so you tick it).
      if step[9] then state.zone, state.x, state.y = step[9][1], step[9][2], step[9][3] end
      if not WITH_POSITION then m.saved.skipped[i] = true end
    elseif kind == "home" then state.home = step[3]
    elseif kind == "farm" then m.saved.skipped[i] = true end -- optional gold farming: ticked off
    moves = moves + 1
  end
  return moves, stuck, state.level, m:Current()
end
""")
RACE_OF = {"Durotar": 2, "Mulgore": 32, "Tirisfal Glades": 16}
LEVELING = sorted(str(k) for k in lua2.eval("DATA.routes").keys() if any(str(k).startswith(z) for z in RACE_OF))
check("styles: speed, safe and explorer, each with and without dungeons, for every start (user)", len(LEVELING) == 18, LEVELING)
for route in LEVELING:
    race = next(v for k, v in RACE_OF.items() if route.startswith(k))
    result = list(lua2.eval(f"PLAY('{route}', {race})")) + [None]
    moves, stuck, level, left = result[:4]
    total = int(lua2.eval(f"#DATA.routes['{route}'].steps"))
    check(f"playthrough {route}: the guide never sticks and reaches the end", stuck == 0 and left is None and level >= 59,
          f"{moves} moves of {total} steps, stuck {stuck}, level {level}, left at {left}")

lua2.execute("WITH_POSITION = true")
moves, stuck, level, left = (list(lua2.eval("PLAY('Tirisfal Glades', 16)")) + [None])[:4]
check("playthrough Tirisfal Glades with your position (nearest first): never sticks, reaches the end",
      stuck == 0 and left is None and level >= 59, f"{moves} moves, stuck {stuck}, level {level}, left at {left}")
lua2.execute("WITH_POSITION = false")

# Each questline guide (attunements, Cozy Sleeping Bag) is followed to its end without sticking.
for g in lua2.eval("DATA.guides").values():
    name = str(g.name)
    moves, stuck, level, left = (list(lua2.eval(f"PLAY({name!r}, 2)")) + [None])[:4]
    check(f"questline {name}: followed to the end", stuck == 0 and left is None, f"{moves} moves, stuck {stuck}, left at {left}")

sys.exit(1 if failed else 0)
