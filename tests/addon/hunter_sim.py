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
UnitName = function(u) if u == "pet" then return "Screech" end return "Testchar" end
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
check("each Auto Shot's time is saved (to measure clipping)", f.autoTimes is not None and list(f.autoTimes.values()) == [1.0, 3.0],
      f.autoTimes and list(f.autoTimes.values()))
check("casts carry target and hawks out", any(str(c).startswith("11.0 Summon Hawk t:AAAAAA h:") for c in f.casts.values()),
      list(f.casts.values()))
check("errors counted", f.errors["Target too close"] == 1)
check("interrupted Aimed Shot in the tries", any(" I Aimed Shot" in str(t) for t in f.tries.values()))
check("Mongoose windows in the tries", any("M+ Mongoose Bite" in str(t) for t in f.tries.values()))
check("pet, family, mana", f.pet == "Screech" and f.petFamily == "Bat" and f.manaStart == 80, (f.pet, f.petFamily, f.manaStart))
macros = g.DufforthTweaksHelperDB.hunter.macros
check("only hunter macros are kept, by number", f.macros == "1" and len(macros) == 1 and "Hunter's Mark" in macros[1], (f.macros, len(macros)))
check("hawks out helper", H.HawksOut(lua.table_from([0, 6]), 17.9) == 2 and H.HawksOut(lua.table_from([0, 6]), 18) == 1)

# Hawks live 18 s across fights: chained pulls (2-6 s apart) summoned a third hawk that the per-fight count missed.
event("PLAYER_REGEN_DISABLED"); at(200); cast(2); at(206); cast(2); at(210); event("PLAYER_REGEN_ENABLED")
event("PLAYER_REGEN_DISABLED"); at(213); cast(2); at(214); event("PLAYER_REGEN_ENABLED")
last = g.DufforthTweaksHelperDB.hunter.fights[len(g.DufforthTweaksHelperDB.hunter.fights)]
check("a hawk with two still out from the last fight counts as a third hawk", last.hawkOver == 1, last.hawkOver)
check("hawks out when the fight starts are saved", last.hawksAtStart == 2, last.hawksAtStart)
check("H.HawksAlive counts across fights", H.HawksAlive() == 2, H.HawksAlive())

# In melee the game's Auto Shot repeat fails ~20 times every 0.1 s: it filled the 500 tries by 11 s (18:44 fight).
event("PLAYER_REGEN_DISABLED")
for i in range(600):
    at(30 + i * 0.01)
    event("UNIT_SPELLCAST_FAILED", "player", "g", 5)
    event("UI_ERROR_MESSAGE", 50, "Target too close")
at(40); cast(2)
cur = H.Current()
listed = list(cur.tries.values())
check("Auto Shot repeats are counted, not listed", cur.autoFails == 600 and not any("F Auto Shot" in str(t) for t in listed), cur.autoFails)
check("repeated error text is listed once a second, then counted", sum("Target too close" in str(t) for t in listed) <= 7
      and cur.errors["Target too close"] == 600, sum("Target too close" in str(t) for t in listed))
check("a later press is still in the log", any("C Summon Hawk" in str(t) for t in listed))
event("PLAYER_REGEN_ENABLED")

lua.execute('CLASS = "WARRIOR"')
event("PLAYER_REGEN_DISABLED")
check("other classes: nothing logged", H.Current() is None)
lua.execute('CLASS = "HUNTER"')
g.DufforthTweaksHelperDB.hunter.log = False
event("PLAYER_REGEN_DISABLED")
check("log off: nothing logged", H.Current() is None)
g.DufforthTweaksHelperDB.hunter.log = True
kept = len(g.DufforthTweaksHelperDB.hunter.fights)
event("PLAYER_REGEN_DISABLED"); at(21); event("PLAYER_REGEN_ENABLED")
check("an empty 1 s fight isn't kept", len(g.DufforthTweaksHelperDB.hunter.fights) == kept)
check("no frame registers the combat log (forbidden on Forever)", not any(fr.events["COMBAT_LOG_EVENT_UNFILTERED"] for fr in g.FRAMES.values()))

# ---- The DTH Hunter macro (built from the 300-fight review, 2026-11-26) ----
def known(*names):
    return lua.table_from({n: True for n in names})


def lines_of(t):
    return [t[i] for i in range(1, len(t) + 1)]


FULL = ("Hunter's Mark", "Summon Hawk", "Aimed Shot", "Arcane Shot", "Raptor Strike", "Auto Shot", "Mongoose Bite")
full = lines_of(H.BuildLines(known(*FULL)))
check("full macro: pet first, a hawk on the first press, the mark in the hawk wait", full == [
    "#showtooltip", "/targetenemy [noharm][dead]", "/petattack",
    "/castsequence reset=combat Summon Hawk,Hunter's Mark,Summon Hawk,Arcane Shot,Summon Hawk,Summon Hawk,Arcane Shot",
    "/cast Raptor Strike", "/cast !Auto Shot", "/cast Mongoose Bite"], full)
body = "\n".join(lines_of(H.Fit(known(*FULL))))
check("full macro fits 255 and keeps the Auto Shot line whole", len(body) <= 255 and "/cast !Auto Shot" in body, len(body))
check("#showtooltip stays (else the button shows a question mark) and Mongoose Bite fits", body.startswith("#showtooltip") and "Mongoose" in body, len(body))
check("no Aimed Shot (short farming fights; it stalled the button in melee)", "Aimed Shot" not in body)
check("Hunter's Mark once per pull, inside the plan", body.count("Hunter's Mark") == 1)


def plan(alive, cd):
    steps, times = H.PlanSteps(known(*FULL), lua.table_from(alive), cd)
    return [steps[i] for i in range(1, len(steps) + 1)], [times[i] for i in range(1, len(times) + 1)]


def never_three(alive, cd):
    steps, times = plan(alive, cd)
    exp = list(alive)
    for s, at in zip(steps, times):
        if s == "Summon Hawk":
            if sum(1 for e in exp if e > at + 0.05) >= 2:
                return False, (alive, cd, steps, times)
            exp.append(at + 18)
    return True, None


check("two hawks still out (3 s and 9 s left): mark, Arcane Shot, then hawks as they run out",
      plan([3, 9], 0)[0] == ["Hunter's Mark", "Arcane Shot", "Summon Hawk", "Summon Hawk", "Arcane Shot", "Summon Hawk", "Summon Hawk"],
      plan([3, 9], 0))
check("one hawk out, shared cooldown 2 s: mark first, then the hawk", plan([10], 2)[0][:2] == ["Hunter's Mark", "Summon Hawk"], plan([10], 2))
bad = [r for r in (never_three([a, b2], c) for a in range(0, 19, 3) for b2 in range(0, 19, 3) for c in (0, 2, 5)) if not r[0]]
bad += [r for r in (never_three([a], c) for a in range(0, 19) for c in (0, 3, 6)) if not r[0]]
check("never a third hawk, whatever is still out at the pull", not bad, bad[:1])

nohawk = lines_of(H.BuildLines(known("Hunter's Mark", "Aimed Shot", "Arcane Shot", "Raptor Strike", "Auto Shot")))
check("no hawk talent: Aimed Shot once at the pull, then Arcane Shot",
      "/castsequence reset=combat Aimed Shot,nil" in nohawk and "/cast Arcane Shot" in nohawk
      and not any("Summon Hawk" in l for l in nohawk), nohawk)
low = lines_of(H.BuildLines(known("Raptor Strike", "Auto Shot")))
check("level 1: no lines for unlearned spells", low == ["#showtooltip", "/targetenemy [noharm][dead]", "/petattack",
      "/cast Raptor Strike", "/cast !Auto Shot"], low)
noarc = lines_of(H.BuildLines(known("Summon Hawk", "Raptor Strike", "Auto Shot")))
check("hawk without Arcane Shot: two hawks a fight, never a third", "/castsequence reset=combat Summon Hawk,Summon Hawk,nil" in noarc, noarc)

lua.execute("""
MADE = {}; MACROS = {}
GetMacroIndexByName = function(n) return MACROS[n] or 0 end
CreateMacro = function(n, icon, b) MADE[#MADE + 1] = "create"; MACROS[n] = 130; BODY = b; return 130 end
EditMacro = function(i, n, icon, b) MADE[#MADE + 1] = "edit"; BODY = b; return i end
INCOMBAT = false; InCombatLockdown = function() return INCOMBAT end
""")
g.DufforthTweaksHelperWarrior.KnownSpells = lua.eval("function() return KNOWN end")
g.KNOWN = known(*FULL)
H.hawkTimes = lua.table_from([])  # no hawks out from the log tests above
g.DufforthTweaksHelperWarrior.lastCastAt = lua.table_from({})  # and no shared cooldown running
check("Update writes DTH Hunter", H.Update() and g.MADE[1] == "create" and "Summon Hawk,Hunter's Mark,Summon Hawk" in g.BODY, list(g.MADE.values()))
H.Update()
check("unchanged text isn't saved again (keeps the sequences' place)", len(g.MADE) == 1, len(g.MADE))
lua.execute("INCOMBAT = true")
g.KNOWN = known(*[n for n in FULL if n != "Mongoose Bite"])
check("in combat it waits", not H.Update() and H.state.pending)
lua.execute("INCOMBAT = false")
event("PLAYER_REGEN_ENABLED")
check("after the fight it rewrites (Mongoose Bite gone)", g.MADE[2] == "edit" and "Mongoose" not in g.BODY, list(g.MADE.values()))
g.DufforthTweaksHelperDB.hunter.enabled = False
g.KNOWN = known(*FULL)
check("turned off: the macro is left alone", not H.Update() and len(g.MADE) == 2)
g.DufforthTweaksHelperDB.hunter.enabled = True
lua.execute('CLASS = "WARRIOR"')
check("other classes: no hunter macro", not H.Update())
lua.execute('CLASS = "HUNTER"')

# ---- The spell the next press casts, drawn on the button (user: "I want to see the spell I'm pressing") ----
g.KNOWN = known(*FULL)
H.state.body = None
H.Update()
lua.execute("SHIFT = false; IsShiftKeyDown = function() return SHIFT end; IsModifierKeyDown = function() return SHIFT end")
READY = {"value": lambda n: True}
g.PY_READY = lambda n: READY["value"](n)


def pick():
    return lua.eval("(function() local s, r, n = DufforthTweaksHelperHunter.Pick(DufforthTweaksHelperHunter.Facts(), PY_READY, NOW); return s end)()")


lua.execute("NOW = 1000")
H.state.body = None
H.Update()
check("a new pull with no hawks out: Summon Hawk first", pick() == "Summon Hawk", pick())
check("no modifier keys in the button (user: one button, no Shift)", "mod:" not in g.BODY)
event("PLAYER_REGEN_DISABLED")
at(901); cast(2)                                   # hawk at 1001
check("after the hawk: Hunter's Mark (fills the shared cooldown)", pick() == "Hunter's Mark", pick())
at(902); cast(1)                                   # mark
check("after the mark: the second hawk", pick() == "Summon Hawk", pick())
at(907); cast(2)                                   # hawk 2 at 1007
READY["value"] = lambda n: n != "Arcane Shot"      # in melee
check("in melee, Arcane Shot can't go: Raptor Strike", pick() == "Raptor Strike", pick())
READY["value"] = lambda n: n not in ("Arcane Shot", "Raptor Strike")
check("nothing else ready: Auto Shot (no '!' in the name)", pick() == "Auto Shot", pick())
READY["value"] = lambda n: True
at(910); event("PLAYER_REGEN_ENABLED")             # chained pull 3 s later, both hawks still out
check("between pulls the macro is rewritten for the hawks still out", "reset=combat Hunter's Mark,Arcane Shot,Summon Hawk" in g.BODY, g.BODY)
check("so the next pull starts with the mark, not a third hawk", pick() == "Hunter's Mark", pick())
lua.execute("for _, t in ipairs(TIMERS) do PENDING = t end")
at(930)
for _ in range(5):
    lua.execute("local list = TIMERS; TIMERS = {}; for _, t in ipairs(list) do t[2]() end")
check("when the hawks run out (out of combat), the hawk goes first again", "reset=combat Summon Hawk,Hunter's Mark" in g.BODY, g.BODY)

lua.execute("""
GetActionInfo = function(slot) if slot == 5 then return "macro", 130 end end
GetActionText = function(slot) return slot == 5 and "DTH Hunter" or nil end
GetSpellTexture = function(n) return "Interface\\\\Icons\\\\" .. tostring(n) end
ActionButton5 = CreateFrame("Button", "ActionButton5"); ActionButton5.action = 5
ActionButton6 = CreateFrame("Button", "ActionButton6"); ActionButton6.action = 6
""")
H.RefreshButtons()
ov = [(b, o) for b, o in H.overlays.items()]
check("the button holding DTH Hunter gets the picture", len(ov) == 1 and ov[0][0].name == "ActionButton5" and ov[0][1].active,
      [b.name for b, _ in ov])
H.UpdateButtons()
check("the picture is the next spell (Summon Hawk)", H.currentPick == "Summon Hawk", H.currentPick)
g.DufforthTweaksHelperDB.hunter.buttonIcon = False
H.UpdateButtons()
check("option off: no picture", not ov[0][1].shown, ov[0][1].shown)

print(f"{len(fails)} failed" if fails else "all passed")
sys.exit(1 if fails else 0)
