"""Travel for the leveling guide: Horde flight masters, which continent each zone is on, and the ships
between continents. The addon turns these into directions when a step is far away.

Continents are world map IDs: 0 Eastern Kingdoms, 1 Kalimdor.
"""
from build_farm import as_dicts, num

FLIGHT_MASTER = 8  # creature_template NpcFlags bits (Classic)
INNKEEPER = 128
REPAIR = 16384

# Zeppelins and boats a Horde character takes between continents (Classic geography, both ways):
# (kind, (name, zone, x, y, continent), (name, zone, x, y, continent)). Map coordinates of the docks.
TRANSPORTS = [
    ("zeppelin", ("Orgrimmar zeppelin tower", "Durotar", 50.8, 13.6, 1), ("Undercity zeppelin tower", "Tirisfal Glades", 60.7, 58.8, 0)),
    ("zeppelin", ("Orgrimmar zeppelin tower", "Durotar", 50.8, 13.6, 1), ("Grom'gol zeppelin tower", "Stranglethorn Vale", 31.4, 30.2, 0)),
    ("boat", ("Ratchet dock", "The Barrens", 63.7, 38.6, 1), ("Booty Bay dock", "Stranglethorn Vale", 25.9, 73.1, 0)),
]


def flight_masters(tables, side_of_faction, where, flag=FLIGHT_MASTER):
    """[[name, zone, x, y, continent]] for every flight master (or NPC with another service flag:
    innkeepers, repairers) the Horde can use."""
    spawns = {}
    for r in as_dicts(tables["creature"]):
        spawns.setdefault(int(num(r["id"])), (int(num(r["map"])), num(r["position_x"]), num(r["position_y"])))
    out = []
    for r in as_dicts(tables["creature_template"]):
        entry = int(num(r["Entry"]))
        if not int(num(r["NpcFlags"])) & flag or side_of_faction(int(num(r["Faction"]))) != "H" or entry not in spawns:
            continue
        point = spawns[entry]
        w = where(point)
        if w:
            out.append([r["Name"], w[0], round(w[1], 1), round(w[2], 1), point[0]])
    return sorted(out, key=lambda f: (f[1], f[0]))


def service_points(tables, side_of_faction, flag):
    """[(name, (map, x, y))] in world yards for Horde NPCs with a service flag (flight masters, innkeepers): for the
    planner's flights and hearthstone."""
    spawns = {}
    for r in as_dicts(tables["creature"]):
        spawns.setdefault(int(num(r["id"])), (int(num(r["map"])), num(r["position_x"]), num(r["position_y"])))
    out = []
    for r in as_dicts(tables["creature_template"]):
        entry = int(num(r["Entry"]))
        if int(num(r["NpcFlags"])) & flag and side_of_faction(int(num(r["Faction"]))) == "H" and entry in spawns                 and spawns[entry][0] in (0, 1):
            out.append((r["Name"], spawns[entry]))
    return sorted(out)


FLIGHT_NEAR = 12  # map %: a route step this close to a flight master passes by it


def add_flight_steps(steps, flights):
    """A copy of the route with a "flight" step at each flight master (user, 2026-11-13: pick up every
    flight path): before the route's first step near it, or its first step in that zone. Steps are
    [kind, quest, zone, x, y, level, text, goal]."""
    inserts = []
    for name, zone, x, y, _ in flights:
        in_zone = [k for k, s in enumerate(steps) if s[2] == zone and s[0] != "travel"]
        if not in_zone:
            continue
        near = [k for k in in_zone if steps[k][3] is not None and abs(steps[k][3] - x) <= FLIGHT_NEAR and abs(steps[k][4] - y) <= FLIGHT_NEAR]
        at = (near or in_zone)[0]
        inserts.append((at, ["flight", 0, zone, x, y, steps[at][5], f"Get the flight path from {name}", 0]))
    out = list(steps)
    for at, step in sorted(inserts, key=lambda t: -t[0]):
        out.insert(at, step)
    return out


def zone_continents(points, where):
    """{zone: continent} from world points."""
    out = {}
    for p in points:
        w = where(p) if p else None
        if w:
            out.setdefault(w[0], p[0])
    return out
