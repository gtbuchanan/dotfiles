#!/usr/bin/env bash
#
# Tests for the Linux mise installer
# (home/.chezmoiscripts/linux/run_onchange_before_install-mise.sh.tmpl), which
# installs the version pinned in home/.chezmoidata/mise.yaml rather than
# whatever mise.run served on the day a host was set up.
#
# Rendered with `chezmoi execute-template`, which consults no .chezmoiignore,
# so the suite runs on any host with chezmoi even though the script deploys
# only on Linux.
#
# Nothing real is reached. HOME points at a sandbox, a `curl` stub serves the
# release from a fixture directory and logs each URL, and a `uname` stub picks
# the architecture -- so what is asserted is which asset the script asks for,
# whether it checks it against the published sum, and what lands in
# ~/.local/bin.
#
#   mise run test:shunit2 [-- shUnit2 args, e.g. a test_* name filter]
#
# Built on the vendored shUnit2 (vendor/shunit2): each behavior is a `test_*`
# function, discovered and summarized by the framework. Deliberately no `set -e`
# -- errexit fights shUnit2.

cd "$(dirname "$0")/.." || exit 1

readonly ROOT="$PWD"
readonly SOURCE="$ROOT/home/.chezmoiscripts/linux/run_onchange_before_install-mise.sh.tmpl"

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
  VERSION=$(chezmoi execute-template --source "$ROOT/home" --no-tty \
    '{{ .mise_version }}')
}

oneTimeTearDown() {
  [ -n "${RENDERED:-}" ] && rm -f "$RENDERED"
}

setUp() {
  SANDBOX=$(mktemp -d)
  BIN="$SANDBOX/bin"
  RELEASE="$SANDBOX/release"
  CURL_LOG="$SANDBOX/curl.log"
  mkdir -p "$BIN" "$RELEASE"

  # Serves the file named by the URL's last segment from the fixture release,
  # writing it wherever -o says, and fails like `curl -f` when it is absent.
  cat >"$BIN/curl" <<'STUB'
#!/usr/bin/env bash
out='' url=''
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out=$2; shift 2 ;;
    -*) shift ;;
    *) url=$1; shift ;;
  esac
done
echo "$url" >>"$CURL_LOG"
src="$RELEASE_DIR/${url##*/}"
[ -f "$src" ] || exit 22
cp "$src" "$out"
STUB

  cat >"$BIN/uname" <<'STUB'
#!/usr/bin/env bash
echo "$STUB_MACHINE"
STUB

  chmod +x "$BIN/curl" "$BIN/uname"
}

tearDown() {
  [ -n "${SANDBOX:-}" ] && rm -rf "$SANDBOX"
}

# A stand-in mise binary that reports version $1 the way the real one does.
fake_mise() {
  printf '#!/usr/bin/env bash\necho "%s linux-x64 (2026-01-01)"\n' "$1"
}

# Publishes a release for the pinned version: the binary for arch $1, and a
# SHASUMS256.txt listing it under the sum given as $2 (default: its real sum).
publish_release() {
  local asset="mise-v$VERSION-linux-$1"
  fake_mise "$VERSION" >"$RELEASE/$asset"
  local sum=${2:-$(sha256sum "$RELEASE/$asset" | cut -d' ' -f1)}
  printf '%s  ./%s\n' "$sum" "$asset" >"$RELEASE/SHASUMS256.txt"
}

# Puts a mise reporting version $1 where the installer looks for one.
preinstall() {
  mkdir -p "$SANDBOX/.local/bin"
  fake_mise "$1" >"$SANDBOX/.local/bin/mise"
  chmod +x "$SANDBOX/.local/bin/mise"
}

run_installer() {
  HOME="$SANDBOX" \
    PATH="$BIN:$PATH" \
    CURL_LOG="$CURL_LOG" \
    RELEASE_DIR="$RELEASE" \
    STUB_MACHINE="${MACHINE:-x86_64}" \
    bash "$RENDERED" >/dev/null 2>&1
}

installed_version() {
  "$SANDBOX/.local/bin/mise" --version 2>/dev/null | cut -d' ' -f1
}

# --- behavior ---------------------------------------------------------------

test_installs_the_pinned_version() {
  publish_release x64

  run_installer
  assertEquals 'exit status' 0 $?
  assertEquals 'installed version' "$VERSION" "$(installed_version)"
}

test_replaces_an_older_install() {
  publish_release x64
  preinstall 2026.8.5

  run_installer
  assertEquals 'installed version' "$VERSION" "$(installed_version)"
}

test_skips_the_download_when_the_pin_is_installed() {
  preinstall "$VERSION"

  run_installer
  assertEquals 'exit status' 0 $?
  assertFalse 'nothing fetched' "[ -s '$CURL_LOG' ]"
}

test_fetches_the_arm64_build_on_aarch64() {
  publish_release arm64

  MACHINE=aarch64 run_installer
  assertEquals 'installed version' "$VERSION" "$(installed_version)"
  assertContains 'asset requested' "$(cat "$CURL_LOG")" "mise-v$VERSION-linux-arm64"
}

test_refuses_a_binary_that_fails_its_checksum() {
  publish_release x64 "$(printf '0%.0s' $(seq 64))"
  preinstall 2026.8.5

  run_installer
  assertNotEquals 'exit status' 0 $?
  assertEquals 'old install left in place' 2026.8.5 "$(installed_version)"
}

test_refuses_an_asset_the_release_publishes_no_sum_for() {
  publish_release x64
  printf '' >"$RELEASE/SHASUMS256.txt"

  run_installer
  assertNotEquals 'exit status' 0 $?
  assertFalse 'nothing installed' "[ -e '$SANDBOX/.local/bin/mise' ]"
}

# shUnit2 takes over here: it discovers the test_* functions above and prints
# the run summary.
# shellcheck source=/dev/null
. ./vendor/shunit2
