# Git

`~/.gitconfig` carries the bulk of the customization (aliases plus
opinionated push/pull/merge defaults), with three auxiliary scripts in
`~/.config/git/` providing branch-aware helpers and a safer
`git clean`. GPG signing and the Android `sshCommand` are covered in
their own docs — this one focuses on everything else.

## File Map

| File | Role |
|---|---|
| `home/dot_config/private_git/executable_clean-safe` | `git clean` wrapper that respects `.cleanignore.local` |
| `home/dot_config/private_git/executable_jira` | `git j` — resolves the JIRA key from a `jira/<key>` branch and forwards to `acli` (ewn host-type only) |
| `home/dot_config/private_git/gpg-wrapper.bat` | Windows GPG shim (see [`gpg-signing.md`](gpg-signing.md#windows)) |
| `home/dot_config/private_git/ignore` | Global gitignore (resolved by git's XDG default) |
| `home/dot_gitconfig.tmpl` | Main config: aliases, opinionated defaults, per-OS branches |

## Opinionated Defaults

The non-default settings worth knowing about:

- **`pull.ff = only` + `pull.rebase = true`** — `git pull` either
  fast-forwards or rebases; never produces a merge commit by accident.
- **`merge.ff = only`** — explicit `git merge` likewise refuses to
  create a merge commit unless the target's ancestor is the source.
- **`merge.conflictStyle = zdiff3`** — conflict markers include the
  common ancestor's content (zealous diff3), which makes resolving
  three-way conflicts substantially less guesswork.
- **`push.autoSetupRemote = true`** — first push on a new branch
  doesn't need `-u`; git infers the upstream from the branch name.
- **`push.forceIfIncludes = true`** — `--force-with-lease` alone can
  still clobber commits you haven't fetched yet; `forceIfIncludes`
  refuses the push unless your local copy actually contains the
  remote's current tip.
- **`fetch.prune = true`** — fetches always remove tracking refs for
  deleted upstream branches.
- **`commit.gpgsign = true`** — every commit is signed. See
  [`gpg-signing.md`](gpg-signing.md) for the per-OS pinentry wiring.

## Delta + KDiff3

[delta](https://github.com/dandavison/delta) is the pager
(`core.pager = delta`) with side-by-side view, line numbers, file
navigation, and hyperlinks enabled. `interactive.diffFilter` routes
`git add -p` through delta too.

[KDiff3](https://kdiff3.sourceforge.net/) is wired in as the diff and
merge GUI on every platform (`diff.guitool` and `merge.tool` are
unconditional), but only Windows installs it (via winget) and
configures the binary path. On Linux/macOS you'd need to install
KDiff3 yourself for `git mergetool` / `git difftool --gui` to work.

## Helper Scripts

### `git clean-safe`

`git clean -fdx` is dangerous in worktrees that hold untracked files
you want to keep (build caches, local config, IDE state). `clean-safe`
reads a `.cleanignore.local` from the worktree root and passes each
line as `-e` to `git clean`. The file itself is auto-excluded so the
list doesn't get cleaned away.

`.cleanignore.local` is in the global ignore too (it's per-worktree
local config, not something to commit).

### `git j` (ewn only)

Branches at work follow a `jira/<KEY>` naming convention. `git j`
reads the current branch, extracts the JIRA key, and forwards to
`acli jira workitem` with that key already filled in. Subcommands
that take a key positionally (`view`) pass it as a positional arg;
everything else passes it as `--key`. Combined with the aliases (`git
jc`, `git jl`, `git jt`, `git jv`) this turns most JIRA operations
into two-character commands when you're already in the right
worktree.

Two more aliases shell out to external PowerShell scripts that this
repo doesn't manage — clone them to `~/Code/` separately:

- `git unpicked` (ewn) — lists commits that haven't been cherry-picked
  to a target branch (or were picked inexactly). Source:
  [`git-unpicked` gist](https://gist.github.com/gtbuchanan/1a9699e8350d2eacc73de902c29d8ea0).
- `git amt` (Windows) — interactive `git add` driven by the mergetool
  (KDiff3) instead of `add -p`'s curses interface. Source:
  [`git-add-mergetool` gist](https://gist.github.com/gtbuchanan/3c5e44100c5a83f4aec7d2a832d50d42).

## Global Ignore

`dot_config/private_git/ignore` deploys to `~/.config/git/ignore`,
which is git's XDG default for `core.excludesFile`. No explicit
`excludesFile` setting is needed — git picks it up automatically.

The list covers OS junk (`.DS_Store`, `Thumbs.db`), editor scratch
files (`*.swo`, `*.swp`, `PowerShellEditorServices.json`), tool output
(`*.orig`, `*.log`, `*.bak`), and per-tool sandboxes
(`.claude/worktrees/`, `.cleanignore.local`).

## Per-OS Quirks

- **Windows** — `core.autocrlf = true`, `core.longpaths = true`, and
  `core.editor` points at the full path to the Windows-native Vim.
  The full path is deliberate: Git Bash bundles its own Vim that
  would otherwise win shell resolution, but the Windows install is
  what's wanted.
- **WSL** — `gpg.program` points at the Windows GPG binary so signing
  uses the host's agent and key store (see
  [`gpg-signing.md`](gpg-signing.md#wsl)).
- **Android** — `core.sshCommand = ssha` so Git auto-starts ssh-agent
  on first use (see [`ssh.md`](ssh.md#android)).
