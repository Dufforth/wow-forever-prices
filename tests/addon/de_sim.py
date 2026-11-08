"""Runs Disenchant.lua outside the game and checks its tables, prices and tooltip lines.

    python tests/addon/de_sim.py
"""
import os
import sys
import lupa.lua51 as L

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = open(os.path.join(ROOT, "addon", "DufforthAHScanner", "Disenchant.lua"), encoding="utf-8").read()

MOCK = r"""
NOW = 1000000
CHAT = {}
time = function() return NOW end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) CHAT[#CHAT+1] = m end }
ITEMS = {
  [1] = { "Green Helm", nil, 2, 30, nil, nil, nil, nil, "INVTYPE_HEAD", nil, nil, 4 },
  [2] = { "Green Sword", nil, 2, 30, nil, nil, nil, nil, "INVTYPE_WEAPON", nil, nil, 2 },
  [3] = { "Blue Ring", nil, 3, 28, nil, nil, nil, nil, "INVTYPE_FINGER", nil, nil, 4 },
  [4] = { "Purple Cloak", nil, 4, 60, nil, nil, nil, nil, "INVTYPE_CLOAK", nil, nil, 4 },
  [5] = { "Green Shirt", nil, 2, 30, nil, nil, nil, nil, "INVTYPE_BODY", nil, nil, 4 },
  [6] = { "Linen Cloth", nil, 1, 5, nil, nil, nil, nil, "", nil, nil, 7 },
}
GetItemInfo = function(id) local i = ITEMS[id]; if i then return unpack(i, 1, 12) end end
HOOKS = {}
local function tooltip(name)
  local t = { lines = {} }
  function t:HookScript(event, f) HOOKS[name .. ":" .. event] = f end
  function t:AddLine(text) self.lines[#self.lines+1] = text end
  function t:AddDoubleLine(l, r) self.lines[#self.lines+1] = l .. " || " .. r end
  function t:Show() end
  function t:GetItem() return "x", "|cff1eff00|Hitem:" .. self.id .. "::|h[x]|h|r" end
  return t
end
GameTooltip = tooltip("GameTooltip")
DufforthAHScanner = { MarketName = function() return "forever.normal.horde.us" end }
DufforthAHScannerPrices = { at = NOW - 3600, ["forever.normal.horde.us"] = { [11083] = 1000, [11082] = 4000, [11084] = 6000, [20725] = 90000 } }
"""

lua = L.LuaRuntime(unpack_returned_tuples=True)
lua.execute(MOCK)
lua.execute(SRC)
g = lua.globals()
DE = g.DufforthAHScannerDE
fails = []


def check(name, ok):
    print(("ok   " if ok else "FAIL ") + name)
    if not ok:
        fails.append(name)


def item(quality, level, class_id, slot="INVTYPE_HEAD"):
    return lua.table_from({"quality": quality, "level": level, "classID": class_id, "slot": slot})


armor = DE.Outcomes(item(2, 30, 4))
check("armor 30: 75% Soul Dust", armor[1].id == 11083 and abs(armor[1].chance - 0.75) < 1e-9)
weapon = DE.Outcomes(item(2, 30, 2))
check("weapons favor essence", abs(weapon[1].chance - 0.2) < 1e-9 and abs(weapon[2].chance - 0.75) < 1e-9)
check("rare 28: Large Glimmering Shard", DE.Outcomes(item(3, 28, 4))[1].id == 11084)
epic = DE.Outcomes(item(4, 60, 4))
check("epic 60: one Nexus Crystal", epic[1].id == 20725 and epic[1].min == 1 and epic[1].max == 1)
check("common items can't be disenchanted", DE.Outcomes(item(1, 30, 4)) is None)
check("shirts can't be disenchanted", DE.Outcomes(item(2, 30, 4, "INVTYPE_BODY")) is None)
check("trade goods can't be disenchanted", DE.Outcomes(item(2, 30, 7)) is None)
check("skill: level 15 needs 1", DE.SkillNeeded(item(2, 15, 4)) == 1)
check("skill: level 30 needs 50", DE.SkillNeeded(item(2, 30, 4)) == 50)
check("skill: rare level 20 needs 25", DE.SkillNeeded(item(3, 20, 2)) == 25)
check("skill: epic 60 needs 200", DE.SkillNeeded(item(4, 60, 4)) == 200)

market = "forever.normal.horde.us"
shipped = g.DufforthAHScannerPrices
check("bundled price for this market", DE.Price(11084, market, shipped) == 6000)
check("no price for another market", DE.Price(11084, "forever.pvp.horde.us", shipped) is None)
check("no price for an unlisted item", DE.Price(10940, market, shipped) is None)

# Average for the level-30 helm with download prices: 75% x1.5 x1000 + 20% x1.5 x4000 + 5% x1 x6000, after 5%.
expected = (0.75 * 1.5 * 1000 + 0.2 * 1.5 * 4000 + 0.05 * 6000) * 0.95
value = DE.ExpectedValue(armor, lua.eval("function(id) return DufforthAHScannerPrices['forever.normal.horde.us'][id] end"))
check("average value matches the page's formula", abs(value - expected) < 1e-6)

lines = DE.TooltipLines(item(2, 30, 4), market, shipped, 1000000, 10)
texts = [lines[i][1] for i in range(1, len(lines) + 1)]
check("header names the skill needed", texts[0] == "Disenchants into (Enchanting 50)")
check("header turns red below the skill", lines[1][3] == 1 and lines[1][4] < 1)
check("one line per material", len(texts) == 5 and "75%  1-2x Soul Dust" in texts[1] and "5%  1x Large Glimmering Shard" in texts[3])
check("fresh prices need no age note", texts[4] == "  Average value")
shipped.at = 1000000 - 3 * 86400
old_lines = DE.TooltipLines(item(2, 30, 4), market, shipped, 1000000, 10)
check("old prices say how old they are", old_lines[5][1] == "  Average value (prices 3 days old)")
lines = DE.TooltipLines(item(4, 60, 4), market, shipped, 1000000, 300)
check("epic: no chance shown when certain", lines[2][1] == "  1x Nexus Crystal" and lines[1][3] != 1)
check("cloth gets no lines", DE.TooltipLines(item(1, 5, 7), market, shipped, 1000000, None) is None)

# Real tooltip hooks: the fallback path adds lines once per item.
GT = g.GameTooltip
GT.id = 1
g.HOOKS["GameTooltip:OnTooltipSetItem"](GT)
g.HOOKS["GameTooltip:OnTooltipSetItem"](GT)
check("tooltip gets the lines once", len(GT.lines) == 5)
g.HOOKS["GameTooltip:OnTooltipCleared"](GT)
GT.lines = lua.table()
GT.id = 6
g.HOOKS["GameTooltip:OnTooltipSetItem"](GT)
check("cloth tooltip untouched", len(GT.lines) == 0)
g.DufforthAHScannerDB = lua.table()
DE.Toggle("off")
GT.id = 2
g.HOOKS["GameTooltip:OnTooltipCleared"](GT)
g.HOOKS["GameTooltip:OnTooltipSetItem"](GT)
check("off means no lines", len(GT.lines) == 0 and "OFF" in g.CHAT[1])

if fails:
    sys.exit(f"{len(fails)} failed")
print("all passed")
