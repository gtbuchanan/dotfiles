# Chezmoi Dotfiles — Agent Guide

Cross-platform dotfiles managed with [chezmoi](https://www.chezmoi.io/) v2.62.2+.
The chezmoi root is `home/`; see `.chezmoiroot`. Deep-dive references for
cross-file configurations live in [`docs/`](docs/README.md).

## CRITICAL: All Changes Go Through Chezmoi

**NEVER edit deployed files directly** (e.g., `~/.gitconfig`, `~/.config/AGENTS.md`,
`~/.claude/settings.json`). Those files are managed by chezmoi and will be overwritten.
Always edit the corresponding source in **this repo** under `home/`, then run
`chezmoi apply` to deploy.

## Workflow

- Always pass `--no-tty` to `chezmoi apply` so it fails on interactive prompts
  instead of blocking. If it fails, report the error and let the user decide
  how to proceed.
- Never combine `--force` with a bare `chezmoi apply` (no targets) —
  `--force` discards any local drift across the entire tree without
  inspection. Always scope `--force` to the specific target(s) that need it:
  `chezmoi apply --no-tty --force <path>`. For everything else, fix the
  drift at the source or ask the user.
- Exception that needs `--force` on every apply: `~/.claude/settings.json`
  is rewritten by Claude Code at runtime (key reordering, blank-line
  stripping, auto-set fields like `editorMode`), so chezmoi sees drift on
  every run. When apply fails because of this, re-run targeted:
  `chezmoi apply --no-tty --force ~/.claude/settings.json`, then a normal
  `chezmoi apply --no-tty` for the rest. If a drifted field is actually
  wanted, add it to `home/dot_claude/settings.json.tmpl` first.
- Edit files under `home/`, then run `chezmoi apply <target>...` to deploy only the
  affected targets (e.g., `chezmoi apply ~/.config/starship.toml ~/.gitconfig`).
- Use bare `chezmoi apply` (no targets) when editing shared templates — files included
  by multiple outputs. Key examples: `dot_config/AGENTS.md.tmpl` (included by Claude,
  Codex, Copilot, and VS Code templates) and files in `.chezmoitemplates/`.
  Targeting a single output will leave the others stale.
- After modifying `home/winget.yaml.tmpl`, the compiled output is regenerated automatically
  by the before-script on the next `chezmoi apply`. The `dist/winget.yaml` file is generated
  output — do not edit it directly.
- To preview changes without applying: `chezmoi diff`.

## Forcing run_onchange Scripts to Re-run

`run_onchange_*` scripts only fire when their rendered content's SHA256
changes. The hash is tracked in chezmoi's `entryState` bucket — deleting
the matching `scriptState` entry alone is NOT enough, because chezmoi
compares the new hash against `entryState` to decide whether to skip
the script.

To force a re-run, delete the script's `entryState` entry (keyed by the
destination path of the rendered script):

```
chezmoi state delete --bucket=entryState \
  --key=$HOME/.chezmoiscripts/<os>/<script>.sh
chezmoi apply --no-tty
```

Useful when the rendered content is unchanged but external state has
drifted (e.g., pnpm's global bin layout moved from `$PNPM_HOME` to
`$PNPM_HOME/bin` and globals need to be reinstalled even though their
pinned versions match).

## File Naming Conventions

Chezmoi uses filename prefixes/suffixes to control deployment behavior:

| Prefix/Suffix | Meaning |
|---|---|
| `dot_` | Deployed with a leading `.` (e.g., `dot_gitconfig` → `.gitconfig`) |
| `private_` | Excluded from world-readable permissions |
| `readonly_` | Deployed read-only |
| `executable_` | Deployed with execute bit set |
| `.tmpl` | Go text template; evaluated during `chezmoi apply` |
| `modify_` | Script that modifies an existing target file |
| `run_onchange_before_` | Script run before apply when its content changes |
| `run_onchange_after_` | Script run after apply when its content changes |
| `remove_` | Ensures the target path is removed |

Prefixes may be combined, e.g., `private_dot_ssh/`.

## Template Variables

Key variables available in `.tmpl` files:

| Variable | Values | Description |
|---|---|---|
| `.chezmoi.os` | `windows`, `linux`, `darwin`, `android` | Host OS |
| `.hosttype` | `personal`, `ewn` | Host type (personal or company) |
| `.osid` | `linux-ubuntu`, `windows`, `darwin`, etc. | OS identifier |
| `.wsl` | `true`/`false` | Running under WSL |
| `.font` | `CaskaydiaCove NF` | Nerd Font family |
| `.fontpack` | `CascadiaCode` | Nerd Font package name |
| `.email` | string | Signing email, varies by host type |
| `.signingkey` | string | GPG key ID, varies by host type |

## Directory Structure

```
package.json                       # pnpm global package versions (Renovate-managed)
home/
├── .chezmoi.yaml.tmpl           # Chezmoi config; prompts for hosttype on first run
├── .chezmoiexternal.yaml.tmpl   # External resources fetched during apply
├── .chezmoiignore               # Platform-conditional file exclusions
├── .chezmoiremove               # Files to remove from target
├── .chezmoitemplates/
│   ├── pnpm-globals             # Shared template: generates pnpm add -g commands
│   ├── powershell_profile.ps1   # PowerShell profile (aliases, functions, shell config)
│   └── ...                      # Other reusable Go templates (VS Code settings, etc.)
├── .chezmoiscripts/
│   ├── windows/                 # PowerShell scripts (run on Windows)
│   ├── linux/                   # Shell scripts (run on Linux/WSL)
│   ├── darwin/                  # Shell scripts (run on macOS)
│   └── android/                 # Shell scripts (run on Termux)
├── dot_gitconfig.tmpl            # Git config (aliases, core, delta, merge, push, etc.)
├── dot_config/
│   ├── AGENTS.md.tmpl            # User-level agent preferences (source of truth)
│   ├── Code/                    # VS Code settings (Windows-only, modify script)
│   ├── wezterm/                 # WezTerm config (Lua)
│   ├── powershell/              # PowerShell profile
│   ├── private_git/             # Git config: global ignore (`ignore`) + GPG wrapper
│   └── private_starship.toml    # Starship prompt
├── dot_claude/
│   ├── CLAUDE.md.tmpl            # References dot_config/AGENTS.md.tmpl
│   ├── settings.json.tmpl       # Auto-allow permissions + status line
│   └── symlink_skills           # → ../.agents/skills
├── dot_copilot/                 # GitHub Copilot instructions (references AGENTS.md)
├── private_dot_vim/             # Vim config, plugins, after-plugin overrides
├── private_dot_ssh/             # SSH config
├── winget.yaml.tmpl             # Windows package/config manifest (DSC)
└── AppData/                     # Windows-specific app configs
    ├── Local/Packages/Microsoft.WindowsTerminal_*/LocalState/
    │   └── settings.json.tmpl   # Windows Terminal settings
    └── Roaming/                 # VS Code, KDiff3, GPG, etc.
```

## Platform-Conditional Targets

Many source files are excluded on certain OSes via `.chezmoiignore`. Before running
`chezmoi apply <target>`, verify the target is managed on the current platform —
unmanaged targets will error. Use `chezmoi managed` or check `.chezmoiignore`.

Key exclusions (see `.chezmoiignore` for the full set):

| Files | Managed on | Excluded on |
|---|---|---|
| `.bash*`, `.blerc`, `.profile`, `*.sh*` | linux, darwin, android | windows |
| `.config/powershell/` | linux, darwin | windows, android |
| `.config/Code/` | linux, darwin | windows, android |
| `.config/wezterm/` | darwin, windows | linux, android |
| `.gnupg/` | linux, darwin, android | windows |
| `.tmux*` | linux, darwin, android | windows |
| `AppData/`, `Documents/`, `*.bat*` | windows | linux, darwin, android |
| `Library/` | darwin | windows, linux, android |
| `.termux/` | android | windows, linux, darwin |

Shared templates (`.chezmoitemplates/`) are **not** deployed directly — they are
included by platform-specific targets. For example, `powershell_profile.ps1` is
consumed by both `dot_config/powershell/` (Linux/macOS) and
`Documents/PowerShell/` (Windows). When editing a shared template, deploy the
target(s) that exist on the current OS.

## Platform-Specific Scripting

Scripts under `.chezmoiscripts/` are platform-gated via `.chezmoiignore`. Each platform
directory is excluded on non-matching OSes. Use the template variables above for finer-grained
conditionals within a script (e.g., WSL vs. native Linux, personal vs. ewn).

## Formatting

- UTF-8, 2-space indent, LF line endings, final newline, trim trailing whitespace.
- Exception: `*gitconfig*` files use tab indent (Git requires tabs).
- See `.editorconfig` for the canonical rules.

## Agent Skills

Skills follow the [Agent Skills](https://agentskills.io) standard. To add one,
add an entry in `home/.chezmoiexternal.yaml.tmpl` pointing to the skill's
archive — every supported tool picks it up automatically.

See [`docs/agent-config.md`](docs/agent-config.md) for the cross-tool deploy
path, Claude symlink redirect, and pinning conventions.

## Global pnpm Packages

Global pnpm package versions are centralized in `package.json` at the repo root.
A shared chezmoi template (`home/.chezmoitemplates/pnpm-globals`) reads this file
and generates `pnpm add -g` commands. Each `run_onchange_after_` script declares
which packages it needs via an include list, so a version bump only re-runs the
scripts that use that package.

To add a new package:

1. Add the package and pinned version to `package.json`.
1. Add the package name to the include list in exactly one script. Scripts that
   need a package for post-install steps (e.g., MCP registration) install it
   themselves to stay self-contained.

See [`docs/pnpm-globals.md`](docs/pnpm-globals.md) for the template internals,
GitHub-spec handling, the `pnpmfile.cjs` hook, and the per-script package mapping.

## User-Level Agent Preferences

Project-agnostic agent preferences (coding style, git conventions, etc.) live in
`home/dot_config/AGENTS.md.tmpl`, the single source consumed by every supported
tool via per-tool wrappers. Do not duplicate those rules here.

See [`docs/agent-config.md`](docs/agent-config.md) for the wrapper map and how
the shared template fans out.
