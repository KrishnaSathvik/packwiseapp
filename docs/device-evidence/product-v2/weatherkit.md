# Current-trip WeatherKit — device evidence (Task 14)

Raw observations first, ruling second. Every value below is a coordinate, a
date, a timezone identifier, a build path, or an error domain/code. No trip
notes, no secrets.

## 1. Physical-device reproduction — 2026-09-08

**Scenario.** Chicago, Sep 8 – Sep 12, created on Sep 8 (trip begins on the
device's current day). No Developer Tools fixture injection before the
observation.

**Observed on Trip Detail immediately after creation:**

```text
Forecast closer to departure
Your list currently uses seasonal conditions for Chicago.
```

**What that copy proves.** The second line is produced only by
`TripDetailView.pendingWeatherDetail(nil)` — the branch taken when the trip
has **no stored weather snapshot at all**. The far-future seasonal path is a
different branch: it stores a `source == .seasonal` snapshot and renders its
`coverageCopy` ("… seasonal conditions and trip details"). A missing snapshot
after creation means `TripWeatherResolver` returned
`ResolvedTripWeather(state: .unavailable, snapshot: nil)`, and the only route
to that with no cache is `WeatherAvailability.unavailable`, which
`WeatherKitWeatherService.availability` returns **only when the provider
client throws**. So the device symptom is a thrown provider error, not date
gating and not a seasonal decision. The wording was misleading (see §5).

**Which build was on the phone.** Xcode DerivedData on this Mac:

```text
PackWise-gjgrxhcrpivxvycrgrwqbwbyybag
  WorkspacePath = /Users/…/packwiseapp/ios/PackWise.xcodeproj      ← main worktree
  Build/Products/Debug-iphoneos/PackWise.app   2026-09-08 09:09
PackWise-chnkdfkziubxxibfkdnndqhcgktp
  WorkspacePath = …/worktrees/packwiseapp/product-v2-stage-a/ios/…  ← Task 14 branch
  last simulator products 2026-09-04
```

The device build came from `main`, which does **not** contain
`WeatherRequestDiagnostics.swift` (it exists only on `product-v2-stage-a`).
So no diagnostics envelope could have been captured on the phone for this
run. `main`'s live weather code is functionally identical to the branch
(the branch only extracts `queryBounds` and adds Debug diagnostics), so the
device behaviour is representative of the current path.

**Device app signing (from the built product):**

```text
application-identifier                          766WG2GGCA.com.packwiseapp.app
com.apple.developer.weatherkit                  true
com.apple.developer.devicecheck.appattest-environment  development
```

**Provisioning profile on this Mac for the App ID** (created 2026-08-30,
`iOS Team Provisioning Profile: com.packwiseapp.app`):

```text
Entitlements.application-identifier     766WG2GGCA.com.packwiseapp.app
Entitlements.com.apple.developer.weatherkit   true
```

Entitlement and profile are correct on the app side.

**Later on the same device:** Developer Tools → *Meaningful rain* → *Inject
weather change* produced a synthetic forecast (Tue 78/61 … Sat 76/62) and a
three-addition weather-change proposal (light sweater, rain jacket, compact
umbrella). That is fixture data (`ChicagoRainyFall`, source `.fixture`),
rebased onto the trip's dates by `DebugWeatherInjection.rebase`. It is
evidence that reconciliation works on hardware; it is **not** evidence about
WeatherKit and must not be compared against Apple Weather.

## 2. Entitled-simulator reproduction of the live provider — 2026-09-08

Branch `product-v2-stage-a`, Xcode 26.3, iPhone 17 Pro simulator, built with
`DEVELOPMENT_TEAM=766WG2GGCA`. The simulator binary's `__TEXT,__entitlements`
section carries `766WG2GGCA.com.packwiseapp.app` and
`com.apple.developer.weatherkit`, i.e. the same identity and entitlement as
the device build. A throwaway test called `LiveWeatherKitClient.fetch` and
`WeatherKitWeatherService.availability` for the Chicago catalog destination
with a trip starting on the simulator's current day (probe removed before
commit).

```text
dest=Chicago lat=41.8781 lon=-87.6298 tz=America/Chicago
deviceTZ=America/Chicago now=2026-09-08 14:23:01 +0000
start=2026-09-08 05:00:00 +0000 end=2026-09-12 05:00:00 +0000

[AuthService] Failed to generate jwt token for: com.apple.weatherkit.authservice
  with error: Error Domain=WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors Code=2 "(null)"

THROWN domain=WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors code=2 userInfo=[:]
availability=unavailable
```

Diagnostics envelope staged by `WeatherKitWeatherService` for that call:

```text
WeatherRequestDiagnostics @ 2026-09-08T14:23:02Z
source: live WeatherKit refresh
destination: Chicago (41.8781, -87.6298) tz=America/Chicago
device: tz=America/Chicago calendar=gregorian
requested: 2026-09-08T05:00:00Z … 2026-09-12T05:00:00Z
normalized: [2026-09-08T05:00:00Z, 2026-09-13T05:00:00Z)
fetchAttempted: true
provider: thrown days=0 coverage=[—, —]
providerMetadata: fetchedAt=— expiresAt=—
providerError: WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors#2
finalState: unavailable
engineReceivedPreciseWeather: false
```

The same identical error was logged a second time for the alerts query.

## 3. What the evidence rules in and out

| Candidate cause | Verdict | Evidence |
| --- | --- | --- |
| Trip-save fetch not firing | Ruled out | `TripSetupView.saveTrip` resolves weather before insert; `TripDetailView.task` refreshes again on open. Simulator run shows `fetchAttempted: true`. |
| Forecast horizon / date gate | Ruled out | Trip start is day 0 from `now` in the destination calendar; `isBeyondDailyHorizon` is false, `skipReason` is nil. |
| Device/destination timezone normalization | Ruled out for this repro | Device and destination are both `America/Chicago`; normalized bounds are the destination midnights `[Sep 8 05:00Z, Sep 13 05:00Z)`, exactly the trip's five days. (The latent cross-timezone risk documented in `deviceAnchoredMidnightCanLandOnADifferentDestinationDay` is untouched by this evidence and remains a separate, unproven thread.) |
| **WeatherKit request failing** | **Confirmed** | Provider throws `WDSJWTAuthenticatorServiceListener.Errors` code 2 — "Failed to generate jwt token for com.apple.weatherkit.authservice" — before any forecast is returned. Reproduced on an entitled simulator build; consistent with the entitled device build's nil-snapshot symptom. |
| Response discarded during normalization | Ruled out | No response exists to normalize (`days=0`, `normalization: nil`). |
| Cache/state not persisted | Ruled out | Nothing to persist; `.unavailable` with no cache correctly stores no snapshot. |
| Presentation | Contributing defect | A nil snapshot rendered as "Forecast closer to departure", the far-future wording, which hid a provider failure on a same-day trip. Fixed in §5. |

## 4. Root cause and required action (outside the codebase)

`WDSJWTAuthenticatorServiceListener.Errors` code 2 is the on-device weather
daemon failing to mint the JWT that authorizes the App ID against Apple's
WeatherKit service. It is raised even when the entitlement is present in the
binary and the profile. The documented causes are:

1. WeatherKit is enabled for the App ID under **Capabilities** (which Xcode
   automatic signing does, and which is why the profile carries the
   entitlement) but **not** under the App ID's **App Services** tab in
   Certificates, Identifiers & Profiles. Without that toggle JWT generation
   always fails.
2. The App Services toggle was flipped recently and Apple's backend has not
   propagated it yet (commonly quoted as up to ~30 minutes, sometimes longer).
3. Apple-side entitlement sync for the App ID is broken and needs a
   developer-support ticket; Apple has resolved reports with exactly this
   signature by fixing it on their end.

Sources: Anup D'Souza, "Fixing WeatherKit JWT Authentication Errors"
(https://www.anupdsouza.com/blog/weatherkit-jwt-auth-error); Apple Developer
Forums thread 786126, "WeatherKit JWT fails (WDSJWTAuthenticatorServiceListener
Code 2) despite entitlement" (https://developer.apple.com/forums/thread/786126).

**Action for the account holder (team 766WG2GGCA, App ID
`com.packwiseapp.app`):** in Certificates, Identifiers & Profiles → Identifiers
→ `com.packwiseapp.app`, confirm WeatherKit is checked under **both**
Capabilities and **App Services**, save, then in Xcode → Settings → Accounts →
Download Manual Profiles, clean, and reinstall. If it is already enabled in
both places, wait for propagation and retry; if it still fails, file the
Apple Developer Support request with the error line above. No source change
can make this request succeed.

## 5. Code changes supported by this evidence (branch `product-v2-stage-a`)

- `TripWeatherRefresh.resolveForSetup` — the trip-creation/edit path now
  commits its diagnostics entry instead of leaving it staged, so the very
  first live attempt for a new trip appears in Developer Tools.
- `TripDetailWeatherCopy` — a trip with no snapshot reads
  "Forecast isn't available right now / PackWise couldn't reach the forecast.
  Your list uses seasonal conditions for Chicago until it can." The
  far-future seasonal snapshot keeps "Forecast closer to departure". A
  provider failure is no longer dressed as a date decision.
- Developer Tools: section **Test Forecast**, scenarios **… Fixture**, button
  **Inject Test Weather**, footer "Synthetic weather used only to test
  weather-change reconciliation. Not live WeatherKit data." Weather card and
  Weather screen show a Debug-only **TEST WEATHER** badge while a fixture
  snapshot is in place.
- Regression test `currentDayTripInAnotherTimezoneRecordsProviderAuthFailure`:
  same-day trip, device calendar America/Chicago, destination Asia/Tokyo,
  provider throwing the exact domain/code above, through the setup path.

Not changed: query bounds, normalization, horizon, cache policy, fallback
semantics, Phase 6 thresholds, packing rules, reconciliation.

## 6. Device recheck procedure (Task 14 stays open until this passes)

1. Complete §4 in the developer portal first.
2. Build the **`product-v2-stage-a` worktree** for the iPhone (not `main`),
   with the team set for signing. Only this branch carries the diagnostics.
3. Create Chicago, starting today, four nights. Do **not** inject a fixture.
4. Expected: Trip Detail shows a real high/low strip and Apple Weather
   attribution, no TEST WEATHER badge. If it instead shows "Forecast isn't
   available right now", open Developer Tools → Weather diagnostics → Copy
   all, and paste it here. The `providerError` line names the failure.
5. Record the result below.

### Recheck log

| Date | Build | Result | providerError | Notes |
| --- | --- | --- | --- | --- |
| 2026-09-08 | main @ f2d2a88 (Debug-iphoneos) | ❌ no snapshot | not captured (build lacked diagnostics) | simulator repro: WDSJWTAuthenticatorServiceListener.Errors#2 |
