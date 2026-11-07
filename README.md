# Forever Prices

A page showing WoW Forever auction prices for profession and gathering items, with price change alerts and crafting and disenchanting profit.

A GitHub Actions job runs every hour. It reads the [public auctionhouse.fyi API](https://auctionhouse.fyi/docs/api), which needs no key, saves the prices on the `data` branch and publishes the page with GitHub Pages.

## How the numbers work

- **Prices come from players** scanning the auction house and uploading to auctionhouse.fyi. A market only has data if someone scans it, so the page shows how old each scan is.
- **Prices are the lowest asking price per unit**, not completed sales, so a single unusual listing can skew them.
- **Profit** is per craft. Reagents use the cheapest of auction, vendor or crafting them yourself, and selling on the auction takes off the 5% cut.
- **Disenchant values** are expected averages from the Classic tables, by item level, so check them in game.
- **Items with random bonuses** are left out of prices, and bind on pickup items can't be sold on the auction.
- **The vendor list** covers common trade-goods reagents only.

## Refreshing prices from the game

Anyone can download the addon from the page's **My scans** tab. Its source is in `addon/TentTimer`, and the hourly job builds the download from it. Your scan list and scans stay in your own browser. A static page can't collect them from other people.

On the same tab, add or remove the items you want. **Copy list for addon** gives you text to paste in game with `/ahscan list`. **Scan my list** or `/ahscan mine` then scans just those items, and every other scan also asks for any list items it didn't find.

The Gathering Tracker addon can read the auction house itself. It asks for one item category at a time (materials, consumables, ammo, bags, recipes, armor and weapons), leaving out quest and miscellaneous items. Each answer gives an item's lowest price and total quantity.

1. Open the auction house and press **Scan prices**, or type `/ahscan` (`/ahscan quick` skips bags, recipes and gear).
2. Type `/reload`, because addons can only save files that way.
3. On the page, press **Load scan** and pick `SavedVariables\TentTimer.lua`.

Scans stay in that browser and are never published.

## After a game patch

```bash
python catalog/build_catalog.py
```

This rebuilds `site/catalog.json` and `site/gear.json` from the client's tables on [wago.tools](https://wago.tools).

## Tests

```bash
python -m unittest discover -b -s tests
node --test tests/*.test.js
pip install lupa
python tests/addon/nodes_sim.py
python tests/addon/scan_sim.py
```

## Notes

GitHub turns off scheduled workflows after 60 days without repository activity. If prices stop updating, re-enable the workflow from the Actions tab.

Item tooltips load from Wowhead when you hover over an item, and are cleaned before they go on the page. Icons load from Blizzard's image server, and favorites are saved in your browser only. To look at the page locally, copy the `data` branch into the git-ignored `site/data/` and serve `site/`.

World of Warcraft is a trademark of Blizzard Entertainment. This is an unofficial fan project.
