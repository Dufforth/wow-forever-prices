-- Hunter fight log (user, 2026-11-25: "record all my logs from battles and learn about this to improve my rotation
-- and recommend the most efficient way to play"). Records only; it never casts and never changes your macro.
-- Per fight: every spell sent, cast, refused or interrupted (with the error text), each cast's target and how many
-- Summon Hawks were out (they last 18 s; two at most), Hunter's Mark per target (to catch double marks),
-- Mongoose Bite windows (it lights up after you dodge) and whether you used them, Auto Shots, your pet, your
-- hunter macros' text, enemies around you, mana before and after, and whether you won.
-- tools/analyze_hunter_fights.py reads it from SavedVariables (written on /reload or logout) and recommends changes.

local L = DufforthTweaksHelperL or setmetatable({}, { __index = function(_, k) return k end })
DufforthTweaksHelperHunter = DufforthTweaksHelperHunter or {}
local H = DufforthTweaksHelperHunter
local W = DufforthTweaksHelperWarrior

H.FIGHTS_KEPT, H.MAX_TRIES, H.MAX_CASTS, H.MAX_AUTOS = 300, 500, 400, 200
H.HAWK = "Summon Hawk"
H.HAWK_SECONDS = 18
H.MARK = "Hunter's Mark"
H.MONGOOSE = "Mongoose Bite"
H.AUTO = "Auto Shot"
-- Spells that mark a macro as one of your hunter macros (its text goes in the log).
H.MACRO_SPELLS = { "Hunter's Mark", "Summon Hawk", "Arcane Shot", "Aimed Shot", "Raptor Strike", "Serpent Sting", "Mongoose Bite" }

local function DB()
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    local db = DufforthTweaksHelperDB
    db.hunter = db.hunter or {}
    local o = db.hunter
    if o.log == nil then o.log = true end
    o.fights = o.fights or {}
    o.macros = o.macros or {}
    o.errors = o.errors or {}
    return o
end
H.Options = DB

function H.IsHunter()
    local ok, _, class = pcall(UnitClass, "player")
    return ok and class == "HUNTER"
end

local function Plain(value)
    if W and W.Plain then return W.Plain(value) end
    return value
end

local function SpellName(id)
    if W and W.SpellName then return W.SpellName(id) end
    return GetSpellInfo and GetSpellInfo(id) or tostring(id)
end

local function Now() return GetTime and GetTime() or 0 end

local function Guard(where, fn)
    return function(...)
        local args, n = { ... }, select("#", ...)
        local ok, err = pcall(function() return fn(unpack(args, 1, n)) end)
        if not ok then
            local errors = DB().errors
            local key = where .. ": " .. tostring(err)
            errors[key] = (errors[key] or 0) + 1
        end
    end
end
H.Guard = Guard

local function Usable(name)
    local ok, usable
    if C_Spell and C_Spell.IsSpellUsable then ok, usable = pcall(C_Spell.IsSpellUsable, name)
    elseif IsUsableSpell then ok, usable = pcall(IsUsableSpell, name) end
    return ok and Plain(usable) == true
end

-- The last 6 characters of a unit's GUID ("" when hidden): enough to tell targets apart in one fight.
local function Tag(unit)
    local ok, guid = pcall(UnitGUID, unit)
    guid = ok and Plain(guid)
    if type(guid) ~= "string" then return "" end
    return string.sub(guid, -6)
end

local function ManaPercent()
    local ok, now, most = pcall(function() return UnitPower("player", 0), UnitPowerMax("player", 0) end)
    now, most = ok and Plain(now), ok and Plain(most)
    if type(now) ~= "number" or type(most) ~= "number" or most <= 0 then return nil end
    return math.floor(now / most * 100 + 0.5)
end

-- Your hunter macros' text, stored once each in DB().macros; returns their numbers ("3,7").
function H.MacroIds()
    if not (GetMacroInfo and GetNumMacros) then return "" end
    local general, character = GetNumMacros()
    local ids, macros = {}, DB().macros
    local function Consider(index)
        local ok, name, _, body = pcall(GetMacroInfo, index)
        if not ok or type(body) ~= "string" then return end
        for _, spell in ipairs(H.MACRO_SPELLS) do
            if string.find(body, spell, 1, true) then
                local id
                for i, text in ipairs(macros) do if text == body then id = i end end
                if not id then macros[#macros + 1] = body; id = #macros end
                ids[#ids + 1] = tostring(id)
                return
            end
        end
    end
    for i = 1, general or 0 do Consider(i) end
    for i = 121, 120 + (character or 0) do Consider(i) end
    return table.concat(ids, ",")
end

local fight
H.preTries = {}

function H.Current() return fight end

function H.FightStart()
    if not DB().log or not H.IsHunter() then return end
    local ok, talents = pcall(function() return W and W.TalentText and W.TalentText() or "?" end)
    local petOk, petName = pcall(UnitName, "pet")
    local familyOk, family = pcall(function() return UnitCreatureFamily and UnitCreatureFamily("pet") end)
    fight = {
        at = time and time() or 0, start = Now(),
        character = DufforthTweaksHelper and DufforthTweaksHelper.CharacterKey and DufforthTweaksHelper.CharacterKey() or "?",
        zone = GetRealZoneText and GetRealZoneText() or "?", level = UnitLevel and UnitLevel("player") or 0,
        group = (IsInGroup and IsInGroup()) and true or false, talents = ok and talents or "?",
        pet = petOk and Plain(petName) or nil, petFamily = familyOk and Plain(family) or nil,
        macros = H.MacroIds(), manaStart = ManaPercent(),
        casts = {}, tries = {}, tried = {}, errors = {}, marks = {}, result = "won",
        autoShots = 0, hawksAtStart = H.HawksAlive(), hawkMax = 0, hawkOver = 0, mongooseWindows = 0, mongooseUsed = 0, enemiesMax = 0,
    }
    for _, try in ipairs(H.preTries) do
        if fight.start - try.at <= 6 then
            fight.tries[#fight.tries + 1] = string.format("%.1f %s %s", try.at - fight.start, try.kind, try.name)
        end
    end
    H.preTries = {}
    H.mongooseUp = Usable(H.MONGOOSE)
end

function H.FightEnd()
    if not fight then return end
    local f = fight
    fight = nil
    f.seconds = math.floor((Now() - f.start) * 10 + 0.5) / 10
    f.start, f.lastError = nil, nil
    f.manaEnd = ManaPercent()
    local deadOk, dead = pcall(UnitIsDead, "pet")
    f.petAlive = f.pet and not (deadOk and Plain(dead) == true) or false
    if #f.casts == 0 and f.seconds < 3 then return end
    local repeats = 0
    for _, count in pairs(f.marks) do if count > 1 then repeats = repeats + count - 1 end end
    f.markRepeats = repeats
    local fights = DB().fights
    fights[#fights + 1] = f
    while #fights > H.FIGHTS_KEPT do table.remove(fights, 1) end
    if W and W.ReadFightDamage then
        local read = Guard("damage meter", function() W.ReadFightDamage(f) end)
        if C_Timer then C_Timer.After(1.5, read) else read() end
    end
end

-- Your hawks' summon times (GetTime), kept across fights: a hawk lives 18 s, longer than the gap between
-- chained pulls, so a per-fight count missed third hawks (2026-11-26: 10 of 54 with reset=combat).
H.hawkTimes = {}

function H.HawksAlive(now)
    now = now or Now()
    local alive = {}
    for _, at in ipairs(H.hawkTimes) do if now - at < H.HAWK_SECONDS then alive[#alive + 1] = at end end
    H.hawkTimes = alive
    return #alive
end

-- A hawk was summoned: true when two were already out (the oldest goes).
function H.NoteHawk(now)
    local over = H.HawksAlive(now) >= 2
    if over then table.remove(H.hawkTimes, 1) end
    H.hawkTimes[#H.hawkTimes + 1] = now
    return over
end

-- Hawks still out at time t (each lasts HAWK_SECONDS).
function H.HawksOut(casts, t)
    local n = 0
    for _, at in ipairs(casts or {}) do if t - at < H.HAWK_SECONDS then n = n + 1 end end
    return n
end

-- kind: S sent, C cast, F failed, Q failed quietly, I interrupted, E error text, M+ / M- Mongoose Bite lit / gone.
function H.LogTry(kind, name)
    if not name then return end
    if fight then
        -- In melee the game's own Auto Shot repeat fails about 20 times every 0.1 s; listing those filled the
        -- whole log by 11 s (2026-11-26). Count them, and list a repeated error text at most once a second.
        if name == H.AUTO and (kind == "F" or kind == "Q") then fight.autoFails = (fight.autoFails or 0) + 1; return end
        if kind == "E" then
            local now = Now()
            fight.lastError = fight.lastError or {}
            if fight.lastError[name] and now - fight.lastError[name] < 1 then return end
            fight.lastError[name] = now
        end
        if #fight.tries < H.MAX_TRIES then
            fight.tries[#fight.tries + 1] = string.format("%.1f %s %s", Now() - fight.start, kind, name)
        end
        local tried = fight.tried[name] or {}
        tried[kind] = (tried[kind] or 0) + 1
        fight.tried[name] = tried
    elseif DB().log and H.IsHunter() then
        table.insert(H.preTries, { at = Now(), kind = kind, name = name })
        while #H.preTries > 30 do table.remove(H.preTries, 1) end
    end
end

-- "seconds spell t:<target> h:<hawks out>"
function H.LogCast(spell)
    if not fight or not spell then return end
    local t = Now() - fight.start
    if spell == H.AUTO then -- every shot: counted, and its time kept (to measure whether Arcane Shot delays it)
        fight.autoShots = fight.autoShots + 1
        fight.autoTimes = fight.autoTimes or {}
        if #fight.autoTimes < H.MAX_AUTOS then fight.autoTimes[#fight.autoTimes + 1] = math.floor(t * 100 + 0.5) / 100 end
        return
    end
    local target = Tag("target")
    if spell == H.MARK then fight.marks[target ~= "" and target or "?"] = (fight.marks[target ~= "" and target or "?"] or 0) + 1 end
    if spell == H.HAWK then
        -- Two out already (hawks live 18 s, also from the fight before): this one wasted the shared cooldown.
        if H.NoteHawk(Now()) then fight.hawkOver = fight.hawkOver + 1 end
        fight.hawkMax = math.max(fight.hawkMax, H.HawksAlive())
    end
    if spell == H.MONGOOSE then fight.mongooseUsed = fight.mongooseUsed + 1 end
    if #fight.casts < H.MAX_CASTS then
        fight.casts[#fight.casts + 1] = string.format("%.1f %s t:%s h:%d", t, spell, target, H.HawksAlive())
    end
end

function H.LogError(message)
    if fight and message then fight.errors[message] = (fight.errors[message] or 0) + 1 end
end

-- Called a few times a second in a fight: Mongoose Bite windows, enemies around you.
function H.Tick()
    if not fight then return end
    local up = Usable(H.MONGOOSE)
    if up and not H.mongooseUp then
        fight.mongooseWindows = fight.mongooseWindows + 1
        H.LogTry("M+", H.MONGOOSE)
    elseif H.mongooseUp and not up then
        H.LogTry("M-", H.MONGOOSE)
    end
    H.mongooseUp = up
    if W and W.EnemyCount then
        local ok, n = pcall(W.EnemyCount)
        if ok and type(n) == "number" and n > fight.enemiesMax then fight.enemiesMax = n end
    end
end

-- ---- The DTH Hunter macro (built from the user's logged fights, 2026-11-26) ----
-- Proven press rule (Warrior.lua): one global-cooldown try per press; off-GCD lines (Raptor Strike,
-- Auto Shot, Mongoose Bite) are tried on every press; "X,nil" casts once, then is skipped.
-- Farming fights are short (median 14.6 s, enemies in melee at ~4 s), so: pet attacks first, a hawk on
-- the first press, Hunter's Mark in the wait for the shared 6 s cooldown, then hawks and Arcane Shot.
-- Aimed Shot is left out (it needs range and a cast, and stalled the button in melee).
-- Two hawks at most, each 18 s, also across chained pulls: between fights the addon plans the next
-- pull's order from the hawks still out (H.PlanSteps) and rewrites the macro (out of combat only).

H.MACRO_NAME, H.MACRO_LIMIT = "DTH Hunter", 255
local MACRO_ICON = "INV_MISC_QUESTIONMARK"
H.DROP_FIRST = { "Mongoose Bite", "#showtooltip" } -- without #showtooltip the button shows a question mark
H.SHARED_CD, H.GCD, H.PLAN_STEPS = 6, 1.5, 7

-- The order of the next pull's global-cooldown presses. alive = seconds left on each hawk still out,
-- cdLeft = seconds left on the shared Hawk/Arcane cooldown. A hawk only when fewer than two will be out;
-- Hunter's Mark fills the first wait; Arcane Shot fills a wait for a hawk to expire. Returns names, times.
function H.PlanSteps(known, alive, cdLeft, count)
    local steps, times, expires = {}, {}, {}
    for _, left in ipairs(alive or {}) do expires[#expires + 1] = left end
    local t, cd, marked = 0, cdLeft or 0, not known[H.MARK]
    local function out(at)
        local n = 0
        for _, e in ipairs(expires) do if e > at + 0.05 then n = n + 1 end end
        return n
    end
    local function add(name, at) steps[#steps + 1] = name; times[#times + 1] = at end
    while #steps < (count or H.PLAN_STEPS) do
        local ready = math.max(t, cd)
        local hawk = out(ready) < 2
        if hawk and ready <= t then
            add(H.HAWK, ready); expires[#expires + 1] = ready + H.HAWK_SECONDS; cd = ready + H.SHARED_CD; t = ready + H.GCD
        elseif not marked then
            add(H.MARK, t); marked = true; t = t + H.GCD
        elseif hawk then
            add(H.HAWK, ready); expires[#expires + 1] = ready + H.HAWK_SECONDS; cd = ready + H.SHARED_CD; t = ready + H.GCD
        elseif known["Arcane Shot"] then
            add("Arcane Shot", ready); cd = ready + H.SHARED_CD; t = ready + H.GCD
        else
            break
        end
    end
    return steps, times
end

function H.BuildLines(known, skip, plan)
    skip = skip or {}
    local function has(name) return known[name] and not skip[name] end
    local out = {}
    if not skip["#showtooltip"] then out[#out + 1] = "#showtooltip" end
    out[#out + 1] = "/targetenemy [noharm][dead]"
    out[#out + 1] = "/petattack" -- the pet goes first
    if has(H.HAWK) and has("Arcane Shot") then
        plan = plan or H.PlanSteps(known, {}, 0)
        out[#out + 1] = "/castsequence reset=combat " .. table.concat(plan, ",")
    else
        if has(H.MARK) then out[#out + 1] = "/castsequence reset=combat Hunter's Mark,nil" end -- once a fight
        if has(H.HAWK) then
            out[#out + 1] = "/castsequence reset=combat Summon Hawk,Summon Hawk,nil"
        else
            if has("Aimed Shot") then out[#out + 1] = "/castsequence reset=combat Aimed Shot,nil" end
            if has("Arcane Shot") then out[#out + 1] = "/cast Arcane Shot" end
        end
    end
    if has("Raptor Strike") then out[#out + 1] = "/cast Raptor Strike" end
    out[#out + 1] = "/cast !Auto Shot"
    if has(H.MONGOOSE) then out[#out + 1] = "/cast Mongoose Bite" end
    return out
end

-- Lines that fit 255 characters (the game cuts longer macros: the user's own lost its Auto Shot line).
function H.Fit(known, plan)
    local skip = {}
    local lines = H.BuildLines(known, skip, plan)
    for _, name in ipairs(H.DROP_FIRST) do
        if #table.concat(lines, "\n") <= H.MACRO_LIMIT then break end
        skip[name] = true
        lines = H.BuildLines(known, skip, plan)
    end
    while #table.concat(lines, "\n") > H.MACRO_LIMIT and #lines > 1 do table.remove(lines, 1) end
    return lines
end

-- Hawks still out (seconds left on each) and the shared cooldown left, right now.
function H.PullState(now)
    now = now or Now()
    H.HawksAlive(now)
    local alive = {}
    for _, at in ipairs(H.hawkTimes) do alive[#alive + 1] = at + H.HAWK_SECONDS - now end
    local last = 0
    local cast = W and W.lastCastAt or {}
    for _, name in ipairs({ H.HAWK, "Arcane Shot" }) do if cast[name] and cast[name] > last then last = cast[name] end end
    local cdLeft = last > 0 and math.max(0, last + H.SHARED_CD - now) or 0
    return alive, cdLeft
end

H.state = { status = L["Not built yet."] }

function H.Update()
    local state = H.state
    if not H.IsHunter() then state.status = L["Only for hunters."]; return false end
    local o = DB()
    if o.enabled == false then state.status = L["Off."]; return false end
    if InCombatLockdown and InCombatLockdown() then state.pending = true; return false end
    state.pending = false
    local known = (W and W.KnownSpells and W.KnownSpells()) or {}
    known[H.AUTO] = true
    local alive, cdLeft = H.PullState()
    local plan = H.PlanSteps(known, alive, cdLeft)
    state.plan = plan
    H.ScheduleReplan(alive, cdLeft)
    local lines = H.Fit(known, plan)
    local body = table.concat(lines, "\n")
    state.lines, state.known = lines, known
    if body == state.body then return false end -- unchanged: don't reset the sequences
    local index = GetMacroIndexByName and GetMacroIndexByName(H.MACRO_NAME)
    local ok, err
    if index and index > 0 then
        ok, err = pcall(EditMacro, index, H.MACRO_NAME, MACRO_ICON, body)
    else
        ok, err = pcall(CreateMacro, H.MACRO_NAME, MACRO_ICON, body, true)
        if ok and (not err or err == 0) then ok, err = false, L["no free character macro slot"] end
    end
    if not ok then
        state.status = L["|cffff5555Couldn't save the macro: "] .. tostring(err) .. "|r"
        return false
    end
    state.body = body
    state.status = string.format(L["Macro %s: %d lines, %d characters%s."], H.MACRO_NAME, #lines, #body, "")
    return true
end

-- Out of combat the plan changes when a hawk runs out or the shared cooldown ends: rewrite then.
local replanAt
function H.ScheduleReplan(alive, cdLeft)
    if not (C_Timer and C_Timer.After) then return end
    local soonest
    for _, left in ipairs(alive) do if left > 0 and (not soonest or left < soonest) then soonest = left end end
    if cdLeft > 0 and (not soonest or cdLeft < soonest) then soonest = cdLeft end
    if not soonest then return end
    local at = Now() + soonest + 0.1
    if replanAt and replanAt <= at and replanAt > Now() then return end
    replanAt = at
    C_Timer.After(soonest + 0.1, function()
        replanAt = nil
        if not (InCombatLockdown and InCombatLockdown()) then H.SafeUpdate() end
    end)
end

function H.SafeUpdate()
    local ok, result = pcall(H.Update)
    if not ok then
        H.state.status = L["|cffff5555Error: "] .. tostring(result) .. "|r"
        DB().errors["update: " .. tostring(result)] = (DB().errors["update: " .. tostring(result)] or 0) + 1
    end
    return ok and result
end

function H.PickUp()
    if InCombatLockdown and InCombatLockdown() then return end
    H.SafeUpdate()
    if PickupMacro then PickupMacro(H.MACRO_NAME) end
end

-- ---- The spell the next press casts, drawn on the DTH Hunter button ----
-- The game's own macro icon shows the first matching spell (or a fixed one with "#showtooltip X"), not
-- the one the press casts. Warrior.lua's helpers follow the castsequences and the one-try rule.

local OFF_GCD = { ["Raptor Strike"] = true, ["Auto Shot"] = true, ["Mongoose Bite"] = true }
local ON_SWING = { ["Raptor Strike"] = true } -- its sequence step (none) would move when queued
local SHARED = { ["Summon Hawk"] = true, ["Arcane Shot"] = true } -- one 6 s cooldown
local WHY_NOT_READY = {
    ["Aimed Shot"] = L["needs range and standing still"],
    ["Arcane Shot"] = L["needs range"],
    ["Summon Hawk"] = L["waits for its shared cooldown"],
}
H.OFF_GCD = OFF_GCD

function H.MacroLines()
    local body
    if GetMacroInfo and GetMacroIndexByName and (GetMacroIndexByName(H.MACRO_NAME) or 0) > 0 then
        local ok, _, _, text = pcall(GetMacroInfo, H.MACRO_NAME)
        if ok and type(text) == "string" then body = text end
    end
    if not body and H.state.lines then body = table.concat(H.state.lines, "\n") end
    return W.ParseMacro(body)
end

function H.Facts()
    return { known = H.state.known or {}, stance = 0,
        inCombat = UnitAffectingCombat and UnitAffectingCombat("player") and true or false,
        inGroup = (IsInGroup and IsInGroup()) and true or false }
end

local function SpellIcon(name)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, texture = pcall(C_Spell.GetSpellTexture, name)
        if ok and texture then return texture end
    end
    return GetSpellTexture and GetSpellTexture(name)
end

local function InRange(name)
    local ok, result
    if C_Spell and C_Spell.IsSpellInRange then ok, result = pcall(C_Spell.IsSpellInRange, name, "target")
    elseif IsSpellInRange then ok, result = pcall(IsSpellInRange, name, "target") end
    result = ok and Plain(result)
    return not (result == false or result == 0)
end

function H.SpellReady(name)
    if not Usable(name) then return false end
    if W.CooldownLeft and W.CooldownLeft(name) > 0 then return false end
    if UnitExists and UnitExists("target") and not InRange(name) then return false end
    return true
end

-- spell, ready, note
function H.Pick(facts, ready, now)
    local lines = H.MacroLines()
    if #lines == 0 then return nil end
    return W.ButtonPick(lines, facts, ready or H.SpellReady, now or Now(), OFF_GCD, WHY_NOT_READY)
end

-- A cast or try moves the addon's copy of each castsequence like the game moves its own.
function H.FollowTry(kind, name)
    local lines = H.MacroLines()
    if #lines == 0 then return end
    local facts, now = H.Facts(), Now()
    if (kind == "C" or kind == "S") and name then
        W.SequenceCast(lines, facts, name, kind, now, ON_SWING)
        if kind == "C" and W.lastCastAt then
            W.lastCastAt[name] = now
            if SHARED[name] then for other in pairs(SHARED) do W.lastCastAt[other] = now end end
        end
    end
    W.SequencePressed(lines, facts, now)
end

local overlays = {}
H.overlays = overlays

function H.RefreshButtons()
    if not (GetActionInfo and W.AllBarButtons) then return end
    local index = GetMacroIndexByName and GetMacroIndexByName(H.MACRO_NAME) or 0
    for _, overlay in pairs(overlays) do overlay.active = false end
    if index and index > 0 then
        for _, button in ipairs(W.AllBarButtons()) do
            local slot = button and W.ButtonSlot(button)
            if slot then
                local kind, id = GetActionInfo(slot)
                local name = GetActionText and GetActionText(slot)
                if kind == "macro" and (id == index or name == H.MACRO_NAME) then
                    local overlay = overlays[button]
                    if not overlay and not (InCombatLockdown and InCombatLockdown()) then
                        overlay = CreateFrame("Frame", nil, button)
                        overlay:SetAllPoints(button)
                        overlay:SetFrameLevel((button:GetFrameLevel() or 1) + 2)
                        overlay:EnableMouse(false)
                        overlay.icon = overlay:CreateTexture(nil, "OVERLAY")
                        overlay.icon:SetPoint("TOPLEFT", 2, -2)
                        overlay.icon:SetPoint("BOTTOMRIGHT", -2, 2)
                        overlays[button] = overlay
                    end
                    if overlay then overlay.active = true end
                end
            end
        end
    end
    H.UpdateButtons()
end

function H.UpdateButtons()
    if not H.IsHunter() then return end
    local on = DB().buttonIcon ~= false
    local spell, ready
    if on and next(overlays) then spell, ready = H.Pick(H.Facts()) end
    H.currentPick = spell
    local texture = spell and SpellIcon(spell)
    for _, overlay in pairs(overlays) do
        local show = overlay.active and on and texture ~= nil or false
        overlay:SetShown(show)
        if show then
            overlay.icon:SetTexture(texture)
            overlay.icon:SetDesaturated(not ready)
        end
    end
end

function H.FightCount() return #DB().fights end
function H.ClearLog() local o = DB(); o.fights = {}; o.macros = {} end

-- ---- Events ----

function H.OnEvent(_, event, a, b, c, ...)
    if not H.IsHunter() then return end
    if event == "PLAYER_REGEN_DISABLED" then H.FightStart(); return end
    if event == "PLAYER_REGEN_ENABLED" then
        H.FightEnd()
        if W.SequenceCombatEnded then W.SequenceCombatEnded() end -- reset=combat lines start over
        H.SafeUpdate(); H.RefreshButtons(); return
    end
    if event == "PLAYER_LOGIN" or event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_SKILL_LINE"
        or event == "PLAYER_TALENT_UPDATE" then
        H.SafeUpdate(); H.RefreshButtons(); return
    end
    if event == "ACTIONBAR_SLOT_CHANGED" or event == "UPDATE_MACROS" or event == "PLAYER_ENTERING_WORLD" then
        if not (InCombatLockdown and InCombatLockdown()) then H.RefreshButtons() end
        return
    end
    if event == "PLAYER_DEAD" then if fight then fight.result = "died" end; return end
    if event == "UI_ERROR_MESSAGE" then
        local message = type(a) == "string" and a or b
        message = Plain(message)
        if type(message) ~= "string" then message = "?" end
        H.LogError(message)
        H.LogTry("E", message)
        return
    end
    if a ~= "player" then return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local name = c and SpellName(c)
        if name == H.HAWK and not fight then H.NoteHawk(Now()) end -- summoned before the pull
        H.LogCast(name)
        if name ~= H.AUTO then H.LogTry("C", name); H.FollowTry("C", name) end
    elseif event == "UNIT_SPELLCAST_SENT" then
        local spellID = ...
        local name = spellID and SpellName(spellID) or tostring(c)
        H.LogTry("S", name)
        if name ~= H.AUTO then H.FollowTry("S", name) end
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        local kind = event == "UNIT_SPELLCAST_FAILED" and "F" or (event == "UNIT_SPELLCAST_FAILED_QUIET" and "Q" or "I")
        H.LogTry(kind, c and SpellName(c) or "?")
    end
end

if CreateFrame then
    local frame = CreateFrame("Frame")
    for _, name in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD", "UI_ERROR_MESSAGE",
        "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET",
        "UNIT_SPELLCAST_INTERRUPTED", "PLAYER_LOGIN", "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE",
        "PLAYER_TALENT_UPDATE", "ACTIONBAR_SLOT_CHANGED", "UPDATE_MACROS", "PLAYER_ENTERING_WORLD" }) do
        pcall(frame.RegisterEvent, frame, name)
    end
    frame:SetScript("OnEvent", Guard("events", H.OnEvent))
    local elapsed, picture = 0, 0
    frame:SetScript("OnUpdate", Guard("tick", function(_, dt)
        picture = picture + (dt or 0)
        if picture >= 0.1 then picture = 0; H.UpdateButtons() end -- the next spell on the button
        if not fight then return end
        elapsed = elapsed + (dt or 0)
        if elapsed >= 0.2 then elapsed = 0; H.Tick() end
    end))
end
