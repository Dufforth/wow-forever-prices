"""Our route rows from RestedXP's event chain (catalog/rxp_chain.py), exactly: one row per guide event, in the
guide's order, nothing added and nothing left out (user, 2026-11-26: "follow exact same steps, hubs and everything").

Places: RestedXP's own map point only. A step without one has no waypoint (it keeps the zone of the step before).
A quest our data doesn't know keeps its step with a stub quest (made by `stub`), so the addon still shows it.
Rows are [kind, quest, zone, x, y, level, text, goal, dest], like the planner's.
"""


def _do_text(q, goal):
    verb = {"kill": f"Kill {goal.count} {goal.name}", "collect": f"Collect {goal.name}" + (f" (about {goal.count} kills)" if goal.mob_level else ""),
            "use": f"Use {goal.name}", "explore": "Explore the area"}.get(goal.kind, goal.name)
    return f'{verb} for "{q.title}"'


def _accept_text(q):
    if q.start_drop:
        item, mob, chance = q.start_drop
        return f'Loot {item} from {mob} ({chance:.0f}%), then right-click it to start "{q.title}"'
    return f'Accept "{q.title}" from {q.start_name}'


def rows_from_events(events, by_id, where, stub=None):
    """Returns (rows, stats). stub(qid, level) -> Quest for a quest `by_id` doesn't hold (it's added to `by_id`)."""
    rows, stats = [], {"unknown": 0, "no_place": 0}
    level, zone_now = 1, "?"

    def row(kind, qid, point, text, goal=0, dest=None):
        nonlocal zone_now
        w = where(tuple(point)) if point else None
        d = where(tuple(dest)) if dest else None
        if w:
            zone_now = w[0]
        rows.append([kind, qid, w[0] if w else zone_now, round(w[1], 1) if w else None, round(w[2], 1) if w else None, level, text,
                     goal, [d[0], round(d[1], 1), round(d[2], 1)] if d else None])

    def next_point(i):
        for e in events[i + 1:]:
            if e[3] is not None:
                return (e[3], e[4], e[5])
        return None

    for i, e in enumerate(events):
        kind, qid, goal_no, here, lv = e[0], e[1], e[2], ((e[3], e[4], e[5]) if e[3] is not None else None), e[6]
        level = max(level, lv)
        q = by_id.get(qid) if qid else None
        if qid and not q:
            stats["unknown"] += 1
            q = by_id[qid] = stub(qid, level) if stub else None
        if qid and here is None:
            stats["no_place"] += 1
        title = q.title if q else f"quest {qid}"
        if kind == "accept":
            row("accept", qid, here, _accept_text(q) if q and q.start_name else f'Accept "{title}"')
        elif kind == "complete":
            goals = q.goals if q else []
            row("do", qid, here, _do_text(q, goals[goal_no - 1]) if 0 < goal_no <= len(goals) else f'Finish "{title}"', goal_no)
        elif kind == "turnin":
            row("turnin", qid, here, f'Turn in "{title}" to {q.end_name}' if q and q.end_name else f'Turn in "{title}"')
        elif kind in ("fly", "hearth"):
            dest = next_point(i)
            d = where(dest) if dest else None
            text = f"Fly to {d[0]}" if kind == "fly" and d else ("Use your Hearthstone" if kind == "hearth" else "Take the flight")
            row(kind, 0, here, text, dest=dest)
        elif kind == "home":
            w = where(here) if here else None
            row("home", 0, here, f"Set your Hearthstone at the inn in {w[0]}" if w else "Set your Hearthstone at the inn")
        else:  # travel
            w = where(here) if here else None
            row("travel", 0, here, f"Go to {w[0]}" if w else "Go on")
    return rows, stats
