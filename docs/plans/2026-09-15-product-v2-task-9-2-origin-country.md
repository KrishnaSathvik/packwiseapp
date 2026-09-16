# Product Experience V2, Task 9.2 — Home country becomes a new-trip default

Date: 2026-09-15 · Branch: `product-v2-stage-a` · Baseline: `b4a7260` (Task 9.1) · Closes finding F9.1-1

## Decision

`Me.homeCountry` is a profile fact that seeds a *new* trip. It is no longer a live engine input for an existing trip.

```text
Me.homeCountry
      ↓ TripDraft.fresh
Trip.originCountry  (TripOrigin: countryCode + source)
      ↓ TripRecord.context / TripRecord.isInternational
international = chip || (origin confirmed && destination ≠ origin)
      ↓
recommendation engine, Trip Detail order, Packing List order
```

The concept is the trip's **origin**, not "home country at creation": a later release can let a trip start from somewhere other than home without a model change. There is no setup control yet.

## What changed

- **Domain.** `TripOrigin` (`TripTypes.swift`) holds the code and its `HomeCountrySource`; `isInternational(destinationCountryCode:)` is the one international decision. `TripContext.origin` replaces the `preferences.homeCountry*` read in `isInternationalConfirmed`; the engine reads no Me home-country value.
- **Persistence.** V5 (5.0.0) is frozen in `SchemaHistory.swift`, generated from `b4a7260`, and pinned to a real store that build wrote (`StoreFixtures/v5-b4a7260`). V6 (6.0.0) is the live shape: `TripRecord.originCountryCode` and `originCountrySourceRaw`, both defaulted to empty. Lightweight 5.0.0 → 6.0.0 stage. An empty source is never a real value, so it doubles as the "not yet owned" marker.
- **Trip creation.** `TripDraft.fresh` copies Me's home country into `draft.origin`; `saveTrip` writes it on the new record. `TripDraft.from(trip:)` restores the trip's own origin and never reapplies Me. `TripRepository.apply` does not touch it.
- **Screens.** `TripDetailView` and `PackingListView` order categories by `trip.isInternational`. Their private copies of the decision (which read Me *unconfirmed* and fell back to the device locale, then `"US"` — a second, divergent rule) are deleted. `PackingListView` no longer queries preferences at all.
- **Me copy.** One footnote under Home country: "Used for trips you create from now on." No new control.
- **Backfill.** `TripOriginBackfill` runs on every store open after the Me-habit backfill. Trips with an empty source are fetched by predicate and given an origin once:

  | Trip's own evidence | Today's Me | Result |
  | --- | --- | --- |
  | "Traveling internationally" chip | any | origin = Me (classification already trip-owned) |
  | a generated `destination.international` row | Me ≠ destination, confirmed | origin = Me |
  | a generated `destination.international` row | Me = destination or unconfirmed | origin = Me **and** the chip is added, so the trip says it itself |
  | generated rows, none international | Me ≠ destination, confirmed | origin = Me's code, **unconfirmed**: it was built without a confirmed origin and stays domestic |
  | generated rows, none international | otherwise | origin = Me |
  | no generated rows | any | origin = Me |

  Deterministic, idempotent (an owned origin is skipped by the predicate), and it never writes rows, quantities, packed state, Not Needed, custom items, owner/carrier, travelers, trip types, activities, or bags. The only other write is the chip, in the one contradiction case.

## Tests (`TripOriginTests`, 10)

| Test | Proves |
| --- | --- |
| `meHomeCountrySeedsAFreshTripsOrigin` | Me India → draft and saved trip own India, international, passport in the list |
| `aFreshTripAfterAMeChangePrefillsTheNewValue` | Me India → US: the next fresh trip prefills US |
| `anUnconfirmedMeHomeCountrySeedsAnUnconfirmedOrigin` | a device guess seeds an unconfirmed origin that is never international |
| `anExistingInternationalTripStaysInternationalWhenMeChanges` | India-origin Chicago trip, Me → US: origin, classification, and regenerated IDs unchanged |
| `anExistingDomesticTripStaysDomesticWhenMeChanges` | US-origin Chicago trip, Me → India: no passport appears |
| `editingATripRestoresItsOwnOriginNeverMe` | `TripDraft.from(trip:)` carries the trip's origin |
| `aCompletedTripIsNeverMutatedByALaterMeChange` | completed trip + Me change + backfill: nothing changes |
| `theListIsDrivenByTheTripsOriginNotByMe` | same context, Me flipped → same list; origin unknown + Me abroad → not international |
| `legacyTripsGainAnOriginOnceFromTheirOwnEvidenceThenMe` | all five backfill rows above, rows untouched, second run with a different Me changes nothing |
| `aTripWithoutAnOriginIsNeverInternationalOnItsOwn` | an unowned trip fails safe |

`AppearanceGuardTests` (2) pins `UIUserInterfaceStyle = Light` in `Info.plist` and fails if any app source reintroduces `.preferredColorScheme(`.

`StoreHistoryTests` now pins the captured 5.0.0 store; every plan schema hashes distinctly, all five real stores upgrade across two launches, and the newest schema is 6.0.0.

Test helpers that expressed "international" through Me (`PackingEngineTests`, `GoldenEngineTests`, `TravelerEligibilityTests`, `FamilySharingTests`, `TripSetupDraftTests`) now seed `origin` from the same Me state, exactly as `saveTrip` does. No fixture or shared file changed.

## Semantic diff

- **Goldens:** 52/52 unchanged (1717 rows; 0 added, removed, quantity, trace, coverage, constraint, or eligibility changes).
- **Moved behavior:** only an existing trip whose classification depended on today's Me — the bug — and Trip Detail / Packing List ordering for trips whose device-suggested home differed from the destination (they ordered as international while the engine did not; both now follow the engine).

## Verification

- **iOS:** 556 tests in 36 suites pass.
- **Engine audit:** `scripts/run_engine_audit.sh` passes (shared validation, Python suite, focused Swift suites, clean golden diff, surfaced-input audit, strict trace audit).
- **Clean Debug build:** 0 Swift warnings; only the existing AppIntents metadata notice.
- **Real install-over upgrade:** the `b4a7260` build wrote a 5.0.0 store on the iPhone 17 Pro simulator; this build installed over it and launched twice with 0 crash reports; the store is labeled 6.0.0, carries `ZORIGINCOUNTRYCODE` / `ZORIGINCOUNTRYSOURCERAW`, and keeps its preference row.
- **API preflight:** not run; no shared or generated artifact changed.

## Findings (not fixed)

- **F9.2-1.** A trip created while Me's home country was only device-suggested owns an *unconfirmed* origin. Confirming the country in Me later does not make that existing trip international; only its next fresh trip. This is the isolation rule applied consistently, but it means a user who confirms Me after creating their first trip must add "Traveling internationally" on that trip themselves. A per-trip origin control would close it.
- **F9.2-2.** `PackingPreferenceRecord.hasConfirmedHomeCountry` is a dead column (initialized false, never read or written); `homeCountrySourceRaw` is the authority. Left alone — removing it is a schema change with no user-facing gain.
