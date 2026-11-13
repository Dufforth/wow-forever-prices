"""Slow or fast weapon at the same DPS? A small model for the warrior's Defensive rotation.

    python tools/weapon_speed.py [white dps] [level]

Classic rules (Forever may differ; unproven there):
- White damage per second is the same for both weapons (same DPS).
- Rage from your hits = 7.5 * damage / c(level), so rage per second from white hits is the same too.
- Heroic Strike replaces a swing: it adds a flat bonus (rank by level) and costs 15 rage, and the
  swing it replaces gives no rage, so a bigger swing makes Heroic Strike cost more rage in total.
- Revenge, Shield Block, Rend and Thunder Clap don't depend on the weapon.
- One Heroic Strike per swing at most, so a slow weapon has fewer chances to spend rage.
Rage from being hit (the main tank income) is the same for both, so it is one shared budget here.
"""
import sys

import pandas as pd

HS_BONUS = [(1, 11), (8, 21), (16, 32), (24, 44), (32, 58), (40, 80), (48, 111), (56, 138)]  # (level, flat bonus)


def hs_bonus(level):
    return max(b for lvl, b in HS_BONUS if level >= lvl)


def rage_c(level):
    return 0.0091107836 * level ** 2 + 3.225598133 * level + 4.2652911


def compare(white_dps, level, seconds=40, spare_rage=60):
    """spare_rage: rage left for Heroic Strike in a fight after Revenge and Shield Block."""
    rows = []
    for speed in (1.5, 1.8, 2.2, 2.6, 3.0, 3.6):
        swing = white_dps * speed
        lost_rage = 7.5 * swing / rage_c(level)  # the replaced swing's rage
        cost = 15 + lost_rage
        swings = seconds / speed
        hs = min(swings, spare_rage / cost)  # limited by rage or by swings
        gain = hs * hs_bonus(level)
        rows.append({"speed": speed, "avg swing": round(swing), "Heroic Strike rage (15 + lost swing rage)": round(cost, 1),
                     "swings per fight": round(swings, 1), "Heroic Strikes": round(hs, 1),
                     "extra damage from them": round(gain), "per rage point": round(hs_bonus(level) / cost, 2)})
    return pd.DataFrame(rows)


def main():
    white = float(sys.argv[1]) if len(sys.argv) > 1 else 23.0  # your white DPS from the damage meter (Auto Attack)
    level = int(sys.argv[2]) if len(sys.argv) > 2 else 25
    print(f"white DPS {white}, level {level}, Heroic Strike bonus +{hs_bonus(level)}, 40 s fight")
    for spare in (30, 60, 120):
        print(f"\n-- {spare} rage to spare per fight on Heroic Strike")
        print(compare(white, level, spare_rage=spare).to_string(index=False))


if __name__ == "__main__":
    main()
