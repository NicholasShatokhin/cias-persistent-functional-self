#!/usr/bin/env python3
from pathlib import Path
import argparse

DEFAULT_LIMIT=100*1024*1024

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--repo',default='.')
    ap.add_argument('--limit-bytes',type=int,default=DEFAULT_LIMIT)
    a=ap.parse_args()
    root=Path(a.repo).resolve()
    bad=[]; largest=[]
    for p in root.rglob('*'):
        if not p.is_file() or '.git' in p.parts:
            continue
        n=p.stat().st_size
        largest.append((n,p.relative_to(root).as_posix()))
        if n>a.limit_bytes: bad.append((n,p.relative_to(root).as_posix()))
    largest.sort(reverse=True)
    if bad:
        for n,name in bad: print(f'GITHUB_OBJECT_TOO_LARGE {n} {name}')
        raise SystemExit(2)
    print(f'GITHUB_SIZE_CHECK_PASS files={len(largest)} largest={largest[0][0] if largest else 0} path={largest[0][1] if largest else "-"}')

if __name__=='__main__': main()
