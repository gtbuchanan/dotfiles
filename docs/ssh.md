# SSH

SSH is set up differently on every platform this repo targets — native
on Linux/macOS, native Microsoft OpenSSH on Windows (with Git and WSL
both routed back to that single agent), and a Termux-popup askpass on
Android. The shared piece is a deliberately minimal `~/.ssh/config`
that lets host-specific entries drop in next to it without being
checked in.

## File Map

| File                                                                                                                      | Role                                                                                                                   |
| ------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| [`home/.chezmoiignore`](../home/.chezmoiignore)                                                                           | Gates `ssh-askpass-termux` and the agent hook to Android                                                               |
| [`home/.chezmoiscripts/android/run_after_ssh-agent-hook.sh`](../home/.chezmoiscripts/android/run_after_ssh-agent-hook.sh) | Symlinks the agent start hook into `$PREFIX/etc/ssh`                                                                   |
| [`home/.chezmoiscripts/android/run_onchange_before.sh.tmpl`](../home/.chezmoiscripts/android/run_onchange_before.sh.tmpl) | Installs `openssh` from Termux's pkg repo                                                                              |
| [`home/dot_bash_profile.tmpl`](../home/dot_bash_profile.tmpl)                                                             | Starts the WSL→Windows agent bridge on WSL hosts                                                                       |
| [`home/dot_config/wezterm/wezterm.lua.tmpl`](../home/dot_config/wezterm/wezterm.lua.tmpl)                                 | Disables WezTerm's built-in agent mux so the native agent stays in charge                                              |
| [`home/dot_gitconfig.tmpl`](../home/dot_gitconfig.tmpl)                                                                   | Sets `core.sshCommand = ssha` on Android so Git auto-starts ssh-agent                                                  |
| [`home/dot_local/bin/.chezmoiignore`](../home/dot_local/bin/.chezmoiignore)                                               | Gates `ssh-agent-pipe` to WSL                                                                                          |
| [`home/dot_local/bin/executable_bw-session-termux`](../home/dot_local/bin/executable_bw-session-termux)                   | Supplies the Bitwarden vault session the agent hook needs                                                              |
| [`home/dot_local/bin/executable_ssh-agent-pipe`](../home/dot_local/bin/executable_ssh-agent-pipe)                         | WSL→Windows agent bridge (socat + npiperelay)                                                                          |
| [`home/dot_local/bin/executable_ssh-askpass-termux`](../home/dot_local/bin/executable_ssh-askpass-termux)                 | Android SSH_ASKPASS via `termux-dialog`                                                                                |
| [`home/dot_local/bin/symlink_ssh-keygena`](../home/dot_local/bin/symlink_ssh-keygena)                                     | Android: `ssh-keygen` under Termux's agent wrapper, for commit signing                                                 |
| [`home/dot_profile.tmpl`](../home/dot_profile.tmpl)                                                                       | Wires `SSH_ASKPASS` + `SSH_ASKPASS_REQUIRE` on Android                                                                 |
| [`home/private_dot_ssh/config.tmpl`](../home/private_dot_ssh/config.tmpl)                                                 | Top-level config: `Include ./*.conf` + macOS keychain                                                                  |
| [`home/private_dot_ssh/start_agent.sh`](../home/private_dot_ssh/start_agent.sh)                                           | Android: seeds ssh-agent from Bitwarden instead of disk                                                                |
| [`home/winget.yaml.tmpl`](../home/winget.yaml.tmpl)                                                                       | Windows: removes built-in OpenSSH client, installs Preview build, sets the agent service per host type, sets `GIT_SSH` |

## Shared ssh_config

The committed `~/.ssh/config` does essentially three things: it pulls
in sibling `*.conf` files via `Include`, on macOS it tells the agent to
persist keys in the system keychain, and it aliases `gist.github.com`'s
host key to `github.com`'s. The include pattern is the key piece — it
lets each host drop its own infrastructure-specific entries into
`~/.ssh/something.conf` without those entries ever needing to land in
this repo. Anything you don't want public stays out of chezmoi.

The `gist.github.com` entry sets `HostKeyAlias github.com` because gists
share github.com's SSH infrastructure and host keys. Verifying both
against the same `known_hosts` entry means trusting github.com once also
covers the gist-backed `git-repo` externals (`git-unpicked`,
`git-add-mergetool`) — no second interactive host-key prompt, which
would otherwise stall a non-interactive `chezmoi apply`.

## Linux and macOS

Nothing in this repo intervenes in SSH startup on native Linux or
macOS — whatever the OS ships handles agent and key flow. The only
SSH-related touch is `UseKeychain yes` on macOS so the system keychain
persists keys across restarts.

## WSL → Windows Agent Bridge

Keys live in the Windows-side agent, not in WSL — that way the same key
material backs Git and `ssh` from both sides without copying anything.
WSL just needs a way to talk to that agent's named pipe;
`ssh-agent-pipe` sets that up at login (adapted from
[Jaykul's gist](https://gist.github.com/Jaykul/19e9f18b8a68f6ab854e338f9b38ca7b)).
`.bash_profile` sources it on WSL hosts only.

The bridge is gated to WSL via [`home/dot_local/bin/.chezmoiignore`](../home/dot_local/bin/.chezmoiignore) so
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
- **An agent on the standard pipe.** Which agent depends on the host
  type — see below. Either way something must answer
  `\\.\pipe\openssh-ssh-agent`, or the WSL bridge has nothing to
  connect to.
- **Git uses the Windows-native client.** Setting `GIT_SSH`
  machine-wide to the OpenSSH binary overrides Git for Windows'
  preference for its bundled `ssh.exe`, so Git transports route
  through the same client and agent as everything else.

### Windows Agent Ownership

The named pipe is the contract; who serves it varies by host type.

On **work** hosts the Windows `ssh-agent` service does. It ships
disabled, so the manifest enables it and sets it to start at boot.

On **personal** hosts Bitwarden Desktop's SSH agent does, serving keys
straight from the vault so no private key is written to disk. Bitwarden
hardcodes the same pipe name, so the two agents cannot coexist — the
manifest sets the Windows service to `Disabled`/`Stopped` on personal
hosts to get out of its way. This is also why
[`bootstrap.ps1`](../bootstrap.ps1) checks that an agent is serving a
key before handing off to chezmoi.

`GIT_SSH` still points at the native client, so Git is unaffected.

The WSL bridge is **untested against Bitwarden**. It should be
unaffected — `ssh-agent-pipe` relays by pipe name, not to a particular
agent — but Bitwarden implements the pipe itself rather than reusing
the Windows service's, and a difference in pipe mode could break
npiperelay even though the name matches. No WSL distro on the host
where this was set up had the bridge provisioned, so the claim has
never been exercised. Verify before relying on it.

The trade is availability. The Windows service started at boot and
never asked for anything; Bitwarden must be running and unlocked or
every SSH operation fails — Git, manual `ssh`, and WSL alike.

## Android

OpenSSH's default behavior is to prompt for the passphrase on the
controlling TTY, which hits the same two problems the GPG side did
(see [`gpg.md`](gpg.md#android-termux)): Claude Code's
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

### Bitwarden-Backed Keys on Android

Rather than keeping a private key on the device, Android seeds the
agent from the Bitwarden vault. `ssha` sources Termux's
`$PREFIX/libexec/source-ssh-agent.sh`, which sources
`$PREFIX/etc/ssh/start_agent.sh` if it exists for the express purpose of
letting `start_agent()` be replaced. `start_agent.sh` overrides it to
pull every vault item carrying an SSH private key and stream each one
into `ssh-add -` on stdin, so the key reaches the agent's memory without
ever being written to disk. Because `ssha` is also Git's
`core.sshCommand`, Git inherits this with no additional wiring.

The hook lives at `~/.ssh/start_agent.sh` because chezmoi only manages
`$HOME`; the `run_after_ssh-agent-hook.sh` script symlinks it into the
prefix on every apply, which also restores it if a Termux reinstall wipes
`$PREFIX`.

Consequences worth knowing:

- The hook runs `bw sync` before listing items. The CLI serves a local
  copy of the vault and refreshes it only on an explicit sync — not on
  unlock, and not on list — so a key added from another device would
  otherwise stay invisible to the hook indefinitely. The sync is
  best-effort, so an offline cold start still proceeds from cache.
- Keys are added with no lifetime. `source-ssh-agent.sh` calls
  `start_agent` only when no agent is reachable — when the agent is up
  but empty it runs a bare `ssh-add`, which the hook cannot override.
  Expiring keys would land on that path and search for on-disk keys that
  aren't there. The agent's own lifetime bounds exposure instead. For
  per-use confirmation, add `-c` to the `ssh-add` call; `SSH_ASKPASS`
  already routes to a Termux popup, so every signature would prompt.
- Seeding unlocks the vault, so the first agent start of a session costs
  a fingerprint prompt and a few seconds of `bw` startup. If the vault is
  locked or unreachable, the hook falls back to a plain `ssh-add` so
  behavior degrades to stock rather than breaking `ssh`.

The vault session itself comes from `bw-session-termux`, which wraps the
session key at rest under a hardware-keystore-derived key and gates reads
behind a fingerprint prompt.

## WezTerm

WezTerm has a built-in agent mux that can override `SSH_AUTH_SOCK` in
panes it spawns. Disabling it via `mux_enable_ssh_agent = false`
leaves the platform-native agent path alone — the WSL bridge socket,
the Windows agent pipe, or whatever the host's login shell set up.
