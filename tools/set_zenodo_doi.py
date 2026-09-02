#!/usr/bin/env python3
"""Apply the DOI assigned to the current immutable Zenodo release.

This is a release-metadata operation only. It does not alter scientific code,
reference results, metrics, or provenance.
"""
from __future__ import annotations
import argparse
import re
from pathlib import Path

TOKEN = "ZENODO-CURRENT-" + "RELEASE-DOI"
DOI_RE = re.compile(r"^10\.\d{4,9}/[-._;()/:A-Za-z0-9]+$")
TEXT_SUFFIXES = {".md", ".tex", ".bib", ".json", ".cff", ".txt"}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("doi", help="Assigned DOI, e.g. 10.5281/zenodo.12345678")
    ap.add_argument("--repo", default=Path(__file__).resolve().parents[1], type=Path)
    args = ap.parse_args()
    doi = args.doi.strip().removeprefix("https://doi.org/")
    if not DOI_RE.match(doi):
        raise SystemExit(f"Invalid DOI syntax: {doi}")
    repo = args.repo.resolve()
    changed = []
    for p in repo.rglob("*"):
        if not p.is_file() or p.suffix.lower() not in TEXT_SUFFIXES:
            continue
        if any(part in {".git", ".venv-experiments", "__pycache__", ".pytest_cache"} for part in p.parts):
            continue
        try:
            s = p.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        if TOKEN in s:
            p.write_text(s.replace(TOKEN, doi), encoding="utf-8")
            changed.append(p.relative_to(repo).as_posix())

    cff = repo / "CITATION.cff"
    if cff.exists():
        s = cff.read_text(encoding="utf-8")
        if not re.search(r"(?m)^doi:\s*", s):
            anchor = 'version: "1.1.0"\n'
            if anchor in s:
                s = s.replace(anchor, anchor + f'doi: "{doi}"\n')
            else:
                s += f'\ndoi: "{doi}"\n'
            cff.write_text(s, encoding="utf-8")
            changed.append("CITATION.cff")

    remaining=[]
    for p in repo.rglob("*"):
        if p.is_file() and p.suffix.lower() in TEXT_SUFFIXES:
            try:
                if TOKEN in p.read_text(encoding="utf-8"):
                    remaining.append(p.relative_to(repo).as_posix())
            except UnicodeDecodeError:
                pass
    if remaining:
        raise SystemExit("DOI token remains in: " + ", ".join(remaining))
    print(f"Applied DOI {doi} to {len(set(changed))} file(s).")
    print("Rebuild paper/manuscript/main.pdf and supplementary.pdf before submission.")

if __name__ == "__main__":
    main()
