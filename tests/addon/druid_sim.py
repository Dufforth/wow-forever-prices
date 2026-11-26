"""Runs the Druid helper outside the game: the macro's lines at each level, form numbers from the
stance bar (by id or by name), the 255-character fit, no shapeshifting in the button, no edits in
combat, and what the next-spell icon shows (including the stuck-finisher prompt).

    python tests/addon/druid_sim.py
"""
import os
import sys

import lupa.lua51 as L

HERE = os.path.dirname(os.path.abspath(__file__))
_src = open(os.path.join(HERE, "warrior_sim.py"), encoding="utf-8").read().split("lua = L.LuaRuntime")[0]
_env = {"__file__": os.path.join(HERE, "warrior_sim.py")}
exec(_src, _env)
MOCK, source, ADDON = _env["MOCK"], _env["source"], _env["ADDON"]

FORM_IDS = {"bear": 5487, "dire": 9634, "aquatic": 1066, "cat": 768, "travel": 783, "moonkin": 24858}
NAMES = {5487: "Bear Form", 9634: "Dire Bear Form", 1066: "Aquatic Form", 768: "Cat Form", 783: "Travel Form",
         24858: "Moonkin Form", 990768: "Cat Form"}

LV1 = ["Wrath", "Healing Touch"]
LV4 = LV1 + ["Moonfire", "Rejuvenation"]
LV10 = LV4 + ["Bear Form", "Maul", "Growl", "Demoralizing Roar"]
LV18 = LV10 + ["Enrage", "Bash", "Swipe", "Faerie Fire", "Regrowth", "Aquatic Form"]
LV20 = LV18 + ["Cat Form", "Claw", "Rip", "Prowl"]
LV24 = LV20 + ["Rake", "Tiger's Fury"]
LV32 = LV24 + ["Travel Form", "Ferocious Bite"]
LV40 = LV32 + ["Dire Bear Form"]
LV40M = LV40 + ["Moonkin Form"]


def runtime():
    lua = L.LuaRuntime(unpack_returned_tuples=True)
    for name in ("Locale.lua", "LocaleES.lua"):
        lua.execute(source(name))
    lua.execute(MOCK)
    lua.execute('CLASS = "DRUID"; UnitClass = function() return "Druid", CLASS end')
    lua.execute(source("Core.lua"))
    lua.execute(source("Warrior.lua"))
    lua.execute(source("Druid.lua"))
    g = lua.globals()
    g.GetSpellInfo = lambda i: NAMES.get(i)
    return lua, g, g.DufforthTweaksHelperDruid


lua, g, D = runtime()
fails = []


def check(name, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + name + (("  [" + str(detail) + "]") if detail and not ok else ""))
    if not ok:
        fails.append(name)


def setup(spells, forms, group=False):
    g.SPELLS = lua.table_from(spells)
    g.FORMS = lua.table_from([FORM_IDS.get(f, f) for f in forms])
    g.IsInGroup = lambda: group
    D.state.body = None
    D.Update()
    return g.MACROS[D.MACRO_NAME]


body = setup(LV1, [])
check("level 1: caster only, Wrath", body == "/startattack\n/cast [noform] Wrath", body)
body = setup(LV4, [])
check("level 4: Moonfire once per pull, then Wrath", "/castsequence [noform] reset=combat Moonfire,nil" in body and body.endswith("[noform] Wrath"), body)
body = setup(LV10, ["bear"])
check("level 10: Maul off the global cooldown in Bear Form", "/cast [form:1] Maul" in body, body)
check("level 10: Demoralizing Roar once, only in combat", "[combat,form:1] reset=combat Demoralizing Roar,nil" in body, body)
body = setup(LV18, ["bear", "aquatic"])
check("level 18 solo: Enrage before Demoralizing Roar, no Swipe solo", "Enrage,Demoralizing Roar,nil" in body and "Swipe" not in body, body)
check("level 18: Faerie Fire then Moonfire once in caster form", "[noform] reset=combat Faerie Fire,Moonfire,nil" in body, body)
body = setup(LV18, ["bear", "aquatic"], group=True)
check("level 18 in a group: Swipe in Bear Form", "/cast [form:1] Swipe;[noform] Wrath" in body, body)
body = setup(LV20, ["bear", "aquatic", "cat"])
check("level 20: Cat Form is form 3 (bar order), Claw x3 then Rip", "/castsequence [form:3] reset=combat Claw,Claw,Claw,Rip" in body, body)
body = setup(LV24, ["bear", "aquatic", "cat"])
check("level 24: Tiger's Fury once, Rake first in the cat sequence (Faerie Fire left out to fit)",
      "[form:3]reset=combat Tiger's Fury,nil" in body and "Rake,Claw,Claw,Claw,Rip" in body
      and list(D.state.dropped.values()) == ["Faerie Fire"] and len(body) <= 255, body)
body = setup(LV32, ["bear", "aquatic", "cat", "travel"])
check("level 32: Ferocious Bite replaces Rip as the finisher", "Rake,Claw,Claw,Claw,Ferocious Bite" in body and "Rip" not in body, body)
check("level 32: fits 255 characters", len(body) <= 255, len(body))
check("level 32: Tiger's Fury is the part left out to fit", "Tiger's Fury" not in body and "Faerie Fire" in body
      and list(D.state.dropped.values()) == ["Tiger's Fury"], body)
for spells, forms, group, label in ((LV40, ["dire", "aquatic", "cat", "travel"], True, "level 40 group"),
                                    (LV40M, ["dire", "aquatic", "cat", "travel", "moonkin"], True, "level 40 moonkin group")):
    body = setup(spells, forms, group)
    check(label + ": fits 255 characters", len(body) <= 255, len(body))
    check(label + ": the cat sequence and Maul are never cut", "Ferocious Bite" in body and "Maul" in body, body)
check("Moonkin Form counts as caster form", "[noform][form:5]" in body, body)
body = setup(LV40, ["dire", "aquatic", "cat", "travel"])
check("Dire Bear Form is read as the bear form", "/cast [form:1]Maul" in body, body)
for spells in (LV40M,):
    body = setup(spells, ["dire", "aquatic", "cat", "travel", "moonkin"])
    check("no form changes in the button (user: never shift)",
          not any(f in body for f in ("Bear Form", "Cat Form", "Travel Form", "Aquatic Form", "Moonkin Form", "Prowl")), body)
    check("Bash and heals are not in the button (own keys)", not any(x in body for x in ("Bash", "Healing Touch", "Regrowth", "Rejuvenation")), body)

# Forever's own spell id for a form: found by name.
body = setup(LV24, ["bear", "aquatic", 990768])
check("a form with an unknown id is found by its name", "[form:3]reset=combat Rake" in body, body)
check("the bar is saved for the log (Forever's form ids)", "3=Cat Form(990768)" in g.DufforthTweaksHelperDB.druid.debug.forms)
# Bar unreadable: forms in learn order.
body = setup(LV24, [])
check("unreadable bar: learn order (Bear 1, Aquatic 2, Cat 3)", "/cast [form:1]Maul" in body and "[form:3]reset=combat Rake" in body, body)

# No edits in combat; unchanged text isn't rewritten.
setup(LV24, ["bear", "aquatic", "cat"])
edits = g.EDITS
g.COMBAT = True
g.SPELLS = lua.table_from(LV32)
D.Update()
check("no macro edit in combat (waits for the fight to end)", g.EDITS == edits and D.state.pending)
g.COMBAT = False
D.Update()
check("rewritten when the fight ends", g.EDITS == edits + 1)
edits = g.EDITS
D.Update()
check("unchanged macro is not rewritten (keeps the sequences' place)", g.EDITS == edits)

# Not a druid: nothing.
g.CLASS = "WARRIOR"
check("other classes get no druid macro", D.Update() is False and D.state.status == "Only for druids.")
g.CLASS = "DRUID"

# ---- The icon follows the button ----
setup(LV32, ["bear", "aquatic", "cat", "travel"])
lines = D.MacroLines()


def facts(form, combat=True, group=False):
    t = lua.table_from({"known": D.state.known, "stance": form, "inCombat": combat, "inGroup": group})
    return t


pick = D.Pick(facts(3), lambda n: True, 0)
check("cat: first pick is Rake", pick[0] == "Rake", pick)
pick = D.Pick(facts(1), lambda n: True, 0)
check("bear in combat, first press: Maul shows (Enrage is background rage)", pick[0] == "Maul", pick)
g.DufforthTweaksHelperWarrior.SequenceCast(lines, facts(1), "Enrage", "C", 0, D.ON_SWING)
pick = D.Pick(facts(1), lambda n: True, 0)
check("bear after Enrage: Demoralizing Roar", pick[0] == "Demoralizing Roar", pick)
pick = D.Pick(facts(1, combat=False), lambda n: True, 0)
check("bear before the pull: Maul (no Roar out of combat)", pick[0] == "Maul", pick)
pick = D.Pick(facts(0), lambda n: True, 0)
check("caster: Faerie Fire first", pick[0] == "Faerie Fire", pick)
# Walk the cat sequence with casts.
for name in ("Rake", "Claw", "Claw", "Claw"):
    g.DufforthTweaksHelperWarrior.SequenceCast(lines, facts(3), name, "C", 1, D.ON_SWING)
pick = D.Pick(facts(3), lambda n: n != "Ferocious Bite", 2)
check("cat after 4 builders: Ferocious Bite next", pick[0] == "Ferocious Bite", pick)
check("stuck finisher with 0 combo points asks for one Claw on its own key", D.StuckFinisher("Ferocious Bite", 0) == "Claw")
check("finisher with combo points is not stuck", D.StuckFinisher("Ferocious Bite", 2) is None)
g.DufforthTweaksHelperWarrior.SequenceCast(lines, facts(3), "Ferocious Bite", "C", 3, D.ON_SWING)
pick = D.Pick(facts(3), lambda n: True, 4)
check("after the finisher the sequence starts over at Rake", pick[0] == "Rake", pick)

# Combo point count from casts when the game hides the number.
D.combo = 0
for name in ("Rake", "Claw", "Claw"):
    D.CountCast(name)
check("own combo count: builders add one each", D.combo == 3)
D.CountCast("Ferocious Bite")
check("own combo count: a finisher spends them", D.combo == 0)

# Own-key prompts.
f = lua.table_from({"known": D.state.known, "form": "bear"})
p = D.OwnKeyPrompt(f, lambda n: True, True, 90)
check("bear + enemy casting: Bash on its own key", p[0] == "Bash", p)
f = lua.table_from({"known": D.state.known, "form": "cat"})
p = D.OwnKeyPrompt(f, lambda n: True, False, 20)
check("low health: a heal prompt (Regrowth first)", p[0] == "Regrowth", p)
p = D.OwnKeyPrompt(f, lambda n: True, False, None)
check("health hidden: no heal prompt", p is None, p)

if fails:
    sys.exit(f"{len(fails)} failed")
print("all passed")
