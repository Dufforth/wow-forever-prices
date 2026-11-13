"""catalog/build_consumables.py: what a consumable does, read from small spell tables."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "catalog"))
import build_consumables  # noqa: E402


def effect(spell, eff, aura=0, bp=0, misc=0, trigger=0):
    return {"SpellID": str(spell), "Effect": str(eff), "EffectAura": str(aura), "EffectBasePointsF": str(bp),
            "EffectMiscValue_0": str(misc), "EffectTriggerSpell": str(trigger)}


def tables():
    return {
        "ItemEffect": [{"ID": "1", "TriggerType": "0", "SpellID": "100"}, {"ID": "2", "TriggerType": "0", "SpellID": "200"},
                       {"ID": "3", "TriggerType": "0", "SpellID": "300"}, {"ID": "4", "TriggerType": "0", "SpellID": "400"},
                       {"ID": "5", "TriggerType": "0", "SpellID": "500"}, {"ID": "6", "TriggerType": "0", "SpellID": "600"},
                       {"ID": "7", "TriggerType": "0", "SpellID": "700"}, {"ID": "8", "TriggerType": "0", "SpellID": "800"}],
        "ItemXItemEffect": [{"ItemEffectID": str(i), "ItemID": str(10 + i)} for i in range(1, 9)],
        "SpellEffect": [
            # Nutritious food: eating heals, and a 10 s trigger gives a generic Well Fed (+bp from the food).
            effect(100, 6, aura=84, bp=50), effect(100, 6, aura=227, bp=20, trigger=900),
            effect(900, 6, aura=29, bp=1, misc=0),
            effect(200, 6, aura=29, bp=25, misc=1), effect(200, 6, aura=290, bp=2),  # elixir: Agility + crit
            effect(300, 10, bp=1400),  # healing potion
            effect(400, 30, bp=600, misc=1), effect(400, 6, aura=29, bp=60, misc=0),  # rage potion
            effect(500, 6, aura=85, bp=42),  # plain drink: mana while drinking
            effect(600, 54, bp=1800, misc=1643),  # sharpening stone: enchant 1643
            effect(700, 54, bp=1800, misc=2628), effect(2000, 6, aura=13, bp=36, misc=126),  # oil: enchant -> equip spell 2000
            effect(800, 54, bp=1800, misc=7098),  # works in one dungeon only
        ],
        "SpellItemEnchantment": [
            {"ID": "1643", "Duration": "1800", "Effect_0": "2", "EffectPointsMin_0": "8", "EffectArg_0": "0",
             "Effect_1": "0", "EffectPointsMin_1": "0", "EffectArg_1": "0", "Effect_2": "0", "EffectPointsMin_2": "0", "EffectArg_2": "0"},
            {"ID": "2628", "Duration": "1800", "Effect_0": "3", "EffectPointsMin_0": "0", "EffectArg_0": "2000",
             "Effect_1": "0", "EffectPointsMin_1": "0", "EffectArg_1": "0", "Effect_2": "0", "EffectPointsMin_2": "0", "EffectArg_2": "0"},
        ],
        "SpellEquippedItems": [{"SpellID": "600", "EquippedItemClass": "2", "EquippedItemSubclass": "33219"}],
        "SpellMisc": [{"SpellID": "900", "DurationIndex": "9"}, {"SpellID": "200", "DurationIndex": "8"}, {"SpellID": "400", "DurationIndex": "7"}],
        "SpellDuration": [{"ID": "9", "Duration": "900000"}, {"ID": "8", "Duration": "3600000"}, {"ID": "7", "Duration": "20000"}],
        "Spell": [{"ID": "100", "Description_lang": "Eat. $@spelldesc1243969"},
                  {"ID": "800", "Description_lang": "Hit. This has no effect outside of Blackfathom Deeps."}],
    }


def catalog():
    item = lambda sc: {"n": "x", "cl": 0, "sc": sc, "rl": 1}
    oil = {"n": "oil", "cl": 7, "sc": 12, "rl": 1}
    return {"build": "1.0", "items": {"11": item(5), "12": item(2), "13": item(1), "14": item(1), "15": item(5),
                                      "16": item(8), "17": oil, "18": item(8)}}


class BuildTest(unittest.TestCase):
    def setUp(self):
        self.items = build_consumables.build(tables(), catalog())["items"]

    def test_food_takes_the_amount_from_its_own_trigger(self):
        self.assertEqual(self.items["11"], ["food", 900, {"str": 20, "xp": 5}, 0])

    def test_elixir(self):
        self.assertEqual(self.items["12"], ["elixir", 3600, {"agi": 25, "crit": 2}, 0])

    def test_stone_reads_its_enchant_and_weapon_types(self):
        self.assertEqual(self.items["16"], ["weapon", 1800, {"wdmg": 8}, 33219])

    def test_oil_reads_its_enchant_spell_even_as_a_trade_good(self):
        self.assertEqual(self.items["17"], ["weapon", 1800, {"sp": 36}, 0])

    def test_one_dungeon_stone_is_left_out(self):
        self.assertNotIn("18", self.items)

    def test_potions(self):
        self.assertEqual(self.items["13"][2], {"hp": 1400})
        self.assertEqual(self.items["14"][2], {"rage": 60, "str": 60})

    def test_plain_drink_is_not_a_buff(self):
        self.assertNotIn("15", self.items)


if __name__ == "__main__":
    unittest.main()
