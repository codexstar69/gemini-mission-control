---
name: mission-planner
description: Interactive 7-phase mission planning procedure
---

# Mission Planner

This skill guides the orchestrator through a structured 7-phase interactive planning procedure. It transforms a user's project description into a complete set of mission artifacts: validation contracts, feature decompositions, infrastructure configuration, and testing strategy.

## When to Use This Skill

Activate this skill when:
- The user invokes `/mission-plan` for an existing mission
- A mission is in `planning` state and needs its plan generated
- The user wants to re-plan or adjust the plan for a mission

## Prerequisites

Before starting, confirm:
1. A mission directory exists at `~/.gemini-mc/missions/mis_<id>/`
2. `state.json` shows `"state": "planning"`
3. You have the user's project description (from `mission.md` or the original `/mission-start` input)

---

## Phase 1: Understand Requirements

**Goal:** Deeply understand what the user wants to build before generating any plan artifacts.

### Handling Vague or Minimal Descriptions

If the user's project description is vague, minimal, or ambiguous (e.g., "build an app", "make a website", "fix my project"), you MUST ask clarifying questions before proceeding. Do NOT generate a plan from insufficient context.

Ask questions such as:
- What is the core problem this project solves?
- Who are the target users?
- What are the must-have features vs. nice-to-haves?
- Are there specific technologies, frameworks, or languages required?
- Is this a greenfield project or does it modify an existing codebase?
- Are there external integrations (APIs, databases, auth providers)?
- What does "done" look like — what are the acceptance criteria?
- Are there performance, security, or compliance requirements?
- What is the deployment target (cloud, local, container, etc.)?

Continue asking until you have enough detail to decompose the project into concrete milestones and features. A good rule of thumb: if you cannot write at least 3 specific behavioral assertions for the project, the description is too vague.

### Investigating the Existing Codebase

If the user's `workingDirectory` points to an existing project (not an empty directory), use the following tools to understand it:

```
read_file — Read key files (README, package.json, Cargo.toml, go.mod, etc.)
grep_search — Search for patterns, imports, configuration
list_directory — Explore the directory structure
```

Specific investigation steps:
1. Use `list_directory` on the working directory to understand the top-level structure
2. Use `read_file` on README.md, package.json, or equivalent project manifest
3. Use `grep_search` to find existing test files, configuration, CI/CD setup
4. Use `read_file` on any existing `.mission/` directory contents (if present from a previous plan)
5. Identify the tech stack, existing patterns, and conventions

### Output of Phase 1

Produce a written summary (in your response to the user) covering:
- Project purpose and scope
- Target tech stack and frameworks
- Key functional requirements (numbered list)
- Non-functional requirements (performance, security, etc.)
- Identified constraints and risks

---

## Phase 2: Investigate Codebase

**Goal:** Build a thorough understanding of the project's codebase structure, conventions, and existing infrastructure.

### Steps

1. **Map the directory structure:**
   ```
   list_directory on workingDirectory (top level)
   list_directory on src/, lib/, app/, or equivalent
   list_directory on tests/, test/, spec/, or equivalent
   ```

2. **Read key configuration files:**
   ```
   read_file on package.json / Cargo.toml / go.mod / requirements.txt / pyproject.toml
   read_file on tsconfig.json / .eslintrc / biome.json / prettier config
   read_file on Dockerfile / docker-compose.yml (if exists)
   read_file on CI config (.github/workflows/, .gitlab-ci.yml, etc.)
   ```

3. **Identify existing patterns:**
   ```
   grep_search for test frameworks (jest, vitest, pytest, go test, etc.)
   grep_search for existing API routes or handlers
   grep_search for database schemas or migrations
   grep_search for environment variable usage (.env patterns)
   ```

4. **Check for existing infrastructure:**
   ```
   grep_search for docker, kubernetes, terraform patterns
   grep_search for existing services (database, redis, message queue)
   list_directory on any deploy/, infra/, or ops/ directories
   ```

### Output of Phase 2

Document your findings:
- Tech stack summary (languages, frameworks, build tools)
- Project structure (key directories and their purpose)
- Existing test infrastructure (framework, coverage, how to run)
- Existing services and dependencies
- Build and run commands
- Coding conventions observed

---

## Phase 3: Identify Milestones

**Goal:** Decompose the project into milestone-gated vertical slices, each delivering end-to-end value.

### Milestone Design Principles

1. **Vertical slices**: Each milestone should deliver a working, testable increment — not a horizontal layer (e.g., "all database models" is bad; "user registration end-to-end" is good).
2. **Dependency ordering**: Earlier milestones provide the foundation for later ones. Infrastructure/setup milestones come first.
3. **Testability**: Every milestone must be independently verifiable. If you can't write behavioral assertions for it, it's not a good milestone.
4. **Size**: Aim for 3–8 features per milestone. Fewer than 3 suggests the milestone is too granular; more than 8 suggests it should be split.
5. **Naming**: Use lowercase, hyphenated names (e.g., `foundation`, `user-auth`, `api-endpoints`, `dashboard-ui`).

### Feature Design Within Milestones

For each milestone, identify the features (units of work) needed:

1. **Feature granularity**: Each feature should be completable by a single worker in one session (roughly 30–60 minutes of agent work). If it's too large, split it.
2. **Preconditions**: Define what other features must be completed first. Preconditions create a DAG (directed acyclic graph) of execution order.
3. **Expected behavior**: Write concrete, verifiable statements about what the feature produces.
4. **Verification steps**: Define shell commands or checks that prove the feature is done.
5. **Skill assignment**: Assign a `skillName` that maps to the worker agent type (e.g., `mission-worker`, `code-quality-worker`).

### DAG Acyclicity Check

Feature preconditions MUST form a valid directed acyclic graph (DAG). Before finalizing the feature list, verify there are no cycles:

1. Build a dependency graph: for each feature, map its `id` to its `preconditions` array.
2. Perform a topological sort (Kahn's algorithm):
   - Compute in-degree for each feature.
   - Initialize a queue with all features that have in-degree 0 (no preconditions).
   - While the queue is non-empty: dequeue a feature, decrement in-degree of all features that depend on it, enqueue any that reach in-degree 0.
   - If the number of processed features equals the total number of features, the graph is acyclic.
3. If a cycle is detected, restructure the features to break the cycle. Common fixes:
   - Merge tightly coupled features into one.
   - Remove a precondition that creates the cycle (if the dependency is soft).
   - Reorder milestones so the dependency flows in one direction.

**Never proceed to Phase 4 with a cyclic dependency graph.**

### Output of Phase 3

Present the milestone plan as a structured list:

```
Milestone 1: <name>
  Feature 1.1: <description> (preconditions: none)
  Feature 1.2: <description> (preconditions: 1.1)
  ...

Milestone 2: <name>
  Feature 2.1: <description> (preconditions: 1.2)
  ...
```

---

## Phase 4: Confirm Milestones

**Goal:** Present the milestone plan to the user and get explicit confirmation before generating artifacts.

### Presentation Format

Present each milestone with:
1. **Milestone name** and purpose
2. **Features** with descriptions, preconditions, and expected behaviors
3. **Validation assertions** (preview of what will be tested)
4. **Estimated scope** (number of features, rough complexity)

### User Interaction

Ask the user:
- "Does this milestone breakdown match your expectations?"
- "Are there any features missing or features that should be removed?"
- "Should any milestones be reordered or merged?"
- "Are the preconditions correct — does this execution order make sense?"

### Handling Feedback

If the user requests changes:
1. Update the milestone/feature plan accordingly
2. Re-run the DAG acyclicity check on the updated preconditions
3. Re-present the updated plan for confirmation
4. Repeat until the user explicitly confirms

**Do NOT proceed to Phase 5 until the user has confirmed the milestone plan.**

---

## Phase 5: Plan Infrastructure

**Goal:** Determine the services, ports, environment setup, and operational boundaries for the mission.

### Steps

1. **Identify required services:**
   - Database (PostgreSQL, MySQL, SQLite, MongoDB, etc.)
   - Cache (Redis, Memcached)
   - Message queue (RabbitMQ, Kafka)
   - External APIs (authentication providers, payment gateways)
   - Development servers (frontend dev server, API server)

2. **Assign ports:**
   - Choose ports from a reasonable range (3000–9999)
   - Avoid conflicts with common services
   - Document each port assignment

3. **Define boundaries:**
   - What directories/files are off-limits
   - What external systems should not be modified
   - What environment variables are required
   - What credentials or API keys are needed (note: never store actual secrets in plan files)

4. **Plan the `services.yaml` contents:**
   ```yaml
   services:
     <service-name>:
       start: "<start command>"
       stop: "<stop command>"
       healthcheck: "<healthcheck command>"
       port: <port number>
       depends_on: [<dependency list>]
   commands:
     test: "<test command>"
     typecheck: "<typecheck command>"
     lint: "<lint command>"
     build: "<build command>"
   ```

5. **Plan the `init.sh` script:**
   - Install dependencies (npm install, pip install, etc.)
   - Create required directories
   - Set up environment files
   - Run database migrations (if applicable)
   - Must be idempotent (safe to run multiple times)

### Output of Phase 5

A documented infrastructure plan including:
- Services and their ports
- Off-limits boundaries
- Required environment variables
- `services.yaml` structure
- `init.sh` steps

---

## Phase 6: Plan Testing

**Goal:** Determine the testing strategy for validating the mission's deliverables.

### Steps

1. **Identify the testing surface:**
   - Unit tests (functions, modules)
   - Integration tests (API endpoints, database queries)
   - End-to-end tests (user flows, CLI commands)
   - Manual/interactive tests (UI, browser-based)

2. **Determine test tooling:**
   - Test framework (Jest, Vitest, pytest, Go test, etc.)
   - Test runners and configuration
   - Coverage tools
   - Linting and type checking tools

3. **Define verification commands:**
   - The exact commands workers will run to verify their work
   - How validators will run the full test suite
   - What constitutes a passing vs. failing verification

4. **Plan user-testing assertions:**
   - For each milestone, identify the key behavioral assertions
   - Determine how each assertion will be tested (command output, file existence, API response, etc.)
   - Define evidence requirements (what proves the assertion passed)

5. **Plan the `user-testing.md` library entry:**
   - Document the testing surface (how to reach the application)
   - List entry points (URLs, CLI commands, file paths)
   - Describe environment setup for testing

### Output of Phase 6

A testing strategy document covering:
- Test framework and commands
- Verification commands for workers
- Behavioral assertions strategy
- User testing approach

---

## Phase 7: Generate Artifacts

**Goal:** Produce all mission artifacts and write them to disk using `write_file`.

### 7.1 Generate `validation-contract.md`

The validation contract defines behavioral assertions that prove the mission's deliverables work correctly. Each assertion follows the `VAL-XXX-NNN` format.

#### VAL-XXX-NNN Format Specification

Assertion IDs follow the pattern: `VAL-<AREA>-<NUMBER>`

- `VAL` — Fixed prefix
- `<AREA>` — 2-6 uppercase letters identifying the functional area (e.g., `AUTH`, `API`, `UI`, `DB`, `SETUP`)
- `<NUMBER>` — 3-digit zero-padded number, sequential within the area (e.g., `001`, `002`, `010`)

Regex pattern: `VAL-[A-Z]{2,6}-[0-9]{3}`

#### Assertion Structure

Each assertion has:
1. **ID**: `VAL-XXX-NNN` format
2. **Title**: Brief descriptive title
3. **Behavioral description**: What must be true, written as a pass/fail criterion
4. **Evidence requirement**: What output or check proves the assertion

#### Example Validation Contract

```markdown
# Validation Contract

## Area: Authentication

### VAL-AUTH-001: User registration creates account
When a POST request is sent to `/api/auth/register` with valid `email` and `password` fields,
the response status is 201, the response body contains a `userId` field, and a corresponding
user record exists in the database.
Evidence: `curl -X POST http://localhost:3000/api/auth/register -d '{"email":"test@example.com","password":"secure123"}' -H 'Content-Type: application/json'` returns 201

### VAL-AUTH-002: Login returns JWT token
When a POST request is sent to `/api/auth/login` with valid credentials, the response
contains an `accessToken` field that is a valid JWT (three dot-separated base64 segments).
Evidence: `curl -X POST http://localhost:3000/api/auth/login -d '{"email":"test@example.com","password":"secure123"}'` returns JSON with accessToken field

## Area: Database

### VAL-DB-001: Migrations create required tables
After running database migrations, the `users`, `sessions`, and `profiles` tables exist
in the database with the correct column schemas.
Evidence: `psql -c "\\dt" | grep -c "users\|sessions\|profiles"` returns 3
```

Write this file to `~/.gemini-mc/missions/mis_<id>/validation-contract.md` using `write_file`.

### 7.2 Generate `features.json`

The features file contains the complete feature decomposition with DAG ordering.

#### Feature Schema

Each feature object has the following fields:

```json
{
  "id": "unique-feature-id",
  "description": "Detailed description of what this feature implements",
  "skillName": "mission-worker",
  "milestone": "milestone-name",
  "preconditions": ["other-feature-id"],
  "expectedBehavior": [
    "First expected behavior statement",
    "Second expected behavior statement"
  ],
  "verificationSteps": [
    "command or check to verify feature is done"
  ],
  "fulfills": ["VAL-AUTH-001", "VAL-AUTH-002"],
  "status": "pending"
}
```

Field descriptions:
- `id` — Unique string identifier (lowercase, hyphens). No duplicates allowed.
- `description` — Detailed description of the implementation work.
- `skillName` — Worker type to dispatch: `mission-worker` (general), `code-quality-worker` (review/refactoring), or a custom skill name.
- `milestone` — Which milestone this feature belongs to.
- `preconditions` — Array of feature IDs that must be completed before this feature can start. Must form a valid DAG (no cycles).
- `expectedBehavior` — Array of concrete, verifiable behavior statements.
- `verificationSteps` — Array of commands or checks proving the feature works.
- `fulfills` — Array of `VAL-XXX-NNN` assertion IDs from the validation contract that this feature satisfies.
- `status` — Always `"pending"` when generated by the planner.

#### Example features.json Entry

```json
{
  "features": [
    {
      "id": "setup-database",
      "description": "Initialize PostgreSQL database with connection pooling, create initial migration for users table with id, email, password_hash, created_at columns.",
      "skillName": "mission-worker",
      "milestone": "foundation",
      "preconditions": [],
      "expectedBehavior": [
        "PostgreSQL database is created and accessible",
        "Users table exists with correct schema",
        "Connection pool is configured"
      ],
      "verificationSteps": [
        "psql -c 'SELECT 1' exits with code 0",
        "psql -c '\\d users' shows expected columns"
      ],
      "fulfills": ["VAL-DB-001"],
      "status": "pending"
    },
    {
      "id": "user-registration",
      "description": "Implement POST /api/auth/register endpoint that validates input, hashes password with bcrypt, stores user in database, and returns 201 with userId.",
      "skillName": "mission-worker",
      "milestone": "user-auth",
      "preconditions": ["setup-database"],
      "expectedBehavior": [
        "POST /api/auth/register returns 201 with userId",
        "Password is hashed before storage",
        "Duplicate email returns 409"
      ],
      "verificationSteps": [
        "curl -X POST localhost:3000/api/auth/register returns 201",
        "Database shows hashed password, not plaintext"
      ],
      "fulfills": ["VAL-AUTH-001"],
      "status": "pending"
    }
  ]
}
```

#### Coverage Gate

Before finalizing `features.json`, enforce the **coverage gate**: every `VAL-XXX-NNN` assertion ID in the validation contract must appear in exactly one feature's `fulfills` array.

**Coverage gate check procedure:**

1. Parse `validation-contract.md` and extract all assertion IDs matching `VAL-[A-Z]+-[0-9]{3}`.
2. Parse `features.json` and collect all IDs from all features' `fulfills` arrays.
3. Check for **orphan assertions**: IDs in the contract that are NOT claimed by any feature. These represent requirements that no feature addresses — this is a plan gap.
4. Check for **duplicate claims**: IDs claimed by more than one feature. Each assertion should be fulfilled by exactly one feature to maintain clear ownership.
5. If orphans or duplicates exist, fix them before proceeding:
   - For orphans: create a feature to address the uncovered assertion, or add the assertion to an existing feature's `fulfills`.
   - For duplicates: assign each assertion to the single most appropriate feature.

**Do NOT proceed to state transition if the coverage gate fails.** The plan is incomplete until every assertion has exactly one responsible feature.

Write `features.json` to `~/.gemini-mc/missions/mis_<id>/features.json` using `write_file`.

### 7.3 Initialize `validation-state.json`

After generating the validation contract, create `validation-state.json` with every assertion ID initialized to `pending` status.

#### Procedure

1. Extract all `VAL-XXX-NNN` IDs from the validation contract.
2. Build the assertions object mapping each ID to `{"status": "pending"}`.
3. Write the file.

#### Format

```json
{
  "assertions": {
    "VAL-AUTH-001": { "status": "pending" },
    "VAL-AUTH-002": { "status": "pending" },
    "VAL-DB-001": { "status": "pending" }
  }
}
```

Valid status values (set during validation, not during planning):
- `"pending"` — Not yet tested (initial state, set by planner)
- `"passed"` — Assertion verified and passing (set by user-testing validator)
- `"failed"` — Assertion tested and failing (set by user-testing validator)
- `"blocked"` — Cannot be tested due to infrastructure or dependency issue (set by user-testing validator)

**Every assertion ID from the validation contract must appear in this file.** Cross-reference the IDs to ensure none are missing.

Write to `~/.gemini-mc/missions/mis_<id>/validation-state.json` using `write_file`.

### 7.4 Generate `AGENTS.md`

Create the mission guidance document at `~/.gemini-mc/missions/mis_<id>/AGENTS.md`.

This file provides guidance to all workers and validators operating in the mission. Include:

1. **Working directory** — Absolute path to the project
2. **Mission boundaries** — Off-limits files/directories, port ranges, external services not to modify
3. **Known pre-existing issues** — Anything workers should not try to fix
4. **Coding conventions** — Language-specific style, frameworks in use, patterns to follow
5. **Verification commands** — How workers should verify their work
6. **State machine reference** — Valid states and transitions

Write to `~/.gemini-mc/missions/mis_<id>/AGENTS.md` using `write_file`.

### 7.5 Generate `mission.md`

Update the mission proposal document at `~/.gemini-mc/missions/mis_<id>/mission.md`.

This should contain:
1. The original project description
2. The refined requirements from Phase 1
3. The milestone plan from Phase 3 (as confirmed in Phase 4)
4. Architecture and infrastructure decisions from Phase 5
5. Testing strategy from Phase 6

Write to `~/.gemini-mc/missions/mis_<id>/mission.md` using `write_file`.

### 7.6 Scaffold `.mission/` Directory

Create the per-project enrichment directory at `<workingDirectory>/.mission/` with the following structure:

```
.mission/
├── services.yaml          # Commands and services manifest
├── init.sh                # Environment setup (idempotent)
├── library/               # Shared knowledge base
│   ├── architecture.md    # Architecture decisions
│   ├── environment.md     # Environment setup details
│   └── user-testing.md    # Testing surface documentation
├── skills/                # Per-mission worker skill definitions
│   └── <worker-type>/
│       └── SKILL.md       # Worker-type-specific procedures
└── research/              # Research artifacts (created empty)
```

#### Creating each file:

1. **`services.yaml`**: Based on the infrastructure plan from Phase 5. Include all services with start/stop/healthcheck commands and all verification commands (test, typecheck, lint, build).

2. **`init.sh`**: Based on the infrastructure plan from Phase 5. Must have `#!/usr/bin/env bash` shebang and `set -euo pipefail`. Must be idempotent. Mark as executable.

3. **`library/architecture.md`**: Document the project's architecture, key design decisions, and component relationships discovered in Phase 2.

4. **`library/environment.md`**: Document environment setup — how to install dependencies, required environment variables, how to start/stop the project.

5. **`library/user-testing.md`**: Document the testing surface — how to reach the application, entry points for testing, what to test and how.

6. **`skills/`**: If custom worker types were identified, create their SKILL.md files here with procedures specific to this project.

7. **`research/`**: Create an empty directory for future research artifacts.

Use `run_shell_command` to create directories (`mkdir -p`) and `write_file` for file contents. Use `run_shell_command` to make `init.sh` executable (`chmod +x`).

### 7.7 State Transition: `planning` → `orchestrator_turn`

After all artifacts are generated and the coverage gate passes, transition the mission state.

#### Procedure

1. Read the current `state.json` from `~/.gemini-mc/missions/mis_<id>/state.json`.
2. Count the total number of features in `features.json`.
3. Update `state.json` with:
   - `"state": "orchestrator_turn"` (was `"planning"`)
   - `"totalFeatures": <count>` (set to the number of features)
   - `"updatedAt": "<current ISO 8601 timestamp>"`
4. Write the updated `state.json` using `write_file`.

#### Verification

After writing, read back `state.json` and confirm:
- `state` is `"orchestrator_turn"`
- `totalFeatures` matches the number of features in `features.json`
- `updatedAt` has been refreshed

Log the state transition to `progress_log.jsonl`:
```json
{"timestamp": "2025-01-15T10:30:00Z", "event": "state_transition", "from": "planning", "to": "orchestrator_turn", "totalFeatures": 12}
```

**The planning phase is now complete.** Inform the user that the plan has been applied and the mission is ready for `/mission-run`.
