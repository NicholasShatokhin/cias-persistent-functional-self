extends RefCounted

const DT = 0.1
const FRAMES = 240
const PROBE_START = 168
const CHANGE_POINTS = [42, 84, 126, 168]
const SCENARIO = "matched_adversarial_identity"
const PROFILES = ["ground_creature", "wheeled_robot", "drone", "virtual_avatar"]
const ANCHORS = [Vector2(-68,-34), Vector2(34,-56), Vector2(72,12), Vector2(8,62), Vector2(-76,48)]
const SIGNATURES = [
    [0.14,0.82,0.30,0.58], [0.69,0.23,0.78,0.34], [0.36,0.72,0.16,0.88],
    [0.84,0.45,0.63,0.19], [0.24,0.36,0.92,0.73]
]

func execute(req: Dictionary) -> Dictionary:
    var mode = str(req.get("mode", "smoke"))
    if mode == "smoke": return _smoke(req)
    if mode == "split": return _run_split(req)
    if mode == "sweep": return _run_sweep(req)
    return {"ok":false,"error":"unknown mode: %s" % mode}

func _smoke(req: Dictionary) -> Dictionary:
    var core_script = str(req.get("core_script", "res://runtime/ontology_core_central.gd"))
    var scene = _generate_scene(315, "ground_creature")
    var result = _run_models(scene, core_script, 315, "ground_creature", "central", null)
    if not bool(result.get("ok",false)): return result
    if int(result.get("frames",0)) != FRAMES: return {"ok":false,"error":"smoke frame count mismatch"}
    return {"ok":true,"marker":"CIAS_ADDITIONAL_SMOKE_PASSED frames=240"}

func _run_split(req: Dictionary) -> Dictionary:
    var seeds: Array = req.get("seeds", [])
    var profiles: Array = req.get("profiles", PROFILES)
    var core_script = str(req.get("core_script", "res://runtime/ontology_core_central.gd"))
    var stream_path = str(req.get("stream_path", ""))
    var tracking_path = str(req.get("tracking_path", ""))
    if stream_path.is_empty() or tracking_path.is_empty(): return {"ok":false,"error":"output paths missing"}
    _ensure_parent(stream_path); _ensure_parent(tracking_path)
    var sf = FileAccess.open(stream_path, FileAccess.WRITE)
    var tf = FileAccess.open(tracking_path, FileAccess.WRITE)
    if sf == null or tf == null: return {"ok":false,"error":"cannot open split outputs"}
    _write_stream_header(sf); _write_tracking_header(tf)
    var scenes = 0
    for seed_v in seeds:
        var seed = int(seed_v)
        for profile_v in profiles:
            var profile = str(profile_v)
            var scene = _generate_scene(seed, profile)
            _write_scene_stream(sf, scene, seed, profile)
            var r = _run_models(scene, core_script, seed, profile, "central", tf)
            if not bool(r.get("ok",false)): return r
            scenes += 1
    sf.close(); tf.close()
    return {"ok":true,"marker":"CIAS_ADDITIONAL_SPLIT_COMPLETE scenes=%d" % scenes}

func _run_sweep(req: Dictionary) -> Dictionary:
    var seeds: Array = req.get("seeds", [])
    var profiles: Array = req.get("profiles", PROFILES)
    var configs: Array = req.get("configs", [])
    var tracking_path = str(req.get("tracking_path", ""))
    if tracking_path.is_empty(): return {"ok":false,"error":"sweep tracking path missing"}
    _ensure_parent(tracking_path)
    var tf = FileAccess.open(tracking_path, FileAccess.WRITE)
    if tf == null: return {"ok":false,"error":"cannot open sweep output"}
    _write_tracking_header(tf)
    var scenes = 0
    for cfg_v in configs:
        var cfg: Dictionary = cfg_v
        var pid = str(cfg.get("parameter_id",""))
        var core_script = str(cfg.get("core_script",""))
        if pid.is_empty() or core_script.is_empty(): return {"ok":false,"error":"bad sweep config"}
        for seed_v in seeds:
            var seed = int(seed_v)
            for profile_v in profiles:
                var profile = str(profile_v)
                var scene = _generate_scene(seed, profile)
                var r = _run_models(scene, core_script, seed, profile, pid, tf)
                if not bool(r.get("ok",false)): return r
                scenes += 1
    tf.close()
    return {"ok":true,"marker":"CIAS_ADDITIONAL_SWEEP_COMPLETE scene_configs=%d" % scenes}

func _run_models(scene: Dictionary, core_script_path: String, seed: int, profile: String, parameter_id: String, tf) -> Dictionary:
    var script = load(core_script_path)
    if script == null: return {"ok":false,"error":"cannot load core: %s" % core_script_path}
    var full = script.new(); var lesion = script.new()
    var core_seed = seed * 1009 + PROFILES.find(profile) * 101 + 17
    full.reset("full", core_seed); lesion.reset("no_persistent_self", core_seed)
    var full_lineage = -1; var lesion_lineage = -1
    for fd_v in scene["frames"]:
        var fd: Dictionary = fd_v; var frame = int(fd["frame"])
        if bool(fd["change_point"]):
            full.notify_change_point(); lesion.notify_change_point()
        var action = float(fd["action"])
        full.register_action(action); lesion.register_action(action)
        var core_obs: Array = []
        for row_v in fd["observations"]: core_obs.append(_core_observation(row_v))
        # Give each condition an independent deep copy of the exact same observable frame.
        # This closes a possible cross-condition mutation channel if an ontology implementation
        # ever normalizes or annotates observation dictionaries in place.
        var fa: Array[int] = full.observe_frame(core_obs.duplicate(true), DT)
        var la: Array[int] = lesion.observe_frame(core_obs.duplicate(true), DT)
        if fa.size() != core_obs.size() or la.size() != core_obs.size():
            return {"ok":false,"error":"assignment-size mismatch seed=%d profile=%s frame=%d" % [seed,profile,frame]}
        if frame == 167:
            for i in range(fd["observations"].size()):
                var row: Dictionary = fd["observations"][i]
                if bool(row["is_true_lineage"]):
                    full_lineage = int(fa[i]); lesion_lineage = int(la[i]); break
        if tf != null:
            _write_tracking_frame(tf, fd, fa, "cias_full", full_lineage, seed, profile, parameter_id, scene["scene_hash"])
            _write_tracking_frame(tf, fd, la, "cias_no_persistent_self", lesion_lineage, seed, profile, parameter_id, scene["scene_hash"])
    if full_lineage < 0 or lesion_lineage < 0: return {"ok":false,"error":"lineage key not established"}
    return {"ok":true,"frames":FRAMES}

func _core_observation(row: Dictionary) -> Dictionary:
    return {
        "position": Vector2(float(row["x"]),float(row["y"])),
        "signature": row["signature"].duplicate(),
        "efference_copy": float(row["efference"]), "action_outcome_match": float(row["outcome"]),
        "proprioceptive_closure": float(row["proprio"]), "temporal_match": float(row["temporal"]),
        "cross_modal_coherence": float(row["crossmodal"]), "persistence": float(row["persistence"]),
        "physical_predictability": float(row["physical"]), "autonomous_dynamics": float(row["autonomy"]),
        "goal_directedness": float(row["goal"]), "response_contingency": float(row["response"]),
        "tool_coupling": float(row["tool"]), "interoceptive_closure": float(row["intero"]),
        "homeostatic_coupling": float(row["homeo"]), "action_history_match": float(row["history"]),
        "reply_emission": float(row["response"])
    }

func _generate_scene(seed: int, profile: String) -> Dictionary:
    var rng = RandomNumberGenerator.new(); rng.seed = seed * 1000003 + (PROFILES.find(profile)+1) * 7919 + 20260901
    var frames: Array = []; var canonical = "%d|%s|%s|" % [seed,profile,SCENARIO]
    var noise = _profile_noise(profile)
    for frame in range(FRAMES):
        var stage = mini(4, int(frame / 42))
        var cp = CHANGE_POINTS.has(frame)
        var action = clampf(0.66 + 0.25 * sin(0.37 * frame + 0.11 * seed), 0.22, 0.98)
        var anchor: Vector2 = ANCHORS[stage]
        var pos = Vector2(anchor.x + 27.0*sin(0.18*frame+0.30*stage), anchor.y + 22.0*cos(0.15*frame+0.17*seed))
        var ambiguous = stage == 4 or (stage > 0 and frame < stage*42 + 24)
        var obs: Array = []
        obs.append(_self_obs(rng,frame,stage,pos,action,noise,ambiguous,profile))
        obs.append(_object_obs(rng,frame,noise))
        obs.append(_agent_obs(rng,frame,seed,noise))
        var lure_present = (stage>0 and stage<4 and frame < stage*42+20) or (stage==4 and frame < PROBE_START+48)
        if lure_present: obs.append(_lure_obs(rng,frame,stage,action,noise,profile))
        _shuffle(obs,rng)
        var fd={"frame":frame,"time_s":frame*DT,"action":action,"change_point":cp,"observations":obs}
        frames.append(fd)
        canonical += _canonical_frame(fd)
    var sh = canonical.sha256_text()
    return {"frames":frames,"scene_hash":sh}

func _self_obs(rng, frame:int, stage:int, pos:Vector2, action:float, noise:float, ambiguous:bool, profile:String) -> Dictionary:
    var sig = _noisy_signature(SIGNATURES[stage],rng,noise*0.65,profile)
    var eff = 0.94; var out = 0.93; var proprio=0.93; var temporal=0.94; var cross=0.91; var intero=0.93; var homeo=0.91; var history=0.92
    if ambiguous:
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
    var rel = _profile_reliability(profile)
    return _row("self",pos,sig,rng,noise,eff*rel,out*rel,proprio*rel,temporal,cross,0.96,0.72,0.03,0.04,0.03,0.02,intero*rel,homeo*rel,history*rel,true,false,"SELF")

func _lure_obs(rng, frame:int, stage:int, action:float, noise:float, profile:String) -> Dictionary:
    var old_stage = maxi(0,stage-1); var anchor: Vector2=ANCHORS[old_stage]
    var pos = Vector2(anchor.x + 8*sin(0.22*frame), anchor.y + 7*cos(0.19*frame))
    var sig = _noisy_signature(SIGNATURES[old_stage],rng,noise*0.45,profile)
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

func _n(x:float,rng,noise:float)->float: return clampf(x+rng.randfn(0,noise),0.0,1.0)
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
func _noisy_signature(base:Array,rng,noise:float,profile:String)->Array:
    var off = 0.015 * float(PROFILES.find(profile)) if PROFILES.has(profile) else 0.0
    var out:Array=[]
    for i in range(base.size()): out.append(clampf(float(base[i])+off*(1 if i%2==0 else -1)+rng.randfn(0,noise),0.0,1.0))
    return out
func _shuffle(a:Array,rng)->void:
    for i in range(a.size()-1,0,-1):
        var j: int = int(rng.randi_range(0, i)); var t: Variant = a[i]; a[i] = a[j]; a[j] = t
func _canonical_frame(fd:Dictionary)->String:
    var s="%d|%.6f|%d|" % [int(fd["frame"]),float(fd["action"]),1 if fd["change_point"] else 0]
    for r_v in fd["observations"]:
        var r:Dictionary=r_v; s += "%s|%.5f|%.5f|" % [r["observation_id"],r["x"],r["y"]]
        for x in r["signature"]: s += "%.5f," % float(x)
        for k in ["efference","outcome","motor","proprio","temporal","crossmodal","persistence","physical","autonomy","goal","response","tool","intero","homeo","history"]: s += "|%.5f" % float(r[k])
    return s+";"

func _write_stream_header(f)->void:
    f.store_csv_line(PackedStringArray(["run_id","seed","profile","scenario","frame","time_s","observation_id","x","y","appearance","appearance_0","appearance_1","appearance_2","appearance_3","efference","outcome","motor","proprio","temporal","crossmodal","persistence","physical","autonomy","goal","response","tool","intero","homeo","history","is_true_lineage","is_lure","truth_entity_id","scene_hash","change_point"]))
func _write_tracking_header(f)->void:
    f.store_csv_line(PackedStringArray(["run_id","seed","profile","scenario","parameter_id","condition","frame","time_s","scene_hash","lineage_id","true_self_entity_id","lure_entity_id","lure_present"]))
func _write_scene_stream(f,scene:Dictionary,seed:int,profile:String)->void:
    var run_id="%d_%s_%s" % [seed,profile,SCENARIO]
    for fd_v in scene["frames"]:
        var fd:Dictionary=fd_v
        for r_v in fd["observations"]:
            var r:Dictionary=r_v; var sig:Array=r["signature"]
            f.store_csv_line(PackedStringArray([run_id,str(seed),profile,SCENARIO,str(fd["frame"]),str(fd["time_s"]),str(r["observation_id"]),str(r["x"]),str(r["y"]),str(r["appearance"]),str(sig[0]),str(sig[1]),str(sig[2]),str(sig[3]),str(r["efference"]),str(r["outcome"]),str(r["motor"]),str(r["proprio"]),str(r["temporal"]),str(r["crossmodal"]),str(r["persistence"]),str(r["physical"]),str(r["autonomy"]),str(r["goal"]),str(r["response"]),str(r["tool"]),str(r["intero"]),str(r["homeo"]),str(r["history"]),"1" if r["is_true_lineage"] else "0","1" if r["is_lure"] else "0",str(r["truth_entity_id"]),str(scene["scene_hash"]),"1" if fd["change_point"] else "0"]))
func _write_tracking_frame(f,fd:Dictionary,assignments:Array,condition:String,lineage_id:int,seed:int,profile:String,parameter_id:String,scene_hash:String)->void:
    var self_id=-1; var lure_id=-1; var lure_present=0
    for i in range(fd["observations"].size()):
        var r:Dictionary=fd["observations"][i]
        if bool(r["is_true_lineage"]): self_id=int(assignments[i])
        if bool(r["is_lure"]): lure_id=int(assignments[i]); lure_present=1
    var run_id="%d_%s_%s" % [seed,profile,SCENARIO]
    f.store_csv_line(PackedStringArray([run_id,str(seed),profile,SCENARIO,parameter_id,condition,str(fd["frame"]),str(fd["time_s"]),scene_hash,str(lineage_id),str(self_id),str(lure_id),str(lure_present)]))
func _ensure_parent(path:String)->void: DirAccess.make_dir_recursive_absolute(path.get_base_dir())
