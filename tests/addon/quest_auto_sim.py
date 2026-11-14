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
}, routes = {}, uiMaps = {} }
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
check("accept: a quest the guide doesn't know (Forever's own) is accepted", run("QUEST_DETAIL", "QUEST = 97558") == [("AcceptQuest",)])
check("accept: holding Shift leaves the window to you", run("QUEST_DETAIL", "QUEST = 100; SHIFT = true") == [])
lua.execute("SHIFT = false")
check("turn in: a finished quest is handed in", run("QUEST_PROGRESS") == [("CompleteQuest",)])
check("turn in: not finished, nothing", run("QUEST_PROGRESS", "COMPLETABLE = false") == [])
check("reward: none to choose, taken", run("QUEST_COMPLETE", "CHOICES = 0") == [("GetQuestReward", 0)], run("QUEST_COMPLETE", "CHOICES = 0"))
check("reward: one to choose, taken", run("QUEST_COMPLETE", "CHOICES = 1") == [("GetQuestReward", 1)])
check("reward: a choice of rewards is left to you", run("QUEST_COMPLETE", "CHOICES = 3") == [])
check("gossip: a finished quest first", run("GOSSIP_SHOW", "ACTIVE = { { questID = 7, isComplete = false }, { questID = 8, isComplete = true } }; "
                                            "AVAILABLE = { { questID = 100 } }") == [("SelectActiveQuest", 8)])
check("gossip: then a new quest", run("GOSSIP_SHOW", "ACTIVE = { { questID = 7, isComplete = false } }; AVAILABLE = { { questID = 101 }, { questID = 100 } }")
      == [("SelectAvailableQuest", 100)], "gray 101 skipped")
check("greeting: a finished quest first", run("QUEST_GREETING", "GREET_ACTIVE = { false, true }; GREET_AVAILABLE = 1") == [("GreetActive", 2)])
check("greeting: then a new quest", run("QUEST_GREETING", "GREET_ACTIVE = { false }; GREET_AVAILABLE = 1") == [("GreetAvailable", 1)])
lua.execute("DufforthTweaksHelperQuestAuto.SetEnabled(false)")
check("off: nothing is answered", run("QUEST_DETAIL", "QUEST = 100") == [] and run("QUEST_PROGRESS") == [])
check("off: remembered", lua.eval("DufforthTweaksHelperDB.guide.auto") is False)
lua.execute("DufforthTweaksHelperQuestAuto.SetEnabled(true)")
check("on again", run("QUEST_DETAIL", "QUEST = 100") == [("AcceptQuest",)])

sys.exit(1 if failed else 0)
