#!/usr/bin/env bash
set -euo pipefail

# session-context.sh
# Checks for active missions in ~/.gemini-mc/missions/ and outputs
# the most recent active mission context for the SessionStart hook.
# This ensures mission state is reloaded on Gemini CLI session restart.

MISSIONS_DIR="${HOME}/.gemini-mc/missions"

# Exit silently if no missions directory exists
if [ ! -d "$MISSIONS_DIR" ]; then
  exit 0
fi

# Find the most recently updated active mission (not completed/failed)
latest_state=""
latest_time=0
latest_dir=""

for mission_dir in "$MISSIONS_DIR"/mis_*/; do
  [ -d "$mission_dir" ] || continue
  state_file="${mission_dir}state.json"
  [ -f "$state_file" ] || continue

  # Read mission state
  state=$(jq -r '.state // empty' "$state_file" 2>/dev/null) || continue

  # Skip completed and failed missions
  if [ "$state" = "completed" ] || [ "$state" = "failed" ]; then
    continue
  fi

  # Get updatedAt timestamp for comparison (prefer state data over mtime)
  updated_at=$(jq -r '.updatedAt // empty' "$state_file" 2>/dev/null) || true

  # Fall back to file modification time if updatedAt is missing
  if [ -z "$updated_at" ]; then
    if [ "$(uname)" = "Darwin" ]; then
      mtime=$(stat -f '%m' "$state_file" 2>/dev/null) || continue
    else
      mtime=$(stat -c '%Y' "$state_file" 2>/dev/null) || continue
    fi
  else
    # Convert ISO 8601 to epoch for comparison (use file mtime as proxy)
    if [ "$(uname)" = "Darwin" ]; then
      mtime=$(stat -f '%m' "$state_file" 2>/dev/null) || continue
    else
      mtime=$(stat -c '%Y' "$state_file" 2>/dev/null) || continue
    fi
  fi

  # Track most recent
  if [ "$mtime" -gt "$latest_time" ]; then
    latest_time=$mtime
    latest_state=$state
    latest_dir=$mission_dir
  fi
done

# No active mission found
if [ -z "$latest_dir" ]; then
  exit 0
fi

# Read mission details
state_file="${latest_dir}state.json"
mission_id=$(jq -r '.missionId // "unknown"' "$state_file" 2>/dev/null)
state=$(jq -r '.state // "unknown"' "$state_file" 2>/dev/null)
working_dir=$(jq -r '.workingDirectory // "unknown"' "$state_file" 2>/dev/null)
completed=$(jq -r '.completedFeatures // 0' "$state_file" 2>/dev/null)
total=$(jq -r '.totalFeatures // 0' "$state_file" 2>/dev/null)

# Output context for the session — this is read by the model on session start
echo "=== Active Mission Context (reloaded from disk) ==="
echo "Mission ID: ${mission_id}"
echo "State: ${state}"
echo "Progress: ${completed}/${total} features completed"
echo "Working directory: ${working_dir}"
echo "Mission directory: ${latest_dir}"

# Suggest next action based on current state
case "$state" in
  planning)
    echo "Next action: Run /mission-plan to continue planning"
    ;;
  orchestrator_turn)
    echo "Next action: Run /mission-run to continue execution"
    ;;
  paused)
    echo "Next action: Run /mission-resume to resume execution"
    ;;
  worker_running|handoff_review)
    echo "Next action: Run /mission-run to recover from interrupted session"
    ;;
  *)
    echo "Run /mission-status for full details"
    ;;
esac

echo "=== End Mission Context ==="
