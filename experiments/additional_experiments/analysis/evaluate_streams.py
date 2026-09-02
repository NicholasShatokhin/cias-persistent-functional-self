#!/usr/bin/env python3
from pathlib import Path
import argparse, json, sys
import numpy as np, pandas as pd
HERE=Path(__file__).resolve().parent; BASE=HERE.parent/'baseline'; sys.path.insert(0,str(BASE))
from generic_recurrent_filter import GenericRecurrentFilter, GaussianEmission, appearance_only, FEATURES, tune_hyperparameters

def bootstrap_ci(values,seed=20260901,n=10000):
    a=np.asarray(values,dtype=float)
    if len(a)==0:return(float('nan'),float('nan'))
    rng=np.random.default_rng(seed); means=np.array([rng.choice(a,size=len(a),replace=True).mean() for _ in range(n)])
    return tuple(np.quantile(means,[.025,.975]))
def evaluate_one(stream,pred,probe_start=168,recovery_k=5):
    truth=stream.loc[pred.selected_index.values].copy(); truth=truth.assign(frame=pred.frame.values,time_s=pred.time_s.values)
    probe=truth[truth.frame>=probe_start]; continuity=float(probe.is_true_lineage.mean()) if len(probe) else float('nan'); lure=float(probe.is_lure.mean()) if len(probe) else float('nan')
    seq=probe.sort_values('frame').is_true_lineage.astype(int).to_numpy(); frames=probe.sort_values('frame').frame.to_numpy(); rec=float('nan')
    for i in range(max(0,len(seq)-recovery_k+1)):
        if seq[i:i+recovery_k].sum()==recovery_k: rec=float((frames[i]-probe_start)*0.1); break
    selected=truth.sort_values('frame').observation_id.astype(str).values; switches=int((selected[1:]!=selected[:-1]).sum()) if len(selected)>1 else 0
    return {'identity_continuity':continuity,'lure_capture':lure,'recovery_latency_s':rec,'selection_switches':switches}
def group_runs(df):
    keys=[c for c in ['run_id','seed','profile','scenario'] if c in df.columns]; return keys,df.groupby(keys,sort=True)
def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--diagnostic',required=True); ap.add_argument('--test',required=True); ap.add_argument('--out',required=True); ap.add_argument('--probe-start',type=int,default=168); ap.add_argument('--frozen-fit',default=None,help='Reuse a previously frozen diagnostic-only model_fit.json without retuning.'); a=ap.parse_args()
    out=Path(a.out); out.mkdir(parents=True,exist_ok=True); diag=pd.read_csv(a.diagnostic); test=pd.read_csv(a.test)
    if a.frozen_fit:
        fit=json.loads(Path(a.frozen_fit).read_text())
        best={k:float(fit['selected_hyperparameters'][k]) for k in ['motion_weight','appearance_continuity_weight','state_update_alpha']}
        model=GenericRecurrentFilter(**best)
        model.emission=GaussianEmission(
            np.asarray(fit['positive_mean'],dtype=float),np.asarray(fit['positive_var'],dtype=float),
            np.asarray(fit['negative_mean'],dtype=float),np.asarray(fit['negative_var'],dtype=float))
        cv=pd.DataFrame([best | {'cv_score':float('nan'),'n_folds':0,'status':'FROZEN_FIT_REUSED'}])
        fit_source=str(Path(a.frozen_fit).resolve())
    else:
        best,cv=tune_hyperparameters(diag,a.probe_start); model=GenericRecurrentFilter(**best).fit(diag); fit_source=None
    cv.to_csv(out/'diagnostic_hyperparameter_cv.csv',index=False)
    rows=[]; keys,groups=group_runs(test)
    for key,g in groups:
        meta=dict(zip(keys,key if isinstance(key,tuple) else (key,)))
        for name,pred in [('generic_recurrent_filter',model.predict_run(g)),('appearance_continuity_sanity',appearance_only(g))]: rows.append(meta|{'model':name}|evaluate_one(g,pred,a.probe_start))
    m=pd.DataFrame(rows); m.to_csv(out/'run_metrics.csv',index=False); agg=m.groupby(['model','seed'])[['identity_continuity','lure_capture']].mean().reset_index(); summary=[]
    for name,g in agg.groupby('model'):
        for metric in ['identity_continuity','lure_capture']:
            vals=g[metric].dropna().to_numpy(); lo,hi=bootstrap_ci(vals); summary.append({'model':name,'metric':metric,'mean':float(vals.mean()),'ci_low':lo,'ci_high':hi,'n_seeds':len(vals)})
    pd.DataFrame(summary).to_csv(out/'summary.csv',index=False)
    (out/'model_fit.json').write_text(json.dumps({'features':FEATURES,'selected_hyperparameters':best,'selection_boundary':'Grouped leave-one-seed-out cross-validation on diagnostic seeds only.','positive_mean':model.emission.pos_mean.tolist(),'positive_var':model.emission.pos_var.tolist(),'negative_mean':model.emission.neg_mean.tolist(),'negative_var':model.emission.neg_var.tolist(),'diagnostic_path':str(Path(a.diagnostic).resolve()),'test_path':str(Path(a.test).resolve()),'frozen_fit_source':fit_source,'boundary':'Truth labels fit diagnostic emissions and evaluate outputs; test prediction strictly whitelists model-visible fields. Preflight/held-out never retune the frozen diagnostic model.'},indent=2)+'\n')
    print(out/'summary.csv')
if __name__=='__main__':main()
