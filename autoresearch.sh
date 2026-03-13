#!/usr/bin/env bash
set -euo pipefail

# Benchmark all 3 shell scripts. Primary metric: total wall-clock µs.
# Runs each script 5 times and reports the median.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Ensure a test mission exists for scaffold (clean each run)
rm -rf "$HOME/.gemini-mc/missions/mis_bench_tmp"

time_us() {
  # Run command, return wall-clock microseconds (via gdate or python fallback)
  local cmd="$*"
  local start end
  if command -v gdate &>/dev/null; then
    start=$(gdate +%s%N)
    eval "$cmd" >/dev/null 2>&1
    end=$(gdate +%s%N)
    echo $(( (end - start) / 1000 ))
  else
    python3 -c "
import subprocess, time
s=time.perf_counter()
subprocess.run('$cmd', shell=True, capture_output=True)
e=time.perf_counter()
print(int((e-s)*1_000_000))
"
  fi
}

median() {
  # Read numbers from stdin, print median
  sort -n | awk '{a[NR]=$1} END{print a[int((NR+1)/2)]}'
}

RUNS=5

# --- scaffold-mission.sh ---
scaffold_times=()
for i in $(seq 1 $RUNS); do
  rm -rf "$HOME/.gemini-mc/missions/mis_bench_tmp"
  t=$(time_us "bash scripts/scaffold-mission.sh bench_tmp /tmp/bench")
  scaffold_times+=("$t")
done
scaffold_median=$(printf '%s\n' "${scaffold_times[@]}" | median)

# --- validate-state.sh ---
validate_times=()
for i in $(seq 1 $RUNS); do
  t=$(time_us "bash scripts/validate-state.sh 076af0")
  validate_times+=("$t")
done
validate_median=$(printf '%s\n' "${validate_times[@]}" | median)

# --- session-context.sh ---
session_times=()
for i in $(seq 1 $RUNS); do
  t=$(time_us "bash scripts/session-context.sh")
  session_times+=("$t")
done
session_median=$(printf '%s\n' "${session_times[@]}" | median)

# Total
total=$((scaffold_median + validate_median + session_median))

# Cleanup
rm -rf "$HOME/.gemini-mc/missions/mis_bench_tmp"

echo "=== RESULTS ==="
echo "scaffold_µs: ${scaffold_median}"
echo "validate_µs: ${validate_median}"
echo "session_µs: ${session_median}"
echo "total_µs: ${total}"
