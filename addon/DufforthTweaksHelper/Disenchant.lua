-- Sell or disenchant advice in item tooltips, for every player: one colored verdict line with
-- what pays most (auction house after its 5% cut, vendor, or disenchant), then short detail lines
-- with the prices aligned. Disenchanting shows only when it's worth knowing, with a note when you
-- lack the Enchanting skill. Uses the same Classic tables as the Forever Prices page. Prices are
-- Blizzard's, bundled with each download (Prices.lua). Settings: the Disenchant tab or /dufforth de off.

local L = DufforthTweaksHelperL or setmetatable({}, { __index = function(_, k) return k end })
local PREFIX = L["|cff66ccffDufforth Tweaks Helper:|r "]
local AUCTION_CUT = 0.05
local OLD_PRICES_SECONDS = 2 * 24 * 3600 -- older bundled prices say how old they are
local WEAPON, ARMOR = 2, 4
local UNCOMMON, RARE, EPIC = 2, 3, 4
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
    [10940] = L["Strange Dust"], [10938] = L["Lesser Magic Essence"], [10939] = L["Greater Magic Essence"],
    [10998] = L["Lesser Astral Essence"], [11082] = L["Greater Astral Essence"], [11134] = L["Lesser Mystic Essence"],
    [11135] = L["Greater Mystic Essence"], [11174] = L["Lesser Nether Essence"], [11175] = L["Greater Nether Essence"],
    [16202] = L["Lesser Eternal Essence"], [16203] = L["Greater Eternal Essence"], [11083] = L["Soul Dust"],
    [11137] = L["Vision Dust"], [11176] = L["Dream Dust"], [16204] = L["Illusion Dust"], [10978] = L["Small Glimmering Shard"],
    [11084] = L["Large Glimmering Shard"], [11138] = L["Small Glowing Shard"], [11139] = L["Large Glowing Shard"],
    [11177] = L["Small Radiant Shard"], [11178] = L["Large Radiant Shard"], [14343] = L["Small Brilliant Shard"],
    [14344] = L["Large Brilliant Shard"], [20725] = L["Nexus Crystal"],
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
    if item.id and DufforthTweaksHelperNoDE and DufforthTweaksHelperNoDE[item.id] then return nil end -- the game won't
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

-- The prices for a market. A market missing from the download (another region, a house the
-- page doesn't scan) uses the same ruleset and faction in the US, then the normal ruleset.
local function MarketPrices(market, shipped)
    if not shipped then return nil end
    if shipped[market] then return shipped[market] end
    local ruleset, faction = string.match(market or "", "^forever%.([^.]+)%.([^.]+)%.")
    if not faction then return nil end
    return shipped["forever." .. ruleset .. "." .. faction .. ".us"] or shipped["forever.normal." .. faction .. ".us"]
end

-- Auction price of one item for your market, from the prices bundled with the download, or nil.
local function Price(id, market, shipped)
    local prices = MarketPrices(market, shipped)
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
    if gold > 0 then return string.format(L["|cffffd100%dg|r |cffc7c7cf%ds|r"], gold, silver) end
    if silver > 0 then return string.format(L["|cffc7c7cf%ds|r |cffeda55f%dc|r"], silver, rest) end
    return string.format("|cffeda55f%dc|r", rest)
end

-- Forever's client has only C_Item.GetItemInfo: the global GetItemInfo is missing unless another
-- addon adds it back, which is why the advice showed on one PC and not on others.
local function ItemInfoFunction()
    if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo end
    if type(GetItemInfo) == "function" then return GetItemInfo end
end

local function MaterialName(id)
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    local info = ItemInfoFunction()
    if not name and info then name = info(id) end
    return name or NAMES[id] or (L["Item "] .. id)
end

-- Your Enchanting skill, or false if you don't have it, or nil if the game can't tell.
local function EnchantingSkill()
    local professions = DufforthTweaksHelper and DufforthTweaksHelper.Professions and DufforthTweaksHelper.Professions()
    if professions then return professions.Enchanting or false end
end

-- What to do with the item: the option that pays most. Ties go to the least work
-- (vendor, then auction house, then disenchant).
-- Returns { key = "vendor" | "ah" | "de", label, value, r, g, b }, or nil when nothing is known.
local ADVICE = {
    vendor = { label = L["Best: Vendor"], r = 0.8, g = 0.8, b = 0.8 },
    ah = { label = L["Best: Auction house"], r = 1, g = 0.82, b = 0 },
    de = { label = L["Best: Disenchant"], r = 0.3, g = 1, b = 0.4 },
}
local function Advice(deValue, ahNet, vendor)
    local best
    for _, option in ipairs({ { "vendor", vendor }, { "ah", ahNet }, { "de", deValue } }) do
        local value = option[2]
        if value and value > 0 and (not best or value > best.value) then best = { key = option[1], value = value } end
    end
    if not best then return nil end
    local style = ADVICE[best.key]
    best.label, best.r, best.g, best.b = style.label, style.r, style.g, style.b
    return best
end

-- Tooltip settings, saved in DufforthTweaksHelperDB.deTooltip: details (verdict and details, or the
-- verdict only), odds (each material's chance), shift (details only while Shift is held).
local TOOLTIP_DEFAULTS = { details = true, odds = false, shift = false }
local function TooltipOptions()
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    local o = DufforthTweaksHelperDB.deTooltip
    if type(o) ~= "table" then o = {}; DufforthTweaksHelperDB.deTooltip = o end
    for key, value in pairs(TOOLTIP_DEFAULTS) do
        if o[key] == nil then o[key] = value end
    end
    return o
end

local GRAY, DETAIL, MISSING = { 0.5, 0.5, 0.5 }, { 0.8, 0.8, 0.8 }, { 1, 0.5, 0.4 }

-- The lines added to a tooltip: { left, right, r, g, b } each. Kept apart from the tooltip so tests can read them.
-- First one verdict line (what pays most, with its value), then short detail lines with the
-- prices aligned on the right. Shown for any item with an auction price or a disenchant value.
-- item: { id, quality, level, classID, slot, sellPrice, bindType, stack }.
-- skill: your Enchanting (number), false (none) or nil (unknown: treated as enough).
-- opts: { details, odds, shift, shiftDown }; nil means the defaults.
local function TooltipLines(item, market, shipped, now, skill, opts)
    if not item then return nil end
    opts = opts or TOOLTIP_DEFAULTS
    local outcomes = Outcomes(item)
    local need = outcomes and SkillNeeded(item)
    local function priceOf(id) return Price(id, market, shipped) end
    local deValue = outcomes and ExpectedValue(outcomes, priceOf)
    local ah = item.id and priceOf(item.id)
    local ahNet = (ah and item.bindType ~= 1) and ah * (1 - AUCTION_CUT) or nil
    local vendor = item.sellPrice and item.sellPrice > 0 and item.sellPrice or nil
    if not ahNet and not deValue then return nil end -- nothing to decide
    local lacking = need ~= nil and (skill == false or (type(skill) == "number" and skill < need))

    -- The verdict picks among what you can do yourself; without the skill, disenchanting
    -- still shows when nothing else pays (an enchanter friend can do it).
    local advice = Advice(not lacking and deValue or nil, ahNet, vendor)
    local deUseful = deValue and deValue > 0 and (not lacking or not advice or deValue > advice.value)
    if not advice and deUseful then
        advice = Advice(deValue, nil, nil)
        advice.label = string.format(L["Best: Disenchant (Enchanting %d)"], need)
        advice.r, advice.g, advice.b = 1, 0.6, 0.2
    end
    if not advice then return nil end

    local each = (item.stack or 1) > 1 and L[" each"] or ""
    local lines = {}
    local function Line(left, right, color) lines[#lines + 1] = { left, right, color[1], color[2], color[3] } end
    local verdictValue = (advice.key == "de" and "~" or "") .. Money(advice.value) .. each
    lines[1] = { advice.label, verdictValue, advice.r, advice.g, advice.b }

    if opts.details == false then return lines, advice end
    if opts.shift and not opts.shiftDown then
        Line(L["  Hold Shift for details"], nil, GRAY)
        return lines, advice
    end
    if ahNet then Line(L["  Auction house (after 5% cut)"], Money(ahNet) .. each, DETAIL) end
    if vendor then Line(L["  Vendor"], Money(vendor) .. each, DETAIL) end
    if deUseful then
        if lacking then
            Line(string.format(L["  Disenchant (needs Enchanting %d)"], need), "~" .. Money(deValue), MISSING)
        else
            Line(L["  Disenchant (average)"], "~" .. Money(deValue), DETAIL)
        end
        if opts.odds then
            for _, o in ipairs(outcomes) do
                if o.chance > 0 then
                    local amount = o.min == o.max and tostring(o.min) or (o.min .. "-" .. o.max)
                    local chance = o.chance >= 0.995 and "" or (string.format("%g%%", math.floor(o.chance * 1000 + 0.5) / 10) .. "  ")
                    local price = priceOf(o.id)
                    Line("    " .. chance .. amount .. "x " .. MaterialName(o.id), price and (Money(price) .. L[" each"]) or L["no price"], GRAY)
                end
            end
        end
    end
    local age = shipped and shipped.at and now and now - shipped.at or 0
    if age > OLD_PRICES_SECONDS then Line(string.format(L["  Prices are %d days old"], math.floor(age / 86400)), nil, GRAY) end
    return lines, advice
end

-- Average value of disenchanting one item, or nil.
local function ValueFor(item, market, shipped)
    local outcomes = Outcomes(item)
    if not outcomes then return nil end
    return ExpectedValue(outcomes, function(id) return Price(id, market, shipped) end)
end

DufforthTweaksHelperDE = {
    Outcomes = Outcomes, SkillNeeded = SkillNeeded, Price = Price, ExpectedValue = ExpectedValue, Advice = Advice,
    TooltipLines = TooltipLines, ValueFor = ValueFor, EnchantingSkill = EnchantingSkill, Money = Money, MaterialName = MaterialName,
    TooltipOptions = TooltipOptions, MarketPrices = MarketPrices, AUCTION_CUT = AUCTION_CUT,
}

-- ---- Tooltip ----
local function Enabled()
    return not (DufforthTweaksHelperDB and DufforthTweaksHelperDB.showDisenchant == false)
end

-- An item's details by ID, or nil when the game hasn't loaded it yet (it is then asked to).
local function ItemFromID(id)
    local info = ItemInfoFunction()
    if not id or not info then return nil end
    local name, _, quality, level, _, _, _, stack, slot, icon, sellPrice, classID, _, bindType = info(id)
    if not quality then
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
        return nil
    end
    return { id = id, name = name, icon = icon, quality = quality, level = level, classID = classID, slot = slot, sellPrice = sellPrice, bindType = bindType, stack = stack }
end
DufforthTweaksHelperDE.ItemFromID = ItemFromID

local function ShiftDown() return IsShiftKeyDown and IsShiftKeyDown() and true or false end

local function AddLines(tooltip, id)
    local o = TooltipOptions()
    local lines = TooltipLines(ItemFromID(id), DufforthTweaksHelper and DufforthTweaksHelper.MarketName and DufforthTweaksHelper.MarketName() or "",
        DufforthTweaksHelperPrices, time(), EnchantingSkill(), { details = o.details, odds = o.odds, shift = o.shift, shiftDown = ShiftDown() })
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

local function AddToTooltip(tooltip, id)
    if not Enabled() or not tooltip or not id then return end
    if issecretvalue and issecretvalue(id) then return end
    if tooltip.dufforthDE == id then return end -- some tooltips fire twice for one item
    pcall(AddLines, tooltip, id) -- never break someone's tooltip
end

local function IdFromLink(link)
    if not link or (issecretvalue and issecretvalue(link)) then return nil end
    return tonumber(string.match(link, "item:(%d+)"))
end

-- Frame names, not text: never translated.
local TOOLTIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }
if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        local id = data and data.id
        if (not id or (issecretvalue and issecretvalue(id))) and tooltip.GetItem then id = IdFromLink(select(2, tooltip:GetItem())) end
        AddToTooltip(tooltip, id)
    end)
else
    for _, name in ipairs(TOOLTIPS) do
        local tooltip = _G[name]
        if tooltip and tooltip.HookScript then
            tooltip:HookScript("OnTooltipSetItem", function(self) AddToTooltip(self, IdFromLink(select(2, self:GetItem()))) end)
        end
    end
end
for _, name in ipairs(TOOLTIPS) do
    local tooltip = _G[name]
    if tooltip and tooltip.HookScript then
        tooltip:HookScript("OnTooltipCleared", function(self) self.dufforthDE = nil end)
    end
end

-- "Hold Shift for details": redraw the item tooltip when Shift goes down or up.
if CreateFrame then
    local watcher = CreateFrame("Frame")
    pcall(watcher.RegisterEvent, watcher, "MODIFIER_STATE_CHANGED")
    watcher:SetScript("OnEvent", function()
        if not (Enabled() and TooltipOptions().shift and TooltipOptions().details) then return end
        local tip = GameTooltip
        if tip and tip.IsShown and tip:IsShown() and tip.dufforthDE and tip.RefreshData then
            tip.dufforthDE = nil
            pcall(tip.RefreshData, tip)
        end
    end)
end

-- /dufforth de [on|off] goes through Core.lua's slash command.
function DufforthTweaksHelperDE.Toggle(option)
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    if option == "on" then
        DufforthTweaksHelperDB.showDisenchant = true
    elseif option == "off" then
        DufforthTweaksHelperDB.showDisenchant = false
    else
        DufforthTweaksHelperDB.showDisenchant = not Enabled()
    end
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. L["Disenchant advice in tooltips: "] .. (Enabled() and "ON" or "OFF") .. ".")
end
