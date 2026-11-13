#!/usr/bin/env python3
"""Build site/farm.json: which monsters drop each tradable item, how often, and where they are,
plus the quests that ask players to bring it.

Drop chances, monsters, spawns and quests come from the CMaNGOS Classic 1.12 world database
(github.com/cmangos/classic-db, GPL-3.0), a community rebuild of the original game's data.
Forever may differ, so the page labels these as Classic estimates. Zone names and map
coordinates come from the Forever client's own map tables through wago.tools.

Read once (about 13 MB) and saved in the repo, so the hourly price job never downloads it.

    python catalog/build_farm.py [--cache DIR] [--commit SHA] [--build 1.60.1.70862]
"""
import argparse
import csv
import gzip
import json
import re
import urllib.request
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AGENT = "wow-forever-prices (personal price page)"
DB_REPO = "cmangos/classic-db"
DB_FILE = "Full_DB/ClassicDB_1_12_1_z2815.sql.gz"
WAGO = "https://wago.tools"
TABLES = ("creature_template", "creature", "creature_loot_template", "reference_loot_template", "quest_template",
          "creature_questrelation", "creature_involvedrelation")
CELL = 250  # yards: grid cell for finding nearby spots with a known zone
NEIGHBOURS = 9
LEVEL_GAP = 15  # a zone whose usual monster level is this far off can't be the monster's zone
MIN_CHANCE = 0.5  # percent: rarer drops aren't worth farming on purpose
MIN_QUEST_CHANCE = 0.1  # quest needs are kept down to this
SOURCES_PER_ITEM = 6
QUESTS_PER_ITEM = 5
MAX_DEPTH = 4
ZONE_TYPE = 3
BATTLEGROUNDS = {30, 489, 529}  # Alterac Valley, Warsong Gulch, Arathi Basin: not farmable
CITIES = {"Stormwind City", "Ironforge", "Darnassus", "Orgrimmar", "Thunder Bluff", "Undercity"}
RANKS = {1: "elite", 2: "rare elite", 3: "boss", 4: "rare"}
SKIP_TITLE = re.compile(r"deprecated|unused|\[ph\]|<|zz|test", re.I)


# ---- Reading the SQL dump ----------------------------------------------------------

def parse_values(text):
    """Rows from the VALUES part of one INSERT: (a,'b',1.5),(...)."""
    rows, row, i, n = [], None, 0, len(text)
    while i < n:
        c = text[i]
        if c == "(" and row is None:
            row, i = [], i + 1
            continue
        if row is None:
            i += 1
            continue
        if c == "'":
            j, out = i + 1, []
            while j < n:
                d = text[j]
                if d == "\\":
                    out.append(text[j + 1]); j += 2; continue
                if d == "'":
                    if j + 1 < n and text[j + 1] == "'":
                        out.append("'"); j += 2; continue
                    break
                out.append(d); j += 1
            row.append("".join(out))
            i = j + 1
            continue
        if c in ",":
            i += 1
            continue
        if c == ")":
            rows.append(row); row = None; i += 1
            continue
        j = i
        while j < n and text[j] not in ",)":
            j += 1
        token = text[i:j].strip()
        row.append(None if token == "NULL" else token)
        i = j
    return rows


def read_dump(text, wanted=TABLES):
    """{table: (columns, rows)} for the wanted tables of a mysqldump file."""
    columns, rows = {}, defaultdict(list)
    current = None
    for line in text.splitlines():
        if line.startswith("CREATE TABLE `"):
            name = line.split("`")[1]
            current = name if name in wanted else None
            if current:
                columns[current] = []
            continue
        if current and line.startswith("  `"):
            columns[current].append(line.split("`")[1])
            continue
        if line.startswith(")"):
            current = None
            continue
        if line.startswith("INSERT INTO `"):
            name = line.split("`")[1]
            if name in wanted:
                rows[name].extend(parse_values(line[line.index("VALUES") + 6:]))
    return {name: (columns.get(name, []), rows[name]) for name in wanted}


def as_dicts(table):
    columns, rows = table
    return [dict(zip(columns, row)) for row in rows]


def num(value, default=0.0):
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


# ---- Loot math -----------------------------------------------------------------

def loot_index(rows):
    by_entry = defaultdict(list)
    for r in rows:
        by_entry[int(r["entry"])].append(r)
    return by_entry


def expected_items(entry, creature_loot, reference_loot, depth=0, scale=1.0, out=None):
    """{item: (chance %, expected count per kill)} for one loot entry.

    CMaNGOS rules: a negative chance only drops while you are on a quest (skipped here). A
    negative min count is a reference to another loot list, rolled with the row's chance, max
    count times. In a group (groupid > 0) exactly one entry drops: entries with a chance roll
    first, and the rest share what's left equally.
    """
    out = {} if out is None else out
    table = creature_loot if depth == 0 else reference_loot
    rows = table.get(entry, [])
    groups = defaultdict(list)
    for r in rows:
        groups[int(num(r["groupid"]))].append(r)
    for group, members in groups.items():
        if group:
            explicit = sum(num(m["ChanceOrQuestChance"]) for m in members if num(m["ChanceOrQuestChance"]) > 0)
            equal = [m for m in members if num(m["ChanceOrQuestChance"]) == 0]
            share = max(0.0, 100.0 - explicit) / len(equal) if equal else 0.0
        for m in members:
            raw = num(m["ChanceOrQuestChance"])
            if raw < 0:
                continue  # quest-only drop
            chance = raw if (raw > 0 or not group) else share
            if chance <= 0:
                continue
            low, high = int(num(m["mincountOrRef"])), int(num(m["maxcount"], 1))
            if low < 0:
                if depth < MAX_DEPTH:
                    expected_items(-low, creature_loot, reference_loot, depth + 1,
                                   scale * chance / 100.0 * max(1, high), out)
                continue
            item = int(m["item"])
            count = (max(1, low) + max(1, high, low)) / 2.0
            p = scale * chance / 100.0
            old_p, old_n = out.get(item, (0.0, 0.0))
            out[item] = (min(1.0, old_p + p), old_n + p * count)
    return out


# ---- Zones -------------------------------------------------------------------------

def zone_finder(assignments, ui_maps, map_names, labelled=()):
    """A function (map, x, y) -> (zone name, map x %, map y %, dungeon?).

    Zone maps are rectangles that overlap at their edges, and the real borders aren't in any
    open data. So when a spot is inside several, it takes the zone most of the nearest spots
    with a known zone have (quest givers and quest targets, whose quest names its zone). With
    none nearby, the zone whose map it sits most centrally on wins.
    """
    zones = []
    names = {int(r["ID"]): r["Name_lang"] for r in ui_maps}
    kinds = {int(r["ID"]): int(num(r["Type"])) for r in ui_maps}
    for r in assignments:
        ui = int(r["UiMapID"])
        if kinds.get(ui) != ZONE_TYPE:
            continue
        min_x, min_y, max_x, max_y = (num(r[k]) for k in ("Region_0", "Region_1", "Region_3", "Region_4"))
        if max_x <= min_x or max_y <= min_y:
            continue
        zones.append((int(num(r["MapID"])), min_x, min_y, max_x, max_y, (max_x - min_x) * (max_y - min_y), names.get(ui, "")))

    grid = defaultdict(list)
    levels = defaultdict(list)
    for map_id, x, y, name, level in labelled:
        grid[(map_id, int(x // CELL), int(y // CELL))].append((x, y, name))
        if level:
            levels[name].append(level)
    usual = {name: sorted(v)[len(v) // 2] for name, v in levels.items()}

    def vote(map_id, x, y, allowed):
        cx, cy = int(x // CELL), int(y // CELL)
        for reach in (1, 2, 4):
            near = []
            for i in range(cx - reach, cx + reach + 1):
                for j in range(cy - reach, cy + reach + 1):
                    for px, py, name in grid.get((map_id, i, j), ()):
                        if name in allowed:
                            near.append(((px - x) ** 2 + (py - y) ** 2, name))
            if len(near) >= 3 or reach == 4:
                break
        if not near:
            return None
        near.sort()
        score = Counter()
        for d2, name in near[:NEIGHBOURS]:
            score[name] += 1.0 / (d2 ** 0.5 + 20)
        return score.most_common(1)[0][0]

    def find(map_id, x, y, level=None, prefer_city=False):
        inside = [z for z in zones if z[0] == map_id and z[1] <= x <= z[3] and z[2] <= y <= z[4]]
        cities = [z for z in inside if z[6] in CITIES]
        if prefer_city and cities:
            _, min_x, min_y, max_x, max_y, _, name = min(cities, key=lambda z: z[5])
            return name, round((max_y - y) / (max_y - min_y) * 100, 1), round((max_x - x) / (max_x - min_x) * 100, 1), False
        # Monsters: a city map's edges overlap the zone around it, where they really are.
        outside_cities = [z for z in inside if z[6] not in CITIES] or inside
        if level and len(outside_cities) > 1:
            fitting = [z for z in outside_cities if z[6] not in usual or abs(usual[z[6]] - level) <= LEVEL_GAP]
            outside_cities = fitting or outside_cities
        best = None
        if len(outside_cities) > 1:
            name = vote(map_id, x, y, {z[6] for z in outside_cities})
            best = next((z for z in outside_cities if z[6] == name), None)
        if best is None and outside_cities:
            def central(z):
                u = (x - z[1]) / (z[3] - z[1]) - 0.5
                v = (y - z[2]) / (z[4] - z[2]) - 0.5
                return u * u + v * v
            best = min(outside_cities, key=central)
        if best:
            _, min_x, min_y, max_x, max_y, _, name = best
            return name, round((max_y - y) / (max_y - min_y) * 100, 1), round((max_x - x) / (max_x - min_x) * 100, 1), False
        if map_id in map_names:
            return map_names[map_id], None, None, True
        return None
    return find


def place_of(spawns, find, level=None):
    """Main zone of a monster's spawns, how many spawn there, and a spot near their middle."""
    by_zone = defaultdict(list)
    for map_id, x, y in spawns:
        if map_id in BATTLEGROUNDS:
            continue
        place = find(map_id, x, y, level)
        if place:
            by_zone[(place[0], place[3])].append((x, y, place[1], place[2]))
    if not by_zone:
        return None
    (zone, dungeon), points = max(by_zone.items(), key=lambda kv: len(kv[1]))
    if dungeon:
        return zone, None, None, len(points), True
    mx = sum(p[0] for p in points) / len(points)
    my = sum(p[1] for p in points) / len(points)
    near = min(points, key=lambda p: (p[0] - mx) ** 2 + (p[1] - my) ** 2)
    return zone, near[2], near[3], len(points), False


# ---- Building --------------------------------------------------------------------

def area_zones(area_rows):
    """{AreaTable ID: top zone name}, rolling sub-areas up to their zone."""
    parent = {int(r["ID"]): int(num(r["ParentAreaID"])) for r in area_rows}
    name = {int(r["ID"]): r["AreaName_lang"] for r in area_rows}
    out = {}
    for area in parent:
        top, hops = area, 0
        while parent.get(top) and hops < 6:
            top, hops = parent[top], hops + 1
        out[area] = name.get(top, "")
    return out


def labelled_spots(tables, zone_of_area):
    """(map, x, y, zone, level) for spawns of quest givers, quest enders and quest targets.
    Only quest targets carry a level: givers in towns are often far above the zone's monsters."""
    zone_of_quest = {}
    targets = defaultdict(set)
    for r in as_dicts(tables["quest_template"]):
        area = int(num(r.get("ZoneOrSort")))
        if area > 0 and zone_of_area.get(area):
            quest = int(r["entry"])
            zone_of_quest[quest] = zone_of_area[area]
            for k in range(1, 5):
                target = int(num(r.get(f"ReqCreatureOrGOId{k}")))
                if target > 0:
                    targets[target].add(zone_of_area[area])
    killed = set(targets)
    for table in ("creature_questrelation", "creature_involvedrelation"):
        for r in as_dicts(tables[table]):
            zone = zone_of_quest.get(int(num(r["quest"])))
            if zone:
                targets[int(num(r["id"]))].add(zone)
    level_of = {int(r["Entry"]): (num(r["MinLevel"]) + num(r["MaxLevel"])) / 2 for r in as_dicts(tables["creature_template"])}
    spots = []
    for r in as_dicts(tables["creature"]):
        entry = int(r["id"])
        zones = targets.get(entry)
        if zones and len(zones) == 1:
            spots.append((int(num(r["map"])), num(r["position_x"]), num(r["position_y"]), next(iter(zones)),
                          level_of.get(entry) if entry in killed else None))
    return spots


def build(tables, tradable, find, commit):
    templates = {int(r["Entry"]): r for r in as_dicts(tables["creature_template"])}
    spawns = defaultdict(list)
    for r in as_dicts(tables["creature"]):
        spawns[int(r["id"])].append((int(num(r["map"])), num(r["position_x"]), num(r["position_y"])))
    creature_loot = loot_index(as_dicts(tables["creature_loot_template"]))
    reference_loot = loot_index(as_dicts(tables["reference_loot_template"]))

    quests = []
    needed_by = defaultdict(list)
    for r in as_dicts(tables["quest_template"]):
        title = (r.get("Title") or "").strip()
        if not title or SKIP_TITLE.search(title):
            continue
        for k in range(1, 5):
            item, count = int(num(r.get(f"ReqItemId{k}"))), int(num(r.get(f"ReqItemCount{k}")))
            if item and count and str(item) in tradable:
                if not needed_by[item] or needed_by[item][-1][0] != len(quests):
                    needed_by[item].append((len(quests), count))
        if any(int(num(r.get(f"ReqItemId{k}"))) and str(int(num(r.get(f"ReqItemId{k}")))) in tradable for k in range(1, 5)):
            quests.append([title, int(num(r.get("QuestLevel"))), int(num(r.get("MinLevel")))])
    drops = defaultdict(list)
    places = {}
    for entry, t in templates.items():
        loot_id = int(num(t.get("LootId")))
        if not loot_id or not spawns.get(entry):
            continue
        for item, (chance, expected) in expected_items(loot_id, creature_loot, reference_loot).items():
            if str(item) not in tradable:
                continue
            pct = chance * 100
            if pct < (MIN_QUEST_CHANCE if item in needed_by else MIN_CHANCE):
                continue
            drops[item].append((entry, pct, expected))

    creatures, creature_index = [], {}
    items = {}
    for item, sources in drops.items():
        sources.sort(key=lambda s: (-s[2], -len(spawns[s[0]])))
        kept = []
        for entry, pct, expected in sources:
            if entry not in creature_index:
                place = places.get(entry)
                if entry not in places:
                    t = templates[entry]
                    place = places[entry] = place_of(spawns[entry], find, (num(t["MinLevel"]) + num(t["MaxLevel"])) / 2)
                if not place:
                    continue
                t = templates[entry]
                zone, x, y, count, dungeon = place
                creature_index[entry] = len(creatures)
                creatures.append([t["Name"], int(num(t["MinLevel"])), int(num(t["MaxLevel"])),
                                  RANKS.get(int(num(t["Rank"])), ""), zone, x, y, count, 1 if dungeon else 0, entry])
            kept.append([creature_index[entry], round(pct, 2), round(expected, 4)])
            if len(kept) >= SOURCES_PER_ITEM:
                break
        if kept:
            items[str(item)] = {"d": kept, "n": len(sources)}
    for item, needs in needed_by.items():
        row = items.setdefault(str(item), {"d": [], "n": 0})
        row["q"] = [[q, c] for q, c in needs[:QUESTS_PER_ITEM]]
        row["qn"] = len(needs)
    return {
        "source": {"db": DB_REPO, "commit": commit, "file": DB_FILE},
        "columns": {"creature": ["name", "minLevel", "maxLevel", "rank", "zone", "x", "y", "spawns", "dungeon", "id"],
                    "drop": ["creature", "chance %", "expected per kill"], "quest": ["title", "level", "minLevel"]},
        "creatures": creatures,
        "quests": quests,
        "items": items,
    }


def fetch(url, path=None, binary=False):
    if path and path.exists():
        return path.read_bytes() if binary else path.read_text(encoding="utf-8")
    request = urllib.request.Request(url, headers={"User-Agent": AGENT})
    with urllib.request.urlopen(request, timeout=300) as response:
        data = response.read()
    if path:
        path.write_bytes(data)
    return data if binary else data.decode("utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cache", type=Path, help="folder to keep downloads in")
    parser.add_argument("--commit", help="classic-db commit (default: newest)")
    parser.add_argument("--build", help="Forever client build for the map tables (default: catalog build)")
    args = parser.parse_args()
    cache = args.cache
    if cache:
        cache.mkdir(parents=True, exist_ok=True)
    commit = args.commit or json.loads(fetch(f"https://api.github.com/repos/{DB_REPO}/commits/master"))["sha"]
    raw = fetch(f"https://raw.githubusercontent.com/{DB_REPO}/{commit}/{DB_FILE}", cache / f"classicdb-{commit[:10]}.sql.gz" if cache else None, binary=True)
    tables = read_dump(gzip.decompress(raw).decode("utf-8", errors="replace"))
    build_name = args.build or json.loads((ROOT / "site" / "catalog.json").read_text(encoding="utf-8"))["build"]

    def table(name):
        text = fetch(f"{WAGO}/db2/{name}/csv?build={build_name}", cache / f"{name}-{build_name}.csv" if cache else None)
        return list(csv.DictReader(text.splitlines()))
    map_names = {int(r["ID"]): r["MapName_lang"] for r in table("Map")}
    spots = labelled_spots(tables, area_zones(table("AreaTable")))
    find = zone_finder(table("UiMapAssignment"), table("UiMap"), map_names, spots)
    tradable = json.loads((ROOT / "site" / "all_items.json").read_text(encoding="utf-8"))
    farm = build(tables, tradable, find, commit)
    out = ROOT / "site" / "farm.json"
    out.write_text(json.dumps(farm, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    print(f"farm.json: {len(farm['items'])} items, {len(farm['creatures'])} monsters, {len(farm['quests'])} quests, {out.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
