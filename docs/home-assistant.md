# Home Assistant CLI

[`hass-cli`](https://github.com/home-assistant-ecosystem/home-assistant-cli)
drives a Home Assistant instance from the terminal. It is deployed on **personal
hosts only**, on every platform this repo supports. Credentials are wired up on
**Windows so far** — see [Credentials](#credentials).

## File Map

| File                                                                                                                            | Role                                                            |
| ------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| [`home/.chezmoiscripts/android/run_onchange_before.sh.tmpl`](../home/.chezmoiscripts/android/run_onchange_before.sh.tmpl)       | Installs Termux's native `uv`, the install engine on Android    |
| [`home/dot_config/mise/conf.d/home-assistant-credentials.toml`](../home/dot_config/mise/conf.d/home-assistant-credentials.toml) | `HASS_SERVER` / `HASS_TOKEN` via `[env]`, personal Windows only |
| [`home/dot_config/mise/conf.d/home-assistant.toml`](../home/dot_config/mise/conf.d/home-assistant.toml)                         | The version pin, personal hosts                                 |
| [`home/dot_config/mise/conf.d/uv.toml`](../home/dot_config/mise/conf.d/uv.toml)                                                 | uv, the engine mise's `pipx:` backend installs through          |
| [`home/dot_local/bin/hass-vault.cmd`](../home/dot_local/bin/hass-vault.cmd)                                                     | Shim, so `[env]` can name a bare command on PATH                |
| [`home/dot_local/bin/hass-vault.ps1`](../home/dot_local/bin/hass-vault.ps1)                                                     | Vault resolver + DPAPI-wrapped credential cache                 |

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

## Credentials

hass-cli takes its server and token from `HASS_SERVER` / `HASS_TOKEN` (or from
flags) on **every** invocation. It has no config file and no hook for fetching a
secret, so something has to put them in the environment.

That something is mise's `[env]`, not a shell wrapper, and the reason is worth
recording because the wrapper is the obvious design and it does not work.

### Why Not a Shell Wrapper

A function named `hass-cli` that resolves credentials and forwards to the binary
only exists in shells that loaded a profile. Agent harnesses, scripts, and any
non-interactive shell resolve the mise shim on PATH instead, get no credentials,
and fall through to zeroconf discovery — `Found no Home Assistant on local
network. Using defaults`. That is the common case, not an edge case: it is how
every agent-driven invocation behaves.

Two smaller traps ruled out alongside it:

- Dispatching through `mise exec -- hass-cli` looks tidier and is worse. In an
  activated shell `mise` is itself a function (installed by `mise activate
pwsh`), and forwarding through it drops the standalone `--`, so mise's parser
  claims the first hass-cli flag that collides with one of its own
  (`error: unexpected argument '--timeout' found`). It fails only on colliding
  arguments, so it looks fine until it doesn't.
- Passing `--server` / `--token` as flags would put a long-lived token in the
  command line, readable from any process listing. Same reason the resolver
  hands `bw` its session through the environment rather than `--session`,
  matching [`ssh.md`](ssh.md)'s askpass helper.

`[env]` has none of these problems: mise applies it in the shim path too, so
activated shells, `mise exec`, scripts, and agents are all covered by one
mechanism. The residual gap is running the binary by its absolute path inside
mise's install directory, which nothing does by accident.

### Resolution and Caching

`[env]` templating sets one variable per `exec()`, so `HASS_SERVER` and
`HASS_TOKEN` are two separate calls to `hass-vault`. A vault lookup costs ~11s —
several of those seconds are Node starting up before the vault is touched — and
mise's computed-env cache is session-scoped, so it does **not** engage on the
shims-only path non-interactive callers take. An uncached resolver would
therefore pay that on every command, twice.

So `hass-vault` caches the resolved pair itself, wrapped with DPAPI exactly as
[`bw-session-windows.ps1`](../home/dot_local/bin/bw-session-windows.ps1) wraps
the vault session key — same protection, same sliding idle window, expiry bound
as the entropy so editing it breaks decryption rather than extending the window.
It is deliberately shorter-lived than the session cache beneath it, because it
holds the credential rather than a key that unlocks a vault. Measured: ~11s
cold, ~0.1s warm.

`env_cache_ttl` sits above that as a second cache, sparing activated shells from
spawning the resolver at all on each directory change. Staleness is harmless
because Home Assistant long-lived tokens don't rotate.

`hass-vault reset` drops the cache; `hass-vault status` reports what's left of
the window.

### Failure Is Silent by Design

The `[env]` entries end in `|| exit 0`, so a failed lookup yields an empty value
instead of an error. Without it, a locked vault, a renamed item, or an offline
`bw` would fail **every** mise command on the host rather than just hass-cli.

The cost is that failure is quiet: mise swallows an `[env]` exec's stderr, so
hass-cli simply falls back to zeroconf and reports it cannot find Home
Assistant. When that happens, run `hass-vault check` — it resolves the same way
and prints the real reason to stderr.

Use `check` for this, never `token` or `server`. Those exist to be captured by
mise and print a credential to stdout, so running one to test the setup writes a
long-lived token into a terminal, a shell history, a log, or an agent
transcript. `check` reports the outcome and the token's length, nothing more.

### Vault Item

The resolver expects one vault item carrying:

- a **login URI** — the first one becomes `HASS_SERVER`; and
- a **custom field named `CLI Token`** — a
  [long-lived access token](https://www.home-assistant.io/docs/authentication/#your-account-profile),
  which becomes `HASS_TOKEN`.

The item is found by search rather than by a fixed id, so it stays renameable
and no vault identifier is committed here. `bw`'s search matches names and URIs
loosely, so it is only a prefilter: the result is narrowed to items that
actually carry the `CLI Token` field, and **an ambiguous match is refused rather
than guessed**. A miss triggers one `bw sync` and a retry, because the CLI
serves a local copy of the vault that never refreshes on unlock — an item added
from another device is otherwise invisible indefinitely.

The default search term is `Home Assistant`; `HASS_VAULT_ITEM` overrides it.

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

## Other Platforms

Linux, macOS, and Termux install the CLI but have no resolver yet, so they get
no credentials — the `[env]` fragment is gated to Windows and is not deployed
there. This is unimplemented, not opted out. Each platform needs its own
resolver rather than a port, because the at-rest wrapping is bound to a platform
API (DPAPI here, the Android keystore in
[`bw-session-termux`](../home/dot_local/bin/executable_bw-session-termux)); the
credential fragment gains that platform in its gate once one exists.
