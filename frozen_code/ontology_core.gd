extends RefCounted

# Canonical executable implementation used by the fresh replication package.
# The scientific mechanism follows the equations documented in paper/pre_rerun_reference/supplementary.tex.

const ROLES: Array[String] = ["Self", "Tool", "Object", "Agent"]
const INF_COST: float = 1000000.0

var ablation: String = "full"
var rng := RandomNumberGenerator.new()
var entities: Dictionary = {}
var next_entity_id: int = 1
var sim_time: float = 0.0
var last_action_strength: float = 0.0
var change_point_seen: bool = false
var frame_index: int = 0
var last_frame_assignments: Array[int] = []
var persistent_self_id: int = -1
var persistent_self_confidence: float = 0.0

func reset(new_ablation: String, seed: int) -> void:
	ablation = new_ablation
	rng.seed = seed
	entities.clear()
	next_entity_id = 1
	sim_time = 0.0
	last_action_strength = 0.0
	change_point_seen = false
	frame_index = 0
	last_frame_assignments.clear()
	persistent_self_id = -1
	persistent_self_confidence = 0.0

func notify_change_point() -> void:
	change_point_seen = true
	persistent_self_id = -1
	persistent_self_confidence = 0.0
	for entity_id in entities.keys():
		var entity: Dictionary = entities[entity_id]
		entity["pre_change_signature"] = entity.get("signature", []).duplicate()
		entity["pre_change_role_features"] = _role_feature_vector_from_entity(entity)
		var anchor_score: float = _entity_self_anchor_strength(entity)
		entity["self_anchor_strength"] = anchor_score
		if anchor_score > persistent_self_confidence:
			persistent_self_confidence = anchor_score
			persistent_self_id = int(entity_id)
		entities[entity_id] = entity
	if ablation == "no_change_point_transfer":
		entities.clear()
		next_entity_id = 1
		persistent_self_id = -1
		persistent_self_confidence = 0.0

func register_action(action_strength: float) -> void:
	last_action_strength = clampf(action_strength, 0.0, 1.0)

func observe(observation: Dictionary, dt: float) -> int:
	var ids: Array[int] = observe_frame([observation], dt)
	return ids[0] if not ids.is_empty() else -1

func observe_frame(observations: Array, dt: float) -> Array[int]:
	sim_time += maxf(0.0, dt)
	frame_index += 1
	last_frame_assignments = _associate_frame(observations)
	return last_frame_assignments.duplicate()

func get_entity_snapshot(entity_id: int) -> Dictionary:
	if not entities.has(entity_id):
		return {}
	var entity: Dictionary = entities[entity_id]
	return entity.duplicate(true)

func get_role_posterior(entity_id: int, role: String) -> float:
	if not entities.has(entity_id):
		return 0.0
	var entity: Dictionary = entities[entity_id]
	var post: Dictionary = _role_posteriors(entity)
	return float(post.get(role, 0.0))

func get_best_role(entity_id: int) -> String:
	if not entities.has(entity_id):
		return ""
	var entity: Dictionary = entities[entity_id]
	var post := _role_posteriors(entity)
	var best := ""
	var score := -INF_COST
	for role in ROLES:
		var v := float(post.get(role, 0.0))
		if v > score:
			score = v
			best = role
	return best

func _associate_frame(observations: Array) -> Array[int]:
	var result: Array[int] = []
	if observations.is_empty():
		return result
	var active_ids: Array[int] = []
	for raw_id in entities.keys():
		var entity: Dictionary = entities[raw_id]
		if sim_time - float(entity.get("last_seen", -999.0)) <= 8.0:
			active_ids.append(int(raw_id))
	active_ids.sort()
	if active_ids.is_empty():
		for obs_v in observations:
			var observation: Dictionary = obs_v
			var new_id := _create_entity_id(observation)
			result.append(new_id)
		return result

	var row_count := observations.size()
	var existing_count := active_ids.size()
	var col_count := existing_count + row_count
	var matrix: Array = []
	for i in range(row_count):
		var row: Array[float] = []
		var observation: Dictionary = observations[i]
		for entity_id in active_ids:
			var candidate: Dictionary = entities[entity_id]
			row.append(_association_cost(candidate, observation))
		for _dummy in range(row_count):
			row.append(_new_entity_cost(observation))
		matrix.append(row)
	var cols: Array[int] = _hungarian(matrix)
	for i in range(row_count):
		var observation: Dictionary = observations[i]
		var col := cols[i]
		if col >= 0 and col < existing_count and float(matrix[i][col]) <= _association_threshold():
			var entity_id := active_ids[col]
			_update_entity(entity_id, observation)
			result.append(entity_id)
		else:
			result.append(_create_entity_id(observation))
	return result

func _association_cost(entity: Dictionary, observation: Dictionary) -> float:
	var age: float = maxf(0.0, sim_time - float(entity.get("last_seen", sim_time)))
	var entity_position: Vector2 = entity.get("position", Vector2.ZERO)
	var predicted_position: Vector2 = entity_position
	if ablation != "no_temporal_continuity":
		var entity_velocity: Vector2 = entity.get("velocity", Vector2.ZERO)
		predicted_position += entity_velocity * age
	var new_position: Vector2 = observation.get("position", Vector2.ZERO)
	var position_cost: float = predicted_position.distance_to(new_position) / 190.0
	var signature_cost: float = _array_distance(entity.get("signature", []), observation.get("signature", []))
	var dynamic_cost: float = _array_distance(_role_feature_vector_from_entity(entity), _role_feature_vector_from_observation(observation))
	var age_penalty: float = minf(0.28, age * 0.045)
	var signature_weight: float = 0.43
	var position_weight: float = 0.37
	var dynamic_weight: float = 0.20
	if ablation == "no_temporal_continuity":
		signature_weight = 0.62
		position_weight = 0.16
		dynamic_weight = 0.22
	var cost: float = signature_weight * signature_cost + position_weight * position_cost + dynamic_weight * dynamic_cost + age_penalty
	if change_point_seen and ablation != "no_change_point_transfer":
		signature_weight = 0.20
		position_weight = 0.29
		dynamic_weight = 0.51
		age_penalty *= 0.55
		cost = signature_weight * signature_cost + position_weight * position_cost + dynamic_weight * dynamic_cost + age_penalty
		if ablation != "no_persistent_self" and persistent_self_id >= 0:
			var observation_self: float = _observation_self_anchor_strength(observation)
			var entity_anchor: float = float(entity.get("self_anchor_strength", _entity_self_anchor_strength(entity)))
			if observation_self > 0.70 and int(entity.get("id", -1)) == persistent_self_id:
				cost = 0.015 + 0.06 * (1.0 - observation_self) + 0.04 * (1.0 - entity_anchor)
			elif observation_self > 0.70:
				cost += 2.0 * observation_self
			elif int(entity.get("id", -1)) == persistent_self_id:
				cost += 0.45 * (1.0 - observation_self)
	return maxf(0.0, cost)

func _association_threshold() -> float:
	if change_point_seen and ablation != "no_change_point_transfer":
		return 0.82
	return 0.66

func _new_entity_cost(observation: Dictionary) -> float:
	if change_point_seen and ablation != "no_change_point_transfer":
		if ablation != "no_persistent_self" and persistent_self_id >= 0 and _observation_self_anchor_strength(observation) > 0.62:
			return 1.08
		return 0.79
	return 0.64

func _create_entity_id(observation: Dictionary) -> int:
	var entity_id := next_entity_id
	next_entity_id += 1
	var pos: Vector2 = observation.get("position", Vector2.ZERO)
	var sig: Array = observation.get("signature", []).duplicate()
	var entity: Dictionary = {
		"id": entity_id,
		"position": pos,
		"velocity": Vector2.ZERO,
		"signature": sig,
		"last_seen": sim_time,
		"seen_count": 1,
		"motor": _motor_authorship(observation),
		"proprio": float(observation.get("proprioceptive_closure", 0.0)),
		"temporal": float(observation.get("temporal_match", 0.0)),
		"crossmodal": float(observation.get("cross_modal_coherence", 0.0)),
		"persistence": float(observation.get("persistence", 0.0)),
		"physical": float(observation.get("physical_predictability", 0.0)),
		"autonomous": float(observation.get("autonomous_dynamics", 0.0)),
		"goal": float(observation.get("goal_directedness", 0.0)),
		"response": float(observation.get("response_contingency", 0.0)),
		"tool_coupling": float(observation.get("tool_coupling", 0.0)),
		"interoceptive": float(observation.get("interoceptive_closure", 0.0)),
		"homeostatic": float(observation.get("homeostatic_coupling", 0.0)),
		"action_history": float(observation.get("action_history_match", 0.0)),
		"self_anchor_strength": 0.0,
		"reply_emission": float(observation.get("reply_emission", 0.0))
	}
	entity["self_anchor_strength"] = _entity_self_anchor_strength(entity)
	entities[entity_id] = entity
	return entity_id

func _update_entity(entity_id: int, observation: Dictionary) -> void:
	var entity: Dictionary = entities[entity_id]
	var old_position: Vector2 = entity.get("position", Vector2.ZERO)
	var new_position: Vector2 = observation.get("position", Vector2.ZERO)
	var elapsed: float = maxf(0.0001, sim_time - float(entity.get("last_seen", sim_time)))
	var observed_velocity: Vector2 = (new_position - old_position) / elapsed
	var old_velocity: Vector2 = entity.get("velocity", Vector2.ZERO)
	entity["velocity"] = old_velocity.lerp(observed_velocity, 0.24)
	entity["position"] = old_position.lerp(new_position, 0.48)
	var old_sig: Array = entity.get("signature", [])
	var new_sig: Array = observation.get("signature", [])
	var sig_alpha: float = 0.10 if not change_point_seen else 0.06
	entity["signature"] = _lerp_array(old_sig, new_sig, sig_alpha)
	var alpha: float = 0.12
	entity["motor"] = lerpf(float(entity.get("motor", 0.0)), _motor_authorship(observation), alpha)
	entity["proprio"] = lerpf(float(entity.get("proprio", 0.0)), float(observation.get("proprioceptive_closure", 0.0)), alpha)
	entity["temporal"] = lerpf(float(entity.get("temporal", 0.0)), float(observation.get("temporal_match", 0.0)), alpha)
	entity["crossmodal"] = lerpf(float(entity.get("crossmodal", 0.0)), float(observation.get("cross_modal_coherence", 0.0)), alpha)
	entity["persistence"] = lerpf(float(entity.get("persistence", 0.0)), float(observation.get("persistence", 0.0)), alpha)
	entity["physical"] = lerpf(float(entity.get("physical", 0.0)), float(observation.get("physical_predictability", 0.0)), alpha)
	entity["autonomous"] = lerpf(float(entity.get("autonomous", 0.0)), float(observation.get("autonomous_dynamics", 0.0)), alpha)
	entity["goal"] = lerpf(float(entity.get("goal", 0.0)), float(observation.get("goal_directedness", 0.0)), alpha)
	entity["response"] = lerpf(float(entity.get("response", 0.0)), float(observation.get("response_contingency", 0.0)), alpha)
	entity["tool_coupling"] = lerpf(float(entity.get("tool_coupling", 0.0)), float(observation.get("tool_coupling", 0.0)), alpha)
	entity["interoceptive"] = lerpf(float(entity.get("interoceptive", 0.08)), float(observation.get("interoceptive_closure", 0.0)), alpha)
	entity["homeostatic"] = lerpf(float(entity.get("homeostatic", 0.08)), float(observation.get("homeostatic_coupling", 0.0)), alpha)
	entity["action_history"] = lerpf(float(entity.get("action_history", 0.08)), float(observation.get("action_history_match", 0.0)), alpha)
	entity["reply_emission"] = float(observation.get("reply_emission", 0.0))
	entity["last_seen"] = sim_time
	entity["seen_count"] = int(entity.get("seen_count", 0)) + 1
	entity["self_anchor_strength"] = _entity_self_anchor_strength(entity)
	entities[entity_id] = entity

func _motor_authorship(observation: Dictionary) -> float:
	var e := float(observation.get("efference_copy", 0.0))
	if ablation == "no_efference" or ablation == "no_motor_authorship_input":
		e = 0.0
	var y := float(observation.get("action_outcome_match", 0.0))
	return sqrt(maxf(0.0, e * y))

func _role_feature_vector_from_observation(observation: Dictionary) -> Array:
	return [
		_motor_authorship(observation),
		float(observation.get("proprioceptive_closure", 0.0)),
		float(observation.get("temporal_match", 0.0)),
		float(observation.get("cross_modal_coherence", 0.0)),
		float(observation.get("persistence", 0.0)),
		float(observation.get("physical_predictability", 0.0)),
		float(observation.get("autonomous_dynamics", 0.0)),
		float(observation.get("goal_directedness", 0.0)),
		float(observation.get("response_contingency", 0.0)),
		float(observation.get("tool_coupling", 0.0)),
		float(observation.get("interoceptive_closure", 0.0)),
		float(observation.get("homeostatic_coupling", 0.0)),
		float(observation.get("action_history_match", 0.0))
	]

func _role_feature_vector_from_entity(entity: Dictionary) -> Array:
	return [
		float(entity.get("motor", 0.0)), float(entity.get("proprio", 0.0)),
		float(entity.get("temporal", 0.0)), float(entity.get("crossmodal", 0.0)),
		float(entity.get("persistence", 0.0)), float(entity.get("physical", 0.0)),
		float(entity.get("autonomous", 0.0)), float(entity.get("goal", 0.0)),
		float(entity.get("response", 0.0)), float(entity.get("tool_coupling", 0.0)),
		float(entity.get("interoceptive", 0.0)), float(entity.get("homeostatic", 0.0)),
		float(entity.get("action_history", 0.0))
	]

func _observation_self_anchor_strength(observation: Dictionary) -> float:
	var m := _motor_authorship(observation)
	var p := float(observation.get("proprioceptive_closure", 0.0))
	var i := float(observation.get("interoceptive_closure", 0.0))
	var h := float(observation.get("homeostatic_coupling", 0.0))
	var a := float(observation.get("action_history_match", 0.0))
	return clampf(0.26*m + 0.18*p + 0.24*i + 0.18*h + 0.14*a, 0.0, 1.0)

func _entity_self_anchor_strength(entity: Dictionary) -> float:
	var post := _role_posteriors(entity)
	return clampf(
		0.26*float(post.get("Self", 0.0)) +
		0.18*float(entity.get("motor", 0.0)) +
		0.14*float(entity.get("proprio", 0.0)) +
		0.18*float(entity.get("interoceptive", 0.0)) +
		0.14*float(entity.get("homeostatic", 0.0)) +
		0.10*float(entity.get("action_history", 0.0)), 0.0, 1.0)

func _role_posteriors(entity: Dictionary) -> Dictionary:
	var m := float(entity.get("motor", 0.0))
	var p := float(entity.get("proprio", 0.0))
	var tau := float(entity.get("temporal", 0.0))
	var chi := float(entity.get("crossmodal", 0.0))
	var r := float(entity.get("persistence", 0.0))
	var f := float(entity.get("physical", 0.0))
	var u := float(entity.get("autonomous", 0.0))
	var g := float(entity.get("goal", 0.0))
	var q := float(entity.get("response", 0.0))
	var l := float(entity.get("tool_coupling", 0.0))
	var i := float(entity.get("interoceptive", 0.0))
	var h := float(entity.get("homeostatic", 0.0))
	var a := float(entity.get("action_history", 0.0))
	var s := float(entity.get("reply_emission", 0.0))
	var e_self := 2.70*m + 1.90*p + 0.90*tau + 0.55*chi + 0.35*r + 1.55*i + 1.25*h + 0.95*a - 1.35*u - 0.75*q - 1.75*l
	var e_tool := 2.65*m - 1.35*p + 1.15*tau + 0.55*chi + 0.55*r + 2.25*l - 0.80*u
	var e_object := 1.70*r + 1.65*f + 0.50*chi - 1.55*m - 1.20*u - 0.65*g - 0.45*q - 0.75*l
	var e_agent := 1.00*r + 1.45*u + 1.45*g + 1.35*q + 1.45*s + 0.35*chi - 1.00*m
	var energies := [e_self, e_tool, e_object, e_agent]
	var max_e: float = energies.max()
	var exps: Array[float] = []
	var total := 0.0
	for e in energies:
		var z := exp(float(e) - max_e)
		exps.append(z)
		total += z
	var out := {}
	for idx in range(ROLES.size()):
		out[ROLES[idx]] = exps[idx] / maxf(total, 1e-12)
	return out

func _array_distance(a: Array, b: Array) -> float:
	if a.is_empty() or b.is_empty() or a.size() != b.size():
		return 1.0
	var s := 0.0
	for i in range(a.size()):
		var d := float(a[i]) - float(b[i])
		s += d*d
	return sqrt(s / float(a.size()))

func _lerp_array(a: Array, b: Array, alpha: float) -> Array:
	if a.size() != b.size():
		return b.duplicate()
	var out: Array = []
	for i in range(a.size()):
		out.append(lerpf(float(a[i]), float(b[i]), alpha))
	return out

# Rectangular Hungarian algorithm for rows <= columns.
func _hungarian(cost: Array) -> Array[int]:
	var n := cost.size()
	var first_row: Array = cost[0]
	var m := first_row.size()
	var u: Array[float] = []
	var v: Array[float] = []
	var p: Array[int] = []
	var way: Array[int] = []
	u.resize(n + 1); u.fill(0.0)
	v.resize(m + 1); v.fill(0.0)
	p.resize(m + 1); p.fill(0)
	way.resize(m + 1); way.fill(0)
	for i in range(1, n + 1):
		p[0] = i
		var j0 := 0
		var minv: Array[float] = []
		var used: Array[bool] = []
		minv.resize(m + 1); minv.fill(INF_COST)
		used.resize(m + 1); used.fill(false)
		while true:
			used[j0] = true
			var i0 := p[j0]
			var delta := INF_COST
			var j1 := 0
			for j in range(1, m + 1):
				if not used[j]:
					var cur := float(cost[i0 - 1][j - 1]) - u[i0] - v[j]
					if cur < minv[j]:
						minv[j] = cur
						way[j] = j0
					if minv[j] < delta:
						delta = minv[j]
						j1 = j
			for j in range(0, m + 1):
				if used[j]:
					u[p[j]] += delta
					v[j] -= delta
				else:
					minv[j] -= delta
			j0 = j1
			if p[j0] == 0:
				break
		while true:
			var j1 := way[j0]
			p[j0] = p[j1]
			j0 = j1
			if j0 == 0:
				break
	var ans: Array[int] = []
	ans.resize(n); ans.fill(-1)
	for j in range(1, m + 1):
		if p[j] > 0 and p[j] <= n:
			ans[p[j] - 1] = j - 1
	return ans
