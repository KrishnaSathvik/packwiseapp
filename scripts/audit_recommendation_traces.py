#!/usr/bin/env python3
"""Recommendation-trace completeness audit for the PackWise engine goldens.

Global product gate 7 promises: "every generated item can state why it is
included, why its quantity was chosen, and which signals mattered."
`ios/PackWiseTests/Goldens/*.json` is where that promise becomes checkable —
every row already carries `reasonCode`, `reason`, `signals`, `reasonArguments`,
`quantity`, and `quantityReason` (`GoldenEngineTests.swift`'s `GoldenItem`).
This script classifies every row across every fixture against two independent
bars and reports exact counts, not vibes.

INCLUSION COMPLETENESS
-----------------------
A row has complete inclusion evidence when all three hold:

  1. non-empty `reasonCode`
  2. non-empty `signals` (at least one causal signal)
  3. the explanation is either://
       - an *approved base essential* — `reasonCode` starts with
         `"base.essential."`, the family the engine uses for the fixed list
         in `shared/rules/base.json`'s `base_essentials`, or
       - *specific* — a real `reasonCode` that is not one of the designed
         generic fallback tiers (`shared/rules/reasons.json` names several:
         `activity.generic`, `trip_type.generic`, `preference.generic`,
         `weather_change.generic`, `context.gap_generic`,
         `context.optimize_generic` — anything ending `.generic`).

A row that clears (1) and (2) but lands on a `.generic` reason code is
"generic-only": present and causally attributed, but the weakest tier of
explanation the engine has — worth tracking, not a defect by itself (the
Engine V2 rebuild plan is explicit that a generic fallback is only a bug when
it appears on a weather- or activity-driven item; this script does not have
enough context to tell a legitimate trip-type-only item from a starved
weather/activity item, so it reports the whole bucket and leaves that call to
a human). A row that fails (1) or (2) outright is a hard defect: the engine
produced an item and lost the ability to say why.

USER-AUTHORITY ROWS ARE EXEMPT, NOT SCORED
-------------------------------------------
An item with `userModified: true`, or a `custom.*` canonical id (an
off-catalog item the user typed in), is expected to carry an empty
`reasonCode`/`reason`/`signals` — the trace exists for engine reasoning, and
these rows are the user's decision, not the engine's. They are reported in
their own bucket and excluded from the inclusion/quantity completeness
denominators; do not count an empty trace here as a defect.

QUANTITY EVIDENCE
------------------
Required only for rows the plan calls "policy-sensitive or quantity>1";
everything else is a "fixed singleton" and not held to the bar:

  requires quantity evidence  quantity > 1
                               OR owner == "shared" (a group-sharing quantity
                                 decision, e.g. one umbrella for a couple)
                               OR the item's catalog `quantity_kind` is one
                                 ClothingNeedPolicy actually governs (laundry/
                                 style/bag sensitivity can move its number —
                                 see ios/PackWise/Domain/Packing/
                                 ClothingQuantity.swift)
  fixed singleton              everything else (quantity == 1, not shared,
                                 not a policy-governed clothing kind)

A row that requires evidence must carry a non-empty `quantityReason`.

CLI:

    python3 scripts/audit_recommendation_traces.py \\
        --goldens ios/PackWiseTests/Goldens
    python3 scripts/audit_recommendation_traces.py \\
        --goldens ios/PackWiseTests/Goldens --format markdown

Exit code reflects tool health only, the same convention
`audit_engine_inputs.py` uses: 0 the goldens (and, if given, the catalog)
loaded and parsed cleanly; 2 a tool error (bad path, malformed JSON). A
non-empty defect bucket — missing reason code, missing causal signal, or
missing quantity evidence on a row that requires it — is a reportable
finding routed to a later phase, not a build-breaking validation failure;
the report's own CLEAN / DEFECTS FOUND line and `--format markdown`'s totals
are how a human (or `docs/engine-audits/2026-09-03-engine-findings.md`) sees
it. Pass `--strict` to exit 1 instead when defects are present, for a CI
step that should treat this file's current defect count as a regression gate.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, FrozenSet, List, Optional, Tuple

# ---------------------------------------------------------------------------
# Schema
# ---------------------------------------------------------------------------

# The `quantity_kind` values ClothingNeedPolicy.all actually declares a
# laundry/style/bag sensitivity for (ios/PackWise/Domain/Packing/
# ClothingQuantity.swift). Mirrored here, not re-derived at runtime, the same
# way report_engine_goldens.py mirrors GoldenItem's field list — six needs,
# stable, update this set if that array changes.
POLICY_SENSITIVE_QUANTITY_KINDS: FrozenSet[str] = frozenset(
    {
        "daily_top",
        "daily_underwear",
        "daily_socks",
        "bottoms",
        "hot_bottoms",
        "sleepwear",
        "workout_top",
        "workout_bottom",
    }
)

BASE_ESSENTIAL_PREFIX = "base.essential."
GENERIC_REASON_SUFFIX = ".generic"
SEASONAL_REASON_PREFIX = "weather.seasonal"

# quantityReasonArguments' closed key vocabulary (Phase 8, Task 1) — grounded
# in the three real call sites that populate it (care, warm-layer rotation,
# party sharing). Any key outside this set means an unreviewed fourth call
# site started writing this field, the same drift ActivityNeed/
# PackingCapability/WeatherSignal already guard against.
CLOSED_QUANTITY_REASON_ARGUMENT_KEYS: FrozenSet[str] = frozenset(
    {"quantity", "days", "rate", "name", "travelerCount", "rainDays", "sharingPolicy", "per", "deviceCount", "eligibleConsumerCount"}
)


@dataclass(frozen=True)
class TraceItem:
    fixture: str
    owner: str
    canonical_item_id: str
    category: str
    quantity: int
    reason_code: str
    reason: str
    signals: Tuple[str, ...]
    reason_arguments: Tuple[Tuple[str, str], ...]
    quantity_reason: str
    quantity_reason_arguments: Tuple[Tuple[str, str], ...]
    user_modified: object

    @property
    def is_user_authority(self) -> bool:
        return bool(self.user_modified) or self.canonical_item_id.startswith("custom.")

    @property
    def label(self) -> str:
        return f"{self.fixture}: {self.owner}/{self.canonical_item_id}"

    @staticmethod
    def from_json(fixture: str, raw: dict) -> "TraceItem":
        return TraceItem(
            fixture=fixture,
            owner=raw.get("owner", ""),
            canonical_item_id=raw.get("canonicalItemID", ""),
            category=raw.get("category", ""),
            quantity=raw.get("quantity", 0),
            reason_code=raw.get("reasonCode", ""),
            reason=raw.get("reason", ""),
            signals=tuple(raw.get("signals", [])),
            reason_arguments=tuple(sorted(raw.get("reasonArguments", {}).items())),
            quantity_reason=raw.get("quantityReason", ""),
            quantity_reason_arguments=tuple(sorted(raw.get("quantityReasonArguments", {}).items())),
            user_modified=raw.get("userModified"),
        )


class TraceLoadError(Exception):
    """A golden file or the catalog file could not be loaded cleanly.

    `main()` catches this and prints a friendly `error: ...` message
    (exit 2) instead of letting the underlying traceback reach the caller —
    matches report_engine_goldens.py's GoldenLoadError / audit_engine_inputs.py's
    ContractLoadError.
    """


def load_items(goldens_dir: Path) -> List[TraceItem]:
    items: List[TraceItem] = []
    paths = sorted(goldens_dir.glob("*.json"))
    if not paths:
        raise TraceLoadError(f"{goldens_dir}: no *.json golden files found")
    for path in paths:
        try:
            raw = json.loads(path.read_text())
        except json.JSONDecodeError as e:
            raise TraceLoadError(f"{path}: invalid JSON ({e})") from e
        fixture = raw.get("fixture", path.stem)
        for raw_item in raw.get("items", []):
            items.append(TraceItem.from_json(fixture, raw_item))
    return items


def load_policy_sensitive_ids(catalog_path: Optional[Path]) -> Tuple[FrozenSet[str], Optional[str]]:
    """Canonical ids whose catalog `quantity_kind` is one
    `POLICY_SENSITIVE_QUANTITY_KINDS` names.

    Returns `(ids, warning)`. Missing/unreadable catalog is not fatal — the
    `owner == "shared"` and `quantity > 1` criteria still fully apply, this
    only narrows the extra quantity==1-but-policy-governed case — but it is
    reported as a warning so a silent narrowing is never mistaken for "no
    such items exist".
    """
    if catalog_path is None:
        return frozenset(), None
    if not catalog_path.is_file():
        return frozenset(), f"catalog {catalog_path} not found; policy-sensitive-by-catalog-kind check skipped"
    try:
        raw = json.loads(catalog_path.read_text())
    except json.JSONDecodeError as e:
        return frozenset(), f"catalog {catalog_path} invalid JSON ({e}); policy-sensitive-by-catalog-kind check skipped"
    ids = frozenset(
        item["id"]
        for item in raw.get("items", [])
        if isinstance(item, dict) and item.get("quantity_kind") in POLICY_SENSITIVE_QUANTITY_KINDS and "id" in item
    )
    return ids, None


# ---------------------------------------------------------------------------
# Classification
# ---------------------------------------------------------------------------

INCLUSION_BUCKETS = (
    "user_authority",
    "missing_reason_code",
    "missing_signal",
    "generic_only",
    "base_essential",
    "specific",
)
INCLUSION_COMPLETE_BUCKETS = ("base_essential", "specific")
INCLUSION_DEFECT_BUCKETS = ("missing_reason_code", "missing_signal")

QUANTITY_BUCKETS = ("user_authority", "fixed_singleton", "evidence_present", "evidence_missing")


def classify_inclusion(item: TraceItem) -> str:
    if item.is_user_authority:
        return "user_authority"
    if not item.reason_code:
        return "missing_reason_code"
    if not item.signals:
        return "missing_signal"
    if item.reason_code.startswith(BASE_ESSENTIAL_PREFIX):
        return "base_essential"
    if item.reason_code.endswith(GENERIC_REASON_SUFFIX):
        return "generic_only"
    return "specific"


def classify_quantity(item: TraceItem, policy_sensitive_ids: FrozenSet[str]) -> str:
    if item.is_user_authority:
        return "user_authority"
    requires_evidence = (
        item.quantity > 1
        or item.owner == "shared"
        or item.canonical_item_id in policy_sensitive_ids
    )
    if not requires_evidence:
        return "fixed_singleton"
    return "evidence_present" if item.quantity_reason else "evidence_missing"


def is_invalid_seasonal_provenance(item: TraceItem) -> bool:
    """A seasonal-fallback row must never carry the day-count/forecast
    arguments only a precise-forecast reason renders — that would mean
    seasonal copy is claiming forecast-derived specifics it doesn't have.
    Both current seasonal codes (weather.seasonal_sun, weather.seasonal_layer,
    PackingEngine.swift) are always rendered with empty arguments; this is a
    regression guard on that invariant, not a currently-failing check."""
    return item.reason_code.startswith(SEASONAL_REASON_PREFIX) and bool(item.reason_arguments)


def is_fabricated_user_authority_provenance(item: TraceItem) -> bool:
    """A user-authority row (userModified or custom.* id) must carry an
    empty reasonCode/reason/signals — the engine must never invent inclusion
    provenance for the user's own decision. Regression guard; 0 violations
    confirmed at eadc345."""
    return item.is_user_authority and bool(item.reason_code or item.reason or item.signals)


def has_invalid_quantity_reason_argument_keys(item: TraceItem) -> bool:
    """quantityReasonArguments is a closed vocabulary (Task 1) — any key
    outside it means an unreviewed fourth call site started writing this
    field, the same drift ActivityNeed/PackingCapability/WeatherSignal
    already guard against."""
    keys = {k for k, _ in item.quantity_reason_arguments}
    return not keys.issubset(CLOSED_QUANTITY_REASON_ARGUMENT_KEYS)


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------


@dataclass
class Report:
    items: List[TraceItem] = field(default_factory=list)
    inclusion: Dict[str, List[TraceItem]] = field(default_factory=dict)
    quantity: Dict[str, List[TraceItem]] = field(default_factory=dict)
    catalog_warning: Optional[str] = None
    # Phase 8, Task 7: two new structural checks plus the closed-vocabulary
    # guard, each a list of the offending rows (not a bucket dict — these
    # are cross-cutting, not mutually exclusive with the inclusion/quantity
    # classification).
    invalid_seasonal_provenance: List[TraceItem] = field(default_factory=list)
    fabricated_user_authority_provenance: List[TraceItem] = field(default_factory=list)
    invalid_quantity_reason_argument_keys: List[TraceItem] = field(default_factory=list)

    @property
    def total_items(self) -> int:
        return len(self.items)

    @property
    def engine_items(self) -> int:
        return self.total_items - len(self.inclusion.get("user_authority", []))

    @property
    def inclusion_complete_count(self) -> int:
        return sum(len(self.inclusion.get(b, [])) for b in INCLUSION_COMPLETE_BUCKETS)

    @property
    def inclusion_defect_count(self) -> int:
        return sum(len(self.inclusion.get(b, [])) for b in INCLUSION_DEFECT_BUCKETS)

    @property
    def inclusion_completeness_pct(self) -> float:
        if self.engine_items == 0:
            return 100.0
        return 100.0 * self.inclusion_complete_count / self.engine_items

    @property
    def quantity_requires_evidence_count(self) -> int:
        return len(self.quantity.get("evidence_present", [])) + len(self.quantity.get("evidence_missing", []))

    @property
    def quantity_evidence_pct(self) -> float:
        requires = self.quantity_requires_evidence_count
        if requires == 0:
            return 100.0
        return 100.0 * len(self.quantity.get("evidence_present", [])) / requires

    @property
    def is_clean(self) -> bool:
        return (
            self.inclusion_defect_count == 0
            and len(self.quantity.get("evidence_missing", [])) == 0
            and len(self.invalid_seasonal_provenance) == 0
            and len(self.fabricated_user_authority_provenance) == 0
            and len(self.invalid_quantity_reason_argument_keys) == 0
        )


def build_report(items: List[TraceItem], policy_sensitive_ids: FrozenSet[str], catalog_warning: Optional[str]) -> Report:
    inclusion: Dict[str, List[TraceItem]] = {b: [] for b in INCLUSION_BUCKETS}
    quantity: Dict[str, List[TraceItem]] = {b: [] for b in QUANTITY_BUCKETS}
    invalid_seasonal_provenance: List[TraceItem] = []
    fabricated_user_authority_provenance: List[TraceItem] = []
    invalid_quantity_reason_argument_keys: List[TraceItem] = []
    for item in items:
        inclusion[classify_inclusion(item)].append(item)
        quantity[classify_quantity(item, policy_sensitive_ids)].append(item)
        if is_invalid_seasonal_provenance(item):
            invalid_seasonal_provenance.append(item)
        if is_fabricated_user_authority_provenance(item):
            fabricated_user_authority_provenance.append(item)
        if has_invalid_quantity_reason_argument_keys(item):
            invalid_quantity_reason_argument_keys.append(item)
    return Report(
        items=items,
        inclusion=inclusion,
        quantity=quantity,
        catalog_warning=catalog_warning,
        invalid_seasonal_provenance=invalid_seasonal_provenance,
        fabricated_user_authority_provenance=fabricated_user_authority_provenance,
        invalid_quantity_reason_argument_keys=invalid_quantity_reason_argument_keys,
    )


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------


def _fmt_pct(pct: float) -> str:
    return f"{pct:.1f}%"


def render_text(report: Report) -> str:
    lines: List[str] = ["Recommendation trace coverage", "=" * len("Recommendation trace coverage"), ""]
    if report.catalog_warning:
        lines.append(f"warning: {report.catalog_warning}")
        lines.append("")

    lines.append(f"Total item rows: {report.total_items}")
    lines.append(f"  user-authority rows (exempt, not scored): {len(report.inclusion.get('user_authority', []))}")
    lines.append(f"  engine-generated rows (scored): {report.engine_items}")
    lines.append("")

    lines.append("Inclusion completeness (engine-generated rows)")
    lines.append("-----------------------------------------------")
    lines.append(
        f"  complete: {report.inclusion_complete_count}/{report.engine_items} "
        f"({_fmt_pct(report.inclusion_completeness_pct)})"
        f"  [base-essential: {len(report.inclusion['base_essential'])}, specific: {len(report.inclusion['specific'])}]"
    )
    lines.append(f"  generic-only (weak, informational, not folded into the pass/fail metric below): {len(report.inclusion['generic_only'])}")
    lines.append(f"  DEFECTS — missing reason code: {len(report.inclusion['missing_reason_code'])}")
    lines.append(f"  DEFECTS — missing causal signal: {len(report.inclusion['missing_signal'])}")
    lines.append(
        f"  recommendations lacking causal structured provenance: {report.inclusion_defect_count} "
        "(= missing reason code + missing causal signal; refined exit metric, Phase 8)"
    )

    if report.inclusion["missing_reason_code"] or report.inclusion["missing_signal"]:
        lines.append("")
        lines.append("  Defect rows:")
        for item in report.inclusion["missing_reason_code"] + report.inclusion["missing_signal"]:
            lines.append(f"    - {item.label} (reasonCode={item.reason_code!r}, signals={list(item.signals)})")

    if report.inclusion["generic_only"]:
        lines.append("")
        lines.append(f"  Generic-only rows ({len(report.inclusion['generic_only'])}):")
        for item in report.inclusion["generic_only"]:
            lines.append(f"    - {item.label} ({item.reason_code}: {item.reason!r})")

    lines.append("")
    lines.append("Quantity evidence (engine-generated rows)")
    lines.append("------------------------------------------")
    lines.append(f"  fixed singletons (not held to the bar): {len(report.quantity['fixed_singleton'])}")
    lines.append(
        f"  requires evidence (quantity>1, shared, or policy-sensitive): "
        f"{report.quantity_requires_evidence_count}"
    )
    lines.append(
        f"    has evidence: {len(report.quantity['evidence_present'])}/{report.quantity_requires_evidence_count} "
        f"({_fmt_pct(report.quantity_evidence_pct)})"
    )
    lines.append(f"    DEFECTS — missing evidence: {len(report.quantity['evidence_missing'])}")
    if report.quantity["evidence_missing"]:
        lines.append("")
        lines.append("  Defect rows:")
        for item in report.quantity["evidence_missing"]:
            lines.append(
                f"    - {item.label} (quantity={item.quantity}, owner={item.owner}, quantityReason={item.quantity_reason!r})"
            )

    lines.append("")
    lines.append("User-authority rows (exempt — expected empty trace)")
    lines.append("-----------------------------------------------------")
    for item in report.inclusion["user_authority"]:
        lines.append(f"  - {item.label} (userModified={item.user_modified}, quantity={item.quantity})")
    if not report.inclusion["user_authority"]:
        lines.append("  (none)")

    lines.append("")
    lines.append("Structural checks (Phase 8, Task 7)")
    lines.append("------------------------------------")
    lines.append(f"  DEFECTS — invalid seasonal provenance: {len(report.invalid_seasonal_provenance)}")
    if report.invalid_seasonal_provenance:
        for item in report.invalid_seasonal_provenance:
            lines.append(f"    - {item.label} (reasonCode={item.reason_code!r}, reasonArguments={dict(item.reason_arguments)})")
    lines.append(f"  DEFECTS — fabricated user-authority provenance: {len(report.fabricated_user_authority_provenance)}")
    if report.fabricated_user_authority_provenance:
        for item in report.fabricated_user_authority_provenance:
            lines.append(f"    - {item.label} (reasonCode={item.reason_code!r}, reason={item.reason!r}, signals={list(item.signals)})")
    lines.append(f"  DEFECTS — quantityReasonArguments keys outside the closed vocabulary: {len(report.invalid_quantity_reason_argument_keys)}")
    if report.invalid_quantity_reason_argument_keys:
        for item in report.invalid_quantity_reason_argument_keys:
            keys = sorted({k for k, _ in item.quantity_reason_arguments} - CLOSED_QUANTITY_REASON_ARGUMENT_KEYS)
            lines.append(f"    - {item.label} (unlisted keys: {keys})")

    lines.append("")
    lines.append("CLEAN" if report.is_clean else "DEFECTS FOUND")

    return "\n".join(lines)


def render_markdown(report: Report) -> str:
    lines: List[str] = ["# Recommendation trace coverage", ""]
    if report.catalog_warning:
        lines.append(f"> warning: {report.catalog_warning}")
        lines.append("")

    lines.append(
        f"Total item rows: **{report.total_items}** "
        f"({len(report.inclusion['user_authority'])} user-authority / exempt, "
        f"{report.engine_items} engine-generated / scored)."
    )
    lines.append("")

    lines.append("## Inclusion completeness")
    lines.append("")
    lines.append("| bucket | count | of engine-generated rows |")
    lines.append("| --- | --- | --- |")
    lines.append(f"| complete (base-essential) | {len(report.inclusion['base_essential'])} | |")
    lines.append(f"| complete (specific) | {len(report.inclusion['specific'])} | |")
    lines.append(
        f"| **complete total** | **{report.inclusion_complete_count}** | **{_fmt_pct(report.inclusion_completeness_pct)}** |"
    )
    lines.append(f"| generic-only (informational, not folded into the pass/fail metric) | {len(report.inclusion['generic_only'])} | |")
    lines.append(f"| defect — missing reason code | {len(report.inclusion['missing_reason_code'])} | |")
    lines.append(f"| defect — missing causal signal | {len(report.inclusion['missing_signal'])} | |")
    lines.append(
        f"| **recommendations lacking causal structured provenance (refined exit metric)** | **{report.inclusion_defect_count}** | |"
    )

    if report.inclusion["missing_reason_code"] or report.inclusion["missing_signal"]:
        lines.append("")
        lines.append("**Defect rows**")
        lines.append("")
        for item in report.inclusion["missing_reason_code"] + report.inclusion["missing_signal"]:
            lines.append(f"- `{item.label}` (reasonCode=`{item.reason_code}`, signals={list(item.signals)})")

    if report.inclusion["generic_only"]:
        lines.append("")
        lines.append(f"**Generic-only rows ({len(report.inclusion['generic_only'])})**")
        lines.append("")
        for item in report.inclusion["generic_only"]:
            lines.append(f"- `{item.label}` (`{item.reason_code}`: {item.reason!r})")

    lines.append("")
    lines.append("## Quantity evidence")
    lines.append("")
    lines.append("| bucket | count |")
    lines.append("| --- | --- |")
    lines.append(f"| fixed singletons (not held to the bar) | {len(report.quantity['fixed_singleton'])} |")
    lines.append(f"| requires evidence | {report.quantity_requires_evidence_count} |")
    lines.append(
        f"| — has evidence | {len(report.quantity['evidence_present'])} ({_fmt_pct(report.quantity_evidence_pct)}) |"
    )
    lines.append(f"| — defect: missing evidence | {len(report.quantity['evidence_missing'])} |")

    if report.quantity["evidence_missing"]:
        lines.append("")
        lines.append("**Defect rows**")
        lines.append("")
        for item in report.quantity["evidence_missing"]:
            lines.append(
                f"- `{item.label}` (quantity={item.quantity}, owner={item.owner}, quantityReason={item.quantity_reason!r})"
            )

    lines.append("")
    lines.append("## User-authority rows (exempt — expected empty trace)")
    lines.append("")
    if report.inclusion["user_authority"]:
        for item in report.inclusion["user_authority"]:
            lines.append(f"- `{item.label}` (userModified={item.user_modified}, quantity={item.quantity})")
    else:
        lines.append("_none_")

    lines.append("")
    lines.append("## Structural checks (Phase 8, Task 7)")
    lines.append("")
    lines.append("| check | count |")
    lines.append("| --- | --- |")
    lines.append(f"| defect — invalid seasonal provenance | {len(report.invalid_seasonal_provenance)} |")
    lines.append(f"| defect — fabricated user-authority provenance | {len(report.fabricated_user_authority_provenance)} |")
    lines.append(f"| defect — quantityReasonArguments keys outside the closed vocabulary | {len(report.invalid_quantity_reason_argument_keys)} |")

    if report.invalid_seasonal_provenance:
        lines.append("")
        lines.append("**Invalid seasonal provenance rows**")
        lines.append("")
        for item in report.invalid_seasonal_provenance:
            lines.append(f"- `{item.label}` (reasonCode=`{item.reason_code}`, reasonArguments={dict(item.reason_arguments)})")

    if report.fabricated_user_authority_provenance:
        lines.append("")
        lines.append("**Fabricated user-authority provenance rows**")
        lines.append("")
        for item in report.fabricated_user_authority_provenance:
            lines.append(f"- `{item.label}` (reasonCode=`{item.reason_code}`, reason={item.reason!r}, signals={list(item.signals)})")

    if report.invalid_quantity_reason_argument_keys:
        lines.append("")
        lines.append("**Rows with a quantityReasonArguments key outside the closed vocabulary**")
        lines.append("")
        for item in report.invalid_quantity_reason_argument_keys:
            keys = sorted({k for k, _ in item.quantity_reason_arguments} - CLOSED_QUANTITY_REASON_ARGUMENT_KEYS)
            lines.append(f"- `{item.label}` (unlisted keys: {keys})")

    lines.append("")
    lines.append("**CLEAN**" if report.is_clean else "**DEFECTS FOUND**")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def find_repo_root() -> Optional[Path]:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    return Path(result.stdout.strip())


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--goldens",
        help="Directory of golden JSON fixtures (default: ios/PackWiseTests/Goldens under the repo root, "
        "discovered via `git rev-parse --show-toplevel`).",
    )
    parser.add_argument(
        "--catalog",
        help="Path to shared/catalog/clothing.json, used to resolve which quantity==1 clothing rows are "
        "policy-sensitive (default: shared/catalog/clothing.json under the repo root). Pass an empty string "
        "to skip this check entirely (owner==shared and quantity>1 still apply).",
    )
    parser.add_argument(
        "--format",
        choices=("text", "markdown"),
        default="text",
        help="Output format (default: text).",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit 1 when any defect (missing reason code, missing causal signal, or missing required "
        "quantity evidence) is found, instead of the default tool-health-only exit code.",
    )
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    args = build_arg_parser().parse_args(argv)

    repo_root = find_repo_root()

    if args.goldens:
        goldens_dir = Path(args.goldens).resolve()
    elif repo_root is not None:
        goldens_dir = repo_root / "ios" / "PackWiseTests" / "Goldens"
    else:
        print("error: --goldens not given and repo root could not be located via git", file=sys.stderr)
        return 2

    if not goldens_dir.is_dir():
        print(f"error: --goldens {goldens_dir} is not a directory", file=sys.stderr)
        return 2

    if args.catalog == "":
        catalog_path: Optional[Path] = None
    elif args.catalog:
        catalog_path = Path(args.catalog).resolve()
    elif repo_root is not None:
        catalog_path = repo_root / "shared" / "catalog" / "clothing.json"
    else:
        catalog_path = None

    try:
        items = load_items(goldens_dir)
    except TraceLoadError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2

    policy_sensitive_ids, catalog_warning = load_policy_sensitive_ids(catalog_path)

    report = build_report(items, policy_sensitive_ids, catalog_warning)
    render = render_markdown if args.format == "markdown" else render_text
    print(render(report))
    if args.strict and not report.is_clean:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
