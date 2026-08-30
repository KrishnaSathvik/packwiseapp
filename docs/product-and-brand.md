# Product and Brand

## Product definition

**PackWise is a personal packing intelligence app for iPhone.**

The user tells PackWise:

- where they're going
- when they're going
- what kind of trip it is
- what they'll be doing
- what bag they're taking
- how they prefer to pack

PackWise combines that with:

- weather
- trip duration
- destination context
- known packing patterns
- the user's previous trips
- explicit preferences
- previous items used / unused / removed
- GPT-5.6 reasoning internally

and produces a packing list that is:

**relevant, explainable, adjustable, and increasingly personal.**

## Core promise

> **Pack what you need. Leave what you don't.**

Alternative brand lines:

- **Know what to pack.**
- **Packed for this trip. Not every trip.**

The last line is the strongest differentiation: the list is for this trip, not a generic travel checklist.

The feeling the product should sell:

> **I don't have to think through packing from scratch anymore.**

## Product philosophy

PackWise must not feel like:

**Checklist app + weather widget + chatbot.**

Everything should feel like one system.

Internal journey:

```text
Understand Trip
      ↓
Understand Conditions
      ↓
Understand Traveler
      ↓
Determine What Matters
      ↓
Build Packing List
      ↓
Explain Recommendations
      ↓
Adapt When Things Change
      ↓
Observe Packing Behavior
      ↓
Improve Next Trip
```

The user never needs to know which recommendation came from WeatherKit, rules, GPT-5.6, packing history, or destination knowledge.

They simply see:

> **Light rain jacket**
>
> Rain is expected Saturday and most of your plans are outdoors.

That is PackWise.

## Brand language — hard product rule

**GPT-5.6 can power PackWise internally, but PackWise must never market itself as an “AI packing app.”**

The customer should experience intelligence, not technology.

They should see:

**Smart Packing List · Packing Impact · Why this item? · Weather changes · Your Packing Habits · What you might be forgetting · Pack lighter**

They must never see:

**AI-generated · Powered by AI · Ask our AI · AI Recommendations · AI Assistant**

PackWise should feel like it simply **knows how to help you pack**.

### Never customer-facing

Avoid unless required in technical or legal documentation:

```text
AI-generated
AI packing
AI assistant
AI recommendation
AI-powered
GPT
LLM
Machine learning
Algorithm
```

### Customer-facing language

Use:

```text
Smart suggestion
Recommended for your trip
Packing suggestion
Packing impact
Based on your trip
Based on the forecast
Based on your activities
Based on how you pack
You usually bring this
You may not need this
PackWise suggests
Ask PackWise
```

Internally: **GPT-5.6 Recommendation Engine**

Externally: **PackWise suggests bringing a light layer.**

### Internal vs external boundary

This boundary is frozen.

**Inside PackWise** (engineering, prompts, docs, code comments):

```text
GPT-5.6
Structured Outputs
reasoning
prompts
rules
confidence
ranking
models
signals
recommendation scoring
```

**Outside PackWise** (UI, App Store, marketing, notifications, onboarding):

```text
PackWise understands my trip.
PackWise knows it's going to rain.
PackWise understands I'm hiking.
PackWise knows I pack light.
PackWise remembers I always take running shoes.
PackWise caught something I forgot.
PackWise told me I don't need three pairs of shoes.
```

Do not sell the engine. Sell the feeling.

If GPT-5.6 improves, is replaced, gets cheaper, becomes more capable, or is temporarily unavailable, the PackWise brand and the user's experience stay the same. The deterministic packing engine still works.

## Main product loop

```text
FIRST TRIP

Create Trip
   ↓
Trip Context
   ↓
Smart Packing List
   ↓
Pack
   ↓
Weather Updates
   ↓
Final Check
   ↓
Travel
   ↓
Trip Review
   ↓
Packing Memory

SECOND TRIP

Create Trip
   ↓
Trip Context
   +
Packing Memory
   ↓
Better Recommendations
   ↓
Pack
   ↓
Learn Again

Eventually:

"My PackWise"
```

Personal packing memory is the long-term moat. The first trip should already feel useful. The second trip should feel personal.

## Signature product concepts

These names are customer-facing and should be used consistently:

| Concept | Meaning |
| --- | --- |
| Smart Packing List | The generated, explainable list for this trip |
| Packing Impact | Why weather, bag, or activities changed the list |
| Why this item? | Human explanation for a recommendation |
| Weather Changed | Non-destructive suggestion flow when forecast changes |
| Final Check | Departure-day critical-item review |
| Ask PackWise | Contextual help inside a trip, not a chatbot |
| What am I forgetting? | Gap check against trip + habits |
| Pack lighter | Overlap and redundancy reduction |
| Your Packing Habits | Human-readable memory, not raw stats |
| Good to Know | Destination notes that only affect packing |

See [intelligence-features.md](intelligence-features.md), [weather-and-packing-impact.md](weather-and-packing-impact.md), and [lifecycle-memory-and-me.md](lifecycle-memory-and-me.md).
