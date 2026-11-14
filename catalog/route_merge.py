"""One stop per NPC visit: pulls a quest pick-up forward to an earlier visit to the same NPC in the same zone,
so one stop both hands in and picks up (user, 2026-11-14: fewer, clearer steps, like hub-based guides).

A pick-up only moves when that's safe: its earlier quest is already handed in (or in your log) by then, your
planned level there is high enough, it isn't timed, item-started or one of an either-or group, you don't leave
the zone in between, and the quest log stays under LOG_CAP.

Steps are [kind, quest, zone, x, y, level, text, goal].
"""
LOG_CAP = 18  # the game's log holds 20; keep two free


def _npc(step, by_id):
    q = by_id.get(step[1])
    if not q:
        return None
    if step[0] == "accept" and not q.start_item and not q.start_drop:
        return (q.start_name, step[2])
    if step[0] == "turnin":
        return (q.end_name, step[2])
    return None


def _log_sizes(steps):
    """Quests in your log after each step."""
    out, held = [], set()
    for s in steps:
        if s[0] == "accept":
            held.add(s[1])
        elif s[0] == "turnin":
            held.discard(s[1])
        out.append(len(held))
    return out


def merge_talks(steps, quests):
    """A copy of the route with pick-ups moved to the earliest safe visit to the same NPC."""
    by_id = {q.id: q for q in quests}
    out = [list(s) for s in steps]
    i = 0
    while i < len(out):
        s = out[i]
        q = by_id.get(s[1]) if s[0] == "accept" else None
        key = _npc(s, by_id) if q else None
        if not key or q.timed or q.exclusive:
            i += 1
            continue
        best = None
        for k in range(i - 1, -1, -1):
            t = out[k]
            if t[2] != s[2]:
                break  # you left the zone in between
            if (q.prev > 0 and t[0] == "turnin" and t[1] == q.prev) or (q.prev < 0 and t[0] == "accept" and t[1] == -q.prev):
                break  # not open before this
            if _npc(t, by_id) == key and (t[5] or 0) >= q.min_level:
                best = k
        if best is None or best == i - 1:
            i += 1
            continue
        at = best
        while at + 1 < i and _npc(out[at + 1], by_id) == key:
            at += 1  # after the whole stop
        if at + 1 >= i:
            i += 1
            continue
        sizes = _log_sizes(out)
        if max(sizes[at:i]) + 1 > LOG_CAP:
            i += 1
            continue
        moved = out.pop(i)
        moved[3], moved[4], moved[5] = out[at][3], out[at][4], out[at][5]
        out.insert(at + 1, moved)
        i += 1
    return out


def stops(steps, quests):
    """How many stops the route makes: talk steps at the same NPC in a row count as one."""
    by_id = {q.id: q for q in quests}
    n, prev = 0, None
    for s in steps:
        key = _npc(s, by_id)
        if key is None or key != prev:
            n += 1
        prev = key
    return n
