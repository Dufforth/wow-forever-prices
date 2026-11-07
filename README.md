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

## After a game patch

```bash
python catalog/build_catalog.py
```

This rebuilds `site/catalog.json` and `site/gear.json` from the client's tables on [wago.tools](https://wago.tools).

## Tests

```bash
python -m unittest discover -s tests
node --test tests/*.test.js
```

## Notes

GitHub turns off scheduled workflows after 60 days without repository activity. If prices stop updating, re-enable the workflow from the Actions tab.

Item tooltips load from Wowhead when you hover over an item, and are cleaned before they go on the page. Icons load from Blizzard's image server, and favorites are saved in your browser only. To look at the page locally, copy the `data` branch into the git-ignored `site/data/` and serve `site/`.

World of Warcraft is a trademark of Blizzard Entertainment. This is an unofficial fan project.
