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

# Collect all state.json paths
state_files=()
for f in "$MISSIONS_DIR"/mis_*/state.json; do
  [ -f "$f" ] && state_files+=("$f")
done

# No missions at all
if [ ${#state_files[@]} -eq 0 ]; then
  exit 0
fi

# Get mtimes for all state files in ONE stat call, sorted newest-first
# Output: "mtime path" per line, sorted descending by mtime
sorted=$(stat -f '%m %N' "${state_files[@]}" 2>/dev/null | sort -rn)

# Walk newest-first, find first active (not completed/failed) mission
# Extract all needed fields in a SINGLE jq call per candidate
while IFS=' ' read -r mtime path; do
  [ -f "$path" ] || continue
  # Single jq call: extract state + all display fields, tab-separated
  line=$(jq -r '[.state // "unknown", .missionId // "unknown", .workingDirectory // "unknown", (.completedFeatures // 0 | tostring), (.totalFeatures // 0 | tostring)] | join("\t")' "$path" 2>/dev/null) || continue

  IFS=$'\t' read -r state mission_id working_dir completed total <<< "$line"

  # Skip completed and failed missions
  [ "$state" = "completed" ] && continue
  [ "$state" = "failed" ] && continue

  # Found the most recent active mission — output context
  # Derive mission_dir from path
  mission_dir="${path%state.json}"

  echo "=== Active Mission Context (reloaded from disk) ==="
  echo "Mission ID: ${mission_id}"
  echo "State: ${state}"
  echo "Progress: ${completed}/${total} features completed"
  echo "Working directory: ${working_dir}"
  echo "Mission directory: ${mission_dir}"

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
  exit 0
done <<< "$sorted"

# No active mission found
exit 0
