-- Dufforth Tweaks Helper, Zone tab: what's worth doing where you are, for your level.
--
-- From ZoneData.lua (Classic estimates from CMaNGOS): quests started by an item a monster
-- drops (easy to miss), rare monsters and their notable drops, the quests with the most
-- experience for your level that you haven't done, and the monsters whose drops are worth the
-- most per kill at today's prices (bundled AH prices after the 5% cut, else what a vendor pays).

local Zone = {}
DufforthTweaksHelperZone = Zone

local CUT = 0.95
local QUEST_BELOW, QUEST_ABOVE = 2, 3 -- quest levels kept: your level -2 to +3 (gray ones give little XP)
local RARE_BELOW, RARE_ABOVE = 5, 4
local MOB_BELOW, MOB_ABOVE = 5, 2
local LIMIT = { starters = 6, rares = 6, quests = 8, mobs = 5 }
-- Class bits in the quest data, by the game's class ID (1 Warrior ... 11 Druid).
local SKIP_TYPES = { dungeon = true, raid = true, pvp = true, legendary = true }

-- Rows: q = {id, title, level, minLevel, side, xp, money, reward, giver, x, y, type, classes, prev}
-- s = {item, itemName, quest, title, level, minLevel, side, dropper, min, max, chance, x, y}
-- r = {name, min, max, rank, x, y, drops}   m = {name, min, max, x, y, spawns, drops}

-- What an item is worth to you: the AH after the cut, else what a vendor pays.
function Zone.ItemValue(id, items, prices)
    local ah = prices and prices[id]
    if ah and ah > 0 then return ah * CUT, "auction" end
    local info = items and items[id]
    if info and info[3] and info[3] > 0 then return info[3], "vendor" end
    return 0, nil
end

local function SideOK(side, mine) return side == "" or side == nil or side == mine end

-- player = { level, side ("A"/"H"), classBit, done = function(questID) -> true/false/nil, inLog = function(id) }
function Zone.Suggest(zone, items, prices, player)
    local out = { starters = {}, rares = {}, quests = {}, mobs = {} }
    if not zone then return out end
    local L = player.level
    local done = player.done or function() return nil end
    for _, s in ipairs(zone.s or {}) do
        if SideOK(s[7], player.side) and s[6] <= L + 2 and s[5] >= L - 3 and s[9] <= L + 3 and not done(s[3]) then
            table.insert(out.starters, { kind = "starter", data = s, item = s[1] })
        end
    end
    table.sort(out.starters, function(a, b) return a.data[11] > b.data[11] end)
    for _, r in ipairs(zone.r or {}) do
        if r[2] <= L + RARE_ABOVE and r[3] >= L - RARE_BELOW then
            local best, bestValue = nil, 0
            for _, d in ipairs(r[7]) do
                local v = Zone.ItemValue(d[1], items, prices)
                if v * d[2] / 100 >= bestValue then best, bestValue = d, v * d[2] / 100 end
            end
            table.insert(out.rares, { kind = "rare", data = r, item = best and best[1], value = bestValue })
        end
    end
    table.sort(out.rares, function(a, b) return a.value > b.value end)
    for _, q in ipairs(zone.q or {}) do
        local classOK = q[13] == 0 or not player.classBit or math.floor(q[13] / player.classBit) % 2 == 1
        if classOK and SideOK(q[5], player.side) and q[4] <= L and q[3] >= L - QUEST_BELOW and q[3] <= L + QUEST_ABOVE
            and not SKIP_TYPES[q[12]] and not done(q[1]) then
            local reward = q[8] > 0 and Zone.ItemValue(q[8], items, prices) or 0
            local entry = { kind = "quest", data = q, item = q[8] > 0 and q[8] or nil, reward = reward,
                needsEarlier = q[14] > 0 and done(q[14]) == false, inLog = player.inLog and player.inLog(q[1]) }
            table.insert(out.quests, entry)
        end
    end
    -- Most experience first; one you can't pick up yet (an earlier quest first) goes last.
    table.sort(out.quests, function(a, b)
        if a.needsEarlier ~= b.needsEarlier then return not a.needsEarlier end
        if a.data[6] ~= b.data[6] then return a.data[6] > b.data[6] end
        return a.reward > b.reward
    end)
    for _, m in ipairs(zone.m or {}) do
        if m[3] >= L - MOB_BELOW and m[2] <= L + MOB_ABOVE then
            local total, top, topValue = 0, nil, -1
            for _, d in ipairs(m[7]) do
                local v = Zone.ItemValue(d[1], items, prices) * d[2]
                total = total + v
                if v > topValue then top, topValue = d[1], v end
            end
            if total > 0 then table.insert(out.mobs, { kind = "mob", data = m, item = top, value = total }) end
        end
    end
    table.sort(out.mobs, function(a, b) return a.value > b.value end)
    for key, limit in pairs(LIMIT) do
        while #out[key] > limit do table.remove(out[key]) end
    end
    return out
end

-- ---- New spells to train ----
-- Your spellbook (name -> highest rank, 0 when it shows no rank) against what your class trainer
-- teaches at your level. A spell you know without a rank shown isn't flagged (can't tell). The user
-- went two levels without Execute (2026-11-12), so this says it at level-up, on login and here.

-- spells = {{level, name, rank, cost}}; known = { [name] = rank }. -> list of rows, total cost.
function Zone.ToTrain(spells, level, known)
    local out, total = {}, 0
    for _, s in ipairs(spells or {}) do
        local have = known[s[2]]
        local missing
        if s[1] > level then missing = false
        elseif have == nil then missing = true
        elseif s[3] > 0 and have > 0 then missing = have < s[3]
        else missing = false end
        if missing then
            -- Only the highest missing rank of each spell.
            local replaced = false
            for i, o in ipairs(out) do
                if o[2] == s[2] then
                    if s[3] > o[3] then total = total - o[4] + s[4]; out[i] = s end
                    replaced = true
                end
            end
            if not replaced then out[#out + 1] = s; total = total + s[4] end
        end
    end
    return out, total
end

-- Trainers of your side: the one in this zone first, then the capitals. Up to n.
function Zone.NearTrainers(trainers, side, zoneName, n)
    local here, cities = {}, {}
    for _, t in ipairs(trainers or {}) do
        if t[2] == "" or t[2] == side then
            if t[3] == zoneName then here[#here + 1] = t else cities[#cities + 1] = t end
        end
    end
    local out, seen = {}, {}
    for _, list in ipairs({ here, cities }) do
        for _, t in ipairs(list) do
            if #out < n and not seen[t[3]] then out[#out + 1] = t; seen[t[3]] = true end
        end
    end
    return out
end

-- Your spellbook: { [name] = highest rank }, 0 for a spell shown without a rank.
function Zone.KnownRanks()
    local known = {}
    local function add(name, sub)
        if not name then return end
        local rank = tonumber(sub and string.match(sub, "(%d+)") or nil) or 0
        if not known[name] or rank > known[name] then known[name] = rank end
    end
    local ok = pcall(function()
        if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemName then
            local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
            for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
                local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
                for slot = (info and info.itemIndexOffset or 0) + 1, (info and info.itemIndexOffset or 0) + (info and info.numSpellBookItems or 0) do
                    add(C_SpellBook.GetSpellBookItemName(slot, bank))
                end
            end
        elseif GetNumSpellTabs then
            for tab = 1, GetNumSpellTabs() do
                local _, _, offset, count = GetSpellTabInfo(tab)
                for slot = (offset or 0) + 1, (offset or 0) + (count or 0) do add(GetSpellBookItemName(slot, BOOKTYPE_SPELL or "spell")) end
            end
        end
    end)
    return ok and known or {}
end

local function SpellLabel(s) return s[3] > 0 and (s[2] .. " " .. s[3]) or s[2] end

-- { rows, total, trainers } for you now, or nil when nothing is new.
function Zone.TrainNow(known)
    local class = UnitClass and select(2, UnitClass("player"))
    local data = class and DufforthTweaksHelperClassTrainers and DufforthTweaksHelperClassTrainers[class]
    if not data then return nil end
    local level = UnitLevel and UnitLevel("player") or 1
    local rows, total = Zone.ToTrain(data.spells, level, known or Zone.KnownRanks())
    if #rows == 0 then return nil end
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local side = faction == "Alliance" and "A" or faction == "Horde" and "H" or ""
    local zoneName = (GetRealZoneText and GetRealZoneText()) or ""
    return { rows = rows, total = total, trainers = Zone.NearTrainers(data.trainers, side, zoneName, 2) }
end

function Zone.TrainMessage(t)
    local names = {}
    for _, s in ipairs(t.rows) do names[#names + 1] = SpellLabel(s) end
    local where = {}
    for _, tr in ipairs(t.trainers) do where[#where + 1] = string.format("%s (%s %d, %d)", tr[3], tr[1], math.floor(tr[4] + 0.5), math.floor(tr[5] + 0.5)) end
    local money = DufforthTweaksHelperDE and DufforthTweaksHelperDE.Money and DufforthTweaksHelperDE.Money(t.total) or tostring(t.total)
    return string.format("%d new spell%s to train: %s. Cost %s.%s", #t.rows, #t.rows == 1 and "" or "s", table.concat(names, ", "), money,
        #where > 0 and (" Trainer: " .. table.concat(where, " or ") .. ".") or "")
end

-- What the reminder read, saved for diagnosis (DufforthTweaksHelperDB.trainDebug): the user didn't
-- see it in game (2026-11-12), so the next /reload tells what the spellbook gave.
local function SaveDebug(t, known)
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    local names, n = {}, 0
    for name, rank in pairs(known or {}) do
        n = n + 1
        if #names < 60 then names[#names + 1] = name .. "=" .. rank end
    end
    table.sort(names)
    DufforthTweaksHelperDB.trainDebug = { at = time and time() or 0, level = UnitLevel and UnitLevel("player") or 0,
        class = UnitClass and select(2, UnitClass("player")) or "?", spellbook = n, sample = table.concat(names, "; "),
        found = t and Zone.TrainMessage(t) or "nothing to train" }
end

-- On screen, never in chat (user: "never use chat for notifications, I can't see the chat"):
-- a small notice above the warrior icon, or at the top of the screen. Click opens the Zone tab,
-- the X hides it until your next level, and it fades after 30 seconds.
-- Drag to move (user: "I cannot move the spell notification"); the spot is saved in DB[key].
local function Draggable(f, key)
    f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if InCombatLockdown and InCombatLockdown() and self.IsProtected and self:IsProtected() then return end
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relative, x, y = self:GetPoint()
        DufforthTweaksHelperDB[key] = { point, relative, x, y }
    end)
    local p = DufforthTweaksHelperDB and DufforthTweaksHelperDB[key]
    if p then f:ClearAllPoints(); f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) end
end

local notice
local function Notice()
    if notice then return notice end
    local f = CreateFrame("Button", "DufforthTweaksHelperNotice", UIParent, "BackdropTemplate")
    f:SetSize(300, 54)
    local hint = _G.DufforthTweaksHelperWarriorHint
    if hint then f:SetPoint("BOTTOM", hint, "TOP", 0, 34) else f:SetPoint("TOP", UIParent, "TOP", 0, -140) end
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0, 0, 0, 0.85); f:SetBackdropBorderColor(1, 0.82, 0, 1)
    end
    f:SetFrameStrata("HIGH")
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    Draggable(f, "noticePoint")
    f.icon = f:CreateTexture(nil, "ARTWORK"); f.icon:SetSize(34, 34); f.icon:SetPoint("LEFT", 10, 0)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.title:SetPoint("TOPLEFT", 52, -9)
    f.title:SetPoint("RIGHT", -26, 0); f.title:SetJustifyH("LEFT")
    f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); f.body:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
    f.body:SetPoint("RIGHT", -10, 0); f.body:SetJustifyH("LEFT")
    if f.body.SetWordWrap then f.body:SetWordWrap(false) end
    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); f.close:SetSize(22, 22); f.close:SetPoint("TOPRIGHT", -2, -2)
    f.close:SetScript("OnClick", function()
        DufforthTweaksHelperDB.trainDismissed = UnitLevel and UnitLevel("player") or 0
        f:Hide()
    end)
    f:SetScript("OnClick", function()
        f:Hide()
        if DufforthTweaksHelperMenu_Toggle then DufforthTweaksHelperMenu_Toggle("zone") end
    end)
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(self.full or "", 1, 1, 1, 1, true)
        GameTooltip:AddLine("Click to open the Zone tab. Drag to move it. The X hides this until your next level.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:Hide()
    notice = f
    return f
end

if DufforthTweaksHelper and DufforthTweaksHelper.RegisterMovable then
    DufforthTweaksHelper.RegisterMovable({ label = "Spell notice", get = Notice,
        enter = function(f)
            f.title:SetText("New spells to train (example)")
            f.body:SetText("Shows at login and level-up when your trainer has something new.")
            f.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
            f:Show()
        end,
        leave = function(f) f:Hide() end })
end

function Zone.ShowTrainNotice(t)
    local f = Notice()
    local names = {}
    for _, s in ipairs(t.rows) do names[#names + 1] = SpellLabel(s) end
    local money = DufforthTweaksHelperDE and DufforthTweaksHelperDE.Money and DufforthTweaksHelperDE.Money(t.total) or tostring(t.total)
    local tr = t.trainers[1]
    f.title:SetText(string.format("%d new spell%s to train (%s)", #t.rows, #t.rows == 1 and "" or "s", money))
    f.body:SetText(table.concat(names, ", ") .. (tr and ("  |cffaaaaaa" .. tr[3] .. "|r") or ""))
    f.icon:SetTexture((GetSpellTexture and GetSpellTexture(t.rows[1][2])) or "Interface\\Icons\\INV_Misc_Book_09")
    f.full = Zone.TrainMessage(t)
    f:Show()
    if C_Timer then C_Timer.After(30, function() if f:IsShown() and not f:IsMouseOver() then f:Hide() end end) end
end

local function Announce()
    local known = Zone.KnownRanks()
    local ok, t = pcall(Zone.TrainNow, known)
    pcall(SaveDebug, ok and t or nil, known)
    local level = UnitLevel and UnitLevel("player") or 0
    if ok and t and (DufforthTweaksHelperDB.trainDismissed or 0) < level then pcall(Zone.ShowTrainNotice, t) end
end
Zone.Announce = Announce
local trainWatcher = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LEVEL_UP", "PLAYER_LOGIN" }) do pcall(trainWatcher.RegisterEvent, trainWatcher, event) end
trainWatcher:SetScript("OnEvent", function()
    -- After a level-up the spellbook and level update a moment later.
    if C_Timer then C_Timer.After(3, Announce) else Announce() end
end)

-- ---- Guide probe ----
-- What the game says about your quests, saved for the leveling guide (DB.guideProbe): completed quest
-- IDs (the guide uses Classic quest IDs, so they must match Forever's), your quest log, and who and
-- where you are. Read after a /reload; nothing is shown in game.
local function CompletedIDs()
    if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
        local ok, ids = pcall(C_QuestLog.GetAllCompletedQuestIDs)
        if ok and type(ids) == "table" then return ids end
    end
    if GetQuestsCompleted then
        local ok, done = pcall(GetQuestsCompleted)
        if ok and type(done) == "table" then
            local ids = {}
            for id in pairs(done) do ids[#ids + 1] = id end
            return ids
        end
    end
    return {}
end

local function LogEntries()
    local out = {}
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID then
                out[#out + 1] = info.questID .. ":" .. tostring(info.title) .. ":" .. tostring(info.level)
            end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        for i = 1, GetNumQuestLogEntries() or 0 do
            local title, level, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
            if title and not isHeader and id then out[#out + 1] = id .. ":" .. title .. ":" .. tostring(level) end
        end
    end
    return out
end

function Zone.SaveGuideProbe()
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    local ids = CompletedIDs()
    table.sort(ids)
    local probe = { at = time and time() or 0, level = UnitLevel and UnitLevel("player") or 0,
        completed = table.concat(ids, ","), completedCount = #ids, log = table.concat(LogEntries(), ";"),
        zone = (GetRealZoneText and GetRealZoneText()) or "?" }
    if UnitRace then local _, race = UnitRace("player"); probe.race = race end
    if UnitClass then probe.class = select(2, UnitClass("player")) end
    if C_Map and C_Map.GetBestMapForUnit then
        local map = C_Map.GetBestMapForUnit("player")
        probe.mapID = map
        local pos = map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
        if pos then
            local x, y = pos.x, pos.y
            if not x and pos.GetXY then x, y = pos:GetXY() end
            if x then probe.x, probe.y = math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10 end
        end
    end
    DufforthTweaksHelperDB.guideProbe = probe
end

local probeWatcher = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "QUEST_TURNED_IN", "QUEST_ACCEPTED" }) do pcall(probeWatcher.RegisterEvent, probeWatcher, event) end
probeWatcher:SetScript("OnEvent", function()
    -- A moment later: the quest log and completed list update after these events.
    if C_Timer then C_Timer.After(2, function() pcall(Zone.SaveGuideProbe) end) else pcall(Zone.SaveGuideProbe) end
end)

-- ---- Panel ----
local ROW_HEIGHT, TOP = 30, -40
local panel, lines, rows, offset = nil, {}, {}, 0

-- Rows that fit the page now: the window can be made taller or shorter, so more rows are made than
-- fit and the rest stay hidden.
local function Shown()
    local h = panel and panel.GetHeight and panel:GetHeight() or 0
    if not h or h <= 0 then return #lines end
    return math.max(4, math.min(#lines, math.floor((h + TOP - 20) / ROW_HEIGHT)))
end

-- Sections fold with a click on their header; folded ones are remembered (DB.collapsed[key]).
local function Collapsed(key)
    local c = DufforthTweaksHelperDB and DufforthTweaksHelperDB.collapsed
    return c and c[key] or false
end
local function Section(key, title, note, entries)
    local closed = Collapsed(key)
    rows[#rows + 1] = { header = title, key = key, closed = closed, count = #entries, note = note }
    if not closed then for _, e in ipairs(entries) do rows[#rows + 1] = e end end
end
local function Toggle(key)
    if not key then return end
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    DufforthTweaksHelperDB.collapsed = DufforthTweaksHelperDB.collapsed or {}
    DufforthTweaksHelperDB.collapsed[key] = (not DufforthTweaksHelperDB.collapsed[key]) or nil
    Zone.Refresh()
end
local status
local SECTIONS = {
    { key = "starters", title = "Quests started by a drop (easy to miss)" },
    { key = "rares", title = "Rare monsters here" },
    { key = "quests", title = "Quests with the most experience for you" },
    { key = "mobs", title = "Monsters worth the most per kill" },
}
local QUALITY = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee" }
local SOURCE = { vendor = "|cff59b3ffVendor|r", auction = "|cffff9933AH|r" }

local function Money(c) return DufforthTweaksHelperDE and DufforthTweaksHelperDE.Money and DufforthTweaksHelperDE.Money(math.floor(c + 0.5)) or tostring(c) end
local function ItemName(id)
    local info = DufforthTweaksHelperZoneItems and DufforthTweaksHelperZoneItems[id]
    if not info then return "Item " .. id end
    return "|cff" .. (QUALITY[info[2]] or "ffffff") .. info[1] .. "|r"
end
local function Icon(id)
    return id and ((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id))) or nil
end
local function Prices()
    local market = DufforthTweaksHelper and DufforthTweaksHelper.MarketName and DufforthTweaksHelper.MarketName() or ""
    return DufforthTweaksHelperPrices and DufforthTweaksHelperPrices[market] or {}
end
local function AtAuction()
    local L = DufforthTweaksHelperLeveling
    if L and L.Where then return L.Where().auction end
    return AuctionHouseFrame and AuctionHouseFrame.IsShown and AuctionHouseFrame:IsShown()
end

local function Player()
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local classID
    if UnitClass then classID = select(3, UnitClass("player")) end
    local function done(id)
        if not id or id <= 0 then return nil end
        if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then return C_QuestLog.IsQuestFlaggedCompleted(id) and true or false end
        if IsQuestFlaggedCompleted then return IsQuestFlaggedCompleted(id) and true or false end
        return nil
    end
    local function inLog(id)
        if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then return C_QuestLog.GetLogIndexForQuestID(id) ~= nil end
        return false
    end
    return { level = UnitLevel and UnitLevel("player") or 1, side = faction == "Alliance" and "A" or faction == "Horde" and "H" or "",
        classBit = classID and 2 ^ (classID - 1) or nil, done = done, inLog = inLog }
end

local function ZoneName() return (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or "" end

local function Where(x, y) return x and string.format("%d, %d", math.floor(x + 0.5), math.floor(y + 0.5)) or "" end

-- Text of one row: name line, second line, right-hand value, right-hand detail.
function Zone.RowText(e)
    local d = e.data
    if e.kind == "train" then
        local tr = e.trainers and e.trainers[1]
        local cost = DufforthTweaksHelperDE and DufforthTweaksHelperDE.Money and DufforthTweaksHelperDE.Money(d[4]) or tostring(d[4])
        return "|cff40ff40" .. SpellLabel(d) .. "|r", tr and string.format("Level %d. Trainer: %s, %s", d[1], tr[1], tr[3]) or ("Level " .. d[1]),
            tr and Where(tr[4], tr[5]) or "", cost
    elseif e.kind == "starter" then
        local level = d[9] == d[10] and tostring(d[9]) or (d[9] .. "-" .. d[10])
        local chance = d[11] < 100 and (" " .. d[11] .. "%") or ""
        return ItemName(d[1]), string.format("From %s (%s)%s. Starts \"%s\", level %d", d[8], level, chance, d[4], d[5]),
            Where(d[12], d[13]), "|cffffd100Hidden|r"
    elseif e.kind == "rare" then
        local drops = {}
        for _, x in ipairs(d[7]) do drops[#drops + 1] = ItemName(x[1]) .. " " .. x[2] .. "%" end
        return "|cffc0c0c0" .. d[1] .. "|r", string.format("Level %d%s %s. %s", d[2], d[3] ~= d[2] and ("-" .. d[3]) or "", d[4],
            #drops > 0 and table.concat(drops, ", ") or "No notable drops"), Where(d[5], d[6]), e.value > 0 and ("~" .. Money(e.value) .. " a kill") or ""
    elseif e.kind == "quest" then
        local reward = e.item and (" Reward: " .. ItemName(e.item)) or ""
        local tag = e.inLog and "|cff40ff40In your log|r" or e.needsEarlier and "|cff808080Earlier quest first|r" or (d[12] == "group" and "|cffff8040Group|r" or "")
        return "|cffffd100" .. d[2] .. "|r", string.format("Level %d, ~%d XP.%s%s", d[3], d[6], d[9] ~= "" and (" " .. d[9] .. ".") or "", reward),
            Where(d[10], d[11]), tag
    else
        return d[1], string.format("Level %d-%d. Mostly %s", d[2], d[3], ItemName(e.item)), Where(d[4], d[5]), Money(e.value) .. " a kill"
    end
end

-- Right-hand column: next to the Search button when it shows, at the edge otherwise. Name and
-- second line end where that column's text starts, so nothing overlaps.
local function PlaceRight(line, searching)
    local inset = searching and -66 or -4
    line.cost:ClearAllPoints(); line.cost:SetPoint("TOPRIGHT", inset, -3)
    line.detail:ClearAllPoints(); line.detail:SetPoint("BOTTOMRIGHT", inset, 4)
end

local function Draw()
    local auction = AtAuction()
    for i, line in ipairs(lines) do
        local r = i <= Shown() and rows[offset + i] or nil
        line.row = r
        line:SetShown(r ~= nil)
        local searching = r ~= nil and not r.header and r.item ~= nil and auction and true or false
        line.search:SetShown(searching)
        PlaceRight(line, searching)
        if r and r.header then
            DufforthTweaksHelper.StyleRow(line, "header", r.closed)
            line.cost:SetText(""); line.detail:SetText(r.closed and ("|cffaaaaaa" .. r.count .. " hidden|r") or "")
            line.name:SetText("|cffffd100" .. r.header .. "|r"); line.sub:SetText(r.closed and "" or (r.note or ""))
        elseif r then
            DufforthTweaksHelper.StyleRow(line, "child")
            local spellIcon = r.kind == "train" and GetSpellTexture and GetSpellTexture(r.data[2]) or nil
        local icon = spellIcon or Icon(r.item) or (r.kind == "quest" and "Interface\\GossipFrame\\AvailableQuestIcon")
            or (r.kind == "train" and "Interface\\Icons\\INV_Misc_Book_09") or "Interface\\Icons\\INV_Misc_QuestionMark"
            line.icon:Show(); line.icon:SetTexture(icon)
            local name, sub, right, detail = Zone.RowText(r)
            line.name:SetText(name); line.sub:SetText(sub); line.cost:SetText(right); line.detail:SetText(detail)
        end
    end
    panel.pageText:SetText(#rows > Shown() and string.format("%d / %d", math.floor(offset / Shown()) + 1, math.ceil(#rows / Shown())) or "")
    panel.status:SetText(status and (GetTime and GetTime() or 0) - status.at < 8 and status.text or "")
end

local function Scroll(delta)
    offset = math.max(0, math.min(offset + delta, math.max(0, #rows - Shown())))
    Draw()
end

function Zone.Refresh()
    if not panel then return end
    local player, zoneName = Player(), ZoneName()
    local zone = DufforthTweaksHelperZoneData and DufforthTweaksHelperZoneData[zoneName]
    panel.title:SetText(string.format("%s, level %d", zoneName ~= "" and zoneName or "Unknown zone", player.level))
    local s = Zone.Suggest(zone, DufforthTweaksHelperZoneItems, Prices(), player)
    rows = {}
    local okTrain, train = pcall(Zone.TrainNow)
    if okTrain and train then
        local money = DufforthTweaksHelperDE and DufforthTweaksHelperDE.Money and DufforthTweaksHelperDE.Money(train.total) or tostring(train.total)
        local enough = not GetMoney or GetMoney() >= train.total
        local entries = {}
        for _, s in ipairs(train.rows) do entries[#entries + 1] = { kind = "train", data = s, trainers = train.trainers } end
        Section("zone:train", "New spells to train", "Cost " .. money .. (enough and "" or " (more than you have)"), entries)
    end
    for _, sec in ipairs(SECTIONS) do
        if #s[sec.key] > 0 then Section("zone:" .. sec.key, sec.title, nil, s[sec.key]) end
    end
    panel.empty:SetText(#rows > 0 and "" or (zone and "Nothing here fits your level. Zones a few levels above you may have more."
        or "No guide for this zone (cities, dungeons and battlegrounds aren't covered)."))
    offset = math.min(offset, math.max(0, #rows - Shown()))
    Draw()
end

-- A click puts a pin on your map at the row's spot.
local function Pin(line)
    local r = line.row
    if not r or r.header then return end
    local d, x, y = r.data, nil, nil
    if r.kind == "train" then
        local tr = r.trainers and r.trainers[1]
        if not tr or tr[3] ~= ZoneName() then
            status = { at = GetTime and GetTime() or 0, text = tr and ("The trainer is in " .. tr[3] .. ".") or "No trainer found." }
            Draw()
            return
        end
        x, y = tr[4], tr[5]
    elseif r.kind == "starter" then x, y = d[12], d[13] elseif r.kind == "rare" then x, y = d[5], d[6]
    elseif r.kind == "quest" then x, y = d[10], d[11] else x, y = d[4], d[5] end
    if not x then return end
    local ok = pcall(function()
        local map = C_Map.GetBestMapForUnit("player")
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x / 100, y / 100))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    end)
    status = { at = GetTime and GetTime() or 0, text = ok and string.format("Map pin set at %d, %d.", math.floor(x + 0.5), math.floor(y + 0.5))
        or string.format("Couldn't set a map pin. The spot is at %d, %d.", math.floor(x + 0.5), math.floor(y + 0.5)) }
    Draw()
end

local function Search(line)
    local r = line.row
    local L = DufforthTweaksHelperLeveling
    if r and r.item and L and L.SearchAuctionHouse then L.SearchAuctionHouse(r.item) end
end

local function ShowRow(line)
    local r = line.row
    if not r or r.header then return end
    GameTooltip:SetOwner(line, "ANCHOR_RIGHT")
    local name, sub = Zone.RowText(r)
    GameTooltip:AddLine(name, 1, 1, 1)
    GameTooltip:AddLine(sub, 0.8, 0.8, 0.8, true)
    local d = r.data
    if r.kind == "train" then
        GameTooltip:AddLine("Your class trainer teaches this at your level. New ranks hit harder; the warrior button uses them by itself.", 0.45, 0.8, 1, true)
        for _, tr in ipairs(r.trainers or {}) do
            GameTooltip:AddDoubleLine("    " .. tr[1], string.format("%s %d, %d", tr[3], math.floor(tr[4] + 0.5), math.floor(tr[5] + 0.5)), 0.8, 0.8, 0.8, 1, 1, 1)
        end
    elseif r.kind == "starter" then
        GameTooltip:AddLine("Loot it and right-click it in your bags to start the quest. Many players never see these.", 0.45, 0.8, 1, true)
    elseif r.kind == "rare" then
        GameTooltip:AddLine("Rares spawn rarely and someone may have killed it. Worth a look when you pass by.", 0.45, 0.8, 1, true)
    elseif r.kind == "quest" then
        GameTooltip:AddDoubleLine("Experience", "about " .. d[6], 0.8, 0.8, 0.8, 1, 1, 1)
        if d[7] > 0 then GameTooltip:AddDoubleLine("Money", Money(d[7]), 0.8, 0.8, 0.8, 1, 1, 1) end
        if r.item then GameTooltip:AddDoubleLine("Reward worth", Money(r.reward), 0.8, 0.8, 0.8, 1, 1, 1) end
        if d[12] == "group" then GameTooltip:AddLine("A group quest: bring friends.", 1, 0.5, 0.25, true) end
    else
        for _, x in ipairs(d[7]) do
            local v, source = Zone.ItemValue(x[1], DufforthTweaksHelperZoneItems, Prices())
            GameTooltip:AddDoubleLine(string.format("    %s (%.1f per 100 kills)", ItemName(x[1]), x[2] * 100), Money(v) .. " " .. (SOURCE[source] or ""), 0.8, 0.8, 0.8, 1, 1, 1)
        end
        GameTooltip:AddDoubleLine("Average per kill", Money(r.value), 1, 0.82, 0, 1, 1, 1)
    end
    GameTooltip:AddLine("Click to put a pin on your map. Classic estimates; Forever may differ.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

function Zone.BuildPanel(parent, width)
    panel = parent
    panel.title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", 8, -4)
    panel.status = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.status:SetPoint("TOPRIGHT", -8, -6); panel.status:SetJustifyH("RIGHT")
    panel.legend = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.legend:SetPoint("TOPLEFT", 8, -22); panel.legend:SetWidth(width - 16); panel.legend:SetJustifyH("LEFT")
    panel.legend:SetText("What's worth doing around you, for your level. Click a row for a map pin; hover for details.")
    panel.empty = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.empty:SetPoint("TOPLEFT", 12, TOP - 8); panel.empty:SetWidth(width - 24); panel.empty:SetJustifyH("LEFT")
    local height = parent.GetHeight and parent:GetHeight() or 0
    -- Rows fill the page down to the arrows.
    local count = height > 0 and math.floor((height + TOP - 20) / ROW_HEIGHT) or 13
    count = 24 -- more than fit; Shown() decides how many show
    for i = 1, count do
        local line = CreateFrame("Button", nil, parent)
        line:SetSize(width - 8, ROW_HEIGHT)
        line:SetPoint("TOPLEFT", 4, TOP - (i - 1) * ROW_HEIGHT)
        line:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        line.icon = line:CreateTexture(nil, "ARTWORK")
        line.icon:SetSize(24, 24); line.icon:SetPoint("LEFT", 2, 0)
        line.cost = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        line.cost:SetJustifyH("RIGHT")
        line.detail = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line.detail:SetJustifyH("RIGHT")
        PlaceRight(line, false)
        line.name = line:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        line.name:SetPoint("TOPLEFT", 32, -3); line.name:SetPoint("RIGHT", line.cost, "LEFT", -6, 0); line.name:SetJustifyH("LEFT")
        line.sub = line:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        line.sub:SetPoint("BOTTOMLEFT", 32, 4); line.sub:SetPoint("RIGHT", line.detail, "LEFT", -6, 0); line.sub:SetJustifyH("LEFT")
        for _, f in ipairs({ line.name, line.sub }) do if f.SetWordWrap then f:SetWordWrap(false) end end
        local thisLine = line
        line.search = CreateFrame("Button", nil, line, "UIPanelButtonTemplate")
        line.search:SetSize(58, 20); line.search:SetPoint("RIGHT", -4, 0); line.search:SetText("Search")
        line.search:SetScript("OnClick", function() pcall(Search, thisLine) end)
        line.search:Hide()
        line:SetScript("OnEnter", ShowRow)
        line:SetScript("OnLeave", function() GameTooltip:Hide() end)
        line:SetScript("OnClick", function()
            if thisLine.row and thisLine.row.header then Toggle(thisLine.row.key) else pcall(Pin, thisLine) end
        end)
        lines[i] = line
    end
    panel.up = DufforthTweaksHelper.ArrowButton(parent, "up", function() Scroll(-Shown()) end)
    panel.up:SetPoint("BOTTOMRIGHT", -30, 2)
    panel.down = DufforthTweaksHelper.ArrowButton(parent, "down", function() Scroll(Shown()) end)
    panel.down:SetPoint("LEFT", panel.up, "RIGHT", 4, 0)
    panel.pageText = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.pageText:SetPoint("RIGHT", panel.up, "LEFT", -6, 0); panel.pageText:SetJustifyH("RIGHT")
    parent:EnableMouseWheel(true)
    parent:SetScript("OnMouseWheel", function(_, delta) Scroll(-delta) end)
    parent:HookScript("OnShow", Zone.Refresh)
end

-- New zone, new level, a quest done, the auction house opening or closing: redraw.
local watcher = CreateFrame("Frame")
for _, event in ipairs({ "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP", "QUEST_TURNED_IN", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" }) do
    pcall(watcher.RegisterEvent, watcher, event)
end
watcher:SetScript("OnEvent", function()
    if panel and panel.IsVisible and panel:IsVisible() then
        if C_Timer then C_Timer.After(0.3, Zone.Refresh) else Zone.Refresh() end
    end
    if DufforthTweaksHelperConsumables and DufforthTweaksHelperConsumables.Redraw then DufforthTweaksHelperConsumables.Redraw() end
end)
