"""Questline guides besides the leveling route (user, 2026-11-13): attunement chains followed in the
quest data, and the Cozy Sleeping Bag chain written by hand (it is newer than the quest database).

A guide is {"name", "note", "steps", "quests"}: steps in the route's format [kind, quest, zone, x, y,
level, text, goal]; quests in route.json's slim format for quests the database doesn't have.
"""

DUNGEON = "Inside the dungeon"
UNKNOWN = "Place not in the data"

# Attunement chains, by the quest that starts them (Horde).
ATTUNEMENTS = [
    ("Onyxia attunement (Horde)", [4903, 4941, 4974, 6566, 6567, 6568, 6569, 6570, 6582, 6583, 6584, 6585, 6601, 6602], "Onyxia's Lair: from Warlord Goretooth's orders in Blackrock Spire to the Blood of the Black Dragon Champion."),
    ("Molten Core attunement", 7848, "Molten Core: Lothos Riftwaker in Blackrock Mountain sends you to the Molten Core's entrance in Blackrock Depths."),
    ("Blackwing Lair attunement", 7761, "Blackwing Lair: Blackhand's Command, from a Scarshield Quartermaster in Blackrock Mountain."),
]


def chain(quests, start):
    """The quests of a chain from `start`: its next quest, or else the first quest that needs it. A list of
    ids is followed as given (quests done side by side, like the four Tests of Skulls); missing ids skipped."""
    if isinstance(start, list):
        return [quests[i] for i in start if i in quests]
    out, seen, q = [], set(), quests.get(start)
    while q and q.id not in seen:
        out.append(q)
        seen.add(q.id)
        nxt = quests.get(q.next_in_chain) if q.next_in_chain else None
        if nxt is None:
            nxt = next((c for c in sorted(quests.values(), key=lambda c: c.id) if c.prev == q.id and c.id not in seen), None)
        q = nxt
    return out


def chain_steps(chain_quests, where):
    """Pick up, each objective, turn in: one quest after the other."""
    steps = []

    def place(point):
        if point is None:
            return [UNKNOWN, None, None]
        w = where(point)
        return [w[0], round(w[1], 1), round(w[2], 1)] if w else [DUNGEON, None, None]
    for q in chain_quests:
        steps.append(["accept", q.id] + place(q.start) + [q.min_level, f'Accept "{q.title}" from {q.start_name}', 0])
        for k, g in enumerate(q.goals, 1):
            steps.append(["do", q.id] + place(g.point) + [q.min_level, f'{g.kind.capitalize()} {g.name} for "{q.title}"', k])
        steps.append(["turnin", q.id] + place(q.end) + [q.min_level, f'Turn in "{q.title}" to {q.end_name}', 0])
    return steps


# Cozy Sleeping Bag, Horde (WoW Forever / Season of Discovery chain). Places from Warcraft Tavern's Forever
# guide and the Warcraft Wiki (quest 79007); Stonetalon and Hillsbrad spots have no published coordinates,
# so those steps describe the spot and carry no map position.
def _q(title, level, prev, nxt, giver, giver_at, turnin, turnin_at):
    return [title, level, 14, 0, "", prev, nxt, giver, giver_at, turnin, turnin_at, [], [], 0, 0, 0]


BARRENS, WESTFALL, LOCH = ["The Barrens", 46.4, 73.9], ["Westfall", 37.5, 50.7], ["Loch Modan", 49.0, 12.0]
STONETALON, HILLSBRAD = ["Stonetalon Mountains", None, None], ["Hillsbrad Foothills", None, None]
COZY_SLEEPING_BAG = {
    "name": "Cozy Sleeping Bag (Horde)",
    "note": "Cozy Sleeping Bag: a hidden chain from the Barrens to Westfall, Stonetalon, Loch Modan and Thoradin's Wall. "
            "Starts at level 14; level 30+ recommended (Loch Modan and Arathi). Rewards the 12-slot Cozy Sleeping Bag.",
    "quests": {
        79007: _q("...and that note you found", 40, 0, 79192, "Burned-Out Remains", BARRENS, "Nailed Plank", WESTFALL),
        79192: _q("Stepping Stones", 40, 79007, 79980, "Nailed Plank", WESTFALL, "Pocket Litter", STONETALON),
        79980: _q("Scramble", 40, 79192, 79974, "Pocket Litter", STONETALON, "Mound of Dirt", STONETALON),
        79974: _q("Wet Job", 40, 79980, 79975, "Mound of Dirt", STONETALON, "Carved Figurine", LOCH),
        79975: _q("Eagle's Fist", 40, 79974, 79976, "Carved Figurine", LOCH, "Messenger Bag", HILLSBRAD),
        79976: _q("This Must Be The Place", 40, 79975, 0, "Messenger Bag", HILLSBRAD, "Hastily Rolled-Up Satchel", HILLSBRAD),
    },
    "steps": [
        ["accept", 79007, *BARRENS, 14, "Click the Burned-Out Remains south of Camp Taurajo: take the note", 0],
        ["turnin", 79007, *WESTFALL, 20, "Westfall, Alexston Farmstead: click the Nailed Plank (boat Ratchet - Booty Bay, or zeppelin to Grom'gol, then north)", 0],
        ["accept", 79192, *WESTFALL, 20, "Take Stepping Stones from the Nailed Plank", 0],
        ["turnin", 79192, *STONETALON, 20, "Stonetalon: a camp on the hill path near Sun Rock Retreat: click the Pocket Litter (no exact coordinates published)", 0],
        ["accept", 79980, *STONETALON, 20, "Take Scramble from the Pocket Litter", 0],
        ["turnin", 79980, *STONETALON, 20, "Walk a hundred paces due north of the stash: click the Mound of Dirt", 0],
        ["accept", 79974, *STONETALON, 20, "Take Wet Job from the messenger bag in the dirt", 0],
        ["turnin", 79974, *LOCH, 30, "Loch Modan, Stonewrought Dam: jump down to the ledge, click the Carved Figurine (level 30 guards)", 0],
        ["accept", 79975, *LOCH, 30, "Take Eagle's Fist from the Carved Figurine", 0],
        ["turnin", 79975, *HILLSBRAD, 30, "Thoradin's Wall, north gap (from Arathi): climb the leaning cart to the wall top, click the Messenger Bag", 0],
        ["accept", 79976, *HILLSBRAD, 30, "Take This Must Be The Place from the Messenger Bag", 0],
        ["turnin", 79976, *HILLSBRAD, 30, "Click the Hastily Rolled-Up Satchel just below: the Cozy Sleeping Bag is yours", 0],
    ],
}


def guides(quests_by_id, where):
    """Every questline guide, ready for route.json."""
    out = []
    for name, start, note in ATTUNEMENTS:
        qs = chain(quests_by_id, start)
        if qs:
            out.append({"name": name, "note": note, "steps": chain_steps(qs, where), "quests": {}})
    out.append(COZY_SLEEPING_BAG)
    return out
