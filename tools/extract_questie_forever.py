"""Extracts Forever's own quests (numbers from 10000: not in Classic Era) from Questie's Forever database, for the
route builder: Riverglades, Shen'dralas, Mount Hyjal, Zephras Isle and Forever's quests in the old zones.

Data source and licence: QuestieDB (https://github.com/Questie/Questie), GPL-3.0, as installed with the Questie addon
(QuestieDB_Forever.toc and support/Forever/QuestXP). Taken per quest: number, name, level, minimum level, races,
classes, chain links, experience, who gives and takes it and where, and where its objectives are done (the spawn
spots of its monsters, objects and item droppers). The output, catalog/forever_questie_quests.json, carries the credit.

Usage: python tools/extract_questie_forever.py <QuestieDB folder> <AreaTable csv (wago.tools, Forever build)>
"""
import csv
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "catalog"))
import route_questie as rq  # noqa: E402
from build_farm import area_zones  # noqa: E402

OUT = ROOT / "catalog" / "forever_questie_quests.json"
CREDIT = ("Forever quest data from QuestieDB (https://github.com/Questie/Questie), GPL-3.0 "
          "(https://www.gnu.org/licenses/gpl-3.0.html): quest givers, objectives, spawn places and experience.")


def main(db_folder, area_csv):
    folder = Path(db_folder)
    db = rq.load_db(folder / "QuestieDB_Forever.toc")
    xp_dir = folder / "support" / "Forever" / "QuestXP"
    xp = rq.read_xp(*((xp_dir / f).read_text(encoding="utf-8") for f in ("xpDB-classic.lua", "xpDB-traces.lua")
                      if (xp_dir / f).exists()))
    zones = {k: v for k, v in area_zones(list(csv.DictReader(open(area_csv, encoding="utf-8")))).items() if v}
    rows = rq.rows(db, zones, xp, first_id=rq.FOREVER_FROM)
    OUT.write_text(json.dumps({"credit": CREDIT, "licence": "GPL-3.0", "quests": rows}, ensure_ascii=False, indent=0),
                   encoding="utf-8")
    by_zone = {}
    for r in rows:
        by_zone[r["zone"]] = by_zone.get(r["zone"], 0) + 1
    print(f"{OUT.name}: {len(rows)} Horde quests; " + ", ".join(f"{z or '?'} {n}" for z, n in sorted(by_zone.items(), key=lambda x: -x[1])[:12]))


if __name__ == "__main__":
    main(*sys.argv[1:3])
