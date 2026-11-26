"""RestedXP's Forever leveling guide as scored steps, for the 1-60 scorecard (user, 2026-11-24: "extend to 60").

Source and licence: RestedXP Guides (https://github.com/RestedXP/RXPGuides), Guides/forever/RestedXP-Skyborne.lua,
CC BY-NC-SA 4.0. Only what the scorecard needs is kept: each step's kind, quest number, first map point and the level
the guide is at (tools/extract_rxp_route.py writes catalog/rxp_forever_route.json). No guide text, tips or order of
the guide's own words is copied.

A step is [kind, quest, continent, world x, world y, level, "", "", dest]: the scorecard (route_score.score) takes a
continent number in the zone field as a world point.
"""
import json
import re

from route_score import XP_TABLE, score

MAIN_HORDE = "RestedXP Forever Guide (H)"
BANDS = [(22, 30), (30, 40), (40, 50), (50, 60)]
ORC_WARRIOR = {"Horde", "Orc", "Warrior"}

GOTO = re.compile(r"^\.goto\s+\d+/(\d+),\s*(-?\d+(?:\.\d+)?)[\d.]*,\s*(-?\d+(?:\.\d+)?)")
EVENT = re.compile(r"^\.(accept|turnin|complete)\s+(\d+)")
XP = re.compile(r"^\.xp\s+<?\s*(\d+)")


def for_me(tag, me):
    """Whether a step tag ("Horde Shaman", "Mage/Warrior", "!Skyborne") applies to a character with these words.
    Alternatives are split by "/"; in one, every plain word must be yours and no "!word" may be."""
    tag = tag.strip()
    if not tag:
        return True
    for alternative in tag.split("/"):
        words = alternative.split()
        if words and all((w[1:] not in me) if w.startswith("!") else (w in me) for w in words):
            return True
    return False


def _point(cont, a, b):
    # RestedXP writes <map>/<continent>,<world y>,<world x>; tools/extract_rxp_forever.py keeps (continent, x, y) too.
    return [int(cont), round(float(b), 2), round(float(a), 2)]


def _part_level(chunk):
    m = re.search(r"^#name\s+(\d+)-", chunk, re.M)
    return int(m.group(1)) if m else 0


def parse_guide(text, group=MAIN_HORDE, me=ORC_WARRIOR, from_level=20):
    """Steps of every guide part in `group` starting at `from_level` or later, in file order, that apply to `me`.
    (The group also holds the Zephras Isle start, 1-13, for Forever's Skyborne race only.)"""
    out, last = [], None
    pending = []  # fly/hearth steps waiting for the next point (where they land)
    for chunk in text.split("RXPGuides.RegisterGuide(")[1:]:
        groups = [g.strip() for g in re.findall(r"^#group\s+(.+?)\s*$", chunk, re.M)]
        if group not in [g.split("<<")[0].strip() for g in groups]:
            continue
        level = _part_level(chunk)
        if level < from_level:
            continue
        pieces = re.split(r"^(\s*step\b.*)$", chunk, flags=re.M)
        for header, body in zip(pieces[1::2], pieces[2::2]):
            tag = header.split("<<", 1)[1] if "<<" in header else ""
            if not for_me(tag, me) or re.search(r"^\s*#optional", body, re.M):
                continue
            # ".dungeon WC": only when you pick that dungeon; the guides run with dungeons off (#disabledungeons),
            # like our no-dungeon routes. ".dungeon !WC" steps are the ones for dungeons off: kept.
            if re.search(r"^\s*\.dungeon\s+[^!\s]", body, re.M):
                continue
            point, events, travel = None, [], None
            for line in body.splitlines():
                t = line.strip()
                m = GOTO.match(t)
                if m and point is None:
                    point = _point(*m.groups())
                    continue
                m = EVENT.match(t)
                if m:
                    events.append((m.group(1), int(m.group(2))))
                    continue
                m = XP.match(t)
                if m:
                    level = max(level, int(m.group(1)))
                    continue
                if t.startswith(".fly"):
                    travel = "fly"
                elif t.startswith(".hs"):
                    travel = "hearth"
            if point is not None:
                for step in pending:  # a flight or hearth lands where the next point is
                    step[8] = list(point)
                pending = []
                last = point
                for kind, qid in events or [("goto", 0)]:
                    out.append([kind, qid, point[0], point[1], point[2], level, "", "", None])
            if travel and last is not None:  # taken from where you stand (this step's point, else the last one)
                step = [travel, 0, last[0], last[1], last[2], level, "", "", None]
                out.append(step)
                pending.append(step)
    # A quest is picked up, done and handed in once: the guide repeats some events in "#completewith" and
    # alternative steps, and counting them again gave RestedXP experience it never earns.
    seen, kept = set(), []
    for s in out:
        if s[0] in ("fly", "hearth") and not s[8]:
            continue
        if s[1] and (s[0], s[1]) in seen and s[0] != "complete":
            continue
        seen.add((s[0], s[1]))
        kept.append(s)
    return kept


def load_steps(path):
    try:
        return json.loads(path.read_text(encoding="utf-8")).get("steps", [])
    except (OSError, ValueError):
        return []


def _paced(card, need):
    """Hours to earn `need` experience at this route's pace in the band. A guide's level labels don't always match
    the experience the model gives it (RestedXP's steps earn about 40% more than the band needs), so raw band hours
    reward whoever does fewer quests; experience per hour is the fair measure."""
    rate = card["xp"] / (card["hours"] - card["grind_hours"]) if card["hours"] > card["grind_hours"] and card["xp"] else 0
    card["xp_per_hour"] = int(rate)
    card["paced_hours"] = round(need / rate, 2) if rate else card["hours"]
    return card


def band_table(ours, theirs, quests, boxes, bands=BANDS, class_bit=1):
    """Our route against RestedXP's, band by band, with the same time model: raw hours, experience per hour, and
    hours to earn the band's experience at each route's pace ("paced"); "faster" compares paced hours."""
    rows = []
    for start, end in list(bands) + [(bands[0][0], bands[-1][1])]:
        need = sum(XP_TABLE[start - 1:end - 1])
        a = _paced(score(ours, quests, boxes, end, class_bit=class_bit, start=start), need)
        b = _paced(score(theirs, quests, boxes, end, class_bit=class_bit, start=start), need)
        rows.append({"band": f"{start}-{end}", "need_xp": need, "ours": a, "rxp": b,
                     "faster": "ours" if a["paced_hours"] <= b["paced_hours"] else "rxp",
                     "diff": round(a["paced_hours"] - b["paced_hours"], 2)})
    return rows


def band_text(rows):
    return "; ".join(f"{r['band']}: ours {r['ours']['paced_hours']} h ({r['ours']['xp_per_hour']} xp/h) vs RestedXP "
                     f"{r['rxp']['paced_hours']} h ({r['rxp']['xp_per_hour']} xp/h) ({r['diff']:+.2f})" for r in rows)
