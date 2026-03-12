# Architecture

Architectural decisions and patterns for the Gemini-native mission control extension.

**What belongs here:** Architectural choices, design patterns, component relationships, file format decisions.

---

## Core Architecture

This is a pure Gemini CLI extension — no TypeScript, no build step, no compiled code. Everything is declarative files:

- **Agents** (`agents/*.md`): Subagent definitions with YAML frontmatter + markdown body. Workers dispatched via native subagent tool calls.
- **Skills** (`skills/*/SKILL.md`): Procedural knowledge activated on demand via `activate_skill`. The orchestrator IS a Gemini agent using skills for its procedure.
- **Commands** (`commands/*.toml`): Custom slash commands with `prompt` and `description` fields.
- **Hooks** (`hooks/hooks.json`): Lifecycle event handlers.
- **Scripts** (`scripts/*.sh`): Shell helper scripts for scaffolding and validation.
- **Context** (`GEMINI.md`): Orchestrator identity, state management protocols, available resources.

## State Management

All state is managed via native file tools (`read_file`, `write_file`, `replace`):

- **Mission state**: `~/.gemini-mc/missions/mis_<id>/state.json`
- **Features**: `~/.gemini-mc/missions/mis_<id>/features.json`
- **Validation**: `~/.gemini-mc/missions/mis_<id>/validation-state.json`
- **Progress log**: `~/.gemini-mc/missions/mis_<id>/progress_log.jsonl`
- **Handoffs**: `~/.gemini-mc/missions/mis_<id>/handoffs/<feature-id>.json`

## File Format Conventions

- Agent frontmatter: `kind: local` always. Valid tool names only.
- Commands: TOML v1 with `prompt` (required) and `description` (optional).
- Hooks: JSON format (`hooks.json`), NOT TOML.
- State files: Valid JSON, parseable by `jq`.
