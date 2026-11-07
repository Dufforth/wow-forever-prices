(function () {
  "use strict";
  const { money, priceChange, significantChanges, craftRows, disenchantDeals, disenchantOutcomes, disenchantValue, afterCut } = Calc;
  const PAGE = 100;
  const POLL_MS = 5 * 60 * 1000;
  const GATHERING = new Set(["herb", "ore", "leather", "cloth", "enchant"]);
  const $ = (id) => document.getElementById(id);
  const esc = (text) => String(text).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

  const store = {
    get(key, fallback) { try { const v = localStorage.getItem("fp." + key); return v == null ? fallback : JSON.parse(v); } catch (e) { return fallback; } },
    set(key, value) { try { localStorage.setItem("fp." + key, JSON.stringify(value)); } catch (e) { /* private window */ } },
  };

  const state = {
    catalog: null, gear: null, meta: null, house: null, prices: {}, ts: null,
    crafted: new Map(), rows: null, deals: null,
    limits: { prices: PAGE, profit: PAGE, deals: PAGE },
    sort: {
      prices: { key: "name", dir: 1 }, profit: { key: "profit", dir: -1 },
      alerts: { key: "percent", dir: -1 }, deals: { key: "profit", dir: -1 },
    },
    alert: Object.assign({ percent: 15, amount: 10, supply: 5, basis: "previous" }, store.get("alert", {})),
  };

  async function getJson(url) {
    const response = await fetch(url, { cache: "no-cache" });
    if (!response.ok) throw new Error(response.status);
    return response.json();
  }

  const itemOf = (id) => state.catalog.items[id] || (state.gear && state.gear[id]) || { n: "Item " + id, q: 1 };
  const itemName = (id) => `<span class="item q${itemOf(id).q}">${esc(itemOf(id).n)}</span>`;

  function changeCells(change) {
    if (!change || change.amount === 0) return `<td class="muted">–</td><td class="muted">–</td>`;
    const up = change.amount > 0;
    const cls = up ? "up" : "down";
    const arrow = up ? "▲" : "▼";
    return `<td class="${cls}">${arrow} ${money(Math.abs(change.amount))}</td><td class="${cls}">${up ? "+" : "-"}${Math.abs(change.percent).toFixed(1)}%</td>`;
  }

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

  function renderTable(table, name, columns, bodyHtml) {
    const spec = state.sort[name];
    const head = columns.map((c) => {
      const sort = c.key === spec.key ? (spec.dir > 0 ? "ascending" : "descending") : "none";
      const cls = c.left ? ' class="left"' : "";
      return c.key ? `<th${cls} data-sort="${c.key}" aria-sort="${sort}" tabindex="0">${c.label}</th>` : `<th${cls}>${c.label}</th>`;
    }).join("");
    table.innerHTML = `<thead><tr>${head}</tr></thead><tbody>${bodyHtml}</tbody>`;
    table.querySelectorAll("th[data-sort]").forEach((th) => {
      const flip = () => {
        const key = th.dataset.sort;
        if (spec.key === key) spec.dir = -spec.dir;
        else { spec.key = key; spec.dir = key === "name" ? 1 : -1; }
        render();
      };
      th.addEventListener("click", flip);
      th.addEventListener("keydown", (e) => { if (e.key === "Enter") flip(); });
    });
  }

  function emptyRow(columns, text) {
    return `<tr><td class="empty" colspan="${columns}">${esc(text)}</td></tr>`;
  }

  // ---- Prices ----
  function matchesGroup(id, item, group) {
    if (group === "all") return true;
    if (group === "gathering") return GATHERING.has(item.g);
    if (GATHERING.has(group)) return item.g === group;
    return (state.crafted.get(Number(id)) || []).includes(group);
  }

  function renderPrices() {
    const search = $("price-search").value.trim().toLowerCase();
    const group = $("price-group").value;
    const basis = $("price-basis").value;
    let rows = [];
    for (const id of Object.keys(state.catalog.items)) {
      const item = state.catalog.items[id];
      if (search && !item.n.toLowerCase().includes(search)) continue;
      if (!matchesGroup(id, item, group)) continue;
      const row = state.prices[id];
      rows.push({ id, item, row, change: row ? priceChange(row, basis) : null });
    }
    rows = sortRows(rows, state.sort.prices, {
      name: (r) => r.item.n, low: (r) => (r.row ? r.row[0] : null), market: (r) => (r.row ? r.row[1] : null),
      amount: (r) => (r.change ? r.change.amount : null), percent: (r) => (r.change ? r.change.percent : null),
      supply: (r) => (r.row ? r.row[2] : null),
    });
    const shown = rows.slice(0, state.limits.prices);
    const columns = [
      { key: "name", label: "Item", left: true }, { key: "low", label: "Lowest" }, { key: "market", label: "Market" },
      { key: "amount", label: "Change" }, { key: "percent", label: "Change %" }, { key: "supply", label: "For sale" },
    ];
    const body = shown.map((r) => {
      const row = r.row;
      return `<tr data-item="${r.id}"><td>${itemName(r.id)}</td><td>${money(row ? row[0] : null)}</td><td>${money(row ? row[1] : null)}</td>${changeCells(r.change)}<td>${row ? row[2].toLocaleString("en-US") : "–"}</td></tr>`;
    }).join("") || emptyRow(6, "No items match.");
    renderTable($("price-table"), "prices", columns, body);
    $("price-more").hidden = rows.length <= shown.length;
    $("price-more").textContent = `Show more (${(rows.length - shown.length).toLocaleString("en-US")} left)`;
  }

  // ---- Alerts ----
  function currentAlerts() {
    const a = state.alert;
    return significantChanges(state.prices, { percent: a.percent, minAmount: a.amount * 100, minSupply: a.supply, basis: a.basis })
      .filter((c) => state.catalog.items[c.id]);
  }

  function renderAlerts() {
    const rows = sortRows(currentAlerts().map((c) => ({ ...c, name: itemOf(c.id).n })), state.sort.alerts, {
      name: (r) => r.name, market: (r) => r.market, old: (r) => r.old, amount: (r) => Math.abs(r.amount),
      percent: (r) => Math.abs(r.percent), supply: (r) => r.supply,
    });
    const columns = [
      { key: "name", label: "Item", left: true }, { key: "market", label: "Now" }, { key: "old", label: "Before" },
      { key: "amount", label: "Change" }, { key: "percent", label: "Change %" }, { key: "supply", label: "For sale" },
    ];
    const body = rows.map((r) => `<tr data-item="${r.id}"><td>${itemName(r.id)}</td><td>${money(r.market)}</td><td>${money(r.old)}</td>${changeCells(r)}<td>${r.supply.toLocaleString("en-US")}</td></tr>`).join("")
      || emptyRow(6, state.ts ? "No significant price changes with these limits." : "Waiting for price data.");
    renderTable($("alert-table"), "alerts", columns, body);
    const count = $("alert-count");
    count.hidden = rows.length === 0;
    count.textContent = rows.length;
  }

  // ---- Profit ----
  // A craft can make several items, so every money column shows the whole craft.
  const perCraft = (each, row) => (each == null ? null : each * row.recipe.c);

  function renderProfit() {
    state.rows = state.rows || craftRows(state.catalog, state.prices);
    const search = $("profit-search").value.trim().toLowerCase();
    const profession = $("profit-profession").value;
    const only = $("profit-only").checked;
    const supply = Number($("profit-supply").value) || 0;
    let rows = state.rows.filter((r) => {
      if (profession !== "all" && r.recipe.p !== profession) return false;
      if (search && !r.item.n.toLowerCase().includes(search)) return false;
      if (only && !(r.profit > 0)) return false;
      if (supply && r.best && r.best.kind === "Sell on auction" && r.supply < supply) return false;
      return true;
    });
    rows = sortRows(rows, state.sort.profit, {
      name: (r) => r.item.n, profession: (r) => r.recipe.p, cost: (r) => r.cost, ah: (r) => perCraft(r.ah, r), de: (r) => perCraft(r.de, r),
      vendor: (r) => perCraft(r.vendor, r), profit: (r) => r.profit, margin: (r) => r.margin, supply: (r) => r.supply,
    });
    const shown = rows.slice(0, state.limits.profit);
    const columns = [
      { key: "name", label: "Item", left: true }, { key: "profession", label: "Profession", left: true }, { key: "cost", label: "Craft cost" },
      { key: "ah", label: "Auction, after cut" }, { key: "de", label: "Disenchant" }, { key: "vendor", label: "Vendor" },
      { label: "Best choice", left: true }, { key: "profit", label: "Profit" }, { key: "margin", label: "Margin" }, { key: "supply", label: "For sale" },
    ];
    const body = shown.map((r) => {
      const each = r.recipe.c > 1 ? ` <span class="badge">makes ${r.recipe.c}</span>` : "";
      const cls = r.profit == null ? "muted" : r.profit > 0 ? "up" : "down";
      const arrow = r.profit == null ? "" : r.profit > 0 ? "▲ " : "▼ ";
      return `<tr data-recipe="${r.recipe.s}"><td>${itemName(r.recipe.i)}${each}</td><td class="left">${esc(r.recipe.p)}</td>
        <td>${r.cost == null ? '<span class="muted">Missing prices</span>' : money(r.cost)}</td>
        <td>${money(perCraft(r.ah, r))}</td><td>${money(perCraft(r.de, r))}</td><td>${money(perCraft(r.vendor, r))}</td>
        <td class="left">${r.best ? esc(r.best.kind) : "–"}</td>
        <td class="${cls}">${arrow}${money(r.profit)}</td>
        <td>${r.margin == null ? "–" : (r.margin * 100).toFixed(0) + "%"}</td><td>${r.supply ? r.supply.toLocaleString("en-US") : "0"}</td></tr>`;
    }).join("") || emptyRow(10, state.ts ? "No recipes match. Try turning off Only profitable." : "Waiting for price data.");
    renderTable($("profit-table"), "profit", columns, body);
    $("profit-more").hidden = rows.length <= shown.length;
    $("profit-more").textContent = `Show more (${(rows.length - shown.length).toLocaleString("en-US")} left)`;
  }

  // ---- Disenchant deals ----
  function renderDeals() {
    if (!state.gear) {
      $("deal-table").innerHTML = `<tbody>${emptyRow(5, "Loading gear list…")}</tbody>`;
      getJson("gear.json").then((gear) => { state.gear = gear; render(); });
      return;
    }
    state.deals = state.deals || disenchantDeals(state.gear, state.prices);
    const search = $("deal-search").value.trim().toLowerCase();
    let rows = state.deals.filter((d) => d.profit > 0 && (!search || d.item.n.toLowerCase().includes(search)));
    rows = sortRows(rows, state.sort.deals, {
      name: (r) => r.item.n, price: (r) => r.price, value: (r) => r.value, profit: (r) => r.profit, supply: (r) => r.supply,
    });
    const shown = rows.slice(0, state.limits.deals);
    const columns = [
      { key: "name", label: "Item", left: true }, { key: "price", label: "Lowest price" }, { key: "value", label: "Expected materials" },
      { key: "profit", label: "Expected profit" }, { key: "supply", label: "For sale" },
    ];
    const body = shown.map((r) => `<tr data-deal="${r.id}"><td><span class="item q${r.item.q}">${esc(r.item.n)}</span></td><td>${money(r.price)}</td><td>${money(r.value)}</td><td class="up">▲ ${money(r.profit)}</td><td>${r.supply}</td></tr>`).join("")
      || emptyRow(5, state.ts ? "No gear is priced below its materials right now." : "Waiting for price data.");
    renderTable($("deal-table"), "deals", columns, body);
    $("deal-more").hidden = rows.length <= shown.length;
    $("deal-more").textContent = `Show more (${(rows.length - shown.length).toLocaleString("en-US")} left)`;
  }

  // ---- Item detail ----
  const SOURCE = { auction: "Auction", vendor: "Vendor", craft: "Craft it", none: "No price" };

  function statBox(label, value) {
    return `<div class="stat"><b>${value}</b><span>${esc(label)}</span></div>`;
  }

  function lineChart(times, values, ranged) {
    const points = times.map((t, i) => ({ t, v: values[i] })).filter((p) => p.v != null);
    if (points.length < 2) return '<p class="muted">Not enough history yet. It builds up with each update.</p>';
    const W = 700, H = 240, L = 62, R = 14, T = 12, B = 26;
    const vs = points.map((p) => p.v);
    let lo = Math.min(...vs), hi = Math.max(...vs);
    if (lo === hi) { lo *= 0.9; hi = hi * 1.1 || 1; }
    const pad = (hi - lo) * 0.08; lo = Math.max(0, lo - pad); hi += pad;
    const t0 = points[0].t, t1 = points[points.length - 1].t;
    const x = (t) => L + ((t - t0) / (t1 - t0 || 1)) * (W - L - R);
    const y = (v) => T + (1 - (v - lo) / (hi - lo)) * (H - T - B);
    const date = (t) => new Date(t * 1000).toLocaleDateString(undefined, { month: "short", day: "numeric" });
    const stamp = (t) => new Date(t * 1000).toLocaleString(undefined, ranged ? { month: "short", day: "numeric" } : { month: "short", day: "numeric", hour: "numeric" });
    const grid = [0, 0.5, 1].map((f) => {
      const v = lo + (hi - lo) * f;
      return `<line x1="${L}" x2="${W - R}" y1="${y(v)}" y2="${y(v)}" stroke="var(--grid)"/><text x="${L - 8}" y="${y(v) + 4}" text-anchor="end">${esc(money(v))}</text>`;
    }).join("");
    const path = points.map((p, i) => `${i ? "L" : "M"}${x(p.t).toFixed(1)} ${y(p.v).toFixed(1)}`).join("");
    const svg = `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Market price history">${grid}
      <text x="${L}" y="${H - 7}">${esc(date(t0))}</text><text x="${W - R}" y="${H - 7}" text-anchor="end">${esc(date(t1))}</text>
      <path d="${path}" fill="none" stroke="var(--series)" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>
      <line class="cross" x1="0" x2="0" y1="${T}" y2="${H - B}" stroke="var(--muted)" visibility="hidden"/>
      <circle class="dot" r="4" fill="var(--series)" stroke="var(--surface)" stroke-width="2" visibility="hidden"/>
      <rect x="${L}" y="${T}" width="${W - L - R}" height="${H - T - B}" fill="transparent"/></svg>`;
    const box = document.createElement("div");
    box.className = "chart";
    box.innerHTML = svg + '<div class="tip" hidden></div>';
    const root = box.querySelector("svg"), cross = box.querySelector(".cross"), dot = box.querySelector(".dot"), tip = box.querySelector(".tip");
    const move = (event) => {
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
    };
    root.addEventListener("pointermove", move);
    root.addEventListener("pointerleave", () => { cross.setAttribute("visibility", "hidden"); dot.setAttribute("visibility", "hidden"); tip.hidden = true; });
    return box;
  }

  async function loadHistory(id, holder) {
    holder.innerHTML = '<p class="muted">Loading history…</p>';
    let history;
    try {
      state.history = state.history && state.history.house === state.house ? state.history : { house: state.house, data: await getJson(`data/hist${state.house}.json`) };
      history = state.history.data;
    } catch (e) {
      holder.innerHTML = '<p class="muted">No history yet.</p>';
      return;
    }
    const show = (range) => {
      const section = range === "days" ? history.days : history.hours;
      const content = lineChart(section.t, section.i[id] || [], range === "days");
      holder.querySelector(".plot").replaceChildren(typeof content === "string" ? Object.assign(document.createElement("div"), { innerHTML: content }) : content);
      holder.querySelectorAll("[data-range]").forEach((b) => b.classList.toggle("on", b.dataset.range === range));
    };
    holder.innerHTML = '<div class="range"><button type="button" class="secondary" data-range="hours">Last 7 days, hourly</button><button type="button" class="secondary" data-range="days">Last 60 days, daily</button></div><div class="plot"></div>';
    holder.querySelectorAll("[data-range]").forEach((b) => b.addEventListener("click", () => show(b.dataset.range)));
    show("hours");
  }

  function reagentTable(parts) {
    const rows = parts.map((p) => `<tr><td>${itemName(p.id)}</td><td>${p.count}</td><td>${money(p.cost)}</td><td>${p.cost == null ? "–" : money(p.cost * p.count)}</td><td class="left">${SOURCE[p.source]}</td></tr>`).join("");
    return `<div class="table-wrap"><table class="detail-table"><thead><tr><th>Reagent</th><th>Needed</th><th>Each</th><th>Total</th><th class="left">Cheapest from</th></tr></thead><tbody>${rows}</tbody></table></div>`;
  }

  function disenchantTable(item) {
    const outcomes = disenchantOutcomes(item);
    if (!outcomes) return "";
    const rows = outcomes.filter((o) => o.chance > 0).map((o) => {
      const row = state.prices[o.id];
      return `<tr><td>${itemName(o.id)}</td><td>${Math.round(o.chance * 1000) / 10}%</td><td>${o.min === o.max ? o.min : o.min + "–" + o.max}</td><td>${money(row && row[2] > 0 ? row[1] : null)}</td></tr>`;
    }).join("");
    return `<h3>Disenchant results (expected)</h3><div class="table-wrap"><table class="detail-table"><thead><tr><th>Material</th><th>Chance</th><th>Amount</th><th>Market each</th></tr></thead><tbody>${rows}</tbody></table></div>`;
  }

  function openItem(id, recipeSpell) {
    const item = itemOf(id);
    const row = state.prices[id];
    const dialog = $("detail");
    $("detail-title").innerHTML = `<span class="q${item.q}">${esc(item.n)}</span>`;
    const stats = [
      statBox("Lowest", money(row ? row[0] : null)), statBox("Market", money(row ? row[1] : null)),
      statBox("Previous update", money(row ? row[3] : null)), statBox("24 hour average", money(row ? row[4] : null)),
      statBox("7 day average", money(row ? row[5] : null)), statBox("For sale", row ? row[2].toLocaleString("en-US") : "–"),
    ].join("");
    const crafts = (state.rows || (state.rows = craftRows(state.catalog, state.prices))).filter((r) => r.recipe.i === Number(id));
    const ordered = recipeSpell ? crafts.sort((a, b) => (b.recipe.s === recipeSpell) - (a.recipe.s === recipeSpell)) : crafts;
    const craftHtml = ordered.map((r) => {
      const options = r.options.map((o) => `${esc(o.kind)}: ${money(o.each * r.recipe.c)}`).join(" · ") || "No selling price known";
      const buy = r.cost != null && r.ah != null && r.supply > 0 && row && row[1] * r.recipe.c < r.cost
        ? `<p class="muted note">Buying it costs ${money(row[1] * r.recipe.c)}, less than crafting it.</p>` : "";
      return `<h3>${esc(r.recipe.p)} recipe, skill ${r.recipe.sk}${r.recipe.c > 1 ? `, makes ${r.recipe.c}` : ""}</h3>
        ${reagentTable(r.parts)}
        <p class="note" style="margin-top:8px">Cost ${money(r.cost)} · ${options} · <b>Profit ${money(r.profit)}</b></p>${buy}`;
    }).join("");
    const usedIn = state.catalog.recipes.filter((r) => r.r.some((p) => p[0] === Number(id)));
    const usedHtml = usedIn.length ? `<h3>Used in ${usedIn.length} recipe${usedIn.length > 1 ? "s" : ""}</h3><p class="muted note">${usedIn.slice(0, 12).map((r) => esc(r.n)).join(", ")}${usedIn.length > 12 ? " and more" : ""}</p>` : "";
    $("detail-body").innerHTML = `<div class="stats">${stats}</div><div id="history"></div>${craftHtml}${disenchantTable(item)}${usedHtml}
      <p class="note" style="margin-top:12px"><a href="https://forever.warcraftdb.com/data/item/${Number(id)}" target="_blank" rel="noopener">Open in Warcraft DB</a></p>`;
    dialog.showModal();
    loadHistory(String(id), $("history"));
  }

  // ---- Page ----
  function render() {
    const tab = store.get("tab", "prices");
    document.querySelectorAll(".tabs button").forEach((b) => b.setAttribute("aria-selected", b.dataset.tab === tab ? "true" : "false"));
    ["prices", "alerts", "profit", "deals"].forEach((name) => { $("tab-" + name).hidden = name !== tab; });
    renderAlerts();
    if (tab === "prices") renderPrices();
    if (tab === "profit") renderProfit();
    if (tab === "deals") renderDeals();
  }

  function timeAgo(seconds) {
    const minutes = Math.round((Date.now() / 1000 - seconds) / 60);
    if (minutes < 1) return "just now";
    if (minutes < 60) return `${minutes} min ago`;
    const hours = Math.round(minutes / 60);
    return hours < 48 ? `${hours} hour${hours > 1 ? "s" : ""} ago` : `${Math.round(hours / 24)} days ago`;
  }

  function showUpdated() {
    $("updated").textContent = state.ts ? `Prices from ${timeAgo(state.ts)}. Checks for new prices every 5 minutes.` : "Waiting for the first prices.";
  }

  function toast(text) {
    const box = $("toast");
    box.textContent = text;
    box.hidden = false;
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => { box.hidden = true; }, 15000);
  }

  function notifyChanges() {
    const key = `seen.${state.house}`;
    const seen = store.get(key, null);
    if (seen === state.ts) return;
    store.set(key, state.ts);
    if (seen == null) return; // First visit: nothing has changed since you last looked.
    const alerts = currentAlerts();
    if (!alerts.length) return;
    const lines = alerts.slice(0, 3).map((a) => `${itemOf(a.id).n} ${a.amount > 0 ? "+" : "-"}${Math.abs(a.percent).toFixed(0)}% (${money(Math.abs(a.amount))})`);
    const more = alerts.length > 3 ? ` and ${alerts.length - 3} more` : "";
    const title = `${alerts.length} significant price change${alerts.length > 1 ? "s" : ""}`;
    toast(`${title}: ${lines.join(", ")}${more}`);
    if ("Notification" in window && Notification.permission === "granted" && store.get("notify", false)) {
      new Notification(title, { body: lines.join("\n") + more, tag: "forever-prices" });
    }
  }

  function updateNotifyButton() {
    const button = $("notify");
    if (!("Notification" in window)) { button.hidden = true; return; }
    const on = Notification.permission === "granted" && store.get("notify", false);
    button.textContent = on ? "Notifications on" : "Turn on notifications";
    button.classList.toggle("on", on);
    button.classList.toggle("secondary", !on);
    button.title = Notification.permission === "denied" ? "Notifications are blocked in your browser settings" : "";
  }

  async function loadHouse(id) {
    state.house = id;
    store.set("house", id);
    let file = { ts: null, items: {} };
    try { file = await getJson(`data/h${id}.json`); } catch (e) { /* no data for this house yet */ }
    state.prices = file.items || {};
    state.ts = file.ts || null;
    state.rows = null; state.deals = null;
    showUpdated();
    render();
  }

  function fillHouses() {
    const select = $("house");
    const houses = state.meta.houses.slice().sort((a, b) => (b.listings || 0) - (a.listings || 0));
    select.innerHTML = houses.map((h) => `<option value="${h.id}">${esc(h.rulesetName)} – ${esc(h.name)}</option>`).join("");
    const saved = store.get("house", null);
    const pick = houses.find((h) => h.id === saved) || houses[0];
    select.value = pick.id;
    return pick.id;
  }

  async function poll() {
    try {
      const meta = await getJson("data/meta.json");
      const first = !state.meta;
      state.meta = meta;
      $("banner").hidden = true;
      if (first) await loadHouse(fillHouses());
      else {
        const file = await getJson(`data/h${state.house}.json`);
        if (file.ts !== state.ts) {
          state.prices = file.items; state.ts = file.ts; state.rows = null; state.deals = null; state.history = null;
          render();
        }
      }
      notifyChanges();
    } catch (e) {
      if (!state.meta) {
        const banner = $("banner");
        banner.hidden = false;
        banner.textContent = "No prices yet. They appear after the first successful update from the Blizzard API.";
        render();
      }
    }
    showUpdated();
  }

  function bind() {
    document.querySelectorAll(".tabs button").forEach((b) => b.addEventListener("click", () => { store.set("tab", b.dataset.tab); render(); }));
    $("house").addEventListener("change", (e) => { state.history = null; loadHouse(Number(e.target.value)).then(notifyChanges); });
    const reset = (name) => () => { state.limits[name] = PAGE; render(); };
    ["price-search", "price-group", "price-basis"].forEach((id) => $(id).addEventListener("input", reset("prices")));
    ["profit-search", "profit-profession", "profit-only", "profit-supply"].forEach((id) => $(id).addEventListener("input", reset("profit")));
    $("deal-search").addEventListener("input", reset("deals"));
    $("price-more").addEventListener("click", () => { state.limits.prices += PAGE; render(); });
    $("profit-more").addEventListener("click", () => { state.limits.profit += PAGE; render(); });
    $("deal-more").addEventListener("click", () => { state.limits.deals += PAGE; render(); });

    [["alert-percent", "percent"], ["alert-amount", "amount"], ["alert-supply", "supply"], ["alert-basis", "basis"]].forEach(([id, key]) => {
      const input = $(id);
      input.value = state.alert[key];
      input.addEventListener("input", () => {
        state.alert[key] = key === "basis" ? input.value : Math.max(0, Number(input.value) || 0);
        store.set("alert", state.alert);
        render();
      });
    });

    $("price-table").addEventListener("click", (e) => { const tr = e.target.closest("tr[data-item]"); if (tr) openItem(tr.dataset.item); });
    $("alert-table").addEventListener("click", (e) => { const tr = e.target.closest("tr[data-item]"); if (tr) openItem(tr.dataset.item); });
    $("profit-table").addEventListener("click", (e) => {
      const tr = e.target.closest("tr[data-recipe]");
      if (!tr) return;
      const recipe = state.catalog.recipes.find((r) => r.s === Number(tr.dataset.recipe));
      openItem(String(recipe.i), recipe.s);
    });
    $("deal-table").addEventListener("click", (e) => { const tr = e.target.closest("tr[data-deal]"); if (tr) openItem(tr.dataset.deal); });
    $("detail-close").addEventListener("click", () => $("detail").close());
    $("detail").addEventListener("click", (e) => { if (e.target === $("detail")) $("detail").close(); });
    $("toast").addEventListener("click", () => { $("toast").hidden = true; store.set("tab", "alerts"); render(); });

    $("notify").addEventListener("click", async () => {
      if (Notification.permission === "default") await Notification.requestPermission();
      if (Notification.permission === "granted") store.set("notify", !store.get("notify", false));
      else toast("Notifications are blocked. Allow them for this site in your browser settings.");
      updateNotifyButton();
    });
  }

  async function start() {
    state.catalog = await getJson("catalog.json");
    $("build").textContent = `Game data build ${state.catalog.build}.`;
    const professions = [...new Set(state.catalog.recipes.map((r) => r.p))].sort();
    for (const recipe of state.catalog.recipes) {
      if (!state.crafted.has(recipe.i)) state.crafted.set(recipe.i, []);
      state.crafted.get(recipe.i).push(recipe.p);
    }
    $("price-professions").innerHTML = professions.map((p) => `<option value="${esc(p)}">${esc(p)}</option>`).join("");
    $("profit-profession").innerHTML = '<option value="all">All professions</option>' + professions.map((p) => `<option value="${esc(p)}">${esc(p)}</option>`).join("");
    bind();
    updateNotifyButton();
    await poll();
    render();
    setInterval(poll, POLL_MS);
    setInterval(showUpdated, 60000);
    document.addEventListener("visibilitychange", () => { if (!document.hidden) poll(); });
  }

  start().catch((error) => {
    const banner = $("banner");
    banner.hidden = false;
    banner.textContent = "The page could not load its data. Try refreshing.";
    console.error(error);
  });
  window.ForeverPrices = { state, afterCut, disenchantValue };
})();
