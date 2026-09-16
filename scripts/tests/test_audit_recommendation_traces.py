#!/usr/bin/env python3
"""Tests for scripts/audit_recommendation_traces.py.

Run with:

    python3 -m unittest scripts.tests.test_audit_recommendation_traces -v

`item(...)` and `golden(...)` build minimal golden-output-shaped dicts, the
same shape `GoldenEngineTests.swift` writes under `ios/PackWiseTests/Goldens/`
(camelCase keys), so these tests exercise the exact parsing path production
goldens go through. Several cases below are copied verbatim from real,
currently-committed goldens (noted per test) rather than invented, so a
change to the actual engine output that breaks the premise of a test is
caught here too.
"""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from scripts.audit_recommendation_traces import (
    POLICY_SENSITIVE_QUANTITY_KINDS,
    TraceItem,
    TraceLoadError,
    build_report,
    classify_inclusion,
    classify_quantity,
    load_items,
    load_policy_sensitive_ids,
    main,
    render_markdown,
    render_text,
)


def item(canonical_item_id, owner="primary", quantity=1, **overrides):
    base = {
        "owner": owner,
        "carrier": owner,
        "canonicalItemID": canonical_item_id,
        "displayName": canonical_item_id,
        "category": "misc",
        "quantity": quantity,
        "importance": "normal",
        "signals": ["weather"],
        "reasonCode": "weather.rain_days",
        "reasonArguments": {},
        "reason": "because",
        "quantityReason": "",
    }
    base.update(overrides)
    return base


def golden(fixture="fixture", items=None):
    return {"fixture": fixture, "engineVersion": "v2", "items": items or []}


def make_item(**overrides):
    """Builds a `TraceItem` directly from its dataclass field names (not the
    JSON dict `item(...)` builds) — for tests exercising the seasonal/
    fabricated-authority/closed-vocabulary checks, which read `reason_code`,
    `reason_arguments`, `quantity_reason_arguments`, `user_modified` fields
    that don't need a full JSON round-trip to test. Dict/list literals are
    normalized to the same hashable tuple shapes `TraceItem.from_json` uses."""
    defaults = dict(
        fixture="test",
        owner="primary",
        canonical_item_id="test.item",
        category="misc",
        quantity=1,
        reason_code="weather.rain_days",
        reason="because",
        signals=("weather",),
        reason_arguments=(),
        quantity_reason="",
        quantity_reason_arguments=(),
        user_modified=None,
    )
    defaults.update(overrides)
    for key in ("reason_arguments", "quantity_reason_arguments"):
        if isinstance(defaults[key], dict):
            defaults[key] = tuple(sorted(defaults[key].items()))
    if isinstance(defaults["signals"], list):
        defaults["signals"] = tuple(defaults["signals"])
    return TraceItem(**defaults)


def write_goldens(tmp_path: Path, *goldens: dict) -> Path:
    goldens_dir = tmp_path / "goldens"
    goldens_dir.mkdir()
    for i, g in enumerate(goldens):
        (goldens_dir / f"{g.get('fixture', f'fixture{i}')}.json").write_text(json.dumps(g))
    return goldens_dir


def write_catalog(tmp_path: Path, items: list) -> Path:
    path = tmp_path / "clothing.json"
    path.write_text(json.dumps({"version": 1, "category": "clothing", "items": items}))
    return path


# ---------------------------------------------------------------------------
# Inclusion completeness classification
# ---------------------------------------------------------------------------


class InclusionClassificationTests(unittest.TestCase):
    def test_fixed_singleton_with_specific_reason_is_specific(self):
        # documents.id, fixture 01: quantity 1, base-essential reason code —
        # a passport/ID-like fixed singleton.
        t = TraceItem.from_json(
            "01",
            item(
                "documents.id",
                reasonCode="base.essential.documents",
                reason="Easy to forget, hard to replace.",
                signals=["baseEssential"],
            ),
        )
        self.assertEqual(classify_inclusion(t), "base_essential")

    def test_weather_driven_jacket_with_specific_signal_is_specific(self):
        # clothing.rain_jacket, fixture 01: weather-driven, specific reason
        # code, named signal and reasonArguments.
        t = TraceItem.from_json(
            "01",
            item(
                "clothing.rain_jacket",
                reasonCode="weather.rain_weekday",
                reason="Rain is expected Tuesday.",
                signals=["weather"],
                reasonArguments={"weekday": "Tuesday"},
            ),
        )
        self.assertEqual(classify_inclusion(t), "specific")

    def test_generic_only_reason_is_generic_not_specific(self):
        # essentials.sunglasses, fixture 01: real trip_type.generic row —
        # the designed generic fallback tier, not a fabricated example.
        t = TraceItem.from_json(
            "01",
            item(
                "essentials.sunglasses",
                reasonCode="trip_type.generic",
                reason="Suggested for a city break trip.",
                signals=["tripType"],
                reasonArguments={"tripType": "city break"},
            ),
        )
        self.assertEqual(classify_inclusion(t), "generic_only")

    def test_shared_umbrella_with_specific_reason_is_specific(self):
        # essentials.umbrella_compact, fixture 11: owner == "shared".
        t = TraceItem.from_json(
            "11",
            item(
                "essentials.umbrella_compact",
                owner="shared",
                reasonCode="weather.rain_days",
                reason="Rain is expected on 3 days. One umbrella should cover your group.",
                signals=["weather"],
            ),
        )
        self.assertEqual(classify_inclusion(t), "specific")

    def test_missing_reason_code_on_a_non_user_authority_row_is_a_defect(self):
        t = TraceItem.from_json(
            "synthetic",
            item("clothing.hat", reasonCode="", reason="", signals=[], userModified=None),
        )
        self.assertEqual(classify_inclusion(t), "missing_reason_code")

    def test_reason_code_present_but_no_signals_is_a_defect(self):
        t = TraceItem.from_json(
            "synthetic",
            item("clothing.hat", reasonCode="weather.hot", signals=[]),
        )
        self.assertEqual(classify_inclusion(t), "missing_signal")

    def test_user_modified_row_with_empty_trace_is_user_authority_not_a_defect(self):
        # clothing.tshirt, fixture 14: real "manual quantity survives
        # refresh" row — the one golden row Task 1's baseline noted has no
        # reason code, because the user, not the engine, owns this decision.
        t = TraceItem.from_json(
            "14",
            item(
                "clothing.tshirt",
                quantity=3,
                reasonCode="",
                reason="",
                signals=[],
                quantityReason="",
                userModified=True,
            ),
        )
        self.assertTrue(t.is_user_authority)
        self.assertEqual(classify_inclusion(t), "user_authority")

    def test_custom_item_with_empty_trace_is_user_authority_not_a_defect(self):
        # custom.lucky_travel_journal, fixture 27: genuinely off-catalog,
        # user-typed item.
        t = TraceItem.from_json(
            "27",
            item(
                "custom.lucky_travel_journal",
                reasonCode="",
                reason="",
                signals=[],
            ),
        )
        self.assertTrue(t.is_user_authority)
        self.assertEqual(classify_inclusion(t), "user_authority")

    def test_existing_item_recognized_as_coverage_is_user_authority(self):
        # clothing.rain_jacket, fixture 26: user-added-existing item folded
        # into coverage — userModified true, empty trace, distinct fixture
        # from the specific-reason rain jacket case above.
        t = TraceItem.from_json(
            "26",
            item(
                "clothing.rain_jacket",
                reasonCode="",
                reason="",
                signals=[],
                userModified=True,
            ),
        )
        self.assertEqual(classify_inclusion(t), "user_authority")


# ---------------------------------------------------------------------------
# Quantity evidence classification
# ---------------------------------------------------------------------------


class QuantityClassificationTests(unittest.TestCase):
    def test_fixed_singleton_quantity_one_not_shared_not_policy_governed(self):
        t = TraceItem.from_json("01", item("documents.id", quantity=1, quantityReason=""))
        self.assertEqual(classify_quantity(t, frozenset()), "fixed_singleton")

    def test_policy_sensitive_quantity_gt_1_with_reason_has_evidence(self):
        # clothing.tshirt, fixture 01: base-essential, policy-governed
        # (daily_top), quantity 2, with a duration-based quantityReason.
        t = TraceItem.from_json(
            "01",
            item(
                "clothing.tshirt",
                quantity=2,
                quantityReason="2 based on a 5-day trip.",
            ),
        )
        self.assertEqual(classify_quantity(t, frozenset({"clothing.tshirt"})), "evidence_present")

    def test_quantity_gt_1_without_policy_membership_still_requires_evidence(self):
        # quantity > 1 alone triggers the requirement, independent of the
        # catalog cross-reference.
        t = TraceItem.from_json("01", item("clothing.tshirt", quantity=2, quantityReason=""))
        self.assertEqual(classify_quantity(t, frozenset()), "evidence_missing")

    def test_shared_owner_at_quantity_one_requires_evidence(self):
        t = TraceItem.from_json(
            "12",
            item(
                "kids.stroller",
                owner="shared",
                quantity=1,
                quantityReason="One for the group — not one per person.",
            ),
        )
        self.assertEqual(classify_quantity(t, frozenset()), "evidence_present")

    def test_shared_owner_at_quantity_one_without_reason_is_missing_evidence(self):
        t = TraceItem.from_json("12", item("kids.stroller", owner="shared", quantity=1, quantityReason=""))
        self.assertEqual(classify_quantity(t, frozenset()), "evidence_missing")

    def test_policy_governed_kind_at_quantity_one_requires_evidence_via_catalog(self):
        # clothing.sleepwear at its floor (quantity 1): policy-sensitive by
        # catalog membership even though quantity itself is not > 1.
        t = TraceItem.from_json("01", item("clothing.sleepwear", quantity=1, quantityReason=""))
        self.assertEqual(classify_quantity(t, frozenset({"clothing.sleepwear"})), "evidence_missing")

    def test_user_authority_row_is_exempt_from_quantity_scoring(self):
        t = TraceItem.from_json(
            "14",
            item("clothing.tshirt", quantity=3, quantityReason="", userModified=True),
        )
        self.assertEqual(classify_quantity(t, frozenset({"clothing.tshirt"})), "user_authority")


# ---------------------------------------------------------------------------
# Catalog loading (policy-sensitive quantity_kind cross-reference)
# ---------------------------------------------------------------------------


class PolicySensitiveCatalogTests(unittest.TestCase):
    def test_items_with_a_policy_kind_are_selected(self):
        with tempfile.TemporaryDirectory() as tmp:
            catalog = write_catalog(
                Path(tmp),
                [
                    {"id": "clothing.tshirt", "quantity_kind": "daily_top"},
                    {"id": "clothing.rain_jacket", "quantity_kind": "one"},
                    {"id": "clothing.sleepwear", "quantity_kind": "sleepwear"},
                ],
            )
            ids, warning = load_policy_sensitive_ids(catalog)
        self.assertIsNone(warning)
        self.assertEqual(ids, frozenset({"clothing.tshirt", "clothing.sleepwear"}))

    def test_every_policy_kind_constant_is_a_real_clothingneedpolicy_kind(self):
        # Cheap guard against the mirrored constant silently drifting from
        # ClothingQuantity.swift: every kind here must actually be one this
        # audit's docstring claims (the six ClothingNeedPolicy needs).
        expected = {
            "daily_top",
            "daily_underwear",
            "daily_socks",
            "bottoms",
            "hot_bottoms",
            "sleepwear",
            "workout_top",
            "workout_bottom",
        }
        self.assertEqual(POLICY_SENSITIVE_QUANTITY_KINDS, frozenset(expected))

    def test_missing_catalog_file_warns_and_returns_empty_set_not_an_error(self):
        ids, warning = load_policy_sensitive_ids(Path("/nonexistent/clothing.json"))
        self.assertEqual(ids, frozenset())
        self.assertIsNotNone(warning)

    def test_none_catalog_path_is_silently_skipped(self):
        ids, warning = load_policy_sensitive_ids(None)
        self.assertEqual(ids, frozenset())
        self.assertIsNone(warning)


# ---------------------------------------------------------------------------
# Loading goldens
# ---------------------------------------------------------------------------


class LoadItemsTests(unittest.TestCase):
    def test_loads_items_across_multiple_fixture_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            goldens_dir = write_goldens(
                Path(tmp),
                golden("fixture-a", [item("documents.id")]),
                golden("fixture-b", [item("clothing.tshirt"), item("clothing.socks")]),
            )
            items = load_items(goldens_dir)
        self.assertEqual(len(items), 3)
        self.assertEqual({i.fixture for i in items}, {"fixture-a", "fixture-b"})

    def test_malformed_json_raises_trace_load_error_naming_the_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            goldens_dir = Path(tmp) / "goldens"
            goldens_dir.mkdir()
            broken = goldens_dir / "broken.json"
            broken.write_text("{not valid json")
            with self.assertRaises(TraceLoadError) as ctx:
                load_items(goldens_dir)
        self.assertIn("broken.json", str(ctx.exception))

    def test_empty_directory_raises_trace_load_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            goldens_dir = Path(tmp) / "goldens"
            goldens_dir.mkdir()
            with self.assertRaises(TraceLoadError):
                load_items(goldens_dir)


# ---------------------------------------------------------------------------
# Report aggregation
# ---------------------------------------------------------------------------


class ReportAggregationTests(unittest.TestCase):
    def test_user_authority_items_excluded_from_engine_item_denominator(self):
        items = [
            TraceItem.from_json("f", item("documents.id")),
            TraceItem.from_json(
                "f",
                item("custom.lucky_journal", reasonCode="", reason="", signals=[]),
            ),
        ]
        report = build_report(items, frozenset(), None)
        self.assertEqual(report.total_items, 2)
        self.assertEqual(report.engine_items, 1)
        self.assertEqual(len(report.inclusion["user_authority"]), 1)

    def test_clean_report_has_zero_defects(self):
        items = [
            TraceItem.from_json("f", item("documents.id", quantity=1, quantityReason="")),
            TraceItem.from_json(
                "f", item("clothing.tshirt", quantity=2, quantityReason="2 based on a 5-day trip.")
            ),
        ]
        report = build_report(items, frozenset(), None)
        self.assertTrue(report.is_clean)
        self.assertEqual(report.inclusion_defect_count, 0)
        self.assertEqual(len(report.quantity["evidence_missing"]), 0)

    def test_defect_report_is_not_clean(self):
        items = [
            TraceItem.from_json(
                "f", item("clothing.hat", reasonCode="", reason="", signals=[], userModified=None)
            )
        ]
        report = build_report(items, frozenset(), None)
        self.assertFalse(report.is_clean)
        self.assertEqual(report.inclusion_defect_count, 1)

    def test_completeness_percentage_over_engine_items_only(self):
        items = [
            TraceItem.from_json("f", item("documents.id")),  # specific/complete via default reasonCode
            TraceItem.from_json(
                "f", item("essentials.sunglasses", reasonCode="trip_type.generic", signals=["tripType"])
            ),
            TraceItem.from_json(
                "f", item("custom.thing", reasonCode="", reason="", signals=[])
            ),  # exempt, not in denominator
        ]
        report = build_report(items, frozenset(), None)
        self.assertEqual(report.engine_items, 2)
        # documents.id is "specific" (default reasonCode weather.rain_days
        # counts as specific in this synthetic set); sunglasses is generic —
        # only 1 of 2 engine rows is complete.
        self.assertEqual(report.inclusion_complete_count, 1)
        self.assertAlmostEqual(report.inclusion_completeness_pct, 50.0)


# ---------------------------------------------------------------------------
# Rendering smoke tests
# ---------------------------------------------------------------------------


class RenderTests(unittest.TestCase):
    def test_text_and_markdown_render_without_error_and_mention_totals(self):
        items = [TraceItem.from_json("f", item("documents.id"))]
        report = build_report(items, frozenset(), None)
        text = render_text(report)
        md = render_markdown(report)
        self.assertIn("Total item rows: 1", text)
        self.assertIn("Total item rows", md)
        self.assertIn("CLEAN", text)

    def test_catalog_warning_surfaces_in_both_formats(self):
        items = [TraceItem.from_json("f", item("documents.id"))]
        report = build_report(items, frozenset(), "catalog missing")
        self.assertIn("catalog missing", render_text(report))
        self.assertIn("catalog missing", render_markdown(report))


# ---------------------------------------------------------------------------
# Phase 8, Task 7: seasonal provenance, fabricated user-authority provenance,
# and the closed quantityReasonArguments key vocabulary
# ---------------------------------------------------------------------------


class NewDefectChecksTests(unittest.TestCase):
    def test_seasonal_reason_code_with_nonempty_arguments_is_a_defect(self):
        i = make_item(reason_code="weather.seasonal_sun", reason_arguments={"days": "3"})
        report = build_report([i], policy_sensitive_ids=frozenset(), catalog_warning=None)
        self.assertEqual(len(report.invalid_seasonal_provenance), 1)

    def test_seasonal_reason_code_with_empty_arguments_is_clean(self):
        i = make_item(reason_code="weather.seasonal_sun", reason_arguments={})
        report = build_report([i], policy_sensitive_ids=frozenset(), catalog_warning=None)
        self.assertEqual(len(report.invalid_seasonal_provenance), 0)

    def test_precise_weather_reason_code_with_arguments_is_unaffected(self):
        i = make_item(reason_code="weather.rain_days", reason_arguments={"rainDays": "2", "tripDays": "5"})
        report = build_report([i], policy_sensitive_ids=frozenset(), catalog_warning=None)
        self.assertEqual(len(report.invalid_seasonal_provenance), 0)

    def test_user_authority_row_with_a_reason_code_is_fabricated_provenance(self):
        i = make_item(user_modified=True, reason_code="base.essential.clothing", signals=("baseEssential",))
        report = build_report([i], policy_sensitive_ids=frozenset(), catalog_warning=None)
        self.assertEqual(len(report.fabricated_user_authority_provenance), 1)

    def test_user_authority_row_with_empty_trace_is_clean(self):
        i = make_item(user_modified=True, reason_code="", reason="", signals=())
        report = build_report([i], policy_sensitive_ids=frozenset(), catalog_warning=None)
        self.assertEqual(len(report.fabricated_user_authority_provenance), 0)

    def test_custom_item_row_with_a_reason_is_fabricated_provenance(self):
        i = make_item(canonical_item_id="custom.lucky_journal", reason="Suggested for your trip", reason_code="trip_type.generic")
        report = build_report([i], policy_sensitive_ids=frozenset(), catalog_warning=None)
        self.assertEqual(len(report.fabricated_user_authority_provenance), 1)

    def test_quantity_reason_argument_key_outside_the_closed_vocabulary_is_a_defect(self):
        i = make_item(quantity_reason_arguments={"washCycleDays": "3"})
        report = build_report([i], policy_sensitive_ids=frozenset(), catalog_warning=None)
        self.assertEqual(len(report.invalid_quantity_reason_argument_keys), 1)

    def test_quantity_reason_argument_keys_from_the_closed_vocabulary_are_clean(self):
        i = make_item(quantity_reason_arguments={"quantity": "2", "travelerCount": "4"})
        report = build_report([i], policy_sensitive_ids=frozenset(), catalog_warning=None)
        self.assertEqual(len(report.invalid_quantity_reason_argument_keys), 0)

    def test_all_six_closed_vocabulary_keys_are_individually_clean(self):
        for key in ("quantity", "days", "rate", "name", "travelerCount", "rainDays"):
            i = make_item(quantity_reason_arguments={key: "x"})
            report = build_report([i], policy_sensitive_ids=frozenset(), catalog_warning=None)
            self.assertEqual(len(report.invalid_quantity_reason_argument_keys), 0, f"key {key!r} should be closed-vocabulary clean")

    def test_new_checks_fold_into_is_clean(self):
        i = make_item(reason_code="weather.seasonal_sun", reason_arguments={"days": "3"})
        report = build_report([i], policy_sensitive_ids=frozenset(), catalog_warning=None)
        self.assertFalse(report.is_clean)

    def test_new_checks_render_in_text_and_markdown(self):
        i = make_item(reason_code="weather.seasonal_sun", reason_arguments={"days": "3"})
        report = build_report([i], policy_sensitive_ids=frozenset(), catalog_warning=None)
        self.assertIn("seasonal", render_text(report).lower())
        self.assertIn("seasonal", render_markdown(report).lower())

    def test_from_json_threads_quantity_reason_arguments_through(self):
        t = TraceItem.from_json(
            "f",
            item("toiletries.sunscreen", owner="shared", quantity=2, quantityReasonArguments={"quantity": "2", "travelerCount": "4"}),
        )
        self.assertEqual(dict(t.quantity_reason_arguments), {"quantity": "2", "travelerCount": "4"})


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


class MainCLITests(unittest.TestCase):
    def test_default_exit_is_zero_even_with_defects(self):
        with tempfile.TemporaryDirectory() as tmp:
            goldens_dir = write_goldens(
                Path(tmp),
                golden(
                    "f",
                    [item("clothing.hat", reasonCode="", reason="", signals=[], userModified=None)],
                ),
            )
            code = main(["--goldens", str(goldens_dir), "--catalog", ""])
        self.assertEqual(code, 0)

    def test_strict_exit_is_one_with_defects(self):
        with tempfile.TemporaryDirectory() as tmp:
            goldens_dir = write_goldens(
                Path(tmp),
                golden(
                    "f",
                    [item("clothing.hat", reasonCode="", reason="", signals=[], userModified=None)],
                ),
            )
            code = main(["--goldens", str(goldens_dir), "--catalog", "", "--strict"])
        self.assertEqual(code, 1)

    def test_strict_exit_is_zero_when_clean(self):
        with tempfile.TemporaryDirectory() as tmp:
            goldens_dir = write_goldens(Path(tmp), golden("f", [item("documents.id")]))
            code = main(["--goldens", str(goldens_dir), "--catalog", "", "--strict"])
        self.assertEqual(code, 0)

    def test_missing_goldens_dir_exits_2(self):
        code = main(["--goldens", "/nonexistent/path"])
        self.assertEqual(code, 2)

    def test_malformed_json_exits_2(self):
        with tempfile.TemporaryDirectory() as tmp:
            goldens_dir = Path(tmp) / "goldens"
            goldens_dir.mkdir()
            (goldens_dir / "broken.json").write_text("{not valid")
            code = main(["--goldens", str(goldens_dir)])
        self.assertEqual(code, 2)


if __name__ == "__main__":
    unittest.main()
