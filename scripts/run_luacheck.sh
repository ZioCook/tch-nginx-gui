#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

MAX_WARNINGS=532

mapfile -t files < <(find decompressed -type f \( -name "*.lp" -o -name "*.lua" \) | sort)
echo "Total files to check: ${#files[@]}"

if [ "$#" -gt 0 ]; then
  luacheck --config .luacheckrc "$@" "${files[@]}"
  exit $?
fi

rc=0
out=$(luacheck --config .luacheckrc --no-color --codes "${files[@]}") || rc=$?
printf '%s\n' "$out"

summary=$(printf '%s\n' "$out" | grep -E '^Total: [0-9]+ warnings? / [0-9]+ errors?' | tail -n 1 || true)
if [ -z "$summary" ]; then
  echo "ERROR: could not parse luacheck summary (exit=$rc)" >&2
  exit 2
fi

warnings=$(printf '%s\n' "$summary" | sed -E 's/^Total: ([0-9]+) warnings? \/ ([0-9]+) errors?.*/\1/')
errors=$(printf '%s\n' "$summary" | sed -E 's/^Total: ([0-9]+) warnings? \/ ([0-9]+) errors?.*/\2/')

if [ "$rc" -ge 2 ] || [ "$errors" -gt 0 ]; then
  echo "FAIL: luacheck reported $errors errors (rc=$rc)" >&2
  exit 1
fi

if [ "$warnings" -gt "$MAX_WARNINGS" ]; then
  echo "FAIL: luacheck warnings regression: $warnings > MAX_WARNINGS ($MAX_WARNINGS)" >&2
  exit 1
fi

echo "OK: $warnings/$MAX_WARNINGS warnings, $errors errors across ${#files[@]} files"
