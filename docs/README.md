# Reference Docs

Deep-dive references for cross-file configurations in this repo — how
the moving parts fit together when a single config spans multiple files.

| Doc | Topic |
|---|---|
| [`agent-config.md`](agent-config.md) | User-level instructions fan-out per tool, skill deployment to `~/.agents/skills/`, Claude divergence |
| [`pnpm-globals.md`](pnpm-globals.md) | Pinned-version source, shared template, per-script include lists, GitHub-spec packages, `pnpmfile.cjs` hook |
| [`worktrunk.md`](worktrunk.md) | Worktrunk install, `wt`-resolution per platform, shared config template, post-start bootstrap, skill deployment |
