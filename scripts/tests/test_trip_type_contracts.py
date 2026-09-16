#!/usr/bin/env python3
"""Tests for scripts/trip_type_contracts.py (Product Experience V2, Task 3).

Run with:

    python3 -m unittest scripts.tests.test_trip_type_contracts -v

`document()` builds a small but complete trip-types.json-shaped dict; each
test breaks exactly one rule so a failure names the rule it proves.
"""

from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path

from scripts.trip_type_contracts import contract_errors, swift_packing_needs

ROOT = Path(__file__).resolve().parents[2]

ORDER = ["vacation", "beach", "other"]
NEEDS = ["leisureGeneralTravel", "beachSwim"]
ACTIVITIES = {"sightseeing", "swimming", "nightlife"}
CATALOG = {"electronics.headphones", "clothing.swimsuit"}


def document():
    return {
        "needs": [
            {"id": "leisureGeneralTravel", "meaning": "down-time", "candidates": ["electronics.headphones"]},
            {"id": "beachSwim", "meaning": "swim", "candidates": ["clothing.swimsuit"]},
        ],
        "tripTypes": [
            {"id": "vacation", "needs": ["leisureGeneralTravel"], "suggestedActivities": ["sightseeing"],
             "excludedNeeds": ["beachSwim"], "excludedActivities": ["nightlife"], "nonImplications": "Beach/swim"},
            {"id": "beach", "needs": ["beachSwim"], "suggestedActivities": ["swimming"],
             "excludedNeeds": [], "excludedActivities": [], "nonImplications": "Vacation baseline"},
            {"id": "other", "needs": [], "suggestedActivities": [],
             "excludedNeeds": [], "excludedActivities": [], "nonImplications": "Anything"},
        ],
    }


def errors(doc):
    return contract_errors(doc, trip_type_order=ORDER, need_vocabulary=NEEDS, activity_ids=ACTIVITIES, catalog_ids=CATALOG)


def type_row(doc, trip_type):
    return next(row for row in doc["tripTypes"] if row["id"] == trip_type)


class ValidDocument(unittest.TestCase):
    def test_a_complete_document_has_no_errors(self):
        self.assertEqual(errors(document()), [])


class TripTypeRows(unittest.TestCase):
    def test_duplicate_trip_type_definitions_are_rejected(self):
        doc = document()
        doc["tripTypes"].append(copy.deepcopy(type_row(doc, "beach")))
        self.assertTrue(any("duplicate trip type beach" in e for e in errors(doc)), errors(doc))

    def test_missing_or_unknown_or_misordered_trip_types_are_rejected(self):
        doc = document()
        doc["tripTypes"] = [row for row in doc["tripTypes"] if row["id"] != "beach"]
        self.assertTrue(any("trip types must be exactly" in e for e in errors(doc)), errors(doc))
        doc = document()
        type_row(doc, "beach")["id"] = "spaceCruise"
        self.assertTrue(any("trip types must be exactly" in e for e in errors(doc)), errors(doc))
        doc = document()
        doc["tripTypes"].reverse()
        self.assertTrue(any("trip types must be exactly" in e for e in errors(doc)), errors(doc))

    def test_legacy_item_list_keys_are_rejected(self):
        doc = document()
        type_row(doc, "vacation")["add"] = ["electronics.headphones"]
        self.assertTrue(any("retired key add" in e for e in errors(doc)), errors(doc))
        doc = document()
        type_row(doc, "vacation")["prefer_activities"] = ["sightseeing"]
        self.assertTrue(any("retired key prefer_activities" in e for e in errors(doc)), errors(doc))


class NeedIDs(unittest.TestCase):
    def test_unknown_need_ids_are_rejected(self):
        doc = document()
        type_row(doc, "vacation")["needs"] = ["leisureGeneralTravel", "spaFacials"]
        self.assertTrue(any("unknown need spaFacials" in e for e in errors(doc)), errors(doc))

    def test_duplicate_need_ids_are_rejected(self):
        doc = document()
        type_row(doc, "vacation")["needs"] = ["leisureGeneralTravel", "leisureGeneralTravel"]
        self.assertTrue(any("repeats need leisureGeneralTravel" in e for e in errors(doc)), errors(doc))

    def test_a_canonical_item_id_where_a_need_id_belongs_is_named_as_such(self):
        doc = document()
        type_row(doc, "vacation")["needs"] = ["electronics.headphones"]
        self.assertTrue(any("canonical item ID electronics.headphones" in e for e in errors(doc)), errors(doc))

    def test_other_contributes_no_deterministic_needs_or_suggestions(self):
        doc = document()
        type_row(doc, "other")["needs"] = ["leisureGeneralTravel"]
        self.assertTrue(any("other must contribute no needs" in e for e in errors(doc)), errors(doc))
        doc = document()
        type_row(doc, "other")["suggestedActivities"] = ["sightseeing"]
        self.assertTrue(any("other must suggest no activities" in e for e in errors(doc)), errors(doc))


class SuggestedActivities(unittest.TestCase):
    def test_unknown_suggested_activities_are_rejected(self):
        doc = document()
        type_row(doc, "beach")["suggestedActivities"] = ["swimming", "cosplay"]
        self.assertTrue(any("unknown suggested activity cosplay" in e for e in errors(doc)), errors(doc))

    def test_duplicate_suggested_activities_are_rejected(self):
        doc = document()
        type_row(doc, "beach")["suggestedActivities"] = ["swimming", "swimming"]
        self.assertTrue(any("repeats suggested activity swimming" in e for e in errors(doc)), errors(doc))


class Exclusions(unittest.TestCase):
    def test_an_excluded_need_the_type_contributes_is_a_contradiction(self):
        doc = document()
        type_row(doc, "vacation")["excludedNeeds"] = ["leisureGeneralTravel"]
        self.assertTrue(any("both contributes and excludes need leisureGeneralTravel" in e for e in errors(doc)), errors(doc))

    def test_an_excluded_activity_the_type_suggests_is_a_contradiction(self):
        doc = document()
        type_row(doc, "vacation")["excludedActivities"] = ["sightseeing"]
        self.assertTrue(any("both suggests and excludes activity sightseeing" in e for e in errors(doc)), errors(doc))

    def test_exclusions_use_the_closed_vocabularies(self):
        doc = document()
        type_row(doc, "vacation")["excludedNeeds"] = ["spaFacials"]
        type_row(doc, "vacation")["excludedActivities"] = ["cosplay"]
        found = errors(doc)
        self.assertTrue(any("unknown excluded need spaFacials" in e for e in found), found)
        self.assertTrue(any("unknown excluded activity cosplay" in e for e in found), found)


class NeedCatalog(unittest.TestCase):
    def test_need_catalog_matches_the_swift_vocabulary_exactly_and_in_order(self):
        doc = document()
        doc["needs"].reverse()
        self.assertTrue(any("needs must be exactly" in e for e in errors(doc)), errors(doc))

    def test_need_candidates_must_be_real_unique_catalog_items(self):
        doc = document()
        doc["needs"][0]["candidates"] = ["electronics.teleporter"]
        self.assertTrue(any("unknown candidate electronics.teleporter" in e for e in errors(doc)), errors(doc))
        doc = document()
        doc["needs"][0]["candidates"] = ["electronics.headphones", "electronics.headphones"]
        self.assertTrue(any("repeats candidate electronics.headphones" in e for e in errors(doc)), errors(doc))

    def test_every_need_is_contributed_by_some_trip_type(self):
        doc = document()
        type_row(doc, "beach")["needs"] = []
        self.assertTrue(any("need beachSwim is contributed by no trip type" in e for e in errors(doc)), errors(doc))


class RepositoryContract(unittest.TestCase):
    """The checked-in rules and Swift vocabulary satisfy every rule above."""

    def test_the_real_trip_type_contract_is_valid(self):
        from scripts.trip_type_contracts import repository_contract_errors

        self.assertEqual(repository_contract_errors(ROOT), [])

    def test_swift_packing_need_vocabulary_is_readable(self):
        needs = swift_packing_needs(ROOT / "ios" / "PackWise" / "Domain" / "Packing" / "TripTypeContracts.swift")
        self.assertEqual(len(needs), 14)
        doc = json.loads((ROOT / "shared" / "rules" / "trip-types.json").read_text())
        self.assertEqual([row["id"] for row in doc["needs"]], needs)


if __name__ == "__main__":
    unittest.main()
