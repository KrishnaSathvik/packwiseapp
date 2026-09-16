# Product Experience V2 — exit checkpoint

**Status: BLOCKED / NOT GREEN.** Date: 2026-09-16. Task 14 and Phase 9 were not started. This report records completed automated work and the remaining physical acceptance work; it does not waive it.

Branch: `product-v2-stage-a`, starting at `7d7cc4d`. Implementation HEAD: **`652a257`** (`fix: let quantity editors represent the persisted quantity domain`). The following documentation/evidence commit is the final checkpoint HEAD; resolve with `git log -1 --format=%H -- docs/plans/2026-09-16-product-v2-exit-checkpoint.md`. No push or deployment.

## Main integration follow-up

The user subsequently authorized merging all work into main. The merge includes
`652a257`, `f7022ac`, and schema-history fix `5a878a9`, preserving the existing
local Xcode signing settings and main's WeatherKit diagnostics. This clears the
separate **missing-schema-fix-on-main** deployment blocker once this merge is
committed. The merged tree passes the full iOS suite (615 tests in 39 suites),
API preflight (141 tests), and strict trace audit; engine goldens are unchanged
from the V2 branch. It does not clear the physical-device/VoiceOver V2 exit gate above.
The dated pre-merge findings below remain as historical evidence.

## Quantity-domain decision

[Full audit and policy](2026-09-16-product-v2-task-13-1-quantity-domain.md). Highest observed: 35 diapers across 52 fixtures / 1,717 records. Infant diapers can reach 56; dresses and shared duration/consumer scaling have no finite product cap. Both editors now use positive Int storage bounds, `1...Int.max`. No generated decisions change. Opening never clamps to 30.

Automated coverage includes 1, 5, 30, 35, 56, 1000 and Int.max; valid increment/decrement arithmetic, save, two disk-container reopens, packed/category/owner/carrier preservation. Manual 35 survives regeneration. [Simulator Item Detail](../device-evidence/product-v2/task131/quantity35-simulator.png) visibly shows generated diapers at 35 with both Stepper controls enabled. This is the in-memory languageChild scene. Native UI tapping and physical process-relaunch quantity preservation remain unverified; model tests are not substituted for them.

## Automated results

| Check | Result |
| --- | --- |
| Full iOS suite | PASS — 615 tests, 39 suites |
| Engine audit | PASS — all six steps; 107 focused Swift tests, 121 Python tests |
| Strict trace audit | CLEAN — zero reported defects |
| Shared validation | PASS — 202 catalog items |
| API preflight | PASS — artifact/schema verification, TypeScript, 141 tests |
| Baseline golden comparison | PASS — 52 fixtures / 1,717 records unchanged from 7d7cc4d, including quantities and trace fields |
| Clean Debug simulator build | PASS |
| Clean Release simulator build | PASS |
| Signed Debug physical-device build | PASS |
| Swift warnings | Zero; existing AppIntents metadata-extraction notice only |
| Release diagnostic exclusion | Checked binary contains none of DebugPreviewScreen, DebugAttestProbe, DeveloperToolsView, DebugWeatherInjection, PackWiseScreen, TEST WEATHER |

[Retained totals](../device-evidence/product-v2/task131/automated-summary.txt), [strict trace audit](../device-evidence/product-v2/task131/trace-audit.md), [semantic comparison](../device-evidence/product-v2/task131/semantic-engine-diff.txt). Full transient logs: `/private/tmp/task131-{full-ios,engine-audit,api,debug,release,device-build}.log`.

Release symbol/string exclusion is build evidence, not a complete Release customer interaction pass. Simulator tests deliberately exercise corrupt-store rejection and emit Core Data errors for those tests; the suite passes.

## Physical and accessibility checkpoint

Connected device: iPhone 17 Pro Max (iPhone18,2). Signed build installed over the existing `com.packwiseapp.app` without uninstalling or erasing its data. Two successive launches succeeded; after the first, PackWise remained in the device process list. This verifies installation/startup only. The pre-existing store's schema version and contents were not established, so this is **not** claimed as a representative V2/V3/V5 upgrade acceptance pass.

| Required checkpoint | Actual result / remaining evidence |
| --- | --- |
| A — fresh install, onboarding and complete creation/navigation | NOT VERIFIED on hardware; existing install preserved |
| B — Vacation + Beach + City Break, Sightseeing, Carry-on + Checked | NOT VERIFIED on hardware; engine suite passes, not a substitute |
| C — family ownership, devices, sharing, People/group edits | NOT VERIFIED on hardware |
| D — real WeatherKit, impact, reason, attribution, unavailable state | NOT VERIFIED on this build; prior evidence does not clear the current gate |
| E — Chicago / Khammam destination and offline visuals | NOT VERIFIED on hardware |
| F — edits and authority through context regeneration | Automated authority regression PASS; physical flow NOT VERIFIED |
| G — offline packing and editing | NOT VERIFIED on hardware |
| H — representative V2/V3/V5 stores, two launches | NOT VERIFIED; migration unit tests pass but are not install-over-install acceptance |
| I — current physical App Attest valid/replay/tamper | NOT RERUN; prior development success is not a current smoke result |
| J — standard/accessibility-large, spoken VoiceOver, contrast, motion | Spoken and hardware settings pass NOT PERFORMED |
| K — Debug/Release build | PASS as above; Release interaction not performed |

**Spoken VoiceOver:** no utterance was heard or recorded in this session. Ordinary, weather, activity, device, shared, grouped family, group member, Item Detail, custom/manual, quantity >1 and accessibility-large cases all remain open. Duplicate reason/quantity, repeated traveler names, decorative speech, group verbosity, internal terms and punctuation therefore have no runtime verdict. No accessibility composition was changed on the basis of guesses.

The available device tools install, launch and inspect processes but cannot operate the phone's UI or listen to its VoiceOver output. A hands-on operator was requested; no operator results were received before this report. Complete the user's A–J scenarios on this installed build, recording actual utterances and device outcomes. In particular use a persisted generated 35: open detail, decrement to 34, increment to 35 (and 36), restore/save 35, force-close/relaunch, then regenerate and verify all explicit state. Do not use the in-memory capture scenes as persistence or real-weather evidence.

## Phone-charger trace

All 52 generated phone-charger examples have exactly one provenance fact: `base.essential.electronics`, empty reasonArguments, source `baseEssential`. No structured owned-phone or companion fact is present. Therefore “Useful for this trip.” remains truthful. `RecommendationReasonRenderer` already renders “For your phone.” for `preference.bringingPhone` or the matching structured companion fact; no second reason source or presentation inference was added.

## Unresolved findings

| Classification | Finding |
| --- | --- |
| BLOCKER | Required physical A–J flows, spoken VoiceOver and quantity UI/relaunch acceptance remain unverified. V2 cannot be declared green. |
| BLOCKER — deployment separately | Schema-history fix `5a878a9` is an ancestor of this V2 branch but **not** of main (`ada11d8` at inspection). Main must receive the fix before any build goes to an existing-install user. Main's pre-existing Xcode project modification was left untouched. |
| V2 follow-up | None newly established beyond the mandatory open acceptance gates. Any observed runtime defect must be classified when evidence exists. |
| Later enhancement | Phone-charger owned-device evidence missing from trace vocabulary/output; consider in a later engine-contract pass, never fabricate in presentation. |
| Later enhancement | Optional direct numeric input for unusually large manual quantities; current native Stepper supports the persisted domain. |

Stop here. Task 13.1 code is committed and automated checks pass; its remaining runtime acceptance and the full V2 exit gate remain open. No Task 14, Phase 9, M3B or M3C work is authorized by this report.
