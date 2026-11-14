"""Reads Horde quests for the leveling route from the CMaNGOS Classic world database tables.

Repository: turns raw tables into route_model.Quest objects; nothing else touches the tables.
Positions are world points (map, x, y): givers and turn-ins at their spawn, objectives at the
group of spawns nearest the quest's giver (so the route goes to the closest monsters).
"""
from collections import defaultdict

from build_farm import as_dicts, num, SKIP_TITLE
from route_model import Goal, Quest

HORDE_RACES = 2 | 16 | 32 | 128  # Orc, Undead, Tauren, Troll
KINDS = {1: "group", 21: "life", 41: "pvp", 62: "raid", 81: "dungeon", 83: "legendary"}
REPEATABLE = 1
XP_PER_MAX_LEVEL_MONEY = 1 / 0.6  # Classic: at level 60 a quest pays 60% of its experience as money
CLUSTER = 250  # yards
CHESTS = (3, 25)  # chest, fishing hole
GUESSED_DROP_CHANCE = 30.0
# Monsters all over the map (zhevras, raptors in the Barrens): at least WIDE_COUNT spawns within WIDE_RANGE
# yards of the objective, and under WIDE_SHARE of them at its spot. Measured: Raptor Thieves 3% at the
# spot (135 spawns), Plainstrider Menace 20%, Harpy Raiders 96% (one camp).
WIDE_COUNT, WIDE_RANGE, WIDE_SHARE = 40, 2500, 0.4
MIN_DROP = 5.0  # %: a quest-starting item rarer than this isn't worth farming for a guide step


def _distance2(a, b):
    return (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2 if a[0] == b[0] else float("inf")


def nearest_cluster(points, anchor, radius=CLUSTER):
    """The middle of the spawns around the one nearest `anchor`, or None."""
    if not points:
        return None
    first = min(points, key=lambda p: _distance2(p, anchor)) if anchor else points[0]
    group = [p for p in points if _distance2(p, first) <= radius * radius]
    return (first[0], sum(p[1] for p in group) / len(group), sum(p[2] for p in group) / len(group))


ELITE_RANKS = (1, 2, 3)  # creature_template Rank: elite, rare elite, boss (4 = rare, not elite)
LOOP_RANGE, LOOP_CELL, LOOP_SPOTS, LOOP_MIN = 350, 80, 5, 4  # yards, yards, spots, spawns


def loop_points(points, spot):
    """Up to LOOP_SPOTS spots around `spot` where these spawns crowd, in walking order from the one nearest
    `spot` (a loop to circle while killing), or [] when there are too few spawns for a loop."""
    near = [p for p in points if _distance2(p, spot) <= LOOP_RANGE * LOOP_RANGE]
    if len(near) < LOOP_MIN:
        return []
    cells = {}
    for p in near:
        key = (round(p[1] / LOOP_CELL), round(p[2] / LOOP_CELL))
        c = cells.setdefault(key, [0, 0.0, 0.0])
        c[0] += 1; c[1] += p[1]; c[2] += p[2]
    ranked = sorted(([n, x / n, y / n] for n, x, y in cells.values()), key=lambda c: -c[0])
    picked = []
    for n, x, y in ranked:
        if all((x - a) ** 2 + (y - b) ** 2 >= (LOOP_CELL * 0.75) ** 2 for a, b in picked):
            picked.append((x, y))
        if len(picked) == LOOP_SPOTS:
            break
    if len(picked) < 2:
        return []
    order, here = [], (spot[1], spot[2])
    while picked:
        nxt = min(picked, key=lambda q: (q[0] - here[0]) ** 2 + (q[1] - here[1]) ** 2)
        picked.remove(nxt); order.append((spot[0], nxt[0], nxt[1])); here = nxt
    return order


def spread_out(points, spot):
    """True when these spawns are all over the map around `spot`, not in one camp."""
    near = [p for p in points if _distance2(p, spot) <= WIDE_RANGE * WIDE_RANGE]
    if len(near) < WIDE_COUNT:
        return False
    at_spot = sum(1 for p in near if _distance2(p, spot) <= CLUSTER * CLUSTER)
    return at_spot / len(near) < WIDE_SHARE


SUMMON_COMMAND = 10  # CMaNGOS dbscripts: summon a creature at x, y, z (datalong = creature entry)
SCRIPT_TABLES = ("dbscripts_on_spell", "dbscripts_on_event", "dbscripts_on_quest_start", "dbscripts_on_go_use",
                 "dbscripts_on_go_template_use", "dbscripts_on_gossip", "dbscripts_on_creature_death", "dbscripts_on_relay")


def instance_entrances(tables, area_triggers, maps=()):
    """{dungeon map id: (continent, x, y)}: where the teleport into it stands (areatrigger_teleport + the client's
    AreaTrigger positions), else the dungeon's corpse point from the client's Map table (you resurrect at the
    entrance; Forever's client lacks many entrance triggers, Wailing Caverns among them)."""
    out = {}
    for r in maps:
        corpse = int(num(r.get("CorpseMapID"), -1))
        if corpse in (0, 1) and int(num(r.get("ID"))) not in (0, 1) and (num(r.get("Corpse_0")) or num(r.get("Corpse_1"))):
            out[int(num(r["ID"]))] = (corpse, num(r["Corpse_0"]), num(r["Corpse_1"]))
    for r in as_dicts(tables.get("areatrigger_teleport", [])) if tables.get("areatrigger_teleport") else []:
        p = area_triggers.get(int(num(r["id"])))
        target = int(num(r["target_map"]))
        if p and p[0] in (0, 1) and target not in (0, 1):
            out[target] = p  # the real entrance trigger beats the corpse point
    return out


def summon_spots(tables):
    """{creature entry: [(x, y)]} where scripts summon it (a monster with no spawn of its own: Echeyakee,
    Ishamuhale...). Scripts don't name the map; the caller uses the quest giver's."""
    out = defaultdict(list)
    for name in SCRIPT_TABLES:
        for r in as_dicts(tables.get(name, [])) if tables.get(name) else []:
            if int(num(r.get("command"))) == SUMMON_COMMAND and int(num(r.get("datalong"))) and (num(r.get("x")) or num(r.get("y"))):
                out[int(num(r["datalong"]))].append((num(r["x"]), num(r["y"])))
    return out


class QuestRepository:
    def __init__(self, tables, npc_side, triggers=None, entrances=None):
        """npc_side(faction template id) -> "A", "H" or ""; triggers: area trigger id -> point;
        entrances: dungeon map id -> its entrance point (objectives inside are placed there)."""
        self.t, self.npc_side, self.triggers = tables, npc_side, triggers or {}
        self.entrances = entrances or {}

    def _index(self):
        t = self.t
        self.mobs = {int(r["Entry"]): r for r in as_dicts(t["creature_template"])}
        self.mob_spawns = defaultdict(list)
        for r in as_dicts(t["creature"]):
            self.mob_spawns[int(r["id"])].append((int(num(r["map"])), num(r["position_x"]), num(r["position_y"])))
        self.summons = summon_spots(t)
        self.objects = {int(r["entry"]): r for r in as_dicts(t["gameobject_template"])}
        self.object_spawns = defaultdict(list)
        for r in as_dicts(t["gameobject"]):
            self.object_spawns[int(r["id"])].append((int(num(r["map"])), num(r["position_x"]), num(r["position_y"])))
        self.items = {int(r["entry"]): r for r in as_dicts(t["item_template"])}
        # Who drops each item: monsters (quest-only drops too) and chests.
        owners = defaultdict(list)
        for entry, m in self.mobs.items():
            if int(num(m.get("LootId"))):
                owners[int(num(m["LootId"]))].append(entry)
        self.droppers = defaultdict(list)
        for r in as_dicts(t["creature_loot_template"]):
            if int(num(r["mincountOrRef"])) < 0:
                continue  # references to shared loot lists: not quest items
            chance = abs(num(r["ChanceOrQuestChance"])) or GUESSED_DROP_CHANCE
            for entry in owners.get(int(r["entry"]), []):
                self.droppers[int(num(r["item"]))].append((entry, chance))
        chest_items = defaultdict(list)
        for r in as_dicts(t["gameobject_loot_template"]):
            chest_items[int(r["entry"])].append(int(num(r["item"])))
        self.chests = defaultdict(list)
        for entry, o in self.objects.items():
            if int(num(o.get("type"))) in CHESTS:
                for item in chest_items.get(int(num(o.get("data1"))), []):
                    self.chests[item].append(entry)
        self.givers, self.enders = defaultdict(list), defaultdict(list)
        for kind, table, target in (("npc", "creature_questrelation", self.givers), ("npc", "creature_involvedrelation", self.enders),
                                    ("object", "gameobject_questrelation", self.givers), ("object", "gameobject_involvedrelation", self.enders)):
            for r in as_dicts(t[table]):
                target[int(num(r["quest"]))].append((kind, int(num(r["id"]))))
        self.trigger_of = {int(num(r["quest"])): int(num(r["id"])) for r in as_dicts(t["areatrigger_involvedrelation"])}
        self.starter_item = {int(num(i["startquest"])): entry for entry, i in self.items.items() if int(num(i.get("startquest")))}

    # -- places and names --
    def _point(self, who, near=None):
        kind, entry = who
        return nearest_cluster(self.mob_spawns.get(entry, []) if kind == "npc" else self.object_spawns.get(entry, []), near)

    def _name(self, who):
        kind, entry = who
        return (self.mobs.get(entry, {}) if kind == "npc" else self.objects.get(entry, {})).get("Name" if kind == "npc" else "name", "?")

    def _mob_info(self, entry):
        """(min level, max level), elite: for a goal's tip."""
        m = self.mobs.get(entry)
        if not m:
            return (0, 0), False
        return (int(num(m["MinLevel"])), int(num(m["MaxLevel"]))), int(num(m.get("Rank", 0))) in ELITE_RANKS

    def _mob_level(self, entry):
        m = self.mobs.get(entry)
        return (num(m["MinLevel"]) + num(m["MaxLevel"])) / 2 if m else 0

    def _horde(self, races, giver):
        if races:
            return bool(races & HORDE_RACES)
        if giver and giver[0] == "npc":
            m = self.mobs.get(giver[1])
            return not (m and self.npc_side(int(num(m["Faction"]))) == "A")
        return True

    def _unplaced_goals(self, r):
        """The objectives by name only (no place): for questline guides."""
        goals = []
        for k in range(1, 5):
            target, count = int(num(r.get(f"ReqCreatureOrGOId{k}"))), int(num(r.get(f"ReqCreatureOrGOCount{k}")))
            if target > 0:
                goals.append(Goal("kill", self.mobs.get(target, {}).get("Name", "?"), None, max(1, count)))
            elif target < 0:
                goals.append(Goal("use", self.objects.get(-target, {}).get("name", "?"), None, max(1, count)))
        for k in range(1, 5):
            item, count = int(num(r.get(f"ReqItemId{k}"))), int(num(r.get(f"ReqItemCount{k}")))
            if item and count and item != int(num(r.get("SrcItemId"))):
                goals.append(Goal("collect", self.items.get(item, {}).get("name", "?"), None, count))
        return goals

    def _goals(self, r, anchor, keep_unplaced=False):
        goals = self._placed_goals(r, anchor)
        if goals is not None or not anchor or int(num(r.get("Type"))) != 0:
            return goals
        # A normal quest whose objective has no place in the data (a summoned monster like Echeyakee, an object
        # with no spawn): put it at the giver and flag it, so the quest and the chain after it stay in the route
        # (user, 2026-11-14: both reference guides do Echeyakee's chain, worth thousands of experience).
        goals = []
        for g in self._unplaced_goals(r):
            g.point, g.guessed = anchor, True
            goals.append(g)
        return goals

    def _placed_goals(self, r, anchor):
        goals = self._placed_goals_raw(r, anchor)
        for g in goals or []:
            if g.point and g.point[0] not in (0, 1) and g.point[0] in self.entrances:
                g.instance, g.point, g.loop, g.wide = g.point[0], self.entrances[g.point[0]], [], False
        return goals

    def _placed_goals_raw(self, r, anchor):
        goals = []
        for k in range(1, 5):
            target, count = int(num(r.get(f"ReqCreatureOrGOId{k}"))), int(num(r.get(f"ReqCreatureOrGOCount{k}")))
            if target > 0:
                spawns = self.mob_spawns.get(target, [])
                if not spawns and anchor and self.summons.get(target):
                    spawns = [(anchor[0], x, y) for x, y in self.summons[target]]  # summoned by a script
                p = nearest_cluster(spawns, anchor)
                if p is None:
                    return None
                levels, elite = self._mob_info(target)
                goals.append(Goal("kill", self.mobs.get(target, {}).get("Name", "?"), p, max(1, count), self._mob_level(target),
                                  wide=spread_out(spawns, p), loop=loop_points(spawns, p), levels=levels, elite=elite))
            elif target < 0:
                p = nearest_cluster(self.object_spawns.get(-target, []), anchor)
                if p is None:
                    return None
                goals.append(Goal("use", self.objects.get(-target, {}).get("name", "?"), p, max(1, count)))
        for k in range(1, 5):
            item, count = int(num(r.get(f"ReqItemId{k}"))), int(num(r.get(f"ReqItemCount{k}")))
            if not item or not count or item == int(num(r.get("SrcItemId"))):
                continue
            sources = sorted(self.droppers.get(item, []), key=lambda s: -s[1])[:4]
            points = [p for entry, _ in sources for p in self.mob_spawns.get(entry, [])]
            points += [p for entry in self.chests.get(item, []) for p in self.object_spawns.get(entry, [])]
            p = nearest_cluster(points, anchor)
            if p is None:
                return None
            name = self.items.get(item, {}).get("name", "?")
            if sources:
                # The monster you'll actually kill there: most spawns at the spot (a rare one that always
                # drops it, like a named raptor, isn't the one to farm).
                def at_spot(entry):
                    return sum(1 for q in self.mob_spawns.get(entry, []) if _distance2(q, p) <= CLUSTER * CLUSTER)
                main, chance = max(sources, key=lambda s: (at_spot(s[0]), s[1]))
                kills = round(count / max(0.05, chance / 100))
                levels, elite = self._mob_info(main)
                goals.append(Goal("collect", name, p, max(1, kills), self._mob_level(main), self.mobs.get(main, {}).get("Name", ""),
                                  wide=spread_out(points, p), loop=loop_points(self.mob_spawns.get(main, []), p), levels=levels, elite=elite))
            else:
                goals.append(Goal("collect", name, p, count))
        qid = int(r["entry"])
        if qid in self.trigger_of:
            p = self.triggers.get(self.trigger_of[qid])
            if p is None:
                return None
            goals.append(Goal("explore", "the area", p, 0))
        return goals

    def _drop(self, item, anchor):
        """Where a quest-starting item drops: (point near anchor, monster, chance %) for its likeliest dropper."""
        sources = [(entry, chance) for entry, chance in self.droppers.get(item, []) if self.mob_spawns.get(entry)]
        if not sources:
            return None
        entry, chance = max(sources, key=lambda s: s[1])
        if chance < MIN_DROP:
            return None
        return nearest_cluster(self.mob_spawns[entry], anchor), self.mobs.get(entry, {}).get("Name", "?"), float(chance)

    def load(self, keep_unplaced=False):
        """keep_unplaced: also quests whose objectives have no place (their point is None), for questline guides."""
        self._index()
        self.keep_unplaced = keep_unplaced
        out = []
        for r in as_dicts(self.t["quest_template"]):
            title = (r.get("Title") or "").strip()
            if not title or SKIP_TITLE.search(title) or int(num(r.get("SpecialFlags"))) & REPEATABLE or int(num(r.get("RequiredSkill"))):
                continue
            qid, races = int(r["entry"]), int(num(r.get("RequiredRaces")))
            giver = next(iter(self.givers.get(qid, [])), None)
            ender = next(iter(self.enders.get(qid, [])), None)
            if not self._horde(races, giver) or not ender:
                continue
            start = self._point(giver) if giver else None
            item = self.starter_item.get(qid, 0)
            if start is None and not item:
                continue
            end = self._point(ender, start)
            if end is None:
                continue
            start_drop = ()
            if start is None and item:
                drop = self._drop(item, end)
                if drop:
                    start, start_name = drop[0], drop[1]
                    start_drop = (self.items.get(item, {}).get("name", "?"), drop[1], drop[2])
            goals = self._goals(r, start or end)
            if goals is None and keep_unplaced:
                goals = self._unplaced_goals(r)
            if goals is None:
                continue  # an objective we can't place: better left out than a step to nowhere
            out.append(Quest(
                id=qid, title=title, level=int(num(r.get("QuestLevel"))), min_level=int(num(r.get("MinLevel"))),
                start=start, start_name=self._name(giver) if giver else (start_drop[1] if start_drop else self.items.get(item, {}).get("name", "?")),
                end=end, end_name=self._name(ender), goals=goals,
                xp=int(int(num(r.get("RewMoneyMaxLevel"))) * XP_PER_MAX_LEVEL_MONEY), races=races,
                classes=int(num(r.get("RequiredClasses"))), kind=KINDS.get(int(num(r.get("Type"))), ""),
                prev=int(num(r.get("PrevQuestId"))), next_in_chain=int(num(r.get("NextQuestInChain"))),
                exclusive=int(num(r.get("ExclusiveGroup"))), start_item=item, timed=int(num(r.get("LimitTime"))) > 0,
                gear=[int(num(r.get(f"RewChoiceItemId{k}"))) for k in range(1, 7) if int(num(r.get(f"RewChoiceItemId{k}")))],
                start_drop=start_drop, money=max(0, int(num(r.get("RewOrReqMoney"))))))
        return out
