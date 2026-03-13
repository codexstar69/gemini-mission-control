# Autoresearch Ideas Backlog

## Quality Improvements (High Impact)
- **Add scenario trace tests**: Walk through specific scenarios (happy path, worker failure, crash recovery, milestone sealing) in the quality test to verify the orchestrator handles each correctly
- **Cross-reference validation**: Verify that every field the orchestrator writes to state.json is listed in the validate-state.sh schema check
- **Agent tool validation**: Verify that every tool name in agent frontmatter is in the valid tool list from define-worker-skills
- **services.yaml format alignment**: Ensure planner, orchestrator, and all agents reference the same services.yaml key structure

## Byte Reduction (Quality-Preserving)
- **Deduplicate log event format examples**: The orchestrator has many `{"timestamp":"...","event":"..."}` examples. Could define a "Log format" section once and reference it
- **Compress GEMINI.md directory tree**: The ASCII directory listing could use a more compact format
- **TOML commands**: Some commands repeat "find most recent mission" logic. Could extract to a shared pattern reference

## Stability Improvements
- **Add explicit "STOP" markers**: Before risky operations (state transitions, milestone sealing), add prominent stop-and-verify instructions
- **Add pre-commit verification**: Before each git commit in workers, verify all tests pass (some workers might commit broken code)
- **Idempotency documentation**: Document which operations are safe to retry vs which have side effects
