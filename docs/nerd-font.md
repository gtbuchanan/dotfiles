# Nerd Font

Every terminal, editor, prompt, and diff tool in this repo renders a
Nerd Font so [Starship](https://starship.rs), tmux, airline, and the
Claude statusline can use powerline arrows and other glyphs without
falling back to tofu boxes. Two chezmoi template variables drive the
whole setup; each platform plugs them into its own installer and
config files.

## File Map

| File | Role |
|---|---|
| [`home/.chezmoi.yaml.tmpl`](../home/.chezmoi.yaml.tmpl) | Defines `.font` and `.fontpack` — the canonical names |
| [`home/.chezmoiscripts/android/run_onchange_before.sh.tmpl`](../home/.chezmoiscripts/android/run_onchange_before.sh.tmpl) | Installs via `getnf`, then copies a single TTF into `~/.termux/font.ttf` and reloads Termux |
| [`home/.chezmoiscripts/darwin/run_onchange_before.sh.tmpl`](../home/.chezmoiscripts/darwin/run_onchange_before.sh.tmpl) | Installs via `getnf` |
| [`home/.chezmoiscripts/linux/run_onchange_before.sh.tmpl`](../home/.chezmoiscripts/linux/run_onchange_before.sh.tmpl) | Installs via `getnf` |
| [`home/.chezmoitemplates/vscode_settings.json`](../home/.chezmoitemplates/vscode_settings.json) | Sets `editor.fontFamily` (with Consolas fallback) |
| [`home/AppData/Local/Packages/Microsoft.WindowsTerminal_*/LocalState/settings.json.tmpl`](../home/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json.tmpl) | Windows Terminal profile font |
| [`home/AppData/Local/kdiff3rc.cmm.tmpl`](../home/AppData/Local/kdiff3rc.cmm.tmpl) | KDiff3 font (Windows merge tool) |
| [`home/dot_config/wezterm/wezterm.lua.tmpl`](../home/dot_config/wezterm/wezterm.lua.tmpl) | WezTerm font |
| [`home/winget.yaml.tmpl`](../home/winget.yaml.tmpl) | Windows install via the `NerdFonts` PowerShell module |

## Two Variables

The font name a consumer sees and the name an installer takes aren't
the same string, so [`.chezmoi.yaml.tmpl`](../home/.chezmoi.yaml.tmpl) defines both:

- **`.font`** — the **font family** name as the OS reports it
  (`CaskaydiaCove NF`). Every app config interpolates this into its
  font-family setting.
- **`.fontpack`** — the **Nerd Fonts pack** identifier
  (`CascadiaCode`). Used only by the installers.

Splitting them keeps every consumer pointing at a single source of
truth and makes swapping fonts a two-line edit in
[`.chezmoi.yaml.tmpl`](../home/.chezmoi.yaml.tmpl).

## Platform Installers

- **Linux, macOS, Termux** use [`getnf`](https://github.com/getnf/getnf),
  a small CLI that downloads Nerd Fonts release archives. The
  before-script bootstraps `getnf` from upstream and asks it to
  install `.fontpack`.
- **Windows** uses the [`NerdFonts`](https://github.com/PSModule/NerdFonts)
  PowerShell module — same job, different ecosystem. The winget DSC
  manifest installs the module, then a DSC script invokes
  `Install-NerdFont` with `.fontpack`.

## Termux Quirk

Termux doesn't read system font directories — it renders whatever TTF
sits at `~/.termux/font.ttf`. After `getnf` installs the pack, the
Android before-script picks the Mono Regular variant out of the
unpacked files (falling back to plain Regular if no Mono variant
exists), copies it to that fixed path, and broadcasts the Termux
reload intent so the change applies without a restart.

## Adding a New Consumer

Anywhere a new tool's config takes a font name, reference `{{ .font }}`
from a `.tmpl` file. Install runs as a `run_onchange_before_*`
script, so the font is on disk before chezmoi writes any target file
that references it.
