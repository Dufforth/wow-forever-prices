-- Dufforth Tweaks Helper, leveling guide: RestedXP's step engine for RestedXP's routes (user, 2026-11-27: the guide
-- follows RestedXP "at 100%", including how it moves you through the steps). Pure, like Guide.lua: the game comes in
-- through the adapter. Rules as in RestedXP's own engine (RXPGuides, CC BY-NC-SA 4.0):
--   * one saved pointer that only moves forward (GuideWindow.lua SetStep / UpdateStepCompletion);
--   * side steps: #sticky and #completewith steps stay active next to the pointer's step until done, or until the
--     pointer passes their label; a step marked #requires waits while the step it needs is open;
--   * a step is done when every line of it is done; a skip condition (.isOnQuest, .xp <N,1, .zoneskip...) ends it;
--   * the arrow walks the active steps' points in order (functions.lua goto, map.lua updateArrowData), a ghost is
--     sent to the corpse, or to the nearest Spirit Healer on a death-skip step.
-- Route data (catalog/rxp_rows.py): rows as in Guide.lua plus [11] RestedXP step and [12] arg; route.rx = step
-- records { p part, t tag, lv level gate, s sticky, cw completewith, req requires, loop, a/b first/last row,
-- c conditions, pt points, tg targets, mob monsters, gs gossip skip, dz death skip }.

local Guide = DufforthTweaksHelperGuide
local Model = Guide.Model
local Rx = setmetatable({}, { __index = Model })
Rx.__index = Rx
Guide.Rx = Rx

local S_KIND, S_QUEST, S_ZONE, S_X, S_Y, S_GOAL, S_STEP, S_ARG = 1, 2, 3, 4, 5, 8, 11, 12
local P_ZONE, P_X, P_Y, P_RADIUS, P_KIND, P_TAG, P_PARENT = 1, 2, 3, 4, 5, 6, 7
local STOP, THROUGH, LOW, ARROW, PIN, WAYPOINT = 0, 1, 2, 3, 4, 5
Rx.MAX_MOVES = 400 -- steps the pointer may move in one refresh (a long jump goes on at the next refresh)

-- ---- State: in the route's saved table (the box builds a new model on every refresh) ----
function Rx:RxState()
    local s = self.saved.rx
    if not s then
        s = { skip = {}, marks = {}, reached = {}, back = {} }
        self.saved.rx = s
    end
    s.skip, s.marks, s.reached, s.back = s.skip or {}, s.marks or {}, s.reached or {}, s.back or {}
    return s
end

function Rx:Rec(n) return self.route.rx[n] end
function Rx:Arg(r) return self.steps[r] and self.steps[r][S_ARG] or {} end

-- ---- RestedXP's applies (GuideLoader.lua): "/" alternatives, "!" not, class (upper), race (Undead = Scourge),
-- faction, a number = your level or above, the game ("FOREVER") ----
function Rx:RxApplies(tag)
    if not tag or tag == "" then return true end
    local g = self.game
    local who = (g.who and g.who()) or {}
    local class, race, faction = string.upper(who.class or ""), who.race or "", who.faction or "Horde"
    local level = g.level()
    local function one(alt)
        for word in string.gmatch(alt, "!?[%w]+") do
            local negate = string.sub(word, 1, 1) == "!"
            if negate then word = string.sub(word, 2) end
            if word == "Undead" then word = "Scourge" end
            local up = string.upper(word)
            local n = tonumber(word)
            local yes = up == class or word == race or word == faction or up == "FOREVER" or (n ~= nil and level >= n)
            if yes == negate then return false end
        end
        return true
    end
    for alt in string.gmatch(tag, "[^/]+") do
        if one(alt) then return true end
    end
    return false
end

function Rx:RxShown(n)
    local rec = self:Rec(n)
    return rec ~= nil and self:RxApplies(rec.t)
end

-- The rows of step n that are yours (line tags).
function Rx:RxRows(n)
    self.rowsOf = self.rowsOf or {}
    if self.rowsOf[n] then return self.rowsOf[n] end
    local out, rec = {}, self:Rec(n)
    if rec and rec.a then
        for r = rec.a, rec.b do
            if self:RxApplies(self:Arg(r).lt) then out[#out + 1] = r end
        end
    end
    self.rowsOf[n] = out
    return out
end

-- ---- When a line is done (functions.lua element handlers) ----
local function XpMet(g, a)
    local level, cur, max = g.level(), 0, 1
    if g.xp then cur, max = g.xp() end
    local x, L = a.x or 0, a.l or 0
    if x < 0 then return level >= L or (level == L - 1 and cur >= max + x) end
    if x >= 1 then return level > L or (level == L and cur >= x) end
    return level > L or (level == L and cur >= max * x)
end

function Rx:RxRowDone(r)
    local st = self:RxState()
    if st.marks[r] or self.saved.skipped[r] then return true end
    return self:RxRowGame(r)
end

-- A line as its check box shows it (RestedXP's element check box): "game" = the game says it's done (ticked, locked),
-- "hand" = ticked by you or by an event (click to untick), "open".
function Rx:RxLineState(r)
    if self:RxRowGame(r) then return "game" end
    local st = self:RxState()
    if st.marks[r] or self.saved.skipped[r] then return "hand" end
    return "open"
end

-- Done by what the game says (quest log, level, items, spells, places reached), not by a tick.
function Rx:RxRowGame(r)
    local st = self:RxState()
    local row, g = self.steps[r], self.game
    local kind, id, a = row[S_KIND], row[S_QUEST], row[S_ARG] or {}
    if kind == "accept" then return g.done(id) or g.inLog(id) end
    if kind == "turnin" then
        if g.done(id) then return true end
        if a.m == 1 and a.i == 1 then return not (g.inLog(id) and g.complete(id)) end
        if a.m == 1 then return not g.inLog(id) end
        return false
    end
    if kind == "do" then
        if a.t == 1 then return true end -- text only
        if g.done(id) then return true end
        if not g.inLog(id) then return a.m == 1 end
        local k = row[S_GOAL] or 0
        if k > 0 and g.objectiveIndexDone then
            local d = g.objectiveIndexDone(id, k)
            if d ~= nil then return d end
        end
        if k > 0 and g.objectiveDone then
            local q = self:Quest(id)
            local goal = q and q[12] and q[12][k]
            local d = g.objectiveDone(id, goal and goal[2], goal, q and q[12])
            if d ~= nil then return d end
        end
        return g.complete(id)
    end
    if kind == "goto" then return st.reached[r] == true end
    if kind == "grind" then
        local met = XpMet(g, a)
        if a.rv == 1 then met = not met end
        return met
    end
    if kind == "fly" then return g.onTaxi ~= nil and g.onTaxi() end
    if kind == "home" then return a.ai ~= nil and g.bindIs ~= nil and g.bindIs(a.ai, a.a) or false end -- else marked when you bind
    if kind == "flight" then
        return row[S_X] ~= nil and g.flightKnown ~= nil and g.flightKnown(row[S_ZONE], row[S_X], row[S_Y]) and true or false
    end
    if kind == "collect" then
        if (a.q or 0) > 0 and (g.done(a.q) or (g.inLog(a.q) and g.complete(a.q))) then return true end
        return g.itemCount ~= nil and g.itemCount(a.i) >= (a.n or 1)
    end
    if kind == "train" then
        local known = g.spellKnown ~= nil and g.spellKnown(a.s) or false
        if a.rv == 1 then return not known end
        return known
    end
    if kind == "use" then return a.t == 1 end
    if kind == "abandon" then
        for _, q in ipairs(a.q or { id }) do if g.inLog(q) then return false end end
        return true
    end
    if kind == "destroy" then return g.itemCount ~= nil and g.itemCount(a.i) == 0 end
    if kind == "zone" then return g.zone() == a.z end
    if kind == "subzone" then return g.inArea ~= nil and g.inArea(a.id, a.z) or false end
    if kind == "equip" or kind == "aura" then return g.has ~= nil and g.has(kind, a.v) or false end
    return false -- hearth, vendor, trainer, stable, bank, cast, deathskip, note: marked by events or by hand (RxMark)
end

-- ---- Skip conditions (functions.lua: a true condition completes the step) ----
local function Ids(v)
    local out = {}
    for _, x in ipairs(v or {}) do
        local n = tonumber(x)
        if n then out[#out + 1] = math.abs(n) end
    end
    return out
end

function Rx:RxCondition(c)
    local kind, a, g = c[1], c[2] or {}, self.game
    local v = a.v or {}
    if kind == "xp" then
        local met = XpMet(g, a)
        if a.rv == 1 then met = not met end
        return met
    elseif kind == "isOnQuest" or kind == "isNotOnQuest" then
        local on = false
        for _, id in ipairs(Ids(v)) do on = on or g.inLog(id) end
        if kind == "isOnQuest" then return not on end
        return on
    elseif kind == "isQuestTurnedIn" or kind == "isQuestAvailable" then
        local any = false
        for _, id in ipairs(Ids(v)) do
            if kind == "isQuestTurnedIn" then any = any or g.done(id) else any = any or not g.done(id) end
        end
        return not any
    elseif kind == "isQuestComplete" or kind == "isQuestNotComplete" then
        local id = Ids(v)[1]
        local done = id ~= nil and g.inLog(id) and g.complete(id)
        if kind == "isQuestComplete" then return not done end
        return done
    elseif kind == "zoneskip" then
        local here, pass = g.zone(), false
        for _, z in ipairs(a.z or {}) do pass = pass or z == here end
        local reverse = (tonumber(v[2]) or 0) % 2 == 1
        return pass == not reverse
    elseif kind == "subzoneskip" then
        if not g.inArea then return false end
        local reverse = (tonumber(v[2]) or 0) % 2 == 1
        return (g.inArea(tonumber(v[1]), a.z and a.z[1]) and true or false) == not reverse
    elseif kind == "money" then
        local s = tostring(v[1] or "")
        local want = (tonumber(string.match(s, "(%d+%.?%d*)")) or 0) * 1e4
        local more = string.sub(s, 1, 1) == ">"
        local have = g.money and g.money() or 0
        if have >= want then return more end
        return not more
    elseif kind == "maxlevel" then
        return g.level() > (tonumber(string.match(tostring(v[1] or ""), "(%d+)")) or 99)
    elseif kind == "bindlocation" then
        if not g.bindIs then return false end
        return (g.bindIs(a.ai, a.a) and true or false) == not (a.rv == 1)
    elseif kind == "itemcount" then
        if not g.itemCount then return false end
        local count = 0
        for id in string.gmatch(tostring(v[1] or ""), "%d+") do count = count + g.itemCount(tonumber(id)) end
        local op, eq, total = string.match(tostring(v[2] or ""), "([<>]?)(=?)%s*(%d+)")
        total = tonumber(total)
        if not total then return false end
        local o = op == "<" and -1 or op == ">" and 1 or 0
        local ok = (eq == "=" and count == total) or (count * o > total * o) or (eq ~= "=" and o == 0 and count >= total)
        return not ok
    elseif kind == "train" then
        local known = g.spellKnown ~= nil and g.spellKnown(a.s) or false
        return known == not (a.rv == 1)
    elseif kind == "skill" then
        if not g.skill then return false end
        local lvl = g.skill(tostring(v[1] or ""))
        if not lvl then return false end
        local s = tostring(v[2] or "1")
        local reverse = string.sub(s, 1, 1) == "<"
        local need = tonumber(string.match(s, "(%d+)")) or 1
        local skip = tonumber(v[3])
        if skip and skip < 0 then reverse = not reverse end
        return (lvl >= need) == not reverse
    elseif kind == "cooldown" then
        if not g.cooldownLeft then return false end
        local left = g.cooldownLeft(v[1], tonumber(v[2]))
        if not left then return false end
        local op, cd, unit = string.match(tostring(v[3] or ""), "([<>]?)%s*(%d+%.?%d*)%s*([ms]?)")
        cd = tonumber(cd) or 0
        if unit == "m" then cd = cd * 60 end
        if cd < 2 then cd = 2 end
        if op == "<" then return left < cd end
        return left > cd
    elseif kind == "itemStat" then
        if not g.slotStat then return false end
        local stat = g.slotStat(tonumber(v[1]), v[2])
        if stat == nil then return false end
        local op, total = string.match(tostring(v[3] or ""), "^([<>]?)(.*)$")
        local ok
        if type(stat) == "number" then
            total = tonumber(total) or 0
            stat = math.floor(stat * 10 + 0.5) / 10
            ok = (op == ">" and total < stat) or (op == "<" and total > stat) or (op == "" and total == stat)
        else
            ok = total == stat
        end
        return not ok
    end
    return false
end

-- Does a condition of step n end it now?
function Rx:RxSkipped(n)
    for _, c in ipairs(self:Rec(n).c or {}) do
        if self:RxApplies(c[3]) and self:RxCondition(c) then return true end
    end
    return false
end

-- Step n done: every line of yours done, or a condition ends it.
function Rx:RxStepDone(n)
    if self:RxSkipped(n) then return true end
    for _, r in ipairs(self:RxRows(n)) do
        if not self:RxRowDone(r) then return false end
    end
    return true
end

-- ---- The pointer (GuideWindow.lua SetStep and UpdateStepCompletion) ----
-- Sticky steps of each part, in order (kept on the route: the data doesn't change).
function Rx:RxStickies(p)
    local route = self.route
    if not route.rxStickies then
        route.rxStickies = {}
        for n, rec in ipairs(route.rx) do
            if rec.s then
                local list = route.rxStickies[rec.p] or {}
                list[#list + 1] = n
                route.rxStickies[rec.p] = list
            end
        end
    end
    return route.rxStickies[p] or {}
end

-- The first step of each part, and where the pointer starts for your level: the first part whose levels end above
-- yours ("1-6 Durotar" at level 7 is passed).
function Rx:RxPartStart(p)
    for n, rec in ipairs(self.route.rx) do if rec.p == p then return n end end
end

function Rx:RxJoin()
    local level = self.game.level()
    for p, name in ipairs(self.route.parts or {}) do
        local hi = tonumber(string.match(name, "^%d+%-(%d+)"))
        if hi and hi > level then return self:RxPartStart(p - 1) or 1 end
    end
    return 1
end

-- The active steps with the pointer at n: open side steps of the part before n, then step n. Returns the list and
-- whether step n is in it.
function Rx:RxCollect(n)
    local st, level = self:RxState(), self.game.level()
    local rec = self:Rec(n)
    local active, isActive = {}, {}
    for _, i in ipairs(self:RxStickies(rec.p)) do
        if i >= n then break end
        local r = self:Rec(i)
        -- At a part's end (held), a "completewith" side step whose step is behind the pointer closes as the pointer
        -- passes it, so it doesn't hold the part (2026-11-27: the guide stuck on "24-26" while RestedXP was in Ashenvale).
        -- (A chain of "completewith next" side steps closes with the plain step at its end.)
        local target, hops = r.cw, 0
        while target and hops < 50 and (self:Rec(target) or {}).s and self:Rec(target).cw do
            target, hops = self:Rec(target).cw, hops + 1
        end
        local passing = st.held and target and not (self:Rec(target) or {}).s and target <= n
        if not st.skip[i] and not passing and self:RxShown(i) and level >= (r.lv or 0) then
            local req = r.req and self:Rec(r.req)
            local blocked = req and (isActive[r.req] or (req.s and not st.skip[r.req]))
            if not blocked then active[#active + 1] = i; isActive[i] = true end
        end
    end
    local inIt = false
    local req = rec.req and self:Rec(rec.req)
    local blocked = req and #active > 0 and (isActive[rec.req] or (req.s and not st.skip[rec.req]))
    if not rec.s and not blocked and level >= (rec.lv or 0) and not st.held then
        active[#active + 1] = n; isActive[n] = true; inIt = true
    end
    return active, inIt
end

-- Move the pointer until it rests: RestedXP's SetStep (stickies pass on, nothing active passes on, the end of a part
-- waits for its open side steps) and UpdateStepCompletion (done side steps drop, a done step moves the pointer).
function Rx:RxSettle()
    if self.rxActive then return self.rxActive end
    local st, recs = self:RxState(), self.route.rx
    if not st.at then st.at = self:RxJoin() end
    local n, moves = st.at, 0
    local from = n -- a pointer put at a part's first step (joined, picked, RestedXP's place) doesn't go back to wait
    local active = {}
    while moves < Rx.MAX_MOVES do
        moves = moves + 1
        if n > #recs then
            st.at, st.finished = #recs + 1, true
            active = {}
            break
        end
        st.finished = nil
        local rec = self:Rec(n)
        -- Into the next part only once the last part's side steps are closed (SetStep past a guide's end).
        local prev = self:Rec(n - 1)
        if n > 1 and n ~= from and prev and prev.p ~= rec.p and not st.held then
            st.at = n - 1
            st.held = true
            local open = self:RxCollect(n - 1)
            st.held = nil
            if #open > 0 then
                st.at, st.held, n = n - 1, true, n - 1
            end
        end
        if st.held and st.at ~= n then st.held = nil end
        if not st.held then st.at = n end
        local inIt
        if not st.held and (not self:RxShown(n) or rec.s) then
            n = n + 1
        else
            active, inIt = self:RxCollect(n)
            if #active == 0 then
                st.held = nil
                n = n + 1
            else
                -- Completion: a done side step (or one whose label the pointer passed) drops; a done step moves on.
                local changed = false
                for _, i in ipairs(active) do
                    local r = self:Rec(i)
                    if r.s then
                        local done = self:RxStepDone(i)
                        if not done and r.cw then
                            local target = self:Rec(r.cw)
                            if target and target.s then done = st.skip[r.cw] == true
                            else done = n > r.cw end
                        end
                        if done then st.skip[i] = true; changed = true end
                    end
                end
                if inIt and self:RxStepDone(n) then
                    n = n + 1
                    changed = true
                elseif not changed then
                    break
                end
            end
        end
    end
    self.rxActive = active
    return active
end

function Rx:RxActive() return self:RxSettle() end
function Rx:RxAt() self:RxSettle(); return self:RxState().at end
function Rx:RxFinished() self:RxSettle(); return self:RxState().finished == true end

-- Rows of step n still to do.
function Rx:RxOpenRows(n)
    local out = {}
    for _, r in ipairs(self:RxRows(n)) do
        if not self:RxRowDone(r) then out[#out + 1] = r end
    end
    return out
end

-- ---- Points: reached, walked in order, looped (map.lua) ----
local function Key(n, k) return n .. ":" .. k end

function Rx:RxPointLive(n, k, p)
    if self:RxState().reached[Key(n, k)] then return false end
    if not self:RxApplies(p[P_TAG]) then return false end
    local parent = p[P_PARENT]
    if parent and self.steps[parent] and self:RxRowDone(parent) then return false end
    return true
end

-- The arrow's point: the first live point of the active steps in order, low-priority points last; a loop step's
-- points start again once all are reached. Also marks the points you stand on: a stop point anywhere, a walk-through
-- point only when the arrow is on it.
function Rx:RxPoint()
    local active, st, g = self:RxActive(), self:RxState(), self.game
    local function pick(low)
        for _, n in ipairs(active) do
            for k, p in ipairs(self:Rec(n).pt or {}) do
                local kind = p[P_KIND]
                local arrow = kind ~= PIN and ((kind == LOW) == low)
                if arrow and self:RxPointLive(n, k, p) then return n, k, p end
            end
        end
    end
    local n, k, p = pick(false)
    if not n then n, k, p = pick(true) end
    if not n then
        local again = false
        for _, i in ipairs(active) do
            if self:Rec(i).loop then
                for j, q in ipairs(self:Rec(i).pt or {}) do
                    if q[P_KIND] == THROUGH or q[P_KIND] == WAYPOINT then st.reached[Key(i, j)] = nil; again = true end
                end
            end
        end
        if again then n, k, p = pick(false) end
    end
    return n, k, p
end

function Rx:RxReach()
    local g, st = self.game, self:RxState()
    if not g.yardsTo then return false end
    local moved = false
    local an, ak = self:RxPoint()
    for _, n in ipairs(self:RxActive()) do
        for k, p in ipairs(self:Rec(n).pt or {}) do
            local kind, radius = p[P_KIND], p[P_RADIUS]
            local walk = kind == THROUGH or kind == WAYPOINT
            if radius and (kind == STOP or (walk and an == n and ak == k)) and self:RxPointLive(n, k, p) then
                local d = g.yardsTo(p[P_ZONE], p[P_X], p[P_Y])
                if d and d <= radius then
                    st.reached[Key(n, k)] = true
                    if kind == STOP and p[P_PARENT] then st.reached[p[P_PARENT]] = true end
                    moved = true
                end
            end
        end
    end
    if moved then self.rxActive = nil end
    return moved
end

-- Where the arrow points: { zone, x, y, kind = "spirit" | "corpse" | "point", step, row }, or nil.
function Rx:RxArrow()
    local g = self.game
    if g.ghost and g.ghost() then
        local deathskip = false
        for _, n in ipairs(self:RxActive()) do
            if self:Rec(n).dz then deathskip = true end
        end
        if deathskip and g.yardsTo then
            local best, bestD
            for _, h in ipairs(self.data.spirit or {}) do
                local d = g.yardsTo(h[1], h[2], h[3])
                if d and (not bestD or d < bestD) then best, bestD = h, d end
            end
            if best then return { zone = best[1], x = best[2], y = best[3], kind = "spirit", text = best[4] } end
        end
        if not deathskip and g.corpse then
            local z, x, y = g.corpse()
            if z and x then return { zone = z, x = x, y = y, kind = "corpse" } end
        end
    end
    for _ = 1, 8 do if not self:RxReach() then break end end
    local n, k, p = self:RxPoint()
    if not n then return nil end
    return { zone = p[P_ZONE], x = p[P_X], y = p[P_Y], kind = "point", step = n, point = k, row = p[P_PARENT] or self:Rec(n).a,
             stop = p[P_KIND] == STOP, radius = p[P_RADIUS] }
end

-- ---- Events the game reports: lines done by doing them (hearthstone cast, taxi, a window opened, a spell cast,
-- resurrected at a Spirit Healer, a new flight path) ----
local EVENT_KINDS = { hearth = "hearth", vendor = "vendor", trainer = "trainer", stable = "stable", bank = "bank", cast = "cast",
                      resurrect = "deathskip", taxi = "fly", flightpath = "flight", home = "home" }
function Rx:RxMark(event, arg)
    local kind = EVENT_KINDS[event]
    if not kind then return false end
    local st, marked = self:RxState(), false
    for _, n in ipairs(self:RxActive()) do
        for _, r in ipairs(self:RxOpenRows(n)) do
            local row = self.steps[r]
            local a = row[S_ARG] or {}
            local fits = row[S_KIND] == kind
            if fits and kind == "cast" and arg then
                fits = false
                for _, s in ipairs(a.s or {}) do fits = fits or s == arg end
            end
            if fits and (kind == "vendor" or kind == "trainer") and arg and (a.npc or 0) > 0 then fits = a.npc == arg end
            if fits then st.marks[r] = true; marked = true end
        end
    end
    if marked then self.rxActive, self.rowsOf = nil, nil end
    return marked
end

-- The active steps' NPCs and monsters for the target macro (RestedXP's .target / .mob / .unitscan).
function Rx:RxTargets()
    local out, seen = {}, {}
    for _, n in ipairs(self:RxActive()) do
        local rec = self:Rec(n)
        for _, list in ipairs({ rec.mob or {}, rec.us or {}, rec.tg or {} }) do
            for _, name in ipairs(list) do
                if not seen[name] then seen[name] = true; out[#out + 1] = name end
            end
        end
    end
    return out
end

-- Names the nameplate scan looks for: name -> "mob" (.mob), "us" (.unitscan: rare, with a sound), "tg" (.target).
function Rx:RxScanNames()
    local out = {}
    for _, n in ipairs(self:RxActive()) do
        local rec = self:Rec(n)
        for _, kind in ipairs({ "us", "mob", "tg" }) do
            for _, name in ipairs(rec[kind] or {}) do out[name] = out[name] or kind end
        end
    end
    return out
end

-- Map and minimap pins (RestedXP's map.lua): every live point of the active steps, in order, with its step number;
-- .arrow on the one the arrow points at. Points of kind PIN (map only) are included, reached ones are not.
function Rx:RxPins()
    local an, ak = self:RxPoint()
    local out = {}
    for _, n in ipairs(self:RxActive()) do
        local rec = self:Rec(n)
        for k, p in ipairs(rec.pt or {}) do
            if p[P_X] and self:RxPointLive(n, k, p) then
                out[#out + 1] = { n = n, k = k, zone = p[P_ZONE], x = p[P_X], y = p[P_Y], kind = p[P_KIND],
                                  row = p[P_PARENT] or rec.a, arrow = n == an and k == ak }
            end
        end
    end
    return out
end

-- Lines between the points of one step, in order (RestedXP draws a step's path on the map).
function Rx:RxPinLines(pins)
    local out = {}
    for k = 2, #(pins or {}) do
        local a, b = pins[k - 1], pins[k]
        if a.n == b.n and a.zone == b.zone then out[#out + 1] = { a, b } end
    end
    return out
end

-- ---- The step list: one row per RestedXP step ----
-- "current" (the pointer's step), "along" (an active side step), "done", "open", "passed" (not for you).
function Rx:RxStepState(n)
    local rec = self:Rec(n)
    if not rec or not self:RxShown(n) or #self:RxRows(n) == 0 then return "passed" end
    local st = self:RxState()
    for _, s in ipairs(self:RxActive()) do
        if s == n then return n == st.at and "current" or "along" end
    end
    if rec.s then
        if st.skip[n] or self:RxStepDone(n) then return "done" end
        return "open"
    end
    if n < (st.at or 1) then return "done" end
    return self:RxStepTicked(n) and "done" or "open" -- a step ahead: its conditions count once the pointer gets there
end

-- Every line of step n done (by the game or ticked)?
function Rx:RxStepTicked(n)
    local rows = self:RxRows(n)
    if #rows == 0 then return false end
    for _, r in ipairs(rows) do
        if not self:RxRowDone(r) then return false end
    end
    return true
end

-- The list row's check box: ticks every open line of the step; when all are done, unticks the ones you ticked.
function Rx:RxToggleWhole(n)
    local st = self:RxState()
    local rows = self:RxRows(n)
    if self:RxStepTicked(n) then
        for _, r in ipairs(rows) do st.marks[r] = nil; self.saved.skipped[r] = nil end
    else
        for _, r in ipairs(rows) do if not self:RxRowDone(r) then st.marks[r] = true end end
    end
    self.rxActive = nil
end

-- At login, drop the other starts' RestedXP routes from memory (GuideData holds all six: about 60 MB of Lua memory,
-- 17.5 MB with one start kept). Their part names stay in data.pruned for the Guides menu; picking one needs a /reload.
-- Questline guides (not RestedXP routes) stay. Returns how many routes this call dropped.
function Guide.PruneRoutes(data, keep)
    local routes = data and data.routes
    if not routes then return 0 end
    data.pruned = data.pruned or {}
    local drop = {}
    for name, route in pairs(routes) do
        if route.rxp and not keep[name] then drop[#drop + 1] = name end
    end
    for _, name in ipairs(drop) do
        local route = routes[name]
        data.pruned[name] = { parts = route.parts or {}, races = route.races }
        routes[name] = nil
    end
    return #drop
end

-- Auto accept / turn-in: only the quests of the active steps (RestedXP's questAccept / questTurnIn lists).
function Rx:RxAutoQuest(id, kind)
    for _, n in ipairs(self:RxActive()) do
        for _, r in ipairs(self:RxOpenRows(n)) do
            local row = self.steps[r]
            if row[S_QUEST] == id and row[S_KIND] == kind then return true end
        end
    end
    return false
end

-- Gossip skip (RestedXP's .skipgossip): true, or its arguments { npc id, option, option... }, of the first active step.
function Rx:RxGossip()
    for _, n in ipairs(self:RxActive()) do
        local gs = self:Rec(n).gs
        if gs then return type(gs) == "table" and gs or true end
    end
    return false
end

-- ---- The box's model calls, from the engine ----
function Rx:Current()
    local active = self:RxActive()
    local at = self:RxState().at
    for _, n in ipairs(active) do
        if n == at then
            local open = self:RxOpenRows(n)
            if open[1] then return open[1] end
        end
    end
    for _, n in ipairs(active) do
        local open = self:RxOpenRows(n)
        if open[1] then return open[1] end
    end
    return nil
end

-- Rows: the active steps' open lines (side steps first, as RestedXP lists them), then the next steps' lines.
function Rx:Upcoming(n)
    local out = {}
    for _, s in ipairs(self:RxActive()) do
        for _, r in ipairs(self:RxOpenRows(s)) do if #out < n then out[#out + 1] = r end end
    end
    local at, recs = self:RxState().at, self.route.rx
    for s = at + 1, #recs do
        if #out >= n then break end
        if self:RxShown(s) and not self:Rec(s).s then
            for _, r in ipairs(self:RxRows(s)) do if #out < n then out[#out + 1] = r end end
        end
    end
    return out
end

-- One card per RestedXP step, as its own window lists them: the active steps' open lines (side steps first), then the
-- next steps (n more cards); .trip = how many cards are active steps.
function Rx:Blocks()
    -- Only the active steps, like RestedXP's current steps frame (2026-11-27 screenshot: our next-step cards made the
    -- box look different); the steps ahead are in the list below.
    local out = { trip = 0 }
    for _, s in ipairs(self:RxActive()) do
        if self:RxOpenRows(s)[1] then out[#out + 1] = self:RxRows(s) end
    end
    out.trip = #out
    return out
end

-- The RestedXP step number of row i (the box's cards and list show it).
function Rx:RxStepOf(i) return self.steps[i] and self.steps[i][S_STEP] end

-- Items to use for the active steps (RestedXP's active item frame: .use lines), first first.
function Rx:RxItems()
    local out, seen = {}, {}
    for _, n in ipairs(self:RxActive()) do
        for _, r in ipairs(self:RxOpenRows(n)) do
            local row = self.steps[r]
            local id = row[S_KIND] == "use" and (row[S_ARG] or {}).i
            if id and id > 0 and not seen[id] then seen[id] = true; out[#out + 1] = id end
        end
    end
    return out
end

function Rx:States(last)
    local states, st = {}, self:RxState()
    local active, current = {}, {}
    for _, n in ipairs(self:RxActive()) do active[n] = true end
    current[st.at or 0] = true
    for i = 1, math.min(last, #self.steps) do
        local n = self.steps[i][S_STEP]
        local mine = self:RxShown(n) and self:RxApplies(self:Arg(i).lt)
        if not mine then states[i] = "passed"
        elseif self:RxRowDone(i) then states[i] = "done"
        elseif active[n] then states[i] = current[n] and "current" or "along"
        elseif n < (st.at or 1) then states[i] = "done"
        else states[i] = "open" end
    end
    return states
end

function Rx:Settled(i)
    local n = self.steps[i] and self.steps[i][S_STEP]
    if not n then return true end
    if not (self:RxShown(n) and self:RxApplies(self:Arg(i).lt)) then return true end
    if self:RxRowDone(i) then return true end
    local active = false
    for _, s in ipairs(self:RxActive()) do active = active or s == n end
    return not active and n < (self:RxState().at or 1)
end

function Rx:WaitsFor() return nil end
function Rx:Along() return {} end
function Rx:AlsoHere() return {} end
function Rx:OffRoute() return {} end

-- Skip: the pointer one step on (RestedXP: click the next step); Back: where it was.
function Rx:Skip()
    local st = self:RxState()
    self:RxSettle()
    st.back[#st.back + 1] = st.at
    st.at, st.held, st.finished = (st.at or 1) + 1, nil, nil
    self.rxActive = nil
end

function Rx:Back()
    local st = self:RxState()
    local n = table.remove(st.back)
    if not n then return end
    st.at, st.held, st.finished = n, nil, nil
    -- Its side steps come back too.
    for i = n, #self.route.rx do if st.skip[i] then st.skip[i] = nil end end
    self.rxActive = nil
end

-- A row picked in the list (or a part in the Guides menu): the pointer goes to its step.
function Rx:SetStart(i)
    local n = self.steps[i] and self.steps[i][S_STEP]
    if n then self:RxGoTo(n) end
end

-- The pointer to step n (a part picked in the Guides menu, a step in the list); its later side steps open again.
function Rx:RxGoTo(n)
    local st = self:RxState()
    if not self:Rec(n) then return end
    st.back[#st.back + 1] = st.at
    st.at, st.held, st.finished = n, nil, nil
    for j = n, #self.route.rx do st.skip[j] = nil end
    self.rxActive = nil
end

function Rx:Start() return 1 end

-- Where a new character of your level joins: the first row of that step.
function Rx:Recommended()
    local n = self:RxJoin()
    local rec = self:Rec(n)
    while rec and not rec.a do n = n + 1; rec = self:Rec(n) end
    return rec and rec.a or 1
end

-- A line ticked by hand ("+" lines, or one you did without the guide), or unticked.
function Rx:ToggleStep(i)
    if not self.steps[i] then return end
    local st = self:RxState()
    if st.marks[i] or self.saved.skipped[i] then st.marks[i] = nil; self.saved.skipped[i] = nil else st.marks[i] = true end
    self.rxActive = nil
end

-- Sections: RestedXP's parts ("1-6 Durotar"), their first and last rows.
function Rx:Sections()
    if self.sections then return self.sections end
    local out, byPart = {}, {}
    for n, rec in ipairs(self.route.rx) do
        if rec.a then
            local sec = byPart[rec.p]
            if not sec then
                local name = (self.route.parts or {})[rec.p + 1] or ""
                local lo, hi, zone = string.match(name, "^(%d+)%-(%d+)%s+(.+)$")
                sec = { first = rec.a, last = rec.b, ["from"] = tonumber(lo) or 1, ["to"] = tonumber(hi) or 60, zone = zone or name, part = rec.p }
                byPart[rec.p] = sec
                out[#out + 1] = sec
            end
            sec.last = rec.b
        end
    end
    self.sectionOf = {}
    for k, sec in ipairs(out) do
        for i = sec.first, sec.last do self.sectionOf[i] = k end
    end
    self.sections = out
    return out
end

-- ---- RestedXP's numbers, names and text (user, 2026-11-27: "compair this is not looking the same") ----
-- RestedXP numbers the steps of each part from 1, counting the steps that are for you (GuideLoader.lua drops the
-- others; GuideWindow.lua ProcessGuideTable keeps the shown ones).
function Rx:RxNumber(n)
    local route = self.route
    local key = self:RxWhoKey()
    route.rxNumbers = route.rxNumbers or {}
    local nums = route.rxNumbers[key]
    if not nums then
        nums = {}
        local count, part = 0, nil
        for i, rec in ipairs(route.rx) do
            if rec.p ~= part then part, count = rec.p, 0 end
            if self:RxApplies(rec.t) then count = count + 1; nums[i] = count end
        end
        route.rxNumbers[key] = nums
    end
    return nums[n]
end

function Rx:RxWhoKey()
    local who = (self.game.who and self.game.who()) or {}
    return tostring(who.class) .. ":" .. tostring(who.race) .. ":" .. tostring(who.faction)
end

function Rx:RxPartName(p) return (self.route.parts or {})[p + 1] or "" end
function Rx:RxSubName(p) return (self.route.subs or {})[p + 1] or "" end

-- "01-06 Mulgore" and "1-6 Mulgore" are the same part.
local function PartKey(name) return (string.gsub(tostring(name or ""), "%f[%d]0+(%d)", "%1")) end

-- RestedXP's own place (its saved RXPCData: currentGuideGroup, currentGuideName, currentStep, currentStepId and the
-- guide's id in guideMetaData): the step of ours it is on, or nil. A step id is the guide's id plus the step's line.
function Rx:RxFind(where)
    if not (where and where.name) then return nil end
    local want = PartKey(where.name)
    local part
    for p, name in ipairs(self.route.parts or {}) do
        if PartKey(name) == want then part = p - 1; break end
    end
    if not part then return nil end
    local line = where.stepId and where.guideId and (where.stepId - where.guideId) or nil
    local byNumber
    for n, rec in ipairs(self.route.rx) do
        if rec.p == part then
            if line and rec.ln == line and self:RxApplies(rec.t) then return n end
            if where.step and self:RxNumber(n) == where.step then byNumber = byNumber or n end
        end
    end
    return byNumber
end

-- Follow RestedXP while it runs next to us: when its place changes, the pointer goes to the same step.
function Rx:RxSync(where)
    if not (where and where.name) then return false end
    local key = PartKey(where.name) .. "#" .. tostring(where.stepId or where.step)
    local st = self:RxState()
    if st.synced == key then return false end
    local n = self:RxFind(where)
    if not n then return false end
    st.synced = key
    if st.at == n then return false end
    st.back[#st.back + 1] = st.at
    st.at, st.held, st.finished = n, nil, nil
    for j = n, #self.route.rx do st.skip[j] = nil end
    -- Side steps: earlier parts' are over; in this part, the ones RestedXP closed (its stepSkip, by its numbers).
    local part = self:Rec(n).p
    for j = 1, n - 1 do
        local rec = self:Rec(j)
        if rec.s then
            if rec.p ~= part then st.skip[j] = true
            elseif where.skip and where.skip[self:RxNumber(j) or 0] then st.skip[j] = true end
        end
    end
    self.rxActive = nil
    return true
end

-- RestedXP's colour names (Themes.lua guideTextColors.default) as the game's colour codes.
Rx.COLORS = { RXP_FRIENDLY_ = "FF00FF25", RXP_ENEMY_ = "FFFF5722", RXP_LOOT_ = "FF00BCD4", RXP_WARN_ = "FFFCDC00",
              RXP_PICK_ = "FFDB2EEF", RXP_BUY_ = "FF0E8312" }
function Rx.Colorize(text)
    text = string.gsub(tostring(text or ""), "|c(RXP_[%u_]-_)", function(k) return "|c" .. (Rx.COLORS[k] or "FFFFFFFF") end)
    return (string.gsub(text, "\\n", "\n"))
end

-- What a step's card and list row show, in RestedXP's order: { text = "..." } for its text lines, { row = r } for its
-- lines you act on (with RestedXP's text in .said when it has one); lines RestedXP shows no text for are left out.
function Rx:RxDisplay(n)
    local rec = self:Rec(n)
    if not rec then return {} end
    local out, k = {}, 0
    local texts = rec.x or {}
    local t = 1
    local function textsUpTo(pos)
        while texts[t] and texts[t][1] <= pos do
            if self:RxApplies(texts[t][3]) then out[#out + 1] = { text = Rx.Colorize(texts[t][2]) } end
            t = t + 1
        end
    end
    textsUpTo(0)
    if rec.a then
        for r = rec.a, rec.b do
            k = k + 1
            local a = self:Arg(r)
            if self:RxApplies(a.lt) and not a.h then
                out[#out + 1] = { row = r, said = a.rt and Rx.Colorize(a.rt) or nil }
            end
            textsUpTo(k)
        end
    end
    textsUpTo(1e9)
    return out
end
