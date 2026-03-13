#!/usr/bin/env bash
set -uo pipefail

# PreCompress hook: save mission state before context compression
# When Gemini CLI compresses context to save tokens, the agent loses conversation history.
# This hook saves a snapshot so the orchestrator can recover.

input=$(cat)

MISSIONS_DIR="${HOME}/.gemini-mc/missions"
[ -d "$MISSIONS_DIR" ] || exit 0

# Find active mission
sorted=$(cd "$MISSIONS_DIR" && ls -t mis_*/state.json 2>/dev/null | head -1) || exit 0
[ -n "$sorted" ] || exit 0

state_file="${MISSIONS_DIR}/${sorted}"
mission_dir="${state_file%state.json}"

[ -f "$state_file" ] || exit 0

# Extract state
state_val=$(grep -o '"state"[[:space:]]*:[[:space:]]*"[^"]*"' "$state_file" | head -1 | sed 's/.*: *"//;s/"$//')
case "$state_val" in
  completed|failed) exit 0 ;;
esac

# Append compression event to progress log
log_file="${mission_dir}progress_log.jsonl"
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "{\"timestamp\":\"${timestamp}\",\"event\":\"context_compressed\",\"state\":\"${state_val}\"}" >> "$log_file" 2>/dev/null

# Show a system message reminding the agent to re-read state
echo "{\"systemMessage\":\"📋 Context compressed. Mission state preserved on disk. Re-read state.json and features.json to restore context.\"}"
exit 0
