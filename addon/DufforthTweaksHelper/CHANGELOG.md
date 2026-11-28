# Dufforth Tweaks Helper: changelog

Newest first. Every release on the website gets an entry here.

## 4.37.6 (2026-11-28)

- **Minimap button opens the window.** A left-click on the minimap button now always opens the Dufforth Tweaks
  Helper window, also while the guide is minimized. The minimized guide opens from its round icon on screen.
- **Alts tab: every character's rested XP.** A new top tab (`/dth alts` or `/dth rested`) lists this character and
  every alt below 60, one row each: name, level, rested XP now (amount and % of a level), the level it reaches,
  resting in an inn or city or outside, and time until full. Alts already full (rest wasted) are marked red and
  alts full within a day gold, with their names on top, so you know whom to log in. Hover a row for details.
  An alt shows after it logs in once with this version. (Replaces the "Rested" view of the class tab.)
- **Fix: characters with the same first name.** Rested XP was saved by first name only, so two characters
  named the same overwrote each other. Each character is now saved by its own id, with first and last name.

- **Cleaner guide box.** The target and quest item buttons now sit in a row under the guide box instead of a
  column on its left, so you see them even with the box at the left edge of the screen. The top strip keeps only
  the step arrows, Best, Menu and minimize: "Show step list" and "Back to my step" moved into the Menu.
- **Leveling log.** The addon now saves what you do while leveling, per character: quests (accepted, objective
  progress, completed, turned in, abandoned), level ups, hearthstone, flights, deaths and corpse runs, vendor, trainer
  and inn visits, zone changes, the guide's own moves (step done, skipped by hand, back, part change), idle and AFK
  time, and XP from kills vs quests and rested XP used. Each event has the time, your level, XP, zone, map position and
  the guide's route, part and step. It keeps the last 5,000 events per character and never writes to chat. See it in
  the Class tab under **Log** (on/off, what it kept, Clear). `tools/analyze_leveling_log.py "<game folder>"` reads it
  and reports time per guide part and step, steps skipped most, steps where you wandered off, deaths per zone, quests
  taken off the guide, dead time, and guide fixes. New file: restart the game fully.

- **The guide sits on the same step as RestedXP and reads like it.** When RestedXP runs next to it, the guide
  follows RestedXP's saved place (part, step and the side steps it closed), and steps are numbered per part the way
  RestedXP numbers them ("26-28 Ashenvale", step 36). Each line shows RestedXP's own text with its colours (monsters,
  friendly NPCs, loot, warnings) and icons, in RestedXP's order; lines RestedXP shows no text for are left out, and
  names replace quest and item numbers ("Abandon Jin'Zil's Forest Magic", "Etched Phial: 0/1").
- **The guide box is RestedXP's size** (about 230 px wide, was 340): no top strip or step counter (the "2899" was our
  own row number; the card already says "Step 6"), the card first, then one small line with the part and the time to
  level. Menu ("=") and minimize ("_") are small icons in the corner; Previous step, Skip this step and Best step for
  my level are in the Menu. Your saved box size starts over once.
- **No "Arrow on: Step 806" bar for the step you're on.** A click on a card no longer moves the arrow (every card is
  a step you're on, and the arrow already goes through them, like RestedXP). A step you pin from the list says
  RestedXP's number, and the bar stops short of the "=" and "_" icons.
- **Pins and the round icon use RestedXP's step number** in the part (the minimap showed "2870").
- **Cards are your active steps only**, side steps first, then yours with its "Step N" tag, like RestedXP's current
  steps frame; the steps ahead are in the list below, under the part's name and its group ("Speedrun Guide 22-30").
- **Each character has its own place in the guide.** Two characters of the same start used to share one pointer.
- **Fixed: the guide stuck at the end of a part** when a "travel with the next step" side step was still open (it
  waited at "24-26 Southern Barrens/Stonetalon" while RestedXP was already in Ashenvale).
- **Fixed: wrong zone names where two zone maps overlap.** A point is now placed on the zone map RestedXP names for
  it, so the river into Ashenvale no longer says "Azshara" (map pins and the arrow use the right zone map too).
- **Fixed: a character joining the guide mid-way was sent back** to the end of the previous part to finish its old
  side steps. Joining, picking a part or following RestedXP now stays on that part's first step.
- **The Money tab explains itself.** Each view has a one-line legend that says what to do and what the green number
  means. Vendor flips show the profit per item in exact coins ("+1s 7c each", "buy at 4s 83c, a vendor pays 5s
  90c") instead of the total for every listing; hovering a row gives the total if you buy them all and what to do.
  Underpriced, Crafts and Farming rows get the same exact coins and hovers. The view buttons are plain tabs (gold line
  under the open one) instead of red buttons. Flips under 1s an item are left out, and the money ideas are rebuilt
  from today's prices.
- **Fixed: tabs drawn past the close button.** With the Alts tab, your class's tab ("Paladin") ran past the X and
  out of the window. Every tab now fits left of the X at any window width: tabs are as wide as their names, shrink
  together when space is short, and a cut name shows in full on hover.
- **Fixed: "You're at your cap" showed twice** on the Professions tab (small and large). It shows once.
- **The Leveling tab is now called Professions** (Profesiones in Spanish): it plans profession skill-ups, not
  character levels. `/dth professions` opens it; `/dth leveling` and a saved "Leveling" tab still open it.
- **A cleaner, modern window.** Slate background with a thin border, a darker tab strip and footer with hairlines,
  grey text on closed tabs and white with a gold line on the open one. Every button in every tab is flat with a
  thin border instead of the game's red beveled one; section titles get a faint gold rule. On the Professions tab,
  Plan / Shopping list is a two-way toggle (the open view is highlighted, both stay clickable) and every price lines
  up in one money column, also next to rows with a Craft or Search button.
- **The guide box now looks and works like RestedXP's.** Each card lists every line of its step with its own check
  box: lines the game already counts as done are ticked and locked, the others you can tick and untick. The step
  list has one row per RestedXP step (its lines together, its check box ticks the whole step); steps for other
  classes or races are left out. The Guides menu lists each route (your start, with and without dungeons, and the
  other starts) with RestedXP's parts; a click on a part takes the guide to its first step.
- **Map and minimap pins at every point of your current steps**, numbered by step, the arrow's step in gold, with a
  line along each step's points. Points you reach go away. Minimap pins use HereBeDragons (Questie ships it).
- **Rare monster alert.** When a rare monster of your current steps shows on a nameplate (or under the mouse), the
  guide plays a sound and flashes the game's icon, once a minute per monster, and the target button goes for it
  first. Menu > Automation > "Sound for rare monsters" turns the sound off. No raid marks: RestedXP doesn't put
  them on Forever either.
- **Less memory.** At login only your start's routes stay loaded (about 17 MB of Lua memory instead of 45-60 MB).
  Picking another start in the Guides menu needs a /reload, and the menu says so.
- **Full rested XP in the guide's progress bar.** The game's XP bar stops at the end of your level; the bar now says
  how far all your rested XP reaches ("Rested to 23 + 83%") when there's room. Its hover gives the total, the share
  of this level, about how many kills of your level it covers (rested doubles kill XP), how long until it's full
  (4x slower outside an inn or city), and each alt's estimated rested and time until full. Estimates use Classic
  rules (5% of a level per 8 hours, 1.5 levels at most). New file: restart the game fully once.
- **The leveling guide follows RestedXP's Forever guide exactly.** Every step of RestedXP's chain for your start
  (Durotar, Mulgore, Tirisfal Glades), in its order: the same quests, hubs, flights, hearthstones and objectives,
  its optional steps included. Nothing of ours is added (no merged talks, extra flight steps, class quests or farm
  stops), and no step is skipped because a quest looks too low. A step without a RestedXP map point has no
  waypoint; a quest our data doesn't know keeps its step under its title. "Include dungeons" switches to
  RestedXP's dungeon guide.
- **The guide now moves you through the steps the way RestedXP does.** One saved step pointer that only moves
  forward: a step is done when all of its lines are done (take quests, objectives, hand-ins, go to a spot, train,
  buy, collect, use an item, learn a flight path, abandon a quest, grind to a level, circle a loop), or when its
  condition says it isn't for you right now. Side steps (along the way) stay on screen next to your step until
  done, and a step that needs one waits for it. Steps for other classes or races are left out. Each RestedXP step is
  one card with its step number. The arrow walks a step's points in order, and when you're dead it points at your
  corpse, or at the nearest Spirit Healer on a "die and respawn" step. Auto accept and turn-in now handle only the
  quests of the steps you're on (a choice of rewards is still always yours), and the guide skips the gossip
  RestedXP skips. The Target button and a "DTH Target" macro target every NPC and monster of your steps; the item
  bar puts the steps' items first. Skip and Back move the step pointer; "Continue from here" moves it to any step.
  New files: restart the game fully once.
- **One guide per start.** The Speed, Safe and Explorer styles are gone, and so is the Guide style row in the Menu.
- **No more advice of our own in the guide box.** The buy food/water, repair, train and class-quest reminders, the
  dungeon-quest, other-quests, Forever-quest and abandon-gray rows, and "Also here" are gone from RestedXP's routes.
  Questline guides (Cozy Sleeping Bag, attunements) are unchanged.
- **One button for your hunter.** The Class tab's Macro view now builds the **DTH Hunter** macro and keeps it up to
  date for the spells you know (after every fight, and when you learn a spell or a talent). Put it on your bar with
  "Put it on my cursor". It was built from 300 logged fights: Hunter's Mark once a fight (no modifier keys), then Summon Hawk, Summon Hawk (they work in melee too), Aimed Shot, Arcane Shot, starting over with a hawk on every pull (only one Aimed Shot per loop,
  early while you're still at range, because enemies reach you after about 6 s and Aimed Shot was interrupted 46% of
  the time after that), with Raptor Strike, Auto Shot and Mongoose Bite on every press. It always fits the game's
  255-character limit (your old macro was 256, so the game had cut its Auto Shot line). The fight log is still there.
- **DTH Hunter plans each pull.** Your pet attacks first, the first press summons a hawk, and Hunter's Mark goes on
  while the hawk cooldown runs. Between pulls the addon rewrites the order from the hawks you still have out, so a
  quick next pull starts with the mark and Arcane Shot instead of a third hawk. Aimed Shot is out of the button:
  farming fights are short, and it stalled the button in melee.
- **The DTH Hunter button shows the spell your next press casts** (Hunter's Mark, Summon Hawk, Aimed Shot,
  Arcane Shot, or Raptor Strike / Auto Shot when nothing else can go), grey when it can't go yet. The game's own icon
  only shows the first spell in the macro. Option "Show the next spell on the button" on the Macro view.
- **Hunter fight log keeps the whole fight.** In melee the game's Auto Shot repeat fails about 20 times every 0.1 s,
  and those lines filled the log within 11 s. They're now counted (`autoFails`), and a repeated error is listed at
  most once a second.
- **Hunter fight log: Auto Shot times.** Each fight now keeps the time of every Auto Shot, so
  `tools/analyze_hunter_fights.py` can measure whether Arcane, Aimed or Multi-Shot delays your next Auto Shot.

## 4.37.5 (2026-11-25)

- **Money tab.** A new tab with money ideas for your realm and faction at the latest auction prices: listings well
  under their usual price on items that sell every day (buy and post again), trainer and vendor recipes that sell for
  more than their materials, listings cheaper than what a vendor pays, and the open-world monsters whose drops are worth
  the most per hour. It shows how old the prices are; at the auction house, Search opens the item there and you buy
  with the game's own buttons. The ideas are worked out with each hourly price update (`tools/money_finder.py`) and
  come with the addon download. New files: restart the game fully.

- **Hunter pet guide.** Hunters get a "Pets" view on the Class tab: the best pets (solo leveling, tanking, groups),
  each family's health, damage and armor, its skills with the rank you can have now and the level of the next one, and
  the beasts of that family you can tame now (closest to your level, with zone and spot, rare and elite marked). It
  also lists the fast attackers you can tame (a tamed beast keeps its attack speed: Broken Tooth in the Badlands hits
  every 1.0 s). Beasts and family stats come from the Classic database (465 tameable beasts); skill ranks are Classic's
  and the guide says to check a beast with Beast Lore before taming. New files: restart the game fully.

- **Hunter fight log.** Hunters get a "Hunter fight log" view on the Class tab. It records your last 300 fights: every
  spell sent, cast, refused (with the error) or interrupted, each cast's target and how many Summon Hawks were out,
  Hunter's Mark per target (catches double marks), Mongoose Bite chances used or missed, Auto Shots, your pet, mana and
  whether you won. It never casts or changes your macro. `tools/analyze_hunter_fights.py` turns the log into numbers and
  advice (shared Hawk/Arcane cooldown use, wasted hawks, repeated marks, missed Mongoose Bites, interrupted Aimed
  Shots, "Target too close", mana). New file: restart the game fully.

- **Leveling routes now follow RestedXP's Forever guide.** Every route (Durotar, Mulgore, Tirisfal Glades; Speed, Safe
  and Explorer, with and without dungeons) takes RestedXP's order from 1 to 60: its quests, flights, hearthstones and
  where it sets your hearthstone, with our quest data for names and places and RestedXP's own map points where its guide
  has one (made for Forever, where some quest givers moved). Dungeon routes follow RestedXP's dungeon guide. Gaps: quests
  our data doesn't know and pick-ups with no place are left out; flight paths and other classes' quests are still added
  where you pass. Measured with the same time model: 22-60 now takes 65 h (RestedXP's own guide: 65 h; our old
  planner: 74 h) and 1-22 about 10.7-12.1 h (was 12.5-13.5 h). Safe routes now go through the same zones as Speed,
  including contested ones. Route data from RestedXP Guides, CC BY-NC-SA 4.0 (see LICENSE-DATA.md).

- **Guide no longer bounces between two "Go to" steps.** A wide objective left open in an earlier zone (done along the
  way until its hand-in) made "Go to The Barrens" and "Go to Dustwallow Marsh" take turns forever.

- **Warrior: two buttons, single target and AoE, that never mix.** "DTH Warrior" now only hits one enemy: Heroic Strike
  is its filler even in a group (no Cleave), and Whirlwind left it. The new "DTH Warrior AoE" macro only uses spells
  that hit everything around you: Thunder Clap (Battle), Whirlwind (Berserker), Revenge with a shield (Defensive),
  Cleave, Demoralizing Shout and Sweeping Strikes once a fight; no Rend, Heroic Strike, Mortal Strike or Sunder Armor.
  The Warrior tab has "Single target on cursor" and "AoE on cursor"; each button shows its own next spell, and the icon
  follows the AoE button and says "press DTH Warrior AoE" once 2 or more enemies are on you.

- **Flight time no longer runs over the zone title.** While flying, the bar refits every second: with little room it
  shows only "Landing in 1:40" instead of the whole "Flying to Camp Taurajo, The Barrens: landing in 1:40" on top of
  "17-20 The Barrens".

- **One-button Druid macro.** Druids get the "DTH Druid" macro on the Class tab, built like the Warrior's: one key that
  fights in the form you're in and never changes form. Bear: Maul every press, Enrage and Demoralizing Roar once a fight,
  Swipe in a group. Cat: Tiger's Fury once, then Rake, Claw x3 and Rip or Ferocious Bite. Caster: Faerie Fire and Moonfire
  once, then Wrath. Only spells you know; the addon rewrites it between fights. A 255-character macro can't hold everything,
  so Faerie Fire (levels 24-31) or Tiger's Fury (32+) is left out, and the tab says which. Same options as the Warrior:
  Put it on my cursor, the next spell on the button, the next-ability icon with your combo points, and a fight log. The icon
  flashes red for Bash (enemy casting), a heal (low health) and "press Claw once" when the target died just before the
  finisher. New file: restart the game fully.

- **Forever's new zones and quests in the leveling routes.** The routes now take 602 of Forever's own quests from
  Questie's Forever database (QuestieDB, GPL-3.0: real quest givers, monster places and experience), up from 150 placed
  with RestedXP's guides. Riverglades (36-44) and Mount Hyjal (55-60) are now in the zone plan, plus Forever's quests in
  the old zones (the Barrens from level 10, Tirisfal, Silverpine, Desolace...). Quests the data can't time stay out: an
  objective with no place, or work in the text ("Acquire 15 Silithus Venom Samples and 20 gold") with no objectives.
  Planner fixes: riding to a flight master is timed at mount speed from 40 (it was timed running), and a kill now takes
  30 s, measured from 287 of your solo fights (30-37 s with looting and walking; it was 20 s, which made grinding look
  better than questing: the Undercity route ground levels 15-28 in Hillsbrad instead of going to the Barrens). The
  routes now grind 1-4 levels instead of 6-9. Hours to 60 are higher because each kill now takes longer, so compare
  under the same 30 s kills: speed routes Durotar 93.4 -> 90.8, Mulgore 94.0 -> 92.8, Tirisfal 95.0 -> 93.4; with
  dungeons 97.5 / 98.7 / 99.4 -> 91.5 / 93.3 / 96.1 (under the old 20 s kills the same changes gave 73.2 / 73.9 / 74.5 ->
  72.1 / 72.9 / 71.6). 22-60 scorecard (its own model, unchanged): 71.4 / 71.7 / 73.0 -> 71.8 / 72.8 / 73.7 h (Zygor
  Forever 74.0, RestedXP Forever 90.6). Shen'dralas is in the plan but unused: its chain starts
  after Desolace's Magram quest "Ongeku" (not on the routes) and Questie has no objectives for most of its quests yet.
  Tried and not kept: hand-ins up to 400 yards off the way (better on the inflated data, ~1 h slower on the real data),
  weighing a whole zone across the sea before grinding (+1.5-3 h), handing in chain quests early, bigger batches and
  pick-up radius (no gain).

- **Routes from the guide log: no grinding steps, real sea crossings, which zeppelin.** From your three characters'
  logs: (1) the Speed and Explorer routes no longer tell you to grind a level (they had 3-9 such steps; grinding is the
  Grind tab, for when you're bored of quests). The Safe routes keep 2-4, at levels 27-35, where no quest fits outside
  the PvP zones. (2) A sea crossing now costs the way to the dock, the ride and the way on from the landing; it was a
  flat 10 minutes from anywhere, and your Barrens to Hillsbrad trip took about 35, so routes hopped between continents.
  (3) The zeppelin step says which one: "Go to Orgrimmar: Undercity zeppelin" (you boarded the Grom'gol one). The
  builder also plans each route with hand-ins across the sea waiting for the hubs on your continent and keeps the faster
  plan (Tirisfal: 17 -> 11 crossings at the same hours). Hours to 60 with the real crossings (30 s kills): Durotar 92.1,
  Mulgore 92.5, Tirisfal 95.4; with grinding allowed they'd be 93.1 / 93.7 / 94.4 with 5 grind levels each. Safe routes
  are 101-105 h with 24-33 sea crossings (few quests outside PvP zones and no grinding to fill the gaps).

- **No gray pick-ups.** Routes skip quests that are already gray (5+ levels below you) when you'd pick them up, unless their chain
  leads to a quest still worth doing. Gray hand-ins: Durotar 37 -> 21, Mulgore 48 -> 37, Tirisfal 76 -> 57 (Mulgore +0.3 h,
  Tirisfal +1.2 h to 60, Durotar unchanged).

- **Your step stays put until it's done.** Walking near another objective no longer switches the current step, so the box stops
  changing while you move.
- **Other quests in your log fold into one row** ("[+] 10 other quests in your log"); open it to list them.

- **The guide box fits the screen and stays in your zone.** The trip shows at most 6 cards (your step and the nearest ones, in route
  order), only from the zone you're in; "along the way" objectives from other zones no longer appear (Barrens steps showed in
  Hillsbrad).

### Sell or disenchant advice in tooltips
- **Fixed: the advice and the disenchant list didn't work on most PCs.** The game client has no `GetItemInfo` of its own;
  it only worked where another addon (GearQuest Forever) added it back. Both now use the game's own item lookup, and an item
  the game hasn't loaded yet is asked for and shows on the next hover.
- **One verdict line first:** "Best: Auction house 1g 20s", "Best: Disenchant ~85s" or "Best: Vendor 30s", in gold, green or
  gray, then short lines for the auction house (after the 5% cut), the vendor and disenchanting, with the prices aligned.
- **For every character and every item with an auction price**, not only weapons and armor. Disenchanting shows only when it's
  worth knowing; without the skill it says which Enchanting level it needs.
- Realms whose market isn't in the download (another region, for example) now use the closest prices for your faction.
- **New settings** in Disenchant > Settings: details or the verdict only, the disenchant odds, and details only while holding Shift.
- The Disenchant tab now shows for every character. **Craft to disenchant** shows for any Blacksmith, Leatherworker, Tailor,
  Engineer or Enchanter, so a crafter can make the gear and send it to a disenchanting alt. Without a crafting profession the
  tab holds only these tooltip settings; the disenchant list settings still need Enchanting.

### Disenchant list
- **Its own flat dark window**, in the addon's style, that opens beside the main window instead of on top of it, or where you
  last dragged it (remembered). A spot that's off your screen is ignored.
- Refreshes when the game finishes loading item details, so new PCs don't show an empty list.
- No chat messages: the keep list shows in each row's hover, and the in-combat notice shows on screen.

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
