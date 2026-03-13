#!/usr/bin/env bash
set -uo pipefail

# AfterAgent hook: validate mission state consistency when agent completes
# Catches silent state drift (e.g., completedFeatures counter doesn't match actual completed features)

input=$(cat)

# Find the most recent active mission
MISSIONS_DIR="${HOME}/.gemini-mc/missions"
[ -d "$MISSIONS_DIR" ] || { echo '{"decision":"allow"}'; exit 0; }

# Find newest mission by mtime
sorted=$(cd "$MISSIONS_DIR" && ls -t mis_*/state.json 2>/dev/null | head -1) || { echo '{"decision":"allow"}'; exit 0; }
[ -n "$sorted" ] || { echo '{"decision":"allow"}'; exit 0; }

state_file="${MISSIONS_DIR}/${sorted}"
features_file="${state_file%state.json}features.json"

[ -f "$state_file" ] || { echo '{"decision":"allow"}'; exit 0; }
[ -f "$features_file" ] || { echo '{"decision":"allow"}'; exit 0; }

# Check if the mission is active (skip completed/failed)
state_val=$(grep -o '"state"[[:space:]]*:[[:space:]]*"[^"]*"' "$state_file" | head -1 | sed 's/.*: *"//;s/"$//')
case "$state_val" in
  completed|failed) echo '{"decision":"allow"}'; exit 0 ;;
esac

# Extract completedFeatures counter from state.json
counter=$(grep -o '"completedFeatures"[[:space:]]*:[[:space:]]*[0-9]*' "$state_file" | head -1 | grep -o '[0-9]*$')
[ -n "$counter" ] || { echo '{"decision":"allow"}'; exit 0; }

# Count actual completed features in features.json (only count "completed" status, not "completedFeatures")
actual=$(grep -c '"status"[[:space:]]*:[[:space:]]*"completed"' "$features_file" 2>/dev/null) || actual=0

warnings=""

if [ "$counter" -ne "$actual" ] 2>/dev/null; then
  warnings="${warnings}completedFeatures counter ($counter) vs actual completed ($actual). "
fi

# Extract totalFeatures counter
total_counter=$(grep -o '"totalFeatures"[[:space:]]*:[[:space:]]*[0-9]*' "$state_file" | head -1 | grep -o '[0-9]*$')
if [ -n "$total_counter" ]; then
  # Count features by counting "id" fields in features array
  actual_total=$(grep -c '"id"[[:space:]]*:' "$features_file" 2>/dev/null) || actual_total=0
  if [ "$total_counter" -ne "$actual_total" ] 2>/dev/null; then
    warnings="${warnings}totalFeatures counter ($total_counter) vs actual total ($actual_total). "
  fi
fi

if [ -n "$warnings" ]; then
  # Escape for JSON
  escaped_warnings=$(echo "$warnings" | sed 's/"/\\"/g')
  echo "{\"systemMessage\":\"⚠️ STATE DRIFT: ${escaped_warnings}Run /mission-status to review.\"}"
else
  echo '{"decision":"allow"}'
fi
exit 0
