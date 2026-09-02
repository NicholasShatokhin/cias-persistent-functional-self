#!/usr/bin/env python3
from __future__ import annotations
from pathlib import Path
import argparse, json, math
import numpy as np
import pandas as pd
from scipy import stats

PROFILES = ["ground_creature","wheeled_robot","drone","virtual_avatar"]
DIAG = ["progressive_persistent","final_from_start","reverse_curriculum","random_curriculum","progressive_history_reset","progressive_no_persistent_self"]
CONF = ["progressive_persistent","progressive_no_persistent_self","progressive_history_reset"]


def ci_t(x):
    a=np.asarray(x,dtype=float); a=a[np.isfinite(a)]
    if len(a)<2: return (float('nan'),float('nan'))
    m=float(a.mean()); se=float(stats.sem(a)); q=float(stats.t.ppf(.975,len(a)-1))
    return m-q*se,m+q*se

def dz(x):
    a=np.asarray(x,dtype=float); a=a[np.isfinite(a)]
    if len(a)<2 or float(a.std(ddof=1))==0: return float('nan')
    return float(a.mean()/a.std(ddof=1))

def seed_paired(df, full, ctrl, metric, lower_better=False):
    sub=df[df.condition.isin([full,ctrl])]
    p=sub.pivot_table(index=['seed','profile'],columns='condition',values=metric,aggfunc='mean').dropna()
    if p.empty: return None
    raw=(p[full]-p[ctrl]) * (-1 if lower_better else 1)
    seed=raw.groupby(level='seed').mean(); lo,hi=ci_t(seed)
    by_profile=raw.groupby(level='profile').mean().to_dict()
    return {
        'full':full,'control':ctrl,'metric':metric,'effect_full_advantage':float(seed.mean()),
        'ci95_low':lo,'ci95_high':hi,'cohen_dz':dz(seed),
        'seed_win_rate':float((seed>0).mean()),'seed_tie_rate':float((seed==0).mean()),
        'body_wins':int(sum(v>0 for v in by_profile.values())),
        'profile_effects':{k:float(v) for k,v in by_profile.items()},'n_seeds':int(len(seed))
    }

def validate(df, expected, conditions):
    keys=['seed','profile','condition']
    return {
        'rows':int(len(df)), 'expected_runs':int(expected), 'row_count_ok':len(df)==expected,
        'duplicates':int(df.duplicated(keys).sum()), 'missing_values':int(df.isna().sum().sum()),
        'profiles':sorted(df.profile.unique().tolist()), 'conditions':sorted(df.condition.unique().tolist()),
        'structure_ok':len(df)==expected and df.duplicated(keys).sum()==0 and set(df.profile)==set(PROFILES) and set(df.condition)==set(conditions)
    }

def condition_means(df):
    numeric=[c for c in df.columns if c not in {'seed','profile','condition','protocol','scene_hash'}]
    return df.groupby('condition')[numeric].mean(numeric_only=True).reset_index()

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--csv',required=True); ap.add_argument('--stage',required=True,choices=['initial_diagnostic','matched_diagnostic','preflight','confirmatory']); ap.add_argument('--outdir',required=True)
    a=ap.parse_args(); p=Path(a.csv); out=Path(a.outdir); out.mkdir(parents=True,exist_ok=True); d=pd.read_csv(p)
    plan={'initial_diagnostic':(192,DIAG),'matched_diagnostic':(288,DIAG),'preflight':(48,CONF),'confirmatory':(360,CONF)}
    expected,conditions=plan[a.stage]; structure=validate(d,expected,conditions)
    means=condition_means(d); means.to_csv(out/f'{a.stage}_condition_means.csv',index=False)
    primary = d[d.condition.isin(['progressive_persistent','progressive_no_persistent_self','progressive_history_reset'])]
    hash_counts = primary.groupby(['seed','profile']).scene_hash.nunique() if 'scene_hash' in primary.columns else pd.Series(dtype=int)
    matched_scene_hash_ok = bool(len(hash_counts)>0 and int(hash_counts.max())==1)
    report={'stage':a.stage,'source':str(p),'structure':structure,'matched_primary_scene_hash_ok':matched_scene_hash_ok,'condition_means':means.to_dict(orient='records')}
    effects=[]
    if a.stage in {'initial_diagnostic','matched_diagnostic'}:
        metric='identity_continuity_score_legacy' if a.stage=='initial_diagnostic' else 'identity_continuity_score_v2'
        for ctrl in ['progressive_no_persistent_self','progressive_history_reset','final_from_start','reverse_curriculum','random_curriculum']:
            e=seed_paired(d,'progressive_persistent',ctrl,metric)
            if e: effects.append(e)
        e=seed_paired(d,'progressive_persistent','progressive_no_persistent_self','final_old_signature_clone_capture',lower_better=True)
        if e: effects.append(e)
        full=d[d.condition=='progressive_persistent'][metric]
        report['endpoint_nondegeneracy']={'metric':metric,'mean':float(full.mean()),'exact_floor_fraction':float((full<=1e-12).mean()),'exact_ceiling_fraction':float((full>=1-1e-12).mean())}
        if a.stage=='initial_diagnostic':
            report['diagnostic_interpretation']={'expected_role':'failure-mode discovery','ceiling_detected':bool((full>=1-1e-12).mean()>=0.50),'confirmatory_status':'EXPLORATORY_ONLY'}
        else:
            report['diagnostic_interpretation']={'expected_role':'repaired matched diagnosis and theory reduction','confirmatory_status':'EXPLORATORY_ONLY'}
    if a.stage=='preflight':
        full=d[d.condition=='progressive_persistent']['identity_continuity_score_v2']
        nondeg=bool(len(full)>0 and float((full<=1e-12).mean())<0.60 and float((full>=1-1e-12).mean())<0.60)
        report['preflight_gate']={'structure_ok':bool(structure['structure_ok']),'matched_primary_scene_hash_ok':matched_scene_hash_ok,'endpoint_nondegenerate':nondeg,'desired_effect_not_used_as_gate':True,'passed':bool(structure['structure_ok'] and matched_scene_hash_ok and nondeg)}
    if a.stage=='confirmatory':
        e1=seed_paired(d,'progressive_persistent','progressive_no_persistent_self','identity_continuity_score_v2')
        e2=seed_paired(d,'progressive_persistent','progressive_no_persistent_self','final_old_signature_clone_capture',lower_better=True)
        effects=[e1,e2]
        full=d[d.condition=='progressive_persistent']['identity_continuity_score_v2']
        nondeg=(0.35<=float(full.mean())<=0.95 and float((full<=1e-12).mean())<0.60 and float((full>=1-1e-12).mean())<0.60)
        gate={
            'continuity_effect_ge_0_15':bool(e1 and e1['effect_full_advantage']>=0.15),
            'continuity_ci_low_gt_0':bool(e1 and e1['ci95_low']>0),
            'continuity_profiles_ge_3':bool(e1 and e1['body_wins']>=3),
            'lure_rejection_effect_ge_0_30':bool(e2 and e2['effect_full_advantage']>=0.30),
            'lure_rejection_ci_low_gt_0':bool(e2 and e2['ci95_low']>0),
            'lure_rejection_profiles_ge_3':bool(e2 and e2['body_wins']>=3),
            'full_endpoint_nondegenerate':bool(nondeg),
            'matched_primary_scene_hash_ok':bool(matched_scene_hash_ok)
        }
        gate['passed']=all(gate.values()); report['confirmatory_gate']=gate
    report['effects']=[e for e in effects if e]
    pd.DataFrame([{k:(json.dumps(v,sort_keys=True) if isinstance(v,dict) else v) for k,v in e.items()} for e in report['effects']]).to_csv(out/f'{a.stage}_effects.csv',index=False)
    (out/f'{a.stage}_analysis.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(out/f'{a.stage}_analysis.json')
    if not structure['structure_ok']:
        raise SystemExit('STRUCTURE FAIL')
    if a.stage=='preflight' and not report['preflight_gate']['passed']:
        raise SystemExit('PREFLIGHT FAIL')

if __name__=='__main__': main()
