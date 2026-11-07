import os, sys
import lupa.lua51 as L

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = open(os.path.join(ROOT, "addon", "TentTimer", "Nodes.lua"), encoding="utf-8").read()

# A fake game: world nodes in yards, a 140 px minimap of radius 200 yards.
MOCK = r"""
NOW, UPTIME = 1000000, 500
MAP_W, MAP_H = 5000, 5000
PLAYER = { x = 0.5, y = 0.5, facing = 0 }
ROTATE, COMBAT, OVER = false, false, false
TRACK = { {spellID=2383, active=true}, {spellID=2580, active=false}, {spellID=1, active=true} }
WORLD = {}   -- { name, kind, east, north }
DOT_PX = 12
CHAT = {}
time = function() return NOW end
GetTime = function() return UPTIME end
InCombatLockdown = function() return COMBAT end
GetPlayerFacing = function() return PLAYER.facing end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) CHAT[#CHAT+1] = m end }
SlashCmdList = {}
C_CVar = { GetCVarBool = function() return ROTATE end }
C_Map = {
  GetBestMapForUnit = function() return MAPID or 1415 end,
  GetPlayerMapPosition = function() return { x = PLAYER.x, y = PLAYER.y } end,
  GetMapWorldSize = function() return MAP_W, MAP_H end,
}
RADIUS = 200
C_Minimap = {
  GetViewRadius = function() return RADIUS end,
  GetNumTrackingTypes = function() return #TRACK end,
  GetTrackingInfo = function(i) return TRACK[i] end,
}
local function isTracked(kind)
  return TRACK[kind == "herb" and 1 or 2].active
end
function playerWorld() return PLAYER.x * MAP_W, -PLAYER.y * MAP_H end
function worldToPx(east, north)
  local px, py = playerWorld()
  local ppy = 70 / RADIUS
  local c, s = math.cos(PLAYER.facing), math.sin(PLAYER.facing)
  local dx, dy = east - px, north - py
  if not ROTATE then c, s = 1, 0 end
  return (dx * c + dy * s) * ppy, (dy * c - dx * s) * ppy
end
local probe = {}
PROBES, SOFT_ON_DURING = 0, true
Minimap = {
  scale = 1,
  GetWidth = function() return 140 end,
  GetLeft = function() return 1000 end,
  GetBottom = function() return 600 end,
  GetEffectiveScale = function(self) return self.scale end,
  IsVisible = function() return true end,
  IsMouseOver = function() return OVER end,
  GetFrameLevel = function() return 1 end,
  SetUsingSoftCursor = function(_, v) SOFT = v end,
  UpdateMouseoverAtPoint = function(self, x, y)
    if not SOFT then SOFT_ON_DURING = false end
    PROBES = PROBES + 1
    probe.ox = x / self.scale - 1000 - 70
    probe.oy = y / self.scale - 600 - 70
  end,
}
C_TooltipInfo = { GetMinimapMouseover = function()
  local lines = {}
  for _, n in ipairs(WORLD) do
    if isTracked(n.kind) then
      local ox, oy = worldToPx(n.east, n.north)
      if (ox-probe.ox)^2 + (oy-probe.oy)^2 <= DOT_PX^2 then
        lines[#lines+1] = { leftText = "|cffffffff" .. n.name .. "|r" }
      end
    end
  end
  for _, p in ipairs(PARTY or {}) do
    local ox, oy = worldToPx(p.east, p.north)
    if (ox-probe.ox)^2 + (oy-probe.oy)^2 <= DOT_PX^2 then lines[#lines+1] = { leftText = p.name } end
  end
  if #lines == 0 then return nil end
  return { lines = lines }
end }
TIP = { lines = {} }
GameTooltip = setmetatable({}, { __index = function() return function() end end })
function GameTooltip:SetOwner() TIP = { lines = {} } end
function GameTooltip:SetText(t, r, g, b) TIP.title, TIP.r, TIP.g, TIP.b = t, r, g, b end
function GameTooltip:AddLine(t, r, g, b) TIP.lines[#TIP.lines+1] = { text = t, r = r, g = g, b = b } end
function GameTooltip:Show() TIP.shown = true end
function TIPTEXT() local o = {}; for _, l in ipairs(TIP.lines) do o[#o+1] = l.text end; return table.concat(o, " | ") end
PROF = { { line = 182, rank = 0, mod = 0 }, { line = 186, rank = 0, mod = 0 } }
GetProfessions = function() return PROF[1] and 1 or nil, PROF[2] and 2 or nil end
GetProfessionInfo = function(i) local p = PROF[i]; return "Prof", 1, p.rank, 300, 1, 1, p.line, p.mod end
Enum = { TooltipDataType = { MinimapMouseover = 99 } }
TooltipDataProcessor = { AddTooltipPostCall = function(kind, f) GAMEHOOK = f end }
function HOVER(name) local i = FIND(name); i.scripts.OnEnter(i) end
ICONS, FONTS = {}, {}
UnitName = function() return "Dufforth" end
GetRealmName = function() return "CAMWOW US1 Realm 4 PvP" end
UnitClass = function() return "Warrior", "WARRIOR" end
RAID_CLASS_COLORS = {}
UnitAura = function() end
C_Timer = { After = function(_, f) f() end, NewTicker = function() end }
local function tex()
  local t = {}
  function t:SetTexture(v) self.texture = v end
  function t:SetVertexColor(r,g,b) self.r, self.g, self.b = r, g, b end
  function t:SetShown(v) self.visible = v end
  function t:SetDesaturated(v) self.gray = v end
  function t:AddMaskTexture(m) self.mask = m end
  return setmetatable(t, { __index = function() return function() end end })
end
function CreateFrame(kind, name, parent)
  local f = { scripts = {}, shown = true, events = {} }
  function f:SetScript(k, v) self.scripts[k] = v end
  function f:CreateTexture() return tex() end
  function f:CreateMaskTexture() return tex() end
  function f:CreateFontString() local s = tex(); function s:SetText(v) self.text = v end; FONTS[#FONTS+1] = s; return s end
  function f:SetPoint(p, rel, rp, x, y) if rel == Minimap then self.ox, self.oy = x, y end end
  function f:SetAlpha(a) self.alpha = a end
  function f:Show() self.shown = true end
  function f:Hide() self.shown = false end
  if name == "TentTimerNodesFrame" then HOLDER = f elseif name == "TentTimerFrame" then TENTFRAME = f else ICONS[#ICONS+1] = f end
  return setmetatable(f, { __index = function(_, k) if k == "marker" or k == "pin" then return nil end return function() end end })
end
UIParent = {}
KNOWN = { [2383] = true, [2580] = true }
C_Item = { GetItemIconByID = function(id) if NO_ITEM_ICONS then return nil end return 100000 + id end }
RESTING, INSTANCE, DEAD, TAXI, STEALTH, CASTING, CURSOR, ENEMY = false, false, false, false, false, false, false, false
GCD_UNTIL, CASTS = 0, {}
IsPlayerSpell = function(id) return KNOWN[id] end
IsResting = function() return RESTING end
IsInInstance = function() return INSTANCE end
UnitAffectingCombat = function() return COMBAT end
UnitIsDeadOrGhost = function(u) return u == "player" and DEAD end
UnitOnTaxi = function() return TAXI end
IsStealthed = function() return STEALTH end
UnitCastingInfo = function() return CASTING and "Herb Gathering" or nil end
UnitChannelInfo = function() end
GetCursorInfo = function() return CURSOR and "item" or nil end
UnitExists = function() return ENEMY end
UnitCanAttack = function() return ENEMY end
C_Spell = { GetSpellCooldown = function()
  if UPTIME < GCD_UNTIL then return { startTime = UPTIME, duration = 1.5 } end
  return { startTime = 0, duration = 0 }
end }
CastSpellByID = function(id)
  CASTS[#CASTS+1] = id
  GCD_UNTIL = UPTIME + 1.5
  SWAP(id == 2383, id == 2580)
end
function FIRE(e, a) HOLDER.scripts.OnEvent(HOLDER, e, a) end
function RUN(seconds)
  local dt = 1/30
  for i = 1, math.floor(seconds / dt) do
    UPTIME, NOW = UPTIME + dt, NOW + dt
    HOLDER.scripts.OnUpdate(HOLDER, dt)
  end
end
function SHOWN()
  local out = {}
  for _, i in ipairs(ICONS) do
    if i.shown and rawget(i, 'pin') then out[#out+1] = i end
  end
  return out
end
function COUNT() return #SHOWN() end
function MARK(name)
  for _, i in ipairs(ICONS) do
    local m = rawget(i, "marker")
    if i.shown and m and m.name == name then return i end
  end
end
function MARKS()
  local c = 0
  for _, i in ipairs(ICONS) do if i.shown and rawget(i, "marker") then c = c + 1 end end
  return c
end
function NAMES()
  local t = {}
  for _, i in ipairs(SHOWN()) do t[#t+1] = i.pin.name end
  table.sort(t)
  return table.concat(t, ",")
end
function FIND(name)
  for _, i in ipairs(SHOWN()) do if i.pin.name == name then return i end end
end
function ERR(name)
  local i = FIND(name)
  if not i then return 9999 end
  for _, n in ipairs(WORLD) do
    if n.name == name then
      local ox, oy = worldToPx(n.east, n.north)
      return math.sqrt((ox-i.ox)^2 + (oy-i.oy)^2)
    end
  end
  return 8888
end
function ADD(name, kind, dEast, dNorth)
  local px, py = playerWorld()
  WORLD[#WORLD+1] = { name = name, kind = kind, east = px + dEast, north = py + dNorth }
end
function REMOVE(name)
  for i, n in ipairs(WORLD) do if n.name == name then table.remove(WORLD, i); return end end
end
function SWAP(herb, ore)
  TRACK[1].active, TRACK[2].active = herb, ore
  FIRE("MINIMAP_UPDATE_TRACKING")
end
"""

def fresh():
    lua = L.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK)
    load = lua.eval("function(src, ns) assert(loadstring(src))('TentTimer', ns) end")
    ns = lua.table()
    load(SRC, ns)
    lua.execute('FIRE("PLAYER_LOGIN")')
    return lua

failed = False
def check(label, cond, detail=""):
    global failed
    print(("PASS " if cond else "FAIL ") + label + (f"   [{detail}]" if detail != "" else ""))
    if not cond:
        failed = True

# 1. The core request: herb stays after swapping to ore, different icons
lua = fresh()
lua.execute('ADD("Peacebloom","herb",60,40); ADD("Copper Vein","ore",-80,30); PARTY = {{name="SomeFriend", east=2500-20, north=-2500-20}}')
lua.execute("RUN(3)")
check("herb gets an icon while tracked", lua.eval("NAMES()") == "Peacebloom", lua.eval("NAMES()"))
check("ore not shown while only herbs are tracked", lua.eval('FIND("Copper Vein")') is None)
check("party member gets no icon", lua.eval('FIND("SomeFriend")') is None)
check("other names are listed as unknown", lua.eval('TentTimerDB.nodes.unknown["SomeFriend"]') is True)
err = lua.eval('ERR("Peacebloom")'); check("icon sits on the dot", err < 3, f"{err:.2f} px off")
check("soft cursor always on while probing, off after", lua.eval("SOFT_ON_DURING") is True and lua.eval("SOFT") is False)
lua.execute("SWAP(false, true); RUN(6)")
check("herb STAYS after swapping to ore", "Peacebloom" in lua.eval("NAMES()"), lua.eval("NAMES()"))
check("ore appears after the swap", "Copper Vein" in lua.eval("NAMES()"), lua.eval("NAMES()"))
check("remembered herb is dimmed", lua.eval('FIND("Peacebloom").alpha') == 0.8)
check("tracked ore is full strength", lua.eval('FIND("Copper Vein").alpha') == 1)
h, o = lua.eval('FIND("Peacebloom").art.texture'), lua.eval('FIND("Copper Vein").art.texture')
check("herb and ore use different pictures", h != o, f"{h} / {o}")
check("icons have no border", lua.eval('rawget(FIND("Peacebloom"), "border")') is None and lua.eval('rawget(FIND("Copper Vein"), "border")') is None)
check("icons are cut to a circle", lua.eval('FIND("Peacebloom").art.mask ~= nil') is True and "TempPortraitAlphaMask" in lua.eval('FIND("Peacebloom").art.mask.texture'))
lua.execute("SWAP(true, false); RUN(6)")
check("ore stays after swapping back", lua.eval("NAMES()") == "Copper Vein,Peacebloom", lua.eval("NAMES()"))
check("no duplicates after several swaps", lua.eval("#TentTimerDB.nodes.pins") == 2, lua.eval("#TentTimerDB.nodes.pins"))

# 2. Gathering
lua = fresh()
lua.execute('ADD("Peacebloom","herb",5,3); ADD("Silverleaf","herb",40,40); ADD("Tin Vein","ore",60,-40)')
lua.execute("SWAP(true, true); RUN(3); SWAP(false, true); RUN(3)")
check("3 icons before gathering", lua.eval("COUNT()") == 3, lua.eval("NAMES()"))
lua.execute('REMOVE("Peacebloom"); FIRE("LOOT_CLOSED"); RUN(0.1)')
check("gathering removes only the node beside you", lua.eval("NAMES()") == "Silverleaf,Tin Vein", lua.eval("NAMES()"))
lua.execute("RUN(5)")
check("gathered herb does not come back", "Peacebloom" not in lua.eval("NAMES()"))
lua.execute('FIRE("LOOT_CLOSED"); RUN(0.1)')
check("looting with nothing near removes nothing", lua.eval("COUNT()") == 2, lua.eval("NAMES()"))
lua.execute('ADD("Mageroyal","herb",3,3); SWAP(true,false); RUN(3); FIRE("LOOT_CLOSED"); RUN(4)')
check("node still there after loot is found again", "Mageroyal" in lua.eval("NAMES()"), lua.eval("NAMES()"))

# 3. Taken by someone else
lua = fresh()
lua.execute('ADD("Peacebloom","herb",40,40); RUN(3); REMOVE("Peacebloom"); RUN(8)')
check("node taken while tracked disappears", lua.eval("COUNT()") == 0, lua.eval("NAMES()"))
lua = fresh()
lua.execute('ADD("Peacebloom","herb",40,40); RUN(3); SWAP(false,true); REMOVE("Peacebloom"); RUN(8)')
check("node taken while NOT tracked stays (cannot be seen)", lua.eval("COUNT()") == 1)
lua.execute("SWAP(true,false); RUN(8)")
check("...and goes once its tracking is back", lua.eval("COUNT()") == 0, lua.eval("NAMES()"))
lua = fresh()
lua.execute('ADD("Peacebloom","herb",40,40); RUN(3); SWAP(false,true); RUN(1); SWAP(true,false); RUN(1)')
check("no false removal right after a swap", lua.eval("COUNT()") == 1)

# 4. Moving, rotation, zoom, scale, keep time
lua = fresh()
lua.execute('ADD("Peacebloom","herb",60,40); RUN(3); SWAP(false,true); PLAYER.x = PLAYER.x + 30/MAP_W; PLAYER.y = PLAYER.y + 20/MAP_H; RUN(0.1)')
err = lua.eval('ERR("Peacebloom")'); check("icon follows the world when you walk", err < 3, f"{err:.2f} px off")
lua.execute('PLAYER.x = PLAYER.x + 500/MAP_W; RUN(0.1)')
check("icon hidden when out of minimap range", lua.eval("COUNT()") == 0)
check("...but still remembered", lua.eval("#TentTimerDB.nodes.pins") == 1)
lua.execute('PLAYER.x = PLAYER.x - 500/MAP_W; RUN(0.1)')
check("...and back when you return", lua.eval("COUNT()") == 1)

lua = fresh()
lua.execute('ROTATE = true; PLAYER.facing = 1.1; ADD("Peacebloom","herb",60,40); RUN(3); SWAP(false,true); PLAYER.facing = 2.5; RUN(0.1)')
err = lua.eval('ERR("Peacebloom")'); check("works with a rotating minimap", err < 3, f"{err:.2f} px off")

lua = fresh()
lua.execute('Minimap.scale = 1.4; ADD("Peacebloom","herb",60,40); RUN(3)')
err = lua.eval('ERR("Peacebloom")'); check("works with UI scale", err < 3, f"{err:.2f} px off")

lua = fresh()
lua.execute('ADD("Peacebloom","herb",60,40); RUN(3); SWAP(false,true); RADIUS = 100; FIRE("MINIMAP_UPDATE_ZOOM"); RUN(0.1)')
err = lua.eval('ERR("Peacebloom")'); check("stays on spot after zooming", err < 3, f"{err:.2f} px off")

lua = fresh()
lua.execute('COMBAT = true; ADD("Peacebloom","herb",60,40); RUN(3)')
check("no scanning in combat", lua.eval("PROBES") == 0)
lua.execute('COMBAT = false; OVER = true; RUN(3)')
check("no scanning while the mouse is on the minimap", lua.eval("PROBES") == 0)
lua.execute('OVER = false; RUN(3)'); check("scanning resumes", lua.eval("COUNT()") == 1)

lua = fresh()
lua.execute('ADD("Peacebloom","herb",60,40); RUN(3); SWAP(false,true); RUN(1); REMOVE("Peacebloom"); NOW = NOW + 31*60; RUN(6)')
check("unseen icon removed after keep time", lua.eval("#TentTimerDB.nodes.pins") == 0)
lua = fresh()
lua.execute('SlashCmdList.TENTTIMERNODES("keep 0"); ADD("Peacebloom","herb",60,40); RUN(3); SWAP(false,true); RUN(1); NOW = NOW + 600*60; RUN(6)')
check("/nk keep 0 keeps icons", lua.eval("#TentTimerDB.nodes.pins") == 1)

lua = fresh()
lua.execute('MAPID = 1415; ADD("Peacebloom","herb",60,40); RUN(3); MAPID = 1416; RUN(0.1)')
check("other zone hides the icon", lua.eval("COUNT()") == 0)
lua.execute('MAPID = 1415; RUN(0.1)'); check("same zone shows it again", lua.eval("COUNT()") == 1)

# 5. Commands, errors
lua = fresh()
lua.execute('ADD("Starbloom","herb",60,40); RUN(3)')
check("names outside the list get no icon", lua.eval("COUNT()") == 0)
lua.execute('SlashCmdList.TENTTIMERNODES("add herb Starbloom"); RUN(3)')
check("/nk add works", lua.eval("NAMES()") == "Starbloom")
for c in ["", "status", "size 18", "size x", "keep x", "add", "add rock X", "unknown", "clear"]:
    lua.globals().SlashCmdList.TENTTIMERNODES(c)
check("commands run; clear empties", lua.eval("#TentTimerDB.nodes.pins") == 0)
lua.execute('C_TooltipInfo.GetMinimapMouseover = function() error("boom") end; RUN(3)')
check("a failing API call leaves the soft cursor off", lua.eval("SOFT") is False)
lua.execute('TentTimerDB.nodes.pins = {}; TRACK[1].active = false; FIRE("MINIMAP_UPDATE_TRACKING"); local p = PROBES; RUN(3); UNCHANGED = PROBES == p')
check("no scanning when nothing is tracked", lua.eval("UNCHANGED") is True)

# 7. Swapping
def nk(lua, c): lua.globals().SlashCmdList.TENTTIMERNODES(c)
lua = fresh()
lua.execute("RUN(20)")
check("swap is off until you ask", lua.eval("#CASTS") == 0)
nk(lua, "swap")
lua.execute("RUN(0.1)")
check("macro command starts it, first swap right away", lua.eval("CASTS[1]") == 2580 and lua.eval("TentTimerDB.nodes.swapEnabled") is True)
lua.execute("RUN(4.1)")
check("default swaps every 4 sec, back and forth", lua.eval("#CASTS") == 2 and lua.eval("CASTS[2]") == 2383, lua.eval("#CASTS"))
nk(lua, "swap 10")
check("time is configurable", lua.eval("TentTimerDB.nodes.swapSeconds") == 10)
lua.execute("RUN(4); CASTS = {}; RUN(7); A = #CASTS; RUN(10); B = #CASTS")
check("new time is used", lua.eval("A") <= 1 and lua.eval("B") == lua.eval("A") + 1, f"{lua.eval('A')},{lua.eval('B')}")
nk(lua, "swap 0.1"); check("time has a safe minimum", lua.eval("TentTimerDB.nodes.swapSeconds") == 2)
nk(lua, "swap 999"); check("time has a maximum", lua.eval("TentTimerDB.nodes.swapSeconds") == 60)
nk(lua, "swap 3.5"); check("half seconds allowed", lua.eval("TentTimerDB.nodes.swapSeconds") == 3.5)
nk(lua, "swap"); lua.execute("CASTS = {}; RUN(20)")
check("same macro command stops it", lua.eval("#CASTS") == 0 and lua.eval("TentTimerDB.nodes.swapEnabled") is False)
nk(lua, "swap on"); lua.execute("RUN(0.1)"); check("/nk swap on", lua.eval("#CASTS") == 1)
nk(lua, "swap off"); lua.execute("CASTS = {}; RUN(20)"); check("/nk swap off", lua.eval("#CASTS") == 0)

for label, flag in [("combat","COMBAT"),("city","RESTING"),("instance","INSTANCE"),("death","DEAD"),("flight path","TAXI"),("stealth","STEALTH"),("casting","CASTING"),("cursor","CURSOR"),("enemy target","ENEMY")]:
    lua = fresh()
    lua.execute("SWAP(true,false)")
    nk(lua, "swap")
    lua.execute("RUN(0.1); CASTS = {}; " + flag + " = true; RUN(20)")
    blocked = lua.eval("#CASTS") == 0
    lua.execute(flag + " = false; RUN(5)")
    check(f"no swap during {label}, resumes after", blocked and lua.eval("#CASTS") >= 1, lua.eval("#CASTS"))
lua = fresh(); nk(lua, "swap"); lua.execute('RUN(0.1); CASTS = {}; FIRE("LOOT_OPENED"); RUN(20)')
blocked = lua.eval("#CASTS") == 0
lua.execute('FIRE("LOOT_CLOSED"); RUN(5)'); check("no swap while looting, resumes after", blocked and lua.eval("#CASTS") >= 1)
lua = fresh(); lua.execute("KNOWN[2580] = nil"); nk(lua, "swap"); lua.execute("RUN(20)")
check("no swap without both professions", lua.eval("#CASTS") == 0)
lua = fresh(); lua.execute("GCD_UNTIL = UPTIME + 3"); nk(lua, "swap"); lua.execute("RUN(2)"); a = lua.eval("#CASTS"); lua.execute("RUN(1.5)")
check("waits for the global cooldown", a == 0 and lua.eval("#CASTS") == 1)

# The whole loop: real swaps keep both kinds, and a taken node still clears
lua = fresh()
lua.execute('ADD("Peacebloom","herb",60,40); ADD("Copper Vein","ore",-80,30); ADD("Silverleaf","herb",-30,-60)')
nk(lua, "swap 2"); nk(lua, "swap on"); lua.execute("RUN(9)")
check("timed swaps show herbs and ore together", lua.eval("NAMES()") == "Copper Vein,Peacebloom,Silverleaf", lua.eval("NAMES()"))
check("no duplicates from timed swaps", lua.eval("#TentTimerDB.nodes.pins") == 3)
lua.execute("RUN(60)")
check("nothing falsely removed in 60 sec of swapping", lua.eval("COUNT()") == 3, lua.eval("NAMES()"))
lua.execute('REMOVE("Peacebloom"); RUN(12)')
check("taken node clears even at the fastest swap", lua.eval("NAMES()") == "Copper Vein,Silverleaf", lua.eval("NAMES()"))

# Master switch
lua = fresh()
lua.execute('ADD("Peacebloom","herb",60,40)'); nk(lua, "swap"); lua.execute("RUN(6)")
check("icon there before stopping", lua.eval("COUNT()") >= 1)
nk(lua, "off")
lua.execute("CASTS = {}; P = PROBES; RUN(20)")
check("/nk off stops swaps and scans", lua.eval("#CASTS") == 0 and lua.eval("PROBES") == lua.eval("P"))
check("/nk off hides icons", lua.eval("COUNT()") == 0)
nk(lua, "toggle"); lua.execute("RUN(3)")
check("/nk toggle brings it all back", lua.eval("COUNT()") >= 1 and lua.eval("#CASTS") >= 1)
lua.execute("RESTING = true; CHAT = {}"); nk(lua, "status")
chat = " ".join(lua.eval("CHAT")[i] for i in range(1, lua.eval("#CHAT") + 1))
check("status explains the pause", "paused: in a city or inn" in chat)

# 8. Specific herb and ore types
lua = fresh()
lua.execute('ADD("Copper Vein","ore",60,40); ADD("Tin Vein","ore",-60,40); ADD("Iron Deposit","ore",-60,-40); ADD("Peacebloom","herb",60,-40); ADD("Silverleaf","herb",30,-70)')
lua.execute("SWAP(true,true); RUN(3)")
check("all five types found", lua.eval("COUNT()") == 5, lua.eval("NAMES()"))
pics = {n: lua.eval('FIND("%s").art.texture' % n) for n in ["Copper Vein", "Tin Vein", "Iron Deposit", "Peacebloom", "Silverleaf"]}
check("every type has its own picture", len(set(pics.values())) == 5, pics)
check("the picture is the item the node gives", pics["Copper Vein"] == 100000 + 2770 and pics["Peacebloom"] == 100000 + 2447, pics["Copper Vein"])
check("names hidden by default", lua.eval('FIND("Copper Vein").label.visible') is False)
lua.globals().SlashCmdList.TENTTIMERNODES("names"); lua.execute("RUN(0.1)")
check("/nk names shows the type name", lua.eval('FIND("Copper Vein").label.visible') is True and lua.eval('FIND("Copper Vein").label.text') == "Copper Vein")
lua.globals().SlashCmdList.TENTTIMERNODES("names"); lua.execute("RUN(0.1)")
check("/nk names hides it again", lua.eval('FIND("Copper Vein").label.visible') is False)
lua = fresh()
lua.execute('NO_ITEM_ICONS = true; ADD("Copper Vein","ore",60,40); SWAP(false,true); RUN(3)')
check("falls back to the ore picture if the game has no item icon", lua.eval('FIND("Copper Vein").art.texture') == "Interface\\Icons\\Spell_Nature_Earthquake")
lua.execute('NO_ITEM_ICONS = false; RUN(0.1)')
check("item picture appears once available", lua.eval('FIND("Copper Vein").art.texture') == 100000 + 2770)
lua = fresh()
lua.execute('ADD("Chunk of Amber","ore",60,40); SWAP(false,true); RUN(3)')
check("node without an item uses the ore picture", lua.eval('FIND("Chunk of Amber").art.texture') == "Interface\\Icons\\Spell_Nature_Earthquake")
lua = fresh()
lua.execute('TentTimerDB = {nodes={pins={{name="Tin Vein",kind="ore",mapID=1415,east=2510,north=-2490,seenAt=NOW,misses=0}}}}; FIRE("PLAYER_LOGIN"); SWAP(true,false); RUN(0.1)')
check("icons saved before this update get the new picture", lua.eval('FIND("Tin Vein").art.texture') == 100000 + 2771, lua.eval('FIND("Tin Vein") and FIND("Tin Vein").art.texture'))

# 9. Hover: can you gather it?
COLORS = {"orange": 1.0, "yellow": 1.0, "green": 0.25, "gray": 0.5, "red": 1.0}
def hover_at(lua, name, skill, mod=0):
    i = 1 if name in ("Earthroot", "Peacebloom") else 2
    lua.execute("PROF[%d].rank = %d; PROF[%d].mod = %d; HOVER(%r)" % (i, skill, i, mod, name))
    return lua.eval("TIP.r"), lua.eval("TIP.g"), lua.eval("TIP.b"), lua.eval("TIPTEXT()")

RGB = {"orange": (1, 0.5, 0.25), "yellow": (1, 1, 0), "green": (0.25, 0.75, 0.25), "gray": (0.5, 0.5, 0.5), "red": (1, 0.13, 0.13)}
lua = fresh()
lua.execute('ADD("Earthroot","herb",60,40); ADD("Peacebloom","herb",-60,40); ADD("Tin Vein","ore",-60,-40); SWAP(true,true); RUN(3)')
for name, skill, want in [
    ("Earthroot", 15, "orange"), ("Earthroot", 39, "orange"), ("Earthroot", 40, "yellow"), ("Earthroot", 64, "yellow"),
    ("Earthroot", 65, "green"), ("Earthroot", 114, "green"), ("Earthroot", 115, "gray"), ("Earthroot", 300, "gray"),
    ("Earthroot", 14, "red"),
    ("Peacebloom", 1, "orange"), ("Peacebloom", 24, "orange"), ("Peacebloom", 25, "yellow"), ("Peacebloom", 49, "yellow"),
    ("Peacebloom", 50, "green"), ("Peacebloom", 99, "green"), ("Peacebloom", 100, "gray"),
    ("Tin Vein", 65, "orange"), ("Tin Vein", 90, "yellow"), ("Tin Vein", 115, "green"), ("Tin Vein", 165, "gray"), ("Tin Vein", 64, "red"),
]:
    r, g, b, text = hover_at(lua, name, skill)
    check(f"{name} at skill {skill} is {want}", (r, g, b) == RGB[want], text)
r, g, b, text = hover_at(lua, "Tin Vein", 50)
check("red says how much more skill is needed", "you need 15 more Mining" in text and "Your skill 50, requires 65" in text, text)
r, g, b, text = hover_at(lua, "Earthroot", 20)
check("orange explains skill gain", "Always gives a skill point" in text and "Your Herbalism 20, requires 15" in text, text)
r, g, b, text = hover_at(lua, "Earthroot", 200)
check("gray says no skill point", "Gives no skill point" in text, text)
r, g, b, text = hover_at(lua, "Tin Vein", 60, 5)
check("skill bonuses count", (r, g, b) == RGB["orange"], text)
lua.execute("PROF[2] = nil; HOVER('Tin Vein')")
check("no profession: red, says so", "You have not learned Mining" in lua.eval("TIPTEXT()") and lua.eval("TIP.g") == 0.13, lua.eval("TIPTEXT()"))
lua.execute("PROF = {}; HOVER('Peacebloom')")
check("no professions at all still works", "You have not learned Herbalism" in lua.eval("TIPTEXT()"))
lua.execute("PROF = { { line = 186, rank = 100, mod = 0 }, { line = 182, rank = 30, mod = 0 } }; HOVER('Tin Vein')")
check("professions in either order", "Your Mining 100" in lua.eval("TIPTEXT()"), lua.eval("TIPTEXT()"))
lua.execute("GetProfessions = nil; C_SkillInfo = { GetSkillLineInfoByID = function(id) if id == 186 then return { rank = 70, modifier = 0 } end end }; HOVER('Tin Vein')")
check("backup skill lookup works", "Your Mining 70" in lua.eval("TIPTEXT()"), lua.eval("TIPTEXT()"))
lua.execute("C_SkillInfo = nil; GetProfessionInfo = nil; HOVER('Tin Vein')")
check("unknown skill just shows the requirement", "Requires Mining 65" in lua.eval("TIPTEXT()"), lua.eval("TIPTEXT()"))

lua = fresh()
lua.execute("PROF[2].rank = 50; TIP = { lines = {} }; GAMEHOOK(GameTooltip, { lines = { { leftText = '|cffffffffTin Vein|r\\nSomeFriend' } } })")
check("hovering a dot with no icon shows it too", "Tin Vein: Cannot gather: you need 15 more Mining" in lua.eval("TIPTEXT()") and lua.eval("TIP.shown") is True, lua.eval("TIPTEXT()"))
lua.execute("TIP = { lines = {} }; GAMEHOOK(GameTooltip, { lines = { { leftText = 'SomeFriend' } } })")
check("other minimap tooltips are left alone", lua.eval("#TIP.lines") == 0 and lua.eval("TIP.shown") is None)
lua = fresh()
lua.execute('ADD("Starbloom","herb",60,40); SlashCmdList.TENTTIMERNODES("add herb Starbloom"); RUN(3); HOVER("Starbloom")')
check("nodes you added yourself still have a tooltip", lua.eval("TIP.title") == "Starbloom" and lua.eval("#TIP.lines") == 1, lua.eval("TIPTEXT()"))

# 10. Gathered markers
lua = fresh()
lua.execute('ADD("Peacebloom","herb",5,3); ADD("Silverleaf","herb",60,40); RUN(3)')
lua.execute('REMOVE("Peacebloom"); FIRE("LOOT_CLOSED"); RUN(0.1)')
check("gathering leaves a marker", lua.eval('MARK("Peacebloom") ~= nil') is True)
check("the node's normal icon is gone", lua.eval('FIND("Peacebloom")') is None and lua.eval("NAMES()") == "Silverleaf")
check("marker is gray and faded", lua.eval('MARK("Peacebloom").art.gray') is True and lua.eval('MARK("Peacebloom").alpha') == 0.6)
check("marker keeps the item picture", lua.eval('MARK("Peacebloom").art.texture') == 100000 + 2447)
check("marker starts at 0m", lua.eval('MARK("Peacebloom").label.text') == "0m" and lua.eval('MARK("Peacebloom").label.visible') is True)
lua.execute("NOW = NOW + 12*60; RUN(0.1)")
check("marker counts up", lua.eval('MARK("Peacebloom").label.text') == "12m", lua.eval('MARK("Peacebloom").label.text'))
lua.execute('local i = MARK("Peacebloom"); i.scripts.OnEnter(i)')
check("hover says how long ago", lua.eval("TIP.title") == "Peacebloom" and "Gathered 12 min ago" in lua.eval("TIPTEXT()"), lua.eval("TIPTEXT()"))
check("normal icons are not gray", lua.eval('FIND("Silverleaf").art.gray') is False)
lua.execute('SWAP(false,true); RUN(5)')
check("marker survives a tracking swap", lua.eval('MARK("Peacebloom") ~= nil') is True)
lua.execute('SWAP(true,false); RUN(5)')
check("marker stays while nothing has come back", lua.eval('MARK("Peacebloom") ~= nil') is True)
lua.execute('ADD("Peacebloom","herb",5,3); RUN(3)')
check("marker clears when the node is back", lua.eval('MARK("Peacebloom")') is None and lua.eval('FIND("Peacebloom") ~= nil') is True)

lua = fresh()
lua.execute('ADD("Peacebloom","herb",5,3); RUN(3); FIRE("LOOT_CLOSED"); RUN(1); REMOVE("Peacebloom"); RUN(6)')
check("a dot lingering after gathering does not lose the marker", lua.eval('MARK("Peacebloom") ~= nil') is True and lua.eval('FIND("Peacebloom")') is None, lua.eval("NAMES()"))
lua = fresh()
lua.execute('ADD("Copper Vein","ore",5,3); SWAP(false,true); RUN(3); FIRE("LOOT_CLOSED"); RUN(15)')
check("a node that is still there replaces the marker", lua.eval('MARK("Copper Vein")') is None and lua.eval('FIND("Copper Vein") ~= nil') is True)
lua = fresh()
lua.execute('RUN(3); FIRE("LOOT_CLOSED"); RUN(1)')
check("loot with no node nearby leaves no marker", lua.eval("#TentTimerDB.nodes.gathered") == 0)
lua = fresh()
lua.execute('ADD("Peacebloom","herb",5,3); ADD("Silverleaf","herb",12,0); RUN(3); REMOVE("Peacebloom"); FIRE("LOOT_CLOSED"); RUN(4)')
check("a different herb nearby keeps the marker", lua.eval('MARK("Peacebloom") ~= nil') is True, lua.eval("MARKS()"))

lua = fresh()
lua.execute('ADD("Peacebloom","herb",5,3); RUN(3); REMOVE("Peacebloom"); FIRE("LOOT_CLOSED"); RUN(0.1)')
lua.execute("NOW = NOW + 59*60; RUN(6)")
check("marker still there at 59 min", lua.eval("MARKS()") == 1)
lua.execute("NOW = NOW + 2*60; RUN(6)")
check("marker removed after 60 min", lua.eval("MARKS()") == 0 and lua.eval("#TentTimerDB.nodes.gathered") == 0)

lua = fresh()
lua.execute('ADD("Peacebloom","herb",5,3); RUN(3); REMOVE("Peacebloom"); FIRE("LOOT_CLOSED"); RUN(0.1)')
lua.globals().SlashCmdList.TENTTIMERNODES("gathered 5")
lua.execute("NOW = NOW + 6*60; RUN(6)")
check("/nk gathered sets the time", lua.eval("MARKS()") == 0 and lua.eval("TentTimerDB.nodes.gatheredMinutes") == 5)
lua = fresh()
lua.globals().SlashCmdList.TENTTIMERNODES("gathered 0")
lua.execute('ADD("Peacebloom","herb",5,3); RUN(3); REMOVE("Peacebloom"); FIRE("LOOT_CLOSED"); RUN(1)')
check("/nk gathered 0 turns markers off", lua.eval("MARKS()") == 0 and lua.eval("COUNT()") == 0)
lua = fresh()
lua.execute('ADD("Peacebloom","herb",5,3); RUN(3); REMOVE("Peacebloom"); FIRE("LOOT_CLOSED"); RUN(0.1)')
lua.globals().SlashCmdList.TENTTIMERNODES("off"); lua.execute("RUN(0.1)")
check("/nk off hides markers", lua.eval("MARKS()") == 0)
lua.globals().SlashCmdList.TENTTIMERNODES("on"); lua.execute("RUN(0.1)")
check("/nk on shows them again", lua.eval("MARKS()") == 1)
lua.execute("MAPID = 1416; RUN(0.1)"); check("other zone hides markers", lua.eval("MARKS()") == 0)
lua.execute("MAPID = 1415; PLAYER.x = PLAYER.x + 500/MAP_W; RUN(0.1)"); check("out of range hides markers", lua.eval("MARKS()") == 0)
lua.execute("PLAYER.x = PLAYER.x - 500/MAP_W; RUN(0.1)"); check("back in range shows them", lua.eval("MARKS()") == 1)
lua.globals().SlashCmdList.TENTTIMERNODES("clear"); lua.execute("RUN(0.1)")
check("/nk clear removes markers", lua.eval("MARKS()") == 0 and lua.eval("#TentTimerDB.nodes.gathered") == 0)
lua = L.LuaRuntime(unpack_returned_tuples=True); lua.execute(MOCK)
lua.execute('TentTimerDB = { nodes = { pins = {}, gathered = { { name="Tin Vein", kind="ore", mapID=1415, east=2510, north=-2490, gatheredAt=NOW-300 } } } }')
lua.eval("function(src) assert(loadstring(src))('TentTimer', {}) end")(SRC)
lua.execute('FIRE("PLAYER_LOGIN"); RUN(0.1)')
check("markers survive logging out, time keeps counting", lua.eval('MARK("Tin Vein").label.text') == "5m", lua.eval('MARK("Tin Vein") and MARK("Tin Vein").label.text'))
lua = L.LuaRuntime(unpack_returned_tuples=True); lua.execute(MOCK)
lua.execute('TentTimerDB = { nodes = { pins = {}, swapSeconds = 7 } }')
lua.eval("function(src) assert(loadstring(src))('TentTimer', {}) end")(SRC)
lua.execute('FIRE("PLAYER_LOGIN"); RUN(0.1)')
check("settings from before this update still load", lua.eval("TentTimerDB.nodes.swapSeconds") == 7 and lua.eval("TentTimerDB.nodes.gatheredMinutes") == 60)

# 6. Tent timer removed
lua = fresh()
lua.execute('CHAT = {}; SlashCmdList.TENTTIMERNODES("status")')
check("/nk works on its own", "game API: ok" in lua.eval("CHAT[1]"), lua.eval("CHAT[1]"))
check("/tent no longer exists", lua.eval("SlashCmdList.TENTTIMER") is None and lua.eval("SLASH_TENTTIMER1") is None)
lua.execute('ADD("Star Lotus","herb",60,40); RUN(3)')
check("Forever-only herb names are known", lua.eval("NAMES()") == "Star Lotus", lua.eval("NAMES()"))
lua = L.LuaRuntime(unpack_returned_tuples=True); lua.execute(MOCK)
lua.execute('TentTimerDB = { chars = { x = {} }, position = {}, collapsed = true, nodes = { swapSeconds = 7, swapEnabled = true, pins = {} } }')
lua.eval("function(src) assert(loadstring(src))('TentTimer', {}) end")(SRC)
lua.execute('FIRE("PLAYER_LOGIN")')
check("old tent data is cleaned up", lua.eval("TentTimerDB.chars") is None and lua.eval("TentTimerDB.position") is None and lua.eval("TentTimerDB.collapsed") is None)
check("your swap settings are kept", lua.eval("TentTimerDB.nodes.swapSeconds") == 7 and lua.eval("TentTimerDB.nodes.swapEnabled") is True)

sys.exit(1 if failed else 0)
