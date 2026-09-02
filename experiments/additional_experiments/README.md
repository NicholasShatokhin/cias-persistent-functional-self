# Additional experiments

This directory contains two prespecified tests that are executed by the repository-level `RUN_ALL_*` command.

## 1. Independent generic state estimator

A generic recurrent state estimator receives the same observable frame stream as CIAS. It has no explicit Self role, no persistent lineage ID, and no change-point reconnect rule. Its Gaussian emission model and recurrent hyperparameters are selected using seeds 315-326 only. Seeds 327-330 are a technical preflight. The frozen diagnostic fit is then evaluated on untouched seeds 331-360.

An appearance-continuity tracker is retained as a sanity baseline.

Ground-truth identity fields are used to fit the diagnostic emission model and to score outputs. They are not included among test-time model-visible features.

## 2. Parameter sensitivity

The canonical CIAS operating point plus 26 prespecified perturbations are evaluated on a separate untouched range, seeds 361-390. The sweep varies association weights/thresholds, anchor gates/costs, and smoothing rates. All 27 settings are retained, including failures.

The analysis reports the fraction of the tested parameter region preserving the Full-versus-lesion continuity and lure-rejection effects, CI support, profile-direction consistency, medians, worst tested effects, and failure regions.

Generated scientific results are written to `results/generated/` and are intentionally trackable by Git.
