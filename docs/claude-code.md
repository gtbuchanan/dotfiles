# Claude Code

Claude Code's setup in this repo spans config (`settings.json` and
related templates), runtime fixes (LSP plugin shims on Windows; ELF
patching on Android), and a Windows-only notification → pane-focus
chain that lets desktop toasts switch focus into the right psmux pane.

## File Map

| File | Role |
|---|---|
| `home/.chezmoiscripts/android/run_onchange_after_claude-code-install.sh.tmpl` | Termux install via the [`claude-code-termux`](https://github.com/gtbuchanan/claude-code-termux) apt package (Renovate-pinned launcher + Claude Code versions; `CLAUDE_CODE_SKIP_SETTINGS=1` so chezmoi keeps `settings.json`) |
| `home/.chezmoiscripts/windows/run_onchange_after_claude-configure.ps1.tmpl` | Plugin install, LSP `.cmd`-shim rewriting, tweakcc patching, `claude-pane://` URL-protocol registration |
| `home/dot_claude/CLAUDE.md.tmpl` | Wrapper that includes shared user instructions + Claude-only sections |
| `home/dot_claude/executable_statusline` | Powerline-style status bar (model, dir, worktree, git state, context %) |
| `home/dot_claude/focus-pane.ps1.tmpl` | `claude-pane://` URL handler — switches psmux pane and brings WezTerm to front |
| `home/dot_claude/notify-input.ps1.tmpl` | Notification hook handler — emits a BurntToast with a `Focus` button |
| `home/dot_claude/settings.json.tmpl` | Claude config (auto-allow MCP tools, plugin enablement, hooks, env, statusLine) |
| `home/dot_claude/symlink_skills` | `~/.claude/skills` → `~/.agents/skills` (see [`agent-config.md`](agent-config.md)) |

## Settings Drift

Claude Code rewrites `~/.claude/settings.json` at runtime — key
reordering, blank-line stripping, auto-set fields like `editorMode`.
Chezmoi sees drift on every apply, so this target needs a `--force`
re-apply whenever its template content changes; everything else
applies normally.

The template intentionally only auto-allows MCP readonly tools, not
built-in tools (Read, Glob, Grep, Agent). Built-ins have no path
restrictions, so auto-allowing them would widen the blast radius of
prompt injection.

## Windows: Plugins and LSP

The Windows `claude-configure` script does several things that can't
sit in `settings.json` because they call `claude plugin`:

1. **Plugin marketplace** — adds `Piebald-AI/claude-code-lsps` so
   `vtsls@claude-code-lsps`, `vue-volar@claude-code-lsps`, etc. are
   resolvable.
2. **Plugin install** — coderabbit, vtsls, vue-volar,
   powershell-editor-services.
3. **`.cmd`-shim rewriting** — Claude Code's plugin manifests
   reference LSP binaries by bare name (`"command": "vtsls"`). On
   Windows, pnpm installs those LSPs as `.cmd` shims, so the bare
   name doesn't resolve. The script rewrites every `.lsp.json` and
   `marketplace.json` to append `.cmd` to known shim commands. See
   [issue #16751](https://github.com/anthropics/claude-code/issues/16751).
4. **tweakcc LSP patch** — `tweakcc --apply --patches fix-lsp-support`
   patches Claude Code's bundled JS to improve LSP-diagnostic
   handling. The script calls `tweakcc --restore` first so a Claude
   upgrade doesn't double-apply or rebase onto stale bytes.

The settings template gates which plugins are enabled.
`vscode-langservers` is intentionally **disabled** because it routes
`.js`/`.mjs` to eslint instead of vtsls — see
[issue #32912](https://github.com/anthropics/claude-code/issues/32912).

## Windows: Notification → Pane Focus

When Claude is idle or waiting for a permission prompt, this repo
surfaces a Windows toast notification with a `Focus` button that
switches the user's terminal directly to the right psmux pane. The
chain crosses several files:

```
settings.json (Notification hook)
  → notify-input.ps1     (resolves the calling Claude's psmux pane,
                          emits BurntToast with a claude-pane:// URL)
  → claude-pane:// URL   (HKCU:\Software\Classes\claude-pane registered
                          by the Windows claude-configure script —
                          *not* by any dot_claude/ file)
  → focus-pane.ps1       (switches psmux + foregrounds WezTerm)
```

The cross-file gotcha worth knowing: the URL-protocol registration
sits in the `claude-configure` PowerShell script alongside the plugin
install, not next to `focus-pane.ps1` itself. Each link in the chain
is self-documenting in its own file.

## Android: claude-code-termux Package

Anthropic ships Claude Code as a bun-compiled glibc ELF with no
android-arm64 build, breaking the npm install path on Termux (see
[issue #50270](https://github.com/anthropics/claude-code/issues/50270)).
The [`claude-code-termux`](https://github.com/gtbuchanan/claude-code-termux)
apt package bypasses npm: it installs a compiled launcher that downloads the
linux-arm64 binary from Anthropic, patches its ELF interpreter to Termux's
glibc loader, and routes embedded-tool re-execs back through the launcher.
The LD_PRELOAD dance, the `CLAUDE_CODE_EXECPATH` patch, the `grun`
vs direct-exec trade-off, and the rpath trap all live in the package — see
its README and `bootstrap.sh` / `patch-execpath.py` for the rationale.

Both the launcher release and the Claude Code binary it fetches are
Renovate-pinned in `home/.chezmoidata/claude-code.yaml`. chezmoi keeps ownership
of `settings.json` rather than letting the package manage it, so the Android
branches below remain the single source for those keys.

The `settings.json` template carries the matching Android branches:

- `LD_PRELOAD` in `env` so subprocesses get termux-exec.
- `autoUpdates: false` so the in-session updater doesn't clobber the
  ELF-patched binary the package installs.
- `statusLine.command` invokes `bash ~/.claude/statusline` explicitly
  so the kernel never resolves the `/usr/bin/env` shebang (no
  termux-exec preload inside glibc claude).
