# Paper I manuscript

The current Paper I submission sources and compiled PDFs are in `paper/manuscript/`.

`paper/pre_rerun_reference/supplementary.tex` exists only because the immutable `frozen_code/ontology_core.gd` contains a historical comment referring to that path. The runner does not read either paper directory. The canonical executable mechanism is identified by `provenance/FROZEN_CORE_IDENTITY.json`.

Before final submission, publish this exact repository state as a new immutable Zenodo version and replace `ZENODO-CURRENT-RELEASE-DOI` in the manuscript/release metadata with the newly assigned version DOI.
