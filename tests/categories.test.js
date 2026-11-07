const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const Categories = require("../site/categories.js");

const context = (favorites = [], crafted = {}) => ({
  favorites: new Set(favorites),
  craftedBy: new Map(Object.entries(crafted).map(([id, list]) => [Number(id), list])),
});
const catalog = JSON.parse(fs.readFileSync(path.join(__dirname, "../site/catalog.json"), "utf8"));
const gear = JSON.parse(fs.readFileSync(path.join(__dirname, "../site/gear.json"), "utf8"));
const typeIds = () => Categories.groups([]).find((g) => g.label === "Item type").categories.map((c) => c.id);

test("types split items by class and subclass", () => {
  assert.equal(Categories.typeOf({ cl: 0, sc: 1 }), "potion");
  assert.equal(Categories.typeOf({ cl: 0, sc: 3 }), "elixir");
  assert.equal(Categories.typeOf({ cl: 0, sc: 8 }), "consumable");
  assert.equal(Categories.typeOf({ cl: 2, sc: 7 }), "weapon");
  assert.equal(Categories.typeOf({ cl: 4, sc: 4 }), "armor-plate");
  assert.equal(Categories.typeOf({ cl: 4, sc: 6 }), "armor-other");
  assert.equal(Categories.typeOf({ cl: 7, sc: 1 }), "parts");
  assert.equal(Categories.typeOf({ cl: 12, sc: 0 }), "other");
});

test("every real item lands in exactly one item type", () => {
  const ids = typeIds();
  for (const item of [...Object.values(catalog.items), ...Object.values(gear)]) {
    const hits = ids.filter((id) => Categories.matches(id, 1, item, context()));
    assert.equal(hits.length, 1, item.n);
  }
});

test("all, favorites and professions", () => {
  const item = { cl: 7, sc: 9, g: "herb" };
  assert.ok(Categories.matches("all", 5, item, context()));
  assert.ok(Categories.matches("favorites", "5", item, context([5])));
  assert.ok(!Categories.matches("favorites", 6, item, context([5])));
  assert.ok(Categories.matches("prof:Alchemy", "5", item, context([], { 5: ["Alchemy"] })));
  assert.ok(!Categories.matches("prof:Mining", 5, item, context([], { 5: ["Alchemy"] })));
  assert.ok(Categories.matches("herb", 5, item, context()));
  assert.ok(!Categories.matches("ore", 5, item, context()));
});

test("unknown categories from a link are rejected", () => {
  assert.ok(Categories.isKnown("herb", []));
  assert.ok(Categories.isKnown("favorites", []));
  assert.ok(Categories.isKnown("prof:Alchemy", ["Alchemy"]));
  assert.ok(!Categories.isKnown("prof:Nonsense", ["Alchemy"]));
  assert.ok(!Categories.isKnown("nonsense", []));
});

test("labels read well", () => {
  assert.equal(Categories.label("all"), "All items");
  assert.equal(Categories.label("herb"), "Herbs");
  assert.equal(Categories.label("prof:Tailoring"), "Crafted by Tailoring");
});

test("icon addresses", () => {
  assert.equal(Categories.iconUrl("inv_ore_copper_01"), "https://render.worldofwarcraft.com/us/icons/56/inv_ore_copper_01.jpg");
  assert.equal(Categories.iconBackupUrl("inv_ore_copper_01"), "https://wow.zamimg.com/images/wow/icons/medium/inv_ore_copper_01.jpg");
  assert.equal(Categories.iconUrl(undefined), null);
});

test("nearly every real item has an icon", () => {
  const items = [...Object.values(catalog.items), ...Object.values(gear)];
  const missing = items.filter((item) => !item.ic);
  assert.ok(missing.length / items.length < 0.02, `${missing.length} of ${items.length} have no icon`);
  for (const item of items) if (item.ic) assert.match(item.ic, /^[a-z0-9_\-.]+$/);
});
