#!/usr/bin/env python3
from pathlib import Path
import argparse, sys
import pandas as pd
sys.path.insert(0,str(Path(__file__).resolve().parent))
from paired_effects import bootstrap_mean_ci

KEYS=['seed','profile','scenario']

def _select_cias(df: pd.DataFrame, condition: str) -> pd.DataFrame:
    """Select one CIAS condition from run-level metrics.

    analyze_cias_tracking.py stores CIAS variants in the `condition` column,
    whereas evaluate_streams.py stores baseline variants in `model`.
    Keep these schemas explicit so Full and lesion rows can never be merged
    together accidentally.
    """
    if 'condition' not in df.columns:
        raise SystemExit('CIAS metrics missing required column: condition')
    out=df[df['condition'].astype(str)==str(condition)].copy()
    if out.empty:
        vals=sorted(map(str,df['condition'].dropna().unique()))
        raise SystemExit(f'CIAS condition {condition!r} not found; available: {vals}')
    return out

def _select_baseline(df: pd.DataFrame, model: str) -> pd.DataFrame:
    if 'model' not in df.columns:
        raise SystemExit('baseline metrics missing required column: model')
    out=df[df['model'].astype(str)==str(model)].copy()
    if out.empty:
        vals=sorted(map(str,df['model'].dropna().unique()))
        raise SystemExit(f'baseline model {model!r} not found; available: {vals}')
    return out

def _assert_unique(df: pd.DataFrame, keys, label: str) -> None:
    dup=df.duplicated(keys,keep=False)
    if dup.any():
        sample=df.loc[dup,keys].drop_duplicates().head(12).to_dict('records')
        raise SystemExit(f'{label} keys are not unique after variant selection for {keys}; sample duplicates: {sample}')

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--cias',required=True,help='CIAS run-level metrics CSV')
    ap.add_argument('--baseline',required=True,help='baseline run_metrics.csv from evaluate_streams.py')
    ap.add_argument('--out',required=True)
    ap.add_argument('--cias-condition',default='cias_full',help='CIAS condition to compare; default: cias_full')
    # Backward-compatible spelling retained for any existing command line from FIXED4.
    ap.add_argument('--cias-model',dest='cias_condition_legacy',default=None,help=argparse.SUPPRESS)
    ap.add_argument('--baseline-model',default='generic_recurrent_filter')
    args=ap.parse_args()
    cias_condition=args.cias_condition_legacy or args.cias_condition
    a=_select_cias(pd.read_csv(args.cias),cias_condition)
    b=_select_baseline(pd.read_csv(args.baseline),args.baseline_model)
    keys=[k for k in KEYS if k in a.columns and k in b.columns]
    if not keys:
        raise SystemExit('CIAS and baseline have no shared pairing keys')
    need=['identity_continuity','lure_capture']
    for d,n in [(a,'CIAS'),(b,'baseline')]:
        miss=[x for x in keys+need if x not in d.columns]
        if miss: raise SystemExit(f'{n} missing columns: {miss}')
    _assert_unique(a,keys,f'CIAS condition {cias_condition}')
    _assert_unique(b,keys,f'baseline model {args.baseline_model}')
    x=a[keys+need].merge(b[keys+need],on=keys,suffixes=('_cias','_baseline'),validate='one_to_one')
    if len(x)!=len(a) or len(x)!=len(b):
        raise SystemExit(f'paired comparison is incomplete: CIAS={len(a)} baseline={len(b)} merged={len(x)}')
    x['cias_condition']=cias_condition
    x['baseline_model']=args.baseline_model
    x['continuity_advantage']=x.identity_continuity_cias-x.identity_continuity_baseline
    x['lure_rejection_advantage']=x.lure_capture_baseline-x.lure_capture_cias
    Path(args.out).parent.mkdir(parents=True,exist_ok=True); x.to_csv(args.out,index=False)
    rows=[]
    for metric in ['continuity_advantage','lure_rejection_advantage']:
        seed=x.groupby('seed')[metric].mean().dropna().to_numpy()
        mean,lo,hi=bootstrap_mean_ci(seed)
        rows.append({'comparison':f'{cias_condition}-vs-{args.baseline_model}','metric':metric,'mean_advantage':mean,'ci_low':lo,'ci_high':hi,'n_seeds':len(seed),'seed_wins':int((seed>0).sum())})
    summary_path=Path(args.out).with_name(Path(args.out).stem+'_summary.csv')
    pd.DataFrame(rows).to_csv(summary_path,index=False)
    print(summary_path)

if __name__=='__main__': main()
