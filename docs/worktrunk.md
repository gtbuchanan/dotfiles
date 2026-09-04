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
| [`home/.chezmoidata/wt.yaml`](../home/.chezmoidata/wt.yaml)                                                                                   | Pinned version for Termux (Renovate-tracked)       |
| [`home/.chezmoiexternal.yaml.tmpl`](../home/.chezmoiexternal.yaml.tmpl)                                                                       | Skill archive → `~/.agents/skills/worktrunk/`      |
| [`home/.chezmoiscripts/android/run_onchange_after_install-wt.sh.tmpl`](../home/.chezmoiscripts/android/run_onchange_after_install-wt.sh.tmpl) | Termux manual install                              |
| [`home/.chezmoitemplates/worktrunk-config.toml`](../home/.chezmoitemplates/worktrunk-config.toml)                                             | Shared user-config template                        |
| [`home/AppData/Roaming/worktrunk/config.toml.tmpl`](../home/AppData/Roaming/worktrunk/config.toml.tmpl)                                       | Renders shared config on Windows (`%APPDATA%`)     |
| [`home/dot_bashrc.tmpl`](../home/dot_bashrc.tmpl)                                                                                             | Bash shell integration                             |
| [`home/dot_config/mise/conf.d/worktrunk.toml`](../home/dot_config/mise/conf.d/worktrunk.toml)                                                 | Pinned version everywhere else (Renovate-tracked)  |
| [`home/dot_config/powershell/profile.d/40-integrations.ps1.tmpl`](../home/dot_config/powershell/profile.d/40-integrations.ps1.tmpl)           | PowerShell shell integration                       |
| [`home/dot_config/worktrunk/config.toml.tmpl`](../home/dot_config/worktrunk/config.toml.tmpl)                                                 | Renders shared config on Linux/macOS/Android (XDG) |
| [`home/dot_local/bin/executable_wt-pre-start`](../home/dot_local/bin/executable_wt-pre-start)                                                 | `pre-start` hook script                            |
| [`home/dot_local/bin/executable_wt-post-start`](../home/dot_local/bin/executable_wt-post-start)                                               | `post-start` hook script                           |
| [`home/winget.yaml.tmpl`](../home/winget.yaml.tmpl)                                                                                           | App Execution Alias removal                        |

## `wt` Resolution Per Platform

Everywhere but Termux, worktrunk is a pin in the
[global mise config](mise.md#global-mise-config-fragments); aqua declares both
`wt` and `git-wt`, so mise shims each of them.

### Windows

Windows Terminal registers its own `wt.exe` as an App Execution Alias in
`%LOCALAPPDATA%\Microsoft\WindowsApps\`, and an alias shadows PATH no matter
where the shims sit, so [`home/winget.yaml.tmpl`](../home/winget.yaml.tmpl)
deletes the alias file (the `wtAppAlias` xScript resource — there is no Windows
API for managing aliases, so the shim is deleted directly). With it gone, `wt`
resolves to mise's shim.

**Why the name has to be `wt`, rather than driving `git-wt`:**
`wt config shell init <shell>` emits both a wrapper function and a clap tab
completer. The completer's `-CommandName` is hardcoded to the binary's clap
name (`wt`) — passing `--cmd=git-wt` retargets the wrapper function but not the
completer. The shim being `wt.exe` lets the default init output drive both.

### Linux / macOS

The mise pin puts `wt` on PATH directly; there is no `wt.exe` collision to work
around.

### Android (Termux)

Neither the Termux registry nor aqua covers android, so worktrunk is in
`disable_tools` and installed out of band: the script fetches the
`aarch64-unknown-linux-musl` static binary from GitHub releases (version from
`wt.yaml`, SHA-256 verified) and symlinks it into `~/.local/bin/wt`. That pin
and the mise one are bumped separately and should move together.

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
