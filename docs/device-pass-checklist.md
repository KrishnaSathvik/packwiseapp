# PackWise Device Pass

One comprehensive pass on a real iPhone, covering both halves of what is still
unproven: the App Attest path against Apple's development environment, and the
product itself under a real finger on real hardware.

Everything below runs against a **Debug** build pointed at
`https://packwiseapp-dev.vercel.app` (App Attest, Apple development
environment). Production stays on `production` and is not touched.

TestFlight is deferred — see the gate note at the end.

### What this pass verifies

This pass clears the pre-M3B physical-device gate against the app's current
state at **`f92eda8`** ("docs: close product hardening phase 8
recommendation trace productization") — Product Hardening Phases 1–8,
closed. It does **not** rely on the connected-device audit recorded on
2026-09-03 in the Gate section below: that audit found the paired device
unavailable in Xcode and was superseded by a sequencing decision to proceed
with the deterministic Phases 1–8 rather than by a passing device result.
Nothing below should be marked done on the strength of that historical
entry.

The App Attest implementation itself — every file listed in section 1 and
the Debug harness, both iOS and API — has not changed since the M3A-2 work
landed (`2b36228`, `18d754d`) and was verified per
[m3a2-verification-runbook.md](m3a2-verification-runbook.md) on 2026-08-30.
That verification is still current; only the physical-device steps in that
runbook and in this checklist remain open. What **has** changed since this
checklist was last written (2026-09-03, before Phase 8) is the product
surface: Phase 8 wired a new "Why it's on your list" authority line into
Item Detail. Section 4a below covers it — it did not exist when this
checklist's other sections were written and is the most likely genuine gap
in this pass.

---

## 0. Prerequisites

```text
[ ] Debug build installs on the device
[ ] Xcode automatic signing produced a development profile
[ ] App Attest capability present (entitlements are shared across
    configurations, so Debug and Release both have it)
[ ] Debug entitlement environment resolves to `development`
[ ] WeatherKit entitlement present
[ ] Bundle identifier is com.packwiseapp.app
```

Verify the last three without guessing:

```bash
codesign -d --entitlements - --xml "<PackWise.app>" | plutil -convert xml1 -o - -
```

---

## First: take a real trip through it

Before the matrix below, use the app the way its owner would, not the way
its author would. Pick somewhere you would actually go. Run all eight setup
steps for real. Pack a few things. Not to test features — to notice what is
annoying. Every screenshot so far came from a debug harness at a fixed
size; nobody has felt the scrolling, the tap targets, or the setup flow on
a real phone.

While doing it, keep a plain list of what feels wrong, **without
diagnosing**. "The date picker is fiddly" is more useful raw than
pre-sorted into P1s and P2s — the sorting judgment works better on
unfiltered observations, afterwards.

---

## 1. App Attest — technical

The chain this proves:

```text
DCAppAttestService.isSupported
 → generateKey()
 → POST /v1/integrity/challenge
 → attestKey()
 → server verifies the real Apple certificate chain
 → key persisted in Upstash
 → generateAssertion()
 → POST /v1/trip/interpret
 → server verifies signature, body digest, counter
 → GPT-5.6
 → 200
```

```text
[ ] DCAppAttestService.isSupported == true
[ ] key generation succeeds
[ ] challenge issued
[ ] real Apple attestation accepted
[ ] registration visible in Upstash
[ ] assertion #1 accepted
[ ] assertion #2 accepted, counter advances
[ ] replayed assertion rejected        (Developer Tools)
[ ] tampered body rejected             (Developer Tools)
[ ] a real interpret request reaches GPT-5.6 and returns 200
```

When something fails, the server's `message` names the exact reason —
`environment_mismatch`, `app_id_mismatch`, `challenge_invalid_or_used`,
`counter_replay`, `assertion_signature_invalid`. Read it before theorising.

### Supported vs. unsupported App Attest device

Every current-generation test device is expected to support App Attest, but
the fallback path is part of the contract
(`AppIntegrityProvider.swift`'s `UnavailableAppIntegrityProvider`,
`IntelligenceHTTPClient.integrityProvider()`) and has never been exercised
on real hardware. Confirm the happy path above on a supported device, then
confirm the refusal behavior does not need real unsupported hardware to
prove — it is deterministic given `requiresAttestation`:

```text
[ ] on the test device, AppAttestIntegrityProvider.isSupported == true
    (Developer Tools already surfaces this — see the Debug harness section)
[ ] if isSupported were false with attestation required, the client selects
    UnavailableAppIntegrityProvider and every request fails closed to
    IntelligenceError.unavailable — confirm by reading the selection logic
    in IntelligenceHTTPClient.integrityProvider(), not by hunting for
    unsupported hardware
[ ] a refused/unavailable integrity request never becomes an unattested one
    (no silent downgrade to DevelopmentAppIntegrityProvider on a build with
    requiresAttestation == true)
```

This is a code-reading confirmation, not a new device requirement — PackWise
has no unsupported-but-otherwise-current device to test against, and the
production code path never falls back to development trust regardless of
support. Record which device/iOS version was used and that
`isSupported == true` on it.

---

## 2. First launch

```text
[ ] clean install
[ ] onboarding renders correctly
[ ] no signup
[ ] no notification permission prompt
[ ] no location permission prompt
[ ] no unexpected permission dialogs
[ ] app renders light even with the system in dark mode
    (dark is intentionally disabled as of 2026-08-31)
[ ] no layout clipping
[ ] navigation feels native
```

---

## 3. Trip creation

### Solo — Chicago, 5 days, city trip, sightseeing, carry-on, balanced

```text
[ ] MapKit destination search
[ ] dates
[ ] timezone correct
[ ] activities
[ ] bag and style prefill from Me
[ ] review screen
[ ] Build My Packing List
[ ] opens Trip Detail directly
```

### Couple

```text
[ ] partner creation
[ ] personal items split correctly
[ ] shared section
[ ] dynamic party tabs
[ ] carrier assignment
```

### Family — 2 adults, 1 toddler

```text
[ ] toddler quantities differ from adult
[ ] kid items appear
[ ] no diapers unless the need was selected
[ ] shared items do not multiply per traveler
[ ] guardian ownership and carrier behave correctly
```

---

## 4. Packing list

Use it the way a traveller would, not the way its author would.

Trip Detail is an overview: the checklist is reached through a category row
or **See All**.

```text
[ ] Trip Detail hero, progress, weather strip, category summary
[ ] a category row opens the list at that category
[ ] See All opens the whole list
[ ] check / uncheck
[ ] quantity editing
[ ] search
[ ] category counts
[ ] All / Left / Packed / Important
[ ] Hide Packed
[ ] add custom item
[ ] delete custom item
[ ] Not Needed
[ ] Why This?
[ ] party tabs
[ ] shared carrier selection
[ ] scrolling stays smooth on a large list
[ ] state survives force-close and relaunch
```

Two rules to confirm explicitly, because they are the ones users notice when
broken:

```text
[ ] Not Needed is not Delete
[ ] a rejected item never silently returns
```

---

## 4a. Item Detail — Recommendation Trace (Phase 8)

New since this checklist was last written. Phase 8 wired
`RecommendationTrace` — a pure read over generation-time facts, never a live
re-derivation — into Item Detail's "Why it's on your list" card
(`ItemDetailView` in `PackingListView.swift`). No live simulator screenshot
was taken for this change either (recorded in the Phase 8 exit doc,
Finding 8); this is the first real look at it on any screen, simulator or
device.

Open Item Detail for one item of each of these four kinds, in the same
trip, and confirm the authority line matches exactly — present only where
the user, not the engine, made the decision:

```text
[ ] a plain engine-recommended item (never touched) — no authority line
    above the main reason text
[ ] an item whose quantity you changed by hand (the Stepper on this same
    screen) — "You changed this."
[ ] a user-added canonical item (added via Add Item, picked from the
    catalog) — "Added by you."
[ ] a custom item (added via Add Item, typed rather than picked) —
    "Added by you."
```

Then confirm the rest of the card still renders correctly underneath the
authority line — these fields are untouched by Phase 8 but share the same
card and are worth reconfirming on real hardware and real font sizes:

```text
[ ] the main reason text is present and legible
[ ] "Why this quantity" appears when the item has a quantity reason, and
    reads correctly (not truncated, not a raw key)
[ ] source-signal chips wrap correctly at default and accessibility Dynamic
    Type sizes (PackWiseFlowLayout)
[ ] the authority line, when present, sits above the main reason text and
    does not crowd it at accessibility sizes
```

No engine or trace logic changes here — if something reads wrong, record it
as a finding; do not edit `RecommendationTrace.swift`, `PackingEngine.swift`,
or the reasons content to make it look better.

---

## 5. Edit trip

Set up a list that has something to lose:

```text
pack several items
change a quantity by hand
add a custom item
mark something Not Needed
```

Then change dates, activities, bag, style, and party details.

```text
[ ] additions selected by default
[ ] quantity changes selected
[ ] removals off by default
```

Apply, then confirm nothing was trampled:

```text
[ ] packed state preserved
[ ] custom item preserved
[ ] manual quantity preserved
[ ] Not Needed preserved
[ ] traveler ownership preserved
[ ] carrier assignment preserved (owner and carrier stay distinct — the
    Phase 8 regression case: a shared item still assigned to the same
    carrier, not silently reset)
```

This is Phase 7/8's user-authority guarantee — `causallyDiffers(from:)`
refreshes only causal fields (reason, quantity reason, trace facts) on
regeneration and never touches packed state, manual overrides, Not Needed,
or ownership/carrier — proven in the unit/simulator suite
(`RegenerationProvenanceTests`) but not yet on a real device or across a
real process relaunch. Force-close and relaunch the app **between** editing
the trip and re-checking the list above, not just after — a bug that only
shows up after a fresh process launch (stale in-memory state masking a
persistence gap) would not be caught by checking within the same session:

```text
[ ] force-close and relaunch after Apply, before re-checking the six items
    above — all six still hold after the relaunch, not just before it
```

---

## 6. Real WeatherKit

This closes M2's outstanding device item.

```text
[ ] real temperatures for the trip dates
[ ] coverage matches the trip window
[ ] correct timezone
[ ] Apple Weather attribution wherever weather appears
[ ] Packing Impact reflects the forecast
[ ] Why This? agrees with Packing Impact
[ ] family weather impacts collapse correctly
[ ] reopening the trip uses the cache rather than refetching
```

Then a far-future trip:

```text
[ ] forecast unavailable falls back to seasonalOnly
[ ] no invented precision
```

---

## 7. Weather change

```text
[ ] "Weather changed" appears        (Developer Tools)
[ ] review changes
[ ] additions on, removals off
[ ] Keep List dismisses the proposal
[ ] Keep List does NOT create Not Needed overrides
[ ] adding a proposed item manually removes it from the proposal
[ ] a stale proposal invalidates
[ ] packed, custom, manual quantity, and Not Needed all survive
```

---

## 8. Packing Impact

```text
[ ] rain — layers and umbrella, with the day count
[ ] cool evenings — a light layer
[ ] high UV — sun protection
[ ] no meaningful weather impact — the card disappears entirely, no empty card
```

---

## 9. Intelligence, on real hardware

**Note enrichment is gated off until M3B** (`ContextIntelligenceGate`,
2026-09-01 audit): the model's output was reaching persisted trip data with
no acceptance step. On device, a trip note must therefore change nothing:

```text
[ ] a note like "lots of walking, one fancy dinner" is stored on the trip
[ ] it adds no activities and no chips — the list is the same with and
    without it
[ ] the UI never says GPT, AI, LLM, model, or a confidence number
```

The live interpret endpoint is still exercised — by the App Attest happy
path in section 1 and the Developer Tools probes, which call it directly.
That verifies the wire, not the wiring; the wiring returns with M3B's
acceptance step and traveler-attribution guard.

Then break the network:

```text
[ ] airplane mode — the deterministic list still builds
[ ] no "AI unavailable" alert during generation
[ ] nothing is lost or regenerated destructively
```

---

## 10. Lifecycle

```text
Create → Generate → Edit → Pack → Complete → Past
```

Force-close and reopen between each stage.

```text
[ ] progress persists
[ ] completed trip appears in Past
[ ] no status regression
[ ] no duplicate trips
```

---

## 11. Me

```text
[ ] home country
[ ] units
[ ] default bag
[ ] default style
[ ] habits
[ ] a new trip actually prefills from these defaults
[ ] Fahrenheit / Celsius
[ ] imperial / metric
```

---

## 12. Accessibility and visual QA

On the device, not the simulator.

```text
[ ] light mode
[ ] system dark mode does not leak into the app (dark is locked off)
[ ] larger Dynamic Type
[ ] VoiceOver on the major controls
[ ] Reduce Motion
[ ] landscape where supported
[ ] long destination names
[ ] long traveler names
[ ] empty states
[ ] a very large packing list
[ ] keyboard behaviour
[ ] sheets dismiss correctly
[ ] no clipped buttons
[ ] 44pt tap targets
[ ] colour is never the only status indicator
```

---

## 13. Failure states

Deliberately break each dependency:

```text
[ ] WeatherKit unavailable
[ ] intelligence API unavailable
[ ] backend 500
[ ] OpenAI timeout
[ ] MapKit search failure
[ ] no weather coverage
[ ] App Attest failure
```

In every case:

```text
[ ] packing remains usable
[ ] local data remains intact
[ ] errors are quiet and useful
[ ] no destructive regeneration
```

---

## Debug harness

Three checks cannot be performed by hand, so **Me → Developer Tools** provides
them. The screen and everything it links to are inside `#if DEBUG`, verified
absent from a Release build:

```text
DeveloperToolsView      0 occurrences in the Release binary
DebugAttestProbe        0
DebugWeatherInjection   0
"Developer Tools"       0
```

```text
App Attest
  Run happy path          registers and makes one accepted assertion
  Replay last assertion   sends the same assertion twice; the second must fail
                          with counter_replay
  Send tampered payload   signs body A, sends body B; must fail with
                          assertion_signature_invalid

Weather
  Inject weather change   stores a fixture snapshot and reconciles it through
                          the same path a real refresh uses, so the result is a
                          real WeatherChangeProposal
```

The replay and tamper probes send deliberately invalid requests to the **normal**
verifier — the server is never relaxed to make them pass. The weather injection
goes through `MockWeatherService` normalization, `repository.storeWeather`, and
`WeatherChangeReconciler`, so nothing about the resulting proposal is fabricated
UI state.

Pick a forecast scenario materially different from the trip's current one; the
tool reports honestly when the signals did not differ enough to propose
anything.

## Gate

### Current-HEAD anchor — f92eda8, 2026-09-04

Product Hardening Phases 1–8 are closed at `f92eda8`. Both open device
checkboxes below (`Physical-device App Attest — development`,
`Full physical-device UI/UX pass`) are evaluated against **this** commit,
not the 2026-09-03 entry immediately below, which predates Phase 8's Item
Detail trace change and was itself superseded by a sequencing decision
rather than a device result (see that entry's own note). Concretely, this
means:

```text
[ ] the physical-device pass includes section 4a (Item Detail
    Recommendation Trace) — not present at the 2026-09-03 evidence date
[ ] the physical-device pass includes the strengthened section 5 checks
    (force-close/relaunch between edit and re-verification, explicit
    carrier-assignment persistence)
[ ] the physical-device pass includes the unsupported-device App Attest
    confirmation in section 1
[ ] App Attest infrastructure itself (iOS AppIntegrityProvider /
    IntelligenceHTTPClient, API integrity + store layers) is unchanged
    since the 2026-08-30 m3a2-verification-runbook.md evidence — confirmed
    by git history on every file listed in that runbook's grounding —
    so that evidence is not re-run, only the physical-device steps it left
    open
```

Record the device, iOS version, and app build/commit hash actually
installed for this run. If the installed build's commit differs from
`f92eda8`, name the actual commit in the evidence and note the delta rather
than silently treating it as equivalent.

### Simulator UI refinement evidence — 2026-09-03

This evidence closes the simulator half of the UI refinement pass. It does not
substitute for any physical-device checkbox above.

```text
[x] Debug simulator build — iPhone 17 Pro / iOS 26.3.1
[x] Automated suite — 143 tests in 15 suites
[x] Full screenshot harness — 29 states × 3 variants = 87 PNGs
[x] Light comparison reviewed
[x] System-dark comparison reviewed — app correctly remained locked light
[x] Accessibility-large comparison reviewed
[x] Reference-board comparison reviewed
[x] Focused recapture after accessibility corrections
[ ] Physical-device UI/UX pass
[ ] Physical-device App Attest — development
```

Evidence locations for this run:

```text
Screenshots: /tmp/packwise-ui-freeze-2026-09-03
Light contact sheet: /tmp/packwise-ui-freeze-2026-09-03-light-contact.png
Locked-dark contact sheet: /tmp/packwise-ui-freeze-2026-09-03-dark-contact.png
Accessibility contact sheet: /tmp/packwise-ui-freeze-2026-09-03-xl-contact.png
Test result bundle: /tmp/PackWise-UI-Freeze-Final-2026-09-03.xcresult
```

Final simulator observations:

```text
- The welcome image fills the display and the bottom action remains readable.
- Setup Back and Next controls remain flat and readable at accessibility size.
- Selected and custom activities share one chip flow.
- Maui uses a designed graphical fallback rather than a generic location tile.
- Zero-packed lists read "Packing list ready" without an empty progress track.
- Trip Detail shows precise and seasonal weather states and five category rows.
- Both Trip Detail hero controls remain visible at accessibility size.
- Packing List rows remain below opaque pinned chrome in top and scrolled states.
- Item Detail renders as medium/large sheets with truthful quantity evidence.
- Add Item uses a nested category selector with a visible selection checkmark.
- Me preference values no longer break into fragments at accessibility size.
```

`python3 scripts/validate_shared.py` was not run: this pass did not modify
`shared/`, catalog data, or packing rules.

Connected-device audit on 2026-09-03 found the paired iPhone 17 Pro Max, but
Xcode reported it unavailable and advised unlocking/attaching it or restoring
same-network Developer Mode connectivity. The product owner subsequently
deferred the physical-device pass and authorized deterministic Product
Hardening Phases 1–8 after the simulator-verified presentation baseline commit.
This is a sequencing decision, not verification: the two device checks remain
open, no device-verified tag is created, and M3B/M3C remain blocked until the
M3A device exit gate is green.

This pass covers Apple's **development** App Attest environment. A locally
signed build cannot exercise the **production** environment — TestFlight and the
App Store always use production regardless of the entitlement — so that remains
genuinely unverified and is recorded as future distribution verification rather
than a release gate.

```text
[x] Live OpenAI Structured Outputs           2026-08-30
[x] Live eval — 18/18                        2026-08-30
[x] Real Redis                               2026-08-30
[x] Production Vercel deployment             2026-08-30
[ ] Physical-device App Attest — development
[ ] Full physical-device UI/UX pass

TestFlight production App Attest
  → deferred to actual App Store distribution
  → does not block M3B
```

When the two device items are green — evaluated against `f92eda8` per the
Current-HEAD anchor above, including section 4a and the strengthened section
5 checks — **M3A verified for the current development scope**, and M3B
unlocks. Phase 9 and M3B/M3C stay explicitly blocked until then; this
checklist prepares the steps and evidence format, it does not itself close
the gate.
