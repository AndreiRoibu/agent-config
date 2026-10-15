#!/usr/bin/env bash
# PostToolUse hook — GLOBAL. Checks the Markdown a file edit produced against
# the writing rules in AGENTS.md that a script can check, and feeds the findings
# back to the agent so it fixes them in the same turn:
#   - no semicolon, and no dash that joins clauses
#   - at most 25 words in a sentence, and 20 in a numbered step
#   - at most six sentences in a paragraph or list item
# Fenced code, inline code, headings, tables, HTML, link targets and front
# matter are not prose and are skipped. The file is never edited.
#
# Runs under Claude Code (Edit and Write, matcher "Edit|Write") and under Codex
# (apply_patch, matcher "apply_patch"), which sends the patch text instead of a
# file name.
#
# Contract:
#   - stdin: hook JSON. Claude Code names the file at .tool_input.file_path.
#     Codex sends an apply_patch body in .tool_input.command, whose
#     "*** Add File:" and "*** Update File:" lines name the files, relative
#     to .cwd
#   - acts only on *.md files that exist inside a git repository, outside any
#     .claude directory, and are not rule files (AGENTS.md, CLAUDE.md), so
#     memory notes, scratch files and the rules themselves never trigger it
#   - an Edit or an Update File reports only the blocks that contain text from
#     that edit, so older problems elsewhere in the file are left alone. A
#     Write or an Add File reports the whole file
#   - findings -> one per line on stderr, exit 2. Both tools show them to the
#     agent as feedback on the edit, which has already happened
#   - nothing to check, or no python3 -> exit 0, silent
set -uo pipefail

command -v python3 >/dev/null 2>&1 || exit 0

HOOK_INPUT="$(cat)" python3 -I - <<'PY'
"""Check the Markdown an edit produced against the writing rules a script can check.

The hook JSON arrives in HOOK_INPUT. Each file is split into blocks, meaning
paragraphs and list items with their wrapped lines joined. Fenced code,
headings, tables, HTML, link definitions and front matter are not prose, so
they are skipped. Inline code, link targets, URLs and parentheses count as one
word each, as the STE word count does. Findings name the line where the block
starts.
"""
import html
import json
import os
import re
import subprocess
import sys

SENTENCE_LIMIT = 25
STEP_LIMIT = 20
PARAGRAPH_LIMIT = 6
MAX_FINDINGS = 20
RULE_FILES = {"AGENTS.md", "CLAUDE.md", "CLAUDE.local.md"}

FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})")
LIST = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+")
STEP = re.compile(r"^\s*\d+[.)]\s+")
HEADING = re.compile(r"^ {0,3}#")
SETEXT = re.compile(r"^ {0,3}(=+|-{2,})\s*$")
HORIZONTAL_RULE = re.compile(r"^ {0,3}([-*_])(\s*\1){2,}\s*$")
TABLE_ROW = re.compile(r"^\s*\|")
TABLE_SEPARATOR = re.compile(r"^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$")
LINK_DEFINITION = re.compile(r"^ {0,3}\[[^\]]+\]:\s*\S+")
LINK_TITLE = re.compile(r"""^\s+["'(].*["')]\s*$""")
HTML_BLOCK = re.compile(r"^ {0,3}</?[A-Za-z][A-Za-z0-9-]*(?:\s|/?>|$)")
ABBREVIATION = re.compile(r"\b(?i:e\.g|i\.e|etc|vs|cf|approx|et al|Fig|No)\.(?=\s+[0-9a-z])")
DASH = re.compile(r"\u2014|(?<!\d)\u2013|\u2013(?!\d)|\s--?\s")


def blocks_of(lines):
    """Split Markdown lines into (kind, first line number, text) prose blocks."""
    blocks = []
    state = {"kind": None, "start": 0, "parts": []}

    def close():
        if state["kind"] is not None and state["parts"]:
            blocks.append((state["kind"], state["start"], " ".join(state["parts"])))
        state["kind"], state["parts"] = None, []

    def discard():
        state["kind"], state["parts"] = None, []

    first = 0
    if lines and lines[0].strip() == "---":
        for index in range(1, len(lines)):
            if lines[index].strip() == "---":
                first = index + 1
                break

    fence = None
    in_comment = in_html = in_table = after_definition = False
    for number in range(first, len(lines)):
        line = re.sub(r"^ {0,3}>\s?", "", lines[number])
        opening = FENCE.match(line)
        if fence is None and opening:
            fence = opening.group(1)
            close()
            continue
        if fence is not None:
            closing = FENCE.match(line)
            if closing and closing.group(1)[0] == fence[0] and len(closing.group(1)) >= len(fence) and line.strip() == closing.group(1):
                fence = None
            continue
        line = re.sub(r"<!--.*?-->", " ", line)
        if in_comment:
            if "-->" not in line:
                continue
            line = line.split("-->", 1)[1]
            in_comment = False
        if "<!--" in line:
            line = line.split("<!--", 1)[0]
            in_comment = True
        if not line.strip():
            close()
            in_html = in_table = after_definition = False
            continue
        if in_html or in_table:
            continue
        if after_definition and LINK_TITLE.match(line):
            continue
        after_definition = False
        if SETEXT.match(line) and state["kind"] == "paragraph" and len(state["parts"]) == 1:
            discard()
            continue
        if TABLE_SEPARATOR.match(line) and state["kind"] == "paragraph" and len(state["parts"]) == 1:
            discard()
            in_table = True
            continue
        if TABLE_ROW.match(line):
            close()
            in_table = True
            continue
        if HTML_BLOCK.match(line):
            close()
            in_html = True
            continue
        if LINK_DEFINITION.match(line):
            close()
            after_definition = True
            continue
        if HEADING.match(line) or HORIZONTAL_RULE.match(line) or SETEXT.match(line):
            close()
            continue
        marker = LIST.match(line)
        if marker:
            close()
            state["kind"] = "step" if STEP.match(line) else "item"
            state["start"], state["parts"] = number + 1, [line[marker.end():].strip()]
            continue
        if state["kind"] is None:
            state["kind"], state["start"], state["parts"] = "paragraph", number + 1, [line.strip()]
        else:
            state["parts"].append(line.strip())
    close()
    return blocks


def strip_markup(text):
    """Remove the Markdown and HTML a reader does not see, keeping every word and mark they do."""
    text = re.sub(r"(`+)(?:(?!\1).)+?\1", " CODE ", text)
    text = re.sub(r"!\[([^\]]*)\]\([^)]*\)", r" \1 ", text)
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r" \1 ", text)
    text = re.sub(r"\[([^\]]*)\]\[[^\]]*\]", r" \1 ", text)
    text = re.sub(r"<(?:https?://|mailto:|[^\s@<>]+@)[^<>\s]*>", " URL ", text)
    text = re.sub(r"</?[A-Za-z][A-Za-z0-9-]*(?:\s[^<>]*)?/?>", " ", text)
    text = re.sub(r"https?://\S+|www\.\S+", " URL ", text)
    text = html.unescape(text)
    text = text.replace("*", "")
    return re.sub(r"\s+", " ", text).strip()


def sentences(text):
    """Split prose into sentences, with parentheticals as one word and abbreviations kept whole."""
    text = re.sub(r"\([^()]*\)", " PAREN ", text)
    text = ABBREVIATION.sub(lambda match: match.group(0).replace(".", "\u2024"), text)
    text = re.sub(r"(\d)\.(\d)", "\\1\u2024\\2", text)
    pieces = re.split(r"(?<=[.!?])[\"')\]]*\s+(?=[^a-z])", text)
    return [piece.strip() for piece in pieces if piece.strip()]


def words(sentence):
    """Count the tokens that carry a letter or digit in any script, so punctuation is free."""
    return [token for token in sentence.split() if re.search(r"\w", token)]


def touched(block_text, changed):
    """Whether the edit's text appears in this block. None means the whole file is new."""
    if changed is None:
        return True
    for line in changed.splitlines():
        line = re.sub(r"^ {0,3}>\s?", "", line)
        line = LIST.sub("", line).strip()
        if len(line) >= 3 and line in block_text:
            return True
    return False


def check(path, changed):
    """Return the findings for one file, limited to the blocks the edit touched."""
    with open(path, encoding="utf-8", errors="replace") as handle:
        lines = handle.read().split("\n")
    findings = []
    for kind, line_number, text in blocks_of(lines):
        if not touched(text, changed):
            continue
        prose = strip_markup(text)
        where = f"{path}:{line_number}:"
        if ";" in prose:
            findings.append(f'{where} semicolon in prose. Use a full stop, or a joining word such as "and", "so" or "because".')
        if DASH.search(prose):
            findings.append(f"{where} dash joins clauses. Use a comma, a full stop or a joining word.")
        found = sentences(prose)
        limit = STEP_LIMIT if kind == "step" else SENTENCE_LIMIT
        for sentence in found:
            count = len(words(sentence))
            if count > limit:
                scope = " in a numbered step" if kind == "step" else ""
                findings.append(f'{where} sentence of {count} words, limit {limit}{scope}: "{sentence[:70]}"')
        if len(found) > PARAGRAPH_LIMIT:
            findings.append(f"{where} paragraph of {len(found)} sentences, limit {PARAGRAPH_LIMIT}. Split it by topic.")
    return findings


def targets(tool_input, cwd):
    """Yield (path, changed text) for each file the edit touched. None means the whole file."""
    path = tool_input.get("file_path")
    if path:
        changed = tool_input.get("new_string") if "old_string" in tool_input else None
        yield os.path.normpath(os.path.join(cwd, path)), changed
        return
    patch = tool_input.get("command") or ""
    if "*** Begin Patch" not in patch:
        return
    files, current = [], None
    for line in patch.splitlines():
        header = re.match(r"\*\*\* (Add|Update|Delete) File: (.+)", line)
        if header:
            current = None
            if header.group(1) != "Delete":
                current = [os.path.normpath(os.path.join(cwd, header.group(2).strip())), [], header.group(1) == "Add"]
                files.append(current)
        elif current is not None and line.startswith("+"):
            current[1].append(line[1:])
    for path, added, whole in files:
        yield path, None if whole else "\n".join(added)


def eligible(path):
    """Whether the hook checks this file at all. See the contract in the header."""
    if not path.endswith(".md") or os.path.basename(path) in RULE_FILES:
        return False
    if "/.claude/" in path or not os.path.isfile(path):
        return False
    try:
        subprocess.run(["git", "-C", os.path.dirname(path), "rev-parse", "--show-toplevel"], check=True, capture_output=True)
    except (OSError, subprocess.CalledProcessError):
        return False
    return True


try:
    hook = json.loads(os.environ.get("HOOK_INPUT") or "{}")
except ValueError:
    sys.exit(0)
tool_input = hook.get("tool_input") or {}
cwd = hook.get("cwd") or os.getcwd()

findings = []
for path, changed in targets(tool_input, cwd):
    if eligible(path):
        findings.extend(check(path, changed))

if findings:
    for finding in findings[:MAX_FINDINGS]:
        print(finding, file=sys.stderr)
    if len(findings) > MAX_FINDINGS:
        print(f"... and {len(findings) - MAX_FINDINGS} more", file=sys.stderr)
    print("These are the writing rules in AGENTS.md. Fix them in the file you just edited.", file=sys.stderr)
    sys.exit(2)
PY
exit $?
