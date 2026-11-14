-- Shared helpers and the /dufforth command.

DufforthTweaksHelper = DufforthTweaksHelper or {}
local PREFIX = "|cff66ccffDufforth Tweaks Helper:|r "
DufforthTweaksHelper.PREFIX = PREFIX

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. message)
end
DufforthTweaksHelper.Print = Print

-- ---- Edit mode: every on-screen piece the addon shows, placed in one go ----
-- Each module registers { label, get = function() -> frame, enter, leave }: enter shows the piece (with
-- example content if it has nothing to show) and makes it draggable; leave puts it back to normal.
-- (User picked this, 2026-11-13, after moving the spell notice and the eat button one by one.)
local movables, editing = {}, false
function DufforthTweaksHelper.RegisterMovable(m) movables[#movables + 1] = m end
function DufforthTweaksHelper.EditMode() return editing end

local function Overlay(frame, label)
    local existing = rawget(frame, "dthOverlay")
    if existing then return existing end
    local o = CreateFrame("Frame", nil, frame)
    o:SetAllPoints(frame)
    o:SetFrameLevel((frame.GetFrameLevel and frame:GetFrameLevel() or 1) + 5)
    local fill = o:CreateTexture(nil, "OVERLAY")
    fill:SetAllPoints(o); fill:SetColorTexture(0.2, 0.8, 0.3, 0.3)
    local text = o:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("BOTTOM", o, "TOP", 0, 2); text:SetText(label .. " |cffaaaaaa(drag)|r")
    o:Hide()
    frame.dthOverlay = o
    return o
end

-- on = true shows every piece to drag; false locks them. Not in combat (some pieces are secure).
function DufforthTweaksHelper.SetEditMode(on)
    if InCombatLockdown and InCombatLockdown() then return false end
    editing = on and true or false
    for _, m in ipairs(movables) do
        local ok, frame = pcall(m.get)
        if ok and frame then
            local o = Overlay(frame, m.label)
            if editing then pcall(m.enter, frame); o:Show() else o:Hide(); pcall(m.leave, frame) end
        end
    end
    return true
end

-- ---- List rows: section titles and the items under them ----
-- User (2026-11-13): sections had no icon, didn't look like titles, and items didn't look like they
-- belonged to them. Titles get a gold band and a +/- icon; items are indented with a gold guide line.
local function Decor(line)
    local d = rawget(line, "dthDecor")
    if d then return d end
    d = {}
    d.band = line:CreateTexture(nil, "BACKGROUND")
    d.band:SetPoint("TOPLEFT", 0, -2); d.band:SetPoint("BOTTOMRIGHT", 0, 2)
    -- A dark neutral strip, not gold: a gold band looked like the hover highlight (user, 2026-11-13).
    d.band:SetColorTexture(0, 0, 0, 0.55)
    d.edge = line:CreateTexture(nil, "BORDER")
    d.edge:SetPoint("BOTTOMLEFT", 0, 2); d.edge:SetPoint("BOTTOMRIGHT", 0, 2); d.edge:SetHeight(1)
    d.edge:SetColorTexture(1, 0.82, 0, 0.7)
    d.guide = line:CreateTexture(nil, "BORDER")
    d.guide:SetPoint("TOPLEFT", 9, 0); d.guide:SetPoint("BOTTOMLEFT", 9, 0); d.guide:SetWidth(2)
    d.guide:SetColorTexture(1, 0.82, 0, 0.35)
    line.dthDecor = d
    return d
end

-- kind: "header" (a section title; closed = folded) or "child" (an item in a section).
function DufforthTweaksHelper.StyleRow(line, kind, closed)
    local d = Decor(line)
    local header = kind == "header"
    d.band:SetShown(header); d.edge:SetShown(header); d.guide:SetShown(not header)
    line.icon:ClearAllPoints()
    if header then
        line.icon:SetSize(16, 16); line.icon:SetPoint("LEFT", 6, 0)
        line.icon:SetTexture(closed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
        line.icon:Show()
        line.name:SetPoint("TOPLEFT", 28, -3); line.sub:SetPoint("BOTTOMLEFT", 28, 4)
    else
        line.icon:SetSize(24, 24); line.icon:SetPoint("LEFT", 16, 0)
        line.name:SetPoint("TOPLEFT", 46, -3); line.sub:SetPoint("BOTTOMLEFT", 46, 4)
    end
end

-- A scroll arrow drawn with the game's own textures: the game's fonts have no ▲ or ▼, so text
-- arrows show as empty squares. direction: "up" or "down".
function DufforthTweaksHelper.ArrowButton(parent, direction, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(22, 22)
    local base = "Interface\\Buttons\\UI-ScrollBar-Scroll" .. (direction == "up" and "Up" or "Down") .. "Button-"
    button:SetNormalTexture(base .. "Up")
    button:SetPushedTexture(base .. "Down")
    button:SetDisabledTexture(base .. "Disabled")
    button:SetHighlightTexture(base .. "Highlight", "ADD")
    if onClick then button:SetScript("OnClick", onClick) end
    return button
end

-- "forever.pvp.horde.us", the market name the Forever Prices page and the bundled prices use.
function DufforthTweaksHelper.MarketName()
    local realm = string.lower(GetRealmName() or "")
    local ruleset = "normal"
    if string.find(realm, "pvp", 1, true) then
        ruleset = "pvp"
    elseif string.find(realm, "%f[%a]rp%f[%A]") then
        ruleset = "rp"
    end
    local faction = string.lower(UnitFactionGroup("player") or "neutral")
    local region = GetCurrentRegion and GetCurrentRegion() == 3 and "eu" or "us"
    return string.format("forever.%s.%s.%s", ruleset, faction, region)
end

-- "Name-Realm", to keep each character's known recipes apart.
function DufforthTweaksHelper.CharacterKey()
    return (UnitName and UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
end

-- Skill line numbers the game uses for each profession.
local SKILL_LINES = {
    [171] = "Alchemy", [164] = "Blacksmithing", [333] = "Enchanting", [202] = "Engineering", [165] = "Leatherworking",
    [197] = "Tailoring", [185] = "Cooking", [129] = "First Aid", [186] = "Mining", [182] = "Herbalism",
    [356] = "Fishing", [393] = "Skinning",
}
local BY_NAME = {}
for _, name in pairs(SKILL_LINES) do BY_NAME[name] = true end

-- Your professions and skill, bonuses included: { Tailoring = 150, ... }, or nil if the game can't tell.
function DufforthTweaksHelper.Professions()
    local out, read = {}, false
    if GetProfessions and GetProfessionInfo then
        read = true
        local a, b, c, d, e, f = GetProfessions()
        local list = { a, b, c, d, e, f }
        for i = 1, 6 do
            if list[i] then
                local name, _, rank, _, _, _, line, modifier = GetProfessionInfo(list[i])
                name = SKILL_LINES[line] or name
                if name and rank then out[name] = rank + (modifier or 0) end
            end
        end
    end
    if not next(out) and GetNumSkillLines and GetSkillLineInfo then
        read = true
        for i = 1, GetNumSkillLines() do
            local name, header, _, rank, _, modifier = GetSkillLineInfo(i)
            if not header and name and BY_NAME[name] and rank then out[name] = rank + (modifier or 0) end
        end
    end
    return read and out or nil
end

SLASH_DUFFORTHTWEAKSHELPER1 = "/dufforth"
SLASH_DUFFORTHTWEAKSHELPER2 = "/dth"
local RunCommand
-- Any error prints in chat instead of leaving the command stuck in the chat box.
SlashCmdList.DUFFORTHTWEAKSHELPER = function(input)
    local ok, err = pcall(RunCommand, input)
    if not ok then
        Print("|cffff5555that command hit an error. Please send this text:|r " .. tostring(err))
    end
end

RunCommand = function(input)
    local command, option = string.match(string.lower(input or ""), "^%s*(%S*)%s*(%S*)")
    if command == "" or command == "menu" then
        if DufforthTweaksHelperMenu_Toggle then DufforthTweaksHelperMenu_Toggle() end
    elseif command == "guide" then
        if DufforthTweaksHelperGuideUI then DufforthTweaksHelperGuideUI.Toggle()
        else Print("the leveling guide needs a full game restart (new files).") end
    elseif command == "auto" then
        if DufforthTweaksHelperQuestAuto then
            DufforthTweaksHelperQuestAuto.SetEnabled(not DufforthTweaksHelperQuestAuto.Enabled())
            if DufforthTweaksHelperGuideUI then DufforthTweaksHelperGuideUI.Refresh() end
        end
    elseif command == "arrow" then
        if DufforthTweaksHelperGuideUI then DufforthTweaksHelperGuideUI.SetArrowShown(not (DufforthTweaksHelperDB.guide or {}).arrow) end
    elseif command == "move" then
        if not DufforthTweaksHelper.SetEditMode(not DufforthTweaksHelper.EditMode()) then Print("on-screen pieces can't move in combat.") end
    elseif command == "crafting" or command == "leveling" or command == "warrior"
        or command == "class" or command == "consumables" or command == "zone" or command == "gear" then
        if DufforthTweaksHelperMenu_Toggle then DufforthTweaksHelperMenu_Toggle(command) end
    elseif command == "shopping" then
        if DufforthTweaksHelperLeveling then DufforthTweaksHelperLeveling.ShowShopping() end
    elseif command == "de" then
        DufforthTweaksHelperDE.Toggle(option)
    elseif command == "disenchant" then
        DufforthTweaksHelperAutoDE.Toggle()
    else
        Print("/dufforth - open the window (also the minimap button). /dth works too.")
        Print("/dufforth crafting, /dufforth leveling, /dufforth zone, /dufforth class (consumables), /dufforth gear, /dufforth warrior - open it on that tab")
        Print("/dufforth shopping - open the Leveling tab's shopping list")
        Print("/dufforth guide - show or hide the leveling guide (Horde 1-60)")
        Print("/dufforth arrow - show or hide the guide's waypoint arrow")
        Print("/dufforth auto - turn auto accept and turn-in of quests on or off (hold Shift to do one yourself)")
        Print("/dufforth move - show every on-screen piece (warrior icon, eat button, spell notice) to drag; again to lock")
        Print("/dufforth de - show or hide disenchant advice in item tooltips")
        Print("/dufforth disenchant - open the list that disenchants BoE gear, one click per item")
        Print("/nk - herb and ore commands; /nk help lists them")
    end
end

-- Older versions saved things this one no longer uses. Drop them.
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= "DufforthTweaksHelper" then return end
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    DufforthTweaksHelperDB.scans, DufforthTweaksHelperDB.scanList, DufforthTweaksHelperDB.autoScan = nil, nil, nil
    DufforthTweaksHelperDB.secondsPerRequest = nil
    self:UnregisterEvent("ADDON_LOADED")
end)
