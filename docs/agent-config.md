# Agent Config

This repo gets two kinds of agent configuration to every supported tool
(Claude Code, Codex, GitHub Copilot, VS Code prompts, plus tools that
read `~/.agents/` directly like Cursor / Gemini CLI / OpenCode):

- **User-level instructions** — coding style, git conventions,
  shell/MCP preferences. Each tool reads from its own path, so the
  shared content is fanned out via per-tool wrappers.
- **Skills** — [agentskills.io](https://agentskills.io) bundles
  fetched from upstream repos. Most tools converge on
  `~/.agents/skills/`; Claude diverges and reads `~/.claude/skills/`,
  resolved by a single symlink.

## File Map

| File                                                                                                                                              | Role                                                                                                      |
| ------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| [`home/.chezmoiexternal.yaml.tmpl`](../home/.chezmoiexternal.yaml.tmpl)                                                                           | Skill archive URLs + host-conditional gating                                                              |
| [`home/AppData/Roaming/Code/user/prompts/personal.instructions.md.tmpl`](../home/AppData/Roaming/Code/user/prompts/personal.instructions.md.tmpl) | VS Code prompts wrapper (adds `applyTo: '**'` frontmatter)                                                |
| [`home/dot_claude/CLAUDE.md.tmpl`](../home/dot_claude/CLAUDE.md.tmpl)                                                                             | Claude wrapper: includes shared instructions + Claude-only sections (LSP, Worktree Sessions, Agent Teams) |
| [`home/dot_claude/symlink_skills`](../home/dot_claude/symlink_skills)                                                                             | `~/.claude/skills` → `~/.agents/skills`                                                                   |
| [`home/dot_codex/AGENTS.md.tmpl`](../home/dot_codex/AGENTS.md.tmpl)                                                                               | Codex wrapper (pass-through)                                                                              |
| [`home/dot_config/AGENTS.md.tmpl`](../home/dot_config/AGENTS.md.tmpl)                                                                             | Shared user-level instructions (source of truth)                                                          |
| [`home/dot_copilot/copilot-instructions.md.tmpl`](../home/dot_copilot/copilot-instructions.md.tmpl)                                               | Copilot wrapper (pass-through)                                                                            |

## User-Level Instructions

There is no cross-tool location for user-level instructions — each tool
reads from its own path. Standardizing one is being tracked upstream at
[agentsmd/agents.md#91](https://github.com/agentsmd/agents.md/issues/91);
until that lands, the workaround is one source plus per-tool wrappers.
The shared content lives in [`home/dot_config/AGENTS.md.tmpl`](../home/dot_config/AGENTS.md.tmpl), and each
tool gets a one-line wrapper that pulls it in via `includeTemplate`:

```text
{{ includeTemplate "dot_config/AGENTS.md.tmpl" . }}
```

The wrappers deploy to each tool's expected location:

| Tool            | Wrapper source                                                                                                                                    | Deployed path                        |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| Claude Code     | [`home/dot_claude/CLAUDE.md.tmpl`](../home/dot_claude/CLAUDE.md.tmpl)                                                                             | `~/.claude/CLAUDE.md`                |
| Codex           | [`home/dot_codex/AGENTS.md.tmpl`](../home/dot_codex/AGENTS.md.tmpl)                                                                               | `~/.codex/AGENTS.md`                 |
| GitHub Copilot  | [`home/dot_copilot/copilot-instructions.md.tmpl`](../home/dot_copilot/copilot-instructions.md.tmpl)                                               | `~/.copilot/copilot-instructions.md` |
| VS Code prompts | [`home/AppData/Roaming/Code/user/prompts/personal.instructions.md.tmpl`](../home/AppData/Roaming/Code/user/prompts/personal.instructions.md.tmpl) | `…/personal.instructions.md`         |

The shared template itself also deploys to `~/.config/AGENTS.md`
because of its chezmoi source path. No tool reads from there — it's
just where chezmoi puts the rendered template — but it's harmless and
keeps the template-include chain straightforward.

Two wrappers add tool-specific content beyond the include:

- **Claude** appends sections that only apply to Claude Code (shell-tool
  preferences, LSP guidance, Agent Teams, Worktree Sessions). Including
  these in the shared template would leak Claude-specific advice into
  other tools.
- **VS Code prompts** adds `applyTo: '**'` frontmatter — VS Code's
  prompt-file format requires it; the body is otherwise verbatim.

## Skills

Skills deploy to `~/.agents/skills/<name>/` via chezmoi externals
(archive entries in [`home/.chezmoiexternal.yaml.tmpl`](../home/.chezmoiexternal.yaml.tmpl)). That's the
cross-tool location read natively by Codex CLI, Cursor, Gemini CLI,
OpenCode, and GitHub Copilot (in VS Code and Visual Studio 2026).

Claude Code only reads `~/.claude/skills`, so a single chezmoi-managed
symlink redirects it:

```text
~/.agents/skills/         ← chezmoi externals land here
    atlassian-cli/SKILL.md
    worktrunk/SKILL.md
    …

~/.claude/skills → ../.agents/skills   (home/dot_claude/symlink_skills)
```

One symlink keeps every tool reading the same files.

### Pinning

Each external is pinned — usually a commit SHA, sometimes a release
tag. Renovate watches the URLs and opens PRs for upstream commits.
Where the upstream repo bundles many skills, `stripComponents` +
`include` carve out just the one we want; that's why the
`MicrosoftDocs/agent-skills` repo can supply both `azure-devops` and
`azure-pipelines` from the same archive (the `$msSkills` loop in the
externals file).

### Adding a New Skill

1. Add an entry to [`home/.chezmoiexternal.yaml.tmpl`](../home/.chezmoiexternal.yaml.tmpl) under
   `'.agents/skills/<name>':`. Pin the URL to a commit SHA or tag.
2. Use `stripComponents` + `include` so only the target skill's
   directory unpacks. Most upstream repos either ship a single skill
   at the root or nest under `skills/<name>/`.

All tools pick it up automatically on the next `chezmoi apply` — no
per-tool registration step.

### Personal Skills

Skills I author myself live in the private
[`gtbuchanan/skills`](https://github.com/gtbuchanan/skills) repo and are
deployed as a whole-repo clone rather than enumerated per-skill, so every
skill installs and new ones are picked up automatically without publishing
the skill names in this public repo. The archive-per-skill approach above
doesn't fit here for two reasons:

- The repo is private, and chezmoi `archive` externals can't authenticate;
  only `git-repo` externals can (over SSH).
- A `git-repo` external can't `stripComponents`/`include` to flatten the
  repo's `skills/<name>/` layout into `.agents/skills/<name>/`.

So the deploy is a two-step: a `git-repo` external in
[`home/.chezmoiexternal.yaml.tmpl`](../home/.chezmoiexternal.yaml.tmpl)
SSH-clones the repo alongside the other dev repos, then a per-OS `run_after`
script symlinks each skill from the clone into `.agents/skills/`. The POSIX
logic is shared via
[`home/.chezmoitemplates/agent-skills-sync`](../home/.chezmoitemplates/agent-skills-sync)
(included by the linux/darwin/android scripts); Windows has its own
PowerShell copy. Only symlinks the script created are pruned — the
third-party skill directories above are left untouched.
