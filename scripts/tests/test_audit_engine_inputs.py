#!/usr/bin/env python3
"""Tests for scripts/audit_engine_inputs.py.

Run with:

    python3 -m unittest scripts.tests.test_audit_engine_inputs -v

`contracts(...)` and `record(...)` build minimal surfaced-input-contracts.json
shaped dicts, matching what `docs/engine-audits/surfaced-input-contracts.json`
actually contains, so these tests exercise the exact parsing path the
production file goes through.
"""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from scripts.audit_engine_inputs import (
    ContractLoadError,
    SourceExpectation,
    build_report,
    check_completeness,
    load_contracts,
)


def record(kind="activity", id_="running", **overrides):
    base = {
        "kind": kind,
        "id": id_,
        "exposed": True,
        "engineContract": "deterministic",
        "fixtureIDs": ["08-running-sightseeing-footwear"],
        "iconContract": "figure.run",
        "ownerScope": "trip",
    }
    base.update(overrides)
    return base


def contracts(*records):
    return {"version": 1, "records": list(records)}


def write_contracts(tmp_path: Path, data: dict) -> Path:
    path = tmp_path / "contracts.json"
    import json

    path.write_text(json.dumps(data))
    return path


class DuplicateIDTests(unittest.TestCase):
    def test_duplicate_kind_and_id_is_a_schema_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write_contracts(
                Path(tmp),
                contracts(
                    record(kind="activity", id_="hiking"),
                    record(kind="activity", id_="hiking", fixtureIDs=[]),
                ),
            )
            records, errors = load_contracts(path)
            self.assertEqual(len(records), 2)
            self.assertTrue(
                any("duplicate" in e and "activity/hiking" in e for e in errors),
                f"expected a duplicate-id error, got: {errors}",
            )

    def test_same_id_different_kind_is_not_a_duplicate(self):
        # "roadTrip" the trip type and a hypothetical "roadTrip" activity id
        # address different vocabularies; only the (kind, id) pair must be unique.
        with tempfile.TemporaryDirectory() as tmp:
            path = write_contracts(
                Path(tmp),
                contracts(
                    record(kind="tripType", id_="roadTrip", engineContract="deterministic", fixtureIDs=["18-x"]),
                    record(kind="activity", id_="roadTrip", engineContract="missing", fixtureIDs=[]),
                ),
            )
            _records, errors = load_contracts(path)
            self.assertEqual(errors, [])


class MissingIconTests(unittest.TestCase):
    def test_empty_icon_contract_is_a_schema_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write_contracts(Path(tmp), contracts(record(iconContract="")))
            _records, errors = load_contracts(path)
            self.assertTrue(
                any("iconContract" in e for e in errors),
                f"expected an iconContract error, got: {errors}",
            )

    def test_missing_icon_contract_key_is_a_schema_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            raw = record()
            del raw["iconContract"]
            path = write_contracts(Path(tmp), contracts(raw))
            _records, errors = load_contracts(path)
            self.assertTrue(any("iconContract" in e for e in errors))


class IllegalContractTests(unittest.TestCase):
    def test_unrecognized_engine_contract_value_is_a_schema_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write_contracts(Path(tmp), contracts(record(engineContract="broken")))
            records, errors = load_contracts(path)
            self.assertEqual(len(records), 1)
            self.assertTrue(
                any("illegal engineContract" in e and "'broken'" in e for e in errors),
                f"expected an illegal-contract error, got: {errors}",
            )


class NoFixtureTests(unittest.TestCase):
    def test_engine_recognized_option_with_no_fixture_is_untested_not_an_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write_contracts(
                Path(tmp),
                contracts(record(kind="activity", id_="snorkeling", engineContract="deterministic", fixtureIDs=[])),
            )
            records, errors = load_contracts(path)
            self.assertEqual(errors, [])
            report = build_report(records)
            self.assertEqual([r.id for r in report.untested], ["snorkeling"])
            self.assertEqual(report.dead, [])
            self.assertEqual(report.context_only, [])


class ContextOnlyTests(unittest.TestCase):
    def test_valid_context_only_option_is_neither_dead_nor_untested(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write_contracts(
                Path(tmp),
                contracts(
                    record(
                        kind="bagType",
                        id_="notSure",
                        engineContract="contextOnly",
                        fixtureIDs=[],
                        iconContract="questionmark.circle",
                    )
                ),
            )
            records, errors = load_contracts(path)
            self.assertEqual(errors, [])
            report = build_report(records)
            self.assertEqual([r.id for r in report.context_only], ["notSure"])
            self.assertEqual(report.dead, [])
            # contextOnly records are exempt from the untested bucket even
            # without a fixture — there is no engine behavior to prove.
            self.assertEqual(report.untested, [])


class DeadBucketTests(unittest.TestCase):
    def test_missing_contract_lands_in_dead_bucket_with_its_fixture(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write_contracts(
                Path(tmp),
                contracts(
                    record(
                        kind="activity",
                        id_="camping",
                        engineContract="missing",
                        fixtureIDs=["18-reykjavik-64d-roadtrip-camping-seasonal"],
                        iconContract="tent",
                    )
                ),
            )
            records, errors = load_contracts(path)
            self.assertEqual(errors, [])
            report = build_report(records)
            self.assertEqual([r.id for r in report.dead], ["camping"])
            self.assertEqual(
                report.dead[0].fixture_ids,
                ("18-reykjavik-64d-roadtrip-camping-seasonal",),
            )


class LoadErrorTests(unittest.TestCase):
    def test_invalid_json_raises_contract_load_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "contracts.json"
            path.write_text("{ not json")
            with self.assertRaises(ContractLoadError):
                load_contracts(path)

    def test_missing_records_key_raises_contract_load_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write_contracts(Path(tmp), {"version": 1})
            with self.assertRaises(ContractLoadError):
                load_contracts(path)


class CompletenessCheckTests(unittest.TestCase):
    def test_source_case_with_no_contract_row_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write_contracts(Path(tmp), contracts(record(kind="tripType", id_="beach")))
            records, errors = load_contracts(path)
            self.assertEqual(errors, [])
            expected = SourceExpectation(
                trip_types={"beach", "business"},
                bag_types=set(),
                packing_styles=set(),
                laundry_access=set(),
                activities=set(),
            )
            completeness_errors = check_completeness(records, expected)
            self.assertTrue(
                any("tripType/business" in e and "no contract row" in e for e in completeness_errors),
                f"expected a missing-row error for tripType/business, got: {completeness_errors}",
            )

    def test_contract_row_with_no_source_case_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write_contracts(Path(tmp), contracts(record(kind="tripType", id_="retiredType")))
            records, errors = load_contracts(path)
            self.assertEqual(errors, [])
            expected = SourceExpectation(
                trip_types=set(),
                bag_types=set(),
                packing_styles=set(),
                laundry_access=set(),
                activities=set(),
            )
            completeness_errors = check_completeness(records, expected)
            self.assertTrue(
                any("tripType/retiredType" in e and "no matching source case" in e for e in completeness_errors),
                f"expected an extra-row error, got: {completeness_errors}",
            )

    def test_matching_ids_produce_no_errors(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write_contracts(Path(tmp), contracts(record(kind="tripType", id_="beach")))
            records, errors = load_contracts(path)
            self.assertEqual(errors, [])
            expected = SourceExpectation(
                trip_types={"beach"},
                bag_types=set(),
                packing_styles=set(),
                laundry_access=set(),
                activities=set(),
            )
            self.assertEqual(check_completeness(records, expected), [])


class RealContractsFileTests(unittest.TestCase):
    """Sanity check against the actual production file, so a future edit that
    breaks the schema (or drifts from the real enum/rule vocabulary) fails
    the Python suite, not just the Swift one."""

    def test_production_contracts_file_is_schema_valid_and_complete(self):
        repo_root = Path(__file__).resolve().parents[2]
        contracts_path = repo_root / "docs" / "engine-audits" / "surfaced-input-contracts.json"
        records, errors = load_contracts(contracts_path)
        self.assertEqual(errors, [], f"schema errors in production contracts file: {errors}")

        from scripts.audit_engine_inputs import discover_expected_ids

        expected = discover_expected_ids(repo_root)
        completeness_errors = check_completeness(records, expected)
        self.assertEqual(
            completeness_errors, [], f"production contracts file drifted from source: {completeness_errors}"
        )

    def test_camping_is_reported_missing_and_points_at_fixture_18(self):
        repo_root = Path(__file__).resolve().parents[2]
        contracts_path = repo_root / "docs" / "engine-audits" / "surfaced-input-contracts.json"
        records, errors = load_contracts(contracts_path)
        self.assertEqual(errors, [])
        report = build_report(records)
        camping = next(r for r in report.dead if r.kind == "activity" and r.id == "camping")
        self.assertIn("18-reykjavik-64d-roadtrip-camping-seasonal", camping.fixture_ids)


if __name__ == "__main__":
    unittest.main()
