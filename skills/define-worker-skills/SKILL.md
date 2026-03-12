---
name: define-worker-skills
description: Procedure for designing mission-specific worker agent definitions
---

# Define Worker Skills

This skill guides you through designing per-mission worker agent definitions — the specialized subagents that execute feature work during a mission. Each worker type is tailored to the project's needs and expressed as an agent `.md` file with YAML frontmatter and a procedural markdown body.

## When to Use This Skill

Activate this skill when:
- The mission planner (Phase 7) needs to create per-mission worker skill definitions
- You need to design new worker types for a specific project's tech stack
- You need to review or refine existing worker agent definitions

---

## Phase 1: Analyze Effective Work Boundaries

**Goal:** Understand the project deeply enough to determine what kinds of work must be done and where natural boundaries exist between work types.

### Steps

1. **Examine the project structure:**
   ```
   list_directory — Map the top-level and key subdirectories
   read_file — Read package.json, Cargo.toml, go.mod, or equivalent manifest
   read_file — Read README, CONTRIBUTING, or development guides
   ```

2. **Identify the technology domains in the project:**
   - Frontend (React, Vue, Svelte, HTML/CSS, etc.)
   - Backend (API routes, server logic, middleware)
   - Database (schemas, migrations, queries, ORM models)
   - Infrastructure (Docker, CI/CD, deployment configs)
   - Testing (test frameworks, fixtures, mocks)
   - Documentation (API docs, user guides)

3. **Map the tooling landscape:**
   - Build tools and commands (npm, cargo, make, etc.)
   - Linters and formatters (ESLint, Prettier, rustfmt, etc.)
   - Test runners and coverage tools
   - Type checkers (tsc, mypy, etc.)

4. **Identify work that requires different expertise or tool access:**
   - Does some work need internet access (`google_web_search`, `web_fetch`) for API docs or research?
   - Does some work need only file operations (`read_file`, `write_file`, `replace`)?
   - Does some work require running shell commands (`run_shell_command`) for builds, tests, or migrations?
   - Does review work need only read access (`read_file`, `grep_search`, `list_directory`, `glob`)?

5. **Identify risk boundaries:**
   - High-risk changes (database migrations, auth logic, payment integrations) may warrant a cautious agent with lower temperature and more turns
   - Low-risk changes (documentation, formatting, config tweaks) can use a faster agent with fewer turns
   - Code review/quality work should be read-heavy with limited write access

### Output of Phase 1

A written analysis covering:
- Project domains and their boundaries
- Tool access requirements per domain
- Risk levels for different work categories
- Natural groupings of work types

---

## Phase 2: Determine Worker Types

**Goal:** Decide how many distinct worker types are needed and what each one does.

### Design Principles

1. **Minimize worker types.** Most missions need only 2–3 worker types. Don't create a worker type for every feature — group related work. Common patterns:
   - **General implementation worker** — Handles most feature work (CRUD, API endpoints, UI components, etc.)
   - **Code quality worker** — Reviews code, runs linters, refactors, improves test coverage
   - **Infrastructure worker** — Sets up CI/CD, Docker, deployment, environment configuration
   - **Research worker** — Investigates APIs, reads docs, produces research artifacts (has `google_web_search` and `web_fetch`)

2. **Differentiate by tool access, not by topic.** A frontend feature and a backend feature can often use the same worker type because they need the same tools (`read_file`, `write_file`, `run_shell_command`). Only create separate types when tool requirements or procedures differ significantly.

3. **Every project needs at least one implementation worker.** This is the workhorse that handles most features. Additional types are optional.

4. **Match `skillName` to agent `name`.** The `skillName` field in `features.json` maps to the `name` field in the agent frontmatter. They must match exactly.

### Common Worker Type Templates

| Worker Type | Primary Use | Key Tools | Typical Temperature | Typical max_turns |
|---|---|---|---|---|
| `mission-worker` | General feature implementation | `read_file`, `write_file`, `replace`, `run_shell_command`, `grep_search`, `list_directory` | 0.1 | 100 |
| `code-quality-worker` | Code review, refactoring, linting | `read_file`, `grep_search`, `list_directory`, `glob`, `read_many_files`, `run_shell_command` | 0.1 | 80 |
| `infra-worker` | CI/CD, Docker, deployment | `read_file`, `write_file`, `replace`, `run_shell_command`, `list_directory` | 0.1 | 60 |
| `research-worker` | API research, doc lookup | `google_web_search`, `web_fetch`, `read_file`, `write_file`, `list_directory` | 0.2 | 40 |

### Decision Checklist

For each candidate worker type, verify:
- [ ] It handles at least 3 features in the plan (otherwise merge it into a broader type)
- [ ] Its tool set differs meaningfully from other types
- [ ] Its procedure (startup/work/cleanup) would be different enough to justify a separate agent definition
- [ ] The `name` uses only lowercase letters, numbers, hyphens, and underscores

### Output of Phase 2

A list of worker types with:
- Name (lowercase, hyphens/underscores)
- Description (one sentence)
- Tool set
- Which features/milestones it will handle
- Justification for why it's a separate type

---

## Phase 3: Create Agent Definition Files

**Goal:** Write the agent `.md` files with correct YAML frontmatter and procedural body content.

### Agent File Location

Worker agent definitions are placed in the extension's `agents/` directory as markdown files with YAML frontmatter:

- Agent definitions: `agents/<worker-name>.md`

Each worker type gets its own `.md` file in the `agents/` directory. The file name (without extension) should match the agent's `name` field in the frontmatter.

### YAML Frontmatter Specification

Every agent definition MUST begin with YAML frontmatter enclosed in `---` delimiters containing the following fields:

#### Required Fields

| Field | Type | Description |
|---|---|---|
| `name` | string | Agent name. Lowercase, numbers, hyphens, underscores only. Must match the `skillName` used in `features.json`. |
| `description` | string | Brief description of what the agent does. Non-empty. |
| `kind` | string | **MUST be `local`**. Never use `kind: agent`. |
| `tools` | array | List of valid Gemini CLI tool names. See valid tool set below. |

#### Optional Fields

| Field | Type | Default | Description |
|---|---|---|---|
| `model` | string | (inherits) | Model to use, e.g., `gemini-2.5-pro`, `gemini-2.5-flash`. |
| `temperature` | float | 0.1 | Sampling temperature (0.0–1.0). Lower = more deterministic. |
| `max_turns` | integer | 100 | Maximum number of tool-use turns before the agent stops. Minimum recommended: 50. |
| `timeout_mins` | integer | 30 | Maximum wall-clock time in minutes before the agent is terminated. Minimum recommended: 15. |

#### Valid Tool Names

Only the following tool names are valid for Gemini CLI agents. Using any other name will cause errors:

- `read_file` — Read a single file
- `write_file` — Write content to a file (creates or overwrites)
- `replace` — Replace text in a file (surgical edits)
- `run_shell_command` — Execute a shell command
- `grep_search` — Search file contents with patterns
- `list_directory` — List directory contents
- `google_web_search` — Search the web (requires internet)
- `web_fetch` — Fetch a URL's content (requires internet)
- `glob` — Find files matching a glob pattern
- `read_many_files` — Read multiple files at once

**INVALID tool names** (common mistakes to avoid):
- `run_command` → use `run_shell_command`
- `search` → use `grep_search`
- `web_search` → use `google_web_search`
- `find_files` → use `glob`
- `edit_file` → use `replace`

### Frontmatter Example

```yaml
---
name: mission-worker
description: "General-purpose implementation worker for feature development"
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

---

## Phase 4: Write Procedural Body Content

**Goal:** Write the markdown body of the agent definition with clear startup/work/cleanup phases and structured handoff requirements.

### Body Structure

The agent body acts as the system prompt for the subagent. It must be structured into three phases:

#### Phase A: Startup

The startup phase runs once when the worker is dispatched. It establishes context and prepares the environment.

Required sections:
1. **Identity and role** — Who is this agent and what does it do?
2. **Read mission context** — Instructions to read `AGENTS.md`, `.mission/services.yaml`, `.mission/library/` for project-specific guidance.
3. **Run init.sh** — Execute `.mission/init.sh` if it exists (once per session, not per feature).
4. **Understand the assigned feature** — Read the feature description, expectedBehavior, verificationSteps, and any referenced validation contract assertions.
5. **Read relevant code** — Use `read_file`, `grep_search`, `list_directory` to understand the area of code being modified.

#### Phase B: Work

The work phase is the core implementation procedure. It is specific to the worker type.

For an **implementation worker**:
1. Plan the changes before writing code
2. Make changes incrementally (small, testable steps)
3. Run verification commands after each significant change
4. Follow coding conventions from `AGENTS.md` and `.mission/library/`
5. Handle errors — if a test fails, debug and fix before moving on
6. Write or update tests for new functionality

For a **code quality worker**:
1. Run linter/formatter/type checker
2. Review each file changed in the milestone
3. Check for code smells, duplication, missing error handling
4. Make targeted improvements (don't rewrite everything)
5. Verify changes don't break existing tests

For a **research worker**:
1. Use `google_web_search` to find relevant documentation
2. Use `web_fetch` to read specific pages
3. Distill findings into `.mission/library/` or `.mission/research/`
4. Summarize key findings for the implementation workers

#### Phase C: Cleanup

The cleanup phase runs once after work is complete. It prepares the structured handoff.

Required sections:
1. **Final verification** — Run all verification steps from the feature's `verificationSteps` array
2. **Verify expected behaviors** — Confirm each item in `expectedBehavior` is satisfied
3. **Check for regressions** — Run the project's test suite (from `.mission/services.yaml` commands)
4. **Produce structured handoff** — Generate the JSON handoff report (see Phase 5)

---

## Phase 5: Define Structured Handoff Requirements

**Goal:** Specify the exact format workers must use to report their results back to the orchestrator.

### Handoff JSON Schema

Every worker MUST produce a structured handoff in the following format at the end of their work. The orchestrator parses this to make dispatch decisions.

```json
{
  "salientSummary": "1-4 sentence summary of what happened in this session",
  "whatWasImplemented": "Concrete description of what was built (minimum 50 characters)",
  "whatWasLeftUndone": "Anything incomplete or deferred. Empty string if everything is complete.",
  "verification": {
    "commandsRun": [
      {
        "command": "npm test",
        "exitCode": 0,
        "observation": "All 42 tests passed in 3.2s"
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
    "coverage": "Summary of what the tests cover"
  },
  "discoveredIssues": [
    {
      "severity": "non_blocking",
      "description": "ESLint warning in utils.ts:42 — unused import",
      "suggestedFix": "Remove the unused import statement"
    }
  ]
}
```

### Handoff Field Requirements

| Field | Required | Description |
|---|---|---|
| `salientSummary` | Yes | 1-4 sentence summary. Must be specific, not vague. |
| `whatWasImplemented` | Yes | At least 50 characters. Concrete, not "implemented the feature". |
| `whatWasLeftUndone` | Yes | Empty string if complete. Otherwise describe what remains. |
| `verification.commandsRun` | Yes | At least one command with its exit code and what the output showed. |
| `verification.interactiveChecks` | No | For UI/browser work, describe what you clicked and saw. |
| `tests.added` | Yes | Array of test files added, with test case names and what they verify. Empty array if no tests. |
| `tests.coverage` | Yes | Summary of test coverage. |
| `discoveredIssues` | Yes | Array of issues found. Empty array if none. Severity: `blocking` or `non_blocking`. |

### Handoff Rules

1. **Be specific in observations.** Don't write "tests passed" — write "All 42 tests passed in 3.2s with 0 failures."
2. **Report actual exit codes.** Run commands and capture exit codes. Don't assume success.
3. **Don't fabricate results.** Only report commands you actually ran and results you actually observed.
4. **Flag blockers immediately.** If something blocks your work, set severity to `blocking` and describe the issue clearly.

---

## Complete Example: Agent Definition

Below is a complete example of a well-formed agent definition file showing correct YAML frontmatter and procedural body.

```markdown
---
name: mission-worker
description: "General-purpose implementation worker for feature development"
kind: local
tools:
  - read_file
  - write_file
  - replace
  - run_shell_command
  - grep_search
  - list_directory
  - glob
  - read_many_files
model: gemini-2.5-pro
temperature: 0.1
max_turns: 100
timeout_mins: 30
---

# Mission Worker

You are a mission worker responsible for implementing a single feature in the current mission.

## Startup

1. **Read mission guidance:**
   - Use `read_file` on `AGENTS.md` in the mission directory for working directory, boundaries, and conventions.
   - Use `read_file` on `.mission/services.yaml` for available commands and services.
   - Use `read_file` on relevant `.mission/library/` files for architecture and environment info.

2. **Run environment setup:**
   - If `.mission/init.sh` exists, use `run_shell_command` to execute it (once per session).

3. **Understand your assigned feature:**
   - Read the feature description, expectedBehavior, and verificationSteps provided in your dispatch prompt.
   - If the feature has `fulfills` references, read those assertions from `validation-contract.md`.

4. **Explore the relevant code area:**
   - Use `list_directory` and `grep_search` to understand the files you will modify.
   - Use `read_file` on key files to understand existing patterns and conventions.

## Work

1. **Plan your changes** before writing any code. Outline what files you will create or modify.
2. **Implement incrementally.** Make one logical change at a time.
3. **Run verification commands** after each significant change using `run_shell_command`:
   - Run tests: check `.mission/services.yaml` for the test command.
   - Run type checker: check `.mission/services.yaml` for the typecheck command.
   - Run linter: check `.mission/services.yaml` for the lint command.
4. **Fix issues as you go.** If a test fails, debug and fix before proceeding.
5. **Follow coding conventions** documented in `AGENTS.md` and `.mission/library/architecture.md`.
6. **Write or update tests** to cover the new functionality.

## Cleanup

1. **Run all verification steps** from the feature's verificationSteps array.
2. **Confirm each expectedBehavior** is satisfied.
3. **Run the full test suite** to check for regressions.
4. **Produce a structured handoff** in JSON format with:
   - `salientSummary` — What you did and the outcome
   - `whatWasImplemented` — Specific changes made
   - `whatWasLeftUndone` — Empty if complete
   - `verification.commandsRun` — Commands with exit codes and observations
   - `tests.added` — Test files and cases you wrote
   - `discoveredIssues` — Any issues found (with severity)
```

---

## Checklist Before Finalizing

Before completing the worker skill design, verify each agent definition against this checklist:

- [ ] Frontmatter has `name` field (lowercase, hyphens, underscores only)
- [ ] Frontmatter has `description` field (non-empty)
- [ ] Frontmatter has `kind: local` (never `kind: agent`)
- [ ] Frontmatter `tools` array contains ONLY valid Gemini CLI tool names
- [ ] Optional fields (`model`, `temperature`, `max_turns`, `timeout_mins`) use valid values
- [ ] Body contains **Startup** phase with context-reading instructions
- [ ] Body contains **Work** phase with type-specific procedure
- [ ] Body contains **Cleanup** phase with verification and handoff
- [ ] Handoff schema matches the required JSON format
- [ ] Agent `name` matches the `skillName` used in `features.json`
