"""Easy money ideas from the auction house data (user, 2026-11-25: "based on all knowledge we have from the AH is
there any way to make easy money"). The math runs here with pandas; only the top rows print.

    python tools/money_finder.py <prices json> [--top N]

<prices json>: one realm/faction file from the `data` branch, e.g. `git show origin/data:hforever.pvp.horde.us.json`.
A price row is [lowest, market, listed, -, day avg, 7-day avg, sold in 7 days] in copper. Reads site/catalog.json
(items, vendor prices, recipes) and site/farm.json (what monsters drop). Four ideas:
  1. Vendor flips: listings cheaper than what a vendor pays for the item.
  2. Underpriced listings: the cheapest well under the 7-day average, on items that sell every day.
  3. Crafts that sell for more than their materials (trainer and vendor recipes only), on items that sell.
  4. Farming: open-world monsters whose drops are worth the most per kill at today's prices.
"""
import argparse
import json
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
AH_CUT = 0.95          # the auction house keeps 5%
KILL_SECONDS = 30      # measured from the user's solo fights (route planner)
MIN_SOLD = 20          # sold in 7 days: below this, "sells" isn't a promise
# Vendor flips must pay for the time: buying, carrying (a bag slot each for gear) and selling. User, 2026-11-27: rows
# like "buy at 5s, a vendor pays 5s" made copper per item. No AH cut or deposit applies: you buy, a vendor buys back.
MIN_FLIP_EACH = 100    # at least 1s profit per item
MIN_FLIP_MARGIN = 0.10  # and at least 10% of what you pay


def gold(c):
    return f"{c / 10000:.2f}g" if c >= 10000 else f"{c / 100:.0f}s"


def load(prices_path):
    prices = json.loads(Path(prices_path).read_text(encoding="utf-8"))["items"]
    cat = json.loads((ROOT / "site" / "catalog.json").read_text(encoding="utf-8"))
    farm = json.loads((ROOT / "site" / "farm.json").read_text(encoding="utf-8"))
    rows = []
    for iid, item in cat["items"].items():
        p = prices.get(iid)
        lowest = (p[0] if p[0] is not None else p[1]) if p else None
        rows.append({"id": int(iid), "name": item["n"], "vendor_pays": item.get("sell") or 0, "vendor_sells": item.get("buy") if item.get("v") else None,  # only reagents vendors are known to sell
                     "lowest": lowest, "market": p[1] if p else None, "listed": p[2] if p else 0,
                     "week": p[5] if p else None, "sold7": p[6] if p else 0, "bop": item.get("bop", 0)})
    return pd.DataFrame(rows).set_index("id"), cat, farm


def vendor_flips(items):
    f = items[(items["listed"] > 0) & items["lowest"].notna() & (items["lowest"] < items["vendor_pays"])].copy()
    f["profit_each"] = f["vendor_pays"] - f["lowest"]
    f = f[(f["profit_each"] >= MIN_FLIP_EACH) & (f["profit_each"] >= MIN_FLIP_MARGIN * f["lowest"])].copy()
    f["profit_all"] = f["profit_each"] * f["listed"]  # an upper bound: only the cheapest listing is known
    return f.sort_values("profit_all", ascending=False)


def underpriced(items):
    f = items[(items["listed"] > 0) & items["week"].notna() & (items["sold7"] >= MIN_SOLD)].copy()
    f["sell_at"] = f["week"] * AH_CUT
    f = f[f["lowest"] < 0.6 * f["week"]]
    f["profit_each"] = f["sell_at"] - f["lowest"]
    return f[f["profit_each"] > 0].sort_values("profit_each", ascending=False)


def unit_cost(items, iid):
    """Cheapest way to get one: vendor price when a vendor sells it, else the AH market price."""
    if iid not in items.index:
        return None
    r = items.loc[iid]
    options = [v for v in (r["vendor_sells"], r["market"]) if v and v == v]
    return min(options) if options else None


def crafts(items, recipes):
    out = []
    for rec in recipes:
        if not set(rec.get("o", [])) & {"trainer", "vendor"} or rec["i"] not in items.index:
            continue
        made = items.loc[rec["i"]]
        if made["bop"] or not made["market"] or made["sold7"] < MIN_SOLD:
            continue
        costs = [unit_cost(items, rid) for rid, _ in rec["r"]]
        if any(c is None for c in costs):
            continue
        cost = sum(c * n for c, (_, n) in zip(costs, rec["r"])) / max(1, rec.get("c", 1))
        sell = made["market"] * AH_CUT
        out.append({"id": rec["i"], "recipe": rec["n"], "profession": rec["p"], "skill": rec.get("sk", 0), "cost": cost, "sell": sell,
                    "profit": sell - cost, "sold7": made["sold7"], "listed": made["listed"]})
    df = pd.DataFrame(out)
    return df[df["profit"] > 0].sort_values(["profit"], ascending=False) if len(df) else df


def farming(items, farm):
    cols = farm["columns"]["creature"]
    creatures = {i: dict(zip(cols, c)) for i, c in enumerate(farm["creatures"])}
    value = {}
    for iid, drop in farm["items"].items():
        iid = int(iid)
        if iid not in items.index:
            continue
        r = items.loc[iid]
        price = r["market"] * AH_CUT if r["market"] and r["sold7"] >= 5 and not r["bop"] else r["vendor_pays"]
        if not price:
            continue
        for creature, _, per_kill in drop["d"]:
            value.setdefault(creature, []).append((per_kill * price, r["name"]))
    out = []
    for c, drops in value.items():
        cr = creatures.get(c)
        if not cr or cr.get("dungeon") or cr.get("rank") not in ("normal", None, ""):
            continue
        total = sum(v for v, _ in drops)
        best = max(drops)[1]
        out.append({"monster": cr["name"], "level": f"{cr['minLevel']}-{cr['maxLevel']}", "zone": cr["zone"],
                    "per_kill": total, "per_hour": total * 3600 / KILL_SECONDS, "best_drop": best, "spawns": cr.get("spawns", 0)})
    df = pd.DataFrame(out)
    return df[df["spawns"] >= 5].sort_values("per_hour", ascending=False) if len(df) else df


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("prices")
    parser.add_argument("--top", type=int, default=10)
    args = parser.parse_args()
    items, cat, farm = load(args.prices)
    n = args.top
    v = vendor_flips(items)
    print(f"1. VENDOR FLIPS ({len(v)} items): buy on the AH, sell to any vendor")
    for iid, r in v.head(n).iterrows():
        print(f"   {r['name']}: buy {gold(r['lowest'])}, vendor pays {gold(r['vendor_pays'])} -> {gold(r['profit_each'])} each, "
              f"{int(r['listed'])} listed = {gold(r['profit_all'])}")
    u = underpriced(items)
    print(f"\n2. UNDERPRICED LISTINGS ({len(u)} items): cheapest under 60% of the 7-day average, sells {MIN_SOLD}+ a week")
    for iid, r in u.head(n).iterrows():
        print(f"   {r['name']}: buy {gold(r['lowest'])}, usually {gold(r['week'])} ({int(r['sold7'])} sold in 7 days) -> "
              f"about {gold(r['profit_each'])} each after the AH cut")
    c = crafts(items, cat["recipes"])
    print(f"\n3. CRAFTS THAT PAY ({len(c)} recipes, trainer or vendor recipes, sells {MIN_SOLD}+ a week)")
    for _, r in c.head(n).iterrows():
        print(f"   {r['recipe']} ({r['profession']} {r['skill']}): materials {gold(r['cost'])}, sells {gold(r['sell'])} -> "
              f"{gold(r['profit'])} each; {int(r['sold7'])} sold in 7 days, {int(r['listed'])} listed")
    f = farming(items, farm)
    print(f"\n4. FARMING (open world, normal monsters, {KILL_SECONDS} s a kill, today's prices)")
    for _, r in f.head(n).iterrows():
        print(f"   {r['monster']} (level {r['level']}, {r['zone']}): {gold(r['per_kill'])} a kill, about {gold(r['per_hour'])} "
              f"an hour; best drop {r['best_drop']}")


if __name__ == "__main__":
    main()
