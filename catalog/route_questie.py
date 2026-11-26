"""Forever's own quests from Questie's Forever database (QuestieDB, https://github.com/Questie/Questie, GPL-3.0).

QuestieDB ships its data "baked" into QuestieDB_Forever.toc: every value is a `## X-<Entity>-<id>-<field>: <base64>`
line (CBOR; the id lists are also zlib-compressed; long values are split into `~N~` chunks). This module decodes it
and turns Forever's own quests into rows for catalog/forever_questie_quests.json, in the same shape as the recorded
quests (route_forever.to_quest), plus their level, minimum level, races, chain links and real experience
(QuestieDB's QuestXP tables, gathered from players' clients).

Field numbers follow QuestieDB's src/meta/*Meta.lua.
"""
import base64
import math
import re
import struct
import zlib

# Quest fields
NAME, STARTED, FINISHED, MIN_LEVEL, LEVEL, RACES, CLASSES, OBJ_TEXT, TRIGGER, OBJECTIVES = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
PRE_GROUP, PRE_SINGLE, EXCLUSIVE, ZONE, SKILL, NEXT, SPECIAL = 12, 13, 16, 17, 18, 22, 24
# Npc / object / item fields
N_NAME, N_MIN, N_MAX, N_RANK, N_SPAWNS, N_FRIENDLY = 1, 4, 5, 6, 7, 13
O_SPAWNS = 4
I_NAME, I_NPC_DROPS, I_OBJ_DROPS = 1, 2, 3

SOURCE_ITEM = 11
WORK = re.compile(r"\b(kill|slay|destroy|collect|gather|obtain|acquire|retrieve|recover|bring|hand in|reputation|gold|\d+)\b", re.I)
FOREVER_FROM = 10000  # Classic Era's quests stop below this number; Forever's own start at 60000
HORDE = 2 | 16 | 32 | 128
MAX_SPOTS = 10
NEAR = 8.0  # map %: spots this close are one group


def cbor(b, i=0, whole=True):
    """Decodes one CBOR value (the subset QuestieDB writes)."""
    value, i = _cbor(b, i)
    return value if whole else (value, i)


def _cbor(b, i):
    head = b[i]
    major, info = head >> 5, head & 31
    i += 1
    if major == 7 and info in (25, 26, 27):
        fmt, n = {25: (">e", 2), 26: (">f", 4), 27: (">d", 8)}[info]
        return struct.unpack(fmt, b[i:i + n])[0], i + n
    if info < 24:
        val = info
    elif info in (24, 25, 26, 27):
        n = 1 << (info - 24)
        val = int.from_bytes(b[i:i + n], "big")
        i += n
    elif info == 31:
        val = None
    else:
        raise ValueError(f"CBOR: bad length {info}")
    if major == 0:
        return val, i
    if major == 1:
        return -1 - val, i
    if major in (2, 3):
        s = b[i:i + val]
        return bytes(s).decode("utf-8", "replace"), i + val  # QuestieDB writes some text as byte strings
    if major == 4:
        out = []
        while (val is None and b[i] != 0xFF) or (val is not None and len(out) < val):
            v, i = _cbor(b, i)
            out.append(v)
        return out, i + (1 if val is None else 0)
    if major == 5:
        out, n = {}, 0
        while (val is None and b[i] != 0xFF) or (val is not None and n < val):
            k, i = _cbor(b, i)
            out[k], i = _cbor(b, i)
            n += 1
        return out, i + (1 if val is None else 0)
    if major == 6:
        return _cbor(b, i)
    return {20: False, 21: True}.get(val), i


def decode(text, compressed=False):
    raw = base64.b64decode(text)
    return cbor(zlib.decompress(raw) if compressed else raw)


def read_meta(toc_path):
    meta = {}
    with open(toc_path, encoding="utf-8") as f:
        for line in f:
            if line.startswith("## X-"):
                key, _, value = line[3:].rstrip("\n").partition(": ")
                meta[key] = value
    return meta


def stored(meta, key):
    """One value, reassembled when it's split into `~N~` chunks."""
    value = meta.get(key)
    m = re.fullmatch(r"~(\d+)~", value or "")
    if m:
        value = "".join(meta[f"{key}-{j}"] for j in range(1, int(m[1]) + 1))
    return value


def entities(meta, kind, fields):
    """{id: {field: value}} for one entity kind ("Quest", "Npc", "Object", "Item")."""
    prefix = f"X-{kind}-"
    out = {}
    for id_ in decode(stored(meta, prefix + "IDS"), compressed=True):
        rec = {}
        s = stored(meta, f"{prefix}{id_}-S")
        row = decode(s) if s else {}
        if isinstance(row, list):
            row = {k + 1: v for k, v in enumerate(row)}
        rec.update({k: v for k, v in row.items() if k != "p" and v is not None})
        for f in range(1, fields + 1):
            t = stored(meta, f"{prefix}{id_}-{f}")
            if t:
                rec[f] = decode(t)
        out[id_] = rec
    return out


def load_db(toc_path):
    meta = read_meta(toc_path)
    return {"quest": entities(meta, "Quest", 36), "npc": entities(meta, "Npc", 15),
            "object": entities(meta, "Object", 7), "item": entities(meta, "Item", 16)}


def read_xp(*texts):
    """{quest: (level, xp)} from QuestieDB's QuestXP files (later texts win: the in-game traces)."""
    out = {}
    for text in texts:
        for m in re.finditer(r"QuestXP\.db\[(\d+)\] = \{(-?\d+), (\d+)\}", text):
            out[int(m[1])] = (int(m[2]), int(m[3]))
    return out


def part(value, index):
    """Item `index` (1-based) of a Lua table decoded as a CBOR list or a sparse map."""
    if isinstance(value, list):
        return value[index - 1] if 0 < index <= len(value) else None
    if isinstance(value, dict):
        return value.get(index, value.get(str(index)))
    return None


def count_in(lines, name):
    """The count the objective text gives for `name` ("Slay 12 Meadowsbrook Farmhands"), or None."""
    words = [w for w in re.findall(r"[A-Za-z']+", name or "") if len(w) > 2]
    for line in lines or []:
        for m in re.finditer(r"\b(\d+)\s+([A-Za-z' :-]+)", line):
            if not words or any(w.lower() in m[2].lower() for w in words):
                return int(m[1])
    return None


def densest(spots):
    """The spots around the densest place (where most of them are within NEAR of each other), up to MAX_SPOTS."""
    if not spots:
        return []
    def near(a, b):
        return a[0] == b[0] and math.hypot(a[1] - b[1], a[2] - b[2]) <= NEAR
    best = max(spots, key=lambda s: sum(1 for t in spots if near(s, t)))
    group = sorted((t for t in spots if near(best, t)), key=lambda t: math.hypot(best[1] - t[1], best[2] - t[2]))
    return group[:MAX_SPOTS]


def _spots(spawns, zones):
    out = []
    if isinstance(spawns, list):  # a Lua table with keys 1..n decodes as a list
        spawns = {k + 1: v for k, v in enumerate(spawns)}
    for area, points in (spawns or {}).items():
        zone = zones.get(int(area))
        for p in points or []:
            if zone and isinstance(p, list) and len(p) >= 2 and p[0] is not None and p[0] >= 0:
                out.append((zone, round(float(p[0]), 1), round(float(p[1]), 1)))
    return out


def _place(ids, table, spawn_field, zones):
    """{name, zone, x, y} of the first of these NPCs or objects with a spawn."""
    for id_ in ids or []:
        rec = table.get(id_) or {}
        spots = densest(_spots(rec.get(spawn_field), zones))
        if spots:
            z, x, y = spots[0]
            return {"name": rec.get(N_NAME, ""), "zone": z, "x": x, "y": y}
    return None


def _horde_npc(rec):
    friendly = rec.get(N_FRIENDLY)
    return not friendly or "H" in str(friendly)


def _mob_level(rec):
    lo, hi = rec.get(N_MIN), rec.get(N_MAX) or rec.get(N_MIN)
    return (lo + hi) / 2 if lo else 0


def _objectives(q, db, zones):
    text = q.get(OBJ_TEXT) or []
    obj = q.get(OBJECTIVES) or {}
    out, elite = [], False
    for entry in part(obj, 1) or []:  # creatures
        npc = db["npc"].get(entry[0]) or {}
        name = (entry[1] if len(entry) > 1 and entry[1] else None) or npc.get(N_NAME, "")
        spots = densest(_spots(npc.get(N_SPAWNS), zones))
        elite = elite or bool(npc.get(N_RANK))
        out.append({"text": name, "kind": "monster", "count": count_in(text, name) or 8, "spots": spots,
                    "mobLevel": _mob_level(npc), "elite": bool(npc.get(N_RANK))})
    for entry in part(obj, 2) or []:  # objects
        o = db["object"].get(entry[0]) or {}
        name = (entry[1] if len(entry) > 1 and entry[1] else None) or o.get(N_NAME, "")
        out.append({"text": name, "kind": "object", "count": count_in(text, name) or 1,
                    "spots": densest(_spots(o.get(O_SPAWNS), zones))})
    for entry in part(obj, 3) or []:  # items: looted from the monsters or objects that drop them
        item = db["item"].get(entry[0]) or {}
        name = (entry[1] if len(entry) > 1 and entry[1] else None) or item.get(I_NAME, "")
        droppers = [db["npc"].get(n) for n in item.get(I_NPC_DROPS) or [] if db["npc"].get(n)]
        spots = densest([s for npc in droppers for s in _spots(npc.get(N_SPAWNS), zones)])
        if not spots:
            spots = densest([s for o in item.get(I_OBJ_DROPS) or [] for s in _spots((db["object"].get(o) or {}).get(O_SPAWNS), zones)])
        row = {"text": name, "kind": "item", "count": count_in(text, name) or 6, "spots": spots}
        if droppers:
            row["mobLevel"] = sum(_mob_level(n) for n in droppers) / len(droppers)
            row["source"] = droppers[0].get(N_NAME, "")
            row["elite"] = all(bool(n.get(N_RANK)) for n in droppers)
            elite = elite or row["elite"]
        out.append(row)
    trigger = q.get(TRIGGER)
    if trigger and part(trigger, 2):
        out.append({"text": part(trigger, 1) or "Explore the area", "kind": "event", "count": 1,
                    "spots": densest(_spots(part(trigger, 2), zones))})
    # No place for an objective (QuestieDB lacks some Forever objects): it borrows the quest's other objectives' spots,
    # marked guessed (the addon then asks Questie in game).
    placed = [s for o in out if o["spots"] for s in o["spots"]]
    for o in out:
        if not o["spots"] and placed:
            o["spots"], o["guessed"] = densest(placed), True
    return out, elite


def rows(db, zones, xp, side_mask=HORDE, first_id=0):
    """Route rows for the quests numbered from `first_id` (FOREVER_FROM: Forever's own) a `side_mask` character can do:
    started by an NPC or object, not profession, repeatable or item-started."""
    out = []
    for qid, q in sorted(db["quest"].items()):
        if qid < first_id:
            continue
        races = q.get(RACES) or 0
        if races and not races & side_mask:
            continue
        if q.get(SKILL) or (q.get(SPECIAL) or 0) & 1 or part(q.get(STARTED), 3):
            continue
        started = q.get(STARTED) or {}
        givers = [n for n in part(started, 1) or [] if _horde_npc(db["npc"].get(n) or {})]
        giver = _place(givers, db["npc"], N_SPAWNS, zones) or _place(part(started, 2), db["object"], O_SPAWNS, zones)
        finished = q.get(FINISHED) or {}
        enders = [n for n in part(finished, 1) or [] if _horde_npc(db["npc"].get(n) or {})]
        ender = _place(enders, db["npc"], N_SPAWNS, zones) or _place(part(finished, 2), db["object"], O_SPAWNS, zones)
        if not giver or not ender:
            continue
        level = q.get(LEVEL) or 0
        if level <= 0:
            level = q.get(MIN_LEVEL) or (xp.get(qid) or (1, 0))[0] or 1
        objectives, elite = _objectives(q, db, zones)
        if not objectives and not q.get(SOURCE_ITEM) and WORK.search(" ".join(q.get(OBJ_TEXT) or [])):
            continue  # work the data doesn't describe (war effort, books, reputation): it can't be timed
        prev = (q.get(PRE_SINGLE) or q.get(PRE_GROUP) or [0])[0]
        exclusive = q.get(EXCLUSIVE) or []
        row = {"id": qid, "title": q.get(NAME, "?"), "level": level, "min_level": q.get(MIN_LEVEL) or max(1, level - 4),
               "xp": (xp.get(qid) or (0, 0))[1], "races": races & 0xFFFF, "classes": q.get(CLASSES) or 0,
               "giver": giver, "turnIn": ender, "objectives": objectives, "zone": zones.get(q.get(ZONE) or 0, "")}
        if prev:
            row["prev"] = prev
        if q.get(NEXT):
            row["next"] = q[NEXT]
        if exclusive:
            row["exclusive"] = min([qid] + list(exclusive))
        if elite:
            row["kind"] = "group"
        out.append(row)
    return out
