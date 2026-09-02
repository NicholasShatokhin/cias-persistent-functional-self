# Results traceability

All numerical results reported in the updated manuscript are traceable to the completed reference execution in the public reproducibility package.

## Primary confirmatory experiment

Seed range: 277–306.

Reference paths:

- `reference_results/paper_experiments/generated/confirmatory_runs.csv`
- `reference_results/paper_experiments/generated/analysis/confirmatory_analysis.json`
- `reference_results/paper_experiments/generated/analysis/confirmatory_effects.csv`

Statistical unit: one seed after averaging matched conditions across the four embodiment profiles. Primary confidence intervals use paired t intervals over 30 seed-level Full-minus-lesion differences.

## Independent recurrent estimator

Ranges:

- fitting/CV: 315–326;
- technical preflight: 327–330;
- held-out evaluation: 331–360.

Reference paths:

- `reference_results/additional_experiments/generated/estimator_heldout_frame_stream.csv`
- `reference_results/additional_experiments/generated/estimator_heldout_cias_run_metrics.csv`
- `reference_results/additional_experiments/generated/generic_heldout/run_metrics.csv`
- `reference_results/additional_experiments/generated/generic_heldout/model_fit.json`
- `reference_results/additional_experiments/generated/cias_vs_generic_heldout_summary.csv`

CIAS-versus-generic intervals use 10,000 nonparametric bootstrap resamples of the 30 paired seed-level differences.

## Parameter sensitivity

Held-out range: 361–390.

Reference paths:

- `reference_results/additional_experiments/generated/parameter_sensitivity_run_metrics.csv`
- `reference_results/additional_experiments/generated/parameter_sensitivity_summary.csv`
- `reference_results/additional_experiments/generated/parameter_sensitivity_summary_basin.csv`
- `reference_results/additional_experiments/generated/parameter_sensitivity_summary_overview.json`

The sweep contains 27 prespecified parameter settings, two CIAS conditions, four profiles, and 30 seeds per setting. Confidence intervals use 10,000 nonparametric bootstrap resamples of paired seed-level effects.

## Execution identity

Canonical scientific core:

`frozen_code/ontology_core.gd`

SHA-256:

`b81f43221b290fc09c06c69719a24533cdd802fe483347301d6015adda9eb38c`

Reference execution runtime:

- Godot 4.7 stable;
- Python 3.13.14.
