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

local L = DufforthTweaksHelperL or setmetatable({}, { __index = function(_, k) return k end })
local UI = {}
DufforthTweaksHelperGuideUI = UI

local function DB()
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    local g = DufforthTweaksHelperDB.guide or {}
    DufforthTweaksHelperDB.guide = g
    if g.shown == nil then g.shown = true end
    if g.showDone == nil then g.showDone = true end
    if g.listV ~= 2 then g.showDone, g.listV = true, 2 end -- 4.28: the list shows the steps behind you (user)
    -- 4.37.4: a right-click on the arrow used to hide it, often by accident ("no waypoint"); turn it back on once.
    if g.arrowV ~= 1 then g.arrow, g.arrowV = nil, 1 end
    if g.showNext == nil then g.showNext = true end
    if g.arrow == nil then g.arrow = true end
    -- 4.22.0 saved the size the game restored from an older, smaller box: start fresh once.
    -- 4.37.6: RestedXP's size (user, 2026-11-28: "the windows is using to much spaces"): start the new width once.
    if (tonumber(g.sizeV) or 0) < 3 then g.size, g.sizeV = nil, 3 end
    g.routes = g.routes or {}
    return g
end
UI.DB = DB

-- Your place in each route, per character (2026-11-27: two characters of the same start shared one pointer, so the
-- Orc Hunter's guide showed the warrior's place). The old shared places stay unused under DB().routes.
function UI.Saved(name)
    local db = DB()
    local key = UnitGUID and UnitGUID("player")
    if not key or key == "" then
        local n, last = UnitName and UnitName("player")
        key = tostring(n) .. " " .. tostring(last or "")
    end
    db.chars = db.chars or {}
    local c = db.chars[key] or {}
    db.chars[key] = c
    c.routes = c.routes or {}
    local saved = c.routes[name] or {}
    c.routes[name] = saved
    return saved
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
    local a = {
        level = function() return UnitLevel and UnitLevel("player") or 1 end,
        classBit = function() return classID and 2 ^ (classID - 1) or 1 end,
        raceBit = function() return DufforthTweaksHelperGuide.RACE_BITS[race] or 2 end,
        done = function(id) return C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id) and true or false end,
        inLog = function(id) return inLog[id] == true end,
        complete = function(id) return C_QuestLog and C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) and true or false end,
        zone = function() return DufforthTweaksHelperLocale.ZoneName() end,
        -- The game's progress lines for a quest in your log: { {text, finished} }.
        objectives = function(id)
            if not inLog[id] or not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return nil end
            local ok, list = pcall(C_QuestLog.GetQuestObjectives, id)
            return ok and type(list) == "table" and #list > 0 and list or nil
        end,
        -- One objective by its name in the game's line ("6/12 Raptor Head"): true/false, nil if not found.
        -- Matched by name, or on a Spanish client by kind, order and count (Guide.MatchObjective).
        objectiveDone = function(id, name, goal, goals)
            if not inLog[id] or not name or not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return nil end
            local ok, list = pcall(C_QuestLog.GetQuestObjectives, id)
            if not ok or type(list) ~= "table" then return nil end
            local k = DufforthTweaksHelperGuide.MatchObjective(list, goal or { [2] = name }, goals)
            if k then return list[k].finished and true or false end
            return nil
        end,
        -- The quest's title in the client's language (Spanish clients only; English uses the route data).
        questTitle = function(id)
            local loc = DufforthTweaksHelperLocale
            if not (loc and loc.spanish and C_QuestLog) then return nil end
            local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
            if (not title or title == "") and C_QuestLog.GetQuestInfo then title = C_QuestLog.GetQuestInfo(id) end
            return type(title) == "string" and title ~= "" and title or nil
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
        -- Questie's place for a quest our data can't place (user, 2026-11-14).
        questieSpot = function(id) return UI.QuestieSpot(id) end,
        -- Yards from you to a zone spot, nil if unknown or on another continent.
        yardsTo = function(zone, x, y) return UI.YardsTo and UI.YardsTo(zone, x, y) or nil end,
        -- Yards between two zone spots on the same continent (nil otherwise): picks the right boat or zeppelin.
        worldDistance = function(z1, x1, y1, z2, x2, y2) return UI.WorldDistance and UI.WorldDistance(z1, x1, y1, z2, x2, y2) or nil end,
        -- Where you stand: zone name and map % (the nearest open objective comes first).
        position = function()
            local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
            local pos = map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
            local info = map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
            if not (pos and info and info.name) then return nil end
            local x, y
            if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
            if not x then return nil end
            return DufforthTweaksHelperLocale.MapZone(map) or DufforthTweaksHelperLocale.EnglishZone(info.name), x * 100, y * 100
        end,
        logIds = LogIds,
    }
    -- RestedXP's step engine reads more of the game (GuideRxUI.lua).
    local rx = DufforthTweaksHelperGuideRxUI
    if rx and rx.Extend then rx.Extend(a) end
    return a
end

-- The zone your hearthstone takes you to (saved when you set it; a capital also from its name) and ready or not.
local HEARTHSTONE = 6948
local CAPITALS = { Orgrimmar = true, ["Thunder Bluff"] = true, Undercity = true }
function UI.Hearth()
    local home = DB().homeZone
    if not home and GetBindLocation then
        local bind = GetBindLocation()
        bind = DufforthTweaksHelperLocale.EnglishZone(bind)
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
    local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
    if not ok or not pos then return nil end
    local a, b
    if pos.GetXY then a, b = pos:GetXY() else a, b = pos.x, pos.y end
    return a and { a, b, continent } or nil
end

function UI.WorldDistance(z1, x1, y1, z2, x2, y2)
    local maps = UI.model and UI.model.data and UI.model.data.uiMaps
    if not (maps and maps[z1] and maps[z2]) then return nil end
    local a = WorldOf(maps[z1], (x1 or 50) / 100, (y1 or 50) / 100)
    local b = WorldOf(maps[z2], (x2 or 50) / 100, (y2 or 50) / 100)
    if not (a and b) or a[3] ~= b[3] then return nil end
    return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2)
end

-- Yards from you to a spot (zone, map %), nil when unknown or on another continent.
function UI.YardsTo(zone, x, y)
    local maps = UI.model and UI.model.data and UI.model.data.uiMaps
    if not (maps and maps[zone] and x and y and C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local here = C_Map.GetBestMapForUnit("player")
    local pos = here and C_Map.GetPlayerMapPosition(here, "player")
    if not pos then return nil end
    local px, py
    if pos.GetXY then px, py = pos:GetXY() else px, py = pos.x, pos.y end
    local a, b = px and WorldOf(here, px, py), WorldOf(maps[zone], x / 100, y / 100)
    if not (a and b) or a[3] ~= b[3] then return nil end
    return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2)
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
        local n = { index = i, name = DufforthTweaksHelperLocale.EnglishNode(TaxiNodeName(i)), type = TaxiNodeGetType(i) }
        if want and taxiMap and TaxiNodePosition then
            local x, y = TaxiNodePosition(i)
            local w = x and WorldOf(taxiMap, x, y)
            if w then n.dist = (w[1] - want[1]) ^ 2 + (w[2] - want[2]) ^ 2 end
        end
        nodes[#nodes + 1] = n
    end
    local pick = DufforthTweaksHelperGuide.PickTaxiNode(nodes, fm[2])
    if pick then UI.OfferFlight(pick, TaxiNodeName(pick)) end
end

-- Ask before flying (user, 2026-11-15: "make me confirm if i want to fly when you are auto using the fly path"): a
-- Yes/No window on screen; Yes takes the flight (a click, so the game allows it).
function UI.OfferFlight(index, name)
    if not (StaticPopupDialogs and StaticPopup_Show) then return end
    StaticPopupDialogs.DUFFORTH_GUIDE_FLY = StaticPopupDialogs.DUFFORTH_GUIDE_FLY or {
        text = L["Guide: fly to %s?"], button1 = YES or L["Yes"], button2 = NO or L["No"],
        OnAccept = function(_, data) if data and TakeTaxiNode then TakeTaxiNode(data) end end,
        timeout = 0, whileDead = false, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("DUFFORTH_GUIDE_FLY", name or "?", nil, index)
end

-- ---- Flight time left (user, 2026-11-15) ----
-- TakeTaxiNode (yours or the guide's) starts a timer; while you're on the flight path the box says when you land, and
-- each real flight's time is kept per route (DB().flightTimes["from|to"]) for the next estimate.
function UI.FlightStarted(from, to, estimate)
    UI.flight = { from = from, to = to, total = estimate or 60, startedAt = GetTime and GetTime() or 0, seenOnTaxi = false }
    if C_Timer and C_Timer.NewTicker and not UI.flightTicker then
        UI.flightTicker = C_Timer.NewTicker(1, function() pcall(UI.FlightCheck) end)
    end
end

-- short = true: only the time ("Landing in 1:40"), for a narrow box.
function UI.FlightText(short)
    local fl = UI.flight
    if not fl then return nil end
    local left = DufforthTweaksHelperGuide.FlightLeft(fl.startedAt, fl.total, GetTime and GetTime() or 0)
    if short then return string.format(L["Landing in %d:%02d"], math.floor(left / 60), left % 60) end
    return string.format(L["Flying to %s: landing in %d:%02d"], fl.to or "?", math.floor(left / 60), left % 60)
end

function UI.FlightCheck()
    local fl = UI.flight
    if not fl then return end
    local onTaxi = UnitOnTaxi and UnitOnTaxi("player")
    local now = GetTime and GetTime() or 0
    if onTaxi then fl.seenOnTaxi = true
    elseif fl.seenOnTaxi or now - fl.startedAt > 15 then
        -- Landed (or the flight never started): keep the real time of a full flight.
        if fl.seenOnTaxi and fl.from and fl.to then
            DB().flightTimes = DB().flightTimes or {}
            DB().flightTimes[fl.from .. "|" .. fl.to] = math.floor(now - fl.startedAt + 0.5)
        end
        UI.flight = nil
        if UI.flightTicker and UI.flightTicker.Cancel then UI.flightTicker:Cancel() end
        UI.flightTicker = nil
    end
    -- Refit the whole bar each second: setting only the right-hand text let a long flight text run
    -- over the zone title (user screenshot, 2026-11-21).
    local f = DufforthTweaksHelperGuideBox -- (the box's local is declared further down)
    if f and f.progress and f.progress.pace then UI.FitProgress(f) end
end

-- Every flight you take: from the node you stand at to the one you picked, with the best estimate.
if hooksecurefunc and TakeTaxiNode then
    hooksecurefunc("TakeTaxiNode", function(index)
        pcall(function()
            local from
            for i = 1, (NumTaxiNodes and NumTaxiNodes() or 0) do
                if TaxiNodeGetType(i) == "CURRENT" then from = TaxiNodeName(i) end
            end
            local to = TaxiNodeName(index)
            local yards
            local map = GetTaxiMapID and GetTaxiMapID()
            if map and TaxiNodePosition then
                local here
                for i = 1, NumTaxiNodes() do if TaxiNodeGetType(i) == "CURRENT" then here = i end end
                local ax, ay = TaxiNodePosition(here or index)
                local bx, by = TaxiNodePosition(index)
                local a, b = ax and WorldOf(map, ax, ay), bx and WorldOf(map, bx, by)
                if a and b then yards = math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2) end
            end
            UI.FlightStarted(from, to, DufforthTweaksHelperGuide.FlightEstimate(DB().flightTimes, from, to, yards))
        end)
    end)
end

-- ---- The guide log (user, 2026-11-14): what happens in game and the settings, in the saved file
-- (DufforthTweaksHelperDB.guideLog), so problems can be solved from facts. Read with tools/read_guide_log.py. ----
local function LogBook()
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    DufforthTweaksHelperDB.guideLog = DufforthTweaksHelperDB.guideLog or {}
    return DufforthTweaksHelperDB.guideLog
end
local function Stamp() return date and date("%m-%d %H:%M:%S") or nil end
function UI.Log(kind, message) pcall(DufforthTweaksHelperGuide.LogAdd, LogBook(), kind, message, Stamp()) end
function UI.LogChange(key, kind, message) pcall(DufforthTweaksHelperGuide.LogChange, LogBook(), key, kind, message, Stamp()) end
local function Plain(text) return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")) end
UI.Plain = Plain

-- Every guide setting with a plain value, sorted: "arrow=true collapsed=false ...".
function UI.SettingsLine()
    local keys = {}
    for k, v in pairs(DB()) do
        local t = type(v)
        if t == "boolean" or t == "number" or t == "string" then keys[#keys + 1] = k end
    end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(DB()[k]) end
    return table.concat(parts, " ")
end

function UI.LogLogin()
    local version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("DufforthTweaksHelper", L["Version"]))
        or (GetAddOnMetadata and GetAddOnMetadata("DufforthTweaksHelper", L["Version"])) or "?"
    local build = GetBuildInfo and select(2, GetBuildInfo()) or "?"
    local _, race = UnitRace and UnitRace("player")
    local _, class = UnitClass and UnitClass("player")
    UI.Log("login", string.format(L["addon %s, game build %s, %s %s level %s, zone %s, route %s"], version, tostring(build), tostring(race),
        tostring(class), tostring(UnitLevel and UnitLevel("player")), tostring(GetRealZoneText and GetRealZoneText()), tostring(UI.RouteName())))
    UI.Log("settings", UI.SettingsLine())
    -- Forever's quest log size: the routes are planned for 40 (2026-11-14); this confirms it.
    local okm, max = pcall(function() return C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept() end)
    UI.Log("questlog", "holds " .. tostring(okm and max or "?") .. " quests (routes planned for 40)")
end

-- ---- Route lines and step numbers on the world map (user, 2026-11-14) ----
-- Each place of the steps ahead gets a round pin with the guide's own step number ("188-189" when several steps
-- are at one spot; user: "see in the map the step number in each specific place"). The current step is gold. Hover:
-- what to do there; click: shows that step in the box. Lines join the first places in route order.
UI.MAP_STEPS = 10 -- steps ahead with pins (user, 2026-11-14: "only the next 10 steps at max")
UI.PIN_PX = 26 -- pins closer than this on screen become one
UI.MAP_LINES = 10 -- pins joined by the route line
local mapLines
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function MapPin(frame, k, pool)
    pool = pool or mapLines.dots
    local pin = pool[k]
    if pin then return pin end
    pin = CreateFrame("Button", nil, frame)
    pin.ring = pin:CreateTexture(nil, "BACKGROUND"); pin.ring:SetAllPoints()
    pin.fill = pin:CreateTexture(nil, "ARTWORK")
    pin.fill:SetPoint("TOPLEFT", 2, -2); pin.fill:SetPoint("BOTTOMRIGHT", -2, 2)
    pin.num = pin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); pin.num:SetPoint("CENTER", 0, 0)
    -- Only the number, with a dark outline so it reads on any map; no circle behind it (user, 2026-11-14: "putting the
    -- number in a black circle is too much, I cannot see what is behind").
    local font, size = pin.num:GetFont()
    if font then pin.num:SetFont(font, (size or 12) + 2, "OUTLINE") end
    rawset(pin.num, "fontFlags", "OUTLINE")
    pin:SetScript("OnEnter", function(self)
        local model = UI.model
        if not (model and GameTooltip and self.steps) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText((#self.steps > 1 and L["Steps "] or L["Step "]) .. (self.title or self.label or ""), 1, 0.82, 0)
        for n, i in ipairs(self.steps) do
            if n > 5 then GameTooltip:AddLine(string.format(L["and %d more"], #self.steps - 5), 0.7, 0.7, 0.7); break end
            local d = DufforthTweaksHelperGuide.Describe(model, self.rowOf and self.rowOf[i] or i)
            GameTooltip:AddLine(string.format("%d. %s", i, d and d.action or "?"), 1, 1, 1, true)
        end
        GameTooltip:AddLine(L["Click: show this step in the guide"], 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    pin:SetScript("OnClick", function(self)
        if self.steps then UI.ViewStep(self.rowOf and self.rowOf[self.steps[1]] or self.steps[1]) end
    end)
    pool[k] = pin
    return pin
end

local function Shape(pin, wide, current)
    -- Just the number: gold for your current step, white for the others (no circle: it hid the map).
    pin.ring:Hide(); pin.fill:Hide()
    pin.num:SetTextColor(current and 1 or 1, current and 0.82 or 1, current and 0 or 1)
end

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
    -- Above the map's own layers (the zone highlight drew over the pins and dimmed them; user screenshot).
    -- Capped: the game allows levels up to 10000, and with 4.37.4's +1000 the pins vanished (user, 2026-11-14).
    local base = tonumber(canvas.GetFrameLevel and (canvas:GetFrameLevel())) or 0
    local level = math.min(base + 500, 9000)
    frame:SetFrameLevel(level)
    for _, l in ipairs(mapLines.lines) do l:Hide() end
    for _, d in ipairs(mapLines.dots) do d:Hide() end
    mapLines.hbdDots = mapLines.hbdDots or {}
    for _, d in ipairs(mapLines.hbdDots) do d:Hide() end
    -- Pins through HereBeDragons when it's loaded (Questie ships it, and Questie's map icons show for the user while our
    -- own layer's pins did not; user, 2026-11-14: "why im not seeing the quest number steps in the map").
    local hbd = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
    if hbd then pcall(hbd.RemoveAllWorldMapIcons, hbd, UI) end
    UI.mapPinsVia = hbd and "HereBeDragons" or "own layer"
    UI.mapPins = {}
    local model = UI.model
    if not model or DB().mapLines == false or not DB().shown then return end
    local mapID, entries = WorldMapFrame:GetMapID(), {}
    local current = model:Current()
    -- RestedXP's route: a pin at every point of the active steps, numbered by step (the arrow's step in gold), and a
    -- line along each step's points (RestedXP's map.lua).
    local rxPins = model.rxp and model.RxPins and model:RxPins() or nil
    local rowOf, segments = nil, {}
    if rxPins then
        local onMap = {}
        rowOf = {}
        for _, p in ipairs(rxPins) do
            if model.data.uiMaps[p.zone] == mapID then
                entries[#entries + 1] = { p.n, p.x, p.y }
                onMap[#onMap + 1] = p
                rowOf[p.n] = rowOf[p.n] or p.row
                if p.arrow then current = p.n end
            end
        end
        segments = model:RxPinLines(onMap)
    else
        for _, i in ipairs(model:Upcoming(UI.MAP_STEPS)) do
            local _, x, y, map = model:Place(i)
            if map == mapID and x and y then entries[#entries + 1] = { i, x, y } end
        end
    end
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    -- Same size on screen at any zoom.
    local scale = WorldMapFrame.GetCanvasScale and tonumber((WorldMapFrame:GetCanvasScale())) or 1
    scale = (scale and scale > 0) and 1 / scale or 1
    -- Pins that would touch on screen become one (at Ratchet two sat on each other).
    local near = UI.PIN_PX * scale
    local pins = DufforthTweaksHelperGuide.MapPins(entries, w > 0 and near / w * 100 or nil, h > 0 and near / h * 100 or nil)
    UI.mapPins = pins
    -- What was drawn, saved for reading the file after /reload when pins don't show.
    DB().mapDebug = { map = mapID, steps = #entries, pins = #pins, w = w, h = h, scale = scale, level = level,
        canvasLevel = base, at = date and date("%H:%M:%S") or nil }
    UI.mapCheckDue = true
    for k, p in ipairs(pins) do
        local pin = hbd and MapPin(UIParent, k, mapLines.hbdDots) or MapPin(frame, k)
        local isCurrent = false
        for _, i in ipairs(p.steps) do if i == current then isCurrent = true end end
        pin.steps, pin.label, pin.title, pin.rowOf = p.steps, p.label, p.title, rowOf
        local label = p.label
        if model and model.rxp and model.RxNumber and label then
            label = string.gsub(tostring(label), "%d+", function(d) return tostring(model:RxNumber(tonumber(d)) or d) end)
        end
        pin.num:SetText(label)
        local textW = tonumber(pin.num.GetStringWidth and (pin.num:GetStringWidth())) or 0
        pin:SetSize(math.max(16, textW + 4), 18) -- as big as the number: hover and click on it
        Shape(pin, false, isCurrent)
        if hbd then
            -- HereBeDragons places, scales and shows it on this map (the map's own pin system).
            if pin.SetScale then pin:SetScale(1) end
            local ok = pcall(hbd.AddWorldMapIconMap, hbd, UI, pin, mapID, p.x / 100, p.y / 100)
            if ok then pin:Show() end
        else
            if pin.SetScale then pin:SetScale(scale) end
            pin:SetFrameLevel((tonumber((frame:GetFrameLevel())) or 0) + (isCurrent and 20 or 10))
            pin:ClearAllPoints(); pin:SetPoint("CENTER", frame, "TOPLEFT", p.x / 100 * w / scale, -p.y / 100 * h / scale)
            pin:Show()
        end
        if not rxPins and k > 1 and k <= UI.MAP_LINES then UI.MapLine(frame, k - 1, pins[k - 1], p, w, h) end
    end
    for s, seg in ipairs(segments) do UI.MapLine(frame, s, seg[1], seg[2], w, h) end
end

-- Line k of the route on the map, from a to b (map %).
function UI.MapLine(frame, k, a, b, w, h)
    if not frame.CreateLine then return end
    local line = mapLines.lines[k]
    if not line then
        line = frame:CreateLine(nil, "OVERLAY")
        if line then line:SetThickness(3); line:SetColorTexture(1, 0.82, 0, 0.8) end
        mapLines.lines[k] = line
    end
    if line then
        line:SetStartPoint("TOPLEFT", frame, a.x / 100 * w, -a.y / 100 * h)
        line:SetEndPoint("TOPLEFT", frame, b.x / 100 * w, -b.y / 100 * h)
        line:Show()
    end
end

-- Minimap pins (RestedXP shows the active steps' points there too): through HereBeDragons, which Questie ships;
-- without it there are none (the arrow still points).
UI.miniDots, UI.MINIMAP_REF = {}, {}
function UI.DrawMinimapPins(model)
    local hbd = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
    if not hbd then return end
    pcall(hbd.RemoveAllMinimapIcons, hbd, UI.MINIMAP_REF)
    for _, d in ipairs(UI.miniDots) do d:Hide() end
    if not (model and model.rxp and model.RxPins) or DB().mapLines == false or not DB().shown then return end
    local maps = model.data.uiMaps
    local k = 0
    for _, p in ipairs(model:RxPins()) do
        local map = maps[p.zone]
        if map then
            k = k + 1
            local pin = MapPin(Minimap or UIParent, k, UI.miniDots)
            local shown = tostring(model.RxNumber and model:RxNumber(p.n) or p.n) -- RestedXP's number in the part
            pin.steps, pin.label, pin.title, pin.rowOf = { p.n }, shown, shown, { [p.n] = p.row }
            pin.num:SetText(shown)
            pin:SetSize(18, 14)
            Shape(pin, false, p.arrow)
            if pcall(hbd.AddMinimapIconMap, hbd, UI.MINIMAP_REF, pin, map, p.x / 100, p.y / 100, true, false) then pin:Show() end
        end
    end
end
-- Is what we drew really on screen? Logged a moment after drawing (user, 2026-11-14: "I dont see any step number in
-- the map": the file said 4 pins were drawn).
function UI.MapCheckLine()
    local function S(v) return tostring(v) end -- tostring with no value errors (a method returning nothing)
    local f = mapLines and mapLines.frame
    if not f then return L["no pin layer"] end
    local function num(v) v = tonumber(v); return v and string.format("%.0f", v) or "nil" end
    local function vis(o) return o and o.IsVisible and S(o:IsVisible()) or "?" end
    local parts = { string.format(L["layer visible=%s shown=%s size=%sx%s scale=%s level=%s alpha=%s"], vis(f), S(f.IsShown and f:IsShown()),
        num(f.GetWidth and f:GetWidth()), num(f.GetHeight and f:GetHeight()), S(f.GetEffectiveScale and f:GetEffectiveScale()),
        S(f.GetFrameLevel and f:GetFrameLevel()), S(f.GetEffectiveAlpha and f:GetEffectiveAlpha())) }
    local canvas = WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
    if canvas then
        parts[#parts + 1] = string.format(L["canvas visible=%s size=%sx%s strata=%s"], vis(canvas), num(canvas:GetWidth()), num(canvas:GetHeight()),
            S(canvas.GetFrameStrata and canvas:GetFrameStrata()))
    end
    parts[#parts + 1] = "pins via " .. S(UI.mapPinsVia)
    local pin = (UI.mapPinsVia == "HereBeDragons" and mapLines.hbdDots and mapLines.hbdDots[1]) or mapLines.dots[1]
    if pin then
        local x, y
        if pin.GetCenter then x, y = pin:GetCenter() end
        parts[#parts + 1] = string.format(L["pin1 \"%s\" visible=%s shown=%s center=%s,%s size=%sx%s scale=%s strata=%s"], S(pin.num and pin.num.GetText and pin.num:GetText()),
            vis(pin), S(pin.IsShown and pin:IsShown()), num(x), num(y), num(pin.GetWidth and pin:GetWidth()), num(pin.GetHeight and pin:GetHeight()),
            S(pin.GetEffectiveScale and pin:GetEffectiveScale()), S(pin.GetFrameStrata and pin:GetFrameStrata()))
    end
    local d = DB().mapDebug or {}
    return string.format(L["map %s: %s steps, %s pins; "], S(d.map), S(d.steps), S(d.pins)) .. table.concat(parts, "; ")
end

-- Drawing errors are kept (DB().mapError and the log), not lost in a silent pcall.
function UI.SafeDrawMap()
    local ok, err = pcall(UI.DrawMapLines)
    if not ok then DB().mapError = tostring(err); UI.Log("error", "map: " .. tostring(err)) elseif DB().mapError then DB().mapError = nil end
    if UI.mapCheckDue then
        UI.mapCheckDue = false
        local function check() local okc, line = pcall(UI.MapCheckLine); UI.LogChange("map", "map", okc and line or (L["check failed: "] .. tostring(line))) end
        if C_Timer then C_Timer.After(0.5, check) else check() end
    end
end
if WorldMapFrame then
    if WorldMapFrame.HookScript then WorldMapFrame:HookScript("OnShow", function() UI.SafeDrawMap() end) end
    local scroll = WorldMapFrame.ScrollContainer
    if scroll and scroll.HookScript and C_Timer then -- zooming changes which pins touch
        scroll:HookScript("OnMouseWheel", function() C_Timer.After(0.15, function() UI.SafeDrawMap() end) end)
    end
    if hooksecurefunc and WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", function() UI.SafeDrawMap() end) end
end

-- ---- Forever's own quests, from your quest log (user, 2026-11-14) ----
-- Forever's public data has only their numbers, so their names, progress and places come from the game.
-- ---- Questie's data (user, 2026-11-14: "use the current information that questie is providing") ----
-- Questie (12.8, with a Forever edition) knows where each quest's monsters, objects and item drops are. Read through
-- its loader, every call in pcall: if Questie is missing or changes, the guide just has no answer.
local function QuestieModules()
    if not (QuestieLoader and QuestieLoader.ImportModule) then return nil end
    local ok, db = pcall(QuestieLoader.ImportModule, QuestieLoader, L["QuestieDB"])
    local okz, zones = pcall(QuestieLoader.ImportModule, QuestieLoader, L["ZoneDB"])
    if not (ok and type(db) == "table" and db.GetQuest and okz and type(zones) == "table" and zones.GetUiMapIdByAreaId) then return nil end
    return db, zones
end

local function ZoneNameOf(uiMap)
    for name, id in pairs(DufforthTweaksHelperGuideData and DufforthTweaksHelperGuideData.uiMaps or {}) do
        if id == uiMap then return name end
    end
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(uiMap)
    return info and info.name
end

-- Questie spawns { [areaId] = { {x, y}, ... } } -> the spot nearest you (on your map first): { zone, x, y, d }.
local function NearestSpawn(zones, spawns, best)
    if type(spawns) ~= "table" then return best end
    local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pos = here and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(here, "player")
    local px, py
    if pos then if pos.GetXY then px, py = pos:GetXY() else px, py = pos.x, pos.y end end
    for areaId, list in pairs(spawns) do
        local okm, ui = pcall(zones.GetUiMapIdByAreaId, zones, areaId)
        local zone = okm and ui and ZoneNameOf(ui)
        if zone and type(list) == "table" then
            for _, p in ipairs(list) do
                if type(p) == "table" and p[1] and p[2] then
                    local d = (ui == here and px) and ((p[1] - px * 100) ^ 2 + (p[2] - py * 100) ^ 2) or 1e6
                    if not best or d < best.d then best = { zone = zone, x = p[1], y = p[2], d = d } end
                end
            end
        end
    end
    return best
end

-- Where quest id's first unfinished objective is, by Questie: zone, x, y, what; nil when Questie can't tell.
function UI.QuestieSpot(id)
    local db, zones = QuestieModules()
    if not db then return nil end
    local ok, quest = pcall(db.GetQuest, id)
    if not ok or type(quest) ~= "table" then return nil end
    local log = {}
    local okl, lines = pcall(C_QuestLog.GetQuestObjectives, id)
    for _, o in ipairs(okl and type(lines) == "table" and lines or {}) do log[#log + 1] = o end
    local function finished(text)
        for _, o in ipairs(log) do
            if text and o.text and string.find(o.text, text, 1, true) then return o.finished end
        end
        return false
    end
    local function query(f, key, objId)
        local okq, v = pcall(f, objId, key)
        return okq and v or nil
    end
    for _, o in ipairs(quest.ObjectiveData or {}) do
        if not finished(o.Text) then
            local best
            if o.Type == "monster" then
                best = NearestSpawn(zones, query(db.QueryNPCSingle, "spawns", o.Id))
            elseif o.Type == "object" then
                best = NearestSpawn(zones, query(db.QueryObjectSingle, "spawns", o.Id))
            elseif o.Type == "item" then
                for n, npc in ipairs(query(db.QueryItemSingle, "npcDrops", o.Id) or {}) do
                    if n > 6 then break end
                    best = NearestSpawn(zones, query(db.QueryNPCSingle, "spawns", npc), best)
                end
                for n, obj in ipairs(query(db.QueryItemSingle, "objectDrops", o.Id) or {}) do
                    if n > 6 then break end
                    best = NearestSpawn(zones, query(db.QueryObjectSingle, "spawns", obj), best)
                end
            end
            if best then return best.zone, best.x, best.y, (o.Text or L["its objective"]) .. " (Questie)" end
        end
    end
    return nil
end

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
            local entry = { id = q.questID, title = q.title or (L["Quest "] .. q.questID), progress = table.concat(progress, " "),
                map = spot and map, x = spot and spot.x and spot.x * 100, y = spot and spot.y and spot.y * 100, zone = info and info.name }
            if not entry.x then -- not on your map: Questie may know where it is
                local zone, x, y = UI.QuestieSpot(q.questID)
                local uiMap = zone and model.data.uiMaps[zone]
                if uiMap then entry.map, entry.x, entry.y, entry.zone = uiMap, x, y, zone end
            end
            out[#out + 1] = entry
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

-- How wide a text draws in this font string (its own width set aside for the measure).
function UI.MeasureText(fs, text)
    if not (fs and fs.GetStringWidth) then return 0 end
    local old = fs.GetText and fs:GetText()
    if fs.SetWidth then fs:SetWidth(0) end
    fs:SetText(text)
    local w = tonumber((fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or (fs:GetStringWidth())) or 0
    fs:SetText(old or "")
    return w
end

function UI.PaceText(long)
    local G = DufforthTweaksHelperGuide
    local s = G.TrackSummary(DB().tracker or {})
    if not long then
        return s.toLevel and (L["Level up in "] .. G.Duration(s.toLevel)) or ""
    end
    local lines = {}
    if s.perHour then lines[#lines + 1] = string.format(L["Experience: %d an hour."], s.perHour) end
    if s.toLevel then lines[#lines + 1] = L["Next level in about "] .. G.Duration(s.toLevel) .. L[" at this pace."] end
    if s.lastLevel then lines[#lines + 1] = string.format(L["Level %d took %s of play."], s.lastLevel.level, G.Duration(s.lastLevel.seconds)) end
    if #lines == 0 then return L["Your leveling pace shows after a few minutes of play."] end
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
            if kind == "CURRENT" or kind == "REACHABLE" then known.names[DufforthTweaksHelperLocale.EnglishNode(TaxiNodeName(i))] = true end
        end
    end
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
    local info = map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    local x, y
    if pos then if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end end
    if x and info and info.name then known.spots[#known.spots + 1] = { DufforthTweaksHelperLocale.MapZone(map) or DufforthTweaksHelperLocale.EnglishZone(info.name), x * 100, y * 100 } end
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
    local name = DufforthTweaksHelperGuide.ROUTE_FOR_RACE[race] or L["Durotar"]
    local data = DufforthTweaksHelperGuideData
    local routes = data and data.routes or {}
    -- One route per start, exactly RestedXP's, with or without its dungeon chain (user, 2026-11-26: the Safe and
    -- Explorer styles are gone).
    if DB().withDungeons and routes[name .. " (dungeons)"] then
        return name .. " (dungeons)" -- also takes dungeon quests, for players who group
    end
    return name
end

local pinned -- the step the map pin is on (declared before the menu functions that clear it)
UI.ROUTE_TIP = L["RestedXP's Forever guide, step by step."]

-- The guide's name as shown: "Speed", "Safe + dungeons", or a questline's name.
function UI.GuideLabel()
    local picked = DB().guideName
    local data = DufforthTweaksHelperGuideData
    if picked and data and data.routes and data.routes[picked] then return picked end
    return L["Leveling"] .. (DB().withDungeons and L[" + dungeons"] or "")
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
    local tip = UI.ROUTE_TIP
    local diff = level and string.format(L["Same steps as before until level %d (%s); from there it differs."], level, zone or "?")
        or L["Same route as before."]
    UI.switchNote = { text = "|cffffd100" .. UI.GuideLabel() .. L[" guide.|r "] .. tip .. " " .. diff, ["until"] = (GetTime and GetTime() or 0) + 12 }
    if C_Timer then C_Timer.After(12.1, function() pcall(UI.Refresh) end) end
end

-- A zone part from the Guides menu: back to the leveling guide, which now starts from that part
-- (the current step, the arrow and the list go there; user, 2026-11-13: only the list moved before).
function UI.SelectBracket(section)
    DB().guideName = nil
    local name = UI.RaceRoute()
    local saved = UI.Saved(name)
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
    return DufforthTweaksHelperGuide.NewModel(DufforthTweaksHelperGuideData, name, adapter, UI.Saved(name))
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
-- About RestedXP's box (230 wide): the card, the part line under it, Menu and _ as small icons (no top strip).
local WIDTH, HEIGHT, MIN_W, MIN_H, MAX_W, MAX_H = 230, 440, 190, 50, 800, 1000
local WAIT_ICON = "Interface\\GossipFrame\\IncompleteQuestIcon" -- the game's gray question mark
local DONE_MARK, WAIT_MARK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t ", "|TInterface\\RaidFrame\\ReadyCheck-Waiting:0|t "
local WHITE = "Interface\\Buttons\\WHITE8x8"
-- What you do, shown as a colored stripe and label beside the text (text stays on a neutral dark
-- background: user, 2026-11-13, colored bands made names hard to read). Colors pass 4.5:1 on the bands.
local KIND = {
    kill = { 1, 0.42, 0.42, "KILL" }, grind = { 1, 0.42, 0.42, "GRIND" }, loot = { 1, 0.66, 0.3, "LOOT" },
    use = { 0.35, 0.85, 0.9, "USE" }, explore = { 0.35, 0.85, 0.9, "EXPLORE" }, accept = { 1, 0.82, 0, L["PICK UP"] },
    turnin = { 0.4, 0.92, 0.45, L["TURN IN"] }, travel = { 0.5, 0.7, 1, "TRAVEL" }, flight = { 0.5, 0.7, 1, L["FLIGHT PATH"] },
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
    -- Light buttons, the text stands out (user, 2026-11-15: "buttons too thick... focus on text, not on the button").
    b.bg:SetAllPoints(); b.bg:SetColorTexture(1, 1, 1, 0.06)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.12)
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
    if on then b.bg:SetColorTexture(0.12, 0.45, 0.2, 0.7) else b.bg:SetColorTexture(1, 1, 1, 0.06) end
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
        GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText(L["Mark this step done (you did it already). Undo it with its check box in the list."], 1, 1, 1, 1, true); GameTooltip:Show()
    end)
    b.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b.items = {} -- RestedXP's route: one line per line of the step, each with its own check box
    -- Click: the pin and the arrow on this step; right-click: its options (user, 2026-11-15).
    if b.EnableMouse then b:EnableMouse(true) end
    b:SetScript("OnMouseUp", function(self, button)
        local i = self.group and self.group[1]
        if not i then return end
        if button == "RightButton" then UI.StepMenu(i, self) else UI.PinStep(i) end
    end)
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
    r.check:SetScript("OnClick", function()
        if r.rx then UI.ToggleWhole(r.rx) elseif r.step then UI.ToggleStep(r.step) end
    end)
    r.check:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText(L["Mark this step done (you did it already), or click again to undo."], 1, 1, 1, 1, true); GameTooltip:Show()
    end)
    r.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Click a step: the box shows it (back or ahead), with the arrow on it (user, 2026-11-14).
    r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, 0.07)
    if r.EnableMouse then r:EnableMouse(true) end
    r:SetScript("OnMouseUp", function(self) if self.step and not self.isHeader then UI.ViewStep(self.step) end end)
    r:SetScript("OnEnter", function(self)
        if not self.step or self.isHeader then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L["Step "] .. (self.rx or self.step), 1, 0.82, 0)
        GameTooltip:AddLine(L["Click: show this step in the guide, with the arrow on it. From there you can go back to your step or continue from this one."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.isHeader, r.rx = false, false
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
    f.menuButton = Flat(f, L["Menu"], 44, 18); f.menuButton:SetPoint("RIGHT", f.hide, "LEFT", -4, 0)
    -- Only Best stays on the strip; Steps and the map pin moved into the Menu (user, 2026-11-27: "why I need
    -- steps now ... why I need the map button beside the menu").
    f.best = Flat(f, L["Best"], 36, 18); f.best:SetPoint("RIGHT", f.menuButton, "LEFT", -4, 0)
    -- RestedXP's size (user, 2026-11-28): no top strip, step counter or Best button; back, skip and best are in the
    -- Menu; Menu ("=") and minimize ("_") are small icons in the top right corner, over the first card.
    for _, o in ipairs({ f.strip, f.back, f.stepNum, f.skip, f.best }) do o:Hide() end
    f.hide:SetSize(16, 14); f.hide:ClearAllPoints(); f.hide:SetPoint("TOPRIGHT", -3, -3)
    f.menuButton:SetText("=")
    f.menuButton:SetSize(16, 14); f.menuButton:ClearAllPoints(); f.menuButton:SetPoint("RIGHT", f.hide, "LEFT", -2, 0)
    f.hide:SetFrameLevel((f:GetFrameLevel() or 1) + 20); f.menuButton:SetFrameLevel((f:GetFrameLevel() or 1) + 20)
    -- Viewing a step other than yours: back to yours, or carry on from the one shown.
    f.viewBar = CreateFrame("Frame", nil, f)
    f.viewBar:SetHeight(22)
    f.viewBar.bg = f.viewBar:CreateTexture(nil, "BACKGROUND"); f.viewBar.bg:SetAllPoints(); f.viewBar.bg:SetColorTexture(0.12, 0.2, 0.32, 1)
    f.viewBar.label = Font(f.viewBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 11)
    f.viewBar.label:SetPoint("LEFT", 6, 0)
    f.viewBar.back = Flat(f.viewBar, L["Back to my step"], 96, 18); f.viewBar.back:SetPoint("RIGHT", -2, 0)
    f.viewBar.go = Flat(f.viewBar, L["Continue from here"], 116, 18); f.viewBar.go:SetPoint("RIGHT", f.viewBar.back, "LEFT", -4, 0)
    f.viewBar.back:SetScript("OnClick", function() UI.BackToStep() end)
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

    Section(L["Guide"])
    -- Guides: the leveling route or a questline guide (attunements, Cozy Sleeping Bag).
    f.guides = MenuRow("action", L["Guides and zones"])
    -- Every step of this part of the route: what you did, where you are, what's next (user, 2026-11-14).
    f.stepsButton = MenuRow("toggle", L["Show step list"])
    f.stepsButton:SetScript("OnClick", function()
        DB().listOpen = not DB().listOpen
        UI.follow, UI.scrolled = true, false
        UI.Refresh()
    end)
    Tip(f.stepsButton, L["Opens every step of this part of the route under the cards: done, yours and next."])
    -- The arrow and the map pin back on your step, after looking at another step or quest.
    f.pin = MenuRow("plain", L["Back to my step"])
    -- Were the strip's < > and Best buttons.
    f.backRow = MenuRow("plain", L["Previous step"])
    f.backRow:SetScript("OnClick", function() f.tools:Hide(); UI.model:Back(); UI.override = nil; pinned = nil; UI.Refresh() end)
    f.skipRow = MenuRow("plain", L["Skip this step"])
    f.skipRow:SetScript("OnClick", function() f.tools:Hide(); UI.model:Skip(); UI.override = nil; pinned = nil; UI.Refresh() end)
    f.bestRow = MenuRow("plain", L["Best step for my level"])
    f.bestRow:SetScript("OnClick", function() f.tools:Hide(); UI.GoRecommended() end)
    f.arrowToggle = MenuRow("toggle", L["Waypoint arrow"])
    f.linesToggle = MenuRow("toggle", L["Route lines on the map"])
    f.dungeonRoute = MenuRow("toggle", L["Include dungeons"])
    f.dungeonRoute:SetScript("OnClick", function()
        local before = UI.RouteName()
        DB().withDungeons = not DB().withDungeons
        UI.follow, UI.scrolled, UI.section, UI.lastCurrent = true, false, nil, nil
        UI.NoteSwitch(before, UI.RouteName())
        UI.Refresh()
    end)
    Tip(f.dungeonRoute, L["Follow RestedXP's dungeon guide instead: the same leveling with its dungeon runs and dungeon quests."])
    Section(L["Automation"])
    f.autoToggle = MenuRow("toggle", L["Auto accept and hand in"])
    f.vendorToggle = MenuRow("toggle", L["Sell junk and repair"])
    f.vendorToggle:SetScript("OnClick", function()
        local q = DufforthTweaksHelperQuestAuto
        if q then q.SetVendorEnabled(not q.VendorEnabled()) end
        SetOn(f.vendorToggle, q and q.VendorEnabled())
    end)
    f.scanToggle = MenuRow("toggle", L["Sound for rare monsters"])
    f.scanToggle:SetScript("OnClick", function() DB().scanSound = DB().scanSound == false; SetOn(f.scanToggle, DB().scanSound ~= false) end)
    Tip(f.scanToggle, L["Plays a sound and flashes the game's icon when a rare monster of your current steps shows on a nameplate (once a minute)."])
    -- Look of the box (user, 2026-11-14): size, opacity, text size, hidden in combat or dungeons.
    Section(L["Look"])
    f.scaleButton = MenuRow("value", L["Size"])
    f.alphaButton = MenuRow("value", L["Opacity"])
    f.fontButton = MenuRow("value", L["Text size"])
    f.combatToggle = MenuRow("toggle", L["Hide in combat"])
    f.dungeonToggle = MenuRow("toggle", L["Hide in dungeons"])
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
    Tip(f.scaleButton, L["The size of the guide box and its bar."])
    Tip(f.alphaButton, L["How see-through the guide box is."])
    Tip(f.fontButton, L["The size of the text in the guide box."])
    Tip(f.combatToggle, L["Fades the guide box out while you fight."])
    Tip(f.dungeonToggle, L["Fades the guide box out inside dungeons and raids."])
    Tip(f.linesToggle, L["Draws the next steps on the world map with numbered dots and lines."])
    Tip(f.vendorToggle, L["At a vendor: sells your gray items and repairs your gear by itself. Hold Shift while opening the vendor to skip it once."])
    f.menuButton:SetScript("OnClick", function()
        if f.tools:IsShown() then f.tools:Hide() else f.guideMenu:Hide(); f.tools:Show() end
    end)
    Tip(f.menuButton, L["Guides, best step, auto quests, arrow and map pin."])
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
            if self.route then UI.SelectPart(self.route, self.part, self.pruned)
            elseif self.bracket then UI.SelectBracket(self.bracket) else UI.SelectGuide(self.guide) end
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
    Tip(f.best, L["Go to the best step for you now: the first open step in the part of the route that still gives you experience at your level, going by the quests you have done."])
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
        Tip(r.skip, L["Done or not needed: hide this errand."])
        r:SetScript("OnClick", function() UI.ErrandClicked(r.errand) end)
        r:SetScript("OnEnter", function(self)
            if not self.errand then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.errand.action, 1, 1, 1, 1, true)
            if self.errand.tip then GameTooltip:AddLine(self.errand.tip, 0.7, 0.7, 0.7, true) end
            GameTooltip:AddLine(L["Click: point the arrow there."], 0.5, 0.8, 1, true)
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
    f.useItem:SetNormalFontObject("GameFontHighlightSmall"); f.useItem:SetText(L["Start quest"])
    f.useItem:Hide()
    Tip(f.useItem, L["Use the item: its quest window opens (and is accepted when Auto is on)."])
    f.blocks[1].band:SetColorTexture(BAND_CURRENT[1], BAND_CURRENT[2], BAND_CURRENT[3], 1)
    f.along = Font(f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 12) -- along the way
    f.along:SetJustifyH("LEFT")
    f.progress = CreateFrame("StatusBar", nil, f)
    f.progress:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    f.progress:SetStatusBarColor(0.11, 0.5, 0.2); f.progress:SetMinMaxValues(0, 1) -- dark enough for white text
    f.progress.bg = f.progress:CreateTexture(nil, "BACKGROUND")
    f.progress.bg:SetAllPoints(); f.progress.bg:SetColorTexture(0, 0, 0, 0.6)
    f.progress.label = Font(f.progress:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 11)
    f.progress.label:SetPoint("LEFT", 4, 0); f.progress.label:SetJustifyH("LEFT")
    if f.progress.label.SetWordWrap then f.progress.label:SetWordWrap(false) end
    if f.progress.EnableMouse then f.progress:EnableMouse(true) end
    -- The whole-route percent only in the hover: always on screen it was noise (user, 2026-11-13).
    f.progress.pace = Font(f.progress:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 10)
    f.progress.pace:SetPoint("RIGHT", -4, 0); f.progress.pace:SetJustifyH("RIGHT")
    Tip(f.progress, function()
        return L["Zone: how much of this part of the route (levels and zone) is done.\n"] .. (f.progress.routeText or "")
            .. (UI.PaceText and ("\n" .. UI.PaceText(true)) or "")
            .. UI.RestedText("\n\n", "HoverText")
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
    f.nextToggle = Flat(f.bar, L["Next"], 34, 18); f.nextToggle:SetPoint("RIGHT", f.prevSection, "LEFT", -5, 0)
    f.doneToggle = Flat(f.bar, L["Done"], 34, 18); f.doneToggle:SetPoint("RIGHT", f.nextToggle, "LEFT", -2, 0)
    f.bar.label:SetPoint("RIGHT", f.doneToggle, "LEFT", -4, 0)

    -- The section's steps.
    f.list = CreateFrame("Frame", nil, f)
    f.list:EnableMouseWheel(true)
    f.rows = {}
    for k = 1, ROWS do f.rows[k] = Row(f.list) end
    f.empty = f.list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.empty:SetPoint("TOPLEFT", 4, -4); f.empty:SetJustifyH("LEFT")

    local function Follow() UI.follow, UI.scrolled = true, false; UI.Refresh() end
    -- Every click about your step leaves a quest you clicked (user, 2026-11-14: the map pin button moved the game's
    -- pin, but the arrow stayed on the class quest).
    f.skip:SetScript("OnClick", function() UI.model:Skip(); UI.override = nil; pinned = nil; UI.Refresh() end)
    f.back:SetScript("OnClick", function() UI.model:Back(); UI.override = nil; pinned = nil; UI.Refresh() end)
    f.pin:SetScript("OnClick", function() f.tools:Hide(); UI.BackToStep() end)
    f.hide:SetScript("OnClick", function() UI.SetCollapsed(true) end)
    f.arrowToggle:SetScript("OnClick", function() UI.SetArrowShown(not DB().arrow) end)
    f.autoToggle:SetScript("OnClick", function()
        local auto = DufforthTweaksHelperQuestAuto
        if auto then auto.SetEnabled(not auto.Enabled()) end
        UI.Refresh()
    end)
    f.doneToggle:SetScript("OnClick", function() DB().showDone = not DB().showDone; Follow() end)
    f.nextToggle:SetScript("OnClick", function() DB().showNext = not DB().showNext; Follow() end)
    f.prevSection:SetScript("OnClick", function() UI.override = nil; UI.Browse(-1) end)
    f.nextSection:SetScript("OnClick", function() UI.override = nil; UI.Browse(1) end)
    f.list:SetScript("OnMouseWheel", function(_, delta) UI.Scroll(-delta) end)

    Tip(f.back, L["Back: bring back the step you skipped last."])
    Tip(f.skip, L["Skip this step (and, for a pick-up, that quest's steps)."])
    Tip(f.pin, L["Put the arrow and the map pin back on your current step."])
    Tip(f.arrowToggle, function() return DB().arrow and L["Hide the waypoint arrow."] or L["Show the waypoint arrow."] end)
    Tip(f.hide, L["Minimize: the guide shrinks to its round icon. Click the icon to open it again."])
    Tip(f.autoToggle, function()
        local on = DufforthTweaksHelperQuestAuto and DufforthTweaksHelperQuestAuto.Enabled()
        return (on and L["Auto quests on: "] or L["Auto quests off: "]) .. L["accepts quests that fit and hands in finished ones; a choice of rewards waits for you. Hold Shift to do one yourself."]
    end)
    Tip(f.doneToggle, function() return DB().showDone and L["Hide the steps behind you."] or L["Show the steps behind you (checked)."] end)
    -- Rows: a check box marks a step done by hand.
    Tip(f.nextToggle, function() return DB().showNext and L["Hide the steps ahead (keep only the current one)."] or L["Show the steps ahead."] end)
    Tip(f.prevSection, L["Previous part of the route. A new step brings you back to yours."])
    Tip(f.nextSection, L["Next part of the route. A new step brings you back to yours."])
    Tip(f.grip, L["Drag to resize."])

    box = f
    if DufforthTweaksHelper and DufforthTweaksHelper.RegisterMovable then
        DufforthTweaksHelper.RegisterMovable({ label = L["Leveling guide"], get = function() return box end,
            enter = function(b) b:Show() end, leave = function() UI.Refresh() end })
    end
    return f
end

-- Extra lines: class quests, dungeon quests, gray quests to abandon.
local function Extras(model)
    local parts = {}
    local class = model:ClassQuests()[1]
    if class then parts[#parts + 1] = string.format(L["|cffc080ffClass quest:|r %s (%s)"], class.title, class.giver) end
    local dungeons = model:DungeonQuests()
    if #dungeons > 0 then parts[#parts + 1] = string.format(L["|cff73bfff%d dungeon quest%s to pick up|r"], #dungeons, #dungeons == 1 and "" or "s") end
    local gray = model:GrayInLog()
    if #gray > 0 then parts[#parts + 1] = string.format(L["|cff9d9d9dAbandon %d gray quest%s|r"], #gray, #gray == 1 and "" or "s") end
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

-- The list's check box on a RestedXP step: every line of it at once.
function UI.ToggleWhole(n)
    if not (UI.model and UI.model.RxToggleWhole) then return end
    UI.model:RxToggleWhole(n)
    pinned = nil
    UI.Refresh()
end

-- RestedXP's step list: one row per step (its lines together), a header where each part starts; steps that aren't
-- for your class or race are left out, like RestedXP does.
local function RxListItems(model)
    local items, db = {}, DB()
    local secOfPart = {}
    for k, sec in ipairs(model:Sections()) do
        local rec = model.route.rx[model:RxStepOf(sec.first) or 0]
        if rec and secOfPart[rec.p] == nil then secOfPart[rec.p] = k end
    end
    local last
    for n, rec in ipairs(model.route.rx) do
        local k = secOfPart[rec.p]
        local state = k and model:RxStepState(n)
        if state and (state == "current" or state == "along" or (state == "open" and db.showNext) or (state == "done" and db.showDone)) then
            if last ~= k then items[#items + 1] = { header = k }; last = k end
            items[#items + 1] = { step = model:RxRows(n)[1], rx = n, state = state }
        end
    end
    return items
end

-- The whole route as the list shows it: a header where each part starts, then its steps, by state and the
-- Done / Next toggles (user, 2026-11-13: see the steps behind you and the ones ahead, like RestedXP).
local function ListItems(model, states)
    if model.rxp and model.RxStepState then return RxListItems(model) end
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
    if model.RxStepOf then
        -- RestedXP's card: "Step N" (its number in the part) on the pointer's step only; side steps have no tag.
        local n = model:RxStepOf(i)
        if not first then return "" end
        return string.format(L["|cffffd100Step %s|r"], tostring(model.RxNumber and model:RxNumber(n) or n))
    end
    local d = DufforthTweaksHelperGuide.Describe(model, i)
    local quest = d and d.quest and ("  |cffd0d0d0" .. d.quest .. "|r") or ""
    local _, x, y = model:Place(i)
    local at = x and string.format(L["  |cff888888%d, %d|r"], math.floor(x + 0.5), math.floor(y + 0.5)) or ""
    return string.format(first and L["|cffffd100Step %s|r%s%s"] or L["|cffaaaaaaStep %s|r%s%s"], number, quest, at)
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
    bar.target = BarButton(bar, L["DufforthTweaksHelperGuideTarget"])
    bar.target:SetPoint("TOPLEFT")
    bar.target.icon:SetTexture("Interface\\Icons\\Ability_Hunter_SniperShot")
    bar.target:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L["Target "] .. (self.who or "?"), 1, 1, 1)
        GameTooltip:AddLine(L["Works when it's close enough to see."], 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    bar.target:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar.items = {}
    for k = 1, BAR_ITEMS do
        local b = BarButton(bar, L["DufforthTweaksHelperGuideItem"] .. k)
        b:SetPoint("TOPLEFT", bar.target, "TOPRIGHT", 4 + (k - 1) * (BAR_SIZE + 4), 0) -- a row under the box
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            if self.itemID and GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.itemID) else GameTooltip:SetText(L["Quest item"]) end
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
-- A quest's own item to use on its objective (the game's quest log knows it): itemID, icon, name; nil when none.
function UI.QuestItemFor(questID)
    if not (questID and C_QuestLog and C_QuestLog.GetLogIndexForQuestID and GetQuestLogSpecialItemInfo) then return nil end
    local okI, index = pcall(C_QuestLog.GetLogIndexForQuestID, questID)
    if not (okI and index) then return nil end
    local ok, link, icon = pcall(GetQuestLogSpecialItemInfo, index)
    if not (ok and link) then return nil end
    local id = tonumber(string.match(link, "item:(%d+)"))
    local name = string.match(link, "%[(.-)%]") or "?"
    return id, icon, name
end

-- The hint on a step card (user, 2026-11-15: "an icon that suggests use the item on the quest objective").
function UI.UseItemHint(questID)
    local id, icon, name = UI.QuestItemFor(questID)
    if not id then return nil end
    return string.format(L["|T%s:16|t |cffffd100Use %s|r on the objective (its button is next to the guide)"], tostring(icon or "Interface\\Icons\\INV_Misc_QuestionMark"), name)
end

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
-- Where the quest bar's top-left goes, in the bar's own units: the box's bottom-left, 4 px lower.
function UI.BarSpot(left, bottom, boxScale, barScale)
    local r = boxScale / ((barScale and barScale > 0) and barScale or 1)
    return left * r, bottom * r - 4
end

function UI.PlaceSecure(f)
    if InCombatLockdown and InCombatLockdown() then return end
    local s = (tonumber((f:GetEffectiveScale())) or 1) / (tonumber((UIParent:GetEffectiveScale())) or 1)
    local left, bottom = tonumber((f:GetLeft())), tonumber((f:GetBottom()))
    if f.questBar and left and bottom then
        -- A row under the box (user, 2026-11-27: the box sits at the screen's left edge, a column on its left was
        -- off screen). The bar has its own scale, so convert screen pixels into its units.
        local x, y = UI.BarSpot(left, bottom, tonumber((f:GetEffectiveScale())) or 1, tonumber((f.questBar:GetEffectiveScale())) or 1)
        f.questBar:ClearAllPoints(); f.questBar:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
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
    -- RestedXP's route: every NPC and monster of the active steps (its targeting frame), like the "DTH Target" macro.
    local rxui = DufforthTweaksHelperGuideRxUI
    local names = DB().shown and model.RxTargets and model:RxTargets() or nil
    if names and rxui and rxui.Order then names = rxui.Order(names, model) end -- seen on a nameplate first
    if names and names[1] and rxui then who = names[1] end
    bar.target.who = who
    if who then
        bar.target:SetAttribute("type", "macro")
        bar.target:SetAttribute("macrotext", (names and names[1] and rxui) and ("/cleartarget\n" .. rxui.MacroText(names))
            or ("/cleartarget\n/targetexact " .. who))
        bar.target:Show()
    else
        bar.target:Hide()
    end
    local items = DB().shown and UI.QuestItems() or {}
    local step = current and model.steps[current]
    local wanted = step and UI.QuestItemFor(step[2])
    if model.RxItems then -- RestedXP's route: the active steps' .use items, ahead of the other quest items
        local have = {}
        for _, it in ipairs(items) do have[it.id] = true end
        local getIcon = C_Item and C_Item.GetItemIconByID or GetItemIcon
        for k, id in ipairs(model:RxItems()) do
            if not have[id] and (UI.adapter and UI.adapter.itemCount and UI.adapter.itemCount(id) or 0) > 0 then
                table.insert(items, k, { id = id, icon = getIcon and getIcon(id) })
            end
        end
        wanted = wanted or model:RxItems()[1]
    end
    if wanted then -- the item for the step you're on comes first
        for k, it in ipairs(items) do if it.id == wanted then table.remove(items, k); table.insert(items, 1, it); break end end
    end
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

-- One line of a RestedXP step in its card: a check box and the line's text.
local function LineItem(b, k)
    local it = b.items[k]
    if it then return it end
    it = CreateFrame("Frame", nil, b)
    it.check = CreateFrame("Button", nil, it)
    it.check:SetSize(14, 14); it.check:SetPoint("TOPLEFT", 0, 0)
    it.check.box = it.check:CreateTexture(nil, "ARTWORK"); it.check.box:SetAllPoints(); it.check.box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
    it.check.mark = it.check:CreateTexture(nil, "OVERLAY"); it.check.mark:SetAllPoints(); it.check.mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    it.check:SetScript("OnClick", function(self) if self.row and not self.locked then UI.ToggleStep(self.row) end end)
    it.check:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(self.locked and L["Done: the game says so."] or L["Tick this line when you've done it; click again to undo."], 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    it.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    it.text = Font(it:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), 13)
    it.text:SetPoint("TOPLEFT", 18, 0); it.text:SetJustifyH("LEFT")
    if it.text.SetSpacing then it.text:SetSpacing(2) end
    b.items[k] = it
    return it
end

-- One line of a RestedXP step as RestedXP writes it: its own text (colours and icons kept) or RestedXP's default for
-- that kind ("Accept <quest>", "<item>: 1/3", the objective's progress); names, never ids.
function UI.RxLineText(model, r, adapter, said)
    local row = model.steps[r]
    if not row then return "" end
    local kind, id, a = row[1], row[2], row[12] or {}
    local d = DufforthTweaksHelperGuide.Describe(model, r)
    local icon = DufforthTweaksHelperGuide.Inline(d and d.icon) .. " "
    local title = (id and id > 0 and model.Title and model:Title(id)) or (d and d.quest) or ""
    if kind == "collect" then
        local name = a.nm
        if not name and a.i then
            if C_Item and C_Item.GetItemNameByID then name = C_Item.GetItemNameByID(a.i) end
            if not name and GetItemInfo then name = GetItemInfo(a.i) end
        end
        local have = adapter and adapter.itemCount and adapter.itemCount(a.i) or 0
        local count = string.format("%d/%d", math.min(have, a.n or 1), a.n or 1)
        if said then return icon .. said .. "\n" .. count end
        return icon .. (name or L["Item"]) .. ": " .. count
    end
    if said then return icon .. said end
    if kind == "accept" and title ~= "" then return icon .. L["Accept "] .. title end
    if kind == "turnin" and title ~= "" then return icon .. L["Turn in "] .. title end
    if kind == "abandon" and title ~= "" then return icon .. L["Abandon "] .. title end
    local action, lines = StepText(model, r, adapter)
    if kind == "do" and lines ~= "" then return lines end
    if row[7] and row[7] ~= "" then return icon .. row[7] end
    return action .. (lines ~= "" and ("\n" .. lines) or "")
end

-- RestedXP's step frame: every line of step n with its own check box (ticked and locked when the game says it's
-- done, ticked by you otherwise; RestedXP's SetElementComplete), then the advice. Returns the card's height.
local function RxLines(b, model, adapter, n, inner, advice)
    b.check:Hide(); b.action:SetText(""); b.lines:SetText("")
    b.header:SetWidth(inner)
    local y = -(4 + Height(b.header, "x") + 3)
    -- RestedXP's order: its text lines (no check box) and the lines you act on (a check box each).
    local shown = model.RxDisplay and model:RxDisplay(n) or {}
    for k, line in ipairs(shown) do
        local it = LineItem(b, k)
        local text, r = line.text, line.row
        if r then
            local state = model:RxLineState(r)
            text = UI.RxLineText(model, r, adapter, line.said)
            if state ~= "open" then text = "|cff9d9d9d" .. Plain(text) .. "|r" end
            it.check.row, it.check.locked = r, state == "game"
            it.check.mark:SetShown(state ~= "open")
            it.check:SetAlpha(state == "game" and 0.5 or 1)
            it.check:Show()
        else
            it.check.row = false
            it.check:Hide()
        end
        it.text:SetWidth(inner - 18); it.text:SetText(text)
        local h = math.max(16, Height(it.text, text))
        it:ClearAllPoints(); it:SetPoint("TOPLEFT", b, "TOPLEFT", 8, y); it:SetSize(inner, h); it:Show()
        y = y - h - 3
    end
    for k = #shown + 1, #b.items do b.items[k]:Hide() end
    b.advice:SetWidth(inner); b.advice:SetText(advice)
    b.advice:ClearAllPoints(); b.advice:SetPoint("TOPLEFT", b, "TOPLEFT", 8, y)
    return -y + (advice ~= "" and Height(b.advice, advice) + 3 or 0) + 2
end

local function DrawBlocks(f, model, adapter, blocks, w, top, bottom)
    local inner, fits = w - 2 * PAD - 12, true
    -- One card per step (user, 2026-11-15); the trip's cards are always drawn, the next ones while they fit.
    local trip = math.max(1, blocks.trip or 1)
    for k = 1, math.max(ACTIVE, #blocks, #f.blocks) do
        f.blocks[k] = f.blocks[k] or Block(f)
        local b, group = f.blocks[k], blocks[k]
        if group then
            local action, lines, note, kind = GroupText(model, group, adapter)
            local c = KIND[kind] or KIND.travel
            b.group = group
            local isCurrent = group[1] == model:Current() or (k == 1 and not blocks.trip)
            if model.rxp and model.RxAt then isCurrent = model:RxStepOf(group[1]) == model:RxAt() end
            b.header:SetText(Header(model, group, isCurrent))
            local band = isCurrent and BAND_CURRENT or BAND_NEXT
            b.band:SetColorTexture(band[1], band[2], band[3], 1)
            -- Waits on an earlier step (user, 2026-11-14: a hand-in looked doable before its objectives): gray, with a
            -- gray question mark and which step comes first.
            local waits = k > 1 and model:WaitsFor(group[1])
            -- Not for a pick-up right after handing in to the same NPC (one talk, two rows).
            local prev = blocks[k - 1] and blocks[k - 1][#blocks[k - 1]]
            if waits and prev and waits == prev and model:TalkTo(prev) and model:TalkTo(prev) == model:TalkTo(group[1]) then waits = nil end
            if waits then
                c = { 0.45, 0.45, 0.45 }
                b.header:SetText(b.header:GetText() .. (type(waits) == "number" and string.format(L["  |cff888888after step %d|r"], waits)
                    or L["  |cff888888after its objectives|r"]))
                action = "|T" .. WAIT_ICON .. L[":0|t |cff888888"] .. (Plain(action):gsub("^%s+", ""):gsub("\n%s+", "\n")) .. "|r"
                lines = lines ~= "" and ("|cff888888" .. Plain(lines) .. "|r") or lines
            end
            b.accent:SetColorTexture(c[1], c[2], c[3], 1)
            local advice = note and ("|cffffd100" .. note .. "|r") or ""
            local st = model.steps[group[1]]
            local useHint = st and st[1] == "do" and UI.UseItemHint(st[2])
            if useHint then advice = useHint .. (advice ~= "" and ("\n" .. advice) or "") end
            local legs = isCurrent and not model.rxp and model:Directions(group[1])
            if legs then
                -- One line (user, 2026-11-15: less text): "Route: Go to Orgrimmar: Undercity zeppelin › Zeppelin to Undercity › Fly to ..."
                local parts = {}
                for _, leg in ipairs(legs) do parts[#parts + 1] = leg.text end
                advice = advice .. (advice ~= "" and "\n" or "") .. L["|cff80b3ffRoute:|r "] .. "|cffd0d0d0" .. table.concat(parts, " > ") .. "|r"
            end
            local rxn = model.rxp and model.RxLineState and model:RxStepOf(group[1]) or nil
            b.rxStep = rxn or false
            local h
            if rxn then
                h = RxLines(b, model, adapter, rxn, inner, advice)
            else
                for _, it in ipairs(b.items) do it:Hide() end
                b.check:Show()
                b.advice:ClearAllPoints(); b.advice:SetPoint("TOPLEFT", b.lines, "BOTTOMLEFT", -20, -3)
                for _, fs in ipairs({ b.header, b.action, b.advice }) do fs:SetWidth(inner) end
                b.lines:SetWidth(inner - 20)
                b.action:SetText(action); b.lines:SetText(lines); b.advice:SetText(advice)
                h = 4 + Height(b.header, "x") + 3 + Height(b.action, action) + (lines ~= "" and 3 + Height(b.lines, lines) or 0)
                    + (advice ~= "" and 3 + Height(b.advice, advice) or 0) + 5
            end
            if k > trip and (not fits or top - h < bottom) then fits = false end
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
        b.header:SetText(L["Leveling guide"]); b.action:SetText(L["Route finished. Well done!"]); b.lines:SetText(""); b.advice:SetText("")
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
    local more = #group > 1 and string.format(L[" |cffaaaaaa+%d more|r"], #group - 1) or ""
    return DufforthTweaksHelperGuide.Inline(d and d.icon) .. " " .. action .. more
end

-- Class, dungeon and gray quests: what each is, where its giver is, and what a click does.
local function Where2(e) return e.zone and string.format("%s %d, %d", e.zone, math.floor((e.x or 0) + 0.5), math.floor((e.y or 0) + 0.5)) or "?" end

local function QuestItem(e, kind, indent)
    local dungeon = e.dungeon and ("|cff73bfff" .. e.dungeon .. ":|r ") or ""
    return {
        text = string.format(L["%s%s%s%s |cffaaaaaa(level %d)|r"], indent, kind ~= "" and ("|cffc080ff" .. kind .. ":|r ") or "", dungeon, e.title, e.level),
        entry = e, kind = kind ~= "" and kind or L["Dungeon quest"], tipTitle = e.title,
        tip = { (e.dungeon and (L["For the dungeon "] .. e.dungeon .. ". ") or "") .. L["Level "] .. e.level .. ".",
                L["From "] .. (e.giver or "?") .. ", " .. Where2(e) .. ".",
                L["Click: a map pin and the arrow to "] .. (e.giver or L["the giver"]) .. L[" (click again to go back to your step)."] },
    }
end

local function ExtraItems(model)
    -- RestedXP's steps only (user, 2026-11-26): no class, dungeon, off-route, Forever or gray-quest rows of ours.
    if model.rxp then return {} end
    local items, db = {}, DB()
    for _, e in ipairs(model:ClassQuests()) do items[#items + 1] = QuestItem(e, L["Class quest"], "") end
    local dungeons = model:DungeonQuests()
    if #dungeons > 0 then
        items[#items + 1] = { toggle = "showDungeons", tipTitle = L["Dungeon quests"],
            text = string.format(L["|cff73bfff%s %d dungeon quest%s to pick up|r"], db.showDungeons and "[-]" or "[+]", #dungeons, #dungeons == 1 and "" or "s"),
            tip = { L["Quests for dungeons near your level, worth taking before you run the dungeon."], L["Click to list them; click one for a map pin and the arrow to its giver."] } }
        if db.showDungeons then for _, e in ipairs(dungeons) do items[#items + 1] = QuestItem(e, "", "    ") end end
    end
    -- Quests in your log the route doesn't plan (a random drop started it, you took it on your own): a row each; a
    -- click points the arrow at its next objective, or at the NPC once it's complete (user, 2026-11-14).
    -- Folded into one row (user, 2026-11-15 screenshot: ten "Your quest" rows crowded the box); open on demand.
    local off = model:OffRoute()
    if #off > 0 then
        items[#items + 1] = { toggle = "showOff", tipTitle = L["Other quests in your log"],
            text = string.format(L["|cffffd100%s %d other quests in your log|r"], db.showOff and "[-]" or "[+]", #off),
            tip = { L["Quests in your log this route doesn't plan. Click to list them; click one for the arrow."] } }
    end
    for _, e in ipairs(db.showOff and off or {}) do
        items[#items + 1] = { text = string.format(L["    |cffffd100Your quest:|r %s |cffaaaaaa(%s)|r"], e.title, e.giver or "?"),
            entry = e, kind = "Your quest", tipTitle = e.title,
            tip = { L["In your log, but not in this route (it starts from a random drop, or you took it yourself)."],
                    e.zone and (L["Next: "] .. (e.giver or "?") .. ", " .. Where2(e) .. ".") or L["Its place isn't in the data: read the quest text."],
                    L["Click: the arrow and a map pin there (click again to go back to your step)."] } }
    end
    -- Forever's own quests (not in the Classic data the route comes from): from your quest log (user, 2026-11-14).
    for _, q in ipairs(UI.ForeverQuests(model)) do
        items[#items + 1] = { text = L["|cffff9933Forever quest:|r "] .. q.title .. (q.progress ~= "" and (" |cffaaaaaa" .. q.progress .. "|r") or ""),
            tipTitle = q.title, forever = q,
            tip = { L["A quest Forever added: the guide has no route for it, so it follows your quest log."],
                    q.x and L["Click: the arrow points at it on your map."] or L["Its place isn't on this map."] } }
    end
    local gray = model:GrayInLog()
    if #gray > 0 then
        items[#items + 1] = { toggle = "showGray", tipTitle = L["Gray quests"],
            text = string.format(L["|cff9d9d9d%s Abandon %d gray quest%s|r"], db.showGray and "[-]" or "[+]", #gray, #gray == 1 and "" or "s"),
            tip = { L["Quests in your log far below your level give little experience."], L["Open your quest log (L) and abandon them to make room. Click to list them."] } }
        if db.showGray then
            for _, e in ipairs(gray) do
                items[#items + 1] = { text = "    |cff9d9d9d" .. e.title .. L[" (level "] .. e.level .. ")|r", tipTitle = e.title,
                    tip = { L["Gray: little experience left. Abandon it in your quest log (L)."] } }
            end
        end
    end
    return items
end

-- How tall the extras (class, dungeon, your own quests) would be at this width.
local function ExtrasHeight(f, model, w)
    local total, items = 0, ExtraItems(model)
    for k, r in ipairs(f.extraRows) do
        local item = items[k]
        if not item then break end
        r.label:SetWidth(w - 2 * PAD - 4)
        total = total + Height(r.label, item.text) + 3
    end
    return total + (#items > 0 and 3 or 0)
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
    local entries = { { nil, L["Leveling 1-60: "] .. L["RestedXP"] .. (DB().withDungeons and L[" + dungeons"] or ""),
        UI.ROUTE_TIP .. L[" Include dungeons in the Menu switches to RestedXP's dungeon guide."] } }
    for _, g in ipairs(data.guides or {}) do entries[#entries + 1] = { g.name or g[1], g.name or g[1], g.note or g[2] } end
    local race = data.routes[UI.RaceRoute()]
    if race and race.rxp then
        -- RestedXP's guide menu: every route (start, with or without dungeons) and its parts, guide by guide.
        for _, e in ipairs(UI.RouteMenuEntries()) do entries[#entries + 1] = e end
    else
        entries[#entries + 1] = { nil, L["|cffffd100Leveling by zone|r"], "", nil, true }
        local leveling = DufforthTweaksHelperGuide.NewModel(data, UI.RaceRoute(), UI.adapter or UI.GameAdapter(), { skipped = {} })
        for _, p in ipairs(leveling:ZoneParts()) do
            entries[#entries + 1] = { nil, "    |cffcccccc" .. p.title .. "|r", L["Show this part of the leveling route in the list. Your current step still follows what you have done."], p.first }
        end
    end
    f.guideMenu.entries, f.guideMenu.offset = entries, 0
    UI.DrawGuideMenu()
    f.guideMenu:Show()
end

-- Menu rows for RestedXP's routes: a header per route, then its parts; your route first, then the loaded ones, then
-- the other starts (dropped from memory at login: picking one needs a /reload).
-- Row: { guide, title, tip, bracket, header, route, part (0-based, as the steps' p), pruned }.
function UI.RouteMenuEntries()
    local data = DufforthTweaksHelperGuideData
    local list = {}
    for name, r in pairs(data.routes or {}) do if r.rxp then list[#list + 1] = { name, r.parts or {}, false } end end
    for name, r in pairs(data.pruned or {}) do list[#list + 1] = { name, r.parts or {}, true } end
    local current = UI.RouteName()
    table.sort(list, function(a, b)
        if (a[1] == current) ~= (b[1] == current) then return a[1] == current end
        if a[3] ~= b[3] then return not a[3] end
        return a[1] < b[1]
    end)
    local out = {}
    for _, e in ipairs(list) do
        local name, parts, pruned = e[1], e[2], e[3]
        out[#out + 1] = { nil, "|cffffd100" .. name .. "|r" .. (pruned and L[" |cff888888(needs /reload)|r"] or ""), "", nil, true }
        for p, part in ipairs(parts) do
            out[#out + 1] = { nil, "    |cffcccccc" .. part .. "|r" .. (pruned and L[" |cff888888(/reload)|r"] or ""),
                pruned and L["Another start: picked now, loaded after you type /reload (only your start's routes stay in memory)."]
                    or L["Go to this part: the guide continues from its first step."], nil, false, name, p - 1, pruned }
        end
    end
    return out
end

-- A part picked in the Guides menu: that route, from the part's first step. Another start waits for a /reload.
function UI.SelectPart(name, p, pruned)
    local data, db = DufforthTweaksHelperGuideData, DB()
    local base = string.gsub(name, " %(dungeons%)$", "")
    local raceBase = string.gsub(UI.RaceRoute(), " %(dungeons%)$", "")
    if base == raceBase then db.guideName = nil; db.withDungeons = name ~= base else db.guideName = name end
    if box and box.guideMenu then box.guideMenu:Hide() end
    UI.follow, UI.scrolled, UI.section, UI.override, UI.lastCurrent = true, false, nil, nil, nil
    pinned = nil
    if pruned or not data.routes[name] then
        db.pendingPart = { route = name, part = p }
        UI.switchNote = { text = string.format(L["|cffffd100%s|r is picked. Type /reload to load it: only your start's routes stay in memory."], name),
            ["until"] = (GetTime and GetTime() or 0) + 30 }
        UI.Refresh()
        return
    end
    local saved = UI.Saved(name)
    local model = DufforthTweaksHelperGuide.NewModel(data, name, UI.adapter or UI.GameAdapter(), saved)
    local n = model.RxPartStart and model:RxPartStart(p)
    if n then model:RxGoTo(n) end
    UI.Refresh()
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
            r.route, r.part, r.pruned = e[6] or false, e[7] or false, e[8] or false
            local on = not e[4] and not e[5] and not e[6] and ((e[1] == picked) or (e[1] == nil and not (picked and data.routes[picked])))
            r.label:SetText((on and L["|cff40ff40> |r"] or "   ") .. e[2]); r:Show()
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
        m.more:SetText(string.format(L["Scroll for more: %d above, %d below"], offset, below)); m.more:Show()
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
        if q.x and q.map then UI.override = { id = q.id, map = q.map, x = q.x, y = q.y, zone = q.zone, text = L["Forever quest: "] .. q.title } end
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
        end
        pinned = nil
    end
    UI.Refresh()
end

-- Along the way: map-wide objectives in your log, with the game's progress.
local function AlongText(model, adapter)
    local parts = {}
    for _, i in ipairs(model:Along()) do
        local here = adapter and adapter.zone and adapter.zone()
        if (UI.inTopBlock and UI.inTopBlock[i]) or (here and here ~= "" and model.steps[i][3] ~= here) then -- shown, or another zone
            -- already in the top block (the whole trip)
        else
            local action, lines = StepText(model, i, adapter)
            parts[#parts + 1] = action .. (lines ~= "" and ("\n      " .. string.gsub(lines, "\n", "\n      ")) or "")
        end
    end
    local text = #parts > 0 and (L["|cff80b3ffAlong the way|r |cff888888(kill them as you go)|r\n"] .. table.concat(parts, "\n")) or ""
    -- Other quests in your log you can do right here (user, 2026-11-14), with the game's progress.
    local current = model:Current()
    local also = (current and not model.rxp) and model:AlsoHere(current) or {} -- not on RestedXP's route (user, 2026-11-26)
    if #also > 0 then
        local lines = {}
        for _, a in ipairs(also) do
            local progress, name = "", a.name
            local list = adapter and adapter.objectives and adapter.objectives(a.quest) or {}
            local k = DufforthTweaksHelperGuide.MatchObjective(list, a.goal or { [2] = a.name }, a.goals)
            if k and list[k].text then
                progress = " |cffaaaaaa" .. list[k].text .. "|r"
                if not string.find(list[k].text, a.name, 1, true) then name = DufforthTweaksHelperGuide.ObjectiveName(list[k].text) or a.name end
            end
            lines[#lines + 1] = string.format(L["  |cffd0d0d0%s|r%s |cff888888for %s|r"], name, progress, a.title)
        end
        text = text .. (text ~= "" and "\n" or "") .. L["|cff80b3ffAlso here|r |cff888888(other quests in your log)|r\n"] .. table.concat(lines, "\n")
    end
    return text
end

local function DrawProgress(f, model, current, w, top)
    local k = current and model:SectionOf(current)
    local done, total = 0, 0
    if k then done, total = model:SectionProgress(k) else done, total = 1, 1 end
    local pct = total > 0 and done / total or 1
    f.progress:ClearAllPoints(); f.progress:SetPoint("TOPLEFT", f, "TOPLEFT", PAD - 4, top); f.progress:SetSize(w - 2 * PAD + 8, PROGRESS)
    f.progress:SetValue(pct)
    local title = k and DufforthTweaksHelperGuide.SectionTitle(model:Sections()[k]) or L["Route finished"]
    local route = current and math.floor((current - 1) / math.max(1, #model.steps) * 100) or 100
    f.progress.routeText = string.format(L["Whole route: %d%% done (step %d of %d)."], route, current or #model.steps, #model.steps)
    -- Side by side, never on top of each other (user, 2026-11-14): with little room the zone %, then the guide name,
    -- then "Level up in" go first; whatever is left is cut with "...".
    f.progress.title, f.progress.pct, f.progress.barW = title, pct, w - 2 * PAD + 8
    UI.FitProgress(f)
    return top - PROGRESS - 4
end

-- The bar's two texts side by side, never on top of each other (user, 2026-11-14 and 2026-11-21):
-- with little room the zone %, then the guide name, then the long pace or flight text go first;
-- whatever is left is cut with "...". Runs on each redraw and each second of a flight.
-- Rested.lua's text (prefix + text), "" when that file isn't loaded or has nothing to say.
function UI.RestedText(prefix, which)
    local R = DufforthTweaksHelperRested
    if not R or not R[which] then return "" end
    local ok, text = pcall(R[which])
    if not ok or not text or text == "" then return "" end
    return prefix .. text
end

function UI.FitProgress(f)
    local bar = f.progress
    if not bar.title or not bar.barW then return end
    local title, barW = bar.title, bar.barW
    local guide, zonePct = "|cffffd100" .. UI.GuideLabel() .. "|r", string.format(L["zone %d%%"], math.floor((bar.pct or 0) * 100 + 0.5))
    local pace, shortPace
    if UI.flight then -- flying: when you land
        pace, shortPace = UI.FlightText(), UI.FlightText(true)
    else
        pace = UI.PaceText(false) or ""
        shortPace = string.gsub(pace, "^Level up in ", "")
    end
    local tries = {
        { guide .. "   " .. title .. "   " .. zonePct, pace }, { guide .. "   " .. title, pace },
        { guide .. "   " .. title, shortPace }, { title, pace }, { title, shortPace }, { title, "" },
    }
    -- Full rested XP first when it fits (user, 2026-11-27); otherwise the older layouts above.
    local rested = UI.RestedText("", "ShortText")
    if rested ~= "" and not UI.flight then
        table.insert(tries, 1, { guide .. "   " .. title, rested .. "   " .. shortPace })
        table.insert(tries, 1, { guide .. "   " .. title .. "   " .. zonePct, rested .. "   " .. shortPace })
    end
    UI.barWidth = barW
    local measure = UI.TextWidth or UI.MeasureText
    local pick = tries[#tries]
    for _, t in ipairs(tries) do
        local paceW = t[2] ~= "" and measure(bar.pace, t[2]) + 8 or 0
        if measure(bar.label, t[1]) + paceW + 4 <= barW then pick = t; break end
    end
    bar.pace:SetText(pick[2])
    local paceW = pick[2] ~= "" and measure(bar.pace, pick[2]) + 8 or 0
    bar.label:SetWidth(math.max(20, barW - paceW - 8))
    bar.label:SetText(pick[1])
    UI.progressPick = pick
end

local function DrawList(f, model, adapter, current, w, top, bottom)
    local sections = model:Sections()
    if UI.follow or not UI.section then UI.section = current and model:SectionOf(current) or #sections end
    if UI.jump then UI.section, UI.follow, UI.scrolled = UI.jump, false, true end -- browsed to a part or bracket
    local sec = sections[UI.section]
    f.bar:ClearAllPoints(); f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", PAD - 4, top); f.bar:SetSize(w - 2 * PAD + 8, BAR)
    f.bar.label:SetText(string.format(L["%s  |cff888888%d/%d|r"], DufforthTweaksHelperGuide.SectionTitle(sec), UI.section, #sections))
    SetOn(f.doneToggle, DB().showDone); SetOn(f.nextToggle, DB().showNext)
    top = top - BAR - 2
    local room = top - bottom
    f.list:ClearAllPoints(); f.list:SetPoint("TOPLEFT", f, "TOPLEFT", PAD - 4, top); f.list:SetSize(w - 2 * PAD + 8, math.max(10, room))
    for _, r in ipairs(f.rows) do r:Hide() end
    if not sec then f.empty:SetText(""); return top end
    local states = (model.rxp and model.RxStepState) and {} or model:States(#model.steps)
    local items = ListItems(model, states)
    if UI.jump then
        -- Browsed to a part: start at its header.
        for k, item in ipairs(items) do if item.header == UI.jump then UI.offset = k; break end end
        UI.jump = nil
    elseif UI.follow and not UI.scrolled then
        -- Following: the current step with the steps behind you above it (more of them in a taller box).
        local behind = math.floor(math.max(1, room / 24) * 0.4)
        UI.offset = 1
        local at = current and model.RxStepOf and model:RxStepOf(current)
        for k, item in ipairs(items) do
            if (item.rx and item.rx == at) or (not item.rx and item.step and item.step == current) then UI.offset = math.max(1, k - behind); break end
        end
    end
    UI.offset = math.max(1, math.min(UI.offset or 1, math.max(1, #items)))
    f.empty:SetText(#items == 0 and L["No steps to show: Done and Next choose which ones."] or "")
    local inner, y, n = w - 2 * PAD, 0, 0
    for k = UI.offset, #items do
        if n >= ROWS then break end
        local item, r = items[k], f.rows[n + 1]
        local text, state
        if item.header then
            r.isHeader, r.step, r.rx = true, nil, false
            text = "|cffffd100" .. DufforthTweaksHelperGuide.SectionTitle(sections[item.header]) .. "|r"
            local sec = sections[item.header]
            if model.rxp and sec and sec.part then
                -- RestedXP's guide title: the part's name, then its group ("26-28 Ashenvale" / "Speedrun Guide 22-30").
                local sub = model:RxSubName(sec.part)
                text = "|cffffd100" .. model:RxPartName(sec.part) .. "|r" .. (sub ~= "" and ("\n|cffd0d0d0" .. sub .. "|r") or "")
            end
            r.num:SetText(""); r.check:Hide()
        elseif item.rx then
            local n = item.rx
            state = item.state
            r.isHeader, r.step, r.rx = false, item.step, n
            local parts = {}
            for _, line in ipairs(model:RxDisplay(n)) do
                parts[#parts + 1] = line.row and UI.RxLineText(model, line.row, adapter, line.said) or line.text
            end
            text = table.concat(parts, "\n")
            if state == "done" then text = DONE_MARK .. text
            elseif state == "along" then text = L["|cff80b3ff(along the way)|r "] .. text end
            r.num:SetText(model.RxNumber and model:RxNumber(n) or n)
            r.check:Show()
            r.check.mark:SetShown(model:RxStepTicked(n))
        else
            r.rx = false
            local i = item.step
            local action, lines = StepText(model, i, adapter)
            state = states[i]
            r.isHeader, r.step = false, i
            text = action .. (lines ~= "" and ("\n" .. lines) or "")
            if state == "done" then text = DONE_MARK .. text
            elseif state == "passed" then text = L["|cff9d9d9d(passed by)|r "] .. text
            elseif state == "along" then text = L["|cff80b3ff(along the way)|r "] .. text end
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
    -- No right-click to hide: it turned the arrow off by accident and the guide looked like it had no waypoint
    -- (user, 2026-11-14). Menu > Waypoint arrow turns it off on purpose.
    a.pointer = a:CreateTexture(nil, "ARTWORK")
    a.pointer:SetTexture("Interface\\Minimap\\MinimapArrow"); a.pointer:SetSize(52, 52); a.pointer:SetPoint("TOP", 0, 0)
    if a.pointer.SetDesaturated then a.pointer:SetDesaturated(true) end
    a.check = a:CreateTexture(nil, "ARTWORK")
    a.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready"); a.check:SetSize(34, 34); a.check:SetPoint("TOP", 0, -8)
    -- Up or down to an NPC on another floor: still a waypoint, not just text (user, 2026-11-14: "there is no waypoint").
    a.climb = a:CreateTexture(nil, "ARTWORK"); a.climb:SetSize(40, 40); a.climb:SetPoint("TOP", 0, -4)
    a.climb:SetVertexColor(1, 0.63, 0.25); a.climb:Hide()
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
        GameTooltip:SetText(self.label:GetText() or L["Your guide step"], 1, 1, 1, 1, true)
        GameTooltip:AddLine(L["Points at your guide step. Drag to move. Menu > Waypoint arrow turns it off."], 0.7, 0.7, 0.7, true)
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
        DufforthTweaksHelper.RegisterMovable({ label = L["Guide arrow"], get = function() return arrow end,
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
        UI.LogChange("arrow", "arrow", not DB().arrow and "hidden: turned off (Menu > Waypoint arrow)" or (not t and L["hidden: no target"]) or "edit mode")
        if not (DufforthTweaksHelper.EditMode and DufforthTweaksHelper.EditMode()) then a:Hide() end
        return
    end
    a.climb:Hide()
    local pmap = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local ppos = pmap and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(pmap, "player")
    local px, py = XY(ppos)
    local pc, pn, pw
    if px then pc, pn, pw = WorldPos(pmap, px, py) end
    local tc, tn, tw = WorldPos(t.map, t.x / 100, t.y / 100)
    if not (pn and tn) then
        UI.LogChange("arrow", "arrow", string.format(L["hidden: no world position (you: map %s %s; target: map %s %s)"], tostring(pmap), tostring(pn ~= nil), tostring(t.map), tostring(tn ~= nil)))
        a:Hide(); return
    end
    a.label:SetText(t.text)
    if pc ~= tc then
        UI.LogChange("arrow", "arrow", "shown: go to " .. tostring(t.zone) .. " (another continent)")
        a.pointer:Hide(); a.check:Hide()
        a.dist:SetText(L["|cff73bfffGo to "] .. t.zone .. "|r")
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
    -- The game gives addons no height, so on the right floor you know it by the NPC: targeted or talking to you.
    local withNpc = t.npc and UnitName and (UnitName("target") == t.npc or UnitName("npc") == t.npc)
    UI.LogChange("arrow", "arrow", dist < 10 and (t.lift and not withNpc and (L["shown: go "] .. (t.lift > 0 and "up " or "down ") .. math.abs(t.lift) .. " yd") or L["shown: you are here"])
        or L["shown: pointing"])
    if dist < 10 and t.lift and not withNpc then
        -- Right under (or over) an NPC on another floor: the map spot is the same, the NPC isn't here (user, 2026-11-14).
        a.pointer:Hide(); a.check:Hide()
        local tex = t.lift > 0 and "Interface\\Buttons\\Arrow-Up-Up" or "Interface\\Buttons\\Arrow-Down-Up"
        a.climb:SetTexture(tex); rawset(a.climb, "tex", tex); a.climb:Show()
        a.dist:SetText(string.format(t.lift > 0 and L["|cffffa040Go up: %d yd above you|r"] or L["|cffffa040Go down: %d yd below you|r"], math.abs(t.lift)))
    elseif dist < 10 then
        a.pointer:Hide(); a.check:Show()
        a.dist:SetText(L["|cff40ff40You are here|r"])
    else
        a.check:Hide()
        local speed = GetUnitSpeed and GetUnitSpeed("player") or 0
        a.dist:SetText(string.format(L["%d yd  |cffffd100%s|r"], math.floor(dist + 0.5), DufforthTweaksHelperGuide.Eta(dist, speed)))
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
        SetOn(f.scanToggle, db.scanSound ~= false)
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
    -- RestedXP running too: the same part and step as it (its saved place, when it changes).
    if UI.model.rxp and DufforthTweaksHelperGuideRxUI and DufforthTweaksHelperGuideRxUI.Follow(UI.model) then
        UI.model = Model(UI.adapter)
    end
    local model, adapter = UI.model, UI.adapter
    local blocks = model:Blocks(ACTIVE, true) -- one row per step (user, 2026-11-15: "do not group the steps")
    UI.inTopBlock = {} -- steps the trip's cards already show (the "Along the way" lines skip them)
    for k = 1, math.max(1, blocks.trip or 1) do for _, i in ipairs(blocks[k] or {}) do UI.inTopBlock[i] = true end end
    local current = blocks[1] and blocks[1][1]
    -- RestedXP's route: side steps are listed first, the pointer's step is yours (GuideRx.lua).
    if model.rxp and model.RxActive then current = model:Current() end
    if UI.viewing and not model.steps[UI.viewing] then UI.viewing = nil end
    if UI.viewing then blocks = { { UI.viewing } } end -- a step you picked in the list
    -- The Start quest button for an item-started quest whose item is in your bags (not changed in combat).
    if not (InCombatLockdown and InCombatLockdown()) then
        local d = current and DufforthTweaksHelperGuide.Describe(model, current)
        if d and d.useItem then
            f.useItem.item = "item:" .. d.useItem
            f.useItem:SetText(d.useLabel or L["Start quest"])
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
    SetOn(f.autoToggle, DufforthTweaksHelperQuestAuto and DufforthTweaksHelperQuestAuto.Enabled())
    SetOn(f.vendorToggle, DufforthTweaksHelperQuestAuto and DufforthTweaksHelperQuestAuto.VendorEnabled and DufforthTweaksHelperQuestAuto.VendorEnabled())
    local bottom = -(h - 6)
    -- Level, zone and progress: always shown, right under the top strip (user, 2026-11-13).
    f.progress:Show()
    UI.ApplyLook()
    -- No errand rows (buy water, repair, train, class quest) on RestedXP's route (user, 2026-11-26).
    UI.errands = model.rxp and {} or UI.Errands(model, adapter, current)
    local top0 = DrawErrands(f, UI.errands, w, -3) -- the card first; the part line goes under the cards
    local note = UI.switchNote
    if note and (GetTime and GetTime() or 0) < note["until"] then
        if not rawget(f, "switchNote") then rawset(f, "switchNote", Font(f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 11)) end
        f.switchNote:ClearAllPoints(); f.switchNote:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, top0 - 2)
        f.switchNote:SetWidth(w - 2 * PAD); f.switchNote:SetJustifyH("LEFT"); f.switchNote:SetText(note.text); f.switchNote:Show()
        top0 = top0 - Height(f.switchNote, note.text) - 6
    elseif rawget(f, "switchNote") then
        f.switchNote:Hide(); UI.switchNote = nil
    end
    if UI.override or UI.viewing then
        -- Ends left of the "=" and "_" icons in the corner (2026-11-28: "Back to my step" sat over the Menu icon).
        f.viewBar:ClearAllPoints(); f.viewBar:SetPoint("TOPLEFT", f, "TOPLEFT", PAD - 4, top0); f.viewBar:SetWidth(w - 2 * PAD + 8 - 38)
        if UI.override then
            -- The arrow is on a class, dungeon or Forever quest you clicked (user, 2026-11-14: no way back to the step).
            f.viewBar.label:SetText(L["Arrow on: "] .. (UI.override.text or L["a quest"]))
            f.viewBar.label:SetPoint("RIGHT", f.viewBar.back, "LEFT", -4, 0)
            f.viewBar.go:Hide()
        else
            f.viewBar.label:SetText(string.format(L["Viewing step %d (yours: %s)"], UI.viewing, current or "-"))
            f.viewBar.label:SetPoint("RIGHT", f.viewBar.go, "LEFT", -4, 0)
            f.viewBar.go:Show()
        end
        if f.viewBar.label.SetWordWrap then f.viewBar.label:SetWordWrap(false) end
        f.viewBar:Show()
        top0 = top0 - 24
    else
        f.viewBar:Hide()
    end
    SetOn(f.stepsButton, DB().listOpen)
    if DB().listOpen then h = math.max(h, -top0 + 420); bottom = -(h - 6) end -- room for the part's steps
    local top, fits = DrawBlocks(f, model, adapter, blocks, w, top0, bottom)
    top = DrawProgress(f, model, current, w, top - 1) -- "30-33 Hillsbrad/Arathi   41m", like RestedXP's guide label
    UI.UpdateBar(f, model, current)
    UI.PlaceSecure(f)
    -- The current block is always shown whole: with 2 or 3 steps at the same place the box grows for them, and
    -- shrinks back with fewer (user, 2026-11-13). Your size limits only what comes after it.
    local mustH = math.floor(-top + 8) -- down to the blocks drawn (block 2 only when it fits your size)
    -- Then, like RestedXP (user, 2026-11-14 screenshots: "on top things I need to do, below only if I resize bigger I can
    -- see all steps"): what to do along the way, then the part's numbered steps filling the room you give the box, and
    -- the class, dungeon and your own quests at the very bottom.
    local along = AlongText(model, adapter)
    f.along:SetWidth(w - 2 * PAD); f.along:SetText(along)
    local alongH = along ~= "" and Height(f.along, along) + 4 or 0
    fits = fits and top - alongH >= bottom
    f.along:SetShown(fits and along ~= "")
    if fits and along ~= "" then f.along:ClearAllPoints(); f.along:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, top); top = top - alongH end
    f.note:SetText(""); f.note:Hide()
    local extrasH = ExtrasHeight(f, model, w)
    local listFits = fits and top - BAR - 40 - extrasH >= bottom
    f.bar:SetShown(listFits); f.list:SetShown(listFits)
    local used = top
    if listFits then
        used = DrawList(f, model, adapter, current, w, top, bottom + extrasH)
        used = math.min(used, bottom + extrasH)
    else
        for _, r in ipairs(f.rows) do r:Hide() end
    end
    used, fits = DrawExtras(f, model, w, used, bottom, fits)
    -- Fit the box to what it shows (not while you drag the corner).
    f.fitH = math.max(math.min(h, math.floor(-used + 22)), mustH)
    if not f.sizing then f:SetHeight(f.fitH) end
    UI.target = nil
    current = UI.viewing or current -- the arrow and pin follow the step you're looking at
    if current then
        if UI.override and UI.override.map and UI.override.x then
            -- The arrow is on a quest you clicked: the game's map pin goes there too, and stays until you go back.
            local o = UI.override
            local key = "o:" .. o.map .. ":" .. o.x .. ":" .. o.y
            if pinned ~= key then
                pinned = key
                pcall(function()
                    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(o.map, o.x / 100, o.y / 100))
                    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
                end)
            end
        else
            Pin(model, current)
        end
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
                          text = string.format(L["Spot %d of %d: "], k, #loop) .. UI.ArrowText(model, blocks[1], adapter), loop = true }
        elseif map and x and y and model:Pinpoint(current) then
            UI.target = { map = map, x = x, y = y, zone = zone, text = UI.ArrowText(model, blocks[1], adapter) }
            UI.target.lift, UI.target.npc = model:Lift(current)
        end
    end
    -- Errands (water, training, repairs) never take the arrow: waypoints are for quests (user, 2026-11-15: "do not put
    -- waypoints to buy water, only for quests"). Their rows stay in the box; a click on one points the arrow there.
    -- RestedXP's route: the arrow walks the active steps' points in order, a ghost goes to the corpse or Spirit Healer.
    local rxui = DufforthTweaksHelperGuideRxUI
    if model.rxp and model.RxArrow and rxui and not UI.viewing then
        UI.target = rxui.Target(model)
        rxui.UpdateMacro(model)
    end
    if UI.override and UI.override.map then UI.target = UI.override end -- you clicked a class or dungeon quest
    if current then
        local st = model.steps[current]
        UI.LogChange("step", "step", string.format(L["%d %s quest %s at %s %s, %s (route %s)"], current, tostring(st and st[1]), tostring(st and st[2]),
            tostring(st and st[3]), tostring(st and st[4]), tostring(st and st[5]), tostring(UI.RouteName())))
    end
    local tg = UI.target
    UI.LogChange("target", "target", tg and string.format("%s %s, %s: %s%s", tostring(tg.zone), tostring(tg.x), tostring(tg.y), Plain(tg.text),
        UI.override and L[" (a quest you clicked)"] or (tg.lift and (" (lift " .. tg.lift .. ")") or "")) or "none")
    UI.LogChange("settings", "settings", UI.SettingsLine())
    UI.UpdateArrow()
    local mapKey = current
    if model.rxp and model.RxPins then
        -- RestedXP's route: the pins follow the active steps' points (a point reached goes away).
        local ok, pins = pcall(model.RxPins, model)
        local keys = { tostring(DB().shown) .. tostring(DB().mapLines) }
        for _, p in ipairs(ok and pins or {}) do keys[#keys + 1] = p.n .. ":" .. p.k .. (p.arrow and "*" or "") end
        mapKey = table.concat(keys, ",")
        if mapKey ~= UI.miniKey then
            UI.miniKey = mapKey
            local okm, err = pcall(UI.DrawMinimapPins, model)
            if not okm then UI.Log("error", "minimap: " .. tostring(err)) end
        end
    end
    if WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown() and UI.mapDrawnFor ~= mapKey then
        UI.mapDrawnFor = mapKey
        UI.SafeDrawMap()
    end
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
        GameTooltip:SetText(L["Leveling guide"], 1, 0.82, 0)
        if self.text then GameTooltip:AddLine(self.text, 1, 1, 1, true) end
        GameTooltip:AddLine(UI.Hidden() and L["Click: open the guide. Drag: move."] or L["Click: minimize the guide. Drag: move."], 0.6, 0.8, 1, true)
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
    local number = current
    if model and model.rxp and model.RxNumber and model.RxStepOf and current then number = model:RxNumber(model:RxStepOf(current)) or current end
    b.num:SetText(number and (L["Step "] .. number) or "")
    b.text = d and string.gsub(d.action or "", "|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") or nil
    local show = DB().shown and UI.Hidden()
    b:SetShown(show and true or false)
    if DufforthTweaksHelperMinimap_SetBadge then DufforthTweaksHelperMinimap_SetBadge(show and d and d.icon or nil) end
end

-- Back to your step: the arrow and the game's map pin leave the quest you clicked, and the box shows your step.
function UI.BackToStep()
    UI.override, UI.viewing = nil, nil
    pinned = nil
    UI.Refresh()
end

-- The arrow and the game's map pin on step i (a click on its card), until you go back to your step.
function UI.PinStep(i)
    local model = UI.model
    if not (model and i) then return end
    local number = i
    if model.rxp and model.RxStepOf then
        -- RestedXP's route: every card is an active step and the arrow already walks them (user, 2026-11-28: an
        -- "Arrow on: Step 806" bar for the step you're on, "fix"). Only a step that isn't active takes the arrow.
        local n = model:RxStepOf(i)
        for _, s in ipairs(model:RxActive()) do
            if s == n then
                if UI.override then UI.override = nil; pinned = nil; UI.Refresh() end
                return
            end
        end
        number = model.RxNumber and model:RxNumber(n) or i
    end
    local zone, x, y, map = model:Place(i)
    if not (map and x and y) then return end
    local d = DufforthTweaksHelperGuide.Describe(model, i)
    UI.override = { step = i, map = map, x = x, y = y, zone = zone,
                    text = string.format(L["Step %d: %s"], number, Plain(d and d.action or "")) }
    pinned = nil
    UI.Refresh()
end

-- Right-click on a step card: its options in a small menu by the mouse.
function UI.StepMenu(i, anchor)
    local model = UI.model
    if not (model and i) then return end
    local m = UI.stepMenu
    if not m then
        m = CreateFrame("Frame", "DufforthTweaksHelperStepMenu", UIParent)
        m:SetFrameStrata("DIALOG"); m:SetSize(190, 10)
        m.bg = m:CreateTexture(nil, "BACKGROUND"); m.bg:SetAllPoints(); m.bg:SetColorTexture(0.06, 0.06, 0.07, 0.96)
        m.rows = {}
        m.idle = 0
        -- Closes like the main Menu: a moment after the mouse leaves it, or on a click anywhere else (user, 2026-11-15:
        -- "right click on the steps is persistent").
        m:SetScript("OnUpdate", function(self, elapsed)
            if UI.MouseOver(self) then self.idle = 0 else self.idle = self.idle + (elapsed or 0) end
            if self.idle > 0.8 then self:Hide() end
        end)
        pcall(m.RegisterEvent, m, "GLOBAL_MOUSE_DOWN")
        m:SetScript("OnEvent", function(self) if not UI.MouseOver(self) then self:Hide() end end)
        UI.stepMenu = m
    end
    local done = model.saved.skipped[i]
    local options = {
        { L["Put the pin and arrow here"], function() UI.PinStep(i) end },
        { done and L["Undo done"] or L["Mark done"], function() model:ToggleStep(i); UI.Refresh() end },
        { L["Continue from this step"], function() UI.ContinueFrom(i) end },
        { L["Back to my step"], function() UI.BackToStep() end },
    }
    for k, o in ipairs(options) do
        local r = m.rows[k]
        if not r then
            -- A slim text row with a light hover, like the main Menu (user: "focus on text, not on the button").
            r = CreateFrame("Button", nil, m)
            r:SetSize(182, 18); r:SetPoint("TOPLEFT", 4, -4 - (k - 1) * 18)
            r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, 0.08)
            r.label = Font(r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 12)
            r.label:SetPoint("LEFT", 6, 0); r.label:SetJustifyH("LEFT")
            m.rows[k] = r
        end
        r.label:SetText(o[1]); rawset(r, "text", o[1])
        r:SetScript("OnClick", function() m:Hide(); o[2]() end)
        r:Show()
    end
    for k = #options + 1, #m.rows do m.rows[k]:Hide() end
    m:SetHeight(8 + #options * 18)
    m:ClearAllPoints()
    local x, y = GetCursorPosition and GetCursorPosition()
    local scale = UIParent.GetEffectiveScale and tonumber((UIParent:GetEffectiveScale())) or 1
    if x and y then m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    else m:SetPoint("TOPLEFT", anchor or UIParent, "TOPRIGHT", 4, 0) end
    m.idle = 0
    m:Show()
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
watcher:SetScript("OnEvent", function(_, event, a1)
    if event == "PLAYER_LOGIN" then
        pcall(UI.LogLogin)
        -- Questie's yellow objective icons when it's installed (user, 2026-11-14).
        local questie = QuestieLoader ~= nil or (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Questie"))
        DufforthTweaksHelperGuide.UseQuestieIcons(questie and true or false)
    end
    if event == "QUEST_ACCEPTED" or event == "QUEST_TURNED_IN" or event == "QUEST_REMOVED" then
        -- QUEST_ACCEPTED gives the log index first on older clients, the quest id on newer: log what came.
        UI.Log("quest", event:lower():gsub("quest_", "") .. " " .. tostring(a1))
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        UI.Log("zone", tostring(GetRealZoneText and GetRealZoneText()))
    elseif event == "PLAYER_LEVEL_UP" then
        UI.Log("level", tostring(a1))
    end
    if event == "TAXIMAP_OPENED" then pcall(UI.LearnFlights); pcall(UI.AutoFly) end
    if event == "HEARTHSTONE_BOUND" and GetRealZoneText then DB().homeZone = DufforthTweaksHelperLocale.ZoneName() end
    if event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" or event == "PLAYER_LOGIN" then pcall(UI.TrackXP) end
    if event == "PLAYER_REGEN_DISABLED" then UI.inCombat = true end
    if event == "PLAYER_REGEN_ENABLED" then UI.inCombat = false; UI.peek = nil end
    if event == "PLAYER_ENTERING_WORLD" then UI.peek = nil end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ENTERING_WORLD" then pcall(UI.ApplyLook) end
    if event == "PLAYER_REGEN_DISABLED" then return end -- fading out needs no redraw
    if soon then return end
    soon = true
    local function go()
        soon = false
        local ok, err = pcall(UI.Refresh)
        if not ok then UI.Log("error", "refresh: " .. tostring(err)) end
    end
    if C_Timer then C_Timer.After(0.5, go) else go() end
end)
