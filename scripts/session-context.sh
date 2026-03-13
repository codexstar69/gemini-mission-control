#!/usr/bin/env bash
set -euo pipefail

# session-context.sh
# Checks for active missions in ~/.gemini-mc/missions/ and outputs
# the most recent active mission context for the SessionStart hook.

MISSIONS_DIR="${HOME}/.gemini-mc/missions"

[ -d "$MISSIONS_DIR" ] || exit 0

# Collect all state.json paths
state_files=()
for f in "$MISSIONS_DIR"/mis_*/state.json; do
  [ -f "$f" ] && state_files+=("$f")
done
[ ${#state_files[@]} -eq 0 ] && exit 0

# Get mtimes sorted newest-first in ONE stat call
sorted=$(stat -f '%m %N' "${state_files[@]}" 2>/dev/null | sort -rn)

# Pure-bash JSON extractor: read line-by-line (state.json is pretty-printed, one key per line)
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

# Walk newest-first, find first active mission
while IFS=' ' read -r mtime path; do
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
