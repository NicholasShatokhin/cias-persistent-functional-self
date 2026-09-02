extends RefCounted

const DT = 0.1
const FRAMES = 240
const PROBE_START = 168
const CHANGE_POINTS = [42, 84, 126, 168]
const TRAINING_CHANGE_POINTS = [42, 84, 126]
const PROFILES = ["ground_creature", "wheeled_robot", "drone", "virtual_avatar"]
const DIAGNOSTIC_CONDITIONS = [
    "progressive_persistent", "final_from_start", "reverse_curriculum",
    "random_curriculum", "progressive_history_reset", "progressive_no_persistent_self"
]
const CONFIRMATORY_CONDITIONS = ["progressive_persistent", "progressive_no_persistent_self", "progressive_history_reset"]
const ANCHORS = [Vector2(-68,-34), Vector2(34,-56), Vector2(72,12), Vector2(8,62), Vector2(-76,48)]
const SIGNATURES = [
    [0.14,0.82,0.30,0.58], [0.69,0.23,0.78,0.34], [0.36,0.72,0.16,0.88],
    [0.84,0.45,0.63,0.19], [0.24,0.36,0.92,0.73]
]

func execute(req: Dictionary) -> Dictionary:
    var mode = str(req.get("mode", "smoke"))
    if mode == "smoke":
        return _smoke(req)
    if mode == "batch":
        return _batch(req)
    return {"ok": false, "error": "unknown mode: %s" % mode}

func _smoke(req: Dictionary) -> Dictionary:
    var core_script = str(req.get("core_script", "res://runtime/ontology_core.gd"))
    var r = _run_one(253, "ground_creature", "progressive_persistent", "matched_diagnostic", core_script, null, null)
    if not bool(r.get("ok", false)):
        return r
    return {"ok": true, "marker": "CIAS_PAPER_SMOKE_PASSED frames=240"}

func _batch(req: Dictionary) -> Dictionary:
    var protocol = str(req.get("protocol", "matched_diagnostic"))
    var seeds: Array = req.get("seeds", [])
    var profiles: Array = req.get("profiles", PROFILES)
    var core_script = str(req.get("core_script", "res://runtime/ontology_core.gd"))
    var output_csv = str(req.get("output_csv", ""))
    var trace_csv = str(req.get("trace_csv", ""))
    if output_csv.is_empty():
        return {"ok": false, "error": "output_csv missing"}
    var conditions: Array = req.get("conditions", _conditions_for(protocol))
    _ensure_parent(output_csv)
    var out = FileAccess.open(output_csv, FileAccess.WRITE)
    if out == null:
        return {"ok": false, "error": "cannot open output_csv"}
    _write_run_header(out)
    var trace = null
    if not trace_csv.is_empty():
        _ensure_parent(trace_csv)
        trace = FileAccess.open(trace_csv, FileAccess.WRITE)
        if trace == null:
            out.close()
            return {"ok": false, "error": "cannot open trace_csv"}
        _write_trace_header(trace)
    var count = 0
    for seed_v in seeds:
        var seed = int(seed_v)
        for profile_v in profiles:
            var profile = str(profile_v)
            for condition_v in conditions:
                var condition = str(condition_v)
                var r = _run_one(seed, profile, condition, protocol, core_script, out, trace)
                if not bool(r.get("ok", false)):
                    out.close()
                    if trace != null: trace.close()
                    return r
                count += 1
    out.close()
    if trace != null: trace.close()
    return {"ok": true, "marker": "CIAS_PAPER_BATCH_COMPLETE protocol=%s runs=%d" % [protocol, count]}

func _conditions_for(protocol: String) -> Array:
    if protocol == "initial_diagnostic" or protocol == "matched_diagnostic":
        return DIAGNOSTIC_CONDITIONS.duplicate()
    return CONFIRMATORY_CONDITIONS.duplicate()

func _run_one(seed: int, profile: String, condition: String, protocol: String, core_script_path: String, out, trace) -> Dictionary:
    var script = load(core_script_path)
    if script == null:
        return {"ok": false, "error": "cannot load core: %s" % core_script_path}
    var core = script.new()
    var ablation = "no_persistent_self" if condition == "progressive_no_persistent_self" else "full"
    var core_seed = seed * 1009 + PROFILES.find(profile) * 101 + 17
    core.reset(ablation, core_seed)
    var levels = _morphology_levels(seed, condition, protocol)
    var epoch = 0
    var initial_key = ""
    var pre_final_key = ""
    var last_true_key = ""
    var final_true_keys: Array[String] = []
    var final_lure_keys: Array[String] = []
    var final_self_margins: Array[float] = []
    var final_role_correct = 0
    var final_role_frames = 0
    var final_switches = 0
    var lure_frames = 0
    var lure_capture = 0
    var correct_final = 0
    var recovery_frame = -1
    var streak = 0
    var stage_pre_keys: Dictionary = {}
    var stage_recovered: Dictionary = {}
    var stage_lure_errors: Dictionary = {}
    var stage_lure_frames: Dictionary = {}
    var stage_recovery_frame: Dictionary = {}
    var all_true_keys: Array[String] = []
    var scene_hash_text = "%s|%d|%s|" % [protocol, seed, profile]
    var rng = _scene_rng(seed, profile, protocol)
    for frame in range(FRAMES):
        var stage = mini(4, int(frame / 42))
        var cp = CHANGE_POINTS.has(frame)
        if cp:
            if frame < PROBE_START:
                stage_pre_keys[stage] = last_true_key
                if condition == "progressive_history_reset":
                    core.reset("full", core_seed + stage * 10007)
                    epoch += 1
                if _notify_training_change_point(protocol, condition):
                    core.notify_change_point()
            else:
                pre_final_key = last_true_key
                core.notify_change_point()
        var level = int(levels[stage])
        var scene_stage = 4 if stage == 4 else level
        var harder = protocol != "initial_diagnostic"
        var previous_level = int(levels[maxi(0, stage-1)])
        var fd = _generate_frame(rng, seed, profile, frame, stage, scene_stage, previous_level, harder)
        var action = float(fd["action"])
        core.register_action(action)
        var core_obs: Array = []
        for row_v in fd["observations"]:
            core_obs.append(_core_observation(row_v))
        var assignments: Array[int] = core.observe_frame(core_obs.duplicate(true), DT)
        if assignments.size() != core_obs.size():
            return {"ok": false, "error": "assignment size mismatch seed=%d profile=%s condition=%s frame=%d" % [seed, profile, condition, frame]}
        var true_id = -1
        var lure_id = -1
        var true_self_p = 0.0
        var lure_self_p = 0.0
        var lure_present = false
        for i in range(fd["observations"].size()):
            var row: Dictionary = fd["observations"][i]
            var entity_id = int(assignments[i])
            if bool(row["is_true_lineage"]):
                true_id = entity_id
                true_self_p = core.get_role_posterior(entity_id, "Self")
            if bool(row["is_lure"]):
                lure_present = true
                lure_id = entity_id
                lure_self_p = core.get_role_posterior(entity_id, "Self")
        if true_id < 0:
            return {"ok": false, "error": "true self missing seed=%d profile=%s condition=%s frame=%d" % [seed, profile, condition, frame]}
        var true_key = "%d:%d" % [epoch, true_id]
        var lure_key = "%d:%d" % [epoch, lure_id] if lure_id >= 0 else ""
        if frame == 32:
            initial_key = true_key
        last_true_key = true_key
        all_true_keys.append(true_key)
        if stage > 0 and stage < 4:
            var block_start = stage * 42
            if frame >= block_start and frame < block_start + 20 and lure_present:
                var skey = str(stage)
                stage_lure_frames[skey] = int(stage_lure_frames.get(skey, 0)) + 1
                if lure_key == str(stage_pre_keys.get(stage, "")):
                    stage_lure_errors[skey] = int(stage_lure_errors.get(skey, 0)) + 1
            if frame >= block_start and frame < block_start + 42:
                var prior_key = str(stage_pre_keys.get(stage, ""))
                if not prior_key.is_empty() and true_key == prior_key:
                    if int(stage_recovered.get(str(stage), 0)) == 0:
                        stage_recovered[str(stage)] = 1
                        stage_recovery_frame[str(stage)] = frame
        if frame >= PROBE_START:
            final_true_keys.append(true_key)
            if lure_present:
                lure_frames += 1
                final_lure_keys.append(lure_key)
                if not pre_final_key.is_empty() and lure_key == pre_final_key:
                    lure_capture += 1
            final_self_margins.append(true_self_p - lure_self_p)
            final_role_frames += 1
            if core.get_best_role(true_id) == "Self": final_role_correct += 1
            if final_true_keys.size() > 1 and final_true_keys[-1] != final_true_keys[-2]:
                final_switches += 1
            if not pre_final_key.is_empty() and true_key == pre_final_key:
                correct_final += 1
                streak += 1
                if streak >= 5 and recovery_frame < 0:
                    recovery_frame = frame - 4
            else:
                streak = 0
        if trace != null:
            _write_trace(trace, seed, profile, condition, protocol, frame, epoch, stage, level, true_key, lure_key, pre_final_key, true_self_p, lure_self_p, lure_present, fd)
        scene_hash_text += _canonical_frame(fd)
    if initial_key.is_empty() or pre_final_key.is_empty():
        return {"ok": false, "error": "lineage anchors missing seed=%d profile=%s condition=%s" % [seed, profile, condition]}
    var retention = float(correct_final) / float(FRAMES - PROBE_START)
    var lure_rate = float(lure_capture) / float(maxi(1, lure_frames))
    var latency = 6.66 if recovery_frame < 0 else float(recovery_frame - PROBE_START) * DT
    var recovery_observed = 0 if recovery_frame < 0 else 1
    var margin = _mean(final_self_margins)
    var final_fragments = _unique_count(final_true_keys)
    var whole_fragments = _unique_count(all_true_keys)
    var qf = 1.0 / (1.0 + 0.28 * maxf(0.0, float(final_fragments - 1)))
    var qt = exp(-latency / 2.8) if recovery_observed == 1 else 0.0
    var qm = clampf((margin + 1.0) / 2.0, 0.0, 1.0)
    var score_v2 = 0.30 * retention + 0.20 * (1.0 - lure_rate) + 0.16 * qt + 0.24 * qm + 0.10 * qf
    var legacy_qt = exp(-latency / 2.4) if recovery_observed == 1 else 0.0
    var score_legacy = 0.50 * retention + 0.25 * (1.0 - lure_rate) + 0.25 * legacy_qt
    var stage_chain = _stage_chain_score(stage_recovered)
    var training_lure_error = _training_lure_error(stage_lure_errors, stage_lure_frames)
    var training_recovery_latency = _training_recovery_latency(stage_recovery_frame)
    var final_role_accuracy = float(final_role_correct) / float(maxi(1, final_role_frames))
    var initial_retained_at_end = 1.0 if not final_true_keys.is_empty() and final_true_keys[-1] == initial_key else 0.0
    if out != null:
        _write_run(out, seed, profile, condition, protocol, score_v2, score_legacy, retention, latency, recovery_observed, lure_rate, final_switches, margin, final_fragments, whole_fragments, stage_chain, training_lure_error, training_recovery_latency, initial_retained_at_end, final_role_accuracy, scene_hash_text.sha256_text())
    return {"ok": true}

func _notify_training_change_point(protocol: String, condition: String) -> bool:
    if protocol == "initial_diagnostic" and condition == "final_from_start":
        return false
    return true

func _morphology_levels(seed: int, condition: String, protocol: String) -> Array[int]:
    var levels: Array[int] = []
    if condition == "final_from_start":
        levels.assign([3, 3, 3, 3, 3])
        return levels
    if condition == "reverse_curriculum":
        if protocol == "initial_diagnostic":
            levels.assign([3, 2, 1, 0, 3])
        else:
            levels.assign([2, 1, 0, 3, 3])
        return levels
    if condition == "random_curriculum":
        if protocol == "initial_diagnostic":
            levels.assign([0, 1, 2, 3])
        else:
            levels.assign([0, 1, 2])
        var rr = RandomNumberGenerator.new()
        rr.seed = seed * 65537 + 991
        for i in range(levels.size() - 1, 0, -1):
            var j: int = int(rr.randi_range(0, i))
            var t: int = levels[i]
            levels[i] = levels[j]
            levels[j] = t
        if protocol == "initial_diagnostic":
            var initial_levels: Array[int] = []
            initial_levels.assign([levels[0], levels[1], levels[2], levels[3], 3])
            return initial_levels
        var matched_levels: Array[int] = []
        matched_levels.assign([levels[0], levels[1], levels[2], 3, 3])
        return matched_levels
    levels.assign([0, 1, 2, 3, 3])
    return levels

func _scene_rng(seed: int, profile: String, protocol: String) -> RandomNumberGenerator:
    var rng = RandomNumberGenerator.new()
    var protocol_offset = 10000019 if protocol == "initial_diagnostic" else 20000033
    rng.seed = seed * 1000003 + (PROFILES.find(profile)+1) * 7919 + protocol_offset
    return rng

func _generate_frame(rng, seed:int, profile:String, frame:int, stage:int, morphology:int, previous_morphology:int, harder:bool) -> Dictionary:
    var action = clampf(0.66 + 0.25 * sin(0.37 * frame + 0.11 * seed), 0.22, 0.98)
    var anchor: Vector2 = ANCHORS[stage]
    var pos = Vector2(anchor.x + 27.0*sin(0.18*frame+0.30*morphology), anchor.y + 22.0*cos(0.15*frame+0.17*seed))
    var ambiguous = stage == 4 or (stage > 0 and frame < stage*42 + (24 if harder else 12))
    var noise = _profile_noise(profile)
    var obs: Array = []
    obs.append(_self_obs(rng, frame, stage, morphology, pos, noise, ambiguous, profile, harder))
    obs.append(_object_obs(rng, frame, noise))
    obs.append(_agent_obs(rng, frame, seed, noise))
    var intermediate_lure_frames = 20 if harder else 12
    var final_lure_frames = 48 if harder else 32
    var lure_present = (stage>0 and stage<4 and frame < stage*42+intermediate_lure_frames) or (stage==4 and frame < PROBE_START+final_lure_frames)
    if lure_present:
        obs.append(_lure_obs(rng, frame, stage, previous_morphology, noise, profile, harder))
    _shuffle(obs, rng)
    return {"frame":frame,"time_s":frame*DT,"action":action,"change_point":CHANGE_POINTS.has(frame),"observations":obs}

func _self_obs(rng, frame:int, stage:int, morphology:int, pos:Vector2, noise:float, ambiguous:bool, profile:String, harder:bool) -> Dictionary:
    var sig_index = 4 if stage == 4 else morphology
    var sig = _noisy_signature(SIGNATURES[sig_index], rng, noise*0.65, profile)
    var eff = 0.94; var out = 0.93; var proprio=0.93; var temporal=0.94; var cross=0.91; var intero=0.93; var homeo=0.91; var history=0.92
    if ambiguous:
        if harder:
            eff=0.76; out=0.78; proprio=0.73; temporal=0.80; cross=0.79; intero=0.76; homeo=0.73; history=0.78
            var phase = (frame-PROBE_START) % 8 if stage==4 else (frame-stage*42)%8
            if phase==0: eff=0.52; out=0.58
            elif phase==1: proprio=0.52
            elif phase==2: intero=0.54
            elif phase==3: homeo=0.52
            elif phase==4: history=0.55
            elif phase==5: temporal=0.58
            elif phase==7:
                eff=0.94; out=0.93; proprio=0.92; temporal=0.93; intero=0.92; homeo=0.90; history=0.91
        else:
            eff=0.87; out=0.88; proprio=0.86; temporal=0.89; intero=0.88; homeo=0.86; history=0.87
    var rel = _profile_reliability(profile)
    return _row("self",pos,sig,rng,noise,eff*rel,out*rel,proprio*rel,temporal,cross,0.96,0.72,0.03,0.04,0.03,0.02,intero*rel,homeo*rel,history*rel,true,false,"SELF")

func _lure_obs(rng, frame:int, stage:int, previous_morphology:int, noise:float, profile:String, harder:bool) -> Dictionary:
    var old_stage = maxi(0, stage-1)
    var anchor: Vector2 = ANCHORS[old_stage]
    var pos = Vector2(anchor.x + 8*sin(0.22*frame), anchor.y + 7*cos(0.19*frame))
    var old_sig_index = previous_morphology if stage < 4 else 3
    var sig = _noisy_signature(SIGNATURES[old_sig_index], rng, noise*0.45, profile)
    if not harder:
        return _row("lure",pos,sig,rng,noise,0.16,0.18,0.12,0.55,0.72,0.94,0.66,0.08,0.05,0.08,0.02,0.07,0.08,0.10,false,true,"LURE")
    var pulse = 0.05*sin(0.31*frame)
    return _row("lure",pos,sig,rng,noise,0.68+pulse,0.67+pulse,0.58,0.82,0.80,0.94,0.66,0.10,0.08,0.18,0.02,0.48,0.44,0.69,false,true,"LURE")

func _object_obs(rng, frame:int, noise:float) -> Dictionary:
    var pos=Vector2(-25+5*sin(0.03*frame),82+3*cos(0.05*frame)); var sig=[0.47,0.50,0.44,0.53]
    return _row("object",pos,_noisy_signature(sig,rng,noise*0.4,""),rng,noise,0.04,0.05,0.05,0.22,0.72,0.97,0.94,0.05,0.03,0.04,0.01,0.03,0.06,0.10,false,false,"OBJECT")

func _agent_obs(rng, frame:int, seed:int, noise:float) -> Dictionary:
    var pos=Vector2(95+18*sin(0.09*frame+seed),-70+20*cos(0.08*frame+0.3*seed)); var sig=[0.61,0.17,0.48,0.79]
    return _row("agent",pos,_noisy_signature(sig,rng,noise*0.55,""),rng,noise,0.05,0.07,0.04,0.42,0.70,0.91,0.30,0.93,0.91,0.86,0.02,0.03,0.04,0.22,false,false,"AGENT")

func _row(id:String,pos:Vector2,sig:Array,rng,noise:float,eff:float,out:float,proprio:float,temporal:float,cross:float,persist:float,physical:float,autonomy:float,goal:float,response:float,tool:float,intero:float,homeo:float,history:float,is_self:bool,is_lure:bool,truth:String) -> Dictionary:
    var eff_n=_n(eff,rng,noise); var out_n=_n(out,rng,noise); var motor=sqrt(maxf(0.0,eff_n*out_n))
    return {"observation_id":id,"x":pos.x+rng.randfn(0,noise*5.0),"y":pos.y+rng.randfn(0,noise*5.0),"signature":sig,
        "appearance":(float(sig[0])+float(sig[1])+float(sig[2])+float(sig[3]))/4.0,
        "efference":eff_n,"outcome":out_n,"motor":motor,"proprio":_n(proprio,rng,noise),
        "temporal":_n(temporal,rng,noise),"crossmodal":_n(cross,rng,noise),"persistence":_n(persist,rng,noise*0.5),
        "physical":_n(physical,rng,noise),"autonomy":_n(autonomy,rng,noise),"goal":_n(goal,rng,noise),"response":_n(response,rng,noise),"tool":_n(tool,rng,noise),
        "intero":_n(intero,rng,noise),"homeo":_n(homeo,rng,noise),"history":_n(history,rng,noise),
        "is_true_lineage":is_self,"is_lure":is_lure,"truth_entity_id":truth}

func _core_observation(row: Dictionary) -> Dictionary:
    return {
        "position": Vector2(float(row["x"]),float(row["y"])), "signature": row["signature"].duplicate(),
        "efference_copy": float(row["efference"]), "action_outcome_match": float(row["outcome"]),
        "proprioceptive_closure": float(row["proprio"]), "temporal_match": float(row["temporal"]),
        "cross_modal_coherence": float(row["crossmodal"]), "persistence": float(row["persistence"]),
        "physical_predictability": float(row["physical"]), "autonomous_dynamics": float(row["autonomy"]),
        "goal_directedness": float(row["goal"]), "response_contingency": float(row["response"]),
        "tool_coupling": float(row["tool"]), "interoceptive_closure": float(row["intero"]),
        "homeostatic_coupling": float(row["homeo"]), "action_history_match": float(row["history"]),
        "reply_emission": float(row["response"])
    }

func _profile_noise(p:String)->float:
    match p:
        "drone": return 0.060
        "wheeled_robot": return 0.030
        "virtual_avatar": return 0.012
    return 0.020

func _profile_reliability(p:String)->float:
    match p:
        "drone": return 0.89
        "wheeled_robot": return 0.94
        "virtual_avatar": return 0.99
    return 0.97

func _n(x:float,rng,noise:float)->float: return clampf(x+rng.randfn(0,noise),0.0,1.0)
func _noisy_signature(base:Array,rng,noise:float,profile:String)->Array:
    var off = 0.015 * float(PROFILES.find(profile)) if PROFILES.has(profile) else 0.0
    var out:Array=[]
    for i in range(base.size()): out.append(clampf(float(base[i])+off*(1 if i%2==0 else -1)+rng.randfn(0,noise),0.0,1.0))
    return out
func _shuffle(a:Array,rng)->void:
    for i in range(a.size()-1,0,-1):
        var j: int = int(rng.randi_range(0, i)); var t: Variant = a[i]; a[i] = a[j]; a[j] = t

func _mean(a:Array)->float:
    if a.is_empty(): return 0.0
    var s=0.0
    for v in a: s += float(v)
    return s/float(a.size())
func _unique_count(a:Array)->int:
    var d:Dictionary={}
    for v in a: d[str(v)] = true
    return d.size()
func _stage_chain_score(recovered:Dictionary)->float:
    var n=0
    for stage in [1,2,3]: n += int(recovered.get(str(stage),0))
    return float(n)/3.0
func _training_lure_error(err:Dictionary, frames:Dictionary)->float:
    var e=0; var n=0
    for stage in [1,2,3]:
        e += int(err.get(str(stage),0)); n += int(frames.get(str(stage),0))
    return float(e)/float(maxi(1,n))
func _training_recovery_latency(recovery:Dictionary)->float:
    var vals:Array=[]
    for stage in [1,2,3]:
        var f=int(recovery.get(str(stage),-1))
        if f>=0: vals.append(float(f-stage*42)*DT)
        else: vals.append(4.2)
    return _mean(vals)
func _canonical_frame(fd:Dictionary)->String:
    var s="%d|%.6f|%d|" % [int(fd["frame"]),float(fd["action"]),1 if fd["change_point"] else 0]
    for r_v in fd["observations"]:
        var r:Dictionary=r_v; s += "%s|%.5f|%.5f|" % [r["observation_id"],r["x"],r["y"]]
        for x in r["signature"]: s += "%.5f," % float(x)
        for k in ["efference","outcome","motor","proprio","temporal","crossmodal","persistence","physical","autonomy","goal","response","tool","intero","homeo","history"]: s += "|%.5f" % float(r[k])
    return s+";"

func _write_run_header(f)->void:
    f.store_csv_line(PackedStringArray(["seed","profile","condition","protocol","identity_continuity_score_v2","identity_continuity_score_legacy","final_identity_retention","final_identity_recovery_latency","final_recovery_observed","final_old_signature_clone_capture","final_identity_switches","final_self_posterior_margin","final_identity_fragmentation","whole_run_self_fragmentation","stage_identity_chain_score","training_transition_lure_error","training_transition_recovery_latency","initial_identity_retained_at_end","final_self_role_accuracy","scene_hash"]))
func _write_run(f,seed:int,profile:String,condition:String,protocol:String,q:float,qlegacy:float,ret:float,lat:float,obs:int,lure:float,switches:int,margin:float,frag:int,whole:int,chain:float,train_lure:float,train_lat:float,initial_end:float,role_acc:float,scene_hash:String)->void:
    f.store_csv_line(PackedStringArray([str(seed),profile,condition,protocol,str(q),str(qlegacy),str(ret),str(lat),str(obs),str(lure),str(switches),str(margin),str(frag),str(whole),str(chain),str(train_lure),str(train_lat),str(initial_end),str(role_acc),scene_hash]))
func _write_trace_header(f)->void:
    f.store_csv_line(PackedStringArray(["seed","profile","condition","protocol","frame","epoch","stage","morphology_level","true_key","lure_key","pre_final_key","true_self_p","lure_self_p","lure_present","change_point"]))
func _write_trace(f,seed:int,profile:String,condition:String,protocol:String,frame:int,epoch:int,stage:int,level:int,true_key:String,lure_key:String,pre_final_key:String,true_p:float,lure_p:float,lure_present:bool,fd:Dictionary)->void:
    f.store_csv_line(PackedStringArray([str(seed),profile,condition,protocol,str(frame),str(epoch),str(stage),str(level),true_key,lure_key,pre_final_key,str(true_p),str(lure_p),"1" if lure_present else "0","1" if fd["change_point"] else "0"]))
func _ensure_parent(path:String)->void: DirAccess.make_dir_recursive_absolute(path.get_base_dir())
