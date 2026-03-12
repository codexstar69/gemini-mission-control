#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="/Users/codex/Projects/gemini-mission-control-extension"
cd "$PROJECT_DIR"

# Ensure directory structure exists
mkdir -p agents commands hooks skills scripts

# Ensure gemini-extension.json exists (create minimal if missing)
if [ ! -f gemini-extension.json ]; then
  echo '{"name":"gemini-mission-control","version":"0.1.0","description":"Multi-agent mission control for Gemini CLI","contextFileName":"GEMINI.md","commandsDir":"commands","skillsDir":"skills","hooksDir":"hooks"}' > gemini-extension.json
fi

# Ensure mission state directory exists
mkdir -p ~/.gemini-mc/missions

echo "Environment ready."
