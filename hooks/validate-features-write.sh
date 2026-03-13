#!/usr/bin/env bash
set -uo pipefail

# AfterTool hook: validate features.json after writes
# Catches common schema violations: missing required fields, invalid status values, cyclic dependencies

input=$(cat)

# Extract file path
file_path=$(echo "$input" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//')
if [ -z "$file_path" ]; then
  file_path=$(echo "$input" | grep -o '"path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//')
fi

# Only validate features.json writes
case "$file_path" in
  */missions/mis_*/features.json)
    ;;
  *)
    echo '{"decision":"allow"}'
    exit 0
    ;;
esac

[ -f "$file_path" ] || { echo '{"decision":"allow"}'; exit 0; }

content=$(cat "$file_path" 2>/dev/null)
[ -n "$content" ] || { echo '{"decision":"allow","systemMessage":"🚨 features.json is empty after write"}'; exit 0; }

warnings=""

# Check that it has a features array
if ! echo "$content" | grep -q '"features"'; then
  warnings="${warnings}Missing top-level 'features' key. "
fi

# Check each feature has required fields
for field in '"id"' '"description"' '"status"' '"milestone"'; do
  # Count features vs field occurrences (rough check)
  feature_count=$(echo "$content" | grep -c '"id"[[:space:]]*:' 2>/dev/null || echo "0")
  field_count=$(echo "$content" | grep -c "${field}[[:space:]]*:" 2>/dev/null || echo "0")
  if [ "$feature_count" -gt 0 ] && [ "$field_count" -lt "$feature_count" ]; then
    clean_field=$(echo "$field" | tr -d '"')
    warnings="${warnings}Some features missing '${clean_field}' field (${field_count}/${feature_count}). "
  fi
done

# Check for invalid status values
invalid_statuses=$(echo "$content" | grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -v '"pending"\|"completed"\|"cancelled"' || true)
if [ -n "$invalid_statuses" ]; then
  warnings="${warnings}Invalid status values found (must be pending/completed/cancelled): ${invalid_statuses}. "
fi

if [ -n "$warnings" ]; then
  cat <<EOF
{"decision":"allow","systemMessage":"⚠️ FEATURES.JSON VALIDATION: ${warnings}"}
EOF
else
  echo '{"decision":"allow"}'
fi
exit 0
