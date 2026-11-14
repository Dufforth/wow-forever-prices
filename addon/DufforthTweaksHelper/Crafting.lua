-- Crafting tab: gear your professions can make that is worth crafting to disenchant.
--
-- Recipes come from the Forever Prices page's game data (Crafts.lua) and prices from the
-- download (Prices.lua). A material a vendor sells is always priced at the vendor's price;
-- otherwise the auction price, otherwise the cost of crafting it from its own materials.
-- The game only lists your recipes while a profession window is open, so open each
-- profession once and the tab marks which recipes you know.

local Crafting = {}
DufforthTweaksHelperCrafting = Crafting

local GEAR_PROFESSIONS = "Blacksmithing, Engineering, Leatherworking and Tailoring"
local ROW_HEIGHT, MAX_ROWS = 32, 16
-- Rows that fit the panel (the window can be short or tall); 9 when the height is unknown.
local panel
local function VisibleRows()
    local h = panel and panel.GetHeight and tonumber(panel:GetHeight()) or 0
    if h <= 0 then return 9 end
    return math.max(2, math.min(MAX_ROWS, math.floor((h - 80 - 22) / ROW_HEIGHT)))
end

local function DB()
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    local c = DufforthTweaksHelperDB.crafting or {}
    DufforthTweaksHelperDB.crafting = c
    c.known = c.known or {}
    if c.onlyKnown == nil then c.onlyKnown = true end
    if c.onlyProfit == nil then c.onlyProfit = true end
    if c.showHigher == nil then c.showHigher = false end
    return c
end
Crafting.Options = DB

local function Market()
    return DufforthTweaksHelper and DufforthTweaksHelper.MarketName and DufforthTweaksHelper.MarketName() or ""
end

-- Recipes this character knows: { spells = { [spell] = true }, scanned = { Tailoring = true } }.
function Crafting.Known(key)
    local all = DB().known
    key = key or (DufforthTweaksHelper.CharacterKey and DufforthTweaksHelper.CharacterKey() or "?")
    local mine = all[key] or { spells = {}, scanned = {} }
    all[key] = mine
    return mine
end

-- Price of one material and where it comes from: "vendor" (always first), "auction", "crafted", or nil.
function Crafting.MaterialCost(id, prices, seen)
    local vendor = DufforthTweaksHelperVendor or {}
    if vendor[id] then return vendor[id], "vendor" end
    if prices and prices[id] then return prices[id], "auction" end
    local craft = (DufforthTweaksHelperMaterialCrafts or {})[id]
    seen = seen or {}
    if craft and not seen[id] then
        seen[id] = true
        local total, list = 0, craft[2]
        for i = 1, #list, 2 do
            local each = Crafting.MaterialCost(list[i], prices, seen)
            if not each then
                seen[id] = nil
                return nil
            end
            total = total + each * list[i + 1]
        end
        seen[id] = nil
        return total / craft[1], "crafted"
    end
    return nil
end

-- One recipe row from Crafts.lua, with its cost, disenchant value and profit.
function Crafting.Evaluate(row, market, shipped)
    local prices = shipped and shipped[market] or {}
    local spell, profession, skill, product, count, quality, level, class, learn, name, materials =
        row[1], row[2], row[3], row[4], row[5], row[6], row[7], row[8], row[9], row[10], row[11]
    local parts, cost = {}, 0
    for i = 1, #materials, 2 do
        local each, source = Crafting.MaterialCost(materials[i], prices)
        parts[#parts + 1] = { id = materials[i], count = materials[i + 1], each = each, source = source }
        if each and cost then cost = cost + each * materials[i + 1] else cost = nil end
    end
    local value = DufforthTweaksHelperDE.ValueFor({ id = product, quality = quality, level = level, classID = class }, market, shipped)
    value = value and value * count
    return {
        spell = spell, profession = (DufforthTweaksHelperProfessions or {})[profession], skill = skill, product = product,
        count = count, quality = quality, level = level, learn = learn, name = name, parts = parts,
        cost = cost, value = value, profit = (value and cost) and (value - cost) or nil, ah = prices[product],
    }
end

-- Recipes for your professions, best profit first.
-- professions: { Tailoring = 150 }; known: Crafting.Known(); options: onlyKnown, onlyProfit, showHigher.
function Crafting.Recommend(professions, known, options, market, shipped)
    local names = DufforthTweaksHelperProfessions or {}
    local out = {}
    for _, row in ipairs(DufforthTweaksHelperCrafts or {}) do
        local profession = names[row[2]]
        local rank = professions and professions[profession]
        if rank then
            local isKnown = known.spells[row[1]] == true
            local scanned = known.scanned[profession] == true
            local allowed = not (options.onlyKnown and scanned and not isKnown)
            if allowed and not options.showHigher and row[3] > rank then allowed = false end
            if allowed then
                local result = Crafting.Evaluate(row, market, shipped)
                result.known, result.scanned, result.rank = isKnown, scanned, rank
                if result.profit and (result.profit > 0 or not options.onlyProfit) then out[#out + 1] = result end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.profit ~= b.profit then return a.profit > b.profit end
        return a.spell < b.spell
    end)
    return out
end

-- ---- Remember which recipes you know, while a profession window is open ----
local function SpellFromLink(link)
    return link and tonumber(string.match(link, "enchant:(%d+)") or string.match(link, "spell:(%d+)"))
end

function Crafting.ScanOpenProfession()
    local known = Crafting.Known()
    local profession = GetTradeSkillLine and GetTradeSkillLine()
    local found = 0
    if GetNumTradeSkills and GetTradeSkillInfo then
        for i = 1, GetNumTradeSkills() do
            local _, kind = GetTradeSkillInfo(i)
            if kind ~= "header" and GetTradeSkillRecipeLink then
                local spell = SpellFromLink(GetTradeSkillRecipeLink(i))
                if spell then known.spells[spell] = true; found = found + 1 end
            end
        end
    end
    if found == 0 and C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
        for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
            local info = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(id)
            if not info or info.learned then known.spells[id] = true; found = found + 1 end
        end
        if not profession and C_TradeSkillUI.GetTradeSkillLine then
            local _, name = C_TradeSkillUI.GetTradeSkillLine()
            profession = name
        end
    end
    -- Enchanting uses the older Craft window on Classic clients.
    if found == 0 and GetNumCrafts and (GetCraftRecipeLink or GetCraftItemLink) then
        for i = 1, GetNumCrafts() do
            local _, _, kind = GetCraftInfo(i)
            if kind ~= "header" then
                local spell = SpellFromLink((GetCraftRecipeLink and GetCraftRecipeLink(i)) or GetCraftItemLink(i))
                if spell then known.spells[spell] = true; found = found + 1 end
            end
        end
        if found > 0 and GetCraftDisplaySkillLine then profession = GetCraftDisplaySkillLine() end
    end
    if (not profession or profession == "UNKNOWN") and DufforthTweaksHelperLeveling and DufforthTweaksHelperLeveling.OpenProfessionName then
        profession = DufforthTweaksHelperLeveling.OpenProfessionName() -- Forever doesn't always name the window
    end
    if profession and found > 0 then known.scanned[profession] = true end
    if Crafting.Refresh then Crafting.Refresh() end
    return found
end

local watcher = CreateFrame("Frame")
-- An event this game version doesn't have is an error when registered (Forever has no
-- CRAFT_* events), and it would stop this file before the tab is defined. Try each one.
for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE" }) do
    pcall(watcher.RegisterEvent, watcher, event)
end
watcher:SetScript("OnEvent", function()
    if C_Timer then C_Timer.After(0.2, Crafting.ScanOpenProfession) else Crafting.ScanOpenProfession() end
end)

-- ---- The tab ----
local lines, rows, offset = {}, {}, 0

local function QualityColor(quality)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    return c and c.hex or "|cff1eff00"
end

local SOURCE_WORDS = { vendor = "vendor", auction = "auction", crafted = "you craft it" }

local function LearnText(result)
    if result.known then return "|cff40ff40you know it|r" end
    if result.learn == 0 then return "trainer" end
    if result.learn and result.learn > 0 then return "recipe item" end
    return "how to learn not known"
end

local function ShowRowTooltip(line)
    local r = line.result
    if not r then return end
    local Money = DufforthTweaksHelperDE.Money
    GameTooltip:SetOwner(line, "ANCHOR_RIGHT")
    if GameTooltip.SetHyperlink then GameTooltip:SetHyperlink("item:" .. r.product) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Profit if you disenchant it", (r.profit >= 0 and "|cff40ff40+" or "|cffff5555-") .. Money(math.abs(r.profit)) .. "|r", 0.45, 0.8, 1)
    GameTooltip:AddDoubleLine("    Disenchant value (average)", Money(r.value), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("    Materials cost", Money(r.cost), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddLine("Materials", 0.45, 0.8, 1)
    for _, part in ipairs(r.parts) do
        local name = DufforthTweaksHelperDE.MaterialName(part.id)
        GameTooltip:AddDoubleLine(string.format("    %dx %s |cff999999(%s)|r", part.count, name, SOURCE_WORDS[part.source] or "no price"),
            part.each and Money(part.each * part.count) or "no price", 0.8, 0.8, 0.8, 1, 1, 1)
    end
    local skill = r.skill > 0 and (r.profession .. " " .. r.skill) or (r.profession .. ", skill not known")
    GameTooltip:AddDoubleLine("Needs", skill, 0.45, 0.8, 1, 1, 1, 1)
    local learn = r.known and "You know it" or r.learn == 0 and "A profession trainer"
        or (r.learn and r.learn > 0) and DufforthTweaksHelperDE.MaterialName(r.learn) or "Not known; check Wowhead"
    GameTooltip:AddDoubleLine("Learn from", learn, 0.45, 0.8, 1, 1, 1, 1)
    if r.ah then GameTooltip:AddDoubleLine("Or sell it on the auction house", Money(r.ah * 0.95), 0.8, 0.8, 0.8, 1, 1, 1) end
    GameTooltip:Show()
end

local function Draw()
    for i, line in ipairs(lines) do
        local r = i <= VisibleRows() and rows[i + offset] or nil
        line.result = r
        line:SetShown(r ~= nil)
        if r then
            local Money = DufforthTweaksHelperDE.Money
            line.icon:SetTexture((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(r.product)) or (GetItemIcon and GetItemIcon(r.product)) or "Interface\\Icons\\INV_Misc_QuestionMark")
            line.name:SetText(QualityColor(r.quality) .. r.name .. "|r")
            line.sub:SetText(string.format("%s %s, %s", r.profession, r.skill > 0 and r.skill or "?", LearnText(r)))
            line.profit:SetText((r.profit >= 0 and "|cff40ff40+" or "|cffff5555-") .. Money(math.abs(r.profit)) .. "|r")
            line.detail:SetText("cost " .. Money(r.cost))
        end
    end
    panel.up:SetEnabled(offset > 0)
    panel.down:SetEnabled(offset + VisibleRows() < #rows)
end

function Crafting.Refresh()
    if not panel or not panel:IsVisible() then return end
    local options = DB()
    local professions = DufforthTweaksHelper.Professions and DufforthTweaksHelper.Professions() or nil
    local known = Crafting.Known()
    local market = Market()
    rows = Crafting.Recommend(professions or {}, known, options, market, DufforthTweaksHelperPrices)
    offset = math.max(0, math.min(offset, #rows - VisibleRows()))
    for _, box in ipairs(panel.boxes) do box:SetChecked(options[box.key] and true or false) end

    local mine, unchecked, crafting = {}, {}, false
    for name, rank in pairs(professions or {}) do
        mine[#mine + 1] = name .. " " .. rank
        for _, gear in ipairs({ "Blacksmithing", "Engineering", "Leatherworking", "Tailoring" }) do
            if gear == name then
                crafting = true
                if not known.scanned[name] then unchecked[#unchecked + 1] = name end
            end
        end
    end
    table.sort(mine)
    local text = "Your professions: " .. (#mine > 0 and table.concat(mine, ", ") or "none found")
    if #unchecked > 0 then
        table.sort(unchecked)
        text = text .. "\n|cffffd100Open your " .. table.concat(unchecked, " and ") .. " window once so this list knows your recipes.|r"
    end
    panel.status:SetText(text)

    local empty = ""
    if not professions then
        empty = "The game didn't share your professions. Open this tab again in a moment."
    elseif not crafting then
        empty = "None of your professions make gear that can be disenchanted. Those are " .. GEAR_PROFESSIONS .. "."
    elseif not (DufforthTweaksHelperPrices and DufforthTweaksHelperPrices[market]) then
        empty = "This download has no prices for your market (" .. market .. "). Download the addon again from the Forever Prices page."
    elseif #rows == 0 then
        empty = options.onlyProfit and "Nothing you can craft makes a profit when disenchanted right now. Untick \"Only profitable\" to see the rest."
            or "No recipes match. Try \"Show recipes above my skill\"."
    end
    panel.empty:SetText(empty)
    panel.count:SetText(#rows > 0 and string.format("%d recipes, best profit first", #rows) or "")
    Draw()
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
        offset = 0
        Crafting.Refresh()
    end)
    box:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tip, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return box
end

-- Builds the tab's content inside `parent` (the window's Crafting tab).
function Crafting.BuildPanel(parent, width)
    panel = parent
    panel.status = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.status:SetPoint("TOPLEFT", 6, -4); panel.status:SetWidth(width - 12); panel.status:SetJustifyH("LEFT")
    panel.boxes = {
        Check(parent, 4, -34, "onlyKnown", "Only recipes I know", "Hides recipes you don't know yet, once you've opened that profession's window. Untick to see what's worth learning."),
        Check(parent, 150, -34, "onlyProfit", "Only profitable", "Hides recipes whose materials cost more than the disenchant materials are worth."),
        Check(parent, 270, -34, "showHigher", "Above my skill", "Also shows recipes that need more skill than you have."),
    }
    panel.count = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.count:SetPoint("TOPLEFT", 8, -60)
    panel.up = DufforthTweaksHelper.ArrowButton(parent, "up", function() offset = math.max(0, offset - VisibleRows()); Draw() end)
    panel.up:SetPoint("TOPRIGHT", -30, -56)
    panel.down = DufforthTweaksHelper.ArrowButton(parent, "down", function() offset = math.min(offset + VisibleRows(), math.max(0, #rows - VisibleRows())); Draw() end)
    panel.down:SetPoint("LEFT", panel.up, "RIGHT", 4, 0)
    panel.empty = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.empty:SetPoint("TOPLEFT", 12, -100); panel.empty:SetWidth(width - 24); panel.empty:SetJustifyH("LEFT")

    for i = 1, MAX_ROWS do
        local line = CreateFrame("Button", nil, parent)
        line:SetSize(width - 8, ROW_HEIGHT)
        line:SetPoint("TOPLEFT", 4, -80 - (i - 1) * ROW_HEIGHT)
        line:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        line.icon = line:CreateTexture(nil, "ARTWORK")
        line.icon:SetSize(26, 26); line.icon:SetPoint("LEFT", 2, 0)
        line.name = line:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        line.name:SetPoint("TOPLEFT", line.icon, "TOPRIGHT", 6, 0); line.name:SetWidth(width - 140); line.name:SetJustifyH("LEFT")
        line.sub = line:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        line.sub:SetPoint("BOTTOMLEFT", line.icon, "BOTTOMRIGHT", 6, 0); line.sub:SetWidth(width - 140); line.sub:SetJustifyH("LEFT")
        line.profit = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        line.profit:SetPoint("TOPRIGHT", -4, -2); line.profit:SetJustifyH("RIGHT")
        line.detail = line:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        line.detail:SetPoint("BOTTOMRIGHT", -4, 3); line.detail:SetJustifyH("RIGHT")
        line:SetScript("OnEnter", ShowRowTooltip)
        line:SetScript("OnLeave", function() GameTooltip:Hide() end)
        line:EnableMouseWheel(true)
        line:SetScript("OnMouseWheel", function(_, delta)
            offset = math.max(0, math.min(offset - delta, #rows - VisibleRows()))
            Draw()
        end)
        lines[i] = line
    end
    local note = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("BOTTOMLEFT", 6, 4); note:SetWidth(width - 12); note:SetJustifyH("LEFT")
    note:SetText("Profit = average disenchant value minus materials. Vendor materials always use the vendor's price. Hover a row for details.")
    parent:HookScript("OnShow", Crafting.Refresh)
end
