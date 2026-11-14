"""Class quests in the route (user, 2026-11-14: put them in the route at the right time).

Each Horde class quest chain goes into the route where the route first stands in the giver's zone at or above the
quest's level: pick-up, its objectives, hand-in. The addon passes them by for other classes (the quest's class
doesn't match), so one route serves every class. Steps are [kind, quest, zone, x, y, level, text, goal, dest].
"""


import math

NEAR = 500     # yards: the route passes this close to the giver
SPREAD = 1500  # yards: and the objectives and hand-in are this close to the giver (far ones stay an errand)


def _dist(a, b):
    return math.hypot(a[1] - b[1], a[2] - b[2]) if a and b and a[0] == b[0] else math.inf


def _point(step, by_id):
    q = by_id.get(step[1])
    if not q:
        return None
    if step[0] == "accept":
        return q.start
    if step[0] == "turnin":
        return q.end
    if step[0] == "do" and 0 < step[7] <= len(q.goals):
        return q.goals[step[7] - 1].point
    return None


def insert_class_quests(steps, quests, where, race_bits):
    """A copy of the route with class quest chains added where the route passes their giver; race_bits: the races
    this route is for."""
    by_id = {q.id: q for q in quests}
    out = [list(s) for s in steps]
    placed_end = {}  # class quest -> index of its hand-in, so a follow-up comes after it
    chains = sorted((q for q in quests if q.classes and q.start and all(g.point for g in q.goals)
                     and (not q.races or q.races & race_bits) and not q.kind
                     and all(_dist(q.start, g.point) <= SPREAD for g in q.goals) and _dist(q.start, q.end) <= SPREAD),
                    key=lambda q: (q.min_level, q.level, q.id))
    for q in chains:
        if q.prev > 0 and q.prev in {c.id for c in chains} and q.prev not in placed_end:
            continue  # its earlier quest isn't in the route
        here = where(q.start)
        if not here:
            continue
        after = placed_end.get(q.prev, -1)
        at = next((k + 1 for k, s in enumerate(out) if k > after and s[5] >= q.min_level
                   and _dist(_point(s, by_id), q.start) <= NEAR), None)
        if at is None:
            continue
        level = out[at - 1][5]
        block = [["accept", q.id, here[0], round(here[1], 1), round(here[2], 1), level, f'Accept "{q.title}" from {q.start_name}', 0, None]]
        for n, g in enumerate(q.goals, 1):
            w = where(g.point)
            if w:
                block.append(["do", q.id, w[0], round(w[1], 1), round(w[2], 1), level, f'{g.name} for "{q.title}"', n, None])
        end = where(q.end) if q.end else None
        if end:
            block.append(["turnin", q.id, end[0], round(end[1], 1), round(end[2], 1), level, f'Turn in "{q.title}" to {q.end_name}', 0, None])
        out[at:at] = block
        for k in list(placed_end):
            if placed_end[k] >= at:
                placed_end[k] += len(block)
        placed_end[q.id] = at + len(block) - 1
    return out
