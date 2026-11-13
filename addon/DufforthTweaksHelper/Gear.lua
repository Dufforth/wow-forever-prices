-- Dufforth Tweaks Helper, class tab Gear view: upgrades for what you wear, from the auction house
-- and from quests you can do now (user, 2026-11-12: "recommend replacement for my current gear with
-- upgrades from AH and quest items I can go for").
--
-- Stats come from the game itself (C_Item.GetItemStats), so they match Forever. Each item gets
-- points: every stat times how much it helps your class (the consumables' class weights), weapon
-- damage per second times 14 attack power, and armor. An upgrade beats what you wear in that slot.
-- Candidates: AH gear the price data covers (GearData.lua) at or a bit below your level, and the
-- gear rewards of quests for your level, side and class that you haven't done (ZoneData.lua).

local Gear = {}
DufforthTweaksHelperGear = Gear

local LEVEL_WINDOW = 8 -- AH items needing up to this many levels below yours
local QUEST_BELOW, QUEST_ABOVE = 3, 3
local MIN_GAIN = 1.5 -- points: smaller differences aren't worth the money or the trip
local AP_PER_DPS = 14

-- Item stats from the game -> the advice's stat names.
local STAT_KEYS = {
    ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_STAMINA_SHORT = "sta",
    ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spi", ITEM_MOD_ATTACK_POWER_SHORT = "ap",
    ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rap", ITEM_MOD_SPELL_POWER_SHORT = "sp", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "sp",
    ITEM_MOD_SPELL_HEALING_DONE_SHORT = "heal", ITEM_MOD_MANA_REGENERATION_SHORT = "mp5", RESISTANCE0_NAME = "armor",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps",
}
Gear.STAT_KEYS = STAT_KEYS

-- Inventory type -> the slots it can go in.
local SLOTS = { [1] = { 1 }, [2] = { 2 }, [3] = { 3 }, [5] = { 5 }, [20] = { 5 }, [6] = { 6 }, [7] = { 7 }, [8] = { 8 },
    [9] = { 9 }, [10] = { 10 }, [11] = { 11, 12 }, [12] = { 13, 14 }, [16] = { 15 }, [13] = { 16 }, [17] = { 16 },
    [21] = { 16 }, [22] = { 17 }, [14] = { 17 }, [23] = { 17 }, [15] = { 18 }, [25] = { 18 }, [26] = { 18 }, [28] = { 18 } }
Gear.SLOTS = SLOTS
local SLOT_NAMES = { [1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet",
    [9] = "Wrist", [10] = "Hands", [11] = "Ring", [12] = "Ring", [13] = "Trinket", [14] = "Trinket", [15] = "Back",
    [16] = "Main hand", [17] = "Off hand", [18] = "Ranged" }
Gear.SLOT_NAMES = SLOT_NAMES
local EQUIP_LOC = { INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_CHEST = 5, INVTYPE_ROBE = 20,
    INVTYPE_WAIST = 6, INVTYPE_LEGS = 7, INVTYPE_FEET = 8, INVTYPE_WRIST = 9, INVTYPE_HAND = 10, INVTYPE_FINGER = 11,
    INVTYPE_TRINKET = 12, INVTYPE_CLOAK = 16, INVTYPE_WEAPON = 13, INVTYPE_2HWEAPON = 17, INVTYPE_WEAPONMAINHAND = 21,
    INVTYPE_WEAPONOFFHAND = 22, INVTYPE_SHIELD = 14, INVTYPE_HOLDABLE = 23, INVTYPE_RANGED = 15, INVTYPE_THROWN = 25,
    INVTYPE_RANGEDRIGHT = 26, INVTYPE_RELIC = 28 }
Gear.EQUIP_LOC = EQUIP_LOC

-- What each class can wear: armor subclasses (0 misc, 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield)
-- and weapon subclasses (0/1 axe, 2 bow, 3 gun, 4/5 mace, 6 polearm, 7/8 sword, 10 staff, 13 fist,
-- 15 dagger, 16 thrown, 18 crossbow, 19 wand). Plate and mail come at level 40 (Classic).
local function Set(list) local s = {} for _, v in ipairs(list) do s[v] = true end return s end
local ARMOR = {
    WARRIOR = { base = Set({ 0, 1, 2, 3, 6 }), at40 = 4 }, PALADIN = { base = Set({ 0, 1, 2, 3, 6, 7 }), at40 = 4 },
    HUNTER = { base = Set({ 0, 1, 2 }), at40 = 3 }, SHAMAN = { base = Set({ 0, 1, 2, 6, 9 }), at40 = 3 },
    ROGUE = { base = Set({ 0, 1, 2 }) }, DRUID = { base = Set({ 0, 1, 2, 8 }) },
    MAGE = { base = Set({ 0, 1 }) }, PRIEST = { base = Set({ 0, 1 }) }, WARLOCK = { base = Set({ 0, 1 }) },
}
local WEAPONS = {
    WARRIOR = Set({ 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 }), PALADIN = Set({ 0, 1, 4, 5, 6, 7, 8 }),
    HUNTER = Set({ 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 }), ROGUE = Set({ 2, 3, 4, 7, 13, 15, 16, 18 }),
    PRIEST = Set({ 4, 10, 15, 19 }), SHAMAN = Set({ 0, 1, 4, 5, 10, 13, 15 }), MAGE = Set({ 7, 10, 15, 19 }),
    WARLOCK = Set({ 7, 10, 15, 19 }), DRUID = Set({ 4, 5, 10, 13, 15 }),
}
local WEAPON, ARMOR_CLASS = 2, 4

function Gear.CanWear(class, level, itemClass, subclass)
    if itemClass == ARMOR_CLASS then
        local a = ARMOR[class]
        return a and (a.base[subclass] or (a.at40 == subclass and level >= 40)) and true or false
    elseif itemClass == WEAPON then
        return WEAPONS[class] and WEAPONS[class][subclass] or false
    end
    return false
end

-- stats = { [game stat key] = amount } -> { str = .., dps = .. }
function Gear.Normalize(raw)
    local out = {}
    for key, value in pairs(raw or {}) do
        local name = STAT_KEYS[key]
        if name and type(value) == "number" then out[name] = (out[name] or 0) + value end
    end
    return out
end

-- Points for a class; ranged = the ranged slot (its damage counts through ranged attack power).
function Gear.Score(stats, class, ranged)
    local weights = DufforthTweaksHelperConsumables and DufforthTweaksHelperConsumables.WEIGHTS or {}
    local w = weights[class] or weights.WARRIOR or {}
    local total = 0
    for key, value in pairs(stats) do
        if key == "dps" then
            local per = ranged and (w.rap or 0) or (w.ap or 0)
            total = total + value * AP_PER_DPS * per
        else
            total = total + (w[key] or 0) * value
        end
    end
    return total
end

-- equipped = { [slot] = { score, name, invType } }; candidates = { { id, inv, score, source... } }.
-- -> list of { slot, candidate, gain, current } best per slot and source (auction / quest).
function Gear.Upgrades(candidates, equipped)
    local best = {}
    for _, c in ipairs(candidates) do
        local slots = SLOTS[c.inv]
        if slots then
            -- Rings and trinkets: compare with the weaker of your two.
            local slot, current = nil, nil
            for _, s in ipairs(slots) do
                local e = equipped[s]
                local fits = true
                if s == 16 and e and e.inv then fits = (c.inv == 17) == (e.inv == 17) end -- two-hander for two-hander
                if s == 17 and e and e.inv then fits = (c.inv == 14) == (e.inv == 14) end -- shield for shield
                if s == 17 and not e then fits = c.inv == 14 or c.inv == 23 end
                if s == 17 and equipped[16] and equipped[16].inv == 17 then fits = false end -- a two-hander fills both hands
                if fits and (not current or (e and e.score or 0) < current.score) then slot, current = s, e or { score = 0, name = "nothing" } end
            end
            if slot then
                local gain = c.score - current.score
                if gain >= MIN_GAIN then
                    local key = slot .. ":" .. c.source
                    if not best[key] or gain > best[key].gain or (gain == best[key].gain and (c.price or 0) < (best[key].candidate.price or 0)) then
                        best[key] = { slot = slot, candidate = c, gain = gain, current = current }
                    end
                end
            end
        end
    end
    local out = {}
    for _, b in pairs(best) do out[#out + 1] = b end
    table.sort(out, function(a, b)
        if a.slot ~= b.slot then return a.slot < b.slot end
        return a.candidate.source < b.candidate.source
    end)
    return out
end

-- Quests that reward gear, for your level, side and class, not done: { { id, title, level, zone, giver, x, y, items } }.
function Gear.QuestRewards(zones, level, side, classBit, done)
    local out = {}
    for zone, z in pairs(zones or {}) do
        for _, q in ipairs(z.q or {}) do
            local rewards = q[15]
            if rewards and #rewards > 0 and q[4] <= level and q[3] >= level - QUEST_BELOW and q[3] <= level + QUEST_ABOVE
                and (q[5] == "" or q[5] == side) and (q[13] == 0 or not classBit or math.floor(q[13] / classBit) % 2 == 1)
                and q[12] ~= "dungeon" and q[12] ~= "raid" and not (done and done(q[1])) then
                out[#out + 1] = { id = q[1], title = q[2], level = q[3], zone = zone, giver = q[9], x = q[10], y = q[11], items = rewards }
            end
        end
    end
    return out
end

-- ---- Reading the game ----
local pending = {}

local function ItemStats(link)
    if not link then return nil end
    local getStats = (C_Item and C_Item.GetItemStats) or GetItemStats
    if not getStats then return nil end
    local ok, stats = pcall(getStats, link)
    return ok and stats or nil
end

local function ItemInfo(id)
    local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getInstant or not getInfo then return {} end
    local _, _, _, equipLoc, _, classID, subclassID = getInstant(id)
    local name, _, quality, _, minLevel = getInfo(id)
    return { equipLoc = equipLoc, inv = EQUIP_LOC[equipLoc], class = classID, subclass = subclassID, name = name, quality = quality, minLevel = minLevel }
end

local function Request(id)
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    pending[id] = true
end

local function Equipped(class)
    local out = {}
    for slot = 1, 18 do
        local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
        if link then
            local id = GetInventoryItemID("player", slot)
            local stats = ItemStats(link)
            local info = id and ItemInfo(id) or {}
            out[slot] = { score = stats and Gear.Score(Gear.Normalize(stats), class, slot == 18) or 0, name = info.name or "?", inv = info.inv, link = link, id = id }
        end
    end
    return out
end

local function Prices()
    local market = DufforthTweaksHelper and DufforthTweaksHelper.MarketName and DufforthTweaksHelper.MarketName() or ""
    return DufforthTweaksHelperPrices and DufforthTweaksHelperPrices[market] or {}
end

-- Builds the candidates from the game's item data; items not loaded yet are requested and counted.
function Gear.Advice()
    local class = (UnitClass and select(2, UnitClass("player"))) or "WARRIOR"
    local classID = UnitClass and select(3, UnitClass("player"))
    local level = UnitLevel and UnitLevel("player") or 1
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local side = faction == "Alliance" and "A" or faction == "Horde" and "H" or ""
    local prices = Prices()
    local candidates, waiting = {}, 0
    local function Add(id, inv, source, extra)
        local stats = ItemStats("item:" .. id)
        if not stats or next(stats) == nil then
            Request(id); waiting = waiting + 1
            return
        end
        local c = { id = id, inv = inv, source = source, score = Gear.Score(Gear.Normalize(stats), class, SLOTS[inv] and SLOTS[inv][1] == 18) }
        for k, v in pairs(extra or {}) do c[k] = v end
        candidates[#candidates + 1] = c
    end
    for _, row in ipairs(DufforthTweaksHelperGearData or {}) do
        local id, inv, rl, itemClass, sub = row[1], row[2], row[3], row[4], row[5]
        local price = prices[id]
        if price and rl <= level and rl >= level - LEVEL_WINDOW and Gear.CanWear(class, level, itemClass, sub) then
            Add(id, inv, "auction", { price = price })
        end
    end
    local done = function(id)
        return C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id) or false
    end
    for _, q in ipairs(Gear.QuestRewards(DufforthTweaksHelperZoneData, level, side, classID and 2 ^ (classID - 1), done)) do
        for _, id in ipairs(q.items) do
            local info = ItemInfo(id)
            if not info.inv then
                Request(id); waiting = waiting + 1
            elseif info.class and Gear.CanWear(class, level, info.class, info.subclass) and (not info.minLevel or info.minLevel <= level + QUEST_ABOVE) then
                Add(id, info.inv, "quest", { quest = q })
            end
        end
    end
    return Gear.Upgrades(candidates, Equipped(class)), waiting
end

-- ---- Panel ----
local ROW_HEIGHT, TOP = 30, -40
local panel, lines, rows, offset = nil, {}, {}, 0
local QUALITY = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee" }

local function Money(c) return DufforthTweaksHelperDE and DufforthTweaksHelperDE.Money and DufforthTweaksHelperDE.Money(c) or tostring(c) end
local function NameOf(id)
    local name, _, quality = (C_Item and C_Item.GetItemInfo or GetItemInfo)(id)
    return name and ("|cff" .. (QUALITY[quality] or "ffffff") .. name .. "|r") or ("Item " .. id)
end
local function AtAuction()
    local L = DufforthTweaksHelperLeveling
    return L and L.Where and L.Where().auction or false
end

local function PlaceRight(line, searching)
    local inset = searching and -66 or -4
    line.cost:ClearAllPoints(); line.cost:SetPoint("TOPRIGHT", inset, -3)
    line.detail:ClearAllPoints(); line.detail:SetPoint("BOTTOMRIGHT", inset, 4)
end

local function Draw()
    local auction = AtAuction()
    for i, line in ipairs(lines) do
        local r = rows[offset + i]
        line.row = r
        line:SetShown(r ~= nil)
        local searching = r ~= nil and not r.header and r.candidate.source == "auction" and auction and true or false
        line.search:SetShown(searching)
        PlaceRight(line, searching)
        if r and r.header then
            line.icon:Hide(); line.cost:SetText(""); line.detail:SetText("")
            line.name:SetText("|cff73bfff" .. r.header .. "|r"); line.sub:SetText(r.note or "")
        elseif r then
            local c = r.candidate
            line.icon:Show()
            line.icon:SetTexture((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(c.id)) or (GetItemIcon and GetItemIcon(c.id)) or "Interface\\Icons\\INV_Misc_QuestionMark")
            line.name:SetText(NameOf(c.id))
            local from = c.source == "auction" and ("|cffff9933AH|r " .. Money(c.price))
                or string.format("|cffffd100Quest|r %s (%d, %s)", c.quest.title, c.quest.level, c.quest.zone)
            line.sub:SetText(string.format("%s, replaces %s. %s", SLOT_NAMES[r.slot], r.current.name, from))
            line.cost:SetText(string.format("|cff40ff40+%.1f|r", r.gain))
            line.detail:SetText("points")
        end
    end
    panel.pageText:SetText(#rows > #lines and string.format("%d / %d", math.floor(offset / #lines) + 1, math.ceil(#rows / #lines)) or "")
end

local function Scroll(delta)
    offset = math.max(0, math.min(offset + delta, math.max(0, #rows - #lines)))
    Draw()
end

function Gear.Refresh()
    if not panel or not (panel.IsVisible and panel:IsVisible()) then return end
    local ok, upgrades, waiting = pcall(Gear.Advice)
    if not ok then
        panel.empty:SetText("|cffff5555The gear advice hit an error:|r " .. tostring(upgrades))
        return
    end
    local _, className = UnitClass and UnitClass("player")
    panel.title:SetText(string.format("Gear upgrades for your %s, level %d", className or "class", UnitLevel and UnitLevel("player") or 1))
    rows = {}
    local auction, quest = {}, {}
    for _, u in ipairs(upgrades) do
        if u.candidate.source == "quest" then quest[#quest + 1] = u else auction[#auction + 1] = u end
    end
    if #quest > 0 then
        rows[#rows + 1] = { header = "From quests you can do now" }
        for _, u in ipairs(quest) do rows[#rows + 1] = u end
    end
    if #auction > 0 then
        rows[#rows + 1] = { header = "From the auction house" }
        for _, u in ipairs(auction) do rows[#rows + 1] = u end
    end
    panel.status:SetText(waiting > 0 and string.format("Loading %d items from the game...", waiting) or "")
    panel.empty:SetText(#rows > 0 and "" or (waiting > 0 and "Loading item data, one moment." or "No upgrades found: your gear beats what the AH and your quests offer at your level."))
    offset = math.min(offset, math.max(0, #rows - #lines))
    Draw()
end

local function ShowRow(line)
    local r = line.row
    if not r or r.header then return end
    local c = r.candidate
    GameTooltip:SetOwner(line, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then GameTooltip:SetItemByID(c.id) else GameTooltip:SetText(NameOf(c.id)) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Better than " .. r.current.name, string.format("+%.1f points", r.gain), 0.8, 0.8, 0.8, 0.25, 1, 0.25)
    if c.source == "quest" then
        GameTooltip:AddLine(string.format("Reward of \"%s\" (level %d) in %s%s.", c.quest.title, c.quest.level, c.quest.zone,
            c.quest.giver ~= "" and (", from " .. c.quest.giver) or ""), 1, 0.82, 0, true)
        GameTooltip:AddLine("Quest data: Classic estimates. Some quests let you pick one reward.", 0.6, 0.6, 0.6, true)
    else
        GameTooltip:AddLine("On the auction house for about " .. Money(c.price) .. ".", 1, 0.6, 0.2, true)
    end
    GameTooltip:AddLine("Points: each stat times how much it helps your class, weapon damage per second x 14 attack power, and armor.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

local function Search(line)
    local r = line.row
    local L = DufforthTweaksHelperLeveling
    if r and not r.header and L and L.SearchAuctionHouse then L.SearchAuctionHouse(r.candidate.id) end
end

function Gear.BuildPanel(parent, width)
    panel = parent
    panel.title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", 8, -4)
    panel.legend = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.legend:SetPoint("TOPLEFT", 8, -22); panel.legend:SetWidth(width - 16); panel.legend:SetJustifyH("LEFT")
    panel.legend:SetText("Better than what you wear, by points for your class. Hover for the item; at the AH, Search opens it.")
    panel.status = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.status:SetPoint("BOTTOMLEFT", 8, 8)
    panel.empty = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.empty:SetPoint("TOPLEFT", 12, TOP - 8); panel.empty:SetWidth(width - 24); panel.empty:SetJustifyH("LEFT")
    local height = parent.GetHeight and parent:GetHeight() or 0
    local count = height > 0 and math.floor((height + TOP - 20) / ROW_HEIGHT) or 13
    count = math.max(4, math.min(count, 20))
    for i = 1, count do
        local line = CreateFrame("Button", nil, parent)
        line:SetSize(width - 8, ROW_HEIGHT)
        line:SetPoint("TOPLEFT", 4, TOP - (i - 1) * ROW_HEIGHT)
        line:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        line.icon = line:CreateTexture(nil, "ARTWORK")
        line.icon:SetSize(24, 24); line.icon:SetPoint("LEFT", 2, 0)
        line.cost = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        line.cost:SetJustifyH("RIGHT")
        line.detail = line:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
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
        lines[i] = line
    end
    panel.up = DufforthTweaksHelper.ArrowButton(parent, "up", function() Scroll(-#lines) end)
    panel.up:SetPoint("BOTTOMRIGHT", -30, 2)
    panel.down = DufforthTweaksHelper.ArrowButton(parent, "down", function() Scroll(#lines) end)
    panel.down:SetPoint("LEFT", panel.up, "RIGHT", 4, 0)
    panel.pageText = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.pageText:SetPoint("RIGHT", panel.up, "LEFT", -6, 0); panel.pageText:SetJustifyH("RIGHT")
    parent:EnableMouseWheel(true)
    parent:SetScript("OnMouseWheel", function(_, delta) Scroll(-delta) end)
    parent:HookScript("OnShow", Gear.Refresh)
end

-- Item data arriving, gear changes, level-ups, the AH opening: redraw (at most twice a second).
local watcher = CreateFrame("Frame")
for _, event in ipairs({ "GET_ITEM_INFO_RECEIVED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "QUEST_TURNED_IN" }) do
    pcall(watcher.RegisterEvent, watcher, event)
end
local soon = false
watcher:SetScript("OnEvent", function()
    if soon or not panel then return end
    soon = true
    local function go() soon = false; pcall(Gear.Refresh) end
    if C_Timer then C_Timer.After(0.5, go) else go() end
end)
