"""Prints a short summary of the Druid helper's saved diagnostics and fight log.

    python tools/read_druid_log.py "<game folder>"

Reads every account's SavedVariables/DufforthTweaksHelper.lua (written by the game on /reload
or logout): the stance bar as the game reports it (Forever's form ids), whether combo points were
readable in combat, errors, and per fight what each spell was tried, refused and cast, plus every
try of the last fight. Needs `pip install lupa`.
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
    druid = db and db.druid
    print(f"== {path}")
    if druid is None:
        print("  no druid data")
        return
    debug = druid.debug
    if debug is not None:
        for key in ("status", "forms", "comboReadable", "comboHidden"):
            print(f"  {key}: {debug[key]}")
        for message, count in items(debug.errors):
            print(f"  ERROR x{count}: {message}")
    fights = [f for _, f in items(druid.fights)]
    print(f"  fights saved: {len(fights)}")
    for f in fights[-10:]:
        tried = "; ".join(f"{name} " + " ".join(f"{k}{v}" for k, v in items(kinds)) for name, kinds in items(f.tried))
        print(f"  {f.at} {f.form} lvl {f.level} {f.seconds}s {f.result} macro {f.macro}: {tried}")
    if fights:
        last = fights[-1]
        print("  last fight tries: " + " | ".join(str(t) for _, t in items(last.tries)))
        print("  last fight casts: " + " | ".join(str(c) for _, c in items(last.casts)))
        macros = [m for _, m in items(druid.macros)]
        if last.macro and 0 < last.macro <= len(macros):
            print("  its macro:\n    " + macros[last.macro - 1].replace("\n", "\n    "))


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    paths = glob.glob(os.path.join(sys.argv[1], "WTF", "Account", "*", "SavedVariables", "DufforthTweaksHelper.lua"))
    for path in sorted(paths):
        summarize(path)


if __name__ == "__main__":
    main()
