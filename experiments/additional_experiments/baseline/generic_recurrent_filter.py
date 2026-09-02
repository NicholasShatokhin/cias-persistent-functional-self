from __future__ import annotations
from dataclasses import dataclass
import numpy as np
import pandas as pd

FEATURES = [
    "appearance_0","appearance_1","appearance_2","appearance_3",
    "efference","outcome","motor","proprio","temporal","crossmodal","persistence","physical",
    "autonomy","goal","response","tool","intero","homeo","history"
]
FORBIDDEN = {"is_true_lineage","is_lure","truth_entity_id","ground_truth_role"}

@dataclass
class GaussianEmission:
    pos_mean: np.ndarray; pos_var: np.ndarray; neg_mean: np.ndarray; neg_var: np.ndarray
    def log_lr(self,x:np.ndarray)->float:
        def ll(v,m,var): return float(-0.5*np.sum(np.log(2*np.pi*var)+(v-m)**2/var))
        return ll(x,self.pos_mean,self.pos_var)-ll(x,self.neg_mean,self.neg_var)

class GenericRecurrentFilter:
    """Supervised-on-diagnostic generic recurrent state estimator.

    It is deliberately strong: diagnostic labels may fit its emission model. At test
    time it receives only whitelisted observations and has no explicit Self role,
    no persistent lineage key, and no change-point-specific reconnect rule.
    """
    def __init__(self,position_scale=190.0,motion_weight=0.55,appearance_continuity_weight=0.25,
                 emission_weight=1.0,state_update_alpha=0.20,variance_floor=0.01):
        self.position_scale=float(position_scale); self.motion_weight=float(motion_weight)
        self.appearance_continuity_weight=float(appearance_continuity_weight); self.emission_weight=float(emission_weight)
        self.alpha=float(state_update_alpha); self.variance_floor=float(variance_floor); self.emission=None
    def fit(self,diagnostic:pd.DataFrame):
        missing=[c for c in FEATURES+["is_true_lineage"] if c not in diagnostic.columns]
        if missing: raise ValueError(f"missing diagnostic columns: {missing}")
        x=diagnostic[FEATURES].astype(float).to_numpy(); y=diagnostic.is_true_lineage.astype(int).to_numpy()
        if not ((y==1).any() and (y==0).any()): raise ValueError("diagnostic needs positive and negative observations")
        xp=x[y==1]; xn=x[y==0]
        self.emission=GaussianEmission(xp.mean(0),np.maximum(xp.var(0,ddof=1),self.variance_floor),xn.mean(0),np.maximum(xn.var(0,ddof=1),self.variance_floor)); return self
    def _visible(self,row): return row[FEATURES].astype(float).to_numpy()
    def predict_run(self,run:pd.DataFrame)->pd.DataFrame:
        if self.emission is None: raise RuntimeError("fit() first")
        req=["frame","time_s","observation_id","x","y"]+FEATURES
        missing=[c for c in req if c not in run.columns]
        if missing: raise ValueError(f"missing test columns: {missing}")
        out=[]; pos=None; vel=np.zeros(2); prev_app=None; prev_t=None; cue_state=None
        for frame,g in run.sort_values(["frame","observation_id"]).groupby("frame",sort=True):
            t=float(g.time_s.iloc[0]); scores=[]
            for idx,row in g.iterrows():
                feat=self._visible(row); score=self.emission_weight*self.emission.log_lr(feat); xy=np.array([float(row.x),float(row.y)])
                app=np.array([float(row[f"appearance_{i}"]) for i in range(4)])
                if pos is not None:
                    dt=max(1e-6,t-prev_t); pred=pos+vel*dt; resid=np.linalg.norm(xy-pred)/max(self.position_scale,1e-9)
                    score += -self.motion_weight*resid*resid
                    if prev_app is not None: score += -self.appearance_continuity_weight*float(np.mean((app-prev_app)**2))
                    if cue_state is not None: score += -0.05*float(np.mean((feat-cue_state)**2))
                scores.append((score,idx,xy,feat,app))
            scores.sort(key=lambda z:z[0],reverse=True); best=scores[0]; row=g.loc[best[1]]; newpos=best[2]
            if pos is not None:
                dt=max(1e-6,t-prev_t); inst=(newpos-pos)/dt; vel=(1-self.alpha)*vel+self.alpha*inst; pos=(1-self.alpha)*pos+self.alpha*newpos
                cue_state=(1-self.alpha)*cue_state+self.alpha*best[3]; prev_app=(1-self.alpha)*prev_app+self.alpha*best[4]
            else: pos=newpos; cue_state=best[3].copy(); prev_app=best[4].copy()
            prev_t=t; raw=np.array([z[0] for z in scores]); raw-=raw.max(); ex=np.exp(np.clip(raw,-60,0)); prob=ex/ex.sum()
            out.append({"frame":int(frame),"time_s":t,"selected_observation_id":str(row.observation_id),"selected_index":best[1],"confidence":float(prob[0])})
        return pd.DataFrame(out)

def appearance_only(run:pd.DataFrame)->pd.DataFrame:
    out=[]
    # Generic appearance continuity: initialize with the first selected appearance,
    # thereafter choose the candidate closest to the previous appearance vector.
    prev=None
    for frame,g in run.sort_values(["frame","observation_id"]).groupby("frame",sort=True):
        if prev is None:
            # pre-change Self-like motor evidence only for initialization; this is a sanity baseline.
            idx=g.motor.astype(float).idxmax()
        else:
            dist=g[[f"appearance_{i}" for i in range(4)]].astype(float).apply(lambda r:float(np.mean((r.to_numpy()-prev)**2)),axis=1)
            idx=dist.idxmin()
        row=g.loc[idx]; prev=row[[f"appearance_{i}" for i in range(4)]].astype(float).to_numpy()
        out.append({"frame":int(frame),"time_s":float(row.time_s),"selected_observation_id":str(row.observation_id),"selected_index":idx,"confidence":1.0})
    return pd.DataFrame(out)


def _diagnostic_score(stream: pd.DataFrame, pred: pd.DataFrame, probe_start: int = 168) -> float:
    selected = stream.loc[pred.selected_index.to_numpy()].copy()
    selected = selected.assign(frame=pred.frame.to_numpy())
    probe = selected[selected.frame >= probe_start]
    if probe.empty:
        return -1e9
    continuity = float(probe.is_true_lineage.astype(int).mean())
    lure_capture = float(probe.is_lure.astype(int).mean())
    # Equal emphasis on keeping the lineage and rejecting the lure.
    return 0.5 * continuity + 0.5 * (1.0 - lure_capture)


def tune_hyperparameters(diagnostic: pd.DataFrame, probe_start: int = 168):
    """Grouped seed CV using diagnostic data only.

    Emission statistics and recurrent hyperparameters are selected without touching
    preflight or held-out rows.  The grid is intentionally small and prespecified.
    """
    if "seed" not in diagnostic.columns or "run_id" not in diagnostic.columns:
        raise ValueError("diagnostic tuning requires seed and run_id")
    grid=[]
    for motion in (0.20, 0.55, 1.00):
        for appearance in (0.00, 0.25, 0.60):
            for alpha in (0.10, 0.20, 0.40):
                grid.append({"motion_weight":motion,"appearance_continuity_weight":appearance,"state_update_alpha":alpha})
    seeds=sorted(int(x) for x in diagnostic.seed.unique())
    if len(seeds) < 2:
        # Unit fixtures may contain only one effective group; retain central settings.
        return grid[13], pd.DataFrame([grid[13] | {"cv_score": float("nan"), "n_folds": 0}])
    rows=[]
    for cfg in grid:
        fold_scores=[]
        for held in seeds:
            train=diagnostic[diagnostic.seed.astype(int)!=held]
            valid=diagnostic[diagnostic.seed.astype(int)==held]
            if train.empty or valid.empty: continue
            model=GenericRecurrentFilter(**cfg).fit(train)
            scores=[]
            for _,g in valid.groupby("run_id",sort=True):
                scores.append(_diagnostic_score(g,model.predict_run(g),probe_start))
            if scores: fold_scores.append(float(np.mean(scores)))
        rows.append(cfg | {"cv_score":float(np.mean(fold_scores)) if fold_scores else -1e9,"n_folds":len(fold_scores)})
    tab=pd.DataFrame(rows).sort_values(
        ["cv_score","motion_weight","appearance_continuity_weight","state_update_alpha"],
        ascending=[False,True,True,True]
    ).reset_index(drop=True)
    best={k:float(tab.iloc[0][k]) for k in ["motion_weight","appearance_continuity_weight","state_update_alpha"]}
    return best,tab
