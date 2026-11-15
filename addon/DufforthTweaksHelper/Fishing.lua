-- One-click fishing (user, 2026-11-15): one key, a double right-click or the fishing bar's icon casts
-- Fishing, and the same key hooks the fish once the bobber has landed (the bobber is the game's soft
-- interact target). Ideas from Mastercraft's Angler (a Forever addon; its code is All Rights Reserved, so
-- nothing is copied): everything here is written for this addon.
-- Blizzard's rules: a cast needs your key press or click, so it's done by secure buttons (the game's own
-- action buttons) and override bindings, changed only out of combat. Never anything during a fight.

local L = DufforthTweaksHelperL or setmetatable({}, { __index = function(_, k) return k end })
local F = {}
DufforthTweaksHelperFishing = F

F.SPELLS = { 7620, 7731, 7732, 18248 } -- Fishing ranks, lowest first
F.IS_SPELL = {}
for _, id in ipairs(F.SPELLS) do F.IS_SPELL[id] = true end
-- Lures, best first: { item, skill bonus }.
F.LURES = { { 6533, 100 }, { 6532, 75 }, { 7307, 75 }, { 6530, 50 }, { 6811, 50 }, { 6529, 25 } }
F.POLE_CLASS, F.POLE_SUBCLASS = 2, 20 -- weapon / fishing pole
F.MAIN, F.OFF = 16, 17
-- Fishing gear besides the pole goes in these slots (by the item's equip place).
F.GEAR_SLOTS = { INVTYPE_HEAD = 1, INVTYPE_FEET = 8, INVTYPE_HAND = 10, INVTYPE_TRINKET = 13 }
F.BOBBER = "35591" -- the Fishing Bobber game object
F.QUICK, F.MOVED = 0.35, 12 -- a right-click shorter than this, moving less than this, can start a double-click
F.DOUBLE_CLICK = 0.4 -- seconds for the second right-click
F.HOLD = 0.25 -- a second right-click held longer is turning the camera: it casts nothing
F.LAND = 1.5 -- at most this long after the cast the key waits for the bobber to land
F.IDLE = 90 -- seconds after the last cast: settings and weapons back
F.NEW_SESSION = 1800 -- a cast after 30 minutes away starts new counters
F.REMIND = 20 -- the "cast again" sound after this many seconds with no line out
F.BUTTON = "DufforthTweaksHelperFishButton"
F.WAIT = "DufforthTweaksHelperFishWait"
F.MODIFIERS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true }
-- Options and their defaults (sounds and the bar lock start off).
F.DEFAULTS = { doubleClick = true, pole = true, lure = true, food = true, loot = true, sound = true, bar = true, marker = true,
    recap = true, lock = false, alertCatch = false, alertEscape = true, alertRemind = false }
-- Volumes while fishing (0 to 1; the game volume -1 = keep yours), and the extra keys.
F.NUMBERS = { volMaster = -1, volSFX = 1, volMusic = 0, volAmbience = 0 }
F.LURE_BUTTON, F.GEAR_BUTTON = "DufforthTweaksHelperFishLureButton", "DufforthTweaksHelperFishGearButton"
F.KEYS = { key = true, jumpKey = true, lureKey = true, gearKey = true }
F.ALERTS = { catch = { "alertCatch", "IG_QUEST_LIST_COMPLETE", 878 }, escape = { "alertEscape", "IG_QUEST_FAILED", 847 },
    remind = { "alertRemind", "READY_CHECK", 8960 } }

local function DB()
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    local db = DufforthTweaksHelperDB
    db.fishing = db.fishing or {}
    local f = db.fishing
    f.caught = f.caught or {}
    f.zones = f.zones or {}
    f.sessions = f.sessions or {}
    return f
end
F.DB = DB

function F.Opt(name)
    local v = DB()[name]
    if v == nil then return F.DEFAULTS[name] == true end
    return v == true
end

function F.Num(name)
    local v = tonumber(DB()[name])
    if v == nil then return F.NUMBERS[name] end
    return v
end

function F.SetNum(name, value)
    DB()[name] = math.floor(value * 100 + 0.5) / 100
    if F.ModeIsOn and F.ModeIsOn() then F.Reapply() end
    F.Refresh()
end

-- The jump key while fishing: Shift+Space unless you chose another one.
function F.JumpKey()
    local k = DB().jumpKey
    if k == nil then return "SHIFT-SPACE" end
    return k ~= "" and k or nil
end

local function InCombat() return (InCombatLockdown and InCombatLockdown()) and true or false end
local function Now() return (GetTime and GetTime()) or 0 end
local function After(seconds, fn) if C_Timer and C_Timer.After then C_Timer.After(seconds, fn) end end

local function Call(fn, ...)
    if not fn then return nil end
    local r = { pcall(fn, ...) }
    if r[1] then return unpack(r, 2, table.maxn(r)) end
    return nil
end

-- ---- Pure rules (tested in tests/addon/fishing_sim.py) ----

-- The highest Fishing rank you know; knows(id) says whether a spell is known.
function F.KnownSpell(knows)
    for i = #F.SPELLS, 1, -1 do
        local ok, yes = pcall(knows, F.SPELLS[i])
        if ok and yes then return F.SPELLS[i] end
    end
    return nil
end

function F.IsPole(classID, subClassID)
    return tonumber(classID) == F.POLE_CLASS and tonumber(subClassID) == F.POLE_SUBCLASS
end

-- The best lure you carry; have = { [item] = count }.
function F.BestLure(have)
    for _, lure in ipairs(F.LURES) do
        if (have[lure[1]] or 0) > 0 then return lure[1], lure[2] end
    end
    return nil
end

-- The Fishing bonus an item gives, from its tooltip lines: the number on an "Equip:" line naming Fishing.
-- Works in any language (the game's own words for Fishing and Equip). Lure lines don't count.
function F.Bonus(lines, fishing, equip)
    local best = 0
    for _, text in ipairs(lines or {}) do
        if type(text) == "string" and fishing and string.find(text, fishing, 1, true)
            and (not equip or string.find(text, equip, 1, true)) then
            local n = tonumber(string.match(text, "%+%s*(%d+)") or string.match(text, "(%d+)"))
            if n and n > best then best = n end
        end
    end
    return best
end

-- What fishing gear goes on: bag = { { id, slot, bonus } }, worn = { [slot] = { id, bonus, pole } }.
-- The best pole when none is on (or a better one), and any hat, boots, gloves or trinket that beats what's on.
function F.GearPlan(bag, worn)
    local plan, count = {}, 0
    local cur = worn[F.MAIN]
    local best = cur and cur.pole and cur.bonus or -1
    for _, it in ipairs(bag) do
        if it.slot == F.MAIN and it.bonus > best then plan[F.MAIN] = it.id; best = it.bonus end
    end
    for _, it in ipairs(bag) do
        if it.slot ~= F.MAIN and it.bonus > 0 then
            local have = worn[it.slot]
            local top = math.max(have and have.bonus or 0, plan[it.slot] and plan[it.slot .. "b"] or 0)
            if it.bonus > top then plan[it.slot] = it.id; plan[it.slot .. "b"] = it.bonus end
        end
    end
    local out = {}
    for slot, id in pairs(plan) do if type(slot) == "number" then out[slot] = id; count = count + 1 end end
    return out, count
end

-- What the next press does. s = { combat, spell, pole, plan, planCount, offHand, freeSlots, channel, lure, lureInBag }.
-- Returns the action ("none", "hook", "gear", "lure", "cast") and its value or the reason for none.
function F.Action(s)
    if s.combat then return "none", "combat" end
    if not s.spell then return "none", "unknown" end
    if s.channel then return "hook" end
    if F.Opt("pole") and (s.planCount or 0) > 0 then
        if s.plan[F.MAIN] and s.offHand and (s.freeSlots or 0) < 1 then return "none", "bagsfull" end
        if s.pole or s.plan[F.MAIN] then return "gear", s.plan end
    end
    if not s.pole then return "none", "nopole" end
    if F.Opt("lure") and not s.lure and s.lureInBag then return "lure", s.lureInBag end
    if F.Opt("food") and not s.fed and s.foodInBag then return "food", s.foodInBag end
    return "cast", s.spell
end

-- The secure button's attributes for an action (the game runs them on your press).
function F.Attributes(action, value)
    if action == "cast" then return { type = "spell", spell = value, macrotext = nil } end
    if action == "gear" then
        local lines = {}
        if value[F.MAIN] then lines[1] = "/equipslot " .. F.MAIN .. " item:" .. value[F.MAIN] end -- the pole first (both hands)
        for _, slot in ipairs({ 1, 8, 10, 13 }) do
            if value[slot] then lines[#lines + 1] = "/equipslot " .. slot .. " item:" .. value[slot] end
        end
        return { type = "macro", spell = nil, macrotext = table.concat(lines, "\n") }
    end
    if action == "lure" then return { type = "macro", spell = nil, macrotext = "/use item:" .. value .. "\n/use 16" } end
    if action == "food" then return { type = "macro", spell = nil, macrotext = "/use item:" .. value } end
    return { type = nil, spell = nil, macrotext = nil }
end

-- A key with its modifiers, as the game names it ("SHIFT-F"); nil for a lone modifier.
function F.KeyName(key, alt, ctrl, shift)
    if not key or F.MODIFIERS[key] then return nil end
    return (alt and "ALT-" or "") .. (ctrl and "CTRL-" or "") .. (shift and "SHIFT-" or "") .. key
end

-- The game's settings while you fish, by name: the bobber as your interact key's target (all around you,
-- as far as a cast lands; only ever raised), its nameplate for the mark, auto loot, a louder splash.
function F.Wanted(opts, current)
    local want = {}
    if opts.interact or opts.marker then
        want.SoftTargetInteract = "3"
        if (tonumber(current("SoftTargetInteractArc")) or 2) < 2 then want.SoftTargetInteractArc = "2" end
        if (tonumber(current("SoftTargetInteractRange")) or 30) < 30 then want.SoftTargetInteractRange = "30" end
    end
    if opts.marker then want.SoftTargetIconGameObject = "1" end
    if opts.loot then want.autoLootDefault = "1" end
    if opts.sound then
        -- vol = { master (-1 keep yours), sfx, music, ambience }, 0 to 1; a volume of 0 turns that sound off
        local vol = opts.vol or { -1, 1, 0, 0 }
        local function V(x) return string.format("%.2f", math.max(0, math.min(1, x))) end
        want.Sound_EnableAllSound = "1"; want.Sound_EnableSFX = "1"; want.Sound_SFXVolume = V(vol[2])
        if vol[1] >= 0 then want.Sound_MasterVolume = V(vol[1]) end
        if vol[3] <= 0 then want.Sound_EnableMusic = "0" else want.Sound_EnableMusic = "1"; want.Sound_MusicVolume = V(vol[3]) end
        if vol[4] <= 0 then want.Sound_EnableAmbience = "0" else want.Sound_EnableAmbience = "1"; want.Sound_AmbienceVolume = V(vol[4]) end
        want.Sound_EnableDialog = "0"; want.Sound_EnableErrorSpeech = "0"
    end
    return want
end

local function Same(a, b)
    if a == nil or b == nil then return a == b end
    local x, y = tonumber(a), tonumber(b)
    if x and y then return math.abs(x - y) < 0.001 end
    return tostring(a) == tostring(b)
end
F.Same = Same

-- Applies want; saved[name] = { old, set } keeps your own value. A setting no longer wanted goes back now.
function F.ApplyCVars(want, saved, get, set)
    for name, value in pairs(want) do
        local ok, cur = pcall(get, name)
        if ok and cur ~= nil then
            local e = saved[name]
            if not e and not Same(cur, value) then
                saved[name] = { old = tostring(cur), set = value }; pcall(set, name, value)
            elseif e and not Same(e.set, value) and Same(cur, e.set) then
                e.set = value; pcall(set, name, value)
            end
        end
    end
    for name in pairs(saved) do
        if want[name] == nil then F.RestoreCVars(saved, get, set, name) end
    end
    return saved
end

-- Puts back your values: only where the setting is still ours (you may have changed it meanwhile).
function F.RestoreCVars(saved, get, set, only)
    for name, e in pairs(saved) do
        if not only or only == name then
            if type(e) ~= "table" then e = { old = e } end
            local ok, cur = pcall(get, name)
            if e.set == nil or (ok and Same(cur, e.set)) then pcall(set, name, e.old) end
            saved[name] = nil
        end
    end
end

-- A pattern for one of the game's message formats ("Requires Fishing %d" -> "^Requires Fishing (%d+)$").
function F.Pattern(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    local p = string.gsub(fmt, "%%%d%$", "%%")
    p = string.gsub(p, "[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
    p = string.gsub(p, "%%d", "(%%d+)")
    p = string.gsub(p, "%%s", "(.+)")
    return "^" .. p .. "$"
end

-- ---- Counters ----
function F.NewSession(now)
    return { start = now, last = now, casts = 0, catches = 0, fish = 0, escapes = 0, waits = 0, waitN = 0, items = {},
        chests = 0, chestMoney = 0, chestItems = {} }
end

function F.Record(session, id, name, count)
    count = tonumber(count) or 1
    local row = session.items[id]
    if not row then row = { id = id, name = name, count = 0 }; session.items[id] = row end
    row.count = row.count + count
    if name and name ~= "" then row.name = name end
    session.fish = session.fish + count
end

function F.PerHour(session, now)
    local seconds = math.max(60, (now or session.last) - session.start)
    return session.catches * 3600 / seconds
end

-- Rows sorted by count, then name; value = count x price(id) (auction house, else what a vendor pays).
function F.Rows(items, price)
    local rows, total = {}, 0
    for id, row in pairs(items) do
        local value = (price(id) or 0) * row.count
        total = total + value
        rows[#rows + 1] = { id = id, name = row.name or ("item " .. id), count = row.count, value = value }
    end
    table.sort(rows, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    return rows, total
end

-- ---- Reading the game (all in pcall: Forever's new engine hides some values) ----
local function ItemInstant(id)
    if not id then return nil end
    local getter = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local _, _, _, equipLoc, _, classID, subClassID = Call(getter, id)
    return classID, subClassID, equipLoc
end

local function TipLines(data)
    local out = {}
    if type(data) == "table" and type(data.lines) == "table" then
        for _, line in ipairs(data.lines) do
            if type(line) == "table" and type(line.leftText) == "string" then out[#out + 1] = line.leftText end
        end
    end
    return out
end

function F.FishingName()
    local name = C_Spell and C_Spell.GetSpellName and Call(C_Spell.GetSpellName, F.SPELLS[1])
    return type(name) == "string" and name or L["Fishing"]
end

local function EquipWord()
    local w = ITEM_SPELL_TRIGGER_ONEQUIP
    return type(w) == "string" and w ~= "" and w or nil
end

function F.Spell()
    local knows = IsPlayerSpell or IsSpellKnown
    local id = knows and F.KnownSpell(knows)
    if id then return id end
    -- Spell checks can be restricted: when the profession is there, use Fishing's first rank.
    local profs = DufforthTweaksHelper and DufforthTweaksHelper.Professions and Call(DufforthTweaksHelper.Professions)
    if profs and profs.Fishing then return F.SPELLS[1] end
    return nil
end

function F.Skill()
    local profs = DufforthTweaksHelper and DufforthTweaksHelper.Professions and Call(DufforthTweaksHelper.Professions)
    return profs and profs.Fishing
end

function F.PoleEquipped()
    return F.IsPole(ItemInstant(Call(GetInventoryItemID, "player", F.MAIN)))
end

local function WornBonus(slot)
    local get = C_TooltipInfo and C_TooltipInfo.GetInventoryItem
    if not get then return 0 end
    return F.Bonus(TipLines(Call(get, "player", slot)), F.FishingName(), EquipWord())
end

local function UseWord()
    local w = ITEM_SPELL_TRIGGER_ONUSE
    return type(w) == "string" and w ~= "" and w or nil
end

-- Your bags: counts by item, the fishing gear in them as { id, slot, bonus }, free slots, and the best
-- fishing food (food whose "Use:" line names Fishing).
local function ReadBags()
    local have, gear, free = {}, {}, 0
    local food, foodBonus = nil, 0
    local slots = C_Container and C_Container.GetContainerNumSlots
    local info = C_Container and C_Container.GetContainerItemInfo
    local tip = C_TooltipInfo and C_TooltipInfo.GetBagItem
    if not slots or not info then return have, gear, free end
    local fishing, equip, use = F.FishingName(), EquipWord(), UseWord()
    for bag = 0, 4 do
        free = free + ((C_Container.GetContainerNumFreeSlots and Call(C_Container.GetContainerNumFreeSlots, bag)) or 0)
        for slot = 1, (Call(slots, bag) or 0) do
            local item = Call(info, bag, slot)
            local id = type(item) == "table" and item.itemID or nil
            if id then
                have[id] = (have[id] or 0) + (item.stackCount or 1)
                local classID, subClassID, equipLoc = ItemInstant(id)
                local where = F.IsPole(classID, subClassID) and F.MAIN or F.GEAR_SLOTS[equipLoc or ""]
                if where then
                    local bonus = tip and F.Bonus(TipLines(Call(tip, bag, slot)), fishing, equip) or 0
                    gear[#gear + 1] = { id = id, slot = where, bonus = bonus }
                elseif tonumber(classID) == 0 and tonumber(subClassID) == 5 and tip then
                    local bonus = F.Bonus(TipLines(Call(tip, bag, slot)), fishing, use)
                    if bonus > foodBonus then food, foodBonus = id, bonus end
                end
            end
        end
    end
    return have, gear, free, food
end

-- A buff naming Fishing on you (Well Fed from fishing food): its bonus, or 0. Read out of combat only.
function F.FedBonus()
    if InCombat() or not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return 0 end
    local get = C_TooltipInfo and C_TooltipInfo.GetUnitBuffByAuraInstanceID
    if not get then return 0 end
    local fishing = F.FishingName()
    for i = 1, 40 do
        local aura = Call(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if type(aura) ~= "table" then break end
        local bonus = F.Bonus(TipLines(Call(get, "player", aura.auraInstanceID)), fishing)
        if bonus > 0 then return bonus end
    end
    return 0
end

function F.Channeling()
    if not UnitChannelInfo then return false end
    local ok, id = pcall(function() return select(8, UnitChannelInfo("player")) end)
    return ok and id ~= nil and F.IS_SPELL[id] == true
end

-- Seconds left on the pole's lure, or nil.
function F.LureLeft()
    local has, ms = Call(GetWeaponEnchantInfo)
    if has and ms then return ms / 1000 end
    return nil
end

function F.State()
    local have, gear, free, food = ReadBags()
    local fed = F.FedBonus()
    local worn = {}
    for _, slot in ipairs({ F.MAIN, 1, 8, 10, 13 }) do
        local id = Call(GetInventoryItemID, "player", slot)
        if id then worn[slot] = { id = id, bonus = WornBonus(slot), pole = slot == F.MAIN and F.IsPole(ItemInstant(id)) } end
    end
    local plan, count = F.GearPlan(gear, worn)
    return { combat = InCombat(), spell = F.Spell(), pole = worn[F.MAIN] and worn[F.MAIN].pole or false,
        plan = plan, planCount = count, offHand = Call(GetInventoryItemID, "player", F.OFF) ~= nil, freeSlots = free,
        channel = F.Channeling(), lure = F.LureLeft() ~= nil, lureInBag = (F.BestLure(have)),
        fed = fed > 0, fedBonus = fed, foodInBag = food, have = have,
        bonus = (worn[F.MAIN] and worn[F.MAIN].bonus or 0) }
end

-- ---- The secure buttons and the bindings (out of combat only) ----
local buttons = {}
F.buttons = buttons
F.lastAction = "none"
F.lastValue = nil
local owners = {}
local function Owner(name)
    if not owners[name] then owners[name] = CreateFrame("Frame", "DufforthTweaksHelperFish" .. name, UIParent) end
    return owners[name]
end
local armed, armToken, rDown, rx, ry = false, nil, nil, 0, 0
local channelAt, stoppedAt, reminded = 0, 0, 0
local hooking, hookToken = false, nil
local Begin, Disarm

-- Remember what fishing gear replaces, so it can go back afterwards (before the press runs).
local function RememberGear()
    if F.lastAction ~= "gear" or InCombat() or type(F.lastValue) ~= "table" then return end
    local db = DB()
    db.weapons = db.weapons or {}
    for slot in pairs(F.lastValue) do
        if db.weapons[slot] == nil then db.weapons[slot] = Call(GetInventoryItemID, "player", slot) or false end
    end
    if F.lastValue[F.MAIN] and db.weapons[F.OFF] == nil then db.weapons[F.OFF] = Call(GetInventoryItemID, "player", F.OFF) or false end
end

local function SecureButton(name, parent, releaseOnly)
    local b = CreateFrame("Button", name, parent or UIParent, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    if releaseOnly then
        -- It acts when the key is let go, never on the press: a release whose press reached something else
        -- (the key was the hook key then) does nothing, and a long second right-click is the camera.
        b:SetAttribute("useOnKeyDown", false)
        b:SetScript("PreClick", function(self, _, down)
            if down then self.pressAt = Now(); return end
            local skip = not self.pressAt or (armed and Now() - self.pressAt > F.HOLD)
            self.pressAt = nil
            if skip and not InCombat() then
                self.skipped = self:GetAttribute("type"); self:SetAttribute("type", nil)
            elseif not skip then
                RememberGear()
            end
        end)
        b:SetScript("PostClick", function(self, _, down)
            if down then return end
            if self.skipped and not InCombat() then self:SetAttribute("type", self.skipped) end
            self.skipped = nil
            if armed then After(0, Disarm) end
            After(0.3, function() pcall(F.Refresh) end)
        end)
    else
        b:SetScript("PreClick", function() RememberGear() end)
        b:SetScript("PostClick", function() After(0.3, function() pcall(F.Refresh) end) end)
    end
    buttons[#buttons + 1] = b
    return b
end

function F.Button()
    if not buttons[1] and not InCombat() then
        local b = SecureButton(F.BUTTON, UIParent, true)
        b:SetSize(1, 1); b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0); b:SetAlpha(0); b:EnableMouse(false)
        -- While the bobber lands, the key clicks this plain button: an early press does nothing.
        local wait = CreateFrame("Button", F.WAIT, UIParent)
        wait:SetSize(1, 1); wait:SetAlpha(0); wait:EnableMouse(false); wait:RegisterForClicks("AnyUp", "AnyDown")
        -- The lure key's button (your best lure on the pole) and the gear key's (fishing gear on, or yours back).
        for _, name in ipairs({ F.LURE_BUTTON, F.GEAR_BUTTON }) do
            local x = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
            x:SetSize(1, 1); x:SetAlpha(0); x:EnableMouse(false); x:RegisterForClicks("AnyUp")
            x:SetScript("PostClick", function() After(0.3, function() pcall(F.Refresh) end) end)
        end
        _G[F.GEAR_BUTTON]:SetScript("PreClick", function(self)
            if InCombat() then return end
            if DB().weapons then F.GearBack() else F.lastAction, F.lastValue = "gear", self.plan; RememberGear() end
        end)
    end
    return buttons[1]
end

-- The lure and gear buttons follow your bags and what you wear (out of combat).
local function SetSideButtons(state)
    if InCombat() or not _G[F.LURE_BUTTON] then return end
    local lure = _G[F.LURE_BUTTON]
    local la = state.pole and state.lureInBag and F.Attributes("lure", state.lureInBag) or F.Attributes("none")
    lure:SetAttribute("type", la.type); lure:SetAttribute("macrotext", la.macrotext)
    local gear = _G[F.GEAR_BUTTON]
    local ga = (not DB().weapons and (state.planCount or 0) > 0) and F.Attributes("gear", state.plan) or F.Attributes("none")
    gear.plan = state.plan
    gear:SetAttribute("type", ga.type); gear:SetAttribute("macrotext", ga.macrotext)
end

local function SetAttributes(action, value)
    if InCombat() then return end
    F.Button()
    local attrs = F.Attributes(action, value)
    for _, b in ipairs(buttons) do
        for _, k in ipairs({ "type", "spell", "macrotext" }) do b:SetAttribute(k, attrs[k]) end
    end
    F.lastAction, F.lastValue = action, value
end

-- A key (or mouse button) still held down: "SHIFT-F" checks F.
local MOUSE = { BUTTON1 = "LeftButton", BUTTON2 = "RightButton", BUTTON3 = "MiddleButton", BUTTON4 = "Button4", BUTTON5 = "Button5" }
local function Held(key)
    if not key then return false end
    local base = string.match(key, "([^%-]+)$") or key
    if MOUSE[base] then return Call(IsMouseButtonDown, MOUSE[base]) == true end
    return Call(IsKeyDown, base) == true
end

-- Is this key one you jump with (the game's Jump binding, or Space)?
local function IsJumpKey(key)
    if key == "SPACE" then return true end
    local a, b = Call(GetBindingKey, "JUMP")
    return key ~= nil and (key == a or key == b)
end

-- The keys while you can fish: the fishing key casts (and equips, lures, feeds) through the button; when it's
-- your jump key, the jump key (Shift+Space) jumps meanwhile; the lure key and the gear key click their buttons.
-- None of them is taken when there's nothing to do: they keep their normal use.
function F.UpdateBindings(state)
    if InCombat() or not ClearOverrideBindings then return end
    local o = Owner("Key")
    ClearOverrideBindings(o)
    local db = DB()
    state = state or F.State()
    if not state.spell then return end
    if db.key and F.Action(state) ~= "none" then
        SetOverrideBindingClick(o, false, db.key, F.BUTTON, "LeftButton")
        local jump = F.JumpKey()
        if jump and jump ~= db.key and IsJumpKey(db.key) then SetOverrideBinding(o, false, jump, "JUMP") end
    end
    if db.lureKey and state.pole and state.lureInBag then SetOverrideBindingClick(o, false, db.lureKey, F.LURE_BUTTON, "LeftButton") end
    if db.gearKey and (db.weapons or (state.planCount or 0) > 0) then SetOverrideBindingClick(o, false, db.gearKey, F.GEAR_BUTTON, "LeftButton") end
end

-- field: "key" (the fishing key), "jumpKey", "lureKey" or "gearKey". A key given to one is taken from the others.
function F.SetKey(key, field)
    if InCombat() then return false end
    field = field or "key"
    if not F.KEYS[field] then return false end
    local db = DB()
    if key then
        for other in pairs(F.KEYS) do
            if other ~= field and (other == "jumpKey" and F.JumpKey() or db[other]) == key then db[other] = other == "jumpKey" and "" or nil end
        end
    end
    if field == "jumpKey" then db.jumpKey = key or "" else db[field] = key end
    F.UpdateBindings()
    F.Refresh()
    return true
end

-- Your bobber, as the thing your interact key reaches.
function F.BobberReady()
    local guid = Call(UnitGUID, "softinteract")
    if type(guid) ~= "string" then return false end
    return string.match(guid, "^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-") == F.BOBBER
end

-- While the line is out, the fishing key hooks: first nothing (until the bobber lands), then the interact key.
-- Never changed while the key is held: its release must reach what its press reached.
local function HookOn()
    local key = DB().key
    if not key or hooking == true then return end
    local token = {}
    hookToken = token
    local function Step()
        if hookToken ~= token or InCombat() then return end
        if not F.Channeling() then return F.HookOff() end -- the line ended (even without its event)
        if not Held(key) then
            local o = Owner("Hook")
            if F.BobberReady() or Now() - channelAt >= F.LAND then
                SetOverrideBinding(o, true, key, "INTERACTTARGET")
                hooking = true
                return
            elseif hooking ~= "wait" then
                SetOverrideBindingClick(o, true, key, F.WAIT, "LeftButton")
                hooking = "wait"
            end
        end
        After(0.1, Step)
    end
    Step()
end

local function HookOff(waited)
    hookToken = nil
    if not hooking or InCombat() then return end
    waited = waited or 0
    if Held(DB().key) and waited < 5 then return After(0.1, function() HookOff(waited + 0.1) end) end
    ClearOverrideBindings(Owner("Hook"))
    hooking = false
end
F.HookOff = HookOff

-- Double right-click: a quick right-click on open ground (not a drag, not on anything you could talk to or
-- loot) arms the right button for a moment; the second click casts on its release. Only with a pole in your
-- hands, out of combat, and never while your line is out (right-click the bobber itself then, or use the key).
local function OverWorldThing()
    if Call(UnitExists, "mouseover") then return true end
    return GameTooltip and GameTooltip.IsShown and GameTooltip:IsShown() and GameTooltip:GetOwner() == UIParent
end

function F.EasyReady(state)
    state = state or F.State()
    if not F.Opt("doubleClick") or state.combat or not state.spell or not state.pole or state.channel then return false end
    local action = F.Action(state)
    if action ~= "cast" and action ~= "lure" and action ~= "gear" then return false end
    if Call(IsMounted) or Call(SpellIsTargeting) or Call(UnitCastingInfo, "player") then return false end
    if LootFrame and LootFrame.IsShown and LootFrame:IsShown() then return false end
    return not OverWorldThing()
end

Disarm = function()
    if not armed or InCombat() then return end
    if Held("BUTTON2") then return After(0.1, Disarm) end
    ClearOverrideBindings(Owner("Mouse"))
    armed, armToken = false, nil
end
F.Disarm = Disarm

local function Arm()
    if armed or InCombat() or Held("BUTTON2") then return end
    SetOverrideBindingClick(Owner("Mouse"), true, "BUTTON2", F.BUTTON, "LeftButton")
    armed = true
    local token = {}
    armToken = token
    After(F.DOUBLE_CLICK, function() if armToken == token then Disarm() end end)
end

function F.WorldMouseDown(button)
    if button == "RightButton" then
        rDown = Now(); rx, ry = Call(GetCursorPosition); rx, ry = rx or 0, ry or 0
    elseif armed then
        Disarm() -- another click in between: no double-click
    end
end

function F.WorldMouseUp(button)
    if button ~= "RightButton" or not rDown or InCombat() then return end
    local quick = Now() - rDown < F.QUICK
    local x, y = Call(GetCursorPosition)
    rDown = nil
    if not quick or math.abs((x or 0) - rx) + math.abs((y or 0) - ry) >= F.MOVED or armed then return end
    if not F.EasyReady() then return end
    -- Not this moment: this release still has to reach the game (its press started the camera turn).
    After(0, function() if not armed and F.EasyReady() then SetAttributes(F.Action(F.State())); Arm() end end)
end
F.IsArmed = function() return armed end

-- ---- The fishing time: settings while you fish, put back afterwards ----
local function CVarGet(name) return (C_CVar and C_CVar.GetCVar or GetCVar)(name) end
local function CVarSet(name, value) return (C_CVar and C_CVar.SetCVar or SetCVar)(name, value) end

local modeOn = false
local function ModeOn()
    if InCombat() then return end
    local db = DB()
    local opts = { interact = DB().key ~= nil, marker = F.Opt("marker"), loot = F.Opt("loot"), sound = F.Opt("sound"),
        vol = { F.Num("volMaster"), F.Num("volSFX"), F.Num("volMusic"), F.Num("volAmbience") } }
    db.savedCVars = F.ApplyCVars(F.Wanted(opts, function(n) return Call(CVarGet, n) end), db.savedCVars or {}, CVarGet, CVarSet)
    modeOn = true
end

local function ModeOff()
    local db = DB()
    if db.savedCVars then F.RestoreCVars(db.savedCVars, CVarGet, CVarSet) end
    db.savedCVars = nil
    modeOn = false
end
F.ModeOff = ModeOff
function F.ModeIsOn() return modeOn end
F.Reapply = function() if modeOn then ModeOn() end end

local function CharKey()
    return (DufforthTweaksHelper and DufforthTweaksHelper.CharacterKey and Call(DufforthTweaksHelper.CharacterKey)) or "?"
end

-- This character's session (kept over a /reload); a long break starts a new one.
function F.Session(create)
    local all = DB().sessions
    local s = all[CharKey()]
    if create and (not s or Now() - s.last > F.NEW_SESSION or Now() < s.last) then
        s = F.NewSession(Now()); all[CharKey()] = s
    end
    return s
end
function F.EndSession() DB().sessions[CharKey()] = nil; F.Refresh() end

local function ZoneName()
    local Loc = DufforthTweaksHelperLocale
    local name = Loc and Loc.ZoneName and Call(Loc.ZoneName)
    if type(name) == "string" and name ~= "" then return name end
    return (GetRealZoneText and Call(GetRealZoneText)) or "?"
end
local function Zone()
    local zones = DB().zones
    local name = ZoneName()
    zones[name] = zones[name] or { casts = 0, catches = 0, escapes = 0, items = {} }
    return zones[name], name
end

Begin = function()
    local s = F.Session(true)
    s.last = Now()
    s.casts = s.casts + 1
    Zone().casts = Zone().casts + 1
    ModeOn()
end
F.Begin = Begin

function F.SetOpt(name, on)
    DB()[name] = on and true or false
    if modeOn then ModeOn() end -- a switch changed while fishing: the new mix now
    F.Refresh()
end

-- Weapons and your own gear back on (out of combat): the main hand first, the off hand once it's in.
function F.GearBack(tries)
    local db = DB()
    if InCombat() or not db.weapons or F.Channeling() then return end
    local equip = (C_Item and C_Item.EquipItemByName) or EquipItemByName
    if not equip then return end
    local w = db.weapons
    if not tries then
        if w[F.MAIN] and F.PoleEquipped() then pcall(equip, w[F.MAIN], F.MAIN) end
        for _, slot in ipairs({ 1, 8, 10, 13 }) do
            if w[slot] and Call(GetInventoryItemID, "player", slot) ~= w[slot] then pcall(equip, w[slot], slot) end
        end
        tries = 0
    end
    if w[F.OFF] then
        -- (the game puts the weapon on a moment after it's asked; the off hand waits for it, 3 s at most)
        if F.PoleEquipped() and tries < 6 then return After(0.5, function() F.GearBack(tries + 1) end) end
        pcall(equip, w[F.OFF], F.OFF)
    end
    db.weapons = nil
    F.Refresh()
end

function F.Idle()
    if modeOn then ModeOff() end
    if F.Opt("pole") then F.GearBack() end
end

-- Every second: the end of the fishing time, and the "cast again" sound.
function F.Tick()
    if F.Channeling() or InCombat() then return end
    local now = Now()
    if modeOn and stoppedAt > 0 and now - stoppedAt > F.IDLE then F.Idle(); F.Refresh(); return end
    if modeOn and stoppedAt > 0 and reminded == 0 and now - stoppedAt > F.REMIND then
        reminded = 1
        F.Alert("remind")
    end
end

function F.Alert(kind)
    local a = F.ALERTS[kind]
    if not a or not F.Opt(a[1]) then return false end
    local id = (SOUNDKIT and SOUNDKIT[a[2]]) or a[3]
    if PlaySound and id then pcall(PlaySound, id, "Master") end
    return true
end

-- ---- What you catch ----
local function Prices()
    local market = DufforthTweaksHelper and DufforthTweaksHelper.MarketName and Call(DufforthTweaksHelper.MarketName) or ""
    return DufforthTweaksHelperPrices and DufforthTweaksHelperPrices[market] or {}
end

-- What one is worth: the auction house after its 5% cut, else what a vendor pays.
function F.Value(id)
    local ah = Prices()[id]
    if ah and ah > 0 then return math.floor(ah * 0.95) end
    local getter = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local sell = select(11, Call(getter, id))
    return tonumber(sell) or 0
end

local recap -- the card that shows what you caught
local lastLoot = 0

local function ItemCount(id)
    local get = (C_Item and C_Item.GetItemCount) or GetItemCount
    return tonumber(Call(get, id)) or 0
end

local function LootList()
    local got = {}
    for i = 1, (Call(GetNumLootItems) or 0) do
        local link = Call(GetLootSlotLink, i)
        local id = type(link) == "string" and tonumber(string.match(link, "item:(%d+)")) or nil
        if id then
            local _, name, count = Call(GetLootSlotInfo, i)
            got[#got + 1] = { id = id, name = type(name) == "string" and name or nil, count = tonumber(count) or 1 }
        end
    end
    return got
end

-- A chest (crate, clam...) you fished up and open counts too: loot from an item in your bags, after which one
-- you caught this session is gone from your bags. Its loot and money go to the session.
local chestPending
function F.OnOtherLoot()
    local s = F.Session(false)
    if not s then return end
    local guid = GetLootSourceInfo and Call(GetLootSourceInfo, 1)
    if type(guid) == "string" and not string.find(guid, "^Item%-") then return end
    local counts = {}
    for id in pairs(s.items) do counts[id] = ItemCount(id) end
    chestPending = { counts = counts, got = LootList(), money = tonumber(Call(GetMoney)) or 0 }
end

function F.CreditChest()
    local p, s = chestPending, F.Session(false)
    chestPending = nil
    if not p or not s then return false end
    for id, before in pairs(p.counts) do
        if ItemCount(id) < before then
            s.chests = (s.chests or 0) + 1
            s.chestMoney = (s.chestMoney or 0) + math.max(0, (tonumber(Call(GetMoney)) or 0) - p.money)
            s.chestItems = s.chestItems or {}
            for _, g in ipairs(p.got) do
                local row = s.chestItems[g.id] or { id = g.id, name = g.name, count = 0 }
                row.count = row.count + g.count
                row.name = g.name or row.name
                s.chestItems[g.id] = row
            end
            return true
        end
    end
    return false
end

function F.OnLoot()
    if not (IsFishingLoot and Call(IsFishingLoot)) then return F.OnOtherLoot() end
    if Now() - lastLoot < 1 then return end -- LOOT_READY and LOOT_OPENED: once per catch
    lastLoot = Now()
    local s = F.Session(true)
    local zone = Zone()
    local all = DB().caught
    s.catches = s.catches + 1
    s.last = Now()
    zone.catches = zone.catches + 1
    local wait = channelAt > 0 and Now() - channelAt or nil
    if wait and wait > 0 and wait <= 30 then s.waits = s.waits + wait; s.waitN = s.waitN + 1 end
    local got = {}
    for i = 1, (Call(GetNumLootItems) or 0) do
        local link = Call(GetLootSlotLink, i)
        local id = type(link) == "string" and tonumber(string.match(link, "item:(%d+)")) or nil
        if id then
            local _, name, count = Call(GetLootSlotInfo, i)
            if type(name) ~= "string" then name = nil end
            count = tonumber(count) or 1
            local first = all[id] == nil
            F.Record(s, id, name, count)
            local row = all[id] or { count = 0 }
            row.count = row.count + count
            row.name = name or row.name
            all[id] = row
            zone.items[id] = (zone.items[id] or 0) + count
            got[#got + 1] = { id = id, name = name or row.name or ("item " .. id), count = count, first = first }
        end
    end
    if #got > 0 then
        F.Alert("catch")
        if F.Opt("recap") then F.ShowRecap(got) end
    end
end

function F.OnError(message)
    if type(message) ~= "string" then return end
    if message == ERR_FISH_ESCAPED or message == FISH_ESCAPED then
        local s = F.Session(false)
        if s then s.escapes = s.escapes + 1 end
        Zone().escapes = Zone().escapes + 1
        F.Alert("escape")
        return
    end
    local p = F.Pattern(SPELL_FAILED_FISHING_TOO_LOW)
    local need = p and tonumber(string.match(message, p))
    if need then Zone().need = need end
end

local function Money(copper)
    copper = math.floor(copper or 0)
    if copper >= 10000 then return string.format(L["%dg %ds"], math.floor(copper / 10000), math.floor(copper % 10000 / 100)) end
    if copper >= 100 then return string.format(L["%ds %dc"], math.floor(copper / 100), copper % 100) end
    return string.format(L["%dc"], copper)
end
F.Money = Money

-- ---- What the bar and the panel say ----
local function KeyText()
    local key = DB().key
    return key and (GetBindingText and Call(GetBindingText, key) or key) or nil
end

function F.StatusText(state, action, reason)
    local key = KeyText()
    local how = key and (F.Opt("doubleClick") and string.format(L["Press %s or double right-click"], key)
        or string.format(L["Press %s"], key))
        or (F.Opt("doubleClick") and L["Double right-click"] or L["Click the fishing bar's icon"])
    if action == "none" then
        if reason == "combat" then return L["|cffff5555In combat: fishing waits until the fight ends.|r"] end
        if reason == "unknown" then return L["Learn Fishing from a fishing trainer first."] end
        if reason == "nopole" then return L["|cffffd100Get a fishing pole: none equipped or in your bags.|r"] end
        if reason == "bagsfull" then return L["|cffffd100Make room for one item in your bags: your off hand goes there.|r"] end
    end
    if action == "hook" then
        if not key then return L["|cff33ff33Right-click the bobber when it splashes.|r"] end
        return "|cff33ff33" .. string.format(L["Press %s"], key) .. L[" to hook the fish when the bobber splashes.|r"]
    end
    if action == "gear" then return how .. L[" to put on your fishing gear."] end
    if action == "lure" then return how .. L[" to put a lure on the pole."] end
    if action == "food" then return how .. L[" to eat your fishing food."] end
    if not key and not F.Opt("doubleClick") then return L["Set a fishing key below, or click the fishing bar's icon."] end
    return how .. L[" to cast."]
end

local function TitleText(state)
    local skill = F.Skill()
    local text = skill and string.format(L["Fishing %d"], skill) or L["Fishing"]
    if state and state.bonus and state.bonus > 0 then text = text .. string.format(L[" +%d"], state.bonus) end
    local left = F.LureLeft()
    if left then text = text .. string.format(L["   lure %d:%02d"], math.floor(left / 60), math.floor(left % 60)) end
    return text
end

local function CountText(now)
    local s = F.Session(false)
    if not s then return L["No catches yet this session."] end
    local text = string.format(L["%d catches, %d an hour"], s.catches, math.floor(F.PerHour(s, now) + 0.5))
    if s.escapes > 0 then text = text .. string.format(L[", %d got away"], s.escapes) end
    return text
end

-- ---- On screen: the fishing bar, the catch card, the mark on your bobber ----
local bar
local function Bar()
    if bar or InCombat() then return bar end
    local db = DB()
    bar = CreateFrame("Frame", "DufforthTweaksHelperFishingBar", UIParent, "BackdropTemplate")
    bar:SetSize(280, 48)
    if bar.SetBackdrop then
        bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        bar:SetBackdropColor(0.05, 0.05, 0.06, 0.92); bar:SetBackdropBorderColor(0.25, 0.6, 1, 0.8)
    end
    local p = db.point
    if p then bar:SetPoint(p[1], UIParent, p[1], p[2], p[3]) else bar:SetPoint("CENTER", UIParent, "CENTER", 260, -120) end
    bar:SetMovable(true); bar:EnableMouse(true); bar:RegisterForDrag("LeftButton"); bar:SetClampedToScreen(true)
    bar:SetScript("OnDragStart", function(self) if not InCombat() and not F.Opt("lock") then self:StartMoving() end end)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local a, _, _, x, y = self:GetPoint()
        if a then DB().point = { a, x, y } end
    end)
    -- The icon is a second secure button with the same action as the key (a click: cast, gear, lure).
    local icon = SecureButton("DufforthTweaksHelperFishBarButton", bar, false)
    icon:SetSize(36, 36); icon:SetPoint("LEFT", 6, 0)
    icon.tex = icon:CreateTexture(nil, "ARTWORK"); icon.tex:SetAllPoints()
    icon.tex:SetTexture("Interface\\Icons\\Trade_Fishing")
    icon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Fishing"], 1, 0.82, 0)
        GameTooltip:AddLine(L["Click: cast, or put on your fishing gear / a lure first."], 1, 1, 1, true)
        GameTooltip:AddLine(L["To hook, use your fishing key or right-click the bobber (a click here can't hook)."], 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(L["Drag the bar to move it. /dth fishing opens the options."], 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Weapons back at once (out of combat).
    local back = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    back:SetSize(64, 18); back:SetPoint("TOPRIGHT", -4, -4); back:SetText(L["Weapons"])
    back:SetScript("OnClick", function() F.GearBack() end)
    back:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Puts your weapons and own gear back on now."], 1, 1, 1, 1, true); GameTooltip:Show()
    end)
    back:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar.back = back
    local function Line(y, font, w)
        local t = bar:CreateFontString(nil, "OVERLAY", font)
        t:SetPoint("TOPLEFT", 48, y); t:SetWidth(w or 224); t:SetJustifyH("LEFT")
        if t.SetWordWrap then t:SetWordWrap(false) end
        return t
    end
    bar.title = Line(-5, "GameFontNormalSmall", 160)
    bar.status = Line(-19, "GameFontHighlightSmall")
    bar.count = Line(-33, "GameFontDisableSmall")
    if DufforthTweaksHelper and DufforthTweaksHelper.RegisterMovable then
        DufforthTweaksHelper.RegisterMovable({ label = L["Fishing bar"], get = function() return bar end,
            enter = function(frame) frame:Show() end, leave = function() F.Refresh() end })
    end
    bar:Hide()
    return bar
end
F.Bar = Bar

-- The catch card: a few seconds above the bar (or high in the middle), one line per item. The mouse goes through.
function F.ShowRecap(got)
    if not recap then
        recap = CreateFrame("Frame", "DufforthTweaksHelperFishCatch", UIParent, "BackdropTemplate")
        recap:SetSize(280, 20)
        recap:SetFrameStrata("HIGH")
        if recap.EnableMouse then recap:EnableMouse(false) end
        if recap.SetBackdrop then
            recap:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            recap:SetBackdropColor(0.05, 0.05, 0.06, 0.9); recap:SetBackdropBorderColor(1, 0.82, 0, 0.7)
        end
        recap.lines = {}
        for i = 1, 4 do
            local t = recap:CreateFontString(nil, "OVERLAY", i == 1 and "GameFontNormalSmall" or "GameFontHighlightSmall")
            t:SetPoint("TOPLEFT", 8, -5 - (i - 1) * 14); t:SetWidth(264); t:SetJustifyH("LEFT")
            if t.SetWordWrap then t:SetWordWrap(false) end
            recap.lines[i] = t
        end
    end
    local s = F.Session(false)
    recap.lines[1]:SetText(string.format(L["Your catch (%d this session)"], s and s.catches or 1))
    local shown = 1
    for i = 1, 3 do
        local g = got[i]
        if g then
            local worth = F.Value(g.id) * g.count
            local tail = g.first and L["   |cff33ff33First catch!|r"] or (worth > 0 and ("   |cffaaaaaa" .. Money(worth) .. "|r") or "")
            recap.lines[i + 1]:SetText(string.format(L["%d x %s"], g.count, g.name) .. tail)
            shown = i + 1
        else
            recap.lines[i + 1]:SetText("")
        end
    end
    recap:SetHeight(10 + shown * 14)
    recap:ClearAllPoints()
    if bar and bar:IsShown() then recap:SetPoint("BOTTOM", bar, "TOP", 0, 6) else recap:SetPoint("TOP", UIParent, "TOP", 0, -160) end
    recap:Show()
    local token = {}
    recap.token = token
    After(4, function() if recap.token == token then recap:Hide() end end)
end

-- The mark on your bobber: our round icon above its nameplate (the game gives the bobber one while it's your
-- interact key's target), bobbing gently; the game's own small icon steps aside meanwhile. Nothing to click.
local mark
local function BobberPlate()
    local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
    local plate = get and Call(get, "softinteract")
    return type(plate) == "table" and plate or nil
end

local function GameIcon(plate)
    local ok, icon = pcall(function() return plate.UnitFrame and plate.UnitFrame.SoftTargetFrame end)
    if ok and type(icon) == "table" and icon.SetAlpha then return icon end
end

function F.HideMark()
    if mark and mark.gameIcon then pcall(mark.gameIcon.SetAlpha, mark.gameIcon, 1); mark.gameIcon = nil end
    if mark then mark:Hide(); mark.plate = nil end
end

function F.UpdateMark()
    if not (F.Opt("marker") and F.Channeling() and F.BobberReady()) then return F.HideMark() end
    local plate = BobberPlate()
    if not plate then return F.HideMark() end
    if not mark then
        mark = CreateFrame("Frame", "DufforthTweaksHelperFishMark", UIParent)
        mark:SetSize(28, 28); mark:SetFrameStrata("LOW")
        if mark.EnableMouse then mark:EnableMouse(false) end
        local tex = mark:CreateTexture(nil, "ARTWORK"); tex:SetAllPoints()
        tex:SetTexture("Interface\\AddOns\\DufforthTweaksHelper\\Media\\GuideIcon")
        local ag = mark.CreateAnimationGroup and mark:CreateAnimationGroup()
        local up = ag and ag.CreateAnimation and ag:CreateAnimation("Translation")
        if up then
            up:SetOffset(0, 5); up:SetDuration(0.7)
            if ag.SetLooping then ag:SetLooping("BOUNCE") end
            mark.bob = ag
        end
        mark:Hide()
    end
    if mark.plate ~= plate then
        F.HideMark()
        local icon = GameIcon(plate)
        if icon and pcall(icon.SetAlpha, icon, 0) then mark.gameIcon = icon end
        mark:ClearAllPoints()
        if not pcall(mark.SetPoint, mark, "BOTTOM", plate, "TOP", 0, mark.gameIcon and 4 or 20) then return F.HideMark() end
        mark.plate = plate
    end
    if not mark:IsShown() then
        mark:Show()
        if mark.bob and mark.bob.Play then mark.bob:Play() end
    end
end
F.MarkShown = function() return mark ~= nil and mark:IsShown() end

local function WatchMark()
    local token = {}
    F.markToken = token
    local function Tick()
        if F.markToken ~= token then return end
        F.UpdateMark()
        if F.Channeling() then After(0.25, Tick) end
    end
    Tick()
end

local panel -- the Fishing tab's controls

function F.Refresh()
    local state = F.State()
    local action, value = F.Action(state)
    if not InCombat() then
        if not armed then SetAttributes(action, value) end
        SetSideButtons(state)
        F.UpdateBindings(state)
    end
    local status = F.StatusText(state, action, value)
    local b = Bar()
    if b and not InCombat() then
        local show = F.Opt("bar") and state.spell and (state.pole or modeOn) and true or false
        if DufforthTweaksHelper and DufforthTweaksHelper.EditMode and DufforthTweaksHelper.EditMode() then show = true end
        b:SetShown(show)
        b.title:SetText(TitleText(state)); b.status:SetText(status); b.count:SetText(CountText(Now()))
        b.back:SetShown(DB().weapons ~= nil)
    end
    if panel then panel.Refresh(state, status) end
end

-- ---- The Codex: what bites where (Classic data, FishingData.lua) next to what you caught there ----
local function Codex() return DufforthTweaksHelperFishCodex or { zones = {}, names = {}, chests = {} } end

function F.ItemName(id)
    local name = Codex().names[id]
    if name then return name end
    local row = DB().caught[id]
    if row and row.name then return row.name end
    local getter = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local n = Call(getter, id)
    return type(n) == "string" and n or ("item " .. id)
end

-- Every zone with a list or with your own catches, by name.
function F.CodexZones()
    local seen, out = {}, {}
    for name in pairs(Codex().zones) do seen[name] = true end
    for name, z in pairs(DB().zones) do if next(z.items or {}) then seen[name] = true end end
    for name in pairs(seen) do if name ~= "?" then out[#out + 1] = name end end
    table.sort(out)
    return out
end

-- A zone's rows: { head = text } or { id, pct (Classic, or nil), mine (your catches there) }.
function F.CodexRows(zone)
    local rows, listed = {}, {}
    local z = Codex().zones[zone]
    local mine = (DB().zones[zone] or {}).items or {}
    local function List(loot)
        for _, r in ipairs(loot) do
            rows[#rows + 1] = { id = r[1], pct = r[2], mine = mine[r[1]] or 0 }
            listed[r[1]] = true
        end
    end
    if z then
        if z.loot and #z.loot > 0 then List(z.loot) end
        local places = {}
        for place in pairs(z.subs or {}) do places[#places + 1] = place end
        table.sort(places)
        for _, place in ipairs(places) do
            rows[#rows + 1] = { head = place }
            List(z.subs[place])
        end
    end
    local extra = {}
    for id, n in pairs(mine) do if not listed[id] then extra[#extra + 1] = { id = id, mine = n } end end
    if #extra > 0 then
        table.sort(extra, function(a, b) return a.mine > b.mine end)
        rows[#rows + 1] = { head = L["Also caught here (yours)"] }
        for _, r in ipairs(extra) do rows[#rows + 1] = r end
    end
    return rows
end

-- ---- The Fishing tab ----
local PERKS = {
    { "doubleClick", L["Double right-click"], L["A quick right-click on open water, then a second one, casts while a fishing pole is in your hands. A second click held down turns the camera as usual. Right-clicking a person, monster or anything you can loot stays normal."] },
    { "pole", L["Fishing gear"], L["The first press puts on your best fishing pole and any fishing hat, boots, gloves or trinket from your bags (read from their tooltips); the next one casts. Your weapons and own gear go back on 90 seconds after your last cast, after a fight, or with the Weapons button."] },
    { "lure", L["Put on a lure"], L["When the pole has no lure, the press puts on your best lure first (Aquadynamic Fish Attractor, Bright Baubles, Flesh Eating Worm, Nightcrawlers, Shiny Bauble)."] },
    { "food", L["Eat fishing food"], L["When you have no fishing buff, the press eats the best food in your bags that gives Fishing (read from its tooltip) before casting. Sit until you're Well Fed: casting stands you up."] },
    { "loot", L["Auto loot"], L["Turns on the game's auto loot while you fish, and back to your setting afterwards."] },
    { "sound", L["Louder splash"], L["While you fish: sound effects at full volume; music, ambience, voices and the error speech off, so the splash is easy to hear. Your settings come back when you stop (unless you changed one yourself meanwhile). The volumes are in Keys and sound."] },
    { "marker", L["Mark my bobber"], L["Our round icon bobs above your own bobber once it has landed, so you can tell it from anyone else's."] },
    { "bar", L["Fishing bar"], L["A small bar on screen while a pole is equipped: click its icon to cast, and see your skill and bonus, lure time and catches. Drag it to move it."] },
    { "lock", L["Lock the bar"], L["The fishing bar stays where it is (Move pieces still moves it)."] },
    { "recap", L["Show what I caught"], L["A card for a few seconds after each catch: what it is, how many, and what it's worth (or First catch!)."] },
    { "alertCatch", L["Sound: a catch"], L["A sound with every catch."] },
    { "alertEscape", L["Sound: it got away"], L["A sound when a fish gets away because you were too slow."] },
    { "alertRemind", L["Sound: cast again"], L["A sound when you've had no line out for 20 seconds while you're still fishing."] },
}
local KEY_ROWS = {
    { "key", L["Fishing key"], L["Click, then press the key you want for fishing (with Shift, Ctrl or Alt if you like). The key casts on release, and once the bobber has landed it hooks the fish. It works only while you can fish and never in combat; the key's normal use comes back otherwise. Right-click clears it."] },
    { "jumpKey", L["Jump while fishing"], L["When your fishing key is your jump key (Space), this key jumps while you fish. Shift+Space at first. Right-click clears it."] },
    { "lureKey", L["Lure key"], L["Puts your best lure on the pole, whenever you like (not only when it has none). Right-click clears it."] },
    { "gearKey", L["Gear key"], L["Puts your fishing gear on, or your weapons and own gear back. Right-click clears it."] },
}
local VOLUMES = {
    { "volMaster", L["Game volume"], -1 },
    { "volSFX", L["Sound effects"], 0 },
    { "volMusic", L["Music"], 0 },
    { "volAmbience", L["Ambience"], 0 },
}

function F.KeyLabel(field)
    local key = field == "jumpKey" and F.JumpKey() or DB()[field]
    return key and (GetBindingText and Call(GetBindingText, key) or key) or nil
end

function F.BuildPanel(page, width)
    local refreshers = {}
    local function Tip(owner, text)
        owner:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(text, 1, 1, 1, 1, true); GameTooltip:Show()
        end)
        owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local function Text(parent, x, y, font, w)
        local t = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
        t:SetPoint("TOPLEFT", x, y); t:SetWidth(w or (width - x - 8)); t:SetJustifyH("LEFT")
        if t.SetWordWrap then t:SetWordWrap(false) end
        return t
    end
    local function Btn(parent, text, w, tip, onClick)
        local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetSize(w, 20); b:SetText(text)
        b:SetScript("OnClick", onClick)
        if tip then Tip(b, tip) end
        return b
    end

    local title = Text(page, 8, -4, "GameFontNormal")
    local status = Text(page, 8, -22, "GameFontHighlightSmall")

    -- Three views: the switches and counters, the keys and volumes, the Codex.
    local views, viewButtons = {}, {}
    local VIEWS = { { "main", L["Fishing"] }, { "keys", L["Keys and sound"] }, { "codex", L["Codex"] } }
    local function ShowView(name)
        if not views[name] then name = "main" end
        DB().view = name
        for key, v in pairs(views) do v:SetShown(key == name) end
        for key, b in pairs(viewButtons) do if b.LockHighlight then if key == name then b:LockHighlight() else b:UnlockHighlight() end end end
        F.Refresh()
    end
    F.ShowView = ShowView
    for i, v in ipairs(VIEWS) do
        local b = Btn(page, v[2], 120, nil, function() ShowView(v[1]) end)
        b:SetPoint("TOPLEFT", 8 + (i - 1) * 124, -40)
        viewButtons[v[1]] = b
        local f = CreateFrame("Frame", nil, page)
        f:SetPoint("TOPLEFT", 0, -66); f:SetPoint("BOTTOMRIGHT", 0, 0)
        f:Hide()
        views[v[1]] = f
    end

    -- A key row: click, then press a key; right-click clears it.
    local function KeyRow(parent, y, row)
        Text(parent, 8, y - 4, "GameFontHighlightSmall", 130):SetText(row[2])
        local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetSize(150, 22); b:SetPoint("TOPLEFT", 140, y)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local capture = CreateFrame("Frame", nil, parent)
        capture:Hide()
        if capture.EnableKeyboard then capture:EnableKeyboard(true) end
        if capture.SetPropagateKeyboardInput then capture:SetPropagateKeyboardInput(false) end
        capture:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then self:Hide(); F.Refresh(); return end
            local name = F.KeyName(key, Call(IsAltKeyDown), Call(IsControlKeyDown), Call(IsShiftKeyDown))
            if not name then return end
            self:Hide()
            F.SetKey(name, row[1])
        end)
        b:SetScript("OnClick", function(_, mouse)
            if InCombat() then return end
            if mouse == "RightButton" then capture:Hide(); F.SetKey(nil, row[1]); return end
            capture:Show()
            b:SetText(L["Press a key (Esc cancels)"])
        end)
        Tip(b, row[3])
        refreshers[#refreshers + 1] = function()
            if not capture:IsShown() then b:SetText(F.KeyLabel(row[1]) or L["Set a key"]) end
        end
        return b
    end

    -- ---- Main view ----
    local main = views.main
    KeyRow(main, 0, KEY_ROWS[1])
    local back = Btn(main, L["Weapons back"], 110, L["Puts your weapons and own gear back on now."], function() F.GearBack() end)
    back:SetPoint("TOPRIGHT", -6, 0)
    refreshers[#refreshers + 1] = function() if back.SetEnabled then back:SetEnabled(DB().weapons ~= nil) end end
    local colWidth = math.floor((width - 16) / 2)
    for i, perk in ipairs(PERKS) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local box = CreateFrame("CheckButton", nil, main, "UICheckButtonTemplate")
        box:SetSize(22, 22); box:SetPoint("TOPLEFT", 8 + col * colWidth, -26 - row * 22)
        local label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", box, "RIGHT", 2, 0); label:SetWidth(colWidth - 30); label:SetJustifyH("LEFT")
        if label.SetWordWrap then label:SetWordWrap(false) end
        label:SetText(perk[2])
        box:SetScript("OnClick", function(self) F.SetOpt(perk[1], self:GetChecked() and true or false) end)
        Tip(box, perk[3])
        refreshers[#refreshers + 1] = function() box:SetChecked(F.Opt(perk[1])) end
    end
    local y = -26 - math.ceil(#PERKS / 2) * 22 - 6
    local session = Text(main, 8, y, "GameFontNormal", width - 130)
    local reset = Btn(main, L["New session"], 110, L["Starts the catch counters again (a cast after 30 minutes away does it too)."], function() F.EndSession() end)
    reset:SetPoint("TOPRIGHT", -6, y + 3)
    local chests = Text(main, 8, y - 18, "GameFontHighlightSmall")
    local here = Text(main, 8, y - 33, "GameFontHighlightSmall")
    y = y - 51
    local lines = {}
    for i = 1, 5 do lines[i] = Text(main, 16, y - (i - 1) * 15, "GameFontHighlightSmall") end
    local allTime = Text(main, 8, y - 5 * 15 - 3, "GameFontDisableSmall")
    local other = Text(main, 8, y - 5 * 15 - 18, "GameFontDisableSmall")

    -- ---- Keys and sound ----
    local keys = views.keys
    for i, row in ipairs(KEY_ROWS) do KeyRow(keys, -(i - 1) * 26, row) end
    Text(keys, 8, -4 * 26 - 6, "GameFontNormal"):SetText(L["Volumes while you fish (Louder splash on)"])
    for i, v in ipairs(VOLUMES) do
        local vy = -4 * 26 - 26 - (i - 1) * 24
        Text(keys, 16, vy - 4, "GameFontHighlightSmall", 140):SetText(v[2])
        local value = Text(keys, 236, vy - 4, "GameFontHighlightSmall", 60)
        value:SetJustifyH("CENTER")
        local minus = Btn(keys, "-", 24, nil, function()
            local cur = F.Num(v[1])
            F.SetNum(v[1], (v[3] < 0 and cur <= 0) and -1 or math.max(v[3], cur - 0.1))
        end)
        minus:SetPoint("TOPLEFT", 206, vy)
        local plus = Btn(keys, "+", 24, nil, function() F.SetNum(v[1], math.min(1, math.max(0, F.Num(v[1]) + 0.1))) end)
        plus:SetPoint("TOPLEFT", 300, vy)
        refreshers[#refreshers + 1] = function()
            local cur = F.Num(v[1])
            value:SetText(cur < 0 and L["Yours"] or string.format(L["%d%%"], math.floor(cur * 100 + 0.5)))
        end
    end

    -- ---- Codex ----
    local codex = views.codex
    local zoneLabel = Text(codex, 40, -4, "GameFontNormal", width - 170)
    zoneLabel:SetJustifyH("CENTER")
    local function Browse(step)
        local list = F.CodexZones()
        if #list == 0 then return end
        local at = 1
        for i, name in ipairs(list) do if name == F.codexZone then at = i end end
        F.codexZone = list[(at - 1 + step) % #list + 1]
        F.Refresh()
    end
    Btn(codex, "<", 26, L["Previous zone"], function() Browse(-1) end):SetPoint("TOPLEFT", 8, 0)
    Btn(codex, ">", 26, L["Next zone"], function() Browse(1) end):SetPoint("TOPRIGHT", -96, 0)
    Btn(codex, L["Here"], 80, L["The zone you're in."], function() F.codexZone = nil; F.Refresh() end):SetPoint("TOPRIGHT", -8, 0)
    local codexRows = {}
    for i = 1, 16 do
        local r = CreateFrame("Button", nil, codex)
        r:SetSize(width - 24, 15); r:SetPoint("TOPLEFT", 12, -26 - (i - 1) * 15)
        r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.label:SetPoint("LEFT", 0, 0); r.label:SetWidth(width - 24); r.label:SetJustifyH("LEFT")
        if r.label.SetWordWrap then r.label:SetWordWrap(false) end
        r:SetScript("OnEnter", function(self)
            if not self.id then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.id) else GameTooltip:SetText(F.ItemName(self.id)) end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        codexRows[i] = r
    end
    Text(codex, 8, -26 - 16 * 15 - 4, "GameFontDisableSmall"):SetText(L["Chances per catch from Classic data (CMaNGOS); Forever may differ, so your own catches show next to them."])

    panel = {}
    function panel.Refresh(state, statusText)
        title:SetText(TitleText(state))
        status:SetText(statusText)
        for _, r in ipairs(refreshers) do r() end
        -- main
        local s = F.Session(false)
        local rows2, total = F.Rows(s and s.items or {}, F.Value)
        if s then
            local text = CountText(Now()) .. (total > 0 and string.format(L[", worth %s"], Money(total)) or "")
            if s.waitN > 0 then text = text .. string.format(L[", a bite every %d s"], math.floor(s.waits / s.waitN + 0.5)) end
            session:SetText(text)
            local crow, cworth = F.Rows(s.chestItems or {}, F.Value)
            if (s.chests or 0) > 0 then
                chests:SetText(string.format(L["%d chests opened: %s in coins, %d items worth %s"], s.chests, Money(s.chestMoney or 0), #crow, Money(cworth)))
            else
                chests:SetText("")
            end
        else
            session:SetText(L["No catches yet this session."])
            chests:SetText("")
        end
        local zone, zoneName = Zone()
        local ztext = string.format(L["Here (%s): %d casts, %d catches"], zoneName, zone.casts, zone.catches)
        if zone.need then ztext = ztext .. string.format(L[", needs Fishing %d"], zone.need) end
        here:SetText(ztext)
        for i, line in ipairs(lines) do
            local r = rows2[i]
            if r then
                line:SetText(string.format(L["%d x %s"], r.count, r.name) .. (r.value > 0 and ("   |cffaaaaaa" .. Money(r.value) .. "|r") or ""))
            elseif i == 1 then
                line:SetText(L["|cffaaaaaaWhat you catch shows here.|r"])
            else
                line:SetText("")
            end
        end
        local count = 0
        for _, row in pairs(DB().caught) do count = count + (row.count or 0) end
        allTime:SetText(string.format(L["All time on this account: %d fish and items caught."], count))
        local gaap = C_AddOns and C_AddOns.IsAddOnLoaded and Call(C_AddOns.IsAddOnLoaded, "GaapOneKeyFishing")
        other:SetText(gaap and L["|cffffd100Gaap One-Key Fishing is on too: give the two different keys, or turn one off.|r"] or "")
        -- codex
        local cz = F.codexZone or zoneName
        zoneLabel:SetText(cz)
        local list = F.CodexRows(cz)
        for i, r in ipairs(codexRows) do
            local row = list[i]
            r.id = row and row.id
            if not row then
                r.label:SetText(i == 1 and L["|cffaaaaaaNo fish known here yet: fish here, or pick a zone with < and >.|r"] or "")
            elseif row.head then
                r.label:SetText("|cffffd100" .. row.head .. "|r")
            else
                local pct = row.pct and string.format(L["%.1f%%"], row.pct) or "   "
                local mine = row.mine > 0 and string.format(L["   |cff33ff33you: %d|r"], row.mine) or ""
                local worth = F.Value(row.id)
                local chest = Codex().chests[row.id] and L[" (opens)"] or ""
                r.label:SetText(pct .. "  " .. F.ItemName(row.id) .. chest .. mine .. (worth > 0 and ("   |cffaaaaaa" .. Money(worth) .. "|r") or ""))
            end
        end
    end
    ShowView(DB().view or "main")
end

-- ---- Events (each registered in pcall: an unknown event on this client must not break the rest) ----
local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "PLAYER_EQUIPMENT_CHANGED",
    "UNIT_INVENTORY_CHANGED", "BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED", "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED",
    "UI_ERROR_MESSAGE", "PLAYER_SOFT_INTERACT_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }) do
    pcall(events.RegisterEvent, events, e)
end
F.events = events

function F.OnEvent(event, a1, a2, a3)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Just before the fight locks things: bindings off, bar away, settings back. Nothing during the fight.
        if ClearOverrideBindings then for _, o in pairs(owners) do ClearOverrideBindings(o) end end
        armed, hooking, hookToken = false, false, nil
        if bar then bar:Hide() end
        F.HideMark()
        ModeOff()
        return
    end
    if event == "PLAYER_SOFT_INTERACT_CHANGED" or event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
        return F.UpdateMark()
    end
    if event == "UI_ERROR_MESSAGE" then return F.OnError(a2) end
    if event == "LOOT_READY" or event == "LOOT_OPENED" then return F.OnLoot() end
    if event == "LOOT_CLOSED" then
        if chestPending then After(0.5, function() if F.CreditChest() then F.Refresh() end end) end
        return
    end
    if InCombat() then return end
    if event == "PLAYER_LOGIN" then
        -- A /reload or crash while fishing: your settings back first.
        local db = DB()
        if db.savedCVars then F.RestoreCVars(db.savedCVars, CVarGet, CVarSet); db.savedCVars = nil end
        if WorldFrame and WorldFrame.HookScript then
            pcall(WorldFrame.HookScript, WorldFrame, "OnMouseDown", function(_, button) pcall(F.WorldMouseDown, button) end)
            pcall(WorldFrame.HookScript, WorldFrame, "OnMouseUp", function(_, button) pcall(F.WorldMouseUp, button) end)
        end
        if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, function() pcall(F.Tick) end) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if F.Opt("pole") then F.GearBack() end
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        if a1 ~= "player" or not F.Channeling() then return end
        channelAt, reminded = Now(), 0
        Disarm()
        Begin()
        HookOn()
        WatchMark()
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if a1 ~= "player" then return end
        stoppedAt = Now()
        F.UpdateMark()
        -- The key goes back to casting a moment later: the release of the press that hooked must not cast.
        After(0.4, function() if not F.Channeling() then HookOff() end end)
    elseif string.find(event, "^UNIT_") and a1 ~= "player" then
        return
    end
    F.Refresh()
end

events:SetScript("OnEvent", function(_, event, a1, a2, a3)
    pcall(F.OnEvent, event, a1, a2, a3) -- a failure here must never spill into chat or other features
end)
