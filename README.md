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
- **Prices**, **Favorites**, **Alerts**, **Profit**, **Disenchant** and **Farming** each keep their own category, search and filters.
- **Farming** lists items worth farming from monsters that sell on the auction house: money per kill, drop chance, the best monster with its level, zone and map coordinates, sales in the last 7 days and the quests that ask for the item. Drop data comes from the open [CMaNGOS Classic database](https://github.com/cmangos/classic-db) and is built once by `catalog/build_farm.py` into `site/farm.json`; it's a Classic estimate.
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
- **Farming values** use Classic drop chances, so Forever can differ. Zones for spawns near zone borders are worked out from nearby quest monsters and can occasionally be wrong.

## The addon

The **Addon** button in the page's top bar downloads Dufforth Tweaks Helper, a gathering, disenchanting, crafting, profession leveling and warrior helper (tabs: Gather, Disenchant, Crafting, Leveling, Zone, and one named after your class). The Leveling tab plans the cheapest way to level a crafting profession from your skill to your cap: for each skill point it picks the recipe with the lowest (materials - selling back, at most 80% of materials) / chance of a point, adds what learning an unknown recipe costs (trainer fee, vendor or auction recipe), and says which trainer or vendor of your faction teaches or sells it, with zone and map coordinates (trainers in a capital city first; an NPC standing inside a capital's map is placed in that capital) (Classic estimates from CMaNGOS, `catalog/build_leveling_sources.py` into `catalog/leveling_sources.json`; `tools/build_addon_leveling.py` writes `LevelingData.lua` at deploy). The Plan view lists each step with its materials under it (amount for the step, per craft, where cheapest, price, and have/need such as 60/78, with your bags shared out step by step). A Shopping list view lists the recipes to learn and every material to buy, with amounts, where each is cheapest and the price; `/dth shopping` opens it. One button next to the views fits where you are: at a vendor, **Buy N items** buys what you still need from it (minus your bags, only when it is no dearer than the list, total shown first); at the auction house, every material row (and any recipe sold there) gets a **Search** button that opens that exact item by its ID in the game's auction house, and you buy with the game's buttons; at a vendor, rows it sells get the same button, and clicking one turns the vendor window to that item and lights it up; every plan step has its own **Craft** button: with your profession window open it reads **Craft N** and crafts that step as many times as it needs or your materials allow; otherwise it says why (Craft greyed out until the window is open, Learn for a recipe you don't know, No mats). Talking to a trainer makes **Learn** active on the steps that trainer can teach you now (the hover says when your skill or level is too low, or the trainer doesn't teach it). Material rows say where each is cheapest as a short colored word: AH in orange, Vendor in blue. Craft only crafts what your bags can hold (free normal-bag slots times the product's stack size, plus room in your stacks of it) and says Bags full when nothing fits. While a batch crafts, a framed progress bar (blue while crafting, green when done, red when stopped) in place of the summary lines shows crafts done of the total, the time left, and when your bags will be full (measured pace after two crafts, the cast time plus a short gap before that). A step whose recipe is an item says **Search** (active at the auction house, or at a vendor selling it) instead of Learn. Opening a profession window opens the Leveling tab on that profession (Forever doesn't always name the window, so the recipes in it tell which profession it is) and closing it closes the window again if it opened it (checkbox **Open with my profession window**, on by default; Mining's smelting is skipped). The Zone tab starts with **New spells to train**: your spellbook's spells and ranks against what your class trainer teaches at your level (`catalog/build_class_trainers.py` writes `catalog/class_trainers.json` from CMaNGOS trainer lists mapped through Classic's learn-spell effects; carried in `ZoneData.lua`), with the cost and the nearest trainers of your side; the same list is printed in chat at login and at each level-up. The Zone tab then says what's worth doing where you are, for your level, side and class: quests started by an item a monster drops (easy to miss), rare monsters near your level with their notable drops, the quests with the most experience you haven't done (giver, coordinates, reward; ones in your log or needing an earlier quest are marked), and the monsters worth the most per kill at bundled prices. Clicking a row puts a pin on your map; at the auction house item rows get a Search button. Classic estimates from CMaNGOS (`catalog/build_zone_guide.py` writes `catalog/zone_guide.json`; `tools/build_addon_zones.py` writes `ZoneData.lua`). The class tab also has a **Gear** view: upgrades for each slot you wear, from the auction house (gear the price data covers, at or up to 8 levels below yours, `tools/build_addon_gear.py` writes `GearData.lua`) and from the gear rewards of quests you can do now (your level, side and class, not done). Stats come from the game itself (`C_Item.GetItemStats`); points are each stat times your class's weight, weapon damage per second x 14 attack power, and armor; rings and trinkets are compared with your weaker one, two-handers only against a two-hander, shields against your shield. The class tab (named after your class) lists consumables worth buying while you level: Forever's Well Fed foods (each gives a stat plus kill experience), elixirs, flasks, scrolls, potions, and weapon buffs (sharpening stones for axes, polearms, swords and daggers; weightstones for maces, staves and fist weapons; wizard and mana oils on any weapon; read from the game's SpellItemEnchantment and SpellEquippedItems tables and matched to your main-hand weapon), only those that help your class and that your level can use, with the cheaper of the AH and vendor price. Each buff is scored as stat x a rough class weight (Strength counts 1 for a warrior), compared per gold per hour (potions per use), and items that replace each other are grouped (one food, one flask, one elixir or scroll per stat; potions share a cooldown). At the auction house each row has a **Search** button. Out of combat, when you aren't Well Fed, a click-to-eat button shows your best food in your bags for your class (Forever's Well Fed adds +5% kill XP); a checkbox in the consumables view turns it off. A **Use together** set at the top picks the best of each group that stacks. The effects come from the game's spell tables (`catalog/build_consumables.py` writes `catalog/consumables.json`; `tools/build_addon_consumables.py` writes `ConsumablesData.lua` at deploy). For warriors the class tab also has the macro, with a button to switch. The warrior macro keeps a one-button `DTH Warrior` macro up to date between fights and shows an icon of what the next press casts; it never casts anything by itself. It also logs your last 300 fights (casts with rage, target health and enemy count, errors, who hit you, result) in its SavedVariables file, to tune the macro from real fights. Its source is in `addon/DufforthTweaksHelper`, and every deploy builds the download from it, bundling Blizzard's latest prices for enchanting materials and disenchantable gear (`tools/build_addon_prices.py`), because addons can't reach the internet. `python tools/archive_warrior_fights.py` copies new fights into a history file on your PC (outside the repo, `../warrior-history/fights.jsonl`) that keeps every fight; `tools/read_warrior_log.py` runs it first. Each fight also saves its damage per spell from the game's damage meter (`spellDamage`), and `python tools/analyze_warrior_fights.py` (pandas) turns the history into a per-spell table (casts, damage, per cast, per rage) plus fights where the button got stuck on one spell; `--csv folder` writes the full tables.

- **Herbs and ores:** when you track the other kind, shows a picture on every spot where you gathered that herb or ore before (no hovering needed) and on each dot you hovered, swaps tracking on a timer, and colors tooltips by your gathering skill (`/nk`).
- **Disenchant tooltips:** weapon and armor tooltips show the materials, chances, prices and average value of disenchanting them.
- **Disenchant window:** offers the next safe BoE item on one button. Its status line adds up the ticked items: the expected materials' value after the auction cut and about how long disenchanting them all takes (learned from your own pace); hover it for each material and amount. The game only allows one cast per click or key press, so it never disenchants on its own. It skips bound, Bind on Pickup, equipment-set, kept and locked items, anything above your quality or item level limit or Enchanting skill, and anything that sells for more on the auction house or to a vendor.
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
python tests/addon/leveling_sim.py
python tests/addon/warrior_sim.py
python tests/addon/warrior_fight_sim.py -v
```

## Notes

GitHub turns off scheduled workflows after 60 days without repository activity. If prices stop updating, re-enable the workflow from the Actions tab.

Item tooltips load from Wowhead when you hover over an item, and are cleaned before they go on the page. Icons load from Blizzard's image server, and favorites are saved in your browser only. To look at the page locally, copy the `data` branch into the git-ignored `site/data/` and serve `site/`.

World of Warcraft is a trademark of Blizzard Entertainment. This is an unofficial fan project.
