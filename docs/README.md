# Reference Docs

Deep-dive references for cross-file configurations in this repo — how
the moving parts fit together when a single config spans multiple files.

| Doc | Topic |
|---|---|
| [`agent-config.md`](agent-config.md) | User-level instructions fan-out per tool, skill deployment to `~/.agents/skills/`, Claude divergence |
| [`bash.md`](bash.md) | Per-OS bash source (Homebrew on macOS, Git Bash on Windows), ble.sh nightly install + vi mode, `.bash_profile` → `.profile` → `.bashrc` load order, auto-tmux |
| [`claude-code.md`](claude-code.md) | settings.json drift, Windows LSP plugin + `.cmd`-shim fixes, notification → pane-focus chain, Android native install |
| [`coderabbit.md`](coderabbit.md) | CLI install (native on Linux/macOS, via WSL on Windows), Windows wrappers for worktree + path translation, Claude Code plugin |
| [`git.md`](git.md) | Opinionated push/pull/merge defaults, delta + KDiff3 wiring, helper scripts (`clean-safe`, `git j`, gist-backed `git unpicked` / `git amt`), per-OS quirks |
| [`gpg-signing.md`](gpg-signing.md) | Per-OS GPG pinentry wiring (Windows wrapper, Linux/macOS native, Termux popup), AI-agent bypass via `AI_AGENT`/`CLAUDE_CODE` |
| [`mcp.md`](mcp.md) | MCP server registrations across Claude + VS Code, `readonly-mcp` install + auto-allow, microsoft-learn HTTP transport |
| [`mise.md`](mise.md) | mise install + activation per platform, Android-only global config, the Termux out-of-band hk/pkl/actionlint lint toolchain, version pinning |
| [`nerd-font.md`](nerd-font.md) | `.font` vs `.fontpack` variable split, per-OS installers (`getnf` / NerdFonts PS module), Termux's fixed-path font quirk |
| [`pnpm-globals.md`](pnpm-globals.md) | Pinned-version source, shared template, per-script include lists, GitHub-spec packages, [`pnpmfile.cjs`](../pnpmfile.cjs) hook |
| [`powershell.md`](powershell.md) | Canonical `~/.config/powershell` profile, Windows `Documents/PowerShell` dot-source stub, `profile.d` numeric-ordered loader + `foreach`-scope rule, per-part breakdown |
| [`ssh.md`](ssh.md) | Shared `Include ./*.conf` config, Windows-native OpenSSH as the canonical client, WSL→Windows agent bridge, Android popup askpass |
| [`vim.md`](vim.md) | `.vimrc` + `.vsvimrc` shared-config split, `data_dir` cross-platform trick, plugin/auto-load layout, Android fauxClip, LSP via vim-lsp + ALE |
| [`worktrunk.md`](worktrunk.md) | Worktrunk install, `wt`-resolution per platform, shared config template, post-start bootstrap, skill deployment |
