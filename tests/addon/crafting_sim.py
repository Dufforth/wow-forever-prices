"""Runs the Crafting tab's logic outside the game: material prices (vendor first), profit,
which recipes are shown, and remembering the recipes a character knows.

    python tests/addon/crafting_sim.py
"""
import os
import sys
import lupa.lua51 as L

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ADDON = os.path.join(ROOT, "addon", "DufforthTweaksHelper")


def source(name):
    return open(os.path.join(ADDON, name), encoding="utf-8").read()


MOCK = r"""
time = function() return 1000 end
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
GetItemInfo = function() end
EVENTS = {}
function CreateFrame()
  local f = {}
  function f:RegisterEvent(e) EVENTS[e] = true end
  function f:SetScript(k, fn) self[k] = fn end
  return f
end
GetRealmName = function() return "Realm" end
UnitName = function() return "Duff" end
UnitFactionGroup = function() return "Horde" end
-- The trade skill window, as the game shows it while open.
TRADE = {}
GetTradeSkillLine = function() return "Tailoring" end
GetNumTradeSkills = function() return #TRADE end
GetTradeSkillInfo = function(i) return TRADE[i][1], TRADE[i][2] end
GetTradeSkillRecipeLink = function(i) return TRADE[i][3] end
"""

# Two gear recipes and their materials:
#  Green Robe (Tailoring 50): 2 Bolt (crafted from 2 Cloth each) + 1 Thread (vendor 10c; AH 1c is ignored).
#  Blue Hat (Tailoring 120): 1 Rare Dye (no price).
#  Green Shield (Blacksmithing 30): 1 Bar (AH 500c).
DATA = r"""
DufforthTweaksHelperProfessions = { "Blacksmithing", "Tailoring" }
DufforthTweaksHelperVendor = { [2] = 10 }
DufforthTweaksHelperMaterialCrafts = { [3] = { 1, { 1, 2 } } }
DufforthTweaksHelperCrafts = {
  { 100, 2, 50, 900, 1, 2, 30, 4, 0, "Green Robe", { 3, 2, 2, 1 } },
  { 101, 2, 120, 901, 1, 3, 28, 4, 555, "Blue Hat", { 4, 1 } },
  { 102, 1, 30, 902, 1, 2, 30, 4, -1, "Green Shield", { 5, 1 } },
  { 103, 2, 60, 903, 1, 2, 30, 4, 0, "Costly Gloves", { 5, 9 } },
}
DufforthTweaksHelperPrices = { at = 1000, ["forever.normal.horde.us"] = {
  [1] = 20, [2] = 1, [5] = 500, [11083] = 1000, [11082] = 4000, [11084] = 6000, [900] = 2000 } }
"""

lua = L.LuaRuntime(unpack_returned_tuples=True)
lua.execute(MOCK)
for name in ("Core.lua", "Disenchant.lua"):
    lua.execute(source(name))
lua.execute(DATA)
lua.execute(source("Crafting.lua"))
g = lua.globals()
C = g.DufforthTweaksHelperCrafting
market = "forever.normal.horde.us"
prices = g.DufforthTweaksHelperPrices[market]
fails = []


def check(name, ok):
    print(("ok   " if ok else "FAIL ") + name)
    if not ok:
        fails.append(name)


check("vendor price always wins, even over a cheaper auction", C.MaterialCost(2, prices) == (10, "vendor"))
check("auction price when no vendor sells it", C.MaterialCost(1, prices) == (20, "auction"))
check("crafted materials cost their own materials", C.MaterialCost(3, prices) == (40, "crafted"))
check("no price at all", C.MaterialCost(4, prices) is None)

robe = C.Evaluate(g.DufforthTweaksHelperCrafts[1], market, g.DufforthTweaksHelperPrices)
de_value = (0.75 * 1.5 * 1000 + 0.2 * 1.5 * 4000 + 0.05 * 6000) * 0.95
check("cost adds every material", robe.cost == 2 * 40 + 10)
check("value is the average disenchant value", abs(robe.value - de_value) < 1e-6)
check("profit is value minus cost", abs(robe.profit - (de_value - 90)) < 1e-6 and robe.profession == "Tailoring")
check("its own auction price is kept for the hover", robe.ah == 2000)
check("each material says where its price comes from",
      [robe.parts[i].source for i in (1, 2)] == ["crafted", "vendor"])

known = C.Known()
options = C.Options()


def names(professions):
    rows = C.Recommend(lua.table_from(professions), known, options, market, g.DufforthTweaksHelperPrices)
    return [rows[i].name for i in range(1, len(rows) + 1)]


check("only your professions and skill", names({"Tailoring": 100}) == ["Green Robe"])
options.showHigher = True
check("above my skill adds harder recipes (if they have prices)", names({"Tailoring": 100}) == ["Green Robe"])
options.showHigher = False
check("another profession, another list", names({"Blacksmithing": 40}) == ["Green Shield"])
check("no matching profession, no rows", names({"Mining": 300}) == [])
options.onlyProfit = False
check("untick only profitable to see losses too", names({"Tailoring": 100}) == ["Green Robe", "Costly Gloves"])
options.onlyProfit = True

# Opening the Tailoring window remembers the recipes you know; then unknown ones hide.
g.TRADE = lua.table_from([lua.table_from(["Cloth", "header", None]), lua.table_from(["Costly Gloves", "optimal", "|cffffd000|Henchant:103|h[Costly Gloves]|h|r"])])
check("the profession window is watched", g.EVENTS["TRADE_SKILL_SHOW"] is True)
check("scanning reads the recipes", C.ScanOpenProfession() == 1 and known.spells[103] is True and known.scanned.Tailoring is True)
check("only recipes I know hides the robe now", names({"Tailoring": 100}) == [])
options.onlyKnown = False
check("untick it to see what's worth learning", names({"Tailoring": 100}) == ["Green Robe"])
options.onlyKnown = True
check("other professions aren't hidden before you open them", names({"Blacksmithing": 40}) == ["Green Shield"])
check("professions read from the game", g.DufforthTweaksHelper.Professions() is None)
lua.execute("GetProfessions = function() return 1, 2 end; GetProfessionInfo = function(i) if i == 1 then return 'Tailoring', nil, 150, 300, nil, nil, 197, 5 else return 'Enchanting', nil, 80, 300, nil, nil, 333, 0 end end")
prof = g.DufforthTweaksHelper.Professions()
check("profession skill includes bonuses", prof.Tailoring == 155 and prof.Enchanting == 80)
check("Enchanting skill for the tooltips", g.DufforthTweaksHelperDE.EnchantingSkill() == 80)

if fails:
    sys.exit(f"{len(fails)} failed")
print("all passed")
