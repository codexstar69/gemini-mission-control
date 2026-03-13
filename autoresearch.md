# Autoresearch: Gemini Mission Control — Instruction Token Footprint

## What We're Optimizing
The total byte size of all instruction files (GEMINI.md, skills, agents, commands) that the Gemini LLM loads during autonomous mission execution. Smaller instructions = fewer tokens consumed per loop iteration = faster + cheaper missions + better instruction following (less noise).

## Primary Metric
`total_bytes` — sum of all instruction file sizes (GEMINI.md + skills + agents + commands).

## Key Secondary Metric  
`hot_path_bytes` — GEMINI.md + mission-orchestrator SKILL.md. This is what gets loaded on EVERY orchestrator loop iteration and is the highest-leverage target.

## Benchmark
`bash autoresearch.sh` — measures file sizes of all instruction content.

## Key Constraints
- **Semantic completeness**: All procedures, state machine rules, decision tree logic, validation pipeline, crash recovery, DAG evaluation, sealed milestones, etc. MUST be preserved. The LLM follows these as its "source code" — removing a step means the LLM won't do it.
- **Gemini CLI compatibility**: Must work within Gemini CLI's extension system (TOML commands, MD skills/agents, JSON hooks).
- **No behavioral regressions**: The extension must produce identical mission outcomes after compression.
- **Correctness test**: After each edit, run `bash scripts/validate-state.sh` on a test mission to confirm no schema drift. Also visually check that key procedures (8-step loop, decision tree, milestone lifecycle) are still fully specified.

## Optimization Strategy
1. **Eliminate redundancy**: The same concepts (state machine, decision tree, sealed milestones) are repeated across GEMINI.md, mission-orchestrator SKILL.md, and mission-planner SKILL.md. Deduplicate by having one canonical location and referencing it.
2. **Compress prose**: Replace verbose explanations with concise, imperative instructions. LLMs follow terse instructions just as well as verbose ones.
3. **Remove examples when schema is clear**: If the JSON schema is defined, don't also show a full example.
4. **Restructure for progressive disclosure**: Move rarely-needed details (scope changes, research delegation, feature cancellation) out of the hot path.
5. **Agent body compression**: Worker agents repeat similar startup/cleanup boilerplate. Extract shared patterns.

## Files by Priority (bytes → tokens ≈ bytes/4)
1. mission-orchestrator SKILL.md (~40KB, ~10K tokens) — THE hot path
2. mission-planner SKILL.md (~25KB, ~6K tokens) — loaded once per mission
3. GEMINI.md (~20KB, ~5K tokens) — loaded every session
4. define-worker-skills SKILL.md (~17KB, ~4K tokens) — loaded once per mission
5. agents/* (~34KB total, ~8K tokens) — loaded per worker dispatch
6. commands/*.toml (~16KB total, ~4K tokens) — loaded per command invoke
