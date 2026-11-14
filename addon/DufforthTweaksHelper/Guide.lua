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
--           optional position(): zone, x, y (map %) where you stand: the nearest open objective comes first
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
local S_DEST = 9 -- fly / hearth: { zone, x, y } where you arrive
local S_FARM = 10 -- farm (explorer style): { {item, monster, chance %, x, y}, ... } the addon picks from by price
Guide.STEP = { KIND = S_KIND, QUEST = S_QUEST, ZONE = S_ZONE, X = S_X, Y = S_Y, LEVEL = S_LEVEL, TEXT = S_TEXT, GOAL = S_GOAL }
-- Objective fields: kind, name, count, zone, x, y, source (who drops it), wide (monsters all over the map),
-- loop (spots to circle where they spawn: {{x, y}...}), monster min and max level, elite (1)
local G_KIND, G_NAME, G_COUNT, G_X, G_Y, G_SOURCE, G_WIDE = 1, 2, 3, 5, 6, 7, 8
local G_LOOP, G_LMIN, G_LMAX, G_ELITE = 9, 10, 11, 12
local G_GUESSED, G_INSTANCE = 13, 14 -- no place in the data (put at the giver) / inside this dungeon (map id)
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
    if (q[CLASSES] or 0) ~= 0 and math.floor(q[CLASSES] / g.classBit()) % 2 ~= 1 then return false end -- another class's
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
    if kind == "fly" or kind == "hearth" or kind == "home" then return self:ShortcutSettled(i) end
    if kind == "farm" then return g.level() > step[S_LEVEL] + 1 or self:MovedOn(i) end -- optional: done once you move on
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

-- A flight, hearthstone or set-home step (user, 2026-11-14: like RestedXP, which flies and hearths to save
-- time): done once you're where it takes you, once you've moved on (a later pick-up or hand-in is done), and a
-- hearthstone on cooldown is passed by (walk instead).
local ARRIVED = 15 -- map %
function Model:ShortcutSettled(i)
    self.saved.shortcuts = self.saved.shortcuts or {}
    if self.saved.shortcuts[i] then return true end -- done once stays done, wherever you walk afterwards
    local done = self:ShortcutNow(i)
    if done then self.saved.shortcuts[i] = true end
    return done
end

-- You've moved past step i: a pick-up or hand-in among the next steps is done.
function Model:MovedOn(i)
    local g = self.game
    for j = i + 1, math.min(#self.steps, i + 8) do
        local s = self.steps[j]
        if (s[S_KIND] == "accept" or s[S_KIND] == "turnin") and (Done(g, s[S_QUEST]) or (s[S_KIND] == "accept" and InLog(g, s[S_QUEST]))) then
            return true
        end
    end
    return false
end

function Model:ShortcutNow(i)
    local step, g = self.steps[i], self.game
    local kind = step[S_KIND]
    if self:MovedOn(i) then return true end
    if kind == "home" then
        local home = g.hearth and g.hearth()
        return home ~= nil and home == step[S_ZONE]
    end
    if kind == "hearth" and g.hearth then
        local _, ready = g.hearth()
        if not ready then return true end
    end
    local dest = step[S_DEST]
    if type(dest) ~= "table" then return true end
    if g.position then
        local zone, x, y = g.position()
        if zone == dest[1] and x and math.abs(x - dest[2]) <= ARRIVED and math.abs(y - dest[3]) <= ARRIVED then return true end
    end
    return false
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

-- Where the guide starts looking: a part you picked in the Guides menu or with Best (user, 2026-11-13).
function Model:Start()
    local at = tonumber(self.saved.startAt)
    if not at or at < 1 or at > #self.steps then return 1 end
    return math.floor(at)
end

function Model:SetStart(i) self.saved.startAt = i end

-- The step that fits you best now: the first open step in the first part of the route whose levels
-- still give you experience (it ends at or above your level), going by what you have done. With all
-- of those done, where the guide would be from the start.
function Model:Recommended()
    local level, keep = self.game.level(), self.saved.startAt
    self.saved.startAt = nil
    local pick
    for _, sec in ipairs(self:Sections()) do
        if (sec["to"] or 0) >= level then
            for i = sec.first, #self.steps do
                if not self:Wide(i) and not self:Settled(i) and self.steps[i][S_KIND] ~= "flight" then pick = i; break end
            end
            if pick then break end
        end
    end
    local result = pick or self:Current()
    self.saved.startAt = keep
    return result
end

function Model:Current()
    -- A flight path is asked for while you are in its part of the route; one behind you doesn't send you back.
    local first, flights, start = nil, {}, self:Start()
    for i = start, #self.steps do
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
    for i = start, limit - 1 do
        if self:Wide(i) and not self:Settled(i) and self:Deadline(i) <= limit then return i end -- must be done now
    end
    return self:Nearest(first)
end

-- Of the objectives of quests in your log in this part of the route, the one nearest to you (user, 2026-11-13:
-- the route's order sent him back to town before a target next to him). Only when the current step is itself
-- such an objective, you stand in its zone, and the game tells where you are.
function Model:Nearest(first)
    local g = self.game
    if not (first and g.position) or self.steps[first][S_KIND] ~= "do" then return first end
    local zone, px, py = g.position()
    if not (zone and px) or self.steps[first][S_ZONE] ~= zone then return first end
    local section = self:SectionOf(first)
    local best, bestD = first, nil
    for i = first, #self.steps do
        local step = self.steps[i]
        if self:SectionOf(i) ~= section then break end
        if step[S_KIND] == "do" and step[S_ZONE] == zone and step[S_X] and g.inLog(step[S_QUEST])
            and not self:Wide(i) and not self:Settled(i) then
            local d = (step[S_X] - px) ^ 2 + (step[S_Y] - py) ^ 2
            if not bestD or d < bestD then best, bestD = i, d end
        end
    end
    return best
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
    -- The current step first (it may be a nearer objective than the route's next), then the rest in order.
    out[1] = current
    Take(assume, self.steps[current])
    for i = 1, #self.steps do
        if #out >= n then break end
        if i == current then
            -- already first
        elseif i < self:Start() then
            -- before the part you chose to start from
        elseif i < current and not self:Wide(i) and (self.steps[i][S_KIND] == "flight" or self:Settled(i)) then
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

-- Who you talk to for a pick-up or turn-in step (nil for other steps and item-started quests).
function Model:TalkTo(i)
    local step = self.steps[i]
    local q = step and self:Quest(step[S_QUEST])
    if not q then return nil end
    if step[S_KIND] == "accept" and type(q[DROP]) ~= "table" then return q[GIVER] end
    if step[S_KIND] == "turnin" then return q[TURNIN] end
    return nil
end

-- Two steps you can do as one: talking to the same NPC (hand in, pick up: one step per place, user
-- 2026-11-14), the same monsters (kill or drop), or objectives at the same spot.
function Model:Together(i, j)
    local ti, tj = self:TalkTo(i), self:TalkTo(j)
    if ti or tj then
        return ti ~= nil and ti == tj and self.steps[i][S_ZONE] == self.steps[j][S_ZONE]
    end
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
            if not open then states[i] = "done"
            elseif self:Wide(i) then states[i] = "along"
            elseif self.steps[i][S_KIND] == "flight" then states[i] = "passed" -- a flight path behind you
            else states[i] = "open" end -- an objective left for later: you went to a nearer one first
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

local CITIES = { Orgrimmar = true, ["Thunder Bluff"] = true, Undercity = true }

-- The route by zone, for the Guides menu: one part per stay in a zone, "11-14 The Barrens"
-- (user, 2026-11-13: 10-level brackets were too big). City visits fold into the part before them,
-- and back-to-back parts in the same zone merge. { {from, to, zone, first = first section, title} }
function Model:ZoneParts()
    local out = {}
    for k, sec in ipairs(self:Sections()) do
        local p = out[#out]
        if p and (CITIES[sec.zone] or p.zone == sec.zone) then
            p["to"] = math.max(p["to"], sec["to"])
        else
            out[#out + 1] = { ["from"] = sec["from"], ["to"] = sec["to"], zone = sec.zone, first = k }
        end
    end
    for _, p in ipairs(out) do p.title = Guide.SectionTitle(p) end
    return out
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
    -- Swords to kill, a bag to loot, a gear to use (like Questie). Centered game icons, not the mouse cursors: the cursor
    -- art sits in a corner of its square, so it never lined up with the text (user, 2026-11-14).
    kill = "Interface\\Icons\\Ability_DualWield", loot = "Interface\\Icons\\INV_Misc_Bag_10",
    use = "Interface\\Icons\\INV_Misc_Gear_01", explore = "Interface\\Icons\\INV_Misc_Map_01",
    travel = "Interface\\Icons\\Ability_Rogue_Sprint", grind = "Interface\\Icons\\Ability_DualWield",
    flight = "Interface\\Icons\\Ability_Mount_Wyvern_01",
    hearth = "Interface\\Icons\\INV_Misc_Rune_01", home = "Interface\\Icons\\INV_Misc_Rune_01",
}
Guide.ICONS = ICONS

-- An icon inside a line of text: as tall as the text and centred on it; game icons are cropped to their art.
function Guide.Inline(path)
    if not path then return "" end
    if string.find(path, "\\Icons\\", 1, true) then return "|T" .. path .. ":0:0:0:0:64:64:5:59:5:59|t" end
    return "|T" .. path .. ":0|t"
end
local function Quest(text) return "|cffffd100" .. text .. "|r" end
local function Npc(text) return "|cff40ff40" .. text .. "|r" end
local function Thing(text) return "|cffff8040" .. text .. "|r" end

-- ---- Tips (user, 2026-11-14: one short line on what to expect, from the data) ----
function Guide.Tip(model, i)
    local step = model.steps[i]
    if not step then return nil end
    local kind = step[S_KIND]
    if kind == "do" then
        local g = model:Goal(i)
        if not g then return nil end
        local parts = {}
        local lo, hi = tonumber(g[G_LMIN]) or 0, tonumber(g[G_LMAX]) or 0
        if lo > 0 then parts[#parts + 1] = lo == hi and ("level " .. lo) or string.format("level %d-%d", lo, hi) end
        if g[G_ELITE] == 1 then parts[#parts + 1] = "elite: bring friends" end
        if g[G_KIND] == "collect" and g[G_SOURCE] and g[G_SOURCE] ~= "" and (g[G_COUNT] or 0) > 1 then
            parts[#parts + 1] = string.format("about %d kills", g[G_COUNT])
        end
        local loop = model:Loop(i)
        if loop then parts[#parts + 1] = string.format("circle the %d spots on your map", #loop) end
        if g[G_INSTANCE] and g[G_INSTANCE] ~= 0 then
            local dungeon = model.data.extras and model.data.extras.dungeonOf and model.data.extras.dungeonOf[step[S_QUEST]]
            parts[#parts + 1] = "inside " .. (dungeon or "the dungeon") .. ": bring a group"
        end
        if g[G_GUESSED] == 1 then parts[#parts + 1] = "its place isn't in the data: read the quest text" end
        if g[G_WIDE] == 1 then parts[#parts + 1] = "they're all over the zone: kill them as you go" end
        if #parts == 0 then return nil end
        local text = table.concat(parts, ", ")
        return string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
    elseif kind == "flight" then
        return "Talk to the flight master once, so you can fly here later"
    elseif kind == "fly" then
        return "Faster than walking there"
    elseif kind == "hearth" then
        return "Saves the walk back; on cooldown, just walk"
    elseif kind == "farm" then
        return "Gold, not experience: stay as long as you like, then tick it or just move on"
    elseif kind == "home" then
        return "You'll come back here: the hearthstone brings you"
    elseif kind == "accept" then
        local q = model:Quest(step[S_QUEST])
        if q and q[LEVEL] and q[LEVEL] >= model.game.level() + 3 then
            return string.format("Level %d quest: hard for you now", q[LEVEL])
        end
    end
    return nil
end

-- The spots to circle for a kill or loot step ({{x, y}...}), or nil.
function Model:Loop(i)
    local g = self:Goal(i)
    local loop = g and g[G_LOOP]
    if type(loop) == "table" and #loop >= 2 then return loop end
    return nil
end

local LOOP_NEAR = 3 -- map %: this close to a loop spot, the arrow moves on to the next one
-- The loop spot to head for: k (1-based) until you reach it, then the next one (round and round).
function Guide.NextLoopSpot(loop, k, x, y)
    k = (k and k >= 1 and k <= #loop) and k or 1
    local spot = loop[k]
    if x and spot and math.abs(spot[1] - x) <= LOOP_NEAR and math.abs(spot[2] - y) <= LOOP_NEAR then
        k = k % #loop + 1
    end
    return k
end

-- Experience a same-level monster gives (Classic: level x 5 + 45) and the kills to fill `left` experience.
function Guide.KillsFor(level, left)
    if not (level and left) or left <= 0 then return 0 end
    return math.ceil(left / (level * 5 + 45))
end

-- A part of the route planned for a higher level than yours: "planned for level N" with the kills it takes
-- (user, 2026-11-14: level checkpoints). nil when you're on track.
function Model:Checkpoint(i)
    local step, g = self.steps[i], self.game
    if not step or step[S_KIND] == "grind" then return nil end
    local level, planned = g.level(), step[S_LEVEL] or 0
    if planned <= level + 1 then return nil end
    local cur, max = 0, 0
    if g.xp then cur, max = g.xp() end
    local left = (max or 0) - (cur or 0)
    for l = level + 1, planned - 2 do left = left + (l * 100 + 300) end -- rough: the levels after this one
    return { level = planned - 1, kills = Guide.KillsFor(level, left) }
end

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
        -- The game's line for this objective: its count goes into the action ("Loot Notched Rib 3/5 from ..."),
        -- not a second line that repeats the name (user, 2026-11-13). Green when done.
        local count = ""
        if objectives then
            local own
            for k, o in ipairs(objectives) do
                if goal and o.text and string.find(o.text, goal[G_NAME], 1, true) then own = k end
            end
            own = own or (objectives[index] and index)
            for k, o in ipairs(objectives) do
                if not own or k == own then
                    local have, need = string.match(o.text or "", "(%d+)%s*/%s*(%d+)")
                    if own and have then
                        count = string.format(o.finished and " |cff40ff40%s/%s|r" or " |cffffffff%s/%s|r", have, need)
                    else
                        d.lines[#d.lines + 1] = { text = o.text, finished = o.finished and true or false }
                    end
                end
            end
        end
        if goalKind == "collect" then
            d.kind = "loot"
            local from = goal[G_SOURCE] and goal[G_SOURCE] ~= "" and (" from " .. Thing(goal[G_SOURCE])) or ""
            d.action = string.format("Loot %s%s%s", Thing(goal[G_NAME]), count, from)
        elseif goalKind == "use" then
            d.kind = "use"
            d.action = "Use " .. Thing(goal[G_NAME]) .. count
        elseif goalKind == "explore" then
            d.kind = "explore"
            d.action = "Explore the marked area" .. count
        else
            d.kind = "kill"
            if goal then
                d.action = count ~= "" and ("Kill " .. Thing(goal[G_NAME]) .. count) or string.format("Kill %d %s", goal[G_COUNT], Thing(goal[G_NAME]))
            else
                d.action = (step[S_TEXT] or "") .. count
            end
        end
        d.quest = q[TITLE] -- shown in the block's header
        if goal and goal[G_WIDE] == 1 then d.wide = true end
    elseif kind == "travel" then
        d.action = "Go to " .. Npc(step[S_ZONE])
    elseif kind == "flight" then
        local who = string.match(step[S_TEXT] or "", "from (.+)$") or "the flight master"
        d.action = string.format("Talk to %s: get the flight path", Npc(who))
    elseif kind == "fly" then
        local from, to = string.match(step[S_TEXT] or "", "^Fly from (.+) to (.+)$")
        d.kind = "flight"
        d.action = string.format("Talk to %s: fly to %s", Npc(from or "the flight master"), Npc(to or "?"))
    elseif kind == "hearth" then
        local dest = step[S_DEST]
        d.kind, d.useItem, d.useLabel = "hearth", 6948, "Hearthstone"
        d.action = "Use your Hearthstone" .. (type(dest) == "table" and (": back to " .. Npc(dest[1])) or "")
    elseif kind == "farm" then
        local g = model.game
        local pick, value = Guide.FarmPick(step[S_FARM], g.price)
        d.kind, d.farm = "loot", pick
        if pick then
            local item = g.itemName and g.itemName(pick[1]) or "loot"
            local worth = value > 0 and g.money and string.format(" |cffaaaaaa(about %s a kill at auction prices)|r", g.money(math.floor(value))) or ""
            d.action = string.format("Optional: farm %s from %s%s", Thing(item), Thing(pick[2]), worth)
        else
            d.action = "Optional: farm here for gold"
        end
    elseif kind == "home" then
        local who = string.match(step[S_TEXT] or "", "at (.+)$") or "the innkeeper"
        d.kind = "home"
        d.action = string.format("Talk to %s: make this inn your home", Npc(who))
    else
        d.action = step[S_TEXT]
    end
    if kind == "grind" and model.game.xp then
        local cur, max = model.game.xp()
        local target = tonumber(string.match(step[S_TEXT] or "", "level (%d+)")) or step[S_LEVEL]
        if cur and max and max > 0 then
            d.action = string.format("Grind here to level %d |cffaaaaaa(%d%% into %d, about %d kills to go)|r", target,
                math.floor(cur / max * 100), model.game.level(), Guide.KillsFor(model.game.level(), max - cur))
        end
    end
    d.tip = Guide.Tip(model, i)
    local check = Model.Checkpoint(model, i)
    if check then
        d.checkpoint = string.format("Planned for level %d+: kill monsters on the way (about %d kills)", check.level, check.kills)
    end
    d.icon = ICONS[d.kind] or ICONS.kill
    return d
end

-- ---- Leveling tracker (user, 2026-11-14): experience per hour, time to the next level, time per level ----
-- saved = { level, cur, active (seconds played this level), times = { [level] = seconds }, gained, played }.
-- Update(saved, now, level, cur, max) on every experience change; gaps over IDLE seconds (away, logged out)
-- don't count as playing time.
local IDLE = 300
Guide.TRACK_IDLE = IDLE

function Guide.TrackXP(saved, now, level, cur, max)
    saved.times = saved.times or {}
    local dt = saved.at and (now - saved.at) or 0
    if dt < 0 or dt > IDLE then dt = 0 end
    saved.at = now
    if saved.level then
        local gained
        if level > saved.level then
            gained = math.max(0, (saved.max or 0) - (saved.cur or 0)) + cur
            saved.times[saved.level] = math.floor((saved.active or 0) + dt + 0.5)
            saved.active = 0
        else
            gained = math.max(0, cur - (saved.cur or 0))
            saved.active = (saved.active or 0) + dt
        end
        saved.gained, saved.played = (saved.gained or 0) + gained, (saved.played or 0) + dt
    end
    saved.level, saved.cur, saved.max = level, cur, max
end

-- { perHour, toLevel (seconds), lastLevel = {level, seconds} } from what was tracked (nil parts when unknown).
function Guide.TrackSummary(saved)
    local out = {}
    if (saved.played or 0) >= 60 and (saved.gained or 0) > 0 then
        out.perHour = math.floor(saved.gained / saved.played * 3600 + 0.5)
        local left = (saved.max or 0) - (saved.cur or 0)
        if left > 0 then out.toLevel = math.floor(left / saved.gained * saved.played + 0.5) end
    end
    local last = saved.level and saved.times and saved.times[saved.level - 1]
    if last then out.lastLevel = { level = saved.level - 1, seconds = last } end
    return out
end

function Guide.Duration(seconds)
    seconds = math.floor(seconds or 0)
    if seconds >= 3600 then return string.format("%dh %02dm", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)) end
    return string.format("%dm", math.max(1, math.floor(seconds / 60 + 0.5)))
end

-- ---- Gold farming (explorer style, user 2026-11-14) ----
-- candidates = { {item, monster, chance %, x, y} }; price(item) -> copper or nil. Returns the best one and its
-- value per kill (copper), or the first one with value 0 when no price is known.
function Guide.FarmPick(candidates, price)
    local best, bestValue
    for _, c in ipairs(candidates or {}) do
        local value = (price and price(c[1]) or 0) * (c[3] or 0) / 100
        if not bestValue or value > bestValue then best, bestValue = c, value end
    end
    return best, bestValue or 0
end

-- ---- Errands: training, hearthstone, repairs, class quests (user, 2026-11-14) ----
-- state = { zone, level, train = {count, cost, trainer = {name, zone, x, y}}, classQuest = {id, title, giver, zone, x, y},
--           homeZone, sectionZone, sectionLeft, inn = {name, zone, x, y}, freeSlots, durability (0-1),
--           repair = {name, zone, x, y}, skipped = {key = true} }
-- Returns { {key, kind, action, zone, x, y, tip} } in the order to do them; only errands in your zone.
local ERRAND_ICONS = { repair = "Interface\\Icons\\Trade_BlackSmithing", train = "Interface\\Icons\\INV_Misc_Book_09",
    home = "Interface\\Icons\\INV_Misc_Rune_01", food = "Interface\\Icons\\INV_Misc_Food_15", classquest = "Interface\\GossipFrame\\AvailableQuestIcon" }
Guide.ERRAND_ICONS = ERRAND_ICONS
Guide.FOOD_MIN = 5 -- fewer than this many to eat (or drink, for mana users) and an innkeeper is near: buy some
Guide.HOME_MIN_STEPS = 12 -- a part of the route with at least this many steps left is worth setting your hearthstone in

function Guide.Errands(state)
    local out, skipped = {}, state.skipped or {}
    local function add(e) if not skipped[e.key] then e.icon = ERRAND_ICONS[e.kind]; out[#out + 1] = e end end
    local r = state.repair
    if r and r.zone == state.zone and ((state.freeSlots and state.freeSlots <= 2) or (state.durability and state.durability <= 0.3)) then
        add({ key = "repair:" .. r.name, kind = "repair", zone = r.zone, x = r.x, y = r.y,
              action = "Sell junk and repair at " .. Npc(r.name), tip = "Your bags are full or your gear is worn" })
    end
    local t = state.train
    if t and (t.count or 0) > 0 and t.trainer and t.trainer.zone == state.zone then
        add({ key = "train:" .. (state.level or 0), kind = "train", zone = t.trainer.zone, x = t.trainer.x, y = t.trainer.y,
              action = string.format("Train %d new spell%s at %s", t.count, t.count == 1 and "" or "s", Npc(t.trainer.name)),
              tip = t.cost and ("Costs " .. t.cost) or nil })
    end
    local food, innHere = state.food, state.innHere
    if food and innHere and innHere.zone == state.zone then
        local lowFood, lowDrink = (food.food or 0) < Guide.FOOD_MIN, food.mana and (food.drink or 0) < Guide.FOOD_MIN
        if lowFood or lowDrink then
            local what = lowFood and lowDrink and "food and water" or (lowFood and "food" or "water")
            add({ key = "food:" .. innHere.name .. ":" .. (state.level or 0), kind = "food", zone = innHere.zone, x = innHere.x, y = innHere.y,
                  action = string.format("Buy %s at %s", what, Npc(innHere.name)), tip = "You're running low: the innkeeper sells some for your level" })
        end
    end
    local inn = state.inn
    if inn and inn.zone == state.sectionZone and state.homeZone ~= state.sectionZone and (state.sectionLeft or 0) >= Guide.HOME_MIN_STEPS then
        add({ key = "home:" .. inn.zone, kind = "home", zone = inn.zone, x = inn.x, y = inn.y,
              action = "Set your Hearthstone at " .. Npc(inn.name), tip = "You'll come back here: the Hearthstone saves the walk" })
    end
    local cq = state.classQuest
    if cq and cq.zone == state.zone then
        add({ key = "cq:" .. cq.id, kind = "classquest", zone = cq.zone, x = cq.x, y = cq.y,
              action = string.format("Talk to %s: accept %s", Npc(cq.giver or "?"), Quest(cq.title or "?")), tip = "Class quest" })
    end
    return out
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
    if self.game.hearth then
        local home, ready = self.game.hearth()
        if ready and home == target then
            return { Leg("Use your Hearthstone: it takes you to " .. home, nil, nil, nil) }
        end
    end
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

-- ---- Auto flight (user, 2026-11-14) ----
-- The flight master to fly to for step i: the one you have nearest the step, in its zone; nil when the step is
-- in the zone you're in or no flight path you have is there.
function Model:FlightTo(i)
    local travel, step, g = self.data.travel, self.steps[i], self.game
    if not (travel and step) then return nil end
    local target = step[S_ZONE]
    if target == g.zone() then return nil end
    local known = {}
    for _, f in ipairs(FlightsIn(travel, target)) do
        if not g.flightKnown or g.flightKnown(f[2], f[3], f[4]) then known[#known + 1] = f end
    end
    return Near(known, step[S_X], step[S_Y])
end

-- Which node of the flight map: nodes = { {index, name ("Crossroads, The Barrens"), type, dist (to the flight
-- master, if known)} }. A reachable node in the flight master's zone; with several, the nearest. nil if unsure.
function Guide.PickTaxiNode(nodes, zone)
    local options = {}
    for _, n in ipairs(nodes) do
        local place, region = string.match(n.name or "", "^(.-),%s*(.+)$")
        if n.type == "REACHABLE" and (region == zone or place == zone or n.name == zone) then options[#options + 1] = n end
    end
    if #options == 1 then return options[1].index end
    local best
    for _, n in ipairs(options) do
        if not n.dist then return nil end
        if not best or n.dist < best.dist then best = n end
    end
    return best and best.index or nil
end

-- A step at one specific place (an NPC, a flight master, an object, one named monster, an item lying in one
-- spot): the guide pins it and points the arrow there. Killing or looting across an area, or grinding, has no
-- single spot, so no pin (user, 2026-11-13: one pin for an area to kill in was confusing).
function Model:Pinpoint(i)
    local step = self.steps[i]
    if not step then return false end
    local kind = step[S_KIND]
    if kind == "accept" or kind == "turnin" or kind == "flight" or kind == "travel" or kind == "fly" or kind == "home" or kind == "farm" then return true end
    if kind ~= "do" then return false end
    local goal = self:Goal(i)
    if not goal then return false end
    local gk = goal[G_KIND]
    if goal[G_GUESSED] == 1 then return false end -- no real place to point at
    if gk == "use" or gk == "explore" then return true end
    if (gk == "kill" or gk == "collect") and self:Loop(i) then return true end -- the arrow circles the loop
    if gk == "kill" then return (goal[G_COUNT] or 0) <= 1 end
    if gk == "collect" then return goal[G_SOURCE] == nil or goal[G_SOURCE] == "" or (goal[G_COUNT] or 0) <= 1 end -- one drop from one monster
    return false
end

-- Where a step is: zone, x, y and the map ID for a pin.
function Model:Place(i)
    local step = self.steps[i]
    if not step then return nil end
    return step[S_ZONE], step[S_X], step[S_Y], self.data.uiMaps[step[S_ZONE]]
end
