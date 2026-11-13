"""Loads every addon file in toc order the way Forever's client does, opens every tab and draws the Leveling plan.

Like the game: registering an unknown event (CRAFT_SHOW) is an error, %d rejects decimals,
and GetProfessions leaves empty slots.

    python tests/addon/full_load_sim.py
"""
import os
import sys
import lupa.lua51 as L
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ADDON = os.path.join(REPO, "addon", "DufforthTweaksHelper")
src = open(os.path.join(REPO, "tests", "addon", "menu_sim.py"), encoding="utf-8").read()
mock = src[src.index('MOCK = r"""') + len('MOCK = r"""'):]
mock = mock[:mock.index('"""')]
lua = L.LuaRuntime(unpack_returned_tuples=True)
lua.execute(mock)
lua.execute(r'''
GetRealmName = function() return "Forever PvP" end
UnitName = function() return "Duff" end
UnitFactionGroup = function() return "Horde" end
DufforthTweaksHelper = nil
local realCreate = CreateFrame
CreateFrame = function(...)
  local f = realCreate(...)
  local reg = f.RegisterEvent
  f.RegisterEvent = function(self, e)
    if string.sub(e, 1, 6) == "CRAFT_" then error("Attempt to register unknown event \"" .. e .. "\"", 2) end
    return reg(self, e)
  end
  f.IsVisible = function() return true end
  return f
end
local realFormat = string.format
string.format = function(pattern, ...)
  local args, i = { ... }, 0
  for spec in string.gmatch(pattern, "%%[-+ #0]*%d*%.?%d*([%a%%])") do
    if spec ~= "%" then
      i = i + 1
      if spec == "d" and type(args[i]) == "number" and args[i] ~= math.floor(args[i]) then error("number has no integer representation", 2) end
    end
  end
  return realFormat(pattern, ...)
end
PROFS = { [1] = { "Tailoring", nil, 87, 150, 0, 0, 197, 0 }, [5] = { "Cooking", nil, 40, 75, 0, 0, 185, 0 } }
GetProfessions = function() return 1, nil, nil, nil, 5, nil end
GetProfessionInfo = function(i) return unpack(PROFS[i], 1, 8) end
''')
toc = open(os.path.join(ADDON, "DufforthTweaksHelper.toc"), encoding="utf-8").read().splitlines()
ns = lua.table()
bad = False
for f in [l.strip() for l in toc if l.strip().endswith(".lua")]:
    code = open(os.path.join(ADDON, f), encoding="utf-8").read()
    try:
        lua.eval("function(src, name, ns) local fn, err = loadstring(src, name); if not fn then error(err) end; fn('DufforthTweaksHelper', ns) end")(code, f, ns)
    except Exception as e:
        bad = True
        print("LOAD ERROR", f, str(e)[:300])
for tab in ("leveling", "gather", "crafting", "warrior", "disenchant", "leveling"):
    try:
        lua.execute(f'DufforthTweaksHelperMenu_Toggle("{tab}")')
    except Exception as e:
        bad = True
        print("OPEN ERROR", tab, str(e)[:300])
chat = lua.eval('table.concat(CHAT, " / ")')
print("chat:", chat[:400])
lua.execute("DufforthTweaksHelperLeveling.Refresh()")
texts = lua.eval('(function() local o = {} for _, f in ipairs(ALL) do local t = rawget(f, "text"); if t and (string.find(t, "/ 150", 1, true) or string.find(t, "To 150", 1, true) or string.find(t, "error", 1, true) or string.find(t, "crafts", 1, true)) then o[#o+1] = t end end return table.concat(o, " || ") end)()')
print("leveling tab:", texts[:500])
ok = not bad and "error" not in texts.lower() and "crafts" in texts
print("all passed" if ok else "FAILED")
sys.exit(0 if ok else 1)
