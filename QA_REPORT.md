# Paper I release QA

Date: 2026-09-02

## Scientific package

- Canonical core: `frozen_code/ontology_core.gd`.
- Canonical core SHA-256: `b81f43221b290fc09c06c69719a24533cdd802fe483347301d6015adda9eb38c`.
- Completed reference execution is preserved under `reference_results/`.
- Fresh execution workspaces under `experiments/*/results/` are kept separate from the reference execution.
- Primary confirmatory, independent-estimator and parameter-sensitivity outputs are all represented in the reference execution.
- Pointwise sensitivity criterion: both primary effects retain positive 95% lower bounds in 25/27 settings.
- Family-wise simultaneous max-bootstrap criterion across 54 effects: both primary effects retain positive lower bounds in 24/27 settings.

## Automated checks

- Repository tests: 24/24 PASS.
- GitHub object-size check: PASS.
- Largest repository object: `reference_results/additional_experiments/generated/estimator_heldout_frame_stream.csv`, 54,105,013 bytes.
- 323 MB raw parameter-sensitivity tracking trace is stored as deterministic gzip with compressed and uncompressed SHA-256 values recorded in `reference_results/RAW_REFERENCE_FILE.json`.
- All 27 prespecified parameter variants are generated through a fail-closed patcher tied to the canonical core hash.

## Runtime validation

Both execution harnesses were smoke-tested with Godot `4.7.stable.official.5b4e0cb0f`:

- paper experiment harness: PASS, 240-frame smoke run;
- additional-experiment harness: PASS, 240-frame smoke run.

The smoke tests do not open protected held-out seeds.

## Manuscript preflight

- Main manuscript: 9 pages, PDF openable, not encrypted, not scanned, Type 3 fonts = 0.
- Supplementary Material: 6 pages, PDF openable, not encrypted, not scanned, Type 3 fonts = 0.
- Bibliography diacritics render as Sörös, Müller and Schölkopf.
- Chen et al. 2026 includes arXiv:2606.13222 and DOI 10.48550/arXiv.2606.13222.
- The Supplementary `E_Self` linear discriminant is typeset as one numbered equation.

## Release metadata

- `LICENSE`, `CITATION.cff`, `.zenodo.json`, exact reference environment and Zenodo publication checklist are present.
- A new immutable Zenodo version has not been invented or assumed by this repository state. The manuscript source uses `ZENODO-CURRENT-RELEASE-DOI` until a DOI is assigned.
- After Zenodo assigns the DOI, run `python tools/set_zenodo_doi.py <DOI>` and rebuild the manuscript PDFs before journal submission.
