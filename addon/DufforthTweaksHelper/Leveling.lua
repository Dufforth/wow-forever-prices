-- Leveling tab: the cheapest way to level a profession from your skill to your current cap.
--
-- For every skill point it picks the recipe with the lowest expected cost per point:
--   (materials - what you get back selling what you made, at most 80% of them) / chance of a skill point
-- plus, the first time a recipe you don't know is used, what learning it costs (trainer fee,
-- or the recipe item from a vendor or the auction house), spread over the points it can give.
-- Skill-up chance uses the game's colors: orange 100%, yellow and green
-- (gray - skill) / (gray - yellow), gray none.
--
-- Recipes and skill colors come from the game data (LevelingData.lua), prices from the
-- download (Prices.lua; vendor materials always at the vendor's price), and trainers and
-- recipe vendors from Classic data (CMaNGOS), so their places are estimates.

local Leveling = {}
DufforthTweaksHelperLeveling = Leveling

local SPELL, PROF, LEARN, YELLOW, GRAY, PRODUCT, COUNT, SELL, NAME, HOW, RECIPE_ITEM, MATS = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
local CUT = 0.95
local RESALE_SHARE = 0.8 -- the most of a craft's materials that selling it back can recover
local MIN_WINDOW = 5 -- a learning cost is spread over at least this many points
local ROW_HEIGHT, VISIBLE_ROWS = 32, 8
local CAPS = { 75, 150, 225, 300 }
local RANK_NAMES = { [75] = "Journeyman", [150] = "Expert", [225] = "Artisan" }

local function DB()
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    local l = DufforthTweaksHelperDB.leveling or {}
    DufforthTweaksHelperDB.leveling = l
    if l.unlearned == nil then l.unlearned = true end
    if l.resale == nil then l.resale = true end
    if l.openWithProfession == nil then l.openWithProfession = true end
    return l
end
Leveling.Options = DB

local function Professions()
    return DufforthTweaksHelperProfessions or {}
end

-- ---- Pure logic (tested in tests/addon/leveling_sim.py) ----

function Leveling.Green(recipe)
    return math.floor((recipe[YELLOW] + recipe[GRAY]) / 2)
end

-- Chance that one craft at this skill gives a point.
function Leveling.Chance(recipe, skill)
    if skill < recipe[LEARN] or skill >= recipe[GRAY] then return 0 end
    if skill < recipe[YELLOW] then return 1 end
    return (recipe[GRAY] - skill) / (recipe[GRAY] - recipe[YELLOW])
end

function Leveling.Color(recipe, skill)
    if skill >= recipe[GRAY] then return "gray" end
    if skill >= Leveling.Green(recipe) then return "green" end
    if skill >= recipe[YELLOW] then return "yellow" end
    return "orange"
end

-- Materials for one craft: total cost (nil if any has no price) and the parts.
function Leveling.MaterialsCost(recipe, prices)
    local cost, parts, mats = 0, {}, recipe[MATS]
    for i = 1, #mats, 2 do
        local each, source = DufforthTweaksHelperCrafting.MaterialCost(mats[i], prices)
        parts[#parts + 1] = { id = mats[i], count = mats[i + 1], each = each, source = source }
        if each and cost then cost = cost + each * mats[i + 1] else cost = nil end
    end
    return cost, parts
end

-- What one craft's product brings back: the better of the auction (after the cut) and a vendor.
function Leveling.Resale(recipe, prices)
    local ah = prices[recipe[PRODUCT]]
    local best = math.max(ah and ah * CUT or 0, recipe[SELL] or 0)
    return best * recipe[COUNT], (ah and ah * CUT or 0) >= (recipe[SELL] or 0) and ah and "auction" or "vendor"
end

local function NPC(index)
    return (DufforthTweaksHelperLevelNPCs or {})[index]
end

-- Places that teach or sell a recipe, your side's first: { {npc, cost, extra}, ... }.
-- The capital cities: trainers there come first (the user's choice), since you pass them most.
local CITIES = { ["Stormwind City"] = true, ["Ironforge"] = true, ["Darnassus"] = true,
    ["Orgrimmar"] = true, ["Thunder Bluff"] = true, ["Undercity"] = true }
Leveling.CITIES = CITIES

local function Places(list, side, cityFirst)
    local out = {}
    for i = 1, #(list or {}), 3 do
        local npc = NPC(list[i])
        if npc and (npc[3] == "" or npc[3] == side or not side) then
            out[#out + 1] = { npc = npc, cost = list[i + 1], extra = list[i + 2] }
        end
    end
    table.sort(out, function(a, b)
        local ca, cb = CITIES[a.npc[4]] and 1 or 0, CITIES[b.npc[4]] and 1 or 0
        if cityFirst and ca ~= cb then return ca > cb end
        if a.cost ~= b.cost then return a.cost < b.cost end
        if ca ~= cb then return ca > cb end
        return a.npc[1] < b.npc[1]
    end)
    return out
end
Leveling.Places = Places

-- How you'd get a recipe and what it costs: cost (nil = can't plan on it), kind, places.
-- kind: known, starter, trainer, vendor, auction.
function Leveling.Acquire(recipe, known, side, prices)
    local spell, how = recipe[SPELL], recipe[HOW]
    if known and known.spells[spell] then return 0, "known" end
    if how == "s" then return 0, "starter" end
    if how == "t" then
        local trainers = Places((DufforthTweaksHelperLevelTrainers or {})[spell], side, true)
        if #trainers == 0 and (DufforthTweaksHelperLevelTrainers or {})[spell] then return nil end -- other faction only
        return trainers[1] and trainers[1].cost or 0, "trainer", trainers
    end
    local item = recipe[RECIPE_ITEM]
    if item and item > 0 then
        local vendors = Places((DufforthTweaksHelperLevelVendors or {})[item], side)
        local ah = prices[item]
        if vendors[1] and (not ah or vendors[1].cost <= ah) then return vendors[1].cost, "vendor", vendors end
        if ah then return ah, "auction", vendors end
    end
    return nil
end

-- The cheapest plan from `skill` to `target` for one profession.
-- options: unlearned (include recipes you don't know), resale (count selling what you make).
-- Returns { steps = {...}, crafts, materials, learning, resale, total, stoppedAt, reached }.
function Leveling.Plan(professionIndex, skill, target, known, options, prices, side)
    prices = prices or {}
    local candidates = {}
    for _, recipe in ipairs(DufforthTweaksHelperLevelRecipes or {}) do
        if recipe[PROF] == professionIndex and recipe[GRAY] > skill and recipe[LEARN] < target then
            local acquire, kind, places = Leveling.Acquire(recipe, known, side, prices)
            local allowed = acquire ~= nil and (kind == "known" or kind == "starter" or options.unlearned)
            local cost, parts = Leveling.MaterialsCost(recipe, prices)
            if allowed and cost then
                -- Selling back recovers at most RESALE_SHARE of the materials: not everything sells,
                -- listings cost a deposit, and a craft that seemed free would make the plan pick
                -- recipes that need many more crafts per point.
                local back = options.resale and math.min(Leveling.Resale(recipe, prices), cost * RESALE_SHARE) or 0
                candidates[#candidates + 1] = { recipe = recipe, acquire = acquire, kind = kind, places = places, parts = parts,
                    materials = cost, back = back, net = cost - back }
            end
        end
    end

    local plan = { steps = {}, crafts = 0, materials = 0, learning = 0, resale = 0, total = 0, reached = skill }
    local learned, step = {}, nil
    for level = skill, target - 1 do
        local best, bestScore
        for _, c in ipairs(candidates) do
            local chance = Leveling.Chance(c.recipe, level)
            if chance > 0 and c.recipe[LEARN] <= level then
                local score = c.net / chance
                if not learned[c] and c.acquire > 0 then
                    score = score + c.acquire / math.max(MIN_WINDOW, Leveling.Green(c.recipe) - level)
                end
                if not best or score < bestScore or (score == bestScore and c.recipe[SPELL] < best.recipe[SPELL]) then
                    best, bestScore = c, score
                end
            end
        end
        if not best then
            plan.stoppedAt = level
            break
        end
        local crafts = 1 / Leveling.Chance(best.recipe, level)
        if not step or step.candidate ~= best then
            step = { candidate = best, recipe = best.recipe, from = level, to = level + 1, crafts = 0, learning = 0,
                color = Leveling.Color(best.recipe, level), chance = Leveling.Chance(best.recipe, level) }
            plan.steps[#plan.steps + 1] = step
            if not learned[best] then
                learned[best] = true
                step.learning = best.acquire
            end
        end
        step.to = level + 1
        step.crafts = step.crafts + crafts
        plan.reached = level + 1
    end
    for _, s in ipairs(plan.steps) do
        s.crafts = math.ceil(s.crafts - 0.01)
        s.materials = s.crafts * s.candidate.materials
        s.back = s.crafts * s.candidate.back
        s.cost = s.materials - s.back + s.learning
        plan.crafts = plan.crafts + s.crafts
        plan.materials = plan.materials + s.materials
        plan.resale = plan.resale + s.back
        plan.learning = plan.learning + s.learning
    end
    plan.total = plan.materials - plan.resale + plan.learning
    return plan
end

-- Everything to buy for a plan: { {id, count, each, source}, ... }, most expensive first.
function Leveling.ShoppingList(plan)
    local totals, order = {}, {}
    for _, s in ipairs(plan.steps) do
        for _, part in ipairs(s.candidate.parts) do
            local t = totals[part.id]
            if not t then
                t = { id = part.id, count = 0, each = part.each, source = part.source }
                totals[part.id] = t
                order[#order + 1] = t
            end
            t.count = t.count + part.count * s.crafts
        end
    end
    table.sort(order, function(a, b) return (a.each or 0) * a.count > (b.each or 0) * b.count end)
    return order
end

-- ---- Buying and crafting (pure; the game calls are below the tab) ----
-- have(id) is how many you carry.
function Leveling.Missing(item, have)
    return math.max(0, item.count - (have(item.id) or 0))
end

-- What to buy from an open vendor. merchant: { [itemID] = { index, price (one purchase),
-- bundle (items per purchase), available (-1 = no limit) } }. Buys only what you're missing,
-- and only when the vendor is no dearer than the list's cheapest price.
function Leveling.VendorPlan(list, have, merchant)
    local buys, total = {}, 0
    for _, t in ipairs(list) do
        local m, missing = merchant[t.id], Leveling.Missing(t, have)
        if m and missing > 0 then
            local bundle = math.max(1, m.bundle or 1)
            if t.source == "vendor" or not t.each or m.price / bundle <= t.each then
                local purchases = math.ceil(missing / bundle)
                if m.available and m.available >= 0 then purchases = math.min(purchases, m.available) end
                if purchases > 0 then
                    local cost = purchases * m.price
                    buys[#buys + 1] = { id = t.id, index = m.index, purchases = purchases, bundle = bundle, units = purchases * bundle, price = m.price, cost = cost }
                    total = total + cost
                end
            end
        end
    end
    return buys, total
end

-- How many crafts your bags can take: free slots hold `stack` each, plus the room left in your
-- stacks of the item already. perCraft: items one craft makes. Materials used up can free more,
-- so this is the least that fits.
function Leveling.CraftsThatFit(freeSlots, stack, have, perCraft)
    stack, have, perCraft = math.max(1, stack or 1), have or 0, math.max(1, perCraft or 1)
    local room = (have % stack == 0) and 0 or (stack - have % stack)
    return math.floor((freeSlots * stack + room) / perCraft)
end

-- How many times the Craft button crafts the current step: what the step needs, or what your
-- materials allow if that's fewer.
function Leveling.CraftCount(step, available)
    return math.max(0, math.min(step.crafts, available or 0))
end

local GATHERING_NAMES = { Mining = true }

-- Skill line numbers the game uses, so a renamed or translated profession still matches.
local SKILL_LINES = {
    [171] = "Alchemy", [164] = "Blacksmithing", [333] = "Enchanting", [202] = "Engineering", [165] = "Leatherworking",
    [197] = "Tailoring", [185] = "Cooking", [129] = "First Aid", [186] = "Mining",
}

-- Your crafting professions: { name = { rank, max } }.
function Leveling.ReadProfessions()
    local out, wanted = {}, {}
    for _, name in ipairs(Professions()) do wanted[name] = true end
    if GetProfessions and GetProfessionInfo then
        -- Fixed slots (first, second, archaeology, fishing, cooking, first aid); empty ones are nil.
        local slots = { GetProfessions() }
        for i = 1, 6 do
            if slots[i] then
                local name, _, rank, max, _, _, line, modifier = GetProfessionInfo(slots[i])
                name = SKILL_LINES[line] or name
                if name and wanted[name] and rank then out[name] = { rank = rank + (modifier or 0), max = (max and max > 0) and max or 300 } end
            end
        end
    end
    if not next(out) and GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local name, header, _, rank, _, modifier, max = GetSkillLineInfo(i)
            if not header and name and wanted[name] and rank then out[name] = { rank = rank + (modifier or 0), max = max or 300 } end
        end
    end
    return out
end

-- The spells of the recipes in the open profession window.
local function OpenWindowSpells()
    local out = {}
    if GetNumTradeSkills and GetTradeSkillRecipeLink then
        for i = 1, GetNumTradeSkills() or 0 do
            local link = GetTradeSkillRecipeLink(i)
            local id = link and tonumber(string.match(link, "enchant:(%d+)") or string.match(link, "spell:(%d+)"))
            if id then out[#out + 1] = id end
        end
    end
    if #out == 0 and C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
        for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do out[#out + 1] = id end
    end
    if #out == 0 and GetNumCrafts and (GetCraftRecipeLink or GetCraftItemLink) then
        for i = 1, GetNumCrafts() or 0 do
            local link = (GetCraftRecipeLink and GetCraftRecipeLink(i)) or (GetCraftItemLink and GetCraftItemLink(i))
            local id = link and tonumber(string.match(link, "enchant:(%d+)") or string.match(link, "spell:(%d+)"))
            if id then out[#out + 1] = id end
        end
    end
    return out
end

local professionOfSpell
-- The profession most of these recipe spells belong to, from the recipe data.
function Leveling.ProfessionOfSpells(spells)
    if not professionOfSpell then
        professionOfSpell = {}
        for _, recipe in ipairs(DufforthTweaksHelperLevelRecipes or {}) do professionOfSpell[recipe[SPELL]] = recipe[PROF] end
    end
    local votes, best = {}, nil
    for _, spell in ipairs(spells) do
        local prof = professionOfSpell[spell]
        if prof then
            votes[prof] = (votes[prof] or 0) + 1
            if not best or votes[prof] > votes[best] then best = prof end
        end
    end
    return best and Professions()[best] or nil
end

local function Usable(name)
    return type(name) == "string" and name ~= "" and name ~= "UNKNOWN" and name or nil
end

-- The name of the open profession window. Forever doesn't always say (GetTradeSkillLine can be
-- empty there), so when the game's answer isn't a profession the tab knows, it's told by the
-- recipes in the window.
function Leveling.OpenProfessionName()
    local name
    if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
        local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        name = ok and type(info) == "table" and Usable(info.professionName) or nil
    end
    if not name and GetTradeSkillLine then name = Usable((GetTradeSkillLine())) end
    if not name and C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillLine then
        local id, lineName = C_TradeSkillUI.GetTradeSkillLine()
        name = Usable(lineName) or SKILL_LINES[id]
    end
    if not name and GetCraftDisplaySkillLine then name = Usable((GetCraftDisplaySkillLine())) end
    local listed = false
    for _, known in ipairs(Professions()) do if known == name then listed = true end end
    if not listed and not (name and GATHERING_NAMES[name]) then
        name = Leveling.ProfessionOfSpells(OpenWindowSpells()) or name
    end
    return name
end

function Leveling.Side()
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    return faction == "Alliance" and "A" or faction == "Horde" and "H" or nil
end

-- ---- The tab ----
-- Layout, top to bottom, each line one row high so nothing can overlap:
--   profession switcher | two options | Plan / Shopping list + total | summary | notice |
--   ROWS rows | page count and scroll arrows. Long text is cut to its row; hovering shows all of it.
local panel, lines, rows, offset = nil, {}, {}, 0
-- Which game windows are open: vendor, auction house, profession window.
local where = { merchant = false, auction = false, tradeSkill = false, trainer = false }

-- The item a row can look up on the auction house: a material, or a recipe sold there.
local function RowItem(row)
    if not row then return nil end
    if row.part then return row.part.id, row.part.count * row.partOf.crafts end
    if row.buy then return row.buy.id, row.buy.count end
    if row.learn and (row.learn.recipe[RECIPE_ITEM] or 0) > 0 then return row.learn.recipe[RECIPE_ITEM], 1 end
end
local current = {}
local VIEW_PLAN, VIEW_SHOP = "plan", "shopping"

local COLORS = { orange = "|cffff8040", yellow = "|cffffff00", green = "|cff40c040", gray = "|cff808080" }
-- Where a material comes from, short and in its own color (the user's choice): AH orange, Vendor blue.
local SOURCE_WORDS = { vendor = "|cff59b3ffVendor|r", auction = "|cffff9933AH|r", crafted = "|cffccccccCraft it yourself|r" }
Leveling.SOURCE_WORDS = SOURCE_WORDS
local KIND_WORDS = { known = "|cff40ff40You know it|r", starter = "Comes with the profession", trainer = "Trainer",
    vendor = "Recipe from a " .. SOURCE_WORDS.vendor, auction = "Recipe on the " .. SOURCE_WORDS.auction }

local function Money(copper)
    return DufforthTweaksHelperDE and DufforthTweaksHelperDE.Money and DufforthTweaksHelperDE.Money(copper) or tostring(copper)
end

local function SignedMoney(copper)
    if copper < 0 then return "|cff40ff40+" .. Money(-copper) .. "|r" end
    return Money(copper)
end

local function ItemIcon(id)
    return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id)) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- The game only knows an item's name once it has loaded it. Until then ask for it; the
-- watcher below redraws when it arrives (GET_ITEM_INFO_RECEIVED).
local waitingForNames = false

local function ItemName(id)
    local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (GetItemInfo and GetItemInfo(id))
    if name then return name end
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    waitingForNames = true
    return DufforthTweaksHelperDE and DufforthTweaksHelperDE.MaterialName and DufforthTweaksHelperDE.MaterialName(id) or ("Item " .. id)
end

local function BagCount(id)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) or 0 end
    return GetItemCount and GetItemCount(id) or 0
end

local function PlaceText(place)
    local npc = place.npc
    local where = npc[4] ~= "" and npc[4] or "?"
    -- Whole numbers only: the game's string.format errors on %d with a decimal like 63.1.
    if npc[5] then where = string.format("%s %d, %d", where, math.floor(npc[5] + 0.5), math.floor(npc[6] + 0.5)) end
    return npc[1], where
end

-- Places in the order to suggest them: the NPC you're talking to (or targeting), then ones in your
-- zone, then the rest (capitals first, as sorted). The user stood at Karn Stonehoof (Thunder Bluff)
-- while the plan named a trainer in Undercity (2026-11-12).
function Leveling.Nearest(places, here, talkingTo)
    local out, used = {}, {}
    local function take(test)
        for i, p in ipairs(places or {}) do
            if not used[i] and test(p) then out[#out + 1] = p; used[i] = true end
        end
    end
    if talkingTo then take(function(p) return p.npc[1] == talkingTo end) end
    if here and here ~= "" then take(function(p) return p.npc[4] == here end) end
    take(function() return true end)
    return out
end

local function NearestPlaces(c)
    local talkingTo = UnitName and (UnitName("npc") or UnitName("target")) or nil
    local here = GetRealZoneText and GetRealZoneText() or ""
    return Leveling.Nearest(c.places, here, talkingTo)
end

local function LearnLine(c)
    if c.kind == "known" or c.kind == "starter" then return KIND_WORDS[c.kind] end
    local first = NearestPlaces(c)[1]
    local cost = Money(c.acquire)
    local name, where
    if first then name, where = PlaceText(first) end
    if c.kind == "trainer" then
        return first and string.format("Trainer %s, %s: %s", name, where, cost) or ("A trainer: " .. cost)
    end
    if c.kind == "vendor" and first then return string.format("Recipe from %s, %s: %s", name, where, cost) end
    return "Recipe on the " .. SOURCE_WORDS.auction .. ": " .. cost
end

-- What the list shows: plan steps, or recipes to learn then materials to buy.
local function ShoppingRows(plan)
    local out = {}
    for _, s in ipairs(plan.steps) do
        if s.learning > 0 then out[#out + 1] = { learn = s } end
    end
    for _, t in ipairs(Leveling.ShoppingList(plan)) do out[#out + 1] = { buy = t } end
    return out
end

local function AddPlaces(c)
    if c.kind == "auction" then GameTooltip:AddDoubleLine("    " .. SOURCE_WORDS.auction, Money(c.acquire), 0.8, 0.8, 0.8, 1, 1, 1) end
    for i, place in ipairs(NearestPlaces(c)) do
        if i > 4 then break end
        local name, where = PlaceText(place)
        local title = place.npc[2] ~= "" and (" <" .. place.npc[2] .. ">") or ""
        GameTooltip:AddDoubleLine("    " .. name .. title .. ", " .. where, Money(place.cost), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    if c.kind == "trainer" and not (c.places and c.places[1]) then GameTooltip:AddLine("    A " .. (current.chosen and current.chosen.name or "profession") .. " trainer", 0.8, 0.8, 0.8) end
    GameTooltip:AddLine("Trainer and vendor places are Classic estimates.", 0.6, 0.6, 0.6)
end

local function ShowRowTooltip(line)
    local row = line.row
    if not row then return end
    GameTooltip:SetOwner(line, "ANCHOR_RIGHT")
    if row.buy then
        local t = row.buy
        if GameTooltip.SetHyperlink then GameTooltip:SetHyperlink("item:" .. t.id) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Needed for this plan", tostring(t.count), 0.45, 0.8, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Cheapest from", SOURCE_WORDS[t.source] or "?", 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Each", Money(t.each or 0), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("All of them", Money((t.each or 0) * t.count), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:Show()
        return
    end
    if row.part then
        local part, s = row.part, row.partOf
        local need = part.count * s.crafts
        if GameTooltip.SetHyperlink then GameTooltip:SetHyperlink("item:" .. part.id) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format("For %s, skill %d to %d", s.recipe[NAME], s.from, s.to), 0.45, 0.8, 1, true)
        GameTooltip:AddDoubleLine("Needed", string.format("%d (%d a craft x %d crafts)", need, part.count, s.crafts), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("In your bags", tostring(BagCount(part.id)), 0.8, 0.8, 0.8, 1, 1, 1)
        if row.have then GameTooltip:AddDoubleLine("Counted for this step", string.format("%d/%d", row.have, row.need), 0.8, 0.8, 0.8, 1, 1, 1) end
        if row.have and row.have < BagCount(part.id) then GameTooltip:AddLine("The rest goes to later steps.", 0.6, 0.6, 0.6) end
        if row.have and row.have < row.need and BagCount(part.id) > row.have then GameTooltip:AddLine("Earlier steps use the rest of your bags.", 0.6, 0.6, 0.6) end
        GameTooltip:AddDoubleLine("Cheapest from", SOURCE_WORDS[part.source] or "?", 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Each", Money(part.each or 0), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("All of them", Money((part.each or 0) * need), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:Show()
        return
    end
    local s = row.learn or row.step
    local r, c = s.recipe, s.candidate
    if GameTooltip.SetHyperlink then GameTooltip:SetHyperlink("item:" .. r[PRODUCT]) end
    GameTooltip:AddLine(" ")
    if row.learn then
        GameTooltip:AddLine("Learn " .. r[NAME] .. " for skill " .. s.from .. " to " .. s.to, 0.45, 0.8, 1, true)
        AddPlaces(c)
        GameTooltip:Show()
        return
    end
    GameTooltip:AddLine(string.format("Skill %d to %d: about %d crafts of %s", s.from, s.to, s.crafts, r[NAME]), 0.45, 0.8, 1, true)
    GameTooltip:AddLine(string.format("|cffff8040Orange|r to %d, |cffffff00yellow|r to %d, |cff40c040green|r to %d, |cff808080gray|r from %d",
        r[YELLOW], Leveling.Green(r), r[GRAY], r[GRAY]), 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine(string.format("Chance of a point at %d: %d%%", s.from, math.floor(s.chance * 100 + 0.5)), 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Materials for one craft", 0.45, 0.8, 1)
    for _, part in ipairs(c.parts) do
        GameTooltip:AddDoubleLine(string.format("    %dx %s (%s)", part.count, ItemName(part.id), SOURCE_WORDS[part.source] or "?"),
            Money(part.each * part.count), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    GameTooltip:AddLine("This step", 0.45, 0.8, 1)
    GameTooltip:AddDoubleLine("    Materials", Money(s.materials), 0.8, 0.8, 0.8, 1, 1, 1)
    if s.back > 0 then GameTooltip:AddDoubleLine("    Selling what you make (up to 80% back)", "-" .. Money(s.back), 0.8, 0.8, 0.8, 0.4, 1, 0.4) end
    if s.learning > 0 then GameTooltip:AddDoubleLine("    Learning it", Money(s.learning), 0.8, 0.8, 0.8, 1, 1, 1) end
    GameTooltip:AddDoubleLine("    Total", SignedMoney(s.cost), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddLine("How to learn", 0.45, 0.8, 1)
    if c.kind == "known" or c.kind == "starter" then
        GameTooltip:AddLine("    " .. KIND_WORDS[c.kind], 0.8, 0.8, 0.8)
    else
        AddPlaces(c)
    end
    GameTooltip:Show()
end

local function Draw()
    local shopping = DB().view == VIEW_SHOP
    for i, line in ipairs(lines) do
        local row = rows[i + offset]
        line.row = row
        line:SetShown(row ~= nil)
        -- Materials sit indented under their step, with a smaller icon.
        local indent = row and row.part and true or false
        line.icon:ClearAllPoints()
        line.icon:SetPoint("LEFT", indent and 26 or 2, 0)
        line.icon:SetSize(indent and 18 or 26, indent and 18 or 26)
        local textLeft = (indent and 26 or 2) + (indent and 18 or 26) + 6
        line.name:ClearAllPoints(); line.name:SetPoint("TOPLEFT", textLeft, -3)
        line.sub:ClearAllPoints(); line.sub:SetPoint("BOTTOMLEFT", textLeft, 4)
        local id = RowItem(row)
        local searchable = id ~= nil and (where.auction or (where.merchant and current.merchant and current.merchant[id] ~= nil)) or false
        local craft = row and row.craft
        if craft then
            line.rowButton:SetText(craft.label)
            line.rowButton:SetEnabled(craft.enabled and craft.run ~= nil)
        elseif searchable then
            line.rowButton:SetText("Search")
            line.rowButton:SetEnabled(true)
        end
        searchable = searchable or craft ~= nil
        line.rowButton:SetShown(searchable)
        local right = searchable and -66 or -4
        line.cost:ClearAllPoints(); line.cost:SetPoint("TOPRIGHT", right, -3)
        line.detail:ClearAllPoints(); line.detail:SetPoint("BOTTOMRIGHT", right, 4)
        local textWidth = line.textWidth - (searchable and 62 or 0) - (indent and 24 or 0)
        line.name:SetWidth(textWidth); line.sub:SetWidth(textWidth)
        if row and row.part then
            local part, s = row.part, row.partOf
            local need, have = row.need, row.have
            line.icon:SetTexture(ItemIcon(part.id))
            line.name:SetText(string.format("|cffffffff%dx|r %s", need, ItemName(part.id)))
            line.sub:SetText(string.format("%d a craft, %s, %s each", part.count, SOURCE_WORDS[part.source] or "?", Money(part.each or 0)))
            line.cost:SetText(Money((part.each or 0) * need))
            line.detail:SetText(string.format(have >= need and "|cff40c040%d/%d|r" or "|cffffffff%d|r/%d", have, need))
        elseif row and row.buy then
            local t = row.buy
            line.icon:SetTexture(ItemIcon(t.id))
            line.name:SetText(string.format("|cffffffff%dx|r %s", t.count, ItemName(t.id)))
            line.sub:SetText(string.format("%s, %s each", SOURCE_WORDS[t.source] or "?", Money(t.each or 0)))
            line.cost:SetText(Money((t.each or 0) * t.count))
            line.detail:SetText("")
        elseif row and row.learn then
            local s = row.learn
            line.icon:SetTexture(ItemIcon(s.recipe[RECIPE_ITEM] > 0 and s.recipe[RECIPE_ITEM] or s.recipe[PRODUCT]))
            line.name:SetText("|cffffd100Learn|r " .. s.recipe[NAME])
            line.sub:SetText(LearnLine(s.candidate))
            line.cost:SetText(Money(s.learning))
            line.detail:SetText("")
        elseif row then
            local s, r = row.step, row.step.recipe
            line.icon:SetTexture(ItemIcon(r[PRODUCT]))
            line.name:SetText(string.format("|cffbbbbbb%d-%d|r  %s%s|r", s.from, s.to, COLORS[s.color], r[NAME]))
            line.sub:SetText(string.format("|cffffffff%d crafts.|r %s", s.crafts, LearnLine(s.candidate)))
            line.cost:SetText(SignedMoney(s.cost))
            line.detail:SetText(SignedMoney(math.floor(s.cost / math.max(1, s.to - s.from))) .. " a point")
        end
    end
    local last = math.min(offset + #lines, #rows)
    panel.pageText:SetText(#rows > #lines and string.format("%d-%d of %d", offset + 1, last, #rows) or "")
    panel.up:SetEnabled(offset > 0)
    panel.down:SetEnabled(last < #rows)
    panel.planButton:SetEnabled(shopping)
    panel.shopButton:SetEnabled(not shopping)
    local action = current.action
    panel.action:SetShown(action ~= nil and action.label ~= nil)
    if action and action.label then
        panel.action:SetText(action.label)
        panel.action:SetEnabled(action.enabled and action.run ~= nil)
    end
end

local function Scroll(by)
    offset = math.max(0, math.min(offset + by, #rows - #lines))
    Draw()
end

local function Market()
    return DufforthTweaksHelper and DufforthTweaksHelper.MarketName and DufforthTweaksHelper.MarketName() or ""
end

local GATHERING = GATHERING_NAMES -- levels by gathering, not crafting

-- ---- Where you are: vendor, auction house, profession window ----
local busyUntil = 0
local STATUS_SECONDS = 8
Leveling.where = where

local function Now() return (GetTime and GetTime()) or 0 end

local Have = BagCount

local function ReadMerchant()
    local out = {}
    if not (GetMerchantNumItems and GetMerchantItemInfo) then return out end
    for i = 1, GetMerchantNumItems() or 0 do
        -- Newer clients return isPurchasable before isUsable and extendedCost; older ones don't.
        local r = { GetMerchantItemInfo(i) }
        local extended = r[8]
        if extended == nil then extended = r[7] end
        local id = GetMerchantItemID and GetMerchantItemID(i)
        if not id and GetMerchantItemLink then id = tonumber(string.match(GetMerchantItemLink(i) or "", "item:(%d+)")) end
        if id and type(r[3]) == "number" and r[3] > 0 and extended ~= true and r[6] ~= false and not out[id] then
            out[id] = { index = i, price = r[3], bundle = r[4] or 1, available = r[5] or -1 }
        end
    end
    return out
end

-- Buys the list, stopping when your money runs out. Returns copper spent and whether money ran short.
local function BuyFromMerchant(buys)
    local money = GetMoney and GetMoney() or math.huge
    local spent, short = 0, false
    for _, b in ipairs(buys) do
        local purchases = b.purchases
        if b.price > 0 then purchases = math.min(purchases, math.floor((money - spent) / b.price)) end
        if purchases < b.purchases then short = true end
        if purchases > 0 then
            if b.bundle > 1 then
                for _ = 1, purchases do BuyMerchantItem(b.index) end
            else
                local stack = math.max(1, (GetMerchantItemMaxStack and GetMerchantItemMaxStack(b.index)) or 20)
                local left = purchases
                while left > 0 do
                    local n = math.min(left, stack)
                    BuyMerchantItem(b.index, n)
                    left = left - n
                end
            end
            spent = spent + purchases * b.price
        end
    end
    return spent, short
end

-- Opens one item in the game's own auction house, so you buy with the game's buttons. By item ID
-- first (its own page, never a look-alike name), else by typing its name into the search box.
-- Returns true, or nil and why not.
local function SearchAuctionHouse(id)
    local frame = AuctionHouseFrame
    local AH = C_AuctionHouse
    local key = AH and AH.MakeItemKey and AH.MakeItemKey(id)
    if frame and key and frame.SelectBrowseResult and AH.GetItemKeyInfo and AH.GetItemKeyInfo(key) then
        if pcall(frame.SelectBrowseResult, frame, { itemKey = key, minPrice = 0, totalQuantity = 0 }) then
            if AH.SendSearchQuery then
                local order = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0
                pcall(AH.SendSearchQuery, key, { { sortOrder = order, reverseSort = false } }, true)
            end
            return true
        end
    end
    local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (GetItemInfo and GetItemInfo(id))
    if not name then
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
        return nil, "The game is still loading this item. Click Search again in a moment."
    end
    if frame and frame.SearchBar then
        if frame.SetDisplayMode and AuctionHouseFrameDisplayMode and AuctionHouseFrameDisplayMode.Buy then
            pcall(frame.SetDisplayMode, frame, AuctionHouseFrameDisplayMode.Buy)
        end
        local bar = frame.SearchBar
        if bar.SetSearchText then bar:SetSearchText(name) elseif bar.SearchBox then bar.SearchBox:SetText(name) end
        if bar.StartSearch then bar:StartSearch(); return true end
    end
    if BrowseName and AuctionFrameBrowse_Search then
        BrowseName:SetText(name)
        AuctionFrameBrowse_Search()
        return true
    end
    return nil, "Couldn't reach the auction house search. Search for " .. name .. " by hand."
end

local function SpellOf(link)
    return link and tonumber(string.match(link, "enchant:(%d+)") or string.match(link, "spell:(%d+)"))
end

-- The recipe in the open profession window: { craft = function(count), available, once }.
local function FindOpenRecipe(spell, name)
    if GetNumTradeSkills and GetTradeSkillInfo and DoTradeSkill then
        for i = 1, GetNumTradeSkills() or 0 do
            local skillName, kind, available = GetTradeSkillInfo(i)
            if kind ~= "header" then
                local id = SpellOf(GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i))
                if id == spell or (not id and skillName == name) then
                    return { available = tonumber(available) or 0, source = "trade skill window", craft = function(n) DoTradeSkill(i, n) end }
                end
            end
        end
    end
    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.CraftRecipe then
        local info = C_TradeSkillUI.GetRecipeInfo(spell)
        if info and info.learned ~= false then
            return { available = tonumber(info.numAvailable) or 0, source = "profession window", craft = function(n) C_TradeSkillUI.CraftRecipe(spell, n) end }
        end
    end
    -- Enchanting's older Craft window makes one per click.
    if GetNumCrafts and GetCraftInfo and DoCraft then
        for i = 1, GetNumCrafts() or 0 do
            local craftName, _, kind, available = GetCraftInfo(i)
            if kind ~= "header" then
                local id = SpellOf((GetCraftRecipeLink and GetCraftRecipeLink(i)) or (GetCraftItemLink and GetCraftItemLink(i)))
                if id == spell or (not id and craftName == name) then
                    return { available = tonumber(available) or 0, source = "craft window", once = true, craft = function() DoCraft(i) end }
                end
            end
        end
    end
end

-- Free slots in your normal bags (not profession bags, which only take their own goods).
local function FreeSlots()
    local free, any = 0, false
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local n, family
        if C_Container and C_Container.GetContainerNumFreeSlots then n, family = C_Container.GetContainerNumFreeSlots(bag)
        elseif GetContainerNumFreeSlots then n, family = GetContainerNumFreeSlots(bag) end
        if n then any = true; if (family or 0) == 0 then free = free + n end end
    end
    return any and free or nil
end

local function StackSize(id)
    local size = C_Item and C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(id)
    if not size and GetItemInfo then size = select(8, GetItemInfo(id)) end
    return tonumber(size) or 1 -- unknown: count one per slot, the safe guess
end

local function Casting()
    return (UnitCastingInfo and UnitCastingInfo("player")) and true or false
end

-- Opens a row's item on the auction house and says how many to buy.
-- Turns the vendor window to the page with that item and lights up its slot for a few seconds.
local glow, glowTexture
local function ShowAtVendor(index)
    if not (MerchantFrame and MerchantFrame_Update) then return false end
    local per = MERCHANT_ITEMS_PER_PAGE or 10
    MerchantFrame.page = math.ceil(index / per)
    MerchantFrame_Update()
    local slot = _G["MerchantItem" .. ((index - 1) % per + 1)]
    local button = slot and (slot.ItemButton or _G["MerchantItem" .. ((index - 1) % per + 1) .. "ItemButton"]) or slot
    if button then
        glow = glow or CreateFrame("Frame")
        glow:SetParent(button); glow:ClearAllPoints(); glow:SetAllPoints(button)
        if glow.SetFrameLevel and button.GetFrameLevel then glow:SetFrameLevel((button:GetFrameLevel() or 0) + 5) end
        glowTexture = glowTexture or glow:CreateTexture(nil, "OVERLAY")
        glowTexture:SetTexture("Interface\\Buttons\\CheckButtonHilight"); glowTexture:SetBlendMode("ADD")
        glowTexture:SetAllPoints(glow)
        glow:Show()
        local shown = glow
        if C_Timer then C_Timer.After(5, function() shown:Hide() end) end
    end
    return true
end

-- At a vendor: finds the row's item in the vendor window. At the auction house: opens it there.
local function SearchRow(row)
    local id, need = RowItem(row)
    if not id then return end
    local missing = math.max(0, need - BagCount(id))
    if where.merchant then
        local m = (current.merchant or ReadMerchant())[id]
        if not m then
            current.status = { at = Now(), text = "|cffffd100This vendor doesn't sell " .. ItemName(id) .. ".|r" }
        else
            local unit = Money(math.floor(m.price / math.max(1, m.bundle) + 0.5))
            local shown = ShowAtVendor(m.index)
            current.status = { at = Now(), text = string.format("|cffffd100%s:|r %s each here, buy %d more%s.", ItemName(id), unit, missing,
                shown and " (lit up in the vendor window)" or "") }
        end
        Leveling.Refresh()
        return
    end
    if not where.auction then return end
    local ok, why = SearchAuctionHouse(id)
    if ok then
        current.status = { at = Now(), text = string.format("|cffffd100%s:|r buy %d more%s.", ItemName(id), missing,
            missing > 0 and "" or ", you already have enough") }
    else
        current.status = { at = Now(), text = "|cffff5555" .. why .. "|r" }
    end
    Leveling.Refresh()
end
Leveling.SearchRow = SearchRow
Leveling.SearchAuctionHouse = SearchAuctionHouse
function Leveling.Where() return where end

-- The one button that fits where you are: { label, enabled, notice, tip = { lines }, run }.
-- A vendor comes first, then the auction house, then your profession window.
local function BuildAction(plan)
    if not plan or #plan.steps == 0 then return nil end
    local busy = Now() < busyUntil
    if where.merchant then
        local buys, total = Leveling.VendorPlan(Leveling.ShoppingList(plan), Have, ReadMerchant())
        if #buys == 0 then
            return { label = "Buy", enabled = false, notice = "This vendor sells nothing you still need for the plan.",
                tip = { "This vendor sells nothing you still need for the plan, or sells it dearer than the list." } }
        end
        local tip = { "Buys what you still need from this vendor, minus what's in your bags:" }
        for _, b in ipairs(buys) do tip[#tip + 1] = { string.format("%dx %s", b.units, ItemName(b.id)), Money(b.cost) } end
        tip[#tip + 1] = { "Total", Money(total) }
        local short = GetMoney and GetMoney() < total
        if short then tip[#tip + 1] = "|cffff5555You don't have enough money for all of it: it buys in this order until it runs out.|r" end
        return {
            label = string.format("Buy %d items", #buys), enabled = not busy, tip = tip,
            notice = string.format("|cffffd100This vendor sells %d things you need: %s.|r Hover Buy for the list.", #buys, Money(total)),
            run = function()
                local spent, ranShort = BuyFromMerchant(buys)
                busyUntil = Now() + 2 -- until your bags update, so a second click can't buy twice
                return string.format("Bought for %s%s.", Money(spent), ranShort and ", then ran out of money" or "")
            end,
        }
    end
    if where.auction then return { notice = "Click Search on a material, or the row itself, to open it on the auction house." } end
    if where.tradeSkill then return { notice = "Click Craft on a step to craft it." } end
end

-- How many crafts your bags have materials for, from the recipe data (mats are id, count pairs).
local function CanMake(recipe)
    local mats, best = recipe[MATS] or {}, nil
    for i = 1, #mats - 1, 2 do
        local n = math.floor(BagCount(mats[i]) / math.max(1, mats[i + 1]))
        best = best and math.min(best, n) or n
    end
    return best or 0
end
Leveling.CanMake = CanMake

-- ---- Crafting progress: a bar with crafts done and time left ----
-- crafting = { spell, name, total, done, startedAt, firstAt, lastAt, endedAt, stopped }
local crafting
local CAST_GAP = 0.3 -- the short pause between two queued crafts
local SHOW_DONE_SECONDS, STALL_SECONDS = 5, 10

-- Share done (0-1) and seconds left. castStart/castEnd: the craft being cast now, if any.
-- Time per craft: the measured pace once two crafts finished, else this cast's length plus the gap.
function Leveling.CraftProgress(c, now, castStart, castEnd)
    local castLength = (castStart and castEnd and castEnd > castStart) and (castEnd - castStart) or nil
    local per = c.per or (castLength and castLength + CAST_GAP) or 3 + CAST_GAP
    local partial = castLength and math.max(0, math.min(1, (now - castStart) / castLength)) or 0
    if c.done >= c.total then partial = 0 end
    local fraction = math.min(1, (c.done + partial) / math.max(1, c.total))
    local left = math.max(0, (c.total - c.done - partial) * per)
    return fraction, left
end

-- 75 -> "1m 15s", 3700 -> "1h 1m".
function Leveling.Duration(seconds)
    seconds = math.floor(seconds + 0.5)
    if seconds < 60 then return seconds .. "s" end
    local m, sec = math.floor(seconds / 60), seconds % 60
    if m < 60 then return sec > 0 and (m .. "m " .. sec .. "s") or (m .. "m") end
    return math.floor(m / 60) .. "h " .. (m % 60) .. "m"
end

local function CastTimes()
    if not UnitCastingInfo then return nil end
    local _, _, _, startMS, endMS = UnitCastingInfo("player")
    if startMS and endMS then return startMS / 1000, endMS / 1000 end
end

-- Draws the bar over the notice line while crafting, and for a few seconds after.
local BAR_COLORS = { crafting = { 0.15, 0.55, 1 }, done = { 0.2, 0.8, 0.25 }, stopped = { 0.9, 0.25, 0.2 } }

local function ShowHeaderLines(show)
    panel.summary:SetShown(show); panel.notice:SetShown(show)
end

local function UpdateProgress()
    if not (panel and panel.progress) then return end
    local c, now = crafting, Now()
    if c and not c.endedAt then
        local castStart = CastTimes()
        -- The queue ended without telling us (out of materials, moved): stop after a quiet while.
        if not castStart and now - (c.lastAt or c.startedAt) > STALL_SECONDS then c.endedAt, c.stopped = now, true end
    end
    if c and c.endedAt and now - c.endedAt > SHOW_DONE_SECONDS then crafting, c = nil, nil end
    if not c then
        panel.progress:Hide()
        ShowHeaderLines(true)
        return
    end
    local castStart, castEnd = CastTimes()
    local fraction, left = Leveling.CraftProgress(c, now, castStart, castEnd)
    local bar = panel.progress
    bar:SetValue(fraction)
    local state = c.endedAt and (c.stopped and "stopped" or "done") or "crafting"
    bar:SetStatusBarColor(unpack(BAR_COLORS[state]))
    bar.count:SetText(string.format("%d / %d", c.done, c.total))
    if state == "crafting" then
        bar.label:SetText("Crafting " .. c.name)
        bar.timeLeft:SetText("about " .. Leveling.Duration(left) .. " left")
    elseif state == "done" then
        bar.label:SetText("Done: " .. c.name)
        bar.timeLeft:SetText(c.bagsFull and "|cffffd100bags full|r" or "")
    else
        bar.label:SetText("Stopped: " .. c.name)
        bar.timeLeft:SetText("")
    end
    -- Below the bar: when your bags will be full, if before the step is done.
    bar.note:SetText(c.bagsFull and string.format("Bags full after %d of the %d this step needs: make room to craft the rest.", c.total, c.wanted) or "")
    bar:Show()
    ShowHeaderLines(false)
end
Leveling.UpdateProgress = UpdateProgress

-- Spell events for the craft in progress. Returns true when it handled the event.
local function TrackCraft(event, spell)
    local c = crafting
    if not c or c.endedAt then return false end
    if spell and spell ~= c.spell then return false end
    local now = Now()
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        c.done = c.done + 1
        c.firstAt = c.firstAt or now
        c.lastAt = now
        if c.done >= 2 then c.per = (c.lastAt - c.firstAt) / (c.done - 1) end
        if c.done >= c.total then c.endedAt = now end
    elseif event == "UNIT_SPELLCAST_START" then
        c.lastAt = now
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
        c.endedAt, c.stopped = now, true
    end
    UpdateProgress()
    return true
end

-- The open trainer's entry for a recipe: { index, category = available | unavailable | used }, or nil.
-- One trainer entry: name and category (available / unavailable / used). Classic returns
-- (name, rank, category); Forever returns (name, category, icon), seen in the user's log
-- (2026-11-12: "Bronze Mace | available | 133483"), so the category is whichever value is one.
local CATEGORIES = { available = true, unavailable = true, used = true }
function Leveling.ServiceInfo(i)
    local name, second, third = GetTrainerServiceInfo(i)
    if CATEGORIES[second] then return name, second end
    return name, third
end

-- What the open trainer lists, for the Learn hover: "The trainer lists 12 spells: A, B, C...".
function Leveling.TrainerSummary()
    if not (GetNumTrainerServices and GetTrainerServiceInfo) then return "The game gave no trainer list to the addon." end
    local n, names = GetNumTrainerServices() or 0, {}
    for i = 1, math.min(n, 6) do
        local serviceName, category = Leveling.ServiceInfo(i)
        if serviceName then names[#names + 1] = serviceName .. (category and category ~= "available" and (" (" .. category .. ")") or "") end
    end
    return string.format("The trainer lists %d spell%s%s", n, n == 1 and "" or "s", #names > 0 and (": " .. table.concat(names, ", ") .. (n > 6 and "..." or "")) or ".")
end

function Leveling.FindTrainerService(name)
    if not (GetNumTrainerServices and GetTrainerServiceInfo and name) then return nil end
    local wanted = string.lower(name)
    for i = 1, GetNumTrainerServices() or 0 do
        local serviceName, category = Leveling.ServiceInfo(i)
        if serviceName and string.lower(serviceName) == wanted then return { index = i, category = category } end
    end
    return nil
end

-- The Craft button of one plan step: { label, enabled, tip = { lines }, run }. The label says
-- why it can't craft: Learn (unknown recipe), No mats, or plain Craft while the window is closed.
local function CraftState(step)
    local r, c = step.recipe, step.candidate
    local profession = current.chosen and current.chosen.name or "profession"
    if c.kind ~= "known" and c.kind ~= "starter" then
        -- A recipe item: Search finds it at the auction house, or at a vendor that sells it.
        local item = r[RECIPE_ITEM] or 0
        local soldHere = item > 0 and where.merchant and current.merchant and current.merchant[item] ~= nil
        if item > 0 and (where.auction or soldHere or c.kind == "auction") then
            local ready = where.auction or soldHere
            return {
                label = "Search", enabled = ready,
                tip = { "You don't know " .. r[NAME] .. " yet: it's learned from a recipe item.", LearnLine(c),
                    ready and "Search opens it so you can buy it." or "Open the auction house to search for it." },
                run = ready and function() SearchRow({ learn = step }) end or nil,
            }
        end
        if where.trainer and c.kind == "trainer" then
            local service = Leveling.FindTrainerService(r[NAME])
            if service and service.category == "available" then
                return {
                    label = "Learn", enabled = true,
                    tip = { "Learns " .. r[NAME] .. " from this trainer.", LearnLine(c) },
                    run = function()
                        BuyTrainerService(service.index)
                        -- Counted as known now, so the plan moves on without reopening your profession window.
                        DufforthTweaksHelperCrafting.Known().spells[r[SPELL]] = true
                        return "Learned " .. r[NAME] .. "."
                    end,
                }
            end
            if service and service.category == "used" then
                DufforthTweaksHelperCrafting.Known().spells[r[SPELL]] = true
                return { label = "Learn", enabled = false, tip = { "You already know " .. r[NAME] .. ". Open your profession window to update the plan." } }
            end
            if service then
                return { label = "Learn", enabled = false, tip = { "This trainer can't teach you " .. r[NAME] .. " yet: your skill or level is too low (the trainer marks it " .. tostring(service.category) .. ").", LearnLine(c) } }
            end
            return { label = "Learn", enabled = false, tip = { "This trainer doesn't teach " .. r[NAME] .. ". If the trainer list is filtered, show all.", LearnLine(c), Leveling.TrainerSummary() } }
        end
        local seen = c.kind == "trainer" and GetNumTrainerServices and (GetNumTrainerServices() or 0) > 0
        return { label = "Learn", enabled = false, tip = { "You don't know " .. r[NAME] .. " yet.", LearnLine(c),
            c.kind == "trainer" and "Talk to the trainer and this button learns it." or "This recipe isn't taught by a trainer.",
            seen and ("|cffff8040The addon didn't get the trainer-opened signal. " .. Leveling.TrainerSummary() .. "|r") or nil } }
    end
    if not where.tradeSkill then
        return { label = "Craft", enabled = false, tip = { string.format("Open your %s window to craft %s here.", profession, r[NAME]) } }
    end
    if Casting() then return { label = "Crafting", enabled = false, tip = { "Crafting now." } } end
    local found = FindOpenRecipe(r[SPELL], r[NAME])
    if not found then
        return { label = "Craft", enabled = false, tip = { r[NAME] .. " isn't in the open window. Open your " .. profession .. " window." } }
    end
    local bags = CanMake(r)
    local available = math.max(found.available, bags)
    local count = found.once and math.min(1, available) or Leveling.CraftCount(step, available)
    local why = string.format("Your bags have materials for %d; the %s says %d.", bags, found.source or "window", found.available)
    -- Bag space: each craft makes r[COUNT] of the product.
    local free, fits = FreeSlots(), nil
    if free then
        fits = Leveling.CraftsThatFit(free, StackSize(r[PRODUCT]), BagCount(r[PRODUCT]), r[COUNT])
        why = why .. string.format(" Your bags have %d free slots: room for at least %d crafts.", free, fits)
        if fits == 0 and count > 0 then
            return { label = "Bags full", enabled = false, tip = { "No room in your bags for " .. r[NAME] .. ". Sell, bank or destroy something, then craft.", why } }
        end
    end
    local wanted = count
    if fits and fits < count then count = fits end
    if count == 0 then
        return { label = "No mats", enabled = false, tip = { "You don't have the materials for one " .. r[NAME] .. ". The rows under this step say what's missing.", why } }
    end
    local tip = { string.format("Crafts %s %d times: this step needs about %d, your materials allow %d.", r[NAME], count, step.crafts, available), why }
    if count < wanted then tip[#tip + 1] = string.format("|cffff8040Your bags fill up after %d crafts: make room to craft the other %d.|r", count, wanted - count) end
    if found.once then tip = { "Crafts one " .. r[NAME] .. ". This window makes one per click.", why } end
    return {
        label = "Craft " .. count, enabled = Now() >= busyUntil, tip = tip,
        run = function()
            found.craft(count)
            crafting = { spell = r[SPELL], name = r[NAME], total = count, done = 0, startedAt = Now(), bagsFull = count < wanted, wanted = wanted }
            UpdateProgress()
            busyUntil = Now() + 1.5 -- until the craft starts, so a second click can't queue it twice
            return string.format("Crafting %s %d times. The plan updates as you skill up.", r[NAME], count)
        end,
    }
end

-- The button at the right of a row: Craft on a step, Search on a material.
local function RowButtonClick(row)
    if row and row.craft then
        local state = row.craft
        if not (state.enabled and state.run) then return end
        local ok, result = pcall(state.run)
        if not ok or result then -- Search sets its own message
            current.status = { at = Now(), text = ok and result or ("|cffff5555That didn't work: " .. tostring(result) .. "|r") }
        end
        Leveling.Refresh()
        return
    end
    SearchRow(row)
end

local function Choices(mine)
    local list = {}
    for i, name in ipairs(Professions()) do
        if mine[name] and not GATHERING[name] then list[#list + 1] = { name = name, index = i } end
    end
    return list
end

local RefreshNow

-- Any error shows in the tab instead of leaving it blank, so it can be reported.
function Leveling.Refresh()
    if not panel or not panel:IsVisible() then return end
    local ok, err = pcall(RefreshNow)
    if not ok then
        rows = {}
        pcall(Draw)
        panel.summary:SetText("")
        panel.notice:SetText("")
        panel.empty:SetText("|cffff5555The Leveling tab hit an error. Please send this text:|r\n" .. tostring(err))
    end
end

RefreshNow = function()
    local options = DB()
    local mine = Leveling.ReadProfessions()
    local list = Choices(mine)
    local chosen
    for _, p in ipairs(list) do if p.name == options.profession then chosen = p end end
    chosen = chosen or list[1]
    current = { list = list, chosen = chosen, notes = {}, status = current.status } -- a button's result stays until you leave
    local function Shown(frame) return frame and frame.IsShown and frame:IsShown() and true or false end
    if MerchantFrame and MerchantFrame.IsShown then where.merchant = Shown(MerchantFrame) end
    if AuctionHouseFrame and AuctionHouseFrame.IsShown then where.auction = Shown(AuctionHouseFrame) end
    -- TRAINER_SHOW / TRAINER_CLOSED decide; the frame can only add. Forever's trainer list may not be
    -- ClassTrainerFrame, and reading that hidden frame turned Learn off at the trainer (user, 2026-11-12:
    -- "I'm interacting with the NPC that teaches Bronze Mace and the Learn button is disabled").
    if ClassTrainerFrame and ClassTrainerFrame.IsShown and ClassTrainerFrame:IsShown() then where.trainer = true end
    local craftFrames = { TradeSkillFrame, ProfessionsFrame, CraftFrame }
    for _, f in ipairs(craftFrames) do if f and f.IsShown and f:IsShown() then where.tradeSkill = true end end
    current.merchant = where.merchant and ReadMerchant() or nil
    for _, box in ipairs(panel.boxes) do box:SetChecked(options[box.key] and true or false) end
    panel.prev:SetShown(#list > 1); panel.next:SetShown(#list > 1)
    rows = {} -- the scroll place stays: bag and skill updates redraw often
    current.action = nil
    panel.summary:SetText(""); panel.total:SetText(""); panel.notice:SetText(""); panel.empty:SetText("")
    if not chosen then
        panel.title:SetText("No crafting profession")
        panel.empty:SetText("Learn a crafting profession at a trainer, then open this tab. Mining levels by mining.")
        Draw()
        return
    end
    local skill = mine[chosen.name]
    panel.title:SetText(string.format("%s  |cffffffff%d / %d|r", chosen.name, skill.rank, skill.max))
    local market = Market()
    local prices = DufforthTweaksHelperPrices and DufforthTweaksHelperPrices[market]
    local known = DufforthTweaksHelperCrafting.Known()
    local plan = Leveling.Plan(chosen.index, skill.rank, skill.max, known, options, prices or {}, Leveling.Side())
    current.plan = plan

    local notes = current.notes
    if not prices then notes[#notes + 1] = "|cffff5555No prices for your market (" .. market .. "). Download the addon again from the Forever Prices page.|r" end
    if known.scanned[chosen.name] ~= true then notes[#notes + 1] = "|cffffd100Open your " .. chosen.name .. " window once so the plan knows your recipes.|r" end
    if skill.rank >= skill.max and skill.max < 300 then
        notes[#notes + 1] = string.format("|cffffd100You're at your cap. Train %s at a %s trainer to go past %d.|r", RANK_NAMES[skill.max] or "the next rank", chosen.name, skill.max)
    elseif plan.stoppedAt then
        notes[#notes + 1] = string.format("|cffffd100No recipe with prices gives points at %d. Try the options above.|r", plan.stoppedAt)
    elseif skill.max < 300 then
        notes[#notes + 1] = string.format("At %d, train %s to keep going.", skill.max, RANK_NAMES[skill.max] or "the next rank")
    end
    current.action = BuildAction(plan)
    if current.action and current.action.notice then table.insert(notes, 1, current.action.notice) end
    -- A button's result shows for a few seconds, then the line goes back to what's true now.
    if current.status and Now() - current.status.at < STATUS_SECONDS then table.insert(notes, 1, current.status.text) end
    panel.notice:SetText(notes[1] or "")
    panel.noticeHover:SetShown(#notes > 0)

    if #plan.steps == 0 then
        panel.empty:SetText(#notes > 0 and table.concat(notes, "\n\n") or "Nothing to plan.")
        Draw()
        return
    end
    panel.total:SetText("Total " .. SignedMoney(plan.total))
    if options.view == VIEW_SHOP then
        rows = ShoppingRows(plan)
        local buy = 0
        for _, row in ipairs(rows) do if row.buy then buy = buy + (row.buy.each or 0) * row.buy.count end end
        panel.summary:SetText(string.format("To %d: buy %s of materials%s", plan.reached, Money(buy),
            plan.learning > 0 and (", learn recipes for " .. Money(plan.learning)) or ""))
    else
        local left = {} -- what's still in your bags for the next steps
        for _, s in ipairs(plan.steps) do
            rows[#rows + 1] = { step = s, craft = CraftState(s) }
            for _, part in ipairs(s.candidate.parts) do
                local need = part.count * s.crafts
                if left[part.id] == nil then left[part.id] = BagCount(part.id) end
                local have = math.min(left[part.id], need)
                left[part.id] = left[part.id] - have
                rows[#rows + 1] = { part = part, partOf = s, have = have, need = need }
            end
        end
        panel.summary:SetText(string.format("To %d: about %d crafts in %d steps", plan.reached, plan.crafts, #plan.steps))
    end
    offset = math.max(0, math.min(offset, #rows - #lines))
    Draw()
end

local function ShowSummaryTooltip(owner)
    local plan = current.plan
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if plan and #plan.steps > 0 then
        GameTooltip:AddLine(string.format("%s to %d", current.chosen.name, plan.reached), 1, 0.82, 0)
        GameTooltip:AddDoubleLine("Crafts (about)", tostring(plan.crafts), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Materials", Money(plan.materials), 0.8, 0.8, 0.8, 1, 1, 1)
        if plan.learning > 0 then GameTooltip:AddDoubleLine("Learning recipes", Money(plan.learning), 0.8, 0.8, 0.8, 1, 1, 1) end
        if plan.resale > 0 then GameTooltip:AddDoubleLine("Selling what you make", "-" .. Money(plan.resale), 0.8, 0.8, 0.8, 0.4, 1, 0.4) end
        GameTooltip:AddDoubleLine("Total", SignedMoney(plan.total), 1, 0.82, 0, 1, 1, 1)
    end
    for _, note in ipairs(current.notes or {}) do GameTooltip:AddLine(note, 1, 1, 1, true) end
    GameTooltip:Show()
end

-- What the tab shows now: { plan, chosen, action, notes, status } (read by the tests).
function Leveling.Current() return current end

-- Opens the window on this tab's shopping list (/dth shopping).
function Leveling.ShowShopping()
    DB().view = VIEW_SHOP
    if DufforthTweaksHelperMenu_Toggle then DufforthTweaksHelperMenu_Toggle("leveling") end
    Leveling.Refresh()
end

local function SetView(view)
    DB().view = view
    offset = 0
    Leveling.Refresh()
end

local function Cycle(direction)
    local list = current.list or {}
    if #list < 2 then return end
    local at = 1
    for i, p in ipairs(list) do if current.chosen and p.name == current.chosen.name then at = i end end
    at = (at - 1 + direction) % #list + 1
    DB().profession = list[at].name
    offset = 0
    Leveling.Refresh()
end

local function Tip(frame, text)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Check(parent, x, y, key, text, tip)
    local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    box:SetSize(22, 22)
    box:SetPoint("TOPLEFT", x, y)
    box.key = key
    local label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", box, "RIGHT", 2, 0)
    label:SetText(text)
    box:SetScript("OnClick", function(self)
        DB()[key] = self:GetChecked() and true or false
        Leveling.Refresh()
    end)
    Tip(box, tip)
    return box
end

local function SmallButton(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 20)
    b:SetText(text)
    return b
end

local function OneLine(fontString, width)
    fontString:SetWidth(width)
    fontString:SetJustifyH("LEFT")
    if fontString.SetWordWrap then fontString:SetWordWrap(false) end
    if fontString.SetMaxLines then fontString:SetMaxLines(1) end
end

local ROWS_TOP = -112
Leveling.LAYOUT = { title = -2, options = -26, views = -52, summary = -78, notice = -94, rows = ROWS_TOP, rowHeight = ROW_HEIGHT }

-- Builds the tab inside `parent` (the window's Leveling tab).
function Leveling.BuildPanel(parent, width)
    panel = parent
    local L = Leveling.LAYOUT
    panel.prev = SmallButton(parent, "<", 24); panel.prev:SetPoint("TOPLEFT", 4, L.title)
    panel.prev:SetScript("OnClick", function() Cycle(-1) end)
    Tip(panel.prev, "Previous profession")
    panel.next = SmallButton(parent, ">", 24); panel.next:SetPoint("TOPRIGHT", -4, L.title)
    panel.next:SetScript("OnClick", function() Cycle(1) end)
    Tip(panel.next, "Next profession")
    panel.title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOP", 0, L.title - 4)

    panel.boxes = {
        Check(parent, 4, L.options, "unlearned", "Include recipes I don't know", "Also plans with recipes you'd still have to learn, when that's cheaper overall: from a trainer, a vendor or the auction house. Learning costs are in the total."),
        Check(parent, 220, L.options, "resale", "Count selling what I make", "Takes off what you get back by selling each crafted item, at the better of the auction house after the 5% cut or a vendor, up to 80% of its materials (not everything sells). Untick if what you make won't sell."),
    }

    panel.planButton = SmallButton(parent, "Plan", 56); panel.planButton:SetPoint("TOPLEFT", 6, L.views)
    panel.planButton:SetScript("OnClick", function() SetView(VIEW_PLAN) end)
    Tip(panel.planButton, "What to craft at each skill, cheapest per point.")
    panel.shopButton = SmallButton(parent, "Shopping list", 96); panel.shopButton:SetPoint("LEFT", panel.planButton, "RIGHT", 4, 0)
    panel.shopButton:SetScript("OnClick", function() SetView(VIEW_SHOP) end)
    Tip(panel.shopButton, "Everything to buy and learn for the whole plan, most expensive first. At a vendor, the auction house or your profession window, a button next to this buys, searches or crafts it.")
    -- One button for where you are: Buy at a vendor, Search next at the auction house, Craft at
    -- your profession window. Hidden anywhere else.
    panel.action = SmallButton(parent, "Craft", 116); panel.action:SetPoint("LEFT", panel.shopButton, "RIGHT", 8, 0)
    panel.action:Hide()
    panel.action:SetScript("OnClick", function()
        local action = current.action
        if not (action and action.enabled and action.run) then return end
        local ok, result = pcall(action.run)
        current.status = { at = Now(), text = ok and result or ("|cffff5555That didn't work: " .. tostring(result) .. "|r") }
        Leveling.Refresh()
    end)
    panel.action:SetScript("OnEnter", function(self)
        local action = current.action
        if not action then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(action.label, 1, 0.82, 0)
        for _, line in ipairs(action.tip or {}) do
            if type(line) == "table" then GameTooltip:AddDoubleLine(line[1], line[2], 0.8, 0.8, 0.8, 1, 1, 1)
            else GameTooltip:AddLine(line, 1, 1, 1, true) end
        end
        GameTooltip:Show()
    end)
    panel.action:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.total = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.total:SetPoint("TOPRIGHT", -8, L.views - 4); panel.total:SetJustifyH("RIGHT")

    panel.summary = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.summary:SetPoint("TOPLEFT", 8, L.summary); OneLine(panel.summary, width - 16)
    panel.notice = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.notice:SetPoint("TOPLEFT", 8, L.notice); OneLine(panel.notice, width - 16)
    -- Hovering the summary or notice shows the cost breakdown and every note in full.
    panel.noticeHover = CreateFrame("Frame", nil, parent)
    panel.noticeHover:SetPoint("TOPLEFT", 4, L.summary + 2); panel.noticeHover:SetSize(width - 8, 32)
    panel.noticeHover:EnableMouse(true)
    panel.noticeHover:SetScript("OnEnter", ShowSummaryTooltip)
    panel.noticeHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Crafting progress: a framed, colored bar in place of the summary and notice lines while a
    -- batch is crafting (blue), then green when done or red when stopped.
    local bar = CreateFrame("StatusBar", nil, parent)
    panel.progress = bar
    bar:SetPoint("TOPLEFT", 8, L.summary + 1); bar:SetSize(width - 16, 20)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(unpack(BAR_COLORS.crafting))
    bar:SetMinMaxValues(0, 1); bar:SetValue(0)
    local back = bar:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints(bar); back:SetColorTexture(0, 0, 0, 0.7)
    -- A thin gold frame so it stands apart from the rows and buttons.
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
        local edge = bar:CreateTexture(nil, "OVERLAY")
        edge:SetColorTexture(1, 0.82, 0, 0.9)
        edge:SetPoint(side[1], bar, side[1], 0, 0); edge:SetPoint(side[2], bar, side[2], 0, 0)
        if side[3] then edge:SetWidth(side[3]) else edge:SetHeight(side[4]) end
    end
    bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bar.label:SetPoint("LEFT", 6, 0); bar.label:SetJustifyH("LEFT"); OneLine(bar.label, width - 210)
    bar.count = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bar.count:SetPoint("RIGHT", -110, 0)
    bar.timeLeft = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.timeLeft:SetPoint("RIGHT", -6, 0); bar.timeLeft:SetJustifyH("RIGHT")
    bar.note = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.note:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -2); OneLine(bar.note, width - 16)
    local sinceDraw = 0
    bar:SetScript("OnUpdate", function(_, elapsed)
        sinceDraw = sinceDraw + (elapsed or 0)
        if sinceDraw >= 0.1 then sinceDraw = 0; UpdateProgress() end
    end)
    panel.progress:Hide()

    panel.empty = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.empty:SetPoint("TOPLEFT", 12, L.rows - 8); panel.empty:SetWidth(width - 24); panel.empty:SetJustifyH("LEFT")

    -- Rows fill the space down to the page bar.
    local height = parent.GetHeight and parent:GetHeight() or 0
    local count = height > 0 and math.floor((height + L.rows - 28) / ROW_HEIGHT) or VISIBLE_ROWS
    count = math.max(4, math.min(count, 12))
    for i = 1, count do
        local line = CreateFrame("Button", nil, parent)
        line:SetSize(width - 8, ROW_HEIGHT)
        line:SetPoint("TOPLEFT", 4, L.rows - (i - 1) * ROW_HEIGHT)
        line:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        line.icon = line:CreateTexture(nil, "ARTWORK")
        line.icon:SetSize(26, 26); line.icon:SetPoint("LEFT", 2, 0)
        line.cost = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        line.cost:SetPoint("TOPRIGHT", -4, -3); line.cost:SetJustifyH("RIGHT")
        line.detail = line:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        line.detail:SetPoint("BOTTOMRIGHT", -4, 4); line.detail:SetJustifyH("RIGHT")
        local thisLine = line
        line.rowButton = SmallButton(line, "Search", 58)
        line.rowButton:SetPoint("RIGHT", -4, 0)
        line.rowButton:Hide()
        if line.rowButton.SetMotionScriptsWhileDisabled then line.rowButton:SetMotionScriptsWhileDisabled(true) end
        line.rowButton:SetScript("OnClick", function() pcall(RowButtonClick, thisLine.row) end)
        line.rowButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local craft = thisLine.row and thisLine.row.craft
            if craft then
                GameTooltip:AddLine(craft.label, 1, 0.82, 0)
                for _, text in ipairs(craft.tip) do GameTooltip:AddLine(text, 1, 1, 1, true) end
            else
                GameTooltip:SetText(where.merchant and "Shows this item in the vendor window." or "Opens this item on the auction house. You buy with the game's own buttons.", 1, 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        line.rowButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
        line:SetScript("OnClick", function() pcall(SearchRow, thisLine.row) end)
        line.textWidth = width - 150
        line.name = line:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        line.name:SetPoint("TOPLEFT", 34, -3); OneLine(line.name, width - 150)
        line.sub = line:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        line.sub:SetPoint("BOTTOMLEFT", 34, 4); OneLine(line.sub, width - 150)
        line:SetScript("OnEnter", ShowRowTooltip)
        line:SetScript("OnLeave", function() GameTooltip:Hide() end)
        lines[i] = line
    end
    Leveling.LAYOUT.rowCount = count

    panel.up = DufforthTweaksHelper.ArrowButton(parent, "up", function() Scroll(-#lines) end)
    panel.up:SetPoint("BOTTOMRIGHT", -30, 2)
    panel.down = DufforthTweaksHelper.ArrowButton(parent, "down", function() Scroll(#lines) end)
    panel.down:SetPoint("LEFT", panel.up, "RIGHT", 4, 0)
    panel.pageText = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.pageText:SetPoint("RIGHT", panel.up, "LEFT", -6, 0); panel.pageText:SetJustifyH("RIGHT")
    -- Bottom left: opening this tab with your profession window (on by default).
    local auto = Check(parent, 4, 0, "openWithProfession", "Open with my profession window",
        "Opening a profession window (Leatherworking, Tailoring...) also opens this tab on that profession, and closing it closes this window again if it opened it. Hover a row for details; places are Classic estimates.")
    auto:ClearAllPoints(); auto:SetPoint("BOTTOMLEFT", 2, 2)
    panel.boxes[#panel.boxes + 1] = auto
    parent:EnableMouseWheel(true)
    parent:SetScript("OnMouseWheel", function(_, delta) Scroll(-delta) end)
    parent:HookScript("OnShow", Leveling.Refresh)
end

-- Opening a profession window shows that profession here.
local watcher = CreateFrame("Frame")
-- Unknown events are errors in some game versions (Forever has no CRAFT_SHOW): try each.
for _, event in ipairs({ "TRADE_SKILL_SHOW", "CRAFT_SHOW", "SKILL_LINES_CHANGED", "GET_ITEM_INFO_RECEIVED",
    "TRADE_SKILL_CLOSE", "CRAFT_CLOSE", "MERCHANT_SHOW", "MERCHANT_CLOSED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
    "TRAINER_SHOW", "TRAINER_CLOSED", "TRAINER_UPDATE",
    "BAG_UPDATE_DELAYED", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_FAILED" }) do
    pcall(watcher.RegisterEvent, watcher, event)
end
local redrawSoon, refreshSoon = false, false
local openedByProfession = false
-- Where-you-are events: which window opened or closed.
local PLACES = {
    MERCHANT_SHOW = { "merchant", true }, MERCHANT_CLOSED = { "merchant", false },
    AUCTION_HOUSE_SHOW = { "auction", true }, AUCTION_HOUSE_CLOSED = { "auction", false },
    TRADE_SKILL_SHOW = { "tradeSkill", true }, CRAFT_SHOW = { "tradeSkill", true },
    TRADE_SKILL_CLOSE = { "tradeSkill", false }, CRAFT_CLOSE = { "tradeSkill", false },
    TRAINER_SHOW = { "trainer", true }, TRAINER_CLOSED = { "trainer", false },
}
local function RefreshSoon(delay)
    if refreshSoon then return end
    refreshSoon = true
    local function go() refreshSoon = false; Leveling.Refresh() end
    if C_Timer then C_Timer.After(delay, go) else go() end
end
-- A profession window opened: show that profession here, and open this tab on it.
local function ProfessionShown()
    local name = Leveling.OpenProfessionName()
    if name then DB().profession = name end
    local plans = false
    for _, known in ipairs(Professions()) do if known == name and not GATHERING[name] then plans = true end end
    if plans and DB().openWithProfession and DufforthTweaksHelperMenu_Toggle then
        local menu = _G.DufforthTweaksHelperMenu
        if not (menu and menu.IsShown and menu:IsShown()) then openedByProfession = true end
        DufforthTweaksHelperMenu_Toggle("leveling")
    end
    RefreshSoon(0.1)
end

local function OnEvent(_, event, unit, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_FAILED" then
        if unit == "player" then TrackCraft(event, select(2, ...)) end
        return
    end
    if event == "UNIT_SPELLCAST_INTERRUPTED" and unit == "player" then TrackCraft(event, select(2, ...)) end
    local place = PLACES[event]
    if place then
        where[place[1]] = place[2]
        current.status = nil
        busyUntil = 0 -- a wait for one window doesn't block another
    end
    -- What a trainer shows, saved for diagnosis (DB().trainerSeen): the user saw Learn greyed at a
    -- profession trainer (2026-11-12) and the cause has to come from the game, not a guess.
    if event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
        local function save()
            local seen = { at = time and time() or 0, event = event, signal = where.trainer and true or false,
                classFrame = ClassTrainerFrame and ClassTrainerFrame.IsShown and ClassTrainerFrame:IsShown() and true or false,
                api = (GetNumTrainerServices and GetTrainerServiceInfo) and true or false, services = {} }
            if seen.api then
                seen.count = GetNumTrainerServices() or 0
                for i = 1, math.min(seen.count, 40) do
                    local name, sub, category = GetTrainerServiceInfo(i)
                    seen.services[#seen.services + 1] = tostring(name) .. " | " .. tostring(sub) .. " | " .. tostring(category)
                end
            end
            local skills = Leveling.ReadProfessions and Leveling.ReadProfessions() or {}
            local bs = skills.Blacksmithing
            seen.blacksmithing = bs and (bs.rank .. "/" .. bs.max) or "?"
            DB().trainerSeen = seen
        end
        pcall(save)
        if C_Timer then C_Timer.After(1, function() pcall(save) end) end -- the list can fill a moment later
    end
    if event == "BAG_UPDATE_DELAYED" or event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        if (event ~= "BAG_UPDATE_DELAYED" and unit ~= "player") then return end
        busyUntil = 0
        RefreshSoon(0.3) -- have/need counts follow your bags; does nothing while the tab is closed
        return
    end
    if event == "MERCHANT_CLOSED" or event == "AUCTION_HOUSE_CLOSED" or event == "TRADE_SKILL_CLOSE" or event == "CRAFT_CLOSE"
        or event == "MERCHANT_SHOW" or event == "AUCTION_HOUSE_SHOW"
        or event == "TRAINER_SHOW" or event == "TRAINER_CLOSED" or event == "TRAINER_UPDATE" then
        if (event == "TRADE_SKILL_CLOSE" or event == "CRAFT_CLOSE") and openedByProfession then
            -- It opened with the profession window, so it closes with it.
            openedByProfession = false
            local menu = _G.DufforthTweaksHelperMenu
            if menu and menu.Hide then menu:Hide() end
        end
        RefreshSoon(0.2)
        return
    end
    if event == "GET_ITEM_INFO_RECEIVED" then
        -- Many names arrive at once: redraw once, shortly after, and only while the tab is open.
        if waitingForNames and not redrawSoon and panel and panel:IsVisible() then
            redrawSoon = true
            local function redraw() redrawSoon = false; waitingForNames = false; pcall(Draw) end
            if C_Timer then C_Timer.After(0.2, redraw) else redraw() end
        end
        return
    end
    if event == "TRADE_SKILL_SHOW" or event == "CRAFT_SHOW" then
        if C_Timer then C_Timer.After(0.3, ProfessionShown) else ProfessionShown() end
        return
    end
    RefreshSoon(0.3)
end
watcher:SetScript("OnEvent", OnEvent)
Leveling.OnEvent = OnEvent
