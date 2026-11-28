"""Runs the leveling log (LevelLog.lua) outside the game: quests (accept, progress, complete, turn in, abandon),
level ups, hearth, flights, deaths and corpse runs, vendor/trainer/inn visits, zone changes, the guide's own moves
(step done, skipped by hand, back, part change), idle and AFK time, XP from kills vs quests and rested XP used,
the 5,000-row cap, the on/off switch, Clear, and no chat output.

    python tests/addon/levellog_sim.py
"""
import os
import sys

import lupa.lua51 as L

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(HERE, "..", "..", "addon", "DufforthTweaksHelper")

lua = L.LuaRuntime(unpack_returned_tuples=True)
lua.execute(r"""
NOW = 1000
CHAT = {}
print = function(...) CHAT[#CHAT + 1] = table.concat({...}, " ") end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) CHAT[#CHAT + 1] = m end }
local function object()
  local o = { scripts = {}, events = {} }
  function o:SetScript(k, f) self.scripts[k] = f end
  function o:RegisterEvent(e) self.events[e] = true end
  return o
end
FRAMES = {}
function CreateFrame() local f = object(); FRAMES[#FRAMES + 1] = f; return f end
UnitGUID = function(u) return u == "player" and "Player-1-0000000A" or nil end
UnitRace = function() return "Orc", "Orc" end
UnitClass = function() return "Warrior", "WARRIOR" end

-- The guide: a RestedXP step engine stand-in (the real one is GuideRx.lua).
DufforthTweaksHelperGuide = { Rx = {} }
local Rx = DufforthTweaksHelperGuide.Rx
RECS = { { p = 0, ln = 5 }, { p = 0, ln = 8, pt = { { "Durotar", 42, 67 } } }, { p = 0, ln = 12 }, { p = 1, ln = 3, pt = { { "Durotar", 30, 30 } } } }
STATE = { at = 1, back = {} }
function Rx:RxState() return STATE end
function Rx:Rec(n) return RECS[n] end
function Rx:RxNumber(n) return ({ 1, 2, 3, 1 })[n] end
function Rx:RxPartName(p) return ({ [0] = "1-6 Durotar", [1] = "6-10 Durotar" })[p] end
function Rx:Skip() STATE.back[#STATE.back + 1] = STATE.at; STATE.at = STATE.at + 1 end
function Rx:Back() STATE.at = table.remove(STATE.back) or STATE.at end
function Rx:RxGoTo(n) STATE.at = n end
DufforthTweaksHelperGuideUI = { model = setmetatable({ rxp = true, routeName = "Durotar" }, { __index = Rx }) }
""")
lua.execute(open(os.path.join(ADDON, "LevelLog.lua"), encoding="utf-8").read())
lua.execute(r"""
LL = DufforthTweaksHelperLevelLog
G = { level = 5, xp = 1000, xpMax = 2800, rested = 300, zone = "Durotar", x = 40, y = 60, afk = false, combat = false,
      taxi = false, dead = false, ghost = false, resting = false, npc = 3167, log = {}, obj = {}, inGuide = { [4641] = true },
      titles = { [4641] = "Your Place In The World", [9999] = "A Forever Quest" } }
LL.game = {
  now = function() return NOW end, level = function() return G.level end, xp = function() return G.xp end,
  xpMax = function() return G.xpMax end, rested = function() return G.rested end, zone = function() return G.zone end,
  pos = function() return G.x, G.y end, afk = function() return G.afk end, combat = function() return G.combat end,
  taxi = function() return G.taxi end, dead = function() return G.dead end, ghost = function() return G.ghost end,
  resting = function() return G.resting end, npc = function() return G.npc end,
  inGuide = function(id) return G.inGuide[id] or false end, title = function(id) return G.titles[id] end,
  logIds = function() return G.log end, objectives = function(id) return G.obj[id] end,
  who = function() return "Orc WARRIOR" end,
}
function EV(...) LL.OnEvent(nil, ...) end
function AT(t) NOW = t; LL.Tick() end
""")
g = lua.globals()
LL = g.LL
fails = []


def check(name, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + name + (("  [" + str(detail) + "]") if detail and not ok else ""))
    if not ok:
        fails.append(name)


def rows():
    out = []
    for i in range(1, int(LL.Count()) + 1):
        out.append(str(LL.Char().rows[i]))
    return out


def kinds():
    return [r.split(";")[1] for r in rows()]


def last(kind):
    found = [r for r in rows() if r.split(";")[1] == kind]
    return found[-1] if found else ""


def extra(row):
    parts = row.split(";")[11]
    return dict(p.split("=", 1) for p in parts.split(",") if "=" in p)


def ex(code):
    lua.execute(code)


# ---- login and the row shape ----
ex('EV("PLAYER_LOGIN")')
r = last("lg")
f = r.split(";")
check("login row", f[1] == "lg" and f[0] == "1000" and f[2] == "5" and f[3] == "1000", r)
names = LL.Char().names
check("zone, route and part are names", names[int(f[4])] == "Durotar" and names[int(f[7])] == "Durotar" and names[int(f[8])] == "1-6 Durotar", r)
check("step number and line", f[9] == "1" and f[10] == "5" and f[5] == "40.0" and f[6] == "60.0", r)
check("character kept by GUID with class, no name", LL.Char().who == "Orc WARRIOR" and g.DufforthTweaksHelperDB.levelLog.chars["Player-1-0000000A"] is not None)

# ---- quests ----
ex('G.log = { 4641 }; G.obj[4641] = { { 0, 10 } }; EV("QUEST_ACCEPTED", 1, 4641)')
check("accepted, in the guide", extra(last("qa")) == {"q": "4641", "g": "1"}, last("qa"))
check("title kept once per character", LL.Char().quests[4641] == "Your Place In The World")
ex('G.obj[4641] = { { 3, 10 } }; EV("QUEST_LOG_UPDATE"); AT(1002)')
check("objective progress", extra(last("qp")) == {"q": "4641", "o": "1", "n": "3/10"}, last("qp"))
n_before = kinds().count("qp")
ex('EV("QUEST_LOG_UPDATE"); AT(1004)')
check("no progress row without a change", kinds().count("qp") == n_before)
ex('G.obj[4641] = { { 10, 10 } }; EV("QUEST_LOG_UPDATE"); AT(1006)')
check("completed when every objective is done", extra(last("qc")).get("q") == "4641", kinds())
ex('G.log = {}; EV("QUEST_TURNED_IN", 4641, 120, 50); EV("QUEST_REMOVED", 4641); G.xp = 1120; EV("PLAYER_XP_UPDATE", "player"); AT(1008)')
check("turned in with its XP", extra(last("qt")) == {"q": "4641", "x": "120", "g": "1"}, last("qt"))
check("a turned-in quest is not abandoned", "qx" not in kinds())
ex('G.log = { 9999 }; G.obj[9999] = { { 0, 1 } }; EV("QUEST_ACCEPTED", 9999)')
check("off-guide accept (newer client: id only)", extra(last("qa")) == {"q": "9999", "g": "0"}, last("qa"))
ex('G.log = {}; EV("QUEST_REMOVED", 9999); AT(1012)')
check("abandoned", extra(last("qx")).get("q") == "9999", kinds())

# ---- XP: kills vs quests, rested used ----
ex('G.xp = 1170; G.rested = 275; EV("PLAYER_XP_UPDATE", "player"); AT(1014)')   # a kill: 50, 25 of it rested
ex('G.zone = "The Barrens"; EV("ZONE_CHANGED_NEW_AREA"); AT(1015)')
xs = extra(last("xs"))
check("XP summary on zone change: quests 120, kills 50, rested 25", xs == {"k": "50", "q": "120", "r": "25"}, last("xs"))
check("zone change row", last("zc") != "" and names[int(last("zc").split(";")[4])] == "The Barrens", last("zc"))
ex('G.level = 6; G.xp = 30; G.xpMax = 3600; EV("PLAYER_LEVEL_UP", 6); AT(1016)')
check("level up", last("lv").split(";")[2] == "6", last("lv"))
ex('EV("PLAYER_XP_UPDATE", "player"); AT(1017); EV("ZONE_CHANGED_NEW_AREA"); AT(1018)')
check("XP across a level-up counts the rest of the old level", extra(last("xs")).get("k") == "1660", last("xs"))

# ---- travel ----
ex('EV("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 8690)')
check("hearthstone", last("hs") != "")
ex('G.taxi = true; AT(1020); G.taxi = false; G.x, G.y = 51, 30; AT(1110)')
check("flight start and landing with its time", last("fs") != "" and extra(last("fl")).get("s") == "90", kinds())

# ---- death and corpse run ----
ex('NOW = 1120; G.dead = true; EV("PLAYER_DEAD"); G.dead = false; G.ghost = true; AT(1150); G.ghost = false; NOW = 1180; EV("PLAYER_UNGHOST")')
check("death", last("dd") != "")
check("corpse run back with its time", extra(last("rz")) == {"s": "60", "c": "1"}, last("rz"))

# ---- vendor, trainer, inn ----
ex('EV("MERCHANT_SHOW"); NOW = 1220; EV("MERCHANT_CLOSED")')
check("vendor visit with its time", extra(last("vn")) == {"npc": "3167", "s": "40"}, last("vn"))
ex('EV("TRAINER_SHOW"); NOW = 1230; EV("TRAINER_CLOSED")')
check("trainer visit", extra(last("tr")).get("s") == "10", last("tr"))
ex('G.resting = true; EV("PLAYER_UPDATE_RESTING"); EV("HEARTHSTONE_BOUND")')
check("inn (resting) and hearth bound", last("in") != "" and last("hb") != "", kinds())

# ---- the guide's own moves ----
ex('STATE.at = 2; AT(1240)')
gd = last("gd")
check("step done when the pointer moves on", gd.split(";")[9] == "2" and gd.split(";")[10] == "8" and extra(gd) == {"f": "5", "pz": "1", "px": "42.0", "py": "67.0"}, gd)
ex('DufforthTweaksHelperGuideUI.model:Skip(); AT(1250)')
check("skipped by hand", last("gs").split(";")[10] == "12" and extra(last("gs")).get("f") == "8", last("gs"))
ex('DufforthTweaksHelperGuideUI.model:Back(); AT(1255)')
check("back", last("gb").split(";")[10] == "8", last("gb"))
ex('STATE.at = 4; AT(1260)')
gp = last("gp")
check("part change", names[int(gp.split(";")[8])] == "6-10 Durotar" and gp.split(";")[9] == "1", gp)

# ---- idle and AFK ----
ex('AT(1300); AT(1400); AT(1450)')
check("idle after two minutes without moving", last("ia") != "" and last("ia").split(";")[0] == "1260", last("ia"))
ex('G.x = 60; AT(1500)')
check("idle ends with its time when you move", extra(last("ie")).get("s") == "240", last("ie"))
ex('G.afk = true; EV("PLAYER_FLAGS_CHANGED", "player"); NOW = 1600; G.afk = false; EV("PLAYER_FLAGS_CHANGED", "player")')
check("AFK on and off with its time", extra(last("ak")).get("s") == "100", kinds())
ex('G.combat = true; AT(1700); AT(1900)')
check("no idle row in combat", kinds().count("ia") == 1)
ex('G.combat = false')

# ---- position samples ----
ex('G.x = 70; AT(1970)')
check("a position sample once a minute while moving", last("ps") != "", kinds()[-3:])

# ---- off, clear, cap, chat ----
count = int(LL.Count())
ex('LL.Options().on = false; EV("PLAYER_LEVEL_UP", 7)')
check("the switch turns logging off", int(LL.Count()) == count)
ex('LL.Options().on = nil')
ex('for i = 1, 5100 do LL.Add("ps") end')
check("cap: at most 5,000 rows", int(LL.Count()) <= 5000 and int(LL.Count()) >= 4750, LL.Count())
check("cap drops the oldest first", rows()[-1].split(";")[1] == "ps" and "lg" not in kinds())
summary = LL.Summary()
check("summary for the Menu", int(summary.rows) == int(LL.Count()) and int(summary.max) == 5000)
ex('LL.Clear()')
check("Clear empties this character's log", int(LL.Count()) == 0)
ex('error_test = pcall(LL.OnEvent, nil, "QUEST_ACCEPTED", nil, nil)')
check("bad event args don't error", g.error_test)
check("no chat output", len(list(g.CHAT.values())) == 0, list(g.CHAT.values()))

print(("%d checks failed" % len(fails)) if fails else "all leveling log checks pass")
sys.exit(1 if fails else 0)
