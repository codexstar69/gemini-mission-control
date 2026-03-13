---
name: mission-orchestrator
description: Autonomous orchestrator run loop for dispatching workers and managing mission execution
---

# Mission Orchestrator

Drives the autonomous run loop: read state → evaluate DAG → dispatch worker → parse handoff → decide → update → check milestones → loop.

## When to Activate
- `/mission-run` with state=`orchestrator_turn`
- `/mission-resume` after pause
- Re-entry after crash recovery

## Prerequisites
1. Mission dir exists at `~/.gemini-mc/missions/mis_<id>/`
2. `state.json` state is `orchestrator_turn` (or `worker_running` for crash recovery)
3. `features.json` has features
4. `workingDirectory` is accessible

---

## Step 1: Read State & Crash Recovery

Read from mission dir: `state.json`, `features.json`, `progress_log.jsonl`, `AGENTS.md`, `validation-contract.md`.

**Crash recovery** (if state=`worker_running`):
1. Find stuck features: scan `progress_log.jsonl` for `worker_started` without matching `worker_completed`
2. Reset stuck features to `pending` in `features.json`
3. Set state to `orchestrator_turn`, log `crash_recovery` event
4. Log state transition

**Early exits:**
- Empty features array → transition to `completed`, exit
- All features `cancelled` → transition to `completed`, exit

---

## Step 2: Evaluate Feature DAG

Find features where: `status=="pending"` AND all `preconditions` have `status=="completed"`.

Select **first** ready feature in array order (position = priority).

**No ready features:**
- No pending features at all → proceed to Step 8 (check completion)
- Pending but none ready (deadlock) → log `deadlock_detected`, transition to `paused`, request user help

---

## Step 3: Construct Worker Prompt

Include in worker prompt:

1. **Feature context**: `id`, `description`, `expectedBehavior`, `verificationSteps`, `fulfills`
2. **Project enrichment** from `<workingDirectory>/.mission/`:
   - `.mission/services.yaml` — full contents (warn if missing)
   - `.mission/library/*.md` — all library files
   - `.mission/skills/<skillName>/SKILL.md` — per-mission worker skill if exists
   - Mission `AGENTS.md` — worker guidance and boundaries
3. **Validation assertions**: extract relevant VAL-XXX-NNN descriptions from `validation-contract.md` for items in feature's `fulfills`
4. **Agent mapping**: `skillName` maps directly to agent name (`mission-worker`, `code-quality-worker`, `scrutiny-validator`, `user-testing-validator`). Unknown skillName → check `agents/<skillName>.md`, fallback to `mission-worker`.
5. **init.sh**: For first worker in session, instruct to run `bash <workingDirectory>/.mission/init.sh` (idempotent)

---

## Step 4: Dispatch Worker

1. Set state to `worker_running`, update `updatedAt`
2. Log `worker_started` event: `{"timestamp":"...","event":"worker_started","featureId":"...","agentName":"...","skillName":"..."}`
3. Call worker agent via native subagent dispatch with enriched prompt
4. Wait for completion

---

## Step 5: Parse Structured Handoff

Extract JSON handoff from worker response. Required fields:
- `salientSummary` (string, non-empty)
- `whatWasImplemented` (string, ≥50 chars)
- `whatWasLeftUndone` (string, empty if complete)
- `verification.commandsRun` (array, ≥1 entry with `command`, `exitCode`, `observation`)
- `discoveredIssues` (array, each: `severity` high/medium/low, `description`, `suggestedFix`)

Optional: `verification.interactiveChecks`, `tests.added`, `tests.coverage`.

If malformed/missing → treat as Option B failure.

Write handoff to `handoffs/<feature-id>.json`. Set state to `handoff_review`. Log `worker_completed`.

---

## Step 6: Decision Tree

Evaluate in order:

### Option A — High-severity issues found
**Trigger:** `discoveredIssues` has `severity:"high"` items.
**Action:**
1. Create follow-up feature(s) at TOP of features array
2. **Sealed check:** if feature's milestone is in `sealedMilestones`, redirect to `misc-*` milestone
3. Follow-up fields: `id`=`fix-<orig>-<N>`, `preconditions`=[original], `fulfills`=[], `status`=`pending`
4. Mark original `completed`, increment `completedFeatures`, update `totalFeatures`

### Option B — Worker failure
**Trigger:** Non-empty `whatWasLeftUndone` + failing exit codes, OR malformed handoff.
**Action:**
1. Reset feature to `pending`, prepend `[RETRY]` context to description
2. Log `feature_retry` event
3. After 3 retries → log `feature_escalation`, transition to `paused`

### Option C — Partial completion
**Trigger:** Non-empty `whatWasLeftUndone` + some passing results, no high-severity issues.
**Action:**
1. Update description: `[PARTIAL] Completed: ... Remaining: ...`
2. Keep `pending` for re-dispatch. Log `feature_partial`.

### Option D — Medium/low issues only
**Trigger:** Only medium/low `discoveredIssues`, empty `whatWasLeftUndone`, passing verification.
**Action:**
1. Mark original `completed`, increment `completedFeatures`
2. Create misc features in `misc-*` milestone (max 5 per misc milestone, overflow to `misc-N+1`)
3. Misc feature: `skillName`=`code-quality-worker`, `preconditions`=[], `fulfills`=[]

### Clean Success
**Trigger:** No issues, empty `whatWasLeftUndone`, all exit codes 0.
**Action:** Mark `completed`, increment `completedFeatures`. No new features.

---

## Step 7: Update State & Log

1. Write updated `features.json`
2. Update `state.json`: state=`orchestrator_turn`, increment counters, update `updatedAt`
3. Log `state_transition` event with decision option
4. Write `messages.jsonl` entry: `{"sender":"orchestrator","type":"feature_completed","content":"<salientSummary>"}`

---

## Step 8: Milestone Completion & Validators

### 8.1 Check milestone completion
After feature completes, check its milestone: are ALL implementation features (not `scrutiny-validator-*` or `user-testing-validator-*`) `completed` or `cancelled`?

### 8.2 Inject validators
If all impl features done AND milestone NOT in `milestonesWithValidationPlanned`:
- Skip if ALL impl features are `cancelled` (no validation needed)
- Create `scrutiny-validator-<milestone>` feature: `skillName`=`scrutiny-validator`, `preconditions`=[]
- Create `user-testing-validator-<milestone>` feature: `skillName`=`user-testing-validator`, `preconditions`=[`scrutiny-validator-<milestone>`]
- Add milestone to `milestonesWithValidationPlanned`, increment `totalFeatures` by 2
- Log `milestone_completed` and `validation_injected` events

### 8.3 Seal milestones
After `user-testing-validator-<milestone>` completes successfully:
- Add milestone to `sealedMilestones`
- Log `milestone_sealed` event
- Write `validation_result` message

**Sealed milestone enforcement:** Never add features to sealed milestones. All Option A follow-ups and Option D misc features targeting sealed milestones → redirect to `misc-*`. Log `sealed_milestone_rejected` if attempted.

### 8.4 Mission completion
All features `completed`/`cancelled` + all milestones sealed → state=`completed`, exit loop.
Otherwise → loop back to Step 1.

---

## Scope Change Protocol

### Add requirement
1. Create VAL assertion in `validation-contract.md`
2. Create feature with `fulfills` referencing it
3. Init assertion as `pending` in `validation-state.json`
4. If target milestone sealed → redirect to `misc-*`
5. Enforce coverage gate. Log `scope_change`.

### Remove requirement
1. Mark assertion `[REMOVED]` in contract, set status to `passed` in validation-state
2. Remove from feature `fulfills` arrays
3. Consider cancelling features with empty `fulfills`. Log `scope_change`.

### Modify requirement
1. Update assertion description in contract
2. Reset assertion to `pending` in validation-state
3. Create follow-up feature if needed. Log `scope_change`.

---

## Budget Enforcement

Track approximate token usage per dispatch cycle. When budget exceeded:
1. State → `paused`. Log `budget_pause`.
2. Exit loop. Resume requires explicit user acknowledgment.

---

## Research Delegation

When feature needs external knowledge not in `.mission/library/`:
1. `google_web_search` for documentation
2. Save raw results to `.mission/research/<topic>.md`
3. Distill into `.mission/library/<topic>.md`
4. Log `research_completed`

---

## Feature Cancellation

Feature cancellation is a terminal state — cancelled features are never re-dispatched.
1. Set `status`=`cancelled`, move to bottom of array
2. Cancelled = "done" for precondition purposes
3. All features cancelled in milestone → milestone complete (no validation)
4. Log `feature_cancelled`

---

## Misc Milestones

Max 5 features per `misc-*` milestone. When full, create `misc-N+1`. Misc milestones follow same validation lifecycle.

---

## Pause / Resume

**Pause:** Complete current state updates, set state=`paused`, log transition, exit loop.
**Resume:** Verify state=`paused`, budget ack if needed, set state=`orchestrator_turn`, re-enter at Step 1.

---

## Inter-Agent Messaging

Append to `messages.jsonl`: `{"timestamp":"...","sender":"...","type":"...","content":"..."}`.

Senders: `orchestrator`, `mission-worker`, `scrutiny-validator`, `user-testing-validator`.
Types: `feature_completed`, `worker_dispatched`, `validation_result`, `scope_change`, `research_available`, `user_instruction`, `error_report`.

Write messages at: dispatch (Step 4), completion (Step 7), milestone events (Step 8), scope changes, research, errors.

---

## Validation Override

When `/mission-override "<justification>"` is invoked:
1. Require non-empty justification
2. Find failed validator features (`scrutiny-validator-*` or `user-testing-validator-*` with `pending` status)
3. Mark as `completed`, increment `completedFeatures`
4. Record in synthesis report: `{"overridden":true,"overriddenAt":"...","justification":"...","originalStatus":"..."}`
5. Seal milestone (override = validators passed)
6. Log `validation_overridden` event, write `validation_result` message
7. Override does NOT change `validation-state.json` — failed assertions stay `failed`
8. If mission was `paused` → transition to `orchestrator_turn`
