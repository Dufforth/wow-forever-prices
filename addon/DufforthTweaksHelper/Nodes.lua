-- Dufforth Tweaks Helper, Gather: remembers the herbs and ore your tracking shows, and keeps an icon
-- on the minimap for each after you swap tracking, until you gather it.
--
-- The game gives addons no list of tracked nodes. Forever does let an addon move the
-- minimap's mouseover to any point and read the names under it, so the minimap is
-- swept with a grid of those probes, and each dot found is stored as a world position.
-- The herb and ore name list comes from ForeverMinimap (ljukas/forever-addons, MIT).
--
-- Forever client 1.60.1.70862 (7 November 2026) stopped that probing for addons: every probe
-- reads nothing, or the dot the player last hovered (ForeverMinimap found the same and turned
-- its scan off). From that build on, a dot is remembered when YOU hover it on the minimap (the
-- game's own tooltip names it), and a gathered spot when you gather it (the cast names the node).

local GRID_STEP = 7 -- minimap pixels between probes
local PROBES_PER_FRAME = 60
local SCAN_INTERVAL = 1.5 -- seconds between sweeps
local LINK_PIXELS = GRID_STEP * 1.6 -- hits this close belong to the same dot
local MATCH_YARDS = 15 -- a dot this close to a same-named icon is that icon
local MATCH_PIXELS = 12 -- the same, when zoomed far out
local LOOT_YARDS = 8 -- how near you must be to a node to have gathered it
local INTERIOR = 0.75 -- dots near the edge are cut off, so their position is not trusted
local MISS_INTERIOR = 0.7 -- how far out a missing dot counts as really missing
local MISSES_TO_REMOVE = 2 -- sweeps in a row without the dot before its icon goes
local SWAP_GRACE = 0.9 -- seconds after a tracking swap before a missing dot counts
local SWAP_SETTLE = 1 -- seconds after a tracking swap before the next sweep
local MIN_SWAP_SECONDS, MAX_SWAP_SECONDS = 2, 60
local DEFAULT_SWAP_SECONDS = 4
local FIND_HERBS, FIND_MINERALS = 2383, 2580
local EDGE_MARGIN = 4
local MAX_ICONS = 60
local DEFAULT_SIZE = 10 -- the size of the game's yellow tracking dots
local OLD_DEFAULT_SIZE = 14
local MIN_SIZE, MAX_SIZE = 6, 20
local DEFAULT_KEEP_MINUTES = 0 -- keep icons until you gather them (the user's choice)
local OLD_DEFAULT_KEEP_MINUTES = 30
local PROBING_BLOCKED_FROM_BUILD = 70862
local HOVER_WEIGHT_CAP = 5 -- a remembered spot moves toward later hovers, up to 1/5 per hover
local GATHER_SECONDS = 20 -- how long after a gathering cast the loot still counts as that node
local DEFAULT_GATHERED_MINUTES = 60
local GATHERED_GRACE = 10 -- seconds a gathered dot may linger before it counts as back
local PREFIX = "|cff66ccffDufforth Tweaks Helper:|r "
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local FIND_SPELLS = { [2383] = "herb", [8387] = "herb", [2580] = "ore", [8388] = "ore" }
-- When the game gives no spell number: the tracking names and pictures.
local FIND_NAMES = { ["Find Herbs"] = "herb", ["Find Minerals"] = "ore" }
local FIND_TEXTURES = { [133939] = "herb", [136025] = "ore",
    ["interface\\icons\\inv_misc_flower_02"] = "herb", ["interface\\icons\\spell_nature_earthquake"] = "ore" }
local STYLE = {
    herb = { icon = "Interface\\Icons\\INV_Misc_Flower_02", r = 0.2, g = 0.9, b = 0.3, label = "Herb" },
    ore = { icon = "Interface\\Icons\\Spell_Nature_Earthquake", r = 1, g = 0.55, b = 0.1, label = "Ore" },
}

local NODES = {
    ["Copper Vein"] = "ore",
    ["Tin Vein"] = "ore",
    ["Incendicite Mineral Vein"] = "ore",
    ["Silver Vein"] = "ore",
    ["Ooze Covered Silver Vein"] = "ore",
    ["Lesser Bloodstone Deposit"] = "ore",
    ["Iron Deposit"] = "ore",
    ["Indurium Mineral Vein"] = "ore",
    ["Gold Vein"] = "ore",
    ["Ooze Covered Gold Vein"] = "ore",
    ["Mithril Deposit"] = "ore",
    ["Ooze Covered Mithril Deposit"] = "ore",
    ["Truesilver Deposit"] = "ore",
    ["Ooze Covered Truesilver Deposit"] = "ore",
    ["Dark Iron Deposit"] = "ore",
    ["Small Thorium Vein"] = "ore",
    ["Ooze Covered Thorium Vein"] = "ore",
    ["Rich Thorium Vein"] = "ore",
    ["Ooze Covered Rich Thorium Vein"] = "ore",
    ["Small Obsidian Chunk"] = "ore",
    ["Large Obsidian Chunk"] = "ore",
    ["Chunk of Amber"] = "ore",
    ["Large Chunk of Amber"] = "ore",
    ["Poor Copper Vein"] = "ore",
    ["Cold Iron Deposit"] = "ore",
    ["Fool's Gold Vein"] = "ore",
    ["Starsilver Vein"] = "ore",
    ["Greater Moonstone Formation"] = "ore",
    ["Hakkari Thorium Vein"] = "ore",
    ["Heavy Thorium Vein"] = "ore",

    ["Peacebloom"] = "herb",
    ["Silverleaf"] = "herb",
    ["Earthroot"] = "herb",
    ["Mageroyal"] = "herb",
    ["Briarthorn"] = "herb",
    ["Stranglekelp"] = "herb",
    ["Bruiseweed"] = "herb",
    ["Wild Steelbloom"] = "herb",
    ["Grave Moss"] = "herb",
    ["Kingsblood"] = "herb",
    ["Liferoot"] = "herb",
    ["Fadeleaf"] = "herb",
    ["Goldthorn"] = "herb",
    ["Khadgar's Whisker"] = "herb",
    ["Wintersbite"] = "herb",
    ["Firebloom"] = "herb",
    ["Purple Lotus"] = "herb",
    ["Arthas' Tears"] = "herb",
    ["Sungrass"] = "herb",
    ["Blindweed"] = "herb",
    ["Ghost Mushroom"] = "herb",
    ["Gromsblood"] = "herb",
    ["Golden Sansam"] = "herb",
    ["Dreamfoil"] = "herb",
    ["Mountain Silversage"] = "herb",
    ["Plaguebloom"] = "herb",
    ["Icecap"] = "herb",
    ["Black Lotus"] = "herb",
    ["Wilted Peacebloom"] = "herb",
    ["Stunted Silverleaf"] = "herb",
    ["Hyjal Silphium"] = "herb",
    ["Tomb Weed"] = "herb",
    ["Doom Weed"] = "herb",
    ["Gloom Weed"] = "herb",
    ["Incendia Agave"] = "herb",
    ["Serpentbloom"] = "herb",
    ["Violet Tragan"] = "herb",
    ["Beached Sea Creature"] = "herb",
    ["Skeletal Sea Turtle"] = "herb",
    ["Nightmare Moss"] = "herb",
    ["Dreamroot"] = "herb",
    ["Moonroot"] = "herb",
    ["Star Lotus"] = "herb",
}

-- The skill each node needs.
local NODE_SKILLS = {
    ["Copper Vein"] = 1,
    ["Tin Vein"] = 65,
    ["Incendicite Mineral Vein"] = 65,
    ["Silver Vein"] = 75,
    ["Ooze Covered Silver Vein"] = 75,
    ["Lesser Bloodstone Deposit"] = 75,
    ["Iron Deposit"] = 125,
    ["Indurium Mineral Vein"] = 150,
    ["Gold Vein"] = 155,
    ["Ooze Covered Gold Vein"] = 155,
    ["Mithril Deposit"] = 175,
    ["Ooze Covered Mithril Deposit"] = 175,
    ["Truesilver Deposit"] = 230,
    ["Ooze Covered Truesilver Deposit"] = 230,
    ["Dark Iron Deposit"] = 230,
    ["Small Thorium Vein"] = 245,
    ["Ooze Covered Thorium Vein"] = 245,
    ["Rich Thorium Vein"] = 275,
    ["Ooze Covered Rich Thorium Vein"] = 275,
    ["Small Obsidian Chunk"] = 305,
    ["Large Obsidian Chunk"] = 305,
    ["Chunk of Amber"] = 1,
    ["Large Chunk of Amber"] = 1,
    ["Poor Copper Vein"] = 1,
    ["Cold Iron Deposit"] = 125,
    ["Fool's Gold Vein"] = 175,
    ["Starsilver Vein"] = 245,
    ["Greater Moonstone Formation"] = 245,
    ["Hakkari Thorium Vein"] = 275,
    ["Heavy Thorium Vein"] = 300,
    ["Peacebloom"] = 1,
    ["Silverleaf"] = 1,
    ["Earthroot"] = 15,
    ["Mageroyal"] = 50,
    ["Briarthorn"] = 70,
    ["Stranglekelp"] = 85,
    ["Bruiseweed"] = 100,
    ["Wild Steelbloom"] = 115,
    ["Grave Moss"] = 120,
    ["Kingsblood"] = 125,
    ["Liferoot"] = 150,
    ["Fadeleaf"] = 160,
    ["Goldthorn"] = 170,
    ["Khadgar's Whisker"] = 185,
    ["Wintersbite"] = 195,
    ["Firebloom"] = 205,
    ["Purple Lotus"] = 210,
    ["Arthas' Tears"] = 220,
    ["Sungrass"] = 230,
    ["Blindweed"] = 235,
    ["Ghost Mushroom"] = 245,
    ["Gromsblood"] = 250,
    ["Golden Sansam"] = 260,
    ["Dreamfoil"] = 270,
    ["Mountain Silversage"] = 280,
    ["Plaguebloom"] = 285,
    ["Icecap"] = 290,
    ["Black Lotus"] = 300,
    ["Wilted Peacebloom"] = 1,
    ["Stunted Silverleaf"] = 1,
    ["Hyjal Silphium"] = 1,
    ["Tomb Weed"] = 1,
    ["Doom Weed"] = 1,
    ["Gloom Weed"] = 1,
    ["Incendia Agave"] = 1,
    ["Serpentbloom"] = 1,
    ["Violet Tragan"] = 1,
    ["Beached Sea Creature"] = 1,
    ["Skeletal Sea Turtle"] = 1,
    ["Nightmare Moss"] = 125,
    ["Dreamroot"] = 205,
    ["Moonroot"] = 250,
    ["Star Lotus"] = 250,
}

-- The item each node gives: its picture is what the minimap icon shows.
local NODE_ITEMS = {
    ["Copper Vein"] = 2770,
    ["Tin Vein"] = 2771,
    ["Incendicite Mineral Vein"] = 3340,
    ["Silver Vein"] = 2775,
    ["Ooze Covered Silver Vein"] = 2775,
    ["Lesser Bloodstone Deposit"] = 4278,
    ["Iron Deposit"] = 2772,
    ["Indurium Mineral Vein"] = 5833,
    ["Gold Vein"] = 2776,
    ["Ooze Covered Gold Vein"] = 2776,
    ["Mithril Deposit"] = 3858,
    ["Ooze Covered Mithril Deposit"] = 3858,
    ["Truesilver Deposit"] = 7911,
    ["Ooze Covered Truesilver Deposit"] = 7911,
    ["Dark Iron Deposit"] = 11370,
    ["Small Thorium Vein"] = 10620,
    ["Ooze Covered Thorium Vein"] = 10620,
    ["Rich Thorium Vein"] = 10620,
    ["Ooze Covered Rich Thorium Vein"] = 10620,
    ["Small Obsidian Chunk"] = 22202,
    ["Large Obsidian Chunk"] = 22203,
    ["Poor Copper Vein"] = 2770,
    ["Cold Iron Deposit"] = 219401,
    ["Fool's Gold Vein"] = 219445,
    ["Starsilver Vein"] = 219486,
    ["Greater Moonstone Formation"] = 219515,
    ["Hakkari Thorium Vein"] = 10620,
    ["Heavy Thorium Vein"] = 248815,
    ["Peacebloom"] = 2447,
    ["Silverleaf"] = 765,
    ["Earthroot"] = 2449,
    ["Mageroyal"] = 785,
    ["Briarthorn"] = 2450,
    ["Stranglekelp"] = 3820,
    ["Bruiseweed"] = 2453,
    ["Wild Steelbloom"] = 3355,
    ["Grave Moss"] = 3369,
    ["Kingsblood"] = 3356,
    ["Liferoot"] = 3357,
    ["Fadeleaf"] = 3818,
    ["Goldthorn"] = 3821,
    ["Khadgar's Whisker"] = 3358,
    ["Wintersbite"] = 3819,
    ["Firebloom"] = 4625,
    ["Purple Lotus"] = 8831,
    ["Arthas' Tears"] = 8836,
    ["Sungrass"] = 8838,
    ["Blindweed"] = 8839,
    ["Ghost Mushroom"] = 8845,
    ["Gromsblood"] = 8846,
    ["Golden Sansam"] = 13464,
    ["Dreamfoil"] = 13463,
    ["Mountain Silversage"] = 13465,
    ["Plaguebloom"] = 13466,
    ["Icecap"] = 13467,
    ["Black Lotus"] = 13468,
    ["Wilted Peacebloom"] = 2447,
    ["Stunted Silverleaf"] = 765,
    ["Hyjal Silphium"] = 274979,
    ["Tomb Weed"] = 286204,
    ["Doom Weed"] = 13702,
    ["Gloom Weed"] = 12737,
    ["Incendia Agave"] = 12732,
    ["Serpentbloom"] = 5339,
    ["Violet Tragan"] = 8526,
    ["Beached Sea Creature"] = 12242,
    ["Skeletal Sea Turtle"] = 12289,
    ["Nightmare Moss"] = 219399,
    ["Dreamroot"] = 219444,
    ["Moonroot"] = 219514,
    ["Star Lotus"] = 219454,
}

local db
local tracked = {} -- kinds tracked right now, { herb = true }
local sweep -- the sweep in progress, or nil
local wait = 0 -- seconds until the next sweep
local trustMissesAt = 0
local swapTimer = 0
local lootOpen = false
local grid, gridWidth, gridSquare
local icons = {}
local stats = { sweeps = 0, lastDots = 0, lastError = nil, hovered = 0 }
local lastGather -- { name, at }: the node your last gathering cast was aimed at

-- True on clients that no longer let addons probe the minimap.
local function ProbingBlocked()
    local build = GetBuildInfo and tonumber((select(2, GetBuildInfo())))
    return build ~= nil and build >= PROBING_BLOCKED_FROM_BUILD
end

local holder = CreateFrame("Frame", "DufforthTweaksHelperNodesFrame", Minimap)

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. message)
end

local function Usable(value)
    if value == nil then
        return false
    end
    if issecretvalue and issecretvalue(value) then
        return false
    end
    return true
end

local function IsSquare()
    return GetMinimapShape ~= nil and GetMinimapShape() == "SQUARE"
end

local function KindOf(name)
    return (db.custom and db.custom[name]) or NODES[name]
end

-- ---------------------------------------------------------------------------
-- Where things are. East and north are yards on the current zone map; offsets
-- are minimap pixels from its center, x right and y up.
-- ---------------------------------------------------------------------------

local view = {}

local function ReadView()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not Usable(mapID) then
        return nil
    end
    local position = C_Map.GetPlayerMapPosition(mapID, "player")
    if not Usable(position) then
        return nil
    end
    local mapWidth, mapHeight = C_Map.GetMapWorldSize(mapID)
    local radius, width = C_Minimap.GetViewRadius(), Minimap:GetWidth()
    if not (Usable(mapWidth) and Usable(mapHeight) and Usable(radius) and Usable(width)) then
        return nil
    end
    if mapWidth <= 0 or mapHeight <= 0 or radius <= 0 or width <= 0 then
        return nil
    end
    local facing = 0
    if C_CVar.GetCVarBool("rotateMinimap") then
        facing = GetPlayerFacing()
        if not Usable(facing) then
            return nil
        end
    end
    view.mapID = mapID
    view.east = position.x * mapWidth
    view.north = -position.y * mapHeight
    view.pixelsPerYard = width / (2 * radius)
    view.half = width / 2
    view.cos, view.sin = math.cos(facing), math.sin(facing)
    return view
end

local function WorldToOffset(east, north, v)
    local dx, dy = east - v.east, north - v.north
    return (dx * v.cos + dy * v.sin) * v.pixelsPerYard, (dy * v.cos - dx * v.sin) * v.pixelsPerYard
end

local function OffsetToWorld(ox, oy, v)
    local x, y = ox / v.pixelsPerYard, oy / v.pixelsPerYard
    return v.east + x * v.cos - y * v.sin, v.north + x * v.sin + y * v.cos
end

-- ---------------------------------------------------------------------------
-- Tracking
-- ---------------------------------------------------------------------------

local function KindOfTexture(texture)
    if not Usable(texture) then
        return nil
    end
    return FIND_TEXTURES[texture] or FIND_TEXTURES[string.lower(tostring(texture))]
end

local function RefreshTracking()
    local now = {}
    if C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo then
        for index = 1, C_Minimap.GetNumTrackingTypes() do
            local info = C_Minimap.GetTrackingInfo(index)
            if Usable(info) and Usable(info.active) and info.active then
                local kind = (Usable(info.spellID) and FIND_SPELLS[info.spellID])
                    or (Usable(info.name) and FIND_NAMES[info.name]) or KindOfTexture(info.texture)
                if kind then
                    now[kind] = true
                end
            end
        end
    elseif GetTrackingTexture then
        local kind = KindOfTexture(GetTrackingTexture())
        if kind then
            now[kind] = true
        end
    end
    local changed = now.herb ~= tracked.herb or now.ore ~= tracked.ore
    tracked = now
    return changed
end

-- ---------------------------------------------------------------------------
-- Sweeping the minimap
-- ---------------------------------------------------------------------------

local function BuildGrid(width, square)
    grid = {}
    gridWidth, gridSquare = width, square
    local half = width / 2
    local cells = math.floor(width / GRID_STEP)
    for column = 0, cells do
        for row = 0, cells do
            local ox, oy = column * GRID_STEP - half, row * GRID_STEP - half
            if square or ox * ox + oy * oy <= half * half then
                grid[#grid + 1] = { ox, oy }
            end
        end
    end
end

local function CanSweep()
    return Minimap:IsVisible() and not InCombatLockdown() and not Minimap:IsMouseOver()
        and Minimap:GetLeft() ~= nil
end

local function CleanLine(text)
    text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    text = string.gsub(text, "|r", "")
    text = string.gsub(text, "|T.-|t", "")
    text = string.gsub(text, "|A.-|a", "")
    return string.match(text, "^%s*(.-)%s*$")
end

-- Hits that touch form one cluster, which is one dot on the minimap.
local function AddHit(name, east, north, linkYards)
    local clusters = sweep.clusters[name]
    if not clusters then
        clusters = {}
        sweep.clusters[name] = clusters
    end
    local home
    local limit = linkYards * linkYards
    for index = #clusters, 1, -1 do
        local cluster = clusters[index]
        local touches = false
        for _, point in ipairs(cluster) do
            local dx, dy = point[1] - east, point[2] - north
            if dx * dx + dy * dy <= limit then
                touches = true
                break
            end
        end
        if touches then
            if home then
                for _, point in ipairs(cluster) do
                    home[#home + 1] = point
                end
                table.remove(clusters, index)
            else
                home = cluster
            end
        end
    end
    if not home then
        home = {}
        clusters[#clusters + 1] = home
    end
    home[#home + 1] = { east, north }
end

local function ReadNamesAt(ox, oy, v, left, bottom, scale)
    Minimap:UpdateMouseoverAtPoint((left + v.half + ox) * scale, (bottom + v.half + oy) * scale)
    local data = C_TooltipInfo.GetMinimapMouseover()
    if not Usable(data) or not Usable(data.lines) then
        return
    end
    for _, line in ipairs(data.lines) do
        local text = Usable(line) and line.leftText
        if text and Usable(text) then
            for part in string.gmatch(text, "[^\n]+") do
                local name = CleanLine(part)
                if name ~= "" then
                    if KindOf(name) then
                        local east, north = OffsetToWorld(ox, oy, v)
                        AddHit(name, east, north, LINK_PIXELS / v.pixelsPerYard)
                    else
                        db.unknown[name] = true
                    end
                end
            end
        end
    end
end

local function ProbeBatch(v)
    local left, bottom, scale = Minimap:GetLeft(), Minimap:GetBottom(), Minimap:GetEffectiveScale()
    local last = math.min(sweep.at + PROBES_PER_FRAME - 1, #grid)
    for index = sweep.at, last do
        local point = grid[index]
        ReadNamesAt(point[1], point[2], v, left, bottom, scale)
    end
    sweep.at = last + 1
end

local function FindPin(name, east, north, reach, matched)
    local best, bestDistance
    for _, pin in ipairs(db.pins) do
        if pin.mapID == view.mapID and pin.name == name and not matched[pin] then
            local dx, dy = pin.east - east, pin.north - north
            local distance = dx * dx + dy * dy
            if distance <= reach * reach and (not best or distance < bestDistance) then
                best, bestDistance = pin, distance
            end
        end
    end
    return best
end

local function ClearGatheredNear(name, east, north, reach, mapID, now)
    for index = #db.gathered, 1, -1 do
        local marker = db.gathered[index]
        if marker.mapID == mapID and marker.name == name and now - marker.gatheredAt >= GATHERED_GRACE then
            local dx, dy = marker.east - east, marker.north - north
            if dx * dx + dy * dy <= reach * reach then
                table.remove(db.gathered, index)
            end
        end
    end
end

local function FinishSweep(v)
    local matched = {}
    local dots = 0
    local reach = math.max(MATCH_YARDS, MATCH_PIXELS / v.pixelsPerYard)
    local now = time()

    for name, clusters in pairs(sweep.clusters) do
        for _, cluster in ipairs(clusters) do
            dots = dots + 1
            local sumEast, sumNorth = 0, 0
            for _, point in ipairs(cluster) do
                sumEast, sumNorth = sumEast + point[1], sumNorth + point[2]
            end
            local east, north = sumEast / #cluster, sumNorth / #cluster
            local ox, oy = WorldToOffset(east, north, v)
            local interior = ox * ox + oy * oy <= (v.half * INTERIOR) ^ 2
            local pin = FindPin(name, east, north, reach, matched)
            if pin then
                if interior then
                    pin.east, pin.north = east, north
                end
            elseif #db.pins < 500 then
                pin = { name = name, kind = KindOf(name), mapID = v.mapID, east = east, north = north }
                db.pins[#db.pins + 1] = pin
            end
            if pin then
                ClearGatheredNear(name, east, north, reach, v.mapID, now)
                pin.seenAt = now
                pin.misses = 0
                matched[pin] = true
            end
        end
    end

    -- A tracked dot that is plainly not there any more was taken by someone else.
    if GetTime() >= trustMissesAt then
        local limit = (v.half * MISS_INTERIOR) ^ 2
        for index = #db.pins, 1, -1 do
            local pin = db.pins[index]
            if pin.mapID == v.mapID and sweep.kinds[pin.kind] and not matched[pin] then
                local ox, oy = WorldToOffset(pin.east, pin.north, v)
                if ox * ox + oy * oy <= limit then
                    pin.misses = (pin.misses or 0) + 1
                    if pin.misses >= MISSES_TO_REMOVE then
                        table.remove(db.pins, index)
                    end
                end
            end
        end
    end

    stats.sweeps = stats.sweeps + 1
    stats.lastDots = dots
end

local function RunSweep(elapsed)
    if ProbingBlocked() or not (tracked.herb or tracked.ore) then
        sweep = nil
        return
    end
    if not CanSweep() then
        sweep = nil
        wait = 0.25
        return
    end
    local v = ReadView()
    if not v then
        sweep = nil
        wait = SCAN_INTERVAL
        return
    end

    if not sweep then
        wait = wait - elapsed
        if wait > 0 then
            return
        end
        local width, square = Minimap:GetWidth(), IsSquare()
        if width ~= gridWidth or square ~= gridSquare then
            BuildGrid(width, square)
        end
        sweep = { at = 1, clusters = {}, mapID = v.mapID, kinds = { herb = tracked.herb, ore = tracked.ore } }
    elseif sweep.mapID ~= v.mapID then
        sweep = nil
        return
    end

    Minimap:SetUsingSoftCursor(true)
    local ok, err = pcall(ProbeBatch, v)
    Minimap:SetUsingSoftCursor(false)
    if not ok then
        stats.lastError = tostring(err)
        sweep = nil
        wait = 5
        return
    end
    if sweep.at > #grid then
        FinishSweep(v)
        sweep = nil
        wait = SCAN_INTERVAL
    end
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

-- The node's own item picture, or the general herb or ore picture if it has none.
local itemPictures = {}

local function PictureFor(pin)
    local picture = itemPictures[pin.name]
    if picture then
        return picture
    end
    local item = NODE_ITEMS[pin.name]
    if item and C_Item and C_Item.GetItemIconByID then
        picture = C_Item.GetItemIconByID(item)
        if Usable(picture) and picture then
            itemPictures[pin.name] = picture
            return picture
        end
    end
    return STYLE[pin.kind].icon
end

-- ---------------------------------------------------------------------------
-- Can you gather it? Skill, and the color for how likely a skill point is.
-- ---------------------------------------------------------------------------

local SKILL_LINES = { herb = 182, ore = 186 }
local PROFESSION_NAMES = { herb = "Herbalism", ore = "Mining" }
local YELLOW_AT, GREEN_AT, GRAY_AT = 25, 50, 100
local RED = { r = 1, g = 0.13, b = 0.13 }
local DIFFICULTY = {
    orange = { r = 1, g = 0.5, b = 0.25, chance = "Always gives a skill point" },
    yellow = { r = 1, g = 1, b = 0, chance = "Usually gives a skill point" },
    green = { r = 0.25, g = 0.75, b = 0.25, chance = "Rarely gives a skill point" },
    gray = { r = 0.5, g = 0.5, b = 0.5, chance = "Gives no skill point" },
}

-- Your skill with this profession, bonuses included: a number, or false if you
-- don't have it, or nil if the game can't tell us.
local function ReadSkill(kind)
    local line = SKILL_LINES[kind]
    if GetProfessions and GetProfessionInfo then
        local first, second = GetProfessions()
        for _, index in ipairs({ first or 0, second or 0 }) do
            if index ~= 0 then
                local _, _, rank, _, _, _, skillLine, modifier = GetProfessionInfo(index)
                if skillLine == line and Usable(rank) then
                    return rank + (Usable(modifier) and modifier or 0)
                end
            end
        end
        return false
    end
    if C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID then
        local info = C_SkillInfo.GetSkillLineInfoByID(line)
        if Usable(info) and Usable(info.rank) and info.rank > 0 then
            return info.rank + (Usable(info.modifier) and info.modifier or 0)
        end
        return false
    end
    return nil
end

local function DifficultyColor(skill, need)
    -- Nodes that need skill 1 change color at 25, 50 and 100, not one point later.
    local over = skill - (need <= 1 and 0 or need)
    if over < YELLOW_AT then
        return DIFFICULTY.orange
    elseif over < GREEN_AT then
        return DIFFICULTY.yellow
    elseif over < GRAY_AT then
        return DIFFICULTY.green
    end
    return DIFFICULTY.gray
end

-- The color for this node's name, and the lines that explain it.
local function DescribeGather(name, kind)
    local need = NODE_SKILLS[name]
    if not need then
        return nil
    end
    local profession = PROFESSION_NAMES[kind]
    local skill = ReadSkill(kind)
    if skill == nil then
        return nil, "Requires " .. profession .. " " .. need
    elseif skill == false then
        return RED, "Cannot gather: requires " .. profession .. " " .. need,
            "You have not learned " .. profession
    elseif skill < need then
        return RED, string.format("Cannot gather: you need %d more %s", need - skill, profession),
            string.format("Your skill %d, requires %d", skill, need)
    end
    local color = DifficultyColor(skill, need)
    return color, color.chance, string.format("Your %s %d, requires %d", profession, skill, need)
end

local function AddGatherLines(tooltip, name, kind, withName)
    local color, first, second = DescribeGather(name, kind)
    if not first then
        return false
    end
    local r, g, b = 0.8, 0.8, 0.8
    if color then
        r, g, b = color.r, color.g, color.b
    end
    tooltip:AddLine(withName and (name .. ": " .. first) or first, r, g, b)
    if second then
        tooltip:AddLine(second, r, g, b)
    end
    return true
end

-- Hovering a tracked dot that has no icon on it shows the same information.
-- Remembers a node where the mouse is: a new icon, or a better position for one already there.
-- Seeing it again also clears a gathered marker of the same name there: it has come back.
local function LearnAtCursor(name, kind)
    local v = ReadView()
    if not v or not GetCursorPosition or not Minimap:GetLeft() then
        return
    end
    local x, y = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local ox = x / scale - Minimap:GetLeft() - v.half
    local oy = y / scale - Minimap:GetBottom() - v.half
    if ox * ox + oy * oy > v.half * v.half * 1.2 then
        return
    end
    local east, north = OffsetToWorld(ox, oy, v)
    local reach = math.max(MATCH_YARDS, MATCH_PIXELS / v.pixelsPerYard)
    local now = time()
    local pin = FindPin(name, east, north, reach, {})
    if pin then
        local weight = math.min(pin.hovers or 1, HOVER_WEIGHT_CAP)
        pin.east = (pin.east * weight + east) / (weight + 1)
        pin.north = (pin.north * weight + north) / (weight + 1)
        pin.hovers = (pin.hovers or 1) + 1
    elseif #db.pins < 500 then
        pin = { name = name, kind = kind, mapID = v.mapID, east = east, north = north, hovers = 1 }
        db.pins[#db.pins + 1] = pin
        stats.hovered = stats.hovered + 1
    end
    if pin then
        pin.seenAt, pin.misses = now, 0
        ClearGatheredNear(name, east, north, reach, v.mapID, now)
    end
end

local function OnGameMinimapTooltip(tooltip, data)
    if not db or not db.enabled or not Usable(data) or not Usable(data.lines) then
        return
    end
    local added = false
    local mouseOnMap = Minimap:IsMouseOver()
    for _, line in ipairs(data.lines) do
        local text = Usable(line) and line.leftText
        if text and Usable(text) then
            for part in string.gmatch(text, "[^\n]+") do
                local name = CleanLine(part)
                local kind = KindOf(name)
                if kind and mouseOnMap then
                    LearnAtCursor(name, kind)
                end
                if kind and AddGatherLines(tooltip, name, kind, true) then
                    added = true
                end
            end
        end
    end
    if added then
        tooltip:Show()
    end
end

local function ShowMarkerTooltip(icon)
    local marker = icon.marker
    local minutes = math.floor((time() - marker.gatheredAt) / 60)
    GameTooltip:SetOwner(icon, "ANCHOR_LEFT")
    GameTooltip:SetText(marker.name, 0.7, 0.7, 0.7)
    GameTooltip:AddLine(minutes < 1 and "Gathered just now" or ("Gathered " .. minutes .. " min ago"), 0.8, 0.8, 0.8)
    GameTooltip:AddLine("The game doesn't share respawn times. When the dot is back, hover it to clear this.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

local function ShowPinTooltip(icon)
    if icon.marker then
        ShowMarkerTooltip(icon)
        return
    end
    local pin = icon.pin
    if not pin then
        return
    end
    local style = STYLE[pin.kind]
    GameTooltip:SetOwner(icon, "ANCHOR_LEFT")
    local color = DescribeGather(pin.name, pin.kind) or style
    GameTooltip:SetText(pin.name, color.r, color.g, color.b)
    AddGatherLines(GameTooltip, pin.name, pin.kind, false)
    local minutes = math.floor((time() - pin.seenAt) / 60)
    GameTooltip:AddLine(minutes < 1 and "Seen just now" or ("Last seen " .. minutes .. " min ago"), 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

local function NewIcon()
    local icon = CreateFrame("Frame", nil, holder)
    icon:SetFrameLevel(holder:GetFrameLevel()) -- under the minimap's buttons (mail, zoom, tracking)
    icon.art = icon:CreateTexture(nil, "OVERLAY")
    icon.art:SetAllPoints()
    icon.art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- Item pictures are square; the mask cuts them to a plain circle.
    -- If the game lacks the mask picture, skip it: a square icon beats an invisible one.
    if icon.CreateMaskTexture and icon.art.AddMaskTexture then
        icon.mask = icon:CreateMaskTexture()
        if icon.mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") ~= false then
            icon.mask:SetAllPoints(icon.art)
            icon.art:AddMaskTexture(icon.mask)
        else
            icon.mask = nil
        end
    end
    icon.label = icon:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    icon.label:SetPoint("LEFT", icon, "RIGHT", 1, 0)
    icon:EnableMouse(true)
    if icon.SetMouseClickEnabled then
        icon:SetMouseClickEnabled(false)
    end
    icon:SetScript("OnEnter", ShowPinTooltip)
    icon:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return icon
end

-- True when the same node already has an icon drawn this close, so duplicates don't pile up.
local function Crowded(placed, name, ox, oy, spacing)
    for _, spot in ipairs(placed) do
        if spot[3] == name then
            local dx, dy = spot[1] - ox, spot[2] - oy
            if dx * dx + dy * dy < spacing * spacing then
                return true
            end
        end
    end
    return false
end

local function Draw()
    local shown = 0
    local v = ReadView()
    local placed = {}
    if v then
        local size = db.size
        local spacing = size * 0.7
        local square = IsSquare()
        local reach = v.half - size * 0.75 - EDGE_MARGIN
        for _, pin in ipairs(db.pins) do
            if pin.mapID == v.mapID and shown < MAX_ICONS then
                local ox, oy = WorldToOffset(pin.east, pin.north, v)
                local inside
                if square then
                    inside = math.abs(ox) <= reach and math.abs(oy) <= reach
                else
                    inside = ox * ox + oy * oy <= reach * reach
                end
                if inside and not Crowded(placed, pin.name, ox, oy, spacing) then
                    placed[#placed + 1] = { ox, oy, pin.name }
                    shown = shown + 1
                    local icon = icons[shown]
                    if not icon then
                        icon = NewIcon()
                        icons[shown] = icon
                    end
                    local style = STYLE[pin.kind]
                    icon.pin = pin
                    icon.marker = nil
                    icon.art:SetDesaturated(false)
                    icon:SetSize(size, size)
                    icon.art:SetTexture(PictureFor(pin))
                    icon.label:SetText(pin.name)
                    icon.label:SetTextColor(style.r, style.g, style.b)
                    icon.label:SetShown(db.labels == true)
                    icon:ClearAllPoints()
                    icon:SetPoint("CENTER", Minimap, "CENTER", ox, oy)
                    icon:SetAlpha(tracked[pin.kind] and 1 or 0.8)
                    icon:Show()
                end
            end
        end

        -- Gathered markers: a gray picture with the minutes since you gathered it.
        local now = time()
        for _, marker in ipairs(db.gathered) do
            if marker.mapID == v.mapID and shown < MAX_ICONS then
                local ox, oy = WorldToOffset(marker.east, marker.north, v)
                local inside
                if square then
                    inside = math.abs(ox) <= reach and math.abs(oy) <= reach
                else
                    inside = ox * ox + oy * oy <= reach * reach
                end
                if inside and not Crowded(placed, marker.name, ox, oy, spacing) then
                    placed[#placed + 1] = { ox, oy, marker.name }
                    shown = shown + 1
                    local icon = icons[shown]
                    if not icon then
                        icon = NewIcon()
                        icons[shown] = icon
                    end
                    icon.pin = nil
                    icon.marker = marker
                    icon:SetSize(size, size)
                    icon.art:SetTexture(PictureFor(marker))
                    icon.art:SetDesaturated(true)
                    icon.label:SetText(math.floor((now - marker.gatheredAt) / 60) .. "m")
                    icon.label:SetTextColor(0.8, 0.8, 0.8)
                    icon.label:SetShown(true)
                    icon:ClearAllPoints()
                    icon:SetPoint("CENTER", Minimap, "CENTER", ox, oy)
                    icon:SetAlpha(0.6)
                    icon:Show()
                end
            end
        end
    end
    for index = shown + 1, #icons do
        icons[index].pin = nil
        icons[index].marker = nil
        icons[index]:Hide()
    end
end

local function ExpireOldPins()
    local oldestMarker = time() - db.gatheredMinutes * 60
    for index = #db.gathered, 1, -1 do
        if db.gathered[index].gatheredAt < oldestMarker then
            table.remove(db.gathered, index)
        end
    end
    if db.keepMinutes <= 0 then
        return
    end
    local oldest = time() - db.keepMinutes * 60
    for index = #db.pins, 1, -1 do
        if db.pins[index].seenAt < oldest then
            table.remove(db.pins, index)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Swapping between Find Herbs and Find Minerals
-- ---------------------------------------------------------------------------

local function IsOnCooldown(spellID)
    local start, duration
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(spellID)
        if Usable(info) then
            start, duration = info.startTime, info.duration
        end
    elseif GetSpellCooldown then
        start, duration = GetSpellCooldown(spellID)
    end
    return Usable(start) and Usable(duration) and start > 0 and duration > 0
end

-- Why a swap can't happen right now, in words, or nil when it can.
local function SwapBlockedBy()
    if not (IsPlayerSpell(FIND_HERBS) and IsPlayerSpell(FIND_MINERALS)) then
        return "this character needs both Herbalism and Mining"
    end
    if UnitAffectingCombat("player") or InCombatLockdown() then
        return "in combat"
    end
    if IsResting() then
        return "in a city or inn"
    end
    if IsInInstance() then
        return "in an instance"
    end
    if UnitIsDeadOrGhost("player") then
        return "dead"
    end
    if UnitOnTaxi("player") then
        return "on a flight path"
    end
    if IsStealthed() then
        return "stealthed"
    end
    if UnitCastingInfo("player") or UnitChannelInfo("player") then
        return "casting"
    end
    if lootOpen then
        return "looting"
    end
    if GetCursorInfo() then
        return "holding something on the cursor"
    end
    if UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDeadOrGhost("target") then
        return "targeting an enemy"
    end
    return nil
end

local function RunSwap(elapsed)
    if not db.swapEnabled then
        return
    end
    swapTimer = swapTimer + elapsed
    if swapTimer < db.swapSeconds or SwapBlockedBy() then
        return
    end
    local nextSpell = tracked.herb and FIND_MINERALS or FIND_HERBS
    if IsOnCooldown(nextSpell) then
        return
    end
    swapTimer = 0
    pcall(CastSpellByID, nextSpell)
end

local function DescribeSwap()
    if not db.swapEnabled then
        return "OFF"
    end
    local text = string.format("ON, every %g sec", db.swapSeconds)
    local blocked = SwapBlockedBy()
    return blocked and (text .. " (paused: " .. blocked .. ")") or text
end

local function SetSwapEnabled(enabled)
    db.swapEnabled = enabled
    swapTimer = db.swapSeconds -- the first swap happens as soon as it is allowed
    Print("tracking swap " .. DescribeSwap() .. ".")
end

local function HideAllIcons()
    for _, icon in ipairs(icons) do
        icon.pin = nil
        icon.marker = nil
        icon:Hide()
    end
end

local function SetEnabled(enabled)
    db.enabled = enabled
    sweep, wait = nil, 0
    if not enabled then
        HideAllIcons()
    end
    Print("herb and ore features " .. (enabled and "ON" or "OFF") .. ".")
end

-- ---------------------------------------------------------------------------
-- Gathering and events
-- ---------------------------------------------------------------------------

local function RemoveGatheredNode()
    local v = ReadView()
    if not v then
        return
    end
    local reach = math.max(LOOT_YARDS, 2 / v.pixelsPerYard)
    local bestIndex, bestDistance
    for index, pin in ipairs(db.pins) do
        if pin.mapID == v.mapID then
            local dx, dy = pin.east - v.east, pin.north - v.north
            local distance = dx * dx + dy * dy
            if distance <= reach * reach and (not bestIndex or distance < bestDistance) then
                bestIndex, bestDistance = index, distance
            end
        end
    end
    local spot
    if bestIndex then
        spot = table.remove(db.pins, bestIndex)
    elseif lastGather and GetTime() - lastGather.at <= GATHER_SECONDS then
        spot = { name = lastGather.name, kind = KindOf(lastGather.name), mapID = v.mapID, east = v.east, north = v.north }
    end
    lastGather = nil
    if spot and db.gatheredMinutes > 0 then
        db.gathered[#db.gathered + 1] = {
            name = spot.name, kind = spot.kind, mapID = spot.mapID,
            east = spot.east, north = spot.north, gatheredAt = time(),
        }
    end
    sweep, wait = nil, 0.5
end

local function PrintStatus()
    local missing = {}
    for label, available in pairs({
        ["Minimap:UpdateMouseoverAtPoint"] = Minimap.UpdateMouseoverAtPoint,
        ["Minimap:SetUsingSoftCursor"] = Minimap.SetUsingSoftCursor,
        ["C_TooltipInfo.GetMinimapMouseover"] = C_TooltipInfo and C_TooltipInfo.GetMinimapMouseover,
    }) do
        if not available then
            missing[#missing + 1] = label
        end
    end
    Print("game API: " .. (#missing == 0 and "ok" or ("MISSING " .. table.concat(missing, ", "))))
    local kinds = {}
    if tracked.herb then kinds[#kinds + 1] = "herbs" end
    if tracked.ore then kinds[#kinds + 1] = "ore" end
    Print("tracking now: " .. (#kinds > 0 and table.concat(kinds, " + ") or "nothing"))
    Print(string.format("saved icons: %d; sweeps this session: %d; dots in last sweep: %d",
        #db.pins, stats.sweeps, stats.lastDots))
    Print("position: " .. (ReadView() and "ok" or "not available here"))
    Print("features: " .. (db.enabled and "ON" or "OFF"))
    Print("tracking swap: " .. DescribeSwap())
    Print(string.format("gathered markers: %d (kept %d min)", #db.gathered, db.gatheredMinutes))
    Print("keep time: " .. (db.keepMinutes > 0 and (db.keepMinutes .. " min") or "until gathered"))
    if stats.lastError then
        Print("last error: " .. stats.lastError)
    end
end

-- For the Gather tab: is the game letting us read the minimap, and what was found.
DufforthTweaksHelperNodes = {
    Status = function()
        if not db then
            return nil
        end
        local kinds = {}
        if tracked.herb then kinds[#kinds + 1] = "herbs" end
        if tracked.ore then kinds[#kinds + 1] = "ore" end
        return {
            blocked = ProbingBlocked(),
            hovered = stats.hovered,
            gathered = #db.gathered,
            api = Minimap.UpdateMouseoverAtPoint ~= nil and Minimap.SetUsingSoftCursor ~= nil
                and C_TooltipInfo ~= nil and C_TooltipInfo.GetMinimapMouseover ~= nil,
            enabled = db.enabled == true,
            tracking = #kinds > 0 and table.concat(kinds, " and ") or nil,
            icons = #db.pins,
            lastDots = stats.lastDots,
            sweeps = stats.sweeps,
            lastError = stats.lastError,
        }
    end,
}

local function HandleSlash(input)
    local command, rest = string.match(input or "", "^%s*(%S*)%s*(.-)%s*$")
    command = string.lower(command or "")

    if command == "status" then
        PrintStatus()
    elseif command == "on" or command == "off" or command == "toggle" then
        if command == "toggle" then
            SetEnabled(not db.enabled)
        else
            SetEnabled(command == "on")
        end
    elseif command == "swap" then
        local option = string.lower(rest)
        if option == "" or option == "toggle" then
            SetSwapEnabled(not db.swapEnabled)
        elseif option == "on" or option == "off" then
            SetSwapEnabled(option == "on")
        elseif tonumber(option) then
            db.swapSeconds = math.max(MIN_SWAP_SECONDS, math.min(MAX_SWAP_SECONDS, tonumber(option)))
            Print(string.format("tracking swap time is now %g sec.", db.swapSeconds))
        else
            Print("use: /nk swap, /nk swap on, /nk swap off, or /nk swap <seconds>")
        end
    elseif command == "size" and tonumber(rest) then
        db.size = math.max(MIN_SIZE, math.min(MAX_SIZE, math.floor(tonumber(rest))))
        Print("icon size is now " .. db.size .. ".")
    elseif command == "keep" and tonumber(rest) then
        db.keepMinutes = math.max(0, math.floor(tonumber(rest)))
        Print(db.keepMinutes > 0 and ("unseen icons are removed after " .. db.keepMinutes .. " min.")
            or "icons now stay until you gather them.")
    elseif command == "gathered" and tonumber(rest) then
        db.gatheredMinutes = math.max(0, math.floor(tonumber(rest)))
        ExpireOldPins()
        Print(db.gatheredMinutes > 0 and ("gathered markers stay for " .. db.gatheredMinutes .. " min.")
            or "gathered markers are off.")
    elseif command == "names" then
        db.labels = not db.labels
        Print("names beside icons " .. (db.labels and "ON" or "OFF") .. ".")
    elseif command == "clear" then
        db.pins = {}
        db.gathered = {}
        sweep, wait = nil, 0
        Print("all icons cleared.")
    elseif command == "add" then
        local kind, name = string.match(rest, "^(%a+)%s+(.+)$")
        kind = kind and string.lower(kind)
        if name and STYLE[kind] then
            db.custom[name] = kind
            db.unknown[name] = nil
            Print("added " .. name .. " as " .. kind .. ".")
        else
            Print("use: /nk add herb <name> or /nk add ore <name>")
        end
    elseif command == "unknown" then
        Print("names seen on the minimap that are not herbs or ore:")
        for name in pairs(db.unknown) do
            Print("  " .. name)
        end
    else
        Print("/nk status - check that it is working")
        Print("/nk swap - start or stop swapping tracking (also: /nk swap on, /nk swap off)")
        Print("/nk swap <2-60> - seconds between swaps")
        Print("/nk toggle - start or stop icons, scanning and swapping (also: /nk on, /nk off)")
        Print("/nk size <6-20> - icon size (10 matches the yellow tracking dots)")
        Print("/nk names - show or hide names beside the icons")
        Print("/nk gathered <minutes> - how long gathered markers stay (0 = off)")
        Print("/nk keep <minutes> - remove unseen icons after this long (0 = never)")
        Print("/nk clear - remove all icons")
        Print("/nk add herb|ore <name> - add a node missing from the list")
        Print("/nk unknown - list other names seen on the minimap")
    end
end

local function OnLogin()
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    DufforthTweaksHelperDB.nodes = DufforthTweaksHelperDB.nodes or {}
    -- Saved by the tent timer, which no longer exists.
    DufforthTweaksHelperDB.chars, DufforthTweaksHelperDB.position, DufforthTweaksHelperDB.hidden = nil, nil, nil
    DufforthTweaksHelperDB.collapsed, DufforthTweaksHelperDB.offlineTicks, DufforthTweaksHelperDB.auraName = nil, nil, nil
    db = DufforthTweaksHelperDB.nodes
    db.pins = db.pins or {}
    db.custom = db.custom or {}
    db.unknown = {}
    -- The old default (14) was too big next to the game's tracking dots.
    if not db.size or db.size == OLD_DEFAULT_SIZE then
        db.size = DEFAULT_SIZE
    end
    db.size = math.max(MIN_SIZE, math.min(MAX_SIZE, db.size))
    if db.keepMinutes == nil or db.keepMinutes == OLD_DEFAULT_KEEP_MINUTES then
        db.keepMinutes = DEFAULT_KEEP_MINUTES
    end
    db.swapSeconds = db.swapSeconds or DEFAULT_SWAP_SECONDS
    db.gathered = db.gathered or {}
    db.gatheredMinutes = db.gatheredMinutes or DEFAULT_GATHERED_MINUTES
    if db.enabled == nil then
        db.enabled = true
    end

    RefreshTracking()
    ExpireOldPins()

    if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.MinimapMouseover then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.MinimapMouseover, OnGameMinimapTooltip)
    end

    SLASH_DUFFORTHTWEAKSHELPERNODES1 = "/nk"
    SlashCmdList.DUFFORTHTWEAKSHELPERNODES = HandleSlash

    local expireTimer = 0
    holder:SetScript("OnUpdate", function(_, elapsed)
        if not db.enabled then
            return
        end
        local ok, err = pcall(RunSwap, elapsed)
        if ok then ok, err = pcall(RunSweep, elapsed) end
        if ok then ok, err = pcall(Draw) end
        if not ok then
            stats.lastError = tostring(err)
        end
        expireTimer = expireTimer + elapsed
        if expireTimer >= 5 then
            expireTimer = 0
            ExpireOldPins()
        end
    end)
end

holder:SetAllPoints(Minimap)
holder:RegisterEvent("PLAYER_LOGIN")
holder:RegisterEvent("MINIMAP_UPDATE_TRACKING")
holder:RegisterEvent("MINIMAP_UPDATE_ZOOM")
holder:RegisterEvent("LOOT_CLOSED")
holder:RegisterEvent("LOOT_OPENED")
holder:RegisterEvent("UNIT_SPELLCAST_SENT")
holder:RegisterEvent("PLAYER_ENTERING_WORLD")

holder:SetScript("OnEvent", function(_, event, unit, target)
    if event == "PLAYER_LOGIN" then
        OnLogin()
    elseif not db then
        return
    elseif event == "MINIMAP_UPDATE_TRACKING" then
        if RefreshTracking() then
            -- Dots take a moment to change after a swap, so don't count them as gone yet.
            trustMissesAt = GetTime() + SWAP_GRACE
            sweep, wait = nil, SWAP_SETTLE
        end
    elseif event == "UNIT_SPELLCAST_SENT" then
        -- Herb Gathering and Mining are aimed at the node, so the cast names it.
        if unit == "player" and Usable(target) and target and KindOf(CleanLine(target)) then
            lastGather = { name = CleanLine(target), at = GetTime() }
        end
    elseif event == "LOOT_OPENED" then
        lootOpen = true
    elseif event == "LOOT_CLOSED" then
        lootOpen = false
        RemoveGatheredNode()
    else
        sweep, wait = nil, 0.25
    end
end)
