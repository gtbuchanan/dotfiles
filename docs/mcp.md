# MCP Servers

This repo registers MCP servers with the agent clients running on each
machine: Claude Code via `claude mcp add` calls in install scripts,
VS Code (Copilot) via `mcp.servers` in the shared VS Code settings
template. Currently provisioned on Windows and Android only — Linux
and macOS would need install scripts added.

## File Map

| File | Role |
|---|---|
| [`home/.chezmoiscripts/android/run_onchange_after_claude-configure.sh`](../home/.chezmoiscripts/android/run_onchange_after_claude-configure.sh) | Android: HTTP MCP registrations (microsoft-learn) |
| [`home/.chezmoiscripts/android/run_onchange_after_mcp-readonly-install.sh.tmpl`](../home/.chezmoiscripts/android/run_onchange_after_mcp-readonly-install.sh.tmpl) | Android: install + register `readonly-mcp` (stdio); `setsid` workaround |
| [`home/.chezmoiscripts/windows/run_onchange_after_claude-configure.ps1.tmpl`](../home/.chezmoiscripts/windows/run_onchange_after_claude-configure.ps1.tmpl) | Windows: HTTP MCP registrations (folded into Claude configure) |
| [`home/.chezmoiscripts/windows/run_onchange_after_mcp-readonly-install.ps1.tmpl`](../home/.chezmoiscripts/windows/run_onchange_after_mcp-readonly-install.ps1.tmpl) | Windows: install + register `readonly-mcp` (stdio) |
| [`home/.chezmoitemplates/vscode_settings.json`](../home/.chezmoitemplates/vscode_settings.json) | VS Code `mcp.servers` config (shared across OSes) |
| [`home/dot_claude/settings.json.tmpl`](../home/dot_claude/settings.json.tmpl) | Claude permissions `allow` list — explicitly enumerates every MCP tool |
| [`package.json`](../package.json) | `@readonly-mcp/core` pin (GitHub-spec) |

## Servers

### `readonly` (stdio)

The [readonly-mcp/core](https://github.com/readonly-mcp/core) server
exposes allowlisted read-only access to common CLI tools so agents can
inspect state without `Bash` permission prompts. See the upstream repo
for the current tool allowlist.

Installed via the pnpm-globals template, then registered with both
Claude and VS Code:

- **Claude**: each OS's `mcp-readonly-install` script registers the
  binary as a user-scope stdio MCP.
- **VS Code**: a `mcp.servers.readonly` entry in the shared
  [`vscode_settings.json`](../home/.chezmoitemplates/vscode_settings.json) template, applied to every OS that deploys
  VS Code settings.

The package is pinned in [`package.json`](../package.json) as a GitHub-spec dep. See
[`pnpm-globals.md`](pnpm-globals.md) for how GitHub-spec pins flow
through the install template.

### `microsoft-learn` (HTTP)

Microsoft's hosted HTTP MCP. Registered with Claude only by each OS's
`claude-configure` script; not added to VS Code.

## Cross-Tool Divergences

The two clients have meaningfully different registration mechanisms:

- **Claude** registers imperatively — the install scripts shell out
  to `claude mcp add`. Permissions are enumerated explicitly in
  `settings.json` under `permissions.allow`; see
  [`claude-code.md`](claude-code.md) for why only MCP tools are
  auto-allowed and built-ins aren't.
- **VS Code** reads `mcp.servers` declaratively from user settings.
  The shared template includes the registration, so any platform that
  deploys VS Code settings picks it up.

This means the Claude install scripts need to run any time the set of
MCP servers changes, while VS Code follows immediately from a chezmoi
apply. The Claude scripts are gated by `run_onchange_*` hashing, so
they re-execute when the rendered registration command changes.

## Gaps

- **Linux/macOS** have the VS Code `mcp.servers` entry deployed but no
  `readonly-mcp` binary installed and no Claude registration script.
  If Claude or Copilot is used there, add an install script modeled on
  the Windows or Android version.
- **`microsoft-learn`** is currently Claude-only; whether VS Code
  should also register it hasn't been decided.
