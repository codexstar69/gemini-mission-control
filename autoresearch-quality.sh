#!/usr/bin/env bash
set -uo pipefail

# Quality test for instruction files.
# Verifies semantic completeness, cross-file consistency, and critical path coverage.
# Exit 0 = all checks pass. Exit 1 = quality regression found.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

ERRORS=0
WARNINGS=0

fail() { echo "  ❌ FAIL: $1"; ((ERRORS++)); }
warn() { echo "  ⚠️  WARN: $1"; ((WARNINGS++)); }
pass() { echo "  ✅ $1"; }

check_present() {
  local file="$1" concept="$2" label="${3:-$2}"
  if rg -q "$concept" "$file" 2>/dev/null; then
    pass "$label in $file"
  else
    fail "$label MISSING in $file"
  fi
}

echo "=== 1. ORCHESTRATOR: 8-step loop completeness ==="
ORCH="skills/mission-orchestrator/SKILL.md"
for step in "Step 1" "Step 2" "Step 3" "Step 4" "Step 5" "Step 6" "Step 7" "Step 8"; do
  check_present "$ORCH" "$step"
done

echo ""
echo "=== 2. ORCHESTRATOR: Decision tree completeness ==="
for opt in "Option A" "Option B" "Option C" "Option D" "Clean"; do
  check_present "$ORCH" "$opt"
done

echo ""
echo "=== 3. ORCHESTRATOR: Critical procedures ==="
check_present "$ORCH" "crash recovery" "Crash recovery procedure"
check_present "$ORCH" "sealedMilestones" "Sealed milestone tracking"
check_present "$ORCH" "milestonesWithValidationPlanned" "Validation planned tracking"
check_present "$ORCH" "deadlock" "Deadlock detection"
check_present "$ORCH" "budget" "Budget enforcement"
check_present "$ORCH" "RETRY" "Retry prefix for descriptions"
check_present "$ORCH" "PARTIAL" "Partial prefix for descriptions"
check_present "$ORCH" "max 5|Maximum 5|5 features" "Misc milestone capacity limit"
check_present "$ORCH" "3 retries|retried 3|After 3|reaches 3|count reaches 3" "Retry limit (3)"
check_present "$ORCH" "scope_change|Scope Change|scope change" "Scope change protocol"

echo ""
echo "=== 4. ORCHESTRATOR: Handoff parsing fields ==="
for field in "salientSummary" "whatWasImplemented" "whatWasLeftUndone" "commandsRun" "exitCode" "discoveredIssues" "severity"; do
  check_present "$ORCH" "$field"
done

echo ""
echo "=== 5. ORCHESTRATOR: State machine states ==="
for state in "orchestrator_turn" "worker_running" "handoff_review" "paused" "completed" "failed"; do
  check_present "$ORCH" "$state"
done

echo ""
echo "=== 6. PLANNER: 7-phase completeness ==="
PLAN="skills/mission-planner/SKILL.md"
for phase in "Phase 1" "Phase 2" "Phase 3" "Phase 4" "Phase 5" "Phase 6" "Phase 7"; do
  check_present "$PLAN" "$phase"
done

echo ""
echo "=== 7. PLANNER: Critical procedures ==="
check_present "$PLAN" "coverage gate|Coverage gate" "Coverage gate enforcement"
check_present "$PLAN" "DAG|acyclic|topological" "DAG acyclicity check"
check_present "$PLAN" "user confirm|user has confirmed|user explicitly confirms|Do NOT proceed until|Do NOT proceed" "User confirmation gate"
check_present "$PLAN" "validation-contract.md" "Validation contract generation"
check_present "$PLAN" "features.json" "Features generation"
check_present "$PLAN" "validation-state.json" "Validation state init"
check_present "$PLAN" "AGENTS.md" "AGENTS.md generation"
check_present "$PLAN" "services.yaml" "Services manifest"
check_present "$PLAN" "init.sh" "Init script"
check_present "$PLAN" "orchestrator_turn" "State transition target"

echo ""
echo "=== 8. AGENTS: Handoff JSON schema in each agent ==="
for agent in agents/*.md; do
  name=$(basename "$agent" .md)
  check_present "$agent" "salientSummary" "Handoff schema in $name"
  check_present "$agent" "whatWasImplemented" "whatWasImplemented in $name"
  check_present "$agent" "whatWasLeftUndone" "whatWasLeftUndone in $name"
  check_present "$agent" "commandsRun" "commandsRun in $name"
  check_present "$agent" "discoveredIssues" "discoveredIssues in $name"
done

echo ""
echo "=== 9. AGENTS: Correct frontmatter ==="
for agent in agents/*.md; do
  name=$(basename "$agent" .md)
  check_present "$agent" "kind: local" "kind:local in $name"
  # Check for valid tool names only
  if rg -q "run_command\b" "$agent" 2>/dev/null; then
    fail "$name uses invalid tool name 'run_command' (should be run_shell_command)"
  fi
  if rg -q "web_search\b" "$agent" 2>/dev/null && ! rg -q "google_web_search" "$agent" 2>/dev/null; then
    fail "$name uses invalid tool name 'web_search' (should be google_web_search)"
  fi
done

echo ""
echo "=== 10. AGENTS: Never-pipe warning ==="
for agent in agents/mission-worker.md agents/code-quality-worker.md agents/scrutiny-validator.md; do
  if rg -q "pipe|tail|head|mask" "$agent" 2>/dev/null; then
    pass "Pipe warning in $(basename $agent)"
  else
    warn "Missing pipe/exit-code warning in $(basename $agent)"
  fi
done

echo ""
echo "=== 11. CROSS-FILE: Terminology consistency ==="
# Decision tree options should use same labels everywhere
check_present "GEMINI.md" "Option A" "GEMINI.md references Option A"
check_present "GEMINI.md" "Option B" "GEMINI.md references Option B"
check_present "GEMINI.md" "coverage gate" "GEMINI.md references coverage gate"
check_present "GEMINI.md" "sealedMilestones" "GEMINI.md references sealedMilestones"

echo ""
echo "=== 12. COMMANDS: All 9 commands exist ==="
for cmd in mission-start mission-plan mission-run mission-status mission-list mission-pause mission-resume mission-export mission-override; do
  if [ -f "commands/$cmd.toml" ]; then
    pass "$cmd.toml exists"
  else
    fail "$cmd.toml MISSING"
  fi
done

echo ""
echo "=== 13. COMMANDS: Key commands reference skills ==="
check_present "commands/mission-plan.toml" "mission-planner|activate_skill" "mission-plan invokes planner skill"
check_present "commands/mission-run.toml" "mission-orchestrator|activate_skill" "mission-run invokes orchestrator skill"

echo ""
echo "=== 14. DEFINE-WORKER-SKILLS: Critical content ==="
DWS="skills/define-worker-skills/SKILL.md"
check_present "$DWS" "kind: local" "kind:local instruction"
check_present "$DWS" "run_shell_command" "Correct tool name example"
check_present "$DWS" "salientSummary" "Handoff schema"
check_present "$DWS" "Startup|startup" "Startup phase"
check_present "$DWS" "Cleanup|cleanup" "Cleanup phase"

echo ""
echo "=== 15. ORCHESTRATOR: Cancelled features satisfy preconditions ==="
check_present "$ORCH" "cancelled" "Orchestrator mentions cancelled features"
# Check that DAG eval mentions cancelled
if rg -q "completed.*cancelled|cancelled.*completed" "$ORCH" 2>/dev/null; then
  pass "DAG eval handles cancelled as satisfied in orchestrator"
else
  warn "Orchestrator may not handle cancelled features in DAG eval"
fi

echo ""
echo "=== 16. GEMINI.md: Cancelled in preconditions ==="
if rg -q "completed or cancelled|completed/cancelled" "GEMINI.md" 2>/dev/null; then
  pass "GEMINI.md mentions cancelled satisfies preconditions"
else
  warn "GEMINI.md may not mention cancelled features satisfy preconditions"
fi

echo ""
echo "=== 17. ORCHESTRATOR: updatedAt timestamp guidance ==="
check_present "$ORCH" "updatedAt" "updatedAt field mentioned"
check_present "$ORCH" "ISO 8601" "ISO 8601 timestamp format"

echo ""
echo "=== 18. PLANNER: Feature JSON example ==="
check_present "$PLAN" "expectedBehavior" "expectedBehavior in feature schema"
check_present "$PLAN" "verificationSteps" "verificationSteps in feature schema"
check_present "$PLAN" "fulfills" "fulfills in feature schema"
check_present "$PLAN" "preconditions" "preconditions in feature schema"

echo ""
echo "=== 19. PLANNER: VAL ID format ==="
check_present "$PLAN" "VAL-" "VAL- prefix in planner"
check_present "$PLAN" "VAL-.*-[0-9]" "VAL ID number suffix pattern"

echo ""
echo "=== 20. AGENTS: All 4 agents have tools array ==="
for agent in agents/*.md; do
  name=$(basename "$agent" .md)
  check_present "$agent" "tools" "tools array in $name"
done

echo ""
echo "=== 21. ORCHESTRATOR: Option A + incomplete clarification ==="
check_present "$ORCH" "high-severity.*incomplete|high.*non-empty.*whatWasLeftUndone|high-severity.*Option B" "Option A + incomplete → Option B fallback"

echo ""
echo "=== 22. HOOKS: SessionStart hook exists ==="
if [ -f "hooks/hooks.json" ]; then
  if rg -q "SessionStart" "hooks/hooks.json" 2>/dev/null; then
    pass "SessionStart hook configured"
  else
    fail "hooks.json missing SessionStart"
  fi
else
  fail "hooks/hooks.json missing"
fi

echo ""
echo "=== 23. SCRIPTS: All scripts executable ==="
for script in scripts/scaffold-mission.sh scripts/session-context.sh scripts/validate-state.sh; do
  if [ -x "$script" ]; then
    pass "$script is executable"
  else
    warn "$script is not executable"
  fi
done

echo ""
echo "=== 24. AGENTS: Tool names are valid Gemini CLI tools ==="
VALID_TOOLS="read_file|write_file|replace|run_shell_command|grep_search|list_directory|google_web_search|web_fetch|glob|read_many_files"
for agent in agents/*.md; do
  name=$(basename "$agent" .md)
  # Extract tool names from frontmatter (between first --- and second ---)
  in_frontmatter=0
  in_tools=0
  while IFS= read -r line; do
    if [[ "$line" == "---" ]]; then
      if [ $in_frontmatter -eq 0 ]; then
        in_frontmatter=1; continue
      else
        break
      fi
    fi
    if [[ "$line" =~ ^tools: ]]; then
      in_tools=1
      # Handle inline array: tools: [read_file, write_file, ...]
      if [[ "$line" =~ \[ ]]; then
        # Extract tools from inline array
        tools_str="${line#*[}"
        tools_str="${tools_str%%]*}"
        for tool in $(echo "$tools_str" | tr ',' '\n' | tr -d ' '); do
          if ! echo "$tool" | rg -q "^($VALID_TOOLS)$" 2>/dev/null; then
            fail "Invalid tool '$tool' in $name"
          fi
        done
        in_tools=0
      fi
      continue
    fi
    if [ $in_tools -eq 1 ]; then
      if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+(.*) ]]; then
        tool="${BASH_REMATCH[1]}"
        if ! echo "$tool" | rg -q "^($VALID_TOOLS)$" 2>/dev/null; then
          fail "Invalid tool '$tool' in $name"
        fi
      elif [[ ! "$line" =~ ^[[:space:]] ]]; then
        in_tools=0
      fi
    fi
  done < "$agent"
  pass "All tools valid in $name"
done

echo ""
echo "=== 25. SCENARIO: Happy path concepts present ==="
# A clean success flow needs: DAG eval → dispatch → handoff parse → Clean Success → milestone check → validator injection → seal
check_present "$ORCH" "first.*ready|first ready" "Happy path: select first ready feature"
check_present "$ORCH" "worker_running" "Happy path: transition to worker_running"
check_present "$ORCH" "handoff_review" "Happy path: transition to handoff_review"
check_present "$ORCH" "Clean Success" "Happy path: clean success path"
check_present "$ORCH" "scrutiny-validator-" "Happy path: scrutiny validator injection"
check_present "$ORCH" "user-testing-validator-" "Happy path: user-testing validator injection"
check_present "$ORCH" "sealedMilestones" "Happy path: milestone sealing"

echo ""
echo "=== 26. SCENARIO: Retry escalation concepts present ==="
check_present "$ORCH" "RETRY" "Retry: RETRY prefix"
check_present "$ORCH" "feature_retry" "Retry: retry log event"
check_present "$ORCH" "feature_escalation" "Retry: escalation log event"
check_present "$ORCH" "Manual intervention|manual intervention|user help" "Retry: user intervention request"

echo ""
echo "=== 27. SCENARIO: Crash recovery concepts present ==="
check_present "$ORCH" "crash_recovery" "Crash: recovery log event"
check_present "$ORCH" "worker_started.*worker_completed|worker_completed.*worker_started" "Crash: detect stuck by matching start/complete events"

echo ""
echo "=== 28. SEVERITY FORMAT: All agents use high/medium/low ==="
for agent in agents/*.md; do
  name=$(basename "$agent" .md)
  if rg -q '"blocking|non_blocking"' "$agent" 2>/dev/null; then
    fail "$name uses blocking/non_blocking severity (should be high/medium/low)"
  else
    pass "Consistent severity format in $name"
  fi
done

echo ""
echo "=== 29. CROSS-FILE: services.yaml format consistency ==="
# Planner should define the format, agents should reference the same fields
check_present "$PLAN" "healthcheck" "Planner defines healthcheck in services.yaml"
check_present "$PLAN" "depends_on" "Planner defines depends_on in services.yaml"
check_present "agents/user-testing-validator.md" "healthcheck" "User-testing validator references healthcheck"
check_present "agents/user-testing-validator.md" "depends_on" "User-testing validator references depends_on"
# Verify test/typecheck/lint commands are mentioned in planner
check_present "$PLAN" "test.*command|command.*test" "Planner defines test command"
check_present "$PLAN" "typecheck" "Planner defines typecheck command"
check_present "$PLAN" "lint" "Planner defines lint command"

echo ""
echo "=== 30. CROSS-FILE: State machine consistency ==="
# Verify all states mentioned in GEMINI.md are handled in orchestrator
for state in "orchestrator_turn" "worker_running" "handoff_review" "paused" "completed" "failed"; do
  check_present "GEMINI.md" "$state" "GEMINI.md mentions state: $state"
done
# Verify orchestrator handles all Decision Tree options mentioned in GEMINI.md
for opt in "Option A" "Option B" "Option C" "Option D" "Clean"; do
  check_present "GEMINI.md" "$opt" "GEMINI.md mentions decision: $opt"
done

echo ""
echo "=== 31. VALIDATE STATE SCRIPT ==="
if bash scripts/validate-state.sh 076af0 2>&1 | rg -q "VALID"; then
  pass "validate-state.sh passes on test mission"
else
  fail "validate-state.sh fails on test mission"
fi

echo ""
echo "=== 29. SCAFFOLD + VALIDATE ROUND-TRIP ==="
test_id="q$(date +%s | tail -c 6)"
test_dir="/tmp/scaffold-test-$$"
mkdir -p "$test_dir"
if bash scripts/scaffold-mission.sh "$test_id" "$test_dir" >/dev/null 2>&1; then
  if bash scripts/validate-state.sh "$test_id" 2>&1 | rg -q "VALID"; then
    pass "Scaffold → validate round-trip passes"
  else
    fail "Scaffolded state.json fails validation"
  fi
  rm -rf "$HOME/.gemini-mc/missions/mis_${test_id}"
else
  fail "scaffold-mission.sh failed"
fi
rm -rf "$test_dir"

echo ""
echo "=== SUMMARY ==="
echo "Errors: $ERRORS"
echo "Warnings: $WARNINGS"

if [ "$ERRORS" -gt 0 ]; then
  echo "QUALITY CHECK FAILED"
  exit 1
else
  echo "QUALITY CHECK PASSED"
  exit 0
fi
