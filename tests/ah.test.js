const test = require("node:test");
const assert = require("node:assert");
const AH = require("../site/ah.js");

const sword = { cl: 2, sc: 7, q: 2, rl: 20, inv: 13 };
const robe = { cl: 4, sc: 1, q: 3, rl: 30, inv: 20 };
const helm = { cl: 4, sc: 4, q: 2, rl: 40, inv: 1 };
const herb = { cl: 7, sc: 9, q: 1, rl: 0, inv: 0 };

test("categories match the game's classes and subclasses", () => {
  assert.ok(AH.matches("ah:2", sword));
  assert.ok(AH.matches("ah:2:7", sword));
  assert.ok(!AH.matches("ah:2:8", sword));
  assert.ok(!AH.matches("ah:4", sword));
  assert.ok(AH.matches("all", herb));
  assert.ok(AH.isAuctionCategory("ah:4:1"));
  assert.ok(!AH.isAuctionCategory("ah:4:5"), "no such armor subclass");
  assert.ok(!AH.isAuctionCategory("herb"));
});

test("level, rarity and slot filters", () => {
  const any = { minLevel: "", maxLevel: "", quality: "", slot: "" };
  assert.ok(AH.passes(sword, any));
  assert.ok(!AH.passes(sword, { ...any, minLevel: 25 }));
  assert.ok(AH.passes(sword, { ...any, minLevel: 10, maxLevel: 20 }));
  assert.ok(!AH.passes(sword, { ...any, quality: 3 }));
  assert.ok(AH.passes(robe, { ...any, slot: 5 }), "robes count as chest");
  assert.ok(!AH.passes(helm, { ...any, slot: 5 }));
});

test("counts and sidebar groups follow the game's order and skip empty ones", () => {
  const counts = AH.counts([sword, robe, helm, herb]);
  assert.equal(counts.get("all"), 4);
  assert.equal(counts.get("ah:4"), 2);
  const groups = AH.groups(counts);
  assert.deepEqual(groups.map((g) => g.label), ["Weapons", "Armor", "Trade Goods"]);
  assert.deepEqual(groups[1].categories.map((c) => c.label), ["All armor", "Cloth", "Plate"]);
  assert.equal(AH.label("ah:4:1"), "Cloth (Armor)");
  assert.ok(AH.showsSlots("ah:4:2") && !AH.showsSlots("ah:2"));
});
