-- One window with a tab per feature (Disenchant, Professions, Zone, your class), opened from the
-- minimap button, /dufforth, or the game's Options > AddOns. Changes go through the same
-- commands as the slash commands, so the window and the commands always agree.

local L = DufforthTweaksHelperL or setmetatable({}, { __index = function(_, k) return k end })
local PREFIX = L["|cff66ccffDufforth Tweaks Helper:|r "]
local ICON = "Interface\\AddOns\\DufforthTweaksHelper\\Media\\GuideIcon" -- the round guide icon (user, 2026-11-14)
local ROW = 26
-- The last tab is your class (named after it): consumables for everyone, the macro for warriors.
-- Disenchant holds the craft-to-disenchant list too, for every gear crafter (user, 2026-11-16). Its
-- Settings are for every character (tooltip advice); the disenchant list part needs Enchanting.
-- Fishing shows only for a character that knows Fishing (user, 2026-11-15).
-- Professions plans profession skill-ups; it was called Leveling until the user said "this is not
-- leveling is profesion leveling" (2026-11-27). Saved "Leveling" and /dth leveling still open it.
-- Alts lists every character's rested XP (user, 2026-11-27: "i want to see all my alts reste experience amount in a tab").
local TABS = { "Disenchant", "Professions", "Zone", "Grind", "Fishing", "Money", "Alts", "Class" }
-- A flat dark window like the leveling guide, with slim flat tabs, resizable both ways (user, 2026-11-14).
-- 4.37.6 modern look (user: "the interface looks rusty"): slate background with a thin border, a darker
-- tab strip and footer with hairlines, flat bordered buttons (the game's red panel buttons are
-- flattened in every tab by Skin), gold section titles with a faint rule.
local WIDTH, HEIGHT = 520, 520
local MIN_W, MAX_W, MIN_H, MAX_H = 420, 900, 300, 1000
local PAGE_WIDTH = WIDTH - 16 -- changes with the window's width; pages are rebuilt for it
local WHITE = "Interface\\Buttons\\WHITE8x8"

local function DB()
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    return DufforthTweaksHelperDB
end

local menu
local refreshers = {} -- the pages' controls (rebuilt with the pages)
local chrome = {} -- the window's own buttons
local pages, tabButtons = {}, {}
local LayoutTabs

-- The Disenchant tab only for a character with Enchanting (when professions can't be read, it stays).
local function HasEnchanting()
    local professions = DufforthTweaksHelper.Professions and DufforthTweaksHelper.Professions()
    if professions == nil then return true end
    return professions.Enchanting ~= nil
end

-- Craft to disenchant for any character that crafts gear, Enchanting or not: it can send the
-- gear to a disenchanting alt (user, 2026-11-16). When professions can't be read, it stays.
local GEAR_CRAFTS = { "Blacksmithing", "Leatherworking", "Tailoring", "Engineering", "Enchanting" }
local function CraftsGear()
    local professions = DufforthTweaksHelper.Professions and DufforthTweaksHelper.Professions()
    if professions == nil then return true end
    for _, name in ipairs(GEAR_CRAFTS) do
        if professions[name] then return true end
    end
    return false
end

-- Tabs that need a profession: Fishing (Fishing).
local function TabShown(name)
    if name == "Fishing" then
        if not DufforthTweaksHelperFishing then return false end
        local ok, spell = pcall(DufforthTweaksHelperFishing.Spell)
        return not ok or spell ~= nil
    end
    return true
end

local function RefreshMenu()
    if LayoutTabs then LayoutTabs() end
    for _, refresh in ipairs(chrome) do refresh() end
    for _, refresh in ipairs(refreshers) do refresh() end
    if DufforthTweaksHelperAutoDE and DufforthTweaksHelperAutoDE.Refresh then DufforthTweaksHelperAutoDE.Refresh() end
    if DufforthTweaksHelperCrafting and DufforthTweaksHelperCrafting.Refresh then DufforthTweaksHelperCrafting.Refresh() end
    if DufforthTweaksHelperConsumables and DufforthTweaksHelperConsumables.Refresh then DufforthTweaksHelperConsumables.Refresh() end
    if DufforthTweaksHelperZone and DufforthTweaksHelperZone.Refresh then DufforthTweaksHelperZone.Refresh() end
    if DufforthTweaksHelperGrind and DufforthTweaksHelperGrind.Refresh then pcall(DufforthTweaksHelperGrind.Refresh) end
    if DufforthTweaksHelperGear and DufforthTweaksHelperGear.Refresh then pcall(DufforthTweaksHelperGear.Refresh) end
    if DufforthTweaksHelperFishing and DufforthTweaksHelperFishing.Refresh then pcall(DufforthTweaksHelperFishing.Refresh) end
    if menu then pcall(SkinTree, menu) end -- rows the panels made just now get the flat look too
end

local function ShowTip(owner, text)
    if not text then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

-- ---- Style ----
local C = {
    bg = { 0.067, 0.071, 0.086, 0.97 }, edge = { 0.20, 0.22, 0.27, 1 }, strip = { 0.035, 0.039, 0.047, 1 },
    btn = { 0.13, 0.14, 0.17, 1 }, btnEdge = { 0.25, 0.27, 0.32, 1 },
    on = { 0.10, 0.34, 0.19, 1 }, onEdge = { 0.22, 0.58, 0.32, 1 },
    sel = { 0.20, 0.22, 0.28, 1 }, selEdge = { 1, 0.82, 0, 0.85 },
}

-- A 1-pixel border from four textures (works on any frame, no template needed).
local function Edges(frame)
    local e = {}
    for i, side in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetPoint(side[1]); t:SetPoint(side[2])
        if i <= 2 then t:SetHeight(1) else t:SetWidth(1) end
        e[i] = t
    end
    return e
end

-- Colors a flat button for its state: on (green), selected (gold edge) or plain.
local function Paint(b)
    if not rawget(b, "bg") then return end
    local fill, edge = C.btn, C.btnEdge
    if rawget(b, "dthOn") then fill, edge = C.on, C.onEdge elseif rawget(b, "dthSelected") then fill, edge = C.sel, C.selEdge end
    b.bg:SetColorTexture(unpack(fill))
    for _, t in ipairs(rawget(b, "edges") or {}) do t:SetColorTexture(unpack(edge)) end
end

-- Gives any button the flat look: dark fill, thin border, soft hover, white text (grey when disabled).
local function Dress(b)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.edges = Edges(b)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.08)
    b:SetNormalFontObject("GameFontHighlightSmall")
    if b.SetHighlightFontObject then b:SetHighlightFontObject("GameFontHighlightSmall") end
    if b.SetDisabledFontObject then b:SetDisabledFontObject("GameFontDisableSmall") end
    Paint(b)
end

-- A flat button like the leveling guide's.
local function Flat(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height or 20)
    Dress(b)
    b:SetText(text)
    return b
end

local function SetOn(b, on) b.dthOn = on and true or nil; Paint(b) end
local function Select(b, on) b.dthSelected = on and true or nil; Paint(b) end

-- Flattens a button made with the game's UIPanelButtonTemplate (the red, beveled one).
local function Skin(b)
    if rawget(b, "dthSkin") then return end
    for _, key in ipairs({ "Left", "Middle", "Right" }) do
        local t = b[key]
        if type(t) == "table" and t.Hide then t:Hide(); if t.SetAlpha then t:SetAlpha(0) end end
    end
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
        if type(b[get]) == "function" then
            local ok, t = pcall(b[get], b)
            if ok and type(t) == "table" and t.SetAlpha then t:SetAlpha(0) end
        end
    end
    b.dthSkin = true
    Dress(b)
end

-- Walks a frame's children and flattens every panel button not done yet (cheap when nothing is new).
local function IsPanelButton(f)
    return type(f.Left) == "table" and type(f.Middle) == "table" and type(f.Right) == "table" and type(f.SetText) == "function"
end
local function SkinTree(frame)
    if type(frame) ~= "table" or type(frame.GetChildren) ~= "function" then return end
    for _, child in ipairs({ frame:GetChildren() }) do
        if type(child) == "table" then
            if not rawget(child, "dthSkin") and IsPanelButton(child) then Skin(child) end
            SkinTree(child)
        end
    end
end

-- Other files (the Professions tab's view toggle) use the same look.
DufforthTweaksHelperUI = { Skin = Skin, SkinTree = SkinTree, Select = Select, SetOn = SetOn, Paint = Paint }

local function Header(parent, y, text)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 8, y)
    label:SetText(text)
    -- A faint gold rule after the title separates the sections.
    local rule = parent:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1); rule:SetColorTexture(1, 0.82, 0, 0.22)
    rule:SetPoint("LEFT", label, "RIGHT", 8, 0); rule:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
    return y - 22
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
    if not TabShown(name) then name = "Professions" end
    if not pages[name] then name = "Professions" end
    for _, tab in ipairs(TABS) do
        if pages[tab] then pages[tab]:SetShown(tab == name) end
    end
    DB().menuTab = name
    RefreshMenu()
end

-- Tabs side by side as wide as their names: the open one is lighter with white text and a gold line
-- under it; the others sit flat on the strip with grey text.
LayoutTabs = function()
    if not menu then return end
    local open = DB().menuTab
    if open and not TabShown(open) then
        open = "Professions"; DB().menuTab = open
        for _, tab in ipairs(TABS) do if pages[tab] then pages[tab]:SetShown(tab == open) end end
    end
    -- Every tab fits between the left edge and the X, whatever the count and the class name (user, 2026-11-28:
    -- "Paladin" was drawn past the X). Each tab is as wide as its name plus padding; when they don't all fit,
    -- they shrink in proportion and a squeezed name is cut, with the full name on hover.
    local shown = {}
    for _, name in ipairs(TABS) do
        local b = tabButtons[name]
        if b then
            local on = TabShown(name)
            b:SetShown(on)
            if on then shown[#shown + 1] = { name = name, b = b } end
        end
    end
    local GAP, PAD = 2, 16
    local avail = (menu:GetWidth() or WIDTH) - 4 - (4 + 20 + 6) -- left margin; X (20) at -4 plus a gap
    local total = GAP * math.max(0, #shown - 1)
    for _, t in ipairs(shown) do
        local on = t.name == open
        t.b:SetNormalFontObject(on and "GameFontHighlightSmall" or "GameFontDisableSmall") -- before measuring
        local fs = t.b.GetFontString and t.b:GetFontString()
        local w = fs and fs.GetStringWidth and fs:GetStringWidth()
        if type(w) ~= "number" or w <= 0 then w = #(t.b:GetText() or t.name) * 6 end
        t.natural = math.ceil(w) + PAD
        total = total + t.natural
    end
    local scale = 1
    if total > avail and total > 0 then scale = (avail - GAP * math.max(0, #shown - 1)) / (total - GAP * math.max(0, #shown - 1)) end
    local x = 4
    for _, t in ipairs(shown) do
        local b, on = t.b, t.name == open
        local width = math.floor(t.natural * scale)
        b.cut = scale < 1 or nil
        b:SetWidth(width)
        local fs = b.GetFontString and b:GetFontString()
        if fs and fs.SetWidth then fs:SetWidth(width - 4); if fs.SetWordWrap then fs:SetWordWrap(false) end end
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", menu, "TOPLEFT", x, -4)
        x = x + width + GAP
        b.bg:SetColorTexture(0.13, 0.14, 0.17, on and 1 or 0)
        b.mark:SetShown(on)
    end
end

local function Page(name)
    local page = CreateFrame("Frame", nil, menu)
    page:SetPoint("TOPLEFT", 8, -32)
    page:SetPoint("BOTTOMRIGHT", -8, 28)
    page:Hide()
    pages[name] = page
    return page
end

local function BuildDisenchant(page)
    local y = -4
    y = Header(page, y, L["Item tooltips"])
    y = Check(page, y, L["Disenchant advice in item tooltips"], L["Item tooltips start with one line that says what pays most: auction house after its 5% cut (gold), vendor (gray) or disenchant (green), with the price. Works for every character; disenchanting shows only when it's worth knowing. Same as /dufforth de."],
        function() return DB().showDisenchant ~= false end, function(on) DufforthTweaksHelperDE.Toggle(on and "on" or "off") end)
    local tip = DufforthTweaksHelperDE.TooltipOptions
    y = Check(page, y, L["Show the details, not only the verdict"], L["Under the verdict, one line each for the auction house, the vendor and disenchanting, with the prices aligned. Untick for the verdict line alone."],
        function() return tip().details end, function(on) tip().details = on end)
    y = Check(page, y, L["Show the disenchant odds"], L["Each material disenchanting can give, with its chance, amount and price."],
        function() return tip().odds end, function(on) tip().odds = on end)
    y = Check(page, y, L["Details only while holding Shift"], L["Keeps tooltips short: the verdict always, the details while you hold Shift."],
        function() return tip().shift end, function(on) tip().shift = on end)
    y = y - 8
    -- The disenchant list settings, only for a character with Enchanting.
    local bags = CreateFrame("Frame", nil, page)
    bags:SetPoint("TOPLEFT", 0, y); bags:SetPoint("BOTTOMRIGHT", 0, 0)
    refreshers[#refreshers + 1] = function() bags:SetShown(HasEnchanting()) end
    page, y = bags, 0
    y = Header(page, y, L["Disenchant from your bags"])
    local auto = DufforthTweaksHelperAutoDE
    y = Stepper(page, y, L["Disenchant up to"], L["Higher qualities start unticked in the disenchant list. Uncommon (green) is the safe default; epics need a deliberate choice."],
        function() return auto.Options().maxQuality end, function(v) auto.Options().maxQuality = v end, 2, 4, 1, function(v) return auto.QUALITY_NAMES[v] end)
    y = Stepper(page, y, L["Highest item level"], L["Items above this item level start unticked. 0 means any level."],
        function() return auto.Options().maxLevel end, function(v) auto.Options().maxLevel = v end, 0, 100, 5, function(v) return v == 0 and L["any"] or tostring(v) end)
    y = Check(page, y, L["Untick items that sell for more on the auction house"], L["Uses the prices in your download: if the item's auction price, after the 5% cut, beats its disenchant value, it starts unticked."],
        function() return auto.Options().skipWorthMore end, function(on) auto.Options().skipWorthMore = on end)
    y = Check(page, y, L["Untick items a vendor pays more for"], L["If a vendor pays more than the disenchant value, the item starts unticked."],
        function() return auto.Options().skipVendor end, function(on) auto.Options().skipVendor = on end)
    Button(page, y, L["Open disenchant list"], L["Lists everything in your bags that can be disenchanted, with a checkbox each. Its button disenchants the ticked items one by one, one click per item. Same as /dufforth disenchant."], function() auto.Toggle() end)
    local clear = Button(page, y, L["Clear keep list"], L["Items you right-clicked in the disenchant list start unticked. This clears that list."], function()
        auto.Options().keep = {}
        DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. L["keep list cleared."])
    end, 184, 150)
    refreshers[#refreshers + 1] = function() clear:SetText(L["Clear keep list ("] .. KeepCount() .. ")") end
end

-- The Disenchant tab: its settings and the gear worth crafting to disenchant (the old Crafting tab).
local deViews = {}
local DE_VIEWS = {
    -- Craft to disenchant first (user, 2026-11-15).
    { key = "craft", label = L["Craft to disenchant"], width = 130, tip = L["Gear worth crafting to disenchant, best profit first."] },
    { key = "settings", label = L["Settings"], width = 70, tip = L["Disenchant advice in tooltips and the disenchant list."] },
}
local function ShowDisenchantView(view)
    if not deViews[view] or (view == "craft" and not CraftsGear()) then view = "settings" end
    for key, frame in pairs(deViews) do frame:SetShown(key == view) end
    DB().deView = view
    RefreshMenu()
end

local function BuildDisenchantTab(page)
    local x = 0
    local buttons = {}
    for _, v in ipairs(DE_VIEWS) do
        local b = Flat(page, v.label, v.width, 20)
        b:SetPoint("TOPLEFT", x, 0)
        b:SetScript("OnClick", function() ShowDisenchantView(v.key) end)
        b:SetScript("OnEnter", function(self) ShowTip(self, v.tip) end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        buttons[v.key] = b
        x = x + v.width + 3
        local frame = CreateFrame("Frame", nil, page)
        frame:SetPoint("TOPLEFT", 0, -26); frame:SetPoint("BOTTOMRIGHT", 0, 0)
        deViews[v.key] = frame
        if v.key == "settings" then BuildDisenchant(frame)
        else DufforthTweaksHelperCrafting.BuildPanel(frame, PAGE_WIDTH) end
    end
    refreshers[#refreshers + 1] = function()
        local crafter = CraftsGear()
        if not crafter and DB().deView ~= "settings" then ShowDisenchantView("settings") end
        for key, b in pairs(buttons) do
            b:SetShown(crafter) -- no gear crafting: there is only Settings, so no view buttons
            SetOn(b, DB().deView == key)
        end
        -- Without the view buttons the settings move up.
        deViews.settings:ClearAllPoints()
        deViews.settings:SetPoint("TOPLEFT", 0, crafter and -26 or 0); deViews.settings:SetPoint("BOTTOMRIGHT", 0, 0)
    end
    ShowDisenchantView(DB().deView or "settings")
end

local function BuildWarrior(page)
    local warrior = DufforthTweaksHelperWarrior
    local y = -4
    y = Header(page, y, L["One button for your warrior"])
    local function Text(height, font)
        local text = page:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
        text:SetPoint("TOPLEFT", 12, y); text:SetWidth(PAGE_WIDTH - 34); text:SetJustifyH("LEFT")
        y = y - height
        return text
    end
    if not warrior or not warrior.state then
        Text(60):SetText(L["|cffff5555The warrior part of the addon didn't load.|r Exit the game completely and start it again: a /reload doesn't load files that are new to an addon."])
        return
    end
    Text(70):SetText(L["|cffffd100How to use it:|r two buttons that never mix. |cffffd100DTH Warrior|r hits one enemy; |cffffd100DTH Warrior AoE|r hits every enemy around you (Thunder Clap, Whirlwind, Cleave, Demoralizing Shout, Sweeping Strikes). Put each on your action bar and press the AoE one when 2 or more enemies are on you; the icon tells you. After every fight the addon rewrites both for the spells you know, your stances and your Battle Shout."])
    local status = Text(28)
    refreshers[#refreshers + 1] = function() status:SetText(warrior.state.status or "") end
    local preview = Text(250, "GameFontDisableSmall")
    refreshers[#refreshers + 1] = function()
        if not warrior.state.lines and not (InCombatLockdown and InCombatLockdown()) then warrior.SafeUpdate() end
        local lines = warrior.state.lines
        preview:SetText(lines and (L["The macro. The game tries one global-cooldown spell per press, so each stance has one line that steps through its spells. Victory Rush, Execute and Shield Bash go on their own keys; the icon flashes red when to press them:\n"] .. table.concat(lines, "\n")
            .. "\n|cffffd100" .. warrior.MACRO_AOE .. ":|r\n" .. table.concat(warrior.state.aoeLines or {}, "\n")) or "")
    end
    local function Rebuild() warrior.state.body = nil; warrior.SafeUpdate() end
    y = Check(page, y, L["Keep the DTH Warrior macro up to date"], L["Rewrites the macro after each fight, when you learn a spell or get a new stance, and when Battle Shout is about to run out. Turn it off to edit the macro yourself."],
        function() return warrior.Options().enabled end, function(on) warrior.Options().enabled = on; if on then Rebuild() end end)
    y = Check(page, y, L["Charge into fights"], L["Starts with Charge in Battle Stance (out of combat) or Intercept in Berserker Stance when the target is far enough away. Up close the button goes straight to the next ability."],
        function() return warrior.Options().charge end, function(on) warrior.Options().charge = on; Rebuild() end)
    y = Check(page, y, L["Show the next spell on the button"], L["The game's own macro icon shows the first spell that matches, not the one the press will cast. This puts the picture of the spell your next press will cast on the DTH Warrior button itself, in every stance."],
        function() return warrior.Options().buttonIcon end, function(on) warrior.Options().buttonIcon = on; warrior.RefreshButtons() end)
    y = Check(page, y, L["Show the next-ability icon"], L["While you have an enemy targeted or are in a fight, an icon shows what your button will cast next, how many enemies are on you and when Battle Shout is gone."],
        function() return warrior.Options().hint end, function(on) warrior.Options().hint = on end)
    y = Check(page, y, L["Log my fights"], L["Saves your last 300 fights: each cast with your rage, the target's health and how many enemies were on you, what the icon showed, error messages, who hit you and for how much, and whether you won. The game writes it to your SavedVariables file on /reload or logout, so the macro can be improved from real fights."],
        function() return warrior.Options().log end, function(on) warrior.Options().log = on end)
    Button(page, y, L["Single target on cursor"], L["Builds the DTH Warrior macro and picks it up so you can drop it on your action bar. Only out of combat."], function() warrior.PickUp() end)
    Button(page, y - 56, L["AoE on cursor"], L["Builds the DTH Warrior AoE macro and picks it up so you can drop it on your action bar. Only out of combat."], function() warrior.PickUp("aoe") end)
    local move = Button(page, y, L["Move the icon"], L["Shows the icon so you can drag it where you like. Click again to lock it."], function()
        warrior.SetHintUnlocked(not warrior.HintUnlocked())
    end, 184, 150)
    refreshers[#refreshers + 1] = function() move:SetText(warrior.HintUnlocked() and L["Lock the icon"] or L["Move the icon"]) end
    Button(page, y - 28, L["Build it now"], L["Rewrites the macro right away. Only out of combat."], Rebuild)
    local clear = Button(page, y - 28, L["Clear fight log"], L["Deletes every saved fight."], function() warrior.ClearLog() end, 184, 150)
    refreshers[#refreshers + 1] = function() clear:SetText(L["Clear fight log ("] .. warrior.FightCount() .. ")") end
end

-- The druid's macro view: same options as the warrior's, minus Charge.
local function BuildDruid(page)
    local druid = DufforthTweaksHelperDruid
    local y = -4
    y = Header(page, y, L["One button for your druid"])
    local function Text(height, font)
        local text = page:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
        text:SetPoint("TOPLEFT", 12, y); text:SetWidth(PAGE_WIDTH - 34); text:SetJustifyH("LEFT")
        y = y - height
        return text
    end
    if not druid or not druid.state then
        Text(60):SetText(L["|cffff5555The druid part of the addon didn't load.|r Exit the game completely and start it again: a /reload doesn't load files that are new to an addon."])
        return
    end
    Text(70):SetText(L["|cffffd100How to use it:|r 1. Click |cffffd100Put it on my cursor|r. 2. Drop it on your action bar. 3. Press only that key in fights. It never changes your form: shift on your stance bar and the button fights in that form.\nIt's the |cffffd100DTH Druid|r macro (Esc > Macros > Character Specific Macros). After every fight the addon rewrites it for the spells and forms you know."])
    local status = Text(28)
    refreshers[#refreshers + 1] = function() status:SetText(druid.state.status or "") end
    local preview = Text(160, "GameFontDisableSmall")
    refreshers[#refreshers + 1] = function()
        if not druid.state.lines and not (InCombatLockdown and InCombatLockdown()) then druid.SafeUpdate() end
        local lines = druid.state.lines
        preview:SetText(lines and (L["The macro. Bear: Maul every press, Enrage and Demoralizing Roar once a fight, Swipe in a group. Cat: Tiger's Fury once, then Rake, Claw x3 and the finisher. Caster: Faerie Fire and Moonfire once, then Wrath. Bash and heals go on their own keys; the icon flashes red when to press them:\n"] .. table.concat(lines, "\n")) or "")
    end
    local function Rebuild() druid.state.body = nil; druid.SafeUpdate() end
    y = Check(page, y, L["Keep the DTH Druid macro up to date"], L["Rewrites the macro after each fight, when you learn a spell or a form, and when you join or leave a group. Turn it off to edit the macro yourself."],
        function() return druid.Options().enabled end, function(on) druid.Options().enabled = on; if on then Rebuild() end end)
    y = Check(page, y, L["Show the next spell on the button"], L["The game's own macro icon shows the first spell that matches, not the one the press will cast. This puts the picture of the spell your next press will cast on the DTH Druid button itself, in every form."],
        function() return druid.Options().buttonIcon end, function(on) druid.Options().buttonIcon = on; druid.RefreshButtons() end)
    y = Check(page, y, L["Show the next-ability icon"], L["While you have an enemy targeted or are in a fight, an icon shows what your button will cast next, your combo points in Cat Form and how many enemies are on you."],
        function() return druid.Options().hint end, function(on) druid.Options().hint = on end)
    y = Check(page, y, L["Log my fights"], L["Saves your last 300 fights: every spell the button tried, each cast with your form and combo points, what the icon showed, error messages and whether you won. The game writes it to your SavedVariables file on /reload or logout, so the macro can be improved from real fights."],
        function() return druid.Options().log end, function(on) druid.Options().log = on end)
    Button(page, y, L["Put it on my cursor"], L["Builds the DTH Druid macro and picks it up so you can drop it on your action bar. Only out of combat."], function() druid.PickUp() end)
    local move = Button(page, y, L["Move the icon"], L["Shows the icon so you can drag it where you like. Click again to lock it."], function()
        druid.SetHintUnlocked(not druid.HintUnlocked())
    end, 184, 150)
    refreshers[#refreshers + 1] = function() move:SetText(druid.HintUnlocked() and L["Lock the icon"] or L["Move the icon"]) end
    Button(page, y - 28, L["Build it now"], L["Rewrites the macro right away. Only out of combat."], Rebuild)
    local clear = Button(page, y - 28, L["Clear fight log"], L["Deletes every saved fight."], function() druid.ClearLog() end, 184, 150)
    refreshers[#refreshers + 1] = function() clear:SetText(L["Clear fight log ("] .. druid.FightCount() .. ")") end
end

-- The hunter's view: the fight log only (your macro stays yours; tools/analyze_hunter_fights.py reads the log).
local function BuildHunter(page)
    local hunter = DufforthTweaksHelperHunter
    local y = -4
    y = Header(page, y, L["One button for your hunter"])
    local function Text(height, font)
        local text = page:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
        text:SetPoint("TOPLEFT", 12, y); text:SetWidth(PAGE_WIDTH - 34); text:SetJustifyH("LEFT")
        y = y - height
        return text
    end
    if not hunter or not hunter.BuildLines then
        Text(60):SetText(L["|cffff5555The hunter part of the addon didn't load.|r Exit the game completely and start it again: a /reload doesn't load files that are new to an addon."])
        return
    end
    Text(70):SetText(L["|cffffd100How to use it:|r 1. Click |cffffd100Put it on my cursor|r. 2. Drop it on your action bar. 3. Press it about twice a second in fights; no other keys needed.\nIt's the |cffffd100DTH Hunter|r macro (Esc > Macros > Character Specific Macros). After every fight the addon rewrites it for the spells you know."])
    local status = Text(28)
    refreshers[#refreshers + 1] = function() status:SetText(hunter.state.status or "") end
    local preview = Text(150, "GameFontDisableSmall")
    refreshers[#refreshers + 1] = function()
        if not hunter.state.lines and not (InCombatLockdown and InCombatLockdown()) then hunter.SafeUpdate() end
        local lines = hunter.state.lines
        preview:SetText(lines and (L["The macro. Pet attacks first, a hawk on the first press, Hunter's Mark while the hawk cooldown runs, then hawks and Arcane Shot. Between pulls the addon plans the order from the hawks still out, so there's never a third hawk. Raptor Strike, Auto Shot and Mongoose Bite on every press:\n"] .. table.concat(lines, "\n")) or "")
    end
    local function Rebuild() hunter.state.body = nil; hunter.SafeUpdate() end
    y = Check(page, y, L["Keep the DTH Hunter macro up to date"], L["Rewrites the macro after each fight and when you learn a spell or a talent. Turn it off to edit the macro yourself."],
        function() return hunter.Options().enabled ~= false end, function(on) hunter.Options().enabled = on; if on then Rebuild() end end)
    y = Check(page, y, L["Show the next spell on the button"], L["The game's own macro icon shows the first spell in the macro, not the one the press will cast. This puts the picture of the spell your next press will cast on the DTH Hunter button itself (grey when it can't go yet)."],
        function() return hunter.Options().buttonIcon ~= false end, function(on) hunter.Options().buttonIcon = on; hunter.RefreshButtons() end)
    y = Check(page, y, L["Log my fights"], L["Saves your last 300 fights: every spell you sent, cast or had refused, hawks out, Hunter's Mark per target, Mongoose Bite chances, Auto Shots, your pet and whether you won. The game writes it on /reload or logout, so the macro can be improved from real fights."],
        function() return hunter.Options().log end, function(on) hunter.Options().log = on end)
    Button(page, y, L["Put it on my cursor"], L["Builds the DTH Hunter macro and picks it up so you can drop it on your action bar. Only out of combat."], function() hunter.PickUp() end)
    local clear = Button(page, y, L["Clear fight log"], L["Deletes every saved fight."], function() hunter.ClearLog() end, 184, 150)
    refreshers[#refreshers + 1] = function() clear:SetText(L["Clear fight log ("] .. hunter.FightCount() .. ")") end
    Button(page, y - 28, L["Build it now"], L["Rewrites the macro right away. Only out of combat."], Rebuild)
end

-- The leveling log (LevelLog.lua): on/off, what it kept, how to read it, Clear. Shown for every class.
local function BuildLevelLog(page)
    local log = DufforthTweaksHelperLevelLog
    local y = -4
    y = Header(page, y, L["Leveling log"])
    local function Text(height, font)
        local text = page:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
        text:SetPoint("TOPLEFT", 12, y); text:SetWidth(PAGE_WIDTH - 34); text:SetJustifyH("LEFT")
        y = y - height
        return text
    end
    if not log then
        Text(60):SetText(L["|cffff5555The leveling log didn't load.|r Exit the game completely and start it again: a /reload doesn't load files that are new to an addon."])
        return
    end
    Text(84):SetText(L["Saves what you do while leveling, for this character: quests, level ups, hearth, flights, deaths, vendors and trainers, zones, the guide's steps (done, skipped, back), idle and AFK time, and XP from kills, quests and rested. It never shows in chat.\nThe game writes it on /reload or logout. To read it, run |cffffd100tools/analyze_leveling_log.py|r on your game folder: it shows where the guide loses time and what to fix."])
    local summary = Text(44)
    refreshers[#refreshers + 1] = function()
        local s = log.Summary()
        summary:SetText(string.format(L["%d of %d events kept, covering %.1f hours.\nDeaths %d, steps skipped by hand %d, quests taken off the guide %d."],
            s.rows, s.max, (s.seconds or 0) / 3600, s.deaths, s.skips, s.offGuide))
    end
    y = Check(page, y, L["Log my leveling"], L["Keeps the last 5,000 events of this character; the oldest go first. Turn it off to stop logging; what's saved stays until you clear it."],
        function() return log.Options().on ~= false end, function(on) log.Options().on = on end)
    local clear = Button(page, y, L["Clear leveling log"], L["Deletes this character's leveling log. Other characters keep theirs."], function() log.Clear() end, 14, 190)
    refreshers[#refreshers + 1] = function() clear:SetText(L["Clear leveling log ("] .. log.Count() .. ")") end
end

-- Your class's tab: consumables for every class; warriors and druids also get the macro, with a switch between them.
local classViews = {}
local function ShowClassView(view)
    for key, frame in pairs(classViews) do frame:SetShown(key == view) end
    DB().classView = view
    RefreshMenu()
end

-- Views of the class tab, in button order. Every view gets small buttons (top right) to the others.
local CLASS_VIEWS = {
    { key = "macro", label = L["Macro"], tip = L["The one-button DTH Warrior macro."],
      classes = { WARRIOR = L["The one-button DTH Warrior macro."], DRUID = L["The one-button DTH Druid macro."],
                  HUNTER = L["The one-button DTH Hunter macro and your fight log."] } },
    { key = "pets", label = L["Pets"], classes = { HUNTER = L["Which pet to tame, its skills and where to learn new ranks."] } },
    { key = "consumables", label = L["Consumables"], tip = L["Food, elixirs and potions worth buying for your class, with AH prices."] },
    { key = "gear", label = L["Gear"], tip = L["Upgrades for what you wear, from the auction house and from quests you can do now."] },
    { key = "log", label = L["Log"], tip = L["Your leveling log: what you do while leveling, to improve the guide."] },
}

local function RestartNote(frame, what)
    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    note:SetPoint("TOPLEFT", 12, -30); note:SetWidth(PAGE_WIDTH - 24); note:SetJustifyH("LEFT")
    note:SetText(L["|cffffd100Restart the game to see "] .. what .. L[".|r The addon got new files, and the game only loads new files on a full restart, not a /reload."])
end

local function BuildClass(page)
    local token -- "x and f()" would keep only f's first value
    if UnitClass then token = select(2, UnitClass("player")) end
    local views = {}
    for _, v in ipairs(CLASS_VIEWS) do
        if not v.classes or v.classes[token] then
            local frame = CreateFrame("Frame", nil, page)
            frame:SetAllPoints(page)
            classViews[v.key] = frame
            if v.classes then v = { key = v.key, label = v.label, tip = v.classes[token] } end
            views[#views + 1] = v
            if v.key == "macro" then
                if token == "DRUID" then BuildDruid(frame) elseif token == "HUNTER" then BuildHunter(frame) else BuildWarrior(frame) end
            elseif v.key == "pets" then
                if DufforthTweaksHelperPets then DufforthTweaksHelperPets.BuildPanel(frame, PAGE_WIDTH) else RestartNote(frame, "the pet guide") end
            elseif v.key == "consumables" then
                if DufforthTweaksHelperConsumables then DufforthTweaksHelperConsumables.BuildPanel(frame, PAGE_WIDTH) else RestartNote(frame, "consumables") end
            elseif v.key == "log" then
                BuildLevelLog(frame)
            elseif v.key == "gear" then
                if DufforthTweaksHelperGear then DufforthTweaksHelperGear.BuildPanel(frame, PAGE_WIDTH) else RestartNote(frame, L["gear advice"]) end
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
    if not classViews[wanted] then wanted = classViews.macro and "macro" or "consumables" end
    ShowClassView(wanted)
end

local function Clamp(v, low, high) return math.max(low, math.min(high, tonumber(v) or low)) end

-- Each tab is built on its own: one that fails shows its error, and the others still work.
local function Note(page, text)
    local note = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    note:SetPoint("TOPLEFT", 12, -12); note:SetWidth(PAGE_WIDTH - 24); note:SetJustifyH("LEFT")
    note:SetText(text)
end
local RESTART = L["|cffffd100Restart the game to use this tab.|r The addon got new files, and the game only loads new files on a full restart, not a /reload."]
local builders = {
    Disenchant = function(page) BuildDisenchantTab(page) end,
    Professions = function(page)
        -- New files only load after a full game restart, not a /reload: say so instead of failing.
        if not DufforthTweaksHelperLeveling then Note(page, RESTART); return end
        DufforthTweaksHelperLeveling.BuildPanel(page, PAGE_WIDTH)
    end,
    Zone = function(page)
        if not DufforthTweaksHelperZone then Note(page, RESTART); return end
        DufforthTweaksHelperZone.BuildPanel(page, PAGE_WIDTH)
    end,
    Grind = function(page)
        if not DufforthTweaksHelperGrind then Note(page, RESTART); return end
        DufforthTweaksHelperGrind.BuildPanel(page, PAGE_WIDTH)
    end,
    Fishing = function(page)
        if not DufforthTweaksHelperFishing then Note(page, RESTART); return end
        DufforthTweaksHelperFishing.BuildPanel(page, PAGE_WIDTH)
    end,
    Money = function(page)
        if not DufforthTweaksHelperMoney then Note(page, RESTART); return end
        DufforthTweaksHelperMoney.BuildPanel(page, PAGE_WIDTH)
    end,
    Alts = function(page)
        if not DufforthTweaksHelperRested then Note(page, RESTART); return end
        refreshers[#refreshers + 1] = DufforthTweaksHelperRested.BuildPanel(page, PAGE_WIDTH)
    end,
    Class = function(page) BuildClass(page) end,
}

-- (Re)builds every page for the current width: the panels lay out their rows from it.
local function BuildPages()
    for _, page in pairs(pages) do page:Hide() end
    for k in pairs(pages) do pages[k] = nil end
    for i = #refreshers, 1, -1 do refreshers[i] = nil end
    for k in pairs(classViews) do classViews[k] = nil end
    for k in pairs(deViews) do deViews[k] = nil end
    for _, name in ipairs(TABS) do
        local page = Page(name)
        local ok, err = pcall(builders[name], page)
        if not ok then
            Note(page, L["|cffff5555This tab hit an error while opening. Please send this text:|r\n"] .. tostring(err))
            -- The error shows on the tab itself; no chat message (the user can't follow chat).
        end
    end
end

-- A new size from the corner: remembered, and the pages are rebuilt when the width changed.
local function ApplySize(w, h)
    w, h = math.floor(Clamp(w, MIN_W, MAX_W) + 0.5), math.floor(Clamp(h, MIN_H, MAX_H) + 0.5)
    menu:SetSize(w, h)
    DB().menuSize = { w, h }
    if w - 16 ~= PAGE_WIDTH then
        PAGE_WIDTH = w - 16
        BuildPages()
    end
    ShowTab(DB().menuTab or "Professions")
    if DufforthTweaksHelperLeveling and DufforthTweaksHelperLeveling.Refresh then pcall(DufforthTweaksHelperLeveling.Refresh) end
end

local function Build()
    menu = CreateFrame("Frame", "DufforthTweaksHelperMenu", UIParent, "BackdropTemplate")
    local size = DB().menuSize or { WIDTH, DB().menuHeight or HEIGHT }
    local w, h = math.floor(Clamp(size[1], MIN_W, MAX_W)), math.floor(Clamp(size[2], MIN_H, MAX_H))
    menu:SetSize(w, h)
    PAGE_WIDTH = w - 16
    if menu.SetBackdrop then
        menu:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        menu:SetBackdropColor(unpack(C.bg)); menu:SetBackdropBorderColor(unpack(C.edge))
    end
    menu:SetPoint("CENTER")
    menu:SetMovable(true); menu:EnableMouse(true); menu:RegisterForDrag("LeftButton")
    menu:SetScript("OnDragStart", menu.StartMoving)
    menu:SetScript("OnDragStop", menu.StopMovingOrSizing)
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:Hide()
    tinsert(UISpecialFrames, "DufforthTweaksHelperMenu") -- Escape closes it
    menu:SetScript("OnShow", RefreshMenu)
    -- Rows a panel adds on its own (not through RefreshMenu) get the flat look within a second.
    local sinceSkin = 0
    menu:SetScript("OnUpdate", function(_, elapsed)
        sinceSkin = sinceSkin + (elapsed or 0)
        if sinceSkin >= 1 then sinceSkin = 0; pcall(SkinTree, menu) end
    end)

    -- Top strip: the tabs, and X to close.
    local strip = menu:CreateTexture(nil, "BORDER")
    strip:SetPoint("TOPLEFT", 1, -1); strip:SetPoint("TOPRIGHT", -1, -1); strip:SetHeight(26)
    strip:SetColorTexture(unpack(C.strip))
    menu.dthHeaderLine = menu:CreateTexture(nil, "BORDER")
    menu.dthHeaderLine:SetPoint("TOPLEFT", strip, "BOTTOMLEFT"); menu.dthHeaderLine:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT")
    menu.dthHeaderLine:SetHeight(1); menu.dthHeaderLine:SetColorTexture(unpack(C.edge))
    -- Bottom strip for the window's own buttons, with a hairline above it.
    local footer = menu:CreateTexture(nil, "BORDER")
    footer:SetPoint("BOTTOMLEFT", 1, 1); footer:SetPoint("BOTTOMRIGHT", -1, 1); footer:SetHeight(26)
    footer:SetColorTexture(unpack(C.strip))
    menu.dthFooterLine = menu:CreateTexture(nil, "BORDER")
    menu.dthFooterLine:SetPoint("BOTTOMLEFT", footer, "TOPLEFT"); menu.dthFooterLine:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT")
    menu.dthFooterLine:SetHeight(1); menu.dthFooterLine:SetColorTexture(unpack(C.edge))
    local close = Flat(menu, "X", 20, 18)
    close.hl:SetColorTexture(0.85, 0.2, 0.2, 0.45) -- red on hover: it closes
    close:SetPoint("TOPRIGHT", -4, -5)
    close:SetScript("OnClick", function() menu:Hide() end)
    close:SetScript("OnEnter", function(self) ShowTip(self, L["Close (Esc). /dth opens it again."]) end)
    close:SetScript("OnLeave", function() GameTooltip:Hide() end)
    for _, name in ipairs(TABS) do
        local tab = Flat(menu, name == "Class" and ((UnitClass and UnitClass("player")) or L["Class"]) or L[name], 70, 20)
        tab.isTab = true
        tab.classTab = name == "Class" or nil
        for _, t in ipairs(tab.edges) do t:Hide() end -- tabs sit flat on the strip, no box
        -- A tab squeezed below its name's width shows the full name on hover.
        tab:SetScript("OnEnter", function(self) if rawget(self, "cut") then ShowTip(self, self:GetText()) end end)
        tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
        tab.mark = tab:CreateTexture(nil, "ARTWORK")
        tab.mark:SetPoint("BOTTOMLEFT"); tab.mark:SetPoint("BOTTOMRIGHT"); tab.mark:SetHeight(2)
        tab.mark:SetColorTexture(1, 0.82, 0, 1)
        tab:SetScript("OnClick", function() ShowTab(name) end)
        tabButtons[name] = tab
    end

    BuildPages()
    pcall(SkinTree, menu)

    -- Bottom row, on every tab: the minimap button and Edit mode.
    local mini = Flat(menu, L["Minimap button"], 100, 18)
    mini:SetPoint("BOTTOMLEFT", 6, 6)
    mini:SetScript("OnClick", function()
        DB().minimap = DB().minimap or {}
        DB().minimap.hide = not DB().minimap.hide
        if DufforthTweaksHelperMinimapButton then DufforthTweaksHelperMinimapButton:SetShown(not DB().minimap.hide) end
        RefreshMenu()
    end)
    mini:SetScript("OnEnter", function(self) ShowTip(self, L["Shows or hides the minimap button (green: shown). Left-click on it opens this window, right-click the disenchant list, drag moves it. If hidden, type /dufforth."]) end)
    mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
    chrome[#chrome + 1] = function() SetOn(mini, not (DB().minimap or {}).hide) end
    -- Edit mode: every on-screen piece shows with a green frame to drag, then lock them in one click.
    local move = Flat(menu, L["Move pieces"], 90, 18)
    move:SetPoint("LEFT", mini, "RIGHT", 4, 0)
    move:SetScript("OnClick", function()
        if not DufforthTweaksHelper.SetEditMode(not DufforthTweaksHelper.EditMode()) then
            ShowTip(move, L["Not in combat: some pieces are locked by the game during fights."])
        end
        RefreshMenu()
    end)
    move:SetScript("OnEnter", function(self) ShowTip(self, L["Shows the warrior icon, the eat button and the spell notice with a green frame so you can drag them where you like. Click again to lock them. /dth move does the same."]) end)
    move:SetScript("OnLeave", function() GameTooltip:Hide() end)
    chrome[#chrome + 1] = function()
        local on = DufforthTweaksHelper.EditMode()
        move:SetText(on and L["Lock pieces"] or L["Move pieces"]); SetOn(move, on)
    end

    -- Any size: drag the corner. Lists show as many rows as fit; the size is remembered.
    menu:SetResizable(true)
    if menu.SetResizeBounds then menu:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    elseif menu.SetMinResize then menu:SetMinResize(MIN_W, MIN_H); menu:SetMaxResize(MAX_W, MAX_H) end
    local grip = CreateFrame("Button", nil, menu)
    grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() menu:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        menu:StopMovingOrSizing()
        ApplySize(menu:GetWidth(), menu:GetHeight())
    end)
    grip:SetScript("OnEnter", function(self) ShowTip(self, L["Drag to make the window bigger or smaller."]) end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)

    if DB().menuTab == "Warrior" then DB().menuTab = "Class" end -- the Warrior tab became your class's tab
    if DB().menuTab == "Crafting" then DB().menuTab = "Disenchant"; DB().deView = "craft" end -- merged
    if DB().menuTab == "Gather" then DB().menuTab = nil end -- removed
    if DB().menuTab == "Leveling" then DB().menuTab = "Professions" end -- renamed (user, 2026-11-27)
    if DB().classView == "rested" then DB().classView = nil end -- moved to the Alts tab
    ShowTab(pages[DB().menuTab or ""] and DB().menuTab or "Professions")
end

local TAB_NAMES = { disenchant = "Disenchant", crafting = "Disenchant", leveling = "Professions", professions = "Professions",
    profession = "Professions", prof = "Professions", zone = "Zone",
    grind = "Grind", fishing = "Fishing", fish = "Fishing", warrior = "Class", druid = "Class", class = "Class", consumables = "Class", gear = "Class", levellog = "Class", log = "Class", rested = "Alts", alts = "Alts" }
local function ToggleMenu(tab)
    if not menu then Build() end
    if tab and TAB_NAMES[tab] then
        if (tab == "warrior" or tab == "druid") and classViews.macro then ShowClassView("macro")
        elseif (tab == "consumables" or tab == "gear") and classViews[tab] then ShowClassView(tab)
        elseif (tab == "levellog" or tab == "log") and classViews.log then ShowClassView("log")
        elseif tab == "crafting" then ShowDisenchantView("craft")
        elseif tab == "disenchant" then ShowDisenchantView("settings") end
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
    GameTooltip:AddLine(L["Disenchanting, crafting, leveling and class help"], 0.7, 0.7, 0.7)
    GameTooltip:AddDoubleLine(L["Disenchant advice"], State(DB().showDisenchant ~= false), 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Left-click: open the window   Right-click: disenchant list"], 0.7, 0.7, 0.7)
    GameTooltip:AddLine(L["Minimized guide: click its round guide icon on your screen"], 0.7, 0.7, 0.7)
    GameTooltip:AddLine(L["Drag: move this button"], 0.7, 0.7, 0.7)
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
    if icon:SetTexture(ICON) == false then icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end -- the icon file loads after a full game restart
    -- While the guide is minimized, the current step's icon rides on the button (dynamic, like the guide's icon).
    local badge = button:CreateTexture(nil, "OVERLAY", nil, 2)
    badge:SetSize(12, 12); badge:SetPoint("BOTTOMRIGHT", -6, 7); badge:Hide()
    if badge.SetMask then badge:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask") end -- round, like the button
    DufforthTweaksHelperMinimap_SetBadge = function(texture)
        badge:SetTexture(texture); badge:SetShown(texture ~= nil)
    end
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53); border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button:SetScript("OnClick", function(_, mouse)
        -- Left-click always opens the window (user, 2026-11-27); the minimized guide opens from its round icon.
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
    text:SetText(L["Everything is in the Dufforth Tweaks Helper window: Disenchant (with Enchanting), Professions, Zone and a tab for your class (consumables, and the macro for warriors)."])
    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(160, 24); open:SetPoint("TOPLEFT", 16, -40); open:SetText(L["Open the window"])
    open:SetScript("OnClick", function() if not menu or not menu:IsShown() then ToggleMenu() end end)
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(panel, panel.name))
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

DufforthTweaksHelperMenu_Toggle = ToggleMenu
DufforthTweaksHelperMenu_ApplySize = function(w, h) if not menu then Build() end; ApplySize(w, h) end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
pcall(loader.RegisterEvent, loader, "SKILL_LINES_CHANGED")
loader:SetScript("OnEvent", function(_, event)
    if event == "SKILL_LINES_CHANGED" then
        if menu and menu:IsShown() then LayoutTabs() end
        return
    end
    BuildMinimapButton()
    RegisterOptions()
end)
