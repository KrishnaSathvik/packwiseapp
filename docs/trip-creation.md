# Trip Creation

Do not use one giant form.

Use a progressive setup. The user should feel like they are describing their trip, not filling in a database record.

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

**Me + partner** asks for an optional name and only the differences that matter (medication, contacts, workout, formal, cold, note).

**Family** asks for adult count, child count, and each child's age group (teen / child / toddler / infant). Optional first names. No birth dates.

**Group** asks for an adult count. One device manages the list. Invites and realtime sync are later.

Shared trip context (destination, dates, weather, activities, bag, style) is not re-asked per person.

## Step 4 — Trip type

Headline: **What kind of trip is it?**

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

Trip type is one signal. It must not directly determine the entire packing list.

## Step 5 — Activities

Headline: **What will you be doing?**

Suggested chips are based partly on trip type.

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

Free text is required. Example: `Sunrise wildlife photography`.

PackWise interprets free-text activities internally. Do not require every activity to be a manually built enum.

Selected activities appear in a **Your activities** list.

## Step 6 — Bag and packing style

One screen, two questions, as the reference board draws it. The draft still
records bag and style separately; only the presentation is merged.

Headline: **How are you traveling?**

Options:

```text
Personal item only
Carry-on
Checked bag
Backpack
Road-trip luggage
Not sure yet
```

Visually explain the implication. Example for **Carry-on**:

> PackWise will favor versatile items and fewer backups.

### How do you prefer to pack?

The second half of the same screen. This is a signature PackWise setting.

### Light

> Keep it minimal. Reuse items where practical.

### Balanced

> Enough for the trip with sensible backups.

### Prepared

> Bring a little extra for the unexpected.

Default: **Balanced**, or the Me tab default if the traveler has set one. Setup prefills bag and packing style from Me. The traveler can still change them for this trip.

Internally this changes:

- quantities
- redundancy
- optional-item score
- footwear count
- backup clothing
- weather-risk tolerance

## Step 8 — Anything else?

Optional.

Headline: **Anything PackWise should know?**

Suggested chips:

```text
I take daily medication
I wear contacts
I'm bringing a laptop
I usually work out
I run while traveling
I need a formal outfit
I'm traveling internationally
I get cold easily
```

Then: **Add a note**

Example: `I'll probably do laundry halfway through.`

That note is useful context. GPT-5.6 interprets it internally. Do not dump the raw note into customer-facing “AI” copy.

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
