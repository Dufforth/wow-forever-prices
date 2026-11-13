#!/usr/bin/env python3
"""Build catalog/class_trainers.json: what each class trainer teaches (spell, rank, level, cost) and
where the class trainers stand, for the addon's "new spells to train" reminder.

Trainer lists come from the CMaNGOS Classic 1.12 world database (npc_trainer, npc_trainer_template);
they list "teach" spells, so Classic's SpellEffect (effect 36, learn spell) maps each to the ability
it teaches, and Classic's SpellName and Spell tables give its name and rank. Places come from the
Forever map tables, with an NPC inside a capital's map placed in that capital. Classic estimates.

    python catalog/build_class_trainers.py [--cache DIR] [--commit SHA]
"""
import argparse
import csv
import gzip
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_farm  # noqa: E402
from build_farm import as_dicts, num  # noqa: E402
from build_leveling_sources import side_of  # noqa: E402

TABLES = ("creature_template", "creature", "npc_trainer", "npc_trainer_template", "quest_template",
          "creature_questrelation", "creature_involvedrelation")
# Classic's newer spell data reuses some old teach spells for other classes (warrior trainer spell
# 1229 now teaches the shaman's Elemental Fury), so a spell is kept only if Forever's own
# SkillLineAbility lists that name for the class (ClassMask bit = class ID - 1).
CLASSES = {1: "WARRIOR", 2: "PALADIN", 3: "HUNTER", 4: "ROGUE", 5: "PRIEST", 7: "SHAMAN", 8: "MAGE", 9: "WARLOCK", 11: "DRUID"}
CLASS_TRAINER = 0  # creature_template.TrainerType
LEARN_SPELL = 36


def rank_of(text):
    m = re.match(r"Rank (\d+)", text or "")
    return int(m.group(1)) if m else 0


def build(tables, wago, commit):
    teaches = {}
    for r in wago["ClassicSpellEffect"]:
        if int(num(r["Effect"])) == LEARN_SPELL and int(num(r["EffectTriggerSpell"])):
            teaches[int(num(r["SpellID"]))] = int(num(r["EffectTriggerSpell"]))
    names = {int(r["ID"]): r["Name_lang"] for r in wago["ClassicSpellName"]}
    ranks = {int(r["ID"]): rank_of(r["NameSubtext_lang"]) for r in wago["ClassicSpell"]}
    forever_names = {r["ID"]: r["Name_lang"] for r in wago["SpellName"]}
    class_spells = defaultdict(set)
    for r in wago["SkillLineAbility"]:
        mask, name = int(num(r["ClassMask"])), forever_names.get(r["Spell"])
        for class_id in CLASSES:
            if name and mask & (1 << (class_id - 1)):
                class_spells[class_id].add(name)
    zone_of_area = build_farm.area_zones(wago["AreaTable"])
    spots = build_farm.labelled_spots(tables, zone_of_area)
    find = build_farm.zone_finder(wago["UiMapAssignment"], wago["UiMap"], {int(r["ID"]): r["MapName_lang"] for r in wago["Map"]}, spots)
    factions = {int(r["ID"]): r for r in wago["FactionTemplate"]}
    spawns = defaultdict(list)
    for r in as_dicts(tables["creature"]):
        spawns[int(r["id"])].append((int(num(r["map"])), num(r["position_x"]), num(r["position_y"])))
    rows_by_npc = defaultdict(list)
    for r in as_dicts(tables["npc_trainer"]):
        rows_by_npc[int(r["entry"])].append(r)
    rows_by_template = defaultdict(list)
    for r in as_dicts(tables["npc_trainer_template"]):
        rows_by_template[int(r["entry"])].append(r)

    out = {name: {"spells": {}, "trainers": []} for name in CLASSES.values()}
    for t in as_dicts(tables["creature_template"]):
        class_id = int(num(t.get("TrainerClass")))
        cls = CLASSES.get(class_id)
        if not cls or int(num(t.get("TrainerType"))) != CLASS_TRAINER:
            continue
        entry = int(t["Entry"])
        rows = rows_by_npc.get(entry, []) + rows_by_template.get(int(num(t.get("TrainerTemplateId"))), [])
        if not rows:
            continue
        for r in rows:
            spell = teaches.get(int(num(r["spell"])), int(num(r["spell"])))
            name = names.get(spell)
            if not name or (class_spells and name not in class_spells[class_id]):
                continue
            key = f"{name}|{ranks.get(spell, 0)}"
            level, cost = int(num(r["reqlevel"])), int(num(r["spellcost"]))
            old = out[cls]["spells"].get(key)
            if not old or level < old[0]:
                out[cls]["spells"][key] = [level, name, ranks.get(spell, 0), cost]
        if spawns.get(entry):
            place = build_farm.place_of(spawns[entry], lambda m, x, y, level=None: find(m, x, y, level, prefer_city=True))
            if place and not place[4]:
                out[cls]["trainers"].append([t["Name"], side_of(factions.get(int(num(t["Faction"])))), place[0], place[1], place[2]])
    for cls in out.values():
        cls["spells"] = sorted(cls["spells"].values(), key=lambda s: (s[0], s[1], s[2]))
        cls["trainers"].sort(key=lambda n: (n[2] not in build_farm.CITIES, n[2], n[0]))
    return {"source": {"db": build_farm.DB_REPO, "commit": commit},
            "columns": {"spell": ["level", "name", "rank (0 = none)", "cost copper"], "trainer": ["name", "side", "zone", "x", "y"]},
            "classes": out}


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
    forever = json.loads((ROOT / "site" / "catalog.json").read_text(encoding="utf-8"))["build"]
    classic = json.loads(build_farm.fetch(f"{build_farm.WAGO}/api/builds"))["wow_classic_era"][0]["version"]

    def table(name, build):
        text = build_farm.fetch(f"{build_farm.WAGO}/db2/{name}/csv?build={build}", cache / f"{name}-{build}.csv" if cache else None)
        return list(csv.DictReader(text.splitlines()))
    wago = {name: table(name, forever) for name in ("UiMapAssignment", "UiMap", "Map", "AreaTable", "FactionTemplate", "SkillLineAbility", "SpellName")}
    for name in ("SpellEffect", "SpellName", "Spell"):
        wago["Classic" + name] = table(name, classic)
    data = build(tables, wago, commit)
    path = ROOT / "catalog" / "class_trainers.json"
    path.write_text(json.dumps(data, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    print(f"class_trainers.json: " + ", ".join(f"{c} {len(v['spells'])} spells/{len(v['trainers'])} trainers" for c, v in data["classes"].items())
          + f", {path.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
