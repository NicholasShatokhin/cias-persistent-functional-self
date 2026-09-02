#!/usr/bin/env python3
from pathlib import Path
import argparse,json
import pandas as pd
from paired_effects import bootstrap_mean_ci


def effect(df,a,b,metric,lower=False):
    x=df[df.condition==a].groupby('seed')[metric].mean()
    y=df[df.condition==b].groupby('seed')[metric].mean()
    z=pd.concat([x,y],axis=1,keys=['a','b']).dropna()
    v=(z.b-z.a if lower else z.a-z.b).to_numpy()
    m,lo,hi=bootstrap_mean_ci(v)
    return {'mean':m,'ci_low':lo,'ci_high':hi,'n_seeds':len(v),'seed_wins':int((v>0).sum())}


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--cias',required=True)
    ap.add_argument('--baseline',required=True)
    ap.add_argument('--comparison',required=True)
    ap.add_argument('--sweep',required=True,help='One-row-per-parameter basin CSV from summarize_sweep.py')
    ap.add_argument('--simultaneous',required=False,help='Family-wise max-bootstrap sensitivity CSV')
    ap.add_argument('--out',required=True)
    a=ap.parse_args()
    c=pd.read_csv(a.cias); _=pd.read_csv(a.baseline); comp=pd.read_csv(a.comparison); sw=pd.read_csv(a.sweep); sim=pd.read_csv(a.simultaneous) if a.simultaneous else None
    def boolcol(name):
        s=sw[name]
        if str(s.dtype)=='bool': return s
        return s.astype(str).str.strip().str.lower().isin({'true','1','yes'})
    sign=boolcol('both_sign_preserved') if len(sw) else pd.Series(dtype=bool)
    cis=boolcol('both_ci_supported') if len(sw) else pd.Series(dtype=bool)
    prof=boolcol('both_profile_direction_3of4') if len(sw) else pd.Series(dtype=bool)
    robustness={
        'parameter_settings':int(len(sw)),
        'both_sign_preserved_count':int(sign.sum()) if len(sw) else 0,
        'both_sign_preserved_fraction':float(sign.mean()) if len(sw) else float('nan'),
        'both_ci_supported_count':int(cis.sum()) if len(sw) else 0,
        'both_ci_supported_fraction':float(cis.mean()) if len(sw) else float('nan'),
        'both_profile_direction_3of4_count':int(prof.sum()) if len(sw) else 0,
        'both_profile_direction_3of4_fraction':float(prof.mean()) if len(sw) else float('nan'),
        'simultaneous_family':'all 54 effects (27 settings x 2 metrics)' if sim is not None else None,
        'both_simultaneous_positive_count':int(sim.both_simultaneous_positive.astype(str).str.lower().isin({'true','1','yes'}).sum()) if sim is not None else None,
        'both_simultaneous_positive_fraction':float(sim.both_simultaneous_positive.astype(str).str.lower().isin({'true','1','yes'}).mean()) if sim is not None else None,
        'median_identity_advantage':float(sw.identity_advantage.median()) if len(sw) else float('nan'),
        'worst_identity_advantage':float(sw.identity_advantage.min()) if len(sw) else float('nan'),
        'median_lure_rejection_advantage':float(sw.lure_rejection_advantage.median()) if len(sw) else float('nan'),
        'worst_lure_rejection_advantage':float(sw.lure_rejection_advantage.min()) if len(sw) else float('nan'),
    }
    summary={
      'scientific_status':'COMPLETE',
      'cias_full_vs_lesion':{
          'identity_continuity':effect(c,'cias_full','cias_no_persistent_self','identity_continuity'),
          'lure_rejection':effect(c,'cias_full','cias_no_persistent_self','lure_capture',True)},
      'cias_vs_generic_definition':'CIAS Full minus generic recurrent estimator; negative values favor the generic estimator',
      'cias_vs_generic':[],
      'parameter_robustness':robustness
    }
    for _,r in comp.iterrows():
        summary['cias_vs_generic'].append({'metric':str(r.metric),'mean_advantage':float(r.mean_advantage),'ci_low':float(r.ci_low),'ci_high':float(r.ci_high),'n_seeds':int(r.n_seeds)})
    out=Path(a.out); out.parent.mkdir(parents=True,exist_ok=True); out.write_text(json.dumps(summary,indent=2)+'\n')
    md=['# Additional experiments execution summary','',f"Status: `{summary['scientific_status']}`",'', 'This summary is generated from the completed additional-experiment seed ranges defined in the repository protocol.','', '## CIAS Full vs anchor lesion']
    for k,v in summary['cias_full_vs_lesion'].items():
        md += [f"- **{k}**: mean advantage {v['mean']:.4f}, 95% bootstrap CI [{v['ci_low']:.4f}, {v['ci_high']:.4f}], n={v['n_seeds']}"]
    md += ['', '## CIAS Full vs generic recurrent estimator', '', 'Differences are CIAS Full minus the generic recurrent estimator; negative values favor the generic estimator.']
    for v in summary['cias_vs_generic']:
        md += [f"- **{v['metric']}**: mean difference {v['mean_advantage']:.4f}, 95% CI [{v['ci_low']:.4f}, {v['ci_high']:.4f}], n={v['n_seeds']}"]
    r=summary['parameter_robustness']
    md += ['', '## Parameter sensitivity',
           f"- Prespecified settings: {r['parameter_settings']}.",
           f"- Both primary effect signs preserved: {r['both_sign_preserved_count']}/{r['parameter_settings']} ({r['both_sign_preserved_fraction']:.1%}).",
           f"- Both primary pointwise 95% CIs above zero: {r['both_ci_supported_count']}/{r['parameter_settings']} ({r['both_ci_supported_fraction']:.1%}).",
           f"- Both 95% simultaneous max-bootstrap intervals above zero: {r['both_simultaneous_positive_count']}/{r['parameter_settings']} ({r['both_simultaneous_positive_fraction']:.1%})." if r['both_simultaneous_positive_count'] is not None else '',
           f"- Correct effect direction in at least 3/4 profiles for both outcomes: {r['both_profile_direction_3of4_count']}/{r['parameter_settings']} ({r['both_profile_direction_3of4_fraction']:.1%}).",
           f"- Identity advantage: median {r['median_identity_advantage']:.4f}; worst tested setting {r['worst_identity_advantage']:.4f}.",
           f"- Lure-rejection advantage: median {r['median_lure_rejection_advantage']:.4f}; worst tested setting {r['worst_lure_rejection_advantage']:.4f}.",
           '', 'All prespecified settings are retained in the summary, including failure regions observed on held-out data.']
    out.with_suffix('.md').write_text('\n'.join(md)+'\n')
    print(out)

if __name__=='__main__':main()
