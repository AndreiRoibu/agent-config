#!/usr/bin/env bash
# Tests claude/hooks/prose-check.sh on throwaway Markdown files inside a scratch
# git repository, because the hook skips files outside one. Run it from anywhere
# with ./tests/test_prose_check.sh.
set -uo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
hook="$src/claude/hooks/prose-check.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

repo="$work/repo"
mkdir -p "$repo/.claude"
git -C "$repo" init -q

# Runs the hook on hook JSON as a tool would send it, and keeps the findings
# and the exit status in $out and $status.
run_json() {
  out="$(printf '%s' "$1" | bash "$hook" 2>&1)"
  status=$?
}

# Runs the hook on a path as Claude Code's Write tool reports it.
run_hook() { run_json "{\"tool_input\":{\"file_path\":\"$1\"}}"; }

# Writes the text to the file, then runs the hook on it as a Write.
try() {
  printf '%b' "$2" >"$1"
  run_hook "$1"
}

# Writes the text to the file, then runs the hook as an Edit whose new text is $3.
try_edit() {
  printf '%b' "$2" >"$1"
  run_json "{\"tool_input\":{\"file_path\":\"$1\",\"old_string\":\"x\",\"new_string\":\"$3\"}}"
}

# Writes the text to the file, then runs the hook as Codex's apply_patch with
# the given patch body, relative to the repository.
try_patch() {
  printf '%b' "$2" >"$1"
  run_json "{\"tool_input\":{\"command\":\"$3\"},\"cwd\":\"$repo\"}"
}

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

passes() { [ "$status" -eq 0 ] && [ -z "$out" ]; }
flags() { [ "$status" -eq 2 ] && grep -q -- "$1" <<<"$out"; }

twenty_five="$(seq -s ' ' 1 25)."
twenty_six="$(seq -s ' ' 1 26)."
twenty="$(seq -s ' ' 1 20)."
twenty_one="$(seq -s ' ' 1 21)."

# Clean prose passes silently, at the limits included.
try "$repo/clean.md" "# Title\n\nShort sentence. $twenty_five\n\n- $twenty_five\n\n1. $twenty\n"
check "clean file passes" passes

# The rules a script can check are reported with the block's line number.
try "$repo/semicolon.md" "Fine line.\n\nOne clause; another clause.\n"
check "flags a semicolon" flags "semicolon"
check "names the line" grep -q "semicolon.md:3:" <<<"$out"
try "$repo/dash.md" "A clause \xe2\x80\x94 another clause.\n"
check "flags an em dash" flags "dash joins clauses"
try "$repo/endash.md" "A clause \xe2\x80\x93 another clause.\n"
check "flags a spaced en dash" flags "dash joins clauses"
try "$repo/range.md" "Read pages 10\xe2\x80\x9312 first.\n"
check "allows an en dash in a number range" passes
try "$repo/spaced.md" "A clause - another clause.\n"
check "flags a spaced hyphen used as a dash" flags "dash joins clauses"
try "$repo/long.md" "$twenty_six\n"
check "flags a sentence over 25 words" flags "sentence of 26 words, limit 25"
try "$repo/step.md" "1. $twenty_one\n"
check "flags a numbered step over 20 words" flags "limit 20 in a numbered step"
try "$repo/bullet.md" "- $twenty_one\n"
check "allows 21 words in a bullet" passes
try "$repo/wrapped.md" "1. $(seq -s ' ' 1 11)\n   $(seq -s ' ' 12 21).\n"
check "joins the wrapped lines of a step" flags "sentence of 21 words"
try "$repo/paragraph.md" "One. Two. Three. Four. Five. Six. Seven.\n"
check "flags a paragraph of seven sentences" flags "paragraph of 7 sentences"
try "$repo/six.md" "One. Two. Three. Four. Five. Six.\n"
check "allows six sentences" passes
try "$repo/item.md" "- One. Two. Three. Four. Five. Six. Seven.\n"
check "flags a list item of seven sentences" flags "paragraph of 7 sentences"
try "$repo/cyrillic.md" "$(printf 'слово %.0s' $(seq 1 26)).\n"
check "counts words in other scripts" flags "sentence of 26 words"

# Punctuation hidden in brackets or entities still counts.
try "$repo/bracket.md" "Use the option (it is fast; it is unsafe).\n"
check "flags a semicolon inside brackets" flags "semicolon"
try "$repo/bracketwords.md" "$(seq -s ' ' 1 24) (one two three four five six seven).\n"
check "counts a bracketed phrase as one word" passes
try "$repo/entity.md" "One clause&semi; another clause.\n"
check "decodes an HTML entity" flags "semicolon"
try "$repo/compare.md" "If x < y; use z > now.\n"
check "keeps text between angle brackets" flags "semicolon"

# Sentence ends: abbreviations end a sentence before a capital, not before a number.
try "$repo/etc.md" "One. Two. Three. Four. Five. Six, etc. Seven.\n"
check "lets etc. end a sentence" flags "paragraph of 7 sentences"
try "$repo/fig.md" "See Fig. 3 now. Two. Three. Four. Five. Six.\n"
check "keeps Fig. 3 together" passes

# Code, tables, headings, links and HTML are not prose.
try "$repo/fence.md" "Text.\n\n\`\`\`\na; b\nc; d\n\`\`\`\n"
check "skips fenced code" passes
try "$repo/nested.md" "\`\`\`\`markdown\n\`\`\`\nfirst; second\n\`\`\`\n\`\`\`\`\n"
check "keeps a fence open until a matching closer" passes
try "$repo/inline.md" "Use \`a; b\` here.\n"
check "skips inline code" passes
try "$repo/double.md" "Use \`\`first; \`second\` \`\` here.\n"
check "skips a double-backtick code span" passes
try "$repo/table.md" "| a; b | c |\n| --- | --- |\n| d; e | f |\n"
check "skips tables" passes
try "$repo/pipeless.md" "Name | Meaning\n--- | ---\nalpha | first; second\n"
check "skips tables without leading pipes" passes
try "$repo/setext.md" "$(seq -s ' ' 1 26)\n===\n\nFine.\n"
check "skips a setext heading" passes
try "$repo/link.md" "See [the guide](https://example.com/a/very/long/path/with/many/segments) for details.\n"
check "counts a link as its text" passes
try "$repo/definition.md" "[x]: https://example.com\n    \"internal; title\"\n"
check "skips a link definition and its title line" passes
try "$repo/html.md" "<div>\nfirst; second\n</div>\n"
check "skips an HTML block" passes
try "$repo/comment.md" "<!-- hidden\nhidden --> One clause; another clause.\n"
check "checks prose after a closing comment" flags "semicolon"

# An Edit reports only the blocks it touched. A Write reports the whole file.
legacy="Old clause; still here.\n\nNew paragraph that is clean.\n"
try_edit "$repo/edit.md" "$legacy" "New paragraph that is clean."
check "an edit leaves older problems alone" passes
try_edit "$repo/edit2.md" "$legacy" "Old clause; still here."
check "an edit reports the block it touched" flags "semicolon"
try "$repo/write.md" "$legacy"
check "a write reports the whole file" flags "semicolon"

# Codex sends an apply_patch body instead of a file name.
try_patch "$repo/added.md" "One clause; another.\n" \
  '*** Begin Patch\n*** Add File: added.md\n+One clause; another.\n*** End Patch'
check "checks a file added by apply_patch" flags "semicolon"
try_patch "$repo/updated.md" "$legacy" \
  '*** Begin Patch\n*** Update File: updated.md\n@@\n+New paragraph that is clean.\n*** End Patch'
check "an apply_patch update leaves older problems alone" passes
try_patch "$repo/updated2.md" "$legacy" \
  '*** Begin Patch\n*** Update File: updated2.md\n@@\n+Old clause; still here.\n*** End Patch'
check "an apply_patch update reports the block it touched" flags "semicolon"
run_json "{\"tool_input\":{\"command\":\"ls\"},\"cwd\":\"$repo\"}"
check "ignores a shell command" passes

# Files the hook must leave alone.
try "$repo/code.py" "a; b\n"
check "ignores a non-Markdown file" passes
try "$repo/.claude/notes.md" "One clause; another.\n"
check "ignores files under .claude" passes
try "$repo/AGENTS.md" "One clause; another.\n"
check "ignores rule files" passes
mkdir -p "$work/loose"
try "$work/loose/notes.md" "One clause; another.\n"
check "ignores files outside a git repository" passes
run_hook "$repo/missing.md"
check "ignores a missing file" passes
run_json "not json"
check "ignores input that is not JSON" passes

# Without python3 the check is skipped, never a crash.
mkdir -p "$work/bin"
for tool in git; do ln -s "$(command -v "$tool")" "$work/bin/$tool"; done
printf 'One clause; another.\n' >"$repo/nopython.md"
out="$(printf '{"tool_input":{"file_path":"%s"}}' "$repo/nopython.md" | PATH="$work/bin" "$BASH" "$hook" 2>&1)"
status=$?
check "skips the check without python3" passes

if [ "$failures" -ne 0 ]; then
  echo "$failures failed"
  exit 1
fi
echo "all passed"
