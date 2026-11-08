// The Auction House tab: the game's own categories and filters, over Blizzard's data.
// No page code here, so the Node tests can run it.
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.AH = factory();
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  // The game's auction house categories: item class, name, and its subclasses.
  const CLASSES = [
    [2, "Weapons", { 0: "One-Handed Axes", 1: "Two-Handed Axes", 2: "Bows", 3: "Guns", 4: "One-Handed Maces", 5: "Two-Handed Maces", 6: "Polearms",
      7: "One-Handed Swords", 8: "Two-Handed Swords", 10: "Staves", 13: "Fist Weapons", 14: "Miscellaneous", 15: "Daggers", 16: "Thrown",
      18: "Crossbows", 19: "Wands", 20: "Fishing Poles" }],
    [4, "Armor", { 0: "Miscellaneous", 1: "Cloth", 2: "Leather", 3: "Mail", 4: "Plate", 6: "Shields", 7: "Librams", 8: "Idols", 9: "Totems" }],
    [1, "Containers", { 0: "Bags", 1: "Soul Bags", 2: "Herb Bags", 3: "Enchanting Bags", 4: "Engineering Bags" }],
    [0, "Consumables", { 0: "Consumables", 1: "Potions", 2: "Elixirs", 3: "Flasks", 4: "Scrolls", 5: "Food & Drink", 6: "Item Enhancements", 7: "Bandages", 8: "Other" }],
    [7, "Trade Goods", { 0: "Trade Goods", 1: "Parts", 2: "Explosives", 3: "Devices", 5: "Cloth", 6: "Leather", 7: "Metal & Stone", 8: "Meat", 9: "Herbs",
      10: "Elemental", 11: "Other", 12: "Enchanting" }],
    [6, "Projectiles", { 2: "Arrows", 3: "Bullets" }],
    [11, "Quivers", { 2: "Quivers", 3: "Ammo Pouches" }],
    [9, "Recipes", { 0: "Books", 1: "Leatherworking", 2: "Tailoring", 3: "Engineering", 4: "Blacksmithing", 5: "Cooking", 6: "Alchemy", 7: "First Aid",
      8: "Enchanting", 9: "Fishing" }],
    [5, "Reagents", { 0: "Reagents" }],
    [15, "Miscellaneous", { 0: "Junk", 1: "Reagents", 2: "Pets", 3: "Holiday", 4: "Other", 5: "Mounts" }],
    [12, "Quest Items", {}],
    [13, "Keys", {}],
  ];
  const BY_CLASS = new Map(CLASSES.map(([id, name, subs]) => [id, { name, subs }]));

  // Armor slots, as the game's slot filter names them. Robes count as chest.
  const SLOTS = [[1, "Head"], [2, "Neck"], [3, "Shoulder"], [16, "Back"], [5, "Chest"], [9, "Wrist"], [10, "Hands"], [6, "Waist"], [7, "Legs"],
    [8, "Feet"], [11, "Finger"], [12, "Trinket"], [23, "Held in Off-hand"], [4, "Shirt"], [19, "Tabard"]];
  const SAME_SLOT = { 20: 5 };

  const QUALITIES = ["Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary"];

  const PREFIX = "ah:";
  const isAuctionCategory = (id) => id === "all" || (typeof id === "string" && id.startsWith(PREFIX) && parse(id) !== null);

  // "ah:4" is Armor, "ah:4:1" is Cloth armor; null if unknown.
  function parse(id) {
    const [, cl, sc] = String(id).split(":");
    const classId = Number(cl);
    if (!BY_CLASS.has(classId)) return null;
    if (sc === undefined) return { classId, subclassId: null };
    const subclassId = Number(sc);
    return subclassId in BY_CLASS.get(classId).subs ? { classId, subclassId } : null;
  }

  function matches(categoryId, item) {
    if (!categoryId || categoryId === "all") return true;
    const where = parse(categoryId);
    if (!where) return true;
    return item.cl === where.classId && (where.subclassId == null || item.sc === where.subclassId);
  }

  // filters: { minLevel, maxLevel (required level), quality, slot } — empty strings mean any.
  function passes(item, filters) {
    const level = item.rl || 0;
    if (filters.minLevel !== "" && filters.minLevel != null && level < Number(filters.minLevel)) return false;
    if (filters.maxLevel !== "" && filters.maxLevel != null && level > Number(filters.maxLevel)) return false;
    if (filters.quality !== "" && filters.quality != null && item.q !== Number(filters.quality)) return false;
    if (filters.slot !== "" && filters.slot != null) {
      const slot = SAME_SLOT[item.inv] || item.inv;
      if (slot !== Number(filters.slot)) return false;
    }
    return true;
  }

  // Listed items per category, for the counts beside each name.
  function counts(items) {
    const out = new Map();
    const add = (key) => out.set(key, (out.get(key) || 0) + 1);
    for (const item of items) {
      if (!BY_CLASS.has(item.cl)) continue;
      add("all");
      add(PREFIX + item.cl);
      if (item.sc in BY_CLASS.get(item.cl).subs) add(`${PREFIX}${item.cl}:${item.sc}`);
    }
    return out;
  }

  // Sidebar groups in the game's order, leaving out anything with nothing listed.
  function groups(countMap) {
    return CLASSES.filter(([id]) => countMap.get(PREFIX + id)).map(([id, name, subs]) => ({
      label: name,
      categories: [{ id: PREFIX + id, label: `All ${name.toLowerCase()}` }].concat(
        Object.keys(subs).filter((sc) => countMap.get(`${PREFIX}${id}:${sc}`)).map((sc) => ({ id: `${PREFIX}${id}:${sc}`, label: subs[sc] }))),
    }));
  }

  function label(categoryId) {
    const where = parse(categoryId);
    if (!where) return "All items";
    const cls = BY_CLASS.get(where.classId);
    return where.subclassId == null ? cls.name : `${cls.subs[where.subclassId]} (${cls.name})`;
  }

  // The slot filter only makes sense for armor.
  const showsSlots = (categoryId) => { const where = parse(categoryId); return Boolean(where && where.classId === 4); };

  return { CLASSES, SLOTS, QUALITIES, isAuctionCategory, matches, passes, counts, groups, label, showsSlots };
});
