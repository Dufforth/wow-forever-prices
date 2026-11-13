"""Gear advice outside the game: who can wear what, points per class, which slot an upgrade replaces,
quest rewards for your level, and a whole run with made-up game data."""
import sys
from pathlib import Path

import lupa.lua51 as L

ADDON = Path(__file__).resolve().parents[2] / "addon" / "DufforthTweaksHelper"
lua = L.LuaRuntime(unpack_returned_tuples=True)
lua.execute("CreateFrame = function() return setmetatable({}, { __index = function() return function() end end }) end")
for name in ("ConsumablesData.lua", "Consumables.lua", "ZoneData.lua", "GearData.lua", "Gear.lua"):
    lua.execute((ADDON / name).read_text(encoding="utf-8"))
lua.execute("G = DufforthTweaksHelperGear")
failed = False


def check(label, cond, detail=""):
    global failed
    print(("PASS " if cond else "FAIL ") + label + (f"   [{detail}]" if detail != "" else ""))
    if not cond:
        failed = True


# Who can wear what (4 armor, 2 weapon).
check("warrior at 26: mail yes, plate not yet", lua.eval("G.CanWear('WARRIOR', 26, 4, 3)") and not lua.eval("G.CanWear('WARRIOR', 26, 4, 4)"))
check("warrior at 40: plate", lua.eval("G.CanWear('WARRIOR', 40, 4, 4)"))
check("mage: cloth only, wands yes, swords one-handed yes, maces no",
      lua.eval("G.CanWear('MAGE', 30, 4, 1)") and not lua.eval("G.CanWear('MAGE', 30, 4, 2)") and lua.eval("G.CanWear('MAGE', 30, 2, 19)")
      and lua.eval("G.CanWear('MAGE', 30, 2, 7)") and not lua.eval("G.CanWear('MAGE', 30, 2, 4)"))
check("rogue: no shields", not lua.eval("G.CanWear('ROGUE', 30, 4, 6)"))

# Points.
lua.execute("""
S = G.Normalize({ ITEM_MOD_STRENGTH_SHORT = 10, ITEM_MOD_STAMINA_SHORT = 5, RESISTANCE0_NAME = 100, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10, SOMETHING_ELSE = 3 })
""")
check("stats: the game's names become the advice's", lua.eval("S.str") == 10 and lua.eval("S.armor") == 100 and lua.eval("S.dps") == 10 and lua.eval("S.SOMETHING_ELSE") is None)
war = lua.eval("G.Score(S, 'WARRIOR')")
check("warrior points: Strength 1, Stamina 0.3, armor 0.02, damage per second x 14 attack power x 0.5", abs(war - (10 + 1.5 + 2 + 70)) < 1e-9, war)
check("a mage gets nothing from Strength or weapon damage", lua.eval("G.Score(G.Normalize({ ITEM_MOD_STRENGTH_SHORT = 10, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10 }), 'MAGE')") == 0)

# Which slot an upgrade replaces.
lua.execute("""
EQ = { [11] = { score = 10, name = "Good Ring" }, [12] = { score = 4, name = "Weak Ring" },
       [16] = { score = 50, name = "One-hander", inv = 13 }, [17] = { score = 20, name = "Shield", inv = 14 },
       [5] = { score = 30, name = "Old Chest" } }
C = {
  { id = 1, inv = 11, score = 8, source = "auction", price = 100 },   -- ring: beats the weak one by 4
  { id = 2, inv = 17, score = 80, source = "auction", price = 100 },  -- two-hander: you use a one-hander
  { id = 3, inv = 13, score = 60, source = "quest", quest = {} },     -- one-hander: +10
  { id = 4, inv = 14, score = 25, source = "auction", price = 100 },  -- shield: +5
  { id = 5, inv = 5, score = 30.5, source = "auction", price = 100 }, -- chest: too small a gain
  { id = 6, inv = 5, score = 40, source = "auction", price = 900 },   -- chest: +10, dear
  { id = 7, inv = 5, score = 40, source = "auction", price = 300 },   -- chest: +10, cheaper: wins
}
U = G.Upgrades(C, EQ)
function FIND(id) for _, u in ipairs(U) do if u.candidate.id == id then return u end end end
""")
check("rings: compared with your weaker ring", lua.eval("FIND(1) and FIND(1).current.name") == "Weak Ring" and abs(lua.eval("FIND(1).gain") - 4) < 1e-9)
check("a two-hander isn't offered when you fight with a one-hander and shield", lua.eval("FIND(2)") is None)
check("a better one-hander replaces yours", lua.eval("FIND(3) and FIND(3).gain") == 10)
check("a better shield replaces yours", lua.eval("FIND(4) and FIND(4).gain") == 5)
check("a tiny gain isn't worth it", lua.eval("FIND(5)") is None)
check("same gain: the cheaper item", lua.eval("FIND(7) ~= nil") and lua.eval("FIND(6)") is None)
check("one best per slot and source", sum(1 for _ in lua.eval("U").values()) == 4)

# Quest rewards for your level, side and class.
lua.execute("""
ZONES = { Here = { q = {
  {1, "Fits", 26, 22, "H", 2000, 0, 0, "Bob", 50, 50, "", 0, 0, {900}},
  {2, "Alliance", 26, 22, "A", 2000, 0, 0, "Al", 50, 50, "", 0, 0, {901}},
  {3, "Too high", 31, 29, "", 2000, 0, 0, "Hi", 50, 50, "", 0, 0, {902}},
  {4, "Mage only", 26, 22, "", 2000, 0, 0, "Ma", 50, 50, "", 128, 0, {903}},
  {5, "Dungeon", 26, 22, "", 2000, 0, 0, "Du", 50, 50, "dungeon", 0, 0, {904}},
  {6, "Done", 26, 22, "", 2000, 0, 0, "Do", 50, 50, "", 0, 0, {905}},
  {7, "No gear", 26, 22, "", 2000, 0, 0, "No", 50, 50, "", 0, 0, {}},
} } }
QR = G.QuestRewards(ZONES, 26, "H", 1, function(id) return id == 6 end)
""")
titles = [lua.eval(f"QR[{i}].title") for i in range(1, int(lua.eval("#QR")) + 1)]
check("quests: only ones you can do now, that reward gear", titles == ["Fits"], titles)

# A whole run: a level 26 Horde warrior, made-up stats for every item the game is asked about.
lua.execute("""
UnitClass = function() return "Warrior", "WARRIOR", 1 end
UnitLevel = function() return 26 end
UnitFactionGroup = function() return "Horde" end
DufforthTweaksHelper = { MarketName = function() return "m" end }
DufforthTweaksHelperPrices = { m = {} }
for _, row in ipairs(DufforthTweaksHelperGearData) do DufforthTweaksHelperPrices.m[row[1]] = 1000 end
STATS = function(link) return { ITEM_MOD_STRENGTH_SHORT = 5, ITEM_MOD_STAMINA_SHORT = 5, RESISTANCE0_NAME = 50 } end
C_Item = { GetItemStats = STATS, RequestLoadItemDataByID = function() end,
  GetItemInfoInstant = function(id) return id, "", "", id % 2 == 1 and "INVTYPE_HEAD" or "INVTYPE_CHEST", 0, 4, 3 end,
  GetItemInfo = function(id) return "Item " .. id, nil, 2, 20, 20 end }
GetInventoryItemLink = function(_, slot) return slot == 5 and "item:1" or nil end
GetInventoryItemID = function(_, slot) return slot == 5 and 1 or nil end
C_QuestLog = { IsQuestFlaggedCompleted = function() return false end }
OK, UP, WAIT = pcall(G.Advice)
""")
check("whole run: no error", lua.eval("OK") is True, lua.eval("tostring(UP)"))
n = int(lua.eval("#UP"))
check("whole run: upgrades for empty slots and the chest", n > 0, n)
check("whole run: no plate offered to a level 26 warrior (mail at most)", all(lua.eval(f"UP[{i}].candidate.inv") != 0 for i in range(1, n + 1)))
check("whole run: quest rewards are among the picks", any(lua.eval(f"UP[{i}].candidate.source") == "quest" for i in range(1, n + 1)))
sys.exit(1 if failed else 0)
