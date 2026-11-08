-- Disenchant BoE gear from your bags, one click (or key press) per item.
-- Blizzard only lets a spell be cast from a click or key press, so no addon can disenchant
-- by itself. This one finds the next safe item and puts it on one button, like other
-- disenchant addons do. Safety checks (guardrails), all on by default:
--   only unbound Bind on Equip weapons and armor; nothing already bound or not BoE;
--   nothing above your quality limit (Uncommon unless you change it) or item level limit;
--   nothing in an equipment set, on your keep list, or locked; nothing you lack the skill for;
--   nothing that sells for more on the auction house, or that a vendor pays more for;
--   if the game can't tell whether an item is bound, it's left alone; and nothing in combat.

local PREFIX = "|cff66ccffDufforth AH Scanner:|r "
local DISENCHANT = 13262
local BIND_ON_EQUIP = 2
local AUCTION_CUT = 0.05
local BAGS = { 0, 1, 2, 3, 4 }
local QUALITY_NAMES = { [2] = "Uncommon", [3] = "Rare", [4] = "Epic" }

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

-- Why an item must not be disenchanted, or nil if it's safe.
-- item: { id, quality, level, classID, slot, bindType, sellPrice, bound, locked, inSet, ahPrice }
local function Blocked(item, o, skill, value, need)
    if item.locked then return "in use" end
    if item.bound == nil then return "can't tell if it's bound" end
    if item.bound then return "already bound" end
    if item.bindType ~= BIND_ON_EQUIP then return "not Bind on Equip" end
    if not need then return "can't be disenchanted" end
    if item.quality > o.maxQuality then return "above your quality limit" end
    if o.maxLevel > 0 and (item.level or 0) > o.maxLevel then return "above your item level limit" end
    if o.keep[item.id] then return "on your keep list" end
    if item.inSet then return "in an equipment set" end
    if skill == false then return "you don't have Enchanting" end
    if skill and skill < need then return "needs Enchanting " .. need end
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

-- Every safe item, plus how many were held back and why.
local skipped = {} -- skipped this session with the Skip button
local function Candidates()
    local o = Options()
    local market = DufforthAHScanner and DufforthAHScanner.MarketName and DufforthAHScanner.MarketName() or ""
    local db, now = DufforthAHScannerDB, time()
    local skill = DufforthAHScannerDE.EnchantingSkill()
    local ready, held = {}, {}
    for _, bag in ipairs(BAGS) do
        for slot = 1, NumSlots(bag) do
            local item = ReadSlot(bag, slot)
            if item and DufforthAHScannerDE.Outcomes(item) and not skipped[item.id] then
                item.ahPrice = DufforthAHScannerDE.MaterialPrice(item.id, market, db, nil, now)
                item.value = DufforthAHScannerDE.ValueFor(item, market, db, DufforthAHScannerDEPrices, now)
                local reason = Blocked(item, o, skill, item.value, DufforthAHScannerDE.SkillNeeded(item))
                if reason then
                    held[reason] = (held[reason] or 0) + 1
                else
                    ready[#ready + 1] = item
                end
            end
        end
    end
    return ready, held
end

DufforthAHScannerAutoDE = { Blocked = Blocked, Options = Options, Candidates = Candidates, DEFAULTS = DEFAULTS, QUALITY_NAMES = QUALITY_NAMES }

-- ---- Window ----
local frame, castButton, current
local function SpellName()
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(DISENCHANT)
        return info and info.name or "Disenchant"
    end
    return (GetSpellInfo and GetSpellInfo(DISENCHANT)) or "Disenchant"
end

local function HeldText(held)
    local parts = {}
    for reason, count in pairs(held) do parts[#parts + 1] = count .. " " .. reason end
    table.sort(parts)
    return #parts > 0 and ("Kept back: " .. table.concat(parts, ", ")) or ""
end

local function Refresh()
    if not frame or not frame:IsShown() then return end
    if InCombatLockdown and InCombatLockdown() then
        frame.status:SetText("Paused in combat.")
        return
    end
    local ready, held = Candidates()
    current = ready[1]
    frame.held:SetText(HeldText(held))
    if current then
        frame.icon:SetTexture(current.icon)
        frame.name:SetText(current.name or ("Item " .. current.id))
        frame.value:SetText(current.value and ("Average value " .. DufforthAHScannerDE.Money(current.value)) or "No material prices yet")
        frame.status:SetText(#ready .. " ready to disenchant")
        castButton:SetAttribute("type", "spell")
        castButton:SetAttribute("spell", SpellName())
        castButton:SetAttribute("target-bag", current.bag)
        castButton:SetAttribute("target-slot", current.bagSlot)
        castButton:Enable()
        frame.skip:Enable(); frame.keepButton:Enable()
    else
        frame.icon:SetTexture(nil)
        frame.name:SetText("Nothing safe to disenchant")
        frame.value:SetText("")
        frame.status:SetText("")
        castButton:SetAttribute("type", nil)
        castButton:Disable()
        frame.skip:Disable(); frame.keepButton:Disable()
    end
end

local function Build()
    frame = CreateFrame("Frame", "DufforthAHScannerDEFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(300, 190)
    frame:SetPoint("CENTER", 260, 0)
    frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    tinsert(UISpecialFrames, "DufforthAHScannerDEFrame") -- Escape closes it
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", 0, -5)
    frame.title:SetText("Disenchant BoE gear")
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(36, 36); frame.icon:SetPoint("TOPLEFT", 14, -34)
    frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.name:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 8, -2); frame.name:SetWidth(230); frame.name:SetJustifyH("LEFT")
    frame.value = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.value:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, -4)
    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.status:SetPoint("TOPLEFT", 14, -78)
    frame.held = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.held:SetPoint("TOPLEFT", 14, -94); frame.held:SetWidth(272); frame.held:SetJustifyH("LEFT")
    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("BOTTOMLEFT", 14, 44); note:SetWidth(272); note:SetJustifyH("LEFT")
    note:SetText("One click per item: the game doesn't let addons cast on their own. Bind a key in Key Bindings > AddOns.")

    castButton = CreateFrame("Button", "DufforthAHScannerDEButton", frame, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    castButton:SetSize(120, 24); castButton:SetPoint("BOTTOMLEFT", 12, 12)
    castButton:SetText("Disenchant")
    castButton:RegisterForClicks("AnyUp", "AnyDown")
    frame.skip = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.skip:SetSize(70, 24); frame.skip:SetPoint("LEFT", castButton, "RIGHT", 6, 0); frame.skip:SetText("Skip")
    frame.skip:SetScript("OnClick", function() if current then skipped[current.id] = true end; Refresh() end)
    frame.keepButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.keepButton:SetSize(70, 24); frame.keepButton:SetPoint("LEFT", frame.skip, "RIGHT", 6, 0); frame.keepButton:SetText("Keep")
    frame.keepButton:SetScript("OnClick", function()
        if current then
            Options().keep[current.id] = true
            Print((current.name or "Item") .. " is on your keep list. Clear it in the menu.")
        end
        Refresh()
    end)

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

BINDING_HEADER_DUFFORTHAHSCANNER = "Dufforth AH Scanner"
_G["BINDING_NAME_CLICK DufforthAHScannerDEButton:LeftButton"] = "Disenchant the next BoE item"
