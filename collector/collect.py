#!/usr/bin/env python3
"""Fetch WoW Forever prices from the public auctionhouse.fyi API and update the price files.

No key is needed. Prices come from players scanning the auction house in game, and each
market has an hourly snapshot: https://auctionhouse.fyi/docs/api

    python collector/collect.py --out state

Writes, for each market, h<market>.json (current prices) and hist<market>.json (history),
plus meta.json listing the markets. Prices are the lowest asking price per unit in copper.
"""
import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
API = "https://auctionhouse.fyi/api/v1"
AGENT = "wow-forever-prices (personal price page)"
RULESETS = {"normal": "Normal", "pvp": "PvP", "rp": "Roleplay"}
HOURLY_KEEP = 24 * 7
DAILY_KEEP = 60
DAY = 86400


def fetch(path):
    """The JSON at an API path, waiting and retrying when the service asks for that."""
    request = urllib.request.Request(API + path, headers={"User-Agent": AGENT, "Accept": "application/json"})
    for wait in (5, 30, None):
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if error.code not in (429, 500, 502, 503, 504) or wait is None:
                raise
            time.sleep(int(error.headers.get("Retry-After") or wait))
        except urllib.error.URLError:
            if wait is None:
                raise
            time.sleep(wait)
    raise RuntimeError("unreachable")


def market_labels(market):
    """("Normal", "Horde") from "forever.normal.horde.us"."""
    parts = market.split(".")
    ruleset = parts[1] if len(parts) > 1 else market
    faction = parts[2] if len(parts) > 2 else ""
    return RULESETS.get(ruleset, ruleset.title()), faction.title()


def read_prices(snapshot, wanted):
    """{item: [lowest, lowest, quantity]} for the wanted items that have a price."""
    prices = {}
    for row in snapshot.get("rows") or []:
        key, price, quantity = row[0], row[1], row[2]
        if key in wanted and price:
            prices[key] = [price, price, quantity or 0]
    return prices


def mean(values):
    values = [v for v in values if v is not None]
    return round(sum(values) / len(values)) if values else None


def load_json(path, default):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def estimate_bought(snapshot):
    """{item: units gone over the service's seven days}: each drop in daily quantity.

    This is only an estimate, because listings also expire or get cancelled.
    """
    bought = {}
    for key, points in snapshot.get("days") or []:
        quantities = [point[2] for point in points if point[2] is not None]
        bought[key] = sum(max(0, old - new) for old, new in zip(quantities, quantities[1:]))
    return bought


def seed_days(snapshot, tracked):
    """A new market starts with the service's seven days of daily closes."""
    by_item = {}
    all_days = set()
    for key, points in snapshot.get("days") or []:
        if key in tracked:
            by_item[key] = {point[0]: point[1] for point in points}
            all_days.update(by_item[key])
    ordered = sorted(all_days)
    return {
        "t": [day * DAY for day in ordered],
        "i": {str(key): [closes.get(day) for day in ordered] for key, closes in by_item.items()},
    }


def add_history(history, stamp, prices, tracked):
    """Adds a snapshot: hourly for a week, one point per day for 60 days."""
    hours = history.setdefault("hours", {"t": [], "i": {}})
    days = history.setdefault("days", {"t": [], "i": {}})

    def append(section, point, values):
        for series in section["i"].values():
            series.append(None)
        section["t"].append(point)
        size = len(section["t"])
        for item_id, value in values.items():
            key = str(item_id)
            if key not in section["i"]:
                section["i"][key] = [None] * size
            section["i"][key][-1] = value

    values = {item_id: row[1] for item_id, row in prices.items() if item_id in tracked}
    append(hours, stamp, values)

    day = stamp - stamp % DAY
    if days["t"] and days["t"][-1] == day:
        for item_id, value in values.items():
            series = days["i"].setdefault(str(item_id), [None] * len(days["t"]))
            series[-1] = value  # The day's point is its latest price.
    else:
        append(days, day, values)

    for section, keep in ((hours, HOURLY_KEEP), (days, DAILY_KEEP)):
        drop = max(0, len(section["t"]) - keep)
        if drop:
            section["t"] = section["t"][drop:]
            section["i"] = {k: s[drop:] for k, s in section["i"].items() if any(v is not None for v in s[drop:])}
    return history


def build_house_file(stamp, prices, history, previous, bought):
    """{item: [lowest, lowest, quantity, previous, 24 h average, 7 day average, bought estimate]}."""
    hours, days = history["hours"], history["days"]
    rows = {}
    for key in set(str(i) for i in prices) | set(hours["i"]) | set(days["i"]):
        hourly = hours["i"].get(key, [])
        daily = days["i"].get(key, [])
        current = prices.get(int(key))
        known = [v for v in hourly if v is not None] or [v for v in daily if v is not None]
        price = current[1] if current else (known[-1] if known else None)
        if price is None:
            continue
        old = previous.get(key)
        rows[key] = [current[0] if current else None, price, current[2] if current else 0,
                     old[1] if old else None, mean(hourly[-24:]), mean(daily[-7:]), bought.get(int(key), 0)]
    return {"ts": stamp, "items": rows}


def update_market(out, house, get, wanted, tracked):
    market = house["id"]
    snapshot = get(f"/ah/{market}/snapshot")
    stamp = (snapshot.get("scan") or snapshot.get("at") or 0) // 1000
    house_path, history_path = out / f"h{market}.json", out / f"hist{market}.json"
    old_house = load_json(house_path, {})
    if not stamp or old_house.get("ts") == stamp:
        return False

    prices = read_prices(snapshot, wanted)
    history = load_json(history_path, None)
    if history is None:
        history = {"hours": {"t": [], "i": {}}, "days": seed_days(snapshot, tracked)}
    add_history(history, stamp, prices, tracked)
    house_file = build_house_file(stamp, prices, history, old_house.get("items", {}), estimate_bought(snapshot))
    house_path.write_text(json.dumps(house_file, separators=(",", ":")), encoding="utf-8")
    history_path.write_text(json.dumps(history, separators=(",", ":")), encoding="utf-8")
    return True


def collect(out, get, wanted, tracked, now):
    out.mkdir(parents=True, exist_ok=True)
    listing = get("/ah")
    houses = []
    for row in listing.get("markets") or []:
        ruleset, faction = market_labels(row["market"])
        houses.append({"id": row["market"], "rulesetName": ruleset, "name": faction,
                       "listings": row.get("listed") or 0, "scannedAt": (row.get("at") or 0) // 1000})
    if not houses:
        raise RuntimeError("the API listed no markets")
    errors = 0
    for house in houses:
        try:
            changed = update_market(out, house, get, wanted, tracked)
            print(f"{house['id']}: {house['listings']} listed, {'updated' if changed else 'unchanged'}")
        except Exception as error:  # one failing market must not lose the others
            errors += 1
            print(f"{house['id']} failed: {type(error).__name__}", file=sys.stderr)
    meta = {"updated": now, "houses": houses}
    (out / "meta.json").write_text(json.dumps(meta, separators=(",", ":")), encoding="utf-8")
    if errors == len(houses):
        raise RuntimeError("every market failed")


def load_wanted(root):
    catalog = json.loads((root / "site/catalog.json").read_text(encoding="utf-8"))
    gear = json.loads((root / "site/gear.json").read_text(encoding="utf-8"))
    tracked = {int(k) for k in catalog["items"]}
    return tracked | {int(k) for k in gear}, tracked


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=Path("state"))
    args = parser.parse_args()
    wanted, tracked = load_wanted(ROOT)
    collect(args.out, fetch, wanted, tracked, int(time.time()))


if __name__ == "__main__":
    main()
