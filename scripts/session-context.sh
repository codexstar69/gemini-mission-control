#!/usr/bin/env bash
set -euo pipefail

# session-context.sh
# Checks for active missions in ~/.gemini-mc/missions/ and outputs
# the most recent active mission context for the SessionStart hook.

MISSIONS_DIR="${HOME}/.gemini-mc/missions"

[ -d "$MISSIONS_DIR" ] || exit 0

# Use ls -t to get state files sorted by mtime (newest first) — one process instead of stat+sort
sorted=$(cd "$MISSIONS_DIR" && ls -t mis_*/state.json 2>/dev/null) || exit 0
[ -n "$sorted" ] || exit 0

# Pure-bash JSON extractor for pretty-printed state.json
parse_state_json() {
  local file="$1"
  j_state="" j_missionId="" j_workingDirectory="" j_completedFeatures="" j_totalFeatures=""
  while IFS= read -r line; do
    case "$line" in
      *'"state"'*)       j_state="${line#*: \"}"; j_state="${j_state%%\"*}" ;;
      *'"missionId"'*)   j_missionId="${line#*: \"}"; j_missionId="${j_missionId%%\"*}" ;;
      *'"workingDirectory"'*) j_workingDirectory="${line#*: \"}"; j_workingDirectory="${j_workingDirectory%%\"*}" ;;
      *'"completedFeatures"'*) j_completedFeatures="${line#*: }"; j_completedFeatures="${j_completedFeatures%%[, ]*}" ;;
      *'"totalFeatures"'*) j_totalFeatures="${line#*: }"; j_totalFeatures="${j_totalFeatures%%[, ]*}" ;;
    esac
  done < "$file"
}

# Walk newest-first
while IFS= read -r relpath; do
  path="${MISSIONS_DIR}/${relpath}"
  [ -f "$path" ] || continue

  parse_state_json "$path"

  [ "$j_state" = "completed" ] && continue
  [ "$j_state" = "failed" ] && continue
  [ -z "$j_state" ] && continue

  mission_dir="${path%state.json}"

  echo "=== Active Mission Context (reloaded from disk) ==="
  echo "Mission ID: ${j_missionId:-unknown}"
  echo "State: ${j_state}"
  echo "Progress: ${j_completedFeatures:-0}/${j_totalFeatures:-0} features completed"
  echo "Working directory: ${j_workingDirectory:-unknown}"
  echo "Mission directory: ${mission_dir}"

  case "$j_state" in
    planning)            echo "Next action: Run /mission-plan to continue planning" ;;
    orchestrator_turn)   echo "Next action: Run /mission-run to continue execution" ;;
    paused)              echo "Next action: Run /mission-resume to resume execution" ;;
    worker_running|handoff_review) echo "Next action: Run /mission-run to recover from interrupted session" ;;
    *)                   echo "Run /mission-status for full details" ;;
  esac

  echo "=== End Mission Context ==="
  exit 0
done <<< "$sorted"

exit 0
