#!/usr/bin/env bash
# PostToolUse hook (Edit|Write) — GLOBAL. Fix + format a changed Python file with
# whatever ruff its OWN repo provides (the repo's .venv), else a ruff on PATH.
# No-ops on non-Python files or when no ruff is available. Never blocks; silent.
#
# Global-safe: the target repo is derived from the edited file's path, NOT from
# this script's location (it lives in ~/.claude/hooks/, not inside any repo).
#
# Contract:
#   - stdin: hook JSON; the edited path is at .tool_input.file_path
#   - only acts on *.py files that exist; everything else is a no-op
#   - ruff's own exit status is ignored so unfixable lint findings never block
set -uo pipefail

file="$(jq -r '.tool_input.file_path // empty' 2>/dev/null)"
[ -z "$file" ] && exit 0
case "$file" in
  *.py) ;;        # Python: continue
  *) exit 0 ;;    # anything else: nothing to do
esac
[ -f "$file" ] || exit 0

# Prefer the project venv's ruff (matches that repo's pinned version/config);
# fall back to a ruff on PATH; if neither exists, skip silently.
repo="$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null)"
ruff=""
if [ -n "$repo" ] && [ -x "$repo/.venv/bin/ruff" ]; then
  ruff="$repo/.venv/bin/ruff"
elif command -v ruff >/dev/null 2>&1; then
  ruff="$(command -v ruff)"
fi
[ -n "$ruff" ] || exit 0

"$ruff" check --fix "$file" >/dev/null 2>&1 || true
"$ruff" format "$file" >/dev/null 2>&1 || true
exit 0
