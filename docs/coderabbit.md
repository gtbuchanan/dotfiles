# CodeRabbit

CodeRabbit ships in two pieces in this repo: the **CLI** (`coderabbit`,
a native Linux/macOS binary) and the **Claude Code plugin**
(`coderabbit@claude-plugins-official`, which provides the
`coderabbit:coderabbit-review` and `coderabbit:autofix` skills). The
CLI has no native Windows build, so the Windows install routes through
WSL via thin wrappers that also paper over a worktree-detection gap
upstream.

## File Map

| File | Role |
|---|---|
| `home/.chezmoiscripts/linux/run_onchange_after_coderabbit-install.sh` | Native CLI install via `cli.coderabbit.ai/install.sh` (runs inside WSL on Windows) |
| `home/.chezmoiscripts/windows/run_onchange_after_claude-configure.ps1.tmpl` | `claude plugin install coderabbit` (Windows-only, alongside the LSP plugins) |
| `home/.chezmoiignore` | Gates the Windows-only WSL wrappers off non-Windows hosts |
| `home/dot_claude/settings.json.tmpl` | Enables `coderabbit@claude-plugins-official` |
| `home/dot_local/bin/coderabbit` | Git Bash wrapper: forwards to WSL with `GIT_DIR`/`GIT_WORK_TREE` translation |
| `home/dot_local/bin/coderabbit.bat` | cmd.exe wrapper: same translation for non-Bash callers |

## CLI Install

On Linux and macOS the install script runs upstream's installer, which
drops a native binary into `~/.local/bin/`. On Windows the same script
runs **inside WSL** — it lives under `.chezmoiscripts/linux/`, which
only fires on Linux hosts, and the WSL distro counts. The Windows side
never gets a native binary; the wrappers below forward into WSL
instead.

## Windows Wrappers

CodeRabbit has no native Windows build, so callers on the Windows side
need to cross into WSL to reach the binary. One wrapper covers Git Bash
callers, one covers cmd.exe / PowerShell. Both solve the same two
problems before handing off to `wsl`:

- **Worktree detection.** The CLI doesn't follow the `.git` *file*
  that linked worktrees use in place of a `.git` *directory*, so it
  can't locate the real gitdir from inside a worktree on its own. The
  wrappers resolve the worktree and gitdir on the Windows side via
  `git rev-parse` and pass them in as env vars so the CLI uses them
  verbatim. The Bash wrapper also normalizes MSYS-style paths
  (`/c/Users/...`) to Windows form before exporting them, since the
  next step expects Windows paths.
- **Path translation across the WSL boundary.** WSL's `WSLENV`
  mechanism rewrites the exported paths from Windows form to Linux
  form when the child process starts inside WSL.

The wrappers are gated off non-Windows hosts in `.chezmoiignore`
(`.local/bin/coderabbit` is excluded everywhere except Windows;
`**/*.bat*` is already excluded globally on non-Windows).

## Claude Code Plugin

Separate from the CLI, the `coderabbit` plugin from the official Claude
Code marketplace exposes two skills:

- `coderabbit:coderabbit-review` — runs a review pass on pending
  changes.
- `coderabbit:autofix` — surfaces existing review-thread feedback from
  GitHub and applies fixes with per-change approval.

The plugin is enabled in `home/dot_claude/settings.json.tmpl`. On
Windows it's installed by the `claude-configure` script, which calls
`claude plugin install coderabbit` alongside the LSP plugins (the
`claude plugin` CLI can't be driven from `settings.json`, so it has to
live in a `run_onchange` script — see [`claude-code.md`](claude-code.md)
for the wider picture).
