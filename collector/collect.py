#!/usr/bin/env python3
"""Fetch WoW Forever auction houses from the Battle.net API and update the price files.

Needs BLIZZARD_CLIENT_ID and BLIZZARD_CLIENT_SECRET in the environment.

    python collector/collect.py --out state --region us

Writes, for each auction house, h<id>.json (current prices) and hist<id>.json (history),
plus meta.json listing the houses. Prices are asking prices in copper, not sales.
"""
import argparse
import base64
import gzip
import json
import os
import sys
import time
import urllib.error
import urllib.request
from email.utils import parsedate_to_datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RULESETS = {1: "PvP", 2: "Normal", 3: "Roleplay", 15: "Roleplay PvP"}
HOURLY_KEEP = 24 * 7
DAILY_KEEP = 60
DAY = 86400


class HttpNotFound(Exception):
    pass


def get_token(client, secret):
    basic = base64.b64encode(f"{client}:{secret}".encode()).decode()
    request = urllib.request.Request("https://oauth.battle.net/token", data=b"grant_type=client_credentials",
                                     headers={"Authorization": f"Basic {basic}"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)["access_token"]


def make_fetcher(token, region):
    base = f"https://{region}.api.blizzard.com"
    namespace = f"dynamic-forever-{region}"

    def fetch(path):
        """The JSON body and the Last-Modified time of a GET."""
        request = urllib.request.Request(f"{base}{path}?namespace={namespace}",
                                         headers={"Authorization": f"Bearer {token}", "Accept-Encoding": "gzip"})
        for attempt, wait in enumerate((5, 20, None)):
            try:
                with urllib.request.urlopen(request, timeout=120) as response:
                    body = response.read()
                    if response.headers.get("Content-Encoding") == "gzip":
                        body = gzip.decompress(body)
                    modified = response.headers.get("Last-Modified")
                    stamp = int(parsedate_to_datetime(modified).timestamp()) if modified else None
                    return json.loads(body), stamp
            except urllib.error.HTTPError as error:
                if error.code == 404:
                    raise HttpNotFound(path) from error
                if error.code not in (429, 500, 502, 503, 504) or wait is None:
                    raise
            except urllib.error.URLError:
                if wait is None:
                    raise
            time.sleep(wait)
        raise RuntimeError("unreachable")

    return fetch


def list_houses(fetch):
    houses = {}
    for ruleset, ruleset_name in RULESETS.items():
        try:
            index, _ = fetch(f"/data/wow/ruleset/{ruleset}/auctions/index")
        except HttpNotFound:
            continue
        for row in index.get("auctions", []):
            house_id = row.get("id")
            if house_id is not None and house_id not in houses:
                houses[house_id] = {"id": house_id, "ruleset": ruleset, "rulesetName": ruleset_name,
                                    "name": str(row.get("name") or f"House {house_id}")}
    return list(houses.values())


def unit_listings(regular, commodities):
    """(item ID, copper per unit, quantity) for each plain listing with a buyout."""
    for listing in regular:
        item = listing.get("item") or {}
        quantity, buyout = listing.get("quantity") or 0, listing.get("buyout") or 0
        if quantity > 0 and buyout > 0 and "id" in item and not item.get("bonus_lists"):
            yield item["id"], buyout / quantity, quantity
    for listing in commodities:
        item = listing.get("item") or {}
        quantity, unit = listing.get("quantity") or 0, listing.get("unit_price") or 0
        if quantity > 0 and unit > 0 and "id" in item:
            yield item["id"], unit, quantity


def summarize(regular, commodities, wanted):
    """{item: [lowest, market, quantity]}. Market is the mean of the cheapest 15% of units."""
    by_item = {}
    for item_id, unit, quantity in unit_listings(regular, commodities):
        if item_id in wanted:
            by_item.setdefault(item_id, []).append((unit, quantity))
    prices = {}
    for item_id, listings in by_item.items():
        listings.sort()
        total = sum(quantity for _, quantity in listings)
        need = max(1, round(total * 0.15))
        taken, cost = 0, 0.0
        for unit, quantity in listings:
            take = min(quantity, need - taken)
            taken += take
            cost += unit * take
            if taken >= need:
                break
        prices[item_id] = [round(listings[0][0]), round(cost / taken), total]
    return prices


def mean(values):
    values = [v for v in values if v is not None]
    return round(sum(values) / len(values)) if values else None


def load_json(path, default):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


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

    # A finished UTC day becomes one daily point when the first snapshot of a later day arrives.
    day = stamp - stamp % DAY
    if days["t"] and days["t"][-1] == day:
        count = days.setdefault("n", 1) + 1
        days["n"] = count
        for item_id, value in values.items():
            series = days["i"].setdefault(str(item_id), [None] * len(days["t"]))
            old = series[-1]
            series[-1] = value if old is None else round(old + (value - old) / count)
    else:
        days["n"] = 1
        append(days, day, values)

    for section, keep in ((hours, HOURLY_KEEP), (days, DAILY_KEEP)):
        drop = max(0, len(section["t"]) - keep)
        if drop:
            section["t"] = section["t"][drop:]
            section["i"] = {k: s[drop:] for k, s in section["i"].items() if any(v is not None for v in s[drop:])}
    return history


def build_house_file(stamp, prices, history, previous):
    """{item: [lowest, market, quantity, previous market, 24 h average, 7 day average]}."""
    hours = history["hours"]
    last_day = 24
    rows = {}
    ids = set(str(i) for i in prices) | set(hours["i"])
    for key in ids:
        series = hours["i"].get(key, [])
        current = prices.get(int(key))
        known = [v for v in series if v is not None]
        market = current[1] if current else (known[-1] if known else None)
        if market is None:
            continue
        old = previous.get(key)
        prev_market = old[1] if old else None
        rows[key] = [current[0] if current else None, market, current[2] if current else 0, prev_market,
                     mean(series[-last_day:]), mean(series)]
    return {"ts": stamp, "items": rows}


def update_house(out, house, fetch, wanted, tracked, now):
    house_id = house["id"]
    path = f"/data/wow/ruleset/{house['ruleset']}/auctions/{house_id}"
    body, stamp = fetch(path)
    regular = body.get("auctions") or []
    try:
        commodities_body, commodity_stamp = fetch(f"{path}/commodities")
        commodities = commodities_body.get("auctions") or []
        stamp = max(s for s in (stamp, commodity_stamp, 0) if s is not None) or None
    except HttpNotFound:
        commodities = []
    stamp = stamp or now

    house_path, history_path = out / f"h{house_id}.json", out / f"hist{house_id}.json"
    old_house = load_json(house_path, {})
    house["listings"] = len(regular) + len(commodities)
    if old_house.get("ts") == stamp:
        return False

    prices = summarize(regular, commodities, wanted)
    history = add_history(load_json(history_path, {}), stamp, prices, tracked)
    house_file = build_house_file(stamp, prices, history, old_house.get("items", {}))
    house_path.write_text(json.dumps(house_file, separators=(",", ":")), encoding="utf-8")
    history_path.write_text(json.dumps(history, separators=(",", ":")), encoding="utf-8")
    return True


def collect(out, fetch, wanted, tracked, region, now):
    out.mkdir(parents=True, exist_ok=True)
    houses = list_houses(fetch)
    if not houses:
        raise RuntimeError("the API listed no auction houses")
    errors = 0
    for house in houses:
        try:
            changed = update_house(out, house, fetch, wanted, tracked, now)
            print(f"house {house['id']} {house['rulesetName']}/{house['name']}: "
                  f"{house['listings']} listings, {'updated' if changed else 'unchanged'}")
        except Exception as error:  # one failing house must not lose the others
            errors += 1
            print(f"house {house['id']} failed: {type(error).__name__}", file=sys.stderr)
    meta = {"updated": now, "region": region, "houses": houses}
    (out / "meta.json").write_text(json.dumps(meta, separators=(",", ":")), encoding="utf-8")
    if errors == len(houses):
        raise RuntimeError("every auction house failed")


def load_wanted(root):
    catalog = json.loads((root / "site/catalog.json").read_text(encoding="utf-8"))
    gear = json.loads((root / "site/gear.json").read_text(encoding="utf-8"))
    tracked = {int(k) for k in catalog["items"]}
    return tracked | {int(k) for k in gear}, tracked


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=Path("state"))
    parser.add_argument("--region", default="us")
    args = parser.parse_args()
    client, secret = os.environ.get("BLIZZARD_CLIENT_ID"), os.environ.get("BLIZZARD_CLIENT_SECRET")
    if not client or not secret:
        sys.exit("BLIZZARD_CLIENT_ID and BLIZZARD_CLIENT_SECRET are not set")
    wanted, tracked = load_wanted(ROOT)
    token = get_token(client, secret)
    collect(args.out, make_fetcher(token, args.region), wanted, tracked, args.region, int(time.time()))


if __name__ == "__main__":
    main()
