#!/usr/bin/env python3
"""Tests for scripts/report_engine_goldens.py.

Run with:

    python3 -m unittest scripts.tests.test_report_engine_goldens -v

`golden(...)` and `item(...)` build minimal golden-output-shaped dicts —
the same shape `GoldenEngineTests.swift` writes under `ios/PackWiseTests/Goldens/`
(camelCase keys, `fixture`/`items`/`coverage`/`constraints`) — so these tests
exercise the exact parsing path production goldens go through.
"""

from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path

from scripts.report_engine_goldens import GoldenLoadError, compare_fixture, load_golden_dir, load_golden_git_ref


def golden(fixture="fixture", items=None, coverage=None, constraints=None):
    return {
        "fixture": fixture,
        "engineVersion": "v2",
        "items": items or [],
        "coverage": coverage or [],
        "constraints": constraints or [],
    }


def item(canonical_item_id, quantity=1, owner="primary", **overrides):
    base = {
        "owner": owner,
        "carrier": owner,
        "canonicalItemID": canonical_item_id,
        "displayName": canonical_item_id,
        "category": "misc",
        "quantity": quantity,
        "importance": "normal",
        "signals": [],
        "reasonCode": "reason.code",
        "reasonArguments": {},
        "reason": "because",
        "quantityReason": "",
    }
    base.update(overrides)
    return base


def coverage_entry(suppressed, owner="primary", capabilities=None, covered_by=None):
    return {
        "owner": owner,
        "suppressed": suppressed,
        "capabilities": capabilities or [],
        "coveredBy": covered_by or [],
    }


def constraint_entry(constraint, owner="primary", summary="Trimmed.", items=None):
    return {
        "owner": owner,
        "constraint": constraint,
        "summary": summary,
        "items": items or [],
    }


class UnchangedItemTests(unittest.TestCase):
    def test_identical_item_is_unchanged_not_a_change_of_any_kind(self):
        report = compare_fixture(
            golden(items=[item("clothing.tshirt", 5)]),
            golden(items=[item("clothing.tshirt", 5)]),
        )
        self.assertEqual(report.unchanged, [("primary", "clothing.tshirt")])
        self.assertEqual(report.added, [])
        self.assertEqual(report.removed, [])
        self.assertEqual(report.quantity_changes, [])
        self.assertEqual(report.trace_changes, [])
        self.assertTrue(report.is_unchanged)


class AdditionTests(unittest.TestCase):
    def test_item_only_in_candidate_is_added_not_a_quantity_change(self):
        report = compare_fixture(
            golden(items=[]),
            golden(items=[item("clothing.tshirt", 5)]),
        )
        self.assertEqual(report.added, [("primary", "clothing.tshirt", 5)])
        self.assertEqual(report.removed, [])
        self.assertEqual(report.quantity_changes, [])
        self.assertEqual(report.trace_changes, [])


class RemovalTests(unittest.TestCase):
    def test_item_only_in_baseline_is_removed_not_a_quantity_change(self):
        report = compare_fixture(
            golden(items=[item("clothing.tshirt", 5)]),
            golden(items=[]),
        )
        self.assertEqual(report.removed, [("primary", "clothing.tshirt", 5)])
        self.assertEqual(report.added, [])
        self.assertEqual(report.quantity_changes, [])
        self.assertEqual(report.trace_changes, [])


class QuantityChangeTests(unittest.TestCase):
    def test_quantity_change_is_not_add_remove(self):
        report = compare_fixture(
            golden(items=[item("clothing.tshirt", 7)]),
            golden(items=[item("clothing.tshirt", 3)]),
        )
        self.assertEqual(report.quantity_changes, [("primary", "clothing.tshirt", 7, 3)])
        self.assertEqual(report.added, [])
        self.assertEqual(report.removed, [])
        self.assertEqual(report.trace_changes, [])


class TraceChangeTests(unittest.TestCase):
    def test_reason_code_change_alone_is_a_trace_change_not_quantity(self):
        report = compare_fixture(
            golden(items=[item("clothing.tshirt", 5, reasonCode="base.essential.clothing")]),
            golden(items=[item("clothing.tshirt", 5, reasonCode="weather.rain_days")]),
        )
        self.assertEqual(len(report.trace_changes), 1)
        change = report.trace_changes[0]
        self.assertEqual((change.owner, change.canonical_item_id), ("primary", "clothing.tshirt"))
        self.assertIn("reasonCode", change.changed_fields)
        self.assertEqual(report.quantity_changes, [])
        self.assertEqual(report.added, [])
        self.assertEqual(report.removed, [])

    def test_signals_and_reason_arguments_are_also_trace_fields(self):
        report = compare_fixture(
            golden(items=[item("clothing.rain_jacket", 1, signals=["weather"], reasonArguments={"weekday": "Tuesday"})]),
            golden(items=[item("clothing.rain_jacket", 1, signals=["weather", "activity"], reasonArguments={"weekday": "Wednesday"})]),
        )
        self.assertEqual(len(report.trace_changes), 1)
        self.assertIn("signals", report.trace_changes[0].changed_fields)
        self.assertIn("reasonArguments", report.trace_changes[0].changed_fields)
        self.assertEqual(report.quantity_changes, [])

    def test_quantity_and_trace_can_change_together_and_both_are_reported(self):
        report = compare_fixture(
            golden(items=[item("clothing.tshirt", 7, reason="old")]),
            golden(items=[item("clothing.tshirt", 3, reason="new")]),
        )
        self.assertEqual(report.quantity_changes, [("primary", "clothing.tshirt", 7, 3)])
        self.assertEqual(len(report.trace_changes), 1)
        self.assertIn("reason", report.trace_changes[0].changed_fields)


class CoverageChangeTests(unittest.TestCase):
    def test_new_coverage_suppression_is_a_coverage_change(self):
        report = compare_fixture(
            golden(coverage=[]),
            golden(coverage=[coverage_entry("clothing.rain_jacket")]),
        )
        self.assertEqual(len(report.coverage_changes), 1)
        self.assertEqual(report.coverage_changes[0].kind, "added")
        self.assertEqual(report.coverage_changes[0].suppressed, "clothing.rain_jacket")

    def test_removed_coverage_suppression_is_a_coverage_change(self):
        report = compare_fixture(
            golden(coverage=[coverage_entry("clothing.rain_jacket")]),
            golden(coverage=[]),
        )
        self.assertEqual(len(report.coverage_changes), 1)
        self.assertEqual(report.coverage_changes[0].kind, "removed")

    def test_changed_coverage_capabilities_is_a_coverage_change(self):
        report = compare_fixture(
            golden(coverage=[coverage_entry("clothing.rain_jacket", capabilities=["outerwear.rain_shell"])]),
            golden(coverage=[coverage_entry("clothing.rain_jacket", capabilities=["outerwear.wind_shell"])]),
        )
        self.assertEqual(len(report.coverage_changes), 1)
        self.assertEqual(report.coverage_changes[0].kind, "changed")

    def test_identical_coverage_is_not_a_change(self):
        report = compare_fixture(
            golden(coverage=[coverage_entry("clothing.rain_jacket")]),
            golden(coverage=[coverage_entry("clothing.rain_jacket")]),
        )
        self.assertEqual(report.coverage_changes, [])


class ConstraintChangeTests(unittest.TestCase):
    def test_new_constraint_decision_is_a_constraint_change(self):
        report = compare_fixture(
            golden(constraints=[]),
            golden(constraints=[constraint_entry("bag.personal_item")]),
        )
        self.assertEqual(len(report.constraint_changes), 1)
        self.assertEqual(report.constraint_changes[0].kind, "added")

    def test_identical_constraints_are_not_a_change(self):
        report = compare_fixture(
            golden(constraints=[constraint_entry("bag.personal_item", items=["a", "b"])]),
            golden(constraints=[constraint_entry("bag.personal_item", items=["a", "b"])]),
        )
        self.assertEqual(report.constraint_changes, [])


class NewFixtureTests(unittest.TestCase):
    def test_fixture_present_only_in_candidate_is_reported_as_new_not_diffed(self):
        from scripts.report_engine_goldens import compare_directories

        baseline = {"01-existing": golden(fixture="01-existing", items=[item("clothing.tshirt", 5)])}
        candidate = {
            "01-existing": golden(fixture="01-existing", items=[item("clothing.tshirt", 5)]),
            "18-anchorage-64d": golden(fixture="18-anchorage-64d", items=[item("clothing.parka", 1)]),
        }
        report = compare_directories(baseline, candidate)
        self.assertEqual(report.new_fixtures, ["18-anchorage-64d"])
        self.assertEqual(report.removed_fixtures, [])
        self.assertEqual(len(report.fixtures), 1)
        self.assertTrue(report.fixtures[0].is_unchanged)

    def test_fixture_present_only_in_baseline_is_reported_as_removed(self):
        from scripts.report_engine_goldens import compare_directories

        baseline = {
            "01-existing": golden(fixture="01-existing", items=[]),
            "99-retired": golden(fixture="99-retired", items=[]),
        }
        candidate = {"01-existing": golden(fixture="01-existing", items=[])}
        report = compare_directories(baseline, candidate)
        self.assertEqual(report.removed_fixtures, ["99-retired"])
        self.assertEqual(report.new_fixtures, [])


class ReportOverallSummaryTests(unittest.TestCase):
    def test_totals_aggregate_across_fixtures(self):
        from scripts.report_engine_goldens import compare_directories

        baseline = {
            "a": golden(fixture="a", items=[item("clothing.tshirt", 5)]),
            "b": golden(fixture="b", items=[item("clothing.socks", 2)]),
        }
        candidate = {
            "a": golden(fixture="a", items=[item("clothing.tshirt", 3)]),
            "b": golden(fixture="b", items=[item("clothing.socks", 2)]),
        }
        report = compare_directories(baseline, candidate)
        totals = report.totals()
        self.assertEqual(totals["QUANTITY CHANGES"], 1)
        self.assertEqual(totals["UNCHANGED"], 1)
        self.assertFalse(report.is_clean)

    def test_clean_report_when_nothing_changed(self):
        from scripts.report_engine_goldens import compare_directories

        baseline = {"a": golden(fixture="a", items=[item("clothing.tshirt", 5)])}
        candidate = {"a": golden(fixture="a", items=[item("clothing.tshirt", 5)])}
        report = compare_directories(baseline, candidate)
        self.assertTrue(report.is_clean)


class LoaderErrorTests(unittest.TestCase):
    """Malformed input must raise a clean GoldenLoadError, not a raw
    traceback — see `main()`'s `except GoldenLoadError` handling below."""

    def test_malformed_json_in_golden_file_raises_clean_error_naming_the_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            bad_path = Path(tmp) / "broken.json"
            bad_path.write_text("{not valid json")
            with self.assertRaises(GoldenLoadError) as ctx:
                load_golden_dir(Path(tmp))
            message = str(ctx.exception)
            self.assertIn(str(bad_path), message)
            self.assertIn("invalid JSON", message)

    def test_well_formed_json_alongside_a_malformed_file_still_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "ok.json").write_text('{"fixture": "ok", "items": []}')
            bad_path = Path(tmp) / "broken.json"
            bad_path.write_text("{not valid json")
            with self.assertRaises(GoldenLoadError):
                load_golden_dir(Path(tmp))

    def test_bad_baseline_ref_raises_clean_error_naming_the_ref(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo_root = Path(tmp)
            subprocess.run(["git", "init", "-q"], cwd=repo_root, check=True)
            with self.assertRaises(GoldenLoadError) as ctx:
                load_golden_git_ref("this-ref-does-not-exist", Path("goldens"), repo_root)
            message = str(ctx.exception)
            self.assertIn("this-ref-does-not-exist", message)


class MainErrorExitCodeTests(unittest.TestCase):
    """These error paths must exit 2 ("tool/usage-level failure"), the same
    code as the existing --candidate/--baseline-dir "is not a directory"
    checks — never 1, which means "real diffs found"."""

    def test_malformed_json_candidate_exits_2_not_1(self):
        from scripts.report_engine_goldens import main

        with tempfile.TemporaryDirectory() as tmp:
            candidate_dir = Path(tmp) / "candidate"
            candidate_dir.mkdir()
            (candidate_dir / "broken.json").write_text("{not valid json")
            baseline_dir = Path(tmp) / "baseline"
            baseline_dir.mkdir()
            exit_code = main(["--baseline-dir", str(baseline_dir), "--candidate", str(candidate_dir)])
            self.assertEqual(exit_code, 2)

    def test_malformed_json_baseline_dir_exits_2_not_1(self):
        from scripts.report_engine_goldens import main

        with tempfile.TemporaryDirectory() as tmp:
            candidate_dir = Path(tmp) / "candidate"
            candidate_dir.mkdir()
            baseline_dir = Path(tmp) / "baseline"
            baseline_dir.mkdir()
            (baseline_dir / "broken.json").write_text("{not valid json")
            exit_code = main(["--baseline-dir", str(baseline_dir), "--candidate", str(candidate_dir)])
            self.assertEqual(exit_code, 2)


class RenderTests(unittest.TestCase):
    def test_text_and_markdown_render_without_error_and_mention_fixture(self):
        from scripts.report_engine_goldens import compare_directories, render_markdown, render_text

        baseline = {"01-existing": golden(fixture="01-existing", items=[item("clothing.tshirt", 5)])}
        candidate = {"01-existing": golden(fixture="01-existing", items=[item("clothing.tshirt", 3)])}
        report = compare_directories(baseline, candidate)

        text = render_text(report)
        self.assertIn("01-existing", text)
        self.assertIn("QUANTITY CHANGES", text)

        markdown = render_markdown(report)
        self.assertIn("01-existing", markdown)
        self.assertIn("QUANTITY CHANGES", markdown)


if __name__ == "__main__":
    unittest.main()
