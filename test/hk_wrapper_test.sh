#!/usr/bin/env bash
#
# Tests for the Termux hk wrapper (home/dot_local/bin/executable_hk.tmpl),
# which launches the static musl hk that
# run_onchange_after_install-hk.sh installs out of band.
#
# Rendered with `chezmoi execute-template`, which consults no .chezmoiignore,
# so the suite runs on any host with chezmoi. The wrapper finds hk under
# $HOME, so each test points HOME at a sandbox holding an hk stub that
# records what it was given.
#
#   mise run test:shunit2 [-- shUnit2 args, e.g. a test_* name filter]
#
# Built on the vendored shUnit2 (vendor/shunit2): each behavior is a `test_*`
# function, discovered and summarized by the framework. Deliberately no `set -e`
# -- errexit fights shUnit2.

cd "$(dirname "$0")/.." || exit 1

readonly ROOT="$PWD"
readonly SOURCE="$ROOT/home/dot_local/bin/executable_hk.tmpl"

if ! command -v chezmoi >/dev/null 2>&1; then
  echo "SKIP: chezmoi not available"
  exit 0
fi

# --- harness ----------------------------------------------------------------

oneTimeSetUp() {
  RENDERED=$(mktemp)
  if ! chezmoi execute-template --source "$ROOT/home" --no-tty \
    <"$SOURCE" >"$RENDERED" 2>/dev/null; then
    fail "could not render $SOURCE"
  fi
  HK_VERSION=$(chezmoi execute-template --source "$ROOT/home" --no-tty \
    '{{ .hk_version }}')
}

oneTimeTearDown() {
  [ -n "${RENDERED:-}" ] && rm -f "$RENDERED"
}

setUp() {
  SANDBOX=$(mktemp -d)
  mkdir -p "$SANDBOX/.local/share/hk"
  cat >"$SANDBOX/.local/share/hk/hk-$HK_VERSION" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$HOME/hk.args"
printf '%s\n' "$SSL_CERT_FILE" >"$HOME/hk.cert"
exit "${STUB_EXIT:-0}"
STUB
  chmod +x "$SANDBOX/.local/share/hk/hk-$HK_VERSION"
}

tearDown() {
  [ -n "${SANDBOX:-}" ] && rm -rf "$SANDBOX"
}

run_wrapper() {
  HOME="$SANDBOX" bash "$RENDERED" "$@" >"$SANDBOX/wrapper.out" 2>&1
}

# --- behavior ---------------------------------------------------------------

test_passes_its_arguments_to_the_pinned_hk() {
  run_wrapper --cd 'some dir' check --all
  assertEquals 'hk arguments' '--cd some dir check --all' "$(cat "$SANDBOX/hk.args" 2>/dev/null)"
}

test_exits_with_the_status_hk_exits_with() {
  STUB_EXIT=3 run_wrapper check
  rc=$?
  assertEquals 'exit status' 3 "$rc"
}

test_points_ssl_cert_file_at_the_termux_bundle_by_default() {
  (unset SSL_CERT_FILE && run_wrapper check)
  assertEquals 'SSL_CERT_FILE' '/data/data/com.termux/files/usr/etc/tls/cert.pem' \
    "$(cat "$SANDBOX/hk.cert" 2>/dev/null)"
}

test_keeps_an_ssl_cert_file_the_caller_set() {
  SSL_CERT_FILE=/custom/cert.pem run_wrapper check
  assertEquals 'SSL_CERT_FILE' '/custom/cert.pem' "$(cat "$SANDBOX/hk.cert" 2>/dev/null)"
}

# shUnit2 takes over here: it discovers the test_* functions above and prints
# the run summary.
# shellcheck source=/dev/null
. ./vendor/shunit2
