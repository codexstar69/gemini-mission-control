# Autoresearch: Gemini Mission Control — Instruction Quality & Stability

## What We're Optimizing
The quality, clarity, and reliability of all instruction files in this Gemini CLI extension. The LLM IS the runtime — it follows markdown instructions as its "source code." Instruction quality directly determines mission success rate.

## Primary Metric
`total_bytes` — total instruction surface area. Lower is better ONLY when quality is preserved or improved. Byte reduction without quality preservation is a regression.

## Quality Criteria (must pass on every experiment)
1. **Semantic completeness** — Every procedure, state rule, edge case, and recovery path must be fully specified
2. **Unambiguity** — No step should have multiple interpretations. Conditionals must be explicit.
3. **Error path coverage** — Every "what if X fails" must have a documented response
4. **LLM execution fidelity** — Instructions must be followable by Gemini 2.5 without external context
5. **Cross-file consistency** — Concepts referenced across files must use identical terminology

## Quality Test (run after every change)
`bash autoresearch-quality.sh` — traces through key execution scenarios and verifies all required concepts, procedures, and error paths are present and correctly cross-referenced.

## Optimization Strategy (Quality-First)
1. **Remove genuine redundancy** — Same concept stated identically in multiple files. Keep the canonical version, remove the copies. But keep cross-references.
2. **Improve clarity** — Rewrite ambiguous instructions. Add explicit conditionals. Replace "if needed" with specific criteria.
3. **Add missing guardrails** — Common LLM failure modes (pipe masking exit codes, fabricating results, drifting from scope) need explicit warnings.
4. **Restructure for cognitive load** — LLMs follow sequential procedures better than nested conditionals. Flatten complex decision trees.
5. **Preserve examples** — JSON schema examples are critical for correct output format. Never remove them.
6. **Only then compress** — Once quality is locked in, remove filler words and verbose explanations that don't add information.

## Key Constraint
**Never trade clarity for brevity.** A 10KB file that the LLM follows correctly beats a 5KB file it misinterprets.

## Current State (post-compression pass)
All files have been compressed. Some may have lost important nuance. Quality audit needed.
