class_name DevelopmentalSelfBenchmarkP2
extends RefCounted

const OntologyCoreScript = preload("res://scripts/ontology_core.gd")

const VERSION: String = "7.0-p2"
const PROFILES: Array[String] = [
	"ground_creature",
	"wheeled_robot",
	"drone",
	"virtual_avatar"
]
const CONDITIONS: Array[String] = [
	"progressive_persistent",
	"final_from_start",
	"reverse_curriculum",
	"random_curriculum",
	"progressive_history_reset",
	"progressive_no_persistent_self"
]

const TRAINING_FRAMES_PER_STAGE: int = 42
const TRANSITION_AMBIGUOUS_FRAMES: int = 24
const TRANSITION_CLONE_FRAMES: int = 20
const FINAL_PROBE_FRAMES: int = 72
const FINAL_CLONE_FRAMES: int = 48
const DT: float = 0.10
const RECOVERY_STREAK_REQUIRED: int = 5

var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func run(profile: String, condition: String, seed: int) -> Dictionary:
	assert(PROFILES.has(profile))
	assert(CONDITIONS.has(condition))
	rng.seed = seed * 100003 + PROFILES.find(profile) * 1009 + CONDITIONS.find(condition) * 17

	var ontology = OntologyCoreScript.new()
	var ontology_ablation: String = "no_persistent_self" if condition == "progressive_no_persistent_self" else "full"
	var epoch: int = 0
	ontology.reset(ontology_ablation, seed * 31 + PROFILES.find(profile) * 7 + 11)

	var schedule: Array[int] = _schedule_for(condition, seed)
	var initial_identity_key: String = ""
	var last_identity_key: String = ""
	var last_self_id: int = -1
	var last_self_signature: Array = []
	var previous_anchor: Vector2 = Vector2(260.0, 280.0)

	var total_self_role_correct: int = 0
	var total_self_role_frames: int = 0
	var whole_run_identity_keys: Dictionary = {}
	var transition_records: Array[Dictionary] = []
	var chain_preserved_transitions: int = 0
	var transition_count: int = 0
	var total_change_point_events: int = 0
	var sham_change_point_events: int = 0

	for stage_index in range(schedule.size()):
		var level: int = schedule[stage_index]
		var is_first: bool = stage_index == 0
		var pre_transition_key: String = last_identity_key
		var old_signature: Array = last_self_signature.duplicate()
		var level_changed: bool = (not is_first) and schedule[stage_index] != schedule[stage_index - 1]

		if not is_first:
			transition_count += 1
			total_change_point_events += 1
			if not level_changed:
				sham_change_point_events += 1

			# Matched change-point exposure across ALL curriculum arms.
			# History-reset has the same post-change association regime but no pre-change identity history.
			if condition == "progressive_history_reset":
				epoch += 1
				ontology.reset("full", seed * 31 + stage_index * 101 + 19)
				ontology.notify_change_point()
			else:
				ontology.notify_change_point()

		var anchor: Vector2 = _stage_anchor(seed, stage_index, profile)
		var clone_anchor: Vector2 = previous_anchor
		var transition_retained: int = 0
		var transition_frames: int = 0
		var clone_capture: int = 0
		var recovery_frame: int = -1
		var recovery_streak: int = 0
		var transition_switches: int = 0
		var previous_transition_key: String = ""

		for frame in range(TRAINING_FRAMES_PER_STAGE):
			var result: Dictionary = _observe_frame(
				ontology, profile, level, seed, stage_index, frame,
				anchor, clone_anchor, old_signature,
				(not is_first and frame < TRANSITION_CLONE_FRAMES),
				(not is_first and frame < TRANSITION_AMBIGUOUS_FRAMES),
				false
			)
			last_self_id = int(result["self_core_id"])
			last_identity_key = _identity_key(epoch, last_self_id)
			last_self_signature = result["self_signature"].duplicate()
			whole_run_identity_keys[last_identity_key] = true

			if previous_transition_key != "" and previous_transition_key != last_identity_key and not is_first:
				transition_switches += 1
			previous_transition_key = last_identity_key

			total_self_role_frames += 1
			if String(result["self_role"]) == "Self":
				total_self_role_correct += 1

			if not is_first:
				transition_frames += 1
				if pre_transition_key != "" and last_identity_key == pre_transition_key:
					transition_retained += 1
					recovery_streak += 1
				else:
					recovery_streak = 0
				if bool(result["clone_present"]) and _identity_key(epoch, int(result["clone_core_id"])) == pre_transition_key:
					clone_capture += 1
				if recovery_frame < 0 and recovery_streak >= RECOVERY_STREAK_REQUIRED:
					recovery_frame = frame - RECOVERY_STREAK_REQUIRED + 1

			if initial_identity_key == "" and frame >= 16:
				initial_identity_key = last_identity_key

		if not is_first:
			var retained_fraction: float = float(transition_retained) / float(maxi(1, transition_frames))
			var lure_fraction: float = float(clone_capture) / float(maxi(1, mini(TRANSITION_CLONE_FRAMES, transition_frames)))
			var recovered: bool = recovery_frame >= 0
			if pre_transition_key != "" and last_identity_key == pre_transition_key:
				chain_preserved_transitions += 1
			transition_records.append({
				"stage_index": stage_index,
				"from_level": schedule[stage_index - 1],
				"to_level": level,
				"level_changed": 1.0 if level_changed else 0.0,
				"retention": retained_fraction,
				"clone_capture": lure_fraction,
				"recovery_latency": float(recovery_frame) * DT if recovered else float(TRAINING_FRAMES_PER_STAGE) * DT,
				"recovered": 1.0 if recovered else 0.0,
				"identity_switches": transition_switches
			})
		previous_anchor = anchor

	# Common adversarial probe. Every arm gets exactly one additional change point.
	var pre_probe_identity_key: String = last_identity_key
	var pre_probe_signature: Array = last_self_signature.duplicate()
	total_change_point_events += 1
	ontology.notify_change_point()

	var final_anchor: Vector2 = _final_probe_anchor(seed, profile)
	var final_retained: int = 0
	var final_clone_capture: int = 0
	var final_role_correct: int = 0
	var final_recovery_frame: int = -1
	var final_recovery_streak: int = 0
	var final_identity_keys: Dictionary = {}
	var final_self_posterior_sum: float = 0.0
	var final_clone_self_posterior_sum: float = 0.0
	var final_identity_switches: int = 0
	var previous_final_key: String = ""

	for frame in range(FINAL_PROBE_FRAMES):
		var result: Dictionary = _observe_frame(
			ontology, profile, 3, seed, 99, frame,
			final_anchor, previous_anchor, pre_probe_signature,
			frame < FINAL_CLONE_FRAMES,
			true,
			true
		)
		last_self_id = int(result["self_core_id"])
		last_identity_key = _identity_key(epoch, last_self_id)
		final_identity_keys[last_identity_key] = true
		whole_run_identity_keys[last_identity_key] = true

		if previous_final_key != "" and previous_final_key != last_identity_key:
			final_identity_switches += 1
		previous_final_key = last_identity_key

		if pre_probe_identity_key != "" and last_identity_key == pre_probe_identity_key:
			final_retained += 1
			final_recovery_streak += 1
		else:
			final_recovery_streak = 0
		if bool(result["clone_present"]) and _identity_key(epoch, int(result["clone_core_id"])) == pre_probe_identity_key:
			final_clone_capture += 1
		if final_recovery_frame < 0 and final_recovery_streak >= RECOVERY_STREAK_REQUIRED:
			final_recovery_frame = frame - RECOVERY_STREAK_REQUIRED + 1
		if String(result["self_role"]) == "Self":
			final_role_correct += 1
		final_self_posterior_sum += float(result["self_posterior"])
		final_clone_self_posterior_sum += float(result["clone_self_posterior"])

	var final_retention: float = float(final_retained) / float(FINAL_PROBE_FRAMES)
	var lure_error: float = float(final_clone_capture) / float(FINAL_CLONE_FRAMES)
	var final_recovered: bool = final_recovery_frame >= 0
	var recovery_latency: float = float(final_recovery_frame) * DT if final_recovered else float(FINAL_PROBE_FRAMES) * DT
	var recovery_score: float = exp(-recovery_latency / 2.8) if final_recovered else 0.0
	var final_role_accuracy: float = float(final_role_correct) / float(FINAL_PROBE_FRAMES)
	var self_post: float = final_self_posterior_sum / float(FINAL_PROBE_FRAMES)
	var clone_post: float = final_clone_self_posterior_sum / float(FINAL_PROBE_FRAMES)
	var posterior_margin: float = self_post - clone_post
	var posterior_preference: float = clampf((posterior_margin + 1.0) * 0.5, 0.0, 1.0)
	var fragmentation_score: float = 1.0 / (1.0 + 0.28 * float(maxi(0, final_identity_keys.size() - 1)))

	# p2 endpoint frozen before execution. It is intentionally continuous, not a pure ID-retention score.
	var identity_continuity_score_v2: float = (
		0.30 * final_retention
		+ 0.20 * (1.0 - lure_error)
		+ 0.16 * recovery_score
		+ 0.24 * posterior_preference
		+ 0.10 * fragmentation_score
	)
	# Legacy p1-compatible score for cross-version diagnostics.
	var identity_continuity_score_legacy: float = (
		0.50 * final_retention
		+ 0.25 * (1.0 - lure_error)
		+ 0.25 * recovery_score
	)

	var stage_chain_score: float = float(chain_preserved_transitions) / float(maxi(1, transition_count))
	var initial_identity_retained_at_end: float = 1.0 if initial_identity_key != "" and last_identity_key == initial_identity_key else 0.0

	return {
		"protocol_version": VERSION,
		"profile": profile,
		"condition": condition,
		"seed": seed,
		"schedule": _schedule_string(schedule),
		"training_transition_count": transition_count,
		"matched_change_point_events": total_change_point_events,
		"sham_change_point_events": sham_change_point_events,
		"training_transition_retention": _mean_transition_value(transition_records, "retention", 1.0),
		"training_transition_lure_error": _mean_transition_value(transition_records, "clone_capture", 0.0),
		"training_transition_recovery_latency": _mean_transition_value(transition_records, "recovery_latency", 0.0),
		"training_transition_identity_switches": _mean_transition_value(transition_records, "identity_switches", 0.0),
		"stage_identity_chain_score": stage_chain_score,
		"final_identity_retention": final_retention,
		"final_identity_recovered": 1.0 if final_recovered else 0.0,
		"final_identity_recovery_latency": recovery_latency,
		"final_old_signature_clone_capture": lure_error,
		"final_identity_switches": final_identity_switches,
		"final_self_role_accuracy": final_role_accuracy,
		"final_self_posterior": self_post,
		"final_clone_self_posterior": clone_post,
		"final_self_posterior_margin": posterior_margin,
		"final_identity_fragmentation": final_identity_keys.size(),
		"whole_run_self_fragmentation": whole_run_identity_keys.size(),
		"initial_identity_retained_at_end": initial_identity_retained_at_end,
		"self_role_accuracy_all_stages": float(total_self_role_correct) / float(maxi(1, total_self_role_frames)),
		"identity_continuity_score_v2": identity_continuity_score_v2,
		"identity_continuity_score_legacy": identity_continuity_score_legacy
	}

func _observe_frame(
	ontology,
	profile: String,
	level: int,
	seed: int,
	stage_index: int,
	frame: int,
	self_anchor: Vector2,
	clone_anchor: Vector2,
	old_signature: Array,
	clone_present: bool,
	ambiguous_phase: bool,
	final_probe: bool
) -> Dictionary:
	var t: float = float(frame) * DT
	var action_strength: float = clampf(0.66 + 0.25 * sin(0.37 * float(frame) + 0.11 * float(seed)), 0.22, 0.98)
	ontology.register_action(action_strength)

	var self_position: Vector2 = self_anchor + Vector2(
		27.0 * sin(0.18 * float(frame) + 0.3 * float(level)),
		22.0 * cos(0.15 * float(frame) + 0.17 * float(seed))
	)
	var self_signature: Array = _self_signature(profile, level, stage_index, final_probe)

	var observations: Array = []
	var self_features: Dictionary = _true_self_features(profile, level, frame, action_strength, ambiguous_phase, final_probe)
	var self_obs: Dictionary = {
		"truth_id": 1,
		"truth_role": "Self",
		"position": self_position,
		"signature": _noisy_signature(self_signature, _profile_noise(profile) * (0.36 if ambiguous_phase else 0.28)),
		"efference_copy": self_features["efference_copy"],
		"action_outcome_match": self_features["action_outcome_match"],
		"temporal_match": self_features["temporal_match"],
		"proprioceptive_closure": self_features["proprioceptive_closure"],
		"crossmodal_coherence": self_features["crossmodal_coherence"],
		"persistence": self_features["persistence"],
		"physical_predictability": self_features["physical_predictability"],
		"autonomous_dynamics": 0.06,
		"goal_directedness": 0.13,
		"response_contingency": 0.08,
		"tool_coupling": 0.03,
		"interoceptive_closure": self_features["interoceptive_closure"],
		"homeostatic_coupling": self_features["homeostatic_coupling"],
		"action_history_match": self_features["action_history_match"]
	}
	observations.append(self_obs)

	if clone_present and not old_signature.is_empty():
		var clone_position: Vector2 = clone_anchor + Vector2(
			10.0 * sin(0.11 * frame + 0.4),
			8.0 * cos(0.13 * frame + 0.2)
		)
		var clone_features: Dictionary = _yoked_clone_features(action_strength, frame, final_probe)
		var clone_obs: Dictionary = {
			"truth_id": 91,
			"truth_role": "Object",
			"position": clone_position,
			"signature": _noisy_signature(old_signature, _profile_noise(profile) * 0.10),
			"efference_copy": clone_features["efference_copy"],
			"action_outcome_match": clone_features["action_outcome_match"],
			"temporal_match": clone_features["temporal_match"],
			"proprioceptive_closure": clone_features["proprioceptive_closure"],
			"crossmodal_coherence": clone_features["crossmodal_coherence"],
			"persistence": 0.97,
			"physical_predictability": 0.92,
			"autonomous_dynamics": 0.04,
			"goal_directedness": 0.03,
			"response_contingency": 0.04,
			"tool_coupling": 0.02,
			"interoceptive_closure": clone_features["interoceptive_closure"],
			"homeostatic_coupling": clone_features["homeostatic_coupling"],
			"action_history_match": clone_features["action_history_match"]
		}
		observations.append(clone_obs)

	observations.append({
		"truth_id": 2,
		"truth_role": "Object",
		"position": Vector2(760.0, 170.0) + Vector2(12.0 * sin(t), 8.0 * cos(t)),
		"signature": [0.12, 0.77, 0.31, 0.63, 0.18, 0.54],
		"efference_copy": 0.02, "action_outcome_match": 0.03, "temporal_match": 0.90,
		"proprioceptive_closure": 0.02, "crossmodal_coherence": 0.76, "persistence": 0.94,
		"physical_predictability": 0.96, "autonomous_dynamics": 0.04, "goal_directedness": 0.02,
		"response_contingency": 0.02, "tool_coupling": 0.01, "interoceptive_closure": 0.01,
		"homeostatic_coupling": 0.01, "action_history_match": 0.02
	})
	observations.append({
		"truth_id": 3,
		"truth_role": "Agent",
		"position": Vector2(690.0, 700.0) + Vector2(30.0 * cos(0.07 * frame), 25.0 * sin(0.09 * frame)),
		"signature": [0.81, 0.21, 0.68, 0.38, 0.72, 0.33],
		"efference_copy": 0.02, "action_outcome_match": 0.04, "temporal_match": 0.86,
		"proprioceptive_closure": 0.03, "crossmodal_coherence": 0.82, "persistence": 0.88,
		"physical_predictability": 0.48, "autonomous_dynamics": 0.92, "goal_directedness": 0.86,
		"response_contingency": 0.72, "tool_coupling": 0.01, "interoceptive_closure": 0.01,
		"homeostatic_coupling": 0.01, "action_history_match": 0.02
	})

	for i in range(observations.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var temp = observations[i]
		observations[i] = observations[j]
		observations[j] = temp

	var ids: Array[int] = ontology.observe_frame(observations, DT)
	var self_core_id: int = -1
	var clone_core_id: int = -1
	var self_role: String = "Object"
	var self_posterior: float = 0.0
	var clone_self_posterior: float = 0.0
	for idx in range(observations.size()):
		var truth_id: int = int(observations[idx].get("truth_id", -1))
		var core_id: int = ids[idx]
		if truth_id == 1:
			self_core_id = core_id
			var entity: Dictionary = ontology.get_entity(core_id)
			self_role = String(entity.get("role", "Object"))
			self_posterior = float(Dictionary(entity.get("posterior", {})).get("Self", 0.0))
		elif truth_id == 91:
			clone_core_id = core_id
			var clone_entity: Dictionary = ontology.get_entity(core_id)
			clone_self_posterior = float(Dictionary(clone_entity.get("posterior", {})).get("Self", 0.0))

	return {
		"self_core_id": self_core_id,
		"clone_core_id": clone_core_id,
		"clone_present": clone_present,
		"self_role": self_role,
		"self_posterior": self_posterior,
		"clone_self_posterior": clone_self_posterior,
		"self_signature": self_signature
	}

func _true_self_features(profile: String, level: int, frame: int, action_strength: float, ambiguous: bool, final_probe: bool) -> Dictionary:
	var base_q: float = _causal_quality(profile, level)
	if not ambiguous:
		return {
			"efference_copy": clampf(action_strength * (base_q + _noise(0.018)), 0.0, 1.0),
			"action_outcome_match": clampf(base_q + _noise(0.022), 0.0, 1.0),
			"temporal_match": clampf(0.92 + _noise(0.024), 0.0, 1.0),
			"proprioceptive_closure": clampf(base_q + 0.025 + _noise(0.018), 0.0, 1.0),
			"crossmodal_coherence": clampf(0.89 + _noise(0.024), 0.0, 1.0),
			"persistence": 0.94,
			"physical_predictability": 0.74,
			"interoceptive_closure": clampf(base_q + 0.035 + _noise(0.016), 0.0, 1.0),
			"homeostatic_coupling": clampf(base_q + 0.020 + _noise(0.018), 0.0, 1.0),
			"action_history_match": clampf(base_q + _noise(0.020), 0.0, 1.0)
		}

	# Ambiguity phase: causal evidence is distributed across time rather than all channels being strong at once.
	# Periodic anchor-refresh frames retain genuine evidence while forcing the core to survive partial dropouts.
	var phase: int = frame % 10
	var refresh: bool = phase >= 8
	var motor_q: float = 0.88 if refresh else (0.60 if phase <= 4 else 0.76)
	var intero_q: float = 0.86 if refresh else (0.72 if phase <= 4 else 0.48)
	var history_q: float = 0.86 if refresh else (0.68 if phase <= 4 else 0.57)
	var proprio_q: float = 0.83 if refresh else (0.64 if phase <= 4 else 0.60)
	var final_penalty: float = 0.04 if final_probe else 0.0

	return {
		"efference_copy": clampf(action_strength * (motor_q - final_penalty + _noise(0.025)), 0.0, 1.0),
		"action_outcome_match": clampf(motor_q + 0.08 + _noise(0.025), 0.0, 1.0),
		"temporal_match": clampf(0.80 + (0.08 if refresh else 0.0) + _noise(0.035), 0.0, 1.0),
		"proprioceptive_closure": clampf(proprio_q - final_penalty + _noise(0.025), 0.0, 1.0),
		"crossmodal_coherence": clampf(0.78 + (0.08 if refresh else 0.0) + _noise(0.035), 0.0, 1.0),
		"persistence": 0.88,
		"physical_predictability": 0.70,
		"interoceptive_closure": clampf(intero_q - final_penalty + _noise(0.022), 0.0, 1.0),
		"homeostatic_coupling": clampf(intero_q - 0.05 - final_penalty + _noise(0.024), 0.0, 1.0),
		"action_history_match": clampf(history_q - final_penalty + _noise(0.025), 0.0, 1.0)
	}

func _yoked_clone_features(action_strength: float, frame: int, final_probe: bool) -> Dictionary:
	var phase: int = frame % 10
	var pulse: float = 0.05 if phase in [2, 3, 6] else 0.0
	var extra: float = 0.035 if final_probe else 0.0
	return {
		"efference_copy": clampf(action_strength * (0.60 + pulse + extra + _noise(0.020)), 0.0, 1.0),
		"action_outcome_match": clampf(0.70 + pulse + extra + _noise(0.022), 0.0, 1.0),
		"temporal_match": clampf(0.93 + _noise(0.018), 0.0, 1.0),
		"proprioceptive_closure": clampf(0.57 + pulse + _noise(0.020), 0.0, 1.0),
		"crossmodal_coherence": clampf(0.86 + _noise(0.020), 0.0, 1.0),
		"interoceptive_closure": clampf(0.46 + pulse + _noise(0.018), 0.0, 1.0),
		"homeostatic_coupling": clampf(0.41 + pulse + _noise(0.018), 0.0, 1.0),
		"action_history_match": clampf(0.50 + pulse + _noise(0.020), 0.0, 1.0)
	}

func _schedule_for(condition: String, seed: int) -> Array[int]:
	if condition in ["progressive_persistent", "progressive_history_reset", "progressive_no_persistent_self"]:
		return [0, 1, 2, 3]
	if condition == "final_from_start":
		return [3, 3, 3, 3]
	if condition == "reverse_curriculum":
		# Same terminal body exposure as progressive; only precursor order differs.
		return [2, 1, 0, 3]
	var precursor: Array[int] = [0, 1, 2]
	var local_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	local_rng.seed = seed * 3301 + 71
	for i in range(precursor.size() - 1, 0, -1):
		var j: int = local_rng.randi_range(0, i)
		var temp: int = precursor[i]
		precursor[i] = precursor[j]
		precursor[j] = temp
	precursor.append(3)
	return precursor

func _stage_anchor(seed: int, stage_index: int, profile: String) -> Vector2:
	var p: int = PROFILES.find(profile)
	return Vector2(
		180.0 + float((seed * 83 + stage_index * 239 + p * 101) % 610),
		150.0 + float((seed * 47 + stage_index * 197 + p * 137) % 590)
	)

func _final_probe_anchor(seed: int, profile: String) -> Vector2:
	var p: int = PROFILES.find(profile)
	return Vector2(
		190.0 + float((seed * 271 + p * 89) % 590),
		170.0 + float((seed * 181 + p * 149) % 560)
	)

func _self_signature(profile: String, level: int, stage_index: int, probe: bool) -> Array:
	var p: float = float(PROFILES.find(profile))
	var l: float = float(level)
	var style: float = float((stage_index if stage_index < 90 else 4) % 5)
	var base: Array = [
		clampf(0.16 + 0.16 * p + 0.04 * l + 0.025 * style, 0.02, 0.98),
		clampf(0.84 - 0.09 * p - 0.06 * l - 0.020 * style, 0.02, 0.98),
		clampf(0.20 + 0.18 * l + 0.018 * style, 0.02, 0.98),
		clampf(0.78 - 0.13 * l + 0.03 * p + 0.015 * style, 0.02, 0.98),
		clampf(0.28 + 0.11 * p + 0.08 * l - 0.022 * style, 0.02, 0.98),
		clampf(0.66 - 0.07 * p + 0.05 * l + 0.019 * style, 0.02, 0.98)
	]
	if not probe:
		return base
	return [
		clampf(1.0 - float(base[3]), 0.02, 0.98),
		clampf(float(base[5]) * 0.72, 0.02, 0.98),
		clampf(1.0 - float(base[0]) * 0.82, 0.02, 0.98),
		clampf(float(base[1]) * 0.48 + 0.10, 0.02, 0.98),
		clampf(1.0 - float(base[4]) * 0.78, 0.02, 0.98),
		clampf(float(base[2]) * 0.55 + 0.18, 0.02, 0.98)
	]

func _causal_quality(profile: String, level: int) -> float:
	var profile_penalty: float = [0.00, 0.030, 0.075, -0.012][PROFILES.find(profile)]
	var developmental_quality: Array[float] = [0.975, 0.935, 0.885, 0.835]
	return clampf(developmental_quality[level] - profile_penalty, 0.69, 0.99)

func _profile_noise(profile: String) -> float:
	return [0.020, 0.030, 0.060, 0.012][PROFILES.find(profile)]

func _identity_key(epoch: int, core_id: int) -> String:
	if core_id < 0:
		return "%d:none" % epoch
	return "%d:%d" % [epoch, core_id]

func _noise(scale: float) -> float:
	return rng.randf_range(-scale, scale)

func _noisy_signature(signature: Array, scale: float) -> Array:
	var result: Array = []
	for value in signature:
		result.append(clampf(float(value) + _noise(scale), 0.0, 1.0))
	return result

func _mean_transition_value(records: Array[Dictionary], key: String, default_value: float) -> float:
	if records.is_empty():
		return default_value
	var total: float = 0.0
	for record in records:
		total += float(record.get(key, default_value))
	return total / float(records.size())

func _schedule_string(schedule: Array[int]) -> String:
	var parts: Array[String] = []
	for value in schedule:
		parts.append(str(value))
	return "-".join(parts)
