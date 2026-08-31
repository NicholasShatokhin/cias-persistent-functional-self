class_name OntologyCore
extends RefCounted

const ROLES: Array[String] = ["Self", "Tool", "Object", "Agent"]
const INF_COST: float = 1000000.0

var ablation: String = "full"
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
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
	var result: Array[int] = observe_frame([observation], dt)
	return result[0] if not result.is_empty() else -1

func observe_frame(observations: Array, dt: float) -> Array[int]:
	sim_time += dt
	frame_index += 1
	var clean_observations: Array = []
	for observation in observations:
		var clean: Dictionary = observation.duplicate(true)
		clean.erase("truth_id")
		clean.erase("truth_role")
		clean_observations.append(clean)

	var assignments: Array[int] = []
	if ablation == "no_entity_clustering":
		for _observation in clean_observations:
			assignments.append(_create_entity_id())
	else:
		assignments = _associate_frame(clean_observations)

	for index in range(clean_observations.size()):
		var entity_id: int = assignments[index]
		var clean: Dictionary = clean_observations[index]
		if not entities.has(entity_id):
			entities[entity_id] = _new_entity(entity_id, clean)
		_update_entity(entity_id, clean, dt)

	for entity_id in assignments:
		var entity: Dictionary = entities[entity_id]
		entity["posterior"] = _role_posterior(entity)
		entity["role"] = _argmax_role(entity["posterior"])
		entity["last_seen"] = sim_time
		entity["last_frame"] = frame_index
		entities[entity_id] = entity

	last_frame_assignments = assignments.duplicate()
	return assignments

func register_social_trial(signal_evidence: Dictionary, reply: bool) -> void:
	if ablation == "no_agent_model" or ablation == "reactive_baseline":
		return
	var responder_id: int = _select_responder_entity(reply)
	if responder_id < 0 or not entities.has(responder_id):
		return
	var q_self: float = infer_self_signal_probability(signal_evidence)
	var entity: Dictionary = entities[responder_id]
	entity["social_self_weight"] = float(entity.get("social_self_weight", 0.0)) + q_self
	entity["social_self_reply"] = float(entity.get("social_self_reply", 0.0)) + q_self * (1.0 if reply else 0.0)
	entity["social_other_weight"] = float(entity.get("social_other_weight", 0.0)) + (1.0 - q_self)
	entity["social_other_reply"] = float(entity.get("social_other_reply", 0.0)) + (1.0 - q_self) * (1.0 if reply else 0.0)
	entity["social_ace"] = _entity_social_ace(entity)
	entities[responder_id] = entity

func infer_self_signal_probability(signal_evidence: Dictionary) -> float:
	if ablation == "reactive_baseline":
		return 0.5
	var present: float = float(signal_evidence.get("signal_present", 0.0))
	var efference: float = float(signal_evidence.get("efference_copy", 0.0))
	var match_value: float = float(signal_evidence.get("action_outcome_match", 0.0))
	var external: float = float(signal_evidence.get("external_source_activity", 0.0))
	var temporal: float = float(signal_evidence.get("temporal_match", 0.0))
	if ablation == "no_efference":
		efference *= 0.12
	var score: float = 0.0
	if ablation == "correlation_only":
		score = 4.2 * temporal + 0.9 * present - 2.2 * external - 2.0
	else:
		score = 4.8 * efference * match_value + 0.8 * present + 0.6 * temporal - 3.0 * external - 2.0
	return 1.0 / (1.0 + exp(-score))

func social_prediction(signal_evidence: Dictionary) -> float:
	if ablation == "no_agent_model" or ablation == "reactive_baseline":
		return 0.5
	var responder_id: int = best_social_entity_id()
	if responder_id < 0 or not entities.has(responder_id):
		return 0.5
	var entity: Dictionary = entities[responder_id]
	var q_self: float = infer_self_signal_probability(signal_evidence)
	var p_self: float = _beta_mean(float(entity.get("social_self_reply", 0.0)), float(entity.get("social_self_weight", 0.0)))
	var p_other: float = _beta_mean(float(entity.get("social_other_reply", 0.0)), float(entity.get("social_other_weight", 0.0)))
	return clampf(q_self * p_self + (1.0 - q_self) * p_other, 0.0, 1.0)

func social_ace() -> float:
	if ablation == "no_agent_model" or ablation == "reactive_baseline":
		return 0.0
	var responder_id: int = best_social_entity_id()
	if responder_id < 0 or not entities.has(responder_id):
		return 0.0
	return _entity_social_ace(entities[responder_id])

func best_social_entity_id() -> int:
	var best_id: int = -1
	var best_score: float = -INF_COST
	for entity_id in entities.keys():
		var entity: Dictionary = entities[entity_id]
		var age: float = sim_time - float(entity.get("last_seen", sim_time))
		if age > 6.0:
			continue
		var posterior: Dictionary = entity.get("posterior", {})
		var score: float = (
			0.34 * float(posterior.get("Agent", 0.0))
			+ 0.24 * float(entity.get("autonomy", 0.0))
			+ 0.18 * float(entity.get("goal", 0.0))
			+ 0.14 * float(entity.get("response", 0.0))
			+ 0.10 * abs(float(entity.get("social_ace", 0.0)))
		)
		if score > best_score:
			best_score = score
			best_id = int(entity_id)
	return best_id

func get_entity(entity_id: int) -> Dictionary:
	return entities.get(entity_id, {})

func active_entity_count(max_age: float = 5.0) -> int:
	var count: int = 0
	for entity_id in entities.keys():
		var entity: Dictionary = entities[entity_id]
		if sim_time - float(entity.get("last_seen", sim_time)) <= max_age:
			count += 1
	return count

func entity_rows() -> Array:
	var rows: Array = []
	for entity_id in entities.keys():
		var entity: Dictionary = entities[entity_id]
		if sim_time - float(entity.get("last_seen", sim_time)) <= 8.0:
			rows.append(entity)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("salience", 0.0)) > float(b.get("salience", 0.0))
	)
	return rows

func _associate_frame(observations: Array) -> Array[int]:
	var active_ids: Array[int] = []
	for entity_id in entities.keys():
		var entity: Dictionary = entities[entity_id]
		if sim_time - float(entity.get("last_seen", sim_time)) <= 8.0:
			active_ids.append(int(entity_id))
	active_ids.sort()

	if active_ids.is_empty():
		var initial: Array[int] = []
		for _observation in observations:
			initial.append(_create_entity_id())
		return initial

	var row_count: int = observations.size()
	var existing_count: int = active_ids.size()
	var column_count: int = existing_count + row_count
	var matrix: Array = []
	for observation in observations:
		var row: Array[float] = []
		for entity_id in active_ids:
			row.append(_association_cost(observation, entities[entity_id]))
		var dummy_cost: float = _new_entity_cost(observation)
		for dummy_index in range(row_count):
			row.append(dummy_cost + 0.0001 * float(dummy_index))
		matrix.append(row)

	var columns: Array[int] = _hungarian(matrix)
	var assignments: Array[int] = []
	for row_index in range(row_count):
		var column: int = columns[row_index]
		if column >= 0 and column < existing_count:
			var candidate_id: int = active_ids[column]
			var candidate_cost: float = float(matrix[row_index][column])
			if candidate_cost <= _association_threshold():
				assignments.append(candidate_id)
				continue
		assignments.append(_create_entity_id())
	return assignments

func _association_cost(observation: Dictionary, entity: Dictionary) -> float:
	var age: float = maxf(0.0, sim_time - float(entity.get("last_seen", sim_time)))
	var observed_position: Vector2 = observation.get("position", Vector2.ZERO)
	var entity_position: Vector2 = entity.get("position", observed_position)
	var predicted_position: Vector2 = entity_position
	if ablation != "no_temporal_continuity":
		predicted_position += Vector2(entity.get("velocity", Vector2.ZERO)) * age
	var position_cost: float = observed_position.distance_to(predicted_position) / 190.0
	var signature_cost: float = _array_distance(observation.get("signature", []), entity.get("signature", []))
	var dynamic_cost: float = _array_distance(_role_feature_vector_from_observation(observation), _role_feature_vector_from_entity(entity))
	var age_penalty: float = min(0.28, age * 0.045)

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
				# A cross-embodiment Self anchor is defined by continued interoception,
				# homeostatic closure and efference, not by old position or appearance.
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

func _hungarian(cost: Array) -> Array[int]:
	var n: int = cost.size()
	if n == 0:
		return []
	var m: int = cost[0].size()
	var u: Array[float] = []
	var v: Array[float] = []
	var p: Array[int] = []
	var way: Array[int] = []
	u.resize(n + 1)
	v.resize(m + 1)
	p.resize(m + 1)
	way.resize(m + 1)
	u.fill(0.0)
	v.fill(0.0)
	p.fill(0)
	way.fill(0)
	for i in range(1, n + 1):
		p[0] = i
		var j0: int = 0
		var minv: Array[float] = []
		var used: Array[bool] = []
		minv.resize(m + 1)
		used.resize(m + 1)
		minv.fill(INF_COST)
		used.fill(false)
		while true:
			used[j0] = true
			var i0: int = p[j0]
			var delta: float = INF_COST
			var j1: int = 0
			for j in range(1, m + 1):
				if used[j]:
					continue
				var current: float = float(cost[i0 - 1][j - 1]) - u[i0] - v[j]
				if current < minv[j]:
					minv[j] = current
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
			var previous_j: int = way[j0]
			p[j0] = p[previous_j]
			j0 = previous_j
			if j0 == 0:
				break
	var assignment: Array[int] = []
	assignment.resize(n)
	assignment.fill(-1)
	for j in range(1, m + 1):
		if p[j] > 0 and p[j] <= n:
			assignment[p[j] - 1] = j - 1
	return assignment

func _create_entity_id() -> int:
	var created_id: int = next_entity_id
	next_entity_id += 1
	return created_id

func _new_entity(entity_id: int, observation: Dictionary) -> Dictionary:
	return {
		"id": entity_id,
		"signature": observation.get("signature", []).duplicate(),
		"position": observation.get("position", Vector2.ZERO),
		"velocity": Vector2.ZERO,
		"motor": 0.18,
		"proprio": 0.18,
		"temporal": 0.18,
		"crossmodal": 0.18,
		"persistence": 0.18,
		"physical": 0.18,
		"autonomy": 0.18,
		"goal": 0.18,
		"response": 0.18,
		"tool_coupling": 0.18,
		"interoceptive": 0.08,
		"homeostatic": 0.08,
		"action_history": 0.08,
		"self_anchor_strength": 0.0,
		"reply_emission": 0.0,
		"social_self_weight": 0.0,
		"social_self_reply": 0.0,
		"social_other_weight": 0.0,
		"social_other_reply": 0.0,
		"social_ace": 0.0,
		"novelty": 1.0,
		"seen": 0,
		"last_seen": sim_time,
		"last_frame": frame_index,
		"posterior": {"Self": 0.25, "Tool": 0.25, "Object": 0.25, "Agent": 0.25},
		"role": "Object",
		"salience": 0.5
	}

func _update_entity(entity_id: int, observation: Dictionary, dt: float) -> void:
	var entity: Dictionary = entities[entity_id]
	var alpha: float = 0.12
	var old_position: Vector2 = entity.get("position", Vector2.ZERO)
	var new_position: Vector2 = observation.get("position", old_position)
	var elapsed: float = maxf(dt, sim_time - float(entity.get("last_seen", sim_time - dt)))
	var observed_velocity: Vector2 = (new_position - old_position) / maxf(0.001, elapsed)
	entity["velocity"] = Vector2(entity.get("velocity", Vector2.ZERO)).lerp(observed_velocity, 0.24)
	entity["position"] = old_position.lerp(new_position, 0.48)
	entity["signature"] = _lerp_array(entity.get("signature", []), observation.get("signature", []), 0.10 if not change_point_seen else 0.06)
	entity["seen"] = int(entity["seen"]) + 1
	entity["novelty"] = max(0.0, 1.0 - float(entity["seen"]) / 42.0)

	var efference: float = float(observation.get("efference_copy", observation.get("motor_contingency", 0.0)))
	var outcome_match: float = float(observation.get("action_outcome_match", observation.get("motor_contingency", 0.0)))
	var temporal_value: float = float(observation.get("temporal_match", 0.0))
	if ablation == "no_efference":
		efference *= 0.12
	var motor_value: float = sqrt(maxf(0.0, efference * outcome_match))
	if ablation == "correlation_only":
		motor_value = temporal_value
	if ablation == "reactive_baseline":
		motor_value = rng.randf()

	var proprio_value: float = float(observation.get("proprioceptive_closure", 0.0))
	if ablation == "no_efference":
		proprio_value *= 0.42
	if ablation == "reactive_baseline":
		proprio_value = rng.randf()

	entity["motor"] = lerpf(float(entity["motor"]), motor_value, alpha)
	entity["proprio"] = lerpf(float(entity["proprio"]), proprio_value, alpha)
	entity["temporal"] = lerpf(float(entity["temporal"]), temporal_value, alpha)
	entity["crossmodal"] = lerpf(float(entity["crossmodal"]), float(observation.get("crossmodal_coherence", 0.0)), alpha)
	entity["persistence"] = lerpf(float(entity["persistence"]), float(observation.get("persistence", 0.0)), alpha)
	entity["physical"] = lerpf(float(entity["physical"]), float(observation.get("physical_predictability", 0.0)), alpha)
	entity["autonomy"] = lerpf(float(entity["autonomy"]), float(observation.get("autonomous_dynamics", 0.0)), alpha)
	entity["goal"] = lerpf(float(entity["goal"]), float(observation.get("goal_directedness", 0.0)), alpha)
	entity["response"] = lerpf(float(entity["response"]), float(observation.get("response_contingency", 0.0)), alpha)
	entity["tool_coupling"] = lerpf(float(entity["tool_coupling"]), float(observation.get("tool_coupling", 0.0)), alpha)
	entity["interoceptive"] = lerpf(float(entity.get("interoceptive", 0.08)), float(observation.get("interoceptive_closure", 0.0)), alpha)
	entity["homeostatic"] = lerpf(float(entity.get("homeostatic", 0.08)), float(observation.get("homeostatic_coupling", 0.0)), alpha)
	entity["action_history"] = lerpf(float(entity.get("action_history", 0.08)), float(observation.get("action_history_match", 0.0)), alpha)
	entity["self_anchor_strength"] = _entity_self_anchor_strength(entity)
	entity["reply_emission"] = float(observation.get("reply_emission", 0.0))
	entity["salience"] = clampf(
		0.32 * float(entity["novelty"])
		+ 0.20 * float(entity["response"])
		+ 0.18 * float(entity["autonomy"])
		+ 0.18 * abs(float(entity["motor"]) - 0.5) * 2.0
		+ 0.12 * float(entity["tool_coupling"]),
		0.0,
		1.0
	)
	entities[entity_id] = entity

func _role_posterior(entity: Dictionary) -> Dictionary:
	if ablation == "reactive_baseline":
		var random_scores: Array[float] = [rng.randf(), rng.randf(), rng.randf(), rng.randf()]
		return _softmax_roles(random_scores)
	var m: float = float(entity["motor"])
	var p: float = float(entity["proprio"])
	var t: float = float(entity["temporal"])
	var x: float = float(entity["crossmodal"])
	var r: float = float(entity["persistence"])
	var f: float = float(entity["physical"])
	var u: float = float(entity["autonomy"])
	var g: float = float(entity["goal"])
	var q: float = float(entity["response"])
	var tool: float = float(entity["tool_coupling"])
	var intero: float = float(entity.get("interoceptive", 0.0))
	var homeo: float = float(entity.get("homeostatic", 0.0))
	var history: float = float(entity.get("action_history", 0.0))
	var social: float = clampf(0.5 + 0.5 * float(entity.get("social_ace", 0.0)), 0.0, 1.0)

	var self_energy: float = 2.70 * m + 1.90 * p + 0.90 * t + 0.55 * x + 0.35 * r + 1.55 * intero + 1.25 * homeo + 0.95 * history - 1.35 * u - 0.75 * q - 1.75 * tool
	var tool_energy: float = 2.65 * m - 1.35 * p + 1.15 * t + 0.55 * x + 0.55 * r + 2.25 * tool - 0.80 * u
	var object_energy: float = 1.70 * r + 1.65 * f + 0.50 * x - 1.55 * m - 1.20 * u - 0.65 * g - 0.45 * q - 0.75 * tool
	var agent_energy: float = 1.00 * r + 1.45 * u + 1.45 * g + 1.35 * q + 1.45 * social + 0.35 * x - 1.00 * m
	if ablation == "no_agent_model":
		agent_energy = -6.0
	if ablation == "no_tool_extension":
		tool_energy = -6.0
	return _softmax_roles([self_energy, tool_energy, object_energy, agent_energy])

func _select_responder_entity(reply: bool) -> int:
	var best_id: int = -1
	var best_score: float = -INF_COST
	for entity_id in entities.keys():
		var entity: Dictionary = entities[entity_id]
		var age: float = sim_time - float(entity.get("last_seen", sim_time))
		if age > 4.0:
			continue
		var score: float = (
			0.38 * float(entity.get("autonomy", 0.0))
			+ 0.28 * float(entity.get("goal", 0.0))
			+ 0.18 * float(entity.get("response", 0.0))
			+ 0.16 * float(entity.get("posterior", {}).get("Agent", 0.0))
		)
		if reply:
			score += 0.75 * float(entity.get("reply_emission", 0.0))
		if score > best_score:
			best_score = score
			best_id = int(entity_id)
	return best_id

func _entity_social_ace(entity: Dictionary) -> float:
	var p_self: float = _beta_mean(float(entity.get("social_self_reply", 0.0)), float(entity.get("social_self_weight", 0.0)))
	var p_other: float = _beta_mean(float(entity.get("social_other_reply", 0.0)), float(entity.get("social_other_weight", 0.0)))
	return p_self - p_other

func _beta_mean(success_weight: float, total_weight: float) -> float:
	return (success_weight + 1.0) / (total_weight + 2.0)

func _softmax_roles(energies: Array[float]) -> Dictionary:
	var maximum: float = energies.max()
	var exps: Array[float] = []
	var total: float = 0.0
	for value in energies:
		var e: float = exp(value - maximum)
		exps.append(e)
		total += e
	var result: Dictionary = {}
	for index in range(ROLES.size()):
		result[ROLES[index]] = exps[index] / maxf(total, 0.000001)
	return result

func _argmax_role(posterior: Dictionary) -> String:
	var best_role: String = ROLES[0]
	var best_value: float = -1.0
	for role in ROLES:
		var value: float = float(posterior.get(role, 0.0))
		if value > best_value:
			best_value = value
			best_role = role
	return best_role

func _role_feature_vector_from_observation(observation: Dictionary) -> Array:
	var efference: float = float(observation.get("efference_copy", observation.get("motor_contingency", 0.0)))
	var outcome_match: float = float(observation.get("action_outcome_match", observation.get("motor_contingency", 0.0)))
	if ablation == "no_efference":
		efference *= 0.12
	var motor_value: float = sqrt(maxf(0.0, efference * outcome_match))
	if ablation == "correlation_only":
		motor_value = float(observation.get("temporal_match", 0.0))
	return [
		motor_value,
		float(observation.get("proprioceptive_closure", 0.0)),
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
		float(entity.get("motor", 0.0)),
		float(entity.get("proprio", 0.0)),
		float(entity.get("physical", 0.0)),
		float(entity.get("autonomy", 0.0)),
		float(entity.get("goal", 0.0)),
		float(entity.get("response", 0.0)),
		float(entity.get("tool_coupling", 0.0)),
		float(entity.get("interoceptive", 0.0)),
		float(entity.get("homeostatic", 0.0)),
		float(entity.get("action_history", 0.0))
	]

func _observation_self_anchor_strength(observation: Dictionary) -> float:
	var efference: float = float(observation.get("efference_copy", 0.0))
	var outcome: float = float(observation.get("action_outcome_match", 0.0))
	var motor: float = sqrt(maxf(0.0, efference * outcome))
	return clampf(
		0.26 * motor
		+ 0.18 * float(observation.get("proprioceptive_closure", 0.0))
		+ 0.24 * float(observation.get("interoceptive_closure", 0.0))
		+ 0.18 * float(observation.get("homeostatic_coupling", 0.0))
		+ 0.14 * float(observation.get("action_history_match", 0.0)),
		0.0, 1.0
	)

func _entity_self_anchor_strength(entity: Dictionary) -> float:
	var posterior: Dictionary = entity.get("posterior", {})
	return clampf(
		0.26 * float(posterior.get("Self", 0.0))
		+ 0.18 * float(entity.get("motor", 0.0))
		+ 0.14 * float(entity.get("proprio", 0.0))
		+ 0.18 * float(entity.get("interoceptive", 0.0))
		+ 0.14 * float(entity.get("homeostatic", 0.0))
		+ 0.10 * float(entity.get("action_history", 0.0)),
		0.0, 1.0
	)

func persistent_self_status() -> Dictionary:
	return {"entity_id": persistent_self_id, "confidence": persistent_self_confidence}

func _array_distance(a: Array, b: Array) -> float:
	if a.is_empty() or b.is_empty():
		return 1.0
	var n: int = mini(a.size(), b.size())
	var total: float = 0.0
	for index in range(n):
		var difference: float = float(a[index]) - float(b[index])
		total += difference * difference
	return sqrt(total / float(maxi(1, n)))

func _lerp_array(a: Array, b: Array, weight: float) -> Array:
	if a.is_empty():
		return b.duplicate()
	if b.is_empty():
		return a.duplicate()
	var n: int = mini(a.size(), b.size())
	var result: Array = []
	for index in range(n):
		result.append(lerpf(float(a[index]), float(b[index]), weight))
	return result
