# Product Experience V2, Task 8.1 — setup UX closure and device-model cleanup

Date: 2026-09-15 · Branch: `product-v2-stage-a` · Baseline: `cefc52b` (Task 8)

## 1. One device model

| Traveler | Phone | Every other device |
| --- | --- | --- |
| You | implicit (`phoneOwnership`: phone, phone charger, car charger) | explicit choice in About you → **Devices you're bringing** |
| Adult / partner / teen | explicit (`bringingPhone`) | explicit choice in their traveler card |
| Younger child | none offered | none offered |

- **New traveler device signals:** `bringingHeadphones`, `bringingPowerBank`, and `bringingCamera`, alongside Task 8's `bringingPhone` and `bringingTablet` and the existing `bringingLaptop`.
  - They live in `base.json` `traveler_device_chips`, on the traveler record. They are never trip chips and never in the Intelligence API chip vocabulary.
  - Generated API artifacts gained only three reason codes.
- **Eligibility.** `headphones → bringingHeadphones`; `power_bank → bringingPowerBank`; `camera`, `camera_charger`, and `memory_card → bringingCamera`.
  - `car_charger` moved to `phoneOwnership`: it charges the phone, and its output is unchanged.
  - The Task 7.2 interim branch is deleted: an item with no named signal reaches no one automatically, You included.
- **D2 narrowed.** A solo trip's Business/Work context counts as the solo traveler's `bringingLaptop` signal only. It never counts for headphones, a power bank, or a camera.
- **Solo generation** now also reads the primary traveler's own chips, so a chosen device with no other rule (a tablet) reaches a solo list.
- **Tests:**
  - `TripSetupDraftTests.primaryDeviceChoicesStayOnYouAndNeverBecomeTripContext`: each device choice gives exactly its items, choices persist on You and round-trip, and nothing leaks between You, Adult 1, and Adult 2;
  - `TravelerEligibilityTests.implicitPrimaryPhoneIsNotGenericDeviceOwnership`;
  - the solo/group ledger tests;
  - `ActivityContractTests` (photography and wildlife).

### Golden diff (vs `cefc52b`)

- **Rows:** 46 removed, all owned by You, across 38 fixtures:
  - `electronics.headphones` ×24;
  - `electronics.power_bank` ×19;
  - `electronics.camera`, `camera_charger`, and `memory_card` ×1 (fixture 52).
- **Everything else:** 0 added, 0 quantity changes, 0 trace, coverage, or constraint changes.
- **Eligibility ledger (67 changes):**
  - 47 new You records: `device_signal.bringingHeadphones` ×24, `.bringingPowerBank` ×19, `.bringingCamera` ×1 group covering the camera, charger, and card;
  - 9 partner and 6 child records now name the specific headphones or power-bank signal;
  - 8 older generic `device_signal_required` entries were removed.

### Consequences

- **Photography is context-only.** Its only content was camera gear, which is now the traveler's own choice; the surfaced-input contract says so.
- **Wildlife** keeps binoculars.
- **Trip-eval fixture.** `ReykjavikPhotography` no longer requires camera gear and now pins that photography alone never adds a camera. Its trip-level context cannot carry a traveler device choice.

## 2. Dynamic Type

- **`PackWiseFont`.** Every role uses a text style whose default is the old sheet size (title 28, headline 17, callout 16, subheadline 15, footnote 13, caption 12), plus `selectionGlyph` (title2, 22). The standard-size hierarchy is unchanged.
- **Scaled geometry.** `PackWiseIconBadge` and `PackWiseRowDivider` scale with `@ScaledMetric`, capped at 1.6×.
- **Shell and fields.** The shell's step count uses `microLabel`, and setup text fields use `rowTitle`.
- **`PackWiseDateRangePicker`.** The 7-column grid and weekday row cap at `.xxxLarge`, the weekday headers stay on one line, and the cell height scales.

## 3. Traveler names

- **Card headings** use `TripParty.positionLabel(for:)`: You, Adult 1, Child 1.
- **Name field.** The typed name appears only in the labeled Name field.
- **Outside the editor**, `label(for:)` shows the name, falling back to the position.
- **Test:** `travelerEditorHeadingsAreStructuralWhileNamesIdentifyEverywhereElse`.

## 4. Checkpoint V

- **Record:** `docs/device-evidence/product-v2/visual-reference-checkpoint.md`.
- **Sheets:** `checkpoint-v-setup-standard.png`, `checkpoint-v-setup-accessibility.png`, and `checkpoint-v-product-context.png` in the same folder.
- **New states:** `setupTravelersGroup` and `packingListFamily`. `M1LoopTests.checkpointVReferenceStatesAreAllCapturable` pins the inventory.

## Verification

- **iOS:** 517 tests pass. Clean Debug build with 0 warnings in the app and test targets.
- **Shared and Python:** shared validation passes; Python tests 121 OK; the strict trace audit is clean; the engine audit passes.
- **API:** preflight 141 pass.
