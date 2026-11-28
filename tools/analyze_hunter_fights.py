"""Hunter fight log analysis: what your fights show and what to change (user, 2026-11-25: "learn about this to improve
my rotation and recommend the most efficient way to play").

    python tools/analyze_hunter_fights.py "<game folder>" [--last N]

Reads every account's SavedVariables/DufforthTweaksHelper.lua (written on /reload or logout; the Hunter fight log in
Hunter.lua). The math runs here with pandas; only the summary prints. Needs `pip install lupa pandas`.
"""
import argparse
import glob
import os
import re

import lupa.lua51 as L
import pandas as pd

SHARED_CD = 6.0      # Summon Hawk and Arcane Shot share it (user, 2026-11-25)
HAWK_SECONDS = 18.0
CAST = re.compile(r"^(-?\d+(?:\.\d+)?) (.+?) t:(\S*) h:(\d+)$")
TRY = re.compile(r"^(-?\d+(?:\.\d+)?) (\S+) (.+)$")


def items(table):
    return list(table.items()) if table is not None else []


def load(game):
    fights, macros = [], {}
    for path in sorted(glob.glob(os.path.join(game, "WTF", "Account", "*", "SavedVariables", "DufforthTweaksHelper.lua"))):
        lua = L.LuaRuntime(unpack_returned_tuples=True)
        lua.execute(open(path, encoding="utf-8", errors="replace").read())
        db = lua.globals().DufforthTweaksHelperDB
        hunter = db and db.hunter
        if hunter is None:
            continue
        account = os.path.basename(os.path.dirname(os.path.dirname(path)))
        for i, text in items(hunter.macros):
            macros[(account, int(i))] = str(text)
        for _, f in items(hunter.fights):
            casts = [m.groups() for _, c in items(f.casts) if (m := CAST.match(str(c)))]
            tries = [m.groups() for _, t in items(f.tries) if (m := TRY.match(str(t)))]
            fights.append({
                "account": account, "at": f.at, "character": f.character, "zone": f.zone, "level": f.level,
                "seconds": float(f.seconds or 0), "result": f.result, "group": bool(f.group), "pet": f.pet,
                "petAlive": bool(f.petAlive), "manaStart": f.manaStart, "manaEnd": f.manaEnd, "enemies": f.enemiesMax or 0,
                "autoShots": f.autoShots or 0, "hawkOver": f.hawkOver or 0, "markRepeats": f.markRepeats or 0,
                "mongooseWindows": f.mongooseWindows or 0, "mongooseUsed": f.mongooseUsed or 0,
                "errors": {str(k): int(v) for k, v in items(f.errors)}, "macros": str(f.macros or ""),
                "casts": [(float(t), s, tgt, int(h)) for t, s, tgt, h in casts],
                "tries": [(float(t), k, n) for t, k, n in tries],
                "damage": f.damage if f.damage is not None else None,
                "autoTimes": [float(v) for _, v in items(f.autoTimes)],
            })
    return fights, macros


def summarize(fights):
    df = pd.DataFrame([{k: v for k, v in f.items() if k not in ("casts", "tries", "errors")} for f in fights])
    casts = pd.DataFrame([(i, t, s, tgt, h) for i, f in enumerate(fights) for t, s, tgt, h in f["casts"]],
                         columns=["fight", "t", "spell", "target", "hawks"])
    tries = pd.DataFrame([(i, t, k, n) for i, f in enumerate(fights) for t, k, n in f["tries"]], columns=["fight", "t", "kind", "name"])
    errors = pd.Series({}, dtype=int)
    for f in fights:
        errors = errors.add(pd.Series(f["errors"], dtype=int), fill_value=0)
    return df, casts, tries, errors.sort_values(ascending=False)


CLIP_SPELLS = ("Arcane Shot", "Aimed Shot", "Multi-Shot")
CLIP_MIN = 0.15  # seconds longer than a plain gap before a spell counts as delaying Auto Shot


def clipping(fights):
    """Gaps between Auto Shots: plain ones (no shot cast in between) give your weapon's own pace; gaps holding an
    Arcane, Aimed or Multi-Shot cast show whether that shot delays the next Auto Shot. Gaps over 2.5x the pace
    (you moved, went to melee) are left out. None when no Auto Shot times were saved yet."""
    rows = []
    for f in fights:
        autos = f.get("autoTimes") or []
        shots = [(t, s) for t, s, _, _ in f["casts"] if s in CLIP_SPELLS]
        for a, b in zip(autos, autos[1:]):
            inside = {s for t, s in shots if a < t <= b}
            label = next((s for s in CLIP_SPELLS if s in inside), "none")
            rows.append((label, b - a))
    if not rows:
        return None
    gaps = pd.DataFrame(rows, columns=["spell", "gap"])
    plain = gaps[gaps["spell"] == "none"]["gap"]
    if not len(plain):
        return None
    pace = plain.median()
    gaps = gaps[gaps["gap"] <= pace * 2.5]
    result = {"pace": pace, "spells": {}}
    for spell in CLIP_SPELLS:
        g = gaps[gaps["spell"] == spell]["gap"]
        if len(g):
            result["spells"][spell] = (g.median(), len(g), g.median() - pace)
    return result


def report(fights, macros):
    if not fights:
        print("No hunter fights saved yet. Fight a few times, then /reload (or log out) so the game writes the file.")
        return
    df, casts, tries, errors = summarize(fights)
    minutes = df["seconds"].sum() / 60
    print(f"Fights: {len(df)} ({df['seconds'].sum() / 60:.0f} min), won {int((df['result'] == 'won').sum())}, died {int((df['result'] == 'died').sum())}, "
          f"average {df['seconds'].mean():.0f} s, levels {int(df['level'].min())}-{int(df['level'].max())}")
    per_min = casts.groupby("spell").size().div(max(minutes, 0.01)).sort_values(ascending=False).round(1)
    print("Casts per minute: " + ", ".join(f"{s} {v}" for s, v in per_min.items()))
    print(f"Auto Shots per minute: {df['autoShots'].sum() / max(minutes, 0.01):.1f}")
    if len(errors):
        print("Errors: " + ", ".join(f"{m} x{int(n)}" for m, n in errors.head(8).items()))
    advice = []

    # The shared 6 s cooldown: how much of it you used (Summon Hawk + Arcane Shot casts vs the most possible).
    shared = casts[casts["spell"].isin(["Summon Hawk", "Arcane Shot"])].groupby("fight").size()
    possible = (df["seconds"] / SHARED_CD).clip(lower=1)
    use = (shared.reindex(df.index, fill_value=0) / possible).clip(upper=1)
    long_fights = df["seconds"] >= 12
    if long_fights.any():
        used = use[long_fights].mean()
        print(f"Shared Hawk/Arcane cooldown used: {used:.0%} of the time it was ready (fights of 12 s or more)")
        if used < 0.75:
            advice.append(f"You use the Hawk/Arcane Shot cooldown {used:.0%} of the time: press the macro every second or so; "
                          "each 6 s you wait is a hawk or an Arcane Shot lost.")
    over = int(df["hawkOver"].sum())
    if over:
        advice.append(f"{over} Summon Hawk casts came with two hawks already out (wasted cooldowns): keep the sequence "
                      "Hawk, Hawk, Arcane Shot with reset=18, and don't press Summon Hawk on its own key.")
    repeats = int(df["markRepeats"].sum())
    if repeats:
        advice.append(f"Hunter's Mark went on the same enemy again {repeats} times: use reset=combat for the mark line "
                      "(Shift-press to mark a new enemy), so looting or re-clicking doesn't recast it.")
    windows, used_mb = int(df["mongooseWindows"].sum()), int(df["mongooseUsed"].sum())
    if windows:
        rate = used_mb / windows
        print(f"Mongoose Bite: {used_mb} of {windows} chances used ({rate:.0%})")
        if rate < 0.5:
            advice.append(f"Mongoose Bite used on {rate:.0%} of your dodges: if the macro's last line never fires it "
                          "(it uses the global cooldown), put it on its own key.")
    interrupted = tries[(tries["kind"] == "I") & (tries["name"] == "Aimed Shot")]
    aimed = int((casts["spell"] == "Aimed Shot").sum())
    if len(interrupted):
        advice.append(f"Aimed Shot was interrupted {len(interrupted)} times ({aimed} landed): stand still for it, or take it "
                      "out of the sequence while you kite.")
    close = int(errors.get("Target too close", 0))
    if close and close / max(minutes, 0.01) > 3:
        advice.append(f"\"Target too close\" {close} times: you shoot in melee range; step back to 8+ yards (your pet holds "
                      "the enemy) or let Raptor Strike do the work up close.")
    mana = [m for m in errors.index if "mana" in m.lower() or "energ" in m.lower()]
    if mana:
        n = int(errors[mana].sum())
        advice.append(f"Out of mana {n} times: drink between pulls, or drop Arcane Shot from the sequence (hawks only) "
                      "on long fights.")
    deaths = df[df["result"] == "died"]
    if len(deaths):
        advice.append(f"You died in {len(deaths)} fights (most enemies seen: {int(deaths['enemies'].max())}): pull one at a "
                      "time, and use Mend Pet or your pet's taunt when two or more come.")
    dead_pet = int((~df["petAlive"] & df["pet"].notna()).sum())
    if dead_pet:
        advice.append(f"Your pet died in {dead_pet} fights: Mend Pet before it drops under half, or let it pull aggro first "
                      "(two or three shots in, then go all out).")
    clip = clipping(fights)
    if clip is None:
        print("Auto Shot times: none saved yet (addon 4.37.6 or newer saves them); play a few fights, then /reload.")
    else:
        print(f"Auto Shot every {clip['pace']:.2f} s on its own. Between two Auto Shots:")
        for spell, (median, n, extra) in clip["spells"].items():
            if extra >= CLIP_MIN:
                print(f"  {spell}: delays your next Auto Shot by {extra:.2f} s ({median:.2f} s, {n} times)")
            else:
                print(f"  {spell}: no delay ({median:.2f} s, {n} times)")
        arcane = clip["spells"].get("Arcane Shot")
        if arcane and arcane[2] >= CLIP_MIN:
            advice.append(f"Arcane Shot delays your Auto Shot by {arcane[2]:.2f} s each time ({arcane[1]} times): "
                          "weigh its damage against the lost Auto Shot time, or take it out of the button.")
    if "damage" in df and df["damage"].notna().any():
        print("Damage meter data found in some fights (see the saved file for details).")
    print()
    print("Recommendations:" if advice else "No problems found in these fights. Keep logging; more fights give firmer advice.")
    for line in advice:
        print(" - " + line)
    last = next((f for f in reversed(fights) if f["macros"]), fights[-1])
    ids = [int(x) for x in last["macros"].split(",") if x]
    if ids:
        print("\nYour hunter macro(s) in the latest fight that had one:")
        for i in ids:
            text = macros.get((last["account"], i))
            if text:
                print("    " + text.replace("\n", "\n    "))
                print()


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("game", help="the game folder (the one with WTF)")
    parser.add_argument("--last", type=int, default=0, help="only the last N fights")
    args = parser.parse_args()
    fights, macros = load(args.game)
    if args.last:
        fights = fights[-args.last:]
    report(fights, macros)


if __name__ == "__main__":
    main()
