"""The Spanish client (user, 2026-11-14): GetLocale() esES/esMX shows the addon's text in Spanish, and the guide still
works when the game gives Spanish zone names and Spanish objective lines.

    python tests/addon/locale_sim.py
"""
import os
import re
import sys
from pathlib import Path

import lupa.lua51 as L

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "DufforthTweaksHelper"
failures = []


def check(label, cond, detail=""):
    print(("ok   " if cond else "FAIL ") + label + ("" if cond else f"   [{detail}]"))
    if not cond:
        failures.append(label)


def source(name):
    return (ADDON / name).read_text(encoding="utf-8")


# ---- The table itself ----
lua = L.LuaRuntime(unpack_returned_tuples=True)
lua.execute("GetLocale = function() return LOCALE end; LOCALE = 'enUS'")
lua.execute(source("Locale.lua")); lua.execute(source("LocaleES.lua"))
Lc = "DufforthTweaksHelperL"
check("English client: texts stay English", lua.eval(f'{Lc}["Turn in %s to %s"]') == "Turn in %s to %s")
lua.execute("DufforthTweaksHelperLocale.Set('esES')")
check("esES: Spanish text", lua.eval(f'{Lc}["Turn in %s to %s"]') == "Entrega %s a %s", lua.eval(f'{Lc}["Turn in %s to %s"]'))
lua.execute("DufforthTweaksHelperLocale.Set('esMX')")
check("esMX: Spanish too", lua.eval(f'{Lc}["Back to my step"]') == "Volver a mi paso")
check("a text with no translation shows in English", lua.eval(f'{Lc}["Some new text"]') == "Some new text")
lua.execute("DufforthTweaksHelperLocale.Set('frFR')")
check("other languages: English", lua.eval(f'{Lc}["Back to my step"]') == "Back to my step")

# Every Spanish key is a text the addon really asks for, and keeps the same %s/%d and colors.
es = dict(re.findall(r'^ES\["((?:[^"\\]|\\.)*)"\] = "((?:[^"\\]|\\.)*)"$', source("LocaleES.lua"), re.M))
code = "".join(source(f) for f in os.listdir(ADDON) if f.endswith(".lua") and not f.startswith("Locale"))
asked = set(re.findall(r'L\["((?:[^"\\\n]|\\.)*)"\]', code))
DYNAMIC = {"Disenchant", "Leveling", "Zone", "Grind", "Fishing", "Class"}  # tab names: L[name] in Menu.lua
stale = [k for k in es if k not in asked and k not in DYNAMIC]
check("every Spanish text is used by the addon", not stale, stale[:5])
check("most of the addon's texts have Spanish", len(es) >= 650 and len([k for k in asked if k in es]) / max(1, len(asked)) > 0.85, (len(es), len(asked)))


def specs(s):
    return re.findall(r"%[-0-9.]*([sdfx])", s.replace("%%", ""))


bad = [k for k, v in es.items() if specs(k) != specs(v) or k.count("|c") != v.count("|c") or k.count("|r") != v.count("|r")]
check("Spanish keeps every %s/%d and color code", not bad, bad[:3])

# ---- Zones by map ID ----
lua.execute(r"""
DufforthTweaksHelperLocale.Set('esES')
DufforthTweaksHelperGuideData = { uiMaps = { Durotar = 1411, ["The Barrens"] = 1413, Orgrimmar = 1454 } }
MAP, ZONE = 1413, "Los Baldíos"
GetRealZoneText = function() return ZONE end
C_Map = { GetBestMapForUnit = function() return MAP end,
  GetMapInfo = function(m) if m == 9001 then return { parentMapID = 1413, mapType = 5 } end if m == 9002 then return { parentMapID = 1414, mapType = 3 } end
    if m == 1414 then return { parentMapID = 947, mapType = 2 } end return nil end }
""")
Z = "DufforthTweaksHelperLocale.ZoneName()"
check("zone: a Spanish name becomes the route's English one by map ID", lua.eval(Z) == "The Barrens", lua.eval(Z))
lua.execute("MAP = 9001; ZONE = 'Cueva de los ladrones'")
check("zone: a cave inside a zone counts as that zone", lua.eval(Z) == "The Barrens", lua.eval(Z))
lua.execute("MAP = 9002; ZONE = 'Cima del Trueno'")
check("zone: unknown map, the Spanish name table decides", lua.eval(Z) == "Thunder Bluff", lua.eval(Z))
check("taxi node: its zone in English", lua.eval("DufforthTweaksHelperLocale.EnglishNode('El Cruce, Los Baldíos')") == "El Cruce, The Barrens")
lua.execute("DufforthTweaksHelperLocale.Set('enUS'); MAP = 1413; ZONE = 'The Barrens'")
check("English client: the game's zone name as before", lua.eval(Z) == "The Barrens")

# ---- The guide on a Spanish client ----
ui = L.LuaRuntime(unpack_returned_tuples=True)
guide_src = (ROOT / "tests" / "addon" / "guide_sim.py").read_text(encoding="utf-8")
start = guide_src.index('ui.execute(r"""\nALL, PINS = {}, {}') + len('ui.execute(r"""')
mock = guide_src[start:guide_src.index('""")', start)]
ui.execute("GetLocale = function() return 'esES' end")
ui.execute(source("Locale.lua")); ui.execute(source("LocaleES.lua"))
ui.execute(mock)
ui.execute(r"""
ZONE = "Durotar"
GetRealZoneText = function() return ZONE end
TITLES = { [1] = "Jabalíes", [3] = "Raptores" }
OBJ = {}
C_QuestLog.GetTitleForQuestID = function(id) return TITLES[id] end
C_QuestLog.GetQuestObjectives = function(id) return OBJ[id] or {} end
-- Maps far apart in this flat world, so other zones are not "just across the border".
C_Map.GetWorldPosFromMapPos = function(map, v) return 1, CreateVector2D(map * 10000 + (1 - v.y) * 1000, (1 - v.x) * 1000) end
DATA = {
  uiMaps = { Durotar = 1411, ["The Barrens"] = 1413 },
  extras = { class = {}, dungeon = {}, item = {} },
  travel = { continents = { Durotar = 1, ["The Barrens"] = 1 }, flights = {}, transports = {} },
  routes = { Durotar = { races = { "Orc" }, steps = {
    { "accept", 1, "Durotar", 40, 60, 1, "" },
    { "do", 1, "Durotar", 45, 65, 1, "", 1 },
    { "do", 1, "Durotar", 46, 66, 1, "", 2 },
    { "turnin", 1, "Durotar", 40, 60, 2, "" },
    { "travel", 0, "The Barrens", 52, 30, 3, "Go to The Barrens" },
    { "accept", 3, "The Barrens", 52, 30, 3, "" },
    { "do", 3, "The Barrens", 55, 35, 4, "", 1 },
    { "turnin", 3, "The Barrens", 52, 30, 5, "" },
  } } },
  quests = {
    [1] = { "Boars", 1, 1, 0, "", 0, 0, "Gornek", { "Durotar", 40, 60 }, "Gornek", { "Durotar", 40, 60 },
      { { "kill", "Boar", 8, "Durotar", 45, 65, "" }, { "collect", "Boar Tusk", 5, "Durotar", 46, 66, "Boar" } }, {}, 0, 2 },
    [3] = { "Raptors", 4, 2, 0, "", 0, 0, "Thork", { "The Barrens", 52, 30 }, "Thork", { "The Barrens", 52, 30 },
      { { "kill", "Raptor", 4, "The Barrens", 55, 35, "" } }, {}, 0, 0 },
  },
}
DufforthTweaksHelperGuideData = DATA
""")
ui.execute(source("Guide.lua"))
ui.execute(source("GuideUI.lua"))
ui.execute("GU = DufforthTweaksHelperGuideUI; GU.Refresh()")
box = ui.eval("DufforthTweaksHelperGuideBox")
check("box: Spanish text", "Habla con" in str(box.step.text) and "Jabalíes" in str(box.step.text), box.step.text)
check("box: Spanish step header", "Paso 1" in str(box.title.text), box.title.text)
check("box: Spanish buttons", str(box.best.text) == "Mejor", box.best.text)

# Spanish objective lines, item first and monster second (not the data's order): matched by kind and order.
ui.execute("""LOG = { [1] = true }
OBJ[1] = { { text = "Colmillo de jabalí: 2/5", type = "item", numRequired = 5, finished = false },
           { text = "Jabalí asesinado: 3/8", type = "monster", numRequired = 8, finished = false } }
GU.Refresh()""")
check("objectives: the guide is on the kill step", ui.eval("GU.model:Current()") == 2, ui.eval("GU.model:Current()"))
check("objectives: the game's Spanish name and count in the action", "Mata" in str(box.step.text) and "Jabalí asesinado" in str(box.step.text)
      and "3/8" in str(box.step.text), box.step.text)
ui.execute("OBJ[1][2].text = 'Jabalí asesinado: 8/8'; OBJ[1][2].finished = true; GU.Refresh()")
check("objectives: a finished kill moves on to the loot step", ui.eval("GU.model:Current()") == 3 and "Despoja" in str(box.step.text)
      and "Colmillo de jabalí" in str(box.step.text) and "2/5" in str(box.step.text), box.step.text)
ui.execute("OBJ[1][1].finished = true; COMPLETE[1] = true; GU.Refresh()")
check("objectives: all done: hand it in, in Spanish", ui.eval("GU.model:Current()") == 4 and "Entrega" in str(box.step.text), box.step.text)

# Directions from Durotar to the next zone, then the zone given in Spanish.
ui.execute("DONE = { [1] = true }; LOG = {}; COMPLETE = {}; LEVEL = 3; GU.Refresh()")
legs = ui.eval("GU.model:Directions(GU.model:Current())")
check("directions: a way to the next zone, in Spanish", legs is not None and len(legs) > 0 and str(legs[1].text).startswith("Corre a"),
      legs and legs[1].text)
ui.execute("ZONE = 'Los Baldíos'; PLAYER.map = 1413; PLAYER.x = 0.52; PLAYER.y = 0.30; GU.Refresh()")
check("zone: in Los Baldíos the guide knows you're in The Barrens", ui.eval("GU.model:Current()") == 6
      and ui.eval("GU.model:Directions(6)") is None, (ui.eval("GU.model:Current()"), ui.eval("GU.model:Directions(6)")))
check("box: the game's Spanish quest title", "Raptores" in str(box.step.text) and "Thork" in str(box.step.text), box.step.text)
ui.execute("LOG = { [3] = true }; OBJ[3] = { { text = 'Raptor asesinado: 1/4', type = 'monster', numRequired = 4, finished = false } }; GU.Refresh()")
check("objectives: one Spanish line, one goal: its progress", ui.eval("GU.model:Current()") == 7 and "1/4" in str(box.step.text), box.step.text)

# ---- Every file loads on a Spanish client and the tabs open, in Spanish ----
menu_src = (ROOT / "tests" / "addon" / "menu_sim.py").read_text(encoding="utf-8")
mock = menu_src[menu_src.index('MOCK = r"""') + len('MOCK = r"""'):]
mock = mock[:mock.index('"""')]
full = L.LuaRuntime(unpack_returned_tuples=True)
full.execute(mock)
full.execute(r'''
GetLocale = function() return "esES" end
SASTRE = os and os.getenv and os.getenv("SASTRE")
GetRealmName = function() return "Forever PvP" end
UnitName = function() return "Duff" end
UnitFactionGroup = function() return "Horde" end
GetRealZoneText = function() return "Los Baldíos" end
DufforthTweaksHelper = nil
local realCreate = CreateFrame
CreateFrame = function(...) local f = realCreate(...); f.IsVisible = function() return true end; return f end
PROFS = { [1] = { SASTRE or "Sastrería", nil, 87, 150, 0, 0, 197, 0 } }
GetProfessions = function() return 1, nil, nil, nil, nil, nil end
GetProfessionInfo = function(i) return unpack(PROFS[i], 1, 8) end
''')
toc = source("DufforthTweaksHelper.toc").splitlines()
errors = []
for f in [l.strip() for l in toc if l.strip().endswith(".lua")]:
    try:
        full.eval("function(src, name) local fn, err = loadstring(src, name); if not fn then error(err) end; fn('DufforthTweaksHelper', {}) end")(source(f), f)
    except Exception as e:
        errors.append(f"{f}: {str(e)[:200]}")
for tab in ("leveling", "zone", "crafting", "class", "disenchant", "leveling"):
    try:
        full.execute(f'DufforthTweaksHelperMenu_Toggle("{tab}")')
    except Exception as e:
        errors.append(f"open {tab}: {str(e)[:200]}")
check("Spanish client: every file loads and every tab opens", not errors, errors[:3])
full.execute("DufforthTweaksHelperLeveling.Refresh()")
texts = full.eval('(function() local o = {} for _, f in ipairs(ALL) do local t = rawget(f, "text"); if type(t) == "string" then o[#o+1] = t end end return table.concat(o, " || ") end)()')
if os.environ.get("LOCALE_DEBUG"): print(texts)
check("Spanish client: the Leveling tab is in Spanish", "fabricaciones" in texts and "Lista de compra" in texts, texts[:300])
check("Spanish client: the tabs are in Spanish", "Subida" in texts and "Zona" in texts, texts[:300])
check("Spanish client: no error shown in the window", "error" not in texts.lower(), [t for t in texts.split(" || ") if "error" in t.lower()][:2])

print(f"{'all passed' if not failures else str(len(failures)) + ' FAILED'}")
sys.exit(1 if failures else 0)
