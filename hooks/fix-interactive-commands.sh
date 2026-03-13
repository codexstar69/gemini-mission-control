#!/usr/bin/env bash
set -uo pipefail

# BeforeTool hook: auto-fix interactive commands to non-interactive
# Workers are subagents that cannot respond to interactive prompts.
# This hook rewrites commands to add --yes/--no-input flags automatically.
#
# Uses Gemini CLI's tool_input mechanism to modify the command parameter
# before execution — the command runs with the fixed version.

input=$(cat)

# Extract the command being run
cmd=$(echo "$input" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//')

if [ -z "$cmd" ]; then
  echo '{"decision":"allow"}'
  exit 0
fi

modified="$cmd"
changed=false

# npx without --yes → add --yes (prevents "Need to install packages" prompt)
if echo "$modified" | grep -qE '\bnpx\b' && ! echo "$modified" | grep -qE '\-\-yes\b|\-y\b'; then
  modified=$(echo "$modified" | sd 'npx ' 'npx --yes ')
  changed=true
fi

# npm init without -y → add -y
if echo "$modified" | grep -qE '\bnpm init\b' && ! echo "$modified" | grep -qE '\-y\b|\-\-yes\b'; then
  modified=$(echo "$modified" | sd 'npm init' 'npm init -y')
  changed=true
fi

if [ "$changed" = true ]; then
  # Escape for JSON
  escaped=$(echo "$modified" | sd '\\' '\\\\' | sd '"' '\\"')
  cat <<EOF
{
  "decision": "allow",
  "hookSpecificOutput": {
    "hookEventName": "BeforeTool",
    "tool_input": {
      "command": "$escaped"
    }
  },
  "reason": "Auto-fixed to non-interactive: added --yes flags so the command runs without prompts."
}
EOF
else
  echo '{"decision":"allow"}'
fi

exit 0
