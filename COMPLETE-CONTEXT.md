# Gemini Mission Control — Complete Context Reference

> **Version:** 0.1.0 | **Last Updated:** 2026-03-13
> A comprehensive, self-contained reference document for the Gemini Mission Control extension.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [The Droid Concept](#2-the-droid-concept)
3. [Gemini CLI Extension System](#3-gemini-cli-extension-system)
4. [Complete File Tree](#4-complete-file-tree)
5. [Setup & Installation](#5-setup--installation)
6. [Commands Reference](#6-commands-reference)
7. [Agents Reference](#7-agents-reference)
8. [Skills Reference](#8-skills-reference)
9. [State Machine](#9-state-machine)
10. [State File Schemas](#10-state-file-schemas)
11. [Orchestrator Run Loop](#11-orchestrator-run-loop)
12. [Planning Procedure](#12-planning-procedure)
13. [Validation Pipeline](#13-validation-pipeline)
14. [Droid vs This Extension](#14-droid-vs-this-extension)
15. [Scripts Reference](#15-scripts-reference)
16. [Hooks Reference](#16-hooks-reference)

---

## 1. Project Overview

### What This Is

Gemini Mission Control is a **Gemini CLI extension** that replicates the **orchestrator-worker-validator pattern** (inspired by Factory Droids) entirely within Gemini CLI's native architecture. It enables autonomous, multi-agent mission execution — planning complex projects, dispatching worker subagents, validating milestones against behavioral contracts, and delivering completed work — all from within a single `gemini` session.

### The Goal

Autonomous mission-grade coding in Gemini CLI. A user opens `gemini`, types `/mission-start "Build a REST API"`, and the system plans milestones, dispatches workers, validates results, and delivers a completed project without further intervention (until the mission is complete, paused, or blocked).

### Why

Factory Droids demonstrate that the orchestrator-worker-validator pattern produces reliable, validated software at scale. This extension proves the same pattern can be implemented entirely within Gemini CLI's extension system, using the LLM itself as the orchestrator following procedural skill instructions.

### Key Constraint: Pure Declarative

The extension consists entirely of declarative files:

- **Markdown** — Agent definitions, skills, context files (`.md`)
- **TOML** — Command definitions (`.toml`)
- **JSON** — Manifest, hooks, state files (`.json`)
- **Shell scripts** — Helper scripts (`.sh`)

There is **no TypeScript, no build step, and no compiled code**. Everything is read directly by the Gemini CLI extension loader.

---

## 2. The Droid Concept

### Factory Droid's 3-Layer Architecture

Factory Droids implement a 3-layer architecture for autonomous software development:

| Layer | Role | Responsibility |
|-------|------|----------------|
| **Orchestrator** | Mission controller | Plans work, dispatches workers, reviews handoffs, manages state, enforces quality gates |
| **Workers** | Implementation agents | Implement features using TDD, produce structured handoff reports |
| **Validators** | Quality gatekeepers | Run test suites, verify behavioral assertions, seal milestones |

### Validation Contracts (VAL-XXX-NNN)

Behavioral assertions follow the format `VAL-<AREA>-<NUMBER>`:

- `VAL` — Fixed prefix
- `<AREA>` — 2-6 uppercase letters identifying the functional area (e.g., `AUTH`, `API`, `UI`, `DB`, `SETUP`)
- `<NUMBER>` — 3-digit zero-padded number, sequential within the area

Regex: `VAL-[A-Z]{2,6}-[0-9]{3}`

Each assertion defines:
- A pass/fail behavioral criterion
- Evidence requirements (commands, outputs, or checks)

Every feature in the plan must `fulfill` at least one assertion, and every assertion must be fulfilled by exactly one feature (the **coverage gate**).

### Feature DAGs

Features are organized as a **directed acyclic graph (DAG)** through `preconditions` arrays. The orchestrator evaluates the DAG each iteration to find features whose preconditions are all `completed`. Cycles are detected during planning and must be resolved before execution begins.

### Decision Tree (A/B/C/D)

After each worker handoff, the orchestrator applies one of four decisions:

| Option | Trigger | Action |
|--------|---------|--------|
| **A** | High-severity discovered issues | Create follow-up feature in the same milestone (or `misc-*` if sealed) |
| **B** | Worker failure (non-zero exit codes + non-empty `whatWasLeftUndone`) | Reset feature to `pending` with retry context (max 3 retries) |
| **C** | Partial completion (some passing, some remaining) | Update feature description with remaining work |
| **D** | Medium/low-severity issues only, worker success | Mark completed; create misc features for issues |
| **Clean** | No issues, empty `whatWasLeftUndone`, all exit code 0 | Mark completed, no new features |

### Milestone Lifecycle

1. **Implementation** — Workers complete all implementation features
2. **Validator Injection** — Scrutiny + user-testing validator features auto-injected
3. **Validation Execution** — Scrutiny runs first, then user-testing
4. **Sealing** — Both validators pass → milestone added to `sealedMilestones`
5. **Override** (optional) — `/mission-override` forces failed validators to complete

### Sealed Milestones

Once sealed, **no new features may be added to a sealed milestone**. This is enforced in:
- Decision Tree Option A (follow-ups redirected to `misc-*`)
- Decision Tree Option D (misc features always go to `misc-*`)
- Scope changes (new requirements redirected away from sealed milestones)

### Crash Recovery

If a session is interrupted during `worker_running`:
1. The orchestrator detects the state on next run
2. Scans `progress_log.jsonl` for unmatched `worker_started` events
3. Resets stuck features to `pending`
4. Transitions back to `orchestrator_turn`
5. Logs a `crash_recovery` event

### Budget Enforcement

Token usage is tracked after each worker dispatch cycle. When the accumulated total exceeds a configured threshold, the mission auto-pauses with a `budget_pause` event. Resume requires explicit acknowledgment.

### Key Difference: Droid vs This Extension

**Factory Droid** = A deterministic TypeScript runner that controls LLM workers. The orchestrator is code; the workers are LLMs.

**This extension** = The LLM IS the orchestrator, following procedural skill instructions written in markdown. Everything is an LLM. There is no deterministic runtime — the orchestrator's behavior emerges from following the `mission-orchestrator` SKILL.md procedure.

---

## 3. Gemini CLI Extension System

### Manifest Format

The extension manifest (`gemini-extension.json`) registers the extension with Gemini CLI:

```json
{
  "name": "gemini-mission-control",
  "version": "0.1.0",
  "description": "Multi-agent mission control for Gemini CLI",
  "contextFileName": "GEMINI.md",
  "commandsDir": "commands",
  "skillsDir": "skills",
  "hooksDir": "hooks"
}
```

| Field | Purpose |
|-------|---------|
| `name` | Extension identifier |
| `version` | Semantic version |
| `description` | Human-readable description |
| `contextFileName` | Markdown file loaded as orchestrator context (the LLM's "identity") |
| `commandsDir` | Directory containing TOML command definitions |
| `skillsDir` | Directory containing skill subdirectories |
| `hooksDir` | Directory containing hooks configuration |

### Agents

Agent definitions are markdown files in `agents/` with YAML frontmatter:

```markdown
---
name: agent-name
description: "What this agent does"
kind: local
tools:
  - read_file
  - write_file
model: gemini-2.5-pro
temperature: 0.1
max_turns: 100
timeout_mins: 30
---

# Agent instructions as markdown body...
```

**Rules:**
- `kind` **must always be `local`** (never `kind: agent`)
- `name` must be lowercase with hyphens/underscores only
- `tools` must only contain valid Gemini CLI tool names (see below)
- The markdown body serves as the agent's system prompt

### Skills

Skills are procedural knowledge activated on demand via `activate_skill`. Each skill lives in `skills/<name>/SKILL.md`:

```markdown
---
name: skill-name
description: "What this skill provides"
---

# Skill Name

## When to Use This Skill
...

## Procedure
...
```

The directory name must match the `name` field in the frontmatter.

### Commands

Commands are TOML files in `commands/`. Each defines a slash command:

```toml
description = "Brief description shown in /help"
prompt = """
The prompt sent to the model when the command is invoked.
Use {{args}} for user arguments.
"""
```

The filename (minus `.toml`) becomes the command name with `/` prefix (e.g., `mission-start.toml` → `/mission-start`).

### Hooks

Hooks are defined in `hooks/hooks.json`. They run shell commands at lifecycle events:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "*",
        "hooks": [
          {
            "name": "hook-name",
            "type": "command",
            "command": "scripts/session-context.sh",
            "timeout": 5000
          }
        ]
      }
    ]
  }
}
```

Currently supported event: `SessionStart` (runs when a Gemini CLI session begins).

### Valid Tool Names

Only these tool names are valid for Gemini CLI agents:

| Tool Name | Purpose |
|-----------|---------|
| `read_file` | Read a single file |
| `write_file` | Write content to a file (creates or overwrites) |
| `replace` | Replace text in a file (surgical edits) |
| `run_shell_command` | Execute a shell command |
| `grep_search` | Search file contents with patterns |
| `list_directory` | List directory contents |
| `google_web_search` | Search the web |
| `web_fetch` | Fetch a URL's content |
| `glob` | Find files matching a glob pattern |
| `read_many_files` | Read multiple files at once |

**Common invalid names to avoid:** `run_command`, `search`, `web_search`, `find_files`, `edit_file`

### Sequential Subagent Dispatch

The orchestrator dispatches one worker subagent at a time. The flow is:
1. Orchestrator constructs a prompt with feature details and project context
2. Orchestrator calls the worker agent by name using Gemini CLI's native subagent mechanism
3. Worker executes autonomously (reads context, implements, tests, commits)
4. Worker returns a structured JSON handoff in its response
5. Orchestrator parses the handoff and applies the decision tree
6. Orchestrator updates state and proceeds to the next feature

Workers do not run concurrently. Each is dispatched, executed, and fully processed before the next.

---

## 4. Complete File Tree

### Extension Directory

```
gemini-mission-control-extension/
├── gemini-extension.json               (  9 lines) Extension manifest
├── GEMINI.md                           (290 lines) Orchestrator context & identity
├── README.md                           (578 lines) User-facing documentation
├── COMPLETE-CONTEXT.md                 (this file) Comprehensive reference
│
├── agents/                             Subagent definitions
│   ├── .gitkeep                        (  0 lines) Placeholder
│   ├── mission-worker.md               (198 lines) General implementation worker
│   ├── code-quality-worker.md          (190 lines) Code quality / refactoring worker
│   ├── scrutiny-validator.md           (264 lines) Milestone scrutiny reviewer
│   └── user-testing-validator.md       (287 lines) Milestone user-testing validator
│
├── skills/                             Procedural knowledge (activated on demand)
│   ├── mission-planner/
│   │   └── SKILL.md                    (610 lines) 7-phase interactive planning
│   ├── mission-orchestrator/
│   │   └── SKILL.md                    (856 lines) Autonomous run loop
│   └── define-worker-skills/
│       └── SKILL.md                    (409 lines) Worker type design procedure
│
├── commands/                           Custom slash commands (TOML)
│   ├── .gitkeep                        (  0 lines) Placeholder
│   ├── mission-start.toml              ( 25 lines) /mission-start
│   ├── mission-plan.toml               ( 30 lines) /mission-plan
│   ├── mission-run.toml                ( 37 lines) /mission-run
│   ├── mission-status.toml             ( 41 lines) /mission-status
│   ├── mission-list.toml               ( 27 lines) /mission-list
│   ├── mission-pause.toml              ( 33 lines) /mission-pause
│   ├── mission-resume.toml             ( 36 lines) /mission-resume
│   ├── mission-export.toml             ( 33 lines) /mission-export
│   └── mission-override.toml           ( 49 lines) /mission-override
│
├── hooks/                              Lifecycle hooks
│   └── hooks.json                      ( 17 lines) SessionStart hook config
│
└── scripts/                            Shell helper scripts
    ├── .gitkeep                        (  0 lines) Placeholder
    ├── scaffold-mission.sh             ( 80 lines) Creates mission directory structure
    ├── session-context.sh              (101 lines) Finds & displays active mission on session start
    └── validate-state.sh               ( 76 lines) Validates state.json schema
```

### Runtime Mission Data

Created at `~/.gemini-mc/missions/mis_<id>/` when `/mission-start` is invoked:

```
~/.gemini-mc/missions/mis_<id>/
├── state.json                  Mission state machine
├── features.json               Feature list with DAG
├── mission.md                  Mission proposal document
├── validation-contract.md      Behavioral assertions (VAL-XXX-NNN)
├── validation-state.json       Assertion pass/fail tracker
├── progress_log.jsonl          Append-only event log (crash recovery)
├── messages.jsonl              Append-only inter-agent message log
├── AGENTS.md                   Worker guidance and boundaries
└── handoffs/                   Worker handoff reports
    └── <feature-id>.json       One file per completed feature
```

### Per-Project Infrastructure

Created at `<project-root>/.mission/` during planning (Phase 7):

```
<project>/.mission/
├── services.yaml               Commands and services manifest
├── init.sh                     Idempotent environment setup script
├── library/                    Shared knowledge base
│   ├── architecture.md         Architecture decisions
│   ├── environment.md          Environment setup details
│   └── user-testing.md         Testing surface documentation
├── skills/                     Per-mission worker skill definitions
│   └── <worker-type>/
│       └── SKILL.md            Worker-type-specific procedures
├── research/                   Research artifacts (from web searches)
└── validation/                 Validation synthesis reports
    └── <milestone>/
        ├── scrutiny/
        │   └── synthesis.json  Scrutiny validator synthesis report
        └── user-testing/
            └── synthesis.json  User-testing validator synthesis report
```

---

## 5. Setup & Installation

### Prerequisites

| Requirement | Why |
|-------------|-----|
| **Gemini CLI v0.33+** | Extension system and subagent support |
| **Subagent support enabled** | Required for dispatching worker agents |
| **jq** | Used by shell helper scripts for JSON processing |
| **Python 3** | Used by scaffold script for safe JSON generation |

### Enabling Subagents

Add to `~/.gemini/settings.json`:

```json
{
  "experimental.enableAgents": true
}
```

### Installation

```bash
# 1. Clone the repository
git clone https://github.com/your-org/gemini-mission-control-extension.git
cd gemini-mission-control-extension

# 2. Link the extension to Gemini CLI
gemini extensions link .

# 3. Verify registration
gemini extensions list
# Should show "gemini-mission-control"
```

### Verifying

```bash
# Open Gemini CLI
gemini

# Test commands are available
/mission-list
```

If `/mission-list` responds (even with "No missions found"), the extension is installed correctly.

---

## 6. Commands Reference

### `/mission-start <description>`

| Property | Value |
|----------|-------|
| **Purpose** | Create a new mission and scaffold its directory structure |
| **Required State** | None (creates a new mission) |
| **State Transition** | → `planning` |

**Example:**
```
/mission-start Build a REST API with Express, PostgreSQL, and JWT auth
```

**Behavior:**
1. Generates a unique 6-character hex mission ID via `/dev/urandom`
2. Determines the current working directory via `pwd`
3. Runs `scripts/scaffold-mission.sh <id> <working_dir>` to create the mission directory at `~/.gemini-mc/missions/mis_<id>/`
4. Initializes `state.json` with `state: "planning"`
5. Creates empty template files: `features.json`, `validation-contract.md`, `validation-state.json`, `progress_log.jsonl`, `messages.jsonl`, `AGENTS.md`, `handoffs/`

**Key prompt instructions:** If `{{args}}` is empty, asks the user to describe what they want to build before proceeding.

---

### `/mission-plan`

| Property | Value |
|----------|-------|
| **Purpose** | Activate the 7-phase interactive planning procedure |
| **Required State** | `planning` |
| **State Transition** | `planning` → `orchestrator_turn` |

**Example:**
```
/mission-plan
```

**Behavior:**
1. Finds the active mission (most recently updated)
2. Verifies state is `planning`
3. Activates the `mission-planner` skill via `activate_skill`
4. Runs through 7 phases: requirements → codebase investigation → milestones → confirmation → infrastructure → testing → artifact generation
5. Generates: `validation-contract.md`, `features.json`, `validation-state.json`, `AGENTS.md`, `.mission/` directory
6. Enforces coverage gate and DAG acyclicity
7. Transitions to `orchestrator_turn`

**Key prompt instructions:** Requires user interaction during Phases 1 and 4 (Q&A and milestone confirmation).

---

### `/mission-run`

| Property | Value |
|----------|-------|
| **Purpose** | Start the autonomous orchestrator run loop |
| **Required State** | `orchestrator_turn` |
| **State Transition** | Cycles through `orchestrator_turn` → `worker_running` → `handoff_review` → `orchestrator_turn` → ... → `completed` |

**Example:**
```
/mission-run
```

**Behavior:**
1. Finds the active mission and verifies state is `orchestrator_turn`
2. Activates the `mission-orchestrator` skill via `activate_skill`
3. Enters the 8-step run loop (see [Section 11](#11-orchestrator-run-loop))
4. Runs autonomously until all features are complete, the mission is paused, or intervention is needed

**Key prompt instructions:** Rejects non-`orchestrator_turn` states with specific error messages for each invalid state.

---

### `/mission-status`

| Property | Value |
|----------|-------|
| **Purpose** | Display the current status of a mission |
| **Required State** | Any |
| **State Transition** | None (read-only) |

**Example:**
```
/mission-status
/mission-status a3f1b2
```

**Output format:**
```
Mission ID: mis_a3f1b2
State: orchestrator_turn
Progress: 5/12 features completed
Current Milestone: backend-api
Working Directory: /Users/you/my-project
Last Updated: 2026-03-13T10:30:00Z
```

**Key prompt instructions:** Determines current milestone by finding the first `pending` feature in `features.json` and reading its `milestone` field. If no features are pending, reports "all complete".

---

### `/mission-list`

| Property | Value |
|----------|-------|
| **Purpose** | List all missions and their current states |
| **Required State** | Any |
| **State Transition** | None (read-only) |

**Example:**
```
/mission-list
```

**Output format:**
```
| Mission ID  | State            | Last Updated             |
|-------------|------------------|--------------------------|
| mis_a3f1b2  | orchestrator_turn| 2026-03-13T10:30:00Z     |
| mis_c4d5e6  | completed        | 2026-03-12T08:00:00Z     |
```

**Key prompt instructions:** Sorts by `updatedAt` (most recent first). Shows "unknown" for malformed state files.

---

### `/mission-pause`

| Property | Value |
|----------|-------|
| **Purpose** | Pause the current mission execution |
| **Required State** | `orchestrator_turn`, `worker_running`, `handoff_review` |
| **State Transition** | `<current>` → `paused` |

**Example:**
```
/mission-pause
```

**Behavior:**
1. Reads `state.json` and verifies the state is pausable
2. Updates `state` to `"paused"`, refreshes `updatedAt`
3. Appends a `state_transition` event to `progress_log.jsonl` with `reason: "user_requested"`
4. Confirms the pause to the user

**Key prompt instructions:** Rejects pause from `planning`, `paused`, `completed`, or `failed` states.

---

### `/mission-resume`

| Property | Value |
|----------|-------|
| **Purpose** | Resume a paused mission |
| **Required State** | `paused` |
| **State Transition** | `paused` → `orchestrator_turn` |

**Example:**
```
/mission-resume
```

**Behavior:**
1. Verifies state is `paused`
2. Checks `progress_log.jsonl` for budget-related pause
3. If budget-paused, informs user and requests acknowledgment
4. Transitions to `orchestrator_turn`
5. Logs `state_transition` event

**Key prompt instructions:** Budget-paused missions require explicit user acknowledgment before resuming.

---

### `/mission-export`

| Property | Value |
|----------|-------|
| **Purpose** | Export a mission as a tar.gz archive |
| **Required State** | Any |
| **State Transition** | None |

**Example:**
```
/mission-export
/mission-export a3f1b2
```

**Behavior:**
1. Finds the mission directory
2. Creates `~/mission-<missionId>-export.tar.gz` via `tar -czf`
3. Verifies the archive was created
4. Reports file path and size

---

### `/mission-override <justification>`

| Property | Value |
|----------|-------|
| **Purpose** | Override a failed validator with documented justification |
| **Required State** | Any (typically `orchestrator_turn` or `paused`) |
| **State Transition** | May seal milestones; may transition `paused` → `orchestrator_turn` |

**Example:**
```
/mission-override "Test environment lacks GPU access; ML inference tests skipped"
```

**Behavior:**
1. Requires non-empty `{{args}}` (justification)
2. Finds failed validator features (scrutiny/user-testing with `pending` status after failure)
3. Marks them as `completed`, increments `completedFeatures`
4. Records override in synthesis report with timestamp and justification
5. Seals milestone if both validators now complete
6. Logs `validation_overridden` event

**Key prompt instructions:** Override does NOT change `validation-state.json` assertion statuses. Failed assertions remain `failed`; only the validator feature status is overridden.

---

## 7. Agents Reference

### mission-worker

**YAML Frontmatter:**
```yaml
---
name: mission-worker
description: "General-purpose implementation worker. Handles feature implementation following a 3-phase procedure: startup, work (TDD), and cleanup with structured JSON handoff."
kind: local
tools:
  - read_file
  - write_file
  - replace
  - run_shell_command
  - grep_search
  - list_directory
model: gemini-2.5-pro
temperature: 0.1
max_turns: 100
timeout_mins: 30
---
```

**Purpose:** General-purpose implementation worker dispatched by the orchestrator to complete individual features.

**Procedure Summary:**

| Phase | Steps |
|-------|-------|
| **Phase 1: Startup** | 1.1 Parse feature assignment (id, description, expectedBehavior, verificationSteps, fulfills). 1.2 Read project context (`.mission/services.yaml`, `AGENTS.md`, `.mission/library/`, `.mission/skills/`). 1.3 Run `init.sh` if exists. 1.4 Run baseline validation (tests must pass before starting). |
| **Phase 2: Work (TDD)** | 2.1 Write failing tests first. 2.2 Implement feature to make tests pass. 2.3 Run full verification (test, lint, typecheck, feature-specific steps). 2.4 Iterate until all pass. **CRITICAL:** Never pipe output through `| tail` or `| head` — masks exit codes. |
| **Phase 3: Cleanup** | 3.1 `git add -A && git commit -m "feat(<id>): <description>"`. 3.2 Produce structured JSON handoff. |

**Handoff format:** See [Section 10 — Worker Handoff JSON Schema](#worker-handoff-json-schema).

---

### code-quality-worker

**YAML Frontmatter:**
```yaml
---
name: code-quality-worker
description: "Code quality and refactoring specialist. Reviews code for quality issues, performs refactoring, and produces a structured handoff with findings and changes."
kind: local
tools:
  - read_file
  - write_file
  - replace
  - run_shell_command
  - grep_search
  - list_directory
model: gemini-2.5-pro
temperature: 0.1
max_turns: 60
timeout_mins: 20
---
```

**Purpose:** Specialized agent for code review, refactoring, and quality improvement.

**Procedure Summary:**

| Phase | Steps |
|-------|-------|
| **Phase 1: Startup** | Parse assignment. Read project context. Run `init.sh`. Establish baseline (run tests + linter before making changes). |
| **Phase 2: Review & Refactor** | 2.1 Analyze code across 6 categories: correctness, maintainability, security, performance, style, testing. 2.2 Apply targeted fixes within scope. 2.3 Run verification. 2.4 Iterate. |
| **Phase 3: Cleanup** | Commit changes with `refactor(<id>):` prefix. Produce structured JSON handoff. |

**Key difference from mission-worker:** Focuses on review and quality, not feature implementation. Lower `max_turns` (60 vs 100) and `timeout_mins` (20 vs 30).

---

### scrutiny-validator

**YAML Frontmatter:**
```yaml
---
name: scrutiny-validator
description: "Milestone scrutiny validator. Runs hard-gate validation commands, reviews completed feature changes, scopes re-validation from prior synthesis reports, and writes a milestone synthesis handoff."
kind: local
tools:
  - read_file
  - run_shell_command
  - grep_search
  - list_directory
  - write_file
model: gemini-2.5-pro
temperature: 0.1
max_turns: 80
timeout_mins: 20
---
```

**Purpose:** Enforces hard validation gates (test/typecheck/lint), reviews feature implementations, produces a synthesis report.

**Procedure Summary:**

| Phase | Steps |
|-------|-------|
| **Phase 1: Load Context** | Read mission inputs (validation-contract, features, state, AGENTS.md, services.yaml). Determine milestone scope. Check for prior synthesis report to scope re-validation. |
| **Phase 2: Hard-Gate Validation** | Discover test/typecheck/lint commands from `services.yaml`. Run each. Any failure = scrutiny fails. Record command evidence. |
| **Phase 3: Feature Review** | Read handoff files for each completed feature. Identify changed files. Review for quality issues (mismatches, missing validation, edge cases, format errors). Scope re-validation intelligently from prior report. |
| **Phase 4: Synthesis Report** | Write JSON report to `.mission/validation/<milestone>/scrutiny/synthesis.json`. Status: `passed` or `failed`. |
| **Phase 5: Handoff** | Return structured JSON handoff with `blocking`/`non_blocking` severities. |

**Key detail:** Does NOT have `write_file` for code changes — only for writing the synthesis report. This is a read-heavy, review-focused agent.

---

### user-testing-validator

**YAML Frontmatter:**
```yaml
---
name: user-testing-validator
description: "Milestone user-testing validator. Tests validation-contract assertions against the configured user surface, updates validation-state.json, scopes re-testing from prior synthesis reports, and writes a milestone synthesis handoff."
kind: local
tools:
  - read_file
  - run_shell_command
  - grep_search
  - list_directory
  - write_file
  - google_web_search
model: gemini-2.5-pro
temperature: 0.1
max_turns: 80
timeout_mins: 25
---
```

**Purpose:** Tests behavioral assertions from the validation contract against the running application. Updates `validation-state.json`.

**Procedure Summary:**

| Phase | Steps |
|-------|-------|
| **Phase 1: Load Context** | Read validation-contract, validation-state, features, state, AGENTS.md, services.yaml, user-testing.md. Determine in-scope assertions from features' `fulfills` arrays. Check prior synthesis for re-testing scope. |
| **Phase 2: Environment Setup** | Read service manifest. Start required services. Wait for healthchecks. Prepare testing surface. Use `google_web_search` only if blocked by missing docs. |
| **Phase 3: Assertion Testing** | Test each in-scope assertion. Classify as `passed`/`failed`/`blocked`. Update `validation-state.json`. Collect evidence. |
| **Phase 4: Synthesis Report** | Write JSON to `.mission/validation/<milestone>/user-testing/synthesis.json`. |
| **Phase 5: Cleanup & Handoff** | Stop services started. Return structured handoff. |

**Key details:**
- Has `google_web_search` tool (unique among agents) for external documentation lookup
- Higher `timeout_mins` (25 vs 20) because it may need to start services and wait for healthchecks
- Updates `validation-state.json` with per-assertion results

---

## 8. Skills Reference

### mission-planner

| Property | Value |
|----------|-------|
| **Name** | `mission-planner` |
| **Activated by** | `/mission-plan` command |
| **When** | Mission is in `planning` state |

**Detailed Phase/Step Breakdown:**

#### Phase 1: Understand Requirements
- If the description is vague, asks clarifying questions (core problem, target users, must-haves vs nice-to-haves, tech stack, greenfield vs existing, integrations, acceptance criteria, deployment target)
- If the working directory has an existing project, investigates it using `read_file`, `grep_search`, `list_directory`
- **Output:** Written summary of project purpose, tech stack, functional requirements, non-functional requirements, constraints, and risks

#### Phase 2: Investigate Codebase
- Maps directory structure (top-level, `src/`, `tests/`)
- Reads configuration files (package.json, tsconfig.json, Dockerfile, CI configs)
- Identifies patterns (test frameworks, API routes, database schemas, env vars)
- Checks existing infrastructure (Docker, k8s, Terraform)
- **Output:** Tech stack summary, project structure, test infrastructure, services, build/run commands, coding conventions

#### Phase 3: Identify Milestones
- Decomposes into milestone-gated vertical slices (not horizontal layers)
- Each milestone: 3-8 features, dependency-ordered, independently testable
- Features: single-worker-session granularity, with preconditions forming a DAG
- **DAG acyclicity check:** Kahn's algorithm (topological sort). If cycles detected, restructures features.
- **Output:** Structured milestone/feature list with preconditions

#### Phase 4: Confirm Milestones
- Presents plan to the user for review
- Handles feedback: update plan → re-run DAG check → re-present
- **Gate:** Does NOT proceed until user explicitly confirms

#### Phase 5: Plan Infrastructure
- Identifies required services (databases, caches, message queues, dev servers)
- Assigns ports (3000-9999 range)
- Defines boundaries (off-limits directories, external systems)
- Plans `services.yaml` structure and `init.sh` script
- **Output:** Infrastructure plan with services, ports, boundaries, env vars

#### Phase 6: Plan Testing
- Identifies testing surface (unit, integration, e2e, manual)
- Determines test tooling and verification commands
- Plans user-testing assertions and evidence requirements
- Plans `user-testing.md` library entry
- **Output:** Testing strategy

#### Phase 7: Generate Artifacts
- **7.1:** Write `validation-contract.md` with `VAL-XXX-NNN` assertions
- **7.2:** Write `features.json` with full feature DAG. **Coverage gate:** Every VAL assertion must be claimed by exactly one feature's `fulfills`. No orphans, no duplicates, no phantom references.
- **7.3:** Initialize `validation-state.json` with every assertion set to `pending`
- **7.4:** Generate `AGENTS.md` with working directory, boundaries, conventions
- **7.5:** Update `mission.md` with refined requirements and plan
- **7.6:** Scaffold `.mission/` directory (services.yaml, init.sh, library/, skills/, research/)
- **7.7:** **Pre-transition coverage gate re-verification (MANDATORY)**. Then transition `state.json`: `planning` → `orchestrator_turn`, set `totalFeatures`. Log to `progress_log.jsonl`.

---

### mission-orchestrator

| Property | Value |
|----------|-------|
| **Name** | `mission-orchestrator` |
| **Activated by** | `/mission-run` command |
| **When** | Mission is in `orchestrator_turn` state (or `worker_running` for crash recovery) |

**Detailed Step Breakdown:** See [Section 11 — Orchestrator Run Loop](#11-orchestrator-run-loop) for the full 8-step procedure.

**Additional protocols managed by this skill:**
- Scope Change Protocol (add/remove/modify requirements)
- Budget Enforcement (token tracking, auto-pause)
- Research Delegation (google_web_search → .mission/research/ → .mission/library/)
- Feature Cancellation (terminal state, irreversible)
- Misc Milestones (max 5 features per misc milestone)
- Pause/Resume
- Inter-Agent Messaging Protocol
- Validation Override Protocol

---

### define-worker-skills

| Property | Value |
|----------|-------|
| **Name** | `define-worker-skills` |
| **Activated by** | During planning phase (Phase 7) when creating per-mission worker types |
| **When** | The mission needs custom worker types beyond the defaults |

**Detailed Phase/Step Breakdown:**

#### Phase 1: Analyze Effective Work Boundaries
- Examine project structure and technology domains (frontend, backend, database, infra, testing, docs)
- Map tooling landscape (build tools, linters, test runners, type checkers)
- Identify tool access requirements per domain
- Identify risk boundaries (high-risk changes → lower temperature, more turns)

#### Phase 2: Determine Worker Types
- **Design principle:** Minimize worker types (most missions need 2-3). Differentiate by tool access, not topic.
- Common templates: `mission-worker`, `code-quality-worker`, `infra-worker`, `research-worker`
- Decision checklist: handles ≥3 features, different tool set, different procedure, valid name format

#### Phase 3: Create Agent Definition Files
- Write `.md` files in `agents/` with correct YAML frontmatter
- Enforce: `kind: local`, valid tool names only, `name` matches `skillName` in features.json
- Optional fields: `model`, `temperature`, `max_turns`, `timeout_mins`

#### Phase 4: Write Procedural Body Content
- Structure: Startup → Work → Cleanup
- Startup: identity, read context, run init.sh, understand feature, explore code
- Work: type-specific procedure (implementation TDD, review/refactor, research)
- Cleanup: final verification, produce structured JSON handoff

#### Phase 5: Define Structured Handoff Requirements
- Specify exact JSON schema (salientSummary, whatWasImplemented, whatWasLeftUndone, verification, tests, discoveredIssues)
- Handoff rules: specific observations, actual exit codes, no fabrication, flag blockers

---

## 9. State Machine

### All 7 States

| State | Description |
|-------|-------------|
| `planning` | Initial state. Planner skill generates mission artifacts interactively. |
| `orchestrator_turn` | Orchestrator evaluates next action: select feature, check milestones, or complete. |
| `worker_running` | Worker subagent is actively implementing a feature. |
| `handoff_review` | Orchestrator received handoff; applying decision tree. |
| `paused` | Mission paused by user or budget exceeded. State persists on disk. |
| `completed` | All features done, all validators passed. Terminal state. |
| `failed` | Unrecoverable error. Terminal state. Requires manual intervention. |

### All Transitions with Triggers

| From | To | Trigger |
|------|----|---------|
| `planning` | `orchestrator_turn` | Planner completes Phase 7, coverage gate passes |
| `orchestrator_turn` | `worker_running` | Worker subagent dispatched for a ready feature |
| `worker_running` | `handoff_review` | Worker completes, structured handoff received |
| `handoff_review` | `orchestrator_turn` | Decision tree applied, state updated |
| `orchestrator_turn` | `completed` | All features done + all milestones sealed |
| `orchestrator_turn` | `paused` | `/mission-pause` or budget exceeded |
| `paused` | `orchestrator_turn` | `/mission-resume` (budget ack if needed) |
| `worker_running` | `orchestrator_turn` | Crash recovery resets stuck features |
| Any | `failed` | Unrecoverable error |

### ASCII State Diagram

```
                   ┌─────────────────────────────────────────────┐
                   │                                             │
                   ▼                                             │
              ┌─────────┐     coverage gate     ┌──────────────────────┐
   /start ──► │planning │ ────────────────────► │  orchestrator_turn   │◄──┐
              └─────────┘                       └──────────────────────┘   │
                                                  │       │       │        │
                                          dispatch│  pause│  done │  loop  │
                                                  ▼       ▼       ▼        │
                                          ┌───────────┐ ┌──────┐ ┌─────────┐
                                          │  worker_   │ │paused│ │completed│
                                          │  running   │ └──┬───┘ └─────────┘
                                          └─────┬─────┘    │
                                        handoff │   resume │
                                                ▼          │
                                          ┌───────────┐    │
                                          │ handoff_   │    │
                                          │ review     ├────┘
                                          └─────┬─────┘
                                       decision │
                                                │
                                                └──────────────────────────┘
                                                          (loops back)

                          Any state ──────────► ┌──────┐
                                                │failed│  (terminal)
                                                └──────┘
```

### Milestone Lifecycle

```
  Implementation Features          Validators              Sealed
  ──────────────────────        ─────────────────      ─────────────
  [feature-a: pending]                                      
  [feature-b: pending]                                      
       ↓ (dispatch workers)                                 
  [feature-a: completed]                                    
  [feature-b: completed]                                    
       ↓ (all impl done)                                    
                            [scrutiny-val: pending]          
                            [user-test-val: pending]         
                                 ↓ (dispatch scrutiny)       
                            [scrutiny-val: completed]        
                                 ↓ (dispatch user-test)      
                            [user-test-val: completed]       
                                                        milestone → sealedMilestones
                                                        (no more features allowed)
```

---

## 10. State File Schemas

### state.json

```json
{
  "missionId": "mis_abc123",
  "state": "planning",
  "workingDirectory": "/absolute/path/to/project",
  "completedFeatures": 0,
  "totalFeatures": 0,
  "createdAt": "2026-01-01T00:00:00Z",
  "updatedAt": "2026-01-01T00:00:00Z",
  "sealedMilestones": [],
  "milestonesWithValidationPlanned": []
}
```

| Field | Type | Description |
|-------|------|-------------|
| `missionId` | string | Unique identifier with `mis_` prefix + 6 hex chars |
| `state` | string | One of: `planning`, `orchestrator_turn`, `worker_running`, `handoff_review`, `paused`, `completed`, `failed` |
| `workingDirectory` | string | Absolute path to the project root |
| `completedFeatures` | integer | Count of completed features (≥ 0) |
| `totalFeatures` | integer | Total number of features (≥ 0) |
| `createdAt` | string | ISO 8601 timestamp of mission creation |
| `updatedAt` | string | ISO 8601 timestamp of last state update |
| `sealedMilestones` | array[string] | Milestones where validation passed; no new features allowed |
| `milestonesWithValidationPlanned` | array[string] | Milestones where validator features have been injected |

---

### features.json

```json
{
  "features": [
    {
      "id": "unique-feature-id",
      "description": "What this feature implements",
      "skillName": "mission-worker",
      "milestone": "milestone-name",
      "preconditions": ["other-feature-id"],
      "expectedBehavior": ["Feature does X", "Feature handles Y"],
      "verificationSteps": ["run test command", "check output"],
      "fulfills": ["VAL-XXX-001"],
      "status": "pending"
    }
  ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique identifier (lowercase, hyphens). No duplicates. |
| `description` | string | Non-empty description of the implementation work |
| `skillName` | string | Maps to agent name: `mission-worker`, `code-quality-worker`, `scrutiny-validator`, `user-testing-validator` |
| `milestone` | string | Which milestone this feature belongs to |
| `preconditions` | array[string] | Feature IDs that must complete first (forms DAG) |
| `expectedBehavior` | array[string] | Concrete, verifiable behavior statements |
| `verificationSteps` | array[string] | Commands/checks proving the feature works |
| `fulfills` | array[string] | `VAL-XXX-NNN` assertion IDs this feature satisfies |
| `status` | string | One of: `pending`, `completed`, `cancelled` |

---

### validation-contract.md Format

```markdown
# Validation Contract

## Area: Authentication

### VAL-AUTH-001: User registration creates account
When a POST request is sent to `/api/auth/register` with valid `email` and `password` fields,
the response status is 201, the response body contains a `userId` field, and a corresponding
user record exists in the database.
Evidence: `curl -X POST http://localhost:3000/api/auth/register ...` returns 201

### VAL-AUTH-002: Login returns JWT token
When a POST request is sent to `/api/auth/login` with valid credentials, the response
contains an `accessToken` field that is a valid JWT.
Evidence: `curl -X POST http://localhost:3000/api/auth/login ...` returns JSON with accessToken
```

Each assertion has:
- **ID** in `VAL-[A-Z]{2,6}-[0-9]{3}` format as the heading
- **Title** after the colon
- **Behavioral description** as the body
- **Evidence requirement** specifying how to prove it

---

### validation-state.json

```json
{
  "assertions": {
    "VAL-AUTH-001": { "status": "pending" },
    "VAL-AUTH-002": { "status": "passed", "evidence": ["curl returned 201"] },
    "VAL-DB-001": { "status": "failed", "evidence": ["table missing"] },
    "VAL-API-001": { "status": "blocked", "evidence": ["service unavailable"] }
  }
}
```

| Status | Set By | Meaning |
|--------|--------|---------|
| `pending` | Planner (initial) | Not yet tested |
| `passed` | User-testing validator | Assertion verified successfully |
| `failed` | User-testing validator | Assertion tested, did not satisfy contract |
| `blocked` | User-testing validator | Could not be tested (environment/dependency issue) |

---

### progress_log.jsonl Events

Each line is a JSON object. Event types:

| Event | When Logged | Key Fields |
|-------|-------------|------------|
| `state_transition` | Any state change | `from`, `to`, `reason` |
| `worker_started` | Worker dispatched | `featureId`, `agentName`, `skillName` |
| `worker_completed` | Worker handoff received | `featureId`, `salientSummary` |
| `milestone_completed` | All impl features in milestone done | `milestone` |
| `validation_injected` | Validator features added | `milestone`, `features` |
| `milestone_sealed` | Both validators passed | `milestone` |
| `crash_recovery` | Stuck features reset | `resetFeatures`, `previousState` |
| `feature_retry` | Feature reset to pending | `featureId`, `reason` |
| `feature_partial` | Feature partially completed | `featureId`, `implemented`, `remaining` |
| `feature_escalation` | Feature retried 3+ times | `featureId`, `retries` |
| `deadlock_detected` | Pending features with unmet preconditions | `pendingFeatures` |
| `scope_change` | Requirements modified | `action`, `assertionId`, `featureId` |
| `budget_pause` | Token limit exceeded | `tokensUsed`, `budget` |
| `research_completed` | Research saved | `topic`, `savedTo` |
| `feature_cancelled` | Feature cancelled | `featureId`, `reason` |
| `validation_overridden` | Validator override applied | `milestone`, `justification`, `features` |
| `sealed_milestone_rejected` | Attempted add to sealed milestone | `milestone`, `featureId`, `redirectedTo` |

Example entry:
```json
{"timestamp": "2026-01-15T10:30:00Z", "event": "worker_started", "featureId": "user-auth", "agentName": "mission-worker", "skillName": "mission-worker"}
```

---

### messages.jsonl Format

Each line is a JSON object for inter-agent communication:

```json
{
  "timestamp": "2026-01-15T10:30:00Z",
  "sender": "orchestrator",
  "type": "feature_completed",
  "content": "User authentication feature implemented with JWT token generation and bcrypt password hashing."
}
```

| Field | Values |
|-------|--------|
| `sender` | `orchestrator`, `mission-worker`, `scrutiny-validator`, `user-testing-validator` |
| `type` | `feature_completed`, `worker_dispatched`, `validation_result`, `scope_change`, `research_available`, `user_instruction`, `error_report` |

---

### Worker Handoff JSON Schema

Every worker and validator must produce this as their final output:

```json
{
  "salientSummary": "1-4 sentence summary of what happened in this session. Be specific.",
  "whatWasImplemented": "Concrete description of what was built. Min 50 chars. Reference files/functions.",
  "whatWasLeftUndone": "Anything incomplete. Empty string if fully done.",
  "verification": {
    "commandsRun": [
      {
        "command": "npm test",
        "exitCode": 0,
        "observation": "All 42 tests passed in 3.2s with 0 failures"
      }
    ],
    "interactiveChecks": [
      {
        "action": "Navigated to /login page",
        "observed": "Login form rendered with email and password fields"
      }
    ]
  },
  "tests": {
    "added": [
      {
        "file": "tests/auth.test.ts",
        "cases": [
          {
            "name": "should register new user",
            "verifies": "POST /api/auth/register returns 201"
          }
        ]
      }
    ],
    "coverage": "Unit tests for user registration covering success, validation errors, and duplicate email"
  },
  "discoveredIssues": [
    {
      "severity": "high",
      "description": "Database connection timeout under load",
      "suggestedFix": "Increase pool size in db.config.ts"
    }
  ]
}
```

| Field | Required | Rules |
|-------|----------|-------|
| `salientSummary` | Yes | 1-4 sentences. Specific, not vague. |
| `whatWasImplemented` | Yes | ≥ 50 chars. Reference specific files/functions. |
| `whatWasLeftUndone` | Yes | Empty string if complete. |
| `verification.commandsRun` | Yes | ≥ 1 entry. Real exit codes, specific observations. |
| `verification.interactiveChecks` | No | For UI/browser work. |
| `tests.added` | Yes | Array (may be empty). File paths and case names. |
| `tests.coverage` | Yes | Summary string. |
| `discoveredIssues` | Yes | Array (may be empty). Severity: `high`, `medium`, `low`. |

Validators use `blocking` and `non_blocking` severities instead of `high`/`medium`/`low`.

---

## 11. Orchestrator Run Loop

The run loop is defined in the `mission-orchestrator` SKILL.md and consists of 8 steps executed in a cycle.

### Step 1: Read State & Crash Recovery

1. Read `state.json`, `features.json`, `progress_log.jsonl`, `AGENTS.md`, `validation-contract.md`
2. **Crash recovery:** If state is `worker_running`, find stuck features (unmatched `worker_started` events in progress_log), reset them to `pending`, transition to `orchestrator_turn`, log `crash_recovery` event
3. **Empty features check:** If `features` array is empty, transition to `completed` and exit
4. **All-cancelled check:** If every feature is `cancelled`, transition to `completed` and exit

### Step 2: Evaluate Feature DAG

1. Build dependency graph from `preconditions` arrays
2. Find features where: `status == "pending"` AND all preconditions have `status == "completed"`
3. Select the first ready feature in array order (array position = priority)
4. **No ready features:** If pending features exist but none are ready → deadlock. Log `deadlock_detected`, transition to `paused`, request user intervention.

### Step 3: Construct Worker Prompt

1. Include feature context: `id`, `description`, `expectedBehavior`, `verificationSteps`, `fulfills`
2. Include project enrichment: `.mission/services.yaml`, `.mission/library/*.md`, `.mission/skills/<skillName>/SKILL.md`, `AGENTS.md`
3. Include validation contract assertions referenced by `fulfills`
4. Map `skillName` to agent name (same name, direct mapping)
5. For the first worker in a session, include `init.sh` execution instruction

### Step 4: Dispatch Worker Subagent

1. State transition: `orchestrator_turn` → `worker_running`
2. Log `worker_started` event
3. Call the worker agent via Gemini CLI's native subagent dispatch
4. Wait for completion

### Step 5: Parse Structured Handoff

1. Extract JSON handoff from worker response
2. Validate required fields (salientSummary, whatWasImplemented ≥ 50 chars, commandsRun non-empty)
3. Write handoff to `handoffs/<feature-id>.json`
4. State transition: `worker_running` → `handoff_review`
5. Log `worker_completed` event

### Step 6: Apply Decision Tree (A/B/C/D)

| Option | Trigger | Action |
|--------|---------|--------|
| **A** | `discoveredIssues` contains `severity: "high"` | Create follow-up feature (in same milestone unless sealed → `misc-*`). Mark original as `completed`. |
| **B** | Explicit failure (non-empty `whatWasLeftUndone` + failing exit codes, or malformed handoff) | Reset to `pending` with `[RETRY]` context in description. Max 3 retries → escalation → `paused`. |
| **C** | Partial success (non-empty `whatWasLeftUndone` but some passing) | Update description with `[PARTIAL]` remaining work. Keep `pending`. |
| **D** | Medium/low issues only, worker success | Mark `completed`. Create misc features in `misc-*` milestone (max 5 per misc). |
| **Clean** | No issues, everything passed | Mark `completed`. No new features. |

### Step 7: Update State & Log Events

1. Write updated `features.json`
2. Update `state.json`: state → `orchestrator_turn`, increment counters, update `updatedAt`
3. Log `state_transition` event with decision option
4. Write inter-agent message to `messages.jsonl`

### Step 8: Check Milestone Completion & Inject Validators

1. Check if all implementation features in the completed feature's milestone are done
2. If yes AND milestone not in `milestonesWithValidationPlanned`:
   - Skip if all impl features are cancelled (no validation needed)
   - Create `scrutiny-validator-<milestone>` feature
   - Create `user-testing-validator-<milestone>` feature (depends on scrutiny)
   - Add milestone to `milestonesWithValidationPlanned`
   - Log `milestone_completed` and `validation_injected` events
3. After user-testing validator completes successfully: add milestone to `sealedMilestones`, log `milestone_sealed`
4. Check mission completion: all features done + all milestones sealed → `completed` state, exit loop
5. Otherwise: loop back to Step 1

---

## 12. Planning Procedure

The planning procedure (defined in `mission-planner` SKILL.md) has 7 phases:

### Phase 1: Understand Requirements

- If description is vague, asks clarifying questions (must be able to write ≥ 3 behavioral assertions)
- If existing project, investigates with `read_file`, `grep_search`, `list_directory`
- **Output:** Project purpose, tech stack, functional/non-functional requirements, constraints, risks

### Phase 2: Investigate Codebase

- Map directory structure, read config files, identify patterns (test frameworks, API routes, DB schemas)
- Check existing infrastructure (Docker, CI/CD)
- **Output:** Tech stack, project structure, test infra, services, build/run commands, conventions

### Phase 3: Identify Milestones

- Decompose into vertical slices (3-8 features per milestone)
- Features: single-worker-session granularity, with preconditions
- **DAG acyclicity check (Kahn's algorithm):** Compute in-degrees, process zero-in-degree features, verify all features processed. If cycle detected → restructure.
- **Output:** Milestone/feature list with preconditions

### Phase 4: Confirm Milestones

- Present plan to user with milestones, features, assertions preview
- Handle feedback: update → re-check DAG → re-present
- **Gate:** User must explicitly confirm before proceeding

### Phase 5: Plan Infrastructure

- Identify services, assign ports (3000-9999), define boundaries
- Plan `services.yaml` and `init.sh`
- **Output:** Infrastructure plan

### Phase 6: Plan Testing

- Identify testing surface (unit, integration, e2e, manual)
- Determine tooling, verification commands, assertion strategy
- Plan `user-testing.md`
- **Output:** Testing strategy

### Phase 7: Generate Artifacts

Seven sub-steps:
1. Write `validation-contract.md`
2. Write `features.json` with **coverage gate** (every VAL assertion claimed by exactly one feature)
3. Initialize `validation-state.json` (all assertions `pending`)
4. Generate `AGENTS.md`
5. Update `mission.md`
6. Scaffold `.mission/` directory
7. **Mandatory pre-transition coverage gate re-verification**, then state transition `planning` → `orchestrator_turn`

---

## 13. Validation Pipeline

### Scrutiny Validator

**When triggered:** All implementation features in a milestone are `completed`.

**Procedure:**
1. Load context: validation-contract, features, state, AGENTS.md, services.yaml
2. **Hard-gate commands:** Run `test`, `typecheck`, `lint` from `services.yaml`. Any failure = scrutiny fails. Missing commands = validation failure.
3. Read handoff files for each completed feature, review changed files
4. Check prior synthesis report — if exists, only re-validate previously failed items (plus always re-run hard-gate commands)
5. Write synthesis report to `.mission/validation/<milestone>/scrutiny/synthesis.json`

**Synthesis report format:**
```json
{
  "milestone": "<name>",
  "validator": "scrutiny",
  "status": "passed|failed",
  "hardGate": {
    "passed": true,
    "commands": [
      {"name": "test", "command": "...", "exitCode": 0, "observation": "..."}
    ]
  },
  "reviewScope": {
    "mode": "full|partial",
    "revalidatedFailuresOnly": false,
    "completedFeaturesReviewed": ["feature-a"]
  },
  "findings": [
    {"severity": "blocking", "featureId": "...", "summary": "...", "evidence": ["..."]}
  ],
  "summary": "...",
  "nextAction": "pass|fail"
}
```

### User-Testing Validator

**When triggered:** Scrutiny validator completes successfully (user-testing depends on scrutiny).

**Procedure:**
1. Determine in-scope assertions from features' `fulfills` arrays
2. Check prior synthesis — only re-test failed/blocked assertions
3. Start required services from `services.yaml`
4. Test each assertion, classify as `passed`/`failed`/`blocked`
5. Update `validation-state.json`
6. Write synthesis report to `.mission/validation/<milestone>/user-testing/synthesis.json`
7. Stop services

**Synthesis report format:**
```json
{
  "milestone": "<name>",
  "validator": "user-testing",
  "status": "passed|failed|blocked",
  "scope": {
    "assertionIds": ["VAL-XXX-001"],
    "retestedFailuresOnly": false
  },
  "results": [
    {"assertionId": "VAL-XXX-001", "status": "passed", "evidence": ["..."], "notes": "..."}
  ],
  "summary": "...",
  "nextAction": "pass|fail"
}
```

### Sealed Milestones

When **both** validators pass for a milestone:
1. Milestone added to `sealedMilestones` in `state.json`
2. `milestone_sealed` event logged
3. `validation_result` message written to `messages.jsonl`
4. No new features can be added to the milestone from this point forward

### Override

When validation fails and the user invokes `/mission-override "<justification>"`:
1. Failed validator features marked as `completed`
2. Override recorded in synthesis report (`overridden: true`, `justification`, `overriddenAt`)
3. Milestone sealed (override counts as "validators passed")
4. `validation_overridden` event logged
5. Override does NOT change `validation-state.json` — failed assertions remain `failed`

### Re-Validation Scoping

Both validators support intelligent re-validation:
- If a prior synthesis report exists, only re-validate items that previously failed
- Scrutiny always re-runs hard-gate commands regardless
- User-testing leaves already-passed assertions untouched
- `reviewScope.revalidatedFailuresOnly` / `scope.retestedFailuresOnly` set to `true` in reports

---

## 14. Droid vs This Extension

| Aspect | Factory Droid | Gemini Mission Control Extension |
|--------|---------------|----------------------------------|
| **Orchestrator** | Deterministic TypeScript runtime | LLM following procedural SKILL.md instructions |
| **Dispatch mechanism** | TypeScript code calls LLM APIs | Gemini CLI native subagent tool calls |
| **State management** | TypeScript code reads/writes JSON | LLM uses `read_file`/`write_file`/`replace` tools |
| **Build step** | TypeScript compilation required | None — pure declarative files (md/toml/json/sh) |
| **Validation contracts** | `VAL-XXX-NNN` format | Same `VAL-XXX-NNN` format |
| **Decision tree** | Code-enforced A/B/C/D logic | LLM follows documented A/B/C/D procedure |
| **Milestone lifecycle** | Code-enforced sealing | LLM checks `sealedMilestones` array per instructions |
| **DAG evaluation** | Algorithmic topological sort | LLM evaluates preconditions per procedure |
| **Coverage gate** | Code-enforced before planning completes | LLM runs manual check per procedure |
| **Crash recovery** | Built into runtime | LLM checks progress_log.jsonl per Step 1 |
| **Installation** | npm/yarn install + build | `gemini extensions link .` — no build |
| **Worker agents** | LLM workers called via API | LLM workers called via Gemini CLI subagent dispatch |
| **Concurrency** | Can dispatch multiple workers | Sequential dispatch only (one at a time) |
| **Determinism** | Orchestrator logic is deterministic | Orchestrator behavior is probabilistic (LLM-driven) |
| **Limitations** | Requires TypeScript build chain | Depends on LLM reliably following procedures; no runtime enforcement of state machine rules |

---

## 15. Scripts Reference

### scaffold-mission.sh

| Property | Value |
|----------|-------|
| **Location** | `scripts/scaffold-mission.sh` |
| **Usage** | `scaffold-mission.sh <mission_id> <working_directory>` |
| **Called by** | `/mission-start` command |

**Arguments:**
- `$1` — Mission ID (6-char hex, without `mis_` prefix)
- `$2` — Absolute path to the working directory

**Behavior:**
1. Creates mission directory at `~/.gemini-mc/missions/mis_<id>/`
2. Creates `handoffs/` subdirectory
3. Generates `state.json` using Python 3 for safe JSON escaping:
   - `missionId`: `"mis_<id>"`
   - `state`: `"planning"`
   - `workingDirectory`: absolute path
   - `completedFeatures`: 0
   - `totalFeatures`: 0
   - `createdAt`/`updatedAt`: current UTC ISO 8601
   - `sealedMilestones`: `[]`
   - `milestonesWithValidationPlanned`: `[]`
4. Creates empty templates: `features.json`, `mission.md`, `validation-contract.md`, `validation-state.json`
5. Creates empty logs: `progress_log.jsonl`, `messages.jsonl`
6. Creates empty `AGENTS.md` template

**Output:** `"Mission mis_<id> scaffolded at <path>"`

---

### session-context.sh

| Property | Value |
|----------|-------|
| **Location** | `scripts/session-context.sh` |
| **Usage** | Called automatically by SessionStart hook |
| **Called by** | `hooks/hooks.json` → SessionStart |

**Arguments:** None

**Behavior:**
1. Exits silently if `~/.gemini-mc/missions/` doesn't exist
2. Iterates over all `mis_*/` directories
3. Reads each `state.json`, skips `completed` and `failed` missions
4. Compares file modification times to find the most recently updated active mission
5. Outputs mission context block:
   ```
   === Active Mission Context (reloaded from disk) ===
   Mission ID: mis_abc123
   State: orchestrator_turn
   Progress: 5/12 features completed
   Working directory: /path/to/project
   Mission directory: ~/.gemini-mc/missions/mis_abc123/
   Next action: Run /mission-run to continue execution
   === End Mission Context ===
   ```
6. Suggests next action based on current state:
   - `planning` → `/mission-plan`
   - `orchestrator_turn` → `/mission-run`
   - `paused` → `/mission-resume`
   - `worker_running`/`handoff_review` → `/mission-run` (for recovery)

**Output:** Printed to stdout, consumed by Gemini CLI session context.

---

### validate-state.sh

| Property | Value |
|----------|-------|
| **Location** | `scripts/validate-state.sh` |
| **Usage** | `validate-state.sh <path-to-state.json>` or `validate-state.sh <mission_id>` |
| **Called by** | Manual invocation or debugging |

**Arguments:**
- `$1` — Either a file path to `state.json` or a mission ID (6-char hex without `mis_` prefix)
- If no slashes in argument, looks in `~/.gemini-mc/missions/mis_<id>/state.json`

**Behavior:**
1. Checks file exists and is valid JSON
2. Validates all required fields using `jq`:
   - `missionId` — must be string
   - `state` — must be one of the 7 valid states
   - `workingDirectory` — must be string
   - `completedFeatures` — must be non-negative number
   - `totalFeatures` — must be non-negative number
   - `createdAt` — must be ISO 8601 timestamp string
   - `updatedAt` — must be ISO 8601 timestamp string
   - `sealedMilestones` — must be array
   - `milestonesWithValidationPlanned` — must be array
3. Reports each validation failure with specific error message

**Output:**
- Success: `"VALID: <path> passes schema validation"` (exit 0)
- Failure: `"VALIDATION FAILED: N error(s) in <path>"` with individual errors to stderr (exit 1)

---

## 16. Hooks Reference

### hooks.json Format

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "*",
        "hooks": [
          {
            "name": "load-active-mission-context",
            "type": "command",
            "command": "scripts/session-context.sh",
            "timeout": 5000
          }
        ]
      }
    ]
  }
}
```

| Field | Description |
|-------|-------------|
| `hooks` | Top-level object containing hook event types |
| `SessionStart` | Array of matcher groups triggered when a Gemini CLI session starts |
| `matcher` | Glob pattern for when to run the hook (`"*"` = always) |
| `hooks[].name` | Human-readable hook identifier |
| `hooks[].type` | Hook type (`"command"` = run a shell command) |
| `hooks[].command` | Path to the script to execute (relative to extension root) |
| `hooks[].timeout` | Maximum execution time in milliseconds |

### SessionStart Behavior

The `load-active-mission-context` hook runs `scripts/session-context.sh` every time a Gemini CLI session begins. This ensures:

1. **Cross-session persistence** — If a mission was in progress when the user closed Gemini CLI, the mission's context is automatically reloaded when they reopen it
2. **Immediate awareness** — The LLM knows about the active mission from the start of the session without the user needing to run `/mission-status`
3. **Action guidance** — The script suggests the next appropriate command based on the mission's current state

### Cross-Session Persistence

The combination of:
- **Disk-persisted state** (all state written immediately via `write_file`)
- **SessionStart hook** (reloads context on session start)
- **Crash recovery** (handles interrupted `worker_running` state)

...ensures that missions are fully resumable across Gemini CLI session restarts, machine reboots, and unexpected interruptions. No in-memory-only state exists.
