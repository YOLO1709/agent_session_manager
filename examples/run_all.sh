#!/usr/bin/env bash
# Run all AgentSessionManager examples in mock mode.
#
# Usage:
#   ./examples/run_all.sh
#
# All examples run in mock mode by default so no API credentials are needed.
# Set LIVE=1 to run with real credentials (requires env vars to be set).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

MOCK_FLAG="--mock"
if [ "${LIVE:-0}" = "1" ]; then
  MOCK_FLAG=""
  echo "Running in LIVE mode (credentials required)"
else
  echo "Running in MOCK mode (no credentials needed)"
  echo "Set LIVE=1 to run with real API credentials."
fi

echo ""
echo "========================================"
echo " AgentSessionManager Examples"
echo "========================================"
echo ""

PASS=0
FAIL=0

run_example() {
  local name="$1"
  local file="$2"
  shift 2
  local extra_args=("$@")

  echo "--- $name ---"
  if mix run "$file" "${extra_args[@]}" $MOCK_FLAG; then
    echo ""
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo ""
    echo "  FAIL: $name"
    FAIL=$((FAIL + 1))
  fi
  echo ""
}

# Run each example
run_example "Live Session (Claude)" "examples/live_session.exs" --provider claude
run_example "Live Session (Codex)"  "examples/live_session.exs" --provider codex

# Summary
echo "========================================"
echo " Results: $PASS passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
