"""Consumables advice outside the game: what fits each class, level limits, best value vs strongest,
prices from the AH or a vendor, with small made-up data and with the real data file."""
import sys
from pathlib import Path

import lupa.lua51 as L

ADDON = Path(__file__).resolve().parents[2] / "addon" / "DufforthTweaksHelper"


def source(name):
    return (ADDON / name).read_text(encoding="utf-8")


lua = L.LuaRuntime(unpack_returned_tuples=True)
lua.execute("CreateFrame = function() return setmetatable({}, { __index = function() return function() end end }) end")
lua.execute(source("ConsumablesData.lua"))
lua.execute(source("Consumables.lua"))
lua.execute("C = DufforthTweaksHelperConsumables")
C = lua.globals().DufforthTweaksHelperConsumables
failed = False


def check(label, cond, detail=""):
    global failed
    print(("PASS " if cond else "FAIL ") + label + (f"   [{detail}]" if detail != "" else ""))
    if not cond:
        failed = True


lua.execute("""
DATA = {
  {1, "Strong Food", "food", 1, 900, 0, { str = 20, xp = 5 }},
  {2, "Strongest Food", "food", 1, 900, 0, { str = 25, xp = 5 }},
  {3, "Tiny Food", "food", 1, 900, 0, { str = 3, xp = 5 }},
  {4, "Brain Food", "food", 1, 900, 0, { int = 20, xp = 5 }},
  {5, "Rage Potion", "potion", 1, 20, 0, { rage = 45 }},
  {6, "Mana Potion", "potion", 1, 0, 0, { mana = 800 }},
  {7, "Healing Potion", "potion", 1, 0, 50, { hp = 500 }},
  {8, "Spell Potion", "potion", 1, 30, 0, { sp = 30 }},
  {9, "High Food", "food", 50, 900, 0, { str = 40, xp = 5 }},
  {10, "Unpriced Elixir", "elixir", 1, 3600, 0, { str = 10 }},
}
PRICES = { [1] = 10000, [2] = 100000, [3] = 100, [4] = 100, [5] = 5000, [6] = 3000, [7] = 900, [8] = 2000, [9] = 100 }
function NAMES(advice, key)
  local t = {}
  for _, e in ipairs(advice[key].rows) do t[#t+1] = e.row[2] .. (e.badge and (":" .. e.badge) or "") end
  return table.concat(t, ",")
end
W = C.Advice(DATA, "WARRIOR", 30, PRICES)
M = C.Advice(DATA, "MAGE", 30, PRICES)
""")
check("warrior food: the strong one is recommended, the strongest is marked, tiny drops behind",
      lua.eval('NAMES(W, "food")') == "Strong Food:best,Strongest Food:strongest,Tiny Food", lua.eval('NAMES(W, "food")'))
check("warrior: Intellect food doesn't fit", "Brain Food" not in lua.eval('NAMES(W, "food")'))
check("warrior: rage potions, no mana potions", lua.eval('NAMES(W, "rage")') == "Rage Potion:best" and lua.eval('NAMES(W, "mana")') == "")
check("warrior: spell damage potions don't fit", lua.eval('NAMES(W, "battle")') == "")
check("mage: Intellect food, no Strength food", lua.eval('NAMES(M, "food")') == "Brain Food:best", lua.eval('NAMES(M, "food")'))
check("mage: mana and spell potions, no rage", lua.eval('NAMES(M, "mana")') == "Mana Potion:best" and lua.eval('NAMES(M, "battle")') == "Spell Potion:best" and lua.eval('NAMES(M, "rage")') == "")
check("level: food above your level is left out", "High Food" not in lua.eval('NAMES(W, "food")'))
check("no price: counted, not listed", lua.eval("W.elixir.unpriced") == 1 and lua.eval('NAMES(W, "elixir")') == "")
check("vendor cheaper than the AH: the vendor price is used", lua.eval("W.hp.rows[1].price") == 50 and lua.eval("W.hp.rows[1].source") == "vendor")
check("AH only: the AH price", lua.eval("W.food.rows[1].source") == "auction")
check("buff value is points per gold per hour", abs(lua.eval("W.food.rows[1].value") - 20 * 0.25 / 1) < 1e-9)
check("potion value is health per gold", abs(lua.eval("W.hp.rows[1].value") - 500 / 0.005) < 1e-6)
lua.execute("""
DATA2 = {
  {11, "Giant Elixir", "elixir", 1, 3600, 0, { str = 25 }},
  {12, "Small Strength Elixir", "elixir", 1, 3600, 0, { str = 8 }},
  {13, "Agile Elixir", "elixir", 1, 3600, 0, { agi = 25 }},
  {14, "Strength Scroll", "scroll", 1, 1800, 0, { str = 13 }},
  {15, "Big Flask", "flask", 1, 7200, 0, { hpmax = 1200 }},
  {16, "Meat", "food", 1, 900, 0, { str = 20 }},
  {17, "Healing Potion", "potion", 1, 0, 0, { hp = 500 }},
  {18, "Rage Potion", "potion", 1, 20, 0, { rage = 45 }},
}
P2 = { [11] = 5000, [12] = 4000, [13] = 5000, [14] = 1000, [15] = 100000, [16] = 1000, [17] = 1000, [18] = 1000 }
A2 = C.Advice(DATA2, "WARRIOR", 60, P2)
KIT = C.Kit(A2)
function KITNAMES() local t = {} for _, e in ipairs(KIT) do t[#t+1] = e.row[2] end return table.concat(t, ",") end
""")
check("groups: Strength elixirs and scrolls replace each other, Agility is its own", lua.eval('C.Group(DATA2[1])') == lua.eval('C.Group(DATA2[4])') and lua.eval('C.Group(DATA2[1])') != lua.eval('C.Group(DATA2[3])'))
kit = lua.eval("KITNAMES()").split(",")
check("use together: one food, one flask, one item per stat, a healing potion and a rage potion",
      kit.count("Meat") == 1 and "Big Flask" in kit and "Agile Elixir" in kit and "Healing Potion" in kit and "Rage Potion" in kit, kit)
check("use together: never two that replace each other", sum(1 for n in kit if n in ("Giant Elixir", "Small Strength Elixir", "Strength Scroll")) == 1, kit)
check("the weak Strength elixir isn't recommended next to the strong one", "Small Strength Elixir" not in kit)
check("group text: plain words", lua.eval('C.GroupText("elixir:str")') == "one Strength elixir or scroll at a time" and "cooldown" in lua.eval('C.GroupText("potion")'))
lua.execute("""
SHARP, BLUNT = 1 + 2 + 64 + 128 + 256 + 32768, 16 + 32 + 1024 + 8192
DATA3 = {
  {21, "Dense Sharpening Stone", "weapon", 35, 1800, 0, { wdmg = 8 }, SHARP},
  {22, "Dense Weightstone", "weapon", 35, 1800, 0, { wdmg = 8 }, BLUNT},
  {23, "Wizard Oil", "weapon", 40, 1800, 0, { sp = 24 }, 0},
}
P3 = { [21] = 500, [22] = 500, [23] = 3000 }
function WNAMES(class, weapon) local t = {} for _, e in ipairs(C.Advice(DATA3, class, 50, P3, weapon).weapon.rows) do t[#t+1] = e.row[2] end return table.concat(t, ",") end
""")
check("weapon: a warrior with a sword gets the sharpening stone, not the weightstone", lua.eval('WNAMES("WARRIOR", 7)') == "Dense Sharpening Stone", lua.eval('WNAMES("WARRIOR", 7)'))
check("weapon: with a mace, the weightstone", lua.eval('WNAMES("WARRIOR", 4)') == "Dense Weightstone")
check("weapon: fist weapons and staves take weightstones", lua.eval('C.FitsWeapon(DATA3[2], 13)') and lua.eval('C.FitsWeapon(DATA3[2], 10)') and not lua.eval('C.FitsWeapon(DATA3[1], 13)'))
check("weapon: a mage gets the wizard oil, no stones", lua.eval('WNAMES("MAGE", 10)') == "Wizard Oil")
check("weapon: one per weapon, in plain words", "one per weapon" in lua.eval('C.GroupText(C.Group(DATA3[1]))'))
check("weapon: says which weapons it goes on", "daggers" in lua.eval("C.WeaponList(DATA3[1])") and "maces" not in lua.eval("C.WeaponList(DATA3[1])"))
# Well Fed reminder: the best food in your bags for your class, only when it makes sense.
lua.execute("""
BAG = { [1] = 2, [4] = 5, [9] = 1 }
HAVE = function(id) return BAG[id] or 0 end
""")
check("food: the best food in your bags for a warrior (Strength, not Intellect)", lua.eval('C.BestFoodInBags(DATA, "WARRIOR", 30, HAVE)[2]') == "Strong Food")
check("food: a mage picks the Intellect food", lua.eval('C.BestFoodInBags(DATA, "MAGE", 30, HAVE)[2]') == "Brain Food")
check("food: food above your level isn't picked", lua.eval('C.BestFoodInBags(DATA, "WARRIOR", 30, function(id) return id == 9 and 1 or 0 end)') is None)
check("food: nothing in your bags, no reminder", lua.eval('C.BestFoodInBags(DATA, "WARRIOR", 30, function() return 0 end)') is None)
base = "on = true, inCombat = false, dead = false, wellFed = nil, eating = nil, level = 30"
check("reminder: out of combat and not Well Fed", lua.eval("C.ShouldRemind({" + base + "})"))
for k, v in (("inCombat", "true"), ("wellFed", "'Well Fed'"), ("eating", "'Food'"), ("dead", "true"), ("on", "false"), ("level", "60")):
    check(f"reminder: not when {k} = {v}", not lua.eval("C.ShouldRemind({" + base + f", {k} = {v}" + "})"))
lua.execute("BUY = C.FoodToBuy(DATA, 'WARRIOR', 30, PRICES)")
check("buy food: the recommended food for your class", lua.eval("BUY.row[2]") == "Strong Food" and lua.eval("BUY.price") == 10000)
check("buy food: a mage gets the Intellect food", lua.eval("C.FoodToBuy(DATA, 'MAGE', 30, PRICES).row[2]") == "Brain Food")
check("buy food: nothing priced, nothing suggested", lua.eval("C.FoodToBuy(DATA, 'WARRIOR', 30, {})") is None)
check("describe: plain words", lua.eval('C.Describe({ str = 20, xp = 5 })') == "+20 Strength, +5% kill experience", lua.eval('C.Describe({ str = 20, xp = 5 })'))
check("describe: restores", lua.eval('C.Describe({ hp = 500 })') == "500 health")
check("duration", lua.eval("C.Duration(900)") == "15 min" and lua.eval("C.Duration(7200)") == "2 h" and lua.eval("C.Duration(0)") == "instant")

# The real data: every class gets advice that fits it, with prices from a made-up market.
lua.execute("""
REAL = DufforthTweaksHelperConsumableData
FAKE = {}
for _, r in ipairs(REAL) do FAKE[r[1]] = 100 + r[4] * 37 end
function FITS(class, level)
  local a = C.Advice(REAL, class, level, FAKE)
  local ok, count = true, 0
  for key, s in pairs(a) do
    for _, e in ipairs(s.rows) do
      count = count + 1
      if e.row[4] > level then ok = false end
      if C.Section(e.row, class) ~= key then ok = false end
    end
  end
  return ok, count, a
end
""")
for cls in ("WARRIOR", "ROGUE", "HUNTER", "PALADIN", "SHAMAN", "DRUID", "MAGE", "WARLOCK", "PRIEST"):
    ok, count, advice = lua.eval(f'FITS("{cls}", 45)')
    check(f"real data, {cls} 45: everything listed fits the class and level", ok and count > 5, count)
_, _, warrior = lua.eval('FITS("WARRIOR", 45)')
check("real data: a warrior's top food gives Strength or Agility or attack power",
      any(k in ("str", "agi", "ap", "crit") for k in dict(warrior.food.rows[1].row[7]).keys()), dict(warrior.food.rows[1].row[7]))
_, _, mage = lua.eval('FITS("MAGE", 45)')
check("real data: a mage gets no rage potions", len(mage.rage.rows) == 0)
check("real data: the food builder found Forever's Well Fed foods", int(lua.eval("#REAL")) > 150)
sys.exit(1 if failed else 0)
