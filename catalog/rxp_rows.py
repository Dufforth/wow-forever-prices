"""RestedXP steps whole (catalog/rxp_chain.py route_steps) as our route: rows to show plus the step records the
addon's step engine runs on (Guide.lua, like RestedXP's GuideWindow.lua SetStep / UpdateStepCompletion and the element
handlers in functions.lua). User, 2026-11-27: the guide follows RestedXP "at 100%".

Rows: one per element you act on, [kind, quest, zone, x, y, level, text, goal, dest, nil, step, arg]; arg holds what the
engine needs (flags, ids, the line's class/race tag "lt").
Step records: {p part, t tag, lv level gate, s sticky, cw completewith step, req requires step, loop, a/b first/last row,
c conditions, pt points, tg targets, mob monsters, us rare monsters (.unitscan), gs gossip skip, dz death skip,
ln RestedXP's line number (its step id), x text-only lines [[rows before it, text, line tag]]}.
RestedXP's text is kept as written (user, 2026-11-27: "look the same"): a line's own text in arg "rt", text-only lines
in the record's x; a line RestedXP shows no text for (a .goto, .use, .train or .cast without ">>") has arg h = 1.
Source and licence: RestedXP Guides, CC BY-NC-SA 4.0 (see LICENSE-DATA.md).
"""
import re

from route_from_rxp import _do_text

CONDITIONS = {"isOnQuest", "isNotOnQuest", "isQuestTurnedIn", "isQuestAvailable", "isQuestComplete", "isQuestNotComplete",
              "zoneskip", "subzoneskip", "money", "maxlevel", "itemStat", "cooldown", "itemcount", "istrained"}
# Point kinds: 0 stop (done on arrival), 1 walk-through (the arrow moves on), 2 low priority, 3 arrow only, 4 pin only,
# 5 waypoint (arrow, no pin)
STOP, THROUGH, LOW, ARROW, PIN, WAYPOINT = 0, 1, 2, 3, 4, 5


def _int(v, default=0):
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return default


def point_kind(tag, radius, optional):
    if tag == "waypoint":
        return WAYPOINT
    if optional:
        return THROUGH if radius and radius > 0 else LOW if radius == 0 else ARROW
    if radius is None:
        return ARROW
    return STOP if radius > 0 else PIN


def rows_from_steps(steps, by_id, where, stub=None, names=None):
    """Returns (rows, records, stats). names = {"map": {id: zone}, "area": {id: name}} for zone and area ids."""
    names = names or {}
    maps, areas, items = names.get("map", {}), names.get("area", {}), names.get("item", {})
    rows, records, stats = [], [], {"unknown": 0, "no_place": 0}
    # A .goto's own map (1440/1 = Ashenvale) names the zone of its point where zone maps overlap (2026-11-27: an
    # Ashenvale point came out as "Go to Azshara"); on(zone, point) places a world point on that zone's map.
    on = names.get("on")
    if on:
        hints = {}
        for st in steps:
            for e in st["e"]:
                if e[0] in ("goto", "waypoint") and len(e[1]) > 5 and maps.get(e[1][5]):
                    hints.setdefault(tuple(e[1][:3]), maps[e[1][5]])
        by_bounds = where

        def where(point):
            zone = hints.get(point) if point is not None else None
            return (zone and on(zone, point)) or by_bounds(point)
    zone_now = ["?"]
    labels = {}
    for n, st in enumerate(steps, 1):
        if st.get("label"):
            labels.setdefault((st["p"], st["label"]), n)

    def resolve(st, n, label):
        if not label:
            return None
        return n + 1 if label == "next" else labels.get((st["p"], label))

    def quest(qid, level):
        q = by_id.get(qid)
        if qid and not q:
            stats["unknown"] += 1
            q = by_id[qid] = stub(qid, level) if stub else None
        return q

    def next_point(i):
        for st in steps[i:]:
            for e in st["e"]:
                if e[0] in ("goto", "waypoint"):
                    return tuple(e[1][:3])
        return None

    for n, st in enumerate(steps, 1):
        level = st["lv"]
        rec = {"p": st["p"]}
        if st.get("ln"):
            rec["ln"] = st["ln"]
        said_lines = []
        for key, flag in (("tag", "t"), ("step_level", "lv")):
            if st.get(key):
                rec[flag] = st[key]
        if st.get("sticky"):
            rec["s"] = 1
        if st.get("loop"):
            rec["loop"] = 1
        for key in ("cw", "req"):
            r = resolve(st, n, st.get(key))
            if r:
                rec[key] = r
        here = next((tuple(e[1][:3]) for e in st["e"] if e[0] in ("goto", "waypoint")), None)
        w = where(here) if here else None
        if w:
            zone_now[0] = w[0]
        conds, points, targets, mobs, scans = [], [], [], [], []
        last = [None]
        start = len(rows) + 1

        said = [None]

        def row(kind, qid=0, text="", goal=0, dest=None, arg=None, point=None, lt="", hidden=False):
            p = where(tuple(point)) if point else w
            d = where(tuple(dest)) if dest else None
            a = {k: v for k, v in (arg or {}).items() if v not in (None, 0, "", [])}
            if lt:
                a["lt"] = lt
            if said[0]:
                a["rt"] = said[0]
            elif hidden:
                a["h"] = 1
            rows.append([kind, qid, p[0] if p else zone_now[0], round(p[1], 1) if p else None, round(p[2], 1) if p else None, level,
                         text, goal, [d[0], round(d[1], 1), round(d[2], 1)] if d else None, None, n, a or None])
            last[0] = len(rows)
            if qid and not p:
                stats["no_place"] += 1

        for e in st["e"]:
            tag, args, lt, text_on = e[0], e[1], e[2], len(e) > 3
            said[0] = e[3] if len(e) > 3 and isinstance(e[3], str) else None
            made = len(rows)
            if tag == "text":
                said_lines.append([len(rows) - start + 1, args[0], lt])
                continue
            if tag in ("goto", "waypoint"):
                pw = where(tuple(args[:3]))
                if not pw:
                    continue
                kind = point_kind(tag, args[3], args[4])
                if kind == STOP:
                    row("goto", text=f"Go to {pw[0]}", point=args[:3], lt=lt, hidden=True)
                # [zone, x, y, radius yards, kind, line tag, parent row (RestedXP: the objective it belongs to)]
                points.append([pw[0], round(pw[1], 2), round(pw[2], 2), args[3] if args[3] and args[3] > 0 else None, kind, lt,
                               len(rows) if kind == STOP else last[0]])
            elif tag == "accept":
                qid = _int(args[0])
                q = quest(qid, level)
                row("accept", qid, f"Accept {q.title if q else qid}",
                    arg={"f": _int(args[1]) if len(args) > 1 else 0, "r": _int(args[2]) if len(args) > 2 else 0}, lt=lt)
            elif tag == "turnin":
                qid = _int(args[0])
                q = quest(abs(qid), level)
                rew = _int(args[1]) if len(args) > 1 else 0
                row("turnin", abs(qid), f"Turn in {q.title if q else abs(qid)}",
                    arg={"m": 1 if qid < 0 else 0, "i": 1 if qid < 0 and rew > 0 else 0}, lt=lt)
            elif tag == "complete":
                qid = _int(args[0])
                q = quest(abs(qid), level)
                obj, objmax, flags = (_int(args[i]) if len(args) > i else 0 for i in (1, 2, 3))
                goals = q.goals if q else []
                text = _do_text(q, goals[obj - 1]) if q and 0 < obj <= len(goals) else f'Finish "{q.title if q else abs(qid)}"'
                row("do", abs(qid), text, obj, arg={"x": objmax, "t": flags % 2, "m": 1 if qid < 0 else 0}, lt=lt)
            elif tag == "xp":
                m = re.search(r"(<?)\s*(\d+)([+.\-]?\d*\.?\d*)", args[0].replace(" ", "")) if args else None
                if not m:
                    continue
                op, lv, extra = m.groups()
                a = {"l": int(lv), "rv": 1 if op == "<" else 0}
                if extra and extra not in ("+", "-", "."):
                    a["x"] = float(extra)
                skip = len(args) > 1 and re.match(r"^-?\d+$", args[1])
                if skip:
                    if _int(args[1]) < 0:
                        a["rv"] = 1 - a["rv"]
                    conds.append(["xp", a, lt])
                else:
                    row("grind", text=f"Grind to level {lv}", arg=a, lt=lt)
            elif tag == "fly":
                loc = args[0] if args else ""
                row("fly", text=f"Fly to {loc}", dest=next_point(n), arg={"n": loc}, lt=lt)
            elif tag == "hs":
                row("hearth", text="Use your Hearthstone", dest=next_point(n), lt=lt)
            elif tag == "home":
                area = areas.get(_int(args[0])) if args else None
                row("home", text=f"Set your Hearthstone at {area or 'the inn'}", arg={"a": area, "ai": _int(args[0]) if args else 0}, lt=lt)
            elif tag == "bindlocation":
                area = areas.get(_int(args[0])) if args else None
                if area:
                    conds.append(["bindlocation", {"a": area, "ai": _int(args[0]), "rv": _int(args[1]) % 2 if len(args) > 1 else 0}, lt])
            elif tag == "fp":
                loc = args[0] if args else ""
                row("flight", text=f"Get the {loc} flight path", arg={"n": loc, "t": 1 if len(args) > 1 and _int(args[1]) % 2 else 0}, lt=lt)
            elif tag == "deathskip":
                rec["dz"] = 1
                row("deathskip", text="Die and respawn at the Spirit Healer", lt=lt)
            elif tag == "collect":
                item = _int(args[0])
                flags = _int(args[4]) if len(args) > 4 else 0
                a = {"i": item, "n": _int(args[1], 1) if len(args) > 1 else 1, "q": _int(args[2]) if len(args) > 2 else 0,
                     "o": _int(args[3]) if len(args) > 3 else 0, "f": 3 if flags < 0 else flags, "has": 1}
                nm = items.get(item)
                if nm:
                    a["nm"] = nm
                row("collect", text=nm or "", arg=a, lt=lt)
            elif tag == "train":
                spell, flags = _int(args[0]), (_int(args[1]) if len(args) > 1 else 0)
                a = {"s": spell, "rv": 1 if flags & 2 else 0}
                if flags & 1:
                    conds.append(["train", a, lt])  # text only: the step is skipped once you know it
                else:
                    row("train", text="", arg=a, lt=lt, hidden=True)
            elif tag in ("trainer", "vendor", "stable"):
                row(tag, text={"trainer": "Visit the trainer", "vendor": "Visit the vendor", "stable": "Visit the stable master"}[tag],
                    arg={"npc": _int(args[0]) if args else 0}, lt=lt)
            elif tag == "use":
                row("use", text="", arg={"i": _int(args[0]) if args else 0, "t": 1}, lt=lt, hidden=True)
            elif tag == "abandon":
                ids = [abs(_int(a)) for a in args if _int(a)]
                titles = [(quest(qid, level) or None) for qid in ids]
                title = titles[0].title if titles and titles[0] else ""
                row("abandon", ids[0] if ids else 0, f"Abandon {title}".strip(), arg={"q": ids}, lt=lt)
            elif tag == "cast":
                row("cast", text="", arg={"s": [_int(a) for a in args if _int(a)]}, lt=lt, hidden=True)
            elif tag in ("equip", "aura"):
                if text_on:  # RestedXP: a line without text is text only
                    row(tag, text=f"{tag.title()} {args[-1] if args else ''}", arg={"v": [_int(a) for a in args]}, lt=lt)
            elif tag == "destroy":
                nm = items.get(_int(args[0]) if args else 0)
                row("destroy", text=f"Throw away {nm} from your bags" if nm else "Throw away an item from your bags",
                    arg={"i": _int(args[0]) if args else 0}, lt=lt)
            elif tag in ("zone", "subzone", "explore"):
                nm = (maps if tag == "zone" else areas).get(_int(args[0]), args[0] if args else "?")
                row("zone" if tag == "zone" else "subzone", text=f"Go to {nm}",
                    arg={"z": nm, "id": _int(args[0]) if args else 0, "f": _int(args[1]) if len(args) > 1 else 0}, lt=lt)
            elif tag in ("bankdeposit", "bankwithdraw"):
                row("bank", text="Visit the bank", lt=lt)
            elif tag == "note":
                row("note", text=args[0], lt=lt)
            elif tag in ("target", "mob", "unitscan"):  # .unitscan: rare mobs RestedXP plays a sound for
                {"target": targets, "mob": mobs, "unitscan": scans}[tag].extend(a for a in args if not a.isdigit())
            elif tag in ("skipgossip", "skipgossipid"):
                ids = [_int(a) for a in args if re.match(r"^-?\d+$", a)]
                rec["gs"] = ids or 1  # RestedXP's arguments: npc id and gossip options to pick in turn
            elif tag == "skill":
                if len(args) > 2:  # with skipstep: a condition
                    conds.append(["skill", {"v": args}, lt])
            elif tag in CONDITIONS:
                c = {"v": args}
                if tag == "zoneskip" and args:
                    c["z"] = [maps.get(_int(z), z) for z in re.split(r"[+/]", args[0])]
                elif tag == "subzoneskip" and args:
                    c["z"] = [areas.get(_int(args[0]), args[0])]
                conds.append([tag, c, lt])
            if said[0] and len(rows) == made:  # RestedXP shows the text of a line we keep no row for (a walk-through point, a condition)
                said_lines.append([len(rows) - start + 1, said[0], lt])
        if len(rows) >= start:
            rec["a"], rec["b"] = start, len(rows)
        for key, val in (("c", conds), ("pt", points), ("tg", targets), ("mob", mobs), ("us", scans), ("x", said_lines)):
            if val:
                rec[key] = val
        records.append(rec)
    # A non-sticky step that needs a sticky one without completewith ends that sticky step (GuideWindow.lua 1984).
    for n, rec in enumerate(records, 1):
        r = rec.get("req")
        if r and not rec.get("s") and 0 < r <= len(records) and records[r - 1].get("s") and not records[r - 1].get("cw"):
            records[r - 1]["cw"] = n
    return rows, records, stats
