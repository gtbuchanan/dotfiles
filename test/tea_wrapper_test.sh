#!/usr/bin/env bash
#
# Tests for the Termux tea wrapper (home/dot_local/bin/wrappers/executable_tea),
# which starts and seeds ssh-agent before running tea, so a login that signs
# its API requests with an agent-held SSH key finds the agent.
#
# The wrapper reaches Termux only through TERMUX__PREFIX, so each test points
# that at a sandbox holding stubs of source-ssh-agent.sh and the real tea. The
# agent stub exports a socket path and records that it ran; the tea stub
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
readonly WRAPPER="$ROOT/home/dot_local/bin/wrappers/executable_tea"

# --- harness ----------------------------------------------------------------

# Builds a sandbox prefix with stubbed agent script and tea binary, and prints
# its path. The tea stub exits with $STUB_TEA_EXIT, defaulting to 0.
make_prefix() {
  local prefix
  prefix=$(mktemp -d)
  mkdir -p "$prefix/libexec" "$prefix/bin"

  cat >"$prefix/libexec/source-ssh-agent.sh" <<STUB
echo sourced >>"$prefix/agent.log"
export SSH_AUTH_SOCK="$prefix/agent.socket"
STUB

  cat >"$prefix/bin/tea" <<STUB
#!$(command -v sh)
for arg in "\$@"; do printf '%s\n' "\$arg"; done >"$prefix/tea.args"
printf '%s\n' "\${SSH_AUTH_SOCK:-}" >"$prefix/tea.sock"
exit "\${STUB_TEA_EXIT:-0}"
STUB
  chmod +x "$prefix/bin/tea"

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

test_passes_arguments_to_the_prefix_tea_verbatim() {
  run_wrapper issues list --title 'two words'

  assertEquals "$(printf '%s\n' issues list --title 'two words')" \
    "$(cat "$PREFIX_DIR/tea.args" 2>/dev/null)"
}

test_runs_tea_with_the_agent_socket_from_the_agent_script() {
  run_wrapper whoami

  assertEquals "$PREFIX_DIR/agent.socket" \
    "$(cat "$PREFIX_DIR/tea.sock" 2>/dev/null)"
}

test_ensures_the_agent_once_per_invocation() {
  run_wrapper whoami

  assertEquals 'sourced' "$(cat "$PREFIX_DIR/agent.log" 2>/dev/null)"
}

test_exits_with_the_status_of_tea() {
  STUB_TEA_EXIT=3 run_wrapper whoami
  assertEquals 3 "$?"
}

# shUnit2 takes over here: it discovers the test_* functions above and prints
# the run summary.
# shellcheck source=/dev/null
. ./vendor/shunit2
