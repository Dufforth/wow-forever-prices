#!/usr/bin/env python3
"""What each buyable consumable does: food buffs, elixirs, flasks, scrolls, potions, from the game's spell tables.

    python catalog/build_consumables.py [--cache folder]

Reads Forever's own ItemEffect, SpellEffect, SpellMisc and SpellDuration tables (wago.tools, the
catalog's build) and writes catalog/consumables.json:

    {"columns": [...], "items": {item id: [kind, seconds, {effect: amount}, weapon types]}}

kind: food, elixir, flask, scroll, potion, other, weapon (sharpening stones, weightstones, oils: a
temporary weapon enchant from SpellItemEnchantment; weapon types is the game's own bit mask of the
weapon subclasses it can go on, from SpellEquippedItems, 0 = any). Effects: str agi sta int spi all (stats), ap, rap
(ranged attack power), sp (spell damage), heal (healing power), crit, scrit (spell crit %), armor,
mp5, hpmax (more maximum health), wdmg (weapon damage), hit (%), hp (instant health), mana, rage, xp (% experience). Forever's "Nutritious Food" gives its stat
through a generic Well Fed buff, with the amount on the food's own trigger effect.
"""
import argparse
import csv
import json
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_farm  # noqa: E402

KINDS = {1: "potion", 2: "elixir", 3: "flask", 4: "scroll", 5: "food", 8: "other"}
STATS = {0: "str", 1: "agi", 2: "sta", 3: "int", 4: "spi", -1: "all"}
# Spell effects and auras (Classic numbering, unchanged on Forever).
APPLY_AURA, HEAL, ENERGIZE, TRIGGER = 6, 10, 30, 64
MOD_STAT, MOD_AP, MOD_RAP, MOD_SPELL_DAMAGE, MOD_HEALING = 29, 99, 124, 13, 135
MOD_CRIT, MOD_CRIT_ALL, MOD_SPELL_CRIT, MOD_RESISTANCE, MOD_POWER_REGEN, MOD_XP = 52, 290, 57, 22, 85, 200
MOD_ARMOR, MOD_HEALTH = 674, 34  # Forever's armor aura; more maximum health
MOD_HIT = 54
ENCHANT_TEMPORARY = 54  # the spell effect of stones and oils
ENCHANT_DAMAGE, ENCHANT_EQUIP_SPELL = 2, 3  # SpellItemEnchantment effect types
WEAPON_CLASS = "2"
PERIODIC_TRIGGER = (227, 23)
FOOD_XP_SPELL = "1243969"  # Forever: "Well Fed XP Boost", named in nutritious food's text
ARMOR_SCHOOL = 1


def num(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def aura_effect(aura, misc, amount):
    """(effect, amount) for one aura, or None for auras the advice doesn't use."""
    if aura == MOD_STAT:
        stat = STATS.get(int(misc))
        return (stat, amount) if stat else None
    if aura == MOD_AP:
        return ("ap", amount)
    if aura == MOD_RAP:
        return ("rap", amount)
    if aura == MOD_SPELL_DAMAGE and int(misc) & 126:
        return ("sp", amount)
    if aura == MOD_HEALING:
        return ("heal", amount)
    if aura in (MOD_CRIT, MOD_CRIT_ALL):
        return ("crit", amount)
    if aura == MOD_SPELL_CRIT:
        return ("scrit", amount)
    if aura == MOD_HEALTH:
        return ("hpmax", amount)
    if aura in (MOD_RESISTANCE, MOD_ARMOR) and int(misc) & ARMOR_SCHOOL:
        return ("armor", amount)
    if aura == MOD_POWER_REGEN and int(misc) == 0:
        return ("mp5", amount)
    if aura == MOD_XP:
        return ("xp", amount)
    if aura == MOD_HIT:
        return ("hit", amount)
    return None


def build(tables, catalog):
    effects_by_id = {r["ID"]: r for r in tables["ItemEffect"]}
    item_spells = defaultdict(list)
    for r in tables["ItemXItemEffect"]:
        e = effects_by_id.get(r["ItemEffectID"])
        if e and e["TriggerType"] == "0":  # on use
            item_spells[r["ItemID"]].append(e["SpellID"])
    spell_effects = defaultdict(list)
    for r in tables["SpellEffect"]:
        spell_effects[r["SpellID"]].append(r)
    durations = {r["ID"]: int(num(r["Duration"])) for r in tables["SpellDuration"]}
    spell_seconds = {r["SpellID"]: durations.get(r["DurationIndex"], 0) // 1000 for r in tables["SpellMisc"]}
    descriptions = {r["ID"]: r["Description_lang"] or "" for r in tables["Spell"]}
    enchants = {r["ID"]: r for r in tables.get("SpellItemEnchantment", [])}
    weapon_types = {r["SpellID"]: int(num(r["EquippedItemSubclass"])) for r in tables.get("SpellEquippedItems", [])
                    if r["EquippedItemClass"] == WEAPON_CLASS}

    def add(out, effect):
        if effect and effect[1] > 0:
            out[effect[0]] = out.get(effect[0], 0) + effect[1]

    out = {}
    for item_id, item in catalog["items"].items():
        kind = KINDS.get(item.get("sc")) if item.get("cl") == 0 else None
        spells = item_spells.get(item_id, [])
        if any(int(num(e["Effect"])) == ENCHANT_TEMPORARY for s in spells for e in spell_effects.get(s, [])):
            kind = "weapon"  # stones and oils (some oils are listed as trade goods)
        if not kind or not spells:
            continue
        if any("no effect outside" in descriptions.get(s, "") for s in spells):
            continue  # only works in one dungeon (Blackfathom Sharpening Stone)
        if item.get("bop") and not item.get("v"):
            continue  # can't be bought
        found, seconds, weapons = {}, 0, 0
        for spell in spells:
            if FOOD_XP_SPELL in descriptions.get(spell, ""):
                found["xp"] = found.get("xp", 0) + 5
            for e in spell_effects.get(spell, []):
                kind_of, aura, amount = int(num(e["Effect"])), int(num(e["EffectAura"])), num(e["EffectBasePointsF"])
                misc, trigger = num(e["EffectMiscValue_0"]), e["EffectTriggerSpell"]
                if kind_of == ENCHANT_TEMPORARY:
                    enchant = enchants.get(str(int(misc)))
                    weapons = weapon_types.get(spell, 0)
                    seconds = max(seconds, int(num(enchant["Duration"])) if enchant else int(amount))
                    for slot in range(3) if enchant else ():
                        kind_e, points, arg = (int(num(enchant[f"{c}_{slot}"])) for c in ("Effect", "EffectPointsMin", "EffectArg"))
                        if kind_e == ENCHANT_DAMAGE:
                            add(found, ("wdmg", points))
                        elif kind_e == ENCHANT_EQUIP_SPELL:
                            for buff in spell_effects.get(str(arg), []):
                                if int(num(buff["Effect"])) == APPLY_AURA:
                                    add(found, aura_effect(int(num(buff["EffectAura"])), num(buff["EffectMiscValue_0"]), num(buff["EffectBasePointsF"])))
                elif kind_of == HEAL:
                    add(found, ("hp", amount))
                elif kind_of == ENERGIZE:
                    add(found, ("mana", amount) if int(misc) == 0 else ("rage", amount / 10) if int(misc) == 1 else None)
                elif kind_of == APPLY_AURA and aura in PERIODIC_TRIGGER and trigger not in ("", "0"):
                    # Well Fed: the buff spell carries the kind of stat, the food carries the amount.
                    for buff in spell_effects.get(trigger, []):
                        own = num(buff["EffectBasePointsF"])
                        add(found, aura_effect(int(num(buff["EffectAura"])), num(buff["EffectMiscValue_0"]), amount if own <= 1 else own))
                    seconds = max(seconds, spell_seconds.get(trigger, 0))
                elif kind_of == APPLY_AURA and kind != "food":  # eating and drinking themselves aren't buffs
                    effect = aura_effect(aura, misc, amount)
                    if effect:
                        add(found, effect)
                        seconds = max(seconds, spell_seconds.get(spell, 0))
        buffs = {k: v for k, v in found.items() if k not in ("hp", "mana", "rage", "xp")}
        if not found or (kind == "food" and not buffs):
            continue  # plain food and drink: no buff to compare
        out[item_id] = [kind, seconds, {k: round(v, 1) if v % 1 else int(v) for k, v in sorted(found.items())}, weapons]
    return {"columns": ["kind", "seconds", "effects", "weapon types"], "build": catalog["build"], "items": out}


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cache", type=Path, help="folder to keep downloads in")
    args = parser.parse_args()
    if args.cache:
        args.cache.mkdir(parents=True, exist_ok=True)
    catalog = json.loads((ROOT / "site" / "catalog.json").read_text(encoding="utf-8"))
    build_name = catalog["build"]

    def table(name):
        text = build_farm.fetch(f"{build_farm.WAGO}/db2/{name}/csv?build={build_name}",
                                args.cache / f"{name}-{build_name}.csv" if args.cache else None)
        return list(csv.DictReader(text.splitlines()))
    tables = {name: table(name) for name in ("ItemEffect", "ItemXItemEffect", "SpellEffect", "SpellMisc", "SpellDuration", "Spell",
                                           "SpellItemEnchantment", "SpellEquippedItems")}
    data = build(tables, catalog)
    path = ROOT / "catalog" / "consumables.json"
    path.write_text(json.dumps(data, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    print(f"consumables.json: {len(data['items'])} consumables, {path.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
