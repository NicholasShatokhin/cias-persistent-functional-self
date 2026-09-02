from __future__ import annotations
import numpy as np, pandas as pd

def seed_paired_effect(df: pd.DataFrame, a: str, b: str, metric: str, model_col='condition'):
    x=df[df[model_col]==a].groupby('seed')[metric].mean()
    y=df[df[model_col]==b].groupby('seed')[metric].mean()
    z=pd.concat([x.rename('a'),y.rename('b')],axis=1).dropna()
    z['diff']=z.a-z.b
    return z

def bootstrap_mean_ci(v, n=10000, seed=91721):
    v=np.asarray(v,dtype=float); rng=np.random.default_rng(seed)
    sims=np.array([rng.choice(v,len(v),replace=True).mean() for _ in range(n)])
    return float(v.mean()), float(np.quantile(sims,.025)), float(np.quantile(sims,.975))
