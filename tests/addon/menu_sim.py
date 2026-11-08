"""Runs the disenchant window, its safety checks, the menu and the minimap button outside the game.

    python tests/addon/menu_sim.py
"""
import os
import sys
import lupa.lua51 as L

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ADDON = os.path.join(ROOT, "addon", "DufforthAHScanner")


def source(name):
    return open(os.path.join(ADDON, name), encoding="utf-8").read()


MOCK = r"""
NOW, COMBAT = 1000000, false
CHAT, ALL, NODES = {}, {}, {}
time = function() return NOW end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) CHAT[#CHAT+1] = m end }
InCombatLockdown = function() return COMBAT end
UISpecialFrames = {}
tinsert = table.insert
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
GetCursorPosition = function() return 0, 100 end
C_Timer = { After = function(_, f) f() end }
SlashCmdList = {
  DUFFORTHAHSCANNERNODES = function(t) NODES[#NODES+1] = t end,
}
C_Spell = { GetSpellInfo = function() return { name = "Disenchant" } end }

local function object(kind, name)
  local o = { kind = kind, name = name, scripts = {}, attributes = {}, shown = true, enabled = true, events = {} }
  function o:SetScript(k, f) self.scripts[k] = f end
  function o:GetScript(k) return self.scripts[k] end
  function o:SetAttribute(k, v) self.attributes[k] = v end
  function o:GetAttribute(k) return self.attributes[k] end
  function o:Show() self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
  function o:Hide() self.shown = false end
  function o:SetShown(v) if v then self:Show() else self:Hide() end end
  function o:IsShown() return self.shown end
  function o:SetText(t) self.text = t end
  function o:GetText() return self.text end
  function o:SetChecked(v) self.checked = v end
  function o:GetChecked() return self.checked end
  function o:Enable() self.enabled = true end
  function o:Disable() self.enabled = false end
  function o:SetTexture(t) self.texture = t end
  function o:RegisterEvent(e) self.events[e] = true end
  function o:GetWidth() return 140 end
  function o:GetEffectiveScale() return 1 end
  function o:GetCenter() return 0, 0 end
  function o:SetPoint(...) self.point = { ... } end
  function o:CreateFontString() local f = object("FontString"); ALL[#ALL+1] = f; return f end
  function o:CreateTexture() return object("Texture") end
  o.StartMoving, o.StopMovingOrSizing = function() end, function() end
  return setmetatable(o, { __index = function() return function() end end })
end
function CreateFrame(kind, name, parent, template)
  local f = object(kind, name)
  f.template = template
  if kind ~= "Frame" or name then f.shown = true end
  ALL[#ALL+1] = f
  if name then _G[name] = f end
  return f
end
UIParent, Minimap = object("Frame"), object("Frame")
GameTooltip = object("GameTooltip")

-- Bags: bag 0 holds the items below, slot by slot.
ITEMS = {
  [101] = { "Green Helm", nil, 2, 30, nil, nil, nil, nil, "INVTYPE_HEAD", "helm", 500, 4, nil, 2 },
  [102] = { "Blue Sword", nil, 3, 30, nil, nil, nil, nil, "INVTYPE_WEAPON", "sword", 900, 2, nil, 2 },
  [103] = { "Soulbound Gloves", nil, 2, 30, nil, nil, nil, nil, "INVTYPE_HAND", "gloves", 400, 4, nil, 1 },
  [104] = { "Green Boots", nil, 2, 31, nil, nil, nil, nil, "INVTYPE_FEET", "boots", 600, 4, nil, 2 },
  [105] = { "Linen Cloth", nil, 1, 5, nil, nil, nil, nil, "", "cloth", 13, 7, nil, 0 },
}
GetItemInfo = function(id) local i = ITEMS[id]; if i then return unpack(i, 1, 14) end end
BAG = {
  { itemID = 101, isBound = false, isLocked = false },
  { itemID = 102, isBound = false, isLocked = false },
  { itemID = 103, isBound = true, isLocked = false },
  { itemID = 104, isBound = false, isLocked = false },
  { itemID = 105, isBound = false, isLocked = false },
}
C_Container = {
  GetContainerNumSlots = function(bag) return bag == 0 and #BAG or 0 end,
  GetContainerItemInfo = function(bag, slot) return bag == 0 and BAG[slot] or nil end,
  GetContainerItemEquipmentSetInfo = function(bag, slot) return slot == 4 end,
}
GetProfessions = function() return 1, nil end
GetProfessionInfo = function() return "Enchanting", nil, 100, 300, nil, nil, 333, 0 end
DufforthAHScanner = { MarketName = function() return "forever.normal.horde.us" end }
DufforthAHScannerPrices = { ["forever.normal.horde.us"] = { [11083] = 1000, [11082] = 4000, [11084] = 6000 } }
DufforthAHScannerDB = { nodes = { enabled = true, labels = false, swapEnabled = false, swapSeconds = 4, size = 14, keepMinutes = 30, gatheredMinutes = 60 } }
"""

lua = L.LuaRuntime(unpack_returned_tuples=True)
lua.execute(MOCK)
lua.execute("GetRealmName = function() return 'Realm 4' end; UnitFactionGroup = function() return 'Horde' end")
for name in ("Core.lua", "Disenchant.lua", "AutoDisenchant.lua", "Menu.lua"):
    lua.execute(source(name))
g = lua.globals()
fails = []


def check(name, ok):
    print(("ok   " if ok else "FAIL ") + name)
    if not ok:
        fails.append(name)


AUTO = g.DufforthAHScannerAutoDE
opts = AUTO.Options()


def blocked(**fields):
    item = {"id": 1, "quality": 2, "level": 30, "classID": 4, "slot": "INVTYPE_HEAD", "bindType": 2, "bound": False, "locked": False, "inSet": False}
    item.update(fields)
    return AUTO.Blocked(lua.table_from(item), opts, fields.pop("skill", 300) if "skill" in fields else 300, fields.get("value", 5000), 50)


check("a plain green BoE is safe", blocked() is None)
check("bound items are kept", blocked(bound=True) == "already bound")
check("unknown binding is kept", AUTO.Blocked(lua.table_from({"id": 1, "quality": 2, "level": 30, "bindType": 2, "locked": False}), opts, 300, 5000, 50) == "can't tell if it's bound")
check("Bind on Pickup is kept", blocked(bindType=1) == "not Bind on Equip")
check("blues are kept by default", blocked(quality=3) == "above your quality limit")
check("locked items are kept", blocked(locked=True) == "in use")
check("equipment sets are kept", blocked(inSet=True) == "in an equipment set")
check("low skill is kept", AUTO.Blocked(lua.table_from({"id": 1, "quality": 2, "level": 30, "bindType": 2, "bound": False}), opts, 40, 5000, 50) == "needs Enchanting 50")
check("no Enchanting is kept", AUTO.Blocked(lua.table_from({"id": 1, "quality": 2, "level": 30, "bindType": 2, "bound": False}), opts, False, 5000, 50) == "you don't have Enchanting")
check("worth more on the AH is kept", blocked(ahPrice=10000) == "sells for more on the auction house")
check("vendor pays more is kept", blocked(sellPrice=6000) == "a vendor pays more")
opts.keep[1] = True
check("keep list is kept", blocked() == "on your keep list")
opts.keep[1] = None
opts.maxLevel = 25
check("item level limit", blocked() == "above your item level limit")
opts.maxLevel = 0

ready, held = AUTO.Candidates()
check("only the green BoE helm is ready", len(ready) == 1 and ready[1].id == 101)
check("the rest are counted with reasons", held["above your quality limit"] == 1 and held["already bound"] == 1 and held["in an equipment set"] == 1)

AUTO.Toggle()
frame, button = g.DufforthAHScannerDEFrame, g.DufforthAHScannerDEButton
check("the button disenchants the helm in bag 0 slot 1",
      button.attributes["type"] == "spell" and button.attributes["spell"] == "Disenchant" and button.attributes["target-bag"] == 0 and button.attributes["target-slot"] == 1)
check("the window says why others are held back", "Kept back:" in (frame.held.text or ""))
frame.skip.scripts.OnClick(frame.skip)
check("Skip leaves nothing else to offer", button.attributes["type"] is None and button.enabled is False)
opts.maxQuality = 3
g.DufforthAHScannerAutoDE.Refresh()
check("allowing blues offers the sword", button.attributes["target-slot"] == 2)
frame.keepButton.scripts.OnClick(frame.keepButton)
check("Keep puts it on the keep list", opts.keep[102] is True)
g.COMBAT = True
frame.status.text = ""
g.DufforthAHScannerAutoDE.Refresh()
check("nothing changes in combat", frame.status.text == "Paused in combat.")
frame.scripts.OnEvent(frame, "PLAYER_REGEN_DISABLED")
check("the window hides when combat starts", frame.shown is False)
g.COMBAT = False

# Menu and minimap button.
loader = lua.eval("function() for i = #ALL, 1, -1 do local f = ALL[i]; if rawget(f, 'name') == nil and f.events.PLAYER_LOGIN then return f end end end")()
loader.scripts.OnEvent(loader, "PLAYER_LOGIN")
mini = g.DufforthAHScannerMinimapButton
check("minimap button exists and shows", mini is not None and mini.shown)
mini.scripts.OnClick(mini, "LeftButton")
menu = g.DufforthAHScannerMenu
check("left-click opens the menu", menu is not None and menu.shown)


# Find a checkbox by the label next to it: labels are font strings created right after their box.
items = list(g.ALL.values())
def box_for(label_text):
    for i, f in enumerate(items):
        if f.kind == "FontString" and f.text == label_text:
            for j in range(i - 1, -1, -1):
                if items[j].kind == "CheckButton":
                    return items[j]
    return None


swap = box_for("Swap tracking automatically")
swap.checked = True
swap.scripts.OnClick(swap)
check("ticking swap runs /nk swap on", list(g.NODES.values())[-1] == "swap on")
names = box_for("Names beside icons")
names.checked = True
names.scripts.OnClick(names)
check("ticking names runs /nk names", list(g.NODES.values())[-1] == "names")
tips = box_for("Disenchant values in item tooltips")
tips.checked = False
tips.scripts.OnClick(tips)
check("unticking tooltips turns them off", g.DufforthAHScannerDB.showDisenchant is False)
hide = box_for("Show the minimap button")
hide.checked = False
hide.scripts.OnClick(hide)
check("the minimap button can be hidden", mini.shown is False and g.DufforthAHScannerDB.minimap.hide is True)
check("/dufforth is registered", g.SlashCmdList.DUFFORTHAHSCANNER is not None)
check("the menu has no auction scan section", box_for("Light scan when the auction house opens") is None)
core = lua.eval("function() for i = 1, #ALL do local f = ALL[i]; if f.events.ADDON_LOADED then return f end end end")()
g.DufforthAHScannerDB.scans = lua.table_from({"x": 1})
g.DufforthAHScannerDB.autoScan = False
core.scripts.OnEvent(core, "ADDON_LOADED", "DufforthAHScanner")
check("old scan data is dropped on load", g.DufforthAHScannerDB.scans is None and g.DufforthAHScannerDB.autoScan is None)
check("market name for a normal Horde realm", g.DufforthAHScanner.MarketName() == "forever.normal.horde.us")
mini.scripts.OnDragStart(mini)
mini.scripts.OnUpdate(mini)
check("dragging saves the button's angle", abs(g.DufforthAHScannerDB.minimap.angle - 90) < 1e-6)

if fails:
    sys.exit(f"{len(fails)} failed")
print("all passed")
