"""Analyzes the warrior fight history on this PC with pandas and prints a short report.

    python tools/analyze_warrior_fights.py                 # default history file
    python tools/analyze_warrior_fights.py path/to/fights.jsonl --csv out_folder

Reads warrior-history/fights.jsonl (written by archive_warrior_fights.py). The numbers come from
the game's damage meter (per spell, per fight) and the addon's cast and try log. All the math runs
here, so only the summary needs reading. --csv also writes the full tables for a spreadsheet.
Needs `pip install pandas`.
"""
import argparse
import json
import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from archive_warrior_fights import DEFAULT_HISTORY  # noqa: E402

# Forever spell ids seen in the damage meter before the addon saved names (2026-11-11 probe).
SPELL_IDS = {6603: "Auto Attack", 285: "Heroic Strike", 6572: "Revenge", 6547: "Rend", 8198: "Thunder Clap",
             402927: "Victory Rush", 1291698: "Deep Wounds?"}
# Rage per cast at these levels (Classic values; talents can lower Heroic Strike and Sunder).
RAGE = {"Heroic Strike": 15, "Revenge": 5, "Rend": 10, "Sunder Armor": 15, "Thunder Clap": 20,
        "Shield Block": 10, "Victory Rush": 0, "Cleave": 20, "Overpower": 5, "Shield Slam": 20,
        "Demoralizing Shout": 10, "Battle Shout": 10, "Execute": 15, "Shield Bash": 10}
GCD_SPELLS = {"Revenge", "Rend", "Sunder Armor", "Thunder Clap", "Victory Rush", "Overpower", "Battle Shout",
              "Demoralizing Shout", "Shield Slam", "Execute", "Mortal Strike", "Bloodthirst", "Whirlwind"}


SAME_SPELL = {"Attack": "Auto Attack"}


def load(path):
    rows = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if line.strip():
                rows.append(json.loads(line))
    return rows


def spell_damage(fight):
    """{spell: damage} for one fight, from the new field or the first probe's raw dump."""
    if isinstance(fight.get("spellDamage"), dict):
        # The game names spell 6603 "Attack"; the first probe's id map called it "Auto Attack".
        out = {}
        for name, amount in fight["spellDamage"].items():
            name = SAME_SPELL.get(name, name)
            out[name] = out.get(name, 0) + amount
        return out
    raw = (fight.get("damage") or {}).get("GetCombatSessionSourceFromType(Current,DamageDone)") or {}
    spells = raw.get("combatSpells") or {}
    spells = spells.values() if isinstance(spells, dict) else spells
    out = {}
    for row in spells:
        if isinstance(row, dict) and isinstance(row.get("totalAmount"), (int, float)):
            name = SPELL_IDS.get(row.get("spellID"), f"spell {row.get('spellID')}")
            out[name] = out.get(name, 0) + row["totalAmount"]
    return out


def tables(records):
    fights, casts, damage, tries = [], [], [], []
    for n, record in enumerate(records):
        f = record["fight"]
        fights.append({"fight": n, "at": f.get("at"), "seconds": f.get("seconds"), "stance": f.get("stance"),
                       "level": f.get("level"), "enemies": f.get("mostEnemies"), "result": f.get("result"),
                       "zone": f.get("zone"), "macro": record.get("macro")})
        for c in f.get("casts") or []:
            parts = c.split(" ")
            name = " ".join(parts[1:]).split(" r")[0]
            casts.append({"fight": n, "t": float(parts[0]), "spell": name})
        for spell, amount in spell_damage(f).items():
            damage.append({"fight": n, "spell": spell, "damage": amount})
        for t in f.get("tries") or []:
            parts = t.split(" ", 2)
            if len(parts) == 3:
                tries.append({"fight": n, "t": float(parts[0]), "kind": parts[1], "what": parts[2]})
    return (pd.DataFrame(fights), pd.DataFrame(casts, columns=["fight", "t", "spell"]),
            pd.DataFrame(damage, columns=["fight", "spell", "damage"]),
            pd.DataFrame(tries, columns=["fight", "t", "kind", "what"]))


def spell_table(fights, casts, damage):
    """Per spell over the fights that have damage numbers: casts, damage, per cast, per rage."""
    with_damage = set(damage["fight"])
    c = casts[casts["fight"].isin(with_damage)].groupby("spell").size().rename("casts")
    d = damage.groupby("spell")["damage"].sum()
    t = pd.concat([c, d], axis=1).fillna(0)
    t["per_cast"] = (t["damage"] / t["casts"].where(t["casts"] > 0)).round(1)
    t["rage"] = t.index.map(lambda s: RAGE.get(s))
    t["per_rage"] = (t["per_cast"] / t["rage"].where(t["rage"] > 0)).round(1)
    t["share_%"] = (100 * t["damage"] / t["damage"].sum()).round(1)
    return t.sort_values("damage", ascending=False)


def stalls(tries, threshold=6):
    """Fights where one global-cooldown spell failed again and again (the button stuck on it)."""
    failed = tries[(tries["kind"] == "F") & tries["what"].isin(GCD_SPELLS)]
    counts = failed.groupby(["fight", "what"]).size().rename("fails").reset_index()
    return counts[counts["fails"] >= threshold].sort_values("fails", ascending=False)


def rend_report(fights, casts, damage):
    rend_fights = casts[casts["spell"] == "Rend"]["fight"].unique()
    seconds = fights.set_index("fight")["seconds"]
    with_damage = set(damage["fight"])
    lines = [f"fights: {len(fights)}, with damage numbers: {len(with_damage)}, "
             f"median length {seconds.median():.1f} s (Rend lasts 15 s at this level, ticks every 3 s)",
             f"Rend cast in {len(rend_fights)} of {len(fights)} fights "
             f"({100 * len(rend_fights) / max(len(fights), 1):.0f}%)"]
    short = (seconds < 15).mean() * 100
    lines.append(f"fights shorter than Rend's 15 s: {short:.0f}% (Rend can't do its full damage there)")
    return lines


def rage_c(level):
    return 0.0091107836 * level ** 2 + 3.225598133 * level + 4.2652911


def rage_table(records, damage):
    """Per fight with damage taken saved: rage from your white hits vs from being hit."""
    white = damage[damage["spell"] == "Auto Attack"].set_index("fight")["damage"]
    rows = []
    for n, record in enumerate(records):
        f = record["fight"]
        taken = f.get("damageTaken")
        if not isinstance(taken, (int, float)) or not f.get("seconds"):
            continue
        c = rage_c(f.get("level") or 1)
        from_hits, from_taken = 7.5 * white.get(n, 0) / c, 2.5 * taken / c
        rows.append({"fight": n, "seconds": f["seconds"], "damage taken": taken,
                     "rage from your hits": round(from_hits), "rage from being hit": round(from_taken),
                     "rage per second": round((from_hits + from_taken) / f["seconds"], 1)})
    table = pd.DataFrame(rows)
    if len(table):
        hits, taken = table["rage from your hits"].sum(), table["rage from being hit"].sum()
        table["being hit %"] = (100 * table["rage from being hit"] /
                                (table["rage from your hits"] + table["rage from being hit"]).clip(lower=1)).round()
        table.loc[len(table)] = {"fight": "all", "seconds": table["seconds"].sum(), "damage taken": table["damage taken"].sum(),
                                 "rage from your hits": hits, "rage from being hit": taken,
                                 "rage per second": round((hits + taken) / table["seconds"].sum(), 1),
                                 "being hit %": round(100 * taken / max(hits + taken, 1))}
    return table


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("history", nargs="?", default=str(DEFAULT_HISTORY))
    parser.add_argument("--csv", help="folder to write the full tables to")
    args = parser.parse_args()
    fights, casts, damage, tries = tables(load(args.history))
    pd.set_option("display.width", 140)
    print("== Per spell (fights with damage numbers)")
    print(spell_table(fights, casts, damage).to_string())
    print("\n== Rend")
    for line in rend_report(fights, casts, damage):
        print("  " + line)
    print("\n== Rage sources (Classic formulas: your white hits 7.5 x damage / c, being hit 2.5 x damage / c)")
    rage = rage_table(load(args.history), damage)
    print(rage.to_string(index=False) if len(rage) else "  no damage taken saved yet (needs fights with the new version)")
    print("\n== Button stuck on one spell (6+ failed tries in a fight)")
    stuck = stalls(tries)
    print(stuck.to_string(index=False) if len(stuck) else "  none")
    if len(stuck):
        print("  by spell: " + ", ".join(f"{k} {v} fights" for k, v in stuck.groupby("what").size().items()))
    if args.csv:
        out = Path(args.csv)
        out.mkdir(parents=True, exist_ok=True)
        for name, frame in (("fights", fights), ("casts", casts), ("damage", damage), ("tries", tries)):
            frame.to_csv(out / f"{name}.csv", index=False)
        print(f"\ntables written to {out}")


if __name__ == "__main__":
    main()
