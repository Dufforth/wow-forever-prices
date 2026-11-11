"""Prints a short summary of the Warrior helper's saved diagnostics and fight log.

    python tools/read_warrior_log.py "D:/World of Warcraft/_forever_"

Reads every account's SavedVariables/DufforthTweaksHelper.lua (written by the game on /reload
or logout). Needs `pip install lupa`.
"""
import glob
import os
import sys

import lupa.lua51 as L


def items(table):
    return list(table.items()) if table is not None else []


def summarize(path):
    lua = L.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open(path, encoding="utf-8", errors="replace").read())
    db = lua.globals().DufforthTweaksHelperDB
    warrior = db and db.warrior
    print(f"== {path}")
    if warrior is None:
        print("  no warrior data (the Warrior part never ran on this account)")
        return
    debug = warrior.debug
    if debug is not None:
        for key in ("build", "status", "rotationSpells", "missingEvents", "buttons"):
            print(f"  {key}: {debug[key]}")
        events = sorted(items(debug.events), key=lambda kv: -kv[1])
        print("  events seen: " + ", ".join(f"{k} {v}" for k, v in events))
        for message, count in items(debug.errors):
            print(f"  ERROR x{count}: {message}")
    fights = [f for _, f in sorted(items(warrior.fights))]
    print(f"  fights saved: {len(fights)}")
    for f in fights[-15:]:
        casts = [c for _, c in sorted(items(f.casts))]
        spells = {}
        for c in casts:
            name = " ".join(c.split(" ")[1:]).split(" r")[0]
            spells[name] = spells.get(name, 0) + 1
        errors = ", ".join(f"{k} x{v}" for k, v in items(f.errors))
        print(f"  - {f.zone} lvl {f.level} stance {f.stance} {f.seconds}s {f.result} enemies {f.mostEnemies} "
              f"casts {spells} errors [{errors}]")
        if f.tried is not None:
            # S sent, F failed, Q failed quietly, I interrupted, C cast
            counts = {name: dict(kinds.items()) for name, kinds in f.tried.items() if name and not str(name)[0].isupper() or True}
            print("      tried: " + "; ".join(f"{k} {v}" for k, v in counts.items()))
    last = fights[-1] if fights else None
    if last is not None and last.tries is not None:
        print("  last fight, every try (S sent, F failed, Q quiet fail, I interrupted, E error, C cast):")
        print("    " + " | ".join(t for _, t in sorted(last.tries.items())))


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "D:/World of Warcraft/_forever_"
    files = glob.glob(os.path.join(root, "WTF", "Account", "*", "SavedVariables", "DufforthTweaksHelper.lua"))
    if not files:
        sys.exit("no DufforthTweaksHelper.lua found")
    for path in files:
        summarize(path)


if __name__ == "__main__":
    main()
