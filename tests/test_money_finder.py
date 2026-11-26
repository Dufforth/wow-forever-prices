"""tools/money_finder.py: vendor flips, underpriced listings and craft profit on a tiny made-up market."""
import sys
import unittest
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import money_finder as M  # noqa: E402


def items():
    return pd.DataFrame([
        {"id": 1, "name": "Grenade", "vendor_pays": 500, "vendor_sells": None, "lowest": 300, "market": 300, "listed": 10, "week": 320, "sold7": 50, "bop": 0},
        {"id": 2, "name": "Pattern", "vendor_pays": 0, "vendor_sells": None, "lowest": 1000, "market": 1000, "listed": 1, "week": 10000, "sold7": 30, "bop": 0},
        {"id": 3, "name": "Bar", "vendor_pays": 0, "vendor_sells": None, "lowest": 2000, "market": 2000, "listed": 5, "week": 2000, "sold7": 99, "bop": 0},
        {"id": 4, "name": "Thread", "vendor_pays": 0, "vendor_sells": 100, "lowest": 900, "market": 900, "listed": 5, "week": 900, "sold7": 99, "bop": 0},
        {"id": 5, "name": "Rod", "vendor_pays": 0, "vendor_sells": None, "lowest": 10000, "market": 10000, "listed": 2, "week": 10000, "sold7": 40, "bop": 0},
    ]).set_index("id")


class MoneyTest(unittest.TestCase):
    def test_vendor_flip(self):
        v = M.vendor_flips(items())
        self.assertEqual(list(v.index), [1])
        self.assertEqual(v.loc[1, "profit_all"], 2000)

    def test_underpriced(self):
        u = M.underpriced(items())
        self.assertEqual(list(u.index), [2])
        self.assertAlmostEqual(u.loc[2, "profit_each"], 10000 * 0.95 - 1000)

    def test_craft_uses_vendor_price_only_for_vendor_reagents(self):
        rec = [{"n": "Rod", "p": "Blacksmithing", "sk": 1, "o": ["trainer"], "i": 5, "c": 1, "r": [[3, 2], [4, 1]]}]
        c = M.crafts(items(), rec)
        self.assertEqual(c.iloc[0]["cost"], 2 * 2000 + 100)  # Thread from the vendor, Bars from the AH
        self.assertAlmostEqual(c.iloc[0]["profit"], 10000 * 0.95 - 4100)


if __name__ == "__main__":
    unittest.main()
