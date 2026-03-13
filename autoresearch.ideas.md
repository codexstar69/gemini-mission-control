# Autoresearch Ideas Backlog

## Completed
- ✅ Scenario trace tests (happy path, retry, crash recovery)
- ✅ Cross-reference validation (scaffold→validate round-trip)
- ✅ Agent tool name validation
- ✅ Worker pre-handoff checklist
- ✅ Option A edge case (high-severity + incomplete → Option B)
- ✅ Handoff context from preconditions in worker prompts
- ✅ Validator feature fields fully specified
- ✅ Service cleanup guardrail

## Quality Improvements (Remaining)
- **End-to-end simulation test**: Create a mock mission with 2 milestones and trace through the entire orchestrator flow verifying state changes at each step
- **Validator handoff parsing**: The scrutiny and user-testing validators produce different handoff formats (blocking/non_blocking vs high/medium/low severity). Verify the orchestrator handles both correctly.
- **Message bus consumption**: Workers are told to read `messages.jsonl` but the orchestrator doesn't explicitly include recent messages in the worker prompt. Consider adding this.

## Byte Reduction (Quality-Preserving)
- **Deduplicate log event format**: The `{"timestamp":"...","event":"..."}` pattern appears 9 times in orchestrator. Could define once and reference. Saves ~200 bytes.
- **Combine Pause/Resume with Budget**: These share logic. Could merge sections. Saves ~100 bytes.
- **Command TOML "find mission" pattern**: 7 commands repeat the same "find mission" logic. Could reference a shared pattern. But TOML commands are independently loaded, so this may not be possible.

## Stability Improvements
- **Worker timeout handling**: What happens when a worker hits timeout_mins? The orchestrator should have explicit instructions for handling subagent timeouts.
- **Concurrent access protection**: If two sessions try to run the same mission simultaneously, state corruption is possible. Document single-session constraint.
- **Progress log rotation**: Over very long missions, progress_log.jsonl could grow large. Consider adding rotation or trimming guidance.
