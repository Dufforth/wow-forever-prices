"""Imports Forever's own quests recorded in game by the addon into catalog/forever_quests.json, for the route builder.

Usage: python tools/import_recorded_quests.py ["D:\\World of Warcraft\\_forever_"]
Reads every account's SavedVariables\\DufforthTweaksHelper.lua (DufforthTweaksHelperDB.recorded), keeps the most
complete record of each quest (handed in, most objective spots), and merges with what was imported before.
Then rebuild the route: python catalog/build_route.py ...
"""
import glob
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "catalog" / "forever_quests.json"
DEFAULT_GAME = r"D:\World of Warcraft\_forever_"


def completeness(row):
    """How much a record knows: handed in first, then objective spots."""
    spots = sum(len(o.get("spots", [])) for o in row.get("objectives", []))
    return (1 if row.get("turnIn", {}).get("zone") else 0, 1 if row.get("giver", {}).get("zone") else 0, spots)


def merge_records(old, new):
    """Lists of records -> one list, the most complete record per quest id, sorted by id."""
    best = {}
    for row in list(old) + list(new):
        qid = int(row.get("id", 0))
        if qid and (qid not in best or completeness(row) > completeness(best[qid])):
            best[qid] = row
    return [best[k] for k in sorted(best)]


def _plain(value):
    """Lua tables (from lupa) -> lists and dicts."""
    if hasattr(value, "items") and not isinstance(value, dict):
        items = dict(value.items())
        if items and all(isinstance(k, int) for k in items):
            return [_plain(items[k]) for k in sorted(items)]
        return {str(k): _plain(v) for k, v in items.items()}
    return value


def read_saved(path):
    import lupa.lua51 as L  # only needed here
    lua = L.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(Path(path).read_text(encoding="utf-8", errors="replace"))
    db = lua.globals().DufforthTweaksHelperDB
    recorded = db and db["recorded"]
    if not recorded:
        return []
    out = []
    for qid, row in recorded.items():
        r = _plain(row)
        r["id"] = int(qid)
        if isinstance(r.get("objectives"), dict):
            r["objectives"] = list(r["objectives"].values())
        out.append(r)
    return out


def main(game=DEFAULT_GAME):
    files = glob.glob(os.path.join(game, "WTF", "Account", "*", "SavedVariables", "DufforthTweaksHelper.lua"))
    new = [row for f in files for row in read_saved(f)]
    old = json.loads(OUT.read_text(encoding="utf-8")) if OUT.exists() else []
    merged = merge_records(old, new)
    OUT.write_text(json.dumps(merged, ensure_ascii=False, indent=1), encoding="utf-8")
    handed = sum(1 for r in merged if r.get("turnIn", {}).get("zone"))
    print(f"{len(files)} saved files, {len(new)} records read; {len(merged)} Forever quests in {OUT.name} ({handed} with a hand-in)")


if __name__ == "__main__":
    main(*sys.argv[1:2])
