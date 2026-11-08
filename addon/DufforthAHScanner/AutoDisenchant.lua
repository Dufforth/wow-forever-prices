-- The disenchant list: every item in your bags that can be disenchanted, each with a
-- checkbox. One button disenchants the ticked items one after another.
--
-- Blizzard only lets a spell be cast from a click or key press, and Disenchant takes about
-- 3 seconds, so no addon can disenchant a whole list from one click. The button always
-- points at the next ticked item: click it (or press its key) again after each cast.
--
-- Safety checks (guardrails). Items that fail one start unticked, with the reason shown;
-- you can still tick them yourself:
--   soulbound or not Bind on Equip; above your quality limit (Uncommon unless you change it)
--   or item level limit; in an equipment set; on your keep list; sells for more on the
--   auction house or to a vendor; or the game can't tell whether it's bound.
-- Items that can't be ticked at all: locked (being moved or traded), or above your
-- Enchanting skill. Items the game won't disenchant never appear. Nothing changes in combat.

local PREFIX = "|cff66ccffDufforth AH Scanner:|r "
local DISENCHANT = 13262
local BIND_ON_EQUIP = 2
local AUCTION_CUT = 0.05
local BAGS = { 0, 1, 2, 3, 4 }
local QUALITY_NAMES = { [2] = "Uncommon", [3] = "Rare", [4] = "Epic" }
local ROW_HEIGHT, VISIBLE_ROWS = 24, 10

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. message)
end

-- Settings live in DufforthAHScannerDB.autoDE.
local DEFAULTS = { maxQuality = 2, maxLevel = 0, skipWorthMore = true, skipVendor = true }
local function Options()
    DufforthAHScannerDB = DufforthAHScannerDB or {}
    local o = DufforthAHScannerDB.autoDE or {}
    DufforthAHScannerDB.autoDE = o
    for key, value in pairs(DEFAULTS) do
        if o[key] == nil then o[key] = value end
    end
    o.keep = o.keep or {}
    return o
end

-- Why an item shouldn't be disenchanted, and whether that's final.
-- Returns nil (fine), or reason and hard (true: it can't be ticked at all).
-- item: { id, quality, level, bindType, sellPrice, bound, locked, inSet, ahPrice }
local function Classify(item, o, skill, value, need)
    if not need then return "can't be disenchanted", true end
    if item.locked then return "in use", true end
    if skill == false then return "you don't have Enchanting", true end
    if skill and skill < need then return "needs Enchanting " .. need, true end
    if o.keep[item.id] then return "on your keep list" end
    if item.bound == nil then return "can't tell if it's bound" end
    if item.bound then return "soulbound" end
    if item.bindType ~= BIND_ON_EQUIP then return "not Bind on Equip" end
    if item.quality > o.maxQuality then return "above your quality limit" end
    if o.maxLevel > 0 and (item.level or 0) > o.maxLevel then return "above your item level limit" end
    if item.inSet then return "in an equipment set" end
    if o.skipWorthMore and value and item.ahPrice and item.ahPrice * (1 - AUCTION_CUT) > value then
        return "sells for more on the auction house"
    end
    if o.skipVendor and value and item.sellPrice and item.sellPrice > value then return "a vendor pays more" end
end

-- ---- Reading your bags ----
local function NumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) end
    return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end

local function IsBound(bag, slot, info)
    if info and info.isBound ~= nil then return info.isBound end
    if C_Item and C_Item.IsBound and ItemLocation and ItemLocation.CreateFromBagAndSlot then
        local ok, bound = pcall(C_Item.IsBound, ItemLocation:CreateFromBagAndSlot(bag, slot))
        if ok then return bound end
    end
    return nil
end

local function InSet(bag, slot)
    if C_Container and C_Container.GetContainerItemEquipmentSetInfo then
        return C_Container.GetContainerItemEquipmentSetInfo(bag, slot) == true
    end
    return false
end

local function ReadSlot(bag, slot)
    local id, locked, info
    if C_Container and C_Container.GetContainerItemInfo then
        info = C_Container.GetContainerItemInfo(bag, slot)
        if not info then return nil end
        id, locked = info.itemID, info.isLocked
    elseif GetContainerItemInfo then
        local _, _, isLocked, _, _, _, _, _, _, itemID = GetContainerItemInfo(bag, slot)
        id, locked = itemID, isLocked
    end
    local item = id and DufforthAHScannerDE.ItemFromID(id)
    if not item then return nil end
    item.bag, item.bagSlot, item.locked = bag, slot, locked
    item.bound = IsBound(bag, slot, info)
    item.inSet = InSet(bag, slot)
    return item
end

-- Your ticks and unticks for this session, by item ID: true, false, or nil (use the default).
local choice = {}

local function IsSelected(row)
    if row.hard then return false end
    local picked = choice[row.item.id]
    if picked == nil then return row.reason == nil end
    return picked
end

-- Every item in your bags that can be disenchanted, in bag order, with its reason if any.
local function Rows()
    local o = Options()
    local market = DufforthAHScanner and DufforthAHScanner.MarketName and DufforthAHScanner.MarketName() or ""
    local skill = DufforthAHScannerDE.EnchantingSkill()
    local rows = {}
    for _, bag in ipairs(BAGS) do
        for slot = 1, NumSlots(bag) do
            local item = ReadSlot(bag, slot)
            if item and DufforthAHScannerDE.Outcomes(item) then
                item.ahPrice = DufforthAHScannerDE.Price(item.id, market, DufforthAHScannerPrices)
                item.value = DufforthAHScannerDE.ValueFor(item, market, DufforthAHScannerPrices)
                local reason, hard = Classify(item, o, skill, item.value, DufforthAHScannerDE.SkillNeeded(item))
                rows[#rows + 1] = { item = item, reason = reason, hard = hard }
            end
        end
    end
    return rows
end

DufforthAHScannerAutoDE = { Classify = Classify, Options = Options, Rows = Rows, IsSelected = IsSelected, DEFAULTS = DEFAULTS, QUALITY_NAMES = QUALITY_NAMES, choice = choice }

-- ---- Window ----
local frame, castButton, rowFrames = nil, nil, {}
local rows, offset = {}, 0

local function SpellName()
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(DISENCHANT)
        return info and info.name or "Disenchant"
    end
    return (GetSpellInfo and GetSpellInfo(DISENCHANT)) or "Disenchant"
end

local function QualityColor(quality)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    return c and c.hex or "|cffffffff"
end

local function DrawRows()
    for i, line in ipairs(rowFrames) do
        local row = rows[i + offset]
        line:SetShown(row ~= nil)
        if row then
            line.row = row
            line.icon:SetTexture(row.item.icon)
            line.name:SetText(QualityColor(row.item.quality) .. (row.item.name or ("Item " .. row.item.id)) .. "|r")
            line.check:SetChecked(IsSelected(row))
            line.check:SetEnabled(not row.hard)
            local value = row.item.value and DufforthAHScannerDE.Money(row.item.value) or "no price"
            line.detail:SetText(row.reason and ("|cff999999" .. row.reason .. "|r") or value)
        end
    end
    frame.scrollUp:SetEnabled(offset > 0)
    frame.scrollDown:SetEnabled(offset + VISIBLE_ROWS < #rows)
end

local function Refresh()
    if not frame or not frame:IsShown() then return end
    if InCombatLockdown and InCombatLockdown() then
        frame.status:SetText("Paused in combat.")
        return
    end
    rows = Rows()
    offset = math.max(0, math.min(offset, #rows - VISIBLE_ROWS))
    local next, count, total = nil, 0, 0
    for _, row in ipairs(rows) do
        if IsSelected(row) then
            count = count + 1
            total = total + (row.item.value or 0)
            next = next or row
        end
    end
    DrawRows()
    if #rows == 0 then
        frame.status:SetText("Nothing in your bags can be disenchanted.")
    else
        frame.status:SetText(string.format("%d of %d ticked · about %s", count, #rows, DufforthAHScannerDE.Money(total)))
    end
    if next then
        castButton:SetAttribute("type", "spell")
        castButton:SetAttribute("spell", SpellName())
        castButton:SetAttribute("target-bag", next.item.bag)
        castButton:SetAttribute("target-slot", next.item.bagSlot)
        castButton:SetText("Disenchant next (" .. count .. ")")
        castButton:Enable()
    else
        castButton:SetAttribute("type", nil)
        castButton:SetText("Disenchant next")
        castButton:Disable()
    end
end

local function SetAll(on)
    for _, row in ipairs(rows) do
        if not row.hard then choice[row.item.id] = on end
    end
    Refresh()
end

local function BuildRow(index)
    local line = CreateFrame("Button", nil, frame)
    line:SetSize(330, ROW_HEIGHT)
    line:SetPoint("TOPLEFT", 12, -56 - (index - 1) * ROW_HEIGHT)
    line:RegisterForClicks("RightButtonUp")
    line.check = CreateFrame("CheckButton", nil, line, "UICheckButtonTemplate")
    line.check:SetSize(22, 22); line.check:SetPoint("LEFT", 0, 0)
    line.check:SetScript("OnClick", function(self)
        if line.row then choice[line.row.item.id] = self:GetChecked() and true or false end
        Refresh()
    end)
    line.icon = line:CreateTexture(nil, "ARTWORK")
    line.icon:SetSize(20, 20); line.icon:SetPoint("LEFT", line.check, "RIGHT", 2, 0)
    line.name = line:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    line.name:SetPoint("LEFT", line.icon, "RIGHT", 6, 0); line.name:SetWidth(160); line.name:SetJustifyH("LEFT")
    line.detail = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line.detail:SetPoint("RIGHT", -4, 0); line.detail:SetWidth(120); line.detail:SetJustifyH("RIGHT")
    -- Right-click adds or removes the item from your keep list for good.
    line:SetScript("OnClick", function()
        if not line.row then return end
        local keep, id = Options().keep, line.row.item.id
        keep[id] = not keep[id] or nil
        choice[id] = nil
        Print((line.row.item.name or "Item") .. (keep[id] and " is on your keep list." or " is off your keep list."))
        Refresh()
    end)
    line:SetScript("OnEnter", function(self)
        if not self.row then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetBagItem then GameTooltip:SetBagItem(self.row.item.bag, self.row.item.bagSlot) end
        GameTooltip:AddLine("Right-click: always keep / stop keeping", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    line:SetScript("OnLeave", function() GameTooltip:Hide() end)
    line:EnableMouseWheel(true)
    line:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, math.min(offset - delta, #rows - VISIBLE_ROWS))
        DrawRows()
    end)
    return line
end

local function SmallButton(text, width, onClick)
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(width, 20)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function Build()
    frame = CreateFrame("Frame", "DufforthAHScannerDEFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(360, 56 + VISIBLE_ROWS * ROW_HEIGHT + 86)
    frame:SetPoint("CENTER", 260, 0)
    frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:Hide()
    tinsert(UISpecialFrames, "DufforthAHScannerDEFrame") -- Escape closes it
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", 0, -5)
    frame.title:SetText("Disenchant from your bags")

    local all = SmallButton("Tick all", 70, function() SetAll(true) end)
    all:SetPoint("TOPLEFT", 12, -30)
    local none = SmallButton("Untick all", 80, function() SetAll(false) end)
    none:SetPoint("LEFT", all, "RIGHT", 4, 0)
    frame.scrollUp = SmallButton("▲", 26, function() offset = math.max(0, offset - VISIBLE_ROWS); DrawRows() end)
    frame.scrollUp:SetPoint("TOPRIGHT", -42, -30)
    frame.scrollDown = SmallButton("▼", 26, function() offset = math.min(offset + VISIBLE_ROWS, math.max(0, #rows - VISIBLE_ROWS)); DrawRows() end)
    frame.scrollDown:SetPoint("LEFT", frame.scrollUp, "RIGHT", 2, 0)

    for i = 1, VISIBLE_ROWS do rowFrames[i] = BuildRow(i) end

    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.status:SetPoint("BOTTOMLEFT", 14, 66)
    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("BOTTOMLEFT", 14, 40); note:SetWidth(332); note:SetJustifyH("LEFT")
    note:SetText("The game allows one disenchant per click: press the button (or its key, under Key Bindings > AddOns) after each cast.")

    castButton = CreateFrame("Button", "DufforthAHScannerDEButton", frame, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    castButton:SetSize(200, 24); castButton:SetPoint("BOTTOM", 0, 12)
    castButton:SetText("Disenchant next")
    castButton:RegisterForClicks("AnyUp", "AnyDown")

    frame:SetScript("OnShow", Refresh)
    frame:RegisterEvent("BAG_UPDATE_DELAYED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED") -- the last moment the window may still be hidden
    frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    frame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    frame:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_REGEN_DISABLED" then frame:Hide(); return end
        if (event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_INTERRUPTED") and unit ~= "player" then return end
        if C_Timer then C_Timer.After(0.3, Refresh) else Refresh() end
    end)
end

function DufforthAHScannerAutoDE.Toggle()
    if InCombatLockdown and InCombatLockdown() then
        Print("the disenchant window can't open in combat.")
        return
    end
    if not frame then Build() end
    frame:SetShown(not frame:IsShown())
end

DufforthAHScannerAutoDE.Refresh = Refresh
DufforthAHScannerAutoDE.SetAll = SetAll

BINDING_HEADER_DUFFORTHAHSCANNER = "Dufforth AH Scanner"
_G["BINDING_NAME_CLICK DufforthAHScannerDEButton:LeftButton"] = "Disenchant the next ticked item"
