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
- **Single-session constraint:** only one orchestrator session should run per mission at a time. Concurrent sessions on the same mission can corrupt state.

## Prerequisites
1. Mission dir exists at `~/.gemini-mc/missions/mis_<id>/`
2. `state.json` state is `orchestrator_turn` (or `worker_running` for crash recovery)
3. `features.json` has at least one feature
4. `workingDirectory` from `state.json` is accessible. **If not accessible:** set state to `"failed"`, log `{"event":"fatal_error","reason":"workingDirectory not accessible: <path>"}`, inform user, exit.

---

## Step 1: Read State & Crash Recovery

Read these files from the mission directory:
- `state.json` — current state, counters, sealed milestones
- `features.json` — feature list with statuses and DAG
- `progress_log.jsonl` — event history (for crash recovery and retry counting)
- `AGENTS.md` — worker guidance
- `validation-contract.md` — behavioral assertions

**Crash recovery** — if `state.json` shows state=`worker_running`:
1. Scan `progress_log.jsonl` for `worker_started` events that have no matching `worker_completed` event **with the same `featureId`**
2. For each stuck feature, reset its `status` to `"pending"` in `features.json`
3. **Reconcile counters:** count all features with `status: "completed"` in `features.json` and set `completedFeatures` in `state.json` to that count. Count total features and set `totalFeatures`. This handles the case where a previous session crashed between writing features.json and state.json.
4. Set `state.json` state to `"orchestrator_turn"`, update `updatedAt` to current ISO 8601 timestamp
5. Append to `progress_log.jsonl`: `{"timestamp":"<ISO 8601>","event":"crash_recovery","recoveredFeatures":["<featureId>",...]}`

**Early exits:**
- Features array is empty → set state to `"completed"`, update `updatedAt`, exit loop
- All features have status `"cancelled"` → set state to `"completed"`, update `updatedAt`, exit loop

---

## Step 2: Evaluate Feature DAG

**Pre-check: validate precondition references.** For each feature, verify that every ID in its `preconditions` array matches the `id` of another feature in `features.json`. If a precondition references a non-existent feature ID, this is a **dangling reference** — log a warning (`{"event":"dangling_precondition","featureId":"<id>","missingPrecondition":"<missing-id>"}`) and treat that precondition as satisfied (so the feature is not permanently blocked by a typo).

A feature is **ready** when:
- Its `status` is `"pending"`
- ALL of its `preconditions` reference features whose `status` is `"completed"` **or** `"cancelled"` (cancelled features count as satisfied dependencies)

Select the **first** ready feature in array order. Array position determines priority — features earlier in the array are dispatched first.

**No ready features found:**
- If no features have status `"pending"` at all → proceed directly to Step 8 (check mission completion)
- If pending features exist but none are ready (all blocked by unfinished preconditions) → this is a **deadlock**. Append `{"timestamp":"<ISO>","event":"deadlock_detected","blockedFeatures":["<id>",...],"waitingOn":["<id>",...]}` to progress log, set state to `"paused"`, inform the user which features are blocked and what they're waiting on

---

## Step 3: Construct Worker Prompt

Build an enriched prompt for the worker agent. Structure the prompt clearly with labeled sections so the worker can find each piece of context:

1. **Feature assignment** — the full feature object: `id`, `description`, `expectedBehavior`, `verificationSteps`, `fulfills`
2. **Project context** from `<workingDirectory>/.mission/`:
   - `services.yaml` — include full contents. If missing, include a warning in the prompt.
   - `library/*.md` — include all library files
   - `skills/<skillName>/SKILL.md` — include the per-mission skill if it exists for this worker type
   - Mission `AGENTS.md` — include worker guidance and boundaries
3. **Relevant validation assertions** — for each VAL-XXX-NNN in the feature's `fulfills` array, extract the full assertion text from `validation-contract.md` and include it
4. **Agent selection** — the feature's `skillName` field maps to the agent name:
   - `mission-worker` → `agents/mission-worker.md`
   - `code-quality-worker` → `agents/code-quality-worker.md`
   - `scrutiny-validator` → `agents/scrutiny-validator.md`
   - `user-testing-validator` → `agents/user-testing-validator.md`
   - Unknown skillName → check if `agents/<skillName>.md` exists; if not, fall back to `mission-worker`
5. **Handoff context** — if the feature has preconditions, read the handoff files (`handoffs/<precondition-id>.json`) for each completed precondition and include their `salientSummary` in the prompt. This gives the worker context about what was already built.
6. **Recent messages** — read the last 10 entries from `messages.jsonl` and include any that contain warnings, discoveries, or user instructions relevant to this feature.
7. **Environment setup** — for the first worker dispatch in this session, include instruction to run `bash <workingDirectory>/.mission/init.sh` (this script is idempotent)

---

## Step 4: Dispatch Worker

1. Update `state.json`: set state to `"worker_running"`, update `updatedAt`
2. Append to `progress_log.jsonl`: `{"timestamp":"<ISO 8601>","event":"worker_started","featureId":"<id>","agentName":"<agent>","skillName":"<skill>"}`
3. Dispatch the worker subagent with the enriched prompt from Step 3
4. Wait for the worker to complete and return its response
5. **If the worker times out or returns no response:** treat as a malformed handoff (→ Option B failure in Step 6). The crash recovery mechanism in Step 1 also handles this if the orchestrator itself is interrupted.

---

## Step 5: Parse Structured Handoff

The worker's response ends with a JSON code block containing the handoff. Find the **last** JSON code block in the response (workers produce the handoff as their final output). Parse it as the handoff.

**Required handoff fields:**
- `salientSummary` — string, non-empty, 1–4 sentences
- `whatWasImplemented` — string, at least 50 characters, referencing specific files
- `whatWasLeftUndone` — string, empty if everything is complete
- `verification.commandsRun` — array with at least 1 entry, each having `command` (string), `exitCode` (integer), `observation` (string)
- `discoveredIssues` — array (can be empty), each entry having `severity` ("high"/"medium"/"low"), `description` (string), `suggestedFix` (string)

**Optional fields:** `verification.interactiveChecks`, `tests.added`, `tests.coverage`

**If the handoff is malformed or missing** → treat the entire dispatch as an Option B failure (see Step 6).

After successful parsing:
1. Write the handoff JSON to `handoffs/<feature-id>.json`
2. Update `state.json`: set state to `"handoff_review"`, update `updatedAt`
3. Append to `progress_log.jsonl`: `{"timestamp":"<ISO 8601>","event":"worker_completed","featureId":"<id>"}`

---

## Step 6: Decision Tree

Evaluate the handoff against these options **in order**. Apply the **first** matching option only.

### Option A — High-severity issues discovered
**Trigger:** The `discoveredIssues` array contains at least one entry with `severity: "high"` AND `whatWasLeftUndone` is empty (the worker completed the feature but found high-severity issues during implementation).
**If high-severity + non-empty `whatWasLeftUndone`:** This means the worker could not complete AND found severe issues. Treat as **Option B** (failure) instead, with the high-severity issues noted in the retry context.
**Action:**
1. For each high-severity issue (or group related issues), create a follow-up feature
2. Insert follow-up feature(s) at the **TOP** of the `features` array (highest priority)
3. **Sealed milestone check:** if the original feature's milestone is in `sealedMilestones`, assign the follow-up to a `misc-*` milestone instead. Never add to a sealed milestone.
4. Follow-up feature fields (ALL required):
   - `id`: `"fix-<original-feature-id>-<issue-index>"` (e.g., `fix-user-auth-001`). If this ID already exists in `features.json`, append a timestamp suffix: `fix-<original-feature-id>-<issue-index>-<epoch>`
   - `description`: issue description + suggested fix from handoff
   - `skillName`: same as original (or `code-quality-worker` for quality issues). **Exception:** if the original was a validator (`scrutiny-validator` or `user-testing-validator`), use `code-quality-worker` for the follow-up.
   - `milestone`: same as original (or `misc-*` if milestone is sealed)
   - `preconditions`: `["<original-feature-id>"]`
   - `expectedBehavior`: `["<issue resolution criteria from discoveredIssues>"]`
   - `verificationSteps`: copy from original feature (or add specific verification for the fix)
   - `fulfills`: `[]`
   - `status`: `"pending"`
5. Mark the original feature as `"completed"` in `features.json`
6. Increment `completedFeatures` in `state.json`
7. Update `totalFeatures` in `state.json` to reflect newly added feature(s)

### Option B — Worker failure
**Trigger:** Non-empty `whatWasLeftUndone` AND `verification.commandsRun` contains entries with non-zero `exitCode`, OR the handoff was malformed/missing.
**Action:**
1. Keep the feature's status as `"pending"` (do NOT mark completed)
2. Update the feature's `description`: prepend `[RETRY] Previous attempt failed: <whatWasLeftUndone>. Error: <relevant verification output>.` to the existing description
3. Append to `progress_log.jsonl`: `{"timestamp":"...","event":"feature_retry","featureId":"<id>","reason":"<brief reason>"}`
4. **Count retries:** scan `progress_log.jsonl` for `feature_retry` events with this `featureId`. If count reaches 3:
   - Append: `{"timestamp":"...","event":"feature_escalation","featureId":"<id>","retries":3}`
   - Set state to `"paused"`, update `updatedAt`
   - Inform user: "Feature `<id>` has failed 3 times. Manual intervention required."
   - Exit the loop

### Option C — Partial completion
**Trigger:** Non-empty `whatWasLeftUndone` AND `verification.commandsRun` has at least some entries with `exitCode: 0` (partial success), AND no high-severity issues in `discoveredIssues`.
**Action:**
1. Update the feature's `description`: `[PARTIAL] Completed: <whatWasImplemented>. Remaining: <whatWasLeftUndone>.`
2. Keep the feature's status as `"pending"` for re-dispatch
3. Append to `progress_log.jsonl`: `{"timestamp":"...","event":"feature_partial","featureId":"<id>","implemented":"<whatWasImplemented>","remaining":"<whatWasLeftUndone>"}`
4. **Count partials:** scan `progress_log.jsonl` for `feature_partial` events with this `featureId`. If count reaches 3:
   - The feature is making progress but never finishing. Treat as **Option B failure** with `whatWasLeftUndone` as the reason. This triggers Option B's retry counter and eventual escalation to the user.

### Option D — Medium/low-severity issues only
**Trigger:** `discoveredIssues` contains ONLY `"medium"` or `"low"` severity entries (no `"high"`), AND `whatWasLeftUndone` is empty, AND all `exitCode` values are 0.
**Action:**
1. Mark the original feature as `"completed"`, increment `completedFeatures`
2. For each medium/low issue, create a feature in a `misc-*` milestone:
   - Find the current misc milestone by scanning `features.json` for features with `milestone` starting with `misc-`. If none exist, create `misc-1`.
   - If the current misc milestone already has 5 features, create the next one (`misc-2`, `misc-3`, ...)
   - Set: `skillName`=`"code-quality-worker"` (or `"mission-worker"` if implementation needed), `preconditions`=`[]`, `fulfills`=`[]`, `status`=`"pending"`
3. Update `totalFeatures` to reflect new features

### Clean Success — No issues at all
**Trigger:** `discoveredIssues` is empty, `whatWasLeftUndone` is empty, ALL `exitCode` values are 0.
**Action:**
1. Mark the feature as `"completed"` in `features.json`
2. Increment `completedFeatures` in `state.json`
3. No new features created

---

## Step 7: Update State & Log

After applying the decision tree:

1. Write the updated `features.json` to disk
2. Update `state.json`:
   - Set state back to `"orchestrator_turn"`
   - Increment `completedFeatures` if a feature was marked completed. Increment `totalFeatures` if new features were created (Option A follow-ups or Option D misc features).
   - Update `updatedAt` to current ISO 8601 timestamp
3. Append to `progress_log.jsonl`: `{"timestamp":"...","event":"state_transition","from":"handoff_review","to":"orchestrator_turn","decision":"<Option A/B/C/D/Clean>","featureId":"<id>"}`
4. Append to `messages.jsonl`: `{"timestamp":"...","sender":"orchestrator","type":"feature_completed","content":"<salientSummary from handoff>"}`

**IMPORTANT:** Every time you modify `state.json`, always update the `updatedAt` field to the current ISO 8601 timestamp.

---

## Step 8: Milestone Completion & Validators

### 8.1 Check milestone completion
After the just-completed feature's status changes, check its milestone: are ALL **implementation features** in that milestone now `"completed"` or `"cancelled"`?

Implementation features = all features in the milestone EXCEPT those whose `id` starts with `scrutiny-validator-` or `user-testing-validator-`.

### 8.2 Inject validators
If all implementation features in the milestone are done AND the milestone is NOT already in `milestonesWithValidationPlanned`:

- **Exception:** if ALL implementation features are `"cancelled"` (no actual work was done), skip validation entirely — do not inject validators
- Create two validator features with ALL required fields:
  1. `scrutiny-validator-<milestone>`:
     - `id`: `"scrutiny-validator-<milestone>"`
     - `description`: `"Run scrutiny validation for milestone <milestone>"`
     - `skillName`: `"scrutiny-validator"`
     - `milestone`: `"<milestone>"`
     - `preconditions`: `[]`
     - `expectedBehavior`: `["Hard-gate passes (test/typecheck/lint)", "No blocking findings in code review"]`
     - `verificationSteps`: `[]`
     - `fulfills`: `[]`
     - `status`: `"pending"`
  2. `user-testing-validator-<milestone>`:
     - `id`: `"user-testing-validator-<milestone>"`
     - `description`: `"Run user-testing validation for milestone <milestone>"`
     - `skillName`: `"user-testing-validator"`
     - `milestone`: `"<milestone>"`
     - `preconditions`: `["scrutiny-validator-<milestone>"]`
     - `expectedBehavior`: `["All in-scope VAL assertions pass or are blocked with documented reason"]`
     - `verificationSteps`: `[]`
     - `fulfills`: `[]`
     - `status`: `"pending"`
- Add the milestone to `milestonesWithValidationPlanned` array in `state.json`
- Increment `totalFeatures` by 2 in `state.json`
- Append to `progress_log.jsonl`: `{"event":"milestone_completed","milestone":"<name>"}` and `{"event":"validation_injected","milestone":"<name>","validators":["scrutiny-validator-<ms>","user-testing-validator-<ms>"]}`

### 8.3 Seal milestones
After `user-testing-validator-<milestone>` completes with a successful handoff (Clean Success or Option D — no high-severity issues):
- Add the milestone to `sealedMilestones` array in `state.json`
- Append to `progress_log.jsonl`: `{"event":"milestone_sealed","milestone":"<name>"}`
- Append to `messages.jsonl`: `{"sender":"orchestrator","type":"validation_result","content":"Milestone <name> validation passed and sealed"}`

**Sealed milestone enforcement:** NEVER add new features to a sealed milestone. If Option A follow-ups or Option D misc features would target a sealed milestone, redirect them to a `misc-*` milestone instead. If this happens, append `{"event":"sealed_milestone_rejected","milestone":"<name>","redirectedTo":"misc-N"}` to the progress log.

### 8.4 Mission completion check
After all Step 8 processing, check: are ALL features in `features.json` either `"completed"` or `"cancelled"`, AND are all milestones with completed implementation features present in `sealedMilestones`?

If yes: set state to `"completed"`, update `updatedAt`, exit the loop.
If no: loop back to Step 1.

---

## Scope Change Protocol

### Add a new requirement
1. Create a new VAL-XXX-NNN assertion in `validation-contract.md`
2. Create a new feature with `fulfills` referencing the new assertion
3. Initialize the assertion as `{"status":"pending"}` in `validation-state.json`
4. If the target milestone is sealed → redirect the feature to a `misc-*` milestone
5. Verify the coverage gate still holds (every VAL ID claimed by exactly one feature)
6. Append `{"event":"scope_change","action":"add","assertionId":"VAL-XXX-NNN"}` to progress log

### Remove a requirement
1. Mark the assertion with `[REMOVED]` prefix in `validation-contract.md`
2. Set the assertion's status to `"passed"` in `validation-state.json`
3. Remove the assertion ID from all features' `fulfills` arrays
4. If a feature now has an empty `fulfills` array and no other purpose, consider cancelling it
5. Append `{"event":"scope_change","action":"remove","assertionId":"VAL-XXX-NNN"}` to progress log

### Modify a requirement
1. Update the assertion description in `validation-contract.md`
2. Reset the assertion status to `"pending"` in `validation-state.json`
3. If the change affects implementation, create a follow-up feature
4. Append `{"event":"scope_change","action":"modify","assertionId":"VAL-XXX-NNN"}` to progress log

---

## Budget Enforcement

Track approximate token usage across dispatch cycles. When the estimated budget is exceeded:
1. Set state to `"paused"`, update `updatedAt`
2. Append `{"event":"budget_pause","estimatedTokens":"<count>"}` to progress log
3. Exit the loop immediately
4. Resume requires explicit user acknowledgment via `/mission-resume`

---

## Research Delegation

When a feature requires external knowledge not available in `.mission/library/`:
1. Use `google_web_search` to find relevant documentation or examples
2. Save the raw search results to `.mission/research/<topic>.md`
3. Distill the key findings into a focused `.mission/library/<topic>.md` file
4. Append `{"event":"research_completed","topic":"<topic>"}` to progress log

---

## Feature Cancellation

Feature cancellation is a **terminal state** — cancelled features are never re-dispatched.

1. Set the feature's `status` to `"cancelled"` in `features.json`
2. Move the feature to the bottom of the features array (lowest priority)
3. Cancelled features count as "done" for precondition evaluation (other features waiting on them can proceed)
4. If ALL features in a milestone are `"cancelled"` → milestone is complete with no validation needed
5. Append `{"event":"feature_cancelled","featureId":"<id>","reason":"<reason>"}` to progress log

---

## Misc Milestones

Misc milestones (`misc-1`, `misc-2`, etc.) hold medium/low-severity follow-up features from Option D.

- Maximum 5 features per misc milestone. When a misc milestone reaches 5 features, create `misc-N+1`.
- Misc milestones follow the same validation lifecycle as regular milestones (validators are injected when all features complete, milestone is sealed after validation passes).

---

## Pause / Resume

**Pause:** Complete any in-progress state updates, set state to `"paused"`, log the transition, exit the loop.
**Resume:** Verify state is `"paused"`. If paused due to budget, require explicit user acknowledgment. Set state to `"orchestrator_turn"`, re-enter the loop at Step 1.

---

## Inter-Agent Messaging

Append messages to `messages.jsonl` with this format:
```json
{"timestamp":"<ISO 8601>","sender":"<sender>","type":"<type>","content":"<content>"}
```

**Senders:** `orchestrator`, `mission-worker`, `scrutiny-validator`, `user-testing-validator`
**Types:** `feature_completed`, `worker_dispatched`, `validation_result`, `scope_change`, `research_available`, `user_instruction`, `error_report`

Write messages at these points: worker dispatch (Step 4), feature completion (Step 7), milestone events (Step 8), scope changes, research completion, and error conditions.

---

## Validation Override

When the user invokes `/mission-override`, it marks failed validators as completed, seals the milestone, and logs the override with the user's justification. The full procedure is in `commands/mission-override.toml`.

**Key rule for the orchestrator to remember:** Override does NOT change `validation-state.json` — failed assertions stay `"failed"`. The override is a procedural bypass, not a claim that validation passed. If the mission was `"paused"`, the override transitions it back to `"orchestrator_turn"`.
