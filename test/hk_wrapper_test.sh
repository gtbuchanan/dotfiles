#!/usr/bin/env bash
#
# Tests for the Termux hk wrapper (home/dot_local/bin/executable_hk.tmpl),
# which launches the static musl hk that
# run_onchange_after_install-hk.sh installs out of band, and seeds pklr's
# package cache when hk.pkl imports a package hk can't fetch.
#
# Rendered with `chezmoi execute-template`, which consults no .chezmoiignore,
# so the suite runs on any host with chezmoi. The wrapper finds hk and
# hk-seed-pkl-cache under $HOME, so each test points HOME at a sandbox holding
# stubs of both that record what they were given. The hk stub fails the way
# a cold pklr fetch does while STUB_UNCACHED is set and nothing has seeded.
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
printf '%s\n' "$*" >>"$HOME/hk.args"
printf '%s\n' "$SSL_CERT_FILE" >"$HOME/hk.cert"
if [ -n "${STUB_UNCACHED:-}" ] && [ ! -e "$HOME/seeded" ]; then
  url=https://github.com/example/hk/releases/download/v9.0.0/hk@9.0.0.zip
  echo "Eval error: HTTP fetch failed for $url: error sending request for url ($url)" >&2
  exit 1
fi
exit "${STUB_EXIT:-0}"
STUB
  mkdir -p "$SANDBOX/.local/bin"
  cat >"$SANDBOX/.local/bin/hk-seed-pkl-cache" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$HOME/seeder.args"
[ -z "${STUB_SEED_FAILS:-}" ] || exit 1
touch "$HOME/seeded"
STUB
  chmod +x "$SANDBOX/.local/share/hk/hk-$HK_VERSION" "$SANDBOX/.local/bin/hk-seed-pkl-cache"
}

tearDown() {
  [ -n "${SANDBOX:-}" ] && rm -rf "$SANDBOX"
}

# Runs the wrapper from the sandbox's work directory.
run_wrapper() {
  mkdir -p "$SANDBOX/work"
  (cd "$SANDBOX/work" && HOME="$SANDBOX" bash "$RENDERED" "$@") >"$SANDBOX/wrapper.out" 2>&1
}

# What the wrapper printed, for an assertion message to carry when it fails.
said() {
  printf '; wrapper said:\n%s' "$(cat "$SANDBOX/wrapper.out" 2>/dev/null)"
}

seeder_args() {
  cat "$SANDBOX/seeder.args" 2>/dev/null
}

# --- behavior ---------------------------------------------------------------

test_passes_its_arguments_to_the_pinned_hk() {
  run_wrapper --cd 'some dir' check --all
  assertEquals 'hk arguments' '--cd some dir check --all' "$(head -n 1 "$SANDBOX/hk.args" 2>/dev/null)"
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

test_seeds_the_current_directory_when_a_package_fetch_fails() {
  STUB_UNCACHED=1 run_wrapper check
  assertEquals "seeder arguments$(said)" "$SANDBOX/work" "$(seeder_args)"
}

test_seeds_the_directory_named_by_cd() {
  STUB_UNCACHED=1 run_wrapper --cd /some/repo check
  assertEquals "seeder arguments$(said)" /some/repo "$(seeder_args)"
}

test_seeds_the_directory_named_by_cd_with_an_equals_sign() {
  STUB_UNCACHED=1 run_wrapper --cd=/some/repo check
  assertEquals "seeder arguments$(said)" /some/repo "$(seeder_args)"
}

test_reruns_the_command_once_the_cache_is_seeded() {
  STUB_UNCACHED=1 run_wrapper install --mise
  assertEquals "runs of the command$(said)" 2 "$(grep -cx 'install --mise' "$SANDBOX/hk.args" 2>/dev/null)"
}

test_exits_zero_when_the_rerun_succeeds() {
  STUB_UNCACHED=1 run_wrapper install --mise
  rc=$?
  assertEquals "exit status$(said)" 0 "$rc"
}

test_does_not_rerun_the_command_when_seeding_fails() {
  STUB_UNCACHED=1 STUB_SEED_FAILS=1 run_wrapper install --mise
  assertEquals "runs of the command$(said)" 1 "$(grep -cx 'install --mise' "$SANDBOX/hk.args" 2>/dev/null)"
}

test_does_not_seed_when_hk_fails_for_another_reason() {
  STUB_EXIT=1 run_wrapper check
  assertEquals "seeder arguments$(said)" '' "$(seeder_args)"
}

test_does_not_seed_when_the_caller_rewrites_fetches() {
  HK_PKL_HTTP_REWRITE='https://=http://127.0.0.1:1/' STUB_UNCACHED=1 run_wrapper validate
  assertEquals "seeder arguments$(said)" '' "$(seeder_args)"
}

# shUnit2 takes over here: it discovers the test_* functions above and prints
# the run summary.
# shellcheck source=/dev/null
. ./vendor/shunit2
