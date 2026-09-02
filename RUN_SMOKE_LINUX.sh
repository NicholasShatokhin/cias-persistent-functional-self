#!/usr/bin/env bash
set -euo pipefail
GODOT=${1:?Usage: ./RUN_SMOKE_LINUX.sh /path/to/godot}
cd "$(dirname "$0")"
python3 -m venv .venv-experiments
. .venv-experiments/bin/activate
python -m pip install -U pip
python -m pip install -r requirements.txt
python tools/run_full_replication.py --repo . --godot "$GODOT" --smoke-only
