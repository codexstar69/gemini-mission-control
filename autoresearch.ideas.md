# Autoresearch Ideas Backlog

## Completed ✅
- Scenario trace tests (happy path, retry, crash recovery) — quality suite §25-27
- Cross-reference validation (scaffold→validate round-trip) — quality suite §32
- Agent tool name validation — quality suite §24
- Worker pre-handoff checklist — agents/mission-worker.md
- Option A edge case (high-severity + incomplete → Option B) — orchestrator Step 6
- Handoff context from preconditions in worker prompts — orchestrator Step 3
- Validator feature fields fully specified — orchestrator Step 8.2
- Service cleanup guardrail — agents/user-testing-validator.md
- Severity format standardization (blocking/non_blocking → high/medium/low) — ALL agents
- Step 8.3 sealing criterion fix — orchestrator Step 8.3
- Worker timeout handling — orchestrator Step 4
- Single-session constraint — orchestrator "When to Activate"
- Message bus context in worker prompts — orchestrator Step 3
- Handoff parsing clarification (last JSON block) — orchestrator Step 5
- Cross-file services.yaml format validation — quality suite §29
- State machine cross-validation — quality suite §30
- Validation override deduplication — orchestrator references command instead of duplicating

## Remaining Ideas (Lower Priority)
- **End-to-end simulation test**: Mock mission with 2 milestones, trace full orchestrator flow
- **Progress log rotation**: Guidance for very long missions where progress_log.jsonl grows large
- **Feature description templates**: Standard description formats for common feature types
- **Orchestrator self-monitoring**: Track dispatch cycle time and warn if budget is being consumed too quickly
