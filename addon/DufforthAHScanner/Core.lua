-- Shared helpers and the /dufforth command.

DufforthAHScanner = DufforthAHScanner or {}
local PREFIX = "|cff66ccffDufforth AH Scanner:|r "

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. message)
end
DufforthAHScanner.Print = Print

-- "forever.pvp.horde.us", the market name the Forever Prices page and the bundled prices use.
function DufforthAHScanner.MarketName()
    local realm = string.lower(GetRealmName() or "")
    local ruleset = "normal"
    if string.find(realm, "pvp", 1, true) then
        ruleset = "pvp"
    elseif string.find(realm, "%f[%a]rp%f[%A]") then
        ruleset = "rp"
    end
    local faction = string.lower(UnitFactionGroup("player") or "neutral")
    local region = GetCurrentRegion and GetCurrentRegion() == 3 and "eu" or "us"
    return string.format("forever.%s.%s.%s", ruleset, faction, region)
end

SLASH_DUFFORTHAHSCANNER1 = "/dufforth"
SlashCmdList.DUFFORTHAHSCANNER = function(input)
    local command, option = string.match(string.lower(input or ""), "^%s*(%S*)%s*(%S*)")
    if command == "" or command == "menu" then
        if DufforthAHScannerMenu_Toggle then DufforthAHScannerMenu_Toggle() end
    elseif command == "de" then
        DufforthAHScannerDE.Toggle(option)
    elseif command == "disenchant" then
        DufforthAHScannerAutoDE.Toggle()
    else
        Print("/dufforth - open the settings menu (also on the minimap button)")
        Print("/dufforth de - show or hide disenchant values in item tooltips")
        Print("/dufforth disenchant - open the window that disenchants BoE gear, one click per item")
        Print("/nk - herb and ore commands; /nk help lists them")
    end
end

-- The auction scan was removed in 3.4.0: Blizzard's prices replace it. Drop what it saved.
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= "DufforthAHScanner" then return end
    DufforthAHScannerDB = DufforthAHScannerDB or {}
    DufforthAHScannerDB.scans, DufforthAHScannerDB.scanList, DufforthAHScannerDB.autoScan = nil, nil, nil
    DufforthAHScannerDB.secondsPerRequest = nil
    self:UnregisterEvent("ADDON_LOADED")
end)
