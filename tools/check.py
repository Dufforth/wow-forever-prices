#!/usr/bin/env python3
"""Run the tests for what you changed, and print only a summary and the failures (user, 2026-11-13: save tokens).

    python tools/check.py            tests for files changed since the last commit (git)
    python tools/check.py guide gear tests whose names contain these words
    python tools/check.py addon/DufforthTweaksHelper/Money.lua   tests for the files you edited (use this while
                                     much work is uncommitted: git diff would select nearly every test)
    python tools/check.py all        every test (only before pushing; takes 10+ minutes)
    -v                               also list the passing files

Prints only failing files (plus up to 8 failing lines each) and a summary; exit code 1 on any failure.
Missing test libraries (lupa, pandas) are installed with pip first.
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SIMS = ROOT / "tests" / "addon"
UNIT = ROOT / "tests"

# Changed file (or folder prefix) -> test files to run. Addon files without a match run the full-load test.
MAP = {
    "addon/DufforthTweaksHelper/Guide": ["guide_sim", "rxp_sim", "rxp_parity_sim"], "catalog/rxp_": ["rxp_sim", "rxp_parity_sim", "test_rxp_steps", "test_route_from_rxp"], "addon/DufforthTweaksHelper/Rested": ["rested_sim", "guide_sim", "locale_sim"], "addon/DufforthTweaksHelper/QuestAuto": ["quest_auto_sim"],
    "addon/DufforthTweaksHelper/Warrior": ["warrior_sim", "warrior_fight_sim", "druid_sim", "druid_fight_sim", "hunter_sim"],
    "addon/DufforthTweaksHelper/Druid": ["druid_sim", "druid_fight_sim", "full_load_sim"],
    "addon/DufforthTweaksHelper/Hunter": ["hunter_sim", "full_load_sim", "menu_sim"],
    "addon/DufforthTweaksHelper/LevelLog": ["levellog_sim", "full_load_sim", "menu_sim"],
    "tools/analyze_leveling_log": ["test_analyze_leveling"], "tests/data/leveling_saved": ["test_analyze_leveling"],
    "addon/DufforthTweaksHelper/Pet": ["pets_sim", "full_load_sim", "menu_sim"],
    "addon/DufforthTweaksHelper/Money": ["money_sim", "full_load_sim", "menu_sim"], "tools/money_finder": ["test_money_finder", "money_sim"],
    "tools/build_addon_money": ["test_money_finder", "money_sim"], "catalog/build_pets": ["test_build_pets"],
    "addon/DufforthTweaksHelper/Consumables": ["consumables_sim"], "addon/DufforthTweaksHelper/Gear": ["gear_sim"],
    "addon/DufforthTweaksHelper/Zone": ["zone_sim"], "addon/DufforthTweaksHelper/Grind": ["grind_sim"], "addon/DufforthTweaksHelper/Fishing": ["fishing_sim"], "catalog/build_fishing": ["fishing_sim"],
    "catalog/build_grind": ["test_grind"], "addon/DufforthTweaksHelper/Leveling": ["leveling_sim"],
    "addon/DufforthTweaksHelper/Craft": ["crafting_sim"], "addon/DufforthTweaksHelper/Disenchant": ["de_sim"],
    "addon/DufforthTweaksHelper/AutoDisenchant": ["de_sim"],
    "addon/DufforthTweaksHelper/Menu": ["menu_sim"], "addon/DufforthTweaksHelper/Locale": ["locale_sim", "full_load_sim"], "addon/DufforthTweaksHelper/Core": ["menu_sim", "full_load_sim"],
    "addon/DufforthTweaksHelper/DufforthTweaksHelper.toc": ["full_load_sim"],
    "catalog/route_questie": ["test_route_questie"], "catalog/route_forever": ["test_route_forever", "test_route_questie"],
    "tools/extract_questie": ["test_route_questie"],
    "catalog/route_data": ["test_route_data"], "catalog/route_planner": ["test_route_planner"],
    "catalog/route_travel": ["test_route_travel"], "catalog/route_guides": ["test_route_guides"],
    "catalog/route_model": ["test_route_data", "test_route_planner"], "catalog/build_route": ["test_route_travel", "test_route_guides"],
    "catalog/build_farm": ["test_farm", "test_route_data"], "tools/": ["test_tools"],
}


def all_tests():
    return sorted(p.stem for p in SIMS.glob("*_sim.py")) + sorted(p.stem for p in UNIT.glob("test_*.py"))


def targets(changed):
    """Test names for changed paths (repo-relative, forward slashes)."""
    out = []
    for path in changed:
        if path.startswith("tests/addon/") and path.endswith("_sim.py") or path.startswith("tests/test_") and path.endswith(".py"):
            hits = [Path(path).stem]
        else:
            hits = [t for prefix, tests in MAP.items() if path.startswith(prefix) for t in tests]
            if not hits and path.startswith("addon/"):
                hits = ["full_load_sim"]
        out += [h for h in hits if h not in out]
    return out


def changed_files():
    run = lambda *a: subprocess.run(["git", *a], cwd=ROOT, capture_output=True, text=True).stdout.split()
    return sorted(set(run("diff", "--name-only", "HEAD") + run("ls-files", "--others", "--exclude-standard")))


def pick(args):
    """Test names for arguments: file paths (contain a slash or a file extension) map through MAP, words match names."""
    paths = [a.replace("\\", "/") for a in args if "/" in a or "\\" in a or Path(a).suffix]
    words = [a for a in args if not ("/" in a or "\\" in a or Path(a).suffix)]
    out = targets(paths)
    out += [t for t in all_tests() if any(w in t for w in words) and t not in out]
    return out


def report(results, verbose=False):
    """Lines to print for [(name, ok, failing lines)]: failures only unless verbose, then the summary."""
    lines = []
    for name, ok, bad in results:
        if ok:
            if verbose:
                lines.append("ok   " + name)
            continue
        lines.append("FAIL " + name)
        lines += ["     " + l[:200] for l in bad[:8]]
    passed = sum(1 for _, ok, _ in results if ok)
    lines.append(f"{passed}/{len(results)} test files passed")
    return lines


def ensure_libs():
    missing = [m for m in ("lupa", "pandas") if subprocess.run([sys.executable, "-c", f"import {m}"], capture_output=True).returncode]
    if missing:
        print("installing " + ", ".join(missing))
        subprocess.run([sys.executable, "-m", "pip", "install", "--quiet", *missing], check=True)


def run(name):
    """(ok, failing lines) for one test file."""
    if name.endswith("_sim"):
        cmd = [sys.executable, str(SIMS / f"{name}.py")]
    else:
        cmd = [sys.executable, "-m", "unittest", "-q", f"tests.{name}"]
    p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace",
                       env={**__import__("os").environ, "PYTHONIOENCODING": "utf-8"})
    text = p.stdout + p.stderr
    bad = [l for l in text.splitlines() if l.startswith(("FAIL", "ERROR")) or "Error:" in l or l.startswith("Traceback")]
    return p.returncode == 0 and not any(l.startswith("FAIL") for l in text.splitlines()), bad


def main(args):
    verbose = "-v" in args
    args = [a for a in args if a != "-v"]
    ensure_libs()
    if args == ["all"]:
        names = all_tests()
    elif args:
        names = pick(args)
    else:
        names = targets(changed_files())
        if not names:
            print("no changed files with tests (use: python tools/check.py all)")
            return 0
    results = [(name, *run(name)) for name in names]
    print("\n".join(report(results, verbose)))
    return 0 if all(ok for _, ok, _ in results) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
