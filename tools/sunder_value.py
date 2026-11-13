"""Is Sunder Armor worth its rage? Computed from the real fight history with pandas.

    python tools/sunder_value.py [history.jsonl]

Sunder does no damage itself: each stack lowers the target's armor, so every physical hit after it
does more, for the rest of the fight. This takes each real fight (its damage per second from the
game's damage meter, and when each Sunder landed), works out the extra damage the stacks gave, and
compares that with what the same 15 rage gives as a Heroic Strike (measured damage per cast).
Target armor isn't readable in game, so it's shown for a range of typical values.
Classic armor formula: reduction = armor / (armor + 400 + 85 * attacker level).
"""
import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from analyze_warrior_fights import load, tables, spell_table  # noqa: E402
from archive_warrior_fights import DEFAULT_HISTORY  # noqa: E402

SUNDER_PER_STACK = [(10, 90), (22, 180), (34, 270), (46, 360), (58, 450)]  # (level learned, armor per stack)
MAX_STACKS = 5
SUNDER_RAGE = 15


def per_stack(level):
    value = 0
    for learned, armor in SUNDER_PER_STACK:
        if level >= learned:
            value = armor
    return value


def reduction(armor, level):
    armor = max(armor, 0)
    return armor / (armor + 400 + 85 * level)


def extra_damage(armor, level, dps, sunder_times, end):
    """Extra damage from the Sunder stacks between each cast and the end of the fight."""
    base = 1 - reduction(armor, level)
    extra, stacks = 0.0, 0
    times = sorted(sunder_times) + [end]
    for start, stop in zip(times, times[1:]):
        stacks = min(stacks + 1, MAX_STACKS)
        lowered = 1 - reduction(armor - stacks * per_stack(level), level)
        # dps was measured with the stacks on, so this slightly overstates the gain (generous to Sunder)
        extra += dps * (lowered / base - 1) * max(stop - start, 0)
    return extra


def main():
    history = sys.argv[1] if len(sys.argv) > 1 else str(DEFAULT_HISTORY)
    records = load(history)
    fights, casts, damage, _ = tables(records)
    totals = damage.groupby("fight")["damage"].sum().rename("damage")
    f = fights.set_index("fight").join(totals, how="inner")
    f = f[f["seconds"] > 0]
    f["dps"] = f["damage"] / f["seconds"]
    sunders = casts[casts["spell"] == "Sunder Armor"].groupby("fight")["t"].apply(list)
    spells = spell_table(fights, casts, damage)
    hs = spells.loc["Heroic Strike", "per_cast"] if "Heroic Strike" in spells.index else 113
    revenge = spells.loc["Revenge", "per_cast"] if "Revenge" in spells.index else 115

    level = int(f["level"].median())
    with_sunder = f.index.intersection(sunders.index)
    print(f"{len(f)} fights with damage numbers, level {level}, median {f['seconds'].median():.1f} s, "
          f"{f['dps'].mean():.0f} damage per second; Sunder cast {sum(len(sunders[i]) for i in with_sunder)} times "
          f"in {len(with_sunder)} fights (-{per_stack(level)} armor per stack)")
    rows = []
    for armor in (600, 900, 1200, 1500):
        gains = [extra_damage(armor, level, f.loc[i, "dps"], sunders[i], f.loc[i, "seconds"]) for i in with_sunder]
        n_casts = sum(len(sunders[i]) for i in with_sunder)
        per_cast = sum(gains) / n_casts if n_casts else 0
        rows.append({"target armor": armor, "damage gained per Sunder": round(per_cast, 1),
                     "per rage point": round(per_cast / SUNDER_RAGE, 2),
                     "Heroic Strike per rage": round(hs / 15, 2), "Revenge per rage": round(revenge / 5, 2),
                     "Sunder vs Heroic Strike": f"{per_cast / hs:.0%}"})
    print(pd.DataFrame(rows).to_string(index=False))
    # Break-even: how long a fight must run after one stack for Sunder to equal a Heroic Strike.
    dps = f["dps"].mean()
    for armor in (900, 1200):
        gain_per_second = dps * ((1 - reduction(armor - per_stack(level), level)) / (1 - reduction(armor, level)) - 1)
        print(f"break-even at armor {armor}: one stack needs {hs / gain_per_second:.0f} s of fighting "
              f"to match one Heroic Strike (your fights last {f['seconds'].median():.0f} s)")


if __name__ == "__main__":
    main()
