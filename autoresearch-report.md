# Autoresearch Final Report

## Summary
**74 experiments** optimized the Gemini Mission Control extension for quality, stability, and size. All kept experiments improved the system.

## Results

| Metric | Baseline | Final | Change |
|--------|----------|-------|--------|
| **total_bytes** | 152,320 | 65,543 | **−57.0%** |
| hot_path_bytes | 60,027 | 26,577 | −55.7% |
| gemini_md_bytes | 20,162 | 6,792 | −66.3% |
| orchestrator_bytes | 39,865 | 19,785 | −50.4% |
| planner_bytes | 25,359 | 9,989 | −60.6% |
| agents_bytes | 33,359 | 18,010 | −46.0% |
| commands_bytes | 16,185 | 5,972 | −63.1% |
| quality_checks | 0 | 196 | +196 |
| hooks | 1 | 6 | +5 |

## Three Phases

### Phase 1: Compression (experiments 1–7)
Removed duplication, verbose phrasing, redundant cross-file repetition. Preserved all JSON examples, edge-case handling, and procedural steps.
**152KB → 57KB** (63% reduction)

### Phase 2: Quality Hardening (experiments 8–62)
Invested ~7KB back to fix bugs and add guardrails. Built a 179-check quality suite.
**57KB → 64KB** (+7KB of critical quality content)

### Phase 3: Hooks (experiments 63–74)
Leveraged Gemini CLI's hook system to enforce rules that were previously just instructions. Added 5 new hooks across 4 event types.
**64KB → 66KB** (+2KB for hook documentation in GEMINI.md)

## Bugs Fixed (3)
1. **Severity format mismatch** — Validators used `blocking/non_blocking` while the decision tree expected `high/medium/low`. Validator handoffs would silently bypass classification.
2. **Option A edge case** — High-severity issues + non-empty `whatWasLeftUndone` had no handling. Could mark incomplete features as completed.
3. **Validator follow-up skillName** — Option A follow-ups from validators would re-assign to the validator agent instead of a worker, creating loops.

## Hooks Added (6)

| Hook | Event | Impact |
|------|-------|--------|
| `load-active-mission-context` | SessionStart | Cross-session persistence (existed before) |
| `validate-state-write` | AfterTool | Catches state.json corruption on every write |
| `validate-features-write` | AfterTool | Catches features.json schema violations on every write |
| `block-pipe-masking` | BeforeTool | **Hard gate** — denies `\| tail`/`\| head` commands that mask exit codes |
| `protect-sealed-milestones` | BeforeTool | Injects sealed milestone reminder on features.json writes |
| `check-state-drift` | AfterAgent | Detects counter mismatches on session end |
| `pre-compress-snapshot` | PreCompress | Logs compression event, reminds agent to re-read state |

The pipe-blocking hook is the most impactful: it converts a text instruction ("don't pipe") into a hard enforcement gate. The LLM literally cannot pipe through tail/head — the tool call is denied with an explanation.

## Quality Suite (196 checks)
- Orchestrator: 8-step loop, decision tree, handoff fields, state machine, critical procedures
- Planner: 7-phase completeness, feature schema, coverage gate, DAG check, user confirmation
- Agents: handoff schema, frontmatter, tool names, pipe warnings, severity format
- Cross-file: terminology, services.yaml format, state machine consistency
- Scenarios: happy path, retry escalation, crash recovery, all-cancelled milestone
- Structural: step ordering, phase ordering, mission completion invariant
- Hooks: JSON validity, executability, JSON I/O, pipe deny/allow, state write passthrough
- Integration: scaffold→validate round-trip

## Key Insight
The biggest quality gains came not from compression but from:
1. **Fixing cross-file inconsistencies** (severity format mismatch was a silent failure)
2. **Adding hooks** that enforce rules deterministically instead of relying on LLM compliance
3. **Making implicit rules explicit** (cancelled features satisfy preconditions, Option A + incomplete → Option B)
