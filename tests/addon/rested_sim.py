"""Runs Rested.lua outside the game: how far your rested XP reaches past the current level, the kills it covers,
the time until it is full (this character and your alts) and the progress bar text.

    python tests/addon/rested_sim.py
"""
import os
import sys

import lupa.lua51 as L

HERE = os.path.dirname(os.path.abspath(__file__))
_src = open(os.path.join(HERE, "warrior_sim.py"), encoding="utf-8").read().split("lua = L.LuaRuntime")[0]
_env = {"__file__": os.path.join(HERE, "warrior_sim.py")}
exec(_src, _env)
MOCK, source = _env["MOCK"], _env["source"]

lua = L.LuaRuntime(unpack_returned_tuples=True)
for name in ("Locale.lua", "LocaleES.lua"):
    lua.execute(source(name))
lua.execute(MOCK)
# The game's string.format errors on %d with a fraction; plain Lua 5.1 truncates. Be as strict as the game.
lua.execute("""
local real = string.format
string.format = function(fmt, ...)
  local args, i = {...}, 0
  for spec in string.gmatch(fmt, "%%[%-%d%.]*([%a%%])") do
    if spec ~= "%" then
      i = i + 1
      if spec == "d" and type(args[i]) == "number" and args[i] ~= math.floor(args[i]) then
        error("bad argument #" .. i .. " to 'format' (number has no integer representation)")
      end
    end
  end
  return real(fmt, ...)
end
LEVEL, XP, XPMAX, RESTED, RESTING, NOW = 22, 24570, 27300, 27300, true, 1000000
UnitLevel = function() return LEVEL end
UnitXP = function() return XP end
UnitXPMax = function() return XPMAX end
GetXPExhaustion = function() return RESTED end
IsResting = function() return RESTING end
UnitName = function() return "Testchar", "Lastname" end -- Forever: first and last name
UnitGUID = function() return "Player-1-0001" end
GetRealmName = function() return "Realm" end
UnitClass = function() return "Warrior", "WARRIOR" end
time = function() return NOW end
""")
lua.execute(source("Rested.lua"))
g = lua.globals()
R = g.DufforthTweaksHelperRested
fails = []


def check(name, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + name + (("  [" + str(detail) + "]") if detail and not ok else ""))
    if not ok:
        fails.append(name)


T = R.XP_TABLE
check("XP table: level 1 needs 400, level 22 needs 27300, 59 levels", T[1] == 400 and T[22] == 27300 and len(T) == 59)

r = R.Reach(22, 24570, 27300, 27300)
check("90% into 22 with a full level of rested: runs past the level to 23 + 83%",
      r.level == 23 and int(r.pct * 100) == 83 and not r.capped, (r.level, r.pct))
check("rested share of the current level: 100%", int(r.share * 100 + 0.5) == 100, r.share)
r = R.Reach(10, 0, 7600, 11400)
check("1.5 levels of rested from 0: level 11 + 43%", r.level == 11 and int(r.pct * 100) == 43, (r.level, r.pct))
r = R.Reach(10, 0, 7600, 1000)
check("rested inside the level: stays at 10 + 13%", r.level == 10 and int(r.pct * 100) == 13, (r.level, r.pct))
r = R.Reach(10, 7600 - 400, 7600, 400 + 8800)
check("exactly to the next level's end: level 12 + 0%", r.level == 12 and r.pct == 0, (r.level, r.pct))
r = R.Reach(59, 160000, 165200, 50000)
check("near 60: stops at level 60", r.level == 60 and r.capped, (r.level, r.capped))

check("kill XP of your level (Classic): level 22 = 155", R.KillXP(22) == 155)
check("rested doubles kill XP: 27300 rested at 22 covers 177 kills", R.Kills(27300, 155) == 177, R.Kills(27300, 155))
check("no rested: 0 kills", R.Kills(0, 155) == 0)

check("cap = 1.5 levels of the current level", R.Cap(7600) == 11400)
s = R.SecondsToCap(0, 7600, True)
check("from empty, resting: 10 days to full", s == 10 * 86400, s)
s = R.SecondsToCap(0, 7600, False)
check("not resting: 4 times slower (40 days)", s == 40 * 86400, s)
check("already full: 0 seconds", R.SecondsToCap(11400, 7600, True) == 0)

snap = lua.table_from({"level": 10, "max": 7600, "rested": 0, "resting": True, "at": 0, "name": "Alt"})
check("an alt resting 5 days: half of the cap (5700)", int(R.Estimate(snap, 5 * 86400)) == 5700, R.Estimate(snap, 5 * 86400))
check("an alt resting 20 days: capped at 11400", R.Estimate(snap, 20 * 86400) == 11400)

check("duration text: days and hours", R.Duration(3 * 86400 + 4 * 3600 + 59) == "3d 4h", R.Duration(3 * 86400 + 4 * 3600))
check("duration text: hours and minutes", R.Duration(5 * 3600 + 20 * 60) == "5h 20m", R.Duration(5 * 3600 + 20 * 60))

check("short bar text: 'Rested to 23 + 83%'", R.ShortText() == "Rested to 23 + 83%", R.ShortText())
lua.execute("RESTED = 0")
check("no rested XP: no bar text", R.ShortText() == "")
lua.execute("RESTED = nil")
check("GetXPExhaustion gives nil: no bar text, no error", R.ShortText() == "")
lua.execute("RESTED = 27300; LEVEL = 60")
check("level 60: no bar text", R.ShortText() == "")
lua.execute("LEVEL = 22")

# Alts: each character's state is saved; others' rested is estimated from the time since.
# Old saves keyed by first name only: two characters with the same first name overwrote each other.
lua.execute('DufforthTweaksHelperDB = { rested = { chars = { ["Testchar-Realm"] = { name = "Testchar", level = 29, max = 44300 } } } }')
R.OnEvent(None, "PLAYER_LOGIN")
store = g.DufforthTweaksHelperDB.rested
R.OnEvent(None, "PLAYER_LOGIN")
me = store.chars["Player-1-0001"]
check("login saves this character by its unique id", me is not None and me.level == 22 and me.rested == 27300 and me.resting, me)
check("the saved name has the last name: 'Testchar Lastname'", me.name == "Testchar Lastname", me.name)
check("the class is saved (UnitClass's second value)", me["class"] == "WARRIOR", me["class"])
check("the old first-name entry is removed", store.chars["Testchar-Realm"] is None)
lua.execute("""
DufforthTweaksHelperDB.rested.chars["Alt-Realm"] = {name = "Alt", level = 10, max = 7600, rested = 0, resting = true, at = NOW - 5 * 86400, class = "MAGE"}
DufforthTweaksHelperDB.rested.chars["Outside-Realm"] = {name = "Outside", level = 30, max = 50800, rested = 76200, resting = false, at = NOW - 3600, class = "ROGUE"}
DufforthTweaksHelperDB.rested.chars["Max-Realm"] = {name = "Max", level = 60, max = 0, rested = 0, resting = true, at = NOW, class = "PRIEST"}
""")
alts = list(R.Alts(store, "Player-1-0001", g.NOW).values())
names = [a.name for a in alts]
check("alts: not me, not level 60, full ones first then soonest", names == ["Outside", "Alt"], names)
check("Alt resting 5 days: 75% of its level rested, full in 5 days", int(alts[1].pct * 100) == 75 and alts[1].left == 5 * 86400,
      (alts[1].pct, alts[1].left))
text = R.HoverText()
for part in ("Rested XP: 27300", "100% of this level", "Reaches level 23 + 83%", "177 kills", "Full in ", "Alts", "Outside (30): full",
             "Alt (10): 75%"):
    check("hover says " + part, part in text, text)
check("hover marks the numbers as estimates", "estimate" in text.lower(), text)
lua.execute("RESTING = false")
check("not resting: hover says it fills 4x slower", "4x slower" in R.HoverText(), R.HoverText())
lua.execute("RESTING = true; XP = 0; RESTED = 40950")
check("full rested: hover says it is full", "full: rest no longer adds" in R.HoverText(), R.HoverText())
R.OnEvent(None, "PLAYER_LOGOUT")
check("logout saves the latest numbers", store.chars["Player-1-0001"].rested == 40950)

rows = list(R.Rows(store, "Player-1-0001", g.NOW).values())
check("window rows: you first, then alts", [r.name for r in rows] == ["Testchar Lastname", "Outside", "Alt"], [r.name for r in rows])
check("window rows: your row is marked", rows[0].me is True and not rows[1].me)
check("window row text: 'Alt (10): 75% rested, full in 5d 0h'", R.RowText(rows[2]) == "Alt (10): 75% rested, full in 5d 0h", R.RowText(rows[2]))
check("window row text: full alt", R.RowText(rows[1]) == "Outside (30): 150% rested, full", R.RowText(rows[1]))
# Alts tab (user: "i want to see all my alts reste experience amount in a tab"): one row per character with
# name and level, rested XP now, the level it reaches, resting or not, and time to full.
check("save keeps the XP into the level, so an alt's reach can be worked out", store.chars["Player-1-0001"].cur == 0,
      store.chars["Player-1-0001"].cur)
lua.execute("""
DufforthTweaksHelperDB.rested.chars["Alt-Realm"].cur = 3800
""")
table = list(R.TableRows(store, "Player-1-0001", g.NOW).values())
check("alts table: you first, then the alts (no level 60)", [r.name for r in table] == ["Testchar Lastname", "Outside", "Alt"],
      [r.name for r in table])
alt = table[2]
check("alts table: rested amount estimated now (5 days in an inn = 5700)", int(alt.rested) == 5700, alt.rested)
check("alts table: reach from where the alt stood (10 + 50%, +5700 rested -> 11 + 21%)",
      alt.reach.level == 11 and int(alt.reach.pct * 100) == 21, (alt.reach.level, alt.reach.pct))
cells = R.Cells(alt)
check("cells: name and level", cells.name == "Alt" and cells.level == "10", (cells.name, cells.level))
check("cells: rested amount with its share of the level", cells.rested == "5,700 (75%)", cells.rested)
check("cells: level it reaches", cells.reach == "11 + 21%", cells.reach)
check("cells: resting in an inn or city", cells.where == "Inn or city", cells.where)
check("cells: time until full", cells.full == "5d 0h", cells.full)
out = R.Cells(table[1])
check("cells: an alt out in the world says so", out.where == "Outside", out.where)
check("cells: a full alt says Full", out.full == "Full", out.full)
lua.execute('DufforthTweaksHelperDB.rested.chars["Old-Realm"] = {name = "Old", level = 20, max = 23200, rested = 0, resting = true, at = NOW}')
old = [r for r in R.TableRows(store, "Player-1-0001", g.NOW).values() if r.name == "Old"][0]
check("cells: an alt saved before the XP was kept shows no reach guess", R.Cells(old).reach == "?" and old.cur is None,
      R.Cells(old).reach)
check("cells: no rested shows 0", R.Cells(old).rested == "0 (0%)", R.Cells(old).rested)
check("cells hover: a reach of 60 says level 60", R.Cells(lua.table_from({"name": "X", "level": 59, "rested": 1, "max": 1,
      "pct": 1, "left": 0, "resting": True, "reach": lua.table_from({"level": 60, "pct": 0, "capped": True})})).reach == "60")
check("big numbers get thousands separators", R.Thousands(1234567) == "1,234,567" and R.Thousands(999) == "999")
check("hover text for a row has every value spelled out", "Rested XP: 5,700" in R.RowTip(alt) and "Reaches level 11 + 21%" in R.RowTip(alt),
      R.RowTip(alt))

# Mark alts about to reach the cap (user: "mark the ones that are about to reach the rested limit so i can
# notice and login and consume it"): full now = rest is being wasted; full within a day = soon.
check("alert: a full alt is marked full (rest wasted)", R.Alert(0) == "full")
check("alert: full within 24 hours is marked soon", R.Alert(23 * 3600) == "soon" and R.Alert(24 * 3600) == "soon")
check("alert: more than a day away is not marked", R.Alert(24 * 3600 + 1) is None)
check("cells: the full alt carries the full mark", out.alert == "full", out.alert)
check("cells: an alt 5 days away has no mark", cells.alert is None, cells.alert)
tip = R.RowTip(table[1])
check("hover on a full alt says to log in and use it", "log in" in tip.lower(), tip)
check("count of marked alts (not you) for the tab title", R.MarkedCount(store, "Player-1-0001", g.NOW) == 1,
      R.MarkedCount(store, "Player-1-0001", g.NOW))

lua.execute("UnitGUID = nil")
key = R.Key()[0]
check("no UnitGUID: falls back to name and realm", key == "Testchar Lastname-Realm", key)

print(f"{len(fails)} failed" if fails else "all passed")
sys.exit(1 if fails else 0)
