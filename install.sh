#!/usr/bin/env bash
# Installs this repository's agent configuration into ~/.claude and ~/.codex.
#
# Rule files and hooks become links, so an edit here takes effect in the next
# session. codex/guard.rules is copied instead, because Codex skips links when
# it lists ~/.codex/rules/. settings.json and config.toml are left alone,
# because the tools write to them (see README.md).
#
# Safe to rerun. A correct link or an identical copy is left as it is. Anything
# else in the way is moved to ~/.agent-config-backup/<time>/ first. A tool whose
# home directory does not exist yet is skipped with a note.
set -euo pipefail
shopt -s nullglob

# Checked first, before any other tool runs. The hooks read their input with
# jq, and without it the safety hook silently lets every command through.
if ! command -v jq >/dev/null 2>&1; then
  echo "error: install jq first, because the Claude Code hooks need it (without it the safety hook allows every command)" >&2
  exit 1
fi

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
expected="$(cd "$HOME" && pwd -P)/agent-config"
if [ "$repo" != "$expected" ]; then
  echo "error: clone this repository to ~/agent-config, because CLAUDE.md imports ~/agent-config/AGENTS.md (it is at $repo)" >&2
  exit 1
fi

backup="$HOME/.agent-config-backup/$(date +%Y%m%d-%H%M%S)"

# Moves whatever is at $1 into the backup folder, keeping its path under $HOME.
move_aside() {
  local rel="${1#"$HOME"/}"
  mkdir -p "$backup/$(dirname "$rel")"
  mv "$1" "$backup/$rel"
  echo "backed up $1"
}

# Makes $2 a link to the repository file $1.
link() {
  local source="$repo/$1" target="$2"
  if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
    return 0
  fi
  if [ -e "$target" ] || [ -L "$target" ]; then
    move_aside "$target"
  fi
  mkdir -p "$(dirname "$target")"
  ln -s "$source" "$target"
  echo "linked $target"
}

# Makes $2 a plain copy of the repository file $1.
copy() {
  local source="$repo/$1" target="$2"
  if [ -f "$target" ] && [ ! -L "$target" ] && cmp -s "$source" "$target"; then
    return 0
  fi
  if [ -e "$target" ] || [ -L "$target" ]; then
    move_aside "$target"
  fi
  mkdir -p "$(dirname "$target")"
  cp "$source" "$target"
  echo "copied $target"
}

if [ -d "$HOME/.claude" ]; then
  link CLAUDE.md "$HOME/.claude/CLAUDE.md"
  for hook in "$repo"/claude/hooks/*.sh; do
    link "claude/hooks/${hook##*/}" "$HOME/.claude/hooks/${hook##*/}"
  done
else
  echo "skipped Claude Code, because ~/.claude does not exist yet"
fi

if [ -d "$HOME/.codex" ]; then
  link AGENTS.md "$HOME/.codex/AGENTS.md"
  copy codex/guard.rules "$HOME/.codex/rules/guard.rules"
else
  echo "skipped Codex, because ~/.codex does not exist yet"
fi
