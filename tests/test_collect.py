import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "collector"))
import collect  # noqa: E402

MARKET = "forever.normal.horde.us"
PVP_HORDE = "forever.pvp.horde.us"
START = 1_800_000_000
SECOND = START + 3600
DAY_ONE = START // collect.DAY


def public_api(rows, stamp, days=None, markets=None):
    def get(path):
        if path == "/ah":
            return {"markets": markets or [{"market": MARKET, "at": stamp * 1000, "listed": len(rows)}]}
        return {"market": MARKET, "at": stamp * 1000, "scan": stamp * 1000, "rows": rows, "days": days or []}
    return get


def no_public(path):
    if path == "/ah":
        return {"markets": []}
    raise AssertionError(path)


def blizzard_api(houses, stamp):
    """houses: {id: (regular listings, commodity listings)}."""
    def get(path):
        parts = path.strip("/").split("/")
        house = int(parts[0])
        if house not in houses:
            return {"id": house}, stamp
        return {"auctions": houses[house][1 if len(parts) > 1 else 0]}, stamp
    return get


def commodity(item, unit, quantity):
    return {"item": {"id": item}, "quantity": quantity, "unit_price": unit}


def read_house(out, market):
    return json.loads((out / f"h{market}.json").read_text())


def quiet(function, *args, **kwargs):
    with redirect_stdout(io.StringIO()) as log:
        function(*args, **kwargs)
    return log.getvalue()


class SummarizeTests(unittest.TestCase):
    def test_market_is_cheapest_15_percent_of_units(self):
        prices = collect.summarize([], [commodity(1, 100, 15), commodity(1, 200, 85)], {1})
        self.assertEqual(prices[1], [100, 100, 100])

    def test_market_blends_when_cheapest_listing_is_small(self):
        prices = collect.summarize([], [commodity(1, 100, 5), commodity(1, 200, 95)], {1})
        self.assertEqual(prices[1], [100, round((100 * 5 + 200 * 10) / 15), 100])

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


class PublicSourceTests(unittest.TestCase):
    def test_reads_wanted_items_with_a_price(self):
        rows = [[1, 100, 5, 0], [2, None, 0, 0], [3, 50, 1, 0], [2147483649, 70, 1, 0]]
        self.assertEqual(collect.read_public_prices({"rows": rows}, {1, 2}), {1: [100, 100, 5]})

    def test_market_labels(self):
        self.assertEqual(collect.market_labels("forever.pvp.alliance.us"), ("PvP", "Alliance"))
        self.assertEqual(collect.market_labels("forever.rp.horde.us"), ("Roleplay", "Horde"))
        self.assertEqual(collect.market_labels("forever.pvp.neutral.us"), ("PvP", "Blackwater"))
        self.assertEqual(collect.market_labels("forever.other119.horde.us"), ("House 119", "Horde"))

    def run_snapshot(self, out, price, stamp, quantity=10, days=None):
        rows = [[1, price, quantity, stamp * 1000]] if price else [[1, None, 0, stamp * 1000]]
        quiet(collect.collect, out, public_api(rows, stamp, days), {1, 2}, {1}, stamp + 60)
        return read_house(out, MARKET)

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

    def test_bought_estimate_adds_up_drops_in_daily_quantity(self):
        snapshot = {"days": [[1, [[10, 5, 100], [11, 5, 70], [12, 5, 90], [13, 5, 85], [14, 5, None]]], [2, [[10, 5, 3]]]]}
        self.assertEqual(collect.estimate_bought_from_days(snapshot), {1: 35, 2: 0})
        self.assertEqual(collect.estimate_bought_from_days({}), {})

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
            quiet(collect.collect, out, public_api([[2, 50, 1, 0]], START), {1, 2}, {1}, START)
            history = json.loads((out / f"hist{MARKET}.json").read_text())
            self.assertEqual(read_house(out, MARKET)["items"]["2"][0], 50)
            self.assertNotIn("2", history["hours"]["i"])

    def test_meta_lists_markets_with_labels_source_and_scan_time(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            quiet(collect.collect, out, public_api([[1, 5, 1, 0]], START), {1}, {1}, START + 9)
            meta = json.loads((out / "meta.json").read_text())
            self.assertEqual(meta["updated"], START + 9)
            self.assertEqual(meta["houses"], [{"id": MARKET, "rulesetName": "Normal", "name": "Horde",
                                               "listings": 1, "scannedAt": START, "source": "players"}])

    def test_one_failing_market_keeps_the_rest(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)

            def get(path):
                if path == "/ah":
                    return {"markets": [{"market": MARKET}, {"market": PVP_HORDE}]}
                if PVP_HORDE in path:
                    raise ValueError("boom")
                return {"scan": START * 1000, "rows": [[1, 10, 1, 0]]}

            with redirect_stdout(io.StringIO()):
                collect.collect(out, get, {1}, {1}, START)
            self.assertTrue((out / f"h{MARKET}.json").exists())
            self.assertFalse((out / f"h{PVP_HORDE}.json").exists())

    def test_nothing_readable_is_an_error(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(RuntimeError):
                collect.collect(Path(folder), no_public, {1}, {1}, START)


class UpdateCheckTests(unittest.TestCase):
    META = {"updated": START, "houses": [{"id": PVP_HORDE, "scannedAt": START - 100}, {"id": MARKET, "scannedAt": START - 100}]}

    def test_updates_as_soon_as_a_house_is_newer(self):
        self.assertTrue(collect.needs_update(self.META, {PVP_HORDE: START - 99}, START + 60))

    def test_waits_when_nothing_is_newer(self):
        self.assertFalse(collect.needs_update(self.META, {PVP_HORDE: START - 100, MARKET: START - 200}, START + 60))

    def test_unknown_markets_do_not_trigger_an_update(self):
        self.assertFalse(collect.needs_update(self.META, {"forever.other119.horde.us": START}, START + 60))

    def test_still_updates_hourly_if_a_check_finds_nothing(self):
        self.assertTrue(collect.needs_update(self.META, {}, START + 3600))
        self.assertFalse(collect.needs_update(self.META, {}, START + 3599))

    def test_first_run_updates(self):
        self.assertTrue(collect.needs_update(None, {}, START))

    def test_check_writes_its_answer_for_the_workflow(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            (out / "meta.json").write_text(json.dumps({"updated": 9999999999, "houses": []}))
            result = out / "github_output"
            saved = {k: collect.os.environ.pop(k, None) for k in ("BLIZZARD_CLIENT_ID", "BLIZZARD_CLIENT_SECRET", "GITHUB_OUTPUT")}
            collect.os.environ["GITHUB_OUTPUT"] = str(result)
            try:
                quiet(collect.check_for_update, out, "us")
            finally:
                del collect.os.environ["GITHUB_OUTPUT"]
                for key, value in saved.items():
                    if value is not None:
                        collect.os.environ[key] = value
            self.assertEqual(result.read_text(), "changed=false\n")


class BlizzardTests(unittest.TestCase):
    def test_house_ids_become_market_names_with_market_averages(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            api = blizzard_api({113: ([], [commodity(1, 100, 5), commodity(1, 200, 95)])}, START)
            quiet(collect.collect, out, no_public, {1}, {1}, START, api)
            row = read_house(out, PVP_HORDE)["items"]["1"]
            self.assertEqual(row[:3], [100, 167, 100])
            meta = json.loads((out / "meta.json").read_text())
            self.assertEqual([(h["id"], h["rulesetName"], h["name"], h["source"]) for h in meta["houses"]],
                             [(PVP_HORDE, "PvP", "Horde", "blizzard")])

    def test_empty_houses_are_left_out(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            quiet(collect.collect, out, no_public, {1}, {1}, START, blizzard_api({113: ([], [commodity(1, 5, 1)]), 110: ([], [])}, START))
            self.assertFalse((out / "hforever.pvp.alliance.us.json").exists())

    def test_blizzard_wins_and_the_public_source_fills_the_gaps(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            markets = [{"market": PVP_HORDE, "at": START * 1000, "listed": 1}, {"market": "forever.rp.horde.us", "at": START * 1000, "listed": 1}]
            public = public_api([[1, 999, 1, 0]], START, markets=markets)
            quiet(collect.collect, out, public, {1}, {1}, START, blizzard_api({113: ([], [commodity(1, 50, 2)])}, START))
            self.assertEqual(read_house(out, PVP_HORDE)["items"]["1"][0], 50)
            self.assertEqual(read_house(out, "forever.rp.horde.us")["items"]["1"][0], 999)
            sources = {h["id"]: h["source"] for h in json.loads((out / "meta.json").read_text())["houses"]}
            self.assertEqual(sources, {PVP_HORDE: "blizzard", "forever.rp.horde.us": "players"})

    def test_a_failing_house_falls_back_to_the_public_source(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)

            def broken(path):
                raise ValueError("boom")

            markets = [{"market": PVP_HORDE, "at": START * 1000, "listed": 1}]
            with redirect_stdout(io.StringIO()):
                collect.collect(out, public_api([[1, 999, 1, 0]], START, markets=markets), {1}, {1}, START, broken)
            self.assertEqual(read_house(out, PVP_HORDE)["items"]["1"][0], 999)

    def test_a_failing_public_source_does_not_lose_blizzard_prices(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)

            def broken(path):
                raise ValueError("boom")

            with redirect_stdout(io.StringIO()):
                collect.collect(out, broken, {1}, {1}, START, blizzard_api({113: ([], [commodity(1, 5, 1)])}, START))
            self.assertTrue((out / "meta.json").exists())

    def test_bought_estimate_adds_drops_between_snapshots(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            for stamp, quantity in ((START, 100), (SECOND, 70), (SECOND + 3600, 90), (SECOND + 7200, 60)):
                quiet(collect.collect, out, no_public, {1, 2}, {1, 2}, stamp, blizzard_api({113: ([], [commodity(1, 5, quantity), commodity(2, 5, 4)] if stamp == START else [commodity(1, 5, quantity)])}, stamp))
            items = read_house(out, PVP_HORDE)["items"]
            self.assertEqual(items["1"][6], 60)
            self.assertEqual(items["2"][6], 4, "a whole listing disappearing counts too")

    def test_bought_estimate_keeps_seven_days(self):
        history, previous = {}, {"1": [5, 5, 10]}
        for day in range(9):
            totals = collect.track_bought(history, START + day * collect.DAY, previous, {1: [5, 5, 9]})
        self.assertEqual(totals, {1: 7})

    def test_log_reports_which_house_matches_each_scanned_market(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            markets = [{"market": PVP_HORDE, "at": START * 1000, "listed": 1}]
            public = public_api([[1, 100, 1, 0], [2, 200, 1, 0]], START, markets=markets)
            api = blizzard_api({113: ([], [commodity(1, 101, 1), commodity(2, 200, 1)]), 114: ([], [commodity(1, 500, 1), commodity(2, 900, 1)])}, START)
            log = quiet(collect.collect, out, public, {1, 2}, {1}, START, api)
            self.assertIn("matches: forever.pvp.horde.us agrees most with house 113", log)


if __name__ == "__main__":
    unittest.main()
