#!/usr/bin/env python3
"""Learn the Grind tab's numbers from your own kills, and rebuild GrindData.lua with them.

    python tools/tune_grind.py "<game folder>"          archive, fit, rebuild, print a summary
    python tools/tune_grind.py "<game folder>" --dry    archive and print, change nothing else

The addon saves every kill that gives experience in DufforthTweaksHelperDB.grind.kills (written
by the game on /reload or logout; the newest 3000). Each run first appends kills not seen before to
grind-history/kills.jsonl next to the repo (never deletes), then fits from the whole history:
  - Forever's lower-level experience cut (solo kills, rested bonus taken out, against Classic's formula)
  - each class and spec's kill speed (fight seconds, level difference taken out) and rest share
    (time between kills minus the fight and the walk)
  - monsters seen casting, and monsters killed often and never seen casting
It writes catalog/grind_tune.json and rebuilds GrindData.lua, whose DufforthTweaksHelperGrindTune
the addon applies at login (a /reload is enough). Needs lupa.
"""
import glob
import json
import os
import statistics
import sys
from datetime import date, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HISTORY = ROOT.parent / "grind-history" / "kills.jsonl"
TUNE = ROOT / "catalog" / "grind_tune.json"
KILL_SECONDS = 16.0   # Grind.KILL_SECONDS: an average spec on a monster of its own level
WALK_SECONDS = 6.0    # walking and looting between kills (the addon's estimate for a normal spot)
MIN_BELOW = 10        # kills needed to fit the lower-level cut
MIN_SPEC = 20         # kills needed to fit a spec
MIN_QUIET = 5         # kills with no cast seen before a monster counts as not a caster
CAST_SHARE = 0.3      # share of kills seen casting that makes a monster a caster (at least 2)
MAX_FIGHT = 120       # seconds: longer "fights" are a mistake of the log (target kept from earlier)


def classic_xp(level, mob, elite=False):
    """Classic kill experience without Forever's cut (Grind.KillXP with the cut set to 0)."""
    if mob <= 0:
        return 0
    base = level * 5 + 45
    if mob >= level:
        xp = base * (1 + 0.05 * min(mob - level, 4))
    else:
        gray = 0 if level <= 5 else level - 5 - level // 10 if level <= 39 else level - 1 - level // 5
        if mob <= gray:
            return 0
        zero = (5 if level < 8 else 6 if level < 10 else 7 if level < 12 else 8 if level < 16 else 9 if level < 20 else
                11 if level < 30 else 12 if level < 40 else 13 if level < 45 else 14 if level < 50 else 15 if level < 55 else
                16 if level < 60 else 17)
        xp = base * (1 - (level - mob) / zero)
    return xp * (2 if elite else 1)


def _solo(k):
    return not k.get("group") and k.get("ml") and k.get("pl") and k.get("xp")


def _elite(k):
    return k.get("rank") in ("elite", "rareelite", "worldboss")


def fit_below(kills):
    """(cut per level below, largest cut, kills used) from solo kills of lower-level monsters."""
    per_diff = {}
    for k in kills:
        if not _solo(k) or k["ml"] >= k["pl"]:
            continue
        full = classic_xp(k["pl"], k["ml"], _elite(k))
        if full <= 0:
            continue
        base = k["xp"] - (k.get("rested") or 0)
        per_diff.setdefault(k["pl"] - k["ml"], []).append(1 - base / full)
    used = sum(len(v) for v in per_diff.values())
    if used < MIN_BELOW:
        return None, None, used
    small = [c / d for d, cuts in per_diff.items() if d <= 4 for c in cuts]
    big = [c for d, cuts in per_diff.items() if d >= 5 for c in cuts]
    step = round(statistics.median(small), 3) if small else None
    top = round(statistics.median(big), 3) if len(big) >= 5 else None
    return step, top, used


def fit_specs(kills):
    """{"CLASS:spec": (speed, rest share, kills used)} for specs with enough solo, normal kills."""
    groups = {}
    for k in kills:
        if not _solo(k) or _elite(k) or not k.get("fight") or k["fight"] > MAX_FIGHT or not k.get("spec"):
            continue
        groups.setdefault(f'{k["class"]}:{k["spec"]}', []).append(k)
    out = {}
    for key, ks in groups.items():
        if len(ks) < MIN_SPEC:
            continue
        norm = [k["fight"] / max(0.5, 1 + 0.1 * (k["ml"] - k["pl"])) for k in ks]
        fight = statistics.median(norm)
        speed = round(KILL_SECONDS / fight, 3)
        cycles = [k["cycle"] for k in ks if k.get("cycle")]
        rest = None
        if len(cycles) >= MIN_SPEC // 2:
            raw = statistics.median(cycles) - statistics.median(k["fight"] for k in ks) - WALK_SECONDS
            rest = round(min(2.0, max(0.0, raw / statistics.median(k["fight"] for k in ks))), 3)
        out[key] = (speed, rest, len(ks))
    return out


def fit_casters(kills):
    """(monsters seen casting, monsters killed often and never seen casting), sorted."""
    seen = {}
    for k in kills:
        if "cast" not in k or k.get("mob") is None:
            continue
        n, c = seen.get(k["mob"], (0, 0))
        seen[k["mob"]] = (n + 1, c + (1 if k["cast"] else 0))
    casters = sorted(m for m, (n, c) in seen.items() if c >= 2 and c / n >= CAST_SHARE)
    quiet = sorted(m for m, (n, c) in seen.items() if c == 0 and n >= MIN_QUIET)
    return casters, quiet


def _key(k):
    return (k.get("at"), k.get("mob"), k.get("xp"), k.get("pl"))


def merge(old, new, account):
    """History plus new kills (tagged with the account), each kill once, oldest first."""
    have = {_key(k) for k in old}
    added = []
    for k in new:
        if _key(k) not in have:
            added.append(dict(k, account=account))
            have.add(_key(k))
    return sorted(old + added, key=lambda k: (k.get("at") or 0)), len(added)


def _lua(v):
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return f"{v:g}"
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, (list, tuple)):
        return "{" + ",".join(_lua(x) for x in v) + "}"
    return "{" + ",".join(f"[{_lua(k)}]={_lua(x)}" for k, x in v.items()) + "}"


def tune_lua(tune):
    """The DufforthTweaksHelperGrindTune table (Grind.ApplyTune reads it)."""
    parts = []
    if tune.get("below"):
        parts.append("below=" + _lua(tune["below"]))
    parts.append("specs={" + ",".join(f"[{_lua(k)}]={_lua(list(v))}" for k, v in sorted(tune.get("specs", {}).items())) + "}")
    parts.append("casters={" + ",".join(f"[{_lua(m)}]=true" for m in tune.get("casters", [])) + "}")
    parts.append("noCast={" + ",".join(f"[{_lua(m)}]=true" for m in tune.get("noCast", [])) + "}")
    parts.append(f'kills={tune.get("kills", 0)}')
    parts.append(f'at={_lua(tune.get("at", ""))}')
    return "-- Learned from your kills by tools/tune_grind.py.\nDufforthTweaksHelperGrindTune = {" + ",".join(parts) + "}\n"


def build_tune(kills):
    step, top, below_n = fit_below(kills)
    specs = fit_specs(kills)
    casters, quiet = fit_casters(kills)
    tune = {"at": date.today().isoformat(), "kills": len(kills),
            "specs": {k: [v[0], v[1]] for k, v in specs.items()}, "casters": casters, "noCast": quiet,
            "used": {"below": below_n, "specs": {k: v[2] for k, v in specs.items()}}}
    if step is not None:
        tune["below"] = [step, top if top is not None else 0.20]
    return tune


# ---- Reading the game's saved file ----

def _plain(t):
    if t is None or isinstance(t, (int, float, str, bool)):
        return t
    keys = list(t.keys())
    if keys and all(isinstance(k, int) for k in keys):
        return [_plain(t[i]) for i in sorted(keys)]
    return {k: _plain(v) for k, v in t.items()}


def saved_kills(game_folder):
    """[(character label, [kill dicts])] from every account's saved file."""
    import lupa.lua51 as L
    out = []
    for path in glob.glob(os.path.join(game_folder, "WTF", "Account", "*", "SavedVariables", "DufforthTweaksHelper.lua")):
        lua = L.LuaRuntime(unpack_returned_tuples=True)
        lua.execute(open(path, encoding="utf-8", errors="replace").read())
        db = lua.globals().DufforthTweaksHelperDB
        account = Path(path).parents[1].name
        saved = datetime.fromtimestamp(os.path.getmtime(path)).strftime("%Y-%m-%d %H:%M")
        grind = db and db["grind"]
        kills = grind and grind["kills"]
        debug = _plain(grind["logDebug"]) if grind is not None and grind["logDebug"] is not None else None
        print(f"{account}: saved file written {saved}, " + explain(grind is not None, len(kills) if kills is not None else 0, debug))
        if grind is None or kills is None:
            continue
        errors = grind["logErrors"]
        if errors is not None:
            for message, count in _plain(errors).items():
                print(f"  log error x{count}: {message}")
        out.append((account, _plain(kills) or []))
    return out


def explain(has_grind, kills, debug):
    """One line on what the addon saw in the last session, and why there may be no kills."""
    if not has_grind:
        return "the Grind tab never ran on this account (new files: exit the game fully and start it again)"
    if debug is None:
        return (f"{kills} kills saved; no counters yet: the counting version hasn't run "
                "(install, restart the game, play, then /reload)")
    seen = (f"last session: {debug.get('combats', 0)} fights, {debug.get('chat', 0)} kill lines "
            f"({debug.get('parsed', 0)} read), {debug.get('xpUpdates', 0)} experience changes, "
            f"{debug.get('fallback', 0)} kills from the experience bar; {kills} kills saved")
    if kills:
        return seen
    if not debug.get("combats"):
        return seen + ". No fights in that session: fight a few monsters, then /reload (the game writes the file only then)"
    if debug.get("chat") and not debug.get("parsed"):
        return seen + f". The kill lines weren't understood: last one {debug.get('lastChat')!r}, format {debug.get('format')!r}"
    return seen + ". Fights but no experience: only kills that give experience are saved (gray monsters don't)"


def summary(kills, tune):
    print(f"{len(kills)} kills in the history.")
    if tune.get("below"):
        print(f"  lower-level cut: {tune['below'][0] * 100:.1f}% a level, at most {tune['below'][1] * 100:.0f}% "
              f"({tune['used']['below']} kills; the addon guessed 4% and 20%)")
    else:
        print(f"  lower-level cut: not enough solo kills below your level yet ({tune['used']['below']} of {MIN_BELOW})")
    for key, (speed, rest) in sorted(tune["specs"].items()):
        print(f"  {key}: kills {speed:.2f}x the average speed, rest {'?' if rest is None else f'{rest * 100:.0f}%'} "
              f"({tune['used']['specs'][key]} kills)")
    if not tune["specs"]:
        print(f"  specs: none with {MIN_SPEC}+ solo kills yet")
    print(f"  seen casting: {', '.join(tune['casters'][:12]) or 'none yet'}")
    print(f"  never seen casting ({MIN_QUIET}+ kills): {len(tune['noCast'])} monsters")
    by_spot = {}
    for k in kills:
        if k.get("spot") and k.get("cycle"):
            by_spot.setdefault((k.get("zone"), k["spot"]), []).append(k)
    if by_spot:
        print("  busiest spots (kills, real kills an hour, xp an hour):")
        for (zone, spot), ks in sorted(by_spot.items(), key=lambda kv: -len(kv[1]))[:6]:
            cycle = statistics.median(k["cycle"] for k in ks)
            xp = statistics.median(k["xp"] for k in ks)
            print(f"    {zone} spot {spot}: {len(ks)}, {3600 / cycle:.0f}, {3600 / cycle * xp:.0f}")


def main(argv):
    if not argv or argv[0].startswith("-"):
        sys.exit(__doc__)
    dry = "--dry" in argv
    history = []
    if HISTORY.exists():
        history = [json.loads(line) for line in HISTORY.read_text(encoding="utf-8").splitlines() if line.strip()]
    total_added = 0
    for account, kills in saved_kills(argv[0]):
        history, added = merge(history, kills, account)
        total_added += added
    HISTORY.parent.mkdir(parents=True, exist_ok=True)
    HISTORY.write_text("".join(json.dumps(k, ensure_ascii=False) + "\n" for k in history), encoding="utf-8")
    print(f"history: {total_added} new kills saved to {HISTORY}")
    if not history:
        print("No kills to learn from yet: nothing changed.")
        return
    tune = build_tune(history)
    summary(history, tune)
    if dry:
        return
    TUNE.write_text(json.dumps(tune, indent=1, ensure_ascii=False), encoding="utf-8")
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import build_addon_grind
    build_addon_grind.main(str(ROOT / "addon" / "DufforthTweaksHelper" / "GrindData.lua"))
    print("Install the addon and /reload to use it.")


if __name__ == "__main__":
    main(sys.argv[1:])
