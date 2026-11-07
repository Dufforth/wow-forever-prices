const test = require("node:test");
const assert = require("node:assert");
const Calc = require("../site/calc.js");

const ORE = 2770, BAR = 2840, THREAD = 2320, HELM = 5000, DUST = 10940, ESS = 10938, BLUE = 6000, SHARD = 10978;
const catalog = {
  items: {
    [ORE]: { n: "Ore", q: 1, sell: 5 },
    [BAR]: { n: "Bar", q: 1, sell: 10 },
    [THREAD]: { n: "Thread", q: 1, buy: 10, v: 1, sell: 1 },
    [HELM]: { n: "Helm", q: 2, il: 10, cl: 4, inv: 1, sell: 50 },
    [BLUE]: { n: "Sword", q: 3, il: 20, cl: 2, inv: 13, sell: 100, bop: 1 },
    [DUST]: { n: "Dust", q: 1 }, [ESS]: { n: "Essence", q: 1 }, [SHARD]: { n: "Shard", q: 3 },
  },
  recipes: [
    { s: 1, n: "Smelt", p: "Mining", sk: 1, i: BAR, c: 1, r: [[ORE, 2]] },
    { s: 2, n: "Helm", p: "Blacksmithing", sk: 1, i: HELM, c: 1, r: [[BAR, 2], [THREAD, 1]] },
    { s: 3, n: "Sword", p: "Blacksmithing", sk: 1, i: BLUE, c: 1, r: [[BAR, 1]] },
  ],
};
const row = (market, supply = 10) => [market, market, supply, null, null, null];
const find = (rows, spell) => rows.find((r) => r.recipe.s === spell);

test("money formats gold, silver and copper", () => {
  assert.equal(Calc.money(5), "5c");
  assert.equal(Calc.money(12345), "1g 23s 45c");
  assert.equal(Calc.money(-250), "-2s 50c");
  assert.equal(Calc.money(1234567), "123g 45s");
  assert.equal(Calc.money(null), "–");
});

test("reagents use the cheapest of auction, vendor and crafting", () => {
  const prices = { [ORE]: row(100), [BAR]: row(500), [THREAD]: row(50), [HELM]: row(3000) };
  const r = find(Calc.craftRows(catalog, prices), 2);
  assert.equal(r.parts[0].source, "craft");
  assert.equal(r.parts[0].cost, 200);
  assert.equal(r.parts[1].source, "vendor");
  assert.equal(r.parts[1].cost, 10);
  assert.equal(r.cost, 410);
});

test("buying wins when it is cheaper than crafting", () => {
  const prices = { [ORE]: row(100), [BAR]: row(150) };
  const r = find(Calc.craftRows(catalog, prices), 2);
  assert.equal(r.parts[0].source, "auction");
  assert.equal(r.parts[0].cost, 150);
});

test("profit takes the auction cut and picks the best way to sell", () => {
  const prices = { [ORE]: row(10), [HELM]: row(1000), [DUST]: row(1), [ESS]: row(1) };
  const r = find(Calc.craftRows(catalog, prices), 2);
  assert.equal(r.ah, 950);
  assert.equal(r.best.kind, "Sell on auction");
  assert.equal(r.profit, 950 - r.cost);
});

test("disenchanting wins when the materials are worth more", () => {
  const prices = { [ORE]: row(10), [HELM]: row(100), [DUST]: row(1000), [ESS]: row(1000) };
  const r = find(Calc.craftRows(catalog, prices), 2);
  assert.equal(r.best.kind, "Disenchant");
  // Item level 10 armor: 80% 1-2 dust, 20% 1-2 essence, after the 5% cut.
  assert.ok(Math.abs(r.de - (0.8 * 1.5 * 950 + 0.2 * 1.5 * 950)) < 1e-6);
});

test("vendor wins when nothing else pays", () => {
  const prices = { [ORE]: row(1), [HELM]: row(10) };
  assert.equal(find(Calc.craftRows(catalog, prices), 2).best.kind, "Sell to vendor");
});

test("a missing reagent price means no cost or profit", () => {
  const r = find(Calc.craftRows(catalog, { [HELM]: row(1000) }), 2);
  assert.equal(r.cost, null);
  assert.equal(r.profit, null);
  assert.deepEqual(r.missing, [BAR]);
});

test("reagents with nothing for sale do not count as available", () => {
  const prices = { [ORE]: [null, 100, 0, null, null, null] };
  assert.equal(find(Calc.craftRows(catalog, prices), 1).cost, null);
});

test("bind on pickup items cannot be sold on the auction", () => {
  const prices = { [ORE]: row(1), [BLUE]: row(99999), [SHARD]: row(5000) };
  const r = find(Calc.craftRows(catalog, prices), 3);
  assert.equal(r.ah, null);
  assert.equal(r.best.kind, "Disenchant");
});

test("recipe yield divides the craft cost and multiplies the income", () => {
  const multi = { items: { ...catalog.items }, recipes: [{ s: 9, n: "x", p: "A", sk: 1, i: BAR, c: 4, r: [[ORE, 1]] }] };
  const r = find(Calc.craftRows(multi, { [ORE]: row(100), [BAR]: row(100) }), 9);
  assert.equal(r.profit, 95 * 4 - 100);
});

test("recipes that make each other do not loop forever", () => {
  const loop = {
    items: { 1: { n: "A", q: 1 }, 2: { n: "B", q: 1 } },
    recipes: [{ s: 1, n: "a", p: "X", sk: 1, i: 1, c: 1, r: [[2, 1]] }, { s: 2, n: "b", p: "X", sk: 1, i: 2, c: 1, r: [[1, 1]] }],
  };
  assert.equal(find(Calc.craftRows(loop, {}), 1).cost, null);
  const priced = Calc.craftRows(loop, { 2: row(100) });
  assert.equal(find(priced, 1).cost, 100);
  assert.equal(find(priced, 2).cost, 100);
});

test("disenchant tables by quality and type", () => {
  const armor = Calc.disenchantOutcomes({ q: 2, il: 30, cl: 4, inv: 1 });
  assert.equal(armor[0].id, 11083);
  assert.equal(armor[0].chance, 0.75);
  const weapon = Calc.disenchantOutcomes({ q: 2, il: 30, cl: 2, inv: 13 });
  assert.equal(weapon[0].chance, 0.2);
  assert.equal(weapon[1].chance, 0.75);
  assert.equal(Calc.disenchantOutcomes({ q: 3, il: 28, cl: 4, inv: 1 })[0].id, 11084);
  const epic = Calc.disenchantOutcomes({ q: 4, il: 60, cl: 4, inv: 1 });
  assert.deepEqual(epic[0], { id: 20725, chance: 1, min: 1, max: 1 });
  assert.equal(Calc.disenchantOutcomes({ q: 1, il: 30, cl: 4, inv: 1 }), null);
  assert.equal(Calc.disenchantOutcomes({ q: 2, il: 30, cl: 4, inv: 4 }), null);
  assert.equal(Calc.disenchantOutcomes({ q: 2, il: 30, cl: 7 }), null);
});

test("enchanting skill needed to disenchant, by the Classic rule", () => {
  assert.equal(Calc.disenchantSkill({ q: 2, il: 15, cl: 4, inv: 1 }), 1);
  assert.equal(Calc.disenchantSkill({ q: 2, il: 21, cl: 4, inv: 1 }), 25);
  assert.equal(Calc.disenchantSkill({ q: 2, il: 30, cl: 4, inv: 1 }), 50);
  assert.equal(Calc.disenchantSkill({ q: 2, il: 45, cl: 4, inv: 1 }), 125);
  assert.equal(Calc.disenchantSkill({ q: 3, il: 20, cl: 2, inv: 13 }), 25);
  assert.equal(Calc.disenchantSkill({ q: 4, il: 60, cl: 4, inv: 1 }), 200);
  assert.equal(Calc.disenchantSkill({ q: 1, il: 30, cl: 4, inv: 1 }), null);
});

test("most likely material: dust for armor, essence for weapons", () => {
  assert.equal(Calc.likelyMaterial({ q: 2, il: 10, cl: 4, inv: 1 }), 10940);
  assert.equal(Calc.likelyMaterial({ q: 2, il: 10, cl: 2, inv: 13 }), 10938);
  assert.equal(Calc.likelyMaterial({ q: 1, il: 10, cl: 2, inv: 13 }), null);
});

test("crafting to disenchant: whole-craft value against cost", () => {
  const prices = { [ORE]: row(10), [HELM]: row(100), [DUST]: row(1000), [ESS]: row(1000) };
  const de = Calc.craftDisenchantRows(Calc.craftRows(catalog, prices));
  const helm = de.find((r) => r.recipe.s === 2);
  assert.equal(helm.price, helm.recipe ? Calc.craftRows(catalog, prices).find((r) => r.recipe.s === 2).cost : null);
  assert.ok(helm.profit > 0);
  assert.equal(helm.skill, 1);
  assert.ok(Math.abs(helm.roi - helm.profit / helm.price) < 1e-9);
  assert.ok(!de.some((r) => r.recipe.s === 1), "bars can't be disenchanted");
});

test("deals list gear priced under its materials, best first", () => {
  const gear = { 1: { n: "A", q: 3, il: 20, cl: 4 }, 2: { n: "B", q: 3, il: 20, cl: 4 }, 3: { n: "C", q: 3, il: 20, cl: 4 } };
  const prices = { 1: row(100), 2: row(800), [SHARD]: row(1000) };
  const deals = Calc.disenchantDeals(gear, prices);
  assert.deepEqual(deals.map((d) => d.id), [1, 2]);
  assert.equal(deals[0].profit, 850);
  assert.equal(deals[1].profit, 150);
  assert.equal(deals[0].roi, 8.5);
  assert.equal(deals[0].skill, 25);
  assert.equal(deals[0].material, SHARD);
});

test("significant changes respect every limit and sort by size", () => {
  const prices = {
    1: [0, 200, 10, 100, 150, 120],   // +100%
    2: [0, 90, 10, 100, 100, 100],    // -10%: too small a percent
    3: [0, 110, 10, 10, 100, 100],    // +1000%, but only 100 copper... still kept at minAmount 50
    4: [0, 500, 1, 100, 100, 100],    // too few for sale
    5: [0, 100, 10, null, 100, 100],  // nothing to compare with
    6: [0, 100, 10, 100, 100, 100],   // no change
    7: [0, 40, 10, 100, 100, 100],    // -60%
  };
  const out = Calc.significantChanges(prices, { percent: 15, minAmount: 50, minSupply: 5, basis: "previous" });
  assert.deepEqual(out.map((c) => c.id), [3, 1, 7]);
  assert.equal(out[1].amount, 100);
  assert.equal(out[1].percent, 100);
  assert.equal(out[2].amount, -60);
  const week = Calc.significantChanges(prices, { percent: 15, minAmount: 0, minSupply: 5, basis: "week" });
  assert.ok(week.some((c) => c.id === 1 && c.old === 120));
  const big = Calc.significantChanges(prices, { percent: 15, minAmount: 95, minSupply: 5, basis: "previous" });
  assert.deepEqual(big.map((c) => c.id), [3, 1]);
});
