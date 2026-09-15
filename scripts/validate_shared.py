#!/usr/bin/env python3
"""Referential integrity for shared catalog, rules, and fixtures."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import build_intelligence_schemas
import trip_type_contracts

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


def swift_stable_order(path: Path, name: str) -> list[str] | None:
    """Read `static let stableOrder: [Name] = [.a, .b]` out of a Swift enum extension."""
    match = re.search(rf"static let stableOrder: \[{name}\] = \[(.*?)\]", path.read_text(), re.S)
    if not match:
        return None
    return re.findall(r"\.(\w+)", match.group(1))


RETIRED_CONTEXT_KEYS = ("tripType", "bagType", "bag")


def trip_context_errors(label: str, row: dict) -> list[str]:
    """Current request/eval fixtures carry tripTypes[]/bagTypes[] only.

    Arrays are sets stored in the stable canonical order, so a fixture's bytes
    never depend on how someone happened to type the selection. Legacy V3
    persistence inputs are not fixtures here; they live in the Swift migration
    tests, which deliberately seed the retired scalar columns.
    """
    errors: list[str] = []
    if retired := [key for key in RETIRED_CONTEXT_KEYS if key in row]:
        errors.append(f"{label} uses retired singular context keys {retired}")
    for field, order, minimum in (
        ("tripTypes", build_intelligence_schemas.TRIP_TYPES, 1),
        ("bagTypes", build_intelligence_schemas.BAG_TYPES, 0),
    ):
        values = row.get(field)
        if not isinstance(values, list):
            errors.append(f"{label} {field} must be an array")
            continue
        if len(values) < minimum:
            errors.append(f"{label} {field} needs at least {minimum} value")
        if unknown := [v for v in values if v not in order]:
            errors.append(f"{label} {field} unknown values {unknown}")
        elif len(set(values)) != len(values):
            errors.append(f"{label} {field} repeats a value")
        elif values != [v for v in order if v in values]:
            errors.append(f"{label} {field} not in stable order: {values}")
    return errors


def stale_script_commands() -> list[str]:
    """Canonical instructions may only prescribe `python3 scripts/<name>.py`
    commands that exist in this checkout.

    Scope is the current source of truth: AGENTS.md, READMEs, top-level docs,
    Cursor rules, CI workflows, the API package scripts, and every execution
    plan AGENTS.md names as active. Dated records under docs/plans/ and
    inactive plans are history and may describe tools that live elsewhere.
    """
    agents = ROOT / "AGENTS.md"
    sources = [agents, ROOT / "README.md", ROOT / "api" / "README.md", ROOT / "api" / "package.json"]
    sources += sorted((ROOT / "docs").glob("*.md"))
    sources += sorted((ROOT / ".cursor" / "rules").glob("*.mdc"))
    sources += sorted((ROOT / ".github" / "workflows").glob("*.yml"))
    sources += [ROOT / plan for plan in sorted(set(re.findall(r"docs/superpowers/plans/[\w.-]+\.md", agents.read_text())))]
    stale: list[str] = []
    for source in sources:
        if not source.exists():
            continue
        for name in sorted(set(re.findall(r"python3 (?:\.\./)?scripts/([\w-]+\.py)", source.read_text()))):
            if not (ROOT / "scripts" / name).exists():
                stale.append(f"{source.relative_to(ROOT)} prescribes missing scripts/{name}")
    return stale


def load(path: Path):
    return json.loads(path.read_text())


ELIGIBILITY_FAMILIES = {
    "universal", "adultOrTeen", "ageSpecific", "explicitChildNeed", "phoneOwnership",
    "deviceSignalRequired", "travelerSignalRequired", "travelerDocument",
}
RETIRED_PARTY_KEYS = ("skipForYoungChildren", "skipForInfantsAndToddlers")
# Task 7.2: the implicit primary-phone signal proves a phone and its charger,
# nothing else.
PHONE_OWNERSHIP_ITEMS = {"essentials.phone", "electronics.phone_charger"}
DEVICE_FAMILIES = {"phoneOwnership", "deviceSignalRequired"}


def eligibility_eligible(entry: dict, age: str, needs: set, chips: set) -> bool:
    """Mirror of TravelerEligibilityResolver for rule-consistency checks only.

    Evaluated for a companion traveler on a party list: an age-group rule
    applies to companions, so no primary-traveler or sole-traveler device
    evidence exists here (Task 7.1 — age is never device ownership)."""
    adult_or_teen = age in ("adult", "teen")
    family = entry["family"]
    if family == "universal":
        return True
    if family == "adultOrTeen":
        return adult_or_teen
    if family == "ageSpecific":
        return age in entry["ageGroups"]
    if family == "explicitChildNeed":
        return entry["need"] in needs
    if family == "phoneOwnership":
        return "bringingPhone" in chips
    if family == "deviceSignalRequired":
        return entry.get("signal") is not None and entry["signal"] in chips
    if family == "travelerSignalRequired":
        return entry["signal"] in chips
    if family == "travelerDocument":
        return entry["travelers"] == "all" or adult_or_teen
    return False


def eligibility_errors(party: dict, catalog: set, chip_names: set) -> list:
    """Task 6: every catalog item carries closed eligibility metadata, and the
    age-group rules never contradict it. Missing metadata fails here rather
    than defaulting permissively."""
    errors = []
    for key in RETIRED_PARTY_KEYS:
        if key in party:
            errors.append(f"party.json retired key {key}: eligibility replaces it")
    for age, body in party["ageGroups"].items():
        if "skipAdultClothing" in body:
            errors.append(f"party age {age}: retired skipAdultClothing")
    table = party.get("eligibility")
    if not isinstance(table, dict):
        return errors + ["party.json missing eligibility"]
    for item_id in sorted(catalog - set(table)):
        errors.append(f"eligibility missing for {item_id}")
    for item_id, entry in sorted(table.items()):
        if item_id not in catalog:
            errors.append(f"eligibility for unknown item {item_id}")
        family = entry.get("family")
        if family not in ELIGIBILITY_FAMILIES:
            errors.append(f"eligibility {item_id}: unknown family {family}")
            continue
        allowed = {"family"} | {
            "ageSpecific": {"ageGroups"}, "explicitChildNeed": {"need"},
            "deviceSignalRequired": {"signal"}, "travelerSignalRequired": {"signal"},
            "travelerDocument": {"travelers"},
        }.get(family, set())
        if extra := set(entry) - allowed:
            errors.append(f"eligibility {item_id}: unexpected keys {sorted(extra)}")
        if family == "ageSpecific" and (not entry.get("ageGroups") or set(entry["ageGroups"]) - set(AGE_GROUPS)):
            errors.append(f"eligibility {item_id}: bad ageGroups {entry.get('ageGroups')}")
        if family == "explicitChildNeed" and entry.get("need") not in CHILD_NEEDS:
            errors.append(f"eligibility {item_id}: unknown need {entry.get('need')}")
        if family == "travelerSignalRequired" and entry.get("signal") not in chip_names:
            errors.append(f"eligibility {item_id}: unknown signal {entry.get('signal')}")
        if family == "deviceSignalRequired" and "signal" in entry and entry["signal"] not in chip_names:
            errors.append(f"eligibility {item_id}: unknown signal {entry.get('signal')}")
        if family == "travelerDocument" and entry.get("travelers") not in ("all", "adultOrTeen"):
            errors.append(f"eligibility {item_id}: unknown travelers {entry.get('travelers')}")
        if family == "travelerDocument" and not item_id.startswith("documents."):
            errors.append(f"eligibility {item_id}: travelerDocument outside documents")
    phone_family = {item_id for item_id, entry in table.items() if entry.get("family") == "phoneOwnership"}
    if phone_family != PHONE_OWNERSHIP_ITEMS:
        errors.append(f"eligibility phoneOwnership must be exactly {sorted(PHONE_OWNERSHIP_ITEMS)}, got {sorted(phone_family)}")
    # Device scaling counts resolved device rows, never travelers by age.
    for item_id, rule in party.get("sharingPolicies", {}).items():
        devices = rule.get("devices")
        if rule.get("policy") == "scaleByDevices":
            if not devices:
                errors.append(f"party policy {item_id}: scaleByDevices must declare devices")
            for device in devices or []:
                if table.get(device, {}).get("family") not in DEVICE_FAMILIES:
                    errors.append(f"party policy {item_id}: {device} is not a device-ownership item")
        elif devices is not None:
            errors.append(f"party policy {item_id}: devices only applies to scaleByDevices")
    # Sensitive families must never be classified permissively.
    for item_id in sorted(table):
        if item_id.startswith("kids.") and table[item_id].get("family") in ("universal", "adultOrTeen"):
            errors.append(f"eligibility {item_id}: child item classified {table[item_id]['family']}")
    for item_id in ("health.daily_medication", "toiletries.contacts_solution", "electronics.phone_charger", "electronics.laptop"):
        if table.get(item_id, {}).get("family") in ("universal", "ageSpecific"):
            errors.append(f"eligibility {item_id}: sensitive item classified permissively")
    for item_id in sorted(i for i in catalog if i.startswith("documents.")):
        if table.get(item_id, {}).get("family") == "ageSpecific":
            errors.append(f"eligibility {item_id}: documents are never filtered by category-wide age rules")
    # Age-group rules must agree with the authority.
    for age, body in party["ageGroups"].items():
        for item_id in body.get("add", []):
            if item_id in table and not eligibility_eligible(table[item_id], age, set(), set()):
                errors.append(f"party age {age} adds {item_id} its eligibility forbids")
        for need, refs in body.get("candidates", {}).items():
            for item_id in refs:
                entry = table.get(item_id, {})
                if entry and (eligibility_eligible(entry, age, set(), set()) or not eligibility_eligible(entry, age, {need}, set())):
                    errors.append(f"party candidate {age}.{need} {item_id} does not require exactly that need")
    return errors


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

    # Trip types own typed needs, not item lists (Product Experience V2, Task 3).
    errors.extend(trip_type_contracts.repository_contract_errors(ROOT))

    for signal, refs in load(SHARED / "rules" / "weather.json")["signalAdds"].items():
        if missing := check(f"weather {signal}", refs):
            errors.append(f"weather {signal}: {missing}")

    for need, refs in load(SHARED / "rules" / "substitutions.json")["needs"].items():
        if missing := check(f"need {need}", refs):
            errors.append(f"need {need}: {missing}")

    party = load(SHARED / "rules" / "party.json")
    for label, refs in [
        ("party shared", party["sharedByDefault"]),
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
    device_chips = base.get("traveler_device_chips", {})
    for chip, refs in device_chips.items():
        if chip in base["context_chips"]:
            errors.append(f"traveler device chip {chip} is also a trip context chip")
        if missing := check(f"device chip {chip}", refs):
            errors.append(f"device chip {chip}: {missing}")
    errors.extend(eligibility_errors(party, set(catalog), set(base["context_chips"]) | set(device_chips)))

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
    # Traveler device signals are Swift chips too, but never inference
    # vocabulary (the API cannot infer who owns a device).
    all_chip_names = chip_names | set(base.get("traveler_device_chips", {}))
    if swift_chips and swift_chips != all_chip_names:
        errors.append(
            "ContextChip drift: "
            f"swift-only {sorted(swift_chips - all_chip_names)}, "
            f"rules-only {sorted(all_chip_names - swift_chips)}"
        )

    # Swift's stableOrder is the one canonical-order authority; the API's
    # generated vocabularies mirror it and must not drift in content or order.
    for name, generated in (
        ("TripType", build_intelligence_schemas.TRIP_TYPES),
        ("BagType", build_intelligence_schemas.BAG_TYPES),
    ):
        swift_order = swift_stable_order(IOS / "Domain" / "TripTypes.swift", name)
        if swift_order != generated:
            errors.append(f"{name}.stableOrder drift: swift {swift_order}, generator {generated}")

    for path in sorted((SHARED / "fixtures" / "trips").glob("*.json")):
        trip = load(path)
        errors.extend(trip_context_errors(trip["id"], trip))
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

    for fixture in load(SHARED / "fixtures" / "golden" / "golden-fixtures.json")["fixtures"]:
        errors.extend(trip_context_errors(f"golden {fixture['id']}", fixture))

    combinations = SHARED / "fixtures" / "contexts" / "product-v2-combinations.json"
    if combinations.exists():
        activity_vocabulary = set(build_intelligence_schemas.vocabularies()["activities"])
        for row in load(combinations)["contexts"]:
            context = row["context"]
            errors.extend(trip_context_errors(f"combination {row['id']}", context))
            if context["destination"]["displayName"] not in dest_names:
                errors.append(f"combination {row['id']} unknown destination")
            if unknown := [a for a in context.get("activities", []) if a not in activity_vocabulary]:
                errors.append(f"combination {row['id']} unknown activities {unknown}")
    else:
        errors.append("missing shared/fixtures/contexts/product-v2-combinations.json")

    errors.extend(stale_script_commands())

    if build_intelligence_schemas.main(["--check"]) != 0:
        errors.append("generated intelligence schemas are stale")

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"OK: {len(items)} items, integrity checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
