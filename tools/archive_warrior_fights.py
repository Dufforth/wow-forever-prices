"""Keeps every warrior fight the addon logged, for good, in one history file on this PC.

The addon only keeps the last fights in the game's saved file, so older ones would be lost. This
copies each fight it hasn't seen yet into a JSON Lines file (one fight per line, with the full
macro text it was played with) and never removes anything.

    python tools/archive_warrior_fights.py                      # default game folder and history file
    python tools/archive_warrior_fights.py "D:/World of Warcraft/_forever_" path/to/fights.jsonl

The game writes its saved file on /reload or logout, so run this after one of those. Needs
`pip install lupa`.
"""
import glob
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_GAME = "D:/World of Warcraft/_forever_"
# Outside the repo (personal play data, not published), in the synced working folder.
DEFAULT_HISTORY = ROOT.parent / "warrior-history" / "fights.jsonl"


def to_python(value):
    """Lua table -> dict, or list when its keys are 1..n."""
    if hasattr(value, "items") and not isinstance(value, (dict, str)):
        items = list(value.items())
        keys = [k for k, _ in items]
        if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [to_python(v) for _, v in sorted(items)]
        return {str(k): to_python(v) for k, v in items}
    return value


def read_saved(path):
    import lupa.lua51 as L
    lua = L.LuaRuntime(unpack_returned_tuples=True)
    with open(path, encoding="utf-8", errors="replace") as handle:
        lua.execute(handle.read())
    db = lua.globals().DufforthTweaksHelperDB
    return to_python(db) if db is not None else {}


def fight_key(account, fight):
    return "|".join(str(x) for x in (account, fight.get("character", ""), fight.get("at"), fight.get("seconds"), fight.get("zone")))


def archive(game=DEFAULT_GAME, history=DEFAULT_HISTORY):
    """Adds new fights to the history file. Returns (added, total)."""
    history = Path(history)
    history.parent.mkdir(parents=True, exist_ok=True)
    known = set()
    if history.exists():
        with open(history, encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if line:
                    known.add(json.loads(line)["key"])
    added = 0
    files = sorted(glob.glob(os.path.join(game, "WTF", "Account", "*", "SavedVariables", "DufforthTweaksHelper.lua")))
    with open(history, "a", encoding="utf-8") as out:
        for path in files:
            account = Path(path).parents[1].name
            warrior = (read_saved(path) or {}).get("warrior") or {}
            macros = warrior.get("macros") or []
            gear = warrior.get("gear") or []
            fights = sorted(warrior.get("fights") or [], key=lambda f: f.get("at") or 0)
            for fight in fights:
                key = fight_key(account, fight)
                if key in known:
                    continue
                index = fight.get("macro") or 0
                record = {
                    "key": key,
                    "account": account,
                    "fight": fight,
                    "macro": macros[index - 1] if isinstance(macros, list) and 0 < index <= len(macros) else None,
                }
                gear_index = fight.get("gear") or 0
                if isinstance(gear, list) and 0 < gear_index <= len(gear):
                    record["gear"] = gear[gear_index - 1]  # items, weapon and stats the fight was fought with
                out.write(json.dumps(record, ensure_ascii=False) + "\n")
                known.add(key)
                added += 1
    return added, len(known)


def main():
    import datetime
    import traceback
    game = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_GAME
    history = Path(sys.argv[2] if len(sys.argv) > 2 else DEFAULT_HISTORY)
    # The hourly scheduled run has no window, so each run leaves one line here to check on it.
    status = history.parent / "last_run.txt"
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    try:
        added, total = archive(game, history)
        message = f"{stamp} ok: added {added} new fights; {total} fights in {history}"
    except Exception:
        message = f"{stamp} FAILED:\n{traceback.format_exc()}"
    history.parent.mkdir(parents=True, exist_ok=True)
    status.write_text(message + "\n", encoding="utf-8")
    print(message)


if __name__ == "__main__":
    main()
