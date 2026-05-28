# Reference Docs

Deep-dive references for cross-file configurations in this repo — how
the moving parts fit together when a single config spans multiple files.

| Doc | Topic |
|---|---|
| [`agent-config.md`](agent-config.md) | User-level instructions fan-out per tool, skill deployment to `~/.agents/skills/`, Claude divergence |
| [`claude-code.md`](claude-code.md) | settings.json drift, Windows LSP plugin + `.cmd`-shim fixes, notification → pane-focus chain, Android native install |
| [`gpg-signing.md`](gpg-signing.md) | Per-OS GPG pinentry wiring (Windows wrapper, Linux/macOS native, Termux popup), AI-agent bypass via `AI_AGENT`/`CLAUDE_CODE` |
| [`pnpm-globals.md`](pnpm-globals.md) | Pinned-version source, shared template, per-script include lists, GitHub-spec packages, `pnpmfile.cjs` hook |
| [`worktrunk.md`](worktrunk.md) | Worktrunk install, `wt`-resolution per platform, shared config template, post-start bootstrap, skill deployment |
