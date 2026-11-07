#!/usr/bin/env python3
"""Build the addon download: a zip that unpacks into Interface\\AddOns as one folder.

    python tools/build_addon_zip.py _site/downloads/GatheringTracker.zip
"""
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "addon" / "TentTimer"


def build(out):
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(ADDON.iterdir()):
            if path.is_file():
                archive.write(path, f"{ADDON.name}/{path.name}")
    return out


if __name__ == "__main__":
    print(build(sys.argv[1]))
