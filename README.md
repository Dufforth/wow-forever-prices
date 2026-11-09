# Forever Prices

A page showing WoW Forever auction prices for profession and gathering items, with price change alerts and crafting and disenchanting profit.

A GitHub Actions job checks Blizzard every 5 minutes and updates as soon as new prices appear, at least hourly. It reads every market from Blizzard's API, fills any gaps from the [public auctionhouse.fyi API](https://auctionhouse.fyi/docs/api), saves the prices on the `data` branch and publishes the page with GitHub Pages.

## Set up

1. Create a client at [develop.battle.net](https://develop.battle.net/access/clients).
2. Save its ID and secret as repository secrets:

   ```bash
   gh secret set BLIZZARD_CLIENT_ID
   gh secret set BLIZZARD_CLIENT_SECRET
   ```

Without them, the page still works using only the public source.

## Using the page

- **Auction House** browses everything listed, like the game's auction house: categories on the left, level, rarity and slot filters.
- **Prices**, **Favorites**, **Alerts**, **Profit** and **Disenchant** each keep their own category, search and filters.
- **Disenchant** has two parts: *Buy and disenchant* (gear for sale worth more as materials) and *Craft and disenchant* (recipes whose disenchanted materials are worth more than the reagents, with how many crafts the listed reagents cover).
- The page checks for new prices every minute and updates itself; changed rows light up briefly. The sun or moon button switches light and dark mode.

## How the numbers work

- **Lowest** is the cheapest unit. **Market** is the average of the cheapest 15% of units, which one unusual listing can't move as much. Player-scanned markets only have the lowest price.
- **Prices are asking prices**, not completed sales.
- **Most bought** is an estimate from falling quantities, because expired and cancelled listings look the same as sales.
- **Profit** is per craft. Reagents use the cheapest of auction, vendor or crafting them yourself, and selling on the auction takes off the 5% cut.
- **Disenchant values** are expected averages from the Classic tables, by item level, so check them in game.
- **Items with random bonuses** are left out of prices, and bind on pickup items can't be sold on the auction.
- **The vendor list** covers common trade-goods reagents only.

## The addon

The **Addon** button in the page's top bar downloads Dufforth Tweaks Helper, a gathering, disenchanting and crafting helper (tabs: Gather, Disenchant, Crafting). Its source is in `addon/DufforthTweaksHelper`, and every deploy builds the download from it, bundling Blizzard's latest prices for enchanting materials and disenchantable gear (`tools/build_addon_prices.py`), because addons can't reach the internet.

- **Herbs and ores:** when you track the other kind, shows a picture on every spot where you gathered that herb or ore before (no hovering needed) and on each dot you hovered, swaps tracking on a timer, and colors tooltips by your gathering skill (`/nk`).
- **Disenchant tooltips:** weapon and armor tooltips show the materials, chances, prices and average value of disenchanting them.
- **Disenchant window:** offers the next safe BoE item on one button. The game only allows one cast per click or key press, so it never disenchants on its own. It skips bound, Bind on Pickup, equipment-set, kept and locked items, anything above your quality or item level limit or Enchanting skill, and anything that sells for more on the auction house or to a vendor.
- **Menu and minimap button:** every setting in one window (`/dufforth`).

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
python tests/addon/de_sim.py
python tests/addon/menu_sim.py
python tests/addon/crafting_sim.py
```

## Notes

GitHub turns off scheduled workflows after 60 days without repository activity. If prices stop updating, re-enable the workflow from the Actions tab.

Item tooltips load from Wowhead when you hover over an item, and are cleaned before they go on the page. Icons load from Blizzard's image server, and favorites are saved in your browser only. To look at the page locally, copy the `data` branch into the git-ignored `site/data/` and serve `site/`.

World of Warcraft is a trademark of Blizzard Entertainment. This is an unofficial fan project.
