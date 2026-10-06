# Agent configuration

My user-level rules and settings for Claude Code and Codex. They hold no company
or repository facts, so they work in any repository and at any job. Repository
facts belong in that repository's own `AGENTS.md`.

Last checked in October 2026 with Claude Code 2.1 and Codex 0.160, on Linux.
macOS should work but has not been tried.

## Quick start on a new machine

1. Install `git`, `bash` and `jq` (`sudo apt install jq` or `brew install jq`).
   The hooks need `jq`, and without it the safety hook lets every command
   through, so `install.sh` refuses to run until it is there.
2. Give the account you will clone with access to this private repository. At
   a new job, follow [Start a new job](#start-a-new-job) first.
3. Run Claude Code and Codex once each, so that `~/.claude` and `~/.codex`
   exist. Skip Codex if you don't use it, and `install.sh` will skip it too.
4. Clone and install. The clone must be at `~/agent-config`, because
   `CLAUDE.md` imports `~/agent-config/AGENTS.md`.

   ```bash
   git clone git@github.com:AndreiRoibu/agent-config.git ~/agent-config
   cd ~/agent-config
   git config user.email "<your personal email>"
   ./install.sh
   ```

   Use `https://github.com/AndreiRoibu/agent-config.git` instead if the
   account has no SSH key. `install.sh` moves anything it replaces into
   `~/.agent-config-backup/<time>/` and is safe to rerun.
5. Apply the settings templates. See
   [Apply the settings templates](#apply-the-settings-templates).
6. Check the result. In Claude Code, run `/memory`, `/hooks` and
   `/permissions`. In Codex, ask it to quote a rule from `AGENTS.md`.

## How to

### Start a new job

1. Check the new employer's rules on keeping personal repositories on a work
   machine.
2. Signed in to GitHub as `AndreiRoibu`, open this repository's
   **Settings**, then **Collaborators**, and invite the new work account.
3. Signed in as the work account, accept the invite at
   https://github.com/AndreiRoibu/agent-config/invitations.
4. Follow the quick start. Keep company facts out of this repository, because
   it leaves with you.

### Leave a job

1. Commit and push any last edits from the work machine.
2. Signed in as `AndreiRoibu`, remove the work account under the repository's
   **Settings**, then **Collaborators**. Until you do, it can still push here.

### Change a rule

1. Edit the file here. Linked files take effect in the next session.
2. Run `./install.sh` again if you edited `codex/guard.rules`, because Codex
   needs a copy of that file.
3. Run `./tests/test_install.sh` if you changed `install.sh`. It uses
   throwaway home folders and never touches the real ones.
4. Commit and push.

### Update another machine

```bash
cd ~/agent-config && git pull && ./install.sh
```

### Apply the settings templates

Claude Code and Codex write to their settings files themselves, so those stay
plain files on each machine and the copies here are templates.

For Claude Code, run this from `~/agent-config`. It keeps the machine's extra
folders, takes everything else from the template, saves the old file as
`settings.json.bak`, and also works when the machine has no settings file yet.
It replaces the machine's list of always-allowed commands, so expect a few
permission prompts at first.

```bash
live=~/.claude/settings.json
[ -f "$live" ] || echo '{}' >"$live"
cp "$live" "$live.bak"
tmp="$(mktemp)"
jq --slurpfile live "$live" \
  '.permissions.additionalDirectories = ($live[0].permissions.additionalDirectories // [])' \
  claude/settings.json >"$tmp" && chmod 644 "$tmp" && mv "$tmp" "$live"
```

For Codex, if the machine has no `~/.codex/config.toml`, copy the template with
`cp codex/config.toml ~/.codex/config.toml`. Otherwise copy the top-level keys
and the `[features]` and `[plugins]` tables by hand. Keep the machine's
`[projects]` entries, and trust single repositories, never the whole home
folder.

### Fix a setting a tool rejects

The templates are a snapshot. Model names (`opus[1m]`, `gpt-6-sol`) and some
settings change between tool versions. For example, Codex 0.124 refuses to
start with `service_tier = "default"`, which Codex 0.160 accepts. If a tool
refuses to start or ignores a setting, check its current settings
documentation, fix the template here, apply it again, and commit.

### Undo

`install.sh` keeps whatever it replaced in `~/.agent-config-backup/<time>/`,
laid out like your home folder. To put a file back, remove the link first and
then copy. Never copy onto a link, because `cp` writes through it and
overwrites the file in this repository.

```bash
ls ~/.agent-config-backup/       # pick the <time> to restore
rm ~/.claude/CLAUDE.md           # removes only the link
cp ~/.agent-config-backup/<time>/.claude/CLAUDE.md ~/.claude/CLAUDE.md
```

To remove the setup completely, delete every link and copy listed in
[What goes where](#what-goes-where) the same way, then copy back what you need.

## Reference

### What goes where

| File here | Live location | How |
| --- | --- | --- |
| `AGENTS.md` | `~/.codex/AGENTS.md` | link |
| `CLAUDE.md` | `~/.claude/CLAUDE.md` | link, imports `AGENTS.md` from here |
| `claude/hooks/*.sh` | `~/.claude/hooks/` | one link per file |
| `codex/guard.rules` | `~/.codex/rules/guard.rules` | copy |
| `claude/settings.json` | `~/.claude/settings.json` | template |
| `codex/config.toml` | `~/.codex/config.toml` | template |
| `routines.md` | none | paste into scheduled routines |

### Claude Code hooks

All three run in every repository, and all three need `jq`.

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
  **Git** rules in `AGENTS.md`. The rules in `AGENTS.md` are requests the model
  usually follows, while these lists are enforced by the tool itself.
- **`routines.md` repeats some rules on purpose.** Scheduled routines run in
  the cloud and cannot see `~/.claude`, so they need their own copy.
