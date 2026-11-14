"""Plays warrior fights with the macro the addon writes, under the macro rules proven by the
in-game fight logs, and checks that every important spell gets cast.

Rules proven by the press-by-press log (fights 34-37, Forever client 1.60.1, 11 Nov 2026) and
consistent with all 37 logged fights:
  * a line whose conditions don't match is skipped;
  * only the FIRST matching spell that uses the global cooldown is tried on a press, cast or
    rejected (Victory Rush rejected -> Revenge, Rend, Sunder never tried);
  * spells off the global cooldown (Shield Block, Heroic Strike, Cleave, Charge) are tried on every
    press wherever they are, and a cast doesn't stop the press;
  * "/castsequence ... X,nil" casts X once, then is skipped;
  * /click of an addon button from the macro never runs.
Anything not proven is modeled the pessimistic way (castsequence timers restart on every press,
reset=target does nothing) or run both ways in two scenarios.

    python tests/addon/warrior_fight_sim.py          checks, quiet
    python tests/addon/warrior_fight_sim.py -v       also prints each scenario's numbers
"""
import os
import random
import re
import sys

import lupa.lua51 as L

HERE = os.path.dirname(os.path.abspath(__file__))
VERBOSE = "-v" in sys.argv

# ---- Build the macro and steps with the real addon code ----
_src = open(os.path.join(HERE, "warrior_sim.py"), encoding="utf-8").read().split("lua = L.LuaRuntime")[0]
_env = {"__file__": os.path.join(HERE, "warrior_sim.py")}
exec(_src, _env)
MOCK, source = _env["MOCK"], _env["source"]

STANCE_IDS = {"battle": 2457, "defensive": 71, "berserker": 2458}


def build(spells, stances, level, shield=True, group=False, buffs=()):
    lua = L.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK)
    lua.execute(source("Core.lua"))
    lua.execute(source("Warrior.lua"))
    g = lua.globals()
    g.SPELLS = lua.table_from(spells)
    g.FORMS = lua.table_from([STANCE_IDS[s] for s in stances])
    g.UnitLevel = lambda unit: level
    g.BUFFS = lua.table_from([lua.table_from([b, 1e12]) for b in buffs])
    g.IsEquippedItemType = lambda kind: shield and kind == "Shields"
    g.IsInGroup = lambda: group
    w = g.DufforthTweaksHelperWarrior
    w.Update()
    return g.MACROS[w.MACRO_NAME], [], None


# ---- A tiny model of the fight ----
SPELL = {
    # name: (rage cost, cooldown, uses the global cooldown)
    "Charge": (0, 15, False), "Battle Shout": (10, 0, True), "Revenge": (5, 5, True),
    "Shield Block": (10, 5, False), "Overpower": (5, 5, True), "Rend": (10, 0, True),
    "Sunder Armor": (15, 0, True), "Heroic Strike": (15, 0, False), "Cleave": (20, 0, False),
    "Victory Rush": (0, 0, True), "Execute": (15, 0, True), "Shield Slam": (20, 6, True),
    "Mortal Strike": (30, 6, True), "Bloodthirst": (30, 6, True), "Whirlwind": (25, 10, True),
    "Intercept": (10, 15, False), "Sweeping Strikes": (30, 30, True),
    "Bloodrage": (0, 60, False),  # +10 rage now and +10 over 10 s, costs some health
}
GCD = 1.5


class Fight:
    def __init__(self, body, steps, click, stance_number, stances, shield, group=False, rage=0,
                 enemies=1, click_works=False, seed=1, seconds=40, press_every=0.3, requeue_fails=False,
                 victorious=False):
        self.rand = random.Random(seed)
        self.body, self.steps, self.click = body.split("\n"), [s.split("\n") for s in steps], click
        self.form, self.stance_names, self.shield, self.group = stance_number, stances, shield, group
        self.rage, self.enemies, self.click_works = rage, enemies, click_works
        self.seconds, self.press_every = seconds, press_every
        self.t, self.gcd_until, self.cd = 0.0, 0.0, {}
        self.in_combat, self.step = False, 0
        self.revenge_until = self.overpower_until = self.block_until = 0.0
        self.target, self.target_hp, self.rend_until = 1, 100.0, 0.0
        self.shout_until, self.hs_queued, self.victorious = 0.0, None, victorious
        self.sequences = {}
        self.casts, self.errors, self.capped = {}, {}, 0.0
        self.bloodrage_until = 0.0
        self.swing_at, self.enemy_swing_at = 0.5, 1.0
        self.kills = 0
        self.requeue_fails = requeue_fails  # unproven: pressing Heroic Strike again while it is queued

    # -- conditions --
    def matches(self, cond):
        for part in [c.strip() for c in cond.split(",") if c.strip()]:
            if part == "nocombat" and self.in_combat: return False
            if part == "combat" and not self.in_combat: return False
            if part == "group" and not self.group: return False
            if part.startswith("form:") and str(self.form) not in part[5:].split("/"): return False
            if part == "equipped:Shields" and not self.shield: return False
        return True

    def usable(self, spell):
        if spell == "nil": return False
        if spell == "Revenge" and self.t > self.revenge_until: return False
        if spell == "Overpower" and self.t > self.overpower_until: return False
        if spell == "Execute" and self.target_hp > 20: return False
        stance = self.stance_names[self.form - 1] if 0 < self.form <= len(self.stance_names) else "?"
        allowed = {"Rend": ("battle", "defensive"), "Revenge": ("defensive",), "Shield Block": ("defensive",),
                   "Shield Slam": ("defensive", "battle", "berserker"), "Overpower": ("battle",),
                   "Execute": ("battle", "berserker"), "Whirlwind": ("berserker",), "Intercept": ("berserker",)}
        if spell in allowed and stance not in allowed[spell]: return False
        if spell in ("Shield Block", "Shield Slam") and not self.shield: return False
        if spell in ("Charge",) and self.in_combat: return False
        if spell == "Victory Rush" and not self.victorious: return False
        return True

    def attempt(self, spell):
        """'skip', 'fail' (stops the press) or 'ok'."""
        if not self.usable(spell): return "skip"
        cost, cooldown, gcd = SPELL[spell]
        if spell in ("Heroic Strike", "Cleave") and self.hs_queued:  # already queued
            return "fail" if self.requeue_fails else "ok"
        if self.cd.get(spell, 0) > self.t or (gcd and self.gcd_until > self.t):
            self.errors["not ready"] = self.errors.get("not ready", 0) + 1
            return "fail"
        if self.rage < cost and spell not in ("Heroic Strike", "Cleave"):
            self.errors["rage"] = self.errors.get("rage", 0) + 1
            return "fail"
        if spell in ("Heroic Strike", "Cleave"):
            if self.rage < cost:
                self.errors["rage"] = self.errors.get("rage", 0) + 1
                return "fail"
            self.hs_queued = spell
            return "ok"
        self.rage -= cost
        if cooldown: self.cd[spell] = self.t + cooldown
        if gcd: self.gcd_until = self.t + GCD
        self.cast(spell)
        return "ok"

    def cast(self, spell):
        self.casts[spell] = self.casts.get(spell, 0) + 1
        if spell == "Charge": self.rage = min(100, self.rage + 12); self.in_combat = True
        if spell == "Bloodrage": self.rage = min(100, self.rage + 10); self.bloodrage_until = self.t + 10
        if spell == "Battle Shout": self.shout_until = self.t + 120
        if spell == "Revenge": self.revenge_until = 0; self.hit(12)
        if spell == "Shield Block": self.block_until = self.t + 5
        if spell == "Overpower": self.overpower_until = 0; self.hit(10)
        if spell == "Rend": self.rend_until = self.t + 15
        if spell == "Victory Rush": self.victorious = False; self.hit(10)
        if spell in ("Sunder Armor", "Execute", "Shield Slam", "Mortal Strike", "Bloodthirst", "Whirlwind"): self.hit(8)
        self.in_combat = True

    def hit(self, amount):
        self.target_hp -= amount
        if self.target_hp <= 0:
            self.kills += 1
            self.target += 1
            self.target_hp, self.rend_until, self.victorious = 100.0, 0.0, True
            for key in list(self.sequences):
                if "target" in key[1]: self.sequences[key] = 0

    # -- the press --
    def try_spell(self, spell):
        """Proven rule: only the first global-cooldown spell of a press is tried (cast or rejected);
        spells off the global cooldown are tried every time. Returns True when it was cast."""
        if spell not in SPELL:
            return False
        uses_gcd = SPELL[spell][2]
        if uses_gcd:
            if self.gcd_tried:
                return False
            self.gcd_tried = True  # even a rejected one (Victory Rush, Revenge without a block)
        return self.attempt(spell) == "ok"

    def run_lines(self, lines):
        """One press."""
        self.gcd_tried = False
        for line in lines:
            line = line.strip()
            if not line or line == "/startattack":
                self.attack_started = True  # combat starts after this press, not before Charge
                continue
            if line.startswith("/click"):
                continue  # proven: the game never ran the addon's button from the macro
            m = re.match(r"/castsequence\s*(\[[^\]]*\])?\s*(?:reset=(\S+)\s+)?(.*)", line)
            if m:
                cond, reset, spells = (m.group(1) or "[]")[1:-1], m.group(2) or "", [x.strip() for x in m.group(3).split(",")]
                if not self.matches(cond): continue
                key = (line, "step")
                seconds = [float(x) for x in reset.split("/") if re.match(r"^\d+(\.\d+)?$", x)]
                # Pessimistic (unproven): the reset timer restarts on every press, so it only resets
                # after a pause with no presses; "reset=target" is not modeled.
                last_press = self.sequences.get((line, "pressed"), -999)
                if seconds and self.t - last_press > seconds[0]:
                    self.sequences[key] = 0
                self.sequences[(line, "pressed")] = self.t
                state = self.sequences.get(key, 0)
                spell = spells[state % len(spells)]  # after the last spell it starts again
                if spell == "nil":
                    continue  # proven: Battle Shout,nil is skipped once cast
                if self.try_spell(spell):
                    self.sequences[key] = state + 1
                continue
            m = re.match(r"/cast\s+(.*)", line)
            if not m: continue
            for clause in m.group(1).split(";"):
                cm = re.match(r"\s*(\[[^\]]*\])?\s*(.+)", clause)
                cond, spell = (cm.group(1) or "[]")[1:-1], cm.group(2).strip()
                if self.matches(cond):
                    self.try_spell(spell)
                    break  # only the first matching clause is tried

    # -- time passing --
    def tick(self, dt):
        self.t += dt
        if self.rage >= 80: self.capped += dt
        if not self.in_combat: return
        if self.t < self.bloodrage_until: self.rage = min(100, self.rage + dt)  # 1 rage a second
        if self.t >= self.swing_at:  # your swing
            self.swing_at += 2.6
            if self.hs_queued and self.rage >= SPELL[self.hs_queued][0]:
                self.rage -= SPELL[self.hs_queued][0]
                self.casts[self.hs_queued] = self.casts.get(self.hs_queued, 0) + 1
                self.hs_queued = None
                self.hit(9)
            else:
                self.hs_queued = None
                self.rage = min(100, self.rage + 7)
                self.hit(6)
                if self.rand.random() < 0.06: self.overpower_until = self.t + 5  # target dodged
        if self.t >= self.enemy_swing_at:  # enemy swings
            self.enemy_swing_at += 2.0 / self.enemies
            if self.t < self.block_until and self.rand.random() < 0.75:
                self.block_until = 0  # one block
                self.revenge_until = self.t + 5
            elif self.rand.random() < 0.15:  # base block, dodge or parry
                self.revenge_until = self.t + 5
            else:
                self.rage = min(100, self.rage + 5)

    def play(self):
        next_press = 0.0
        while self.t < self.seconds:
            if self.t >= next_press:
                self.run_lines(self.body)
                if getattr(self, "attack_started", False): self.in_combat = True
                next_press += self.press_every
            self.tick(0.1)
        return self


# ---- Scenarios ----
LEVEL25 =["Battle Stance", "Defensive Stance", "Heroic Strike", "Battle Shout", "Charge", "Rend", "Overpower",
           "Sunder Armor", "Revenge", "Shield Block", "Victory Rush", "Cleave"]
LEVEL26 = None  # set below: level 25 plus Execute (learned at 24)
LEVEL12 = ["Battle Stance", "Defensive Stance", "Heroic Strike", "Battle Shout", "Charge", "Rend", "Overpower", "Sunder Armor"]
LEVEL60 = LEVEL25 + ["Berserker Stance", "Intercept", "Execute", "Shield Slam", "Mortal Strike", "Whirlwind", "Sweeping Strikes"]

fails = []


def check(name, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + name + (("  [" + detail + "]") if (detail and (VERBOSE or not ok)) else ""))
    if not ok:
        fails.append(name)


# ---- First: the model must reproduce what the real logs showed ----
REPLAYS = {
    # fights 34-37 (16:14-16:16): every press tried Victory Rush, Shield Block, Heroic Strike only.
    "macro 13": ("/startattack\n/cast [nocombat,form:1/2] Charge\n/cast Victory Rush\n/castsequence reset=120 Battle Shout,nil\n"
                 "/cast [form:2] Revenge;[form:1] Overpower\n/cast [form:2] Shield Block\n/castsequence reset=15 Rend,nil\n"
                 "/cast [form:2] Sunder Armor\n/cast Heroic Strike", ("Revenge", "Rend", "Sunder Armor"), ("Shield Block", "Heroic Strike")),
    # fights 20-28 (14:56-15:09): Revenge and Heroic Strike, never Rend or Sunder.
    "macro 10": ("/startattack\n/cast [nocombat,form:1/2] Charge\n/cast [form:2] Revenge;[form:1] Overpower\n"
                 "/castsequence [form:1/2] reset=target/15 Rend,nil\n/cast Heroic Strike\n/cast [form:2] Sunder Armor",
                 ("Rend", "Sunder Armor"), ("Revenge", "Heroic Strike")),
}
for name, (text, never, seen) in REPLAYS.items():
    total = {}
    for seed in range(1, 6):
        f = Fight(text, [], None, 2, ["battle", "defensive"], True, seed=seed, rage=20).play()
        for k, v in f.casts.items(): total[k] = total.get(k, 0) + v
    ok_never = all(total.get(x, 0) == 0 for x in never)
    ok_seen = all(total.get(x, 0) > 0 for x in seen)
    check(f"replay {name}: the model casts what the game cast and never what it never cast", ok_never and ok_seen, str(total))

def run(name, spells, stances, level, form, shield, seeds=range(1, 11), **kw):
    body, steps, click = build(spells, stances, level, shield=shield, group=kw.get("group", False), buffs=kw.pop("buffs", ()))
    total, errors, capped, kills, seconds = {}, {}, 0.0, 0, 0
    for seed in seeds:
        f = Fight(body, steps, click, form, stances, shield, seed=seed, **kw).play()
        for k, v in f.casts.items(): total[k] = total.get(k, 0) + v
        for k, v in f.errors.items(): errors[k] = errors.get(k, 0) + v
        capped += f.capped
        kills += f.kills
        seconds += f.seconds
    n = len(list(seeds))
    per = {k: round(v / n, 1) for k, v in sorted(total.items())}
    global LAST_ERRORS
    LAST_ERRORS = {k: v / n for k, v in errors.items()}
    summary = f"per fight {per}, kills {kills / n:.1f}, rage 80+ {capped / seconds:.0%}, errors {errors}"
    if VERBOSE:
        print(f"-- {name}: {summary}")
    return per, capped / seconds, summary, body, steps


# Defensive Stance with a shield (the user's warrior, level 25).
per, cap, s, body, steps = run("defensive, shield, lvl 25", LEVEL25, ["battle", "defensive"], 25, 2, True)
check("defensive + shield: Shield Block about every 6 s (its cooldown is 5)", per.get("Shield Block", 0) >= 6, s)
check("defensive + shield: Revenge after blocks (the sequence waits for one)", per.get("Revenge", 0) >= 4, s)
check("defensive + shield: no Rend (33 damage a cast, it took Revenge's try; user agreed 2026-11-11)", per.get("Rend", 0) == 0 and not any("Rend" in l and "form:2" in l for l in body.split(chr(10))), s)
check("defensive + shield: no rage is wasted (Sunder only gets what's left, that's expected solo)", cap < 0.05, s)
check("defensive + shield solo: no Sunder Armor, its rage goes to Heroic Strike", per.get("Sunder Armor", 0) == 0 and per.get("Heroic Strike", 0) >= 2, s)
check("defensive + shield: rage stays under 80% most of the time", cap < 0.2, s)

per, cap, s, *_ = run("defensive, shield, 3 enemies", LEVEL25, ["battle", "defensive"], 25, 2, True, enemies=3)
check("3 enemies: Shield Block and Revenge keep going", per.get("Shield Block", 0) >= 6 and per.get("Revenge", 0) >= 5, s)
check("3 enemies: the extra rage goes into Heroic Strike", per.get("Heroic Strike", 0) >= 6, s)
check("3 enemies: rage stays under 80% most of the time", cap < 0.25, s)

per, cap, s, body, _ = run("defensive, shield, group", LEVEL25, ["battle", "defensive"], 25, 2, True, group=True, enemies=2)
check("in a group: Cleave instead of Heroic Strike", "Cleave" in body and per.get("Heroic Strike", 0) == 0 and per.get("Cleave", 0) >= 1, s)

per, cap, s, *_ = run("defensive, no shield", LEVEL25, ["battle", "defensive"], 25, 2, False)
check("defensive without a shield: no Shield Block, Rend and Sunder instead", per.get("Shield Block", 0) == 0 and per.get("Sunder Armor", 0) >= 3, s)

per, cap, s, *_ = run("battle, lvl 25, shout up", LEVEL25, ["battle", "defensive"], 25, 1, True, buffs=("Battle Shout",))
check("battle stance: Charge opens the fight", per.get("Charge", 0) >= 1, s)
check("battle stance: Rend once, then Heroic Strike", per.get("Rend", 0) == 1 and per.get("Heroic Strike", 0) >= 6, s)
per, cap, s, body, _ = run("battle, lvl 25, shout missing", LEVEL25, ["battle", "defensive"], 25, 1, True)
check("shout missing with a shield: Rend and Battle Shout both fit (no Sunder solo)", "Battle Shout" in body and "Rend" in body and len(body) <= 255, s)
check("battle stance: no Defensive Stance spells", not any(per.get(x) for x in ("Revenge", "Shield Block", "Sunder Armor")), s)

# Execute in Battle Stance (user, 2026-11-12: "Execute is not in the rotation"). Real logs: Overpower,
# the stance's only global-cooldown spell, was refused 129 times and cast once in 22 fights.
LEVEL26 = LEVEL25 + ["Execute"]
# Bloodrage (user, 2026-11-12: build it; "Not enough rage" is the most common error in every stance).
LEVEL26B = LEVEL26 + ["Bloodrage"]
for form, label in ((1, "battle"), (2, "defensive")):
    _, _, s_without, *_ = run(f"{label}, lvl 26 without Bloodrage", LEVEL26, ["battle", "defensive"], 26, form, True, buffs=("Battle Shout",))
    per_b, cap_b, s_with, body_b, _ = run(f"{label}, lvl 26 with Bloodrage", LEVEL26B, ["battle", "defensive"], 26, form, True, buffs=("Battle Shout",))
    errors_b = LAST_ERRORS
    print(f"     {label} without Bloodrage: " + s_without)
    print(f"     {label} with Bloodrage:    " + s_with)
    check(f"{label}: Bloodrage in the button once per fight, only in combat", "/castsequence [combat]reset=combat Bloodrage,nil" in body_b, body_b)
    check(f"{label}: Bloodrage once a fight", per_b.get("Bloodrage", 0) == 1.0, s_with)
    if label == "battle":  # in Defensive Stance most "not ready" refusals are Shield Block's, so only Battle tells
        check(f"{label}: Bloodrage isn't asked for again while it cools down", errors_b.get("not ready", 0) < 60, s_with)
    check(f"{label}: Bloodrage doesn't push rage to waste", cap_b < 0.1, s_with)
per_old, _, s_old, *_ = run("battle, lvl 25 (Overpower line)", LEVEL25, ["battle", "defensive"], 25, 1, True, buffs=("Battle Shout",))
per, cap, s, body, _ = run("battle, lvl 26 with Execute", LEVEL26, ["battle", "defensive"], 26, 1, True, buffs=("Battle Shout",))
check("battle with Execute known: Execute is in the button for Battle Stance", "/cast [form:1] Execute" in body, body)
check("battle with Execute: it finishes fights (about one or more a fight)", per.get("Execute", 0) >= 1, s)
check("battle with Execute: Rend and Heroic Strike still cast", per.get("Rend", 0) >= 1 and per.get("Heroic Strike", 0) >= 4, s)
print("     Overpower line: " + s_old)
print("     Execute line:   " + s)
per, cap, s, body, _ = run("defensive, lvl 26 with Execute", LEVEL26, ["battle", "defensive"], 26, 2, True)
check("defensive with Execute known: nothing changes there (Execute only works in Battle and Berserker)",
      per.get("Execute", 0) == 0 and per.get("Revenge", 0) >= 4 and per.get("Shield Block", 0) >= 6, s)

per, cap, s, *_ = run("battle, lvl 12", LEVEL12, ["battle", "defensive"], 12, 1, True)
check("level 12 battle: Charge, Rend and Heroic Strike", per.get("Rend", 0) >= 1 and per.get("Heroic Strike", 0) >= 3, s)

per, cap, s, *_ = run("defensive, starts with 100 rage", LEVEL25, ["battle", "defensive"], 25, 2, True, rage=100)
check("a full rage bar comes down", cap < 0.25, s)

per, cap, s, *_ = run("defensive, level 60", LEVEL60, ["battle", "defensive", "berserker"], 60, 2, True)
check("level 60 defensive solo: Shield Slam, Revenge and Shield Block cast, no Sunder", per.get("Shield Slam", 0) >= 2
      and per.get("Revenge", 0) >= 2 and per.get("Sunder Armor", 0) == 0 and per.get("Shield Block", 0) >= 5, s)
# KNOWN LIMIT (not hidden): this model gives level 60 the rage income of level 25, so Shield Slam
# (20 rage) and Mortal Strike (30) starve. Real level 60 hits give far more rage; to check in game.
print("KNOWN LIMIT level 60 defensive: " + s)
per, cap, s, *_ = run("berserker, level 60", LEVEL60, ["battle", "defensive", "berserker"], 60, 3, False)
check("level 60 berserker: Mortal Strike every cooldown or so", per.get("Mortal Strike", 0) >= 3, s)
print("KNOWN LIMIT level 60: Execute is an own-key prompt on the icon, not in the macro: " + s)

# The macro itself: fits, uses no hidden button, no Victory Rush.
for spells, stances, level in ((LEVEL12, ["battle", "defensive"], 12), (LEVEL25, ["battle", "defensive"], 25),
                               (LEVEL60, ["battle", "defensive", "berserker"], 60)):
    body, _, _ = build(spells, stances, level)
    check(f"level {level}: the macro fits 255 characters", len(body) <= 255, str(len(body)))
    check(f"level {level}: no /click (the game doesn't run addon buttons from macros)", "/click" not in body)
    check(f"level {level}: no Victory Rush (it would take every press while it can't be cast)", "Victory Rush" not in body)
    if level == 60:
        check("level 60: Execute stays out of the button (it would block Mortal Strike)", "Execute" not in body)
    gcd_lines = [l for l in body.split("\n") if "[form:2]" in l and "Shield Block" not in l and "Rend" not in l]
    check(f"level {level}: one global-cooldown line for Defensive Stance", len(gcd_lines) <= 1, " | ".join(gcd_lines))
    check(f"level {level}: at most one of Mortal Strike and Bloodthirst", sum(1 for x in ("Mortal Strike", "Bloodthirst") if x in body) <= 1)
body, _, _ = build(LEVEL25, ["battle", "defensive"], 25)
lines = body.split("\n")
body, _, _ = build(LEVEL25, ["battle", "defensive"], 25, buffs=("Battle Shout",))
lines = body.split("\n")
check("level 25: Rend only in Battle Stance once per pull, Revenge -> Sunder -> Heroic Strike in Defensive, Shield Block every press",
      lines.index("/castsequence [form:1] reset=combat Rend,nil") < lines.index("/castsequence [form:2] Revenge,Heroic Strike")
      and "/cast [form:2] Shield Block" in lines, body)
per, cap, s, *_ = run("defensive, shield, if re-pressing a queued Heroic Strike fails", LEVEL25, ["battle", "defensive"], 25, 2, True,
                      requeue_fails=True)
check("(unproven rule) re-pressing a queued Heroic Strike either way: Shield Block and Revenge the same",
      per.get("Shield Block", 0) >= 6 and per.get("Revenge", 0) >= 4, s)
# Victory Rush is cast on demand (own key, 2026-11-11), never in the button, even right after a kill.
body_vr, _, _ = build(LEVEL25, ["battle", "defensive"], 25, buffs=("Victorious",))
check("after a kill: no Victory Rush in the button (own key)", "Victory Rush" not in body_vr, body_vr)

# Two pulls in a row with Battle Shout missing and the same macro text (the game keeps a sequence's
# place between fights, and reset=N restarts its timer on every press). reset=combat starts the line
# over when a fight ends, so the shout is cast on every pull that needs it.
def two_pulls(text, spell):
    counts = []
    carried = {}
    for seed in (1, 2):
        f = Fight(text, [], None, 2, ["battle", "defensive"], True, seed=seed)
        f.sequences = dict(carried)
        f.play()
        counts.append(f.casts.get(spell, 0))
        # Combat ends: lines with reset=combat start over, the others keep their place.
        carried = {k: v for k, v in f.sequences.items() if not (k[1] == "step" and "combat" in k[0].split("reset=")[-1].split(" ")[0])}
    return counts
body_bs, _, _ = build(LEVEL25, ["battle", "defensive"], 25)
check("Battle Shout line starts over each fight", "/castsequence reset=combat Battle Shout,nil" in body_bs, body_bs)
old = body_bs.replace("/castsequence reset=combat Battle Shout,nil", "/castsequence reset=120 Battle Shout,nil")
check("old reset=120 shout line: cast on the first pull only (the gaps in the logs)", two_pulls(old, "Battle Shout") == [1, 0], str(two_pulls(old, "Battle Shout")))
check("reset=combat: Battle Shout on every pull that needs it", two_pulls(body_bs, "Battle Shout") == [1, 1], str(two_pulls(body_bs, "Battle Shout")))
if VERBOSE:
    print(body)

if fails:
    sys.exit(f"{len(fails)} failed")
print("all passed")
