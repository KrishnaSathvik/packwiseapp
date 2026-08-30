# Packing Engine

This is the heart of PackWise.

## Why two systems

### Deterministic engine

Handles:

```text
trip duration
base essentials
known activity mappings
weather thresholds
quantity math
deduplication
list reconciliation
user overrides
```

### GPT-5.6

Handles:

```text
free-text interpretation
unusual activities
destination nuance
cross-signal reasoning
packing gaps
packing-light suggestions
better explanations
natural questions
post-trip interpretation
```

Neither replaces the other. If GPT is unavailable, the deterministic engine still produces a useful list.

Frozen M3 principle:

```text
Deterministic engine  →  core packing list
GPT-5.6               →  context enrichment / gap finding / unusual-trip reasoning
Recommendation Resolver →  final user-controlled result
```

Never `trip → GPT → arbitrary list`. GPT understands language. The engine understands packing.

## Intelligence pipeline

Weather path: `WeatherSignalExtractor → PackingConditions → WeatherPackingRules`. Weather runs once per trip, then splits into personal effects and shared effects. Substitution uses capabilities, not blunt ID pairs. Quantity policies live in `shared/rules/quantities.json`. Party sharing policies and age candidates live in `shared/rules/party.json`. Every suggestion carries `reasonCode` + arguments.

Packing Impact (M2B, closed) reads that provenance and groups weather-sourced items for the UI. It does not re-run weather thresholds or add items.

Weather-change reconciliation (M2C, closed) diffs packing signals first. Only a meaningful signal change calls `recommendationDiff()`. The proposal is not the list. Snapshot save and packing acceptance stay separate; dismiss is not Not Needed.

```text
                         Trip
                          │
                          ▼
                  Trip Context Builder
                          │
            ┌─────────────┼──────────────┐
            │             │              │
            ▼             ▼              ▼
         Weather       Preferences     History
            │             │              │
            └─────────────┼──────────────┘
                          ▼
                    Signal Builder
                          │
            ┌─────────────┴─────────────┐
            ▼                           ▼
      Packing Rules                GPT-5.6
            │                           │
            ▼                           ▼
     Rule Suggestions        Contextual Suggestions
            │                           │
            └──────────────┬────────────┘
                           ▼
                 Recommendation Resolver
                           │
                           ▼
                     Deduplication
                           │
                           ▼
                     Quantity Engine
                           │
                           ▼
                  Preference Resolver
                           │
                           ▼
                    User Overrides
                           │
                           ▼
                    Final Packing List
```

## Internal GPT-5.6 architecture

Never call OpenAI directly from the iPhone.

```text
PackWise iOS
      │
      │ HTTPS
      ▼
PackWise Intelligence API
      │
      ├── Request validation
      ├── App attestation
      ├── Rate limiting
      ├── Prompt version
      ├── Context minimization
      ├── Structured output schema
      │
      ▼
OpenAI Responses API
      │
      ▼
GPT-5.6
```

API secret stays server-side.

## GPT does not write user data

Never:

```text
GPT → SwiftData
```

Instead:

```text
GPT
 ↓
Structured recommendation
 ↓
Validate schema
 ↓
Validate canonical items
 ↓
Recommendation Resolver
 ↓
Apply rules / overrides
 ↓
User sees recommendation
 ↓
User accepts / list updates
 ↓
SwiftData
```

## Structured response

Internal example:

```json
{
  "suggestions": [
    {
      "canonical_item_id": "electronics.power_bank",
      "action": "recommend",
      "confidence": 0.91,
      "signals": [
        "long_day_activities",
        "destination_context"
      ],
      "reason": "Several planned activities involve long periods away from your hotel."
    }
  ]
}
```

The UI sees:

**Portable charger**

> You'll have several long days away from your hotel.

Nothing about GPT.

Reasons shown to the user must be human, trip-specific, and source-translated (Forecast, Activities, Your packing habits). See [packing-experience.md](packing-experience.md).

## Recommendation Resolver

One of the most important domain services.

Inputs:

```text
Rule Suggestions
GPT Suggestions
Personal History
Existing Packing List
User Overrides
```

Output:

```text
Final Recommendation Set
```

Priority rule:

> **Explicit user decision always wins.**

## User overrides

If PackWise recommends **Travel pillow** and the user deletes it, store:

```text
TripRecommendationOverride

tripID
canonicalItemID
action = removed
```

Weather refreshes.

GPT reruns.

Rules rerun.

The item still does not come back automatically.

That is essential.

## Longer-term preference memory

Repeated removals feed `PackingMemory`. Eventually PackWise stops recommending the item unless context is unusually strong. See [lifecycle-memory-and-me.md](lifecycle-memory-and-me.md).

## Recommendation scoring

Conceptually:

```text
Final Relevance

=
base rule strength

+ trip type relevance
+ activity relevance
+ weather relevance
+ destination relevance
+ personal preference relevance
+ historical behavior relevance
+ contextual reasoning relevance

- bag constraint penalty
- repeated rejection penalty
```

Then convert into:

```text
Required
Recommended
Helpful
Optional
Do not show
```

Do not expose numeric scores in the UI.

## Packing style effects

From trip setup. Internally packing style changes:

- quantities
- redundancy
- optional-item score
- footwear count
- backup clothing
- weather-risk tolerance

Light favors reuse and fewer backups. Prepared raises weather-risk tolerance and backups. Balanced is the default.

## Deduplication and quantities

Deduplication and the quantity engine run after the resolver and before user-facing list commit. See [packing-experience.md](packing-experience.md).

## Endpoint responsibilities

Do not create one giant `/chat` endpoint.

Early PackWise Intelligence API:

```text
/interpret-trip
/recommend-context
/check-gaps
/pack-lighter
/ask
```

Versioned conceptually:

### `/v1/trip/interpret`

Natural language → structured Trip Context.

### `/v1/trip/context`

Trip context → contextual signals.

### `/v1/packing/gaps`

Existing list → things potentially missing.

### `/v1/packing/optimize`

Existing list → possible reductions / overlaps.

### `/v1/trip/ask`

Contextual user question.

Product capabilities remain explicit.

## Context minimization

Do not send the entire user's life to GPT every time.

For each request assemble only relevant context.

Packing gap check example:

```text
destination
dates
trip type
activities
weather summary
packing style
bag
current item IDs
relevant preferences
small amount of packing memory
```

That is it.
