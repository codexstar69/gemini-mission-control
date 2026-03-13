# Mission Worker Lifecycle & Orchestration Workflow

Exact step-by-step workflow of how Droid v0.70.0 runs a mission — from planning through worker spawning, validation, and completion. Verified against the official binary at `/opt/homebrew/Caskroom/droid/0.70.0/droid`.

---

## Architecture Overview

### Two-Directory Model

Droid separates **mission state** from **project infrastructure**:

| Location                      | Purpose                                                             | Git?                        |
| ----------------------------- | ------------------------------------------------------------------- | --------------------------- |
| `~/.factory/missions/<uuid>/` | Mission-specific state (state.json, features.json, handoffs/, etc.) | No                          |
| `<project>/.factory/`         | Shared infra (skills, services.yaml, init.sh, library/, AGENTS.md)  | **Yes — must be committed** |

> `.factory/` in the project root is NOT gitignored. It's shared infrastructure that workers depend on.

### Built-in vs Dynamic Skills

| Skill | Type | Location | Purpose |
|-------|------|----------|---------|
| `mission-planning` | Built-in | Compiled into binary | 7-phase interactive planning |
| `define-mission-skills` | Built-in | Compiled into binary | Designs worker personas per mission |
| `mission-worker-base` | Built-in | Compiled into binary | Base skill every worker loads first |
| `scrutiny-validator` | Built-in | Compiled into binary | Code review + contract assertion checking |
| `user-testing-validator` | Built-in | Compiled into binary | User-flow testing with isolation |
| `tui-worker` | Dynamic | `.factory/skills/tui-worker/SKILL.md` | TDD + TUI manual verification via `tuistory` |
| `backend-worker` | Dynamic | `.factory/skills/backend-worker/SKILL.md` | TDD-first + actual behavior verification |
| Custom per-mission | Dynamic | `.factory/skills/<name>/SKILL.md` | Mission-specific worker types |

Dynamic skills are created by `define-mission-skills` during Phase 1 and live inside the project's `.factory/skills/` directory.

---

## Phase 1: Planning (Orchestrator — your Claude session)

The orchestrator loads two built-in skills sequentially:

### 1a. `mission-planning` — 7 Interactive Phases

1. **Understand** — Read existing codebase, `.factory/` state, prior missions
2. **Clarify** — Ask user questions via `ASK USER` (style, scope, constraints, priorities)
3. **Propose milestones** — Break work into ordered milestone groups
4. **Write validation contract** — `validation-contract.md` with `VAL-XXX-NNN` assertions. This is written BEFORE features.json — mission-level TDD
5. **Adversarial review** — At least 2 review passes of the contract, looking for gaps and missing edge cases
6. **Design features** — Create `features.json` with DAG dependencies, preconditions, expectedBehavior, verificationSteps
7. **User approval** — Present full plan, get explicit go-ahead

### 1b. `define-mission-skills` — Worker Design

After planning, the orchestrator designs the worker types needed:

- Analyzes each feature's requirements
- Creates `.factory/skills/<name>/SKILL.md` files with detailed procedures
- Each skill defines: role, tools, workflow steps, verification expectations
- Common patterns: `tui-worker` (TUI apps), `backend-worker` (API/DB), `infra-worker`, `data-worker`

### 1c. Artifact Creation

The orchestrator creates all mission artifacts:

**Mission directory** (`~/.factory/missions/<uuid>/`):
- `mission.md` — human-readable plan with milestones
- `features.json` — every feature with `id`, `description`, `skillName`, `preconditions`, `expectedBehavior`, `verificationSteps`, `fulfills` (VAL IDs), milestone grouping, DAG dependencies
- `validation-contract.md` — `VAL-XXX-NNN` acceptance criteria (written BEFORE features)
- `validation-state.json` — all assertions set to `"pending"`
- `AGENTS.md` — boundaries, off-limits zones, environment context, conventions for workers
- `working_directory.txt` — absolute path to project
- `model-settings.json` — model assignments for orchestrator/worker/validator
- `state.json` — created with `"state": "running"`

**Project `.factory/`** (committed to git):
- `services.yaml` — service definitions workers can start/manage
- `init.sh` — setup steps (install deps, create directories, seed data)
- `library/<topic>.md` — reference docs workers will read
- `skills/<name>/SKILL.md` — custom worker skill definitions

### Artifact Checklist (from binary)

The orchestrator verifies before proceeding:
- [ ] `mission.md` complete with milestones
- [ ] `validation-contract.md` with all VAL assertions
- [ ] `features.json` with all features, correct DAG ordering
- [ ] `validation-state.json` initialized
- [ ] `AGENTS.md` with environment context
- [ ] Custom skill files created
- [ ] `services.yaml` updated if needed
- [ ] `init.sh` updated if needed
- [ ] All `.factory/` changes committed to git

---

## Phase 2: Mission Run (Orchestrator loop)

### `start_mission_run` — Blocking Call

The orchestrator calls `start_mission_run` which is a **blocking call** — the orchestrator cedes control of the conversation until it returns. The run loops through features sequentially:

```
for each feature in features.json (array order):
    → spawn worker
    → wait for completion
    → review handoff
    → decide next action (next feature / inject fix / retry)
```

### Feature Ordering Rules

- Features execute in **array order** within `features.json`
- Preconditions must be met before dispatch
- Completed features are auto-moved to the **bottom** of the array
- `"cancelled"` is a terminal status (feature permanently skipped)
- The orchestrator never reorders features arbitrarily — DAG + milestone order is respected

### Per-Iteration Steps

**8. Select next pending feature** from `features.json`
- Checks preconditions are met
- Logs `worker_selected_feature` to `progress_log.jsonl`

**9. Spawn worker** via daemon RPC (`daemon.initialize_session`)
- Logs `worker_started`
- Worker gets a unique `workerSessionId` (UUID)
- Worker model comes from `model-settings.json` (e.g. `Copilot--Claude-Opus-4.6-Fast-78`)

**10. Worker auto-loads `mission-worker-base` skill** (compiled into binary). This makes the worker:
- Read `mission.md` — understand the overall plan
- Read `AGENTS.md` — understand boundaries and environment
- Read `features.json` — find its assigned feature's description, preconditions, expectedBehavior
- Read relevant `library/*.md` files — domain knowledge
- Run `init.sh` if needed — ensure environment is ready
- Read `messages.jsonl` — learn from previous workers' discoveries (broadcasts)
- Establish baseline (e.g. run tests, check services)

**11. Worker loads its role-specific skill** — the `skillName` from the feature (e.g. `tui-worker` from `.factory/skills/tui-worker/SKILL.md`)

**12. Task sent via `daemon.add_user_message`** — the feature description becomes the worker's task prompt

**13. Worker runs autonomously** — reads files, writes code, runs commands, makes commits. Daemon handles context compaction if it gets long.

**14. Worker completes** → daemon generates a "transcript skeleton" (summarized tool call log)
- Logs `worker_completed`
- Handoff JSON saved to `handoffs/{timestamp}__{featureId}__{sessionId}.json`
- Contains: `featureId`, `commitId`, `milestone`, `successState`, `handoff` payload, `returnToOrchestrator` flag

### Commit Hygiene

- Workers commit their own changes with descriptive messages
- The `commitId` in the handoff is the worker's own commit (BUG-025: worker-owned attribution)
- In parallel scenarios, ambient HEAD is not used — each worker reports its own commit
- Orchestrator does NOT commit on behalf of workers

### Handoff Review & Decision Tree

**15. Orchestrator reviews handoff** — reads the handoff JSON, evaluates what the worker did:

| Option | When | Action |
|--------|------|--------|
| **A — New feature** | Worker found something new that needs doing | Create a new feature in features.json, dispatch new worker |
| **B — Reset to pending** | Worker failed, needs fresh retry | Set feature status back to `"pending"`, re-dispatch |
| **C — Update existing** | Partial completion, needs adjustments | Update the feature description with new context, re-dispatch |
| **D — Misc milestone** | Loose ends, cleanup tasks | Create feature in a "miscellaneous" milestone |

**16. Pre-existing issues handling**: If a worker discovers pre-existing bugs/issues in the codebase, the orchestrator creates targeted fix features (e.g. `fix-blog-docker-seeding`, `fix-preexisting-recipe-data`) rather than burdening the current worker.

---

## Phase 3: Milestone Validation (auto-injected)

### Validation Pipeline

**17. When all features in a milestone complete** → orchestrator auto-injects two validation features:
- `scrutiny-validator-{milestone}` — loads `scrutiny-validator` skill (built-in)
- `user-testing-validator-{milestone}` — loads `user-testing-validator` skill (built-in)
- These are injected into `features.json` as real features with status `"pending"`

### Scrutiny Validator

**18. Scrutiny validator worker** spawns (same lifecycle as steps 9–14):
- Loads `scrutiny-validator` skill (compiled into binary)
- Spawns **code review subagents** per feature in the milestone
- Checks validation-contract assertions (`VAL-XXX-NNN`)
- Updates `validation-state.json` (pass/fail per assertion)
- Produces a **synthesis report** with:
  - `appliedUpdates` — changes it made directly
  - `suggestedGuidanceUpdates` — proposed changes to AGENTS.md / mission guidelines
- Can update code, fix issues, and commit changes itself

### User Testing Validator

**19. User testing validator worker** spawns (same lifecycle as steps 9–14):
- Loads `user-testing-validator` skill (compiled into binary)
- Uses **isolation strategy** — unique accounts, namespaces, test data per flow
- Has **setup resolution** — ensures test environment is in known state before testing
- Spawns flow-test subagents with isolated contexts
- Curls endpoints, checks DB state, verifies HTTP responses
- Tests the user testing strategy defined in `mission.md`

### Validation Override

If validators produce false positives or the orchestrator disagrees:
- Orchestrator can **override** individual assertion results
- Override must include documented justification
- Overridden assertions are marked in `validation-state.json`

### Sealed Milestones

**20. Once validators pass** → milestone is **sealed**:
- Never add new features to a completed/validated milestone
- If new work is discovered, it goes into the next milestone or a new "miscellaneous" milestone
- This prevents regression and maintains validation integrity

**21. If validators find issues** → orchestrator creates fix features and re-runs validators (loop back to step 8)

---

## Phase 4: Repeat & Complete

**22. Move to next milestone** → repeat steps 8–21 for each milestone group.

### End-of-Mission Gate

Before declaring mission complete:
- **ALL** validation assertions must be `"passed"` in `validation-state.json`
- README must be created or updated
- All `.factory/` changes committed
- No pending or failed features remain

---

## Mid-Mission User Requests

When the user interrupts with a new request during an active mission, the orchestrator follows an 8-step process:

1. **Pause current execution** — don't spawn new workers
2. **Understand the request** — read what the user wants
3. **Assess impact** — does this change scope, priorities, or existing features?
4. **Update mission plan** — modify `mission.md` if scope changed
5. **Update features** — add/modify/reorder features in `features.json`
6. **Update validation contract** — add new VAL assertions if needed
7. **Update skills** — modify skill definitions if worker behavior needs to change
8. **Resume execution** — continue the mission loop with updated plan

### When to Return to User

The orchestrator returns control to the user when:
- A milestone fails validation after max retries
- A worker encounters an unrecoverable blocker
- The mission requires user input (credentials, design decisions, access)
- All milestones are complete (mission done)
- Cost or time limits are approaching

---

## Dynamic Skills: `tui-worker` Deep Dive

The `tui-worker` is a dynamic skill created by `define-mission-skills` for missions involving terminal UI applications. Its definition is embedded in the binary as a template.

### Workflow

1. **TDD Phase** — Write tests first for the TUI component
2. **Implementation** — Build the TUI feature
3. **Manual TUI Verification** — Use `tuistory` to visually verify the TUI

### `tuistory` Commands

```bash
tuistory launch "command"      # Launch TUI app
tuistory wait "text"           # Wait for specific text to appear
tuistory press "key"           # Press a key (enter, tab, up, down, etc.)
tuistory type "text"           # Type text input
tuistory snapshot --trim       # Capture current TUI state (trimmed)
```

### Example Flow

```bash
tuistory launch "bun run my-tui"
tuistory wait "Main Menu"
tuistory snapshot --trim           # Verify main menu renders
tuistory press "down"
tuistory press "enter"
tuistory wait "Settings"
tuistory snapshot --trim           # Verify navigation worked
```

The worker captures snapshots at key interaction points and verifies the TUI matches expected behavior from `expectedBehavior` in the feature definition.

---

## Dynamic Skills: `backend-worker` Deep Dive

The `backend-worker` follows a strict TDD-first approach:

1. **Write failing tests** — based on `expectedBehavior` and `verificationSteps`
2. **Implement** — write the minimal code to pass tests
3. **Verify actual behavior** — run the service, curl endpoints, check DB state
4. **Commit** — atomic commit with descriptive message

---

## Browser Automation: `agent-browser`

Workers can use the `agent-browser` tool for web interaction:

- **Ref-based interaction model** — elements are referenced by stable IDs, not selectors
- Supports: click, type, navigate, screenshot, wait
- Used by validators for user-flow testing
- Used by workers for web-based feature implementation

---

## Inter-Agent Communication

### `messages.jsonl`

Workers communicate via a file-based message bus:

| Message Type | Direction | Purpose |
|-------------|-----------|---------|
| `discovery` | Worker → All | Pattern/convention found during work |
| `blocker` | Worker → Orchestrator | Worker is stuck, needs help |
| `status` | Worker → Orchestrator | Progress update |
| `instruction` | Orchestrator → Worker | Directive to specific worker |
| `shared_knowledge` | Any → All | Knowledge merged into AGENTS.md |
| `warning` | Any → All | Issue other agents should know about |

Workers read broadcasts on startup to learn from previous workers' discoveries.

---

## State Tracking (continuous)

These files are continuously updated throughout the entire run:

| File | Purpose |
|------|---------|
| `state.json` | Current feature, worker session, completed count, overall state, active workers, milestone tracking |
| `features.json` | Feature statuses, runtime statuses, worker session assignments |
| `progress_log.jsonl` | Every event timestamped (worker starts, completions, validations) |
| `worker-transcripts.jsonl` | Skeleton summaries of what each worker did |
| `validation-state.json` | Per-assertion pass/fail/pending status, contract versioning |
| `handoffs/` | One JSON per worker completion with full handoff payload |
| `messages.jsonl` | Inter-agent messages (discoveries, blockers, instructions) |
| `model-settings.json` | Model assignments (can be changed mid-mission) |

---

## Quality Enforcement Flow

```
Feature Implementation
    → Worker self-verification (verificationSteps)
    → Handoff with commitId + successState
    → Orchestrator review (decision tree)
    → Milestone boundary reached?
        → Scrutiny validator (code review + contract assertions)
        → User testing validator (isolated flow tests)
        → All VAL assertions passed?
            → Seal milestone, move to next
            → OR: create fix features, re-validate
    → All milestones sealed?
        → End-of-mission gate check
        → Mission complete
```

---

## Event Sequence Diagram

```
mission_accepted
mission_run_started
  ┌─ worker_selected_feature (feature from DAG order)
  ├─ worker_started (daemon.initialize_session)
  ├─   ... worker runs autonomously ...
  ├─   ... worker reads messages.jsonl (learn from predecessors) ...
  ├─   ... worker loads mission-worker-base + role skill ...
  ├─   ... worker implements, tests, commits ...
  ├─ worker_completed (handoff saved)
  ├─ orchestrator reviews handoff (Options A/B/C/D)
  ├─ [if milestone boundary] validation auto-injected
  ├─   → scrutiny-validator worker (code review + VAL checks)
  ├─   → user-testing-validator worker (isolated flow tests)
  ├─ [if issues found] spawn fix worker, re-validate
  ├─ [if passed] seal milestone
  └─ loop to next feature
mission_completed (all VAL assertions passed)
```

---

## Tools Available to Workers

| Tool | Purpose |
|------|---------|
| `Read` / `Write` / `Edit` | File operations |
| `Bash` | Shell commands |
| `agent-browser` | Web interaction (ref-based) |
| `tuistory` | TUI testing (launch, wait, press, type, snapshot) |
| `daemon.*` | RPC to factoryd (session management) |
| `ASK USER` | Request user input (rare, orchestrator preference) |

---

## Real Example: FindCoffee Mission Stats

From the `c1e6a0ff` mission run:
- **40 workers** spawned total
- **7 milestones** with validation
- **7 milestone validations** (each triggering 2 validator workers = 14 validation runs)
- Several fix workers created on-the-fly for issues found during validation (e.g. `fix-blog-docker-seeding`, `fix-preexisting-recipe-data`)
- Runtime: ~5.5 hours (14:51 → 20:17 UTC)

---

## Key Architecture Notes

- Workers are spawned via **daemon RPC** (`factoryd`), NOT raw subprocess
- `start_mission_run` is a **blocking call** — orchestrator cedes control until it returns
- Built-in skills (`mission-worker-base`, `scrutiny-validator`, `user-testing-validator`, `mission-planning`, `define-mission-skills`) are **compiled into the binary**, not in `~/.factory/skills/`
- Dynamic skills (e.g. `tui-worker`, `backend-worker`) are created per-mission in `.factory/skills/` inside the project
- Orchestrator runs in **your Claude session** — it's the outer loop
- Workers run in **separate daemon sessions** — isolated context, own model settings
- Validation is **auto-injected** at milestone boundaries
- Validation contract is written **BEFORE** features (mission-level TDD)
- Sealed milestones are **immutable** — no new features added after validation passes
- `.factory/` directory **must be committed to git** — workers depend on it
- `"cancelled"` is a terminal feature status — distinct from `"skipped"`
- Workers report their own `commitId` in handoffs (no ambient HEAD cross-attribution)


---

## Validation Contract Format (from binary)

The validation contract (`validation-contract.md`) uses a specific format with stable IDs, behavioral descriptions, and evidence requirements:

```markdown
## Area: Authentication

### VAL-AUTH-001: Successful login
A user with valid credentials submits the login form and is redirected to the dashboard.
Evidence: screenshot, console-errors, network(POST /api/auth/login -> 200)

### VAL-AUTH-002: Login form validation
Submitting the login form with empty fields shows per-field validation errors without making a network request.
Evidence: screenshot, console-errors

## Cross-Area Flows

### VAL-CROSS-001: Auth gates pricing
A guest user sees "Sign in for pricing" on the catalog. After logging in, real prices are shown.
Evidence: screenshot(guest-view), screenshot(authed-view)
```

### Assertion Structure

Each assertion requires:
- **Stable ID** with area prefix — `VAL-AUTH-001`, `VAL-CATALOG-003`, `VAL-CROSS-002`
- **Title** — short description of the behavior
- **Behavioral description** — semantic but unambiguous, with a clear pass/fail condition
- **Evidence requirements** — what evidence must be collected: `screenshot`, `console-errors`, `network(METHOD /path -> status)`, `terminal output`

Organized by **area** (Authentication, Catalog, Checkout, etc.) plus a **Cross-Area Flows** section for flows spanning multiple features.

### Per-Feature Assertions

For each user-facing feature, cover all interactions users will have. Example for a Slack clone message composer:
- Typing a message, sending it, seeing it appear in the channel
- Editing, deleting, adding reactions, replying in threads
- Mentioning users, thread messages being interactable like top-level messages

Watch for **subtle requirements**: if building an invoicing app, changing a line item price must recalculate the total AND update percentage-based discounts.

### Cross-Feature Assertions

Cover:
- Flows spanning multiple features (e.g., add item to cart → logout → login → cart preserved)
- Entry points and navigability (first-visit flow, reachability via actual navigation not just direct URL)
- Any flows that span multiple features

### Adversarial Contract Review (from binary)

After drafting the contract, run **at least 2 sequential review passes**:

1. Each pass spawns **parallel subagents by section** — one reviewer per area plus one for cross-area
2. Each reviewer:
   - Reads the full draft contract and mission proposal
   - Investigates the codebase to verify coverage
   - Actively tries to find gaps (skeptical, adversarial posture)
3. After each pass: synthesize findings, update `validation-contract.md` with missing assertions
4. Passes run **sequentially** so each builds on the previous pass's additions
5. Orchestrator does a **final pass** after reviewers complete

---

## features.json Full Schema (from binary)

```json
{
  "features": [
    {
      "id": "checkout-reserve-inventory-endpoint",
      "description": "POST /api/checkout/reserve - Atomically reserve inventory for all items in user's cart. Returns reservation with 15-minute TTL. Handles concurrent requests for limited stock, partial availability, and reservation conflicts.",
      "skillName": "backend-worker",
      "milestone": "checkout",
      "preconditions": [
        "Cart service returns user's current cart items with quantities",
        "Inventory table has available_quantity and reserved_quantity columns",
        "Redis configured for distributed locking"
      ],
      "expectedBehavior": [
        "Returns 200 with { reservation_id, expires_at, items: [...] } when all items successfully reserved",
        "Returns 409 with { code: 'INSUFFICIENT_STOCK', unavailable: [{ sku, requested, available }] } if any item cannot be reserved",
        "Reservation is atomic - if any item fails, no items are reserved (all-or-nothing)",
        "Concurrent requests for last unit: exactly one succeeds, others receive 409 (no overselling)",
        "Returns 400 with { code: 'EMPTY_CART' } if user's cart is empty",
        "Returns 409 with { code: 'EXISTING_RESERVATION' } if user already has active reservation",
        "Reserved quantities reflected immediately in available_quantity for other users",
        "Reservation auto-expires after 15 minutes (TTL), releasing reserved quantities"
      ],
      "verificationSteps": [
        "npm test -- --grep 'reserve inventory' (expect 8+ test cases)",
        "curl POST /api/checkout/reserve with valid cart, verify 200 and inventory decremented"
      ],
      "fulfills": ["VAL-CHECKOUT-001", "VAL-CHECKOUT-002"],
      "status": "pending",
      "workerSessionIds": [],
      "currentWorkerSessionId": null,
      "completedWorkerSessionId": null
    }
  ]
}
```

### Coverage Gate (from binary)

**REQUIRED before starting mission:**

> Every assertion ID in `validation-contract.md` must be claimed by exactly one feature's `fulfills` — no orphans, no duplicates.

- Each `VAL-XXX-NNN` ID must appear in **exactly one** feature's `fulfills` array
- Unclaimed assertions = planning gap → fix before proceeding
- For large contracts: **use a subagent** to systematically extract all assertion IDs from the contract, cross-reference against all `fulfills` arrays, and report gaps

---

## Online Research Guidelines (from binary)

### When Research IS NOT Needed

Foundational, slowly-evolving technologies with massive training coverage:
- React, PostgreSQL, Express, standard HTML/CSS/JS, Python stdlib, etc.
- Training knowledge of these is reliable

### When Research IS Needed

Technologies where knowledge may be outdated, incomplete, or architecturally misleading:
- **Smaller or newer ecosystems** — Convex, Drizzle, Hono, etc.
- **SDK-heavy integrations** where the specific API surface matters — Vercel AI SDK, Stripe Elements, Supabase Auth helpers, etc.

### How to Research

1. **Delegate to subagents** — spawn one per technology needing research
2. Subagents use `WebSearch` and `FetchUrl` to look up current documentation
3. **Raw research reports** → `.factory/research/` (create directory if needed)
4. **Distilled worker-facing knowledge** → `.factory/library/`
5. Use judgment on depth:
   - Some technologies: summary of idiomatic patterns + anti-patterns is enough
   - Others: workers need actual API references, method signatures, config details → download and include documentation pages directly

### Directory Distinction

| Directory | Contents | Audience |
|-----------|----------|----------|
| `.factory/research/` | Raw research reports from subagents | Orchestrator reference |
| `.factory/library/` | Distilled, actionable knowledge | Workers read these directly |

Both directories are committed to git as part of `.factory/`.

### Required Library Files

- `.factory/library/user-testing.md` — MUST be initialized with testing surface findings (tools, URLs, setup steps, known quirks). Updated by validators during milestone validation.

---

## Validation Readiness Dry Run (from binary)

**REQUIRED before proceeding to mission proposal.** This is a critical quality gate.

### Purpose

Confirm that the validation approach is actually executable in the environment before implementation begins.

### Process

1. Use the `Task` tool to delegate the dry run to a subagent
2. Start required services and run a representative pass of intended user-testing flows
3. Use the actual tools the mission will use (`agent-browser`, `tuistory`, `curl`)
4. Include auth/bootstrap paths when applicable

### Greenfield vs Existing Codebases

**New (greenfield) codebases:**
- No running application yet — dry run verifies the **toolchain**
- Confirm testing tools are installed and functional
- Confirm planned ports are available
- Confirm environment can support the validation approach

**Existing codebases:**
- Verify the **full validation path**:
  - Dev server starts, pages load
  - Testing tools can interact with the application surface
  - Auth/bootstrap paths work
  - Existing fixtures/seed data are available
  - Application is in a testable state

### Blockers

Identify blockers early:
- Auth/access issues
- Missing fixtures/seed data
- Env/config gaps
- Broken local setup
- Unavailable entrypoints
- Flaky prerequisites

Present blockers and concrete options to user. Iterate until validation is runnable OR user explicitly approves an alternative approach with known limitations.

**Do NOT proceed until the dry run is complete.**

---

## `start_mission_run` Return Conditions (from binary)

The blocking call returns control to the orchestrator when:

1. **Worker handoff has actionable items** — `discoveredIssues`, unfinished work, or `returnToOrchestrator=true`
2. **User pauses the mission**
3. **All features complete**

### Return Payload

Returns `workerHandoffs` — an array of worker handoff **summaries** since the last run. Each summary includes:
- Worker's feature
- Pass/fail status
- Counts of discovered issues / unfinished work
- `handoffFile` path (for full handoff JSON)

Also includes `latestWorkerHandoff` — the latest newly-returned handoff shown inline in full.

### How to Respond

1. Review handoff summary
2. Decide if fixable within mission or requires user input
3. **Delegate analysis to subagents** — have them review the full handoff, analyze root causes, recommend fix approaches. Orchestrator synthesizes findings into decisions, does not investigate details itself.
4. If fixable: create follow-up features and/or update existing feature descriptions, then call `start_mission_run` again
5. If user input required: return to user with clear explanation

To resume after handling the halt cause, call `start_mission_run` again.

---

## Assertion Lifecycle (from binary)

### No "Cancelled" State

Assertions do NOT have a "cancelled" state. When a requirement is dropped:
- Assertions are **removed entirely** from both `validation-contract.md` and `validation-state.json`
- The contract is a living specification of current requirements, not a history log
- Git history provides the audit trail
- Features use `"cancelled"` status because they serve as execution history; assertions don't need this because they represent what's true *now*

### Contract Update Semantics (Mid-Mission)

| Change | Contract Action | State Action |
|--------|----------------|--------------|
| Added requirement | Write new assertions following existing format/ID conventions | Add IDs as `"pending"` |
| Removed requirement | Delete assertions from contract | Remove IDs entirely |
| Modified requirement (criteria changed) | Update behavioral description and pass/fail criteria | Reset to `"pending"` if old evidence no longer proves the assertion |
| Modified requirement (cosmetic) | Update wording | Leave status unchanged |

---

## Handling Worker Returns — Detailed (from binary)

### Milestone Validation Flow

Both `scrutiny-validator` and `user-testing-validator` are **auto-injected** when a milestone completes. The orchestrator does NOT create these manually.

### Scrutiny Validator Output

Produces a synthesis report:
```json
{
  "passedAssertions": ["VAL-AUTH-001", "VAL-AUTH-002"],
  "failedAssertions": [
    { "id": "VAL-CHECKOUT-003", "reason": "Payment form validation missing" }
  ],
  "blockedAssertions": [
    { "id": "VAL-DASHBOARD-001", "blockedBy": "Login broken" }
  ],
  "appliedUpdates": [
    { "target": "user-testing.md|services.yaml", "description": "...", "source": "setup|flow-report" }
  ],
  "previousRound": null
}
```

Commits: synthesis report + updated `validation-state.json` + any `.factory/services.yaml` or `.factory/library/` changes (single atomic commit).

### User Testing Validator Behavior

- Reads `.factory/library/user-testing.md` and `services.yaml` for testing surface knowledge
- Determines testable assertions from features' `fulfills` field
- Sets up environment (starts services, seeds data), resolving setup issues if needed
- May update `library/user-testing.md` and `services.yaml` with corrections
- Plans isolation strategy (assigns test accounts/data namespaces per subagent)
- Spawns flow validator subagents to test assertions
- **May spend entire session resolving setup issues** without testing assertions — if so, just re-run (no fix features needed)

---

## AGENTS.md Structure (from binary)

Must include:

### Mission Boundaries (NEVER VIOLATE)

```markdown
## Mission Boundaries (NEVER VIOLATE)
**Port Range:** 3100-3199. Never start services outside this range.
**External Services:**
- USE existing postgres on localhost:5432 (do not start a new database)
```

### Required Sections

- **Mission Boundaries** — port ranges, external services, off-limits resources
- **Coding conventions** — architectural patterns, style rules
- **User-provided instructions** — preferences (may be updated mid-run)
- **Testing & Validation Guidance** (optional) — instructions for validators on how to test, what to skip, credentials, special considerations. Validators treat this section as **authoritative**.

---

## Mid-Mission Scope Changes — Full Protocol (from binary)

When user requests something substantial mid-mission:

1. **Pause execution** — don't immediately decompose into features
2. **Clarify and investigate iteratively** — interleave as needed:
   - Ask clarifying questions
   - Investigate via subagents (implications, affected code, dependencies)
   - Online research if new technologies introduced
   - Ask again if investigation reveals ambiguities
   - For significant requests: multiple subagents (one per affected area) + synthesis pass
3. **Propose the change** — explain how it's incorporated
4. **Get confirmation** — wait for user agreement
5. **Update validation contract** — delegate to subagents (Task tool) to preserve context window:
   - **Small scope changes**: single subagent with description + paths
   - **Large scope changes**: per-area subagents → reports → single subagent applies changes
   - Orchestrator does NOT edit contract files itself during mid-mission updates
6. **Ensure full assertion coverage** — reconcile `fulfills` arrays against new/removed VAL IDs
7. **Update `mission.md`** if scope changed
8. **Commit and resume** — single atomic commit for all artifact updates → `start_mission_run`

### Scope Reduction

When user removes scope: cancel affected features (don't delete). Delegate contract cleanup to subagent. Update `mission.md`.

### Scope Too Large

If scope change would fundamentally restructure the mission → tell user to start a new mission instead.


---

## Process Safety Rules (from binary)

Workers operate under strict process safety constraints to prevent collateral damage:

### NEVER Do
- `pkill node`, `killall node`, or any kill-by-process-name
- Kill processes on ports you didn't declare in `services.yaml`
- Kill user processes that were running before the mission started
- `kill -9` without trying graceful shutdown first

### ALLOWED
- Stop services using their `stop` command from `services.yaml`
- Kill PIDs that **you** started (tracked in worker state)
- Port-based kills **only** on ports declared in `services.yaml`
- Graceful shutdown signals (SIGTERM before SIGKILL)

### Rationale
Workers run in the user's environment alongside their other work. A stray `pkill node` could kill the user's dev server, Electron app, or other critical processes. The safety rules ensure workers only manage processes they own.

---

## services.yaml Full Schema (from binary)

```yaml
services:
  - name: api-server          # Unique name (no duplicates allowed)
    start: "bun run dev"      # Start command
    stop: "kill $(lsof -ti:3100)"  # Stop command (must reference same port)
    healthcheck: "curl -sf http://localhost:3100/health"  # Must reference same port
    port: 3100                # Declared port (must be consistent across start/stop/healthcheck)
    depends_on:               # Optional: services that must be healthy first
      - postgres

commands:
  - name: seed-db             # Unique name
    command: "bun run db:seed" # Just the command string
```

### Schema Rules
- **Services** require: `name`, `start`, `stop`, `healthcheck`, `port`
- **Commands** require: `name`, `command`
- Port must be **hardcoded and consistent** across `start`, `stop`, and `healthcheck`
- No duplicate names or ports across all services
- Changes are **additive only** — never remove or rename existing services mid-mission
- `depends_on` creates a startup ordering dependency

---

## init.sh Rules (from binary)

`init.sh` runs at **every worker startup** — it must be idempotent:

### MUST
- Be fully idempotent (safe to run 100 times)
- Use guards: `command -v X || install X`, `[ -f .env ] || cp .env.example .env`
- Install dependencies (`bun install`, `pip install -r requirements.txt`)
- Create directories, seed data, generate configs

### MUST NOT
- Start services — that's `services.yaml`'s job
- Contain `bun run dev`, `docker-compose up`, or any long-running process
- Assume it runs only once
- Have side effects that break on re-execution

### Example Pattern
```bash
#!/bin/bash
set -euo pipefail

# Dependencies (idempotent)
bun install

# Database setup (idempotent)
bun run db:migrate 2>/dev/null || true

# Seed data (idempotent guard)
if ! bun run db:check-seed 2>/dev/null; then
  bun run db:seed
fi

# Config (idempotent)
[ -f .env ] || cp .env.example .env
```

---

## EndFeatureRun — Critical Behavior (from binary)

`EndFeatureRun` is the tool workers call to signal completion. **Critical rules:**

1. Worker MUST **stop all services** it started (via `services.yaml` stop commands)
2. Worker MUST **close any browser sessions** it opened
3. Worker MUST **reflect on skill adherence** — did it follow the skill's procedure?
4. Worker MUST **commit all changes** before calling EndFeatureRun
5. Worker MUST **end its turn immediately** after calling EndFeatureRun — no additional tool calls, no more work

### The "Immediately" Rule

After `EndFeatureRun` is called, the worker's session is considered terminated. Any tool calls after `EndFeatureRun` are undefined behavior — they may execute in a half-torn-down environment, corrupt state, or silently fail.

### Handoff Payload

The `EndFeatureRun` call includes the full handoff payload:
- `salientSummary` — what was done
- `whatWasImplemented` / `whatWasLeftUndone`
- `verification` — commands run + results
- `tests` — added/updated test files + coverage
- `discoveredIssues` — blocking and non-blocking issues found
- `skillFeedback` — whether the worker followed the skill procedure, deviations, and suggestions
- `commitId` — the worker's own commit hash (BUG-025: worker-owned attribution)
- `successState` — `"success"` | `"failure"` | `"partial"`

---

## dismiss_handoff_items Tool (from binary)

Orchestrator tool to dismiss items from a worker's handoff that don't need action:

```
dismiss_handoff_items({
  handoffId: "handoffs/2024-01-15T10:30:00Z__checkout-api__ses_abc123.json",
  items: [
    { type: "discoveredIssue", index: 0, justification: "Pre-existing issue, tracked in JIRA-1234" },
    { type: "undoneWork", index: 1, justification: "Out of scope for this milestone" }
  ]
})
```

### Rules
- **Every** handoff item (discovered issues, undone work) must be either **addressed** (by creating a fix feature) or **dismissed** (with justification)
- Justification is **required** — no silent dismissals
- Dismissed items are logged in the handoff record for audit trail
- The orchestrator must not ignore handoff items — they represent real findings from workers

---

## Validation Output Directory Structure (from binary)

Validation results are stored in a structured directory under `.factory/validation/`:

```
.factory/validation/
└── <milestone>/
    ├── scrutiny/
    │   ├── synthesis.json           # Overall results + applied updates
    │   └── features/
    │       ├── <feature-id-1>.json  # Per-feature code review report
    │       └── <feature-id-2>.json
    └── user-testing/
        ├── synthesis.json           # Overall results + flow outcomes
        └── flows/
            ├── <flow-name-1>.json   # Per-flow test report
            └── <flow-name-2>.json
```

### synthesis.json Contents
- `passedAssertions` — VAL IDs that passed
- `failedAssertions` — VAL IDs that failed with reasons
- `blockedAssertions` — VAL IDs blocked by other failures
- `appliedUpdates` — changes the validator made to `.factory/` files
- `suggestedGuidanceUpdates` — proposed changes for AGENTS.md
- `previousRound` — link to prior validation round (for re-validation tracking)

---

## Scrutiny Feature Reviewer — Shared State Observations (from binary)

The scrutiny validator's per-feature code reviewers categorize findings into 4 observation types that feed back into the mission's shared knowledge:

### 1. Convention Gaps
Patterns the codebase uses that aren't documented in AGENTS.md:
- Naming conventions, file organization patterns
- Error handling patterns, logging conventions
- **Action:** Triaged into `apply-now` (add to AGENTS.md immediately), `recommend` (suggest to orchestrator), or `reject` (not a real convention)

### 2. Skill Gaps
Procedures in the worker's skill definition that are missing, wrong, or incomplete:
- Steps that don't match actual codebase patterns
- Missing verification steps
- **Action:** Feed back into `.factory/skills/<name>/SKILL.md` updates

### 3. Services/Commands Gaps
Missing or incorrect entries in `services.yaml`:
- Services the worker had to start manually
- Health checks that don't work
- **Action:** Update `services.yaml` directly (validator has write access)

### 4. Knowledge Gaps
Missing information in `.factory/library/` files:
- API patterns, auth flows, data models not documented
- External service integration details
- **Action:** Update or create `.factory/library/<topic>.md` files

All observations are committed as part of the validator's atomic commit, improving the mission's shared infrastructure for subsequent workers.

---

## MissionWakeLock (from binary)

Prevents the machine from sleeping during long mission runs:

| Platform | Mechanism | Command |
|----------|-----------|---------|
| macOS | `caffeinate` | `caffeinate -dims` (display + idle + disk + system) |
| Linux | `systemd-inhibit` | `systemd-inhibit --what=idle:sleep --who=droid --why="Mission running"` |
| Windows | PowerShell | `SetThreadExecutionState` via PowerShell script |

### Behavior
- Acquired when `start_mission_run` begins
- Released when the run returns (completion, pause, or error)
- **Graceful degradation** — if the wake lock tool isn't available (e.g., `caffeinate` not found), the mission continues without it. A warning is logged but execution is not blocked.
- The lock prevents idle sleep only — user can still manually sleep the machine

---

## Infrastructure Resilience — Daemon Failures (from binary)

When the `factoryd` daemon encounters an error during mission execution:

1. **First failure** — automatic retry of the failed operation
2. **Second failure** — mission pauses and tells the user to restart Droid

The orchestrator does NOT attempt complex recovery strategies. The daemon is the single point of coordination, and if it's unhealthy, the safest action is a clean restart.

### Worker Crash Recovery
- If a worker process dies unexpectedly, its feature is set to `runtimeStatus: "failed"`
- The orchestrator treats it like a failed handoff — can retry (reset to pending) or create fix features
- Worker session transcripts are preserved even on crash (daemon captures what it has)

---

## User Testing Flow Validator — Resource Awareness (from binary)

The user-testing validator spawns parallel subagents (one per flow), which can exhaust system resources:

### Isolation Strategy
Each flow validator subagent gets:
- **Unique test account** — separate user credentials per subagent
- **Unique data namespace** — isolated test data (e.g., prefixed DB records)
- **Separate browser context** — no shared cookies or session state

### Resource Considerations
- Parallel subagents share CPU, memory, and network
- Too many simultaneous browser instances can cause timeouts and flaky results
- The validator plans subagent count based on available system resources
- If flows interfere with each other (e.g., competing for limited inventory), they must run sequentially

### Setup Resolution
Before spawning flow subagents, the validator:
1. Starts all required services from `services.yaml`
2. Runs setup/seed steps
3. Verifies the application is in a testable state
4. If setup fails, **the entire session may be spent resolving setup issues** — this is expected behavior, not a failure. Just re-run the validator.

---

## Validation Override Mechanism (from binary)

When validators produce incorrect results (false positives, environmental issues, etc.):

### How to Override
Add justification directly to `synthesis.json`:

```json
{
  "failedAssertions": [
    {
      "id": "VAL-CHECKOUT-003",
      "reason": "Payment form timeout during test",
      "override": {
        "status": "pass",
        "justification": "Timeout was due to test environment network latency, not a real failure. Manually verified payment form works correctly.",
        "overriddenBy": "orchestrator",
        "overriddenAt": "2024-01-15T10:30:00Z"
      }
    }
  ]
}
```

### Rules
- Override must include `justification` explaining why the validator's result is wrong
- The override is **schema-compatible** — it extends the existing synthesis format
- Overridden failures can get **misc fix features** later if the orchestrator wants to address the underlying issue
- Overrides are committed to git as part of the validation record
- `validation-state.json` is updated to reflect the overridden status

---

## agent-browser Full Command Reference (from binary)

### Navigation
| Command | Purpose |
|---------|---------|
| `open <url>` | Navigate to URL |
| `back` | Go back in history |
| `forward` | Go forward in history |
| `reload` | Reload current page |
| `close` | Close current tab |
| `connect` | Connect to existing browser session |

### Interaction
| Command | Purpose |
|---------|---------|
| `snapshot` | Capture page structure (returns ref IDs) |
| `snapshot -i` | Interactive snapshot (includes form state) |
| `snapshot -i -C` | Interactive snapshot with computed styles |
| `click @ref` | Click element by ref ID |
| `fill @ref "value"` | Fill input element |

### Screenshots & Diffing
| Command | Purpose |
|---------|---------|
| `screenshot` | Take screenshot of current viewport |
| `diff snapshot --baseline <file>` | Compare current snapshot against baseline |
| `diff screenshot --baseline <file>` | Compare current screenshot against baseline |

Elements are referenced by **stable refs** (`@e1`, `@e2`), not CSS selectors. Always take a snapshot first to discover available refs.


---

## Scrutiny Validator — Exact Execution Procedure (Binary-Verified)

> Source: Built-in skill `scrutiny-validator` (variable `gLH` / procedure `mLB` in binary). Auto-injected as `scrutiny-validator-<milestone>` when all implementation features in a milestone complete.

The scrutiny validator runs a **6-phase procedure** inside a single worker session:

### Phase 1: Automated Quality Gates

Runs three commands sequentially, recording exact exit codes and full output:

```
EXECUTE (bun test, timeout: 120s, impact: medium)
EXECUTE (bun x tsc --noEmit, timeout: 60s, impact: medium)  
EXECUTE (bun x eslint ., timeout: 60s, impact: low)
```

- **CRITICAL**: Output must NOT be piped through `| tail`, `| head`, or similar — full output is required for accurate assessment
- Each command's exit code and observation are recorded in the handoff's `verification.commandsRun[]`
- Failures here don't immediately fail the feature — they're inputs to the review phases

### Phase 2: Feature-by-Feature Code Review

For each completed feature in the milestone:
- Spawns a **review subagent** that examines the feature's changes
- Reviews against the feature's `expectedBehavior` and `verificationSteps`
- Produces per-feature observations (see "Scrutiny Feature Reviewer" section above)

### Phase 3: Contract Assertion Checking

- Reads `validation-contract.md` for the milestone
- Checks each assertion ID (e.g., `VAL-TOOL-004`) against actual project state
- Records pass/fail/blocked/skipped per assertion in `validation-state.json`

### Phase 4: Cross-Feature Integration Review

- Looks for integration issues between features completed in this milestone
- Checks for conflicting imports, duplicate functionality, broken cross-references

### Phase 5: Synthesis

- Aggregates all findings from phases 1–4
- Classifies issues as `blocking` vs `non_blocking` in `discoveredIssues[]`
- Determines overall `successState`: `"success"` | `"failure"` | `"partial"`

### Phase 6: Handoff

- Always sets `returnToOrchestrator: true` (scrutiny validators always return)
- Commits any fixes made during review (if the validator fixed minor issues)
- Writes structured handoff JSON with full verification data

### Skip Mechanism

The `skipScrutiny` flag in `model-settings.json` bypasses scrutiny validation entirely:

```json
// model-settings.json
{
  "skipScrutiny": true  // Skips scrutiny-validator injection for all milestones
}
```

When skipped, `checkMilestoneCompletionAndInjectValidation` does not create the `scrutiny-validator-<milestone>` feature.

---

## Technical-Writer README Feature (Dynamically Planned)

> Source: Observed in mission execution logs. NOT a built-in binary behavior — created by the orchestrator during `define-mission-skills` planning phase.

### What Happens

When the orchestrator plans a mission, it may create a **technical-writer** feature as the final task:

```
TASK (technical-writer: "create root README")
```

This appears as a regular feature in `features.json`:

```json
{
  "id": "technical-writer-readme",
  "description": "Create comprehensive root README.md documenting the project...",
  "skillName": "technical-writer",
  "preconditions": ["<all other features>"],
  "expectedBehavior": ["README.md exists at project root", "Covers setup, usage, architecture"],
  "verificationSteps": ["test -f README.md"],
  "milestone": "<final milestone>",
  "status": "pending"
}
```

### Key Points

- **Not hardcoded** — the orchestrator decides whether to include this based on the mission's scope and the `define-mission-skills` output
- **`technical-writer` is a droid persona** (one of 142 in `~/.factory/droids/`), not a built-in skill
- The worker loads `mission-worker-base` (built-in) + the droid persona's instructions
- Preconditions typically include all implementation features, so it runs last
- The README content is generated based on what was actually built, not the original plan

### When It Appears

- Missions that create new projects or significant new functionality
- The orchestrator's planning phase decides this — it's not automatic for every mission
- Can be skipped like any other feature via `mission_skip` tool

