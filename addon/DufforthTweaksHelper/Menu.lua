-- One window with a tab per feature (Gather, Disenchant, Crafting, Warrior), opened from the
-- minimap button, /dufforth, or the game's Options > AddOns. Changes go through the same
-- commands as the slash commands, so the window and the commands always agree.

local PREFIX = "|cff66ccffDufforth Tweaks Helper:|r "
local ICON = "Interface\\Icons\\INV_Misc_QuestionMark" -- a question mark: help
local ROW = 26
-- The last tab is your class (named after it): consumables for everyone, the macro for warriors.
local TABS = { "Gather", "Disenchant", "Crafting", "Leveling", "Zone", "Class" }
-- Tabs in one slim row on top: side tabs took too much room (user, 2026-11-13). 560 wide so six
-- names fit (at 500, "Disenchant" spilled out of its tab).
local WIDTH, HEIGHT = 560, 560
local PAGE_WIDTH = WIDTH - 16
local MIN_HEIGHT, MAX_HEIGHT = 460, 1000

local function DB()
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    return DufforthTweaksHelperDB
end
local function Nodes() return DB().nodes or {} end
local function NodesCommand(text) if SlashCmdList.DUFFORTHTWEAKSHELPERNODES then SlashCmdList.DUFFORTHTWEAKSHELPERNODES(text) end end

local menu
local refreshers = {}
local pages, tabButtons = {}, {}

local function RefreshMenu()
    for _, refresh in ipairs(refreshers) do refresh() end
    if DufforthTweaksHelperAutoDE and DufforthTweaksHelperAutoDE.Refresh then DufforthTweaksHelperAutoDE.Refresh() end
    if DufforthTweaksHelperCrafting and DufforthTweaksHelperCrafting.Refresh then DufforthTweaksHelperCrafting.Refresh() end
    if DufforthTweaksHelperConsumables and DufforthTweaksHelperConsumables.Refresh then DufforthTweaksHelperConsumables.Refresh() end
    if DufforthTweaksHelperZone and DufforthTweaksHelperZone.Refresh then DufforthTweaksHelperZone.Refresh() end
    if DufforthTweaksHelperGear and DufforthTweaksHelperGear.Refresh then pcall(DufforthTweaksHelperGear.Refresh) end
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
    label:SetPoint("TOPLEFT", 8, y)
    label:SetText(text)
    return y - 20
end

local function Check(parent, y, text, tip, get, set)
    local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    box:SetSize(24, 24)
    box:SetPoint("TOPLEFT", 10, y)
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
    label:SetPoint("TOPLEFT", 16, y - 5)
    label:SetText(text)
    local plus = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    plus:SetSize(24, 20); plus:SetPoint("TOPRIGHT", -10, y - 1); plus:SetText("+")
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
    button:SetPoint("TOPLEFT", x or 14, y)
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

-- ---- Tabs ----
local function ShowTab(name)
    for _, tab in ipairs(TABS) do
        if pages[tab] then pages[tab]:SetShown(tab == name) end
        if tabButtons[tab] then tabButtons[tab]:SetEnabled(tab ~= name) end -- the open tab looks pressed
    end
    DB().menuTab = name
    RefreshMenu()
end

local function Page(name)
    local page = CreateFrame("Frame", nil, menu)
    page:SetPoint("TOPLEFT", 8, -56)
    page:SetPoint("BOTTOMRIGHT", -8, 34)
    page:Hide()
    pages[name] = page
    return page
end

local function GatherStatus()
    local status = DufforthTweaksHelperNodes and DufforthTweaksHelperNodes.Status and DufforthTweaksHelperNodes.Status()
    if not status then return "" end
    if not status.enabled then return "Herb and ore icons are off." end
    if status.blocked or not status.api then
        return string.format("When you track the other kind, pictures show each dot you hovered (|cffffd100%d|r)%s. Since the 7 November game patch, addons can't read the minimap by themselves.",
            status.icons, status.showHistory and string.format(" and every spot where you gathered before (|cffffd100spawn spots: %d|r)", status.spots or 0) or "")
    end
    if not status.tracking then return "|cffffd100Turn on Find Herbs or Find Minerals so icons can be found.|r" end
    local text = string.format("Tracking %s. Icons saved: %d. Dots seen in the last check: %d.", status.tracking, status.icons, status.lastDots)
    if status.lastError then text = text .. "\n|cffff5555Last error: " .. status.lastError .. "|r" end
    return text
end

local function BuildGather(page)
    local y = -4
    y = Header(page, y, "Herb and ore icons on the minimap")
    local status = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", 12, y); status:SetWidth(PAGE_WIDTH - 34); status:SetJustifyH("LEFT")
    refreshers[#refreshers + 1] = function() status:SetText(GatherStatus()) end
    y = y - 58
    y = Check(page, y, "Keep herb and ore icons after swapping tracking", "Remembers each herb and ore dot you hover on the minimap. After you swap tracking, it shows a small picture of that node there (Peacebloom, Copper Ore, and so on), so herbs stay visible while you find minerals and the other way round, for 5 minutes after you last hovered it (see below). While a tracking is on, the game shows its own dots and the addon adds nothing on top. Hover a picture to see its name. Same as /nk on and /nk off.",
        function() return Nodes().enabled end, function(on) NodesCommand(on and "on" or "off") end)
    y = Check(page, y, "Swap tracking automatically", "Switches between Find Herbs and Find Minerals on a timer. Needs both Herbalism and Mining. Pauses in combat, in cities and inns, in instances, while dead, on flight paths and while stealthed.",
        function() return Nodes().swapEnabled end, function(on) NodesCommand(on and "swap on" or "swap off") end)
    y = Check(page, y, "Show spawn spots from my gathering history", "Every herb and ore you gather is saved where you stood. When you track the other kind, a slightly faded picture shows each of those spots, with no hovering needed. The node may not be there right now, so this is off by default; a spot you just gathered hides for 10 minutes. Same as /nk history on and off.",
        function() return Nodes().showHistory end, function(on) NodesCommand(on and "history on" or "history off") end)
    y = Stepper(page, y, "Swap every", "Seconds between tracking swaps.",
        function() return Nodes().swapSeconds end, function(v) NodesCommand("swap " .. v) end, 2, 60, 1, function(v) return (v or 0) .. " sec" end)
    y = Stepper(page, y, "Icon size", "Size of the node pictures shown for the kind you are not tracking.",
        function() return Nodes().size end, function(v) NodesCommand("size " .. v) end, 6, 20, 1)
    y = Stepper(page, y, "Forget unseen dots after", "Dots are removed after this long without being hovered again, since someone else may have taken the node. 'until gathered' keeps them until you gather it.",
        function() return Nodes().keepMinutes end, function(v) NodesCommand("keep " .. v) end, 0, 240, 5, function(v) return v == 0 and "until gathered" or (v .. " min") end)
    Button(page, y, "Clear hovered nodes", "Removes the nodes you hovered. Your gathering history stays.", function() NodesCommand("clear") end)
    Button(page, y - 30, "Clear gathering history", "Removes every saved spawn spot. Same as /nk history clear.", function() NodesCommand("history clear") end)
    Button(page, y, "Status in chat", "Prints what the icon finder sees right now, to help when icons don't show. Same as /nk status.", function() NodesCommand("status") end, 184, 150)
end

local function BuildDisenchant(page)
    local y = -4
    y = Header(page, y, "Item tooltips")
    y = Check(page, y, "Disenchant advice in item tooltips", "Weapon and armor tooltips show the disenchant materials with their chances and prices, the average value, and a colored tag that says what pays most: disenchant (green), auction house (gold) or vendor (gray). Same as /dufforth de.",
        function() return DB().showDisenchant ~= false end, function(on) DufforthTweaksHelperDE.Toggle(on and "on" or "off") end)
    y = y - 8
    y = Header(page, y, "Disenchant from your bags")
    local auto = DufforthTweaksHelperAutoDE
    y = Stepper(page, y, "Disenchant up to", "Higher qualities start unticked in the disenchant list. Uncommon (green) is the safe default; epics need a deliberate choice.",
        function() return auto.Options().maxQuality end, function(v) auto.Options().maxQuality = v end, 2, 4, 1, function(v) return auto.QUALITY_NAMES[v] end)
    y = Stepper(page, y, "Highest item level", "Items above this item level start unticked. 0 means any level.",
        function() return auto.Options().maxLevel end, function(v) auto.Options().maxLevel = v end, 0, 100, 5, function(v) return v == 0 and "any" or tostring(v) end)
    y = Check(page, y, "Untick items that sell for more on the auction house", "Uses the prices in your download: if the item's auction price, after the 5% cut, beats its disenchant value, it starts unticked.",
        function() return auto.Options().skipWorthMore end, function(on) auto.Options().skipWorthMore = on end)
    y = Check(page, y, "Untick items a vendor pays more for", "If a vendor pays more than the disenchant value, the item starts unticked.",
        function() return auto.Options().skipVendor end, function(on) auto.Options().skipVendor = on end)
    Button(page, y, "Open disenchant list", "Lists everything in your bags that can be disenchanted, with a checkbox each. Its button disenchants the ticked items one by one, one click per item. Same as /dufforth disenchant.", function() auto.Toggle() end)
    local clear = Button(page, y, "Clear keep list", "Items you right-clicked in the disenchant list start unticked. This clears that list.", function()
        auto.Options().keep = {}
        DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. "keep list cleared.")
    end, 184, 150)
    refreshers[#refreshers + 1] = function() clear:SetText("Clear keep list (" .. KeepCount() .. ")") end
end

local function BuildWarrior(page)
    local warrior = DufforthTweaksHelperWarrior
    local y = -4
    y = Header(page, y, "One button for your warrior")
    local function Text(height, font)
        local text = page:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
        text:SetPoint("TOPLEFT", 12, y); text:SetWidth(PAGE_WIDTH - 34); text:SetJustifyH("LEFT")
        y = y - height
        return text
    end
    if not warrior or not warrior.state then
        Text(60):SetText("|cffff5555The warrior part of the addon didn't load.|r Exit the game completely and start it again: a /reload doesn't load files that are new to an addon.")
        return
    end
    Text(70):SetText("|cffffd100How to use it:|r 1. Click |cffffd100Put it on my cursor|r. 2. Drop it on your action bar. 3. Press only that key in fights while you move.\nIt's the |cffffd100DTH Warrior|r macro (Esc > Macros > Character Specific Macros). After every fight the addon rewrites it for the spells you know, your stances and your Battle Shout.")
    local status = Text(28)
    refreshers[#refreshers + 1] = function() status:SetText(warrior.state.status or "") end
    local preview = Text(160, "GameFontDisableSmall")
    refreshers[#refreshers + 1] = function()
        if not warrior.state.lines and not (InCombatLockdown and InCombatLockdown()) then warrior.SafeUpdate() end
        local lines = warrior.state.lines
        preview:SetText(lines and ("The macro. The game tries one global-cooldown spell per press, so each stance has one line that steps through its spells. Victory Rush, Execute and Shield Bash go on their own keys; the icon flashes red when to press them:\n" .. table.concat(lines, "\n")) or "")
    end
    local function Rebuild() warrior.state.body = nil; warrior.SafeUpdate() end
    y = Check(page, y, "Keep the DTH Warrior macro up to date", "Rewrites the macro after each fight, when you learn a spell or get a new stance, and when Battle Shout is about to run out. Turn it off to edit the macro yourself.",
        function() return warrior.Options().enabled end, function(on) warrior.Options().enabled = on; if on then Rebuild() end end)
    y = Check(page, y, "Charge into fights", "Starts with Charge in Battle Stance (out of combat) or Intercept in Berserker Stance when the target is far enough away. Up close the button goes straight to the next ability.",
        function() return warrior.Options().charge end, function(on) warrior.Options().charge = on; Rebuild() end)
    y = Check(page, y, "Show the next spell on the button", "The game's own macro icon shows the first spell that matches, not the one the press will cast. This puts the picture of the spell your next press will cast on the DTH Warrior button itself, in every stance.",
        function() return warrior.Options().buttonIcon end, function(on) warrior.Options().buttonIcon = on; warrior.RefreshButtons() end)
    y = Check(page, y, "Show the next-ability icon", "While you have an enemy targeted or are in a fight, an icon shows what your button will cast next, how many enemies are on you and when Battle Shout is gone.",
        function() return warrior.Options().hint end, function(on) warrior.Options().hint = on end)
    y = Check(page, y, "Log my fights", "Saves your last 300 fights: each cast with your rage, the target's health and how many enemies were on you, what the icon showed, error messages, who hit you and for how much, and whether you won. The game writes it to your SavedVariables file on /reload or logout, so the macro can be improved from real fights.",
        function() return warrior.Options().log end, function(on) warrior.Options().log = on end)
    Button(page, y, "Put it on my cursor", "Builds the DTH Warrior macro and picks it up so you can drop it on your action bar. Only out of combat.", function() warrior.PickUp() end)
    local move = Button(page, y, "Move the icon", "Shows the icon so you can drag it where you like. Click again to lock it.", function()
        warrior.SetHintUnlocked(not warrior.HintUnlocked())
    end, 184, 150)
    refreshers[#refreshers + 1] = function() move:SetText(warrior.HintUnlocked() and "Lock the icon" or "Move the icon") end
    Button(page, y - 28, "Build it now", "Rewrites the macro right away. Only out of combat.", Rebuild)
    local clear = Button(page, y - 28, "Clear fight log", "Deletes every saved fight.", function() warrior.ClearLog() end, 184, 150)
    refreshers[#refreshers + 1] = function() clear:SetText("Clear fight log (" .. warrior.FightCount() .. ")") end
end

-- Your class's tab: consumables for every class; warriors also get the macro, with a switch between them.
local classViews = {}
local function ShowClassView(view)
    for key, frame in pairs(classViews) do frame:SetShown(key == view) end
    DB().classView = view
    RefreshMenu()
end

-- Views of the class tab, in button order. Every view gets small buttons (top right) to the others.
local CLASS_VIEWS = {
    { key = "macro", label = "Macro", tip = "The one-button DTH Warrior macro.", warriorOnly = true },
    { key = "consumables", label = "Consumables", tip = "Food, elixirs and potions worth buying for your class, with AH prices." },
    { key = "gear", label = "Gear", tip = "Upgrades for what you wear, from the auction house and from quests you can do now." },
}

local function RestartNote(frame, what)
    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    note:SetPoint("TOPLEFT", 12, -30); note:SetWidth(PAGE_WIDTH - 24); note:SetJustifyH("LEFT")
    note:SetText("|cffffd100Restart the game to see " .. what .. ".|r The addon got new files, and the game only loads new files on a full restart, not a /reload.")
end

local function BuildClass(page)
    local token -- "x and f()" would keep only f's first value
    if UnitClass then token = select(2, UnitClass("player")) end
    local views = {}
    for _, v in ipairs(CLASS_VIEWS) do
        if not v.warriorOnly or token == "WARRIOR" then
            local frame = CreateFrame("Frame", nil, page)
            frame:SetAllPoints(page)
            classViews[v.key] = frame
            views[#views + 1] = v
            if v.key == "macro" then BuildWarrior(frame)
            elseif v.key == "consumables" then
                if DufforthTweaksHelperConsumables then DufforthTweaksHelperConsumables.BuildPanel(frame, PAGE_WIDTH) else RestartNote(frame, "consumables") end
            elseif v.key == "gear" then
                if DufforthTweaksHelperGear then DufforthTweaksHelperGear.BuildPanel(frame, PAGE_WIDTH) else RestartNote(frame, "gear advice") end
            end
        end
    end
    -- Buttons to the other views, right-aligned on the title line.
    for _, v in ipairs(views) do
        local x = PAGE_WIDTH
        for i = #views, 1, -1 do
            local other = views[i]
            if other.key ~= v.key then
                local width = other.key == "consumables" and 96 or 64
                x = x - width - 4
                local b = Button(classViews[v.key], -2, other.label, other.tip, function() ShowClassView(other.key) end, x, width)
                b:SetHeight(20)
            end
        end
    end
    local wanted = DB().classView
    if not classViews[wanted] then wanted = token == "WARRIOR" and "macro" or "consumables" end
    ShowClassView(wanted)
end

local function Build()
    menu = CreateFrame("Frame", "DufforthTweaksHelperMenu", UIParent, "BasicFrameTemplateWithInset")
    menu:SetSize(WIDTH, math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, DB().menuHeight or HEIGHT)))
    menu:SetPoint("CENTER")
    menu:SetMovable(true); menu:EnableMouse(true); menu:RegisterForDrag("LeftButton")
    menu:SetScript("OnDragStart", menu.StartMoving)
    menu:SetScript("OnDragStop", menu.StopMovingOrSizing)
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:Hide()
    tinsert(UISpecialFrames, "DufforthTweaksHelperMenu") -- Escape closes it
    local title = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5)
    title:SetText("Dufforth Tweaks Helper")
    menu:SetScript("OnShow", RefreshMenu)

    for i, name in ipairs(TABS) do
        local tab = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
        local tabWidth = math.floor((WIDTH - 24) / #TABS) - 4
        tab:SetSize(tabWidth, 24)
        tab:SetPoint("TOPLEFT", 12 + (i - 1) * (tabWidth + 4), -28)
        tab:SetText(name == "Class" and ((UnitClass and UnitClass("player")) or "Class") or name)
        tab:SetScript("OnClick", function() ShowTab(name) end)
        tabButtons[name] = tab
    end
    -- Each tab is built on its own: one that fails shows its error, and the others still work.
    local function Note(page, text)
        local note = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        note:SetPoint("TOPLEFT", 12, -12); note:SetWidth(PAGE_WIDTH - 24); note:SetJustifyH("LEFT")
        note:SetText(text)
    end
    local builders = {
        Gather = function(page) BuildGather(page) end,
        Disenchant = function(page) BuildDisenchant(page) end,
        Crafting = function(page) DufforthTweaksHelperCrafting.BuildPanel(page, PAGE_WIDTH) end,
        Leveling = function(page)
            -- New files only load after a full game restart, not a /reload: say so instead of failing.
            if not DufforthTweaksHelperLeveling then
                Note(page, "|cffffd100Restart the game to use this tab.|r The addon got new files, and the game only loads new files on a full restart, not a /reload.")
                return
            end
            DufforthTweaksHelperLeveling.BuildPanel(page, PAGE_WIDTH)
        end,
        Zone = function(page)
            if not DufforthTweaksHelperZone then
                Note(page, "|cffffd100Restart the game to use this tab.|r The addon got new files, and the game only loads new files on a full restart, not a /reload.")
                return
            end
            DufforthTweaksHelperZone.BuildPanel(page, PAGE_WIDTH)
        end,
        Class = function(page) BuildClass(page) end,
    }
    for _, name in ipairs(TABS) do
        local page = Page(name)
        local ok, err = pcall(builders[name], page)
        if not ok then
            Note(page, "|cffff5555This tab hit an error while opening. Please send this text:|r\n" .. tostring(err))
            -- The error shows on the tab itself; no chat message (the user can't follow chat).
        end
    end

    -- Footer, on every tab.
    local box = CreateFrame("CheckButton", nil, menu, "UICheckButtonTemplate")
    box:SetSize(22, 22); box:SetPoint("BOTTOMLEFT", 12, 8)
    local label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", box, "RIGHT", 2, 0)
    label:SetText("Show the minimap button")
    box:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        DB().minimap = DB().minimap or {}
        DB().minimap.hide = not on
        if DufforthTweaksHelperMinimapButton then DufforthTweaksHelperMinimapButton:SetShown(on) end
    end)
    box:SetScript("OnEnter", function(self) ShowTip(self, "Left-click opens this window, right-click opens the disenchant list, drag moves it. If hidden, type /dufforth.") end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    refreshers[#refreshers + 1] = function() box:SetChecked(not (DB().minimap or {}).hide) end
    -- Edit mode: every on-screen piece shows with a green frame to drag, then lock them in one click.
    local move = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
    move:SetSize(110, 22); move:SetPoint("BOTTOMRIGHT", -26, 8)
    move:SetScript("OnClick", function()
        if not DufforthTweaksHelper.SetEditMode(not DufforthTweaksHelper.EditMode()) then
            ShowTip(move, "Not in combat: some pieces are locked by the game during fights.")
        end
        RefreshMenu()
    end)
    move:SetScript("OnEnter", function(self) ShowTip(self, "Shows the warrior icon, the eat button and the spell notice with a green frame so you can drag them where you like. Click again to lock them. Same as /dth move.") end)
    move:SetScript("OnLeave", function() GameTooltip:Hide() end)
    refreshers[#refreshers + 1] = function() move:SetText(DufforthTweaksHelper.EditMode() and "Lock pieces" or "Move pieces") end

    -- Taller or shorter: drag the corner. Lists show as many rows as fit; the height is remembered.
    menu:SetResizable(true)
    if menu.SetResizeBounds then menu:SetResizeBounds(WIDTH, MIN_HEIGHT, WIDTH, MAX_HEIGHT)
    elseif menu.SetMinResize then menu:SetMinResize(WIDTH, MIN_HEIGHT); menu:SetMaxResize(WIDTH, MAX_HEIGHT) end
    local grip = CreateFrame("Button", nil, menu)
    grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() menu:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        menu:StopMovingOrSizing()
        DB().menuHeight = math.floor(menu:GetHeight() + 0.5)
        RefreshMenu()
        if DufforthTweaksHelperLeveling and DufforthTweaksHelperLeveling.Refresh then pcall(DufforthTweaksHelperLeveling.Refresh) end
    end)
    grip:SetScript("OnEnter", function(self) ShowTip(self, "Drag to make the window taller or shorter.") end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)

    if DB().menuTab == "Warrior" then DB().menuTab = "Class" end -- the Warrior tab became your class's tab
    ShowTab(pages[DB().menuTab or ""] and DB().menuTab or "Gather")
end

local TAB_NAMES = { gather = "Gather", disenchant = "Disenchant", crafting = "Crafting", leveling = "Leveling", zone = "Zone",
    warrior = "Class", class = "Class", consumables = "Class", gear = "Class" }
local function ToggleMenu(tab)
    if not menu then Build() end
    if tab and TAB_NAMES[tab] then
        if tab == "warrior" and classViews.macro then ShowClassView("macro")
        elseif (tab == "consumables" or tab == "gear") and classViews[tab] then ShowClassView(tab) end
        ShowTab(TAB_NAMES[tab])
        menu:Show()
        return
    end
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
    GameTooltip:AddLine("Dufforth Tweaks Helper")
    GameTooltip:AddLine("Gathering, disenchanting, crafting, leveling and class help", 0.7, 0.7, 0.7)
    GameTooltip:AddDoubleLine("Herb and ore icons", State(Nodes().enabled), 1, 1, 1)
    GameTooltip:AddDoubleLine("Tracking swap", State(Nodes().swapEnabled), 1, 1, 1)
    GameTooltip:AddDoubleLine("Disenchant advice", State(DB().showDisenchant ~= false), 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: open the window   Right-click: disenchant list", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function BuildMinimapButton()
    local button = CreateFrame("Button", "DufforthTweaksHelperMinimapButton", Minimap)
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
        if mouse == "RightButton" then DufforthTweaksHelperAutoDE.Toggle() else ToggleMenu() end
    end)
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnDragUpdate) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", ButtonTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    PlaceButton(button)
    button:SetShown(not (DB().minimap or {}).hide)
end

-- ---- Game options page: a pointer to the window ----
local function RegisterOptions()
    local panel = CreateFrame("Frame")
    panel.name = "Dufforth Tweaks Helper"
    local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 16, -16)
    text:SetText("Everything is in the Dufforth Tweaks Helper window: Gather, Disenchant, Crafting, Leveling, Zone and a tab for your class (consumables, and the macro for warriors).")
    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(160, 24); open:SetPoint("TOPLEFT", 16, -40); open:SetText("Open the window")
    open:SetScript("OnClick", function() if not menu or not menu:IsShown() then ToggleMenu() end end)
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(panel, panel.name))
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

DufforthTweaksHelperMenu_Toggle = ToggleMenu

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    BuildMinimapButton()
    RegisterOptions()
end)
