#!/usr/bin/env python3
from __future__ import annotations
from pathlib import Path
import argparse, subprocess, sys, json, shutil, hashlib, time, os, gzip

PROFILES=['ground_creature','wheeled_robot','drone','virtual_avatar']
DIAG_COND=['progressive_persistent','final_from_start','reverse_curriculum','random_curriculum','progressive_history_reset','progressive_no_persistent_self']
CONF_COND=['progressive_persistent','progressive_no_persistent_self','progressive_history_reset']

def log(msg=''): print(msg,flush=True)
def run(cmd,cwd=None):
    log('> '+' '.join(map(str,cmd)))
    p=subprocess.run(list(map(str,cmd)),cwd=cwd)
    if p.returncode: raise SystemExit(p.returncode)
def capture(cmd): return subprocess.check_output(list(map(str,cmd)),text=True,stderr=subprocess.STDOUT).strip()
def rangei(a,b): return list(range(a,b+1))
def write_json(p,obj): p.parent.mkdir(parents=True,exist_ok=True); p.write_text(json.dumps(obj,indent=2)+'\n',encoding='utf-8')
def read_json(p): return json.loads(p.read_text(encoding='utf-8'))
def hashfile(p): return hashlib.sha256(p.read_bytes()).hexdigest()

def clean_ephemeral_staging(repo:Path):
    # Runtime copies and request files are execution staging, not evidence.
    # Remove leftovers from an interrupted smoke before static QA/manifesting.
    for project in [repo/'experiments/paper_experiments/godot', repo/'experiments/additional_experiments/godot']:
        runtime=project/'runtime'
        if runtime.exists():
            for q in runtime.glob('*.gd'):
                q.unlink()
        work=project/'work'
        if work.exists():
            for q in work.glob('*.json'):
                q.unlink()
    transient=repo/'experiments/additional_experiments/work'
    if transient.exists():
        shutil.rmtree(transient)

def godot_req(project:Path,obj:dict,script:str):
    q=project/'work/run_request.json'; q.parent.mkdir(parents=True,exist_ok=True); write_json(q,obj); return q,script

def godot_run(godot:str,project:Path,script:str):
    run([godot,'--headless','--path',project,'--script',script,'--','--request=res://work/run_request.json'])

def assert_clean_results(repo:Path,resume:bool):
    markers=list(repo.glob('provenance/**/HELDOUT_ACCESS.json'))
    generated=[]
    for base in [repo/'experiments/paper_experiments/results',repo/'experiments/additional_experiments/results']:
        if base.exists(): generated += [p for p in base.rglob('*') if p.is_file() and p.name not in {'.gitkeep','README.md'}]
    if (markers or generated) and not resume:
        msg=['This checkout already contains execution evidence. Refusing to present a repeat as a fresh run.']
        msg += [f' marker: {p}' for p in markers]
        msg += [f' result: {p}' for p in generated[:10]]
        raise SystemExit('\n'.join(msg)+'\nUse RUN_RESUME_WINDOWS.bat only to continue an interrupted execution.')

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--repo',default='.')
    ap.add_argument('--godot',required=True)
    ap.add_argument('--smoke-only',action='store_true')
    ap.add_argument('--resume',action='store_true')
    a=ap.parse_args()
    if sys.version_info < (3,10): raise SystemExit('Python 3.10+ required')
    repo=Path(a.repo).resolve(); paper=repo/'experiments/paper_experiments'; add=repo/'experiments/additional_experiments'
    assert_clean_results(repo,a.resume)
    if not a.resume:
        clean_ephemeral_staging(repo)
    try: version=capture([a.godot,'--version'])
    except Exception as e: raise SystemExit(f'Cannot execute Godot: {e}')
    log('Godot: '+version)
    if not version.startswith('4.7'): raise SystemExit('This replication package requires Godot 4.7.x.')
    core=repo/'frozen_code/ontology_core.gd'; identity=read_json(repo/'provenance/FROZEN_CORE_IDENTITY.json')
    actual=hashfile(core)
    if actual.lower()!=str(identity['sha256']).lower(): raise SystemExit(f'Canonical core SHA mismatch: {actual} != {identity["sha256"]}')

    if a.resume:
        os.environ['CIAS_EXECUTION_RESUME']='1'
    log('\n=== STATIC TESTS ===')
    run([sys.executable,'-m','pytest',repo/'tests','-q'])
    run([sys.executable,repo/'tools/build_manifest.py'])

    for sub in [paper/'godot',add/'godot']:
        runtime=sub/'runtime'; runtime.mkdir(parents=True,exist_ok=True); shutil.copy2(core,runtime/'ontology_core.gd')
    log('\n=== GODOT SMOKE: PAPER HARNESS ===')
    write_json(paper/'godot/work/run_request.json',{'mode':'smoke','core_script':'res://runtime/ontology_core.gd'})
    godot_run(a.godot,paper/'godot','res://tools/run_paper_experiments.gd')
    log('\n=== GODOT SMOKE: ADDITIONAL HARNESS ===')
    write_json(add/'godot/work/run_request.json',{'mode':'smoke','core_script':'res://runtime/ontology_core.gd'})
    godot_run(a.godot,add/'godot','res://tools/run_additional_experiments.gd')
    if a.smoke_only:
        log('\nSMOKE COMPLETE. No held-out range was opened.')
        return 0

    paper_results=paper/'results/generated'; paper_results.mkdir(parents=True,exist_ok=True)
    paper_prov=repo/'provenance/paper_experiments_execution'; paper_prov.mkdir(parents=True,exist_ok=True)
    paper_plan=read_json(paper/'config/seed_plan.json')
    def paper_stage(stage,protocol,conditions):
        q=paper_plan[stage]; out=paper_results/f'{stage}_runs.csv'; trace=paper_results/f'{stage}_trace.csv'
        if a.resume and out.exists() and trace.exists():
            log(f'RESUME: preserving existing paper stage {stage}: {out.name}')
        else:
            write_json(paper/'godot/work/run_request.json',{'mode':'batch','protocol':protocol,'seeds':rangei(q['first'],q['last']),'profiles':PROFILES,'conditions':conditions,'core_script':'res://runtime/ontology_core.gd','output_csv':str(out),'trace_csv':str(trace)})
            godot_run(a.godot,paper/'godot','res://tools/run_paper_experiments.gd')
        analysis=paper_results/'analysis'; run([sys.executable,paper/'analysis/analyze_paper_runs.py','--csv',out,'--stage',stage,'--outdir',analysis]); return out

    log('\n=== PAPER: INITIAL DIAGNOSTIC 253-260 ==='); paper_stage('initial_diagnostic','initial_diagnostic',DIAG_COND)
    log('\n=== PAPER: MATCHED DIAGNOSTIC 261-272 ==='); paper_stage('matched_diagnostic','matched_diagnostic',DIAG_COND)
    log('\n=== PAPER: PREFLIGHT 273-276 ==='); paper_stage('preflight','preflight',CONF_COND)
    confirm_marker=paper_prov/'HELDOUT_ACCESS.json'
    if not confirm_marker.exists():
        write_json(confirm_marker,{'status':'OPENED','range':'277-306','opened_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'purpose':'paper confirmatory replication'})
    log('\n=== PAPER: CONFIRMATORY 277-306 ==='); paper_stage('confirmatory','confirmatory',CONF_COND)

    add_results=add/'results/generated'; add_results.mkdir(parents=True,exist_ok=True)
    add_prov=repo/'provenance/additional_experiments_execution'; add_prov.mkdir(parents=True,exist_ok=True)
    add_plan=read_json(add/'config/seed_plan.json')
    indep=add_plan['independent_estimator']; sens=add_plan['parameter_sensitivity']['heldout']
    def add_split(label,q):
        stream=add_results/f'{label}_frame_stream.csv'; track=add_results/f'{label}_cias_tracking.csv'
        if a.resume and stream.exists() and track.exists():
            log(f'RESUME: preserving existing additional split {label}')
        else:
            write_json(add/'godot/work/run_request.json',{'mode':'split','seeds':rangei(q['first'],q['last']),'profiles':PROFILES,'core_script':'res://runtime/ontology_core.gd','stream_path':str(stream),'tracking_path':str(track)})
            godot_run(a.godot,add/'godot','res://tools/run_additional_experiments.gd')
        run([sys.executable,add/'analysis/validate_frame_stream.py',stream,'--expected-first',q['first'],'--expected-last',q['last']])
        run([sys.executable,add/'analysis/analyze_cias_tracking.py','--tracking',track,'--out',add_results/f'{label}_cias_run_metrics.csv'])
        return stream,track

    log('\n=== INDEPENDENT ESTIMATOR: DIAGNOSTIC 315-326 ==='); dstream,dtrack=add_split('estimator_diagnostic',indep['diagnostic'])
    log('\n=== INDEPENDENT ESTIMATOR: PREFLIGHT 327-330 ==='); pstream,ptrack=add_split('estimator_preflight',indep['preflight'])
    pre=add_results/'generic_preflight'
    frozen_fit=pre/'model_fit.json'
    if a.resume and frozen_fit.exists() and (pre/'run_metrics.csv').exists():
        log('RESUME: preserving existing diagnostic-only generic estimator fit and preflight evaluation')
    else:
        run([sys.executable,add/'analysis/evaluate_streams.py','--diagnostic',dstream,'--test',pstream,'--out',pre])
    gate=add_prov/'ESTIMATOR_PREFLIGHT_GATE.json'
    run([sys.executable,add/'analysis/preflight_gate.py','--stream',pstream,'--tracking',ptrack,'--baseline-metrics',pre/'run_metrics.csv','--baseline-fit',frozen_fit,'--out',gate])
    estimator_marker=add_prov/'HELDOUT_ACCESS.json'
    if not estimator_marker.exists():
        write_json(estimator_marker,{'status':'OPENED','range':'331-360','opened_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'purpose':'independent estimator held-out'})
    log('\n=== INDEPENDENT ESTIMATOR: HELD-OUT 331-360 ==='); hstream,htrack=add_split('estimator_heldout',indep['heldout'])
    bout=add_results/'generic_heldout'
    if a.resume and (bout/'run_metrics.csv').exists() and (bout/'model_fit.json').exists():
        log('RESUME: preserving existing generic held-out evaluation')
    else:
        run([sys.executable,add/'analysis/evaluate_streams.py','--diagnostic',dstream,'--test',hstream,'--out',bout,'--frozen-fit',frozen_fit])
    comparison=add_results/'cias_vs_generic_heldout.csv'
    run([sys.executable,add/'analysis/compare_with_cias.py','--cias',add_results/'estimator_heldout_cias_run_metrics.csv','--baseline',bout/'run_metrics.csv','--out',comparison])
    comparison_summary=comparison.with_name(comparison.stem+'_summary.csv')

    log('\n=== PARAMETER SENSITIVITY: PRESPECIFIED GRID, FRESH 361-390 ===')
    grid=add/'work/parameter_grid.jsonl'; grid.parent.mkdir(parents=True,exist_ok=True)
    run([sys.executable,add/'sweep/generate_parameter_grid.py','--config',add/'config/parameter_sweep.json','--out',grid])
    core_dir=add/'work/parameterized_cores'; patch_manifest=add_prov/'PARAMETERIZED_CORES.json'
    run([sys.executable,repo/'tools/patch_frozen_core.py','--source',core,'--grid',grid,'--outdir',core_dir,'--manifest',patch_manifest])
    sens_marker=add_prov/'PARAMETER_SENSITIVITY_HELDOUT_ACCESS.json'
    if not sens_marker.exists(): write_json(sens_marker,{'status':'OPENED','range':'361-390','opened_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'purpose':'parameter sensitivity held-out'})
    rows=[json.loads(x) for x in grid.read_text().splitlines() if x.strip()]
    active=add/'godot/runtime/ontology_core.gd'; parts=add/'work/sweep_parts'; parts.mkdir(parents=True,exist_ok=True); part_paths=[]
    for i,cfg in enumerate(rows,1):
        pid=cfg['parameter_id']; shutil.copy2(core_dir/f'ontology_core_{pid}.gd',active); part=parts/f'{i:02d}_{pid}.csv'; part_paths.append(part)
        log(f' parameter {i}/{len(rows)}: {cfg.get("label",pid)}')
        if a.resume and part.exists() and part.stat().st_size > 100:
            log(f'RESUME: preserving existing sweep part {part.name}')
        else:
            write_json(add/'godot/work/run_request.json',{'mode':'sweep','seeds':rangei(sens['first'],sens['last']),'profiles':PROFILES,'configs':[{'parameter_id':pid,'core_script':'res://runtime/ontology_core.gd'}],'tracking_path':str(part)})
            godot_run(a.godot,add/'godot','res://tools/run_additional_experiments.gd')
    shutil.copy2(core,active)
    sweep_track=add_results/'parameter_sensitivity_tracking.csv'
    with sweep_track.open('w',encoding='utf-8',newline='') as out:
        first=True
        for part in part_paths:
            lines=part.read_text(encoding='utf-8').splitlines(True)
            out.writelines(lines if first else lines[1:]); first=False
    sweep_metrics=add_results/'parameter_sensitivity_run_metrics.csv'; run([sys.executable,add/'analysis/analyze_cias_tracking.py','--tracking',sweep_track,'--out',sweep_metrics])
    sweep_summary=add_results/'parameter_sensitivity_summary.csv'; run([sys.executable,add/'sweep/summarize_sweep.py','--csv',sweep_metrics,'--out',sweep_summary,'--grid',grid])
    sweep_basin=sweep_summary.with_name(sweep_summary.stem+'_basin.csv')
    simultaneous=add_results/'parameter_sensitivity_simultaneous.csv'
    run([sys.executable,add/'analysis/simultaneous_sensitivity.py',
         '--csv',sweep_metrics,'--grid-summary',sweep_basin,'--out',simultaneous])
    run([sys.executable,add/'analysis/final_report.py',
         '--cias',add_results/'estimator_heldout_cias_run_metrics.csv',
         '--baseline',bout/'run_metrics.csv',
         '--comparison',comparison_summary,
         '--sweep',sweep_basin,
         '--simultaneous',simultaneous,
         '--out',add_results/'additional_experiments_execution_summary.json'])
    # Keep the raw frame-level sensitivity trace in a GitHub-safe compressed form.
    sweep_gz=sweep_track.with_suffix(sweep_track.suffix+'.gz')
    with sweep_track.open('rb') as fi, sweep_gz.open('wb') as raw:
        with gzip.GzipFile(filename='',mode='wb',fileobj=raw,compresslevel=9,mtime=0) as fo:
            shutil.copyfileobj(fi,fo,1024*1024)
    sweep_track.unlink()

    write_json(repo/'provenance/EXECUTION_SUMMARY.json',{
        'status':'COMPLETE','completed_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'godot_version':version,'python_version':sys.version.split()[0],
        'core_sha256':actual,'paper_confirmatory':'277-306','independent_estimator_heldout':'331-360','parameter_sensitivity_heldout':'361-390'
    })
    run([sys.executable,repo/'tools/build_manifest.py'])
    log('\nALL EXPERIMENTS COMPLETE')
    log('Generated outputs are available under experiments/*/results/generated/ and provenance/.')
    return 0

if __name__=='__main__': raise SystemExit(main())
