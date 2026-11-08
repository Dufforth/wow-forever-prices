-- One menu for every feature, opened from the minimap button, /dufforth, or
-- the game's Options > AddOns. Changes go through the same commands as the slash
-- commands, so the menu and the commands always agree.

local PREFIX = "|cff66ccffDufforth AH Scanner:|r "
local ICON = "Interface\\Icons\\INV_Misc_Flower_02"
local ROW = 26

local function DB()
    DufforthAHScannerDB = DufforthAHScannerDB or {}
    return DufforthAHScannerDB
end
local function Nodes() return DB().nodes or {} end
local function NodesCommand(text) if SlashCmdList.DUFFORTHAHSCANNERNODES then SlashCmdList.DUFFORTHAHSCANNERNODES(text) end end

local menu
local refreshers = {}

local function RefreshMenu()
    for _, refresh in ipairs(refreshers) do refresh() end
    if DufforthAHScannerAutoDE and DufforthAHScannerAutoDE.Refresh then DufforthAHScannerAutoDE.Refresh() end
end

local function ShowTip(owner, text)
    if not text then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

-- ---- Controls ----
local function Header(parent, y, text)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 14, y)
    label:SetText(text)
    return y - 20
end

local function Check(parent, y, text, tip, get, set)
    local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    box:SetSize(24, 24)
    box:SetPoint("TOPLEFT", 16, y)
    local label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", box, "RIGHT", 4, 0)
    label:SetText(text)
    box:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); RefreshMenu() end)
    box:SetScript("OnEnter", function(self) ShowTip(self, tip) end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    refreshers[#refreshers + 1] = function() box:SetChecked(get() and true or false) end
    return y - ROW
end

-- A number with - and + buttons; sturdier than a slider across game versions.
local function Stepper(parent, y, text, tip, get, set, low, high, step, show)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", 22, y - 5)
    label:SetText(text)
    local plus = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    plus:SetSize(24, 20); plus:SetPoint("TOPRIGHT", -16, y - 1); plus:SetText("+")
    local value = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    value:SetPoint("RIGHT", plus, "LEFT", -6, 0); value:SetWidth(70); value:SetJustifyH("CENTER")
    local minus = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    minus:SetSize(24, 20); minus:SetPoint("RIGHT", value, "LEFT", -6, 0); minus:SetText("-")
    local function change(delta)
        local next = math.max(low, math.min(high, (get() or low) + delta))
        if next ~= get() then set(next); RefreshMenu() end
    end
    minus:SetScript("OnClick", function() change(-step) end)
    plus:SetScript("OnClick", function() change(step) end)
    for _, control in ipairs({ minus, plus }) do
        control:SetScript("OnEnter", function(self) ShowTip(self, tip) end)
        control:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    refreshers[#refreshers + 1] = function() value:SetText(show and show(get()) or tostring(get())) end
    return y - ROW
end

local function Button(parent, y, text, tip, onClick, x, width)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 150, 22)
    button:SetPoint("TOPLEFT", x or 20, y)
    button:SetText(text)
    button:SetScript("OnClick", function() onClick(button); RefreshMenu() end)
    button:SetScript("OnEnter", function(self) ShowTip(self, tip) end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

local function KeepCount()
    local count = 0
    for _ in pairs((DB().autoDE or {}).keep or {}) do count = count + 1 end
    return count
end

local function Build()
    menu = CreateFrame("Frame", "DufforthAHScannerMenu", UIParent, "BasicFrameTemplateWithInset")
    menu:SetSize(400, 540)
    menu:SetPoint("CENTER")
    menu:SetMovable(true); menu:EnableMouse(true); menu:RegisterForDrag("LeftButton")
    menu:SetScript("OnDragStart", menu.StartMoving)
    menu:SetScript("OnDragStop", menu.StopMovingOrSizing)
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:Hide()
    tinsert(UISpecialFrames, "DufforthAHScannerMenu") -- Escape closes it
    local title = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5)
    title:SetText("Dufforth AH Scanner")
    menu:SetScript("OnShow", RefreshMenu)

    local y = -32
    y = Header(menu, y, "Herbs and ores")
    y = Check(menu, y, "Herb and ore icons on the minimap", "Keeps herb and ore icons on the minimap when you swap tracking. Same as /nk on and /nk off.",
        function() return Nodes().enabled end, function(on) NodesCommand(on and "on" or "off") end)
    y = Check(menu, y, "Names beside icons", "Shows the herb or ore name next to each icon. Same as /nk names.",
        function() return Nodes().labels end, function(on) if (Nodes().labels and true or false) ~= on then NodesCommand("names") end end)
    y = Check(menu, y, "Swap tracking automatically", "Switches between Find Herbs and Find Minerals on a timer. Needs both Herbalism and Mining. Pauses in combat, in cities and inns, in instances, while dead, on flight paths and while stealthed.",
        function() return Nodes().swapEnabled end, function(on) NodesCommand(on and "swap on" or "swap off") end)
    y = Stepper(menu, y, "Swap every", "Seconds between tracking swaps.",
        function() return Nodes().swapSeconds end, function(v) NodesCommand("swap " .. v) end, 2, 60, 1, function(v) return (v or 0) .. " sec" end)
    y = Stepper(menu, y, "Icon size", "Size of the herb and ore icons.",
        function() return Nodes().size end, function(v) NodesCommand("size " .. v) end, 8, 28, 2)
    y = Stepper(menu, y, "Forget unseen icons after", "Icons you haven't seen again are removed after this long. 0 keeps them until you gather them.",
        function() return Nodes().keepMinutes end, function(v) NodesCommand("keep " .. v) end, 0, 240, 10, function(v) return v == 0 and "never" or (v .. " min") end)
    y = Stepper(menu, y, "Gathered markers last", "How long a 'gathered' marker stays where you picked a node. 0 turns them off.",
        function() return Nodes().gatheredMinutes end, function(v) NodesCommand("gathered " .. v) end, 0, 240, 10, function(v) return v == 0 and "off" or (v .. " min") end)
    Button(menu, y, "Clear all icons", "Removes every herb and ore icon and gathered marker.", function() NodesCommand("clear") end)
    y = y - ROW - 8

    y = Header(menu, y, "Disenchanting")
    y = Check(menu, y, "Disenchant values in item tooltips", "Adds the materials, their chances and prices, and the average value to weapon and armor tooltips. Same as /dufforth de.",
        function() return DB().showDisenchant ~= false end, function(on) DufforthAHScannerDE.Toggle(on and "on" or "off") end)
    local auto = DufforthAHScannerAutoDE
    y = Stepper(menu, y, "Disenchant up to", "The highest quality the disenchant window offers. Uncommon (green) is the safe default; epics need a deliberate choice.",
        function() return auto.Options().maxQuality end, function(v) auto.Options().maxQuality = v end, 2, 4, 1, function(v) return auto.QUALITY_NAMES[v] end)
    y = Stepper(menu, y, "Highest item level", "Items above this item level are never offered. 0 means any level.",
        function() return auto.Options().maxLevel end, function(v) auto.Options().maxLevel = v end, 0, 100, 5, function(v) return v == 0 and "any" or tostring(v) end)
    y = Check(menu, y, "Skip items that sell for more on the auction house", "Uses Blizzard's prices from your download: if the item's auction price, after the 5% cut, beats its disenchant value, it's kept.",
        function() return auto.Options().skipWorthMore end, function(on) auto.Options().skipWorthMore = on end)
    y = Check(menu, y, "Skip items a vendor pays more for", "If a vendor pays more than the disenchant value, the item is kept.",
        function() return auto.Options().skipVendor end, function(on) auto.Options().skipVendor = on end)
    Button(menu, y, "Open disenchant window", "Shows the next safe BoE item and a Disenchant button. One click per item. Same as /dufforth disenchant.", function() auto.Toggle() end)
    local clear = Button(menu, y, "Clear keep list", "Items you marked Keep in the disenchant window are never offered. This clears that list.", function()
        auto.Options().keep = {}
        DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. "keep list cleared.")
    end, 190, 150)
    refreshers[#refreshers + 1] = function() clear:SetText("Clear keep list (" .. KeepCount() .. ")") end
    y = y - ROW - 8

    y = Header(menu, y, "Minimap")
    y = Check(menu, y, "Show the minimap button", "Left-click opens this menu, right-click opens the disenchant window, drag moves it. If hidden, use /dufforth.",
        function() return not (DB().minimap or {}).hide end, function(on)
            DB().minimap = DB().minimap or {}
            DB().minimap.hide = not on
            if DufforthAHScannerMinimapButton then DufforthAHScannerMinimapButton:SetShown(on) end
        end)
end

local function ToggleMenu()
    if not menu then Build() end
    menu:SetShown(not menu:IsShown())
end

-- ---- Minimap button ----
local function PlaceButton(button)
    local angle = math.rad((DB().minimap or {}).angle or 200)
    local radius = (Minimap:GetWidth() / 2) + 10
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate(button)
    local x, y = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = Minimap:GetCenter()
    DB().minimap = DB().minimap or {}
    DB().minimap.angle = math.deg(math.atan2(y / scale - cy, x / scale - cx))
    PlaceButton(button)
end

local function State(on) return on and "|cff40ff40on|r" or "|cff999999off|r" end

local function ButtonTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Dufforth AH Scanner")
    GameTooltip:AddDoubleLine("Herb and ore icons", State(Nodes().enabled), 1, 1, 1)
    GameTooltip:AddDoubleLine("Tracking swap", State(Nodes().swapEnabled), 1, 1, 1)
    GameTooltip:AddDoubleLine("Disenchant tooltips", State(DB().showDisenchant ~= false), 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: menu   Right-click: disenchant window", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function BuildMinimapButton()
    local button = CreateFrame("Button", "DufforthAHScannerMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20); background:SetPoint("TOPLEFT", 7, -5)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17); icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture(ICON)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53); border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then DufforthAHScannerAutoDE.Toggle() else ToggleMenu() end
    end)
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnDragUpdate) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", ButtonTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    PlaceButton(button)
    button:SetShown(not (DB().minimap or {}).hide)
end

-- ---- Game options page: a pointer to the menu ----
local function RegisterOptions()
    local panel = CreateFrame("Frame")
    panel.name = "Dufforth AH Scanner"
    local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 16, -16)
    text:SetText("Every setting is in the Dufforth AH Scanner menu.")
    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(160, 24); open:SetPoint("TOPLEFT", 16, -40); open:SetText("Open the menu")
    open:SetScript("OnClick", function() if not menu or not menu:IsShown() then ToggleMenu() end end)
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(panel, panel.name))
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

DufforthAHScannerMenu_Toggle = ToggleMenu

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    BuildMinimapButton()
    RegisterOptions()
end)
