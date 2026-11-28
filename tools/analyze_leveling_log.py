"""Leveling log analysis: where the guide loses time and what to fix (user, 2026-11-27: "can you create a logs of the
quest and what im doing in game to analyze and improve the guide").

    python tools/analyze_leveling_log.py "<game folder>" [--top N]

Reads every account's SavedVariables/DufforthTweaksHelper.lua (the leveling log in LevelLog.lua, written on /reload or
logout). The math runs here with pandas; only the summary prints. Needs `pip install lupa pandas`.

A row is at;kind;level;xp;zone;x;y;route;part;number;line;extra (zone, route and part index the character's names).
Time is counted between one row and the next, on the step the earlier row was on; idle, AFK and logged-out stretches,
and gaps over MAX_GAP seconds, are left out.
"""
import argparse
import glob
import math
import os
import sys

import lupa.lua51 as L
import pandas as pd

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "catalog"))
from route_score import XP_TABLE  # noqa: E402

MAX_GAP = 900        # seconds; a longer gap between rows is time nobody knows about (crash, alt-tab)
WANDER = 15.0        # map % from the step's point
LONG_STEP = 15 * 60  # seconds on one step worth a look
SKIP_FIX = 2         # times skipped by hand before a fix is suggested
DEATH_FIX = 3        # deaths in one zone before a warning is suggested
# RestedXP's pace in our route model (reports/route-scorecard-22-60.json, Durotar, xp per hour; 1-22 = 215,600 xp in
# 12.4 h). Only a yardstick: the model's hours, not RestedXP's own.
PACE = [(1, 22, 17387), (22, 30, 27572), (30, 40, 42838), (40, 50, 54889), (50, 61, 62697)]
NOT_ACTIVE = {"ia", "lo"}
COLUMNS = ["at", "kind", "level", "xp", "zone", "x", "y", "route", "part", "number", "line", "extra"]


def items(table):
    return list(table.items()) if table is not None else []


def _num(text):
    try:
        return float(text) if "." in text else int(text)
    except (TypeError, ValueError):
        return None


def _extra(text):
    out = {}
    for pair in (text or "").split(","):
        if "=" in pair:
            k, v = pair.split("=", 1)
            n = _num(v)
            out[k] = v if n is None else n
    return out


def parse_row(text, names):
    f = str(text).split(";")
    if len(f) < 12:
        return None
    name = lambda i: names[i - 1] if isinstance(i, int) and 0 < i <= len(names) else None  # noqa: E731
    extra = _extra(";".join(f[11:]))
    if "pz" in extra:
        extra["pz"] = name(extra["pz"])  # the step point's zone, by name
    return {"at": _num(f[0]), "kind": f[1], "level": _num(f[2]), "xp": _num(f[3]), "zone": name(_num(f[4])),
            "x": _num(f[5]), "y": _num(f[6]), "route": name(_num(f[7])), "part": name(_num(f[8])),
            "number": _num(f[9]), "line": _num(f[10]), "extra": extra}


def load(game):
    rows, titles = [], {}
    for path in sorted(glob.glob(os.path.join(game, "WTF", "Account", "*", "SavedVariables", "DufforthTweaksHelper.lua"))):
        lua = L.LuaRuntime(unpack_returned_tuples=True)
        lua.execute(open(path, encoding="utf-8", errors="replace").read())
        db = lua.globals().DufforthTweaksHelperDB
        log = db and db.levelLog
        if log is None:
            continue
        account = os.path.basename(os.path.dirname(os.path.dirname(path)))
        for key, char in items(log.chars):
            names = [str(v) for _, v in sorted(items(char.names), key=lambda kv: kv[0])]
            for qid, title in items(char.quests):
                titles[int(qid)] = str(title)
            for _, text in sorted(items(char.rows), key=lambda kv: kv[0]):
                r = parse_row(text, names)
                if r:
                    r.update(account=account, char=str(key), who=str(char.who or "?"))
                    rows.append(r)
    df = pd.DataFrame(rows, columns=COLUMNS + ["account", "char", "who"])
    df.attrs["titles"] = titles
    return df


def _gain(a, b):
    """XP from row a to row b, across level-ups (Classic XP table)."""
    if a["level"] is None or b["level"] is None or a["xp"] is None or b["xp"] is None:
        return 0
    if b["level"] == a["level"]:
        return max(0, b["xp"] - a["xp"])
    if b["level"] > a["level"]:
        gain = XP_TABLE[a["level"] - 1] - a["xp"] if a["level"] - 1 < len(XP_TABLE) else 0
        for lv in range(a["level"] + 1, b["level"]):
            gain += XP_TABLE[lv - 1] if lv - 1 < len(XP_TABLE) else 0
        return max(0, gain + b["xp"])
    return 0


def timeline(df):
    """One row per stretch: who, step, seconds active, xp gained."""
    out = []
    for _, char in df.groupby("char", sort=False):
        rs = char.to_dict("records")
        afk = False
        for a, b in zip(rs, rs[1:]):
            if a["kind"] == "ak":
                afk = "on" in a["extra"]
            gap = (b["at"] or 0) - (a["at"] or 0)
            active = a["kind"] not in NOT_ACTIVE and not afk and 0 <= gap <= MAX_GAP
            out.append({"char": a["char"], "part": a["part"], "number": a["number"], "line": a["line"], "level": a["level"],
                        "seconds": gap if active else 0, "xp": _gain(a, b)})
    return pd.DataFrame(out, columns=["char", "part", "number", "line", "level", "seconds", "xp"])


def _pace(level):
    for lo, hi, xph in PACE:
        if lo <= (level or 1) < hi:
            return xph
    return PACE[-1][2]


def analyze(df):
    res = {"rows": df, "titles": df.attrs.get("titles", {})}
    tl = timeline(df)
    res["chars"] = df["char"].nunique()
    res["seconds"] = int(tl["seconds"].sum()) if len(tl) else 0
    parts = tl.groupby("part", sort=False).agg(seconds=("seconds", "sum"), xp=("xp", "sum"), level=("level", "min")).reset_index()
    parts["xph"] = parts.apply(lambda r: r["xp"] / (r["seconds"] / 3600) if r["seconds"] else 0, axis=1)
    parts["pace"] = parts["level"].map(_pace)
    res["parts"] = parts
    steps = tl.groupby(["part", "line"], sort=False).agg(seconds=("seconds", "sum"), number=("number", "first"),
                                                         chars=("char", "nunique")).reset_index()
    res["steps"] = steps.sort_values("seconds", ascending=False)

    # Skipped by hand: the step you were on when you skipped (the guide row before the skip).
    skips, guide_kinds = [], {"lg", "gd", "gs", "gb", "gj", "gp"}
    for _, char in df.groupby("char", sort=False):
        prev = None
        for r in char.to_dict("records"):
            if r["kind"] == "gs" and prev is not None:
                skips.append({"part": prev["part"], "number": prev["number"], "line": prev["line"], "char": r["char"]})
            if r["kind"] in guide_kinds or prev is None:
                prev = r
    sk = pd.DataFrame(skips, columns=["part", "number", "line", "char"])
    res["skips"] = (sk.groupby(["part", "number", "line"]).agg(times=("char", "size"), chars=("char", "nunique"))
                    .reset_index().sort_values(["times", "chars"], ascending=False))

    # Wandering: the farthest you went (same zone) from the step's point.
    points = {}
    for r in df.to_dict("records"):
        e = r["extra"]
        if "pz" in e and "px" in e:
            points[(r["part"], r["line"])] = (e["pz"], e["px"], e["py"])
    far = []
    for key, rs in df.groupby(["part", "line"], sort=False):
        pt = points.get(key)
        if not pt:
            continue
        best = 0.0
        for r in rs.to_dict("records"):
            if r["zone"] == pt[0] and r["x"] is not None:
                best = max(best, math.hypot(r["x"] - pt[1], r["y"] - pt[2]))
        if best > WANDER:
            far.append({"part": key[0], "line": key[1], "number": rs["number"].iloc[0], "distance": round(best, 1)})
    res["wander"] = pd.DataFrame(far, columns=["part", "line", "number", "distance"]).sort_values("distance", ascending=False)

    deaths = df[df["kind"] == "dd"]
    res["deaths"] = deaths["zone"].value_counts()
    res["deathSteps"] = deaths.groupby(["part", "line", "number"]).size().sort_values(ascending=False)
    ex = lambda kind, key: int(sum(e.get(key, 0) for e in df[df["kind"] == kind]["extra"]))  # noqa: E731
    res["dead"] = {"corpse": ex("rz", "s"), "vendor": ex("vn", "s"), "trainer": ex("tr", "s"),
                   "idle": ex("ie", "s"), "afk": ex("ak", "s"), "flight": ex("fl", "s")}
    res["xp"] = {"kills": ex("xs", "k"), "quests": ex("xs", "q"), "rested": ex("xs", "r")}
    qa = df[df["kind"] == "qa"]
    off = [{"quest": e["q"], "part": p, "zone": z} for e, p, z in zip(qa["extra"], qa["part"], qa["zone"]) if e.get("g") == 0]
    res["offguide"] = pd.DataFrame(off, columns=["quest", "part", "zone"]).drop_duplicates("quest")
    res["abandoned"] = [e["q"] for e in df[df["kind"] == "qx"]["extra"] if "q" in e]
    res["fixes"] = fixes(res)
    return res


def _step(part, number, line):
    return f"{part} step {int(number) if number == number and number is not None else '?'} (line {int(line) if line == line and line is not None else '?'})"


def fixes(res):
    out = []
    for r in res["skips"].itertuples():
        if r.times >= SKIP_FIX or r.chars >= 2:
            out.append(f"{_step(r.part, r.number, r.line)}: skipped by hand {r.times} times ({r.chars} characters). "
                       "Check its condition (done already? another class or race?) or mark it optional.")
    for r in res["wander"].itertuples():
        out.append(f"{_step(r.part, r.number, r.line)}: players went {r.distance:.0f} map % from its point. "
                   "The point may be wrong, or the objective is elsewhere: add a .goto where they went.")
    for r in res["steps"].itertuples():
        if r.seconds >= LONG_STEP:
            out.append(f"{_step(r.part, r.number, r.line)}: {r.seconds / 60:.0f} min on this step. "
                       "Split it, add points for the objective, or move it next to a step in the same place.")
    for zone, n in res["deaths"].items():
        if n >= DEATH_FIX:
            out.append(f"{zone}: {n} deaths. Add a warning for the dangerous monsters there or a level check before the step.")
    titles = res["titles"]
    for r in res["offguide"].itertuples():
        out.append(f"Quest {titles.get(r.quest, '?')} ({r.quest}) taken off the guide in {r.part or r.zone}. "
                   "If it's worth it, add it to that part.")
    return out


def _min(seconds):
    return f"{seconds / 60:.0f} min"


def report(res, top=10):
    print(f"{res['chars']} characters, {_min(res['seconds'])} played (idle, AFK and logged out left out)")
    xp = res["xp"]
    print(f"XP: kills {xp['kills']}, quests {xp['quests']}, rested used {xp['rested']}")
    print("\nTime per guide part (your XP per hour vs RestedXP's pace in our route model):")
    for r in res["parts"].itertuples():
        pct = f", {r.xph / r.pace:.0%} of pace {r.pace:,}" if r.seconds else ""
        print(f"  {r.part}: {_min(r.seconds)}, {r.xp} xp, {r.xph:,.0f} xp/h{pct}")
    print(f"\nLongest steps (top {top}):")
    for r in res["steps"].head(top).itertuples():
        print(f"  {_step(r.part, r.number, r.line)}: {_min(r.seconds)} ({r.chars} characters)")
    print("\nSkipped by hand most:")
    if not len(res["skips"]):
        print("  none")
    for r in res["skips"].head(top).itertuples():
        print(f"  Skipped by hand: {_step(r.part, r.number, r.line)} {r.times} times")
    print(f"\nWandered over {WANDER:.0f} map % from the step's point:")
    if not len(res["wander"]):
        print("  none")
    for r in res["wander"].head(top).itertuples():
        print(f"  {_step(r.part, r.number, r.line)}: {r.distance:.0f} map %")
    print("\nDeaths per zone:")
    if not len(res["deaths"]):
        print("  none")
    for zone, n in res["deaths"].items():
        print(f"  {zone}: {n} deaths")
    d = res["dead"]
    print(f"\nDead time: corpse runs {_min(d['corpse'])}, vendors {_min(d['vendor'])}, trainers {_min(d['trainer'])}, "
          f"idle {_min(d['idle'])}, AFK {_min(d['afk'])}; flying {_min(d['flight'])}")
    titles = res["titles"]
    print("\nQuests taken off the guide:")
    if not len(res["offguide"]):
        print("  none")
    for r in res["offguide"].head(top).itertuples():
        print(f"  {titles.get(r.quest, '?')} ({r.quest}) in {r.part or r.zone}")
    if res["abandoned"]:
        print("Abandoned: " + ", ".join(f"{titles.get(q, '?')} ({q})" for q in res["abandoned"][:top]))
    print("\nGuide fixes it suggests:")
    if not res["fixes"]:
        print("  none yet: play more with the log on")
    for f in res["fixes"][:top * 2]:
        print("  FIX: " + f)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("game", help="the game folder, e.g. D:/World of Warcraft/_forever_")
    ap.add_argument("--top", type=int, default=10)
    args = ap.parse_args(argv)
    df = load(args.game)
    if not len(df):
        files = glob.glob(os.path.join(args.game, "WTF", "Account", "*", "SavedVariables", "DufforthTweaksHelper.lua"))
        why = "no saved file found under WTF/Account" if not files else \
            "the saved files have no levelLog yet: play with the addon's new version, then /reload or log out"
        print(f"No leveling log: {why}.")
        return
    report(analyze(df), args.top)


if __name__ == "__main__":
    main()
