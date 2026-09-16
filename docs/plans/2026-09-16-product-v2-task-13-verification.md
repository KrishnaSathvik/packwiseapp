# Task 13 — review handoff

Baseline: `80e49a0` on `product-v2-stage-a`. Implementation commit: `8475a16`; the following handoff commit includes the final owner-context correction and evidence. Tasks 11.1 and 12 were approved. Stop here for review; Task 14 and Phase 9 were not begun.

## Architecture and compatibility

One pure `RecommendationReasonRenderer` reads `RecommendationTrace` facets. Generated inclusion prose uses only the record's complete structured provenance. Owner context supplies identity/pronouns, never causal input. List rows, Item Detail, group members, and proposed-change rows all use it. Groups themselves retain their Task 11 counts and do not merge causes.

Deleted: `PackingReasonPresentation`, singular `tripType` sentence interpolation, direct `item.reason` display in the list/detail/diff surfaces, the fake custom-item fallback, and broad source chips in detail. Source guards protect the three reason/presentation files. Expanded trace UI is deferred; one concise sentence is enough here.

Remaining compatibility: engine-side `ReasonRenderer`, legacy reason codes/arguments/strings, trip compatibility accessors used outside reason rendering, and persisted trace encoding remain. The engine/audit contract was not rewritten for presentation. Pre-trace records omit missing inclusion copy rather than inferring it from current trip metadata. No second stored explanation field, schema change, trace deletion, or recommendation resolver change.

## Representative output

| Evidence | Customer inclusion reason | Separate evidence |
| --- | --- | --- |
| Other or Vacation alone | Useful for this trip. | Hidden on list rows |
| Beach alone | Useful for the beach. | — |
| Beach + Festival | Useful for beach and festival days. | Both facts retained |
| Business + Wedding/Event | For work and the event. | Both facts retained |
| City Break + Sightseeing | Useful for sightseeing and days around the city. | Both facts retained |
| Rain | Rain is expected during your trip. | No raw temperatures |
| Hot + high UV | For hot, sunny weather. | Both facts required |
| Hiking | For hiking. | Unselected suggestions contribute nothing |
| Nice Dinner / Nightlife | For a nicer dinner. / For nights out. | Same smart-casual item |
| Primary traveler laptop charger | For the laptop you're bringing. | Own record's companion fact |
| Adult 1 tablet | For the tablet they're bringing. | No primary-traveler device lookup |
| Explicit child diapers | For Ada. | About 5 a day for Ada — 35 for 7 days. |
| Shared sunscreen | Useful for beach days. | 2 for the group. |
| Personal-item clothing cap | Everyday clothing for the trip. | Packed lighter to fit your luggage. |
| Checked available, no effect | Existing inclusion reason | No invented bag explanation |
| Manual/custom item | None | Added by you. |
| Edited generated item | Original inclusion trace | User authority; stale quantity copy omitted |

Priority and stable template order are tested independently of fact order, set order and persisted JSON order. The complete fixture sweep checks concise output, forbidden taxonomy and read-only behavior.

## Naming

[The complete audit](2026-09-16-product-v2-task-13-language-audit.md) covers all 202 catalog names and lists every canonical ID, before/after name, decision and representative output. Eighty-three canonical IDs have actual generated examples in the 52 fixture matrix; the remaining rows explicitly say that no fixture example exists and that manual addition gets no generated reason.

All 11 renames, with IDs unchanged:

| Canonical ID | Before | After |
| --- | --- | --- |
| `clothing.nice_outfit` | Nice dinner outfit | Smart casual outfit |
| `documents.visa` | Visa / entry docs | Visa or entry documents |
| `electronics.outlet_splitter` | USB hub / splitter | USB hub |
| `kids.snacks` | Kid snacks | Children’s snacks |
| `kids.sunscreen` | Kid sunscreen | Children’s sunscreen |
| `kids.activities` | Small activities | Coloring supplies |
| `miscellaneous.ziplocks` | Ziplock bags | Resealable bags |
| `miscellaneous.wedding_card` | Card for event | Greeting card |
| `toiletries.aftershave` | Aftershave / serum | Aftershave |
| `travel_comfort.reusable_bottle` | Empty security bottle set | Travel toiletry bottles |
| `travel_comfort.empty_security_bottle` | Empty security bottle | Empty water bottle |

Nightlife is resolved by naming only: the existing `dinner`/`smart_casual` contract already represents the broader concept. No activity split or behavior expansion. Formal outfit and Sun hat remain age-neutral. The catalog has no tablet-charger canonical item; no new one was invented for this task.

## Visual and accessibility evidence

- [Required 12-panel contact sheet](../device-evidence/product-v2/task13-reasons-language-sheet.png).
- [Accessibility-large review sheet](../device-evidence/product-v2/task13-reasons-accessibility-sheet.png).
- [22 original simulator captures](../device-evidence/product-v2/task13/): eleven states at normal and accessibility-large sizes.
- Reproduce with `scripts/capture_task13_reasons.sh`, then `python3 scripts/compose_task13_reason_sheet.py` (Pillow).

These are real iPhone 17 Pro simulator screens backed by generated fixture traces, not physical-device or live weather evidence. Detail captures use the same ItemDetailView in a full-screen navigation host; grouped detail is the actual medium sheet. Normal and accessibility-large language was visually inspected for grammar, punctuation, wrapping, repetition and internal vocabulary. Long reasons wrap without truncation; large group sheets scroll their underlying records. A duplicate reason disclosure arrow inside NavigationLink was removed. Baseline items remain quiet and readable.

VoiceOver source review: the reason is nested once under the combined row, the decorative chevron is hidden, and the quantity badge has an explicit “Quantity N” label. Task 11 group accessibility is retained. A spoken VoiceOver pass was **not performed**; source inspection and screenshots are not equivalent to runtime speech verification. Do not claim that part of the exit gate as externally verified.

## Verification

- `RecommendationReasonRendererTests`: 10 passed, including all requested type/source/owner/manual/quantity cases, ordering/encoding checks, source guard and a complete fixture sweep.
- Full iOS suite: 614 tests in 39 suites passed. Includes ReasonQualityTests, RecommendationTraceTests, RegenerationProvenanceTests, PackingListAggregationTests, CategorySelectorTests, M1LoopTests and persistence coverage. This repository has no separately named ItemDetailTests suite; its shared renderer, category behavior and captures were verified through these existing surfaces.
- Clean Debug simulator build: passed; zero Swift warnings. Xcode emits the unrelated AppIntents metadata-extraction notice because the app does not depend on AppIntents.
- `scripts/run_engine_audit.sh` at `8475a16`: all six steps passed, including 107 Swift tests in five suites and 121 Python audit tests.
- Strict recommendation-trace audit: clean; zero seasonal-provenance, fabricated-user-authority or quantity-argument-vocabulary defects. [Retained audit](../device-evidence/product-v2/task13/trace-audit.md).
- Surfaced-input audit completed. [Retained audit](../device-evidence/product-v2/task13/input-audit.md).
- Shared validation: 202 items, integrity checks passed.
- API preflight: schema/artifact verification and TypeScript checks passed; 141 tests passed.
- Semantic comparison against **80e49a0**, excluding only reviewed `displayName`: 52/52 fixtures and 1,717 records unchanged. Zero additions, removals, quantity, coverage, constraint, eligibility, ownership/sharing or provenance changes. [Retained diff](../device-evidence/product-v2/task13/semantic-engine-diff.txt).
- A separate exact JSON comparison restored only the 58 reviewed display-name occurrences and found every golden identical to baseline. No reason, quantity or provenance fields were excluded from that check. The subsequent owner-context-only correction passed the final full iOS suite and clean build. The engine-audit script also compares against the implementation HEAD; that is supplemental, not a substitute for the original-baseline comparison.

## Findings and limits

1. **F13-1 — pre-existing quantity editor bound:** the generated diaper quantity is 35, while Item Detail's Stepper is declared `1...30`. The screenshot exposes the mismatch. No quantity behavior was changed; review separately from this presentation task.
2. Applied bag-cap evidence does not retain bag identity; honest generic luggage copy is used instead of inferring “personal item.”
3. Spoken VoiceOver remains unverified. Dynamic Type and source-level accessibility review passed; physical-device, Apple-service and App Attest claims are not made by this task.
4. The full suite initially found three goldens using the previous “Travel games” build while source goldens had already been corrected to “Coloring supplies.” The final fresh build/full suite passes with the catalog's actual crayons/coloring semantics.

Worktree: `/private/tmp/packwise-task13` on `product-v2-stage-a`, moved with approval from the original external worktree location. The main checkout and its pre-existing Xcode project modification were left untouched. No push or deployment. Implementation and evidence are committed; stop for review.
