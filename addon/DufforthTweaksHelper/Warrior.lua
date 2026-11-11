-- Warrior one-button helper.
--
-- The game lets nothing change what a button casts during combat, so this works in two parts:
--  * Between fights it rewrites the "DTH Warrior" macro: only spells you know, stance numbers
--    that match your stance bar, Battle Shout only when the buff is missing or about to end, and
--    a second part on a hidden button when it doesn't fit in 255 characters.
--  * During fights an icon shows what the button will cast next, plus how many enemies are on
--    you and whether Battle Shout is gone. You still press the button; the addon never casts.

DufforthTweaksHelperWarrior = DufforthTweaksHelperWarrior or {}
local W = DufforthTweaksHelperWarrior

local MACRO_NAME = "DTH Warrior"
local MACRO_ICON = "INV_MISC_QUESTIONMARK" -- the question mark shows the spell the macro will cast
local MACRO_LIMIT = 255
local SHOUT = "Battle Shout"
local SHOUT_KEEP_SECONDS = 45 -- leave Battle Shout out of the macro while it has this long left
local VICTORIOUS = "Victorious" -- the buff a kill that gives XP or honor puts on you (Victory Rush)
local VICTORY_MIN_SECONDS = 6
W.MACRO_NAME, W.MACRO_LIMIT = MACRO_NAME, MACRO_LIMIT

-- Stances by spell id; their number on the stance bar depends on which ones you know.
local STANCES = { { id = 2457, name = "Battle Stance" }, { id = 71, name = "Defensive Stance" }, { id = 2458, name = "Berserker Stance" } }
local BATTLE, DEFENSIVE, BERSERKER = 1, 2, 3

-- How the macro is built. Rules proven by the press-by-press log (fights 34-37, 11 Nov 2026, and
-- every earlier fight fits them):
--  * on each press the game tries only ONE spell that uses the global cooldown: the first line
--    whose conditions match. If that spell is rejected (Victory Rush without a kill, Revenge without
--    a block, Overpower without a dodge), the other global-cooldown lines are not even tried;
--  * spells off the global cooldown (Shield Block, Heroic Strike, Cleave, Charge) are tried on every
--    press, wherever they are;
--  * "/castsequence ... X,nil" casts X once and then is skipped (Battle Shout);
--  * a macro can't run an addon's button with /click.
-- So each stance gets exactly one global-cooldown line, and when a stance has several such spells
-- they go in one /castsequence that steps to the next spell each time one is cast: Defensive
-- Stance "Revenge, Sunder Armor, Heroic Strike" (Revenge waits for a block; Shield Block makes
-- blocks), Battle Stance Overpower. Rend and Battle Shout go first, once each. Victory Rush and
-- Execute can't share the button (they would take every press while they can't be cast), so the
-- icon tells you when to press them on their own key, like Shield Bash.
local LINES = {
    { { spell = "Charge" }, { spell = "Intercept" }, { spell = "Battle Shout" }, { spell = "Rend" },
      { spell = "Revenge" }, { spell = "Sunder Armor" }, { spell = "Shield Slam" }, { spell = "Shield Block" },
      { spell = "Overpower" }, { spell = "Mortal Strike" }, { spell = "Bloodthirst" }, { spell = "Whirlwind" },
      { spell = "Heroic Strike" }, { spell = "Cleave" } },
}
W.LINES = LINES

-- The best global-cooldown attack for Battle or Berserker Stance, if any.
local function BigAttack(known, stance)
    local order = stance == BERSERKER and { "Bloodthirst", "Mortal Strike", "Whirlwind" } or { "Mortal Strike", "Bloodthirst" }
    for _, name in ipairs(order) do if known[name] then return name end end
end

local function DB()
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    local db = DufforthTweaksHelperDB
    db.warrior = db.warrior or {}
    local o = db.warrior
    if o.enabled == nil then o.enabled = true end
    if o.hint == nil then o.hint = true end
    if o.charge == nil then o.charge = true end
    if o.log == nil then o.log = true end
    if o.buttonIcon == nil then o.buttonIcon = true end
    o.debug = o.debug or {}
    o.debug.events = o.debug.events or {}
    o.debug.errors = o.debug.errors or {}
    o.fights = o.fights or {}
    o.macros = o.macros or {}
    return o
end
W.Options = DB

function W.IsWarrior()
    local _, class = UnitClass("player")
    return class == "WARRIOR"
end

local function Lockdown() return InCombatLockdown and InCombatLockdown() end

-- Newer clients hide some combat values from addons ("secret values"); comparing or doing math
-- on one is an error. Plain() turns those into nil.
local function Plain(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end
W.Plain = Plain

-- Errors are kept in DufforthTweaksHelperDB.warrior.debug.errors ("where: message" -> count),
-- because the game hides addon errors by default.
local MAX_ERRORS = 30
function W.RecordError(where, message)
    local errors = DB().debug.errors
    local key = where .. ": " .. tostring(message)
    if errors[key] then errors[key] = errors[key] + 1; return end
    local count = 0
    for _ in pairs(errors) do count = count + 1 end
    if count < MAX_ERRORS then errors[key] = 1 end
end

-- Runs fn(...) and records any error instead of stopping.
function W.Guard(where, fn)
    return function(...)
        local args, n = { ... }, select("#", ...)
        local ok, err = pcall(function() return fn(unpack(args, 1, n)) end)
        if not ok then W.RecordError(where, err) end
    end
end

local function CountEvent(event)
    local events = DB().debug.events
    events[event] = (events[event] or 0) + 1
end
W.CountEvent = CountEvent

-- Spell functions, from C_Spell / C_SpellBook on newer clients or the old globals.
local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if C_Spell and C_Spell.GetSpellInfo then local info = C_Spell.GetSpellInfo(id); return info and info.name end
    return GetSpellInfo and (GetSpellInfo(id))
end
local function SpellUsable(name)
    if C_Spell and C_Spell.IsSpellUsable then return C_Spell.IsSpellUsable(name) end
    if IsUsableSpell then return IsUsableSpell(name) end
    return false
end
local function SpellCooldown(name)
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(name)
        if info then return info.startTime, info.duration end
        return 0, 0
    end
    if GetSpellCooldown then return GetSpellCooldown(name) end
    return 0, 0
end
local function SpellIcon(name)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(name) end
    return GetSpellTexture and GetSpellTexture(name)
end
-- false when the target is out of range; true or nil (can't tell) otherwise.
local function SpellInRange(name)
    local result
    if C_Spell and C_Spell.IsSpellInRange then result = C_Spell.IsSpellInRange(name, "target")
    elseif IsSpellInRange then result = IsSpellInRange(name, "target") end
    if result == false or result == 0 then return false end
    return true
end
W.SpellName = SpellName

-- Registers each event that this client knows; unknown names would stop the whole file.
W.missingEvents = {}
local function Listen(frame, names)
    for _, name in ipairs(names) do
        local ok, err = pcall(frame.RegisterEvent, frame, name)
        if not ok then W.missingEvents[#W.missingEvents + 1] = name .. " (" .. tostring(err) .. ")" end
    end
end

-- ---- Reading the game ----

-- Names of every spell in your spellbook: { ["Heroic Strike"] = true, ... }.
function W.KnownSpells()
    local known = {}
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemName then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
            local offset, count = info and info.itemIndexOffset or 0, info and info.numSpellBookItems or 0
            for slot = offset + 1, offset + count do
                local name = C_SpellBook.GetSpellBookItemName(slot, bank)
                if name then known[name] = true end
            end
        end
        if next(known) then return known end
    end
    local tabs = GetNumSpellTabs and GetNumSpellTabs() or 0
    for tab = 1, tabs do
        local _, _, offset, count = GetSpellTabInfo(tab)
        for slot = (offset or 0) + 1, (offset or 0) + (count or 0) do
            local name
            if GetSpellBookItemName then name = GetSpellBookItemName(slot, BOOKTYPE_SPELL or "spell")
            elseif GetSpellName then name = GetSpellName(slot, BOOKTYPE_SPELL or "spell") end
            if name then known[name] = true end
        end
    end
    return known
end

-- Stance -> its number on the stance bar ({ [1] = 1, [2] = 2 }), for the stances you know.
function W.StanceNumbers(known)
    local numbers = {}
    local count = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
    for i = 1, count do
        local _, _, _, spellID = GetShapeshiftFormInfo(i)
        for stance, info in ipairs(STANCES) do
            if spellID == info.id then numbers[stance] = i end
        end
    end
    if not next(numbers) then -- can't read the bar: stances come in the order you learn them
        local n = 0
        for stance, info in ipairs(STANCES) do
            if known[info.name] then n = n + 1; numbers[stance] = n end
        end
    end
    return numbers
end

-- The stance you're in now (BATTLE, DEFENSIVE, BERSERKER) or nil.
function W.CurrentStance(numbers)
    local form = GetShapeshiftForm and GetShapeshiftForm() or 0
    for stance, number in pairs(numbers) do
        if number == form then return stance end
    end
end

-- Seconds left on one of your buffs, math.huge if it never ends, nil if you don't have it.
W.auraCache = {}
function W.BuffLeft(name)
    if UnitAffectingCombat and UnitAffectingCombat("player") then
        local expires = W.auraCache[name]
        if not expires then return nil end
        if expires == math.huge then return math.huge end
        local left = expires - GetTime()
        return left > 0 and left or nil
    end
    local left = W.ReadBuff(name)
    W.auraCache[name] = left and (left == math.huge and math.huge or GetTime() + left) or nil
    return left
end

function W.ReadBuff(name)
    for i = 1, 40 do
        local auraName, expires
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not aura then return nil end
            auraName, expires = aura.name, aura.expirationTime
        elseif UnitBuff then
            local buffName, _, _, _, _, expiration = UnitBuff("player", i)
            if not buffName then return nil end
            auraName, expires = buffName, expiration
        else
            return nil
        end
        if auraName == name then
            if not expires or expires == 0 then return math.huge end
            return math.max(0, expires - GetTime())
        end
    end
end

-- ---- Building the macro (pure: no game calls) ----

local function ClauseText(clause, numbers)
    local conditions = {}
    if clause.when then conditions[#conditions + 1] = clause.when end
    if clause.equipped then conditions[#conditions + 1] = "equipped:" .. clause.equipped end
    if clause.stance then
        if not numbers[clause.stance] then return nil end -- a stance you don't have
        conditions[#conditions + 1] = "form:" .. numbers[clause.stance]
    elseif clause.stances then
        local forms = {}
        for _, stance in ipairs(clause.stances) do
            if numbers[stance] then forms[#forms + 1] = numbers[stance] end
        end
        if #forms == 0 then return nil end
        table.sort(forms)
        conditions[#conditions + 1] = "form:" .. table.concat(forms, "/")
    end
    if #conditions == 0 then return clause.spell end
    return "[" .. table.concat(conditions, ",") .. "] " .. clause.spell
end

-- The macro's lines for these known spells, stance numbers and options.
-- Where Charge can be cast besides Battle Stance. The Warbringer talent allows every stance and
-- combat; other talents are found by asking the game, out of combat, whether Charge is usable in the
-- stance you're in. Saved per character in warrior.charge["Name-Realm"] = { [stance] = true/false }.
function W.LearnCharge(known, numbers)
    if not known["Charge"] then return {}, false end
    if known["Warbringer"] then return { [DEFENSIVE] = true, [BERSERKER] = true }, true end
    local saved = DB().chargeStances or {}
    DB().chargeStances = saved
    local key = DufforthTweaksHelper.CharacterKey and DufforthTweaksHelper.CharacterKey() or "?"
    saved[key] = saved[key] or {}
    local mine = saved[key]
    local stance = W.CurrentStance(numbers)
    if stance and stance ~= BATTLE and not Lockdown() then
        local usable = SpellUsable("Charge")
        mine[stance] = usable and true or false
    end
    local out = {}
    for s, ok in pairs(mine) do if ok then out[s] = true end end
    return out, false
end

-- Whether you hold a shield: the item in your off hand is armor (class 4) of the shield kind (6).
function W.HasShield()
    if IsEquippedItemType and IsEquippedItemType("Shields") then return true end
    local id = GetInventoryItemID and GetInventoryItemID("player", 17)
    if not id then return false end
    local info = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not info then return false end
    local _, _, _, _, _, classID, subclassID = info(id)
    return classID == 4 and subclassID == 6
end

function W.OnlyHolds(only, shield, group)
    if only == "shield" then return shield and true or false end
    if only == "group" then return group and true or false end
    if only == "solo" then return not group end
    return true
end

-- Rend lasts longer at higher ranks; ranks come with level (9 s at first, 21 s from level 40).
function W.RendSeconds(level)
    level = level or 1
    if level >= 40 then return 21 elseif level >= 30 then return 18 elseif level >= 20 then return 15 elseif level >= 10 then return 12 end
    return 9
end

-- Charge works in Battle Stance out of combat, unless a talent widens it:
-- chargeStances = { [DEFENSIVE] = true, ... } stances where Charge is allowed too, chargeInCombat.
local function ChargeClause(clause, options)
    if clause.spell ~= "Charge" then return clause end
    local stances = { BATTLE }
    for _, stance in ipairs({ DEFENSIVE, BERSERKER }) do
        if options.chargeStances and options.chargeStances[stance] then stances[#stances + 1] = stance end
    end
    return { spell = "Charge", stances = stances, when = not options.chargeInCombat and "nocombat" or nil }
end
W.ChargeClause = ChargeClause

-- options: shout (Battle Shout is missing), charge (false = no Charge), shield, group, level,
-- chargeStances / chargeInCombat (where your talents allow Charge).
function W.BuildLines(known, numbers, options)
    options = options or {}
    local out = { "/startattack" }
    local berserkerKnown = numbers[BERSERKER] ~= nil
    local filler = (options.group and known["Cleave"]) and "Cleave" or (known["Heroic Strike"] and "Heroic Strike" or nil)

    -- Off the global cooldown: tried on every press.
    if options.charge ~= false then
        local parts = {}
        local intercept = known["Intercept"] and numbers[BERSERKER]
        if known["Charge"] then
            if intercept or options.chargeInCombat then
                local text = ClauseText(ChargeClause({ spell = "Charge" }, options), numbers)
                if text then parts[#parts + 1] = text end
            else
                -- Off the global cooldown: in a stance where it can't be used the game just rejects it.
                parts[#parts + 1] = "[nocombat] Charge"
            end
        end
        if intercept then parts[#parts + 1] = "[nocombat,form:" .. numbers[BERSERKER] .. "] Intercept" end
        if #parts > 0 then out[#out + 1] = "/cast " .. table.concat(parts, ";") end
    end

    -- Global cooldown, once each.
    -- Right after a kill that gives XP or honor (the Victorious buff, about 20 s): Victory Rush once,
    -- on the next pull. Written only while the buff has time left and removed when it ends, so it
    -- never sits first while it can't be cast (that would take the global-cooldown try every press).
    if options.victorious and known["Victory Rush"] then out[#out + 1] = "/castsequence Victory Rush,nil" end
    if options.shout and known[SHOUT] then out[#out + 1] = "/castsequence reset=120 " .. SHOUT .. ",nil" end
    if known["Rend"] and (numbers[BATTLE] or numbers[DEFENSIVE]) then
        local seconds = W.RendSeconds(options.level)
        if berserkerKnown then
            local forms = {}
            for _, stance in ipairs({ BATTLE, DEFENSIVE }) do if numbers[stance] then forms[#forms + 1] = numbers[stance] end end
            out[#out + 1] = string.format("/castsequence [form:%s] reset=%d Rend,nil", table.concat(forms, "/"), seconds)
        else
            out[#out + 1] = string.format("/castsequence reset=%d Rend,nil", seconds) -- every known stance allows Rend
        end
    end

    -- One global-cooldown line per stance.
    local function Line(stance, spells)
        if not numbers[stance] or #spells == 0 then return end
        if #spells == 1 then
            out[#out + 1] = "/cast [form:" .. numbers[stance] .. "] " .. spells[1]
        else
            out[#out + 1] = "/castsequence [form:" .. numbers[stance] .. "] " .. table.concat(spells, ",")
        end
    end
    local defensive = {}
    if options.shield and known["Shield Slam"] then defensive[#defensive + 1] = "Shield Slam" end
    if options.shield and known["Revenge"] then defensive[#defensive + 1] = "Revenge" end -- needs blocks to come up
    if known["Sunder Armor"] then defensive[#defensive + 1] = "Sunder Armor" end
    if #defensive > 0 and filler then defensive[#defensive + 1] = filler end
    Line(DEFENSIVE, defensive)
    local battleBig = BigAttack(known, BATTLE)
    if battleBig then Line(BATTLE, filler and { battleBig, filler } or { battleBig })
    elseif known["Overpower"] then Line(BATTLE, { "Overpower" }) end
    local berserkerBig = BigAttack(known, BERSERKER)
    if berserkerBig then Line(BERSERKER, filler and { berserkerBig, filler } or { berserkerBig }) end

    -- Off the global cooldown again.
    if options.shield and known["Shield Block"] and numbers[DEFENSIVE] then
        out[#out + 1] = "/cast [form:" .. numbers[DEFENSIVE] .. "] Shield Block"
    end
    -- Heroic Strike on every press where no sequence above already uses it (Battle Stance at low level).
    if filler and numbers[BATTLE] and not battleBig then out[#out + 1] = "/cast [form:" .. numbers[BATTLE] .. "] " .. filler end
    return out
end

-- The macro text, at most 255 characters: if it's longer, the least important lines go first.
local DROP_FIRST = { "Rend", "Charge", "Battle Shout" }
-- With Victory Rush in (right after a kill), Charge goes first: you are usually close already.
local DROP_FIRST_VICTORY = { "Charge", "Battle Shout", "Rend" }
function W.Fit(lines)
    local kept = {}
    for i, line in ipairs(lines) do kept[i] = line end
    local function TooLong() return #table.concat(kept, "\n") > MACRO_LIMIT end
    local victory = false
    for _, line in ipairs(kept) do if string.find(line, "Victory Rush", 1, true) then victory = true end end
    for _, name in ipairs(victory and DROP_FIRST_VICTORY or DROP_FIRST) do
        if not TooLong() then break end
        for i = #kept, 1, -1 do
            if string.find(kept[i], name, 1, true) then table.remove(kept, i); break end
        end
    end
    while TooLong() and #kept > 1 do table.remove(kept) end
    return table.concat(kept, "\n"), #lines - #kept
end

-- ---- Writing the macro ----

W.state = { status = "Not built yet." }
local shoutTimer

-- Rebuilds the macro if anything changed. Returns true when it wrote the macro.
function W.Update()
    local state = W.state
    if not W.IsWarrior() then state.status = "Only for warriors."; return false end -- tests check this text
    local options = DB()
    if not options.enabled then state.status = "Off."; return false end
    if Lockdown() then state.pending = true; return false end -- try again when the fight ends
    state.pending = false

    local known = W.KnownSpells()
    local numbers = W.StanceNumbers(known)
    local left = W.BuffLeft(SHOUT)
    local shout = not left or left < SHOUT_KEEP_SECONDS
    local chargeStances, chargeInCombat = W.LearnCharge(known, numbers)
    -- At least 6 s left, so the buff is still there when the next pull's first presses come.
    local victoryLeft = W.BuffLeft(VICTORIOUS)
    local victorious = victoryLeft ~= nil and victoryLeft >= VICTORY_MIN_SECONDS
    state.victoryLeft = victoryLeft
    -- Take it out again when under 6 s are left (no event fires then), so a pull never starts with a
    -- Victory Rush that runs out before it is cast.
    if victorious and victoryLeft ~= math.huge and C_Timer and not W.victoryTimer then
        W.victoryTimer = true
        C_Timer.After(victoryLeft - VICTORY_MIN_SECONDS + 0.1, function() W.victoryTimer = nil; W.SafeUpdate() end)
    end
    local shield = W.HasShield()
    local group = (IsInGroup and IsInGroup()) or (GetNumGroupMembers and GetNumGroupMembers() > 0) or false
    local lines = W.BuildLines(known, numbers, { shout = shout, charge = options.charge, shield = shield, group = group,
        chargeStances = chargeStances, chargeInCombat = chargeInCombat, victorious = victorious,
        level = UnitLevel and UnitLevel("player") })
    local body, dropped = W.Fit(lines)
    state.known, state.numbers, state.lines, state.dropped = known, numbers, lines, dropped
    state.shout, state.shield, state.group = shout, shield, group
    state.victoryInMacro = string.find(body, "Victory Rush", 1, true) ~= nil
    state.chargeStances, state.chargeInCombat = chargeStances, chargeInCombat

    -- Come back when Battle Shout is about to run out, so the macro adds it again in time.
    if left and left ~= math.huge and left >= SHOUT_KEEP_SECONDS and C_Timer and not shoutTimer then
        shoutTimer = true
        C_Timer.After(left - SHOUT_KEEP_SECONDS + 1, function() shoutTimer = nil; W.Update() end)
    end

    if body == state.body then return false end -- unchanged: don't reset the Battle Shout sequence

    local index = GetMacroIndexByName(MACRO_NAME)
    local ok, err
    if index and index > 0 then
        ok, err = pcall(EditMacro, index, MACRO_NAME, MACRO_ICON, body)
    else
        ok, err = pcall(CreateMacro, MACRO_NAME, MACRO_ICON, body, true)
        if ok and (not err or err == 0) then ok, err = false, "no free character macro slot" end
    end
    if not ok then
        state.status = "|cffff5555Couldn't save the macro: " .. tostring(err) .. "|r"
        return false
    end
    state.body = body
    state.status = string.format("Macro %s: %d lines, %d characters%s.", MACRO_NAME, #lines - dropped, #body,
        dropped > 0 and (", " .. dropped .. " left out to fit") or "")
    return true
end

-- W.Update, with any error shown on the Warrior tab.
function W.SafeUpdate()
    local ok, result = pcall(W.Update)
    if not ok then
        W.state.status = "|cffff5555Error: " .. tostring(result) .. "|r"
        W.RecordError("update", result)
    end
    local debug = DB().debug
    debug.status = W.state.status
    debug.build = GetBuildInfo and table.concat({ tostring((GetBuildInfo())), tostring(select(2, GetBuildInfo())), tostring(select(4, GetBuildInfo())) }, " ") or "?"
    debug.updatedAt = time and time() or 0
    debug.missingEvents = table.concat(W.missingEvents, "; ")
    if W.state.known then
        local names = {}
        for name in pairs(W.state.known) do
            for _, line in ipairs(LINES) do
                for _, clause in ipairs(line) do if clause.spell == name then names[#names + 1] = name end end
            end
        end
        table.sort(names)
        debug.rotationSpells = table.concat(names, ", ")
    end
    return ok and result
end

function W.PickUp()
    if Lockdown() then return end
    W.SafeUpdate()
    if PickupMacro then PickupMacro(MACRO_NAME) end
end

function W.Print()
    local say = DufforthTweaksHelper.Print
    if not W.state.lines then say(W.state.status); return end
    say(W.state.status)
    for _, line in ipairs(W.state.lines) do DEFAULT_CHAT_FRAME:AddMessage("  " .. line) end
end

-- ---- What the button will do next (for the icon) ----

local function SpellReady(name)
    local usable, noMana = SpellUsable(name)
    usable, noMana = Plain(usable), Plain(noMana)
    if usable == false or noMana then return false end
    local start, duration = SpellCooldown(name)
    start, duration = Plain(start), Plain(duration) -- hidden in combat on this client
    if start and start > 0 and duration and duration > 1.5 then return false end -- 1.5 s is the global cooldown
    if UnitExists("target") and not SpellInRange(name) then return false end
    return true
end

-- What the button will cast on the next press (the icon). The castsequence position is inside the
-- game, so for Defensive Stance it shows the best spell that's ready right now.
-- facts = { known, stance, inCombat, inGroup, shield, rendOnTarget, shoutLeft, shoutInMacro, charge };
-- ready(name) -> bool.
function W.NextSpell(facts, ready)
    local known = facts.known
    local function ok(name) return known[name] and ready(name) end
    if facts.victoryInMacro and ok("Victory Rush") then return "Victory Rush" end -- once, after a kill
    if not facts.inCombat and facts.charge ~= false and ok("Charge") then return "Charge" end
    if facts.shoutInMacro and known[SHOUT] and not facts.shoutLeft and ok(SHOUT) then return SHOUT end
    if (facts.stance == BATTLE or facts.stance == DEFENSIVE) and not facts.rendOnTarget and ok("Rend") then return "Rend" end
    if facts.stance == DEFENSIVE then
        if facts.shield and ok("Shield Block") then return "Shield Block" end
        for _, name in ipairs({ "Shield Slam", "Revenge", "Sunder Armor" }) do
            if (facts.shield or name == "Sunder Armor") and ok(name) then return name end
        end
    elseif facts.stance == BATTLE then
        local big = BigAttack(known, BATTLE)
        if big and ok(big) then return big end
        if ok("Overpower") then return "Overpower" end
    elseif facts.stance == BERSERKER then
        local big = BigAttack(known, BERSERKER)
        if big and ok(big) then return big end
    end
    local filler = (facts.inGroup and known["Cleave"]) and "Cleave" or "Heroic Strike"
    if ok(filler) then return filler end
end

-- Spells for their own key, shown on the icon when they can be cast: they can't share the button,
-- because the game would try them first on every press and skip the rest while they can't be cast.
function W.OwnKeyPrompt(facts, ready)
    -- When the macro already has it (a kill before this pull), the button casts it: no prompt.
    if facts.known["Victory Rush"] and not facts.victoryInMacro and ready("Victory Rush") then return "Victory Rush" end
    if facts.known["Execute"] and (facts.stance == BATTLE or facts.stance == BERSERKER) and ready("Execute") then return "Execute" end
end

-- Enemies that hit you or that you hit in the last few seconds, read from the game's combat log
-- (the same data as the damage details). guid -> { at = GetTime(), name = name }.
local RECENT_SECONDS = 5
local HOSTILE = 0x00000040 -- COMBATLOG_OBJECT_REACTION_HOSTILE
W.recent = {}

-- One combat log line. Returns true when it counted an enemy.
function W.CombatLog(subevent, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, amount)
    local me = UnitGUID and UnitGUID("player")
    if not me or not subevent then return false end
    local hit = string.find(subevent, "_DAMAGE$") or string.find(subevent, "_MISSED$") or subevent == "SWING_DAMAGE"
    if not hit then return false end
    local now = GetTime()
    if destGUID == me and sourceGUID and bit.band(sourceFlags or 0, HOSTILE) ~= 0 then
        W.recent[sourceGUID] = { at = now, name = sourceName }
        W.LogHit(sourceName, amount)
        return true
    elseif sourceGUID == me and destGUID and bit.band(destFlags or 0, HOSTILE) ~= 0 then
        W.recent[destGUID] = { at = now, name = destName }
        return true
    end
    return false
end

function W.ForgetDead(guid) W.recent[guid] = nil end

local function RecentCount()
    local now, count = GetTime(), 0
    for guid, seen in pairs(W.recent) do
        if now - seen.at <= RECENT_SECONDS then count = count + 1 else W.recent[guid] = nil end
    end
    return count
end

-- Enemies fighting you: the higher of the combat log count and the enemy nameplates
-- (nameplates catch enemies that haven't swung yet; the combat log works with nameplates off).
function W.EnemyCount()
    local count = RecentCount()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return count end
    local plates = 0
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit and UnitCanAttack("player", unit) and not UnitIsDead(unit) and UnitAffectingCombat(unit) then
            local threat = UnitThreatSituation and Plain(UnitThreatSituation("player", unit))
            if threat or UnitIsUnit(unit .. "target", "player") then plates = plates + 1 end
        end
    end
    return math.max(count, plates)
end

-- Whether your target has your Rend (or another debuff of yours by that name).
W.rendAt = {}
function W.TargetHasMyDebuff(name)
    if not UnitExists("target") then return false end
    if name == "Rend" then
        local guid = UnitGUID and Plain(UnitGUID("target"))
        local at = guid and W.rendAt[guid]
        return at and GetTime() - at < W.RendSeconds(UnitLevel and UnitLevel("player")) or false
    end
    if UnitAffectingCombat and UnitAffectingCombat("player") then return false end
    for i = 1, 40 do
        local auraName
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local aura = C_UnitAuras.GetAuraDataByIndex("target", i, "HARMFUL|PLAYER")
            if not aura then return false end
            auraName = Plain(aura.name)
        elseif UnitDebuff then
            local debuffName = UnitDebuff("target", i, "PLAYER")
            if not debuffName then return false end
            auraName = Plain(debuffName)
        else
            return false
        end
        if auraName == name then return true end
    end
    return false
end

local hint
local function HintFacts()
    local state = W.state
    local known = state.known or W.KnownSpells()
    local numbers = state.numbers or W.StanceNumbers(known)
    return {
        known = known,
        stance = W.CurrentStance(numbers),
        inCombat = UnitAffectingCombat("player") and true or false,
        inGroup = (IsInGroup and IsInGroup()) or (GetNumGroupMembers and GetNumGroupMembers() > 0) or false,
        shield = W.HasShield(),
        rendOnTarget = W.TargetHasMyDebuff("Rend"),
        shoutLeft = W.BuffLeft(SHOUT),
        shoutInMacro = state.shout,
        chargeStances = state.chargeStances, chargeInCombat = state.chargeInCombat,
        charge = DB().charge,
        victoryInMacro = state.victoryInMacro,
    }
end

-- Action buttons that hold the DTH Warrior macro get a picture of the next spell on top, because
-- the game's own macro icon shows the first spell whose conditions match, not the one it will cast.
local BAR_BUTTONS = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }
local overlays = {}
W.overlays = overlays

local function ButtonSlot(button)
    local slot = button.action
    if type(slot) ~= "number" and button.GetAttribute then slot = button:GetAttribute("action") end
    if type(slot) ~= "number" and button.GetPagedID then slot = button:GetPagedID() end
    return type(slot) == "number" and slot or nil
end

-- Finds the buttons with the macro and puts an overlay on each. New overlays are made only out of
-- combat; in combat (a stance change flips the bar) existing ones are just shown or hidden.
local function AllBarButtons()
    local list, seen = {}, {}
    local function add(button) if button and not seen[button] then seen[button] = true; list[#list + 1] = button end end
    for _, prefix in ipairs(BAR_BUTTONS) do
        for i = 1, 12 do add(_G[prefix .. i]) end
    end
    -- Newer clients keep every action button in this list.
    if ActionBarButtonEventsFrame and type(ActionBarButtonEventsFrame.frames) == "table" then
        for _, button in pairs(ActionBarButtonEventsFrame.frames) do add(button) end
    end
    return list
end

function W.RefreshButtons()
    if not GetActionInfo then return end
    local index = GetMacroIndexByName and GetMacroIndexByName(MACRO_NAME) or 0
    -- Saved for the log: what the game reports for every bar slot holding a macro.
    local facts, matched = {}, {}
    for slot = 1, 180 do
        local kind, id, subType = GetActionInfo(slot)
        if kind == "macro" then facts[#facts + 1] = slot .. "=" .. tostring(id) .. "/" .. tostring(subType) end
    end
    for _, overlay in pairs(overlays) do overlay.active = false end
    if index and index > 0 then
        for _, button in ipairs(AllBarButtons()) do
            do
                local slot = button and ButtonSlot(button)
                if slot then
                    local kind, id = GetActionInfo(slot)
                    local name = GetActionText and GetActionText(slot)
                    if kind == "macro" and (id == index or name == MACRO_NAME) then
                        matched[#matched + 1] = tostring(button.GetName and button:GetName() or "?") .. "@" .. slot
                        local overlay = overlays[button]
                        if not overlay and not Lockdown() then
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
    end
    for _, overlay in pairs(overlays) do overlay:SetShown(overlay.active and DB().buttonIcon and true or false) end
    local debug = DB().debug
    debug.buttons = string.format("macro index %s; macro slots %s; matched %s", tostring(index),
        table.concat(facts, " "), #matched > 0 and table.concat(matched, " ") or "none")
end

local function ShowOnButtons(spell)
    local texture = spell and SpellIcon(spell)
    for _, overlay in pairs(overlays) do
        overlay:SetShown(overlay.active and DB().buttonIcon and texture ~= nil or false)
        if overlay.active and texture then
            overlay.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
            overlay.icon:SetDesaturated(not spell)
        end
    end
end

-- Whether your target is casting or channeling. Values may be hidden in combat; a hidden value
-- still means a cast is there.
function W.TargetCasting()
    if not UnitExists("target") or not UnitCanAttack("player", "target") then return false end
    for _, fn in ipairs({ UnitCastingInfo, UnitChannelInfo }) do
        if fn then
            local ok, name = pcall(fn, "target")
            if ok and name ~= nil then return true end
        end
    end
    return false
end

-- The interrupt to press on its own key when the target casts: Shield Bash with a shield in
-- Battle or Defensive Stance, Pummel in Berserker Stance. A macro can't see enemy casts, and with
-- a cooldown in the macro every press would stop on it, so this is only a prompt on the icon.
function W.Interrupt(facts, ready)
    if not facts.casting then return nil end
    if facts.stance == BERSERKER then
        if facts.known["Pummel"] and ready("Pummel") then return "Pummel" end
    elseif facts.shield and facts.known["Shield Bash"] and ready("Shield Bash") then
        return "Shield Bash"
    end
end

local lastAlert = 0
local function UpdateHint()
    if not hint then return end
    local options = DB()
    if not W.IsWarrior() then hint:Hide(); return end
    local facts = HintFacts()
    local spell = W.NextSpell(facts, SpellReady)
    W.currentPick = spell
    ShowOnButtons(spell)
    facts.casting = W.TargetCasting()
    local interrupt = W.Interrupt(facts, SpellReady) or W.OwnKeyPrompt(facts, SpellReady)
    W.currentInterrupt = interrupt
    if interrupt then
        if GetTime() - lastAlert > 3 and PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
            PlaySound(SOUNDKIT.RAID_WARNING)
        end
        lastAlert = GetTime()
        hint:Show()
        hint.icon:SetTexture(SpellIcon(interrupt) or "Interface\\Icons\\INV_Misc_QuestionMark")
        hint.icon:SetDesaturated(false)
        hint.spell:SetText("|cffff3030" .. interrupt .. "!|r")
        hint.notes:SetText(facts.casting and W.Interrupt(facts, SpellReady)
            and ("|cffff3030Enemy is casting: press " .. interrupt .. "|r")
            or ("|cffff3030Press " .. interrupt .. " (its own key)|r"))
        return
    end
    local hostile = UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target")
    -- After a kill the icon also shows without a target, counting down Victory Rush.
    local victoryLeft = facts.victoryInMacro and W.BuffLeft(VICTORIOUS)
    local show = options.hint and (hostile or UnitAffectingCombat("player") or victoryLeft) or hint.unlocked
    hint:SetShown(show and true or false)
    if not show then return end
    local texture = spell and SpellIcon(spell)
    hint.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    hint.icon:SetDesaturated(not spell)
    local notes = {}
    if victoryLeft and victoryLeft ~= math.huge then
        notes[#notes + 1] = string.format("|cff40ff40Victory Rush: %d s. Your next press on an enemy casts it.|r", math.floor(victoryLeft))
    end
    local enemies = W.EnemyCount()
    if enemies >= 2 then notes[#notes + 1] = enemies .. " enemies" end
    if facts.known[SHOUT] and not facts.shoutLeft and facts.inCombat then notes[#notes + 1] = "|cffff8040No Battle Shout|r" end
    hint.spell:SetText(spell or (hint.unlocked and "Drag to move" or "Wait"))
    hint.notes:SetText(table.concat(notes, "\n"))
end

local function BuildHint()
    local options = DB()
    hint = CreateFrame("Frame", "DufforthTweaksHelperWarriorHint", UIParent)
    hint:SetSize(44, 44)
    local p = options.hintPoint
    hint:SetPoint(p and p[1] or "CENTER", UIParent, p and p[2] or "CENTER", p and p[3] or 0, p and p[4] or -160)
    hint:SetMovable(true); hint:SetClampedToScreen(true)
    hint:RegisterForDrag("LeftButton")
    hint:SetScript("OnDragStart", function(self) if self.unlocked then self:StartMoving() end end)
    hint:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relative, x, y = self:GetPoint()
        DB().hintPoint = { point, relative, x, y }
    end)
    hint.icon = hint:CreateTexture(nil, "ARTWORK")
    hint.icon:SetAllPoints()
    hint.spell = hint:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint.spell:SetPoint("TOP", hint, "BOTTOM", 0, -2)
    hint.notes = hint:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint.notes:SetPoint("LEFT", hint, "RIGHT", 6, 0)
    hint.notes:SetJustifyH("LEFT")
    hint:Hide()
    local elapsed = 0
    local ticker = CreateFrame("Frame")
    local guardedHint, guardedTick = W.Guard("icon", UpdateHint), W.Guard("log tick", function(step) W.LogTick(step) end)
    ticker:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < 0.1 then return end
        local step = elapsed
        elapsed = 0
        guardedHint()
        guardedTick(step)
    end)
end

-- Unlock to drag the icon; lock again to keep it in place and let clicks pass through.
function W.SetHintUnlocked(on)
    if not hint then return end
    hint.unlocked = on and true or false
    hint:EnableMouse(hint.unlocked)
    UpdateHint()
end
function W.HintUnlocked() return hint and hint.unlocked or false end

-- ---- Fight log ----
-- Each fight is saved in DufforthTweaksHelperDB.warrior.fights (the game writes the file on
-- /reload or logout), so the macro and the icon can be checked against real fights later.

local FIGHTS_KEPT = 40
local RAGE_CAP = 90 -- rage this high for a while means rage was wasted
W.FIGHTS_KEPT = FIGHTS_KEPT
local fight

local function Rage()
    if UnitPower then return Plain(UnitPower("player", 1)) or 0 end
    return UnitMana and UnitMana("player") or 0
end

local function TargetHealth()
    if not UnitExists("target") then return -1 end
    local most, now = Plain(UnitHealthMax("target")), Plain(UnitHealth("target"))
    if not most or not now or most <= 0 then return -1 end -- hidden or unknown
    return math.floor(now * 100 / most + 0.5)
end

-- The macro's text is stored once; fights point to it by number.
local function MacroId(body)
    local macros = DB().macros
    for i, text in ipairs(macros) do if text == body then return i end end
    macros[#macros + 1] = body
    return #macros
end

local function AddEnemy(unit)
    if not fight or not UnitExists(unit) or not UnitCanAttack("player", unit) then return end
    local key = tostring(Plain(UnitName(unit)) or "?") .. ":" .. tostring(Plain(UnitLevel(unit)) or 0)
    if not fight.seen[key] then
        fight.seen[key] = true
        fight.enemies[#fight.enemies + 1] = key
    end
end

function W.FightStart()
    if not DB().log or not W.IsWarrior() then return end
    local body = W.state.body
    fight = {
        at = time and time() or 0, start = GetTime(),
        zone = GetRealZoneText and GetRealZoneText() or "?", level = UnitLevel("player") or 0,
        group = (IsInGroup and IsInGroup()) or (GetNumGroupMembers and GetNumGroupMembers() > 0) or false,
        macro = body and MacroId(body) or 0, stance = W.CurrentStance(W.state.numbers or {}) or 0,
        rage = Rage(), casts = {}, errors = {}, enemies = {}, seen = {}, hitBy = {}, mostEnemies = 0,
        rageCapped = 0, shoutUp = 0, ticked = 0, result = "won", tries = {}, tried = {},
    }
    -- The pull: what was tried in the 6 seconds before combat started (Charge, first presses).
    for _, try in ipairs(W.preTries) do
        if fight.start - try.at <= 6 then
            fight.tries[#fight.tries + 1] = string.format("%.1f %s %s", try.at - fight.start, try.kind, try.name)
        end
    end
    W.preTries = {}
    AddEnemy("target")
end

function W.FightEnd()
    if not fight then return end
    local f = fight
    fight = nil
    f.seconds = math.floor((GetTime() - f.start) * 10 + 0.5) / 10
    f.start, f.seen = nil, nil
    f.rageCapped = math.floor(f.rageCapped * 10 + 0.5) / 10
    f.shoutUp = f.ticked > 0 and math.floor(f.shoutUp * 100 / f.ticked + 0.5) or 0 -- percent of the fight
    f.ticked = nil
    if #f.casts == 0 and f.seconds < 3 then return end -- a tap of combat, nothing to learn from
    local fights = DB().fights
    fights[#fights + 1] = f
    while #fights > FIGHTS_KEPT do table.remove(fights, 1) end
end

-- Every attempt: "seconds S name" sent to the server, "F name" failed, "Q name" failed quietly,
-- "I name" interrupted, "E message" an error on screen, "C name" cast. Kept per fight (up to 400),
-- plus the last few seconds before the fight (the pull) with negative times.
local MAX_TRIES = 400
W.preTries = {}
function W.LogTry(kind, name)
    if not name then return end
    if fight then
        if #fight.tries < MAX_TRIES then
            fight.tries[#fight.tries + 1] = string.format("%.1f %s %s", GetTime() - fight.start, kind, name)
        end
        local tried = fight.tried[name] or {}
        tried[kind] = (tried[kind] or 0) + 1
        fight.tried[name] = tried
    elseif DB().log and W.IsWarrior() then
        table.insert(W.preTries, { at = GetTime(), kind = kind, name = name })
        while #W.preTries > 30 do table.remove(W.preTries, 1) end
    end
end

function W.LogCast(spell)
    if spell == "Rend" and UnitGUID then
        local guid = Plain(UnitGUID("target"))
        if guid then W.rendAt[guid] = GetTime() end
    end
    if not fight or not spell then return end
    -- "seconds spell r<rage> h<target health %> n<enemies> p:<what the icon showed>"
    fight.casts[#fight.casts + 1] = string.format("%.1f %s r%d h%d n%d p:%s", GetTime() - fight.start, spell,
        Rage(), TargetHealth(), W.EnemyCount(), W.lastPrediction or "-")
end

function W.LogError(message)
    if not fight or not message then return end
    fight.errors[message] = (fight.errors[message] or 0) + 1
end

function W.LogDied() if fight then fight.result = "died" end end

-- Damage taken per enemy name, from the combat log.
function W.LogHit(name, amount)
    if not fight then return end
    name = name or "?"
    fight.hitBy[name] = (fight.hitBy[name] or 0) + (tonumber(Plain(amount)) or 0)
end

function W.LogTick(seconds)
    if not fight then return end
    fight.ticked = fight.ticked + seconds
    if Rage() >= RAGE_CAP then fight.rageCapped = fight.rageCapped + seconds end
    if W.BuffLeft(SHOUT) then fight.shoutUp = fight.shoutUp + seconds end
    local enemies = W.EnemyCount()
    if enemies > fight.mostEnemies then fight.mostEnemies = enemies end
    W.lastPrediction = W.NextSpell(HintFacts(), SpellReady)
end

function W.FightCount() return #DB().fights end
function W.ClearLog() DB().fights = {}; DB().macros = {} end

local logEvents = CreateFrame("Frame")
Listen(logEvents, { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_SPELLCAST_SUCCEEDED",
    "UI_ERROR_MESSAGE", "PLAYER_DEAD", "PLAYER_TARGET_CHANGED", "COMBAT_LOG_EVENT_UNFILTERED",
    "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED" })
logEvents:SetScript("OnEvent", W.Guard("fight log", function(_, event, a, b, c, ...)
    CountEvent(event)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not W.IsWarrior() or not CombatLogGetCurrentEventInfo then return end
        local _, subevent, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags, _, p12, _, _, p15 =
            CombatLogGetCurrentEventInfo()
        if subevent == "UNIT_DIED" then W.ForgetDead(destGUID); return end
        -- Swings put the amount 12th; spells put it 15th.
        W.CombatLog(subevent, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags,
            subevent == "SWING_DAMAGE" and p12 or (string.find(subevent, "_DAMAGE$") and p15 or 0))
    elseif event == "PLAYER_REGEN_DISABLED" then W.FightStart()
    elseif event == "PLAYER_REGEN_ENABLED" then W.FightEnd(); W.recent = {}
    elseif event == "PLAYER_DEAD" then W.LogDied()
    elseif event == "PLAYER_TARGET_CHANGED" then AddEnemy("target")
    elseif event == "UI_ERROR_MESSAGE" then
        local message = type(a) == "string" and a or b -- (type, message) or (message)
        W.LogError(message)
        W.LogTry("E", message and tostring(Plain(message) or "?"))
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" and a == "player" then
        local name = c and SpellName(c) -- (unit, castGUID, spellID)
        if not name and type(b) == "string" and not string.find(b, "-", 1, true) then name = b end -- old (unit, spellName)
        W.LogCast(name)
        W.LogTry("C", name)
    elseif event == "UNIT_SPELLCAST_SENT" and a == "player" then
        local spellID = ...  -- (unit, target, castGUID, spellID): a, b, c are the first three
        W.LogTry("S", spellID and SpellName(spellID) or tostring(c))
    elseif (event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" or event == "UNIT_SPELLCAST_INTERRUPTED") and a == "player" then
        local kind = event == "UNIT_SPELLCAST_FAILED" and "F" or (event == "UNIT_SPELLCAST_FAILED_QUIET" and "Q" or "I")
        W.LogTry(kind, c and SpellName(c) or "?") -- (unit, castGUID, spellID)
    end
end))

-- ---- Events ----

local events = CreateFrame("Frame")
Listen(events, { "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED",
    "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE", "UPDATE_SHAPESHIFT_FORMS", "UNIT_AURA",
    "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_SHAPESHIFT_FORM", "UPDATE_BONUS_ACTIONBAR",
    "PLAYER_EQUIPMENT_CHANGED", "GROUP_ROSTER_UPDATE" })
events:SetScript("OnEvent", W.Guard("macro events", function(_, event, unit)
    if event ~= "UNIT_AURA" then CountEvent(event) end
    if event == "PLAYER_LOGIN" then
        if W.IsWarrior() then BuildHint() end
        return
    end
    if not W.IsWarrior() then return end
    if event == "ACTIONBAR_SLOT_CHANGED" or event == "ACTIONBAR_PAGE_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM"
        or event == "UPDATE_BONUS_ACTIONBAR" then
        -- A new stance out of combat: also check where Charge works and rewrite if needed.
        if event == "UPDATE_SHAPESHIFT_FORM" and not Lockdown() then W.SafeUpdate() end
        W.RefreshButtons()
        return
    end
    if event == "UNIT_AURA" then
        if unit ~= "player" then return end
        local now = GetTime()
        if W.lastAura and now - W.lastAura < 1 then return end -- buffs change often; once a second is plenty
        W.lastAura = now
    end
    if event == "PLAYER_REGEN_ENABLED" or not Lockdown() then W.SafeUpdate(); W.RefreshButtons() end
end))
