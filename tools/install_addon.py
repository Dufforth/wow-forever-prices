#!/usr/bin/env python3
"""Copy the addon from this project into the game. The project's copy is the source of truth.

    python tools/install_addon.py "D:\\World of Warcraft\\_forever_"

Files no longer in the project are deleted from the game's copy. It also moves anyone on
an old name over (Dufforth AH Scanner, and before that TentTimer): the old folder is removed
so both don't load, and each account's saved settings are copied to the new name, newest
old name first. The old settings file stays in place, so nothing is lost.
"""
import shutil
import sys
from pathlib import Path

ADDON = Path(__file__).resolve().parents[1] / "addon" / "DufforthTweaksHelper"
NEW_VARIABLE = "DufforthTweaksHelperDB"
OLD_NAMES = [("DufforthAHScanner", "DufforthAHScannerDB"), ("TentTimer", "TentTimerDB")]  # newest first


def migrate_settings(game):
    moved = 0
    for account in (game / "WTF" / "Account").glob("*/SavedVariables"):
        new = account / f"{ADDON.name}.lua"
        if new.exists():
            continue
        for old_name, old_variable in OLD_NAMES:
            old = account / f"{old_name}.lua"
            if old.exists():
                new.write_text(old.read_text(encoding="utf-8").replace(old_variable, NEW_VARIABLE), encoding="utf-8")
                moved += 1
                break
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
    for old_name, _ in OLD_NAMES:
        old = addons / old_name
        if old.exists():
            shutil.rmtree(old)
    return target, moved


if __name__ == "__main__":
    print("Installed to %s, moved settings for %d accounts" % install(sys.argv[1]))
