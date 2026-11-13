"""Compares damage between gear sets (for example before and after a weapon swap), with pandas.

    python tools/compare_gear.py [history.jsonl]

Groups the fights that have damage numbers by gear set (fights from before gear was saved are
"before gear tracking"), then prints per group: fights, levels, damage per second, auto attack per
second, Heroic Strike and Revenge per cast, damage taken per second, rage shortages per minute, and
spells that only one group has (a weapon's chance-on-hit effect shows up there).
"""
import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from analyze_warrior_fights import load, tables  # noqa: E402
from archive_warrior_fights import DEFAULT_HISTORY  # noqa: E402


def group_name(record):
    gear = record.get("gear")
    if not gear:
        return "before gear tracking"
    items = gear.get("items") or {}
    main = (items.get("mainhand") or {}).get("name") or "?"
    return f"{main} (lvl {gear.get('level')})"


def main():
    history = sys.argv[1] if len(sys.argv) > 1 else str(DEFAULT_HISTORY)
    records = load(history)
    fights, casts, damage, tries = tables(records)
    fights["group"] = [group_name(r) for r in records]
    fights["taken"] = [r["fight"].get("damageTaken") for r in records]
    with_damage = set(damage["fight"])
    f = fights[fights["fight"].isin(with_damage)].copy()
    dmg = damage.merge(f[["fight", "group"]], on="fight")
    c = casts.merge(f[["fight", "group"]], on="fight")
    rage_fails = tries[(tries["kind"] == "E") & (tries["what"] == "Not enough rage")].merge(f[["fight", "group"]], on="fight")
    misses = tries[(tries["kind"] == "E") & tries["what"].str.contains("miss|dodge|parr", case=False, regex=True)]

    rows = []
    for group, g in f.groupby("group", sort=False):
        secs = g["seconds"].sum()
        d = dmg[dmg["group"] == group]
        by_spell = d.groupby("spell")["damage"].sum()
        cc = c[c["group"] == group].groupby("spell").size()
        taken = g["taken"].dropna()
        rows.append({
            "group": group, "fights": len(g), "levels": f"{g['level'].min()}-{g['level'].max()}",
            "median fight s": round(g["seconds"].median(), 1),
            "damage/s": round(by_spell.sum() / secs, 1),
            "auto attack/s": round(by_spell.get("Auto Attack", 0) / secs, 1),
            "Heroic Strike/cast": round(by_spell.get("Heroic Strike", 0) / cc.get("Heroic Strike", 1), 0) if cc.get("Heroic Strike") else None,
            "Revenge/cast": round(by_spell.get("Revenge", 0) / cc.get("Revenge", 1), 0) if cc.get("Revenge") else None,
            "taken/s": round(taken.sum() / g.loc[taken.index, "seconds"].sum(), 1) if len(taken) else None,
            "no rage /min": round(len(rage_fails[rage_fails["group"] == group]) / secs * 60, 1),
        })
    print(pd.DataFrame(rows).to_string(index=False))

    print("\nDamage per second by spell:")
    per = dmg.groupby(["group", "spell"])["damage"].sum().unstack(0).fillna(0)
    secs = f.groupby("group")["seconds"].sum()
    print((per / secs).round(1).sort_values(per.columns[0], ascending=False).to_string())

    groups = list(f["group"].unique())
    spells = {gname: set(dmg[dmg["group"] == gname]["spell"]) for gname in groups}
    for gname in groups:
        only = spells[gname] - set().union(*(spells[o] for o in groups if o != gname))
        if only:
            sub = dmg[(dmg["group"] == gname) & dmg["spell"].isin(only)].groupby("spell")["damage"].agg(["sum", "count"])
            for spell, row in sub.iterrows():
                print(f"only with {gname}: {spell}: {row['sum']:.0f} damage in {row['count']} of "
                      f"{(f['group'] == gname).sum()} fights ({row['sum'] / secs[gname]:.1f}/s)")
    if len(misses):
        print("\n(misses are not in the error messages the log keeps; weapon skill can't be measured here)")


if __name__ == "__main__":
    main()
