"""Prints the leveling guide's log and settings from the saved file, to solve guide problems from facts.

    python tools/read_guide_log.py "<game folder>" [lines] [kind]

lines: how many of the newest log lines (default 60); kind: only lines of that kind (step, target, arrow, map,
settings, quest, zone, level, login, error). Reads every account's SavedVariables/DufforthTweaksHelper.lua (the game
writes it on /reload or logout). Needs `pip install lupa`.
"""
import glob
import os
import sys
import time

import lupa.lua51 as L


def summarize(path, lines, kind):
    lua = L.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open(path, encoding="utf-8", errors="replace").read())
    db = lua.globals().DufforthTweaksHelperDB
    print(f"== {path} (saved {time.strftime('%Y-%m-%d %H:%M', time.localtime(os.path.getmtime(path)))})")
    if db is None:
        print("  empty")
        return
    guide = db.guide
    if guide is not None:
        plain = sorted((k, v) for k, v in guide.items() if isinstance(v, (bool, int, float, str)))
        print("  settings: " + " ".join(f"{k}={v}" for k, v in plain))
        for key in ("mapDebug", "mapError"):
            v = guide[key]
            if v is not None:
                print(f"  {key}: " + (", ".join(f"{a}={b}" for a, b in sorted(v.items())) if hasattr(v, "items") else str(v)))
    log = db.guideLog
    entries = [str(v) for _, v in sorted(log.entries.items())] if log is not None and log.entries is not None else []
    if kind:
        entries = [e for e in entries if f" {kind}: " in f" {e}"]
    print(f"  log: {len(entries)} lines" + (f" of kind {kind}" if kind else "") + f", newest {min(lines, len(entries))}:")
    for e in entries[-lines:]:
        print("    " + e)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    root = sys.argv[1]
    lines = int(sys.argv[2]) if len(sys.argv) > 2 else 60
    kind = sys.argv[3] if len(sys.argv) > 3 else None
    paths = glob.glob(os.path.join(root, "WTF", "Account", "*", "SavedVariables", "DufforthTweaksHelper.lua"))
    if not paths:
        print("no saved file found under", root)
    for path in sorted(paths, key=os.path.getmtime, reverse=True):
        summarize(path, lines, kind)


if __name__ == "__main__":
    main()
