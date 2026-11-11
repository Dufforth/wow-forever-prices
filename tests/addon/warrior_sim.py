"""Runs the Warrior helper outside the game: which lines the macro gets at each level, stance
numbers, Battle Shout only when needed, the 255-character split, no edits in combat, and what
the next-ability icon shows.

    python tests/addon/warrior_sim.py
"""
import os
import sys
import lupa.lua51 as L

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ADDON = os.path.join(ROOT, "addon", "DufforthTweaksHelper")


def source(name):
    return open(os.path.join(ADDON, name), encoding="utf-8").read()


MOCK = r"""
NOW, COMBAT, CLASS = 1000, false, "WARRIOR"
SlashCmdList = {}
CHAT = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) CHAT[#CHAT+1] = m end }
GetTime = function() return NOW end
InCombatLockdown = function() return COMBAT end
UnitClass = function() return "Warrior", CLASS end
TIMERS = {}
C_Timer = { After = function(s, f) TIMERS[#TIMERS+1] = { s, f } end }

local function object(name)
  local o = { name = name, scripts = {}, attributes = {}, events = {} }
  function o:SetScript(k, f) self.scripts[k] = f end
  function o:SetAttribute(k, v) self.attributes[k] = v end
  function o:RegisterEvent(e) self.events[e] = true end
  function o:CreateTexture() return object() end
  function o:SetShown(v) self.shown = v end
  return setmetatable(o, { __index = function() return function() end end })
end
FRAMES = {}
SecureHandlerWrapScript = function(frame, script, header, pre) frame.wrapped = pre end
function CreateFrame(kind, name) local f = object(name); FRAMES[#FRAMES+1] = f; if name then _G[name] = f end; return f end
UIParent = object()

-- Spellbook: one tab with these names.
SPELLS = {}
GetNumSpellTabs = function() return 1 end
GetSpellTabInfo = function() return "General", nil, 0, #SPELLS end
GetSpellBookItemName = function(i) return SPELLS[i] end

-- Stance bar: spell ids in bar order.
FORMS, FORM = {}, 1
GetNumShapeshiftForms = function() return #FORMS end
GetShapeshiftFormInfo = function(i) return nil, false, true, FORMS[i] end
GetShapeshiftForm = function() return FORM end

-- Buffs: { name, expirationTime }.
BUFFS = {}
UnitBuff = function(_, i) local b = BUFFS[i]; if b then return b[1], nil, nil, nil, 120, b[2] end end

-- Macros.
MACROS, EDITS, CREATES = {}, 0, 0
GetMacroIndexByName = function(n) return MACROS[n] and 1 or 0 end
CreateMacro = function(n, icon, body) CREATES = CREATES + 1; MACROS[n] = body; return 1 end
EditMacro = function(i, n, icon, body) EDITS = EDITS + 1; MACROS[n] = body; return i end

-- Fight log and combat log.
bit = { band = function(a, b) local r, m = 0, 1; while a > 0 and b > 0 do if a % 2 == 1 and b % 2 == 1 then r = r + m end; a, b, m = math.floor(a/2), math.floor(b/2), m*2 end; return r end }
time = function() return 1700000000 end
UnitGUID = function(u) return u == "player" and "Player-1" or nil end
RAGE, THP, INCOMBAT = 40, 50, false
UnitPower = function() return RAGE end
UnitExists = function(u) return u == "target" end
UnitHealth = function() return THP end
UnitHealthMax = function() return 100 end
UnitCanAttack = function() return true end
UnitName = function() return "Kobold" end
UnitLevel = function(u) return u == "player" and 12 or 8 end
UnitIsDead = function() return false end
UnitAffectingCombat = function() return INCOMBAT end
IsInGroup = function() return false end
GetRealZoneText = function() return "Elwynn Forest" end
IsUsableSpell = function(n) return n == "Heroic Strike" end
GetSpellCooldown = function() return 0, 0 end
GetSpellInfo = function(id) return ({ [78] = "Heroic Strike", [772] = "Rend" })[id] end
"""

lua = L.LuaRuntime(unpack_returned_tuples=True)
lua.execute(MOCK)
lua.execute(source("Core.lua"))
lua.execute(source("Warrior.lua"))
g = lua.globals()
W = g.DufforthTweaksHelperWarrior
fails = []


def check(name, ok):
    print(("ok   " if ok else "FAIL ") + name)
    if not ok:
        fails.append(name)


def setup(spells, forms):
    g.SPELLS = lua.table_from(spells)
    g.FORMS = lua.table_from(forms)


def macro():
    return g.MACROS[W.MACRO_NAME]


def update():
    W.state.body = None  # force a rewrite, as if nothing was saved yet
    return W.Update()


def everything():
    return macro()


def steps_text():
    return ""  # there is no second part any more


# Level 1: Battle Stance, Heroic Strike, Battle Shout.
setup(["Attack", "Battle Stance", "Heroic Strike", "Battle Shout"], [2457])
check("level 1 macro is written", update() is True and g.CREATES == 1)
check("level 1: attack, shout, Heroic Strike", macro() == "/startattack\n/castsequence reset=120 Battle Shout,nil\n/cast [form:1] Heroic Strike")

# Level 12: Defensive Stance and some battle spells; Execute and Revenge not yet.
setup(["Battle Stance", "Defensive Stance", "Heroic Strike", "Battle Shout", "Charge", "Rend", "Overpower", "Sunder Armor"], [2457, 71])
update()
lines = macro().split("\n")
check("Charge before the fight (off the global cooldown, rejected harmlessly where it can't be used)", "/cast [nocombat] Charge" in lines)
check("one global-cooldown line per stance: Overpower in Battle, Sunder then Heroic Strike in Defensive",
      "/cast [form:1] Overpower" in lines and "/castsequence [form:2] Sunder Armor,Heroic Strike" in lines)
check("no Intercept, Whirlwind or Execute before you learn them", not any(x in macro() for x in ("Intercept", "Whirlwind", "Execute", "Mortal")))
check("an update to the existing macro edits it", g.EDITS == 1 and g.CREATES == 1)
check("Rend once, before the stance lines", lines.index("/castsequence reset=12 Rend,nil") < lines.index("/castsequence [form:2] Sunder Armor,Heroic Strike"))
check("no hidden button: everything is in the one macro", "/click" not in macro())

# Stance numbers follow the bar, not a fixed list: Berserker as the second stance.
setup(["Battle Stance", "Berserker Stance", "Whirlwind", "Heroic Strike"], [2457, 2458])
update()
check("Berserker on slot 2 uses form:2", "/castsequence [form:2] Whirlwind,Heroic Strike" in macro())

# Everything learned.
ALL = ["Battle Stance", "Defensive Stance", "Berserker Stance", "Heroic Strike", "Battle Shout", "Charge", "Intercept",
       "Victory Rush", "Sweeping Strikes", "Revenge", "Execute", "Overpower", "Shield Slam", "Mortal Strike",
       "Bloodthirst", "Whirlwind", "Sunder Armor", "Cleave"]
setup(ALL, [2457, 71, 2458])
g.IsEquippedItemType = lambda kind: kind == "Shields"
update()
body = macro()
check("macro fits the 255-character limit", len(body) <= 255)
check("Defensive Stance with a shield: Shield Slam, Revenge, Sunder, Heroic Strike in one sequence",
      "/castsequence [form:2] Shield Slam,Revenge,Sunder Armor,Heroic Strike" in body)
check("solo: Heroic Strike, no Cleave", "Heroic Strike" in body and "Cleave" not in body)
check("Berserker Stance: Bloodthirst then Heroic Strike", "/castsequence [form:3] Bloodthirst,Heroic Strike" in body)
check("level 60 macro still fits", len(body) <= 255)
g.IsInGroup = lambda: True
update()
check("in a group: Cleave instead of Heroic Strike", "Cleave" in macro() and "Heroic Strike" not in macro())
g.IsInGroup = lambda: False
g.IsEquippedItemType = lambda kind: False
update()
check("without a shield: no Shield Slam, Shield Block or Revenge (Revenge would wait for blocks)",
      "Shield" not in macro().replace("Battle Shout", "") and "Revenge" not in macro())

# Battle Shout: left out while the buff has time, with a timer to add it back.
g.BUFFS = lua.table_from([lua.table_from(["Battle Shout", 1100])])  # 100 s left
g.TIMERS = lua.table_from([])
update()
check("shout left out while the buff has 100 s left", "Battle Shout" not in macro() + steps_text())
check("a timer brings it back before it runs out", len(g.TIMERS) == 1 and abs(g.TIMERS[1][1] - 56) < 1e-6)
g.BUFFS = lua.table_from([lua.table_from(["Battle Shout", 1030])])  # 30 s left
update()
check("shout added back when under 45 s are left", "Battle Shout" in macro())

# Unchanged macro is not rewritten (that would reset the shout sequence).
edits = g.EDITS
check("unchanged macro is not edited again", W.Update() is False and g.EDITS == edits)

# In combat nothing is written; it waits for the fight to end.
g.COMBAT = True
g.BUFFS = lua.table_from([])
check("no edits in combat", update() is False and W.state.pending is True and g.EDITS == edits)
g.COMBAT = False
handler = [f for f in g.FRAMES.values() if f.events["SPELLS_CHANGED"]][0]
handler.scripts["OnEvent"](handler, "PLAYER_REGEN_ENABLED")
check("leaving combat writes it", g.EDITS == edits + 1 and W.state.pending is False)

# Charge can be turned off.
W.Options().charge = False
update()
check("charge off removes Charge and Intercept", "Charge" not in macro() and "Intercept" not in macro())
W.Options().charge = True

# Not a warrior: nothing happens.
g.CLASS = "MAGE"
check("other classes get no macro", update() is False and W.state.status == "Only for warriors.")
g.CLASS = "WARRIOR"

# The icon follows the macro's order.
known = lua.table_from({s: True for s in ALL})


def next_spell(ready, **facts):
    base = {"known": known, "stance": 1, "inCombat": True, "inGroup": False, "shoutLeft": 60, "shoutInMacro": True, "charge": True}
    base.update(facts)
    return W.NextSpell(lua.table_from(base), lambda name: name in ready)


check("Execute is a prompt for its own key, not the button's pick", W.OwnKeyPrompt(lua.table_from({"known": known, "stance": 1}), lambda n: n == "Execute") == "Execute"
      and next_spell({"Execute", "Heroic Strike"}) == "Heroic Strike")
check("Battle Stance: Overpower after a dodge, before Heroic Strike", next_spell({"Overpower", "Heroic Strike"}, rendOnTarget=True) == "Overpower")
check("Charge only out of combat", next_spell({"Charge", "Heroic Strike"}, inCombat=False) == "Charge"
      and next_spell({"Charge", "Heroic Strike"}) == "Heroic Strike")
check("Battle Shout when the buff is gone", next_spell({"Battle Shout", "Mortal Strike"}, shoutLeft=None) == "Battle Shout")
check("Defensive Stance: Shield Slam, then Revenge", next_spell({"Revenge", "Shield Slam"}, stance=2, rendOnTarget=True, shield=True) == "Shield Slam"
      and next_spell({"Revenge", "Sunder Armor"}, stance=2, rendOnTarget=True, shield=True) == "Revenge")
check("Defensive Stance: Sunder when Execute and Revenge can't be used", next_spell({"Sunder Armor"}, stance=2, rendOnTarget=True) == "Sunder Armor")
check("in a group, Cleave instead of Heroic Strike", next_spell({"Cleave", "Heroic Strike"}, inGroup=True) == "Cleave")
check("nothing ready shows nothing", next_spell(set()) is None)

# ---- Fight log ----
g.INCOMBAT = True
log_frame = [f for f in g.FRAMES.values() if f.events["COMBAT_LOG_EVENT_UNFILTERED"]][0]


def fire(event, *args):
    log_frame.scripts["OnEvent"](log_frame, event, *args)


HOSTILE = 0x40
setup(ALL, [2457, 71, 2458])
update()
g.NOW = 2000
fire("PLAYER_REGEN_DISABLED")
check("a fight starts when combat starts", W.FightCount() == 0 and g.DufforthTweaksHelperDB.warrior.fights is not None)
g.NOW = 2001.5
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 78)
W.CombatLog("SWING_DAMAGE", "Creature-1", "Kobold", HOSTILE, "Player-1", "Duff", 0x511, 12)
W.CombatLog("SWING_DAMAGE", "Creature-2", "Kobold Miner", HOSTILE, "Player-1", "Duff", 0x511, 7)
W.CombatLog("SPELL_DAMAGE", "Player-1", "Duff", 0x511, "Creature-3", "Kobold Worker", HOSTILE, 30)
W.CombatLog("SWING_DAMAGE", "Creature-9", "Guard", 0x10, "Player-1", "Duff", 0x511, 5)  # friendly: not counted
check("combat log counts enemies that hit you or that you hit", W.EnemyCount() == 3)
W.LogTick(0.5)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 78)
W.ForgetDead("Creature-3")
check("a dead enemy stops counting", W.EnemyCount() == 2)
W.LogTick(0.5)
fire("UI_ERROR_MESSAGE", 51, "Not enough rage")
fire("UI_ERROR_MESSAGE", 51, "Not enough rage")
g.NOW = 2009
check("enemies older than 5 seconds drop out", W.EnemyCount() == 0)
fire("PLAYER_REGEN_ENABLED")
fights = g.DufforthTweaksHelperDB.warrior.fights
f = fights[1]
check("the fight is saved when it ends", W.FightCount() == 1 and f.seconds == 9 and f.zone == "Elwynn Forest" and f.level == 12)
check("each cast has time, rage, target health, enemies and the icon's pick",
      f.casts[1] == "1.5 Heroic Strike r40 h50 n0 p:-" and f.casts[2] == "1.5 Heroic Strike r40 h50 n3 p:Heroic Strike")
check("errors are counted", f.errors["Not enough rage"] == 2)
check("damage taken per enemy", f.hitBy["Kobold"] == 12 and f.hitBy["Kobold Miner"] == 7 and f.hitBy["Guard"] is None)
check("the most enemies at once is kept", f.mostEnemies == 3)
check("the enemy you targeted is listed with its level", f.enemies[1] == "Kobold:8")
check("the macro text is stored once and linked", g.DufforthTweaksHelperDB.warrior.macros[f.macro].startswith("/startattack"))
check("Battle Shout uptime is a percent", f.shoutUp == 0)

g.NOW = 3000
fire("PLAYER_REGEN_DISABLED"); g.NOW = 3001; fire("PLAYER_REGEN_ENABLED")
check("a second-long fight with no casts isn't saved", W.FightCount() == 1)
fire("PLAYER_REGEN_DISABLED"); fire("PLAYER_DEAD"); g.NOW = 3010; fire("PLAYER_REGEN_ENABLED")
check("dying is recorded", fights[2].result == "died" and fights[1].result == "won")
for i in range(45):
    g.NOW = 4000 + i * 20
    fire("PLAYER_REGEN_DISABLED"); g.NOW += 5; fire("PLAYER_REGEN_ENABLED")
check("only the last 40 fights are kept", W.FightCount() == W.FIGHTS_KEPT)
check("macro text isn't stored again for each fight", len(g.DufforthTweaksHelperDB.warrior.macros) == 1)
W.Options().log = False
fire("PLAYER_REGEN_DISABLED"); g.NOW += 10; fire("PLAYER_REGEN_ENABLED")
check("logging off saves nothing", W.FightCount() == W.FIGHTS_KEPT and fights[W.FIGHTS_KEPT].at == 1700000000)
W.ClearLog()
check("clear empties the log", W.FightCount() == 0)

g.INCOMBAT = False

# ---- Newer clients: C_SpellBook and C_Spell instead of the old globals ----
lua.execute("""
GetNumSpellTabs, GetSpellTabInfo, GetSpellBookItemName, IsUsableSpell, GetSpellCooldown, GetSpellInfo = nil, nil, nil, nil, nil, nil
Enum = { SpellBookSpellBank = { Player = 0 } }
C_SpellBook = {
  GetNumSpellBookSkillLines = function() return 2 end,
  GetSpellBookSkillLineInfo = function(i) if i == 1 then return { itemIndexOffset = 0, numSpellBookItems = 2 } end return { itemIndexOffset = 2, numSpellBookItems = 1 } end,
  GetSpellBookItemName = function(i) return ({ "Battle Stance", "Heroic Strike", "Rend" })[i] end,
}
C_Spell = {
  GetSpellName = function(id) return id == 78 and "Heroic Strike" or nil end,
  IsSpellUsable = function(n) return n == "Heroic Strike" end,
  GetSpellCooldown = function() return { startTime = 0, duration = 0 } end,
}
""")
known = W.KnownSpells()
check("newer clients: spellbook read through C_SpellBook", known["Heroic Strike"] and known["Rend"] and known["Battle Stance"])
check("newer clients: spell names through C_Spell", W.SpellName(78) == "Heroic Strike")
g.CLASS = "WARRIOR"
W.Options().log = True
check("newer clients: the macro still builds", W.SafeUpdate() is not None and "Heroic Strike" in everything())

# An event this client doesn't know must not stop the file from loading.
lua.execute("""
local real = CreateFrame
CreateFrame = function(...) local f = real(...); f.RegisterEvent = function(self, e) if e == "LEARNED_SPELL_IN_TAB" then error("unknown event") end; self.events[e] = true end; return f end
""")
lua.execute(source("Warrior.lua"))
check("an unknown event name is skipped, the rest still registers",
      any(f.events["COMBAT_LOG_EVENT_UNFILTERED"] for f in list(g.FRAMES.values())[-3:]))
check("an error while building shows on the tab", (lambda: (lua.execute("UnitClass = function() error('boom') end"), W.SafeUpdate(), "Error" in W.state.status)[2])())

# ---- Diagnostics in the saved file ----
dbg = g.DufforthTweaksHelperDB.warrior.debug
check("errors are saved for reading later", any("update: " in k for k in dbg.errors.keys()))
lua.execute("UnitClass = function() return 'Warrior', 'WARRIOR' end")
W.SafeUpdate()
check("client build and status are saved", isinstance(dbg.build, str) and isinstance(dbg.status, str))
check("the rotation spells the addon found are saved", "Heroic Strike" in dbg.rotationSpells)
check("events that couldn't be registered are listed", "LEARNED_SPELL_IN_TAB" in dbg.missingEvents)
bad = W.Guard("test", lambda: (_ for _ in ()).throw(Exception("x")))
lua.execute("BAD = function() error('kaboom') end")
W.Guard("test", g.BAD)()
check("a guarded handler records its error instead of stopping", any("test: " in k and "kaboom" in k for k in dbg.errors.keys()))
lua.execute("issecretvalue = function(v) return v == 'SECRET' end")
check("hidden combat values become nil", W.Plain("SECRET") is None and W.Plain(5) == 5)

# ---- Stance rotations, Victory Rush, Rend, Shield Block ----
lua.execute("""
C_SpellBook = nil; C_Spell = nil
GetNumSpellTabs = function() return 1 end
GetSpellTabInfo = function() return "General", nil, 0, #SPELLS end
GetSpellBookItemName = function(i) return SPELLS[i] end
UnitClass = function() return 'Warrior', 'WARRIOR' end
""")
g.CLASS = "WARRIOR"
LOW = ["Battle Stance", "Defensive Stance", "Heroic Strike", "Battle Shout", "Charge", "Rend", "Overpower",
       "Sunder Armor", "Revenge", "Shield Block", "Victory Rush", "Cleave"]
setup(LOW, [2457, 71])
g.BUFFS = lua.table_from([])
update()
g.IsEquippedItemType = lambda kind: kind == "Shields"
update()
m = macro()
check("Victory Rush is not in the macro (it would take every press while it can't be cast)", "Victory Rush" not in m)
check("Shield Block in Defensive Stance when a shield is worn", "/cast [form:2] Shield Block" in m)
check("Rend once per target in Battle and Defensive Stance", "/castsequence reset=12 Rend,nil" in m)
g.BUFFS = lua.table_from([lua.table_from(["Victorious", 1e9])])
update()
lines_vr = macro().split(chr(10))
check("after a kill: Victory Rush once, as the first global-cooldown line", "/castsequence Victory Rush,nil" in lines_vr
      and lines_vr.index("/castsequence Victory Rush,nil") < min(i for i, l in enumerate(lines_vr) if "Rend" in l or "Revenge" in l or "Sunder" in l))
check("after a kill the macro still fits", len(macro()) <= 255)
g.BUFFS = lua.table_from([lua.table_from(["Victorious", g.NOW + 3])])
update()
check("with under 6 s of the buff left it isn't added (it could run out mid-pull)", "Victory Rush" not in macro())
g.BUFFS = lua.table_from([lua.table_from(["Victorious", g.NOW + 18])])
g.TIMERS = lua.table_from([])
W.victoryTimer = None
update()
vt = [t for t in g.TIMERS.values() if abs(t[1] - 12.1) < 1e-6]
check("a timer takes Victory Rush out when 6 s are left", "Victory Rush" in macro() and len(vt) == 1)
g.NOW = g.NOW + 12.1
g.BUFFS = lua.table_from([lua.table_from(["Victorious", g.NOW + 5.9])])
vt[0][2]()
check("and it is gone after the timer", "Victory Rush" not in macro())
g.BUFFS = lua.table_from([])
g.BUFFS = lua.table_from([])
check("Rend lasts longer with level", W.RendSeconds(5) == 9 and W.RendSeconds(25) == 15 and W.RendSeconds(60) == 21)

known = lua.table_from({s: True for s in LOW})


def pick(ready, **facts):
    base = {"known": known, "stance": 1, "inCombat": True, "inGroup": False, "shield": True, "rendOnTarget": False,
            "shoutLeft": 60, "shoutInMacro": True, "victorious": False, "charge": True}
    base.update(facts)
    return W.NextSpell(lua.table_from(base), lambda name: name in ready)


everything = set(LOW)
check("the icon prompts Victory Rush on its own key when the game allows it",
      W.OwnKeyPrompt(lua.table_from({"known": known, "stance": 2}), lambda n: n == "Victory Rush") == "Victory Rush"
      and W.OwnKeyPrompt(lua.table_from({"known": known, "stance": 2}), lambda n: False) is None)
check("Battle Stance: Rend first on a new target, then Overpower", pick({"Overpower", "Rend", "Heroic Strike"}) == "Rend"
      and pick({"Overpower", "Rend", "Heroic Strike"}, rendOnTarget=True) == "Overpower")
check("Battle Stance: Rend when the target doesn't have it", pick({"Rend", "Heroic Strike"}) == "Rend")
check("Battle Stance: Heroic Strike once Rend is on", pick({"Rend", "Heroic Strike"}, rendOnTarget=True) == "Heroic Strike")
check("Defensive Stance: Shield Block when ready, Revenge before Sunder", pick({"Revenge", "Shield Block", "Sunder Armor"}, stance=2, rendOnTarget=True) == "Shield Block"
      and pick({"Revenge", "Sunder Armor"}, stance=2, rendOnTarget=True) == "Revenge")
check("Defensive Stance: Shield Block when Revenge isn't up and Rend is on", pick({"Shield Block", "Sunder Armor"}, stance=2, rendOnTarget=True) == "Shield Block")
check("Defensive Stance without a shield: no Shield Block", pick({"Shield Block", "Rend", "Sunder Armor"}, stance=2, shield=False) == "Rend")
check("Defensive Stance: Sunder before Heroic Strike", pick({"Sunder Armor", "Heroic Strike"}, stance=2, rendOnTarget=True) == "Sunder Armor")
check("Defensive Stance: Sunder when nothing else is ready", pick({"Sunder Armor"}, stance=2, rendOnTarget=True) == "Sunder Armor")
check("Battle Stance never picks Defensive spells", pick({"Revenge", "Shield Block", "Sunder Armor", "Heroic Strike"}) == "Heroic Strike")

# The next spell is drawn on the action button holding the macro.
lua.execute("""
GetActionInfo = function(slot) if slot == 5 then return "macro", 1 end end
ActionButton5 = CreateFrame("Button", "ActionButton5"); ActionButton5.action = 5
ActionButton6 = CreateFrame("Button", "ActionButton6"); ActionButton6.action = 6
""")
W.RefreshButtons()
ov = [(b, o) for b, o in W.overlays.items()]
check("the button holding the macro gets an overlay", len(ov) == 1 and ov[0][0].name == "ActionButton5" and ov[0][1].active)

# ---- Charge in other stances (talents) ----
setup(LOW, [2457, 71])
g.FORM = 2  # Defensive Stance
lua.execute("IsUsableSpell = function(n) return n == 'Charge' end")
update()
check("Charge is written for every stance (the game rejects it where your talents don't allow it)", "/cast [nocombat] Charge" in macro())
check("it's remembered per character", g.DufforthTweaksHelperDB.warrior.chargeStances[g.DufforthTweaksHelper.CharacterKey()][2] is True)
g.FORM = 1
update()
check("still there back in Battle Stance", "/cast [nocombat] Charge" in macro())
check("the icon shows Charge in Defensive Stance out of combat",
      W.NextSpell(lua.table_from({"known": known, "stance": 2, "inCombat": False, "chargeStances": lua.table_from({2: True}),
                                   "charge": True, "shield": True}), lambda n: n == "Charge") == "Charge")
lua.execute("IsUsableSpell = function(n) return false end")
g.FORM = 2
update()
check("without the talent, the same line (rejected harmlessly in Defensive Stance)", "/cast [nocombat] Charge" in macro())
setup(LOW + ["Warbringer"], [2457, 71])
update()
check("Warbringer: Charge in every stance and in combat", "/cast [form:1/2] Charge" in macro())
g.FORM = 1

# ---- Hidden buffs in combat: values read before the fight are used ----
g.INCOMBAT = False
g.BUFFS = lua.table_from([lua.table_from(["Battle Shout", g.NOW + 100])])
check("out of combat the buff is read", abs(W.BuffLeft("Battle Shout") - 100) < 1e-6)
g.INCOMBAT = True
lua.execute("UnitBuff = function() error('Auras cannot be accessed when secret') end")
g.NOW = g.NOW + 30
check("in combat no aura call is made; the time left counts down", abs(W.BuffLeft("Battle Shout") - 70) < 1e-6)
lua.execute("UnitGUID = function(u) return u == 'player' and 'Player-1' or 'Creature-77' end")
W.LogCast("Rend")
check("Rend on the target is remembered from your own cast", W.TargetHasMyDebuff("Rend") is True)
g.NOW = g.NOW + 30
check("and forgotten when it has worn off", W.TargetHasMyDebuff("Rend") is False)
g.INCOMBAT = False

# ---- Shield Bash / Pummel prompt when the target casts ----
lua.execute("UnitCastingInfo = function(u) return CASTING end; UnitChannelInfo = function() return nil end; UnitCanAttack = function() return true end")
g.CASTING = None
check("no cast, no interrupt prompt", W.TargetCasting() is False)
g.CASTING = "Lightning Bolt"
check("a cast is seen", W.TargetCasting() is True)
lua.execute("issecretvalue = function(v) return v == 'SECRET' end")
g.CASTING = "SECRET"
check("a hidden cast still counts as a cast", W.TargetCasting() is True)
kn = lua.table_from({"Shield Bash": True, "Pummel": True})
f = lambda **kw: lua.table_from(dict({"known": kn, "casting": True, "stance": 2, "shield": True}, **kw))
check("Defensive Stance with a shield: Shield Bash", W.Interrupt(f(), lambda n: True) == "Shield Bash")
check("Berserker Stance: Pummel", W.Interrupt(f(stance=3), lambda n: True) == "Pummel")
check("no shield: no Shield Bash", W.Interrupt(f(shield=False), lambda n: True) is None)
check("on cooldown: no prompt", W.Interrupt(f(), lambda n: False) is None)
check("not casting: no prompt", W.Interrupt(f(casting=False), lambda n: True) is None)
check("Shield Bash is never in the macro (its cooldown would stop every press)", "Shield Bash" not in macro() and "Pummel" not in macro())

# ---- Shield found from the off-hand item ----
lua.execute("IsEquippedItemType = function() return false end; GetInventoryItemID = function(u, slot) return slot == 17 and 2129 or nil end")
lua.execute("C_Item = { GetItemInfoInstant = function(id) return 'Large Round Shield', nil, nil, 'INVTYPE_SHIELD', nil, 4, 6 end }")
check("a shield in the off hand is found even when IsEquippedItemType says no", W.HasShield() is True)
lua.execute("C_Item = { GetItemInfoInstant = function(id) return 'Dagger', nil, nil, 'INVTYPE_WEAPON', nil, 2, 15 end }")
check("a weapon in the off hand is not a shield", W.HasShield() is False)
lua.execute("GetInventoryItemID = function() return nil end")
check("nothing in the off hand: no shield", W.HasShield() is False)

# ---- Tracking every try, for the next log ----
lua.execute("GetSpellInfo = function(id) return ({ [772] = 'Rend' })[id] end")
g.INCOMBAT = False
W.Options().log = True
W.preTries = lua.table_from([])
g.NOW = 9000
W.LogTry("S", "Charge")
W.LogTry("E", "Out of range.")
g.NOW = 9002
log_frame2 = [f for f in g.FRAMES.values() if f.events["UNIT_SPELLCAST_FAILED"]][-1]
log_frame2.scripts["OnEvent"](log_frame2, "PLAYER_REGEN_DISABLED")
g.NOW = 9003
log_frame2.scripts["OnEvent"](log_frame2, "UNIT_SPELLCAST_SENT", "player", "target", "Cast-9", 772)
log_frame2.scripts["OnEvent"](log_frame2, "UNIT_SPELLCAST_FAILED", "player", "Cast-9", 772)
log_frame2.scripts["OnEvent"](log_frame2, "UI_ERROR_MESSAGE", 51, "Not enough rage")
g.NOW = 9010
log_frame2.scripts["OnEvent"](log_frame2, "PLAYER_REGEN_ENABLED")
fl = g.DufforthTweaksHelperDB.warrior.fights
last = fl[len(fl)]
tries = list(last.tries.values())
check("the pull is kept (Charge tried 2 s before combat)", "-2.0 S Charge" in tries and "-2.0 E Out of range." in tries)
check("each try in the fight: sent, failed, error", "1.0 S Rend" in tries and "1.0 F Rend" in tries and "1.0 E Not enough rage" in tries)
check("tries are counted per spell", last.tried["Rend"]["S"] == 1 and last.tried["Rend"]["F"] == 1)
lua.execute("GetActionInfo = function(slot) if slot == 5 then return 'macro', 1, nil end end; GetActionText = function(slot) return slot == 5 and 'DTH Warrior' or nil end")
W.RefreshButtons()
check("the action bar facts are saved for the log", "5=1" in g.DufforthTweaksHelperDB.warrior.debug.buttons)

if fails:
    sys.exit(f"{len(fails)} failed")
print("all passed")
