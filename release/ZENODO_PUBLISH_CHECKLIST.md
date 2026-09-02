# Zenodo release checklist

This repository state contains the complete rerun reported by Paper I and should
receive a new immutable Zenodo version before final manuscript submission.

1. Commit the complete repository state and create the intended GitHub release tag (recommended: `v1.1.0`).
2. Upload/archive that exact release on Zenodo as a **new version** of the preceding deposit `10.5281/zenodo.22207678`.
3. Record the newly assigned **version DOI**.
4. Replace the token `ZENODO-CURRENT-RELEASE-DOI` in:
   - `paper/manuscript/main.tex`
   - `paper/manuscript/supplementary.tex` (if present)
   - `paper/manuscript/references.bib`
   - `paper/manuscript/SCHOLARONE_METADATA.md`
   - `CITATION.cff` (add `doi:`)
5. Recompile the PDF, verify the DOI link, and regenerate `provenance/MANIFEST_SHA256.*`.
6. Do not replace the preceding DOI in historical provenance; it identifies the earlier snapshot.
