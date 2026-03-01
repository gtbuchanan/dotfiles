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

## Python

- Always use `py.exe` on Windows instead of `python.exe` or `python3.exe` directly
