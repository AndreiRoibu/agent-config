#!/usr/bin/env bash
# Stop hook — GLOBAL. Runs the CURRENT repo's own fast-check script if it defines
# one at <repo>/.claude/checks.sh. Repos that don't opt in are silent, so ordinary
# turns are never slowed. Never blocks the stop; checks.sh output is informational.
#
# Convention: a repo opts in by adding an executable .claude/checks.sh that runs
# its fast checks and prints whatever it wants surfaced to the user. Each repo
# decides what "fast checks" means (e.g. `just pytest-smoke`, `npm test`).
#
# Contract:
#   - not in a repo, or no .claude/checks.sh -> exit 0, silent
#   - otherwise -> run it; if it printed anything, surface it via systemMessage
set -uo pipefail

repo="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
checks="$repo/.claude/checks.sh"
[ -x "$checks" ] || exit 0   # repo didn't opt in: stay silent

out="$("$checks" 2>&1)"      # exit status intentionally ignored: never block
[ -z "$out" ] && exit 0      # opted in but nothing to report

jq -n --arg m "$out" '{systemMessage: $m, suppressOutput: true}'
exit 0
