"""Scores candidate one-hand weapons against the current one, from the warrior's real fight numbers.

    python tools/weapon_compare.py

Weapon stats are from Wowhead Classic tooltips (2026-11-12). The model, per second of fighting:
- White hits: (weapon DPS + attack power / 14) x a hit factor measured from the logs with the
  current weapon (misses, dodges, glancing blows and swings replaced by Heroic Strike included).
- Heroic Strike: the logged casts per minute; each hit = the weapon's average swing + 44 (rank 4).
  Counted only as its bonus over the swing it replaces (the white part is already in the white hits).
- Strength: 2 attack power each. Agility: about 0.033 damage per second per point (crit + Revenge).
- Chance-on-hit effects: the current dagger's Firebolt was measured at 1.2 per second; others are
  scaled by their damage and swings per second (Classic procs are a chance per hit).
- Stamina is shown as health; it doesn't add damage.
"""
import pandas as pd

AP = 201  # from the saved weapon reading: Meteor Shard shows 32.7 dps with attack power, 18.33 without
WHITE_MEASURED = 19.5  # auto attack per second with Meteor Shard (25 fights)
HS_PER_MINUTE = 4.2
HS_BONUS = 44
CURRENT_PROC = 1.2  # Firebolt per second, measured

WEAPONS = [
    # name, min, max, speed, strength, agility, stamina, spirit, proc average damage (0 = none)
    ("Meteor Shard (now)", 23, 43, 1.8, 0, 0, 0, 0, 35),
    ("Beazel's Basher", 32, 60, 2.5, 6, 0, 0, 2, 0),
    ("Bearded Boneaxe", 25, 47, 1.9, 4, 4, 0, 0, 0),
    ("Looming Gavel", 33, 62, 2.4, 0, 3, 6, 0, 0),
    ("The Black Knight", 26, 49, 1.9, 0, 0, 0, 0, 40),
]


def main():
    now = WEAPONS[0]
    now_dps = (now[1] + now[2]) / 2 / now[3]
    hit_factor = WHITE_MEASURED / (now_dps + AP / 14)
    rows = []
    for name, low, high, speed, strength, agility, stamina, spirit, proc in WEAPONS:
        weapon_dps = (low + high) / 2 / speed
        ap = AP + 2 * strength
        white = (weapon_dps + ap / 14) * hit_factor
        heroic = HS_PER_MINUTE / 60 * HS_BONUS
        proc_dps = CURRENT_PROC * (proc / now[8]) * (now[3] / speed) if proc else 0
        agility_dps = 0.033 * agility
        total = white + heroic + proc_dps + agility_dps
        rows.append({"weapon": name, "speed": speed, "weapon dps": round(weapon_dps, 2),
                     "white/s": round(white, 1), "proc/s": round(proc_dps, 1), "stats/s": round(agility_dps, 2),
                     "damage/s from weapon": round(total, 1), "health": stamina * 10})
    table = pd.DataFrame(rows)
    base = table.loc[0, "damage/s from weapon"]
    table["vs now"] = (table["damage/s from weapon"] - base).round(1)
    table["vs now %"] = (100 * table["vs now"] / 40.1).round(1)  # of your total 40.1 damage per second
    print(table.sort_values("damage/s from weapon", ascending=False).to_string(index=False))


if __name__ == "__main__":
    main()
