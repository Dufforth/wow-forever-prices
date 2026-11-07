import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "collector"))
import collect  # noqa: E402

MARKET = "forever.normal.horde.us"
START = 1_800_000_000
SECOND = START + 3600
DAY_ONE = START // collect.DAY


def api(rows, stamp, days=None, markets=None):
    def get(path):
        if path == "/ah":
            return {"markets": markets or [{"market": MARKET, "at": stamp * 1000, "listed": len(rows)}]}
        return {"market": MARKET, "at": stamp * 1000, "scan": stamp * 1000, "rows": rows, "days": days or []}
    return get


class ReadPricesTests(unittest.TestCase):
    def test_reads_wanted_items_with_a_price(self):
        rows = [[1, 100, 5, 0], [2, None, 0, 0], [3, 50, 1, 0], [2147483649, 70, 1, 0]]
        self.assertEqual(collect.read_prices({"rows": rows}, {1, 2}), {1: [100, 100, 5]})

    def test_market_labels(self):
        self.assertEqual(collect.market_labels("forever.pvp.alliance.us"), ("PvP", "Alliance"))
        self.assertEqual(collect.market_labels("forever.rp.horde.us"), ("Roleplay", "Horde"))


class CollectTests(unittest.TestCase):
    def run_snapshot(self, out, price, stamp, quantity=10, days=None):
        rows = [[1, price, quantity, stamp * 1000]] if price else [[1, None, 0, stamp * 1000]]
        collect.collect(out, api(rows, stamp, days), {1, 2}, {1}, stamp + 60)
        return json.loads((out / f"h{MARKET}.json").read_text())

    def test_previous_price_and_averages(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            first = self.run_snapshot(out, 100, START)
            self.assertEqual(first["items"]["1"], [100, 100, 10, None, 100, 100, 0])
            second = self.run_snapshot(out, 150, SECOND)
            self.assertEqual(second["items"]["1"][:5], [150, 150, 10, 100, 125])

    def test_new_market_starts_with_the_services_daily_history(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            days = [[1, [[DAY_ONE - 2, 80, 3], [DAY_ONE - 1, 90, 4]]], [999, [[DAY_ONE - 1, 5, 1]]]]
            house = self.run_snapshot(out, 100, START, days=days)
            history = json.loads((out / f"hist{MARKET}.json").read_text())
            self.assertEqual(history["days"]["i"]["1"], [80, 90, 100])
            self.assertNotIn("999", history["days"]["i"])
            self.assertEqual(house["items"]["1"][5], 90)

    def test_bought_estimate_adds_up_drops_in_quantity(self):
        snapshot = {"days": [[1, [[10, 5, 100], [11, 5, 70], [12, 5, 90], [13, 5, 85], [14, 5, None]]], [2, [[10, 5, 3]]]]}
        self.assertEqual(collect.estimate_bought(snapshot), {1: 35, 2: 0})
        self.assertEqual(collect.estimate_bought({}), {})

    def test_same_scan_twice_does_not_replace_previous(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            self.run_snapshot(out, 100, START)
            self.run_snapshot(out, 150, SECOND)
            again = self.run_snapshot(out, 150, SECOND)
            self.assertEqual(again["items"]["1"][3], 100)
            history = json.loads((out / f"hist{MARKET}.json").read_text())
            self.assertEqual(len(history["hours"]["t"]), 2)

    def test_item_no_longer_listed_keeps_last_price_with_zero_for_sale(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            self.run_snapshot(out, 100, START)
            gone = self.run_snapshot(out, None, SECOND)
            self.assertEqual(gone["items"]["1"][:3], [None, 100, 0])

    def test_history_is_trimmed_and_keeps_one_point_per_day(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            for hour in range(200):
                self.run_snapshot(out, 100 + hour, START + hour * 3600)
            history = json.loads((out / f"hist{MARKET}.json").read_text())
            self.assertEqual(len(history["hours"]["t"]), collect.HOURLY_KEEP)
            self.assertEqual(history["hours"]["i"]["1"][-1], 299)
            self.assertEqual(len(history["days"]["t"]), len(history["days"]["i"]["1"]))
            self.assertLess(len(history["days"]["t"]), 10)
            self.assertEqual(history["days"]["i"]["1"][-1], 299)

    def test_gear_is_priced_but_has_no_history(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            collect.collect(out, api([[2, 50, 1, 0]], START), {1, 2}, {1}, START)
            house = json.loads((out / f"h{MARKET}.json").read_text())
            history = json.loads((out / f"hist{MARKET}.json").read_text())
            self.assertEqual(house["items"]["2"][0], 50)
            self.assertNotIn("2", history["hours"]["i"])

    def test_meta_lists_markets_with_labels_and_scan_time(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            collect.collect(out, api([[1, 5, 1, 0]], START), {1}, {1}, START + 9)
            meta = json.loads((out / "meta.json").read_text())
            self.assertEqual(meta["updated"], START + 9)
            self.assertEqual(meta["houses"], [{"id": MARKET, "rulesetName": "Normal", "name": "Horde",
                                               "listings": 1, "scannedAt": START}])

    def test_one_failing_market_keeps_the_rest(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            other = "forever.pvp.horde.us"

            def get(path):
                if path == "/ah":
                    return {"markets": [{"market": MARKET}, {"market": other}]}
                if other in path:
                    raise ValueError("boom")
                return {"scan": START * 1000, "rows": [[1, 10, 1, 0]]}

            collect.collect(out, get, {1}, {1}, START)
            self.assertTrue((out / f"h{MARKET}.json").exists())
            self.assertFalse((out / f"h{other}.json").exists())

    def test_no_markets_is_an_error(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(RuntimeError):
                collect.collect(Path(folder), lambda path: {"markets": []}, {1}, {1}, START)


if __name__ == "__main__":
    unittest.main()
