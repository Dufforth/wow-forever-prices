#!/usr/bin/env python3
"""Run the tests for what you changed, and print only a summary and the failures (user, 2026-11-13: save tokens).

    python tools/check.py            tests for files changed since the last commit (git)
    python tools/check.py guide gear tests whose names contain these words
    python tools/check.py all        every test (do this before installing or pushing)

One line per test file ("ok guide_sim" or "FAIL guide_sim" plus up to 8 failing lines); exit code 1 on any failure.
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
    "addon/DufforthTweaksHelper/Guide": ["guide_sim"], "addon/DufforthTweaksHelper/QuestAuto": ["quest_auto_sim"],
    "addon/DufforthTweaksHelper/Warrior": ["warrior_sim", "warrior_fight_sim"],
    "addon/DufforthTweaksHelper/Consumables": ["consumables_sim"], "addon/DufforthTweaksHelper/Gear": ["gear_sim"],
    "addon/DufforthTweaksHelper/Zone": ["zone_sim"], "addon/DufforthTweaksHelper/Leveling": ["leveling_sim"],
    "addon/DufforthTweaksHelper/Craft": ["crafting_sim"], "addon/DufforthTweaksHelper/Disenchant": ["de_sim"],
    "addon/DufforthTweaksHelper/AutoDisenchant": ["de_sim"],
    "addon/DufforthTweaksHelper/Menu": ["menu_sim"], "addon/DufforthTweaksHelper/Core": ["menu_sim", "full_load_sim"],
    "addon/DufforthTweaksHelper/DufforthTweaksHelper.toc": ["full_load_sim"],
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
    ensure_libs()
    if args == ["all"]:
        names = all_tests()
    elif args:
        names = [t for t in all_tests() if any(a in t for a in args)]
    else:
        names = targets(changed_files())
        if not names:
            print("no changed files with tests (use: python tools/check.py all)")
            return 0
    failed = 0
    for name in names:
        ok, bad = run(name)
        print(("ok   " if ok else "FAIL ") + name)
        if not ok:
            failed += 1
            for line in bad[:8]:
                print("     " + line[:200])
    print(f"{len(names) - failed}/{len(names)} test files passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
