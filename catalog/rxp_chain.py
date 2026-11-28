"""RestedXP's Forever guides as a chain of events, the base of our leveling routes (user, 2026-11-24: "I want to base
our route on RestedXP's route"; every route, follow its order and fill gaps).

Source and licence: RestedXP Guides (https://github.com/RestedXP/RXPGuides), Guides/forever, CC BY-NC-SA 4.0. Only
the order of the guide's events is kept (accept, objective, hand-in, flight, hearthstone, set hearthstone, its first
map point and level); no guide text, tips or wording. tools/extract_rxp_route.py writes catalog/rxp_routes.json.

An event is [kind, quest, objective, continent, world x, world y, level]; kind: accept, complete, turnin, fly,
hearth, home, travel. Points are world yards (continent, x, y), like the rest of the route builder.
"""
import re

from rxp_route import for_me

GOTO = re.compile(r"^\.goto\s+\d+/(\d+),\s*(-?\d+(?:\.\d+)?)[\d.]*,\s*(-?\d+(?:\.\d+)?)")
EVENT = re.compile(r"^\.(accept|turnin|complete)\s+(\d+)(?:,(\d+))?")
XP = re.compile(r"^\.xp\s+<?\s*(\d+)")
HOME = re.compile(r"^\.(home|bindlocation)\b")

MAIN, DUNGEON = "RestedXP Forever Guide (H)", "RestedXP Forever Dungeon Guide (H)"
# Where each of our starts begins in RestedXP's guides.
FIRST_PART = {"Durotar": "1-6 Durotar", "Mulgore": "1-6 Mulgore", "Tirisfal Glades": "1-6 Tirisfal Glades"}
# Who the route is for: the start's races and a warrior (the guide's class branches go the "most classes" way;
# other classes' own quests are added later by route_class.insert_class_quests).
STARTS = {"Durotar": {"Horde", "Orc", "Troll", "Warrior"}, "Mulgore": {"Horde", "Tauren", "Warrior"},
          "Tirisfal Glades": {"Horde", "Undead", "Warrior"}}


def parts(texts):
    """{(group, name): (start level, body)} of every guide part in these files."""
    out = {}
    for text in texts:
        for chunk in text.split("RXPGuides.RegisterGuide(")[1:]:
            name = re.search(r"^#name\s+(.+?)\s*$", chunk, re.M)
            if not name:
                continue
            level = re.match(r"(\d+)-", name.group(1))
            for group in re.findall(r"^#group\s+(.+?)\s*$", chunk, re.M):
                out.setdefault((group.split("<<")[0].strip(), name.group(1)), (int(level.group(1)) if level else 0, chunk))
    return out


def _next(body, me, group, known):
    """The next part's name for `me`: the first "#next" line whose tag fits, then the first of its ";" options that exists."""
    for line in re.findall(r"^#next\s+(.+?)\s*$", body, re.M):
        names, _, tag = line.partition("<<")
        if not for_me(tag, me):
            continue
        for name in names.split(";"):
            name = name.strip()
            if (group, name) in known:
                return name
            # "#next Razorfen Downs" names the part "38-38 Razorfen Downs" without its levels
            for g, n in known:
                if g == group and re.sub(r"^\d+-\d+\s+", "", n) == name:
                    return n
    return None


def chain(known, group, first, me, limit=80):
    """Names of the parts from `first`, following "#next" for `me`."""
    out, name = [], first
    while name and (group, name) in known and name not in out and len(out) < limit:
        out.append(name)
        name = _next(known[(group, name)][1], me, group, known)
    return out


def _point(cont, a, b):
    return [int(cont), round(float(b), 2), round(float(a), 2)]  # <map>/<continent>,<world y>,<world x>


def events(body, level, me, dungeons=False):
    """Events of one guide part for `me`, in order. dungeons: also the steps for picked dungeons (".dungeon X"),
    else the ones for dungeons off (".dungeon !X")."""
    out = []
    pieces = re.split(r"^(\s*step\b.*)$", body, flags=re.M)
    for header, step in zip(pieces[1::2], pieces[2::2]):
        tag = header.split("<<", 1)[1] if "<<" in header else ""
        if not for_me(tag, me):
            continue  # #optional steps stay: the route keeps every RestedXP step (user, 2026-11-26)
        marks = re.findall(r"^\s*\.dungeon\s+(\S+)", step, re.M)
        if any(not m.startswith("!") for m in marks) and not dungeons:
            continue
        if any(m.startswith("!") for m in marks) and dungeons:
            continue
        point, found = None, []
        for line in step.splitlines():
            t = line.strip()
            m = GOTO.match(t)
            if m:
                point = point or _point(*m.groups())
                continue
            m = EVENT.match(t)
            if m:
                found.append([m.group(1), int(m.group(2)), int(m.group(3) or 0)])
                continue
            m = XP.match(t)
            if m:
                level = max(level, int(m.group(1)))
            elif t.startswith(".fly"):
                found.append(["fly", 0, 0])
            elif t.startswith(".hs"):
                found.append(["hearth", 0, 0])
            elif HOME.match(t):
                found.append(["home", 0, 0])
            elif t.startswith(".zone ") and not found:
                found.append(["travel", 0, 0])
        if not found and point:
            found.append(["travel", 0, 0])
        for kind, qid, goal in found:
            out.append([kind, qid, goal] + (point or [None, None, None]) + [level])
    return out, level


def route_events(known, start, dungeons=False):
    """Every event of our route for this start: the guide chain from its first part, main or dungeon guide."""
    me, group = STARTS[start], DUNGEON if dungeons else MAIN
    out = []
    for name in chain(known, group, FIRST_PART[start], me):
        level, body = known[(group, name)]
        found, _ = events(body, level, me, dungeons)
        out += found
    return out


# ---- RestedXP steps kept whole (user, 2026-11-27: guide "at 100%" like RestedXP's own engine) ----
# Every line of a step that RestedXP's engine acts on, with its raw arguments (GuideLoader.lua parseLine): the addon's
# step engine (Guide.lua) reads them the way RestedXP's functions.lua does. Guide text is not kept, except the "+"
# lines, which are steps you tick by hand.
KEPT = {"accept", "turnin", "complete", "goto", "waypoint", "xp", "fly", "hs", "home", "bindlocation", "fp", "deathskip",
        "collect", "itemcount", "train", "trainer", "vendor", "use", "abandon", "cast", "equip", "destroy", "zone",
        "subzone", "zoneskip", "subzoneskip", "isOnQuest", "isNotOnQuest", "isQuestTurnedIn", "isQuestAvailable",
        "isQuestComplete", "isQuestNotComplete", "money", "maxlevel", "skill", "itemStat", "cooldown", "aura", "explore",
        "target", "mob", "unitscan", "skipgossip", "skipgossipid", "bankdeposit", "bankwithdraw", "stable", "istrained"}
# Step filters with RestedXP's defaults on Forever (RXPGuides.lua stepLogic): hardcore off, hardcore server off, solo
# self-found off, season 0 (no Season of Mastery), phase 6, xp rate 1, group quests off.
POINT = re.compile(r"^(\d+)/(\d+)$")


def _season_ok(value):
    return any(s == "0" for s in re.findall(r"[^,;\s]+", value or ""))


def _phase_ok(value):
    m = re.match(r"(\d+)-(\d+)", value or "")
    lo, hi = (int(m.group(1)), int(m.group(2))) if m else (int(value) if (value or "").isdigit() else 0, 0xffff)
    return lo <= 6 <= hi


def _xprate_ok(value):
    m = re.match(r"^([<>]?)\s*(\d+\.?\d*)-?(\d*\.?\d*)", value or "")
    if not m:
        return True
    op, a, b = m.groups()
    lo, hi = (0, float(a) - 1e-4) if op == "<" else (float(a) + 1e-4, 0xfff) if op == ">" else (float(a), float(b) if b else 0xfff)
    return lo <= 1 <= hi


def _shown(tags):
    """RestedXP's IsStepShown for the step tags (#name value) with Forever's default settings."""
    if "hardcore" in tags or "hardcoreserver" in tags or "ssf" in tags or "som" in tags or "group" in tags:
        return False
    if "season" in tags and not _season_ok(tags["season"]):
        return False
    if "phase" in tags and not _phase_ok(tags["phase"]):
        return False
    return "xprate" not in tags or _xprate_ok(tags["xprate"])


def _args(tag, raw):
    if tag in ("goto", "waypoint"):
        parts_ = [a.strip() for a in raw.split(",")]
        m = POINT.match(parts_[0]) if parts_ else None
        if not m or len(parts_) < 3:
            return None
        try:
            point = _point(m.group(2), parts_[1], parts_[2])
            radius = float(parts_[3]) if len(parts_) > 3 and parts_[3] != "" else None
        except ValueError:
            return None
        return point + [radius, len(parts_) > 4 and parts_[4] != "", int(m.group(1))]  # map id last: the zone RestedXP names
    return [a for a in re.sub(r"\s*,\s*", ",", raw.strip()).split(",") if a != ""]


def step_lines(body):
    """RestedXP's line number of each step (GuideLoader.lua: the guide text after "[[", non-empty lines counted from 1;
    a step's id is that number plus the guide's id), in order."""
    text = body.split("[[", 1)[1] if "[[" in body else body
    out, n = [], 0
    for line in re.split(r"[\r\n]+", text):
        if line == "":
            continue
        n += 1
        if line.strip()[:4] == "step":
            out.append(n)
    return out


def steps(body, level, part=0, name=""):
    """The RestedXP steps of one guide part, whole. Each: {p, part, lv, tag, label, cw, req, sticky, loop, optional, ln, e}
    with e = [[tag, args, line tag, RestedXP's text]]; text-only lines (">>text", "*text") are ["text", [text], line tag].
    Class and race tags stay (the game judges them for the player). User, 2026-11-27: the guide shows RestedXP's own
    text (CC BY-NC-SA 4.0, credit in LICENSE-DATA.md); ln = RestedXP's line number (its step id)."""
    lines_at = step_lines(body)
    body = re.sub(r"--[^\r\n]*", "", body)
    out = []
    pieces = re.split(r"^(\s*step\b.*)$", body, flags=re.M)
    headers = pieces[1::2]
    numbered = len(headers) == len(lines_at)
    for k, (header, text) in enumerate(zip(headers, pieces[2::2])):
        tag = header.split("<<", 1)[1].strip() if "<<" in header else ""
        st = {"p": part, "part": name, "tag": tag, "e": []}
        if numbered:
            st["ln"] = lines_at[k]
        tags = {}
        for line in text.splitlines():
            t = line.strip()
            if not t:
                continue
            ltag = ""
            if "<<" in t:
                t, ltag = t.split("<<", 1)
                t, ltag = t.strip(), ltag.strip()
            m = re.match(r"^#(\S+)\s*(.*)$", t)
            if m:
                tags.setdefault(m.group(1), m.group(2).strip())
                continue
            if t.startswith("+"):
                st["e"].append(["note", [t[1:].strip()], ltag])
                continue
            if t.startswith("*") or t.startswith(">>"):
                said = t[1:] if t.startswith("*") else t[2:]
                if said.strip():
                    st["e"].append(["text", [said.strip()], ltag])
                continue
            m = re.match(r"^\.(\S+)\s*(.*)$", t)
            if not m:
                continue
            etag, raw = m.group(1), m.group(2).split(">>", 1)[0]
            said = m.group(2).split(">>", 1)[1].strip() if ">>" in m.group(2) else ""
            if etag == "group":
                tags["group"] = ""
            elif etag == "dungeon":
                tags.setdefault("dungeon", raw.strip())
            elif etag in KEPT:
                args = _args(etag, raw)
                if args is not None:
                    st["e"].append([etag, args, ltag] + ([said] if said else []))  # RestedXP's text for the line
        if not _shown(tags):
            continue
        for e in st["e"]:
            if e[0] == "xp" and not e[2] and len(e[1]) == 1:  # a reach-level step raises the route's level from here
                lv = re.match(r"(\d+)", e[1][0])
                level = max(level, int(lv.group(1))) if lv and not e[1][0].startswith("<") else level
        st["lv"] = level
        st["step_level"] = int(tags["level"]) if tags.get("level", "").isdigit() else 0
        for key, flag in (("completewith", "cw"), ("requires", "req"), ("label", "label")):
            if key in tags:
                st[flag] = tags[key]
        st["sticky"] = "sticky" in tags or "completewith" in tags
        st["loop"] = "loop" in tags
        st["optional"] = "optional" in tags
        if "dungeon" in tags:
            st["dungeon"] = tags["dungeon"]
        if "include" in tags:
            st["include"] = tags["include"]
        out.append(st)
    return out, level


def route_steps(known, start, dungeons=False):
    """Every RestedXP step of our route for this start, part after part ("#next"), dungeon guide or main guide.
    "#include group\name" steps are replaced by that part's steps (RestedXP's ProcessSteps)."""
    me, group = STARTS[start], DUNGEON if dungeons else MAIN
    out, level = [], 1

    def expand(name, grp, index, level, depth=0):
        lv, body = known[(grp, name)]
        found, level = steps(body, max(level, lv), part=index, name=name)
        result = []
        for st in found:
            inc = st.get("include")
            if inc and depth < 3:
                g, _, n = inc.partition("\\")
                if (g.strip(), n.strip()) in known:
                    sub, level = expand(n.strip(), g.strip(), index, level, depth + 1)
                    result += sub
                continue
            d = st.get("dungeon")
            if d and (d.startswith("!") == dungeons):  # ".dungeon X" only with dungeons on, ".dungeon !X" only with them off
                continue
            result.append(st)
        return result, level

    for index, name in enumerate(chain(known, group, FIRST_PART[start], me)):
        found, level = expand(name, group, index, level)
        sub = re.search(r"^#subgroup\s+(.+?)\s*$", known[(group, name)][1], re.M)
        for st in found:
            st["part"] = name
            st["sub"] = sub.group(1) if sub else ""
        out += found
    return out


def spirit_healers(text):
    """RestedXP's Spirit Healer list (DB/forever/SpiritHealerDB.lua): [[continent, world x, world y, name]], the same
    world point order as our route points (map.lua points a ghost on a death-skip step at the nearest one)."""
    out, cont = [], None
    for line in text.splitlines():
        m = re.match(r"^\s*\[(\d+)\]\s*=\s*\{", line)
        if m:
            cont = int(m.group(1))
            continue
        m = re.search(r"wx\s*=\s*(-?[\d.]+),\s*wy\s*=\s*(-?[\d.]+),\s*name\s*=\s*\"([^\"]*)\"", line)
        if m and cont is not None:
            out.append([cont, float(m.group(1)), float(m.group(2)), m.group(3).strip()])
    return out
