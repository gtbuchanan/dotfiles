# pnpm Globals

Global pnpm packages installed across machines have pinned versions in the
`globals` catalog of [`pnpm-workspace.yaml`](../pnpm-workspace.yaml) at the repo
root. A shared chezmoi template renders `pnpm add -g` commands into per-script
install scripts, so each script re-runs only when _its_ packages change — not
when an unrelated package bumps.

## File Map

| File                                                                                                                                                                | Role                                                                                              |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| [`.pnpmfile.cjs`](../.pnpmfile.cjs)                                                                                                                                 | Global pnpm hooks (patches a volar dep, ink-link's missing react, m365's missing `@azure/logger`) |
| [`home/.chezmoiscripts/android/run_onchange_after_install-pnpm-globals.sh.tmpl`](../home/.chezmoiscripts/android/run_onchange_after_install-pnpm-globals.sh.tmpl)   | Termux installer                                                                                  |
| [`home/.chezmoiscripts/windows/run_onchange_after_claude-configure.ps1.tmpl`](../home/.chezmoiscripts/windows/run_onchange_after_claude-configure.ps1.tmpl)         | Installs `tweakcc` + Claude plugin setup                                                          |
| [`home/.chezmoiscripts/windows/run_onchange_after_install-pnpm-globals.ps1.tmpl`](../home/.chezmoiscripts/windows/run_onchange_after_install-pnpm-globals.ps1.tmpl) | Installs global npm packages                                                                      |
| [`home/.chezmoiscripts/windows/run_onchange_after_mcp-readonly-install.ps1.tmpl`](../home/.chezmoiscripts/windows/run_onchange_after_mcp-readonly-install.ps1.tmpl) | Installs `@readonly-mcp/core` + Claude registration                                               |
| [`home/.chezmoitemplates/pnpm-globals`](../home/.chezmoitemplates/pnpm-globals)                                                                                     | Shared template that renders `pnpm add -g <name@version> …`                                       |
| [`pnpm-workspace.yaml`](../pnpm-workspace.yaml)                                                                                                                     | Pinned versions (`globals` catalog); Renovate-managed                                             |

## How the Template Renders

The template takes a `dict` with:

- `include` — list of package names to install on this invocation
- `workingTree` — repo root, used to wire `--config.global-pnpmfile`

It resolves each `include` name against the `globals` catalog in
[`pnpm-workspace.yaml`](../pnpm-workspace.yaml) and emits `pnpm add -g`, always
passing the root [`.pnpmfile.cjs`](../.pnpmfile.cjs) via
`--config.global-pnpmfile`. Two version-spec branches:

- `github:<owner>/<repo>#<sha>` → passed verbatim (pnpm understands the
  spec); `name@version` would error because there is no published
  version. `@readonly-mcp/core` uses this — it's installed from a pinned
  commit on the upstream repo.
- Everything else → `name@version` form.

So a script declaring `include "@openai/codex"` renders to roughly:

```sh
pnpm add -g --config.global-pnpmfile=<root>/.pnpmfile.cjs @openai/codex@0.120.0
```

with the version baked into the rendered file content.

## Why Include Lists Instead of Installing Everything

Chezmoi's `run_onchange_*` mechanism hashes the _rendered_ script
content. If every script installed every global, bumping any package
would re-run every script (slow; some have non-trivial post-install
steps like Claude plugin registration). With include lists, the rendered
content only changes for scripts that actually use the bumped package.

The trade-off: each package must belong to exactly one script. Scripts
that need a package for post-install steps (e.g., the MCP install
script needs `@readonly-mcp/core` before registering it with Claude)
install that package themselves via the same template — making them
self-contained, no ordering dependencies.

## The `.pnpmfile.cjs` Hook

[`.pnpmfile.cjs`](../.pnpmfile.cjs) at the repo root contains a `readPackage`
hook with three patches:

- `volar-service-emmet@0.0.64`'s GitHub-resolved `@emmetio/css-parser`
  dep is repointed to the npm-published version (pnpm 11 rejects the
  fork). Pulled by `@vue/language-server`, installed by
  `install-pnpm-globals`.
- `ink-link` omits its `react` dependency, crashing `tweakcc` under
  pnpm's isolated `node_modules`; the hook adds it. Pulled by `tweakcc`,
  installed by `claude-configure`.
- `@azure/monitor-opentelemetry-exporter` (via `@pnp/cli-microsoft365`)
  leaves `@azure/logger` in `devDependencies`, crashing `m365` under
  isolated `node_modules`; the hook adds it. Installed by
  `install-pnpm-globals` (`ewn` only).

The template wires this file via `--config.global-pnpmfile=` on every
`pnpm add -g`, so a global that needs a patch is covered without opting in
per script; the hook is a no-op for packages that match neither name. It
doubles as the workspace's local hook for `pnpm install` (pnpm's canonical
`.pnpmfile.cjs`). See the inline comments in
[`.pnpmfile.cjs`](../.pnpmfile.cjs) for each patch's full mechanism and
upstream-issue trail.

## Adding a New Global Package

1. Add the package + pinned version to the `globals` catalog in
   [`pnpm-workspace.yaml`](../pnpm-workspace.yaml).
1. Add the name to the `include` list in exactly one script.

Renovate's pnpm-catalog support picks up version bumps and opens PRs. The
shared template handles GitHub-spec packages automatically — pin them as
`github:<owner>/<repo>#<sha>` in the catalog.
