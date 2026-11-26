# Leveling route data: credit and licence

The leveling routes include **Forever's own quests** (the ones that exist only in WoW Forever), placed with data
from **RestedXP Guides** — <https://github.com/RestedXP/RXPGuides>, folder `Guides/forever` — which is licensed
**Creative Commons Attribution-NonCommercial-ShareAlike 4.0** (<https://creativecommons.org/licenses/by-nc-sa/4.0/>).

Taken from it, per Forever-only quest: its number and name, which faction it's for, the level of the guide part,
where it is picked up and handed in and who gives and takes it, and the spots where its objectives are done
(`tools/extract_rxp_forever.py`). No guide text, step order or tips were copied. Experience values are not
from RestedXP (they stand in from Classic quests of the same level).

Because of that licence, these files are shared under **CC BY-NC-SA 4.0** too: free to use, share and change for
non-commercial purposes, with credit to RestedXP Guides and to this project, and under the same licence:

- `catalog/forever_rxp_quests.json`
- `catalog/rxp_routes.json` (the order of RestedXP's Forever Horde guides, 1-60, main and dungeon; every leveling route follows it)
- `catalog/rxp_forever_route.json` (the steps of RestedXP's Forever Horde guide, 22-60, kept only to compare our routes with it; not in the addon)
- `reports/route-scorecard-22-60.json`
- `catalog/route.json`
- `addon/DufforthTweaksHelper/GuideData.lua`
- the Dufforth Tweaks Helper addon download that contains them

Most of Forever's own quests (Riverglades, Shen'dralas, Mount Hyjal, Zephras Isle and Forever's quests in the old
zones) come from **QuestieDB**, the database of the Questie addon — <https://github.com/Questie/Questie> — licensed
**GPL-3.0** (<https://www.gnu.org/licenses/gpl-3.0.html>): quest givers and hand-ins, objectives, the spawn places of
their monsters, objects and item droppers, levels, races, chain links and experience (QuestieDB's QuestXP tables,
gathered from players' clients), read from the installed addon by `tools/extract_questie_forever.py` into
`catalog/forever_questie_quests.json`. RestedXP's places are used only for the quests Questie can't place.

The rest of the route data comes from the CMaNGOS Classic database (GPL-3.0, see `catalog/route.json` "source") and
from the game client's tables (wago.tools). Nothing from Zygor Guides is used.
