"""Guide styles (user, 2026-11-14): the same planner, three ways to level.

  speed     the fastest route (the default)
  safe      leaves out the zones known for world PvP: no quest there (flying over is fine)
  explorer  more zones and their flight paths, quests that reward gear or gold, and a gold-farming stop per zone

Each style is also built with dungeon quests ("with dungeons"). This module holds what differs between the styles;
the planner and the builder stay the same.
"""
import math

from route_planner import HubScorer

# Zones where Horde and Alliance quest side by side and world PvP is common (Tarren Mill / Southshore,
# Stranglethorn, Ashenvale, Arathi, Alterac).
PVP_ZONES = {"Stranglethorn Vale", "Hillsbrad Foothills", "Ashenvale", "Arathi Highlands", "Alterac Mountains"}

STYLES = {
    "speed": {"suffix": "", "label": "Speed"},
    "safe": {"suffix": " - Safe", "label": "Safe"},
    "explorer": {"suffix": " - Explorer", "label": "Explorer"},
}


def route_name(start, style, dungeons):
    return start + STYLES[style]["suffix"] + (" (dungeons)" if dungeons else "")


def safe_bands(bands):
    """The zone plan without the PvP zones (a band left empty keeps its other zones' neighbours via the planner's
    fallback)."""
    return [(low, high, [z for z in zones if z not in PVP_ZONES]) for low, high, zones in bands]


def explorer_bands(bands, spread=2):
    """Each band also takes the zones of its neighbours and starts and ends a little wider: more zones visited."""
    out = []
    for k, (low, high, zones) in enumerate(bands):
        more = list(zones)
        for j in (k - 1, k + 1):
            if 0 <= j < len(bands):
                more += [z for z in bands[j][2] if z not in more]
        out.append((max(1, low - spread), high + spread, more))
    return out


class ExplorerScorer(HubScorer):
    """Values a hub's gold and gear rewards on top of its experience."""
    MONEY_XP = 0.5   # experience a copper of quest reward money is worth to an explorer
    GEAR_BONUS = 0.3  # a quest with a gear reward counts this much more

    def value(self, quests, here, hub, level, xp, travel, extra_seconds=0):
        base = super().value(quests, here, hub, level, xp, travel, extra_seconds)
        if not quests or base <= 0:
            return base
        gained = sum(xp.quest_xp(q.xp, q.level, level) for q in quests) or 1
        bonus = sum(q.money * self.MONEY_XP + (self.GEAR_BONUS * xp.quest_xp(q.xp, q.level, level) if q.gear else 0) for q in quests)
        return base * (1 + bonus / gained)


def touches(q, zones, where):
    """True when a quest's giver, objectives or hand-in are in one of these zones."""
    for p in [q.start, q.end] + [g.point for g in q.goals]:
        w = where(p) if p else None
        if w and w[0] in zones:
            return True
    return False


# ---- Gold-farming stops (explorer) ----
FARM_BELOW, FARM_ABOVE, FARM_MIN_LEVEL, FARM_CANDIDATES = 3, 1, 10, 3


def farm_spots(farm):
    """{zone: [(min level, max level, name, x, y, [(item, chance %), ...])]} from site/farm.json: monsters outside
    dungeons, not elite, with the items worth farming they drop."""
    creatures = farm["creatures"]
    drops = {}
    for item, row in farm["items"].items():
        for index, chance, _ in row["d"]:
            drops.setdefault(index, []).append((int(item), chance))
    out = {}
    for index, items in drops.items():
        name, low, high, rank, zone, x, y, spawns, dungeon = creatures[index][:9]
        if dungeon or rank not in ("", "normal", None) or x is None or (spawns or 0) < 5:
            continue
        out.setdefault(zone, []).append((low, high, name, x, y, sorted(items, key=lambda t: -t[1])[:4]))
    return out


def insert_farm_stops(rows, spots):
    """After the last step of each visit to a zone (level 10+), a "farm" step with up to three monsters of your
    level there and what they drop; the addon picks the one worth the most at today's prices.
    Step: ["farm", 0, zone, x, y, level, text, 0, None, [[item, monster, chance, x, y], ...]]."""
    out = []
    for k, s in enumerate(rows):
        out.append(s)
        nxt = rows[k + 1] if k + 1 < len(rows) else None
        zone, level = s[2], s[5]
        if level < FARM_MIN_LEVEL or (nxt and nxt[2] == zone) or s[0] in ("fly", "hearth", "travel"):
            continue
        near = [c for c in spots.get(zone, []) if c[0] - FARM_ABOVE <= level <= c[1] + FARM_BELOW]
        if not near:
            continue
        here = (s[3], s[4]) if s[3] is not None else None
        near.sort(key=lambda c: (math.hypot(c[3] - here[0], c[4] - here[1]) if here else 0))
        cands = []
        for low, high, name, x, y, items in near[:FARM_CANDIDATES]:
            for item, chance in items[:1]:
                cands.append([item, name, round(chance, 1), x, y])
        if cands:
            out.append(["farm", 0, zone, cands[0][3], cands[0][4], level, f"Farm {cands[0][1]}", 0, None, cands])
    return out
