"""Grind tab outside the game: kill experience (Classic + Forever's lower-level rule), kills per
hour, time to level, class and spec rules (casters, packs, elites), Best tags, and the real
GrindData.lua for a few characters."""
import sys
from pathlib import Path

import lupa.lua51 as L

ADDON = Path(__file__).resolve().parents[2] / "addon" / "DufforthTweaksHelper"
lua = L.LuaRuntime(unpack_returned_tuples=True)
for _loc in ("Locale.lua", "LocaleES.lua"):
    lua.execute((ADDON / _loc).read_text(encoding="utf-8"))
lua.execute("CreateFrame = function() return setmetatable({}, { __index = function() return function() end end }) end")
# The game's string.format errors on %d with a fraction; plain Lua truncates. Be strict like the game.
lua.execute("""
local real = string.format
string.format = function(fmt, ...)
  local args = {...}
  local i = 0
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
""")
for name in ("GrindData.lua", "Grind.lua"):
    lua.execute((ADDON / name).read_text(encoding="utf-8"))
failed = False


def check(label, cond, detail=""):
    global failed
    print(("PASS " if cond else "FAIL ") + label + (f"   [{detail}]" if detail != "" else ""))
    if not cond:
        failed = True


G = lua.eval("DufforthTweaksHelperGrind")
xp = lua.eval("DufforthTweaksHelperGrind.KillXP")

# ---- Experience ----
check("xp: even level is level x 5 + 45", xp(20, 20, False) == 145)
check("xp: +5% a level above, capped at 4 levels", abs(xp(20, 22, False) - 145 * 1.10) < 1e-9 and xp(20, 30, False) == xp(20, 24, False))
check("xp: elites give double", xp(20, 20, True) == 290)
below = 145 * (1 - 2 / 11) * (1 - 0.08)
check("xp: below your level Classic falloff, then Forever's 4% a level less", abs(xp(20, 18, False) - below) < 1e-9, xp(20, 18, False))
check("xp: Forever's cut stops at 20%", abs(xp(40, 33, False) - (245 * (1 - 7 / 13) * 0.8)) < 1e-9, xp(40, 33, False))
check("xp: gray monsters give nothing", xp(20, 13, False) == 0 and lua.eval("DufforthTweaksHelperGrind.GrayLevel(20)") == 13)
check("rested: double until the pool runs out", lua.eval("DufforthTweaksHelperGrind.XPToGo(1000, 300)") == 700
      and lua.eval("DufforthTweaksHelperGrind.XPToGo(1000, 5000)") == 500)

# ---- Specs ----
spec = lua.eval("DufforthTweaksHelperGrind.SpecFromTalents")
tbl = lua.eval("function(a,b,c) return {a,b,c} end")
check("talents: the tree with most points", spec("WARRIOR", tbl(0, 3, 11)) == "protection" and spec("MAGE", tbl(20, 0, 1)) == "arcane")
check("talents: druid Feral needs your answer (cat or bear)", spec("DRUID", tbl(0, 20, 0)) is None)
check("talents: too few points or a tie asks you", spec("ROGUE", tbl(1, 2, 0)) is None and spec("ROGUE", tbl(8, 8, 0)) is None)
check("specs: every class has its specs, druid has four", all(lua.eval(f"#DufforthTweaksHelperGrind.SPECS.{c}") >= 3 for c in
      ("WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID")) and lua.eval("#DufforthTweaksHelperGrind.SPECS.DRUID") == 4)

# ---- Rates and rules with made-up spots ----
lua.execute("""
G = DufforthTweaksHelperGrind
ITEMS = { [100] = {"Fur", 1, 10}, [200] = {"Green Sword", 2, 500} }
PRICES = { [100] = 1000 }
function SPOT(min, max, flags, gap, spawns, respawn, vendor, mobs, drops)
  return { 1, 50, 50, min, max, spawns or 20, gap or 20, respawn or 300, flags or 0, vendor or 20, mobs or {"Wolf"}, drops or {} }
end
function P(class, key, level) return { level = level or 20, xp = 0, xpMax = 23200, rested = 0, spec = G.SpecInfo(class, key) } end
""")
r = lua.eval("G.Rate(SPOT(20, 20), P('WARRIOR', 'arms'), ITEMS, PRICES)")
check("rate: kills an hour from fight, rest and walking", abs(r.kph - 3600 / r.perKill) < 1e-6 and r.kph > 60 and r.kph < 200, r.kph)
check("rate: experience an hour = kills x xp", abs(r.xph - r.kph * 145) < 1e-6)
check("rate: time to level from your experience to go", abs(r.toLevel - 23200 / r.xph * 3600) < 1e-6)
few = lua.eval("G.Rate(SPOT(20, 20, 0, 20, 4, 600), P('WARRIOR', 'arms'), ITEMS, PRICES)")
check("rate: a small spot is limited by the respawn", few.limited is True and abs(few.kph - 4 * 3600 / 600) < 1e-9, few.kph)
gold = lua.eval("G.Rate(SPOT(20, 20, 0, 20, 20, 300, 20, nil, {{100, 0.5}, {200, 0.01}}), P('WARRIOR', 'arms'), ITEMS, PRICES)")
check("gold: vendor + AH after the cut (or vendor when better)", abs(gold.copper - (20 + 0.5 * 950 + 0.01 * 500)) < 1e-9, gold.copper)
hunter = lua.eval("G.Rate(SPOT(20, 20), P('HUNTER', 'beast'), ITEMS, PRICES)")
priest = lua.eval("G.Rate(SPOT(20, 20), P('PRIEST', 'holy'), ITEMS, PRICES)")
check("class: a hunter kills faster than a holy priest", hunter.xph > priest.xph)


def warn_keys(r):
    return sorted(w["key"] for w in r.warnings.values())


caster = 1
war = lua.eval(f"G.Rate(SPOT(20, 21, {caster}), P('WARRIOR', 'arms'), ITEMS, PRICES)")
rogue = lua.eval(f"G.Rate(SPOT(20, 21, {caster}), P('ROGUE', 'combat'), ITEMS, PRICES)")
mage = lua.eval(f"G.Rate(SPOT(20, 21, {caster}), P('MAGE', 'frost'), ITEMS, PRICES)")
check("casters: not recommended for an arms warrior", war.bad is True and "caster" in warn_keys(war), warn_keys(war))
check("casters: fine for a rogue (Kick)", rogue.bad is False and "caster" not in warn_keys(rogue))
check("casters: not recommended for a mage (kiting doesn't work)", mage.bad is True)
prot = lua.eval(f"G.Rate(SPOT(20, 21, {caster}), P('WARRIOR', 'protection'), ITEMS, PRICES)")
check("casters: ok for a protection warrior (Shield Bash)", prot.bad is False)
pack = 16
bear = lua.eval(f"G.Rate(SPOT(20, 21, {pack}), P('DRUID', 'tank'), ITEMS, PRICES)")
cat = lua.eval(f"G.Rate(SPOT(20, 21, {pack}), P('DRUID', 'feral'), ITEMS, PRICES)")
check("packs: good for a bear tank, not for a cat", bear.bad is False and cat.bad is True and "pack" in warn_keys(cat))
elite = 8
e_war = lua.eval(f"G.Rate(SPOT(18, 18, {elite}), P('WARRIOR', 'arms'), ITEMS, PRICES)")
e_lock = lua.eval(f"G.Rate(SPOT(17, 18, {elite}), P('WARLOCK', 'affliction'), ITEMS, PRICES)")
check("elites: need a group for most", e_war.bad is True and "elite" in warn_keys(e_war))
check("elites: a warlock can solo ones 2+ levels below", e_lock.bad is False, warn_keys(e_lock))
heal = lua.eval("G.Rate(SPOT(20, 21, 2 + 4), P('PALADIN', 'retribution'), ITEMS, PRICES)")
check("healers and runners: a note, not a block", heal.bad is False and warn_keys(heal) == ["flees", "healer"], warn_keys(heal))

# ---- The list ----
lua.execute("""
SPOTS = {
  SPOT(20, 21, 0, 15, 30, 300, 20, {"Easy"}),
  SPOT(21, 22, 0, 40, 30, 300, 20, {"Spread out"}),
  SPOT(20, 21, 1, 15, 30, 300, 20, {"Caster camp"}),
  SPOT(30, 31, 0, 15, 30, 300, 20, {"Way up"}),
  SPOT(10, 11, 0, 15, 30, 300, 20, {"Gray"}),
  SPOT(20, 20, 0, 15, 30, 300, 900, {"Rich"}),
}
LIST = G.List(SPOTS, P('WARRIOR', 'arms'), ITEMS, PRICES, "xp")
GOLD = G.List(SPOTS, P('WARRIOR', 'arms'), ITEMS, PRICES, "gold")
function NAMES(list) local t = {} for _, r in ipairs(list) do t[#t+1] = r.spot[11][1] .. (r.best and "*" or "") .. (r.bad and "!" or "") end return table.concat(t, ",") end
""")
names = lua.eval("NAMES(LIST)").split(",")
check("list: only spots near your level", "Way up" not in " ".join(names) and "Gray" not in " ".join(names), names)
check("list: not recommended spots last, marked", names[-1] == "Caster camp!", names)
check("list: Best on the easy, close, high-experience spots", "Easy*" in names and "Spread out" in names, names)
check("list: gold mode puts the rich spot first", lua.eval("NAMES(GOLD)").split(",")[0].startswith("Rich"), lua.eval("NAMES(GOLD)"))
name, sub, right, detail = lua.eval("G.RowText(LIST[1], 'xp')")
check("row: tag, xp a kill, kills an hour, time to level, xp/h on the right", "Best" in name and "xp a kill" in sub and "kills/h" in sub
      and "level up in" in sub and "xp/h" in right, (name, sub, right))
check("row: no zone name repeated (it's in the zone header)", "The Barrens" not in sub and "Alterac" not in sub, sub)
name, sub, right, detail = lua.eval("G.RowText(LIST[#LIST], 'xp')")
check("row: a spot that doesn't suit you says why", "Casters" in sub, sub)

enemy = lua.eval("""(function()
  local z = 0
  for i, name in ipairs(DufforthTweaksHelperGrindZones) do if name == "Westfall" then z = i end end
  local s = SPOT(20, 20); s[1] = z
  local p = P('DRUID', 'feral'); p.side = "H"
  local mine = SPOT(20, 20); p2 = P('DRUID', 'feral'); p2.side = "A"
  return G.Rate(s, p, ITEMS, PRICES), G.Rate(s, p2, ITEMS, PRICES)
end)()""")
check("side: the other faction's home zone is a note and sorts after yours", enemy[0].enemy is True and enemy[0].tier == 1
      and enemy[1].enemy is False)

# ---- Balanced mode ----
lua.execute("""
MIX = {
  SPOT(20, 20, 0, 15, 30, 300, 5, {"XP only"}),
  SPOT(20, 20, 0, 15, 30, 300, 800, {"Mix"}),
  SPOT(19, 19, 0, 15, 30, 300, 900, {"Gold only"}),
  SPOT(14, 14, 0, 15, 30, 300, 9000, {"Gray-ish"}),
}
PM = P('WARRIOR', 'arms'); PM.level = 20
function FIRST(mode) local l = G.List(MIX, PM, ITEMS, PRICES, mode) return l[1].spot[11][1] end
""")
check("balance: the default mode is Balanced", lua.eval("G.DEFAULT_MODE") == "balance")
lua.execute("""
function TOP(mode, key) local best, v = nil, -1 for _, r in ipairs(G.List(MIX, PM, ITEMS, PRICES, mode)) do if r[key] > v then best, v = r, r[key] end end return best.spot[11][1] end
function SCORE_OK() local l = G.List(MIX, PM, ITEMS, PRICES, 'balance'); local tx, tg = 0, 0
  for _, r in ipairs(l) do tx = math.max(tx, r.xph); tg = math.max(tg, r.gph) end
  for _, r in ipairs(l) do if math.abs(r.score - (0.5 * r.xph / tx + 0.5 * r.gph / tg)) > 1e-9 then return false end end
  return l[1].score >= l[#l].score end
""")
check("balance: gold mode puts the most gold an hour first", lua.eval("FIRST('gold')") == lua.eval("TOP('gold', 'gph')"))
check("balance: experience mode puts the most experience an hour first", lua.eval("FIRST('xp')") == lua.eval("TOP('xp', 'xph')"))
check("balance: balanced = half experience share + half gold share, best first", lua.eval("SCORE_OK()") is True)
check("balance: no mode given means balanced", lua.eval("FIRST(nil)") == lua.eval("FIRST('balance')"))

check("levels: monsters more than 2 levels below you aren't listed, even for gold", not any(
    lua.eval("(function() for _, r in ipairs(G.List(MIX, PM, ITEMS, PRICES, 'gold')) do if r.spot[11][1] == 'Gray-ish' then return true end end return false end)()") for _ in [0]))
check("levels: the window is 2 below to 2 above, never gray", lua.eval("G.Fits(18, 18, 20)") and not lua.eval("G.Fits(17, 17, 20)")
      and lua.eval("G.Fits(22, 22, 20)") and not lua.eval("G.Fits(23, 23, 20)") and not lua.eval("G.Fits(4, 6, 10)"))

# ---- Zones, best now, monsters ----
lua.execute("""
GZ = { SPOT(20, 20, 0, 15, 30, 300, 20, {"Wolf"}), SPOT(20, 20, 0, 15, 30, 300, 20, {"Wolf"}), SPOT(20, 21, 0, 15, 30, 300, 20, {"Bear"}) }
GZ[3][1] = 2
GROUPS = G.Group(G.List(GZ, PM, ITEMS, PRICES, 'xp'))
""")
check("zones: spots grouped by zone", lua.eval("#GROUPS") == 2)
check("zones: camps of the same monster in a zone are one row", lua.eval("#GROUPS[1].rows + #GROUPS[2].rows") == 2
      and max(lua.eval("#GROUPS[1].rows[1].camps"), lua.eval("#GROUPS[2].rows[1].camps")) == 2)
lua.execute("BEST = G.BestNow(MIX, PM, ITEMS, PRICES)")
check("best now: a pick for experience, gold and balanced", lua.eval("BEST.xp ~= nil and BEST.gold ~= nil and BEST.balance ~= nil") is True)
check("levels: game difficulty colors", lua.eval("G.LevelColor(20, 25)") == "ff2020" and lua.eval("G.LevelColor(20, 20)") == "ffff00"
      and lua.eval("G.LevelColor(20, 16)") == "40c040" and lua.eval("G.LevelColor(20, 12)") == "808080")

# ---- Experience boosts ----
lua.execute("""
B_ALL = G.Boosts({ level = 20, maxLevel = 60, elixirInBags = true, food = "Roasted Boar Meat", rested = 0 })
B_ON = G.Boosts({ level = 20, maxLevel = 60, elixirActive = true, wellFed = true, rested = 5000 })
B_BUY = G.Boosts({ level = 20, maxLevel = 60, buy = {"Kaldorei Spider Kabob", 150}, rested = 0 }, function(c) return c .. "c" end)
B_MAX = G.Boosts({ level = 60, maxLevel = 60, elixirInBags = true })
function TEXTS(b) local t = {} for _, x in ipairs(b) do t[#t+1] = x.text end return table.concat(t, " | ") end
""")
check("boosts: elixir in bags and food to eat are reminders", lua.eval("G.Missing(B_ALL)") == 2 and "Use Elixir" in lua.eval("TEXTS(B_ALL)")
      and "Eat Roasted Boar Meat" in lua.eval("TEXTS(B_ALL)"), lua.eval("TEXTS(B_ALL)"))
check("boosts: active ones say they're on, nothing missing", lua.eval("G.Missing(B_ON)") == 0 and "is on" in lua.eval("TEXTS(B_ON)")
      and "Rested" in lua.eval("TEXTS(B_ON)"))
check("boosts: no food in bags suggests the best one to buy", "Buy Kaldorei Spider Kabob (150c" in lua.eval("TEXTS(B_BUY)"), lua.eval("TEXTS(B_BUY)"))
check("boosts: no rested experience says how to get it", "inn" in lua.eval("TEXTS(B_ALL)"))
check("boosts: nothing at max level", lua.eval("#B_MAX") == 0)
check("boosts: elixir +200% and Well Fed +5% add up", abs(lua.eval("G.XPBonus({ elixirActive = true, wellFed = true })") - 3.05) < 1e-9
      and lua.eval("G.XPBonus(nil)") == 1)
lua.execute("PB = P('WARRIOR', 'arms'); PB.bonus = 3")
plain, boosted = lua.eval("G.Rate(SPOT(20, 20), P('WARRIOR', 'arms'), ITEMS, PRICES)"), lua.eval("G.Rate(SPOT(20, 20), PB, ITEMS, PRICES)")
check("boosts: rates and time to level count active boosts", abs(boosted.xph - 3 * plain.xph) < 1e-6 and boosted.toLevel < plain.toLevel)

# ---- Kill log ----
parse = lua.eval("DufforthTweaksHelperGrind.ParseXP")
n, x, b = parse("Mottled Boar dies, you gain 52 experience. (+26 exp Rested bonus)", "%s dies, you gain %d experience.")
check("log: reads the kill line with a rested bonus", (n, x, b) == ("Mottled Boar", 52, 26), (n, x, b))
n, x, b = parse("Kolkar Drudge dies, you gain 47 experience.", None)
check("log: plain kill line (English default format)", (n, x, b) == ("Kolkar Drudge", 47, 0), (n, x, b))
n, x, b = parse("Jabalí moteado muere, ganas 52 puntos de experiencia. (+26 exp. bonificación Descansado)", "%s muere, ganas %d puntos de experiencia.")
check("log: a Spanish client's own format works too", (n, x, b) == ("Jabalí moteado", 52, 26), (n, x, b))
check("log: other chat lines are ignored", parse("You gain 120 experience.", "%s dies, you gain %d experience.") is None)
lua.execute("""
NOW, TARGET, CASTING = 100, nil, false
GAME = { now = function() return NOW end, time = function() return 1700000000 + NOW end, format = "%s dies, you gain %d experience.",
  target = function() return TARGET and { guid = TARGET.guid, name = TARGET.name, level = TARGET.level, rank = "normal", kind = "Humanoid" } end,
  casting = function() return CASTING end,
  player = function() return { level = 14, zone = "The Barrens", x = 50, y = 50, class = "DRUID", spec = "feral" } end }
LOG = {}
T = G.NewTracker(GAME, LOG)
TARGET = { guid = "c1", name = "Kolkar Stormer", level = 15 }
T:OnTarget()
NOW = 103; T:OnCombat(true)
NOW = 106; CASTING = true; T:OnTick(); CASTING = false
NOW = 121; E1 = T:OnXP("Kolkar Stormer dies, you gain 150 experience. (+75 exp Rested bonus)")
T:OnCombat(false)
TARGET = { guid = "c2", name = "Zhevra Runner", level = 14 }
NOW = 140; T:OnTarget(); NOW = 141; T:OnCombat(true)
NOW = 155; E2 = T:OnXP("Zhevra Runner dies, you gain 115 experience.")
""")
e1, e2 = lua.eval("E1"), lua.eval("E2")
check("log: kill time from the pull, monster level, type, rank", e1.fight == 18 and e1.ml == 15 and e1.kind == "Humanoid" and e1.rank == "normal",
      (e1.fight, e1.ml))
check("log: a monster seen casting is marked", e1.cast is True and e2.cast is False)
check("log: experience and rested bonus kept apart", e1.xp == 150 and e1.rested == 75 and e2.rested == 0)
check("log: time since the last kill (fight + rest + walk)", e1.cycle is None and e2.cycle == 34, e2.cycle)
check("log: who killed it (class, spec, level, place)", e2["class"] == "DRUID" and e2.spec == "feral" and e2.pl == 14 and e2.zone == "The Barrens")
check("log: saved in order", lua.eval("#LOG") == 2 and lua.eval("LOG[2].mob") == "Zhevra Runner")
lua.execute("""
-- The kill line after the fight ended still finds the monster.
DBG = {}
T2 = G.NewTracker(GAME, {}, DBG)
TARGET = { guid = "c3", name = "Savannah Prowler", level = 15 }
NOW = 200; T2:OnTarget(); T2:OnCombat(true)
NOW = 214; T2:OnCombat(false)
E3 = T2:OnXP("Savannah Prowler dies, you gain 140 experience.")
-- No kill line at all: the experience bar gives the kill.
T2.lastXP = { 1000, 23200, 23 }
TARGET = { guid = "c4", name = "Kolkar Wrangler", level = 16 }
NOW = 230; T2:OnTarget(); T2:OnCombat(true)
NOW = 245; T2:OnXPUpdate(1150, 23200, 23); EARLY = T2:Flush()
NOW = 246; E4 = T2:Flush(); T2:OnCombat(false)
-- The bar and the kill line both come: one kill, not two.
TARGET = { guid = "c5", name = "Kolkar Wrangler", level = 16 }
NOW = 260; T2:OnTarget(); T2:OnCombat(true)
NOW = 270; T2:OnXPUpdate(1300, 23200, 23); T2:OnXP("Kolkar Wrangler dies, you gain 150 experience.")
NOW = 272; E5 = T2:Flush()
-- Quest experience out of a fight isn't a kill.
NOW = 400; T2:OnCombat(false); NOW = 420; T2:OnXPUpdate(2300, 23200, 23); NOW = 421; E6 = T2:Flush()
""")
e3, e4 = lua.eval("E3"), lua.eval("E4")
check("log: a kill line after the fight ended keeps the fight time and level", e3.fight == 14 and e3.ml == 15, (e3.fight, e3.ml))
check("log: no kill line -> the experience bar logs the kill", lua.eval("EARLY") is None and e4 is not None and e4.xp == 150
      and e4.mob == "Kolkar Wrangler" and e4.source == "bar" and e4.fight == 16, e4 and (e4.xp, e4.mob, e4.fight))
check("log: bar and kill line together give one kill", lua.eval("E5") is None and lua.eval("#T2.log") == 3, lua.eval("#T2.log"))
check("log: experience from a quest out of combat isn't a kill", lua.eval("E6") is None)
check("log: counters saved to explain an empty log", lua.eval("DBG.chat") == 2 and lua.eval("DBG.parsed") == 2
      and lua.eval("DBG.fallback") == 1 and lua.eval("DBG.combats") == 3 and "Kolkar" in lua.eval("DBG.lastChat"))
lua.execute("G.KILL_MAX = 3; for i = 1, 5 do T:OnXP('Zhevra Runner dies, you gain 1 experience.') end")
check("log: keeps only the newest KILL_MAX kills", lua.eval("#LOG") == 3)

# ---- Tune ----
lua.execute("""
OLD_STEP, OLD_SPEED = G.BELOW_STEP, G.SpecInfo("DRUID", "feral").speed
G.ApplyTune({ below = {0.05, 0.25}, specs = { ["DRUID:feral"] = {1.3, 0.1} }, casters = { ["Wolf"] = true }, noCast = { ["Quiet Mage"] = true } })
TUNED = { xp = G.KillXP(20, 18, false), speed = G.SpecInfo("DRUID", "feral").speed,
  wolf = G.SpotFlags(SPOT(20, 20, 0, 20, 20, 300, 0, {"Wolf"})), quiet = G.SpotFlags(SPOT(20, 20, 1, 20, 20, 300, 0, {"Quiet Mage"})) }
G.ApplyTune({ below = {OLD_STEP, 0.20}, specs = { ["DRUID:feral"] = {OLD_SPEED, 0.25} } })
G.tune = nil
""")
tuned = lua.eval("TUNED")
check("tune: the fitted lower-level cut is used", abs(tuned.xp - 145 * (1 - 2 / 11) * 0.90) < 1e-9, tuned.xp)
check("tune: a spec's fitted kill speed is used", tuned.speed == 1.3)
check("tune: a monster seen casting makes its spot a caster spot", tuned.wolf == 1)
check("tune: monsters never seen casting clear the caster flag", tuned.quiet == 0)

# ---- Real data ----
check("data: many spots and items", lua.eval("#DufforthTweaksHelperGrindSpots") > 500 and lua.eval("#DufforthTweaksHelperGrindZones") > 30)
lua.execute("""
PH = P('DRUID', 'feral', 14); PH.side = "H"
REAL = G.List(DufforthTweaksHelperGrindSpots, PH, DufforthTweaksHelperGrindItems, {}, "xp")
function ZONES(list, n) local t = {} for i = 1, math.min(n, #list) do t[#t+1] = G.ZoneOf(list[i].spot) end return table.concat(t, ",") end
function ALLOK(list) for _, r in ipairs(list) do if r.xph ~= r.xph or r.kph <= 0 then return false end end return true end
""")
check("real: a level 14 feral druid gets spots, sane numbers", lua.eval("#REAL") > 10 and lua.eval("ALLOK(REAL)"), lua.eval("#REAL"))
top = lua.eval("ZONES(REAL, 5)")
check("real: a level 14 Horde druid's top spots aren't in Alliance home zones", not any(z in top for z in
      ("Westfall", "Loch Modan", "Darkshore", "Redridge Mountains", "Elwynn Forest")), top)
for level in (5, 30, 45, 58):
    n = lua.eval(f"#G.List(DufforthTweaksHelperGrindSpots, P('MAGE', 'frost', {level}), DufforthTweaksHelperGrindItems, {{}}, 'xp')")
    check(f"real: spots for a level {level} mage", n > 5, n)
lua.execute("""
PP = P('PALADIN', 'retribution', 10); PP.side = "H"
DufforthTweaksHelperDB = {}
SPOTROWS = G.BuildRows("spots", PP, DufforthTweaksHelperGrindSpots, DufforthTweaksHelperGrindItems, {}, "balance")
MOBROWS = G.BuildRows("monsters", PP, DufforthTweaksHelperGrindSpots, DufforthTweaksHelperGrindItems, {}, "balance")
function KINDS(rows) local c = {} for _, r in ipairs(rows) do local k = r.header and "header" or r.kind; c[k] = (c[k] or 0) + 1 end return c end
function LEVELS_OK(rows) for _, r in ipairs(rows) do local x = r.r or (r.e and { spot = { 0, 0, 0, r.e.mob[2], r.e.mob[3] } })
  if x and not G.Fits(x.spot[4], x.spot[5], 10) then return false end end return true end
""")
k = lua.eval("KINDS(SPOTROWS)")
check("real view: Best right now first, then zone headers with spot rows", lua.eval("SPOTROWS[1].header and SPOTROWS[1].key == 'grind:best'")
      and (k["best"] or 0) >= 1 and (k["header"] or 0) >= 3 and (k["spot"] or 0) >= 5, dict(k))
check("real view: every row fits a level 10 (no gray, at most 2 below or above)", lua.eval("LEVELS_OK(SPOTROWS)") and lua.eval("LEVELS_OK(MOBROWS)"))
km = lua.eval("KINDS(MOBROWS)")
check("real monsters view: zones with monsters (drops folded)", (km["mob"] or 0) >= 5 and not km["drop"], dict(km))
lua.execute("""DufforthTweaksHelperDB.grind = { openMobs = { [MOBROWS[#MOBROWS].key] = true } }
MOBROWS2 = G.BuildRows("monsters", PP, DufforthTweaksHelperGrindSpots, DufforthTweaksHelperGrindItems, {}, "balance")""")
check("real monsters view: an opened monster lists its drops under it", (lua.eval("KINDS(MOBROWS2)")["drop"] or 0) >= 1)
check("real data: monsters have model ids and names", lua.eval("#DufforthTweaksHelperGrindMobs") > 500
      and lua.eval("(function() local n = 0 for _, m in ipairs(DufforthTweaksHelperGrindMobs) do if m[4] > 0 then n = n + 1 end end return n end)()") > 500)
check("real data: no town guards", lua.eval("(function() for _, m in ipairs(DufforthTweaksHelperGrindMobs) do if m[1] == 'Booty Bay Bruiser' then return false end end return true end)()") is True)
ok = lua.eval("""(function() for _, r in ipairs(REAL) do G.RowText(r, 'xp'); G.RowText(r, 'gold') end return true end)()""")
check("real: every row's text builds (strict %d)", ok is True)

print("FAILED" if failed else "ALL PASS")
sys.exit(1 if failed else 0)
