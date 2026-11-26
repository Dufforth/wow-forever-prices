-- Hunter pet guide (user, 2026-11-25: "which pet is best, best pet skills, where to get new pet skills from the open
-- world, which pets are worth taming"). Families and beasts come from PetData.lua (Classic database: every tameable
-- beast, its family, levels, attack speed and where it lives; family health, damage and armor). Which skills each
-- family can learn and at which levels the ranks come are Classic's (the database doesn't list which beast teaches
-- which rank), so the guide says to check a beast with Beast Lore before taming it. Forever may differ.

local L = DufforthTweaksHelperL or setmetatable({}, { __index = function(_, k) return k end })
DufforthTweaksHelperPets = DufforthTweaksHelperPets or {}
local P = DufforthTweaksHelperPets

-- Skills a family can learn from beasts in the open world, and the levels their ranks come at (Classic).
P.SKILLS = {
    Bite = { ranks = { 1, 8, 16, 24, 32, 40, 48, 56 }, what = L["main attack, every few seconds"] },
    Claw = { ranks = { 1, 8, 16, 24, 32, 40, 48, 56 }, what = L["main attack, uses focus fast"] },
    Dash = { ranks = { 30, 40, 50 }, what = L["runs faster for a moment"] },
    Dive = { ranks = { 30, 40, 50 }, what = L["flies faster for a moment"] },
    Prowl = { ranks = { 30, 40, 50 }, what = L["stealth; its first attack hits harder"] },
    Charge = { ranks = { 1, 12, 24, 36, 48, 60 }, what = L["charges in and stuns: a strong pull"] },
    ["Furious Howl"] = { ranks = { 10, 24, 40, 56 }, what = L["your group's next attack hits harder"] },
    ["Lightning Breath"] = { ranks = { 1, 12, 24, 36, 48, 60 }, what = L["nature damage from range"] },
    ["Scorpid Poison"] = { ranks = { 8, 24, 40, 56 }, what = L["poison that stacks over time"] },
    Screech = { ranks = { 8, 24, 48, 56 }, what = L["damage, and enemies near it hit weaker"] },
    ["Shell Shield"] = { ranks = { 20 }, what = L["takes half damage for a while"] },
    Thunderstomp = { ranks = { 30, 40, 50 }, what = L["hits every enemy around it: holds several"] },
}
P.SKILL_ORDER = { "Bite", "Claw", "Charge", "Lightning Breath", "Screech", "Scorpid Poison", "Furious Howl", "Thunderstomp",
    "Shell Shield", "Prowl", "Dash", "Dive" }

-- Per family: its own skills (besides Cower and the pet trainer's Growl, Natural Armor and resistances), what it's
-- good for, and a 1-3 rating for solo leveling.
P.FAMILIES = {
    [1] = { skills = { "Bite", "Furious Howl", "Dash" }, role = L["groups: Furious Howl helps everyone"], solo = 2 },
    [2] = { skills = { "Bite", "Claw", "Prowl", "Dash" }, role = L["damage: the best solo leveling pet"], solo = 3 },
    [3] = { skills = { "Bite" }, role = L["plain damage"], solo = 2 },
    [4] = { skills = { "Bite", "Claw" }, role = L["tank: the most health"], solo = 2 },
    [5] = { skills = { "Bite", "Charge", "Dash" }, role = L["Charge pulls and stuns; great from level 1"], solo = 3 },
    [6] = { skills = { "Bite" }, role = L["sturdy, plain"], solo = 1 },
    [7] = { skills = { "Bite", "Claw", "Dive", "Screech" }, role = L["two attacks and Screech"], solo = 2 },
    [8] = { skills = { "Claw" }, role = L["tank: the most armor, low damage"], solo = 1 },
    [9] = { skills = { "Bite", "Thunderstomp" }, role = L["holds several enemies (Thunderstomp)"], solo = 2 },
    [11] = { skills = { "Bite", "Claw" }, role = L["damage: two attacks"], solo = 3 },
    [12] = { skills = { "Bite" }, role = L["plain"], solo = 1 },
    [20] = { skills = { "Claw", "Scorpid Poison" }, role = L["poison damage on long fights"], solo = 2 },
    [21] = { skills = { "Bite", "Shell Shield" }, role = L["tank: armor and Shell Shield"], solo = 2 },
    [24] = { skills = { "Bite", "Dive", "Screech" }, role = L["Screech weakens enemies"], solo = 2 },
    [25] = { skills = { "Bite", "Dash" }, role = L["plain, fast"], solo = 1 },
    [26] = { skills = { "Claw", "Dive", "Screech" }, role = L["Screech weakens enemies"], solo = 2 },
    [27] = { skills = { "Bite", "Dive", "Lightning Breath" }, role = L["damage from range (Lightning Breath)"], solo = 3 },
}

local function Data() return DufforthTweaksHelperPetData or { families = {}, beasts = {} } end
local function DB()
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    DufforthTweaksHelperDB.pets = DufforthTweaksHelperDB.pets or {}
    return DufforthTweaksHelperDB.pets
end
local function Level() return (UnitLevel and UnitLevel("player")) or 1 end

-- Family ids in a fixed order: best for solo leveling first, then by name.
function P.FamilyIds()
    local ids = {}
    for id in pairs(Data().families) do if P.FAMILIES[id] then ids[#ids + 1] = id end end
    table.sort(ids, function(a, b)
        if P.FAMILIES[a].solo ~= P.FAMILIES[b].solo then return P.FAMILIES[a].solo > P.FAMILIES[b].solo end
        return Data().families[a][1] < Data().families[b][1]
    end)
    return ids
end

function P.FamilyName(id) local f = Data().families[id]; return f and f[1] or "?" end

-- "+10% damage, -2% health" from the family's modifiers.
function P.StatText(id)
    local f = Data().families[id]
    if not f then return "" end
    local parts = {}
    for i, label in ipairs({ L["health"], L["damage"], L["armor"] }) do
        local v = f[i + 1]
        if v and math.abs(v - 1) >= 0.005 then parts[#parts + 1] = string.format("%+d%% %s", math.floor((v - 1) * 100 + 0.5), label) end
    end
    return #parts > 0 and table.concat(parts, ", ") or L["average stats"]
end

-- Per skill this family learns: the best rank you can have now (now = its level, nil below rank 1's level) and the
-- level the next rank comes at (nextLevel, nil at the top rank).
function P.NextRanks(id, level)
    local out = {}
    for _, skill in ipairs((P.FAMILIES[id] or {}).skills or {}) do
        local best, nextOne
        for _, lv in ipairs(P.SKILLS[skill].ranks) do
            if lv <= level then best = lv elseif not nextOne then nextOne = lv end
        end
        out[#out + 1] = { skill = skill, now = best, nextLevel = nextOne }
    end
    return out
end

-- Beasts of this family you can tame now or soon (up to your level; the closest to it first).
function P.BeastsFor(id, level, count)
    local list = {}
    for _, b in ipairs(Data().beasts) do
        if b[2] == id and b[3] <= level and b[4] >= level - 12 then list[#list + 1] = b end
    end
    table.sort(list, function(a, b)
        if a[4] ~= b[4] then return a[4] > b[4] end
        return a[1] < b[1]
    end)
    while #list > (count or 6) do table.remove(list) end
    return list
end

-- Beasts that attack faster than the usual 2.0 s (a tamed pet keeps its speed), up to your level.
function P.FastBeasts(level, count)
    local list = {}
    for _, b in ipairs(Data().beasts) do
        if b[8] < 2000 and b[3] <= level and b[4] >= level - 15 then list[#list + 1] = b end
    end
    table.sort(list, function(a, b)
        if a[8] ~= b[8] then return a[8] < b[8] end
        return a[4] > b[4]
    end)
    while #list > (count or 5) do table.remove(list) end
    return list
end

local RANKS = { [1] = L["elite"], [2] = L["rare elite"], [4] = L["rare"] }
function P.BeastLine(b)
    local tag = RANKS[b[9]] and (" |cffff8040" .. RANKS[b[9]] .. "|r") or ""
    local lv = b[3] == b[4] and tostring(b[3]) or (b[3] .. "-" .. b[4])
    local speed = b[8] < 2000 and string.format(" |cff40ff40%.1fs|r", b[8] / 1000) or ""
    return string.format("%s (%s, %s)%s%s  |cffaaaaaa%s %.0f, %.0f|r", b[1], P.FamilyName(b[2]), lv, tag, speed, b[5], b[6], b[7])
end

function P.Summary(level)
    local lines = {
        L["|cffffd100Best pets:|r solo leveling: Cat, Raptor or Wind Serpent (damage); Boar early (Charge pulls). Tanking: Bear (health), Turtle or Crab (armor). Groups: Wolf (Furious Howl). Gorilla holds several enemies."],
        L["A tamed beast keeps its attack speed: a fast one (|cff40ff40green|r) hits more often. Pet skills: tame a beast of the family that knows the rank (check it with Beast Lore), keep it until you learn the rank, then teach your pet with Beast Training; Growl, Natural Armor and resistances come from the pet trainer."],
    }
    local fast = P.FastBeasts(level, 3)
    if #fast > 0 then
        local names = {}
        for _, b in ipairs(fast) do names[#names + 1] = P.BeastLine(b) end
        lines[#lines + 1] = L["|cffffd100Fast attackers you can tame:|r "] .. table.concat(names, "; ")
    end
    return table.concat(lines, "\n")
end

function P.FamilyText(id, level)
    local info = P.FAMILIES[id] or {}
    local lines = { string.format("|cffffd100%s|r  %s. %s.", P.FamilyName(id), P.StatText(id), info.role or "") }
    for _, r in ipairs(P.NextRanks(id, level)) do
        local skill = P.SKILLS[r.skill]
        local now = r.now and string.format(L["rank at %d"], r.now) or L["not yet"]
        local after = r.nextLevel and string.format(L["; next rank at level %d"], r.nextLevel) or L["; top rank"]
        lines[#lines + 1] = string.format("  %s: %s (%s%s)", r.skill, skill.what, now, after)
    end
    local list = P.BeastsFor(id, level, 6)
    lines[#lines + 1] = #list > 0 and L["|cffffd100Tame now (closest to your level):|r"] or L["No beast of this family up to your level in the data."]
    for _, b in ipairs(list) do lines[#lines + 1] = "  " .. P.BeastLine(b) end
    return table.concat(lines, "\n")
end

-- ---- The view on the Class tab ----

local panel
function P.Refresh()
    if not panel then return end
    local ids = P.FamilyIds()
    if #ids == 0 then panel.summary:SetText(L["|cffff5555No pet data. Restart the game fully (new file).|r"]); return end
    local db = DB()
    local index = 1
    for i, id in ipairs(ids) do if id == db.family then index = i end end
    db.family = ids[index]
    local level = Level()
    panel.summary:SetText(P.Summary(level))
    panel.name:SetText(string.format("%s (%d/%d)", P.FamilyName(db.family), index, #ids))
    panel.family:SetText(P.FamilyText(db.family, level))
    panel.note:SetText(L["|cffaaaaaaSkills and ranks are Classic's; Forever may differ. Beast data: Classic database.|r"])
end

function P.Step(delta)
    local ids = P.FamilyIds()
    if #ids == 0 then return end
    local db = DB()
    local index = 1
    for i, id in ipairs(ids) do if id == db.family then index = i end end
    index = (index - 1 + delta) % #ids + 1
    db.family = ids[index]
    P.Refresh()
end

function P.BuildPanel(parent, width)
    panel = parent
    local function Text(y, height, font)
        local t = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
        t:SetPoint("TOPLEFT", 10, y); t:SetWidth(width - 20); t:SetJustifyH("LEFT")
        if height and t.SetHeight then t:SetHeight(height) end
        if t.SetJustifyV then t:SetJustifyV("TOP") end
        return t
    end
    panel.title = Text(-4, nil, "GameFontNormal")
    panel.title:SetText(L["Pet guide"])
    panel.summary = Text(-24, 118)
    local function Arrow(text, x, delta)
        local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetSize(26, 20); b:SetPoint("TOPLEFT", x, -146); b:SetText(text)
        b:SetScript("OnClick", function() P.Step(delta) end)
        return b
    end
    Arrow("<", 10, -1)
    panel.name = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.name:SetPoint("TOPLEFT", 42, -149)
    Arrow(">", width - 40, 1)
    panel.family = Text(-172, 230)
    panel.note = Text(-404, 30)
    if parent.HookScript then parent:HookScript("OnShow", function() P.Refresh() end) end
    P.Refresh()
end
