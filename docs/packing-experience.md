# Packing Experience

Trip Detail is PackWise's most important screen. Packing dominates the page.

## Trip Detail — core screen

```text
Chicago
Sep 12 – Sep 16 · 5 days

████████████████░░       74%
31 of 42 packed
11 remaining


WEATHER
61° – 78° · Rain Saturday


PACKING IMPACT
Rain expected Saturday
Rain jacket added

Cool evenings
Light sweater added

                  View Weather


PACKING

Essentials                     4 / 6
Clothing                       9 / 13
Footwear                       2 / 3
Toiletries                     6 / 8
Electronics                    4 / 5
Activities                     3 / 5
Travel Comfort                 3 / 4
```

A floating **+** control adds items. Weather is a compact trip-scoped headline, not a general weather app. Packing Impact sits between weather and the checklist when the engine already used weather signals. Hide it entirely when weather caused no packing change. If a later snapshot changes packing signals, a **Weather changed** card appears above the list — review applies `recommendationDiff()`, never a silent rewrite. The daily forecast strip lives on **View Weather**, not Trip Detail.

## Packing categories

Initial canonical categories:

```text
Essentials
Documents
Clothing
Kids
Footwear
Toiletries
Electronics
Health
Activities
Travel Comfort
Miscellaneous
```

Category order may depend slightly on context:

- International trips: Documents rises
- Outdoor trips: Activities rises

Do not overdo dynamic UI movement.

## Party lists

Solo stays one list.

Couple and family add a second filter row generated from the party:

```text
All | Krishna | Maya | Shared
All | You | Maya | Kids | Shared
All | You | Partner | Arjun | Shared
```

Shared items can ask **Who is bringing it?** That is the carrier (`assignedTravelerID`), not the owner. See [travelers-and-parties.md](travelers-and-parties.md).

## Packing item UX

Basic row:

```text
○   Rain jacket
    Rain expected Saturday
```

Quantity:

```text
○   T-shirts                    ×4
```

Personal recommendation:

```text
○   Portable charger
    You usually bring this
```

Important:

```text
!   Passport
    Required for this trip
```

Once packed:

```text
✓   Passport
```

## Do not turn every row into a card

Apple Reminders-style simplicity:

```text
○ T-shirts ×4
○ Jeans ×1
○ Light sweater
○ Rain jacket
```

Cards only when something deserves emphasis:

```text
Weather changed
Final check
Packing suggestion
```

Otherwise the UI becomes noisy.

## Swipe actions

Native gestures.

Swipe left:

```text
Delete
Not Needed
```

These are different actions.

```text
Not Needed
= PackWise recommended it, the user rejected it
= store RecommendationOverride so it does not silently return

Delete
= remove this record
= no override
= the right action for custom items
```

A deleted catalog item may come back as an add if the trip context still supports it. Not Needed will not.

Swipe right:

```text
Pack
```

Long press:

```text
Edit
Move category
Change quantity
Why this item?
Don't suggest on trips like this
```

## Item detail

Tap an item. Bottom sheet.

Example:

**Rain Jacket**

**1**

### Why it's on your list

> Rain is expected Saturday and your sightseeing plans include significant outdoor time.

### Recommended by

```text
Forecast
Activities
```

Never show:

```text
AI
GPT
Algorithm
```

Actions:

```text
Change quantity
Move category
Mark not needed
Remove
```

Later:

```text
Always bring on rainy trips
Don't suggest this again
```

## Recommendation sources

Internally every recommendation may have:

```text
weather
duration
activity
tripType
destination
baseEssential
userPreference
history
GPT reasoning
```

Externally translate into understandable signals:

```text
Forecast
Trip length
Your activities
Your destination
Your preferences
Your packing habits
```

Never expose GPT reasoning as a source.

## Smart quantity system

Users should see quantities, not bare names:

```text
T-shirts                    ×4
Underwear                   ×6
Socks                       ×6
Pants                       ×2
```

Internal calculation considers:

```text
days
nights
activities
packing style
laundry
weather
clothing reuse
formal requirements
workout frequency
```

Example:

```text
6-day trip
Carry-on
Light packing
Laundry available

T-shirts → 4
Pants → 2
Underwear → 6
```

## Quantity explanation

Tap quantity:

> **Why 4 shirts?**
>
> You're traveling for six days, packing light, and indicated that you'll have access to laundry.

## Deduplication

This must happen internally.

Suppose:

```text
Sightseeing → Comfortable shoes
Running → Running shoes
Travel → Sneakers
```

PackWise should reason whether **1 versatile pair** can satisfy multiple needs.

Potential suggestion:

> **Running shoes can also cover your sightseeing days.**
>
> You may not need another pair of sneakers.

That is packing intelligence, not mere list generation.

## Add item

Persistent: **+ Add Item**

Sheet:

```text
Item
[ Portable fan ]

Quantity
1

Category
Travel Comfort

Remember this for future trips
○
```

Custom items become training signals for Packing Memory.

## Search

For long lists: **Search items**

Search both current list items and catalog items.

Typing `cha` could show:

```text
Phone charger
Laptop charger
Camera charger
```

## Filtering

Simple chips only:

```text
All
Left to pack
Packed
Important
```

Optional: **Hide packed items**

Do not create a large filter system.

## Progress

Progress must be useful, not only a percent.

Show:

```text
31 of 42 packed
11 items left
```

Near departure:

```text
4 essentials still unpacked
```

## Critical items

Internal importance:

```text
critical
important
normal
optional
```

Examples:

### Critical

Passport, medication, wallet, required travel documents

### Important

Phone, charger, glasses

### Normal

Shirts

### Optional

Travel pillow

Do not visually scream about importance while the trip is weeks away. Near departure it matters. See Final Check in [lifecycle-memory-and-me.md](lifecycle-memory-and-me.md).
