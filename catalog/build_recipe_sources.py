#!/usr/bin/env python3
"""Build catalog/recipe_sources.json: the skill each recipe is learned at and where it comes from.

The game client's tables don't say which trainer teaches a recipe or which monster drops it, so
this reads Wowhead's Classic profession lists, whose skill numbers match the Forever client
(Greater Mana Potion turns yellow at 220 in both). About 20 pages, read once after a game
patch and saved in the repo, so the hourly price job never contacts Wowhead.

    python catalog/build_recipe_sources.py [--cache DIR]
"""
import argparse
import json
import re
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AGENT = "wow-forever-prices (personal price page)"
BASE = "https://www.wowhead.com/classic"
SPELL_PAGES = [f"spells/professions/{p}" for p in
               ("alchemy", "blacksmithing", "enchanting", "engineering", "leatherworking", "tailoring", "mining")]
SPELL_PAGES += ["spells/secondary-skills/cooking", "spells/secondary-skills/first-aid"]
ITEM_PAGES = [f"items/recipes/{p}" for p in
              ("alchemy", "blacksmithing", "cooking", "enchanting", "engineering", "first-aid", "leatherworking", "tailoring")]
RECORD = re.compile(r"\{\"[^{}]*\}")
MAX_SKILL = 450


def fetch(page, cache):
    path = cache / (page.replace("/", "_") + ".html") if cache else None
    if path and path.exists():
        return path.read_text(encoding="utf-8")
    request = urllib.request.Request(f"{BASE}/{page}", headers={"User-Agent": AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        text = response.read().decode("utf-8")
    if path:
        path.write_text(text, encoding="utf-8")
    time.sleep(1.5)  # be gentle
    return text


def field(record, name):
    match = re.search(rf'"{name}":(\[[^\]]*\]|-?\d+|true|false)', record)
    return json.loads(match.group(1)) if match else None


def parse(text, kind):
    """{id: [skill, sources, world drop]} from one Wowhead list page."""
    out = {}
    for match in RECORD.finditer(text):
        record = match.group(0)
        item_id = field(record, "id")
        if not isinstance(item_id, int):
            continue
        if kind == "spell":
            skill = field(record, "learnedat")
            if skill is None or field(record, "creates") is None:
                continue
        else:
            if field(record, "classs") != 9:
                continue
            skill = field(record, "skill")
        skill = skill if isinstance(skill, int) and 0 < skill <= MAX_SKILL else 0
        out[str(item_id)] = [skill, field(record, "source") or [], 1 if field(record, "commondrop") else 0]
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path)
    args = parser.parse_args()
    if args.cache:
        args.cache.mkdir(parents=True, exist_ok=True)
    spells, items = {}, {}
    for page in SPELL_PAGES:
        spells.update(parse(fetch(page, args.cache), "spell"))
    for page in ITEM_PAGES:
        items.update(parse(fetch(page, args.cache), "item"))
    out = {"note": "From Wowhead Classic lists; rebuild with catalog/build_recipe_sources.py after a game patch.",
           "spells": spells, "items": items}
    (ROOT / "catalog" / "recipe_sources.json").write_text(json.dumps(out, separators=(",", ":"), sort_keys=True), encoding="utf-8")
    print(f"{len(spells)} recipes, {len(items)} recipe items")


if __name__ == "__main__":
    main()
