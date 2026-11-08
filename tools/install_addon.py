#!/usr/bin/env python3
"""Copy the addon from this project into the game. The project's copy is the source of truth.

    python tools/install_addon.py "D:\\World of Warcraft\\_forever_"

Files no longer in the project are deleted from the game's copy. It also moves anyone on
the old TentTimer folder over: the old folder is removed so both
don't load, and each account's saved settings are copied to the new name. The old settings
file stays in place, so nothing is lost.
"""
import shutil
import sys
from pathlib import Path

ADDON = Path(__file__).resolve().parents[1] / "addon" / "DufforthAHScanner"
OLD_NAME, OLD_VARIABLE = "TentTimer", "TentTimerDB"
NEW_VARIABLE = "DufforthAHScannerDB"


def migrate_settings(game):
    moved = 0
    for old in (game / "WTF" / "Account").glob(f"*/SavedVariables/{OLD_NAME}.lua"):
        new = old.with_name(f"{ADDON.name}.lua")
        if not new.exists():
            new.write_text(old.read_text(encoding="utf-8").replace(OLD_VARIABLE, NEW_VARIABLE), encoding="utf-8")
            moved += 1
    return moved


def install(game):
    game = Path(game)
    addons = game / "Interface" / "AddOns"
    target = addons / ADDON.name
    target.mkdir(parents=True, exist_ok=True)
    # Files removed from the project are removed from the game too, so nothing stale lingers.
    wanted = {path.name for path in ADDON.iterdir() if path.is_file()}
    for path in target.iterdir():
        if path.is_file() and path.name not in wanted:
            path.unlink()
    for path in ADDON.iterdir():
        if path.is_file():
            shutil.copy(path, target / path.name)
    moved = migrate_settings(game)
    old = addons / OLD_NAME
    if old.exists():
        shutil.rmtree(old)
    return target, moved


if __name__ == "__main__":
    print("Installed to %s, moved settings for %d accounts" % install(sys.argv[1]))
