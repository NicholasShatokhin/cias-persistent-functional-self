#!/usr/bin/env python3
from pathlib import Path
import hashlib, json
ROOT=Path(__file__).resolve().parents[1]
EXCLUDE={'.git','.venv-experiments','__pycache__','.pytest_cache'}
rows=[]
def is_ephemeral(rel:Path)->bool:
    parts=rel.parts
    posix=rel.as_posix()
    if '.godot' in parts: return True
    if '/godot/runtime/' in '/'+posix and rel.suffix=='.gd': return True
    if '/godot/work/' in '/'+posix and rel.suffix=='.json': return True
    if posix.startswith('experiments/additional_experiments/work/'): return True
    return False

for p in sorted(ROOT.rglob('*')):
    if not p.is_file(): continue
    rel=p.relative_to(ROOT)
    if any(part in EXCLUDE for part in rel.parts): continue
    if is_ephemeral(rel): continue
    if rel.as_posix() in {'provenance/MANIFEST_SHA256.json','provenance/MANIFEST_SHA256.txt'}: continue
    rows.append({'path':rel.as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size})
(ROOT/'provenance/MANIFEST_SHA256.json').write_text(json.dumps({'files':rows},indent=2)+'\n',encoding='utf-8')
(ROOT/'provenance/MANIFEST_SHA256.txt').write_text(''.join(f"{r['sha256']}  {r['path']}\n" for r in rows),encoding='utf-8')
print(f'Manifest: {len(rows)} files')
