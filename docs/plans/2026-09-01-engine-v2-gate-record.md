# Engine V2 — Gate Record

**Verdict: PASS** (2026-09-01). The Miami-beach vs Chicago-business gate from
`2026-08-31-engine-v2-rebuild.md`, Step 7.

## Method

Self-administering blind instrument ("The Two-Trip Test"): both five-day solo
lists rendered identically with full rows (item, quantity, reason), destination
names replaced with "your destination", nothing else altered. A/B assignment
randomized per run; timer from list reveal to answer; pass criteria hidden from
the tester. A keyword-blind follow-up round asked testers to re-identify the
trips pretending *beach*, *business*, *working*, *swimming*, and *nice dinner*
did not appear.

**Criteria, fixed before any run:** correct identification, under ten seconds,
at least two specific items or quantities named.

## Results — four runs

- **4/4 correct** on the primary question.
- **4/4 correct** on the keyword-blind follow-up — the lists differentiate on
  substance (sun hat / sunglasses / sandals / shorts / swimsuit vs blazer /
  dress shirts / dress shoes / laptop), not labels. Two runs named the
  quantity asymmetry specifically.
- Times: 0.8s, 1.3s, 24.6s, 119.8s. The randomizer produced both mappings
  across the set, and mapping and answer agree in every run.
- Every run named well more than two signals.

**Adjudication note (proctor):** the two slow runs count as passes. The
criterion measured recognition; the clock measured typing. Both slow runs show
immediate recognition followed by long written explanation ("That's what gave
it away", then continuing), and the two sub-two-second runs establish that
perception is near-instant when the tester isn't writing an essay.

**Caveat, recorded rather than assumed away:** the proctor could not verify
from the result screenshots that all four testers were human. If any were
models, the finding holds directionally but the record should not be read as
four independent human trials.

## The line that matters

> "B also packed 7 shirts/socks/underwear for 5 days, which feels like work,
> not the beach."

A tester used the quantity difference as evidence, unprompted — Step 2's
quantity model being *perceived*, not just correct in a golden file. It is
also the rebuild's first post-gate bug: seven t-shirts beside two dress shirts
on a five-day business trip reads as a signal but is really the daily-top need
not knowing that formal tops satisfy some of its uses. That is the first
hardening slice.

## What the gate did not test

Recorded at gate time so hardening starts honest: absolute quantity
correctness (differentiation ≠ correctness); couple/family attribution;
international documents; snow and cold trips; the 30-day plateau; the
override/diff lifecycle; base-essential copy quality. All covered by fixtures,
properties, and golden review — none yet by a human eye.
