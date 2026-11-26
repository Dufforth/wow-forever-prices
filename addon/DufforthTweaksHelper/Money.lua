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

-- One view's rows as { id (item to search, or nil), name, sub, value }.
function M.Rows(view, market)
    local out = {}
    for _, r in ipairs((market or {})[view] or {}) do
        if view == "flips" then
            out[#out + 1] = { id = r[1], name = r[2], value = M.Gold((r[4] - r[3]) * r[5]),
                sub = string.format(L["buy at %s, a vendor pays %s; %d listed"], M.Gold(r[3]), M.Gold(r[4]), r[5]) }
        elseif view == "cheap" then
            out[#out + 1] = { id = r[1], name = r[2], value = "+" .. M.Gold(r[4] * 0.95 - r[3]),
                sub = string.format(L["buy at %s, usually %s; %d sold in 7 days"], M.Gold(r[3]), M.Gold(r[4]), r[5]) }
        elseif view == "crafts" then
            out[#out + 1] = { id = r[1], name = r[2], value = "+" .. M.Gold(r[6] - r[5]),
                sub = string.format(L["%s %d: materials %s, sells %s; %d sold in 7 days"], r[3], r[4], M.Gold(r[5]), M.Gold(r[6]), r[7]) }
        elseif view == "farm" then
            out[#out + 1] = { name = string.format("%s (%s)", r[1], r[2]), value = string.format(L["%s/h"], M.Gold(r[5])),
                sub = string.format(L["%s; %s a kill, best drop %s"], r[3], M.Gold(r[4]), r[6]) }
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
    for _, b in ipairs(panel.views) do
        if b.LockHighlight then if b.key == view then b:LockHighlight() else b:UnlockHighlight() end end
    end
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
        local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetSize(each - 4, 20); b:SetPoint("TOPLEFT", x, -42); b:SetText(v.label)
        b.key = v.key
        b:SetScript("OnClick", function() M.ShowView(v.key) end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(v.tip, 1, 1, 1, 1, true); GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        panel.views[#panel.views + 1] = b
        x = x + each
    end
    panel.empty = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.empty:SetPoint("TOPLEFT", 12, -74); panel.empty:SetText(L["Nothing worth it right now. Check again after the next price update."])
    panel.lines = {}
    for i = 1, M.ROWS do
        local line = CreateFrame("Button", nil, parent)
        line:SetSize(width - 8, 30)
        line:SetPoint("TOPLEFT", 4, -68 - (i - 1) * 30)
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
        line.search:SetScript("OnClick", function()
            local lv = DufforthTweaksHelperLeveling
            if thisLine.row and thisLine.row.id and lv and lv.SearchAuctionHouse then pcall(lv.SearchAuctionHouse, thisLine.row.id) end
        end)
        line:SetScript("OnEnter", function(self)
            if self.row and self.row.id and GameTooltip.SetHyperlink then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink("item:" .. self.row.id); GameTooltip:Show()
            end
        end)
        line:SetScript("OnLeave", function() GameTooltip:Hide() end)
        panel.lines[i] = line
    end
    if parent.HookScript then parent:HookScript("OnShow", function() M.Refresh() end) end
    M.Refresh()
end
