"""Forever's own quests, recorded in game by the addon (user, 2026-11-14): Forever's public data lists only their
numbers, so the addon writes down who gave each one and where, its objectives with the spots where they progressed,
and who took it back and where. tools/import_recorded_quests.py turns the saved file into
catalog/forever_quests.json; this module turns that into route quests.

forever_quests.json: [{id, title, level, xp, giver: {name, zone, x, y}, turnIn: {name, zone, x, y},
                       objectives: [{text, kind, count, spots: [[zone, x, y], ...]}]}] (map %).
"""
import json

from route_model import Goal, Quest
from route_score import world


def _point(boxes, place):
    """A place as a world point: {"world": [continent, x, y]} (RestedXP), or {"zone", "x", "y"} in map % (recorded)."""
    if not place:
        return None
    if place.get("world"):
        c, x, y = place["world"]
        return (int(c), float(x), float(y))
    return world(boxes, place.get("zone"), place.get("x"), place.get("y"))


def to_quest(row, boxes):
    """One recorded quest as a route Quest, or None when its giver or hand-in has no place."""
    start, end = _point(boxes, row.get("giver")), _point(boxes, row.get("turnIn"))
    if not start or not end:
        return None
    goals = []
    for o in row.get("objectives", []):
        spots = [p for p in ((int(s[0]), float(s[1]), float(s[2])) if isinstance(s[0], int) else world(boxes, *s)
                             for s in o.get("spots", [])) if p and p[0] == start[0]]
        point = (start[0], sum(p[1] for p in spots) / len(spots), sum(p[2] for p in spots) / len(spots)) if spots else start
        kind = {"monster": "kill", "item": "collect", "object": "use"}.get(o.get("kind"), "kill")
        count = int(o.get("count") or 0) or (8 if kind == "kill" else 6 if kind == "collect" else 1)  # guides don't say: typical
        goals.append(Goal(kind, o.get("text") or "the objective", point, count, float(row.get("level") or 1), guessed=not spots))
    level = int(row.get("level") or 1)
    return Quest(int(row["id"]), row.get("title", "?"), level, max(1, level - 4), start, row["giver"].get("name", "?"),
                 end, row["turnIn"].get("name", "?"), goals, int(row.get("xp") or 0))


HORDE_RACES = 2 | 16 | 32 | 128


def load_rxp(path, boxes, known_ids=(), xp_by_level=None, side="H"):
    """Forever's own quests from RestedXP's Forever guides (tools/extract_rxp_forever.py, CC BY-NC-SA 4.0): the ones
    for `side` (or both factions) with a level, a pick-up and a hand-in. Their experience isn't in the guides: the
    median of Classic quests of the same level (xp_by_level) stands in."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    known, out = set(known_ids), []
    for row in data.get("quests", []):
        if row.get("side") not in (side, "both") or not row.get("level") or int(row["id"]) in known:
            continue
        level = int(row["level"]) + 1  # the guide part's first level: its quests sit about a level above
        row = dict(row, level=level, xp=(xp_by_level or {}).get(level, 0))
        row.setdefault("giver", {}).setdefault("name", "")
        row.setdefault("turnIn", {}).setdefault("name", "")
        q = to_quest(row, boxes)
        if q:
            q.races = HORDE_RACES if side == "H" else 0
            q.start_name = q.start_name or "the quest giver"
            q.end_name = q.end_name or "the quest giver"
            out.append(q)
    return out


def load_recorded(path, boxes, known_ids=()):
    """Recorded quests not already in the Classic data; [] when nothing was recorded yet."""
    try:
        rows = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    known = set(known_ids)
    out = []
    for row in rows:
        if int(row.get("id", 0)) in known:
            continue
        q = to_quest(row, boxes)
        if q:
            out.append(q)
    return out
