# Data, Privacy, and Platform

## Weather architecture

```text
Destination
    ↓
Coordinates
    ↓
WeatherKit
    ↓
Weather Adapter
    ↓
TripWeatherContext
```

Normalized context:

```text
minTemperature
maxTemperature

dailyForecast[]

rainDays
snowDays

uvRange

windRange

weatherSummary

fetchedAt
```

Domain logic never deals directly with WeatherKit types.

## Weather snapshot

Store a trip weather snapshot locally. Encoded `TripWeatherContext` is the source of truth.

```text
WeatherSnapshot

tripID
fetchedAt
providerFetchedAt
providerExpiresAt

coverageStart
coverageEnd
forecastAvailableForWholeTrip
forecastAvailableForPartialTrip
source

dailyForecast
summary
```

Offline user still sees:

> Updated 5 hours ago.

If WeatherKit fails, keep the cached snapshot (`failedUsingCache`) and still open the list. Far-future trips persist `source = seasonal` and do not pretend to have a forecast.

## Weather diff engine

M2C (closed). Detect only meaningful **packing-signal** changes. A 2° temperature wiggle is not a packing event.

```text
Previous Weather
        +
Current Weather
        ↓
packing signal change?
        ↓
packing consequence change?
        ↓
WeatherChangeProposal (pending until review; one actionable proposal per trip)
```

Example:

```text
Rain
0 days → 2 days

Minimum
64 → 49

Snow
none → expected
```

Then rerun only relevant recommendation layers.

## Packing diff

After changed context:

```text
Current list
       +
New suggestions
       ↓
Recommendation Diff
```

Produces:

```text
ADD
Rain jacket

REMOVE CANDIDATE
Heavy sweater

QUANTITY CHANGE
T-shirts 5 → 4
```

Then the user decides. Never silently rewrite the list.

## Persistence

Use SwiftData.

Core persistent entities:

```text
Trip
PackingItem
Destination
WeatherSnapshot
TripActivity
PackingPreference
PackingMemory
RecommendationOverride
PostTripFeedback
```

Keep data model versioning from day one because it will evolve.

## Repositories

Views should not scatter SwiftData queries everywhere.

Use:

```text
TripRepository
PackingRepository
PreferenceRepository
MemoryRepository
```

This gives:

```text
production SwiftData repository
test in-memory repository
future cloud repository
```

without rewriting UI.

## Offline behavior

PackWise needs to work extremely well offline.

Source of truth: **local database**.

Open trip:

```text
SwiftData
  ↓
Render immediately
  ↓
Refresh external context in background
```

Never:

```text
Open Trip
↓
Network request
↓
Spinner
↓
Maybe render
```

## Cloud sync

Not required for MVP.

Later: **SwiftData + CloudKit**

Advantages:

```text
iPhone/iPad sync
iCloud account
no custom password requirement
Apple-native
```

Keep PackWise usable without requiring an account.

## When a real backend is needed

A tiny backend is already required for GPT-5.6. That is not a huge product backend.

Early:

```text
PackWise Intelligence API

/interpret-trip
/recommend-context
/check-gaps
/pack-lighter
/ask
```

Local iOS still owns most app data.

Later backend becomes broader for:

```text
group trips
Android
web
server-managed user accounts
shared trips
remote packing knowledge
subscriptions across platforms
```

Endpoint contracts: [packing-engine.md](packing-engine.md).

## Privacy

PackWise does **not** need live GPS location.

It needs selected destination coordinates.

Do not request location permission unless a later feature genuinely requires it.

Travel apps often abuse this permission. PackWise should not.

No signup on first launch. No notification permission on first launch.

## Sensitive information

User may enter:

```text
Medication
Contacts
Medical device
Travel documents
Destinations
Travel dates
```

Keep local wherever possible.

Do not encourage storing:

```text
Passport number
Passport photo
Credit card
Visa numbers
Medical records
```

PackWise needs the reminder **Passport**, not the passport itself.

## Analytics

Keep product analytics focused.

Events:

```text
trip_created
packing_generated
packing_item_packed
packing_item_removed
packing_item_added
suggestion_accepted
suggestion_rejected
weather_change_reviewed
final_check_opened
trip_completed
post_trip_review_completed
pack_lighter_used
packing_gap_check_used
```

Do not casually transmit custom item names.

## Notifications architecture

`NotificationCoordinator` owns:

```text
forecast_available
weather_change
three_days_before
day_before
departure_day
post_trip_review
```

Changing trip dates automatically cancels and rebuilds scheduled notifications.

Copy rules: [lifecycle-memory-and-me.md](lifecycle-memory-and-me.md).

## Background work

iOS background refresh is opportunistic.

```text
Background refresh
      ↓
Upcoming relevant trips
      ↓
Weather refresh
      ↓
Meaningful change
      ↓
Local notification
```

Never promise exact minute-by-minute checks.

## App startup

```text
Launch
  ↓
SwiftData initialization
  ↓
Load local upcoming trips
  ↓
Render
  ↓
Refresh relevant background context
```

Should feel essentially instantaneous.
