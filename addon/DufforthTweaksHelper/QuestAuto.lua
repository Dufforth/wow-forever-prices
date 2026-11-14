-- Dufforth Tweaks Helper: auto accept and turn in quests (user, 2026-11-13).
--
-- Answers the quest windows for you: accepts quests that fit (a gray quest, or one you skipped in the
-- guide, is left to you), hands in finished quests, takes the reward when there is nothing to choose
-- (a choice of rewards stays open for you), and at an NPC with several quests picks a finished one
-- first, then a new one. Hold Shift to do it yourself. On by default; the "Auto" button on the guide or
-- /dth auto turns it off. Never writes to chat.

local Q = {}
DufforthTweaksHelperQuestAuto = Q

local function DB()
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    local g = DufforthTweaksHelperDB.guide or {}
    DufforthTweaksHelperDB.guide = g
    if g.auto == nil then g.auto = true end
    return g
end

function Q.Enabled() return DB().auto end

function Q.SetEnabled(on) DB().auto = on and true or false end

-- A quest worth taking: not gray, not one you skipped in the guide. Unknown quests (Forever's own) are.
function Q.Wanted(id)
    local data, guide = DufforthTweaksHelperGuideData, DufforthTweaksHelperGuide
    local q = data and data.quests and data.quests[id]
    if q and guide and guide.GRAY and UnitLevel and q[2] > 0 and q[2] <= UnitLevel("player") - guide.GRAY then return false end
    for _, saved in pairs(DB().routes or {}) do
        if saved.skippedQuests and saved.skippedQuests[id] then return false end
    end
    return true
end

local function Gossip()
    local G = C_GossipInfo
    if not G then return end
    for _, q in ipairs(G.GetActiveQuests and G.GetActiveQuests() or {}) do
        if q.isComplete then G.SelectActiveQuest(q.questID); return end
    end
    for _, q in ipairs(G.GetAvailableQuests and G.GetAvailableQuests() or {}) do
        if Q.Wanted(q.questID) then G.SelectAvailableQuest(q.questID); return end
    end
end

local function Greeting()
    for i = 1, GetNumActiveQuests and GetNumActiveQuests() or 0 do
        local _, complete = GetActiveTitle(i)
        if complete then SelectActiveQuest(i); return end
    end
    if (GetNumAvailableQuests and GetNumAvailableQuests() or 0) > 0 then SelectAvailableQuest(1) end -- the quest window checks it
end

function Q.OnEvent(event)
    if not Q.Enabled() or (IsShiftKeyDown and IsShiftKeyDown()) then return end
    if event == "QUEST_DETAIL" then
        local id = GetQuestID and GetQuestID()
        if id and Q.Wanted(id) then AcceptQuest() end
    elseif event == "QUEST_PROGRESS" then
        if IsQuestCompletable and IsQuestCompletable() then CompleteQuest() end
    elseif event == "QUEST_COMPLETE" then
        local choices = GetNumQuestChoices and GetNumQuestChoices() or 0
        if choices <= 1 then GetQuestReward(choices) end
    elseif event == "GOSSIP_SHOW" then
        Gossip()
    elseif event == "QUEST_GREETING" then
        Greeting()
    end
end

local frame = CreateFrame("Frame")
for _, event in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "GOSSIP_SHOW", "QUEST_GREETING" }) do
    pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event) pcall(Q.OnEvent, event) end)
