-- Money tab (user, 2026-11-25: "is there any way to make easy money" / "Yes, add a Money tab"). Shows the best money
-- ideas for your realm and faction at the latest auction prices (MoneyData.lua, built by tools/build_addon_money.py
-- with tools/money_finder.py): vendor flips, underpriced listings, crafts that pay, and farming spots. At the auction
-- house, Search opens the item there; you buy with the game's own buttons. The addon never buys or sells.

local L = DufforthTweaksHelperL or setmetatable({}, { __index = function(_, k) return k end })
DufforthTweaksHelperMoney = DufforthTweaksHelperMoney or {}
local M = DufforthTweaksHelperMoney

M.VIEWS = {
    { key = "cheap", label = L["Underpriced"], tip = L["Listings well under their usual price, on items that sell every day: buy and post again."] },
    { key = "crafts", label = L["Crafts"], tip = L["Trainer and vendor recipes that sell for more than their materials cost."] },
    { key = "flips", label = L["Vendor flips"], tip = L["Listings cheaper than what a vendor pays: buy and sell to any vendor."] },
    { key = "farm", label = L["Farming"], tip = L["Open-world monsters whose drops are worth the most, at today's prices (30 s a kill)."] },
}
M.ROWS = 12

local function DB()
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    DufforthTweaksHelperDB.money = DufforthTweaksHelperDB.money or {}
    return DufforthTweaksHelperDB.money
end

function M.Gold(copper)
    copper = math.floor(copper or 0)
    if copper >= 10000 then return string.format("%.1fg", copper / 10000) end
    if copper >= 100 then return string.format("%ds", math.floor(copper / 100)) end
    return string.format("%dc", copper)
end

function M.Market()
    local name = DufforthTweaksHelper and DufforthTweaksHelper.MarketName and DufforthTweaksHelper.MarketName()
    local data = DufforthTweaksHelperMoneyData
    return name, data and data.markets and data.markets[name]
end

-- "3 hours ago" for the prices' time.
function M.Age(at, now)
    if not at or at == 0 then return L["unknown time"] end
    local hours = math.floor(((now or (time and time()) or at) - at) / 3600)
    if hours < 1 then return L["less than an hour ago"] end
    if hours < 48 then return string.format(L["%d hours ago"], hours) end
    return string.format(L["%d days ago"], math.floor(hours / 24))
end

-- Exact coins, "1g 23s 45c": a few copper matter when the whole gain is a few copper (user, 2026-11-27).
function M.Coins(copper)
    copper = math.floor(copper or 0)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

M.MIN_FLIP_EACH = 100 -- a vendor flip must make at least 1s an item (older price files had copper flips)

-- What each view is, in one line; the green number is named (user: "i dont understand this").
M.LEGENDS = {
    flips = L["Buy on the auction house, sell to any vendor. Green: profit per item."],
    cheap = L["Cheap listings that sell daily: buy, post again. Green: profit per item after the 5% cut."],
    crafts = L["Sells for more than its materials: craft and post. Green: profit per craft."],
    farm = L["Monsters with the most valuable drops. Green: gold an hour at 30 s a kill."],
}

-- One view's rows as { id (item to search, or nil), name, sub, value, each (copper), tip (lines) }.
function M.Rows(view, market)
    local out = {}
    local C = M.Coins
    for _, r in ipairs((market or {})[view] or {}) do
        if view == "flips" then
            local each = r[4] - r[3]
            if each >= M.MIN_FLIP_EACH then
                out[#out + 1] = { id = r[1], name = r[2], each = each, value = "+" .. C(each) .. L[" each"],
                    sub = string.format(L["buy at %s, a vendor pays %s; %d listed"], C(r[3]), C(r[4]), r[5]),
                    tip = { string.format(L["Buy it on the auction house at %s, a vendor pays %s: +%s an item."], C(r[3]), C(r[4]), C(each)),
                        string.format(L["If you buy all %d listed: +%s (only the cheapest price is known, so check each)."], r[5], C(each * r[5])),
                        L["Buy them on the auction house, then sell them to any vendor."] } }
            end
        elseif view == "cheap" then
            local each = math.floor(r[4] * 0.95 - r[3])
            out[#out + 1] = { id = r[1], name = r[2], each = each, value = "+" .. C(each) .. L[" each"],
                sub = string.format(L["buy at %s, usually %s; %d sold in 7 days"], C(r[3]), C(r[4]), r[5]),
                tip = { string.format(L["Listed at %s; it usually sells for %s. After the 5%% auction cut you keep +%s an item."], C(r[3]), C(r[4]), C(each)),
                    string.format(L["%d sold in the last 7 days, so it moves."], r[5]),
                    string.format(L["Buy it, then post it again near %s."], C(r[4])) } }
        elseif view == "crafts" then
            local each = r[6] - r[5]
            out[#out + 1] = { id = r[1], name = r[2], each = each, value = "+" .. C(each) .. L[" a craft"],
                sub = string.format(L["%s %d: materials %s, sells %s; %d sold in 7 days"], r[3], r[4], C(r[5]), C(r[6]), r[7]),
                tip = { string.format(L["Materials cost %s and it sells for %s after the auction cut: +%s a craft."], C(r[5]), C(r[6]), C(each)),
                    string.format(L["Needs %s %d. %d sold in the last 7 days."], r[3], r[4], r[7]),
                    L["Buy the materials, craft it and post it on the auction house."] } }
        elseif view == "farm" then
            out[#out + 1] = { name = string.format("%s (%s)", r[1], r[2]), each = r[5], value = string.format(L["%s/h"], C(r[5])),
                sub = string.format(L["%s; %s a kill, best drop %s"], r[3], C(r[4]), r[6]),
                tip = { string.format(L["Kill %s in %s: about %s a kill, %s an hour at 30 s a kill."], r[1], r[3], C(r[4]), C(r[5])),
                    string.format(L["Best drop: %s. Sell the drops on the auction house."], r[6]) } }
        end
    end
    return out
end

-- ---- The tab ----

local panel
local function AtAuction()
    local lv = DufforthTweaksHelperLeveling
    local where = lv and lv.where
    return type(where) == "table" and where.auction and true or false
end

function M.Refresh()
    if not panel then return end
    local db = DB()
    local view = db.view or M.VIEWS[1].key
    local name, market = M.Market()
    local data = DufforthTweaksHelperMoneyData
    -- Plain tabs: the open view is lighter with white text and a gold line, the others grey.
    for _, b in ipairs(panel.views) do
        local on = b.key == view
        b.on = on
        b.bg:SetColorTexture(0.2, 0.22, 0.28, on and 1 or 0)
        b.mark:SetShown(on)
        if b.SetNormalFontObject then b:SetNormalFontObject(on and "GameFontHighlightSmall" or "GameFontDisableSmall") end
    end
    panel.legend:SetText(M.LEGENDS[view] or "")
    if not market then
        panel.status:SetText(string.format(L["|cffff5555No money ideas for %s yet.|r Download the addon again from the Forever Prices page: it carries the latest prices."], tostring(name)))
    else
        panel.status:SetText(string.format(L["Your market: %s. Prices from %s: check the AH before you buy."], name, M.Age(data.at)))
    end
    local rows = M.Rows(view, market)
    local search = AtAuction()
    for i, line in ipairs(panel.lines) do
        local r = rows[i]
        line.row = r
        line:SetShown(r ~= nil)
        if r then
            line.name:SetText(r.name)
            line.sub:SetText(r.sub)
            line.value:SetText("|cff40ff40" .. r.value .. "|r")
            line.search:SetShown(search and r.id ~= nil)
        end
    end
    panel.empty:SetShown(market ~= nil and #rows == 0)
end

function M.ShowView(key)
    DB().view = key
    M.Refresh()
end

function M.BuildPanel(parent, width)
    panel = parent
    panel.title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", 8, -4)
    panel.title:SetText(L["Money ideas"])
    panel.status = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.status:SetPoint("TOPLEFT", 8, -22); panel.status:SetWidth(width - 16); panel.status:SetJustifyH("LEFT")
    panel.views = {}
    local x, each = 8, math.floor((width - 16) / #M.VIEWS)
    for _, v in ipairs(M.VIEWS) do
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(each - 4, 20); b:SetPoint("TOPLEFT", x, -42); b:SetText(v.label)
        b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
        b.mark = b:CreateTexture(nil, "ARTWORK")
        b.mark:SetPoint("BOTTOMLEFT"); b.mark:SetPoint("BOTTOMRIGHT"); b.mark:SetHeight(2); b.mark:SetColorTexture(1, 0.82, 0, 1)
        local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
        b.key = v.key
        b:SetScript("OnClick", function() M.ShowView(v.key) end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(v.tip, 1, 1, 1, 1, true); GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        panel.views[#panel.views + 1] = b
        x = x + each
    end
    -- What the open view is and what its green number means, in one line.
    panel.legend = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.legend:SetPoint("TOPLEFT", 8, -68); panel.legend:SetWidth(width - 16); panel.legend:SetJustifyH("LEFT")
    if panel.legend.SetWordWrap then panel.legend:SetWordWrap(false) end
    panel.empty = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.empty:SetPoint("TOPLEFT", 12, -90); panel.empty:SetText(L["Nothing worth it right now. Check again after the next price update."])
    panel.lines = {}
    for i = 1, M.ROWS do
        local line = CreateFrame("Button", nil, parent)
        line:SetSize(width - 8, 30)
        line:SetPoint("TOPLEFT", 4, -84 - (i - 1) * 30)
        line.name = line:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        line.name:SetPoint("TOPLEFT", 4, -2); line.name:SetPoint("RIGHT", -130, 0); line.name:SetJustifyH("LEFT")
        line.sub = line:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        line.sub:SetPoint("BOTTOMLEFT", 4, 2); line.sub:SetPoint("RIGHT", -70, 0); line.sub:SetJustifyH("LEFT")
        line.value = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        line.value:SetPoint("TOPRIGHT", -66, -3); line.value:SetJustifyH("RIGHT")
        for _, f in ipairs({ line.name, line.sub }) do if f.SetWordWrap then f:SetWordWrap(false) end end
        local thisLine = line
        line.search = CreateFrame("Button", nil, line, "UIPanelButtonTemplate")
        line.search:SetSize(58, 20); line.search:SetPoint("RIGHT", -4, 0); line.search:SetText(L["Search"])
        if DufforthTweaksHelperUI and DufforthTweaksHelperUI.Skin then DufforthTweaksHelperUI.Skin(line.search) end
        line.search:SetScript("OnClick", function()
            local lv = DufforthTweaksHelperLeveling
            if thisLine.row and thisLine.row.id and lv and lv.SearchAuctionHouse then pcall(lv.SearchAuctionHouse, thisLine.row.id) end
        end)
        -- Hover: what the row means, then what to do (green).
        line:SetScript("OnEnter", function(self)
            local r = self.row
            if not r then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(r.name, 1, 0.82, 0)
            for i, text in ipairs(r.tip or {}) do
                if i == #r.tip then GameTooltip:AddLine(text, 0.4, 1, 0.4, true) else GameTooltip:AddLine(text, 1, 1, 1, true) end
            end
            GameTooltip:Show()
        end)
        line:SetScript("OnLeave", function() GameTooltip:Hide() end)
        panel.lines[i] = line
    end
    if parent.HookScript then parent:HookScript("OnShow", function() M.Refresh() end) end
    M.Refresh()
end
