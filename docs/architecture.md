# Architecture

## Architecture principle

**Local-first + intelligence-enhanced.**

Local app owns:

```text
Trips
Packing lists
Packed state
User overrides
Preferences
Packing memory
```

External services provide:

```text
Destination lookup
Weather
Contextual reasoning
Optional sync
```

If external services disappear, **the packing list still works.**

## Core stack

### iOS

```text
Swift
SwiftUI
SwiftData
Swift Concurrency
Observation
```

### Apple

```text
MapKit
WeatherKit
UserNotifications
Swift Charts
WidgetKit later
App Intents later
CloudKit later
StoreKit 2 later
```

### Intelligence

```text
GPT-5.6
OpenAI Responses API
Structured Outputs
```

via the PackWise backend. **Never call OpenAI directly from the iPhone.**

## Application layers

```text
┌─────────────────────────────────────┐
│              SwiftUI                │
│           Presentation              │
├─────────────────────────────────────┤
│        Feature / State Layer        │
├─────────────────────────────────────┤
│           Domain Layer              │
│                                     │
│ Packing Engine                      │
│ Quantity Engine                     │
│ Recommendation Resolver             │
│ Personalization                     │
│ Weather Logic                       │
├─────────────────────────────────────┤
│             Data Layer              │
│                                     │
│ Repositories                        │
│ SwiftData                           │
├─────────────────────────────────────┤
│          External Services          │
│                                     │
│ MapKit                              │
│ WeatherKit                          │
│ PackWise Intelligence API           │
└─────────────────────────────────────┘
```

Views do not scatter SwiftData queries. Domain logic does not import WeatherKit types. GPT never writes SwiftData. See [packing-engine.md](packing-engine.md).

## Monorepo

```text
PackWise/
├── ios/PackWise/
├── api/
├── shared/
│   ├── schemas/
│   ├── fixtures/
│   └── contracts/
├── docs/
└── README.md
```

`shared` is contracts, catalog JSON, rules, fixtures, and schemas only. It is not a shared executable business-logic layer.

Production destinations come from MapKit (`MKLocalSearch` / completer). `shared/fixtures/test-destinations.json` is test/preview only.

Weather models include coverage, provider expiration, alerts, and attribution. Any UI that shows Apple weather must include WeatherKit attribution.

iOS 18 minimum. Bundle ID `com.packwiseapp.app`. Display name PackWise.

## Weather service

```text
WeatherService
├── MockWeatherService          previews / tests / fixtures / failure
└── WeatherKitWeatherService    live app (M2A)
        └── WeatherKitClient    WeatherKit types stay here
```

```text
MapKit destination
        ↓
coordinates + timezone
        ↓
WeatherKitWeatherService
        ↓
normalized TripWeatherContext
        ↓
WeatherSnapshot persistence/cache
        ↓
Packing engine weather signals
```

Domain code talks only to `WeatherService`, `TripWeatherContext`, and `TripWeatherState`. The engine never imports WeatherKit.

`PackingImpactBuilder` (M2B, closed) groups persisted item provenance for Packing Impact UI. It does not infer new recommendations.

M2C (closed) compares packing signals between snapshots, then reuses `recommendationDiff()`. A pending `WeatherChangeProposal` is separate from the live list until the user reviews it. Newer refreshes supersede the pending proposal. Dismissing it does not write Not Needed overrides, and the newer snapshot stays saved.

`TripWeatherState` (internal): `unavailable`, `seasonalOnly`, `forecastPartial`, `forecastComplete`, `stale`, `refreshing`, `failedUsingCache`.

## Intelligence service

```swift
protocol ContextIntelligenceService {
    func interpretTripNote(_ note: String, context: TripContext) async throws -> TripContextEnrichment
    func findPackingGaps(context: TripContext, items: [PackingItemDraft]) async throws -> [PackingSuggestion]
    func optimizePacking(context: TripContext, items: [PackingItemDraft]) async throws -> [PackingOptimization]
}
```

M1: `MockContextIntelligenceService`. M3: `RemoteContextIntelligenceService`.

Trip context crosses the API as `tripTypes[]` (one or more known types) and `bagTypes[]` (zero or more physical bags; `[]` means not specified). The schema rejects duplicates, unknown values, `notSure`, `roadTripLuggage`, and the retired singular `tripType`/`bagType` fields, and the server canonicalizes both arrays to the stable order before building model input. The generated `api/generated/vocab/trip-context.json` mirrors the Swift orders, and `scripts/validate_shared.py` fails on drift.

## Feature organization

```text
ios/PackWise/

App/

Features/
    Trips/
    TripSetup/
    TripDetail/
    PackingList/
    Weather/
    FinalCheck/
    AskPackWise/
    PostTrip/
    PackingHabits/
    Settings/

Domain/
    Trips/
    Packing/
    Weather/
    Personalization/
    Recommendations/

Data/
    Persistence/
    Repositories/
    MapKit/
    WeatherKit/
    Intelligence/

Services/
    Notifications/
    Sharing/
    Analytics/

DesignSystem/

Resources/
    PackingCatalog/
    Rules/
```

## Trip model

Persistent user data.

```text
Trip

id
destination
startDate
endDate
tripTypes[]
activities
bagTypes[]
packingStyle

status

createdAt
updatedAt
```

Possible status:

```text
draft
planning
packing
traveling
completed
archived
```

## Trip context

`PackWiseSchemaV4` (Product Experience V2, Task 2) persists set-valued trip types, preferred bags, memory fingerprints, and structured provenance; the legacy scalar columns remain only as V3 migration input. Add a new schema version for every stored-model change; never delete the store to conceal migration failure.

`TripContext` carries `tripTypes` and `bagTypes` as sets (Task 15). Every boundary that serializes them — persistence, the Intelligence API DTO, fixtures, signatures — orders them through `StableRawValueSetCodec.orderedRawValues` with `TripType.stableOrder` / `BagType.stableOrder`, never `Set` iteration order. Until Tasks 3–5 land, engine and list code still read temporary singleton accessors that resolve a multi-value selection to `.other` / `.notSure` rather than a primary value.

`Trip` is persistent user data. `TripContext` is what the intelligence system evaluates.

```text
TripContext

destination
country
coordinates

tripDates
durationDays
durationNights

tripTypes[]

activities

bagTypes[]
normalized luggage context
packingStyle

userNotes

weather

travelerPreferences

party (TripParty + Traveler[])

relevantPackingMemory
```

This context drives recommendations. Solo is a party of one. See [travelers-and-parties.md](travelers-and-parties.md).

## Packing item

```text
PackingItem

id
tripID

canonicalItemID

displayName
category

ownershipType          personal | shared
travelerID?
assignedTravelerID?
bagID?

quantity
packedQuantity

importance

sourceSignals[]

reason

isUserAdded
isUserModified

createdAt
updatedAt
```

## Canonical packing catalog

Do not scatter item strings through code.

Use canonical identifiers.

Example:

```text
clothing.tshirt
clothing.underwear
clothing.light_jacket
clothing.rain_jacket

footwear.walking_shoes
footwear.running_shoes

electronics.phone_charger
electronics.power_bank

documents.passport

health.daily_medication
```

Catalog entry:

```json
{
  "id": "electronics.power_bank",
  "display_name": "Portable charger",
  "category": "electronics",
  "importance": "important",
  "symbol": "battery.100percent",
  "keywords": [
    "battery pack",
    "power bank",
    "portable battery"
  ]
}
```

## Rules / configuration

Stable mappings should be configuration-driven.

Examples:

```text
hiking
→ hiking footwear
→ daypack
→ water bottle
```

Weather thresholds:

```text
rain_probability
temperature bands
UV thresholds
snow
wind
```

Do not create a home-grown programming language.

Use configuration where appropriate and normal Swift for complex behavior.

Catalog and rules live in `Resources/PackingCatalog/` and `Resources/Rules/`.
