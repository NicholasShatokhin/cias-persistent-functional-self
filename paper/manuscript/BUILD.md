# Building the manuscript

The checked-in PDFs are built from the LaTeX sources in this directory.

Before final journal submission, reserve or publish the current immutable
Zenodo version and apply its DOI from the repository root:

```bash
python tools/set_zenodo_doi.py 10.5281/zenodo.YOUR_CURRENT_VERSION
```

Then rebuild:

```bash
cd paper/manuscript
pdflatex -interaction=nonstopmode main.tex
bibtex main
pdflatex -interaction=nonstopmode main.tex
pdflatex -interaction=nonstopmode main.tex
pdflatex -interaction=nonstopmode supplementary.tex
pdflatex -interaction=nonstopmode supplementary.tex
```

The DOI replacement changes release metadata only; it does not modify the
scientific code or reference results.
