# PackWise — Round 2 Fixes (product-grounded)

Supersedes the earlier round-2 list. Two rulings in it were wrong, because they were derived from the visual sheet alone without the product spec. Those are corrected first.

**Authority order from here on:**

1. The product spec (this document's source) — decides *behavior, structure, and intent*
2. The 10-screen sheet — decides *visual treatment* where the spec is silent
3. Neither — derive from the rules, don't invent

The sheet is a marketing mock of ten screens. It is not the product.

---

## Corrections to previous rulings

### C1. "Every screen composes from PWCards" was wrong for the Packing List

The spec is explicit:

> The design is intentionally closer to **Apple Reminders** than a stack of giant cards.

AGENTS.md non-negotiable 7 was **product intent**, not legacy drift, and retiring it was a mistake — mine. The correct answer was the "Hybrid" option: cards for Trip Detail sections, trip cards, and setup summaries; **plain Reminders-style rows inside the Packing List screen**.

**Action:** restore non-negotiable 7 in AGENTS.md, scoped: *"The full Packing List uses plain grouped rows, not cards. Cards are for emphasis surfaces — Trip Detail sections, trip cards, setup summaries."* Note in the doc that the sheet governs visual treatment but not this structural choice.

The current Packing List is already Reminders-style, so no code change — but the contract needs to say so, or a future pass will "fix" it back into cards.

### C2. The gold star was wrong, and it caused the checkbox bug

The spec says:

> Internally items can have importance such as Critical, Important, Normal, Optional. […] critical essentials might use an **orange warning glyph**.

The gold star came from an archived sheet. Your original orange `(!)` was closer to intent. And replacing the leading control with any importance glyph created a real bug.

**Correct structure — the importance indicator never occupies the checkbox slot:**

```
[○ checkbox]  Item name              ×2   [!]
              reason line                   ↑
      ↑                              importance, trailing
  always present
```

- **Critical** → orange `exclamationmark.circle.fill`, trailing
- **Important** → same glyph, `accent`, trailing
- **Normal / Optional** → nothing

Right now `Keys`, `Phone`, `Wallet`, `Photo ID`, `Rain jacket`, `Toothbrush`, `Toothpaste`, `Deodorant`, `Daypack`, `Walking shoes`, and `Portable charger` all render a star where the checkbox should be — **none of them can be packed.** This is the highest-priority fix in this document.

### C3. Locking to light-only may have regressed a shipped feature

The spec lists **"light/dark/accessibility UI system"** under *Built*. Round 1 locked `.preferredColorScheme(.light)` and marked "Dark Mode from day one" superseded in AGENTS.md.

That was my recommendation and your call, and it was reasonable given there's no dark reference — but it's worth being explicit that this **turned off a working feature**, not deferred an unbuilt one.

**Options:**
- Keep the lock, and write a dated line in AGENTS.md saying dark mode is intentionally disabled pending a dark reference sheet
- Or restore dark mode by giving each token a dark counterpart and accepting that dark has no sheet to check against

Don't leave it silently off with no note. Someone will find the dead code in three months and wonder.

---

## 1. Trip Setup → full-screen navigation

Unchanged from the previous list, and the spec strengthens it: this is the product's primary flow, eight steps, and the thing every new user does first. It is currently presented as a modal sheet — gray backdrop, rounded corners, parent bleeding through.

**Change:** `.fullScreenCover` containing a `NavigationStack`; push each step.

Add a thin 2pt `primary` progress bar under the nav bar tracking position across the eight steps. Not page dots — eight is too many.

**Nav bar:**
- Step 1: `Cancel` — `Next` (pill)
- Steps 2–7: `‹ Back` — `Next` (pill)
- Step 8: `‹ Back`, no `Next`; `Build My Packing List` is the full-width action

**Review screen grouping.** The spec groups the review into named sections rather than a flat eight-row list:

```
[destination hero]

Your trip        Vacation · Just you
Activities       Swimming, Beach days
Packing          Not sure yet · Balanced
Preferences      <selected context chips>
```

Current implementation is a flat 8-row card. Regroup to match.

---

## 2. Review Changes → pushed screen, with all three sections

Currently a bottom sheet showing **only additions**. The spec requires three sections with different default states:

| Section | Default |
|---|---|
| **Add** | selected |
| **Quantity changes** | selected |
| **Remove** | **off — user must deliberately approve** |

Your dev tool reported "2 removal candidate(s)" and the UI has never once shown a removal. Either the removal path isn't wired to the view, or it's filtered. This is a correctness gap, not a styling one — a proposal engine that only ever adds will inflate every list over time.

**Structure (pushed screen, not a sheet):**
- Nav bar `‹ Back` — `Done`
- Headline `Review changes` + what triggered it
- Forecast-change summary: old signal → new signal
- **Add** — green `+` tile, name, reason, checkbox **on**
- **Quantity changes** — name, `5 → 4`, reason, checkbox **on**
- **Remove** — red `−` tile, name, reason, checkbox **off**
- `Apply changes` (primary) + `Keep list` (text link)

**Keep the Keep List semantics exact.** Per the spec, `Keep list` dismisses *this proposal only* and preserves the new forecast. It is **not** a per-item "Not Needed." Don't let the copy blur these — "Dismiss" or "Not now" would be wrong.

---

## 3. Packing list interaction — the real gap

Beyond the checkbox bug, the spec requires interactions that don't exist yet.

### Item Detail (push from any row)

Spec actions, which differ from what I listed last round:

- Quantity stepper
- **Change category**
- **Mark Not Needed** — records a recommendation override
- **Remove** — for custom items
- Later: *always bring* / *don't suggest again*
- `Why this?` — full reason prose, plus the contributing signals

Add a chevron on rows that have a reason so the affordance is discoverable.

### Not Needed vs Delete — these are different operations

This distinction is in the spec and has no UI at all today:

- **Not Needed** on a PackWise recommendation → stores an override. Regeneration and weather proposals must respect it.
- **Delete** on a custom item → row disappears, no permanent rejection recorded.

Swipe actions on the row should offer the right one based on item origin. Offering "Delete" on a generated recommendation would silently lose the override signal.

### Manual quantity edits are sticky

Spec: if the user changes `×5 → ×3`, that's a user decision, and a later weather refresh or trip edit **must not overwrite it**. Confirm the override is persisted and respected in `recommendationDiff()`.

---

## 4. Quantity engine is ignoring laundry and style

Not a design issue, but visible in the screenshots and worth fixing before more UI work.

A 15-day Tokyo trip is producing `T-shirts ×15`, `Socks ×16`, `Underwear ×16`, `Pants ×6`. That's the naive duration formula. The spec says:

> It does not simply do: trip = 5 days therefore shirts = 5. It considers duration + packing style + laundry availability + baggage + item reuse + activity needs + weather.

And gives the worked example: six days, carry-on, light, laundry available → **shirts ×4, not ×6**.

The user toggled `Laundry` during setup and the quantities didn't move. Either the laundry signal isn't reaching the quantity engine, or the engine has no laundry term. Also check that `Balanced` and bag choice are actually modulating output.

This matters more than it looks: `×16 socks` for a carry-on trip undermines the core claim that PackWise packs for *this* trip.

---

## 5. Trips Home — missing the Current state

The spec defines **three** sections:

```
Upcoming    trips you're preparing for
Current     a trip happening now, when relevant
Past        completed trips
```

Only Upcoming and Past exist. Add Current, shown only when a trip's date range contains today. A trip in progress is a different mental state from one you're preparing for, and it should sort to the top.

**Hero card is also missing its progress block.** Per spec and sheet, the card shows packed count, percentage, green bar, and items-left. Yours shows only `Forecast closer to departure` and `Packing list ready`.

---

## 6. Trip Detail — show all categories

The spec describes the category overview listing every category with progress, then `See All` for the full checklist. It does not describe truncation.

Remove the `N more categories` link and render all of them. `See All` in the section header already covers the full-list path; having both is redundant.

---

## 7. Onboarding — two-zone layout

Screen 1 in the reference is two zones. Yours is one.

- **Top ~40%:** white, blue briefcase + `PackWise`, headline in **dark** text, gray subtitle
- **Bottom ~60%:** photo, three benefit rows in white over it, blue CTA, dots

Yours runs the photo full-bleed and stacks logo + headline + subtitle + benefits + CTA into the bottom third in white. Split it. The status-bar luminance problem disappears as a side effect, since the top becomes white.

**Screens 2 and 3 end around 55–60% with a large void.** Scale card padding, row height, and inter-card spacing up so the content group fills the available height. Don't add a third card — the two-cards-and-an-arrow structure *is* the teaching device on screen 2.

**Copy check against the spec:** no mention of AI, GPT, models, or algorithms anywhere in onboarding. Current copy passes. Keep it that way in every future screen — the spec is firm that users see "PackWise suggests," never "AI-powered."

---

## 8. Empty state

- Lift the group to ~40% of screen height; it's currently centered in the full frame with dead space above
- `New Trip` should be a **compact pill**, not full-width — an invitation, not a form submit
- Hide the top-right `+` in the empty state; two competing actions for one job
- The illustration should read as travel, not a lone briefcase

---

## 9. Me — units conflict

The spec has **two** unit preferences (temperature F/C, distance & weight Imperial/Metric). The sheet shows **one** row. Round 1 merged them into `Fahrenheit · Miles`.

Resolution: keep the single summary row per the sheet, but make it push to a detail screen with both controls. Summary shows the combined value; the underlying model keeps two settings, as the spec requires.

---

## 10. Smaller items

- **FAB overlaps content** — `Socks ×16` and `T-shirts ×15` sit under the blue `+`. Add bottom inset = FAB height + 24pt.
- **Forecast day ordering** — `Rain likely Wed, Mon, Sat` is unordered. Sort chronologically.
- **Contradictory weather copy** — header reads `Mild days, rain Saturday, cool evenings` while the card below says `Rain Wednesday`. The summary string isn't regenerating from the current snapshot. Given the spec's insistence that PackWise never fakes precision, a stale summary is worse than no summary.
- **Quantity badges** should be styled badges, not plain gray text.
- **Verify Complete Trip is reachable** from the `•••` menu — the lifecycle depends on it and I haven't seen it.

---

## Imagery — gate it, don't necessarily cut it

I said "cut Look Around." The spec actually names it as the intended middle tier:

> Destination → Look Around when useful → Map / graphical fallback

and already anticipates the problem:

> MapKit can sometimes return technically correct but visually boring imagery.

The Tokyo hero is exactly that — a street-level grab of glass office doors, now the hero on three screens.

**Revised recommendation:** keep the tier, add a gate. Only use Look Around when the coordinate resolves to a recognized POI or landmark rather than a raw city centroid. Everything else falls through to the branded panel. Then fill the bundled catalog — 20 cities covers most real use, and bundled always wins.

---

## Explicitly out of scope for this round

Per the spec's own milestone split, don't let the agent drift into: notifications, Final Check, post-trip review, Packing Memory, Ask PackWise, pack-lighter, packing-gap detection, outfit planner, bag weight, widgets, iCloud sync, collaboration.

---

## Order of work

| # | Item | Why here |
|---|---|---|
| 1 | Checkbox / importance glyph (C2) | Functional bug — a third of items can't be packed |
| 2 | Restore Reminders-row contract (C1) | Prevents the next pass undoing it |
| 3 | Trip Setup → full-screen nav | Primary flow, fixes several layout complaints at once |
| 4 | Item Detail + Not Needed / Delete | Unblocks quantity, category, overrides |
| 5 | Review Changes → screen, all three sections | Correctness gap, not just presentation |
| 6 | Quantity engine: laundry / style / bag | Undermines the core product claim |
| 7 | Onboarding two-zone + fill | Highest-visibility screens |
| 8 | Current section, hero progress, all categories | Structural gaps vs spec |
| 9 | Empty state, FAB inset, units detail | |
| 10 | Weather copy/ordering, imagery gate | |
| 11 | Dark-mode decision recorded in AGENTS.md (C3) | Don't leave it silently off |

Still no commits.
