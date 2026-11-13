"""Runs the Leveling tab's planner outside the game: skill-up chances, the cheapest recipe per
point, learning costs by faction, selling back what you make, caps and the shopping list.

    python tests/addon/leveling_sim.py
"""
import os
import re
import sys
import lupa.lua51 as L

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ADDON = os.path.join(ROOT, "addon", "DufforthTweaksHelper")


def source(name):
    return open(os.path.join(ADDON, name), encoding="utf-8").read()


MOCK = r"""
-- Like the game: %d with a number that has decimals is an error (plain Lua 5.1 just truncates).
local realFormat = string.format
string.format = function(pattern, ...)
  local args, i = { ... }, 0
  for spec in string.gmatch(pattern, "%%[-+ #0]*%d*%.?%d*([%a%%])") do
    if spec ~= "%" then
      i = i + 1
      if (spec == "d" or spec == "i") and type(args[i]) == "number" and args[i] ~= math.floor(args[i]) then
        error("bad argument #" .. (i + 1) .. " to 'format' (number has no integer representation)", 2)
      end
    end
  end
  return realFormat(pattern, ...)
end
time = function() return 1000 end
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
GetItemInfo = function() end
EVENTS = {}
function CreateFrame()
  local f = {}
  function f:RegisterEvent(e) EVENTS[e] = true end
  function f:SetScript(k, fn) self[k] = fn end
  return f
end
GetRealmName = function() return "Realm" end
UnitName = function() return "Duff" end
FACTION = "Horde"
UnitFactionGroup = function() return FACTION end
SKILLS = { { "Tailoring", false, false, 40, 0, 0, 75 } }
GetNumSkillLines = function() return #SKILLS end
GetSkillLineInfo = function(i) return unpack(SKILLS[i]) end
"""

# Tailoring (profession 2). Materials: 1 Cloth (AH 10c), 2 Thread (vendor 5c), 3 Dye (AH 100c).
#  Bolt     learn 1,  yellow 25, gray 35: 2 Cloth             -> 20c; sells 1c to a vendor
#  Shirt    learn 1,  yellow 50, gray 70: 3 Cloth + 1 Thread  -> 35c
#  Vest     learn 30, yellow 60, gray 90: 2 Cloth + 1 Thread  -> 25c, trainer: Horde 50c, Alliance 10c
#  Gloves   learn 30, yellow 60, gray 90: 1 Cloth             -> 10c, recipe item 900 (vendor 5000c, AH 3000c)
#  Robe     learn 40, yellow 70, gray 100: 4 Cloth            -> 40c, product sells 200c on the AH
#  Fancy    learn 1, yellow 10, gray 20: 1 Mystery (no price)
DATA = r"""
DufforthTweaksHelperProfessions = { "Blacksmithing", "Tailoring" }
DufforthTweaksHelperVendor = { [2] = 5 }
DufforthTweaksHelperMaterialCrafts = {}
DufforthTweaksHelperLevelRecipes = {
  { 10, 2, 1, 25, 35, 500, 1, 1, "Bolt", "s", 0, { 1, 2 } },
  { 11, 2, 1, 50, 70, 501, 1, 0, "Shirt", "s", 0, { 1, 3, 2, 1 } },
  { 12, 2, 30, 60, 90, 502, 1, 0, "Vest", "t", 0, { 1, 2, 2, 1 } },
  { 13, 2, 30, 60, 90, 503, 1, 0, "Gloves", "v", 900, { 1, 1 } },
  { 14, 2, 40, 70, 100, 504, 1, 0, "Robe", "s", 0, { 1, 4 } },
  { 15, 2, 1, 10, 20, 505, 1, 0, "Fancy", "s", 0, { 4, 1 } },
  { 16, 1, 1, 50, 90, 506, 1, 0, "Smithing", "s", 0, { 1, 1 } },
}
DufforthTweaksHelperLevelNPCs = { { "Horde Trainer", "Tailor", "H", "Orgrimmar", 63.1, 45.2 }, { "Alliance Trainer", "", "A", "Elwynn Forest", 40, 50 }, { "Goblin", "", "", "Tanaris", 50, 28 } }
DufforthTweaksHelperLevelTrainers = { [12] = { 1, 50, 30, 2, 10, 30 } }
DufforthTweaksHelperLevelVendors = { [900] = { 3, 5000, 1 } }
PRICES = { [1] = 10, [2] = 1, [504] = 200, [900] = 3000 }
"""

lua = L.LuaRuntime(unpack_returned_tuples=True)
lua.execute(MOCK)
lua.execute(DATA)
for name in ("Crafting.lua", "Leveling.lua"):
    lua.execute(source(name))
g = lua.globals()
V = g.DufforthTweaksHelperLeveling
fails = []


def check(name, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + name + (f"   [{detail}]" if detail != "" else ""))
    if not ok:
        fails.append(name)


lua.execute("function R(spell) for _, r in ipairs(DufforthTweaksHelperLevelRecipes) do if r[1] == spell then return r end end end")
lua.execute("""function PLAN(skill, target, options, known)
  known = known or { spells = {}, scanned = {} }
  local side = FACTION == "Horde" and "H" or "A"
  P = DufforthTweaksHelperLeveling.Plan(2, skill, target, known, options or { unlearned = true, resale = true }, PRICES, side)
  local out = {}
  for _, s in ipairs(P.steps) do out[#out + 1] = s.recipe[9] .. " " .. s.from .. "-" .. s.to end
  return table.concat(out, ", ")
end""")

# Chances follow the game's colors.
check("orange: always a point", lua.eval("DufforthTweaksHelperLeveling.Chance(R(11), 30)") == 1)
check("yellow/green: (gray - skill) / (gray - yellow)", abs(lua.eval("DufforthTweaksHelperLeveling.Chance(R(11), 60)") - 0.5) < 1e-9)
check("gray: no points", lua.eval("DufforthTweaksHelperLeveling.Chance(R(11), 70)") == 0)
check("not learnable yet: no points", lua.eval("DufforthTweaksHelperLeveling.Chance(R(12), 29)") == 0)
check("green starts halfway between yellow and gray", lua.eval("DufforthTweaksHelperLeveling.Green(R(11))") == 60 and lua.eval("DufforthTweaksHelperLeveling.Color(R(11), 61)") == "green")

# The plan.
plan = lua.eval("PLAN(1, 75)")
check("cheapest per point: Bolt while orange, then the cheaper recipes as they open", plan.startswith("Bolt 1-"), plan)
check("Fancy is never used: one material has no price", "Fancy" not in plan)
check("other professions' recipes are ignored", "Smithing" not in plan)
check("Robe's resale (200c on the AH) makes it pay for itself once learnable", "Robe 40-" in plan, plan)
check("plan reaches the cap", lua.eval("P.reached") == 75 and lua.eval("P.stoppedAt") is None)
check("totals add up", lua.eval("P.total") == lua.eval("P.materials - P.resale + P.learning"))
crafts = lua.eval("(function() local n = 0; for _, s in ipairs(P.steps) do n = n + s.crafts end; return n end)()")
check("crafts add up", crafts == lua.eval("P.crafts"))
lua.execute("PRICES[505] = 100000; PRICES[4] = 1")
lua.eval("PLAN(1, 15)")
check("a craft that sells for a profit doesn't win by needing more crafts per point", lua.eval("P.steps[1].chance") == 1, lua.eval("P.steps[1].recipe[9]"))
check("selling back recovers at most 80% of the materials", all(lua.eval(f"P.steps[{i}].candidate.back <= P.steps[{i}].candidate.materials * 0.8 + 1e-9") for i in range(1, int(lua.eval("#P.steps")) + 1)))
lua.execute("PRICES[505] = nil; PRICES[4] = nil")

plan_no_resale = lua.eval("PLAN(1, 75, { unlearned = true, resale = false })")
check("without selling back, Vest stays cheapest until Robe's better chance wins near the end", "Vest 30-74" in plan_no_resale, plan_no_resale)

plan_known = lua.eval("PLAN(30, 60, { unlearned = false, resale = false })")
check("only known recipes: no trainer or vendor recipes", "Vest" not in plan_known and "Gloves" not in plan_known, plan_known)
plan_learn = lua.eval("PLAN(30, 60, { unlearned = true, resale = false })")
check("unknown recipes join when cheaper overall", "Gloves" in plan_learn or "Vest" in plan_learn, plan_learn)
check("learning cost is counted once", lua.eval("P.learning") in (50, 3000), lua.eval("P.learning"))

# Learning: faction and vendor vs auction.
lua.execute('A, K, PL = DufforthTweaksHelperLeveling.Acquire(R(12), { spells = {} }, "H", PRICES)')
check("Horde pays the Horde trainer", lua.eval("A") == 50 and lua.eval("K") == "trainer" and lua.eval("PL[1].npc[1]") == "Horde Trainer")
lua.execute('A, K, PL = DufforthTweaksHelperLeveling.Acquire(R(12), { spells = {} }, "A", PRICES)')
check("Alliance pays the Alliance trainer", lua.eval("A") == 10 and lua.eval("PL[1].npc[4]") == "Elwynn Forest")
lua.execute('A, K = DufforthTweaksHelperLeveling.Acquire(R(13), { spells = {} }, "H", PRICES)')
check("a recipe cheaper on the auction house than at the vendor", lua.eval("A") == 3000 and lua.eval("K") == "auction")
lua.execute('A, K = DufforthTweaksHelperLeveling.Acquire(R(13), { spells = { [13] = true } }, "H", PRICES)')
check("a recipe you know costs nothing", lua.eval("A") == 0 and lua.eval("K") == "known")
lua.execute('PRICES[900] = nil; A, K, PL = DufforthTweaksHelperLeveling.Acquire(R(13), { spells = {} }, "A", PRICES); PRICES[900] = 3000')
check("neutral vendors serve both sides", lua.eval("A") == 5000 and lua.eval("K") == "vendor" and lua.eval("PL[1].npc[1]") == "Goblin")

# Selling back: the better of auction after the cut and vendor.
check("resale uses the auction after the 5% cut", lua.eval("DufforthTweaksHelperLeveling.Resale(R(14), PRICES)")[0] == 190)
check("resale uses the vendor when it pays more", lua.eval("DufforthTweaksHelperLeveling.Resale(R(10), PRICES)")[0] == 1)

# Stopping and shopping.
lua.execute("PRICES[1] = nil")
check("no prices: the plan stops and says where", lua.eval("PLAN(1, 75)") == "" and lua.eval("P.stoppedAt") == 1)
lua.execute("PRICES[1] = 10")
lua.eval("PLAN(1, 75)")
lua.execute("SHOP = DufforthTweaksHelperLeveling.ShoppingList(P)")
cloth = lua.eval("(function() for _, t in ipairs(SHOP) do if t.id == 1 then return t.count end end end)()")
expected = lua.eval("(function() local n = 0; for _, s in ipairs(P.steps) do for _, p in ipairs(s.candidate.parts) do if p.id == 1 then n = n + p.count * s.crafts end end end; return n end)()")
check("shopping list totals each material", cloth == expected and cloth > 0, cloth)

# Reading professions and the cap.
check("reads skill and cap", lua.eval('DufforthTweaksHelperLeveling.ReadProfessions().Tailoring.rank') == 40 and lua.eval('DufforthTweaksHelperLeveling.ReadProfessions().Tailoring.max') == 75)
check("faction side", lua.eval("DufforthTweaksHelperLeveling.Side()") == "H")
lua.execute("""GetProfessions = function() return nil, 7, nil, nil, 5, nil end
PROFS = { [7] = { "Schneiderei", nil, 87, 150, 0, 0, 197, 0 }, [5] = { "Cooking", nil, 40, 75, 0, 0, 185, 0 } }
GetProfessionInfo = function(i) return unpack(PROFS[i], 1, 8) end""")
check("reads every profession slot, even after an empty one, and matches by skill line",
      lua.eval("DufforthTweaksHelperLeveling.ReadProfessions().Tailoring.rank") == 87 and lua.eval("DufforthTweaksHelperLeveling.ReadProfessions().Tailoring.max") == 150)
lua.execute("GetProfessions = nil")
check("profession windows (and Enchanting's craft window) are watched", lua.eval('EVENTS.TRADE_SKILL_SHOW and EVENTS.CRAFT_SHOW') is True)

# Real data: the generated file loads and plans every profession without errors.
real = L.LuaRuntime(unpack_returned_tuples=True)
real.execute(MOCK)
real.execute('DufforthTweaksHelperProfessions = { "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering", "First Aid", "Leatherworking", "Mining", "Tailoring" }')
real.execute('DufforthTweaksHelperVendor = {}; DufforthTweaksHelperMaterialCrafts = {}')
real.execute(source("LevelingData.lua"))
for name in ("Crafting.lua", "Leveling.lua"):
    real.execute(source(name))
real.execute("""PR = {}
for _, r in ipairs(DufforthTweaksHelperLevelRecipes) do for i = 1, #r[12], 2 do PR[r[12][i]] = 50 end; if r[11] > 0 then PR[r[11]] = 5000 end end
OUT = {}
for p = 1, 9 do if p == 8 then OUT[p] = 0 else
  local plan = DufforthTweaksHelperLeveling.Plan(p, 1, 300, { spells = {}, scanned = {} }, { unlearned = true, resale = false }, PR, "H")
  OUT[p] = plan.reached
  STOP = STOP or {}; STOP[p] = plan.stoppedAt
end end""")
reached = [real.eval(f"OUT[{p}]") for p in range(1, 10)]
check("real data: every crafting profession plans from 1 (with stand-in prices)", all(r > 1 for i, r in enumerate(reached) if i != 7), reached)
check("Mining isn't offered in the tab: it levels by mining", 'GATHERING_NAMES = { Mining = true }' in source("Leveling.lua"))
check("real data: tailoring plans all the way to 300 with prices for everything", real.eval("OUT[9]") == 300, real.eval("OUT[9]"))


# The tab itself, with the real data and the real bundled prices: Tailoring 40/75, Horde, PvP realm.
UI = r"""
CHAT, TIP, FRAMES = {}, {}, {}
local function widget(kind)
  local w = { shown = true, scripts = {}, kind = kind }
  FRAMES[#FRAMES + 1] = w
  return setmetatable(w, { __index = function(t, k)
    if k == "SetText" then return function(self, v) self.text = v end end
    if k == "SetShown" then return function(self, v) self.shown = v end end
    if k == "Show" then return function(self) self.shown = true end end
    if k == "Hide" then return function(self) self.shown = false end end
    if k == "SetScript" or k == "HookScript" then return function(self, e, f) self.scripts[e] = f end end
    if k == "IsVisible" then return function() return true end end
    if k == "GetChecked" then return function(self) return self.checked end end
    if k == "SetChecked" then return function(self, v) self.checked = v end end
    if k == "SetEnabled" then return function(self, v) self.enabled = v end end
    if k == "SetWordWrap" then return function(self, v) self.wrap = v end end
    if k == "SetValue" then return function(self, v) self.value = v end end
    if k == "SetStatusBarColor" then return function(self, r, g, b) self.color = (g > 0.7 and "done") or (r > 0.8 and "stopped") or "crafting" end end
    if k == "SetPoint" then return function(self, a, b, c, d, e) self.point = { a, b, c, d, e } end end
    if k == "CreateFontString" then return function() return widget("font") end end
    if k == "CreateTexture" then return function() return widget("texture") end end
    if k == "row" or k == "text" or k == "point" or k == "wrap" or k == "enabled" or k == "value" or k == "color" then return nil end
    return function() end
  end })
end
CreateFrame = function() return widget("frame") end
PARENT = widget("frame")
GameTooltip = setmetatable({}, { __index = function(_, k)
  if k == "AddLine" then return function(_, t) TIP[#TIP + 1] = t end end
  if k == "AddDoubleLine" then return function(_, a, b) TIP[#TIP + 1] = a .. " | " .. b end end
  if k == "SetOwner" then return function() TIP = {} end end
  return function() end
end })
print = function(t) CHAT[#CHAT + 1] = t end
C_Timer = nil
GetRealmName = function() return "Forever PvP" end
DufforthTweaksHelperDB = {}
function TEXTS()
  local out = {}
  for _, f in ipairs(FRAMES) do local t = rawget(f, "text"); if t and rawget(f, "shown") ~= false then out[#out + 1] = t end end
  return table.concat(out, "\n")
end
function ROWS()
  local out = {}
  for _, f in ipairs(FRAMES) do if rawget(f, "row") and rawget(f, "shown") ~= false then out[#out + 1] = f end end
  return out
end
function HOVER(f) f.scripts.OnEnter(f); return table.concat(TIP, "\n") end
"""
ui_lua = L.LuaRuntime(unpack_returned_tuples=True)
ui_lua.execute(MOCK)
ui_lua.execute(UI)
for name in ("Core.lua", "Prices.lua", "Crafts.lua", "Disenchant.lua", "Crafting.lua", "LevelingData.lua", "Leveling.lua"):
    ui_lua.execute(source(name))
ui_lua.execute("DufforthTweaksHelperLeveling.BuildPanel(PARENT, 424); DufforthTweaksHelperLeveling.Refresh()")
texts = ui_lua.eval("TEXTS()")
check("UI: the tab shows the profession, skill and cap", "Tailoring  |cffffffff40 / 75|r" in texts)
check("UI: one-line summary and the total beside the view buttons", "To 75: about" in texts and "Total " in texts, texts[:300])
check("UI: asks to open the profession window once", "Open your Tailoring window once" in texts)

# Layout: every line has its own row, so nothing can overlap (the user's screenshot showed a wrapped
# summary running into the list), and single-line text never wraps.
layout = ui_lua.eval("DufforthTweaksHelperLeveling.LAYOUT")
order = [layout.title, layout.options, layout.views, layout.summary, layout.notice, layout.rows]
check("UI: header lines stack top to bottom with room for one line each", all(a - b >= 14 for a, b in zip(order, order[1:])), order)
check("UI: the rows start below the notice line", layout.rows <= layout.notice - 16)
check("UI: summary, notice and row text never wrap into the next line",
      ui_lua.eval("(function() for _, f in ipairs(FRAMES) do if rawget(f, 'kind') == 'font' and rawget(f, 'point') and rawget(f, 'wrap') == nil then local p = rawget(f, 'point'); if p[1] == 'TOPLEFT' and (p[3] == -78 or p[3] == -94) then return false end end end return true end)()") is True)
check("UI: no arrow characters in buttons, which the game's fonts can't draw", all("\u25b2" not in source(n) and "\u25bc" not in source(n) for n in ("Leveling.lua", "Crafting.lua", "AutoDisenchant.lua")))
check("UI: scroll arrows use the game's scroll textures", "UI-ScrollBar-Scroll" in source("Core.lua"))

rows = ui_lua.eval("ROWS()")
check("UI: plan rows are drawn", rows is not None and len(rows) > 0)
first = ui_lua.eval("ROWS()[1]")
name, sub, cost = first.name.text, first.sub.text, first.cost.text
check("UI: a plan row says the skill range, recipe, crafts and how to learn it", "-" in name and "crafts." in sub, f"{name} | {sub} | {cost}")
tip = ui_lua.eval("HOVER(ROWS()[1])")
check("UI: hovering a step explains colors, materials, totals and how to learn it",
      "Orange|r to" in tip and "Materials for one craft" in tip and "Total" in tip and "How to learn" in tip, tip[:200])
print("     plan row:", name, "|", sub, "|", cost)
second = ui_lua.eval("ROWS()[2]")
check("UI: each step is followed by its materials, amount for the whole step", second.row.part is not None and re.search(r"\d+x\|r", second.name.text) and "a craft" in second.sub.text,
      f"{second.name.text} | {second.sub.text} | {second.cost.text} | {second.detail.text}")
check("UI: a step's material rows add up to its materials cost",
      ui_lua.eval("(function() local r = ROWS(); local s = r[1].row.step; local sum = 0; for _, p in ipairs(s.candidate.parts) do sum = sum + p.each * p.count * s.crafts end; return math.abs(sum - s.materials) < 0.5 end)()") is True)
check("UI: material rows say have/need", re.search(r"\d+\|r/\d+|\d+/\d+", second.detail.text or "") is not None, second.detail.text)
tip = ui_lua.eval("HOVER(ROWS()[2])")
check("UI: hovering a material row says per craft, crafts and bags", "a craft x" in tip and "In your bags" in tip, tip[:160])
# Bags are shared out step by step: the same material in two steps isn't counted twice.
ui_lua.execute("""
SHARED = nil
for _, f in ipairs(ROWS()) do if f.row.part then SHARED = SHARED or f.row.part.id end end
GetItemCount = function(id) if id == SHARED then return 1000000 end return 0 end
DufforthTweaksHelperLeveling.Refresh()
""")
shared = [r.row for r in ui_lua.eval("ROWS()").values() if r.row.part and r.row.part.id == ui_lua.eval("SHARED")]
check("UI: with plenty in your bags every step shows it has enough", all(r.have == r.need for r in shared) and "|cff40c040" in ui_lua.eval("ROWS()[2]").detail.text)
ui_lua.execute("GetItemCount = function(id) if id == SHARED then return 5 end return 0 end; DufforthTweaksHelperLeveling.Refresh()")
rows_all = [r.row for r in ui_lua.eval("ROWS()").values() if r.row.part and r.row.part.id == ui_lua.eval("SHARED")]
check("UI: a few in your bags count for the first step only", rows_all[0].have == min(5, rows_all[0].need) and sum(r.have for r in rows_all) <= 5)
ui_lua.execute("GetItemCount = function() return 0 end; DufforthTweaksHelperLeveling.Refresh()")
print("     material row:", second.name.text, "|", second.sub.text, "|", second.cost.text, "|", second.detail.text)

# The shopping list is a view in the tab, not chat lines.
ui_lua.execute("PARENT.shopButton.scripts.OnClick(PARENT.shopButton)")
texts = ui_lua.eval("TEXTS()")
check("UI: Shopping list view sums what to buy", "buy" in texts and "of materials" in texts, texts[:200])
first = ui_lua.eval("ROWS()[1]")
check("UI: shopping rows show recipes to learn first, then materials with amount and price",
      ("Learn" in first.name.text) or ("x" in first.name.text and "each" in first.sub.text), f"{first.name.text} | {first.sub.text}")
buy_rows = [r for r in ui_lua.eval("ROWS()").values() if "each" in (r.sub.text or "")]
check("UI: material rows say where it's cheapest and the price each", len(buy_rows) > 0)
tip = ui_lua.eval("HOVER(ROWS()[#ROWS()])")
check("UI: hovering a material says how many and the total", "Needed for this plan" in tip and "All of them" in tip, tip[:200])
for r in list(ui_lua.eval("ROWS()").values())[:5]:
    print("     shop row:", r.name.text, "|", r.sub.text, "|", r.cost.text)
check("UI: nothing is printed to chat", int(ui_lua.eval("#CHAT")) == 0)
check("UI: the open view is remembered", ui_lua.eval("DufforthTweaksHelperDB.leveling.view") == "shopping")
check("UI: the active view's button is shown pressed", ui_lua.eval("PARENT.shopButton.enabled") is False and ui_lua.eval("PARENT.planButton.enabled") is True)

ui_lua.execute('SKILLS = {}; DufforthTweaksHelperLeveling.Refresh()')
check("UI: no crafting profession says what to do", "Learn a crafting profession" in ui_lua.eval("TEXTS()"))


# ---- Buying and crafting: the pure helpers ----
lua.execute("""
LIST = { { id = 1, count = 10, each = 10, source = "auction" }, { id = 2, count = 5, each = 5, source = "vendor" },
         { id = 3, count = 4, each = 3, source = "auction" }, { id = 4, count = 2, each = 1, source = "crafted" } }
BAGS = { [1] = 10, [3] = 1 }
HAVE = function(id) return BAGS[id] or 0 end
""")
lua.execute("B, TOTAL = DufforthTweaksHelperLeveling.VendorPlan(LIST, HAVE, { [2] = { index = 4, price = 5, bundle = 1, available = -1 }, [3] = { index = 5, price = 50, bundle = 1, available = -1 } })")
check("vendor: buys only what's missing", lua.eval("#B") == 1 and lua.eval("B[1].units") == 5 and lua.eval("TOTAL") == 25)
check("vendor: skips items it sells dearer than the list", lua.eval("B[1].id") == 2)
lua.execute("B, TOTAL = DufforthTweaksHelperLeveling.VendorPlan(LIST, HAVE, { [2] = { index = 4, price = 20, bundle = 3, available = -1 } })")
check("vendor: bundles round up to cover what's missing", lua.eval("B[1].purchases") == 2 and lua.eval("B[1].units") == 6 and lua.eval("TOTAL") == 40)
lua.execute("B, TOTAL = DufforthTweaksHelperLeveling.VendorPlan(LIST, HAVE, { [2] = { index = 4, price = 5, bundle = 1, available = 2 } })")
check("vendor: no more than it has in stock", lua.eval("B[1].purchases") == 2)
check("progress: halfway through the 2nd of 4 crafts of 3s", lua.eval("(DufforthTweaksHelperLeveling.CraftProgress({ done = 1, total = 4 }, 11.5, 10, 13))") == 1.5 / 4)
check("progress: time left counts the gap between crafts", abs(lua.eval("select(2, DufforthTweaksHelperLeveling.CraftProgress({ done = 1, total = 4 }, 11.5, 10, 13))") - 2.5 * 3.3) < 1e-9)
check("progress: measured pace wins once known", lua.eval("select(2, DufforthTweaksHelperLeveling.CraftProgress({ done = 2, total = 4, per = 4 }, 0))") == 8)
check("progress: durations read plainly", [lua.eval(f"DufforthTweaksHelperLeveling.Duration({n})") for n in (7, 75, 120, 3700)] == ["7s", "1m 15s", "2m", "1h 1m"])
check("bags: 3 free slots of stacks of 20, 5 already in a stack, 1 per craft", lua.eval("DufforthTweaksHelperLeveling.CraftsThatFit(3, 20, 5, 1)") == 75)
check("bags: items that don't stack need a slot each", lua.eval("DufforthTweaksHelperLeveling.CraftsThatFit(4, 1, 7, 1)") == 4)
check("bags: crafts that make 2 at a time", lua.eval("DufforthTweaksHelperLeveling.CraftsThatFit(3, 1, 0, 2)") == 1)
check("bags: full bags fit nothing", lua.eval("DufforthTweaksHelperLeveling.CraftsThatFit(0, 1, 0, 1)") == 0)
check("craft: what the step needs, or what materials allow", lua.eval("DufforthTweaksHelperLeveling.CraftCount({ crafts = 12 }, 5)") == 5
      and lua.eval("DufforthTweaksHelperLeveling.CraftCount({ crafts = 12 }, 40)") == 12 and lua.eval("DufforthTweaksHelperLeveling.CraftCount({ crafts = 12 }, nil)") == 0)

# ---- The button in the tab, with the real data ----
ui_lua.execute("""
T = 100; GetTime = function() return T end
MONEY = 10000000; GetMoney = function() return MONEY end
BOUGHT, SEARCHED, CRAFTED = {}, {}, {}
SKILLS = { { "Tailoring", false, false, 40, 0, 0, 75 } }
DufforthTweaksHelperDB.leveling.view = "shopping"
EVENT = function(e, ...) DufforthTweaksHelperLeveling.OnEvent(nil, e, ...) end
""")
ui_lua.execute("DufforthTweaksHelperLeveling.Refresh()")
ui_lua.execute("""
DufforthTweaksHelperDB.leveling.view = "plan"; DufforthTweaksHelperLeveling.Refresh()
function STEPLINE(n) local k = 0; for _, f in ipairs(ROWS()) do if f.row.step then k = k + 1; if k == (n or 1) then return f end end end end
""")
check("button: no top button away from vendors", ui_lua.eval("PARENT.action.shown") is False)
check("craft: every plan step has its own button", all(r.rowButton.shown for r in ui_lua.eval("ROWS()").values() if r.row.step))
check("craft: a step you can't craft yet says why on the button",
      all(r.rowButton.text in ("Craft", "Learn") and r.rowButton.enabled is False for r in ui_lua.eval("ROWS()").values() if r.row.step))
check("craft: hovering it says to open the window or where to learn", any("Open your Tailoring window" in ui_lua.eval("HOVER(STEPLINE(%d).rowButton)" % i) or "know" in ui_lua.eval("HOVER(STEPLINE(%d).rowButton)" % i) for i in (1, 2)))
check("craft: material rows have no button away from the auction house and vendors", not any(r.rowButton.shown for r in ui_lua.eval("ROWS()").values() if r.row.part))
ui_lua.execute('DufforthTweaksHelperDB.leveling.view = "shopping"; DufforthTweaksHelperLeveling.Refresh()')

# A vendor that sells every material on the list at 1c.
ui_lua.execute("""
SHOP = {}
for _, t in ipairs(DufforthTweaksHelperLeveling.ShoppingList(DufforthTweaksHelperLeveling.Current().plan)) do
  SHOP[#SHOP + 1] = t.id
end
GetMerchantNumItems = function() return #SHOP end
GetMerchantItemInfo = function(i) return "x", 1, 1, 1, -1, true, true, false end
GetMerchantItemID = function(i) return SHOP[i] end
GetMerchantItemMaxStack = function() return 20 end
BuyMerchantItem = function(i, n) BOUGHT[#BOUGHT + 1] = { i, n or 1 } end
EVENT("MERCHANT_SHOW")
""")
check("vendor: Buy shows how many things it buys", ui_lua.eval("PARENT.action.shown") is True and ui_lua.eval("PARENT.action.text").startswith("Buy "), ui_lua.eval("PARENT.action.text"))
check("vendor: the total shows before buying", "This vendor sells" in ui_lua.eval("TEXTS()"))
tip = ui_lua.eval("HOVER(PARENT.action)")
check("vendor: hovering Buy lists each item and the total", "Total" in tip and "x " in tip, tip[:160])
ui_lua.execute("PARENT.action.scripts.OnClick(PARENT.action)")
n_bought = int(ui_lua.eval("#BOUGHT"))
check("vendor: one click buys", n_bought > 0, n_bought)
check("vendor: says what it spent", "Bought for" in ui_lua.eval("TEXTS()"))
ui_lua.execute("PARENT.action.scripts.OnClick(PARENT.action)")
check("vendor: a second click before your bags update buys nothing more", int(ui_lua.eval("#BOUGHT")) == n_bought and ui_lua.eval("PARENT.action.enabled") is False)
check("vendor: stacks of up to 20 per purchase", all(ui_lua.eval(f"BOUGHT[{i}][2]") <= 20 for i in range(1, n_bought + 1)))
ui_lua.execute("BOUGHT = {}; MONEY = 3; T = 200; EVENT('BAG_UPDATE_DELAYED'); PARENT.action.scripts.OnClick(PARENT.action)")
check("vendor: stops when money runs out and says so", "ran out of money" in ui_lua.eval("TEXTS()") and int(ui_lua.eval("#BOUGHT")) <= 3)
# Clicking a material at the vendor finds it in the vendor window.
ui_lua.execute("""
MERCHANT_ITEMS_PER_PAGE = 10
MerchantFrame = { page = 1 }
UPDATED = 0
MerchantFrame_Update = function() UPDATED = UPDATED + 1 end
for i = 1, 10 do _G["MerchantItem" .. i] = CreateFrame("Frame"); _G["MerchantItem" .. i].ItemButton = CreateFrame("Button") end
T = 300; DufforthTweaksHelperLeveling.Refresh()
""")
sold = [r for r in ui_lua.eval("ROWS()").values() if r.rowButton.shown]
check("vendor: rows this vendor sells get a button", len(sold) > 0, len(sold))
target = sold[-1]
target.scripts.OnClick(target)
check("vendor: clicking a material turns the vendor window to it", int(ui_lua.eval("UPDATED")) >= 1 and "each here" in ui_lua.eval("TEXTS()"), ui_lua.eval("PARENT.notice.text"))
ui_lua.execute("MONEY = 10000000; EVENT('MERCHANT_CLOSED')")
check("vendor: Buy goes away when the vendor closes", ui_lua.eval("PARENT.action.shown") is False)

# The auction house: a Search button on every material row, opening the item by its ID.
ui_lua.execute("""
SELECTED = {}
C_AuctionHouse = { MakeItemKey = function(id) return { itemID = id } end, GetItemKeyInfo = function(key) return { isCommodity = true } end,
  SendSearchQuery = function(key) SEARCHED[#SEARCHED + 1] = key.itemID end }
AuctionHouseFrame = { SelectBrowseResult = function(self, result) SELECTED[#SELECTED + 1] = result.itemKey.itemID end }
EVENT("AUCTION_HOUSE_SHOW")
""")
check("auction: no top button; the note says to use the rows", ui_lua.eval("PARENT.action.shown") is False and "Click Search on a material" in ui_lua.eval("TEXTS()"))
search_rows = [r for r in ui_lua.eval("ROWS()").values() if r.rowButton.shown]
check("auction: every material row has a Search button", len(search_rows) > 0 and all(r.row.buy or r.row.part or r.row.learn for r in search_rows), len(search_rows))
check("layout: name and second line keep their own lines on every row",
      all(r.name.point[1] == "TOPLEFT" and r.name.point[3] == -3 and r.sub.point[1] == "BOTTOMLEFT" and r.sub.point[3] == 4 for r in ui_lua.eval("ROWS()").values()))
check("layout: material rows are indented past their icon", all(r.name.point[2] == 50 for r in ui_lua.eval("ROWS()").values() if r.row.part))
check("auction: the button doesn't cover the price", all(r.cost.point[2] == -66 for r in search_rows))
target = search_rows[-1]
want = target.row.buy.id if target.row.buy else (target.row.part.id if target.row.part else None)
target.rowButton.scripts.OnClick(target.rowButton)
check("auction: Search opens that exact item by ID", ui_lua.eval("SELECTED[#SELECTED]") == want and ui_lua.eval("SEARCHED[#SEARCHED]") == want, f"{ui_lua.eval('SELECTED[#SELECTED]')} vs {want}")
check("auction: says how many to buy", "buy " in ui_lua.eval("TEXTS()") and "more" in ui_lua.eval("TEXTS()"))
other = search_rows[0]
other.scripts.OnClick(other)
check("auction: clicking the row itself searches it too", int(ui_lua.eval("#SELECTED")) == 2)
ui_lua.execute("C_AuctionHouse.GetItemKeyInfo = function() return nil end; AuctionHouseFrame.SearchBar = { SetSearchText = function(self, t) self.text = t end, StartSearch = function(self) SEARCHED[#SEARCHED + 1] = self.text end }")
ui_lua.execute("GetItemInfo = function(id) return 'Name ' .. id end")
other.rowButton.scripts.OnClick(other.rowButton)
check("auction: an item the AH doesn't know yet falls back to its name", str(ui_lua.eval("SEARCHED[#SEARCHED]")).startswith("Name "))
ui_lua.execute("GetItemInfo = function() end")
other.rowButton.scripts.OnClick(other.rowButton)
check("auction: an item still loading says to click again", "still loading" in ui_lua.eval("TEXTS()"))
ui_lua.execute("EVENT('AUCTION_HOUSE_CLOSED')")
check("auction: the Search buttons go away when it closes", not any(r.rowButton.shown for r in ui_lua.eval("ROWS()").values()))

# The profession window: crafts the current step.
ui_lua.execute("""
DufforthTweaksHelperDB.leveling.view = "plan"
DufforthTweaksHelperLeveling.Refresh()
STEP = DufforthTweaksHelperLeveling.Current().plan.steps[1]
DufforthTweaksHelperCrafting.Known().spells[STEP.recipe[1]] = true
AVAILABLE = 3
GetTradeSkillLine = function() return "Tailoring" end
GetNumTradeSkills = function() return 2 end
GetTradeSkillInfo = function(i) if i == 1 then return "Cloth", "header", 0 end return STEP.recipe[9], "optimal", AVAILABLE end
GetTradeSkillRecipeLink = function(i) return "|Henchant:" .. STEP.recipe[1] .. "|h[x]|h" end
DoTradeSkill = function(i, n) CRAFTED[#CRAFTED + 1] = { i, n } end
EVENT("TRADE_SKILL_SHOW")
""")
label = ui_lua.eval("STEPLINE(1).rowButton.text")
check("craft: the step's button says Craft N, limited by your materials", label == "Craft 3", label)
ui_lua.execute("STEPLINE(1).rowButton.scripts.OnClick(STEPLINE(1).rowButton)")
check("craft: crafts that step's recipe that many times", int(ui_lua.eval("#CRAFTED")) == 1 and ui_lua.eval("CRAFTED[1][1]") == 2 and ui_lua.eval("CRAFTED[1][2]") == 3)
ui_lua.execute("STEPLINE(1).rowButton.scripts.OnClick(STEPLINE(1).rowButton)")
check("craft: a second quick click doesn't queue it twice", int(ui_lua.eval("#CRAFTED")) == 1)
check("craft: says what it's crafting", "Crafting " in ui_lua.eval("TEXTS()"))
ui_lua.execute("function PROG() local b = PARENT.progress; return (b.label.text or '') .. ' | ' .. (b.count.text or '') .. ' | ' .. (b.timeLeft.text or '') end")
check("progress: blue while crafting, in place of the summary", ui_lua.eval("PARENT.summary.shown") is False)
check("progress: the bar shows over the notice line when crafting starts", ui_lua.eval("PARENT.progress.shown") is True and ui_lua.eval("PARENT.notice.shown") is False)
check("progress: says how many of how many and the time left", "0 / 3" in ui_lua.eval("PROG()") and "about" in ui_lua.eval("PROG()"), ui_lua.eval("PROG()"))
ui_lua.execute("SP = STEP.recipe[1]; T = T + 3; EVENT('UNIT_SPELLCAST_SUCCEEDED', 'player', 'guid', SP); T = T + 3; EVENT('UNIT_SPELLCAST_SUCCEEDED', 'player', 'guid', SP)")
check("progress: counts each finished craft", "2 / 3" in ui_lua.eval("PROG()") and abs(ui_lua.eval("PARENT.progress.value") - 2 / 3) < 0.01, ui_lua.eval("PROG()"))
check("progress: time left uses the measured pace", "about 3s left" in ui_lua.eval("PROG()"), ui_lua.eval("PROG()"))
ui_lua.execute("EVENT('UNIT_SPELLCAST_SUCCEEDED', 'player', 'guid', 99999)")
check("progress: other spells don't count", "2 / 3" in ui_lua.eval("PROG()"))
ui_lua.execute("T = T + 3; EVENT('UNIT_SPELLCAST_SUCCEEDED', 'player', 'guid', SP)")
check("progress: says Done at the end", ui_lua.eval("PROG()").startswith("Done: "))
ui_lua.execute("T = T + 6; DufforthTweaksHelperLeveling.UpdateProgress()")
check("progress: green when done", ui_lua.eval("PARENT.progress.color") == "done")
check("progress: goes away a few seconds later and the notice comes back", ui_lua.eval("PARENT.progress.shown") is False and ui_lua.eval("PARENT.notice.shown") is True)
ui_lua.execute("UnitCastingInfo = function() return 'Craft' end; T = 400; DufforthTweaksHelperLeveling.Refresh()")
ui_lua.execute("UnitCastingInfo = nil; T = 500; GetContainerNumFreeSlots = function(bag) if bag == 0 then return 2, 0 end return 0, 0 end; DufforthTweaksHelperLeveling.Refresh()")
check("bags: the Craft button crafts only what fits", ui_lua.eval("STEPLINE(1).rowButton.text") == "Craft 2", ui_lua.eval("STEPLINE(1).rowButton.text"))
check("bags: its hover says when the bags fill up", "bags fill up after 2" in ui_lua.eval("HOVER(STEPLINE(1).rowButton)"))
ui_lua.execute("CRAFTED = {}; STEPLINE(1).rowButton.scripts.OnClick(STEPLINE(1).rowButton)")
check("bags: the bar says the batch stops when the bags are full", "Bags full after 2" in (ui_lua.eval("PARENT.progress.note.text") or ""))
ui_lua.execute("GetContainerNumFreeSlots = function() return 0, 0 end; T = 600; DufforthTweaksHelperLeveling.UpdateProgress(); DufforthTweaksHelperLeveling.Refresh()")
check("bags: no room says Bags full", ui_lua.eval("STEPLINE(1).rowButton.text") == "Bags full")
ui_lua.execute("GetContainerNumFreeSlots = nil; T = 700; DufforthTweaksHelperLeveling.UpdateProgress(); UnitCastingInfo = function() return 'Craft' end; DufforthTweaksHelperLeveling.Refresh()")
check("craft: while crafting the buttons wait", ui_lua.eval("STEPLINE(1).rowButton.text") == "Crafting" and ui_lua.eval("STEPLINE(1).rowButton.enabled") is False)
ui_lua.execute("UnitCastingInfo = nil; AVAILABLE = 0; DufforthTweaksHelperLeveling.Refresh()")
check("craft: no materials says No mats", ui_lua.eval("STEPLINE(1).rowButton.text") == "No mats" and ui_lua.eval("STEPLINE(1).rowButton.enabled") is False)
ui_lua.execute("GetItemCount = function() return 1000 end; DufforthTweaksHelperLeveling.Refresh()")
label = ui_lua.eval("STEPLINE(1).rowButton.text")
check("craft: the window says 0 but your bags have the materials: still crafts", label.startswith("Craft ") and label != "Craft", label)
check("craft: the hover shows both numbers", "Your bags have materials for" in ui_lua.eval("HOVER(STEPLINE(1).rowButton)"))
check("craft: bag count uses the recipe's materials", ui_lua.eval("DufforthTweaksHelperLeveling.CanMake({ [12] = { 1, 2, 3, 5 } })") == 200)
ui_lua.execute("GetItemCount = function() return 0 end; DufforthTweaksHelperLeveling.Refresh()")
check("craft: hovering No mats points at the material rows", "what's missing" in ui_lua.eval("HOVER(STEPLINE(1).rowButton)"))
ui_lua.execute("DufforthTweaksHelperCrafting.Known().spells[STEP.recipe[1]] = nil; AVAILABLE = 3; DufforthTweaksHelperLeveling.Refresh()")
check("craft: a recipe you don't know says Learn", ui_lua.eval("STEP.recipe[10]") == "s" or ui_lua.eval("STEPLINE(1).rowButton.text") == "Learn")
ui_lua.execute("EVENT('TRADE_SKILL_CLOSE'); DufforthTweaksHelperCrafting.Known().spells[STEP.recipe[1]] = true; DufforthTweaksHelperLeveling.Refresh()")
check("craft: the buttons grey out when the window closes", ui_lua.eval("STEPLINE(1).rowButton.enabled") is False and ui_lua.eval("STEPLINE(1).rowButton.text") == "Craft")
# Opening a profession window opens this tab on it, and closing it closes the window again.
ui_lua.execute("""
SHOWN, OPENED = false, nil
DufforthTweaksHelperMenu = { IsShown = function() return SHOWN end, Hide = function() SHOWN = false end }
DufforthTweaksHelperMenu_Toggle = function(tab) OPENED = tab; SHOWN = true end
DufforthTweaksHelperDB.leveling.profession = "Blacksmithing"
EVENT("TRADE_SKILL_SHOW")
""")
check("auto-open: opening Tailoring opens the Leveling tab on Tailoring", ui_lua.eval("OPENED") == "leveling" and ui_lua.eval("DufforthTweaksHelperDB.leveling.profession") == "Tailoring")
ui_lua.execute("EVENT('TRADE_SKILL_CLOSE')")
check("auto-open: closing the profession window closes it again", ui_lua.eval("SHOWN") is False)
ui_lua.execute("SHOWN, OPENED = true, nil; EVENT('TRADE_SKILL_SHOW'); EVENT('TRADE_SKILL_CLOSE')")
check("auto-open: a window you opened yourself stays open", ui_lua.eval("SHOWN") is True)
ui_lua.execute("SHOWN, OPENED = false, nil; GetTradeSkillLine = function() return 'Mining' end; EVENT('TRADE_SKILL_SHOW')")
check("auto-open: smelting (Mining) doesn't open it", ui_lua.eval("OPENED") is None)
ui_lua.execute("GetTradeSkillLine = function() return 'Tailoring' end; DufforthTweaksHelperDB.leveling.openWithProfession = false; EVENT('TRADE_SKILL_SHOW')")
check("auto-open: the checkbox turns it off", ui_lua.eval("OPENED") is None)
# Forever: the game doesn't name the window; the recipes in it tell which profession it is.
ui_lua.execute("""
SHOWN, OPENED = false, nil
DufforthTweaksHelperDB.leveling.openWithProfession = true
DufforthTweaksHelperDB.leveling.profession = "Blacksmithing"
GetTradeSkillLine = function() return nil end
EVENT("TRADE_SKILL_SHOW")
""")
check("auto-open: an unnamed window is told by its recipes and opens the tab", ui_lua.eval("OPENED") == "leveling" and ui_lua.eval("DufforthTweaksHelperDB.leveling.profession") == "Tailoring",
      ui_lua.eval("DufforthTweaksHelperDB.leveling.profession"))
ui_lua.execute("GetTradeSkillLine = function() return 'UNKNOWN' end; DufforthTweaksHelperDB.leveling.profession = 'Blacksmithing'; EVENT('TRADE_SKILL_SHOW')")
check("auto-open: 'UNKNOWN' is not a name either", ui_lua.eval("DufforthTweaksHelperDB.leveling.profession") == "Tailoring")
ui_lua.execute("DufforthTweaksHelperCrafting.Known().scanned = {}; DufforthTweaksHelperCrafting.ScanOpenProfession()")
check("crafting: the window's recipes count as scanned for that profession", ui_lua.eval("DufforthTweaksHelperCrafting.Known().scanned.Tailoring") is True)
ui_lua.execute("GetTradeSkillLine = function() return 'Tailoring' end; EVENT('TRADE_SKILL_CLOSE')")
check("auto-open: on by default, with a checkbox in the tab", any(rawb == "openWithProfession" for rawb in [b.key for b in ui_lua.eval("PARENT.boxes").values()]))
# A step whose recipe is an item: Search, not Learn.
ui_lua.execute("""
DufforthTweaksHelperDB.leveling.view = "plan"
RSTEP = nil
for _, f in ipairs(ROWS()) do if f.row.step and f.row.step.candidate.kind ~= "known" and (f.row.step.recipe[11] or 0) > 0 then RSTEP = RSTEP or f.row.step end end
if not RSTEP then
  -- Make the first step's recipe an item sold on the auction house (how "i", 5c).
  RSTEP = DufforthTweaksHelperLeveling.Current().plan.steps[1]
  RSTEP.recipe[10] = "i"; RSTEP.recipe[11] = 900001
  DufforthTweaksHelperPrices[DufforthTweaksHelper.MarketName()][900001] = 5
end
DufforthTweaksHelperLeveling.Refresh()
function RLINE() for _, f in ipairs(ROWS()) do if f.row.step and f.row.step.recipe[1] == RSTEP.recipe[1] then return f end end end
DufforthTweaksHelperCrafting.Known().spells[RSTEP.recipe[1]] = nil
EVENT('AUCTION_HOUSE_CLOSED'); EVENT('MERCHANT_CLOSED')
""")
print("     recipe step:", ui_lua.eval("RSTEP.recipe[9]"), ui_lua.eval("RLINE().row.step.candidate.kind"))
check("recipe item: the test step is learned from an AH recipe", ui_lua.eval("RLINE().row.step.candidate.kind") == "auction")
if True:
    check("recipe item: away from the auction house the step says Search, greyed", ui_lua.eval("RLINE().rowButton.text") == "Search" and ui_lua.eval("RLINE().rowButton.enabled") is False)
    check("recipe item: hovering says to open the auction house", "Open the auction house" in ui_lua.eval("HOVER(RLINE().rowButton)"))
ui_lua.execute("SELECTED = {}; C_AuctionHouse.GetItemKeyInfo = function() return {} end; EVENT('AUCTION_HOUSE_SHOW')")
check("recipe item: at the auction house it's an active Search", ui_lua.eval("RLINE().rowButton.text") == "Search" and ui_lua.eval("RLINE().rowButton.enabled") is True)
ui_lua.execute("RLINE().rowButton.scripts.OnClick(RLINE().rowButton)")
check("recipe item: Search opens the recipe item", ui_lua.eval("SELECTED[#SELECTED]") == ui_lua.eval("RSTEP.recipe[11]"))
# Material sources are short and colored: AH and Vendor.
texts = ui_lua.eval("TEXTS()")
check("materials: the auction house is written AH, in orange", "|cffff9933AH|r" in texts and "auction house," not in texts, texts[:300])
W = ui_lua.eval("DufforthTweaksHelperLeveling.SOURCE_WORDS")
check("materials: vendor and AH have different colors", W.vendor[:10] != W.auction[:10] and "Vendor" in W.vendor)
# At a trainer: Learn learns the step's recipe.
ui_lua.execute("""
EVENT('AUCTION_HOUSE_CLOSED')
RSTEP.recipe[10] = "t"; RSTEP.recipe[11] = 0
DufforthTweaksHelperLevelTrainers[RSTEP.recipe[1]] = { 1, 50, 1 }
SERVICES = { { "Other Recipe", "", "available" }, { RSTEP.recipe[9], "", "available" } }
GetNumTrainerServices = function() return #SERVICES end
GetTrainerServiceInfo = function(i) return SERVICES[i][1], SERVICES[i][2], SERVICES[i][3] end
LEARNED = nil; BuyTrainerService = function(i) LEARNED = i end
DufforthTweaksHelperLeveling.Refresh()
""")
check("trainer: away from a trainer Learn is greyed", ui_lua.eval("RLINE().rowButton.text") == "Learn" and ui_lua.eval("RLINE().rowButton.enabled") is False)
check("trainer: the hover names the trainer and says to talk to one", "Trainer " in ui_lua.eval("HOVER(RLINE().rowButton)") and "Talk to the trainer" in ui_lua.eval("HOVER(RLINE().rowButton)"))
ui_lua.execute("EVENT('TRAINER_SHOW')")
check("trainer: at the trainer Learn is active", ui_lua.eval("RLINE().rowButton.text") == "Learn" and ui_lua.eval("RLINE().rowButton.enabled") is True)
ui_lua.execute("RLINE().rowButton.scripts.OnClick(RLINE().rowButton)")
check("trainer: Learn buys that recipe's entry", ui_lua.eval("LEARNED") == 2)
check("trainer: it counts as known right away", ui_lua.eval("DufforthTweaksHelperCrafting.Known().spells[RSTEP.recipe[1]]") is True)
ui_lua.execute("DufforthTweaksHelperCrafting.Known().spells[RSTEP.recipe[1]] = nil; SERVICES[2][3] = 'unavailable'; DufforthTweaksHelperLeveling.Refresh()")
check("trainer: too low skill: greyed, and says why", ui_lua.eval("RLINE().rowButton.enabled") is False and "too low" in ui_lua.eval("HOVER(RLINE().rowButton)"))
ui_lua.execute("SERVICES = { SERVICES[1] }; DufforthTweaksHelperLeveling.Refresh()")
check("trainer: a trainer that doesn't teach it says so", "doesn't teach" in ui_lua.eval("HOVER(RLINE().rowButton)"))
ui_lua.execute("EVENT('TRAINER_CLOSED'); DufforthTweaksHelperLeveling.Refresh()")
check("trainer: closing the trainer greys it again", ui_lua.eval("RLINE().rowButton.enabled") is False)
# Forever: a hidden ClassTrainerFrame must not switch Learn off while the trainer is open.
ui_lua.execute("""
SERVICES = { { "Other Recipe", "", "available" }, { RSTEP.recipe[9], "", "available" } }
ClassTrainerFrame = { IsShown = function() return false end }
EVENT('TRAINER_SHOW'); DufforthTweaksHelperLeveling.Refresh()
""")
check("trainer: a hidden ClassTrainerFrame doesn't turn Learn off at the trainer", ui_lua.eval("RLINE().rowButton.enabled") is True)
ui_lua.execute("SERVICES = { SERVICES[1] }; DufforthTweaksHelperLeveling.Refresh()")
check("trainer: the hover lists what the trainer offers", "The trainer lists 1 spell: Other Recipe" in ui_lua.eval("HOVER(RLINE().rowButton)"), ui_lua.eval("HOVER(RLINE().rowButton)"))
# The trainer you're talking to, then one in your zone, comes first.
ui_lua.execute("""
PL = { { npc = { "James Van Brunt", "", "H", "Undercity", 61, 31 } }, { npc = { "Far One", "", "H", "Orgrimmar", 1, 1 } },
       { npc = { "Karn Stonehoof", "", "H", "Thunder Bluff", 39, 55 } }, { npc = { "Local", "", "H", "Thunder Bluff", 40, 50 } } }
N1 = DufforthTweaksHelperLeveling.Nearest(PL, "Thunder Bluff", "Karn Stonehoof")
N2 = DufforthTweaksHelperLeveling.Nearest(PL, "Thunder Bluff", nil)
N3 = DufforthTweaksHelperLeveling.Nearest(PL, "Ashenvale", nil)
""")
check("trainer place: the one you're talking to first", ui_lua.eval("N1[1].npc[1]") == "Karn Stonehoof" and ui_lua.eval("#N1") == 4)
check("trainer place: then one in your zone", ui_lua.eval("N2[1].npc[1]") == "Karn Stonehoof" and ui_lua.eval("N2[2].npc[1]") == "Local")
check("trainer place: elsewhere, the usual order", ui_lua.eval("N3[1].npc[1]") == "James Van Brunt")
# Forever's trainer list: (name, category, icon), not Classic's (name, rank, category).
ui_lua.execute("""
SERVICES = { { "Other Recipe", "available", 133476 }, { RSTEP.recipe[9], "available", 133483 } }
DufforthTweaksHelperLeveling.Refresh()
""")
check("trainer: Forever's list layout (name, category, icon) still finds an available recipe", ui_lua.eval("RLINE().rowButton.enabled") is True)
ui_lua.execute("SERVICES[2] = { RSTEP.recipe[9], 'unavailable', 133483 }; DufforthTweaksHelperLeveling.Refresh()")
check("trainer: Forever layout, unavailable stays greyed", ui_lua.eval("RLINE().rowButton.enabled") is False)
ui_lua.execute("EVENT('TRAINER_CLOSED'); ClassTrainerFrame = nil; DufforthTweaksHelperLeveling.Refresh()")
ui_lua.execute("REAL = DufforthTweaksHelperLevelNPCs; DufforthTweaksHelperLevelNPCs = { { 'Horde Trainer', '', 'H', 'Orgrimmar', 1, 1 }, {}, { 'Goblin', '', '', 'Tanaris', 1, 1 } }")
ui_lua.execute("PC = DufforthTweaksHelperLeveling.Places({ 3, 10, 0, 1, 50, 0 }, nil, true); PN = DufforthTweaksHelperLeveling.Places({ 3, 10, 0, 1, 50, 0 }, nil)")
check("trainers: a capital city's trainer comes first", ui_lua.eval("PC[1].npc[4]") == "Orgrimmar")
check("vendors: still cheapest first", ui_lua.eval("PN[1].npc[1]") == "Goblin")
ui_lua.execute("DufforthTweaksHelperLevelNPCs = REAL")
ui_lua.execute("EVENT('AUCTION_HOUSE_CLOSED')")
check("button: nothing is printed to chat", int(ui_lua.eval("#CHAT")) == 0)

print(f"\n{len(fails)} failed" if fails else "\nall passed")
sys.exit(1 if fails else 0)
