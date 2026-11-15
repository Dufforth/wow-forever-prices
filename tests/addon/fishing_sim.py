"""One-click fishing outside the game (user, 2026-11-15): what each press does (fishing gear, lure, cast, hook),
the secure buttons, the key (casts on release, hooks only once the bobber has landed and the key is up), the
double right-click (armed by a quick first click, a held second click is the camera), the settings changed while
fishing and put back only where still ours, gear back after, catch counters, escapes, zone needs, sounds, the catch
card, the bobber mark, never acting in combat, never writing to chat, and the Fishing tab (English and Spanish).

    python tests/addon/fishing_sim.py
"""
import sys
from pathlib import Path

import lupa.lua51 as L

ADDON = Path(__file__).resolve().parents[2] / "addon" / "DufforthTweaksHelper"
lua = L.LuaRuntime(unpack_returned_tuples=True)
lua.execute("GetLocale = function() return LOCALE end; LOCALE = 'enUS'")
for _loc in ("Locale.lua", "LocaleES.lua"):
    lua.execute((ADDON / _loc).read_text(encoding="utf-8"))
lua.execute(r"""
NOW, COMBAT = 1000, false
CHAT, BINDS, EQUIPPED_LOG, SOUNDS = {}, {}, {}, {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) CHAT[#CHAT+1] = m end }
GetTime = function() return NOW end
InCombatLockdown = function() return COMBAT end
TIMERS = {}
C_Timer = { After = function(s, f) TIMERS[#TIMERS+1] = { NOW + s, f } end }
-- Runs every timer due by now (and ones they add that are due too).
function Run(seconds)
  NOW = NOW + (seconds or 0)
  for _ = 1, 200 do
    local due
    for i, t in ipairs(TIMERS) do if t[1] <= NOW + 1e-9 then due = i; break end end
    if not due then return end
    local t = table.remove(TIMERS, due); t[2]()
  end
end

local real = string.format
string.format = function(fmt, ...)
  local args, i = {...}, 0
  for spec in fmt:gmatch("%%[-+ #0]*%d*%.?%d*([%a%%])") do
    if spec ~= "%" then
      i = i + 1
      if spec == "d" and type(args[i]) == "number" and args[i] ~= math.floor(args[i]) then
        error("bad argument #" .. i .. " to 'format' (number has no integer representation)")
      end
    end
  end
  return real(fmt, ...)
end

ALL = {}
local function object(kind, name)
  local o = { kind = kind, name = name, scripts = {}, attributes = {}, shown = true, events = {}, alpha = 1 }
  function o:SetScript(k, f) self.scripts[k] = f end
  function o:GetScript(k) return self.scripts[k] end
  function o:HookScript(k, f) self.scripts[k] = f end
  function o:SetAttribute(k, v)
    if COMBAT then error("ADDON_ACTION_BLOCKED SetAttribute in combat") end
    self.attributes[k] = v
  end
  function o:GetAttribute(k) return self.attributes[k] end
  function o:Show() self.shown = true end
  function o:Hide() self.shown = false end
  function o:SetShown(v) self.shown = v and true or false end
  function o:IsShown() return self.shown end
  function o:SetText(t) self.text = t end
  function o:GetText() return self.text end
  function o:SetChecked(v) self.checked = v end
  function o:GetChecked() return self.checked end
  function o:SetAlpha(a) self.alpha = a end
  function o:SetPoint(...) self.point = { ... } end
  function o:RegisterEvent(e) self.events[e] = true end
  function o:CreateFontString() local f = object("FontString"); ALL[#ALL+1] = f; return f end
  function o:CreateTexture() return object("Texture") end
  function o:GetName() return self.name end
  -- Unknown methods do nothing; unknown fields are nil, as on real frames.
  return setmetatable(o, { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return function() end end end })
end
function CreateFrame(kind, name, parent, template)
  local f = object(kind, name); f.template = template; f.parent = parent
  ALL[#ALL+1] = f
  if name then _G[name] = f end
  return f
end
UIParent, WorldFrame = object("Frame"), object("Frame")
GameTooltip = object("GameTooltip"); GameTooltip.shown = false

local function ownerName(o) return o.name or "?" end
function ClearOverrideBindings(owner)
  if COMBAT then error("blocked in combat") end
  for k, v in pairs(BINDS) do if v.owner == owner then BINDS[k] = nil end end
end
local function put(owner, prio, key, cmd)
  if COMBAT then error("blocked in combat") end
  local slot = key .. (prio and "!" or "")
  if cmd == nil then BINDS[slot] = nil else BINDS[slot] = { owner = owner, cmd = cmd } end
end
function SetOverrideBinding(owner, prio, key, command) put(owner, prio, key, command) end
function SetOverrideBindingClick(owner, prio, key, button, mouse) put(owner, prio, key, "CLICK " .. button) end
-- What a key does now: a priority binding wins.
function KEY(k) local b = BINDS[k .. "!"] or BINDS[k]; return b and b.cmd end
GetBindingText = function(k) return k end
HELD = {}
IsKeyDown = function(k) return HELD[k] == true end
IsMouseButtonDown = function(b) return HELD[b] == true end
CURSOR = { 500, 300 }
GetCursorPosition = function() return CURSOR[1], CURSOR[2] end

CVARS = { SoftTargetInteract = "1", SoftTargetInteractArc = "1", SoftTargetInteractRange = "45", SoftTargetIconGameObject = "0",
  autoLootDefault = "0", Sound_EnableAllSound = "1", Sound_EnableSFX = "1", Sound_SFXVolume = "0.4", Sound_EnableMusic = "1",
  Sound_EnableAmbience = "1", Sound_EnableDialog = "1", Sound_EnableErrorSpeech = "1",
  Sound_MusicVolume = "0.5", Sound_AmbienceVolume = "0.5", Sound_MasterVolume = "0.8" }
C_CVar = { GetCVar = function(n) return CVARS[n] end, SetCVar = function(n, v) CVARS[n] = tostring(v) end }

KNOWN = { [7620] = true, [7731] = true, [7732] = true, [18248] = true }
IsPlayerSpell = function(id) return KNOWN[id] == true end
C_Spell = { GetSpellName = function(id) return id == 7620 and "Fishing" or nil end }
ITEM_SPELL_TRIGGER_ONEQUIP = "Equip:"
ERR_FISH_ESCAPED = "Your fish got away!"
SPELL_FAILED_FISHING_TOO_LOW = "Requires Fishing %d"
SOUNDKIT = { IG_QUEST_LIST_COMPLETE = 878, IG_QUEST_FAILED = 847, READY_CHECK = 8960 }
PlaySound = function(id) SOUNDS[#SOUNDS+1] = id end
PROFS = { Fishing = 210 }
ZONE = "Durotar"
GetRealZoneText = function() return ZONE end
DufforthTweaksHelper = {
  Professions = function() return PROFS end,
  MarketName = function() return "m" end,
  CharacterKey = function() return "Duff-Forever" end,
  EditMode = function() return false end,
  RegisterMovable = function() end,
}
DufforthTweaksHelperPrices = { m = { [6303] = 100, [6358] = 200 } }

-- Items: 6256 Fishing Pole (+0), 6366 Darkwood Fishing Pole (+15), 7996 a fishing hat (+5), 2000 sword, 2001 shield,
-- 2002 a plain hat, lures 6529 and 6532.
INFO = { [6256] = { 2, 20, "INVTYPE_2HWEAPON" }, [6366] = { 2, 20, "INVTYPE_2HWEAPON" }, [2000] = { 2, 7, "INVTYPE_WEAPON" },
  [2001] = { 4, 6, "INVTYPE_SHIELD" }, [7996] = { 4, 1, "INVTYPE_HEAD" }, [2002] = { 4, 1, "INVTYPE_HEAD" },
  [6303] = { 7, 8, "" }, [6358] = { 7, 8, "" } }
TIPS = { [6366] = { "Darkwood Fishing Pole", "Equip: Increased Fishing +15." }, [7996] = { "Lucky Hat", "Equip: Fishing increased by +5." },
  [6256] = { "Fishing Pole" }, [2002] = { "Plain Hat" } }
SELL = { [6303] = 1, [9999] = 7 }
local function tip(id) local t = { lines = {} }; for _, s in ipairs(TIPS[id] or {}) do t.lines[#t.lines+1] = { leftText = s } end; return t end
C_TooltipInfo = {
  GetBagItem = function(bag, slot) local b = BAG[slot]; return b and tip(b[1]) end,
  GetInventoryItem = function(_, slot) local id = SLOTS[slot]; if id then local t = tip(id); if slot == 16 and ENCHANT then t.lines[#t.lines+1] = { leftText = "Shiny Bauble (+25 Fishing)" } end; return t end end,
}
C_Item = {
  GetItemInfoInstant = function(id) local c = INFO[id]; if c then return id, "", "", c[3], 0, c[1], c[2] end end,
  GetItemInfo = function(id) return "n", "l", 1, 1, 1, "", "", 1, "", 0, SELL[id] or 0 end,
  EquipItemByName = function(id, slot) EQUIPPED_LOG[#EQUIPPED_LOG+1] = id .. "@" .. tostring(slot); SLOTS[slot] = id end,
}
SLOTS = { [16] = 2000, [17] = 2001, [1] = 2002 }
GetInventoryItemID = function(_, slot) return SLOTS[slot] end
BAG, FREE = {}, 4
C_Container = {
  GetContainerNumSlots = function(bag) return bag == 0 and #BAG or 0 end,
  GetContainerNumFreeSlots = function(bag) return bag == 0 and FREE or 0 end,
  GetContainerItemInfo = function(bag, slot) local b = BAG[slot]; if bag == 0 and b then return { itemID = b[1], stackCount = b[2] } end end,
}
ENCHANT = nil
GetWeaponEnchantInfo = function() if ENCHANT then return true, ENCHANT end return false end
CHANNEL = nil
UnitChannelInfo = function() if CHANNEL then return "Fishing", "", "", 0, 0, false, false, CHANNEL end end
SOFT = nil
UnitGUID = function(u) if u == "softinteract" then return SOFT end end
PLATE = { UnitFrame = { SoftTargetFrame = { alpha = 1, SetAlpha = function(self, a) self.alpha = a end } } }
C_NamePlate = { GetNamePlateForUnit = function(u) if u == "softinteract" and SOFT then return PLATE end end }
MOUSEOVER, MOUNTED = false, false
UnitExists = function(u) return u == "mouseover" and MOUSEOVER end
IsMounted = function() return MOUNTED end
FISHLOOT, LOOT = true, {}
IsFishingLoot = function() return FISHLOOT end
GetNumLootItems = function() return #LOOT end
GetLootSlotLink = function(i) return "|cffffffff|Hitem:" .. LOOT[i][1] .. "::::::|h[x]|h|r" end
GetLootSlotInfo = function(i) return "tex", LOOT[i][2], LOOT[i][3] end
BOBBER_GUID = "GameObject-0-1-2-3-35591-0000A1B2"
ITEM_SPELL_TRIGGER_ONUSE = "Use:"
INFO[3000] = { 0, 5, "" }; TIPS[3000] = { "Fishing Stew", "Use: Restores 100 health. Well Fed: +10 Fishing for 10 min." }
INFO[3001] = { 0, 5, "" }; TIPS[3001] = { "Bread", "Use: Restores 100 health." }
INFO[6351] = { 15, 0, "" }
BUFFS = {}
C_UnitAuras = { GetAuraDataByIndex = function(_, i) local b = BUFFS[i]; if b then return { auraInstanceID = i } end end }
C_TooltipInfo.GetUnitBuffByAuraInstanceID = function(_, id) local b = BUFFS[id]; if b then return { lines = { { leftText = b } } } end end
COUNTS = {}
C_Item.GetItemCount = function(id) return COUNTS[id] or 0 end
MONEY = 1000
GetMoney = function() return MONEY end
LOOTSRC = nil
GetLootSourceInfo = function() return LOOTSRC end
GetBindingKey = function(cmd) if cmd == "JUMP" then return "SPACE" end end
""")
lua.execute((ADDON / "FishingData.lua").read_text(encoding="utf-8"))
lua.execute((ADDON / "Fishing.lua").read_text(encoding="utf-8"))
failed = False


def check(label, cond, detail=""):
    global failed
    print(("PASS " if cond else "FAIL ") + label + ("" if cond or detail == "" else f"   [{detail}]"))
    if not cond:
        failed = True


F = lua.eval("DufforthTweaksHelperFishing")
run = lua.execute
ev = lua.eval("function(e, a, b) DufforthTweaksHelperFishing.OnEvent(e, a, b) end")
attr = lambda k: lua.eval(f"DufforthTweaksHelperFishButton and DufforthTweaksHelperFishButton:GetAttribute('{k}')")
key = lambda k: lua.eval(f"KEY('{k}')")
cvar = lambda n: lua.eval(f"CVARS['{n}']")
vals = lambda t: list(lua.eval(t).values())
press = lambda: run("local b = DufforthTweaksHelperFishButton; b.scripts.PreClick(b, 'LeftButton', true); b.scripts.PostClick(b, 'LeftButton', true); b.scripts.PreClick(b, 'LeftButton', false); b.scripts.PostClick(b, 'LeftButton', false)")

# ---- Pure rules ----
check("spell: the highest Fishing rank you know", F.Spell() == 18248)
run("KNOWN = { [7620] = true }")
check("spell: a lower rank when that's all you know", F.Spell() == 7620)
run("KNOWN = {}")
check("spell: restricted spell checks fall back to the profession (rank 1)", F.Spell() == 7620)
run("PROFS = {}")
check("spell: no Fishing at all = nothing", F.Spell() is None)
run("PROFS = { Fishing = 210 }; KNOWN = { [7620] = true, [7731] = true, [7732] = true, [18248] = true }")
check("pole: weapon class 2, subclass 20 only", F.IsPole(2, 20) and not F.IsPole(2, 7) and not F.IsPole(None, None))
lures = lua.eval("function(t) return DufforthTweaksHelperFishing.BestLure(t) end")
check("lure: the best one you carry", lures(lua.eval("{ [6529] = 3, [6532] = 1 }"))[0] == 6532)
check("lure: none carried = none", lures(lua.eval("{ [2000] = 1 }")) is None)
bonus = lua.eval("function(lines) return DufforthTweaksHelperFishing.Bonus(lines, 'Fishing', 'Equip:') end")
check("bonus: read from the Equip line naming Fishing", bonus(lua.eval("{ 'Pole', 'Equip: Increased Fishing +20.' }")) == 20)
check("bonus: a lure line on the pole doesn't count", bonus(lua.eval("{ 'Pole', 'Shiny Bauble (+25 Fishing)' }")) == 0)
check("bonus: Spanish tooltip works with the game's own words",
      lua.eval("DufforthTweaksHelperFishing.Bonus({ 'Equipar: Pesca aumentada +15.' }, 'Pesca', 'Equipar:')") == 15)
plan = lua.eval("""function(bag, worn) local p, n = DufforthTweaksHelperFishing.GearPlan(bag, worn); return p, n end""")
p, n = plan(lua.eval("{ {id=6256, slot=16, bonus=0}, {id=6366, slot=16, bonus=15}, {id=7996, slot=1, bonus=5} }"),
            lua.eval("{ [16] = {id=2000, bonus=0, pole=false}, [1] = {id=2002, bonus=0} }"))
check("gear: the best pole and a fishing hat go on", p[16] == 6366 and p[1] == 7996 and n == 2, (p[16], p[1], n))
p, n = plan(lua.eval("{ {id=6256, slot=16, bonus=0} }"), lua.eval("{ [16] = {id=6366, bonus=15, pole=true} }"))
check("gear: a worse pole stays in the bags", n == 0)

_act = lua.eval("function(t) return {DufforthTweaksHelperFishing.Action(t)} end")
act = lambda t: tuple(_act(t).values())
S = lambda **k: lua.table_from(k)
POLE = lua.eval("{ [16] = 6256 }")
check("action: never in combat", act(S(combat=True, spell=7620, pole=True)) == ("none", "combat"))
check("action: no Fishing = nothing", act(S(spell=None)) == ("none", "unknown"))
check("action: bobber out = hook", act(S(spell=7620, pole=True, channel=True))[0] == "hook")
check("action: no pole on, one in bags = gear", act(S(spell=7620, pole=False, plan=POLE, planCount=1, freeSlots=2))[0] == "gear")
check("action: bags full with an off hand = say so", act(S(spell=7620, pole=False, plan=POLE, planCount=1, offHand=True, freeSlots=0)) == ("none", "bagsfull"))
check("action: no pole anywhere = say so", act(S(spell=7620, pole=False, planCount=0)) == ("none", "nopole"))
check("action: pole without lure, lure in bags = lure first", act(S(spell=7620, pole=True, lure=False, lureInBag=6532)) == ("lure", 6532))
check("action: pole with lure = cast", act(S(spell=7620, pole=True, lure=True, lureInBag=6532)) == ("cast", 7620))
run("DufforthTweaksHelperFishing.SetOpt('lure', false)")
check("action: lure option off = cast without one", act(S(spell=7620, pole=True, lure=False, lureInBag=6532)) == ("cast", 7620))
run("DufforthTweaksHelperFishing.SetOpt('pole', false)")
check("action: gear option off = no auto equip", act(S(spell=7620, pole=False, plan=POLE, planCount=1, freeSlots=2)) == ("none", "nopole"))
run("DufforthTweaksHelperFishing.SetOpt('lure', true); DufforthTweaksHelperFishing.SetOpt('pole', true)")
a = F.Attributes("lure", 6532)
check("attributes: a lure is used on the pole (slot 16)", a.type == "macro" and a.macrotext == "/use item:6532\n/use 16")
check("attributes: gear by slot, the pole first", F.Attributes("gear", lua.eval("{ [1] = 7996, [16] = 6366 }")).macrotext == "/equipslot 16 item:6366\n/equipslot 1 item:7996")
check("attributes: cast by spell id (names can be secret on Forever)", F.Attributes("cast", 18248).spell == 18248)
check("key: modifiers in the game's order", F.KeyName("F", True, False, True) == "ALT-SHIFT-F" and F.KeyName("F", False, False, False) == "F")
check("key: a lone modifier is not a key", F.KeyName("LSHIFT", False, False, True) is None)
pat = F.Pattern("Requires Fishing %d")
check("pattern: the game's message formats", pat == "^Requires Fishing (%d+)$", pat)
w = F.Wanted(lua.eval("{ interact = true, marker = true, loot = false, sound = true }"), lua.eval("function(n) return CVARS[n] end"))
check("cvars: bobber in reach (arc raised to 2, a longer range kept), its nameplate, the splash",
      w.SoftTargetInteract == "3" and w.SoftTargetInteractArc == "2" and w.SoftTargetInteractRange is None
      and w.SoftTargetIconGameObject == "1" and w.Sound_EnableMusic == "0" and w.autoLootDefault is None)

# ---- Loading: events registered in pcall, nothing in chat ----
evs = lua.eval("DufforthTweaksHelperFishing.events.events")
check("events: casting, loot, errors, combat and the bobber's nameplate", all(evs[e] for e in
      ("UNIT_SPELLCAST_CHANNEL_START", "LOOT_READY", "UI_ERROR_MESSAGE", "PLAYER_REGEN_DISABLED", "PLAYER_SOFT_INTERACT_CHANGED")))
check("events: registered in pcall (an unknown event can't break loading)", "pcall(events.RegisterEvent" in (ADDON / "Fishing.lua").read_text(encoding="utf-8"))

# ---- Gear: the press puts on the best pole and hat, they're remembered and go back ----
run("BAG = { { 6256, 1 }, { 6366, 1 }, { 7996, 1 }, { 6529, 5 } }")
ev("PLAYER_LOGIN")
check("login: hooks the world's right-click", lua.eval("WorldFrame.scripts.OnMouseUp") is not None)
check("button: casts on release only", attr("useOnKeyDown") is False)
check("gear: the button puts on the best pole, then the hat", attr("type") == "macro" and attr("macrotext") == "/equipslot 16 item:6366\n/equipslot 1 item:7996", attr("macrotext"))
press()
run("SLOTS = { [16] = 6366, [1] = 7996 }")
check("gear: what it replaced is remembered", lua.eval("DufforthTweaksHelperDB.fishing.weapons[16]") == 2000
      and lua.eval("DufforthTweaksHelperDB.fishing.weapons[17]") == 2001 and lua.eval("DufforthTweaksHelperDB.fishing.weapons[1]") == 2002)
ev("PLAYER_EQUIPMENT_CHANGED")
check("lure: next press puts the lure on the pole", attr("macrotext") == "/use item:6529\n/use 16", attr("macrotext"))
run("ENCHANT = 600000"); ev("UNIT_INVENTORY_CHANGED", "player")
check("cast: then it casts your best rank", attr("type") == "spell" and attr("spell") == 18248 and attr("macrotext") is None)
check("bar: shown with a pole on, skill and pole bonus (not the lure)", lua.eval("DufforthTweaksHelperFishingBar:IsShown()") is True
      and "Fishing 210 +15" in lua.eval("DufforthTweaksHelperFishingBar.title:GetText()"), lua.eval("DufforthTweaksHelperFishingBar.title:GetText()"))
check("bar: lure time and a Weapons button", "lure 10:00" in lua.eval("DufforthTweaksHelperFishingBar.title:GetText()")
      and lua.eval("DufforthTweaksHelperFishingBar.back:IsShown()") is True)
check("bar: its icon is a secure button with the same action", lua.eval("DufforthTweaksHelperFishBarButton:GetAttribute('spell')") == 18248
      and lua.eval("DufforthTweaksHelperFishBarButton.template") == "SecureActionButtonTemplate")

# ---- The key: casts on release; hooks only once the bobber landed and the key is up ----
check("key: none set = no binding", key("SHIFT-F") is None)
run("DufforthTweaksHelperFishing.SetKey('SPACE')")
check("key: Space casts, Shift+Space still jumps", key("SPACE") == "CLICK DufforthTweaksHelperFishButton" and key("SHIFT-SPACE") == "JUMP")
run("DufforthTweaksHelperFishing.SetKey('SHIFT-F')")
check("key: casts through the secure button", key("SHIFT-F") == "CLICK DufforthTweaksHelperFishButton" and key("SHIFT-SPACE") is None)
run("local b = DufforthTweaksHelperFishButton; b.scripts.PreClick(b, 'LeftButton', false)")
check("key: a release without its own press casts nothing", attr("type") is None)
run("local b = DufforthTweaksHelperFishButton; b.scripts.PostClick(b, 'LeftButton', false)")
check("key: ...and the button is back to casting", attr("type") == "spell")
run("HELD.F = true; CHANNEL = 18248"); ev("UNIT_SPELLCAST_CHANNEL_START", "player")
check("session: a cast starts it; bobber soft target, auto loot, louder splash", lua.eval("DufforthTweaksHelperFishing.ModeIsOn()") is True
      and cvar("SoftTargetInteract") == "3" and cvar("autoLootDefault") == "1" and float(cvar("Sound_SFXVolume")) == 1 and cvar("Sound_EnableMusic") == "0")
check("key: unchanged while still held after the cast", key("SHIFT-F") == "CLICK DufforthTweaksHelperFishButton")
run("HELD.F = false; Run(0.1)")
check("key: does nothing until the bobber lands", key("SHIFT-F") == "CLICK DufforthTweaksHelperFishWait")
run("SOFT = BOBBER_GUID"); ev("PLAYER_SOFT_INTERACT_CHANGED"); run("Run(0.1)")
check("key: hooks once your bobber is the interact target", key("SHIFT-F") == "INTERACTTARGET")
check("mark: shown on your bobber, the game's own icon steps aside", lua.eval("DufforthTweaksHelperFishing.MarkShown()") is True and lua.eval("PLATE.UnitFrame.SoftTargetFrame.alpha") == 0)
check("bar: says to hook", "hook" in lua.eval("DufforthTweaksHelperFishingBar.status:GetText()"))
run("HELD.F = true; CHANNEL = nil; SOFT = nil"); ev("UNIT_SPELLCAST_CHANNEL_STOP", "player"); run("Run(0.5)")
check("mark: gone with the line", lua.eval("DufforthTweaksHelperFishing.MarkShown()") is False and lua.eval("PLATE.UnitFrame.SoftTargetFrame.alpha") == 1)
check("key: stays the hook key while the hooking press is held", key("SHIFT-F") == "INTERACTTARGET")
run("HELD.F = false; Run(0.2)")
check("key: back to casting once let go", key("SHIFT-F") == "CLICK DufforthTweaksHelperFishButton")
run("CHANNEL = 18248"); ev("UNIT_SPELLCAST_CHANNEL_START", "player"); run("Run(1.6)")
check("key: a bobber the game won't name gets the hook key after 1.5 s", key("SHIFT-F") == "INTERACTTARGET")
run("CHANNEL = nil"); ev("UNIT_SPELLCAST_CHANNEL_STOP", "player"); run("Run(0.5)")
ev("UNIT_SPELLCAST_CHANNEL_START", "target")
check("events: other units are ignored", key("SHIFT-F") == "CLICK DufforthTweaksHelperFishButton")

# ---- What you caught, what got away, what the zone needs ----
run("LOOT = { { 6303, 'Raw Slitherskin Mackerel', 1 }, { 6358, 'Oily Blackmouth', 2 } }"); ev("LOOT_READY"); ev("LOOT_OPENED")
check("loot: LOOT_READY then LOOT_OPENED count once", lua.eval("DufforthTweaksHelperFishing.Session(false).catches") == 1)
check("card: what you caught, first catch marked", lua.eval("DufforthTweaksHelperFishCatch:IsShown()") is True
      and "First catch" in lua.eval("DufforthTweaksHelperFishCatch.lines[2]:GetText()"))
run("Run(4.1)")
check("card: gone after a few seconds", lua.eval("DufforthTweaksHelperFishCatch:IsShown()") is False)
run("Run(60); LOOT = { { 6303, 'Raw Slitherskin Mackerel', 1 } }"); ev("LOOT_OPENED")
check("card: a repeat catch shows its worth", "1s" not in lua.eval("DufforthTweaksHelperFishCatch.lines[2]:GetText()") and "95c" in lua.eval("DufforthTweaksHelperFishCatch.lines[2]:GetText()"),
      lua.eval("DufforthTweaksHelperFishCatch.lines[2]:GetText()"))
run("FISHLOOT = false; LOOT = { { 2000, 'Sword', 1 } }; Run(2)"); ev("LOOT_OPENED"); run("FISHLOOT = true")
s = lua.eval("DufforthTweaksHelperFishing.Session(false)")
check("loot: catches and fish counted, other loot not", s.catches == 2 and s.fish == 4 and s["items"][2000] is None, (s.catches, s.fish))
check("loot: all-time and zone counts kept in saved data", lua.eval("DufforthTweaksHelperDB.fishing.caught[6303].count") == 2
      and lua.eval("DufforthTweaksHelperDB.fishing.zones.Durotar.catches") == 2 and lua.eval("DufforthTweaksHelperDB.fishing.zones.Durotar.casts") == 2)
check("rate: catches an hour (at least a minute counted)", abs(F.PerHour(s, s.start + 60) - 2 * 3600 / 60) < 1e-9)
check("value: AH after its cut, else what a vendor pays", F.Value(6303) == 95 and F.Value(9999) == 7)
rows, total = F.Rows(s["items"], F.Value)
check("rows: most caught first (ties by name), worth count x value", rows[1].name == "Oily Blackmouth" and rows[2].count == 2 and total == 2 * 95 + 2 * 190, total)
run("SOUNDS = {}")
ev("UI_ERROR_MESSAGE", 1, "Your fish got away!")
check("escape: counted, with its sound (on by default)", s.escapes == 1 and vals("SOUNDS") == [847])
ev("UI_ERROR_MESSAGE", 1, "Requires Fishing 205")
check("zone: the skill it needs is learned from the game's message", lua.eval("DufforthTweaksHelperDB.fishing.zones.Durotar.need") == 205)
check("sound: catch sound off by default", 878 not in vals("SOUNDS"))

# ---- Double right-click ----
run("Run(5)")
def click(hold=0.05, moved=0):
    run(f"DufforthTweaksHelperFishing.WorldMouseDown('RightButton'); CURSOR[1] = CURSOR[1] + {moved}; NOW = NOW + {hold}; DufforthTweaksHelperFishing.WorldMouseUp('RightButton'); Run(0)")
click()
check("double-click: a quick right-click arms the right button", key("BUTTON2") == "CLICK DufforthTweaksHelperFishButton")
press(); run("Run(0)")
check("double-click: the second click casts and right-click is normal again", key("BUTTON2") is None and lua.eval("DufforthTweaksHelperFishing.IsArmed()") is False)
click(); run("Run(0.5)")
check("double-click: no second click = disarmed after a moment", key("BUTTON2") is None)
click(hold=0.5)
check("double-click: a long first click (turning the camera) arms nothing", key("BUTTON2") is None)
click(moved=40)
check("double-click: a drag arms nothing", key("BUTTON2") is None)
click()
run("local b = DufforthTweaksHelperFishButton; b.scripts.PreClick(b, 'LeftButton', true); NOW = NOW + 0.3; b.scripts.PreClick(b, 'LeftButton', false)")
check("double-click: a held second click is the camera, it casts nothing", attr("type") is None)
run("local b = DufforthTweaksHelperFishButton; b.scripts.PostClick(b, 'LeftButton', false); Run(0.5)")
check("double-click: ...and the button casts again after", attr("type") == "spell" and key("BUTTON2") is None)
run("MOUSEOVER = true"); click(); run("MOUSEOVER = false")
check("double-click: on a person or monster stays normal", key("BUTTON2") is None)
run("GameTooltip.shown = true; GameTooltip.GetOwner = function() return UIParent end"); click(); run("GameTooltip.shown = false")
check("double-click: on something in the world you could loot stays normal", key("BUTTON2") is None)
run("MOUNTED = true"); click(); run("MOUNTED = false")
check("double-click: not while mounted", key("BUTTON2") is None)
run("CHANNEL = 18248"); click(); run("CHANNEL = nil")
check("double-click: never while your line is out", key("BUTTON2") is None)
run("DufforthTweaksHelperFishing.SetOpt('doubleClick', false)"); click()
check("double-click: off = nothing", key("BUTTON2") is None)
run("DufforthTweaksHelperFishing.SetOpt('doubleClick', true)")

# ---- Settings back only where still ours; a switch changed while fishing ----
run("DufforthTweaksHelperFishing.Begin(); CVARS.Sound_SFXVolume = '0.7'")
run("DufforthTweaksHelperFishing.SetOpt('loot', false)")
check("option: auto loot off while fishing = your setting back now", cvar("autoLootDefault") == "0")
run("DufforthTweaksHelperFishing.SetOpt('loot', true); DufforthTweaksHelperFishing.ModeOff()")
check("restore: your own change meanwhile is kept, the rest goes back", cvar("Sound_SFXVolume") == "0.7" and cvar("Sound_EnableMusic") == "1" and cvar("SoftTargetInteract") == "1")
run("CVARS.Sound_SFXVolume = '0.4'")

# ---- Combat: everything stops before the fight; nothing is changed during it ----
click()
run("DufforthTweaksHelperFishing.Begin()")
ev("PLAYER_REGEN_DISABLED")
check("combat: every binding off before the lock", key("SHIFT-F") is None and key("BUTTON2") is None)
check("combat: settings back, bar hidden", cvar("Sound_SFXVolume") == "0.4" and cvar("autoLootDefault") == "0"
      and lua.eval("DufforthTweaksHelperFishingBar:IsShown()") is False)
run("COMBAT = true")
ok = lua.eval("function() return pcall(function() local F = DufforthTweaksHelperFishing; F.OnEvent('BAG_UPDATE_DELAYED'); F.Refresh(); F.WorldMouseDown('RightButton'); F.WorldMouseUp('RightButton'); Run(1); F.SetKey('G'); F.GearBack(); F.OnEvent('UNIT_SPELLCAST_CHANNEL_START', 'player') end) end")()
check("combat: refresh, clicks, key and gear changes do nothing (no blocked action)", ok is True and key("SHIFT-F") is None and key("G") is None, ok)
check("combat: weapons stay until it ends", lua.eval("#EQUIPPED_LOG") == 0)
run("COMBAT = false"); ev("PLAYER_REGEN_ENABLED"); run("Run(0.6)")
check("after combat: weapons and own hat back (off hand once the weapon is in)", vals("EQUIPPED_LOG") == ["2000@16", "2002@1", "2001@17"], vals("EQUIPPED_LOG"))
check("after combat: the key casts again", key("SHIFT-F") is not None)

# ---- Idle: the fishing time ends by itself; the "cast again" sound ----
run("SLOTS = { [16] = 6366 }; DufforthTweaksHelperDB.fishing.weapons = { [16] = 2000 }; EQUIPPED_LOG = {}; SOUNDS = {}")
run("DufforthTweaksHelperFishing.SetOpt('alertRemind', true); CHANNEL = 18248"); ev("UNIT_SPELLCAST_CHANNEL_START", "player")
run("CHANNEL = nil"); ev("UNIT_SPELLCAST_CHANNEL_STOP", "player"); run("Run(0.5)")
run("Run(25); DufforthTweaksHelperFishing.Tick()")
check("remind: a sound after 20 s with no line out", vals("SOUNDS") == [8960])
run("Run(30); DufforthTweaksHelperFishing.Tick()")
check("remind: only once", vals("SOUNDS") == [8960] and lua.eval("DufforthTweaksHelperFishing.ModeIsOn()") is True)
run("Run(40); DufforthTweaksHelperFishing.Tick()")
check("idle: 90 s after the last cast, settings and weapons back", lua.eval("DufforthTweaksHelperFishing.ModeIsOn()") is False
      and cvar("Sound_SFXVolume") == "0.4" and vals("EQUIPPED_LOG") == ["2000@16"])

# ---- A /reload while fishing: the session stays, the next login puts settings back ----
run("SLOTS = { [16] = 6366 }; DufforthTweaksHelperFishing.Begin()")
check("reload: your settings kept in saved data", lua.eval("DufforthTweaksHelperDB.fishing.savedCVars.Sound_SFXVolume.old") == "0.4")
ev("PLAYER_LOGIN")
check("reload: login puts them back, the session stays", cvar("Sound_SFXVolume") == "0.4" and lua.eval("DufforthTweaksHelperDB.fishing.savedCVars") is None
      and lua.eval("DufforthTweaksHelperFishing.Session(false).catches") == 2)
run("NOW = NOW + 2000; CHANNEL = 18248"); ev("UNIT_SPELLCAST_CHANNEL_START", "player"); run("CHANNEL = nil; DufforthTweaksHelperFishing.ModeOff(); Run(0.2)")
check("session: a cast after a long break starts new counters", lua.eval("DufforthTweaksHelperFishing.Session(false).catches") == 0)

# ---- No pole anywhere, bags full ----
run("SLOTS = { [16] = 2000, [17] = 2001 }; BAG = { { 6256, 1 } }; FREE = 0"); ev("BAG_UPDATE_DELAYED")
check("bags full: the button does nothing and says why", attr("type") is None and "Make room" in lua.eval("DufforthTweaksHelperFishingBar.status:GetText()"))
run("BAG = {}; FREE = 4"); ev("BAG_UPDATE_DELAYED")
check("no pole: says so, bar hidden", "fishing pole" in lua.eval("DufforthTweaksHelperFishingBar.status:GetText()") and lua.eval("DufforthTweaksHelperFishingBar:IsShown()") is False)
check("no pole: the fishing key keeps its normal use", key("SHIFT-F") is None)

# ---- The Fishing tab ----
run("SLOTS = { [16] = 6366 }; ENCHANT = 60000; LOOT = { { 6303, 'Raw Slitherskin Mackerel', 2 } }; Run(2)"); ev("LOOT_OPENED")
run("PAGE = CreateFrame('Frame'); DufforthTweaksHelperFishing.BuildPanel(PAGE, 504)")
texts = lambda: "\n".join(str(f.text) for f in lua.eval("ALL").values() if f.kind == "FontString" and f.text)
t = texts()
check("tab: skill, status and the key", "Fishing 210 +15" in t and "SHIFT-F or double right-click to cast" in t, t[:300])
check("tab: what you caught, with its worth, and this zone", "2 x Raw Slitherskin Mackerel" in t and "worth" in t and "Here (Durotar)" in t and "needs Fishing 205" in t)
boxes = [f for f in lua.eval("ALL").values() if f.template == "UICheckButtonTemplate"]
check("tab: a switch per perk", len(boxes) == 13, len(boxes))
boxes[5].checked = False
boxes[5].scripts.OnClick(boxes[5])
check("tab: a switch turns its perk off", lua.eval("DufforthTweaksHelperDB.fishing.sound") is False)
run("DufforthTweaksHelperFishing.SetOpt('sound', true)")
keyb = lua.eval("(function() for _, f in ipairs(ALL) do if f.template == 'UIPanelButtonTemplate' and f.text == 'SHIFT-F' then return f end end end)()")
keyb.scripts.OnClick(keyb, "LeftButton")
cap = [f for f in lua.eval("ALL").values() if f.scripts.OnKeyDown][0]
check("tab: key button waits for a key", cap.shown is True and "Press a key" in keyb.text)
run("IsShiftKeyDown = function() return true end")
cap.scripts.OnKeyDown(cap, "LSHIFT")
check("tab: a lone Shift keeps waiting", cap.shown is True)
cap.scripts.OnKeyDown(cap, "G")
check("tab: Shift+G becomes the key", lua.eval("DufforthTweaksHelperDB.fishing.key") == "SHIFT-G" and key("SHIFT-G") is not None and key("SHIFT-F") is None)
keyb.scripts.OnClick(keyb, "RightButton")
check("tab: right-click clears the key", lua.eval("DufforthTweaksHelperDB.fishing.key") is None and key("SHIFT-G") is None)
run("C_AddOns = { IsAddOnLoaded = function(n) return n == 'GaapOneKeyFishing' end }; DufforthTweaksHelperFishing.Refresh()")
check("tab: warns when Gaap One-Key Fishing is on too", "Gaap One-Key Fishing is on too" in texts())

# ---- Fishing food ----
run("SLOTS = { [16] = 6366 }; ENCHANT = 60000; BAG = { { 3001, 5 }, { 3000, 2 } }"); ev("BAG_UPDATE_DELAYED")
check("food: the press eats the food that gives Fishing (not plain bread)", attr("macrotext") == "/use item:3000", attr("macrotext"))
check("food: the bar says so", "eat your fishing food" in lua.eval("DufforthTweaksHelperFishingBar.status:GetText()"))
run("BUFFS = { 'Well Fed: Fishing increased by 10.' }"); ev("UNIT_INVENTORY_CHANGED", "player")
check("food: with the fishing buff on, it casts", attr("type") == "spell")
run("BUFFS = {}; DufforthTweaksHelperFishing.SetOpt('food', false)"); ev("BAG_UPDATE_DELAYED")
check("food: switch off = casts without eating", attr("type") == "spell")
run("DufforthTweaksHelperFishing.SetOpt('food', true); BAG = {}"); ev("BAG_UPDATE_DELAYED")

# ---- Fished-up chests ----
run("Run(2); LOOT = { { 6351, 'Battered Chest', 1 } }"); ev("LOOT_OPENED")
run("COUNTS = { [6351] = 1, [6303] = 4 }; LOOTSRC = 'Item-1-0-ABC'; FISHLOOT = false; LOOT = { { 2000, 'Sword', 1 } }"); ev("LOOT_OPENED")
run("MONEY = 1250; COUNTS[6351] = 0"); ev("LOOT_CLOSED"); run("Run(0.6); FISHLOOT = true")
s2 = lua.eval("DufforthTweaksHelperFishing.Session(false)")
check("chest: opening one you caught counts its loot and coins", s2.chests == 1 and s2.chestMoney == 250 and s2["chestItems"][2000].count == 1, (s2.chests, s2.chestMoney))
run("LOOTSRC = 'Creature-0-1-2-3-4-5'; FISHLOOT = false; LOOT = { { 2000, 'Sword', 1 } }"); ev("LOOT_OPENED")
run("COUNTS[6303] = 3"); ev("LOOT_CLOSED"); run("Run(0.6); FISHLOOT = true")
check("chest: a monster's loot is not a chest", s2.chests == 1)
run("Run(2); LOOTSRC = 'Item-1-0-DEF'; FISHLOOT = false; LOOT = { { 2000, 'Sword', 1 } }"); ev("LOOT_OPENED")
ev("LOOT_CLOSED"); run("Run(0.6); FISHLOOT = true")
check("chest: an item you didn't fish up is not counted", s2.chests == 1)

# ---- Keys: jump, lure, gear ----
run("SLOTS = { [16] = 6366 }; ENCHANT = 60000; BAG = { { 6529, 3 } }; DufforthTweaksHelperFishing.SetKey('SPACE')")
check("jump: with Space as the fishing key, Shift+Space jumps", key("SPACE") == "CLICK DufforthTweaksHelperFishButton" and key("SHIFT-SPACE") == "JUMP")
run("DufforthTweaksHelperFishing.SetKey('ALT-SPACE', 'jumpKey')")
check("jump: your own jump key", key("ALT-SPACE") == "JUMP" and key("SHIFT-SPACE") is None)
run("DufforthTweaksHelperFishing.SetKey('SHIFT-F')")
check("jump: not taken when the fishing key isn't your jump key", key("ALT-SPACE") is None)
run("DufforthTweaksHelperFishing.SetKey('L', 'lureKey'); DufforthTweaksHelperFishing.SetKey('K', 'gearKey')")
check("lure key: puts your best lure on (even with one on)", key("L") == "CLICK DufforthTweaksHelperFishLureButton"
      and lua.eval("DufforthTweaksHelperFishLureButton:GetAttribute('macrotext')") == "/use item:6529\n/use 16")
check("gear key: nothing to swap = the key stays yours", key("K") is None)
run("SLOTS = { [16] = 2000 }; BAG = { { 6366, 1 } }"); ev("BAG_UPDATE_DELAYED")
check("gear key: puts the fishing gear on", key("K") == "CLICK DufforthTweaksHelperFishGearButton"
      and lua.eval("DufforthTweaksHelperFishGearButton:GetAttribute('macrotext')") == "/equipslot 16 item:6366")
run("local g = DufforthTweaksHelperFishGearButton; g.scripts.PreClick(g); SLOTS = { [16] = 6366 }; BAG = { { 2000, 1 } }"); ev("PLAYER_EQUIPMENT_CHANGED")
check("gear key: remembers your weapon, then puts it back", lua.eval("DufforthTweaksHelperDB.fishing.weapons[16]") == 2000
      and key("K") == "CLICK DufforthTweaksHelperFishGearButton" and lua.eval("DufforthTweaksHelperFishGearButton:GetAttribute('type')") is None)
run("EQUIPPED_LOG = {}; local g = DufforthTweaksHelperFishGearButton; g.scripts.PreClick(g)")
check("gear key: ...on the next press", vals("EQUIPPED_LOG") == ["2000@16"] and lua.eval("DufforthTweaksHelperDB.fishing.weapons") is None)
run("DufforthTweaksHelperFishing.SetKey('L', 'key')")
check("keys: a key given to one is taken from the other", lua.eval("DufforthTweaksHelperDB.fishing.lureKey") is None and lua.eval("DufforthTweaksHelperDB.fishing.key") == "L")
run("DufforthTweaksHelperFishing.SetKey('SHIFT-F'); DufforthTweaksHelperFishing.SetKey(nil, 'gearKey')")

# ---- Volumes ----
run("SLOTS = { [16] = 6366 }; BAG = {}; DufforthTweaksHelperFishing.Begin(); DufforthTweaksHelperFishing.SetNum('volMusic', 0.3)")
check("volume: music at your level while fishing", cvar("Sound_EnableMusic") == "1" and float(cvar("Sound_MusicVolume") or 0) == 0.3)
check("volume: the game volume is yours unless you set it", cvar("Sound_MasterVolume") == "0.8")
run("DufforthTweaksHelperFishing.SetNum('volSFX', 0.8); DufforthTweaksHelperFishing.SetNum('volMaster', 1)")
check("volume: effects and game volume follow the steppers", float(cvar("Sound_SFXVolume")) == 0.8 and float(cvar("Sound_MasterVolume")) == 1)
run("DufforthTweaksHelperFishing.ModeOff()")
check("volume: all back after", float(cvar("Sound_SFXVolume")) == 0.4 and cvar("Sound_EnableMusic") == "1" and cvar("Sound_MusicVolume") == "0.5" and cvar("Sound_MasterVolume") == "0.8")
run("DufforthTweaksHelperFishing.SetNum('volMusic', 0); DufforthTweaksHelperFishing.SetNum('volSFX', 1); DufforthTweaksHelperFishing.SetNum('volMaster', -1)")

# ---- Codex (real FishingData.lua) ----
zones = list(F.CodexZones().values())
check("codex: real data, about 50 zones", len(zones) >= 40 and "Durotar" in zones, len(zones))
rows = F.CodexRows("Durotar")
check("codex: Durotar's coast first, with its chance", rows[1].id == 6303 and rows[1].pct == 98.0, (rows[1].id, rows[1].pct))
check("codex: named places with their own list as headers", any(r.head and "Southfury River" in r.head for r in rows.values()))
check("codex: your own catches next to the chance", rows[1].mine >= 2)
run("DufforthTweaksHelperDB.fishing.zones.Durotar.items[13755] = 1")
rows = F.CodexRows("Durotar")
check("codex: what you caught that the data doesn't list", any(r.head == "Also caught here (yours)" for r in rows.values()) and any(r.id == 13755 and r.pct is None for r in rows.values()))
names = lua.eval("DufforthTweaksHelperFishCodex.names")
missing = lua.eval("(function() local n = 0 for _, z in pairs(DufforthTweaksHelperFishCodex.zones) do for _, r in ipairs(z.loot) do if not DufforthTweaksHelperFishCodex.names[r[1]] then n = n + 1 end end end return n end)()")
check("codex: every fish has a name", missing == 0, missing)
run("DufforthTweaksHelperFishing.ShowView('codex')")
t = texts()
check("codex view: the zone and its fish, chests marked", "98.0%  Raw Slitherskin Mackerel" in t and "you: " in t and "(opens)" in t, [x for x in t.split("\n") if "%" in x][:3])
run("DufforthTweaksHelperFishing.codexZone = 'Stranglethorn Vale'; DufforthTweaksHelperFishing.Refresh()")
check("codex view: browse other zones", "Stranglethorn Vale" in texts() and "Raw Mithril Head Trout" in texts())
run("DufforthTweaksHelperFishing.ShowView('keys')")
t = texts()
check("keys view: four keys and four volumes", all(w in t for w in ("Jump while fishing", "Lure key", "Gear key", "Game volume", "Yours", "100%")))
run("DufforthTweaksHelperFishing.ShowView('main')")

# ---- Spanish ----
run("DufforthTweaksHelperLocale.Set('esES')")
lua.execute((ADDON / "Fishing.lua").read_text(encoding="utf-8"))
st = lua.eval("DufforthTweaksHelperFishing.StatusText({}, 'gear')")
check("spanish: the bar's text is Spanish", "equipo de pesca" in st, st)

check("chat: never a message", len(lua.eval("CHAT")) == 0, vals("CHAT")[:2])
print("FAILED" if failed else "ALL PASS")
sys.exit(1 if failed else 0)
