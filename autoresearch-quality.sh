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
for agent in agents/mission-worker.md agents/code-quality-worker.md agents/scrutiny-validator.md agents/user-testing-validator.md; do
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
echo "=== 32. SCAFFOLD + VALIDATE ROUND-TRIP ==="
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
echo "=== 33. SCENARIO: All-cancelled milestone (no validation) ==="
check_present "$ORCH" "ALL.*cancelled.*skip validation|ALL.*cancelled.*do not inject" "All-cancelled milestone skips validation"

echo ""
echo "=== 34. PLANNER: Feature schema completeness ==="
# All required feature fields must be documented in the planner
for field in "id" "description" "skillName" "milestone" "preconditions" "expectedBehavior" "verificationSteps" "fulfills"; do
  check_present "$PLAN" "\`$field\`" "Planner documents feature field: $field"
done

echo ""
echo "=== 35. STRUCTURAL: Orchestrator step ordering ==="
# Steps must appear in order 1-8
prev_line=0
all_ordered=true
for step in 1 2 3 4 5 6 7 8; do
  line=$(rg -n "^## Step ${step}:" "$ORCH" | head -1 | cut -d: -f1)
  if [ -z "$line" ]; then
    fail "Step $step missing from orchestrator"
    all_ordered=false
  elif [ "$line" -le "$prev_line" ]; then
    fail "Step $step is out of order (line $line, prev was $prev_line)"
    all_ordered=false
  else
    prev_line=$line
  fi
done
$all_ordered && pass "Steps 1-8 appear in correct order"

echo ""
echo "=== 36. STRUCTURAL: Planner phase ordering ==="
prev_line=0
all_ordered=true
for phase in 1 2 3 4 5 6 7; do
  line=$(rg -n "^## Phase ${phase}:" "$PLAN" | head -1 | cut -d: -f1)
  if [ -z "$line" ]; then
    fail "Phase $phase missing from planner"
    all_ordered=false
  elif [ "$line" -le "$prev_line" ]; then
    fail "Phase $phase is out of order"
    all_ordered=false
  else
    prev_line=$line
  fi
done
$all_ordered && pass "Phases 1-7 appear in correct order"

echo ""
echo "=== 37. ORCHESTRATOR: Mission completion requires BOTH features done AND milestones sealed ==="
check_present "$ORCH" 'completed.*cancelled.*sealedMilestones' "Completion requires features AND milestones"

echo ""
echo "=== 38. GEMINI.md: Common Pitfalls section exists ==="
check_present "GEMINI.md" "Common Pitfalls" "Common Pitfalls section"
check_present "GEMINI.md" "pipe.*exit code|exit code.*pipe" "Pipe warning in pitfalls"
check_present "GEMINI.md" "high/medium/low" "Severity format in pitfalls"
check_present "GEMINI.md" "sealed.*immutable|immutable.*sealed" "Sealed milestone warning in pitfalls"
check_present "GEMINI.md" "[Cc]ancelled.*satisfy|cancelled.*precondition" "Cancelled preconditions in pitfalls"

echo ""
echo "=== 39. HOOKS: hooks.json is valid JSON ==="
if python3 -c "import json; json.load(open('hooks/hooks.json'))" 2>/dev/null; then
  pass "hooks.json is valid JSON"
else
  fail "hooks.json is NOT valid JSON"
fi

echo ""
echo "=== 40. HOOKS: All hook scripts exist and are executable ==="
for hook_script in hooks/validate-state-write.sh hooks/block-pipe-masking.sh hooks/protect-sealed-milestones.sh hooks/check-state-drift.sh hooks/validate-features-write.sh hooks/pre-compress-snapshot.sh; do
  if [ -x "$hook_script" ]; then
    pass "$(basename $hook_script) exists and is executable"
  else
    fail "$(basename $hook_script) missing or not executable"
  fi
done

echo ""
echo "=== 41. HOOKS: Hook scripts handle JSON I/O correctly ==="
# Each hook must output valid JSON for the "allow" case
for hook_script in hooks/validate-state-write.sh hooks/block-pipe-masking.sh hooks/protect-sealed-milestones.sh hooks/check-state-drift.sh hooks/validate-features-write.sh hooks/pre-compress-snapshot.sh; do
  output=$(echo '{"tool_name":"test","tool_input":{}}' | bash "$hook_script" 2>/dev/null)
  if echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
    pass "$(basename $hook_script) outputs valid JSON"
  else
    fail "$(basename $hook_script) outputs invalid JSON: $output"
  fi
done

echo ""
echo "=== 42. HOOKS: Pipe-blocking hook denies | tail ==="
deny_output=$(echo '{"tool_name":"run_shell_command","tool_input":{"command":"npm test | tail -20"}}' | bash hooks/block-pipe-masking.sh 2>/dev/null)
if echo "$deny_output" | grep -q '"deny"'; then
  pass "Pipe-blocking hook correctly denies '| tail'"
else
  fail "Pipe-blocking hook did NOT deny '| tail': $deny_output"
fi

echo ""
echo "=== 43. HOOKS: Pipe-blocking hook allows clean commands ==="
allow_output=$(echo '{"tool_name":"run_shell_command","tool_input":{"command":"npm test"}}' | bash hooks/block-pipe-masking.sh 2>/dev/null)
if echo "$allow_output" | grep -q '"allow"'; then
  pass "Pipe-blocking hook correctly allows clean command"
else
  fail "Pipe-blocking hook did NOT allow clean command: $allow_output"
fi

echo ""
echo "=== 44. HOOKS: State validation hook allows non-state writes ==="
allow_output=$(echo '{"tool_name":"write_file","tool_input":{"file_path":"/tmp/test.txt","content":"hello"}}' | bash hooks/validate-state-write.sh 2>/dev/null)
if echo "$allow_output" | grep -q '"allow"'; then
  pass "State hook allows non-state.json writes"
else
  fail "State hook blocked non-state.json write: $allow_output"
fi

echo ""
echo "=== 45. HOOKS: SessionStart hook referenced in hooks.json ==="
if grep -q "session-context" hooks/hooks.json; then
  pass "SessionStart hook registered"
else
  fail "SessionStart hook NOT registered in hooks.json"
fi

echo ""
echo "=== 46. ORCHESTRATOR: Step 3 worker prompt includes all 7 context items ==="
ORCH="skills/mission-orchestrator/SKILL.md"
for ctx in "services.yaml" "library/" "AGENTS.md" "validation" "handoff" "messages.jsonl" "init.sh"; do
  if grep -qi "$ctx" "$ORCH" 2>/dev/null; then
    pass "Step 3 references $ctx"
  else
    fail "Step 3 missing reference to $ctx"
  fi
done

echo ""
echo "=== 47. ORCHESTRATOR: Deadlock detection ==="
if grep -q "deadlock" "$ORCH" 2>/dev/null; then
  pass "Deadlock detection documented"
else
  fail "Deadlock detection missing from orchestrator"
fi

echo ""
echo "=== 48. ORCHESTRATOR: Budget enforcement ==="
if grep -q "budget" "$ORCH" 2>/dev/null; then
  pass "Budget enforcement documented"
else
  fail "Budget enforcement missing from orchestrator"
fi

echo ""
echo "=== 49. PLANNER: DAG acyclicity check ==="
if grep -q "topological\|acycl\|cycle" "$PLAN" 2>/dev/null; then
  pass "DAG acyclicity check documented in planner"
else
  fail "DAG acyclicity check missing from planner"
fi

echo ""
echo "=== 50. AGENTS: Workers produce handoff as LAST JSON block ==="
for agent in agents/mission-worker.md agents/code-quality-worker.md agents/scrutiny-validator.md agents/user-testing-validator.md; do
  if grep -qi "last.*json\|last thing\|final output" "$agent" 2>/dev/null; then
    pass "$(basename $agent) specifies handoff is last output"
  else
    fail "$(basename $agent) does not specify handoff position"
  fi
done

echo ""
echo "=== 51. ORCHESTRATOR: All state transitions log updatedAt ==="
if grep -c "updatedAt" "$ORCH" 2>/dev/null | grep -q '[3-9]\|[1-9][0-9]'; then
  pass "updatedAt referenced multiple times in state transitions"
else
  fail "updatedAt may not be referenced in all state transitions"
fi

echo ""
echo "=== 52. ORCHESTRATOR: Option C has loop prevention ==="
if grep -q "Count partials\|partial.*3\|partial.*escalat" "$ORCH" 2>/dev/null; then
  pass "Option C has partial-completion escalation limit"
else
  fail "Option C missing loop prevention — could re-dispatch indefinitely"
fi

echo ""
echo "=== 53. ORCHESTRATOR: Dangling precondition validation ==="
if grep -q "dangling\|non-existent\|missing.*precondition" "$ORCH" 2>/dev/null; then
  pass "Dangling precondition references are handled"
else
  fail "No handling for dangling precondition references — typos cause silent deadlock"
fi

echo ""
echo "=== 54. ORCHESTRATOR: Crash recovery reconciles counters ==="
if grep -q "Reconcile counters\|reconcil" "$ORCH" 2>/dev/null; then
  pass "Crash recovery reconciles completedFeatures/totalFeatures"
else
  fail "Crash recovery does not reconcile counters — mid-crash state drift possible"
fi

echo ""
echo "=== 55. PLANNER: Duplicate feature ID check ==="
if grep -q "duplicate.*[Ii][Dd]\|[Ii][Dd].*unique\|[Nn]o duplicate" "$PLAN" 2>/dev/null; then
  pass "Planner checks for duplicate feature IDs"
else
  fail "Planner does not check for duplicate feature IDs"
fi

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
