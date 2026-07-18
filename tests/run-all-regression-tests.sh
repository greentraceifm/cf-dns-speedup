#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

bash "$ROOT/tests/run-regression-tests.sh"
bash "$ROOT/tests/test-router-candidate-gate.sh"
bash "$ROOT/tests/test-router-canary-plan.sh"
bash "$ROOT/tests/test-router-canary-mock.sh"
bash "$ROOT/sidecar/tests/run-tests.sh"

echo "all project regression tests passed"
