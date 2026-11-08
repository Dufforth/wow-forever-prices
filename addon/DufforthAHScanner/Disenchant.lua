-- Disenchant values in item tooltips: what weapons and armor can turn into, the chance of
-- each material, its price, and the average value. Uses the same Classic tables as the
-- Forever Prices page. Prices are Blizzard's, bundled with each download (Prices.lua).
-- Turn it off with /dufforth de off.

local PREFIX = "|cff66ccffDufforth AH Scanner:|r "
local AUCTION_CUT = 0.05
local OLD_PRICES_SECONDS = 2 * 24 * 3600 -- older bundled prices say how old they are
local WEAPON, ARMOR = 2, 4
local UNCOMMON, RARE, EPIC = 2, 3, 4
local ENCHANTING = 333
local SKIP_SLOTS = { INVTYPE_BODY = true, INVTYPE_TABARD = true } -- shirts and tabards

-- Row fields: item levels from, to; dust, essence, shard item IDs; dust and essence chance
-- for armor; dust and essence chance for weapons; dust and essence amounts.
local UNCOMMON_TABLE = {
    { 5, 15, 10940, 10938, nil, 80, 20, 20, 80, 1, 2, 1, 2 },
    { 16, 20, 10940, 10939, 10978, 75, 20, 20, 75, 2, 3, 1, 2 },
    { 21, 25, 10940, 10998, 10978, 75, 15, 15, 75, 4, 6, 1, 2 },
    { 26, 30, 11083, 11082, 11084, 75, 20, 20, 75, 1, 2, 1, 2 },
    { 31, 35, 11083, 11134, 11138, 75, 20, 20, 75, 2, 5, 1, 2 },
    { 36, 40, 11137, 11135, 11139, 75, 20, 20, 75, 1, 2, 1, 2 },
    { 41, 45, 11137, 11174, 11177, 75, 20, 20, 75, 2, 5, 1, 2 },
    { 46, 50, 11176, 11175, 11178, 75, 20, 20, 75, 1, 2, 1, 2 },
    { 51, 55, 11176, 16202, 14343, 75, 20, 22, 75, 2, 5, 1, 2 },
    { 56, 60, 16204, 16203, 14344, 75, 20, 22, 75, 1, 2, 1, 2 },
    { 61, 65, 16204, 16203, 14344, 75, 20, 22, 75, 2, 5, 2, 3 },
}
local RARE_TABLE = {
    { 1, 25, 10978 }, { 26, 30, 11084 }, { 31, 35, 11138 }, { 36, 40, 11139 }, { 41, 45, 11177 },
    { 46, 50, 11178 }, { 51, 55, 14343 }, { 56, 80, 14344, 20725 },
}
local EPIC_TABLE = {
    { 40, 45, 11177, 2, 4 }, { 46, 50, 11178, 2, 4 }, { 51, 55, 14343, 2, 4 }, { 56, 60, 20725, 1, 1 }, { 61, 88, 20725, 1, 2 },
}

-- Names for when the game hasn't loaded a material's details yet.
local NAMES = {
    [10940] = "Strange Dust", [10938] = "Lesser Magic Essence", [10939] = "Greater Magic Essence",
    [10998] = "Lesser Astral Essence", [11082] = "Greater Astral Essence", [11134] = "Lesser Mystic Essence",
    [11135] = "Greater Mystic Essence", [11174] = "Lesser Nether Essence", [11175] = "Greater Nether Essence",
    [16202] = "Lesser Eternal Essence", [16203] = "Greater Eternal Essence", [11083] = "Soul Dust",
    [11137] = "Vision Dust", [11176] = "Dream Dust", [16204] = "Illusion Dust", [10978] = "Small Glimmering Shard",
    [11084] = "Large Glimmering Shard", [11138] = "Small Glowing Shard", [11139] = "Large Glowing Shard",
    [11177] = "Small Radiant Shard", [11178] = "Large Radiant Shard", [14343] = "Small Brilliant Shard",
    [14344] = "Large Brilliant Shard", [20725] = "Nexus Crystal",
}

local function FindBand(rows, level)
    for _, row in ipairs(rows) do
        if level >= row[1] and level <= row[2] then return row end
    end
end

-- item: { quality, level, classID, slot }. Returns { { id, chance (0-1), min, max }, ... } or nil.
local function Outcomes(item)
    if not item or not item.level or (item.classID ~= WEAPON and item.classID ~= ARMOR) then return nil end
    if SKIP_SLOTS[item.slot or ""] then return nil end
    local level = item.level
    if item.quality == UNCOMMON then
        local row = FindBand(UNCOMMON_TABLE, level)
        if not row then return nil end
        local weapon = item.classID == WEAPON
        local dust = (weapon and row[8] or row[6]) / 100
        local essence = (weapon and row[9] or row[7]) / 100
        local out = {
            { id = row[3], chance = dust, min = row[10], max = row[11] },
            { id = row[4], chance = essence, min = row[12], max = row[13] },
        }
        if row[5] then out[#out + 1] = { id = row[5], chance = math.max(0, 1 - dust - essence), min = 1, max = 1 } end
        return out
    elseif item.quality == RARE then
        local row = FindBand(RARE_TABLE, level)
        if not row then return nil end
        if row[4] then
            return { { id = row[3], chance = 0.995, min = 1, max = 1 }, { id = row[4], chance = 0.005, min = 1, max = 1 } }
        end
        return { { id = row[3], chance = 1, min = 1, max = 1 } }
    elseif item.quality == EPIC then
        local row = FindBand(EPIC_TABLE, level)
        return row and { { id = row[3], chance = 1, min = row[4], max = row[5] } } or nil
    end
end

-- Enchanting skill needed, by the Classic rule.
local function SkillNeeded(item)
    if not Outcomes(item) then return nil end
    local level = item.level
    if item.quality >= RARE and level <= 25 then return 25 end
    if level <= 20 then return 1 end
    return math.max(25, (math.ceil(level / 5) - 4) * 25)
end

-- Auction price of one item for your market, from the prices bundled with the download, or nil.
local function Price(id, market, shipped)
    local prices = shipped and shipped[market]
    return prices and prices[id] or nil
end

-- Average value after the auction cut, or nil if a material has no price.
local function ExpectedValue(outcomes, priceOf)
    local total = 0
    for _, o in ipairs(outcomes) do
        if o.chance > 0 then
            local price = priceOf(o.id)
            if not price then return nil end
            total = total + o.chance * (o.min + o.max) / 2 * price * (1 - AUCTION_CUT)
        end
    end
    return total
end

local function Money(copper)
    copper = math.floor(copper + 0.5)
    local gold, silver, rest = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
    if gold > 0 then return string.format("|cffffd100%dg|r |cffc7c7cf%ds|r", gold, silver) end
    if silver > 0 then return string.format("|cffc7c7cf%ds|r |cffeda55f%dc|r", silver, rest) end
    return string.format("|cffeda55f%dc|r", rest)
end

local function MaterialName(id)
    local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (GetItemInfo and GetItemInfo(id))
    return name or NAMES[id] or ("Item " .. id)
end

-- Your Enchanting skill, or false if you don't have it, or nil if the game can't tell.
local function EnchantingSkill()
    if GetProfessions and GetProfessionInfo then
        local first, second = GetProfessions()
        for _, index in ipairs({ first or 0, second or 0 }) do
            if index ~= 0 then
                local _, _, rank, _, _, _, line, modifier = GetProfessionInfo(index)
                if line == ENCHANTING and rank then return rank + (modifier or 0) end
            end
        end
        return false
    end
end

-- The lines added to a tooltip: { left, right, r, g, b } each. Kept apart from the tooltip so tests can read them.
local function TooltipLines(item, market, shipped, now, skill)
    local outcomes = Outcomes(item)
    if not outcomes then return nil end
    local need = SkillNeeded(item)
    local lines = {}
    local header = "Disenchants into"
    local r, g, b = 0.4, 0.8, 1
    if need and need > 1 then
        header = header .. string.format(" (Enchanting %d)", need)
        if skill ~= nil and (skill == false or skill < need) then r, g, b = 1, 0.35, 0.35 end
    end
    lines[#lines + 1] = { header, nil, r, g, b }
    local function priceOf(id) return Price(id, market, shipped) end
    for _, o in ipairs(outcomes) do
        if o.chance > 0 then
            local amount = o.min == o.max and tostring(o.min) or (o.min .. "-" .. o.max)
            local chance = o.chance >= 0.995 and "" or (string.format("%g%%", math.floor(o.chance * 1000 + 0.5) / 10) .. "  ")
            local price = priceOf(o.id)
            lines[#lines + 1] = { "  " .. chance .. amount .. "x " .. MaterialName(o.id), price and (Money(price) .. " each") or "no price", 1, 1, 1 }
        end
    end
    local value = ExpectedValue(outcomes, priceOf)
    if value then
        local age = shipped and shipped.at and now - shipped.at or 0
        local note = age > OLD_PRICES_SECONDS and string.format(" (prices %d days old)", math.floor(age / 86400)) or ""
        lines[#lines + 1] = { "  Average value" .. note, Money(value), 0.6, 1, 0.6 }
    end
    return lines
end

-- Average value of disenchanting one item, or nil.
local function ValueFor(item, market, shipped)
    local outcomes = Outcomes(item)
    if not outcomes then return nil end
    return ExpectedValue(outcomes, function(id) return Price(id, market, shipped) end)
end

DufforthAHScannerDE = {
    Outcomes = Outcomes, SkillNeeded = SkillNeeded, Price = Price, ExpectedValue = ExpectedValue,
    TooltipLines = TooltipLines, ValueFor = ValueFor, EnchantingSkill = EnchantingSkill, Money = Money,
}

-- ---- Tooltip ----
local function Enabled()
    return not (DufforthAHScannerDB and DufforthAHScannerDB.showDisenchant == false)
end

local function ItemFromID(id)
    if not id then return nil end
    local name, _, quality, level, _, _, _, _, slot, icon, sellPrice, classID, _, bindType = GetItemInfo(id)
    if not quality then return nil end
    return { id = id, name = name, icon = icon, quality = quality, level = level, classID = classID, slot = slot, sellPrice = sellPrice, bindType = bindType }
end
DufforthAHScannerDE.ItemFromID = ItemFromID

local function AddToTooltip(tooltip, id)
    if not Enabled() or not tooltip or not id then return end
    if tooltip.dufforthDE == id then return end -- some tooltips fire twice for one item
    local lines = TooltipLines(ItemFromID(id), DufforthAHScanner and DufforthAHScanner.MarketName and DufforthAHScanner.MarketName() or "",
        DufforthAHScannerPrices, time(), EnchantingSkill())
    if not lines then return end
    tooltip.dufforthDE = id
    for _, line in ipairs(lines) do
        if line[2] then
            tooltip:AddDoubleLine(line[1], line[2], line[3], line[4], line[5], 1, 1, 1)
        else
            tooltip:AddLine(line[1], line[3], line[4], line[5])
        end
    end
    tooltip:Show()
end

local function IdFromLink(link)
    return link and tonumber(string.match(link, "item:(%d+)"))
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        local id = data and data.id
        if not id and tooltip.GetItem then id = IdFromLink(select(2, tooltip:GetItem())) end
        AddToTooltip(tooltip, id)
    end)
else
    for _, name in ipairs({ "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }) do
        local tooltip = _G[name]
        if tooltip and tooltip.HookScript then
            tooltip:HookScript("OnTooltipSetItem", function(self) AddToTooltip(self, IdFromLink(select(2, self:GetItem()))) end)
        end
    end
end
for _, name in ipairs({ "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }) do
    local tooltip = _G[name]
    if tooltip and tooltip.HookScript then
        tooltip:HookScript("OnTooltipCleared", function(self) self.dufforthDE = nil end)
    end
end

-- /dufforth de [on|off] goes through Core.lua's slash command.
function DufforthAHScannerDE.Toggle(option)
    DufforthAHScannerDB = DufforthAHScannerDB or {}
    if option == "on" then
        DufforthAHScannerDB.showDisenchant = true
    elseif option == "off" then
        DufforthAHScannerDB.showDisenchant = false
    else
        DufforthAHScannerDB.showDisenchant = not Enabled()
    end
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. "Disenchant values in tooltips: " .. (Enabled() and "ON" or "OFF") .. ".")
end
