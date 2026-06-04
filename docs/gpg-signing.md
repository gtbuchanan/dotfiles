# GPG Signing

All commits are GPG-signed. Each OS handles pinentry differently — and
agent/automation contexts need to bypass interactive prompts entirely.
This doc covers the wiring per platform plus the cross-OS convention
for non-interactive signing.

## File Map

| File | Role |
|---|---|
| [`home/.chezmoiscripts/android/run_onchange_before.sh.tmpl`](../home/.chezmoiscripts/android/run_onchange_before.sh.tmpl) | Installs pinentry-termux's runtime dependencies |
| [`home/AppData/Roaming/gnupg/gpg-agent.conf`](../home/AppData/Roaming/gnupg/gpg-agent.conf) | Windows `gpg-agent` config (`allow-loopback-pinentry`) |
| [`home/dot_config/private_git/gpg-wrapper.bat`](../home/dot_config/private_git/gpg-wrapper.bat) | Windows GPG shim; toggles loopback based on caller env |
| [`home/dot_gitconfig.tmpl`](../home/dot_gitconfig.tmpl) | `[gpg] program = …` hookup, per-OS |
| [`home/dot_local/bin/executable_pinentry-termux`](../home/dot_local/bin/executable_pinentry-termux) | Termux pinentry using `termux-dialog` (Android popup) |
| [`home/private_dot_gnupg/gpg-agent.conf.tmpl`](../home/private_dot_gnupg/gpg-agent.conf.tmpl) | Linux/macOS/Android `gpg-agent` config |

## The AI-Agent Convention

For automation contexts (Claude Code, scripted commits, CI), set
`AI_AGENT=1` (or `CLAUDE_CODE`, set automatically by Claude Code)
before invoking `git`. The repo's wrapper logic checks these env vars
and **skips the TTY-loopback override** — gpg defers to system
pinentry, which uses the cached passphrase when available and falls
back to GUI pinentry otherwise. The GUI popup is the design: agents
run commands through non-interactive shells and can't answer terminal
prompts, so on a cache miss the human at the desktop approves through
the GUI and signing proceeds.

The user-level AGENTS.md documents this rule so agents follow it
without per-project reminders.

## Platform Mechanics

### Windows

Windows GPG defaults to GUI pinentry (`pinentry-w32`), which doesn't
work from non-interactive contexts and is wrong for terminal sessions.
[`home/dot_config/private_git/gpg-wrapper.bat`](../home/dot_config/private_git/gpg-wrapper.bat) adjusts behavior by
caller environment:

| Caller env | Wrapper behavior |
|---|---|
| `CLAUDE_CODE` or `AI_AGENT` set | Pass through — default pinentry (cached → no prompt, cache miss → GUI) |
| `GPG_TTY` set, no AI env | Add `--pinentry-mode loopback` — pinentry prompts via current terminal |
| Neither | Pass through — default GUI pinentry |

`gpg-agent.conf` has `allow-loopback-pinentry` so the loopback mode
works at all.

Hooked up via `[gpg] program = ~/.config/git/gpg-wrapper.bat` in
`gitconfig`.

### Linux / macOS

Standard pinentry works (`pinentry-tty`, `pinentry-curses`, or the
system GUI). No wrapper needed. The shared `gpg-agent.conf` only
configures cache timeouts.

`gitconfig` doesn't override `gpg.program` on these platforms — the
default `gpg` on PATH handles signing.

### Android (Termux)

Termux's stock TUI pinentry normally works fine in a regular shell,
but Claude Code's terminal handling mangles its rendering and
keyboard input — so signing inside a Claude session breaks. The repo
sidesteps the conflict by routing pinentry through an Android-native
popup that doesn't share the TUI with the calling terminal at all.

A secondary benefit: Android password manager autofill works
naturally with a native popup. TUI pinentry needs a
password-manager-aware keyboard to fill the field, which not every
manager supports on mobile.

[`home/dot_local/bin/executable_pinentry-termux`](../home/dot_local/bin/executable_pinentry-termux) is a custom
Assuan-protocol pinentry that speaks pinentry's line protocol to
gpg-agent and uses `termux-dialog text -p` to prompt via a native
Android popup (returns JSON, parsed by `jq`).

Wired in via `gpg-agent.conf`'s `pinentry-program` directive (gated
to Android by template conditional):

```
{{- if eq .chezmoi.os "android" }}
pinentry-program {{ .chezmoi.homeDir }}/.local/bin/pinentry-termux
{{- end }}
```

The directive applies to every Termux session, not just Claude — a
small UX trade-off (popup instead of inline TUI prompt) for not
having to detect the caller.

The script's runtime dependencies are installed by the [Termux
before-script](../home/.chezmoiscripts/android/run_onchange_before.sh.tmpl).
The user must also install the **Termux:API** companion app from
F-Droid for `termux-dialog` to surface UI.

The same `AI_AGENT` bypass works here — with a cached passphrase the
agent signs without prompting; on a cache miss the popup fires so
the user can approve.

### WSL

`gitconfig` points `gpg.program` directly at the Windows GPG binary
(`/mnt/c/Program Files/GnuPG/bin/gpg.exe`) so signing uses the
Windows gpg-agent and key store. The Windows wrapper is **not**
invoked — WSL gets a working terminal pinentry through the Windows
agent without it.

This is a small inconsistency: the `AI_AGENT` env var has no effect
on WSL because the wrapper isn't in the call path. If non-interactive
signing from WSL becomes a need, route WSL through the wrapper too.
