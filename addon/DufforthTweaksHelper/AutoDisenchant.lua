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

local L = DufforthTweaksHelperL or setmetatable({}, { __index = function(_, k) return k end })
local PREFIX = L["|cff66ccffDufforth Tweaks Helper:|r "]
local DISENCHANT = 13262
local BIND_ON_EQUIP = 2
local AUCTION_CUT = 0.05
local BAGS = { 0, 1, 2, 3, 4 }
local QUALITY_NAMES = { [2] = L["Uncommon"], [3] = L["Rare"], [4] = L["Epic"] }
local ROW_HEIGHT, VISIBLE_ROWS = 24, 10

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. message)
end

-- Settings live in DufforthTweaksHelperDB.autoDE.
local DEFAULTS = { maxQuality = 2, maxLevel = 0, skipWorthMore = true, skipVendor = true }
local function Options()
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    local o = DufforthTweaksHelperDB.autoDE or {}
    DufforthTweaksHelperDB.autoDE = o
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
    if not need then return L["can't be disenchanted"], true end
    if item.locked then return L["in use"], true end
    if skill == false then return L["you don't have Enchanting"], true end
    if skill and skill < need then return L["needs Enchanting "] .. need, true end
    if o.keep[item.id] then return L["on your keep list"] end
    if item.bound == nil then return L["can't tell if it's bound"] end
    if item.bound then return "soulbound" end
    if item.bindType ~= BIND_ON_EQUIP then return L["not Bind on Equip"] end
    if item.quality > o.maxQuality then return L["above your quality limit"] end
    if o.maxLevel > 0 and (item.level or 0) > o.maxLevel then return L["above your item level limit"] end
    if item.inSet then return L["in an equipment set"] end
    if o.skipWorthMore and value and item.ahPrice and item.ahPrice * (1 - AUCTION_CUT) > value then
        return L["sells for more on the auction house"]
    end
    if o.skipVendor and value and item.sellPrice and item.sellPrice > value then return L["a vendor pays more"] end
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
    local item = id and DufforthTweaksHelperDE.ItemFromID(id)
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
    local market = DufforthTweaksHelper and DufforthTweaksHelper.MarketName and DufforthTweaksHelper.MarketName() or ""
    local skill = DufforthTweaksHelperDE.EnchantingSkill()
    local rows = {}
    for _, bag in ipairs(BAGS) do
        for slot = 1, NumSlots(bag) do
            local item = ReadSlot(bag, slot)
            if item and DufforthTweaksHelperDE.Outcomes(item) then
                item.ahPrice = DufforthTweaksHelperDE.Price(item.id, market, DufforthTweaksHelperPrices)
                item.value = DufforthTweaksHelperDE.ValueFor(item, market, DufforthTweaksHelperPrices)
                local reason, hard = Classify(item, o, skill, item.value, DufforthTweaksHelperDE.SkillNeeded(item))
                rows[#rows + 1] = { item = item, reason = reason, hard = hard }
            end
        end
    end
    return rows
end

-- ---- Totals for everything ticked: materials and time ----
-- Each disenchant: the 3 s cast plus looting and your next click. Learned from your own pace.
local SECONDS_PER_DE = 4.5

local function SecondsPerDE()
    local learned = Options().secondsPerDE
    return (type(learned) == "number" and learned >= 3 and learned <= 15) and learned or SECONDS_PER_DE
end

-- { count, value, unpriced, seconds, mats = { {id, amount, each, value}, ... } (most valuable first) }.
-- Amounts are averages: chance x the middle of each material's range.
local function Summary(rows, isSelected, secondsEach, market, shipped)
    local DE = DufforthTweaksHelperDE
    local s, byId = { count = 0, value = 0, unpriced = 0, mats = {} }, {}
    for _, row in ipairs(rows) do
        if isSelected(row) then
            s.count = s.count + 1
            if row.item.value then s.value = s.value + row.item.value else s.unpriced = s.unpriced + 1 end
            for _, o in ipairs(DE.Outcomes(row.item) or {}) do
                if o.chance > 0 then
                    local m = byId[o.id]
                    if not m then
                        m = { id = o.id, amount = 0 }
                        byId[o.id] = m
                        s.mats[#s.mats + 1] = m
                    end
                    m.amount = m.amount + o.chance * (o.min + o.max) / 2
                end
            end
        end
    end
    for _, m in ipairs(s.mats) do
        local price = DE.Price(m.id, market, shipped)
        m.each = price and price * (1 - (DE.AUCTION_CUT or 0.05)) or nil
        m.value = m.each and m.each * m.amount or nil
    end
    table.sort(s.mats, function(a, b) return (a.value or -1) > (b.value or -1) end)
    s.seconds = s.count * secondsEach
    return s
end

local function Duration(seconds)
    if DufforthTweaksHelperLeveling and DufforthTweaksHelperLeveling.Duration then return DufforthTweaksHelperLeveling.Duration(seconds) end
    return math.floor(seconds + 0.5) .. "s"
end

DufforthTweaksHelperAutoDE = { Summary = Summary, SecondsPerDE = SecondsPerDE, Classify = Classify, Options = Options, Rows = Rows, IsSelected = IsSelected, DEFAULTS = DEFAULTS, QUALITY_NAMES = QUALITY_NAMES, choice = choice }

-- ---- Where the window opens ----
-- Its own window, never on top of the menu (user screenshot: it covered the Settings view).
-- menu: { left, top, right, bottom } of the open menu or nil; saved: { left, top } or nil.
-- Screen coordinates start bottom left. Returns the window's left and top.
local GAP = 8
local function Overlaps(aLeft, aTop, w, h, b)
    return aLeft < b.right and aLeft + w > b.left and aTop > b.bottom and aTop - h < b.top
end

local function Place(menu, w, h, screenW, screenH, saved)
    if saved and saved.left and saved.top and saved.left >= 0 and saved.left + w <= screenW and saved.top <= screenH and saved.top - h >= 0
        and not (menu and Overlaps(saved.left, saved.top, w, h, menu)) then
        return saved.left, saved.top
    end
    if menu and menu.left and menu.right and menu.top then
        local top = math.max(h, math.min(menu.top, screenH))
        if menu.right + GAP + w <= screenW then return menu.right + GAP, top end
        if menu.left - GAP - w >= 0 then return menu.left - GAP - w, top end
        -- No room on either side: the side with more room, kept on the screen.
        if screenW - menu.right >= menu.left then return screenW - w, top end
        return 0, top
    end
    return math.floor((screenW - w) / 2), math.floor((screenH + h) / 2)
end
DufforthTweaksHelperAutoDE.Place = Place

-- ---- Window ----
local WIDTH = 360
local HEIGHT = 56 + VISIBLE_ROWS * ROW_HEIGHT + 86
local WHITE = "Interface\\Buttons\\WHITE8x8"
local frame, castButton, rowFrames = nil, nil, {}
local rows, offset = {}, 0
local summary -- the totals shown on the status line and in its hover

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

local function ShowTip(owner, text)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

-- Flat look, like the menu: a dark fill and a light highlight.
local function Skin(b)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints(); b.bg:SetColorTexture(0.18, 0.18, 0.2, 0.95)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.12)
    b:SetNormalFontObject("GameFontHighlightSmall")
    if b.SetDisabledFontObject then b:SetDisabledFontObject("GameFontDisableSmall") end
end

local function Flat(text, width, height, onClick, tip)
    local b = CreateFrame("Button", nil, frame)
    b:SetSize(width, height or 18)
    Skin(b)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    if tip then
        b:SetScript("OnEnter", function(self) ShowTip(self, tip) end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return b
end

local function DrawRows()
    for i, line in ipairs(rowFrames) do
        local row = rows[i + offset]
        line:SetShown(row ~= nil)
        if row then
            line.row = row
            line.icon:SetTexture(row.item.icon)
            line.name:SetText(QualityColor(row.item.quality) .. (row.item.name or (L["Item "] .. row.item.id)) .. "|r")
            line.check:SetChecked(IsSelected(row))
            line.check:SetEnabled(not row.hard)
            local value = row.item.value and DufforthTweaksHelperDE.Money(row.item.value) or L["no price"]
            line.detail:SetText(row.reason and ("|cff999999" .. row.reason .. "|r") or value)
        end
    end
    frame.scrollUp:SetEnabled(offset > 0)
    frame.scrollDown:SetEnabled(offset + VISIBLE_ROWS < #rows)
end

local function Refresh()
    if not frame or not frame:IsShown() then return end
    if InCombatLockdown and InCombatLockdown() then
        frame.status:SetText(L["Paused in combat."])
        return
    end
    rows = Rows()
    offset = math.max(0, math.min(offset, #rows - VISIBLE_ROWS))
    local next = nil
    for _, row in ipairs(rows) do
        if IsSelected(row) then next = next or row end
    end
    local market = DufforthTweaksHelper and DufforthTweaksHelper.MarketName and DufforthTweaksHelper.MarketName() or ""
    summary = Summary(rows, IsSelected, SecondsPerDE(), market, DufforthTweaksHelperPrices)
    local count = summary.count
    DrawRows()
    if #rows == 0 then
        frame.status:SetText(L["Nothing in your bags can be disenchanted."])
    elseif count == 0 then
        frame.status:SetText(string.format(L["0 of %d ticked."], #rows))
    else
        frame.status:SetText(string.format(L["%d of %d ticked: about %s of materials, about %s. Hover for details."], count, #rows,
            DufforthTweaksHelperDE.Money(summary.value), Duration(summary.seconds)))
    end
    if next then
        castButton:SetAttribute("type", "spell")
        castButton:SetAttribute("spell", SpellName())
        castButton:SetAttribute("target-bag", next.item.bag)
        castButton:SetAttribute("target-slot", next.item.bagSlot)
        castButton:SetText(L["Disenchant next ("] .. count .. ")")
        castButton:Enable()
        castButton.bg:SetColorTexture(0.12, 0.45, 0.2, 0.95)
    else
        castButton:SetAttribute("type", nil)
        castButton:SetText(L["Disenchant next"])
        castButton:Disable()
        castButton.bg:SetColorTexture(0.18, 0.18, 0.2, 0.95)
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
    line:SetSize(WIDTH - 24, ROW_HEIGHT)
    line:SetPoint("TOPLEFT", 12, -56 - (index - 1) * ROW_HEIGHT)
    line:RegisterForClicks("RightButtonUp")
    line.hl = line:CreateTexture(nil, "HIGHLIGHT")
    line.hl:SetAllPoints(); line.hl:SetColorTexture(1, 1, 1, 0.06)
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
    if line.name.SetWordWrap then line.name:SetWordWrap(false) end
    line.detail = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line.detail:SetPoint("RIGHT", -4, 0); line.detail:SetWidth(120); line.detail:SetJustifyH("RIGHT")
    if line.detail.SetWordWrap then line.detail:SetWordWrap(false) end
    -- Right-click adds or removes the item from your keep list for good.
    line:SetScript("OnClick", function()
        if not line.row then return end
        local keep, id = Options().keep, line.row.item.id
        keep[id] = not keep[id] or nil
        choice[id] = nil
        Refresh()
    end)
    line:SetScript("OnEnter", function(self)
        if not self.row then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetBagItem then GameTooltip:SetBagItem(self.row.item.bag, self.row.item.bagSlot) end
        local keep = Options().keep[self.row.item.id]
        GameTooltip:AddLine(keep and L["On your keep list. Right-click: stop keeping"] or L["Right-click: always keep / stop keeping"], 0.7, 0.7, 0.7)
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

local function SavePosition()
    local left, top = frame:GetLeft(), frame:GetTop()
    if left and top then Options().pos = { left = math.floor(left + 0.5), top = math.floor(top + 0.5) } end
end

local function MenuRect()
    local menu = DufforthTweaksHelperMenu
    if not (menu and menu.IsShown and menu:IsShown()) then return nil end
    local left, top, right, bottom = menu:GetLeft(), menu:GetTop(), menu:GetRight(), menu:GetBottom()
    if not (left and top and right and bottom) then return nil end
    return { left = left, top = top, right = right, bottom = bottom }
end

local function Position()
    local screenW = UIParent.GetWidth and UIParent:GetWidth() or 1920
    local screenH = UIParent.GetHeight and UIParent:GetHeight() or 1080
    local left, top = Place(MenuRect(), WIDTH, HEIGHT, screenW or 1920, screenH or 1080, Options().pos)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

local function Build()
    frame = CreateFrame("Frame", "DufforthTweaksHelperDEFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    if frame.SetBackdrop then
        frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        frame:SetBackdropColor(0.05, 0.05, 0.06, 0.97); frame:SetBackdropBorderColor(0, 0, 0, 1)
    end
    frame:SetPoint("CENTER")
    frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
    if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end -- our own saved spot, not the game's layout cache
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true) -- a click brings it above the menu
    frame:SetClampedToScreen(true)
    frame:Hide()
    tinsert(UISpecialFrames, "DufforthTweaksHelperDEFrame") -- Escape closes it

    -- Top strip with the title and X, like the menu.
    local strip = frame:CreateTexture(nil, "BORDER")
    strip:SetPoint("TOPLEFT", 1, -1); strip:SetPoint("TOPRIGHT", -1, -1); strip:SetHeight(24)
    strip:SetColorTexture(0, 0, 0, 0.85)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", 10, -6)
    frame.title:SetText(L["Disenchant list"])
    local close = Flat("X", 20, 18, function() frame:Hide() end, L["Close (Esc). Drag the window to move it; it opens there next time."])
    close:SetPoint("TOPRIGHT", -4, -4)

    local all = Flat(L["Tick all"], 70, 18, function() SetAll(true) end)
    all:SetPoint("TOPLEFT", 12, -31)
    local none = Flat(L["Untick all"], 80, 18, function() SetAll(false) end)
    none:SetPoint("LEFT", all, "RIGHT", 4, 0)
    frame.scrollUp = DufforthTweaksHelper.ArrowButton(frame, "up", function() offset = math.max(0, offset - VISIBLE_ROWS); DrawRows() end)
    frame.scrollUp:SetPoint("TOPRIGHT", -36, -29)
    frame.scrollDown = DufforthTweaksHelper.ArrowButton(frame, "down", function() offset = math.min(offset + VISIBLE_ROWS, math.max(0, #rows - VISIBLE_ROWS)); DrawRows() end)
    frame.scrollDown:SetPoint("LEFT", frame.scrollUp, "RIGHT", 4, 0)

    for i = 1, VISIBLE_ROWS do rowFrames[i] = BuildRow(i) end

    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.status:SetPoint("BOTTOMLEFT", 14, 66); frame.status:SetWidth(WIDTH - 28); frame.status:SetJustifyH("LEFT")
    if frame.status.SetWordWrap then frame.status:SetWordWrap(false) end
    -- Hovering the totals: time, and each material you can expect with its value.
    frame.statusHover = CreateFrame("Frame", nil, frame)
    frame.statusHover:SetPoint("BOTTOMLEFT", 10, 60); frame.statusHover:SetSize(WIDTH - 20, 20)
    frame.statusHover:EnableMouse(true)
    frame.statusHover:SetScript("OnEnter", function(self) DufforthTweaksHelperAutoDE.ShowSummary(self) end)
    frame.statusHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("BOTTOMLEFT", 14, 40); note:SetWidth(WIDTH - 28); note:SetJustifyH("LEFT")
    note:SetText(L["The game allows one disenchant per click: press the button (or its key, under Key Bindings > AddOns) after each cast."])

    -- Secure, so the click can cast; flat like the rest. Both mouse down and up are registered
    -- so it works whatever "cast on key down" is set to on that PC.
    castButton = CreateFrame("Button", "DufforthTweaksHelperDEButton", frame, "SecureActionButtonTemplate")
    castButton:SetSize(200, 24); castButton:SetPoint("BOTTOM", 0, 12)
    Skin(castButton)
    castButton:SetText(L["Disenchant next"])
    castButton:RegisterForClicks("AnyUp", "AnyDown")

    frame:SetScript("OnShow", Refresh)
    for _, event in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "UNIT_SPELLCAST_SUCCEEDED",
        "UNIT_SPELLCAST_INTERRUPTED", "GET_ITEM_INFO_RECEIVED" }) do
        pcall(frame.RegisterEvent, frame, event) -- an event this client lacks must not stop the rest
    end
    local pending = false
    frame:SetScript("OnEvent", function(_, event, unit, _, spell)
        if event == "PLAYER_REGEN_DISABLED" then frame:Hide(); return end -- the last moment the window may still be hidden
        if (event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_INTERRUPTED") and unit ~= "player" then return end
        if event == "UNIT_SPELLCAST_SUCCEEDED" and spell == DISENCHANT then DufforthTweaksHelperAutoDE.LearnPace(GetTime and GetTime() or 0) end
        if event == "GET_ITEM_INFO_RECEIVED" and not frame:IsShown() then return end
        if not C_Timer then Refresh(); return end
        if pending then return end -- many item loads at once: one refresh
        pending = true
        C_Timer.After(0.3, function() pending = false; Refresh() end)
    end)
end

function DufforthTweaksHelperAutoDE.Toggle()
    if InCombatLockdown and InCombatLockdown() then
        local message = L["The disenchant list can't open in combat."]
        if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(message, 1, 0.3, 0.3) else Print(message) end
        return
    end
    if not frame then Build() end
    if frame:IsShown() then frame:Hide(); return end
    Position()
    frame:Show()
end

DufforthTweaksHelperAutoDE.Refresh = Refresh

-- Your own pace: the time between two disenchants in a row (under 20 s), smoothed.
local lastDE
function DufforthTweaksHelperAutoDE.LearnPace(now)
    if lastDE and now - lastDE > 0 and now - lastDE < 20 then
        local o = Options()
        o.secondsPerDE = 0.7 * SecondsPerDE() + 0.3 * (now - lastDE)
    end
    lastDE = now
end

function DufforthTweaksHelperAutoDE.ShowSummary(owner)
    local s = summary
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    if not s or s.count == 0 then
        GameTooltip:SetText(L["Tick items to see the time and the materials you'd get."], 1, 1, 1, 1, true)
        GameTooltip:Show()
        return
    end
    local DE = DufforthTweaksHelperDE
    GameTooltip:AddLine(string.format(L["Disenchanting %d items"], s.count), 1, 0.82, 0)
    GameTooltip:AddDoubleLine(L["Time"], L["about "] .. Duration(s.seconds), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddLine(string.format(L["%.1f s each: the cast, looting and your next click (learned from your pace)."], SecondsPerDE()), 0.6, 0.6, 0.6, true)
    GameTooltip:AddLine(L["Materials you can expect (averages)"], 0.45, 0.8, 1)
    for _, m in ipairs(s.mats) do
        GameTooltip:AddDoubleLine(string.format(L["    %.1fx %s"], m.amount, DE.MaterialName(m.id)), m.value and DE.Money(m.value) or L["no price"], 0.8, 0.8, 0.8, 1, 1, 1)
    end
    GameTooltip:AddDoubleLine(L["Total, after the 5% auction cut"], DE.Money(s.value), 1, 0.82, 0, 1, 1, 1)
    if s.unpriced > 0 then GameTooltip:AddLine(string.format(L["%d items have materials without a price and aren't in the total."], s.unpriced), 1, 0.5, 0.25, true) end
    GameTooltip:AddLine(L["Each disenchant is random: real amounts vary."], 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end
DufforthTweaksHelperAutoDE.SetAll = SetAll

BINDING_HEADER_DUFFORTHTWEAKSHELPER = "Dufforth Tweaks Helper"
_G["BINDING_NAME_CLICK DufforthTweaksHelperDEButton:LeftButton"] = L["Disenchant the next ticked item"]
