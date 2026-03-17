# Chezmoi Dotfiles — Agent Guide

Cross-platform dotfiles managed with [chezmoi](https://www.chezmoi.io/) v2.62.2+.
The chezmoi root is `home/`; see `.chezmoiroot`.

## CRITICAL: All Changes Go Through Chezmoi

**NEVER edit deployed files directly** (e.g., `~/.gitconfig`, `~/.config/AGENTS.md`,
`~/.claude/settings.json`). Those files are managed by chezmoi and will be overwritten.
Always edit the corresponding source in **this repo** under `home/`, then run
`chezmoi apply` to deploy.

## Workflow

- Edit files under `home/`, then run `chezmoi apply` to deploy changes.
- After modifying `home/winget.yaml.tmpl`, the compiled output is regenerated automatically
  by the before-script on the next `chezmoi apply`. The `dist/winget.yaml` file is generated
  output — do not edit it directly.
- After editing a shared template (e.g., `AGENTS.md`, files in `.chezmoitemplates/`),
  run `chezmoi apply` with no args to update all targets that reference it.
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
mcp-readonly/                    # Read-only MCP server (runs from repo, not deployed)
├── index.mjs                    # Server entrypoint (security docs + wiring)
├── lib/                         # Shared helpers (exec, allowlist)
├── tools/                       # One tool per file + barrel index
└── test/                        # node:test integration tests
home/
├── .chezmoi.yaml.tmpl           # Chezmoi config; prompts for hosttype on first run
├── .chezmoiexternal.yaml.tmpl   # External resources fetched during apply
├── .chezmoiignore               # Platform-conditional file exclusions
├── .chezmoiremove               # Files to remove from target
├── .chezmoitemplates/
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
│   └── symlink_skills           # → ../.config/skills
├── dot_copilot/                 # GitHub Copilot instructions (references AGENTS.md)
│   └── symlink_skills           # → ../.config/skills
├── dot_agents/
│   └── symlink_skills           # → ../.config/skills
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

## Agent Skills

Skills follow the [Agent Skills](https://agentskills.io) standard. Skills are fetched as
external archives via `home/.chezmoiexternal.yaml.tmpl` and deployed to `~/.config/skills/`.
Each tool discovers skills via a `skills/` symlink in its config directory:

```
~/.config/skills/              ← deployed by chezmoi externals
    atlassian-cli/SKILL.md

~/.claude/skills  → ../.config/skills   (symlink)
~/.copilot/skills → ../.config/skills   (symlink)
~/.agents/skills  → ../.config/skills   (symlink)
```

To add a new skill, add an entry in `.chezmoiexternal.yaml.tmpl` pointing to the skill's
archive. All tools pick it up automatically. Use template conditionals to gate
host-specific skills (e.g., `atlassian-cli` is ewn-only).

## MCP Readonly Server

A custom MCP server at `mcp-readonly/` (repo root) provides read-only tool access
for AI agents. It exposes allowlisted subsets of `az`, `git`, `gh`, `chezmoi`, `acli`, `npm`, `pnpm`,
and common shell utilities (ls, jq, stat, wc, etc.) — blocking any mutating operations.

The server runs directly from the chezmoi repo — it is **not** deployed by chezmoi.
Tools reference the repo path via `{{ .chezmoi.workingTree }}`.

Configuration targets:
- **Claude Code**: Registered via `claude mcp add --scope user` (in the install script), auto-allow permissions in `home/dot_claude/settings.json.tmpl`
- **VS Code / Copilot**: `home/.chezmoitemplates/vscode_settings.json` (`mcp.servers`)

Dependencies are installed and the server is registered via
`home/.chezmoiscripts/windows/run_onchange_after_mcp-readonly-install.ps1.tmpl`,
which reruns when `pnpm-lock.yaml` changes (hashed via `git hash-object`).

After any change to the MCP server, run security tests before committing:
`pnpm -C mcp-readonly install && pnpm -C mcp-readonly test`

Security design rationale is documented in the `index.mjs` header comment and
`test/*.test.mjs`. Auto-allow decisions are in `home/dot_claude/settings.json.tmpl`.

## User-Level Agent Preferences

Project-agnostic agent preferences (coding style, git conventions, etc.) live in
`home/dot_config/AGENTS.md.tmpl`. That file is the single source consumed by Claude Code
(`dot_claude/CLAUDE.md.tmpl`), GitHub Copilot (`dot_copilot/copilot-instructions.md.tmpl`),
and VS Code (`AppData/Roaming/Code/user/prompts/personal.instructions.md.tmpl`).
Do not duplicate those rules here.
