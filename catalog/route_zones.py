"""Which zone a quest's objective is in, where two zone maps overlap.

Zone maps are rectangles that overlap at their borders, and the finder guesses from nearby known spots. For a quest's
own objectives the quest says its zone (quest_template.ZoneOrSort): when the spot lies on that zone's map, it's there
(user, 2026-11-14: the Witchwing harpies of Harpy Raiders, a Barrens quest, were put on the Stonetalon map and the
guide sent them flying to Stonetalon while they stood next to the harpies).
"""


def quest_zone_hints(quests, zone_of_quest):
    """{world point: zone} for every objective spot (and its loop spots) of quests whose zone is known."""
    hints = {}
    for q in quests:
        zone = zone_of_quest.get(q.id)
        if not zone:
            continue
        for g in q.goals:
            for p in [g.point] + list(g.loop or []):
                if p is not None:
                    hints.setdefault(p, zone)
    return hints


def on_map(boxes, zone, point):
    """(zone, map x %, map y %) when the world point is on that zone's map, else None."""
    b = boxes.get(zone)
    if not b or point is None:
        return None
    x0, y0, x1, y1, mp = b
    _, wx, wy = point
    if point[0] != mp or not (x0 <= wx <= x1 and y0 <= wy <= y1):
        return None
    return zone, round((y1 - wy) / (y1 - y0) * 100, 1), round((x1 - wx) / (x1 - x0) * 100, 1)


def hinted_where(where, boxes, hints):
    """where(point), except points with a hint whose zone map holds them."""
    def place(point):
        zone = hints.get(point) if point is not None else None
        return (zone and on_map(boxes, zone, point)) or where(point)
    return place
