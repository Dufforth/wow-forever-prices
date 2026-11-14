"""Auto accept and turn-in (QuestAuto.lua) outside the game: which quest windows it answers, with a fake
game. User (2026-11-13): "i want to auto accept and turn in the quest"."""
import sys
from pathlib import Path

import lupa.lua51 as L

ADDON = Path(__file__).resolve().parents[2] / "addon" / "DufforthTweaksHelper"
lua = L.LuaRuntime(unpack_returned_tuples=True)
failed = False


def check(label, cond, detail=""):
    global failed
    print(("PASS " if cond else "FAIL ") + label + (f"   [{detail}]" if detail != "" else ""))
    if not cond:
        failed = True


lua.execute("""
CALLS = {}
local function call(name) return function(...) CALLS[#CALLS + 1] = { name, ... } end end
CreateFrame = function() return setmetatable({ RegisterEvent = function() end, SetScript = function() end }, { __index = function() return function() end end }) end
DufforthTweaksHelperDB = {}
LEVEL, SHIFT, QUEST, COMPLETABLE, CHOICES = 20, false, 100, true, 0
UnitLevel = function() return LEVEL end
UnitRace = function() return "Orc", "Orc" end
IsShiftKeyDown = function() return SHIFT end
GetQuestID = function() return QUEST end
AcceptQuest, CompleteQuest, GetQuestReward = call("AcceptQuest"), call("CompleteQuest"), call("GetQuestReward")
IsQuestCompletable = function() return COMPLETABLE end
GetNumQuestChoices = function() return CHOICES end
ACTIVE, AVAILABLE = {}, {}
C_GossipInfo = {
  GetActiveQuests = function() return ACTIVE end, GetAvailableQuests = function() return AVAILABLE end,
  SelectActiveQuest = call("SelectActiveQuest"), SelectAvailableQuest = call("SelectAvailableQuest"),
}
GREET_ACTIVE, GREET_AVAILABLE = {}, 0
GetNumActiveQuests = function() return #GREET_ACTIVE end
GetActiveTitle = function(i) return "q", GREET_ACTIVE[i] end
GetNumAvailableQuests = function() return GREET_AVAILABLE end
SelectActiveQuest, SelectAvailableQuest = call("GreetActive"), call("GreetAvailable")
DufforthTweaksHelperGuideData = { quests = {
  [100] = { "Fits", 20, 15, 0, "", 0, 0, "Npc", {}, "Npc", {}, {}, {}, 0, 0 },
  [101] = { "Gray", 10, 5, 0, "", 0, 0, "Npc", {}, "Npc", {}, {}, {}, 0, 0 },
}, routes = { Durotar = { steps = { { "accept", 100 }, { "turnin", 100 }, { "accept", 101 }, { "turnin", 101 } } } }, uiMaps = {} }
DufforthTweaksHelperGuideUI = { RouteName = function() return "Durotar" end }
""")
lua.execute((ADDON / "Guide.lua").read_text(encoding="utf-8"))
lua.execute((ADDON / "QuestAuto.lua").read_text(encoding="utf-8"))


def run(event, setup=""):
    lua.execute("CALLS = {}; " + setup)
    lua.execute(f"DufforthTweaksHelperQuestAuto.OnEvent('{event}')")
    calls = lua.eval("CALLS")
    return [tuple(calls[k][j] for j in sorted(calls[k])) for k in sorted(calls)]


check("accept: a quest that fits is accepted", run("QUEST_DETAIL") == [("AcceptQuest",)], run("QUEST_DETAIL"))
check("accept: a gray quest is left for you to decide", run("QUEST_DETAIL", "QUEST = 101") == [])
check("accept: a quest that isn't in the guide is left to you (user: only the guide's quests)", run("QUEST_DETAIL", "QUEST = 97558") == [])
check("turn in: a finished quest that isn't in the guide is left to you", run("QUEST_PROGRESS", "QUEST = 97558") == [])
check("turn in: the guide's finished quest is handed in", run("QUEST_PROGRESS", "QUEST = 100") == [("CompleteQuest",)])
check("accept: holding Shift leaves the window to you", run("QUEST_DETAIL", "QUEST = 100; SHIFT = true") == [])
lua.execute("SHIFT = false")
check("turn in: a finished quest is handed in", run("QUEST_PROGRESS") == [("CompleteQuest",)])
check("turn in: not finished, nothing", run("QUEST_PROGRESS", "COMPLETABLE = false") == [])
check("reward: none to choose, taken", run("QUEST_COMPLETE", "CHOICES = 0") == [("GetQuestReward", 0)], run("QUEST_COMPLETE", "CHOICES = 0"))
check("reward: one to choose, taken", run("QUEST_COMPLETE", "CHOICES = 1") == [("GetQuestReward", 1)])
check("reward: without gear scoring loaded, a choice is left to you", run("QUEST_COMPLETE", "CHOICES = 3") == [])
check("gossip: the guide's finished quest first", run("GOSSIP_SHOW", "ACTIVE = { { questID = 7, isComplete = false }, { questID = 101, isComplete = true } }; "
                                            "AVAILABLE = { { questID = 100 } }") == [("SelectActiveQuest", 101)])
check("gossip: a finished quest outside the guide is left to you", run("GOSSIP_SHOW", "ACTIVE = { { questID = 8, isComplete = true } }; AVAILABLE = {}") == [])
check("gossip: then a new quest", run("GOSSIP_SHOW", "ACTIVE = { { questID = 7, isComplete = false } }; AVAILABLE = { { questID = 101 }, { questID = 100 } }")
      == [("SelectAvailableQuest", 100)], "gray 101 skipped")
check("greeting: a finished quest first", run("QUEST_GREETING", "GREET_ACTIVE = { false, true }; GREET_AVAILABLE = 1") == [("GreetActive", 2)])
check("greeting: then a new quest", run("QUEST_GREETING", "GREET_ACTIVE = { false }; GREET_AVAILABLE = 1") == [("GreetAvailable", 1)])
lua.execute("DufforthTweaksHelperQuestAuto.SetEnabled(false)")
check("off: nothing is answered", run("QUEST_DETAIL", "QUEST = 100") == [] and run("QUEST_PROGRESS") == [])
check("off: remembered", lua.eval("DufforthTweaksHelperDB.guide.auto") is False)
lua.execute("DufforthTweaksHelperQuestAuto.SetEnabled(true)")
check("on again", run("QUEST_DETAIL", "QUEST = 100") == [("AcceptQuest",)])

# A choice of rewards: the best upgrade, else the best price (user, 2026-11-14).
lua.execute("""
REWARDS = { { name = "Cloth", gain = nil, price = 50 }, { name = "Sword", gain = 12, price = 10 }, { name = "Ring", gain = 4, price = 99 } }
DufforthTweaksHelperGear = { RewardChoices = function() return REWARDS end }
DufforthTweaksHelperQuestAuto.ShowRecommendation = function(t) SHOWN = t end
""")
lua.execute("--" + (ADDON / "Gear.lua").read_text(encoding="utf-8").split("-- ---- Quest reward choice")[1].split("-- The quest window's")[0]
            .replace("function Gear.PickReward", "function DufforthTweaksHelperGear.PickReward"))
check("reward: a choice is never taken for you, only suggested (user)", run("QUEST_COMPLETE", "CHOICES = 3") == [], run("QUEST_COMPLETE", "CHOICES = 3"))
check("reward: says which on screen and why", "Sword" in str(lua.eval("SHOWN")) and "upgrade" in str(lua.eval("SHOWN")), lua.eval("SHOWN"))
lua.execute("REWARDS[2].gain = nil; REWARDS[3].gain = nil")
run("QUEST_COMPLETE", "CHOICES = 3")
check("reward: no upgrade, it suggests the one that sells for the most", "Ring" in str(lua.eval("SHOWN")) and "sells" in str(lua.eval("SHOWN")), lua.eval("SHOWN"))
lua.execute("DufforthTweaksHelperQuestAuto.SetEnabled(false)")
check("reward: Auto off, nothing taken", run("QUEST_COMPLETE", "CHOICES = 3") == [])
lua.execute("DufforthTweaksHelperQuestAuto.SetEnabled(true)")

# Recording Forever's own quests (user, 2026-11-14).
lua.execute("""
POS = { x = 0.40, y = 0.60 }
C_Map = { GetBestMapForUnit = function() return 1413 end,
  GetPlayerMapPosition = function() return { x = POS.x, y = POS.y } end,
  GetMapInfo = function() return { name = "The Barrens" } end }
UnitName = function(u) if u == "npc" then return NPC end end
NPC = "Forever Giver"
HAVE = 0
C_QuestLog = { GetTitleForQuestID = function() return "Parts and Pieces" end,
  GetQuestObjectives = function() return { { text = HAVE .. "/8 Gear Parts", type = "item", numRequired = 8, numFulfilled = HAVE } } end }
Q = DufforthTweaksHelperQuestAuto
Q.RecordAccept(97253)
HAVE = 1; POS.x = 0.50; Q.RecordProgress()
HAVE = 2; POS.x = 0.505; Q.RecordProgress()
HAVE = 3; POS.x = 0.60; Q.RecordProgress()
NPC = "Forever Ender"; Q.RecordTurnIn(97253, 1450)
Q.RecordAccept(100)
""")
rec = lua.eval("DufforthTweaksHelperDB.recorded[97253]")
check("record: Forever's quest with giver, zone and spot", rec.title == "Parts and Pieces" and rec.giver.name == "Forever Giver"
      and rec.giver.zone == "The Barrens" and rec.giver.x == 40, (rec.giver.name, rec.giver.x))
check("record: objective with its kind and count", rec.objectives[1].kind == "item" and rec.objectives[1].count == 8)
check("record: spots where it moved on, not two in the same place", len(list(rec.objectives[1].spots.values())) == 2,
      len(list(rec.objectives[1].spots.values())))
check("record: who took it back, where, and the experience", rec.turnIn.name == "Forever Ender" and rec.xp == 1450)
check("record: quests the guide already knows aren't recorded", lua.eval("DufforthTweaksHelperDB.recorded[100]") is None)

# Vendor: sell gray items and repair (user, 2026-11-14).
lua.execute("""
BAGS = { [0] = { { itemID = 1, quality = 0 }, { itemID = 2, quality = 1 }, { itemID = 3, quality = 0, hasNoValue = true } } }
C_Container = {
  GetContainerNumSlots = function(bag) return BAGS[bag] and #BAGS[bag] or 0 end,
  GetContainerItemInfo = function(bag, slot) return BAGS[bag] and BAGS[bag][slot] end,
  UseContainerItem = function(bag, slot) CALLS[#CALLS + 1] = { "Sell", BAGS[bag][slot].itemID } end,
}
CanMerchantRepair = function() return true end
GetRepairAllCost = function() return 500, true end
GetMoney = function() return 10000 end
RepairAllItems = function() CALLS[#CALLS + 1] = { "Repair" } end
""")
check("vendor: sells gray items with a price, then repairs", run("MERCHANT_SHOW") == [("Sell", 1), ("Repair",)], run("MERCHANT_SHOW"))
lua.execute("DufforthTweaksHelperQuestAuto.SetEnabled(false)")
check("vendor: works with auto quests off", run("MERCHANT_SHOW") == [("Sell", 1), ("Repair",)])
lua.execute("DufforthTweaksHelperQuestAuto.SetEnabled(true); DufforthTweaksHelperQuestAuto.SetVendorEnabled(false)")
check("vendor: off when turned off", run("MERCHANT_SHOW") == [])
lua.execute("DufforthTweaksHelperQuestAuto.SetVendorEnabled(true)")
check("vendor: no repair without the money", run("MERCHANT_SHOW", "GetMoney = function() return 100 end") == [("Sell", 1)])

sys.exit(1 if failed else 0)
