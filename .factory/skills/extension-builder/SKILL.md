---
name: extension-builder
description: Builds Gemini CLI extension files — agents, skills, commands, hooks, scripts, and manifest configuration
---

# Extension Builder

NOTE: Startup and cleanup are handled by `worker-base`. This skill defines the WORK PROCEDURE.

## When to Use This Skill

Use this worker for features that create or modify:
- `gemini-extension.json` manifest
- `GEMINI.md` context file
- Agent definitions in `agents/*.md` (YAML frontmatter + markdown body)
- Skill definitions in `skills/*/SKILL.md` (YAML frontmatter + markdown body)
- Custom commands in `commands/*.toml` (TOML with `prompt` and `description`)
- Hook configuration in `hooks/hooks.json`
- Shell scripts in `scripts/`
- `README.md`

## Work Procedure

### Phase 1: Understand the Feature

1. Read the feature description, expectedBehavior, and verificationSteps from the assignment.
2. Read `GEMINI.md` (if it exists) to understand the orchestrator context and conventions.
3. Read `.factory/library/architecture.md` for architectural decisions already made.
4. Read `.factory/library/gemini-cli-reference.md` for Gemini CLI extension format details.

### Phase 2: Implement

For each file the feature requires:

**Agent definitions (`agents/*.md`):**
- YAML frontmatter MUST include: `name` (lowercase, hyphens, underscores), `description`, `kind: local`
- Frontmatter MAY include: `tools` (array), `model`, `temperature`, `max_turns`, `timeout_mins`
- Valid tool names ONLY: `read_file`, `write_file`, `replace`, `run_shell_command`, `grep_search`, `list_directory`, `google_web_search`, `web_fetch`, `glob`, `read_many_files`
- Body: structured system prompt with phases (Startup, Work, Cleanup/Handoff)
- NEVER use `kind: agent`, `run_command`, `search`, or `web_search` — these are invalid

**Skill definitions (`skills/*/SKILL.md`):**
- YAML frontmatter MUST include: `name`, `description`
- Body: When to Use, Work Procedure (numbered steps), Example output
- Skills are activated via `activate_skill` tool call — they provide procedural knowledge

**Custom commands (`commands/*.toml`):**
- MUST have `prompt` field (required, string) and `description` field (optional, string)
- Use `{{args}}` for user argument interpolation in prompts
- Use `@{path/to/file}` to inject file content
- Use `!{shell command}` for dynamic output injection
- TOML v1 format only

**Hook configuration (`hooks/hooks.json`):**
- Valid JSON with event-based structure
- Valid lifecycle events: `SessionStart`, `SessionEnd`, `BeforeAgent`, `AfterAgent`, `BeforeTool`, `AfterTool`
- Hook commands reference executable scripts

**Shell scripts (`scripts/*.sh`):**
- `#!/usr/bin/env bash` shebang
- `set -euo pipefail` for safety
- Make executable: `chmod +x`
- Must be idempotent (safe to run multiple times)

### Phase 3: Verify

1. Validate JSON files: `jq . <file>` for JSON, `python3 -c "import tomllib; tomllib.load(open('<file>','rb'))"` for TOML
2. Validate agent frontmatter: check `kind: local`, valid tool names, required fields
3. Validate skill frontmatter: check `name` and `description` present
4. Check shell scripts are executable: `test -x <file>`
5. Run `gemini extensions link .` from project root — must exit 0
6. Cross-reference manifest directories with actual file structure

### Phase 4: Handoff

Return structured handoff with all verification results.

## Example Handoff

```json
{
  "salientSummary": "Created mission-worker agent definition with read_file, write_file, replace, run_shell_command, grep_search, list_directory tools. Frontmatter uses kind: local. Body contains 3-phase procedure (Startup, Work, Cleanup) with structured JSON handoff protocol. Verified frontmatter parses correctly and all tool names are in the valid set. gemini extensions link . exits 0.",
  "whatWasImplemented": "agents/mission-worker.md — full agent definition with YAML frontmatter (name, description, kind, tools, model, temperature, max_turns, timeout_mins) and markdown body defining the worker's 3-phase procedure for autonomous feature implementation including init.sh execution, TDD workflow, and structured JSON handoff output format.",
  "whatWasLeftUndone": "",
  "verification": {
    "commandsRun": [
      {"command": "python3 -c \"import yaml; yaml.safe_load(open('agents/mission-worker.md').read().split('---')[1])\"", "exitCode": 0, "observation": "Frontmatter parses as valid YAML"},
      {"command": "gemini extensions link .", "exitCode": 0, "observation": "Extension linked successfully, no validation errors"}
    ],
    "interactiveChecks": [
      {"action": "Verified all tool names against valid set", "observed": "All 6 tools (read_file, write_file, replace, run_shell_command, grep_search, list_directory) are valid Gemini CLI tool names"},
      {"action": "Checked kind field", "observed": "kind: local — correct value"}
    ]
  },
  "tests": {
    "added": [],
    "updated": [],
    "coverage": "N/A — declarative extension, no compiled tests"
  },
  "discoveredIssues": []
}
```

## When to Return to Orchestrator

- Gemini CLI extension format has changed and documentation doesn't match expected behavior
- `gemini extensions link .` fails with errors that can't be resolved by fixing file format
- Feature requires creating a file type not covered by this skill's procedures
