-- Dufforth Tweaks Helper, leveling guide: the view and controller.
--
-- GameAdapter reads the real game for the model (Guide.lua). The guide box (dark, like Zygor) shows:
--   a top strip with < step number > (Back / Skip), a map pin and close button; the active steps as
--   blocks (Step N and where, an action icon, what to do with names highlighted, the game's own
--   progress lines, advice), the current one colored by what you do (kill red, loot amber...); a green
--   bar with your progress through this part of the route; class or dungeon quests to pick up; a bar
--   named by levels and zone ("12-16 The Barrens") with Done / Next toggles and < > to browse parts;
--   that part's steps as a list that scrolls with the mouse wheel.
-- The box moves (drag, or Move pieces) and resizes from its corner. A waypoint arrow points at the
-- current step with distance and time. Each new step gets a map pin. Quest, level and zone events
-- refresh it.

local UI = {}
DufforthTweaksHelperGuideUI = UI

local function DB()
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    local g = DufforthTweaksHelperDB.guide or {}
    DufforthTweaksHelperDB.guide = g
    if g.shown == nil then g.shown = true end
    if g.showDone == nil then g.showDone = true end
    if g.listV ~= 2 then g.showDone, g.listV = true, 2 end -- 4.28: the list shows the steps behind you (user)
    if g.showNext == nil then g.showNext = true end
    if g.arrow == nil then g.arrow = true end
    -- 4.22.0 saved the size the game restored from an older, smaller box: start fresh once.
    if g.sizeV ~= 2 then g.size, g.sizeV = nil, 2 end
    g.routes = g.routes or {}
    return g
end

-- ---- The game, as the model needs it ----
local logCache

local function LogIds()
    if logCache then return logCache end
    local ids = {}
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID then ids[#ids + 1] = info.questID end
        end
    end
    logCache = ids
    return ids
end

function UI.GameAdapter()
    local inLog = {}
    for _, id in ipairs(LogIds()) do inLog[id] = true end
    local race
    if UnitRace then _, race = UnitRace("player") end
    local classID
    if UnitClass then classID = select(3, UnitClass("player")) end
    return {
        level = function() return UnitLevel and UnitLevel("player") or 1 end,
        classBit = function() return classID and 2 ^ (classID - 1) or 1 end,
        raceBit = function() return DufforthTweaksHelperGuide.RACE_BITS[race] or 2 end,
        done = function(id) return C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id) and true or false end,
        inLog = function(id) return inLog[id] == true end,
        complete = function(id) return C_QuestLog and C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) and true or false end,
        zone = function() return (GetRealZoneText and GetRealZoneText()) or "" end,
        -- The game's progress lines for a quest in your log: { {text, finished} }.
        objectives = function(id)
            if not inLog[id] or not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return nil end
            local ok, list = pcall(C_QuestLog.GetQuestObjectives, id)
            return ok and type(list) == "table" and #list > 0 and list or nil
        end,
        -- One objective by its name in the game's line ("6/12 Raptor Head"): true/false, nil if not found.
        objectiveDone = function(id, name)
            if not inLog[id] or not name or not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return nil end
            local ok, list = pcall(C_QuestLog.GetQuestObjectives, id)
            if not ok or type(list) ~= "table" then return nil end
            for _, o in ipairs(list) do
                if o.text and string.find(o.text, name, 1, true) then return o.finished and true or false end
            end
            return nil
        end,
        -- A flight path you have: you talked to that flight master, or you know as many paths in its zone
        -- as it has Horde flight masters (the flight map names a path's zone, not its flight master).
        flightKnown = function(zone, x, y)
            local known = DB().flights
            if not known then return false end
            for _, spot in ipairs(known.spots or {}) do
                if spot[1] == zone and math.abs(spot[2] - x) <= 8 and math.abs(spot[3] - y) <= 8 then return true end
            end
            local have, total = 0, 0
            for name in pairs(known.names or {}) do
                if string.match(name, ",%s*(.-)%s*$") == zone then have = have + 1 end
            end
            local travel = DufforthTweaksHelperGuideData and DufforthTweaksHelperGuideData.travel
            for _, f in ipairs(travel and travel.flights or {}) do
                if f[2] == zone then total = total + 1 end
            end
            return total > 0 and have >= total
        end,
        hasItem = function(id) return GetItemCount ~= nil and (GetItemCount(id) or 0) > 0 end,
        logIds = LogIds,
    }
end

-- Talking to a flight master: remember the paths you have and where you stand.
function UI.LearnFlights()
    local known = DB().flights or { spots = {}, names = {} }
    DB().flights = known
    known.spots, known.names = known.spots or {}, known.names or {}
    if NumTaxiNodes and TaxiNodeName then
        for i = 1, NumTaxiNodes() or 0 do
            local kind = TaxiNodeGetType and TaxiNodeGetType(i)
            if kind == "CURRENT" or kind == "REACHABLE" then known.names[TaxiNodeName(i)] = true end
        end
    end
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
    local info = map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    local x, y
    if pos then if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end end
    if x and info and info.name then known.spots[#known.spots + 1] = { info.name, x * 100, y * 100 } end
end

-- The route you follow: a questline guide you picked, or the leveling route for your race.
function UI.RouteName()
    local picked = DB().guideName
    local data = DufforthTweaksHelperGuideData
    if picked and data and data.routes and data.routes[picked] then return picked end
    local race
    if UnitRace then _, race = UnitRace("player") end
    return DufforthTweaksHelperGuide.ROUTE_FOR_RACE[race] or "Durotar"
end

function UI.SelectGuide(name)
    DB().guideName = name
    UI.follow, UI.scrolled, UI.section, UI.override, UI.lastCurrent = true, false, nil, nil, nil
    pinned = nil
    if box and box.guideMenu then box.guideMenu:Hide() end
    UI.Refresh()
end

local function Model(adapter)
    local name = UI.RouteName()
    local saved = DB().routes[name] or {}
    DB().routes[name] = saved
    return DufforthTweaksHelperGuide.NewModel(DufforthTweaksHelperGuideData, name, adapter, saved)
end

-- ---- Map pin ----
local pinned

local function Pin(model, i)
    local zone, x, y, map = model:Place(i)
    if not (map and x and y) or pinned == i then return end
    pinned = i
    pcall(function()
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x / 100, y / 100))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    end)
end

-- ---- Look ----
local ACTIVE, ROWS, PAD, LINE, BAR, STRIP, PROGRESS, BEHIND = 2, 40, 8, 14, 22, 24, 12, 3
local WIDTH, HEIGHT, MIN_W, MIN_H, MAX_W, MAX_H = 340, 440, 220, 70, 800, 1000
local DONE_MARK, WAIT_MARK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t ", "|TInterface\\RaidFrame\\ReadyCheck-Waiting:12:12|t "
local WHITE = "Interface\\Buttons\\WHITE8x8"
-- What you do, shown as a colored stripe and label beside the text (text stays on a neutral dark
-- background: user, 2026-11-13, colored bands made names hard to read). Colors pass 4.5:1 on the bands.
local KIND = {
    kill = { 1, 0.42, 0.42, "KILL" }, grind = { 1, 0.42, 0.42, "GRIND" }, loot = { 1, 0.66, 0.3, "LOOT" },
    use = { 0.35, 0.85, 0.9, "USE" }, explore = { 0.35, 0.85, 0.9, "EXPLORE" }, accept = { 1, 0.82, 0, "PICK UP" },
    turnin = { 0.4, 0.92, 0.45, "TURN IN" }, travel = { 0.5, 0.7, 1, "TRAVEL" }, flight = { 0.5, 0.7, 1, "FLIGHT PATH" },
}
local BAND_CURRENT, BAND_NEXT = { 0.17, 0.17, 0.19 }, { 0.13, 0.13, 0.145 }
-- A clean narrow font with a shadow (the game's own Arial Narrow).
local FONT = "Fonts\\ARIALN.TTF"
local function Font(fs, size)
    if fs.SetFont then fs:SetFont(FONT, size, "") end
    if fs.SetShadowOffset then fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 1) end
    return fs
end

-- A FontString's height once wrapped (an estimate from its line count when the game can't say yet).
local function Height(fs, text)
    if not text or text == "" then return 0 end
    local h = fs.GetStringHeight and fs:GetStringHeight()
    if type(h) == "number" and h > 0 then return h end
    local _, breaks = string.gsub(text, "\n", "")
    return LINE * (breaks + 1)
end

-- A flat dark button with text, or with an icon (texture path).
local function Flat(parent, text, width, height, icon)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height or 18)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints(); b.bg:SetColorTexture(0.22, 0.22, 0.24, 0.95)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.15)
    if icon then
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("CENTER"); b.icon:SetSize((height or 18) - 2, (height or 18) - 2); b.icon:SetTexture(icon)
    else
        b:SetNormalFontObject("GameFontHighlightSmall")
        b:SetText(text)
    end
    return b
end

local function SetOn(b, on)
    if on then b.bg:SetColorTexture(0.12, 0.45, 0.2, 0.95) else b.bg:SetColorTexture(0.22, 0.22, 0.24, 0.95) end
end

local function Tip(b, text)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(type(text) == "function" and text() or text, 1, 1, 1, 1, true); GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- What a step says: icon and action, the game's progress lines with a check or waiting mark, advice, kind.
local function StepText(model, i, adapter)
    local step = model.steps[i]
    local S = DufforthTweaksHelperGuide.STEP
    local objectives = step[S.KIND] == "do" and adapter.objectives(step[S.QUEST]) or nil
    local d = DufforthTweaksHelperGuide.Describe(model, i, objectives)
    local lines = {}
    for _, line in ipairs(d.lines) do
        lines[#lines + 1] = line.finished and (DONE_MARK .. "|cff80ff80" .. line.text .. "|r") or (WAIT_MARK .. line.text)
    end
    return "|T" .. d.icon .. ":16:16|t " .. (d.action or ""), table.concat(lines, "\n"), d.note, d.kind
end

-- A block of steps done as one: their actions and lines together, the first one's kind and advice.
local function GroupText(model, group, adapter)
    local actions, all, note, kind = {}, {}, nil, nil
    for k, i in ipairs(group) do
        local action, lines, n, kd = StepText(model, i, adapter)
        actions[#actions + 1] = action
        if lines ~= "" then all[#all + 1] = lines end
        if k == 1 then note, kind = n, kd end
    end
    return table.concat(actions, "\n"), table.concat(all, "\n"), note, kind
end

local function Where(model, i)
    local zone, x, y = model:Place(i)
    return string.format("|cffaaaaaa%s%s|r", zone or "?", x and string.format(" %d, %d", math.floor(x + 0.5), math.floor(y + 0.5)) or "")
end

-- ---- The box ----
local box

-- One active step: header (Step N, where), action, progress lines, advice.
local function Block(parent)
    local b = CreateFrame("Frame", nil, parent)
    b.band = b:CreateTexture(nil, "BACKGROUND")
    b.band:SetAllPoints(); b.band:SetColorTexture(BAND_NEXT[1], BAND_NEXT[2], BAND_NEXT[3], 1)
    b.accent = b:CreateTexture(nil, "BORDER")
    b.accent:SetPoint("TOPLEFT"); b.accent:SetPoint("BOTTOMLEFT"); b.accent:SetWidth(3); b.accent:SetColorTexture(1, 1, 1, 1)
    b.header = Font(b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"), 11)
    b.header:SetPoint("TOPLEFT", 8, -4); b.header:SetJustifyH("LEFT")
    b.action = Font(b:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), 14)
    b.action:SetPoint("TOPLEFT", b.header, "BOTTOMLEFT", 0, -3); b.action:SetJustifyH("LEFT")
    if b.action.SetSpacing then b.action:SetSpacing(2) end
    b.lines = Font(b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 12)
    b.lines:SetPoint("TOPLEFT", b.action, "BOTTOMLEFT", 20, -3); b.lines:SetJustifyH("LEFT")
    b.advice = Font(b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 12)
    b.advice:SetPoint("TOPLEFT", b.lines, "BOTTOMLEFT", -20, -3); b.advice:SetJustifyH("LEFT")
    return b
end

-- One list row: the step's text and its number on the right.
local function Row(parent)
    local r = CreateFrame("Frame", nil, parent)
    r.band = r:CreateTexture(nil, "BACKGROUND")
    r.band:SetAllPoints(); r.band:SetColorTexture(1, 1, 1, 0)
    r.num = Font(r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), 11)
    r.num:SetPoint("TOPRIGHT", -4, -3); r.num:SetJustifyH("RIGHT"); r.num:SetTextColor(0.6, 0.6, 0.6)
    r.label = Font(r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 12)
    r.label:SetPoint("TOPLEFT", 24, -3); r.label:SetJustifyH("LEFT")
    -- Mark the step done (you did it without the guide), or undo it.
    r.check = CreateFrame("Button", nil, r)
    r.check:SetSize(16, 16); r.check:SetPoint("TOPLEFT", 3, -2)
    r.check.box = r.check:CreateTexture(nil, "ARTWORK"); r.check.box:SetAllPoints(); r.check.box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
    r.check.mark = r.check:CreateTexture(nil, "OVERLAY"); r.check.mark:SetAllPoints(); r.check.mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    r.check:SetScript("OnClick", function() if r.step then UI.ToggleStep(r.step) end end)
    r.check:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText("Mark this step done (you did it already), or click again to undo.", 1, 1, 1, 1, true); GameTooltip:Show()
    end)
    r.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.isHeader = false
    return r
end

-- Your size (width, and the most height the box takes).
local function Size(f)
    return f.w or WIDTH, f.h or HEIGHT
end

local function Box()
    if box then return box end
    local f = CreateFrame("Frame", "DufforthTweaksHelperGuideBox", UIParent, "BackdropTemplate")
    -- The game would restore an older box's size and place over ours: we keep them ourselves.
    if f.SetDontSavePosition then f:SetDontSavePosition(true) end
    local size = DB().size
    f.w, f.h = size and size[1] or WIDTH, size and size[2] or HEIGHT
    f:SetSize(f.w, f.h)
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -220, -180)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        f:SetBackdropColor(0.10, 0.10, 0.11, 0.93); f:SetBackdropBorderColor(0, 0, 0, 1)
    end
    f:SetMovable(true); f:SetClampedToScreen(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relative, x, y = self:GetPoint()
        DB().point = { point, relative, x, y }
    end)
    local p = DB().point
    if p then f:ClearAllPoints(); f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) end

    -- Resize from the bottom-right corner; only a size you drag is remembered.
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    elseif f.SetMinResize then f:SetMinResize(MIN_W, MIN_H); if f.SetMaxResize then f:SetMaxResize(MAX_W, MAX_H) end end
    f.grip = CreateFrame("Button", nil, f)
    f.grip:SetSize(16, 16); f.grip:SetPoint("BOTTOMRIGHT", -2, 2); f.grip:SetFrameLevel((f:GetFrameLevel() or 0) + 10)
    f.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    f.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    f.grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    -- Your size is the most the box takes; it shrinks to fit what it shows (user, 2026-11-13: the frame
    -- went past the content). While you drag, it is redrawn so you see what fits.
    f.grip:SetScript("OnMouseDown", function()
        f.sizing = true
        f:SetHeight(f.h) -- drag from your size, not the fitted one
        f:StartSizing("BOTTOMRIGHT")
    end)
    f.grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        f.sizing = false
        DB().size = { math.floor(f.w + 0.5), math.floor(f.h + 0.5) }
        UI.Refresh()
    end)
    local lastDraw = 0
    f:SetScript("OnSizeChanged", function(self, w, h)
        if not self.sizing or type(w) ~= "number" or type(h) ~= "number" then return end -- only a size you drag
        self.w, self.h = w, h
        local now = GetTime and GetTime() or 0
        if now - lastDraw >= 0.05 or now == 0 then lastDraw = now; UI.Refresh() end
    end)

    -- Top strip: < step > , map pin, close.
    f.strip = f:CreateTexture(nil, "BORDER")
    f.strip:SetPoint("TOPLEFT", 1, -1); f.strip:SetPoint("TOPRIGHT", -1, -1); f.strip:SetHeight(STRIP)
    f.strip:SetColorTexture(0, 0, 0, 0.85)
    f.back = Flat(f, nil, 22, 18, "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up"); f.back:SetPoint("TOPLEFT", 4, -4)
    f.stepNum = Font(f:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), 14)
    f.stepNum:SetPoint("LEFT", f.back, "RIGHT", 6, 0)
    f.skip = Flat(f, nil, 22, 18, "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"); f.skip:SetPoint("LEFT", f.stepNum, "RIGHT", 6, 0)
    -- Guides: the leveling route or a questline guide (attunements, Cozy Sleeping Bag).
    f.guides = Flat(f, "Guides", 50, 18); f.guides:SetPoint("LEFT", f.skip, "RIGHT", 8, 0)
    f.guideMenu = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.guideMenu:SetPoint("TOPLEFT", f.guides, "BOTTOMLEFT", 0, -2); f.guideMenu:SetSize(230, 20)
    f.guideMenu:SetFrameStrata("DIALOG")
    if f.guideMenu.SetBackdrop then
        f.guideMenu:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        f.guideMenu:SetBackdropColor(0.08, 0.08, 0.09, 0.97); f.guideMenu:SetBackdropBorderColor(0, 0, 0, 1)
    end
    f.guideMenu:Hide()
    f.guideRows = {}
    for k = 1, 10 do
        local r = CreateFrame("Button", nil, f.guideMenu)
        r:SetSize(226, 20); r:SetPoint("TOPLEFT", 2, -2 - (k - 1) * 20)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, 0.1)
        r.label = Font(r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 12)
        r.label:SetPoint("LEFT", 6, 0); r.label:SetJustifyH("LEFT")
        r:SetScript("OnClick", function(self) UI.SelectGuide(self.guide) end)
        r:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.title or "", 1, 0.82, 0); GameTooltip:AddLine(self.note or "", 1, 1, 1, true); GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:Hide()
        f.guideRows[k] = r
    end
    f.guides:SetScript("OnClick", function() UI.ToggleGuideMenu() end)
    Tip(f.guides, "Choose a guide: fast leveling (the default), or a questline like an attunement or the Cozy Sleeping Bag.")
    f.routePct = Font(f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), 11); f.routePct:SetTextColor(0.65, 0.65, 0.65)
    f.routePct:SetPoint("LEFT", f.skip, "RIGHT", 8, 0)
    f.hide = Flat(f, "X", 20, 18); f.hide:SetPoint("TOPRIGHT", -4, -4)
    f.pin = Flat(f, nil, 20, 18, "Interface\\Icons\\INV_Misc_Map_01"); f.pin:SetPoint("RIGHT", f.hide, "LEFT", -3, 0)
    f.arrowToggle = Flat(f, nil, 20, 18, "Interface\\Minimap\\MinimapArrow"); f.arrowToggle:SetPoint("RIGHT", f.pin, "LEFT", -3, 0)
    f.autoToggle = Flat(f, "Auto", 36, 18); f.autoToggle:SetPoint("RIGHT", f.arrowToggle, "LEFT", -3, 0)

    -- Active steps, the progress bar, then the extras line.
    f.blocks = {}
    for k = 1, ACTIVE do f.blocks[k] = Block(f) end
    f.title, f.step = f.blocks[1].header, f.blocks[1].action -- the current step
    -- Start quest: uses the quest's item from your bags (a secure button: items are used only from a click).
    f.useItem = CreateFrame("Button", "DufforthTweaksHelperGuideUseItem", f, "SecureActionButtonTemplate")
    f.useItem:SetSize(96, 20); f.useItem:SetPoint("TOPRIGHT", f.blocks[1], "TOPRIGHT", -4, -3)
    if f.useItem.RegisterForClicks then f.useItem:RegisterForClicks("AnyUp", "AnyDown") end
    f.useItem.bg = f.useItem:CreateTexture(nil, "BACKGROUND")
    f.useItem.bg:SetAllPoints(); f.useItem.bg:SetColorTexture(0.12, 0.45, 0.2, 0.95)
    f.useItem.hl = f.useItem:CreateTexture(nil, "HIGHLIGHT")
    f.useItem.hl:SetAllPoints(); f.useItem.hl:SetColorTexture(1, 1, 1, 0.15)
    f.useItem:SetNormalFontObject("GameFontHighlightSmall"); f.useItem:SetText("Start quest")
    f.useItem:Hide()
    Tip(f.useItem, "Use the item: its quest window opens (and is accepted when Auto is on).")
    f.blocks[1].band:SetColorTexture(BAND_CURRENT[1], BAND_CURRENT[2], BAND_CURRENT[3], 1)
    f.along = Font(f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 12) -- along the way
    f.along:SetJustifyH("LEFT")
    f.progress = CreateFrame("StatusBar", nil, f)
    f.progress:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    f.progress:SetStatusBarColor(0.11, 0.5, 0.2); f.progress:SetMinMaxValues(0, 1) -- dark enough for white text
    f.progress.bg = f.progress:CreateTexture(nil, "BACKGROUND")
    f.progress.bg:SetAllPoints(); f.progress.bg:SetColorTexture(0, 0, 0, 0.6)
    f.progress.label = Font(f.progress:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 11)
    f.progress.label:SetPoint("CENTER")
    if f.progress.EnableMouse then f.progress:EnableMouse(true) end
    Tip(f.progress, "Zone: how much of this part of the route (levels and zone) is done. Route: how much of the whole 1-60 guide is done.")
    f.note = Font(f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 12) -- (unused since 4.27: extra rows)
    -- Class, dungeon and gray quests as rows you can hover and click (user, 2026-11-13).
    f.extraRows = {}
    for k = 1, 16 do
        local r = CreateFrame("Button", nil, f)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, 0.08)
        r.label = Font(r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 12)
        r.label:SetPoint("TOPLEFT", 2, -1); r.label:SetJustifyH("LEFT")
        r:SetScript("OnClick", function(self) UI.ExtraClicked(self.item) end)
        r:SetScript("OnEnter", function(self)
            local item = self.item
            if not item then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(item.tipTitle or "", 1, 0.82, 0)
            for _, line in ipairs(item.tip or {}) do GameTooltip:AddLine(line, 1, 1, 1, true) end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:Hide()
        f.extraRows[k] = r
    end
    f.note:SetJustifyH("LEFT")

    -- Section bar: levels and zone, Done / Next toggles, < > to browse.
    f.bar = CreateFrame("Frame", nil, f)
    f.bar.band = f.bar:CreateTexture(nil, "BACKGROUND")
    f.bar.band:SetAllPoints(); f.bar.band:SetColorTexture(0.17, 0.17, 0.19, 1)
    f.bar.label = Font(f.bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"), 12)
    f.bar.label:SetPoint("LEFT", 6, 0); f.bar.label:SetJustifyH("LEFT")
    if f.bar.label.SetWordWrap then f.bar.label:SetWordWrap(false) end
    f.nextSection = Flat(f.bar, nil, 18, 18, "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"); f.nextSection:SetPoint("RIGHT", -2, 0)
    f.prevSection = Flat(f.bar, nil, 18, 18, "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up"); f.prevSection:SetPoint("RIGHT", f.nextSection, "LEFT", -2, 0)
    f.nextToggle = Flat(f.bar, "Next", 34, 18); f.nextToggle:SetPoint("RIGHT", f.prevSection, "LEFT", -5, 0)
    f.doneToggle = Flat(f.bar, "Done", 34, 18); f.doneToggle:SetPoint("RIGHT", f.nextToggle, "LEFT", -2, 0)
    f.bar.label:SetPoint("RIGHT", f.doneToggle, "LEFT", -4, 0)

    -- The section's steps.
    f.list = CreateFrame("Frame", nil, f)
    f.list:EnableMouseWheel(true)
    f.rows = {}
    for k = 1, ROWS do f.rows[k] = Row(f.list) end
    f.empty = f.list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.empty:SetPoint("TOPLEFT", 4, -4); f.empty:SetJustifyH("LEFT")

    local function Follow() UI.follow, UI.scrolled = true, false; UI.Refresh() end
    f.skip:SetScript("OnClick", function() UI.model:Skip(); pinned = nil; UI.Refresh() end)
    f.back:SetScript("OnClick", function() UI.model:Back(); pinned = nil; UI.Refresh() end)
    f.pin:SetScript("OnClick", function() pinned = nil; local i = UI.model:Current(); if i then Pin(UI.model, i) end end)
    f.hide:SetScript("OnClick", function() UI.SetShown(false) end)
    f.arrowToggle:SetScript("OnClick", function() UI.SetArrowShown(not DB().arrow) end)
    f.autoToggle:SetScript("OnClick", function()
        local auto = DufforthTweaksHelperQuestAuto
        if auto then auto.SetEnabled(not auto.Enabled()) end
        UI.Refresh()
    end)
    f.doneToggle:SetScript("OnClick", function() DB().showDone = not DB().showDone; Follow() end)
    f.nextToggle:SetScript("OnClick", function() DB().showNext = not DB().showNext; Follow() end)
    f.prevSection:SetScript("OnClick", function() UI.Browse(-1) end)
    f.nextSection:SetScript("OnClick", function() UI.Browse(1) end)
    f.list:SetScript("OnMouseWheel", function(_, delta) UI.Scroll(-delta) end)

    Tip(f.back, "Back: bring back the step you skipped last.")
    Tip(f.skip, "Skip this step (and, for a pick-up, that quest's steps).")
    Tip(f.pin, "Put a pin on your map at this step.")
    Tip(f.arrowToggle, function() return DB().arrow and "Hide the waypoint arrow." or "Show the waypoint arrow." end)
    Tip(f.hide, "Hide the guide. /dth guide shows it again.")
    Tip(f.autoToggle, function()
        local on = DufforthTweaksHelperQuestAuto and DufforthTweaksHelperQuestAuto.Enabled()
        return (on and "Auto quests on: " or "Auto quests off: ") .. "accepts quests that fit and hands in finished ones; a choice of rewards waits for you. Hold Shift to do one yourself."
    end)
    Tip(f.doneToggle, function() return DB().showDone and "Hide the steps behind you." or "Show the steps behind you (checked)." end)
    -- Rows: a check box marks a step done by hand.
    Tip(f.nextToggle, function() return DB().showNext and "Hide the steps ahead (keep only the current one)." or "Show the steps ahead." end)
    Tip(f.prevSection, "Previous part of the route. A new step brings you back to yours.")
    Tip(f.nextSection, "Next part of the route. A new step brings you back to yours.")
    Tip(f.grip, "Drag to resize.")

    box = f
    if DufforthTweaksHelper and DufforthTweaksHelper.RegisterMovable then
        DufforthTweaksHelper.RegisterMovable({ label = "Leveling guide", get = function() return box end,
            enter = function(b) b:Show() end, leave = function() UI.Refresh() end })
    end
    return f
end

-- Extra lines: class quests, dungeon quests, gray quests to abandon.
local function Extras(model)
    local parts = {}
    local class = model:ClassQuests()[1]
    if class then parts[#parts + 1] = string.format("|cffc080ffClass quest:|r %s (%s)", class.title, class.giver) end
    local dungeons = model:DungeonQuests()
    if #dungeons > 0 then parts[#parts + 1] = string.format("|cff73bfff%d dungeon quest%s to pick up|r", #dungeons, #dungeons == 1 and "" or "s") end
    local gray = model:GrayInLog()
    if #gray > 0 then parts[#parts + 1] = string.format("|cff9d9d9dAbandon %d gray quest%s|r", #gray, #gray == 1 and "" or "s") end
    return table.concat(parts, "  ")
end

-- ---- Browsing and scrolling (the controller keeps where you look; the model says what is there) ----
UI.follow, UI.section, UI.offset, UI.scrolled = true, nil, 1, false

function UI.Browse(step)
    if not UI.model then return end
    local count = #UI.model:Sections()
    UI.section = math.max(1, math.min(count, (UI.section or 1) + step))
    UI.follow, UI.scrolled, UI.jump = false, true, UI.section -- the list jumps to that part's header
    UI.Refresh()
end

local WHEEL = 2 -- rows a mouse-wheel notch scrolls

function UI.Scroll(step)
    UI.offset = math.max(1, (UI.offset or 1) + step * WHEEL)
    UI.scrolled = true
    UI.Refresh()
end

function UI.ToggleStep(i)
    if not UI.model then return end
    UI.model:ToggleStep(i)
    pinned = nil
    UI.Refresh()
end

-- The whole route as the list shows it: a header where each part starts, then its steps, by state and the
-- Done / Next toggles (user, 2026-11-13: see the steps behind you and the ones ahead, like RestedXP).
local function ListItems(model, states)
    local items, db = {}, DB()
    for k, sec in ipairs(model:Sections()) do
        local headed = false
        for i = sec.first, sec.last do
            local state = states[i]
            if state == "current" or state == "along" or (state == "open" and db.showNext) or ((state == "done" or state == "passed") and db.showDone) then
                if not headed then items[#items + 1] = { header = k }; headed = true end
                items[#items + 1] = { step = i }
            end
        end
    end
    return items
end

local function Header(model, group, first)
    local i = group[1]
    local number = #group > 1 and string.format("%d + %d", i, group[#group]) or tostring(i)
    if first then return string.format("Step %s of %d  %s", number, #model.steps, Where(model, i)) end
    return string.format("|cffaaaaaaStep %s|r  %s", number, Where(model, i))
end

-- The blocks; the first always, the others only while they fit (a small box shows only your step).
local function DrawBlocks(f, model, adapter, blocks, w, top, bottom)
    local inner, fits = w - 2 * PAD - 12, true
    for k = 1, ACTIVE do
        local b, group = f.blocks[k], blocks[k]
        if group then
            local action, lines, note, kind = GroupText(model, group, adapter)
            local c = KIND[kind] or KIND.travel
            b.accent:SetColorTexture(c[1], c[2], c[3], 1)
            local label = string.format("|cff%02x%02x%02x%s|r  ", c[1] * 255, c[2] * 255, c[3] * 255, c[4])
            b.header:SetText(label .. Header(model, group, k == 1))
            local advice = note and ("|cffffd100" .. note .. "|r") or ""
            local legs = k == 1 and model:Directions(group[1])
            if legs then
                local parts = { "|cff80b3ffHow to get there:|r" }
                for n, leg in ipairs(legs) do parts[#parts + 1] = string.format("%d. %s", n, leg.text) end
                advice = advice .. (advice ~= "" and "\n" or "") .. table.concat(parts, "\n")
            end
            for _, fs in ipairs({ b.header, b.action, b.advice }) do fs:SetWidth(inner) end
            b.lines:SetWidth(inner - 20)
            b.action:SetText(action); b.lines:SetText(lines); b.advice:SetText(advice)
            local h = 4 + Height(b.header, "x") + 3 + Height(b.action, action) + (lines ~= "" and 3 + Height(b.lines, lines) or 0)
                + (advice ~= "" and 3 + Height(b.advice, advice) or 0) + 5
            if k > 1 and (not fits or top - h < bottom) then fits = false end
            if fits then
                b:ClearAllPoints(); b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD - 4, top); b:SetSize(w - 2 * PAD + 8, h); b:Show()
                top = top - h - 3
            else
                b:Hide()
            end
        else
            b:Hide()
        end
    end
    if not blocks[1] then
        local b = f.blocks[1]
        b.header:SetText("Leveling guide"); b.action:SetText("Route finished. Well done!"); b.lines:SetText(""); b.advice:SetText("")
        b.accent:SetColorTexture(0.4, 0.92, 0.45, 1)
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD - 4, top); b:SetSize(w - 2 * PAD + 8, 40); b:Show()
        top = top - 43
    end
    return top, fits
end

-- The arrow's line: the first step's action, without the quest name after it, and how many more steps the
-- block holds (user, 2026-11-13: the arrow showed every grouped step with its quest name).
function UI.ArrowText(model, group, adapter)
    local d = DufforthTweaksHelperGuide.Describe(model, group[1])
    local action = string.gsub(d and d.action or "", "%s*|cffaaaaaa%(.-%)|r$", "")
    local more = #group > 1 and string.format(" |cffaaaaaa+%d more|r", #group - 1) or ""
    return "|T" .. (d and d.icon or "") .. ":14:14|t " .. action .. more
end

-- Class, dungeon and gray quests: what each is, where its giver is, and what a click does.
local function Where2(e) return e.zone and string.format("%s %d, %d", e.zone, math.floor((e.x or 0) + 0.5), math.floor((e.y or 0) + 0.5)) or "?" end

local function QuestItem(e, kind, indent)
    local dungeon = e.dungeon and ("|cff73bfff" .. e.dungeon .. ":|r ") or ""
    return {
        text = string.format("%s%s%s%s |cffaaaaaa(level %d)|r", indent, kind ~= "" and ("|cffc080ff" .. kind .. ":|r ") or "", dungeon, e.title, e.level),
        entry = e, kind = kind ~= "" and kind or "Dungeon quest", tipTitle = e.title,
        tip = { (e.dungeon and ("For the dungeon " .. e.dungeon .. ". ") or "") .. "Level " .. e.level .. ".",
                "From " .. (e.giver or "?") .. ", " .. Where2(e) .. ".",
                "Click: a map pin and the arrow to " .. (e.giver or "the giver") .. " (click again to go back to your step)." },
    }
end

local function ExtraItems(model)
    local items, db = {}, DB()
    for _, e in ipairs(model:ClassQuests()) do items[#items + 1] = QuestItem(e, "Class quest", "") end
    local dungeons = model:DungeonQuests()
    if #dungeons > 0 then
        items[#items + 1] = { toggle = "showDungeons", tipTitle = "Dungeon quests",
            text = string.format("|cff73bfff%s %d dungeon quest%s to pick up|r", db.showDungeons and "[-]" or "[+]", #dungeons, #dungeons == 1 and "" or "s"),
            tip = { "Quests for dungeons near your level, worth taking before you run the dungeon.", "Click to list them; click one for a map pin and the arrow to its giver." } }
        if db.showDungeons then for _, e in ipairs(dungeons) do items[#items + 1] = QuestItem(e, "", "    ") end end
    end
    local gray = model:GrayInLog()
    if #gray > 0 then
        items[#items + 1] = { toggle = "showGray", tipTitle = "Gray quests",
            text = string.format("|cff9d9d9d%s Abandon %d gray quest%s|r", db.showGray and "[-]" or "[+]", #gray, #gray == 1 and "" or "s"),
            tip = { "Quests in your log far below your level give little experience.", "Open your quest log (L) and abandon them to make room. Click to list them." } }
        if db.showGray then
            for _, e in ipairs(gray) do
                items[#items + 1] = { text = "    |cff9d9d9d" .. e.title .. " (level " .. e.level .. ")|r", tipTitle = e.title,
                    tip = { "Gray: little experience left. Abandon it in your quest log (L)." } }
            end
        end
    end
    return items
end

local function DrawExtras(f, model, w, top, bottom, fits)
    local items, y = ExtraItems(model), top
    for k, r in ipairs(f.extraRows) do
        local item = items[k]
        if item and fits then
            r.item = item
            r.label:SetWidth(w - 2 * PAD - 4); r.label:SetText(item.text)
            local h = Height(r.label, item.text) + 3
            if y - h < bottom then fits = false; r:Hide()
            else
                r:ClearAllPoints(); r:SetPoint("TOPLEFT", f, "TOPLEFT", PAD - 2, y); r:SetSize(w - 2 * PAD + 4, h); r:Show()
                y = y - h
            end
        else
            r.item = nil; r:Hide()
        end
    end
    return y - (#items > 0 and 3 or 0), fits
end

function UI.ToggleGuideMenu()
    local f = Box()
    if f.guideMenu:IsShown() then f.guideMenu:Hide(); return end
    local data, picked = DufforthTweaksHelperGuideData, DB().guideName
    local entries = { { nil, "Leveling 1-60 (fast, for your race)", "Quests and route picked for the fastest leveling: low-experience quests and long walks left out." } }
    for _, g in ipairs(data.guides or {}) do entries[#entries + 1] = { g.name or g[1], g.name or g[1], g.note or g[2] } end
    for k, r in ipairs(f.guideRows) do
        local e = entries[k]
        if e then
            r.guide, r.title, r.note = e[1], e[2], e[3]
            local on = (e[1] == picked) or (e[1] == nil and not (picked and data.routes[picked]))
            r.label:SetText((on and "|cff40ff40> |r" or "   ") .. e[2]); r:Show()
        else
            r:Hide()
        end
    end
    f.guideMenu:SetHeight(4 + math.min(#entries, #f.guideRows) * 20)
    f.guideMenu:Show()
end

-- A click on an extra: open or close a list, or point the arrow (and a map pin) at a quest's giver.
function UI.ExtraClicked(item)
    if not item then return end
    if item.toggle then
        DB()[item.toggle] = not DB()[item.toggle]
    elseif item.entry then
        local e = item.entry
        if UI.override and UI.override.id == e.id then
            UI.override = nil
        else
            local map = DufforthTweaksHelperGuideData.uiMaps[e.zone]
            UI.override = { id = e.id, map = map, x = e.x, y = e.y, zone = e.zone, text = item.kind .. ": " .. e.title .. " - " .. (e.giver or "") }
            if map and e.x then
                pcall(function() C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, e.x / 100, e.y / 100)) end)
            end
        end
        pinned = nil
    end
    UI.Refresh()
end

-- Along the way: map-wide objectives in your log, with the game's progress.
local function AlongText(model, adapter)
    local parts = {}
    for _, i in ipairs(model:Along()) do
        local action, lines = StepText(model, i, adapter)
        parts[#parts + 1] = action .. (lines ~= "" and ("\n      " .. string.gsub(lines, "\n", "\n      ")) or "")
    end
    if #parts == 0 then return "" end
    return "|cff80b3ffAlong the way|r |cff888888(kill them as you go)|r\n" .. table.concat(parts, "\n")
end

local function DrawProgress(f, model, current, w, top)
    local k = current and model:SectionOf(current)
    local done, total = 0, 0
    if k then done, total = model:SectionProgress(k) else done, total = 1, 1 end
    local pct = total > 0 and done / total or 1
    f.progress:ClearAllPoints(); f.progress:SetPoint("TOPLEFT", f, "TOPLEFT", PAD - 4, top); f.progress:SetSize(w - 2 * PAD + 8, PROGRESS)
    f.progress:SetValue(pct)
    local title = k and DufforthTweaksHelperGuide.SectionTitle(model:Sections()[k]) or "Route finished"
    local route = current and math.floor((current - 1) / math.max(1, #model.steps) * 100) or 100
    f.progress.label:SetText(string.format("%s   zone %d%%   route %d%%", title, math.floor(pct * 100 + 0.5), route))
    return top - PROGRESS - 4
end

local function DrawList(f, model, adapter, current, w, top, bottom)
    local sections = model:Sections()
    if UI.follow or not UI.section then UI.section = current and model:SectionOf(current) or #sections end
    local sec = sections[UI.section]
    f.bar:ClearAllPoints(); f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", PAD - 4, top); f.bar:SetSize(w - 2 * PAD + 8, BAR)
    f.bar.label:SetText(string.format("%s  |cff888888%d/%d|r", DufforthTweaksHelperGuide.SectionTitle(sec), UI.section, #sections))
    SetOn(f.doneToggle, DB().showDone); SetOn(f.nextToggle, DB().showNext)
    top = top - BAR - 2
    local room = top - bottom
    f.list:ClearAllPoints(); f.list:SetPoint("TOPLEFT", f, "TOPLEFT", PAD - 4, top); f.list:SetSize(w - 2 * PAD + 8, math.max(10, room))
    for _, r in ipairs(f.rows) do r:Hide() end
    if not sec then f.empty:SetText(""); return top end
    local states = model:States(#model.steps)
    local items = ListItems(model, states)
    if UI.jump then
        -- Browsed to a part: start at its header.
        for k, item in ipairs(items) do if item.header == UI.jump then UI.offset = k; break end end
        UI.jump = nil
    elseif UI.follow and not UI.scrolled then
        -- Following: the current step with the steps behind you above it (more of them in a taller box).
        local behind = math.floor(math.max(1, room / 24) * 0.4)
        UI.offset = 1
        for k, item in ipairs(items) do
            if item.step == current then UI.offset = math.max(1, k - behind); break end
        end
    end
    UI.offset = math.max(1, math.min(UI.offset or 1, math.max(1, #items)))
    f.empty:SetText(#items == 0 and "No steps to show: Done and Next choose which ones." or "")
    local inner, y, n = w - 2 * PAD, 0, 0
    for k = UI.offset, #items do
        if n >= ROWS then break end
        local item, r = items[k], f.rows[n + 1]
        local text, state
        if item.header then
            r.isHeader, r.step = true, nil
            text = "|cffffd100" .. DufforthTweaksHelperGuide.SectionTitle(sections[item.header]) .. "|r"
            r.num:SetText(""); r.check:Hide()
        else
            local i = item.step
            local action, lines = StepText(model, i, adapter)
            state = states[i]
            r.isHeader, r.step = false, i
            text = action .. (lines ~= "" and ("\n" .. lines) or "")
            if state == "done" then text = DONE_MARK .. text
            elseif state == "passed" then text = "|cff9d9d9d(passed by)|r " .. text
            elseif state == "along" then text = "|cff80b3ff(along the way)|r " .. text end
            r.num:SetText(i)
            r.check:Show()
            r.check.mark:SetShown(model.saved.skipped[i] and true or false)
        end
        r.label:SetWidth(inner - 56)
        r.label:SetText(text)
        local h = math.max(item.header and 18 or 20, Height(r.label, text) + 6)
        if -y + h > room and n > 0 then break end -- no half rows over the edge
        n = n + 1
        r:SetAlpha((state == "done" or state == "passed") and 0.55 or 1)
        if item.header then r.band:SetColorTexture(0.2, 0.2, 0.23, 1)
        else r.band:SetColorTexture(1, 1, 1, state == "current" and 0.08 or 0) end
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", f.list, "TOPLEFT", 0, y); r:SetSize(w - 2 * PAD + 8, h); r:Show()
        y = y - h - 2
    end
    if n == 0 and f.empty:GetText() ~= "" then y = y - 20 end
    return top + y -- the lowest point drawn
end

-- ---- The waypoint arrow ----
local arrow

local function Arrow()
    if arrow then return arrow end
    local a = CreateFrame("Frame", "DufforthTweaksHelperGuideArrow", UIParent)
    if a.SetDontSavePosition then a:SetDontSavePosition(true) end
    a:SetSize(220, 92)
    a:SetPoint("TOP", UIParent, "TOP", 0, -120)
    local p = DB().arrowPoint
    if p then a:ClearAllPoints(); a:SetPoint(p[1], UIParent, p[2], p[3], p[4]) end
    a:SetMovable(true); a:SetClampedToScreen(true); a:EnableMouse(true)
    a:RegisterForDrag("LeftButton")
    a:SetScript("OnDragStart", function(self) self:StartMoving() end)
    a:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relative, x, y = self:GetPoint()
        DB().arrowPoint = { point, relative, x, y }
    end)
    a:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then UI.SetArrowShown(false) end end)
    a.pointer = a:CreateTexture(nil, "ARTWORK")
    a.pointer:SetTexture("Interface\\Minimap\\MinimapArrow"); a.pointer:SetSize(52, 52); a.pointer:SetPoint("TOP", 0, 0)
    if a.pointer.SetDesaturated then a.pointer:SetDesaturated(true) end
    a.check = a:CreateTexture(nil, "ARTWORK")
    a.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready"); a.check:SetSize(34, 34); a.check:SetPoint("TOP", 0, -8)
    a.label = a:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    a.label:SetPoint("TOP", a.pointer, "BOTTOM", 0, 0); a.label:SetWidth(220); a.label:SetJustifyH("CENTER")
    if a.label.SetShadowOffset then a.label:SetShadowOffset(1, -1) end
    a.dist = a:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    a.dist:SetPoint("TOP", a.label, "BOTTOM", 0, -2)
    a.angle = 0
    a:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Points at your guide step. Drag to move, right-click to hide (the arrow button on the guide shows it).", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    a:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local wait = 0
    a:SetScript("OnUpdate", function(_, elapsed)
        wait = wait - (elapsed or 0)
        if wait > 0 then return end
        wait = 0.05
        pcall(UI.UpdateArrow)
    end)
    arrow = a
    if DufforthTweaksHelper and DufforthTweaksHelper.RegisterMovable then
        DufforthTweaksHelper.RegisterMovable({ label = "Guide arrow", get = function() return arrow end,
            enter = function(f) f:Show() end, leave = function() UI.UpdateArrow() end })
    end
    return a
end

local function XY(v)
    if not v then return nil end
    if v.GetXY then return v:GetXY() end
    return v.x, v.y
end

-- Where you are, in world yards (north, west) and the continent, or nil.
local function WorldPos(map, x, y)
    if not (map and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local continent, pos = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(x, y))
    local n, w = XY(pos)
    if not n then return nil end
    return continent, n, w
end

function UI.UpdateArrow()
    if not DufforthTweaksHelperGuide then return end
    local a, t = Arrow(), UI.target
    if not DB().arrow or not t or (DufforthTweaksHelper.EditMode and DufforthTweaksHelper.EditMode()) then
        if not (DufforthTweaksHelper.EditMode and DufforthTweaksHelper.EditMode()) then a:Hide() end
        return
    end
    local pmap = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local ppos = pmap and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(pmap, "player")
    local px, py = XY(ppos)
    local pc, pn, pw
    if px then pc, pn, pw = WorldPos(pmap, px, py) end
    local tc, tn, tw = WorldPos(t.map, t.x / 100, t.y / 100)
    if not (pn and tn) then a:Hide(); return end
    a.label:SetText(t.text)
    if pc ~= tc then
        a.pointer:Hide(); a.check:Hide()
        a.dist:SetText("|cff73bfffGo to " .. t.zone .. "|r")
        a:Show()
        return
    end
    local facing = GetPlayerFacing and GetPlayerFacing()
    local rel, dist = DufforthTweaksHelperGuide.Bearing(pn, pw, tn, tw, facing or 0)
    if dist < 10 then
        a.pointer:Hide(); a.check:Show()
        a.dist:SetText("|cff40ff40You are here|r")
    else
        a.check:Hide()
        local speed = GetUnitSpeed and GetUnitSpeed("player") or 0
        a.dist:SetText(string.format("%d yd  |cffffd100%s|r", math.floor(dist + 0.5), DufforthTweaksHelperGuide.Eta(dist, speed)))
        if facing then
            a.angle = rel
            a.pointer:SetRotation(rel)
            local off = math.abs(rel)
            if off < 0.35 then a.pointer:SetVertexColor(0.2, 1, 0.2)
            elseif off < 1.3 then a.pointer:SetVertexColor(1, 0.85, 0.1)
            else a.pointer:SetVertexColor(1, 0.25, 0.2) end
            a.pointer:Show()
        else
            a.pointer:Hide() -- no facing (instances): distance only
        end
    end
    a:Show()
end

function UI.SetArrowShown(on)
    DB().arrow = on and true or false
    if on then UI.UpdateArrow() elseif arrow then arrow:Hide() end
end

-- ---- Refresh ----
function UI.Refresh()
    if not DufforthTweaksHelperGuideData or not DufforthTweaksHelperGuide then return end
    local f = Box()
    if not DB().shown then f:Hide(); UI.target = nil; if arrow then arrow:Hide() end; return end
    if DufforthTweaksHelper.EditMode and DufforthTweaksHelper.EditMode() then return end
    if not f.sized then f:SetWidth(f.w); f.sized = true end -- over any size the game restored
    logCache = nil
    UI.adapter = UI.GameAdapter()
    UI.model = Model(UI.adapter)
    local model, adapter = UI.model, UI.adapter
    local blocks = model:Blocks(ACTIVE)
    local current = blocks[1] and blocks[1][1]
    -- The Start quest button for an item-started quest whose item is in your bags (not changed in combat).
    if not (InCombatLockdown and InCombatLockdown()) then
        local d = current and DufforthTweaksHelperGuide.Describe(model, current)
        if d and d.useItem then
            f.useItem.item = "item:" .. d.useItem
            f.useItem:SetAttribute("type", "item"); f.useItem:SetAttribute("item", f.useItem.item)
            f.useItem:Show()
        else
            f.useItem:Hide()
        end
    end
    if current ~= UI.lastCurrent then UI.follow, UI.scrolled, UI.lastCurrent, UI.override = true, false, current, nil end
    f:Show()
    local w, h = Size(f)
    f.stepNum:SetText(current or "-")
    f.routePct:SetText("")
    SetOn(f.arrowToggle, DB().arrow)
    SetOn(f.autoToggle, DufforthTweaksHelperQuestAuto and DufforthTweaksHelperQuestAuto.Enabled())
    local bottom = -(h - 6)
    -- Level, zone and progress: always shown, right under the top strip (user, 2026-11-13).
    f.progress:Show()
    local top, fits = DrawBlocks(f, model, adapter, blocks, w, DrawProgress(f, model, current, w, -(STRIP + 3)), bottom)
    -- Then, while there is room: along the way, the progress bar, the extras, the list.
    local along = AlongText(model, adapter)
    f.along:SetWidth(w - 2 * PAD); f.along:SetText(along)
    local alongH = along ~= "" and Height(f.along, along) + 4 or 0
    fits = fits and top - alongH >= bottom
    f.along:SetShown(fits and along ~= "")
    if fits and along ~= "" then f.along:ClearAllPoints(); f.along:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, top); top = top - alongH end
    f.note:SetText(""); f.note:Hide()
    top, fits = DrawExtras(f, model, w, top, bottom, fits)
    fits = fits and top - BAR - 20 >= bottom
    f.bar:SetShown(fits); f.list:SetShown(fits)
    local used = top
    if fits then used = DrawList(f, model, adapter, current, w, top, bottom)
    else for _, r in ipairs(f.rows) do r:Hide() end end
    -- Fit the box to what it shows (not while you drag the corner).
    f.fitH = math.min(h, math.floor(-used + 22))
    if not f.sizing then f:SetHeight(f.fitH) end
    UI.target = nil
    if current then
        Pin(model, current)
        local zone, x, y, map = model:Place(current)
        local legs = model:Directions(current)
        local first = legs and legs[1]
        if first and first.x and model.data.uiMaps[first.zone] then
            -- Far away: the arrow points at the first leg (the zeppelin tower, the flight master).
            UI.target = { map = model.data.uiMaps[first.zone], x = first.x, y = first.y, zone = first.zone, text = "1. " .. first.text }
        elseif map and x and y then
            UI.target = { map = map, x = x, y = y, zone = zone, text = UI.ArrowText(model, blocks[1], adapter) }
        end
    end
    if UI.override and UI.override.map then UI.target = UI.override end -- you clicked a class or dungeon quest
    UI.UpdateArrow()
end

function UI.SetShown(on)
    DB().shown = on and true or false
    if box and not on then box:Hide(); if arrow then arrow:Hide() end end
    if on then UI.Refresh() end
end

function UI.Toggle() UI.SetShown(not DB().shown) end

-- Quest and level changes: refresh a moment later (the quest log updates after these events).
local watcher = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_LOG_UPDATE",
    "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "TAXIMAP_OPENED" }) do pcall(watcher.RegisterEvent, watcher, event) end
local soon = false
watcher:SetScript("OnEvent", function(_, event)
    if event == "TAXIMAP_OPENED" then pcall(UI.LearnFlights) end
    if soon then return end
    soon = true
    local function go() soon = false; pcall(UI.Refresh) end
    if C_Timer then C_Timer.After(0.5, go) else go() end
end)
