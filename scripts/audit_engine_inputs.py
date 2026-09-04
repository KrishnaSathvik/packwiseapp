#!/usr/bin/env python3
"""Audit for `docs/engine-audits/surfaced-input-contracts.json`.

Every trip type, bag type, packing style, laundry access value, suggested
activity, and preference/context chip a user can select in `TripSetupView`
ends up as one field on `TripContext` (chips land on `TripContext.contextChips`
or, per-traveler, on `Traveler.chips`). That field either drives the
deterministic engine (`PackingEngine`,
`ClothingQuantityEngine`, `ConstraintResolver`) in some observable way, is
merely stored/descriptive, or — the failure mode this audit exists to catch —
is offered to the user and silently does nothing. `surfaced-input-contracts.json`
records one honest answer per input; this script validates that file's schema
and turns it into a report.

Each record has the shape:

    {
      "kind": "activity",
      "id": "camping",
      "exposed": true,
      "engineContract": "deterministic",
      "fixtureIDs": ["18-reykjavik-64d-roadtrip-camping-seasonal"],
      "testIDs": ["ActivityContractTests.swift::campingAloneAddsItsFourCandidatesAndNoCampsiteLogistics"],
      "iconContract": "tent",
      "ownerScope": "trip"
    }

`testIDs` is optional and every entry is file-qualified as
`<SwiftFile>::<testFunctionName>`. It exists because the real requirement is
"at least one fixture **or** test": eight activities have real code paths that
no golden fixture exercises, and a named, verified test is better evidence
than fixture spam. To keep the field from becoming a way to type a green
audit, each entry is verified against the file it names — a same-named
function in another suite does not satisfy it, so a moved or renamed test
breaks the audit loudly.

`engineContract` is one of:

    deterministic   a real, code-level rule keys off this value and produces
                     an observably different packing list (item, quantity, or
                     constraint decision) for at least one other value of the
                     same kind.
    contextOnly      the value is surfaced and stored but does not
                     independently drive rule-based generation differently —
                     e.g. it is folded into a broader bucket another value
                     already produces identical output for.
    missing          exposed in the UI (or otherwise reachable) but has no
                     deterministic engine effect at all. This is a defect,
                     not a design choice — never relabel one of these
                     `contextOnly` to make the report read clean.

This script does not re-derive `engineContract` from the rule JSON/Swift
source itself — that judgment call is made once, by a person, reading the
rule files (see the `note` field on each record for the reasoning). What it
does check mechanically:

  * schema validity: required fields present and correctly typed, no
    duplicate (kind, id) pairs, `engineContract` is one of the three legal
    values, every record has a non-empty `iconContract`.
  * optionally, that the file's ids for tripType/bagType/packingStyle/
    laundryAccess/contextChip exactly match the real Swift enum cases
    (`--verify-source`, on by default when the repo can be located), and
    that the activity ids are a superset of
    `shared/rules/activity-rules.json`'s keys.

It then buckets every record that passed validation into a report:

    DEAD            engineContract == "missing" — offered to the user,
                     verified to do nothing. Every row here is a defect to
                     route to a later phase. Phase 5 emptied this bucket, and
                     it is expected to stay empty: a row reappearing here is
                     a regression, not a finding to file away.
    CONTEXT-ONLY    engineContract == "contextOnly" — surfaced, stored, but
                     does not independently change engine output. Still never
                     a label to reach for when the real answer is `missing`.
    UNTESTED        engineContract == "deterministic" but neither fixtureIDs
                     nor testIDs is populated — the code path is real, but
                     nothing proves it, so a regression would go unnoticed.

CLI:

    python3 scripts/audit_engine_inputs.py \\
        --contracts docs/engine-audits/surfaced-input-contracts.json
    python3 scripts/audit_engine_inputs.py \\
        --contracts docs/engine-audits/surfaced-input-contracts.json --format markdown

Exit code reflects schema validity only (0 clean, 1 validation errors); a
non-empty DEAD/UNTESTED bucket is a reportable finding, not a validation
failure. Since Phase 5 the remaining UNTESTED rows are the context chips,
which are reported rather than silenced because no phase owns them yet.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

ALLOWED_CONTRACTS = ("deterministic", "contextOnly", "missing")
ALLOWED_KINDS = ("tripType", "bagType", "packingStyle", "laundryAccess", "activity", "contextChip")

_REQUIRED_STRING_FIELDS = ("kind", "id", "engineContract", "iconContract", "ownerScope")

#: `testIDs` entries are file-qualified so a reference resolves to one place.
_TEST_ID_PATTERN = re.compile(r"^(?P<file>[A-Za-z0-9_]+\.swift)::(?P<func>[A-Za-z_][A-Za-z0-9_]*)$")

#: Where `testIDs` files are resolved from, relative to the repo root.
_TESTS_DIR = ("ios", "PackWiseTests")


# ---------------------------------------------------------------------------
# Schema
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class ContractRecord:
    kind: str
    id: str
    exposed: bool
    engine_contract: str
    fixture_ids: Tuple[str, ...]
    icon_contract: str
    owner_scope: str
    note: Optional[str] = None
    #: File-qualified `<SwiftFile>::<testFunctionName>` references.
    test_ids: Tuple[str, ...] = ()

    @property
    def key(self) -> Tuple[str, str]:
        return (self.kind, self.id)

    @staticmethod
    def from_json(raw: dict, index: int) -> Tuple[Optional["ContractRecord"], List[str]]:
        errors: List[str] = []
        for name in _REQUIRED_STRING_FIELDS:
            if not isinstance(raw.get(name), str) or not raw.get(name):
                errors.append(f"record[{index}]: missing or empty required string field {name!r}")
        if "exposed" not in raw or not isinstance(raw.get("exposed"), bool):
            errors.append(f"record[{index}]: missing or non-boolean required field 'exposed'")
        fixture_ids = raw.get("fixtureIDs")
        if fixture_ids is None:
            fixture_ids = []
        if not isinstance(fixture_ids, list) or not all(isinstance(f, str) for f in fixture_ids):
            errors.append(f"record[{index}]: 'fixtureIDs' must be a list of strings")
            fixture_ids = []
        test_ids = raw.get("testIDs")
        if test_ids is None:
            test_ids = []
        if not isinstance(test_ids, list) or not all(isinstance(t, str) for t in test_ids):
            errors.append(f"record[{index}]: 'testIDs' must be a list of strings")
            test_ids = []
        else:
            # File-qualification is enforced at load time so an unqualified
            # name can never be resolved leniently against the whole test
            # directory. The reference must say where the evidence lives.
            for test_id in test_ids:
                if not _TEST_ID_PATTERN.match(test_id):
                    errors.append(
                        f"record[{index}]: testIDs entry {test_id!r} must be "
                        f"'<SwiftFile>.swift::<testFunctionName>'"
                    )
        if errors:
            return None, errors

        record = ContractRecord(
            kind=raw["kind"],
            id=raw["id"],
            exposed=raw["exposed"],
            engine_contract=raw["engineContract"],
            fixture_ids=tuple(fixture_ids),
            icon_contract=raw["iconContract"],
            owner_scope=raw["ownerScope"],
            note=raw.get("note"),
            test_ids=tuple(test_ids),
        )

        if record.kind not in ALLOWED_KINDS:
            errors.append(
                f"record[{index}] ({record.kind}/{record.id}): unknown kind {record.kind!r}; "
                f"expected one of {ALLOWED_KINDS}"
            )
        if record.engine_contract not in ALLOWED_CONTRACTS:
            errors.append(
                f"record[{index}] ({record.kind}/{record.id}): illegal engineContract "
                f"{record.engine_contract!r}; expected one of {ALLOWED_CONTRACTS}"
            )

        return record, errors


class ContractLoadError(Exception):
    """The contracts file could not be parsed at all (bad JSON / bad top-level shape)."""


def load_contracts(path: Path) -> Tuple[List[ContractRecord], List[str]]:
    """Load and schema-validate the contracts file.

    Returns `(records, errors)`. `records` contains every syntactically valid
    record (even ones that fail a semantic check like duplicate-id or
    illegal-contract, so the report can still describe them); `errors`
    collects every schema problem found, including duplicates and missing
    icons, which are checked across the whole file rather than per-record.
    """
    try:
        raw = json.loads(path.read_text())
    except json.JSONDecodeError as e:
        raise ContractLoadError(f"{path}: invalid JSON ({e})") from e
    except OSError as e:
        raise ContractLoadError(f"{path}: {e}") from e

    raw_records = raw.get("records") if isinstance(raw, dict) else None
    if raw_records is None:
        if isinstance(raw, list):
            raw_records = raw
        else:
            raise ContractLoadError(f"{path}: expected a top-level 'records' array")
    if not isinstance(raw_records, list):
        raise ContractLoadError(f"{path}: 'records' must be an array")

    records: List[ContractRecord] = []
    errors: List[str] = []
    for i, raw_record in enumerate(raw_records):
        if not isinstance(raw_record, dict):
            errors.append(f"record[{i}]: expected an object")
            continue
        record, record_errors = ContractRecord.from_json(raw_record, i)
        errors.extend(record_errors)
        if record is not None:
            records.append(record)

    seen: Dict[Tuple[str, str], int] = {}
    for i, record in enumerate(records):
        if record.key in seen:
            errors.append(
                f"record[{i}] ({record.kind}/{record.id}): duplicate of record[{seen[record.key]}] "
                f"— (kind, id) pairs must be unique"
            )
        else:
            seen[record.key] = i

    return records, errors


# ---------------------------------------------------------------------------
# Source-of-truth cross-check
# ---------------------------------------------------------------------------


def swift_enum_cases(path: Path, name: str) -> Set[str]:
    """Read `case foo` names out of a Swift String-backed enum.

    Mirrors `scripts/validate_shared.py`'s helper of the same name so both
    scripts agree on how enum cases are discovered from source.
    """
    body = path.read_text()
    match = re.search(rf"enum {name}: String[^{{]*{{(.*?)\n}}", body, re.S)
    if not match:
        return set()
    return set(re.findall(r"^\s*case (\w+)", match.group(1), re.M))


@dataclass(frozen=True)
class SourceExpectation:
    """The ids a contracts file should have one row per, per kind, as
    discovered directly from the Swift/JSON source rather than hand-copied."""

    trip_types: Set[str]
    bag_types: Set[str]
    packing_styles: Set[str]
    laundry_access: Set[str]
    activities: Set[str]
    # Defaulted (rather than a fifth positional field) so existing call sites
    # that predate ContextChip coverage — including test helpers that build
    # a SourceExpectation by hand — keep working unchanged.
    context_chips: Set[str] = field(default_factory=set)


def discover_expected_ids(repo_root: Path) -> SourceExpectation:
    trip_types_path = repo_root / "ios" / "PackWise" / "Domain" / "TripTypes.swift"
    activity_rules_path = repo_root / "shared" / "rules" / "activity-rules.json"

    trip_types = swift_enum_cases(trip_types_path, "TripType")
    bag_types = swift_enum_cases(trip_types_path, "BagType")
    packing_styles = swift_enum_cases(trip_types_path, "PackingStyle")
    laundry_access = swift_enum_cases(trip_types_path, "LaundryAccess")
    context_chips = swift_enum_cases(trip_types_path, "ContextChip")

    activities: Set[str] = set()
    if activity_rules_path.is_file():
        activities |= set(json.loads(activity_rules_path.read_text()).get("activities", {}).keys())

    return SourceExpectation(
        trip_types=trip_types,
        bag_types=bag_types,
        packing_styles=packing_styles,
        laundry_access=laundry_access,
        activities=activities,
        context_chips=context_chips,
    )


_KIND_TO_EXPECTATION_FIELD = {
    "tripType": "trip_types",
    "bagType": "bag_types",
    "packingStyle": "packing_styles",
    "laundryAccess": "laundry_access",
    "activity": "activities",
    "contextChip": "context_chips",
}


def check_completeness(records: List[ContractRecord], expected: SourceExpectation) -> List[str]:
    """Compare the contracts file's ids against `expected`, per kind.

    Returns one human-readable error per (kind, missing-or-extra id). Extra
    ids (a contract row with no source case, e.g. a typo or a retired case)
    are reported too — the ledger should track exactly the real vocabulary.
    """
    errors: List[str] = []
    present: Dict[str, Set[str]] = {kind: set() for kind in ALLOWED_KINDS}
    for record in records:
        present.setdefault(record.kind, set()).add(record.id)

    for kind, attr in _KIND_TO_EXPECTATION_FIELD.items():
        expected_ids = getattr(expected, attr)
        actual_ids = present.get(kind, set())
        for missing_id in sorted(expected_ids - actual_ids):
            errors.append(f"{kind}/{missing_id}: exists in source but has no contract row")
        for extra_id in sorted(actual_ids - expected_ids):
            errors.append(f"{kind}/{extra_id}: has a contract row but no matching source case")

    return errors


def check_test_references(records: List[ContractRecord], repo_root: Path) -> List[str]:
    """Verify every `testIDs` entry names a real test function in its file.

    Resolution is scoped to the file the entry names, never to the test
    directory as a whole: a same-named function in another suite must not
    satisfy the reference, or the ledger stops saying where the evidence
    actually lives and a moved test silently keeps the audit green.
    """
    errors: List[str] = []
    tests_dir = repo_root.joinpath(*_TESTS_DIR)
    # None means "file does not exist"; a set means "these functions are in it".
    functions_by_file: Dict[str, Optional[Set[str]]] = {}

    def functions_in(file_name: str) -> Optional[Set[str]]:
        if file_name not in functions_by_file:
            path = tests_dir / file_name
            functions_by_file[file_name] = (
                set(re.findall(r"\bfunc\s+(\w+)\s*\(", path.read_text())) if path.is_file() else None
            )
        return functions_by_file[file_name]

    for record in records:
        for test_id in record.test_ids:
            match = _TEST_ID_PATTERN.match(test_id)
            if match is None:
                continue  # already reported as a schema error at load time
            file_name, func_name = match.group("file"), match.group("func")
            functions = functions_in(file_name)
            if functions is None:
                errors.append(
                    f"{record.kind}/{record.id}: testIDs entry {test_id!r} names "
                    f"{file_name!r}, which does not exist under {'/'.join(_TESTS_DIR)}"
                )
            elif func_name not in functions:
                errors.append(
                    f"{record.kind}/{record.id}: testIDs entry {test_id!r} names no "
                    f"'func {func_name}(' in {file_name}"
                )

    return errors


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


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------


@dataclass
class Report:
    records: List[ContractRecord] = field(default_factory=list)

    @property
    def dead(self) -> List[ContractRecord]:
        return [r for r in self.records if r.engine_contract == "missing"]

    @property
    def context_only(self) -> List[ContractRecord]:
        return [r for r in self.records if r.engine_contract == "contextOnly"]

    @property
    def untested(self) -> List[ContractRecord]:
        return [
            r
            for r in self.records
            if r.engine_contract == "deterministic" and not r.fixture_ids and not r.test_ids
        ]

    @property
    def deterministic_and_tested(self) -> List[ContractRecord]:
        return [
            r
            for r in self.records
            if r.engine_contract == "deterministic" and (r.fixture_ids or r.test_ids)
        ]

    def counts(self) -> Dict[str, int]:
        return {
            "total": len(self.records),
            "deterministic (tested)": len(self.deterministic_and_tested),
            "untested": len(self.untested),
            "context-only": len(self.context_only),
            "dead": len(self.dead),
        }


def build_report(records: List[ContractRecord]) -> Report:
    return Report(records=sorted(records, key=lambda r: (r.kind, r.id)))


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

_COUNT_LABELS = ("total", "deterministic (tested)", "untested", "context-only", "dead")


def _describe(record: ContractRecord) -> str:
    fixtures = ", ".join(record.fixture_ids) if record.fixture_ids else "none"
    return f"{record.kind}/{record.id} (icon: {record.icon_contract}, fixtures: {fixtures})"


def render_text(report: Report) -> str:
    lines: List[str] = ["Surfaced-input contract audit", "=" * len("Surfaced-input contract audit"), ""]
    counts = report.counts()
    lines.append("  " + "  ".join(f"{label}: {counts[label]}" for label in _COUNT_LABELS))

    lines.append("")
    lines.append(f"DEAD ({len(report.dead)}) — exposed, verified to do nothing:")
    for r in report.dead:
        lines.append(f"  - {_describe(r)}")
        if r.note:
            lines.append(f"      {r.note}")
    if not report.dead:
        lines.append("  (none)")

    lines.append("")
    lines.append(f"CONTEXT-ONLY ({len(report.context_only)}) — surfaced/stored, no independent engine effect:")
    for r in report.context_only:
        lines.append(f"  - {_describe(r)}")
        if r.note:
            lines.append(f"      {r.note}")
    if not report.context_only:
        lines.append("  (none)")

    lines.append("")
    lines.append(f"UNTESTED ({len(report.untested)}) — deterministic, no golden fixture proves it:")
    for r in report.untested:
        lines.append(f"  - {_describe(r)}")
        if r.note:
            lines.append(f"      {r.note}")
    if not report.untested:
        lines.append("  (none)")

    return "\n".join(lines)


def render_markdown(report: Report) -> str:
    lines: List[str] = ["# Surfaced-input contract audit", ""]
    counts = report.counts()
    lines.append("| " + " | ".join(_COUNT_LABELS) + " |")
    lines.append("| " + " | ".join(["---"] * len(_COUNT_LABELS)) + " |")
    lines.append("| " + " | ".join(str(counts[label]) for label in _COUNT_LABELS) + " |")

    def section(title: str, records: List[ContractRecord]) -> None:
        lines.append("")
        lines.append(f"## {title} ({len(records)})")
        if not records:
            lines.append("")
            lines.append("_none_")
            return
        lines.append("")
        lines.append("| kind | id | icon | fixtures |")
        lines.append("| --- | --- | --- | --- |")
        for r in records:
            fixtures = ", ".join(f"`{f}`" for f in r.fixture_ids) if r.fixture_ids else "_none_"
            lines.append(f"| {r.kind} | `{r.id}` | `{r.icon_contract}` | {fixtures} |")
            if r.note:
                lines.append(f"| | | | {r.note} |")

    section("Dead — exposed, verified to do nothing", report.dead)
    section("Context-only — surfaced/stored, no independent engine effect", report.context_only)
    section("Untested — deterministic, no golden fixture proves it", report.untested)

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--contracts",
        required=True,
        help="Path to the surfaced-input contracts JSON file "
        "(docs/engine-audits/surfaced-input-contracts.json).",
    )
    parser.add_argument(
        "--format",
        choices=("text", "markdown"),
        default="text",
        help="Output format (default: text).",
    )
    verify_group = parser.add_mutually_exclusive_group()
    verify_group.add_argument(
        "--verify-source",
        dest="verify_source",
        action="store_true",
        default=None,
        help="Cross-check contract ids against the real TripType/BagType/PackingStyle/"
        "LaundryAccess Swift enums and shared/rules/activity-rules.json. On by default "
        "when the repo root can be located via git; pass this explicitly to fail loudly "
        "if it cannot be.",
    )
    verify_group.add_argument(
        "--no-verify-source",
        dest="verify_source",
        action="store_false",
        help="Skip the source cross-check even if the repo root can be located.",
    )
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    args = build_arg_parser().parse_args(argv)

    contracts_path = Path(args.contracts).resolve()
    try:
        records, errors = load_contracts(contracts_path)
    except ContractLoadError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2

    if args.verify_source is not False:
        repo_root = find_repo_root()
        if repo_root is None:
            if args.verify_source is True:
                print("error: --verify-source requested but repo root could not be located via git", file=sys.stderr)
                return 2
        else:
            expected = discover_expected_ids(repo_root)
            errors.extend(check_completeness(records, expected))
            # A fabricated or relocated test reference fails schema
            # validation rather than quietly greening the UNTESTED bucket.
            errors.extend(check_test_references(records, repo_root))

    if errors:
        print(f"Schema validation failed for {contracts_path} ({len(errors)} error(s)):", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1

    report = build_report(records)
    render = render_markdown if args.format == "markdown" else render_text
    print(render(report))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
