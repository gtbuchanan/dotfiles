# Nerd Font

Every terminal, editor, prompt, and diff tool in this repo renders a
Nerd Font so [Starship](https://starship.rs), tmux, airline, and the
Claude statusline can use powerline arrows and other glyphs without
falling back to tofu boxes. Two chezmoi template variables drive the
whole setup; each platform plugs them into its own installer and
config files.

## File Map

| File                                                                                                                                                                                            | Role                                                  |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| [`home/.chezmoi.yaml.tmpl`](../home/.chezmoi.yaml.tmpl)                                                                                                                                         | Defines `.font` and `.fontpack` — the canonical names |
| [`home/.chezmoidata/nerd-fonts.yaml`](../home/.chezmoidata/nerd-fonts.yaml)                                                                                                                     | Pinned Nerd Fonts release (Renovate-tracked)          |
| [`home/.chezmoiscripts/*/run_onchange_before_install-nerd-font.sh.tmpl`](../home/.chezmoiscripts/linux/run_onchange_before_install-nerd-font.sh.tmpl)                                           | Per-platform wrapper over the shared install body     |
| [`home/.chezmoitemplates/nerd-font-install`](../home/.chezmoitemplates/nerd-font-install)                                                                                                       | Download, checksum, unpack, and the Termux TTF step   |
| [`home/.chezmoitemplates/vscode_settings.json`](../home/.chezmoitemplates/vscode_settings.json)                                                                                                 | Sets `editor.fontFamily` (with Consolas fallback)     |
| [`home/AppData/Local/Packages/Microsoft.WindowsTerminal_*/LocalState/settings.json.tmpl`](../home/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json.tmpl) | Windows Terminal profile font                         |
| [`home/AppData/Local/kdiff3rc.cmm.tmpl`](../home/AppData/Local/kdiff3rc.cmm.tmpl)                                                                                                               | KDiff3 font (Windows merge tool)                      |
| [`home/dot_config/wezterm/wezterm.lua.tmpl`](../home/dot_config/wezterm/wezterm.lua.tmpl)                                                                                                       | WezTerm font                                          |
| [`home/winget.yaml.tmpl`](../home/winget.yaml.tmpl)                                                                                                                                             | Windows install via the `NerdFonts` PowerShell module |

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

- **Linux, macOS, Termux** download `.fontpack` straight from the Nerd Fonts
  release pinned in
  [`nerd-fonts.yaml`](../home/.chezmoidata/nerd-fonts.yaml) and verify the
  archive against the `SHA-256.txt` published in the same release, failing the
  apply on a mismatch or a renamed asset. One shared body
  ([`nerd-font-install`](../home/.chezmoitemplates/nerd-font-install)) is
  included by a thin per-platform script, so a version bump re-fires the font
  install alone rather than the whole package pass.
- **Windows** uses the [`NerdFonts`](https://github.com/PSModule/NerdFonts)
  PowerShell module — same job, different ecosystem. The winget DSC
  manifest installs the module, then a DSC script invokes
  `Install-NerdFont` with `.fontpack`. That module takes no version, so
  Windows is the one platform the pin above does not reach.

## Nerd Font Install Directory

Where the pack lands differs because the two font systems search differently:

- **Linux and Termux** — `~/.local/share/fonts/<pack>`. fontconfig recurses,
  so the pack gets a directory of its own and is replaced wholesale on a bump,
  leaving nothing stale behind. `fc-cache` refreshes the index afterwards.
- **macOS** — `~/Library/Fonts`, flat. CoreText reads that directory and is not
  documented to recurse, and it needs no cache refresh. Files from an older
  release stay put: they carry the version in their names, so they don't
  collide, and the rest of that directory isn't ours to delete.

## Termux Quirk

Termux doesn't read system font directories — it renders whatever TTF
sits at `~/.termux/font.ttf`. After unpacking, the Android script picks the
Mono Regular variant out of the pack (falling back to plain Regular if no Mono
variant exists), copies it to that fixed path, and broadcasts the Termux
reload intent so the change applies without a restart.

## Adding a New Consumer

Anywhere a new tool's config takes a font name, reference `{{ .font }}`
from a `.tmpl` file. Install stays a `run_onchange_before_*` script, so the
font is on disk before chezmoi writes any target file that references it.
