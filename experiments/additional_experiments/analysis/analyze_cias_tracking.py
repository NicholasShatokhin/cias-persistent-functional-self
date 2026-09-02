#!/usr/bin/env python3
from pathlib import Path
import argparse, numpy as np, pandas as pd

def metrics(g,probe_start=168,k=5):
    g=g.sort_values('frame'); p=g[g.frame>=probe_start]
    correct=(p.true_self_entity_id.astype(int)==p.lineage_id.astype(int)).astype(int)
    lure=((p.lure_present.astype(int)==1)&(p.lure_entity_id.astype(int)==p.lineage_id.astype(int))).astype(int)
    rec=np.nan; arr=correct.to_numpy(); frames=p.frame.to_numpy()
    for i in range(max(0,len(arr)-k+1)):
        if arr[i:i+k].sum()==k: rec=(frames[i]-probe_start)*0.1; break
    self_ids=g.true_self_entity_id.astype(int).to_numpy(); switches=int((self_ids[1:]!=self_ids[:-1]).sum()) if len(self_ids)>1 else 0
    return {'identity_continuity':float(correct.mean()),'lure_capture':float(lure.mean()),'recovery_latency_s':rec,'selection_switches':switches,'final_lineage_retention':int(correct.iloc[-1]) if len(correct) else 0}
def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--tracking',required=True); ap.add_argument('--out',required=True); a=ap.parse_args(); d=pd.read_csv(a.tracking)
    keys=['parameter_id','condition','run_id','seed','profile','scenario']; rows=[]
    for key,g in d.groupby(keys,sort=True): rows.append(dict(zip(keys,key))|metrics(g))
    out=Path(a.out); out.parent.mkdir(parents=True,exist_ok=True); pd.DataFrame(rows).to_csv(out,index=False); print(out)
if __name__=='__main__':main()
