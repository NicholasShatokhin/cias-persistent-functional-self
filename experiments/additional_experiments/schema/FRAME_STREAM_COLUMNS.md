# Canonical matched observation stream

Each row is one candidate observation at one simulation frame. The scene is generated **once per seed/profile** and the same frame dictionaries are passed to CIAS Full and the anchor lesion. The generic comparator reads the same exported rows.

## Model-visible fields

- metadata: `run_id`, `seed`, `profile`, `scenario`, `frame`, `time_s`, `observation_id`
- position: `x`, `y`
- raw engineered appearance vector: `appearance_0..appearance_3` (`appearance` is a convenience mean)
- causal/dynamic cues: `efference`, `outcome`, their conjunction `motor`, `proprio`, `temporal`, `crossmodal`, `persistence`, `physical`, `autonomy`, `goal`, `response`, `tool`, `intero`, `homeo`, `history`

All cue components are in `[0,1]`. These remain engineered semantic variables; this suite does **not** solve learning from raw pixels/tactile/interoceptive streams.

## Evaluator-only fields

- `is_true_lineage`
- `is_lure`
- `truth_entity_id`

These are never passed into CIAS or a comparator at test time. `GenericRecurrentFilter` may use diagnostic `is_true_lineage` only to fit a deliberately strong supervised emission model; test prediction strictly whitelists visible fields.

## Provenance

- `scene_hash`: SHA-256 of the generated scene/cue realization before any model inference.
- `change_point`: exported for audit/plotting; the primary generic recurrent filter does not consume it.
