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
-- blocks). Battle Stance: Execute once learned, else Overpower. Execute is refused until the
-- target is under 20%, and while refused it takes the stance's one try, but that try was wasted
-- anyway: in 22 real Battle Stance fights Overpower was refused 129 times and cast once (user:
-- "Execute is not in the rotation", 2026-11-12). With Mortal Strike or Bloodthirst, Execute stays an
-- own-key prompt on the icon, because there it would block the big attack. Rend and Battle Shout go
-- first, once each. Victory Rush can't share the button outside the after-kill line, so the icon
-- tells you when to press it on its own key, like Shield Bash.
local LINES = {
    { { spell = "Charge" }, { spell = "Intercept" }, { spell = "Battle Shout" }, { spell = "Rend" },
      { spell = "Revenge" }, { spell = "Sunder Armor" }, { spell = "Shield Slam" }, { spell = "Shield Block" },
      { spell = "Overpower" }, { spell = "Execute" }, { spell = "Bloodrage" }, { spell = "Mortal Strike" }, { spell = "Bloodthirst" }, { spell = "Whirlwind" },
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
    o.cooldowns = o.cooldowns or {} -- spell -> cooldown seconds, learned out of combat
    o.gear = o.gear or {} -- distinct gear and stat sets; fights point at one (fight.gear)
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
    -- Victory Rush is not in the button (2026-11-11, user: "remove vr from the rotation, this will be
    -- casted on demand"); the icon still prompts it for its own key when it can be cast.
    -- Battle Shout: written while the buff is missing or has under SHOUT_KEEP_SECONDS left, once per
    -- fight. reset=combat, because reset=120 restarted its timer on every press and often never
    -- re-armed between pulls (Battle Shout was up 86% of the last 30 fights).
    if options.shout and known[SHOUT] then out[#out + 1] = "/castsequence reset=combat " .. SHOUT .. ",nil" end
    -- Rend in Battle Stance only, once per pull (2026-11-11, user agreed): in Defensive it did 33
    -- damage a cast (3.3 per rage point, Revenge 23) and took the global-cooldown try from Revenge.
    -- reset=combat, because reset=N restarts its timer on every press and never re-armed it.
    if known["Rend"] and numbers[BATTLE] then
        out[#out + 1] = string.format("/castsequence [form:%d] reset=combat Rend,nil", numbers[BATTLE])
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
    -- Sunder Armor only in a group (threat), or when it's the only attack Defensive Stance has (no
    -- shield). Solo it gave ~2 damage per rage point against Heroic Strike's 7.6 (user: "remove it",
    -- 2026-11-11; tools/sunder_value.py).
    local hasRevenge = defensive[#defensive] == "Revenge" or defensive[1] == "Shield Slam"
    if known["Sunder Armor"] and (options.group or not hasRevenge) then defensive[#defensive + 1] = "Sunder Armor" end
    if #defensive > 0 and filler then defensive[#defensive + 1] = filler end
    Line(DEFENSIVE, defensive)
    local battleBig = BigAttack(known, BATTLE)
    if battleBig then Line(BATTLE, filler and { battleBig, filler } or { battleBig })
    elseif known["Execute"] then Line(BATTLE, { "Execute" })
    elseif known["Overpower"] then Line(BATTLE, { "Overpower" }) end
    local berserkerBig = BigAttack(known, BERSERKER)
    if berserkerBig then Line(BERSERKER, filler and { berserkerBig, filler } or { berserkerBig })
    elseif known["Execute"] then Line(BERSERKER, { "Execute" }) end

    -- Off the global cooldown again.
    if options.shield and known["Shield Block"] and numbers[DEFENSIVE] then
        out[#out + 1] = "/cast [form:" .. numbers[DEFENSIVE] .. "] Shield Block"
    end
    -- Heroic Strike on every press where no sequence above already uses it (Battle Stance at low level).
    if filler and numbers[BATTLE] and not battleBig then out[#out + 1] = "/cast [form:" .. numbers[BATTLE] .. "] " .. filler end
    -- Bloodrage: free rage, off the global cooldown, so it never takes another spell's try; on its
    -- one-minute cooldown the game just skips it. "Not enough rage" was the most common error in
    -- every stance (user asked for it, 2026-11-12). In combat only, so it isn't spent before a pull.
    -- Once per fight: a castsequence at "nil" is skipped silently, so after Bloodrage goes off the
    -- button stops asking for it (it was refused 15-26 times a fight on its cooldown).
    -- No space after "]": the game trims it, and it keeps the level 26 macro at 255 characters.
    if known["Bloodrage"] then out[#out + 1] = "/castsequence [combat]reset=combat Bloodrage,nil" end
    return out
end

-- The macro text, at most 255 characters: if it's longer, the least important lines go first.
local DROP_FIRST = { "Bloodrage", "Rend", "Charge", "Battle Shout" }
-- With Victory Rush in (right after a kill), Charge goes first: you are usually close already.
local DROP_FIRST_VICTORY = { "Bloodrage", "Charge", "Battle Shout", "Rend" }
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
    -- Victory Rush is cast on demand (its own key), never written into the button.
    local victoryLeft = W.BuffLeft(VICTORIOUS)
    state.victoryLeft = victoryLeft
    local victorious = false
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

-- Seconds until a spell's cooldown ends (0 = ready). The game hides cooldowns in combat, so the
-- addon learns each spell's cooldown when it can read it (out of combat) and, in combat, counts
-- from its last cast. Learned lengths are kept in DufforthTweaksHelperDB.warrior.cooldowns.
W.lastCastAt = {}
function W.CooldownLeft(name, now)
    now = now or GetTime()
    local start, duration = SpellCooldown(name)
    start, duration = Plain(start), Plain(duration)
    if start and duration then
        if start > 0 and duration > 1.5 then -- 1.5 s is the global cooldown
            local learned = DB().cooldowns
            if not learned[name] or duration > learned[name] then learned[name] = duration end
            return math.max(0, start + duration - now)
        end
        return 0
    end
    local at, length = W.lastCastAt[name], DB().cooldowns[name]
    if at and length then return math.max(0, at + length - now) end
    return 0
end

local function SpellReady(name)
    local usable, noMana = SpellUsable(name)
    usable, noMana = Plain(usable), Plain(noMana)
    if usable == false or noMana then return false end
    if W.CooldownLeft(name) > 0 then return false end
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
    if facts.stance == BATTLE and not facts.rendOnTarget and ok("Rend") then return "Rend" end
    if facts.stance == DEFENSIVE then
        if facts.shield and ok("Shield Block") then return "Shield Block" end
        for _, name in ipairs({ "Shield Slam", "Revenge", "Sunder Armor" }) do
            local sunderFits = name == "Sunder Armor" and (facts.inGroup or not facts.shield) -- same rule as the macro
            if ((facts.shield and name ~= "Sunder Armor") or sunderFits) and ok(name) then return name end
        end
    elseif facts.stance == BATTLE then
        local big = BigAttack(known, BATTLE)
        if big and ok(big) then return big end
        if not big and known["Execute"] then
            if ok("Execute") then return "Execute" end
        elseif ok("Overpower") then return "Overpower" end
    elseif facts.stance == BERSERKER then
        local big = BigAttack(known, BERSERKER)
        if big and ok(big) then return big end
        if not big and known["Execute"] and ok("Execute") then return "Execute" end
    end
    local filler = (facts.inGroup and known["Cleave"]) and "Cleave" or "Heroic Strike"
    if ok(filler) then return filler end
end

-- While the button holds the after-kill Victory Rush, pressing Victory Rush on its own key would
-- break the rotation for the rest of that fight, so the icon says not to.
local VICTORY_WARNING = "|cffffd100Victory Rush is on the button: don't use its key|r"
function W.VictoryWarning(facts)
    if facts.victoryInMacro and facts.known["Victory Rush"] then return VICTORY_WARNING end
end

-- Spells for their own key, shown on the icon when they can be cast: they can't share the button,
-- because the game would try them first on every press and skip the rest while they can't be cast.
function W.OwnKeyPrompt(facts, ready)
    -- When the macro already has it (a kill before this pull), the button casts it: no prompt.
    if facts.known["Victory Rush"] and not facts.victoryInMacro and ready("Victory Rush") then return "Victory Rush" end
    -- Execute: only when the button doesn't have it (with Mortal Strike, Bloodthirst or Whirlwind).
    local big = facts.stance == BATTLE and BigAttack(facts.known, BATTLE) or facts.stance == BERSERKER and BigAttack(facts.known, BERSERKER)
    if facts.known["Execute"] and big and ready("Execute") then return "Execute" end
end

-- ---- Following the button's castsequence (what the next press really does) ----
-- The proven rule: per press the game tries only the first global-cooldown spell the macro's lines
-- give (cast or rejected), while off-global-cooldown spells are tried on every press. A
-- /castsequence line gives the spell at its current step, which lives inside the game, so this
-- keeps its own copy of each step: a cast of the step's spell moves it on (Heroic Strike and Cleave
-- when queued), "nil" stays until a reset, the end wraps to the start. reset=N starts over after N
-- seconds without a press (every press counts, so pressing through a fight never resets it),
-- reset=combat when a fight ends. A /reload starts every sequence over, in the game and here.
local OFF_GCD = { ["Shield Block"] = true, ["Heroic Strike"] = true, ["Cleave"] = true, ["Charge"] = true,
    ["Intercept"] = true, ["Bloodrage"] = true, ["Berserker Rage"] = true, ["Pummel"] = true,
    ["Shield Bash"] = true, ["Recklessness"] = true, ["Shield Wall"] = true, ["Retaliation"] = true }
W.OFF_GCD = OFF_GCD
local ON_SWING = { ["Heroic Strike"] = true, ["Cleave"] = true } -- the step moves when they're queued
W.sequences = {} -- sequence text -> { index = n, used = GetTime() of the last press }

local function Trim(text) return (string.gsub(text or "", "^%s*(.-)%s*$", "%1")) end

-- One condition list ("nocombat,form:1/2") against the facts; unknown conditions count as met.
local function ConditionsMet(list, facts)
    for word in string.gmatch(list, "[^,]+") do
        word = Trim(word)
        local no, name, value = string.match(word, "^(n?o?)(%a+):?(.*)$")
        local met = true
        if name == "combat" then
            met = facts.inCombat and true or false
        elseif name == "form" or name == "stance" then
            met = false
            if value == "" then met = (facts.stance or 0) > 0 end
            for number in string.gmatch(value, "%d+") do
                if tonumber(number) == facts.stance then met = true end
            end
        end
        if no == "no" then met = not met end
        if not met then return false end
    end
    return true
end

-- The text a /cast or /castsequence line acts on right now, or nil. Uses the game's own parser
-- when there is one.
function W.LineAction(args, facts)
    if SecureCmdOptionParse then
        local ok, action = pcall(SecureCmdOptionParse, args)
        if ok then return action ~= nil and action ~= "" and action or nil end
    end
    for clause in string.gmatch(args .. ";", "([^;]*);") do
        clause = Trim(clause)
        local any, open = false, false
        local rest = string.gsub(clause, "%[([^%]]*)%]", function(list)
            open = true
            if ConditionsMet(list, facts) then any = true end
            return ""
        end)
        if not open or any then
            rest = Trim(rest)
            return rest ~= "" and rest or nil
        end
    end
end

local function SplitSequence(text)
    local reset, list = string.match(text, "^reset=(%S+)%s+(.*)$")
    if not reset then list = text end
    local spells = {}
    for name in string.gmatch(list, "[^,]+") do spells[#spells + 1] = Trim(name) end
    return reset, spells
end

local function SequenceEntry(text, now)
    local entry = W.sequences[text]
    if not entry then entry = { index = 1 }; W.sequences[text] = entry end
    local reset = SplitSequence(text)
    local seconds = reset and tonumber(string.match(reset, "%d+"))
    if seconds and entry.used and now - entry.used > seconds then entry.index = 1 end
    return entry
end

-- The spell a sequence gives on the next press ("nil" gives nothing).
function W.SequenceNext(text, now)
    if QueryCastSequence then
        local ok, name = pcall(QueryCastSequence, text)
        if ok and type(name) == "string" and name ~= "" then W.queryWorks = true; return name ~= "nil" and name or nil end
    end
    local _, spells = SplitSequence(text)
    local name = spells[SequenceEntry(text, now).index]
    if name == "nil" then return nil end
    return name
end

-- The macro's /cast and /castsequence lines: { kind = "cast"|"castsequence", args = "..." }.
function W.ParseMacro(body)
    local lines = {}
    for line in string.gmatch((body or "") .. "\n", "([^\n]*)\n") do
        local command, args = string.match(Trim(line), "^/(%a+)%s+(.+)$")
        if command == "cast" or command == "castsequence" then lines[#lines + 1] = { kind = command, args = args } end
    end
    return lines
end

-- What the next press does. Returns the global-cooldown spell it tries (gcd) and the first ready
-- off-global-cooldown spell it casts (off).
function W.MacroNext(lines, facts, ready, now)
    local gcd, off
    for _, line in ipairs(lines) do
        local action = W.LineAction(line.args, facts)
        local spell = action
        if action and line.kind == "castsequence" then spell = W.SequenceNext(action, now) end
        if spell then
            if OFF_GCD[spell] then
                -- Bloodrage is background rage: the icon shows what you're fighting with instead.
                if not off and spell ~= "Bloodrage" and ready(spell) then off = spell end
            elseif not gcd then
                gcd = spell
            end
        end
    end
    return gcd, off
end

-- A press happened (any try): every sequence the macro reached is used now.
function W.SequencePressed(lines, facts, now)
    for _, line in ipairs(lines) do
        if line.kind == "castsequence" then
            local action = W.LineAction(line.args, facts)
            if action then SequenceEntry(action, now).used = now end
        end
    end
end

-- A spell went off (kind "C") or was queued (kind "S", for Heroic Strike and Cleave): sequences
-- waiting on it move to their next step.
function W.SequenceCast(lines, facts, name, kind, now)
    if not name then return end
    if (ON_SWING[name] or false) ~= (kind == "S") then return end
    for _, line in ipairs(lines) do
        if line.kind == "castsequence" then
            local action = W.LineAction(line.args, facts)
            if action then
                local entry = SequenceEntry(action, now)
                local _, spells = SplitSequence(action)
                if spells[entry.index] == name then
                    entry.index = entry.index + 1
                    if entry.index > #spells then entry.index = 1 end
                end
                entry.used = now
            end
        end
    end
end

-- A fight ended: sequences with reset=combat start over.
function W.SequenceCombatEnded()
    for text, entry in pairs(W.sequences) do
        local reset = SplitSequence(text)
        if reset and string.find(reset, "combat", 1, true) then entry.index = 1 end
    end
end

-- The icon's pick, and a note when the button's next spell can't be cast yet.
-- Returns spell, ready (bool), note.
local WHY_NOT_READY = {
    ["Revenge"] = "needs a block, dodge or parry first",
    ["Overpower"] = "needs the enemy to dodge first",
    ["Victory Rush"] = "needs a kill first",
    ["Execute"] = "needs the enemy under 20% health",
}
function W.ButtonPick(lines, facts, ready, now)
    local gcd, off = W.MacroNext(lines, facts, ready, now)
    if gcd and ready(gcd) then return gcd, true end
    local why = gcd and (WHY_NOT_READY[gcd] or "not ready yet")
    if off then
        return off, true, gcd and string.format("|cffc0c0c0Then %s (%s)|r", gcd, why) or nil
    end
    if gcd then
        return gcd, false, string.format("|cffc0c0c0%s %s: this press only auto-attacks|r", gcd, why)
    end
end

function W.MacroLines()
    local body
    if GetMacroInfo and GetMacroIndexByName and (GetMacroIndexByName(MACRO_NAME) or 0) > 0 then
        local ok, _, _, text = pcall(GetMacroInfo, MACRO_NAME)
        if ok and type(text) == "string" then body = text end
    end
    if not body and W.state.lines then body = table.concat(W.state.lines, "\n") end
    return W.ParseMacro(body)
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

local function ShowOnButtons(spell, ready)
    local texture = spell and SpellIcon(spell)
    for _, overlay in pairs(overlays) do
        overlay:SetShown(overlay.active and DB().buttonIcon and texture ~= nil or false)
        if overlay.active and texture then
            overlay.icon:SetTexture(texture)
            overlay.icon:SetDesaturated(not ready)
        end
    end
end

-- The icon's pick: the button's real next step when the macro is known, else the best ready spell.
-- Returns spell, ready, note.
function W.Pick(facts)
    local lines = W.MacroLines()
    if #lines > 0 then return W.ButtonPick(lines, facts, SpellReady, GetTime()) end
    local spell = W.NextSpell(facts, SpellReady)
    return spell, spell ~= nil
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

-- A curse on you (or a "Bane"): its name, else nil. Shatter Curse is only suggested, never in the button.
-- Forever blocks reading auras in combat ("Auras cannot be accessed when secret while tainted"), and
-- an error here once froze the icon on Charge (2026-11-12). So the read is protected, hidden values
-- are dropped, and once the game blocks it the check rests until the fight ends.
local CLEANSE = "Shatter Curse"
local curseBlocked = false

local function ReadCurse()
    for i = 1, 40 do
        local name, kind
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HARMFUL")
            if not aura then return nil end
            name, kind = Plain(aura.name), Plain(aura.dispelName)
        elseif UnitDebuff then
            local n, _, _, k = UnitDebuff("player", i)
            if not n then return nil end
            name, kind = Plain(n), Plain(k)
        else
            return nil
        end
        if kind == "Curse" or (type(name) == "string" and string.find(name, "Bane", 1, true)) then return name end
    end
    return nil
end

-- In combat the aura list can't be read, so curses are also tracked from UNIT_AURA's own report of
-- what was added and removed (updateInfo). Whether Forever lets an addon read that report in combat
-- is unknown: DB().debug.auraSignal counts readable and hidden reports to find out.
W.curses = {}
function W.TrackCurse(updateInfo)
    if type(updateInfo) ~= "table" then return end
    local signal = DB().debug.auraSignal or { reports = 0, readable = 0, hidden = 0, curses = 0 }
    DB().debug.auraSignal = signal
    signal.reports = signal.reports + 1
    if updateInfo.isFullUpdate then W.curses = {} end
    for _, aura in ipairs(updateInfo.addedAuras or {}) do
        local id, name, kind = Plain(aura.auraInstanceID), Plain(aura.name), Plain(aura.dispelName)
        if id == nil or (name == nil and kind == nil) then
            signal.hidden = signal.hidden + 1
        else
            signal.readable = signal.readable + 1
            if kind == "Curse" or (type(name) == "string" and string.find(name, "Bane", 1, true)) then
                W.curses[id] = name or "Curse"
                signal.curses = signal.curses + 1
            end
        end
    end
    for _, id in ipairs(updateInfo.removedAuraInstanceIDs or {}) do
        local plain = Plain(id)
        if plain ~= nil then W.curses[plain] = nil end
    end
end

function W.CurseOnYou()
    local fighting = UnitAffectingCombat and UnitAffectingCombat("player")
    if not fighting then curseBlocked = false end
    for _, name in pairs(W.curses) do return name end -- seen through aura events (works in combat if allowed)
    if curseBlocked then return nil end
    local ok, name = pcall(ReadCurse)
    if not ok then
        curseBlocked = true -- blocked in this fight: don't keep asking
        return nil
    end
    return name
end

function W.CursePrompt(facts, ready, curse)
    if curse and facts.known[CLEANSE] and ready(CLEANSE) then return CLEANSE end
    return nil
end

-- Before a pull: whether Charge would land now (user: Charge failed with "Out of range" or "Target too
-- close" when pressed at the wrong distance, 2026-11-13). inRange: the game's range check; close:
-- within about 10 yards (Charge needs 8 to 25).
function W.ChargeNote(inRange, close)
    if inRange then return "|cff40ff40In Charge range|r" end
    if close then return "|cffff8040Too close to Charge|r" end
    return "|cffaaaaaaGet closer to Charge|r"
end

local lastAlert = 0
local function UpdateHint()
    if not hint then return end
    local options = DB()
    if not W.IsWarrior() then hint:Hide(); return end
    local facts = HintFacts()
    local spell, ready, pickNote = W.Pick(facts)
    W.currentPick = spell
    ShowOnButtons(spell, ready)
    facts.casting = W.TargetCasting()
    local curse = W.CurseOnYou()
    local cleanse = W.CursePrompt(facts, SpellReady, curse)
    local interrupt = W.Interrupt(facts, SpellReady) or cleanse or W.OwnKeyPrompt(facts, SpellReady)
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
        hint.notes:SetText(facts.casting and W.Interrupt(facts, SpellReady) and "|cffff3030Enemy casting|r"
            or interrupt == cleanse and ("|cffc080ff" .. curse .. "|r") or "|cffff3030Own key|r")
        return
    end
    local hostile = UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target")
    -- After a kill the icon also shows without a target, counting down Victory Rush.
    local victoryLeft = facts.victoryInMacro and W.BuffLeft(VICTORIOUS)
    local show = options.hint and (hostile or UnitAffectingCombat("player") or victoryLeft) or hint.unlocked
    hint:SetShown(show and true or false)
    if not show then return end
    local texture = spell and SpellIcon(spell)
    if not texture and not hint.unlocked then hint:Hide(); return end -- nothing to show: no question mark, no placeholder text
    hint.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    hint.icon:SetDesaturated(not ready)
    local notes = {}
    if pickNote then notes[#notes + 1] = pickNote end
    if victoryLeft and victoryLeft ~= math.huge then
        notes[#notes + 1] = string.format("|cff40ff40Victory Rush %ds|r", math.floor(victoryLeft))
    end
    -- Guard: a Victory Rush pressed on its own key now would leave the button's Victory Rush line
    -- waiting all fight (the macro can't change in combat), and the rotation would stop.
    local warning = W.VictoryWarning(facts)
    if warning then notes[#notes + 1] = warning end
    local enemies = W.EnemyCount()
    if enemies >= 2 then notes[#notes + 1] = enemies .. " enemies" end
    if spell == "Charge" and not facts.inCombat and hostile then
        local close = CheckInteractDistance and CheckInteractDistance("target", 3) and true or false
        notes[#notes + 1] = W.ChargeNote(SpellInRange("Charge"), close)
    end
    if facts.known[SHOUT] and not facts.shoutLeft and facts.inCombat then notes[#notes + 1] = "|cffff8040No Battle Shout|r" end
    hint.spell:SetText(hint.unlocked and "Drag to move" or (ready and spell or ("|cff909090" .. spell .. "|r")))
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
    -- Notes go under the spell name (the user's choice), centered, short.
    hint.notes = hint:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint.notes:SetPoint("TOP", hint.spell, "BOTTOM", 0, -2)
    hint.notes:SetWidth(200)
    hint.notes:SetJustifyH("CENTER")
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
if DufforthTweaksHelper.RegisterMovable then
    DufforthTweaksHelper.RegisterMovable({ label = "Warrior icon", get = function() return hint end,
        enter = function() W.SetHintUnlocked(true) end, leave = function() W.SetHintUnlocked(false) end })
end

-- ---- Fight log ----
-- Each fight is saved in DufforthTweaksHelperDB.warrior.fights (the game writes the file on
-- /reload or logout), so the macro and the icon can be checked against real fights later.

local FIGHTS_KEPT = 300 -- about 1.7 KB each; tools/archive_warrior_fights.py copies them to a history file that keeps all
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

-- ---- Gear, weapon and stats (for gear and stat advice later) ----
-- Read out of combat (values can be hidden in combat) whenever the macro is checked or gear
-- changes, kept once per distinct set in DufforthTweaksHelperDB.warrior.gear, and each fight
-- points at the set it was fought with (fight.gear).
local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    for i = 2, #results do results[i] = Plain(results[i]) end
    return unpack(results, 2)
end

local SLOT_NAMES = { [1] = "head", [2] = "neck", [3] = "shoulder", [5] = "chest", [6] = "waist", [7] = "legs",
    [8] = "feet", [9] = "wrist", [10] = "hands", [11] = "finger1", [12] = "finger2", [13] = "trinket1",
    [14] = "trinket2", [15] = "back", [16] = "mainhand", [17] = "offhand", [18] = "ranged" }
local STAT_NAMES = { "strength", "agility", "stamina", "intellect", "spirit" }

function W.Snapshot()
    local s = { level = Read(UnitLevel, "player") or 0, items = {}, stats = {} }
    for slot, name in pairs(SLOT_NAMES) do
        local link = Read(GetInventoryItemLink, "player", slot)
        if type(link) == "string" then
            local id, enchant = string.match(link, "item:(%d+):?(%d*)")
            s.items[name] = { id = tonumber(id), enchant = tonumber(enchant) or 0, name = string.match(link, "%[(.-)%]") }
        end
    end
    for i, name in ipairs(STAT_NAMES) do
        local _, effective = Read(UnitStat, "player", i)
        s.stats[name] = effective
    end
    local _, armor = Read(UnitArmor, "player")
    s.stats.armor = armor
    local base, plus, minus = Read(UnitAttackPower, "player")
    s.stats.attackPower = base and (base + (plus or 0) + (minus or 0)) or nil
    s.stats.crit = Read(GetCritChance)
    s.stats.dodge = Read(GetDodgeChance)
    s.stats.parry = Read(GetParryChance)
    s.stats.block = Read(GetBlockChance)
    s.stats.blockValue = Read(GetShieldBlock)
    s.stats.health = Read(UnitHealthMax, "player")
    local speed = Read(UnitAttackSpeed, "player")
    local low, high = Read(UnitDamage, "player")
    s.weapon = { speed = speed, low = low, high = high,
        dps = (speed and low and high and speed > 0) and math.floor((low + high) / 2 / speed * 10 + 0.5) / 10 or nil }
    return s
end

local function SnapshotKey(s)
    local parts = { tostring(s.level) }
    local names = {}
    for name in pairs(s.items) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do parts[#parts + 1] = name .. "=" .. s.items[name].id .. ":" .. s.items[name].enchant end
    return table.concat(parts, ",")
end

-- Buffs raise stats for a while, so a set keeps the lowest value seen for each stat (about the
-- unbuffed value) and the highest seen as statsBuffed.
local function MergeStats(saved, now)
    saved.statsBuffed = saved.statsBuffed or {}
    for name, value in pairs(now.stats) do
        if type(value) == "number" then
            if type(saved.stats[name]) ~= "number" or value < saved.stats[name] then saved.stats[name] = value end
            if type(saved.statsBuffed[name]) ~= "number" or value > saved.statsBuffed[name] then saved.statsBuffed[name] = value end
        end
    end
    if not saved.weapon.dps and now.weapon.dps then saved.weapon = now.weapon end
end

-- Saves the current set if it's new; W.gearId is the set the next fight uses.
function W.TrackGear()
    if Lockdown() or (UnitAffectingCombat and UnitAffectingCombat("player")) then return end
    local s = W.Snapshot()
    s.key = SnapshotKey(s)
    local gear = DB().gear
    for i, saved in ipairs(gear) do
        if saved.key == s.key then MergeStats(saved, s); W.gearId = i; return i end
    end
    s.at = time and time() or 0
    s.statsBuffed = {}
    for name, value in pairs(s.stats) do s.statsBuffed[name] = value end
    gear[#gear + 1] = s
    W.gearId = #gear
    return W.gearId
end

-- Talent points per tree, "Arms 10 / Fury 0 / Protection 7". Classic returns (name, icon, points,
-- ...), newer clients (id, name, description, icon, points, ...): the name is the first text and the
-- points the first number up to 61 after it.
function W.TalentText()
    if not (GetNumTalentTabs and GetTalentTabInfo) then return "?" end
    local parts = {}
    for tab = 1, GetNumTalentTabs() or 0 do
        local values = { GetTalentTabInfo(tab) }
        local name, points
        for i = 1, #values do
            local v = Plain(values[i])
            if not name and type(v) == "string" then name = v
            elseif name and not points and type(v) == "number" and v >= 0 and v <= 61 then points = v end
        end
        parts[#parts + 1] = (name or ("Tree " .. tab)) .. " " .. (points or "?")
    end
    return #parts > 0 and table.concat(parts, " / ") or "?"
end

-- "2H", "1H+shield", "dual wield", "1H" or "none" from what's in your hands.
function W.WeaponSetup()
    local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local function loc(slot)
        local id = GetInventoryItemID and GetInventoryItemID("player", slot)
        if not id or not getInfo then return nil end
        local _, _, _, equipLoc = getInfo(id)
        return equipLoc
    end
    local main, off = loc(16), loc(17)
    if main == "INVTYPE_2HWEAPON" then return "2H" end
    if off == "INVTYPE_SHIELD" then return "1H+shield" end
    if off == "INVTYPE_WEAPON" or off == "INVTYPE_WEAPONOFFHAND" then return "dual wield" end
    return main and "1H" or "none"
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
        character = DufforthTweaksHelper.CharacterKey and DufforthTweaksHelper.CharacterKey() or "?",
        zone = GetRealZoneText and GetRealZoneText() or "?", level = UnitLevel("player") or 0,
        group = (IsInGroup and IsInGroup()) or (GetNumGroupMembers and GetNumGroupMembers() > 0) or false,
        macro = body and MacroId(body) or 0, stance = W.CurrentStance(W.state.numbers or {}) or 0,
        rage = Rage(), casts = {}, errors = {}, enemies = {}, seen = {}, hitBy = {}, mostEnemies = 0,
        rageCapped = 0, shoutUp = 0, ticked = 0, result = "won", tries = {}, tried = {},
        gear = W.gearId or 0, manual = {}, -- manual: spells cast that the macro doesn't have (own keys)
    }
    -- Spec and weapons, to compare Prot or Arms and shield or two-hander from real fights.
    local okTalents, talents = pcall(W.TalentText)
    fight.talents = okTalents and talents or "?"
    local okSetup, setup = pcall(W.WeaponSetup)
    fight.setup = okSetup and setup or "?"
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
    -- The combat log is closed on Forever; the game's own damage meter may still be readable once
    -- the fight is over. Give it a moment to finish, then try.
    if C_Timer then C_Timer.After(1.5, W.Guard("damage meter", function() W.AfterFight(f) end)) else W.AfterFight(f) end
end

-- ---- The game's damage meter (discovery) ----
-- Forever closes COMBAT_LOG_EVENT_* to addons and hides health in combat, so per-spell damage can
-- only come from the built-in damage meter (C_DamageMeter on this engine), if it lets addons read
-- it. Its shape here isn't known yet, so this records what it offers (debug.damageMeter) and keeps
-- whatever readable numbers a call returns on the fight (fight.damage). Secret values are dropped.
local function Dump(value, depth, budget)
    budget.left = budget.left - 1
    if budget.left < 0 then return "..." end
    value = Plain(value)
    local kind = type(value)
    if kind == "nil" then return "<hidden or nil>" end
    if kind ~= "table" then return kind == "function" and "<function>" or value end
    if depth <= 0 then return "<table>" end
    local out = {}
    for key, item in pairs(value) do
        key = Plain(key)
        if key ~= nil then out[tostring(key)] = Dump(item, depth - 1, budget) end
    end
    return out
end
W.DumpForLog = Dump

function W.ProbeDamageMeter(fight)
    local meter = C_DamageMeter
    local debug = DB().debug
    if type(meter) ~= "table" then
        debug.damageMeter = { available = false }
        return
    end
    local api = {}
    for name, item in pairs(meter) do
        if type(item) == "function" then api[#api + 1] = name end
    end
    table.sort(api)
    local enums = {}
    if Enum then
        for name, values in pairs(Enum) do
            if type(name) == "string" and string.find(name, "DamageMeter", 1, true) and type(values) == "table" then
                enums[name] = Dump(values, 1, { left = 60 })
            end
        end
    end
    -- Only no-argument getters, and the session getters with every enum pair: reading, never changing.
    local results, budget = {}, { left = 600 }
    for _, name in ipairs(api) do
        if string.find(name, "^Get") or string.find(name, "^Is") or string.find(name, "^Has") then
            local ok, a, b = pcall(meter[name])
            results[name .. "()"] = ok and { Dump(a, 4, budget), Dump(b, 2, budget) } or ("error: " .. tostring(a))
        end
    end
    local sessionTypes = Enum and Enum.DamageMeterSessionType
    local meterTypes = Enum and Enum.DamageMeterType
    if type(sessionTypes) == "table" and type(meterTypes) == "table" then
        for _, getter in ipairs({ "GetCombatSessionFromType", "GetCombatSessionSourceFromType" }) do
            if type(meter[getter]) == "function" then
                for sessionName, sessionValue in pairs(sessionTypes) do
                    for meterName, meterValue in pairs(meterTypes) do
                        if meterName == "DamageDone" or meterName == "Dps" then
                            local ok, a = pcall(meter[getter], sessionValue, meterValue, UnitGUID and UnitGUID("player"))
                            results[getter .. "(" .. tostring(sessionName) .. "," .. tostring(meterName) .. ")"] =
                                ok and Dump(a, 5, budget) or ("error: " .. tostring(a))
                        end
                    end
                end
            end
        end
    end
    debug.damageMeter = { available = true, api = table.concat(api, ", "), enums = enums, results = results,
        at = time and time() or 0 }
end

-- Proven on Forever (2026-11-11): right after a fight, C_DamageMeter's "Current" session is that
-- fight, and GetCombatSessionSourceFromType(Current, DamageDone, <your GUID>).combatSpells lists
-- { spellID, totalAmount, amountPerSecond } per spell. Saved on the fight as
-- spellDamage = { ["Rend"] = 40, ["Auto Attack"] = 290, ... }, damageTotal and damageSeconds.
function W.ReadFightDamage(fight)
    local meter = C_DamageMeter
    local sessions, types = Enum and Enum.DamageMeterSessionType, Enum and Enum.DamageMeterType
    if type(meter) ~= "table" or type(sessions) ~= "table" or type(types) ~= "table" then return false end
    if type(meter.GetCombatSessionSourceFromType) ~= "function" then return false end
    local ok, source = pcall(meter.GetCombatSessionSourceFromType, sessions.Current, types.DamageDone,
        UnitGUID and UnitGUID("player"))
    if not ok or type(source) ~= "table" or type(source.combatSpells) ~= "table" then return false end
    local spells = {}
    for _, row in pairs(source.combatSpells) do
        local id, amount = Plain(row.spellID), Plain(row.totalAmount)
        if id and type(amount) == "number" then
            local name = SpellName(id) or ("spell " .. tostring(id))
            spells[name] = (spells[name] or 0) + amount
        end
    end
    fight.spellDamage = spells
    fight.damageTotal = Plain(source.totalAmount)
    if type(meter.GetCombatSessionFromType) == "function" then
        local okSession, session = pcall(meter.GetCombatSessionFromType, sessions.Current, types.DamageDone)
        if okSession and type(session) == "table" then fight.damageSeconds = Plain(session.durationSeconds) end
    end
    W.ReadDamageTaken(fight, meter, sessions, types)
    return true
end

-- Damage you took this fight (Enum.DamageMeterType.DamageTaken = 7 on Forever): rage from being hit
-- is 2.5 x damage / c(level), most of a tank's rage. Saved as damageTaken and takenBy = { name = amount }
-- (enemy or its spell, whichever the meter names). The meter's row shape for this type isn't known
-- yet, so the first one each session is also kept raw in debug.damageTakenSample.
function W.ReadDamageTaken(fight, meter, sessions, types)
    if not types.DamageTaken then return false end
    local ok, source = pcall(meter.GetCombatSessionSourceFromType, sessions.Current, types.DamageTaken,
        UnitGUID and UnitGUID("player"))
    if not ok or type(source) ~= "table" then return false end
    if not W.takenSampled then
        W.takenSampled = true
        DB().debug.damageTakenSample = Dump(source, 4, { left = 120 })
    end
    fight.damageTaken = Plain(source.totalAmount)
    local by = {}
    for _, row in pairs(type(source.combatSpells) == "table" and source.combatSpells or {}) do
        local amount = Plain(row.totalAmount)
        if type(amount) == "number" then
            local details = type(row.combatSpellDetails) == "table" and row.combatSpellDetails or {}
            local name = Plain(row.creatureName) or Plain(details.unitName)
            if name == "" then name = nil end
            local id = Plain(row.spellID)
            name = name or (id and (SpellName(id) or ("spell " .. tostring(id)))) or "?"
            by[name] = (by[name] or 0) + amount
        end
    end
    fight.takenBy = by
    return true
end

function W.AfterFight(fight)
    W.ReadFightDamage(fight)
    -- The full meter dump runs once a session: it only checks the meter still looks the same.
    if not W.meterProbed then W.meterProbed = true; W.ProbeDamageMeter() end
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
    if spell then W.lastCastAt[spell] = GetTime() end
    if spell == "Rend" and UnitGUID then
        local guid = Plain(UnitGUID("target"))
        if guid then W.rendAt[guid] = GetTime() end
    end
    if not fight or not spell then return end
    -- Play style: spells pressed on their own keys (not in the button's macro).
    local body = W.state.body
    if fight.manual and body and not string.find(body, spell, 1, true) then
        fight.manual[spell] = (fight.manual[spell] or 0) + 1
    end
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
    W.lastPrediction = (W.Pick(HintFacts()))
end

-- Keeps the icon's copy of the castsequence steps in line with the game (see SequenceNext).
function W.FollowTry(kind, name)
    if not W.IsWarrior() then return end
    local lines = W.MacroLines()
    if #lines == 0 then return end
    local facts, now = HintFacts(), GetTime()
    if kind == "C" or kind == "S" then W.SequenceCast(lines, facts, name, kind, now) end
    W.SequencePressed(lines, facts, now)
end

function W.FightCount() return #DB().fights end
function W.ClearLog() DB().fights = {}; DB().macros = {} end

local logEvents = CreateFrame("Frame")
Listen(logEvents, { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_SPELLCAST_SUCCEEDED",
    "UI_ERROR_MESSAGE", "PLAYER_DEAD", "PLAYER_TARGET_CHANGED",
    "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED" })
logEvents:SetScript("OnEvent", W.Guard("fight log", function(_, event, a, b, c, ...)
    CountEvent(event)
    -- No combat log: Forever forbids addons to register it, and trying shows the game's "blocked from an
    -- action" popup (user, 2026-11-13). W.CombatLog stays for clients that allow it.
    if event == "PLAYER_REGEN_DISABLED" then W.FightStart()
    elseif event == "PLAYER_REGEN_ENABLED" then W.FightEnd(); W.recent = {}; W.SequenceCombatEnded()
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
        W.FollowTry("C", name)
    elseif event == "UNIT_SPELLCAST_SENT" and a == "player" then
        local spellID = ...  -- (unit, target, castGUID, spellID): a, b, c are the first three
        local name = spellID and SpellName(spellID) or tostring(c)
        W.LogTry("S", name)
        W.FollowTry("S", name)
    elseif (event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" or event == "UNIT_SPELLCAST_INTERRUPTED") and a == "player" then
        local kind = event == "UNIT_SPELLCAST_FAILED" and "F" or (event == "UNIT_SPELLCAST_FAILED_QUIET" and "Q" or "I")
        W.LogTry(kind, c and SpellName(c) or "?") -- (unit, castGUID, spellID)
        W.FollowTry(kind)
    end
end))

-- ---- Events ----

local events = CreateFrame("Frame")
Listen(events, { "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED",
    "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE", "UPDATE_SHAPESHIFT_FORMS", "UNIT_AURA",
    "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_SHAPESHIFT_FORM", "UPDATE_BONUS_ACTIONBAR",
    "PLAYER_EQUIPMENT_CHANGED", "GROUP_ROSTER_UPDATE" })
events:SetScript("OnEvent", W.Guard("macro events", function(_, event, unit, updateInfo)
    if event ~= "UNIT_AURA" then CountEvent(event) end
    if event == "PLAYER_LOGIN" then
        -- Errors start fresh each session, so the saved file shows only the current version's.
        DB().debug.errors = {}
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
        pcall(W.TrackCurse, updateInfo)
        local now = GetTime()
        if W.lastAura and now - W.lastAura < 1 then return end -- buffs change often; once a second is plenty
        W.lastAura = now
    end
    if event == "PLAYER_REGEN_ENABLED" or not Lockdown() then
        W.SafeUpdate(); W.RefreshButtons()
        W.Guard("gear", W.TrackGear)()
    end
end))
