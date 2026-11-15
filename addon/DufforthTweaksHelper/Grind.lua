-- Grind tab: the best places around the world to kill monsters for experience or gold, for your
-- level, class and spec (user, 2026-11-15). Data: GrindData.lua (catalog/build_grind.py, Classic
-- CMaNGOS spawns and loot). Experience, kills per hour and time to level are worked out here.
-- The model (Grind.KillXP, Grind.Rate, Grind.List, Grind.SPECS) is pure and tested in grind_sim.py;
-- the panel at the bottom only draws it.
local L = DufforthTweaksHelperL or setmetatable({}, { __index = function(_, k) return k end })
local Grind = {}
DufforthTweaksHelperGrind = Grind

local CASTER, HEALER, FLEES, ELITE, PACK = 1, 2, 4, 8, 16
Grind.FLAGS = { caster = CASTER, healer = HEALER, flees = FLEES, elite = ELITE, pack = PACK }
local function Has(flags, bit) return flags % (bit * 2) >= bit end
Grind.Has = Has

-- ---- Experience ------------------------------------------------------------------------
-- Classic kill experience, then Forever's rule: monsters below your level give 4-20% less
-- (conquestcapped's Forever review). Read as 4% less per level below, at most 20%: unconfirmed.
Grind.BELOW_STEP, Grind.BELOW_MAX = 0.04, 0.20

local function ZeroDiff(level)
    if level < 8 then return 5 elseif level < 10 then return 6 elseif level < 12 then return 7
    elseif level < 16 then return 8 elseif level < 20 then return 9 elseif level < 30 then return 11
    elseif level < 40 then return 12 elseif level < 45 then return 13 elseif level < 50 then return 14
    elseif level < 55 then return 15 elseif level < 60 then return 16 end
    return 17
end

function Grind.GrayLevel(level)
    if level <= 5 then return 0 end
    if level <= 39 then return level - 5 - math.floor(level / 10) end
    return level - 1 - math.floor(level / 5)
end

function Grind.KillXP(level, mob, elite)
    if not level or not mob or mob <= 0 then return 0 end
    local base = level * 5 + 45
    local xp
    if mob >= level then
        xp = base * (1 + 0.05 * math.min(mob - level, 4))
    else
        if mob <= Grind.GrayLevel(level) then return 0 end
        xp = base * (1 - (level - mob) / ZeroDiff(level))
        xp = xp * (1 - math.min(Grind.BELOW_MAX, Grind.BELOW_STEP * (level - mob)))
    end
    if elite then xp = xp * 2 end
    return math.max(0, xp)
end

-- Average over the spot's levels (each level about as common).
function Grind.SpotXP(level, low, high, elite)
    local sum, n = 0, 0
    for m = low, math.max(low, high) do sum, n = sum + Grind.KillXP(level, m, elite), n + 1 end
    return n > 0 and sum / n or 0
end

-- Kills still needed with rested experience (each kill gives double until the rested pool is used).
function Grind.XPToGo(need, rested)
    rested = rested or 0
    return math.max(need / 2, need - rested)
end

-- ---- Classes and specs ---------------------------------------------------------------------
-- speed: how fast the spec kills (1 = average), rest: share of time eating, drinking or bandaging,
-- casters / packs: "good", "ok" or "bad" for that spec, elites: "ok" when the spec can solo the
-- easier ones a few levels below, interrupt: has a way to stop a cast (healers and casters).
-- From Classic class knowledge; Forever may differ. Unsure rules are the user's to confirm.
local function S(key, name, speed, rest, casters, packs, elites, interrupt, why)
    return { key = key, name = name, speed = speed, rest = rest, casters = casters, packs = packs,
        elites = elites, interrupt = interrupt, why = why }
end
Grind.SPECS = {
    WARRIOR = { S("arms", L["Arms"], 1.0, 0.45, "bad", "bad", "bad", false, L["no self-healing and spells ignore your armor"]),
                S("fury", L["Fury"], 1.05, 0.5, "bad", "bad", "bad", false, L["no self-healing and spells ignore your armor"]),
                S("protection", L["Protection (tank)"], 0.8, 0.3, "ok", "ok", "bad", true, L["Shield Bash stops casts"]) },
    PALADIN = { S("holy", L["Holy"], 0.75, 0.15, "bad", "ok", "bad", false, L["no interrupt and no way to close the gap"]),
                S("protection", L["Protection (tank)"], 0.8, 0.1, "bad", "good", "ok", false, L["no interrupt and no way to close the gap"]),
                S("retribution", L["Retribution"], 0.95, 0.15, "bad", "ok", "bad", false, L["no interrupt and no way to close the gap"]) },
    HUNTER = { S("beast", L["Beast Mastery"], 1.15, 0.1, "good", "bad", "ok", false, L["the pet holds them while you shoot"]),
               S("marksmanship", L["Marksmanship"], 1.1, 0.15, "good", "bad", "ok", false, L["the pet holds them while you shoot"]),
               S("survival", L["Survival"], 1.05, 0.15, "good", "bad", "ok", false, L["the pet holds them while you shoot"]) },
    ROGUE = { S("assassination", L["Assassination"], 1.05, 0.35, "good", "bad", "bad", true, L["Kick stops casts"]),
              S("combat", L["Combat"], 1.1, 0.35, "good", "bad", "bad", true, L["Kick stops casts"]),
              S("subtlety", L["Subtlety"], 1.0, 0.35, "good", "bad", "bad", true, L["Kick stops casts"]) },
    PRIEST = { S("discipline", L["Discipline"], 0.8, 0.3, "ok", "bad", "bad", false, L["slow kills, but you outheal them"]),
               S("holy", L["Holy"], 0.7, 0.3, "ok", "bad", "bad", false, L["slow kills, but you outheal them"]),
               S("shadow", L["Shadow"], 1.0, 0.25, "good", "bad", "bad", true, L["Silence and Psychic Scream stop casts"]) },
    SHAMAN = { S("elemental", L["Elemental"], 1.0, 0.35, "good", "bad", "bad", true, L["Earth Shock stops casts"]),
               S("enhancement", L["Enhancement"], 1.05, 0.2, "good", "ok", "bad", true, L["Earth Shock stops casts"]),
               S("restoration", L["Restoration"], 0.75, 0.25, "good", "bad", "bad", true, L["Earth Shock stops casts"]) },
    MAGE = { S("arcane", L["Arcane"], 0.95, 0.4, "bad", "ok", "bad", true, L["casters don't chase you, so kiting doesn't work"]),
             S("fire", L["Fire"], 1.05, 0.4, "bad", "bad", "bad", true, L["casters don't chase you, so kiting doesn't work"]),
             S("frost", L["Frost"], 1.0, 0.35, "bad", "good", "bad", true, L["casters don't chase you, so kiting doesn't work"]) },
    WARLOCK = { S("affliction", L["Affliction"], 1.05, 0.1, "ok", "ok", "ok", false, L["Fear and your pet handle them"]),
                S("demonology", L["Demonology"], 1.0, 0.1, "ok", "ok", "ok", false, L["Fear and your pet handle them"]),
                S("destruction", L["Destruction"], 1.0, 0.2, "ok", "bad", "bad", false, L["Fear and your pet handle them"]) },
    DRUID = { S("balance", L["Balance"], 0.9, 0.35, "ok", "bad", "bad", false, L["you trade spells with them"]),
              S("feral", L["Feral (cat, damage)"], 1.05, 0.25, "ok", "bad", "bad", false, L["they hit hard through cat armor"]),
              S("tank", L["Feral (bear, tank)"], 0.85, 0.15, "ok", "good", "ok", true, L["Bash stops casts"]),
              S("restoration", L["Restoration"], 0.7, 0.3, "ok", "bad", "bad", false, L["slow kills, but you outheal them"]) },
}
Grind.GENERIC = S("any", L["Any"], 1.0, 0.3, "ok", "bad", "bad", false, "")

function Grind.SpecInfo(class, key)
    for _, s in ipairs(Grind.SPECS[class] or {}) do if s.key == key then return s end end
    return nil
end

-- Talent tree number -> spec, for classes where the tree says it. Druid Feral is ambiguous
-- (cat or bear), so it needs your answer.
local TREES = {
    WARRIOR = { "arms", "fury", "protection" }, PALADIN = { "holy", "protection", "retribution" },
    HUNTER = { "beast", "marksmanship", "survival" }, ROGUE = { "assassination", "combat", "subtlety" },
    PRIEST = { "discipline", "holy", "shadow" }, SHAMAN = { "elemental", "enhancement", "restoration" },
    MAGE = { "arcane", "fire", "frost" }, WARLOCK = { "affliction", "demonology", "destruction" },
    DRUID = { "balance", nil, "restoration" },
}
Grind.MIN_TALENT_POINTS = 5

-- points = {tree 1 points, tree 2, tree 3}; returns a spec key or nil (ask the player).
function Grind.SpecFromTalents(class, points)
    if not points then return nil end
    local best, top, total = nil, -1, 0
    for i = 1, 3 do
        local p = points[i] or 0
        total = total + p
        if p > top then best, top = i, p end
    end
    if total < Grind.MIN_TALENT_POINTS then return nil end
    for i = 1, 3 do if i ~= best and (points[i] or 0) == top then return nil end end -- tie
    local trees = TREES[class]
    return trees and trees[best] or nil
end

-- ---- Rates -----------------------------------------------------------------------------------
Grind.KILL_SECONDS = 16   -- an average spec on a monster of its own level
Grind.RUN = 7             -- yards per second (no mount)
Grind.LOOT_SECONDS = 3
Grind.MIN_GAP = 8         -- yards: even packed monsters need a few steps
Grind.WALK_FACTOR = 1.5   -- the next living monster is further than the nearest spawn once the camp thins out
Grind.CUT = 0.95          -- auction house cut
Grind.WINDOW_BELOW, Grind.WINDOW_ABOVE = 2, 2   -- levels around you that the list shows (user: only your level, never gray)
Grind.BEST_SHARE = 0.85   -- "Best" within this share of the top experience per hour
Grind.BEST_GAP, Grind.BEST_SPAWNS = 30, 12

-- What one drop is worth to you: the better of the AH after the cut and the vendor.
function Grind.DropValue(id, items, prices)
    local ah = prices and prices[id] or 0
    local sell = items and items[id] and items[id][3] or 0
    if ah > 0 and ah * Grind.CUT > sell then return ah * Grind.CUT, "auction" end
    return sell, sell > 0 and "vendor" or nil
end

-- The sides' own leveling zones: the other side's are a long trip past its guards, so they
-- sort after yours (still shown). Contested zones (Duskwood, Wetlands, Ashenvale...) are no one's.
Grind.ZONE_SIDE = {
    ["Dun Morogh"] = "A", ["Elwynn Forest"] = "A", ["Teldrassil"] = "A", ["Darkshore"] = "A", ["Loch Modan"] = "A",
    ["Westfall"] = "A", ["Redridge Mountains"] = "A",
    ["Durotar"] = "H", ["Mulgore"] = "H", ["Tirisfal Glades"] = "H", ["Silverpine Forest"] = "H", ["The Barrens"] = "H",
}

-- Why a spot doesn't suit you: a list of {key, text, severe}.
function Grind.Warnings(spot, spec, level, side)
    local flags, out = Grind.SpotFlags(spot), {}
    local zoneSide = Grind.ZONE_SIDE[DufforthTweaksHelperGrindZones and DufforthTweaksHelperGrindZones[spot[1]] or ""]
    if side and zoneSide and zoneSide ~= side then
        out[#out + 1] = { key = "enemy", severe = false, text = L["The other faction's zone"] }
    end
    if Has(flags, ELITE) and not (spec.elites == "ok" and spot[5] <= level - 2) then
        out[#out + 1] = { key = "elite", severe = true, text = L["Elite: needs a group"] }
    end
    if Has(flags, CASTER) and spec.casters == "bad" then
        out[#out + 1] = { key = "caster", severe = true, text = L["Casters: hard for you"] }
    end
    if Has(flags, PACK) and spec.packs == "bad" then
        out[#out + 1] = { key = "pack", severe = true, text = L["Packs: you pull several"] }
    end
    if spot[4] > level + Grind.WINDOW_ABOVE then
        out[#out + 1] = { key = "high", severe = true, text = L["Too high for you"] }
    end
    if Has(flags, HEALER) and not spec.interrupt then
        out[#out + 1] = { key = "healer", severe = false, text = L["Some heal themselves"] }
    end
    if Has(flags, FLEES) then
        out[#out + 1] = { key = "flees", severe = false, text = L["Some run away"] }
    end
    return out
end

-- One spot for you. p = {level, xp, xpMax, rested, spec}; items, prices from the data.
function Grind.Rate(spot, p, items, prices)
    local spec = p.spec or Grind.GENERIC
    local level, flags = p.level, Grind.SpotFlags(spot)
    local elite = Has(flags, ELITE)
    local xp = Grind.SpotXP(level, spot[4], spot[5], elite) * (p.bonus or 1)
    local mid = (spot[4] + spot[5]) / 2
    local kill = Grind.KILL_SECONDS * math.max(0.5, 1 + 0.1 * (mid - level)) / spec.speed
    if elite then kill = kill * 3 end
    local rest = spec.rest
    if Has(flags, CASTER) and spec.casters == "bad" then kill, rest = kill * 1.15, rest * 1.4 end
    if Has(flags, CASTER) and spec.casters == "good" then kill = kill * 0.95 end
    if Has(flags, PACK) and spec.packs == "bad" then rest = rest * 1.3 end
    if Has(flags, PACK) and spec.packs == "good" then kill = kill * 0.85 end
    if Has(flags, HEALER) and not spec.interrupt then kill = kill * 1.15 end
    if Has(flags, FLEES) then kill = kill * 1.05 end
    local walk = math.max(Grind.MIN_GAP, spot[7] or 0) * Grind.WALK_FACTOR / Grind.RUN + Grind.LOOT_SECONDS
    local perKill = kill * (1 + rest) + walk
    local kph = 3600 / perKill
    local cap = (spot[8] or 0) > 0 and spot[6] * 3600 / spot[8] or kph
    local limited = cap < kph
    kph = math.min(kph, cap)
    local copper = spot[10] or 0
    for _, d in ipairs(spot[12] or {}) do copper = copper + d[2] * Grind.DropValue(d[1], items, prices) end
    local r = { spot = spot, xp = xp, kph = kph, perKill = perKill, kill = kill, limited = limited,
        xph = kph * xp, copper = copper, gph = kph * copper }
    if p.xpMax and p.xpMax > 0 and r.xph > 0 then
        r.toLevel = Grind.XPToGo(p.xpMax - (p.xp or 0), p.rested) / r.xph * 3600
        r.kills = math.ceil(Grind.XPToGo(p.xpMax - (p.xp or 0), p.rested) / xp)
    end
    r.warnings = Grind.Warnings(spot, spec, level, p.side)
    r.bad, r.enemy = false, false
    for _, w in ipairs(r.warnings) do
        if w.severe then r.bad = true end
        if w.key == "enemy" then r.enemy = true end
    end
    r.tier = r.bad and 2 or r.enemy and 1 or 0
    return r
end

-- How much each mode weighs experience against gold (shares of the best spot's numbers).
Grind.MODES = { balance = { xp = 0.5, gold = 0.5 }, xp = { xp = 1, gold = 0 }, gold = { xp = 0, gold = 1 } }
Grind.DEFAULT_MODE = "balance"

-- A spot fits you when its monsters are within WINDOW_BELOW / WINDOW_ABOVE levels of you and none is
-- gray (every one gives experience).
function Grind.Fits(low, high, level)
    return high >= level - Grind.WINDOW_BELOW and low <= level + Grind.WINDOW_ABOVE and low > Grind.GrayLevel(level)
end

-- Spots for you, best first. mode "balance" (default: the best mix of experience and gold),
-- "xp" or "gold". Each spot's score is its experience and gold an hour as shares of the best spot's,
-- weighed by the mode. Spots that don't suit you go last.
function Grind.List(spots, p, items, prices, mode)
    local weights = Grind.MODES[mode or ""] or Grind.MODES[Grind.DEFAULT_MODE]
    local out, topX, topG = {}, 0, 0
    for _, spot in ipairs(spots or {}) do
        if Grind.Fits(spot[4], spot[5], p.level) then
            local r = Grind.Rate(spot, p, items, prices)
            if r.xp > 0 then
                out[#out + 1] = r
                if r.tier == 0 then topX, topG = math.max(topX, r.xph), math.max(topG, r.gph) end
            end
        end
    end
    local topScore = 0
    for _, r in ipairs(out) do
        r.score = weights.xp * (topX > 0 and r.xph / topX or 0) + weights.gold * (topG > 0 and r.gph / topG or 0)
        if r.tier == 0 and r.score > topScore then topScore = r.score end
    end
    for _, r in ipairs(out) do
        r.best = r.tier == 0 and r.spot[5] <= p.level + 1 and r.score >= topScore * Grind.BEST_SHARE
            and (r.spot[7] or 99) <= Grind.BEST_GAP and r.spot[6] >= Grind.BEST_SPAWNS
    end
    table.sort(out, function(a, b)
        if a.tier ~= b.tier then return a.tier < b.tier end
        if a.score ~= b.score then return a.score > b.score end
        return a.spot[6] > b.spot[6]
    end)
    return out
end

-- Monsters: spot[11] holds numbers into DufforthTweaksHelperGrindMobs
-- ({name, min, max, model id, creature type, family, flags, vendor copper a kill, {{item, per kill}}}).
-- Test data may hold names.
function Grind.Mob(i)
    if type(i) ~= "number" then return nil end
    return DufforthTweaksHelperGrindMobs and DufforthTweaksHelperGrindMobs[i] or nil
end

function Grind.MobName(i)
    if type(i) == "string" then return i end
    local m = Grind.Mob(i)
    return m and m[1] or "?"
end

function Grind.MobNames(spot, n)
    local out = {}
    for k, i in ipairs(spot[11] or {}) do
        if k > (n or 3) then break end
        out[#out + 1] = Grind.MobName(i)
    end
    return table.concat(out, ", ")
end

-- The list grouped by zone (zones in the order of their best spot), with camps of the same main
-- monster in a zone merged into one row (r.camps = every camp's spot, best first).
function Grind.Group(list)
    local zones, byZone = {}, {}
    for _, r in ipairs(list or {}) do
        local z = r.spot[1]
        local g = byZone[z]
        if not g then
            g = { zone = z, rows = {}, keyed = {} }
            byZone[z] = g
            zones[#zones + 1] = g
        end
        local key = tostring(r.spot[11] and r.spot[11][1])
        local row = g.keyed[key]
        if row then
            row.camps[#row.camps + 1] = r.spot
        else
            r.camps = { r.spot }
            g.keyed[key] = r
            g.rows[#g.rows + 1] = r
        end
    end
    return zones
end

-- The best spot that suits you right now for each mode: { xp = r, gold = r, balance = r }.
function Grind.BestNow(spots, p, items, prices)
    local out = {}
    for mode in pairs(Grind.MODES) do
        local list = Grind.List(spots, p, items, prices, mode)
        if list[1] and list[1].tier == 0 then out[mode] = list[1] end
    end
    return out
end

-- Each zone's monsters at your level with their drops, zones in the order of the spots list.
-- { {zone, mobs = { {index, mob, xp, value, camps = {spot...}, flags} }} }, mobs by value a kill.
function Grind.Monsters(spots, p, items, prices)
    local zones, byZone = {}, {}
    for _, r in ipairs(Grind.List(spots, p, items, prices, "balance")) do
        local z = r.spot[1]
        local g = byZone[z]
        if not g then g = { zone = z, mobs = {}, keyed = {} }; byZone[z] = g; zones[#zones + 1] = g end
        for _, i in ipairs(r.spot[11] or {}) do
            local m = Grind.Mob(i)
            if m and Grind.Fits(m[2], m[3], p.level) then
                local e = g.keyed[i]
                if not e then
                    local value = m[8] or 0
                    for _, d in ipairs(m[9] or {}) do value = value + d[2] * Grind.DropValue(d[1], items, prices) end
                    e = { index = i, mob = m, flags = m[7] or 0, camps = {}, value = value,
                        xp = Grind.SpotXP(p.level, m[2], m[3], Has(m[7] or 0, ELITE)) * (p.bonus or 1) }
                    g.keyed[i] = e
                    g.mobs[#g.mobs + 1] = e
                end
                e.camps[#e.camps + 1] = r.spot
            end
        end
    end
    for _, g in ipairs(zones) do table.sort(g.mobs, function(a, b) return a.value > b.value end) end
    local out = {}
    for _, g in ipairs(zones) do if #g.mobs > 0 then out[#out + 1] = g end end
    return out
end

-- The game's difficulty colors for a monster's level.
function Grind.LevelColor(level, mob)
    local d = mob - level
    if d >= 5 then return "ff2020" elseif d >= 3 then return "ff8040" elseif d >= -2 then return "ffff00" end
    if mob > Grind.GrayLevel(level) then return "40c040" end
    return "808080"
end

function Grind.Levels(level, low, high)
    local text = low == high and tostring(low) or (low .. "-" .. high)
    return "|cff" .. Grind.LevelColor(level, high) .. text .. "|r"
end

function Grind.Duration(seconds)
    if not seconds or seconds ~= seconds or seconds == math.huge then return "?" end
    local m = math.floor(seconds / 60 + 0.5)
    if m < 60 then return string.format(L["%dm"], math.max(1, m)) end
    return string.format(L["%dh %dm"], math.floor(m / 60), m % 60)
end

-- ---- Experience boosts (user, 2026-11-15: "a reminder for exp buffs available before a grinding session") ----
-- Forever: Elixir of Endless Experience (item 289334, buff 1328127) +200% experience for 1 hour and
-- reusable (client data: charges -1); Nutritious Food's Well Fed +5% kill experience for 15 min.
-- How they stack is unconfirmed: added here.
Grind.ELIXIR_ITEM, Grind.ELIXIR_SPELL, Grind.ELIXIR_BONUS = 289334, 1328127, 2.0
Grind.FOOD_BONUS = 0.05

-- state = { elixirActive, elixirInBags, wellFed, food = name in bags, buy = {name, price}, rested, level, maxLevel }
function Grind.XPBonus(state)
    if not state then return 1 end
    return 1 + (state.elixirActive and Grind.ELIXIR_BONUS or 0) + (state.wellFed and Grind.FOOD_BONUS or 0)
end

-- What to do before you start: { {key, text, ready (true = already on)} }.
function Grind.Boosts(state, money)
    local out = {}
    if not state or (state.level or 0) >= (state.maxLevel or 60) then return out end
    if state.elixirActive then
        out[#out + 1] = { key = "elixir", ready = true, text = L["Elixir of Endless Experience is on: +200% experience."] }
    elseif state.elixirInBags then
        out[#out + 1] = { key = "elixir", text = L["Use Elixir of Endless Experience: +200% experience for 1 hour."],
            short = L["Use your Elixir of Endless Experience (+200% XP)"] }
    end
    if state.wellFed then
        out[#out + 1] = { key = "food", ready = true, text = L["Well Fed: +5% kill experience."] }
    elseif state.food then
        out[#out + 1] = { key = "food", text = string.format(L["Eat %s: +5%% kill experience for 15 min."], state.food),
            short = string.format(L["Eat %s (+5%% XP)"], state.food) }
    elseif state.buy then
        out[#out + 1] = { key = "food", text = string.format(L["Buy %s (%s at the AH) for +5%% kill experience."], state.buy[1],
            money and money(state.buy[2]) or tostring(state.buy[2])), short = string.format(L["Buy %s (+5%% XP)"], state.buy[1]) }
    end
    if (state.rested or 0) > 0 then
        out[#out + 1] = { key = "rested", ready = true, text = string.format(L["Rested: your next %d experience from kills is doubled."], math.floor(state.rested)) }
    else
        out[#out + 1] = { key = "rested", text = L["No rested experience: log out in an inn or a city to earn some."] }
    end
    return out
end

-- Boosts still to use (not ready, not just information).
function Grind.Missing(boosts)
    local n = 0
    for _, b in ipairs(boosts or {}) do if not b.ready and b.key ~= "rested" then n = n + 1 end end
    return n
end

local function Short(n)
    n = math.floor(n + 0.5)
    if n >= 10000 then return string.format("%dk", math.floor(n / 1000 + 0.5)) end
    if n >= 1000 then return string.format("%.1fk", n / 1000) end
    return tostring(n)
end
Grind.Short = Short

-- ---- Learning from your kills (user, 2026-11-15: "add a log so you can review kill time, exp gained, mob type") ----
-- Every kill that gives experience is saved in DufforthTweaksHelperDB.grind.kills (newest last, up to
-- Grind.KILL_MAX). tools/tune_grind.py reads them after a /reload, fits the model's numbers (Forever's
-- lower-level experience, each spec's kill time and rest, which monsters really cast) and writes
-- DufforthTweaksHelperGrindTune into GrindData.lua, which Grind.ApplyTune uses.
Grind.KILL_MAX = 3000
Grind.CYCLE_MAX = 600      -- seconds: a longer gap since the last kill is a break, not resting
Grind.SPOT_NEAR = 6        -- map %: a kill this close to a known spot counts for that spot

local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
Grind.Plain = Plain

-- A Lua pattern from a game format string ("%s dies, you gain %d experience.").
function Grind.XPPattern(fmt)
    local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%s", "(.-)"):gsub("%%d", "(%%d+)")
    return "^" .. p
end

-- name, total experience, rested bonus from the game's kill line, or nil. The total includes the
-- bonus; the bonus is the first "+N" after the experience.
function Grind.ParseXP(msg, fmt)
    if type(msg) ~= "string" then return nil end
    fmt = fmt or COMBATLOG_XPGAIN_FIRSTPERSON or "%s dies, you gain %d experience."
    local cut = fmt:find("%d", 1, true)
    if not cut then return nil end
    local head = Grind.XPPattern(fmt:sub(1, cut + 1))
    local name, xp = msg:match(head)
    if not name or not xp then return nil end
    local after = select(3, msg:match(head .. "(.*)$"))
    local bonus = after and after:match("%+(%d+)") or nil
    return name, tonumber(xp), tonumber(bonus) or 0
end

function Grind.NearestSpot(zone, x, y, spots, zones)
    if not (zone and x and y and spots and zones) then return nil end
    local best, bestD
    for i, s in ipairs(spots) do
        if zones[s[1]] == zone then
            local d = math.sqrt((s[2] - x) ^ 2 + (s[3] - y) ^ 2)
            if d <= Grind.SPOT_NEAR and (not bestD or d < bestD) then best, bestD = i, d end
        end
    end
    return best
end

-- The tracker. game = { now(), target() -> {guid, name, level, rank, kind} or nil, casting() -> bool,
-- player() -> {level, zone, x, y, group, class, spec} }; log = the saved list.
Grind.AFTER_COMBAT = 5     -- seconds the last fight's targets are kept (the kill line can come after the fight ends)
Grind.XP_WAIT = 0.6        -- seconds to wait for the kill line after the experience bar moves

-- debug = counters saved for tools/tune_grind.py, so "no kills saved" can be explained.
function Grind.NewTracker(game, log, debug)
    local t = { game = game, log = log, seen = {}, fightStart = nil, lastKill = nil, combatEnd = nil,
        debug = debug or {}, lastChatKill = -1000, pending = nil }
    local function Count(key) t.debug[key] = (t.debug[key] or 0) + 1 end

    function t:OnTarget()
        local info = self.game.target()
        if not (info and info.guid) then return end
        local old = self.seen[info.guid]
        if old then
            old.level = old.level or info.level
            if self.fightStart and not old.engaged then old.engaged = self.game.now() end
            return
        end
        info.engaged = self.fightStart and self.game.now() or nil
        self.seen[info.guid] = info
    end

    function t:OnCombat(started)
        local now = self.game.now()
        if started then
            Count("combats")
            -- Forget older fights' targets, so the table doesn't grow.
            for guid, info in pairs(self.seen) do
                if info.dead or (info.left and now - info.left > Grind.AFTER_COMBAT) then self.seen[guid] = nil end
            end
            self.fightStart = now
            self:OnTarget()
            local info = self:Current()
            if info and not info.engaged then info.engaged = self.fightStart end
        else
            self.fightStart, self.combatEnd = nil, now
            for _, info in pairs(self.seen) do info.left = info.left or now end
        end
    end

    function t:Current()
        local info = self.game.target()
        return info and info.guid and self.seen[info.guid] or nil
    end

    -- Called every half second in a fight: was the target casting?
    function t:OnTick()
        local info = self:Current()
        if info and self.game.casting() then info.cast = true end
    end

    function t:OnXP(msg)
        Count("chat")
        if type(msg) == "string" then self.debug.lastChat = msg:sub(1, 120) end
        local name, xp, bonus = Grind.ParseXP(msg, self.game.format)
        if not name then return nil end
        Count("parsed")
        self.lastChatKill = self.game.now()
        self.pending = nil
        return self:AddKill(name, xp, bonus, nil)
    end

    -- Backup when the kill line never comes: the experience bar moved in or just after a fight.
    function t:OnXPUpdate(current, max, level)
        Count("xpUpdates")
        local last = self.lastXP
        self.lastXP = { current, max, level }
        if not (last and current) then return end
        local gained = current - last[1]
        if level and last[3] and level > last[3] then gained = (last[2] - last[1]) + current end
        if gained <= 0 then return end
        local now = self.game.now()
        local fighting = self.fightStart or (self.combatEnd and now - self.combatEnd <= Grind.AFTER_COMBAT)
        if fighting and now - self.lastChatKill > 1 then self.pending = { at = now, xp = gained } end
    end

    function t:Flush()
        local pending = self.pending
        if not pending or self.game.now() - pending.at < Grind.XP_WAIT then return nil end
        self.pending = nil
        if self.lastChatKill >= pending.at - 1 then return nil end
        local info
        for _, i in pairs(self.seen) do
            if not i.dead and (not info or (i.engaged or 0) > (info.engaged or 0)) then info = i end
        end
        Count("fallback")
        return self:AddKill(info and info.name or "?", pending.xp, nil, "bar")
    end

    function t:AddKill(name, xp, bonus, source)
        local now = self.game.now()
        local info
        for _, i in pairs(self.seen) do
            if i.name == name and not i.dead and (not info or (i.engaged or 0) > (info.engaged or 0)) then info = i end
        end
        local p = self.game.player()
        local e = { at = self.game.time and self.game.time() or now, mob = name, pl = p.level, xp = xp, rested = bonus,
            zone = p.zone, x = p.x, y = p.y, class = p.class, spec = p.spec, group = p.group or nil, source = source }
        if info then
            info.dead = true
            e.ml, e.rank, e.kind, e.cast = info.level, info.rank, info.kind, info.cast or false
            local from = info.engaged or self.fightStart
            if from then e.fight = math.floor((now - from) * 10 + 0.5) / 10 end
        end
        if self.lastKill and now - self.lastKill <= Grind.CYCLE_MAX then
            e.cycle = math.floor((now - self.lastKill) * 10 + 0.5) / 10
        end
        self.lastKill = now
        e.spot = Grind.NearestSpot(e.zone, e.x, e.y, DufforthTweaksHelperGrindSpots, DufforthTweaksHelperGrindZones)
        self.log[#self.log + 1] = e
        while #self.log > Grind.KILL_MAX do table.remove(self.log, 1) end
        return e
    end
    return t
end

-- ---- What the log taught (DufforthTweaksHelperGrindTune, written by tools/tune_grind.py) ----
-- tune = { below = {step, max}, killSeconds, specs = {["CLASS:spec"] = {speed, rest}}, casters = {name = true},
--          noCast = {name = true}, kills = n, at = "date" }
function Grind.ApplyTune(tune)
    Grind.tune = tune
    if type(tune) ~= "table" then return end
    if tune.below then Grind.BELOW_STEP, Grind.BELOW_MAX = tune.below[1] or Grind.BELOW_STEP, tune.below[2] or Grind.BELOW_MAX end
    if tune.killSeconds then Grind.KILL_SECONDS = tune.killSeconds end
    for key, v in pairs(tune.specs or {}) do
        local class, spec = key:match("^(%u+):(%w+)$")
        local s = class and Grind.SpecInfo(class, spec)
        if s then s.speed, s.rest = v[1] or s.speed, v[2] or s.rest end
    end
end

-- The spot's flags, corrected by what your kills showed: a monster seen casting makes it a caster
-- spot; monsters killed often and never seen casting clear it.
function Grind.SpotFlags(spot)
    local flags = spot[9] or 0
    local tune = Grind.tune
    if not tune then return flags end
    local seenCast, allQuiet, any = false, true, false
    for _, i in ipairs(spot[11] or {}) do
        local name = Grind.MobName(i)
        any = true
        if tune.casters and tune.casters[name] then seenCast = true end
        if not (tune.noCast and tune.noCast[name]) then allQuiet = false end
    end
    if seenCast and not Has(flags, CASTER) then flags = flags + CASTER end
    if any and allQuiet and not seenCast and Has(flags, CASTER) then flags = flags - CASTER end
    return flags
end

-- ---- The player (game glue) --------------------------------------------------------------------
local function DB()
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    local db = DufforthTweaksHelperDB
    db.grind = db.grind or {}
    db.grind.spec = db.grind.spec or {}
    return db.grind
end

local function CharKey()
    local name = UnitName and UnitName("player") or "?"
    local realm = GetRealmName and GetRealmName() or ""
    return name .. "-" .. realm
end

local function ClassToken()
    if not UnitClass then return "WARRIOR" end
    local _, token = UnitClass("player")
    return token or "WARRIOR"
end

-- Talent points per tree when the game tells them (it didn't on Forever's client in Nov 2026).
function Grind.ReadTalents()
    if not (GetNumTalentTabs and GetTalentTabInfo) then
        local index = GetSpecialization and GetSpecialization()
        if type(index) == "number" and index >= 1 and index <= 3 then
            local points = { 0, 0, 0 }
            points[index] = Grind.MIN_TALENT_POINTS
            return points
        end
        return nil
    end
    local points = {}
    for tab = 1, math.min(3, GetNumTalentTabs() or 0) do
        local values = { GetTalentTabInfo(tab) }
        local p
        for i = 2, #values do
            local v = values[i]
            if type(v) == "number" and (not issecretvalue or not issecretvalue(v)) and v >= 0 and v <= 61 then p = v; break end
        end
        points[tab] = p or 0
    end
    return #points == 3 and points or nil
end

-- Your spec: your own choice (saved per character) first, else from talents, else nil.
function Grind.CurrentSpec()
    local class = ClassToken()
    local chosen = DB().spec[CharKey()]
    if chosen and Grind.SpecInfo(class, chosen) then return Grind.SpecInfo(class, chosen), "chosen" end
    local ok, points = pcall(Grind.ReadTalents)
    local key = ok and Grind.SpecFromTalents(class, points) or nil
    if key then return Grind.SpecInfo(class, key), "talents" end
    return nil, nil
end

function Grind.ChooseSpec(key)
    DB().spec[CharKey()] = key
    Grind.choosing = false
    Grind.Refresh()
end

local function Prices()
    local market = DufforthTweaksHelper and DufforthTweaksHelper.MarketName and DufforthTweaksHelper.MarketName() or ""
    return DufforthTweaksHelperPrices and DufforthTweaksHelperPrices[market] or {}
end

function Grind.Side()
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    return faction == "Alliance" and "A" or faction == "Horde" and "H" or nil
end

-- Your boosts, read out of combat (buffs are hidden in a fight on Forever); kept for the fight.
function Grind.ReadBoosts()
    local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
    if inCombat and Grind.boosts then return Grind.boosts end
    local level = UnitLevel and UnitLevel("player") or 1
    local state = { level = level, maxLevel = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60,
        rested = (GetXPExhaustion and GetXPExhaustion()) or 0 }
    for i = 1, 40 do
        local ok, a = pcall(function() return C_UnitAuras and C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL") end)
        if not ok or not a then break end
        local id, name = Plain(a.spellId), Plain(a.name)
        if id == Grind.ELIXIR_SPELL then state.elixirActive = true end
        if name == "Well Fed" or (name and name:find("Well Fed", 1, true)) then state.wellFed = true end
    end
    local function have(id)
        return (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id)) or (GetItemCount and GetItemCount(id)) or 0
    end
    state.elixirInBags = have(Grind.ELIXIR_ITEM) > 0
    local Cons, data = DufforthTweaksHelperConsumables, DufforthTweaksHelperConsumableData
    if Cons and data and not state.wellFed then
        local class = ClassToken()
        local row = Cons.BestFoodInBags and Cons.BestFoodInBags(data, class, level, have)
        if row then state.food = (GetItemInfo and GetItemInfo(row[1])) or row[2]
        elseif Cons.FoodToBuy then
            local okBuy, e = pcall(Cons.FoodToBuy, data, class, level, Prices())
            if okBuy and e and e.row and e.price then state.buy = { (GetItemInfo and GetItemInfo(e.row[1])) or e.row[2], e.price } end
        end
    end
    Grind.boosts = state
    return state
end

function Grind.Player()
    local spec = Grind.CurrentSpec()
    local okB, boosts = pcall(Grind.ReadBoosts)
    return { level = UnitLevel and UnitLevel("player") or 1, xp = UnitXP and UnitXP("player") or 0,
        xpMax = UnitXPMax and UnitXPMax("player") or 0, rested = GetXPExhaustion and GetXPExhaustion() or 0,
        spec = spec or Grind.GENERIC, class = ClassToken(), side = Grind.Side(),
        bonus = Grind.XPBonus(okB and boosts or nil), boosts = okB and boosts or nil }
end

local function Money(c)
    if DufforthTweaksHelperDE and DufforthTweaksHelperDE.Money then return DufforthTweaksHelperDE.Money(math.floor(c + 0.5)) end
    return tostring(math.floor(c + 0.5)) .. "c"
end

local function ZoneOf(spot) return DufforthTweaksHelperGrindZones and DufforthTweaksHelperGrindZones[spot[1]] or "?" end
Grind.ZoneOf = ZoneOf

local function ShownZone(zone)
    local Loc = DufforthTweaksHelperLocale
    return Loc and Loc.ShowZone and Loc.ShowZone(zone) or zone
end

local function XY(spot) return string.format("%d, %d", math.floor(spot[2] + 0.5), math.floor(spot[3] + 0.5)) end

local MODE_TAG = { xp = "|cff66ccff" .. L["Experience"] .. "|r", gold = "|cffffd100" .. L["Gold"] .. "|r",
    balance = "|cff33ff33" .. L["Balanced"] .. "|r" }

-- Text of one spot row: name line, second line, right value, right detail. The zone is in the
-- section header, so the row doesn't repeat it.
function Grind.RowText(r, mode, level)
    local s = r.spot
    level = level or s[4]
    local tag = r.best and ("|cff33ff33" .. L["Best"] .. "|r  ") or ""
    local name = tag .. "|cffffffff" .. Grind.MobNames(s, 2) .. "|r  " .. Grind.Levels(level, s[4], s[5])
    local parts = { string.format(L["%d xp a kill"], math.floor(r.xp + 0.5)), string.format(L["%d kills/h"], math.floor(r.kph + 0.5)) }
    if r.toLevel then parts[#parts + 1] = L["level up in "] .. Grind.Duration(r.toLevel) end
    if r.camps and #r.camps > 1 then parts[#parts + 1] = string.format(L["%d camps"], #r.camps) end
    local sub = table.concat(parts, "   ")
    local warn = {}
    for _, w in ipairs(r.warnings) do if w.severe then warn[#warn + 1] = w.text end end
    if #warn > 0 then sub = "|cffff7777" .. table.concat(warn, ", ") .. "|r   " .. sub end
    local right, detail
    if mode == "gold" then right, detail = Money(r.gph) .. L["/h"], Short(r.xph) .. L[" xp/h"]
    else right, detail = Short(r.xph) .. L[" xp/h"], Money(r.gph) .. L["/h"] end
    return name, sub, right, detail
end

-- ---- The panel ---------------------------------------------------------------------------------
local panel
local lines, rows, offset = {}, {}, 0
local ROW_HEIGHT, TOP = 34, -70
Grind.choosing = false

local function Shown()
    local h = panel and panel.GetHeight and panel:GetHeight() or 0
    if not h or h <= 0 then return 10 end
    return math.max(3, math.min(#lines, math.floor((h + TOP - 24) / ROW_HEIGHT)))
end

-- Pictures: the monster's own model, else an icon for its family or type.
local ICONS = "Interface\\Icons\\"
local FAMILY_ICONS = { [1] = "Ability_Hunter_Pet_Wolf", [2] = "Ability_Hunter_Pet_Cat", [3] = "Ability_Hunter_Pet_Spider",
    [4] = "Ability_Hunter_Pet_Bear", [5] = "Ability_Hunter_Pet_Boar", [6] = "Ability_Hunter_Pet_Crocolisk",
    [7] = "Ability_Hunter_Pet_Vulture", [8] = "Ability_Hunter_Pet_Crab", [9] = "Ability_Hunter_Pet_Gorilla",
    [11] = "Ability_Hunter_Pet_Raptor", [12] = "Ability_Hunter_Pet_TallStrider", [20] = "Ability_Hunter_Pet_Scorpid",
    [21] = "Ability_Hunter_Pet_Turtle", [24] = "Ability_Hunter_Pet_Bat", [25] = "Ability_Hunter_Pet_Hyena",
    [26] = "Ability_Hunter_Pet_Owl", [27] = "Ability_Hunter_Pet_WindSerpent" }
local TYPE_ICONS = { [1] = "Ability_Hunter_BeastTaming", [2] = "INV_Misc_Head_Dragon_01", [3] = "Spell_Shadow_SummonImp",
    [4] = "Spell_Nature_StrengthOfEarthTotem02", [5] = "Ability_Warrior_Revenge", [6] = "Spell_Shadow_RaiseDead",
    [7] = "INV_Misc_Head_Human_01", [9] = "INV_Misc_Gear_01" }

function Grind.MobIcon(m)
    if not m then return ICONS .. "Ability_DualWield" end
    return ICONS .. (FAMILY_ICONS[m[6] or 0] or TYPE_ICONS[m[5] or 0] or "Ability_DualWield")
end

local function SetPicture(line, mobIndex)
    local m = Grind.Mob(mobIndex)
    line.icon:SetTexture(Grind.MobIcon(m))
    line.icon:Show()
    local model = rawget(line, "model")
    if not model then return end
    local display = m and m[4] or 0
    if display > 0 then
        local ok = pcall(function()
            if model.dthDisplay ~= display then
                model:ClearModel()
                model:SetDisplayInfo(display)
                if model.SetPortraitZoom then model:SetPortraitZoom(1) end
                model.dthDisplay = display
            end
        end)
        if ok then
            model:ClearAllPoints(); model:SetAllPoints(line.icon)
            model:Show(); line.icon:SetAlpha(0.25)
            return
        end
    end
    model:Hide(); line.icon:SetAlpha(1)
end

local function ItemIcon(id)
    local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id))
    return icon or (ICONS .. "INV_Misc_QuestionMark")
end

local QUALITY = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000" }

local function ItemName(id)
    local info = DufforthTweaksHelperGrindItems and DufforthTweaksHelperGrindItems[id]
    local name = (GetItemInfo and GetItemInfo(id)) or (info and info[1]) or ("item " .. id)
    return "|cff" .. (QUALITY[info and info[2] or 1] or "ffffff") .. name .. "|r"
end

local function DrawLine(line, r, mode, level)
    local hideModel = function() local m = rawget(line, "model"); if m then m:Hide() end; line.icon:SetAlpha(1) end
    line.cost:SetText(""); line.detail:SetText(""); line.sub:SetText("")
    if r.header then
        DufforthTweaksHelper.StyleRow(line, "header", r.closed)
        hideModel()
        line.name:SetText("|cffffd100" .. r.title .. "|r")
        line.cost:SetText(r.closed and string.format(L["%d hidden"], r.count) or "")
        line.detail:SetText(r.note or "")
        return
    end
    DufforthTweaksHelper.StyleRow(line, "child")
    if r.kind == "best" then
        local x = r.r
        SetPicture(line, x.spot[11] and x.spot[11][1])
        line.name:SetText(r.tags .. "  |cffffffff" .. Grind.MobNames(x.spot, 2) .. "|r  " .. Grind.Levels(level, x.spot[4], x.spot[5]))
        line.sub:SetText(ShownZone(ZoneOf(x.spot)) .. " " .. XY(x.spot) .. "   " .. string.format(L["%d xp a kill"], math.floor(x.xp + 0.5)))
        line.cost:SetText(Short(x.xph) .. L[" xp/h"]); line.detail:SetText(Money(x.gph) .. L["/h"])
    elseif r.kind == "spot" then
        SetPicture(line, r.r.spot[11] and r.r.spot[11][1])
        local name, sub, right, detail = Grind.RowText(r.r, mode, level)
        line.name:SetText(name); line.sub:SetText(sub); line.cost:SetText(right); line.detail:SetText(detail)
    elseif r.kind == "mob" then
        local e = r.e
        SetPicture(line, e.index)
        local open = r.open and "|cffaaaaaa" .. L["drops below"] .. "|r" or ""
        line.name:SetText("|cffffffff" .. e.mob[1] .. "|r  " .. Grind.Levels(level, e.mob[2], e.mob[3]))
        local parts = { string.format(L["%d xp a kill"], math.floor(e.xp + 0.5)), string.format(L["%d camps"], #e.camps) }
        local flags = e.flags
        if Has(flags, CASTER) then parts[#parts + 1] = "|cffff7777" .. L["caster"] .. "|r" end
        if Has(flags, HEALER) then parts[#parts + 1] = L["heals"] end
        if Has(flags, FLEES) then parts[#parts + 1] = L["runs away"] end
        if Has(flags, ELITE) then parts[#parts + 1] = "|cffff7777" .. L["elite"] .. "|r" end
        line.sub:SetText(table.concat(parts, "   "))
        line.cost:SetText(Money(e.value) .. L[" a kill"]); line.detail:SetText(open)
    elseif r.kind == "drop" then
        hideModel()
        line.icon:SetTexture(ItemIcon(r.item)); line.icon:Show()
        line.name:SetText("    " .. ItemName(r.item))
        line.sub:SetText("    " .. string.format(L["%.1f per 100 kills"], r.per * 100) .. "   " .. (r.source == "auction" and L["AH"] or r.source == "vendor" and L["vendor"] or ""))
        line.cost:SetText(Money(r.value)); line.detail:SetText(L["each"])
    end
end

local function Draw()
    if not panel then return end
    local mode = DB().mode or Grind.DEFAULT_MODE
    local level = UnitLevel and UnitLevel("player") or 1
    local shown = Shown()
    for i, line in ipairs(lines) do
        local r = rows[offset + i]
        if r and i <= shown then
            line.row = r
            local ok, err = pcall(DrawLine, line, r, mode, level)
            if not ok then line.name:SetText("|cffff5555" .. tostring(err) .. "|r") end
            line:Show()
        else
            line.row = nil
            line:Hide()
        end
    end
    if panel.pageText then
        panel.pageText:SetText(#rows > shown and string.format(L["%d-%d of %d"], offset + 1, math.min(#rows, offset + shown), #rows) or "")
    end
    if panel.status then
        panel.status:SetText(Grind.status or string.format(L["Your kills make these estimates better: %d saved."], Grind.KillCount and Grind.KillCount() or 0))
    end
end

local function Scroll(delta)
    offset = math.max(0, math.min(offset + delta, #rows - Shown()))
    Draw()
end

local function Collapsed()
    local g = DB()
    g.collapsed = g.collapsed or {}
    return g.collapsed
end

local function OpenMobs()
    local g = DB()
    g.openMobs = g.openMobs or {}
    return g.openMobs
end

function Grind.Toggle(key, default)
    local c = Collapsed()
    local closed = c[key]
    if closed == nil then closed = default or false end
    c[key] = not closed
    Grind.Refresh()
end

local function Closed(key, default)
    local v = Collapsed()[key]
    if v == nil then return default or false end
    return v
end

-- The rows for the chosen view: "Best right now" first, then zones with spots or with monsters and drops.
function Grind.BuildRows(view, p, spots, items, prices, mode)
    local out = {}
    local function Section(key, title, count, note, default)
        local closed = Closed(key, default)
        out[#out + 1] = { header = true, key = key, title = title, count = count, note = note, closed = closed }
        return not closed
    end
    -- Best right now, for each mode (one row per spot; a spot best for two modes shows both tags).
    local best = Grind.BestNow(spots, p, items, prices)
    local picks, seen = {}, {}
    for _, m in ipairs({ "balance", "xp", "gold" }) do
        local r = best[m]
        if r then
            if seen[r.spot] then seen[r.spot].tags = seen[r.spot].tags .. ", " .. MODE_TAG[m]
            else
                local row = { kind = "best", r = r, tags = MODE_TAG[m] }
                seen[r.spot] = row
                picks[#picks + 1] = row
            end
        end
    end
    if #picks > 0 and Section("grind:best", L["Best right now"], #picks, nil) then
        for _, row in ipairs(picks) do out[#out + 1] = row end
    end
    if view == "monsters" then
        for _, g in ipairs(Grind.Monsters(spots, p, items, prices)) do
            local zone = DufforthTweaksHelperGrindZones and DufforthTweaksHelperGrindZones[g.zone] or "?"
            if Section("grind:m:" .. zone, ShownZone(zone), #g.mobs, string.format(L["%d monsters"], #g.mobs)) then
                for _, e in ipairs(g.mobs) do
                    local key = zone .. ":" .. e.index
                    local open = OpenMobs()[key] and true or false
                    out[#out + 1] = { kind = "mob", e = e, key = key, open = open }
                    if open then
                        for _, d in ipairs(e.mob[9] or {}) do
                            local value, source = Grind.DropValue(d[1], items, prices)
                            out[#out + 1] = { kind = "drop", item = d[1], per = d[2], value = value, source = source, mob = e }
                        end
                    end
                end
            end
        end
    else
        for _, g in ipairs(Grind.Group(Grind.List(spots, p, items, prices, mode))) do
            local zone = DufforthTweaksHelperGrindZones and DufforthTweaksHelperGrindZones[g.zone] or "?"
            local top = g.rows[1]
            local note = top and (Short(top.xph) .. L[" xp/h"]) or nil
            if Section("grind:z:" .. zone, ShownZone(zone), #g.rows, note, top and top.tier > 0) then
                for _, r in ipairs(g.rows) do out[#out + 1] = { kind = "spot", r = r } end
            end
        end
    end
    return out
end

local function DrawSpecs(class, spec, source)
    local specs = Grind.SPECS[class] or {}
    local asking = Grind.choosing or not spec
    for i, b in ipairs(panel.specButtons) do
        local s = specs[i]
        if asking and s then
            b.key = s.key
            b:SetText(s.name)
            b:SetWidth(math.max(70, (b:GetFontString() and b:GetFontString():GetStringWidth() or 60) + 20))
            b:Show()
        else
            b:Hide()
        end
    end
    if asking then
        panel.question:SetText(L["Which spec do you play? It changes what's easy for you (saved for this character):"])
        panel.question:Show()
    else
        panel.question:Hide()
    end
    panel.specButton:SetText(spec and (L["Spec: "] .. spec.name) or L["Choose spec"])
    panel.specSource = source
end

function Grind.Refresh()
    if not panel then return end
    local ok, err = pcall(function()
        local p = Grind.Player()
        local spec, source = Grind.CurrentSpec()
        local class = p.class
        local className = UnitClass and UnitClass("player") or class
        panel.title:SetText(string.format(L["Grind spots for level %d %s"], p.level, className or ""))
        DrawSpecs(class, spec, source)
        local mode = DB().mode or Grind.DEFAULT_MODE
        local view = DB().view or "spots"
        panel.balanceButton:SetEnabled(mode ~= "balance")
        panel.xpButton:SetEnabled(mode ~= "xp"); panel.goldButton:SetEnabled(mode ~= "gold")
        panel.spotsButton:SetEnabled(view ~= "spots"); panel.monstersButton:SetEnabled(view ~= "monsters")
        Grind.DrawBoosts(p.boosts)
        local asking = Grind.choosing or not spec
        rows = asking and {} or Grind.BuildRows(view, p, DufforthTweaksHelperGrindSpots, DufforthTweaksHelperGrindItems, Prices(), mode)
        panel.empty:SetText(asking and "" or (#rows == 0 and L["No grind spots known for your level. Classic data covers levels 1-62 in the open world."] or ""))
        offset = math.min(offset, math.max(0, #rows - Shown()))
    end)
    if not ok then panel.empty:SetText("|cffff5555" .. L["Grind tab error: "] .. tostring(err) .. "|r") end
    Draw()
end

function Grind.DrawBoosts(state)
    if not (panel and panel.boosts) then return end
    local boosts = Grind.Boosts(state, Money)
    Grind.lastBoosts = boosts
    local missing = Grind.Missing(boosts)
    local on = {}
    for _, b in ipairs(boosts) do if b.ready and b.key ~= "rested" then on[#on + 1] = b.key end end
    local text
    if missing > 0 then
        for _, b in ipairs(boosts) do if not b.ready and b.key ~= "rested" then text = "|cffffd100" .. (b.short or b.text) .. "|r"; break end end
    elseif #on > 0 then
        text = "|cff33ff33" .. string.format(L["Boosts on: +%d%% experience."], math.floor(((state and Grind.XPBonus(state) or 1) - 1) * 100 + 0.5)) .. "|r"
    else
        text = "|cffaaaaaa" .. L["No experience boosts in your bags. Hover for what helps."] .. "|r"
    end
    panel.boosts.label:SetText(text)
end

-- The reminder when you pick a spot: what to use before you start, with a button for the elixir.
local notice
local function Notice()
    if notice then return notice end
    local f = CreateFrame("Frame", "DufforthTweaksHelperGrindNotice", UIParent, "BackdropTemplate")
    f:SetSize(320, 96)
    f:SetFrameStrata("DIALOG")
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(0.05, 0.05, 0.05, 0.95); f:SetBackdropBorderColor(1, 0.82, 0, 0.8)
    end
    local point = DB().noticePoint
    if point then f:SetPoint(point[1], UIParent, point[1], point[2], point[3]) else f:SetPoint("TOP", UIParent, "TOP", 0, -140) end
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local a, _, _, x, y = self:GetPoint()
        DB().noticePoint = { a, x, y }
    end)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 10, -8); f.title:SetText(L["Before you grind"])
    f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.body:SetPoint("TOPLEFT", 10, -26); f.body:SetWidth(300); f.body:SetJustifyH("LEFT")
    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", 2, 2)
    -- A secure button: using an item needs your click. Built and changed only out of combat.
    f.use = CreateFrame("Button", "DufforthTweaksHelperGrindElixir", f, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    f.use:SetSize(150, 22); f.use:SetPoint("BOTTOMLEFT", 10, 8)
    f.use:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    f.use:SetAttribute("type", "item"); f.use:SetAttribute("item", "item:" .. Grind.ELIXIR_ITEM)
    f.use:SetText(L["Use the elixir"])
    f.use:SetScript("PostClick", function() if C_Timer then C_Timer.After(1, function() pcall(Grind.ShowNotice, true) end) end end)
    if DufforthTweaksHelper and DufforthTweaksHelper.RegisterMovable then
        DufforthTweaksHelper.RegisterMovable({ label = L["Grind reminder"], get = function() return f end,
            enter = function(frame) frame:Show() end, leave = function(frame) frame:Hide() end })
    end
    notice = f
    return f
end

-- Shown when you pick a spot and something could still boost you. refresh = only redraw if open.
function Grind.ShowNotice(refresh)
    if InCombatLockdown and InCombatLockdown() then return end
    local f = Notice()
    if refresh and not f:IsShown() then return end
    local state = Grind.ReadBoosts()
    local boosts = Grind.Boosts(state, Money)
    if Grind.Missing(boosts) == 0 and not refresh then return end
    local lines = {}
    for _, b in ipairs(boosts) do lines[#lines + 1] = (b.ready and "|cff33ff33" or "|cffffd100") .. b.text .. "|r" end
    f.body:SetText(table.concat(lines, "\n"))
    local showUse = state.elixirInBags and not state.elixirActive
    f.use:SetShown(showUse and true or false)
    local h = (f.body.GetStringHeight and f.body:GetStringHeight() or 14 * #lines)
    f:SetHeight(math.max(60, 34 + h + (showUse and 32 or 8)))
    f:Show()
    if C_Timer and not refresh then C_Timer.After(45, function() if f:IsShown() and not (f.IsMouseOver and f:IsMouseOver()) then f:Hide() end end) end
end

-- A fight starts: the notice goes (it holds a secure button, which can't hide later in combat).
local noticeWatcher = CreateFrame("Frame")
pcall(noticeWatcher.RegisterEvent, noticeWatcher, "PLAYER_REGEN_DISABLED")
pcall(noticeWatcher.RegisterEvent, noticeWatcher, "UNIT_AURA")
noticeWatcher:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_REGEN_DISABLED" then
        if notice and notice:IsShown() then notice:Hide() end
    elseif unit == "player" and notice and notice:IsShown() then
        pcall(Grind.ShowNotice, true)
    end
end)

-- A click: the guide's arrow and the game's map pin on a camp. Clicking the same row again goes to
-- its next camp.
function Grind.PinSpot(r)
    if not r then return end
    local camps = r.camps or { r.spot }
    r.campIndex = ((r.campIndex or 0) % #camps) + 1
    local s = camps[r.campIndex]
    local zone = ZoneOf(s)
    local GD = DufforthTweaksHelperGuideData
    local map = GD and GD.uiMaps and GD.uiMaps[zone]
    if not map and C_Map and C_Map.GetBestMapForUnit then map = C_Map.GetBestMapForUnit("player") end
    local text = string.format(L["Grind: %s"], Grind.MobNames(s, 2))
    local UI = DufforthTweaksHelperGuideUI
    if UI and map then
        UI.override = { map = map, x = s[2], y = s[3], zone = zone, text = text }
        if UI.Refresh then pcall(UI.Refresh) end
    end
    local ok = pcall(function()
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, s[2] / 100, s[3] / 100))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    end)
    pcall(Grind.ShowNotice)
    local camp = #camps > 1 and string.format(L[" (camp %d of %d: click again for the next)"], r.campIndex, #camps) or ""
    Grind.status = (ok and string.format(L["Arrow and map pin on %s %s."], ShownZone(zone), XY(s))
        or string.format(L["The spot is at %s %s."], ShownZone(zone), XY(s))) .. camp
    Draw()
end

local function Row(label, value) GameTooltip:AddDoubleLine(label, value, 0.75, 0.75, 0.75, 1, 1, 1) end

-- Hover on a spot: every number behind the row.
function Grind.Tooltip(owner, r)
    local s, p = r.spot, Grind.Player()
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(Grind.MobNames(s, 3), 1, 1, 1)
    GameTooltip:AddLine(string.format(L["Level %s, %d spawns about %d yards apart, back after %s."],
        Grind.Levels(p.level, s[4], s[5]), s[6], s[7], Grind.Duration(s[8])), 0.75, 0.75, 0.75, true)
    if r.best then GameTooltip:AddLine(L["Best: easy for you, close together and among the most experience per hour."], 0.2, 1, 0.2, true) end
    for _, w in ipairs(r.warnings) do
        local why = (w.key == "caster" and p.spec and p.spec.why ~= "") and (" (" .. p.spec.why .. ")") or ""
        if w.severe then GameTooltip:AddLine(w.text .. why, 1, 0.4, 0.4, true) else GameTooltip:AddLine(w.text, 1, 0.82, 0, true) end
    end
    GameTooltip:AddLine(" ")
    Row(L["Experience a kill"], tostring(math.floor(r.xp + 0.5)))
    Row(L["Time a kill (fight, rest, walk)"], string.format("%d s", math.floor(r.perKill + 0.5)))
    Row(L["Kills an hour"], tostring(math.floor(r.kph + 0.5)) .. (r.limited and L[" (respawn limits it)"] or ""))
    Row(L["Experience an hour"], Short(r.xph))
    if r.toLevel then Row(L["Next level"], string.format(L["%d kills, %s"], r.kills or 0, Grind.Duration(r.toLevel))) end
    Row(L["Gold an hour"], Money(r.gph))
    if r.camps and #r.camps > 1 then
        local where = {}
        for k, c in ipairs(r.camps) do if k <= 6 then where[#where + 1] = XY(c) end end
        Row(string.format(L["%d camps"], #r.camps), table.concat(where, "; "))
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Click for the arrow and a map pin. Classic estimates; Forever may differ."], 0.5, 0.5, 0.5, true)
    GameTooltip:Show()
end

-- Hover on a monster: how it fights and what it drops.
function Grind.MobTooltip(owner, e)
    local m, p = e.mob, Grind.Player()
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(m[1], 1, 1, 1)
    GameTooltip:AddLine(string.format(L["Level %s, %d camps in this zone."], Grind.Levels(p.level, m[2], m[3]), #e.camps), 0.75, 0.75, 0.75, true)
    Row(L["Experience a kill"], tostring(math.floor(e.xp + 0.5)))
    Row(L["Coins and vendor trash a kill"], Money(m[8] or 0))
    for _, d in ipairs(m[9] or {}) do
        local v, source = Grind.DropValue(d[1], DufforthTweaksHelperGrindItems, Prices())
        GameTooltip:AddDoubleLine(string.format(L["    %s (%.1f per 100 kills)"], ItemName(d[1]), d[2] * 100),
            Money(v) .. " " .. (source == "auction" and L["AH"] or source == "vendor" and L["vendor"] or ""), 0.75, 0.75, 0.75, 1, 1, 1)
    end
    Row(L["Worth a kill"], Money(e.value))
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Click to show or hide its drops. Right-click for the arrow to its camp."], 0.5, 0.5, 0.5, true)
    GameTooltip:Show()
end

local function OnRowEnter(line)
    local r = line.row
    if not r then return end
    if r.kind == "spot" then Grind.Tooltip(line, r.r)
    elseif r.kind == "best" then Grind.Tooltip(line, r.r)
    elseif r.kind == "mob" then Grind.MobTooltip(line, r.e)
    elseif r.kind == "drop" then
        GameTooltip:SetOwner(line, "ANCHOR_RIGHT")
        if GameTooltip.SetItemByID then GameTooltip:SetItemByID(r.item) else GameTooltip:AddLine(ItemName(r.item)) end
        GameTooltip:Show()
    end
end

local function OnRowClick(line, button)
    local r = line.row
    if not r then return end
    if r.header then Collapsed()[r.key] = not r.closed; Grind.Refresh(); return end
    if r.kind == "spot" or r.kind == "best" then Grind.PinSpot(r.r); return end
    if r.kind == "mob" then
        if button == "RightButton" then
            local e = r.e
            Grind.PinSpot({ spot = e.camps[1], camps = e.camps })
        else
            local open = OpenMobs()
            open[r.key] = not open[r.key] or nil
            Grind.Refresh()
        end
    elseif r.kind == "drop" then
        local LV = DufforthTweaksHelperLeveling
        if LV and LV.SearchAuctionHouse and LV.Where and LV.Where().auction then pcall(LV.SearchAuctionHouse, r.item) end
    end
end

local function Flat(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 60, 20)
    b:SetText(text)
    return b
end

function Grind.BuildPanel(parent, width)
    panel = parent
    panel.title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", 8, -4)
    panel.status = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.status:SetPoint("BOTTOMLEFT", 8, 6); panel.status:SetWidth(width - 120); panel.status:SetJustifyH("LEFT")
    if panel.status.SetWordWrap then panel.status:SetWordWrap(false) end
    local function Mode(button, mode, tip)
        button:SetScript("OnClick", function() DB().mode = mode; offset = 0; Grind.Refresh() end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT"); GameTooltip:AddLine(tip, 1, 1, 1, true); GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    panel.balanceButton = Flat(parent, L["Balanced"], 72)
    panel.balanceButton:SetPoint("TOPLEFT", 8, -22)
    Mode(panel.balanceButton, "balance", L["Balanced: the best mix of experience and gold. Experience or Gold puts one first."])
    panel.xpButton = Flat(parent, L["Experience"], 80)
    panel.xpButton:SetPoint("LEFT", panel.balanceButton, "RIGHT", 4, 0)
    Mode(panel.xpButton, "xp", L["Most experience an hour first."])
    panel.goldButton = Flat(parent, L["Gold"], 50)
    panel.goldButton:SetPoint("LEFT", panel.xpButton, "RIGHT", 4, 0)
    Mode(panel.goldButton, "gold", L["Most gold an hour first (coins, vendor trash and drops at their auction price)."])
    panel.specButton = Flat(parent, L["Choose spec"], 150)
    panel.specButton:SetPoint("TOPRIGHT", -8, -22)
    panel.specButton:SetScript("OnClick", function() Grind.choosing = not Grind.choosing; Grind.Refresh() end)
    panel.specButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine(L["Your spec"], 1, 1, 1)
        GameTooltip:AddLine(panel.specSource == "talents" and L["Read from your talents. Click to choose another."]
            or panel.specSource == "chosen" and L["You chose it. Click to change."]
            or L["The game doesn't tell the addon your spec here: click and pick it once."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    panel.specButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Second row: the view (spots or monsters) and the experience boosts.
    panel.spotsButton = Flat(parent, L["Spots"], 56)
    panel.spotsButton:SetPoint("TOPLEFT", 8, -46)
    panel.spotsButton:SetScript("OnClick", function() DB().view = "spots"; offset = 0; Grind.Refresh() end)
    panel.monstersButton = Flat(parent, L["Monsters"], 72)
    panel.monstersButton:SetPoint("LEFT", panel.spotsButton, "RIGHT", 4, 0)
    panel.monstersButton:SetScript("OnClick", function() DB().view = "monsters"; offset = 0; Grind.Refresh() end)
    panel.boosts = CreateFrame("Button", nil, parent)
    panel.boosts:SetPoint("LEFT", panel.monstersButton, "RIGHT", 8, 0); panel.boosts:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
    panel.boosts:SetHeight(18)
    panel.boosts.label = panel.boosts:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.boosts.label:SetAllPoints(); panel.boosts.label:SetJustifyH("LEFT")
    if panel.boosts.label.SetWordWrap then panel.boosts.label:SetWordWrap(false) end
    panel.boosts:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine(L["Experience boosts"], 1, 1, 1)
        for _, b in ipairs(Grind.lastBoosts or {}) do
            GameTooltip:AddLine((b.ready and "|cff33ff33" or "|cffffd100") .. b.text .. "|r", 1, 1, 1, true)
        end
        GameTooltip:AddLine(L["Rates in the list already count the boosts you have on."], 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    panel.boosts:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.question = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.question:SetPoint("TOPLEFT", 12, TOP - 4); panel.question:SetWidth(width - 24); panel.question:SetJustifyH("LEFT")
    panel.specButtons = {}
    for i = 1, 4 do
        local b = Flat(parent, "", 110)
        b:SetPoint("TOPLEFT", 12, TOP - 44 - (i - 1) * 26)
        b:SetScript("OnClick", function(self) if self.key then Grind.ChooseSpec(self.key) end end)
        b:Hide()
        panel.specButtons[i] = b
    end
    panel.empty = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.empty:SetPoint("TOPLEFT", 12, TOP - 8); panel.empty:SetWidth(width - 24); panel.empty:SetJustifyH("LEFT")
    for i = 1, 24 do
        local line = CreateFrame("Button", nil, parent)
        line:SetSize(width - 8, ROW_HEIGHT)
        line:SetPoint("TOPLEFT", 4, TOP - (i - 1) * ROW_HEIGHT)
        line:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        line:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        line.icon = line:CreateTexture(nil, "ARTWORK")
        line.icon:SetSize(24, 24); line.icon:SetPoint("LEFT", 16, 0)
        local okModel, model = pcall(CreateFrame, "PlayerModel", nil, line)
        if okModel and model then
            model:SetSize(26, 26)
            model:Hide()
            rawset(line, "model", model)
        end
        line.cost = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        line.cost:SetPoint("TOPRIGHT", -6, -3); line.cost:SetJustifyH("RIGHT")
        line.detail = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line.detail:SetPoint("BOTTOMRIGHT", -6, 4); line.detail:SetJustifyH("RIGHT")
        line.name = line:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        line.name:SetPoint("TOPLEFT", 46, -3); line.name:SetPoint("RIGHT", line.cost, "LEFT", -6, 0); line.name:SetJustifyH("LEFT")
        line.sub = line:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        line.sub:SetPoint("BOTTOMLEFT", 46, 4); line.sub:SetPoint("RIGHT", line.detail, "LEFT", -6, 0); line.sub:SetJustifyH("LEFT")
        for _, f in ipairs({ line.name, line.sub }) do if f.SetWordWrap then f:SetWordWrap(false) end end
        local thisLine = line
        line:SetScript("OnEnter", function() pcall(OnRowEnter, thisLine) end)
        line:SetScript("OnLeave", function() GameTooltip:Hide() end)
        line:SetScript("OnClick", function(_, button) pcall(OnRowClick, thisLine, button) end)
        line:Hide()
        lines[i] = line
    end
    panel.up = DufforthTweaksHelper.ArrowButton(parent, "up", function() Scroll(-Shown()) end)
    panel.up:SetPoint("BOTTOMRIGHT", -30, 2)
    panel.down = DufforthTweaksHelper.ArrowButton(parent, "down", function() Scroll(Shown()) end)
    panel.down:SetPoint("LEFT", panel.up, "RIGHT", 4, 0)
    panel.pageText = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.pageText:SetPoint("RIGHT", panel.up, "LEFT", -6, 0); panel.pageText:SetJustifyH("RIGHT")
    parent:EnableMouseWheel(true)
    parent:SetScript("OnMouseWheel", function(_, delta) Scroll(-delta * 2) end)
    parent:HookScript("OnShow", Grind.Refresh)
end

-- New level, new experience, auction house open or closed (prices shown don't change, but the
-- tab is often open then): redraw while the tab shows.
local watcher = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE" }) do
    pcall(watcher.RegisterEvent, watcher, event)
end
local pending = false
watcher:SetScript("OnEvent", function()
    if pending or not (panel and panel.IsVisible and panel:IsVisible()) then return end
    pending = true
    local function go() pending = false; Grind.Refresh() end
    if C_Timer then C_Timer.After(0.5, go) else go() end
end)

-- ---- The kill log in the game ----
local function SpecKey()
    local spec = Grind.CurrentSpec()
    return spec and spec.key or nil
end

Grind.game = {
    now = function() return GetTime and GetTime() or 0 end,
    time = function() return time and time() or 0 end,
    format = COMBATLOG_XPGAIN_FIRSTPERSON,
    target = function()
        if not (UnitExists and UnitExists("target")) or (UnitIsPlayer and UnitIsPlayer("target")) then return nil end
        if UnitCanAttack and not UnitCanAttack("player", "target") then return nil end
        return { guid = Plain(UnitGUID and UnitGUID("target")), name = Plain(UnitName and UnitName("target")),
            level = Plain(UnitLevel and UnitLevel("target")), rank = Plain(UnitClassification and UnitClassification("target")),
            kind = Plain(UnitCreatureType and UnitCreatureType("target")) }
    end,
    casting = function()
        -- A hidden (secret) value still means something is being cast.
        return (UnitCastingInfo and UnitCastingInfo("target")) ~= nil or (UnitChannelInfo and UnitChannelInfo("target")) ~= nil
    end,
    player = function()
        local Loc = DufforthTweaksHelperLocale
        local zone = Loc and Loc.ZoneName and Loc.ZoneName() or (GetRealZoneText and GetRealZoneText()) or ""
        local x, y
        if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
            local map = C_Map.GetBestMapForUnit("player")
            local pos = map and C_Map.GetPlayerMapPosition(map, "player")
            if pos and pos.GetXY then
                local px, py = pos:GetXY()
                px, py = Plain(px), Plain(py)
                if px and py then x, y = math.floor(px * 1000 + 0.5) / 10, math.floor(py * 1000 + 0.5) / 10 end
            end
        end
        return { level = UnitLevel and UnitLevel("player") or 0, zone = zone, x = x, y = y,
            group = IsInGroup and IsInGroup() or false, class = ClassToken(), spec = SpecKey() }
    end,
}

local function KillLog()
    local g = DB()
    g.kills = g.kills or {}
    return g.kills
end

local function Guarded(where, f, ...)
    local ok, err = pcall(f, ...)
    if not ok then
        local g = DB()
        g.logErrors = g.logErrors or {}
        local key = where .. ": " .. tostring(err)
        g.logErrors[key] = (g.logErrors[key] or 0) + 1
    end
end

local function LogDebug()
    local g = DB()
    g.logDebug = g.logDebug or {}
    return g.logDebug
end

local killWatcher = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "CHAT_MSG_COMBAT_XP_GAIN", "PLAYER_XP_UPDATE" }) do
    local ok = pcall(killWatcher.RegisterEvent, killWatcher, event)
    if not ok then Guarded("register", error, "unknown event " .. event) end
end
local tickAt = 0
killWatcher:SetScript("OnEvent", function(_, event, msg)
    if event == "PLAYER_LOGIN" then
        Guarded("login", function()
            DB().logErrors = nil -- only this session's errors
            DB().logDebug = { session = time and time() or 0, format = COMBATLOG_XPGAIN_FIRSTPERSON or "none" }
            Grind.ApplyTune(DufforthTweaksHelperGrindTune)
        end)
        return
    end
    if not Grind.tracker then
        Grind.tracker = Grind.NewTracker(Grind.game, KillLog(), LogDebug())
        Grind.tracker.lastXP = { Plain(UnitXP and UnitXP("player")), Plain(UnitXPMax and UnitXPMax("player")), UnitLevel and UnitLevel("player") }
    end
    local t = Grind.tracker
    if event == "PLAYER_TARGET_CHANGED" then Guarded("target", t.OnTarget, t)
    elseif event == "PLAYER_REGEN_DISABLED" then Guarded("combat", t.OnCombat, t, true)
    elseif event == "PLAYER_REGEN_ENABLED" then Guarded("combat", t.OnCombat, t, false)
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then Guarded("xp", t.OnXP, t, msg)
    elseif event == "PLAYER_XP_UPDATE" then
        Guarded("xpbar", t.OnXPUpdate, t, Plain(UnitXP and UnitXP("player")), Plain(UnitXPMax and UnitXPMax("player")),
            UnitLevel and UnitLevel("player"))
    end
end)
killWatcher:SetScript("OnUpdate", function()
    local t = Grind.tracker
    if not t then return end
    if t.pending then Guarded("flush", t.Flush, t) end
    if not t.fightStart then return end
    local now = GetTime and GetTime() or 0
    if now - tickAt < 0.5 then return end
    tickAt = now
    Guarded("tick", t.OnTick, t)
end)

function Grind.KillCount() return #(KillLog()) end
