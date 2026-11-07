const test = require("node:test");
const assert = require("node:assert");
const { address, sanitize } = require("../site/tooltip.js");

test("keeps real tooltip content and removes comments", () => {
  const input = '<table width="100%"><tr><td><!--nstart--><b class="q2">Thorium Greatsword</b><!--nend--><span class="q"><br>Item Level <!--ilvl-->52</span></td><th>Speed 3.60</th></tr></table>';
  assert.equal(sanitize(input), '<table><tr><td><b class="q2">Thorium Greatsword</b><span class="q"><br>Item Level 52</span></td><th>Speed 3.60</th></tr></table>');
});

test("keeps sell price markup", () => {
  assert.equal(sanitize('<div class="whtt-sellprice">Sell Price: <span class="moneygold">2</span> <span class="moneycopper">34</span></div>'),
    '<div class="whtt-sellprice">Sell Price: <span class="moneygold">2</span> <span class="moneycopper">34</span></div>');
});

test("turns links into plain colored text", () => {
  assert.equal(sanitize('<a href="/forever/spell=439" class="q2">Restores 70 to 90 health.</a>'), '<span class="q2">Restores 70 to 90 health.</span>');
});

test("keeps entities in text", () => {
  assert.equal(sanitize("&quot;Ephemeral &amp; unstable.&quot;"), "&quot;Ephemeral &amp; unstable.&quot;");
});

for (const [name, input] of Object.entries({
  "script": "<script>alert(1)</script>",
  "uppercase script": "<SCRIPT src=x>alert(1)</SCRIPT>",
  "image handler": "<img src=x onerror=alert(1)>",
  "svg": "<svg onload=alert(1)></svg>",
  "iframe": '<iframe src="javascript:alert(1)"></iframe>',
  "style": "<style>body{display:none}</style>",
  "javascript link": '<a href="javascript:alert(1)">',
  "event on allowed tag": '<div onclick="alert(1)" onmouseover=alert(1)>',
  "style attribute": '<span style="position:fixed">',
  "bad class": '<span class="q2 x&quot; onclick=&quot;alert(1)">',
  "broken tag": "<img src=x onerror=alert(1) ",
  "attribute with bracket": '<div title="a>b" onclick="alert(1)">',
})) {
  test(`removes dangerous content: ${name}`, () => {
    const out = sanitize(input);
    assert.doesNotMatch(out, /<(script|img|svg|iframe|style)\b/i, out);
    assert.doesNotMatch(out, /<[^>]*(\son\w+\s*=|href|src|style\s*=)/i, out);
  });
}

test("unexpected input gives nothing", () => {
  assert.equal(sanitize(undefined), "");
  assert.equal(sanitize(null), "");
  assert.equal(sanitize(5), "");
});

test("address only ever contains a number", () => {
  assert.equal(address("118"), "https://nether.wowhead.com/forever/tooltip/item/118");
  assert.equal(address("../evil"), "https://nether.wowhead.com/forever/tooltip/item/NaN");
});
