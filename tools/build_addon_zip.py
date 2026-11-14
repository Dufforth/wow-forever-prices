#!/usr/bin/env python3
"""Build the addon download: a zip that unpacks into Interface\\AddOns as one folder.

    python tools/build_addon_zip.py _site/downloads

Writes DufforthTweaksHelper-<version>.zip, a copy under a name that never changes,
and latest.json, which tells the page which version to offer.
"""
import json
import re
import shutil
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "addon" / "DufforthTweaksHelper"


def version():
    toc = (ADDON / f"{ADDON.name}.toc").read_text(encoding="utf-8")
    return re.search(r"(?m)^## Version: (\S+)", toc).group(1)


def build(folder):
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    current = version()
    versioned = folder / f"{ADDON.name}-{current}.zip"
    with zipfile.ZipFile(versioned, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(ADDON.rglob("*")):  # subfolders too (Media: the guide icon)
            if path.is_file():
                archive.write(path, f"{ADDON.name}/{path.relative_to(ADDON).as_posix()}")
    shutil.copy(versioned, folder / f"{ADDON.name}.zip")
    (folder / "latest.json").write_text(json.dumps({"version": current, "file": versioned.name}), encoding="utf-8")
    return versioned


if __name__ == "__main__":
    print(build(sys.argv[1]))
