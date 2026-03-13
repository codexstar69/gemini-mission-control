---
name: define-worker-skills
description: Procedure for designing mission-specific worker agent definitions
---

# Define Worker Skills

Designs per-mission worker agent definitions — subagent `.md` files with YAML frontmatter and procedural body.

## Activation
During planning Phase 7 when creating worker skill definitions.

---

## Phase 1: Analyze Work Boundaries

1. Examine project structure (`list_directory`, `read_file` on manifests/configs)
2. Identify technology domains (frontend, backend, DB, infra, testing, docs)
3. Map tooling (build, lint, test, typecheck commands)
4. Identify work needing different tool access (internet vs file-only vs read-only)
5. Identify risk levels (DB migrations = high, docs = low)

---

## Phase 2: Determine Worker Types

**Principles:**
- Minimize types. Most missions need 2–3. Differentiate by tool access, not by topic.
- Every project needs at least `mission-worker` (general implementation)
- `skillName` in features.json must match agent `name` exactly

Common types:

| Type | Tools | temp | max_turns |
|------|-------|------|-----------|
| `mission-worker` | read_file, write_file, replace, run_shell_command, grep_search, list_directory | 0.1 | 100 |
| `code-quality-worker` | read_file, grep_search, list_directory, glob, read_many_files, run_shell_command | 0.1 | 80 |
| `infra-worker` | read_file, write_file, replace, run_shell_command, list_directory | 0.1 | 60 |
| `research-worker` | google_web_search, web_fetch, read_file, write_file, list_directory | 0.2 | 40 |

Each type must handle ≥3 features (otherwise merge into a broader type).

---

## Phase 3: Create Agent Files

Location: `agents/<worker-name>.md`

### Frontmatter (YAML, required)

```yaml
---
name: worker-name          # lowercase, hyphens, underscores only
description: "What it does" # non-empty
kind: local                 # MUST be "local", never "agent"
tools:                      # ONLY valid Gemini CLI tool names
  - read_file
  - write_file
  - replace
  - run_shell_command
  - grep_search
  - list_directory
model: gemini-2.5-pro       # optional
temperature: 0.1            # optional, 0.0–1.0
max_turns: 100              # optional, min recommended 50
timeout_mins: 30            # optional, min recommended 15
---
```

### Valid tool names
`read_file`, `write_file`, `replace`, `run_shell_command`, `grep_search`, `list_directory`, `google_web_search`, `web_fetch`, `glob`, `read_many_files`.

**Common mistakes:** `run_command`→`run_shell_command`, `search`→`grep_search`, `web_search`→`google_web_search`, `find_files`→`glob`, `edit_file`→`replace`.

---

## Phase 4: Write Agent Body

Three-phase structure:

### Startup
1. Read `AGENTS.md` for boundaries and conventions
2. Read `.mission/services.yaml` for commands/services
3. Read `.mission/library/*.md` for project knowledge
4. Run `.mission/init.sh` if exists (once per session)
5. Understand assigned feature: description, expectedBehavior, verificationSteps, fulfills

### Work (varies by type)
- **Implementation:** Plan → implement incrementally → run verification after each change → follow conventions → write tests
- **Quality:** Run lint/typecheck → review changed files → fix issues → verify no regressions
- **Research:** google_web_search → web_fetch → distill into library/research files

### Cleanup
1. Run all verificationSteps
2. Confirm each expectedBehavior satisfied
3. Run full test suite (from services.yaml)
4. Produce structured JSON handoff

---

## Handoff Schema

Every worker MUST produce this JSON at the end:

```json
{
  "salientSummary": "1-4 sentences, specific",
  "whatWasImplemented": "≥50 chars, concrete",
  "whatWasLeftUndone": "" or "remaining work",
  "verification": {
    "commandsRun": [{"command":"...","exitCode":0,"observation":"..."}],
    "interactiveChecks": [{"action":"...","observed":"..."}]
  },
  "tests": {
    "added": [{"file":"...","cases":[{"name":"...","verifies":"..."}]}],
    "coverage": "summary"
  },
  "discoveredIssues": [{"severity":"high|medium|low","description":"...","suggestedFix":"..."}]
}
```

Required: salientSummary, whatWasImplemented, whatWasLeftUndone, verification.commandsRun (≥1), discoveredIssues (can be []).

**Rules:**
- Report actual exit codes. Don't fabricate results. Flag blockers as severity=high.
- **CRITICAL for Work phase:** Include an explicit warning in every agent body to never pipe command output through `| tail` or `| head` — this masks exit codes and hides failures.

---

## Checklist
- [ ] `name` lowercase, hyphens/underscores only
- [ ] `kind: local` (never `kind: agent`)
- [ ] `tools` array uses ONLY valid Gemini CLI tool names
- [ ] Body has Startup/Work/Cleanup phases
- [ ] Cleanup includes `git add -A && git commit` step
- [ ] Cleanup includes pipe-masking warning
- [ ] Handoff schema matches required format (all 5 required fields)
- [ ] Agent `name` matches `skillName` in features.json
