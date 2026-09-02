#!/usr/bin/env python3
from pathlib import Path
import argparse,json,hashlib,random

def normalize(v):
    s=sum(v); return [x/s for x in v]
def pid(d):
    raw=json.dumps(d,sort_keys=True,separators=(',',':')).encode(); return hashlib.sha256(raw).hexdigest()[:16]

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--config',required=True); ap.add_argument('--out',required=True); args=ap.parse_args()
    spec=json.loads(Path(args.config).read_text()); c=spec['central']; configs=[]
    def add(label,d):
        q=dict(d); q['label']=label; q['parameter_id']=pid(q); configs.append(q)
    add('central',c)
    # One-component weight perturbations, renormalized.
    # Perturb the causal-role component (index 2) and renormalize the mixture.
    # This moves mass jointly against appearance/position while keeping the grid compact.
    for fam in ['ordinary','postchange']:
        key=fam+'_weights'; vals=c[key]; i=2
        for scale in spec['one_factor'][fam+'_weight_component_scale']:
            d=dict(c); vv=list(vals); vv[i]*=scale; d[key]=normalize(vv); add(f'{fam}_causal_weight_x{scale}',d)
    for key in ['ordinary_threshold','postchange_threshold','new_entity_anchor_gate','persistent_reconnect_gate','smoothing_scale','anchor_cost_scale','nonpersistent_penalty_scale']:
        for val in spec['one_factor'][key]:
            d=dict(c); d[key]=val; add(f'{key}_{val}',d)
    # Deterministic stratified joint sample inside stated ranges.
    rng=random.Random(spec['joint_sample']['seed'])
    ranges={
      'ordinary_threshold':(0.58,0.74),'postchange_threshold':(0.74,0.90),
      'new_entity_anchor_gate':(0.56,0.68),'persistent_reconnect_gate':(0.63,0.77),
      'smoothing_scale':(0.80,1.20),'anchor_cost_scale':(0.75,1.25),'nonpersistent_penalty_scale':(0.75,1.25)}
    n=spec['joint_sample']['count']
    strata=list(range(n))
    cols={k:rng.sample(strata,n) for k in ranges}
    for r in range(n):
        d=dict(c)
        for key,(lo,hi) in ranges.items():
            u=(cols[key][r]+0.5)/n; d[key]=lo+(hi-lo)*u
        # Modestly perturb all mixture components, then renormalize.
        for key in ['ordinary_weights','postchange_weights']:
            base=c[key]; factors=[0.8+0.4*rng.random() for _ in base]; d[key]=normalize([x*f for x,f in zip(base,factors)])
        add(f'joint_{r:02d}',d)
    out=Path(args.out); out.parent.mkdir(parents=True,exist_ok=True)
    with out.open('w',encoding='utf-8') as f:
        for d in configs: f.write(json.dumps(d,sort_keys=True)+"\n")
    print(f'{len(configs)} parameter configurations -> {out}')
if __name__=='__main__': main()
