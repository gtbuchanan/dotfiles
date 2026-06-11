# Bash

Bash is the Unix-side shell across every platform this repo targets
(PowerShell handles the Windows side — see [`README.md`](../README.md)).
The setup has three load-bearing pieces: a current bash on every host,
[ble.sh](https://github.com/akinomyoga/ble.sh) turning bash into
something competitive with zsh/fish, and a single set of `.bashrc` /
`.bash_aliases` / `.blerc` files with template branches for per-OS
divergence.

## File Map

| File | Role |
|---|---|
| [`home/.chezmoiignore`](../home/.chezmoiignore) | Gates `.bash*`, `.blerc`, `.profile`, `*.sh*` off non-bash platforms |
| [`home/.chezmoiscripts/android/run_onchange_before.sh.tmpl`](../home/.chezmoiscripts/android/run_onchange_before.sh.tmpl) | Termux: installs `bash-completion`, downloads ble.sh nightly |
| [`home/.chezmoiscripts/darwin/run_onchange_before.sh.tmpl`](../home/.chezmoiscripts/darwin/run_onchange_before.sh.tmpl) | macOS: installs Homebrew bash + bash-completion, `chsh`'s the login shell, downloads ble.sh nightly |
| [`home/.chezmoiscripts/linux/run_onchange_before.sh.tmpl`](../home/.chezmoiscripts/linux/run_onchange_before.sh.tmpl) | apt-installs `bash-completion`, downloads ble.sh nightly |
| [`home/dot_bash_aliases.tmpl`](../home/dot_bash_aliases.tmpl) | Shortcuts + worktree-cd helper |
| [`home/dot_bash_profile.tmpl`](../home/dot_bash_profile.tmpl) | Login-shell entry: sources `.profile`, WSL agent bridge, `.bashrc` |
| [`home/dot_bashrc.tmpl`](../home/dot_bashrc.tmpl) | Interactive shell setup (sourced by `.bash_profile`) |
| [`home/dot_blerc`](../home/dot_blerc) | ble.sh config: vi mode, prompt mode-indicator hook, `progcomp_alias` |
| [`home/dot_profile.tmpl`](../home/dot_profile.tmpl) | POSIX-shell env vars (PATH additions incl. mise shims, Android `SSH_ASKPASS` and friends, macOS Homebrew prepends) |
| [`home/winget.yaml.tmpl`](../home/winget.yaml.tmpl) | Windows: installs Git for Windows (which provides Git Bash) and prepends `Git\bin` to PATH for pre-commit |

## Bash Source

Each platform's bash comes from somewhere different:

- **macOS** still ships bash 3.2 — old enough that ble.sh and modern
  scripts don't run cleanly on it. The darwin before-script installs
  Homebrew's bash, adds it to `/etc/shells`, and `chsh`'s the login
  shell to it (which also replaces zsh as the default — see the
  README's "consistency" framing).
- **Termux / Linux / WSL** — the distro's bash is current; no special
  handling.
- **Windows** ships Git Bash via the Git for Windows winget package.
  PowerShell is the primary interactive shell on Windows, so the
  chezmoi-managed bash dotfiles don't deploy there at all (see the
  [`.chezmoiignore`](../home/.chezmoiignore) gate). Git Bash exists for tooling that needs a
  POSIX shell — most notably pre-commit, whose
  [Windows quirk](https://github.com/pre-commit/pre-commit/issues/3091)
  is why the winget manifest **prepends** `Git\bin` to PATH instead of
  appending.

## ble.sh

[ble.sh](https://github.com/akinomyoga/ble.sh) is the autocomplete /
syntax-highlighting / vi-mode editing engine. Each platform's
before-script downloads the current upstream nightly tarball directly
at apply time — tracking nightly upstream rather than distro
repositories.

`.blerc` does three things:

- Enables vi mode (`set -o vi`).
- Exposes a `vim-mode` prompt callback that [Starship](https://starship.rs)
  reads to render NORMAL / INSERT / VISUAL etc. — and suppresses
  ble.sh's own mode indicator so Starship is the only source of
  truth.
- Enables `progcomp_alias` so completion fires through aliases
  (`g <tab>` completes as `git <tab>`).

The README's "_mostly_ consistent cross-shell Vi mode" caveat is real:
ble.sh's vi mode is far more complete than PSReadLine's on the
PowerShell side, but the two diverge in edge cases.

## Load Order

The bash startup chain follows the [Greg's Wiki](https://mywiki.wooledge.org/DotFiles)
idiom: `.bash_profile` sources `.profile` first (POSIX-shell env vars
that should be inherited by non-bash logins too — Android sets
`SSH_ASKPASS` and friends there), then sources `.bashrc` so login and
non-login interactive shells get the same setup. On WSL,
`.bash_profile` additionally starts the
[Windows agent bridge](ssh.md#wsl--windows-agent-bridge) before
handing off.

`.bashrc` is where the interactive surface lives — every shell
integration (Starship, fzf, delta completion, worktrunk's `wt`
function, nvm, mise activation, wezterm shell integration) is wired up here so
individual tool docs don't have to.

## Auto-tmux

On non-WSL interactive sessions, `.bashrc` execs into a shared named
tmux session so every new terminal window joins (or starts) the same
one. WSL skips this — WezTerm on the Windows side already launches
[psmux](https://github.com/marlocarlo/psmux) as its default program,
and nesting multiplexers gets confusing fast.
