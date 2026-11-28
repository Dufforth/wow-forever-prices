"""RestedXP's step engine in the guide (GuideRx.lua) outside the game: the forward-only pointer, side steps
(#completewith, #sticky, #requires), step and line tags, level gates, skip conditions, waypoints walked in order,
loops, the ghost arrow, event marks, targets and auto quest, joining ahead, and a step-by-step walk of the real
Durotar route (GuideData.lua) against RestedXP's own step order (user, 2026-11-27: "at 100%")."""
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
    for f in ("Locale.lua", "LocaleES.lua", "Guide.lua", "GuideRx.lua"):
        lua.execute((ADDON / f).read_text(encoding="utf-8"))
    lua.execute("""
G = DufforthTweaksHelperGuide
-- A fake game the tests change as the player plays: T holds level, log, done, objectives, zone, position, items...
function GAME(T)
  return {
    level = function() return T.level end, classBit = function() return 1 end, raceBit = function() return 2 end,
    who = function() return { class = T.class or "WARRIOR", race = T.race or "Orc", faction = "Horde" } end,
    done = function(id) return T.done[id] == true end, inLog = function(id) return T.log[id] == true end,
    complete = function(id) return T.complete[id] == true end, zone = function() return T.zone end,
    logIds = function() local o = {} for id in pairs(T.log) do o[#o + 1] = id end table.sort(o) return o end,
    objectiveDone = function(id, name, goal, goals) if T.obj[id] ~= nil then return T.obj[id] end return nil end,
    objectiveIndexDone = function(id, k) local o = T.objk[id]; if o and o[k] ~= nil then return o[k] end return T.obj[id] end,
    position = function() if T.pos then return T.pos[1], T.pos[2], T.pos[3] end end,
    yardsTo = function(zone, x, y) if T.pos and T.pos[1] == zone and x then return math.sqrt((T.pos[2] - x) ^ 2 + (T.pos[3] - y) ^ 2) * 10 end end,
    ghost = function() return T.ghost == true end,
    corpse = function() if T.corpse then return T.corpse[1], T.corpse[2], T.corpse[3] end end,
    xp = function() return T.cur or 0, T.max or 1000 end,
    itemCount = function(id) return T.items[id] or 0 end,
    spellKnown = function(id) return T.spells[id] == true end,
    money = function() return T.money or 0 end,
    inArea = function(id, name) return T.area == id end,
    bindIs = function(id, name) return T.bind ~= nil and T.bind == id end,
    onTaxi = function() return T.taxi == true end,
    hearth = function() return T.bindZone, true end,
    flightKnown = function() return false end,
    skill = function(name) return T.skills and T.skills[name] end,
    cooldownLeft = function(kind, id) return T.cd and T.cd[id] end,
    slotStat = function() return nil end,
  }
end
function NEWT(t)
  t.log, t.done, t.complete, t.obj, t.objk, t.items, t.spells = t.log or {}, t.done or {}, t.complete or {}, t.obj or {}, {}, {}, {}
  t.zone = t.zone or "Durotar"
  return t
end
""")
    return lua


# rows: kind, quest, zone, x, y, level, text, goal, dest, nil, rx step, arg
FIXTURE = """
DATA = {
  uiMaps = { Durotar = 1411, ["The Barrens"] = 1413 }, extras = { class = {}, dungeon = {}, item = {} },
  spirit = { { "Durotar", 10, 10, "Valley" }, { "Durotar", 80, 80, "Razor Hill" }, { "The Barrens", 50, 50, "Crossroads" } },
  routes = { Durotar = { races = { "Orc" }, rxp = true, parts = { "1-6 Durotar", "6-10 Durotar" }, steps = {
    { "do", 1, "Durotar", 20, 20, 1, "Kill boars", 1, nil, nil, 1 },                          -- 1
    { "accept", 1, "Durotar", 40, 60, 1, "", 0, nil, nil, 2 },                                -- 2
    { "accept", 2, "Durotar", 40, 60, 1, "", 0, nil, nil, 2, { lt = "Warrior" } },            -- 3
    { "accept", 3, "Durotar", 40, 60, 1, "", 0, nil, nil, 2, { lt = "Mage" } },               -- 4
    { "goto", 0, "Durotar", 50, 50, 1, "Go to Durotar", 0, nil, nil, 3 },                     -- 5
    { "accept", 9, "Durotar", 50, 50, 1, "", 0, nil, nil, 4 },                                -- 6
    { "do", 2, "Durotar", 55, 55, 2, "", 1, nil, nil, 5 },                                    -- 7
    { "turnin", 1, "Durotar", 40, 60, 3, "", 0, nil, nil, 6 },                                -- 8
    { "turnin", 2, "Durotar", 40, 60, 3, "", 0, nil, nil, 6 },                                -- 9
    { "grind", 0, "Durotar", 45, 45, 5, "Grind to level 5", 0, nil, nil, 7, { l = 5 } },      -- 10
    { "accept", 5, "Durotar", 60, 60, 6, "", 0, nil, nil, 8 },                                -- 11
    { "deathskip", 0, "Durotar", 60, 60, 6, "Die", 0, nil, nil, 9 },                          -- 12
    { "hearth", 0, "Durotar", 60, 60, 6, "Hearth", 0, nil, nil, 10 },                         -- 13
    { "vendor", 0, "Durotar", 60, 60, 6, "Vendor", 0, nil, nil, 10, { npc = 3 } },            -- 14
    { "train", 0, "Durotar", 60, 60, 6, "Train", 0, nil, nil, 10, { s = 100 } },              -- 15
    { "collect", 0, "Durotar", 60, 60, 6, "Collect", 0, nil, nil, 10, { i = 500, n = 3 } },   -- 16
    { "note", 0, "Durotar", 60, 60, 6, "Read the sign", 0, nil, nil, 10 },                    -- 17
    { "fly", 0, "Durotar", 60, 60, 6, "Fly", 0, { "The Barrens", 50, 50 }, nil, 11, { n = "Crossroads" } }, -- 18
  }, rx = {
    { p = 0, s = 1, cw = 3, loop = 1, a = 1, b = 1, pt = { { "Durotar", 20, 20, 5, 1, "", 1 }, { "Durotar", 30, 20, 5, 1, "", 1 } }, mob = { "Mottled Boar" }, us = { "Warlord Kolkanis" } },
    { p = 0, a = 2, b = 4, pt = { { "Durotar", 40, 60, nil, 3, "", nil } }, tg = { "Gornek" }, gs = 1 },
    { p = 0, a = 5, b = 5, c = { { "isOnQuest", { v = { "2" } }, "" } }, pt = { { "Durotar", 50, 50, 10, 0, "", 5 } } },
    { p = 0, t = "Mage", a = 6, b = 6 },
    { p = 0, s = 1, cw = 6, a = 7, b = 7 },
    { p = 0, req = 5, a = 8, b = 9 },
    { p = 0, lv = 5, a = 10, b = 10 },
    { p = 1, a = 11, b = 11, c = { { "xp", { l = 4, rv = 1 }, "" } } },
    { p = 1, dz = 1, a = 12, b = 12 },
    { p = 1, a = 13, b = 17 },
    { p = 1, a = 18, b = 18, c = { { "zoneskip", { v = { "The Barrens" }, z = { "The Barrens" } }, "" } } },
  } },
  Hold = { races = { "Orc" }, rxp = true, parts = { "1-6 A", "6-10 B" }, steps = {
    { "do", 7, "Durotar", 20, 20, 1, "", 1, nil, nil, 1 },
    { "accept", 8, "Durotar", 20, 20, 1, "", 0, nil, nil, 2 },
    { "accept", 9, "Durotar", 20, 20, 6, "", 0, nil, nil, 3 },
  }, rx = { { p = 0, s = 1, a = 1, b = 1 }, { p = 0, a = 2, b = 2 }, { p = 1, a = 3, b = 3 } } },
  },
  quests = {},
}
"""


def main():
    lua = runtime()
    lua.execute(FIXTURE)
    lua.execute("""
T = NEWT({ level = 1 })
SAVED = { skipped = {} }
function M(route) return G.NewModel(DATA, route or "Durotar", GAME(T), SAVED) end
function J(t) local o = {} for _, v in ipairs(t or {}) do o[#o + 1] = tostring(v) end return table.concat(o, ",") end
""")
    ev = lua.eval
    run = lua.execute

    # 1. A new level 1 Orc Warrior: the sticky side step 1 and step 2, whose Mage line isn't shown.
    check("RestedXP routes get the step engine", ev("M().rxp and M().RxActive ~= nil"))
    check("start: side step 1 and step 2 are active", ev("J(M():RxActive())") == "1,2", ev("J(M():RxActive())"))
    check("current row: step 2's first line", ev("M():Current()") == 2, ev("M():Current()"))
    check("rows of step 2 for a Warrior (not the Mage line)", ev("J(M():RxRows(2))") == "2,3", ev("J(M():RxRows(2))"))
    check("cards: the active steps only, side step first (RestedXP's current steps)", ev("J((function() local o = {} for _, b in ipairs(M():Blocks(4, true)) do o[#o+1] = b[1] end return o end)())") == "1,2",
          ev("J((function() local o = {} for _, b in ipairs(M():Blocks(4, true)) do o[#o+1] = b[1] end return o end)())"))
    check("targets: the step's NPC and the side step's mob", ev("J(M():RxTargets())") == "Mottled Boar,Warlord Kolkanis,Gornek", ev("J(M():RxTargets())"))
    check("gossip skip on step 2", ev("M():RxGossip()") is True)
    check("auto accept: quest 1 yes, Mage quest 3 no, turn-in 1 no", ev("M():RxAutoQuest(1, 'accept') and not M():RxAutoQuest(3, 'accept') and not M():RxAutoQuest(1, 'turnin')") is True)
    # Arrow: the side step's walk-through points come first (active steps in order).
    run("T.pos = { 'Durotar', 0, 0 }")
    check("arrow: side step's first walk-through point", ev("(function() local a = M():RxArrow() return a and (a.x .. ',' .. a.y) end)()") == "20,20")
    run("T.pos = { 'Durotar', 20.2, 20 }; M():RxArrow()")
    check("walk-through reached: the arrow moves to the next point", ev("(function() local a = M():RxArrow() return a.x .. ',' .. a.y end)()") == "30,20")
    run("T.pos = { 'Durotar', 30, 20.1 }; M():RxArrow()")
    # RestedXP restarts a loop's points only when no active step has a point left (map.lua updateArrowData).
    check("loop done: the arrow moves to the next active step's point", ev("(function() local a = M():RxArrow() return a.x .. ',' .. a.y end)()") == "40,60")
    run("SAVED.rx.reached['1:1'] = true; SAVED.rx.reached['1:2'] = true; SAVED.rx.reached['2:1'] = true")
    check("no point left: the loop starts again", ev("(function() local a = M():RxArrow() return a.x .. ',' .. a.y end)()") == "20,20")
    run("SAVED.rx.reached = {}")
    run("T.log[1] = true; T.obj[1] = true; T.pos = { 'Durotar', 0, 0 }")
    check("a point whose objective is done is passed: arrow on step 2", ev("(function() local a = M():RxArrow() return a.x .. ',' .. a.y end)()") == "40,60")
    run("T.obj[1] = nil; T.log[1] = nil; SAVED.rx.skip[1] = nil")  # side step 1 was closed by that: open again for the next checks

    # 2. Quests taken: step 2 done, the pointer moves on (forward only).
    run("T.log[1] = true; T.log[2] = true")
    check("step 2 done: pointer on step 3", ev("M():RxAt()") == 3 and ev("J(M():RxActive())") == "1,3", ev("J(M():RxActive())"))
    check("stop point is a row; arrow on step 1's loop first", ev("M():Current()") == 5)
    run("T.log[2] = nil")
    check("condition isOnQuest false: step 3 skipped", ev("M():RxAt()") >= 5, ev("M():RxAt()"))
    # Back to the start of the scenario with quest 2 in the log again: the pointer never goes back by itself.
    run("T.log[2] = true")
    check("forward only: dropping and taking a quest back doesn't move the pointer back", ev("M():RxAt()") >= 5)
    run("SAVED.rx.at = 3")
    run("T.pos = { 'Durotar', 50.5, 50 }; M():RxArrow()")
    # 3. Stop point reached: step 3 done; step 4 (Mage) not shown; step 5 sticky; step 6 waits on it (#requires).
    check("completewith: step 1 ends once the pointer passes step 3", ev("SAVED.rx.skip[1] == true"))
    check("requires: step 6 waits for side step 5", ev("J(M():RxActive())") == "5" and ev("M():RxAt()") == 6, ev("J(M():RxActive())") + " at " + str(ev("M():RxAt()")))
    check("current row while waiting: the side step's line", ev("M():Current()") == 7)
    run("T.obj[2] = true")
    check("side step 5 done: step 6 active", ev("J(M():RxActive())") == "6", ev("J(M():RxActive())"))
    check("auto turn-in now on, accept off", ev("M():RxAutoQuest(1, 'turnin') and not M():RxAutoQuest(1, 'accept')") is True)
    # 4. Hand-ins: step 7 is gated at level 5 (level 3): nothing active, so on to part 2; step 8's ".xp <4,1" skips it.
    run("T.level = 3; T.done[1] = true; T.done[2] = true; T.log[1] = nil; T.log[2] = nil")
    check("level gate and xp skip: on to the death-skip step", ev("M():RxAt()") == 9, ev("M():RxAt()"))
    # 5. Ghost: a death-skip step points at the nearest Spirit Healer; elsewhere at the corpse.
    run("T.ghost = true; T.pos = { 'Durotar', 70, 75 }; T.corpse = { 'Durotar', 61, 61 }")
    check("ghost on a death-skip step: nearest Spirit Healer", ev("(function() local a = M():RxArrow() return a.x .. ',' .. a.y .. ' ' .. a.kind end)()") == "80,80 spirit")
    run("T.ghost = false; M():RxMark('resurrect')")
    check("resurrected: death-skip done, step 10", ev("M():RxAt()") == 10, ev("M():RxAt()"))
    run("T.ghost = true")
    check("ghost elsewhere: the corpse", ev("(function() local a = M():RxArrow() return a.x .. ',' .. a.y .. ' ' .. a.kind end)()") == "61,61 corpse")
    run("T.ghost = false")
    # 6. Hearth, vendor, train, collect, note: each its own way of being done.
    run("M():RxMark('hearth'); M():RxMark('vendor')")
    check("hearth and vendor marked, train/collect/note open", ev("J(M():RxOpenRows(10))") == "15,16,17", ev("J(M():RxOpenRows(10))"))
    run("T.spells[100] = true; T.items[500] = 3")
    check("trained and collected", ev("J(M():RxOpenRows(10))") == "17")
    run("M():ToggleStep(17)")
    check("note ticked by hand: on to step 11", ev("M():RxAt()") == 11, ev("M():RxAt()"))
    run("T.zone = 'The Barrens'")
    check("zoneskip: already in The Barrens, route finished", ev("M():Current() == nil and M():RxFinished()") is True)

    # 7. Skip, back, a step picked in the list.
    run("SAVED.rx = nil; T = NEWT({ level = 1 }); T.log[2] = true")
    run("M():Skip()")
    check("skip moves the pointer one step", ev("M():RxAt()") == 3, ev("M():RxAt()"))
    run("M():Back()")
    check("back returns to it", ev("M():RxAt()") == 2)
    run("M():SetStart(8)")
    check("a row picked in the list: its step", ev("M():RxAt()") == 6)
    # 8. Joining ahead: a level 7 with no pointer starts at the first part that ends above its level.
    run("SAVED.rx = nil; T = NEWT({ level = 7 })")
    check("joining ahead at level 7: part 6-10", ev("M():RxAt()") == 8, ev("M():RxAt()"))
    check("Recommended is that step's first row", ev("(function() SAVED.rx = nil return M():Recommended() end)()") == 11)
    # 9. A side step still open at the end of a part keeps you in it (RestedXP's SetStep past the guide end).
    run("HS = { skipped = {} }; T = NEWT({ level = 1 }); T.log[7] = true; T.log[8] = true")
    check("part end waits for its open side step", ev("J(G.NewModel(DATA, 'Hold', GAME(T), HS):RxActive())") == "1"
          and ev("G.NewModel(DATA, 'Hold', GAME(T), HS):Current()") == 1)
    run("T.obj[7] = true")
    check("side step done: next part", ev("J(G.NewModel(DATA, 'Hold', GAME(T), HS):RxActive())") == "3")
    # Sections are RestedXP's parts.
    check("sections: one per RestedXP part", ev("(function() local s = M():Sections() return #s .. ' ' .. s[1].first .. '-' .. s[1].last .. ' ' .. s[2]['from'] .. ' ' .. s[2].zone end)()") == "2 1-10 6 Durotar",
          ev("(function() local s = M():Sections() return #s .. ' ' .. s[1].first .. '-' .. s[1].last .. ' ' .. s[2]['from'] .. ' ' .. s[2].zone end)()"))

    interface_parts(lua)
    ui_parts()
    ui_box()
    real_memory()
    real_walk()
    sys.exit(1 if failed else 0)


def interface_parts(lua):
    """The engine's answers for the interface pieces copied from RestedXP: a check box per line, one list row per step,
    pins at every point of the active steps, the names the nameplate scan looks for, and dropping other starts."""
    ev, run = lua.eval, lua.execute
    run("SAVED.rx = nil; SAVED.skipped = {}; T = NEWT({ level = 1 }); T.pos = { 'Durotar', 0, 0 }")
    # 1. Per line: open, ticked by the game (locked), ticked by hand (can be unticked).
    check("line: an open line", ev("M():RxLineState(2)") == "open", ev("M():RxLineState(2)"))
    run("T.log[1] = true")
    check("line: done by the game is ticked and locked", ev("M():RxLineState(2)") == "game")
    run("M():ToggleStep(3)")
    check("line: ticked by hand", ev("M():RxLineState(3)") == "hand" and ev("M():RxAt()") >= 3, ev("M():RxLineState(3)"))
    run("M():ToggleStep(3)")
    check("line: unticked again", ev("M():RxLineState(3)") == "open")
    run("SAVED.rx = nil; T = NEWT({ level = 1 }); T.pos = { 'Durotar', 0, 0 }")
    # 2. One list row per step, with the step's own state.
    states = ev("(function() local m = M() local o = {} for n = 1, 6 do o[#o+1] = m:RxStepState(n) end return table.concat(o, ',') end)()")
    check("list: a state per RestedXP step", states == "along,current,open,passed,open,open", states)
    check("list: a step's lines, yours only", ev("J(M():RxRows(2))") == "2,3")
    run("M():RxToggleWhole(2)")
    check("list: its check box ticks every line of the step", ev("M():RxStepState(2)") == "done" and ev("M():RxAt()") >= 3, ev("M():RxStepState(2)"))
    check("list: and the row shows ticked", ev("M():RxStepTicked(2)") is True)
    run("M():RxToggleWhole(2)")
    check("list: a second click unticks what you ticked", ev("M():RxLineState(2)") == "open" and ev("M():RxStepTicked(2)") is False)
    run("SAVED.rx = nil; T = NEWT({ level = 1 }); T.pos = { 'Durotar', 0, 0 }")
    # 3. Pins: every point of the active steps, with the step number; reached points go; lines join a step's points.
    pins = ev("(function() local o = {} for _, p in ipairs(M():RxPins()) do o[#o+1] = p.n .. '@' .. p.x .. ',' .. p.y end return J(o) end)()")
    check("pins: every point of the active steps, side step first", pins == "1@20,20,1@30,20,2@40,60", pins)
    check("pins: a line between the points of one step", ev("#M():RxPinLines(M():RxPins())") == 1)
    run("T.pos = { 'Durotar', 20.2, 20 }; M():RxArrow(); T.pos = { 'Durotar', 0, 0 }")
    pins = ev("(function() local o = {} for _, p in ipairs(M():RxPins()) do o[#o+1] = p.n .. '@' .. p.x end return J(o) end)()")
    check("pins: a reached point is gone", pins == "1@30,2@40", pins)
    check("pins: the arrow's point is marked", ev("(function() for _, p in ipairs(M():RxPins()) do if p.arrow then return p.x end end end)()") == 30)
    # 4. Nameplate names: the step's NPCs, monsters and rare monsters (the sound is for the rare ones).
    check("scan: names and their kind", ev("(function() local s = M():RxScanNames() return s['Mottled Boar'] .. s['Warlord Kolkanis'] .. s['Gornek'] end)()") == "mobustg")
    # 5. Dropping the other starts' routes: questline guides and the kept start stay.
    run("PD = { routes = { A = { rxp = true, parts = { '1-6 A' }, steps = {} }, ['A (dungeons)'] = { rxp = true, parts = {}, steps = {} }, B = { rxp = true, parts = { '1-6 B' }, steps = {} }, Q = { steps = {} } } }")
    run("PRUNED = G.PruneRoutes(PD, { A = true, ['A (dungeons)'] = true })")
    check("prune: other starts dropped, kept start and questline guides stay", ev("PRUNED") == 1 and ev("PD.routes.B == nil and PD.routes.A ~= nil and PD.routes.Q ~= nil") is True)
    check("prune: their part names stay for the Guides menu", ev("PD.pruned.B.parts[1]") == "1-6 B")
    check("prune: a second call changes nothing", ev("G.PruneRoutes(PD, { A = true })") == 1 and ev("PD.routes['A (dungeons)'] == nil") is True)


def ui_parts():
    """GuideRxUI.lua and QuestAuto.lua pieces: the target macro, the arrow's target, the gossip option picked."""
    lua = runtime()
    lua.execute("""
local frame = { RegisterEvent = function() end, SetScript = function() end }
CreateFrame = function() return frame end
DufforthTweaksHelperGuideUI = {}
""")
    for f in ("GuideRxUI.lua", "QuestAuto.lua"):
        lua.execute((ADDON / f).read_text(encoding="utf-8"))
    lua.execute(FIXTURE)
    lua.execute("T = NEWT({ level = 1 }); SAVED = { skipped = {} }; MODEL = G.NewModel(DATA, 'Durotar', GAME(T), SAVED)")
    rx, q = "DufforthTweaksHelperGuideRxUI", "DufforthTweaksHelperQuestAuto"
    check("macro: one /targetexact line per name", lua.eval(f"{rx}.MacroText({{'Gornek', 'Mottled Boar'}})") == "/targetexact Gornek\n/targetexact Mottled Boar")
    long = lua.eval(f"(function() local t = {{}} for i = 1, 40 do t[i] = 'Monster name ' .. i end return #{rx}.MacroText(t) end)()")
    check("macro fits the game's 255 characters", long <= 255, long)
    lua.execute("T.pos = { 'Durotar', 0, 0 }")
    tg = lua.eval(f"{rx}.Target(MODEL)")
    check("arrow target: the side step's point on the zone's map", tg is not None and tg.map == 1411 and tg.x == 20 and "1" in str(tg.text), tg and (tg.map, tg.x, tg.text))
    lua.execute("T.ghost = true; T.corpse = { 'Durotar', 61, 61 }")
    tg = lua.eval(f"{rx}.Target(MODEL)")
    check("arrow target when dead: the corpse", tg is not None and tg.x == 61, tg and tg.text)
    check("gossip: no arguments, first option when no quest is offered", lua.eval(f"{q}.SkipGossip(true, 5, 2, 0)") == 1)
    check("gossip: never while the NPC offers quests", lua.eval(f"{q}.SkipGossip(true, 5, 2, 1)") is None)
    check("gossip: an option number", lua.eval(f"{q}.SkipGossip({{2}}, 5, 3, 0)") == 2)
    check("gossip: the npc's own id means its first option", lua.eval(f"{q}.SkipGossip({{3881}}, 3881, 3, 0)") == 1)
    check("gossip: another npc's options are left alone", lua.eval(f"{q}.SkipGossip({{3881, 2}}, 9, 3, 0)") is None)
    check("gossip: options in turn", [lua.eval(f"{q}.SkipGossip({{3881, 2, 1}}, 3881, 3, 0)") for _ in range(3)] == [2, 1, 2])


UI_MOCK = r'''
ALL = {}
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
  function o:SetPoint(...) rawset(self, "pt", { ... }) end
  function o:SetSize(w, h) rawset(self, "size", { w, h }) end
  function o:GetWidth() return 1000 end
  function o:GetHeight() return 1000 end
  function o:SetAlpha(v) rawset(self, "alpha", v) end
  function o:SetAttribute(k, v) local a = rawget(self, "attrs") or {}; a[k] = v; rawset(self, "attrs", a) end
  function o:CreateFontString() local f = object("FontString"); ALL[#ALL+1] = f; return f end
  function o:CreateTexture() return object("Texture") end
  function o:CreateLine() local l = object("Line"); LINES[#LINES+1] = l; return l end
  return setmetatable(o, { __index = function() return function() end end })
end
LINES = {}
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
UnitFactionGroup = function() return "Horde" end
GetRealZoneText = function() return ZONE end
GetTime = function() return NOW end
NOW = 100
C_QuestLog = {
  IsQuestFlaggedCompleted = function(id) return DONE[id] == true end,
  GetNumQuestLogEntries = function() local n = 0 for _ in pairs(LOG) do n = n + 1 end return n end,
  GetInfo = function(i) local ids = {} for id in pairs(LOG) do ids[#ids+1] = id end table.sort(ids) return { questID = ids[i], title = "q" } end,
  IsComplete = function(id) return COMPLETE[id] == true end,
  GetQuestObjectives = function(id) return {} end,
}
UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { map = map, x = x, y = y } end }
PLAYER = { map = 1411, x = 0.0, y = 0.0, facing = 0 }
function CreateVector2D(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end
C_Map = { SetUserWaypoint = function() end, ClearUserWaypoint = function() end,
  GetBestMapForUnit = function() return PLAYER.map end,
  GetPlayerMapPosition = function() return CreateVector2D(PLAYER.x, PLAYER.y) end,
  GetWorldPosFromMapPos = function(map, v) return 1, CreateVector2D((1 - v.y) * 1000, (1 - v.x) * 1000) end }
GetPlayerFacing = function() return 0 end
GetUnitSpeed = function() return 0 end
C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }
WorldMapFrame = object("Frame")
CANVAS = object("Frame"); WorldMapFrame.ScrollContainer = object("Frame")
function WorldMapFrame:GetMapID() return 1411 end
function WorldMapFrame:GetCanvas() return CANVAS end
function WorldMapFrame:GetCanvasScale() return 1 end
HBD = { world = {}, mini = {} }
function HBD:RemoveAllWorldMapIcons() self.world = {} end
function HBD:RemoveAllMinimapIcons() self.mini = {} end
function HBD:AddWorldMapIconMap(ref, icon, map, x, y) self.world[#self.world+1] = { icon = icon, map = map, x = x, y = y } end
function HBD:AddMinimapIconMap(ref, icon, map, x, y) self.mini[#self.mini+1] = { icon = icon, map = map, x = x, y = y } end
LibStub = function(name, silent) if name == "HereBeDragons-Pins-2.0" then return HBD end end
SOUNDS, FLASHES = {}, 0
PlaySound = function(id, channel) SOUNDS[#SOUNDS+1] = id end
FlashClientIcon = function() FLASHES = FLASHES + 1 end
SOUNDKIT = { RAID_WARNING = 8959 }
NAMES = {}
UnitName = function(unit) return NAMES[unit] end
UnitIsDead = function() return false end
'''


def find_block(step):
    return f"B1 = nil; for _, b in pairs(box.blocks) do if b.shown and b.rxStep == {step} then B1 = b end end"


def ui_box():
    """The guide box on a RestedXP route, as RestedXP shows it: a check box per line in each card, one list row per
    step, the Guides menu by route and part, map and minimap pins at the active steps' points, nameplate names with a
    sound for rare monsters, and the other starts dropped from memory at login."""
    ui = L.LuaRuntime(unpack_returned_tuples=True)
    for f in ("Locale.lua", "LocaleES.lua"):
        ui.execute((ADDON / f).read_text(encoding="utf-8"))
    ui.execute(UI_MOCK)
    ui.execute(FIXTURE)
    ui.execute("DATA.routes.Mulgore = { races = { 'Tauren' }, rxp = true, parts = { '1-6 Mulgore' }, steps = {}, rx = {} }")
    ui.execute("DufforthTweaksHelperGuideData = DATA")
    for f in ("Guide.lua", "GuideRx.lua", "GuideUI.lua", "GuideRxUI.lua"):
        ui.execute((ADDON / f).read_text(encoding="utf-8"))
    ev, run = ui.eval, ui.execute
    rx = "DufforthTweaksHelperGuideRxUI"
    fire = rx + ".events.scripts.OnEvent(" + rx + ".events, "
    # 6. Login: the other starts leave memory, the Orc's start stays.
    run(fire + "'PLAYER_LOGIN')")
    check("login: other starts' routes dropped", ev("DATA.routes.Mulgore == nil and DATA.routes.Hold == nil and DATA.routes.Durotar ~= nil") is True)
    check("login: their parts kept for the menu", ev("DATA.pruned.Mulgore.parts[1]") == "1-6 Mulgore")
    run("GU = DufforthTweaksHelperGuideUI; GU.Refresh(); box = DufforthTweaksHelperGuideBox")
    # 1. A check box per line inside each card.
    run(find_block(2))
    check("card: step 2 has a line per line of the step", ev("B1 ~= nil and B1.items[1].shown and B1.items[2].shown") is True)
    check("card: no whole-card check box on RestedXP's route", ev("B1.check.shown") is False)
    check("card: lines are open", ev("B1.items[1].check.mark.shown") is False)
    run("LOG[1] = true; GU.Refresh(); " + find_block(2))
    check("card: a line the game finished is ticked and locked", ev("B1.items[1].check.mark.shown and B1.items[1].check.locked") is True)
    run("B1.items[1].check.scripts.OnClick(B1.items[1].check)")
    check("card: a locked line can't be unticked", ev("GU.model:RxLineState(2)") == "game")
    run("B1.items[2].check.scripts.OnClick(B1.items[2].check)")
    check("card: ticking the last line finishes the step", ev("GU.model:RxLineState(3)") == "hand" and ev("GU.model:RxAt()") >= 3, ev("GU.model:RxAt()"))
    run("DufforthTweaksHelperGuideUI.Saved('Durotar').rx = nil; LOG = {}; GU.Refresh()")
    # 2. The step list: one row per RestedXP step.
    run("box.grip.scripts.OnMouseDown(box.grip); box.scripts.OnSizeChanged(box, 420, 900); box.grip.scripts.OnMouseUp(box.grip)")
    run("GU.follow, GU.scrolled = true, false; GU.Refresh()")
    nums = ev("(function() local o = {} for k = 1, 40 do local r = box.rows[k] if r and r.shown and not r.isHeader then o[#o+1] = r.num.text end end return table.concat(o, ',') end)()")
    check("list: one row per step, numbered per part like RestedXP (only steps for you)", str(nums).startswith("1,2,3,4,5,6,1"), nums)
    run("R2 = nil; for k = 1, 40 do local r = box.rows[k] if r and r.shown and r.rx == 2 then R2 = r end end")
    check("list: the row holds every line of the step", ev("R2 ~= nil and string.find(R2.label.text, '\\n') ~= nil") is True, ev("R2 and R2.label.text"))
    run("R2.check.scripts.OnClick(R2.check)")
    check("list: its check box ticks the whole step", ev("GU.model:RxStepTicked(2)") is True)
    run("DufforthTweaksHelperGuideUI.Saved('Durotar').rx = nil; GU.Refresh()")
    # 3. The Guides menu: each route with RestedXP's parts; another start needs a /reload.
    run("GU.FillGuideMenu(); E = box.guideMenu.entries")
    titles = str(ev("(function() local o = {} for _, e in ipairs(E) do o[#o+1] = e[2] end return table.concat(o, '|') end)()"))
    check("menu: the route and its RestedXP parts", "1-6 Durotar" in titles and "6-10 Durotar" in titles, titles)
    check("menu: another start, marked /reload", "Mulgore" in titles and "/reload" in titles, titles)
    pick = "for k, e in ipairs(E) do if e[2]:find('%s') then box.guideMenu.offset = k - 1 end end; GU.DrawGuideMenu(); box.guideRows[1].scripts.OnClick(box.guideRows[1])"
    run(pick % "6%-10 Durotar")
    check("menu: a part moves the pointer to its first step (step 8, skipped below level 4 by its .xp <4,1)",
          ev("GU.model:RxAt()") == 9 and ev("GU.model:RxState().back[#GU.model:RxState().back]") == 2, ev("GU.model:RxAt()"))
    run(pick % "1%-6 Mulgore")
    note = ev("GU.switchNote and GU.switchNote.text")
    check("menu: another start is picked for the next /reload", ev("DufforthTweaksHelperDB.guide.guideName") == "Mulgore"
          and ev("DufforthTweaksHelperDB.guide.pendingPart.part") == 0 and "/reload" in str(note), note)
    check("menu: until then the guide stays on your start", ev("GU.RouteName()") == "Durotar", ev("GU.RouteName()"))
    run("DufforthTweaksHelperDB.guide.guideName = nil; DufforthTweaksHelperDB.guide.pendingPart = nil; DufforthTweaksHelperGuideUI.Saved('Durotar').rx = nil; GU.Refresh()")
    # 4. Map and minimap pins at every point of the active steps, numbered by step, lines between a step's points.
    run("GU.SafeDrawMap()")
    labels = ev("(function() local o = {} for _, w in ipairs(HBD.world) do o[#o+1] = w.icon.num.text end return table.concat(o, ',') end)()")
    check("map: a pin at each point of the active steps, with its step number", labels == "1,1,2", labels)
    check("map: a line between the points of a step", ev("(function() local n = 0 for _, l in ipairs(LINES) do if l.shown then n = n + 1 end end return n end)()") == 1)
    run("GU.DrawMinimapPins(GU.model)")
    check("minimap: the same pins", ev("#HBD.mini") == 3 and ev("HBD.mini[3].x") == 0.4, ev("#HBD.mini"))
    # 5. Nameplates: names of the active steps' monsters; a sound for rare ones (.unitscan), once a minute.
    run("NAMES.nameplate1 = 'Warlord Kolkanis'; " + fire + "'NAME_PLATE_UNIT_ADDED', 'nameplate1')")
    check("scan: a rare monster's nameplate plays a sound and flashes the game icon", ev("#SOUNDS") == 1 and ev("FLASHES") == 1)
    run(fire + "'NAME_PLATE_UNIT_ADDED', 'nameplate1')")
    check("scan: not again right away", ev("#SOUNDS") == 1)
    run("NOW = 200; " + fire + "'NAME_PLATE_UNIT_ADDED', 'nameplate1')")
    check("scan: again after a minute", ev("#SOUNDS") == 2)
    run("NAMES.mouseover = 'Mottled Boar'; " + fire + "'UPDATE_MOUSEOVER_UNIT')")
    check("scan: a step's monster is seen, no sound", ev("#SOUNDS") == 2 and ev(rx + ".seen['Mottled Boar']") == 200)
    macro = str(ev("DufforthTweaksHelperGuideBar.target.attrs.macrotext"))
    check("scan: the target button goes for the rare one seen first", macro.split("\n")[1:2] == ["/targetexact Warlord Kolkanis"], macro)
    run("DufforthTweaksHelperDB.guide.scanSound = false; NOW = 400; " + fire + "'NAME_PLATE_UNIT_ADDED', 'nameplate1')")
    check("scan: the Menu option turns the sound off", ev("#SOUNDS") == 2)
    # 7. Next to RestedXP (2026-11-27 screenshot): its saved place moves ours; cards have "Step N" only on yours;
    # each character keeps its own place.
    run("DufforthTweaksHelperGuideUI.Saved('Durotar').rx = nil; LOG = {}; GU.Refresh()")
    run("RXPCData = { currentGuideGroup = 'RestedXP Forever Guide (H)', currentGuideName = '6-10 Durotar', currentStep = 2 }; GU.Refresh()")
    check("RestedXP's place: ours goes to the same part and step", ev("GU.model:RxAt()") == 9 and ev("GU.model:RxNumber(9)") == 2, ev("GU.model:RxAt()"))
    run("RXPCData = nil; " + find_block(9))
    check("card: 'Step 2' (RestedXP's number in the part) on your step", ev("B1 ~= nil and B1.header.text") == "|cffffd100Step 2|r", ev("B1 and B1.header.text"))
    check("RestedXP's dungeon guide doesn't move the main route",
          ev("DufforthTweaksHelperGuideRxUI.RestedXPPlace('Durotar') == nil and true") is None
          or ev("(function() RXPCData = { currentGuideGroup = 'RestedXP Forever Dungeon Guide (H)', currentGuideName = '1-6 Durotar', currentStep = 1 } local p = DufforthTweaksHelperGuideRxUI.RestedXPPlace('Durotar') RXPCData = nil return p == nil end)()") is True)
    run("UnitGUID = function() return 'Player-2' end; GU.Refresh()")
    check("another character: its own place (a fresh start), the first one's kept",
          ev("GU.model:RxAt()") != 9 and ev("DufforthTweaksHelperDB.guide.chars['Player-2'] ~= nil") is True)
    run("UnitGUID = nil")
    # 8. RestedXP's size (user, 2026-11-28 screenshot: "the windows is using to much spaces ... rested xp is not that
    # bigger", and a "2899" step counter): no top strip or counter, the card first, the part line under it, Menu and
    # minimize as small icons; back / skip / best are in the Menu; pins carry RestedXP's step numbers.
    run("DufforthTweaksHelperGuideUI.Saved('Durotar').rx = nil; LOG = {}; GU.Refresh()")
    check("compact: no step counter or arrows on top", ev("box.stepNum.shown or box.back.shown or box.skip.shown") is False)
    check("compact: no Best button or strip on top", ev("box.best.shown or box.strip.shown") is False)
    check("compact: Menu and minimize stay, as small icons", ev("box.menuButton.shown and box.hide.shown") is True
          and ev("box.menuButton.size[1] <= 18 and box.hide.size[1] <= 18") is True, ev("box.menuButton.size and box.menuButton.size[1]"))
    run("DufforthTweaksHelperDB.guide.size = nil; box.w, box.h = false, false; GU.switchNote, GU.viewing, GU.override = nil, nil, nil; GU.Refresh()")
    run(find_block(2))
    check("compact: about RestedXP's width (a new box: the card is under 230)", ev("B1.size[1]") <= 230, ev("B1.size[1]"))
    check("compact: the first card starts at the top", ev("box.blocks[1].pt[5]") >= -6, ev("box.blocks[1].pt[5]"))
    check("compact: the part line sits under the cards", ev("box.progress.pt[5] < B1.pt[5]") is True, ev("box.progress.pt[5]"))
    run("box.skipRow.scripts.OnClick(box.skipRow)")
    check("Menu: 'Skip this step' moves the pointer on", ev("GU.model:RxAt()") > 2, ev("GU.model:RxAt()"))
    run("box.backRow.scripts.OnClick(box.backRow)")
    check("Menu: 'Previous step' goes back", ev("GU.model:RxAt()") == 2, ev("GU.model:RxAt()"))
    check("Menu: 'Best step for my level' is there", ev("box.bestRow ~= nil and box.bestRow.text ~= nil") is True)
    run("GU.DrawMinimapPins(GU.model)")
    labels = ev("(function() local o = {} for _, p in ipairs(HBD.mini) do o[#o+1] = p.icon.num.text end return table.concat(o, ',') end)()")
    want = ev("(function() local o = {} for _, p in ipairs(GU.model:RxPins()) do o[#o+1] = tostring(GU.model:RxNumber(p.n)) end return table.concat(o, ',') end)()")
    check("minimap: pins show RestedXP's step number in the part, not our row number", labels == want and labels != "", (labels, want))
    # 9. No "Arrow on: Step 806" bar for a step you're on (user, 2026-11-28 screenshot, circled: "fix"): a click on a
    # card of an active step keeps the arrow as it is; a pinned other step says RestedXP's number; the bar ends left
    # of the "=" and "_" icons.
    run("GU.override, GU.viewing = nil, nil; DufforthTweaksHelperGuideUI.Saved('Durotar').rx = nil; LOG = {}; GU.Refresh(); " + find_block(2))
    run("B1.scripts.OnMouseUp(B1, 'LeftButton')")
    check("card click on your step: no 'Arrow on' bar", ev("GU.override == nil and not box.viewBar.shown") is True, ev("GU.override and GU.override.text"))
    run("GU.PinStep(DATA.routes.Durotar.rx[8].a)")
    text = str(ev("box.viewBar.label.text"))
    check("a pinned step ahead: RestedXP's number in its part (step 8 = '6-10' step 1)", "Step 1:" in text and "Step 8" not in text and "Step 11" not in text, text)
    check("the bar ends left of the corner icons", ev("box.viewBar.width") <= ev("box.blocks[1].size[1]") - 34, (ev("box.viewBar.width"), ev("box.blocks[1].size[1]")))
    run("GU.BackToStep()")


def real_memory():
    """GuideData holds six RestedXP routes; at login only your start's two stay (user brief, 2026-11-27: 59.7 MB of Lua
    memory, 17.5 MB with one start kept)."""
    lua = runtime()
    lua.execute((ADDON / "GuideData.lua").read_text(encoding="utf-8"))
    r = lua.execute("""
collectgarbage("collect")
local before = collectgarbage("count")
local D = DufforthTweaksHelperGuideData
local n = G.PruneRoutes(D, { Durotar = true, ["Durotar (dungeons)"] = true })
collectgarbage("collect")
local after = collectgarbage("count")
local kept = 0
for _ in pairs(D.routes) do kept = kept + 1 end
return { before = math.floor(before / 1024), after = math.floor(after / 1024), pruned = n, kept = kept }
""")
    r = dict(r.items())
    print(f"     memory: {r['before']} MB with every route, {r['after']} MB after dropping {r['pruned']} routes")
    check("memory: the other four starts' routes are dropped", r["pruned"] == 4, r)
    check("memory: under half the Lua memory with one start kept", r["after"] < r["before"] * 0.5, r)


def real_walk():
    """Plays the real Durotar route as an Orc Warrior, doing what each active step asks; the pointer must visit
    RestedXP's steps in order, never go back, and reach the end."""
    lua = runtime()
    lua.execute((ADDON / "GuideData.lua").read_text(encoding="utf-8"))
    for name in ("Durotar", "Mulgore (dungeons)"):
        result = lua.execute("""
local name = ...
local D = DufforthTweaksHelperGuideData
T = NEWT({ level = 1, race = name == "Durotar" and "Orc" or "Tauren" })
local S = { skipped = {} }
local function M() return G.NewModel(D, name, GAME(T), S) end
local steps = D.routes[name].steps
local last, back, visited, quests, guard = 0, 0, 0, 0, 0
local order_ok = true
local stuckAt, stuck, skips = 0, 0, 0
local lastQuestStep = 0
while guard < 60000 do
  guard = guard + 1
  local m = M()
  local act = m:RxActive()
  if m:RxFinished() then break end
  local at = m:RxAt()
  if at < last then back = back + 1 end
  if at > last then visited = visited + 1 end
  last = at
  local did = false
  for _, n in ipairs(act) do
    for _, r in ipairs(m:RxOpenRows(n)) do
      local s = steps[r]; local k, q, a = s[1], s[2], s[12] or {}
      T.zone = s[3] or T.zone
      if s[6] and s[6] > T.level then T.level, T.cur = s[6], 0 end
      if k == "accept" then T.log[q] = true
      elseif k == "turnin" then T.done[q] = true; T.log[q] = nil
      elseif k == "do" then T.obj[q] = true; T.complete[q] = true
      elseif k == "goto" then T.pos = { s[3], s[4], s[5] }; m:RxArrow()
      elseif k == "grind" then
        if (a.l or 0) > T.level then T.level, T.cur = a.l, 0 end
        if a.x and a.x < 0 then T.level = math.max(T.level, a.l) end
        if a.x and a.x >= 1 then T.cur = math.max(T.cur or 0, a.x) elseif a.x then T.cur = (T.max or 1000) end
      elseif k == "collect" then T.items[a.i] = a.n or 1
      elseif k == "train" then T.spells[a.s] = true
      elseif k == "abandon" then for _, id in ipairs(a.q or { q }) do T.log[id] = nil end
      elseif k == "zone" then T.zone = a.z
      elseif k == "subzone" then T.area = a.id
      elseif k == "home" and a.ai then T.bind = a.ai
      elseif k == "destroy" then T.items[a.i] = 0
      else m:ToggleStep(r) end
      if (k == "accept" or k == "turnin") and n == at then
        if n < lastQuestStep then order_ok = false end
        lastQuestStep = n; quests = quests + 1
      end
      did = true
    end
  end
  -- Nothing to do here, or still stuck after doing it (an objective of a quest you couldn't take, like RestedXP): skip.
  if at == stuckAt then stuck = stuck + 1 else stuckAt, stuck = at, 0 end
  if not did or stuck >= 3 then M():Skip(); skips = skips + 1; stuck = 0 end
end
return { skips = skips, guard = guard, back = back, visited = visited, quests = quests, order = order_ok, finished = M():RxFinished(), total = #D.routes[name].rx, level = T.level }
""", name)
        r = dict(result.items())
        check(f"{name}: the walk reaches the end of RestedXP's route", r["finished"] is True and r["guard"] < 60000, r)
        check(f"{name}: the pointer never goes back", r["back"] == 0, r["back"])
        check(f"{name}: quest steps done in RestedXP's order", r["order"] is True)
        check(f"{name}: most quest steps taken and handed in on the way", r["quests"] > 1500, r["quests"])
        check(f"{name}: few steps you must skip by hand", r["skips"] < r["total"] // 20, r["skips"])


if __name__ == "__main__":
    main()
