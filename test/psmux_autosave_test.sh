#!/usr/bin/env bash
#
# Tests for psmux-autosave, the periodic layout save. Claude's SessionStart
# and SessionEnd are the only other snapshot triggers, so a pane opened,
# closed or moved between two of them is missing from the layout until the
# next one fires -- and psmux has no hook that closes the gap: `kill-pane`
# and `kill-window`, which prefix-x and prefix-& are bound to, fire nothing
# at all, measured against a live server.
#
# What this must not become is psmux-continuum, whose `client-attached` hook
# started an unbounded `while ($true)` pwsh loop on every attach, deduped by
# nothing and reaped by nothing -- its own plugin.conf calls that "harmless
# since saves are idempotent", which misses that the processes accumulate.
# Hence the two properties most of this suite is about: exactly one loop, and
# a loop that goes away when the server does.
#
#   mise run test:shunit2 [-- shUnit2 args, e.g. a test_* name filter]
#
# Built on the vendored shUnit2 (vendor/shunit2): each behavior is a `test_*`
# function, discovered and summarized by the framework. Deliberately no `set -e`
# -- errexit fights shUnit2.

cd "$(dirname "$0")/.." || exit 1

readonly AUTOSAVE="$PWD/home/dot_psmux/psmux-autosave"

if [ ! -f "$AUTOSAVE" ]; then
  echo "SKIP: $AUTOSAVE not found"
  exit 0
fi

# --- harness ----------------------------------------------------------------

# $1 is the exit status the stub reports for every call: 0 for a server that
# is still there, 1 for one that has gone. That status is the whole of what
# the loop reads psmux for.
stub_psmux() {
  cat >"$BIN/psmux" <<STUB
#!/usr/bin/env bash
exit $1
STUB
  chmod +x "$BIN/psmux"
}

# Logs one line of arguments per call, so a test can count saves and see what
# the loop passed.
stub_snapshot() {
  cat >"$BIN/snapshot" <<STUB
#!/usr/bin/env bash
printf '%s\\n' "\$*" >>"$SAVELOG"
STUB
  chmod +x "$BIN/snapshot"
}

# Bounded, so a loop that fails to notice a dead server fails the test rather
# than hanging the suite. 124 is what timeout reports when it has to step in.
run_autosave_until_it_exits() {
  PATH="$BIN:$PATH" timeout 10 \
    bash "$AUTOSAVE" --interval 0.2 --pidfile "$PIDFILE" \
    --snapshot-bin "$BIN/snapshot"
}

start_autosave() {
  PATH="$BIN:$PATH" bash "$AUTOSAVE" --interval 0.2 --pidfile "$PIDFILE" \
    --snapshot-bin "$BIN/snapshot" "$@" &
  LOOP_PID=$!
}

stop_autosave() {
  [ -n "${LOOP_PID:-}" ] || return 0
  kill "$LOOP_PID" 2>/dev/null
  wait "$LOOP_PID" 2>/dev/null
  LOOP_PID=''
}

saves() {
  grep -c . "$SAVELOG" 2>/dev/null || true
}

setUp() {
  SANDBOX=$(mktemp -d)
  BIN="$SANDBOX/bin"
  PIDFILE="$SANDBOX/autosave.pid"
  SAVELOG="$SANDBOX/saves.log"
  LOOP_PID=''
  mkdir -p "$BIN"
  : >"$SAVELOG"
}

tearDown() {
  stop_autosave
  [ -n "$SANDBOX" ] && rm -rf "$SANDBOX"
}

# --- behavior -----------------------------------------------------------------

test_it_keeps_saving_while_the_server_is_alive() {
  stub_psmux 0
  stub_snapshot

  start_autosave
  sleep 1
  stop_autosave

  assertTrue "saved repeatedly, got $(saves)" "[ $(saves) -ge 2 ]"
}

test_it_stops_once_the_server_is_gone() {
  stub_psmux 1
  stub_snapshot

  run_autosave_until_it_exits
  local rc=$?

  assertEquals 'returned on its own rather than looping on' 0 "$rc"
  assertEquals 'saved nothing against a server that had gone' 0 "$(saves)"
}

test_it_clears_its_pidfile_when_it_stops() {
  stub_psmux 1
  stub_snapshot

  run_autosave_until_it_exits

  assertFalse 'pidfile removed on the way out' "[ -e '$PIDFILE' ]"
}

test_a_second_instance_exits_rather_than_doubling_the_loop() {
  stub_psmux 0
  stub_snapshot
  # This shell is certainly alive, so its pid stands in for a running loop.
  printf '%s\n' "$$" >"$PIDFILE"

  run_autosave_until_it_exits
  local rc=$?

  assertEquals 'stood down without error' 0 "$rc"
  assertEquals 'took no save of its own' 0 "$(saves)"
  assertTrue 'left the running loop pidfile alone' "[ -e '$PIDFILE' ]"
}

test_a_pidfile_left_by_a_dead_instance_does_not_block_startup() {
  # Power loss leaves one behind. Refusing to start then would mean no
  # periodic save again until someone deleted a file by hand.
  stub_psmux 0
  stub_snapshot
  printf '%s\n' '999999' >"$PIDFILE"

  start_autosave
  sleep 0.6
  stop_autosave

  assertTrue "started anyway, saves=$(saves)" "[ $(saves) -ge 1 ]"
}

test_it_tells_the_snapshot_which_server_to_capture() {
  # The loop has no pane and so no $TMUX to derive one from, which is the
  # whole reason psmux-snapshot takes --namespace.
  stub_psmux 0
  stub_snapshot

  start_autosave --namespace custom
  sleep 0.6
  stop_autosave

  local matched
  matched=$(grep -c -- '--namespace custom' "$SAVELOG" 2>/dev/null || true)
  assertTrue "forwarded the namespace, matched=$matched" "[ $matched -ge 1 ]"
}

# shUnit2 takes over here: it discovers the test_* functions above and prints
# the run summary.
# shellcheck source=/dev/null
. ./vendor/shunit2
