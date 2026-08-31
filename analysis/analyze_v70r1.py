#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, math
from pathlib import Path
import pandas as pd
from scipy import stats

FULL="progressive_persistent"
PRIMARY="progressive_no_persistent_self"
SECONDARY="progressive_history_reset"

def effect(df, control, metric, sign=1):
    p=df[df.condition.isin([FULL,control])].pivot_table(index=["seed","profile"],columns="condition",values=metric)
    d=sign*(p[FULL]-p[control])
    seed=d.groupby(level="seed").mean()
    mean=float(seed.mean()); sd=float(seed.std(ddof=1)); sem=sd/math.sqrt(len(seed))
    crit=float(stats.t.ppf(.975,len(seed)-1))
    body=d.groupby(level="profile").mean().to_dict()
    return {
        "metric":metric,"control":control,"effect":mean,
        "ci95_low":mean-crit*sem,"ci95_high":mean+crit*sem,
        "cohen_dz":mean/sd if sd>0 else None,
        "seed_win_rate":float((seed>0).mean()),
        "body_wins":int(sum(v>0 for v in body.values())),
        "body_effects":{str(k):float(v) for k,v in body.items()}
    }

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("heldout_csv")
    ap.add_argument("--outdir",default="analysis_v70r1")
    a=ap.parse_args()
    df=pd.read_csv(a.heldout_csv)
    out=Path(a.outdir); out.mkdir(parents=True,exist_ok=True)

    expected=30*4*3
    structure_ok=(
        len(df)==expected and df.seed.nunique()==30 and df.profile.nunique()==4 and
        set(df.condition.unique())=={FULL,PRIMARY,SECONDARY} and
        not df.duplicated(["seed","profile","condition"]).any() and
        (df.matched_change_point_events==4).all()
    )

    continuity=effect(df,PRIMARY,"identity_continuity_score_v2",+1)
    lure=effect(df,PRIMARY,"final_old_signature_clone_capture",-1)
    retention=effect(df,PRIMARY,"final_identity_retention",+1)
    posterior=effect(df,PRIMARY,"final_self_posterior_margin",+1)

    secondary_continuity=effect(df,SECONDARY,"identity_continuity_score_v2",+1)
    secondary_lure=effect(df,SECONDARY,"final_old_signature_clone_capture",-1)

    full=df[df.condition==FULL]
    full_mean=float(full.identity_continuity_score_v2.mean())
    floor=float((full.identity_continuity_score_v2<=1e-12).mean())
    ceiling=float((full.identity_continuity_score_v2>=1-1e-12).mean())
    nondegenerate=(0.35<=full_mean<=0.95 and floor<0.60 and ceiling<0.60)

    primary_pass=(
        structure_ok and nondegenerate and
        continuity["effect"]>=0.15 and continuity["ci95_low"]>0 and continuity["body_wins"]>=3 and
        lure["effect"]>=0.30 and lure["ci95_low"]>0 and lure["body_wins"]>=3
    )

    audit={
        "release_version":"7.0-r1",
        "frozen_benchmark_protocol":"7.0-p2",
        "structure_ok":bool(structure_ok),
        "nondegeneracy":{"full_mean":full_mean,"floor_fraction":floor,"ceiling_fraction":ceiling,"passed":bool(nondegenerate)},
        "primary":{
            "continuity":continuity,
            "old_appearance_lure_rejection":lure,
            "retention":retention,
            "posterior_margin":posterior,
        },
        "secondary_history_reset":{
            "continuity":secondary_continuity,
            "lure_rejection":secondary_lure,
        },
        "confirmatory_pass":bool(primary_pass),
        "claim_boundary":"A PASS supports the necessity of the persistent causal identity anchor for functional identity continuity under the frozen adversarial change-point task. It does not establish phenomenal identity, autobiographical history sufficiency, or developmental morphology-order benefit."
    }
    (out/"V7.0-R1_confirmatory_audit.json").write_text(json.dumps(audit,indent=2,ensure_ascii=False),encoding="utf-8")
    pd.DataFrame([continuity,lure,retention,posterior,secondary_continuity,secondary_lure]).to_csv(out/"V7.0-R1_effects.csv",index=False)
    print(json.dumps(audit,indent=2,ensure_ascii=False))

if __name__=="__main__":
    main()
