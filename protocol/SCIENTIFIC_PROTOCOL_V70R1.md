# CIAS v7.0-r1 — Frozen Persistent Causal Identity Confirmatory

## Frozen claim

**Primary claim:** under radical appearance/position change, intermittent true-Self causal dropout, and an old-appearance clone carrying partially yoked false causal cues, the persistent causal identity anchor is necessary for functional Self continuity.

This release does **not** test a benefit of progressive morphology order. v7.0-p2 failed to support that stronger hypothesis, so it is excluded from the confirmatory claim.

## Scientific code freeze

The complete benchmark behavior is copied byte-for-byte from v7.0-p2:
- `scripts/ontology_core.gd`
- `scripts/developmental_self_benchmark_p2.gd`

No thresholds, cue schedules, clone behavior, endpoint formulas or ontology logic are changed after p2.

## Conditions

Primary:
- `progressive_persistent`
- `progressive_no_persistent_self`

Secondary:
- `progressive_history_reset`

The history-reset arm does not determine confirmatory PASS. p2 showed that generic retained association history is not equivalent to the persistent identity anchor.

## Preflight

Seeds **273–276**.

4 seeds × 4 embodiment × 3 conditions = **48 runs**.

Preflight checks only:
- complete factorial structure;
- exactly four matched change-point events;
- finite/nonmissing endpoints;
- nondegenerate Full endpoint range.

It does not require a Full-vs-lesion effect.

Held-out opens only from the same Godot process after preflight PASS.

## Frozen held-out

Seeds **277–306**.

30 seeds × 4 embodiment × 3 conditions = **360 runs**.

## Conjunctive primary criteria

All must pass:

1. `identity_continuity_score_v2`
   - Full advantage over `no_persistent_self` ≥ **0.15**;
   - two-sided paired-seed 95% CI lower bound > 0;
   - correct direction in at least 3/4 embodiment.

2. Rejection of the old-appearance lure (`final_old_signature_clone_capture`, lower is better)
   - Full advantage ≥ **0.30**;
   - paired-seed 95% CI lower bound > 0;
   - correct direction in at least 3/4 embodiment.

3. Full endpoint nondegeneracy:
   - mean continuity in [0.35, 0.95];
   - exact floor fraction < 0.60;
   - exact ceiling fraction < 0.60.

## Secondary outcomes

- final identity retention;
- recovery latency;
- posterior margin;
- history-reset comparison.

Secondary results cannot rescue a failed primary claim.

## Interpretation boundary

A PASS supports a mechanistic theory of **persistent functional Self** as a compact causal identity anchor across change points.

It does not establish:
- phenomenal consciousness;
- qualia;
- that all autobiographical history must be retained;
- that progressive morphology order is beneficial;
- that the current mechanism is sufficient for indefinite long-horizon identity.
