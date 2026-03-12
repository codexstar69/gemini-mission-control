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
