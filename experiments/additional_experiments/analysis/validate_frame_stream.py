#!/usr/bin/env python3
from pathlib import Path
import argparse, sys, pandas as pd
VISIBLE=['x','y','appearance_0','appearance_1','appearance_2','appearance_3','efference','outcome','motor','proprio','temporal','crossmodal','persistence','physical','autonomy','goal','response','tool','intero','homeo','history']
META=['run_id','seed','profile','scenario','frame','time_s','observation_id','scene_hash','change_point','is_true_lineage','is_lure']
def main():
    ap=argparse.ArgumentParser(); ap.add_argument('csv'); ap.add_argument('--expected-first',type=int); ap.add_argument('--expected-last',type=int); a=ap.parse_args(); d=pd.read_csv(a.csv)
    miss=[c for c in META+VISIBLE if c not in d.columns]
    if miss: raise SystemExit(f'missing columns: {miss}')
    if d[META+VISIBLE].isna().any().any(): raise SystemExit('NaN detected in required fields')
    cues=[c for c in VISIBLE if c not in ['x','y']]
    bad=((d[cues].astype(float)<-1e-9)|(d[cues].astype(float)>1+1e-9)).any().any()
    if bad: raise SystemExit('cue outside [0,1]')
    if a.expected_first is not None:
        got=set(d.seed.astype(int).unique()); exp=set(range(a.expected_first,a.expected_last+1))
        if got!=exp: raise SystemExit(f'seed coverage mismatch got={sorted(got)} expected={sorted(exp)}')
    for run,g in d.groupby('run_id'):
        frames=set(g.frame.astype(int));
        if frames!=set(range(240)): raise SystemExit(f'{run}: frame coverage mismatch')
        if g.scene_hash.nunique()!=1: raise SystemExit(f'{run}: scene_hash not constant')
        by=g.groupby('frame')
        if not all(x.is_true_lineage.astype(int).sum()==1 for _,x in by): raise SystemExit(f'{run}: true-lineage multiplicity error')
    print(f'FRAME_STREAM_VALID rows={len(d)} runs={d.run_id.nunique()} seeds={d.seed.nunique()}')
if __name__=='__main__':main()
