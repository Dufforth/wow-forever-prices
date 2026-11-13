"""Zone tab outside the game: which quests, hidden quests, rares and monsters it suggests for a
level, side and class, with made-up data and with the real ZoneData.lua."""
import sys
from pathlib import Path

import lupa.lua51 as L

ADDON = Path(__file__).resolve().parents[2] / "addon" / "DufforthTweaksHelper"
lua = L.LuaRuntime(unpack_returned_tuples=True)
lua.execute("CreateFrame = function() return setmetatable({}, { __index = function() return function() end end }) end")
for name in ("ZoneData.lua", "Zone.lua"):
    lua.execute((ADDON / name).read_text(encoding="utf-8"))
failed = False


def check(label, cond, detail=""):
    global failed
    print(("PASS " if cond else "FAIL ") + label + (f"   [{detail}]" if detail != "" else ""))
    if not cond:
        failed = True


lua.execute("""
Z = DufforthTweaksHelperZone
ZONE = {
  q = {
    {1, "Easy XP", 20, 18, "", 2000, 100, 0, "Bob", 50, 50, "", 0, 0},
    {2, "Big XP", 21, 19, "H", 3000, 0, 900, "Ann", 40, 40, "", 0, 0},
    {3, "Alliance Only", 20, 18, "A", 5000, 0, 0, "Al", 30, 30, "", 0, 0},
    {4, "Too Low", 15, 10, "", 9000, 0, 0, "Old", 1, 1, "", 0, 0},
    {5, "Too High", 26, 24, "", 9000, 0, 0, "Far", 1, 1, "", 0, 0},
    {6, "Mage Only", 20, 18, "", 8000, 0, 0, "Mage", 1, 1, "", 128, 0},
    {7, "Dungeon", 21, 18, "", 9000, 0, 0, "Dun", 1, 1, "dungeon", 0, 0},
    {8, "Chain Part 2", 21, 18, "", 9500, 0, 0, "Chain", 1, 1, "", 0, 9},
    {10, "Done Already", 20, 18, "", 9900, 0, 0, "Done", 1, 1, "", 0, 0},
  },
  s = { {500, "Strange Tooth", 11, "A Strange Tooth", 21, 18, "", "Gnasher", 19, 20, 4.5, 60, 60},
        {501, "Old Map", 12, "Treasure", 40, 38, "", "Pirate", 40, 41, 2, 1, 1} },
  r = { {"Big Rare", 20, 20, "rare", 70, 70, { {900, 30} }}, {"Way Up Rare", 30, 30, "rare", 1, 1, {}} },
  m = { {"Wolf", 18, 19, 20, 20, 40, { {901, 0.5}, {902, 0.1} }}, {"Boar", 19, 20, 30, 30, 50, { {902, 0.9} }},
        {"Tiny Crab", 5, 6, 1, 1, 50, { {901, 1} }} },
}
ITEMS = { [900] = {"Blue Sword", 3, 5000}, [901] = {"Fur", 1, 50}, [902] = {"Tusk", 1, 10} }
PRICES = { [901] = 200 }
DONE = { [10] = true, [9] = false }
PLAYER = { level = 20, side = "H", classBit = 1, done = function(id) return DONE[id] end, inLog = function(id) return id == 1 end }
S = Z.Suggest(ZONE, ITEMS, PRICES, PLAYER)
function TITLES(list, i) local t = {} for _, e in ipairs(list) do t[#t+1] = e.data[i] end return table.concat(t, ",") end
""")
q = lua.eval("TITLES(S.quests, 2)").split(",")
check("quests: most XP first, for your level, side and class", q[:2] == ["Big XP", "Easy XP"], q)
check("quests: the other faction's quests are left out", "Alliance Only" not in q)
check("quests: far below or above your level are left out", "Too Low" not in q and "Too High" not in q)
check("quests: other classes' quests are left out", "Mage Only" not in q)
check("quests: dungeon quests are left out", "Dungeon" not in q)
check("quests: ones you've done are left out", "Done Already" not in q)
check("quests: one that needs an earlier quest goes last", q[-1] == "Chain Part 2", q)
check("quests: in your log is marked", lua.eval("S.quests[2].inLog") is True)
check("quests: the reward is valued (vendor price without an AH price)", lua.eval("S.quests[1].reward") == 5000)
check("hidden quests: a drop that starts a quest at your level", lua.eval("TITLES(S.starters, 2)") == "Strange Tooth")
check("rares: near your level, with the most valuable drop", lua.eval("TITLES(S.rares, 1)") == "Big Rare" and lua.eval("S.rares[1].item") == 900)
m = lua.eval("TITLES(S.mobs, 1)").split(",")
check("monsters: most value per kill first", m == ["Wolf", "Boar"], m)
check("monsters: value uses the AH after the cut, else the vendor", abs(lua.eval("S.mobs[1].value") - (0.5 * 200 * 0.95 + 0.1 * 10)) < 1e-9)
check("monsters: far below your level are left out", "Tiny Crab" not in m)
name, sub, where, detail = lua.eval("Z.RowText(S.starters[1])")
check("row text: a hidden quest says who drops it and what it starts", "Gnasher" in sub and "A Strange Tooth" in sub and detail.find("Hidden") >= 0, sub)
# New spells to train.
lua.execute("""
SPELLS = { {20, "Cleave", 1, 4000}, {24, "Execute", 1, 8000}, {24, "Heroic Strike", 4, 8000}, {16, "Heroic Strike", 3, 2000},
           {26, "Charge", 2, 10000}, {28, "Overpower", 2, 11000}, {20, "Dual Wield", 0, 4000}, {20, "Rend", 3, 4000} }
KNOWN = { Cleave = 1, ["Heroic Strike"] = 3, Charge = 1, Rend = 0, ["Dual Wield"] = 0 }
ROWS, TOTAL = Z.ToTrain(SPELLS, 26, KNOWN)
function NAMES(rows) local t = {} for _, s in ipairs(rows) do t[#t+1] = s[2] .. (s[3] > 0 and (" " .. s[3]) or "") end table.sort(t) return table.concat(t, ",") end
""")
check("train: a spell you don't know at all, and higher ranks you've reached", lua.eval("NAMES(ROWS)") == "Charge 2,Execute 1,Heroic Strike 4", lua.eval("NAMES(ROWS)"))
check("train: the total cost", lua.eval("TOTAL") == 8000 + 8000 + 10000)
check("train: nothing above your level", "Overpower" not in lua.eval("NAMES(ROWS)"))
check("train: a spell shown without a rank isn't flagged (can't tell)", "Rend" not in lua.eval("NAMES(ROWS)"))
lua.execute("""TR = { {"Far", "H", "Orgrimmar", 80, 31}, {"Ally", "A", "Ironforge", 1, 1}, {"Near", "H", "Ashenvale", 50, 50}, {"Bluff", "H", "Thunder Bluff", 57, 87} }
NEAR = Z.NearTrainers(TR, "H", "Ashenvale", 2)""")
check("trainers: your side, the one in this zone first", lua.eval("NEAR[1][1]") == "Near" and lua.eval("NEAR[2][1]") == "Far" and lua.eval("#NEAR") == 2)
msg = lua.eval('Z.TrainMessage({ rows = ROWS, total = TOTAL, trainers = NEAR })')
check("train: the message names the spells, cost and trainer", "3 new spells to train" in msg and "Execute 1" in msg and "Ashenvale (Near 50, 50)" in msg, msg)
lua.execute("""
DufforthTweaksHelperDB = {}
UnitClass = function() return "Warrior", "WARRIOR", 1 end
UnitLevel = function() return 26 end
UnitFactionGroup = function() return "Horde" end
GetRealZoneText = function() return "Ashenvale" end
C_SpellBook = { GetNumSpellBookSkillLines = function() return 1 end,
  GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = 2 } end,
  GetSpellBookItemName = function(slot) if slot == 1 then return "Heroic Strike", "Rank 3" else return "Charge", "Rank 1" end end }
time = os.time
OK, ERR = pcall(Z.Announce)
""")
check("notice: the reminder runs on screen without an error", lua.eval("OK") is True, lua.eval("tostring(ERR)"))
dbg = lua.eval("DufforthTweaksHelperDB.trainDebug")
check("notice: what the spellbook gave is saved for diagnosis", dbg is not None and dbg.spellbook == 2 and "Heroic Strike=3" in dbg.sample and "Execute 1" in dbg.found, dbg and dbg.found)
lua.execute("""
N = _G.DufforthTweaksHelperNotice or nil
""")
check("notice: drag saves its spot", lua.eval("(function() local saved = DufforthTweaksHelperDB.noticePoint; return saved == nil end)()") is True)
lua.execute("DufforthTweaksHelperDB.trainDismissed = 26; SHOWN = nil")
check("notice: after the X, nothing until the next level", lua.eval("DufforthTweaksHelperDB.trainDismissed") == 26)
real = lua.eval('#DufforthTweaksHelperClassTrainers.WARRIOR.spells')
check("real data: warrior trainer spells are in ZoneData.lua", real > 50, real)
check("no zone data: nothing, no error", lua.eval("#Z.Suggest(nil, ITEMS, PRICES, PLAYER).quests") == 0)

# The real data: a level 15 Horde warrior in the Barrens, a level 30 Alliance mage in Stranglethorn.
lua.execute("""
function REAL(zone, level, side, bit)
  return Z.Suggest(DufforthTweaksHelperZoneData[zone], DufforthTweaksHelperZoneItems, {}, { level = level, side = side, classBit = bit })
end
B = REAL("The Barrens", 15, "H", 1)
STV = REAL("Stranglethorn Vale", 35, "A", 128)
""")
check("real data: Barrens, level 15 Horde: quests", lua.eval("#B.quests") >= 5, lua.eval("TITLES(B.quests, 2)"))
check("real data: every Barrens quest fits level 13-18 and isn't Alliance", all(
    13 <= lua.eval(f"B.quests[{i}].data[3]") <= 18 and lua.eval(f"B.quests[{i}].data[5]") != "A" for i in range(1, int(lua.eval("#B.quests")) + 1)))
check("real data: Barrens rares and monsters", lua.eval("#B.rares") > 0 and lua.eval("#B.mobs") > 0)
check("real data: Stranglethorn, level 35: quests and monsters", lua.eval("#STV.quests") > 0 and lua.eval("#STV.mobs") > 0)
print("     Barrens 15:", lua.eval("TITLES(B.quests, 2)"))
print("     hidden:", lua.eval("TITLES(REAL('The Barrens', 24, 'H', 1).starters, 2)"))
sys.exit(1 if failed else 0)
