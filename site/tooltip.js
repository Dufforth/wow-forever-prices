// Cleans item tooltip HTML from Wowhead before it goes on the page.
// Output contains only known tags and classes, and no other attributes, so nothing can run.
// No page code here, so it runs in Node tests too.
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.Tooltip = factory();
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  const ADDRESS = "https://nether.wowhead.com/forever/tooltip/item/";
  const TAGS = new Set(["table", "tbody", "tr", "td", "th", "b", "br", "span", "div"]);
  const RENAMED = { a: "span" }; // Keeps a link's text and color, without the link.
  const CLASSES = /^(q[0-9]?|money(gold|silver|copper)|whtt-(sellprice|maxstack|extra|ilvl))$/;
  const TOKEN = /<!--[\s\S]*?-->|<(script|style)\b[\s\S]*?<\/\1\s*>|<(\/?)([a-zA-Z][a-zA-Z0-9]*)((?:"[^"]*"|'[^']*'|[^>"'])*)>/g;

  function safeClasses(attributes) {
    const match = /(?:^|\s)class\s*=\s*"([^"]*)"/i.exec(attributes);
    if (!match) return "";
    const kept = match[1].split(/\s+/).filter((name) => CLASSES.test(name));
    return kept.length ? ` class="${kept.join(" ")}"` : "";
  }

  // Entities such as &quot; are already safe, so only stray < and > need escaping.
  function safeText(text) {
    return text.replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }

  function sanitize(html) {
    if (typeof html !== "string") return "";
    let out = "", last = 0, match;
    TOKEN.lastIndex = 0;
    while ((match = TOKEN.exec(html))) {
      out += safeText(html.slice(last, match.index));
      last = TOKEN.lastIndex;
      if (!match[3]) continue; // A comment, script or style.
      const lower = match[3].toLowerCase();
      const name = RENAMED[lower] || lower;
      if (!TAGS.has(name)) continue;
      if (match[2]) out += `</${name}>`;
      else out += `<${name}${safeClasses(match[4])}>`;
    }
    return out + safeText(html.slice(last));
  }

  function address(id) {
    return ADDRESS + encodeURIComponent(Number(id));
  }

  return { address, sanitize };
});
