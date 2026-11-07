// Reads the addon's auction scans from its saved file, and ranks market activity.
// No page code here, so it runs in Node tests too.
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.Scan = factory();
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  const ENTRY = /\["(forever\.[a-z]+\.[a-z]+\.[a-z]+)"\]\s*=\s*\{([^{}]*)\}/g;
  const FIELD_AT = /\["at"\]\s*=\s*(\d+)/;
  const FIELD_MODE = /\["mode"\]\s*=\s*"(\w+)"/;
  const FIELD_COMPLETE = /\["complete"\]\s*=\s*(true|false)/;
  const FIELD_DATA = /\["data"\]\s*=\s*"([\d:;]*)"/;

  // From the text of the game's TentTimer.lua: { market: { at, mode, complete, data } }.
  function parseSavedFile(text) {
    const scans = {};
    if (typeof text !== "string") return scans;
    ENTRY.lastIndex = 0;
    let match;
    while ((match = ENTRY.exec(text))) {
      const body = match[2];
      const at = FIELD_AT.exec(body), data = FIELD_DATA.exec(body);
      if (!at || !data) continue;
      const mode = FIELD_MODE.exec(body), complete = FIELD_COMPLETE.exec(body);
      scans[match[1]] = {
        at: Number(at[1]), data: data[1], mode: mode ? mode[1] : "full",
        complete: complete ? complete[1] === "true" : true,
      };
    }
    return scans;
  }

  // "2447:19:3351;2770:40:5710" as { 2447: [19, 3351], 2770: [40, 5710] }.
  function decodeRows(data) {
    const rows = {};
    for (const part of String(data || "").split(";")) {
      const [id, price, quantity] = part.split(":").map(Number);
      // Price 0 with quantity 0 means the addon asked and none are for sale.
      if (id > 0 && (price > 0 ? quantity >= 0 : price === 0 && quantity === 0)) rows[id] = [price, quantity];
    }
    return rows;
  }

  // Scanned prices over published ones. The published price becomes "previous",
  // so the change columns show how far the price moved since the last public scan.
  function applyScan(published, scanRows) {
    const merged = { ...published };
    for (const id of Object.keys(scanRows)) {
      const [price, quantity] = scanRows[id];
      const old = published[id];
      if (price === 0) {
        if (old) merged[id] = [null, old[1], 0, old[1], old[4], old[5], old[6] || 0];
        continue;
      }
      merged[id] = [price, price, quantity, old ? old[1] : null, old ? old[4] : null, old ? old[5] : null, old ? old[6] || 0 : 0];
    }
    return merged;
  }

  // The IDs of the top items by a column of a price row.
  function topBy(rows, column, count) {
    return new Set(Object.keys(rows)
      .filter((id) => rows[id][column] > 0)
      .sort((a, b) => rows[b][column] - rows[a][column])
      .slice(0, count)
      .map(Number));
  }

  // The text pasted into the addon's /ahscan list window.
  function listString(ids) {
    return "GT1:" + ids.join(",");
  }

  // Items for the add box: an exact ID, then names starting with the text, then containing it.
  // items: { id: [name, quality, icon, class, subclass] }
  function searchItems(items, text, limit) {
    const query = String(text || "").trim().toLowerCase();
    if (!query) return [];
    if (/^\d+$/.test(query) && items[query]) return [Number(query)];
    const starts = [], contains = [];
    for (const id of Object.keys(items)) {
      const at = items[id][0].toLowerCase().indexOf(query);
      if (at === 0) starts.push(id);
      else if (at > 0) contains.push(id);
    }
    const byName = (a, b) => items[a][0].localeCompare(items[b][0]);
    return starts.sort(byName).concat(contains.sort(byName)).slice(0, limit).map(Number);
  }

  return { applyScan, decodeRows, listString, parseSavedFile, searchItems, topBy };
});
