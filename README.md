# Persistent Functional Self — Reproducibility Package

Code, protocols, analysis scripts, and reference outputs for the study **A Causal Theory of Persistent Functional Self in Embodied Artificial Agents**.

The repository is designed for independent use. A fresh checkout can reproduce the full experimental program with a local Godot 4.7.x executable. One completed reference execution is included under `reference_results/`; those files are never used as inputs by the runners.

## Requirements

- Windows 10/11 or Linux
- Python 3.10+
- Godot Engine **4.7.x** standard build
- Internet access on the first run so Python can install the packages in `requirements.txt`

## Quick start

### 1. Smoke test

Windows:

```powershell
.\RUN_SMOKE_WINDOWS.bat "C:\path\to\Godot_v4.7-stable_win64.exe"
```

Linux:

```bash
./RUN_SMOKE_LINUX.sh /path/to/godot
```

The smoke test validates both headless Godot harnesses and does not open any confirmatory or held-out seed range.

### 2. Full reproduction

Windows:

```powershell
.\RUN_ALL_WINDOWS.bat "C:\path\to\Godot_v4.7-stable_win64.exe"
```

Linux:

```bash
./RUN_ALL_LINUX.sh /path/to/godot
```

The runner creates its Python environment, verifies the canonical ontology hash, executes every stage, computes all summaries, and writes execution provenance automatically.

## Experimental program

| Stage | Seeds | Purpose |
|---|---:|---|
| Initial diagnostic | 253–260 | Reproduce the ceiling and unmatched-change-point failure mode of the first benchmark design. |
| Matched diagnostic | 261–272 | Evaluate the repaired matched design and theory-reduction conditions. |
| Preflight | 273–276 | Structural and nondegeneracy checks before the primary confirmatory range. |
| Confirmatory | 277–306 | Full, persistent-anchor lesion, and history-reset comparison. |
| Generic-estimator diagnostic | 315–326 | Fit a generic recurrent estimator on diagnostic labels only. |
| Comparator preflight | 327–330 | Technical validation of the frozen diagnostic-only estimator. |
| Independent-estimator held-out | 331–360 | Compare CIAS with the generic estimator on untouched observations. |
| Parameter-sensitivity held-out | 361–390 | Evaluate 27 prespecified parameter settings on a separate untouched range. |

Seeds 307–314 are intentionally unused in this package.

The complete stage definitions are in `protocols/COMPLETE_EXPERIMENTAL_PROGRAM.md`.

## Included reference execution

`reference_results/` contains one completed execution produced with Godot `4.7.stable.official.5b4e0cb0f` and the canonical core identified in `provenance/FROZEN_CORE_IDENTITY.json`.

Headline outputs from that execution:

- Full vs persistent-anchor lesion, identity-continuity advantage: **0.4734**, 95% CI **[0.4160, 0.5308]**.
- Full vs persistent-anchor lesion, lure-rejection advantage: **0.7405**, 95% CI **[0.6529, 0.8280]**.
- CIAS Full minus generic recurrent estimator, continuity: **−0.0506**, 95% CI **[−0.0676, −0.0345]**.
- CIAS Full minus generic recurrent estimator, lure rejection: **−0.0218**, 95% CI **[−0.0314, −0.0130]**.
- Both primary Full-vs-lesion effect signs were preserved in **25/27 (92.6%)** prespecified parameter settings using pointwise descriptive 95% bootstrap intervals.
- A family-wise max-bootstrap check across all **54 sensitivity effects** retained simultaneous positive lower bounds for both primary effects in **24/27 (88.9%)** settings.

Negative CIAS-minus-generic values mean that the generic recurrent estimator scored slightly higher on those two held-out metrics. The raw and derived files are retained so this comparison can be inspected directly. The 323 MB frame-level parameter-sensitivity trace is stored as deterministic `parameter_sensitivity_tracking.csv.gz` (about 7.5 MB); `reference_results/RAW_REFERENCE_FILE.json` records SHA-256 hashes and sizes for both compressed and uncompressed representations. No Git LFS is required, and every file in the repository is below GitHub's 100 MB object limit.

To materialize the large trace locally without changing the repository copy:

```bash
gzip -dk reference_results/additional_experiments/generated/parameter_sensitivity_tracking.csv.gz
```

The decompressed CSV can be verified against `reference_results/RAW_REFERENCE_FILE.json`.

## Output locations for a new run

A fresh run writes new files to:

```text
experiments/paper_experiments/results/generated/
experiments/additional_experiments/results/generated/
provenance/paper_experiments_execution/
provenance/additional_experiments_execution/
provenance/EXECUTION_SUMMARY.json
```

These paths are intentionally separate from `reference_results/`.

## Interrupted execution

A held-out access marker is written before the first run in each protected range. If execution stops after a protected range has been opened, continue with:

```powershell
.\RUN_RESUME_WINDOWS.bat "C:\path\to\Godot_v4.7-stable_win64.exe"
```

Resume mode preserves completed stages and continues from the existing checkpoint. It does not present a repeated held-out execution as a fresh opening.

## Canonical mechanism

The executable ontology is:

```text
frozen_code/ontology_core.gd
```

Its SHA-256 is stored in `provenance/FROZEN_CORE_IDENTITY.json` and verified automatically before execution.

## Repository layout

```text
frozen_code/                         canonical ontology mechanism
experiments/paper_experiments/      diagnostic, preflight, and confirmatory harness
experiments/additional_experiments/ independent estimator and parameter sensitivity
protocols/                           experimental specification
reference_results/                   completed reference execution; never used as runner input
provenance/                          canonical hashes and local execution metadata
tests/                               regression and reproducibility checks
tools/                               orchestration, patching, manifest, and GitHub-size utilities
reference_environment/               exact Python/Godot versions for the included execution
paper/manuscript/                     current Paper I manuscript and supplementary material
release/                              Zenodo publication checklist
```


## Reconstructing the reference software environment

A new reproduction run uses compatible ranges from `requirements.txt`. The exact Python package versions recorded for the included reference execution are pinned in:

```text
reference_environment/requirements-reference.txt
```

The reference execution used Python `3.13.14` and Godot `4.7.stable.official.5b4e0cb0f`.

## GitHub and archival storage

The repository is intentionally usable with ordinary Git. `tools/verify_github_limits.py` checks that no file exceeds GitHub's 100 MB hard object limit. The only original output above that threshold, the frame-level parameter-sensitivity trace, is stored as `.csv.gz`; pandas can read it directly with `pandas.read_csv`.

The complete rerun has reserved Zenodo version DOI `10.5281/zenodo.22253924`. The Zenodo draft should contain the current repository archive, its SHA-256 checksum, and standalone copies of the main and supplementary PDFs. Do not import the obsolete file set from the preceding version. `.zenodo.json` contains the record metadata and `release/ZENODO_PUBLISH_CHECKLIST.md` lists the publication checks. The preceding DOI `10.5281/zenodo.22207678` remains an immutable historical snapshot.

## Citation and licensing

Citation metadata are provided in `CITATION.cff`. Software is licensed under MIT; reference data are made available under CC BY 4.0 as described in `LICENSE`. Manuscript copyright is handled separately from the software license.
