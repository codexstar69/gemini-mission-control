#!/usr/bin/env bash
set -euo pipefail

# Benchmark: instruction token footprint
# Measures total bytes of all instruction files that the LLM loads during operation.
#
# Files measured:
#   ALWAYS LOADED (every session):
#     - GEMINI.md (extension context, loaded on every session start)
#
#   LOADED ON /mission-run (orchestrator loop — the hot path):
#     - skills/mission-orchestrator/SKILL.md
#
#   LOADED ON /mission-plan:
#     - skills/mission-planner/SKILL.md
#
#   LOADED ON /mission-plan (Phase 7, worker design):
#     - skills/define-worker-skills/SKILL.md
#
#   LOADED PER WORKER DISPATCH (worker gets agent body as system prompt):
#     - agents/mission-worker.md
#     - agents/code-quality-worker.md
#     - agents/scrutiny-validator.md
#     - agents/user-testing-validator.md
#
#   LOADED PER COMMAND INVOCATION:
#     - commands/*.toml (each one is small, but they add up)
#
# Primary metric: total_bytes of ALL instruction files
# Secondary metrics: per-file and per-category breakdowns

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

file_bytes() {
  wc -c < "$1" 2>/dev/null | tr -d ' '
}

# === ALWAYS LOADED ===
gemini_md=$(file_bytes "GEMINI.md")

# === ORCHESTRATOR (hot path — every loop iteration) ===
orchestrator=$(file_bytes "skills/mission-orchestrator/SKILL.md")

# === PLANNER ===
planner=$(file_bytes "skills/mission-planner/SKILL.md")

# === WORKER SKILLS DESIGNER ===
worker_skills=$(file_bytes "skills/define-worker-skills/SKILL.md")

# === AGENTS (loaded per worker dispatch) ===
agent_worker=$(file_bytes "agents/mission-worker.md")
agent_quality=$(file_bytes "agents/code-quality-worker.md")
agent_scrutiny=$(file_bytes "agents/scrutiny-validator.md")
agent_usertesting=$(file_bytes "agents/user-testing-validator.md")
agents_total=$((agent_worker + agent_quality + agent_scrutiny + agent_usertesting))

# === COMMANDS ===
commands_total=0
for f in commands/*.toml; do
  [ -f "$f" ] && commands_total=$((commands_total + $(file_bytes "$f")))
done

# === SCRIPTS (not LLM-loaded, but part of extension) ===
scripts_total=0
for f in scripts/*.sh; do
  [ -f "$f" ] && scripts_total=$((scripts_total + $(file_bytes "$f")))
done

# === TOTALS ===
# "hot_path_bytes" = what the LLM processes every orchestrator loop iteration
# This is: GEMINI.md + mission-orchestrator SKILL.md
hot_path=$((gemini_md + orchestrator))

# "full_bytes" = every instruction file in the extension
total=$((gemini_md + orchestrator + planner + worker_skills + agents_total + commands_total))

# === QUALITY CHECK ===
if ! bash autoresearch-quality.sh >/dev/null 2>&1; then
  echo "QUALITY CHECK FAILED — run bash autoresearch-quality.sh for details"
  exit 1
fi

echo "=== RESULTS ==="
echo "total_bytes: ${total}"
echo "hot_path_bytes: ${hot_path}"
echo "gemini_md_bytes: ${gemini_md}"
echo "orchestrator_bytes: ${orchestrator}"
echo "planner_bytes: ${planner}"
echo "worker_skills_bytes: ${worker_skills}"
echo "agents_bytes: ${agents_total}"
echo "commands_bytes: ${commands_total}"
echo "scripts_bytes: ${scripts_total}"
