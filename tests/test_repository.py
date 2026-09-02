from pathlib import Path
import hashlib, json, subprocess, sys, re
import pandas as pd
import os

ROOT=Path(__file__).resolve().parents[1]

def test_canonical_core_hash():
    meta=json.loads((ROOT/'provenance/FROZEN_CORE_IDENTITY.json').read_text())
    p=ROOT/meta['path']
    assert p.is_file()
    assert hashlib.sha256(p.read_bytes()).hexdigest()==meta['sha256']

def test_no_obsolete_naming_or_old_sha_in_active_text():
    banned=['baa0'+'bfe03eb13c14a8df559442c05fda49519fae374c744c88950710b19eb3ce']
    for p in ROOT.rglob('*'):
        if not p.is_file() or p.suffix.lower() in {'.pdf','.png','.jpg','.jpeg','.zip'}: continue
        if any(x in p.parts for x in ['.venv-experiments','__pycache__','.pytest_cache']): continue
        txt=p.read_text(encoding='utf-8',errors='ignore').lower()
        for b in banned: assert b not in txt, f'{b} in {p}'

def test_seed_ranges_are_disjoint():
    plan=json.loads((ROOT/'experiments/paper_experiments/config/seed_plan.json').read_text())
    ranges=[]
    for name,q in plan.items():
        if 'first' in q and 'last' in q:
            r=set(range(q['first'],q['last']+1)); ranges.append((name,r))
    for i,(a,ra) in enumerate(ranges):
        for b,rb in ranges[i+1:]:
            assert ra.isdisjoint(rb), (a,b,sorted(ra&rb))

def test_additional_ranges_match_master_plan():
    master=json.loads((ROOT/'experiments/paper_experiments/config/seed_plan.json').read_text())
    add=json.loads((ROOT/'experiments/additional_experiments/config/seed_plan.json').read_text())
    assert add['independent_estimator']['heldout']=={k:master['independent_estimator_heldout'][k] for k in ['first','last']}
    assert add['parameter_sensitivity']['heldout']=={k:master['parameter_sensitivity_heldout'][k] for k in ['first','last']}

def test_expected_run_counts():
    p=json.loads((ROOT/'experiments/paper_experiments/config/seed_plan.json').read_text())
    for name in ['initial_diagnostic','matched_diagnostic','preflight','confirmatory']:
        q=p[name]
        assert (q['last']-q['first']+1)*q['profiles']*q['conditions']==q['expected_runs']

def test_results_are_clean_before_execution():
    # Fresh-package QA requires no evidence. During an explicit resume, existing
    # evidence is the checkpoint being preserved and must not make static QA fail.
    if os.environ.get('CIAS_EXECUTION_RESUME') == '1':
        return
    for base in [ROOT/'experiments/paper_experiments/results',ROOT/'experiments/additional_experiments/results']:
        for p in base.rglob('*'):
            if p.is_file(): assert p.name in {'.gitkeep','README.md'}

def test_core_contains_documented_operating_point():
    s=(ROOT/'frozen_code/ontology_core.gd').read_text()
    for token in ['var signature_weight: float = 0.43','var position_weight: float = 0.37','var dynamic_weight: float = 0.20',
                  'signature_weight = 0.20','position_weight = 0.29','dynamic_weight = 0.51','return 0.82','return 0.66',
                  'observation_self > 0.70','_observation_self_anchor_strength(observation) > 0.62','var alpha: float = 0.12']:
        assert token in s

def test_parameter_grid_has_27_unique_points(tmp_path):
    out=tmp_path/'grid.jsonl'
    subprocess.run([sys.executable,ROOT/'experiments/additional_experiments/sweep/generate_parameter_grid.py','--config',ROOT/'experiments/additional_experiments/config/parameter_sweep.json','--out',out],check=True)
    rows=[json.loads(x) for x in out.read_text().splitlines() if x.strip()]
    assert len(rows)==27
    assert len({r['parameter_id'] for r in rows})==27

def test_parameter_patcher_is_fail_closed_and_generates(tmp_path):
    grid=tmp_path/'grid.jsonl'; cores=tmp_path/'cores'; manifest=tmp_path/'manifest.json'
    subprocess.run([sys.executable,ROOT/'experiments/additional_experiments/sweep/generate_parameter_grid.py','--config',ROOT/'experiments/additional_experiments/config/parameter_sweep.json','--out',grid],check=True)
    subprocess.run([sys.executable,ROOT/'tools/patch_frozen_core.py','--source',ROOT/'frozen_code/ontology_core.gd','--grid',grid,'--outdir',cores,'--manifest',manifest],check=True)
    m=json.loads(manifest.read_text()); assert len(m['generated'])==27
    altered=tmp_path/'bad.gd'; altered.write_text((ROOT/'frozen_code/ontology_core.gd').read_text()+'\n# mutation\n')
    p=subprocess.run([sys.executable,ROOT/'tools/patch_frozen_core.py','--source',altered,'--grid',grid,'--outdir',tmp_path/'badcores','--manifest',tmp_path/'badmanifest.json'])
    assert p.returncode!=0

def test_paper_harness_has_exact_conditions_and_240_frames():
    s=(ROOT/'experiments/paper_experiments/godot/scripts/paper_experiments_benchmark.gd').read_text()
    assert 'const FRAMES = 240' in s and 'const PROBE_START = 168' in s
    for c in ['progressive_persistent','final_from_start','reverse_curriculum','random_curriculum','progressive_history_reset','progressive_no_persistent_self']:
        assert c in s
    assert 'protocol == "initial_diagnostic" and condition == "final_from_start"' in s

def test_additional_harness_uses_pre_final_lineage_and_matched_noise():
    s=(ROOT/'experiments/additional_experiments/godot/scripts/additional_experiments_benchmark.gd').read_text()
    assert 'if frame == 167:' in s
    assert '"drone": return 0.060' in s
    assert '"wheeled_robot": return 0.030' in s
    assert '"virtual_avatar": return 0.012' in s
    assert 'return 0.020' in s

def test_public_text_has_no_internal_handoff_language():
    targets=[ROOT/'README.md', ROOT/'README_UA.md', ROOT/'protocols/COMPLETE_EXPERIMENTAL_PROGRAM.md', ROOT/'tools/run_full_replication.py', ROOT/'experiments/additional_experiments/analysis/final_report.py']
    banned=['send this '+'repository','send '+'back','return them for '+'manuscript','manuscript '+'recomputation','pending '+'manuscript interpretation','pre_'+'rerun_reference','post-run '+'manuscript']
    for p in targets:
        txt=p.read_text(encoding='utf-8',errors='ignore').lower()
        for phrase in banned:
            assert phrase not in txt, f'internal handoff language in {p}: {phrase}'


def test_root_one_click_entrypoints_exist():
    for f in ['RUN_SMOKE_WINDOWS.bat','RUN_ALL_WINDOWS.bat','RUN_RESUME_WINDOWS.bat','RUN_SMOKE_LINUX.sh','RUN_ALL_LINUX.sh']:
        assert (ROOT/f).is_file()


def test_godot_47_harness_avoids_ambiguous_string_constructors_and_inference():
    # Check only newly written execution harnesses. The canonical scientific core
    # is an independently versioned dependency and valid typed inference inside
    # it must not be rejected by this compatibility guard.
    harnesses = [
        ROOT/'experiments/paper_experiments/godot/scripts/paper_experiments_benchmark.gd',
        ROOT/'experiments/paper_experiments/godot/tools/run_paper_experiments.gd',
        ROOT/'experiments/additional_experiments/godot/scripts/additional_experiments_benchmark.gd',
        ROOT/'experiments/additional_experiments/godot/tools/run_additional_experiments.gd',
    ]
    for p in harnesses:
        s=p.read_text()
        assert 'String(' not in s, f'Godot 4.7-incompatible constructor-style String conversion in {p}'
        assert ':=' not in s, f'Ambiguous inferred assignment remains in dynamic experiment harness: {p}'
    paper=harnesses[0].read_text()
    additional=harnesses[2].read_text()
    assert 'var j: int = int(rng.randi_range(0, i))' in paper
    assert 'var j: int = int(rng.randi_range(0, i))' in additional


def test_manifest_excludes_ephemeral_godot_staging(tmp_path):
    paper_runtime=ROOT/'experiments/paper_experiments/godot/runtime/ontology_core.gd'
    paper_work=ROOT/'experiments/paper_experiments/godot/work/run_request.json'
    # A fresh clone intentionally has no runtime/work staging directories.
    # The test must create its own ephemeral staging before checking that the
    # manifest excludes it.
    paper_runtime.parent.mkdir(parents=True, exist_ok=True)
    paper_work.parent.mkdir(parents=True, exist_ok=True)
    paper_runtime.write_text('# staging copy\n')
    paper_work.write_text('{}\n')
    try:
        subprocess.run([sys.executable,ROOT/'tools/build_manifest.py'],check=True)
        manifest=json.loads((ROOT/'provenance/MANIFEST_SHA256.json').read_text())
        paths={r['path'] for r in manifest['files']}
        assert 'experiments/paper_experiments/godot/runtime/ontology_core.gd' not in paths
        assert 'experiments/paper_experiments/godot/work/run_request.json' not in paths
    finally:
        paper_runtime.unlink(missing_ok=True)
        paper_work.unlink(missing_ok=True)
        for d in (paper_runtime.parent, paper_work.parent):
            try:
                d.rmdir()
            except OSError:
                pass
        subprocess.run([sys.executable,ROOT/'tools/build_manifest.py'],check=True)

def test_godot_typed_arrays_avoid_ternary_assignment():
    pattern = re.compile(r'Array\[[^\]]+\]\s*=\s*.*\bif\b.*\belse\b')
    harnesses = [
        ROOT/'experiments/paper_experiments/godot/scripts/paper_experiments_benchmark.gd',
        ROOT/'experiments/additional_experiments/godot/scripts/additional_experiments_benchmark.gd',
    ]
    for p in harnesses:
        for line_no, line in enumerate(p.read_text().splitlines(), 1):
            assert not pattern.search(line), f'Godot typed-array ternary assignment in {p}:{line_no}: {line}'


def test_preflight_gate_checks_lineage_only_after_frame_167():
    s=(ROOT/'experiments/additional_experiments/analysis/preflight_gate.py').read_text()
    assert 'frame.astype(int)>=167' in s
    assert 'frame.astype(int)>=32' not in s

def test_resume_entrypoint_is_checkpoint_aware():
    s=(ROOT/'tools/run_full_replication.py').read_text()
    assert 'RESUME: preserving existing paper stage' in s
    assert 'RESUME: preserving existing additional split' in s
    assert "os.environ['CIAS_EXECUTION_RESUME']='1'" in s

def test_preflight_gate_accepts_lineage_established_at_frame_167(tmp_path):
    import numpy as np
    profiles=['ground_creature','wheeled_robot','drone','virtual_avatar']
    cues=['appearance','appearance_0','appearance_1','appearance_2','appearance_3','efference','outcome','motor','proprio','temporal','crossmodal','persistence','physical','autonomy','goal','response','tool','intero','homeo','history']
    stream=[]; tracking=[]; metrics=[]
    for seed in range(327,331):
        for profile in profiles:
            rid=f'{seed}_{profile}'
            sh=f'hash_{seed}_{profile}'
            for frame in range(240):
                row={'run_id':rid,'seed':seed,'profile':profile,'scenario':'persistent_identity_lure','frame':frame,'time_s':frame*0.1,'scene_hash':sh,'is_lure':1 if frame>=168 else 0}
                for c in cues: row[c]=0.5
                stream.append(row)
                for cond in ['cias_full','cias_no_persistent_self']:
                    tracking.append({'condition':cond,'run_id':rid,'seed':seed,'profile':profile,'scenario':'persistent_identity_lure','frame':frame,'scene_hash':sh,'lineage_id':-1 if frame<167 else 1})
            metrics.append({'model':'generic_recurrent_filter','run_id':rid,'seed':seed,'profile':profile,'scenario':'persistent_identity_lure','identity_continuity':0.5,'lure_capture':0.5})
    sp=tmp_path/'stream.csv'; tp=tmp_path/'tracking.csv'; mp=tmp_path/'metrics.csv'; fp=tmp_path/'fit.json'; op=tmp_path/'gate.json'
    pd.DataFrame(stream).to_csv(sp,index=False); pd.DataFrame(tracking).to_csv(tp,index=False); pd.DataFrame(metrics).to_csv(mp,index=False)
    fit={'selection_boundary':'Grouped leave-one-seed-out cross-validation on diagnostic seeds only.','positive_mean':[0.5],'positive_var':[0.1],'negative_mean':[0.4],'negative_var':[0.1]}
    fp.write_text(json.dumps(fit))
    p=subprocess.run([sys.executable,ROOT/'experiments/additional_experiments/analysis/preflight_gate.py','--stream',sp,'--tracking',tp,'--baseline-metrics',mp,'--baseline-fit',fp,'--out',op],capture_output=True,text=True)
    assert p.returncode==0, p.stdout+p.stderr
    obj=json.loads(op.read_text())
    assert obj['status']=='PASS'


def test_compare_with_cias_filters_condition_before_one_to_one_merge(tmp_path):
    cias=[]; base=[]
    for seed in [331,332]:
        for profile in ['ground_creature','wheeled_robot','drone','virtual_avatar']:
            common={'seed':seed,'profile':profile,'scenario':'matched_adversarial_identity'}
            cias.append(common|{'condition':'cias_full','identity_continuity':0.8,'lure_capture':0.1})
            cias.append(common|{'condition':'cias_no_persistent_self','identity_continuity':0.3,'lure_capture':0.8})
            base.append(common|{'model':'generic_recurrent_filter','identity_continuity':0.6,'lure_capture':0.3})
            base.append(common|{'model':'appearance_continuity_sanity','identity_continuity':0.2,'lure_capture':0.9})
    cp=tmp_path/'cias.csv'; bp=tmp_path/'baseline.csv'; op=tmp_path/'comparison.csv'
    pd.DataFrame(cias).to_csv(cp,index=False); pd.DataFrame(base).to_csv(bp,index=False)
    q=subprocess.run([sys.executable,ROOT/'experiments/additional_experiments/analysis/compare_with_cias.py','--cias',cp,'--baseline',bp,'--out',op],capture_output=True,text=True)
    assert q.returncode==0, q.stdout+q.stderr
    out=pd.read_csv(op)
    assert len(out)==8
    assert set(out.cias_condition)=={'cias_full'}
    assert set(out.baseline_model)=={'generic_recurrent_filter'}
    assert (out.continuity_advantage.round(8)==0.2).all()
    assert (out.lure_rejection_advantage.round(8)==0.2).all()
    sm=pd.read_csv(op.with_name('comparison_summary.csv'))
    assert set(sm.metric)=={'continuity_advantage','lure_rejection_advantage'}
    assert (sm.n_seeds==2).all()


def test_runner_wires_filtered_cias_comparison_and_final_report():
    s=(ROOT/'tools/run_full_replication.py').read_text()
    assert "comparison=add_results/'cias_vs_generic_heldout.csv'" in s
    assert "comparison_summary=comparison.with_name(comparison.stem+'_summary.csv')" in s
    assert "add/'analysis/final_report.py'" in s
    assert "sweep_summary.stem+'_basin.csv'" in s


def test_public_repository_has_no_github_100mb_objects():
    limit=100*1024*1024
    bad=[]
    for p in ROOT.rglob('*'):
        if p.is_file() and '.git' not in p.parts and p.stat().st_size>limit:
            bad.append((p.relative_to(ROOT).as_posix(),p.stat().st_size))
    assert not bad, bad


def test_reference_sensitivity_trace_is_compressed_and_hashed():
    import gzip, hashlib
    gz=ROOT/'reference_results/additional_experiments/generated/parameter_sensitivity_tracking.csv.gz'
    meta=json.loads((ROOT/'reference_results/RAW_REFERENCE_FILE.json').read_text())
    assert gz.exists()
    assert gz.stat().st_size < 100*1024*1024
    assert hashlib.sha256(gz.read_bytes()).hexdigest()==meta['compressed_sha256']
    h=hashlib.sha256(); n=0
    with gzip.open(gz,'rb') as f:
        while True:
            b=f.read(1024*1024)
            if not b: break
            n+=len(b); h.update(b)
    assert n==meta['uncompressed_size_bytes']
    assert h.hexdigest()==meta['uncompressed_sha256']


def test_simultaneous_sensitivity_output_is_complete():
    p=ROOT/'reference_results/additional_experiments/generated/parameter_sensitivity_simultaneous.csv'
    m=p.with_suffix('.json')
    assert p.exists() and m.exists()
    df=pd.read_csv(p)
    meta=json.loads(m.read_text())
    assert len(df)==27
    assert meta['family']=='all 54 sensitivity effects (27 settings x 2 primary metrics)'
    assert meta['both_simultaneous_positive_count']==24
