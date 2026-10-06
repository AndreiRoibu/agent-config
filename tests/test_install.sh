#!/usr/bin/env bash
# Tests install.sh against throwaway home directories, so the real ~/.claude and
# ~/.codex are never touched. Run it from anywhere with ./tests/test_install.sh.
#
# Each case copies this repository to <fake home>/agent-config, because
# install.sh refuses to run from any other location.
set -uo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
homes=()
failures=0
trap 'rm -rf "${homes[@]}"' EXIT

# Creates a fake home holding a copy of this repository and the named tool
# directories, and prints its path.
new_home() {
  local home
  home="$(mktemp -d)"
  homes+=("$home")
  mkdir -p "$home/agent-config"
  tar -C "$src" --exclude=.git -cf - . | tar -C "$home/agent-config" -xf -
  for tool in "$@"; do mkdir -p "$home/$tool"; done
  printf '%s\n' "$home"
}

install_in() { HOME="$1" bash "$1/agent-config/install.sh"; }

check() {
  local name="$1"
  shift
  if "$@"; then
    echo "ok   $name"
  else
    echo "FAIL $name"
    failures=$((failures + 1))
  fi
}

links_to() { [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ]; }
plain_copy_of() { [ -f "$1" ] && [ ! -L "$1" ] && cmp -s "$1" "$2"; }
no_backup() { [ ! -e "$1/.agent-config-backup" ]; }
backed_up() { find "$1/.agent-config-backup" -path "*/$2" -print -quit 2>/dev/null | grep -q .; }

# Missing state: both tools present, nothing installed yet.
home="$(new_home .claude .codex)"
repo="$(cd "$home/agent-config" && pwd -P)"
install_in "$home" >/dev/null
check "links CLAUDE.md" links_to "$home/.claude/CLAUDE.md" "$repo/CLAUDE.md"
check "links every hook" links_to "$home/.claude/hooks/stop-checks.sh" "$repo/claude/hooks/stop-checks.sh"
check "links Codex AGENTS.md" links_to "$home/.codex/AGENTS.md" "$repo/AGENTS.md"
check "copies guard.rules, because Codex skips linked rule files" \
  plain_copy_of "$home/.codex/rules/guard.rules" "$repo/codex/guard.rules"
check "makes no backup when nothing was in the way" no_backup "$home"

# Correct state: a second run changes nothing and says nothing.
out="$(install_in "$home")"
check "rerun is silent" [ -z "$out" ]
check "rerun makes no backup" no_backup "$home"

# Broken state: an old file, a dangling link, a stale copy and a linked rule file.
home="$(new_home .claude .codex)"
repo="$(cd "$home/agent-config" && pwd -P)"
mkdir -p "$home/.claude/hooks" "$home/.codex/rules"
echo old >"$home/.claude/CLAUDE.md"
ln -s "$home/nowhere" "$home/.codex/AGENTS.md"
echo stale >"$home/.claude/hooks/ruff-format.sh"
ln -s "$repo/codex/guard.rules" "$home/.codex/rules/guard.rules"
install_in "$home" >/dev/null
check "replaces an old file with a link" links_to "$home/.claude/CLAUDE.md" "$repo/CLAUDE.md"
check "backs up the old file" backed_up "$home" ".claude/CLAUDE.md"
check "replaces a dangling link" links_to "$home/.codex/AGENTS.md" "$repo/AGENTS.md"
check "backs up the dangling link" backed_up "$home" ".codex/AGENTS.md"
check "replaces a stale hook" links_to "$home/.claude/hooks/ruff-format.sh" "$repo/claude/hooks/ruff-format.sh"
check "turns a linked rule file into a copy" \
  plain_copy_of "$home/.codex/rules/guard.rules" "$repo/codex/guard.rules"

# A tool that is not installed is skipped, and nothing is created for it.
home="$(new_home .claude)"
out="$(install_in "$home")"
check "skips Codex when ~/.codex is missing" [ ! -e "$home/.codex" ]
check "says Codex was skipped" grep -q "skipped Codex" <<<"$out"

# Wrong location: CLAUDE.md imports ~/agent-config/AGENTS.md, so refuse.
home="$(new_home .claude .codex)"
mv "$home/agent-config" "$home/elsewhere"
err="$(HOME="$home" bash "$home/elsewhere/install.sh" 2>&1 >/dev/null)"
status=$?
check "refuses to run outside ~/agent-config" [ "$status" -ne 0 ]
check "explains where to clone" grep -q "clone this repository to ~/agent-config" <<<"$err"
check "installs nothing when it refuses" [ ! -e "$home/.claude/CLAUDE.md" ]

if [ "$failures" -ne 0 ]; then
  echo "$failures failed"
  exit 1
fi
echo "all passed"
