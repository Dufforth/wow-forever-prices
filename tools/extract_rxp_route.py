"""Writes RestedXP's Forever Horde guides for the route builder: catalog/rxp_routes.json (the event chain each of our
routes is based on, catalog/rxp_chain.py) and catalog/rxp_forever_route.json (22-60 steps for the scorecard).

Data source and licence: RestedXP Guides (https://github.com/RestedXP/RXPGuides), Guides/forever, CC BY-NC-SA 4.0.
rxp_routes.json keeps each RestedXP step whole (catalog/rxp_chain.py route_steps: every line RestedXP's engine acts on,
its tags and conditions; no guide text except "+" lines) and RestedXP's Forever Spirit Healer list (DB/forever). Both files carry the credit and
licence; the routes built on them (catalog/route.json, the addon's GuideData.lua) are shared under the same licence.

Usage: python tools/extract_rxp_route.py <RXPGuides folder> [<installed RXPGuides folder for DB/forever/SpiritHealerDB.lua>]
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "catalog"))
from rxp_chain import STARTS, parts, route_steps, spirit_healers  # noqa: E402
from rxp_route import MAIN_HORDE, ORC_WARRIOR, parse_guide  # noqa: E402

OUT = ROOT / "catalog" / "rxp_forever_route.json"
CHAINS = ROOT / "catalog" / "rxp_routes.json"
CREDIT = ("Steps from RestedXP Guides (https://github.com/RestedXP/RXPGuides), Guides/forever/RestedXP-Skyborne.lua, "
          "group \"RestedXP Forever Guide (H)\", CC BY-NC-SA 4.0 (https://creativecommons.org/licenses/by-nc-sa/4.0/). "
          "Shared under the same licence; used only to compare leveling routes.")


def compact(found):
    """Steps without empty fields, and each part's name once: {"parts": [names by p], "steps": [...]}."""
    names, subs = {}, {}
    out = []
    for st in found:
        names.setdefault(st["p"], st.get("part", ""))
        subs.setdefault(st["p"], st.get("sub", ""))
        out.append({k: v for k, v in st.items() if k in ("p", "lv", "e") or (k not in ("part", "sub") and v not in (None, False, "", 0, []))})
    return {"parts": [names[k] for k in sorted(names)], "subs": [subs[k] for k in sorted(subs)], "steps": out}


def main(folder, installed=None):
    guide = Path(folder) / "Guides" / "forever" / "RestedXP-Skyborne.lua"
    steps = parse_guide(guide.read_text(encoding="utf-8", errors="ignore"), MAIN_HORDE, ORC_WARRIOR)
    OUT.write_text(json.dumps({"credit": CREDIT, "licence": "CC BY-NC-SA 4.0", "guide": MAIN_HORDE, "character": "Orc Warrior",
                               "steps": steps}, separators=(",", ":")), encoding="utf-8")
    known = parts([f.read_text(encoding="utf-8", errors="ignore") for f in sorted((Path(folder) / "Guides" / "forever").rglob("*.lua"))])
    routes = {start: {"main": compact(route_steps(known, start)), "dungeons": compact(route_steps(known, start, dungeons=True))}
              for start in STARTS}
    healers_file = next((Path(f) / "DB" / "forever" / "SpiritHealerDB.lua" for f in (folder, installed) if f
                         and (Path(f) / "DB" / "forever" / "SpiritHealerDB.lua").exists()), None)
    healers = spirit_healers(healers_file.read_text(encoding="utf-8", errors="ignore")) if healers_file else []
    CHAINS.write_text(json.dumps({"credit": CREDIT.replace("Guides/forever/RestedXP-Skyborne.lua, group \"RestedXP Forever Guide (H)\"",
                                                           "Guides/forever (Horde main and dungeon guides)").replace("used only to compare leveling routes",
                                                                                                                    "our leveling routes follow their order"),
                                  "licence": "CC BY-NC-SA 4.0", "step": "{p part, part, tag, lv, step_level, label, cw, req, sticky, loop, optional, dungeon, ln RestedXP line number, e [[tag, args, line tag, RestedXP text]]}",
                                  "spirit": healers, "routes": routes}, separators=(",", ":")), encoding="utf-8")
    for start, r in routes.items():
        print(f"{start}: {len(r['main']['steps'])} steps, with dungeons {len(r['dungeons']['steps'])} -> {CHAINS.name}")
    print(f"{len(healers)} Spirit Healers")
    levels = [s[5] for s in steps]
    print(f"{len(steps)} steps, levels {min(levels)}-{max(levels)}, "
          f"{sum(1 for s in steps if s[0] == 'turnin')} hand-ins, {sum(1 for s in steps if s[0] == 'fly')} flights, "
          f"{sum(1 for s in steps if s[0] == 'hearth')} hearthstones -> {OUT.name}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
