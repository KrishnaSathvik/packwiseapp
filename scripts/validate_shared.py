#!/usr/bin/env python3
"""Referential integrity for shared catalog, rules, and fixtures."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import build_intelligence_schemas

ROOT = Path(__file__).resolve().parents[1]
SHARED = ROOT / "shared"
IOS = ROOT / "ios" / "PackWise"

TRAVELER_ROLES = {"self", "partner", "child", "otherAdult"}
AGE_GROUPS = {"adult", "teen", "child", "toddler", "infant"}
TRAVEL_MODES = {"solo", "couple", "family", "group"}
CHILD_NEEDS = {
    "diapers",
    "formula",
    "pacifier",
    "stroller",
    "carrier",
    "carSeat",
    "medication",
    "comfortItem",
}


def swift_enum_cases(path: Path, name: str) -> set[str]:
    """Read `case foo` names out of a Swift String-backed enum."""
    body = path.read_text()
    match = re.search(rf"enum {name}: String[^{{]*{{(.*?)\n}}", body, re.S)
    if not match:
        return set()
    return set(re.findall(r"^\s*case (\w+)", match.group(1), re.M))


def load(path: Path):
    return json.loads(path.read_text())


def main() -> int:
    items = []
    for path in sorted((SHARED / "catalog").glob("*.json")):
        items.extend(load(path)["items"])
    ids = [item["id"] for item in items]
    if len(ids) != len(set(ids)):
        print("duplicate catalog IDs", file=sys.stderr)
        return 1
    catalog = {item["id"]: item for item in items}
    quantity_kinds = set(load(SHARED / "rules" / "quantities.json")["policies"])

    def check(label: str, refs: list[str]) -> list[str]:
        return [item_id for item_id in refs if item_id not in catalog]

    errors: list[str] = []
    base = load(SHARED / "rules" / "base.json")
    for label, refs in [
        ("base", base["base_essentials"]),
        ("international", base["international_adds"]),
    ]:
        if missing := check(label, refs):
            errors.append(f"{label}: {missing}")
    for chip, refs in base["context_chips"].items():
        if missing := check(f"chip {chip}", refs):
            errors.append(f"chip {chip}: {missing}")

    activities = load(SHARED / "rules" / "activity-rules.json")["activities"]
    for activity, refs in activities.items():
        if missing := check(f"activity {activity}", refs):
            errors.append(f"activity {activity}: {missing}")

    for trip_type, body in load(SHARED / "rules" / "trip-types.json")["trip_types"].items():
        if missing := check(f"trip {trip_type}", body["add"]):
            errors.append(f"trip {trip_type}: {missing}")

    for signal, refs in load(SHARED / "rules" / "weather.json")["signalAdds"].items():
        if missing := check(f"weather {signal}", refs):
            errors.append(f"weather {signal}: {missing}")

    for need, refs in load(SHARED / "rules" / "substitutions.json")["needs"].items():
        if missing := check(f"need {need}", refs):
            errors.append(f"need {need}: {missing}")

    party = load(SHARED / "rules" / "party.json")
    for label, refs in [
        ("party shared", party["sharedByDefault"]),
        ("party skip", party["skipForYoungChildren"]),
    ]:
        if missing := check(label, refs):
            errors.append(f"{label}: {missing}")
    for age, body in party["ageGroups"].items():
        if missing := check(f"party age {age}", body.get("add", [])):
            errors.append(f"party age {age}: {missing}")
        for need, refs in body.get("candidates", {}).items():
            if missing := check(f"party candidate {age}.{need}", refs):
                errors.append(f"party candidate {age}.{need}: {missing}")
    for activity, refs in party.get("activityAdds", {}).items():
        if missing := check(f"party activity {activity}", refs):
            errors.append(f"party activity {activity}: {missing}")
    for item_id in party.get("sharingPolicies", {}):
        if item_id not in catalog:
            errors.append(f"party policy unknown {item_id}")

    for item in items:
        if item["quantity_kind"] not in quantity_kinds:
            errors.append(f"quantity_kind {item['quantity_kind']} on {item['id']}")
        for companion in item.get("companions", []):
            if companion not in catalog:
                errors.append(f"companion {companion} missing for {item['id']}")

    dest_names = {row["displayName"] for row in load(SHARED / "fixtures" / "test-destinations.json")["destinations"]}
    weather_ids = set(load(SHARED / "fixtures" / "weather" / "named-fixtures.json")["fixtures"])
    chip_names = set(base["context_chips"])
    activity_names = set(activities)
    inference_vocabulary = chip_names | activity_names

    swift_chips = swift_enum_cases(IOS / "Domain" / "TripTypes.swift", "ContextChip")
    if swift_chips and swift_chips != chip_names:
        errors.append(
            "ContextChip drift: "
            f"swift-only {sorted(swift_chips - chip_names)}, "
            f"rules-only {sorted(chip_names - swift_chips)}"
        )

    for path in sorted((SHARED / "fixtures" / "trips").glob("*.json")):
        trip = load(path)
        if trip["destinationFixture"] not in dest_names:
            errors.append(f"{trip['id']} unknown destination")
        if (fixture := trip.get("weatherFixture")) and fixture not in weather_ids:
            errors.append(f"{trip['id']} unknown weather {fixture}")
        if missing := check(trip["id"], trip.get("mustInclude", []) + trip.get("mustNotInclude", [])):
            errors.append(f"{trip['id']} refs: {missing}")
        if missing := check(trip["id"], trip.get("allowedSuggestions", [])):
            errors.append(f"{trip['id']} allowedSuggestions: {missing}")
        for field in ("mustInfer", "mustNotInfer"):
            unknown = [v for v in trip.get(field, []) if v not in inference_vocabulary]
            if unknown:
                errors.append(f"{trip['id']} {field} outside chip/activity vocabulary: {unknown}")
        if trip.get("mustInfer") and not trip.get("note"):
            errors.append(f"{trip['id']} declares mustInfer without a note to interpret")
        overlap = set(trip.get("mustInfer", [])) & set(trip.get("mustNotInfer", []))
        if overlap:
            errors.append(f"{trip['id']} mustInfer and mustNotInfer overlap: {sorted(overlap)}")
        if party := trip.get("party"):
            if party.get("travelMode") not in TRAVEL_MODES:
                errors.append(f"{trip['id']} unknown travelMode {party.get('travelMode')}")
            for traveler in party.get("travelers", []):
                if traveler.get("role") not in TRAVELER_ROLES:
                    errors.append(f"{trip['id']} unknown traveler role {traveler.get('role')}")
                if traveler.get("ageGroup") not in AGE_GROUPS:
                    errors.append(f"{trip['id']} unknown ageGroup {traveler.get('ageGroup')}")
                if unknown := [n for n in traveler.get("needs", []) if n not in CHILD_NEEDS]:
                    errors.append(f"{trip['id']} unknown child needs {unknown}")

    if build_intelligence_schemas.main(["--check"]) != 0:
        errors.append("generated intelligence schemas are stale")

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"OK: {len(items)} items, integrity checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
