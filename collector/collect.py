#!/usr/bin/env python3
"""Update the price files from Blizzard's API, with auctionhouse.fyi as the backup.

    python collector/collect.py --out state

With BLIZZARD_CLIENT_ID and BLIZZARD_CLIENT_SECRET set, each market comes from Blizzard's
API. Any market Blizzard can't provide comes from the public auctionhouse.fyi API, whose
prices are player scans of the lowest listing and need no key.

Writes, for each market, h<market>.json (current prices) and hist<market>.json (history),
plus meta.json listing the markets. Prices are asking prices in copper, not sales.
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
PUBLIC_API = "https://auctionhouse.fyi/api/v1"
AGENT = "wow-forever-prices (personal price page)"
RULESETS = {"normal": "Normal", "pvp": "PvP", "rp": "Roleplay"}
HOURLY_KEEP = 24 * 7
DAILY_KEEP = 60
BOUGHT_DAYS = 7
DAY = 86400

# The ruleset in the address doesn't select the market, so one is used for every house.
BLIZZARD_RULESET = 1
# Blizzard's house IDs, which its API doesn't label. PvP is confirmed by another project;
# the rest come from comparing listings, so check the "matches" lines in the log.
BLIZZARD_HOUSES = {
    110: ("pvp", "alliance"), 113: ("pvp", "horde"), 116: ("pvp", "neutral"),
    111: ("normal", "alliance"), 114: ("normal", "horde"), 117: ("normal", "neutral"),
    119: ("other119", "alliance"), 120: ("other119", "horde"), 121: ("other119", "neutral"),
    123: ("other123", "alliance"), 124: ("other123", "horde"), 125: ("other123", "neutral"),
}


class NotFound(Exception):
    pass


def request_json(request):
    """The JSON and the Last-Modified time of a request, retrying when the service is busy."""
    for wait in (5, 30, None):
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
                raise NotFound(request.full_url) from error
            if error.code not in (429, 500, 502, 503, 504) or wait is None:
                raise
            time.sleep(int(error.headers.get("Retry-After") or wait))
        except urllib.error.URLError:
            if wait is None:
                raise
            time.sleep(wait)
    raise RuntimeError("unreachable")


def public_get(path):
    request = urllib.request.Request(PUBLIC_API + path, headers={"User-Agent": AGENT, "Accept": "application/json"})
    return request_json(request)[0]


def blizzard_token(client, secret):
    basic = base64.b64encode(f"{client}:{secret}".encode()).decode()
    request = urllib.request.Request("https://oauth.battle.net/token", data=b"grant_type=client_credentials",
                                     headers={"Authorization": f"Basic {basic}"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)["access_token"]


def blizzard_getter(token, region):
    base = f"https://{region}.api.blizzard.com/data/wow/ruleset/{BLIZZARD_RULESET}/auctions"
    namespace = f"dynamic-forever-{region}"

    def get(path):
        request = urllib.request.Request(f"{base}{path}?namespace={namespace}",
                                         headers={"Authorization": f"Bearer {token}", "Accept-Encoding": "gzip"})
        return request_json(request)

    return get


def market_labels(market):
    """("Normal", "Horde") from "forever.normal.horde.us"."""
    parts = market.split(".")
    ruleset = parts[1] if len(parts) > 1 else market
    faction = parts[2] if len(parts) > 2 else ""
    if ruleset.startswith("other"):
        name = f"House {ruleset[5:]}"
    else:
        name = RULESETS.get(ruleset, ruleset.title())
    return name, "Blackwater" if faction == "neutral" else faction.title()


def read_public_prices(snapshot, wanted):
    """{item: [lowest, lowest, quantity]}. This source only has the lowest price."""
    prices = {}
    for row in snapshot.get("rows") or []:
        key, price, quantity = row[0], row[1], row[2]
        if key in wanted and price:
            prices[key] = [price, price, quantity or 0]
    return prices


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


def estimate_bought_from_days(snapshot):
    """{item: units gone over the public service's seven days}: each drop in daily quantity.

    This is only an estimate, because listings also expire or get cancelled.
    """
    bought = {}
    for key, points in snapshot.get("days") or []:
        quantities = [point[2] for point in points if point[2] is not None]
        bought[key] = sum(max(0, old - new) for old, new in zip(quantities, quantities[1:]))
    return bought


def track_bought(history, stamp, previous, prices):
    """{item: units gone over seven days}, adding each drop in quantity since the last snapshot.

    This is only an estimate, because listings also expire or get cancelled.
    """
    days = history.setdefault("bought", {})
    today = days.setdefault(str(stamp - stamp % DAY), {})
    for key, old in previous.items():
        now = prices.get(int(key))
        drop = (old[2] or 0) - (now[2] if now else 0)
        if drop > 0:
            today[key] = today.get(key, 0) + drop
    for day in sorted(days, key=int)[:-BOUGHT_DAYS]:
        del days[day]
    totals = {}
    for units in days.values():
        for key, amount in units.items():
            totals[int(key)] = totals.get(int(key), 0) + amount
    return totals


def seed_days(snapshot, tracked):
    """A new market starts with the public service's seven days of daily closes."""
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
    """{item: [lowest, market, quantity, previous market, 24 h average, 7 day average, bought estimate]}."""
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


def write_market(out, market, stamp, prices, tracked, seed=None, public_bought=None):
    """Saves a snapshot unless it's the one already saved. Returns True if it was new."""
    house_path, history_path = out / f"h{market}.json", out / f"hist{market}.json"
    old_house = load_json(house_path, {})
    if not stamp or old_house.get("ts") == stamp:
        return False
    history = load_json(history_path, None)
    if history is None:
        history = {"hours": {"t": [], "i": {}}, "days": seed or {"t": [], "i": {}}}
    previous = old_house.get("items", {})
    bought = track_bought(history, stamp, previous, prices)
    if public_bought is not None:
        bought = public_bought
    add_history(history, stamp, prices, tracked)
    house_file = build_house_file(stamp, prices, history, previous, bought)
    house_path.write_text(json.dumps(house_file, separators=(",", ":")), encoding="utf-8")
    history_path.write_text(json.dumps(history, separators=(",", ":")), encoding="utf-8")
    return True


def house_entry(market, listings, stamp, source):
    ruleset, faction = market_labels(market)
    return {"id": market, "rulesetName": ruleset, "name": faction, "listings": listings, "scannedAt": stamp, "source": source}


def collect_blizzard(out, get, wanted, tracked, region, now, snapshots=None):
    """Blizzard's houses that have listings, as meta entries. A failed house is left out."""
    entries = []
    for house_id, (ruleset, faction) in BLIZZARD_HOUSES.items():
        market = f"forever.{ruleset}.{faction}.{region}"
        try:
            body, stamp = get(f"/{house_id}")
            try:
                commodity_body, commodity_stamp = get(f"/{house_id}/commodities")
            except NotFound:
                commodity_body, commodity_stamp = {}, None
            regular = body.get("auctions") or []
            commodities = commodity_body.get("auctions") or []
            if not regular and not commodities:
                print(f"house {house_id} {market}: empty")
                continue
            stamp = max(s for s in (stamp, commodity_stamp, 0) if s is not None) or now
            prices = summarize(regular, commodities, wanted)
            if snapshots is not None:
                snapshots[market] = (house_id, prices)
            changed = write_market(out, market, stamp, prices, tracked)
            count = len(regular) + len(commodities)
            entries.append(house_entry(market, count, stamp, "blizzard"))
            print(f"house {house_id} {market}: {count} listings, {'updated' if changed else 'unchanged'}")
        except Exception as error:  # one failing house must not lose the others
            print(f"house {house_id} {market} failed: {type(error).__name__}", file=sys.stderr)
    return entries


def collect_public(out, get, wanted, tracked, skip, reports=None):
    """Markets from the public API that Blizzard didn't provide, as meta entries."""
    entries = []
    for row in get("/ah").get("markets") or []:
        market = row["market"]
        try:
            snapshot = get(f"/ah/{market}/snapshot")
            prices = read_public_prices(snapshot, wanted)
            if reports is not None:
                reports[market] = prices
            if market in skip:
                continue
            stamp = (snapshot.get("scan") or snapshot.get("at") or 0) // 1000
            changed = write_market(out, market, stamp, prices, tracked, seed_days(snapshot, tracked),
                                   estimate_bought_from_days(snapshot))
            entries.append(house_entry(market, row.get("listed") or 0, (row.get("at") or 0) // 1000, "players"))
            print(f"{market}: {row.get('listed') or 0} listed by players, {'updated' if changed else 'unchanged'}")
        except Exception as error:
            print(f"{market} failed: {type(error).__name__}", file=sys.stderr)
    return entries


def report_matches(blizzard, public):
    """Logs which Blizzard house best agrees with each player-scanned market, to check the labels."""
    for market, scanned in public.items():
        best, best_score = None, -1.0
        for house_market, (house_id, prices) in blizzard.items():
            shared = [item for item in scanned if item in prices]
            if not shared:
                continue
            close = sum(1 for item in shared if abs(scanned[item][0] - prices[item][0]) <= 0.1 * prices[item][0])
            score = close / len(shared)
            if score > best_score:
                best, best_score = (house_id, house_market), score
        if best:
            print(f"matches: {market} agrees most with house {best[0]} ({best[1]}), {best_score:.0%} of shared prices")


def collect(out, public, wanted, tracked, now, blizzard=None, region="us"):
    out.mkdir(parents=True, exist_ok=True)
    entries, snapshots, reports = [], {}, {}
    if blizzard:
        entries = collect_blizzard(out, blizzard, wanted, tracked, region, now, snapshots)
    done = {entry["id"] for entry in entries}
    try:
        entries += collect_public(out, public, wanted, tracked, done, reports)
    except Exception as error:  # Blizzard's prices are enough on their own.
        print(f"public source failed: {type(error).__name__}", file=sys.stderr)
    if snapshots:
        report_matches(snapshots, reports)
    if not entries:
        raise RuntimeError("no market could be read")
    meta = {"updated": now, "houses": entries}
    (out / "meta.json").write_text(json.dumps(meta, separators=(",", ":")), encoding="utf-8")


def load_wanted(root):
    catalog = json.loads((root / "site/catalog.json").read_text(encoding="utf-8"))
    gear = json.loads((root / "site/gear.json").read_text(encoding="utf-8"))
    tradable = json.loads((root / "site/all_items.json").read_text(encoding="utf-8"))
    tracked = {int(k) for k in catalog["items"]}
    return tracked | {int(k) for k in gear} | {int(k) for k in tradable}, tracked


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=Path("state"))
    parser.add_argument("--region", default="us")
    args = parser.parse_args()
    wanted, tracked = load_wanted(ROOT)
    blizzard = None
    client, secret = os.environ.get("BLIZZARD_CLIENT_ID"), os.environ.get("BLIZZARD_CLIENT_SECRET")
    if client and secret:
        try:
            blizzard = blizzard_getter(blizzard_token(client, secret), args.region)
        except Exception as error:  # Never log the error itself, in case it holds a credential.
            print(f"Blizzard sign-in failed: {type(error).__name__}. Using the public source.", file=sys.stderr)
    else:
        print("No Blizzard credentials are set. Using the public source.")
    collect(args.out, public_get, wanted, tracked, int(time.time()), blizzard, args.region)


if __name__ == "__main__":
    main()
