---
name: mission-planner
description: Interactive 7-phase mission planning procedure
---

# Mission Planner

Transforms a project description into complete mission artifacts through 7 interactive phases.

## Activation
- `/mission-plan` with state=`planning`
- Mission dir must exist at `~/.gemini-mc/missions/mis_<id>/`

---

## Phase 1: Understand Requirements

If description is vague (can't write ≥3 behavioral assertions), ask clarifying questions:
- Core problem, target users, must-have vs nice-to-have features
- Tech stack, greenfield vs existing, external integrations
- Acceptance criteria, deployment target, performance/security requirements

**For existing codebases:** Use `list_directory`, `read_file`, `grep_search` to investigate structure, tech stack, tests, CI/CD, dependencies.

**Output:** Project purpose, tech stack, functional/non-functional requirements, constraints, risks.

---

## Phase 2: Investigate Codebase

1. Map directory structure (`list_directory` on root, src/, tests/)
2. Read config files (package.json, tsconfig, Dockerfile, CI configs)
3. Identify patterns (`grep_search` for test frameworks, API routes, DB schemas, env vars)
4. Check infrastructure (Docker, Kubernetes, existing services)

**Output:** Tech stack, project structure, test infra, services, build/run commands, conventions.

---

## Phase 3: Identify Milestones

### Principles
- **Vertical slices** (not horizontal layers) — each milestone delivers testable value
- **3–8 features per milestone**, each completable in one worker session
- **Lowercase hyphenated names** (e.g., `foundation`, `user-auth`)

### Feature Design
Each feature needs: `id`, `description`, `skillName`, `milestone`, `preconditions` (feature IDs), `expectedBehavior`, `verificationSteps`, `fulfills` (VAL IDs).

### DAG Acyclicity Check (MANDATORY)
Run Kahn's algorithm on feature preconditions:
1. Compute in-degrees
2. Process zero-in-degree features iteratively
3. If processed count ≠ total features → cycle detected → restructure

**Never proceed with cyclic dependencies.**

**Output:** Milestone/feature list with preconditions and DAG verification.

---

## Phase 4: Confirm Milestones

Present plan to user. For each milestone show: name, features, preconditions, expected behaviors, assertion previews.

Ask for explicit confirmation. On feedback: update plan → re-check DAG → re-present.

**Do NOT proceed until user confirms.**

---

## Phase 5: Plan Infrastructure

1. Identify services (DB, cache, queue, dev servers) and assign ports (3000–9999)
2. Define boundaries (off-limits dirs, env vars needed, no real secrets in files)
3. Plan `services.yaml`:
   ```yaml
   services:
     - name: <name>
       start: "<cmd>"
       stop: "<cmd>"
       healthcheck: "<cmd>"
       port: <N>
       depends_on: [<deps>]
   commands:
     - name: test
       command: "<test cmd>"
   ```
4. Plan `init.sh`: install deps, create dirs, run migrations, set up env. Must be idempotent with `set -euo pipefail`.

**Output:** Infrastructure plan with services, ports, boundaries, services.yaml, init.sh.

---

## Phase 6: Plan Testing

1. Identify testing surface (unit, integration, e2e, manual)
2. Determine tooling (test framework, coverage, linting, typecheck)
3. Define verification commands for workers and validators
4. Plan behavioral assertions per milestone with evidence requirements
5. Plan `library/user-testing.md` with testing surface documentation

**Output:** Testing strategy with commands, assertions, and user-testing approach.

---

## Phase 7: Generate Artifacts

Write all artifacts to disk using `write_file`.

### 7.1 `validation-contract.md`
Write to `~/.gemini-mc/missions/mis_<id>/validation-contract.md`.

Format per assertion:
```markdown
### VAL-AREA-NNN: Title
Behavioral description with clear pass/fail criterion.
Evidence: <command or check that proves it>
```
ID pattern: `VAL-[A-Z]{2,6}-[0-9]{3}`, organized by area + cross-area flows section.

### 7.2 `features.json`
Write to `~/.gemini-mc/missions/mis_<id>/features.json`.

Schema per feature: `{id, description, skillName, milestone, preconditions:[], expectedBehavior:[], verificationSteps:[], fulfills:["VAL-XXX-NNN"], status:"pending"}`.

**Coverage gate (MANDATORY):** Every VAL ID in contract → exactly one feature's `fulfills`. No orphans, no duplicates, no phantom references. Fix violations before proceeding.

### 7.3 `validation-state.json`
Write to `~/.gemini-mc/missions/mis_<id>/validation-state.json`.
Every VAL ID from contract mapped to `{"status":"pending"}`.

### 7.4 `AGENTS.md`
Write to `~/.gemini-mc/missions/mis_<id>/AGENTS.md`.
Include: working directory, mission boundaries, known issues, coding conventions, verification commands.

### 7.5 `mission.md`
Update `~/.gemini-mc/missions/mis_<id>/mission.md` with: original description, refined requirements, milestone plan, architecture decisions, testing strategy.

### 7.6 Scaffold `.mission/`
Create `<workingDirectory>/.mission/` with:
- `services.yaml` — from Phase 5
- `init.sh` — from Phase 5 (make executable with `chmod +x`)
- `library/` — architecture.md, environment.md, user-testing.md
- `skills/` — per-mission worker SKILL.md files if needed
- `research/` — empty directory

### 7.7 State Transition: `planning` → `orchestrator_turn`

**Pre-transition coverage gate re-verification (MANDATORY):**
1. Re-read `validation-contract.md`, extract all VAL IDs
2. Re-read `features.json`, collect all `fulfills` IDs
3. Verify: no orphans, no duplicates, no phantoms
4. **STOP if any check fails** — fix and re-verify

Then:
1. Update `state.json`: `state`→`orchestrator_turn`, set `totalFeatures`, update `updatedAt`
2. Verify by reading back
3. Log state transition to `progress_log.jsonl`
4. Inform user: plan applied, coverage gate passed, ready for `/mission-run`
