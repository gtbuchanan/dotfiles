#!/usr/bin/env bash
#
# Tests for the Termux pklr cache seeder (home/dot_local/bin/
# executable_hk-seed-pkl-cache), which downloads the Pkl packages hk.pkl
# imports and feeds them to hk over a loopback server, because hk's static
# musl build can't resolve hostnames on Android, and for the run_onchange
# script that calls it on the chezmoi working tree
# (home/.chezmoiscripts/android/run_onchange_after_seed-hk-pkl-cache.sh.tmpl).
#
# The run_onchange script is rendered with `chezmoi execute-template`, which
# consults no .chezmoiignore, so the suite runs on any host with chezmoi and
# python3.
#
# Nothing real is reached. A `curl` stub serves upstream packages from a
# fixture directory and logs each URL. An `hk` stub plays pklr: it needs the
# packages named in STUB_REQUIRES, takes each from its cache when present, and
# otherwise fetches it through HK_PKL_HTTP_REWRITE -- failing the way pklr
# does when the rewritten URL is still https (no DNS) or the server has no
# such file. So what is asserted is that packages reach hk's cache through the
# script's own loopback server.
#
#   mise run test:shunit2 [-- shUnit2 args, e.g. a test_* name filter]
#
# Built on the vendored shUnit2 (vendor/shunit2): each behavior is a `test_*`
# function, discovered and summarized by the framework. Deliberately no `set -e`
# -- errexit fights shUnit2.

cd "$(dirname "$0")/.." || exit 1

readonly ROOT="$PWD"
readonly SEEDER="$ROOT/home/dot_local/bin/executable_hk-seed-pkl-cache"
readonly SOURCE="$ROOT/home/.chezmoiscripts/android/run_onchange_after_seed-hk-pkl-cache.sh.tmpl"

for tool in chezmoi python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "SKIP: $tool not available"
    exit 0
  fi
done

readonly CONFIG_URL='https://github.com/example/tooling/releases/download/cfg@1.0.0/cfg@1.0.0.zip'
readonly DEP_URL='https://github.com/example/hk/releases/download/v9.0.0/hk@9.0.0.zip'

# --- harness ----------------------------------------------------------------

oneTimeSetUp() {
  RENDERED=$(mktemp)
  if ! chezmoi execute-template --source "$ROOT/home" --no-tty \
    <"$SOURCE" >"$RENDERED" 2>/dev/null; then
    fail "could not render $SOURCE"
  fi
}

oneTimeTearDown() {
  [ -n "${RENDERED:-}" ] && rm -f "$RENDERED"
}

setUp() {
  SANDBOX=$(mktemp -d)
  BIN="$SANDBOX/bin"
  UPSTREAM="$SANDBOX/upstream"
  CACHE="$SANDBOX/cache"
  TREE="$SANDBOX/tree"
  CURL_LOG="$SANDBOX/curl.log"
  mkdir -p "$BIN" "$UPSTREAM" "$CACHE" "$TREE" "$SANDBOX/.local/bin"
  : >"$CURL_LOG"

  # Serves https://<path> from $UPSTREAM_DIR/<path>, writing it wherever -o
  # says, and fails like `curl -f` when it is absent.
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
src="$UPSTREAM_DIR/${url#https://}"
[ -f "$src" ] || exit 22
cp "$src" "$out"
STUB

  cat >"$SANDBOX/.local/bin/hk" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$HOME/hk.args"
for url in $STUB_REQUIRES; do
  key=${url//[^A-Za-z0-9]/_}
  [ -f "$STUB_CACHE/$key" ] && continue
  fetch=$url
  if [ -n "${HK_PKL_HTTP_REWRITE:-}" ]; then
    from=${HK_PKL_HTTP_REWRITE%%=*} to=${HK_PKL_HTTP_REWRITE#*=}
    case $fetch in "$from"*) fetch=$to${fetch#"$from"} ;; esac
  fi
  case $fetch in
    https://*)
      echo "Eval error: HTTP fetch failed for $fetch: error sending request for url ($fetch)"
      exit 1
      ;;
  esac
  if ! python3 -c 'import sys, urllib.request
open(sys.argv[2], "wb").write(urllib.request.urlopen(sys.argv[1]).read())' \
    "$fetch" "$STUB_CACHE/$key" 2>/dev/null; then
    rm -f "$STUB_CACHE/$key"
    echo "Import not found: $fetch"
    exit 1
  fi
done
if [ -n "${STUB_BROKEN:-}" ]; then
  echo 'Type mismatch: expected Listing, got String'
  exit 1
fi
echo 'hk.pkl is valid'
STUB

  chmod +x "$BIN/curl" "$SANDBOX/.local/bin/hk"
}

tearDown() {
  [ -n "${SANDBOX:-}" ] && rm -rf "$SANDBOX"
}

# Publishes package URL $1 upstream with content $2.
publish() {
  local path="$UPSTREAM/${1#https://}"
  mkdir -p "$(dirname "$path")"
  printf '%s' "$2" >"$path"
}

# Where the hk stub caches package URL $1: the URL flattened to one filename.
cache_file() {
  echo "$CACHE/${1//[^A-Za-z0-9]/_}"
}

# Puts package URL $1 in hk's cache, as an earlier evaluation would have.
precache() {
  printf 'cached' >"$(cache_file "$1")"
}

# Runs the seeder from directory $1 with the remaining arguments.
run_seeder_in() {
  local dir=$1
  shift
  (
    cd "$dir" || exit 1
    HOME="$SANDBOX" \
      PATH="$BIN:$PATH" \
      CURL_LOG="$CURL_LOG" \
      UPSTREAM_DIR="$UPSTREAM" \
      STUB_CACHE="$CACHE" \
      STUB_REQUIRES="${REQUIRES:-}" \
      STUB_BROKEN="${BROKEN:-}" \
      bash "$SEEDER" "$@" >"$SANDBOX/seeder.out" 2>&1
  )
}

# Runs the seeder on the working tree, as the run_onchange script does.
run_seeder() {
  run_seeder_in "$SANDBOX" "$TREE"
}

# What the seeder printed, for an assertion message to carry when it fails.
said() {
  printf '; seeder said:\n%s' "$(cat "$SANDBOX/seeder.out" 2>/dev/null)"
}

# --- behavior ---------------------------------------------------------------

test_rendered_script_lists_the_hk_config_import() {
  assertContains 'rendered imports' "$(cat "$RENDERED")" \
    'package://github.com/gtbuchanan/tooling/releases/download/hk-config@'
}

test_rendered_script_lists_the_hk_import() {
  assertContains 'rendered imports' "$(cat "$RENDERED")" \
    'package://github.com/jdx/hk/releases/download/v'
}

test_caches_an_uncached_package_as_published_upstream() {
  publish "$CONFIG_URL" 'config-package'

  REQUIRES="$CONFIG_URL" run_seeder
  assertEquals "cached content$(said)" 'config-package' "$(cat "$(cache_file "$CONFIG_URL")" 2>/dev/null)"
}

test_caches_a_package_only_reported_after_another_is_seeded() {
  publish "$CONFIG_URL" 'config-package'
  publish "$DEP_URL" 'dep-package'

  REQUIRES="$CONFIG_URL $DEP_URL" run_seeder
  assertEquals "cached content$(said)" 'dep-package' "$(cat "$(cache_file "$DEP_URL")" 2>/dev/null)"
}

test_exits_zero_once_every_package_is_cached() {
  publish "$CONFIG_URL" 'config-package'

  REQUIRES="$CONFIG_URL" run_seeder
  rc=$?
  assertEquals "exit status$(said)" 0 "$rc"
}

test_downloads_nothing_when_the_cache_is_warm() {
  precache "$CONFIG_URL"

  REQUIRES="$CONFIG_URL" run_seeder
  rc=$?
  assertEquals "exit status$(said)" 0 "$rc"
  assertFalse 'nothing fetched' "[ -s '$CURL_LOG' ]"
}

test_validates_the_working_tree_hk_pkl() {
  precache "$CONFIG_URL"

  REQUIRES="$CONFIG_URL" run_seeder
  assertEquals "hk arguments$(said)" "--cd $TREE validate" "$(cat "$SANDBOX/hk.args" 2>/dev/null)"
}

test_validates_the_current_directory_without_an_argument() {
  precache "$CONFIG_URL"

  REQUIRES="$CONFIG_URL" run_seeder_in "$TREE"
  assertEquals "hk arguments$(said)" "--cd $TREE validate" "$(cat "$SANDBOX/hk.args" 2>/dev/null)"
}

test_run_onchange_script_seeds_the_chezmoi_working_tree() {
  cat >"$SANDBOX/.local/bin/hk-seed-pkl-cache" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$HOME/seeder.args"
STUB
  chmod +x "$SANDBOX/.local/bin/hk-seed-pkl-cache"

  HOME="$SANDBOX" CHEZMOI_WORKING_TREE="$TREE" bash "$RENDERED" >"$SANDBOX/seeder.out" 2>&1
  assertEquals "seeder arguments$(said)" "$TREE" "$(cat "$SANDBOX/seeder.args" 2>/dev/null)"
}

test_fails_when_a_package_cannot_be_downloaded() {
  REQUIRES="$CONFIG_URL" run_seeder
  rc=$?
  assertNotEquals "exit status$(said)" 0 "$rc"
}

test_fails_when_hk_pkl_fails_for_another_reason() {
  precache "$CONFIG_URL"

  REQUIRES="$CONFIG_URL" BROKEN=1 run_seeder
  rc=$?
  assertNotEquals "exit status$(said)" 0 "$rc"
}

# shUnit2 takes over here: it discovers the test_* functions above and prints
# the run summary.
# shellcheck source=/dev/null
. ./vendor/shunit2
