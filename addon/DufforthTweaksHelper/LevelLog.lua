-- Leveling log (user, 2026-11-27: "can you create a logs of the quest and what im doing in game to analyze and improve
-- the guide"). Saves what you do while leveling, per character, so tools/analyze_leveling_log.py can show where the
-- guide loses time. Never prints to chat; nothing here acts in the game.
--
-- DufforthTweaksHelperDB.levelLog = { on (nil = on), chars[UnitGUID] = { who = "Orc WARRIOR", names = {...},
--   quests = { [id] = title }, rows = {...} } }
-- A row is one line: at;kind;level;xp;zone;x;y;route;part;number;line;extra
--   zone, route and part are indexes into names; number and line are the guide step (RestedXP's step number in its
--   part and the step's line); extra is "key=value,key=value".
-- Kinds: lg login, lo logout, qa accepted (q, g = in the guide), qp objective (q, o, n = have/need), qc completed,
--   qt turned in (q, x = xp, g), qx abandoned, lv level up, xs XP since the last summary (k kills, q quests,
--   r rested used), hs hearthstone, hb hearth bound, fs flight start, fl landed (s), dd died, rz alive again
--   (s, c = was a ghost: corpse run), vn vendor (npc, s), tr trainer (npc, s), in resting (inn or city), zc zone change,
--   gd step done (f = line before; pz, px, py = the new step's point), gs skipped by hand, gb back, gj jumped (list or
--   Guides menu), gp part change, ia idle start (at = the last thing you did), ie idle end (s), ak AFK (on / s), ps place.

local LL = {}
DufforthTweaksHelperLevelLog = LL

LL.MAX = 5000          -- rows per character (user's pick, 2026-11-27); the oldest go first
LL.TRIM = 250          -- dropped at once when full, so a full log isn't shifted on every row
LL.IDLE_AFTER = 120    -- seconds without moving, XP or anything logged
LL.SAMPLE_EVERY = 60   -- a place row at most this often while you move
LL.SAMPLE_MOVE = 1     -- map % moved since the last place row
LL.XP_WAIT = 1         -- seconds an XP gain waits for its quest turn-in before it counts as kill XP
LL.SUMMARY_EVERY = 300 -- an XP summary row at least this often
LL.HEARTH = 8690

local function Plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function Call(f, ...)
    if not f then return nil end
    local ok, a, b = pcall(f, ...)
    if not ok then return nil end
    return Plain(a), Plain(b)
end

-- ---- the game, behind one adapter (tests replace it) ----
local function Zone()
    local loc = DufforthTweaksHelperLocale
    local z = loc and loc.ZoneName and Call(loc.ZoneName)
    return z or Call(GetRealZoneText) or "?"
end

local function Pos()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local map = Call(C_Map.GetBestMapForUnit, "player")
    local p = map and Call(C_Map.GetPlayerMapPosition, map, "player")
    if not p then return nil end
    local ok, x, y = pcall(p.GetXY, p)
    if not ok or not Plain(x) or not Plain(y) then return nil end
    return x * 100, y * 100
end

local function Objectives(id)
    if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return nil end
    local list = Call(C_QuestLog.GetQuestObjectives, id)
    if type(list) ~= "table" then return nil end
    local out = {}
    for i, o in ipairs(list) do out[i] = { Plain(o.numFulfilled) or (o.finished and 1 or 0), Plain(o.numRequired) or 1 } end
    return out
end

local function LogIds()
    local out = {}
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, Call(C_QuestLog.GetNumQuestLogEntries) or 0 do
            local info = Call(C_QuestLog.GetInfo, i)
            if type(info) == "table" and not info.isHeader and Plain(info.questID) then out[#out + 1] = info.questID end
        end
    end
    return out
end

local function NpcId()
    local guid = Call(UnitGUID, "npc")
    return guid and tonumber(string.match(guid, "^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)")) or nil
end

local function InGuide(id)
    local q = DufforthTweaksHelperQuestAuto
    if not (q and q.InGuide) then return false end
    return (Call(q.InGuide, id, "accept") or Call(q.InGuide, id, "turnin")) and true or false
end

local function Title(id)
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then return Call(C_QuestLog.GetTitleForQuestID, id) end
end

local function Who()
    local race
    if UnitRace then local ok, _, token = pcall(UnitRace, "player"); race = ok and token or nil end
    local class
    if UnitClass then class = select(2, UnitClass("player")) end
    return tostring(Plain(race) or "?") .. " " .. tostring(Plain(class) or "?")
end

LL.game = {
    now = function() return (time and time()) or 0 end,
    level = function() return Call(UnitLevel, "player") end,
    xp = function() return Call(UnitXP, "player") end,
    xpMax = function() return Call(UnitXPMax, "player") end,
    rested = function() return Call(GetXPExhaustion) or 0 end,
    zone = Zone, pos = Pos, objectives = Objectives, logIds = LogIds, npc = NpcId, inGuide = InGuide, title = Title, who = Who,
    afk = function() return Call(UnitIsAFK, "player") and true or false end,
    combat = function() return (Call(InCombatLockdown) or Call(UnitAffectingCombat, "player")) and true or false end,
    taxi = function() return Call(UnitOnTaxi, "player") and true or false end,
    dead = function() return Call(UnitIsDead, "player") and true or false end,
    ghost = function() return Call(UnitIsGhost, "player") and true or false end,
    resting = function() return Call(IsResting) and true or false end,
}

local function G(name, ...)
    local f = LL.game[name]
    if not f then return nil end
    local ok, a, b = pcall(f, ...)
    if not ok then return nil end
    return a, b
end

-- ---- storage ----
function LL.Options()
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    local o = DufforthTweaksHelperDB.levelLog or {}
    DufforthTweaksHelperDB.levelLog = o
    o.chars = o.chars or {}
    return o
end

local function CharKey()
    local guid = Call(UnitGUID, "player")
    return (guid and guid ~= "") and guid or "?"
end

function LL.Char()
    local chars = LL.Options().chars
    local key = CharKey()
    local c = chars[key] or {}
    chars[key] = c
    c.names, c.quests, c.rows = c.names or {}, c.quests or {}, c.rows or {}
    c.who = c.who or G("who")
    return c
end

local nameIndex = {} -- per character: name -> index
local function Name(c, name)
    if not name or name == "" then return 0 end
    local key = tostring(c)
    local idx = nameIndex[key]
    if not idx then
        idx = {}
        for i, n in ipairs(c.names) do idx[n] = i end
        nameIndex[key] = idx
    end
    if not idx[name] then
        c.names[#c.names + 1] = name
        idx[name] = #c.names
    end
    return idx[name]
end

local function Num(v) return (type(v) == "number") and v or nil end
local function Coord(v) return v and string.format("%.1f", v) or "" end

-- The guide's place right now: route, part, step number, line, and the step's first point.
function LL.Guide()
    local ui = DufforthTweaksHelperGuideUI
    local model = ui and ui.model
    if not (model and model.rxp and model.RxState) then return nil end
    local ok, out = pcall(function()
        local at = model:RxState().at or 1
        local rec = model:Rec(at)
        if not rec then return nil end
        local pt = rec.pt and rec.pt[1]
        return { at = at, route = model.routeName, part = model:RxPartName(rec.p), partIndex = rec.p, number = model:RxNumber(at),
                 line = rec.ln, pz = pt and pt[1], px = pt and Num(pt[2]), py = pt and Num(pt[3]) }
    end)
    return ok and out or nil
end

local state = { quests = {}, pendingXP = {}, removed = {}, turned = {}, acc = { k = 0, q = 0, r = 0 }, owed = 0 }
LL.state = state

local function Extra(t)
    if not t then return "" end
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do
        local v = t[k]
        if v ~= nil then out[#out + 1] = k .. "=" .. string.gsub(tostring(v), "[,;=]", " ") end
    end
    return table.concat(out, ",")
end

-- One row. `at` overrides the time (an idle row is dated when the idle began).
function LL.Add(kind, extra, at)
    local o = LL.Options()
    if o.on == false then return end
    local c = LL.Char()
    local now = at or G("now") or 0
    local x, y = G("pos")
    local guide = LL.Guide() or {}
    local row = table.concat({ tostring(math.floor(now)), kind, tostring(G("level") or 0), tostring(G("xp") or 0),
        tostring(Name(c, G("zone"))), Coord(Num(x)), Coord(Num(y)), tostring(Name(c, guide.route)),
        tostring(Name(c, guide.part)), tostring(guide.number or ""), tostring(guide.line or ""), Extra(extra) }, ";")
    local rows = c.rows
    rows[#rows + 1] = row
    if #rows > LL.MAX then
        local keep, start = {}, #rows - (LL.MAX - LL.TRIM) + 1
        for i = start, #rows do keep[#keep + 1] = rows[i] end
        c.rows = keep
    end
    if not at then state.activeAt = now end
end

function LL.Count() return #LL.Char().rows end

function LL.Clear()
    local c = LL.Char()
    c.rows = {}
    nameIndex[tostring(c)] = nil
    c.names, c.quests = {}, {}
end

-- For the Menu view: rows kept, the cap, time covered, deaths, skips and off-guide quests.
function LL.Summary()
    local c = LL.Char()
    local out = { rows = #c.rows, max = LL.MAX, deaths = 0, skips = 0, offGuide = 0, seconds = 0 }
    local first, last
    for _, r in ipairs(c.rows) do
        local at, kind = string.match(r, "^(%d+);(%a+);")
        at = tonumber(at)
        if at then first = first or at; last = at end
        if kind == "dd" then out.deaths = out.deaths + 1
        elseif kind == "gs" then out.skips = out.skips + 1
        elseif kind == "qa" and string.find(r, "g=0", 1, true) then out.offGuide = out.offGuide + 1 end
    end
    if first and last then out.seconds = last - first end
    return out
end

-- ---- XP: kill vs quest, rested used ----
local function FlushXP(force)
    local now = G("now") or 0
    local keep = {}
    for _, p in ipairs(state.pendingXP) do
        if force or now - p.at >= LL.XP_WAIT then
            local take = math.min(p.gain, state.owed)
            state.owed = state.owed - take
            state.acc.q = state.acc.q + take
            state.acc.k = state.acc.k + (p.gain - take)
        else
            keep[#keep + 1] = p
        end
    end
    state.pendingXP = keep
    if state.owedAt and now - state.owedAt > 5 then state.owed, state.owedAt = 0, nil end
end

local function Summary(force)
    FlushXP(true)
    local a = state.acc
    if a.k == 0 and a.q == 0 and a.r == 0 then return end
    local now = G("now") or 0
    if not force and state.summaryAt and now - state.summaryAt < LL.SUMMARY_EVERY then return end
    LL.Add("xs", { k = a.k, q = a.q, r = a.r })
    state.acc = { k = 0, q = 0, r = 0 }
    state.summaryAt = now
end
LL.FlushSummary = Summary

local function XPUpdate()
    local xp, level, max, rested = G("xp"), G("level"), G("xpMax"), G("rested") or 0
    if not (xp and level) then return end
    local gain = 0
    if state.xp and state.level then
        if level > state.level then gain = math.max(0, (state.xpMax or 0) - state.xp) + xp
        elseif level == state.level then gain = xp - state.xp end
    end
    if state.rested and rested < state.rested and gain > 0 then
        state.acc.r = state.acc.r + math.min(state.rested - rested, gain)
    end
    if gain > 0 then
        state.pendingXP[#state.pendingXP + 1] = { at = G("now") or 0, gain = gain }
        state.activeAt = G("now")
    end
    state.xp, state.level, state.xpMax, state.rested = xp, level, max, rested
end

-- ---- quests ----
local function Snapshot(id)
    local list = G("objectives", id) or {}
    local done = #list > 0
    for _, o in ipairs(list) do if (o[1] or 0) < (o[2] or 1) then done = false end end
    state.quests[id] = { list = list, done = done }
end

local function ScanQuests()
    state.dirty = nil
    local ids = G("logIds") or {}
    for _, id in ipairs(ids) do
        local before = state.quests[id]
        if not before then Snapshot(id) else
            local list = G("objectives", id) or {}
            local done = #list > 0
            for i, o in ipairs(list) do
                local have, need = o[1] or 0, o[2] or 1
                local was = before.list[i] and before.list[i][1] or 0
                if have > was then LL.Add("qp", { q = id, o = i, n = have .. "/" .. need }) end
                if have < need then done = false end
            end
            if done and not before.done then LL.Add("qc", { q = id }) end
            state.quests[id] = { list = list, done = done }
        end
    end
end

local function QuestId(a, b)
    if type(b) == "number" and b > 0 then return b end
    if type(a) == "number" and a > 0 then return a end
end

local function Remember(id)
    local c = LL.Char()
    if not c.quests[id] then c.quests[id] = G("title", id) end
end

-- ---- the guide's moves ----
local pendingMove -- "gs" / "gb" / "gj", set by the wrapped Skip / Back / RxGoTo
local function Wrap()
    local rx = DufforthTweaksHelperGuide and DufforthTweaksHelperGuide.Rx
    if not rx or rx.dthLogWrapped then return end
    rx.dthLogWrapped = true
    for name, kind in pairs({ Skip = "gs", Back = "gb", RxGoTo = "gj" }) do
        local orig = rx[name]
        if orig then
            rx[name] = function(...)
                pendingMove = pendingMove or kind
                return orig(...)
            end
        end
    end
end
Wrap()

local function GuideMoved()
    local guide = LL.Guide()
    if not guide then return end
    local last = state.guide
    state.guide = guide
    if not last or last.route ~= guide.route then pendingMove = nil; return end
    if last.at == guide.at then pendingMove = nil; return end
    local kind = pendingMove or (guide.partIndex ~= last.partIndex and "gp") or (guide.at > last.at and "gd") or "gj"
    pendingMove = nil
    Summary(true)
    local c = LL.Char()
    LL.Add(kind, { f = last.line, pz = guide.pz and Name(c, guide.pz) or nil, px = guide.px and Coord(guide.px) or nil,
        py = guide.py and Coord(guide.py) or nil })
    if kind ~= "gp" and guide.partIndex ~= last.partIndex then LL.Add("gp", { f = last.line }) end
end

-- ---- once a second: deferred work, flights, idle, places ----
local function Distance(ax, ay, bx, by)
    if not (ax and ay and bx and by) then return 0 end
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

function LL.Tick()
    if LL.Options().on == false then return end
    local now = G("now") or 0
    if state.dirty then ScanQuests() end
    FlushXP(false)
    -- Quests removed a second ago and never turned in: abandoned.
    for id, at in pairs(state.removed) do
        if now - at >= 1 then
            state.removed[id] = nil
            if not state.turned[id] then LL.Add("qx", { q = id }) end
            state.quests[id] = nil
        end
    end
    GuideMoved()
    -- Flights.
    local taxi = G("taxi")
    if taxi and not state.taxiAt then state.taxiAt = now; LL.Add("fs")
    elseif not taxi and state.taxiAt then LL.Add("fl", { s = now - state.taxiAt }); state.taxiAt = nil end
    if G("ghost") then state.wasGhost = true end
    -- Moving, idle, places.
    local x, y = G("pos")
    local moved = state.x and Distance(x, y, state.x, state.y) > 0.05
    state.x, state.y = x, y
    if moved then state.activeAt = now end
    state.activeAt = state.activeAt or now
    if state.idleFrom then
        if moved or G("combat") then LL.Add("ie", { s = now - state.idleFrom }); state.idleFrom = nil end
    elseif not taxi and not G("combat") and now - state.activeAt >= LL.IDLE_AFTER then
        state.idleFrom = state.activeAt
        LL.Add("ia", nil, state.idleFrom)
    end
    if not taxi and not state.idleFrom and x and (not state.sampleAt or now - state.sampleAt >= LL.SAMPLE_EVERY)
        and Distance(x, y, state.sx, state.sy) >= LL.SAMPLE_MOVE then
        state.sampleAt, state.sx, state.sy = now, x, y
        LL.Add("ps")
    end
    Summary(false)
end

-- ---- events ----
local open = {} -- vendor / trainer windows: when they opened

function LL.OnEvent(_, event, a, b, c)
    if LL.Options().on == false then return end
    local now = G("now") or 0
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        if state.loggedIn then return end
        state.loggedIn = true
        state.xp, state.level, state.xpMax, state.rested = G("xp"), G("level"), G("xpMax"), G("rested") or 0
        for _, id in ipairs(G("logIds") or {}) do Snapshot(id) end
        state.guide = LL.Guide()
        state.sx, state.sy = G("pos")
        state.sampleAt, state.summaryAt = now, now
        LL.Add("lg")
    elseif event == "PLAYER_LOGOUT" then
        Summary(true)
        LL.Add("lo")
    elseif event == "QUEST_ACCEPTED" then
        local id = QuestId(a, b)
        if not id then return end
        Snapshot(id)
        Remember(id)
        LL.Add("qa", { q = id, g = G("inGuide", id) and 1 or 0 })
    elseif event == "QUEST_TURNED_IN" then
        local id = QuestId(a)
        if not id then return end
        state.turned[id] = now
        local xp = Num(Plain(b)) or 0
        state.owed, state.owedAt = state.owed + xp, now
        Remember(id)
        LL.Add("qt", { q = id, x = xp, g = G("inGuide", id) and 1 or 0 })
        state.quests[id] = nil
    elseif event == "QUEST_REMOVED" then
        local id = QuestId(a)
        if id then state.removed[id] = now end
    elseif event == "QUEST_LOG_UPDATE" or event == "UNIT_QUEST_LOG_CHANGED" then
        state.dirty = true
    elseif event == "PLAYER_XP_UPDATE" then
        XPUpdate()
    elseif event == "PLAYER_LEVEL_UP" then
        XPUpdate()
        Summary(true)
        LL.Add("lv", { l = Num(Plain(a)) })
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if a == "player" and Plain(c) == LL.HEARTH then LL.Add("hs") end
    elseif event == "HEARTHSTONE_BOUND" then
        LL.Add("hb")
    elseif event == "PLAYER_DEAD" then
        state.deadAt, state.wasGhost = now, false
        LL.Add("dd")
    elseif event == "PLAYER_UNGHOST" or event == "PLAYER_ALIVE" then
        if state.deadAt and not G("dead") and not G("ghost") then
            LL.Add("rz", { s = now - state.deadAt, c = state.wasGhost and 1 or 0 })
            state.deadAt, state.wasGhost = nil, nil
        elseif G("ghost") then state.wasGhost = true end
    elseif event == "MERCHANT_SHOW" or event == "TRAINER_SHOW" then
        open[event] = { at = now, npc = G("npc") }
        state.activeAt = now
    elseif event == "MERCHANT_CLOSED" or event == "TRAINER_CLOSED" then
        local key = event == "MERCHANT_CLOSED" and "MERCHANT_SHOW" or "TRAINER_SHOW"
        local o = open[key]
        if o then
            open[key] = nil
            LL.Add(key == "MERCHANT_SHOW" and "vn" or "tr", { npc = o.npc, s = now - o.at })
        end
    elseif event == "PLAYER_UPDATE_RESTING" then
        local resting = G("resting")
        if resting and not state.resting then LL.Add("in") end
        state.resting = resting
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        Summary(true)
        LL.Add("zc")
    elseif event == "PLAYER_FLAGS_CHANGED" then
        if a and a ~= "player" then return end
        local afk = G("afk")
        if afk and not state.afkAt then state.afkAt = now; LL.Add("ak", { on = 1 })
        elseif not afk and state.afkAt then LL.Add("ak", { s = now - state.afkAt }); state.afkAt = nil end
    end
end

-- ---- wiring ----
local frame = CreateFrame and CreateFrame("Frame")
if frame then
    for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT", "QUEST_ACCEPTED", "QUEST_TURNED_IN",
        "QUEST_REMOVED", "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP",
        "UNIT_SPELLCAST_SUCCEEDED", "HEARTHSTONE_BOUND", "PLAYER_DEAD", "PLAYER_UNGHOST", "PLAYER_ALIVE", "MERCHANT_SHOW",
        "MERCHANT_CLOSED", "TRAINER_SHOW", "TRAINER_CLOSED", "PLAYER_UPDATE_RESTING", "ZONE_CHANGED_NEW_AREA",
        "PLAYER_FLAGS_CHANGED" }) do
        if frame.RegisterEvent then pcall(frame.RegisterEvent, frame, e) end
    end
    if frame.SetScript then
        frame:SetScript("OnEvent", function(...) pcall(LL.OnEvent, ...) end)
        local wait = 0
        frame:SetScript("OnUpdate", function(_, elapsed)
            wait = wait + (elapsed or 0)
            if wait < 1 then return end
            wait = 0
            pcall(LL.Tick)
        end)
    end
end
