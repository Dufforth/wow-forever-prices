(function () {
  "use strict";
  const { arrangeColumns, columnId, sortBy, topBy, leastSold, disenchantValue, money, priceChange, rateReturn, ratePriceNow, significantChanges, craftRows, craftDisenchantRows, disenchantDeals, disenchantOutcomes } = Calc;
  const { groups, iconBackupUrl, iconUrl, isKnown, label: categoryLabel, matches, sourceLabel, sourceOf, typeLabel, PROFESSION_PREFIX } = Categories;

  // Plain explanations for column titles, shown on hover or keyboard focus.
  const HINTS = {
    "Big move": "Whether the price moved enough to count as an alert, using your Alerts settings. Got cheaper: a chance to buy. Got pricier: a chance to sell.",
    "Craft profit": "What you keep if you craft it yourself with the best recipe and sell it the best way, after the 5% auction cut.",
    "Disenchant value": "What the enchanting materials from disenchanting one are worth on average, after the 5% auction cut. Only gear can be disenchanted.",
    "Recipe": "The profession that makes it and the skill the recipe needs.",
    "Can craft now": "How many crafts the reagents listed on the auction house cover right now. Reagents from vendors don't limit it.",
    "Mats sold, 7 days": "About how many of the main material sold in the last 7 days: a guide to how fast you can sell what you disenchant.",
    "Enchanting needed": "The Enchanting skill needed to disenchant it.",
    "Item level": "How advanced the item is. On gear, higher usually means stronger. On materials, it roughly matches the level of the zones where you find them.",
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
  const PAGE_SIZES = [25, 50, 100, 250];
  const POLL_MS = 60 * 1000; // a 1 KB check; prices download only when they change
  const FLASH_MS = 4000;
  const STALE_SECONDS = 12 * 3600;
  const SEARCH_DELAY_MS = 150;
  const TABS = ["auction", "prices", "favorites", "alerts", "profit", "deals"];
  const MAX_SORTS = 3;
  const TEXT_KEYS = new Set(["name", "profession", "type", "source", "material"]);
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
    rows: null, deals: null, professions: [], craftedBy: new Map(), mostPosted: new Set(), mostBought: new Set(), leastSold: new Set(),
    allItems: null, fileTs: null, columns: store.get("columns", {}), views: {},
    favorites: new Set(store.get("favorites", [])),
    loading: true, tab: "prices", category: "all", search: "", source: "all", collapsed: store.get("collapsed", { "Crafted by": true, "Item type": true }), page: 0, pageSize: PAGE_SIZES.includes(store.get("pageSize", 100)) ? store.get("pageSize", 100) : 100, detailId: null,
    // Each tab sorts by up to MAX_SORTS columns in turn.
    sort: {
      auction: [{ key: "name", dir: 1 }], prices: [{ key: "name", dir: 1 }], favorites: [{ key: "name", dir: 1 }], profit: [{ key: "profit", dir: -1 }],
      alerts: [{ key: "percent", dir: -1 }], "deals-buy": [{ key: "profit", dir: -1 }], "deals-craft": [{ key: "profit", dir: -1 }],
    },
    de: Object.assign({ mode: "buy", skill: "", supply: "" }, store.get("de", {})),
    ah: Object.assign({ minLevel: "", maxLevel: "", quality: "", slot: "" }, store.get("ah", {})),
    alert: Object.assign({ percent: 15, amount: 10, supply: 5, basis: "previous", favorites: false }, store.get("alert", {})),
  };

  for (const [tab, levels] of Object.entries(store.get("sort", {}))) {
    const valid = Array.isArray(levels) ? levels.filter((l) => l && typeof l.key === "string" && (l.dir === 1 || l.dir === -1)).slice(0, MAX_SORTS) : [];
    if (state.sort[tab] && valid.length) state.sort[tab] = valid;
  }

  // The key for columns and sorting: each tab, and each Disenchant sub-section, has its own.
  const viewKey = () => (state.tab === "deals" ? `deals-${state.de.mode}` : state.tab);

  async function getJson(url) {
    const response = await fetch(url, { cache: "no-cache" });
    if (!response.ok) throw new Error(`${url}: ${response.status}`);
    return response.json();
  }

  const context = () => ({ favorites: state.favorites, craftedBy: state.craftedBy, mostPosted: state.mostPosted, mostBought: state.mostBought, leastSold: state.leastSold });
  function tradableItem(id) {
    const row = state.allItems && state.allItems[id];
    return row ? { n: row[0], q: row[1], ic: row[2], cl: row[3], sc: row[4], sell: row[5], il: row[6], rl: row[7], inv: row[8] } : null;
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


  const sortRows = (rows, levels, getters) => sortBy(rows, levels, getters);

  function emptyRow(columns, text) {
    return `<tr><td class="empty" colspan="${columns}">${esc(text)}</td></tr>`;
  }

  // Item level: the same column on every tab; `itemFor` finds the row's item.
  function levelColumn(itemFor) {
    return {
      key: "level", label: "Item level", hint: HINTS["Item level"], p: 2,
      say: (r) => {
        const il = itemFor(r).il;
        if (!il) return "Item level not known.";
        const gear = itemFor(r).cl === 2 || itemFor(r).cl === 4;
        return `Item level ${number(il)}. ${gear ? "Higher usually means stronger gear." : "For materials, it roughly matches the level of the zones where you find them."}`;
      },
      cell: (r) => (itemFor(r).il ? number(itemFor(r).il) : "–"),
    };
  }

  // Every tab draws through here: one table, one count line, one set of page buttons.
  // A column has a label and a cell, and optionally a sort key, alignment (left),
  // tone (a class for the cell) and priority (p: 1 to 3; higher hides sooner on small screens).
  // A cell explains its own value with `say`, or falls back to what the column means. The
  // sentence is worked out only when you hover the cell, so drawing a table stays quick.
  function cellText(td) {
    const tr = td.parentElement;
    if (!state.drawn || !tr || tr.dataset.i == null) return null;
    const column = state.drawn.columns[td.cellIndex];
    if (!column || column.key === "name" || !column.hint) return null;
    return column.say ? column.say(state.drawn.rows[Number(tr.dataset.i)]) : column.hint;
  }

  function drawTable(allColumns, rows, rowAttributes, emptyText, unit, rowClass) {
    const levels = state.sort[viewKey()];
    state.tableColumns = allColumns;
    const columns = arrangeColumns(allColumns, state.columns[viewKey()]).shown;
    const classes = (column, extra) => {
      const list = [column.left && "left", column.p && `p${column.p}`, extra].filter(Boolean);
      return list.length ? ` class="${list.join(" ")}"` : "";
    };
    const head = columns.map((column) => {
      const hint = column.hint ? ` data-hint="${esc(column.hint)}"` : "";
      const label = column.hint ? `<span class="hinted">${column.label}</span>` : column.label;
      if (!column.key) return `<th scope="col"${classes(column)}${hint}${column.hint ? ' tabindex="0"' : ""}>${label}</th>`;
      const at = levels.findIndex((l) => l.key === column.key);
      const sort = at === 0 ? (levels[0].dir > 0 ? "ascending" : "descending") : "none";
      const mark = at < 0 ? "" : `<span class="sort-mark" aria-hidden="true">${levels[at].dir > 0 ? "▲" : "▼"}${levels.length > 1 ? `<sup>${at + 1}</sup>` : ""}</span>`
        + (at > 0 ? `<span class="sr-only">, sort ${at + 1}</span>` : "");
      return `<th scope="col"${classes(column)}${hint} data-sort="${column.key}" aria-sort="${sort}" tabindex="0">${label}${mark}</th>`;
    }).join("");
    const pages = Math.max(1, Math.ceil(rows.length / state.pageSize));
    state.page = Math.min(state.page, pages - 1);
    const from = state.page * state.pageSize;
    const shown = rows.slice(from, from + state.pageSize);
    state.drawn = { columns, rows: shown };
    const flashing = state.flash && Date.now() < state.flash.until ? state.flash.ids : null;
    const body = shown.map((row, i) => {
      const extra = [rowClass && rowClass(row), flashing && flashing.has(String(row.id)) && "flash"].filter(Boolean).join(" ");
      return `<tr class="row${extra ? " " + extra : ""}" data-i="${i}" ${rowAttributes(row)}>${columns.map((column) => `<td${classes(column, column.tone && column.tone(row))}>${column.cell(row)}</td>`).join("")}</tr>`;
    }).join("")
      || emptyRow(columns.length, state.loading ? "Loading prices…" : favoritesEmpty() || emptyText);
    $("table").innerHTML = `<thead><tr>${head}</tr></thead><tbody>${body}</tbody>`;
    if (state.columnsOpen) renderColumnsPanel();
    const parts = [];
    if (state.category !== "all") parts.push(state.tab === "auction" ? AH.label(state.category) : categoryLabel(state.category));
    if (state.source !== "all" && state.tab !== "profit") parts.push(sourceLabel(state.source).toLowerCase());
    const scope = parts.length ? ` in ${parts.join(", ")}` : "";
    $("result-count").textContent = `${number(rows.length)} ${unit}${rows.length === 1 ? "" : "s"}${scope}`;
    $("clear-filters").hidden = state.category === "all" && !state.search && (state.source === "all" || state.tab === "profit");
    drawPager(rows.length, from, shown.length, pages);
  }

  // An empty Favorites tab says how to add items, so it never looks like the page failed to load.
  function favoritesEmpty() {
    if (state.tab !== "favorites") return "";
    const count = state.favorites.size;
    if (!count) return "No favorites yet. Select the ☆ next to any item, on any tab, to track it here.";
    return `None of your ${number(count)} favorite${count === 1 ? "" : "s"} match your search or filters. Clear them to see all of them.`;
  }

  // Pages: how many rows show at once is the viewer's choice; the range and total are always shown.
  function drawPager(total, from, count, pages) {
    $("pager").hidden = total === 0;
    $("pager-range").textContent = `Showing ${number(from + 1)}–${number(from + count)} of ${number(total)}`;
    $("page-now").textContent = `Page ${number(state.page + 1)} of ${number(pages)}`;
    document.querySelector(".pager-buttons").hidden = pages === 1;
    $("page-first").disabled = $("page-prev").disabled = state.page === 0;
    $("page-last").disabled = $("page-next").disabled = state.page >= pages - 1;
    $("page-size").value = String(state.pageSize);
  }

  function goToPage(page) {
    state.page = Math.max(0, page);
    render();
    const wrap = $("table").parentElement;
    wrap.scrollTop = 0;
    if (wrap.getBoundingClientRect().top < 0) wrap.scrollIntoView({ block: "start" });
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
    const listedOnly = $("price-listed").checked;
    let rows = [];
    // These lists can hold items outside the profession catalog.
    const special = { "most-posted": [...state.mostPosted], "most-bought": [...state.mostBought], "least-sold": [...state.leastSold] }[state.category];
    for (const id of (special || allItemIds()).map(String)) {
      const item = itemOf(id);
      if (!passesFilters(id, item)) continue;
      const row = state.prices[id];
      if (listedOnly && !(row && row[2] > 0)) continue;
      rows.push({ id, item, row, change: row ? priceChange(row, basis) : null });
    }
    rows = sortRows(rows, state.sort.prices, {
      name: (r) => r.item.n, level: (r) => r.item.il || null, price: (r) => lowestOf(r.row), market: (r) => (r.row ? r.row[1] : null),
      amount: (r) => (r.change ? r.change.amount : null), percent: (r) => (r.change ? r.change.percent : null),
      supply: (r) => (r.row ? r.row[2] : null), day: (r) => (r.row ? r.row[4] : null), week: (r) => (r.row ? r.row[5] : null),
      bought: (r) => (r.row ? r.row[6] || 0 : null),
      now: (r) => { const rating = ratePriceNow(r.row); return rating ? { cheap: 0, usual: 1, pricey: 2 }[rating] : null; },
      vendor: (r) => vendorPays(r.item), vendorBuy: (r) => vendorCharges(r.item),
      type: (r) => typeLabel(r.item), source: (r) => sourceLabel(sourceOf(r.id, r.item, context())),
    });
    drawTable([
      { key: "name", label: "Item", hint: HINTS["Item"], left: true, cell: (r) => itemCell(r.id) },
      levelColumn((r) => itemOf(r.id)),
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

  // ---- Auction House ----
  // Like the game's auction house: everything listed now, browsed by the game's categories.
  // Uses the full item list (it has required level and slot), so it waits for that to load.
  const auctionItem = (id) => tradableItem(id) || itemOf(id);

  function listedAuctionIds() {
    return Object.keys(state.prices).filter((id) => state.prices[id][2] > 0);
  }

  let auctionCountsCache = { key: null, counts: null };
  function auctionCounts() {
    const key = [state.house, state.ts, Boolean(state.allItems)].join("|");
    if (auctionCountsCache.key !== key) auctionCountsCache = { key, counts: AH.counts(listedAuctionIds().map(auctionItem)) };
    return auctionCountsCache.counts;
  }

  function renderAuction() {
    $("ah-slot-label").hidden = !AH.showsSlots(state.category);
    if (!state.allItems) {
      $("table").innerHTML = `<tbody>${emptyRow(5, "Loading the auction house…")}</tbody>`;
      $("result-count").textContent = "";
      $("pager").hidden = true;
      return;
    }
    const filters = { ...state.ah, slot: AH.showsSlots(state.category) ? state.ah.slot : "" };
    let rows = [];
    for (const id of listedAuctionIds()) {
      const item = auctionItem(id);
      if (state.search && !item.n.toLowerCase().includes(state.search)) continue;
      if (state.source !== "all" && sourceOf(id, item, context()) !== state.source) continue;
      if (!AH.matches(state.category, item) || !AH.passes(item, filters)) continue;
      rows.push({ id, item, row: state.prices[id] });
    }
    rows = sortRows(rows, state.sort.auction, {
      name: (r) => r.item.n, required: (r) => r.item.rl || 0, level: (r) => r.item.il || null, supply: (r) => r.row[2],
      price: (r) => lowestOf(r.row), market: (r) => r.row[1], now: (r) => { const rating = ratePriceNow(r.row); return rating ? { cheap: 0, usual: 1, pricey: 2 }[rating] : null; },
      week: (r) => r.row[5], source: (r) => sourceLabel(sourceOf(r.id, r.item, context())), quality: (r) => r.item.q,
    });
    drawTable([
      { key: "name", label: "Item", hint: HINTS["Item"], left: true, cell: (r) => itemCell(r.id) },
      { key: "required", label: "Level", hint: "The level a character needs to use it.", say: (r) => (r.item.rl ? `Usable from level ${r.item.rl}.` : "Any level can use it."), cell: (r) => (r.item.rl ? number(r.item.rl) : "–") },
      Object.assign(levelColumn((r) => r.item), { p: 2 }),
      { key: "supply", label: "Available", hint: HINTS["For sale"], say: (r) => say.supply(r.row[2]), cell: (r) => number(r.row[2]) },
      { key: "price", label: "Buyout (each)", hint: HINTS["Lowest price"], say: (r) => say.lowest(r.row), cell: (r) => coins(lowestOf(r.row)) },
      { key: "market", label: "Market", hint: HINTS["Market"], say: (r) => say.market(r.row), p: 1, cell: (r) => coins(r.row[1]) },
      { key: "now", label: "Price now", hint: "Is today's typical price cheap, usual or pricey compared with its 7-day average?", say: (r) => say.now(r.row), p: 1, cell: (r) => badge(ratePriceNow(r.row)) },
      { key: "week", label: "7 day average", hint: HINTS["7 day average"], off: true, cell: (r) => coins(r.row[5]) },
      { key: "quality", label: "Rarity", hint: "The item's rarity, as colored in game.", off: true, left: true, cell: (r) => `<span class="q${r.item.q}">${esc(AH.QUALITIES[r.item.q] || "")}</span>` },
      { key: "source", label: "Source", hint: HINTS["Source"], left: true, off: true, cell: (r) => esc(sourceLabel(sourceOf(r.id, r.item, context()))) },
    ], rows, (r) => `data-item="${r.id}"`, "Nothing listed matches. Try another category, level range or rarity.", "listing", (r) => goodRow(ratePriceNow(r.row)));
  }

  // ---- Favorites ----
  // Everything about the items you starred: prices, trend, alerts, crafting and disenchanting.
  function bestCrafts() {
    state.rows = state.rows || craftRows(state.catalog, state.prices);
    const best = new Map();
    for (const r of state.rows) {
      const id = String(r.recipe.i);
      if (!state.favorites.has(Number(id)) || r.profit == null) continue;
      const old = best.get(id);
      if (!old || r.profit > old.profit) best.set(id, r);
    }
    return best;
  }

  function renderFavorites() {
    const basis = $("fav-basis").value;
    const alerts = new Map(allAlerts().map((a) => [String(a.id), a]));
    const crafts = bestCrafts();
    let rows = [...state.favorites].map(String).filter((id) => passesFilters(id, itemOf(id))).map((id) => {
      const item = itemOf(id), row = state.prices[id];
      return { id, item, row, change: row ? priceChange(row, basis) : null, alert: alerts.get(id) || null, craft: crafts.get(id) || null, de: disenchantValue(item, state.prices) };
    });
    rows = sortRows(rows, state.sort.favorites, {
      name: (r) => r.item.n, level: (r) => r.item.il || null, price: (r) => lowestOf(r.row), market: (r) => (r.row ? r.row[1] : null),
      now: (r) => { const rating = ratePriceNow(r.row); return rating ? { cheap: 0, usual: 1, pricey: 2 }[rating] : null; },
      percent: (r) => (r.change ? r.change.percent : null), amount: (r) => (r.change ? r.change.amount : null),
      alert: (r) => (r.alert ? r.alert.amount : null), supply: (r) => (r.row ? r.row[2] : null),
      craft: (r) => (r.craft ? r.craft.profit : null), de: (r) => r.de, vendor: (r) => vendorPays(r.item),
      day: (r) => (r.row ? r.row[4] : null), week: (r) => (r.row ? r.row[5] : null), bought: (r) => (r.row ? r.row[6] || 0 : null),
      source: (r) => sourceLabel(sourceOf(r.id, r.item, context())), type: (r) => typeLabel(r.item),
    });
    const craftTone = (r) => (!r.craft ? "muted" : r.craft.profit > 0 ? "up" : "down");
    drawTable([
      { key: "name", label: "Item", hint: HINTS["Item"], left: true, cell: (r) => itemCell(r.id) },
      levelColumn((r) => r.item),
      { key: "price", label: "Lowest price", hint: HINTS["Lowest price"], say: (r) => say.lowest(r.row), cell: (r) => `${coins(lowestOf(r.row))}${r.row && !r.row[2] ? ' <span class="badge">last seen</span>' : ""}` },
      { key: "market", label: "Market", hint: HINTS["Market"], say: (r) => say.market(r.row), p: 1, cell: (r) => coins(r.row ? r.row[1] : null) },
      { key: "now", label: "Price now", hint: "Is today's typical price cheap, usual or pricey compared with its 7-day average?", say: (r) => say.now(r.row), cell: (r) => badge(ratePriceNow(r.row)) },
      { key: "percent", label: "Change %", hint: HINTS["Change %"], say: (r) => say.change(r.change, basis), p: 1, tone: (r) => changeTone(r.change), cell: (r) => changePercent(r.change) },
      { key: "amount", label: "Change", hint: HINTS["Change"], say: (r) => say.change(r.change, basis), p: 2, tone: (r) => changeTone(r.change), cell: (r) => changeAmount(r.change) },
      { key: "alert", label: "Big move", hint: HINTS["Big move"], say: (r) => (r.alert ? `${say.change(r.alert, state.alert.basis)} ${r.alert.amount < 0 ? "A chance to buy for less." : "A chance to sell for more."}` : "No big price move with your Alerts settings."), p: 1, cell: (r) => (r.alert ? badge(r.alert.amount < 0 ? "cheaper" : "pricier") : badge(null)) },
      { key: "supply", label: "For sale", hint: HINTS["For sale"], say: (r) => say.supply(r.row ? r.row[2] : 0), p: 1, cell: (r) => (r.row ? number(r.row[2]) : "–") },
      { key: "craft", label: "Craft profit", hint: HINTS["Craft profit"], p: 2, tone: craftTone,
        say: (r) => (r.craft ? `${say.deal(r.craft.profit, r.craft.cost, "spend")} Best recipe: ${r.craft.recipe.p}${r.craft.recipe.c > 1 ? `, makes ${r.craft.recipe.c}` : ""}.` : "No recipe makes this, or some reagent prices are missing."),
        cell: (r) => (r.craft ? `${r.craft.profit > 0 ? "▲ " : "▼ "}${coins(r.craft.profit)}` : "–") },
      { key: "de", label: "Disenchant value", hint: HINTS["Disenchant value"], p: 2,
        say: (r) => (r.de == null ? "It can't be disenchanted, or its materials have no price." : `Disenchanting one gives materials worth about ${money(r.de)} on average, after the 5% cut.`), cell: (r) => coins(r.de) },
      { key: "vendor", label: "Vendor pays", hint: HINTS["Vendor pays"], say: (r) => say.vendorPays(r.item, r.row), p: 2, cell: (r) => coins(vendorPays(r.item)) },
      { key: "day", label: "24 hour average", hint: HINTS["24 hour average"], say: (r) => (r.row && r.row[4] ? `Over the last 24 hours it cost ${money(r.row[4])} on average.` : "Not enough history yet."), p: 3, cell: (r) => coins(r.row ? r.row[4] : null) },
      { key: "week", label: "7 day average", hint: HINTS["7 day average"], say: (r) => (r.row && r.row[5] ? `Over the last 7 days it cost ${money(r.row[5])} on average.` : "Not enough history yet."), p: 3, cell: (r) => coins(r.row ? r.row[5] : null) },
      { key: "bought", label: "Bought, 7 days (est.)", hint: HINTS["Bought, 7 days (est.)"], p: 3, cell: (r) => (r.row ? number(r.row[6] || 0) : "–") },
      { key: "source", label: "Source", hint: HINTS["Source"], left: true, p: 3, cell: (r) => esc(sourceLabel(sourceOf(r.id, r.item, context()))) },
      { key: "type", label: "Type", hint: HINTS["Type"], left: true, p: 3, cell: (r) => esc(typeLabel(r.item)) },
    ], rows, (r) => `data-item="${r.id}"`, "", "favorite", (r) => (r.alert && r.alert.amount < 0 ? "good-row" : goodRow(ratePriceNow(r.row))));
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

  function updateFavoriteBadge() {
    $("fav-count").hidden = state.favorites.size === 0;
    $("fav-count").textContent = state.favorites.size;
  }

  function updateAlertBadge() {
    const count = allAlerts().length;
    $("alert-count").hidden = count === 0;
    $("alert-count").textContent = count;
  }

  function renderAlerts() {
    const filtered = allAlerts().filter((c) => passesFilters(c.id, itemOf(c.id))).map((c) => ({ ...c, name: itemOf(c.id).n }));
    const rows = sortRows(filtered, state.sort.alerts, {
      name: (r) => r.name, level: (r) => itemOf(r.id).il || null, price: (r) => r.market, old: (r) => r.old, amount: (r) => Math.abs(r.amount),
      percent: (r) => Math.abs(r.percent), supply: (r) => r.supply, meaning: (r) => r.amount, vendor: (r) => vendorPays(itemOf(r.id)),
    });
    drawTable([
      { key: "name", label: "Item", hint: HINTS["Item"], left: true, cell: (r) => itemCell(r.id) },
      levelColumn((r) => itemOf(r.id)),
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
      name: (r) => r.item.n, level: (r) => r.item.il || null, profession: (r) => r.recipe.p, cost: (r) => r.cost, ah: (r) => perCraft(r.ah, r), de: (r) => perCraft(r.de, r),
      vendor: (r) => perCraft(r.vendor, r), deal: (r) => (r.profit == null ? null : r.cost > 0 ? r.profit / r.cost : 0), profit: (r) => r.profit, margin: (r) => r.margin, supply: (r) => r.supply,
    });
    const profitTone = (r) => (r.profit == null ? "muted" : r.profit > 0 ? "up" : "down");
    const profitArrow = (r) => (r.profit == null ? "" : r.profit > 0 ? "▲ " : "▼ ");
    drawTable([
      { key: "name", label: "Item", hint: HINTS["Item"], left: true, cell: (r) => itemCell(r.recipe.i, r.recipe.c > 1 ? ` <span class="badge">makes ${r.recipe.c}</span>` : "") },
      levelColumn((r) => r.item),
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
      $("pager").hidden = true;
      getJson("gear.json").then((gear) => { state.gear = gear; render(); }).catch(() => {
        $("table").innerHTML = `<tbody>${emptyRow(5, "The gear list could not load. Try refreshing.")}</tbody>`;
      });
      return;
    }
    if (crafting) {
      state.rows = state.rows || craftRows(state.catalog, state.prices);
      state.craftDeals = state.craftDeals || craftDisenchantRows(state.rows, state.prices);
    } else {
      state.deals = state.deals || disenchantDeals(state.gear, state.prices);
    }
    const skill = Number(state.de.skill) || null;
    const supply = Number(state.de.supply) || 0;
    let rows = (crafting ? state.craftDeals : state.deals).filter((d) => d.profit > 0
      && (!skill || d.skill <= skill)
      && (crafting || d.supply >= supply)
      && passesFilters(d.id, d.item));
    rows = sortRows(rows, state.sort[viewKey()], {
      name: (r) => r.item.n, level: (r) => r.item.il || null, price: (r) => r.price, value: (r) => r.value, profit: (r) => r.profit, supply: (r) => r.supply,
      roi: (r) => r.roi, skill: (r) => r.skill, material: (r) => (r.material ? itemOf(r.material).n : null),
      profession: (r) => (r.recipe ? r.recipe.p : null), vendor: (r) => vendorPays(r.item),
      source: (r) => sourceLabel(sourceOf(r.id, r.item, context())), crafts: (r) => (r.crafts == null ? Infinity : r.crafts),
      sold: (r) => r.materialSold,
    });
    state.bestCrafts = crafting ? rows.filter((r) => rateReturn(r.profit, r.price) === "good" && r.crafts !== 0).slice(0, 3) : [];
    const makes = (r) => (r.recipe && r.recipe.c > 1 ? ` <span class="badge">makes ${r.recipe.c}</span>` : "");
    const verb = crafting ? "spend" : "pay";
    const common = {
      deal: { key: "roi", label: "Deal", hint: "Good deal: on average you get back at least 20% more than you spend. Fair: a small expected profit.", say: (r) => say.deal(r.profit, r.price, verb), cell: (r) => badge(rateReturn(r.profit, r.price)) },
      value: { key: "value", label: crafting ? "Materials value" : "Expected materials", hint: HINTS["Expected materials"], say: (r) => `Disenchanting gives materials worth about ${money(r.value)} on average, after the 5% cut.`, p: 1, cell: (r) => coins(r.value) },
      ret: { key: "roi", id: "return", label: "Return", hint: HINTS["Return"], say: (r) => say.deal(r.profit, r.price, verb), off: true, cell: (r) => (r.roi == null ? "–" : `${Math.round(r.roi * 100)}%`) },
      skill: { key: "skill", label: "Enchanting needed", hint: HINTS["Enchanting needed"], say: (r) => (r.skill == null ? "Not known." : `You need ${number(r.skill)} Enchanting skill to disenchant it.`), p: 2, cell: (r) => (r.skill == null ? "–" : number(r.skill)) },
      material: { key: "material", label: "Mostly gives", hint: HINTS["Mostly gives"], say: (r) => (r.material ? `Disenchanting it mostly gives ${itemOf(r.material).n}. Hover the material for its details.` : "Not known."), left: true, p: 2, cell: (r) => materialCell(r.material) },
      level: Object.assign(levelColumn((r) => r.item), { off: true }),
      vendor: { key: "vendor", label: "Vendor pays", hint: HINTS["Vendor pays"], say: (r) => say.vendorPays(r.item, null), off: true, cell: (r) => coins(vendorPays(r.item)) },
    };
    const columns = crafting ? [
      { key: "name", label: "Item", hint: HINTS["Item"], left: true, cell: (r) => itemCell(r.id, makes(r)) },
      { key: "profession", label: "Recipe", hint: HINTS["Recipe"], left: true, p: 1, say: (r) => `${r.recipe.p} makes it from skill ${r.recipe.sk}. Open the item to see every reagent and where to get it.`,
        cell: (r) => `${esc(r.recipe.p)} <span class="muted">${number(r.recipe.sk)}</span>` },
      common.deal,
      { key: "profit", label: "Profit per craft", hint: HINTS["Expected profit"], say: (r) => `On average you make ${money(r.profit)} by buying the reagents, crafting it and disenchanting it. Each disenchant is random, so one try can give more or less.`, tone: () => "up", cell: (r) => `▲ ${coins(r.profit)}` },
      { key: "price", label: "Craft cost", hint: HINTS["Craft cost"], say: (r) => `Getting all the reagents costs ${money(r.price)}.`, p: 1, cell: (r) => coins(r.price) },
      common.value,
      { key: "crafts", label: "Can craft now", hint: HINTS["Can craft now"], p: 1,
        say: (r) => (r.crafts == null ? "Every reagent comes from a vendor or your own crafts, so supply doesn't limit it." : r.crafts === 0 ? "Not enough reagents are listed right now for even one craft." : `The reagents listed now cover about ${number(r.crafts)} craft${r.crafts === 1 ? "" : "s"}.`),
        tone: (r) => (r.crafts === 0 ? "down" : ""), cell: (r) => (r.crafts == null ? "Any" : number(r.crafts)) },
      common.skill, common.material,
      { key: "sold", label: "Mats sold, 7 days", hint: HINTS["Mats sold, 7 days"], off: true, cell: (r) => (r.materialSold == null ? "–" : number(r.materialSold)) },
      common.ret, common.level,
    ] : [
      { key: "name", label: "Item", hint: HINTS["Item"], left: true, cell: (r) => itemCell(r.id) },
      common.deal,
      { key: "profit", label: "Expected profit", hint: HINTS["Expected profit"], say: (r) => `On average you make ${money(r.profit)} by buying it and disenchanting it. Each disenchant is random, so one try can give more or less.`, tone: () => "up", cell: (r) => `▲ ${coins(r.profit)}` },
      { key: "price", label: "Lowest price", hint: HINTS["Lowest price"], say: (r) => `The cheapest one for sale costs ${money(r.price)}.`, p: 1, cell: (r) => coins(r.price) },
      common.value, common.skill, common.material,
      { key: "source", label: "Source", hint: HINTS["Source"], left: true, p: 2, say: (r) => `Where it comes from: ${sourceLabel(sourceOf(r.id, r.item, context())).toLowerCase()}.`, cell: (r) => esc(sourceLabel(sourceOf(r.id, r.item, context()))) },
      { key: "supply", label: "For sale", hint: HINTS["For sale"], say: (r) => say.supply(r.supply), p: 2, cell: (r) => number(r.supply) },
      common.ret, common.level, common.vendor,
    ];
    drawTable(columns, rows, (r) => (r.recipe ? `data-recipe="${r.recipe.s}"` : `data-item="${r.id}"`),
      state.ts ? (crafting ? "No craft is worth more disenchanted than its reagents right now." : "Nothing for sale here is worth more disenchanted right now. Try another market, or crafting it.") : "Waiting for price data.",
      crafting ? "craft" : "item", (r) => goodRow(rateReturn(r.profit, r.price)));
    $("legend").innerHTML = LEGENDS.deals();
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
      const cell = event.target.closest && event.target.closest("#table td");
      if (cell && cell === tip.hintFor) return;
      hideTip();
      const text = cell && cellText(cell);
      if (text) {
        tip.hintFor = cell;
        tip.timer = setTimeout(() => showHint(text), TIP_DELAY_MS);
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
      none.textContent = "Not enough history yet. It builds up with each update.";
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
    updateDetailFavorite();
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
    const key = [state.house, state.ts, state.source, state.favorites.size, Boolean(state.allItems), state.mostPosted.size].join("|");
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
    counts.set("most-posted", state.mostPosted.size);
    counts.set("most-bought", state.mostBought.size);
    counts.set("least-sold", state.leastSold.size);
    countsCache = { key, counts };
    return counts;
  }

  function renderCategories() {
    const auction = state.tab === "auction";
    const counts = auction ? auctionCounts() : categoryCounts();
    const button = (id, label) => `<li><button type="button" class="cat" data-category="${esc(id)}" aria-current="${state.category === id}"><span>${esc(label)}</span><span>${number(counts.get(id) || 0)}</span></button></li>`;
    const select = $("category-select");
    let html = `<ul>${button("all", "All items")}</ul>`;
    let options = '<option value="all">All items</option>';
    for (const group of auction ? AH.groups(counts) : groups(state.professions)) {
      // A group opens by itself when the chosen category is inside it.
      const holdsCurrent = group.categories.some((c) => c.id === state.category);
      const collapsedKey = auction ? `ah:${group.label}` : group.label;
      const open = holdsCurrent || (auction ? state.collapsed[collapsedKey] === false : !state.collapsed[collapsedKey]);
      const listId = `group-${group.label.toLowerCase().replace(/[^a-z]+/g, "-")}`;
      html += `<button type="button" class="group-toggle" data-group="${esc(collapsedKey)}" aria-expanded="${open}" aria-controls="${listId}">${esc(group.label)}</button>`
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
    let category = params.get("category") || "all";
    if (category === "favorites") { state.tab = "favorites"; category = "all"; } // Links from before Favorites became a tab.
    const known = state.tab === "auction" ? AH.isAuctionCategory(category) : isKnown(category, state.professions);
    state.category = known ? category : "all";
    state.search = (params.get("q") || "").toLowerCase();
    $("search").value = state.search;
  }

  const LEGENDS = {
    auction: () => `Everything listed on this auction house, like the game's: browse by category on the left, then filter by level and rarity. ${badge("cheap")} cheaper than usual this week · ${badge("pricey")} pricier than usual.`,
    prices: () => `${badge("cheap")} lower than its usual price this week, a good time to buy · ${badge("pricey")} higher than usual, a good time to sell · ▲ ▼ show how much the price moved. Hover a column title to see what it means.`,
    favorites: () => `Everything about the items you track. Select ☆ next to any item, on any tab, to add it; select ★ to remove it. ${badge("cheap")} and ${badge("cheaper")} are good times to buy · ${badge("pricey")} and ${badge("pricier")} are good times to sell.`,
    alerts: () => `Items whose price moved a lot. ${badge("cheaper")} is a chance to buy, and ${badge("pricier")} is a chance to sell. Hover a column title to see what it means.`,
    profit: () => `${badge("good")} pays back at least 20% more than you spend · ${badge("fair")} small profit · ${badge("poor")} loses money. Profit is per craft, after the 5% auction cut.`,
    deals: () => (state.de.mode === "craft"
      ? `Buy the reagents, craft, disenchant and sell the materials. ${badge("good")} returns at least 20% more than you spend · ${badge("fair")} a small profit. Profit is per craft, after the 5% cut.`
        + (state.bestCrafts && state.bestCrafts.length ? ` <b>Best now:</b> ${state.bestCrafts.map((r) => `${esc(r.item.n)} (${money(r.profit)})`).join(", ")}.` : "")
      : `Gear for sale that's worth more as enchanting materials than it costs. ${badge("good")} returns at least 20% more than you spend · ${badge("fair")} a small expected profit. Results vary item by item.`),
  };

  function renderSubTabs() {
    document.querySelectorAll("[data-de-mode]").forEach((button) => {
      const on = button.dataset.deMode === state.de.mode;
      button.setAttribute("aria-selected", on);
      button.tabIndex = on ? 0 : -1;
    });
    $("de-supply-label").hidden = state.de.mode === "craft"; // crafting shows how many crafts the reagents cover instead
  }

  // Each tab keeps its own category, search, source and page, so tabs don't filter each other.
  function switchTab(tab) {
    state.views[state.tab] = { category: state.category, search: state.search, source: state.source, page: state.page };
    state.tab = tab;
    store.set("tab", tab);
    const view = state.views[tab] || { category: "all", search: "", source: "all", page: 0 };
    Object.assign(state, view);
    $("search").value = state.search;
    $("source-filter").value = state.source;
    render();
    $("table").parentElement.scrollTop = 0;
  }

  function render() {
    renderSubTabs();
    document.querySelectorAll(".tabs button").forEach((b) => {
      const on = b.dataset.tab === state.tab;
      b.setAttribute("aria-selected", on);
      b.tabIndex = on ? 0 : -1;
    });
    TABS.forEach((name) => { $("tab-" + name).hidden = name !== state.tab; });
    $("results").setAttribute("aria-labelledby", "tabbtn-" + state.tab);
    $("legend").innerHTML = LEGENDS[state.tab]();
    $("table").parentElement.setAttribute("aria-busy", state.loading ? "true" : "false");
    $("source-filter").hidden = state.tab === "profit"; // Every recipe is crafted.
    hideTip();
    updateAlertBadge();
    updateFavoriteBadge();
    renderCategories();
    ({ auction: renderAuction, prices: renderPrices, favorites: renderFavorites, alerts: renderAlerts, profit: renderProfit, deals: renderDeals })[state.tab]();
    writeHash();
  }

  function resetAndRender() {
    state.page = 0;
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

  const allHouses = () => (state.meta ? state.meta.houses.slice() : []);

  const houseLabel = (h) => `${h.rulesetName} ${h.name} · ${h.scannedAt ? timeAgo(h.scannedAt).replace(" ago", "") : "no data"}`;

  // The live badge: green while checks work, with how old the prices are.
  function showLive(state_, text) {
    const badge = $("live");
    badge.dataset.state = state_;
    badge.querySelector(".live-text").textContent = text;
  }

  function liveText() {
    return state.ts ? `Live · prices ${timeAgo(state.ts)}` : "Live";
  }

  // Item IDs whose lowest price, market price or quantity changed, for a short highlight.
  function changedIds(before, after) {
    const ids = new Set();
    for (const id of Object.keys(after)) {
      const a = after[id], b = before[id];
      if (!b || a[0] !== b[0] || a[1] !== b[1] || a[2] !== b[2]) ids.add(id);
    }
    return ids;
  }

  function showUpdated() {
    if (state.ts && $("live").dataset.state !== "error") showLive("ok", liveText());
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

  // Light or dark: follows the computer until you choose; your choice stays in this browser.
  function currentTheme() {
    const chosen = document.documentElement.dataset.theme;
    if (chosen) return chosen;
    return window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  }

  function updateThemeButton() {
    const dark = currentTheme() === "dark";
    const button = $("theme");
    button.innerHTML = dark
      ? '<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>'
      : '<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/></svg>';
    const text = dark ? "Switch to light mode" : "Switch to dark mode";
    button.title = text;
    button.setAttribute("aria-label", text);
  }

  function toggleTheme() {
    const next = currentTheme() === "dark" ? "light" : "dark";
    document.documentElement.dataset.theme = next;
    store.set("theme", next);
    updateThemeButton();
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

  // Everything that reads prices reads state.prices.
  function usePrices(file) {
    state.prices = file.items || {};
    state.ts = state.fileTs = file.ts || null;
    state.history = null;
    state.mostPosted = topBy(state.prices, 2, TOP_ITEMS);
    state.mostBought = topBy(state.prices, 6, TOP_ITEMS);
    state.leastSold = leastSold(state.prices, TOP_ITEMS);
    state.rows = null; state.deals = null; state.craftDeals = null;
  }

  // The page starts downloading the saved market's prices before the scripts run (index.html).
  function houseFile(id) {
    const early = window.FP_EARLY && window.FP_EARLY.house;
    if (early && early.id === id && !early.used) {
      early.used = true;
      return early.file.catch(() => getJson(`data/h${encodeURIComponent(id)}.json`));
    }
    return getJson(`data/h${encodeURIComponent(id)}.json`);
  }

  async function loadHouse(id) {
    state.house = id;
    store.set("house", id);
    let file = {};
    try { file = await houseFile(id); } catch (e) { /* no data for this market yet */ }
    usePrices(file);
    state.page = 0;
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
      const changed = !first && meta.updated !== state.meta.updated;
      state.meta = meta;
      if (first) await loadHouse(fillHouses());
      else if (changed) {
        showLive("busy", "Updating…");
        const file = await getJson(`data/h${encodeURIComponent(state.house)}.json`);
        if (file.ts !== state.fileTs) {
          const ids = changedIds(state.prices, file.items || {});
          usePrices(file);
          state.flash = { ids, until: Date.now() + FLASH_MS };
          render(); // keeps your tab, filters, page and scroll position
          setTimeout(() => { state.flash = null; }, FLASH_MS);
          if (ids.size) toast(`New prices: ${number(ids.size)} item${ids.size === 1 ? "" : "s"} changed.`);
        }
      }
      notifyChanges();
      state.loading = false;
      showLive("ok", liveText());
    } catch (e) {
      state.loading = false;
      if (state.meta) showLive("error", "Offline · retrying");
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
    if (id === "most-posted") state.sort.prices = [{ key: "supply", dir: -1 }];
    if (id === "most-bought") state.sort.prices = [{ key: "bought", dir: -1 }];
    if (id === "least-sold") state.sort.prices = [{ key: "bought", dir: 1 }, { key: "supply", dir: -1 }];
    resetAndRender();
  }

  function bind() {
    const tabs = [...document.querySelectorAll(".tabs button")];
    tabs.forEach((button, index) => {
      button.addEventListener("click", () => switchTab(button.dataset.tab));
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
    ["price-basis", "fav-basis", "price-listed", "profit-only", "profit-supply"].forEach((id) => $(id).addEventListener("input", resetAndRender));
    [["ah-min", "minLevel"], ["ah-max", "maxLevel"], ["ah-quality", "quality"], ["ah-slot", "slot"]].forEach(([id, key]) => {
      const input = $(id);
      input.value = state.ah[key];
      input.addEventListener("input", () => {
        state.ah[key] = input.value;
        store.set("ah", state.ah);
        resetAndRender();
      });
    });
    document.querySelectorAll("[data-de-mode]").forEach((button) => button.addEventListener("click", () => {
      state.de.mode = button.dataset.deMode;
      store.set("de", state.de);
      resetAndRender();
    }));
    [["de-skill", "skill"], ["de-supply", "supply"]].forEach(([id, key]) => {
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
    $("page-first").addEventListener("click", () => goToPage(0));
    $("page-prev").addEventListener("click", () => goToPage(state.page - 1));
    $("page-next").addEventListener("click", () => goToPage(state.page + 1));
    $("page-last").addEventListener("click", () => goToPage(Number.MAX_SAFE_INTEGER));
    $("page-size").addEventListener("change", (event) => {
      state.pageSize = Number(event.target.value);
      store.set("pageSize", state.pageSize);
      goToPage(0);
    });

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
      if (head) { changeSort(head.dataset.sort, event.shiftKey); return; }
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
        changeSort(key, event.shiftKey);
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
    window.addEventListener("hashchange", () => { readHash(); state.page = 0; render(); });
  }

  const firstDirection = (key) => (TEXT_KEYS.has(key) ? 1 : -1);

  function changeSort(key, add) {
    const levels = state.sort[viewKey()];
    const at = levels.findIndex((l) => l.key === key);
    if (add && at >= 0) levels[at].dir = -levels[at].dir;
    else if (add) levels.splice(Math.min(levels.length, MAX_SORTS - 1), MAX_SORTS, { key, dir: firstDirection(key) });
    else state.sort[viewKey()] = [{ key, dir: at === 0 ? -levels[0].dir : firstDirection(key) }];
    saveSort();
  }

  function saveSort() {
    store.set("sort", state.sort);
    state.page = 0;
    render();
  }

  // ---- Columns and sorting panel ----
  // Show, hide and reorder columns, and choose up to three sort levels. Saved in this browser only.
  function sortableColumns() {
    const seen = new Set();
    return state.tableColumns.filter((c) => c.key && !seen.has(c.key) && seen.add(c.key));
  }

  function directionLabel(key, dir) {
    if (TEXT_KEYS.has(key)) return dir > 0 ? "A to Z" : "Z to A";
    return dir > 0 ? "Low to high" : "High to low";
  }

  function renderColumnsPanel() {
    const panel = $("columns-panel");
    if (!state.tableColumns) return;
    const saved = state.columns[viewKey()] || {};
    const hidden = new Set(saved.hidden || state.tableColumns.filter((c) => c.off).map(columnId));
    const all = arrangeColumns(state.tableColumns, saved).all.slice(1);
    const plain = (c) => esc(c.label);
    const columnRows = all.map((c, i) => {
      const id = esc(columnId(c));
      return `<li draggable="true" data-col="${id}"><span class="cp-grip" aria-hidden="true">⠿</span>
        <label><input type="checkbox" data-show="${id}"${hidden.has(columnId(c)) ? "" : " checked"}> ${plain(c)}</label>
        <button type="button" class="secondary cp-move" data-move="-1" data-col="${id}" aria-label="Move ${plain(c)} earlier"${i === 0 ? " disabled" : ""}>↑</button>
        <button type="button" class="secondary cp-move" data-move="1" data-col="${id}" aria-label="Move ${plain(c)} later"${i === all.length - 1 ? " disabled" : ""}>↓</button></li>`;
    }).join("");
    const sortable = sortableColumns();
    const levels = state.sort[viewKey()];
    const sortRowsHtml = levels.map((level, i) => `<li><span class="cp-then">${i === 0 ? "Sort by" : "then by"}</span>
        <select data-sort-level="${i}" aria-label="${i === 0 ? "Sort by" : `Then by, level ${i + 1}`}">${sortable.map((c) => `<option value="${esc(c.key)}"${c.key === level.key ? " selected" : ""}>${plain(c)}</option>`).join("")}</select>
        <button type="button" class="secondary" data-sort-dir="${i}">${directionLabel(level.key, level.dir)}</button>
        ${i > 0 ? `<button type="button" class="linkish" data-sort-remove="${i}" aria-label="Remove sort level ${i + 1}">Remove</button>` : ""}</li>`).join("");
    const canAdd = levels.length < MAX_SORTS && sortable.some((c) => !levels.some((l) => l.key === c.key));
    panel.innerHTML = `<div class="cp-head"><b>Columns</b><button type="button" class="linkish" data-reset>Reset</button>
        <button type="button" class="cp-close" data-close aria-label="Close">×</button></div>
      <p class="muted cp-note">Tick to show or hide. Drag, or use the arrows, to reorder. Saved in this browser only.</p>
      <ul class="cp-list">${columnRows}</ul>
      <div class="cp-head"><b>Sort</b></div>
      <p class="muted cp-note">Later levels break ties, for example item level and then name. Shortcut: Shift+click a column title.</p>
      <ol class="cp-sorts">${sortRowsHtml}</ol>
      ${canAdd ? '<button type="button" class="secondary" data-sort-add>Add another sort</button>' : ""}`;
  }

  function saveColumns(order, hidden) {
    state.columns[viewKey()] = { order, hidden };
    store.set("columns", state.columns);
    render();
  }

  function currentColumns() {
    const saved = state.columns[viewKey()] || {};
    return { order: arrangeColumns(state.tableColumns, saved).all.slice(1).map(columnId), hidden: (saved.hidden || state.tableColumns.filter((c) => c.off).map(columnId)).slice() };
  }

  function moveColumn(id, to) {
    const { order, hidden } = currentColumns();
    const from = order.indexOf(id);
    if (from < 0 || to < 0 || to >= order.length) return;
    order.splice(to, 0, ...order.splice(from, 1));
    saveColumns(order, hidden);
  }

  // Redrawing replaces the panel, so focus goes back to the control with the same job.
  function keepFocus(selector) {
    const again = selector && $("columns-panel").querySelector(selector);
    if (again && !again.disabled) again.focus();
    else $("columns-panel").focus();
  }

  function setColumnsOpen(open) {
    state.columnsOpen = open;
    $("columns-panel").hidden = !open;
    $("columns-toggle").setAttribute("aria-expanded", open);
    if (open) { renderColumnsPanel(); $("columns-panel").focus(); }
  }

  function bindColumns() {
    const panel = $("columns-panel");
    $("columns-toggle").addEventListener("click", () => setColumnsOpen(!state.columnsOpen));
    panel.addEventListener("keydown", (event) => {
      if (event.key === "Escape") { setColumnsOpen(false); $("columns-toggle").focus(); }
    });
    document.addEventListener("pointerdown", (event) => {
      if (state.columnsOpen && !panel.contains(event.target) && !$("columns-toggle").contains(event.target)) setColumnsOpen(false);
    });
    panel.addEventListener("change", (event) => {
      const show = event.target.dataset.show;
      if (show != null) {
        const { order, hidden } = currentColumns();
        const set = new Set(hidden);
        if (event.target.checked) set.delete(show); else set.add(show);
        saveColumns(order, [...set]);
        keepFocus(`[data-show="${CSS.escape(show)}"]`);
        return;
      }
      const level = event.target.dataset.sortLevel;
      if (level != null) {
        const key = event.target.value;
        // A column sorts at one level only, so choosing it here takes it off any other level.
        const levels = state.sort[viewKey()].filter((l, i) => i !== Number(level) && l.key !== key);
        const at = Math.min(Number(level), levels.length);
        levels.splice(at, 0, { key, dir: firstDirection(key) });
        state.sort[viewKey()] = levels;
        saveSort();
        keepFocus(`[data-sort-level="${at}"]`);
      }
    });
    panel.addEventListener("click", (event) => {
      const target = event.target.closest("button");
      if (!target) return;
      const data = target.dataset;
      if (data.close != null) { setColumnsOpen(false); $("columns-toggle").focus(); return; }
      if (data.reset != null) {
        delete state.columns[viewKey()];
        store.set("columns", state.columns);
        render();
        keepFocus("[data-reset]");
      } else if (data.move) {
        const { order } = currentColumns();
        const to = order.indexOf(data.col) + Number(data.move);
        moveColumn(data.col, to);
        keepFocus(`[data-move="${data.move}"][data-col="${CSS.escape(data.col)}"]`);
      } else if (data.sortDir != null) {
        const level = state.sort[viewKey()][Number(data.sortDir)];
        level.dir = -level.dir;
        saveSort();
        keepFocus(`[data-sort-dir="${data.sortDir}"]`);
      } else if (data.sortRemove != null) {
        state.sort[viewKey()].splice(Number(data.sortRemove), 1);
        saveSort();
        keepFocus("[data-sort-add]");
      } else if (data.sortAdd != null) {
        const levels = state.sort[viewKey()];
        const next = sortableColumns().find((c) => !levels.some((l) => l.key === c.key));
        if (next) levels.push({ key: next.key, dir: firstDirection(next.key) });
        saveSort();
        keepFocus(`[data-sort-level="${levels.length - 1}"]`);
      }
    });
    // Drag a column onto another to put it there.
    let dragged = null;
    panel.addEventListener("dragstart", (event) => {
      const row = event.target.closest("[data-col]");
      dragged = row ? row.dataset.col : null;
      if (dragged) event.dataTransfer.effectAllowed = "move";
    });
    panel.addEventListener("dragover", (event) => { if (dragged && event.target.closest(".cp-list [data-col]")) event.preventDefault(); });
    panel.addEventListener("drop", (event) => {
      const row = event.target.closest(".cp-list li[data-col]");
      if (!dragged || !row) return;
      event.preventDefault();
      moveColumn(dragged, currentColumns().order.indexOf(row.dataset.col));
      dragged = null;
    });
  }

  async function start() {
    const early = window.FP_EARLY || {};
    state.metaEarly = (early.meta || getJson("data/meta.json")).catch(() => null);
    state.catalog = await (early.catalog ? early.catalog.catch(() => getJson("catalog.json")) : getJson("catalog.json"));
    $("build").textContent = `Game data build ${state.catalog.build}.`;
    state.professions = [...new Set(state.catalog.recipes.map((r) => r.p))].sort();
    for (const recipe of state.catalog.recipes) {
      if (!state.craftedBy.has(recipe.i)) state.craftedBy.set(recipe.i, []);
      state.craftedBy.get(recipe.i).push(recipe.p);
    }
    readHash();
    bind();
    bindTip();
    bindColumns();
    getJson("downloads/latest.json").then((latest) => {
      if (!/^[\w.-]+\.zip$/.test(latest.file)) return;
      const link = $("addon-download");
      link.href = `downloads/${latest.file}`;
      link.title = `Download the free Dufforth AH Scanner addon, version ${latest.version}`;
      link.setAttribute("aria-label", link.title);
    }).catch(() => { /* The plain link still works. */ });
    getJson("all_items.json").then((items) => {
      state.allItems = items;
      render();
    }).catch(() => { /* Names outside the catalog stay as item numbers. */ });
    updateNotifyButton();
    updateThemeButton();
    $("theme").addEventListener("click", toggleTheme);
    await poll();
    // Checks every minute while the page is visible, and at once when you come back to it.
    setInterval(() => { if (!document.hidden) poll(); }, POLL_MS);
    setInterval(showUpdated, 30000);
    document.addEventListener("visibilitychange", () => { if (!document.hidden) poll(); });
  }

  start().catch((error) => {
    $("banner").hidden = false;
    $("banner").textContent = "The page could not load its data. Try refreshing.";
    console.error(error);
  });
})();
