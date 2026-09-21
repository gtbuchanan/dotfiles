#!/usr/bin/env bash
#
# Tests for ccr, the bash half of the resume shortcut: it asks pane-session
# which conversation belongs to this pane and hands the id to `claude --resume`,
# falling back to `--continue` when the pane has no record.
#
# The pair is what makes the SessionStart hook useful. `ccc` starts a new
# session, `claude --continue` takes the newest one in the directory, and only
# `--resume <id>` reaches the conversation this pane was holding.
#
# Rendered with `chezmoi execute-template` rather than `chezmoi cat`, which the
# hass-vault suite uses: .bash_aliases is unmanaged on Windows, so `cat` would
# skip the suite on the platform where psmux runs. execute-template consults no
# .chezmoiignore, so the same assertions run everywhere chezmoi is installed.
#
# Nothing real is reached. HOME points at a sandbox holding a stub
# pane-session, so the function's own lookup path is exercised without a
# production seam, and a `claude` stub on PATH records the argv it was handed --
# which is the whole claim these tests make.
#
#   mise run test:shunit2 [-- shUnit2 args, e.g. a test_* name filter]
#
# Built on the vendored shUnit2 (vendor/shunit2): each behavior is a `test_*`
# function, discovered and summarized by the framework. Deliberately no `set -e`
# -- errexit fights shUnit2.

cd "$(dirname "$0")/.." || exit 1

readonly ROOT="$PWD"
readonly SOURCE="$ROOT/home/dot_bash_aliases.tmpl"

if [ ! -f "$SOURCE" ]; then
  echo "SKIP: $SOURCE not found"
  exit 0
fi

if ! command -v chezmoi >/dev/null 2>&1; then
  echo "SKIP: chezmoi not available"
  exit 0
fi

# --- harness ----------------------------------------------------------------

oneTimeSetUp() {
  RENDERED=$(mktemp)
  if ! chezmoi execute-template --source "$ROOT/home" --no-tty \
    <"$SOURCE" >"$RENDERED" 2>/dev/null; then
    echo "SKIP: could not render $SOURCE"
    exit 0
  fi
}

oneTimeTearDown() {
  [ -n "${RENDERED:-}" ] && rm -f "$RENDERED"
}

setUp() {
  SANDBOX=$(mktemp -d)
  BIN="$SANDBOX/bin"
  LOG="$SANDBOX/claude-argv"
  mkdir -p "$BIN" "$SANDBOX/.claude"

  # Records the argv `ccr` builds, one argument per line, and nothing else.
  cat >"$BIN/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$CLAUDE_ARGV_LOG"
STUB

  # ccr clears the screen the way ccc does; a no-op keeps the escape sequence
  # out of the suite's output.
  cat >"$BIN/clear" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB

  chmod +x "$BIN/claude" "$BIN/clear"
}

tearDown() {
  [ -n "${SANDBOX:-}" ] && rm -rf "$SANDBOX"
}

# Stands in for the recorded pane, printing $1 as the session id it resolves to.
stub_pane_session() {
  cat >"$SANDBOX/.claude/pane-session" <<STUB
#!/usr/bin/env bash
printf '%s' '$1'
STUB
  chmod +x "$SANDBOX/.claude/pane-session"
}

# Runs ccr with the sandbox as HOME, and prints the argv claude received.
run_ccr() {
  (
    HOME="$SANDBOX" \
      PATH="$BIN:$PATH" \
      CLAUDE_ARGV_LOG="$LOG" \
      bash -c ". '$RENDERED'; ccr $*" >/dev/null 2>&1
  )
  cat "$LOG" 2>/dev/null
}

# --- behavior ---------------------------------------------------------------

test_a_recorded_pane_resumes_its_own_session() {
  stub_pane_session '11111111-2222-3333-4444-555555555555'

  assertEquals 'resumes by id' \
    "$(printf '%s\n' '--resume' '11111111-2222-3333-4444-555555555555')" \
    "$(run_ccr)"
}

test_a_pane_with_no_record_continues_the_newest_session() {
  stub_pane_session ''

  assertEquals 'falls back' '--continue' "$(run_ccr)"
}

test_extra_arguments_reach_claude() {
  stub_pane_session '11111111-2222-3333-4444-555555555555'

  assertEquals 'arguments forwarded after the resume flag' \
    "$(printf '%s\n' '--resume' '11111111-2222-3333-4444-555555555555' '--model' 'opus')" \
    "$(run_ccr --model opus)"
}

test_a_missing_pane_session_script_still_starts_claude() {
  assertEquals 'falls back rather than failing' '--continue' "$(run_ccr)"
}

# shUnit2 takes over here: it discovers the test_* functions above and prints
# the run summary.
# shellcheck source=/dev/null
. ./vendor/shunit2
