// A short guided tour: Janine, the guide avatar, floats over the page and explains each section
// in a speech balloon. At most six steps, started on demand with the Guide button.
(function () {
  "use strict";

  const AVATAR = `<svg class="guide-avatar" viewBox="0 0 120 140" aria-hidden="true" focusable="false">
  <g class="guide-bob">
    <path class="guide-tail" d="M86 122 C108 118 114 94 104 80 C99 73 104 64 111 68" fill="none" stroke="#1b1b20" stroke-width="7" stroke-linecap="round"/>
    <path d="M30 140 C30 110 43 97 60 97 C77 97 90 110 90 140 Z" fill="#26262c" stroke="#101014" stroke-width="2"/>
    <path d="M60 100 V132" stroke="#101014" stroke-width="1.5"/>
    <path d="M34 60 L33 32 L50 47 Z" fill="#26262c" stroke="#101014" stroke-width="2" stroke-linejoin="round"/>
    <path d="M86 60 L89 30 L71 46 Z" fill="#26262c" stroke="#101014" stroke-width="2" stroke-linejoin="round"/>
    <path d="M85 54 L87 37 L76 47 Z" fill="#e8956a"/>
    <circle cx="60" cy="72" r="28" fill="#26262c" stroke="#101014" stroke-width="2"/>
    <ellipse cx="60" cy="80" rx="18" ry="16" fill="#f2c9a0"/>
    <path d="M42 70 C44 84 46 90 50 94 L44 94 C40 88 40 78 42 70 Z M78 70 C76 84 74 90 70 94 L76 94 C80 88 80 78 78 70 Z" fill="#3b2a22"/>
    <path d="M37 72 H42 M78 72 H83" stroke="#101014" stroke-width="4"/>
    <rect x="40" y="64" width="40" height="17" rx="7" fill="#3a3b42" stroke="#101014" stroke-width="2"/>
    <rect x="45" y="67" width="14" height="3" rx="1.5" fill="#777a84"/>
    <path d="M52 87 Q60 93 68 87" fill="none" stroke="#7a3b22" stroke-width="2" stroke-linecap="round"/>
    <path d="M44 47 C46 24 54 13 60 13 C66 13 74 24 76 47 Z" fill="#e9c27a" stroke="#6b4a1f" stroke-width="2"/>
    <path d="M45 39 H75" stroke="#2f9e6e" stroke-width="4"/>
    <polyline points="46,35 50,31 54,35 58,31 62,35 66,31 70,35 74,31" fill="none" stroke="#d8572a" stroke-width="2"/>
    <ellipse cx="60" cy="49" rx="54" ry="11" fill="#e9c27a" stroke="#6b4a1f" stroke-width="2"/>
    <ellipse cx="60" cy="50" rx="47" ry="8" fill="none" stroke="#1f8f9a" stroke-width="2"/>
    <polyline points="16,50 22,55 28,51 34,57 40,52 46,58 52,53 58,59 64,53 70,58 76,52 82,57 88,51 94,55 100,50 104,52" fill="none" stroke="#d8572a" stroke-width="2.5" stroke-linejoin="round"/>
    <polyline points="20,52 26,56 32,53 38,58 44,54 50,59 56,55 62,59 68,55 74,58 80,54 86,57 92,53 98,55" fill="none" stroke="#f2c230" stroke-width="1.5" stroke-linejoin="round"/>
    <path d="M77 103 L93 97 L86 113 Z" fill="#f08a2a" stroke="#a24d10" stroke-width="1.5" stroke-linejoin="round"/>
    <circle cx="80" cy="110" r="6" fill="#26262c" stroke="#101014" stroke-width="2"/>
  </g>
</svg>`;

  // Each step points at the first of its targets that is visible (the sidebar becomes a menu on small screens).
  const STEPS = [
    { targets: ["#house"], title: "Hi, I'm Janine!",
      text: "Pick your auction house here. Prices refresh about once an hour, straight from Blizzard." },
    { targets: [".sidebar", "#category-select"], title: "Categories",
      text: "Choose a group, like herbs, ores or gear. Tap the ☆ on any item to track it in the Favorites tab." },
    { targets: ["#tabbtn-auction", "#tabbtn-prices"], title: "Auction House and Prices",
      text: "Auction House lets you browse everything for sale, like in game. Prices, Favorites and Alerts track costs and big moves. Hover any number to learn more." },
    { targets: ["#tabbtn-profit", "#tabbtn-deals"], title: "Profit and Disenchant",
      text: "What's worth crafting, and which gear is worth more as enchanting materials. Green Good deal rows are the best chances." },
    { targets: ["#columns-toggle"], title: "Columns and sorting",
      text: "Show, hide or reorder columns, and sort by more than one, like item level and then name. Click a column title to sort." },
    { targets: ["#addon-download"], title: "The addon",
      text: "Get the free Dufforth AH Scanner addon for your game here. Happy trading!" },
  ];

  const visible = (el) => el && el.getClientRects().length > 0 && getComputedStyle(el).visibility !== "hidden";
  const targetOf = (step) => step.targets.map((s) => document.querySelector(s)).find(visible) || null;

  let index = -1, box, spot, opener;

  function build() {
    spot = document.createElement("div");
    spot.className = "guide-spot";
    spot.hidden = true;
    box = document.createElement("div");
    box.className = "guide";
    box.setAttribute("role", "dialog");
    box.setAttribute("aria-label", "Janine's page guide");
    box.hidden = true;
    box.innerHTML = `${AVATAR}<div class="guide-balloon">
      <button type="button" class="guide-close" aria-label="Close the guide">×</button>
      <p class="guide-title"></p><p class="guide-text" aria-live="polite"></p>
      <div class="guide-nav"><span class="guide-step muted"></span>
        <button type="button" class="secondary guide-back">Back</button>
        <button type="button" class="guide-next">Next</button></div></div>`;
    document.body.append(spot, box);
    box.querySelector(".guide-close").addEventListener("click", stop);
    box.querySelector(".guide-back").addEventListener("click", () => show(index - 1));
    box.querySelector(".guide-next").addEventListener("click", () => (index === STEPS.length - 1 ? stop() : show(index + 1)));
    box.addEventListener("keydown", (event) => {
      if (event.key === "Escape") stop();
      else if (event.key === "ArrowRight" && index < STEPS.length - 1) show(index + 1);
      else if (event.key === "ArrowLeft" && index > 0) show(index - 1);
    });
    addEventListener("resize", place);
    addEventListener("scroll", place, true);
  }

  function place() {
    if (index < 0) return;
    const target = targetOf(STEPS[index]);
    const pad = 6, gap = 12, edge = 16;
    if (!target) { spot.hidden = true; return; }
    const r = target.getBoundingClientRect();
    // Tall targets like the sidebar only get their visible part outlined.
    const top = Math.max(r.top, 0), bottom = Math.min(r.bottom, innerHeight);
    Object.assign(spot.style, { left: `${r.left - pad}px`, top: `${Math.max(2, top - pad)}px`, width: `${r.width + pad * 2}px`, height: `${bottom - top + pad * 2}px` });
    spot.hidden = false;
    if (innerWidth < 600) { box.classList.add("docked"); box.style.left = box.style.top = ""; return; }
    box.classList.remove("docked");
    const w = box.offsetWidth, h = box.offsetHeight;
    // Beside tall targets, below short ones, and above when there's no room below.
    let x, y;
    if (r.height > innerHeight / 2) { x = r.right + gap; y = Math.max(edge, Math.min(top + 40, innerHeight - h - edge)); }
    else { x = r.left; y = r.bottom + gap + pad; if (y + h > innerHeight - edge) y = r.top - h - gap - pad; }
    box.style.left = `${Math.max(edge, Math.min(x, innerWidth - w - edge))}px`;
    box.style.top = `${Math.max(edge, y)}px`;
  }

  function show(i) {
    index = Math.max(0, Math.min(i, STEPS.length - 1));
    const step = STEPS[index];
    const target = targetOf(step);
    if (target) target.scrollIntoView({ block: "nearest", inline: "center" });
    box.querySelector(".guide-title").textContent = step.title;
    box.querySelector(".guide-text").textContent = step.text;
    box.querySelector(".guide-step").textContent = `${index + 1} of ${STEPS.length}`;
    box.querySelector(".guide-back").hidden = index === 0;
    box.querySelector(".guide-next").textContent = index === STEPS.length - 1 ? "Done" : "Next";
    box.hidden = false;
    place();
    box.querySelector(".guide-next").focus({ preventScroll: true });
  }

  function start() {
    if (!box) build();
    opener = document.activeElement;
    document.getElementById("tip").hidden = true;
    show(0);
  }

  function stop() {
    index = -1;
    box.hidden = true;
    spot.hidden = true;
    if (opener && opener.focus) opener.focus();
  }

  document.addEventListener("DOMContentLoaded", () => {
    const button = document.getElementById("guide-start");
    if (button) button.addEventListener("click", start);
  });
  if (typeof module === "object") module.exports = { STEPS };
})();
