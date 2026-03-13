#!/usr/bin/env bash
set -uo pipefail

# BeforeTool hook: block pipe-masking patterns in shell commands
# Prevents workers from piping through tail/head/grep which masks exit codes.
# This enforces what was previously just an instruction — now it's a hard gate.

input=$(cat)

# Extract the command being run
cmd=$(echo "$input" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//')

if [ -z "$cmd" ]; then
  echo '{"decision":"allow"}'
  exit 0
fi

# Check for pipe-masking patterns: command | tail, command | head, command | grep
# These mask the real exit code of the left-hand command.
# Allow: grep by itself, pipes to tee, pipes to cat (passthrough)
# Block: test/lint/build commands piped through tail/head/grep/wc
if echo "$cmd" | grep -qE '\|\s*(tail|head)\b'; then
  cat <<EOF
{
  "decision": "deny",
  "reason": "BLOCKED: Piping through tail/head masks the real exit code. If the left-hand command fails, the pipe reports tail/head's exit code (0) instead. Run the command directly without piping: remove the '| tail' or '| head' suffix."
}
EOF
  exit 0
fi

echo '{"decision":"allow"}'
exit 0
