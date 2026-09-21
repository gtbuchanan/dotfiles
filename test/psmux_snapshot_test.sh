#!/usr/bin/env bash
#
# Tests for psmux-snapshot, which captures every session/window/pane on the
# current multiplexer server -- name, layout, cwd -- so psmux-restore can
# rebuild it after a reboot. pane-session backgrounds a call to this script on
# every successful --record/--forget; this script itself knows nothing about
# Claude Code or hooks, only about the multiplexer and the per-pane records
# pane-session already keeps.
#
# Each pane's own record ($root/<namespace>-<paneId>.json, written by
# pane-session --record) is cross-referenced here for the session id it last
# recorded, so a restored pane can be resumed directly with
# `claude --resume <id>` rather than falling back to `--continue`, which
# always picks wrong once two panes share a directory.
#
# psmux itself is stubbed: a fake `psmux` on PATH prints fixed rows for
# `list-panes -a -F ...`, ignoring the exact format string, since production
# always calls it with the same one. That is the only thing standing in for
# reality here -- everything downstream (the join against per-pane records,
# the grouping into sessions/windows/panes) is the real script.
#
#   mise run test:shunit2 [-- shUnit2 args, e.g. a test_* name filter]
#
# Built on the vendored shUnit2 (vendor/shunit2): each behavior is a `test_*`
# function, discovered and summarized by the framework. Deliberately no `set -e`
# -- errexit fights shUnit2.

cd "$(dirname "$0")/.." || exit 1

readonly SNAPSHOT="$PWD/home/dot_psmux/psmux-snapshot"

if [ ! -f "$SNAPSHOT" ]; then
  echo "SKIP: $SNAPSHOT not found"
  exit 0
fi

# --- harness ----------------------------------------------------------------

socket() {
  printf '/tmp/psmux-37668/%s,60648,0' "${1:-default}"
}

# Fixed rows: two panes in window 0 of session "main" (indices 0 and 1, cwd
# $PANE_CWD) and one pane in window 1 of session "side" (cwd $ELSEWHERE).
#
# Requires bare invocation -- no -L at all -- rather than matching list-panes
# alone: `-L default` addresses a *different* socket than the unnamed default
# server, confirmed live against a running psmux (`-L default` reported "no
# server running" for a server `psmux ls`, with no -L, had just listed). A
# guessed -S path was tried too and it silently fell back to the same wrong
# behavior -- proven wrong against an isolated second server, where an -S
# guess kept returning the *first* server's panes -- so bare invocation,
# verified live to reach the real default server every time, is the one
# addressing mode this stub accepts for it.
stub_psmux() {
  cat >"$BIN/psmux" <<STUB
#!/usr/bin/env bash
case "\$*" in
  *'-L'*) exit 1 ;;
  *'list-panes'*)
    printf '%s\\n' \\
      '%3	main	0	shell	1	layout-a	0	$PANE_CWD' \\
      '%4	main	0	shell	1	layout-a	1	$PANE_CWD' \\
      '%5	side	1	editor	0	layout-b	0	$ELSEWHERE'
    ;;
  *) exit 1 ;;
esac
STUB
  chmod +x "$BIN/psmux"
}

# Writes a pane-session record for pane $1 naming session id $2.
plant_record() {
  local pane_id="$1" session_id="$2" namespace="${3:-default}"
  local key
  key=$(printf '%s-%s' "$namespace" "$pane_id" | tr -c 'A-Za-z0-9._-' '_')
  jq -n --arg sessionId "$session_id" '{sessionId: $sessionId}' \
    >"$RECORDS/$key.json"
}

run_snapshot() {
  PATH="$BIN:$PATH" TMUX="$(socket)" \
    bash "$SNAPSHOT" --root "$RECORDS" --layout "$LAYOUT"
}

# Reports one pane in a session named $1, so two runs can be told apart by
# the name the layout ends up carrying.
stub_psmux_naming() {
  cat >"$BIN/psmux" <<STUB
#!/usr/bin/env bash
case "\$*" in
  *'-L'*) exit 1 ;;
  *'list-panes'*) printf '%s\\n' '%3	$1	0	shell	1	L	0	$PANE_CWD' ;;
  *) exit 1 ;;
esac
STUB
  chmod +x "$BIN/psmux"
}

# $TMUX is <socket>,<server pid>,<session id>, and the pid is what separates
# one server's lifetime from the next: it is how the snapshot knows a reboot
# has happened since the layout on disk was written.
run_snapshot_from_server() {
  PATH="$BIN:$PATH" TMUX="/tmp/psmux-37668/default,$1,0" \
    bash "$SNAPSHOT" --root "$RECORDS" --layout "$LAYOUT"
}

setUp() {
  SANDBOX=$(mktemp -d)
  RECORDS="$SANDBOX/panes"
  BIN="$SANDBOX/bin"
  LAYOUT="$SANDBOX/layout.json"
  HISTORY="$SANDBOX/layouts"
  PANE_CWD="$SANDBOX/repo"
  ELSEWHERE="$SANDBOX/other"
  mkdir -p "$RECORDS" "$BIN" "$PANE_CWD" "$ELSEWHERE"
}

tearDown() {
  [ -n "$SANDBOX" ] && rm -rf "$SANDBOX"
}

# --- behavior -----------------------------------------------------------------

test_uses_bare_invocation_for_the_unnamed_default_server() {
  # Exit code alone can't prove this: production exits 0 whether or not the
  # call succeeded, silent-failure style. Only a written layout proves a
  # bare call -- no -L, no -S -- is the one that actually reached the stub;
  # an -S guess was tried live and shown to fall back to the right answer
  # for the wrong reason, so this rejects that path too, not just -L.
  cat >"$BIN/psmux" <<STUB
#!/usr/bin/env bash
case "\$*" in
  *'-L'*|*'-S'*) exit 1 ;;
  *'list-panes'*) printf '%s\\n' '%3	main	0	shell	1	L	0	$PANE_CWD' ;;
  *) exit 1 ;;
esac
STUB
  chmod +x "$BIN/psmux"

  run_snapshot
  assertEquals 'wrote the layout from the bare-addressed row' 'main' \
    "$(jq -r '.sessions[0].name' "$LAYOUT" 2>/dev/null)"
}

test_uses_dashL_for_a_named_server() {
  # Unlike the unnamed default, -L <name> for a genuinely named server (one
  # actually started with -L) is verified live to reach it correctly, so a
  # named namespace should still use it rather than bare invocation, which
  # would address whichever server happens to be the unnamed default instead.
  cat >"$BIN/psmux" <<STUB
#!/usr/bin/env bash
case "\$*" in
  *'-L custom'*'list-panes'*) printf '%s\\n' '%9	work	0	shell	1	L	0	$PANE_CWD' ;;
  *) exit 1 ;;
esac
STUB
  chmod +x "$BIN/psmux"

  PATH="$BIN:$PATH" TMUX="$(socket custom)" \
    bash "$SNAPSHOT" --root "$RECORDS" --layout "$LAYOUT"

  assertEquals 'wrote the layout from the -L-addressed row' 'work' \
    "$(jq -r '.sessions[0].name' "$LAYOUT" 2>/dev/null)"
}

test_lays_out_every_session_window_and_pane() {
  stub_psmux
  run_snapshot

  assertEquals 'namespace' 'default' "$(jq -r '.namespace' "$LAYOUT")"
  assertEquals 'two sessions' 2 "$(jq '.sessions | length' "$LAYOUT")"

  assertEquals 'main has one window' 1 \
    "$(jq '.sessions[] | select(.name=="main") | .windows | length' "$LAYOUT")"
  assertEquals 'that window has two panes' 2 \
    "$(jq '.sessions[] | select(.name=="main") | .windows[0].panes | length' "$LAYOUT")"
  assertEquals 'layout string carried through' 'layout-a' \
    "$(jq -r '.sessions[] | select(.name=="main") | .windows[0].layout' "$LAYOUT")"
  assertEquals 'active flag carried through' 'true' \
    "$(jq -r '.sessions[] | select(.name=="main") | .windows[0].active' "$LAYOUT")"

  assertEquals 'side session present' 'editor' \
    "$(jq -r '.sessions[] | select(.name=="side") | .windows[0].name' "$LAYOUT")"
  assertEquals 'inactive window flag carried through' 'false' \
    "$(jq -r '.sessions[] | select(.name=="side") | .windows[0].active' "$LAYOUT")"
}

test_cross_references_each_panes_recorded_session_id() {
  plant_record '%3' '11111111-2222-3333-4444-555555555555'
  stub_psmux

  run_snapshot

  assertEquals 'recorded pane carries its session id' \
    '11111111-2222-3333-4444-555555555555' \
    "$(jq -r '.sessions[] | select(.name=="main") | .windows[0].panes[] |
      select(.index==0) | .sessionId' "$LAYOUT")"
  assertEquals 'a pane never recorded carries null' 'null' \
    "$(jq -r '.sessions[] | select(.name=="main") | .windows[0].panes[] |
      select(.index==1) | .sessionId' "$LAYOUT")"
}

test_is_a_noop_when_psmux_is_unavailable() {
  # Exclusive PATH, not run_snapshot's prepend: the default case now runs a
  # bare call, so on a dev machine with a real psmux installed, prepending
  # $BIN ahead of it would still find and reach that real server, making the
  # test pass by accident regardless of what this script does. bash itself
  # is resolved to an absolute path first -- an empty, exclusive PATH would
  # otherwise hide it too, and the test would then pass because the script
  # never ran at all rather than because it handled a missing psmux.
  local bash_bin
  bash_bin=$(command -v bash)

  PATH="$BIN" TMUX="$(socket)" \
    "$bash_bin" "$SNAPSHOT" --root "$RECORDS" --layout "$LAYOUT"

  assertFalse 'no layout file written' "[ -e '$LAYOUT' ]"
}

test_is_a_noop_when_the_server_reports_no_panes() {
  cat >"$BIN/psmux" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$BIN/psmux"

  run_snapshot

  assertFalse 'no layout file written' "[ -e '$LAYOUT' ]"
}

test_a_second_run_overwrites_the_first_rather_than_appending() {
  stub_psmux
  run_snapshot
  run_snapshot

  assertEquals 'still two sessions, not four' 2 \
    "$(jq '.sessions | length' "$LAYOUT")"
}

test_every_layout_is_also_kept_in_the_history() {
  # The first snapshot after a reboot replaces what the machine was running
  # with what survived the boot, and nothing else holds the difference: a
  # new server hands out pane ids from %1, so the per-pane records naming
  # the old panes are overwritten by the sessions started after it.
  stub_psmux_naming 'before'
  run_snapshot_from_server 1111
  stub_psmux_naming 'after'
  run_snapshot_from_server 2222

  assertEquals 'the running server wrote the layout' 'after' \
    "$(jq -r '.sessions[0].name' "$LAYOUT")"
  assertEquals 'both layouts are in the history' 2 \
    "$(find "$HISTORY" -name '*.json' 2>/dev/null | wc -l)"
  assertEquals 'the pre-reboot one among them' 1 \
    "$(grep -l '"before"' "$HISTORY"/*.json 2>/dev/null | wc -l)"
}

test_the_history_keeps_saves_that_share_a_second() {
  # Two snapshots inside the same second are ordinary: a SessionEnd and the
  # SessionStart replacing it land together. A name carrying only a
  # timestamp would collide and the older of the pair would be lost.
  stub_psmux_naming 'before'
  run_snapshot_from_server 1111
  stub_psmux_naming 'after'
  run_snapshot_from_server 1111

  assertEquals 'both survived' 2 \
    "$(find "$HISTORY" -name '*.json' 2>/dev/null | wc -l)"
}

test_a_layout_past_the_retention_window_is_swept() {
  stub_psmux
  run_snapshot
  mkdir -p "$HISTORY"
  : >"$HISTORY/layout-20000101-000000-0.json"
  touch -d '2000-01-01' "$HISTORY/layout-20000101-000000-0.json" 2>/dev/null
  run_snapshot

  assertFalse 'the ancient one is gone' \
    "[ -e '$HISTORY/layout-20000101-000000-0.json' ]"
  assertNotEquals 'recent ones are kept' 0 \
    "$(find "$HISTORY" -name '*.json' 2>/dev/null | wc -l)"
}

test_a_file_that_is_not_a_layout_is_left_in_place() {
  # The sweep runs unattended against a directory under the user's home.
  stub_psmux
  mkdir -p "$HISTORY"
  : >"$HISTORY/notes.txt"
  touch -d '2000-01-01' "$HISTORY/notes.txt" 2>/dev/null
  run_snapshot

  assertTrue 'an unrelated old file is untouched' "[ -e '$HISTORY/notes.txt' ]"
}

# shUnit2 takes over here: it discovers the test_* functions above and prints
# the run summary.
# shellcheck source=/dev/null
. ./vendor/shunit2
