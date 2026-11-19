#!/usr/bin/env bash
#
# Tests for the Termux gt wrapper (home/dot_local/bin/wrappers/executable_gt),
# which runs gt's static linux-arm64 release under proot so it can resolve
# names, with Termux's CA bundle and a seeded ssh-agent for SSH-signed logins.
#
# The wrapper reaches Termux only through TERMUX__PREFIX and the binary only
# through HOME, so each test points both at a sandbox. The agent stub exports a
# socket path and records that it ran; the proot stub records its arguments and
# the environment it saw instead of running anything. The wrapper is run with
# `sh` rather than through its shebang, which names Termux's sh and exists
# nowhere else, so the suite runs on any CI leg.
#
#   mise run test:shunit2 [-- shUnit2 args, e.g. a test_* name filter]
#
# Built on the vendored shUnit2 (vendor/shunit2): each behavior is a `test_*`
# function, discovered and summarized by the framework. Deliberately no `set -e`
# -- errexit fights shUnit2.

cd "$(dirname "$0")/.." || exit 1

readonly ROOT="$PWD"
readonly WRAPPER="$ROOT/home/dot_local/bin/wrappers/executable_gt"

# --- harness ----------------------------------------------------------------

# Builds a sandbox holding a prefix with stubbed agent script and proot, and an
# empty home, and prints its path. The proot stub exits with $STUB_PROOT_EXIT,
# defaulting to 0.
make_sandbox() {
  local sandbox
  sandbox=$(mktemp -d)
  mkdir -p "$sandbox/prefix/libexec" "$sandbox/prefix/bin" "$sandbox/home"

  cat >"$sandbox/prefix/libexec/source-ssh-agent.sh" <<STUB
echo sourced >>"$sandbox/agent.log"
export SSH_AUTH_SOCK="$sandbox/agent.socket"
STUB

  cat >"$sandbox/prefix/bin/proot" <<STUB
#!$(command -v sh)
for arg in "\$@"; do printf '%s\n' "\$arg"; done >"$sandbox/proot.args"
printf '%s\n' "\${SSH_AUTH_SOCK:-}" >"$sandbox/proot.sock"
printf '%s\n' "\${SSL_CERT_FILE:-}" >"$sandbox/proot.cert"
exit "\${STUB_PROOT_EXIT:-0}"
STUB
  chmod +x "$sandbox/prefix/bin/proot"

  printf '%s\n' "$sandbox"
}

run_wrapper() {
  TERMUX__PREFIX="$SANDBOX/prefix" HOME="$SANDBOX/home" sh "$WRAPPER" "$@"
}

setUp() {
  SANDBOX=$(make_sandbox)
  unset SSL_CERT_FILE
}

tearDown() {
  rm -rf "$SANDBOX"
}

# --- tests ------------------------------------------------------------------

test_runs_the_installed_gt_under_proot_with_the_resolver_bound() {
  run_wrapper pr view 1 --json 'number,title'

  assertEquals "$(printf '%s\n' \
    -b "$SANDBOX/prefix/etc/resolv.conf:/etc/resolv.conf" \
    "$SANDBOX/home/.local/share/gitea-cli/gt" \
    pr view 1 --json 'number,title')" \
    "$(cat "$SANDBOX/proot.args" 2>/dev/null)"
}

test_points_ssl_cert_file_at_the_termux_bundle() {
  run_wrapper auth status

  assertEquals "$SANDBOX/prefix/etc/tls/cert.pem" \
    "$(cat "$SANDBOX/proot.cert" 2>/dev/null)"
}

test_keeps_an_ssl_cert_file_the_caller_set() {
  SSL_CERT_FILE=/custom/ca.pem run_wrapper auth status

  assertEquals /custom/ca.pem "$(cat "$SANDBOX/proot.cert" 2>/dev/null)"
}

test_runs_gt_with_the_agent_socket_from_the_agent_script() {
  run_wrapper auth status

  assertEquals "$SANDBOX/agent.socket" \
    "$(cat "$SANDBOX/proot.sock" 2>/dev/null)"
}

test_ensures_the_agent_once_per_invocation() {
  run_wrapper auth status

  assertEquals 'sourced' "$(cat "$SANDBOX/agent.log" 2>/dev/null)"
}

test_exits_with_the_status_of_gt() {
  STUB_PROOT_EXIT=4 run_wrapper auth status
  assertEquals 4 "$?"
}

# shUnit2 takes over here: it discovers the test_* functions above and prints
# the run summary.
# shellcheck source=/dev/null
. ./vendor/shunit2
