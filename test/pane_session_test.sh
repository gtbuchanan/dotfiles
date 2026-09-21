#!/usr/bin/env bash
#
# Tests for pane-session, the SessionStart hook that pairs a multiplexer pane
# with the Claude session started in it.
#
# `claude --continue` resolves the most recent transcript for a directory,
# because ~/.claude/projects/<slugified-cwd>/ holds one .jsonl per session and
# records nothing about which pane produced it. Two panes in one repo therefore
# resume the same conversation, and whichever resumes first becomes the "most
# recent" the other then picks up. The hook records session_id per pane so each
# pane can resume with `--resume <id>` instead.
#
# tmux and psmux both export TMUX_PANE into the pane and child processes
# inherit it, which is what lets one bash hook serve every platform rather than
# a PowerShell one serving Windows alone.
#
# A server hands out pane ids from %0 on each start, so a record outlives the
# pane it describes and that id can later belong to an unrelated pane. Each
# record therefore stores the pane's directory, and resolution rejects a record
# whose directory no longer matches: a stale pane falls back to `--continue`
# rather than resuming a conversation from somewhere else.
#
# The hook is read straight from home/, not rendered through `chezmoi cat`: it
# is a plain file rather than a template, so the rendered output would be
# byte-identical, and reading it directly lets this suite run on every leg.
#
#   mise run test:shunit2 [-- shUnit2 args, e.g. a test_* name filter]
#
# Built on the vendored shUnit2 (vendor/shunit2): each behavior is a `test_*`
# function, discovered and summarized by the framework. Deliberately no `set -e`
# -- errexit fights shUnit2.

cd "$(dirname "$0")/.." || exit 1

readonly HOOK="$PWD/home/dot_claude/pane-session"

if [ ! -f "$HOOK" ]; then
  echo "SKIP: $HOOK not found"
  exit 0
fi

# --- harness ----------------------------------------------------------------

# A socket path of the shape tmux and psmux both put in $TMUX:
# <socket>,<server pid>,<session id>. Only the socket's leaf distinguishes one
# server from another, and the pid in its parent changes on every start.
socket() {
  printf '/tmp/psmux-37668/%s,60648,0' "${1:-default}"
}

# Records $2 as the session id for pane $1, from directory $3.
record() {
  local pane="$1" session_id="$2" dir="$3" namespace="${4:-default}"
  (
    cd "$dir" || exit 1
    printf '{"session_id":"%s"}' "$session_id" |
      TMUX_PANE="$pane" TMUX="$(socket "$namespace")" \
        bash "$HOOK" --record --root "$RECORDS"
  )
}

# Prints the session id pane $1 resolves to from directory $2, if any.
resolve() {
  local pane="$1" dir="$2" namespace="${3:-default}"
  (
    cd "$dir" || exit 1
    TMUX_PANE="$pane" TMUX="$(socket "$namespace")" \
      bash "$HOOK" --resolve --root "$RECORDS"
  )
}

# Tells pane $1 that session $2 (from directory $3) has ended.
forget() {
  local pane="$1" session_id="$2" dir="$3" namespace="${4:-default}"
  (
    cd "$dir" || exit 1
    printf '{"session_id":"%s"}' "$session_id" |
      TMUX_PANE="$pane" TMUX="$(socket "$namespace")" \
        bash "$HOOK" --forget --root "$RECORDS"
  )
}

setUp() {
  SANDBOX=$(mktemp -d)
  RECORDS="$SANDBOX/panes"
  PANE_CWD="$SANDBOX/repo"
  ELSEWHERE="$SANDBOX/other"
  mkdir -p "$RECORDS" "$PANE_CWD" "$ELSEWHERE"
}

tearDown() {
  [ -n "$SANDBOX" ] && rm -rf "$SANDBOX"
}

# --- recording --------------------------------------------------------------

test_a_record_carries_the_session_id_pane_and_directory() {
  record '%3' '11111111-2222-3333-4444-555555555555' "$PANE_CWD"

  local file
  file=$(find "$RECORDS" -name '*.json')
  assertEquals 'one record written' 1 "$(printf '%s\n' "$file" | grep -c .)"

  assertEquals 'session id' '11111111-2222-3333-4444-555555555555' \
    "$(jq -r '.sessionId' "$file")"
  assertEquals 'pane id' '%3' "$(jq -r '.paneId' "$file")"

  # Compared as directories rather than strings: on Windows the recorded path
  # is the native spelling MSYS handed jq, so `/tmp/x` comes back as
  # `C:/Users/.../Temp/x` and naming the same directory is the actual claim.
  local recorded
  recorded=$(jq -r '.cwd' "$file")
  assertTrue "record names the pane directory, got $recorded" \
    "[ '$recorded' -ef '$PANE_CWD' ]"
}

test_each_pane_keeps_its_own_record() {
  record '%3' 'aaaaaaaa-0000-0000-0000-000000000000' "$PANE_CWD"
  record '%4' 'bbbbbbbb-0000-0000-0000-000000000000' "$PANE_CWD"

  assertEquals 'two records' 2 "$(find "$RECORDS" -name '*.json' | grep -c .)"
}

test_a_shell_outside_a_multiplexer_records_nothing() {
  (
    cd "$PANE_CWD" || exit 1
    printf '{"session_id":"11111111-2222-3333-4444-555555555555"}' |
      TMUX_PANE='' TMUX='' bash "$HOOK" --record --root "$RECORDS"
  )

  assertEquals 'no records' 0 "$(find "$RECORDS" -type f | grep -c .)"
}

test_a_payload_without_a_session_id_records_nothing() {
  (
    cd "$PANE_CWD" || exit 1
    printf '{"cwd":"/somewhere"}' |
      TMUX_PANE='%3' TMUX="$(socket)" bash "$HOOK" --record --root "$RECORDS"
  )

  assertEquals 'no records' 0 "$(find "$RECORDS" -type f | grep -c .)"
}

# --- resolving --------------------------------------------------------------

test_a_pane_resolves_to_the_session_recorded_for_it() {
  record '%3' '11111111-2222-3333-4444-555555555555' "$PANE_CWD"

  assertEquals '11111111-2222-3333-4444-555555555555' \
    "$(resolve '%3' "$PANE_CWD")"
}

test_a_pane_with_no_record_resolves_to_nothing() {
  assertEquals '' "$(resolve '%9' "$PANE_CWD")"
}

test_a_record_from_another_directory_is_rejected() {
  record '%3' '11111111-2222-3333-4444-555555555555' "$PANE_CWD"

  assertEquals '' "$(resolve '%3' "$ELSEWHERE")"
}

test_panes_sharing_an_id_on_different_servers_stay_separate() {
  record '%1' 'aaaaaaaa-0000-0000-0000-000000000000' "$PANE_CWD" 'default'

  assertEquals '' "$(resolve '%1' "$PANE_CWD" 'other')"
}

test_the_second_session_in_a_pane_replaces_the_first() {
  record '%3' 'aaaaaaaa-0000-0000-0000-000000000000' "$PANE_CWD"
  record '%3' 'bbbbbbbb-0000-0000-0000-000000000000' "$PANE_CWD"

  assertEquals 'one record' 1 "$(find "$RECORDS" -name '*.json' | grep -c .)"
  assertEquals 'the newer session' 'bbbbbbbb-0000-0000-0000-000000000000' \
    "$(resolve '%3' "$PANE_CWD")"
}

# --- forgetting --------------------------------------------------------------

test_forget_removes_the_session_it_names() {
  record '%3' '11111111-2222-3333-4444-555555555555' "$PANE_CWD"
  forget '%3' '11111111-2222-3333-4444-555555555555' "$PANE_CWD"

  assertEquals 'no records left' 0 "$(find "$RECORDS" -type f | grep -c .)"
  assertEquals '' "$(resolve '%3' "$PANE_CWD")"
}

test_forget_leaves_a_record_from_a_newer_session() {
  # A SessionEnd hook call can arrive after the same pane has already started
  # a different session; the slot now belongs to that newer session and
  # forgetting the old one must not take it down too.
  record '%3' 'aaaaaaaa-0000-0000-0000-000000000000' "$PANE_CWD"
  record '%3' 'bbbbbbbb-0000-0000-0000-000000000000' "$PANE_CWD"
  forget '%3' 'aaaaaaaa-0000-0000-0000-000000000000' "$PANE_CWD"

  assertEquals 'the newer session survives' 'bbbbbbbb-0000-0000-0000-000000000000' \
    "$(resolve '%3' "$PANE_CWD")"
}

test_forget_with_no_record_is_a_noop() {
  forget '%9' '11111111-2222-3333-4444-555555555555' "$PANE_CWD"

  assertEquals 'no records' 0 "$(find "$RECORDS" -type f | grep -c .)"
}

test_forget_without_a_session_id_leaves_the_record() {
  record '%3' '11111111-2222-3333-4444-555555555555' "$PANE_CWD"
  (
    cd "$PANE_CWD" || exit 1
    printf '{}' |
      TMUX_PANE='%3' TMUX="$(socket)" bash "$HOOK" --forget --root "$RECORDS"
  )

  assertEquals '11111111-2222-3333-4444-555555555555' \
    "$(resolve '%3' "$PANE_CWD")"
}

test_forget_without_a_session_id_does_not_clear_a_corrupt_record() {
  # An empty payload's session_id and a record's missing sessionId field both
  # read back as '' from jq, so the two guards can look interchangeable. This
  # pins the one that would otherwise be dead: a hand-edited or truncated
  # record with no sessionId must not match an equally empty request.
  local key file
  key=$(printf 'default-%s' '%3' | tr -c 'A-Za-z0-9._-' '_')
  file="$RECORDS/$key.json"
  printf '{"cwd":"%s","paneId":"%%3"}' "$PANE_CWD" >"$file"

  (
    cd "$PANE_CWD" || exit 1
    printf '{}' |
      TMUX_PANE='%3' TMUX="$(socket)" bash "$HOOK" --forget --root "$RECORDS"
  )

  assertTrue 'the corrupt record is untouched' "[ -f '$file' ]"
}

# shUnit2 takes over here: it discovers the test_* functions above and prints
# the run summary.
# shellcheck source=/dev/null
. ./vendor/shunit2
