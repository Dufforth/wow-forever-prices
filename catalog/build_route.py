#!/usr/bin/env python3
"""Build catalog/route.json: a Horde leveling route from level 1 to 60 for each starting zone
(Durotar: Orc and Troll, Mulgore: Tauren, Tirisfal Glades: Undead), planned to keep walking short.

This file only wires the parts together:
  route_data.QuestRepository   quests from the CMaNGOS Classic world database (Classic estimates)
  route_planner.RoutePlanner   simulates a new character: hubs, nearest objective first, turn-ins
  build_farm.zone_finder       world positions -> zone and map coordinates (Forever's map tables)
Class quests, dungeon quests and quests started by an item are written apart ("extras"): the addon
offers them when they fit your class and level.

    python catalog/build_route.py [--cache DIR] [--commit SHA]
"""
import argparse
import csv
import gzip
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_farm  # noqa: E402
from build_farm import num  # noqa: E402
from build_leveling_sources import side_of  # noqa: E402
from route_data import QuestRepository  # noqa: E402
from route_guides import guides  # noqa: E402
from route_travel import TRANSPORTS, add_flight_steps, flight_masters, zone_continents  # noqa: E402
from route_planner import Eligibility, HubScorer, RoutePlanner, TravelModel, XpModel, ZonePlan  # noqa: E402

TABLES = build_farm.TABLES + ("item_template", "gameobject_questrelation", "gameobject_involvedrelation", "gameobject",
                              "gameobject_template", "gameobject_loot_template", "areatrigger_involvedrelation")
STARTS = {"Durotar": ("Orc", "Troll"), "Mulgore": ("Tauren",), "Tirisfal Glades": ("Undead",)}
RACE_BITS = {"Orc": 2, "Undead": 16, "Tauren": 32, "Troll": 128}
CITIES = {"Orgrimmar", "Thunder Bluff", "Undercity"}
# Which zones fit each level band for the Horde (general leveling knowledge, not taken from any guide).
# Bands overlap so the planner can finish a zone; the planner picks hubs and order inside them.
HORDE_BANDS = [
    (10, 17, ["The Barrens", "Silverpine Forest"]),
    (16, 22, ["Stonetalon Mountains", "The Barrens", "Ashenvale"]),
    (20, 25, ["Hillsbrad Foothills", "Stonetalon Mountains", "Ashenvale", "The Barrens"]),
    (24, 30, ["Ashenvale", "Thousand Needles", "Hillsbrad Foothills"]),
    (28, 34, ["Thousand Needles", "Desolace", "Arathi Highlands", "Stranglethorn Vale"]),
    (32, 38, ["Stranglethorn Vale", "Dustwallow Marsh", "Arathi Highlands", "Desolace", "Swamp of Sorrows"]),
    (36, 42, ["Badlands", "Swamp of Sorrows", "Stranglethorn Vale", "Dustwallow Marsh", "Desolace"]),
    (40, 46, ["Tanaris", "Feralas", "Stranglethorn Vale", "The Hinterlands"]),
    (44, 50, ["Feralas", "The Hinterlands", "Searing Gorge", "Tanaris", "Azshara"]),
    (48, 53, ["Un'Goro Crater", "Azshara", "Felwood", "Searing Gorge", "Blasted Lands"]),
    (51, 56, ["Felwood", "Burning Steppes", "Winterspring", "Un'Goro Crater"]),
    (54, 60, ["Winterspring", "Western Plaguelands", "Eastern Plaguelands", "Silithus", "Burning Steppes"]),
]
START_BANDS = {"Durotar": [(1, 11, ["Durotar"])], "Mulgore": [(1, 11, ["Mulgore"])],
               "Tirisfal Glades": [(1, 11, ["Tirisfal Glades"]), (9, 13, ["Silverpine Forest"])]}


def horde_plan(start_zone):
    """The zone plan for a character that starts in this zone."""
    return ZonePlan(START_BANDS[start_zone] + HORDE_BANDS, cities=CITIES)


def make_where(wago, tables):
    zone_of_area = build_farm.area_zones(wago["AreaTable"])
    find = build_farm.zone_finder(wago["UiMapAssignment"], wago["UiMap"], {int(r["ID"]): r["MapName_lang"] for r in wago["Map"]},
                                  build_farm.labelled_spots(tables, zone_of_area))

    def where(point):
        """(zone, map x %, map y %) for a world point, or None (dungeons, unknown places)."""
        if point is None:
            return None
        p = find(point[0], point[1], point[2], None, prefer_city=True)
        return None if not p or p[3] else (p[0], p[1], p[2])
    return where


def start_point(quests, zone, race_bit, where):
    """Where a new character of this race starts: the giver of its first race-only quest in the zone."""
    firsts = [q for q in quests if q.min_level <= 1 and q.races and q.races & race_bit and not q.classes and q.start
              and (where(q.start) or ("",))[0] == zone]
    return min(firsts, key=lambda q: (q.level, q.id)).start


def serialize(quests, routes, where, ui_maps, commit, travel=None):
    by_id = {q.id: q for q in quests}
    extras = {"class": [q.id for q in quests if q.classes], "dungeon": [q.id for q in quests if q.kind == "dungeon"],
              "item": [q.id for q in quests if q.start_item and not q.classes and not q.kind]}
    used = {q.id for q in quests}  # every Horde quest: the addon needs them to recognize done and logged quests

    def place(point):
        w = where(point)
        return list(w) if w else None
    slim = {}
    for qid in sorted(used):
        q = by_id[qid]
        slim[str(qid)] = [q.title, q.level, q.min_level, q.classes, q.kind, q.prev, q.next_in_chain, q.start_name, place(q.start),
                          q.end_name, place(q.end), [[g.kind, g.name, g.count] + (place(g.point) or ["?", None, None]) + [g.source, int(g.wide)] for g in q.goals],
                          q.gear, q.start_item, q.races, list(q.start_drop) or 0]
    return {"source": {"db": build_farm.DB_REPO, "commit": commit}, "uiMaps": ui_maps,
            "columns": {"quest": ["title", "level", "minLevel", "classes", "type", "prev", "nextInChain", "giver", "giverPlace",
                                  "turnIn", "turnInPlace", "goals [kind, name, count, zone, x, y, source, wide]", "gearRewards", "startItem", "races",
                                  "drop [item, monster, chance %] for a quest started by a dropped item, else 0"],
                        "step": ["kind", "quest", "zone", "x", "y", "level", "text", "goal"]},
            "routes": routes, "extras": extras, "quests": slim, "travel": travel or {}}


def travel(quests, tables, factions, where):
    """Flight masters, each zone's continent and the ships, for the guide's directions."""
    flights = flight_masters(tables, lambda f: side_of(factions.get(f)), where)
    points = [p for q in quests for p in [q.start, q.end] + [g.point for g in q.goals]]
    continents = zone_continents(points, where)
    for f in flights:
        continents.setdefault(f[1], f[4])
    return {"flights": flights, "continents": continents,
            "transports": [[kind, list(a), list(b)] for kind, a, b in TRANSPORTS]}


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cache", type=Path, help="folder to keep downloads in")
    parser.add_argument("--commit", help="classic-db commit (default: newest)")
    args = parser.parse_args()
    cache = args.cache
    if cache:
        cache.mkdir(parents=True, exist_ok=True)
    commit = args.commit or json.loads(build_farm.fetch(f"https://api.github.com/repos/{build_farm.DB_REPO}/commits/master"))["sha"]
    raw = build_farm.fetch(f"https://raw.githubusercontent.com/{build_farm.DB_REPO}/{commit}/{build_farm.DB_FILE}",
                           cache / f"classicdb-{commit[:10]}.sql.gz" if cache else None, binary=True)
    tables = build_farm.read_dump(gzip.decompress(raw).decode("utf-8", errors="replace"), TABLES)
    build_name = json.loads((ROOT / "site" / "catalog.json").read_text(encoding="utf-8"))["build"]

    def table(name):
        text = build_farm.fetch(f"{build_farm.WAGO}/db2/{name}/csv?build={build_name}", cache / f"{name}-{build_name}.csv" if cache else None)
        return list(csv.DictReader(text.splitlines()))
    wago = {name: table(name) for name in ("UiMapAssignment", "UiMap", "Map", "AreaTable", "FactionTemplate", "AreaTrigger")}
    factions = {int(r["ID"]): r for r in wago["FactionTemplate"]}
    triggers = {int(r["ID"]): (int(num(r["ContinentID"])), num(r["Pos_0"]), num(r["Pos_1"])) for r in wago["AreaTrigger"]}
    every = QuestRepository(tables, npc_side=lambda f: side_of(factions.get(f)), triggers=triggers).load(keep_unplaced=True)
    # The route only uses quests it can place; questline guides take them all.
    quests = [q for q in every if all(g.point is not None for g in q.goals)]
    where = make_where(wago, tables)
    routes = {}
    for zone, races in STARTS.items():
        race_bit = RACE_BITS[races[0]]
        planner = RoutePlanner(quests, where=where, eligibility=Eligibility(), xp=XpModel(), travel=TravelModel(), scorer=HubScorer(),
                               zone_plan=horde_plan(zone))
        steps, me = planner.plan(start=start_point(quests, zone, race_bit, where), race_bit=race_bit)
        routes[zone] = {"races": list(races), "reached": me.level, "hours": round(me.time / 3600, 1),
                        "steps": [[s.kind, s.quest, s.zone, s.x, s.y, s.level, s.text, s.goal] for s in steps]}
        print(f"{zone}: {len(steps)} steps, level {me.level}, about {routes[zone]['hours']} h, "
              f"{sum(1 for s in steps if s.kind == 'grind')} grind steps")
    ui_maps = {r["Name_lang"]: int(r["ID"]) for r in wago["UiMap"] if r["Type"] == "3"}
    flights = flight_masters(tables, lambda f: side_of(factions.get(f)), where)
    for r in routes.values():
        r["steps"] = add_flight_steps(r["steps"], flights)
    data = serialize(quests, {z: {**r, "steps": [dict(zip(["kind", "quest", "zone", "x", "y", "level", "text", "goal"], s)) for s in r["steps"]]}
                              for z, r in routes.items()}, where, ui_maps, commit, travel(quests, tables, factions, where))
    for r in data["routes"].values():
        r["steps"] = [[s["kind"], s["quest"], s["zone"], s["x"], s["y"], s["level"], s["text"], s["goal"]] for s in r["steps"]]
    # Questline guides (attunements, Cozy Sleeping Bag): their own routes, chosen in the addon.
    data["guides"] = []
    for g in guides({q.id: q for q in every}, where):
        data["guides"].append({"name": g["name"], "note": g["note"]})
        data["routes"][g["name"]] = {"races": [], "guide": True, "steps": g["steps"]}
        for qid, row in g["quests"].items():
            data["quests"].setdefault(str(qid), row)
        for q in every:  # chain quests the route left out still need a row for the addon
            if any(s[1] == q.id for s in g["steps"]) and str(q.id) not in data["quests"]:
                data["quests"][str(q.id)] = [q.title, q.level, q.min_level, q.classes, q.kind, q.prev, q.next_in_chain, q.start_name,
                                             None, q.end_name, None, [[x.kind, x.name, x.count, "?", None, None, x.source, 0] for x in q.goals],
                                             q.gear, q.start_item, q.races, 0]
    # Which dungeon a dungeon quest is for: the instance its objectives are in (user: '9 dungeon quests', but which?).
    map_names = {int(r["ID"]): r["MapName_lang"] for r in wago["Map"]}
    data["extras"]["dungeonOf"] = {str(q.id): map_names[g.point[0]] for q in quests if q.kind == "dungeon"
                                   for g in q.goals[:1] if g.point and g.point[0] not in (0, 1) and g.point[0] in map_names}
    path = ROOT / "catalog" / "route.json"
    path.write_text(json.dumps(data, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    print(f"route.json: {len(data['quests'])} quests, {path.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
