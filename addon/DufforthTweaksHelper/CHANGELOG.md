# Dufforth Tweaks Helper: changelog

Newest first. Every release on the website gets an entry here.

## 4.37.4 (2026-11-15)

### One-click fishing
- **New Fishing tab, shown on characters that know Fishing.** One key, a double right-click or a click on the fishing bar casts;
  the same key hooks the fish once your bobber has landed (the bobber becomes the game's soft interact target, all around you and
  as far as a cast lands). Click **Set a key** and press any key (Shift, Ctrl and Alt work; with Space, Shift+Space still jumps);
  right-click it to clear. The key casts when you let it go, waits for the bobber, and never changes while held, so it can't get
  stuck or talk to someone nearby. It's only taken while you can fish and never in combat; otherwise it keeps its normal use.
- **Double right-click:** a quick right-click on open water, then a second one, casts while a pole is in your hands. Holding the
  second click turns the camera as usual; right-clicking people, monsters or lootable things stays normal; never while the line is out.
- **Perks, each with its own switch:** fishing gear (your best pole and any fishing hat, boots, gloves or trinket from your bags, read
  from their tooltips; your weapons and gear go back 90 seconds after your last cast, after a fight, or with the Weapons button), your
  best lure when the pole has none, auto loot, a louder splash (effects at full; music, ambience, voices and error speech off), a mark
  on your own bobber, the fishing bar (skill and pole bonus, lure time, catches; lock it or place it with Move pieces), a card with
  what you caught and its worth (or First catch!), and sounds for a catch, a fish that got away, and time to cast again.
- Your settings come back when you stop fishing (even after a /reload), except any you changed yourself meanwhile.
- **Fishing food:** when you have no fishing buff, the press eats the best food in your bags that gives Fishing (read from its
  tooltip) before casting.
- **Fished-up chests:** opening a chest, crate or clam you caught this session adds its coins and items to the session.
- **Keys and sound view:** a jump key while fishing (when the fishing key is Space; Shift+Space at first), a lure key (your best
  lure on now), a gear key (fishing gear on, or your weapons back), and the volumes while fishing: game volume (yours unless set),
  sound effects, music and ambience (0 turns that sound off).
- **Codex view:** what bites in each zone and its named places, with the chance per catch, what it's worth, which ones open, and
  what you caught there yourself (also fish the list doesn't have). Browse zones with < and >, Here goes back to yours.
  From the CMaNGOS Classic database (`catalog/build_fishing.py`, new file FishingData.lua): Forever may differ.
- Counters: this session's casts, catches, catches an hour, fish that got away, time to a bite and what the catch is worth (auction
  house, else vendor), kept over a /reload; per zone, casts, catches and the Fishing skill the zone needs (learned from the game's
  message); and an all-time count.
- Never acts in combat and never writes in chat. Warns when Gaap One-Key Fishing is on too.
- Ideas from Mastercraft's Angler (a Forever addon, All Rights Reserved): read for its features only, written from scratch here.
- New files (FishingData.lua, Fishing.lua): **exit the game fully and start it again**, a /reload is not enough.

### Grind spots
- **New Grind tab: the best places in the world to kill monsters for your level, class and spec.** About 900 open-world spots
  (levels 1-62) from Classic spawn and loot data. Each row shows the monsters and their levels, the zone and spot, experience a
  kill, kills an hour, time to your next level (rested experience counted) and experience or gold an hour. Switch between
  **Experience** and **Gold** to sort by either. Gold counts coins, vendor trash and the drops worth selling at their auction price.
- **Best** marks easy, close-packed spots among the most experience an hour for you. **Not for you** marks spots that don't suit
  your spec, with the reason: casters (for example arms and fury warriors, paladins and mages), packs (for classes that can't
  handle several at once), elites, or monsters above your level. Monsters that heal or run away get a note. The other faction's home
  zones sort after yours.
- **Your spec**: Forever doesn't tell addons your talents, so the tab asks once which spec you play (druids: Balance, Feral cat,
  Feral bear or Restoration) and remembers it for that character. Change it any time with the Spec button.
- Click a row for the guide's arrow and a map pin on the spot; hover it for every number behind it.
- **Clearer Grind list.** Only monsters that give you experience and are within 2 levels of you are listed, never gray ones.
  The list starts with **Best right now** (the best spot for experience, for gold and balanced) and then groups spots by zone
  under headers you can fold. Camps of the same monster in a zone are one row (click again for the next camp). Each row shows
  the monster's picture (its 3D portrait, or an icon for its kind), its levels in the game's difficulty colors and a short
  line. New **Monsters** view: each zone's monsters with their experience and worth a kill; click one to see its drops
  underneath (hover a drop for the item, click it at the auction house to search it). Town guards are no longer listed.
- **Balanced, Experience or Gold.** Balanced (the default) ranks spots by the best mix of experience and gold an hour; Experience
  or Gold puts one first. Gold also looks at easy monsters up to 10 levels below you, Balanced up to 3.
- **Experience boosts before you start.** A line in the tab says what's on and what you could still use: the Elixir of Endless
  Experience (+200% for 1 hour), Well Fed food (+5% kill experience: the best in your bags, or the best to buy) and your rested
  experience. Picking a spot shows a movable reminder with a button that uses the elixir. The rates count the boosts you have on.
- **It learns from your kills.** Every kill that gives experience is saved (monster, level, type, rank, whether it cast, fight
  time, time since the last kill, experience and rested bonus, place, your level and spec). `tools/tune_grind.py` reads them after
  a /reload, keeps every kill in a history file on the PC, fits Forever's real lower-level experience, each spec's kill speed and
  rest time, and which monsters really cast, and rebuilds the tab's data with what it learned. If the game doesn't send the
  "dies, you gain N experience" line, the kill is taken from the experience bar instead. When there are no kills, the script
  says why (the new files aren't loaded yet, no fights in that session, or kill lines it couldn't read).
- Monsters below your level are counted with Forever's lower experience (4% less a level, at most 20%).
- New files (GrindData.lua, Grind.lua): **exit the game fully and start it again**, a /reload is not enough.

### Spanish
- **The addon speaks Spanish on Spanish clients.** On esES and esMX clients every window, tooltip, button, menu row, guide step,
  errand and arrow text is in Spanish; any other client language stays English. Quest titles and objective names come from the game,
  so they show in your client's language; NPC and item names in the guide stay English.
- **The guide works on a Spanish client.** Zones are recognised by map ID (the game gives Spanish zone names), objectives are matched
  by kind, order and count when the game's text is Spanish, and flight paths and the hearthstone map Spanish zone names back. Not yet:
  the warrior button's macro uses English spell names, so on a Spanish client it can't be built yet.
- New files (Locale.lua, LocaleES.lua): **exit the game fully and start it again**, a /reload is not enough.

### Leveling guide
- **Quests on zone borders point to the right place.** The Witchwing harpies for Harpy Raiders are in the Barrens now, not on the
  Stonetalon map, so the guide no longer sends you to a flight master while you stand next to them. 70 border spots were fixed the same way.
- **No flight for a short trip.** A step less than about 1,500 yards away on the same continent gets no flight or boat directions.
- **NPCs up a tower or underground.** When a quest NPC stands a floor or more above or below the ground (Darsok Swiftdagger on top of
  the Crossroads tower), the step says so and the arrow shows a big up or down arrow with "Go up" or "Go down" instead of
  "You are here". It says "You are here" once you target the NPC.
- **Step numbers on the world map.** Each place of the next 15 steps gets a round pin with the guide's step number; your current step is
  gold. Hover a pin to see what to do there, click it to open that step. Pins that would touch become one.
- **Back to your step.** After clicking a class, dungeon or Forever quest, a bar says "Arrow on: ..." with a "Back to my step" button,
  and the game's map pin follows the arrow both ways. The map pin button, the step arrows, Best, Skip and Back also bring the arrow
  back to your step.
- **The progress bar doesn't overlap when the box is narrow.** Less important parts drop out first.
- **Quests in batches, like RestedXP and Zygor.** The routes now collect quests from nearby givers (up to 1,200 yards, when their
  objectives are near the trip and worth the walk) before heading out, so one trip does several quests: more objectives per
  hand-in round and fewer single-quest trips, about as fast overall. The box shows every objective in the area (within about
  10% of the map, plus monsters found all over the zone) as one block instead of one at a time.
- **Step numbers on the world map, drawn the way Questie draws its icons.** With Questie installed, the pins go through the
  HereBeDragons map library, so they show wherever Questie's icons show. Only the next 10 steps, and only the number (outlined,
  gold for your current step), with no circle hiding the map.
- **One row per step, in route order.** Steps are no longer grouped: each has its own card with its own step number, in step order;
  the step the arrow points at has the gold header, the lighter background and the directions. The
  trip's cards (every objective until the next hand-in) always show, even in a small box; the next steps appear while they fit.
- **The whole trip at once, laid out like RestedXP.** The top block lists every objective of this trip (until the next hand-in or
  pick-up, plus monsters all over the zone), each with its progress, even when the box is small. Make the box bigger and the part's
  numbered steps fill the space below; class, dungeon and your own quests sit at the very bottom.
- **Routes planned for Forever's 40-quest log** (Classic's was 20). The guide log records the size the game reports, to confirm it.
- **No long walk for a single quest.** A far objective with nothing else of yours near it waits (up to 3 levels) until you can take
  the quests around it, so you do them in one trip; it's only done alone when nothing else is left. Fewer lonely trips (Mulgore 47 ->
  34) and slightly faster Horde starts (Mulgore 74.0 -> 73.6 h to 60). Each route is planned with and without this rule and the
  faster plan is kept, so no route gets slower (the Undead route keeps its old plan).
- **No jump across the map after a hand-in.** "Nearest objective first" now uses the real place of each objective (Questie's when our
  data only guessed it), so a quest like Ishamuhale no longer jumps ahead of your route because its guessed spot was where you stood.
- **Waypoints only for quests.** Errands (buy water, train, repair) no longer take the arrow from your step; they stay as rows in the
  box, and a click on one points the arrow there.
- **No elite dungeon quests without dungeons.** With dungeon quests off, routes no longer take dungeon quests whose objectives are
  elite, even outside the instance (Deviate Hides at the Wailing Caverns entrance).
- **The guide box kept refreshing after a game change.** The game can hide your running speed from addons; the arrow's time estimate
  now handles that instead of stopping the box with an error.
- **Steps that wait on another are gray.** A hand-in whose objectives aren't done yet (or a pick-up whose earlier quest isn't
  finished) shows a gray question mark, gray text and "after step N".
- **Your whole quest log, not just the route.** Under your step, "Also here" lists other quests in your log with objectives at the
  same spot, on the same monsters or all over the zone, with their progress. Quests the route doesn't plan (like Chen's Empty Keg,
  which starts from a random drop) get a "Your quest" row: a click points the arrow at the next objective, or at the NPC once it's done.
- **Questie's icons.** With Questie installed, steps use its yellow icons (a gear to use, a sword to kill, a bag to loot), the same as
  on its map.
- **Questie integration.** When the guide's data has no place for a quest in your log, it asks Questie (if installed) where the
  objective's monsters, objects or item drops are, nearest to you first. Route steps without a place (like Echeyakee, summoned with a
  horn) also take Questie's spot, with the pin and the arrow.
- **A guide log for solving problems.** The addon keeps the last 500 lines of what the guide does (steps, where the arrow points
  and why, map drawing, quests, zones, levels, errors) and every settings change in its saved file.
- **The waypoint arrow can't be hidden by accident.** A right-click on it no longer turns it off (Menu > Waypoint arrow does), and an
  arrow turned off that way comes back once after the update.

- **Lighter menus and buttons.** The right-click step menu uses slim text rows like the main Menu and closes a moment after the mouse
  leaves it (or on a click elsewhere); buttons are light so their text stands out.
- **The right boat or zeppelin.** Directions pick the boat or zeppelin by real distance (walk to the dock plus from the landing to the
  step): from the Barrens to Hillsbrad it's the Orgrimmar zeppelin to Undercity, not the boat to Booty Bay and a run up the continent.
- **Less text.** Directions are one line ("Route: Go to Orgrimmar (zeppelin) > Zeppelin to Undercity > Fly to Hillsbrad Foothills"),
  without coordinates (the arrow points at each leg), and step notes are short ("Lvl 16-18, ~6 kills, 5 spots on the map").
- **Questline guides keep every quest.** The Cozy Sleeping Bag guide said "Route finished" at level 20: its level-14 quests counted
  as not worth your time, a rule meant only for the leveling route.
- **Click a step to pin it; right-click for options.** A click puts the arrow and the map pin on that step ("Back to my step"
  returns); a right-click offers Put the pin and arrow here, Mark done / Undo done, Continue from this step, Back to my step.
- **Use-the-item hint.** A step whose quest has an item to use shows the item's icon and "Use <item> on the objective", and the
  item's button comes first on the bar next to the guide.
- **Flights: ask first, and time left.** Auto flight asks Yes/No before flying. While you fly, the guide shows when you land, from
  the distance at first and from your own past flights on that route afterwards.
- **Cozy Sleeping Bag quests are level 14**, not 40 (the chain starts at 14; the later parts still say which areas need 20 or 30).

### Disenchant tab
- **Craft to disenchant comes first**, before Settings.
- **Materials under each item**, indented, with how many, where they come from and their price.
- **Search buttons** on the items and materials at the auction house or a vendor, like the Leveling tab.
- **Craft button** on each item while that profession's window is open ("Craft (3)" = how many you can make).
- **What you have** next to each material ("(have 5)", green when it's enough for one craft, red when short), and the row text no
  longer overlaps.

## 4.37.3 (2026-11-14)

### Leveling guide
- Routes from 1 to 60 with Forever's own quests and zones (quest places from RestedXP's Forever guides, CC BY-NC-SA 4.0).
- Three guide styles, each with or without dungeons: Speed, Safe (avoids high-PvP zones) and Explorer (flight paths, unique rewards,
  gold farming).
- Round "D" icon when the guide is minimized (also the minimap button); a minimize button; hiding in combat works.
- Steps view of the current part, with "Continue from here" and "Back to my step".
- Quests are only accepted and handed in automatically when they're in the guide's route; rewards with a choice are only suggested.

### Professions
- Profession data checked against Forever's own: Elixir of Minor Strength no longer comes free with Alchemy, and 25 other errors fixed.
- Earlier plan steps can be shown; materials you can craft list their own materials, folded until you open them.
