"""tools/analyze_hunter_fights.py on a small saved file: the numbers and the advice it gives."""
import contextlib
import io
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import analyze_hunter_fights as A  # noqa: E402


class AnalyzeTest(unittest.TestCase):
    def setUp(self):
        self.game = Path(tempfile.mkdtemp())
        folder = self.game / "WTF" / "Account" / "A1" / "SavedVariables"
        folder.mkdir(parents=True)
        shutil.copy(ROOT / "tests" / "data" / "hunter_saved_sample.lua", folder / "DufforthTweaksHelper.lua")

    def tearDown(self):
        shutil.rmtree(self.game)

    def test_report(self):
        fights, macros = A.load(str(self.game))
        self.assertEqual(len(fights), 2)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            A.report(fights, macros)
        text = out.getvalue()
        self.assertIn("won 1, died 1", text)
        self.assertIn("Mongoose Bite: 1 of 4 chances used (25%)", text)
        self.assertIn("Hunter's Mark went on the same enemy again 2 times", text)
        self.assertIn("two hawks already out", text)
        self.assertIn("Aimed Shot was interrupted 1 times", text)
        self.assertIn("Out of mana 2 times", text)
        self.assertIn("/castsequence reset=target Hunter's Mark,nil", text)
        self.assertIn("Auto Shot every 2.00 s on its own", text)
        self.assertIn("Arcane Shot: no delay (2.00 s, 1 times)", text)
        self.assertIn("Aimed Shot: delays your next Auto Shot by 1.00 s (3.00 s, 1 times)", text)  # the macro of the last fight with one

    def test_no_fights(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            A.report([], {})
        self.assertIn("No hunter fights saved yet", out.getvalue())

    def test_clipping_needs_times(self):
        fights, _ = A.load(str(self.game))
        for f in fights:
            f["autoTimes"] = []
        self.assertIsNone(A.clipping(fights))


if __name__ == "__main__":
    unittest.main()
