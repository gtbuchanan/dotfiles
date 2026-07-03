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
| [`home/.chezmoiignore`](../home/.chezmoiignore)                                                                                                               | Gates `.config/mise` (and the android scripts) to Termux only          |
| [`home/.chezmoiscripts/android/run_onchange_after_install-actionlint.sh.tmpl`](../home/.chezmoiscripts/android/run_onchange_after_install-actionlint.sh.tmpl) | Termux out-of-band `actionlint` install                                |
| [`home/.chezmoiscripts/android/run_onchange_after_install-hk.sh.tmpl`](../home/.chezmoiscripts/android/run_onchange_after_install-hk.sh.tmpl)                 | Termux out-of-band `hk` + `pkl` install                                |
| [`home/.chezmoiscripts/android/run_onchange_before.sh.tmpl`](../home/.chezmoiscripts/android/run_onchange_before.sh.tmpl)                                     | Termux mise + native-bionic linters (`pkg`)                            |
| [`home/.chezmoiscripts/darwin/run_onchange_before.sh.tmpl`](../home/.chezmoiscripts/darwin/run_onchange_before.sh.tmpl)                                       | macOS mise install (Homebrew formula)                                  |
| [`home/.chezmoiscripts/linux/run_onchange_before.sh.tmpl`](../home/.chezmoiscripts/linux/run_onchange_before.sh.tmpl)                                         | Linux mise install (`mise.run`)                                        |
| [`home/dot_bashrc.tmpl`](../home/dot_bashrc.tmpl)                                                                                                             | `mise activate bash` (interactive)                                     |
| [`home/dot_config/mise/config.toml`](../home/dot_config/mise/config.toml)                                                                                     | Global mise config — **Android-only** (Termux backend workarounds)     |
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

## Global mise Config Is Android-Only

[`dot_config/mise/config.toml`](../home/dot_config/mise/config.toml) is the
**only** repo-managed global mise config, and it is gated to Termux —
[`.chezmoiignore`](../home/.chezmoiignore) excludes `.config/mise` on every OS
except android. On glibc Linux, macOS, and Windows there is intentionally no
global config: mise's `core`/`aqua` backends install everything cleanly, so
the repo leaves the global namespace empty and lets each project's `mise.toml`
drive tool versions.

The Termux config exists only because mise's backend OS detection is
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
  out-of-band release fetches (below). The exceptions are `uv` and
  `powershell`, which get no replacement: `uv` is disabled only because its
  sole consumer here (`clang-format`) is satisfied by Termux's `clang`
  package, and `powershell`'s only consumer (the psscriptanalyzer hk step)
  isn't run on Termux. `chezmoi` is a further special case — aqua _does_ ship
  an Android asset and mise installs it, but the generic Go binary can't
  resolve DNS on bionic (breaking `.chezmoiexternal` fetches), so it too is
  disabled in favor of the `pkg` build.

Each disabled tool's per-tool rationale lives inline in the config — keep that
as the source of truth and update it when a tool's Android story changes.

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
route it does) lives inline in
[`dot_config/mise/config.toml`](../home/dot_config/mise/config.toml).

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
