# Taylor Buchanan's dotfiles

A [dotfiles] configuration using [chezmoi].

## Features

* A _mostly_ consistent cross-platform terminal emulator using [Wezterm]

  * Android uses [Termux], for [reasons](https://wiki.termux.com/wiki/Getting_started)

* A _mostly_ consistent cross-platform terminal multiplexer using [Wezterm] with
  [tmux bindings][wez-tmux] 

  * Android and non-GUI Linux must use tmux directly

* A consistent nerd font, [Caskaydia Cove]

* A consistent cross-shell prompt using [Starship]

* A _mostly_ consistent cross-shell Vi mode using [ble.sh] and [PSReadLine]

  * [PSReadLine] lacks many Vi mode features, [but you can edit the current command
    externally](https://github.com/PowerShell/PowerShell/issues/21525#issuecomment-2078215370)

* Bash autocomplete, syntax highlighting, and more with [ble.sh]

* Latest vanilla Vim with autocomplete, syntax highlighting, LSP support, and more

* Native cross-platform SSH agent configurations

  * macOS uses Keychain to persist restarts

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

[ble.sh]: https://github.com/akinomyoga/ble.sh/
[Caskaydia Cove]: https://github.com/eliheuer/caskaydia-cove/
[chezmoi]: https://www.chezmoi.io/
[dotfiles]: https://dotfiles.github.io/
[PowerShell]: https://github.com/PowerShell/PowerShell/
[PSReadLine]: https://github.com/PowerShell/PSReadLine/
[Starship]: https://starship.rs/
[Termux]: https://termux.dev/en/
[wez-tmux]: https://github.com/sei40kr/wez-tmux/
[Wezterm]: https://wezterm.org/
