# Replication Package for *A Causal Theory of Persistent Functional Self in Embodied Artificial Agents*

[![DOI](https://zenodo.org/badge/DOI/PENDING.svg)](https://zenodo.org/)

**Author:** Mykola Shatokhin  
**ORCID:** https://orcid.org/0000-0003-0028-6208  
**Repository:** https://github.com/NicholasShatokhin/cias-persistent-functional-self

This repository contains the frozen materials required to audit and reproduce the narrow claims reported in:

> **A Causal Theory of Persistent Functional Self in Embodied Artificial Agents**

The repository is a **replication package**, not the full CIAS research repository.

## Scientific scope

The package concerns persistent **functional** identity in simulated embodied artificial agents. It tests whether identity remains associated with causal continuity when appearance, position, and selected short-term causal cues become misleading.

It does **not** establish phenomenal consciousness, qualia, or human-like selfhood.

## Repository contents

- `frozen_code/` — frozen ontology and adversarial benchmark used by the v7.0 confirmatory program.
- `protocol/` — frozen scientific protocol and seed ledger.
- `data/` — v7.0-p1/p2 diagnostic data and v7.0-r1 preflight/held-out raw data and manifests.
- `analysis/` — frozen confirmatory analyzer and derived summaries.
- `provenance/` — SHA-256 record for frozen scientific code.
- `CITATION.cff` — machine-readable citation metadata.
- `LICENSES.md` and `LICENSES/` — code/data licensing.

## Primary confirmatory experiment

The frozen **v7.0-r1** experiment used:

- preflight seeds `273–276`;
- held-out seeds `277–306`;
- four embodiment profiles;
- three frozen conditions;
- `360/360` held-out runs after preflight PASS.

The confirmatory claim is deliberately narrow: a **persistent causal identity anchor** is necessary for robust functional Self continuity under the frozen adversarial morphology/appearance-change task.

## Reproduce the confirmatory analysis

### Requirements

Python 3.10+ with:

```bash
pip install pandas scipy
```

### Run

From the repository root:

```bash
python analysis/analyze_v70r1.py \
  data/v70r1_heldout_277-306_2026-08-21T12-40-43_raw.csv \
  --outdir reproduced_analysis
```

On Windows PowerShell:

```powershell
python .\analysis\analyze_v70r1.py `
  .\data\v70r1_heldout_277-306_2026-08-21T12-40-43_raw.csv `
  --outdir .\reproduced_analysis
```

The expected decision is **confirmatory PASS** under the criteria frozen in:

`protocol/SCIENTIFIC_PROTOCOL_V70R1.md`

## Integrity and provenance

The frozen identity code hashes are recorded in:

`provenance/FROZEN_SCIENTIFIC_CODE_SHA256.json`

Repository-file hashes are listed in:

`SHA256SUMS.txt`

To verify the release archive after downloading it, compare its SHA-256 with the checksum published in the corresponding GitHub Release / Zenodo record.

## Citation

GitHub will display citation metadata from [`CITATION.cff`](CITATION.cff).

For release `v1.0.0`, cite the archived Zenodo record once the DOI is minted. The associated article is **"A Causal Theory of Persistent Functional Self in Embodied Artificial Agents"**. Its public preprint/journal citation will be added here when available.

## Licensing

This is a mixed-content research repository:

- **software/code:** MIT License;
- **data and documentation:** CC BY 4.0.

See [`LICENSES.md`](LICENSES.md) for the exact scope.

## Reproducibility boundary

This package reproduces the reported analysis from frozen raw results. It does not claim to reproduce the complete developmental history of the CIAS project or every exploratory experiment that preceded the frozen confirmatory protocol.
