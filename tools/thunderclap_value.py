"""Is Thunder Clap worth adding? Computed from the real fight history with pandas.

    python tools/thunderclap_value.py [history.jsonl]

Uses the measured damage per cast (game's damage meter) of Thunder Clap, Heroic Strike and Revenge,
the stance each Thunder Clap was cast in (from the fight log), and how damage per rage point grows
with the number of enemies it hits.
"""
import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from analyze_warrior_fights import load, tables, spell_table  # noqa: E402
from archive_warrior_fights import DEFAULT_HISTORY  # noqa: E402

RAGE = {"Thunder Clap": 20, "Heroic Strike": 15, "Revenge": 5}


def main():
    history = sys.argv[1] if len(sys.argv) > 1 else str(DEFAULT_HISTORY)
    records = load(history)
    fights, casts, damage, tries = tables(records)
    tc_damage = damage[damage["spell"] == "Thunder Clap"]
    # Casts per fight from the damage meter fights only; damage per hit on one enemy.
    tc_casts = casts[(casts["spell"] == "Thunder Clap") & casts["fight"].isin(tc_damage["fight"])]
    per_fight = tc_damage.set_index("fight")["damage"]
    counted = tc_casts.groupby("fight").size()
    per_cast_rows = [per_fight[i] / counted.get(i, 1) for i in per_fight.index]  # 1 cast when the log missed it
    tc = pd.Series(per_cast_rows).mean() if per_cast_rows else float("nan")
    spells = spell_table(fights, casts, damage)
    hs, rev = spells.loc["Heroic Strike", "per_cast"], spells.loc["Revenge", "per_cast"]
    stance = fights.set_index("fight")["stance"]
    all_tc = casts[casts["spell"] == "Thunder Clap"]
    fails = tries[(tries["what"] == "Thunder Clap") & (tries["kind"] == "F")]
    print(f"Thunder Clap: {len(per_cast_rows)} fights with damage numbers, {tc:.0f} damage per cast on one enemy; "
          f"cast {len(all_tc)} times in fights that started in stance {sorted(stance[all_tc['fight']].unique())} "
          f"(1 Battle, 2 Defensive), failed tries {len(fails)}")
    rows = []
    for enemies in (1, 2, 3, 4, 5):
        tc_rage = tc * enemies / RAGE["Thunder Clap"]
        rows.append({"enemies hit": enemies, "Thunder Clap damage": round(tc * enemies),
                     "per rage point": round(tc_rage, 1), "Heroic Strike per rage": round(hs / 15, 1),
                     "Revenge per rage": round(rev / 5, 1), "vs Heroic Strike": f"{tc_rage / (hs / 15):.0%}"})
    print(pd.DataFrame(rows).to_string(index=False))
    need = (hs / 15) * RAGE["Thunder Clap"] / tc
    print(f"break-even with Heroic Strike: {need:.1f} enemies hit")
    print(f"enemies seen per fight (most at once): "
          + ", ".join(f"{k}: {v}" for k, v in fights["enemies"].value_counts().sort_index().items()))


if __name__ == "__main__":
    main()
