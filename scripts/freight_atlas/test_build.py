#!/usr/bin/env python3
"""Unit tests for the freight atlas pipeline: python3 scripts/freight_atlas/test_build.py"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import build  # noqa: E402

# A straight east-west line 40 km long at 40°N.
LINE = [(40.0, -100.0), (40.0, -99.53)]


def crossing(lon, tpd, family="bnsf", lat=40.0, mph=60, tracks=1):
    return {"lat": lat, "lon": lon, "tpd": tpd, "mph": mph, "tracks": tracks, "family": family}


class PolylineTests(unittest.TestCase):
    def test_round_trip(self):
        path = [(38.5, -120.2), (40.7, -120.95), (43.252, -126.453)]
        self.assertEqual(build.encode_polyline(path), "_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        decoded = build.decode_polyline(build.encode_polyline(path))
        for (a, b), (c, d) in zip(path, decoded):
            self.assertAlmostEqual(a, c, places=5)
            self.assertAlmostEqual(b, d, places=5)


class ChunkTests(unittest.TestCase):
    def test_chunks_cover_the_line_in_about_eight_km_pieces(self):
        chunks = build.chunk_path(LINE)
        total = sum(build.km_between(a, b) for chunk in chunks for a, b in zip(chunk, chunk[1:]))
        self.assertAlmostEqual(total, build.km_between(*LINE), delta=0.01)
        self.assertEqual(len(chunks), 5)
        for chunk in chunks[:-1]:
            self.assertAlmostEqual(build.km_between(chunk[0], chunk[-1]), build.CHUNK_KM, delta=0.01)
        for left, right in zip(chunks, chunks[1:]):
            self.assertEqual(left[-1], right[0])

    def test_short_line_is_one_chunk(self):
        self.assertEqual(len(build.chunk_path([(40.0, -100.0), (40.0, -99.99)])), 1)


class DensityTests(unittest.TestCase):
    def test_own_railroad_crossings_win_over_a_parallel_line(self):
        index = build.CrossingIndex([
            crossing(-99.98, 40, family="bnsf", lat=40.004),          # ~0.45 km off, same railroad
            crossing(-99.97, 90, family="unionPacific", lat=40.003),   # ~0.3 km off, another railroad
        ])
        measure = build.measure_chunk(build.chunk_path(LINE)[0], "bnsf", index)
        self.assertEqual(measure["tpd"], 40)

    def test_foreign_crossings_need_to_be_very_close(self):
        index = build.CrossingIndex([crossing(-99.98, 90, family="unionPacific", lat=40.006)])  # ~0.7 km
        self.assertIsNone(build.measure_chunk(build.chunk_path(LINE)[0], "bnsf", index))

    def test_gaps_borrow_from_neighbours_but_not_from_far_away(self):
        measures = [{"tpd": 10, "mph": 50, "tracks": 1, "n": 3}] + [None] * 5 + [{"tpd": 30, "mph": 60, "tracks": 2, "n": 4}]
        filled = build.fill_gaps(measures)
        self.assertEqual(filled[1]["tpd"], 10)
        self.assertEqual(filled[3]["tpd"], 20)   # both neighbours within reach: averaged
        self.assertEqual(filled[5]["tpd"], 30)
        self.assertEqual(filled[1]["n"], 0)

    def test_runs_in_one_tier_merge_into_a_corridor(self):
        # Traffic changes exactly where the second 8 km chunk ends (16 km ≈ 0.188° of longitude at 40°N).
        lons = [-100.0 + 0.005 + i * 0.02 for i in range(24)]
        index = build.CrossingIndex([crossing(lon, 20 if lon < -99.8125 else 60) for lon in lons])
        corridors = build.corridors_for_piece(LINE, "bnsf", index)
        self.assertEqual([c["tpd"] for c in corridors], [20, 60])
        self.assertTrue(all(c["rr"] == "bnsf" and c["mph"] == 60 for c in corridors))

    def test_unmeasured_track_is_kept_without_a_count(self):
        corridors = build.corridors_for_piece(LINE, "csx", build.CrossingIndex([]))
        self.assertEqual(len(corridors), 1)
        self.assertIsNone(corridors[0]["tpd"])

    def test_tiers(self):
        self.assertEqual([build.tier(v) for v in (None, 2, 5, 29.9, 30, 120)], [-1, 0, 1, 2, 3, 5])


class CrossingLoadTests(unittest.TestCase):
    def test_passenger_and_transit_trains_are_subtracted(self):
        import json, tempfile
        with tempfile.TemporaryDirectory() as folder:
            rows = [
                {"crossingid": "1A", "railroadcode": "BNSF", "latitude": "40", "longitude": "-100",
                 "totaldaylightthrutrains": "20", "totalnighttimethrutrains": "10",
                 "numberpassengertrainperday": "4", "totaltransittrains": "0"},
                {"crossingid": "2B", "railroadcode": "MNCW", "latitude": "41", "longitude": "-73.9",
                 "totaldaylightthrutrains": "80", "totalnighttimethrutrains": "20"},
                {"crossingid": "3C", "railroadcode": "UP", "latitude": "41", "longitude": "-101",
                 "totaldaylightthrutrains": "400", "totalnighttimethrutrains": "0"},
            ]
            Path(folder, "p000.json").write_text(json.dumps(rows))
            crossings = build.load_crossings(Path(folder), {"2B": 100})
        self.assertEqual([c["tpd"] for c in crossings], [26, 0])  # 3C is an implausible count and dropped
        self.assertEqual(crossings[0]["family"], "bnsf")
        self.assertIsNone(crossings[1]["family"])


class TerminalTests(unittest.TestCase):
    def test_terminal_operators_are_parsed(self):
        [terminal] = build.build_terminals([{
            "TERMINAL": "Seaport", "CITY": "Olympia", "STATE": "WA", "PORT": "Port of Olympia",
            "RAIL_CO": "BNSF, UP via OYLO", "EQUIPMENT": "TOFC/COFC", "LAT": 47.05, "LON": -122.9,
        }])
        self.assertEqual(terminal["railroads"], ["bnsf", "unionPacific"])
        self.assertTrue(terminal["trailers"] and terminal["containers"])
        self.assertEqual(terminal["id"], "wa-olympia-seaport")

    def test_blank_port_becomes_none(self):
        [terminal] = build.build_terminals([{
            "TERMINAL": "Huntsville, AL", "CITY": "Huntsville", "STATE": "AL", "PORT": " ",
            "RAIL_CO": "NS", "EQUIPMENT": "COFC", "LAT": 34.6, "LON": -86.7,
        }])
        self.assertIsNone(terminal["port"])
        self.assertFalse(terminal["trailers"])


if __name__ == "__main__":
    unittest.main()
