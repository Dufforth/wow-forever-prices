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

H.FIGHTS_KEPT, H.MAX_TRIES, H.MAX_CASTS = 300, 500, 400
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
        autoShots = 0, hawkCasts = {}, hawkMax = 0, hawkOver = 0, mongooseWindows = 0, mongooseUsed = 0, enemiesMax = 0,
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
    f.start, f.hawkCasts = nil, nil
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
    if spell == H.AUTO then fight.autoShots = fight.autoShots + 1; return end -- every shot: counted, not listed
    local target = Tag("target")
    if spell == H.MARK then fight.marks[target ~= "" and target or "?"] = (fight.marks[target ~= "" and target or "?"] or 0) + 1 end
    if spell == H.HAWK then
        if H.HawksOut(fight.hawkCasts, t) >= 2 then
            -- Two out already: the game keeps two at most, so this one wasted the shared cooldown (counted) and,
            -- if it replaces one, the oldest goes.
            fight.hawkOver = fight.hawkOver + 1
            for i, at in ipairs(fight.hawkCasts) do
                if t - at < H.HAWK_SECONDS then table.remove(fight.hawkCasts, i); break end
            end
        end
        fight.hawkCasts[#fight.hawkCasts + 1] = t
        fight.hawkMax = math.max(fight.hawkMax, H.HawksOut(fight.hawkCasts, t))
    end
    if spell == H.MONGOOSE then fight.mongooseUsed = fight.mongooseUsed + 1 end
    if #fight.casts < H.MAX_CASTS then
        fight.casts[#fight.casts + 1] = string.format("%.1f %s t:%s h:%d", t, spell, target, H.HawksOut(fight.hawkCasts, t))
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

function H.FightCount() return #DB().fights end
function H.ClearLog() local o = DB(); o.fights = {}; o.macros = {} end

-- ---- Events ----

function H.OnEvent(_, event, a, b, c, ...)
    if not H.IsHunter() then return end
    if event == "PLAYER_REGEN_DISABLED" then H.FightStart(); return end
    if event == "PLAYER_REGEN_ENABLED" then H.FightEnd(); return end
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
        H.LogCast(name)
        if name ~= H.AUTO then H.LogTry("C", name) end
    elseif event == "UNIT_SPELLCAST_SENT" then
        local spellID = ...
        H.LogTry("S", spellID and SpellName(spellID) or tostring(c))
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        local kind = event == "UNIT_SPELLCAST_FAILED" and "F" or (event == "UNIT_SPELLCAST_FAILED_QUIET" and "Q" or "I")
        H.LogTry(kind, c and SpellName(c) or "?")
    end
end

if CreateFrame then
    local frame = CreateFrame("Frame")
    for _, name in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD", "UI_ERROR_MESSAGE",
        "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET",
        "UNIT_SPELLCAST_INTERRUPTED" }) do
        pcall(frame.RegisterEvent, frame, name)
    end
    frame:SetScript("OnEvent", Guard("events", H.OnEvent))
    local elapsed = 0
    frame:SetScript("OnUpdate", Guard("tick", function(_, dt)
        if not fight then return end
        elapsed = elapsed + (dt or 0)
        if elapsed >= 0.2 then elapsed = 0; H.Tick() end
    end))
end
