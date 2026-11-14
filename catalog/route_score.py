"""Scorecard for a leveling route: estimated hours, running, flights, hearthstones, quests, experience.

The same time model as the 2026-11-14 comparison (reports/speed-leveling-plan.html), so changes to the planner are
measured, not guessed. Reference on Orc Warrior 1-22 with this model: RestedXP 12.4 h, Zygor 14.3 h.

Model: run 7 yd/s between steps (one point per step), fly 25 yd/s + 20 s, hearthstone 15 s, a continent change 300 s,
each NPC talk 10 s, each objective kill 20 s; experience = quest XP + objective-kill XP; the shortfall to the target
level is ground at 135 xp per 20 s.
Steps are [kind, quest, zone, x, y, level, text, goal, dest]; dest = [zone, x, y] for fly and hearth steps.
"""
import math

RUN, FLY, KILL, TALK, HEARTH, SHIP, FLY_OVERHEAD = 7.0, 25.0, 20.0, 10.0, 15.0, 300.0, 20.0
XP_TABLE = [400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400, 16000, 17700, 19400,
            21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400, 50800, 54100, 57700, 61000,
            64900, 68200, 71900, 75300, 79100, 82800, 86800, 90600, 94500, 98600, 102700, 106800, 111000, 115200, 119500,
            123800, 128200, 132600, 137000, 141600, 146200, 150800, 155500, 160300, 165200]
REFERENCE_1_22 = {"RestedXP": 12.4, "Zygor": 14.3}


def zone_boxes(ui_map_rows, assignment_rows):
    """{zone name: (x0, y0, x1, y1, map)} in world yards, from UiMap and UiMapAssignment."""
    uimap = {int(r["ID"]): r for r in ui_map_rows}
    boxes = {}
    for r in assignment_rows:
        m = uimap.get(int(r["UiMapID"]))
        if not m or m["Type"] != "3":
            continue
        x0, y0, x1, y1 = (float(r[k]) for k in ("Region_0", "Region_1", "Region_3", "Region_4"))
        area = abs((x1 - x0) * (y1 - y0))
        if m["Name_lang"] not in boxes or area > boxes[m["Name_lang"]][5]:
            boxes[m["Name_lang"]] = (x0, y0, x1, y1, int(r["MapID"]), area)
    return {k: v[:5] for k, v in boxes.items()}


def world(boxes, zone, x, y):
    b = boxes.get(zone)
    if not b or x is None:
        return None
    x0, y0, x1, y1, mp = b
    return (mp, x1 - (y / 100) * (x1 - x0), y1 - (x / 100) * (y1 - y0))


def _mob_xp(level):
    return max(1, int(level or 1)) * 5 + 45


DUNGEON_RUN = 2400.0  # seconds per dungeon visited (the planner's estimate)


def score(steps, quests, boxes, target=22, class_bit=1, start=1):
    """quests: {id: route_model.Quest}. Only steps planned from level `start` to below `target` count; class quests
    only for class_bit (1 = Warrior). The shortfall is ground at one same-level kill per 20 s at the middle level."""
    runs = set()
    yards = fly_yards = 0.0
    talks = turned = flights = hearths = ships = kills = 0
    xp = 0.0
    last = None
    for s in steps:
        kind, qid, zone, x, y, level = s[0], s[1], s[2], s[3], s[4], s[5]
        if level >= target:
            break
        if level < start:
            continue
        q = quests.get(qid)
        if q and q.classes and not q.classes & class_bit:
            continue  # another class's quest: passed by
        p = world(boxes, zone, x, y)
        if kind in ("fly", "hearth") and len(s) > 8 and s[8]:
            d = world(boxes, *s[8])
            if kind == "fly":
                flights += 1
                if p and d and p[0] == d[0]:
                    fly_yards += math.hypot(p[1] - d[1], p[2] - d[2])
            else:
                hearths += 1
            if p and last and p[0] == last[0]:
                yards += math.hypot(p[1] - last[1], p[2] - last[2])
            last = d or last
            continue
        if p is not None:
            if last is not None:
                if p[0] != last[0]:
                    ships += 1
                else:
                    yards += math.hypot(p[1] - last[1], p[2] - last[2])
            last = p
        if kind == "accept":
            talks += 1
        elif kind == "turnin" and qid in quests:
            talks += 1
            turned += 1
            q = quests[qid]
            n = sum(g.count for g in q.goals if g.kind in ("kill", "collect"))
            kills += n
            xp += q.xp + sum(g.count * _mob_xp(g.mob_level) for g in q.goals if g.kind in ("kill", "collect"))
            runs.update(g.instance for g in q.goals if getattr(g, "instance", 0))
    need = sum(XP_TABLE[start - 1:target - 1])
    middle = (start + target) / 2
    grind = max(0.0, need - xp) / (135 if target <= 22 else middle * 5 + 45) * KILL
    t = len(runs) * DUNGEON_RUN + yards / RUN + fly_yards / FLY + flights * FLY_OVERHEAD + hearths * HEARTH + ships * SHIP + talks * TALK + kills * KILL
    return {"hours": round((t + grind) / 3600, 2), "grind_hours": round(grind / 3600, 2), "run_km": round(yards / 1093.6, 1),
            "flights": flights, "hearths": hearths, "quests": turned, "xp": int(xp), "dungeons": len(runs)}
