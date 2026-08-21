# SSH

SSH is set up differently on every platform this repo targets — native
on Linux/macOS, native Microsoft OpenSSH on Windows (with Git and WSL
both routed back to that single agent), and a Termux-popup askpass on
Android. The shared piece is a deliberately minimal `~/.ssh/config`
that lets host-specific entries drop in next to it without being
checked in.

## File Map

| File                                                                                                                                | Role                                                                                                                   |
| ----------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| [`home/.chezmoiexternal.yaml.tmpl`](../home/.chezmoiexternal.yaml.tmpl)                                                             | Clones the private host inventory to `~/.ssh/hosts` on personal hosts                                                  |
| [`home/.chezmoiignore`](../home/.chezmoiignore)                                                                                     | Gates `ssh-askpass-termux` and the agent hook to Android, the `*.pub` halves to personal                               |
| [`home/.chezmoiscripts/android/run_after_ssh-agent-hook.sh`](../home/.chezmoiscripts/android/run_after_ssh-agent-hook.sh)           | Symlinks the agent start hook into `$PREFIX/etc/ssh`                                                                   |
| [`home/.chezmoiscripts/android/run_onchange_before.sh.tmpl`](../home/.chezmoiscripts/android/run_onchange_before.sh.tmpl)           | Installs `openssh` from Termux's pkg repo                                                                              |
| [`home/dot_bash_profile.tmpl`](../home/dot_bash_profile.tmpl)                                                                       | Starts the WSL→Windows agent bridge on WSL hosts                                                                       |
| [`home/dot_config/powershell/profile.d/40-integrations.ps1.tmpl`](../home/dot_config/powershell/profile.d/40-integrations.ps1.tmpl) | Points `SSH_ASKPASS` at the Bitwarden helper on personal Windows                                                       |
| [`home/dot_config/wezterm/wezterm.lua.tmpl`](../home/dot_config/wezterm/wezterm.lua.tmpl)                                           | Disables WezTerm's built-in agent mux so the native agent stays in charge                                              |
| [`home/dot_gitconfig.tmpl`](../home/dot_gitconfig.tmpl)                                                                             | Sets `core.sshCommand = ssha` on Android so Git auto-starts ssh-agent                                                  |
| [`home/dot_local/bin/.chezmoiignore`](../home/dot_local/bin/.chezmoiignore)                                                         | Gates `ssh-agent-pipe` to WSL, the Bitwarden askpass to personal Windows                                               |
| [`home/dot_local/bin/bw-session-windows.ps1`](../home/dot_local/bin/bw-session-windows.ps1)                                         | Windows: DPAPI-cached vault session, so unlocks are amortized                                                          |
| [`home/dot_local/bin/executable_bw-session-termux`](../home/dot_local/bin/executable_bw-session-termux)                             | Supplies the Bitwarden vault session the agent hook needs                                                              |
| [`home/dot_local/bin/executable_ssh-agent-pipe`](../home/dot_local/bin/executable_ssh-agent-pipe)                                   | WSL→Windows agent bridge (socat + npiperelay)                                                                          |
| [`home/dot_local/bin/executable_ssh-askpass-termux`](../home/dot_local/bin/executable_ssh-askpass-termux)                           | Android SSH_ASKPASS via `termux-dialog`                                                                                |
| [`home/dot_local/bin/ssh-askpass-bw.cmd`](../home/dot_local/bin/ssh-askpass-bw.cmd)                                                 | Windows SSH_ASKPASS entry point; `SSH_ASKPASS` needs an executable                                                     |
| [`home/dot_local/bin/ssh-askpass-bw.ps1`](../home/dot_local/bin/ssh-askpass-bw.ps1)                                                 | Resolves a host password from the vault, else prompts via a dialog                                                     |
| [`home/dot_local/bin/symlink_ssh-keygena`](../home/dot_local/bin/symlink_ssh-keygena)                                               | Android: `ssh-keygen` under Termux's agent wrapper, for commit signing                                                 |
| [`home/dot_profile.tmpl`](../home/dot_profile.tmpl)                                                                                 | Wires `SSH_ASKPASS` + `SSH_ASKPASS_REQUIRE` on Android                                                                 |
| [`home/private_dot_ssh/config.tmpl`](../home/private_dot_ssh/config.tmpl)                                                           | Top-level config: both `Include`s, the tag-driven `Match` blocks, macOS keychain                                       |
| [`home/private_dot_ssh/legacy.pub`](../home/private_dot_ssh/legacy.pub)                                                             | Public half of the pre-migration key, pinned by the `:legacy:` flag                                                    |
| [`home/private_dot_ssh/primary.pub`](../home/private_dot_ssh/primary.pub)                                                           | Public half of the agent-held primary key, so `-Y sign` can select it                                                  |
| [`home/private_dot_ssh/start_agent.sh`](../home/private_dot_ssh/start_agent.sh)                                                     | Android: seeds ssh-agent from Bitwarden instead of disk                                                                |
| [`home/winget.yaml.tmpl`](../home/winget.yaml.tmpl)                                                                                 | Windows: removes built-in OpenSSH client, installs Preview build, sets the agent service per host type, sets `GIT_SSH` |

## Shared ssh_config

The committed `~/.ssh/config` does essentially three things: it pulls
in sibling `*.conf` files via `Include`, on macOS it tells the agent to
persist keys in the system keychain, and it routes GitHub over that
service's `:443` endpoint. The include pattern is the key piece — it
lets each host drop its own infrastructure-specific entries into
`~/.ssh/something.conf` without those entries ever needing to land in
this repo. Anything you don't want public stays out of chezmoi.

One entry covers `github.com` and `gist.github.com` together. It is
unconditional rather than reserved for networks that need it: 443 is no
worse than 22 where both are open, and the failure it avoids — a clone
that hangs until it times out — reads like anything but a blocked port.
`HostKeyAlias` is the piece the `git-repo` externals depend on, since a
second host-key prompt would stall a non-interactive `chezmoi apply`.
That entry's comment in
[`config.tmpl`](../home/private_dot_ssh/config.tmpl) carries the
mechanics and the one case where 443 loses to 22.

## Private SSH Host Inventory

Host definitions live in a separate private repo, `gtbuchanan/ssh-hosts`,
cloned to `~/.ssh/hosts/` by a `git-repo` external gated to personal
hosts. `config.tmpl` picks them up with `Include hosts/*.conf`, listed
after `Include ./*.conf` so an unversioned local file still wins on
conflicts — ssh takes the first value obtained for each keyword. A glob
matching nothing is not an error, so the include is inert on hosts
without the clone.

The alternative was committing the definitions here encrypted. A public
repo archives its ciphertext permanently — forks, clones, GH Archive —
so anything published stays exposed even after deletion, and re-keying
later cannot undo that for what was already pushed. A separate repo
removes the exposure rather than shrinking it, and keeps diffs readable
and mergeable. A submodule would have worked too, but its pinned SHA
means every private host edit needs a pointer-bump commit here, which
publishes the timing of private config changes.

The split between the two repos is worth stating precisely, because it
decides where any new piece belongs:

- **This repo holds identity and behavior.** Public keys, and the
  `Match` blocks deciding what each host flag implies. Public keys are
  not secret by construction — they go to every server you touch — and
  `.chezmoi.yaml.tmpl` already carries the ed25519 signing key in the
  clear.
- **The private repo holds topology.** Hostnames, users, ports, and the
  flags each host claims. Nothing there describes behavior.

## SSH Host Tags

Hosts in the private repo describe themselves with flags; this repo
attaches behavior to each flag. That keeps the host list private while
the policy stays reviewable here.

ssh allows only **one `Tag` per host** — a second `Tag` line is silently
ignored, and `Tag a,b` parses as a single literal tag rather than a
list. Independent axes therefore have to share one string. Hosts use a
colon-wrapped flag list (`Tag :shell:legacy:`) matched by glob, and the
wrapping is what makes matching order-independent: `*:legacy:*` hits
whether `legacy` is first, last, or alone. `Match tagged` does accept a
pattern list and supports negation, so widen or exclude on the matching
side rather than tagging a host twice.

Every block needs a positive pattern. A bare `*` also matches the empty
tag on untagged hosts such as `github.com`, and a `RemoteCommand` there
would break Git.

| Flag         | Meaning                                                                 | Effect                                               |
| ------------ | ----------------------------------------------------------------------- | ---------------------------------------------------- |
| `:legacy:`   | Host has not migrated to the primary ed25519 key                        | Pins `~/.ssh/legacy.pub` with `IdentitiesOnly yes`   |
| `:password:` | Host only accepts a password, typically an appliance                    | Disables key auth; password served via `SSH_ASKPASS` |
| `:shell:`    | An interactive login lands in a general-purpose shell, not a vendor CLI | Starts or attaches a persistent tmux session         |

`:shell:` is opt-in rather than opt-out because the failure modes are
not symmetric: forgetting the flag costs a tmux session, while sending a
`RemoteCommand` to an appliance whose shell is restricted or absent can
break the session outright.

The tmux block is additionally gated on `command ""` so it applies only
to interactive sessions and leaves file transfers alone; the `:legacy:`
block deliberately is not, since transfers must authenticate too. Each
block's comment in [`config.tmpl`](../home/private_dot_ssh/config.tmpl)
carries the mechanics.

`Tag`, `Match tagged`, and the `command` criterion all require OpenSSH
9.4 or newer on the client; the remote's version is irrelevant.

To add a host, commit a `*.conf` to the private repo with its
`HostName`, `User`, and flags. Nothing in this repo changes unless the
host needs a flag that doesn't exist yet.

Flags are for settings shared by a class of hosts; genuinely
host-specific ones can be written inline in the private repo instead,
since a flag matching a set of one buys nothing. Inline directives win —
the private `*.conf` files are included before these `Match` blocks, and
ssh takes the first value obtained — and they win per keyword rather
than per block, so a host that inlines its own `RemoteCommand` still
picks up `RequestTTY` from the flag block.

## SSH Agent Forwarding

No host enables `ForwardAgent` through this config, and none should.
Forwarding is opt-in per invocation — `ssh -A <host>` — deliberately not
a host flag.

Forwarding publishes a socket on the remote that anyone able to open it
can use to sign challenges as you: root there, and any process running
as your user. No key material crosses — the remote relays signature
requests back to the local agent — so exposure ends with the connection.
What it does not bound is scope. The socket authenticates to every host
that trusts the key, so forwarding to a low-value host lends it the
authority of your strongest one. A flag would make that asymmetry
standing; an `-A` typed when it's needed keeps it to a window you chose.

The remote's supply chain is the practical threat, not its
administrator. Anything running as you there inherits `SSH_AUTH_SOCK`
from the environment — build steps, package post-install hooks, an agent
started in that shell. Container hosts widen this further: reaching the
container runtime's socket is generally equivalent to root on the host,
so every container holding that socket is a path to the forwarded agent.

### SSH Agent Forwarding Prompts

As of 2026-08 the Bitwarden agent raises an approval dialog for every
forwarded signature, even under _Remember until vault is locked_ — that
cache covers local requests only. Worth knowing, not worth relying on:
`main` in `bitwarden/clients` carries a fingerprint-keyed cache for
forwarded approvals in
`apps/desktop/src/autofill/services/ssh-agent.service.ts`, which would
turn per-signature prompting into one prompt per host per unlock with no
notice. Treat today's behavior as a happy accident rather than a
control.

The dialog identifies neither the destination nor the requesting host —
only a generic forwarding warning — so an approval granted during your
own work can't be distinguished from one solicited alongside it.

### SSH Agent Forwarding Into tmux

Hosts flagged `:shell:` reattach a persistent tmux that outlives the
connection which started it. Panes keep whatever `SSH_AUTH_SOCK` the
server was launched with, so a reattached session points at a socket
that died with the previous connection — forwarding looks broken when it
isn't. The `:shell:` `RemoteCommand` therefore points a fixed path at
the live socket and exports that instead, giving long-lived panes a name
that stays valid across reattaches. It is inert when nothing was
forwarded.

### Blocked Outbound 22 Versus Broken Forwarding

This config rides 443, but a host you SSH into reads its own config, not
this one, and a filtered network there drops outbound 22 while leaving
443 open. A clone from the remote then hangs until it times out, which
looks like broken agent forwarding despite never reaching
authentication.

Separate the two before touching the agent. A bare TCP probe to the
forge on 22 settles the port question. `ssh -A <host> 'ssh-add -l'`
settles the forwarding question independently — it lists the local
agent's keys as seen from the remote, and supplying a command defeats
the `:shell:` block's `command ""` guard, so the tmux `RemoteCommand`
stays out of the way.

Where the port is at fault, an unmanaged remote needs the same GitHub
entry described under [Shared ssh_config](#shared-ssh_config) in its own
`~/.ssh/config` — or, with no config change at all, the one-off URL
`ssh://git@ssh.github.com:443/<owner>/<repo>.git`.

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

On **work** hosts the Windows `ssh-agent` service does.
It ships disabled,
so the manifest enables it and sets it to start at boot —
and [`bootstrap.ps1`](../bootstrap.ps1) enables it earlier still,
because it has to seed the agent before the apply that would.

Dashlane has no agent of its own,
but it doesn't need one.
`ssh-add` accepts a key on stdin,
so bootstrap streams the vault copy straight into the service
and no private key is ever written to disk.
The service persists keys per-user in the registry,
so that one seed survives reboots —
nothing re-seeds at login,
and the vault is only read once per host.

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

### Bitwarden-Backed Passwords on Windows

Some hosts only offer password auth. Rather than copying those out of
the vault by hand, `SSH_ASKPASS` points at a helper that looks them up:
OpenSSH passes the prompt as the sole argument and reads the secret from
the helper's stdout, so nothing else may be written there.

The chain is `SSH_ASKPASS` → `ssh-askpass-bw.cmd` → `ssh-askpass-bw.ps1`
→ `bw-session-windows.ps1` → `bw`. The `.cmd` exists only because
`SSH_ASKPASS` must name an executable and a `.ps1` is not one.

`SSH_ASKPASS_REQUIRE` is **`force`**, not `prefer`. `prefer` only
consults an askpass when `DISPLAY` is set, which it never is on Windows,
so it would read as configured and silently never fire. Because `force`
routes _every_ prompt through the helper — Git's included, and hosts
absent from the vault — the helper always answers, falling back to a
native dialog rather than failing, since a failure aborts the connection
outright. The dialog rather than `Read-Host` because ssh owns the
helper's stdout and may redirect its stdin.

### Host Keys Under the Windows Askpass

`force` also routes host key verification here, and that one cannot be
answered honestly. `SSH_ASKPASS` names a bare executable with no
arguments, so reaching PowerShell needs a `.cmd` shim — and `cmd.exe`
ends its command line at the first newline. ssh's prompt is several
lines, so the fingerprint and the `yes/no` question are discarded before
the script starts; only the opening `The authenticity of host …` line
survives. Approving a key whose fingerprint cannot be shown would defeat
the check the prompt exists to perform.

So the helper recognises those prompts, declines with `no`, and shows a
dialog explaining how to accept the host deliberately:

```powershell
$env:SSH_ASKPASS_REQUIRE = 'never'; ssh <host>
```

That gives ssh's own prompt, fingerprint included; once accepted the key
is in `known_hosts` and the situation does not recur for that host.

`ssh-keyscan` is offered only for comparing a fingerprint against one
read off the device. It is not a substitute for the above: it fetches
the key over a _separate_ connection, so under an active
machine-in-the-middle it can show a different key than the session is
negotiating, and appending its output to `known_hosts` verifies nothing
at all.

Fixing this properly means dropping `cmd.exe` from the path, which needs
a compiled launcher that forwards `argv` to PowerShell intact — a build
step this repo does not otherwise have.

Mark a host by adding a `ssh://<host>` URI to its vault item. Either the
alias or the `HostName` works: the helper tries the host named in the
prompt, the `HostName` that `ssh -G` resolves it to, and the short name,
in that order. Resolving through ssh itself is what makes the choice
free — whether OpenSSH names a host by alias or by resolved `HostName`
is not knowable from the prompt, and without the resolution step an alias
prompt can never reach an FQDN-stored URI.

Matching is done in the helper, **not** with `bw list --url`, which
honours each item's own URI match detection. That defaults to base
domain, so querying `ssh://sw01.home.gbcelt.com` also returns every
unrelated item under `gbcelt.com` — observed returning five items, four
of them different hosts. For a password prompt that means handing one
host's credential to another. Setting the target item to Exact does not
help, because the loose settings live on the _other_ items; making
`--url` safe would need Exact across the whole vault, and one item added
later with defaults would silently undo it. So `--search` is a prefilter
only, the URI is compared exactly, and an ambiguous result is refused
rather than guessed.

Expect several seconds per lookup. Roughly four of those are Node
starting up before the vault is touched, so neither the filter nor the
vault size is the lever; only caching the password itself would help,
which is not worth it for hosts reached this rarely.

### Bitwarden Session Cache on Windows

`bw` never persists the key that decrypts vault items — `bw unlock`
returns it and expects the caller to carry it in `BW_SESSION` — so
without a cache every lookup means another unlock, and under
`SSH_ASKPASS` that is a biometric prompt per connection.
`bw-session-windows.ps1` caches it under DPAPI with a sliding idle
window, and offers the same `get|check|lock|reset|status` surface as its
Termux counterpart.

The unlock itself comes from `bitwarden-cli-bio`, which asks the desktop
app for a session over the IPC channel the browser extension uses. The
official CLI has no biometric unlock, so the alternative is feeding it a
master password. Bitwarden has an open PR adopting the same mechanism
upstream; **this wrapper is a bridge until that lands**, at which point
it should collapse back to plain `bw`.

Two of its behaviours are worth knowing before changing anything.
`--nointeraction` suppresses the biometric prompt as well as the
master-password one, so the unlock must run without it and only the
query carries it. And the unlock's exit code is unreliable — a denied
prompt falls through to a master-password prompt that dies on closed
stdin and still exits `0` — so success is judged by whether stdout holds
something session-key shaped.

This is deliberately weaker than
[`bw-session-termux`](../home/dot_local/bin/executable_bw-session-termux),
which derives its key-encryption key from a signature made inside the
Android hardware keystore and so demands a fingerprint per read. The
Windows counterpart is `KeyCredentialManager`, whose key lives in the
TPM — but that is the Windows Hello **for Business** API, and these hosts
run a convenience PIN on a domain-joined account with WHfB not deployed
(`NgcSet: NO`, `AllowDomainPINLogon: 1`). No container exists for it to
open, so it is unavailable rather than merely inconvenient.
`KeyCredentialManager.IsSupportedAsync` returning true is misleading: it
reports device capability, not account provisioning.

DPAPI therefore binds to the user identity rather than to presence — any
process running as this user can unseal the cache with no prompt. It
defends a copied cache file, a second account, and offline disk access,
and nothing against code already running as you. A consent-style Hello
gate would not change that, since DPAPI still unseals for anything that
skips the prompt and calls `Unprotect` directly. Exposure is bounded by
the idle window rather than by the wrapping, which is why the window is
short; the expiry is bound as the DPAPI entropy, so editing it in the
file breaks decryption instead of extending it — the role additional
authenticated data plays in the Termux cache.

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

Because `force` routes _every_ prompt here, the script sorts them by
shape rather than assuming each is a secret:

- **Host keys.** `Are you sure you want to continue connecting
(yes/no/[fingerprint])?` is a question, not a secret, so it gets a
  confirm dialog, whose hint renders as body text — the host, address,
  and full fingerprint wrapped and legible. ssh accepts a third answer,
  the expected fingerprint, which a text field could return and two
  buttons cannot; but `termux-dialog` draws a text field's hint as a
  _placeholder_, truncated mid-fingerprint and erased the moment typing
  starts, leaving nothing to compare against. Being able to read the key
  beats being able to paste it, so `[fingerprint]` is stripped from the
  question shown rather than offered and not delivered. Anything but an
  explicit yes — a dismissed dialog included — declines. Windows refuses
  these outright: its `.cmd` entry point truncates the multi-line
  prompt, and approving a fingerprint you cannot read is worse than not
  approving it.
- **Host passwords.** `user@host's password:` and the
  keyboard-interactive `(user@host) Password:` name a host, which is
  looked up in the vault by the same client-side URI matching the
  Windows helper uses (see [Bitwarden-Backed Passwords on
  Windows](#bitwarden-backed-passwords-on-windows)). A hit answers without
  any dialog; a miss, an ambiguous match, or an unavailable vault falls
  through to the masked field rather than failing, which would abort the
  connection.
- **Everything else.** Key passphrases and the like have no host to key
  on and go straight to the masked field.

The vault lookup degrades on its own — it checks for `bw` and
`bw-session-termux` first — so no host-type gating is needed: a host
without a vault simply gets the dialog.

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
