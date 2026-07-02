# Vim

Vim is configured for both standalone use and as the engine behind
Visual Studio's VsVim extension. The two contexts share a single
"safe" config file, layered with Vim-only settings and per-plugin
customizations.

## File Map

| File                                                                                                                | Role                                                                                                                                              |
| ------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`home/dot_vimrc`](../home/dot_vimrc)                                                                               | Standalone Vim entrypoint; sets `g:data_dir` and sources `config/*.vim`                                                                           |
| [`home/dot_vsvimrc`](../home/dot_vsvimrc)                                                                           | VsVim entrypoint; sources `shared.vim` only                                                                                                       |
| [`home/private_dot_vim/private_after/private_plugin/*.vim`](../home/private_dot_vim/private_after/private_plugin/)  | Per-plugin configuration (auto-loaded after plugins)                                                                                              |
| [`home/private_dot_vim/private_config/packages.vim`](../home/private_dot_vim/private_config/packages.vim)           | Loads built-in optional packages (e.g., editorconfig)                                                                                             |
| [`home/private_dot_vim/private_config/plug.vim.tmpl`](../home/private_dot_vim/private_config/plug.vim.tmpl)         | vim-plug plugin manifest (host-conditional)                                                                                                       |
| [`home/private_dot_vim/private_config/shared.vim`](../home/private_dot_vim/private_config/shared.vim)               | Settings safe for both Vim and VsVim                                                                                                              |
| [`home/private_dot_vim/private_plugin/settings.vim.tmpl`](../home/private_dot_vim/private_plugin/settings.vim.tmpl) | Vim-only settings (auto-loaded); on Windows also sets the shell for vim-tmux-navigator edge-forwarding (see [`tmux.md`](tmux.md#pane-navigation)) |

## Two-Entrypoint Layout

VsVim is Visual Studio's Vim emulator. It supports a subset of Vim
syntax — settings, key mappings, and basic motions, but not real
plugins, autocmds, or `set` options Vim doesn't share. Stuffing
everything into a single rc file would either work in Vim and break
VsVim on parse, or limit standalone Vim to VsVim's subset.

The split:

- `shared.vim` — disciplined to syntax both Vim and VsVim
  understand. Its header comment enforces this rule.
- `settings.vim.tmpl` (under `plugin/`) — Vim-only options that VsVim
  doesn't parse.

`dot_vimrc` sources `shared.vim` (and the rest of `config/`).
`dot_vsvimrc` sources only `shared.vim`. Putting a Vim-only setting
into `shared.vim` would break VsVim parsing on every Visual Studio
launch.

## Cross-Platform `data_dir`

Vim on Windows looks for `~/vimfiles/`; everywhere else it's `~/.vim/`.
Maintaining two parallel chezmoi source trees would be ugly. Instead,
`dot_vimrc` forces `~/.vim/` onto `runtimepath` (and prepends its
`after/` subdir too), overriding the platform default. The repo only
ships [`home/private_dot_vim/`](../home/private_dot_vim/).

## Plugin Layout Convention

Three directories under `~/.vim/`, each with a different loading
mechanism:

- **`config/`** — custom, not auto-loaded. `dot_vimrc` sources each
  file explicitly. Used for setup that must happen in order
  (`packages`, then `plug`, then `shared`).
- **`plugin/`** — Vim's standard auto-load directory. Every `.vim`
  file here loads at startup. This is where `settings.vim.tmpl`
  lives.
- **`after/plugin/`** — Vim's standard "after plugins" auto-load
  directory. Files here load _after_ every plugin has loaded, so they
  can safely reference plugin-defined variables and commands. Per-
  plugin tweaks (airline theme, easymotion mappings, fzf workarounds,
  lsp overrides) all live here.

vim-plug installs to `g:data_dir . '/bundle'` to keep installed
plugins separate from this repo's tracked configuration.

## Host-Conditional Pieces

Two patterns appear:

- **Plugin gating** in `plug.vim.tmpl` — the relevant `Plug` line is
  wrapped in a `{{- if eq .chezmoi.os … }}` template guard, so the
  plugin isn't installed on other platforms.
- **Plugin config gating** in the matching `after/plugin/*.vim.tmpl`
  — the per-plugin tweaks are gated by the same OS conditional.

Both files have to be gated. Installing the plugin without configuring
it would leave its feature half-wired; configuring without installing
would error on platforms that don't have the plugin loaded.

Currently used for `fauxClip` (Android, polyfills clipboard registers
via Termux's CLI) and `fzf` (Windows-only popup sizing workaround).

## LSP Setup

The LSP integration layers an LSP client, an auto-install plugin
that fetches matching servers on first open, ALE for diagnostics and
fixers, and a bridge that funnels LSP diagnostics through ALE so a
single pipeline shows everything. The actual plugin names are in
`plug.vim.tmpl`.

`after/plugin/lsp.vim` overrides which LSP servers the auto-installer
picks for Vue and TypeScript filetypes. The auto-installer manages
its own server installs separately from the global pnpm-installed
versions used by other tools.
