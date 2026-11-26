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
        if not for_me(tag, me) or re.search(r"^\s*#optional", step, re.M):
            continue
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
