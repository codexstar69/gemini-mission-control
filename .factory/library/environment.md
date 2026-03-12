# Environment

Environment variables, external dependencies, and setup notes.

**What belongs here:** Required tools, Gemini CLI version constraints, configuration notes.
**What does NOT belong here:** Service ports/commands (use `.factory/services.yaml`).

---

## Prerequisites

- Gemini CLI v0.33+ (installed and functional)
- `experimental.enableAgents: true` in `~/.gemini/settings.json`
- Python 3 (for TOML validation)
- `jq` (for JSON validation)
- `shellcheck` (optional, for shell script validation)

## State Directory

Mission state stored at `~/.gemini-mc/missions/`. This directory is shared with the old TypeScript CLI project — do NOT delete existing missions.

## Extension Installation

```bash
cd /Users/codex/Projects/gemini-mission-control-extension
gemini extensions link .
```
