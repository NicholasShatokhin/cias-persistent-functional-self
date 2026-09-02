# Changelog

## 1.1.0 - 2026-09-02

This release is the complete Paper I reproducibility snapshot accompanying the
full rerun of *A Causal Theory of Persistent Functional Self in Embodied
Artificial Agents*.

### Added

- complete rerun reference execution for the primary diagnostic, preflight and
  confirmatory program;
- independent generic recurrent-estimator comparison on a separate held-out
  seed range;
- 27-setting prespecified parameter-sensitivity experiment;
- family-wise simultaneous max-bootstrap sensitivity analysis across all 54
  setting-by-metric effects;
- exact reference Python environment, `CITATION.cff`, Zenodo release metadata,
  and explicit mixed licensing;
- manuscript and Supplementary Material synchronized to the complete rerun.

### Repository packaging

- the 323 MB frame-level sensitivity trace is stored as deterministic gzip with
  compressed and uncompressed SHA-256 values;
- every Git object is below 100 MB, so Git LFS is not required;
- active execution directories remain clean while the completed execution is
  preserved under `reference_results/`.

### Scientific status

The primary Full-versus-anchor-lesion effect reproduces across all confirmatory
seeds and embodiment profiles. The generic recurrent estimator demonstrates
that an explicit Self anchor is not uniquely required for the structured
benchmark. Parameter sensitivity retains both primary effect directions in
25/27 settings using pointwise descriptive intervals and in 24/27 settings
under the simultaneous family-wise max-bootstrap criterion.
