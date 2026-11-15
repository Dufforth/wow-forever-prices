"""How far above (or below) the ground around it a quest NPC stands, from the spawns' heights.

User, 2026-11-14: Darsok Swiftdagger stands on top of the Crossroads tower; right under him the guide said "You are
here" and no NPC was in sight. Map spots have no height, so the guide needs one: the NPC's z minus the ground's, the
ground being a low percentile of the other spawns within RADIUS yards (most of them stand on the ground).
"""
from collections import defaultdict

RADIUS = 40.0     # yards around the NPC whose spawns tell the ground
MIN_NEAR = 3      # fewer neighbours than this: unknown
LIFT_MIN = 12     # yards: less than this is a slope or a step, not "up a tower"
GROUND_SHARE = 0.25  # the ground is the height a quarter of the neighbours stand at or below
CELL = 50.0


class Heights:
    def __init__(self, spawns):
        """spawns: (map, x, y, z) of creatures and objects."""
        self.z = {}
        self.grid = defaultdict(list)
        for m, x, y, z in spawns:
            self.z.setdefault((m, x, y), z)
            self.grid[(m, int(x // CELL), int(y // CELL))].append((x, y, z))

    def lift(self, point):
        """Whole yards above (+) or below (-) the ground, 0 when under LIFT_MIN or unknown."""
        if point is None or point not in self.z:
            return 0
        m, x, y = point
        z = self.z[point]
        cx, cy = int(x // CELL), int(y // CELL)
        near = []
        for i in (cx - 1, cx, cx + 1):
            for j in (cy - 1, cy, cy + 1):
                for px, py, pz in self.grid.get((m, i, j), ()):
                    if (px, py) != (x, y) and (px - x) ** 2 + (py - y) ** 2 <= RADIUS * RADIUS:
                        near.append(pz)
        if len(near) < MIN_NEAR:
            return 0
        near.sort()
        ground = near[int((len(near) - 1) * GROUND_SHARE)]
        up = z - ground
        return int(round(up)) if abs(up) >= LIFT_MIN else 0
