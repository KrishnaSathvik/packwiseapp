# Trip Creation

Do not use one giant form.

Use a progressive setup. The user should feel like they are describing their trip, not filling in a database record.

This document is the approved Product Experience V2 target. Implementation status (2026-09-14): trip types and bags are already sets in persistence, `TripContext`, fixtures, and the Intelligence API, but the shipped setup screens still select one trip type and one bag, and the engine consumes a selection only as a singleton, until Tasks 3–5 and 8 land. See [implementation-decisions.md](implementation-decisions.md).

Product Experience V2 uses one shared shell on every step: native Back/cancel, compact progress, title and helper, scrollable content, and a sticky bottom primary action. `Next` does not live at top-right.

V1 supports **one primary destination**. Multi-destination comes later.

## Step 1 — Destination

Headline: **Where are you going?**

Search placeholder: **Search city or destination**

Production search is MapKit. Persist displayName, city, region, country, countryCode, coordinates, and the **destination timezone from MapKit** — never the device timezone. `shared/fixtures/test-destinations.json` is test/preview/weather-fixture matching only. A map thumbnail is polish, not an M1 blocker.

Results example:

```text
Chicago, Illinois
Chicago Heights, Illinois
Chicago Midway Airport
```

Once selected, show:

```text
Chicago
Illinois, United States
```

A map thumbnail of the selected place is expected (see the design mock).

Internally store:

```text
displayName
city
region
country
countryCode
latitude
longitude
timeZone
MapKit identifier if useful
```

## Step 2 — Dates

Headline: **When are you going?**

Native date range selection.

Immediately derive both days and nights:

```text
Sep 12 → Sep 16

5 days
4 nights
```

Packing logic may use either days or nights. Persist both.

## Step 3 — Who's traveling?

Headline: **Who's traveling?**

```text
Just me
Me + partner
Family
Group
```

**Just me** adds no extra fields. Internally this is a `TripParty` with one adult.

**Me + partner**, **Family**, and **Group** share one traveler-details card per person besides you:

- **Adults** (the partner, or each other adult): optional name, **Devices** (Phone / Laptop / Tablet), the differences that matter (medication, contacts, workout, formal, cold), and a note.
- **Children**: optional name, age group (teen / child / toddler / infant), and the needs for that age. Only a **teen** is offered **Devices**; younger children never get device choices by default. No birth dates.

**Family** counts **Other adults** and **Children**; **Group** counts **Other adults** (at least one). You are implicit, so the count never includes you. Review reads unambiguously, e.g. `You + 3 adults` or `You + 1 adult, 2 children`. Empty names display stable positional labels — You, Adult 1, Adult 2, Child 1 — which never overwrite a name.

Device choices are traveler-scoped signals (`bringingPhone`, `bringingLaptop`, `bringingTablet`). PackWise never infers a device from age, from a Business trip, or from another traveler: you own a phone implicitly because PackWise runs on it; everyone else brings only what their card says. One device manages the list. Invites and realtime sync are later.

Shared trip context (destination, dates, weather, activities, bag, style) is not re-asked per person.

## Step 4 — Trip types

Headline: **What describes this trip?**

Helper: **Choose everything that applies.**

Initial types:

```text
Vacation
City Break
Beach
Business
Outdoor
Road Trip
Wedding / Event
Ski / Snow
Festival
Visiting Family
Other
```

Trip types are multi-select. At least one known type is required. Every selected known type contributes deterministic typed needs into one composition pipeline; there is no primary type and no per-type checklist. `Other` remains inert context unless a deterministic contract is approved.

## Step 5 — Activities

Headline: **What will you be doing?**

Suggested chips are the stable union from all selected trip types, but suggestion is not selection. Trip type changes affect only suggestion visibility/order. Only a user tap writes an activity into trip context, and changing trip types never silently adds or removes a selected activity.

For beach:

```text
Swimming
Beach days
Snorkeling
Nice dinner
Running
Sightseeing
Boat trip
```

For city:

```text
Sightseeing
Walking
Fine dining
Nightlife
Running
Shopping
Museums
Work
```

Always include **+ Add something**.

Free text is supported. Example: `Sunrise wildlife photography`.

PackWise interprets free-text activities internally. Do not require every activity to be a manually built enum.

Suggestions are the stable union of every selected trip type's contract suggestions, shown as multi-select cards; a selection outside them stays visible. Only a tap changes the activities — changing trip types never adds or removes one, and an unselected suggestion has no effect on the list. **Add something** stores a typed activity; a known keyword normalizes to its activity, anything else stays inert.

## Step 6 — Bags

Headline: **What bags are you bringing?**

Helper: **Choose all that apply.**

Options:

```text
Personal item
Carry-on
Checked bag
Backpack
```

These are multi-select physical bags. An empty selection displays **Not sure yet** and applies no luggage constraint. Road Trip is trip context, not luggage. If any checked bag is selected, carry-on-only trimming does not apply.

Visually explain the normalized implication. Example for **Carry-on**:

> PackWise will favor versatile items and fewer backups.

## Step 7 — Packing style and laundry

### How do you prefer to pack?

The second half of the same screen. This is a signature PackWise setting.

### Light

> Keep it minimal. Reuse items where practical.

### Balanced

> Enough for the trip with sensible backups.

### Prepared

> Bring a little extra for the unexpected.

Default: **Balanced**, or the Me tab default if the traveler has set one. Setup prefills bags and packing style from Me. The traveler can still change them for this trip.

Internally this changes:

- quantities
- redundancy
- optional-item score
- footwear count
- backup clothing
- weather-risk tolerance

Laundry is a separate single-select policy on the same screen: **No laundry**, **Laundry if I need it**, or **Planning to do laundry**.

## Step 8 — About you / trip preferences

Optional.

Headline: **Anything PackWise should know?**

Chips, grouped:

```text
Health              Daily medication · Contacts
Devices & work      Laptop
Clothing & comfort  Work out · Running · Formal outfit · Get cold easily
This trip           International
```

Traveler device signals for other people live in their traveler cards, never here. Setup does not collect a free-text note today; an existing trip's note is kept.

Example: `I'll probably do laundry halfway through.`

That note is stored as explicit context. Interpretation remains gated off during Product Experience V2; M3B may later propose accepted enrichment with traveler-attribution guards. Do not dump the raw note into customer-facing “AI” copy.

## Step 9 — Review

Review separately summarizes trip types, travelers, activities, bags, packing style, laundry, and preferences with wrapping text. Empty bags show **Not sure yet**. Family counts distinguish the current user from **Other adults**.

## Natural language shortcut

Later, or V1.1.

At the start of trip creation:

**Tell PackWise about your trip**

Example:

> I'm going to Seattle for five days in October. Mostly sightseeing and hiking, one nicer dinner, carry-on only, and I pack pretty light.

Internally extract:

```text
Seattle
October dates if supplied
City/outdoor
Sightseeing
Hiking
Fine dining
Carry-on
Light
```

Then show **Here's what I got** for the user to verify.

This uses GPT without ever saying **Chat with AI**. The label is **Tell PackWise about your trip.**

Not in MVP unless explicitly pulled forward. See [roadmap.md](roadmap.md).

## Review screen

Before creation, show a confirmation summary:

```text
Seattle

Oct 10 – Oct 14
5 days · 4 nights

City + Outdoor

Sightseeing
Hiking
Nice dinner

Carry-on

Light packing
```

Weather state:

```text
Forecast available
```

or:

```text
Forecast will be available closer to your trip.
```

CTA: **Build My Packing List**

## Generation experience

Do not fake an absurd loading animation.

It should take about a second or two.

Potential messages, only if real processing time warrants them:

```text
Checking your trip
Considering the forecast
Building your packing list
```

Then transition straight into Trip Detail. Never say “AI is generating your list.”
