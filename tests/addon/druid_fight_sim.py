"""Plays druid fights in each form with the macro the addon writes, under the macro rules proven by
the warrior's in-game logs (Forever 1.60.1, Nov 2026; nothing druid-specific is proven yet):
  * a line whose conditions don't match is skipped;
  * only the FIRST matching global-cooldown spell is tried on a press (cast or rejected);
  * off-global-cooldown spells (Maul, Enrage) are tried on every press wherever they are;
  * "/castsequence ... X,nil" casts X once, then is skipped; reset=combat starts it over;
  * a castsequence step moves only when its spell is cast (a refused one stays).
Unproven, run both ways: combo points stay on the target (Classic: a new target starts at 0, so
the cat sequence can wait on its finisher) or on the player.

    python tests/addon/druid_fight_sim.py          checks, quiet
    python tests/addon/druid_fight_sim.py -v       also prints each scenario's numbers
"""
import os
import random
import re
import sys

import lupa.lua51 as L

HERE = os.path.dirname(os.path.abspath(__file__))
VERBOSE = "-v" in sys.argv
_src = open(os.path.join(HERE, "warrior_sim.py"), encoding="utf-8").read().split("lua = L.LuaRuntime")[0]
_env = {"__file__": os.path.join(HERE, "warrior_sim.py")}
exec(_src, _env)
MOCK, source = _env["MOCK"], _env["source"]

FORM_IDS = {"bear": 5487, "aquatic": 1066, "cat": 768, "travel": 783}
LV10 = ["Wrath", "Healing Touch", "Moonfire", "Rejuvenation", "Bear Form", "Maul", "Growl", "Demoralizing Roar"]
LV18 = LV10 + ["Enrage", "Bash", "Swipe", "Faerie Fire", "Regrowth", "Aquatic Form"]
LV20 = LV18 + ["Cat Form", "Claw", "Rip", "Prowl"]
LV24 = LV20 + ["Rake", "Tiger's Fury"]
LV32 = LV24 + ["Travel Form", "Ferocious Bite"]


def build(spells, forms, group=False):
    lua = L.LuaRuntime(unpack_returned_tuples=True)
    for name in ("Locale.lua", "LocaleES.lua"):
        lua.execute(source(name))
    lua.execute(MOCK)
    lua.execute('CLASS = "DRUID"; UnitClass = function() return "Druid", CLASS end')
    for name in ("Core.lua", "Warrior.lua", "Druid.lua"):
        lua.execute(source(name))
    g = lua.globals()
    g.SPELLS = lua.table_from(spells)
    g.FORMS = lua.table_from([FORM_IDS[f] for f in forms])
    g.IsInGroup = lambda: group
    d = g.DufforthTweaksHelperDruid
    d.Update()
    return g.MACROS[d.MACRO_NAME]


# name: (cost, cooldown, uses the global cooldown, cast seconds)
SPELL = {
    "Maul": (15, 0, False, 0), "Enrage": (0, 60, False, 0), "Demoralizing Roar": (10, 0, True, 0),
    "Swipe": (20, 0, True, 0), "Tiger's Fury": (30, 0, True, 0), "Rake": (35, 0, True, 0),
    "Claw": (40, 0, True, 0), "Rip": (30, 0, True, 0), "Ferocious Bite": (35, 0, True, 0),
    "Faerie Fire": (20, 0, True, 0), "Moonfire": (25, 0, True, 0), "Wrath": (20, 0, True, 2.0),
}
FINISHERS = ("Rip", "Ferocious Bite")


class Fight:
    def __init__(self, body, form, seed=1, enemies=1, seconds=60, group=False, cp_on_target=True, hp=300, follow_prompt=False):
        self.rand = random.Random(seed)
        self.lines = body.split("\n")
        self.form, self.group, self.enemies_left, self.seconds = form, group, enemies, seconds
        self.cp_on_target, self.hp_max = cp_on_target, hp
        self.t, self.gcd_until, self.cast_until, self.cd = 0.0, 0.0, 0.0, {}
        self.in_combat = False
        self.power = {"bear": 0, "cat": 100, "caster": 400}[form]  # rage, energy, mana
        self.follow_prompt = follow_prompt
        self.cp, self.target_hp = 0, hp
        self.maul_queued, self.enrage_until = False, 0.0
        self.sequences, self.casts, self.refused = {}, {}, {}
        self.kills, self.stuck = 0, 0.0
        self.swing_at, self.enemy_swing_at = 1.0, 1.5
        self.form_number = {"bear": "1", "cat": "3", "caster": "0"}[form]

    def matches(self, cond):
        if cond == "":
            return True
        for part in [c.strip() for c in cond.split(",") if c.strip()]:
            if part == "nocombat" and self.in_combat: return False
            if part == "combat" and not self.in_combat: return False
            if part == "group" and not self.group: return False
            if part == "noform" and self.form != "caster": return False
            if part.startswith("form:") and self.form_number not in part[5:].split("/"): return False
        return True

    def clause(self, text):
        """First clause whose bracket groups match: (clause key, action text) or None."""
        for c in text.split(";"):
            groups = re.findall(r"\[([^\]]*)\]", c)
            rest = re.sub(r"\[[^\]]*\]", "", c).strip()
            if not groups or any(self.matches(gr) for gr in groups):
                return c, rest
        return None

    def attempt(self, spell):
        cost, cooldown, gcd, cast = SPELL[spell]
        if spell in FINISHERS and self.cp == 0:
            return self.refuse(spell, "combo")
        if self.t < self.cast_until or (gcd and self.t < self.gcd_until) or self.cd.get(spell, 0) > self.t:
            return self.refuse(spell, "not ready")
        if spell == "Maul" and self.maul_queued:
            return True  # already queued
        if self.power < cost:
            return self.refuse(spell, "power")
        if spell == "Maul":
            self.maul_queued = True
            return True
        self.power -= cost
        if cooldown: self.cd[spell] = self.t + cooldown
        if gcd: self.gcd_until = self.t + (1.0 if self.form == "cat" else 1.5)
        if cast: self.cast_until = self.t + cast
        self.done(spell)
        return True

    def refuse(self, spell, why):
        self.refused[why] = self.refused.get(why, 0) + 1
        return False

    def done(self, spell):
        self.casts[spell] = self.casts.get(spell, 0) + 1
        self.in_combat = True
        if spell == "Enrage": self.enrage_until = self.t + 10
        if spell in ("Rake", "Claw"): self.cp = min(5, self.cp + 1); self.hit(25 if spell == "Claw" else 35)
        if spell == "Rip": self.hit(20 * self.cp + 20); self.cp = 0
        if spell == "Ferocious Bite": self.hit(30 + 25 * self.cp); self.cp = 0
        if spell == "Swipe": self.hit(18)
        if spell == "Moonfire": self.hit(30)
        if spell == "Wrath": self.hit(40)

    def hit(self, amount):
        self.target_hp -= amount
        if self.target_hp <= 0:
            self.kills += 1
            self.enemies_left -= 1
            self.target_hp = self.hp_max
            if self.cp_on_target: self.cp = 0

    def try_spell(self, spell):
        if spell not in SPELL:
            return False
        if SPELL[spell][2]:
            if self.gcd_tried:
                return False
            self.gcd_tried = True  # even a refused one
        return self.attempt(spell)

    def press(self):
        self.gcd_tried = False
        for line in self.lines:
            line = line.strip()
            if line == "/startattack":
                self.attack = True
                continue
            m = re.match(r"/(castsequence|cast)\s+(.*)", line)
            if not m: continue
            found = self.clause(m.group(2))
            if not found: continue
            key, action = found
            if m.group(1) == "cast":
                self.try_spell(action)
                continue
            rm = re.match(r"reset=(\S+)\s+(.*)", action)
            spells = [x.strip() for x in (rm.group(2) if rm else action).split(",")]
            step = self.sequences.get(key, 0)
            spell = spells[step % len(spells)]
            if spell == "nil": continue
            if self.follow_prompt and self.next_finisher_waits(spell) and self.power >= 40 and self.t >= self.gcd_until:
                self.gcd_tried = True  # you press Claw on its own key (the icon's prompt) instead of the button
                self.power -= 40; self.gcd_until = self.t + 1.0; self.done("Claw")
                continue
            if self.try_spell(spell):
                self.sequences[key] = step + 1

    def next_finisher_waits(self, spell):
        return spell in FINISHERS and self.cp == 0

    def tick(self, dt):
        self.t += dt
        if self.form == "cat":
            self.power = min(100, self.power + 10 * dt)
        if not self.in_combat: return
        if self.form == "cat":
            for line in self.lines:
                found = self.clause(line[len("/castsequence "):]) if line.startswith("/castsequence") else None
                if found and ("Claw" in found[1]):
                    spells = [x.strip() for x in found[1].split(" ", 1)[1].split(",")]
                    if spells[self.sequences.get(found[0], 0) % len(spells)] in FINISHERS and self.cp == 0:
                        self.stuck += dt
        if self.form == "caster": self.power = min(400, self.power + 2 * dt)
        if self.form == "bear" and self.t < self.enrage_until: self.power = min(100, self.power + 2 * dt)
        if self.t >= self.swing_at:
            self.swing_at += 2.5 if self.form == "bear" else 1.0
            if self.maul_queued and self.power >= 15:
                self.power -= 15
                self.maul_queued = False
                self.casts["Maul"] = self.casts.get("Maul", 0) + 1
                self.hit(30)
            else:
                self.maul_queued = False
                if self.form == "bear": self.power = min(100, self.power + 4)
                self.hit(12 if self.form != "caster" else 0)
        if self.form == "bear" and self.t >= self.enemy_swing_at:
            self.enemy_swing_at += 2.0 / max(1, min(3, self.enemies_left))
            self.power = min(100, self.power + 5)

    def play(self):
        next_press = 0.0
        while self.t < self.seconds and self.enemies_left > 0:
            if self.t >= next_press:
                self.press()
                if getattr(self, "attack", False) and self.form != "caster": self.in_combat = True
                next_press += 0.3
            self.tick(0.1)
        return self


fails = []


def check(name, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + name + (("  [" + str(detail) + "]") if detail and (VERBOSE or not ok) else ""))
    if not ok:
        fails.append(name)


def run(name, body, form, seeds=range(1, 11), **kw):
    total, refused, kills, stuck, secs = {}, {}, 0, 0.0, 0.0
    for seed in seeds:
        f = Fight(body, form, seed=seed, **kw).play()
        for k, v in f.casts.items(): total[k] = total.get(k, 0) + v
        for k, v in f.refused.items(): refused[k] = refused.get(k, 0) + v
        kills += f.kills; stuck += f.stuck; secs += f.t
    n = len(list(seeds))
    per = {k: round(v / n, 1) for k, v in sorted(total.items())}
    summary = f"per fight {per}, kills {kills / n:.1f}, {secs / n:.0f} s, stuck on finisher {stuck / n:.1f} s, refused {refused}"
    if VERBOSE: print(f"-- {name}: {summary}")
    return per, stuck / n, summary


# The model must show the proven rule: a refused first global-cooldown line blocks the lines after it.
per, _, s = run("rule: refused finisher first", "/startattack\n/cast [form:3] Ferocious Bite\n/cast [form:3] Claw", "cat", seconds=20)
check("rule replay: a finisher refused first takes every press, Claw never casts", per.get("Claw", 0) == 0, s)

FORMS = ["bear", "aquatic", "cat"]
body24 = build(LV24, FORMS)
body32 = build(LV32, FORMS + ["travel"])
check("level 24 macro fits", len(body24) <= 255, len(body24))
check("level 32 macro fits", len(body32) <= 255, len(body32))

# Cat Form.
per, stuck, s = run("cat lvl 24, one enemy", body24, "cat")
check("cat 24: Tiger's Fury once per pull", per.get("Tiger's Fury", 0) == 1.0, s)
check("cat 24: Rake, Claw and Rip all cast", per.get("Rake", 0) >= 1 and per.get("Claw", 0) >= 3 and per.get("Rip", 0) >= 1, s)
check("cat 24: the enemy dies", "kills 1.0" in s, s)
per, stuck, s = run("cat lvl 32, one enemy", body32, "cat")
check("cat 32: Ferocious Bite finishes", per.get("Ferocious Bite", 0) >= 1 and per.get("Rake", 0) >= 1, s)
per, stuck_t, s_t = run("cat lvl 32, 3 enemies, combo points on the target", body32, "cat", enemies=3, seconds=90)
per_p, stuck_p, s_p = run("cat lvl 32, 3 enemies, combo points on you", body32, "cat", enemies=3, seconds=90, cp_on_target=False)
check("cat 32, 3 enemies: all three die either way", "kills 3.0" in s_t and "kills 3.0" in s_p, s_t + " | " + s_p)
check("cat, combo points on you: the sequence never waits on its finisher", stuck_p == 0, s_p)
per_f, stuck_f, s_f = run("cat lvl 32, 3 enemies, on the target, you follow the icon's Claw prompt", body32, "cat", enemies=3, seconds=90, follow_prompt=True)
check("cat, combo points on the target: one Claw on its own key when the icon asks cuts the wait to a few seconds (energy)", stuck_f < 5 and "kills 3.0" in s_f, s_f)
print(f"KNOWN LIMIT cat, 3 enemies, combo points on the target: waits {stuck_t:.1f} s per pull on a finisher with no combo points "
      "(the icon asks for one Claw on its own key); the button never casts Claw itself until the fight ends.")

# Two pulls with the same macro: reset=combat starts every sequence over.
f1 = Fight(body24, "cat", seed=3, enemies=1).play()
carried = {k: v for k, v in f1.sequences.items() if "reset=combat" not in k}
f2 = Fight(body24, "cat", seed=4, enemies=1)
f2.sequences = carried
f2.play()
check("second pull: Tiger's Fury and Rake again (reset=combat)", f2.casts.get("Tiger's Fury", 0) == 1 and f2.casts.get("Rake", 0) >= 1, str(f2.casts))

# Bear Form.
per, _, s = run("bear lvl 24 solo", body24, "bear")
check("bear solo: Maul on most swings", per.get("Maul", 0) >= 8, s)
check("bear solo: Enrage and Demoralizing Roar once", per.get("Enrage", 0) == 1.0 and per.get("Demoralizing Roar", 0) == 1.0, s)
check("bear solo: no Swipe", per.get("Swipe", 0) == 0, s)
body_g = build(LV24, FORMS, group=True)
per, _, s = run("bear lvl 24 group, 3 enemies", body_g, "bear", group=True, enemies=3, seconds=60)
check("bear in a group: Swipe and Maul both cast", per.get("Swipe", 0) >= 3 and per.get("Maul", 0) >= 5, s)

# Caster.
per, _, s = run("caster lvl 24", body24, "caster")
check("caster: Faerie Fire is out of the level 24 macro (left out to fit)", "Faerie Fire" not in body24 and per.get("Faerie Fire", 0) == 0, s)
check("caster: Moonfire once, then Wrath", per.get("Moonfire", 0) == 1.0 and per.get("Wrath", 0) >= 4, s)
per, _, s = run("caster lvl 32", body32, "caster")
check("caster 32: Faerie Fire then Moonfire once each, then Wrath",
      per.get("Faerie Fire", 0) == 1.0 and per.get("Moonfire", 0) == 1.0 and per.get("Wrath", 0) >= 4, s)

if VERBOSE:
    print(body24)
    print(body32)
if fails:
    sys.exit(f"{len(fails)} failed")
print("all passed")
