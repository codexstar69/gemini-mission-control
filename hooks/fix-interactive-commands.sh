#!/usr/bin/env bash
set -uo pipefail

# BeforeTool hook: auto-fix interactive commands to non-interactive
# Workers are subagents that cannot respond to interactive prompts.
# This hook rewrites commands to add flags that skip prompts/foreground blocking.
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

# ─── CATEGORY 1: Package managers ───

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

# yarn create without --yes → add --yes
if echo "$modified" | grep -qE '\byarn create\b' && ! echo "$modified" | grep -qE '\-\-yes\b'; then
  modified=$(echo "$modified" | sd 'yarn create ' 'yarn create --yes ')
  changed=true
fi

# pnpm create without --yes → add --yes
if echo "$modified" | grep -qE '\bpnpm create\b' && ! echo "$modified" | grep -qE '\-\-yes\b'; then
  modified=$(echo "$modified" | sd 'pnpm create ' 'pnpm create --yes ')
  changed=true
fi

# composer install/update without --no-interaction
if echo "$modified" | grep -qE '\bcomposer (install|update|require)\b' && ! echo "$modified" | grep -qE '\-\-no-interaction\b|\-n\b'; then
  modified=$(echo "$modified" | sd 'composer (install|update|require)' 'composer $1 --no-interaction')
  changed=true
fi

# ─── CATEGORY 3: Docker foreground blocking ───

# docker run without -d → add -d (prevents foreground hang)
# But skip if command already has -d, --detach, -it, --rm (short-lived)
if echo "$modified" | grep -qE '\bdocker run\b' && ! echo "$modified" | grep -qE '\-d\b|\-\-detach\b'; then
  # Only add -d for long-running containers (those with service images like postgres, redis, mysql, mongo, etc.)
  if echo "$modified" | grep -qE 'postgres|redis|mysql|mongo|rabbitmq|elasticsearch|kafka|nginx|httpd|memcached|mariadb|minio'; then
    modified=$(echo "$modified" | sd 'docker run ' 'docker run -d ')
    changed=true
  fi
fi

# docker compose up without -d → add -d
if echo "$modified" | grep -qE '\bdocker compose up\b|\bdocker-compose up\b' && ! echo "$modified" | grep -qE '\-d\b|\-\-detach\b'; then
  modified=$(echo "$modified" | sd 'docker compose up' 'docker compose up -d' | sd 'docker-compose up' 'docker-compose up -d')
  changed=true
fi

# docker exec -it → docker exec (drop -it, subagent has no tty)
if echo "$modified" | grep -qE '\bdocker exec\s+\-it\b|\bdocker exec\s+\-ti\b'; then
  modified=$(echo "$modified" | sd 'docker exec -it ' 'docker exec ' | sd 'docker exec -ti ' 'docker exec ')
  changed=true
fi

# ─── CATEGORY 4: Git editor prompts ───

# git commit without -m → prevent editor opening
if echo "$modified" | grep -qE '\bgit commit\b' && ! echo "$modified" | grep -qE '\-m\b|\-\-message\b|\-\-allow-empty-message\b|\-\-amend\b'; then
  modified=$(echo "$modified" | sd 'git commit' 'git commit --allow-empty-message')
  changed=true
fi

# Set GIT_TERMINAL_PROMPT=0 for git clone/push/pull/fetch to prevent credential prompts
if echo "$modified" | grep -qE '\bgit (clone|push|pull|fetch)\b' && ! echo "$modified" | grep -qE 'GIT_TERMINAL_PROMPT'; then
  modified="GIT_TERMINAL_PROMPT=0 $modified"
  changed=true
fi

# ─── Output ───

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
  "reason": "Auto-fixed to non-interactive: added flags so the command runs without prompts in subagent context."
}
EOF
else
  echo '{"decision":"allow"}'
fi

exit 0
