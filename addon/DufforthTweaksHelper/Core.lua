-- Shared helpers and the /dufforth command.

DufforthTweaksHelper = DufforthTweaksHelper or {}
local PREFIX = "|cff66ccffDufforth Tweaks Helper:|r "
DufforthTweaksHelper.PREFIX = PREFIX

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. message)
end
DufforthTweaksHelper.Print = Print

-- "forever.pvp.horde.us", the market name the Forever Prices page and the bundled prices use.
function DufforthTweaksHelper.MarketName()
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

-- "Name-Realm", to keep each character's known recipes apart.
function DufforthTweaksHelper.CharacterKey()
    return (UnitName and UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
end

-- Skill line numbers the game uses for each profession.
local SKILL_LINES = {
    [171] = "Alchemy", [164] = "Blacksmithing", [333] = "Enchanting", [202] = "Engineering", [165] = "Leatherworking",
    [197] = "Tailoring", [185] = "Cooking", [129] = "First Aid", [186] = "Mining", [182] = "Herbalism",
    [356] = "Fishing", [393] = "Skinning",
}
local BY_NAME = {}
for _, name in pairs(SKILL_LINES) do BY_NAME[name] = true end

-- Your professions and skill, bonuses included: { Tailoring = 150, ... }, or nil if the game can't tell.
function DufforthTweaksHelper.Professions()
    local out, read = {}, false
    if GetProfessions and GetProfessionInfo then
        read = true
        local a, b, c, d, e, f = GetProfessions()
        local list = { a, b, c, d, e, f }
        for i = 1, 6 do
            if list[i] then
                local name, _, rank, _, _, _, line, modifier = GetProfessionInfo(list[i])
                name = SKILL_LINES[line] or name
                if name and rank then out[name] = rank + (modifier or 0) end
            end
        end
    end
    if not next(out) and GetNumSkillLines and GetSkillLineInfo then
        read = true
        for i = 1, GetNumSkillLines() do
            local name, header, _, rank, _, modifier = GetSkillLineInfo(i)
            if not header and name and BY_NAME[name] and rank then out[name] = rank + (modifier or 0) end
        end
    end
    return read and out or nil
end

SLASH_DUFFORTHTWEAKSHELPER1 = "/dufforth"
SLASH_DUFFORTHTWEAKSHELPER2 = "/dth"
SlashCmdList.DUFFORTHTWEAKSHELPER = function(input)
    local command, option = string.match(string.lower(input or ""), "^%s*(%S*)%s*(%S*)")
    if command == "" or command == "menu" then
        if DufforthTweaksHelperMenu_Toggle then DufforthTweaksHelperMenu_Toggle() end
    elseif command == "gather" or command == "crafting" or command == "warrior" then
        if DufforthTweaksHelperMenu_Toggle then DufforthTweaksHelperMenu_Toggle(command) end
    elseif command == "de" then
        DufforthTweaksHelperDE.Toggle(option)
    elseif command == "disenchant" then
        DufforthTweaksHelperAutoDE.Toggle()
    else
        Print("/dufforth - open the window (also the minimap button). /dth works too.")
        Print("/dufforth gather, /dufforth crafting, /dufforth warrior - open it on that tab")
        Print("/dufforth de - show or hide disenchant advice in item tooltips")
        Print("/dufforth disenchant - open the list that disenchants BoE gear, one click per item")
        Print("/nk - herb and ore commands; /nk help lists them")
    end
end

-- Older versions saved things this one no longer uses. Drop them.
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= "DufforthTweaksHelper" then return end
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    DufforthTweaksHelperDB.scans, DufforthTweaksHelperDB.scanList, DufforthTweaksHelperDB.autoScan = nil, nil, nil
    DufforthTweaksHelperDB.secondsPerRequest = nil
    self:UnregisterEvent("ADDON_LOADED")
end)
