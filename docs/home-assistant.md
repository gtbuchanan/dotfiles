# Home Assistant CLI

[`hass-cli`](https://github.com/home-assistant-ecosystem/home-assistant-cli)
drives a Home Assistant instance from the terminal. It is deployed on **personal
hosts only**, on every platform this repo supports. Credentials are wired up on **Windows and Termux**, by deliberately different mechanisms — see [Credentials](#credentials).

## File Map

| File                                                                                                                            | Role                                                                |
| ------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| [`home/.chezmoiscripts/android/run_onchange_before.sh.tmpl`](../home/.chezmoiscripts/android/run_onchange_before.sh.tmpl)       | Installs Termux's native `uv`, the install engine on Android        |
| [`home/dot_bashrc.tmpl`](../home/dot_bashrc.tmpl)                                                                               | Re-prepends `wrappers/` after `mise activate`                       |
| [`home/dot_config/mise/conf.d/home-assistant-credentials.toml`](../home/dot_config/mise/conf.d/home-assistant-credentials.toml) | `HASS_SERVER` / `HASS_TOKEN` via `[env]`, personal Windows          |
| [`home/dot_config/mise/conf.d/home-assistant.toml`](../home/dot_config/mise/conf.d/home-assistant.toml)                         | The version pin, personal hosts                                     |
| [`home/dot_config/mise/conf.d/uv.toml`](../home/dot_config/mise/conf.d/uv.toml)                                                 | uv, the engine mise's `pipx:` backend installs through              |
| [`home/dot_local/bin/executable_hass-cli-postinstall`](../home/dot_local/bin/executable_hass-cli-postinstall)                   | Event-loop shim for Python 3.14 venvs, run by the pin's postinstall |
| [`home/dot_local/bin/executable_hass-vault`](../home/dot_local/bin/executable_hass-vault)                                       | Vault resolver + keystore-sealed cache, Termux                      |
| [`home/dot_local/bin/hass-cli-postinstall.cmd`](../home/dot_local/bin/hass-cli-postinstall.cmd)                                 | Windows no-op, so the shared pin's postinstall resolves there       |
| [`home/dot_local/bin/hass-vault.cmd`](../home/dot_local/bin/hass-vault.cmd)                                                     | Shim, so `[env]` can name a bare command on PATH                    |
| [`home/dot_local/bin/hass-vault.ps1`](../home/dot_local/bin/hass-vault.ps1)                                                     | Vault resolver + DPAPI-wrapped cache, Windows                       |
| [`home/dot_local/bin/wrappers/executable_hass-cli`](../home/dot_local/bin/wrappers/executable_hass-cli)                         | Scopes the credentials to hass-cli's process, Termux                |
| [`home/dot_profile.tmpl`](../home/dot_profile.tmpl)                                                                             | Puts `wrappers/` ahead of the mise shims                            |
| [`test/hass_vault_test.sh`](../test/hass_vault_test.sh)                                                                         | shUnit2 suite, device-only (`mise run test:hass-vault`)             |

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

hass-cli takes its server and token from `HASS_SERVER` / `HASS_TOKEN` (or from flags) on **every** invocation. It has no config file and no hook for fetching a secret, so something has to put them in the environment. The two platforms answer that differently, and the difference is the interesting part.

|               | Windows                                  | Termux                             |
| ------------- | ---------------------------------------- | ---------------------------------- |
| Delivery      | mise `[env]`                             | `hass-cli` wrapper on PATH         |
| Token reaches | every process mise spawns through a shim | hass-cli's process                 |
| At rest       | DPAPI                                    | Android hardware keystore          |
| On a miss     | resolves silently, fails soft            | resolves, may prompt, fails loudly |

### Why Not a Shell Wrapper

A shell _function_ named `hass-cli` only exists in shells that loaded a profile. Agent harnesses, scripts, and any non-interactive shell resolve the mise shim on PATH instead, get no credentials, and fall through to zeroconf discovery — `Found no Home Assistant on local network. Using defaults`. That is the common case, not an edge case: it is how every agent-driven invocation behaves. It is also why the Windows half uses `[env]`.

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

### The Cost

hass-cli's own startup dominates any invocation, which is what makes the sealed cache affordable without a faster tier above it. Measured on-device:

|                                 | per `hass-cli` call |
| ------------------------------- | ------------------: |
| hass-cli's own startup (floor)  |              876 ms |
| wrapper + keystore-sealed cache |            ~1610 ms |

The keystore round trip is a `termux-api` IPC call costing the better part of a second. One per invocation is affordable against that floor plus a network round trip; one per _mise command_ would not have been, which is the trap `[env]` falls into and the reason the Windows resolver needs a second cache tier.

`hass-vault` resolves both values in a single call for the same reason — splitting them across two commands would pay for the keystore twice.

### What `redact` Does Not Do

The Windows `[env]` entries are marked `redact = true`, which may do less than the name suggests. **Measured on Termux:** the values stay out of `mise doctor`, but `mise env` prints both in full, and `mise env --redacted` narrows the listing to the redacted variables rather than masking their values — a shortcut to the secrets, not a mask.

**Whether Windows behaves identically is unverified.** It is a reasonable assumption and not a safe one: mise's handling of an `[env]` exec's stderr already differs between the two platforms, so `redact` may too. Worth measuring before relying on it; until then, treat `mise env` output as the token itself.

The wrapper removes this class of exposure on Termux by not putting the token in `[env]` at all. It remains open on Windows.

### Failure

The Windows `[env]` entries end in `|| exit 0`, so a failed lookup yields an empty value rather than breaking **every** mise command on the host. The cost is that hass-cli simply falls back to zeroconf.

The Termux wrapper needs none of that: a failure there stops hass-cli and says why.

Whether mise shows an `[env]` exec's stderr **differs by platform**, which is worth knowing before trusting either behaviour. On Windows it is swallowed, so a failed lookup really is silent and `hass-vault check` is the only way to see the reason. On Termux it is printed, once per variable — better, since a real fault surfaces unasked, but it means anything routine written there would repeat on every mise command. That is moot now that Termux resolves through a wrapper rather than `[env]`, and it is why the Termux resolver reserves stderr for genuine faults.

`hass-vault check` reports whether credentials resolve without emitting either value; `hass-vault status` answers whether any are cached without touching the keystore or the vault. `hass-vault credential` exists for the wrapper and prints the pair, so it is not a command to run by hand.

### Vault Item

The resolver expects one vault item carrying:

- a **login URI** — the first one becomes `HASS_SERVER`; and
- a **custom field named `CLI Token`** — a [long-lived access token](https://www.home-assistant.io/docs/authentication/#your-account-profile), which becomes `HASS_TOKEN`.

The item is found by search rather than by a fixed id, so it stays renameable and no vault identifier is committed here. `bw`'s search matches names and URIs loosely, so it is only a prefilter: the result is narrowed to items that actually carry the `CLI Token` field, and **an ambiguous match is refused rather than guessed**. A miss triggers one `bw sync` and a retry, because the CLI serves a local copy of the vault that never refreshes on unlock.

The default search term is `Home Assistant`; `HASS_VAULT_ITEM` overrides it.

### The Sealed Cache

A vault lookup costs seconds and may prompt, so `hass-vault` caches the resolved pair, wrapped against the Android hardware keystore exactly as [`bw-session-termux`](../home/dot_local/bin/executable_bw-session-termux) wraps the vault session key: a KEK derived from a deterministic signature by a non-extractable key, AES-256-GCM, the expiry bound as additional authenticated data so editing it breaks decryption rather than extending the window. The cache is therefore inert on any other device, which DPAPI's binding to the user identity does not give.

The idle window slides, but only once more than half spent — rewriting costs another keystore round trip, and an idle timeout need not be exact. It stays under `bw-session-termux`'s, so the credential cache cannot outlive the session cache beneath it. `HASS_VAULT_IDLE_TIMEOUT` overrides it; a lapse costs a vault lookup, not a silent failure.

**`termux-keystore` reports a missing alias by writing nothing and exiting 0.** A resolver that signs without checking therefore folds to the SHA-256 of the empty string and uses that public constant as its key — identically on write and read, so the cache round-trips perfectly while bound to nothing. The key is created up front on the write path, and that constant is refused. The test suite asserts the binding directly, because no assertion about behaviour can detect this.

`hass-vault reset` drops the cache and the hardware key, making any surviving copy permanently unreadable.

## Other Platforms

Linux and macOS install the CLI but have no resolver, so they get no credentials. Each needs its own wrapping (Keychain, libsecret) because the at-rest binding is a platform API.

Windows could take the wrapper approach too — that is what would close the `mise env` exposure there — but it needs its own wrapper and its own PATH ordering, and is not attempted here.

## Git Bash Path Arguments

Credentials resolve the same in Git Bash as in PowerShell — `[env]` is applied
by the shim either way. What differs is argument handling: MSYS2 rewrites
arguments that look like Unix paths into Windows paths, so

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
