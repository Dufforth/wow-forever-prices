// Item categories and icon addresses. No page code here, so they run in Node tests too.
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.Categories = factory();
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  const ICON_BASE = "https://render.worldofwarcraft.com/us/icons/56/";
  const ICON_BACKUP = "https://wow.zamimg.com/images/wow/icons/medium/"; // Has Forever's newest icons.
  const PROFESSION_PREFIX = "prof:";

  const type = (cl, sc) => (item) => item.cl === cl && (sc === undefined || item.sc === sc);
  const anyOf = (...tests) => (item) => tests.some((test) => test(item));
  const gathered = (group) => (item) => item.g === group;

  const SPECIFIC_TYPES = [
    { id: "potion", label: "Potions", test: type(0, 1) },
    { id: "elixir", label: "Elixirs and flasks", test: anyOf(type(0, 2), type(0, 3)) },
    { id: "food", label: "Food and drink", test: type(0, 5) },
    { id: "bandage", label: "Bandages", test: type(0, 7) },
    { id: "explosive", label: "Explosives and devices", test: anyOf(type(0, 0), type(0, 14)) },
    { id: "consumable", label: "Other consumables", test: type(0) },
    { id: "weapon", label: "Weapons", test: type(2) },
    { id: "armor-cloth", label: "Cloth armor", test: type(4, 1) },
    { id: "armor-leather", label: "Leather armor", test: type(4, 2) },
    { id: "armor-mail", label: "Mail armor", test: type(4, 3) },
    { id: "armor-plate", label: "Plate armor", test: type(4, 4) },
    { id: "armor-other", label: "Shields and other armor", test: type(4) },
    { id: "bag", label: "Bags", test: type(1) },
    { id: "ammo", label: "Ammo and quivers", test: anyOf(type(6), type(11)) },
    { id: "parts", label: "Engineering parts", test: type(7, 1) },
    { id: "trade", label: "Other trade goods", test: type(7) },
  ];

  // Each item belongs to the first type that matches, and to "Other" when none does.
  function typeOf(item) {
    const found = SPECIFIC_TYPES.find((category) => category.test(item));
    return found ? found.id : "other";
  }

  const TYPE_CATEGORIES = SPECIFIC_TYPES
    .map(({ id, label }) => ({ id, label, test: (item) => typeOf(item) === id }))
    .concat({ id: "other", label: "Other", test: (item) => typeOf(item) === "other" });

  const GATHERING_CATEGORIES = [
    { id: "herb", label: "Herbs", test: gathered("herb") },
    { id: "ore", label: "Ore, bars and stone", test: gathered("ore") },
    { id: "leather", label: "Leather and hides", test: gathered("leather") },
    { id: "cloth", label: "Cloth", test: gathered("cloth") },
    { id: "enchant", label: "Enchanting materials", test: gathered("enchant") },
    { id: "elemental", label: "Elemental", test: type(7, 10) },
    { id: "cooking", label: "Cooking ingredients", test: type(7, 8) },
  ];

  // The most specific name for an item, such as "Herbs" rather than "Other trade goods".
  function typeLabel(item) {
    const gatheredCategory = GATHERING_CATEGORIES.find((category) => category.test(item));
    if (gatheredCategory) return gatheredCategory.label;
    const id = typeOf(item);
    return (TYPE_CATEGORIES.find((category) => category.id === id) || { label: "Other" }).label;
  }

  const MARKET_CATEGORIES = [
    { id: "most-posted", label: "Most posted" },
    { id: "most-bought", label: "Most bought (estimate)" },
  ];

  function groups(professions) {
    return [
      { label: "Market", categories: MARKET_CATEGORIES },
      { label: "Gathering", categories: GATHERING_CATEGORIES },
      {
        label: "Crafted by",
        categories: professions.map((name) => ({ id: PROFESSION_PREFIX + name, label: name })),
      },
      { label: "Item type", categories: TYPE_CATEGORIES },
    ];
  }

  const byId = new Map(GATHERING_CATEGORIES.concat(TYPE_CATEGORIES).map((category) => [category.id, category]));

  // context: { favorites: Set of item IDs, craftedBy: Map of item ID to profession names }
  function matches(categoryId, id, item, context) {
    if (categoryId === "all") return true;
    if (categoryId === "favorites") return context.favorites.has(Number(id));
    if (categoryId === "most-posted") return Boolean(context.mostPosted && context.mostPosted.has(Number(id)));
    if (categoryId === "most-bought") return Boolean(context.mostBought && context.mostBought.has(Number(id)));
    if (categoryId.startsWith(PROFESSION_PREFIX)) {
      return (context.craftedBy.get(Number(id)) || []).includes(categoryId.slice(PROFESSION_PREFIX.length));
    }
    const category = byId.get(categoryId);
    return category ? category.test(item) : true;
  }

  function isKnown(categoryId, professions) {
    if (categoryId === "all" || categoryId === "favorites" || byId.has(categoryId)) return true;
    if (MARKET_CATEGORIES.some((category) => category.id === categoryId)) return true;
    return categoryId.startsWith(PROFESSION_PREFIX) && professions.includes(categoryId.slice(PROFESSION_PREFIX.length));
  }

  function label(categoryId) {
    if (categoryId === "all") return "All items";
    if (categoryId === "favorites") return "Favorites";
    const market = MARKET_CATEGORIES.find((category) => category.id === categoryId);
    if (market) return market.label;
    if (categoryId.startsWith(PROFESSION_PREFIX)) return "Crafted by " + categoryId.slice(PROFESSION_PREFIX.length);
    const category = byId.get(categoryId);
    return category ? category.label : "All items";
  }

  function iconUrl(name) {
    return name ? ICON_BASE + encodeURIComponent(name) + ".jpg" : null;
  }

  function iconBackupUrl(name) {
    return name ? ICON_BACKUP + encodeURIComponent(name) + ".jpg" : null;
  }

  return { groups, iconBackupUrl, iconUrl, isKnown, label, matches, typeLabel, typeOf, PROFESSION_PREFIX };
});
