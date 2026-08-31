# Minimal replication package - Persistent Functional Self Paper I

Author: Mykola Shatokhin (ORCID: 0000-0003-0028-6208)

This package contains only the materials needed to audit/reproduce the narrow v7.0 Paper-I claims. It is not the full CIAS research repository.

## Contents
- `frozen_code/`: frozen ontology and matched adversarial benchmark used by v7.0-r1.
- `protocol/`: scientific protocol and seed ledger.
- `data/`: p1/p2 diagnostics, r1 preflight, and r1 held-out raw CSV/manifests.
- `analysis/`: frozen r1 analyzer and derived confirmatory summaries.
- `provenance/`: scientific-code SHA-256 record.

## Confirmatory analysis
Python requirements: pandas, scipy.

```bash
python analysis/analyze_v70r1.py data/v70r1_heldout_277-306_2026-08-21T12-40-43_raw.csv --outdir reproduced_analysis
```

Expected primary result: confirmatory PASS under the criteria in `protocol/SCIENTIFIC_PROTOCOL_V70R1.md`.

## Scope boundary
The package reproduces a simulation result about persistent *functional* identity. It does not establish phenomenal consciousness or human-like selfhood.

## License
No software/data license is granted by this draft package. Select an explicit public license before publishing the repository.
