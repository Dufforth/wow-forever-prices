# Forever Prices

A page showing WoW Forever auction prices for profession and gathering items, with price change alerts and crafting and disenchanting profit.

A GitHub Actions job runs every hour. It reads the auction houses from the Battle.net API, saves the prices on the `data` branch and publishes the page with GitHub Pages.

## Set up

1. Create a client at [develop.battle.net](https://develop.battle.net/access/clients).
2. Save its ID and secret as repository secrets:

   ```bash
   gh secret set BLIZZARD_CLIENT_ID
   gh secret set BLIZZARD_CLIENT_SECRET
   ```

3. Run the **Update prices** workflow from the Actions tab, or wait for the next hour.

## How the numbers work

- **Market** is the average of the cheapest 15% of units for sale. **Lowest** is the single cheapest unit.
- **Prices are asking prices**, not completed sales. Blizzard's API gives no sales.
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
node --test tests/calc.test.js
```

## Notes

GitHub turns off scheduled workflows after 60 days without repository activity. If prices stop updating, re-enable the workflow from the Actions tab.

World of Warcraft is a trademark of Blizzard Entertainment. This is an unofficial fan project.
