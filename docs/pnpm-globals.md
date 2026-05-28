# pnpm Globals

Global pnpm packages installed across machines have pinned versions in
`package.json` at the repo root. A shared chezmoi template renders
`pnpm add -g` commands into per-script install scripts, so each script
re-runs only when *its* packages change — not when an unrelated package
bumps.

## File Map

| File | Role |
|---|---|
| `package.json` | Pinned versions; Renovate-managed |
| `pnpmfile.cjs` | Optional global pnpm hooks (currently patches a volar dep) |
| `home/.chezmoitemplates/pnpm-globals` | Shared template that renders `pnpm add -g <name@version> …` |
| `home/.chezmoiscripts/android/run_onchange_after_install-pnpm-globals.sh.tmpl` | Termux installer |
| `home/.chezmoiscripts/windows/run_onchange_after_claude-configure.ps1.tmpl` | Installs `tweakcc` + Claude plugin setup |
| `home/.chezmoiscripts/windows/run_onchange_after_install-pnpm-globals.ps1.tmpl` | Installs codex + LSP servers (uses `pnpmfile.cjs`) |
| `home/.chezmoiscripts/windows/run_onchange_after_mcp-readonly-install.ps1.tmpl` | Installs `@readonly-mcp/core` + Claude registration |

## How the Template Renders

The template takes a `dict` with:

- `include` — list of package names to install on this invocation
- `pnpmfile` — optional path passed as `--config.global-pnpmfile=<path>`

It iterates `package.json`'s `dependencies`, keeps entries whose name is
in `include`, and emits `pnpm add -g`. Two version-spec branches:

- `github:<owner>/<repo>#<sha>` → passed verbatim (pnpm understands the
  spec); `name@version` would error because there is no published
  version. `@readonly-mcp/core` uses this — it's installed from a pinned
  commit on the upstream repo.
- Everything else → `name@version` form.

So a script declaring `include "@openai/codex"` renders to roughly:

```
pnpm add -g @openai/codex@0.120.0
```

with the version baked into the rendered file content.

## Why Include Lists Instead of Installing Everything

Chezmoi's `run_onchange_*` mechanism hashes the *rendered* script
content. If every script installed every global, bumping any package
would re-run every script (slow; some have non-trivial post-install
steps like Claude plugin registration). With include lists, the rendered
content only changes for scripts that actually use the bumped package.

The trade-off: each package must belong to exactly one script. Scripts
that need a package for post-install steps (e.g., the MCP install
script needs `@readonly-mcp/core` before registering it with Claude)
install that package themselves via the same template — making them
self-contained, no ordering dependencies.

## The `pnpmfile` Option

`pnpmfile.cjs` at the repo root contains a `readPackage` hook that
patches `volar-service-emmet@0.0.64`'s GitHub-resolved
`@emmetio/css-parser` dep to the npm-published version (pnpm 11's
`blockExoticSubdeps` rejects the GitHub fork). The Windows
`install-pnpm-globals` script passes the file via
`--config.global-pnpmfile=` because that's the only script installing
`@vue/language-server`, which transitively pulls the broken volar
dep. Other scripts don't set the flag — they don't need it. See the
inline comments in `pnpmfile.cjs` for the upstream-issue trail.

## Adding a New Global Package

1. Add the package + pinned version to `package.json`.
2. Add the name to the `include` list in exactly one script.

Renovate's existing `package.json` watcher picks up version bumps and
opens PRs. The shared template handles GitHub-spec packages
automatically — pin them as `github:<owner>/<repo>#<sha>` in
`package.json`.
