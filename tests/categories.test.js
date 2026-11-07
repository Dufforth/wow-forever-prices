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

test("type labels", () => {
  assert.equal(Categories.typeLabel({ cl: 0, sc: 1 }), "Potions");
  assert.equal(Categories.typeLabel({ cl: 12, sc: 0 }), "Other");
  assert.equal(Categories.typeLabel({ cl: 7, sc: 9, g: "herb" }), "Herbs");
  assert.equal(Categories.typeLabel({ cl: 7, sc: 8 }), "Cooking ingredients");
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

test("my scan list category", () => {
  const ctx = { ...context(), scanList: new Set([5]) };
  assert.ok(Categories.matches("scan-list", "5", { cl: 12 }, ctx));
  assert.ok(!Categories.matches("scan-list", 6, { cl: 12 }, ctx));
  assert.ok(Categories.isKnown("scan-list", []));
  assert.equal(Categories.label("scan-list"), "My scan list");
});

test("sources: crafted first, then gathered, vendor, and everything else", () => {
  const ctx = context([], { 1: ["Tailoring"] });
  assert.equal(Categories.sourceOf(1, { cl: 4 }, ctx), "crafted");
  assert.equal(Categories.sourceOf("2", { cl: 7, g: "herb" }, ctx), "gathered");
  assert.equal(Categories.sourceOf(3, { cl: 7, v: 1 }, ctx), "vendor");
  assert.equal(Categories.sourceOf(4, { cl: 4 }, ctx), "other");
  assert.equal(Categories.sourceLabel("other"), "Drop or other");
  assert.equal(Categories.sourceLabel("all"), "All sources");
});

test("market categories", () => {
  const item = { cl: 7, sc: 9 };
  const ctx = { ...context(), mostPosted: new Set([5]), mostBought: new Set([6]) };
  assert.ok(Categories.matches("most-posted", "5", item, ctx));
  assert.ok(!Categories.matches("most-posted", 6, item, ctx));
  assert.ok(Categories.matches("most-bought", 6, item, ctx));
  assert.ok(!Categories.matches("most-bought", 6, item, context()));
  assert.ok(Categories.isKnown("most-bought", []));
  assert.equal(Categories.label("most-posted"), "Most posted");
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
