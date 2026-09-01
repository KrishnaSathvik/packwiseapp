# Lifecycle, Memory, and Me

## Packing timeline

PackWise adapts as departure approaches. The user does not configure these phases.

### Weeks away

```text
Packing list ready
```

### Forecast becomes available

```text
Your forecast is ready.
2 packing suggestions changed.
```

### Three days away

```text
You're 46% packed.
```

### Day before

```text
9 items left.
3 are important.
```

### Departure day

```text
Final Check
```

## Final Check

Day of departure changes the product experience.

Instead of normal packing mode:

**Final Check**

```text
Passport                    ✓
Wallet                      ✓
Medication                  ○
Phone                       ✓
Phone charger               ○
Keys                        ✓
```

Then:

> **2 important items still unchecked.**

This is one of PackWise's highest-value moments. Do not visually scream about importance weeks in advance.

## Notifications

Strict usefulness rule.

Send:

> Rain is now expected during your Chicago trip. Two packing suggestions changed.

Send:

> Your Chicago trip is tomorrow. 6 items remain unpacked.

Send:

> Passport and medication are still unchecked.

Do not send:

> It's packing time! 🎉

Do not send:

> PackWise misses you.

Do not use meaningless engagement notifications.

Do not request notification permission during first-launch onboarding. Ask later, at a useful moment.

Notification types and architecture: [data-privacy-and-platform.md](data-privacy-and-platform.md).

## Share

MVP: native iOS Share Sheet.

Formatted list:

```text
Chicago · Sep 12–16

Essentials
✓ Passport
○ Medication

Clothing
✓ T-shirts ×4
○ Rain jacket
```

Later: **Share as PackWise trip** could enable collaboration. Server collaboration is not required initially.

## Complete trip

M1 gives the loop an ending. **Complete Trip** on Trip Detail sets status to `completed` and moves the card to Past. Do not write Packing Memory from this action. Post-trip review is V1.

The packing list stays available from Past.

## During trip

PackWise gets out of the way.

Trip state:

**You're packed.**

**Have a great trip to Chicago.**

The user can still access:

```text
Packing list
Weather
Trip details
```

Do not suddenly turn into itinerary mode.

## Post-trip review

After return:

**How did packing go?**

Make this fast. PackWise selects useful items to ask about.

Example:

> You packed a rain jacket. Did you use it?

**Used** / **Didn't Use**

Next:

> Anything you wish you'd packed?

**Add something**

Then:

> You brought 3 pairs of shoes.

**About right** / **Too many**

Five interactions maximum. No 42-item survey.

## Packing Memory

This is the long-term product.

Internally collect structured signals:

```text
Suggested
Packed
Removed
Manually added
Used
Unused
Forgotten
Quantity adjusted
```

Over many trips:

```text
Portable charger
Packed 8 / 9 trips

Travel pillow
Removed 5 / 6 times

Jeans
Average suggested: 2
Average used: 1

Running shoes
Manually added 4 times
```

If the user removes Travel Pillow repeatedly:

```text
PackingMemory
item = travel_pillow
suggested = 7
removed = 6
packed = 1
used = 0
```

Memory is eventually keyed by `travelerID` so partner and child habits stay separate. Solo trips keep a single self traveler.

Eventually:

> You usually skip travel pillows.

Or PackWise simply stops recommending it unless context is unusually strong.

## Me — Packing Habits

Do not show nerdy statistics initially.

Show:

**Your Packing Habits**

### You usually bring

```text
Portable charger
Running shoes
Sleep mask
```

### You tend to skip

```text
Travel pillow
Extra jeans
```

### Packing style

```text
Balanced
```

### Common travel habits

```text
Usually works out
Often travels carry-on
```

Everything is editable.

## Saved preferences

Me → Preferences.

Possible settings:

```text
Default packing style
Preferred bag
Temperature units
Weight units
Usually work out while traveling
Usually bring laptop
Wear contacts
Always bring medication
```

Avoid asking for deeply personal details unless needed.

## Past trips

```text
Maui
Aug 14 – Aug 20

Completed

48 items
45 packed

Carry-on
Balanced

Weather
82–91°F

View Packing List
```

Actions:

- **Use as inspiration**
- **Plan a Similar Trip**

Not a blind clone. Repeat-trip intelligence lives in [intelligence-features.md](intelligence-features.md).

---

## Memory event log — retention (decided 2026-09-01)

Engine V2 Step 6 replaced the aggregate `PackingMemoryRecord` counters (which
nothing ever wrote) with an immutable event log: `PackingMemoryEventRecord`,
one row per `suggested / userAdded / notNeeded / packed / quantityChanged`
event, each carrying a structured `ContextFingerprint` (duration bucket,
laundry plan, style, bag, trip type, party size) so future memory features are
group-bys, not a research project. Suggested/added/declined record at the
repository mediation points; packed and quantity-changed snapshot once at trip
completion — final state, not mid-trip churn.

**Events survive trip deletion, deliberately.** They reference the trip's
UUID with no SwiftData relationship, so deleting a trip removes the trip but
keeps the packing history it produced — accumulated memory is the point of
collecting them, and the data is local-first and never leaves the device.

**Me gets a "Clear packing history" control when memory ships a user-visible
feature.** Until something reads the log there is nothing user-visible to
clear; when Packing Memory surfaces in the product, the control ships in the
same release.
