"""The guide next to RestedXP (user, 2026-11-27, screenshot ingame-compare-1: "compair this is not looking the same"):
the same part and step as RestedXP (its saved place followed, its step numbers), RestedXP's own text with its colours
and icons, cards for the active steps only, and no deadlock at the end of a part. Fixture scenarios plus the real
Durotar route at the screenshot's moment (Orc Hunter, 26-28 Ashenvale step 36)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rxp_sim import ADDON, check, runtime  # noqa: E402
import rxp_sim  # noqa: E402

FIXTURE = r"""
DATA = { uiMaps = { Durotar = 1411 }, extras = { class = {}, dungeon = {}, item = {} }, quests = {},
  routes = { Two = { races = { "Orc" }, rxp = true, parts = { "01-06 A", "6-10 B" }, subs = { "Speedrun Guide 1-22", "Speedrun Guide 1-22" },
    steps = {
      { "goto", 0, "Durotar", 90, 90, 1, "Go to Durotar", 0, nil, nil, 1, { rt = "Travel |cRXP_WARN_north|r" } },  -- 1
      { "accept", 1, "Durotar", 20, 20, 1, "Accept One", 0, nil, nil, 2, { rt = "Accept |cRXP_FRIENDLY_One|r" } }, -- 2
      { "use", 0, "Durotar", 20, 20, 1, "", 0, nil, nil, 2, { i = 5, t = 1, h = 1 } },                             -- 3
      { "accept", 3, "Durotar", 20, 20, 1, "Accept Mage", 0, nil, nil, 3, { lt = "Mage" } },                         -- 4
      { "accept", 2, "Durotar", 30, 30, 6, "Accept Two", 0, nil, nil, 4 },                                          -- 5
    },
    rx = {
      { p = 0, ln = 4, s = 1, cw = 2, a = 1, b = 1, pt = { { "Durotar", 90, 90, 25, 0, "", 1 } } },
      { p = 0, ln = 9, a = 2, b = 3, x = { { 0, "Kill |cRXP_ENEMY_Boars|r. Loot |T133972:0|t[|cRXP_LOOT_Meat|r]", "" }, { 1, "|cRXP_WARN_Mages only|r", "Mage" }, { 2, "After", "" } } },
      { p = 0, ln = 14, t = "Mage", a = 4, b = 4 },
      { p = 1, ln = 4, a = 5, b = 5 },
    } },
    Join = { races = { "Orc" }, rxp = true, parts = { "1-6 A", "6-10 B" }, steps = {
      { "accept", 7, "Durotar", 20, 20, 1, "Accept Seven", 0, nil, nil, 1 },
      { "accept", 8, "Durotar", 20, 20, 1, "Accept Eight", 0, nil, nil, 2 },
      { "accept", 9, "Durotar", 20, 20, 6, "Accept Nine", 0, nil, nil, 3 },
    }, rx = { { p = 0, s = 1, a = 1, b = 1 }, { p = 0, a = 2, b = 2 }, { p = 1, a = 3, b = 3 } } },
  },
}
"""


def fixture():
    lua = runtime()
    lua.execute(FIXTURE)
    lua.execute("""
T = NEWT({ level = 1, class = "HUNTER" })
SAVED = { skipped = {} }
function M() return G.NewModel(DATA, "Two", GAME(T), SAVED) end
function J(t) local o = {} for _, v in ipairs(t or {}) do o[#o + 1] = tostring(v) end return table.concat(o, ",") end
""")
    ev, run = lua.eval, lua.execute

    # 1. A "completewith next" side step before a part's last step doesn't hold the part (the 24-26 deadlock).
    check("start: side step 1 and step 2", ev("J(M():RxActive())") == "1,2", ev("J(M():RxActive())"))
    run("T.log[1] = true")
    check("last step of part A done: the pointer goes into part B, the side step closes", ev("M():RxAt()") == 4, ev("M():RxAt()"))
    check("part B's step is active", ev("J(M():RxActive())") == "4", ev("J(M():RxActive())"))

    # 1b. Joining (or being put) at a part's first step doesn't go back to wait for the last part's open side steps
    # (a level 14 Druid joined "12-17 The Barrens" and was pulled back to the end of "6-12 Mulgore").
    check("join at level 6: part B's first step, not held in part A", ev("(function() T.level = 6 local m = G.NewModel(DATA, 'Join', GAME(T), { skipped = {} }) local at = m:RxAt() T.level = 1 return at end)()") == 3)
    check("moving into part B the normal way still waits for part A's open side step",
          ev("(function() local s = { skipped = {} } local m = G.NewModel(DATA, 'Join', GAME(T), s) m:RxAt() T.log[8] = true m = G.NewModel(DATA, 'Join', GAME(T), s) local at = m:RxAt() T.log[8] = nil return at end)()") == 2)

    # 2. RestedXP's numbers: per part, counting only the steps for you (a Hunter: the Mage step isn't counted).
    check("step numbers per part, yours only", ev("J({ M():RxNumber(1), M():RxNumber(2), tostring(M():RxNumber(3)), M():RxNumber(4) })") == "1,2,nil,1",
          ev("J({ M():RxNumber(1), M():RxNumber(2), tostring(M():RxNumber(3)), M():RxNumber(4) })"))

    # 3. RestedXP's saved place: by step id (guide id + line), "01-06" is "1-6"; then by number; only when it changes.
    run("SAVED = { skipped = {} }; T.log[1] = nil")
    check("sync to RestedXP's step id", ev("M():RxSync({ name = '1-6 A', stepId = 1009, guideId = 1000 })") is True and ev("M():RxAt()") == 2)
    run("SAVED.rx.at = 4")
    check("same RestedXP place again: no move (you moved on here)", ev("M():RxSync({ name = '1-6 A', stepId = 1009, guideId = 1000 })") is False and ev("M():RxAt()") == 4)
    check("sync by RestedXP's number when no id", ev("M():RxSync({ name = '6-10 B', step = 1 })") is False and ev("M():RxAt()") == 4)
    check("sync: RestedXP's skipped side steps", ev("M():RxSync({ name = '01-06 A', step = 2, skip = { [1] = true } })") is True
          and ev("M():RxAt()") == 2 and ev("J(M():RxActive())") == "2", ev("J(M():RxActive())"))
    check("unknown part: no move", ev("M():RxSync({ name = '99-99 Z', step = 1 })") is False)

    # 4. RestedXP's text, in its order, with its colours; lines it shows no text for are left out.
    d = "local o = {} for _, l in ipairs(M():RxDisplay(2)) do o[#o + 1] = l.text or (l.said or ('row' .. l.row)) end return table.concat(o, ' | ')"
    want = ("Kill |cFFFF5722Boars|r. Loot |T133972:0|t[|cFF00BCD4Meat|r] | Accept |cFF00FF25One|r | After")
    check("card lines: RestedXP's text lines and line text, colours as RestedXP's, the .use without text hidden, Mage line out",
          ev("(function() " + d + " end)()") == want, ev("(function() " + d + " end)()"))
    check("unknown colour names fall back to white", ev("G.Rx.Colorize('|cRXP_NEW_x|r')") == "|cFFFFFFFFx|r")
    check("part and subgroup names", ev("M():RxPartName(0) .. ' / ' .. M():RxSubName(0)") == "01-06 A / Speedrun Guide 1-22")


def real_screenshot():
    """The real Durotar route at the screenshot's moment: RestedXP on 26-28 Ashenvale step 36 (step id 1151209535,
    guide id 1151209086), Orc Hunter level 28 with The Sacred Flame (1195) in the log."""
    lua = runtime()
    lua.execute((ADDON / "GuideData.lua").read_text(encoding="utf-8"))
    lua.execute("""
D = DufforthTweaksHelperGuideData
T = NEWT({ level = 28, class = "HUNTER", race = "Orc" })
T.log[1195] = true; T.log[1088] = true; T.log[6441] = true; T.log[6503] = true
S = { skipped = {} }
function M() return G.NewModel(D, "Durotar", GAME(T), S) end
function NUMS(t) local o = {} for _, n in ipairs(t) do o[#o + 1] = tostring(M():RxNumber(n)) end return table.concat(o, ",") end
""")
    ev = lua.eval
    moved = ev("M():RxSync({ name = '26-28 Ashenvale', step = 36, stepId = 1151209535, guideId = 1151209086, "
               "skip = { [6] = true, [11] = true, [12] = true, [13] = true, [16] = true, [17] = true, [18] = true, [23] = true, [24] = true, [25] = true, [27] = true } })")
    check("real: synced to RestedXP's place", moved is True)
    at = ev("M():RxAt()")
    check("real: same part and step number as RestedXP (26-28 Ashenvale, step 36)",
          ev("M():RxPartName(M():Rec(M():RxAt()).p)") == "26-28 Ashenvale" and ev("M():RxNumber(M():RxAt())") == 36,
          f"{ev('M():RxPartName(M():Rec(M():RxAt()).p)')} {ev('M():RxNumber(M():RxAt())')}")
    nums = ev("NUMS(M():RxActive())")
    check("real: the last active steps are RestedXP's cards (34 Raynewood, 35 Shadumbra, 36 Laughing Sisters)", nums.endswith("34,35,36"), nums)
    lines = ev("(function() local o = {} for _, l in ipairs(M():RxDisplay(M():RxAt())) do o[#o + 1] = l.text or l.said or ('row:' .. D.routes.Durotar.steps[l.row][1]) end return table.concat(o, ' | ') end)()")
    check("real: step 36 shows RestedXP's text with colours and the item icon",
          lines.startswith("Kill |cFFFF5722Laughing Sisters|r. Loot them for an |T134776:0|t[|cFF00BCD4Etched Phial|r]"), lines)
    check("real: then its collect line (Etched Phial: 0/1 in the game)", lines.endswith("row:collect"), lines)
    side = ev("(function() local a = M():RxActive() local o = {} for _, l in ipairs(M():RxDisplay(a[#a - 1])) do o[#o + 1] = l.text or l.said or D.routes.Durotar.steps[l.row][1] end return table.concat(o, ' | ') end)()")
    check("real: Shadumbra card = RestedXP's lines in order (text, text, collect, accept)",
          side.startswith("Kill |cFFFF5722Shadumbra|r. Loot her for |T132225:0|t") and "patrols around slightly" in side
          and side.endswith("collect | Accept Shadumbra's Head"), side)
    raw = ev("(function() for _, s in ipairs(D.routes.Durotar.steps) do local t = s[7] or '' if t:match('quest %d') or t:match('item %d') or t:match('spell %d') then return t end end return '' end)()")
    check("real: no raw ids in any line text", raw == "", raw)


def main():
    fixture()
    real_screenshot()
    if rxp_sim.failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
