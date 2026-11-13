"""Gear, stat and play-style advice from the warrior fight history, computed locally with pandas.

    python tools/gear_advice.py [history.jsonl]

1. Your current gear set (from the newest fight that has one): items, weapon, stats.
2. How each gear set did: fights, damage per second, damage taken per second, deaths.
3. What one point of Strength, Agility or Stamina is worth for you, from your real numbers
   (damage per spell from the game's damage meter, damage taken, weapon speed, crit and dodge)
   and the Classic formulas (unproven on Forever):
   - Strength: 2 attack power; 14 attack power = 1 damage per second on weapon hits (white hits,
     Heroic Strike); 20 Strength = 1 block value (damage a block stops).
   - Agility: 20 = 1% crit (crits do double); 20 = 1% dodge (dodges stop a hit and enable Revenge);
     2 armor each.
   - Stamina: 10 health each.
4. Spells you pressed on their own keys (outside the button).
"""
import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from analyze_warrior_fights import load, tables  # noqa: E402
from archive_warrior_fights import DEFAULT_HISTORY  # noqa: E402

ENEMY_SWINGS_PER_SECOND = 0.5  # a level-matched mob swings about every 2 s (not readable in game)
REVENGE_USE = 0.5  # share of extra dodges that turn into a Revenge (5 s cooldown, the button's order)


def armor_reduction(armor, level):
    return armor / (armor + 400 + 85 * level)


def stat_values(level, seconds, white, weapon_yellow, other, revenge_hit, taken, crit, armor, blocks_per_second):
    """Per one point of each stat, per minute of fighting: damage you add, damage you avoid, health."""
    enemy_dps = taken / seconds if seconds else 15.0
    weapon_dps = (white + weapon_yellow) / seconds
    all_dps = (white + weapon_yellow + other) / seconds
    minute = 60
    rows = []
    # Strength
    str_damage = 2 / 14 * minute * (weapon_dps / max(weapon_dps, 1e-9))  # +0.143 dps on weapon hits
    str_avoid = blocks_per_second * minute / 20
    rows.append(("Strength", str_damage, str_avoid, 0))
    # Agility
    agi_crit = all_dps * 0.0005 * minute  # +0.05% crit, a crit adds one more hit
    dodges = ENEMY_SWINGS_PER_SECOND * 0.0005 * minute
    agi_revenge = dodges * REVENGE_USE * revenge_hit
    hit = enemy_dps / ENEMY_SWINGS_PER_SECOND if ENEMY_SWINGS_PER_SECOND else 0
    agi_dodge_avoid = dodges * hit
    raw = enemy_dps / max(1 - armor_reduction(armor, level), 1e-9)  # enemy damage before your armor
    agi_armor_avoid = raw * (armor_reduction(armor + 2, level) - armor_reduction(armor, level)) * minute
    rows.append(("Agility", agi_crit + agi_revenge, agi_dodge_avoid + agi_armor_avoid, 0))
    rows.append(("Stamina", 0, 0, 10))
    table = pd.DataFrame(rows, columns=["stat (1 point)", "your damage per minute", "damage you avoid per minute", "health"])
    table["extra seconds alive"] = (table["health"] / enemy_dps).round(2) if enemy_dps else 0
    return table.round(2), enemy_dps


def main():
    history = sys.argv[1] if len(sys.argv) > 1 else str(DEFAULT_HISTORY)
    records = load(history)
    fights, casts, damage, tries = tables(records)

    # 1. Current gear
    with_gear = [(n, r) for n, r in enumerate(records) if r.get("gear")]
    if with_gear:
        _, newest = with_gear[-1]
        g = newest["gear"]
        st, wp = g.get("stats") or {}, g.get("weapon") or {}
        print("== Current gear (level {})".format(g.get("level")))
        for slot, item in sorted((g.get("items") or {}).items()):
            print(f"  {slot:9} {item.get('name')}" + (f" (enchant {item.get('enchant')})" if item.get("enchant") else ""))
        print(f"  weapon: speed {wp.get('speed')}, {wp.get('low')}-{wp.get('high')} damage, {wp.get('dps')} dps")
        print("  stats (unbuffed): " + ", ".join(f"{k} {v:.1f}" if isinstance(v, float) else f"{k} {v}" for k, v in st.items()))
    else:
        print("== Current gear: none saved yet (needs fights with the new version)")
        st, wp = {}, {}

    # 2. Per gear set
    if with_gear:
        rows = []
        dmg_by_fight = damage.groupby("fight")["damage"].sum()
        for n, r in with_gear:
            f = r["fight"]
            key = r["gear"].get("key", "?")
            rows.append({"set": key[-40:], "seconds": f.get("seconds") or 0, "damage": dmg_by_fight.get(n, 0),
                         "taken": f.get("damageTaken") or 0, "died": 1 if f.get("result") == "died" else 0})
        sets = pd.DataFrame(rows).groupby("set").agg(fights=("seconds", "size"), seconds=("seconds", "sum"),
                                                     damage=("damage", "sum"), taken=("taken", "sum"), deaths=("died", "sum"))
        sets["dps"] = (sets["damage"] / sets["seconds"]).round(1)
        sets["taken per second"] = (sets["taken"] / sets["seconds"]).round(1)
        print("\n== Gear sets")
        print(sets[["fights", "dps", "taken per second", "deaths"]].to_string())

    # 3. Stat values, from the fights with damage numbers
    have = fights[fights["fight"].isin(damage["fight"])]
    seconds = have["seconds"].sum()
    by_spell = damage.groupby("spell")["damage"].sum()
    white = by_spell.get("Auto Attack", 0)
    weapon_yellow = by_spell.get("Heroic Strike", 0) + by_spell.get("Cleave", 0) + by_spell.get("Overpower", 0)
    other = by_spell.sum() - white - weapon_yellow
    revenge_casts = len(casts[(casts["spell"] == "Revenge") & casts["fight"].isin(damage["fight"])])
    revenge_hit = by_spell.get("Revenge", 0) / revenge_casts if revenge_casts else 115
    taken = sum((r["fight"].get("damageTaken") or 0) for n, r in enumerate(records) if n in set(damage["fight"]))
    taken_seconds = sum(r["fight"].get("seconds") or 0 for r in records if isinstance(r["fight"].get("damageTaken"), (int, float)))
    level = int(have["level"].median()) if len(have) else 25
    armor = st.get("armor") or 25 * level * 2  # guess when no gear saved yet
    blocks = (st.get("block") or 5) / 100 * ENEMY_SWINGS_PER_SECOND
    table, enemy_dps = stat_values(level, taken_seconds or seconds, white, weapon_yellow, other, revenge_hit,
                                   taken if taken_seconds else 15.0 * seconds, st.get("crit") or 5, armor, blocks)
    print(f"\n== One point of each stat, per minute of fighting (level {level}, enemy damage {enemy_dps:.1f}/s"
          + ("" if taken_seconds else ", guessed: no damage taken saved yet") + ")")
    print(table.to_string(index=False))
    print("  Strength adds the most damage; Stamina keeps you alive longest; Agility is a little of both.")

    # 4. Play style
    manual = {}
    for r in records:
        for spell, count in (r["fight"].get("manual") or {}).items():
            manual[spell] = manual.get(spell, 0) + count
    print("\n== Spells pressed on their own keys (outside the button)")
    print("  " + (", ".join(f"{k} {v}" for k, v in sorted(manual.items(), key=lambda kv: -kv[1])) or "none saved yet"))


if __name__ == "__main__":
    main()
