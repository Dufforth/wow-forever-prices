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
from route_model import Quest  # noqa: E402
from route_guides import guides  # noqa: E402
from route_merge import merge_talks, stops  # noqa: E402
from route_data import SCRIPT_TABLES, instance_entrances  # noqa: E402
from route_class import insert_class_quests  # noqa: E402
from route_forever import load_questie, load_recorded, load_rxp  # noqa: E402
from route_styles import STYLES, PVP_ZONES, ExplorerScorer, explorer_bands, farm_spots, insert_farm_stops, route_name, safe_bands  # noqa: E402
from route_planner import Shortcuts  # noqa: E402
from route_score import score, world, zone_boxes  # noqa: E402

from rxp_route import ORC_WARRIOR, band_table, band_text, for_me, load_steps  # noqa: E402
from rxp_rows import rows_from_steps  # noqa: E402
from route_zones import hinted_where, on_map, quest_zone_hints  # noqa: E402
from route_height import Heights  # noqa: E402
from route_travel import service_points, FLIGHT_MASTER  # noqa: E402

DUNGEON_SUFFIX = " (dungeons)"
from route_travel import INNKEEPER, REPAIR, TRANSPORTS, add_flight_steps, flight_masters, zone_continents  # noqa: E402
from route_planner import Eligibility, HubScorer, RoutePlanner, TravelModel, XpModel, ZonePlan  # noqa: E402

TABLES = build_farm.TABLES + ("item_template", "gameobject_questrelation", "gameobject_involvedrelation", "gameobject",
                              "gameobject_template", "gameobject_loot_template", "areatrigger_involvedrelation", "areatrigger_teleport") + SCRIPT_TABLES
STARTS = {"Durotar": ("Orc", "Troll"), "Mulgore": ("Tauren",), "Tirisfal Glades": ("Undead",)}
RACE_BITS = {"Orc": 2, "Undead": 16, "Tauren": 32, "Troll": 128}
CITIES = {"Orgrimmar", "Thunder Bluff", "Undercity"}
USE_QUESTIE = True  # Forever's own quests from Questie's Forever database (catalog/forever_questie_quests.json)
# Which zones fit each level band for the Horde (general leveling knowledge, not taken from any guide).
# Bands overlap so the planner can finish a zone; the planner picks hubs and order inside them.
HORDE_BANDS = [
    (10, 17, ["The Barrens", "Silverpine Forest", "Tirisfal Glades"]),  # Forever's own quests make Tirisfal worth it
    (16, 22, ["Stonetalon Mountains", "The Barrens", "Ashenvale"]),
    (20, 25, ["Hillsbrad Foothills", "Stonetalon Mountains", "Ashenvale", "The Barrens"]),
    (24, 30, ["Ashenvale", "Thousand Needles", "Hillsbrad Foothills"]),
    (28, 34, ["Thousand Needles", "Desolace", "Arathi Highlands", "Stranglethorn Vale"]),
    # Forever's new zones (Questie's Forever data, 2026-11-16): Riverglades 36-44, Shen'dralas 35-45, Mount Hyjal 55-60.
    # Measured with them (speed routes): Durotar 70.7 -> 70.1 h... see CHANGELOG 4.37.5.
    (32, 38, ["Stranglethorn Vale", "Dustwallow Marsh", "Arathi Highlands", "Desolace", "Swamp of Sorrows", "Shen'dralas"]),
    (36, 42, ["Badlands", "Swamp of Sorrows", "Stranglethorn Vale", "Dustwallow Marsh", "Desolace", "Riverglades", "Shen'dralas"]),
    (40, 46, ["Tanaris", "Feralas", "Stranglethorn Vale", "The Hinterlands", "Riverglades"]),
    (44, 50, ["Feralas", "The Hinterlands", "Searing Gorge", "Tanaris", "Azshara"]),
    (48, 53, ["Un'Goro Crater", "Azshara", "Felwood", "Searing Gorge", "Blasted Lands"]),
    (51, 56, ["Felwood", "Burning Steppes", "Winterspring", "Un'Goro Crater"]),
    (54, 60, ["Winterspring", "Western Plaguelands", "Eastern Plaguelands", "Silithus", "Burning Steppes", "Mount Hyjal"]),
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


def goal_row(g, place):
    """[kind, name, count, zone, x, y, source, wide, loop [[x, y]...], min level, max level, elite]."""
    spot = place(g.point) or ["?", None, None]
    loop = []
    for p in g.loop:
        w = place(p)
        if w and w[0] == spot[0]:
            loop.append([round(w[1], 1), round(w[2], 1)])
    return [g.kind, g.name, g.count] + spot + [g.source, int(g.wide), loop, g.levels[0], g.levels[1], int(g.elite), int(g.guessed), g.instance]


def serialize(quests, routes, where, ui_maps, commit, travel=None, heights=None):
    by_id = {q.id: q for q in quests}
    extras = {"class": [q.id for q in quests if q.classes], "dungeon": [q.id for q in quests if q.kind == "dungeon"],
              "item": [q.id for q in quests if q.start_item and not q.classes and not q.kind]}
    used = {q.id for q in quests}  # every Horde quest: the addon needs them to recognize done and logged quests

    def place(point):
        w = where(point) if point else None
        return list(w) if w else None

    def npc_place(point):
        """[zone, x, y] plus how far above (+) or below (-) the ground the NPC stands, when it's a floor or more
        (user, 2026-11-14: Darsok Swiftdagger on top of the Crossroads tower)."""
        w = place(point)
        lift = heights.lift(point) if (w and heights) else 0
        return w + [lift] if lift else w
    slim = {}
    for qid in sorted(used):
        q = by_id[qid]
        slim[str(qid)] = [q.title, q.level, q.min_level, q.classes, q.kind, q.prev, q.next_in_chain, q.start_name, npc_place(q.start),
                          q.end_name, npc_place(q.end), [goal_row(g, place) for g in q.goals],
                          q.gear, q.start_item, q.races, list(q.start_drop) or 0]
    return {"source": {"db": build_farm.DB_REPO, "commit": commit}, "uiMaps": ui_maps,
            "columns": {"quest": ["title", "level", "minLevel", "classes", "type", "prev", "nextInChain", "giver", "giverPlace",
                                  "turnIn", "turnInPlace", "goals [kind, name, count, zone, x, y, source, wide, loop, minLevel, maxLevel, elite, guessed place, dungeon map]", "gearRewards", "startItem", "races",
                                  "drop [item, monster, chance %] for a quest started by a dropped item, else 0"],
                        "step": ["kind", "quest", "zone", "x", "y", "level", "text", "goal", "dest [zone, x, y] for fly and hearth"]},
            "routes": routes, "extras": extras, "quests": slim, "travel": travel or {}}


def travel(quests, tables, factions, where):
    """Flight masters, each zone's continent and the ships, for the guide's directions."""
    flights = flight_masters(tables, lambda f: side_of(factions.get(f)), where)
    points = [p for q in quests for p in [q.start, q.end] + [g.point for g in q.goals] if p]
    continents = zone_continents(points, where)
    for f in flights:
        continents.setdefault(f[1], f[4])
    side = lambda f: side_of(factions.get(f))  # noqa: E731
    inns = [i[:4] for i in flight_masters(tables, side, where, INNKEEPER)]
    repairs = [r[:4] for r in flight_masters(tables, side, where, REPAIR)]
    return {"flights": flights, "continents": continents, "inns": inns, "repairs": repairs,
            "transports": [[kind, list(a), list(b)] for kind, a, b in TRANSPORTS]}


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cache", type=Path, help="folder to keep downloads in")
    parser.add_argument("--commit", help="classic-db commit (default: newest)")
    parser.add_argument("--out", type=Path, default=ROOT / "catalog" / "route.json", help="where to write (default catalog/route.json)")
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
    entrances = instance_entrances(tables, triggers, wago["Map"])  # dungeon objectives are placed at the entrance
    every = QuestRepository(tables, npc_side=lambda f: side_of(factions.get(f)), triggers=triggers,
                            entrances=entrances).load(keep_unplaced=True)
    boxes = zone_boxes(wago["UiMap"], wago["UiMapAssignment"])
    # Forever's own quests recorded in game (tools/import_recorded_quests.py): they join the route like any other.
    recorded = load_recorded(ROOT / "catalog" / "forever_quests.json", boxes, {q.id for q in every})
    every += recorded
    # Forever's own quests with places from RestedXP's Forever guides (CC BY-NC-SA 4.0, see LICENSE-DATA.md);
    # their experience: the median Classic quest of the same level.
    by_level = {}
    for q in every:
        if q.xp:
            by_level.setdefault(q.level, []).append(q.xp)
    xp_by_level = {lv: sorted(v)[len(v) // 2] for lv, v in by_level.items()}
    # Forever's own quests from Questie's Forever database (GPL-3.0, tools/extract_questie_forever.py): real givers,
    # spawn places and experience; they come before RestedXP's (which only fill the quests Questie can't place).
    questie = load_questie(ROOT / "catalog" / "forever_questie_quests.json", boxes, {q.id for q in every}) if USE_QUESTIE else []
    for q in questie:
        q.xp = q.xp or xp_by_level.get(q.level, 0)
    every += questie
    rxp = load_rxp(ROOT / "catalog" / "forever_rxp_quests.json", boxes, {q.id for q in every}, xp_by_level)
    every += rxp
    print(f"Forever quests: {len(recorded)} recorded in game, {len(questie)} from Questie, {len(rxp)} from RestedXP's Forever guides")
    # The route only uses quests it can place; questline guides take them all.
    quests = [q for q in every if all(g.point is not None for g in q.goals)]
    by_id = {q.id: q for q in every}
    where = make_where(wago, tables)
    # A quest's objectives in the overlap of two zone maps take the quest's own zone (route_zones.py).
    zone_of_area = build_farm.area_zones(wago["AreaTable"])
    zone_of_quest = {int(r["entry"]): zone_of_area.get(int(num(r.get("ZoneOrSort"))))
                     for r in build_farm.as_dicts(tables["quest_template"]) if int(num(r.get("ZoneOrSort"))) > 0}
    where = hinted_where(where, boxes, quest_zone_hints(every, zone_of_quest))
    side = lambda f: side_of(factions.get(f))  # noqa: E731
    flight_points, inn_points = service_points(tables, side, FLIGHT_MASTER), service_points(tables, side, INNKEEPER)
    flights = flight_masters(tables, side, where)
    # Boats and zeppelins as world points: a sea crossing costs the way to the dock, the ride and the way on.
    docks = [(world(boxes, a[1], a[2], a[3]), world(boxes, b[1], b[2], b[3])) for _, a, b in TRANSPORTS]
    farm = farm_spots(json.loads((ROOT / "site" / "farm.json").read_text(encoding="utf-8")))  # explorer's farming stops
    routes, scorecards = {}, {}
    # Quests RestedXP names that our data doesn't hold: a stub with the best title we have, so the step stays.
    titles = {int(r["entry"]): ((r.get("Title") or "").strip(), int(num(r.get("QuestLevel"))), int(num(r.get("MinLevel"))))
              for r in build_farm.as_dicts(tables["quest_template"])}
    for f in ("forever_questie_quests.json", "forever_rxp_quests.json"):
        for q in json.loads((ROOT / "catalog" / f).read_text(encoding="utf-8"))["quests"]:
            titles.setdefault(int(q["id"]), (q["title"], int(q.get("level") or 0), int(q.get("min_level") or 1)))
    route_qids = set()

    def stub(qid, level):
        title, qlevel, min_level = titles.get(qid, (f"Quest {qid}", level, 1))
        return Quest(qid, title or f"Quest {qid}", qlevel or level, min_level or 1, None, "", None, "", [])
    try:  # RestedXP's guide steps (tools/extract_rxp_route.py, CC BY-NC-SA 4.0, see LICENSE-DATA.md)
        rxp_file = json.loads((ROOT / "catalog" / "rxp_routes.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        rxp_file = {}
    rxp_chains = rxp_file.get("routes", {})
    # Zone and area names for RestedXP's .zone/.zoneskip (UiMap ids) and .home/.subzone (AreaTable ids).
    rx_names = {"map": {int(r["ID"]): r["Name_lang"] for r in wago["UiMap"]},
                "area": {int(r["ID"]): r["AreaName_lang"] for r in wago["AreaTable"]},
                "on": lambda zone, point: on_map(boxes, zone, point),
                "item": {int(k): v[0] for k, v in json.loads((ROOT / "site" / "all_items.json").read_text(encoding="utf-8")).items()}}
    for zone, races in STARTS.items():
        race_bit = RACE_BITS[races[0]]
        race_bits = sum(RACE_BITS[r] for r in races)
        # One route per start and a dungeon variant, exactly RestedXP's two chains (user, 2026-11-26: "RestedXP only":
        # the Safe and Explorer styles are gone).
        for style, dungeons in [("speed", False), ("speed", True)]:
            eligibility = Eligibility()
            eligibility.dungeons = dungeons  # the "with dungeons" route also takes dungeon quests (for players who group)
            bands = START_BANDS[zone] + HORDE_BANDS
            if style == "safe":
                bands = safe_bands(bands)
            elif style == "explorer":
                bands = explorer_bands(bands)
            def make_planner(wait_levels, sea_waits=False):
                p = RoutePlanner(quests, where=where, eligibility=eligibility, xp=XpModel(), travel=TravelModel(docks),
                                 scorer=ExplorerScorer() if style == "explorer" else HubScorer(),
                                 zone_plan=ZonePlan(bands, cities=CITIES), shortcuts=Shortcuts(flight_points, inn_points),
                                 avoid=PVP_ZONES if style == "safe" else ())
                p.WAIT_LEVELS = wait_levels
                p.SEA_TURNIN_WAITS = sea_waits
                if style == "explorer":
                    p.ZONE_CHANGE, p.STAY = 150, 0.3  # moves on to new zones sooner: more of the world, more flight paths
                return p
            # Every route follows RestedXP's Forever guide (user, 2026-11-24: "base our route on RestedXP's route",
            # every route, follow its order and fill gaps); the planner below is only the fallback without that file.
            chain = rxp_chains.get(zone, {}).get("dungeons" if dungeons else "main")
            if chain:
                # Exactly RestedXP's steps (user, 2026-11-26: "follow exact same steps hubs and everything"): no merged
                # talks, class quests, extra flight steps or farm stops of ours.
                # RestedXP's steps whole, run by the addon's step engine (user, 2026-11-27: "at 100%" like RestedXP).
                rows, records, stats = rows_from_steps(chain["steps"], by_id, where, stub, rx_names)
                route_qids.update(r[1] for r in rows if r[1])
                name = route_name(zone, style, dungeons)
                # The scorecard times one character's way through: an Orc Warrior's steps and lines.
                mine = [r for r in rows if for_me(records[r[10] - 1].get("t", ""), ORC_WARRIOR)
                        and for_me((r[11] or {}).get("lt", ""), ORC_WARRIOR) and r[0] in ("accept", "turnin", "do", "fly", "hearth")]
                whole = score(mine, by_id, boxes, 60, class_bit=1)
                routes[name] = {"races": list(races), "reached": 60 if max(r[5] for r in rows) >= 59 else max(r[5] for r in rows), "hours": round(whole["hours"], 1),
                                "dungeons": dungeons, "style": style, "steps": rows, "base": "RestedXP", "rx": records,
                                "parts": chain["parts"], "subs": chain.get("subs", [])}
                card = score(mine, by_id, boxes, 22, class_bit=1)
                rxp_steps = load_steps(ROOT / "catalog" / "rxp_forever_route.json")
                if rxp_steps:
                    scorecards[name] = band_table(mine, rxp_steps, by_id, boxes)
                print(f"{name}: RestedXP base, {len(rows)} steps, about {routes[name]['hours']} h to 60 (scorecard model); "
                      f"{stats['unknown']} steps of quests our data doesn't know (kept with RestedXP's quest number), "
                      f"{stats['no_place']} quest steps without a guide point (no waypoint); 1-22: {card['hours']} h"
                      + (f"; vs RestedXP Forever: {band_text(scorecards[name])}" if name in scorecards else ""))
                continue
            # Planned with and without waiting for the quests around a far lonely objective (user, 2026-11-14: no long walk
            # for one quest); the faster plan is kept, so the rule never makes a route slower (Tirisfal was +4.6 h with it).
            start = start_point(quests, zone, race_bit, where)
            planner = make_planner(RoutePlanner.WAIT_LEVELS)
            steps, me = planner.plan(start=start, race_bit=race_bit)
            plain = make_planner(0)
            plain_steps, plain_me = plain.plan(start=start, race_bit=race_bit)
            if plain_me.level >= me.level and plain_me.time < me.time:
                planner, steps, me = plain, plain_steps, plain_me
            # And with hand-ins across the sea waiting for this continent's hubs (fewer crossings): kept when faster.
            for wait_levels in (RoutePlanner.WAIT_LEVELS, 0):
                other = make_planner(wait_levels, sea_waits=True)
                other_steps, other_me = other.plan(start=start, race_bit=race_bit)
                if other_me.level >= me.level and other_me.time < me.time:
                    planner, steps, me = other, other_steps, other_me
            rows = [[s.kind, s.quest, s.zone, s.x, s.y, s.level, s.text, s.goal, s.dest] for s in steps]
            rows = merge_talks(rows, quests)                               # one stop per NPC visit
            rows = insert_class_quests(rows, quests, where, race_bits)     # class quests where the route passes their giver
            rows = add_flight_steps(rows, flights)
            if style == "explorer":
                rows = insert_farm_stops(rows, farm)                       # a gold-farming stop per zone visit
            name = route_name(zone, style, dungeons)
            routes[name] = {"races": list(races), "reached": me.level, "hours": round(me.time / 3600, 1), "dungeons": dungeons,
                            "style": style, "steps": rows}
            card = score(rows, by_id, boxes, 22, class_bit=1)
            late = score(rows, by_id, boxes, 60, class_bit=1, start=22)
            # 22-60 band by band against RestedXP's Forever guide, same time model (user, 2026-11-24: "extend to 60").
            rxp_steps = load_steps(ROOT / "catalog" / "rxp_forever_route.json")
            if rxp_steps:  # every start here is Horde, like the guide
                scorecards[name] = band_table(rows, rxp_steps, by_id, boxes)
                print(f"{name} vs RestedXP Forever: {band_text(scorecards[name])}")
            print(f"{name}: {len(rows)} steps, level {me.level}, about {routes[name]['hours']} h to 60, {planner.flights_taken} flights, "
                  f"{planner.hearths_used} hearthstones, {planner.crossings} sea crossings; scorecard 1-22 (warrior): {card}  (reference RestedXP 12.4 h, Zygor 14.3 h); "
                  f"22-60: {late['hours']} h (reference Zygor Forever 74.0 h, RestedXP Forever 90.6 h)")
    if scorecards:  # kept for reading later without rebuilding (reports/, not shipped)
        (ROOT / "reports" / "route-scorecard-22-60.json").write_text(json.dumps(scorecards, indent=1), encoding="utf-8")
    ui_maps = {r["Name_lang"]: int(r["ID"]) for r in wago["UiMap"] if r["Type"] == "3"}
    spawns = [(int(num(r["map"])), num(r["position_x"]), num(r["position_y"]), num(r["position_z"]))
              for table in ("creature", "gameobject") for r in build_farm.as_dicts(tables[table])]
    placed = {q.id for q in quests}
    quests = quests + [by_id[qid] for qid in sorted(route_qids) if qid not in placed and qid in by_id]  # every route quest has data
    data = serialize(quests, routes, where, ui_maps, commit, travel(quests, tables, factions, where), Heights(spawns))
    # RestedXP's Forever Spirit Healers as zone spots: the ghost arrow on death-skip steps (map.lua).
    data["spirit"] = [[w[0], round(w[1], 2), round(w[2], 2), h[3]] for h in rxp_file.get("spirit", []) for w in [where((h[0], h[1], h[2]))] if w]
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
    path = args.out
    path.write_text(json.dumps(data, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    print(f"route.json: {len(data['quests'])} quests, {path.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
