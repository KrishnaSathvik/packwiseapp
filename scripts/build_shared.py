#!/usr/bin/env python3
"""Bootstrap/migrate shared config into the versioned JSON layout.

Source of truth after this run is the JSON under shared/. This script may be
used to regenerate fixtures and to validate integrity. Catalog edits should
happen in the JSON files, not here.
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHARED = ROOT / "shared"
OLD_CATALOG = SHARED / "fixtures" / "packing-catalog.json"
OLD_RULES = SHARED / "fixtures" / "packing-rules.json"
OLD_DEST = SHARED / "fixtures" / "destinations.json"
OLD_WEATHER = SHARED / "fixtures" / "weather-fixtures.json"

WATER_OLD = {"essentials.water_bottle_everyday", "activities.water_bottle"}
WATER_NEW = "hydration.water_bottle"
EMPTY_BOTTLE_OLD = "travel_comfort.water_empty"
EMPTY_BOTTLE_NEW = "travel_comfort.empty_security_bottle"


def write(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")


def rewrite_id(item_id: str) -> str:
    if item_id in WATER_OLD:
        return WATER_NEW
    if item_id == EMPTY_BOTTLE_OLD:
        return EMPTY_BOTTLE_NEW
    return item_id


def rewrite_ids(ids: list[str]) -> list[str]:
    out: list[str] = []
    seen: set[str] = set()
    for raw in ids:
        item_id = rewrite_id(raw)
        if item_id not in seen:
            seen.add(item_id)
            out.append(item_id)
    return out


def capabilities_for(item: dict) -> list[str]:
    item_id = item["id"]
    tags = item.get("tags", [])
    caps: list[str] = []
    mapping = {
        "footwear.walking_shoes": ["walking", "casual"],
        "footwear.running_shoes": ["walking", "running", "casual"],
        "footwear.hiking_shoes": ["hiking", "walking", "outdoor"],
        "electronics.headphones": ["audio"],
        "electronics.earbuds_case": ["audio"],
        "clothing.rain_jacket": ["rain", "shell"],
        "clothing.windbreaker": ["wind", "shell"],
        WATER_NEW: ["hydration", "everyday", "hiking", "outdoor"],
        EMPTY_BOTTLE_NEW: ["hydration", "flight"],
        "clothing.nice_outfit": ["dinner", "smart_casual"],
        "clothing.formal_outfit": ["formal"],
        "footwear.sandals": ["beach", "hot"],
        "footwear.flip_flops": ["swim", "wet"],
        "essentials.snacks": ["snacks"],
        "travel_comfort.snacks_flight": ["snacks", "flight"],
        "miscellaneous.car_snacks": ["snacks", "road_trip"],
    }
    caps.extend(mapping.get(item_id, []))
    for tag in tags:
        if tag not in caps:
            caps.append(tag)
    return caps


def companions_for(item_id: str) -> list[str]:
    return {
        "electronics.laptop": ["electronics.laptop_charger"],
        "electronics.camera": ["electronics.camera_charger"],
        "toiletries.contacts_solution": ["toiletries.contact_case"],
        "health.daily_medication": ["health.prescription_copy"],
    }.get(item_id, [])


def restricted(item_id: str, tags: list[str]) -> bool:
    return item_id == "miscellaneous.multi_tool" or "sharp" in tags


def transform_item(raw: dict) -> dict:
    item_id = rewrite_id(raw["id"])
    category = "essentials" if item_id == WATER_NEW else raw["category"]
    display = "Water bottle" if item_id == WATER_NEW else raw["display_name"]
    if item_id == EMPTY_BOTTLE_NEW:
        display = "Empty security bottle"
    keywords = list(raw.get("keywords", []))
    if item_id == WATER_NEW:
        for extra in ["water bottle", "hydroflask", "hydration"]:
            if extra not in keywords:
                keywords.append(extra)
    return {
        "id": item_id,
        "localizationKey": f"packing.{item_id}",
        "display_name": display,
        "category": category,
        "importance": raw["importance"],
        "symbol": raw.get("symbol", "suitcase"),
        "keywords": keywords,
        "quantity_kind": raw.get("quantity_kind", "one"),
        "tags": raw.get("tags", []),
        "capabilities": capabilities_for({**raw, "id": item_id}),
        "companions": companions_for(item_id),
        "travelRestrictionReviewRequired": restricted(item_id, raw.get("tags", [])),
    }


def split_catalog(items: list[dict]) -> None:
    buckets: dict[str, list[dict]] = {}
    seen: set[str] = set()
    for raw in items:
        item = transform_item(raw)
        if item["id"] in seen:
            continue
        seen.add(item["id"])
        buckets.setdefault(item["category"], []).append(item)

    names = {
        "essentials": "essentials.json",
        "documents": "documents.json",
        "clothing": "clothing.json",
        "footwear": "footwear.json",
        "toiletries": "toiletries.json",
        "electronics": "electronics.json",
        "health": "health.json",
        "activities": "activities.json",
        "travel_comfort": "travel-comfort.json",
        "miscellaneous": "miscellaneous.json",
    }
    for category, filename in names.items():
        write(
            SHARED / "catalog" / filename,
            {"version": 1, "category": category, "items": buckets.get(category, [])},
        )


def write_rules(old: dict) -> None:
    write(
        SHARED / "rules" / "base.json",
        {
            "base_essentials": rewrite_ids(old["base_essentials"]),
            "international_adds": rewrite_ids(old["international_adds"]),
            "context_chips": {k: rewrite_ids(v) for k, v in old["context_chips"].items()},
            "free_text_keywords": old["free_text_keywords"],
        },
    )
    write(
        SHARED / "rules" / "trip-types.json",
        {
            "trip_types": {
                key: {"add": rewrite_ids(value.get("add", [])), "prefer_activities": value.get("prefer_activities", [])}
                for key, value in old["trip_types"].items()
            }
        },
    )
    write(
        SHARED / "rules" / "activities.json",
        {"activities": {key: rewrite_ids(ids) for key, ids in old["activities"].items()}},
    )

    weather = old["weather"]
    write(
        SHARED / "rules" / "weather.json",
        {
            "thresholds": {
                "rain_probability_add": weather["rain_probability_add"],
                "cool_evening_max_f": weather["cool_evening_max_f"],
                "cold_max_f": weather["cold_max_f"],
                "hot_min_f": weather["hot_min_f"],
                "uv_add": weather["uv_add"],
                "wind_mph_add": weather["wind_mph_add"],
                "temperature_swing_add": 20,
                "heavy_rain_probability": 0.6,
            },
            "signalAdds": {
                "meaningfulRain": rewrite_ids(weather["rain_adds"]),
                "persistentRain": rewrite_ids(weather["rain_adds"]),
                "coldRain": rewrite_ids(weather["rain_adds"] + ["clothing.light_sweater"]),
                "snowExposure": rewrite_ids(weather["snow_adds"]),
                "coldEvenings": rewrite_ids(weather["cool_evening_adds"]),
                "hotOutdoorExposure": rewrite_ids(weather["hot_adds"]),
                "highUVExposure": rewrite_ids(weather["uv_adds"]),
                "highWindExposure": rewrite_ids(weather["wind_adds"]),
                "largeTemperatureSwing": ["clothing.light_sweater", "clothing.light_jacket"],
            },
        },
    )

    write(
        SHARED / "rules" / "quantities.json",
        {
            "policies": {
                "one": {"kind": "fixed", "value": 1},
                "daily_top": {
                    "kind": "style_factor",
                    "light": {"factor": 0.65, "min": 2, "no_laundry_minus": 1},
                    "balanced": {"factor": 0.75, "min": 3, "no_laundry_use_days": True},
                    "prepared": {"factor": 1.0, "min": 4, "no_laundry_plus": 1, "laundry_minus": 1},
                },
                "daily_underwear": {
                    "kind": "style_days",
                    "light": {"laundry_use": "days_capped_6", "no_laundry_use": "days"},
                    "balanced": {"plus": 1, "laundry_plus": 0},
                    "prepared": {"plus": 2},
                },
                "daily_socks": {"kind": "alias", "alias": "daily_underwear"},
                "bottoms": {"kind": "reuse_interval", "light": 3.0, "balanced": 2.5, "prepared": 2.0, "min": 1},
                "hot_bottoms": {"kind": "reuse_interval", "light": 3.0, "balanced": 2.5, "prepared": 2.0, "min": 1},
                "layer": {"kind": "style_fixed", "light": 1, "balanced": 1, "prepared": 2},
                "sleepwear": {"kind": "long_trip_backup", "threshold_days": 6},
                "workout_top": {"kind": "workout", "light_divisor": 3, "balanced_divisor": 2},
                "workout_bottom": {"kind": "alias", "alias": "workout_top"},
                "formal_top": {"kind": "style_fixed", "light": 1, "balanced": 1, "prepared": 2},
                "dresses": {"kind": "reuse_interval", "light": 4.0, "balanced": 4.0, "prepared": 3.0, "min": 1},
            }
        },
    )

    write(
        SHARED / "rules" / "substitutions.json",
        {
            "needs": {
                "walking": ["footwear.walking_shoes", "footwear.running_shoes", "footwear.hiking_shoes"],
                "running": ["footwear.running_shoes"],
                "hiking": ["footwear.hiking_shoes"],
                "audio": ["electronics.headphones", "electronics.earbuds_case"],
                "hydration": [WATER_NEW],
            },
            "preferSingleWhen": {
                "walking": {
                    "ifActivity": "running",
                    "keep": "footwear.running_shoes",
                    "reasonCode": "substitution.running_covers_walking",
                },
                "walkingHiking": {
                    "ifActivity": "hiking",
                    "unlessActivity": "running",
                    "keep": "footwear.hiking_shoes",
                    "drop": "footwear.walking_shoes",
                    "reasonCode": "substitution.hiking_covers_walking",
                },
            },
        },
    )

    write(
        SHARED / "rules" / "reasons.json",
        {
            "templates": {
                "base.essential": "A core item for almost every trip.",
                "trip_type.generic": "Suggested for a {tripType} trip.",
                "activity.hiking": "Hiking is on your plans.",
                "activity.running": "You plan to run.",
                "activity.sightseeing": "You'll have sightseeing days in {destination}.",
                "activity.generic": "Based on what you'll be doing.",
                "weather.rain_days": "Rain is expected on {rainDays} of your {tripDays} travel days.",
                "weather.rain_weekday": "Rain is expected {weekday}.",
                "weather.temperature_swing": "Temperatures may drop more than {swing}° between afternoon and evening.",
                "weather.cold": "Cold temperatures are expected.",
                "weather.cool_evenings": "Evenings look cool.",
                "weather.hot": "Hot weather is expected.",
                "weather.uv": "Sun exposure looks high.",
                "weather.wind": "It looks windy at your destination.",
                "weather.snow": "Snow is expected during your trip.",
                "weather.seasonal_layer": "Seasonal conditions suggest a warmer layer. The forecast will refine this closer to departure.",
                "weather.seasonal_sun": "Seasonal sun is likely. The forecast will refine this closer to departure.",
                "destination.international": "You're traveling internationally. Check the entry requirements that apply to you.",
                "documents.visa_check": "Check the entry requirements that apply to you.",
                "preference.generic": "Based on how you travel.",
                "substitution.running_covers_walking": "Running shoes can also cover your walking and sightseeing days.",
                "substitution.hiking_covers_walking": "Hiking shoes can cover most walking days on this trip.",
                "quantity.daily_top": "You're traveling for {days} days{styleClause}{laundryClause}.",
                "flight.empty_bottle": "Useful after airport security.",
            }
        },
    )


def write_eval_fixtures() -> None:
    trips = [
        {
            "id": "ChicagoCityRainy5Day",
            "destinationFixture": "Chicago",
            "weatherFixture": "ChicagoRainyFall",
            "days": 5,
            "tripType": "cityBreak",
            "activities": ["sightseeing", "walking"],
            "bag": "carryOn",
            "style": "balanced",
            "homeCountryCode": "US",
            "homeCountrySource": "userConfirmed",
            "mustInclude": ["clothing.rain_jacket", "footwear.walking_shoes", "essentials.wallet"],
            "mustNotInclude": ["clothing.winter_coat"],
            "expectedQuantityRanges": {"clothing.underwear": [5, 6]},
        },
        {
            "id": "MiamiBeachCarryOn",
            "destinationFixture": "Miami",
            "weatherFixture": "MiamiHotBeach",
            "days": 6,
            "tripType": "beach",
            "activities": ["swimming", "beachDays"],
            "bag": "carryOn",
            "style": "light",
            "chips": ["laundryAvailable"],
            "homeCountryCode": "US",
            "homeCountrySource": "userConfirmed",
            "mustInclude": ["clothing.swimsuit", "toiletries.sunscreen"],
            "mustNotInclude": ["clothing.winter_coat"],
            "expectedQuantityRanges": {"clothing.tshirt": [4, 4]},
        },
        {
            "id": "DenverOutdoorCold",
            "destinationFixture": "Denver",
            "weatherFixture": "DenverColdOutdoor",
            "days": 5,
            "tripType": "outdoor",
            "activities": ["hiking"],
            "bag": "notSure",
            "style": "balanced",
            "homeCountryCode": "US",
            "homeCountrySource": "userConfirmed",
            "mustInclude": ["footwear.hiking_shoes", "activities.daypack", WATER_NEW, "clothing.winter_coat"],
            "mustNotInclude": ["clothing.swimsuit"],
        },
        {
            "id": "TokyoInternationalWalking",
            "destinationFixture": "Tokyo",
            "weatherFixture": "TokyoMildSpring",
            "days": 6,
            "tripType": "cityBreak",
            "activities": ["sightseeing", "walking"],
            "bag": "carryOn",
            "style": "balanced",
            "homeCountryCode": "US",
            "homeCountrySource": "userConfirmed",
            "mustInclude": ["documents.passport", "electronics.travel_adapter", "footwear.walking_shoes"],
            "mustNotInclude": ["clothing.winter_coat"],
        },
        {
            "id": "ReykjavikPhotography",
            "destinationFixture": "Reykjavik",
            "weatherFixture": "ReykjavikColdWindy",
            "days": 5,
            "tripType": "outdoor",
            "activities": ["photography", "sightseeing"],
            "bag": "checked",
            "style": "prepared",
            "homeCountryCode": "US",
            "homeCountrySource": "userConfirmed",
            "mustInclude": ["electronics.camera", "electronics.camera_charger", "clothing.windbreaker"],
            "mustNotInclude": [],
        },
        {
            "id": "BusinessTrip3Day",
            "destinationFixture": "Chicago",
            "weatherFixture": "ChicagoRainyFall",
            "days": 3,
            "tripType": "business",
            "activities": ["work"],
            "bag": "carryOn",
            "style": "balanced",
            "homeCountryCode": "US",
            "homeCountrySource": "userConfirmed",
            "mustInclude": ["clothing.dress_shirt", "footwear.dress_shoes", "electronics.laptop", "electronics.laptop_charger"],
            "mustNotInclude": ["clothing.swimsuit"],
        },
        {
            "id": "WeddingWeekend",
            "destinationFixture": "Chicago",
            "days": 3,
            "tripType": "weddingEvent",
            "activities": ["niceDinner"],
            "bag": "carryOn",
            "style": "balanced",
            "homeCountryCode": "US",
            "homeCountrySource": "userConfirmed",
            "mustInclude": ["clothing.formal_outfit", "footwear.dress_shoes"],
            "mustNotInclude": ["clothing.winter_coat"],
        },
        {
            "id": "OverrideKeepsRainJacketDeleted",
            "destinationFixture": "Chicago",
            "weatherFixture": "ChicagoRainyFall",
            "days": 5,
            "tripType": "cityBreak",
            "activities": ["sightseeing"],
            "bag": "carryOn",
            "style": "balanced",
            "homeCountryCode": "US",
            "homeCountrySource": "userConfirmed",
            "overrides": [{"canonicalItemID": "clothing.rain_jacket", "action": "removed"}],
            "mustInclude": [],
            "mustNotInclude": ["clothing.rain_jacket"],
        },
        {
            "id": "PreserveManualQuantity",
            "destinationFixture": "Chicago",
            "days": 6,
            "tripType": "cityBreak",
            "activities": ["sightseeing"],
            "bag": "carryOn",
            "style": "light",
            "chips": ["laundryAvailable"],
            "homeCountryCode": "US",
            "homeCountrySource": "userConfirmed",
            "existing": [
                {
                    "canonicalItemID": "clothing.tshirt",
                    "displayName": "T-shirts",
                    "category": "clothing",
                    "quantity": 3,
                    "isUserModified": True,
                }
            ],
            "mustInclude": ["clothing.tshirt"],
            "expectedExactQuantities": {"clothing.tshirt": 3},
        },
        {
            "id": "OneDayNoWeather",
            "destinationFixture": "Chicago",
            "days": 1,
            "tripType": "cityBreak",
            "activities": [],
            "bag": "notSure",
            "style": "balanced",
            "homeCountryCode": "US",
            "homeCountrySource": "userConfirmed",
            "mustInclude": ["essentials.wallet", "essentials.phone"],
            "mustNotInclude": ["clothing.winter_coat"],
        },
    ]
    for trip in trips:
        write(SHARED / "fixtures" / "trips" / f"{trip['id']}.json", trip)


def write_schemas() -> None:
    item = {
        "type": "object",
        "required": [
            "id",
            "localizationKey",
            "display_name",
            "category",
            "importance",
            "quantity_kind",
        ],
        "properties": {
            "id": {"type": "string"},
            "localizationKey": {"type": "string"},
            "display_name": {"type": "string"},
            "category": {"type": "string"},
            "importance": {"enum": ["critical", "important", "normal", "optional"]},
            "symbol": {"type": "string"},
            "keywords": {"type": "array", "items": {"type": "string"}},
            "quantity_kind": {"type": "string"},
            "tags": {"type": "array", "items": {"type": "string"}},
            "capabilities": {"type": "array", "items": {"type": "string"}},
            "companions": {"type": "array", "items": {"type": "string"}},
            "travelRestrictionReviewRequired": {"type": "boolean"},
        },
    }
    write(SHARED / "schemas" / "catalog-item.schema.json", item)
    write(
        SHARED / "schemas" / "packing-catalog.schema.json",
        {
            "type": "object",
            "required": ["version", "items"],
            "properties": {
                "version": {"type": "integer"},
                "category": {"type": "string"},
                "items": {"type": "array", "items": item},
            },
        },
    )
    write(
        SHARED / "schemas" / "packing-rules.schema.json",
        {"type": "object", "additionalProperties": True},
    )
    write(
        SHARED / "schemas" / "weather-fixtures.schema.json",
        {"type": "object", "required": ["version", "fixtures"]},
    )
    write(
        SHARED / "schemas" / "test-destination.schema.json",
        {"type": "object", "required": ["version", "destinations"]},
    )
    write(
        SHARED / "schemas" / "trip-eval.schema.json",
        {
            "type": "object",
            "required": ["id", "destinationFixture", "mustInclude", "mustNotInclude"],
            "properties": {
                "id": {"type": "string"},
                "mustInclude": {"type": "array", "items": {"type": "string"}},
                "mustNotInclude": {"type": "array", "items": {"type": "string"}},
            },
        },
    )


def write_openapi() -> None:
    path = SHARED / "contracts" / "intelligence-api.yaml"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        """openapi: 3.1.0
info:
  title: PackWise Intelligence API
  version: 0.1.0
  description: >
    Explicit product capabilities. No /chat endpoint.
    GPT-5.6 via Structured Outputs. Model IDs come from server env
    PACKWISE_MODEL_CONTEXT / GAPS / OPTIMIZE.
servers:
  - url: http://localhost:3000
  - url: https://api.packwise.app
security:
  - AppAttest: []
paths:
  /v1/challenge:
    post:
      summary: App Attest one-time challenge
      operationId: createAttestChallenge
      responses:
        "200":
          description: Challenge
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/ChallengeResponse"
  /v1/attest:
    post:
      summary: Register an App Attest attestation
      operationId: registerAttestation
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/AttestationRequest"
      responses:
        "204":
          description: Accepted
        "401":
          $ref: "#/components/responses/Unauthorized"
  /v1/trip/interpret:
    post:
      summary: Natural language to structured trip context
      operationId: interpretTrip
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/InterpretTripRequest"
      responses:
        "200":
          description: Structured enrichment
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/InterpretTripResponse"
        "429":
          $ref: "#/components/responses/RateLimited"
        "503":
          $ref: "#/components/responses/Unavailable"
  /v1/trip/context:
    post:
      summary: Trip context to contextual signals
      operationId: recommendContext
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/TripContextRequest"
      responses:
        "200":
          description: Contextual signals
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/ContextualSignalsResponse"
  /v1/packing/gaps:
    post:
      summary: Find likely missing items
      operationId: findPackingGaps
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/PackingGapsRequest"
      responses:
        "200":
          description: Gap suggestions
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/PackingGapResponse"
  /v1/packing/optimize:
    post:
      summary: Suggest reductions and overlaps
      operationId: optimizePacking
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/PackingOptimizeRequest"
      responses:
        "200":
          description: Optimizations
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/PackingOptimizationResponse"
  /v1/trip/ask:
    post:
      summary: Contextual trip question
      operationId: askPackWise
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/AskRequest"
      responses:
        "200":
          description: Answer
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/AskResponse"
components:
  securitySchemes:
    AppAttest:
      type: apiKey
      in: header
      name: X-PackWise-Assertion
  responses:
    Unauthorized:
      description: Attestation or assertion failed
      content:
        application/json:
          schema:
            $ref: "#/components/schemas/APIError"
    RateLimited:
      description: Per-capability quota exceeded
      content:
        application/json:
          schema:
            $ref: "#/components/schemas/APIError"
    Unavailable:
      description: Intelligence temporarily unavailable
      content:
        application/json:
          schema:
            $ref: "#/components/schemas/APIError"
  schemas:
    APIError:
      type: object
      required: [error, requestID]
      properties:
        error:
          type: string
        message:
          type: string
        requestID:
          type: string
    IntelligenceMeta:
      type: object
      required: [requestID, generatedAt, promptVersion, schemaVersion]
      properties:
        requestID:
          type: string
        generatedAt:
          type: string
          format: date-time
        model:
          type: string
        promptVersion:
          type: string
        schemaVersion:
          type: string
        cached:
          type: boolean
    ChallengeResponse:
      type: object
      required: [challenge, expiresAt]
      properties:
        challenge:
          type: string
        expiresAt:
          type: string
          format: date-time
    AttestationRequest:
      type: object
      required: [keyId, attestation]
      properties:
        keyId:
          type: string
        attestation:
          type: string
    TripContextDTO:
      type: object
      required: [destination, startDate, endDate, tripType, activities, bagType, packingStyle]
      properties:
        destination:
          $ref: "#/components/schemas/DestinationDTO"
        startDate:
          type: string
          format: date
        endDate:
          type: string
          format: date
        tripType:
          type: string
        activities:
          type: array
          items:
            type: string
        bagType:
          type: string
        packingStyle:
          type: string
        transportation:
          type: string
        laundryAccess:
          type: string
        travelerCount:
          type: integer
          minimum: 1
        userNotes:
          type: string
        weatherSummary:
          type: string
        currentItemIDs:
          type: array
          items:
            type: string
    DestinationDTO:
      type: object
      required: [displayName, countryCode]
      properties:
        displayName:
          type: string
        countryCode:
          type: string
        latitude:
          type: number
        longitude:
          type: number
    PackingItemDTO:
      type: object
      required: [displayName]
      properties:
        canonicalItemID:
          type: string
        displayName:
          type: string
        quantity:
          type: integer
        category:
          type: string
    PackingSuggestionDTO:
      type: object
      required: [canonical_item_id, action, reason, reasonCode]
      properties:
        canonical_item_id:
          type: string
        action:
          enum: [recommend, remove_candidate, quantity_change]
        confidence:
          type: number
          minimum: 0
          maximum: 1
        signals:
          type: array
          items:
            type: string
        reason:
          type: string
        reasonCode:
          type: string
        arguments:
          type: object
          additionalProperties: true
    InterpretTripRequest:
      type: object
      required: [note, context, safetyIdentifier]
      properties:
        note:
          type: string
        context:
          $ref: "#/components/schemas/TripContextDTO"
        safetyIdentifier:
          type: string
    InterpretTripResponse:
      type: object
      required: [meta, inferredActivities, inferredChips]
      properties:
        meta:
          $ref: "#/components/schemas/IntelligenceMeta"
        inferredActivities:
          type: array
          items:
            type: string
        inferredChips:
          type: array
          items:
            type: string
        noteSummary:
          type: string
    TripContextRequest:
      type: object
      required: [context, safetyIdentifier]
      properties:
        context:
          $ref: "#/components/schemas/TripContextDTO"
        safetyIdentifier:
          type: string
    ContextualSignalsResponse:
      type: object
      required: [meta, suggestions]
      properties:
        meta:
          $ref: "#/components/schemas/IntelligenceMeta"
        suggestions:
          type: array
          items:
            $ref: "#/components/schemas/PackingSuggestionDTO"
    PackingGapsRequest:
      type: object
      required: [context, items, safetyIdentifier]
      properties:
        context:
          $ref: "#/components/schemas/TripContextDTO"
        items:
          type: array
          items:
            $ref: "#/components/schemas/PackingItemDTO"
        relevantPreferences:
          type: object
          additionalProperties: true
        safetyIdentifier:
          type: string
    PackingGapResponse:
      type: object
      required: [meta, suggestions]
      properties:
        meta:
          $ref: "#/components/schemas/IntelligenceMeta"
        suggestions:
          type: array
          items:
            $ref: "#/components/schemas/PackingSuggestionDTO"
    PackingOptimizeRequest:
      type: object
      required: [context, items, safetyIdentifier]
      properties:
        context:
          $ref: "#/components/schemas/TripContextDTO"
        items:
          type: array
          items:
            $ref: "#/components/schemas/PackingItemDTO"
        safetyIdentifier:
          type: string
    PackingOptimizationResponse:
      type: object
      required: [meta, optimizations]
      properties:
        meta:
          $ref: "#/components/schemas/IntelligenceMeta"
        optimizations:
          type: array
          items:
            type: object
            required: [canonicalItemID, reason]
            properties:
              canonicalItemID:
                type: string
              reason:
                type: string
              suggestedQuantity:
                type: integer
    AskRequest:
      type: object
      required: [question, context, items, safetyIdentifier]
      properties:
        question:
          type: string
        context:
          $ref: "#/components/schemas/TripContextDTO"
        items:
          type: array
          items:
            $ref: "#/components/schemas/PackingItemDTO"
        safetyIdentifier:
          type: string
    AskResponse:
      type: object
      required: [meta, answer]
      properties:
        meta:
          $ref: "#/components/schemas/IntelligenceMeta"
        answer:
          type: string
        suggestions:
          type: array
          items:
            $ref: "#/components/schemas/PackingSuggestionDTO"
"""
    )


def write_reason_and_trip_context_schemas() -> None:
    write(
        SHARED / "schemas" / "trip-context.schema.json",
        {
            "type": "object",
            "required": ["destination", "startDate", "endDate", "tripType"],
            "properties": {
                "travelerCount": {"type": "integer", "minimum": 1},
                "transportation": {"type": "string"},
                "laundryAccess": {"enum": ["none", "possible", "planned"]},
                "datedActivities": {"type": "array"},
            },
        },
    )
    write(
        SHARED / "schemas" / "packing-suggestion.schema.json",
        {
            "type": "object",
            "required": ["canonical_item_id", "action", "reasonCode"],
        },
    )
    write(
        SHARED / "schemas" / "packing-gap-response.schema.json",
        {"type": "object", "required": ["meta", "suggestions"]},
    )
    write(
        SHARED / "schemas" / "packing-optimization.schema.json",
        {"type": "object", "required": ["meta", "optimizations"]},
    )


def move_fixtures() -> None:
    dest = json.loads(OLD_DEST.read_text())
    write(SHARED / "fixtures" / "test-destinations.json", dest)
    weather = json.loads(OLD_WEATHER.read_text())
    write(SHARED / "fixtures" / "weather" / "named-fixtures.json", weather)


def validate() -> None:
    items: list[dict] = []
    for path in sorted((SHARED / "catalog").glob("*.json")):
        payload = json.loads(path.read_text())
        items.extend(payload["items"])
    ids = [item["id"] for item in items]
    assert len(ids) == len(set(ids)), "duplicate catalog IDs"
    catalog = {item["id"]: item for item in items}
    quantity_kinds = set(json.loads((SHARED / "rules" / "quantities.json").read_text())["policies"])
    quantity_kinds.add("one")

    def check_ids(label: str, refs: list[str]) -> None:
        missing = [item_id for item_id in refs if item_id not in catalog]
        assert not missing, f"{label} missing catalog IDs: {missing}"

    base = json.loads((SHARED / "rules" / "base.json").read_text())
    check_ids("base", base["base_essentials"])
    check_ids("international", base["international_adds"])
    for chip, refs in base["context_chips"].items():
        check_ids(f"chip {chip}", refs)

    activities = json.loads((SHARED / "rules" / "activities.json").read_text())["activities"]
    for activity, refs in activities.items():
        check_ids(f"activity {activity}", refs)

    trip_types = json.loads((SHARED / "rules" / "trip-types.json").read_text())["trip_types"]
    for trip_type, body in trip_types.items():
        check_ids(f"trip {trip_type}", body["add"])
        for activity in body.get("prefer_activities", []):
            assert activity in activities or activity == "", f"unknown activity {activity}"

    weather = json.loads((SHARED / "rules" / "weather.json").read_text())
    for signal, refs in weather["signalAdds"].items():
        check_ids(f"weather {signal}", refs)

    substitutions = json.loads((SHARED / "rules" / "substitutions.json").read_text())
    for need, refs in substitutions["needs"].items():
        check_ids(f"need {need}", refs)

    for item in items:
        assert item["quantity_kind"] in quantity_kinds, f"unknown quantity_kind {item['quantity_kind']} on {item['id']}"
        for companion in item.get("companions", []):
            assert companion in catalog, f"companion {companion} missing for {item['id']}"

    dests = json.loads((SHARED / "fixtures" / "test-destinations.json").read_text())["destinations"]
    dest_names = {row["displayName"] for row in dests}
    weather_ids = set(json.loads((SHARED / "fixtures" / "weather" / "named-fixtures.json").read_text())["fixtures"])
    for path in (SHARED / "fixtures" / "trips").glob("*.json"):
        trip = json.loads(path.read_text())
        assert trip["destinationFixture"] in dest_names, trip["id"]
        if fixture := trip.get("weatherFixture"):
            assert fixture in weather_ids, f"{trip['id']} unknown weather {fixture}"
        check_ids(trip["id"] + " mustInclude", trip.get("mustInclude", []))
        check_ids(trip["id"] + " mustNotInclude", trip.get("mustNotInclude", []))

    print(f"Validated {len(items)} catalog items, {len(list((SHARED / 'fixtures' / 'trips').glob('*.json')))} trip fixtures")


def main() -> None:
    items = json.loads(OLD_CATALOG.read_text())["items"]
    rules = json.loads(OLD_RULES.read_text())
    split_catalog(items)
    write_rules(rules)
    write_eval_fixtures()
    write_schemas()
    write_reason_and_trip_context_schemas()
    write_openapi()
    move_fixtures()
    validate()
    for stale in (OLD_CATALOG, OLD_RULES, OLD_DEST, OLD_WEATHER, SHARED / "contracts" / "intelligence-api.json"):
        if stale.exists():
            stale.unlink()
    print("Shared layout written")


if __name__ == "__main__":
    main()
