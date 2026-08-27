# mise & hk

[mise](https://mise.jdx.dev) is the tool-version / env / task manager
installed on every platform this repo supports. [hk](https://hk.jdx.dev) is
jdx's git-hook lint orchestrator that downstream project repos drive _through_
mise (it resolves hk, pkl, actionlint, and the linters from mise-managed
tools).

This repo manages mise **installation and activation** on each platform, plus
a Termux-only workaround layer that stands in for mise's tool backends where
they have no Android assets. It pins the Termux lint toolchain (`hk`, `pkl`,
`actionlint` — see [hk Toolchain Version Pinning](#hk-toolchain-version-pinning)),
but does **not** pin downstream projects' tool versions — those live in each
project's `mise.toml` (the canonical reference here is `gtbuchanan/tooling`'s
`mise.toml`, which the Termux pins are kept in sync with).

## File Map

| File                                                                                                                                                          | Role                                                                   |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| [`home/.chezmoidata/actionlint.yaml`](../home/.chezmoidata/actionlint.yaml)                                                                                   | Pinned `actionlint` version for the Termux install (Renovate-tracked)  |
| [`home/.chezmoidata/hk.yaml`](../home/.chezmoidata/hk.yaml)                                                                                                   | Pinned `hk` + `pkl` versions for the Termux install (Renovate-tracked) |
| [`home/.chezmoiexternal.yaml.tmpl`](../home/.chezmoiexternal.yaml.tmpl)                                                                                       | `mise-guide` skill archive → `~/.agents/skills/mise-guide/`            |
| [`home/.chezmoiignore`](../home/.chezmoiignore)                                                                                                               | Gates the android scripts to Termux only                               |
| [`home/.chezmoiscripts/android/run_onchange_after_install-actionlint.sh.tmpl`](../home/.chezmoiscripts/android/run_onchange_after_install-actionlint.sh.tmpl) | Termux out-of-band `actionlint` install                                |
| [`home/.chezmoiscripts/android/run_onchange_after_install-hk.sh.tmpl`](../home/.chezmoiscripts/android/run_onchange_after_install-hk.sh.tmpl)                 | Termux out-of-band `hk` + `pkl` install                                |
| [`home/.chezmoiscripts/android/run_onchange_before.sh.tmpl`](../home/.chezmoiscripts/android/run_onchange_before.sh.tmpl)                                     | Termux mise + native-bionic linters (`pkg`)                            |
| [`home/.chezmoiscripts/darwin/run_onchange_before.sh.tmpl`](../home/.chezmoiscripts/darwin/run_onchange_before.sh.tmpl)                                       | macOS mise install (Homebrew formula)                                  |
| [`home/.chezmoiscripts/linux/run_onchange_before.sh.tmpl`](../home/.chezmoiscripts/linux/run_onchange_before.sh.tmpl)                                         | Linux mise install (`mise.run`)                                        |
| [`home/dot_bashrc.tmpl`](../home/dot_bashrc.tmpl)                                                                                                             | `mise activate bash` (interactive)                                     |
| [`home/dot_config/mise/conf.d/`](../home/dot_config/mise/conf.d)                                                                                              | Global mise config fragments, gated per-platform by their own ignore   |
| [`home/dot_config/powershell/profile.d/40-integrations.ps1.tmpl`](../home/dot_config/powershell/profile.d/40-integrations.ps1.tmpl)                           | `mise activate pwsh`                                                   |
| [`home/dot_profile.tmpl`](../home/dot_profile.tmpl)                                                                                                           | Shims dir on PATH (non-interactive)                                    |
| [`home/winget.yaml.tmpl`](../home/winget.yaml.tmpl)                                                                                                           | Windows mise install + shims-dir PATH entry                            |

## mise Installation Per Platform

| Platform         | Source                        | mise binary         | Resolution path                      |
| ---------------- | ----------------------------- | ------------------- | ------------------------------------ |
| Windows          | winget `jdx.mise`             | WinGet packages dir | shims at `%LOCALAPPDATA%\mise\shims` |
| Linux            | `curl https://mise.run \| sh` | `~/.local/bin`      | `mise activate` / shims              |
| macOS            | Homebrew formula `mise`       | Homebrew prefix     | `mise activate` / shims              |
| Android (Termux) | `pkg install mise`            | Termux prefix       | `mise activate` / shims              |

On Windows the winget config also appends `%LOCALAPPDATA%\mise\shims` to the
**user** PATH (the `miseShimsPath` xScript resource), so mise-managed tools
resolve even in non-interactive contexts that never run `mise activate`.

## mise Shell Activation

Interactive shells run `mise activate`, which prepends the **real** tool paths
(not the shims) ahead of everything, so mise-pinned versions win over
system/Homebrew copies:

- bash — [`dot_bashrc.tmpl`](../home/dot_bashrc.tmpl): `eval "$(mise activate bash)"`
- PowerShell — [`40-integrations.ps1.tmpl`](../home/dot_config/powershell/profile.d/40-integrations.ps1.tmpl): `mise activate pwsh | … | Invoke-Expression`

Non-interactive POSIX contexts don't run `mise activate`, so
[`dot_profile.tmpl`](../home/dot_profile.tmpl) instead prepends the
`~/.local/share/mise/shims` directory to PATH (last, so it still outranks
system tools). Windows covers the same gap via the user-PATH shims entry
above.

## Global mise Config Fragments

The repo-managed global config is a set of fragments under
[`dot_config/mise/conf.d/`](../home/dot_config/mise/conf.d), not a single
`config.toml`. mise loads every non-hidden `.toml` in that directory
alphabetically, below `~/.config/mise/config.toml` in precedence, which leaves
the plain config file free for anything hand-written on a host.

| Fragment                                                                    | Deployed on    | Holds                                              |
| --------------------------------------------------------------------------- | -------------- | -------------------------------------------------- |
| [`home-assistant.toml`](../home/dot_config/mise/conf.d/home-assistant.toml) | personal hosts | The `pipx:homeassistant-cli` pin                   |
| [`termux.toml`](../home/dot_config/mise/conf.d/termux.toml)                 | android        | `HK_PKL_BACKEND` + the `disable_tools` workarounds |
| [`uv.toml`](../home/dot_config/mise/conf.d/uv.toml)                         | every host     | uv, the engine mise's `pipx:` backend installs via |

**Dev toolchains stay out of the global namespace** on every platform. mise's
`core`/`aqua` backends install them cleanly, so each project's `mise.toml`
drives those versions. hass-cli is the standing exception, and it earns that by
not being a dev toolchain: it is a user-facing application, so no project
`mise.toml` would ever pin it and nothing downstream can be shadowed by it.

The split into fragments is what keeps them **plain TOML instead of chezmoi
templates**, and that is the point of the layout. Renovate's own `mise` manager
parses these files and resolves both the `pipx:` (PyPI) and `core` datasources,
so no version here needs a hand-written `# renovate:` annotation or a custom
regex manager. Go template directives would make a file unparseable and push it
back onto one. So the per-platform split lives in
[`conf.d/.chezmoiignore`](../home/dot_config/mise/conf.d/.chezmoiignore) rather
than in `{{ if }}` gates inside the files.

The manager needs one nudge to find them: its built-in patterns key on a literal
`.config/mise/conf.d`, which the chezmoi `dot_config` source path doesn't match,
so [`renovate.json`](../.github/renovate.json) adds a pattern for this
directory. `managerFilePatterns` is additive, so the repo-root `mise.toml` keeps
matching by default.

## Global mise Config Termux Fragment

The Termux fragment exists only because mise's backend OS detection is
**compile-time**: Termux-native mise always resolves `android/arm64`, for
which aqua publishes no assets and `core` backends fall back to
from-source builds that don't compile against bionic. The config therefore:

- sets `HK_PKL_BACKEND = "pkl"` so hk routes pkl through the external CLI
  instead of its embedded evaluator. The repo `mise.toml` pins this backend on
  every platform for consistent evaluation; on Termux it is also mandatory —
  the embedded backend's rustls/reqwest client can't fetch the remote pkl
  package over HTTPS on bionic; and
- lists every tool with no usable Android backend in `disable_tools`. Most
  are then supplied from PATH instead — either native `pkg` builds or
  out-of-band release fetches (below). The exception is `powershell`, which
  gets no replacement: its only consumer, the psscriptanalyzer hk step, isn't
  run on Termux. `chezmoi` is a special case in the other direction — aqua
  _does_ ship an Android asset and mise installs it, but the generic Go binary
  can't resolve DNS on bionic (breaking `.chezmoiexternal` fetches), so it too
  is disabled in favor of the `pkg` build.

Each disabled tool's rationale lives beside its own `disable_tools` entry —
keep that as the source of truth and update it when a tool's Android story
changes.

## hk Pre-Commit Toolchain on Termux

Downstream repos run hk for pre-commit linting; on normal platforms mise
installs hk and its dependencies via aqua. On Termux that path is dead (see
above), so the toolchain is reconstructed from two install routes, both
landing wrappers/symlinks in `~/.local/bin`:

- **Native bionic builds from `pkg`** — tools Termux already packages are
  installed by
  [`run_onchange_before.sh`](../home/.chezmoiscripts/android/run_onchange_before.sh.tmpl)
  and resolved from PATH (they're in `disable_tools`).
- **Out-of-band release fetches** — tools with no Termux package each have
  their own `run_onchange_after_install-*` script, so a version bump re-fires
  only the affected install:
  - `hk` and `pkl` are installed together by
    [`install-hk.sh`](../home/.chezmoiscripts/android/run_onchange_after_install-hk.sh.tmpl)
    because pkl is an hk **runtime** dependency (hk invokes it for
    validate/check/fix/install). pkl can't be exec'd directly on bionic, so
    `grun -c` patches its ELF interpreter and a wrapper launches it through
    `grun` (provided by the `claude-code-termux` package; see
    [`claude-code.md`](claude-code.md)).
  - `actionlint` is installed alone by
    [`install-actionlint.sh`](../home/.chezmoiscripts/android/run_onchange_after_install-actionlint.sh.tmpl)
    — hk merely **orchestrates** it as a workflow-lint step, it's not an hk
    runtime dependency.

The full per-tool breakdown (which backend fails and why each tool takes the
route it does) lives beside each entry in
[`conf.d/termux.toml`](../home/dot_config/mise/conf.d/termux.toml).

## hk Toolchain Version Pinning

The out-of-band Termux installs are version-pinned in
[`.chezmoidata`](../home/.chezmoidata) so the rendered `run_onchange` scripts
re-fire on a bump:

- [`hk.yaml`](../home/.chezmoidata/hk.yaml) — `hk_version`, `pkl_version`
- [`actionlint.yaml`](../home/.chezmoidata/actionlint.yaml) — `actionlint_version`

All carry `renovate:` annotations (datasource `github-releases`) for automated
bumps, and are kept in sync with `gtbuchanan/tooling`'s `mise.toml` so local
Termux hk runs match what CI installs through aqua. actionlint publishes
per-asset checksums, which the install script verifies; jdx/hk does not
publish per-tarball checksums, so hk is pinned by version only.

## mise Skill

The `mise-guide` skill ships as a chezmoi external archive and is deployed to
`~/.agents/skills/mise-guide/`. See [`agent-config.md`](agent-config.md) for
the skill deploy path shared by every tool.

## mise Bootstrap as a chezmoi Replacement

`mise bootstrap` — a converging machine provisioner mise grew over its 2026
releases — overlaps chezmoi's job enough to raise the question of whether it
could replace it here. Evaluated as of 2026-08 against mise 2026.8.2:
**no.** Keep chezmoi as the file-deployment layer.

What bootstrap does bring:

- `[dotfiles]`, keyed by target path, with `symlink`, `symlink-each`, `copy`,
  and `template` (tera) modes — plus _edit_ entries that own a
  marker-delimited block or a single exact line inside a file mise doesn't
  otherwise own. Confirmed working on Windows: template mode renders with
  `[vars]` in scope, and `symlink` falls back to copying for files (documented
  behavior, since file symlinks need elevation there).
- System-level convergence that chezmoi can only model as shell scripts —
  `[bootstrap.packages]`, `[bootstrap.services]`, `[bootstrap.linux.firewall]`,
  `[bootstrap.linux.systemd.units]`, `[bootstrap.macos.defaults]`,
  `[bootstrap.macos.launchd.agents]`, `[bootstrap.users]`/`[bootstrap.groups]`.
- `[bootstrap.repos]`, which covers the `type: git` entries in
  [`.chezmoiexternal.yaml.tmpl`](../home/.chezmoiexternal.yaml.tmpl).
- `mise bootstrap remote` (bootstrap other machines over OpenSSH) and
  `mise bootstrap plan`, neither of which chezmoi has an analogue for.

What blocks it for this repo:

| Gap                                                                                                                                                                                                                                                                                                 | Dependency here                                                                                                                                                                             |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| No conditional gating of entries. `mise.toml` is strict TOML and tera renders inside string _values_, not over the file, so `{% if os() == "windows" %}` around `[dotfiles]` entries is a parse error. `[bootstrap.packages]` entries take an `os` filter; `[dotfiles]` entries have no equivalent. | [`.chezmoiignore`](../home/.chezmoiignore) gates whole categories of targets per-OS. The workaround would be sharding into `mise.<env>.toml` files and setting `MISE_ENV` on every machine. |
| No Windows package manager — no `winget`, `scoop`, or `chocolatey` backend anywhere in the CLI or schema.                                                                                                                                                                                           | [`winget.yaml.tmpl`](../home/winget.yaml.tmpl), which provisions Windows packages including mise itself.                                                                                    |
| `mise bootstrap status` fails outright on Windows (`managed system files are only supported on Unix`); only sub-phases such as `bootstrap dotfiles` run.                                                                                                                                            | Windows is a primary platform.                                                                                                                                                              |
| No prompted, persisted per-host data. `[vars]` is static; `[bootstrap.secrets]` prompts only for secret inputs.                                                                                                                                                                                     | `promptChoiceOnce` for `hosttype` in [`.chezmoi.yaml.tmpl`](../home/.chezmoi.yaml.tmpl), fanning out to `email`, `signingkey`, `osid`, and `wsl`.                                           |
| No permission attributes on dotfile entries; `template` mode simply inherits the source file's permissions.                                                                                                                                                                                         | The `private_`, `readonly_`, and `executable_` prefixes — notably [`private_dot_ssh`](../home/private_dot_ssh).                                                                             |
| No `modify_` equivalent. Edit entries manage comment-marker blocks or exact lines, not structured merges.                                                                                                                                                                                           | The `modify_` scripts, above all the VS Code `settings.json` merge that has to survive VS Code's own writes.                                                                                |
| No archive or single-file externals; `[bootstrap.repos]` is git-only.                                                                                                                                                                                                                               | The `type: archive` and `type: file` externals (agent skills, vim-plug).                                                                                                                    |
| Bootstrap hooks run on every invocation and must be idempotent. Task `sources`/`outputs` fingerprinting is the nearest analogue to re-firing on a rendered-content hash change, but it isn't the same contract.                                                                                     | The `run_onchange_*` scripts.                                                                                                                                                               |

Migration would also mean porting every `*.tmpl` from Go `text/template` to
tera.

Maturity weighs in too, for a repo that has to work on every platform above:
bootstrap is new and moving quickly, and mise's published JSON schema already
lags its own CLI — `--help` documents `[bootstrap.files]`,
`[bootstrap.services]`, `[bootstrap.compose]`, and
`[bootstrap.users]`/`[bootstrap.groups]`, while `mise.json` omits them.

Re-evaluate if either of these lands:

- a `winget:` (or `scoop:`) manager for `[bootstrap.packages]`, which would
  give `winget.yaml.tmpl` somewhere to go; or
- an `os` filter on `[dotfiles]` entries, matching what
  `[bootstrap.packages]` already accepts — the `.chezmoiignore` replacement.

A narrower question stays open: moving only the _provisioning_ half (the
`run_onchange_*` scripts and `winget.yaml.tmpl`) into `mise bootstrap` while
chezmoi keeps deploying files. That doesn't pay off today either, because this
repo's provisioning is concentrated in Windows winget and the Termux backend
workarounds above — the two areas bootstrap serves least well.
