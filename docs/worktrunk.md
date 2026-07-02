# Worktrunk

[Worktrunk](https://worktrunk.dev)'s `wt` CLI replaces raw `git worktree`
across every platform this repo supports. This doc covers how the pieces
fit together; individual files document themselves. Agent-facing usage
rules live in [`home/dot_config/AGENTS.md.tmpl`](../home/dot_config/AGENTS.md.tmpl)
(`## Worktrees`) and [`home/dot_claude/CLAUDE.md.tmpl`](../home/dot_claude/CLAUDE.md.tmpl)
(`## Worktree Sessions`).

## File Map

| File                                                                                                                                          | Role                                               |
| --------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------- |
| [`home/.chezmoidata/wt.yaml`](../home/.chezmoidata/wt.yaml)                                                                                   | Pinned version (Renovate-tracked)                  |
| [`home/.chezmoiexternal.yaml.tmpl`](../home/.chezmoiexternal.yaml.tmpl)                                                                       | Skill archive → `~/.agents/skills/worktrunk/`      |
| [`home/.chezmoiscripts/android/run_onchange_after_install-wt.sh.tmpl`](../home/.chezmoiscripts/android/run_onchange_after_install-wt.sh.tmpl) | Termux manual install                              |
| [`home/.chezmoitemplates/worktrunk-config.toml`](../home/.chezmoitemplates/worktrunk-config.toml)                                             | Shared user-config template                        |
| [`home/AppData/Roaming/worktrunk/config.toml.tmpl`](../home/AppData/Roaming/worktrunk/config.toml.tmpl)                                       | Renders shared config on Windows (`%APPDATA%`)     |
| [`home/dot_bashrc.tmpl`](../home/dot_bashrc.tmpl)                                                                                             | Bash shell integration                             |
| [`home/dot_config/powershell/profile.d/40-integrations.ps1.tmpl`](../home/dot_config/powershell/profile.d/40-integrations.ps1.tmpl)           | PowerShell shell integration                       |
| [`home/dot_config/worktrunk/config.toml.tmpl`](../home/dot_config/worktrunk/config.toml.tmpl)                                                 | Renders shared config on Linux/macOS/Android (XDG) |
| [`home/dot_local/bin/executable_wt-pre-start`](../home/dot_local/bin/executable_wt-pre-start)                                                 | `pre-start` hook script                            |
| [`home/dot_local/bin/executable_wt-post-start`](../home/dot_local/bin/executable_wt-post-start)                                               | `post-start` hook script                           |
| [`home/dot_local/bin/symlink_wt.exe.tmpl`](../home/dot_local/bin/symlink_wt.exe.tmpl)                                                         | Windows symlink → winget-installed `wt.exe`        |
| [`home/winget.yaml.tmpl`](../home/winget.yaml.tmpl)                                                                                           | Windows install + App Execution Alias removal      |

## `wt` Resolution Per Platform

### Windows

Two `wt.exe` binaries compete:

- Worktrunk's `wt.exe` ships in the winget package directory but is _not_
  symlinked into `WinGet\Links\` — winget skips it because the link would
  collide with the existing App Execution Alias. Only `git-wt.exe` gets
  a Links entry.
- Windows Terminal's `wt.exe` is registered as an App Execution Alias
  in `%LOCALAPPDATA%\Microsoft\WindowsApps\`, which sits early on PATH.

[`home/winget.yaml.tmpl`](../home/winget.yaml.tmpl) installs worktrunk, then deletes the App
Execution Alias file (the `wtAppAlias` xScript resource — there is no
Windows API for managing aliases, so we delete the shim directly).
Chezmoi then deploys `~/.local/bin/wt.exe` as a symlink to worktrunk's
binary. `~/.local/bin` is on user PATH, so `wt` resolves to the symlink
on every shell.

**Why the symlink is named `wt.exe`, not a `git-wt`-based wrapper:**
`wt config shell init <shell>` emits both a wrapper function and a clap
tab completer. The completer's `-CommandName` is hardcoded to the
binary's clap name (`wt`) — passing `--cmd=git-wt` retargets the wrapper
function but not the completer. Naming the symlink `wt.exe` lets the
default init output drive both.

### Linux / macOS

Not yet installed by this repo. When added, the binary lands on PATH
as `wt` directly — there is no `wt.exe` collision.

### Android (Termux)

Not in the Termux registry. The install script fetches the
`aarch64-unknown-linux-musl` static binary from GitHub releases (version
from `wt.yaml`, SHA-256 verified) and symlinks it into `~/.local/bin/wt`.

## User Config

One shared template, two thin wrappers:

- [`home/.chezmoitemplates/worktrunk-config.toml`](../home/.chezmoitemplates/worktrunk-config.toml) — shared template
- [`home/dot_config/worktrunk/config.toml.tmpl`](../home/dot_config/worktrunk/config.toml.tmpl) → `~/.config/worktrunk/config.toml` (Linux/macOS/Android)
- [`home/AppData/Roaming/worktrunk/config.toml.tmpl`](../home/AppData/Roaming/worktrunk/config.toml.tmpl) → `%APPDATA%\worktrunk\config.toml` (Windows)

[`.chezmoiignore`](../home/.chezmoiignore) excludes `.config/worktrunk` on Windows (the binary
reads `%APPDATA%` there). Edit the shared template to change config on
every platform.

### Pre-Start

The config wires worktrunk `pre-start` to our `wt-pre-start` shell script. Add new blocking steps
there (e.g., `mise trust`).

### Post-Start

The config wires worktrunk `post-start` to our `wt-post-start` shell script. Add new slow,
non-blocking steps there (e.g., dependency installation).

## Skill

The worktrunk skill ships as a chezmoi external archive pinned to the
same `worktrunk_version` as the binary, so a Renovate bump updates both
together. Deployed to `~/.agents/skills/worktrunk/`.
