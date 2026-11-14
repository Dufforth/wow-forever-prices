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
        price = function(id)
            local market = DufforthTweaksHelper and DufforthTweaksHelper.MarketName and DufforthTweaksHelper.MarketName()
            local p = market and DufforthTweaksHelperPrices and DufforthTweaksHelperPrices[market]
            return p and p[id] or nil
        end,
        itemName = function(id)
            local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
            return getInfo and getInfo(id) or nil
        end,
        money = function(c) return DufforthTweaksHelperDE and DufforthTweaksHelperDE.Money and DufforthTweaksHelperDE.Money(c) or (c .. "c") end,
        xp = function()
            return tonumber(UnitXP and UnitXP("player")) or 0, tonumber(UnitXPMax and UnitXPMax("player")) or 0
        end,
        -- Your hearthstone: the zone it takes you to, and whether it's ready.
        hearth = function() return UI.Hearth() end,
        -- Where you stand: zone name and map % (the nearest open objective comes first).
        position = function()
            local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
            local pos = map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
            local info = map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
            if not (pos and info and info.name) then return nil end
            local x, y
            if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
            if not x then return nil end
            return info.name, x * 100, y * 100
        end,
        logIds = LogIds,
    }
end

-- The zone your hearthstone takes you to (saved when you set it; a capital also from its name) and ready or not.
local HEARTHSTONE = 6948
local CAPITALS = { Orgrimmar = true, ["Thunder Bluff"] = true, Undercity = true }
function UI.Hearth()
    local home = DB().homeZone
    if not home and GetBindLocation then
        local bind = GetBindLocation()
        if CAPITALS[bind] then home = bind end
    end
    if not home then return nil end
    if not GetItemCount or (GetItemCount(HEARTHSTONE) or 0) == 0 then return home, false end
    local start, duration = 0, 0
    if C_Container and C_Container.GetItemCooldown then start, duration = C_Container.GetItemCooldown(HEARTHSTONE)
    elseif GetItemCooldown then start, duration = GetItemCooldown(HEARTHSTONE) end
    return home, (tonumber(start) or 0) == 0 or (tonumber(duration) or 0) == 0
end

-- Free slots in your normal bags, and your most worn item (0-1), for the repair errand.
local function FreeSlots()
    if not (C_Container and C_Container.GetContainerNumFreeSlots) then return nil end
    local free = 0
    for bag = 0, 4 do
        local n, family = C_Container.GetContainerNumFreeSlots(bag)
        if (family or 0) == 0 then free = free + (n or 0) end
    end
    return free
end
local function Durability()
    if not GetInventoryItemDurability then return nil end
    local worst
    for slot = 1, 18 do
        local cur, max = GetInventoryItemDurability(slot)
        cur, max = tonumber(cur), tonumber(max)
        if cur and max and max > 0 then worst = math.min(worst or 1, cur / max) end
    end
    return worst
end

local function Nearest(list, zone, x, y)
    local best, bestD
    for _, n in ipairs(list or {}) do
        if n[2] == zone then
            local d = (x and n[3]) and ((n[3] - x) ^ 2 + (n[4] - y) ^ 2) or 0
            if not bestD or d < bestD then best, bestD = n, d end
        end
    end
    return best and { name = best[1], zone = best[2], x = best[3], y = best[4] } or nil
end

-- Food and drink in your bags you can use now (by the item's use: Food or Drink), and whether you use mana.
local function FoodInBags(level)
    local out = { food = 0, drink = 0, mana = UnitPowerType and UnitPowerType("player") == 0 or false }
    if not (C_Container and C_Container.GetContainerNumSlots) then return nil end
    local spellOf = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if id and instant and select(6, instant(id)) == 0 and select(7, instant(id)) == 5 then
                local need = getInfo and select(5, getInfo(id)) or 0
                local use = spellOf and spellOf(id)
                if (need or 0) <= level and use then
                    local kind = string.find(use, "Drink") and "drink" or "food"
                    out[kind] = out[kind] + (info.stackCount or 1)
                end
            end
        end
    end
    return out
end

-- Training, hearthstone, repairs and a class quest where you are (user, 2026-11-14).
function UI.Errands(model, adapter, current)
    local here = adapter.zone()
    local _, px, py
    if adapter.position then _, px, py = adapter.position() end
    local state = { zone = here, level = adapter.level(), homeZone = DB().homeZone, skipped = DB().errandSkip or {},
        freeSlots = FreeSlots(), durability = Durability() }
    local travel = model.data.travel or {}
    state.repair = Nearest(travel.repairs, here, px, py)
    state.innHere = Nearest(travel.inns, here, px, py)
    state.food = FoodInBags(state.level)
    local Z = DufforthTweaksHelperZone
    if Z and Z.TrainNow then
        local ok, t = pcall(Z.TrainNow)
        if ok and t and t.rows and #t.rows > 0 then
            local tr = t.trainers and t.trainers[1]
            local money = DufforthTweaksHelperDE and DufforthTweaksHelperDE.Money
            state.train = { count = #t.rows, cost = money and t.total and money(t.total) or nil,
                trainer = tr and { name = tr[1], zone = tr[3], x = tr[4], y = tr[5] } or nil }
        end
    end
    local cq = model:ClassQuests()[1]
    if cq then state.classQuest = cq end
    if current then
        local k = model:SectionOf(current)
        local sec = k and model:Sections()[k]
        if sec then
            local zone, x, y = model:Place(current)
            state.sectionZone, state.sectionLeft = sec.zone, sec.last - current
        end
    end
    return DufforthTweaksHelperGuide.Errands(state)
end

-- At a flight master with Auto on: fly to the one nearest your next step (user, 2026-11-14). Shift skips it.
local function WorldOf(map, x, y)
    if not (map and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, _, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
    if not ok or not pos then return nil end
    local a, b
    if pos.GetXY then a, b = pos:GetXY() else a, b = pos.x, pos.y end
    return a and { a, b } or nil
end

function UI.AutoFly()
    local auto = DufforthTweaksHelperQuestAuto
    if not (auto and auto.Enabled and auto.Enabled()) or (IsShiftKeyDown and IsShiftKeyDown()) then return end
    if not (NumTaxiNodes and TaxiNodeName and TaxiNodeGetType and TakeTaxiNode) then return end
    local model = UI.model
    local current = model and model:Current()
    local fm = current and model:FlightTo(current)
    if not fm then return end
    local want = WorldOf(model.data.uiMaps[fm[2]], fm[3] / 100, fm[4] / 100)
    local taxiMap = GetTaxiMapID and GetTaxiMapID()
    local nodes = {}
    for i = 1, NumTaxiNodes() do
        local n = { index = i, name = TaxiNodeName(i), type = TaxiNodeGetType(i) }
        if want and taxiMap and TaxiNodePosition then
            local x, y = TaxiNodePosition(i)
            local w = x and WorldOf(taxiMap, x, y)
            if w then n.dist = (w[1] - want[1]) ^ 2 + (w[2] - want[2]) ^ 2 end
        end
        nodes[#nodes + 1] = n
    end
    local pick = DufforthTweaksHelperGuide.PickTaxiNode(nodes, fm[2])
    if pick then TakeTaxiNode(pick) end
end

-- ---- Route lines on the world map (user, 2026-11-14) ----
local mapLines
function UI.DrawMapLines()
    if not (WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame.GetCanvas) then return end
    local canvas = WorldMapFrame:GetCanvas()
    if not canvas then return end
    if not mapLines then
        local frame = CreateFrame("Frame", nil, canvas)
        frame:SetAllPoints(canvas)
        mapLines = { frame = frame, lines = {}, dots = {} }
    end
    local frame = mapLines.frame
    frame:SetFrameLevel((canvas.GetFrameLevel and canvas:GetFrameLevel() or 0) + 50)
    for _, l in ipairs(mapLines.lines) do l:Hide() end
    for _, d in ipairs(mapLines.dots) do d:Hide() end
    local model = UI.model
    if not model or DB().mapLines == false or not DB().shown then return end
    local mapID, points = WorldMapFrame:GetMapID(), {}
    for _, i in ipairs(model:Upcoming(8)) do
        local zone, x, y, map = model:Place(i)
        if map == mapID and x and y then points[#points + 1] = { x / 100, y / 100 } end
    end
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    for k, p in ipairs(points) do
        local dot = mapLines.dots[k]
        if not dot then
            dot = CreateFrame("Frame", nil, frame); dot:SetSize(18, 18)
            dot.bg = dot:CreateTexture(nil, "ARTWORK"); dot.bg:SetAllPoints()
            dot.bg:SetTexture("Interface\\Minimap\\ObjectIconsAtlas"); dot.bg:SetColorTexture(0.1, 0.1, 0.1, 0.9)
            dot.num = dot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); dot.num:SetPoint("CENTER")
            mapLines.dots[k] = dot
        end
        dot:ClearAllPoints(); dot:SetPoint("CENTER", frame, "TOPLEFT", p[1] * w, -p[2] * h)
        dot.num:SetText(k); dot:Show()
        if k > 1 and frame.CreateLine then
            local line = mapLines.lines[k - 1]
            if not line then
                line = frame:CreateLine(nil, "OVERLAY"); line:SetThickness(3); line:SetColorTexture(1, 0.82, 0, 0.8)
                mapLines.lines[k - 1] = line
            end
            local a = points[k - 1]
            line:SetStartPoint("TOPLEFT", frame, a[1] * w, -a[2] * h)
            line:SetEndPoint("TOPLEFT", frame, p[1] * w, -p[2] * h)
            line:Show()
        end
    end
end
if WorldMapFrame then
    if WorldMapFrame.HookScript then WorldMapFrame:HookScript("OnShow", function() pcall(UI.DrawMapLines) end) end
    if hooksecurefunc and WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", function() pcall(UI.DrawMapLines) end) end
end

-- ---- Forever's own quests, from your quest log (user, 2026-11-14) ----
-- Forever's public data has only their numbers, so their names, progress and places come from the game.
function UI.ForeverQuests(model)
    local out = {}
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then return out end
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local spots = {}
    if map and C_QuestLog.GetQuestsOnMap then
        local ok, list = pcall(C_QuestLog.GetQuestsOnMap, map)
        for _, q in ipairs(ok and list or {}) do if q.questID then spots[q.questID] = q end end
    end
    local info = map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    for i = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
        local q = C_QuestLog.GetInfo(i)
        if q and not q.isHeader and q.questID and not model.data.quests[q.questID] then
            local progress = {}
            local ok, list = pcall(C_QuestLog.GetQuestObjectives, q.questID)
            for _, o in ipairs(ok and type(list) == "table" and list or {}) do
                local have, need = string.match(o.text or "", "(%d+)%s*/%s*(%d+)")
                if have then progress[#progress + 1] = have .. "/" .. need end
            end
            local spot = spots[q.questID]
            out[#out + 1] = { id = q.questID, title = q.title or ("Quest " .. q.questID), progress = table.concat(progress, " "),
                map = spot and map, x = spot and spot.x and spot.x * 100, y = spot and spot.y and spot.y * 100, zone = info and info.name }
        end
    end
    return out
end

-- The leveling tracker: experience per hour and time to level (short on the bar, long in its hover).
function UI.TrackXP()
    if not (UnitLevel and UnitXP and UnitXPMax) then return end
    local t = DB().tracker or {}
    DB().tracker = t
    DufforthTweaksHelperGuide.TrackXP(t, GetTime and GetTime() or 0, UnitLevel("player"), tonumber(UnitXP("player")) or 0, tonumber(UnitXPMax("player")) or 0)
end

function UI.PaceText(long)
    local G = DufforthTweaksHelperGuide
    local s = G.TrackSummary(DB().tracker or {})
    if not long then
        return s.toLevel and ("Level up in " .. G.Duration(s.toLevel)) or ""
    end
    local lines = {}
    if s.perHour then lines[#lines + 1] = string.format("Experience: %d an hour.", s.perHour) end
    if s.toLevel then lines[#lines + 1] = "Next level in about " .. G.Duration(s.toLevel) .. " at this pace." end
    if s.lastLevel then lines[#lines + 1] = string.format("Level %d took %s of play.", s.lastLevel.level, G.Duration(s.lastLevel.seconds)) end
    if #lines == 0 then return "Your leveling pace shows after a few minutes of play." end
    return table.concat(lines, "\n")
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
    return UI.RaceRoute()
end

-- The leveling route for your race.
function UI.RaceRoute()
    local race
    if UnitRace then _, race = UnitRace("player") end
    local name = DufforthTweaksHelperGuide.ROUTE_FOR_RACE[race] or "Durotar"
    local data = DufforthTweaksHelperGuideData
    local routes = data and data.routes or {}
    -- Style (user, 2026-11-14): Speed (fastest), Safe (no quests in world-PvP zones), Explorer (more zones and flight
    -- paths, gear and gold rewards, farming stops); each with or without dungeon quests.
    local styled = name .. (UI.STYLE_SUFFIX[DB().style or "speed"] or "")
    if routes[styled] then name = styled end
    if DB().withDungeons and routes[name .. " (dungeons)"] then
        return name .. " (dungeons)" -- also takes dungeon quests, for players who group
    end
    return name
end

local pinned -- the step the map pin is on (declared before the menu functions that clear it)
UI.STYLES = { "speed", "safe", "explorer" }
UI.STYLE_SUFFIX = { speed = "", safe = " - Safe", explorer = " - Explorer" }
UI.STYLE_LABEL = { speed = "Speed", safe = "Safe", explorer = "Explorer" }
UI.STYLE_TIP = {
    speed = "The fastest way to 60.",
    safe = "Leaves out quests in the zones known for world PvP (Stranglethorn, Hillsbrad, Ashenvale, Arathi, Alterac). A bit slower.",
    explorer = "More zones and their flight paths, quests with gear or gold rewards, and an optional gold-farming stop in each zone.",
}

function UI.SetStyle(dir)
    local list, at = UI.STYLES, 1
    for k, s in ipairs(list) do if s == (DB().style or "speed") then at = k end end
    local before = UI.RouteName()
    DB().style = list[math.max(1, math.min(#list, at + dir))]
    UI.follow, UI.scrolled, UI.section, UI.lastCurrent, UI.override = true, false, nil, nil, nil
    UI.NoteSwitch(before, UI.RouteName())
    UI.Refresh()
end

-- The guide's name as shown: "Speed", "Safe + dungeons", or a questline's name.
function UI.GuideLabel()
    local picked = DB().guideName
    local data = DufforthTweaksHelperGuideData
    if picked and data and data.routes and data.routes[picked] then return picked end
    local name = UI.STYLE_LABEL[DB().style or "speed"] or "Speed"
    return name .. (DB().withDungeons and " + dungeons" or "")
end

-- After switching guides: what's different, and from which level the routes part (user, 2026-11-14: "when I
-- change nothing changes": the styles share their first levels).
function UI.FirstDifference(a, b)
    local ra, rb = a and a.steps or {}, b and b.steps or {}
    local seen = {}
    for k = 1, math.max(#ra, #rb) do
        local x, y = ra[k], rb[k]
        if not (x and y and x[1] == y[1] and x[2] == y[2] and x[3] == y[3]) then
            local s = y or x
            return s and s[6], s and s[3]
        end
    end
    return nil
end

function UI.NoteSwitch(before, after)
    local routes = DufforthTweaksHelperGuideData and DufforthTweaksHelperGuideData.routes or {}
    local level, zone = UI.FirstDifference(routes[before], routes[after])
    local tip = UI.STYLE_TIP[DB().style or "speed"] or ""
    local diff = level and string.format("Same steps as before until level %d (%s); from there it differs.", level, zone or "?")
        or "Same route as before."
    UI.switchNote = { text = "|cffffd100" .. UI.GuideLabel() .. " guide.|r " .. tip .. " " .. diff, ["until"] = (GetTime and GetTime() or 0) + 12 }
    if C_Timer then C_Timer.After(12.1, function() pcall(UI.Refresh) end) end
end

-- A zone part from the Guides menu: back to the leveling guide, which now starts from that part
-- (the current step, the arrow and the list go there; user, 2026-11-13: only the list moved before).
function UI.SelectBracket(section)
    DB().guideName = nil
    local name = UI.RaceRoute()
    local saved = DB().routes[name] or {}
    DB().routes[name] = saved
    local model = DufforthTweaksHelperGuide.NewModel(DufforthTweaksHelperGuideData, name, UI.adapter or UI.GameAdapter(), saved)
    local sec = model:Sections()[section]
    if sec then model:SetStart(sec.first) end
    UI.follow, UI.scrolled, UI.section, UI.override, UI.lastCurrent = true, false, nil, nil, nil
    pinned = nil
    if box and box.guideMenu then box.guideMenu:Hide() end
    UI.Refresh()
end

-- Best: the step that fits your level and what you have done.
function UI.GoRecommended()
    if not UI.model then UI.Refresh() end
    local model = UI.model
    if not model then return end
    model:SetStart(model:Recommended())
    UI.follow, UI.scrolled, UI.section, UI.override, UI.lastCurrent = true, false, nil, nil, nil
    pinned = nil
    UI.Refresh()
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

local function ClearPin()
    if pinned == "none" then return end
    pinned = "none"
    pcall(function()
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(false) end
        if C_Map.ClearUserWaypoint then C_Map.ClearUserWaypoint() end
    end)
end

local function Pin(model, i)
    if not model:Pinpoint(i) then ClearPin(); return end -- an area to kill or loot in: no single spot
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
local fonts = {} -- every text, so the Text size option can change them all
local ERRAND_H = 20 -- an errand row (train, hearthstone, repair, class quest)
local MENU_ROWS, MENU_MIN_W, MENU_MAX_W = 16, 220, 320 -- the Guides menu
local TOOLS_W, MENU_ROW = 210, 22 -- the Menu panel and one of its rows
local WIDTH, HEIGHT, MIN_W, MIN_H, MAX_W, MAX_H = 340, 440, 290, 70, 800, 1000 -- 290: the strip fits Steps, Best, the pin, Menu and _
local DONE_MARK, WAIT_MARK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t ", "|TInterface\\RaidFrame\\ReadyCheck-Waiting:0|t "
local WHITE = "Interface\\Buttons\\WHITE8x8"
-- What you do, shown as a colored stripe and label beside the text (text stays on a neutral dark
-- background: user, 2026-11-13, colored bands made names hard to read). Colors pass 4.5:1 on the bands.
local KIND = {
    kill = { 1, 0.42, 0.42, "KILL" }, grind = { 1, 0.42, 0.42, "GRIND" }, loot = { 1, 0.66, 0.3, "LOOT" },
    use = { 0.35, 0.85, 0.9, "USE" }, explore = { 0.35, 0.85, 0.9, "EXPLORE" }, accept = { 1, 0.82, 0, "PICK UP" },
    turnin = { 0.4, 0.92, 0.45, "TURN IN" }, travel = { 0.5, 0.7, 1, "TRAVEL" }, flight = { 0.5, 0.7, 1, "FLIGHT PATH" },
}
local BAND_CURRENT, BAND_NEXT = { 0.12, 0.12, 0.14 }, { 0.08, 0.08, 0.09 } -- dark, so names read clearly (user)
-- A clean narrow font with a shadow (the game's own Arial Narrow).
local FONT = "Fonts\\ARIALN.TTF"
local function Font(fs, size)
    fonts[#fonts + 1] = { fs, size }
    if fs.SetFont then fs:SetFont(FONT, size + (DB().fontDelta or 0), "") end
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
    local mark = rawget(b, "check") -- a check box row in the Menu
    if mark then mark:SetShown(on and true or false); return end
    if on then b.bg:SetColorTexture(0.12, 0.45, 0.2, 0.95) else b.bg:SetColorTexture(0.22, 0.22, 0.24, 0.95) end
end

local function Tip(b, text)
    b:SetScript("OnEnter", function(self)
        local inMenu = box and box.tools and self:GetParent() == box.tools
        GameTooltip:SetOwner(self, inMenu and "ANCHOR_LEFT" or "ANCHOR_TOP"); -- a menu row's tip beside the menu, not over it GameTooltip:SetText(type(text) == "function" and text() or text, 1, 1, 1, 1, true); GameTooltip:Show()
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
    if d.tip then lines[#lines + 1] = "|cffaaaaaa" .. d.tip .. "|r" end
    local note = d.checkpoint and ((d.note and (d.note .. "\n") or "") .. d.checkpoint) or d.note
    return DufforthTweaksHelperGuide.Inline(d.icon) .. " " .. (d.action or ""), table.concat(lines, "\n"), note, d.kind -- centred on the text (user)
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
    -- Mark this block's steps done (you did them without the guide), like the list's check boxes (user, 2026-11-13).
    b.check = CreateFrame("Button", nil, b)
    b.check:SetSize(16, 16); b.check:SetPoint("TOPRIGHT", -3, -2)
    b.check.box = b.check:CreateTexture(nil, "ARTWORK"); b.check.box:SetAllPoints(); b.check.box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
    b.check:SetScript("OnClick", function()
        for _, i in ipairs(b.group or {}) do if UI.model then UI.model:ToggleStep(i) end end
        UI.Refresh()
    end)
    b.check:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText("Mark this step done (you did it already). Undo it with its check box in the list.", 1, 1, 1, 1, true); GameTooltip:Show()
    end)
    b.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
    -- Click a step: the box shows it (back or ahead), with the arrow on it (user, 2026-11-14).
    r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, 0.07)
    if r.EnableMouse then r:EnableMouse(true) end
    r:SetScript("OnMouseUp", function(self) if self.step and not self.isHeader then UI.ViewStep(self.step) end end)
    r:SetScript("OnEnter", function(self)
        if not self.step or self.isHeader then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Step " .. self.step, 1, 0.82, 0)
        GameTooltip:AddLine("Click: show this step in the guide, with the arrow on it. From there you can go back to your step or continue from this one.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
        f:SetBackdropColor(0.05, 0.05, 0.06, 0.97); f:SetBackdropBorderColor(0, 0, 0, 1) -- nearly solid: the world doesn't show through
    end
    f:SetMovable(true); f:SetClampedToScreen(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relative, x, y = self:GetPoint()
        DB().point = { point, relative, x, y }
        if UI.PlaceSecure then UI.PlaceSecure(self) end -- its buttons follow
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
    -- The other buttons live in one Menu, so a narrow box never overlaps them (user, 2026-11-13).
    f.hide = Flat(f, "_", 20, 18); f.hide:SetPoint("TOPRIGHT", -4, -4) -- minimize to the round icon
    f.menuButton = Flat(f, "Menu", 44, 18); f.menuButton:SetPoint("RIGHT", f.hide, "LEFT", -4, 0)
    -- One-click actions stay buttons on the strip, next to Menu (user, 2026-11-14: in the menu they looked like
    -- more menus): the map pin and the best step for you.
    f.pin = Flat(f, nil, 20, 18, "Interface\\Icons\\INV_Misc_Map_01"); f.pin:SetPoint("RIGHT", f.menuButton, "LEFT", -4, 0)
    f.best = Flat(f, "Best", 36, 18); f.best:SetPoint("RIGHT", f.pin, "LEFT", -4, 0)
    -- Every step of this part of the route: what you did, where you are, what's next (user, 2026-11-14).
    f.stepsButton = Flat(f, "Steps", 40, 18); f.stepsButton:SetPoint("RIGHT", f.best, "LEFT", -4, 0)
    f.stepsButton:SetScript("OnClick", function()
        DB().listOpen = not DB().listOpen
        UI.follow, UI.scrolled = true, false
        UI.Refresh()
    end)
    -- Viewing a step other than yours: back to yours, or carry on from the one shown.
    f.viewBar = CreateFrame("Frame", nil, f)
    f.viewBar:SetHeight(22)
    f.viewBar.bg = f.viewBar:CreateTexture(nil, "BACKGROUND"); f.viewBar.bg:SetAllPoints(); f.viewBar.bg:SetColorTexture(0.12, 0.2, 0.32, 1)
    f.viewBar.label = Font(f.viewBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 11)
    f.viewBar.label:SetPoint("LEFT", 6, 0)
    f.viewBar.back = Flat(f.viewBar, "Back to my step", 96, 18); f.viewBar.back:SetPoint("RIGHT", -2, 0)
    f.viewBar.go = Flat(f.viewBar, "Continue from here", 116, 18); f.viewBar.go:SetPoint("RIGHT", f.viewBar.back, "LEFT", -4, 0)
    f.viewBar.back:SetScript("OnClick", function() UI.ViewStep(nil) end)
    f.viewBar.go:SetScript("OnClick", function() UI.ContinueFrom(UI.viewing) end)
    f.viewBar:Hide()
    -- The Menu panel (user, 2026-11-14: "menu is really bad"): three titled sections, plain rows, check boxes
    -- for on/off, < value > for sizes, so each row says what it is and whether it's on.
    f.tools = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.tools:SetPoint("TOPRIGHT", f.menuButton, "BOTTOMRIGHT", 0, -2); f.tools:SetWidth(TOOLS_W)
    f.tools:SetFrameStrata("DIALOG")
    if f.tools.SetClampedToScreen then f.tools:SetClampedToScreen(true) end
    if f.tools.SetBackdrop then
        f.tools:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        f.tools:SetBackdropColor(0.06, 0.06, 0.07, 0.98); f.tools:SetBackdropBorderColor(0.3, 0.3, 0.32, 1)
    end
    f.tools:Hide()
    local y = -6
    local function Section(title)
        if y < -6 then
            local line = f.tools:CreateTexture(nil, "BORDER")
            line:SetColorTexture(1, 1, 1, 0.1); line:SetHeight(1)
            line:SetPoint("TOPLEFT", 8, y - 2); line:SetPoint("TOPRIGHT", -8, y - 2)
            y = y - 6
        end
        local fs = Font(f.tools:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"), 10)
        fs:SetPoint("TOPLEFT", 10, y); fs:SetTextColor(1, 0.82, 0); fs:SetText(title)
        y = y - 15
    end
    local function MenuRow(kind, text)
        local b = CreateFrame("Button", nil, f.tools)
        b:SetHeight(MENU_ROW); b:SetPoint("TOPLEFT", 4, y); b:SetPoint("TOPRIGHT", -4, y)
        b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.08)
        local x = 8
        if kind == "toggle" then
            b.box = b:CreateTexture(nil, "ARTWORK"); b.box:SetSize(18, 18); b.box:SetPoint("LEFT", 3, 0)
            b.box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
            b.check = b:CreateTexture(nil, "OVERLAY"); b.check:SetSize(18, 18); b.check:SetPoint("LEFT", 3, 0)
            b.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check"); b.check:Hide()
            x = 25
        end
        b.label = Font(b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 12)
        b.label:SetPoint("LEFT", x, 0); b.label:SetJustifyH("LEFT"); b.label:SetText(text)
        b.text = text
        if kind == "action" then
            b.more = Font(b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), 12)
            b.more:SetPoint("RIGHT", -6, 0); b.more:SetText(">")
        elseif kind == "value" then
            b.up = Flat(b, ">", 18, 16); b.up:SetPoint("RIGHT", -4, 0)
            b.value = Font(b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 12)
            b.value:SetPoint("RIGHT", b.up, "LEFT", -2, 0); b.value:SetWidth(42); b.value:SetJustifyH("CENTER")
            b.value:SetTextColor(1, 0.82, 0)
            b.down = Flat(b, "<", 18, 16); b.down:SetPoint("RIGHT", b.value, "LEFT", -2, 0)
        end
        y = y - MENU_ROW
        return b
    end

    Section("Guide")
    f.styleButton = MenuRow("value", "Guide style")
    f.styleButton.down:SetScript("OnClick", function() UI.SetStyle(-1) end)
    f.styleButton.up:SetScript("OnClick", function() UI.SetStyle(1) end)
    f.styleButton:SetScript("OnClick", function() UI.SetStyle(1) end)
    Tip(f.styleButton, function() return UI.STYLE_TIP[DB().style or "speed"] .. " Include dungeons below adds dungeon quests to any style." end)
    -- Guides: the leveling route or a questline guide (attunements, Cozy Sleeping Bag).
    f.guides = MenuRow("action", "Guides and zones")
    f.arrowToggle = MenuRow("toggle", "Waypoint arrow")
    f.linesToggle = MenuRow("toggle", "Route lines on the map")
    f.dungeonRoute = MenuRow("toggle", "Include dungeons")
    f.dungeonRoute:SetScript("OnClick", function()
        local before = UI.RouteName()
        DB().withDungeons = not DB().withDungeons
        UI.follow, UI.scrolled, UI.section, UI.lastCurrent = true, false, nil, nil
        UI.NoteSwitch(before, UI.RouteName())
        UI.Refresh()
    end)
    Tip(f.dungeonRoute, "Use the route that also takes dungeon quests (Wailing Caverns, Shadowfang Keep...). For players who group; solo players leave it off.")
    Section("Automation")
    f.autoToggle = MenuRow("toggle", "Auto accept and hand in")
    f.vendorToggle = MenuRow("toggle", "Sell junk and repair")
    f.vendorToggle:SetScript("OnClick", function()
        local q = DufforthTweaksHelperQuestAuto
        if q then q.SetVendorEnabled(not q.VendorEnabled()) end
        SetOn(f.vendorToggle, q and q.VendorEnabled())
    end)
    -- Look of the box (user, 2026-11-14): size, opacity, text size, hidden in combat or dungeons.
    Section("Look")
    f.scaleButton = MenuRow("value", "Size")
    f.alphaButton = MenuRow("value", "Opacity")
    f.fontButton = MenuRow("value", "Text size")
    f.combatToggle = MenuRow("toggle", "Hide in combat")
    f.dungeonToggle = MenuRow("toggle", "Hide in dungeons")
    f.tools:SetHeight(-y + 6)
    local function Stepper(b, key, list, default, after)
        local function go(dir)
            DB()[key] = UI.StepIn(list, DB()[key] or default, dir)
            UI.ApplyLook()
            if after then after() end
        end
        b.down:SetScript("OnClick", function() go(-1) end)
        b.up:SetScript("OnClick", function() go(1) end)
        b:SetScript("OnClick", function() go(1) end)
    end
    Stepper(f.scaleButton, "scale", UI.SCALES, 1)
    Stepper(f.alphaButton, "opacity", UI.OPACITIES, 1)
    Stepper(f.fontButton, "fontDelta", UI.FONT_DELTAS, 0, function() UI.Refresh() end)
    f.combatToggle:SetScript("OnClick", function() DB().hideInCombat = not DB().hideInCombat; UI.ApplyLook() end)
    f.dungeonToggle:SetScript("OnClick", function() DB().hideInDungeons = not DB().hideInDungeons; UI.ApplyLook() end)
    f.linesToggle:SetScript("OnClick", function() DB().mapLines = DB().mapLines == false; UI.ApplyLook(); UI.DrawMapLines() end)
    Tip(f.scaleButton, "The size of the guide box and its bar.")
    Tip(f.alphaButton, "How see-through the guide box is.")
    Tip(f.fontButton, "The size of the text in the guide box.")
    Tip(f.combatToggle, "Fades the guide box out while you fight.")
    Tip(f.dungeonToggle, "Fades the guide box out inside dungeons and raids.")
    Tip(f.linesToggle, "Draws the next steps on the world map with numbered dots and lines.")
    Tip(f.vendorToggle, "At a vendor: sells your gray items and repairs your gear by itself. Hold Shift while opening the vendor to skip it once.")
    f.menuButton:SetScript("OnClick", function()
        if f.tools:IsShown() then f.tools:Hide() else f.guideMenu:Hide(); f.tools:Show() end
    end)
    Tip(f.menuButton, "Guides, best step, auto quests, arrow and map pin.")
    f.guideMenu = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.guideMenu:SetPoint("TOPRIGHT", f.menuButton, "BOTTOMRIGHT", 0, -2); f.guideMenu:SetSize(230, 20) -- re-anchored as a fly-out
    f.guideMenu:SetFrameStrata("DIALOG")
    if f.guideMenu.SetBackdrop then
        f.guideMenu:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        f.guideMenu:SetBackdropColor(0.08, 0.08, 0.09, 0.97); f.guideMenu:SetBackdropBorderColor(0, 0, 0, 1)
    end
    f.guideMenu:Hide()
    if f.guideMenu.SetClampedToScreen then f.guideMenu:SetClampedToScreen(true) end
    -- Many zone parts: the menu scrolls with the mouse wheel instead of running off its frame (user, 2026-11-13).
    if f.guideMenu.EnableMouseWheel then f.guideMenu:EnableMouseWheel(true) end
    f.guideMenu:SetScript("OnMouseWheel", function(_, delta) UI.ScrollGuideMenu(delta > 0 and -3 or 3) end)
    f.guideMenu.more = Font(f.guideMenu:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), 11)
    f.guideMenu.more:SetPoint("BOTTOMLEFT", 8, 4); f.guideMenu.more:SetTextColor(0.65, 0.65, 0.65)
    f.guideRows = {}
    for k = 1, MENU_ROWS do
        local r = CreateFrame("Button", nil, f.guideMenu)
        r:SetSize(226, 20); r:SetPoint("TOPLEFT", 2, -2 - (k - 1) * 20)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, 0.1)
        r.label = Font(r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 12)
        r.label:SetPoint("LEFT", 6, 0); r.label:SetPoint("RIGHT", -4, 0); r.label:SetJustifyH("LEFT")
        if r.label.SetWordWrap then r.label:SetWordWrap(false) end
        if r.EnableMouseWheel then r:EnableMouseWheel(true) end
        r:SetScript("OnMouseWheel", function(_, delta) UI.ScrollGuideMenu(delta > 0 and -3 or 3) end)
        r:SetScript("OnClick", function(self)
            if self.isHeader then return end
            if self.bracket then UI.SelectBracket(self.bracket) else UI.SelectGuide(self.guide) end
        end)
        r:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.title or "", 1, 0.82, 0); GameTooltip:AddLine(self.note or "", 1, 1, 1, true); GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:Hide()
        f.guideRows[k] = r
    end
    -- Hover (or click) "Guides and zones": its list flies out to the left of the Menu and stays while the mouse is
    -- on the row or the list; it closes a moment after the mouse leaves both, or with the Menu.
    f.guides:SetScript("OnClick", function() UI.OpenGuideMenu() end)
    f.guides:SetScript("OnEnter", function() UI.OpenGuideMenu() end)
    f.tools:SetScript("OnHide", function() f.guideMenu:Hide() end)
    local listAway, menuAway = 0, 0
    f.tools:SetScript("OnUpdate", function(_, elapsed)
        elapsed = elapsed or 0
        local onList = UI.MouseOver(f.guideMenu) or UI.MouseOver(f.guides)
        -- The guide list: only while you're on it or its row (user, 2026-11-14: it stayed open).
        if f.guideMenu:IsShown() and not onList then
            listAway = listAway + elapsed
            if listAway > 0.3 then f.guideMenu:Hide(); listAway = 0 end
        else
            listAway = 0
        end
        -- The Menu itself: closes a moment after the mouse leaves it, its button and the list.
        if not (onList or UI.MouseOver(f.tools) or UI.MouseOver(f.menuButton)) then
            menuAway = menuAway + elapsed
            if menuAway > 0.8 then f.tools:Hide(); menuAway = 0 end
        else
            menuAway = 0
        end
    end)
    f.best:SetScript("OnClick", function() f.tools:Hide(); UI.GoRecommended() end)
    Tip(f.best, "Go to the best step for you now: the first open step in the part of the route that still gives you experience at your level, going by the quests you have done.")
    f.routePct = Font(f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), 11); f.routePct:SetTextColor(0.65, 0.65, 0.65)
    f.routePct:SetPoint("LEFT", f.skip, "RIGHT", 8, 0)

    -- Errands (train, hearthstone, repair, class quest): a row each, click to point the arrow, X to skip.
    f.errandRows = {}
    for k = 1, 3 do
        local r = CreateFrame("Button", nil, f)
        r:SetHeight(ERRAND_H)
        r.band = r:CreateTexture(nil, "BACKGROUND"); r.band:SetAllPoints(); r.band:SetColorTexture(0.1, 0.14, 0.2, 1)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, 0.08)
        r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(14, 14); r.icon:SetPoint("LEFT", 6, 0)
        r.label = Font(r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 12)
        r.label:SetPoint("LEFT", r.icon, "RIGHT", 5, 0); r.label:SetPoint("RIGHT", -26, 0); r.label:SetJustifyH("LEFT")
        if r.label.SetWordWrap then r.label:SetWordWrap(false) end
        r.skip = Flat(r, "X", 18, 16); r.skip:SetPoint("RIGHT", -3, 0)
        r.skip:SetScript("OnClick", function()
            if r.errand then DB().errandSkip = DB().errandSkip or {}; DB().errandSkip[r.errand.key] = true end
            UI.override = nil
            UI.Refresh()
        end)
        Tip(r.skip, "Done or not needed: hide this errand.")
        r:SetScript("OnClick", function() UI.ErrandClicked(r.errand) end)
        r:SetScript("OnEnter", function(self)
            if not self.errand then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.errand.action, 1, 1, 1, 1, true)
            if self.errand.tip then GameTooltip:AddLine(self.errand.tip, 0.7, 0.7, 0.7, true) end
            GameTooltip:AddLine("Click: point the arrow there.", 0.5, 0.8, 1, true)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:Hide()
        f.errandRows[k] = r
    end
    UI.BuildBar(f)

    -- Active steps, the progress bar, then the extras line.
    f.blocks = {}
    for k = 1, ACTIVE do f.blocks[k] = Block(f) end
    f.title, f.step = f.blocks[1].header, f.blocks[1].action -- the current step
    -- Start quest: uses the quest's item from your bags (a secure button: items are used only from a click).
    -- On UIParent, not the box: a secure child would lock the box during fights (it couldn't hide in combat).
    f.useItem = CreateFrame("Button", "DufforthTweaksHelperGuideUseItem", UIParent, "SecureActionButtonTemplate")
    f.useItem:SetFrameStrata("MEDIUM")
    -- Placed by UI.PlaceSecure on the screen, not anchored to the box: a box a secure button hangs on is locked in
    -- a fight (the game wouldn't let it hide: minimizing in combat left it on screen, 2026-11-14).
    f.useItem:SetSize(96, 20); f.useItem:SetPoint("CENTER", UIParent, "CENTER")
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
    -- The whole-route percent only in the hover: always on screen it was noise (user, 2026-11-13).
    f.progress.pace = Font(f.progress:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 10)
    f.progress.pace:SetPoint("RIGHT", -4, 0); f.progress.pace:SetJustifyH("RIGHT")
    Tip(f.progress, function()
        return "Zone: how much of this part of the route (levels and zone) is done.\n" .. (f.progress.routeText or "")
            .. (UI.PaceText and ("\n" .. UI.PaceText(true)) or "")
    end)
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
    f.pin:SetScript("OnClick", function() f.tools:Hide(); pinned = nil; local i = UI.model:Current(); if i then Pin(UI.model, i) end end)
    f.hide:SetScript("OnClick", function() UI.SetCollapsed(true) end)
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
    Tip(f.hide, "Minimize: the guide shrinks to its round icon. Click the icon, or the minimap button, to open it again.")
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

-- "Step 45  The Mills Overrun  49, 42": the zone and route share are in the progress row above, and the kind is
-- the icon and the stripe (user, 2026-11-13: the block repeated itself).
local function Header(model, group, first)
    local i = group[1]
    local number = #group > 1 and string.format("%d + %d", i, group[#group]) or tostring(i)
    local d = DufforthTweaksHelperGuide.Describe(model, i)
    local quest = d and d.quest and ("  |cffd0d0d0" .. d.quest .. "|r") or ""
    local _, x, y = model:Place(i)
    local at = x and string.format("  |cff888888%d, %d|r", math.floor(x + 0.5), math.floor(y + 0.5)) or ""
    return string.format(first and "|cffffd100Step %s|r%s%s" or "|cffaaaaaaStep %s|r%s%s", number, quest, at)
end

-- The blocks; the first always, the others only while they fit (a small box shows only your step).
local function DrawErrands(f, errands, w, top)
    for k, r in ipairs(f.errandRows) do
        local e = errands[k]
        r.errand = e
        if e then
            r.icon:SetTexture(e.icon)
            r.label:SetText(e.action)
            r:ClearAllPoints(); r:SetPoint("TOPLEFT", f, "TOPLEFT", PAD - 4, top); r:SetWidth(w - 2 * PAD + 8); r:Show()
            top = top - ERRAND_H - 2
        else
            r:Hide()
        end
    end
    return top
end

function UI.ErrandClicked(e)
    if not e or not e.x then return end
    local map = DufforthTweaksHelperGuideData.uiMaps[e.zone]
    if map then UI.override = { map = map, x = e.x, y = e.y, zone = e.zone, text = e.action } end
    UI.Refresh()
end

-- ---- The target and quest item bar (user, 2026-11-14) ----
-- Secure buttons: a click targets the step's monster or NPC, or uses a quest item from your bags.
-- The game allows changing them only out of combat.
local BAR_SIZE, BAR_ITEMS = 30, 6
local function BarButton(parent, name)
    local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
    b:SetSize(BAR_SIZE, BAR_SIZE)
    if b.RegisterForClicks then b:RegisterForClicks("AnyUp", "AnyDown") end -- works with "cast on key down" too
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints()
    b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.2)
    b:Hide()
    return b
end

function UI.BuildBar(f)
    local bar = CreateFrame("Frame", "DufforthTweaksHelperGuideBar", UIParent)
    bar:SetSize(BAR_SIZE, BAR_SIZE); bar:SetPoint("CENTER", UIParent, "CENTER") -- placed by UI.PlaceSecure
    bar.target = BarButton(bar, "DufforthTweaksHelperGuideTarget")
    bar.target:SetPoint("TOPLEFT")
    bar.target.icon:SetTexture("Interface\\Icons\\Ability_Hunter_SniperShot")
    bar.target:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Target " .. (self.who or "?"), 1, 1, 1)
        GameTooltip:AddLine("Works when it's close enough to see.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    bar.target:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar.items = {}
    for k = 1, BAR_ITEMS do
        local b = BarButton(bar, "DufforthTweaksHelperGuideItem" .. k)
        b:SetPoint("TOPLEFT", bar.target, "BOTTOMLEFT", 0, -4 - (k - 1) * (BAR_SIZE + 4))
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            if self.itemID and GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.itemID) else GameTooltip:SetText("Quest item") end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        bar.items[k] = b
    end
    f.questBar = bar
end

-- Who the step is about: the monster to kill or loot from, or the NPC to talk to.
function UI.TargetName(model, i)
    local step = i and model.steps[i]
    if not step then return nil end
    local S = DufforthTweaksHelperGuide.STEP
    local who = model:TalkTo(i)
    if who then return who end
    if step[S.KIND] == "flight" then return string.match(step[S.TEXT] or "", "from (.+)$") end
    local g = model:Goal(i)
    if g then
        if g[1] == "kill" then return g[2] end
        if g[1] == "collect" and g[7] and g[7] ~= "" then return g[7] end
    end
    return nil
end

-- Usable quest items in your bags (quest class with a use effect).
function UI.QuestItems()
    local out, seen = {}, {}
    if not (C_Container and C_Container.GetContainerNumSlots) then return out end
    local spellOf = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if id and not seen[id] then
                seen[id] = true
                local classID = instant and select(6, instant(id))
                if classID == 12 and spellOf and spellOf(id) then out[#out + 1] = { id = id, icon = info.iconFileID } end
            end
        end
    end
    return out
end

-- The secure buttons follow the box on the screen (they can only be moved out of combat), without being anchored
-- to it, so the box itself can hide or minimize in a fight.
function UI.PlaceSecure(f)
    if InCombatLockdown and InCombatLockdown() then return end
    local s = (tonumber((f:GetEffectiveScale())) or 1) / (tonumber((UIParent:GetEffectiveScale())) or 1)
    local left, top = tonumber((f:GetLeft())), tonumber((f:GetTop()))
    if f.questBar and left and top then
        f.questBar:ClearAllPoints(); f.questBar:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", left * s - 4, top * s)
    end
    local b = f.blocks and f.blocks[1]
    local right, btop = b and tonumber((b:GetRight())), b and tonumber((b:GetTop()))
    if f.useItem and right and btop then
        f.useItem:ClearAllPoints(); f.useItem:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right * s - 4, btop * s - 3)
    end
end

function UI.UpdateBar(f, model, current)
    local bar = f.questBar
    if not bar or (InCombatLockdown and InCombatLockdown()) then return end
    local who = DB().shown and UI.TargetName(model, current)
    bar.target.who = who
    if who then
        bar.target:SetAttribute("type", "macro")
        bar.target:SetAttribute("macrotext", "/cleartarget\n/targetexact " .. who)
        bar.target:Show()
    else
        bar.target:Hide()
    end
    local items = DB().shown and UI.QuestItems() or {}
    for k, b in ipairs(bar.items) do
        local it = items[k]
        b.itemID = it and it.id
        if it then
            b:SetAttribute("type", "item"); b:SetAttribute("item", "item:" .. it.id)
            b.icon:SetTexture(it.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            b:Show()
        else
            b:Hide()
        end
    end
    bar:SetShown(who ~= nil or #items > 0)
end

local function DrawBlocks(f, model, adapter, blocks, w, top, bottom)
    local inner, fits = w - 2 * PAD - 12, true
    for k = 1, ACTIVE do
        local b, group = f.blocks[k], blocks[k]
        if group then
            local action, lines, note, kind = GroupText(model, group, adapter)
            local c = KIND[kind] or KIND.travel
            b.accent:SetColorTexture(c[1], c[2], c[3], 1)
            b.group = group
            b.header:SetText(Header(model, group, k == 1))
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
    return DufforthTweaksHelperGuide.Inline(d and d.icon) .. " " .. action .. more
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
    -- Forever's own quests (not in the Classic data the route comes from): from your quest log (user, 2026-11-14).
    for _, q in ipairs(UI.ForeverQuests(model)) do
        items[#items + 1] = { text = "|cffff9933Forever quest:|r " .. q.title .. (q.progress ~= "" and (" |cffaaaaaa" .. q.progress .. "|r") or ""),
            tipTitle = q.title, forever = q,
            tip = { "A quest Forever added: the guide has no route for it, so it follows your quest log.",
                    q.x and "Click: the arrow points at it on your map." or "Its place isn't on this map." } }
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

-- Is the mouse over this frame (shown)? frame:IsMouseOver() where it exists, else MouseIsOver (1/nil on old clients).
function UI.MouseOver(frame)
    if not (frame and frame.IsShown and frame:IsShown()) then return false end
    if frame.IsMouseOver then return frame:IsMouseOver() and true or false end
    return MouseIsOver and MouseIsOver(frame) and true or false
end

-- The guide list as a fly-out beside the Menu's "Guides and zones" row (hover opens it).
function UI.OpenGuideMenu()
    local f = Box()
    if f.guideMenu:IsShown() then return end
    UI.FillGuideMenu() -- first: its width depends on the names
    UI.PlaceGuideMenu()
end

-- Beside the Menu on the side with room, never over it (user, 2026-11-14: with the box near the left edge the
-- list was pushed back on top of the Menu): left, else right, else below.
function UI.SideFor(menuLeft, menuRight, screenRight, width)
    if menuLeft and menuLeft - width - 8 >= 0 then return "left" end
    if menuRight and screenRight and menuRight + width + 8 <= screenRight then return "right" end
    return "below"
end

function UI.PlaceGuideMenu()
    local f = Box()
    local m = f.guideMenu
    local scale = f.tools.GetEffectiveScale and (f.tools:GetEffectiveScale()) or 1
    local uiScale = UIParent.GetEffectiveScale and (UIParent:GetEffectiveScale()) or 1
    local function screen(v) v = tonumber(v); return v and v * (tonumber(scale) or 1) / (tonumber(uiScale) or 1) or nil end
    local width = (tonumber((m:GetWidth())) or 230) * (tonumber(scale) or 1) / (tonumber(uiScale) or 1)
    local side = UI.SideFor(screen((f.tools:GetLeft())), screen((f.tools:GetRight())), tonumber((UIParent:GetRight())), width)
    m:ClearAllPoints()
    if side == "left" then m:SetPoint("TOPRIGHT", f.tools, "TOPLEFT", -4, 0)
    elseif side == "right" then m:SetPoint("TOPLEFT", f.tools, "TOPRIGHT", 4, 0)
    else m:SetPoint("TOPLEFT", f.tools, "BOTTOMLEFT", 0, -4) end
    m.side = side
    if m.SetFrameLevel and f.tools.GetFrameLevel then m:SetFrameLevel((f.tools:GetFrameLevel() or 0) + 10) end
end

function UI.ToggleGuideMenu()
    local f = Box()
    if f.guideMenu:IsShown() then f.guideMenu:Hide(); return end
    UI.FillGuideMenu()
end

function UI.FillGuideMenu()
    local f = Box()
    local data, picked = DufforthTweaksHelperGuideData, DB().guideName
    -- Guides first (always in view), then the leveling route by zone: a click shows that part in the list.
    local entries = { { nil, "Leveling 1-60: " .. UI.STYLE_LABEL[DB().style or "speed"] .. (DB().withDungeons and " + dungeons" or ""),
        (UI.STYLE_TIP[DB().style or "speed"] or "") .. " Change the style in the Menu (Guide style)." } }
    for _, g in ipairs(data.guides or {}) do entries[#entries + 1] = { g.name or g[1], g.name or g[1], g.note or g[2] } end
    entries[#entries + 1] = { nil, "|cffffd100Leveling by zone|r", "", nil, true }
    local leveling = DufforthTweaksHelperGuide.NewModel(data, UI.RaceRoute(), UI.adapter or UI.GameAdapter(), { skipped = {} })
    for _, p in ipairs(leveling:ZoneParts()) do
        entries[#entries + 1] = { nil, "    |cffcccccc" .. p.title .. "|r", "Show this part of the leveling route in the list. Your current step still follows what you have done.", p.first }
    end
    f.guideMenu.entries, f.guideMenu.offset = entries, 0
    UI.DrawGuideMenu()
    f.guideMenu:Show()
end

function UI.ScrollGuideMenu(by)
    local m = Box().guideMenu
    local most = math.max(0, #(m.entries or {}) - MENU_ROWS)
    m.offset = math.max(0, math.min(most, (m.offset or 0) + by))
    UI.DrawGuideMenu()
end

function UI.DrawGuideMenu()
    local f = Box()
    local m, data, picked = f.guideMenu, DufforthTweaksHelperGuideData, DB().guideName
    local entries, offset, widest = m.entries or {}, m.offset or 0, 0
    for k, r in ipairs(f.guideRows) do
        local e = entries[offset + k]
        if e then
            r.guide, r.title, r.note, r.bracket, r.isHeader = e[1], e[2], e[3], e[4] or false, e[5] or false
            local on = not e[4] and not e[5] and ((e[1] == picked) or (e[1] == nil and not (picked and data.routes[picked])))
            r.label:SetText((on and "|cff40ff40> |r" or "   ") .. e[2]); r:Show()
            local sw = tonumber(r.label.GetStringWidth and r.label:GetStringWidth()) or 0
            widest = math.max(widest, sw)
        else
            r:Hide()
        end
    end
    -- As wide as the longest name (within limits), so text stays inside the menu and every row is clickable.
    local w = math.max(MENU_MIN_W, math.min(MENU_MAX_W, widest + 24))
    for _, r in ipairs(f.guideRows) do r:SetWidth(w - 4) end
    local shown = math.min(#entries - offset, MENU_ROWS)
    local below = #entries - offset - shown
    if offset > 0 or below > 0 then
        m.more:SetText(string.format("Scroll for more: %d above, %d below", offset, below)); m.more:Show()
    else
        m.more:SetText(""); m.more:Hide()
    end
    m:SetWidth(w)
    m:SetHeight(4 + shown * 20 + ((offset > 0 or below > 0) and 16 or 0))
end

-- A click on an extra: open or close a list, or point the arrow (and a map pin) at a quest's giver.
function UI.ExtraClicked(item)
    if not item then return end
    if item.forever then
        local q = item.forever
        if q.x and q.map then UI.override = { id = q.id, map = q.map, x = q.x, y = q.y, zone = q.zone, text = "Forever quest: " .. q.title } end
        UI.Refresh()
        return
    end
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
    f.progress.label:SetText(string.format("|cffffd100%s|r   %s   zone %d%%", UI.GuideLabel(), title, math.floor(pct * 100 + 0.5)))
    f.progress.routeText = string.format("Whole route: %d%% done (step %d of %d).", route, current or #model.steps, #model.steps)
    f.progress.pace:SetText(UI.PaceText(false))
    return top - PROGRESS - 4
end

local function DrawList(f, model, adapter, current, w, top, bottom)
    local sections = model:Sections()
    if UI.follow or not UI.section then UI.section = current and model:SectionOf(current) or #sections end
    if UI.jump then UI.section, UI.follow, UI.scrolled = UI.jump, false, true end -- browsed to a part or bracket
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
    -- The step text stays in the guide window (user, 2026-11-13: the arrow repeated it); the arrow shows only
    -- the distance and time, outlined so it reads over any ground (no plate: it looked bad). Step in the tooltip.
    a.label = a:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    a.label:Hide()
    a.dist = a:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    a.dist:SetPoint("TOP", a.pointer, "BOTTOM", 0, -4)
    if a.dist.SetFont then a.dist:SetFont(FONT, 14, "OUTLINE") end
    a.angle = 0
    a:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(self.label:GetText() or "Your guide step", 1, 1, 1, 1, true)
        GameTooltip:AddLine("Points at your guide step. Drag to move, right-click to hide (the arrow button on the guide shows it).", 0.7, 0.7, 0.7, true)
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
    if t.loop and dist < 25 and not UI.loopPending then
        UI.loopPending = true -- next spot of the loop
        local function go() UI.loopPending = false; pcall(UI.Refresh) end
        if C_Timer then C_Timer.After(0.2, go) else go() end
    end
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
    if box and box.arrowToggle then SetOn(box.arrowToggle, DB().arrow) end -- the Menu's check box at once
end

-- ---- Refresh ----
-- ---- Look of the box (user, 2026-11-14) ----
UI.SCALES, UI.OPACITIES, UI.FONT_DELTAS = { 0.8, 0.9, 1, 1.1, 1.25 }, { 0.5, 0.7, 0.85, 1 }, { -1, 0, 2 }
-- One step along an ordered list, stopping at both ends.
function UI.StepIn(list, value, dir)
    local at = 1
    for k, v in ipairs(list) do if math.abs(v - value) < 0.001 then at = k end end
    return list[math.max(1, math.min(#list, at + dir))]
end
local FONT_NAMES = { [0] = "normal", [2] = "large", [-1] = "small" }
function UI.NextIn(list, value)
    for k, v in ipairs(list) do if math.abs(v - value) < 0.001 then return list[k % #list + 1] end end
    return list[1]
end

local function InDungeon()
    if not IsInInstance then return false end
    local inside, kind = IsInInstance()
    return inside and (kind == "party" or kind == "raid") or false
end

-- Size and opacity are always allowed; hiding uses opacity 0 because the box holds secure buttons, which the
-- game doesn't let addons hide during a fight.
-- In a fight: from the events (PLAYER_REGEN_DISABLED comes just before the game's lockdown starts, so
-- InCombatLockdown() still says no there: that's why "Hide in combat" didn't work).
function UI.InCombat()
    if UI.inCombat ~= nil then return UI.inCombat end
    return (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) or false
end

-- The box is out of sight: minimized to the icon, or in a fight / dungeon with those options on, unless you
-- opened it from the icon there (UI.peek).
function UI.Hidden()
    local db = DB()
    if db.collapsed then return true end
    if UI.peek then return false end
    return (db.hideInCombat and UI.InCombat()) or (db.hideInDungeons and InDungeon()) or false
end

function UI.SetCollapsed(on)
    DB().collapsed = on and true or false
    UI.peek = (not on) and (UI.InCombat() or InDungeon()) or nil
    UI.ApplyLook()
    if not on then UI.Refresh() end
end

function UI.ApplyLook()
    local f = box
    if not f then return end
    local db = DB()
    local scale, alpha = db.scale or 1, db.opacity or 1
    local hidden = UI.Hidden()
    f:SetScale(scale); f:SetAlpha(alpha)
    f:SetShown(DB().shown and not hidden)
    -- Secure buttons can't be hidden in a fight: they fade out instead.
    if f.questBar then f.questBar:SetScale(scale); f.questBar:SetAlpha(hidden and 0 or 1) end
    if f.useItem then f.useItem:SetAlpha(hidden and 0 or 1) end
    UI.UpdateIcon()
    for _, entry in ipairs(fonts) do
        if entry[1].SetFont then entry[1]:SetFont(FONT, entry[2] + (db.fontDelta or 0), "") end
    end
    if f.scaleButton then
        f.scaleButton.value:SetText(string.format("%d%%", math.floor(scale * 100 + 0.5)))
        f.alphaButton.value:SetText(string.format("%d%%", math.floor(alpha * 100 + 0.5)))
        f.fontButton.value:SetText(FONT_NAMES[db.fontDelta or 0] or "normal")
        SetOn(f.combatToggle, db.hideInCombat); SetOn(f.dungeonToggle, db.hideInDungeons); SetOn(f.linesToggle, db.mapLines ~= false)
    end
end

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
    if UI.viewing and not model.steps[UI.viewing] then UI.viewing = nil end
    if UI.viewing then blocks = { { UI.viewing } } end -- a step you picked in the list
    -- The Start quest button for an item-started quest whose item is in your bags (not changed in combat).
    if not (InCombatLockdown and InCombatLockdown()) then
        local d = current and DufforthTweaksHelperGuide.Describe(model, current)
        if d and d.useItem then
            f.useItem.item = "item:" .. d.useItem
            f.useItem:SetText(d.useLabel or "Start quest")
            f.useItem:SetAttribute("type", "item"); f.useItem:SetAttribute("item", f.useItem.item)
            f.useItem:Show()
        else
            f.useItem:Hide()
        end
    end
    if current ~= UI.lastCurrent then UI.follow, UI.scrolled, UI.lastCurrent, UI.override = true, false, current, nil end
    f:SetShown(not UI.Hidden())
    local w, h = Size(f)
    f.stepNum:SetText(current or "-")
    f.routePct:SetText("")
    SetOn(f.arrowToggle, DB().arrow)
    if f.dungeonRoute then SetOn(f.dungeonRoute, DB().withDungeons) end
    if f.styleButton then f.styleButton.value:SetText(UI.STYLE_LABEL[DB().style or "speed"]) end
    SetOn(f.autoToggle, DufforthTweaksHelperQuestAuto and DufforthTweaksHelperQuestAuto.Enabled())
    SetOn(f.vendorToggle, DufforthTweaksHelperQuestAuto and DufforthTweaksHelperQuestAuto.VendorEnabled and DufforthTweaksHelperQuestAuto.VendorEnabled())
    local bottom = -(h - 6)
    -- Level, zone and progress: always shown, right under the top strip (user, 2026-11-13).
    f.progress:Show()
    UI.ApplyLook()
    UI.errands = UI.Errands(model, adapter, current)
    local top0 = DrawErrands(f, UI.errands, w, DrawProgress(f, model, current, w, -(STRIP + 3)))
    local note = UI.switchNote
    if note and (GetTime and GetTime() or 0) < note["until"] then
        if not rawget(f, "switchNote") then rawset(f, "switchNote", Font(f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 11)) end
        f.switchNote:ClearAllPoints(); f.switchNote:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, top0 - 2)
        f.switchNote:SetWidth(w - 2 * PAD); f.switchNote:SetJustifyH("LEFT"); f.switchNote:SetText(note.text); f.switchNote:Show()
        top0 = top0 - Height(f.switchNote, note.text) - 6
    elseif rawget(f, "switchNote") then
        f.switchNote:Hide(); UI.switchNote = nil
    end
    if UI.viewing then
        f.viewBar:ClearAllPoints(); f.viewBar:SetPoint("TOPLEFT", f, "TOPLEFT", PAD - 4, top0); f.viewBar:SetWidth(w - 2 * PAD + 8)
        f.viewBar.label:SetText(string.format("Viewing step %d (yours: %s)", UI.viewing, current or "-"))
        f.viewBar:Show()
        top0 = top0 - 24
    else
        f.viewBar:Hide()
    end
    SetOn(f.stepsButton, DB().listOpen)
    if DB().listOpen then h = math.max(h, -top0 + 420); bottom = -(h - 6) end -- room for the part's steps
    local top, fits = DrawBlocks(f, model, adapter, blocks, w, top0, bottom)
    UI.UpdateBar(f, model, current)
    UI.PlaceSecure(f)
    -- The current block is always shown whole: with 2 or 3 steps at the same place the box grows for them, and
    -- shrinks back with fewer (user, 2026-11-13). Your size limits only what comes after it.
    local mustH = math.floor(-top + 8) -- down to the blocks drawn (block 2 only when it fits your size)
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
    f.fitH = math.max(math.min(h, math.floor(-used + 22)), mustH)
    if not f.sizing then f:SetHeight(f.fitH) end
    UI.target = nil
    current = UI.viewing or current -- the arrow and pin follow the step you're looking at
    if current then
        Pin(model, current)
        local zone, x, y, map = model:Place(current)
        local legs = model:Directions(current)
        local first = legs and legs[1]
        if first and first.x and model.data.uiMaps[first.zone] then
            -- Far away: the arrow points at the first leg (the zeppelin tower, the flight master).
            UI.target = { map = model.data.uiMaps[first.zone], x = first.x, y = first.y, zone = first.zone, text = "1. " .. first.text }
        elseif map and model:Loop(current) then
            -- Kill or loot across an area: the arrow circles the spots where they spawn (user, 2026-11-14).
            local loop = model:Loop(current)
            local here, px, py
            if adapter.position then here, px, py = adapter.position() end
            if here ~= zone then px, py = nil, nil end
            UI.loopAt = UI.loopAt or {}
            local k = DufforthTweaksHelperGuide.NextLoopSpot(loop, UI.loopAt[current], px, py)
            UI.loopAt[current] = k
            UI.target = { map = map, x = loop[k][1], y = loop[k][2], zone = zone,
                          text = string.format("Spot %d of %d: ", k, #loop) .. UI.ArrowText(model, blocks[1], adapter), loop = true }
        elseif map and x and y and model:Pinpoint(current) then
            UI.target = { map = map, x = x, y = y, zone = zone, text = UI.ArrowText(model, blocks[1], adapter) }
        end
    end
    local e = UI.errands and UI.errands[1]
    if not UI.override and e and e.x and e.kind ~= "classquest" and model.data.uiMaps[e.zone] then
        UI.target = { map = model.data.uiMaps[e.zone], x = e.x, y = e.y, zone = e.zone, text = e.action } -- errands first
    end
    if UI.override and UI.override.map then UI.target = UI.override end -- you clicked a class or dungeon quest
    UI.UpdateArrow()
end

-- ---- The round icon (user, 2026-11-14): shown while the box is out of sight; a click opens or minimizes the
-- box. Dynamic: it carries the current step's action icon and number, and its tooltip says the step. ----
UI.ICON = "Interface\\AddOns\\DufforthTweaksHelper\\Media\\GuideIcon"
local guideIcon
local function GuideIcon()
    if guideIcon then return guideIcon end
    local b = CreateFrame("Button", "DufforthTweaksHelperGuideIcon", UIParent)
    b:SetSize(40, 40); b:SetFrameStrata("MEDIUM"); b:SetMovable(true); b:EnableMouse(true)
    b:SetClampedToScreen(true); b:RegisterForDrag("LeftButton")
    local p = DB().iconPoint
    if p then b:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else b:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -260, -200) end
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints()
    if b.icon:SetTexture(UI.ICON) == false then b.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end -- new file: needs a full restart
    -- Hover: the icon itself glows (a round glow, user 2026-11-14: the minimap button's highlight sat off-centre
    -- and looked square).
    b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetTexture(UI.ICON)
    b.hl:SetBlendMode("ADD"); b.hl:SetAlpha(0.35)
    -- The current step's icon as a round badge on a dark ring (it was a square).
    b.ring = b:CreateTexture(nil, "OVERLAY", nil, 1); b.ring:SetSize(20, 20); b.ring:SetPoint("BOTTOMRIGHT", 5, -5)
    b.ring:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask"); b.ring:SetVertexColor(0.05, 0.05, 0.05, 1)
    b.badge = b:CreateTexture(nil, "OVERLAY", nil, 2); b.badge:SetSize(16, 16); b.badge:SetPoint("CENTER", b.ring, "CENTER")
    if b.badge.SetMask then b.badge:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask") end
    b.num = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.num:SetPoint("TOP", b, "BOTTOM", 0, -1)
    b:SetScript("OnDragStart", function(self) self:StartMoving() end)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relative, x, y = self:GetPoint()
        DB().iconPoint = { point, relative, x, y }
    end)
    b:SetScript("OnClick", function() UI.SetCollapsed(not UI.Hidden() and true or false) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Leveling guide", 1, 0.82, 0)
        if self.text then GameTooltip:AddLine(self.text, 1, 1, 1, true) end
        GameTooltip:AddLine(UI.Hidden() and "Click: open the guide. Drag: move." or "Click: minimize the guide. Drag: move.", 0.6, 0.8, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    guideIcon = b
    return b
end

-- The icon (and the minimap button's badge) show the current step.
function UI.UpdateIcon()
    if not DufforthTweaksHelperGuide then return end
    local b = GuideIcon()
    local model, current = UI.model, UI.lastCurrent
    local d = model and current and DufforthTweaksHelperGuide.Describe(model, current)
    b.badge:SetTexture(d and d.icon or nil); b.badge:SetShown(d ~= nil); b.ring:SetShown(d ~= nil)
    b.num:SetText(current and ("Step " .. current) or "")
    b.text = d and string.gsub(d.action or "", "|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") or nil
    local show = DB().shown and UI.Hidden()
    b:SetShown(show and true or false)
    if DufforthTweaksHelperMinimap_SetBadge then DufforthTweaksHelperMinimap_SetBadge(show and d and d.icon or nil) end
end

-- Show one step from the list (nil: back to yours).
function UI.ViewStep(i)
    UI.viewing = i
    UI.override = nil
    UI.Refresh()
end

-- Carry on from the step shown: the guide starts there (earlier open steps are left behind).
function UI.ContinueFrom(i)
    if not (i and UI.model) then return end
    UI.model:SetStart(i)
    UI.viewing, UI.follow, UI.scrolled, UI.lastCurrent = nil, true, false, nil
    UI.Refresh()
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
    "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "TAXIMAP_OPENED", "HEARTHSTONE_BOUND", "BAG_UPDATE_DELAYED",
    "PLAYER_REGEN_ENABLED", "LEARNED_SPELL_IN_SKILL_LINE", "SPELLS_CHANGED", "PLAYER_XP_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD" }) do pcall(watcher.RegisterEvent, watcher, event) end
local soon = false
watcher:SetScript("OnEvent", function(_, event)
    if event == "TAXIMAP_OPENED" then pcall(UI.LearnFlights); pcall(UI.AutoFly) end
    if event == "HEARTHSTONE_BOUND" and GetRealZoneText then DB().homeZone = GetRealZoneText() end
    if event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" or event == "PLAYER_LOGIN" then pcall(UI.TrackXP) end
    if event == "PLAYER_REGEN_DISABLED" then UI.inCombat = true end
    if event == "PLAYER_REGEN_ENABLED" then UI.inCombat = false; UI.peek = nil end
    if event == "PLAYER_ENTERING_WORLD" then UI.peek = nil end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ENTERING_WORLD" then pcall(UI.ApplyLook) end
    if event == "PLAYER_REGEN_DISABLED" then return end -- fading out needs no redraw
    if soon then return end
    soon = true
    local function go() soon = false; pcall(UI.Refresh) end
    if C_Timer then C_Timer.After(0.5, go) else go() end
end)
