#!/usr/bin/env bash
#
# Tests for the Claude Code statusline, the script Claude Code runs to render
# the bar under its prompt. It reads a session JSON payload on stdin and writes
# one line of ANSI to stdout.
#
# The statusline is read straight from home/, not rendered through `chezmoi cat`
# as the hass-vault suite does: it is a plain file rather than a template, so
# the rendered output would be byte-identical, and reading it directly keeps
# this suite free of the config-and-hosttype dance CI would otherwise need.
#
# That is also why the cost segment is gated by a `--cost` argument rather than
# by a hosttype conditional in the script: the gate lives in
# home/dot_claude/settings.json.tmpl, which decides whether to pass the flag, so
# the script stays a pure function of stdin plus argv and both of its branches
# are reachable here without rendering anything.
#
#   mise run test:shunit2 [-- shUnit2 args, e.g. a test_* name filter]
#
# Built on the vendored shUnit2 (vendor/shunit2): each behavior is a `test_*`
# function, discovered and summarized by the framework. Deliberately no `set -e`
# -- errexit fights shUnit2.

cd "$(dirname "$0")/.." || exit 1

readonly STATUSLINE="$PWD/home/dot_claude/executable_statusline"

if [ ! -f "$STATUSLINE" ]; then
  echo "SKIP: $STATUSLINE not found"
  exit 0
fi

if ! command -v jq >/dev/null; then
  echo 'SKIP: jq not available'
  exit 0
fi

# The git segment shells out to git in the cwd and memoizes the result under
# TMPDIR, keyed by cwd. A TMPDIR of the suite's own keeps it off whatever the
# developer's live sessions cached there, and takes the cache with it on the way
# out.
TMPDIR=$(mktemp -d) || exit 1
export TMPDIR
trap 'rm -rf "$TMPDIR"' EXIT

# --- harness ----------------------------------------------------------------

# The powerline glyphs the bar is built from: the right arrow each segment is
# introduced by, and the right cap the line ends with. Built with printf for the
# same reason the statusline builds its own that way -- the escapes are the
# readable spelling of the codepoint, and they survive an editor that has no
# Nerd Font. Spelled out here rather than read from the script, so the append
# assertion below anchors on an independently known boundary.
SEP=$(printf '\xee\x82\xb0') #  powerline right arrow
CAP=$(printf '\xee\x82\xb4') #  powerline right round
readonly SEP CAP

# A statusline payload carrying $1 as the session cost in USD. Only the fields
# the assertions depend on are set; the script defaults the rest, which is
# itself part of what is covered here.
payload() { # $1 = total_cost_usd
  jq -nc --argjson cost "$1" '{
    model: { display_name: "Opus 5" },
    cwd: "/tmp/claude-statusline-test",
    workspace: { project_dir: "/tmp/claude-statusline-test" },
    context_window: { used_percentage: 8 },
    cost: { total_cost_usd: $cost }
  }'
}

render() { # $1 = total_cost_usd, $2... = statusline arguments
  payload "$1" | bash "$STATUSLINE" "${@:2}"
}

# The visible text of a rendered line, with the colour and cursor escapes
# dropped. Assertions read better against this, and it is what a reader of the
# bar actually sees.
visible() { sed $'s/\033\\[[0-9;]*m//g'; }

# --- the cost segment -------------------------------------------------------

test_cost_is_rendered_when_asked_for() {
  # Two decimals because the figure is money, and because the raw float is wide
  # enough to shove the rest of the bar sideways between frames.
  assertContains 'dollars and cents' "$(render 1.234 --cost)" "\$1.23"
}

test_cost_rounds_rather_than_truncates() {
  assertContains 'rounded up' "$(render 0.126 --cost)" "\$0.13"
}

test_a_session_that_has_spent_nothing_still_shows_a_figure() {
  # Zero is a real answer -- the session has not reached the API yet -- and a
  # blank segment would read as the flag never having been wired up.
  assertContains 'zero cost' "$(render 0 --cost)" "\$0.00"
}

test_a_missing_cost_field_reads_as_zero() {
  # Claude Code always sends `cost`, but the statusline is also run by hand and
  # from here. A jq null must not reach printf, whose format would reject it and
  # take the whole bar down with it. Only `cost` is dropped, so a failure here
  # can only be about the cost segment.
  local out
  out=$(payload 0 | jq -c 'del(.cost)' | bash "$STATUSLINE" --cost)
  assertContains 'absent cost' "$out" "\$0.00"
}

test_cost_is_absent_unless_asked_for() {
  # The default, and what a subscription-billed host gets: no flag, no segment.
  local out
  out=$(render 1.234 | visible)
  assertNotContains 'no figure' "$out" '1.23'
  assertNotContains 'no currency marker' "$out" '$'
}

test_the_flag_only_appends() {
  # Everything ahead of the cost segment has to render identically with the flag
  # and without, so the flag cannot reorder or recolour the bar. Compared as
  # whole visible lines rather than by substring, which would not notice a
  # segment that moved.
  local without with
  without=$(render 1.234 | visible)
  with=$(render 1.234 --cost | visible)
  assertEquals 'cost lands just inside the line cap' \
    "${without%"$CAP"}${SEP} \$1.23 ${CAP}" "$with"
}

test_the_statusline_writes_nothing_to_stderr() {
  # The bar renders into a corner of the terminal where a mangled line is easy
  # to read past, and Claude Code surfaces neither the exit code nor stderr.
  # Only capturing it here says the script itself went wrong.
  local err
  err=$(payload 1.234 | bash "$STATUSLINE" --cost 2>&1 >/dev/null)
  assertEquals 'with the flag' '' "$err"
  err=$(payload 1.234 | bash "$STATUSLINE" 2>&1 >/dev/null)
  assertEquals 'without it' '' "$err"
}

# --- the git segment --------------------------------------------------------
#
# Each test builds a throwaway repository under the suite's TMPDIR and renders
# from inside it with a payload naming it as the cwd. The cache is keyed by
# that cwd, so a fresh directory per test is also a cold cache per test.
#
# The developer's own git config is kept out: status.showUntrackedFiles,
# a default branch name, or a hook would otherwise change what is counted.

GIT_CONFIG_GLOBAL="$TMPDIR/gitconfig"
GIT_CONFIG_NOSYSTEM=1
GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL \
  GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
printf '[init]\n\tdefaultBranch = main\n' >"$GIT_CONFIG_GLOBAL"

ICON_BRANCH=$(printf '\xef\x90\x98')
ICON_STAGED=$(printf '\xef\x81\x86')
ICON_MODIFIED=$(printf '\xef\x81\x84')
ICON_REBASE=$(printf '\xee\x9c\xa8')
ICON_MERGE=$(printf '\xee\x9c\xa7')
ICON_STASH=$(printf '\xef\x83\x87')
readonly ICON_BRANCH ICON_STAGED ICON_MODIFIED ICON_REBASE ICON_MERGE ICON_STASH

# A repository at $1 with one commit on main.
make_repo() {
  mkdir -p "$1" &&
    git -C "$1" init -q &&
    printf 'a\n' >"$1/tracked" &&
    git -C "$1" add tracked &&
    git -C "$1" commit -qm initial
}

# The visible line rendered from inside directory $1, with the payload naming
# it as the cwd and project dir.
render_in() { # $1 = directory, $2... = statusline arguments
  local dir="$1"
  shift
  payload 0 |
    jq -c --arg dir "$dir" '.cwd = $dir | .workspace.project_dir = $dir' |
    (cd "$dir" && bash "$STATUSLINE" "$@") | visible
}

# The git segment of a visible line: what sits between the separator that
# opens it and the one that opens the context segment after it.
git_segment() {
  local line="$1" after_dir
  after_dir="${line#*"$SEP"*"$SEP"}"
  printf '%s' "${after_dir%%"$SEP"*}"
}

test_a_clean_branch_shows_only_its_name() {
  local repo="$TMPDIR/clean"
  make_repo "$repo"
  assertEquals " ${ICON_BRANCH} main " "$(git_segment "$(render_in "$repo")")"
}

test_working_tree_changes_are_counted_by_kind() {
  local repo="$TMPDIR/changes"
  make_repo "$repo"
  git -C "$repo" switch -qc feature
  printf 'b\n' >"$repo/tracked"
  printf 'x\n' >"$repo/staged" && git -C "$repo" add staged
  printf 'y\n' >"$repo/untracked1"
  printf 'z\n' >"$repo/untracked2"

  assertEquals \
    " ${ICON_BRANCH} feature ${ICON_MODIFIED} ?2 ~1 ${ICON_STAGED} 1 " \
    "$(git_segment "$(render_in "$repo")")"
}

test_stashes_are_counted_ahead_of_everything_else() {
  local repo="$TMPDIR/stash"
  make_repo "$repo"
  printf 'b\n' >"$repo/tracked" && git -C "$repo" stash -q
  printf 'c\n' >"$repo/tracked" && git -C "$repo" stash -q
  printf 'd\n' >"$repo/tracked"

  assertEquals " ${ICON_BRANCH} main ${ICON_STASH} 2 ${ICON_MODIFIED} ~1 " \
    "$(git_segment "$(render_in "$repo")")"
}

# A repository at $1 on branch feature tracking local branch base, with $2
# commits only feature has and $3 only base has.
make_tracking_repo() {
  local i
  make_repo "$1"
  git -C "$1" branch -q base
  git -C "$1" switch -qc feature
  git -C "$1" branch -q --set-upstream-to=base
  for ((i = 0; i < $2; i++)); do git -C "$1" commit -q --allow-empty -m ahead; done
  git -C "$1" switch -q base
  for ((i = 0; i < $3; i++)); do git -C "$1" commit -q --allow-empty -m behind; done
  git -C "$1" switch -q feature
}

test_commits_ahead_of_the_upstream_are_counted() {
  make_tracking_repo "$TMPDIR/ahead" 2 0
  assertEquals " ${ICON_BRANCH} feature ⇡2 " \
    "$(git_segment "$(render_in "$TMPDIR/ahead")")"
}

test_commits_behind_the_upstream_are_counted() {
  make_tracking_repo "$TMPDIR/behind" 0 3
  assertEquals " ${ICON_BRANCH} feature ⇣3 " \
    "$(git_segment "$(render_in "$TMPDIR/behind")")"
}

test_a_diverged_branch_shows_both_ways() {
  make_tracking_repo "$TMPDIR/diverged" 1 1
  assertEquals " ${ICON_BRANCH} feature ⇕ " \
    "$(git_segment "$(render_in "$TMPDIR/diverged")")"
}

test_a_detached_head_reads_as_head() {
  local repo="$TMPDIR/detached"
  make_repo "$repo"
  git -C "$repo" switch -q --detach
  assertEquals " ${ICON_BRANCH} HEAD " "$(git_segment "$(render_in "$repo")")"
}

test_a_rebase_in_progress_shows_its_step() {
  # Planted rather than staged with a real conflicting rebase: the files are
  # all the statusline reads, and these are the ones git writes.
  local repo="$TMPDIR/rebase"
  make_repo "$repo"
  mkdir "$repo/.git/rebase-merge"
  printf '2\n' >"$repo/.git/rebase-merge/msgnum"
  printf '5\n' >"$repo/.git/rebase-merge/end"

  assertEquals " ${ICON_BRANCH} main ${ICON_REBASE} 2/5 " \
    "$(git_segment "$(render_in "$repo")")"
}

test_a_merge_in_progress_is_flagged() {
  local repo="$TMPDIR/merge"
  make_repo "$repo"
  git -C "$repo" rev-parse HEAD >"$repo/.git/MERGE_HEAD"

  assertEquals " ${ICON_BRANCH} main ${ICON_MERGE} " \
    "$(git_segment "$(render_in "$repo")")"
}

test_a_linked_worktree_named_for_its_branch_shows_the_tree() {
  # Worktrunk's layout, <repo>.<sanitized branch>, so the worktree name says
  # nothing the branch does not and the branch icon becomes the tree instead.
  local repo="$TMPDIR/wtrepo"
  make_repo "$repo"
  git -C "$repo" worktree add -q -b feature/x "$TMPDIR/wtrepo.feature-x"

  assertEquals ' 🌳feature/x ' \
    "$(git_segment "$(render_in "$TMPDIR/wtrepo.feature-x")")"
}

test_a_directory_outside_git_has_no_git_segment() {
  local dir="$TMPDIR/plain"
  mkdir -p "$dir"
  local line
  line=$(render_in "$dir")

  assertNotContains 'no branch icon' "$line" "$ICON_BRANCH"
  assertNotContains 'no detached HEAD' "$line" 'HEAD'
}

# --- what a render costs ----------------------------------------------------

# A PATH holding a logging shim for every external command the statusline has
# ever used, each handing off to the real one. Prints the directory; calls are
# logged one line each to $1/calls.
shim_commands() {
  local dir="$1" cmd real
  mkdir -p "$dir"
  for cmd in cat cut date git jq md5sum stat tr wc; do
    real=$(command -v "$cmd") || continue
    cat >"$dir/$cmd" <<STUB
#!/usr/bin/env bash
printf '%s\\n' '$cmd' >>"$dir/calls"
exec "$real" "\$@"
STUB
    chmod +x "$dir/$cmd"
  done
}

calls_in() {
  local n
  n=$(wc -l <"$1/calls" 2>/dev/null | tr -d '[:space:]')
  : >"$1/calls"
  printf '%s' "${n:-0}"
}

test_a_render_starts_a_fixed_handful_of_processes() {
  # Claude Code renders the bar on every update of every open session, and on
  # Windows under endpoint protection each new process costs up to a second.
  # A render that started a few dozen took long enough for the next to begin
  # behind it, and the backlog stalled the whole machine. A cold render needs
  # jq for the payload and git twice for the repository; a warm one, inside
  # the cache window, needs jq alone.
  local repo="$TMPDIR/cost" shims="$TMPDIR/shims"
  make_repo "$repo"
  printf 'b\n' >"$repo/tracked"
  shim_commands "$shims"
  local json
  json=$(payload 0 |
    jq -c --arg dir "$repo" '.cwd = $dir | .workspace.project_dir = $dir')

  (cd "$repo" && PATH="$shims:$PATH" bash "$STATUSLINE" --cost <<<"$json") >/dev/null
  local cold
  cold=$(calls_in "$shims")
  (cd "$repo" && PATH="$shims:$PATH" bash "$STATUSLINE" --cost <<<"$json") >/dev/null
  local warm
  warm=$(calls_in "$shims")

  assertTrue "a cold render started $cold" "[ $cold -le 3 ]"
  assertTrue "a warm render started $warm" "[ $warm -le 1 ]"
}

# shUnit2 takes over here: it discovers the test_* functions above and prints
# the run summary.
# shellcheck source=/dev/null
. ./vendor/shunit2
