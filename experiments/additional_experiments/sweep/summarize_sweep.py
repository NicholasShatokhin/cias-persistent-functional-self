#!/usr/bin/env python3
from pathlib import Path
import argparse, json
import numpy as np
import pandas as pd
from sys import path
path.insert(0,str(Path(__file__).resolve().parents[1]/'analysis'))
from paired_effects import bootstrap_mean_ci


def paired_values(g: pd.DataFrame, metric: str, lower: bool=False):
    x=g[g.condition=='cias_full'].groupby('seed')[metric].mean()
    y=g[g.condition=='cias_no_persistent_self'].groupby('seed')[metric].mean()
    z=pd.concat([x,y],axis=1,keys=['full','lesion']).dropna()
    v=(z.lesion-z.full if lower else z.full-z.lesion).to_numpy(dtype=float)
    return z,v


def profile_positive_count(g: pd.DataFrame, metric: str, lower: bool=False) -> int:
    wins=0
    for _,p in g.groupby('profile',sort=True):
        f=p[p.condition=='cias_full'][metric].astype(float).mean()
        l=p[p.condition=='cias_no_persistent_self'][metric].astype(float).mean()
        effect=(l-f) if lower else (f-l)
        wins += int(np.isfinite(effect) and effect>0)
    return wins


def load_grid(path_value):
    if not path_value:
        return {}
    rows=[json.loads(x) for x in Path(path_value).read_text().splitlines() if x.strip()]
    return {str(r['parameter_id']):r for r in rows}


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--csv',required=True)
    ap.add_argument('--out',required=True)
    ap.add_argument('--grid',default=None,help='Optional parameter_grid.jsonl; adds labels/parameter values to basin table.')
    a=ap.parse_args()
    d=pd.read_csv(a.csv)
    grid=load_grid(a.grid)
    metric_rows=[]
    basin_rows=[]
    for pid,g in d.groupby('parameter_id',sort=True):
        effects={}
        for metric,lower,out_name in [
            ('identity_continuity',False,'identity_continuity_advantage'),
            ('lure_capture',True,'lure_rejection_advantage')]:
            _,v=paired_values(g,metric,lower)
            m,lo,hi=bootstrap_mean_ci(v)
            pc=profile_positive_count(g,metric,lower)
            effects[out_name]={'mean':m,'lo':lo,'hi':hi,'n':len(v),'wins':int((v>0).sum()),'profiles':pc}
            metric_rows.append({
                'parameter_id':pid,'metric':out_name,'mean_advantage':m,'ci_low':lo,'ci_high':hi,
                'n_seeds':len(v),'seed_wins':int((v>0).sum()),'profile_positive_count':pc,
                'qualitative_positive':bool(m>0),'ci_supported':bool(lo>0)
            })
        i=effects['identity_continuity_advantage']; l=effects['lure_rejection_advantage']
        cfg=grid.get(str(pid),{})
        row={
            'parameter_id':pid,
            'label':cfg.get('label',''),
            'identity_advantage':i['mean'],'identity_ci_low':i['lo'],'identity_ci_high':i['hi'],
            'identity_seed_wins':i['wins'],'identity_profile_positive_count':i['profiles'],
            'lure_rejection_advantage':l['mean'],'lure_ci_low':l['lo'],'lure_ci_high':l['hi'],
            'lure_seed_wins':l['wins'],'lure_profile_positive_count':l['profiles'],
            'both_sign_preserved':bool(i['mean']>0 and l['mean']>0),
            'both_ci_supported':bool(i['lo']>0 and l['lo']>0),
            'both_profile_direction_3of4':bool(i['profiles']>=3 and l['profiles']>=3),
        }
        for key in ['ordinary_threshold','postchange_threshold','new_entity_anchor_gate','persistent_reconnect_gate','smoothing_scale','anchor_cost_scale','nonpersistent_penalty_scale']:
            row[key]=cfg.get(key,np.nan)
        basin_rows.append(row)
    out=Path(a.out); out.parent.mkdir(parents=True,exist_ok=True)
    metric_df=pd.DataFrame(metric_rows)
    basin_df=pd.DataFrame(basin_rows)
    metric_df.to_csv(out,index=False)
    basin_path=out.with_name(out.stem+'_basin.csv')
    basin_df.to_csv(basin_path,index=False)
    if len(basin_df):
        overview={
            'parameter_settings':int(len(basin_df)),
            'both_sign_preserved_count':int(basin_df.both_sign_preserved.sum()),
            'both_sign_preserved_fraction':float(basin_df.both_sign_preserved.mean()),
            'both_ci_supported_count':int(basin_df.both_ci_supported.sum()),
            'both_ci_supported_fraction':float(basin_df.both_ci_supported.mean()),
            'both_profile_direction_3of4_count':int(basin_df.both_profile_direction_3of4.sum()),
            'both_profile_direction_3of4_fraction':float(basin_df.both_profile_direction_3of4.mean()),
            'worst_identity_advantage':float(basin_df.identity_advantage.min()),
            'worst_lure_rejection_advantage':float(basin_df.lure_rejection_advantage.min()),
            'median_identity_advantage':float(basin_df.identity_advantage.median()),
            'median_lure_rejection_advantage':float(basin_df.lure_rejection_advantage.median()),
        }
    else:
        overview={'parameter_settings':0}
    overview_path=out.with_name(out.stem+'_overview.json')
    overview_path.write_text(json.dumps(overview,indent=2)+'\n',encoding='utf-8')
    print(out)
    print(basin_path)
    print(overview_path)

if __name__=='__main__': main()
