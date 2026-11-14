#!/usr/bin/env python3
"""Compares warrior setups from real fights: weapons (two-hander, one-hander and shield...), talents
(Arms / Fury / Protection points) and stance, so "Prot or Arms, shield or two-hander" is answered with
your own numbers.

    python tools/compare_setups.py [history.jsonl]

Per setup: fights, average fight length, damage per second, damage taken per second, deaths, and
"seconds per kill with rest": the fight plus the time to eat back the damage taken (at REGEN health
per second), which is what decides leveling speed. Fights from before talents and setup were saved
(addon 4.19) show the setup as guessed from the off hand and talents as "not saved".
"""
import json
import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from archive_warrior_fights import DEFAULT_HISTORY  # noqa: E402

REGEN = 30.0  # health per second while eating, about what level 20-30 food gives (rough)
STANCES = {1: "Battle", 2: "Defensive", 3: "Berserker"}


def rows(path):
    for line in open(path, encoding="utf-8"):
        if not line.strip():
            continue
        r = json.loads(line)
        f = r.get("fight") or {}
        items = (r.get("gear") or {}).get("items") or {}
        setup = f.get("setup")
        if not setup:
            setup = "1H+off hand" if items.get("offhand") else ("weapon only" if items.get("mainhand") else "?")
        yield {
            "setup": setup, "talents": f.get("talents") or "not saved", "stance": STANCES.get(f.get("stance"), "?"),
            "level": f.get("level"), "seconds": f.get("seconds") or 0, "damage": f.get("damageTotal") or 0,
            "taken": f.get("damageTaken") or 0, "died": f.get("result") == "died", "enemies": f.get("mostEnemies") or 1,
            "weapon": (items.get("mainhand") or {}).get("name"),
        }


def table(path):
    d = pd.DataFrame(rows(path))
    d = d[(d.seconds > 3) & (d.damage > 0)]
    d["dps"] = d.damage / d.seconds
    d["taken_ps"] = d.taken / d.seconds
    d["rest"] = d.taken / REGEN
    g = d.groupby(["setup", "talents", "stance"]).agg(
        fights=("dps", "size"), level=("level", "median"), seconds=("seconds", "mean"), dps=("dps", "mean"),
        taken_ps=("taken_ps", "mean"), deaths=("died", "sum"), enemies=("enemies", "mean"), rest=("rest", "mean"))
    g["per_kill_with_rest"] = g.seconds + g.rest
    return g.round(1).sort_values("per_kill_with_rest")


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_HISTORY
    g = table(path)
    print(g.to_string())
    print(f"\nper_kill_with_rest = fight seconds + damage taken / {REGEN:.0f} health per second of eating. Lower is faster leveling.")
    small = g[g.fights < 15]
    if len(small):
        print("Fewer than 15 fights in: " + "; ".join(" / ".join(map(str, k)) for k in small.index) + " (too few to trust).")


if __name__ == "__main__":
    main()
