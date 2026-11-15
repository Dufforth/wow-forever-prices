import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import tune_grind as tg  # noqa: E402


def kill(pl=20, ml=20, xp=None, rested=0, fight=16.0, cycle=None, mob="Wolf", cast=False, cls="DRUID", spec="feral", group=None, at=1):
    if xp is None:
        xp = round(tg.classic_xp(pl, ml))
    return {"at": at, "pl": pl, "ml": ml, "xp": xp, "rested": rested, "fight": fight, "cycle": cycle, "mob": mob,
            "cast": cast, "class": cls, "spec": spec, "group": group, "rank": "normal"}


class XpTest(unittest.TestCase):
    def test_classic_formula(self):
        self.assertEqual(tg.classic_xp(20, 20), 145)
        self.assertEqual(tg.classic_xp(20, 13), 0)
        self.assertAlmostEqual(tg.classic_xp(20, 18), 145 * (1 - 2 / 11))

    def test_fits_the_lower_level_cut(self):
        kills = []
        for d in (1, 2, 3, 4):
            for _ in range(5):
                kills.append(kill(ml=20 - d, xp=tg.classic_xp(20, 20 - d) * (1 - 0.05 * d)))
        step, top, n = tg.fit_below(kills)
        self.assertAlmostEqual(step, 0.05, places=2)
        self.assertEqual(n, 20)

    def test_rested_bonus_and_groups_are_left_out(self):
        kills = [kill(ml=18, xp=tg.classic_xp(20, 18) * 0.92 * 2, rested=round(tg.classic_xp(20, 18) * 0.92)) for _ in range(12)]
        kills += [kill(ml=18, xp=1, group=True) for _ in range(30)]
        step, _, n = tg.fit_below(kills)
        self.assertEqual(n, 12)
        self.assertAlmostEqual(step, 0.04, places=2)

    def test_too_few_kills_fit_nothing(self):
        self.assertIsNone(tg.fit_below([kill(ml=18)])[0])


class SpecTest(unittest.TestCase):
    def test_speed_and_rest_from_fights_and_cycles(self):
        kills = [kill(fight=8.0, cycle=16.0 + 8.0 + tg.WALK_SECONDS) for _ in range(25)]
        specs = tg.fit_specs(kills)
        speed, rest, n = specs["DRUID:feral"]
        self.assertAlmostEqual(speed, tg.KILL_SECONDS / 8.0)
        self.assertAlmostEqual(rest, 2.0)  # clamped
        kills = [kill(fight=16.0, cycle=16.0 * 1.25 + tg.WALK_SECONDS) for _ in range(25)]
        speed, rest, _ = tg.fit_specs(kills)["DRUID:feral"]
        self.assertAlmostEqual(speed, 1.0)
        self.assertAlmostEqual(rest, 0.25)

    def test_level_difference_is_taken_out(self):
        kills = [kill(ml=22, fight=16.0 * 1.2) for _ in range(25)]
        self.assertAlmostEqual(tg.fit_specs(kills)["DRUID:feral"][0], 1.0)

    def test_needs_enough_kills(self):
        self.assertEqual(tg.fit_specs([kill() for _ in range(5)]), {})


class CasterTest(unittest.TestCase):
    def test_casters_and_quiet_monsters(self):
        kills = [kill(mob="Kolkar Stormer", cast=True), kill(mob="Kolkar Stormer", cast=True), kill(mob="Kolkar Stormer")]
        kills += [kill(mob="Zhevra Runner") for _ in range(6)] + [kill(mob="Rare Visitor")]
        casters, quiet = tg.fit_casters(kills)
        self.assertEqual(casters, ["Kolkar Stormer"])
        self.assertEqual(quiet, ["Zhevra Runner"])


class ArchiveTest(unittest.TestCase):
    def test_merge_keeps_each_kill_once(self):
        old = [kill(at=1, mob="A"), kill(at=2, mob="B")]
        new = [kill(at=2, mob="B"), kill(at=3, mob="C")]
        merged, added = tg.merge(old, new, "Duff-Realm")
        self.assertEqual(added, 1)
        self.assertEqual([k["mob"] for k in merged], ["A", "B", "C"])

    def test_lua_table_of_the_tune(self):
        text = tg.tune_lua({"below": [0.05, 0.2], "specs": {"DRUID:feral": [1.2, 0.3]}, "casters": ["X"], "noCast": [], "kills": 3, "at": "2026-11-15"})
        self.assertIn("DufforthTweaksHelperGrindTune = {", text)
        self.assertIn('["DRUID:feral"]={1.2,0.3}', text)
        self.assertIn('casters={["X"]=true}', text)


class ExplainTest(unittest.TestCase):
    def test_says_why_there_are_no_kills(self):
        self.assertIn("never ran", tg.explain(False, 0, None))
        self.assertIn("hasn't run", tg.explain(True, 0, None))
        self.assertIn("No fights", tg.explain(True, 0, {"combats": 0}))
        self.assertIn("weren't understood", tg.explain(True, 0, {"combats": 3, "chat": 3, "parsed": 0, "lastChat": "x"}))
        self.assertIn("gray", tg.explain(True, 0, {"combats": 3, "chat": 0}))
        self.assertIn("12 kills saved", tg.explain(True, 12, {"combats": 12, "chat": 12, "parsed": 12}))


class AddonTest(unittest.TestCase):
    def test_the_addon_applies_the_written_tune(self):
        try:
            import lupa.lua51 as L
        except ImportError:
            self.skipTest("lupa")
        addon = Path(__file__).resolve().parents[1] / "addon" / "DufforthTweaksHelper"
        lua = L.LuaRuntime(unpack_returned_tuples=True)
        lua.execute("CreateFrame = function() return setmetatable({}, { __index = function() return function() end end }) end")
        lua.execute((addon / "Grind.lua").read_text(encoding="utf-8"))
        tune = tg.build_tune([kill(fight=8.0, cycle=20.0) for _ in range(25)] + [kill(ml=18, xp=tg.classic_xp(20, 18) * 0.9) for _ in range(12)])
        lua.execute(tg.tune_lua(tune))
        lua.execute("DufforthTweaksHelperGrind.ApplyTune(DufforthTweaksHelperGrindTune)")
        self.assertAlmostEqual(lua.eval("DufforthTweaksHelperGrind.SpecInfo('DRUID', 'feral').speed"), 2.0)
        self.assertAlmostEqual(lua.eval("DufforthTweaksHelperGrind.BELOW_STEP"), 0.05, places=3)


if __name__ == "__main__":
    unittest.main()
