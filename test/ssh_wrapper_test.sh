#!/usr/bin/env bash
#
# Tests for the Termux ssh wrapper (home/dot_local/bin/wrappers/executable_ssh),
# which makes a plain `ssh` start and seed ssh-agent the way Termux's `ssha`
# does.
#
# The wrapper reaches Termux only through TERMUX__PREFIX, so each test points
# that at a sandbox holding stubs of source-ssh-agent.sh and the real ssh. The
# agent stub exports a socket path and records that it ran; the ssh stub
# records what it was given and what it saw. The wrapper is run with `sh`
# rather than through its shebang, which names Termux's sh and exists nowhere
# else, so the suite runs on any CI leg.
#
#   mise run test:shunit2 [-- shUnit2 args, e.g. a test_* name filter]
#
# Built on the vendored shUnit2 (vendor/shunit2): each behavior is a `test_*`
# function, discovered and summarized by the framework. Deliberately no `set -e`
# -- errexit fights shUnit2.

cd "$(dirname "$0")/.." || exit 1

readonly ROOT="$PWD"
readonly WRAPPER="$ROOT/home/dot_local/bin/wrappers/executable_ssh"

# --- harness ----------------------------------------------------------------

# Builds a sandbox prefix with stubbed agent script and ssh binary, and prints
# its path. The ssh stub exits with $STUB_SSH_EXIT, defaulting to 0.
make_prefix() {
  local prefix
  prefix=$(mktemp -d)
  mkdir -p "$prefix/libexec" "$prefix/bin"

  cat >"$prefix/libexec/source-ssh-agent.sh" <<STUB
echo sourced >>"$prefix/agent.log"
export SSH_AUTH_SOCK="$prefix/agent.socket"
STUB

  cat >"$prefix/bin/ssh" <<STUB
#!$(command -v sh)
for arg in "\$@"; do printf '%s\n' "\$arg"; done >"$prefix/ssh.args"
printf '%s\n' "\${SSH_AUTH_SOCK:-}" >"$prefix/ssh.sock"
exit "\${STUB_SSH_EXIT:-0}"
STUB
  chmod +x "$prefix/bin/ssh"

  printf '%s\n' "$prefix"
}

run_wrapper() {
  TERMUX__PREFIX="$PREFIX_DIR" sh "$WRAPPER" "$@"
}

setUp() {
  PREFIX_DIR=$(make_prefix)
}

tearDown() {
  rm -rf "$PREFIX_DIR"
}

# --- tests ------------------------------------------------------------------

test_passes_arguments_to_the_prefix_ssh_verbatim() {
  run_wrapper -p 2222 host 'echo "two words"'

  assertEquals "$(printf '%s\n' -p 2222 host 'echo "two words"')" \
    "$(cat "$PREFIX_DIR/ssh.args" 2>/dev/null)"
}

test_runs_ssh_with_the_agent_socket_from_the_agent_script() {
  run_wrapper host

  assertEquals "$PREFIX_DIR/agent.socket" \
    "$(cat "$PREFIX_DIR/ssh.sock" 2>/dev/null)"
}

test_ensures_the_agent_once_per_invocation() {
  run_wrapper host

  assertEquals 'sourced' "$(cat "$PREFIX_DIR/agent.log" 2>/dev/null)"
}

test_exits_with_the_status_of_ssh() {
  STUB_SSH_EXIT=255 run_wrapper host
  assertEquals 255 "$?"
}

# shUnit2 takes over here: it discovers the test_* functions above and prints
# the run summary.
# shellcheck source=/dev/null
. ./vendor/shunit2
