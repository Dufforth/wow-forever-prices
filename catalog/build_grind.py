"""Build catalog/grind.json: places in the open world worth killing monsters for experience and gold.

Run by hand (like build_farm.py), with the same CMaNGOS classic-db dump and Forever map tables:
    python catalog/build_grind.py --cache <folder> --commit c33f90b8eeb3f8bacb53d5cbfee45075c80b416c

A spot is a group of spawns of similar level close together. For each one it keeps where it is,
the levels, how many spawn and how far apart (kills per hour depend on it), how fast they come
back, whether they cast, heal, run away or are elite, the coin and vendor value per kill and the
drops worth checking on the auction house. Experience per kill and time to level are worked out
in the game from your own level, class and spec (Grind.lua), so the file holds no player numbers.
Classic data: Forever may differ.
"""
import argparse
import csv
import gzip
import json
import math
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_farm  # noqa: E402
from build_farm import as_dicts, num  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
TABLES = ("creature_template", "creature", "creature_loot_template", "reference_loot_template", "item_template",
          "creature_ai_scripts", "creature_template_spells", "creature_spell_list", "game_event_creature")
CONTINENTS = {0, 1}            # Eastern Kingdoms, Kalimdor: dungeons and battlegrounds are left out
LINK = 45                      # yards: spawns this close belong to the same spot
LEVEL_BAND = 3                 # levels: only spawns in the same band of levels join (no chains from 6 to 18)
TILE = 400                     # yards: a spot spread wider than this is cut into tiles
MIN_SPAWNS = 8                 # fewer than this isn't a grind spot
MIN_ELITE_SPAWNS = 5
NEIGHBOUR = 60                 # yards, for picking the spot's centre
MOBS_PER_SPOT = 3
NOTABLE = 4                    # drops per spot shown with their auction price
MIN_EXPECTED = 0.003           # drops per kill: rarer ones say little about a spot's value
PLAYER_GROUPS = 2 | 4          # FactionTemplate group bits: Alliance players 2, Horde players 4
NOT_ATTACKABLE = 0x2 | 0x100 | 0x2000000  # non attackable, immune to players, not selectable
NO_FIGHT_TYPES = {8, 11, 12, 13}          # critter, totem, non-combat pet, gas cloud
ELITE_RANKS = {1, 2, 3}
GUARD = 0x400                  # creature_template.ExtraFlags: town guards (Bruisers, Grunts, City Guards)
SKIP_RANKS = {3, 4}             # bosses and rares: one of a kind, not a grind
MAX_RESPAWN = 1200             # seconds: named monsters that come back slowly aren't a grind either

CASTER, HEALER, FLEES, ELITE, PACK = 1, 2, 4, 8, 16
DAMAGE_SPELL = re.compile(r"bolt|fireball|blast|shock|lightning|smite|missile|nova|immolat|corruption|curse|"
                          r"flame|frost|shadow word|mind flay|holy fire|starfire|wrath|moonfire|scorch|pyro|"
                          r"chain|drain|siphon|arcane|hex|poison bolt|acid spit|venom spit", re.I)
HEAL_SPELL = re.compile(r"\bheal|renew|rejuvenation|holy light|flash of light|lesser heal|regrowth|"
                        r"healing wave|mend", re.I)
PACK_GAP = 12                  # yards: monsters standing this close usually come together


# ---- Pure parts (tested) -------------------------------------------------------------

def attackable(t, factions):
    if int(num(t.get("NpcFlags"))) or int(num(t.get("CreatureType"))) in NO_FIGHT_TYPES:
        return False
    if int(num(t.get("UnitFlags"))) & NOT_ATTACKABLE or int(num(t.get("ExtraFlags"))) & GUARD or num(t.get("MinLevel")) < 1:
        return False
    if num(t.get("ExperienceMultiplier"), 1) <= 0:
        return False
    f = factions.get(int(num(t.get("Faction"))))
    if f and (int(num(f.get("FactionGroup"))) & PLAYER_GROUPS or int(num(f.get("FriendGroup"))) & PLAYER_GROUPS):
        return False  # a side's own people: guards, townsfolk
    return True


def mob_flags(t, spell_names, behaviour):
    flags = 0
    if int(num(t.get("UnitClass"))) == 8 or any(DAMAGE_SPELL.search(n) for n in spell_names):
        flags |= CASTER
    if any(HEAL_SPELL.search(n) for n in spell_names):
        flags |= HEALER
    if "flee" in behaviour:
        flags |= FLEES
    if int(num(t.get("Rank"))) in ELITE_RANKS:
        flags |= ELITE
    return flags


def loot_value(drops, items, coin=0.0):
    """(vendor copper per kill incl. coin, [[item, expected per kill] notable drops]).

    Gray and bound items count at what a vendor pays. Tradable white and better drops are kept
    apart: the game checks their auction price (it changes hourly) and uses the better of the two.
    """
    vendor, notable = float(coin), []
    for item, (_, expected) in drops.items():
        row = items.get(item)
        if not row or expected < MIN_EXPECTED * 0.1:
            continue
        sell = num(row.get("SellPrice"))
        quality, bonding = int(num(row.get("Quality"))), int(num(row.get("bonding")))
        if bonding == 4:
            continue  # quest item
        if quality == 0 or bonding == 1 or expected < MIN_EXPECTED:
            vendor += expected * sell
        else:
            notable.append([item, expected, sell])
    notable.sort(key=lambda n: -n[1] * max(n[2], 1))
    for _, expected, sell in notable[NOTABLE:]:
        vendor += expected * sell
    return vendor, [[i, e] for i, e, _ in notable[:NOTABLE]]


MOB_COLUMNS = ["name", "minLevel", "maxLevel", "display (model id)", "creature type", "family", "flags",
               "vendor copper per kill incl. coin", "drops [item, expected per kill]"]


def mob_summary(t, flags, vendor, notable):
    """One monster's row: what it looks like (model, type, family), how it fights and what it's worth."""
    display = next((int(num(t.get(f"ModelId{k}"))) for k in range(1, 5) if int(num(t.get(f"ModelId{k}")))), 0)
    return [t["Name"], int(num(t["MinLevel"])), int(num(t["MaxLevel"])), display, int(num(t.get("CreatureType"))),
            int(num(t.get("Family"))), flags, round(vendor, 1), notable]


def _dist(a, b):
    return math.hypot(a["x"] - b["x"], a["y"] - b["y"])


def clusters(spawns):
    """Groups of spawns joined when within LINK yards and in the same level band; wide groups cut into tiles."""
    def band(s):
        return int(s["level"] // LEVEL_BAND)
    grid = defaultdict(list)
    for i, s in enumerate(spawns):
        grid[(s["map"], int(s["x"] // LINK), int(s["y"] // LINK))].append(i)
    parent = list(range(len(spawns)))

    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for (m, cx, cy), members in grid.items():
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for j in grid.get((m, cx + dx, cy + dy), ()):
                    for i in members:
                        if i < j and band(spawns[i]) == band(spawns[j]) and _dist(spawns[i], spawns[j]) <= LINK:
                            parent[root(i)] = root(j)
    groups = defaultdict(list)
    for i in range(len(spawns)):
        groups[root(i)].append(spawns[i])
    out = []
    for g in groups.values():
        xs, ys = [s["x"] for s in g], [s["y"] for s in g]
        if max(xs) - min(xs) <= TILE and max(ys) - min(ys) <= TILE:
            out.append(g)
            continue
        x0, y0 = min(xs), min(ys)
        tiles = defaultdict(list)
        for s in g:
            tiles[(int((s["x"] - x0) // TILE), int((s["y"] - y0) // TILE))].append(s)
        out.extend(tiles.values())
    return out


def nearest_gap(group):
    """Median distance from each spawn to its nearest neighbour, in yards."""
    if len(group) < 2:
        return 0.0
    gaps = sorted(min(_dist(a, b) for b in group if b is not a) for a in group)
    return gaps[len(gaps) // 2]


def centre(group):
    def key(a):
        near = [_dist(a, b) for b in group if _dist(a, b) <= NEIGHBOUR]
        return len(near), -sum(near)
    return max(group, key=key)


# ---- Building ----------------------------------------------------------------------

def creature_spells(tables, spell_name):
    """{creature entry: [spell names]} from its scripts and spell lists, and {entry: {"flee"}}."""
    spells, behaviour = defaultdict(list), defaultdict(set)
    for r in as_dicts(tables["creature_ai_scripts"]):
        entry = int(num(r["creature_id"]))
        for k in (1, 2, 3):
            kind = int(num(r.get(f"action{k}_type")))
            if kind == 11:
                name = spell_name.get(int(num(r.get(f"action{k}_param1"))))
                if name:
                    spells[entry].append(name)
            elif kind == 25:
                behaviour[entry].add("flee")
    for r in as_dicts(tables["creature_template_spells"]):
        entry = int(num(r["entry"]))
        for k in range(1, 11):
            name = spell_name.get(int(num(r.get(f"spell{k}"))))
            if name:
                spells[entry].append(name)
    lists = defaultdict(list)
    for r in as_dicts(tables["creature_spell_list"]):
        name = spell_name.get(int(num(r.get("SpellId"))))
        if name:
            lists[int(num(r["Id"]))].append(name)  # creature_template.SpellList points here
    return spells, behaviour, lists


def build(tables, factions, spell_name, find, commit):
    templates = {int(r["Entry"]): r for r in as_dicts(tables["creature_template"])}
    items = {int(r["entry"]): r for r in as_dicts(tables["item_template"])}
    creature_loot = build_farm.loot_index(as_dicts(tables["creature_loot_template"]))
    reference_loot = build_farm.loot_index(as_dicts(tables["reference_loot_template"]))
    spells, behaviour, lists = creature_spells(tables, spell_name)

    events = {int(num(r["guid"])) for r in as_dicts(tables["game_event_creature"])}  # holiday and invasion spawns
    spawns = []
    for r in as_dicts(tables["creature"]):
        entry, m = int(r["id"]), int(num(r["map"]))
        t = templates.get(entry)
        if int(num(r["guid"])) in events or m not in CONTINENTS or not t or not attackable(t, factions):
            continue
        if int(num(t.get("Rank"))) in SKIP_RANKS or num(r.get("spawntimesecsmin"), 300) > MAX_RESPAWN:
            continue
        spawns.append({"entry": entry, "map": m, "x": num(r["position_x"]), "y": num(r["position_y"]),
                       "level": (num(t["MinLevel"]) + num(t["MaxLevel"])) / 2, "respawn": num(r.get("spawntimesecsmin"), 300)})

    per_mob = {}

    def mob(entry):
        if entry not in per_mob:
            t = templates[entry]
            names = spells.get(entry, []) + lists.get(int(num(t.get("SpellList"))), [])
            loot_id = int(num(t.get("LootId")))
            drops = build_farm.expected_items(loot_id, creature_loot, reference_loot) if loot_id else {}
            coin = (num(t.get("MinLootGold")) + num(t.get("MaxLootGold"))) / 2
            per_mob[entry] = (mob_flags(t, names, behaviour.get(entry, set())), drops, coin)
        return per_mob[entry]

    mobs, mob_index, used = [], {}, set()

    def mob_row(entry):
        """Index (1-based, as in Lua) of a monster in the mobs table, added on first use."""
        if entry not in mob_index:
            t = templates[entry]
            flags, mob_drops, coin = mob(entry)
            vendor, notable = loot_value(mob_drops, items, coin)
            notable = [[i, round(e, 4)] for i, e in notable if e >= MIN_EXPECTED]
            used.update(i for i, _ in notable)
            mobs.append(mob_summary(t, flags, vendor, notable))
            mob_index[entry] = len(mobs)
        return mob_index[entry]

    spots = []
    for group in clusters(spawns):
        counts = Counter(s["entry"] for s in group)
        flags = 0
        for entry in counts:
            flags |= mob(entry)[0]
        if len(group) < (MIN_ELITE_SPAWNS if flags & ELITE else MIN_SPAWNS):
            continue
        c = centre(group)
        place = find(c["map"], c["x"], c["y"], c["level"])
        if not place or place[3] or place[1] is None:
            continue
        gap = nearest_gap(group)
        if gap and gap <= PACK_GAP:
            flags |= PACK
        # Value per kill, weighted by how many of each monster spawn here.
        total = sum(counts.values())
        vendor, drops = 0.0, defaultdict(float)
        for entry, n in counts.items():
            _, mob_drops, coin = mob(entry)
            v, notable = loot_value(mob_drops, items, coin)
            vendor += v * n / total
            for item, e in notable:
                drops[item] += e * n / total
        best = sorted(drops.items(), key=lambda d: -d[1] * max(num(items[d[0]].get("SellPrice")), 1))
        for item, e in best[NOTABLE:]:
            vendor += e * num(items[item].get("SellPrice"))
        best = [[i, round(e, 4)] for i, e in best[:NOTABLE] if e >= MIN_EXPECTED]
        used.update(i for i, _ in best)
        lows = [num(templates[e]["MinLevel"]) for e in counts]
        highs = [num(templates[e]["MaxLevel"]) for e in counts]
        respawns = sorted(s["respawn"] for s in group)
        spots.append([place[0], place[1], place[2], int(min(lows)), int(max(highs)), len(group), round(gap),
                      int(respawns[len(respawns) // 2]), flags, round(vendor, 1),
                      [mob_row(e) for e, _ in counts.most_common(MOBS_PER_SPOT)], best])
    spots.sort(key=lambda s: (s[3], s[0], -s[5]))
    item_info = {str(i): [items[i]["name"], int(num(items[i].get("Quality"))), int(num(items[i].get("SellPrice")))]
                 for i in sorted(used)}
    return {
        "source": {"db": build_farm.DB_REPO, "commit": commit},
        "columns": {"spot": ["zone", "x", "y", "minLevel", "maxLevel", "spawns", "gap yards", "respawn seconds",
                             "flags (1 caster, 2 healer, 4 flees, 8 elite, 16 pack)", "vendor copper per kill incl. coin",
                             "monsters (index in mobs, most common first)", "drops [item, expected per kill]"],
                    "mob": MOB_COLUMNS,
                    "item": ["name", "quality", "vendor sell price"]},
        "spots": spots,
        "mobs": mobs,
        "items": item_info,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cache", type=Path, required=True, help="folder with the downloads (build_farm's cache)")
    parser.add_argument("--commit", required=True, help="classic-db commit")
    parser.add_argument("--build", help="Forever client build for the map tables (default: catalog build)")
    args = parser.parse_args()
    cache = args.cache
    raw = build_farm.fetch(f"https://raw.githubusercontent.com/{build_farm.DB_REPO}/{args.commit}/{build_farm.DB_FILE}",
                           cache / f"classicdb-{args.commit[:10]}.sql.gz", binary=True)
    tables = build_farm.read_dump(gzip.decompress(raw).decode("utf-8", errors="replace"),
                                  TABLES + ("quest_template", "creature_questrelation", "creature_involvedrelation"))
    build_name = args.build or json.loads((ROOT / "site" / "catalog.json").read_text(encoding="utf-8"))["build"]

    def table(name, build=build_name):
        text = build_farm.fetch(f"{build_farm.WAGO}/db2/{name}/csv?build={build}", cache / f"{name}-{build}.csv")
        return list(csv.DictReader(text.splitlines()))
    map_names = {int(r["ID"]): r["MapName_lang"] for r in table("Map")}
    spots = build_farm.labelled_spots(tables, build_farm.area_zones(table("AreaTable")))
    find = build_farm.zone_finder(table("UiMapAssignment"), table("UiMap"), map_names, spots)
    factions = {int(r["ID"]): r for r in table("FactionTemplate")}
    spell_name = {int(r["ID"]): r["Name_lang"] for r in table("SpellName", "1.15.9.70576")}
    data = build(tables, factions, spell_name, find, args.commit)
    out = ROOT / "catalog" / "grind.json"
    out.write_text(json.dumps(data, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    print(f"grind.json: {len(data['spots'])} spots, {len(data['items'])} items, {out.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
