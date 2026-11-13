#!/usr/bin/env python3
"""Build catalog/zone_guide.json: per zone, the quests, the quests started by a dropped item,
the rare monsters and the monsters whose drops are worth the most, for the addon's Zone tab.

Quests, monsters, spawns and loot come from the CMaNGOS Classic 1.12 world database (the same
dump as build_farm.py); zones and map coordinates from the Forever client's map tables. Forever
may differ, so the addon labels these as Classic estimates.

    python catalog/build_zone_guide.py [--cache DIR] [--commit SHA]
"""
import argparse
import csv
import gzip
import json
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_farm  # noqa: E402
from build_farm import as_dicts, num  # noqa: E402
from build_leveling_sources import side_of  # noqa: E402

TABLES = build_farm.TABLES + ("item_template", "gameobject_questrelation", "gameobject", "gameobject_template")
ALLIANCE_RACES, HORDE_RACES = 1 | 4 | 8 | 64, 2 | 16 | 32 | 128
RARE_RANKS = {2: "rare elite", 4: "rare"}
ELITE_RANKS = {1, 2, 3}
REPEATABLE = 1  # SpecialFlags
QUEST_TYPES = {1: "group", 21: "life", 41: "pvp", 62: "raid", 81: "dungeon", 83: "legendary"}
XP_PER_MAX_LEVEL_MONEY = 1 / 0.6  # Classic: at level 60 a quest pays RewMoneyMaxLevel instead of its XP, about 60% of it
MIN_DROP_CHANCE = 1.0  # percent, for rare monsters' notable drops
DROPS_PER_MOB = 5
# Inventory types you wear (no shirts, tabards, bags, ammo or quivers).
WEARABLE = {1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 20, 21, 22, 23, 25, 26, 28}
LIMITS = {"quests": 400, "starters": 40, "rares": 40, "mobs": 50}
MIN_EXPECTED = 0.005  # drops per kill: rarer ones (bags at 0.1%) say little about what a kill is worth


def side_of_races(mask):
    mask = int(mask or 0)
    if not mask or (mask & ALLIANCE_RACES and mask & HORDE_RACES):
        return ""
    return "A" if mask & ALLIANCE_RACES else "H"


def build(tables, wago, commit):
    zone_of_area = build_farm.area_zones(wago["AreaTable"])
    spots = build_farm.labelled_spots(tables, zone_of_area)
    find = build_farm.zone_finder(wago["UiMapAssignment"], wago["UiMap"], {int(r["ID"]): r["MapName_lang"] for r in wago["Map"]}, spots)

    def find_npc(map_id, x, y, level=None):
        return find(map_id, x, y, level, prefer_city=True)
    factions = {int(r["ID"]): r for r in wago["FactionTemplate"]}
    templates = {int(r["Entry"]): r for r in as_dicts(tables["creature_template"])}
    spawns = defaultdict(list)
    for r in as_dicts(tables["creature"]):
        spawns[int(r["id"])].append((int(num(r["map"])), num(r["position_x"]), num(r["position_y"])))
    object_spawns = defaultdict(list)
    for r in as_dicts(tables["gameobject"]):
        object_spawns[int(r["id"])].append((int(num(r["map"])), num(r["position_x"]), num(r["position_y"])))
    object_names = {int(r["entry"]): r.get("name") or "" for r in as_dicts(tables["gameobject_template"])}
    items = {int(r["entry"]): r for r in as_dicts(tables["item_template"])}
    creature_loot = build_farm.loot_index(as_dicts(tables["creature_loot_template"]))
    reference_loot = build_farm.loot_index(as_dicts(tables["reference_loot_template"]))

    places = {}

    def place(entry, npc=True):
        key = (entry, npc)
        if key not in places:
            t = templates.get(entry) if npc else None
            level = (num(t["MinLevel"]) + num(t["MaxLevel"])) / 2 if t else None
            where = spawns.get(entry) if npc else object_spawns.get(entry)
            places[key] = build_farm.place_of(where, find_npc if npc else find, level) if where else None
        return places[key]

    zones = defaultdict(lambda: {"quests": [], "starters": [], "rares": [], "mobs": []})
    used_items = set()

    # Quests, at their giver (a creature or an object), or the quest's own zone.
    givers = defaultdict(list)
    for r in as_dicts(tables["creature_questrelation"]):
        givers[int(num(r["quest"]))].append((int(num(r["id"])), True))
    for r in as_dicts(tables["gameobject_questrelation"]):
        givers[int(num(r["quest"]))].append((int(num(r["id"])), False))
    starter_items = {}
    for item_id, it in items.items():
        q = int(num(it.get("startquest")))
        if q:
            starter_items[q] = item_id
    quest_rows = {}
    for r in as_dicts(tables["quest_template"]):
        title = (r.get("Title") or "").strip()
        if not title or build_farm.SKIP_TITLE.search(title) or int(num(r.get("SpecialFlags"))) & REPEATABLE:
            continue
        if int(num(r.get("RequiredSkill"))) or int(num(r.get("ZoneOrSort"))) < 0 and not int(num(r.get("RequiredClasses"))):
            continue  # profession and holiday quests
        entry = int(r["entry"])
        quest_rows[entry] = r
        reward, quality = 0, 0
        for k in list(range(1, 7)) + [None] * 0:
            item = int(num(r.get(f"RewChoiceItemId{k}")))
            q = int(num(items.get(item, {}).get("Quality"))) if item else 0
            if item and q > quality:
                reward, quality = item, q
        for k in range(1, 5):
            item = int(num(r.get(f"RewItemId{k}")))
            q = int(num(items.get(item, {}).get("Quality"))) if item else 0
            if item and q > quality:
                reward, quality = item, q
        if reward:
            used_items.add(reward)
        # Every reward you can wear (choices and fixed), for the gear advice: equipment slots only.
        gear = []
        for key in [f"RewChoiceItemId{k}" for k in range(1, 7)] + [f"RewItemId{k}" for k in range(1, 5)]:
            item = int(num(r.get(key)))
            if item and int(num(items.get(item, {}).get("InventoryType"))) in WEARABLE:
                gear.append(item)
        used_items.update(gear)
        side = side_of_races(r.get("RequiredRaces"))
        giver_name, x, y, zone = "", None, None, None
        for giver, npc in givers.get(entry, []):
            p = place(giver, npc)
            if p and not p[4]:
                zone, x, y = p[0], p[1], p[2]
                if npc and giver in templates:
                    giver_name = templates[giver]["Name"]
                    side = side or side_of(factions.get(int(num(templates[giver]["Faction"]))))
                else:
                    giver_name = object_names.get(giver, "")
                break
        starter = starter_items.get(entry)
        if not zone and not starter:
            area = int(num(r.get("ZoneOrSort")))
            zone = zone_of_area.get(area) if area > 0 else None
        row = [entry, title, int(num(r.get("QuestLevel"))), int(num(r.get("MinLevel"))), side,
               int(int(num(r.get("RewMoneyMaxLevel"))) * XP_PER_MAX_LEVEL_MONEY), int(num(r.get("RewOrReqMoney"))),
               reward, giver_name, x, y, QUEST_TYPES.get(int(num(r.get("Type"))), ""),
               int(num(r.get("RequiredClasses"))), int(num(r.get("PrevQuestId"))), gear]
        if zone and not starter:
            zones[zone]["quests"].append(row)

    # Monsters: rares with their notable drops, quest-starting drops, and what each kill is worth.
    for entry, t in templates.items():
        loot_id = int(num(t.get("LootId")))
        if not spawns.get(entry):
            continue
        p = place(entry)
        if not p or p[4]:
            continue  # dungeons are left out
        zone, x, y, count, _ = p
        drops = build_farm.expected_items(loot_id, creature_loot, reference_loot) if loot_id else {}
        low, high, rank = int(num(t["MinLevel"])), int(num(t["MaxLevel"])), int(num(t["Rank"]))
        for item, (chance, _) in drops.items():
            q = int(num(items.get(item, {}).get("startquest")))
            if q and q in quest_rows and chance * 100 >= 0.5:
                r = quest_rows[q]
                zones[zone]["starters"].append([item, items[item]["name"], q, r["Title"].strip(), int(num(r.get("QuestLevel"))),
                                                 int(num(r.get("MinLevel"))), side_of_races(r.get("RequiredRaces")),
                                                 t["Name"], low, high, round(chance * 100, 1), x, y])
        tradable = [(item, chance, expected) for item, (chance, expected) in drops.items()
                    if item in items and not int(num(items[item].get("startquest"))) and int(num(items[item].get("bonding"))) not in (1, 4)]
        if rank in RARE_RANKS:
            notable = sorted([(i, c) for i, c, _ in tradable if c * 100 >= MIN_DROP_CHANCE and int(num(items[i].get("Quality"))) >= 2],
                             key=lambda d: -d[1])[:DROPS_PER_MOB]
            used_items.update(i for i, _ in notable)
            zones[zone]["rares"].append([t["Name"], low, high, RARE_RANKS[rank], x, y, [[i, round(c * 100, 1)] for i, c in notable]])
        elif rank not in ELITE_RANKS and count >= 5 and tradable:
            common = [d for d in tradable if d[2] >= MIN_EXPECTED]
            best = sorted(common, key=lambda d: -d[2] * max(1, int(num(items[d[0]].get("SellPrice")))))[:DROPS_PER_MOB]
            if not best:
                continue
            used_items.update(i for i, _, _ in best)
            zones[zone]["mobs"].append([t["Name"], low, high, x, y, count, [[i, round(e, 4)] for i, _, e in best]])

    out = {}
    for zone, z in zones.items():
        z["quests"].sort(key=lambda q: (q[2], q[0]))
        z["starters"].sort(key=lambda s: (s[4], -s[10]))
        z["rares"].sort(key=lambda r: r[1])
        z["mobs"].sort(key=lambda m: -m[5])
        out[zone] = {k: v[:LIMITS[k]] for k, v in z.items()}
    for zone in out.values():
        for s in zone["starters"]:
            used_items.add(s[0])
    item_info = {str(i): [items[i]["name"], int(num(items[i].get("Quality"))), int(num(items[i].get("SellPrice")))]
                 for i in sorted(used_items) if i in items}
    return {
        "source": {"db": build_farm.DB_REPO, "commit": commit},
        "columns": {
            "quest": ["id", "title", "level", "minLevel", "side", "xp", "money", "rewardItem", "giver", "x", "y", "type", "classes", "prevQuest", "gearRewards"],
            "starter": ["item", "itemName", "quest", "title", "level", "minLevel", "side", "dropper", "minLevel", "maxLevel", "chance %", "x", "y"],
            "rare": ["name", "minLevel", "maxLevel", "rank", "x", "y", "drops [item, chance %]"],
            "mob": ["name", "minLevel", "maxLevel", "x", "y", "spawns", "drops [item, expected per kill]"],
            "item": ["name", "quality", "vendor sell price"],
        },
        "zones": out,
        "items": item_info,
    }


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
    wago = {name: table(name) for name in ("UiMapAssignment", "UiMap", "Map", "AreaTable", "FactionTemplate")}
    data = build(tables, wago, commit)
    path = ROOT / "catalog" / "zone_guide.json"
    path.write_text(json.dumps(data, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    z = data["zones"]
    print(f"zone_guide.json: {len(z)} zones, {sum(len(v['quests']) for v in z.values())} quests, "
          f"{sum(len(v['starters']) for v in z.values())} item-started quests, {sum(len(v['rares']) for v in z.values())} rares, "
          f"{sum(len(v['mobs']) for v in z.values())} monsters, {len(data['items'])} items, {path.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
