# Autoresearch Ideas Backlog

## Explored & Exhausted
- [x] Compression via deduplication (Phase 1, ~63% reduction)
- [x] Quality hardening with guardrails (Phase 2, 215 checks)
- [x] Hook-based enforcement (6 new hooks across 5 event types)
- [x] Gemini CLI Plan Mode — our custom planner is better for this use case
- [x] Gemini CLI policies — hooks already cover key safety rules
- [x] Gemini CLI model routing — agent frontmatter handles this
- [x] Edge case audit — found and fixed 6 bugs

## Future Directions (if needed)
- **Hook: BeforeModel context injection** — inject current mission state into every LLM request so the model never forgets it's in a mission. Currently redundant with SessionStart hook but could help during long sessions.
- **Hook: AfterModel response validation** — validate that worker responses contain valid JSON handoff before the agent processes them. Could catch malformed responses earlier.
- **Policy: block rm -rf in mission dirs** — add a policy that prevents destructive operations in `~/.gemini-mc/missions/`. Low priority since workers don't have delete capabilities.
- **Parallel dispatch** — currently the orchestrator dispatches one feature at a time. Could dispatch multiple independent features in parallel using subagents. Major architectural change.
- **Dynamic temperature** — use higher temperature during planning (creative) and lower during validation (deterministic). Requires BeforeModel hook to override agent frontmatter temperature.
- **Checkpoint/restore** — save full mission state snapshots at milestone boundaries for rollback. Currently only progress_log.jsonl provides event history.
- **MCP integration** — expose mission status and control as MCP tools so other agents/UIs can interact with the mission system.
- **Validation contract inheritance** — allow child missions to inherit VAL assertions from parent missions for multi-project deployments.
