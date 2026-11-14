"""Plans a leveling route that keeps walking short. Pure: no files, no network.

Parts, each with one job and injected into the planner (so they can be tested alone and swapped):
  Eligibility  which quests a character can take now (level window, race, chains, groups)
  XpModel      Classic experience for quests and kills, and leveling up
  TravelModel  seconds to get from one place to another
  HubScorer    strategy that rates a quest hub: experience per second of walking and work
  ZonePlan     strategy: which zones fit each level band (so the route doesn't hop the world)
  RoutePlanner simulates a character: hubs, accepting, nearest objective first, turn-ins
"""
import math
from collections import defaultdict
from dataclasses import dataclass

from route_model import Step

XP_TO_LEVEL = [0, 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400, 16000, 17700,
               19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400, 50800, 54100, 57700,
               61000, 64900, 68200, 71900, 75300, 79100, 82800, 86800, 90600, 94500, 98600, 102700, 106800, 111000, 115200,
               119500, 123800, 128200, 132600, 137000, 141600, 146200, 150800, 155500, 160300, 165200]


def distance(a, b):
    if a is None or b is None or a[0] != b[0]:
        return math.inf
    return math.hypot(a[1] - b[1], a[2] - b[2])


class XpModel:
    def quest_xp(self, full, quest_level, player_level):
        """Full experience up to 5 levels above the quest, then 80, 60, 40, 20 and 10%."""
        diff = player_level - quest_level
        if diff <= 5:
            return full
        return full * {6: 0.8, 7: 0.6, 8: 0.4, 9: 0.2}.get(diff, 0.1)

    def kill_xp(self, player_level, mob_level):
        if mob_level <= 0:
            return 0
        base = player_level * 5 + 45
        diff = mob_level - player_level
        if diff >= 0:
            return base * (1 + 0.05 * min(diff, 4))
        gray = player_level - (5 if player_level < 40 else player_level // 10 + 1)
        if mob_level <= gray:
            return 0
        zero = 5 if player_level < 8 else 6 if player_level < 10 else 7 if player_level < 12 else 8 if player_level < 16 else \
            9 if player_level < 20 else 10 if player_level < 30 else 11 if player_level < 40 else 12 if player_level < 45 else \
            13 if player_level < 50 else 14 if player_level < 55 else 15
        return base * (1 - (player_level - mob_level) / zero)

    def add(self, level, current, gained, max_level=60):
        """(level, experience into it) after gaining some."""
        current += gained
        while level < max_level and current >= XP_TO_LEVEL[level]:
            current -= XP_TO_LEVEL[level]
            level += 1
        return level, current


class TravelModel:
    RUN, MOUNT, MOUNT_LEVEL = 7.0, 10.5, 40  # yards per second; Classic mount at 40
    SHIP = 300                               # seconds on top of walking to the dock: boat or zeppelin wait and ride (about 10 min in all)

    def seconds(self, a, b, level):
        d = distance(a, b)
        if d == math.inf:
            return self.SHIP + 300
        return d / (self.MOUNT if level >= self.MOUNT_LEVEL else self.RUN)


class Eligibility:
    ABOVE, BELOW = 3, 6  # quest levels taken: up to 3 above you, down to 6 below (80%+ of their experience)
    # From level 22, a wider window: quests up to 5 above and 8 below you. Scored on the 22-60 scorecard
    # (2026-11-14): 76.8 h -> 71.9 h, 1-22 unchanged (the low-level window stays 3 above, 6 below).
    ABOVE_HIGH, BELOW_HIGH, HIGH_FROM = 5, 8, 22
    MAX_SPREAD = 3000    # yards: objectives farther from the giver send you too far (big zones span about this)

    GROUP_SOLO = 3       # an elite (group) quest is soloable this many levels above it
    dungeons = False     # the "with dungeons" route takes dungeon quests too
    STRETCH = 4          # with nothing else to do, quests this many levels above you before grinding

    def spread_ok(self, q):
        """Objectives near enough; the turn-in anywhere (deliveries, even to another continent, are
        done when the route goes there, and the hub score counts the trip)."""
        return all(distance(q.start, g.point) <= self.MAX_SPREAD for g in q.goals)

    def available(self, q, level, done, active, race_bit, groups, stretch=False):
        if q.id in done or q.id in active:
            return False
        if q.races and not q.races & race_bit:
            return False
        if q.classes or q.timed or (q.start_item and not q.start_drop) or q.start is None:
            return False  # class, timed and item-started quests are offered separately
        outside = q.kind == "dungeon" and q.goals and all(g.point and g.point[0] in (0, 1) and not g.instance for g in q.goals)
        if q.kind and not outside and not (q.kind == "group" and level >= q.level + self.GROUP_SOLO) \
                and not (q.kind == "dungeon" and self.dungeons):
            return False  # dungeons (unless their objectives are outside, or the route takes dungeons), raids, PvP
        above = self.STRETCH if stretch else (self.ABOVE_HIGH if level >= self.HIGH_FROM else self.ABOVE)
        below = self.BELOW_HIGH if level >= self.HIGH_FROM else self.BELOW
        if q.min_level > level or q.level > level + above or q.level < level - below:
            return False
        if q.prev > 0 and q.prev not in done:
            return False
        if q.prev < 0 and -q.prev not in active:
            return False
        if q.exclusive > 0 and any(o != q.id and (o in done or o in active) for o in groups.get(q.exclusive, ())):
            return False
        return self.spread_ok(q)


class HubScorer:
    """Experience per second for the quests at a hub: getting there, the objectives (there and back,
    shared by the hub's quests), the kills, and the turn-ins."""
    KILL_SECONDS = 20
    OVERHEAD = 60

    def value(self, quests, here, hub, level, xp, travel, extra_seconds=0):
        """extra_seconds: getting there costs more than walking (another zone: loading, flights, boats)."""
        if not quests:
            return 0.0
        gained = sum(xp.quest_xp(q.xp, q.level, level) for q in quests)
        # The kills the objectives need give experience too (the same as grinding them would).
        gained += sum(g.count * xp.kill_xp(level, g.mob_level) for q in quests for g in q.goals
                      if g.kind in ("kill", "collect") and g.mob_level)
        work = 0.0
        for q in quests:
            for g in q.goals:
                work += travel.seconds(hub, g.point, level) * 2 / len(quests) + g.count * self.KILL_SECONDS
            work += travel.seconds(hub, q.end, level) / len(quests)
        return gained / (travel.seconds(here, hub, level) + extra_seconds + work + self.OVERHEAD)


class ZonePlan:
    """Which zones fit each level band: [(from level, to level, [zones])]. Cities always fit (turn-ins,
    trainers). An empty plan lets every zone fit."""

    def __init__(self, bands, cities=()):
        self.bands, self.cities = bands, set(cities)

    def allows(self, zone, level):
        if not self.bands or zone in self.cities:
            return True
        return any(low <= level <= high and zone in zones for low, high, zones in self.bands)


@dataclass
class Character:
    level: int = 1
    xp: float = 0
    time: float = 0.0


class Shortcuts:
    """Flights and the hearthstone (user, 2026-11-14: RestedXP's flights and hearthstones are why it runs a third
    less). Flight paths are learned as the route passes flight masters; the hearthstone is set at a town with an
    inn when the route arrives in a new zone, and used when it saves time (one hour cooldown).
    flights / inns: [(name, world point)]."""
    FLY_SPEED, FLY_OVERHEAD, FLY_DETOUR = 25.0, 20.0, 1.25  # yards/s; seconds to talk and take off; flight paths aren't straight
    LEARN = 400          # yards: passing this close to a flight master, the route has its flight path
    HEARTH_CAST, HEARTH_COOLDOWN = 10.0, 3600.0
    INN_NEAR = 250       # yards: an inn this close to a hub is that town's
    MIN_SAVING = 60      # seconds: a shortcut must save at least this much

    def __init__(self, flights=(), inns=()):
        self.flights, self.inns = list(flights), list(inns)
        self.known, self.home, self.ready_at = set(), None, 0.0

    def learn(self, pos):
        for k, (_, p) in enumerate(self.flights):
            if distance(p, pos) <= self.LEARN:
                self.known.add(k)

    def inn_near(self, point):
        best = min(self.inns, key=lambda i: distance(i[1], point), default=None)
        return best if best and distance(best[1], point) <= self.INN_NEAR else None

    def best(self, a, b, walk, now):
        """Cheapest way from a to b: ("walk", seconds) | ("fly", seconds, from, to) | ("hearth", seconds)."""
        options = [("walk", walk)]
        if len(self.known) >= 2 and a and b and a[0] == b[0]:
            same = [self.flights[k] for k in self.known if self.flights[k][1][0] == a[0]]
            if len(same) >= 2:
                f1 = min(same, key=lambda f: distance(f[1], a))
                f2 = min(same, key=lambda f: distance(f[1], b))
                if f1 is not f2:
                    t = (distance(a, f1[1]) + distance(f2[1], b)) / TravelModel.RUN \
                        + distance(f1[1], f2[1]) * self.FLY_DETOUR / self.FLY_SPEED + self.FLY_OVERHEAD
                    options.append(("fly", t, f1, f2))
        if self.home and now >= self.ready_at and b and self.home[1][0] == b[0]:
            options.append(("hearth", self.HEARTH_CAST + distance(self.home[1], b) / TravelModel.RUN))
        pick = min(options, key=lambda o: o[1])
        return pick if pick[0] == "walk" or pick[1] + self.MIN_SAVING < walk else options[0]


class RoutePlanner:
    NEAR = 120        # yards: givers this close are the same quest hub (one town)
    TALK = 40         # yards: a turn-in this close is where you stand
    MAX_ACTIVE = 20   # the quest log holds 20
    KILL_SECONDS = 20
    DROP_NEAR = 250   # yards: a quest-starting drop is picked up while working this close to its monsters
    WORTH = 0.5       # a quest must give at least this share of grinding's experience per second (user: fast leveling)
    SHARED_WALK = 0.5 # share of a quest's walk counted against it (the rest is shared with the hub's other quests)
    DETOUR = 40       # yards: a turn-in that adds less than this to the next walk is done on the way
    ZONE_CHANGE = 300 # seconds: what leaving your zone costs on top of walking (loading, flights, boats)
    STAY = 0.5        # stay in your zone while its best hub is worth at least half of the best elsewhere
    start_level = 1   # the route can be planned from any level
    DUNGEON_RUN = 2400  # seconds: one dungeon run with a group (finding one, the run, back out)

    def __init__(self, quests, where, eligibility, xp, travel, scorer, zone_plan=None, shortcuts=None, avoid=()):
        self.shortcuts = shortcuts or Shortcuts()
        self.avoid, self._avoid_cache = set(avoid), {}  # safe style: zones whose quests are left out
        self.quests = {q.id: q for q in quests}
        self.zone_plan = zone_plan or ZonePlan([])
        self.planned = True  # follow the zone plan; off for a moment when its zones have nothing left
        self.where, self.eligibility, self.xp, self.travel, self.scorer = where, eligibility, xp, travel, scorer
        self.groups = defaultdict(list)
        for q in quests:
            if q.exclusive > 0:
                self.groups[q.exclusive].append(q.id)
        self.most_active = 0
        self.needed = {abs(q.prev) for q in quests if q.prev}  # quests another quest needs: kept for their chain

    # -- state helpers --
    def _available(self, q, stretch=False):
        return self.eligibility.available(q, self.me.level, self.done, set(self.active), self.race_bit, self.groups, stretch)

    def _hub_ok(self, q, stretch):
        """A quest the route may go to a new hub for: available, in a zone the plan allows now, not in an avoided zone
        (safe style)."""
        return self._available(q, stretch) and (not self.planned or self.zone_plan.allows(self._zone(q.start), self.me.level)) \
            and self._worth(q) and not self._avoided(q)

    def _avoided(self, q):
        if not self.avoid:
            return False
        if q.id not in self._avoid_cache:
            self._avoid_cache[q.id] = any((self.where(p) or ("?",))[0] in self.avoid for p in [q.start, q.end] + [g.point for g in q.goals] if p)
        return self._avoid_cache[q.id]

    def _step(self, kind, qid, point, text, goal=0, dest=None):
        w = self.where(point) if point else None
        d = self.where(dest) if dest else None
        self.steps.append(Step(kind, qid, w[0] if w else "?", w[1] if w else None, w[2] if w else None, self.me.level, text, goal,
                               [d[0], round(d[1], 1), round(d[2], 1)] if d else None))

    def _go(self, point):
        walk = self.travel.seconds(self.pos, point, self.me.level)
        way = self.shortcuts.best(self.pos, point, walk, self.me.time) if walk > self.shortcuts.MIN_SAVING else ("walk", walk)
        if way[0] == "fly":
            _, seconds, f1, f2 = way
            self._step("fly", 0, f1[1], f"Fly from {f1[0]} to {f2[0]}", dest=f2[1])
            self.flights_taken += 1
        elif way[0] == "hearth":
            seconds = way[1]
            self._step("hearth", 0, self.pos, "Use your Hearthstone", dest=self.shortcuts.home[1])
            self.shortcuts.ready_at = self.me.time + Shortcuts.HEARTH_COOLDOWN
            self.hearths_used += 1
        else:
            seconds = walk
        self.me.time += seconds
        self.pos = point
        self.shortcuts.learn(point)

    def _settle_in(self, hub):
        """Arriving at a hub in a new zone: set the hearthstone at its inn (you'll come back to turn in)."""
        inn = self.shortcuts.inn_near(hub)
        if not inn or (self.shortcuts.home and self._zone(self.shortcuts.home[1]) == self._zone(inn[1])):
            return
        self.shortcuts.home = inn
        self._step("home", 0, inn[1], f"Set your Hearthstone at {inn[0]}")
        self.me.time += 15

    def _gain(self, amount):
        self.me.level, self.me.xp = self.xp.add(self.me.level, self.me.xp, amount, self.max_level)

    # -- actions --
    def _accept_here(self):
        stretch, self.stretching = self.stretching, False
        # Follow the plan here too (quests beside you in a zone off the plan pull the route away),
        # unless the fallback just chose this hub outside the plan.
        self.planned, self.off_plan = not self.off_plan, False
        here = [q for q in self.quests.values() if self._hub_ok(q, stretch)
                and distance(q.start, self.pos) <= (self.DROP_NEAR if q.start_drop else self.NEAR)]
        self.planned = True
        here.sort(key=lambda q: (distance(q.start, self.pos), q.id))
        for q in here:
            if len(self.active) >= self.MAX_ACTIVE:
                break
            self.active[q.id] = list(q.goals)
            self.most_active = max(self.most_active, len(self.active))
            if q.start_drop:
                # A dropped item starts it: loot it from the monsters here (expected kills), then right-click it.
                item, mob, chance = q.start_drop
                self.me.time += min(30, round(100 / max(1.0, chance))) * self.KILL_SECONDS
                self._step("accept", q.id, q.start, f'Loot {item} from {mob} ({chance:.0f}%), then right-click it to start "{q.title}"')
            else:
                self._step("accept", q.id, q.start, f'Accept "{q.title}" from {q.start_name}')

    def _worth(self, q):
        """Enough experience for its time (walk to its objectives and back, kills) compared with grinding;
        quests that lead on in a chain are always worth it."""
        if q.next_in_chain or q.id in self.needed or q.start_drop:
            return True
        walk, here = 0.0, q.start
        for g in q.goals:
            walk += distance(here, g.point)
            here = g.point
        walk += distance(here, q.end)
        kills = sum(g.count for g in q.goals if g.kind in ("kill", "collect") and g.mob_level)
        seconds = self.SHARED_WALK * walk / 7.0 + kills * self.KILL_SECONDS + 10 * len(q.goals) + 10
        xp = self.xp.quest_xp(q.xp, q.level, self.me.level) + sum(
            g.count * self.xp.kill_xp(self.me.level, g.mob_level) for g in q.goals if g.kind in ("kill", "collect") and g.mob_level)
        return xp / seconds >= self.WORTH * self._grind_rate()

    def _turn_in_here(self):
        ready = sorted(qid for qid, goals in self.active.items() if not goals and distance(self.quests[qid].end, self.pos) <= self.TALK)
        for qid in ready:
            q = self.quests[qid]
            del self.active[qid]
            self.done.add(qid)
            self._gain(self.xp.quest_xp(q.xp, q.level, self.me.level))
            self._step("turnin", qid, q.end, f'Turn in "{q.title}" to {q.end_name}')
        return bool(ready)

    def _do(self, qid, goal):
        q = self.quests[qid]
        self._go(goal.point)
        verb = {"kill": f"Kill {goal.count} {goal.name}", "collect": f"Collect {goal.name}" + (f" (about {goal.count} kills)" if goal.mob_level else ""),
                "use": f"Use {goal.name}", "explore": "Explore the area"}.get(goal.kind, goal.name)
        self._step("do", qid, goal.point, f'{verb} for "{q.title}"', q.goals.index(goal) + 1)
        kills = goal.count if goal.kind in ("kill", "collect") and goal.mob_level else 0
        self.me.time += kills * self.KILL_SECONDS + 10
        if goal.instance and goal.instance not in self.runs:
            self.runs.add(goal.instance)  # one run of the dungeon does all its quests
            self.me.time += self.DUNGEON_RUN
        if kills:
            self._gain(kills * self.xp.kill_xp(self.me.level, goal.mob_level))
        self.active[qid].remove(goal)

    def _zone(self, point):
        return (self.where(point) or ("?",))[0]

    def _next_hub(self, stretch=False):
        """Where to go for new quests: a hub in your zone while it's worth at least STAY of the best
        elsewhere, so the route finishes a zone instead of hopping (boats cost minutes)."""
        here = self._zone(self.pos)
        local, local_value = self._best_hub(stretch, zone=here, with_value=True)
        # Next zone: on this continent while it's worth at least STAY of the best across the sea.
        near_zone, near_value = self._best_zone(stretch, exclude=here, continent=self.pos[0])
        far_zone, far_value = self._best_zone(stretch, exclude=here, continent=self.pos[0], other_continent=True)
        if near_zone is not None and near_value >= self.STAY * far_value:
            zone, zone_value = near_zone, near_value
        else:
            zone, zone_value = (far_zone, far_value) if far_zone is not None else (near_zone, near_value)
        if local is not None and local_value >= self.STAY * zone_value:
            self.hub_value = local_value
            return local
        if zone is None:
            self.hub_value = local_value
            return local
        hub, self.hub_value = self._best_hub(stretch, zone=zone, with_value=True)
        return hub

    def _grind_rate(self):
        """Experience per second from killing monsters of your level where you are."""
        return self.xp.kill_xp(self.me.level, self.me.level) / self.KILL_SECONDS

    def _grind(self, why):
        needed = XP_TO_LEVEL[self.me.level] - self.me.xp
        self._step("grind", 0, self.pos, f"Kill monsters of your level around here to reach level {self.me.level + 1}: {why}")
        self.me.time += needed / max(1e-9, self._grind_rate())
        self._gain(needed)

    def _best_zone(self, stretch=False, exclude=None, continent=None, other_continent=False):
        """The zone with the most experience per second for all its quests that fit now (getting there
        included): one rich hub across the sea loses to a zone with several good hubs nearby."""
        by_zone = defaultdict(list)
        for q in self.quests.values():
            if self._hub_ok(q, stretch) and not q.start_drop and (continent is None or ((q.start[0] == continent) != other_continent)):
                z = self._zone(q.start)
                if z != exclude:
                    by_zone[z].append(q)
        best, best_value = None, 0.0
        for z, qs in by_zone.items():
            entry = min((q.start for q in qs), key=lambda p: distance(p, self.pos))
            value = self.scorer.value(qs, self.pos, entry, self.me.level, self.xp, self.travel, self.ZONE_CHANGE)
            if value > best_value:
                best, best_value = z, value
        return best, best_value

    def _best_hub(self, stretch=False, zone=None, exclude=None, with_value=False):
        """The quest hub with the most experience per second; zone: only hubs in that zone; exclude:
        not in that zone."""
        hubs = defaultdict(list)
        for q in self.quests.values():
            if self._hub_ok(q, stretch) and not q.start_drop and (zone is None or self._zone(q.start) == zone)                     and (exclude is None or self._zone(q.start) != exclude):
                hubs[(q.start[0], round(q.start[1] / self.NEAR), round(q.start[2] / self.NEAR))].append(q)
        best, best_value = None, 0.0
        here_zone = (self.where(self.pos) or ("?",))[0]
        for qs in hubs.values():
            point = qs[0].start
            near = [q for q in self.quests.values() if self._available(q, stretch) and distance(q.start, point) <= self.NEAR]
            extra = 0 if (self.where(point) or ("?",))[0] == here_zone else self.ZONE_CHANGE
            value = self.scorer.value(near, self.pos, point, self.me.level, self.xp, self.travel, extra)
            if value > best_value:
                best, best_value = point, value
        return (best, best_value) if with_value else best

    def _on_the_way(self, stop, target):
        """True when stopping at `stop` adds almost nothing to the walk to `target`."""
        detour = distance(self.pos, stop) + distance(stop, target) - distance(self.pos, target)
        return detour <= self.DETOUR

    def plan(self, start, race_bit, max_level=60):
        self.me, self.pos, self.race_bit, self.max_level = Character(level=self.start_level), start, race_bit, max_level
        self.done, self.active, self.steps = set(), {}, []
        self.flights_taken = self.hearths_used = 0
        self.runs = set()
        self.shortcuts.learn(start)
        self.stretching = False
        self.off_plan = False
        guard = 0
        while self.me.level < max_level and guard < 50000:
            guard += 1
            self._turn_in_here()
            self._accept_here()
            todo = [(qid, g) for qid, goals in self.active.items() for g in goals]
            ready = [qid for qid, goals in self.active.items() if not goals]
            nearest_end = min((self.quests[r].end for r in ready), key=lambda p: distance(p, self.pos), default=None)
            if todo:
                qid, goal = min(todo, key=lambda t: (distance(t[1].point, self.pos), t[0]))
                if nearest_end and self._on_the_way(nearest_end, goal.point):
                    self._go(nearest_end)  # a turn-in on the way comes first
                    continue
                self._do(qid, goal)
                continue
            if nearest_end:
                # Turn-ins elsewhere wait while this zone still has a hub: leave a zone once, not per quest. Not when
                # the quest log is full (nothing more fits) or that hub is where you stand: that walked in circles
                # (2026-11-14, the Tirisfal route with Forever's own quests stopped at level 10).
                local = None
                if self._zone(nearest_end) != self._zone(self.pos) and len(self.active) < self.MAX_ACTIVE:
                    local = self._best_hub(zone=self._zone(self.pos))
                    if local is not None and distance(local, self.pos) <= self.NEAR:
                        local = None
                self._go(local or nearest_end)
                continue
            hub = None
            for planned, stretch in ((True, False), (True, True), (False, False), (False, True)):
                # The plan's zones first, harder quests before leaving them, then anywhere before grinding.
                self.planned = planned
                hub = self._next_hub(stretch)
                if hub is not None:
                    self.stretching, self.off_plan = stretch, not planned
                    break
            self.planned = True
            if hub is None:
                self._grind("no quests fit your level now")
                continue
            if hub[0] != self.pos[0] and self.hub_value < self._grind_rate():
                # Only a sea crossing is weighed against grinding: those trips are what make a route hop.
                self._grind("the next quests aren't worth the trip yet")
                continue
            before = self.where(self.pos)[0] if self.where(self.pos) else None
            self._go(hub)
            after = self.where(hub)
            if after and after[0] != before:
                self._step("travel", 0, hub, f"Go to {after[0]}")
            self._settle_in(hub)
        return self.steps, self.me
