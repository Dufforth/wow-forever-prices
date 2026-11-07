#!/usr/bin/env python3
"""Build site/catalog.json and site/gear.json from the WoW Forever client's own tables.

wago.tools publishes each client table (DB2) as CSV. From them this keeps every
profession recipe with a created item, its reagents, and the item facts the page needs.

    python catalog/build_catalog.py [--cache DIR] [--build 1.60.1.70862]

Run it again after a game patch. Without --build it uses the newest Forever build.
"""
import argparse
import csv
import json
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SITE = "https://wago.tools"
AGENT = "wow-forever-prices (personal price page)"
TABLES = ("SkillLineAbility", "SpellReagents", "SpellEffect", "SpellName", "ItemSparse", "Item")
CREATE_ITEM = 24

PROFESSIONS = {
    171: "Alchemy", 164: "Blacksmithing", 185: "Cooking", 333: "Enchanting", 202: "Engineering",
    129: "First Aid", 165: "Leatherworking", 186: "Mining", 197: "Tailoring",
}
WEAPON, ARMOR, TRADESKILL = 2, 4, 7
NEVER_DISENCHANT_SLOTS = {4, 19}  # shirt, tabard
ENCHANT_MATERIALS = {
    10940, 10938, 10939, 10978, 10998, 11082, 11083, 11084, 11134, 11135, 11137, 11138, 11139,
    11174, 11175, 11176, 11177, 11178, 16202, 16203, 16204, 14343, 14344, 20725,
}
# Reagents trade-goods vendors sell without limit. The game tables have no vendor list.
VENDOR_REAGENTS = {
    2880, 3466, 2320, 2321, 4291, 8343, 14341, 3371, 3372, 8925, 18256, 4289, 2678, 2692, 3713, 2665,
    159, 1179, 6217, 3857, 4470, 4399, 4400, 2324, 2325, 2604, 6260, 6261, 4340, 4341, 4342, 10290,
}


def read_table(name, build, cache):
    path = cache / f"{name}.csv" if cache else None
    if path and path.exists():
        text = path.read_text(encoding="utf-8")
    else:
        url = f"{SITE}/db2/{name}/csv?build={build}&hotfixes=true"
        request = urllib.request.Request(url, headers={"User-Agent": AGENT})
        with urllib.request.urlopen(request, timeout=300) as response:
            text = response.read().decode("utf-8")
        if path:
            path.write_text(text, encoding="utf-8")
    return list(csv.DictReader(text.splitlines()))


def newest_build():
    request = urllib.request.Request(f"{SITE}/api/builds", headers={"User-Agent": AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)["wowf"][0]["version"]


def number(row, column, default=0):
    try:
        return int(float(row.get(column) or default))
    except ValueError:
        return default


def gather_group(item_id, item, nodes):
    if item_id in ENCHANT_MATERIALS:
        return "enchant"
    if nodes.get(str(item_id)):
        return nodes[str(item_id)]
    if item["cl"] != TRADESKILL:
        return None
    return {5: "cloth", 6: "leather", 7: "ore", 9: "herb", 12: "enchant"}.get(item["sc"])


def build(tables, build_name, nodes):
    item_class = {number(r, "ID"): r for r in tables["Item"]}
    items = {}
    for row in tables["ItemSparse"]:
        item_id = number(row, "ID")
        base = item_class.get(item_id, {})
        stack = max(number(row, "VendorStackCount", 1), 1)
        items[item_id] = {
            "n": row.get("Display_lang", ""),
            "q": number(row, "OverallQualityID"),
            "il": number(row, "ItemLevel"),
            "rl": number(row, "RequiredLevel"),
            "sell": number(row, "SellPrice"),
            "buy": number(row, "BuyPrice") / stack,
            "cl": number(base, "ClassID"),
            "sc": number(base, "SubclassID"),
            "inv": number(row, "InventoryType"),
            "bop": 1 if number(row, "Bonding") == 1 else 0,
        }

    reagents = {}
    for row in tables["SpellReagents"]:
        pairs = []
        for slot in range(8):
            item_id, count = number(row, f"Reagent_{slot}"), number(row, f"ReagentCount_{slot}")
            if item_id > 0 and count > 0:
                pairs.append([item_id, count])
        if pairs:
            reagents[number(row, "SpellID")] = pairs

    created = {}
    for row in tables["SpellEffect"]:
        if number(row, "Effect") == CREATE_ITEM and number(row, "EffectItemType") > 0:
            spell = number(row, "SpellID")
            created.setdefault(spell, (number(row, "EffectItemType"), max(number(row, "EffectBasePointsF", 1), 1)))

    names = {number(r, "ID"): r.get("Name_lang", "") for r in tables["SpellName"]}

    recipes = {}
    for row in tables["SkillLineAbility"]:
        skill_line, spell = number(row, "SkillLine"), number(row, "Spell")
        if skill_line not in PROFESSIONS or spell in recipes:
            continue
        product = created.get(spell)
        if not product or spell not in reagents or product[0] not in items:
            continue
        if any(pair[0] not in items for pair in reagents[spell]):
            continue
        recipes[spell] = {
            "s": spell, "n": names.get(spell) or items[product[0]]["n"], "p": PROFESSIONS[skill_line],
            "sk": number(row, "MinSkillLineRank"), "i": product[0], "c": product[1], "r": reagents[spell],
        }

    wanted = set(ENCHANT_MATERIALS) | {int(k) for k in nodes}
    for recipe in recipes.values():
        wanted.add(recipe["i"])
        wanted.update(pair[0] for pair in recipe["r"])

    catalog_items = {}
    for item_id in sorted(wanted):
        item = items.get(item_id)
        if not item or not item["n"]:
            continue
        row = dict(item)
        group = gather_group(item_id, item, nodes)
        if group:
            row["g"] = group
        if item_id in VENDOR_REAGENTS and item["buy"] > 0:
            row["v"] = 1
        catalog_items[item_id] = row

    gear = {}
    for item_id, item in items.items():
        if (item["cl"] in (WEAPON, ARMOR) and 2 <= item["q"] <= 4 and item["il"] > 0 and item["n"]
                and item["inv"] not in NEVER_DISENCHANT_SLOTS and not item["bop"]):
            gear[item_id] = {"n": item["n"], "q": item["q"], "il": item["il"], "cl": item["cl"]}

    catalog = {
        "build": build_name,
        "items": catalog_items,
        "recipes": sorted(recipes.values(), key=lambda r: (r["p"], r["sk"], r["n"])),
    }
    return catalog, gear


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path)
    parser.add_argument("--build")
    args = parser.parse_args()
    build_name = args.build or newest_build()
    tables = {name: read_table(name, build_name, args.cache) for name in TABLES}
    nodes = json.loads((ROOT / "catalog/gather_items.json").read_text(encoding="utf-8"))
    catalog, gear = build(tables, build_name, nodes)
    out = ROOT / "site"
    (out / "catalog.json").write_text(json.dumps(catalog, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    (out / "gear.json").write_text(json.dumps(gear, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    print(f"build {build_name}: {len(catalog['recipes'])} recipes, {len(catalog['items'])} items, {len(gear)} gear items")


if __name__ == "__main__":
    main()
