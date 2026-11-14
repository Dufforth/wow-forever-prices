-- Dufforth Tweaks Helper: auto accept and turn in quests (user, 2026-11-13).
--
-- Answers the quest windows for you, only for quests in the guide's route you follow (user, 2026-11-14: not
-- every quest): accepts the route's pick-ups (a gray quest, or one you skipped, is left to you), hands in the
-- route's finished quests, takes the reward when there is nothing to choose (a choice of rewards is only
-- suggested, never taken), and at an NPC with several quests picks the route's finished one first, then the
-- route's new one. Any other quest is left to you. Hold Shift to do it yourself. On by default; the "Auto" button on the guide or
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

-- At a vendor: sell gray items and repair (user, 2026-11-14). On unless turned off in the guide's Menu.
function Q.VendorEnabled() return DB().autoVendor ~= false end
function Q.SetVendorEnabled(on) DB().autoVendor = on and true or false end

function Q.Vendor()
    local sold = 0
    if C_Container and C_Container.GetContainerNumSlots and C_Container.UseContainerItem then
        for bag = 0, 4 do
            for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.quality == 0 and not info.hasNoValue and not info.isLocked then
                    C_Container.UseContainerItem(bag, slot)
                    sold = sold + 1
                end
            end
        end
    end
    local repaired = false
    if CanMerchantRepair and CanMerchantRepair() and GetRepairAllCost and RepairAllItems then
        local cost, needed = GetRepairAllCost()
        if needed and (cost or 0) > 0 and (not GetMoney or GetMoney() >= cost) then RepairAllItems(); repaired = true end
    end
    return sold, repaired
end

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

-- Is this quest a pick-up (kind "accept") or hand-in ("turnin") of the guide's route you follow?
function Q.InGuide(id, kind)
    local data, ui = DufforthTweaksHelperGuideData, DufforthTweaksHelperGuideUI
    if not (id and data and data.routes) then return false end
    local name = ui and ui.RouteName and ui.RouteName()
    local route = name and data.routes[name]
    for _, step in ipairs(route and route.steps or {}) do
        if step[2] == id and step[1] == kind then return true end
    end
    return false
end

local function Gossip()
    local G = C_GossipInfo
    if not G then return end
    for _, q in ipairs(G.GetActiveQuests and G.GetActiveQuests() or {}) do
        if q.isComplete and Q.InGuide(q.questID, "turnin") then G.SelectActiveQuest(q.questID); return end
    end
    for _, q in ipairs(G.GetAvailableQuests and G.GetAvailableQuests() or {}) do
        if Q.InGuide(q.questID, "accept") and Q.Wanted(q.questID) then G.SelectAvailableQuest(q.questID); return end
    end
end

local function Greeting()
    for i = 1, GetNumActiveQuests and GetNumActiveQuests() or 0 do
        local _, complete = GetActiveTitle(i)
        if complete then SelectActiveQuest(i); return end
    end
    if (GetNumAvailableQuests and GetNumAvailableQuests() or 0) > 0 then SelectAvailableQuest(1) end -- the quest window checks it
end

-- A choice of rewards: the best upgrade for you, else the one that sells for the most (user, 2026-11-14).
-- Shown on screen by the quest window, never taken for you. Returns the index, why and its name.
function Q.RecommendReward()
    local gear = DufforthTweaksHelperGear
    if not (gear and gear.RewardChoices and gear.PickReward) then return nil end
    local ok, choices = pcall(gear.RewardChoices)
    if not ok or type(choices) ~= "table" or #choices == 0 then return nil end
    local pick, why = gear.PickReward(choices)
    if not pick then return nil end
    local c = choices[pick]
    Q.ShowRecommendation(why == "upgrade" and string.format("Best reward: %s (upgrade, +%.0f points)", c.name, c.gain)
        or string.format("Best reward: %s (no upgrade: sells for the most)", c.name))
    return pick, why, c.name
end

local note
function Q.ShowRecommendation(text)
    if not note then
        note = CreateFrame("Frame", nil, UIParent)
        note:SetSize(320, 24); note:SetFrameStrata("DIALOG")
        note.bg = note:CreateTexture(nil, "BACKGROUND"); note.bg:SetAllPoints(); note.bg:SetColorTexture(0, 0, 0, 0.8)
        note.text = note:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); note.text:SetPoint("CENTER")
    end
    note:ClearAllPoints()
    if QuestFrame and QuestFrame.IsShown and QuestFrame:IsShown() then note:SetPoint("BOTTOM", QuestFrame, "TOP", 0, 4)
    else note:SetPoint("TOP", UIParent, "TOP", 0, -120) end
    note.text:SetText(text)
    note:Show()
    if C_Timer then C_Timer.After(12, function() note:Hide() end) end
end

function Q.OnEvent(event)
    if IsShiftKeyDown and IsShiftKeyDown() then return end
    if event == "MERCHANT_SHOW" then
        if Q.VendorEnabled() then Q.Vendor() end
        return
    end
    if not Q.Enabled() then return end
    if event == "QUEST_DETAIL" then
        local id = GetQuestID and GetQuestID()
        if id and Q.InGuide(id, "accept") and Q.Wanted(id) then AcceptQuest() end
    elseif event == "QUEST_PROGRESS" then
        local id = GetQuestID and GetQuestID()
        if IsQuestCompletable and IsQuestCompletable() and Q.InGuide(id, "turnin") then CompleteQuest() end
    elseif event == "QUEST_COMPLETE" then
        local choices = GetNumQuestChoices and GetNumQuestChoices() or 0
        if choices <= 1 then
            if Q.InGuide(GetQuestID and GetQuestID(), "turnin") then GetQuestReward(choices) end
            return
        end
        -- A choice of rewards is always yours: the addon only suggests one (user, 2026-11-14).
        Q.RecommendReward()
    elseif event == "GOSSIP_SHOW" then
        Gossip()
    elseif event == "QUEST_GREETING" then
        Greeting()
    end
end

-- ---- Recording Forever's own quests (user, 2026-11-14) ----
-- Forever's public data lists only their numbers. For every quest the guide doesn't know, this writes down who
-- gave it and where, its objectives and the spots where they moved on, and who took it back, where, and the
-- experience. tools/import_recorded_quests.py reads the saved file so those quests can join the route.
local SPOTS, SPOT_APART = 12, 1.5 -- per objective: at most this many spots, this many map % apart

local function Recorded()
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    DufforthTweaksHelperDB.recorded = DufforthTweaksHelperDB.recorded or {}
    return DufforthTweaksHelperDB.recorded
end

function Q.Here()
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
    local info = map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    if not (pos and info and info.name) then return nil end
    local x, y
    if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
    if not x then return nil end
    return { zone = info.name, x = math.floor(x * 1000 + 0.5) / 10, y = math.floor(y * 1000 + 0.5) / 10 }
end

local function Npc()
    return (UnitName and (UnitName("npc") or UnitName("target"))) or nil
end

-- A quest the guide's data doesn't have (Forever's own).
function Q.Unknown(id)
    local data = DufforthTweaksHelperGuideData
    return id ~= nil and not (data and data.quests and data.quests[id])
end

local function Objectives(id)
    if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return {} end
    local ok, list = pcall(C_QuestLog.GetQuestObjectives, id)
    return ok and type(list) == "table" and list or {}
end

function Q.RecordAccept(id)
    if not Q.Unknown(id) then return end
    local r = Recorded()[id] or { id = id, objectives = {} }
    Recorded()[id] = r
    r.title = (C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)) or r.title
    r.level = UnitLevel and UnitLevel("player") or r.level
    r.giver = { name = Npc() }
    local here = Q.Here()
    if here then r.giver.zone, r.giver.x, r.giver.y = here.zone, here.x, here.y end
    for k, o in ipairs(Objectives(id)) do
        r.objectives[k] = r.objectives[k] or { spots = {} }
        local ob = r.objectives[k]
        ob.text, ob.kind, ob.count, ob.have = o.text, o.type, o.numRequired, o.numFulfilled or 0
    end
end

-- An objective moved on: remember where you stood.
function Q.RecordProgress()
    local here
    for id, r in pairs(Recorded()) do
        if not r.turnIn then
            for k, o in ipairs(Objectives(id)) do
                local ob = r.objectives[k]
                if ob and (o.numFulfilled or 0) > (ob.have or 0) then
                    ob.have = o.numFulfilled
                    here = here or Q.Here()
                    local last = ob.spots[#ob.spots]
                    if here and #ob.spots < SPOTS and (not last or last[1] ~= here.zone
                        or math.abs(last[2] - here.x) + math.abs(last[3] - here.y) >= SPOT_APART) then
                        ob.spots[#ob.spots + 1] = { here.zone, here.x, here.y }
                    end
                end
            end
        end
    end
end

function Q.RecordTurnIn(id, xp)
    local r = Recorded()[id]
    if not r then return end
    r.turnIn = { name = Npc() }
    local here = Q.Here()
    if here then r.turnIn.zone, r.turnIn.x, r.turnIn.y = here.zone, here.x, here.y end
    r.xp = tonumber(xp) or r.xp
end

local recorder = CreateFrame("Frame")
for _, event in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE" }) do pcall(recorder.RegisterEvent, recorder, event) end
recorder:SetScript("OnEvent", function(_, event, a, b, c)
    if event == "QUEST_ACCEPTED" then pcall(Q.RecordAccept, b or a) -- (index, id) on older clients, (id) on newer
    elseif event == "QUEST_TURNED_IN" then pcall(Q.RecordTurnIn, a, b)
    else pcall(Q.RecordProgress) end
end)

local frame = CreateFrame("Frame")
for _, event in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "GOSSIP_SHOW", "QUEST_GREETING", "MERCHANT_SHOW" }) do
    pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event) pcall(Q.OnEvent, event) end)
