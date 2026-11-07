-- Auction scan: reads lowest prices and quantities for the Forever Prices page.
-- It asks for one item category at a time, then for each item on your own scan list
-- that the categories didn't find. Addons can't reach the internet, so the page reads
-- the file the game saves on /reload.

local CATEGORY_TIMEOUT = 20 -- seconds without an answer before trying a category again
local ITEM_TIMEOUT = 8 -- the same for one item
local MAX_TRIES = 3
local RETRY_DELAY = 3 -- seconds to wait when another addon asks at the same time
local KEEP_OLD_SECONDS = 24 * 3600 -- earlier results stay in the saved scan for this long
local MAX_LIST_ITEMS = 2000
local AUTO_DELAY = 1 -- seconds after the window opens, so the game's own window can finish loading
local AUTO_MIN_GAP = 60 -- reopening sooner than this doesn't scan again
local AUTO_MAX_INTERRUPTIONS = 2 -- searches an automatic scan yields to before it stops
local LIST_PREFIX = "^%s*GT1:"
local PREFIX = "|cff66ccffDufforth AH Scanner:|r "

-- Quest items and miscellaneous items are left out, so this is not a full scan.
-- The light scan, used when the auction house opens: materials and consumables, rare and
-- epic gear, then a short list of popular crafted gear (Watch.lua) and your own list.
-- It stops at LIGHT_TIME_LIMIT seconds and keeps what it has read.
local LIGHT_TIME_LIMIT = 30
local DEFAULT_SECONDS_PER_REQUEST = 1
local LIGHT_CATEGORIES = {
    { class = 7, name = "Trade goods" },
    { class = 5, name = "Reagents" },
    { class = 0, name = "Consumables" },
    { class = 4, name = "Rare and epic armor", rareAndEpic = true },
    { class = 2, name = "Rare and epic weapons", rareAndEpic = true },
}

local CATEGORIES = {
    { class = 7, name = "Trade goods" },
    { class = 0, name = "Consumables" },
    { class = 5, name = "Reagents" },
    { class = 6, name = "Ammo" },
    { class = 1, name = "Bags", full = true },
    { class = 11, name = "Quivers", full = true },
    { class = 9, name = "Recipes", full = true },
    { class = 4, name = "Armor", full = true },
    { class = 2, name = "Weapons", full = true },
}

local db
local houseOpen = false
local scan -- the scan in progress, or nil
local sending = false -- true while this addon sends its own query
local needsReload = false
local lastAutoStart
local button, listButton, listFrame, listEdit
local frame = CreateFrame("Frame", "DufforthAHScannerScanFrame", UIParent)
local RareAndEpicFilters, ExtraItems

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. message)
end

-- "forever.pvp.horde.us", the same name the page uses.
local function MarketName()
    local realm = string.lower(GetRealmName() or "")
    local ruleset = "normal"
    if string.find(realm, "pvp", 1, true) == nil and string.find(realm, "%f[%a]rp%f[%A]") then
        ruleset = "rp"
    elseif string.find(realm, "pvp", 1, true) then
        ruleset = "pvp"
    end
    local faction = string.lower(UnitFactionGroup("player") or "neutral")
    local region = GetCurrentRegion and GetCurrentRegion() == 3 and "eu" or "us"
    return string.format("forever.%s.%s.%s", ruleset, faction, region)
end

local function ScanList()
    return db and db.scanList or {}
end

local function UpdateButtons()
    if button then
        if scan then
            button:SetText(string.format("Stop scan (%d/%d)", scan.step, #scan.steps))
        elseif needsReload then
            button:SetText("Save scan (reload)")
        else
            button:SetText("Scan prices")
        end
    end
    if listButton then
        listButton:SetText(string.format("Scan my list (%d)", #ScanList()))
        listButton:SetShown(not scan and not needsReload and #ScanList() > 0)
    end
end

local function DecodeSaved(saved)
    local items = {}
    if saved and saved.data and time() - (saved.at or 0) <= KEEP_OLD_SECONDS then
        for id, price, quantity in string.gmatch(saved.data, "(%d+):(%d+):(%d+)") do
            items[tonumber(id)] = { tonumber(price), tonumber(quantity) }
        end
    end
    return items
end

-- New results replace old ones. Recent results for other items stay, so a list scan
-- doesn't throw away an earlier category scan.
local function SaveScan(complete)
    db.scans = db.scans or {}
    local merged = DecodeSaved(db.scans[scan.market])
    local fresh = 0
    for id, row in pairs(scan.items) do
        merged[id] = row
        fresh = fresh + 1
    end
    local parts, count = {}, 0
    for id, row in pairs(merged) do
        count = count + 1
        parts[count] = string.format("%d:%d:%d", id, row[1], row[2])
    end
    table.sort(parts)
    db.scans[scan.market] = {
        at = time(),
        mode = scan.mode,
        complete = complete,
        data = table.concat(parts, ";"),
    }
    return fresh
end

local function FinishScan(complete, reason)
    local count = SaveScan(complete)
    local seconds = time() - scan.startedAt
    -- Learn how long a request takes here, so the next estimate is closer.
    if scan.requests >= 3 and seconds > 0 then
        local measured = seconds / scan.requests
        db.secondsPerRequest = (db.secondsPerRequest or DEFAULT_SECONDS_PER_REQUEST) * 0.6 + measured * 0.4
    end
    local skipped = scan.skipped
    scan = nil
    needsReload = count > 0
    if reason then
        Print(reason)
    end
    if skipped > 0 then
        Print(string.format("%d didn't answer and kept their earlier prices.", skipped))
    end
    Print(string.format("%s %d items in %d seconds. Type /reload, then load the file on the Forever Prices page.",
        complete and "Scan finished:" or "Partial scan saved:", count, seconds))
    UpdateButtons()
end

local function ReadBrowseResults()
    local results = C_AuctionHouse.GetBrowseResults() or {}
    for _, result in ipairs(results) do
        local key = result.itemKey
        local plain = key and (key.itemSuffix or 0) == 0 and (key.battlePetSpeciesID or 0) == 0
        if plain and result.minPrice and result.minPrice > 0 then
            local row = scan.items[key.itemID]
            if row then
                row[1] = math.min(row[1], result.minPrice)
                row[2] = row[2] + (result.totalQuantity or 0)
            else
                scan.items[key.itemID] = { result.minPrice, result.totalQuantity or 0 }
            end
        end
    end
    return #results
end

local function SearchSorts()
    local order = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0
    return { { sortOrder = order, reverseSort = false } }
end

-- 0 for price and quantity means the item was asked for and none are for sale.
local function ReadCommodity(id)
    local info = C_AuctionHouse.GetCommoditySearchResultInfo(id, 1)
    if info and info.unitPrice and info.unitPrice > 0 then
        scan.items[id] = { info.unitPrice, C_AuctionHouse.GetCommoditySearchResultsQuantity(id) or 0 }
    else
        scan.items[id] = { 0, 0 }
    end
end

local function ReadItem(id)
    local key = C_AuctionHouse.MakeItemKey(id)
    local lowest, total = nil, 0
    for index = 1, C_AuctionHouse.GetNumItemSearchResults(key) or 0 do
        local info = C_AuctionHouse.GetItemSearchResultInfo(key, index)
        if info and info.quantity and info.quantity > 0 then
            total = total + info.quantity
            if info.buyoutAmount and info.buyoutAmount > 0 then
                local unit = math.ceil(info.buyoutAmount / info.quantity)
                lowest = lowest and math.min(lowest, unit) or unit
            end
        end
    end
    scan.items[id] = lowest and { lowest, total } or { 0, 0 }
end

local NextStep

-- Asks only for rare and epic items. Nil if this game version has no such filters.
RareAndEpicFilters = function()
    local filters = Enum and Enum.AuctionHouseFilter
    if filters and filters.RareQuality and filters.EpicQuality then
        return { filters.RareQuality, filters.EpicQuality }
    end
end

local function SendStep()
    if not scan then
        return
    end
    scan.waitingToSend = true
    if not C_AuctionHouse.IsThrottledMessageSystemReady() then
        return -- AUCTION_HOUSE_THROTTLED_SYSTEM_READY sends it.
    end
    scan.waitingToSend = false
    scan.lastAnswer = GetTime()
    scan.tries = scan.tries + 1
    scan.asked = true
    local step = scan.steps[scan.step]
    sending = true
    if step.itemID then
        C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(step.itemID), SearchSorts(), false)
    else
        C_AuctionHouse.SendBrowseQuery({
            searchString = "",
            sorts = {},
            filters = step.rareAndEpic and RareAndEpicFilters() or {},
            itemClassFilters = { { classID = step.class } },
        })
    end
    scan.requests = scan.requests + 1
    sending = false
end

local function RequestMore()
    if not C_AuctionHouse.IsThrottledMessageSystemReady() then
        scan.waitingForMore = true
        return
    end
    scan.waitingForMore = false
    scan.lastAnswer = GetTime()
    scan.requests = scan.requests + 1
    C_AuctionHouse.RequestMoreBrowseResults()
end

-- Items asked for one at a time: the popular crafted gear for a light scan, then your list.
ExtraItems = function(mode)
    local ids, seen = {}, {}
    local function add(list)
        for _, id in ipairs(list or {}) do
            if not seen[id] then
                seen[id] = true
                ids[#ids + 1] = id
            end
        end
    end
    if mode == "light" then
        add(DufforthAHScannerWatch)
    end
    add(ScanList())
    return ids
end

-- List items wait until the categories are done, so only the ones they missed are asked for.
local function AddListSteps()
    if scan.listAdded then
        return
    end
    scan.listAdded = true
    for _, id in ipairs(ExtraItems(scan.mode)) do
        if not scan.items[id] then
            scan.steps[#scan.steps + 1] = { itemID = id, name = "Item " .. id }
        end
    end
end

NextStep = function()
    scan.step = scan.step + 1
    scan.tries = 0
    if scan.step > #scan.steps then
        AddListSteps()
    end
    if scan.step > #scan.steps then
        FinishScan(true)
        return
    end
    UpdateButtons()
    SendStep()
end

local function OnBrowseResults()
    if not scan or not scan.asked or scan.steps[scan.step].itemID then
        return
    end
    scan.lastAnswer = GetTime()
    if C_AuctionHouse.HasFullBrowseResults() then
        scan.asked = false
        local count = ReadBrowseResults()
        if not scan.auto then
            Print(string.format("%s: %d results.", scan.steps[scan.step].name, count))
        end
        NextStep()
    else
        RequestMore()
    end
end

local function OnItemResults(id, read)
    if not scan or not scan.asked then
        return
    end
    local step = scan.steps[scan.step]
    if step.itemID ~= id then
        return
    end
    scan.asked = false
    read(id)
    NextStep()
end

local function StartScan(mode, auto)
    if scan then
        Print("A scan is already running. Type /ahscan stop to end it.")
        return
    end
    if not houseOpen then
        Print("Open the auction house first.")
        return
    end
    local steps = {}
    if mode == "light" then
        for _, category in ipairs(LIGHT_CATEGORIES) do
            if not category.rareAndEpic or RareAndEpicFilters() then
                steps[#steps + 1] = category
            end
        end
    elseif mode ~= "list" then
        for _, category in ipairs(CATEGORIES) do
            if not (mode == "quick" and category.full) then
                steps[#steps + 1] = category
            end
        end
    elseif #ScanList() == 0 then
        Print("Your scan list is empty. Copy it from the Forever Prices page, then type /ahscan list.")
        return
    end
    needsReload = false
    scan = {
        steps = steps, step = 0, tries = 0, items = {}, market = MarketName(), skipped = 0,
        mode = mode, startedAt = time(), lastAnswer = GetTime(), auto = auto, interruptions = 0, requests = 0,
    }
    if mode == "light" then
        -- One request per category, plus some for categories that come in parts, plus one per extra item.
        local requests = #steps * 2 + #ExtraItems(mode)
        local estimate = math.min(LIGHT_TIME_LIMIT, math.ceil(requests * (db.secondsPerRequest or DEFAULT_SECONDS_PER_REQUEST)))
        Print(string.format("%s light scan: about %d seconds, never more than %d. Type /ahscan stop to stop%s.",
            auto and "Automatic" or "Starting a", estimate, LIGHT_TIME_LIMIT, auto and ", or /ahscan auto off to turn this off" or ""))
    elseif auto then
        Print("Scanning prices automatically. Type /ahscan stop to stop, or /ahscan auto off to turn this off.")
    else
        Print(mode == "list" and string.format("Scanning your list of %d items in %s.", #ScanList(), scan.market)
            or string.format("Scanning %s: %d categories, without quest and miscellaneous items.", scan.market, #steps))
    end
    NextStep()
end

local function AutoScanEnabled()
    return db and db.autoScan ~= false
end

local function MaybeAutoScan()
    if not AutoScanEnabled() or not houseOpen or scan then
        return
    end
    if lastAutoStart and time() - lastAutoStart < AUTO_MIN_GAP then
        return
    end
    lastAutoStart = time()
    StartScan("light", true)
end

-- Results are shared, so someone else's search replaces what this scan asked for.
-- A manual scan waits and asks again. An automatic one gives way, so it never fights you.
local function OnOtherQuery(isBrowse)
    if not scan or sending or not scan.asked then
        return
    end
    if scan.auto then
        scan.interruptions = scan.interruptions + 1
        if scan.interruptions >= AUTO_MAX_INTERRUPTIONS then
            FinishScan(false, "Another search started, so the automatic scan stopped. Type /ahscan to run it again.")
            return
        end
    elseif not isBrowse or scan.steps[scan.step].itemID then
        return
    end
    scan.asked = false
    C_Timer.After(RETRY_DELAY, function()
        if scan and not scan.asked then
            scan.tries = 0
            SendStep()
        end
    end)
end

local function CheckTimeout()
    if scan and scan.mode == "light" and time() - scan.startedAt >= LIGHT_TIME_LIMIT then
        FinishScan(false, string.format("The light scan reached its %d second limit.", LIGHT_TIME_LIMIT))
        return
    end
    if not scan or scan.waitingToSend or scan.step < 1 then
        return
    end
    local step = scan.steps[scan.step]
    local limit = step.itemID and ITEM_TIMEOUT or CATEGORY_TIMEOUT
    if GetTime() - scan.lastAnswer < limit then
        return
    end
    if not step.itemID and scan.tries < MAX_TRIES then
        Print(step.name .. " isn't answering. Trying again.")
        SendStep()
    else
        if not step.itemID then
            Print(step.name .. " didn't answer. Skipping it.")
        end
        scan.skipped = scan.skipped + 1
        scan.asked = false
        NextStep()
    end
end

-- ---------------------------------------------------------------------------
-- The scan list comes from the page, which is its one source of truth.
-- ---------------------------------------------------------------------------

local function ParseList(text)
    local body = string.gsub(text or "", LIST_PREFIX, "")
    local ids, seen = {}, {}
    for digits in string.gmatch(body, "%d+") do
        local id = tonumber(digits)
        if id and id > 0 and id < 2147483648 and not seen[id] and #ids < MAX_LIST_ITEMS then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    return ids
end

local function SaveList()
    db.scanList = ParseList(listEdit:GetText())
    listFrame:Hide()
    Print(string.format("Scan list saved: %d items.", #db.scanList))
    UpdateButtons()
end

local function ShowListWindow()
    if not listFrame then
        listFrame = CreateFrame("Frame", "DufforthAHScannerListFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        listFrame:SetSize(420, 170)
        listFrame:SetPoint("CENTER")
        listFrame:SetFrameStrata("DIALOG")
        if listFrame.SetBackdrop then
            listFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            listFrame:SetBackdropColor(0.05, 0.06, 0.08, 0.95)
            listFrame:SetBackdropBorderColor(0, 0, 0, 1)
        end
        local title = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 12, -10)
        title:SetText("Paste your scan list from the Forever Prices page")

        listEdit = CreateFrame("EditBox", "DufforthAHScannerListEdit", listFrame)
        listEdit:SetPoint("TOPLEFT", 12, -34)
        listEdit:SetPoint("BOTTOMRIGHT", -12, 44)
        listEdit:SetMultiLine(true)
        listEdit:SetMaxLetters(0)
        listEdit:SetAutoFocus(true)
        listEdit:SetFontObject(ChatFontNormal)
        listEdit:SetScript("OnEscapePressed", function() listFrame:Hide() end)

        local save = CreateFrame("Button", "DufforthAHScannerListSave", listFrame, "UIPanelButtonTemplate")
        save:SetSize(90, 24)
        save:SetPoint("BOTTOMRIGHT", -12, 10)
        save:SetText("Save")
        save:SetScript("OnClick", SaveList)

        local cancel = CreateFrame("Button", "DufforthAHScannerListCancel", listFrame, "UIPanelButtonTemplate")
        cancel:SetSize(90, 24)
        cancel:SetPoint("RIGHT", save, "LEFT", -8, 0)
        cancel:SetText("Cancel")
        cancel:SetScript("OnClick", function() listFrame:Hide() end)
    end
    local ids = ScanList()
    listEdit:SetText(#ids > 0 and ("GT1:" .. table.concat(ids, ",")) or "")
    listFrame:Show()
    listEdit:SetFocus()
    listEdit:HighlightText()
end

local function CreateButtons()
    if button then
        UpdateButtons()
        return
    end
    local parent = AuctionHouseFrame or UIParent
    button = CreateFrame("Button", "DufforthAHScannerScanButton", parent, "UIPanelButtonTemplate")
    button:SetSize(150, 22)
    if AuctionHouseFrame then
        button:SetPoint("TOPRIGHT", AuctionHouseFrame, "TOPRIGHT", -70, -1)
    else
        button:SetPoint("TOP", UIParent, "TOP", 0, -80)
    end
    button:SetScript("OnClick", function()
        if scan then
            FinishScan(false, "Scan stopped.")
        elseif needsReload then
            ReloadUI()
        else
            StartScan("full")
        end
    end)
    listButton = CreateFrame("Button", "DufforthAHScannerScanListButton", parent, "UIPanelButtonTemplate")
    listButton:SetSize(150, 22)
    listButton:SetPoint("RIGHT", button, "LEFT", -6, 0)
    listButton:SetScript("OnClick", function() StartScan("list") end)
    UpdateButtons()
end

SLASH_DUFFORTHAHSCANNERSCAN1 = "/ahscan"
SlashCmdList.DUFFORTHAHSCANNERSCAN = function(input)
    local command = string.lower(string.match(input or "", "^%s*(%S*)") or "")
    if command == "stop" then
        if scan then
            FinishScan(false, "Scan stopped.")
        else
            Print("No scan is running.")
        end
    elseif command == "light" then
        StartScan("light")
    elseif command == "quick" then
        StartScan("quick")
    elseif command == "mine" then
        StartScan("list")
    elseif command == "list" then
        ShowListWindow()
    elseif command == "auto" then
        local option = string.lower(string.match(input or "", "^%s*%S+%s+(%S+)") or "")
        if option == "on" then
            db.autoScan = true
        elseif option == "off" then
            db.autoScan = false
        else
            db.autoScan = not AutoScanEnabled()
        end
        Print("Automatic scan when you open the auction house: " .. (AutoScanEnabled() and "ON" or "OFF") .. ".")
    elseif command == "" then
        StartScan("full")
    else
        Print("/ahscan - scan materials, consumables, recipes, gear and your list")
        Print("/ahscan light - the automatic scan: materials, rare and epic gear, popular crafted gear and your list, at most 30 seconds")
        Print("/ahscan quick - scan only materials, consumables, ammo and your list")
        Print("/ahscan mine - scan only your list")
        Print("/ahscan list - paste your list from the Forever Prices page")
        Print("/ahscan auto - turn the automatic scan on or off")
        Print("/ahscan stop - stop and keep what has been read")
    end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("AUCTION_HOUSE_SHOW")
frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
frame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
frame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
frame:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
frame:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
frame:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")

local hooked = false

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "DufforthAHScanner" then
            DufforthAHScannerDB = DufforthAHScannerDB or {}
            db = DufforthAHScannerDB
        end
    elseif event == "AUCTION_HOUSE_SHOW" then
        houseOpen = true
        CreateButtons()
        if not hooked and C_AuctionHouse and hooksecurefunc then
            hooked = true
            hooksecurefunc(C_AuctionHouse, "SendBrowseQuery", function() OnOtherQuery(true) end)
            hooksecurefunc(C_AuctionHouse, "SendSearchQuery", function() OnOtherQuery(false) end)
        end
        if AutoScanEnabled() then
            C_Timer.After(AUTO_DELAY, MaybeAutoScan)
        end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        houseOpen = false
        if scan then
            FinishScan(false, "The auction house closed.")
        end
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        if scan and scan.waitingToSend then
            SendStep()
        elseif scan and scan.waitingForMore then
            RequestMore()
        end
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        OnBrowseResults()
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        OnItemResults(arg1, ReadCommodity)
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        OnItemResults(type(arg1) == "table" and arg1.itemID or nil, ReadItem)
    end
end)

C_Timer.NewTicker(2, CheckTimeout)
