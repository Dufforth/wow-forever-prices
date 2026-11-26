"""Our route rows from RestedXP's event chain (catalog/rxp_chain.py): RestedXP's order, our quest data for names,
givers and places (user, 2026-11-24: "base our route on RestedXP's route", follow it and fill gaps).

Gaps: a quest our data doesn't know is left out (counted); a hand-in of a quest the route never picked up is left
out (counted). Places: RestedXP's own map point when the guide step has one (it's made for Forever, where some
givers moved), else our data's. An objective the guide never names gets no step of its own: the guide gathers it
along the way (adding one before the hand-in sent you across the map: Blue Pearls in Stranglethorn from Badlands).
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


def rows_from_events(events, by_id, where):
    """Returns (rows, stats)."""
    rows, stats = [], {"unknown": 0, "not_picked_up": 0, "unnamed_objectives": 0, "no_place": 0}
    accepted, done = set(), set()
    level, zone_now = 1, None

    def row(kind, qid, point, text, goal=0, dest=None):
        nonlocal zone_now
        w = where(tuple(point)) if point else None
        d = where(tuple(dest)) if dest else None
        if rows and rows[-1][0] == kind and rows[-1][1] == qid and rows[-1][7] == goal and rows[-1][2] == (w[0] if w else "?")                 and kind in ("home", "travel", "fly", "hearth"):
            return  # the guide says it twice in a row (two steps for one inn)
        rows.append([kind, qid, w[0] if w else "?", round(w[1], 1) if w else None, round(w[2], 1) if w else None, level, text, goal,
                     [d[0], round(d[1], 1), round(d[2], 1)] if d else None])
        if w:
            zone_now = w[0]

    def next_point(i):
        for e in events[i + 1:]:
            if e[3] is not None:
                return (e[3], e[4], e[5])
        return None

    last = None
    for i, e in enumerate(events):
        kind, qid, goal_no, here, lv = e[0], e[1], e[2], ((e[3], e[4], e[5]) if e[3] is not None else None), e[6]
        level = max(level, lv)
        q = by_id.get(qid) if qid else None
        if qid and not q:
            stats["unknown"] += 1
            continue
        if kind == "accept":
            if qid in accepted:
                continue
            if not (here or q.start):  # started by a looted item where the guide gives no place: nowhere to send you
                stats["no_place"] += 1
                continue
            accepted.add(qid)
            row("accept", qid, here or q.start, _accept_text(q))
        elif kind == "complete":
            if not q.goals or qid not in accepted:
                continue
            index = goal_no if 0 < goal_no <= len(q.goals) else 1
            if (qid, index) in done:
                continue
            done.add((qid, index))
            row("do", qid, here or q.goals[index - 1].point, _do_text(q, q.goals[index - 1]), index)
        elif kind == "turnin":
            if qid not in accepted:
                stats["not_picked_up"] += 1
                continue
            if ("turnin", qid) in done:
                continue
            stats["unnamed_objectives"] += sum(1 for index in range(1, len(q.goals) + 1) if (qid, index) not in done)
            done.add(("turnin", qid))
            row("turnin", qid, here or q.end, f'Turn in "{q.title}" to {q.end_name}')
        elif kind in ("fly", "hearth"):
            dest = next_point(i)
            at = here or last
            if not dest or not at:
                continue
            d = where(dest)
            text = f"Fly to {d[0]}" if kind == "fly" and d else ("Use your Hearthstone" if kind == "hearth" else "Take the flight")
            row(kind, 0, at, text, dest=dest)
        elif kind == "home" and here:
            w = where(here)
            row("home", 0, here, f"Set your Hearthstone at the inn in {w[0]}" if w else "Set your Hearthstone at the inn")
        elif kind == "travel" and here:
            w = where(here)
            if w and w[0] != zone_now:
                row("travel", 0, here, f"Go to {w[0]}")
        if here:
            last = here
    return rows, stats
