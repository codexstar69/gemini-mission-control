---
name: mission-orchestrator
description: Autonomous orchestrator run loop for dispatching workers and managing mission execution
---

# Mission Orchestrator

This skill drives the autonomous orchestrator run loop. It reads mission state, evaluates the feature DAG, dispatches worker subagents, parses handoffs, applies a decision tree, updates state, and manages milestone validation — all without user intervention until the mission is complete (or paused/blocked).

## When to Use This Skill

Activate this skill when:
- The user invokes `/mission-run` for a mission in `orchestrator_turn` state
- Resuming a mission after `/mission-resume`
- Re-entering the run loop after crash recovery

## Prerequisites

Before starting, confirm:
1. A mission directory exists at `~/.gemini-mc/missions/mis_<id>/`
2. `state.json` shows `"state": "orchestrator_turn"` (or `worker_running` for crash recovery)
3. `features.json` contains a non-empty features array
4. The project working directory (from `state.json.workingDirectory`) is accessible

---

## Run Loop Overview

The orchestrator executes an 8-step loop:

```
┌──────────────────────────────────────────────────────────┐
│  Step 1: Read State & Crash Recovery                     │
│  Step 2: Evaluate Feature DAG                            │
│  Step 3: Construct Worker Prompt                         │
│  Step 4: Dispatch Worker Subagent                        │
│  Step 5: Parse Structured Handoff                        │
│  Step 6: Apply Decision Tree (Options A/B/C/D)           │
│  Step 7: Update State & Log Events                       │
│  Step 8: Check Milestone Completion & Inject Validators  │
│                                                          │
│  ↻ Loop back to Step 1 (or exit if completed/paused)     │
└──────────────────────────────────────────────────────────┘
```

---

## Step 1: Read State & Crash Recovery

**Goal:** Load current mission state and recover from any crash that interrupted a previous run.

### 1.1 Read State Files

Read the following files from the mission directory `~/.gemini-mc/missions/mis_<id>/`:

```
read_file: state.json
read_file: features.json
read_file: progress_log.jsonl
read_file: AGENTS.md
read_file: validation-contract.md
```

Parse `state.json` to determine:
- Current `state` value
- `workingDirectory` path
- `completedFeatures` / `totalFeatures` counts
- `sealedMilestones` array
- `milestonesWithValidationPlanned` array

### 1.2 Crash Recovery

If `state.json` shows `state: "worker_running"`, a previous worker was interrupted mid-execution. Perform crash recovery:

1. **Identify stuck features:** Scan `features.json` for any feature that was being processed. Check `progress_log.jsonl` for the last `worker_started` event without a corresponding `worker_completed` event. The feature referenced in that event is stuck.

2. **Reset stuck features:** Update the stuck feature's status back to `"pending"` in `features.json` using `write_file`. This makes it eligible for re-dispatch.

3. **Clear active workers from progress log:** Append a recovery event to `progress_log.jsonl`:
   ```json
   {"timestamp": "<ISO 8601>", "event": "crash_recovery", "resetFeatures": ["<stuck-feature-id>"], "previousState": "worker_running"}
   ```

4. **Reset state:** Update `state.json` to `"state": "orchestrator_turn"` using `write_file`.

5. **Log the state transition:**
   ```json
   {"timestamp": "<ISO 8601>", "event": "state_transition", "from": "worker_running", "to": "orchestrator_turn", "reason": "crash_recovery"}
   ```

### 1.3 Empty Features Check

If `features.json` has zero features (empty `features` array), transition directly to `completed`:

1. Update `state.json`: set `"state": "completed"`, update `updatedAt`.
2. Log: `{"timestamp": "<ISO 8601>", "event": "state_transition", "from": "orchestrator_turn", "to": "completed", "reason": "empty_features"}`
3. Inform the user: "No features to process. Mission completed."
4. **Exit the run loop.**

### 1.4 All-Cancelled Check

If every feature in `features.json` has `status: "cancelled"`, treat the mission as complete:

1. Update `state.json`: set `"state": "completed"`, update `updatedAt`.
2. Log: `{"timestamp": "<ISO 8601>", "event": "state_transition", "from": "orchestrator_turn", "to": "completed", "reason": "all_features_cancelled"}`
3. Inform the user: "All features have been cancelled. Mission completed."
4. **Exit the run loop.**

---

## Step 2: Evaluate Feature DAG

**Goal:** Find the next feature whose preconditions are all met and whose status is `pending`.

### 2.1 Build Dependency Graph

For each feature in `features.json`:
1. Check if `status` is `"pending"`.
2. Check if ALL feature IDs listed in `preconditions` have `status: "completed"` in the features array.
3. Skip any feature with `status: "completed"` or `status: "cancelled"`.

### 2.2 Select Next Feature

From all features whose preconditions are satisfied and status is `pending`, select the first one in array order. Array order reflects priority — features earlier in the array are dispatched first.

### 2.3 No Ready Features

If no features are ready (all pending features have unmet preconditions):

- Check if there are any `pending` features at all. If not, all features are either `completed` or `cancelled`. Proceed to Step 8 to check milestone completion and potentially transition to `completed`.
- If there ARE pending features but none are ready (deadlock), log a warning and inform the user:
  ```json
  {"timestamp": "<ISO 8601>", "event": "deadlock_detected", "pendingFeatures": ["list-of-pending-ids"]}
  ```
  Transition to `paused` state and request user intervention.

---

## Step 3: Construct Worker Prompt

**Goal:** Build a rich, context-aware prompt for the worker subagent that includes everything it needs to implement the feature.

### 3.1 Feature Context

Include in the worker prompt:

```
Feature ID: <feature.id>
Description: <feature.description>
Expected Behavior:
  - <feature.expectedBehavior[0]>
  - <feature.expectedBehavior[1]>
  ...
Verification Steps:
  - <feature.verificationSteps[0]>
  - <feature.verificationSteps[1]>
  ...
Fulfills: <feature.fulfills>  (validation contract assertion IDs)
```

### 3.2 Project Enrichment

Read and include content from the project's `.mission/` directory (located at `<workingDirectory>/.mission/`):

1. **`.mission/services.yaml`** — The single source of truth for all commands and services. Read with `read_file` and include the full contents. If the file does not exist, include a warning: "No services.yaml found — worker must determine commands independently."

2. **`.mission/library/*.md`** — Shared knowledge base. Read all `.md` files in the library directory using `list_directory` and `read_file`. Include their contents under a "Library Knowledge" section. If files are missing, include a note: "No library files found."

3. **`.mission/skills/<skillName>/SKILL.md`** — Per-mission worker skill. If a skill file exists matching the feature's `skillName`, read it with `read_file` and include its contents. This provides mission-specific procedural guidance that the worker must follow. If no per-mission skill exists, the worker uses its built-in procedure.

4. **`AGENTS.md`** — Mission guidance from `~/.gemini-mc/missions/mis_<id>/AGENTS.md`. Read and include the full contents. This provides worker boundaries, coding conventions, and known issues.

### 3.3 Validation Contract Context

If the feature has a non-empty `fulfills` array, extract the relevant assertions from `validation-contract.md` and include them in the worker prompt:

```
Validation Assertions to Fulfill:
  VAL-XXX-001: <assertion description>
  VAL-XXX-002: <assertion description>
```

This tells the worker exactly what behavioral requirements their implementation must satisfy.

### 3.4 Map skillName to Agent Name

The feature's `skillName` field maps directly to the agent to dispatch:

| skillName | Agent Name | Description |
|-----------|------------|-------------|
| `mission-worker` | `mission-worker` | General implementation worker |
| `code-quality-worker` | `code-quality-worker` | Code review and refactoring |
| `scrutiny-validator` | `scrutiny-validator` | Milestone code quality validation |
| `user-testing-validator` | `user-testing-validator` | Milestone behavioral testing validation |

If a `skillName` does not match any known agent, check if a custom agent file exists at `agents/<skillName>.md`. If not, fall back to `mission-worker`.

### 3.5 init.sh Execution

Before dispatching the **first** worker in a mission run session, check if `.mission/init.sh` exists. If it does, instruct the worker prompt to run it:

```
IMPORTANT: Before starting implementation, run the environment setup script:
  run_shell_command: bash <workingDirectory>/.mission/init.sh
This is idempotent — safe to run multiple times.
```

After the first worker has run init.sh, subsequent workers in the same session do not need to re-run it (but it is safe if they do).

---

## Step 4: Dispatch Worker Subagent

**Goal:** Send the constructed prompt to the appropriate worker subagent and wait for its response.

### 4.1 State Transition

Before dispatching, update `state.json`:
- Set `"state": "worker_running"`
- Update `"updatedAt"` to current ISO 8601 timestamp

Log the dispatch event to `progress_log.jsonl`:
```json
{"timestamp": "<ISO 8601>", "event": "worker_started", "featureId": "<feature.id>", "agentName": "<agent-name>", "skillName": "<feature.skillName>"}
```

### 4.2 Dispatch via Native Tool Call

Call the worker agent by name using Gemini CLI's native subagent dispatch mechanism. The agent name corresponds to the mapped agent from Step 3.4.

Pass the enriched prompt from Step 3 as the agent's input. The worker will execute autonomously and return a structured response.

### 4.3 Wait for Completion

The orchestrator waits for the worker subagent to complete. The worker's entire response — including its structured JSON handoff — is returned to the orchestrator.

---

## Step 5: Parse Structured Handoff

**Goal:** Extract the structured JSON handoff from the worker's response and persist it.

### 5.1 Extract Handoff JSON

The worker's response contains a structured JSON handoff block. Parse it to extract the following fields:

```json
{
  "salientSummary": "1-4 sentence summary of what happened",
  "whatWasImplemented": "Concrete description of what was built (min 50 chars)",
  "whatWasLeftUndone": "Anything incomplete (empty string if complete)",
  "verification": {
    "commandsRun": [
      {"command": "...", "exitCode": 0, "observation": "..."}
    ],
    "interactiveChecks": [
      {"action": "...", "observed": "..."}
    ]
  },
  "tests": {
    "added": [
      {"file": "...", "cases": [{"name": "...", "verifies": "..."}]}
    ],
    "coverage": "Summary of test coverage"
  },
  "discoveredIssues": [
    {"severity": "blocking|non_blocking", "description": "...", "suggestedFix": "..."}
  ]
}
```

### 5.2 Validate Handoff Fields

Verify the handoff contains all required fields:
- `salientSummary` — non-empty string
- `whatWasImplemented` — string with at least 50 characters
- `verification.commandsRun` — non-empty array with at least one entry
- `discoveredIssues` — array (may be empty)

If the handoff is malformed or missing critical fields, treat it as a **failure** (Option B in the decision tree).

### 5.3 Write Handoff to File

Write the complete handoff JSON to the mission's handoffs directory:

```
write_file: ~/.gemini-mc/missions/mis_<id>/handoffs/<feature-id>.json
```

The file must contain valid JSON matching the handoff schema above. This creates a permanent record of the worker's output for later reference by validators and other workers.

### 5.4 State Transition

Update `state.json`:
- Set `"state": "handoff_review"`
- Update `"updatedAt"` to current ISO 8601 timestamp

Log the completion event to `progress_log.jsonl`:
```json
{"timestamp": "<ISO 8601>", "event": "worker_completed", "featureId": "<feature.id>", "salientSummary": "<handoff.salientSummary>"}
```

---

## Step 6: Apply Decision Tree (Options A/B/C/D)

**Goal:** Based on the worker's handoff, determine the appropriate next action.

Evaluate the handoff in this order:

### Option A: Follow-Up Feature for High/Critical Issues

**Trigger:** The `discoveredIssues` array contains one or more issues with `severity: "blocking"`.

**Action:**
1. Create a new follow-up feature for each blocking issue (or group related issues into one feature).
2. Insert the new feature(s) at the **top** of the `features` array in `features.json` (highest priority).
3. Set the follow-up feature's fields:
   - `id`: `"fix-<original-feature-id>-<issue-index>"` (e.g., `fix-user-auth-001`)
   - `description`: The issue description + suggested fix from the handoff
   - `skillName`: Same as the original feature (or `code-quality-worker` for quality issues)
   - `milestone`: Same milestone as the original feature
   - `preconditions`: `[<original-feature-id>]` (depends on the original being done)
   - `expectedBehavior`: Derived from the issue description
   - `verificationSteps`: Derived from the suggested fix
   - `fulfills`: `[]` (follow-ups typically don't fulfill new assertions)
   - `status`: `"pending"`
4. Mark the original feature as `"completed"` (it did its work; the follow-up addresses remaining issues).
5. Increment `completedFeatures` in `state.json`.
6. Update `totalFeatures` to reflect the newly added feature(s).

### Option B: Reset to Pending on Failure

**Trigger:** The worker explicitly reports failure — `whatWasLeftUndone` is non-empty AND `verification.commandsRun` shows failing exit codes (non-zero), OR the handoff is malformed/missing.

**Action:**
1. Reset the feature's `status` to `"pending"` in `features.json`.
2. Update the feature's `description` to include context from the failure:
   ```
   [RETRY] Original: <original description>. Previous attempt failed: <whatWasLeftUndone>. Error context: <relevant verification output>.
   ```
3. Do NOT increment `completedFeatures`.
4. Log a retry event:
   ```json
   {"timestamp": "<ISO 8601>", "event": "feature_retry", "featureId": "<id>", "reason": "<brief reason>"}
   ```
5. Track retry count. If a feature has been retried 3 times, escalate:
   - Log: `{"timestamp": "<ISO 8601>", "event": "feature_escalation", "featureId": "<id>", "retries": 3}`
   - Transition to `paused` state and inform the user that a feature is repeatedly failing.

### Option C: Update Description for Partial Completion

**Trigger:** The worker reports partial success — `whatWasLeftUndone` is non-empty but `verification.commandsRun` shows some passing results, AND there are no blocking `discoveredIssues`.

**Action:**
1. Update the feature's `description` in `features.json` to reflect only the remaining work:
   ```
   [PARTIAL] Completed: <whatWasImplemented>. Remaining: <whatWasLeftUndone>.
   ```
2. Keep the feature's `status` as `"pending"` so it will be re-dispatched.
3. Do NOT increment `completedFeatures`.
4. Log:
   ```json
   {"timestamp": "<ISO 8601>", "event": "feature_partial", "featureId": "<id>", "implemented": "<whatWasImplemented>", "remaining": "<whatWasLeftUndone>"}
   ```

### Option D: Misc Milestone for Low/Medium Issues

**Trigger:** The `discoveredIssues` array contains issues with `severity: "non_blocking"` only (no blocking issues), AND the worker reports success (empty `whatWasLeftUndone`, passing verification).

**Action:**
1. Mark the original feature as `"completed"` in `features.json`.
2. Increment `completedFeatures` in `state.json`.
3. For each `non_blocking` issue, create a new feature in a `misc-*` milestone:
   - Find the current misc milestone (`misc-1`, `misc-2`, etc.).
   - If the current misc milestone has 5 features already, create the next one (`misc-2`, `misc-3`, etc.).
   - Set the new feature's fields:
     - `id`: `"misc-<issue-description-slug>"` (short, descriptive)
     - `description`: The issue description + suggested fix
     - `skillName`: `code-quality-worker` (or `mission-worker` if implementation work is needed)
     - `milestone`: `"misc-N"` (current misc milestone)
     - `preconditions`: `[]`
     - `expectedBehavior`: Derived from the issue
     - `verificationSteps`: Derived from the suggested fix
     - `fulfills`: `[]`
     - `status`: `"pending"`
4. Update `totalFeatures` in `state.json` to reflect newly added features.

### Option: Clean Success (No Issues)

**Trigger:** No `discoveredIssues`, empty `whatWasLeftUndone`, all verification commands passed (exit code 0).

**Action:**
1. Mark the feature as `"completed"` in `features.json`.
2. Increment `completedFeatures` in `state.json`.
3. No new features are created.

---

## Step 7: Update State & Log Events

**Goal:** Persist all state changes and log the decision outcome.

### 7.1 Update features.json

Write the updated features array back to `features.json` using `write_file`. This reflects:
- Feature status changes (completed, pending reset)
- New features added (follow-ups, misc features)
- Description updates (partial completion, retry context)

### 7.2 Update state.json

Update `state.json` with:
- `"state": "orchestrator_turn"` (returning from `handoff_review`)
- `"completedFeatures"`: Incremented if the feature was completed
- `"totalFeatures"`: Updated if new features were added
- `"updatedAt"`: Current ISO 8601 timestamp

### 7.3 Log to progress_log.jsonl

Append a state transition event:
```json
{"timestamp": "<ISO 8601>", "event": "state_transition", "from": "handoff_review", "to": "orchestrator_turn", "featureId": "<id>", "decision": "<A|B|C|D|clean_success>"}
```

### 7.4 Write Inter-Agent Message

Append a message to `messages.jsonl` summarizing the completed work:
```json
{"timestamp": "<ISO 8601>", "sender": "orchestrator", "type": "feature_completed", "content": "<salientSummary from handoff>"}
```

### Event Types for progress_log.jsonl

The following event types are logged throughout the run loop:

| Event | When Logged |
|-------|-------------|
| `worker_started` | Step 4 — Worker subagent dispatched |
| `worker_completed` | Step 5 — Worker handoff received |
| `state_transition` | Any state change in state.json |
| `milestone_completed` | Step 8 — All implementation features in a milestone are done |
| `validation_injected` | Step 8 — Validator features added for a milestone |
| `crash_recovery` | Step 1 — Stuck features reset after crash |
| `feature_retry` | Step 6 Option B — Feature reset to pending |
| `feature_partial` | Step 6 Option C — Feature partially completed |
| `feature_escalation` | Step 6 Option B — Feature retried 3+ times |
| `deadlock_detected` | Step 2 — Pending features with unmet preconditions |
| `scope_change` | Scope change protocol — Requirements modified |
| `budget_pause` | Budget enforcement — Token limit exceeded |
| `research_completed` | Research delegation — Research saved |
| `feature_cancelled` | Feature cancellation — Feature moved to terminal state |

---

## Step 8: Check Milestone Completion & Inject Validators

**Goal:** Detect when all implementation features in a milestone are done and inject validation features.

### 8.1 Identify Completed Milestones

After updating the feature that just completed:

1. Get the `milestone` value from the completed feature.
2. Find ALL features in `features.json` that share this milestone.
3. Separate implementation features from validator features:
   - **Implementation features**: Those whose `id` does NOT start with `scrutiny-validator-` or `user-testing-validator-`.
   - **Validator features**: Those whose `id` starts with `scrutiny-validator-` or `user-testing-validator-`.
4. Check if ALL implementation features have `status: "completed"` or `status: "cancelled"`.

### 8.2 Inject Validator Features

If all implementation features in the milestone are done AND the milestone is NOT already in `milestonesWithValidationPlanned`:

1. **Create scrutiny validator feature:**
   ```json
   {
     "id": "scrutiny-validator-<milestone>",
     "description": "Scrutiny validation for milestone \"<milestone>\". Runs test suite, typecheck, and lint. Reviews each completed feature's code changes. Synthesizes findings. Always returns to orchestrator.",
     "skillName": "scrutiny-validator",
     "milestone": "<milestone>",
     "preconditions": ["All implementation features for milestone \"<milestone>\" are complete"],
     "expectedBehavior": [
       "Validators pass (test, typecheck, lint)",
       "Review completed for each feature",
       "Findings synthesized into scrutiny report"
     ],
     "verificationSteps": [],
     "fulfills": [],
     "status": "pending"
   }
   ```

2. **Create user-testing validator feature:**
   ```json
   {
     "id": "user-testing-validator-<milestone>",
     "description": "User testing validation for milestone \"<milestone>\". Tests behavioral assertions from validation contract. Updates validation-state.json. Always returns to orchestrator.",
     "skillName": "user-testing-validator",
     "milestone": "<milestone>",
     "preconditions": ["scrutiny-validator-<milestone>"],
     "expectedBehavior": [
       "Testable assertions determined from fulfills mapping",
       "Each assertion tested and results recorded",
       "validation-state.json updated with pass/fail/blocked",
       "Results synthesized into user-testing report"
     ],
     "verificationSteps": [],
     "fulfills": [],
     "status": "pending"
   }
   ```

   **Important:** The user-testing validator depends on the scrutiny validator (`preconditions` includes `scrutiny-validator-<milestone>`). This ensures code quality gates pass before behavioral testing.

3. **Add both features** to the `features` array in `features.json`.

4. **Update state.json:**
   - Add the milestone name to `milestonesWithValidationPlanned` array.
   - Increment `totalFeatures` by 2.
   - Update `updatedAt`.

5. **Log the injection:**
   ```json
   {"timestamp": "<ISO 8601>", "event": "milestone_completed", "milestone": "<milestone>"}
   {"timestamp": "<ISO 8601>", "event": "validation_injected", "milestone": "<milestone>", "features": ["scrutiny-validator-<milestone>", "user-testing-validator-<milestone>"]}
   ```

### 8.3 Check for Sealed Milestones

After a `user-testing-validator-<milestone>` feature completes successfully (clean success or Option D):

1. Add the milestone to `sealedMilestones` in `state.json`.
2. From this point forward, reject any attempt to add features to this milestone. New work goes to a follow-up milestone or `misc-*` milestone instead.

### 8.4 Check for Mission Completion

After processing all state updates:

1. Check if ALL features have `status: "completed"` or `status: "cancelled"`.
2. Check if ALL milestones that had implementation features are in `sealedMilestones` (or all their features are cancelled).
3. If both conditions are met:
   - Update `state.json`: set `"state": "completed"`, update `updatedAt`.
   - Log: `{"timestamp": "<ISO 8601>", "event": "state_transition", "from": "orchestrator_turn", "to": "completed", "reason": "all_milestones_sealed"}`
   - Inform the user: "Mission completed. All features implemented and milestones validated."
   - **Exit the run loop.**
4. If conditions are NOT met, **loop back to Step 1** to process the next feature.

---

## Scope Change Protocol

The orchestrator supports mid-mission scope changes — adding, removing, or modifying requirements.

### Adding Requirements

1. Receive new requirement from the user (via message or command).
2. Create a new VAL assertion ID in `validation-contract.md` following the `VAL-XXX-NNN` format.
3. Create a new feature in `features.json` with `fulfills` referencing the new assertion.
4. Initialize the new assertion in `validation-state.json` with `status: "pending"`.
5. Update `totalFeatures` in `state.json`.
6. If the target milestone is sealed, direct the new feature to a `misc-*` milestone or create a new milestone.
7. Enforce the coverage gate: the new assertion must be claimed by exactly one feature.
8. Log: `{"timestamp": "<ISO 8601>", "event": "scope_change", "action": "add", "assertionId": "VAL-XXX-NNN", "featureId": "<new-feature-id>"}`

### Removing Requirements

1. Mark the VAL assertion as removed in `validation-contract.md` (add `[REMOVED]` prefix).
2. Update `validation-state.json`: set the assertion status to `"passed"` (it no longer needs testing).
3. Remove the assertion ID from the `fulfills` array of any feature that references it.
4. If removing the assertion leaves a feature with an empty `fulfills` array and no other purpose, consider cancelling the feature.
5. Log: `{"timestamp": "<ISO 8601>", "event": "scope_change", "action": "remove", "assertionId": "VAL-XXX-NNN"}`

### Modifying Requirements

1. Update the assertion's description in `validation-contract.md`.
2. Reset the assertion's status to `"pending"` in `validation-state.json` (it needs re-testing).
3. If the change affects a completed feature's implementation, create a follow-up feature to address the modification.
4. Enforce the coverage gate: the modified assertion must still be claimed by exactly one feature.
5. Log: `{"timestamp": "<ISO 8601>", "event": "scope_change", "action": "modify", "assertionId": "VAL-XXX-NNN"}`

---

## Budget Enforcement

The orchestrator tracks token usage and pauses when a budget limit is exceeded.

### Token Tracking

After each worker dispatch-and-handoff cycle, estimate the token usage:
- Count the approximate tokens in the worker prompt (input).
- Count the approximate tokens in the worker response (output).
- Accumulate a running total in `state.json` or `progress_log.jsonl`.

### Auto-Pause on Budget Exceeded

If the accumulated token usage exceeds a configured budget threshold:

1. Transition `state.json` to `"state": "paused"`.
2. Log:
   ```json
   {"timestamp": "<ISO 8601>", "event": "budget_pause", "tokensUsed": <total>, "budget": <limit>}
   ```
3. Inform the user: "Budget limit exceeded (<tokensUsed> / <budget> tokens). Mission paused. Use `/mission-resume` to continue with acknowledgment."
4. **Exit the run loop.** Do NOT dispatch more workers.

### Resume with Acknowledgment

When `/mission-resume` is invoked for a budget-paused mission:
1. Require explicit acknowledgment from the user that they accept continued token usage.
2. Only after acknowledgment, transition back to `orchestrator_turn`.
3. Optionally reset the budget counter or increase the budget limit.

---

## Research Delegation

When a feature requires knowledge beyond what's available in the library or the model's training data, delegate research using `google_web_search`.

### When to Research

Research is needed when:
- A feature references a specific API, SDK, or service that the orchestrator is unfamiliar with.
- The `.mission/library/` does not contain guidance for the required technology.
- A worker's handoff reports confusion about a technology or API.

### Research Procedure

1. Use `google_web_search` to find relevant documentation, tutorials, and examples.
2. Save raw search results and relevant page content to `.mission/research/<topic>.md` using `write_file`.
3. Distill the key findings into a concise guide and save to `.mission/library/<topic>.md` using `write_file`.
4. Include the library entry in future worker prompts (via Step 3.2 enrichment).
5. Log:
   ```json
   {"timestamp": "<ISO 8601>", "event": "research_completed", "topic": "<topic>", "savedTo": [".mission/research/<topic>.md", ".mission/library/<topic>.md"]}
   ```

---

## Feature Cancellation

Features can be cancelled when they are no longer needed. Cancellation is a **terminal state** — cancelled features are never re-dispatched.

### Cancellation Procedure

1. Set the feature's `status` to `"cancelled"` in `features.json`.
2. Move the cancelled feature to the **bottom** of the `features` array (lowest priority).
3. Update `totalFeatures` in `state.json` (do NOT decrement — cancelled features count toward total).
4. Remove the feature's `fulfills` assertion IDs from the coverage requirement (mark those assertions as `"passed"` or add them to another feature's `fulfills`).
5. Log:
   ```json
   {"timestamp": "<ISO 8601>", "event": "feature_cancelled", "featureId": "<id>", "reason": "<reason>"}
   ```

### Cancellation Rules

- Cancellation is **irreversible**. Once cancelled, a feature cannot be un-cancelled.
- If a cancelled feature was a precondition for other features, those dependent features' preconditions are considered met (cancellation counts as "done" for dependency purposes).
- Cancellation of all features in a milestone means the milestone is considered complete (no validation needed for an empty milestone).

---

## Misc Milestones

Non-blocking issues discovered during implementation are tracked in `misc-*` milestones.

### Capacity Limit

Each misc milestone holds a maximum of **5 features**. When a misc milestone reaches capacity:
- Create the next sequential misc milestone: `misc-1`, `misc-2`, `misc-3`, etc.
- New misc features go into the latest misc milestone with available capacity.

### Feature Assignment

When creating a feature in a misc milestone (Option D in the decision tree):
1. List all milestones matching the `misc-*` pattern.
2. Find the latest misc milestone (highest number).
3. Count features in that milestone.
4. If count < 5, add the new feature to that milestone.
5. If count >= 5, create `misc-<N+1>` and add the feature there.

### Misc Milestone Validation

Misc milestones follow the same validation lifecycle as regular milestones:
- When all 5 features (or fewer, if the milestone is the last) are completed, inject validators.
- Validators can be auto-injected or deferred until the mission nears completion.

---

## Pause / Resume

The orchestrator supports pausing and resuming the run loop.

### Pause

Triggered by `/mission-pause` command or automatically on budget exceeded:

1. Complete any in-progress state updates (don't leave state half-written).
2. Update `state.json`: set `"state": "paused"`, update `updatedAt`.
3. Log:
   ```json
   {"timestamp": "<ISO 8601>", "event": "state_transition", "from": "orchestrator_turn", "to": "paused", "reason": "user_requested|budget_exceeded"}
   ```
4. Inform the user: "Mission paused. Use `/mission-resume` to continue."
5. **Exit the run loop.**

### Resume

Triggered by `/mission-resume` command:

1. Read `state.json` and verify `state` is `"paused"`.
2. If paused due to budget (`budget_pause` event in `progress_log.jsonl`), require explicit user acknowledgment before continuing.
3. Update `state.json`: set `"state": "orchestrator_turn"`, update `updatedAt`.
4. Log:
   ```json
   {"timestamp": "<ISO 8601>", "event": "state_transition", "from": "paused", "to": "orchestrator_turn", "reason": "user_resumed"}
   ```
5. **Re-enter the run loop at Step 1.**

---

## Inter-Agent Messaging Protocol

The orchestrator and workers communicate through `messages.jsonl`, an append-only log of structured messages.

### Message Format

Each line in `messages.jsonl` is a JSON object:

```json
{
  "timestamp": "<ISO 8601>",
  "sender": "orchestrator|mission-worker|scrutiny-validator|user-testing-validator",
  "type": "feature_completed|worker_dispatched|validation_result|scope_change|research_available|user_instruction|error_report",
  "content": "Human-readable message content describing what happened"
}
```

### Message Fields

- **`timestamp`** — ISO 8601 timestamp of when the message was written.
- **`sender`** — Identifier of the agent that wrote the message. Use the agent name (e.g., `orchestrator`, `mission-worker`, `scrutiny-validator`).
- **`type`** — Message category. Valid types:
  - `feature_completed` — A feature has been completed or updated.
  - `worker_dispatched` — A worker has been sent to implement a feature.
  - `validation_result` — Validation outcome for a milestone.
  - `scope_change` — Requirements have been added, removed, or modified.
  - `research_available` — New research or library content has been added.
  - `user_instruction` — Instruction from the user relayed to agents.
  - `error_report` — An error or warning that other agents should know about.
- **`content`** — Human-readable description of the event.

### When to Write Messages

- **Step 4 (Dispatch):** Write a `worker_dispatched` message with the feature ID and agent name.
- **Step 7 (Update State):** Write a `feature_completed` message with the salient summary.
- **Step 8 (Milestone):** Write a `validation_result` message when validators are injected or complete.
- **Scope Change:** Write a `scope_change` message when requirements are modified.
- **Research:** Write a `research_available` message when new library content is added.
- **Error:** Write an `error_report` message when a deadlock, escalation, or crash recovery occurs.

Workers may also write messages to `messages.jsonl` to communicate findings or requests to the orchestrator and future workers.
