# SSH

SSH is set up differently on every platform this repo targets — native
on Linux/macOS, native Microsoft OpenSSH on Windows (with Git and WSL
both routed back to that single agent), and a Termux-popup askpass on
Android. The shared piece is a deliberately minimal `~/.ssh/config`
that lets host-specific entries drop in next to it without being
checked in.

## File Map

| File | Role |
|---|---|
| `home/.chezmoiscripts/android/run_onchange_before.sh.tmpl` | Installs `openssh` from Termux's pkg repo |
| `home/.chezmoiignore` | Gates `ssh-askpass-termux` to Android |
| `home/dot_bash_profile.tmpl` | Starts the WSL→Windows agent bridge on WSL hosts |
| `home/dot_config/wezterm/wezterm.lua.tmpl` | Disables WezTerm's built-in agent mux so the native agent stays in charge |
| `home/dot_gitconfig.tmpl` | Sets `core.sshCommand = ssha` on Android so Git auto-starts ssh-agent |
| `home/dot_local/bin/.chezmoiignore` | Gates `ssh-agent-pipe` to WSL |
| `home/dot_local/bin/executable_ssh-agent-pipe` | WSL→Windows agent bridge (socat + npiperelay) |
| `home/dot_local/bin/executable_ssh-askpass-termux` | Android SSH_ASKPASS via `termux-dialog` |
| `home/dot_profile.tmpl` | Wires `SSH_ASKPASS` + `SSH_ASKPASS_REQUIRE` on Android |
| `home/private_dot_ssh/config.tmpl` | Top-level config: `Include ./*.conf` + macOS keychain |
| `home/winget.yaml.tmpl` | Windows: removes built-in OpenSSH client, installs Preview build, starts agent service, sets `GIT_SSH` |

## Shared ssh_config

The committed `~/.ssh/config` does essentially two things: it pulls in
sibling `*.conf` files via `Include`, and on macOS it tells the agent
to persist keys in the system keychain. The include pattern is the key
piece — it lets each host drop its own infrastructure-specific entries
into `~/.ssh/something.conf` without those entries ever needing to land
in this repo. Anything you don't want public stays out of chezmoi.

## Linux and macOS

Nothing in this repo intervenes in SSH startup on native Linux or
macOS — whatever the OS ships handles agent and key flow. The only
SSH-related touch is `UseKeychain yes` on macOS so the system keychain
persists keys across restarts.

## WSL → Windows Agent Bridge

Keys live in the Windows agent, not in WSL — that way the same key
material backs Git and `ssh` from both sides without copying anything.
WSL just needs a way to talk to the Windows agent's named pipe;
`ssh-agent-pipe` sets that up at login (adapted from
[Jaykul's gist](https://gist.github.com/Jaykul/19e9f18b8a68f6ab854e338f9b38ca7b)).
`.bash_profile` sources it on WSL hosts only.

The bridge is gated to WSL via `home/dot_local/bin/.chezmoiignore` so
the wrapper doesn't pollute non-WSL Linux hosts where it would do
nothing. Its two runtime dependencies are managed here too: `socat` by
the Linux before-script (WSL is Linux from chezmoi's perspective) and
`npiperelay.exe` by the Windows winget manifest.

## Windows

The intent on Windows is simple: **the Microsoft-native OpenSSH client
is the canonical client on every Windows host**, including the one Git
uses. Git for Windows ships its own `ssh.exe` and prefers it by
default — but routing Git through Windows-native SSH means Git, manual
`ssh`, WSL (via the bridge above), and anything else all share one
agent and one key store.

The winget DSC manifest does three things to make that work, all
because the OS defaults aren't quite right out of the box:

- **Newer OpenSSH binaries.** The OpenSSH client shipped as a Windows
  optional capability lags upstream by a wide margin. The manifest
  removes that capability and installs Microsoft's preview winget
  package, which tracks upstream much more closely.
- **Agent service running.** The Windows `ssh-agent` service ships
  disabled. The manifest enables it and sets it to start at boot —
  without this the WSL bridge has nothing to connect to.
- **Git uses the Windows-native client.** Setting `GIT_SSH`
  machine-wide to the OpenSSH binary overrides Git for Windows'
  preference for its bundled `ssh.exe`, so Git transports route
  through the same client and agent as everything else.

## Android

OpenSSH's default behavior is to prompt for the passphrase on the
controlling TTY, which hits the same two problems the GPG side did
(see [`gpg-signing.md`](gpg-signing.md#android-termux)): Claude Code's
terminal handling mangles the prompt, and Android password-manager
autofill doesn't work against TTY input — it expects a native field.
Routing through a native popup sidesteps both.

`SSH_ASKPASS` points at `ssh-askpass-termux`, which shells out to
`termux-dialog` for the popup. `SSH_ASKPASS_REQUIRE=force` makes
OpenSSH always go through askpass even when a TTY is available —
otherwise it would prefer the TTY prompt and the popup would never
fire.

Like the GPG pinentry, this depends on the **Termux:API** companion
app from F-Droid for `termux-dialog` to surface UI.

Separately, Git on Android uses `core.sshCommand = ssha` —
[Termux's wrapper](https://wiki.termux.com/wiki/Remote_Access#SSH_Agent)
that ensures `ssh-agent` is running before invoking `ssh`, so the
agent spins up on first use without a manual `ssh-add` step.

## WezTerm

WezTerm has a built-in agent mux that can override `SSH_AUTH_SOCK` in
panes it spawns. Disabling it via `mux_enable_ssh_agent = false`
leaves the platform-native agent path alone — the WSL bridge socket,
the Windows agent pipe, or whatever the host's login shell set up.
