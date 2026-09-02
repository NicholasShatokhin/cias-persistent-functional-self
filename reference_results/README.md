# Reference execution

This directory contains outputs from one completed execution of the full protocol. It is provided for inspection, comparison, and independent reanalysis.

The reference execution used:

- Godot: `4.7.stable.official.5b4e0cb0f`
- Python: `3.13.14`
- Canonical core SHA-256: `b81f43221b290fc09c06c69719a24533cdd802fe483347301d6015adda9eb38c`
- Primary confirmatory seeds: `277-306`
- Independent-estimator held-out seeds: `331-360`
- Parameter-sensitivity held-out seeds: `361-390`

The runner does not read files from `reference_results/`; a new execution is generated independently in the active output directories.


## Large raw trace

`additional_experiments/generated/parameter_sensitivity_tracking.csv.gz` is the exact gzip-compressed form of the 323 MB frame-level sensitivity trace. It is compressed solely to remain compatible with ordinary Git/GitHub. `../reference_results/RAW_REFERENCE_FILE.json` records both representations' SHA-256 hashes and byte sizes. Python/pandas reads the gzip file transparently.

The pointwise sensitivity summary is complemented by `parameter_sensitivity_simultaneous.csv` and `.json`, which report a 95% family-wise max-bootstrap interval across all 54 sensitivity effects.
