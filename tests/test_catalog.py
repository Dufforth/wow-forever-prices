import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "catalog"))
import build_catalog  # noqa: E402


def tables():
    return {
        "Item": [
            {"ID": "1", "ClassID": "7", "SubclassID": "9", "IconFileDataID": "50"},
            {"ID": "2", "ClassID": "0", "SubclassID": "1", "IconFileDataID": "0"},
            {"ID": "3", "ClassID": "4", "SubclassID": "1", "IconFileDataID": "51"},
            {"ID": "4", "ClassID": "4", "SubclassID": "1", "IconFileDataID": "51"},
        ],
        "ItemSparse": [
            {"ID": "1", "Display_lang": "Herb", "OverallQualityID": "1", "ItemLevel": "5"},
            {"ID": "2", "Display_lang": "Potion", "OverallQualityID": "1", "ItemLevel": "5", "VendorStackCount": "1"},
            {"ID": "3", "Display_lang": "Robe", "OverallQualityID": "2", "ItemLevel": "20", "InventoryType": "5", "Bonding": "2"},
            {"ID": "4", "Display_lang": "Soulbound Robe", "OverallQualityID": "2", "ItemLevel": "20", "Bonding": "1"},
        ],
        "ManifestInterfaceData": [
            {"ID": "50", "FileName": "INV_Misc_Herb_01.blp"},
            {"ID": "51", "FileName": "INV_Chest_Cloth_01.BLP"},
        ],
        "ItemModifiedAppearance": [{"ItemID": "4", "ItemAppearanceID": "7", "OrderIndex": "0"}],
        "ItemAppearance": [{"ID": "7", "DefaultIconFileDataID": "50"}],
        "SpellReagents": [{"SpellID": "9", "Reagent_0": "1", "ReagentCount_0": "2"}],
        "SpellEffect": [{"SpellID": "9", "Effect": "24", "EffectItemType": "2", "EffectBasePointsF": "3"}],
        "SpellName": [{"ID": "9", "Name_lang": "Brew"}],
        "SkillLineAbility": [{"SkillLine": "171", "Spell": "9", "MinSkillLineRank": "1"}],
    }


class BuildTests(unittest.TestCase):
    def build(self, fallback=None):
        return build_catalog.build(tables(), "1.0", {}, fallback or {})

    def test_recipe_and_yield(self):
        catalog = self.build()[0]
        recipe = catalog["recipes"][0]
        self.assertEqual((recipe["p"], recipe["i"], recipe["c"], recipe["r"]), ("Alchemy", 2, 3, [[1, 2]]))

    def test_icon_comes_from_client_file_name_in_lower_case(self):
        catalog, gear, _ = self.build()
        self.assertEqual(catalog["items"][1]["ic"], "inv_misc_herb_01")
        self.assertEqual(gear[3]["ic"], "inv_chest_cloth_01")

    def test_icon_name_cleans_up_client_typos(self):
        self.assertEqual(build_catalog.icon_name(1, {1: "INV_Chest _Cloth.blp"}), "inv_chest_cloth")
        self.assertIsNone(build_catalog.icon_name(2, {1: "x.blp"}))

    def test_icon_falls_back_when_the_client_has_none(self):
        self.assertNotIn("ic", self.build()[0]["items"][2])
        catalog = self.build({2: "inv_potion_01"})[0]
        self.assertEqual(catalog["items"][2]["ic"], "inv_potion_01")

    def test_icon_comes_from_the_appearance_when_the_item_has_none(self):
        data = tables()
        data["Item"][1]["IconFileDataID"] = "0"
        data["ItemModifiedAppearance"].append({"ItemID": "2", "ItemAppearanceID": "7", "OrderIndex": "0"})
        catalog = build_catalog.build(data, "1.0", {}, {2: "not_used"})[0]
        self.assertEqual(catalog["items"][2]["ic"], "inv_misc_herb_01")

    def test_gear_keeps_type_for_categories_and_leaves_out_soulbound(self):
        gear = self.build()[1]
        self.assertEqual((gear[3]["cl"], gear[3]["sc"]), (4, 1))
        self.assertNotIn(4, gear)

    def test_every_list_keeps_the_vendor_price(self):
        data = tables()
        data["ItemSparse"][2]["SellPrice"] = "250"
        catalog, gear, tradable = build_catalog.build(data, "1.0", {}, {})
        self.assertEqual(gear[3]["sell"], 250)
        self.assertEqual(tradable[3][5], 250)

    def test_tradable_list_leaves_out_soulbound_items(self):
        tradable = self.build()[2]
        self.assertEqual(tradable[3][:6], ["Robe", 2, "inv_chest_cloth_01", 4, 1, 0])
        self.assertIsInstance(tradable[3][6], int, "item level")
        self.assertNotIn(4, tradable)
        self.assertEqual(tradable[3][8], 5, "inventory slot, for the auction house view")

    def test_items_flagged_not_disenchantable_leave_the_gear_list(self):
        data = tables()
        data["ItemSparse"][2]["Flags_0"] = str(0x8000)
        catalog, gear, _ = build_catalog.build(data, "1.0", {}, {})
        self.assertNotIn(3, gear)
        self.assertEqual(catalog["noDisenchant"], [3])
        self.assertIn(3, self.build()[1], "unflagged gear stays")


if __name__ == "__main__":
    unittest.main()


class RecipeOriginTests(unittest.TestCase):
    def with_recipe_item(self):
        data = tables()
        data["Item"].append({"ID": "5", "ClassID": "9", "SubclassID": "6"})
        data["ItemSparse"].append({"ID": "5", "Display_lang": "Recipe: Brew", "OverallQualityID": "2", "RequiredSkillRank": "125"})
        data["ItemEffect"] = [{"ID": "70", "SpellID": "9"}]
        data["ItemXItemEffect"] = [{"ItemID": "5", "ItemEffectID": "70"}]
        data["SkillLineAbility"][0]["TrivialSkillLineRankLow"] = "140"
        return data

    def test_recipe_item_gives_skill_and_is_kept_for_its_price(self):
        catalog = build_catalog.build(self.with_recipe_item(), "1.0", {}, {})[0]
        recipe = catalog["recipes"][0]
        self.assertEqual((recipe["sk"], recipe["ri"], recipe["y"], recipe["o"]), (125, 5, 140, ["item"]))
        self.assertIn(5, catalog["items"], "the recipe item, so the page can show its AH price")

    def test_wowhead_learned_at_and_sources_win(self):
        sources = {"spells": {"9": [110, [], 0]}, "items": {"5": [125, [2, 5, 21], 1]}}
        recipe = build_catalog.build(self.with_recipe_item(), "1.0", {}, {}, sources)[0]["recipes"][0]
        self.assertEqual(recipe["sk"], 110)
        self.assertEqual(recipe["o"], ["world", "vendor", "pickpocket"])

    def test_trainer_and_unknown(self):
        trainer = build_catalog.build(tables(), "1.0", {}, {}, {"spells": {"9": [50, [6], 0]}, "items": {}})[0]["recipes"][0]
        self.assertEqual((trainer["sk"], trainer["o"]), (50, ["trainer"]))
        unknown = build_catalog.build(tables(), "1.0", {}, {})[0]["recipes"][0]
        self.assertEqual((unknown["sk"], unknown["o"]), (0, ["unknown"]))
