#!/usr/bin/env python3
"""Copy the addon from this project into the game. The project's copy is the source of truth.

    python tools/install_addon.py "D:\\World of Warcraft\\_forever_\\Interface\\AddOns"
"""
import shutil
import sys
from pathlib import Path

ADDON = Path(__file__).resolve().parents[1] / "addon" / "TentTimer"

if __name__ == "__main__":
    target = Path(sys.argv[1]) / ADDON.name
    target.mkdir(parents=True, exist_ok=True)
    for path in ADDON.iterdir():
        if path.is_file():
            shutil.copy(path, target / path.name)
    print(f"Installed to {target}")
