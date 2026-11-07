(function () {
  "use strict";
  const { money, priceChange, rateReturn, ratePriceNow, significantChanges, craftRows, craftDisenchantRows, disenchantDeals, disenchantOutcomes } = Calc;
  const { groups, iconBackupUrl, iconUrl, isKnown, label: categoryLabel, matches, sourceLabel, sourceOf, typeLabel, PROFESSION_PREFIX } = Categories;

  // Plain explanations for column titles, shown on hover or keyboard focus.
  const HINTS = {
    "Item": "The item. Select it for details, history and recipes. Hover it to see its in-game tooltip.",
    "Lowest price": "The cheapest price anyone is asking for one right now.",
    "Market": "The typical price: the average of the cheapest 15% of items for sale. One unusually cheap or expensive listing barely moves it.",
    "Change %": "How much the typical price moved, compared with the setting above. +50% means it now costs one and a half times as much. -50% means half as much.",
    "Change": "The same price move, in gold, silver and copper.",
    "For sale": "How many are listed on this auction house right now.",
    "Vendor pays": "What a vendor (NPC) gives you if you sell one to them. Selling on the auction house for less than this loses money.",
    "Vendor sells at": "What a vendor (NPC) charges for one, for reagents vendors are known to sell.",
    "Bought, 7 days (est.)": "A guess at how many sold in the last 7 days, from how much the number for sale dropped. Expired listings look the same, so treat it as a rough guide.",
    "24 hour average": "The average typical price over the last 24 hours.",
    "7 day average": "The average typical price over the last 7 days. Use it to tell whether today's price is unusual.",
    "Source": "Where the item comes from: crafted by a profession, gathered, sold by vendors, or anything else (usually drops).",
    "Type": "What kind of item it is.",
    "Now": "The typical price right now.",
    "Before": "The typical price it's compared against.",
    "Profit": "What you keep per craft after buying the reagents and paying the 5% auction cut. Green means you make money, red means you lose money.",
    "Sell by": "The best way to sell what you craft: on the auction house, by disenchanting it, or to a vendor.",
    "Craft cost": "What the reagents for one craft cost, buying each the cheapest way.",
    "Auction, after cut": "What one craft's items sell for on the auction house, minus the 5% the auction house keeps.",
    "Disenchant": "What one craft's items are worth if you disenchant them and sell the materials, on average.",
    "Vendor": "What a vendor pays for one craft's items.",
    "Margin": "Profit compared with what you spend. 50% means you get back one and a half times your cost.",
    "Profession": "The profession that makes it.",
    "Expected profit": "What you keep on average after paying for the item and selling the materials, with the 5% auction cut taken off.",
    "Expected materials": "What the enchanting materials are worth on average, after the 5% auction cut.",
    "Return": "Profit compared with what you spend. 100% means you double your money on average.",
    "Skill needed": "The Enchanting skill needed to disenchant it.",
    "Mostly gives": "The material it gives most often when disenchanted. Select the item for all the odds.",
  };
  const PAGE = 100;
  const POLL_MS = 5 * 60 * 1000;
  const STALE_SECONDS = 12 * 3600;
  const SEARCH_DELAY_MS = 150;
  const TABS = ["prices", "alerts", "profit", "deals", "scan"];
  const SUGGESTIONS = 12;
  const SELL_BY = { "Sell on auction": "Auction", Disenchant: "Disenchant", "Sell to vendor": "Vendor" };
  const SOURCE = { auction: "Auction", vendor: "Vendor", craft: "Craft it", none: "No price" };

  const $ = (id) => document.getElementById(id);
  const esc = (text) => String(text).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const number = (value) => Number(value).toLocaleString("en-US");

  const store = {
    get(key, fallback) { try { const v = localStorage.getItem("fp." + key); return v == null ? fallback : JSON.parse(v); } catch (e) { return fallback; } },
    set(key, value) { try { localStorage.setItem("fp." + key, JSON.stringify(value)); } catch (e) { /* private window */ } },
  };

  const state = {
    catalog: null, gear: null, meta: null, house: null, prices: {}, ts: null, history: null,
    rows: null, deals: null, professions: [], craftedBy: new Map(), mostPosted: new Set(), mostBought: new Set(),
    scanList: store.get("scanList", []), allItems: null, suggestions: [], activeSuggestion: -1,
    fileTs: null, published: {}, scans: store.get("scans", {}), scanHandle: null,
    favorites: new Set(store.get("favorites", [])),
    loading: true, tab: "prices", category: "all", search: "", source: "all", collapsed: store.get("collapsed", { "Crafted by": true, "Item type": true }), limit: PAGE, detailId: null,
    sort: {
      prices: { key: "name", dir: 1 }, profit: { key: "profit", dir: -1 },
      alerts: { key: "percent", dir: -1 }, deals: { key: "profit", dir: -1 }, scan: { key: "name", dir: 1 },
    },
    de: Object.assign({ mode: "buy", skill: "", supply: "" }, store.get("de", {})),
    alert: Object.assign({ percent: 15, amount: 10, supply: 5, basis: "previous", favorites: false }, store.get("alert", {})),
  };

  async function getJson(url) {
    const response = await fetch(url, { cache: "no-cache" });
    if (!response.ok) throw new Error(`${url}: ${response.status}`);
    return response.json();
  }

  const context = () => ({ favorites: state.favorites, craftedBy: state.craftedBy, mostPosted: state.mostPosted, mostBought: state.mostBought, scanList: new Set(state.scanList) });
  function tradableItem(id) {
    const row = state.allItems && state.allItems[id];
    return row ? { n: row[0], q: row[1], ic: row[2], cl: row[3], sc: row[4], sell: row[5] } : null;
  }
  const itemOf = (id) => state.catalog.items[id] || (state.gear && state.gear[id]) || tradableItem(id) || { n: "Item " + id, q: 1 };

  function coins(copper) {
    const text = money(copper);
    return text === "–" ? '<span class="muted">–</span>'
      : esc(text).replace(/(\d)([gsc])/g, '$1<span class="u u-$2">$2</span>');
  }

  function iconHtml(item) {
    const url = iconUrl(item.ic);
    return url ? `<img class="icon" src="${esc(url)}" data-backup="${esc(iconBackupUrl(item.ic))}" alt="" width="28" height="28" loading="lazy" decoding="async">`
      : '<span class="icon" aria-hidden="true"></span>';
  }

  function starHtml(id, item) {
    const on = state.favorites.has(Number(id));
    return `<button type="button" class="star" data-star="${Number(id)}" aria-pressed="${on}" aria-label="${on ? "Remove" : "Add"} ${esc(item.n)} ${on ? "from" : "to"} favorites">${on ? "★" : "☆"}</button>`;
  }

  function itemCell(id, extra) {
    const item = itemOf(id);
    return `<div class="item-cell">${starHtml(id, item)}${iconHtml(item)}<span><button type="button" class="name q${item.q}" data-open="${Number(id)}">${esc(item.n)}</button>${extra || ""}</span></div>`;
  }

  // The cheapest listing, or the last known price if none are for sale.
  // What a vendor pays, and what a vendor charges for the reagents they're known to sell.
  const vendorPays = (item) => (item.sell > 0 ? item.sell : null);
  const vendorCharges = (item) => (item.v && item.buy > 0 ? item.buy : null);
  const lowestOf = (row) => (row ? (row[0] == null ? row[1] : row[0]) : null);

  const BADGES = {
    good: ["Good deal", "good"], fair: ["Fair", "fair"], poor: ["Loss", "poor"],
    cheap: ["Cheap now", "good"], usual: ["Usual price", "fair"], pricey: ["Pricey now", "warn"],
    cheaper: ["Got cheaper", "good"], pricier: ["Got pricier", "warn"],
  };
  const badge = (kind) => (kind ? `<span class="deal deal-${BADGES[kind][1]}">${BADGES[kind][0]}</span>` : '<span class="muted">–</span>');
  const goodRow = (kind) => (kind && BADGES[kind][1] === "good" ? "good-row" : "");

  const hasChange = (change) => Boolean(change && change.amount !== 0);
  const changeTone = (change) => (hasChange(change) ? "" : "muted"); // A move up or down isn't good or bad by itself.
  const changeAmount = (change) => (hasChange(change) ? `${change.amount > 0 ? "▲" : "▼"} ${coins(Math.abs(change.amount))}` : "–");
  const changePercent = (change) => (hasChange(change) ? `${change.amount > 0 ? "+" : "-"}${Math.abs(change.percent).toFixed(1)}%` : "–");

  // ---- Plain sentences for each cell (shown when you hover a cell) ----
  const BASIS_TEXT = { previous: "the last update", day: "the 24-hour average", week: "the 7-day average" };
  const pct = (fraction) => `${Math.round(fraction * 100)}%`;
  const say = {
    lowest: (row) => (!row ? "No price data for this item yet."
      : row[2] > 0 ? `The cheapest one for sale right now costs ${money(lowestOf(row))}.`
      : `None for sale right now. The last price seen was ${money(lowestOf(row))}.`),
    market: (row) => (row && row[1] != null ? `Most of the cheaper listings cost about ${money(row[1])}. That's a fairer price than the single cheapest one.` : "No price data yet."),
    now: (row) => {
      const rating = ratePriceNow(row);
      if (!rating) return "Not enough price history yet to compare.";
      const base = `Today it costs about ${money(row[1])}; the 7-day average is ${money(row[5])}.`;
      return `${base} ${{ cheap: "That's cheaper than usual: a good time to buy.", usual: "That's about normal.", pricey: "That's more than usual: a good time to sell." }[rating]}`;
    },
    change: (change, basis) => {
      if (!change) return `No earlier price to compare with ${BASIS_TEXT[basis] || "before"}.`;
      if (!hasChange(change)) return `Same price as ${BASIS_TEXT[basis]}.`;
      const up = change.amount > 0;
      const times = up && change.percent >= 100 ? ` It now costs about ${(1 + change.percent / 100).toFixed(1)} times as much.` : "";
      return `${up ? "Up" : "Down"} ${money(Math.abs(change.amount))} (${Math.abs(change.percent).toFixed(1)}%) from ${money(change.old)} at ${BASIS_TEXT[basis]} to ${money(change.old + change.amount)}.${times}`;
    },
    supply: (count) => (count > 0 ? `${number(count)} for sale on the auction house right now.` : "None for sale right now."),
    vendorPays: (item, row) => {
      const pays = vendorPays(item);
      if (!pays) return "Vendors won't buy this item.";
      const cheapest = row && row[2] > 0 ? lowestOf(row) : null;
      return `A vendor pays ${money(pays)} for one.${cheapest != null && cheapest < pays ? " That's more than the cheapest auction, so buying it and selling to a vendor makes money." : ""}`;
    },
    vendorSells: (item) => (vendorCharges(item) ? `A vendor sells this for ${money(vendorCharges(item))}.` : "No vendor sells this item."),
    deal: (profit, spend, verb) => {
      if (profit == null || spend == null) return "Some prices are missing, so the deal can't be worked out.";
      const back = spend + profit;
      if (profit <= 0) return `You ${verb} ${money(spend)} and get back ${money(back)}, losing ${money(-profit)}.`;
      const share = spend > 0 ? pct(profit / spend) : "much";
      return `You ${verb} ${money(spend)} and get back ${money(back)}: ${share} more. ${rateReturn(profit, spend) === "good" ? "A good deal." : "A small profit."}`;
    },
  };


  function sortRows(rows, spec, getters) {
    const get = getters[spec.key];
    return rows.slice().sort((a, b) => {
      const x = get(a), y = get(b);
      if (x == null && y == null) return 0;
      if (x == null) return 1;
      if (y == null) return -1;
      if (typeof x === "string") return x.localeCompare(y) * spec.dir;
      return (x - y) * spec.dir;
    });
  }

  function emptyRow(columns, text) {
    return `<tr><td class="empty" colspan="${columns}">${esc(text)}</td></tr>`;
  }

  // Every tab draws through here: one table, one count line, one Show more button.
  // A column has a label and a cell, and optionally a sort key, alignment (left),
  // tone (a class for the cell) and priority (p: 1 to 3; higher hides sooner on small screens).
  // A cell explains its own value with `say`, or falls back to what the column means.
  function cellHint(column, row) {
    if (column.key === "name" || !column.hint) return "";
    const text = column.say ? column.say(row) : column.hint;
    return text ? ` data-cell="${esc(text)}"` : "";
  }

  function drawTable(columns, rows, rowAttributes, emptyText, unit, rowClass) {
    const spec = state.sort[state.tab];
    const classes = (column, extra) => {
      const list = [column.left && "left", column.p && `p${column.p}`, extra].filter(Boolean);
      return list.length ? ` class="${list.join(" ")}"` : "";
    };
    const head = columns.map((column) => {
      const hint = column.hint ? ` data-hint="${esc(column.hint)}"` : "";
      const label = column.hint ? `<span class="hinted">${column.label}</span>` : column.label;
      if (!column.key) return `<th scope="col"${classes(column)}${hint}${column.hint ? ' tabindex="0"' : ""}>${label}</th>`;
      const sort = column.key === spec.key ? (spec.dir > 0 ? "ascending" : "descending") : "none";
      return `<th scope="col"${classes(column)}${hint} data-sort="${column.key}" aria-sort="${sort}" tabindex="0">${label}</th>`;
    }).join("");
    const shown = rows.slice(0, state.limit);
    const body = shown.map((row) => `<tr class="row${rowClass && rowClass(row) ? " " + rowClass(row) : ""}" ${rowAttributes(row)}>${columns.map((column) => `<td${classes(column, column.tone && column.tone(row))}${cellHint(column, row)}>${column.cell(row)}</td>`).join("")}</tr>`).join("")
      || emptyRow(columns.length, state.loading ? "Loading prices…" : emptyText);
    $("table").innerHTML = `<thead><tr>${head}</tr></thead><tbody>${body}</tbody>`;
    const parts = [];
    if (state.category !== "all") parts.push(categoryLabel(state.category));
    if (state.source !== "all" && state.tab !== "profit") parts.push(sourceLabel(state.source).toLowerCase());
    const scope = parts.length ? ` in ${parts.join(", ")}` : "";
    $("result-count").textContent = `${number(rows.length)} ${unit}${rows.length === 1 ? "" : "s"}${scope}`;
    $("clear-filters").hidden = state.category === "all" && !state.search && (state.source === "all" || state.tab === "profit");
    const left = rows.length - shown.length;
    $("more").hidden = left <= 0;
    $("more").textContent = `Show ${number(Math.min(left, PAGE))} more of ${number(left)}`;
  }

  function passesFilters(id, item) {
    if (state.search && !item.n.toLowerCase().includes(state.search)) return false;
    if (state.source !== "all" && sourceOf(id, item, context()) !== state.source) return false;
    return matches(state.category, id, item, context());
  }

  // Every item people can trade, not only profession items. The full list loads after the page.
  function allItemIds() {
    if (!state.allItems) return Object.keys(state.catalog.items);
    const ids = new Set(Object.keys(state.allItems));
    for (const id of Object.keys(state.catalog.items)) ids.add(id);
    return [...ids];
  }

  // ---- Prices ----
  function renderPrices() {
    const basis = $("price-basis").value;
    const listedOnly = $("price-listed").checked && state.category !== "favorites" && state.category !== "scan-list";
    let rows = [];
    // These lists can hold items outside the profession catalog.
    const special = { "scan-list": state.scanList, "most-posted": [...state.mostPosted], "most-bought": [...state.mostBought] }[state.category];
    for (const id of (special || allItemIds()).map(String)) {
      const item = itemOf(id);
      if (!passesFilters(id, item)) continue;
      const row = state.prices[id];
      if (listedOnly && !(row && row[2] > 0)) continue;
      rows.push({ id, item, row, change: row ? priceChange(row, basis) : null });
    }
    rows = sortRows(rows, state.sort.prices, {
      name: (r) => r.item.n, price: (r) => lowestOf(r.row), market: (r) => (r.row ? r.row[1] : null),
      amount: (r) => (r.change ? r.change.amount : null), percent: (r) => (r.change ? r.change.percent : null),
      supply: (r) => (r.row ? r.row[2] : null), day: (r) => (r.row ? r.row[4] : null), week: (r) => (r.row ? r.row[5] : null),
      bought: (r) => (r.row ? r.row[6] || 0 : null),
      now: (r) => { const rating = ratePriceNow(r.row); return rating ? { cheap: 0, usual: 1, pricey: 2 }[rating] : null; },
      vendor: (r) => vendorPays(r.item), vendorBuy: (r) => vendorCharges(r.item),
      type: (r) => typeLabel(r.item), source: (r) => sourceLabel(sourceOf(r.id, r.item, context())),
    });
    drawTable([
      { key: "name", label: "Item", hint: HINTS["Item"], left: true, cell: (r) => itemCell(r.id) },
      { key: "price", label: "Lowest price", hint: HINTS["Lowest price"], say: (r) => say.lowest(r.row), cell: (r) => `${coins(lowestOf(r.row))}${r.row && !r.row[2] ? ' <span class="badge">last seen</span>' : ""}` },
      { key: "market", label: "Market", hint: HINTS["Market"], say: (r) => say.market(r.row), p: 1, cell: (r) => coins(r.row ? r.row[1] : null) },
      { key: "now", label: "Price now", hint: "Is today's typical price cheap, usual or pricey compared with its 7-day average? Cheap is a good time to buy; pricey is a good time to sell.", say: (r) => say.now(r.row), cell: (r) => badge(ratePriceNow(r.row)) },
      { key: "percent", label: "Change %", hint: HINTS["Change %"], say: (r) => say.change(r.change, basis), p: 1, tone: (r) => changeTone(r.change), cell: (r) => changePercent(r.change) },
      { key: "amount", label: "Change", hint: HINTS["Change"], say: (r) => say.change(r.change, basis), p: 2, tone: (r) => changeTone(r.change), cell: (r) => changeAmount(r.change) },
      { key: "supply", label: "For sale", hint: HINTS["For sale"], say: (r) => say.supply(r.row ? r.row[2] : 0), p: 1, cell: (r) => (r.row ? number(r.row[2]) : "–") },
      { key: "vendor", label: "Vendor pays", hint: HINTS["Vendor pays"], say: (r) => say.vendorPays(r.item, r.row), p: 1, cell: (r) => coins(vendorPays(r.item)) },
      { key: "vendorBuy", label: "Vendor sells at", hint: HINTS["Vendor sells at"], say: (r) => say.vendorSells(r.item), p: 3, cell: (r) => coins(vendorCharges(r.item)) },
      { key: "bought", label: "Bought, 7 days (est.)", hint: HINTS["Bought, 7 days (est.)"], say: (r) => (r.row ? `About ${number(r.row[6] || 0)} bought in the last 7 days. This is a guess from listings that disappeared, and some of those may have expired instead.` : "No data yet."), p: 3, cell: (r) => (r.row ? number(r.row[6] || 0) : "–") },
      { key: "day", label: "24 hour average", hint: HINTS["24 hour average"], say: (r) => (r.row && r.row[4] ? `Over the last 24 hours it cost ${money(r.row[4])} on average.` : "Not enough history yet."), p: 3, cell: (r) => coins(r.row ? r.row[4] : null) },
      { key: "week", label: "7 day average", hint: HINTS["7 day average"], say: (r) => (r.row && r.row[5] ? `Over the last 7 days it cost ${money(r.row[5])} on average.` : "Not enough history yet."), p: 3, cell: (r) => coins(r.row ? r.row[5] : null) },
      { key: "source", label: "Source", hint: HINTS["Source"], left: true, p: 2, cell: (r) => esc(sourceLabel(sourceOf(r.id, r.item, context()))) },
      { key: "type", label: "Type", hint: HINTS["Type"], left: true, p: 3, cell: (r) => esc(typeLabel(r.item)) },
    ], rows, (r) => `data-item="${r.id}"`, "No items match. Try another category or source, or clear your search.", "item", (r) => goodRow(ratePriceNow(r.row)));
  }

  // ---- Alerts ----
  let alertsCache = { key: null, list: null };
  function allAlerts() {
    const a = state.alert;
    const key = JSON.stringify([state.house, state.ts, a, a.favorites ? [...state.favorites] : 0]);
    if (alertsCache.key === key) return alertsCache.list;
    alertsCache = { key, list: computeAlerts(a) };
    return alertsCache.list;
  }

  function computeAlerts(a) {
    return significantChanges(state.prices, { percent: a.percent, minAmount: a.amount * 100, minSupply: a.supply, basis: a.basis })
      .filter((c) => state.catalog.items[c.id] && (!a.favorites || state.favorites.has(c.id)));
  }

  function updateAlertBadge() {
    const count = allAlerts().length;
    $("alert-count").hidden = count === 0;
    $("alert-count").textContent = count;
  }

  function renderAlerts() {
    const filtered = allAlerts().filter((c) => passesFilters(c.id, itemOf(c.id))).map((c) => ({ ...c, name: itemOf(c.id).n }));
    const rows = sortRows(filtered, state.sort.alerts, {
      name: (r) => r.name, price: (r) => r.market, old: (r) => r.old, amount: (r) => Math.abs(r.amount),
      percent: (r) => Math.abs(r.percent), supply: (r) => r.supply, meaning: (r) => r.amount, vendor: (r) => vendorPays(itemOf(r.id)),
    });
    drawTable([
      { key: "name", label: "Item", hint: HINTS["Item"], left: true, cell: (r) => itemCell(r.id) },
      { key: "price", label: "Now", hint: HINTS["Now"], say: (r) => `It costs about ${money(r.market)} now.`, cell: (r) => coins(r.market) },
      { key: "meaning", label: "What it means", hint: "Got cheaper: a chance to buy for less than before. Got pricier: a chance to sell for more than before.", say: (r) => `${say.change(r, state.alert.basis)} ${r.amount < 0 ? "A chance to buy for less." : "A chance to sell for more."}`, cell: (r) => badge(r.amount < 0 ? "cheaper" : "pricier") },
      { key: "percent", label: "Change %", hint: HINTS["Change %"], say: (r) => say.change(r, state.alert.basis), p: 1, tone: (r) => changeTone(r), cell: (r) => changePercent(r) },
      { key: "old", label: "Before", hint: HINTS["Before"], say: (r) => `It cost ${money(r.old)} at ${BASIS_TEXT[state.alert.basis]}.`, p: 1, cell: (r) => coins(r.old) },
      { key: "amount", label: "Change", hint: HINTS["Change"], say: (r) => say.change(r, state.alert.basis), p: 1, tone: (r) => changeTone(r), cell: (r) => changeAmount(r) },
      { key: "supply", label: "For sale", hint: HINTS["For sale"], say: (r) => say.supply(r.supply), p: 1, cell: (r) => number(r.supply) },
      { key: "vendor", label: "Vendor pays", hint: HINTS["Vendor pays"], say: (r) => say.vendorPays(itemOf(r.id), state.prices[r.id]), p: 1, cell: (r) => coins(vendorPays(itemOf(r.id))) },
    ], rows, (r) => `data-item="${r.id}"`,
    state.ts ? "No big price changes with these settings. Lower the limits to see more." : "Waiting for price data.", "alert", (r) => (r.amount < 0 ? "good-row" : ""));
  }

  // ---- Profit ----
  // A craft can make several items, so every money column shows the whole craft.
  const perCraft = (each, row) => (each == null ? null : each * row.recipe.c);

  function renderProfit() {
    state.rows = state.rows || craftRows(state.catalog, state.prices);
    const profession = state.category.startsWith(PROFESSION_PREFIX) ? state.category.slice(PROFESSION_PREFIX.length) : null;
    const onlyProfitable = $("profit-only").checked;
    const supply = Number($("profit-supply").value) || 0;
    let rows = state.rows.filter((r) => {
      if (profession ? r.recipe.p !== profession : !matches(state.category, r.recipe.i, r.item, context())) return false;
      if (state.search && !r.item.n.toLowerCase().includes(state.search)) return false;
      if (onlyProfitable && !(r.profit > 0)) return false;
      if (supply && r.best && r.best.kind === "Sell on auction" && r.supply < supply) return false;
      return true;
    });
    rows = sortRows(rows, state.sort.profit, {
      name: (r) => r.item.n, profession: (r) => r.recipe.p, cost: (r) => r.cost, ah: (r) => perCraft(r.ah, r), de: (r) => perCraft(r.de, r),
      vendor: (r) => perCraft(r.vendor, r), deal: (r) => (r.profit == null ? null : r.cost > 0 ? r.profit / r.cost : 0), profit: (r) => r.profit, margin: (r) => r.margin, supply: (r) => r.supply,
    });
    const profitTone = (r) => (r.profit == null ? "muted" : r.profit > 0 ? "up" : "down");
    const profitArrow = (r) => (r.profit == null ? "" : r.profit > 0 ? "▲ " : "▼ ");
    drawTable([
      { key: "name", label: "Item", hint: HINTS["Item"], left: true, cell: (r) => itemCell(r.recipe.i, r.recipe.c > 1 ? ` <span class="badge">makes ${r.recipe.c}</span>` : "") },
      { key: "deal", label: "Deal", hint: "Good deal: you get back at least 20% more than you spend. Fair: a small profit. Loss: you lose money.", say: (r) => say.deal(r.profit, r.cost, "spend"), cell: (r) => badge(rateReturn(r.profit, r.cost)) },
      { key: "profit", label: "Profit", hint: HINTS["Profit"], say: (r) => (r.profit == null ? "Some reagent prices are missing, so profit can't be worked out." : `Making it costs ${money(r.cost)} and the best way to sell brings ${money(r.cost + r.profit)}, so you ${r.profit > 0 ? "keep" : "lose"} ${money(Math.abs(r.profit))}.`), tone: profitTone, cell: (r) => `${profitArrow(r)}${coins(r.profit)}` },
      { label: "Sell by", hint: HINTS["Sell by"], say: (r) => (r.best ? { "Sell on auction": "Selling it on the auction house earns the most.", Disenchant: "Disenchanting it and selling the materials earns the most.", "Sell to vendor": "Selling it to a vendor earns the most." }[r.best.kind] : "No way to sell it has a price yet."), left: true, p: 1, cell: (r) => (r.best ? SELL_BY[r.best.kind] : "–") },
      { key: "cost", label: "Craft cost", hint: HINTS["Craft cost"], say: (r) => (r.cost == null ? `No price yet for: ${r.missing.map((id) => itemOf(id).n).join(", ")}.` : `Getting all the reagents the cheapest way costs ${money(r.cost)}. Open the item to see each reagent.`), p: 1, cell: (r) => (r.cost == null ? '<span class="muted">Missing prices</span>' : coins(r.cost)) },
      { key: "ah", label: "Auction, after cut", hint: HINTS["Auction, after cut"], say: (r) => (r.ah == null ? "It can't be sold on the auction house, or it has no price there." : `Selling on the auction house brings ${money(perCraft(r.ah, r))} after the 5% cut.`), p: 2, cell: (r) => coins(perCraft(r.ah, r)) },
      { key: "de", label: "Disenchant", hint: HINTS["Disenchant"], say: (r) => (r.de == null ? "It can't be disenchanted, or its materials have no price." : `Disenchanting gives materials worth about ${money(perCraft(r.de, r))} on average, after the 5% cut.`), p: 2, cell: (r) => coins(perCraft(r.de, r)) },
      { key: "vendor", label: "Vendor", hint: HINTS["Vendor"], say: (r) => (r.vendor ? `A vendor pays ${money(perCraft(r.vendor, r))}.` : "Vendors won't buy it."), p: 3, cell: (r) => coins(perCraft(r.vendor, r)) },
      { key: "margin", label: "Margin", hint: HINTS["Margin"], say: (r) => (r.margin == null ? "Not known yet." : `${pct(r.margin)} of what you sell it for is profit.`), p: 3, cell: (r) => (r.margin == null ? "–" : (r.margin * 100).toFixed(0) + "%") },
      { key: "supply", label: "For sale", hint: HINTS["For sale"], say: (r) => `${say.supply(r.supply || 0)} More listings means more sellers to compete with.`, p: 2, cell: (r) => number(r.supply || 0) },
      { key: "profession", label: "Profession", hint: HINTS["Profession"], left: true, p: 3, cell: (r) => esc(r.recipe.p) },
    ], rows, (r) => `data-recipe="${r.recipe.s}"`,
    state.ts ? "No recipes match. Try another category, clear your search or turn off Profitable only." : "Waiting for price data.", "recipe", (r) => goodRow(rateReturn(r.profit, r.cost)));
  }

  // ---- Disenchant deals ----
  function materialCell(id) {
    if (!id) return "–";
    const material = itemOf(id);
    return `<div class="item-cell" data-item="${Number(id)}">${iconHtml(material)}<span class="q${material.q}">${esc(material.n)}</span></div>`;
  }

  function renderDeals() {
    const crafting = state.de.mode === "craft";
    if (!crafting && !state.gear) {
      $("table").innerHTML = `<tbody>${emptyRow(5, "Loading the gear list…")}</tbody>`;
      $("result-count").textContent = "";
      $("more").hidden = true;
      getJson("gear.json").then((gear) => { state.gear = gear; render(); }).catch(() => {
        $("table").innerHTML = `<tbody>${emptyRow(5, "The gear list could not load. Try refreshing.")}</tbody>`;
      });
      return;
    }
    if (crafting) {
      state.rows = state.rows || craftRows(state.catalog, state.prices);
      state.craftDeals = state.craftDeals || craftDisenchantRows(state.rows);
    } else {
      state.deals = state.deals || disenchantDeals(state.gear, state.prices);
    }
    const skill = Number(state.de.skill) || null;
    const supply = Number(state.de.supply) || 0;
    let rows = (crafting ? state.craftDeals : state.deals).filter((d) => d.profit > 0
      && (!skill || d.skill <= skill)
      && (crafting || d.supply >= supply)
      && passesFilters(d.id, d.item));
    rows = sortRows(rows, state.sort.deals, {
      name: (r) => r.item.n, price: (r) => r.price, value: (r) => r.value, profit: (r) => r.profit, supply: (r) => r.supply,
      roi: (r) => r.roi, skill: (r) => r.skill, material: (r) => (r.material ? itemOf(r.material).n : null),
      profession: (r) => (r.recipe ? r.recipe.p : null), vendor: (r) => vendorPays(r.item),
    });
    const makes = (r) => (r.recipe && r.recipe.c > 1 ? ` <span class="badge">makes ${r.recipe.c}</span>` : "");
    drawTable([
      { key: "name", label: "Item", hint: HINTS["Item"], left: true, cell: (r) => itemCell(r.id, makes(r)) },
      { key: "roi", label: "Deal", hint: "Good deal: on average you get back at least 20% more than you spend. Fair: a small expected profit.", say: (r) => say.deal(r.profit, r.price, crafting ? "spend" : "pay"), cell: (r) => badge(rateReturn(r.profit, r.price)) },
      { key: "profit", label: "Expected profit", hint: HINTS["Expected profit"], say: (r) => `On average you make ${money(r.profit)} by ${crafting ? "crafting" : "buying"} it and disenchanting it. Each disenchant is random, so one try can give more or less.`, tone: () => "up", cell: (r) => `▲ ${coins(r.profit)}` },
      { key: "price", label: crafting ? "Craft cost" : "Lowest price", hint: crafting ? HINTS["Craft cost"] : HINTS["Lowest price"], say: (r) => (crafting ? `Getting all the reagents costs ${money(r.price)}.` : `The cheapest one for sale costs ${money(r.price)}.`), p: 1, cell: (r) => coins(r.price) },
      { key: "value", label: "Expected materials", hint: HINTS["Expected materials"], say: (r) => `Disenchanting gives materials worth about ${money(r.value)} on average, after the 5% cut.`, p: 1, cell: (r) => coins(r.value) },
      { key: "roi", label: "Return", hint: HINTS["Return"], say: (r) => say.deal(r.profit, r.price, crafting ? "spend" : "pay"), p: 1, cell: (r) => (r.roi == null ? "–" : `${Math.round(r.roi * 100)}%`) },
      { key: "skill", label: "Skill needed", hint: HINTS["Skill needed"], say: (r) => (r.skill == null ? "Not known." : `You need ${number(r.skill)} Enchanting skill to disenchant it.`), p: 1, cell: (r) => (r.skill == null ? "–" : number(r.skill)) },
      { key: "material", label: "Mostly gives", hint: HINTS["Mostly gives"], say: (r) => (r.material ? `Disenchanting it mostly gives ${itemOf(r.material).n}. Hover the material for its details.` : "Not known."), left: true, p: 2, cell: (r) => materialCell(r.material) },
      crafting
        ? { key: "profession", label: "Profession", hint: HINTS["Profession"], left: true, p: 3, cell: (r) => esc(r.recipe.p) }
        : { key: "supply", label: "For sale", hint: HINTS["For sale"], say: (r) => say.supply(r.supply), p: 2, cell: (r) => number(r.supply) },
      { key: "vendor", label: "Vendor pays", hint: HINTS["Vendor pays"], say: (r) => say.vendorPays(r.item, null), p: 3, cell: (r) => coins(vendorPays(r.item)) },
    ], rows, (r) => (r.recipe ? `data-recipe="${r.recipe.s}"` : `data-item="${r.id}"`),
    state.ts ? (crafting ? "No craft is worth more disenchanted than its reagents right now." : "Nothing for sale here is worth more disenchanted right now. Try another market, or crafting it.") : "Waiting for price data.",
    crafting ? "craft" : "item", (r) => goodRow(rateReturn(r.profit, r.price)));
  }

  // ---- My scans ----
  function setScanList(ids) {
    state.scanList = ids;
    store.set("scanList", ids);
    updateCopyButton();
  }

  function updateCopyButton() {
    const changed = store.get("scanCopied", null) !== Scan.listString(state.scanList);
    $("scan-copy").textContent = changed && state.scanList.length ? "Copy list for addon (changed)" : "Copy list for addon";
    $("scan-copy").disabled = state.scanList.length === 0;
  }

  function addToScanList(id) {
    const key = Number(id);
    if (!state.scanList.includes(key)) setScanList(state.scanList.concat(key));
  }

  function removeFromScanList(id) {
    setScanList(state.scanList.filter((key) => key !== Number(id)));
  }

  function renderScanList() {
    const rows = sortRows(state.scanList.map((id) => ({ id, item: itemOf(id), row: state.prices[id] })).filter((r) => passesFilters(r.id, r.item)), state.sort.scan, {
      name: (r) => r.item.n, price: (r) => lowestOf(r.row), supply: (r) => (r.row ? r.row[2] : null), type: (r) => typeLabel(r.item), vendor: (r) => vendorPays(r.item),
    });
    drawTable([
      { key: "name", label: "Item", hint: HINTS["Item"], left: true, cell: (r) => itemCell(r.id) },
      { key: "price", label: "Lowest price", hint: HINTS["Lowest price"], say: (r) => say.lowest(r.row), cell: (r) => `${coins(lowestOf(r.row))}${r.row && !r.row[2] ? ' <span class="badge">last seen</span>' : ""}` },
      { key: "supply", label: "For sale", hint: HINTS["For sale"], say: (r) => say.supply(r.row ? r.row[2] : 0), p: 1, cell: (r) => (r.row ? number(r.row[2]) : "–") },
      { key: "vendor", label: "Vendor pays", hint: HINTS["Vendor pays"], say: (r) => say.vendorPays(r.item, r.row), p: 1, cell: (r) => coins(vendorPays(r.item)) },
      { key: "type", label: "Type", hint: HINTS["Type"], left: true, p: 2, cell: (r) => esc(typeLabel(r.item)) },
      { label: "", cell: (r) => `<button type="button" class="secondary remove" data-remove="${r.id}" aria-label="Remove ${esc(r.item.n)} from your scan list">Remove</button>` },
    ], rows, (r) => `data-item="${r.id}"`,
    state.scanList.length ? "No items here match your search or category." : "Your scan list is empty. Add an item above, and the addon will scan it every time. Open How it works to get started.", "item");
  }

  function closeSuggestions() {
    state.suggestions = []; state.activeSuggestion = -1;
    $("add-suggestions").hidden = true;
    $("add-item").setAttribute("aria-expanded", "false");
    $("add-item").removeAttribute("aria-activedescendant");
  }

  function drawSuggestions() {
    const list = $("add-suggestions");
    const input = $("add-item");
    if (!state.suggestions.length) {
      const text = input.value.trim();
      if (!text) { closeSuggestions(); return; }
      list.innerHTML = `<li class="muted" aria-disabled="true">${state.allItems ? "No items found" : "Loading items…"}</li>`;
      list.hidden = false;
      return;
    }
    list.innerHTML = state.suggestions.map((id, index) => {
      const item = itemOf(id);
      const added = state.scanList.includes(id);
      return `<li id="suggestion-${index}" role="option" data-add="${id}" aria-selected="${index === state.activeSuggestion}">${iconHtml(item)}<span class="q${item.q}">${esc(item.n)}</span>${added ? '<span class="badge added">Added</span>' : ""}</li>`;
    }).join("");
    list.hidden = false;
    input.setAttribute("aria-expanded", "true");
    if (state.activeSuggestion >= 0) {
      input.setAttribute("aria-activedescendant", `suggestion-${state.activeSuggestion}`);
      $(`suggestion-${state.activeSuggestion}`).scrollIntoView({ block: "nearest" });
    } else input.removeAttribute("aria-activedescendant");
  }

  function pickSuggestion(id) {
    const added = !state.scanList.includes(id);
    addToScanList(id);
    toast(added ? `Added ${itemOf(id).n} to your scan list.` : `${itemOf(id).n} is already on your list.`);
    $("add-item").value = "";
    closeSuggestions();
    render();
    $("add-item").focus();
  }

  async function copyScanList() {
    const text = Scan.listString(state.scanList);
    try {
      await navigator.clipboard.writeText(text);
      store.set("scanCopied", text);
      updateCopyButton();
      toast("Copied. In game, type /ahscan list, paste and press Save.");
    } catch (error) {
      window.prompt("Copy this, then in game type /ahscan list and paste it:", text);
      store.set("scanCopied", text);
      updateCopyButton();
    }
  }

  function bindScanList() {
    const input = $("add-item");
    let timer;
    input.addEventListener("input", () => {
      clearTimeout(timer);
      timer = setTimeout(() => {
        state.suggestions = state.allItems ? Scan.searchItems(state.allItems, input.value, SUGGESTIONS) : [];
        state.activeSuggestion = -1;
        drawSuggestions();
      }, SEARCH_DELAY_MS);
    });
    input.addEventListener("keydown", (event) => {
      if (event.key === "Escape") { closeSuggestions(); return; }
      const count = state.suggestions.length;
      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault();
        if (!count) return;
        const step = event.key === "ArrowDown" ? 1 : -1;
        state.activeSuggestion = (state.activeSuggestion + step + count) % count;
        drawSuggestions();
      } else if (event.key === "Enter" && count) {
        event.preventDefault();
        pickSuggestion(state.suggestions[Math.max(0, state.activeSuggestion)]);
      }
    });
    input.addEventListener("blur", () => setTimeout(closeSuggestions, 150));
    // Pointer down, so the choice lands before the input loses focus.
    $("add-suggestions").addEventListener("pointerdown", (event) => {
      const option = event.target.closest("[data-add]");
      if (!option) return;
      event.preventDefault();
      pickSuggestion(Number(option.dataset.add));
    });
    $("scan-copy").addEventListener("click", copyScanList);
    $("detail-scan").addEventListener("click", () => {
      const key = Number(state.detailId);
      if (state.scanList.includes(key)) removeFromScanList(key);
      else addToScanList(key);
      updateDetailButtons();
      render();
    });
  }

  // ---- Item tooltip ----
  // Shows at once from local data, then fills in the game's tooltip from Wowhead.
  const TIP_DELAY_MS = 120;
  const TOP_ITEMS = 100;
  const TIP_GAP = 14;
  const gameInfo = new Map(); // Item ID to a promise of clean HTML, or of null if it failed.
  const tip = { id: null, timer: null, x: 0, y: 0 };

  function loadGameInfo(id) {
    if (!gameInfo.has(id)) {
      gameInfo.set(id, fetch(Tooltip.address(id))
        .then((response) => (response.ok ? response.json() : Promise.reject(new Error(response.status))))
        .then((data) => Tooltip.sanitize(data.tooltip) || null)
        .catch(() => null));
    }
    return gameInfo.get(id);
  }

  function localInfo(item) {
    const lines = [`<b class="q${item.q}">${esc(item.n)}</b>`];
    if (item.il) lines.push(`<span class="q">Item Level ${Number(item.il)}</span>`);
    if (item.bop) lines.push("Binds when picked up");
    if (item.cl !== undefined) lines.push(esc(typeLabel(item)));
    if (item.rl) lines.push(`Requires Level ${Number(item.rl)}`);
    return lines.join("<br>");
  }

  function marketInfo(id) {
    const row = state.prices[id];
    const lines = [];
    if (row) {
      lines.push(row[2] > 0 ? `Lowest price ${coins(lowestOf(row))} · Market ${coins(row[1])} · ${number(row[2])} for sale` : `None for sale. Last seen at ${coins(row[1])}`);
    } else lines.push("No price seen yet");
    const item = itemOf(id);
    if (vendorPays(item)) lines.push(`Vendor pays ${coins(vendorPays(item))}`);
    if (vendorCharges(item)) lines.push(`Vendor sells at ${coins(vendorCharges(item))}`);
    const crafted = state.catalog.recipes.filter((r) => r.i === Number(id));
    if (crafted.length) lines.push("Crafted with " + [...new Set(crafted.map((r) => `${esc(r.p)} (skill ${r.sk})`))].join(", "));
    const used = state.catalog.recipes.filter((r) => r.r.some((part) => part[0] === Number(id))).length;
    if (used) lines.push(`Used in ${number(used)} recipe${used > 1 ? "s" : ""}`);
    return lines.join("<br>");
  }

  function placeTip() {
    const box = $("tip");
    const { width, height } = box.getBoundingClientRect();
    const fitsRight = tip.x + TIP_GAP + width <= innerWidth - 8;
    const fitsBelow = tip.y + TIP_GAP + height <= innerHeight - 8;
    const left = fitsRight ? tip.x + TIP_GAP : tip.x - TIP_GAP - width;
    const top = fitsBelow ? tip.y + TIP_GAP : tip.y - TIP_GAP - height;
    box.style.left = `${Math.max(8, Math.min(left, innerWidth - width - 8))}px`;
    box.style.top = `${Math.max(8, Math.min(top, innerHeight - height - 8))}px`;
  }

  function showTip(id) {
    const box = $("tip");
    const item = itemOf(id);
    tip.id = id;
    // A modal dialog sits above everything else, so the tooltip has to live inside it.
    const parent = $("detail").open ? $("detail") : document.body;
    if (box.parentElement !== parent) parent.appendChild(box);
    box.innerHTML = `${iconHtml(item)}<div class="tip-text"><div class="tip-game">${localInfo(item)}</div><div class="tip-market">${marketInfo(id)}</div></div>`;
    box.hidden = false;
    placeTip();
    loadGameInfo(id).then((html) => {
      if (tip.id !== id || box.hidden) return;
      if (html) box.querySelector(".tip-game").innerHTML = html;
      else box.querySelector(".tip-game").insertAdjacentHTML("beforeend", '<p class="muted">More details are unavailable right now.</p>');
      placeTip();
    });
  }

  function showHint(text) {
    const box = $("tip");
    tip.id = "hint";
    const parent = $("detail").open ? $("detail") : document.body;
    if (box.parentElement !== parent) parent.appendChild(box);
    box.innerHTML = `<div class="tip-text">${esc(text)}</div>`;
    box.hidden = false;
    placeTip();
  }

  function hideTip() {
    clearTimeout(tip.timer);
    tip.id = null;
    tip.hintFor = null;
    $("tip").hidden = true;
  }

  // Item details show only over an item's icon or name, not anywhere in its row.
  function tipTarget(element) {
    if (!element.closest || !element.closest(".icon, .item-cell .name, .item-cell [class^='q']")) return null;
    const holder = element.closest("[data-item],[data-recipe]");
    if (!holder) return null;
    if (holder.dataset.item) return holder.dataset.item;
    const recipe = state.catalog.recipes.find((r) => r.s === Number(holder.dataset.recipe));
    return recipe ? String(recipe.i) : null;
  }

  function bindTip() {
    document.addEventListener("pointerover", (event) => {
      const hinted = event.target.closest && event.target.closest("[data-hint]");
      if (hinted) {
        if (tip.hintFor === hinted) return;
        hideTip();
        tip.hintFor = hinted;
        const rect = hinted.getBoundingClientRect();
        tip.x = rect.left; tip.y = rect.bottom;
        showHint(hinted.dataset.hint);
        return;
      }
      if (event.pointerType === "touch") { if (tip.id === "hint") hideTip(); return; } // Tapping opens the item details instead.
      tip.x = event.clientX; tip.y = event.clientY;
      const id = tipTarget(event.target);
      if (id) {
        if (id === tip.id) return;
        hideTip();
        tip.timer = setTimeout(() => showTip(id), TIP_DELAY_MS);
        return;
      }
      const cell = event.target.closest && event.target.closest("td[data-cell]");
      if (cell && cell === tip.hintFor) return;
      hideTip();
      if (cell) {
        tip.hintFor = cell;
        tip.timer = setTimeout(() => showHint(cell.dataset.cell), TIP_DELAY_MS);
      }
    });
    document.addEventListener("pointermove", (event) => {
      if (event.pointerType === "touch") return;
      tip.x = event.clientX; tip.y = event.clientY;
      if (tip.id) placeTip();
    });
    document.addEventListener("focusin", (event) => {
      if (event.target.matches("[data-hint]")) {
        const rect = event.target.getBoundingClientRect();
        tip.x = rect.left; tip.y = rect.bottom;
        hideTip();
        showHint(event.target.dataset.hint);
        return;
      }
      if (!event.target.matches(".name")) return;
      const id = tipTarget(event.target);
      if (!id) return;
      const rect = event.target.getBoundingClientRect();
      tip.x = rect.left; tip.y = rect.bottom;
      hideTip();
      showTip(id);
    });
    document.addEventListener("focusout", (event) => { if (event.target.matches(".name, [data-hint]")) hideTip(); });
    document.addEventListener("keydown", (event) => { if (event.key === "Escape") hideTip(); });
    // Tabbing to a row can scroll the table, so a keyboard tooltip moves with its row.
    document.addEventListener("scroll", () => {
      const focused = document.activeElement;
      if (!tip.id || !focused || !focused.matches(".name") || tipTarget(focused) !== tip.id) { hideTip(); return; }
      const rect = focused.getBoundingClientRect();
      tip.x = rect.left; tip.y = rect.bottom;
      placeTip();
    }, true);
    window.addEventListener("blur", hideTip);
  }

  // ---- Item detail ----
  function statBox(label, html) {
    return `<div class="stat"><b>${html}</b><span class="label">${esc(label)}</span></div>`;
  }

  function lineChart(times, values, daily) {
    const points = times.map((t, i) => ({ t, v: values[i] })).filter((p) => p.v != null);
    if (points.length < 2) {
      const none = document.createElement("p");
      none.className = "muted";
      none.textContent = "Not enough history yet. It builds up with each scan.";
      return none;
    }
    const W = 700, H = 240, L = 62, R = 14, T = 12, B = 26;
    const vs = points.map((p) => p.v);
    let lo = Math.min(...vs), hi = Math.max(...vs);
    if (lo === hi) { lo *= 0.9; hi = hi * 1.1 || 1; }
    const pad = (hi - lo) * 0.08; lo = Math.max(0, lo - pad); hi += pad;
    const t0 = points[0].t, t1 = points[points.length - 1].t;
    const x = (t) => L + ((t - t0) / (t1 - t0 || 1)) * (W - L - R);
    const y = (v) => T + (1 - (v - lo) / (hi - lo)) * (H - T - B);
    const date = (t) => new Date(t * 1000).toLocaleDateString(undefined, { month: "short", day: "numeric" });
    const stamp = (t) => new Date(t * 1000).toLocaleString(undefined, daily ? { month: "short", day: "numeric" } : { month: "short", day: "numeric", hour: "numeric" });
    const grid = [0, 0.5, 1].map((f) => {
      const v = lo + (hi - lo) * f;
      return `<line x1="${L}" x2="${W - R}" y1="${y(v)}" y2="${y(v)}" stroke="var(--grid)"/><text x="${L - 8}" y="${y(v) + 4}" text-anchor="end">${esc(money(v))}</text>`;
    }).join("");
    const path = points.map((p, i) => `${i ? "L" : "M"}${x(p.t).toFixed(1)} ${y(p.v).toFixed(1)}`).join("");
    const box = document.createElement("div");
    box.className = "chart";
    box.innerHTML = `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Lowest price from ${esc(date(t0))} to ${esc(date(t1))}, between ${esc(money(Math.min(...vs)))} and ${esc(money(Math.max(...vs)))}">${grid}
      <text x="${L}" y="${H - 7}">${esc(date(t0))}</text><text x="${W - R}" y="${H - 7}" text-anchor="end">${esc(date(t1))}</text>
      <path d="${path}" fill="none" stroke="var(--series)" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>
      <line class="cross" x1="0" x2="0" y1="${T}" y2="${H - B}" stroke="var(--muted)" visibility="hidden"/>
      <circle class="dot" r="4" fill="var(--series)" stroke="var(--surface)" stroke-width="2" visibility="hidden"/>
      <rect x="${L}" y="${T}" width="${W - L - R}" height="${H - T - B}" fill="transparent"/></svg><div class="tip" hidden></div>`;
    const root = box.querySelector("svg"), cross = box.querySelector(".cross"), dot = box.querySelector(".dot"), tip = box.querySelector(".tip");
    root.addEventListener("pointermove", (event) => {
      const rect = root.getBoundingClientRect();
      const px = ((event.clientX - rect.left) / rect.width) * W;
      let best = points[0];
      for (const p of points) if (Math.abs(x(p.t) - px) < Math.abs(x(best.t) - px)) best = p;
      cross.setAttribute("x1", x(best.t)); cross.setAttribute("x2", x(best.t)); cross.setAttribute("visibility", "visible");
      dot.setAttribute("cx", x(best.t)); dot.setAttribute("cy", y(best.v)); dot.setAttribute("visibility", "visible");
      tip.hidden = false;
      tip.textContent = `${stamp(best.t)}: ${money(best.v)}`;
      tip.style.left = Math.min(rect.width - 70, Math.max(70, (x(best.t) / W) * rect.width)) + "px";
      tip.style.top = (y(best.v) / H) * rect.height + "px";
    });
    root.addEventListener("pointerleave", () => { cross.setAttribute("visibility", "hidden"); dot.setAttribute("visibility", "hidden"); tip.hidden = true; });
    return box;
  }

  async function loadHistory(id, holder) {
    holder.textContent = "Loading history…";
    let history;
    try {
      if (!state.history || state.history.house !== state.house) {
        state.history = { house: state.house, data: await getJson(`data/hist${encodeURIComponent(state.house)}.json`) };
      }
      history = state.history.data;
    } catch (e) {
      holder.textContent = "No history yet.";
      return;
    }
    holder.innerHTML = '<div class="range"><button type="button" class="secondary" data-range="hours">Last 7 days, hourly</button><button type="button" class="secondary" data-range="days">Last 60 days, daily</button></div><div class="plot"></div>';
    const show = (range) => {
      const section = range === "days" ? history.days : history.hours;
      holder.querySelector(".plot").replaceChildren(lineChart(section.t, section.i[id] || [], range === "days"));
      holder.querySelectorAll("[data-range]").forEach((b) => {
        const on = b.dataset.range === range;
        b.classList.toggle("on", on);
        b.classList.toggle("secondary", !on);
        b.setAttribute("aria-pressed", on);
      });
    };
    holder.querySelectorAll("[data-range]").forEach((b) => b.addEventListener("click", () => show(b.dataset.range)));
    const hourly = (history.hours.i[id] || []).filter((v) => v != null).length;
    show(hourly >= 2 ? "hours" : "days");
  }

  function reagentTable(parts) {
    const rows = parts.map((p) => `<tr><td><div class="item-cell" data-item="${p.id}">${iconHtml(itemOf(p.id))}<span class="q${itemOf(p.id).q}">${esc(itemOf(p.id).n)}</span></div></td><td>${p.count}</td><td>${coins(p.cost)}</td><td>${p.cost == null ? "–" : coins(p.cost * p.count)}</td><td class="left">${SOURCE[p.source]}</td></tr>`).join("");
    return `<div class="table-wrap"><table class="detail-table"><thead><tr><th scope="col">Reagent</th><th scope="col">Needed</th><th scope="col">Each</th><th scope="col">Total</th><th scope="col" class="left">Cheapest from</th></tr></thead><tbody>${rows}</tbody></table></div>`;
  }

  function disenchantTable(item) {
    const outcomes = disenchantOutcomes(item);
    if (!outcomes) return "";
    const rows = outcomes.filter((o) => o.chance > 0).map((o) => {
      const row = state.prices[o.id];
      const material = itemOf(o.id);
      return `<tr><td><div class="item-cell" data-item="${o.id}">${iconHtml(material)}<span class="q${material.q}">${esc(material.n)}</span></div></td><td>${Math.round(o.chance * 1000) / 10}%</td><td>${o.min === o.max ? o.min : o.min + "–" + o.max}</td><td>${coins(row && row[2] > 0 ? row[1] : null)}</td></tr>`;
    }).join("");
    return `<h3>Disenchant results (expected)</h3><div class="table-wrap"><table class="detail-table"><thead><tr><th scope="col">Material</th><th scope="col">Chance</th><th scope="col">Amount</th><th scope="col">Price each</th></tr></thead><tbody>${rows}</tbody></table></div>`;
  }

  function updateDetailButtons() {
    const onList = state.scanList.includes(Number(state.detailId));
    $("detail-scan").textContent = onList ? "On my scan list" : "Add to scan list";
    $("detail-scan").setAttribute("aria-pressed", onList);
    updateDetailFavorite();
  }

  function updateDetailFavorite() {
    const on = state.favorites.has(Number(state.detailId));
    const button = $("detail-favorite");
    button.textContent = on ? "★ Favorite" : "☆ Add to favorites";
    button.setAttribute("aria-pressed", on);
  }

  function openItem(id, recipeSpell) {
    const item = itemOf(id);
    const row = state.prices[id];
    state.detailId = id;
    $("detail-title").innerHTML = `${iconHtml(item)}<span class="q${item.q}">${esc(item.n)}</span>`;
    updateDetailButtons();
    const stats = [
      statBox("Lowest price", coins(lowestOf(row))), statBox("Market", coins(row ? row[1] : null)), statBox("Previous update", coins(row ? row[3] : null)),
      statBox("24 hour average", coins(row ? row[4] : null)), statBox("7 day average", coins(row ? row[5] : null)),
      statBox("For sale", row ? number(row[2]) : "–"), statBox("Vendor pays", coins(vendorPays(item))),
      ...(vendorCharges(item) ? [statBox("Vendor sells at", coins(vendorCharges(item)))] : []),
    ].join("");
    state.rows = state.rows || craftRows(state.catalog, state.prices);
    const crafts = state.rows.filter((r) => r.recipe.i === Number(id));
    if (recipeSpell) crafts.sort((a, b) => (b.recipe.s === recipeSpell) - (a.recipe.s === recipeSpell));
    const craftHtml = crafts.map((r) => {
      const options = r.options.map((o) => `${esc(o.kind)}: ${coins(o.each * r.recipe.c)}`).join(" · ") || "No selling price known";
      const buyCost = row ? row[1] * r.recipe.c : null;
      const buy = r.cost != null && r.supply > 0 && buyCost != null && buyCost < r.cost ? `<p class="muted note">Buying it costs ${coins(buyCost)}, less than crafting it.</p>` : "";
      return `<h3>${esc(r.recipe.p)} recipe, skill ${r.recipe.sk}${r.recipe.c > 1 ? `, makes ${r.recipe.c}` : ""}</h3>
        ${reagentTable(r.parts)}
        <p class="note" style="margin-top:8px">Cost ${coins(r.cost)} · ${options} · <b>Profit ${coins(r.profit)}</b></p>${buy}`;
    }).join("");
    const usedIn = state.catalog.recipes.filter((r) => r.r.some((p) => p[0] === Number(id)));
    const usedHtml = usedIn.length ? `<h3>Used in ${usedIn.length} recipe${usedIn.length > 1 ? "s" : ""}</h3><p class="muted note">${usedIn.slice(0, 12).map((r) => esc(r.n)).join(", ")}${usedIn.length > 12 ? " and more" : ""}</p>` : "";
    hideTip();
    $("detail-body").innerHTML = `<div class="tip-game detail-game" id="detail-game">${localInfo(item)}</div><div class="stats">${stats}</div><div id="history"></div>${craftHtml}${disenchantTable(item)}${usedHtml}
      <p class="note" style="margin-top:12px"><a href="https://forever.warcraftdb.com/data/item/${Number(id)}" target="_blank" rel="noopener">Open in Warcraft DB</a></p>`;
    $("detail").showModal();
    loadGameInfo(id).then((html) => {
      const holder = $("detail-game");
      if (html && holder && state.detailId === id) holder.innerHTML = html;
    });
    loadHistory(String(id), $("history"));
  }

  // ---- Favorites ----
  function toggleFavorite(id) {
    const key = Number(id);
    if (state.favorites.has(key)) state.favorites.delete(key);
    else state.favorites.add(key);
    store.set("favorites", [...state.favorites]);
  }

  // ---- Categories ----
  // Counting every item in every category is the slowest part of drawing the page, so it's
  // only redone when something it depends on changes.
  let countsCache = { key: null, counts: null };
  function categoryCounts() {
    const key = [state.house, state.ts, state.source, state.favorites.size, state.scanList.length, Boolean(state.allItems), state.mostPosted.size].join("|");
    if (countsCache.key === key) return countsCache.counts;
    const counts = new Map();
    const add = (key) => counts.set(key, (counts.get(key) || 0) + 1);
    const allGroups = groups(state.professions);
    for (const id of allItemIds()) {
      const row = state.prices[id];
      if (!(row && row[2] > 0)) continue;
      const item = itemOf(id);
      if (state.source !== "all" && sourceOf(id, item, context()) !== state.source) continue;
      add("all");
      for (const group of allGroups) {
        for (const category of group.categories) {
          if (matches(category.id, id, item, context())) add(category.id);
        }
      }
    }
    counts.set("favorites", state.favorites.size);
    counts.set("scan-list", state.scanList.length);
    counts.set("most-posted", state.mostPosted.size);
    counts.set("most-bought", state.mostBought.size);
    countsCache = { key, counts };
    return counts;
  }

  function renderCategories() {
    const counts = categoryCounts();
    const button = (id, label) => `<li><button type="button" class="cat" data-category="${esc(id)}" aria-current="${state.category === id}"><span>${esc(label)}</span><span>${number(counts.get(id) || 0)}</span></button></li>`;
    const select = $("category-select");
    let html = `<ul>${button("all", "All items")}${button("favorites", "★ Favorites")}${button("scan-list", "My scan list")}</ul>`;
    let options = '<option value="all">All items</option><option value="favorites">★ Favorites</option><option value="scan-list">My scan list</option>';
    for (const group of groups(state.professions)) {
      // A group opens by itself when the chosen category is inside it.
      const holdsCurrent = group.categories.some((c) => c.id === state.category);
      const open = holdsCurrent || !state.collapsed[group.label];
      const listId = `group-${group.label.toLowerCase().replace(/[^a-z]+/g, "-")}`;
      html += `<button type="button" class="group-toggle" data-group="${esc(group.label)}" aria-expanded="${open}" aria-controls="${listId}">${esc(group.label)}</button>`
        + `<ul id="${listId}"${open ? "" : " hidden"}>${group.categories.map((c) => button(c.id, c.label)).join("")}</ul>`;
      options += `<optgroup label="${esc(group.label)}">${group.categories.map((c) => `<option value="${esc(c.id)}">${esc(c.label)}</option>`).join("")}</optgroup>`;
    }
    const scroll = $("categories").parentElement.scrollTop;
    $("categories").innerHTML = html;
    $("categories").parentElement.scrollTop = scroll;
    select.innerHTML = options;
    select.value = state.category;
  }

  // ---- Page ----
  function writeHash() {
    const params = new URLSearchParams();
    if (state.category !== "all") params.set("category", state.category);
    if (state.search) params.set("q", state.search);
    const query = params.toString();
    history.replaceState(null, "", `#${state.tab}${query ? "?" + query : ""}`);
  }

  function readHash() {
    const [tab, query] = location.hash.slice(1).split("?");
    const params = new URLSearchParams(query || "");
    state.tab = TABS.includes(tab) ? tab : store.get("tab", "prices");
    if (!TABS.includes(state.tab)) state.tab = "prices";
    const category = params.get("category") || "all";
    state.category = isKnown(category, state.professions) ? category : "all";
    state.search = (params.get("q") || "").toLowerCase();
    $("search").value = state.search;
  }

  const LEGENDS = {
    prices: () => `${badge("cheap")} lower than its usual price this week, a good time to buy · ${badge("pricey")} higher than usual, a good time to sell · ▲ ▼ show how much the price moved. Hover a column title to see what it means.`,
    alerts: () => `Items whose price moved a lot. ${badge("cheaper")} is a chance to buy, and ${badge("pricier")} is a chance to sell. Hover a column title to see what it means.`,
    profit: () => `${badge("good")} pays back at least 20% more than you spend · ${badge("fair")} small profit · ${badge("poor")} loses money. Profit is per craft, after the 5% auction cut.`,
    deals: () => `Items worth more as enchanting materials than they cost. ${badge("good")} expected to return at least 20% more than you spend · ${badge("fair")} small expected profit. Results vary item by item.`,
    scan: () => "Items your addon scans every time. Add or remove items here, then copy the list into the game. Open How it works for the steps.",
  };

  function render() {
    document.querySelectorAll(".tabs button").forEach((b) => {
      const on = b.dataset.tab === state.tab;
      b.setAttribute("aria-selected", on);
      b.tabIndex = on ? 0 : -1;
    });
    TABS.forEach((name) => { $("tab-" + name).hidden = name !== state.tab; });
    $("results").setAttribute("aria-labelledby", "tabbtn-" + state.tab);
    $("legend").innerHTML = LEGENDS[state.tab]();
    $("table").parentElement.setAttribute("aria-busy", state.loading ? "true" : "false");
    // The add box does the searching on this tab, and all its controls stay visible.
    $("search").hidden = state.tab === "scan";
    $("source-filter").hidden = state.tab === "profit"; // Every recipe is crafted.
    $("filters-toggle").classList.toggle("not-needed", state.tab === "scan");
    hideTip();
    updateAlertBadge();
    renderCategories();
    ({ prices: renderPrices, alerts: renderAlerts, profit: renderProfit, deals: renderDeals, scan: renderScanList })[state.tab]();
    writeHash();
  }

  function resetAndRender() {
    state.limit = PAGE;
    render();
    $("table").parentElement.scrollTop = 0;
  }

  function timeAgo(seconds) {
    const minutes = Math.round((Date.now() / 1000 - seconds) / 60);
    if (minutes < 1) return "just now";
    if (minutes < 60) return `${minutes} min ago`;
    const hours = Math.round(minutes / 60);
    return hours < 48 ? `${hours} hour${hours > 1 ? "s" : ""} ago` : `${Math.round(hours / 24)} days ago`;
  }

  // Published markets, plus any you scanned that nobody has published yet.
  function allHouses() {
    const houses = state.meta ? state.meta.houses.slice() : [];
    for (const id of Object.keys(state.scans)) {
      if (!houses.some((h) => h.id === id)) {
        const [, ruleset = "", faction = ""] = id.split(".");
        const title = (word) => word.charAt(0).toUpperCase() + word.slice(1);
        houses.push({ id, rulesetName: ruleset === "pvp" ? "PvP" : ruleset === "rp" ? "Roleplay" : title(ruleset), name: title(faction), scannedAt: 0 });
      }
    }
    return houses.map((h) => {
      const scan = state.scans[h.id];
      return scan && scan.at > (h.scannedAt || 0) ? { ...h, scannedAt: scan.at } : h;
    });
  }

  const houseLabel = (h) => `${h.rulesetName} ${h.name} · ${h.scannedAt ? timeAgo(h.scannedAt).replace(" ago", "") : "no scans"}`;

  function showUpdated() {
    if (state.meta) {
      [...$("house").options].forEach((option) => {
        const found = allHouses().find((h) => h.id === option.value);
        if (found) option.textContent = houseLabel(found);
      });
    }
    const banner = $("banner");
    if (state.ts && Date.now() / 1000 - state.ts > STALE_SECONDS) {
      banner.hidden = false;
      banner.textContent = `This auction house hasn't been updated for ${timeAgo(state.ts).replace(" ago", "")}, so these prices may be out of date.`;
    } else if (state.ts) {
      banner.hidden = true;
    }
  }

  function toast(text) {
    const box = $("toast");
    box.textContent = text;
    box.hidden = false;
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => { box.hidden = true; }, 8000);
  }

  function notifyChanges() {
    const key = `seen.${state.house}`;
    const seen = store.get(key, null);
    if (seen === state.ts) return;
    store.set(key, state.ts);
    if (seen == null) return; // First visit: nothing has changed since you last looked.
    const alerts = allAlerts();
    if (!alerts.length) return;
    const lines = alerts.slice(0, 3).map((a) => `${itemOf(a.id).n} ${a.amount > 0 ? "+" : "-"}${Math.abs(a.percent).toFixed(0)}% (${money(Math.abs(a.amount))})`);
    const more = alerts.length > 3 ? ` and ${alerts.length - 3} more` : "";
    const title = `${alerts.length} big price change${alerts.length > 1 ? "s" : ""}`;
    toast(`${title}: ${lines.join(", ")}${more}`);
    if ("Notification" in window && Notification.permission === "granted" && store.get("notify", false)) {
      new Notification(title, { body: lines.join("\n") + more, tag: "forever-prices" });
    }
  }

  function updateNotifyButton() {
    const button = $("notify");
    if (!("Notification" in window)) { button.hidden = true; return; }
    const on = Notification.permission === "granted" && store.get("notify", false);
    const text = on ? "Notifications on. Select to turn off." : "Turn on notifications";
    button.title = text;
    button.setAttribute("aria-label", text);
    button.classList.toggle("on", on);
    button.classList.toggle("secondary", !on);
    button.setAttribute("aria-pressed", on);
  }

  function activeScan() {
    const scan = state.scans[state.house];
    return scan && scan.at > (state.fileTs || 0) ? scan : null;
  }

  // Everything that reads prices reads state.prices: published data, plus a newer scan if there is one.
  function refreshPrices() {
    const scan = activeScan();
    state.prices = scan ? Scan.applyScan(state.published, Scan.decodeRows(scan.data)) : state.published;
    state.ts = scan ? scan.at : state.fileTs;
    state.mostPosted = Scan.topBy(state.prices, 2, TOP_ITEMS);
    state.mostBought = Scan.topBy(state.prices, 6, TOP_ITEMS);
    state.rows = null; state.deals = null; state.craftDeals = null;
    const status = $("scan-status");
    const saved = state.scans[state.house];
    status.hidden = !saved;
    $("scan-remove").hidden = !saved;
    if (saved) {
      const count = Object.keys(Scan.decodeRows(saved.data)).length;
      status.textContent = `${scan ? "Your scan" : "Your older scan, not in use"}: ${number(count)} item${count === 1 ? "" : "s"}, ${timeAgo(saved.at)}${saved.complete ? "" : " (partial)"} ·`;
    }
    $("scan-load").textContent = state.scanHandle ? "Refresh scan" : "Load scan";
  }

  function usePrices(file) {
    state.published = file.items || {};
    state.fileTs = file.ts || null;
    state.history = null;
    refreshPrices();
  }

  function useScanText(text) {
    const scans = Scan.parseSavedFile(text);
    const markets = Object.keys(scans);
    if (!markets.length) {
      toast("No scan found in that file. Pick DufforthAHScanner.lua after scanning and typing /reload in game.");
      return;
    }
    state.scans = { ...state.scans, ...scans };
    store.set("scans", state.scans);
    const known = allHouses().some((h) => h.id === state.house);
    const target = scans[state.house] ? state.house : markets[0];
    fillHouses();
    $("house").value = known ? target : markets[0];
    loadHouse($("house").value).then(() => {
      const count = Object.keys(Scan.decodeRows(state.scans[state.house].data)).length;
      toast(`Loaded your scan of ${number(count)} item${count === 1 ? "" : "s"}.`);
    });
  }

  async function loadScan() {
    if (state.scanHandle) {
      const file = await state.scanHandle.getFile();
      useScanText(await file.text());
    } else if (window.showOpenFilePicker) {
      try {
        const [handle] = await window.showOpenFilePicker({ types: [{ description: "Addon data", accept: { "text/plain": [".lua"] } }] });
        state.scanHandle = handle;
        useScanText(await (await handle.getFile()).text());
      } catch (error) {
        if (error.name !== "AbortError") toast("That file could not be opened. Try again.");
      }
    } else {
      $("scan-file").click();
    }
  }

  async function loadHouse(id) {
    state.house = id;
    store.set("house", id);
    let file = {};
    try { file = await getJson(`data/h${encodeURIComponent(id)}.json`); } catch (e) { /* no data for this market yet */ }
    usePrices(file);
    state.limit = PAGE;
    showUpdated();
    render();
  }

  function fillHouses() {
    const select = $("house");
    const houses = allHouses().sort((a, b) => (b.scannedAt || 0) - (a.scannedAt || 0));
    select.innerHTML = houses.map((h) => `<option value="${esc(h.id)}">${esc(houseLabel(h))}</option>`).join("");
    const saved = store.get("house", null);
    const pick = houses.find((h) => h.id === saved) || houses[0];
    if (!pick) throw new Error("no markets");
    select.value = pick.id;
    return pick.id;
  }

  async function poll() {
    try {
      const early = state.metaEarly;
      state.metaEarly = null;
      const meta = (early && await early) || await getJson("data/meta.json");
      const first = !state.meta;
      state.meta = meta;
      if (first) await loadHouse(fillHouses());
      else {
        const file = await getJson(`data/h${encodeURIComponent(state.house)}.json`);
        if (file.ts !== state.fileTs) { usePrices(file); render(); }
      }
      notifyChanges();
      state.loading = false;
    } catch (e) {
      state.loading = false;
      if (!state.meta) {
        $("banner").hidden = false;
        $("banner").textContent = "No prices yet. They appear after the first successful update.";
        render();
      }
    }
    showUpdated();
  }

  function setCategory(id) {
    state.category = id;
    // These lists only make sense ranked, so they open sorted by what they measure.
    if (id === "most-posted") state.sort.prices = { key: "supply", dir: -1 };
    if (id === "most-bought") state.sort.prices = { key: "bought", dir: -1 };
    resetAndRender();
  }

  function bind() {
    const tabs = [...document.querySelectorAll(".tabs button")];
    tabs.forEach((button, index) => {
      button.addEventListener("click", () => { state.tab = button.dataset.tab; store.set("tab", state.tab); resetAndRender(); });
      button.addEventListener("keydown", (event) => {
        const step = { ArrowRight: 1, ArrowLeft: -1 }[event.key];
        if (!step) return;
        event.preventDefault();
        const next = tabs[(index + step + tabs.length) % tabs.length];
        next.click();
        next.focus();
      });
    });

    $("categories").addEventListener("click", (event) => {
      const toggle = event.target.closest("[data-group]");
      if (toggle) {
        const group = toggle.dataset.group;
        state.collapsed[group] = toggle.getAttribute("aria-expanded") === "true";
        store.set("collapsed", state.collapsed);
        renderCategories();
        $("categories").querySelector(`[data-group="${CSS.escape(group)}"]`).focus();
        return;
      }
      const button = event.target.closest("[data-category]");
      if (!button) return;
      setCategory(button.dataset.category);
      $("categories").querySelector(`[data-category="${CSS.escape(state.category)}"]`).focus();
    });
    $("category-select").addEventListener("change", (event) => setCategory(event.target.value));
    $("source-filter").addEventListener("change", (event) => { state.source = event.target.value; resetAndRender(); });

    let searchTimer;
    $("search").addEventListener("input", (event) => {
      clearTimeout(searchTimer);
      searchTimer = setTimeout(() => { state.search = event.target.value.trim().toLowerCase(); resetAndRender(); }, SEARCH_DELAY_MS);
    });
    $("clear-filters").addEventListener("click", () => {
      state.search = ""; $("search").value = ""; state.category = "all";
      state.source = "all"; $("source-filter").value = "all";
      resetAndRender();
      $("search").focus();
    });

    $("house").addEventListener("change", (event) => loadHouse(event.target.value).then(notifyChanges));
    ["price-basis", "price-listed", "profit-only", "profit-supply"].forEach((id) => $(id).addEventListener("input", resetAndRender));
    $("scan-load").addEventListener("click", () => {
      loadScan().catch(() => { state.scanHandle = null; toast("That file could not be read. Press Load scan and pick it again."); refreshPrices(); });
    });
    $("scan-file").addEventListener("change", async (event) => {
      const file = event.target.files[0];
      if (file) useScanText(await file.text());
      event.target.value = "";
    });
    $("scan-remove").addEventListener("click", () => {
      delete state.scans[state.house];
      store.set("scans", state.scans);
      state.scanHandle = null;
      if (!state.meta.houses.some((h) => h.id === state.house)) {
        loadHouse(fillHouses());
      } else {
        fillHouses();
        $("house").value = state.house;
        refreshPrices();
        render();
      }
      toast("Scan removed. Showing published prices.");
    });
    [["de-mode", "mode"], ["de-skill", "skill"], ["de-supply", "supply"]].forEach(([id, key]) => {
      const input = $(id);
      input.value = state.de[key];
      input.addEventListener("input", () => {
        state.de[key] = input.value;
        store.set("de", state.de);
        resetAndRender();
      });
    });
    $("filters-toggle").addEventListener("click", (event) => {
      const open = document.querySelector(".toolbar").classList.toggle("filters-open");
      event.currentTarget.setAttribute("aria-expanded", open);
    });
    $("more").addEventListener("click", () => { state.limit += PAGE; render(); });

    [["alert-percent", "percent"], ["alert-amount", "amount"], ["alert-supply", "supply"], ["alert-basis", "basis"]].forEach(([id, key]) => {
      const input = $(id);
      input.value = state.alert[key];
      input.addEventListener("input", () => {
        state.alert[key] = key === "basis" ? input.value : Math.max(0, Number(input.value) || 0);
        store.set("alert", state.alert);
        render();
      });
    });
    $("alert-favorites").checked = state.alert.favorites;
    $("alert-favorites").addEventListener("input", (event) => {
      state.alert.favorites = event.target.checked;
      store.set("alert", state.alert);
      render();
    });

    $("table").addEventListener("click", (event) => {
      const remove = event.target.closest("[data-remove]");
      if (remove) {
        const name = itemOf(remove.dataset.remove).n;
        removeFromScanList(remove.dataset.remove);
        render();
        toast(`Removed ${name} from your scan list.`);
        return;
      }
      const star = event.target.closest("[data-star]");
      if (star) {
        toggleFavorite(star.dataset.star);
        const id = star.dataset.star;
        render();
        const again = $("table").querySelector(`[data-star="${id}"]`);
        (again || $("search")).focus();
        return;
      }
      const head = event.target.closest("th[data-sort]");
      if (head) { changeSort(head.dataset.sort); return; }
      const row = event.target.closest("tr.row");
      if (!row) return;
      if (row.dataset.recipe) {
        const recipe = state.catalog.recipes.find((r) => r.s === Number(row.dataset.recipe));
        openItem(String(recipe.i), recipe.s);
      } else openItem(row.dataset.item);
    });
    $("table").addEventListener("keydown", (event) => {
      const head = event.target.closest("th[data-sort]");
      if (head && (event.key === "Enter" || event.key === " ")) {
        event.preventDefault();
        const key = head.dataset.sort;
        changeSort(key);
        $("table").querySelector(`th[data-sort="${key}"]`).focus();
      }
    });
    // A missing icon tries the backup server, then leaves an empty square, never a broken image.
    document.addEventListener("error", (event) => {
      const image = event.target;
      if (!image.matches || !image.matches("img.icon")) return;
      if (image.dataset.backup) {
        image.src = image.dataset.backup;
        delete image.dataset.backup;
      } else image.removeAttribute("src");
    }, true);

    $("detail-close").addEventListener("click", () => $("detail").close());
    $("detail").addEventListener("click", (event) => { if (event.target === $("detail")) $("detail").close(); });
    $("detail-favorite").addEventListener("click", () => { toggleFavorite(state.detailId); updateDetailFavorite(); render(); });
    $("toast").addEventListener("click", () => { $("toast").hidden = true; state.tab = "alerts"; resetAndRender(); });

    $("notify").addEventListener("click", async () => {
      if (Notification.permission === "default") await Notification.requestPermission();
      if (Notification.permission === "granted") store.set("notify", !store.get("notify", false));
      else toast("Notifications are blocked. Allow them for this site in your browser settings.");
      updateNotifyButton();
    });
    window.addEventListener("hashchange", () => { readHash(); state.limit = PAGE; render(); });
  }

  function changeSort(key) {
    const spec = state.sort[state.tab];
    if (spec.key === key) spec.dir = -spec.dir;
    else { spec.key = key; spec.dir = key === "name" || key === "profession" ? 1 : -1; }
    state.limit = PAGE;
    render();
  }

  async function start() {
    state.metaEarly = getJson("data/meta.json").catch(() => null);
    state.catalog = await getJson("catalog.json");
    $("build").textContent = `Game data build ${state.catalog.build}.`;
    state.professions = [...new Set(state.catalog.recipes.map((r) => r.p))].sort();
    for (const recipe of state.catalog.recipes) {
      if (!state.craftedBy.has(recipe.i)) state.craftedBy.set(recipe.i, []);
      state.craftedBy.get(recipe.i).push(recipe.p);
    }
    readHash();
    bind();
    bindTip();
    bindScanList();
    updateCopyButton();
    getJson("downloads/latest.json").then((latest) => {
      if (!/^[\w.-]+\.zip$/.test(latest.file)) return;
      const link = $("addon-download");
      link.href = `downloads/${latest.file}`;
      link.textContent = `Download Dufforth AH Scanner v${latest.version}`;
    }).catch(() => { /* The plain link still works. */ });
    getJson("all_items.json").then((items) => {
      state.allItems = items;
      refreshPrices();
      render();
    }).catch(() => { /* Names outside the catalog stay as item numbers. */ });
    updateNotifyButton();
    await poll();
    setInterval(poll, POLL_MS);
    setInterval(showUpdated, 60000);
    document.addEventListener("visibilitychange", () => { if (!document.hidden) poll(); });
  }

  start().catch((error) => {
    $("banner").hidden = false;
    $("banner").textContent = "The page could not load its data. Try refreshing.";
    console.error(error);
  });
})();
