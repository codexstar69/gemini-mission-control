# Gemini Mission Control

A Gemini CLI extension that brings autonomous multi-agent mission orchestration to the Gemini CLI. Plan complex software projects, dispatch worker subagents, validate milestones against behavioral contracts, and deliver completed work — all from within a single `gemini` session.

Gemini Mission Control replicates the orchestrator-worker-validator pattern (inspired by [Factory Droids](https://www.factory.ai/)) entirely within Gemini CLI's native architecture. There is no TypeScript, no build step, and no compiled code. The extension consists entirely of markdown agents, TOML commands, JSON configuration, and shell scripts.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Commands](#commands)
- [Architecture](#architecture)
- [File Formats](#file-formats)
- [State Management](#state-management)
- [How It Works](#how-it-works)
- [License](#license)

## Prerequisites

- **Gemini CLI v0.33+** — Install or update via [Gemini CLI docs](https://github.com/google-gemini/gemini-cli)
- **Subagent support enabled** — Add the following to `~/.gemini/settings.json`:
  ```json
  {
    "experimental.enableAgents": true
  }
  ```
- **jq** — Required by shell helper scripts for JSON processing
- **Python 3** — Used by the scaffold script for safe JSON generation

## Installation

1. **Clone the repository:**

   ```bash
   git clone https://github.com/your-org/gemini-mission-control-extension.git
   cd gemini-mission-control-extension
   ```

2. **Link the extension to Gemini CLI:**

   ```bash
   gemini extensions link .
   ```

3. **Verify the extension is registered:**

   ```bash
   gemini extensions list
   ```

   You should see `gemini-mission-control` in the output.

4. **Start Gemini CLI and test:**

   ```bash
   gemini
   ```

   Type `/mission-list` to confirm the commands are available.

## Quick Start

### Option A: Fully Autonomous (one command)

```bash
# Open Gemini CLI
gemini

# Create, plan, and run — all in one go
/mission-auto Build a REST API with user authentication and CRUD endpoints
```

That's it. The system scaffolds the mission, plans headlessly (no questions asked), and enters the autonomous orchestrator loop.

### Option B: Interactive (step-by-step control)

```bash
# Open Gemini CLI
gemini

# 1. Create a new mission
/mission-start Build a REST API with user authentication and CRUD endpoints

# 2. Plan the mission interactively (7-phase planning procedure)
/mission-plan

# 3. Run the autonomous orchestrator loop
/mission-run

# 4. Check progress at any time
/mission-status
```

The interactive flow lets you shape the plan — answer questions, confirm milestones, adjust scope — before autonomous execution begins.

## Commands

Gemini Mission Control provides 10 slash commands for managing the full mission lifecycle:

### `/mission-auto <description>`

Create, plan, and run a mission autonomously — all in one command. No questions asked.

```
/mission-auto Build a REST API with Express, PostgreSQL, and JWT auth
```

**What it does:**
1. Generates a mission ID and scaffolds the mission directory
2. Activates the mission planner in **headless mode** — investigates the codebase, identifies milestones, generates all artifacts, enforces quality gates — without asking any questions
3. Transitions to `orchestrator_turn` and immediately enters the autonomous run loop
4. Dispatches workers, validates milestones, and loops until the mission completes

**When to use it:** You have a clear project description and want the system to just go. The planner makes reasonable decisions based on the description and codebase — choosing simpler interpretations when ambiguous.

**When to use `/mission-start` + `/mission-plan` + `/mission-run` instead:** You want to review the plan, adjust milestones, or provide detailed requirements interactively before execution begins.

---

### `/mission-start <description>`

Create a new mission and scaffold its directory structure.

```
/mission-start Build a REST API with Express, PostgreSQL, and JWT auth
```

**What it does:**
- Generates a unique mission ID (e.g., `mis_a3f1b2`)
- Creates the mission directory at `~/.gemini-mc/missions/mis_<id>/`
- Initializes `state.json` with `state: "planning"`
- Scaffolds all required state files (`features.json`, `validation-contract.md`, `validation-state.json`, `progress_log.jsonl`, `messages.jsonl`, `AGENTS.md`, `handoffs/`)

**Output example:**
```
Mission mis_a3f1b2 created.
State: planning
Next step: Run /mission-plan to begin interactive planning.
```

---

### `/mission-plan`

Activate the interactive 7-phase planning procedure for the current mission.

```
/mission-plan
```

**What it does:**
1. **Understand requirements** — Interactive Q&A to clarify the project scope
2. **Investigate codebase** — Scans the working directory using file tools
3. **Identify milestones** — Breaks work into vertical slices
4. **Confirm milestones** — Reviews the plan with you interactively
5. **Plan infrastructure** — Defines boundaries, services, and environment setup
6. **Plan testing strategy** — Determines verification approaches
7. **Generate artifacts** — Creates `validation-contract.md` (with `VAL-XXX-NNN` assertions), `features.json` (feature DAG with preconditions), `validation-state.json`, `AGENTS.md`, and the `.mission/` project directory

Transitions the mission from `planning` to `orchestrator_turn` when complete.

---

### `/mission-run`

Start the autonomous orchestrator run loop.

```
/mission-run
```

**What it does:**
- Reads mission state and performs crash recovery if needed
- Evaluates the feature DAG to find the next ready feature
- Constructs an enriched prompt with project context, services, library knowledge, and skills
- Dispatches a worker subagent to implement the feature
- Parses the worker's structured JSON handoff
- Applies the decision tree (Options A/B/C/D) based on the outcome
- Updates state, logs progress, and checks for milestone completion
- Auto-injects scrutiny and user-testing validators at milestone boundaries
- Loops until all features are complete or intervention is needed

**Requires:** Mission must be in `orchestrator_turn` state.

---

### `/mission-status`

Display the current status of a mission.

```
/mission-status
/mission-status a3f1b2
```

**Output example:**
```
Mission ID: mis_a3f1b2
State: orchestrator_turn
Progress: 5/12 features completed
Current Milestone: backend-api
Working Directory: /Users/you/my-project
Last Updated: 2026-03-13T10:30:00Z
```

---

### `/mission-list`

List all missions and their current states.

```
/mission-list
```

**Output example:**
```
| Mission ID  | State            | Last Updated             |
|-------------|------------------|--------------------------|
| mis_a3f1b2  | orchestrator_turn| 2026-03-13T10:30:00Z     |
| mis_c4d5e6  | completed        | 2026-03-12T08:00:00Z     |
| mis_f7a8b9  | planning         | 2026-03-11T14:15:00Z     |
```

---

### `/mission-pause`

Pause the current mission execution.

```
/mission-pause
```

**What it does:**
- Transitions the mission state to `paused`
- Saves all in-progress work to disk
- Logs the pause event to `progress_log.jsonl`
- The mission can be resumed later with `/mission-resume`

**Works from states:** `orchestrator_turn`, `worker_running`, `handoff_review`

---

### `/mission-resume`

Resume a paused mission.

```
/mission-resume
```

**What it does:**
- Transitions the mission from `paused` back to `orchestrator_turn`
- If the mission was paused due to budget limits, asks for acknowledgment before resuming
- Logs the resume event to `progress_log.jsonl`
- After resuming, run `/mission-run` to re-enter the orchestrator loop

---

### `/mission-export`

Export a mission as a tar.gz archive.

```
/mission-export
/mission-export a3f1b2
```

**What it does:**
- Creates a compressed archive at `~/mission-<missionId>-export.tar.gz`
- Includes all state files, handoffs, artifacts, and progress logs
- Useful for backup, sharing, or moving missions between machines

**Output example:**
```
Mission ID: mis_a3f1b2
Archive: ~/mission-mis_a3f1b2-export.tar.gz
Size: 45K
```

---

### `/mission-override <justification>`

Override a failed validation with documented justification.

```
/mission-override "Test environment lacks GPU access; ML inference tests skipped"
```

**What it does:**
- Finds failed validator features (scrutiny or user-testing validators)
- Marks them as completed with the provided justification
- Records the override in the validation synthesis report
- Seals the milestone if both validators are now complete
- Logs the override event to `progress_log.jsonl`

**Requires:** A non-empty justification string.

## Architecture

### Extension Structure

```
gemini-mission-control-extension/
├── gemini-extension.json          # Extension manifest
├── GEMINI.md                      # Orchestrator context & identity
├── README.md                      # This file
│
├── agents/                        # Subagent definitions
│   ├── mission-worker.md          # General implementation worker
│   ├── code-quality-worker.md     # Code quality / refactoring worker
│   ├── scrutiny-validator.md      # Milestone scrutiny reviewer
│   └── user-testing-validator.md  # Milestone user-testing validator
│
├── skills/                        # Procedural knowledge (activated on demand)
│   ├── mission-planner/
│   │   └── SKILL.md               # 7-phase interactive planning
│   ├── mission-orchestrator/
│   │   └── SKILL.md               # Autonomous run loop
│   └── define-worker-skills/
│       └── SKILL.md               # Worker type design procedure
│
├── commands/                      # Custom slash commands (TOML)
│   ├── mission-auto.toml          # /mission-auto (one-command autonomous flow)
│   ├── mission-start.toml         # /mission-start
│   ├── mission-plan.toml          # /mission-plan
│   ├── mission-run.toml           # /mission-run
│   ├── mission-status.toml        # /mission-status
│   ├── mission-list.toml          # /mission-list
│   ├── mission-pause.toml         # /mission-pause
│   ├── mission-resume.toml        # /mission-resume
│   ├── mission-export.toml        # /mission-export
│   └── mission-override.toml      # /mission-override
│
├── hooks/                         # Lifecycle hooks
│   └── hooks.json                 # Session start: loads active mission context
│
└── scripts/                       # Shell helper scripts
    ├── scaffold-mission.sh        # Creates mission directory structure
    ├── session-context.sh         # Finds & displays active mission on session start
    └── validate-state.sh          # Validates JSON state file schemas
```

### Subagent Dispatch

The orchestrator dispatches worker subagents using Gemini CLI's native subagent tool calls. Each agent is a markdown file with YAML frontmatter defining its tools, model, temperature, turn limits, and timeout. The agent's body contains its procedural instructions.

```
┌──────────────────────────────────────────────────────────────┐
│  Gemini CLI Session                                          │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Orchestrator (GEMINI.md + mission-orchestrator skill) │  │
│  │                                                        │  │
│  │  1. Read state.json + features.json                    │  │
│  │  2. Evaluate feature DAG → select ready feature        │  │
│  │  3. Construct enriched worker prompt                   │  │
│  │  4. Dispatch worker subagent ─────────────┐            │  │
│  │  5. Receive structured JSON handoff ◄─────┤            │  │
│  │  6. Apply decision tree (A/B/C/D)         │            │  │
│  │  7. Update state + log progress           │            │  │
│  │  8. Check milestone → inject validators   │            │  │
│  │  9. Loop back to step 1                   │            │  │
│  └───────────────────────────────────────────┘            │  │
│                                                │            │  │
│                    ┌───────────────────────────┘            │  │
│                    ▼                                        │  │
│  ┌────────────────────────────────────┐                    │  │
│  │  Worker Subagent (agents/*.md)     │                    │  │
│  │                                    │                    │  │
│  │  • Reads project context           │                    │  │
│  │  • Runs init.sh if exists          │                    │  │
│  │  • Implements feature (TDD)        │                    │  │
│  │  • Returns JSON handoff            │────────────────────┘  │
│  └────────────────────────────────────┘                       │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### State Management

All mission state is persisted to disk using Gemini CLI's native file tools (`read_file`, `write_file`, `replace`). There is no in-memory-only state — every change is immediately written to JSON files in the mission directory.

**Mission directory** (`~/.gemini-mc/missions/mis_<id>/`):

| File | Purpose |
|------|---------|
| `state.json` | State machine: current state, counters, sealed milestones |
| `features.json` | Feature list with DAG ordering, preconditions, and status |
| `mission.md` | Mission proposal document |
| `validation-contract.md` | Behavioral assertions (`VAL-XXX-NNN` format) |
| `validation-state.json` | Per-assertion pass/fail/blocked tracking |
| `progress_log.jsonl` | Append-only event log for crash recovery |
| `messages.jsonl` | Inter-agent message log |
| `AGENTS.md` | Worker guidance and mission boundaries |
| `handoffs/<feature-id>.json` | Individual worker handoff reports |

**Per-project directory** (`<project-root>/.mission/`):

| Path | Purpose |
|------|---------|
| `services.yaml` | Commands and services manifest |
| `init.sh` | Idempotent environment setup script |
| `library/` | Shared knowledge base for workers |
| `skills/<worker-type>/SKILL.md` | Per-mission worker skill definitions |
| `research/` | Research artifacts from web searches |
| `validation/<milestone>/` | Validation synthesis reports |

### Decision Tree

After receiving a worker's handoff, the orchestrator applies one of four decision options:

| Option | Trigger | Action |
|--------|---------|--------|
| **A** | High/critical severity issues | Create a follow-up feature in the same milestone |
| **B** | Worker failure | Reset feature to `pending` with updated description |
| **C** | Partial completion | Update existing feature description for retry |
| **D** | Medium/low severity issues | Create a feature in a `misc-*` milestone |

### Milestone Validation

When all implementation features in a milestone are completed, the orchestrator automatically injects two validator features:

1. **`scrutiny-validator-<milestone>`** — Runs tests, typechecking, and linting; reviews each feature's code changes
2. **`user-testing-validator-<milestone>`** — Tests behavioral assertions from the validation contract against the running application

The user-testing validator depends on the scrutiny validator (scrutiny runs first). When both pass, the milestone is **sealed** — no new features can be added to it.

## File Formats

### Extension Manifest (`gemini-extension.json`)

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

### Agent Definition (`agents/*.md`)

Agents use YAML frontmatter with a markdown body:

```markdown
---
name: agent-name
description: "What this agent does"
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

# Agent instructions as markdown...
```

**Rules:**
- `kind` must always be `local`
- `name` must be lowercase with hyphens/underscores only
- `tools` must only contain valid Gemini CLI tool names: `read_file`, `write_file`, `replace`, `run_shell_command`, `grep_search`, `list_directory`, `google_web_search`, `web_fetch`, `glob`, `read_many_files`

### Skill Definition (`skills/*/SKILL.md`)

Skills use YAML frontmatter with a procedural markdown body:

```markdown
---
name: skill-name
description: "What this skill provides"
---

# Skill Name

## When to Use This Skill
...

## Work Procedure
...
```

The directory name must match the `name` field in the frontmatter.

### Command Definition (`commands/*.toml`)

Commands use TOML v1 format:

```toml
description = "Brief description shown in /help"
prompt = """
The prompt sent to the model when the command is invoked.
Use {{args}} for user arguments.
Use @{path/to/file} to inject file content.
Use !{shell command} to inject command output.
"""
```

The `prompt` field is required. The `description` field is optional.

### Hooks Configuration (`hooks/hooks.json`)

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

### State Schemas

#### `state.json`

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

Valid states: `planning`, `orchestrator_turn`, `worker_running`, `handoff_review`, `paused`, `completed`, `failed`

#### `features.json`

```json
{
  "features": [
    {
      "id": "feature-id",
      "description": "What to implement",
      "skillName": "mission-worker",
      "milestone": "milestone-name",
      "preconditions": [],
      "expectedBehavior": ["Feature does X"],
      "verificationSteps": ["Run tests"],
      "fulfills": ["VAL-XXX-001"],
      "status": "pending"
    }
  ]
}
```

Valid statuses: `pending`, `completed`, `cancelled`

#### `validation-state.json`

```json
{
  "assertions": {
    "VAL-XXX-001": { "status": "pending" },
    "VAL-XXX-002": { "status": "passed" },
    "VAL-XXX-003": { "status": "failed" }
  }
}
```

Valid assertion statuses: `pending`, `passed`, `failed`, `blocked`

## How It Works

### Mission Lifecycle

1. **Start** — `/mission-start` scaffolds the mission directory and initializes state
2. **Plan** — `/mission-plan` activates the 7-phase planner: requirements → codebase investigation → milestones → confirmation → infrastructure → testing → artifact generation
3. **Run** — `/mission-run` enters the autonomous orchestrator loop: evaluate DAG → dispatch workers → parse handoffs → apply decisions → update state → check milestones → inject validators → loop
4. **Validate** — Validators are auto-injected at milestone boundaries: scrutiny (tests + code review) then user-testing (behavioral assertion verification)
5. **Complete** — When all features and validators pass, the mission transitions to `completed`

### Cross-Session Persistence

Missions survive Gemini CLI session restarts. All state is written to disk immediately. A `SessionStart` hook (`hooks.json`) automatically loads the active mission's context when you open a new `gemini` session. If a session was interrupted during worker execution, the orchestrator performs crash recovery on the next `/mission-run` — resetting stuck features to `pending` and resuming cleanly.

### Budget & Pause

The orchestrator tracks token usage and auto-pauses when a budget limit is exceeded. You can also manually pause with `/mission-pause`. Resume with `/mission-resume` (budget-paused missions require explicit acknowledgment).

## License

MIT
