# Travelers and Parties

PackWise builds the list for the trip **and for everyone going**. Solo stays the simple path. Couple and family are first-class, one-device, no accounts.

## Promise

> PackWise builds the list for the trip — and for everyone going.

A family is not `4 × the solo list`. Party composition changes **what** gets packed, not just how many copies you generate.

## Models

```text
Trip
├── party: TripParty
│     travelMode: solo | couple | family | group
│     travelers[]
├── packingItems (personal or shared)
└── bags[]
```

### Traveler

```text
id
name / nickname
role: self | partner | child | otherAdult
ageGroup: adult | teen | child | toddler | infant
packingResponsibility: self | anotherTraveler | shared | guardian
guardianTravelerID?
needs[]                  // child candidates: diapers, formula, stroller…
preferences / chips
specialNeeds note
```

No birth dates, weights, or heights.

`packingResponsibility` is an enum even if MVP barely uses it. Children default to `guardian`.

`guardianTravelerID` is optional now. It matters when something belongs to the child but an adult packs it.

### PackingItem — owner vs carrier

Keep these meanings strict:

```text
travelerID            whose item it is (nil when shared)
assignedTravelerID    who is responsible for bringing it
ownershipType         personal | shared
bagID?
```

Examples:

```text
Emma's jacket
travelerID = Emma
assignedTravelerID = Dad

Shared sunscreen
travelerID = nil
ownershipType = shared
assignedTravelerID = Mom
```

### Bag

```text
id
name
type
ownerTravelerID?
ownershipType: personal | shared
```

That supports “Krishna's carry-on”, “Partner's backpack”, and “Family checked suitcase” without another migration. Assignment UI is later.

## Sharing policy

Shared items do not all scale the same way.

```text
sharingPolicy:
singlePerParty
scaleByParty
scaleByDevices
scaleByDurationAndParty
personalOnly
```

Examples for four people:

```text
First-aid kit     singlePerParty            ×1
Travel adapter    scaleByDevices            ×2
Umbrella          scaleByParty              ×2
Sunscreen         scaleByParty              ×2
Snacks            scaleByDurationAndParty
```

Policies live in `shared/rules/party.json` as **rule metadata**. Do not copy `sharingPolicy` onto every `PackingItem`. The generated item stores the resolved result (`quantity`, reason). The policy stays in the catalog/rule layer.

**Status: frozen for V1 architecture.** Do not expand this model until the packing engine and trip-setup UI prove the flows.

## Invariants

Enforced in the domain layer (`PartyInvariants`).

```text
personal item:
ownershipType = personal
travelerID != nil

shared item:
ownershipType = shared
travelerID = nil

assignedTravelerID:
may be nil
must reference a traveler in the same TripParty

guardianTravelerID:
only valid for teen / child / toddler / infant
must reference an adult traveler in the same TripParty

bag owner:
ownerTravelerID must belong to the same TripParty
```

## Kids: eligible, not assumed

Age group makes items **candidates**. Clothes, pajamas, and backup outfits can enter automatically. Diapers, formula, pacifiers, strollers, car seats, and child medication enter only when a setup chip or a stronger signal (such as swimming → swim diapers) confirms them.

```text
Toddler
→ automatic: tops, pajamas, extra outfits
→ candidate: diapers, stroller, comfort item
```

## Setup

**Who's traveling?** Just me / Me + partner / Family / Group

- **Just me** — no extra screens. Internally `TripParty` with one `self` adult.
- **Couple** — You + Partner. Optional partner differences only.
- **Family** — adult count, child count, each child's age group, and only the child needs that apply.
- **Group** — adult count. One device manages the list.

## Engine

Weather and trip-wide signals run **once**.

```text
Trip-wide context
        ↓
Party context
        ↓
Traveler-specific needs
        ↓
Shared needs
        ↓
Quantity engine
        ↓
Overlap/substitution resolver
        ↓
Recommendation resolver
        ↓
Final list
```

Rain becomes a personal rain layer per traveler who needs one, and a shared umbrella count for the party — not four umbrellas.

## UI

Tabs are generated from the party, not hardcoded.

```text
Krishna + Maya          All | Krishna | Maya | Shared
You + Maya + 2 kids     All | You | Maya | Kids | Shared
You + Partner + Arjun   All | You | Partner | Arjun | Shared
```

Shared rows can ask **Who is bringing it?** That writes `assignedTravelerID`.

## Persistence

`PackWiseSchemaV1` → `PackWiseSchemaV2` with a lightweight `SchemaMigrationPlan`. Do not treat delete-and-reinstall as the migration strategy.

## Memory

`PackingMemory.travelerID` so partner and child habits stay separate.

## Out of MVP

Realtime collaboration, invites, multi-account sync, cross-device family profiles, bag-assignment UI.
