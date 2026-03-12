# Gemini CLI Extension Reference

Quick reference for Gemini CLI extension file formats and conventions.

---

## Extension Manifest (gemini-extension.json)

```json
{
  "name": "extension-name",
  "version": "0.1.0",
  "description": "Extension description",
  "contextFileName": "GEMINI.md",
  "commandsDir": "commands",
  "skillsDir": "skills",
  "hooksDir": "hooks"
}
```

## Agent Definition Format (agents/*.md)

```markdown
---
name: agent-name
description: "What this agent does"
kind: local
tools:
  - read_file
  - write_file
  - replace
  - run_shell_command
  - grep_search
  - list_directory
model: gemini-2.5-pro
temperature: 0.1
max_turns: 100
timeout_mins: 30
---

System prompt body as markdown...
```

### Valid Tool Names
- `read_file`, `write_file`, `replace`
- `run_shell_command`
- `grep_search`, `list_directory`, `glob`, `read_many_files`
- `google_web_search`, `web_fetch`

### INVALID Tool Names (never use)
- `run_command` (use `run_shell_command`)
- `search` (use `grep_search`)
- `web_search` (use `google_web_search`)
- `kind: agent` (use `kind: local`)

## Skill Format (skills/*/SKILL.md)

```markdown
---
name: skill-name
description: "What this skill provides"
---

# Skill Name

## When to Use This Skill
...

## Work Procedure
...
```

Skills are activated via `activate_skill` tool call. They provide procedural knowledge.

## Command Format (commands/*.toml)

```toml
description = "Brief description shown in /help"
prompt = "The prompt sent to the model when command is invoked. Use {{args}} for user arguments."
```

Special syntax in prompts:
- `{{args}}` — User arguments (shell-escaped in `!{...}` blocks)
- `@{path/to/file}` — Inject file content (processed first)
- `!{shell command}` — Execute shell command and inject output

## Hook Format (hooks/hooks.json)

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "*",
        "hooks": [
          {
            "name": "hook-name",
            "type": "command",
            "command": "path/to/script.sh",
            "timeout": 5000
          }
        ]
      }
    ]
  }
}
```

Valid events: SessionStart, SessionEnd, BeforeAgent, AfterAgent, BeforeTool, AfterTool

## Extension Linking

```bash
gemini extensions link .   # Register extension
gemini extensions list     # Verify registration
```
