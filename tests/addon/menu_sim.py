"""Runs the disenchant window, its safety checks, the menu and the minimap button outside the game.

    python tests/addon/menu_sim.py
"""
import os
import sys
import lupa.lua51 as L

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ADDON = os.path.join(ROOT, "addon", "DufforthTweaksHelper")


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
  DUFFORTHTWEAKSHELPERNODES = function(t) NODES[#NODES+1] = t end,
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
DufforthTweaksHelper = { MarketName = function() return "forever.normal.horde.us" end }
DufforthTweaksHelperPrices = { ["forever.normal.horde.us"] = { [11083] = 1000, [11082] = 4000, [11084] = 6000 } }
DufforthTweaksHelperDB = { nodes = { enabled = true, labels = false, swapEnabled = false, swapSeconds = 4, size = 14, keepMinutes = 30, gatheredMinutes = 60 } }
"""

lua = L.LuaRuntime(unpack_returned_tuples=True)
lua.execute(MOCK)
lua.execute("GetRealmName = function() return 'Realm 4' end; UnitFactionGroup = function() return 'Horde' end")
for name in ("Core.lua", "Disenchant.lua", "AutoDisenchant.lua", "Crafting.lua", "Menu.lua"):
    lua.execute(source(name))
g = lua.globals()
fails = []


def check(name, ok):
    print(("ok   " if ok else "FAIL ") + name)
    if not ok:
        fails.append(name)


AUTO = g.DufforthTweaksHelperAutoDE
opts = AUTO.Options()


def classify(skill=300, **fields):
    item = {"id": 1, "quality": 2, "level": 30, "bindType": 2, "bound": False, "locked": False, "inSet": False}
    item.update(fields)
    result = AUTO.Classify(lua.table_from(item), opts, skill, 5000, 50)
    return result if isinstance(result, tuple) or result is None else (result, None)


check("a plain green BoE is fine", classify() is None)
check("soulbound starts unticked", classify(bound=True) == ("soulbound", None))
check("Bind on Pickup starts unticked", classify(bindType=1)[0] == "not Bind on Equip")
check("blues start unticked by default", classify(quality=3)[0] == "above your quality limit")
check("equipment sets start unticked", classify(inSet=True)[0] == "in an equipment set")
check("worth more on the AH starts unticked", classify(ahPrice=10000)[0] == "sells for more on the auction house")
check("vendor pays more starts unticked", classify(sellPrice=6000)[0] == "a vendor pays more")
check("locked items can't be ticked", classify(locked=True) == ("in use", True))
check("low skill can't be ticked", classify(skill=40) == ("needs Enchanting 50", True))
check("no Enchanting can't be ticked", classify(skill=False) == ("you don't have Enchanting", True))
opts.keep[1] = True
check("keep list starts unticked", classify()[0] == "on your keep list")
opts.keep[1] = None
opts.maxLevel = 25
check("item level limit", classify()[0] == "above your item level limit")
opts.maxLevel = 0

rows = AUTO.Rows()
names = [rows[i].item.name for i in range(1, len(rows) + 1)]
check("every disenchantable item is listed, cloth is not", names == ["Green Helm", "Blue Sword", "Soulbound Gloves", "Green Boots"])
check("only the safe one starts ticked", [bool(AUTO.IsSelected(rows[i])) for i in range(1, len(rows) + 1)] == [True, False, False, False])

AUTO.Toggle()
frame, button = g.DufforthTweaksHelperDEFrame, g.DufforthTweaksHelperDEButton
check("the button disenchants the helm in bag 0 slot 1",
      button.attributes["type"] == "spell" and button.attributes["spell"] == "Disenchant" and button.attributes["target-bag"] == 0 and button.attributes["target-slot"] == 1)
check("the button counts ticked items", button.text == "Disenchant next (1)")
lines = lua.eval("function() local out = {} for i = 1, #ALL do local f = ALL[i]; if f.kind == 'CheckButton' and f.point and rawget(f, 'point') then out[#out+1] = f end end return out end")()
checks = [lines[i] for i in range(1, len(lines) + 1)]
check("rows show the reason for unticked items", "|cff999999above your quality limit|r" in [str(f.text) for f in g.ALL.values() if f.kind == "FontString"])
sword_box = checks[1]
sword_box.checked = True
sword_box.scripts.OnClick(sword_box)
check("ticking the sword adds it", button.text == "Disenchant next (2)")
helm_box = checks[0]
helm_box.checked = False
helm_box.scripts.OnClick(helm_box)
check("unticking the helm moves the button to the sword", button.attributes["target-slot"] == 2 and button.text == "Disenchant next (1)")
AUTO.SetAll(False)
check("untick all leaves nothing to cast", button.attributes["type"] is None and button.enabled is False)
AUTO.SetAll(True)
check("tick all selects every allowed item", button.text == "Disenchant next (4)")
g.COMBAT = True
frame.status.text = ""
AUTO.Refresh()
check("nothing changes in combat", frame.status.text == "Paused in combat.")
frame.scripts.OnEvent(frame, "PLAYER_REGEN_DISABLED")
check("the window hides when combat starts", frame.shown is False)
g.COMBAT = False

# Menu and minimap button.
loader = lua.eval("function() for i = #ALL, 1, -1 do local f = ALL[i]; if rawget(f, 'name') == nil and f.events.PLAYER_LOGIN then return f end end end")()
loader.scripts.OnEvent(loader, "PLAYER_LOGIN")
mini = g.DufforthTweaksHelperMinimapButton
check("minimap button exists and shows", mini is not None and mini.shown)
mini.scripts.OnClick(mini, "LeftButton")
menu = g.DufforthTweaksHelperMenu
check("left-click opens the menu", menu is not None and menu.shown)
tab_names = [f.text for f in g.ALL.values() if f.kind == "Button" and f.text in ("Gather", "Disenchant", "Crafting")]
check("the window has Gather, Disenchant and Crafting tabs", tab_names == ["Gather", "Disenchant", "Crafting"])
g.DufforthTweaksHelperMenu_Toggle("crafting")
check("/dufforth crafting opens the Crafting tab", g.DufforthTweaksHelperDB.menuTab == "Crafting" and menu.shown)
g.DufforthTweaksHelperMenu_Toggle("gather")
check("/dufforth gather opens the Gather tab", g.DufforthTweaksHelperDB.menuTab == "Gather")
check("the minimap button is a question mark (help)", 'local ICON = "Interface' in source("Menu.lua") and 'INV_Misc_QuestionMark" -- a question mark' in source("Menu.lua"))


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
check("no names option any more", box_for("Names beside icons") is None)
tips = box_for("Disenchant advice in item tooltips")
tips.checked = False
tips.scripts.OnClick(tips)
check("unticking tooltips turns them off", g.DufforthTweaksHelperDB.showDisenchant is False)
hide = box_for("Show the minimap button")
hide.checked = False
hide.scripts.OnClick(hide)
check("the minimap button can be hidden", mini.shown is False and g.DufforthTweaksHelperDB.minimap.hide is True)
check("/dufforth is registered", g.SlashCmdList.DUFFORTHTWEAKSHELPER is not None)
check("the menu has no auction scan section", box_for("Light scan when the auction house opens") is None)
core = lua.eval("function() for i = 1, #ALL do local f = ALL[i]; if f.events.ADDON_LOADED then return f end end end")()
g.DufforthTweaksHelperDB.scans = lua.table_from({"x": 1})
g.DufforthTweaksHelperDB.autoScan = False
core.scripts.OnEvent(core, "ADDON_LOADED", "DufforthTweaksHelper")
check("old scan data is dropped on load", g.DufforthTweaksHelperDB.scans is None and g.DufforthTweaksHelperDB.autoScan is None)
check("market name for a normal Horde realm", g.DufforthTweaksHelper.MarketName() == "forever.normal.horde.us")
mini.scripts.OnDragStart(mini)
mini.scripts.OnUpdate(mini)
check("dragging saves the button's angle", abs(g.DufforthTweaksHelperDB.minimap.angle - 90) < 1e-6)

if fails:
    sys.exit(f"{len(fails)} failed")
print("all passed")
