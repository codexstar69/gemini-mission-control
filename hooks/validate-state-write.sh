#!/usr/bin/env bash
set -uo pipefail

# AfterTool hook: validate state.json after every write
# Fires after write_file/replace targeting a mission state.json
# Catches corruption immediately instead of failing on next session start.

input=$(cat)

# Extract the file path from tool_input
file_path=$(echo "$input" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//')
# Also check 'path' field (replace tool uses this)
if [ -z "$file_path" ]; then
  file_path=$(echo "$input" | grep -o '"path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//')
fi

# Only validate state.json writes
case "$file_path" in
  */missions/mis_*/state.json)
    ;;
  *)
    echo '{"decision":"allow"}'
    exit 0
    ;;
esac

# Validate the written file exists and is valid JSON
if [ ! -f "$file_path" ]; then
  echo '{"decision":"allow","systemMessage":"⚠️ state.json write detected but file not found at '"$file_path"'"}'
  exit 0
fi

# Check it's valid JSON (pure bash — no jq dependency)
content=$(cat "$file_path" 2>/dev/null)
if [ -z "$content" ]; then
  cat <<EOF
{"decision":"allow","systemMessage":"🚨 STATE CORRUPTION: state.json is empty after write. Check your write_file call."}
EOF
  exit 0
fi

# Verify required fields exist
missing=""
for field in "state" "missionId" "workingDirectory" "completedFeatures" "totalFeatures" "updatedAt"; do
  if ! echo "$content" | grep -q "\"$field\""; then
    missing="$missing $field"
  fi
done

if [ -n "$missing" ]; then
  cat <<EOF
{"decision":"allow","systemMessage":"🚨 STATE CORRUPTION: state.json missing required fields:${missing}. Re-read the file and fix immediately."}
EOF
  exit 0
fi

# Verify state is a known value
state_val=$(echo "$content" | grep -o '"state"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//')
case "$state_val" in
  planning|orchestrator_turn|worker_running|handoff_review|paused|completed|failed)
    ;;
  *)
    cat <<EOF
{"decision":"allow","systemMessage":"🚨 STATE CORRUPTION: state.json has invalid state value '${state_val}'. Must be one of: planning, orchestrator_turn, worker_running, handoff_review, paused, completed, failed."}
EOF
    exit 0
    ;;
esac

# All checks passed
echo '{"decision":"allow"}'
exit 0
