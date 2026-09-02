#!/usr/bin/env python3
"""Analytical margin check. This is NOT a replacement for behavioral reruns."""
import argparse, csv

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--out',default='anchor_margin.csv'); args=ap.parse_args()
    rows=[]
    for cost_scale in [0.5,0.75,1.0,1.25,1.5,2.0]:
      for gate in [0.60,0.65,0.70,0.75,0.80]:
       for thr in [0.70,0.74,0.78,0.82,0.86,0.90]:
        # Historical sufficient-condition upper bound: 0.015+0.06+0.04=0.115.
        pmax=0.115*cost_scale
        rows.append({'anchor_cost_scale':cost_scale,'observation_gate':gate,'postchange_threshold':thr,
                     'persistent_edge_upper_bound':pmax,'admissible_by_bound':int(pmax<thr),
                     'note':'analytical sufficient bound only; says nothing about cue separation frequency or full assignment dynamics'})
    with open(args.out,'w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=rows[0].keys()); w.writeheader(); w.writerows(rows)
    print(args.out)
if __name__=='__main__': main()
