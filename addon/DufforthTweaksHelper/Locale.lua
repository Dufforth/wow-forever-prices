-- The addon's language (user, 2026-11-14): Spanish on esES and esMX clients, English everywhere else.
-- DufforthTweaksHelperL["English text"] gives the Spanish text when there is one, else the English text, so a
-- missing translation never breaks anything. The route data stays English; zones are matched by map ID.
-- Loaded first (see the toc). Spanish texts are in LocaleES.lua.

DufforthTweaksHelperLocale = DufforthTweaksHelperLocale or {}
local Loc = DufforthTweaksHelperLocale
Loc.ES = Loc.ES or {}

function Loc.Set(locale)
    Loc.locale = locale or "enUS"
    Loc.spanish = Loc.locale == "esES" or Loc.locale == "esMX"
end
Loc.Set(GetLocale and GetLocale() or "enUS")

DufforthTweaksHelperL = setmetatable({}, {
    __index = function(_, key)
        if Loc.spanish and key ~= nil then
            local es = Loc.ES[key]
            if es then return es end
        end
        return key
    end,
    __call = function(t, key) return t[key] end,
})

-- Spanish zone names (esES; esMX where it differs) -> the English names the route data uses.
-- Only a fallback: the map ID decides first (Loc.MapZone).
Loc.ZONES = {
    ["Los Baldíos"] = "The Barrens", ["Cima del Trueno"] = "Thunder Bluff", ["Claros de Tirisfal"] = "Tirisfal Glades",
    ["Entrañas"] = "Undercity", ["Bosque de Argénteos"] = "Silverpine Forest", ["Bosque de Argenteos"] = "Silverpine Forest",
    ["Sierra Espolón"] = "Stonetalon Mountains", ["Sierra Espolon"] = "Stonetalon Mountains", ["Vallefresno"] = "Ashenvale",
    ["Laderas de Trabalomas"] = "Hillsbrad Foothills", ["Las Mil Agujas"] = "Thousand Needles", ["Mil Agujas"] = "Thousand Needles",
    ["Vega de Tuercespina"] = "Stranglethorn Vale", ["Tierras Altas de Arathi"] = "Arathi Highlands",
    ["Marjal Revolcafango"] = "Dustwallow Marsh", ["Tierras Inhóspitas"] = "Badlands", ["Pantano de las Penas"] = "Swamp of Sorrows",
    ["Tierras del Interior"] = "The Hinterlands", ["La Garganta de Fuego"] = "Searing Gorge", ["Garganta de Fuego"] = "Searing Gorge",
    ["Cráter de Un'Goro"] = "Un'Goro Crater", ["Frondavil"] = "Felwood", ["Las Estepas Ardientes"] = "Burning Steppes",
    ["Estepas Ardientes"] = "Burning Steppes", ["Cuna del Invierno"] = "Winterspring",
    ["Tierras de la Peste del Oeste"] = "Western Plaguelands", ["Tierras de la Peste del Este"] = "Eastern Plaguelands",
    ["Montañas de Alterac"] = "Alterac Mountains", ["Los Humedales"] = "Wetlands", ["Humedales"] = "Wetlands",
    ["Bosque de Elwynn"] = "Elwynn Forest", ["Páramos de Poniente"] = "Westfall", ["Montañas Crestagrana"] = "Redridge Mountains",
    ["Bosque del Ocaso"] = "Duskwood", ["Costa Oscura"] = "Darkshore", ["Claro de la Luna"] = "Moonglade",
    ["Paso de la Muerte"] = "Deadwind Pass", ["Las Tierras Devastadas"] = "Blasted Lands", ["Tierras Devastadas"] = "Blasted Lands",
    ["Forjaz"] = "Ironforge", ["Ventormenta"] = "Stormwind City", ["Ciudad de Ventormenta"] = "Stormwind City",
    ["Monte Hyjal"] = "Mount Hyjal", ["Isla Zephras"] = "Zephras Isle",
}

local function MapsByName() return DufforthTweaksHelperGuideData and DufforthTweaksHelperGuideData.uiMaps or {} end

-- The English zone name of a map ID (a cave or a town inside a zone counts as that zone), nil if unknown.
function Loc.MapZone(map)
    if not map then return nil end
    if not Loc.byMap then
        local byMap, count = {}, 0
        for name, id in pairs(MapsByName()) do byMap[id] = name; count = count + 1 end
        if count == 0 then return nil end
        Loc.byMap = byMap
    end
    for _ = 1, 6 do
        local name = Loc.byMap[map]
        if name then return name end
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
        if not (info and info.parentMapID and info.parentMapID ~= 0) or (info.mapType and info.mapType <= 2) then return nil end
        map = info.parentMapID
    end
    return nil
end

-- A zone name from the game (any language) as the route data's English name.
function Loc.EnglishZone(name)
    if not name or name == "" then return name end
    if MapsByName()[name] or not Loc.spanish then return name end
    return Loc.ZONES[name] or name
end

-- Where you are, as an English zone name: on a Spanish client by map ID, else the game's own name.
function Loc.ZoneName()
    local raw = (GetRealZoneText and GetRealZoneText()) or ""
    if not Loc.spanish or MapsByName()[raw] then return raw end
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    return Loc.MapZone(map) or Loc.EnglishZone(raw)
end

-- A taxi node name "Place, Zone" with the zone in English.
function Loc.EnglishNode(name)
    if not (Loc.spanish and name) then return name end
    local place, region = string.match(name, "^(.-),%s*(.+)$")
    if not region then return Loc.EnglishZone(name) end
    return place .. ", " .. Loc.EnglishZone(region)
end

-- Profession names to show (the addon keeps the English names as keys).
Loc.PROFESSIONS = {
    Alchemy = "Alquimia", Blacksmithing = "Herrería", Enchanting = "Encantamiento", Engineering = "Ingeniería",
    Leatherworking = "Peletería", Tailoring = "Sastrería", Cooking = "Cocina", ["First Aid"] = "Primeros auxilios",
    Mining = "Minería", Herbalism = "Herboristería", Fishing = "Pesca", Skinning = "Desuello",
}
function Loc.Prof(name)
    if Loc.spanish and name then return Loc.PROFESSIONS[name] or name end
    return name
end
