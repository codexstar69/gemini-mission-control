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

# pip install without --no-input → add --no-input
if echo "$modified" | grep -qE '\bpip3? install\b' && ! echo "$modified" | grep -qE '\-\-no-input\b'; then
  modified=$(echo "$modified" | sd '(pip3?) install' '$1 install --no-input')
  changed=true
fi

# ─── CATEGORY 2: System package managers ───

# apt-get install without -y
if echo "$modified" | grep -qE '\bapt-get install\b' && ! echo "$modified" | grep -qE '\-y\b|\-\-yes\b'; then
  modified=$(echo "$modified" | sd 'apt-get install' 'apt-get install -y')
  changed=true
fi

# apt install without -y
if echo "$modified" | grep -qE '\bapt install\b' && ! echo "$modified" | grep -qE '\-y\b|\-\-yes\b'; then
  modified=$(echo "$modified" | sd 'apt install' 'apt install -y')
  changed=true
fi

# yum install without -y
if echo "$modified" | grep -qE '\byum install\b' && ! echo "$modified" | grep -qE '\-y\b|\-\-yes\b'; then
  modified=$(echo "$modified" | sd 'yum install' 'yum install -y')
  changed=true
fi

# dnf install without -y
if echo "$modified" | grep -qE '\bdnf install\b' && ! echo "$modified" | grep -qE '\-y\b|\-\-yes\b'; then
  modified=$(echo "$modified" | sd 'dnf install' 'dnf install -y')
  changed=true
fi

# pacman -S without --noconfirm
if echo "$modified" | grep -qE '\bpacman -S\b' && ! echo "$modified" | grep -qE '\-\-noconfirm\b'; then
  modified=$(echo "$modified" | sd 'pacman -S' 'pacman -S --noconfirm')
  changed=true
fi

# ─── CATEGORY 3: Docker foreground blocking ───

# docker run without -d → add -d for known long-running service images
if echo "$modified" | grep -qE '\bdocker run\b' && ! echo "$modified" | grep -qE '\-d\b|\-\-detach\b'; then
  if echo "$modified" | grep -qE 'postgres|redis|mysql|mongo|rabbitmq|elasticsearch|kafka|nginx|httpd|memcached|mariadb|minio|supabase|nats|zookeeper|consul|vault|grafana|prometheus|influxdb|clickhouse'; then
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

# ─── CATEGORY 4: Git editor/credential prompts ───

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

# ─── CATEGORY 5: Interactive shells and REPLs (BLOCK) ───

# mysql/psql/mongo without -c/-e/--command → opens interactive shell
if echo "$modified" | grep -qE '^\s*(mysql|psql|mongosh?)\s*$' || \
   echo "$modified" | grep -qE '^\s*(mysql|psql|mongosh?)\s+[^-]' && \
   ! echo "$modified" | grep -qE '\-c\b|\-e\b|\-\-command\b|\-f\b|\-\-file\b'; then
  # Can't auto-fix — need a query. Warn but allow.
  :
fi

# python/node/ruby without args → opens REPL (BLOCK)
if echo "$modified" | grep -qE '^\s*(python3?|node|ruby|irb|lua)\s*$'; then
  cat <<EOF
{
  "decision": "deny",
  "reason": "BLOCKED: '${modified}' opens an interactive REPL. Workers cannot interact with REPLs. Use 'python3 -c \"...\"' or 'node -e \"...\"' for one-liner execution, or 'python3 script.py' / 'node script.js' for file execution."
}
EOF
  exit 0
fi

# ssh-keygen without -N → prompts for passphrase
if echo "$modified" | grep -qE '\bssh-keygen\b' && ! echo "$modified" | grep -qE '\-N\b'; then
  modified=$(echo "$modified" | sd 'ssh-keygen' 'ssh-keygen -N ""')
  changed=true
fi

# ─── CATEGORY 6: TUI/pager programs (BLOCK) ───

if echo "$modified" | grep -qE '^\s*(less|more|vi|vim|nvim|nano|emacs|top|htop|man)\b'; then
  cat <<EOF
{
  "decision": "deny",
  "reason": "BLOCKED: '$(echo "$modified" | sd '"' '\\"')' opens an interactive TUI. Workers cannot interact with TUIs. Use 'cat' to view files, or pipe output to a file instead."
}
EOF
  exit 0
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
