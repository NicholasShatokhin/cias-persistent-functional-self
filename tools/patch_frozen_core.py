#!/usr/bin/env python3
from pathlib import Path
import argparse, json, re, hashlib

def fmt(x):
    s=f"{float(x):.10f}".rstrip('0').rstrip('.')
    return s if '.' in s else s+'.0'

def replace_once(text, pattern, repl, label):
    out,n=re.subn(pattern,repl,text,count=1,flags=re.M)
    if n!=1: raise ValueError(f"patch target {label!r} expected once, found {n}")
    return out

def patch(text,cfg):
    ow=cfg['ordinary_weights']; pw=cfg['postchange_weights']
    text=replace_once(text,r"var signature_weight: float = 0\.43\s*\n\s*var position_weight: float = 0\.37\s*\n\s*var dynamic_weight: float = 0\.20",
        f"var signature_weight: float = {fmt(ow[0])}\n\tvar position_weight: float = {fmt(ow[1])}\n\tvar dynamic_weight: float = {fmt(ow[2])}",'ordinary_weights')
    text=replace_once(text,r"signature_weight = 0\.20\s*\n\s*position_weight = 0\.29\s*\n\s*dynamic_weight = 0\.51",
        f"signature_weight = {fmt(pw[0])}\n\t\tposition_weight = {fmt(pw[1])}\n\t\tdynamic_weight = {fmt(pw[2])}",'postchange_weights')
    text=replace_once(text,r"(func _association_threshold\(\) -> float:\s*\n\s*if change_point_seen[^\n]*:\s*\n\s*)return 0\.82\s*\n\s*return 0\.66",
        rf"\g<1>return {fmt(cfg['postchange_threshold'])}\n\treturn {fmt(cfg['ordinary_threshold'])}",'association_thresholds')
    text=replace_once(text,r"(_observation_self_anchor_strength\(observation\)\s*>\s*)0\.62",rf"\g<1>{fmt(cfg['new_entity_anchor_gate'])}",'new_entity_anchor_gate')
    text=replace_once(text,r"(observation_self\s*>\s*)0\.70",rf"\g<1>{fmt(cfg['persistent_reconnect_gate'])}",'persistent_reconnect_gate')
    scale=float(cfg['smoothing_scale'])
    targets=[('role_alpha',r"var alpha: float = 0\.12",f"var alpha: float = {fmt(0.12*scale)}"),
             ('velocity_alpha',r"\.lerp\(observed_velocity, 0\.24\)",f".lerp(observed_velocity, {fmt(0.24*scale)})"),
             ('position_alpha',r"\.lerp\(new_position, 0\.48\)",f".lerp(new_position, {fmt(0.48*scale)})"),
             ('signature_alpha',r"0\.10 if not change_point_seen else 0\.06",f"{fmt(0.10*scale)} if not change_point_seen else {fmt(0.06*scale)}")]
    for label,pat,repl in targets: text=replace_once(text,pat,repl,label)
    ac=float(cfg['anchor_cost_scale'])
    text=replace_once(text,r"cost = 0\.015 \+ 0\.06 \* \(1\.0 - observation_self\) \+ 0\.04 \* \(1\.0 - entity_anchor\)",
        f"cost = {fmt(0.015*ac)} + {fmt(0.06*ac)} * (1.0 - observation_self) + {fmt(0.04*ac)} * (1.0 - entity_anchor)",'anchor_cost')
    text=replace_once(text,r"cost \+= 0\.45 \* \(1\.0 - observation_self\)",f"cost += {fmt(0.45*ac)} * (1.0 - observation_self)",'low_anchor_persistent_penalty')
    np=float(cfg['nonpersistent_penalty_scale'])
    text=replace_once(text,r"cost \+= 2\.0 \* observation_self",f"cost += {fmt(2.0*np)} * observation_self",'nonpersistent_penalty')
    return text

def load_expected_sha(source: Path) -> tuple[str, Path]:
    repo = Path(__file__).resolve().parents[1]
    meta_path = repo/'provenance/FROZEN_CORE_IDENTITY.json'
    meta=json.loads(meta_path.read_text(encoding='utf-8'))
    return str(meta['sha256']).lower(), meta_path

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--source',required=True); ap.add_argument('--grid',required=True); ap.add_argument('--outdir',required=True); ap.add_argument('--manifest',required=True)
    a=ap.parse_args(); src=Path(a.source); text=src.read_text(encoding='utf-8')
    digest=hashlib.sha256(src.read_bytes()).hexdigest(); expected,meta_path=load_expected_sha(src)
    if digest != expected:
        raise SystemExit(f"Refusing to patch non-canonical frozen source: actual={digest} expected={expected}")
    configs=[json.loads(x) for x in Path(a.grid).read_text().splitlines() if x.strip()]
    outdir=Path(a.outdir); outdir.mkdir(parents=True,exist_ok=True); rows=[]
    for cfg in configs:
        pid=cfg['parameter_id']; out=outdir/f"ontology_core_{pid}.gd"
        patched=text if cfg.get('label')=='central' else patch(text,cfg)
        out.write_text(patched,encoding='utf-8',newline='\n')
        rows.append({'parameter_id':pid,'label':cfg.get('label'),'script':out.name,'sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'parameters':cfg})
    Path(a.manifest).parent.mkdir(parents=True,exist_ok=True)
    Path(a.manifest).write_text(json.dumps({'central_source_sha256':expected,'identity_metadata':str(meta_path),'generated':rows},indent=2)+'\n',encoding='utf-8')
    print(f"Generated {len(rows)} runtime ontology scripts -> {outdir}")
if __name__=='__main__': main()
