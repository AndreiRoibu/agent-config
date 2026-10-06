#!/usr/bin/env bash
# PreToolUse hook (Bash): defense-in-depth backstop that blocks ONLY genuinely
# catastrophic commands. It is not the primary guard (normal permission prompts
# are) and deliberately errs towards allowing: anything not clearly catastrophic
# passes through.
#
# Blocks: recursive rm of `/`, `/*`, `~`, `~/`, `$HOME`, or a bare top-level
# system dir; `rm --no-preserve-root`; a classic fork bomb; `mkfs`; and `dd`
# writing to a raw `/dev/` device.
# Allows: project-relative cleanup the justfile relies on (rm -rf dist,
# __pycache__, ./path) and removals of deep paths under those roots.
#
# Contract:
#   - stdin: hook JSON; the command is at .tool_input.command
#   - catastrophic match -> message on stderr, exit 2 (blocks the tool call)
#   - otherwise          -> exit 0 (allow)
set -uo pipefail

cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$cmd" ] && exit 0

# Collapse runs of whitespace so flag/target matching is position-independent.
norm="$(printf '%s' "$cmd" | tr -s '[:space:]' ' ')"

block() { printf 'BLOCKED by catastrophic-command backstop: %s\n' "$1" >&2; exit 2; }

# rm (with any flags) whose target is a bare root/home location.
if printf '%s' "$norm" \
  | grep -Eq 'rm[[:space:]]+(-[^[:space:]]+[[:space:]]+)*(/\*|/|~/|~|\$HOME)([[:space:]]|$)'; then
  block "recursive rm of / or \$HOME"
fi
# rm whose target is a bare top-level system directory (or its /* glob).
if printf '%s' "$norm" \
  | grep -Eq 'rm[[:space:]]+(-[^[:space:]]+[[:space:]]+)*/(etc|usr|bin|sbin|lib|lib64|var|boot|root|home|sys|proc|dev|opt)([[:space:]]|/\*|$)'; then
  block "rm of a top-level system directory"
fi
printf '%s' "$norm" | grep -Eq 'rm[[:space:]].*--no-preserve-root' && block "rm --no-preserve-root"
printf '%s' "$norm" | grep -Eq ':\(\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;\s*:' && block "fork bomb"
printf '%s' "$norm" | grep -Eq '(^| )mkfs([. ]|$)' && block "mkfs (filesystem format)"
printf '%s' "$norm" | grep -Eq 'dd[[:space:]].*of=/dev/' && block "dd writing to a raw /dev/ device"

exit 0
