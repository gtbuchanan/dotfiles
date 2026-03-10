# Taylor Buchanan's dotfiles

A [dotfiles] configuration using [chezmoi].

## Features

* A _mostly_ consistent cross-platform terminal emulator using [Wezterm]

  * Android uses [Termux], for [reasons](https://wiki.termux.com/wiki/Getting_started)

* A _mostly_ consistent cross-platform terminal multiplexer using [tmux] and
  [psmux] (Windows)

  * Android and non-GUI Linux use tmux directly

* A consistent nerd font, [Caskaydia Cove]

* A consistent cross-shell prompt using [Starship]

* A _mostly_ consistent cross-shell Vi mode using [ble.sh] and [PSReadLine]

  * [PSReadLine] lacks many Vi mode features, [but you can edit the current command
    externally](https://github.com/PowerShell/PowerShell/issues/21525#issuecomment-2078215370)

* Bash autocomplete, syntax highlighting, and more with [ble.sh]

* Latest vanilla Vim with autocomplete, syntax highlighting, LSP support, and more

* Native cross-platform SSH agent configurations

  * macOS uses Keychain to persist restarts

* Consistent cross-tool [AI agent preferences][AGENTS.md] and [skills][Agent Skills]

  * [Claude Code]
  * [Codex CLI]
  * [GitHub Copilot CLI]
  * [VS Code Copilot]

* Windows Subsystem for Linux (WSL) support

  * SSH agent forwarding to host

  * Git GPG forwarding to host (no global forwarding **yet**)

  * Shellception: `win pwsh` -> `wsl bash` -> `wsl pwsh`

## Limitations

* Only Android, Windows, Linux, and macOS platforms are supported

  * I don't use iOS, and it's too limited for terminal emulation (AFAIK)

  * Linux support only tested on Ubuntu WSL (for now)

* Only Bash and [PowerShell] (`pwsh.exe`) shells are supported

  * Bash is available almost everywhere, and [ble.sh] makes it just as good as other shells

  * CMD and Windows PowerShell are effectively in maintenance mode. Long live [PowerShell]!

  * On macOS, ZSH is replaced by the latest Bash for consistency

## Getting Started

### Prerequisites

* [Chezmoi][chezmoi]
  * Windows: `winget install -e --id twpayne.chezmoi`
  * macOS: `brew install chezmoi`
  * Ubuntu/Snap: `snap install --classic chezmoi`
* [Chezmoi Modify Manager]: Unzip [release][Chezmoi Modify Manager Release] and add to PATH
  * macOS: `xattr -d com.apple.quarantine "$HOME/bin/chezmoi_modify_manager"`
* [PowerShell] (Windows only): `winget install -e --id Microsoft.PowerShell`
* [Dashlane CLI] (Work only): Unzip [release][Dashlane CLI Release] and add to PATH

### Install

1. Reset WinGet if needed (Windows only, see [workaround][WinGet Reset]):

   `Reset-AppxPackage -Package 'Microsoft.DesktopAppInstaller_1.26.430.0_x64__8wekyb3d8bbwe'`

1. Restart shell or reload environment variables
1. `dcli sync` (Work only)
1. `chezmoi init --apply gtbuchanan`

### Troubleshooting

#### WinGet Errors

WinGet intermittently fails with RPC errors. To retry from the repo root
(`cmcd`):

```
winget configure -f dist/winget.yaml --suppress-initial-details --accept-configuration-agreements
```

Alternatively, clear the script cache and re-run `chezmoi apply`:

```
chezmoi state delete-bucket --bucket=scriptState
```

[Agent Skills]: https://agentskills.io/
[AGENTS.md]: home/dot_config/AGENTS.md
[ble.sh]: https://github.com/akinomyoga/ble.sh/
[Caskaydia Cove]: https://github.com/eliheuer/caskaydia-cove/
[chezmoi]: https://www.chezmoi.io/
[Chezmoi Modify Manager]: https://github.com/VorpalBlade/chezmoi_modify_manager
[Chezmoi Modify Manager Release]: https://github.com/VorpalBlade/chezmoi_modify_manager/releases
[Claude Code]: https://claude.ai/code
[Codex CLI]: https://github.com/openai/codex
[Dashlane CLI]: https://github.com/Dashlane/dashlane-cli
[Dashlane CLI Release]: https://github.com/Dashlane/dashlane-cli/releases
[dotfiles]: https://dotfiles.github.io/
[GitHub Copilot CLI]: https://github.com/github/copilot-cli
[PowerShell]: https://github.com/PowerShell/PowerShell/
[psmux]: https://github.com/marlocarlo/psmux
[PSReadLine]: https://github.com/PowerShell/PSReadLine/
[Starship]: https://starship.rs/
[Termux]: https://termux.dev/en/
[tmux]: https://github.com/tmux/tmux
[VS Code Copilot]: https://code.visualstudio.com/docs/copilot/overview
[Wezterm]: https://wezterm.org/
[WinGet Reset]: https://github.com/microsoft/winget-cli/issues/5626#issuecomment-3264037684
