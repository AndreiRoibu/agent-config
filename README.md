# Agent configuration

My user-level instructions and settings for Claude Code and Codex. They hold no
company or repository facts, so they work in any repository and on any machine.
Repository facts belong in each repository's own `AGENTS.md`.

## Set up a machine

1. Clone this repository to `~/agent-config`. `CLAUDE.md` imports
   `~/agent-config/AGENTS.md`, so it must live there.
2. Run Claude Code and Codex once each, so that `~/.claude` and `~/.codex`
   exist.
3. Run `./install.sh`. It moves anything it replaces into
   `~/.agent-config-backup/<time>/` and is safe to rerun.
4. Apply the settings templates as described below.
5. Check the result. In Claude Code, run `/memory`, `/hooks` and
   `/permissions`. In Codex, ask it to quote a rule from `AGENTS.md`.

## Change a rule

1. Edit the file here. Linked files take effect in the next session.
2. After editing `codex/guard.rules`, rerun `./install.sh`, because Codex needs
   a copy of that file.
3. Run `./tests/test_install.sh` after changing `install.sh`.
4. Commit and push from here.

## Apply the settings templates

Claude Code and Codex write to their settings files themselves, so those stay
plain files on each machine and the copies here are templates.

For Claude Code, this keeps the machine's extra directories and takes
everything else from the template.

```bash
tmp="$(mktemp)"
jq --slurpfile live ~/.claude/settings.json \
  '.permissions.additionalDirectories = ($live[0].permissions.additionalDirectories // [])' \
  claude/settings.json >"$tmp" && chmod 644 "$tmp" && mv "$tmp" ~/.claude/settings.json
```

For Codex, copy the top-level keys and the `[features]` and `[plugins]` tables
from `codex/config.toml` by hand. Keep the machine's `[projects]` entries, and
trust single repositories, never the whole home directory.

## What goes where

| File here | Live location | How |
| --- | --- | --- |
| `AGENTS.md` | `~/.codex/AGENTS.md` | link |
| `CLAUDE.md` | `~/.claude/CLAUDE.md` | link, imports `AGENTS.md` from here |
| `claude/hooks/*.sh` | `~/.claude/hooks/` | one link per file |
| `codex/guard.rules` | `~/.codex/rules/guard.rules` | copy |
| `claude/settings.json` | `~/.claude/settings.json` | template |
| `codex/config.toml` | `~/.codex/config.toml` | template |
| `routines.md` | none | paste into scheduled routines |

## Claude Code hooks

All three run in every repository.

| Hook | When | What it does |
| --- | --- | --- |
| `block-catastrophic-bash.sh` | Before every shell command | Blocks only catastrophic commands (`rm -rf /` or `~`, system directories, `mkfs`, `dd` to a device, fork bomb). Everything else passes. |
| `ruff-format.sh` | After every file edit | Runs `ruff check --fix` and `ruff format` on an edited Python file, using the repository's own `.venv` ruff when present. |
| `stop-checks.sh` | When a turn ends | Runs `<repo>/.claude/checks.sh` if the repository provides one, and is silent otherwise. |

`ruff-format.sh` reformats the whole edited file, so in a repository whose files
are not already ruff-formatted it adds unrelated formatting changes to the diff.

## Why it is shaped this way

- **Some files are copies or templates, not links.** Codex skips links when it
  lists `~/.codex/rules/`, because it checks each entry's own type
  (`collect_policy_files` in
  [`codex-rs/core/src/exec_policy.rs`](https://github.com/openai/codex/blob/main/codex-rs/core/src/exec_policy.rs)).
  The settings files are written by the tools, for example when you approve a
  command or trust a project. As links, those writes would land here, and some
  tools save by replacing a file, which breaks a link.
- **`CLAUDE.md` only imports `AGENTS.md`.** Codex, Copilot and Cursor read
  `AGENTS.md`, so one file serves every tool.
- **The instruction files hold rules only.** They are loaded into every
  session, so the reasoning lives here instead.
- **Git commands ask first in both tools.** `claude/settings.json` lists them
  under `ask` and `codex/guard.rules` marks them `prompt`, which backs the
  **Git** rules in `AGENTS.md`.
