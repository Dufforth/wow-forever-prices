import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "collector"))
import collect  # noqa: E402

HOUSE = {"id": 110, "name": "Alliance"}
START = 1_800_000_000


def fake_api(regular, commodities, stamp):
    def fetch(path):
        if path.endswith("/index"):
            if "/ruleset/1/" in path:
                return {"auctions": [HOUSE]}, None
            raise collect.HttpNotFound(path)
        if path.endswith("/commodities"):
            return {"auctions": commodities}, stamp
        return {"auctions": regular}, stamp
    return fetch


def commodity(item, unit, quantity):
    return {"id": 1, "item": {"id": item}, "quantity": quantity, "unit_price": unit, "time_left": "LONG"}


class SummarizeTests(unittest.TestCase):
    def test_market_is_cheapest_15_percent_of_units(self):
        prices = collect.summarize([], [commodity(1, 100, 15), commodity(1, 200, 85)], {1})
        self.assertEqual(prices[1], [100, 100, 100])

    def test_market_blends_when_cheapest_listing_is_small(self):
        prices = collect.summarize([], [commodity(1, 100, 5), commodity(1, 200, 95)], {1})
        self.assertEqual(prices[1][1], round((100 * 5 + 200 * 10) / 15))

    def test_regular_auctions_use_price_per_unit(self):
        regular = [{"item": {"id": 2}, "quantity": 4, "buyout": 400}]
        self.assertEqual(collect.summarize(regular, [], {2})[2], [100, 100, 4])

    def test_skips_no_buyout_bonus_items_and_unwanted(self):
        regular = [
            {"item": {"id": 2}, "quantity": 1, "bid": 5},
            {"item": {"id": 2, "bonus_lists": [1]}, "quantity": 1, "buyout": 5},
            {"item": {"id": 3}, "quantity": 1, "buyout": 5},
        ]
        self.assertEqual(collect.summarize(regular, [], {2}), {})


class CollectTests(unittest.TestCase):
    def run_snapshot(self, out, unit, stamp, quantity=10):
        api = fake_api([], [commodity(1, unit, quantity)] if quantity else [], stamp)
        collect.collect(out, api, {1, 2}, {1}, "us", stamp + 60)
        return json.loads((out / "h110.json").read_text())

    def test_previous_price_and_averages(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            first = self.run_snapshot(out, 100, START)
            self.assertEqual(first["items"]["1"], [100, 100, 10, None, 100, 100])
            second = self.run_snapshot(out, 150, START + 3600)
            self.assertEqual(second["items"]["1"], [150, 150, 10, 100, 125, 125])

    def test_unchanged_snapshot_does_not_replace_previous(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            self.run_snapshot(out, 100, START)
            self.run_snapshot(out, 150, START + 3600)
            again = self.run_snapshot(out, 150, START + 3600)
            self.assertEqual(again["items"]["1"][3], 100)
            history = json.loads((out / "hist110.json").read_text())
            self.assertEqual(len(history["hours"]["t"]), 2)

    def test_item_no_longer_listed_keeps_last_price_with_zero_for_sale(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            self.run_snapshot(out, 100, START)
            gone = self.run_snapshot(out, 100, START + 3600, quantity=0)
            self.assertEqual(gone["items"]["1"][:3], [None, 100, 0])

    def test_history_is_trimmed_and_daily_points_average(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            for hour in range(200):
                self.run_snapshot(out, 100 + hour, START + hour * 3600)
            history = json.loads((out / "hist110.json").read_text())
            self.assertEqual(len(history["hours"]["t"]), collect.HOURLY_KEEP)
            self.assertEqual(history["hours"]["i"]["1"][-1], 299)
            self.assertEqual(len(history["days"]["t"]), len(history["days"]["i"]["1"]))
            self.assertLess(len(history["days"]["t"]), 10)

    def test_gear_is_priced_but_has_no_history(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            api = fake_api([], [commodity(2, 50, 1)], START)
            collect.collect(out, api, {1, 2}, {1}, "us", START)
            house = json.loads((out / "h110.json").read_text())
            history = json.loads((out / "hist110.json").read_text())
            self.assertEqual(house["items"]["2"][0], 50)
            self.assertNotIn("2", history["hours"]["i"])

    def test_one_failing_house_keeps_the_rest(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)

            def fetch(path):
                if path.endswith("/index"):
                    if "/ruleset/1/" in path:
                        return {"auctions": [HOUSE, {"id": 111, "name": "Horde"}]}, None
                    raise collect.HttpNotFound(path)
                if "/111" in path:
                    raise ValueError("boom")
                return {"auctions": [commodity(1, 10, 1)]}, START

            collect.collect(out, fetch, {1}, {1}, "us", START)
            self.assertTrue((out / "h110.json").exists())
            self.assertFalse((out / "h111.json").exists())

    def test_no_houses_is_an_error(self):
        with tempfile.TemporaryDirectory() as folder:
            def fetch(path):
                raise collect.HttpNotFound(path)
            with self.assertRaises(RuntimeError):
                collect.collect(Path(folder), fetch, {1}, {1}, "us", START)


if __name__ == "__main__":
    unittest.main()
