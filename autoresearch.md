# Autoresearch: Gemini Mission Control Shell Script Performance

## What We're Optimizing
The 3 shell scripts in this Gemini CLI extension: `scaffold-mission.sh`, `validate-state.sh`, `session-context.sh`.

## Primary Metric
`total_µs` — sum of median wall-clock microseconds across all 3 scripts (5 runs each).

## Benchmark
`bash autoresearch.sh` — runs each script 5x, takes median, sums them.

## Baseline
~280,000 µs (280ms) total. `session-context.sh` dominates at ~218ms.

## Key Constraints
- Scripts must remain pure bash + jq/python3 (no compiled binaries)
- All existing functionality and output format must be preserved
- `validate-state.sh` must still validate all schema fields
- `session-context.sh` must still find the most recent active mission
- `scaffold-mission.sh` must still create all required files

## Hot Path Analysis
- `session-context.sh` (~218ms, 78%): Iterates all mission dirs, runs jq per dir, runs stat per dir
- `scaffold-mission.sh` (~45ms, 16%): Spawns python3 for JSON generation
- `validate-state.sh` (~17ms, 6%): Single jq invocation, already fast

## Optimization Ideas
- session-context.sh: Replace per-dir jq calls with single jq pass, reduce stat calls
- scaffold-mission.sh: Replace python3 JSON generation with printf/cat
- validate-state.sh: Already lean, minor gains possible
