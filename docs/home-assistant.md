# Home Assistant CLI

[`hass-cli`](https://github.com/home-assistant-ecosystem/home-assistant-cli)
drives a Home Assistant instance from the terminal. It is deployed on **personal
hosts only**, on every platform this repo supports. Credentials are wired up on **Windows and Termux**, by the same mechanism with platform-specific parts — see [Credentials](#credentials).

## File Map

| File                                                                                                                                | Role                                                                 |
| ----------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| [`home/.chezmoiremove`](../home/.chezmoiremove)                                                                                     | Deletes the retired `[env]` fragment from hosts that already had it  |
| [`home/.chezmoiscripts/android/run_onchange_before.sh.tmpl`](../home/.chezmoiscripts/android/run_onchange_before.sh.tmpl)           | Installs Termux's native `uv`, the install engine on Android         |
| [`home/dot_bashrc.tmpl`](../home/dot_bashrc.tmpl)                                                                                   | Re-prepends `wrappers/` after `mise activate`                        |
| [`home/dot_config/mise/conf.d/home-assistant.toml`](../home/dot_config/mise/conf.d/home-assistant.toml)                             | The version pin, personal hosts                                      |
| [`home/dot_config/mise/conf.d/uv.toml`](../home/dot_config/mise/conf.d/uv.toml)                                                     | uv, the engine mise's `pipx:` backend installs through               |
| [`home/dot_config/powershell/profile.d/40-integrations.ps1.tmpl`](../home/dot_config/powershell/profile.d/40-integrations.ps1.tmpl) | Re-prepends `wrappers/` after `mise activate`, Windows               |
| [`home/dot_local/bin/executable_hass-cli-postinstall`](../home/dot_local/bin/executable_hass-cli-postinstall)                       | Event-loop shim for Python 3.14 venvs, run by the pin's postinstall  |
| [`home/dot_local/bin/executable_hass-vault`](../home/dot_local/bin/executable_hass-vault)                                           | Vault resolver + keystore-sealed cache, Termux                       |
| [`home/dot_local/bin/hass-cli-postinstall.cmd`](../home/dot_local/bin/hass-cli-postinstall.cmd)                                     | Windows no-op, so the shared pin's postinstall resolves there        |
| [`home/dot_local/bin/hass-vault.cmd`](../home/dot_local/bin/hass-vault.cmd)                                                         | Shim, so the wrapper can name `hass-vault` as a bare command         |
| [`home/dot_local/bin/hass-vault.ps1`](../home/dot_local/bin/hass-vault.ps1)                                                         | Vault resolver + DPAPI-wrapped cache, Windows                        |
| [`home/dot_local/bin/wrappers/executable_hass-cli.tmpl`](../home/dot_local/bin/wrappers/executable_hass-cli.tmpl)                   | Scopes credentials to hass-cli's process (Termux); Git Bash hand-off |
| [`home/dot_local/bin/wrappers/hass-cli.cmd`](../home/dot_local/bin/wrappers/hass-cli.cmd)                                           | Scopes credentials to hass-cli's process, Windows                    |
| [`home/dot_profile.tmpl`](../home/dot_profile.tmpl)                                                                                 | Puts `wrappers/` ahead of the mise shims                             |
| [`home/winget.yaml.tmpl`](../home/winget.yaml.tmpl)                                                                                 | Puts `wrappers/` ahead of the mise shims on the user PATH            |
| [`test/hass_vault_test.sh`](../test/hass_vault_test.sh)                                                                             | shUnit2 suite, Termux (`mise run test:shunit2`), in CI               |
| [`test/stubs/termux-keystore`](../test/stubs/termux-keystore)                                                                       | Model of the keystore, so that suite can run off a device            |

## Installation

The CLI is a Python application, pinned in mise's global namespace rather than
installed per-platform — see
[`mise.md`](mise.md#global-mise-config-fragments) for why a user-facing
application is the one thing allowed there, and how the fragment stays
Renovate-parseable.

mise's `pipx:` backend prefers `uv tool install` over pipx, so `uv` is pinned
alongside it. That covers Windows, Linux, and macOS, where mise installs uv
itself. On Termux it can't: aqua ships no android asset, so the mise-managed uv
is in `termux.toml`'s `disable_tools` and Termux's own `pkg` build serves from
PATH instead. Termux packages a Python new enough for the CLI's floor, so the
same `pipx:` pin resolves there.

### Python 3.14 and the Event-Loop Shim

Termux's Python is past the CLI's ceiling, not just its floor. hass-cli 1.0.0 still calls `asyncio.get_event_loop()` from a thread with no running loop, which Python deprecated in 3.10 and removed in 3.14, so on Termux the affected subcommands died before reaching the network:

```text
error: RuntimeError: There is no current event loop in thread 'MainThread'.
```

`entity list` and `area list` take that path; `raw`, `state`, and `service` do not. It is unrelated to credentials — the failing commands are authenticated, they just never get that far.

The pin therefore carries a `postinstall` that runs [`hass-cli-postinstall`](../home/dot_local/bin/executable_hass-cli-postinstall), which drops a `sitecustomize.py` into the tool venv — Python imports that at startup, ahead of any application code, and establishing a loop there restores what the interpreter used to do implicitly.

Three things shaped that:

- **A setting would have been lighter.** The usual fix for a misbehaving `pipx:` tool is an environment variable steering uv — `UV_PRERELEASE` to let a pre-release dependency resolve, `UV_PYTHON` to pin an interpreter. `UV_PYTHON` is the analogue and is unavailable: Termux packages only 3.14 and uv cannot supply another, since python-build-standalone is glibc-linked and bionic won't run it.
- **`postinstall`, not a chezmoi script**, because the shim goes in a directory mise owns and discards on any reinstall or version bump. A `run_after_` script would only fire on the next `chezmoi apply`.
- **The install path comes from the environment.** mise sets `MISE_TOOL_INSTALL_PATH`, with `MISE_TOOL_NAME` and `MISE_TOOL_VERSION`. Templating the command does not survive: there is no install-path variable, and `{{version}}` reaches the script as the literal `{version}`.

The script gates on the venv's interpreter rather than the OS, so a Linux or macOS host whose uv lands on 3.14 is repaired too, and one on an older interpreter has any stale shim removed. Windows gets a deliberate no-op `.cmd`, because the pin is plain TOML shared by every personal host and a command that did not resolve there would fail `mise install`.

## Credentials

hass-cli takes its server and token from `HASS_SERVER` / `HASS_TOKEN` (or from flags) on **every** invocation. It has no config file and no hook for fetching a secret, so something has to put them in the environment. Both platforms now answer that the same way — a wrapper on PATH — and what remains different is what each platform can seal a cache with.

|               | Windows                    | Termux                             |
| ------------- | -------------------------- | ---------------------------------- |
| Delivery      | `hass-cli` wrapper on PATH | `hass-cli` wrapper on PATH         |
| Token reaches | hass-cli's process         | hass-cli's process                 |
| At rest       | DPAPI                      | Android hardware keystore          |
| On a miss     | resolves, fails loudly     | resolves, may prompt, fails loudly |

Windows arrived there second. It shipped on mise `[env]`, which put the token in every process mise spawned through a shim and in every child of an activated shell, and left it readable via `mise env` — all three measured, and all three now closed. `[env]` is gone from every platform, and the fragment that carried it is listed in [`.chezmoiremove`](../home/.chezmoiremove), since dropping a file from the source only stops chezmoi managing it: a host that already had it would have gone on exporting the token.

### Why Not a Shell Wrapper

A shell _function_ named `hass-cli` only exists in shells that loaded a profile. Agent harnesses, scripts, and any non-interactive shell resolve the mise shim on PATH instead, get no credentials, and fall through to zeroconf discovery — `Found no Home Assistant on local network. Using defaults`. That is the common case, not an edge case: it is how every agent-driven invocation behaves. It is why `[env]` was the first answer on Windows, and why the replacement had to be an executable rather than a function.

Two smaller traps ruled out alongside it:

- Dispatching through `mise exec -- hass-cli` looks tidier and is worse. In an activated shell `mise` is itself a function, and forwarding through it drops the standalone `--`, so mise's parser claims the first hass-cli flag that collides with one of its own (`error: unexpected argument '--timeout' found`). It fails only on colliding arguments, so it looks fine until it doesn't.
- Passing `--server` / `--token` as flags would put a long-lived token in the command line, readable from any process listing.

### The Termux Wrapper

A wrapper _executable_ is a different thing from a shell function, and it does work — every caller reaches a file on PATH. The obstacle is that mise puts its shims directory ahead of `~/.local/bin`, so a wrapper there is shadowed by the tool's own shim.

The fix is ordering, and both mutations belong to this repo:
[`dot_profile`](../home/dot_profile.tmpl) prepends `~/.local/bin/wrappers` after the shims for non-interactive callers, and
[`dot_bashrc`](../home/dot_bashrc.tmpl) prepends it again after `mise activate`, which rewrites PATH on activation. Verified in all three paths — non-interactive, activated, and after repeated `hook-env` runs.

It gets its own directory rather than putting `~/.local/bin` in front, which would change resolution for everything in there to win one name. Nothing in `~/.local/bin` collides with a shim today — but only because the tools that would (`pnpm`, `node`) are the ones `termux.toml`'s `disable_tools` disables, so mise generates no shim for them. Should one leave that list later, it would start shadowing mise's copy by way of a PATH change made years earlier for hass-cli. A dedicated directory keeps the reordering scoped to what asked for it, and says so.

**What this buys, beyond scoping the token:** the wrapper runs only because someone ran hass-cli. That dissolves the constraint behind most of the Windows design — mise cannot tell hass-cli from anything else it runs, but the wrapper does not have to. So the Termux resolver may prompt on a miss, since a fingerprint dialog is then exactly what the caller asked for, and it fails loudly, because the failure is hass-cli's alone rather than every mise command's.

`disable_tools` would also drop the shim and free the name, and is not needed: the wrapper simply wins. It would additionally stop mise installing the tool, which is the pin's whole purpose.

### The Windows Wrapper

Same idea, two files, because Windows resolves a bare command name two different ways.

[`hass-cli.cmd`](../home/dot_local/bin/wrappers/hass-cli.cmd) is the wrapper proper, and it is `cmd` rather than a `.ps1` behind a shim because `hass-vault` is already a `.cmd` that starts pwsh — routing this through pwsh as well would put a second interpreter startup in front of every call. `setlocal` scopes both variables to the wrapper and its children, so they are gone when it exits. cmd has no `exec`, so unlike Termux the wrapper stays as a parent holding the same values; that is untidy rather than weaker, since reading them there needs the access that reading the child's environment already needs.

`hass-vault` is invoked by path (`%~dp0..\hass-vault.cmd`) rather than by name, because **cmd.exe searches the caller's current directory before PATH**. A stray `hass-vault.cmd` in whatever directory hass-cli happened to be run from would otherwise be executed and its output taken as the credentials. Demonstrated with a decoy: by name the decoy wins, by path it does not. The Termux wrapper needs no equivalent, since a POSIX PATH does not include the current directory.

Worth noting for anyone re-testing this: the harness process here sets `NoDefaultCurrentDirectoryInExePath=1`, which disables that search and masks the vector entirely. It has to be cleared to reproduce, and `where` lists the decoy first regardless of whether it would actually be executed.

The second file exists because **MSYS bash does not honour `PATHEXT`**. A bare `hass-cli` in Git Bash never matches a `.cmd` no matter where `wrappers/` sits on PATH — bash walks straight past it to mise's shim and runs with no credentials, failing over to zeroconf exactly as before. Measured: the full entity list through the wrapper, and the zeroconf failure without it. Bash _can_ execute a `.cmd` given a path, so the extensionless [`hass-cli`](../home/dot_local/bin/wrappers/executable_hass-cli.tmpl) is a one-line hand-off to its sibling rather than a second implementation. That is also why that source is a template: one file has to serve Termux's full wrapper and this hand-off.

PATH ordering takes two mutations here as well, mirroring `.profile` and `.bashrc`:
the winget config's `wrappersPath` resource puts `wrappers/` on the **user** PATH ahead of the mise shims, for non-interactive callers and Git Bash, and
[`40-integrations.ps1`](../home/dot_config/powershell/profile.d/40-integrations.ps1.tmpl) prepends it again after `mise activate`, which puts mise's _real_ tool directories in front of everything. That resource tests position rather than mere presence, since a wrapper below the shim it shadows is the same as no wrapper at all.

### The Cost

hass-cli's own startup dominates any invocation, which is what makes the sealed cache affordable without a faster tier above it. Measured on-device:

|                                 | per `hass-cli` call |
| ------------------------------- | ------------------: |
| hass-cli's own startup (floor)  |              876 ms |
| wrapper + keystore-sealed cache |            ~1610 ms |

The keystore round trip is a `termux-api` IPC call costing the better part of a second. One per invocation is affordable against that floor plus a network round trip; one per _mise command_ would not have been, which is the trap `[env]` fell into on both platforms.

Windows keeps its DPAPI-sealed cache for a different reason: a vault lookup there is dominated by `bw` starting Node, and sealing the pair turns a repeat call from seconds into milliseconds. `[env]` made that cache mandatory; the wrapper makes it merely worthwhile.

`hass-vault` resolves both values in a single call for the same reason — splitting them across two commands would pay for the keystore twice.

### What `redact` Does Not Do

This is why `[env]` was abandoned rather than tuned. Entries were marked `redact = true`, which does less than the name suggests. **Measured on Termux:** the values stay out of `mise doctor`, but `mise env` prints both in full, and `mise env --redacted` narrows the listing to the redacted variables rather than masking their values — a shortcut to the secrets, not a mask.

**Windows was then measured too, and behaved the same** — `mise env` printed the token in full there despite `redact`. Worth having checked rather than assumed: mise's handling of an `[env]` exec's stderr genuinely does differ between the two platforms, so the two were not safe to infer from each other.

Neither platform puts the token in `[env]` anymore, so the exposure is closed on both. Re-measured on Windows after the switch: no `HASS_*` in `mise env`, none in a process spawned by `mise exec`, none in a child of an activated shell.

### Failure

A wrapper fails loudly on both platforms: the failure belongs to `hass-cli` alone, so it exits non-zero and says why. On Windows that surfaces the resolver's actual reason _and_ the wrapper's guidance, where the old `[env]` path printed nothing at all.

That silence was the reason `[env]` needed `|| exit 0`: without it a locked vault, a renamed item, or an offline `bw` failed **every** mise command on the host, so a failed lookup had to yield an empty value and let hass-cli fall through to zeroconf. Nothing needs that bargain now.

Whether mise shows an `[env]` exec's stderr **differed by platform**, which is worth recording since it is what made the two platforms unsafe to reason about interchangeably. On Windows it was swallowed, so a failed lookup really was silent and `hass-vault check` was the only way to see the reason. On Termux it was printed, once per variable — better, but it meant anything routine written there would repeat on every mise command, which is why the Termux resolver reserves stderr for genuine faults.

`hass-vault check` reports whether credentials resolve without emitting either value; `hass-vault status` answers whether any are cached without touching the keystore or the vault. `hass-vault credential` exists for the wrapper and prints the pair, so it is not a command to run by hand.

### Vault Item

The resolver expects one vault item carrying:

- a **login URI** — the first one becomes `HASS_SERVER`; and
- a **custom field named `CLI Token`** — a [long-lived access token](https://www.home-assistant.io/docs/authentication/#your-account-profile), which becomes `HASS_TOKEN`.

The item is found by search rather than by a fixed id, so it stays renameable and no vault identifier is committed here. `bw`'s search matches names and URIs loosely, so it is only a prefilter: the result is narrowed to items that actually carry the `CLI Token` field, and **an ambiguous match is refused rather than guessed**. Every cold resolve runs `bw sync` first, because the CLI serves a local copy of the vault that refreshes on nothing else — not on unlock, not on `list`.

The default search term is `Home Assistant`; `HASS_VAULT_ITEM` overrides it.

### Rotating the Token

Update the `CLI Token` field in the vault item, then run `hass-vault refresh`.

The second step is not optional. Every cold resolve now syncs `bw`'s local copy before searching, so the _vault_ side is handled automatically — but a resolve never reaches `bw` while a valid cache holds, and the cache keeps serving the previous token for the rest of its idle window. `refresh` drops it so the next resolve fetches afresh.

The failure this prevents does not look like a stale credential. The lookup still finds the item, so the resolver returns a well-formed token and reports success, and only Home Assistant rejects it:

```text
error: HTTPError: 401 Client Error: Unauthorized
```

`hass-vault check` reports success in that state too, since it verifies that credentials resolve, not that they are accepted. **A 401 shortly after a rotation means the cache is behind, not that anything is broken.**

### The Sealed Cache

A vault lookup costs seconds and may prompt, so `hass-vault` caches the resolved pair, wrapped against the Android hardware keystore exactly as [`bw-session-termux`](../home/dot_local/bin/executable_bw-session-termux) wraps the vault session key: a KEK derived from a deterministic signature by a non-extractable key, AES-256-GCM, the expiry bound as additional authenticated data so editing it breaks decryption rather than extending the window. The cache is therefore inert on any other device, which DPAPI's binding to the user identity does not give.

The idle window slides, but only once more than half spent — rewriting costs another keystore round trip, and an idle timeout need not be exact. It stays under `bw-session-termux`'s, so the credential cache cannot outlive the session cache beneath it. `HASS_VAULT_IDLE_TIMEOUT` overrides it; a lapse costs a vault lookup, not a silent failure.

**`termux-keystore` reports a missing alias by writing nothing and exiting 0.** A resolver that signs without checking therefore folds to the SHA-256 of the empty string and uses that public constant as its key — identically on write and read, so the cache round-trips perfectly while bound to nothing. The key is created up front on the write path, and that constant is refused. The test suite asserts the binding directly, because no assertion about behaviour can detect this.

`hass-vault refresh` discards the cached pair and resolves again — the same command on both platforms, and the answer to a rotated token.

`hass-vault reset` is Termux-only and goes further: it drops the cache _and_ the hardware key, making any surviving copy permanently unreadable. Windows has no key to destroy, so it has no `reset`; there, `refresh` is the whole story.

## Other Platforms

Linux and macOS install the CLI but have no resolver, so they get no credentials. Each needs its own wrapping (Keychain, libsecret) because the at-rest binding is a platform API. The wrapper and its PATH ordering would port largely unchanged from Termux — `.profile` and `.bashrc` already carry the mutations — so a resolver is the only missing piece.

## Git Bash Path Arguments

Credentials resolve the same in Git Bash as in PowerShell, once the
extensionless hand-off described above is on PATH. What differs is argument
handling: MSYS2 rewrites arguments that look like Unix paths into Windows
paths, so

```sh
hass-cli raw get /api/
```

sends `C:/Program Files/Git/api/` and fails with a URL like
`https://home-assistant.example.comC:/Program Files/Git/api/`. The credentials
were fine; the path was mangled before hass-cli saw it. Suppress the conversion
for commands that take URL paths:

```sh
MSYS2_ARG_CONV_EXCL='*' hass-cli raw get /api/
```

Subcommands that take no path-shaped argument (`entity list`, `state get`, …)
are unaffected, as is PowerShell.
