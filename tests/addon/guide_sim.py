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
    for _loc in ("Locale.lua", "LocaleES.lua"): lua.execute((__import__("pathlib").Path(__file__).resolve().parents[2] / "addon" / "DufforthTweaksHelper" / _loc).read_text(encoding="utf-8"))
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
# One block for an area's objectives (user, 2026-11-14: "guide is useless if make me do quest 1 by one").
lua.execute("""
local function quest(title, mob, x, y, wide) return { title, 5, 1, 0, "", 0, 0, "A", { "Durotar", 50, 50 }, "A", { "Durotar", 50, 50 },
  { { "kill", mob, 5, "Durotar", x, y, "", wide, {}, 5, 6, 0 } }, {}, 0, 2 } end
DATA.quests[70] = quest("Boars", "Boar", 45, 65, 0); DATA.quests[71] = quest("Scorpids", "Scorpid", 53, 70, 0)
DATA.quests[72] = quest("Far", "Raptor", 75, 95, 0); DATA.quests[73] = quest("Everywhere", "Hyena", 80, 20, 1)
DATA.routes.Area = { races = {}, steps = { { "do", 70, "Durotar", 45, 65, 5, "", 1 }, { "do", 71, "Durotar", 53, 70, 5, "", 1 },
  { "do", 72, "Durotar", 75, 95, 5, "", 1 }, { "do", 73, "Durotar", 80, 20, 5, "", 1 } } }
AM = G.NewModel(DATA, "Area", GAME({ level = 5, log = { [70] = true, [71] = true, [72] = true, [73] = true } }), { skipped = {} })
""")
check("area: objectives in the same area are one block", lua.eval("AM:Together(1, 2)") is True)
check("area: one across the zone is not", lua.eval("AM:Together(1, 3)") is False)
check("area: one all over the zone joins any block", lua.eval("AM:Together(1, 4)") is True)
# The whole trip in the first block (user, 2026-11-14: "i want to see all the steps i should be doing before turn in a
# quest, remember i can do more than one quest at the same time").
lua.execute("""
DATA.routes.Trip = { races = {}, steps = { { "do", 70, "Durotar", 45, 65, 5, "", 1 }, { "do", 72, "Durotar", 75, 95, 5, "", 1 },
  { "do", 71, "Durotar", 53, 70, 5, "", 1 }, { "turnin", 70, "Durotar", 50, 50, 6, "" }, { "do", 73, "Durotar", 80, 20, 6, "", 1 } } }
TM = G.NewModel(DATA, "Trip", GAME({ level = 5, log = { [70] = true, [71] = true, [72] = true, [73] = true } }), { skipped = {} })
TB = TM:Blocks(2)
""")
check("trip: every objective until the next hand-in is in the first block (and the one all over the zone)", lua.eval("#TB[1]") == 4, lua.eval("#TB[1]"))
check("trip: the hand-in is the next block", lua.eval("TM.steps[TB[2][1]][1]") == "turnin")
lua.execute("DATA.quests[73][12][1][8] = 1; TM2 = G.NewModel(DATA, 'Trip', GAME({ level = 5, log = { [70] = true, [71] = true, [72] = true, [73] = true } }), { skipped = {} }); TB2 = TM2:Blocks(2)")
check("trip: objectives all over the zone are in the top block too, so the small box shows the whole trip",
      any(lua.eval(f"TB2[1][{k}]") == 5 for k in range(1, lua.eval("#TB2[1]") + 1)), [lua.eval(f"TB2[1][{k}]") for k in range(1, lua.eval("#TB2[1]") + 1)])
# One row per step, not grouped (user, 2026-11-15: "now idk which step i am, do not group the steps, show all of them in
# different rows"): each trip step is its own block, and the blocks say how many make up the trip.
lua.execute("FB = TM2:Blocks(3, true)")
check("rows: the trip's rows are in step order (user, 2026-11-15: 390, 373, 368 was impossible to follow)",
      [lua.eval(f"FB[{k}][1]") for k in range(1, lua.eval("FB.trip") + 1)] == sorted(lua.eval(f"FB[{k}][1]") for k in range(1, lua.eval("FB.trip") + 1)),
      [lua.eval(f"FB[{k}][1]") for k in range(1, lua.eval("FB.trip") + 1)])
lua.execute("TM3 = G.NewModel(DATA, 'Trip', GAME({ level = 5, log = { [70] = true, [71] = true, [72] = true, [73] = true }, zone = 'Durotar', pos = { 'Durotar', 75, 95 } }), { skipped = {} }); FB3 = TM3:Blocks(3, true)")
order3 = [lua.eval(f"FB3[{k}][1]") for k in range(1, lua.eval("FB3.trip") + 1)]
check("rows: in step order even when you stand by a later objective", order3 == sorted(order3) and lua.eval("TM3:Current()") == 2, (order3, lua.eval("TM3:Current()")))
check("rows: one step per block", all(lua.eval(f"#FB[{k}]") == 1 for k in range(1, lua.eval("#FB") + 1)), [lua.eval(f"#FB[{k}]") for k in range(1, lua.eval("#FB") + 1)])
check("rows: every trip step is there, then the next ones", lua.eval("FB.trip") == 4 and lua.eval("#FB") == 5 and lua.eval("TM2.steps[FB[5][1]][1]") == "turnin", (lua.eval("FB.trip"), lua.eval("#FB")))
lua.execute("DATA.routes.Trip = nil")
lua.execute("for id = 70, 73 do DATA.quests[id] = nil end; DATA.routes.Area = nil")
lua.execute("""
DATA.quests[1][12] = { { "kill", "Boar", 8, "Durotar", 45, 65, "", 0, { { 44, 64 }, { 50, 60 }, { 47, 70 } }, 3, 4, 0 } }
DATA.quests[3][12] = { { "collect", "Raptor Head", 12, "The Barrens", 55, 35, "Raptor", 1, {}, 11, 12, 1 } }
""")
lua.execute("M3 = G.NewModel(DATA, 'Durotar', GAME({ level = 3 }), { skipped = {} })")
# Quests in your log the route doesn't plan (user, 2026-11-14: Chen's Empty Keg starts from a random drop, so it isn't in the
# route; its Savannah Lion Tusks could be done with Prowlers of the Barrens): "also here" and rows of their own.
lua.execute("""
DATA.quests[50] = { "Chen's Empty Keg", 3, 1, 0, "", 0, 0, "Brewmaster Drohn", { "The Barrens", 62, 38 }, "Brewmaster Drohn", { "The Barrens", 62, 38 },
  { { "collect", "Savannah Lion Tusk", 5, "The Barrens", 57, 36, "Savannah Lion", 0, {}, 11, 12, 0 },
    { "collect", "Plainstrider Kidney", 12, "The Barrens", 20, 80, "Fleeting Plainstrider", 1, {}, 11, 12, 0 },
    { "collect", "Thunder Lizard Horn", 5, "The Barrens", 50, 90, "Thunder Lizard", 0, {}, 11, 12, 0 } }, {}, 0, 2 }
AH = G.NewModel(DATA, 'Durotar', GAME({ level = 4, done = { [1] = true, [2] = true }, log = { [3] = true, [50] = true }, zone = 'The Barrens' }), { skipped = {} })
ALSO = AH:AlsoHere(9)
OFF = AH:OffRoute()
""")
also = [str(lua.eval(f"ALSO[{k}].name")) for k in range(1, lua.eval("#ALSO") + 1)]
check("also here: another log quest's objective at the same spot", "Savannah Lion Tusk" in also, also)
check("also here: one all over the zone too", "Plainstrider Kidney" in also, also)
check("also here: not one far away", "Thunder Lizard Horn" not in also, also)
check("also here: not the step's own quest", all(lua.eval(f"ALSO[{k}].quest") != 3 for k in range(1, lua.eval("#ALSO") + 1)))
check("off route: a log quest the route doesn't have gets a row", lua.eval("#OFF") == 1 and lua.eval("OFF[1].id") == 50, lua.eval("#OFF"))
check("off route: the arrow goes to an objective while it's open", lua.eval("OFF[1].x") == 57 and "Savannah Lion Tusk" in str(lua.eval("OFF[1].giver")),
      (lua.eval("OFF[1].x"), lua.eval("OFF[1].giver")))
lua.execute("AH2 = G.NewModel(DATA, 'Durotar', GAME({ level = 4, log = { [50] = true }, complete = { [50] = true } }), { skipped = {} }); OFF2 = AH2:OffRoute()")
check("off route: complete, to the NPC to hand it in", lua.eval("OFF2[1].x") == 62 and "Turn in" in str(lua.eval("OFF2[1].giver")), lua.eval("OFF2[1].giver"))
# No place in our data: ask Questie (user, 2026-11-14: "use the current information that questie is providing").
lua.execute("""
DATA.quests[51] = { "Unplaced", 3, 1, 0, "", 0, 0, "Someone", { "The Barrens", 50, 50 }, "Someone", { "The Barrens", 50, 50 },
  { { "collect", "Odd Thing", 3, "?", nil, nil, "", 0, {}, 0, 0, 0 } }, {}, 0, 2 }
QG = GAME({ level = 4, log = { [51] = true } })
QG.questieSpot = function(id) if id == 51 then return 'The Barrens', 44, 33, 'Odd Thing (Questie)' end end
OFFQ = G.NewModel(DATA, 'Durotar', QG, { skipped = {} }):OffRoute()
DATA.quests[51] = nil
""")
check("off route: no place in our data, Questie's place", lua.eval("OFFQ[1].x") == 44 and "Questie" in str(lua.eval("OFFQ[1].giver")),
      (lua.eval("OFFQ[1].x"), lua.eval("OFFQ[1].giver")))
lua.execute("DATA.quests[50] = nil")

# A route step whose place isn't in our data (Echeyakee, summoned with a horn) takes Questie's (user, 2026-11-14:
# "echeyakee does not have place i said use questie").
lua.execute("""
DATA.quests[60] = { "Echeyakee", 16, 12, 0, "", 0, 0, "Sergra Darkthorn", { "The Barrens", 52, 30 }, "Sergra Darkthorn", { "The Barrens", 52, 30 },
  { { "collect", "Echeyakee's Hide", 1, "The Barrens", 52, 30, "", 0, {}, 0, 0, 0, 1, 0 } }, {}, 0, 2 }
DATA.routes.Gs = { races = {}, steps = { { "do", 60, "The Barrens", 52, 30, 16, "", 1 } } }
EG = GAME({ level = 16, log = { [60] = true }, zone = "The Barrens" })
EG.questieSpot = function(id) if id == 60 then return "The Barrens", 55.4, 17.6, "Echeyakee (Questie)" end end
EM = G.NewModel(DATA, "Gs", EG, { skipped = {} })
EM_NONE = G.NewModel(DATA, "Gs", GAME({ level = 16, log = { [60] = true } }), { skipped = {} })
""")
check("questie place: a guessed step takes Questie's spot", lua.eval("(select(2, EM:Place(1)))") == 55.4 and lua.eval("(select(3, EM:Place(1)))") == 17.6,
      lua.eval("(select(2, EM:Place(1)))"))
check("questie place: so it gets the pin and the arrow", lua.eval("EM:Pinpoint(1)") is True)
check("questie place: the tip says where it came from", "Questie" in str(lua.eval("G.Tip(EM, 1)")), lua.eval("G.Tip(EM, 1)"))
check("questie place: without Questie, still the giver and no pin", lua.eval("(select(2, EM_NONE:Place(1)))") == 52 and lua.eval("EM_NONE:Pinpoint(1)") is False)
# "Nearest first" must use the real place (log, 2026-11-15: Ishamuhale's place was guessed at its giver, where the user stood,
# so it jumped ahead of the route; the arrow then went to Questie's spot across the map).
lua.execute("""
DATA.quests[61] = { "Near", 16, 12, 0, "", 0, 0, "A", { "The Barrens", 50, 50 }, "A", { "The Barrens", 50, 50 },
  { { "kill", "Boar", 5, "The Barrens", 46, 58, "", 0, {}, 0, 0, 0, 0, 0 } }, {}, 0, 2 }
DATA.routes.Near = { races = {}, steps = { { "do", 61, "The Barrens", 46, 58, 16, "", 1 }, { "do", 60, "The Barrens", 44.9, 59.1, 16, "", 1 } } }
local function game(questie)
  local g = GAME({ level = 16, log = { [60] = true, [61] = true }, zone = "The Barrens", pos = { "The Barrens", 44.9, 59.1 } })
  if questie then g.questieSpot = function(id) if id == 60 then return "The Barrens", 59.8, 30.6, "Ishamuhale (Questie)" end end end
  return g
end
NQ = G.NewModel(DATA, "Near", game(true), { skipped = {} })
NG = G.NewModel(DATA, "Near", game(false), { skipped = {} })
""")
check("nearest: Questie's far spot doesn't jump ahead", lua.eval("NQ:Nearest(1)") == 1, lua.eval("NQ:Nearest(1)"))
check("nearest: a guessed spot never counts as near", lua.eval("NG:Nearest(1)") == 1, lua.eval("NG:Nearest(1)"))
lua.execute("DATA.quests[61] = nil; DATA.routes.Near = nil")
lua.execute("DATA.quests[60] = nil; DATA.routes.Gs = nil")

# A questline guide you chose: every quest counts, whatever your level (user, 2026-11-15: Cozy Sleeping Bag at level 20 said
# "Route finished": its level-14 quests counted as not worth it).
lua.execute("""
DATA.quests[62] = { "Low Chain", 14, 14, 0, "", 0, 0, "Note", { "The Barrens", 46, 74 }, "Plank", { "Westfall", 50, 50 }, {}, {}, 0, 0 }
DATA.routes.Line = { races = {}, guide = true, steps = { { "accept", 62, "The Barrens", 46, 74, 14, "" }, { "turnin", 62, "Westfall", 50, 50, 20, "" } } }
DATA.routes.Lvl = { races = {}, steps = { { "accept", 62, "The Barrens", 46, 74, 14, "" } } }
LG = G.NewModel(DATA, "Line", GAME({ level = 20 }), { skipped = {} })
LL = G.NewModel(DATA, "Lvl", GAME({ level = 20 }), { skipped = {} })
""")
check("questline guide: a low quest is still a step for you", lua.eval("LG:Current()") == 1, lua.eval("LG:Current()"))
check("leveling route: a low quest is still left out", lua.eval("LL:Current()") is None, lua.eval("LL:Current()"))
lua.execute("DATA.quests[62] = nil; DATA.routes.Line = nil; DATA.routes.Lvl = nil")

# Steps that wait on an earlier one (user, 2026-11-14: "Turn in Prowlers of the Barrens" showed as doable while step
# 231, the claws, wasn't done).
lua.execute("WM = G.NewModel(DATA, 'Durotar', GAME({ level = 3, log = { [1] = true } }), { skipped = {} })")
check("waits: a hand-in waits on its quest's open objective step", lua.eval("WM:WaitsFor(3)") == 2, lua.eval("WM:WaitsFor(3)"))
check("waits: a pick-up waits on the quest before it (its first open step)", lua.eval("WM:WaitsFor(4)") == 2, lua.eval("WM:WaitsFor(4)"))
check("waits: the objective step itself doesn't wait", lua.eval("WM:WaitsFor(2)") is None)
lua.execute("WM2 = G.NewModel(DATA, 'Durotar', GAME({ level = 3, log = { [1] = true }, complete = { [1] = true } }), { skipped = {} })")
check("waits: objectives done, the hand-in is open", lua.eval("WM2:WaitsFor(3)") is None)

# An NPC up high (user, 2026-11-14: Darsok Swiftdagger on top of the Crossroads tower; under him: "You are here").
lua.execute("DATA.quests[3][9] = { 'The Barrens', 52, 30, 28 }; DATA.quests[3][11] = { 'The Barrens', 52, 30, -15 }")
check("height: the giver's height for an accept step", lua.eval("(M3:Lift(8))") == 28, lua.eval("(M3:Lift(8))"))
check("height: the turn-in's for a turnin step, below is negative", lua.eval("(M3:Lift(10))") == -15)
check("height: none for other steps", lua.eval("M3:Lift(9)") is None and lua.eval("M3:Lift(1)") is None)
check("height: the tip says to go up", "28 yd above" in str(lua.eval("G.Tip(M3, 8)")), lua.eval("G.Tip(M3, 8)"))
check("height: and to go down", "15 yd below" in str(lua.eval("G.Tip(M3, 10)")), lua.eval("G.Tip(M3, 10)"))
lua.execute("DATA.quests[3][9] = { 'The Barrens', 52, 30 }; DATA.quests[3][11] = { 'The Barrens', 52, 30 }")
check("tip: monster levels and the loop", lua.eval("G.Tip(M3, 2)") == "Lvl 3-4, 3 spots on the map", lua.eval("G.Tip(M3, 2)"))
check("tip: elite, kills, along the way", lua.eval("G.Tip(M3, 9)") ==
      "Lvl 11-12, elite: bring friends, ~12 kills, all over the zone", lua.eval("G.Tip(M3, 9)"))
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
# The game can hand addons a hidden ("secret") speed that can't be compared (log, 2026-11-14: the box stopped refreshing).
lua.execute("issecretvalue = function(v) return v == 99 end")
check("arrow: a hidden speed counts as running speed, no error", lua.eval("G.Eta(70, 99)") == "0:10", lua.eval("G.Eta(70, 99)"))
lua.execute("issecretvalue = nil")
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
check("group: two quests on the same monster are one block (plus the along-the-way objective of the trip)", first[:2] == [5, 6], first)
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
check("directions: other continent, the zeppelin first", len(far) == 3 and far[0] == "Go to Orgrimmar (zeppelin)", far)
check("directions: which zeppelin to take", far[1] == "Zeppelin to Undercity", far)
check("directions: then fly to the flight point near the step", far[2] == "Fly to Hillsbrad Foothills" and lua.eval("F:Directions(1)[3].zone") == "Undercity", far)
near = legs("Tirisfal Glades")
check("directions: same continent, fly from the nearest city", len(near) == 1 and near[0] == "Fly to Hillsbrad Foothills", near)
check("directions: none when you are in the step's zone", legs("Hillsbrad Foothills") == [])
lua.execute("FAR('Tirisfal Glades'); F.game.flightKnown = function(zone) return zone ~= 'Hillsbrad Foothills' end")
d = lua.eval("F:Directions(1)")
run_leg = [str(d[k].text) for k in sorted(d)] if d else []
check("directions: a flight path you don't have yet: run there (user, screenshot)", len(run_leg) == 1 and "Run to" in run_leg[0]
      and "Hillsbrad Foothills" in run_leg[0] and "Fly" not in run_leg[0], run_leg)
# A step just across a zone border (user, 2026-11-14 screenshot: harpies next to them, but "Fly from Devrak"):
# close by in yards, no flight, the arrow points at the step itself.
lua.execute("FAR('Tirisfal Glades'); F.game.yardsTo = function() return 400 end")
check("directions: a step a short run away needs no flight", lua.eval("F:Directions(1)") is None)
lua.execute("FAR('Tirisfal Glades'); F.game.yardsTo = function() return 5000 end")
check("directions: far away, still the flight", "Fly" in str(lua.eval("F:Directions(1)[1].text")))
# By real distance (user, 2026-11-15 screenshot: Barrens to Hillsbrad by boat to Booty Bay, then a run up the whole continent).
lua.execute("""
DATA.travel.transports[2] = { "boat", { "Ratchet dock", "The Barrens", 63.7, 38.6, 1 }, { "Booty Bay dock", "Stranglethorn Vale", 25.9, 73.1, 0 } }
DATA.travel.continents["Stranglethorn Vale"] = 0
local W = { ["The Barrens"] = { 900, 300 }, Durotar = { 1000, 0 }, ["Tirisfal Glades"] = { 0, 0 }, ["Stranglethorn Vale"] = { 200, 2000 }, ["Hillsbrad Foothills"] = { 100, 300 } }
local function pos(z, x, y) local w = W[z] or { 0, 0 } return w[1] + (x or 50), w[2] + (y or 50) end
FAR('The Barrens')
F.game.worldDistance = function(z1, x1, y1, z2, x2, y2) local a, b = pos(z1, x1, y1); local c, d = pos(z2, x2, y2); return math.sqrt((a - c) ^ 2 + (b - d) ^ 2) end
""")
via = [str(lua.eval(f"F:Directions(1)[{k}].text")) for k in range(1, lua.eval("#F:Directions(1)") + 1)]
check("directions: the zeppelin to Undercity, not the boat to Booty Bay, for Hillsbrad", any("zeppelin" in v.lower() for v in via) and not any("Booty Bay" in v for v in via), via)
lua.execute("table.remove(DATA.travel.transports, 2)")
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
# With Questie installed, its yellow objective icons, so the guide matches its map (user, 2026-11-14 screenshot: "use same
# icons as questie, that should be the yellow one").
lua.execute("G.UseQuestieIcons(true)")
check("icons: Questie's gear for use, sword for kill, bag for loot", r"Questie\Icons\object" in lua.eval("G.ICONS.use")
      and r"Questie\Icons\slay" in lua.eval("G.ICONS.kill") and r"Questie\Icons\loot" in lua.eval("G.ICONS.loot"), lua.eval("G.ICONS.use"))
check("icons: Questie's are not cropped (round, with their own edge)", lua.eval("G.Inline(G.ICONS.use)").endswith(":0|t"), lua.eval("G.Inline(G.ICONS.use)"))
lua.execute("G.UseQuestieIcons(false)")
check("icons: without Questie, the game's own again", "INV_Misc_Gear_01" in lua.eval("G.ICONS.use"))

# ---- The step box (GuideUI.lua): view and controller, with stand-in frames and game ----
# Step numbers on the world map (user, 2026-11-14: "see in the map the step number in each specific place"):
# the guide's own numbers, steps at the same spot share one pin ("188-189").
lua.execute("PINS = G.MapPins({ {188, 52, 32}, {189, 52.5, 32.2}, {190, 47, 40}, {192, 52.2, 31.9}, {195, 10, 10} })")
check("map pins: steps at one spot share a pin", lua.eval("#PINS") == 3, lua.eval("#PINS"))
check("map pins: one number per pin, the first step there (user: '249-250+' was unreadable)", lua.eval("PINS[1].label") == "188", lua.eval("PINS[1].label"))
check("map pins: the hover title lists them all", lua.eval("PINS[1].title") == "188-189, 192", lua.eval("PINS[1].title"))
check("map pins: more than one step there is counted", lua.eval("PINS[1].more") == 2 and lua.eval("PINS[2].more") == 0)
# Pins that would touch on screen merge (at Ratchet two pins sat on each other): the distance comes in map %.
lua.execute("WIDE = G.MapPins({ {249, 60, 40}, {251, 63, 41}, {260, 80, 80} }, 4, 4)")
check("map pins: close on screen, one pin", lua.eval("#WIDE") == 2 and lua.eval("WIDE[1].title") == "249, 251", lua.eval("WIDE[1].title"))
check("map pins: a single step shows its own number", lua.eval("PINS[2].label") == "190" and lua.eval("PINS[3].label") == "195")
check("map pins: the pin keeps its steps for the hover and the click", lua.eval("PINS[1].steps[1]") == 188 and lua.eval("#PINS[1].steps") == 3)
check("map pins: many steps at one spot stay short", lua.eval("G.StepLabel({3, 5, 7, 9, 11})") == "3, 5, 7+", lua.eval("G.StepLabel({3, 5, 7, 9, 11})"))

# Flight time (user, 2026-11-15: "add the fly time remaining when im flying in the guide").
check("flight: a time you flew before wins", lua.eval("G.FlightEstimate({ ['A|B'] = 95 }, 'A', 'B', 5000)") == 95)
check("flight: otherwise from the distance (25 yd/s, paths bend, take-off)", lua.eval("G.FlightEstimate({}, 'A', 'B', 2500)") == 140,
      lua.eval("G.FlightEstimate({}, 'A', 'B', 2500)"))
check("flight: time left counts down and stops at 0", lua.eval("G.FlightLeft(100, 90, 130)") == 60 and lua.eval("G.FlightLeft(100, 90, 300)") == 0)

# The guide log (user, 2026-11-14: "save logs of whats happening in the game and with the app configuration").
lua.execute("LOG1 = {}; G.LogAdd(LOG1, 'step', 'step 5', '11-14 17:00:00')")
check("log: a line with time, kind and message", lua.eval("LOG1.entries[1]") == "11-14 17:00:00 step: step 5", lua.eval("LOG1.entries[1]"))
lua.execute("SAVED_MAX = G.LOG_MAX; G.LOG_MAX = 3; for k = 1, 5 do G.LogAdd(LOG1, 'x', tostring(k)) end; G.LOG_MAX = SAVED_MAX")
check("log: keeps only the newest lines", lua.eval("#LOG1.entries") == 3 and lua.eval("LOG1.entries[3]").endswith("x: 5"), lua.eval("LOG1.entries[3]"))
lua.execute("LOG2 = {}; A1 = G.LogChange(LOG2, 'arrow', 'arrow', 'off'); A2 = G.LogChange(LOG2, 'arrow', 'arrow', 'off'); A3 = G.LogChange(LOG2, 'arrow', 'arrow', 'on')")
check("log: a state is written only when it changes", lua.eval("A1") is True and lua.eval("A2") is False and lua.eval("A3") is True and lua.eval("#LOG2.entries") == 2)

ui = L.LuaRuntime(unpack_returned_tuples=True)
for _loc in ("Locale.lua", "LocaleES.lua"): ui.execute((__import__("pathlib").Path(__file__).resolve().parents[2] / "addon" / "DufforthTweaksHelper" / _loc).read_text(encoding="utf-8"))
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
# A step that waits on the current one is grayed, with a gray "?" (user, 2026-11-14 screenshot: step 232 looked doable).
ui.execute("SAVED_LOG = LOG; LOG = { [1] = true }; GU.Refresh()")
b2 = box.blocks[2]
check("waiting: the next block says which step comes first", "after step 2" in str(b2.header.text), b2.header.text)
check("waiting: a gray question mark, gray text", "IncompleteQuestIcon" in str(b2.action.text) and "|cff888888" in str(b2.action.text)
      and "ActiveQuestIcon" not in str(b2.action.text), b2.action.text)
ui.execute("COMPLETE[1] = true; GU.Refresh()")
check("waiting: once it's done, the block is normal again", "after step" not in str(box.blocks[1].header.text) and "after step" not in str(box.blocks[2].header.text or ""),
      (box.blocks[1].header.text, box.blocks[2].header.text))
ui.execute("COMPLETE[1] = nil; LOG = SAVED_LOG; GU.Refresh()")
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
ui.execute("box.grip.scripts.OnMouseDown(box.grip); box.scripts.OnSizeChanged(box, 420, 900); box.grip.scripts.OnMouseUp(box.grip)")
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

# Resizing never overlaps the bar's texts (user, 2026-11-14 screenshot: "12-15 The Barrens" under "Level up in 7h 12m"):
# with little room, the less important parts go first (zone %, then the guide name, then "Level up in").
ui.execute("""
GU.TextWidth = function(_, t) return #((t or ''):gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '')) * 6 end
SAVED_PACE = GU.PaceText
GU.PaceText = function(long) return long and 'Next level in about 7h 12m.' or 'Level up in 7h 12m' end
function BAR_FITS()
  local p = DufforthTweaksHelperGuideBox.progress
  local w = GU.TextWidth(nil, p.label.text) + GU.TextWidth(nil, p.pace.text) + 12
  return w <= GU.barWidth, w, GU.barWidth
end
""")
for width in (290, 340, 420, 600):
    ui.execute(f"box.grip.scripts.OnMouseDown(box.grip); box.scripts.OnSizeChanged(box, {width}, 520); box.grip.scripts.OnMouseUp(box.grip)")
    fits = ui.eval("{BAR_FITS()}")
    check(f"bar: at {width} wide the texts don't overlap", fits[1] is True, (fits[2], fits[3], box.progress.label.text, box.progress.pace.text))
check("bar: wide, everything shows", "zone" in str(box.progress.label.text) and "Level up" in str(box.progress.pace.text),
      (box.progress.label.text, box.progress.pace.text))
ui.execute("box.grip.scripts.OnMouseDown(box.grip); box.scripts.OnSizeChanged(box, 290, 520); box.grip.scripts.OnMouseUp(box.grip)")
check("bar: narrow, the zone part still shows", "1-3 Durotar" in str(box.progress.label.text) or "Durotar" in str(box.progress.label.text),
      box.progress.label.text)
ui.execute("GU.PaceText = SAVED_PACE; GU.TextWidth = nil; box.grip.scripts.OnMouseDown(box.grip); box.scripts.OnSizeChanged(box, 420, 520); box.grip.scripts.OnMouseUp(box.grip)")

# Questie's data as a fallback place (user, 2026-11-14), through its loader; nothing breaks without Questie.
check("questie: none installed, no answer", ui.eval("GU.QuestieSpot(900)") is None)
ui.execute("""
QDB = { GetQuest = function(id) if id == 900 then return { ObjectiveData = { { Type = "item", Id = 4, Text = "Savannah Lion Tusk" } } } end end,
  QueryItemSingle = function(id, key) if id == 4 and key == "npcDrops" then return { 77 } end end,
  QueryNPCSingle = function(id, key) if id == 77 and key == "spawns" then return { [17] = { { 40, 20 }, { 70, 70 } } } end end,
  QueryObjectSingle = function() return nil end }
QZ = { GetUiMapIdByAreaId = function(_, area) return area == 17 and 1413 or nil end }
QuestieLoader = { ImportModule = function(_, name) return ({ QuestieDB = QDB, ZoneDB = QZ })[name] end }
""")
qs = ui.eval("{GU.QuestieSpot(900)}")
check("questie: an item objective's drop spot, by zone name", qs and qs[1] == "The Barrens" and qs[2] == 40 and "Savannah Lion Tusk" in str(qs[4]), qs and list(qs.values()))
ui.execute("QDB.GetQuest = function() error('changed') end")
check("questie: an error inside Questie is no answer, not a broken guide", ui.eval("GU.QuestieSpot(900)") is None)
ui.execute("QuestieLoader = nil")

# Step numbers on the world map (user, 2026-11-14).
ui.execute("""
MAPCANVAS = CreateFrame("Frame"); MAPCANVAS.GetWidth = function() return 1000 end; MAPCANVAS.GetHeight = function() return 660 end
WorldMapFrame = CreateFrame("Frame"); WorldMapFrame.GetCanvas = function() return MAPCANVAS end
WorldMapFrame.GetMapID = function() return DufforthTweaksHelperGuideData.uiMaps["Durotar"] end
WorldMapFrame.IsShown = function() return true end
GU.mapDrawnFor = nil; GU.DrawMapLines()
""")
pins = ui.eval("GU.mapPins")
labels = [str(pins[k].label) for k in sorted(pins)] if pins else []
cur = ui.eval("DufforthTweaksHelperGuideBox.stepNum.text")
check("map: a pin with the step number at each place", len(labels) > 0 and all(l[0].isdigit() for l in labels), labels)
check("map: the current step has its pin", any(str(cur) in l.replace(" ", "").replace("-", ",").split(",") or l.startswith(str(cur)) for l in labels), (cur, labels))
check("map: what was drawn is saved for reading after /reload", ui.eval("DufforthTweaksHelperDB.guide.mapDebug.pins") == len(labels)
      and ui.eval("DufforthTweaksHelperDB.guide.mapDebug.level") <= 9000, ui.eval("DufforthTweaksHelperDB.guide.mapDebug.pins"))
ui.execute("SAVED_DRAW = GU.DrawMapLines; GU.DrawMapLines = function() error('boom') end; GU.SafeDrawMap(); GU.DrawMapLines = SAVED_DRAW")
check("map: a drawing error is kept, not lost", "boom" in str(ui.eval("DufforthTweaksHelperDB.guide.mapError")))
ui.execute("GU.SafeDrawMap()")
check("map: and cleared once it draws again", ui.eval("DufforthTweaksHelperDB.guide.mapError") is None)
ui.execute("GU.mapCheckDue = true; GU.SafeDrawMap()")
log_lines = lambda: [str(v) for k, v in sorted(ui.eval("DufforthTweaksHelperDB.guideLog.entries").items())]
check("log: the map check says whether the pins are on screen", any("map: map " in l and "pin1" in l and "visible=" in l for l in log_lines()),
      [l for l in log_lines() if "map" in l][-3:])
# Through HereBeDragons when it's loaded (Questie ships it; user: "why im not seeing the quest number steps in the map").
ui.execute("""
HBD_ADDED = {}
local hbd = { AddWorldMapIconMap = function(_, ref, icon, map, x, y) HBD_ADDED[#HBD_ADDED + 1] = { icon = icon, map = map, x = x, y = y } end,
  RemoveAllWorldMapIcons = function() HBD_ADDED = {} end }
LibStub = function(name, silent) if name == "HereBeDragons-Pins-2.0" then return hbd end end
GU.DrawMapLines()
""")
check("map: pins go through HereBeDragons, one per place, with map and spot", ui.eval("#HBD_ADDED") == len(labels)
      and ui.eval("HBD_ADDED[1].map") == ui.eval("DufforthTweaksHelperGuideData.uiMaps['Durotar']") and 0 < ui.eval("HBD_ADDED[1].x") < 1,
      ui.eval("#HBD_ADDED"))
check("map: the pin shows its step number", str(ui.eval("HBD_ADDED[1].icon.num.text")) in labels, ui.eval("HBD_ADDED[1].icon.num.text"))
# Only the number, outlined, no black circle, and at most 10 steps (user, 2026-11-14: "i cannot see what is behind").
check("map: at most the next 10 steps", ui.eval("GU.MAP_STEPS") == 10)
check("map: no circle behind the number", ui.eval("HBD_ADDED[1].icon.ring.shown") is False and ui.eval("HBD_ADDED[1].icon.fill.shown") is False)
check("map: the number is outlined so it reads on any map", "OUTLINE" in str(ui.eval("HBD_ADDED[1].icon.num.fontFlags")), ui.eval("HBD_ADDED[1].icon.num.fontFlags"))
ui.execute("LibStub = nil; GU.DrawMapLines()")
ui.execute("WorldMapFrame.GetMapID = function() return 999999 end; GU.DrawMapLines()")
check("map: none on a map with no steps", ui.eval("#GU.mapPins") == 0)
ui.execute("WorldMapFrame = nil")

# A step whose quest has an item to use: an icon and a hint on its card (user, 2026-11-15: "an icon that suggests use the item
# on the quest objective").
ui.execute("""
C_QuestLog.GetLogIndexForQuestID = function(id) if id == 2 then return 7 end end
GetQuestLogSpecialItemInfo = function(index) if index == 7 then return "|cffffffff|Hitem:5056::::::::|h[Root Sampler]|h|r", "Interface\Icons\INV_Misc_Root", 1 end end
""")
it = ui.eval("{GU.QuestItemFor(2)}")
check("quest item: the quest's own item from the game", it and it[1] == 5056 and "Root" in str(it[2]), it and list(it.values()))
check("quest item: none for a quest without one", ui.eval("GU.QuestItemFor(1)") is None)
hint = str(ui.eval("GU.UseItemHint(2)"))
check("quest item: the hint shows the icon and says to use it on the objective", "INV_Misc_Root" in hint and "Root Sampler" in hint and "Use" in hint, hint)
ui.execute("C_QuestLog.GetLogIndexForQuestID = nil; GetQuestLogSpecialItemInfo = nil")

# Click a step card: the pin and the arrow go there; right-click: options (user, 2026-11-15).
ui.execute("GU.BackToStep(); CARD = DufforthTweaksHelperGuideBox.blocks[2]; CARD_STEP = CARD.group[1]; CARD.scripts.OnMouseUp(CARD, 'LeftButton')")
check("step click: the arrow goes to that step", ui.eval("GU.override and GU.override.step") == ui.eval("CARD_STEP"), ui.eval("GU.override and GU.override.step"))
check("step click: and the game's map pin", abs(ui.eval("PINS[#PINS].x * 100") - ui.eval("(select(2, GU.model:Place(CARD_STEP)))")) < 1e-6,
      (ui.eval("PINS[#PINS].x * 100"), ui.eval("(select(2, GU.model:Place(CARD_STEP)))")))
ui.execute("GU.BackToStep(); CARD.scripts.OnMouseUp(CARD, 'RightButton')")
menu = ui.eval("GU.stepMenu")
labels = [str(r.text) for k, r in sorted(menu.rows.items()) if r.shown] if menu else []
check("step right-click: a menu of options", menu is not None and menu.shown and any("pin" in l.lower() for l in labels)
      and any("done" in l.lower() for l in labels) and any("continue" in l.lower() for l in labels), labels)
ui.execute("for _, r in pairs(GU.stepMenu.rows) do if r.shown and string.find(string.lower(r.text or ''), 'done') then r.scripts.OnClick(r) break end end")
check("step right-click: Mark done marks it", ui.eval("DufforthTweaksHelperDB.guide.routes.Durotar.skipped[CARD_STEP]") is True)
# Like the main Menu (user, 2026-11-15: "right click on the steps is persistent"; "focus on text, not on the button"):
# slim text rows, and it closes a moment after the mouse leaves.
ui.execute("CARD.scripts.OnMouseUp(CARD, 'RightButton')")
row1 = ui.eval("GU.stepMenu.rows[1]")
check("step menu: text rows, no filled button", ui.eval("rawget(GU.stepMenu.rows[1], 'bg')") is None and ui.eval("GU.stepMenu.rows[1].label.text") is not None,
      ui.eval("GU.stepMenu.rows[1].label.text"))
ui.execute("GU.stepMenu.scripts.OnUpdate(GU.stepMenu, 1.0)")
check("step menu: closes after the mouse leaves it", ui.eval("GU.stepMenu.shown") is False)
ui.execute("GU.model:ToggleStep(CARD_STEP); GU.BackToStep()")

# Auto flight asks first (user, 2026-11-15: "make me confirm if i want to fly when you are auto using the fly path").
ui.execute("""
TAKEN = nil; POPUP = nil
TakeTaxiNode = function(i) TAKEN = i end
StaticPopupDialogs = {}
StaticPopup_Show = function(which, text1, text2, data) POPUP = { which = which, text = text1, data = data } return {} end
GU.OfferFlight(3, "Crossroads, The Barrens")
""")
check("auto flight: a Yes/No window, not a flight", ui.eval("TAKEN") is None and ui.eval("POPUP and POPUP.which") == "DUFFORTH_GUIDE_FLY"
      and "Crossroads" in str(ui.eval("POPUP.text")), ui.eval("POPUP and POPUP.text"))
ui.execute("StaticPopupDialogs.DUFFORTH_GUIDE_FLY.OnAccept(nil, POPUP.data)")
check("auto flight: Yes takes that flight", ui.eval("TAKEN") == 3)
# While flying: the time left in the box, learned from each real flight.
ui.execute("""
NOW = 1000; GetTime = function() return NOW end
ONTAXI = true; UnitOnTaxi = function() return ONTAXI end
GU.FlightStarted("Thunder Bluff", "Crossroads", 120)
NOW = 1030; GU.FlightCheck()
""")
check("flying: the box says when you land", "1:30" in str(ui.eval("GU.FlightText()")), ui.eval("GU.FlightText()"))
ui.execute("NOW = 1105; ONTAXI = false; GU.FlightCheck()")
check("flying: landed, the real time is kept for next time", ui.eval("DufforthTweaksHelperDB.guide.flightTimes['Thunder Bluff|Crossroads']") == 105)
check("flying: and the text goes away", ui.eval("GU.FlightText()") is None)
ui.execute("GetTime = nil; UnitOnTaxi = nil")

# Errands don't take the arrow from your step (log, 2026-11-15: "Buy water at Innkeeper Byula" pulled the arrow off
# Ishamuhale; user: "waypoint is pointing wrong place"). A click on the errand row points it there.
ui.execute("""
SAVED_ERRANDS = GU.Errands
FAKE_ERRAND = { key = "food:x", kind = "food", zone = "Durotar", x = 12, y = 34, action = "Buy water at Innkeeper" }
GU.Errands = function() return { FAKE_ERRAND } end
GU.override = nil; GU.Refresh()
""")
check("errands: the arrow stays on your step", "Buy water" not in str(ui.eval("GU.target and GU.target.text")), ui.eval("GU.target and GU.target.text"))
ui.execute("GU.ErrandClicked(FAKE_ERRAND)")
check("errands: a click on the errand points the arrow there", "Buy water" in str(ui.eval("GU.target and GU.target.text")), ui.eval("GU.target and GU.target.text"))
ui.execute("GU.Errands = SAVED_ERRANDS; GU.BackToStep()")

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
# Back to your step (user, 2026-11-14: "when i want to go back to my current step waypoint is not changing").
check("extras: the game's map pin goes to the quest too, and stays there", ui.eval("PINS[#PINS].map") == 1454, ui.eval("PINS[#PINS].map"))
check("extras: a bar says the arrow is on the quest, with a way back", box.viewBar.shown and "Arrow on" in str(box.viewBar.label.text)
      and not box.viewBar.go.shown, box.viewBar.label.text)
ui.execute("box.viewBar.back.scripts.OnClick(box.viewBar.back)")
check("extras: back to my step: the arrow is on your step again", ui.eval("GU.override") is None and ui.eval("GU.target and GU.target.zone") != "Orgrimmar",
      ui.eval("GU.target and GU.target.zone"))
check("extras: and so is the game's map pin", ui.eval("PINS[#PINS].map") != 1454, ui.eval("PINS[#PINS].map"))
check("extras: the bar goes away", not box.viewBar.shown)
# Any click about your step brings it back too (user, 2026-11-14: "clicking step 255 waypoint is not coming back").
CLS = cls[0] if cls else 1
ui.execute("""function DEEPCOPY(t) if type(t) ~= 'table' then return t end local o = {} for k, v in pairs(t) do o[k] = DEEPCOPY(v) end return o end
SAVED_GUIDE_DB = DEEPCOPY(DufforthTweaksHelperDB.guide)""")
for name, click_lua in (("the map pin button", "box.pin.scripts.OnClick(box.pin)"), ("Best", "box.best.scripts.OnClick(box.best)"),
                        ("the step arrows", "box.nextSection.scripts.OnClick(box.nextSection)"), ("Skip", "box.skip.scripts.OnClick(box.skip)"),
                        ("Back", "box.back.scripts.OnClick(box.back)")):
    ui.execute(f"box.extraRows[{CLS}].scripts.OnClick(box.extraRows[{CLS}])")
    ui.execute(click_lua)
    check(f"extras: {name} leaves the class quest", ui.eval("GU.override") is None and ui.eval("GU.target and GU.target.zone") != "Orgrimmar"
          and ui.eval("PINS[#PINS].map") != 1454, (ui.eval("GU.target and GU.target.zone"), ui.eval("PINS[#PINS].map")))
ui.execute("for k in pairs(DufforthTweaksHelperDB.guide) do DufforthTweaksHelperDB.guide[k] = nil end "
           "for k, v in pairs(SAVED_GUIDE_DB) do DufforthTweaksHelperDB.guide[k] = v end GU.BackToStep()")
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
ui.execute("GU.target.lift = 28; GU.UpdateArrow()")
check("arrow: under an NPC up high, says to go up, not 'You are here' (user screenshot)",
      "go up" in str(arrow.dist.text).lower() and "28" in str(arrow.dist.text) and "here" not in str(arrow.dist.text).lower(), arrow.dist.text)
check("arrow: and a big up arrow, so it's still a waypoint (user: 'there is no waypoint')", arrow.climb.shown and "Up" in str(arrow.climb.tex),
      (arrow.climb.shown, arrow.climb.tex))
ui.execute("GU.target.npc = 'Darsok Swiftdagger'; SAVED_UN = UnitName; UnitName = function(u) return u == 'target' and 'Darsok Swiftdagger' or nil end; GU.UpdateArrow()")
check("arrow: up there with the NPC targeted, you are here", "here" in str(arrow.dist.text).lower(), arrow.dist.text)
ui.execute("UnitName = SAVED_UN; GU.target.npc = nil")
ui.execute("GU.target.lift = -15; GU.UpdateArrow()")
check("arrow: over one down below, says to go down", "go down" in str(arrow.dist.text).lower(), arrow.dist.text)
check("arrow: a down arrow below", arrow.climb.shown and "Down" in str(arrow.climb.tex), arrow.climb.tex)
ui.execute("GU.target.lift = nil; GU.UpdateArrow()")
check("arrow: no climb arrow on the ground", not arrow.climb.shown)
ui.execute("SAVED_WP = C_Map.GetWorldPosFromMapPos; C_Map.GetWorldPosFromMapPos = nil; GU.UpdateArrow()")
check("arrow: hides when the game can't place you", arrow.shown is False)
ui.execute("C_Map.GetWorldPosFromMapPos = SAVED_WP; PLAYER.y, PLAYER.facing = 0.70, 0; GU.UpdateArrow()")
ui.execute("local a = DufforthTweaksHelperGuideArrow; if rawget(a.scripts, 'OnMouseUp') then a.scripts.OnMouseUp(a, 'RightButton') end")
check("arrow: a right-click doesn't hide it (user: the arrow got turned off by accident, 'no waypoint')", arrow.shown is True
      and ui.eval("DufforthTweaksHelperDB.guide.arrow") is not False)
ui.execute("GU.SetArrowShown(false)")
check("arrow: can be turned off, and remembers", arrow.shown is False and ui.eval("DufforthTweaksHelperDB.guide.arrow") is False)
ui.execute("GU.SetArrowShown(true)")
check("arrow: and on again", arrow.shown is True)
ui.execute("DufforthTweaksHelperDB.guide.arrow, DufforthTweaksHelperDB.guide.arrowV = false, nil; GU.Refresh()")
check("arrow: turned off by the old right-click: on again once after the update", arrow.shown is True
      and ui.eval("DufforthTweaksHelperDB.guide.arrowV") == 1)
ui.execute("GU.SetArrowShown(false); GU.Refresh()")
check("arrow: off from the Menu after that stays off", arrow.shown is False)
lines = [str(v) for k, v in sorted(ui.eval("DufforthTweaksHelperDB.guideLog.entries").items())]
check("log: says the arrow is off and why", any("arrow: hidden: turned off" in l for l in lines), lines[-3:])
check("log: the step, where the arrow points and the settings", any(l.startswith("step: ") for l in lines) and any(l.startswith("target: ") for l in lines)
      and any(l.startswith("settings: ") and "arrow=" in l for l in lines), lines[-6:])
ui.execute("GU.SetArrowShown(true)")
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
