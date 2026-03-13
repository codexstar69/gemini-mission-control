#!/usr/bin/env bash
set -euo pipefail

# validate-state.sh — Validate state.json schema (pure bash, no jq)
# Usage: validate-state.sh <path-to-state.json>
#   or:  validate-state.sh <mission_id>

if [ $# -lt 1 ]; then
  echo "Usage: validate-state.sh <path-to-state.json | mission_id>" >&2
  exit 1
fi

INPUT="$1"

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
err() { echo "$1" >&2; ERRORS=$((ERRORS + 1)); }

# Parse known fields from pretty-printed JSON (one key per line)
has_missionId=0 has_state=0 has_workingDir=0 has_completed=0 has_total=0
has_createdAt=0 has_updatedAt=0 has_sealed=0 has_valPlanned=0
v_state="" v_createdAt="" v_updatedAt="" v_completed="" v_total=""

while IFS= read -r line; do
  case "$line" in
    *'"missionId"'*:*)
      has_missionId=1
      # Check it's a string (has quotes after colon)
      [[ "$line" == *': "'* ]] || err "FAIL: missionId must be a string"
      ;;
    *'"state"'*:*)
      has_state=1
      if [[ "$line" == *': "'* ]]; then
        v_state="${line#*: \"}"; v_state="${v_state%%\"*}"
      else
        err "FAIL: state must be a string"
      fi
      ;;
    *'"workingDirectory"'*:*)
      has_workingDir=1
      [[ "$line" == *': "'* ]] || err "FAIL: workingDirectory must be a string"
      ;;
    *'"completedFeatures"'*:*)
      has_completed=1
      v_completed="${line#*: }"; v_completed="${v_completed%%[, ]*}"
      ;;
    *'"totalFeatures"'*:*)
      has_total=1
      v_total="${line#*: }"; v_total="${v_total%%[, ]*}"
      ;;
    *'"createdAt"'*:*)
      has_createdAt=1
      if [[ "$line" == *': "'* ]]; then
        v_createdAt="${line#*: \"}"; v_createdAt="${v_createdAt%%\"*}"
      else
        err "FAIL: createdAt must be a string (ISO 8601)"
      fi
      ;;
    *'"updatedAt"'*:*)
      has_updatedAt=1
      if [[ "$line" == *': "'* ]]; then
        v_updatedAt="${line#*: \"}"; v_updatedAt="${v_updatedAt%%\"*}"
      else
        err "FAIL: updatedAt must be a string (ISO 8601)"
      fi
      ;;
    *'"sealedMilestones"'*:*)
      has_sealed=1
      [[ "$line" == *'['* ]] || err "FAIL: sealedMilestones must be an array"
      ;;
    *'"milestonesWithValidationPlanned"'*:*)
      has_valPlanned=1
      [[ "$line" == *'['* ]] || err "FAIL: milestonesWithValidationPlanned must be an array"
      ;;
  esac
done < "$STATE_FILE"

# Check required fields exist
[ $has_missionId -eq 1 ] || err "FAIL: missionId must be a string"
[ $has_state -eq 1 ] || err "FAIL: state must be a string"
[ $has_workingDir -eq 1 ] || err "FAIL: workingDirectory must be a string"
[ $has_completed -eq 1 ] || err "FAIL: completedFeatures must be a non-negative number"
[ $has_total -eq 1 ] || err "FAIL: totalFeatures must be a non-negative number"
[ $has_createdAt -eq 1 ] || err "FAIL: createdAt must be a string (ISO 8601)"
[ $has_updatedAt -eq 1 ] || err "FAIL: updatedAt must be a string (ISO 8601)"
[ $has_sealed -eq 1 ] || err "FAIL: sealedMilestones must be an array"
[ $has_valPlanned -eq 1 ] || err "FAIL: milestonesWithValidationPlanned must be an array"

# Validate state enum
if [ -n "$v_state" ]; then
  case "$v_state" in
    planning|orchestrator_turn|worker_running|handoff_review|paused|completed|failed) ;;
    *) err "FAIL: state must be one of: planning, orchestrator_turn, worker_running, handoff_review, paused, completed, failed (got: $v_state)" ;;
  esac
fi

# Validate numbers are non-negative integers
if [ -n "$v_completed" ]; then
  [[ "$v_completed" =~ ^[0-9]+$ ]] || err "FAIL: completedFeatures must be a non-negative number"
fi
if [ -n "$v_total" ]; then
  [[ "$v_total" =~ ^[0-9]+$ ]] || err "FAIL: totalFeatures must be a non-negative number"
fi

# Validate ISO 8601 timestamps
iso_re='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}'
if [ -n "$v_createdAt" ]; then
  [[ "$v_createdAt" =~ $iso_re ]] || err "FAIL: createdAt must be an ISO-8601 timestamp"
fi
if [ -n "$v_updatedAt" ]; then
  [[ "$v_updatedAt" =~ $iso_re ]] || err "FAIL: updatedAt must be an ISO-8601 timestamp"
fi

if [ "$ERRORS" -gt 0 ]; then
  echo "VALIDATION FAILED: ${ERRORS} error(s) in ${STATE_FILE}" >&2
  exit 1
fi

echo "VALID: ${STATE_FILE} passes schema validation"
