#!/usr/bin/env python3
"""Semantic diff for the PackWise engine golden fixtures.

`ios/PackWiseTests/Goldens/*.json` is a regression ledger, not truth — a
byte-diff on those files makes every reordering and every trace-only change
look identical to a real recommendation regression. This is the structural
comparator: it decodes each golden the way `GoldenEngineTests.swift`
serializes it, matches items across baseline and candidate by
`(owner, canonicalItemID)`, and classifies every difference into one of:

    UNCHANGED           item present, identical, in both
    ADDED               item present only in the candidate
    REMOVED             item present only in the baseline
    QUANTITY CHANGES    the `quantity` number itself differs
    TRACE CHANGES       any other field differs (carrier, category,
                         importance, signals, reason code/arguments/copy,
                         quantity reason, userModified) — evidence for *why*
                         an item is recommended, not *whether* or *how many*
    COVERAGE CHANGES    the fixture's `coverage` suppression ledger differs
    ELIGIBILITY CHANGES the fixture's `eligibility` ledger (candidates a
                         traveler did not receive, with result and reason)
                         differs
    CONSTRAINT CHANGES  the fixture's `constraints` ledger differs, or its
                         one normalized `luggage` decision (capacity,
                         selected bags) differs

Quantity and trace are independent axes: an item can appear in both lists
at once if both changed. Fixtures present in only one side are reported as
NEW FIXTURES / REMOVED FIXTURES rather than diffed item-by-item.

CLI:

    python3 scripts/report_engine_goldens.py \\
        --baseline-ref HEAD --candidate ios/PackWiseTests/Goldens

    python3 scripts/report_engine_goldens.py \\
        --baseline-dir /tmp/baseline --candidate /tmp/candidate --format markdown

`--baseline-ref` never touches the working tree: it reads the candidate
directory's path at that ref via `git ls-tree` / `git show`.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from collections import namedtuple
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# ---------------------------------------------------------------------------
# Schema — mirrors GoldenItem/GoldenCoverageEntry/GoldenConstraintEntry/
# GoldenOutput in ios/PackWiseTests/GoldenEngineTests.swift field-for-field.
# ---------------------------------------------------------------------------

ItemKey = Tuple[str, str]  # (owner, canonicalItemID)

# Fields compared for a matched item, beyond identity (owner + canonicalItemID)
# and quantity. A change to any of these alone is a TRACE CHANGE.
_TRACE_FIELDS = (
    "carrier",
    "display_name",
    "category",
    "importance",
    "signals",
    "reason_code",
    "reason_arguments",
    "reason",
    "quantity_reason",
    "quantity_evidence",
    "provenance",
    "user_modified",
)

_TRACE_FIELD_JSON_NAMES = {
    "carrier": "carrier",
    "display_name": "displayName",
    "category": "category",
    "importance": "importance",
    "signals": "signals",
    "reason_code": "reasonCode",
    "reason_arguments": "reasonArguments",
    "reason": "reason",
    "quantity_reason": "quantityReason",
    "quantity_evidence": "quantityEvidence",
    "provenance": "provenance",
    "user_modified": "userModified",
}


@dataclass(frozen=True)
class GoldenItem:
    owner: str
    carrier: str
    canonical_item_id: str
    display_name: str
    category: str
    quantity: int
    importance: str
    signals: Tuple[str, ...]
    reason_code: str
    reason_arguments: Tuple[Tuple[str, str], ...]
    reason: str
    quantity_reason: str
    quantity_evidence: Optional[str]
    # Canonical JSON of the structured provenance facts (Product Experience
    # V2, Task 4). Absent in goldens recorded before provenance existed.
    provenance: Optional[str]
    user_modified: object

    @property
    def key(self) -> ItemKey:
        return (self.owner, self.canonical_item_id)

    @staticmethod
    def from_json(raw: dict) -> "GoldenItem":
        return GoldenItem(
            owner=raw["owner"],
            carrier=raw["carrier"],
            canonical_item_id=raw["canonicalItemID"],
            display_name=raw["displayName"],
            category=raw["category"],
            quantity=raw["quantity"],
            importance=raw["importance"],
            signals=tuple(raw.get("signals", [])),
            reason_code=raw.get("reasonCode", ""),
            reason_arguments=tuple(sorted((raw.get("reasonArguments") or {}).items())),
            reason=raw.get("reason", ""),
            quantity_reason=raw.get("quantityReason", ""),
            quantity_evidence=(
                json.dumps(raw["quantityEvidence"], sort_keys=True, separators=(",", ":"))
                if raw.get("quantityEvidence") is not None
                else None
            ),
            provenance=(
                json.dumps(raw["provenance"], sort_keys=True, separators=(",", ":"))
                if "provenance" in raw
                else None
            ),
            user_modified=raw.get("userModified"),
        )


@dataclass(frozen=True)
class CoverageEntry:
    owner: str
    suppressed: str
    capabilities: Tuple[str, ...]
    covered_by: Tuple[str, ...]
    covered_capabilities: Tuple[Tuple[str, str], ...]
    refuted_capabilities: Tuple[str, ...]

    @property
    def key(self) -> ItemKey:
        return (self.owner, self.suppressed)

    @staticmethod
    def from_json(raw: dict) -> "CoverageEntry":
        return CoverageEntry(
            owner=raw["owner"],
            suppressed=raw["suppressed"],
            capabilities=tuple(raw.get("capabilities", [])),
            covered_by=tuple(raw.get("coveredBy", [])),
            covered_capabilities=tuple(sorted((raw.get("coveredCapabilities") or {}).items())),
            refuted_capabilities=tuple(sorted(raw.get("refutedCapabilities") or [])),
        )

    def describe(self) -> str:
        covered_by = ", ".join(self.covered_by) if self.covered_by else "nothing"
        exact = ", ".join(f"{capability} -> {item}" for capability, item in self.covered_capabilities)
        refuted = ", ".join(self.refuted_capabilities)
        details = []
        if exact:
            details.append(f"exact [{exact}]")
        if refuted:
            details.append(f"refuted [{refuted}]")
        suffix = f"; {'; '.join(details)}" if details else ""
        return f"suppresses [{', '.join(self.capabilities)}], covered by {covered_by}{suffix}"


@dataclass(frozen=True)
class ConstraintEntry:
    owner: str
    constraint: str
    summary: str
    items: Tuple[str, ...]
    # The luggage decision behind the trim (Product Experience V2, Task 5).
    # None/() in goldens recorded before that evidence existed.
    capacity: Optional[str] = None
    selected_bags: Tuple[str, ...] = ()

    @property
    def key(self) -> ItemKey:
        return (self.owner, self.constraint)

    @staticmethod
    def from_json(raw: dict) -> "ConstraintEntry":
        return ConstraintEntry(
            owner=raw["owner"],
            constraint=raw["constraint"],
            summary=raw["summary"],
            items=tuple(raw.get("items", [])),
            capacity=raw.get("capacity"),
            selected_bags=tuple(raw.get("selectedBags", [])),
        )

    def without_luggage_evidence(self) -> "ConstraintEntry":
        return ConstraintEntry(self.owner, self.constraint, self.summary, self.items)

    def describe(self) -> str:
        luggage = f" under {self.capacity} [{', '.join(self.selected_bags)}]" if self.capacity else ""
        return f'"{self.summary}" removed [{", ".join(self.items)}]{luggage}'


@dataclass(frozen=True)
class EligibilityEntry:
    owner: str
    result: str
    reason: str
    items: Tuple[str, ...]

    @property
    def key(self) -> Tuple[str, str, str]:
        return (self.owner, self.result, self.reason)

    @staticmethod
    def from_json(raw: dict) -> "EligibilityEntry":
        return EligibilityEntry(
            owner=raw["owner"], result=raw["result"], reason=raw["reason"], items=tuple(raw.get("items", []))
        )


EligibilityChange = namedtuple("EligibilityChange", "kind owner reason added removed")


def _compare_eligibility(
    baseline: Tuple[EligibilityEntry, ...], candidate: Tuple[EligibilityEntry, ...]
) -> List["EligibilityChange"]:
    baseline_map = {e.key: e for e in baseline}
    candidate_map = {e.key: e for e in candidate}
    changes = []
    for key in sorted(set(baseline_map) | set(candidate_map)):
        before = set(baseline_map[key].items) if key in baseline_map else set()
        after = set(candidate_map[key].items) if key in candidate_map else set()
        if before != after:
            kind = "added" if not before else "removed" if not after else "changed"
            changes.append(EligibilityChange(kind, key[0], f"{key[1]}:{key[2]}", sorted(after - before), sorted(before - after)))
    return changes


@dataclass(frozen=True)
class LuggageDecision:
    capacity: str
    selected_bags: Tuple[str, ...]
    applies_capacity_constraint: bool

    @staticmethod
    def from_json(raw: Optional[dict]) -> Optional["LuggageDecision"]:
        if raw is None:
            return None
        return LuggageDecision(
            capacity=raw["capacity"],
            selected_bags=tuple(raw.get("selectedBags", [])),
            applies_capacity_constraint=bool(raw.get("appliesCapacityConstraint", False)),
        )

    def describe(self) -> str:
        return f"{self.capacity} [{', '.join(self.selected_bags)}]"


@dataclass(frozen=True)
class Golden:
    fixture: str
    items: Tuple[GoldenItem, ...]
    coverage: Tuple[CoverageEntry, ...]
    constraints: Tuple[ConstraintEntry, ...]
    luggage: Optional[LuggageDecision] = None
    eligibility: Tuple[EligibilityEntry, ...] = ()

    @staticmethod
    def from_json(raw: dict) -> "Golden":
        return Golden(
            fixture=raw.get("fixture", ""),
            items=tuple(GoldenItem.from_json(i) for i in raw.get("items", [])),
            coverage=tuple(CoverageEntry.from_json(c) for c in (raw.get("coverage") or [])),
            constraints=tuple(ConstraintEntry.from_json(c) for c in (raw.get("constraints") or [])),
            luggage=LuggageDecision.from_json(raw.get("luggage")),
            eligibility=tuple(EligibilityEntry.from_json(e) for e in (raw.get("eligibility") or [])),
        )


# ---------------------------------------------------------------------------
# Change records
# ---------------------------------------------------------------------------

AddedItem = namedtuple("AddedItem", "owner canonical_item_id quantity")
RemovedItem = namedtuple("RemovedItem", "owner canonical_item_id quantity")
QuantityChange = namedtuple("QuantityChange", "owner canonical_item_id baseline_quantity candidate_quantity")
TraceChange = namedtuple("TraceChange", "owner canonical_item_id changed_fields")
LedgerChange = namedtuple("LedgerChange", "kind owner suppressed detail")  # coverage
ConstraintChange = namedtuple("ConstraintChange", "kind owner constraint detail")


@dataclass
class FixtureReport:
    fixture: str
    unchanged: List[ItemKey] = field(default_factory=list)
    added: List[AddedItem] = field(default_factory=list)
    removed: List[RemovedItem] = field(default_factory=list)
    quantity_changes: List[QuantityChange] = field(default_factory=list)
    trace_changes: List[TraceChange] = field(default_factory=list)
    coverage_changes: List[LedgerChange] = field(default_factory=list)
    constraint_changes: List[ConstraintChange] = field(default_factory=list)
    eligibility_changes: List["EligibilityChange"] = field(default_factory=list)

    @property
    def is_unchanged(self) -> bool:
        return not (
            self.added
            or self.removed
            or self.quantity_changes
            or self.trace_changes
            or self.coverage_changes
            or self.constraint_changes
            or self.eligibility_changes
        )

    def counts(self) -> Dict[str, int]:
        return {
            "UNCHANGED": len(self.unchanged),
            "ADDED": len(self.added),
            "REMOVED": len(self.removed),
            "QUANTITY CHANGES": len(self.quantity_changes),
            "TRACE CHANGES": len(self.trace_changes),
            "COVERAGE CHANGES": len(self.coverage_changes),
            "CONSTRAINT CHANGES": len(self.constraint_changes),
            "ELIGIBILITY CHANGES": len(self.eligibility_changes),
        }


@dataclass
class Report:
    fixtures: List[FixtureReport] = field(default_factory=list)
    new_fixtures: List[str] = field(default_factory=list)
    removed_fixtures: List[str] = field(default_factory=list)

    @property
    def unchanged_fixture_count(self) -> int:
        return sum(1 for f in self.fixtures if f.is_unchanged)

    @property
    def is_clean(self) -> bool:
        return (
            not self.new_fixtures
            and not self.removed_fixtures
            and all(f.is_unchanged for f in self.fixtures)
        )

    def totals(self) -> Dict[str, int]:
        totals = {
            "UNCHANGED": 0,
            "ADDED": 0,
            "REMOVED": 0,
            "QUANTITY CHANGES": 0,
            "TRACE CHANGES": 0,
            "COVERAGE CHANGES": 0,
            "CONSTRAINT CHANGES": 0,
            "ELIGIBILITY CHANGES": 0,
        }
        for f in self.fixtures:
            for label, count in f.counts().items():
                totals[label] += count
        totals["UNCHANGED FIXTURES"] = self.unchanged_fixture_count
        totals["NEW FIXTURES"] = len(self.new_fixtures)
        totals["REMOVED FIXTURES"] = len(self.removed_fixtures)
        return totals


# ---------------------------------------------------------------------------
# Comparison
# ---------------------------------------------------------------------------


def _changed_trace_fields(
    baseline: GoldenItem, candidate: GoldenItem, ignored: Tuple[str, ...] = ()
) -> Tuple[str, ...]:
    changed = []
    for attr in _TRACE_FIELDS:
        if _TRACE_FIELD_JSON_NAMES[attr] in ignored:
            continue
        if getattr(baseline, attr) != getattr(candidate, attr):
            changed.append(_TRACE_FIELD_JSON_NAMES[attr])
    return tuple(changed)


def _compare_coverage(baseline: Tuple[CoverageEntry, ...], candidate: Tuple[CoverageEntry, ...]) -> List[LedgerChange]:
    baseline_map = {c.key: c for c in baseline}
    candidate_map = {c.key: c for c in candidate}
    changes: List[LedgerChange] = []
    for key, c_entry in candidate_map.items():
        b_entry = baseline_map.get(key)
        if b_entry is None:
            changes.append(LedgerChange("added", key[0], key[1], c_entry.describe()))
        elif b_entry != c_entry:
            changes.append(LedgerChange("changed", key[0], key[1], f"{b_entry.describe()} -> {c_entry.describe()}"))
    for key, b_entry in baseline_map.items():
        if key not in candidate_map:
            changes.append(LedgerChange("removed", key[0], key[1], b_entry.describe()))
    return sorted(changes, key=lambda c: (c.owner, c.suppressed, c.kind))


def _compare_constraints(
    baseline: Tuple[ConstraintEntry, ...],
    candidate: Tuple[ConstraintEntry, ...],
    baseline_luggage: Optional[LuggageDecision] = None,
    candidate_luggage: Optional[LuggageDecision] = None,
    ignore_luggage_evidence: bool = False,
) -> List[ConstraintChange]:
    if ignore_luggage_evidence:
        baseline = tuple(c.without_luggage_evidence() for c in baseline)
        candidate = tuple(c.without_luggage_evidence() for c in candidate)
    baseline_map = {c.key: c for c in baseline}
    candidate_map = {c.key: c for c in candidate}
    changes: List[ConstraintChange] = []
    if not ignore_luggage_evidence and baseline_luggage != candidate_luggage:
        before = baseline_luggage.describe() if baseline_luggage else "not recorded"
        after = candidate_luggage.describe() if candidate_luggage else "not recorded"
        changes.append(ConstraintChange("luggage", "trip", "luggage", f"{before} -> {after}"))
    for key, c_entry in candidate_map.items():
        b_entry = baseline_map.get(key)
        if b_entry is None:
            changes.append(ConstraintChange("added", key[0], key[1], c_entry.describe()))
        elif b_entry != c_entry:
            changes.append(ConstraintChange("changed", key[0], key[1], f"{b_entry.describe()} -> {c_entry.describe()}"))
    for key, b_entry in baseline_map.items():
        if key not in candidate_map:
            changes.append(ConstraintChange("removed", key[0], key[1], b_entry.describe()))
    return sorted(changes, key=lambda c: (c.owner, c.constraint, c.kind))


def compare_fixture(
    baseline_raw: dict,
    candidate_raw: dict,
    ignored_trace_fields: Tuple[str, ...] = (),
    ignore_luggage_evidence: bool = False,
) -> FixtureReport:
    """Compare one fixture's baseline and candidate golden JSON (already
    `json.load`-ed dicts, in the exact shape `GoldenEngineTests.swift`
    writes)."""
    baseline = Golden.from_json(baseline_raw)
    candidate = Golden.from_json(candidate_raw)

    baseline_items = {i.key: i for i in baseline.items}
    candidate_items = {i.key: i for i in candidate.items}

    unchanged: List[ItemKey] = []
    added: List[AddedItem] = []
    quantity_changes: List[QuantityChange] = []
    trace_changes: List[TraceChange] = []

    for key, c_item in candidate_items.items():
        b_item = baseline_items.get(key)
        if b_item is None:
            added.append(AddedItem(key[0], key[1], c_item.quantity))
            continue
        quantity_changed = b_item.quantity != c_item.quantity
        changed_fields = _changed_trace_fields(b_item, c_item, ignored_trace_fields)
        if quantity_changed:
            quantity_changes.append(QuantityChange(key[0], key[1], b_item.quantity, c_item.quantity))
        if changed_fields:
            trace_changes.append(TraceChange(key[0], key[1], changed_fields))
        if not quantity_changed and not changed_fields:
            unchanged.append(key)

    removed: List[RemovedItem] = [
        RemovedItem(key[0], key[1], b_item.quantity)
        for key, b_item in baseline_items.items()
        if key not in candidate_items
    ]

    fixture_id = candidate.fixture or baseline.fixture
    return FixtureReport(
        fixture=fixture_id,
        unchanged=sorted(unchanged),
        added=sorted(added),
        removed=sorted(removed),
        quantity_changes=sorted(quantity_changes),
        trace_changes=sorted(trace_changes),
        coverage_changes=_compare_coverage(baseline.coverage, candidate.coverage),
        constraint_changes=_compare_constraints(
            baseline.constraints, candidate.constraints, baseline.luggage, candidate.luggage, ignore_luggage_evidence
        ),
        eligibility_changes=_compare_eligibility(baseline.eligibility, candidate.eligibility),
    )


def compare_directories(
    baseline: Dict[str, dict],
    candidate: Dict[str, dict],
    ignored_trace_fields: Tuple[str, ...] = (),
    ignore_luggage_evidence: bool = False,
) -> Report:
    """Compare two `{fixture_id: golden_json_dict}` maps, e.g. as loaded by
    `load_golden_dir` / `load_golden_git_ref`."""
    common = sorted(set(baseline) & set(candidate))
    fixtures = [
        compare_fixture(baseline[fid], candidate[fid], ignored_trace_fields, ignore_luggage_evidence) for fid in common
    ]
    return Report(
        fixtures=fixtures,
        new_fixtures=sorted(set(candidate) - set(baseline)),
        removed_fixtures=sorted(set(baseline) - set(candidate)),
    )


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------


class GoldenLoadError(Exception):
    """A golden file or git ref could not be loaded cleanly.

    `main()` catches this and prints a friendly `error: ...` message
    (exit 2) instead of letting the underlying traceback (JSONDecodeError,
    CalledProcessError) reach the caller.
    """


def _git_error_detail(error: subprocess.CalledProcessError) -> str:
    stderr = (error.stderr or "").strip()
    return stderr if stderr else str(error)


def load_golden_dir(directory: Path) -> Dict[str, dict]:
    """Read every `*.json` golden file directly from a directory on disk."""
    result: Dict[str, dict] = {}
    for path in sorted(directory.glob("*.json")):
        try:
            result[path.stem] = json.loads(path.read_text())
        except json.JSONDecodeError as e:
            raise GoldenLoadError(f"{path}: invalid JSON ({e})") from e
    return result


def load_golden_git_ref(ref: str, rel_dir: Path, repo_root: Path) -> Dict[str, dict]:
    """Read every `*.json` golden file at `rel_dir` as it existed at `ref`,
    without touching the working tree (`git ls-tree` + `git show`)."""
    try:
        listing = subprocess.run(
            ["git", "ls-tree", "-r", "--name-only", ref, "--", str(rel_dir)],
            cwd=repo_root,
            capture_output=True,
            text=True,
            check=True,
        ).stdout.splitlines()
    except subprocess.CalledProcessError as e:
        raise GoldenLoadError(f"{ref}: {_git_error_detail(e)}") from e
    result: Dict[str, dict] = {}
    for rel_path in listing:
        if not rel_path.endswith(".json"):
            continue
        try:
            content = subprocess.run(
                ["git", "show", f"{ref}:{rel_path}"],
                cwd=repo_root,
                capture_output=True,
                text=True,
                check=True,
            ).stdout
        except subprocess.CalledProcessError as e:
            raise GoldenLoadError(f"{ref}: {_git_error_detail(e)}") from e
        try:
            result[Path(rel_path).stem] = json.loads(content)
        except json.JSONDecodeError as e:
            raise GoldenLoadError(f"{ref}:{rel_path}: invalid JSON ({e})") from e
    return result


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

_SUMMARY_LABELS = (
    "UNCHANGED",
    "ADDED",
    "REMOVED",
    "QUANTITY CHANGES",
    "TRACE CHANGES",
    "COVERAGE CHANGES",
    "CONSTRAINT CHANGES",
    "ELIGIBILITY CHANGES",
)


def render_text(report: Report) -> str:
    lines: List[str] = ["Engine golden diff", "=" * len("Engine golden diff")]

    for f in report.fixtures:
        lines.append("")
        lines.append(f"[{f.fixture}]" + ("  (unchanged)" if f.is_unchanged else ""))
        counts = f.counts()
        lines.append("  " + "  ".join(f"{label}: {counts[label]}" for label in _SUMMARY_LABELS))
        for a in f.added:
            lines.append(f"    + {a.owner}/{a.canonical_item_id} (qty {a.quantity})")
        for r in f.removed:
            lines.append(f"    - {r.owner}/{r.canonical_item_id} (qty {r.quantity})")
        for q in f.quantity_changes:
            lines.append(f"    ~ {q.owner}/{q.canonical_item_id}: quantity {q.baseline_quantity} -> {q.candidate_quantity}")
        for t in f.trace_changes:
            lines.append(f"    ~ {t.owner}/{t.canonical_item_id}: {', '.join(t.changed_fields)}")
        for c in f.coverage_changes:
            lines.append(f"    coverage {c.kind}: {c.owner}/{c.suppressed} ({c.detail})")
        for c in f.constraint_changes:
            lines.append(f"    constraint {c.kind}: {c.owner}/{c.constraint} ({c.detail})")
        for e in f.eligibility_changes:
            lines.append(f"    eligibility {e.kind}: {e.owner}/{e.reason} +{e.added} -{e.removed}")

    if report.new_fixtures:
        lines.append("")
        lines.append(f"NEW FIXTURES ({len(report.new_fixtures)}):")
        for fid in report.new_fixtures:
            lines.append(f"  + {fid}")

    if report.removed_fixtures:
        lines.append("")
        lines.append(f"REMOVED FIXTURES ({len(report.removed_fixtures)}):")
        for fid in report.removed_fixtures:
            lines.append(f"  - {fid}")

    lines.append("")
    lines.append("Overall")
    lines.append("-------")
    totals = report.totals()
    lines.append(f"Fixtures compared: {len(report.fixtures)} ({totals['UNCHANGED FIXTURES']} unchanged)")
    lines.append("  " + "  ".join(f"{label}: {totals[label]}" for label in _SUMMARY_LABELS))
    if totals["NEW FIXTURES"] or totals["REMOVED FIXTURES"]:
        lines.append(f"  NEW FIXTURES: {totals['NEW FIXTURES']}  REMOVED FIXTURES: {totals['REMOVED FIXTURES']}")
    lines.append("CLEAN" if report.is_clean else "CHANGES FOUND")

    return "\n".join(lines)


def render_markdown(report: Report) -> str:
    lines: List[str] = ["# Engine golden diff", ""]

    lines.append("## Summary")
    lines.append("")
    totals = report.totals()
    header = ["Fixture"] + [label for label in _SUMMARY_LABELS]
    lines.append("| " + " | ".join(header) + " |")
    lines.append("| " + " | ".join(["---"] * len(header)) + " |")
    for f in report.fixtures:
        counts = f.counts()
        row = [f.fixture] + [str(counts[label]) for label in _SUMMARY_LABELS]
        lines.append("| " + " | ".join(row) + " |")
    total_row = ["**Total**"] + [f"**{totals[label]}**" for label in _SUMMARY_LABELS]
    lines.append("| " + " | ".join(total_row) + " |")
    lines.append("")
    lines.append(
        f"Fixtures compared: {len(report.fixtures)} ({totals['UNCHANGED FIXTURES']} unchanged). "
        f"New fixtures: {totals['NEW FIXTURES']}. Removed fixtures: {totals['REMOVED FIXTURES']}. "
        + ("**CLEAN**" if report.is_clean else "**CHANGES FOUND**")
    )

    for f in report.fixtures:
        if f.is_unchanged:
            continue
        lines.append("")
        lines.append(f"## {f.fixture}")
        if f.added:
            lines.append("")
            lines.append("**ADDED**")
            for a in f.added:
                lines.append(f"- `{a.owner}/{a.canonical_item_id}` (qty {a.quantity})")
        if f.removed:
            lines.append("")
            lines.append("**REMOVED**")
            for r in f.removed:
                lines.append(f"- `{r.owner}/{r.canonical_item_id}` (qty {r.quantity})")
        if f.quantity_changes:
            lines.append("")
            lines.append("**QUANTITY CHANGES**")
            for q in f.quantity_changes:
                lines.append(f"- `{q.owner}/{q.canonical_item_id}`: {q.baseline_quantity} -> {q.candidate_quantity}")
        if f.trace_changes:
            lines.append("")
            lines.append("**TRACE CHANGES**")
            for t in f.trace_changes:
                lines.append(f"- `{t.owner}/{t.canonical_item_id}`: {', '.join(t.changed_fields)}")
        if f.coverage_changes:
            lines.append("")
            lines.append("**COVERAGE CHANGES**")
            for c in f.coverage_changes:
                lines.append(f"- {c.kind}: `{c.owner}/{c.suppressed}` ({c.detail})")
        if f.constraint_changes:
            lines.append("")
            lines.append("**CONSTRAINT CHANGES**")
            for c in f.constraint_changes:
                lines.append(f"- {c.kind}: `{c.owner}/{c.constraint}` ({c.detail})")
        if f.eligibility_changes:
            lines.append("")
            lines.append("**ELIGIBILITY CHANGES**")
            for e in f.eligibility_changes:
                lines.append(f"- {e.kind}: `{e.owner}/{e.reason}` added {e.added} removed {e.removed}")

    if report.new_fixtures:
        lines.append("")
        lines.append("## New fixtures")
        for fid in report.new_fixtures:
            lines.append(f"- `{fid}`")

    if report.removed_fixtures:
        lines.append("")
        lines.append("## Removed fixtures")
        for fid in report.removed_fixtures:
            lines.append(f"- `{fid}`")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    baseline_group = parser.add_mutually_exclusive_group(required=True)
    baseline_group.add_argument(
        "--baseline-ref",
        help="Git ref to read the baseline golden files from (e.g. HEAD). "
        "Reads --candidate's path at that ref via `git show`; never touches the working tree.",
    )
    baseline_group.add_argument(
        "--baseline-dir",
        help="Directory of baseline golden JSON files, read directly from disk.",
    )
    parser.add_argument(
        "--candidate",
        required=True,
        help="Directory of candidate golden JSON files on disk (typically ios/PackWiseTests/Goldens).",
    )
    parser.add_argument(
        "--ignore-trace-field",
        action="append",
        default=[],
        choices=sorted(_TRACE_FIELD_JSON_NAMES.values()),
        help="Leave one trace field out of the comparison (repeatable). For comparing against "
        "a baseline recorded before that field existed; say so in any report that uses it.",
    )
    parser.add_argument(
        "--ignore-luggage-evidence",
        action="store_true",
        help="Leave the luggage decision (the golden `luggage` block and each constraint's capacity/"
        "selectedBags) out of the comparison. For comparing against a baseline recorded before "
        "Product Experience V2 Task 5's luggage evidence; say so in any report that uses it.",
    )
    parser.add_argument(
        "--format",
        choices=("text", "markdown"),
        default="text",
        help="Output format (default: text).",
    )
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    args = build_arg_parser().parse_args(argv)

    candidate_dir = Path(args.candidate).resolve()
    if not candidate_dir.is_dir():
        print(f"error: --candidate {candidate_dir} is not a directory", file=sys.stderr)
        return 2

    try:
        candidate = load_golden_dir(candidate_dir)

        if args.baseline_dir:
            baseline_dir = Path(args.baseline_dir).resolve()
            if not baseline_dir.is_dir():
                print(f"error: --baseline-dir {baseline_dir} is not a directory", file=sys.stderr)
                return 2
            baseline = load_golden_dir(baseline_dir)
        else:
            repo_root = Path(
                subprocess.run(
                    ["git", "rev-parse", "--show-toplevel"],
                    capture_output=True,
                    text=True,
                    check=True,
                ).stdout.strip()
            )
            try:
                rel_dir = candidate_dir.relative_to(repo_root)
            except ValueError:
                print(
                    f"error: --candidate {candidate_dir} is outside repo {repo_root}; "
                    "--baseline-ref needs a repo-relative path",
                    file=sys.stderr,
                )
                return 2
            baseline = load_golden_git_ref(args.baseline_ref, rel_dir, repo_root)
    except GoldenLoadError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2

    report = compare_directories(baseline, candidate, tuple(args.ignore_trace_field), args.ignore_luggage_evidence)
    render = render_markdown if args.format == "markdown" else render_text
    print(render(report))
    return 0 if report.is_clean else 1


if __name__ == "__main__":
    raise SystemExit(main())
