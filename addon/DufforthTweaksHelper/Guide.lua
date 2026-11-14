-- Dufforth Tweaks Helper, leveling guide: the model. Pure: it never calls the game directly.
--
-- The route (GuideData.lua) is a list of steps planned for a new character (catalog/build_route.py).
-- The model decides which step is current for YOU from a small game adapter (level, class, race,
-- completed quests, quest log, finished objectives, zone), so it works from any level: steps for
-- quests you did, gave up, or that are too low and lead nowhere are passed by. A low quest that
-- starts a chain up to your level is kept, with advice. The view (GuideUI.lua) only draws this.
--
-- adapter = { level(), classBit(), raceBit(), done(id), inLog(id), complete(id), zone(), logIds() }
--           optional objectiveDone(id, name): true/false for one objective (the game's line), nil if unknown
--
-- Along the way (user, 2026-11-13): an objective whose monsters are all over the map (raptors, zhevras;
-- "wide" in the data) doesn't hold you up: you kill them while going to other quests. The guide asks
-- for it only when it must be done: before its turn-in or before the next part of the route.

local Guide = {}
DufforthTweaksHelperGuide = Guide

-- Quest fields: title, level, minLevel, classes, type, prev, nextInChain, giver, {zone,x,y}, turnIn, {zone,x,y}, goals, gear, startItem, races
local TITLE, LEVEL, MIN, CLASSES, KIND, PREV, NEXT, GIVER, GIVER_AT, TURNIN, TURNIN_AT, GOALS, GEAR, ITEM, RACES = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
-- 16: drop = { item name, monster, chance % } for a quest started by a dropped item, else 0
local DROP = 16
-- Step fields: kind, quest, zone, x, y, level, text, objective (do steps)
local S_KIND, S_QUEST, S_ZONE, S_X, S_Y, S_LEVEL, S_TEXT, S_GOAL = 1, 2, 3, 4, 5, 6, 7, 8
Guide.STEP = { KIND = S_KIND, QUEST = S_QUEST, ZONE = S_ZONE, X = S_X, Y = S_Y, LEVEL = S_LEVEL, TEXT = S_TEXT, GOAL = S_GOAL }
-- Objective fields: kind, name, count, zone, x, y, source (who drops it), wide (monsters all over the map)
local G_KIND, G_NAME, G_COUNT, G_X, G_Y, G_SOURCE, G_WIDE = 1, 2, 3, 5, 6, 7, 8
local NEAR_SPOT = 4 -- map % apart: two objectives this close are one stop

local LOW = 3          -- a quest this many levels below you (or more) is skipped unless it starts a worthwhile chain
local GRAY = 6         -- a quest this many levels below you gives little: abandon it
Guide.GRAY = GRAY
local CHAIN_HOPS = 4   -- a chain counts if it reaches your level within this many quests
local CLASS_BELOW = 5  -- class quests shown down to this many levels below you
local CLASS_ABOVE = 1  -- and up to this many above (user: a level 30 quest at 27 is too early)
local DUNGEON_BELOW, DUNGEON_ABOVE = 2, 5

-- Which route a race starts on (UnitRace's second value).
Guide.ROUTE_FOR_RACE = { Orc = "Durotar", Troll = "Durotar", Tauren = "Mulgore", Scourge = "Tirisfal Glades", Undead = "Tirisfal Glades" }
Guide.RACE_BITS = { Orc = 2, Scourge = 16, Undead = 16, Tauren = 32, Troll = 128 }

local Model = {}
Model.__index = Model

function Guide.NewModel(data, routeName, game, saved)
    local route = data.routes[routeName]
    saved.skipped = saved.skipped or {}
    return setmetatable({ data = data, steps = route and route.steps or {}, game = game, saved = saved }, Model)
end

function Model:Quest(id) return self.data.quests[id] end

-- The highest level a chain reaches within CHAIN_HOPS quests from q (its own level if none).
function Model:ChainTop(id)
    local top, q, hops = 0, self:Quest(id), 0
    while q and hops <= CHAIN_HOPS do
        top = math.max(top, q[LEVEL])
        q, hops = self:Quest(q[NEXT]), hops + 1
    end
    return top
end

-- Done or in your log, counting what the steps before an upcoming one will have done (assume).
local function Done(g, id, assume) return g.done(id) or (assume and assume.done[id]) or false end
local function InLog(g, id, assume) return g.inLog(id) or (assume and assume.log[id]) or false end

-- Could you take this quest now (race, earlier quest)? Level is judged separately.
function Model:Open(id, assume)
    local q, g = self:Quest(id), self.game
    if not q then return false end
    if q[RACES] ~= 0 and math.floor(q[RACES] / g.raceBit()) % 2 ~= 1 then return false end
    local prev = q[PREV]
    if prev > 0 and not Done(g, prev, assume) and not InLog(g, prev, assume) then return false end
    if prev < 0 and not InLog(g, -prev, assume) then return false end
    return true
end

-- Is a quest worth taking at your level? Low quests only when their chain reaches your level.
function Model:Worth(id)
    local q, level = self:Quest(id), self.game.level()
    if not q then return false end
    if q[LEVEL] > level - LOW then return true end
    return self:ChainTop(id) >= level - 1
end

-- The next step that isn't settled, from i on, for a travel step's look-ahead.
function Model:NextOpenAfter(i, assume)
    for j = i + 1, #self.steps do
        if self.steps[j][S_KIND] ~= "travel" and not self:Settled(j, assume) then return j end
    end
end

-- True when step i needs nothing from you (done, not for you, or passed by).
function Model:Settled(i, assume)
    if self.saved.skipped[i] then return true end
    local step, g = self.steps[i], self.game
    local kind, id = step[S_KIND], step[S_QUEST]
    if kind == "grind" then return g.level() > step[S_LEVEL] end
    if kind == "flight" then return g.flightKnown ~= nil and g.flightKnown(step[S_ZONE], step[S_X], step[S_Y]) and true or false end
    if kind == "travel" then
        if g.zone() == step[S_ZONE] then return true end
        local nextStep = self:NextOpenAfter(i, assume)
        return not nextStep or self.steps[nextStep][S_ZONE] ~= step[S_ZONE]
    end
    -- A quest you skipped by hand: its later steps go too.
    if self.saved.skippedQuests and self.saved.skippedQuests[id] then return true end
    if Done(g, id, assume) then return true end
    if kind == "accept" then
        if InLog(g, id, assume) then return true end
        return not self:Open(id, assume) or not self:Worth(id)
    end
    if not InLog(g, id, assume) then return true end -- never taken: nothing to do or turn in
    if kind == "do" then
        if assume and assume.log[id] then return false end
        if g.objectiveDone then
            local goal = self:Goal(i)
            local finished = goal and g.objectiveDone(id, goal[G_NAME])
            if finished ~= nil then return finished end
        end
        return g.complete(id)
    end
    return false -- turnin: in your log, not done yet
end

-- The objective a do step works on, or nil.
function Model:Goal(i)
    local step = self.steps[i]
    if not step or step[S_KIND] ~= "do" then return nil end
    local q = self:Quest(step[S_QUEST])
    return q and q[GOALS] and q[GOALS][step[S_GOAL] or 1]
end

-- A do step whose monsters are all over the map: done along the way.
function Model:Wide(i)
    local goal = self:Goal(i)
    return goal ~= nil and goal[G_WIDE] == 1
end

-- The step by which along-the-way step i must be done: its quest's turn-in or the next part of the route.
function Model:Deadline(i)
    self.deadlines = self.deadlines or {}
    if self.deadlines[i] then return self.deadlines[i] end
    local id, section, at = self.steps[i][S_QUEST], self:SectionOf(i), #self.steps + 1
    for j = i + 1, #self.steps do
        local step = self.steps[j]
        if self:SectionOf(j) ~= section or (step[S_KIND] == "turnin" and step[S_QUEST] == id) then at = j; break end
    end
    self.deadlines[i] = at
    return at
end

function Model:Current()
    -- A flight path is asked for while you are in its part of the route; one behind you doesn't send you back.
    local first, flights = nil, {}
    for i = 1, #self.steps do
        if not self:Wide(i) and not self:Settled(i) then
            if self.steps[i][S_KIND] == "flight" then
                flights[#flights + 1] = i
            else
                first = i
                for _, f in ipairs(flights) do
                    if self:SectionOf(f) == self:SectionOf(i) then first = f; break end
                end
                break
            end
        end
    end
    first = first or flights[1]
    local limit = first or #self.steps + 1
    for i = 1, limit - 1 do
        if self:Wide(i) and not self:Settled(i) and self:Deadline(i) <= limit then return i end -- must be done now
    end
    return first
end

-- Along-the-way steps you have in your log and haven't finished (not the current step).
function Model:Along()
    local out, current = {}, self:Current()
    for i = 1, #self.steps do
        if i ~= current and self:Wide(i) and not self:Settled(i) and self.game.inLog(self.steps[i][S_QUEST]) then out[#out + 1] = i end
    end
    return out
end

-- What doing step i will have done, for judging the steps after it.
local function Take(assume, step)
    local kind, id = step[S_KIND], step[S_QUEST]
    if kind == "accept" then assume.log[id] = true
    elseif kind == "turnin" then assume.done[id] = true; assume.log[id] = nil end
end

-- The current step and the next ones (up to n), as if you do each in turn: a quest picked up a step
-- earlier still has its objectives ahead, and one turned in opens its follow-up.
-- Along-the-way steps wait until their deadline comes.
function Model:Upcoming(n)
    local out, assume, current, waiting = {}, { log = {}, done = {} }, self:Current(), {}
    if not current then return out end
    local function flush(upTo)
        for k = #waiting, 1, -1 do
            if #out < n and self:Deadline(waiting[k]) <= upTo then out[#out + 1] = table.remove(waiting, k) end
        end
    end
    for i = 1, #self.steps do
        if #out >= n then break end
        if i < current and not self:Wide(i) then
            -- behind you: a flight path you passed by
        elseif not self:Settled(i, assume) then
            if self:Wide(i) and i ~= current then
                waiting[#waiting + 1] = i
            else
                flush(i)
                if #out < n then out[#out + 1] = i; Take(assume, self.steps[i]) end
            end
        end
    end
    flush(#self.steps + 1)
    return out
end

-- Two do steps you can do as one: the same monsters (kill or drop), or objectives at the same spot.
function Model:Together(i, j)
    local a, b = self:Goal(i), self:Goal(j)
    if not (a and b) or self.steps[i][S_ZONE] ~= self.steps[j][S_ZONE] then return false end
    local function mob(goal) return goal[G_KIND] == "kill" and goal[G_NAME] or (goal[G_SOURCE] ~= "" and goal[G_SOURCE]) or nil end
    if mob(a) and mob(a) == mob(b) then return true end
    local si, sj = self.steps[i], self.steps[j]
    return si[S_X] and sj[S_X] and math.abs(si[S_X] - sj[S_X]) <= NEAR_SPOT and math.abs(si[S_Y] - sj[S_Y]) <= NEAR_SPOT or false
end

-- The next n blocks: upcoming steps, with steps you can do as one put together.
function Model:Blocks(n)
    local blocks = {}
    for _, i in ipairs(self:Upcoming(n * 4)) do
        local last = blocks[#blocks]
        if last and self:Together(last[1], i) then last[#last + 1] = i
        elseif #blocks < n then blocks[#blocks + 1] = { i }
        else break end
    end
    return blocks
end

-- Each step up to last: "done" (before the current step), "current", "open" (ahead) or "passed" (ahead,
-- but the guide will pass it by: gray, not open to you, skipped).
function Model:States(last)
    local states, current, assume = {}, self:Current(), { log = {}, done = {} }
    for i = 1, math.min(last, #self.steps) do
        if self.saved.skipped[i] then
            states[i] = "done" -- marked done by hand
        elseif not current or i < current then
            local open = not self:Settled(i)
            states[i] = (open and self:Wide(i)) and "along" or (open and "passed") or "done"
        elseif self:Settled(i, assume) then states[i] = "passed"
        elseif i ~= current and self:Wide(i) then states[i] = "along"
        else
            states[i] = i == current and "current" or "open"
            Take(assume, self.steps[i])
        end
    end
    return states
end

-- ---- Sections: the route by zone, with the levels you have there ("12-16 The Barrens") ----
-- A visit shorter than this (a hub over a zone border) stays in the section around it.
local MIN_SECTION = 4

function Model:Sections()
    if self.sections then return self.sections end
    local runs = {}
    for i, step in ipairs(self.steps) do
        local run = runs[#runs]
        if run and run.zone == step[S_ZONE] then run.last = i
        else runs[#runs + 1] = { zone = step[S_ZONE], first = i, last = i } end
    end
    local out = {}
    for _, run in ipairs(runs) do
        local prev = out[#out]
        if prev and (prev.zone == run.zone or run.last - run.first + 1 < MIN_SECTION) then prev.last = run.last
        else out[#out + 1] = run end
    end
    self.sectionOf = {}
    for k, sec in ipairs(out) do
        sec["from"], sec["to"] = self.steps[sec.first][S_LEVEL], self.steps[sec.last][S_LEVEL]
        for i = sec.first, sec.last do self.sectionOf[i] = k end
    end
    self.sections = out
    return out
end

function Model:SectionOf(i)
    self:Sections()
    return self.sectionOf[i]
end

-- Steps behind you in section k, and its size (the green bar).
function Model:SectionProgress(k)
    local sec = self:Sections()[k]
    if not sec then return 0, 0 end
    local states, done = self:States(sec.last), 0
    for i = sec.first, sec.last do
        if states[i] == "done" then done = done + 1 end
    end
    return done, sec.last - sec.first + 1
end

-- ---- The arrow ----
-- Which way to turn and how far: positions as world (north, west) yards; facing in radians from north,
-- turning left is +. Returns the angle to turn (left +, -pi..pi) and the distance.
function Guide.Bearing(pn, pw, tn, tw, facing)
    local dn, dw = tn - pn, tw - pw
    local rel = math.atan2(dw, dn) - (facing or 0)
    while rel > math.pi do rel = rel - 2 * math.pi end
    while rel <= -math.pi do rel = rel + 2 * math.pi end
    return rel, math.sqrt(dn * dn + dw * dw)
end

-- Time to cover a distance at a speed (yards a second; standing still counts as running, 7).
function Guide.Eta(distance, speed)
    if not speed or speed <= 0 then speed = 7 end
    local seconds = math.floor(distance / speed + 0.5)
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

function Guide.SectionTitle(sec)
    if not sec then return "" end
    if sec["from"] == sec["to"] then return string.format("%d %s", sec["from"], sec.zone) end
    return string.format("%d-%d %s", sec["from"], sec["to"], sec.zone)
end

-- Advice for a step: a chain worth starting, a level to reach first.
function Model:Note(i)
    local step = self.steps[i]
    if not step or step[S_KIND] ~= "accept" then return nil end
    local q, level = self:Quest(step[S_QUEST]), self.game.level()
    if not q then return nil end
    if q[MIN] > level then return string.format("Needs level %d: do other quests or grind first.", q[MIN]) end
    if q[LEVEL] <= level - LOW then
        return string.format("Low, but it starts a chain up to level %d: worth doing.", self:ChainTop(step[S_QUEST]))
    end
end

function Model:Skip()
    local i = self:Current()
    if not i then return end
    self.saved.skipped[i] = true
    local id = self.steps[i][S_QUEST]
    if id and id > 0 and self.steps[i][S_KIND] == "accept" then
        self.saved.skippedQuests = self.saved.skippedQuests or {}
        self.saved.skippedQuests[id] = true
    end
    self.saved.lastSkipped = i
end

-- Mark one step done by hand (you did it without the guide), or undo that.
function Model:ToggleStep(i)
    if not self.steps[i] then return end
    if self.saved.skipped[i] then self.saved.skipped[i] = nil else self.saved.skipped[i] = true end
end

function Model:Back()
    local i = self.saved.lastSkipped
    if not i then return end
    self.saved.skipped[i] = nil
    local id = self.steps[i][S_QUEST]
    if id and self.saved.skippedQuests then self.saved.skippedQuests[id] = nil end
    self.saved.lastSkipped = nil
end

local function Entry(id, q, data)
    local at = q[GIVER_AT] or {}
    return { id = id, title = q[TITLE], level = q[LEVEL], giver = q[GIVER], at = at, zone = at[1], x = at[2], y = at[3],
             dungeon = data and data.extras and data.extras.dungeonOf and data.extras.dungeonOf[id] }
end

-- Class quests for your class you can take now, lowest first (at most 3).
function Model:ClassQuests()
    local out, g, level = {}, self.game, self.game.level()
    for _, id in ipairs(self.data.extras.class or {}) do
        local q = self:Quest(id)
        if q and math.floor(q[CLASSES] / g.classBit()) % 2 == 1 and q[MIN] <= level and q[LEVEL] >= level - CLASS_BELOW
            and q[LEVEL] <= level + CLASS_ABOVE
            and not g.done(id) and not g.inLog(id) and self:Open(id) then
            out[#out + 1] = Entry(id, q, self.data)
        end
    end
    table.sort(out, function(a, b) return a.level < b.level end)
    while #out > 3 do table.remove(out) end
    return out
end

-- Dungeon quests near your level you can pick up.
function Model:DungeonQuests()
    local out, g, level = {}, self.game, self.game.level()
    for _, id in ipairs(self.data.extras.dungeon or {}) do
        local q = self:Quest(id)
        if q and q[MIN] <= level and q[LEVEL] >= level - DUNGEON_BELOW and q[LEVEL] <= level + DUNGEON_ABOVE
            and not g.done(id) and not g.inLog(id) and self:Open(id) then
            out[#out + 1] = Entry(id, q, self.data)
        end
    end
    table.sort(out, function(a, b) return a.level < b.level end)
    return out
end

-- Quests in your log that went gray (little experience left): worth abandoning.
function Model:GrayInLog()
    local out, level = {}, self.game.level()
    for _, id in ipairs(self.game.logIds()) do
        local q = self:Quest(id)
        if q and q[LEVEL] <= level - GRAY then out[#out + 1] = Entry(id, q, self.data) end
    end
    return out
end

-- ---- Presenter: how a step reads (no frames, so it's tested like the model) ----
-- User (2026-11-13): show whether a step is kill, loot, use an object or talk to an NPC, names
-- highlighted, with the game's own progress lines, several steps at a time.
local ICONS = {
    accept = "Interface\\GossipFrame\\AvailableQuestIcon", turnin = "Interface\\GossipFrame\\ActiveQuestIcon",
    kill = "Interface\\Icons\\Ability_DualWield", loot = "Interface\\Icons\\INV_Misc_Bag_08",
    use = "Interface\\Icons\\INV_Misc_Gear_01", explore = "Interface\\Icons\\INV_Misc_Map_01",
    travel = "Interface\\Icons\\Ability_Rogue_Sprint", grind = "Interface\\Icons\\Ability_Warrior_Rampage",
    flight = "Interface\\TaxiFrame\\UI-Taxi-Icon-Green",
}
Guide.ICONS = ICONS
local function Quest(text) return "|cffffd100" .. text .. "|r" end
local function Npc(text) return "|cff40ff40" .. text .. "|r" end
local function Thing(text) return "|cffff8040" .. text .. "|r" end

-- { kind, icon, action, lines = { {text, finished} }, note } for step i. objectives: the game's list for
-- the step's quest ({text, finished}), or nil.
function Guide.Describe(model, i, objectives)
    local step = model.steps[i]
    if not step then return nil end
    local kind, id = step[S_KIND], step[S_QUEST]
    local q = model:Quest(id)
    local d = { kind = kind, lines = {}, note = model:Note(i) }
    local drop = q and type(q[DROP]) == "table" and q[DROP]
    if kind == "accept" and drop then
        -- Started by a dropped item: loot it, then right-click it (the view offers a button for that).
        if model.game.hasItem and model.game.hasItem(q[ITEM]) then
            d.kind, d.useItem = "use", q[ITEM]
            d.action = string.format("Right-click %s in your bags: starts %s", Thing(drop[1]), Quest(q[TITLE]))
        else
            d.kind = "loot"
            local chance = drop[3] < 100 and string.format(" |cffaaaaaa(%d%% drop)|r", math.floor(drop[3] + 0.5)) or ""
            d.action = string.format("Loot %s from %s%s: starts %s", Thing(drop[1]), Thing(drop[2]), chance, Quest(q[TITLE]))
        end
    elseif kind == "accept" and q then
        d.action = string.format("Talk to %s: accept %s", Npc(q[GIVER]), Quest(q[TITLE]))
    elseif kind == "turnin" and q then
        d.action = string.format("Turn in %s to %s", Quest(q[TITLE]), Npc(q[TURNIN]))
    elseif kind == "do" and q then
        local index = step[S_GOAL] or 1
        local goal = q[GOALS] and q[GOALS][index]
        local goalKind = goal and goal[G_KIND] or "kill"
        if goalKind == "collect" then
            d.kind = "loot"
            local from = goal[G_SOURCE] and goal[G_SOURCE] ~= "" and (" from " .. Thing(goal[G_SOURCE])) or ""
            d.action = string.format("Loot %s%s", Thing(goal[G_NAME]), from)
        elseif goalKind == "use" then
            d.kind = "use"
            d.action = "Use " .. Thing(goal[G_NAME])
        elseif goalKind == "explore" then
            d.kind = "explore"
            d.action = "Explore the marked area"
        else
            d.kind = "kill"
            d.action = goal and string.format("Kill %d %s", goal[G_COUNT], Thing(goal[G_NAME])) or step[S_TEXT]
        end
        d.action = d.action .. "  |cffaaaaaa(" .. q[TITLE] .. ")|r"
        if objectives then
            local own
            for k, o in ipairs(objectives) do
                if goal and o.text and string.find(o.text, goal[G_NAME], 1, true) then own = k end
            end
            own = own or (objectives[index] and index)
            for k, o in ipairs(objectives) do
                if not own or k == own then d.lines[#d.lines + 1] = { text = o.text, finished = o.finished and true or false } end
            end
            if goal and goal[G_WIDE] == 1 then d.wide = true end
        end
    elseif kind == "travel" then
        d.action = "Go to " .. Npc(step[S_ZONE])
    elseif kind == "flight" then
        local who = string.match(step[S_TEXT] or "", "from (.+)$") or "the flight master"
        d.action = string.format("Talk to %s: get the flight path", Npc(who))
    else
        d.action = step[S_TEXT]
    end
    d.icon = ICONS[d.kind] or ICONS.kill
    return d
end

-- ---- Directions: how to reach a step in another zone (user, 2026-11-13) ----
-- data.travel = { flights = {{name, zone, x, y, continent}}, continents = {zone = 0|1}, transports = {{kind, from, to}} }
-- The flight master for a zone that has none of its own (you arrive by zeppelin outside the city).
local CITY_FOR = { Durotar = "Orgrimmar", ["Tirisfal Glades"] = "Undercity", Mulgore = "Thunder Bluff" }

local function Near(points, x, y)
    local best, bestD
    for _, p in ipairs(points) do
        local d = (x and p[3]) and ((p[3] - x) ^ 2 + (p[4] - y) ^ 2) or 0
        if not bestD or d < bestD then best, bestD = p, d end
    end
    return best
end

local function FlightsIn(travel, zone)
    local out = {}
    for _, f in ipairs(travel.flights or {}) do
        if f[2] == zone or f[2] == CITY_FOR[zone] then out[#out + 1] = f end
    end
    return out
end

local function Leg(text, zone, x, y) return { text = text, zone = zone, x = x, y = y } end
local function At(zone, x, y) return string.format("(%s %d, %d)", zone, math.floor(x + 0.5), math.floor(y + 0.5)) end

-- The legs to step i from where you are: { {text, zone, x, y} }, or nil when you're in its zone.
function Model:Directions(i)
    local travel, step = self.data.travel, self.steps[i]
    if not (travel and travel.continents and step) then return nil end
    local target, here = step[S_ZONE], self.game.zone()
    if not here or here == "" or here == target then return nil end
    local legs, from, fromX, fromY = {}, here, nil, nil
    local tc, pc = travel.continents[target], travel.continents[here]
    if tc and pc and tc ~= pc then
        local pick
        for _, t in ipairs(travel.transports or {}) do
            for _, way in ipairs({ { t[2], t[3] }, { t[3], t[2] } }) do
                local a, b = way[1], way[2]
                if a[5] == pc and b[5] == tc then
                    local score = (b[2] == target and 3 or 0) + (a[2] == here and 2 or 0) + (t[1] == "zeppelin" and 1 or 0)
                    if not pick or score > pick.score then pick = { kind = t[1], a = a, b = b, score = score } end
                end
            end
        end
        if not pick then return nil end
        legs[#legs + 1] = Leg("Go to the " .. pick.a[1] .. " " .. At(pick.a[2], pick.a[3], pick.a[4]), pick.a[2], pick.a[3], pick.a[4])
        legs[#legs + 1] = Leg("Take the " .. pick.kind .. " to the " .. pick.b[1] .. " " .. At(pick.b[2], pick.b[3], pick.b[4]), pick.b[2], pick.b[3], pick.b[4])
        from, fromX, fromY = pick.b[2], pick.b[3], pick.b[4]
    end
    if from ~= target then
        local to = Near(FlightsIn(travel, target), step[S_X], step[S_Y])
        local start = Near(FlightsIn(travel, from), fromX, fromY)
        local g = self.game
        if to and g.flightKnown and not g.flightKnown(to[2], to[3], to[4]) then
            to = nil -- you can't fly to a flight path you don't have yet
        end
        if not to then
            legs[#legs + 1] = Leg(string.format("Run to %s %d, %d", target, math.floor((step[S_X] or 50) + 0.5), math.floor((step[S_Y] or 50) + 0.5)),
                target, step[S_X], step[S_Y])
        elseif to and start and start ~= to then
            legs[#legs + 1] = Leg(string.format("Fly from %s %s to %s (%s)", start[1], At(start[2], start[3], start[4]), to[1], to[2]),
                start[2], start[3], start[4])
        elseif to then
            legs[#legs + 1] = Leg(string.format("Fly to %s (%s) from a flight master", to[1], to[2]), to[2], to[3], to[4])
        end
    end
    return #legs > 0 and legs or nil
end

-- Where a step is: zone, x, y and the map ID for a pin.
function Model:Place(i)
    local step = self.steps[i]
    if not step then return nil end
    return step[S_ZONE], step[S_X], step[S_Y], self.data.uiMaps[step[S_ZONE]]
end
