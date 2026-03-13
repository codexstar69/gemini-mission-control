---
name: mission-planner
description: Interactive 7-phase mission planning procedure
---

# Mission Planner

Transforms a project description into complete mission artifacts through 7 interactive phases. This is a conversation with the user — present findings, ask for confirmation, iterate on feedback.

## Activation
- `/mission-plan` with state=`planning`
- Mission dir must exist at `~/.gemini-mc/missions/mis_<id>/`

---

## Phase 1: Understand Requirements

If the description is vague (you can't write ≥3 specific behavioral assertions for the project), ask clarifying questions before proceeding:
- What core problem does this solve? Who are the target users?
- Must-have features vs nice-to-haves?
- Tech stack, frameworks, language requirements?
- Greenfield project or modifying an existing codebase?
- External integrations (APIs, databases, auth providers)?
- What does "done" look like — acceptance criteria?
- Performance, security, compliance requirements?
- Deployment target (cloud, local, container)?

**For existing codebases:** Use `list_directory`, `read_file`, `grep_search` to investigate project structure, tech stack, existing tests, CI/CD configuration, and dependencies.

**Output to present:** Project purpose and scope, tech stack, numbered functional requirements, non-functional requirements, constraints and risks.

---

## Phase 2: Investigate Codebase

1. Map directory structure (`list_directory` on root, src/, tests/, etc.)
2. Read config files (package.json, tsconfig, Dockerfile, CI configs)
3. Identify patterns (`grep_search` for test frameworks, API routes, DB schemas, env vars)
4. Check infrastructure (Docker, Kubernetes, existing services/ports)

**Output to present:** Tech stack summary, project structure map, test infrastructure, services/dependencies, build/run commands, coding conventions observed.

---

## Phase 3: Identify Milestones

### Milestone Principles
- **Vertical slices** (not horizontal layers) — each milestone delivers end-to-end testable value
- **3–8 features per milestone**, each completable by one worker in one session
- **Lowercase hyphenated names** (e.g., `foundation`, `user-auth`, `api-endpoints`)

### Feature Fields
Each feature requires:
- `id` — unique, lowercase with hyphens (e.g., `setup-database`, `user-registration`)
- `description` — detailed implementation instructions for the worker
- `skillName` — agent type: `mission-worker`, `code-quality-worker`, or custom
- `milestone` — which milestone this belongs to
- `preconditions` — array of feature IDs that must complete first (forms a DAG)
- `expectedBehavior` — array of concrete, verifiable behavior statements
- `verificationSteps` — array of shell commands that prove the feature works
- `fulfills` — array of VAL-XXX-NNN assertion IDs this feature satisfies

### DAG Acyclicity Check (MANDATORY)

Before proceeding, verify the precondition graph has no cycles using topological sort:

1. For each feature, compute its in-degree (number of features it depends on)
2. Initialize a queue with all features that have in-degree 0
3. While queue is non-empty: dequeue a feature, decrement in-degree of all features that list it as a precondition, enqueue any that reach in-degree 0
4. If the number of processed features equals total features → graph is acyclic ✓
5. If not → cycle detected → restructure: merge tightly coupled features, remove soft dependencies, or reorder milestones

**Never proceed to Phase 4 with cyclic dependencies.** Also avoid long dependency chains (>5 deep) which block parallelism and increase risk of partial-completion cascades.

**Output to present:** Milestone/feature list with preconditions and DAG verification result.

---

## Phase 4: Confirm Milestones

Present the plan to the user. For each milestone show: name, features with descriptions, preconditions, expected behaviors, and assertion previews.

Ask for explicit confirmation:
- "Does this breakdown match your expectations?"
- "Any missing features, wrong ordering, or milestones to merge/split?"

On feedback: update the plan → re-run DAG check → re-present for confirmation.

**Do NOT proceed to Phase 5 until the user explicitly confirms the milestone plan.**

---

## Phase 5: Plan Infrastructure

1. Identify required services (DB, cache, queue, dev servers) and assign ports (3000–9999)
2. Define mission boundaries (off-limits directories/files, required env vars — never store actual secrets in plan files)
3. Plan `services.yaml` structure:
   ```yaml
   services:
     <service-name>:
       start: "<start command>"
       stop: "<stop command>"
       healthcheck: "<healthcheck command>"
       port: <port>
       depends_on: [<dependency list>]
   commands:
     test: "<test command>"
     typecheck: "<typecheck command>"
     lint: "<lint command>"
     build: "<build command>"
   ```
4. Plan `init.sh`: install deps, create directories, set up env files, run migrations. Must be idempotent (safe to run multiple times) with `#!/usr/bin/env bash` and `set -euo pipefail`.

**Output to present:** Services, ports, boundaries, services.yaml plan, init.sh plan.

---

## Phase 6: Plan Testing

1. Identify the testing surface (unit, integration, e2e, manual/interactive)
2. Determine test tooling (framework, coverage, linting, typecheck commands)
3. Define verification commands workers will run after each feature
4. Plan behavioral assertions per milestone with evidence requirements (commands that prove the assertion)
5. Plan `library/user-testing.md` documenting: how to reach the app, entry points for testing, what to test and how

**Output to present:** Testing strategy with commands, assertions approach, and user-testing documentation plan.

---

## Phase 7: Generate Artifacts

Write all artifacts to disk using `write_file`.

### 7.1 `validation-contract.md`
Write to `~/.gemini-mc/missions/mis_<id>/validation-contract.md`.

Each assertion follows the `VAL-<AREA>-<NNN>` format (regex: `VAL-[A-Z]{2,6}-[0-9]{3}`):

```markdown
## Area: Authentication

### VAL-AUTH-001: User registration creates account
When a POST request is sent to /api/auth/register with valid email and password,
the response status is 201, the body contains a userId, and the user exists in the database.
Evidence: `curl -X POST http://localhost:3000/api/auth/register -d '...' -H 'Content-Type: application/json'` returns 201
```

### 7.2 `features.json`
Write to `~/.gemini-mc/missions/mis_<id>/features.json`.

```json
{
  "features": [
    {
      "id": "setup-database",
      "description": "Initialize PostgreSQL database with connection pooling...",
      "skillName": "mission-worker",
      "milestone": "foundation",
      "preconditions": [],
      "expectedBehavior": ["PostgreSQL database is accessible", "Users table exists"],
      "verificationSteps": ["psql -c 'SELECT 1' exits with code 0"],
      "fulfills": ["VAL-DB-001"],
      "status": "pending"
    }
  ]
}
```

**Coverage gate (MANDATORY before proceeding):**
1. Extract all VAL-XXX-NNN IDs from `validation-contract.md`
2. Collect all IDs from all features' `fulfills` arrays
3. Verify:
   - **No orphans:** every VAL ID from the contract is claimed by at least one feature
   - **No duplicates:** no VAL ID appears in more than one feature's `fulfills`
   - **No phantoms:** every VAL ID in `fulfills` exists in the contract
4. Fix any violations before proceeding

### 7.3 `validation-state.json`
Write to `~/.gemini-mc/missions/mis_<id>/validation-state.json`.
Map every VAL ID from the contract to `{"status":"pending"}`:
```json
{"assertions": {"VAL-AUTH-001": {"status": "pending"}, "VAL-DB-001": {"status": "pending"}}}
```

### 7.4 `AGENTS.md`
Write to `~/.gemini-mc/missions/mis_<id>/AGENTS.md`.

This file is read by every worker agent at startup. Include:
- **Working directory:** the absolute path to the project
- **Mission boundaries:** files/directories workers must NOT modify, external services they must NOT access
- **Known pre-existing issues:** failures that existed before the mission started (so workers don't try to fix them)
- **Coding conventions:** language style, naming conventions, import ordering, test naming patterns observed in Phase 2
- **Verification commands:** quick reference to test/lint/typecheck commands from services.yaml

### 7.5 `mission.md`
Update `~/.gemini-mc/missions/mis_<id>/mission.md` with: original description, refined requirements, confirmed milestone plan, architecture decisions, testing strategy.

### 7.6 Scaffold `.mission/`
Create `<workingDirectory>/.mission/` with:
- `services.yaml` — from Phase 5 plan
- `init.sh` — from Phase 5 plan (run `chmod +x` to make executable)
- `library/architecture.md` — architecture decisions from Phase 2
- `library/environment.md` — environment setup documentation
- `library/user-testing.md` — testing surface from Phase 6
- `skills/` — per-mission worker SKILL.md files if custom types were identified
- `research/` — empty directory for future research artifacts

### 7.7 State Transition: `planning` → `orchestrator_turn`

**Pre-transition coverage gate re-verification (MANDATORY):**
1. Re-read the just-written `validation-contract.md`, extract all VAL IDs
2. Re-read the just-written `features.json`, collect all `fulfills` IDs
3. Verify: no orphans, no duplicates, no phantoms
4. **If any check fails → STOP.** Fix the violations, re-write the files, re-verify. Do NOT transition.

Once the coverage gate passes:
1. Update `state.json`: set `state` to `"orchestrator_turn"`, set `totalFeatures` to the feature count, update `updatedAt` to current ISO 8601 timestamp
2. Read back `state.json` to verify the write succeeded
3. Append to `progress_log.jsonl`: `{"timestamp":"<ISO 8601>","event":"state_transition","from":"planning","to":"orchestrator_turn","totalFeatures":<N>,"coverageGatePassed":true}`
4. Inform the user: "Plan applied. Coverage gate passed. Ready for `/mission-run`."
