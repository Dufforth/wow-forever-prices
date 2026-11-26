"""Runs the Hunter fight log outside the game: a fight with Hunter's Mark twice on one target, three Summon Hawks
(the third with two still out), a Mongoose Bite window used and one missed, Auto Shots, an error, a death; and
nothing logged for other classes.

    python tests/addon/hunter_sim.py
"""
import os
import sys

import lupa.lua51 as L

HERE = os.path.dirname(os.path.abspath(__file__))
_src = open(os.path.join(HERE, "warrior_sim.py"), encoding="utf-8").read().split("lua = L.LuaRuntime")[0]
_env = {"__file__": os.path.join(HERE, "warrior_sim.py")}
exec(_src, _env)
MOCK, source = _env["MOCK"], _env["source"]

lua = L.LuaRuntime(unpack_returned_tuples=True)
for name in ("Locale.lua", "LocaleES.lua"):
    lua.execute(source(name))
lua.execute(MOCK)
lua.execute("""
CLASS = "HUNTER"; UnitClass = function() return "Hunter", CLASS end
NOW = 100; GetTime = function() return NOW end
TARGET = "Creature-0-0-0-0-111-0000AAAAAA"
UnitGUID = function(u) if u == "target" then return TARGET end return "Player-1" end
UnitName = function(u) if u == "pet" then return "Screech" end return "Dufforth" end
UnitCreatureFamily = function() return "Bat" end
UnitIsDead = function() return false end
MANA = 80; UnitPower = function() return MANA end; UnitPowerMax = function() return 100 end
MONGOOSE = false
IsUsableSpell = function(n) if n == "Mongoose Bite" then return MONGOOSE end return true end
NAMES = { [1] = "Hunter's Mark", [2] = "Summon Hawk", [3] = "Arcane Shot", [4] = "Mongoose Bite", [5] = "Auto Shot", [6] = "Aimed Shot" }
GetSpellInfo = function(id) return NAMES[id] end
MACROTEXT = { [121] = "#showtooltip\\n/castsequence reset=target Hunter's Mark,nil\\n/cast Arcane Shot", [122] = "/say hi" }
GetNumMacros = function() return 0, 2 end
GetMacroInfo = function(i) if MACROTEXT[i] then return "M" .. i, 1, MACROTEXT[i] end end
""")
lua.execute(source("Core.lua"))
lua.execute(source("Warrior.lua"))
lua.execute(source("Hunter.lua"))
g = lua.globals()
H = g.DufforthTweaksHelperHunter
fails = []


def check(name, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + name + (("  [" + str(detail) + "]") if detail and not ok else ""))
    if not ok:
        fails.append(name)


def event(*args):
    lua.globals().H_EV = lua.table_from(list(args))
    lua.execute("DufforthTweaksHelperHunter.OnEvent(nil, unpack(H_EV))")


def at(t):
    lua.execute(f"NOW = {100 + t}")


def cast(spell_id):
    event("UNIT_SPELLCAST_SENT", "player", "target", "guid", spell_id)
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", spell_id)


event("PLAYER_REGEN_DISABLED")
check("a hunter's fight starts", H.Current() is not None)
at(0.5); cast(1)                                   # Hunter's Mark
at(1); event("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 5)   # Auto Shot
at(2); cast(2)                                     # hawk 1
at(3); event("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 5)
at(8); cast(2)                                     # hawk 2
at(9); lua.execute("MONGOOSE = true"); H.Tick()    # you dodged: window 1
at(9.5); cast(4)                                   # used
at(10); lua.execute("MONGOOSE = false"); H.Tick()
at(11); cast(2)                                    # hawk 3 with two out (wasted)
at(12); lua.execute("MONGOOSE = true"); H.Tick()   # window 2, missed
at(14); lua.execute("MONGOOSE = false"); H.Tick()
at(15); cast(1)                                    # Hunter's Mark again on the same target
at(16); event("UI_ERROR_MESSAGE", 50, "Target too close")
at(17); event("UNIT_SPELLCAST_INTERRUPTED", "player", "g", 6)
at(20); event("PLAYER_DEAD")
event("PLAYER_REGEN_ENABLED")

fights = g.DufforthTweaksHelperDB.hunter.fights
check("the fight is saved", len(fights) == 1)
f = fights[1]
check("seconds and result", f.seconds == 20 and f.result == "died", (f.seconds, f.result))
check("Hunter's Mark twice on one target is counted", f.markRepeats == 1, f.markRepeats)
check("hawks: never more than 2 out counted, the extra one flagged", f.hawkMax == 2 and f.hawkOver == 1, (f.hawkMax, f.hawkOver))
check("Mongoose Bite: 2 windows, 1 used", f.mongooseWindows == 2 and f.mongooseUsed == 1, (f.mongooseWindows, f.mongooseUsed))
check("Auto Shots counted, not listed", f.autoShots == 2 and not any("Auto Shot" in str(c) for c in f.casts.values()))
check("casts carry target and hawks out", any(str(c).startswith("11.0 Summon Hawk t:AAAAAA h:") for c in f.casts.values()),
      list(f.casts.values()))
check("errors counted", f.errors["Target too close"] == 1)
check("interrupted Aimed Shot in the tries", any(" I Aimed Shot" in str(t) for t in f.tries.values()))
check("Mongoose windows in the tries", any("M+ Mongoose Bite" in str(t) for t in f.tries.values()))
check("pet, family, mana", f.pet == "Screech" and f.petFamily == "Bat" and f.manaStart == 80, (f.pet, f.petFamily, f.manaStart))
macros = g.DufforthTweaksHelperDB.hunter.macros
check("only hunter macros are kept, by number", f.macros == "1" and len(macros) == 1 and "Hunter's Mark" in macros[1], (f.macros, len(macros)))
check("hawks out helper", H.HawksOut(lua.table_from([0, 6]), 17.9) == 2 and H.HawksOut(lua.table_from([0, 6]), 18) == 1)

lua.execute('CLASS = "WARRIOR"')
event("PLAYER_REGEN_DISABLED")
check("other classes: nothing logged", H.Current() is None)
lua.execute('CLASS = "HUNTER"')
g.DufforthTweaksHelperDB.hunter.log = False
event("PLAYER_REGEN_DISABLED")
check("log off: nothing logged", H.Current() is None)
g.DufforthTweaksHelperDB.hunter.log = True
event("PLAYER_REGEN_DISABLED"); at(21); event("PLAYER_REGEN_ENABLED")
check("an empty 1 s fight isn't kept", len(g.DufforthTweaksHelperDB.hunter.fights) == 1)
check("no frame registers the combat log (forbidden on Forever)", not any(fr.events["COMBAT_LOG_EVENT_UNFILTERED"] for fr in g.FRAMES.values()))

print(f"{len(fails)} failed" if fails else "all passed")
sys.exit(1 if fails else 0)
