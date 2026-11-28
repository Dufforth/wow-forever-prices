"""tools/analyze_leveling_log.py on a small saved file: the numbers and the guide fixes it suggests."""
import contextlib
import io
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import analyze_leveling_log as A  # noqa: E402


class AnalyzeLevelingTest(unittest.TestCase):
    def setUp(self):
        self.game = Path(tempfile.mkdtemp())
        folder = self.game / "WTF" / "Account" / "A1" / "SavedVariables"
        folder.mkdir(parents=True)
        shutil.copy(ROOT / "tests" / "data" / "leveling_saved_sample.lua", folder / "DufforthTweaksHelper.lua")
        self.rows = A.load(str(self.game))
        self.res = A.analyze(self.rows)

    def tearDown(self):
        shutil.rmtree(self.game)

    def test_rows_are_read(self):
        self.assertEqual(len(self.rows), 29)
        first = self.rows.iloc[0]
        self.assertEqual(first["kind"], "lg")
        self.assertEqual(first["part"], "1-6 Durotar")
        self.assertEqual(first["zone"], "Durotar")
        self.assertEqual(first["extra"], {})

    def test_time_per_part_leaves_idle_and_logout_out(self):
        parts = self.res["parts"].set_index("part")
        self.assertEqual(parts.loc["1-6 Durotar", "seconds"], 1800)   # 1300 (A) + 500 (B)
        self.assertEqual(parts.loc["6-10 Durotar", "seconds"], 500)
        self.assertEqual(parts.loc["1-6 Durotar", "xp"], 300)
        self.assertEqual(parts.loc["6-10 Durotar", "xp"], 120)        # 20 + 30, then 50 + 10 across the level-up, then 10

    def test_time_per_step(self):
        steps = self.res["steps"].set_index(["part", "line"])
        self.assertEqual(steps.loc[("1-6 Durotar", 8), "seconds"], 440)
        self.assertEqual(steps.loc[("1-6 Durotar", 15), "seconds"], 700)   # A 300 (600 idle left out) + B 400

    def test_skipped_most(self):
        skips = self.res["skips"]
        top = skips.iloc[0]
        self.assertEqual((top["part"], top["number"], top["line"], top["times"]), ("1-6 Durotar", 3, 12, 2))

    def test_wandered(self):
        far = self.res["wander"]
        self.assertEqual(list(zip(far["part"], far["line"])), [("6-10 Durotar", 3)])
        self.assertAlmostEqual(far.iloc[0]["distance"], 63.2, places=1)

    def test_deaths_dead_time_and_off_guide(self):
        self.assertEqual(self.res["deaths"].to_dict(), {"The Barrens": 2, "Durotar": 1})
        dead = self.res["dead"]
        self.assertEqual((dead["corpse"], dead["vendor"], dead["idle"]), (210, 40, 600))
        off = self.res["offguide"]
        self.assertEqual(list(off["quest"]), [9999])
        self.assertEqual(self.res["xp"], {"kills": 200, "quests": 100, "rested": 50})

    def test_report_and_fixes(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            A.report(self.res)
        text = out.getvalue()
        self.assertIn("2 characters, 38 min played", text)
        self.assertIn("1-6 Durotar: 30 min", text)
        self.assertIn("Skipped by hand: 1-6 Durotar step 3 (line 12) 2 times", text)
        self.assertIn("A Forever Quest (9999)", text)
        self.assertIn("The Barrens: 2 deaths", text)
        self.assertIn("FIX: 1-6 Durotar step 3 (line 12)", text)
        self.assertIn("FIX: 6-10 Durotar step 1 (line 3)", text)

    def test_empty_log_says_why(self):
        empty = Path(tempfile.mkdtemp())
        try:
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                A.main([str(empty)])
            self.assertIn("No leveling log", out.getvalue())
        finally:
            shutil.rmtree(empty)


if __name__ == "__main__":
    unittest.main()
