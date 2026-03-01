# Chezmoi Dotfiles — Agent Guide

Cross-platform dotfiles managed with [chezmoi](https://www.chezmoi.io/) v2.62.2+.
The chezmoi root is `home/`; see `.chezmoiroot`.

## Workflow

- After modifying any file under `home/`, run `chezmoi apply` to deploy changes.
- After modifying `home/winget.yaml.tmpl`, the compiled output is regenerated automatically
  by the before-script on the next `chezmoi apply`. The `dist/winget.yaml` file is generated
  output — do not edit it directly.
- To preview changes without applying: `chezmoi diff`.

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
home/
├── .chezmoi.yaml.tmpl           # Chezmoi config; prompts for hosttype on first run
├── .chezmoiexternal.yaml.tmpl   # External resources fetched during apply
├── .chezmoiignore               # Platform-conditional file exclusions
├── .chezmoiremove               # Files to remove from target
├── .chezmoitemplates/           # Reusable Go templates (PowerShell profile, VS Code settings)
├── .chezmoiscripts/
│   ├── windows/                 # PowerShell scripts (run on Windows)
│   ├── linux/                   # Shell scripts (run on Linux/WSL)
│   ├── darwin/                  # Shell scripts (run on macOS)
│   └── android/                 # Shell scripts (run on Termux)
├── dot_config/
│   ├── AGENTS.md                # User-level agent preferences (source of truth)
│   ├── wezterm/                 # WezTerm config (Lua)
│   ├── powershell/              # PowerShell profile
│   ├── private_git/             # Global gitignore + GPG wrapper
│   └── private_starship.toml    # Starship prompt
├── dot_claude/CLAUDE.md         # References dot_config/AGENTS.md
├── dot_copilot/                 # GitHub Copilot instructions (references AGENTS.md)
├── private_dot_vim/             # Vim config, plugins, after-plugin overrides
├── private_dot_ssh/             # SSH config
├── winget.yaml.tmpl             # Windows package/config manifest (DSC)
└── AppData/                     # Windows-specific app configs (Terminal, VS Code, KDiff3, GPG)
```

## Platform-Specific Scripting

Scripts under `.chezmoiscripts/` are platform-gated via `.chezmoiignore`. Each platform
directory is excluded on non-matching OSes. Use the template variables above for finer-grained
conditionals within a script (e.g., WSL vs. native Linux, personal vs. ewn).

## Formatting

- UTF-8, 2-space indent, LF line endings, final newline, trim trailing whitespace.
- Exception: `*gitconfig*` files use tab indent (Git requires tabs).
- See `.editorconfig` for the canonical rules.

## GPG Signing and AI Agents

GPG signing is enabled for all commits. The GPG wrapper at
`home/dot_config/private_git/gpg-wrapper.bat` adjusts pinentry behavior based on the caller:

- When `CLAUDE_CODE` or `AI_AGENT` env var is set: calls GPG without `--pinentry-mode loopback`
  so non-interactive signing works.
- Otherwise with `GPG_TTY` set: adds `--pinentry-mode loopback` for terminal pinentry.

Always set `AI_AGENT=1` when running git commands as an agent.

## User-Level Agent Preferences

Project-agnostic agent preferences (coding style, git conventions, etc.) live in
`home/dot_config/AGENTS.md`. That file is the single source consumed by Claude Code
(`dot_claude/CLAUDE.md`), GitHub Copilot (`dot_copilot/copilot-instructions.md.tmpl`),
and VS Code (`AppData/.../personal.instructions.md.tmpl`).
Do not duplicate those rules here.
