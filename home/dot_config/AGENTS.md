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
- When creating issues or PRs, always use the repository's issue/PR templates if available.

## Testing

- Always use Playwright CLI to verify website changes

## Shell

- NEVER use `cd` to change to the current working directory before running a command.
  The working directory is already set — just run the command directly.
  IMPORTANT: On Windows with Git Bash, `/c/Users/...` and `C:\Users\...` are the SAME path.
  Do NOT do `cd /c/Users/.../project && command` if the cwd is
  `C:\Users\...\project`. They are equivalent — skip the `cd`.

## Python

- Always use `py.exe` on Windows instead of `python.exe` or `python3.exe` directly
