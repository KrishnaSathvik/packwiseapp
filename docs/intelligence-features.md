# Intelligence Features

These features expose reasoning without presenting a chatbot or mentioning AI.

## Ask PackWise

This is how GPT-5.6 capability is exposed without an AI chatbot.

Inside a trip: **Ask PackWise**

Suggested prompts:

```text
What am I forgetting?
Can I pack lighter?
Do I need another pair of shoes?
What should I wear on travel day?
Anything special for this destination?
Can this fit in a carry-on?
```

The user can type naturally.

This must remain contextual to the current trip.

Do not create a ChatGPT clone inside PackWise.

Do not create a giant `/chat` backend endpoint. Product capabilities stay explicit. See [packing-engine.md](packing-engine.md).

## What am I forgetting?

Dedicated action.

PackWise evaluates:

```text
trip
destination
weather
activities
current list
items removed
packing habits
```

Then possibly says:

**A few things to consider**

**Portable charger**

> You'll have several long sightseeing days and it isn't currently on your list.

**Medication**

> You usually bring this on trips, but it hasn't been added yet.

User can:

- **Add**
- **Not Needed**

## Pack lighter

Signature action.

PackWise examines overlap and redundancy.

Example:

**You could probably remove 4 items**

**Second pair of jeans**

> Your five-day trip likely only needs one pair with your light packing style.

**Separate walking shoes**

> Your running shoes can likely serve both purposes.

**Second sweatshirt**

> One layer should cover the expected temperature range.

Estimated later:

> Save about 3.2 lb.

Do not say AI.

## Destination considerations

Not a full destination guide.

Only packing-relevant context.

Example:

**Good to Know**

Tokyo

```text
You'll likely walk a lot.
Comfortable footwear matters.

Rain can be unpredictable.
A compact umbrella may be useful.

You're planning a nicer dinner.
One smart-casual outfit should cover it.
```

Everything must connect back to packing.

## Repeat trip intelligence

If the user returns to a previous destination (example: Maui), combine:

```text
Previous Maui packing behavior
+
New activities
+
Current weather
+
Current bag
+
Current packing style
```

Then:

> You packed for Maui before. PackWise used what worked last time and adjusted for this trip.

Do not simply clone the previous list.

## Edit trip creates a recommendation diff

The user can change:

```text
Dates
Activities
Bag
Packing style
Trip type
Personal context
```

Changing context creates a recommendation diff, not a full regenerate.

Example: user adds **Hiking**.

> Hiking affects your packing list.

Suggested:

```text
+ Hiking shoes
+ Daypack
+ Water bottle
```

Not:

> Regenerating your list…

Preserve the user's list. The user decides what to add or remove.

## Scope

Ask PackWise, What am I forgetting?, Pack lighter, and visible Packing Memory are **V1 after launch**, not MVP, unless scope is explicitly expanded. See [roadmap.md](roadmap.md).

The deterministic engine and GPT contextual recommendation layer *are* in MVP. The dedicated gap/optimize surfaces come after the core list is excellent.
