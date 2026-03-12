#!/usr/bin/env bash
set -euo pipefail

# session-context.sh
# Checks for active missions in ~/.gemini-mc/missions/ and outputs
# the most recent active mission context for the SessionStart hook.

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

  # Get file modification time (seconds since epoch)
  if [ "$(uname)" = "Darwin" ]; then
    mtime=$(stat -f '%m' "$state_file" 2>/dev/null) || continue
  else
    mtime=$(stat -c '%Y' "$state_file" 2>/dev/null) || continue
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

# Output context for the session
echo "Active mission: ${mission_id} (state: ${state})"
echo "Progress: ${completed}/${total} features completed"
echo "Working directory: ${working_dir}"
echo "State file: ${state_file}"
