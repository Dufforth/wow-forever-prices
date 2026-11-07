const test = require("node:test");
const assert = require("node:assert");
const Scan = require("../site/scan.js");

const SAVED = `
TentTimerDB = {
["nodes"] = {
["size"] = 14,
["pins"] = {
{
["name"] = "Peacebloom",
},
},
},
["scans"] = {
["forever.pvp.alliance.us"] = {
["complete"] = false,
["at"] = 1800000000,
["mode"] = "quick",
["data"] = "2447:19:3351;2770:40:5710",
},
["forever.pvp.horde.us"] = {
["data"] = "118:100:5",
["at"] = 1800000100,
},
},
}
`;

test("reads every scan in the saved file, in any field order", () => {
  const scans = Scan.parseSavedFile(SAVED);
  assert.deepEqual(Object.keys(scans).sort(), ["forever.pvp.alliance.us", "forever.pvp.horde.us"]);
  assert.deepEqual(scans["forever.pvp.alliance.us"], { at: 1800000000, data: "2447:19:3351;2770:40:5710", mode: "quick", complete: false });
  assert.equal(scans["forever.pvp.horde.us"].complete, true);
});

test("the wrong file or a damaged scan gives nothing", () => {
  assert.deepEqual(Scan.parseSavedFile("NotOurAddon = { }"), {});
  assert.deepEqual(Scan.parseSavedFile(undefined), {});
  assert.deepEqual(Scan.parseSavedFile('["forever.pvp.horde.us"] = { ["at"] = 5, }'), {});
  assert.deepEqual(Scan.parseSavedFile('["forever.pvp.horde.us"] = { ["at"] = 5, ["data"] = "<script>", }'), {});
});

test("decodes rows and skips bad ones", () => {
  assert.deepEqual(Scan.decodeRows("2447:19:3351;2770:40:0"), { 2447: [19, 3351], 2770: [40, 0] });
  assert.deepEqual(Scan.decodeRows("1:0:5;x:1:1;5:5;;"), {});
  assert.deepEqual(Scan.decodeRows("7:0:0"), { 7: [0, 0] });
  assert.deepEqual(Scan.decodeRows(undefined), {});
});

test("scanned prices replace published ones and keep comparisons", () => {
  const published = { 1: [100, 100, 10, 90, 95, 80, 7], 2: [50, 50, 5, 40, 45, 30, 1] };
  const merged = Scan.applyScan(published, { 1: [120, 3], 3: [9, 2] });
  assert.deepEqual(merged[1], [120, 120, 3, 100, 95, 80, 7]);
  assert.deepEqual(merged[2], published[2]);
  assert.deepEqual(merged[3], [9, 9, 2, null, null, null, 0]);
  assert.deepEqual(published[1], [100, 100, 10, 90, 95, 80, 7], "the published data isn't changed");
});

test("an item asked for with none for sale shows zero and keeps its last price", () => {
  const published = { 1: [100, 100, 10, 90, 95, 80, 7] };
  const merged = Scan.applyScan(published, { 1: [0, 0], 2: [0, 0] });
  assert.deepEqual(merged[1], [null, 100, 0, 100, 95, 80, 7]);
  assert.equal(merged[2], undefined);
});

test("list text for the addon", () => {
  assert.equal(Scan.listString([2447, 118]), "GT1:2447,118");
  assert.equal(Scan.listString([]), "GT1:");
});

test("item search ranks exact ID, then name start, then name contains", () => {
  const items = { 10: ["Copper Ore", 1], 11: ["Copper Bar", 1], 12: ["Rough Copper Bomb", 1], 13: ["Tin Ore", 1] };
  assert.deepEqual(Scan.searchItems(items, "copper", 10), [11, 10, 12]);
  assert.deepEqual(Scan.searchItems(items, "COPPER", 1), [11]);
  assert.deepEqual(Scan.searchItems(items, "13", 10), [13]);
  assert.deepEqual(Scan.searchItems(items, "  ", 10), []);
  assert.deepEqual(Scan.searchItems(items, "zzz", 10), []);
});

test("ranks the top items by a column and ignores zero", () => {
  const rows = { 1: [0, 0, 5, 0, 0, 0, 0], 2: [0, 0, 50, 0, 0, 0, 9], 3: [0, 0, 20, 0, 0, 0, 3], 4: [0, 0, 0] };
  assert.deepEqual([...Scan.topBy(rows, 2, 2)], [2, 3]);
  assert.deepEqual([...Scan.topBy(rows, 6, 5)], [2, 3]);
});
