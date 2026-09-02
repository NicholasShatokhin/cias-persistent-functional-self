# Complete experimental program

This document defines the experimental stages implemented by this repository.

## Primary experiment sequence

| Stage | Seeds | Conditions | Runs | Purpose |
|---|---:|---:|---:|---|
| Initial diagnostic | 253-260 | 6 | 192 | Reproduce the ceiling and unmatched-change-point failure mode of the first benchmark design. |
| Matched diagnostic | 261-272 | 6 | 288 | Evaluate the repaired matched design, stronger lure, epoch-aware reset evaluation, and theory-reduction conditions. |
| Preflight | 273-276 | 3 | 48 | Structural and nondegeneracy gate; desired effect direction is not a pass criterion. |
| Confirmatory | 277-306 | 3 | 360 | Primary comparison of Full, persistent-anchor lesion, and history-reset control. |

Seeds 307-314 are intentionally unused in this package.

## Additional experiments

| Stage | Seeds | Purpose |
|---|---:|---|
| Independent-estimator diagnostic | 315-326 | Fit and select a generic recurrent state estimator using diagnostic labels only. |
| Independent-estimator preflight | 327-330 | Technical validation of the frozen diagnostic-only estimator. |
| Independent-estimator held-out | 331-360 | Matched comparison against CIAS Full and lesion on untouched observations. |
| Parameter-sensitivity held-out | 361-390 | Evaluate 27 prespecified parameter settings on a separate untouched seed range. |

The two additional held-out ranges are disjoint by design.

## One run

Each run contains 240 frames at 0.1 s per frame. Four 42-frame sensorimotor exposure blocks are followed by a 72-frame adversarial probe. Change points occur at frames 42, 84, 126, and 168. The final probe transforms and relocates the true body while an old-looking lure preserves appearance/location continuity and receives partially plausible causal cues.

The environment does not supply a privileged Self identifier to the ontology. Ground-truth fields are retained by evaluators and, during diagnostic fitting only, by the comparator-training procedure.

## Reproducibility boundary

`frozen_code/ontology_core.gd` is the canonical executable mechanism for this repository. Its SHA-256 is recorded in `provenance/FROZEN_CORE_IDENTITY.json` and checked before execution.

`reference_results/` stores one completed execution for comparison and inspection. The runners write new outputs only to the active `experiments/*/results/generated/` and `provenance/*_execution/` paths; reference outputs are never read as model inputs.
