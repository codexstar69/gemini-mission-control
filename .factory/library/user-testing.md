# User Testing

Testing surface: tools, URLs, setup steps, isolation notes, known quirks.

**What belongs here:** How to manually test the extension, what tools to use, known limitations.

---

## Testing Surface

- **Tool**: Gemini CLI (`gemini` command in terminal)
- **Entry points**: Custom commands (`/mission-start`, `/mission-plan`, `/mission-run`, `/mission-status`, etc.)
- **Verification method**: Run commands, observe output, check state files with `jq`
- **No browser testing needed** — this is a CLI extension

## Validation Tools

- `jq` — JSON validation and querying
- `python3 -c "import tomllib; ..."` — TOML validation
- `gemini extensions link .` — Extension structural validation
- Shell scripts in `scripts/` — Automated checks

## Testing Workflow

1. Link extension: `gemini extensions link .`
2. Open Gemini CLI: `gemini`
3. Run commands: `/mission-start "test project"`, `/mission-status`, etc.
4. Verify state files: `jq . ~/.gemini-mc/missions/mis_*/state.json`

## Known Quirks

- Subagents require `experimental.enableAgents: true` in settings.json
- Agent names must be lowercase with hyphens/underscores only
- `google_web_search` is the correct tool name (not `web_search`)
- Hooks use JSON format (`hooks.json`), not TOML

## Flow Validator Guidance: gemini-cli-extension

- Use the real Gemini CLI surface from `/Users/codex/Projects/gemini-mission-control-extension`; do not simulate command behavior by only reading files when a CLI flow can be exercised directly.
- Preferred command pattern for headless checks: `gemini -p "<prompt>" -y --approval-mode yolo -e gemini-mission-control` from the project root after ensuring the extension is linked.
- Isolate parallel runs by assigning each validator a unique mission/data namespace, such as distinct mission descriptions or explicit mission IDs/prefixes in any created artifacts under `~/.gemini-mc/missions/`.
- Do not modify or delete pre-existing missions in `~/.gemini-mc/missions/`; validators may create new missions but should only inspect or reference the ones in their assigned namespace.
- For `/mission-list`, validate that the assigned namespace missions appear with correct state ordering/fields rather than asserting exact global mission counts, because other missions may already exist.
- No browser automation is needed; CLI output plus direct inspection of generated mission files with `jq`, `python3 -c 'import tomllib'`, and shell checks is the correct evidence surface.
- When a command cannot be exercised non-interactively, fall back to validating the generated artifacts and prompt behavior as closely as possible, and record the limitation explicitly in the flow report.
