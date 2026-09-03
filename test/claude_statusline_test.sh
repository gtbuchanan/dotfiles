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

# shUnit2 takes over here: it discovers the test_* functions above and prints
# the run summary.
# shellcheck source=/dev/null
. ./vendor/shunit2
