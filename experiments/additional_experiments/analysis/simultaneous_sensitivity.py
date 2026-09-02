#!/usr/bin/env python3
"""Family-wise max-bootstrap intervals for the 27-setting sensitivity experiment.

The resampling unit is the held-out seed. The same sampled seed indices are used
for every parameter setting and both primary effects, preserving their
cross-setting dependence. The 95% simultaneous interval uses the 95th
percentile of the maximum absolute centered bootstrap deviation over all
27 x 2 = 54 effects.
"""
from __future__ import annotations
import argparse, json
from pathlib import Path
import numpy as np
import pandas as pd


def build_effect_cube(df: pd.DataFrame):
    required={"parameter_id","condition","seed","profile","identity_continuity","lure_capture"}
    missing=required-set(df.columns)
    if missing:
        raise SystemExit(f"missing columns: {sorted(missing)}")
    g=(df.groupby(["parameter_id","seed","condition"],as_index=False)
         .agg(identity_continuity=("identity_continuity","mean"),
              lure_capture=("lure_capture","mean")))
    pv=g.pivot(index=["parameter_id","seed"],columns="condition",
               values=["identity_continuity","lure_capture"])
    for cond in ("cias_full","cias_no_persistent_self"):
        if ("identity_continuity",cond) not in pv.columns:
            raise SystemExit(f"missing condition {cond}")
    e=pd.DataFrame(index=pv.index)
    e["identity_continuity_advantage"]=(pv[("identity_continuity","cias_full")]
                                       -pv[("identity_continuity","cias_no_persistent_self")])
    e["lure_rejection_advantage"]=(pv[("lure_capture","cias_no_persistent_self")]
                                   -pv[("lure_capture","cias_full")])
    e=e.reset_index()
    pids=sorted(e.parameter_id.unique())
    seeds=sorted(e.seed.unique())
    cube=np.empty((len(pids),len(seeds),2),dtype=float)
    metrics=["identity_continuity_advantage","lure_rejection_advantage"]
    for i,pid in enumerate(pids):
        sub=e[e.parameter_id==pid].set_index("seed")
        if set(sub.index)!=set(seeds):
            raise SystemExit(f"incomplete seed support for {pid}")
        sub=sub.loc[seeds]
        cube[i,:,0]=sub[metrics[0]].to_numpy()
        cube[i,:,1]=sub[metrics[1]].to_numpy()
    return pids,seeds,metrics,cube


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--csv",required=True)
    ap.add_argument("--grid-summary",required=True,help="parameter_sensitivity_summary_basin.csv")
    ap.add_argument("--out",required=True)
    ap.add_argument("--reps",type=int,default=20000)
    ap.add_argument("--seed",type=int,default=20260902)
    a=ap.parse_args()
    df=pd.read_csv(a.csv)
    pids,seeds,metrics,cube=build_effect_cube(df)
    observed=cube.mean(axis=1)
    rng=np.random.default_rng(a.seed)
    max_dev=np.empty(a.reps,dtype=float)
    n=len(seeds)
    for b in range(a.reps):
        idx=rng.integers(0,n,n)
        boot=cube[:,idx,:].mean(axis=1)
        max_dev[b]=np.abs(boot-observed).max()
    critical=float(np.quantile(max_dev,0.95))
    low=observed-critical
    high=observed+critical
    labels=pd.read_csv(a.grid_summary)[["parameter_id","label"]].drop_duplicates()
    label_map=dict(zip(labels.parameter_id,labels.label))
    rows=[]
    for i,pid in enumerate(pids):
        row={"parameter_id":pid,"label":label_map.get(pid,pid)}
        for j,m in enumerate(metrics):
            prefix="identity" if j==0 else "lure_rejection"
            row[f"{prefix}_advantage"]=float(observed[i,j])
            row[f"{prefix}_simultaneous_low"]=float(low[i,j])
            row[f"{prefix}_simultaneous_high"]=float(high[i,j])
        row["both_simultaneous_positive"]=bool((low[i,:]>0).all())
        rows.append(row)
    out=Path(a.out); out.parent.mkdir(parents=True,exist_ok=True)
    pd.DataFrame(rows).to_csv(out,index=False)
    meta={
      "method":"seed-resampled max-absolute-deviation bootstrap",
      "family":"all 54 sensitivity effects (27 settings x 2 primary metrics)",
      "confidence_level":0.95,
      "bootstrap_replicates":a.reps,
      "rng_seed":a.seed,
      "resampling_unit":"held-out seed, shared jointly across all settings and metrics",
      "critical_max_absolute_deviation":critical,
      "settings":len(pids),
      "seeds":len(seeds),
      "both_simultaneous_positive_count":int(sum(r["both_simultaneous_positive"] for r in rows)),
      "both_simultaneous_positive_fraction":float(np.mean([r["both_simultaneous_positive"] for r in rows])),
      "output_csv":out.name,
    }
    out.with_suffix('.json').write_text(json.dumps(meta,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(meta,indent=2))

if __name__=="__main__": main()
