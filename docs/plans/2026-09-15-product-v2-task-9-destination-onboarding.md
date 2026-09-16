# Product Experience V2, Task 9 — onboarding, destination setup, and the destination-hero system

Date: 2026-09-15 · Branch: `product-v2-stage-a` · Baseline: `126696c` (Task 8.2)

Presentation only. The engine, goldens, trace architecture, eligibility, sharing, weather semantics, user authority, and App Attest are unchanged. Destination presentation does not alter recommendation context: display-time region expansion never writes the stored `Destination`.

## A–B. Onboarding

- **One shell** (`OnboardingView`). Every page has:
  - `PackWiseBrandMark` in the same place;
  - a framed hero with one height rule, radius, and border;
  - `screenTitle` and `screenSubtitle`;
  - page dots and the primary button pinned in the bottom safe-area inset.
- **Light throughout.** The old dark full-bleed page 1 is gone.
- **Copy** lives in `OnboardingPage`, word for word from the brief:

  | Page | Title | Subtitle | Hero |
  | --- | --- | --- | --- |
  | 1 | Pack for the trip you're actually taking. | Destination, dates, weather and plans shape your list. | Travel photo plus four input pills |
  | 2 | One trip can be many things. | Beach, city, business, activities and luggage work together. | One trip: three selected types, activities, bags |
  | 3 | Your choices stay yours. | Change quantities, skip items and add your own without losing your decisions. | Changed quantity, skipped item, added item |

- **Removed:** "Personalized over time", the "remembers what you bring…" promise, and the example habits card. `DestinationVisualTests.onboardingMakesOnlyTruthfulClaims` pins the copy and bans AI, GPT, LLM, model, remember, learn, personalized, and "over time".
- **Dynamic Type.** Title and copy use `PackWiseFont` roles.
  - Hero illustrations cap at `.large`: they are examples, and each reads as a single VoiceOver label.
  - At accessibility sizes the hero yields height (34% of the page instead of 62%), so the title and subtitle are on screen without scrolling.
  - The CTA and dots are in the safe-area inset and always visible.
  - Reduce Motion removes page and advance animations.

## C. Destination setup

- **`DestinationStepContent`** is inside the Task 8 shell. `DestinationStepPhase` shows one state at a time:
  - **empty:** recents when the user has trips, otherwise three guidance rows;
  - **searching;**
  - **results:** compact rows, 52pt minimum;
  - **no results:** "No places found for “x” — check the spelling, or try again when you're online";
  - **selected.**
- **Recents** are the user's own trips only: newest first, deduplicated, at most three. Nothing is invented.
- **Result rows.**
  - **Title:** the place name.
  - **Subtitle:** region and country, with US and Canadian postal codes expanded at display time (`IL` → Illinois).
  - **VoiceOver:** "Khammam, Telangana, India" plus a hint.
- **Selected state.** The results give way to one confirmed card:
  - a map thumbnail;
  - "✓ Selected" — text plus glyph, not color alone;
  - name and context;
  - **Change**, which stacks vertically at accessibility sizes.
  - Selection posts a VoiceOver announcement.
  - The duplicate large preview card is gone.

## D–E. Destination visual policy and MapKit

`MapKitDestinationVisualService` resolves trusted imagery, then street imagery (policy-gated), then an `MKMapSnapshotter` map, then the graphical fallback.

- **Trusted imagery:** bundled `Destination-<name>` assets. None ship today.
- **Street imagery is off** (`DestinationVisualPolicy.production`). See deviation 1.
- **Map snapshot:** flat satellite (`MKImageryMapConfiguration`), with no labels to collide with the title.
  - **Span** by destination granularity: city 0.16°, region 3.5°, country 16° of latitude.
  - **Placement:** the destination sits at a per-purpose height fraction — card 0.28, hero 0.45, thumbnail 0.5.
- **Cache key:** `map-v4_<lat4>_<lon4>_<scale>_<purpose>_<w>x<h>`. Rounded coordinates, never names. It is versioned, so style changes invalidate old files.
  - Results are cached in memory and in Caches, with a tier marker byte.
  - A failure is never persisted; it retries after 60 s.
- **Concurrency.** Rendering is detached from the main actor. Only `MKMapSnapshotter.Options` trait setup runs on the main actor, because trait mutation is main-actor isolated.
  - Caller cancellation cancels the snapshotter, resumes exactly once, and caches nothing.
- **View states** (`DestinationVisualDisplayState`): loading (brand gradient in final geometry), image, map, graphical. The fade is disabled under Reduce Motion.
- **Graphical fallback:** brand gradient plus one dashed route motif ending in the shared marker, or a monogram on thumbnails. The globe and airplane are deleted.

Tests (`DestinationVisualTests`, injected providers, no Apple network):

- trusted imagery wins and touches no provider;
- Chicago and Khammam resolve to a map once, then from memory, then from disk after a relaunch;
- production never runs street imagery, and a Look Around miss falls through to the map;
- offline gives graphical, not persisted, not re-requested within the interval, and recovers on reconnect;
- cancellation;
- deterministic keys, span per granularity, marker placement, and long names that never reach file names;
- decoration and marker stay outside the text region;
- destination phases, recents, and row presentation.

## F–G. Destination heroes

`DestinationHero` (style `.hero` or `.card`) renders Review, the Trips Home current-trip card, and the Trip Detail hero.

- **Shared:** visual policy, `DestinationScrim` (stronger under Increase Contrast), and the tokens `heroTitle` (largeTitle bold), `heroCardTitle` (title2 bold), and `heroMetadata` (subheadline medium).
- **Text safe region.** The visual is a background, so text sets the height above `minHeight` (card 150, hero 270) and nothing reflows when the visual loads.
- **Decoration band.** Decoration is confined to the band above the text and below `reservedTop` (Detail's controls).
  - `DestinationVisualLayout.decorationRect` and `textSafeRect` never intersect.
  - The map marker is a SwiftUI overlay, drawn only when its halo fits in the band. At accessibility sizes it hides instead of sitting under the title; the first accessibility capture showed that collision.
  - The old airplane-over-text bug cannot recur.
- **Attribution.** Apple imagery attribution stays visible: text keeps a constant 18pt clearance above the bottom-left corner.
- **Thumbnails.** Compact trip cards use the same visual at `PackWiseRadius.control`, replacing the old raw 10pt radius.
- **Preserved:** Trips Home sections, the add control, and progress semantics; Trip Detail's status, Weather, Packing Impact, and Categories; Review's summaries and multi-select semantics.

## J. Systemic review

Contact sheets:

- `docs/device-evidence/product-v2/task9-contact-sheet-standard.png`
- `docs/device-evidence/product-v2/task9-contact-sheet-accessibility.png`
- `docs/device-evidence/product-v2/task9-increase-contrast.png`

Seventeen states at standard and accessibility-large (iPhone 17 Pro, iOS 26.3), plus three heroes under Increase Contrast. `M1LoopTests.task9ReferenceStatesAreAllCapturable` pins the inventory.

**Compared with Checkpoint V:**

| Surface | Checkpoint V | Task 9 |
| --- | --- | --- |
| Onboarding | Dark full-bleed ad, white explainer, settings mock — three compositions | One shell; the heroes differ inside the same frame |
| Destination | Selected row plus a second large card with a Look Around photo of office doors | One confirmed card with a satellite thumbnail |
| Review / Home / Detail | Look Around doors, airplane-and-globe fallback, three text treatments | One primitive: satellite map or route fallback, shared scrim and type |

**With titles hidden,** the screens still read as one product.

**Pass findings and fixes,** all in shared primitives:

| # | Finding | Fix |
| --- | --- | --- |
| 1 | Standard-map labels collided with titles; white text lacked contrast on light maps | Satellite configuration |
| 2 | Map attribution sat under the date line and would be hidden by Detail's overlapping progress card | Constant attribution clearance; the progress card no longer overlaps the hero |
| 3 | The route motif ran into Detail's options button | `reservedTop` |
| 4 | Onboarding demo heroes were too pale | `accentWash` frame |
| 5 | At accessibility sizes, onboarding copy started behind the controls | The hero yields height |
| 6 | At accessibility sizes, the baked-in marker sat under the Review title | Marker became a band-gated overlay |
| 7 | After fix 6, the band gate hid markers even at the standard size | Per-purpose marker fractions |

## Deviations

1. **Look Around tier is implemented but off.** The brief lists Look Around "where useful". The only evidence (Chicago → glass doors) shows it is not useful by default, so the provider and gate exist behind `DestinationVisualPolicy` (tests cover both settings) and production skips to the map.
2. **Satellite, not the standard map style.** Labels collide with the destination title and contrast fails on the standard style.
3. **Trip Detail's progress card no longer overlaps the hero.** The attribution licensing requirement wins over the visual stitch. This is the only Detail layout change. Krishna approved it as the final layout in Task 9.1.
4. **Design contract change.** The earlier rule "never a map snapshot" (2026-08-31) is superseded by the brief. `docs/design-system.md` is updated.

## Findings (not fixed)

- **F9-1.** The status bar over Trip Detail's dark hero renders dark glyphs (the app is light-only). It predates Task 9, and Checkpoint V shows it too. Trip Detail chrome belongs to Task 10.
- **F9-2.** `DestinationSearching` returns `[]` for both "no match" and "offline", so the step shows one combined message. A typed failure would allow a distinct offline message.
- **F9-3.** At accessibility-large, the Trips Home card's weather line truncates ("Rain…"). This predates Task 9 and is outside the hero.

## Verification

- **iOS:** 536 tests in 34 suites pass. The clean Debug build has 0 Swift warnings; the only lines are the existing AppIntents metadata notice.
- **Engine audit:** passes. Shared validation, Python tests (121 OK), focused Swift suites (107), a clean golden diff (52/52 unchanged), the surfaced-input audit, and the strict trace audit are all clean.
- **Goldens:** unchanged.
- **API preflight:** not run; no shared artifact changed.
