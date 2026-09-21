#!/usr/bin/env bash
#
# Tests for psmux-restore, which reads the layout psmux-snapshot wrote and
# recreates it -- sessions, windows, panes, the saved layout actually applied
# (the old psmux-resurrect captured a layout string and never called
# select-layout, so it was dead data) -- then resumes each pane's own
# conversation directly with `claude --resume <id>`.
#
# --resume rather than `ccr`/`--continue` is the point of the whole
# pane-session/psmux-snapshot chain: a freshly restored pane's own live pane-
# id lookup can never match anything (a new server hands out ids from %0), so
# `ccr` would always fall back to `--continue`, which is wrong the instant two
# restored panes share a directory.
#
# psmux is stubbed to log every invocation's argv, one call per line, and to
# answer each creation command's `-P -F` with a value chosen to differ from
# whatever index the fixture saved -- proving the script targets the pane or
# window psmux actually just reported, not the number that happened to be
# saved for it. A real server's own index-assignment behavior (sequential in
# creation order, `-P -F` reporting it directly) was verified by hand against
# a live, isolated psmux server; this suite covers the restore logic itself.
#
#   mise run test:shunit2 [-- shUnit2 args, e.g. a test_* name filter]
#
# Built on the vendored shUnit2 (vendor/shunit2): each behavior is a `test_*`
# function, discovered and summarized by the framework. Deliberately no `set -e`
# -- errexit fights shUnit2.

cd "$(dirname "$0")/.." || exit 1

readonly RESTORE="$PWD/home/dot_psmux/psmux-restore"

if [ ! -f "$RESTORE" ]; then
  echo "SKIP: $RESTORE not found"
  exit 0
fi

# --- harness ----------------------------------------------------------------

# Logs every call as one line of tab-joined argv, then answers each
# subcommand psmux-restore depends on. has-session succeeds only for a name
# listed in $EXISTING (space-separated), simulating a session that survived
# the restart and should not be recreated. Every creation command's `-P -F`
# prints a number distinct from anything the fixture below saves, so a test
# asserting on that number can only pass if the script used what psmux
# reported rather than the value it started from.
write_psmux_stub() {
  cat >"$BIN/psmux" <<STUB
#!/usr/bin/env bash
printf '%s\\t' "\$@" >>"$LOG"
printf '\\n' >>"$LOG"

case " \$* " in
  *' has-session '*)
    for existing in $EXISTING; do
      [[ " \$* " == *" -t \$existing "* ]] && exit 0
    done
    exit 1
    ;;
  *' new-session '*) echo '30' ;;
  *' new-window '*) echo '31' ;;
  *' split-window '*) echo '32' ;;
  *' list-panes '*) echo '33' ;;
esac
exit 0
STUB
  chmod +x "$BIN/psmux"
}

# $1: session name, $2: JSON array of windows (each {name, layout, active,
# panes: [{cwd, sessionId}]}) to write as the whole layout's one session.
# $3: namespace, defaulting to the unnamed default server.
write_layout() {
  jq -n --arg namespace "${3:-default}" --arg name "$1" --argjson windows "$2" \
    '{namespace: $namespace, sessions: [{name: $name, windows: $windows}]}' \
    >"$LAYOUT"
}

run_restore() {
  PATH="$BIN:$PATH" bash "$RESTORE" --layout "$LAYOUT"
}

# Every call matching $1 (a substring), across the whole log. `--` guards a
# pattern starting with a dash (e.g. '-L') from being parsed as a grep flag.
calls_matching() {
  grep -c -- "$1" "$LOG" 2>/dev/null || true
}

setUp() {
  SANDBOX=$(mktemp -d)
  BIN="$SANDBOX/bin"
  LOG="$SANDBOX/argv.log"
  LAYOUT="$SANDBOX/layout.json"
  EXISTING=''
  mkdir -p "$BIN"
  : >"$LOG"
}

tearDown() {
  [ -n "$SANDBOX" ] && rm -rf "$SANDBOX"
}

# --- behavior -----------------------------------------------------------------

test_uses_bare_invocation_for_the_unnamed_default_server() {
  # `-L default` addresses a different, unrelated socket than the ordinary
  # unnamed default server does -- confirmed live, it reported "no server
  # running" for a server bare psmux had just listed. A saved namespace of
  # "default" must therefore never reach psmux as an -L argument at all.
  write_layout 'main' '[{"name":"one","layout":"L","active":true,
    "panes":[{"cwd":"/repo","sessionId":null}]}]'
  write_psmux_stub

  run_restore

  assertEquals 'no call carries -L' 0 "$(calls_matching '-L')"
}

test_uses_dashL_for_a_named_server() {
  # Unlike the unnamed default, -L <name> for a genuinely named server (one
  # actually started with -L) does reach it correctly, so a saved namespace
  # that isn't "default" should still address the server that way.
  write_layout 'work' '[{"name":"one","layout":"L","active":true,
    "panes":[{"cwd":"/repo","sessionId":null}]}]' 'custom'
  write_psmux_stub

  run_restore

  assertNotEquals 'at least one call carries -L custom' 0 \
    "$(calls_matching '-L.*custom')"
}

test_is_a_noop_when_the_layout_file_is_missing() {
  write_psmux_stub

  run_restore

  assertEquals 'no psmux calls at all' 0 "$(calls_matching '.')"
}

test_skips_a_session_that_already_exists() {
  write_layout 'already-there' '[{"name":"one","layout":"L","active":true,
    "panes":[{"cwd":"/a","sessionId":null}]}]'
  EXISTING='already-there'
  write_psmux_stub

  run_restore

  assertEquals 'no new-session for it' 0 "$(calls_matching 'new-session.*already-there')"
}

test_creates_a_missing_session_at_its_first_panes_directory() {
  write_layout 'main' '[{"name":"one","layout":"L","active":true,
    "panes":[{"cwd":"/repo","sessionId":null}]}]'
  write_psmux_stub

  run_restore

  assertNotEquals 'new-session created it at the right directory' 0 \
    "$(calls_matching 'new-session.*-s.*main.*-c.*/repo')"
}

test_renames_the_first_window_to_its_saved_name() {
  write_layout 'main' '[{"name":"editor","layout":"L","active":true,
    "panes":[{"cwd":"/repo","sessionId":null}]}]'
  write_psmux_stub

  run_restore

  # new-session's -P -F reports window 30 (see write_psmux_stub); the rename
  # must target that, not window 0 or 1.
  assertNotEquals 'renamed the reported window to the saved name' 0 \
    "$(calls_matching 'rename-window.*main:30.*editor')"
}

test_creates_one_pane_per_extra_pane_at_its_own_directory() {
  write_layout 'main' '[{"name":"one","layout":"L","active":true,
    "panes":[{"cwd":"/repo","sessionId":null},{"cwd":"/repo/sub","sessionId":null}]}]'
  write_psmux_stub

  run_restore

  assertEquals 'one split for the second pane' 1 \
    "$(calls_matching 'split-window.*-c./repo/sub')"
}

test_applies_the_saved_layout_string() {
  write_layout 'main' '[{"name":"one","layout":"a1b2,80x24,0,0,1","active":true,
    "panes":[{"cwd":"/repo","sessionId":null}]}]'
  write_psmux_stub

  run_restore

  assertEquals 'select-layout with the exact saved string' 1 \
    "$(calls_matching 'select-layout.*a1b2,80x24,0,0,1')"
}

test_resumes_a_pane_that_has_a_recorded_session_id() {
  write_layout 'main' '[{"name":"one","layout":"L","active":true,
    "panes":[
      {"cwd":"/repo","sessionId":null},
      {"cwd":"/repo","sessionId":"11111111-2222-3333-4444-555555555555"}
    ]}]'
  write_psmux_stub

  run_restore

  # The saved index for this pane is 1; split-window's -P -F reports 32.
  # Targeting :1 instead of :32 would be using the saved index, not the one
  # psmux actually just assigned.
  assertEquals 'resumed at the reported pane, by id' 1 \
    "$(calls_matching 'send-keys.*main:30\.32.*claude --resume 11111111-2222-3333-4444-555555555555')"
}

test_does_not_send_anything_to_a_pane_with_no_recorded_session() {
  write_layout 'main' '[{"name":"one","layout":"L","active":true,
    "panes":[{"cwd":"/repo","sessionId":null}]}]'
  write_psmux_stub

  run_restore

  assertEquals 'no send-keys at all' 0 "$(calls_matching 'send-keys')"
}

test_a_gap_in_the_saved_window_or_pane_indices_changes_nothing() {
  # Closing a tab doesn't reflow the ones after it, so a saved layout can
  # carry non-contiguous window/pane index fields (windows 0 and 5; panes 0
  # and 7, say -- 1-4 and 1-6 having been closed since the save). Restore
  # never reads those fields at all, only array position, so their being
  # non-contiguous -- or present -- must not change anything it does.
  write_layout 'main' '[
    {"name":"one","layout":"L1","active":true,"index":0,
      "panes":[{"cwd":"/repo","sessionId":null,"index":0}]},
    {"name":"two","layout":"L2","active":false,"index":5,
      "panes":[
        {"cwd":"/repo/other","sessionId":null,"index":0},
        {"cwd":"/repo/other","sessionId":"22222222-3333-4444-5555-666666666666","index":7}
      ]}
  ]'
  write_psmux_stub

  run_restore

  assertEquals 'second window still created by name' 1 \
    "$(calls_matching 'new-window.*-n.*two.*-c./repo/other')"
  assertEquals 'its extra pane still split at the right directory' 1 \
    "$(calls_matching 'split-window.*-c./repo/other')"
  assertEquals 'still resumed at the reported pane, by id, not the saved 7' 1 \
    "$(calls_matching 'send-keys.*main:31\.32.*claude --resume 22222222-3333-4444-5555-666666666666')"
}

test_creates_a_second_window_with_its_own_panes_and_layout() {
  write_layout 'main' '[
    {"name":"one","layout":"L1","active":true,
      "panes":[{"cwd":"/repo","sessionId":null}]},
    {"name":"two","layout":"L2","active":false,
      "panes":[{"cwd":"/repo/other","sessionId":null}]}
  ]'
  write_psmux_stub

  run_restore

  assertEquals 'new-window for the second window' 1 \
    "$(calls_matching 'new-window.*-n.*two.*-c./repo/other')"
  assertEquals 'its own layout applied' 1 "$(calls_matching 'select-layout.*L2')"
}

# shUnit2 takes over here: it discovers the test_* functions above and prints
# the run summary.
# shellcheck source=/dev/null
. ./vendor/shunit2
