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

# Single jq call: validate JSON + schema, output only errors (empty = valid)
ERRORS=$(jq -r '
  [
    (if (has("missionId") and (.missionId | type == "string")) then empty else "FAIL: missionId must be a string" end),
    (if (has("state") and (.state | type == "string")) then
      if .state == "planning" or .state == "orchestrator_turn" or .state == "worker_running" or .state == "handoff_review" or .state == "paused" or .state == "completed" or .state == "failed" then empty
      else "FAIL: state must be one of: planning, orchestrator_turn, worker_running, handoff_review, paused, completed, failed (got: \(.state))" end
    else "FAIL: state must be a string" end),
    (if (has("workingDirectory") and (.workingDirectory | type == "string")) then empty else "FAIL: workingDirectory must be a string" end),
    (if (has("completedFeatures") and (.completedFeatures | type == "number") and .completedFeatures >= 0) then empty else "FAIL: completedFeatures must be a non-negative number" end),
    (if (has("totalFeatures") and (.totalFeatures | type == "number") and .totalFeatures >= 0) then empty else "FAIL: totalFeatures must be a non-negative number" end),
    (if (has("createdAt") and (.createdAt | type == "string") and (.createdAt | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}"))) then empty else "FAIL: createdAt must be an ISO-8601 timestamp" end),
    (if (has("updatedAt") and (.updatedAt | type == "string") and (.updatedAt | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}"))) then empty else "FAIL: updatedAt must be an ISO-8601 timestamp" end),
    (if (has("sealedMilestones") and (.sealedMilestones | type == "array")) then empty else "FAIL: sealedMilestones must be an array" end),
    (if (has("milestonesWithValidationPlanned") and (.milestonesWithValidationPlanned | type == "array")) then empty else "FAIL: milestonesWithValidationPlanned must be an array" end)
  ] | .[]
' "$STATE_FILE" 2>&1) || {
  echo "ERROR: ${STATE_FILE} is not valid JSON" >&2
  exit 1
}

if [ -n "$ERRORS" ]; then
  echo "$ERRORS" >&2
  count=$(echo "$ERRORS" | wc -l)
  echo "VALIDATION FAILED: ${count} error(s) in ${STATE_FILE}" >&2
  exit 1
fi

echo "VALID: ${STATE_FILE} passes schema validation"
