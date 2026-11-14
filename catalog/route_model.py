"""Data types of the leveling route: what a quest needs, and one step of the route.

Points are world positions (map, x, y) in yards.
"""
from dataclasses import dataclass, field
from typing import List, Optional, Tuple

Point = Tuple[int, float, float]


@dataclass
class Goal:
    """One objective: kill monsters, collect an item (count = kills it takes), use an object, explore."""
    kind: str
    name: str
    point: Point
    count: int = 1
    mob_level: float = 0
    source: str = ""        # collect: the monster that drops it (for "Loot X from Y")
    wide: bool = False      # its monsters are all over the map: done along the way, not as a stop


@dataclass
class Quest:
    id: int
    title: str
    level: int
    min_level: int
    start: Optional[Point]
    start_name: str
    end: Point
    end_name: str
    goals: List[Goal] = field(default_factory=list)
    xp: int = 0
    races: int = 0          # race bits, 0 = any
    classes: int = 0        # class bits, 0 = any
    kind: str = ""          # "", "group", "dungeon", "raid", "pvp"...
    prev: int = 0           # > 0: must be done first; < 0: must be in your log
    next_in_chain: int = 0
    exclusive: int = 0      # > 0: only one quest of this group
    start_item: int = 0     # started by an item instead of a giver
    timed: bool = False
    gear: List[int] = field(default_factory=list)
    start_drop: tuple = ()  # started by a dropped item: (item name, monster, drop chance %); start is where it drops


@dataclass
class Step:
    kind: str               # accept, do, turnin, travel, grind
    quest: int
    zone: str
    x: Optional[float]
    y: Optional[float]
    level: int
    text: str
    goal: int = 0           # do: which of the quest's objectives (1-based)
