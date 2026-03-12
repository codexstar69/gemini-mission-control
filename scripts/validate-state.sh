#!/usr/bin/env bash
set -euo pipefail

# validate-state.sh — Validate state.json schema using jq
# Usage: validate-state.sh <path-to-state.json>
#   or:  validate-state.sh <mission_id>
# If a mission_id is given (no slashes), looks in ~/.gemini-mc/missions/mis_<id>/state.json

if [ $# -lt 1 ]; then
  echo "Usage: validate-state.sh <path-to-state.json | mission_id>" >&2
  exit 1
fi

INPUT="$1"

# Determine state.json path
if [[ "$INPUT" == */* || "$INPUT" == *.json ]]; then
  STATE_FILE="$INPUT"
else
  STATE_FILE="$HOME/.gemini-mc/missions/mis_${INPUT}/state.json"
fi

if [ ! -f "$STATE_FILE" ]; then
  echo "ERROR: File not found: ${STATE_FILE}" >&2
  exit 1
fi

ERRORS=0

# Check that the file is valid JSON
if ! jq empty "$STATE_FILE" 2>/dev/null; then
  echo "ERROR: ${STATE_FILE} is not valid JSON" >&2
  exit 1
fi

# Validate required fields exist and have correct types
VALIDATION=$(jq -r '
  def check:
    . as $root |
    (if ($root | has("missionId")) and ($root.missionId | type == "string") then "ok" else "FAIL: missionId must be a string" end),
    (if ($root | has("state")) and ($root.state | type == "string") then
      if ($root.state | IN("planning", "orchestrator_turn", "worker_running", "handoff_review", "paused", "completed", "failed")) then "ok"
      else "FAIL: state must be one of: planning, orchestrator_turn, worker_running, handoff_review, paused, completed, failed (got: \($root.state))"
      end
    else "FAIL: state must be a string" end),
    (if ($root | has("workingDirectory")) and ($root.workingDirectory | type == "string") then "ok" else "FAIL: workingDirectory must be a string" end),
    (if ($root | has("completedFeatures")) and ($root.completedFeatures | type == "number") and ($root.completedFeatures >= 0) then "ok" else "FAIL: completedFeatures must be a non-negative number" end),
    (if ($root | has("totalFeatures")) and ($root.totalFeatures | type == "number") and ($root.totalFeatures >= 0) then "ok" else "FAIL: totalFeatures must be a non-negative number" end),
    (if ($root | has("createdAt")) and ($root.createdAt | type == "string") then
      if ($root.createdAt | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}")) then "ok"
      else "FAIL: createdAt must be an ISO-8601 timestamp (got: \($root.createdAt))"
      end
    else "FAIL: createdAt must be a string (ISO 8601)" end),
    (if ($root | has("updatedAt")) and ($root.updatedAt | type == "string") then
      if ($root.updatedAt | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}")) then "ok"
      else "FAIL: updatedAt must be an ISO-8601 timestamp (got: \($root.updatedAt))"
      end
    else "FAIL: updatedAt must be a string (ISO 8601)" end),
    (if ($root | has("sealedMilestones")) and ($root.sealedMilestones | type == "array") then "ok" else "FAIL: sealedMilestones must be an array" end),
    (if ($root | has("milestonesWithValidationPlanned")) and ($root.milestonesWithValidationPlanned | type == "array") then "ok" else "FAIL: milestonesWithValidationPlanned must be an array" end);
  check
' "$STATE_FILE")

while IFS= read -r line; do
  if [ "$line" != "ok" ]; then
    echo "$line" >&2
    ERRORS=$((ERRORS + 1))
  fi
done <<< "$VALIDATION"

if [ "$ERRORS" -gt 0 ]; then
  echo "VALIDATION FAILED: ${ERRORS} error(s) in ${STATE_FILE}" >&2
  exit 1
fi

echo "VALID: ${STATE_FILE} passes schema validation"
