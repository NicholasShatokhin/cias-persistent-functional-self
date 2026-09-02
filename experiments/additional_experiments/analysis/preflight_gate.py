#!/usr/bin/env python3
from pathlib import Path
import argparse,json,numpy as np,pandas as pd
PROFILES={'ground_creature','wheeled_robot','drone','virtual_avatar'}
CONDS={'cias_full','cias_no_persistent_self'}
CUES=['appearance','appearance_0','appearance_1','appearance_2','appearance_3','efference','outcome','motor','proprio','temporal','crossmodal','persistence','physical','autonomy','goal','response','tool','intero','homeo','history']

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--stream',required=True); ap.add_argument('--tracking',required=True); ap.add_argument('--baseline-metrics',default=None); ap.add_argument('--baseline-fit',default=None); ap.add_argument('--out',required=True); a=ap.parse_args()
    s=pd.read_csv(a.stream); t=pd.read_csv(a.tracking); reasons=[]
    if set(map(int,s.seed.unique()))!=set(range(327,331)): reasons.append('expected exactly preflight seeds 327-330')
    if set(s.profile.astype(str).unique())!=PROFILES: reasons.append('profile coverage mismatch')
    if s.run_id.nunique()!=16: reasons.append('expected 16 seed-profile scenes')
    if any(c not in s.columns for c in CUES): reasons.append('required model-visible cue missing')
    elif not np.isfinite(s[CUES].astype(float).to_numpy()).all(): reasons.append('NaN/Inf in model-visible cues')
    if 'scene_hash' not in s.columns or (s.groupby('run_id').scene_hash.nunique()!=1).any(): reasons.append('stream scene_hash not unique per run')
    if set(t.condition.astype(str).unique())!=CONDS: reasons.append('CIAS condition coverage mismatch')
    if t.duplicated(['condition','run_id','frame']).any(): reasons.append('duplicate tracking condition/run/frame rows')
    if not t.empty and t.groupby(['condition','run_id']).frame.nunique().min()!=240: reasons.append('tracking frame coverage incomplete')
    if 'scene_hash' in t.columns:
        hashes=t.groupby(['run_id','condition']).scene_hash.first().unstack('condition')
        if not CONDS.issubset(set(hashes.columns)) or (hashes['cias_full']!=hashes['cias_no_persistent_self']).any(): reasons.append('paired CIAS scene_hash mismatch')
        stream_hash=s.groupby('run_id').scene_hash.first()
        for run,row in hashes.iterrows():
            if run not in stream_hash.index or str(row['cias_full'])!=str(stream_hash.loc[run]): reasons.append(f'tracking/stream scene_hash mismatch: {run}'); break
    if not ((s.frame.astype(int)>=168)&(s.is_lure.astype(int)==1)).any(): reasons.append('final lure absent')
    post_lineage=t[t.frame.astype(int)>=167]
    if post_lineage.empty or (post_lineage.lineage_id.astype(int)<0).any(): reasons.append('lineage key missing after pre-probe lineage establishment (frame 167)')

    # The strong alternative estimator must execute successfully on preflight before
    # held-out seeds can be opened.  This check is deliberately technical only:
    # no effect direction, effect size, or performance threshold is inspected.
    if a.baseline_metrics:
        try:
            b=pd.read_csv(a.baseline_metrics)
            g=b[b.model.astype(str)=='generic_recurrent_filter'].copy() if 'model' in b.columns else pd.DataFrame()
            if len(g)!=16: reasons.append('generic comparator preflight coverage mismatch (expected 16 run rows)')
            elif set(map(int,g.seed.unique()))!=set(range(327,331)): reasons.append('generic comparator seed coverage mismatch')
            elif set(g.profile.astype(str).unique())!=PROFILES: reasons.append('generic comparator profile coverage mismatch')
            elif g.duplicated(['seed','profile','scenario']).any(): reasons.append('duplicate generic comparator preflight run rows')
            elif not np.isfinite(g[['identity_continuity','lure_capture']].astype(float).to_numpy()).all(): reasons.append('NaN/Inf in generic comparator primary preflight metrics')
        except Exception as exc:
            reasons.append('cannot validate generic comparator preflight metrics: %s' % exc)
    if a.baseline_fit:
        try:
            fit=json.loads(Path(a.baseline_fit).read_text())
            if 'diagnostic seeds only' not in str(fit.get('selection_boundary','')).lower(): reasons.append('generic comparator fit boundary is not diagnostic-only')
            vals=[]
            for k in ['positive_mean','positive_var','negative_mean','negative_var']: vals.extend(list(map(float,fit.get(k,[]))))
            if not vals or not np.isfinite(np.asarray(vals,dtype=float)).all(): reasons.append('generic comparator frozen fit is incomplete/nonfinite')
        except Exception as exc:
            reasons.append('cannot validate generic comparator frozen fit: %s' % exc)
    # Readiness gate intentionally does not inspect Full-vs-lesion or CIAS-vs-baseline effect direction/magnitude.
    status='PASS' if not reasons else 'FAIL'; obj={'status':status,'mission':'pipeline/readiness gate only; no desired-effect conditioning','reasons':reasons,'seeds':sorted(map(int,s.seed.unique())),'runs':int(s.run_id.nunique()),'tracking_rows':int(len(t))}
    Path(a.out).parent.mkdir(parents=True,exist_ok=True); Path(a.out).write_text(json.dumps(obj,indent=2)+'\n'); print('PREFLIGHT_'+status)
    raise SystemExit(0 if status=='PASS' else 2)
if __name__=='__main__':main()
