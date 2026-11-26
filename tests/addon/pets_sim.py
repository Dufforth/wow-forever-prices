"""Runs the hunter pet guide outside the game with the real PetData.lua: families in order, stat text, skill ranks for
your level, beasts you can tame now, fast attackers, and the Class tab view (arrows switch family).

    python tests/addon/pets_sim.py
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
lua.execute("LEVEL = 37; UnitLevel = function() return LEVEL end")
# Text widgets for the view: CreateFontString keeps what's set on it.
lua.execute("""
local realCreate = CreateFrame
CreateFrame = function(...)
  local f = realCreate(...)
  f.CreateFontString = function() local t = realCreate("FontString"); t.SetText = function(self, v) self.text = v end; return t end
  f.SetText = function(self, v) self.text = v end
  return f
end
""")
lua.execute(source("PetData.lua"))
lua.execute(source("Pets.lua"))
g = lua.globals()
P = g.DufforthTweaksHelperPets
fails = []


def check(name, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + name + (("  [" + str(detail) + "]") if detail and not ok else ""))
    if not ok:
        fails.append(name)


ids = list(P.FamilyIds().values())
check("17 families, the best for solo leveling first", len(ids) == 17 and P.FAMILIES[ids[0]].solo == 3, [P.FamilyName(i) for i in ids])
check("Cat: +10% damage", "+10% damage" in P.StatText(2), P.StatText(2))
check("Boar: tougher, less damage", "+4% health" in P.StatText(5) and "-10% damage" in P.StatText(5), P.StatText(5))
ranks = {r.skill: (r.now, r.nextLevel) for r in P.NextRanks(2, 37).values()}
check("Cat at 37: Bite rank at 32, next at 40; Prowl at 30, next at 40", ranks["Bite"] == (32, 40) and ranks["Prowl"] == (30, 40), ranks)
low = {r.skill: (r.now, r.nextLevel) for r in P.NextRanks(9, 20).values()}
check("Gorilla at 20: no Thunderstomp yet (comes at 30)", low["Thunderstomp"] == (None, 30), low)
top = {r.skill: (r.now, r.nextLevel) for r in P.NextRanks(21, 60).values()}
check("Turtle at 60: Shell Shield's only rank, no next", top["Shell Shield"] == (20, None), top)
cats = list(P.BeastsFor(2, 37, 6).values())
check("cats to tame at 37: none above your level, closest first", cats and all(b[3] <= 37 for b in cats) and cats[0][4] >= cats[-1][4],
      [(b[1], b[3], b[4]) for b in cats])
check("Broken Tooth (Badlands, 1.0 s) is among the fast attackers at 37",
      any(b[1] == "Broken Tooth" for b in P.FastBeasts(37, 5).values()), [b[1] for b in P.FastBeasts(37, 5).values()])
check("fast attackers sorted fastest first", (lambda f: all(f[i][8] <= f[i + 1][8] for i in range(len(f) - 1)))(list(P.FastBeasts(37, 5).values())))
line = P.BeastLine(next(b for b in g.DufforthTweaksHelperPetData.beasts.values() if b[1] == "Broken Tooth"))
check("a beast line: family, level, rare, speed, zone and spot", "Cat" in line and "rare" in line and "1.0s" in line and "Badlands" in line, line)
text = P.FamilyText(2, 37)
check("family text: stats, role, skills and beasts", "Bite:" in text and "Tame now" in text and "+10% damage" in text, text)
check("summary names the best pets", "Cat" in P.Summary(37) and "Wolf" in P.Summary(37))

parent = lua.eval("CreateFrame('Frame')")
P.BuildPanel(parent, 400)
names = [f.text for f in g.FRAMES.values() if isinstance(getattr(f, "text", None), str)]
check("the view shows the title and a family", any("Pet guide" == t for t in names) and any("(1/17)" in t for t in names), names[:6])
first = g.DufforthTweaksHelperDB.pets.family
P.Step(1)
check("> goes to the next family and remembers it", g.DufforthTweaksHelperDB.pets.family != first)
P.Step(-1)
check("< goes back", g.DufforthTweaksHelperDB.pets.family == first)
lua.execute("LEVEL = 1"); P.Refresh()
check("level 1: still shows a family without errors", g.DufforthTweaksHelperDB.pets.family is not None)

print(f"{len(fails)} failed" if fails else "all passed")
sys.exit(1 if fails else 0)
