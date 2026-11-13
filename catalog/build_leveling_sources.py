#!/usr/bin/env python3
"""Build catalog/leveling_sources.json: who teaches each recipe, who sells each recipe item, and
the skill where each recipe turns gray.

- Trainers, recipe vendors, their spawns and prices: the CMaNGOS Classic 1.12 database
  (github.com/cmangos/classic-db, GPL-3.0), the same file catalog/build_farm.py reads.
- Gray skill: the Forever client's tables through wago.tools.
- Teaching spell -> recipe: the Classic Era client's tables (Forever's client leaves the
  trainers' teaching spells out), also through wago.tools.

Forever renumbered many recipes, so trainer spells and recipe items are matched to Forever's
recipes by profession and name. Read once and saved in the repo; tools/build_addon_leveling.py
turns it into the addon's Leveling data at deploy time.

    python catalog/build_leveling_sources.py [--cache DIR] [--commit SHA]
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

TABLES = ("creature_template", "creature", "npc_trainer", "npc_trainer_template", "npc_vendor", "npc_vendor_template",
          "item_template", "quest_template", "creature_questrelation", "creature_involvedrelation")
LEARN_SPELL = 36  # SpellEffect: teaches another spell
PROFESSIONS = {
    171: "Alchemy", 164: "Blacksmithing", 185: "Cooking", 333: "Enchanting", 202: "Engineering",
    129: "First Aid", 165: "Leatherworking", 186: "Mining", 197: "Tailoring",
}
ALLIANCE, HORDE = 2, 4  # FactionTemplate group bits
MAX_PLACES = 8  # trainers or vendors kept per recipe


def side_of(template):
    """'A', 'H' or '' (both) from a FactionTemplate row."""
    if not template:
        return ""
    groups = build_farm.num(template["FactionGroup"]) or 0
    friends = build_farm.num(template["FriendGroup"]) or 0
    enemies = build_farm.num(template["EnemyGroup"]) or 0
    mask = int(groups) | int(friends)
    alliance = bool(mask & ALLIANCE) and not int(enemies) & ALLIANCE
    horde = bool(mask & HORDE) and not int(enemies) & HORDE
    if alliance and not horde:
        return "A"
    if horde and not alliance:
        return "H"
    return ""


def build(tables, wago, catalog, commit, classic=""):
    as_dicts = build_farm.as_dicts
    num = build_farm.num
    recipes = catalog["recipes"]
    items = catalog["items"]
    by_name = defaultdict(list)
    for r in recipes:
        by_name[(r["p"], r["n"].lower())].append(r["s"])
    forever_spells = {r["s"] for r in recipes}

    # Gray skill and skill-ups per Forever recipe.
    gray = {}
    for row in wago["SkillLineAbility"]:
        spell = int(num(row["Spell"]))
        if spell in forever_spells:
            gray[str(spell)] = int(num(row["TrivialSkillLineRankHigh"]))

    spell_names = {int(r["ID"]): r["Name_lang"] for r in wago["ClassicSpellName"]}
    spell_names.update({int(r["ID"]): r["Name_lang"] for r in wago["SpellName"]})
    teaches = {}
    for row in wago["ClassicSpellEffect"]:
        if int(num(row["Effect"])) == LEARN_SPELL:
            teaches[int(num(row["SpellID"]))] = int(num(row["EffectTriggerSpell"]))

    def forever_recipe(classic_spell, profession):
        if classic_spell in forever_spells:
            return [classic_spell]
        name = spell_names.get(classic_spell)
        return by_name.get((profession, name.lower()), []) if name else []

    # NPCs: spawns, zone, side.
    find = build_farm.zone_finder(wago["UiMapAssignment"], wago["UiMap"],
                                  {int(r["ID"]): r["MapName_lang"] for r in wago["Map"]},
                                  build_farm.labelled_spots(tables, build_farm.area_zones(wago["AreaTable"])))
    def find_npc(map_id, x, y, level=None):
        return find(map_id, x, y, level, prefer_city=True)
    factions = {int(r["ID"]): r for r in wago["FactionTemplate"]}
    templates = {int(r["Entry"]): r for r in as_dicts(tables["creature_template"])}
    spawns = defaultdict(list)
    for r in as_dicts(tables["creature"]):
        spawns[int(r["id"])].append((int(num(r["map"])), num(r["position_x"]), num(r["position_y"])))
    npcs, npc_index = [], {}

    def npc(entry):
        if entry in npc_index:
            return npc_index[entry]
        t = templates.get(entry)
        # Trainers and vendors: a spot inside a capital's map is in that capital (Karn Stonehoof was put in Desolace).
        place = t and spawns.get(entry) and build_farm.place_of(spawns[entry], find_npc, (num(t["MinLevel"]) + num(t["MaxLevel"])) / 2)
        if not place:
            npc_index[entry] = None
            return None
        zone, x, y, _, _ = place
        npc_index[entry] = len(npcs)
        npcs.append([t["Name"], t.get("SubName") or "", side_of(factions.get(int(num(t["Faction"])))), zone, x, y])
        return npc_index[entry]

    # Trainers: npc_trainer rows by NPC, plus template rows through TrainerTemplateId.
    trainer_rows = defaultdict(list)
    for r in as_dicts(tables["npc_trainer"]):
        trainer_rows[int(r["entry"])].append(r)
    template_rows = defaultdict(list)
    for r in as_dicts(tables["npc_trainer_template"]):
        template_rows[int(r["entry"])].append(r)
    for entry, t in templates.items():
        template = int(num(t.get("TrainerTemplateId")))
        if template:
            trainer_rows[entry].extend(template_rows.get(template, []))
    trainers = defaultdict(list)
    for entry, rows in trainer_rows.items():
        for r in rows:
            profession = PROFESSIONS.get(int(num(r["reqskill"])))
            if not profession:
                continue
            taught = teaches.get(int(num(r["spell"])), int(num(r["spell"])))
            for spell in forever_recipe(taught, profession):
                index = npc(entry)
                if index is not None:
                    trainers[str(spell)].append([index, int(num(r["spellcost"])), int(num(r["reqskillvalue"]))])

    # Recipe vendors: classic item -> Forever recipe item by name.
    classic_items = {int(r["entry"]): r for r in as_dicts(tables["item_template"])}
    recipe_items = {}
    for r in recipes:
        if r.get("ri") and str(r["ri"]) in items:
            recipe_items[items[str(r["ri"])]["n"].lower()] = r["ri"]
    vendor_rows = defaultdict(list)
    for r in as_dicts(tables["npc_vendor"]):
        vendor_rows[int(r["entry"])].append(r)
    vtemplate_rows = defaultdict(list)
    for r in as_dicts(tables["npc_vendor_template"]):
        vtemplate_rows[int(r["entry"])].append(r)
    for entry, t in templates.items():
        template = int(num(t.get("VendorTemplateId")))
        if template:
            vendor_rows[entry].extend(vtemplate_rows.get(template, []))
    vendors = defaultdict(list)
    for entry, rows in vendor_rows.items():
        for r in rows:
            item = classic_items.get(int(num(r["item"])))
            if not item:
                continue
            forever_item = recipe_items.get((item.get("name") or "").lower())
            if not forever_item:
                continue
            index = npc(entry)
            if index is not None:
                vendors[str(forever_item)].append([index, int(num(item.get("BuyPrice"))), 1 if int(num(r["maxcount"])) > 0 else 0])

    def trim(table):
        return {k: v[:MAX_PLACES] for k, v in sorted(table.items(), key=lambda kv: int(kv[0]))}

    return {
        "source": {"db": build_farm.DB_REPO, "commit": commit, "build": catalog["build"], "classicBuild": classic},
        "columns": {"npc": ["name", "title", "side A/H/both", "zone", "x", "y"], "trainer": ["npc", "cost", "skill"],
                    "vendor": ["npc", "price", "limited supply"]},
        "gray": dict(sorted(gray.items(), key=lambda kv: int(kv[0]))),
        "npcs": npcs,
        "trainers": trim(trainers),
        "vendors": trim(vendors),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cache", type=Path, help="folder to keep downloads in")
    parser.add_argument("--commit", help="classic-db commit (default: newest)")
    args = parser.parse_args()
    cache = args.cache
    if cache:
        cache.mkdir(parents=True, exist_ok=True)
    catalog = json.loads((ROOT / "site" / "catalog.json").read_text(encoding="utf-8"))
    commit = args.commit or json.loads(build_farm.fetch(f"https://api.github.com/repos/{build_farm.DB_REPO}/commits/master"))["sha"]
    raw = build_farm.fetch(f"https://raw.githubusercontent.com/{build_farm.DB_REPO}/{commit}/{build_farm.DB_FILE}",
                           cache / f"classicdb-{commit[:10]}.sql.gz" if cache else None, binary=True)
    tables = build_farm.read_dump(gzip.decompress(raw).decode("utf-8", errors="replace"), TABLES)
    build_name = catalog["build"]

    def table(name):
        text = build_farm.fetch(f"{build_farm.WAGO}/db2/{name}/csv?build={build_name}", cache / f"{name}-{build_name}.csv" if cache else None)
        return list(csv.DictReader(text.splitlines()))
    wago = {name: table(name) for name in ("SkillLineAbility", "SpellName", "FactionTemplate",
                                           "UiMapAssignment", "UiMap", "Map", "AreaTable")}
    classic = json.loads(build_farm.fetch(f"{build_farm.WAGO}/api/builds"))["wow_classic_era"][0]["version"]
    for name in ("SpellEffect", "SpellName"):
        text = build_farm.fetch(f"{build_farm.WAGO}/db2/{name}/csv?build={classic}", cache / f"{name}-{classic}.csv" if cache else None)
        wago["Classic" + name] = list(csv.DictReader(text.splitlines()))
    data = build(tables, wago, catalog, commit, classic)
    out = ROOT / "catalog" / "leveling_sources.json"
    out.write_text(json.dumps(data, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    print(f"leveling_sources.json: {len(data['gray'])} gray levels, {len(data['trainers'])} trained recipes, "
          f"{len(data['vendors'])} recipe items sold, {len(data['npcs'])} NPCs, {out.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
