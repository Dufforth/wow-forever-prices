-- Druid one-button helper, built like the Warrior one (Warrior.lua) and on the same proven rule:
--  * on each press the game tries only the FIRST matching spell that uses the global cooldown
--    (cast or rejected, a rejected one still uses the try);
--  * spells off the global cooldown (Maul, Enrage) are tried on every press, wherever they are;
--  * "/castsequence ... X,nil" casts X once and then is skipped; reset=combat starts it over.
-- The button reads the form you're in ([form:N] from the stance bar, [noform] = caster) and never
-- changes form (user, 2026-11-16). Between fights the addon rewrites the "DTH Druid" macro for the
-- spells you know; in fights an icon shows what the next press casts. The addon never casts.

local L = DufforthTweaksHelperL or setmetatable({}, { __index = function(_, k) return k end })
DufforthTweaksHelperDruid = DufforthTweaksHelperDruid or {}
local D = DufforthTweaksHelperDruid
local W = DufforthTweaksHelperWarrior

local MACRO_NAME = "DTH Druid"
local MACRO_ICON = "INV_MISC_QUESTIONMARK"
local MACRO_LIMIT = 255
D.MACRO_NAME, D.MACRO_LIMIT = MACRO_NAME, MACRO_LIMIT

-- Forms by spell id or name (Forever has its own ids for some spells, so names count too). Their
-- number on the stance bar depends on which ones you know; the fallback is the order you learn them.
local FORMS = {
    { key = "bear", ids = { [5487] = true, [9634] = true }, names = { ["Bear Form"] = true, ["Dire Bear Form"] = true } },
    { key = "aquatic", ids = { [1066] = true }, names = { ["Aquatic Form"] = true } },
    { key = "cat", ids = { [768] = true }, names = { ["Cat Form"] = true } },
    { key = "travel", ids = { [783] = true }, names = { ["Travel Form"] = true } },
    { key = "moonkin", ids = { [24858] = true }, names = { ["Moonkin Form"] = true } },
}
D.FORMS = FORMS

-- Spells the macro may use, and those off the global cooldown (tried on every press).
D.ROTATION = { "Maul", "Enrage", "Demoralizing Roar", "Swipe", "Tiger's Fury", "Rake", "Claw", "Rip",
    "Ferocious Bite", "Faerie Fire", "Moonfire", "Wrath" }
local OFF_GCD = { ["Maul"] = true, ["Enrage"] = true, ["Feral Charge"] = true }
local ON_SWING = { ["Maul"] = true } -- a castsequence step moves when it's queued
local BUILDERS = { ["Claw"] = true, ["Rake"] = true, ["Shred"] = true, ["Ravage"] = true, ["Pounce"] = true }
local FINISHERS = { ["Ferocious Bite"] = true, ["Rip"] = true }
local HEALS = { "Regrowth", "Healing Touch", "Rejuvenation" }
local HEAL_BELOW = 35 -- percent of your health
D.OFF_GCD, D.ON_SWING = OFF_GCD, ON_SWING

local function DB()
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    local db = DufforthTweaksHelperDB
    db.druid = db.druid or {}
    local o = db.druid
    if o.enabled == nil then o.enabled = true end
    if o.hint == nil then o.hint = true end
    if o.log == nil then o.log = true end
    if o.buttonIcon == nil then o.buttonIcon = true end
    o.debug = o.debug or {}
    o.debug.errors = o.debug.errors or {}
    o.fights = o.fights or {}
    o.macros = o.macros or {}
    return o
end
D.Options = DB

function D.IsDruid()
    local _, class = UnitClass("player")
    return class == "DRUID"
end

local function Lockdown() return InCombatLockdown and InCombatLockdown() end
local Plain = W.Plain
local SpellName = W.SpellName

function D.RecordError(where, message)
    local errors = DB().debug.errors
    local key = where .. ": " .. tostring(message)
    if errors[key] then errors[key] = errors[key] + 1; return end
    local count = 0
    for _ in pairs(errors) do count = count + 1 end
    if count < 30 then errors[key] = 1 end
end

function D.Guard(where, fn)
    return function(...)
        local args, n = { ... }, select("#", ...)
        local ok, err = pcall(function() return fn(unpack(args, 1, n)) end)
        if not ok then D.RecordError(where, err) end
    end
end

local function SpellUsable(name)
    if C_Spell and C_Spell.IsSpellUsable then return C_Spell.IsSpellUsable(name) end
    if IsUsableSpell then return IsUsableSpell(name) end
    return false
end
local function SpellIcon(name)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(name) end
    return GetSpellTexture and GetSpellTexture(name)
end
local function SpellInRange(name)
    local result
    if C_Spell and C_Spell.IsSpellInRange then result = C_Spell.IsSpellInRange(name, "target")
    elseif IsSpellInRange then result = IsSpellInRange(name, "target") end
    return not (result == false or result == 0)
end

local function Listen(frame, names)
    for _, name in ipairs(names) do pcall(frame.RegisterEvent, frame, name) end
end

-- ---- Reading the game ----

-- Form key -> its number on the stance bar ({ bear = 1, cat = 3 }). D.formsSeen keeps what the bar
-- said ("1=Bear Form(5487) ..."), so the fight log shows Forever's own form ids.
function D.FormNumbers(known)
    local numbers, seen = {}, {}
    local count = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
    for i = 1, count do
        local _, _, _, spellID = GetShapeshiftFormInfo(i)
        spellID = Plain(spellID)
        local name = spellID and SpellName(spellID)
        seen[#seen + 1] = i .. "=" .. tostring(name) .. "(" .. tostring(spellID) .. ")"
        for _, form in ipairs(FORMS) do
            if (spellID and form.ids[spellID]) or (name and form.names[name]) then numbers[form.key] = i end
        end
    end
    D.formsSeen = table.concat(seen, " ")
    if not next(numbers) then -- can't read the bar: forms come in the order you learn them
        local n = 0
        for _, form in ipairs(FORMS) do
            local has = false
            for name in pairs(form.names) do if known[name] then has = true end end
            if has then n = n + 1; numbers[form.key] = n end
        end
    end
    return numbers
end

-- The form you're in: its key ("bear", "cat", ...), "caster" with no form, or "other".
function D.CurrentForm(numbers)
    local form = GetShapeshiftForm and GetShapeshiftForm() or 0
    if form == 0 then return "caster", 0 end
    for key, number in pairs(numbers) do if number == form then return key, form end end
    return "other", form
end

-- ---- Building the macro (pure: no game calls) ----

-- options: group (in a party or raid), skip = { [spell] = true } (left out to fit), compact (no
-- space after "]"; Warrior's Bloodrage line was written that way).
function D.BuildLines(known, numbers, options)
    options = options or {}
    local skip = options.skip or {}
    local function has(name) return known[name] and not skip[name] end
    local out = { "/startattack" }
    local bear, cat = numbers.bear, numbers.cat
    local caster = "[noform]" .. (numbers.moonkin and ("[form:" .. numbers.moonkin .. "]") or "")

    -- Off the global cooldown: Maul on every press in Bear Form (it waits for your next swing).
    if bear and has("Maul") then out[#out + 1] = "/cast [form:" .. bear .. "] Maul" end

    -- Once per pull, one clause per form. Bear only in combat: Demoralizing Roar before the pull
    -- would hit nothing and the line would be spent.
    local once = {}
    if bear then
        local s = {}
        if has("Enrage") then s[#s + 1] = "Enrage" end
        if has("Demoralizing Roar") then s[#s + 1] = "Demoralizing Roar" end
        if #s > 0 then once[#once + 1] = "[combat,form:" .. bear .. "] reset=combat " .. table.concat(s, ",") .. ",nil" end
    end
    if cat and has("Tiger's Fury") then once[#once + 1] = "[form:" .. cat .. "] reset=combat Tiger's Fury,nil" end
    local s = {}
    if has("Faerie Fire") then s[#s + 1] = "Faerie Fire" end
    if has("Moonfire") then s[#s + 1] = "Moonfire" end
    if #s > 0 then once[#once + 1] = caster .. " reset=combat " .. table.concat(s, ",") .. ",nil" end
    if #once > 0 then out[#out + 1] = "/castsequence " .. table.concat(once, ";") end

    -- Cat Form: one global-cooldown line that builds combo points and then spends them.
    if cat and known["Claw"] then
        local finisher = (known["Ferocious Bite"] and "Ferocious Bite") or (known["Rip"] and "Rip") or nil
        if finisher then
            local seq = {}
            if known["Rake"] then seq[#seq + 1] = "Rake" end
            for _ = 1, 3 do seq[#seq + 1] = "Claw" end
            seq[#seq + 1] = finisher
            out[#out + 1] = "/castsequence [form:" .. cat .. "] reset=combat " .. table.concat(seq, ",")
        else
            out[#out + 1] = "/cast [form:" .. cat .. "] Claw"
        end
    end

    -- Last global-cooldown line: Swipe in a group (Bear), Wrath in caster form.
    local last = {}
    if bear and has("Swipe") and options.group then last[#last + 1] = "[form:" .. bear .. "] Swipe" end
    if known["Wrath"] then last[#last + 1] = caster .. " Wrath" end
    if #last > 0 then out[#out + 1] = "/cast " .. table.concat(last, ";") end

    if options.compact then
        for i, line in ipairs(out) do out[i] = (string.gsub(line, "%] ", "]")) end
    end
    return out
end

-- The least important parts go first when the macro is too long (feral cat leveling: Faerie Fire in
-- caster form matters least). One part left out is tried before two: at level 24 dropping Faerie
-- Fire is enough; from Ferocious Bite (32) on only Tiger's Fury alone brings it under 255.
D.DROP_FIRST = { "Faerie Fire", "Tiger's Fury", "Enrage", "Demoralizing Roar", "Swipe", "Moonfire" }

-- Lines that fit in 255 characters, and the names left out.
function D.Fit(known, numbers, options)
    options = options or {}
    local skip, dropped = {}, {}
    local function try(compact)
        local lines = D.BuildLines(known, numbers, { group = options.group, skip = skip, compact = compact })
        return lines, #table.concat(lines, "\n")
    end
    local lines, size = try(false)
    if size <= MACRO_LIMIT then return lines, dropped end
    lines, size = try(true)
    if size <= MACRO_LIMIT then return lines, dropped end
    for _, name in ipairs(D.DROP_FIRST) do -- one part out
        if known[name] then
            skip = { [name] = true }
            local l, s = try(true)
            if s <= MACRO_LIMIT then return l, { name } end
        end
    end
    skip = {}
    for _, name in ipairs(D.DROP_FIRST) do
        if size <= MACRO_LIMIT then break end
        if known[name] then
            skip[name] = true
            dropped[#dropped + 1] = name
            lines, size = try(true)
        end
    end
    while size > MACRO_LIMIT and #lines > 1 do table.remove(lines); size = #table.concat(lines, "\n") end
    return lines, dropped
end

-- ---- Writing the macro ----

D.state = { status = L["Not built yet."] }

function D.InGroup()
    return (IsInGroup and IsInGroup()) or (GetNumGroupMembers and GetNumGroupMembers() > 0) or false
end

function D.Update()
    local state = D.state
    if not D.IsDruid() then state.status = L["Only for druids."]; return false end
    local options = DB()
    if not options.enabled then state.status = L["Off."]; return false end
    if Lockdown() then state.pending = true; return false end
    state.pending = false
    local known = W.KnownSpells()
    local numbers = D.FormNumbers(known)
    local group = D.InGroup()
    local lines, dropped = D.Fit(known, numbers, { group = group })
    local body = table.concat(lines, "\n")
    state.known, state.numbers, state.lines, state.dropped, state.group = known, numbers, lines, dropped, group
    DB().debug.forms = D.formsSeen
    if body == state.body then return false end -- unchanged: don't reset the sequences
    local index = GetMacroIndexByName(MACRO_NAME)
    local ok, err
    if index and index > 0 then
        ok, err = pcall(EditMacro, index, MACRO_NAME, MACRO_ICON, body)
    else
        ok, err = pcall(CreateMacro, MACRO_NAME, MACRO_ICON, body, true)
        if ok and (not err or err == 0) then ok, err = false, L["no free character macro slot"] end
    end
    if not ok then
        state.status = L["|cffff5555Couldn't save the macro: "] .. tostring(err) .. "|r"
        return false
    end
    state.body = body
    state.status = string.format(L["Macro %s: %d lines, %d characters%s."], MACRO_NAME, #lines, #body,
        #dropped > 0 and (L[", left out to fit: "] .. table.concat(dropped, ", ")) or "")
    return true
end

function D.SafeUpdate()
    local ok, result = pcall(D.Update)
    if not ok then
        D.state.status = L["|cffff5555Error: "] .. tostring(result) .. "|r"
        D.RecordError("update", result)
    end
    DB().debug.status = D.state.status
    return ok and result
end

function D.PickUp()
    if Lockdown() then return end
    D.SafeUpdate()
    if PickupMacro then PickupMacro(MACRO_NAME) end
end

-- ---- What the button does next (the icon) ----

-- Combo points: the game's own number when it can be read, else the addon's count from your casts
-- (builders +1, finishers spend all, a new target starts at 0).
D.combo = 0
function D.ComboPoints()
    local value
    if GetComboPoints then
        local ok, v = pcall(GetComboPoints, "player", "target")
        if ok then value = Plain(v) end
    end
    if value == nil and UnitPower then
        local ok, v = pcall(UnitPower, "player", 4)
        if ok then value = Plain(v) end
    end
    local debug = DB().debug
    if UnitAffectingCombat and UnitAffectingCombat("player") then
        local key = value ~= nil and "comboReadable" or "comboHidden"
        debug[key] = (debug[key] or 0) + 1
    end
    if type(value) == "number" then return value, true end
    return D.combo, false
end

local function SpellReady(name)
    local usable, noMana = SpellUsable(name)
    usable, noMana = Plain(usable), Plain(noMana)
    if usable == false or noMana then return false end
    if UnitExists("target") and not SpellInRange(name) then return false end
    return true
end
D.SpellReady = SpellReady

local WHY_NOT_READY = {
    ["Ferocious Bite"] = L["needs combo points"], ["Rip"] = L["needs combo points"],
    ["Claw"] = L["needs energy"], ["Rake"] = L["needs energy"], ["Tiger's Fury"] = L["needs energy"],
    ["Swipe"] = L["needs rage"], ["Demoralizing Roar"] = L["needs rage"],
}

function D.MacroLines()
    local body
    if GetMacroInfo and GetMacroIndexByName and (GetMacroIndexByName(MACRO_NAME) or 0) > 0 then
        local ok, _, _, text = pcall(GetMacroInfo, MACRO_NAME)
        if ok and type(text) == "string" then body = text end
    end
    if not body and D.state.lines then body = table.concat(D.state.lines, "\n") end
    return W.ParseMacro(body)
end

-- facts.stance is the form number (0 = caster), which is what the macro conditions test.
function D.Facts()
    local known = D.state.known or W.KnownSpells()
    local numbers = D.state.numbers or D.FormNumbers(known)
    local form, number = D.CurrentForm(numbers)
    return { known = known, numbers = numbers, form = form, stance = number,
        inCombat = UnitAffectingCombat("player") and true or false, inGroup = D.InGroup() }
end

-- The button's next spell: spell, ready, note.
function D.Pick(facts, ready, now)
    ready = ready or SpellReady
    local lines = D.MacroLines()
    if #lines == 0 then return nil end
    return W.ButtonPick(lines, facts, ready, now or GetTime(), OFF_GCD, WHY_NOT_READY)
end

-- Cat sequence waiting on its finisher with no combo points (the target died before it): the button
-- would only auto-attack until the fight ends, so the icon asks for one Claw on its own key.
function D.StuckFinisher(spell, combo)
    if spell and FINISHERS[spell] and combo == 0 then return "Claw" end
end

-- Health in percent, or nil when it's hidden.
local function HealthPercent()
    local now, most = Plain(UnitHealth("player")), Plain(UnitHealthMax("player"))
    if type(now) ~= "number" or type(most) ~= "number" or most <= 0 then return nil end
    return now * 100 / most
end

-- A spell for its own key: Bash when the target casts (Bear Form), a heal when you're low.
function D.OwnKeyPrompt(facts, ready, casting, health)
    if casting and facts.form == "bear" and facts.known["Bash"] and ready("Bash") then return "Bash", L["|cffff3030Enemy casting|r"] end
    if health and health < HEAL_BELOW then
        for _, name in ipairs(HEALS) do
            if facts.known[name] and ready(name) then return name, L["|cffff3030Low health: leave your form and heal|r"] end
        end
    end
end

-- ---- Following the castsequence (W keeps each step; Maul moves its step when queued) ----

function D.FollowTry(kind, name)
    local lines = D.MacroLines()
    if #lines == 0 then return end
    local facts, now = D.Facts(), GetTime()
    if kind == "C" or kind == "S" then W.SequenceCast(lines, facts, name, kind, now, ON_SWING) end
    W.SequencePressed(lines, facts, now)
end

function D.CountCast(name)
    if BUILDERS[name] then D.combo = math.min(5, D.combo + 1)
    elseif FINISHERS[name] then D.combo = 0 end
end

-- ---- The icon and the picture on the button ----

local hint
local overlays = {}
D.overlays = overlays

function D.RefreshButtons()
    if not GetActionInfo then return end
    local index = GetMacroIndexByName and GetMacroIndexByName(MACRO_NAME) or 0
    for _, overlay in pairs(overlays) do overlay.active = false end
    if index and index > 0 then
        for _, button in ipairs(W.AllBarButtons()) do
            local slot = button and W.ButtonSlot(button)
            if slot then
                local kind, id = GetActionInfo(slot)
                local name = GetActionText and GetActionText(slot)
                if kind == "macro" and (id == index or name == MACRO_NAME) then
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
    for _, overlay in pairs(overlays) do overlay:SetShown(overlay.active and DB().buttonIcon and true or false) end
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

local lastAlert = 0
local function Alert(text, spell)
    if GetTime() - lastAlert > 3 and PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
    lastAlert = GetTime()
    hint:Show()
    hint.icon:SetTexture(SpellIcon(spell) or "Interface\\Icons\\INV_Misc_QuestionMark")
    hint.icon:SetDesaturated(false)
    hint.spell:SetText("|cffff3030" .. spell .. "!|r")
    hint.notes:SetText(text)
end

function D.UpdateHint()
    if not hint then return end
    if not D.IsDruid() then hint:Hide(); return end
    local facts = D.Facts()
    local spell, ready, note = D.Pick(facts)
    D.currentPick = spell
    ShowOnButtons(spell, ready)
    local combo = D.ComboPoints()
    local stuck = D.StuckFinisher(spell, combo)
    if stuck and facts.inCombat then
        Alert(L["|cffff3030Finisher needs combo points: press Claw on its own key once|r"], stuck)
        return
    end
    local prompt, why = D.OwnKeyPrompt(facts, SpellReady, W.TargetCasting(), HealthPercent())
    if prompt then Alert(why, prompt); return end
    local hostile = UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target")
    local show = DB().hint and (hostile or UnitAffectingCombat("player")) or hint.unlocked
    hint:SetShown(show and true or false)
    if not show then return end
    local texture = spell and SpellIcon(spell)
    if not texture and not hint.unlocked then hint:Hide(); return end
    hint.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    hint.icon:SetDesaturated(not ready)
    local notes = {}
    if note then notes[#notes + 1] = note end
    if facts.form == "cat" then notes[#notes + 1] = string.format(L["%d combo points"], combo) end
    local enemies = W.EnemyCount()
    if enemies >= 2 then notes[#notes + 1] = enemies .. L[" enemies"] end
    hint.spell:SetText(hint.unlocked and L["Drag to move"] or (ready and spell or ("|cff909090" .. tostring(spell) .. "|r")))
    hint.notes:SetText(table.concat(notes, "\n"))
end

local function BuildHint()
    local options = DB()
    hint = CreateFrame("Frame", "DufforthTweaksHelperDruidHint", UIParent)
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
    hint.notes:SetPoint("TOP", hint.spell, "BOTTOM", 0, -2)
    hint.notes:SetWidth(200)
    hint.notes:SetJustifyH("CENTER")
    hint:Hide()
    local elapsed = 0
    local ticker = CreateFrame("Frame")
    local guarded = D.Guard("icon", D.UpdateHint)
    ticker:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < 0.1 then return end
        elapsed = 0
        guarded()
    end)
end
D.BuildHint = BuildHint

function D.SetHintUnlocked(on)
    if not hint then return end
    hint.unlocked = on and true or false
    hint:EnableMouse(hint.unlocked)
    D.UpdateHint()
end
function D.HintUnlocked() return hint and hint.unlocked or false end
if DufforthTweaksHelper and DufforthTweaksHelper.RegisterMovable then
    DufforthTweaksHelper.RegisterMovable({ label = L["Druid icon"], get = function() return hint end,
        enter = function() D.SetHintUnlocked(true) end, leave = function() D.SetHintUnlocked(false) end })
end

-- ---- Fight log (DufforthTweaksHelperDB.druid.fights, written on /reload or logout) ----

local FIGHTS_KEPT, MAX_TRIES = 300, 400
D.FIGHTS_KEPT = FIGHTS_KEPT
local fight
D.preTries = {}

local function MacroId(body)
    local macros = DB().macros
    for i, text in ipairs(macros) do if text == body then return i end end
    macros[#macros + 1] = body
    return #macros
end

function D.FightStart()
    if not DB().log or not D.IsDruid() then return end
    local body = D.state.body
    local facts = D.Facts()
    fight = {
        at = time and time() or 0, start = GetTime(),
        character = DufforthTweaksHelper.CharacterKey and DufforthTweaksHelper.CharacterKey() or "?",
        zone = GetRealZoneText and GetRealZoneText() or "?", level = UnitLevel("player") or 0,
        group = facts.inGroup, form = facts.form, macro = body and MacroId(body) or 0,
        casts = {}, errors = {}, tries = {}, tried = {}, result = "won", manual = {},
    }
    local ok, talents = pcall(W.TalentText)
    fight.talents = ok and talents or "?"
    for _, try in ipairs(D.preTries) do
        if fight.start - try.at <= 6 then
            fight.tries[#fight.tries + 1] = string.format("%.1f %s %s", try.at - fight.start, try.kind, try.name)
        end
    end
    D.preTries = {}
end

function D.FightEnd()
    if not fight then return end
    local f = fight
    fight = nil
    f.seconds = math.floor((GetTime() - f.start) * 10 + 0.5) / 10
    f.start = nil
    if #f.casts == 0 and f.seconds < 3 then return end
    local fights = DB().fights
    fights[#fights + 1] = f
    while #fights > FIGHTS_KEPT do table.remove(fights, 1) end
    local read = D.Guard("damage meter", function() W.ReadFightDamage(f) end)
    if C_Timer then C_Timer.After(1.5, read) else read() end
end

function D.LogTry(kind, name)
    if not name then return end
    if fight then
        if #fight.tries < MAX_TRIES then
            fight.tries[#fight.tries + 1] = string.format("%.1f %s %s", GetTime() - fight.start, kind, name)
        end
        local tried = fight.tried[name] or {}
        tried[kind] = (tried[kind] or 0) + 1
        fight.tried[name] = tried
    elseif DB().log and D.IsDruid() then
        table.insert(D.preTries, { at = GetTime(), kind = kind, name = name })
        while #D.preTries > 30 do table.remove(D.preTries, 1) end
    end
end

-- "seconds spell f:<form> cp<combo points> p:<what the icon showed>"
function D.LogCast(spell)
    if not fight or not spell then return end
    local body = D.state.body
    if body and not string.find(body, spell, 1, true) then fight.manual[spell] = (fight.manual[spell] or 0) + 1 end
    local facts = D.Facts()
    local combo = D.ComboPoints()
    fight.casts[#fight.casts + 1] = string.format("%.1f %s f:%s cp%d p:%s", GetTime() - fight.start, spell,
        facts.form, combo or 0, D.currentPick or "-")
end

function D.LogError(message)
    if fight and message then fight.errors[message] = (fight.errors[message] or 0) + 1 end
end

function D.FightCount() return #DB().fights end
function D.ClearLog() DB().fights = {}; DB().macros = {} end

-- ---- Events ----

local events = CreateFrame("Frame")
Listen(events, { "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "UPDATE_SHAPESHIFT_FORMS", "UPDATE_SHAPESHIFT_FORM",
    "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "GROUP_ROSTER_UPDATE",
    "PLAYER_TARGET_CHANGED", "PLAYER_DEAD", "UI_ERROR_MESSAGE", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_SENT",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED" })
events:SetScript("OnEvent", D.Guard("events", function(_, event, a, b, c, ...)
    if event == "PLAYER_LOGIN" then
        DB().debug.errors = {}
        if D.IsDruid() then BuildHint() end
        return
    end
    if not D.IsDruid() then return end
    if event == "PLAYER_REGEN_DISABLED" then D.FightStart(); return end
    if event == "PLAYER_REGEN_ENABLED" then D.FightEnd(); D.combo = 0; D.SafeUpdate(); D.RefreshButtons(); return end
    if event == "PLAYER_TARGET_CHANGED" then D.combo = 0; return end
    if event == "PLAYER_DEAD" then if fight then fight.result = "died" end; return end
    if event == "UI_ERROR_MESSAGE" then
        local message = type(a) == "string" and a or b
        D.LogError(message)
        D.LogTry("E", message and tostring(Plain(message) or "?"))
        return
    end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if a ~= "player" then return end
        local name = c and SpellName(c)
        D.CountCast(name)
        D.LogCast(name)
        D.LogTry("C", name)
        D.FollowTry("C", name)
        return
    end
    if event == "UNIT_SPELLCAST_SENT" then
        if a ~= "player" then return end
        local spellID = ...
        local name = spellID and SpellName(spellID) or tostring(c)
        D.LogTry("S", name)
        D.FollowTry("S", name)
        return
    end
    if event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        if a ~= "player" then return end
        local kind = event == "UNIT_SPELLCAST_FAILED" and "F" or (event == "UNIT_SPELLCAST_FAILED_QUIET" and "Q" or "I")
        D.LogTry(kind, c and SpellName(c) or "?")
        D.FollowTry(kind)
        return
    end
    if event == "ACTIONBAR_SLOT_CHANGED" or event == "ACTIONBAR_PAGE_CHANGED" or event == "UPDATE_BONUS_ACTIONBAR"
        or event == "UPDATE_SHAPESHIFT_FORM" then
        D.RefreshButtons()
        return
    end
    if not Lockdown() then D.SafeUpdate(); D.RefreshButtons() end
end))
