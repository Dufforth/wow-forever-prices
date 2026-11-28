-- Dufforth Tweaks Helper, leveling guide: the game side of RestedXP's step engine (GuideRx.lua). Adds what the engine
-- reads from the game to the box's adapter, tells it what you did (hearthstone, taxi, vendor and trainer windows,
-- spells, resurrecting, binding), keeps the "DTH Target" macro on the active steps' NPCs and monsters, and gives
-- the arrow its point. Behaviour follows RestedXP (RXPGuides, CC BY-NC-SA 4.0; credit in LICENSE-DATA.md).

local UI = DufforthTweaksHelperGuideUI
local RxUI = {}
DufforthTweaksHelperGuideRxUI = RxUI

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- Seconds left on a spell or item cooldown (0 when ready), nil when the game won't say.
local function CooldownLeft(kind, id)
    if not id then return nil end
    local start, duration
    if kind == "item" then
        if C_Container and C_Container.GetItemCooldown then start, duration = C_Container.GetItemCooldown(id)
        elseif GetItemCooldown then start, duration = GetItemCooldown(id) end
    elseif kind == "spell" then
        if C_Spell and C_Spell.GetSpellCooldown then
            local info = C_Spell.GetSpellCooldown(id)
            if info then start, duration = info.startTime, info.duration end
        elseif GetSpellCooldown then start, duration = GetSpellCooldown(id) end
    end
    if start == nil or duration == nil or Secret(start) or Secret(duration) then return nil end
    if start == 0 or duration == 0 then return 0 end
    return math.max(0, start + duration - (GetTime and GetTime() or 0))
end

local function AreaName(id)
    if not (id and C_Map and C_Map.GetAreaInfo) then return nil end
    return C_Map.GetAreaInfo(id)
end

-- The engine's extra game calls (Guide.lua's adapter has the rest).
function RxUI.Extend(a)
    a.who = function()
        local class = UnitClass and select(2, UnitClass("player"))
        local race = UnitRace and select(2, UnitRace("player"))
        local faction = UnitFactionGroup and UnitFactionGroup("player")
        return { class = class, race = race, faction = faction }
    end
    a.objectiveIndexDone = function(id, k)
        if not (a.inLog(id) and C_QuestLog and C_QuestLog.GetQuestObjectives) then return nil end
        local ok, list = pcall(C_QuestLog.GetQuestObjectives, id)
        local o = ok and type(list) == "table" and list[k]
        if not o then return nil end
        return o.finished and true or false
    end
    a.ghost = function() return UnitIsGhost ~= nil and UnitIsGhost("player") and true or false end
    a.corpse = function()
        local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local pos = map and C_DeathInfo and C_DeathInfo.GetCorpseMapPosition and C_DeathInfo.GetCorpseMapPosition(map)
        if not pos then return nil end
        local x, y
        if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
        if not x then return nil end
        return DufforthTweaksHelperLocale.MapZone(map) or DufforthTweaksHelperLocale.ZoneName(), x * 100, y * 100
    end
    a.itemCount = function(id)
        local count = (C_Item and C_Item.GetItemCount) or GetItemCount
        return id and count and (count(id) or 0) or 0
    end
    a.spellKnown = function(id)
        if not id then return false end
        if IsPlayerSpell and IsPlayerSpell(id) then return true end
        return IsSpellKnown ~= nil and IsSpellKnown(id) and true or false
    end
    a.money = function() return GetMoney and GetMoney() or 0 end
    a.inArea = function(id)
        local name = AreaName(id)
        if not name then return false end
        return (GetSubZoneText and GetSubZoneText() == name) or (GetZoneText and GetZoneText() == name) or false
    end
    a.bindIs = function(id)
        local name = AreaName(id)
        return name ~= nil and GetBindLocation ~= nil and GetBindLocation() == name
    end
    a.onTaxi = function() return UnitOnTaxi ~= nil and UnitOnTaxi("player") and true or false end
    a.skill = function(name)
        if not (GetNumSkillLines and GetSkillLineInfo) then return nil end
        name = string.lower(name or "")
        for i = 1, GetNumSkillLines() do
            local skill, header, _, rank = GetSkillLineInfo(i)
            if not header and skill and string.lower(skill) == name then return rank end
        end
        return 0
    end
    a.cooldownLeft = CooldownLeft
    a.slotStat = function(slot, stat)
        if not slot then return nil end
        if stat == "QUALITY" then return GetInventoryItemQuality and GetInventoryItemQuality("player", slot) end
        local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
        if not link then return nil end
        if stat == "LEVEL" then
            local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
            return info and select(4, info(link)) or nil
        end
        local stats = (C_Item and C_Item.GetItemStats and C_Item.GetItemStats(link)) or (GetItemStats and GetItemStats(link))
        return stats and stats[stat] or nil
    end
    a.has = function(kind, v)
        local id = v and v[#v]
        if not id then return false end
        if kind == "equip" then return IsEquippedItem ~= nil and IsEquippedItem(id) and true or false end
        if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then return C_UnitAuras.GetPlayerAuraBySpellID(id) ~= nil end
        return false
    end
    return a
end

-- The arrow's target for a RestedXP route, in the box's format { map, x, y, zone, text }.
function RxUI.Target(model)
    local L = DufforthTweaksHelperL or setmetatable({}, { __index = function(_, k) return k end })
    local KIND_TEXT = { spirit = L["Spirit Healer"], corpse = L["Your corpse"] }
    local ok, p = pcall(model.RxArrow, model)
    if not ok or not p or not p.x then return nil end
    local map = model.data.uiMaps[p.zone]
    if not map then return nil end
    local text
    if KIND_TEXT[p.kind] then
        text = KIND_TEXT[p.kind] .. (p.text and (": " .. p.text) or "")
    else
        local row = p.row and model.steps[p.row]
        text = row and DufforthTweaksHelperGuide.Describe and select(2, pcall(function()
            local d = DufforthTweaksHelperGuide.Describe(model, p.row)
            return d and d.text
        end)) or nil
        if type(text) ~= "string" then text = row and row[7] or "" end
        text = string.format(L["Step %d: %s"], p.step, text)
    end
    return { map = map, x = p.x, y = p.y, zone = p.zone, text = text, rx = p }
end

-- ---- The "DTH Target" macro: /target lines for the active steps' NPCs and monsters (RestedXP's .target and .mob),
-- rewritten when they change, never in combat. Put it on a bar once; it follows the guide. ----
RxUI.MACRO = "DTH Target"
local lastMacro
function RxUI.MacroText(names)
    local lines = {}
    local size = 0
    for _, name in ipairs(names or {}) do
        local line = "/targetexact " .. name
        if size + #line + 1 > 250 then break end
        lines[#lines + 1] = line
        size = size + #line + 1
    end
    return table.concat(lines, "\n")
end

function RxUI.UpdateMacro(model)
    if not (model and model.RxTargets and CreateMacro and GetMacroIndexByName) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local ok, names = pcall(model.RxTargets, model)
    if not ok then return end
    local body = RxUI.MacroText(RxUI.Order(names, model))
    if body == lastMacro then return end
    local index = GetMacroIndexByName(RxUI.MACRO)
    if index and index > 0 then
        EditMacro(index, RxUI.MACRO, nil, body)
    else
        local count = GetNumMacros and GetNumMacros() or 0
        if count >= (MAX_ACCOUNT_MACROS or 120) then return end
        pcall(CreateMacro, RxUI.MACRO, "INV_Misc_QuestionMark", body, nil)
    end
    lastMacro = body
end

-- ---- Memory: at login only your start's routes stay (GuideData holds all six; RestedXP loads one guide at a time) ----
-- Your start = the route you follow (or your race's when a questline guide is picked), with and without dungeons.
function RxUI.KeepSet()
    local data = DufforthTweaksHelperGuideData
    local name = UI.RouteName()
    local route = data and data.routes and data.routes[name]
    if route and not route.rxp then name = UI.RaceRoute() end
    local base = string.gsub(name or "", " %(dungeons%)$", "")
    return { [base] = true, [base .. " (dungeons)"] = true }
end

function RxUI.Prune()
    local data = DufforthTweaksHelperGuideData
    if not (data and data.routes and DufforthTweaksHelperGuide.PruneRoutes) then return 0 end
    local n = DufforthTweaksHelperGuide.PruneRoutes(data, RxUI.KeepSet())
    if n > 0 and collectgarbage then collectgarbage("collect") end
    RxUI.ApplyPending()
    return n
end

-- A part of another start picked in the Guides menu before the /reload: the pointer goes to its first step now.
function RxUI.ApplyPending()
    local db = UI.DB()
    local p = db.pendingPart
    local data = DufforthTweaksHelperGuideData
    if not (p and data and data.routes and data.routes[p.route]) then return end
    db.pendingPart = nil
    local saved = UI.Saved(p.route)
    local model = DufforthTweaksHelperGuide.NewModel(data, p.route, UI.adapter or UI.GameAdapter(), saved)
    local n = model.RxPartStart and model:RxPartStart(p.part)
    if n then model:RxGoTo(n) end
end

-- ---- RestedXP next to us (user, 2026-11-27: the guide must sit on RestedXP's part and step) ----
-- RestedXP keeps its place per character in RXPCData (RXPGuides.lua SaveGuideProgress): the guide's group and name,
-- the step number, the step id (guide id + line) and the side steps it closed. Nil when RestedXP isn't loaded.
function RxUI.RestedXPPlace(routeName)
    local c = rawget(_G, "RXPCData")
    if type(c) ~= "table" or type(c.currentGuideName) ~= "string" then return nil end
    local group = tostring(c.currentGuideGroup or "")
    local dungeons = string.find(group, "Dungeon", 1, true) ~= nil
    if string.find(group, "RestedXP Forever", 1, true) == nil then return nil end
    if routeName and (string.find(routeName, "(dungeons)", 1, true) ~= nil) ~= dungeons then return nil end
    local meta = type(c.guideMetaData) == "table" and c.guideMetaData[group .. "||" .. c.currentGuideName]
    return { name = c.currentGuideName, step = tonumber(c.currentStep), stepId = tonumber(c.currentStepId),
             guideId = type(meta) == "table" and tonumber(meta.guideId) or nil,
             skip = type(c.stepSkip) == "table" and c.stepSkip or nil }
end

function RxUI.Follow(model)
    if not (model and model.RxSync and model.route) then return false end
    local ok, moved = pcall(model.RxSync, model, RxUI.RestedXPPlace(model.routeName))
    return ok and moved or false
end

-- ---- Nameplates (RestedXP's Targeting.lua on Forever: names only, no raid marks there either) ----
-- A nameplate or the mouse over a monster of the active steps: remembered, so the target button goes for it first;
-- a rare one (.unitscan) plays a sound and flashes the game's icon, once a minute per name. Nothing in chat.
RxUI.seen, RxUI.alerted, RxUI.ALERT_GAP, RxUI.SEEN_FOR = {}, {}, 60, 120
function RxUI.Scan(unit)
    local model = UI.model
    if not (unit and model and model.RxScanNames and UnitName) then return nil end
    local name = UnitName(unit)
    if type(name) ~= "string" or Secret(name) then return nil end
    if UnitIsDead and UnitIsDead(unit) then return nil end
    local ok, names = pcall(model.RxScanNames, model)
    local kind = ok and names and names[name]
    if not kind then return nil end
    local now = GetTime and GetTime() or 0
    local fresh = not RxUI.seen[name] or now - RxUI.seen[name] > 10
    RxUI.seen[name] = now
    if kind == "us" and UI.DB().scanSound ~= false then
        local last = RxUI.alerted[name]
        if not last or now - last >= RxUI.ALERT_GAP then
            RxUI.alerted[name] = now
            if PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master") end
            if FlashClientIcon then pcall(FlashClientIcon) end
        end
    end
    if fresh and not (InCombatLockdown and InCombatLockdown()) then pcall(UI.Refresh) end
    return kind
end

-- Target names in the order to try: rare ones seen lately, then others seen lately, then the rest.
function RxUI.Order(names, model)
    local now = GetTime and GetTime() or 0
    local kinds = {}
    if model and model.RxScanNames then
        local ok, k = pcall(model.RxScanNames, model)
        if ok then kinds = k end
    end
    local function rank(name)
        local seen = RxUI.seen[name]
        if seen and now - seen <= RxUI.SEEN_FOR then return kinds[name] == "us" and 1 or 2 end
        return 3
    end
    local out = {}
    for k, name in ipairs(names or {}) do out[k] = { name, rank(name), k } end
    table.sort(out, function(a, b) if a[2] ~= b[2] then return a[2] < b[2] end return a[3] < b[3] end)
    for k, e in ipairs(out) do out[k] = e[1] end
    return out
end

-- ---- Events the engine counts as done (RestedXP's .hs, .fly, .vendor, .trainer, .deathskip, .home, .fp, .cast) ----
local HEARTH_SPELL = 8690
local function NpcId()
    local guid = UnitGUID and UnitGUID("npc")
    local id = guid and string.match(guid, "^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    return tonumber(id)
end

function RxUI.Mark(event, arg)
    local model = UI.model
    if not (model and model.RxMark) then return false end
    local ok, marked = pcall(model.RxMark, model, event, arg)
    return ok and marked
end

local events = CreateFrame("Frame")
RxUI.events = events
for _, e in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_CONTROL_LOST", "MERCHANT_SHOW", "TRAINER_SHOW", "PET_STABLE_SHOW",
    "BANKFRAME_OPENED", "PLAYER_UNGHOST", "PLAYER_ALIVE", "HEARTHSTONE_BOUND", "TAXIMAP_OPENED", "PLAYER_REGEN_ENABLED",
    "PLAYER_LOGIN", "NAME_PLATE_UNIT_ADDED", "UPDATE_MOUSEOVER_UNIT" }) do
    pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", function(_, event, a1, _, a3)
    local marked = false
    if event == "PLAYER_LOGIN" then pcall(RxUI.Prune); return
    elseif event == "NAME_PLATE_UNIT_ADDED" then pcall(RxUI.Scan, a1); return
    elseif event == "UPDATE_MOUSEOVER_UNIT" then pcall(RxUI.Scan, "mouseover"); return
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if a1 ~= "player" or Secret(a3) then return end
        marked = (a3 == HEARTH_SPELL and RxUI.Mark("hearth")) or RxUI.Mark("cast", a3)
    elseif event == "PLAYER_CONTROL_LOST" then
        if C_Timer then C_Timer.After(1, function() if UnitOnTaxi and UnitOnTaxi("player") then RxUI.Mark("taxi"); pcall(UI.Refresh) end end) end
    elseif event == "MERCHANT_SHOW" then marked = RxUI.Mark("vendor", NpcId())
    elseif event == "TRAINER_SHOW" then marked = RxUI.Mark("trainer", NpcId())
    elseif event == "PET_STABLE_SHOW" then marked = RxUI.Mark("stable")
    elseif event == "BANKFRAME_OPENED" then marked = RxUI.Mark("bank")
    elseif event == "PLAYER_UNGHOST" or event == "PLAYER_ALIVE" then
        if not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then marked = RxUI.Mark("resurrect") end
    elseif event == "HEARTHSTONE_BOUND" then marked = RxUI.Mark("home")
    elseif event == "TAXIMAP_OPENED" then marked = RxUI.Mark("flightpath")
    elseif event == "PLAYER_REGEN_ENABLED" then RxUI.UpdateMacro(UI.model); return
    end
    if marked and C_Timer then C_Timer.After(0.2, function() pcall(UI.Refresh) end) end
end)
