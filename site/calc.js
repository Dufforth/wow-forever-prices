// Price and profit calculations. No page code here, so they run in Node tests too.
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.Calc = factory();
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  const AUCTION_CUT = 0.05;
  const WEAPON = 2;
  const UNCOMMON = 2, RARE = 3, EPIC = 4;

  // Row fields: item levels from, to; dust, essence, shard item IDs; dust and essence
  // chance for armor; dust and essence chance for weapons; dust and essence amounts.
  const UNCOMMON_TABLE = [
    [5, 15, 10940, 10938, null, 80, 20, 20, 80, 1, 2, 1, 2],
    [16, 20, 10940, 10939, 10978, 75, 20, 20, 75, 2, 3, 1, 2],
    [21, 25, 10940, 10998, 10978, 75, 15, 15, 75, 4, 6, 1, 2],
    [26, 30, 11083, 11082, 11084, 75, 20, 20, 75, 1, 2, 1, 2],
    [31, 35, 11083, 11134, 11138, 75, 20, 20, 75, 2, 5, 1, 2],
    [36, 40, 11137, 11135, 11139, 75, 20, 20, 75, 1, 2, 1, 2],
    [41, 45, 11137, 11174, 11177, 75, 20, 20, 75, 2, 5, 1, 2],
    [46, 50, 11176, 11175, 11178, 75, 20, 20, 75, 1, 2, 1, 2],
    [51, 55, 11176, 16202, 14343, 75, 20, 22, 75, 2, 5, 1, 2],
    [56, 60, 16204, 16203, 14344, 75, 20, 22, 75, 1, 2, 1, 2],
    [61, 65, 16204, 16203, 14344, 75, 20, 22, 75, 2, 5, 2, 3],
  ];
  const RARE_TABLE = [
    [1, 25, 10978], [26, 30, 11084], [31, 35, 11138], [36, 40, 11139], [41, 45, 11177],
    [46, 50, 11178], [51, 55, 14343], [56, 80, 14344, 20725],
  ];
  const EPIC_TABLE = [
    [40, 45, 11177, 2, 4], [46, 50, 11178, 2, 4], [51, 55, 14343, 2, 4], [56, 60, 20725, 1, 1], [61, 88, 20725, 1, 2],
  ];

  function findBand(rows, level) {
    return rows.find((row) => level >= row[0] && level <= row[1]);
  }

  // What disenchanting an item is expected to give: [{ id, chance (0-1), min, max }], or null.
  function disenchantOutcomes(item) {
    if (!item || !(item.cl === WEAPON || item.cl === 4)) return null;
    if (item.inv === 4 || item.inv === 19) return null;
    const level = item.il;
    if (item.q === UNCOMMON) {
      const row = findBand(UNCOMMON_TABLE, level);
      if (!row) return null;
      const weapon = item.cl === WEAPON;
      const dust = (weapon ? row[7] : row[5]) / 100;
      const essence = (weapon ? row[8] : row[6]) / 100;
      const out = [
        { id: row[2], chance: dust, min: row[9], max: row[10] },
        { id: row[3], chance: essence, min: row[11], max: row[12] },
      ];
      if (row[4]) out.push({ id: row[4], chance: Math.max(0, 1 - dust - essence), min: 1, max: 1 });
      return out;
    }
    if (item.q === RARE) {
      const row = findBand(RARE_TABLE, level);
      if (!row) return null;
      if (row[3]) return [{ id: row[2], chance: 0.995, min: 1, max: 1 }, { id: row[3], chance: 0.005, min: 1, max: 1 }];
      return [{ id: row[2], chance: 1, min: 1, max: 1 }];
    }
    if (item.q === EPIC) {
      const row = findBand(EPIC_TABLE, level);
      return row ? [{ id: row[2], chance: 1, min: row[3], max: row[4] }] : null;
    }
    return null;
  }

  function afterCut(copper) {
    return copper * (1 - AUCTION_CUT);
  }

  // Rows in a house file: [lowest, market, quantity, previous, 24 h average, 7 day average].
  function listedMarket(prices, id) {
    const row = prices[id];
    return row && row[2] > 0 ? row[1] : null;
  }

  // Value of disenchanting one item once its materials sell, after the auction cut.
  function disenchantValue(item, prices) {
    const outcomes = disenchantOutcomes(item);
    if (!outcomes) return null;
    let total = 0;
    for (const result of outcomes) {
      if (result.chance <= 0) continue;
      const market = listedMarket(prices, result.id);
      if (market == null) return null;
      total += result.chance * ((result.min + result.max) / 2) * afterCut(market);
    }
    return total;
  }

  function indexRecipes(recipes) {
    const byItem = new Map();
    for (const recipe of recipes) {
      if (!byItem.has(recipe.i)) byItem.set(recipe.i, []);
      byItem.get(recipe.i).push(recipe);
    }
    return byItem;
  }

  // The cheapest way to get one of an item: buy, vendor or craft it.
  function makeCoster(catalog, prices, byItem) {
    const memo = new Map();

    function recipeCost(recipe, visiting) {
      let total = 0;
      const parts = [];
      for (const [id, count] of recipe.r) {
        const part = bestCost(id, visiting);
        parts.push({ id, count, cost: part.cost, source: part.source });
        if (part.cost == null) total = null;
        else if (total != null) total += part.cost * count;
      }
      return { total, parts };
    }

    function bestCost(id, visiting) {
      if (memo.has(id)) return memo.get(id);
      const item = catalog.items[id];
      let best = { cost: null, source: "none" };
      const market = listedMarket(prices, id);
      if (market != null) best = { cost: market, source: "auction" };
      if (item && item.v && item.buy > 0 && (best.cost == null || item.buy < best.cost)) {
        best = { cost: item.buy, source: "vendor" };
      }
      const seen = visiting || new Set();
      if (!seen.has(id)) {
        seen.add(id);
        for (const recipe of byItem.get(id) || []) {
          const made = recipeCost(recipe, seen);
          if (made.total != null) {
            const each = made.total / recipe.c;
            if (best.cost == null || each < best.cost) best = { cost: each, source: "craft" };
          }
        }
        seen.delete(id);
      }
      // A result found while another item is in progress may be cut short by that loop.
      if (!visiting || visiting.size === 0) memo.set(id, best);
      return best;
    }

    return { bestCost: (id) => bestCost(id), recipeCost: (recipe) => recipeCost(recipe, new Set([recipe.i])) };
  }

  function craftRow(recipe, catalog, prices, coster) {
    const item = catalog.items[recipe.i];
    const made = coster.recipeCost(recipe);
    const market = item.bop ? null : listedMarket(prices, recipe.i);
    const options = [];
    if (market != null) options.push({ kind: "Sell on auction", each: afterCut(market) });
    const de = disenchantValue(item, prices);
    if (de != null) options.push({ kind: "Disenchant", each: de });
    if (item.sell > 0) options.push({ kind: "Sell to vendor", each: item.sell });
    options.sort((a, b) => b.each - a.each);
    const best = options[0] || null;
    const cost = made.total;
    const profit = cost != null && best ? best.each * recipe.c - cost : null;
    const row = prices[recipe.i];
    return {
      recipe, item, cost, parts: made.parts, options, best, profit,
      ah: market != null ? afterCut(market) : null, de, vendor: item.sell || null,
      margin: profit != null && cost > 0 ? profit / cost : null,
      supply: row ? row[2] : 0,
      missing: made.parts.filter((p) => p.cost == null).map((p) => p.id),
    };
  }

  function craftRows(catalog, prices) {
    const byItem = indexRecipes(catalog.recipes);
    const coster = makeCoster(catalog, prices, byItem);
    return catalog.recipes.filter((r) => catalog.items[r.i]).map((r) => craftRow(r, catalog, prices, coster));
  }

  // The Enchanting skill needed to disenchant an item, by the Classic rule.
  function disenchantSkill(item) {
    if (!disenchantOutcomes(item)) return null;
    const level = item.il;
    if (item.q >= RARE && level <= 25) return 25;
    if (level <= 20) return 1;
    return Math.max(25, (Math.ceil(level / 5) - 4) * 25);
  }

  // The material most likely to come out, for a quick label.
  function likelyMaterial(item) {
    const outcomes = disenchantOutcomes(item);
    if (!outcomes) return null;
    return outcomes.slice().sort((a, b) => b.chance - a.chance)[0].id;
  }

  // Gear for sale below what its materials are worth.
  function disenchantDeals(gear, prices) {
    const rows = [];
    for (const id of Object.keys(gear)) {
      const row = prices[id];
      if (!row || !(row[2] > 0) || row[0] == null) continue;
      const value = disenchantValue(gear[id], prices);
      if (value == null) continue;
      const profit = value - row[0];
      rows.push({
        id: Number(id), item: gear[id], price: row[0], value, profit, supply: row[2],
        roi: row[0] > 0 ? profit / row[0] : null, skill: disenchantSkill(gear[id]), material: likelyMaterial(gear[id]),
      });
    }
    return rows.sort((a, b) => b.profit - a.profit);
  }

  // Crafts whose disenchanted materials are worth more than the reagents.
  function craftDisenchantRows(rows) {
    return rows
      .filter((r) => r.de != null && r.cost != null)
      .map((r) => {
        const value = r.de * r.recipe.c;
        const profit = value - r.cost;
        return {
          id: r.recipe.i, item: r.item, recipe: r.recipe, price: r.cost, value, profit, supply: r.supply,
          roi: r.cost > 0 ? profit / r.cost : null, skill: disenchantSkill(r.item), material: likelyMaterial(r.item),
        };
      })
      .sort((a, b) => b.profit - a.profit);
  }

  // Plain-language ratings, so nobody has to read percentages to spot a good opportunity.
  const GOOD_RETURN = 0.2; // profit of at least 20% of what you spend
  const USUAL_BAND = 0.15; // within 15% of the 7-day average counts as a usual price

  // Crafting: "good" pays back at least 20% more than it costs, "fair" makes a little, "poor" loses money.
  function rateReturn(profit, cost) {
    if (profit == null) return null;
    if (profit <= 0) return "poor";
    return cost > 0 && profit / cost >= GOOD_RETURN ? "good" : "fair";
  }

  // Today's typical price against its 7-day average.
  function ratePriceNow(row) {
    if (!row || !(row[2] > 0) || !(row[5] > 0) || row[1] == null) return null;
    const ratio = row[1] / row[5];
    if (ratio <= 1 - USUAL_BAND) return "cheap";
    if (ratio >= 1 + USUAL_BAND) return "pricey";
    return "usual";
  }

  const BASIS_COLUMN = { previous: 3, day: 4, week: 5 };

  function priceChange(row, basis) {
    const old = row[BASIS_COLUMN[basis || "previous"]];
    if (old == null || old <= 0 || row[1] == null) return null;
    return { old, amount: row[1] - old, percent: ((row[1] - old) / old) * 100 };
  }

  // Items whose price moved enough to matter, biggest moves first.
  function significantChanges(prices, options) {
    const out = [];
    for (const id of Object.keys(prices)) {
      const row = prices[id];
      if (!(row[2] >= options.minSupply)) continue;
      const change = priceChange(row, options.basis);
      if (!change || row[1] === change.old) continue;
      if (Math.abs(change.percent) < options.percent || Math.abs(change.amount) < options.minAmount) continue;
      out.push({ id: Number(id), market: row[1], supply: row[2], ...change });
    }
    return out.sort((a, b) => Math.abs(b.percent) - Math.abs(a.percent));
  }

  function money(copper) {
    if (copper == null || !isFinite(copper)) return "–";
    const sign = copper < 0 ? "-" : "";
    const value = Math.round(Math.abs(copper));
    const gold = Math.floor(value / 10000), silver = Math.floor((value % 10000) / 100), rest = value % 100;
    if (gold > 0) return `${sign}${gold.toLocaleString("en-US")}g ${silver}s` + (gold < 100 && rest ? ` ${rest}c` : "");
    if (silver > 0) return `${sign}${silver}s ${rest}c`;
    return `${sign}${rest}c`;
  }

  return {
    AUCTION_CUT, GOOD_RETURN, USUAL_BAND, rateReturn, ratePriceNow, afterCut, craftDisenchantRows, craftRows, disenchantDeals, disenchantOutcomes, disenchantSkill, disenchantValue, likelyMaterial,
    indexRecipes, money, priceChange, significantChanges,
  };
});
