#!/usr/bin/env python3
"""Validation for shared/rules/trip-types.json (Product Experience V2, Task 3).

Trip types own closed need IDs, never canonical item IDs. The rules here are
the executable form of design Section 8.1:

  * `tripTypes` lists every known trip type exactly once, in
    `TripType.stableOrder`, and carries no retired item-list keys.
  * `needs` is the closed `PackingNeed` vocabulary, exactly and in Swift order;
    each need is contributed by some trip type and maps to real, unique
    catalog candidates.
  * a trip type's needs, suggestions, and exclusions are known and unique; it
    never both contributes and excludes a need, or suggests and excludes an
    activity; `other` contributes and suggests nothing.

`contract_errors` is pure so tests can break one rule at a time;
`repository_contract_errors` wires it to the checked-in files.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

RETIRED_KEYS = ("add", "prefer_activities")
TYPE_KEYS = ("needs", "suggestedActivities", "excludedNeeds", "excludedActivities")


def _duplicates(values: list[str]) -> list[str]:
    seen: set[str] = set()
    repeated: list[str] = []
    for value in values:
        if value in seen and value not in repeated:
            repeated.append(value)
        seen.add(value)
    return repeated


def contract_errors(
    doc: dict,
    *,
    trip_type_order: list[str],
    need_vocabulary: list[str],
    activity_ids: set[str],
    catalog_ids: set[str],
) -> list[str]:
    errors: list[str] = []
    needs = set(need_vocabulary)

    need_rows = doc.get("needs", [])
    if [row.get("id") for row in need_rows] != need_vocabulary:
        errors.append(f"needs must be exactly {need_vocabulary} in order; found {[row.get('id') for row in need_rows]}")
    for row in need_rows:
        need_id = row.get("id")
        candidates = row.get("candidates", [])
        for unknown in [c for c in candidates if c not in catalog_ids]:
            errors.append(f"need {need_id} has unknown candidate {unknown}")
        for repeated in _duplicates(candidates):
            errors.append(f"need {need_id} repeats candidate {repeated}")
        if not str(row.get("meaning", "")).strip():
            errors.append(f"need {need_id} has no meaning")

    type_rows = doc.get("tripTypes", [])
    ids = [row.get("id") for row in type_rows]
    for repeated in _duplicates(ids):
        errors.append(f"duplicate trip type {repeated}")
    if ids != trip_type_order:
        errors.append(f"trip types must be exactly {trip_type_order} in order; found {ids}")

    contributed: set[str] = set()
    for row in type_rows:
        trip_type = row.get("id")
        for key in RETIRED_KEYS:
            if key in row:
                errors.append(f"trip {trip_type} uses retired key {key}")
        for key in TYPE_KEYS:
            if not isinstance(row.get(key), list):
                errors.append(f"trip {trip_type} {key} must be an array")
        if not str(row.get("nonImplications", "")).strip():
            errors.append(f"trip {trip_type} has no nonImplications")

        own_needs = row.get("needs") or []
        for need in own_needs:
            if need in needs:
                contributed.add(need)
            elif "." in need:
                errors.append(f"trip {trip_type} names canonical item ID {need} where a need ID belongs")
            else:
                errors.append(f"trip {trip_type} has unknown need {need}")
        for repeated in _duplicates(own_needs):
            errors.append(f"trip {trip_type} repeats need {repeated}")

        suggested = row.get("suggestedActivities") or []
        for activity in suggested:
            if activity not in activity_ids:
                errors.append(f"trip {trip_type} has unknown suggested activity {activity}")
        for repeated in _duplicates(suggested):
            errors.append(f"trip {trip_type} repeats suggested activity {repeated}")

        excluded_needs = row.get("excludedNeeds") or []
        for need in excluded_needs:
            if need not in needs:
                errors.append(f"trip {trip_type} has unknown excluded need {need}")
            elif need in own_needs:
                errors.append(f"trip {trip_type} both contributes and excludes need {need}")
        excluded_activities = row.get("excludedActivities") or []
        for activity in excluded_activities:
            if activity not in activity_ids:
                errors.append(f"trip {trip_type} has unknown excluded activity {activity}")
            elif activity in suggested:
                errors.append(f"trip {trip_type} both suggests and excludes activity {activity}")

        if trip_type == "other":
            if own_needs:
                errors.append("trip other must contribute no needs")
            if suggested:
                errors.append("trip other must suggest no activities")

    for need in need_vocabulary:
        if need not in contributed:
            errors.append(f"need {need} is contributed by no trip type")
    return errors


def swift_packing_needs(path: Path) -> list[str]:
    """Case names of `enum PackingNeed` in declaration order ([] if absent)."""
    if not path.exists():
        return []
    match = re.search(r"enum PackingNeed\b[^{]*\{(.*?)\n\}", path.read_text(), re.S)
    if not match:
        return []
    return re.findall(r"^\s*case (\w+)", match.group(1), re.M)


def swift_trip_type_order(path: Path) -> list[str]:
    match = re.search(r"static let stableOrder: \[TripType\] = \[(.*?)\]", path.read_text(), re.S)
    return re.findall(r"\.(\w+)", match.group(1)) if match else []


def repository_contract_errors(root: Path) -> list[str]:
    shared = root / "shared"
    doc = json.loads((shared / "rules" / "trip-types.json").read_text())
    catalog_ids: set[str] = set()
    for path in sorted((shared / "catalog").glob("*.json")):
        catalog_ids.update(item["id"] for item in json.loads(path.read_text())["items"])
    activity_ids = set(json.loads((shared / "rules" / "activity-rules.json").read_text())["activities"])
    domain = root / "ios" / "PackWise" / "Domain"
    return contract_errors(
        doc,
        trip_type_order=swift_trip_type_order(domain / "TripTypes.swift"),
        need_vocabulary=swift_packing_needs(domain / "Packing" / "TripTypeContracts.swift"),
        activity_ids=activity_ids,
        catalog_ids=catalog_ids,
    )
