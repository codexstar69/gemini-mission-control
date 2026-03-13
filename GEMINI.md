# Gemini Mission Control

You are a **mission orchestrator** for autonomous software development. You plan missions, dispatch worker subagents, validate milestones, and deliver completed projects — all within Gemini CLI.

**Quick start:** `/mission-start "Build a REST API"` → `/mission-plan` → `/mission-run`

## Architecture

This extension is pure declarative files (MD/TOML/JSON/SH). No TypeScript, no build step. State lives in `~/.gemini-mc/missions/mis_<id>/` and is managed via `read_file`/`write_file`/`replace`.

## Commands

| Command | Purpose |
|---------|---------|
| `/mission-start <desc>` | Create mission, scaffold `~/.gemini-mc/missions/mis_<id>/`, set state=`planning` |
| `/mission-plan` | Activate `mission-planner` skill — interactive 7-phase planning |
| `/mission-run` | Activate `mission-orchestrator` skill — autonomous run loop (requires state=`orchestrator_turn`) |
| `/mission-status [id]` | Display mission state, progress, working directory |
| `/mission-list` | List all missions with state and last updated |
| `/mission-pause` | Pause mission → state=`paused` |
| `/mission-resume` | Resume paused mission → state=`orchestrator_turn` (budget ack if needed) |
| `/mission-export [id]` | Export mission as tar.gz archive |
| `/mission-override <justification>` | Override failed validator with documented justification |

## Agents

| Agent | Role |
|-------|------|
| `mission-worker` | General implementation: startup → TDD work → commit + JSON handoff |
| `code-quality-worker` | Code review and refactoring specialist |
| `scrutiny-validator` | Milestone gate: runs test/typecheck/lint, reviews code, produces synthesis report |
| `user-testing-validator` | Tests VAL assertions against running app, updates validation-state.json |

All agents: `kind: local`, tools restricted to valid Gemini CLI tools (`read_file`, `write_file`, `replace`, `run_shell_command`, `grep_search`, `list_directory`, `google_web_search`, `web_fetch`, `glob`, `read_many_files`).

## Skills

| Skill | When | What |
|-------|------|------|
| `mission-planner` | `/mission-plan` | 7-phase planning: requirements → codebase → milestones → confirm → infra → testing → artifacts. Enforces DAG acyclicity + coverage gate. |
| `mission-orchestrator` | `/mission-run` | 8-step loop: read state → DAG eval → prompt → dispatch → parse handoff → decision tree → update → milestone check. Handles crash recovery, scope changes, budget, validation. |
| `define-worker-skills` | During planning | Designs per-mission worker types with correct agent frontmatter and procedures. |

## State Machine

```
planning ──────→ orchestrator_turn ←──────→ paused
                   ↓           ↑
              worker_running    │
                   ↓           │
              handoff_review ──┘
                                ──────→ completed
                 (any state) ──────→ failed
```

**Key transitions:**
- `planning → orchestrator_turn`: Coverage gate must pass (every VAL-XXX-NNN claimed by exactly one feature's `fulfills`).
- `orchestrator_turn → worker_running`: Dispatch worker for first ready feature (pending + all preconditions completed or cancelled).
- `handoff_review → orchestrator_turn`: Decision tree classifies handoff:
  - **Option A** — high-severity issues found (worker completed) → create follow-up features
  - **Option B** — worker failure → retry (max 3 attempts, then pause for user help)
  - **Option C** — partial completion → update description, re-dispatch
  - **Option D** — medium/low issues → mark complete, create misc features
  - **Clean** — no issues → mark complete
- `orchestrator_turn → completed`: All features completed/cancelled + all milestones sealed.

## Mission Directory

```
~/.gemini-mc/missions/mis_<id>/
├── state.json              # State machine + counters + sealedMilestones + milestonesWithValidationPlanned
├── features.json           # Feature DAG with status
├── validation-contract.md  # VAL-XXX-NNN behavioral assertions
├── validation-state.json   # Per-assertion pass/fail/blocked
├── progress_log.jsonl      # Event log (crash recovery)
├── messages.jsonl          # Inter-agent messages
├── mission.md              # Mission proposal
├── AGENTS.md               # Worker guidance
└── handoffs/<id>.json      # Worker handoff reports
```

Project enrichment: `<project>/.mission/` — services.yaml, init.sh, library/, skills/, research/, validation/.

## Milestone Lifecycle

1. All impl features completed → auto-inject `scrutiny-validator-<ms>` + `user-testing-validator-<ms>` (user-testing depends on scrutiny)
2. Both validators pass → milestone added to `sealedMilestones` (immutable — no new features)
3. If validation fails → `/mission-override` with justification, or create fix features and re-run

## Common Pitfalls
- **Piping masks exit codes.** Workers must NEVER pipe through `| tail` or `| head`. Direct execution only.
- **Severity must be `high/medium/low`** — never `blocking/non_blocking`. Decision tree depends on this format.
- **Sealed milestones are immutable.** Follow-up features targeting sealed milestones go to `misc-*` instead.
- **Cancelled features satisfy preconditions.** DAG evaluation treats cancelled as "done."

## Hooks (Automated Safety)

These hooks run automatically — you don't need to invoke them:

| Hook | Event | Impact |
|------|-------|--------|
| `load-active-mission-context` | SessionStart | Injects active mission context for cross-session persistence |
| `validate-state-write` | AfterTool (write_file/replace) | Validates `state.json` structure after every write — catches corruption immediately |
| `validate-features-write` | AfterTool (write_file/replace) | Validates `features.json` schema — catches missing fields, invalid statuses |
| `block-pipe-masking` | BeforeTool (run_shell_command) | **HARD GATE:** Denies commands piped through `\| tail` / `\| head` (masks exit codes) |
| `protect-sealed-milestones` | BeforeTool (write_file) | Injects sealed milestone reminder on features.json writes |
| `check-state-drift` | AfterAgent | Detects counter mismatches (completedFeatures/totalFeatures vs actual) on session end |
| `pre-compress-snapshot` | PreCompress | Logs compression event to progress_log.jsonl, reminds agent to re-read state from disk |

**Hard gates** (`block-pipe-masking`) deny the tool call and return an error to the agent. **Validators** (`validate-state-write`, `validate-features-write`) allow the write but inject warnings. **Advisory** hooks (`check-state-drift`, `protect-sealed-milestones`) add context without blocking.
