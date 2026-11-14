"""Travel between zones for the guide (catalog/route_travel.py): flight masters, continents, ships.

User (2026-11-13): the guide asked for a turn-in on the other continent without saying how to get there.
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "catalog"))
from route_travel import TRANSPORTS, add_flight_steps, flight_masters, zone_continents  # noqa: E402


def t(columns, *rows):
    return (columns, [list(r) for r in rows])


def where(point):
    """A made-up world: map 1 x < 1000 is Durotar, else The Barrens; map 0 is Tirisfal Glades."""
    if point[0] == 0:
        return ("Tirisfal Glades", 50.0, 50.0)
    return ("Durotar", point[1] / 20, point[2] / 20) if point[1] < 1000 else ("The Barrens", 40.0, 30.0)


class FlightMastersTest(unittest.TestCase):
    def setUp(self):
        self.tables = {
            "creature_template": t(["Entry", "Name", "NpcFlags", "Faction"],
                                   [1, "Horde Flyer", 8 | 2, 10], [2, "Alliance Flyer", 8, 20], [3, "Horde Vendor", 4, 10]),
            "creature": t(["id", "map", "position_x", "position_y"],
                          [1, 1, 200, 400], [2, 1, 300, 300], [3, 1, 100, 100]),
        }
        self.side = {10: "H", 20: "A"}.get

    def test_only_horde_flight_masters(self):
        out = flight_masters(self.tables, self.side, where)
        self.assertEqual(out, [["Horde Flyer", "Durotar", 10.0, 20.0, 1]])

    def test_continents_of_zones(self):
        self.assertEqual(zone_continents([(1, 10, 10), (1, 2000, 10), (0, 5, 5), None], where),
                         {"Durotar": 1, "The Barrens": 1, "Tirisfal Glades": 0})


class FlightStepsTest(unittest.TestCase):
    """User (2026-11-13): a route that picks up every flight path on the way."""
    FLIGHTS = [["Devrak", "The Barrens", 51.5, 30.3, 1], ["Omusa", "The Barrens", 44.4, 59.2, 1], ["Nobody", "Nowhere", 1, 1, 1]]

    def steps(self):
        return [["accept", 1, "Durotar", 40, 60, 5, "a", 0], ["travel", 0, "The Barrens", 52, 30, 10, "Go to The Barrens", 0],
                ["accept", 2, "The Barrens", 52, 31, 10, "b", 0], ["do", 2, "The Barrens", 60, 40, 11, "c", 1],
                ["accept", 3, "The Barrens", 45, 58, 14, "d", 0]]

    def test_a_stop_at_each_flight_master_when_the_route_first_comes_near(self):
        out = add_flight_steps(self.steps(), self.FLIGHTS)
        kinds = [(s[0], s[2]) for s in out]
        self.assertEqual(len(out), 7)
        self.assertEqual(out[2][:6], ["flight", 0, "The Barrens", 51.5, 30.3, 10], "at the Crossroads, before its first quest there")
        self.assertIn("Devrak", out[2][6])
        self.assertEqual(out[5][0], "flight", "Camp Taurajo's when the route gets there")
        self.assertEqual(out[6][6], "d")
        self.assertNotIn(("flight", "Nowhere"), kinds, "zones the route never visits get none")

    def test_the_route_is_not_changed_in_place(self):
        steps = self.steps()
        add_flight_steps(steps, self.FLIGHTS)
        self.assertEqual(len(steps), 5)


class TransportsTest(unittest.TestCase):
    def test_ships_join_the_continents(self):
        self.assertTrue(TRANSPORTS)
        for kind, a, b in TRANSPORTS:
            self.assertIn(kind, ("zeppelin", "boat"))
            self.assertEqual(len(a), 5)  # name, zone, x, y, continent
            self.assertNotEqual(a[4], b[4], "a ship goes to the other continent")

    def test_orgrimmar_and_undercity_are_joined(self):
        pairs = {(a[1], b[1]) for _, a, b in TRANSPORTS}
        self.assertIn(("Durotar", "Tirisfal Glades"), pairs)


if __name__ == "__main__":
    unittest.main()
