-- Dufforth Tweaks Helper, class tab: consumables worth buying while you level, for your class.
--
-- Every buyable food buff, elixir, flask, scroll and potion (ConsumablesData.lua, read from the
-- game's spell tables) is scored for your class: each stat it gives times how much that stat helps
-- your class (rough leveling weights below). Buffs are compared by score per gold per hour, potions
-- by health, mana or rage per gold. Prices: the cheaper of the AH (bundled download) and a vendor.

local Cons = {}
DufforthTweaksHelperConsumables = Cons

-- Which buffs replace each other (Classic rules): one Well Fed food, one flask, one elixir or
-- scroll per stat (a stronger Strength elixir replaces a weaker one), and potions share one cooldown.
-- Buffs from different groups stack, so the "Use together" set takes the best of each.

-- How much one point of each effect helps a class while leveling (Strength = 1 for a warrior).
-- Rough, from how each class's damage and survival scale in Classic.
local WEIGHTS = {
    WARRIOR = { wdmg = 2, hit = 12, str = 1, agi = 0.5, sta = 0.3, ap = 0.5, crit = 12, armor = 0.02, hpmax = 0.03, all = 1.8 },
    ROGUE = { wdmg = 2, hit = 12, agi = 1, str = 0.5, sta = 0.3, ap = 0.5, crit = 12, armor = 0.01, hpmax = 0.03, all = 1.8 },
    HUNTER = { wdmg = 0.3, hit = 10, agi = 1, rap = 0.5, int = 0.2, sta = 0.3, ap = 0.1, crit = 12, hpmax = 0.03, all = 1.5 },
    PALADIN = { wdmg = 2, hit = 10, str = 1, ap = 0.5, int = 0.3, sta = 0.3, agi = 0.3, sp = 0.3, crit = 12, armor = 0.01, hpmax = 0.03, mp5 = 1, all = 1.8 },
    SHAMAN = { wdmg = 1.5, hit = 10, str = 0.8, ap = 0.4, int = 0.5, agi = 0.3, sp = 0.5, sta = 0.3, crit = 12, hpmax = 0.03, mp5 = 1, all = 2 },
    DRUID = { str = 0.6, agi = 0.6, int = 0.5, sp = 0.6, ap = 0.3, sta = 0.3, spi = 0.2, crit = 12, hpmax = 0.03, mp5 = 1, all = 2 },
    MAGE = { sp = 1, int = 0.6, spi = 0.3, sta = 0.3, scrit = 10, hpmax = 0.03, mp5 = 1.2, all = 1.2 },
    WARLOCK = { sp = 1, int = 0.5, sta = 0.4, spi = 0.3, scrit = 10, hpmax = 0.04, mp5 = 1, all = 1.2 },
    PRIEST = { sp = 1, int = 0.6, spi = 0.6, heal = 0.3, sta = 0.3, scrit = 10, hpmax = 0.03, mp5 = 1.2, all = 1.8 },
}
Cons.WEIGHTS = WEIGHTS
local NO_MANA = { WARRIOR = true, ROGUE = true }
local KEEP_NEAR = 0.6 -- "best value" must be at least this share of the strongest you can use
local PER_SECTION = 5
local PER_ELIXIR_SECTION = 8

local NAMES = { wdmg = "weapon damage", hit = "% hit", str = "Strength", agi = "Agility", sta = "Stamina", int = "Intellect", spi = "Spirit", all = "all stats",
    ap = "attack power", rap = "ranged attack power", sp = "spell damage", heal = "healing", crit = "% crit", scrit = "% spell crit",
    armor = "armor", mp5 = "mana every 5 sec", hpmax = "maximum health", hp = "health", mana = "mana", rage = "rage", xp = "% kill experience" }
local ORDER = { "wdmg", "str", "agi", "sta", "int", "spi", "all", "ap", "rap", "sp", "heal", "crit", "hit", "scrit", "armor", "hpmax", "mp5", "hp", "mana", "rage", "xp" }
Cons.SECTIONS = {
    { key = "food", title = "Food (Well Fed)" },
    { key = "elixir", title = "Elixirs, flasks and scrolls" },
    { key = "weapon", title = "Weapon stones and oils" },
    { key = "battle", title = "Potions for a fight" },
    { key = "hp", title = "Healing potions" },
    { key = "mana", title = "Mana potions" },
    { key = "rage", title = "Rage potions" },
}

local ID, NAME, KIND, LEVEL, SECONDS, VENDOR, EFFECTS, WEAPONS = 1, 2, 3, 4, 5, 6, 7, 8
-- Weapon subclasses (the game's numbers), for the stones' "sharp" and "blunt" weapon lists.
local WEAPON_NAMES = { [0] = "one-handed axes", [1] = "two-handed axes", [4] = "one-handed maces", [5] = "two-handed maces",
    [6] = "polearms", [7] = "one-handed swords", [8] = "two-handed swords", [10] = "staves", [13] = "fist weapons", [15] = "daggers" }

-- Can a stone or oil go on this weapon subclass? Unknown weapon or no list: yes.
function Cons.FitsWeapon(row, subclass)
    local mask = row[WEAPONS] or 0
    if mask == 0 or not subclass then return true end
    return math.floor(mask / 2 ^ subclass) % 2 == 1
end

function Cons.WeaponList(row)
    local mask, names = row[WEAPONS] or 0, {}
    if mask == 0 then return "any weapon" end
    for bit = 0, 20 do
        if WEAPON_NAMES[bit] and math.floor(mask / 2 ^ bit) % 2 == 1 then names[#names + 1] = WEAPON_NAMES[bit] end
    end
    return table.concat(names, ", ")
end

-- The buff group a consumable is in: items in the same group replace each other.
function Cons.Group(row)
    local kind = row[KIND]
    if kind == "food" then return "food" end
    if kind == "flask" then return "flask" end
    if kind == "potion" then return "potion" end
    if kind == "weapon" then return "weapon" end
    for _, key in ipairs(ORDER) do
        if row[EFFECTS][key] and key ~= "xp" then return "elixir:" .. key end
    end
    return "elixir:other"
end

-- Plain words for a group: "one Strength elixir or scroll at a time".
function Cons.GroupText(group)
    if group == "food" then return "one Well Fed food at a time" end
    if group == "flask" then return "one flask at a time" end
    if group == "potion" then return "potions share one cooldown" end
    if group == "weapon" then return "one per weapon; replaces poisons and Windfury" end
    local stat = group:match("^elixir:(.+)$")
    return "one " .. (NAMES[stat] or "such") .. " elixir or scroll at a time"
end

local function Money(copper)
    return DufforthTweaksHelperDE and DufforthTweaksHelperDE.Money and DufforthTweaksHelperDE.Money(copper) or tostring(copper)
end

-- "+20 Strength, +5% kill experience"
function Cons.Describe(effects)
    local parts = {}
    for _, key in ipairs(ORDER) do
        local v = effects[key]
        if v then
            local amount = (v % 1 == 0) and tostring(v) or string.format("%.1f", v)
            if key == "crit" or key == "scrit" or key == "xp" or key == "hit" then parts[#parts + 1] = "+" .. amount .. NAMES[key]
            elseif key == "hp" or key == "mana" or key == "rage" then parts[#parts + 1] = amount .. " " .. NAMES[key]
            else parts[#parts + 1] = "+" .. amount .. " " .. NAMES[key] end
        end
    end
    return table.concat(parts, ", ")
end

function Cons.Duration(seconds)
    if not seconds or seconds <= 0 then return "instant" end
    if seconds >= 3600 then return (seconds % 3600 == 0) and (seconds / 3600 .. " h") or string.format("%.1f h", seconds / 3600) end
    if seconds >= 60 then return math.floor(seconds / 60 + 0.5) .. " min" end
    return seconds .. " sec"
end

-- How much a buff helps this class: the sum of effect x weight (experience and restores aside).
function Cons.Power(effects, class)
    local w, total = WEIGHTS[class] or WEIGHTS.WARRIOR, 0
    for key, value in pairs(effects) do total = total + (w[key] or 0) * value end
    return total
end

-- Which section a consumable is in for this class, or nil if it doesn't help it.
-- weapon: your main-hand weapon subclass, so a weightstone isn't offered for a sword.
function Cons.Section(row, class, weapon)
    local e, kind = row[EFFECTS], row[KIND]
    if kind == "weapon" then
        return Cons.FitsWeapon(row, weapon) and Cons.Power(e, class) > 0 and "weapon" or nil
    end
    if kind == "potion" then
        if e.rage then return class == "WARRIOR" and "rage" or nil end
        if e.mana and not e.hp then return not NO_MANA[class] and "mana" or nil end
        if e.hp then return "hp" end
        return Cons.Power(e, class) > 0 and "battle" or nil
    end
    if Cons.Power(e, class) <= 0 then return nil end
    return kind == "food" and "food" or "elixir"
end

-- The cheaper of the AH and a vendor: price, "AH" or "Vendor". nil when neither has a price.
function Cons.Price(row, prices)
    local ah = prices and prices[row[ID]]
    local vendor = row[VENDOR] > 0 and row[VENDOR] or nil
    if vendor and (not ah or vendor <= ah) then return vendor, "vendor" end
    if ah then return ah, "auction" end
    return nil
end

-- The amount a potion restores, counted for this class (a mana user counts health and mana).
local function Restore(e, section)
    if section == "rage" then return e.rage or 0 end
    if section == "mana" then return e.mana or 0 end
    return e.hp or 0
end

-- { [section key] = { rows = { {row, price, source, power, value, badge}, ... } } } for a class and level.
-- power: what it gives you (buff score, or amount restored). value: power per gold (per gold per hour for buffs).
function Cons.Advice(data, class, level, prices, weapon)
    local out = {}
    for _, s in ipairs(Cons.SECTIONS) do out[s.key] = { rows = {}, unpriced = 0 } end
    for _, row in ipairs(data or {}) do
        local section = row[LEVEL] <= level and Cons.Section(row, class, weapon)
        if section then
            local price, source = Cons.Price(row, prices)
            local e = row[EFFECTS]
            local restore = section == "hp" or section == "mana" or section == "rage"
            local power = restore and Restore(e, section) or Cons.Power(e, class)
            if restore and section == "rage" and e.str then power = power + Cons.Power({ str = e.str }, class) * row[SECONDS] / 60 end
            local entry = { row = row, price = price, source = source, power = power }
            if price and price > 0 then
                -- Buffs: per hour they last. Potions: per use (one fight).
                local hours = (row[KIND] ~= "potion" and row[SECONDS] > 0) and row[SECONDS] / 3600 or 1
                entry.value = power * hours / (price / 10000)
                table.insert(out[section].rows, entry)
            else
                out[section].unpriced = out[section].unpriced + 1
            end
        end
    end
    for key, s in pairs(out) do
        -- Badges per buff group: the best value and the strongest of each group.
        local groups, strongestOf = {}, {}
        for _, e in ipairs(s.rows) do
            e.group = Cons.Group(e.row)
            groups[e.group] = groups[e.group] or {}
            table.insert(groups[e.group], e)
        end
        for group, list in pairs(groups) do
            local strongest, best = nil, nil
            for _, e in ipairs(list) do if not strongest or e.power > strongest.power then strongest = e end end
            for _, e in ipairs(list) do
                if e.power >= KEEP_NEAR * strongest.power and (not best or e.value > best.value) then best = e end
            end
            if best then best.badge = "best" end
            if strongest ~= best then strongest.badge = "strongest" end
            strongestOf[group] = strongest.power
        end
        local function strong(e) return e.power >= KEEP_NEAR * strongestOf[e.group] end
        -- Recommended first (best value first), then the strongest, then the rest; weak ones drop off.
        table.sort(s.rows, function(a, b)
            local ra = a.badge == "best" and 2 or a.badge == "strongest" and 1 or 0
            local rb = b.badge == "best" and 2 or b.badge == "strongest" and 1 or 0
            if ra ~= rb then return ra > rb end
            if strong(a) ~= strong(b) then return strong(a) end
            return a.value > b.value
        end)
        local limit = key == "elixir" and PER_ELIXIR_SECTION or PER_SECTION
        while #s.rows > limit do table.remove(s.rows) end
    end
    return out
end

-- What to use together: the recommended item of each group whose buffs stack (food, a flask,
-- up to 3 elixirs or scrolls for different stats), plus a healing potion and one more potion for
-- your class (potions share a cooldown, so these are for different moments).
local MAX_ELIXIRS = 3
function Cons.Kit(advice)
    local kit = {}
    local function bestOf(key)
        for _, e in ipairs(advice[key].rows) do if e.badge == "best" then return e end end
    end
    if bestOf("food") then kit[#kit + 1] = bestOf("food") end
    local elixirs = {}
    for _, e in ipairs(advice.elixir.rows) do if e.badge == "best" then elixirs[#elixirs + 1] = e end end
    table.sort(elixirs, function(a, b) return a.value > b.value end)
    local flask, count = false, 0
    for _, e in ipairs(elixirs) do
        if e.group == "flask" then
            if not flask then flask = true; kit[#kit + 1] = e end
        elseif count < MAX_ELIXIRS then
            count = count + 1; kit[#kit + 1] = e
        end
    end
    if bestOf("weapon") then kit[#kit + 1] = bestOf("weapon") end
    if bestOf("hp") then kit[#kit + 1] = bestOf("hp") end
    local other = bestOf("rage") or bestOf("mana") or bestOf("battle")
    if other then kit[#kit + 1] = other end
    return kit
end

-- ---- Well Fed reminder ----
-- Forever's Nutritious Food gives a stat and +5% kill experience while Well Fed (15 min). Out of
-- combat, when it's missing and a food that helps your class is in your bags, a button with that
-- food shows next to the warrior icon (or mid-screen): one click eats it.

-- The food in your bags that helps your class most: the data row, or nil. have(id) -> count.
function Cons.BestFoodInBags(data, class, level, have)
    local best, bestPower = nil, 0
    for _, row in ipairs(data or {}) do
        if row[KIND] == "food" and row[LEVEL] <= level and (have(row[ID]) or 0) > 0 then
            local power = Cons.Power(row[EFFECTS], class)
            if power > bestPower then best, bestPower = row, power end
        end
    end
    return best
end

-- s = { on, inCombat, dead, wellFed, eating, level, maxLevel }: should the reminder show?
function Cons.ShouldRemind(s)
    return s.on and not s.inCombat and not s.dead and not s.wellFed and not s.eating and s.level < (s.maxLevel or 60)
end

local function Options()
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    local o = DufforthTweaksHelperDB.consumables or {}
    DufforthTweaksHelperDB.consumables = o
    if o.foodReminder == nil then o.foodReminder = true end
    return o
end
Cons.Options = Options

-- Buff names on you, read only out of combat (in combat Forever hides auras from addons).
local function HasBuff(names)
    local ok, found = pcall(function()
        for i = 1, 40 do
            local name
            if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
                local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
                if not aura then return nil end
                name = aura.name
            elseif UnitBuff then
                name = UnitBuff("player", i)
                if not name then return nil end
            else
                return nil
            end
            if issecretvalue and issecretvalue(name) then name = nil end
            if name and names[name] then return name end
        end
    end)
    return ok and found or nil
end

-- Drag to move (user: "I cannot move the spell notification"); the spot is saved in DB[key].
local function Draggable(f, key, mouseButton)
    f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag(mouseButton or "LeftButton")
    f:SetScript("OnDragStart", function(self)
        if InCombatLockdown and InCombatLockdown() and self.IsProtected and self:IsProtected() then return end
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relative, x, y = self:GetPoint()
        DufforthTweaksHelperDB[key] = { point, relative, x, y }
    end)
    local p = DufforthTweaksHelperDB and DufforthTweaksHelperDB[key]
    if p then f:ClearAllPoints(); f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) end
end

local foodButton
local function FoodButton()
    if foodButton then return foodButton end
    local b = CreateFrame("Button", "DufforthTweaksHelperFoodButton", UIParent, "SecureActionButtonTemplate")
    b:SetSize(36, 36)
    local hint = _G.DufforthTweaksHelperWarriorHint
    if hint then b:SetPoint("RIGHT", hint, "LEFT", -10, 0) else b:SetPoint("CENTER", UIParent, "CENTER", -60, -160) end
    -- Left-click eats, right-drag moves (user: "when I'm trying to move the food reminder I'm using
    -- it": a left-button drag also clicked it). Only the left button has an action.
    b:RegisterForClicks("LeftButtonUp")
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    Draggable(b, "foodPoint", "RightButton")
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints()
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.label:SetPoint("TOP", b, "BOTTOM", 0, -2); b.label:SetWidth(140)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.food and GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.food[ID]) end
        GameTooltip:AddLine("Click to eat. Well Fed adds +5% kill experience on Forever and lasts 15 min. Right-drag to move it.", 0.45, 0.8, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    foodButton = b
    return b
end

local WELL_FED, EATING = { ["Well Fed"] = true }, { ["Food"] = true, ["Food & Drink"] = true, ["Nutritious Food"] = true }

function Cons.UpdateFoodReminder()
    if InCombatLockdown and InCombatLockdown() then return end -- a secure button can't change in combat
    local b = FoodButton()
    local class = (UnitClass and select(2, UnitClass("player"))) or "WARRIOR"
    local level = UnitLevel and UnitLevel("player") or 1
    local state = { on = Options().foodReminder, inCombat = UnitAffectingCombat and UnitAffectingCombat("player"),
        dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player"), level = level }
    local food
    if Cons.ShouldRemind(state) then
        state.wellFed, state.eating = HasBuff(WELL_FED), HasBuff(EATING)
        if Cons.ShouldRemind(state) then
            local have = function(id) return (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id)) or (GetItemCount and GetItemCount(id)) or 0 end
            food = Cons.BestFoodInBags(DufforthTweaksHelperConsumableData, class, level, have)
        end
    end
    b.food = food
    -- Saved for diagnosis (DufforthTweaksHelperDB.consumables.lastCheck).
    Options().lastCheck = { at = time and time() or 0, on = state.on and true or false, wellFed = state.wellFed or false,
        eating = state.eating or false, level = level, class = class, food = food and food[NAME] or "none in bags" }
    if food then
        b:SetAttribute("type1", "item")
        b:SetAttribute("item1", "item:" .. food[ID])
        b.icon:SetTexture((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(food[ID])) or (GetItemIcon and GetItemIcon(food[ID])) or "Interface\\Icons\\INV_Misc_Food_15")
        b.label:SetText("|cffffd100Eat:|r " .. food[NAME])
        b:Show()
    else
        b:Hide()
    end
end

local foodWatcher = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "BAG_UPDATE_DELAYED", "UNIT_AURA", "PLAYER_LEVEL_UP" }) do
    pcall(foodWatcher.RegisterEvent, foodWatcher, event)
end
pcall(foodWatcher.RegisterEvent, foodWatcher, "PLAYER_REGEN_DISABLED")
foodWatcher:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" and unit ~= "player" then return end
    if event == "PLAYER_REGEN_DISABLED" then
        if foodButton and not (InCombatLockdown and InCombatLockdown()) then foodButton:Hide() end
        return
    end
    pcall(Cons.UpdateFoodReminder)
end)

-- ---- Panel ----
local ROW_HEIGHT, TOP = 30, -40
local panel, lines, rows, offset = nil, {}, {}, 0
local SOURCE = { vendor = "|cff59b3ffVendor|r", auction = "|cffff9933AH|r" }
local BADGE = { best = "|cff9ad99aBest of its kind|r", strongest = "|cffffd100Strongest|r", kit = "|cff40ff40Recommended|r" }

local function PlayerClass()
    local name, token -- "x and f()" would keep only f's first value
    if UnitClass then name, token = UnitClass("player") end
    return token or "WARRIOR", name or "Warrior"
end

-- Your main-hand weapon's subclass (sword, mace...), or nil when unknown.
local function MainHand()
    local id = GetInventoryItemID and GetInventoryItemID("player", 16)
    if not id then return nil end
    local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not getInfo then return nil end
    local ok, _, _, _, _, _, classID, subclassID = pcall(getInfo, id)
    if ok and classID == 2 then return subclassID end
    return nil
end

local function Prices()
    local market = DufforthTweaksHelper and DufforthTweaksHelper.MarketName and DufforthTweaksHelper.MarketName() or ""
    return DufforthTweaksHelperPrices and DufforthTweaksHelperPrices[market] or {}
end

local function Icon(id)
    return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id)) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function AtAuction()
    local L = DufforthTweaksHelperLeveling
    return L and L.Where and L.Where().auction or false
end

-- Right-hand column: next to the Search button when it shows, at the edge otherwise. Name and
-- second line end where that column's text starts, so nothing overlaps.
local function PlaceRight(line, searching)
    local inset = searching and -66 or -4
    line.cost:ClearAllPoints(); line.cost:SetPoint("TOPRIGHT", inset, -3)
    line.detail:ClearAllPoints(); line.detail:SetPoint("BOTTOMRIGHT", inset, 4)
end

local function Draw()
    local auction = AtAuction()
    for i, line in ipairs(lines) do
        local r = rows[offset + i]
        line.row = r
        line:SetShown(r ~= nil)
        local searching = r ~= nil and not r.header and auction and true or false
        line.search:SetShown(searching)
        PlaceRight(line, searching)
        if r and r.header then
            line.icon:Hide(); line.cost:SetText(""); line.detail:SetText("")
            line.name:SetText("|cff73bfff" .. r.header .. "|r"); line.sub:SetText(r.note or "")
        elseif r then
            local item = r.row
            line.icon:Show(); line.icon:SetTexture(Icon(item[ID]))
            line.name:SetText(item[NAME])
            local timing = item[SECONDS] > 0 and (", " .. Cons.Duration(item[SECONDS])) or ""
            line.sub:SetText(Cons.Describe(item[EFFECTS]) .. timing .. (r.kit and "" or ("  |cff808080(" .. Cons.GroupText(Cons.Group(item)) .. ")|r")))
            line.cost:SetText(Money(r.price) .. " " .. (SOURCE[r.source] or ""))
            line.detail:SetText(BADGE[r.kit and "kit" or r.badge] or "")
        end
    end
    local pages = math.max(1, math.ceil(#rows / math.max(1, #lines)))
    panel.pageText:SetText(#rows > #lines and string.format("%d / %d", math.floor(offset / #lines) + 1, pages) or "")
end

local function Scroll(delta)
    offset = math.max(0, math.min(offset + delta, math.max(0, #rows - #lines)))
    Draw()
end

function Cons.Redraw() if panel then Draw() end end

function Cons.Refresh()
    if not panel then return end
    local class, className = PlayerClass()
    local level = UnitLevel and UnitLevel("player") or 1
    panel.title:SetText(string.format("Consumables for your %s, level %d", className, level))
    local advice = Cons.Advice(DufforthTweaksHelperConsumableData, class, level, Prices(), MainHand())
    rows = {}
    local kit = Cons.Kit(advice)
    if #kit > 0 then
        rows[#rows + 1] = { header = "Use together: these buffs stack", note = "One of each kind. Potions are for different moments: they share a cooldown." }
        for _, e in ipairs(kit) do
            local copy = {}
            for k, v in pairs(e) do copy[k] = v end
            copy.kit = true
            rows[#rows + 1] = copy
        end
    end
    for _, s in ipairs(Cons.SECTIONS) do
        local list = advice[s.key]
        if #list.rows > 0 then
            rows[#rows + 1] = { header = s.title, note = list.unpriced > 0 and string.format("%d more without a price", list.unpriced) or nil }
            for _, r in ipairs(list.rows) do rows[#rows + 1] = r end
        end
    end
    panel.empty:SetText(#rows == 0 and "No consumable with a price helps your class at your level yet. Prices come with the addon download." or "")
    offset = math.min(offset, math.max(0, #rows - #lines))
    Draw()
end

local function ShowRow(line)
    local r = line.row
    if not r or r.header then return end
    local item, class, className = r.row, PlayerClass()
    GameTooltip:SetOwner(line, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then GameTooltip:SetItemByID(item[ID]) else GameTooltip:SetText(item[NAME]) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(Cons.Describe(item[EFFECTS]) .. (item[SECONDS] > 0 and (" for " .. Cons.Duration(item[SECONDS])) or ""), 0.45, 0.8, 1, true)
    GameTooltip:AddDoubleLine("Price", Money(r.price) .. " " .. (SOURCE[r.source] or ""), 0.8, 0.8, 0.8, 1, 1, 1)
    local section = Cons.Section(item, class)
    if section == "hp" or section == "mana" or section == "rage" then
        GameTooltip:AddDoubleLine("Per gold", string.format("%d %s", math.floor(r.value + 0.5), NAMES[section]), 0.8, 0.8, 0.8, 1, 1, 1)
    else
        GameTooltip:AddDoubleLine("Worth to a " .. className, string.format("%.1f points", r.power), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine(item[KIND] == "potion" and "Points per gold per use" or "Points per gold per hour", string.format("%.0f", r.value), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddLine("Points: each stat times how much it helps your class (Strength counts 1 for a warrior). Rough leveling weights.", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:AddLine("Stacking: " .. Cons.GroupText(Cons.Group(item)) .. ". Different kinds stack.", 0.8, 0.8, 0.8, true)
    if item[KIND] == "weapon" then GameTooltip:AddLine("Goes on: " .. Cons.WeaponList(item) .. ".", 0.8, 0.8, 0.8, true) end
    if r.kit then GameTooltip:AddLine("Recommended: part of the set to use together, the most for your gold in its kind.", 0.25, 1, 0.25, true)
    elseif r.badge == "best" then GameTooltip:AddLine("Best of its kind: the most for your gold among the strong ones you can use. Not in the set above, because other kinds give more for the gold.", 0.6, 0.85, 0.6, true)
    elseif r.badge == "strongest" then GameTooltip:AddLine("Strongest you can use, but it costs more for what it gives.", 1, 0.82, 0, true) end
    if item[EFFECTS].xp then GameTooltip:AddLine("Forever's Well Fed food also adds kill experience while you level.", 0.6, 0.6, 0.6, true) end
    GameTooltip:Show()
end

-- At the auction house, a click opens the item there.
local function ClickRow(line)
    local r = line.row
    local L = DufforthTweaksHelperLeveling
    if not r or r.header or not (L and L.SearchAuctionHouse and L.Where and L.Where().auction) then return end
    L.SearchAuctionHouse(r.row[ID])
end

function Cons.BuildPanel(parent, width)
    panel = parent
    panel.title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", 8, -4)
    panel.legend = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.legend:SetPoint("TOPLEFT", 8, -22); panel.legend:SetWidth(width - 16); panel.legend:SetJustifyH("LEFT")
    panel.legend:SetText("Only what helps your class. |cff40ff40Recommended|r: the set to use together. Hover for why; at the AH, Search opens it.")
    panel.empty = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.empty:SetPoint("TOPLEFT", 12, TOP - 8); panel.empty:SetWidth(width - 24); panel.empty:SetJustifyH("LEFT")
    local height = parent.GetHeight and parent:GetHeight() or 0
    -- Rows fill the page down to the arrows.
    local count = height > 0 and math.floor((height + TOP - 20) / ROW_HEIGHT) or 13
    count = math.max(4, math.min(count, 20))
    for i = 1, count do
        local line = CreateFrame("Button", nil, parent)
        line:SetSize(width - 8, ROW_HEIGHT)
        line:SetPoint("TOPLEFT", 4, TOP - (i - 1) * ROW_HEIGHT)
        line:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        line.icon = line:CreateTexture(nil, "ARTWORK")
        line.icon:SetSize(24, 24); line.icon:SetPoint("LEFT", 2, 0)
        line.cost = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        line.cost:SetJustifyH("RIGHT")
        line.detail = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line.detail:SetJustifyH("RIGHT")
        PlaceRight(line, false)
        line.name = line:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        line.name:SetPoint("TOPLEFT", 32, -3); line.name:SetPoint("RIGHT", line.cost, "LEFT", -6, 0); line.name:SetJustifyH("LEFT")
        line.sub = line:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        line.sub:SetPoint("BOTTOMLEFT", 32, 4); line.sub:SetPoint("RIGHT", line.detail, "LEFT", -6, 0); line.sub:SetJustifyH("LEFT")
        for _, f in ipairs({ line.name, line.sub }) do if f.SetWordWrap then f:SetWordWrap(false) end end
        -- At the auction house: Search opens this item there, and you buy with the game's buttons.
        local thisLine = line
        line.search = CreateFrame("Button", nil, line, "UIPanelButtonTemplate")
        line.search:SetSize(58, 20); line.search:SetPoint("RIGHT", -4, 0); line.search:SetText("Search")
        line.search:SetScript("OnClick", function() pcall(ClickRow, thisLine) end)
        line.search:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Opens this item on the auction house. You buy with the game's own buttons.", 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        line.search:SetScript("OnLeave", function() GameTooltip:Hide() end)
        line.search:Hide()
        line:SetScript("OnEnter", ShowRow)
        line:SetScript("OnLeave", function() GameTooltip:Hide() end)
        line:SetScript("OnClick", ClickRow)
        lines[i] = line
    end
    panel.up = DufforthTweaksHelper.ArrowButton(parent, "up", function() Scroll(-#lines) end)
    panel.up:SetPoint("BOTTOMRIGHT", -30, 2)
    panel.down = DufforthTweaksHelper.ArrowButton(parent, "down", function() Scroll(#lines) end)
    panel.down:SetPoint("LEFT", panel.up, "RIGHT", 4, 0)
    panel.pageText = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.pageText:SetPoint("RIGHT", panel.up, "LEFT", -6, 0); panel.pageText:SetJustifyH("RIGHT")
    -- Bottom left: the eat reminder (on by default).
    local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    box:SetSize(22, 22); box:SetPoint("BOTTOMLEFT", 2, 2)
    box.label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    box.label:SetPoint("LEFT", box, "RIGHT", 2, 0); box.label:SetText("Remind me to eat (Well Fed: +5% XP)")
    box:SetChecked(Options().foodReminder)
    box:SetScript("OnClick", function(self) Options().foodReminder = self:GetChecked() and true or false; pcall(Cons.UpdateFoodReminder) end)
    box:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Out of combat, when you aren't Well Fed, a button shows your best food in your bags for your class. One click eats it.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.foodBox = box
    parent:EnableMouseWheel(true)
    parent:SetScript("OnMouseWheel", function(_, delta) Scroll(-delta) end)
    parent:HookScript("OnShow", Cons.Refresh)
end
