# Godot export contract

The frozen scientific dynamics must not be rewritten merely to add a comparator.

Additive instrumentation should expose, for every frame and every candidate observation, the fields in `schema/FRAME_STREAM_COLUMNS.md` **before** CIAS makes the identity-association decision. The exporter must also compute a `scene_hash` from scene/cue data that is independent of model condition.

## Required invariants

1. Exporting rows does not consume RNG calls.
2. Changing `model_condition` does not change scene/cue RNG.
3. Candidate order may be shuffled, but `scene_hash` is computed from a canonical sorted representation.
4. Truth labels are written only to the evaluator output; they are never placed into the input dictionary passed to comparator code.
5. The existing v1.0.0 runner and raw files remain untouched.

## Parameter overrides

For the robustness experiment, create an additive runner that accepts a JSON parameter override and instantiates the same ontology/benchmark with those values. Do not patch source files in place between runs. Each output row must include `parameter_id` and the SHA-256 of the exact override JSON.

## Expected run-level metrics export

At minimum:

`seed,profile,scenario,condition,parameter_id,identity_continuity,lure_capture,recovery_latency_s,fragment_count,scene_hash`

The sensitivity analyzer assumes `full` and `no_persistent_self` are paired within each seed/profile/scenario/parameter_id.
