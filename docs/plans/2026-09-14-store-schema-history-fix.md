# Store schema history fix

Date: 2026-09-14 · Branch: `product-v2-stage-a` · Blocks: hardening integration, Task 3

## Defect

Upgrading any existing install crashed at launch with `NSInvalidArgumentException: Duplicate version checksums detected`, thrown from `NSLightweightMigrationStage` inside `PackWisePersistence.container`. CoreData raises it as an Objective-C exception, which can't be caught.

`PackWiseSchemaV2`, `V3`, and `V4` all aliased the live `@Model` types. Every version therefore shared one checksum (V2 differed only by lacking the memory-event entity). Any store that wasn't already in the exact current shape needed a migration stage between two identical checksums, and CoreData aborted. Adding any stored column, as Product Hardening Phase 8 does, moves every aliased version at once.

Reproduced on the iPhone 17 Pro simulator by installing a real old build, launching it, and then installing the newer build over it:

| Store written by | Opened by | Result |
| --- | --- | --- |
| `791cf88` (V3, pre-Task 2) | `d7663a5` (`main` model) | crash, on `main` today |
| `d7663a5` (`main` model) | hardening integration | crash |

The Task 2 migration tests missed it because their "V3" stores were built from the same aliased live types, so they never opened a genuinely older shape.

## Ground truth

Real stores were captured from actual `com.packwiseapp.app` builds and are checked in under `ios/PackWiseTests/StoreFixtures/`:

| Fixture | Label in store | Checksum | Built by |
| --- | --- | --- | --- |
| `v2-a975eab` | 2.0.0 | `L3DEX…` | `18d754d` … `a975eab` (verified identical at both ends) |
| `v3-791cf88` | 3.0.0 | `x1im…` | `d4ed374` … Task 1 |
| `v4.0-7a219ee` | 4.0.0 | `Spmg…` | `7a219ee` only |
| `v4.1-d7663a5` | 4.0.0 | `Kvqc…` | `c5c35bb` … `d7663a5` (= `main`) |
| `unsupported-hardening-b302634` | 3.0.0 | `4fVF…` | `product-hardening-phase1` tip, never on `main` |

Builds before `18d754d` used bundle ID `com.packwise.app`, a separate sandbox, so no V1 store can reach this app.

## Fix

- **`SchemaHistory.swift`:** frozen V2, V3, and V4 (4.0.0) snapshots, generated from each commit's own `@Model` declarations.
- **`PackWiseSchemaV4_1` (4.1.0):** the only version on the live types, and the current schema. A `main` store matches it by hash, so it opens with no migration at all.
- **Plan:** V1→V2→V3→V4→V4.1, all lightweight. The V4 data backfill still runs post-open.
- **Pre-open guard:** `PackWisePersistence.container(storeURL:)` compares the store's entity hashes with every plan schema first. An unrecognized shape throws `PackWisePersistenceError.unrecognizedStoreModel` and the store stays untouched, where before it aborted.

## Evidence

- **`StoreHistoryTests` (8):**
  - Every plan schema hashes distinctly.
  - Each real fixture matches exactly its schema.
  - The newest schema is the one the app opens.
  - All four real fixtures upgrade across two launches.
  - The unsupported store throws with its bytes unchanged.
  - A rich V3 store keeps trips, travelers (including guardian), the owned bag's identity, manual and packed quantities, custom shared items, Not Needed overrides, preferences, and memory events.
  - A V2 store upgrades, and `roadTripLuggage` never becomes Road Trip.
  - A V4.0 store keeps multi-value trip types.
- **Red first:** before the fix the same tests failed without crashing. V3 and V4 hashed identically, the V2, V3, and V4.0 stores matched nothing, and the `main` store matched both 3.0.0 and 4.0.0.
- **Real install-over upgrades with the fixed build:** V2, V3, and `main` stores each launched twice with zero new crash reports.
- **Full suite:** iOS 207/207, goldens unchanged, shared validation, API 141/141, preflight.

## Known limits

- A 4.0.0 store (only the intermediate `7a219ee` commit wrote one) predates `preferredBagTypesMigrated`, so its preference set is re-derived from the scalar once. Its trips are unaffected. This is pinned by a test.
- Stores from the unmerged hardening branch are refused with a typed error instead of opening. That shape was never on `main`, so simulators that ran it need the app reinstalled.
- `PackWiseApp` still calls `fatalError` on any container error. The store is preserved, but there is no recovery screen.
