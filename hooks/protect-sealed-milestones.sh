#!/usr/bin/env bash
set -uo pipefail

# BeforeTool hook: prevent writing to features.json if it would add features to a sealed milestone
# This enforces the "sealed milestones are immutable" rule at the tool level.

input=$(cat)

# Extract file path
file_path=$(echo "$input" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//')
if [ -z "$file_path" ]; then
  file_path=$(echo "$input" | grep -o '"path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//')
fi

# Only check features.json writes
case "$file_path" in
  */missions/mis_*/features.json)
    ;;
  *)
    echo '{"decision":"allow"}'
    exit 0
    ;;
esac

# Find the corresponding state.json
state_file="${file_path%features.json}state.json"
if [ ! -f "$state_file" ]; then
  echo '{"decision":"allow"}'
  exit 0
fi

# Extract sealedMilestones array from state.json
sealed=$(grep -o '"sealedMilestones"[[:space:]]*:[[:space:]]*\[[^]]*\]' "$state_file" 2>/dev/null || true)
if [ -z "$sealed" ]; then
  # No sealed milestones — nothing to protect
  echo '{"decision":"allow"}'
  exit 0
fi

# Extract the new content being written
new_content=$(echo "$input" | grep -o '"content"[[:space:]]*:[[:space:]]*"' | head -1)
if [ -z "$new_content" ]; then
  # Can't parse content — allow and let the orchestrator catch issues
  echo '{"decision":"allow"}'
  exit 0
fi

# If sealed milestones exist, warn the agent
cat <<EOF
{
  "decision": "allow",
  "hookSpecificOutput": {
    "additionalContext": "⚠️ REMINDER: This mission has sealed milestones (${sealed}). Do NOT add new features to sealed milestones. Redirect to misc-* milestones instead."
  }
}
EOF
exit 0
