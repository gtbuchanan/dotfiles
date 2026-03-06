# Personal Agent Preferences

## Coding Style

- Prefer functional programming style over procedural
- Prefer pure functions for testability. Push side effects to app boundaries

## Communication

- I'm a senior engineer - don't explain basics

## Configuration

- Always update user-level configuration in Chezmoi directory and run `chezmoi apply`

## Git

- Always keep commit subject 72 characters or less. Prefer 50 or less. Don't truncate blindly.
  Prefer semantic meaning over implementation details.
- Wrap commit body at 72 characters, when possible
- Always run project-specific build before committing
- Always use `--force-with-lease` to force push, when necessary
- Always set `AI_AGENT=1` when running git commands that trigger GPG signing (e.g., commit, tag)
- When squash-merging a PR, always provide your own summarized commit message
  that includes the PR reference suffix (e.g., ` (#1234)`).
  Do not accept the default squash message (concatenated individual commits).
- When creating a PR, always ask whether to open it as a draft or ready for review.
- Never push to a remote unless explicitly told to.
- Never force push to main/master.
- Only force push when changing history of pushed commits.
- When creating issues or PRs, always use the repository's issue/PR templates if available.
- Always delete local and remote PR branch after merging a PR.
{{- if eq .hosttype "ewn" }}
- When a GitHub org is ambiguous or unspecified, infer `energyworldnet`
{{- end }}
- When creating a new repo, always ask where to create it (org/account).
{{- if eq .hosttype "ewn" }}
  Default suggestion: `energyworldnet`
{{- else }}
  Default suggestion: personal account
{{- end }}

## Testing

- Always use Playwright CLI to verify website changes

## Shell

- NEVER use `cd` to change to the current working directory before running a command.
  The working directory is already set — just run the command directly.
  IMPORTANT: On Windows with Git Bash, `/c/Users/...` and `C:\Users\...` are the SAME path.
  Do NOT do `cd /c/Users/.../project && command` if the cwd is
  `C:\Users\...\project`. They are equivalent — skip the `cd`.
- When a temporary directory change is needed, use
  `pushd dir && command; rc=$?; popd; exit $rc` instead of `cd dir && command`.
  This ensures the working directory is always restored and the command's exit
  code is preserved.

## MCP Readonly Tools

- Prefer MCP readonly tools over Bash for read-only operations:
  - `mcp__readonly__git` for: status, diff, log, branch, show, rev-parse
  - `mcp__readonly__shell` for: ls, jq, stat, file, wc, eza, which, etc.
  - `mcp__readonly__gh` for: issue/pr/repo/run viewing
  - `mcp__readonly__chezmoi` for read-only chezmoi commands
  - `mcp__readonly__acli` for read-only Jira commands
  - `mcp__readonly__npm` for: audit, bin, explain, fund, ls, outdated, root, search, view
  - `mcp__readonly__pnpm` for: audit, bin, licenses list, list, outdated, root, search, store status, why
- Only fall back to Bash when a command isn't supported by the MCP server

## Node.js

- Prefer pnpm over npm when the project's package manager is ambiguous

## Python

- Always use `py.exe` on Windows instead of `python.exe` or `python3.exe` directly
