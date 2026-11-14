"""Extracts Forever's own quests (those not in Classic Era) from RestedXP's Forever guides, for the route builder.

Data source and licence: RestedXP Guides (https://github.com/RestedXP/RXPGuides), "Guides/forever", licensed
CC BY-NC-SA 4.0. The extracted file (catalog/forever_rxp_quests.json) carries that credit and licence; the routes
built from it are shared under the same licence (see LICENSE-DATA.md).

What is taken per quest: its number and name, which faction's guide uses it, the level of the guide part, where it
is picked up and handed in and who gives and takes it, and the spots where its objectives are done (world positions from the guide's map
points). Nothing else (no guide text, order or tips) is copied.

Usage: python tools/extract_rxp_forever.py <RXPGuides folder> <Classic Era QuestV2.csv>
"""
import csv
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "catalog" / "forever_rxp_quests.json"
CREDIT = ("Quest places from RestedXP Guides (https://github.com/RestedXP/RXPGuides), Guides/forever, "
          "CC BY-NC-SA 4.0 (https://creativecommons.org/licenses/by-nc-sa/4.0/). Shared under the same licence.")

GOTO = re.compile(r"^\.goto\s+(\d+)/(\d),\s*(-?\d+(?:\.\d+)?)[\d.]*,\s*(-?\d+(?:\.\d+)?)")
QUEST = re.compile(r"^\.(accept|turnin|complete)\s+(\d+)(?:,(\d+))?(?:\s*>>\s*(.*))?")
MOB = re.compile(r"^\.(?:mob|unitscan)\s+(.+?)\s*$")
TARGET = re.compile(r"^\.target\s+(.+?)\s*$")


def world(cont, a, b):
    """RestedXP writes Forever map points as <map>/<continent>,<world y>,<world x>; we keep (continent, x, y)."""
    return [int(cont), round(float(b), 1), round(float(a), 1)]


def faction_of(chunk):
    groups = re.findall(r"^#group .*?\((H|A)\)", chunk, re.M)
    if groups and set(groups) == {"H"}:
        return "H"
    if groups and set(groups) == {"A"}:
        return "A"
    return "both"


HORDE_TAGS = {"Horde", "Orc", "Troll", "Tauren", "Undead", "Scourge", "BloodElf"}
ALLIANCE_TAGS = {"Alliance", "Human", "Dwarf", "Gnome", "NightElf", "Draenei"}


def step_side(header, chunk_side):
    """A step's faction from its tag (<< Horde, << Orc Warrior...), else its guide part's."""
    tag = header.split("<<", 1)[1] if "<<" in header else ""
    words = set(re.findall(r"[A-Za-z]+", tag.replace("!", " NOT_")))
    h = any(w in HORDE_TAGS for w in words)
    a = any(w in ALLIANCE_TAGS for w in words)
    if h and not a:
        return "H"
    if a and not h:
        return "A"
    return chunk_side


def part_level(chunk):
    """The level a guide part starts at ("22-24 Hillsbrad" -> 22); 0 for numbered dungeon parts ("101 Ragefire")."""
    m = re.search(r"^#name\s+(\d+)(-)?", chunk, re.M)
    if not m:
        return 0
    level = int(m.group(1))
    return level if m.group(2) and level <= 60 else 0


def extract(guide_dir, classic_ids):
    quests = {}
    for f in sorted(os.listdir(guide_dir)):
        if not f.endswith(".lua"):
            continue
        body = open(os.path.join(guide_dir, f), encoding="utf-8", errors="ignore").read()
        for chunk in body.split("RXPGuides.RegisterGuide(")[1:]:
            side, level = faction_of(chunk), part_level(chunk)
            pieces = re.split(r"^(\s*step\b.*)$", chunk, flags=re.M)
            for header, step in zip(pieces[1::2], pieces[2::2]):
                side_here = step_side(header, side)
                points, mobs, events, targets = [], [], [], []
                for line in step.splitlines():
                    t = line.strip()
                    if not t.startswith("."):
                        continue  # comments (--) and text lines
                    m = GOTO.match(t)
                    if m:
                        points.append(world(m.group(2), m.group(3), m.group(4)))
                        continue
                    m = TARGET.match(t)
                    if m:
                        targets.append(m.group(1).split("<<")[0].strip())
                        continue
                    m = MOB.match(t)
                    if m:
                        mobs.append(m.group(1).split("<<")[0].strip())
                        continue
                    m = QUEST.match(t)
                    if m:
                        events.append((m.group(1), int(m.group(2)), int(m.group(3) or 0), (m.group(4) or "").split("<<")[0].strip()))
                if not points:
                    continue
                for kind, qid, index, text in events:
                    if qid in classic_ids:
                        continue
                    q = quests.setdefault(qid, {"id": qid, "title": "", "level": level, "sides": [], "objectives": {}})
                    if side_here not in q["sides"]:
                        q["sides"].append(side_here)
                    q["level"] = min(q["level"], level) if q["level"] and level else (q["level"] or level)
                    if kind == "accept":
                        q["title"] = q["title"] or re.sub(r"^Accept\s+", "", text)
                        q.setdefault("giver", {"world": points[-1], "name": targets[0] if targets else ""})
                    elif kind == "turnin":
                        q["title"] = q["title"] or re.sub(r"^Turn in\s+", "", text)
                        q.setdefault("turnIn", {"world": points[-1], "name": targets[0] if targets else ""})
                    else:
                        o = q["objectives"].setdefault(index or 1, {"text": mobs[0] if mobs else "", "kind": "monster" if mobs else "item",
                                                                     "count": 1, "spots": []})
                        for p in points:
                            if p not in o["spots"] and len(o["spots"]) < 12:
                                o["spots"].append(p)
    out = []
    for q in sorted(quests.values(), key=lambda q: q["id"]):
        q["objectives"] = [q["objectives"][k] for k in sorted(q["objectives"])]
        sides = set(q.pop("sides"))
        q["side"] = "H" if "H" in sides and "A" not in sides else "A" if "A" in sides and "H" not in sides else "both"
        out.append(q)
    return out


def main(rxp_folder, questv2_csv):
    classic = {int(r["ID"]) for r in csv.DictReader(open(questv2_csv, encoding="utf-8"))}
    quests = extract(os.path.join(rxp_folder, "Guides", "forever"), classic)
    for q in quests:
        q["side"] = q["side"] or "both"
    OUT.write_text(json.dumps({"credit": CREDIT, "licence": "CC BY-NC-SA 4.0", "quests": quests}, ensure_ascii=False, indent=1),
                   encoding="utf-8")
    placed = sum(1 for q in quests if q.get("giver") and q.get("turnIn"))
    print(f"{len(quests)} Forever quests, {placed} with a pick-up and a hand-in place -> {OUT.name}")


if __name__ == "__main__":
    main(*sys.argv[1:3])
