# Product Experience V2 — Task 15: array trip-context contract

Date: 2026-09-14 · Branch: `product-v2-stage-a` · Plan: [../superpowers/plans/2026-09-04-product-experience-v2.md](../superpowers/plans/2026-09-04-product-experience-v2.md)

Task 15 changes the shape of trip context at every request, fixture, and API boundary. It does not change what PackWise recommends. After this task, `tripTypes[]` and `bagTypes[]` are the only accepted context shape. The engine's multi-value behavior still belongs to Tasks 3–5.

## Commits

| Commit | Scope |
| --- | --- |
| `a66640c` refactor: carry full trip-type and bag sets on TripContext | `TripContext` stores the sets; singular accessors become temporary singleton adapters; the weather-proposal signature renders the sets |
| `56c59bd` feat: migrate intelligence context to trip and bag arrays | Contract YAML, generator, generated artifacts, API types, validation, canonicalization, model input, Swift DTO, Debug App Attest probe |
| `6bf98a9` test: migrate current fixtures to multi-value context | 12 trip evals, 17 golden-ledger fixtures, eval schema, shared validation, 10 contract-only combination fixtures; temporary API test bridge removed |
| docs: align product contracts with experience v2 | This record, canonical docs/rules, plan checkboxes |

Every commit passed its boundary checks before landing. Commit 1 ran the full iOS suite. Commits 2 and 3 ran the full iOS suite, `validate_shared.py`, `npm test`, and `npm run preflight`.

## Step 1 — contract audit (before editing)

| Hit | Classification | Task 15 action |
| --- | --- | --- |
| `SchemaV1.swift` `tripTypeRaw`/`bagTypeRaw`/`preferredBagRaw` | legacy persistence (frozen V1–V3 schemas) | none |
| `Models.swift` `TripRecord.tripTypeRaw`/`bagTypeRaw`, V4 backfill, `PackingMemoryEventRecord.tripTypeRaw`/`bagRaw` | legacy persistence migration + compatibility storage | none |
| `TripRecord.tripType`/`bagType` accessors | current Swift product model (Task 2 temporary adapter) | none; consumers owned by Tasks 3–5/10/13 |
| `TripContext.tripType`/`bagType` stored scalars | current Swift product model — **singular authority** | became sets + temporary accessors |
| `WeatherChangeProposalLifecycle.tripContextSignature` | signature/fingerprint — read scalars | renders stable sets |
| `IntelligenceDTO.TripContextPayload.tripType`/`bagType` | request DTO | arrays |
| `DebugAttestProbe` raw body | request DTO (Debug tooling) | mechanical array update |
| `api/src/types.ts`, `model/inputs.ts`, `capabilities/common.ts` | request DTO / model input | arrays + canonical order |
| `api/src/validation.ts` | API validation — schema-driven, no field code | none (generated schema changed) |
| `api/src/canonical.ts` | model-output domain validation; no request canonicalization existed | added fail-closed request canonicalization |
| `api/src/model/fake.ts` | model stand-in reading the model input | reads arrays |
| `scripts/build_intelligence_schemas.py`, `api/generated/**` | generated artifact source/output — `BAG_TYPES` still listed `roadTripLuggage`/`notSure` | arrays, physical bags only |
| `shared/contracts/intelligence-api.yaml` | API contract | arrays |
| `shared/schemas/trip-eval.schema.json`, `shared/fixtures/trips/*.json` (`tripType`, `bag`) | fixture | arrays |
| `shared/fixtures/golden/golden-fixtures.json` (`tripType`, `bag`) + `GoldenEngineTests`, `PackingEngineTests`, `SharedResources.TripEvalFixture` | fixture + test decoders | arrays |
| `ios/PackWiseTests/Goldens/*.json` `"tripType"` | `RecommendationSignal.tripType` in engine output — a single provenance fact | none |
| `RecommendationSignal.tripType`, `reasons.json` `{tripType}`, gap `context.gap_trip_type` | single provenance fact / reason argument | none |
| `Party.swift` `TripBag.bagType`, `BagRecord.bagTypeRaw` | one physical bag record's type | none |
| `TripSetupView` draft, `TripRepository.createTrip`/`apply` singular params, `MeView` preferred bag | current product UI + write path (Task 8) | none — see findings |
| `BagType.notSure`/`.roadTripLuggage` cases, `BagTypeLegacyRawValue` | legacy vocabulary kept for non-V2 call sites and migration decoding | none |
| `scripts/build_shared.py` literals | obsolete bootstrap — see deviations | none |
| Canonical docs/rules | documentation — already on the V2 target; missing target vs. implemented status | status notes |

## Decisions

- **`TripContext` holds the sets.** `IntelligenceDTO.payload(for:)` only sees a `TripContext`. Wrapping the scalar would have sent `["other"]` for a multi-type trip, which is an invented value. The singular fields are now computed accessors marked TEMPORARY. They mirror Task 2's `TripRecord` adapter: a singleton resolves to its value, and a multi-value set resolves to `.other`/`.notSure`, never to a primary.
- **Duplicates are rejected, not collapsed.** Arrays are sets (`uniqueItems`). Wire order carries no meaning, and the server canonicalizes it.
- **Singular fields are refused even beside valid arrays.** The rule is `not: anyOf required tripType|bagType`. This means no handler can ever read them as a fallback. `TripContextDTO` gained no `additionalProperties: false`, so every unrelated field keeps its current behavior.
- **`bagTypes` is required.** Omitting it would make "not specified" ambiguous; `[]` states it explicitly.
- **One ordering primitive.** `StableRawValueSetCodec.orderedRawValues` backs the persistence codec, the DTO, and the signature. The generator's `TRIP_TYPES`/`BAG_TYPES` mirror the Swift `stableOrder` lists, and `validate_shared.py` fails on any content or order drift. That check was proven by deliberately swapping two bags.
- **`schemaVersion` `2026-08-29` → `2026-09-14`.** The request shape broke, and `meta.schemaVersion` exists so a behavior change can be attributed. Prompt versions are unchanged: the prompt text did not change, and model input is still `JSON.stringify` of the trip shape, now with arrays.
- **The signature stays byte-identical for singletons.** Pending weather proposals persist `tripContextSignature`. Sets are joined with `+`, so `["beach"]` still renders `beach`, and the empty bag set keeps the old `notSure` token (fingerprint text only). Existing pending proposals therefore stay valid after the upgrade, while two different multi-type trips no longer collide on `other`.
- **The model stand-in counts a bag set as space-constrained only when every bag is compact.** Real multi-bag precedence is Task 5's `LuggageContext`.

## Request contract

| | Before | After |
| --- | --- | --- |
| API `TripContextDTO` | `tripType: enum(11)` required; `bagType: enum(personalItem, carryOn, checked, backpack, roadTripLuggage, notSure)` required | `tripTypes: array, minItems 1, uniqueItems, items enum(11)` required; `bagTypes: array, uniqueItems, items enum(4 physical)` required; singular keys rejected |
| Swift DTO | `tripType: String`, `bagType: String` from the scalars | `tripTypes: [String]`, `bagTypes: [String]` from the sets in stable order |
| TypeScript | `tripType: string`, `bagType: string`; model input the same | `tripTypes: string[]`, `bagTypes: string[]`; model input canonical arrays |
| Generated | `schemaVersion 2026-08-29`, `buildHash e9a8c2c9b5c97d73` | `schemaVersion 2026-09-14`, `buildHash 43fc852c9f70f9f9`; new `vocab/trip-context.json`; strict model-output schemas byte-identical |

## Fixtures

- **Migrated:** 29 current fixtures, all wrapped as singletons. That is 12 trip evals (`DenverOutdoorCold` and `OneDayNoWeather` had `notSure`, now `[]`) and 17 golden-ledger fixtures (all physical bags).
- **Prepared:** 10 contract-only V2 combinations in `shared/fixtures/contexts/product-v2-combinations.json`. Six are trip-type combinations (Vacation+Beach, Vacation+City Break+Beach, City Break+Business, Outdoor+Road Trip, Vacation+Wedding/Event, Outdoor+Ski/Snow), owned by Task 4. Four are bag combinations (Personal item+Carry-on, Carry-on+Checked, Personal item+Carry-on+Checked, Checked+Backpack), owned by Task 5. None carries an engine expectation, and all sit outside the golden ledger and the trip evals.
- **Legacy persistence inputs:** the V3 scalar seeds remain inside `PersistenceMigrationV4Tests` and were not converted.

## Semantic golden diff

All 17 goldens are untouched (`git diff ios/PackWiseTests/Goldens` is empty), and `engineOutputMatchesGoldens` passes byte-for-byte. All 12 trip evals pass, including their inclusion, exclusion, and quantity expectations. Across every category the change count is zero: inclusion 0, removal 0, quantity 0, coverage 0, constraint 0, ownership/carrier 0, authority 0.

## Step 16 — closure audit of remaining singular references

**New request contract:** reads only `tripTypes[]`/`bagTypes[]`. No request, fixture, generated schema, or model input carries a singular context field.

**No first-value decision path exists.** The remaining singular references fall into these legitimate groups:

1. **V3→V4 migration input:** `SchemaV1.swift`, and the backfill reads of `TripRecord.tripTypeRaw`/`bagTypeRaw`, `PackingMemoryEventRecord.tripTypeRaw`/`bagRaw`, `PackingPreferenceRecord.preferredBagRaw`.
2. **Compatibility persistence storage, written but never read for decisions:** `TripRepository.applyTripTypes`/`applyBagTypes` and `PackingMemoryEventRecord.init` write the first stable value into the legacy scalar columns only so older diagnostics can read the row. No product path reads those columns outside migration.
3. **Temporary singleton adapters that fail safe:**
   - Engine: `PackingEngine`, `CoverageResolver`, and `ClothingQuantity` read `TripContext.tripType`/`bagType`. These resolve to `.other`/`.notSure` for multi-value sets and are owned by Tasks 3–5.
   - Lists: `PackingListView` and `TripDetailView` read `TripRecord.tripType` for outdoor ordering and reason copy. They are owned by Tasks 10/13.
   - Reachability: there are no production callers of `applyTripTypes`/`applyBagTypes`, so no shipped screen can create a multi-value trip yet. The `other` trip-type rule adds no items and no copy.
4. **Single provenance facts:** `RecommendationSignal.tripType`, the `{tripType}` reason placeholders, and the fake adapter's `weddingEvent` gap argument.
5. **Unrelated singular semantics:** `TripBag.bagType`/`BagRecord.bagTypeRaw` (one physical bag's type), and `TripSetupView`'s single-select draft plus the `createTrip`/`apply` singular parameters. The setup path writes both the scalar and singleton arrays, and it is rewired by Task 8.

**One legacy scalar still drives current behavior. It predates Task 15 and is reported, not fixed** (see findings): Me's preferred bag.

**Compatibility adapters:** the temporary API test bridge from `56c59bd` was removed in `6bf98a9`. The singleton accessors on `TripContext` and `TripRecord` remain by design. They are the plan's explicit engine guards, and Tasks 4 and 5 remove them.

## Deviations

- **`scripts/build_shared.py` cannot run.** It is a one-shot bootstrap: it reads `shared/fixtures/packing-catalog.json` and three sibling inputs that its own first run deleted, so it raises `FileNotFoundError` before writing anything (on HEAD too). It is not a live generator. The only working generator is `build_intelligence_schemas.py`. Its stale singular literals are dead bootstrap history and were left alone. If they are ever revived, they would overwrite hand-maintained fixtures.
- **Plan wording vs. this task's instruction.** The plan's compatibility note says boundary adapters "return `unsupportedButSafe` for multiple values." The Task 15 instruction requires the API to accept multi-value context. The API does accept it, and the fail-safe guard lives at the engine accessors, which never choose a primary value.
- **`trip-eval.schema.json` had never been enforced.** The new API test compiles it with Ajv and found `PreserveManualQuantity` missing the always-required `mustNotInclude`. The fixture gained `[]`, which every consumer already defaulted to.

## Findings for review

- **Me's preferred bag still uses the legacy scalar, in both directions.** `MeView` binds `Picker` directly to `PackingPreferenceRecord.preferredBagRaw`, and the picker still offers `roadTripLuggage` and `notSure`. `TripDraft.fresh` seeds the setup bag from `TravelerPreferences.preferredBag`, which decodes the same scalar. Nothing reads the V4 `preferredBagTypes`, and a Me edit never updates `preferredBagTypesRaw`. Concrete scenario: a user migrates with Carry-on and later picks Checked in Me. When Task 8 switches readers to `preferredBagTypes`, the user sees Carry-on again. Task 8 owns the Me/setup rewire. Either it must reconcile `preferredBagTypesRaw` from the scalar once, or Me should dual-write before then.

## Verification

| Check | Baseline `176bb42` | Task 15 |
| --- | --- | --- |
| iOS full suite (iPhone 17 Pro simulator) | 185 tests / 18 suites passed | 196 tests / 18 suites passed |
| `python3 scripts/validate_shared.py` | OK, 202 items | OK, 202 items (+ stable-order drift and fixture-shape checks) |
| `npm --prefix api test` | 106 passed | 141 passed |
| `npm --prefix api run preflight` | green | green (`schema 2026-09-14, build 43fc852c9f70f9f9`) |
| Compile warnings | 0 (2 AppIntents metadata notices) | 0 (same 2 notices) |

Tests added: 11 Swift tests (TripContext set authority and signature ×5, DTO contract ×6 including the combination round-trip), and 35 API tests (contract, canonicalization, model input, three endpoints ×2, 10 combination fixtures, eval schema).

M3B/M3C and Phase 9 stay frozen. `ContextIntelligenceGate` is unchanged, so no intelligence output is newly wired into product behavior.
