# tmux

A mostly-consistent cross-platform terminal multiplexer from a single config,
[`home/dot_tmux.conf.tmpl`](../home/dot_tmux.conf.tmpl). The backend differs by
platform:

- **Linux, macOS, Android** use [tmux] directly.
- **Windows** uses [psmux], a tmux-command-compatible multiplexer implemented
  for Windows. It reads `~/.tmux.conf`, so the same source file drives both.

Template conditionals (`{{ if eq .chezmoi.os "windows" }}`) fork the places
where the backends diverge.

## File Map

| File                                                                                                                  | Role                                                                           |
| --------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| [`home/.chezmoiexternal.yaml.tmpl`](../home/.chezmoiexternal.yaml.tmpl)                                               | Fetches TPM Redux (non-Windows plugin manager)                                 |
| [`home/.chezmoiignore`](../home/.chezmoiignore)                                                                       | Gates `dot_psmux` off non-Windows                                              |
| [`home/dot_psmux/plugins/psmux-vim-navigator/plugin.conf`](../home/dot_psmux/plugins/psmux-vim-navigator/plugin.conf) | Windows-only psmux plugin: Vim-aware `C-h/j/k/l` binds                         |
| [`home/dot_tmux.conf.tmpl`](../home/dot_tmux.conf.tmpl)                                                               | The multiplexer config; prefix, splits, per-OS tuning, plugin/nav declarations |
| [`home/private_dot_vim/private_config/plug.vim.tmpl`](../home/private_dot_vim/private_config/plug.vim.tmpl)           | Declares `christoomey/vim-tmux-navigator` — the Vim side, all platforms        |
| [`home/private_dot_vim/private_plugin/settings.vim.tmpl`](../home/private_dot_vim/private_plugin/settings.vim.tmpl)   | Windows-only Vim shell override so edge-forwarding runs `tmux`                 |

## Prefix and Splits

The prefix is remapped from `C-b` to `C-Space`. Splits open in the current
pane's directory. Prefix `C-l` is preserved to send a readline clear-screen,
since unprefixed `C-l` is otherwise a navigation key (see
[Pane Navigation](#pane-navigation)).

## Windows psmux Tuning

psmux-only options in the Windows branch disable warm panes so each pane gets a
fresh shell ([psmux#120](https://github.com/psmux/psmux/issues/120)) and allow
predictions to preserve the user's `PredictionSource`
([psmux#150](https://github.com/psmux/psmux/issues/150)).

## Pane Navigation

Seamless `C-h/j/k/l` movement between Vim splits and multiplexer panes, so one
set of keys crosses both boundaries. This is a two-sided design
([`christoomey/vim-tmux-navigator`][vtn]):

- The **multiplexer side** decides, per keypress, whether the active pane runs
  Vim. If so it forwards the key _into_ Vim; otherwise it switches panes.
- The **Vim side** moves between splits, and _at a layout edge_ forwards the key
  back to the multiplexer.

Both halves must agree, or navigation can't enter Vim's splits or can't escape
them.

### Multiplexer Side: tmux

On Linux/macOS/Android the multiplexer side is the upstream
[`vim-tmux-navigator`][vtn] tmux plugin. Its `.tmux` script detects Vim by
running `ps` against the pane's tty and matching the foreground process name.
That approach has no Windows equivalent (no `ps`, no tty).

### Multiplexer Side: psmux Plugin

psmux ships no port of `vim-tmux-navigator`, so this repo provides one:
[`psmux-vim-navigator`](../home/dot_psmux/plugins/psmux-vim-navigator/plugin.conf).
It detects Vim from psmux's native `#{pane_current_command}` — Windows has no
`ps` or tty — then forwards into Vim or switches panes per keypress; the plugin
file documents the condition and bindings.

It loads from a `set -g @plugin` line, which psmux sources natively (no `ppm`
entry point, and ppm isn't wired into this config), so chezmoi just deploys the
plugin directory.

### Vim Side and the Windows Shell

The Vim side is the same [`vim-tmux-navigator`][vtn] plugin on every platform;
at a split edge it shells out via Vim's `system()` to switch panes, resolving
through the `tmux` shim psmux puts on the `PATH`. That call fails under Windows'
default `cmd.exe`, so
[`settings.vim.tmpl`](../home/private_dot_vim/private_plugin/settings.vim.tmpl)
points Vim's shell at Git Bash — the file explains why cmd.exe breaks and what
the override sets.

### Netrw C-l Caveat

Inside netrw buffers on Windows, `C-l` bells and jumps the cursor to the last
entry (`C-h/j/k` are unaffected). This is a `vim-tmux-navigator` bug: its netrw
workaround registers a `<C-l>` entry in `g:Netrw_UserMaps` whose value is a
command string, but this netrw version expects a function name there, so the
resulting mapping misfires.

Disabling the workaround is _not_ a fix: netrw has other `C-l` handling that
then wedges the key outright — strictly worse than the bell/jump. The workaround
is left enabled and the netrw quirk accepted; ordinary file buffers are
unaffected.

[tmux]: https://github.com/tmux/tmux
[psmux]: https://github.com/marlocarlo/psmux
[vtn]: https://github.com/christoomey/vim-tmux-navigator
