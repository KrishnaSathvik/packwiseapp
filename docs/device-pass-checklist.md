# PackWise Device Pass

One comprehensive pass on a real iPhone, covering both halves of what is still
unproven: the App Attest path against Apple's development environment, and the
product itself under a real finger on real hardware.

Everything below runs against a **Debug** build pointed at
`https://packwiseapp-dev.vercel.app` (App Attest, Apple development
environment). Production stays on `production` and is not touched.

TestFlight is deferred — see the gate note at the end.

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

---

## 2. First launch

```text
[ ] clean install
[ ] onboarding renders correctly
[ ] no signup
[ ] no notification permission prompt
[ ] no location permission prompt
[ ] no unexpected permission dialogs
[ ] light and dark mode both correct
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

```text
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

Use a real note:

> Going to Tokyo, lots of walking, one fancy dinner, I'll work out twice, and I
> get cold easily.

```text
[ ] interpretation yields walking, niceDinner, usuallyWorkOut, getColdEasily
[ ] the UI never says GPT, AI, LLM, model, or a confidence number
[ ] it still reads like PackWise
```

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
[ ] dark mode
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

When the two device items are green: **M3A verified for the current development
scope**, and M3B unlocks.
