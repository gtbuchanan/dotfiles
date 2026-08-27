# MCP Servers

This repo registers MCP servers with the agent clients running on each
machine: Claude Code via `claude mcp add` calls in install scripts,
VS Code (Copilot) via `mcp.servers` in the shared VS Code settings
template, and GitHub Copilot CLI via a chezmoi-managed
`~/.copilot/mcp-config.json`. Currently provisioned on Windows and
Android only — Linux and macOS would need install scripts added.

## File Map

| File                                                                                                                                                                | Role                                                                    |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| [`home/.chezmoiscripts/android/run_onchange_after_claude-configure.sh`](../home/.chezmoiscripts/android/run_onchange_after_claude-configure.sh)                     | Android: HTTP MCP registrations (microsoft-learn)                       |
| [`home/.chezmoiscripts/android/run_onchange_after_mcp-readonly-install.sh.tmpl`](../home/.chezmoiscripts/android/run_onchange_after_mcp-readonly-install.sh.tmpl)   | Android: install + register `readonly-mcp` (stdio); `setsid` workaround |
| [`home/.chezmoiscripts/windows/run_onchange_after_claude-configure.ps1.tmpl`](../home/.chezmoiscripts/windows/run_onchange_after_claude-configure.ps1.tmpl)         | Windows: HTTP MCP registrations (folded into Claude configure)          |
| [`home/.chezmoiscripts/windows/run_onchange_after_mcp-readonly-install.ps1.tmpl`](../home/.chezmoiscripts/windows/run_onchange_after_mcp-readonly-install.ps1.tmpl) | Windows: install + register `readonly-mcp` (stdio)                      |
| [`home/.chezmoitemplates/vscode_settings.json`](../home/.chezmoitemplates/vscode_settings.json)                                                                     | VS Code `mcp.servers` config (shared across OSes)                       |
| [`home/dot_claude/settings.json.tmpl`](../home/dot_claude/settings.json.tmpl)                                                                                       | Claude permissions `allow` list — explicitly enumerates every MCP tool  |
| [`home/dot_copilot/mcp-config.json`](../home/dot_copilot/mcp-config.json)                                                                                           | Copilot CLI `mcpServers` config (shared across OSes)                    |
| [`package.json`](../package.json)                                                                                                                                   | `@readonly-mcp/core` pin (GitHub-spec)                                  |

## Servers

### `readonly` (stdio)

The [readonly-mcp/core](https://github.com/readonly-mcp/core) server
exposes allowlisted read-only access to common CLI tools so agents can
inspect state without `Bash` permission prompts. See the upstream repo
for the current tool allowlist.

Installed via the pnpm-globals template, then registered per client:

- **Claude**: each OS's `mcp-readonly-install` script registers the
  binary as a user-scope stdio MCP.
- **VS Code**: a `mcp.servers.readonly` entry in the shared
  [`vscode_settings.json`](../home/.chezmoitemplates/vscode_settings.json) template, applied to every OS that deploys
  VS Code settings.
- **Copilot CLI**: an `mcpServers.readonly` entry in
  [`home/dot_copilot/mcp-config.json`](../home/dot_copilot/mcp-config.json), deployed to
  `~/.copilot/mcp-config.json` on every OS.

The package is pinned in [`package.json`](../package.json) as a GitHub-spec dep. See
[`pnpm-globals.md`](pnpm-globals.md) for how GitHub-spec pins flow
through the install template.

### `microsoft-learn` (HTTP)

Microsoft's hosted HTTP MCP. Registered per client:

- **Claude**: each OS's `claude-configure` script registers the
  endpoint as a user-scope HTTP MCP.
- **Copilot CLI**: an `mcpServers.microsoft-learn` entry in
  [`home/dot_copilot/mcp-config.json`](../home/dot_copilot/mcp-config.json).

Being hosted, it needs no local install — the declarative clients pick
it up from a chezmoi apply with no binary to provision first.

## Cross-Tool Divergences

The clients have meaningfully different registration mechanisms:

- **Claude** registers imperatively — the install scripts shell out
  to `claude mcp add`. Permissions are enumerated explicitly in
  `settings.json` under `permissions.allow`; see
  [`claude-code.md`](claude-code.md) for why only MCP tools are
  auto-allowed and built-ins aren't.
- **VS Code** reads `mcp.servers` declaratively from user settings.
  The shared template includes the registration, so any platform that
  deploys VS Code settings picks it up.
- **Copilot CLI** reads `mcpServers` declaratively from
  `~/.copilot/mcp-config.json`. `copilot mcp add` exists but only
  writes that same file, so chezmoi owns it directly and no install
  script is needed. The file is checked in verbatim rather than
  templated — nothing in it varies by host or OS.

This means the Claude install scripts need to run any time the set of
MCP servers changes, while VS Code and Copilot CLI follow immediately
from a chezmoi apply. The Claude scripts are gated by `run_onchange_*`
hashing, so they re-execute when the rendered registration command
changes.

Tool permissions diverge too. Claude auto-allows each MCP tool by name
in `permissions.allow`, but Copilot CLI has no persistent equivalent —
its config exposes `allowedUrls`, `deniedUrls`, and `trustedFolders`,
and tool approval is flag-only (`--allow-tool 'readonly'`). So readonly
tools still prompt in a default `copilot` session.

## Gaps

- **Linux/macOS** have the VS Code and Copilot CLI registrations
  deployed but no `readonly-mcp` binary installed and no Claude
  registration script. If Claude or Copilot is used there, add an
  install script modeled on the Windows or Android version.
- **`microsoft-learn`** is registered with Claude and Copilot CLI;
  whether VS Code should also register it hasn't been decided.
