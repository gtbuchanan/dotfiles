#!/usr/bin/env bash
#
# Tests for hass-vault, the Termux Home Assistant credential resolver. Renders
# the script from the chezmoi source rather than reading the deployed copy, so
# what is under test is this working tree and not whatever was last applied.
#
# `bw` and `bw-session-termux` are stubbed, so no vault is contacted and no
# prompt is raised. Everything else runs for real: the Android hardware
# keystore, node's AES-256-GCM, jq, the sealed cache, and every refusal.
#
# DEVICE-ONLY, and deliberately not wired into hk or CI. The keystore reaches
# Termux:API, which needs the Termux:API app on a real device -- the
# termux-docker userland that `test:templates-android` borrows has no Android
# API service to answer it. So this runs when someone runs it:
#
#   mise run test:hass-vault [-- shUnit2 args, e.g. a test_* name filter]
#
# It skips cleanly, rather than failing, anywhere it cannot apply.
#
# Built on the vendored shUnit2 (vendor/shunit2): each behavior is a `test_*`
# function, discovered and summarized by the framework. Deliberately no `set -e`
# -- errexit fights shUnit2.
#
# HASS_VAULT_KEY_ALIAS is the load-bearing isolation here. Redirecting
# XDG_STATE_HOME is not enough: the keystore is device-wide, so without a test
# alias the `reset` coverage below deletes the real hardware key and orphans the
# real credential cache.

cd "$(dirname "$0")/.." || exit 1

readonly ROOT=$PWD
readonly TARGET="$HOME/.local/bin/hass-vault"
readonly WRAPPER_TARGET="$HOME/.local/bin/wrappers/hass-cli"
readonly TEST_ALIAS=hass-vault-kek-test

# Reasons to skip rather than fail: none of them indicate a defect in the code
# under test, and all of them are the normal state on some host this repo
# supports.
if [ "$(uname -o 2>/dev/null)" != "Android" ]; then
  echo "SKIP: hass-vault is Termux-only (this is not Android)"
  exit 0
fi
for tool in chezmoi termux-keystore jq node; do
  if ! command -v "$tool" >/dev/null; then
    echo "SKIP: $tool not available"
    exit 0
  fi
done
if ! chezmoi cat --source "$ROOT" --no-tty "$TARGET" >/dev/null 2>&1 ||
  ! chezmoi cat --source "$ROOT" --no-tty "$WRAPPER_TARGET" >/dev/null 2>&1; then
  echo "SKIP: hass-vault is not managed for this host (needs a personal android host)"
  exit 0
fi

# --- fixtures ---------------------------------------------------------------

# A vault item as `bw list items` returns it. Callers vary one field at a time,
# so a test names the thing it is actually about.
vault_item() { # $1 = uri, $2 = token field name, $3 = token value, $4 = item name
  cat <<EOF
{"name":"${4:-Home Assistant}",
 "login":{"uris":[$([ -n "$1" ] && printf '{"uri":"%s"}' "$1")]},
 "fields":[{"name":"$2","value":"$3"}]}
EOF
}

ITEM_URI='https://ha.example.test:8123'
ITEM_TOKEN='stub-token-0123456789'

items_ok() { printf '[%s]' "$(vault_item "$ITEM_URI" 'CLI Token' "$ITEM_TOKEN")"; }
items_no_field() { printf '[%s]' "$(vault_item "$ITEM_URI" 'Other' x)"; }
items_no_uri() { printf '[%s]' "$(vault_item '' 'CLI Token' "$ITEM_TOKEN")"; }
items_empty_token() { printf '[%s]' "$(vault_item "$ITEM_URI" 'CLI Token' '')"; }
items_ambiguous() {
  printf '[%s,%s]' \
    "$(vault_item "$ITEM_URI" 'CLI Token' "$ITEM_TOKEN")" \
    "$(vault_item 'https://old.example.test' 'CLI Token' other 'Home Assistant (old)')"
}

# Resolves through the stub vault to populate the cache.
seed_cache() { # $@ = extra env assignments
  env STUB_ITEMS="$(items_ok)" "$@" hass-vault check >/dev/null 2>&1
}

# Rewritten before every test: two of them replace `bw` in place to simulate an
# offline sync and a mid-resolve refresh, and a stub that outlived its test
# would silently change the meaning of the next one.
install_stubs() {
  cat >"$BIN/bw-session-termux" <<'STUB'
#!/usr/bin/env bash
[ -n "${STUB_VAULT_LOCKED:-}" ] && { echo "stub: vault locked" >&2; exit 1; }
printf 'c3R1Yi1zZXNzaW9uLWtleQ=='
STUB

  # Records each subcommand so a test can assert the vault was refreshed before
  # it was searched, which is invisible from the returned credential alone.
  cat >"$BIN/bw" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$1" >>"${STUB_BW_LOG:-/dev/null}"
[ "$1" = sync ] && exit 0
[ -z "${BW_SESSION:-}" ] && { echo "stub: no session" >&2; exit 1; }
printf '%s' "${STUB_ITEMS:-[]}"
STUB
  chmod +x "$BIN"/*
}

oneTimeSetUp() {
  SANDBOX=$(mktemp -d)
  BIN="$SANDBOX/bin"
  mkdir -p "$BIN"

  chezmoi cat --source "$ROOT" --no-tty "$TARGET" >"$BIN/hass-vault"
  install_stubs

  WRAPPER="$SANDBOX/hass-cli"
  chezmoi cat --source "$ROOT" --no-tty "$WRAPPER_TARGET" >"$WRAPPER"
  chmod +x "$WRAPPER"

  export PATH="$BIN:$PATH"
  export XDG_STATE_HOME="$SANDBOX/state"
  export HASS_VAULT_KEY_ALIAS="$TEST_ALIAS"

  CACHE_FILE="$XDG_STATE_HOME/hass-vault/cache.enc"
}

# The cache and the hardware key, so no test inherits another's state. The key
# is dropped too because several tests turn on whether it exists.
setUp() {
  install_stubs
  rm -rf "$XDG_STATE_HOME/hass-vault"
  termux-keystore delete "$TEST_ALIAS" 2>/dev/null
  return 0
}

oneTimeTearDown() {
  termux-keystore delete "$TEST_ALIAS" 2>/dev/null
  [ -n "${SANDBOX:-}" ] && rm -rf "$SANDBOX"
  return 0
}

# --- resolution -------------------------------------------------------------

test_status_reports_an_empty_cache_without_prompting() {
  local out
  out=$(hass-vault status 2>&1)
  assertContains 'names the empty cache' "$out" 'no cached credentials'
  assertContains 'and says what will happen' "$out" 'resolve them on next use'
}

# Unlike the Windows resolver, this one may resolve on a miss: it runs only
# because someone ran hass-cli, so reaching the vault is what they asked for.
test_credential_resolves_on_a_miss() {
  local out
  out=$(env STUB_ITEMS="$(items_ok)" hass-vault credential 2>/dev/null)
  assertContains 'the pair comes back without a warm cache' "$out" "$ITEM_URI"
  assertContains 'including the token' "$out" "$ITEM_TOKEN"
  assertContains 'and it is cached for next time' \
    "$(hass-vault status 2>&1)" 'cached credentials valid for'
}

test_credential_is_the_default_command() {
  seed_cache
  assertContains 'the wrapper invokes it bare' \
    "$(hass-vault 2>/dev/null)" "$ITEM_TOKEN"
}

test_check_resolves_and_caches() {
  local out
  out=$(env STUB_ITEMS="$(items_ok)" hass-vault check 2>&1)
  assertContains 'reports the shape' "$out" 'credentials resolved'
  assertContains 'including the token length' "$out" "token ${#ITEM_TOKEN} chars"
  assertTrue 'and writes the sealed cache' "[ -s '$CACHE_FILE' ]"
}

test_check_never_emits_the_credential() {
  seed_cache
  local out
  out=$(hass-vault check 2>&1)
  assertNotContains 'check is the safe command precisely because of this' \
    "$out" "$ITEM_TOKEN"
}

# One call returns both, so a hass-cli invocation costs one keystore round
# trip rather than two.
test_a_warm_read_serves_the_pair_without_the_vault() {
  seed_cache
  local out server token
  out=$(hass-vault credential 2>&1)
  {
    IFS= read -r server
    IFS= read -r token
  } <<<"$out"
  assertEquals 'server' "$ITEM_URI" "$server"
  assertEquals 'token' "$ITEM_TOKEN" "$token"
}

# --- the binding ------------------------------------------------------------

# The assertions below are the ones behavior cannot stand in for. A resolver
# that signs a missing alias gets 0 bytes and exit 0 from termux-keystore,
# folds that to sha256("") and uses the constant as its KEK -- on both the write
# and the read, so every other test here still passes while the cache is bound
# to nothing and readable by anyone.

test_the_cache_is_wrapped() {
  seed_cache
  assertFalse 'the token must not appear in the cache file' \
    "grep -q '$ITEM_TOKEN' '$CACHE_FILE'"
}

test_resolving_creates_the_hardware_key() {
  seed_cache
  assertTrue 'a cache with no key behind it is bound to nothing' \
    "termux-keystore list 2>/dev/null | jq -e 'map(select(.alias == \"$TEST_ALIAS\")) | length > 0' >/dev/null"
}

test_the_cache_does_not_open_under_the_empty_signature_key() {
  seed_cache
  local empty
  empty=$(printf '' | sha256sum | cut -d' ' -f1)
  assertFalse 'sha256("") must not decrypt the cache' \
    "HASS_KEK='$empty' node -e '
       const c = require(\"crypto\");
       const o = JSON.parse(require(\"fs\").readFileSync(0, \"utf8\"));
       const d = c.createDecipheriv(\"aes-256-gcm\",
         Buffer.from(process.env.HASS_KEK, \"hex\"), Buffer.from(o.iv, \"base64\"));
       d.setAAD(Buffer.from(String(o.exp)));
       d.setAuthTag(Buffer.from(o.tag, \"base64\"));
       d.update(Buffer.from(o.ct, \"base64\")); d.final();
     ' <'$CACHE_FILE' >/dev/null 2>&1"
}

test_an_edited_expiry_is_refused_rather_than_honoured() {
  seed_cache
  jq '.exp = (.exp + 999999)' "$CACHE_FILE" >"$CACHE_FILE.tampered"
  mv "$CACHE_FILE.tampered" "$CACHE_FILE"

  assertContains 'the expiry is bound as AEAD data, so editing it breaks the open' \
    "$(env STUB_VAULT_LOCKED=1 hass-vault check 2>&1)" 'credentials did not resolve'
  assertContains 'and the unusable cache is dropped' \
    "$(hass-vault status 2>&1)" 'no cached credentials'
}

# --- the windows ------------------------------------------------------------

test_a_fresh_window_is_not_rewritten() {
  seed_cache
  local before after
  before=$(jq -r '.exp' "$CACHE_FILE")
  hass-vault credential >/dev/null 2>&1
  after=$(jq -r '.exp' "$CACHE_FILE")
  assertEquals 'rewriting costs a keystore round trip on a path mise runs twice per command' \
    "$before" "$after"
}

test_a_half_spent_window_slides_forward() {
  seed_cache HASS_VAULT_IDLE_TIMEOUT=100
  local before after
  before=$(jq -r '.exp' "$CACHE_FILE")
  HASS_VAULT_IDLE_TIMEOUT=1000 hass-vault credential >/dev/null 2>&1
  after=$(jq -r '.exp' "$CACHE_FILE")
  assertTrue 'past the halfway mark the idle window is pushed out' \
    "[ '$after' -gt '$before' ]"
}

test_a_lapsed_window_is_refused() {
  seed_cache HASS_VAULT_IDLE_TIMEOUT=1
  sleep 2
  assertContains 'past the window the cache is not served' \
    "$(env STUB_VAULT_LOCKED=1 hass-vault check 2>&1)" 'credentials did not resolve'
}

# --- the wrapper ------------------------------------------------------------

# The point of the whole design: credentials reach hass-cli and nothing else.
# A stand-in shim reports what it was handed, so the assertions can be about the
# child's environment without a real hass-cli or a real instance.

wrapper_sandbox() { # echoes a HOME whose shim reports its own environment
  local home="$SANDBOX/wrapper-home"
  mkdir -p "$home/.local/share/mise/shims"
  cat >"$home/.local/share/mise/shims/hass-cli" <<'SHIM'
#!/data/data/com.termux/files/usr/bin/bash
printf 'server=%d token=%d args=%s\n' \
  "${#HASS_SERVER}" "${#HASS_TOKEN}" "$*"
SHIM
  chmod +x "$home/.local/share/mise/shims/hass-cli"
  printf '%s' "$home"
}

test_the_wrapper_hands_the_credentials_to_the_child() {
  seed_cache
  local out
  out=$(HOME="$(wrapper_sandbox)" "$WRAPPER" state get sun.sun 2>&1)
  assertEquals 'both variables reach the child, and the arguments pass through' \
    "server=${#ITEM_URI} token=${#ITEM_TOKEN} args=state get sun.sun" "$out"
}

test_the_wrapper_leaves_the_callers_environment_alone() {
  seed_cache
  HOME="$(wrapper_sandbox)" "$WRAPPER" --version >/dev/null 2>&1
  assertEquals 'nothing is exported to the process that invoked it' \
    0 "$(env | cut -d= -f1 | grep -cE '^HASS_(SERVER|TOKEN)$')"
}

test_the_wrapper_reports_a_missing_shim_rather_than_running_bare() {
  seed_cache
  local empty out
  empty="$SANDBOX/no-shim"
  mkdir -p "$empty"
  out=$(HOME="$empty" "$WRAPPER" --version 2>&1)
  assertContains 'names what is missing' "$out" 'mise shim not found'
  assertContains 'and how to fix it' "$out" 'mise install'
}

test_the_wrapper_fails_when_credentials_cannot_resolve() {
  local out
  out=$(HOME="$(wrapper_sandbox)" STUB_VAULT_LOCKED=1 "$WRAPPER" --version 2>&1)
  assertContains 'points at the diagnostic command' "$out" 'hass-vault check'
}

# --- refusals ---------------------------------------------------------------

test_a_different_item_query_does_not_serve_the_cached_one() {
  seed_cache
  # The read consults the cache before it reaches the vault, so without the
  # query bound into the AAD this returns the previously cached item.
  local out
  out=$(env HASS_VAULT_ITEM=Other STUB_ITEMS='[]' hass-vault credential 2>&1)
  assertNotContains 'a cache filled for one item must not answer for another' \
    "$out" "$ITEM_URI"
  assertContains 'it looks the new item up and reports the miss' \
    "$out" "matching 'Other'"
}

test_a_non_https_server_uri_is_refused() {
  local items out
  items=$(printf '[%s]' "$(vault_item 'http://plain.test:8123' 'CLI Token' "$ITEM_TOKEN")")
  out=$(env STUB_ITEMS="$items" hass-vault credential 2>&1)
  assertContains 'a long-lived token is not sent in the clear' "$out" 'non-https URI'
  assertNotContains 'and the token never reaches stdout' "$out" "$ITEM_TOKEN"
}

# A rotated token is the case this protects. bw serves a local copy of the vault
# and refreshes it only on an explicit sync, so without one the resolver returns
# the previous token -- still a valid, unexpired JWT, so `check` reports success
# while hass-cli gets 401. Nothing about the returned credential reveals that,
# which is why this asserts on the calls rather than the result.

test_resolving_syncs_the_vault_before_searching() {
  local log
  log="$SANDBOX/bw-calls"
  : >"$log"
  env STUB_BW_LOG="$log" STUB_ITEMS="$(items_ok)" hass-vault check >/dev/null 2>&1
  assertEquals 'the local copy is refreshed before it is read' \
    'sync' "$(head -1 "$log")"
  assertContains 'and then searched' "$(cat "$log")" 'list'
}

test_a_warm_cache_does_not_sync() {
  local log
  seed_cache
  log="$SANDBOX/bw-calls-warm"
  : >"$log"
  env STUB_BW_LOG="$log" hass-vault credential >/dev/null 2>&1
  assertEquals 'the cold path cost stays off cached reads' '' "$(cat "$log")"
}

test_an_offline_sync_does_not_block_resolution() {
  # `bw sync` failing must not stop a resolve that the local copy can satisfy.
  cat >"$BIN/bw" <<'STUB'
#!/usr/bin/env bash
[ "$1" = sync ] && { echo "stub: offline" >&2; exit 1; }
printf '%s' "${STUB_ITEMS:-[]}"
STUB
  chmod +x "$BIN/bw"
  local out
  out=$(env STUB_ITEMS="$(items_ok)" hass-vault check 2>&1)
  assertContains 'the local copy still resolves' "$out" 'credentials resolved'
}

test_an_ambiguous_vault_match_is_refused_not_guessed() {
  assertContains 'picking one would hand over a credential nobody chose' \
    "$(env STUB_ITEMS="$(items_ambiguous)" hass-vault check 2>&1)" 'refusing to guess'
}

test_an_item_without_the_token_field_is_reported() {
  assertContains 'names the field it looked for' \
    "$(env STUB_ITEMS="$(items_no_field)" hass-vault check 2>&1)" "'CLI Token' field"
}

test_an_item_without_a_uri_is_reported() {
  assertContains 'the first login URI becomes HASS_SERVER' \
    "$(env STUB_ITEMS="$(items_no_uri)" hass-vault check 2>&1)" 'no URI to use as the server'
}

test_an_item_with_an_empty_token_is_reported() {
  assertContains 'an empty field would export an empty credential' \
    "$(env STUB_ITEMS="$(items_empty_token)" hass-vault check 2>&1)" "empty 'CLI Token' field"
}

test_the_search_term_is_overridable() {
  assertContains 'HASS_VAULT_ITEM keeps the vault item renameable' \
    "$(env HASS_VAULT_ITEM=Nope STUB_ITEMS='[]' hass-vault check 2>&1)" "matching 'Nope'"
}

test_an_unknown_command_is_rejected() {
  assertContains 'lists what it accepts' \
    "$(hass-vault bogus 2>&1)" 'unknown command'
}

# --- failing soft -----------------------------------------------------------

test_a_locked_vault_reports_the_reason_through_check() {
  local out
  out=$(env STUB_VAULT_LOCKED=1 hass-vault check 2>&1)
  assertContains 'check exists to surface this' "$out" 'credentials did not resolve'
  assertContains 'with the underlying cause' "$out" 'could not unlock the vault'
}

# Loud, unlike the Windows resolver: this failure is hass-cli's alone, so it
# does not have to stay quiet to avoid breaking unrelated mise commands.
test_a_locked_vault_fails_loudly_rather_than_silently() {
  local out
  out=$(env STUB_VAULT_LOCKED=1 hass-vault credential 2>&1)
  assertContains 'says why' "$out" 'could not unlock the vault'
  env STUB_VAULT_LOCKED=1 hass-vault credential >/dev/null 2>&1
  assertNotEquals 'and exits non-zero' 0 $?
}

# --- reset ------------------------------------------------------------------

# A rotation changes the vault under a cache that is still valid. The cold-path
# sync cannot help, because the read never reaches bw while the cache holds --
# so there has to be a way to say "this one is stale" that does not involve
# destroying the hardware key.

test_refresh_picks_up_a_rotated_token() {
  seed_cache
  local rotated out
  rotated=$(printf '[%s]' "$(vault_item "$ITEM_URI" 'CLI Token' 'token-ROTATED')")

  assertContains 'a warm cache still serves the old one' \
    "$(env STUB_ITEMS="$rotated" hass-vault credential 2>/dev/null)" "$ITEM_TOKEN"

  out=$(env STUB_ITEMS="$rotated" hass-vault refresh 2>&1)
  assertContains 'refresh reports the new shape' "$out" 'credentials resolved'
  assertContains 'and the rotated token is now served' \
    "$(hass-vault credential 2>/dev/null)" 'token-ROTATED'
}

test_refresh_keeps_the_hardware_key() {
  seed_cache
  env STUB_ITEMS="$(items_ok)" hass-vault refresh >/dev/null 2>&1
  assertTrue 'refresh is not reset -- the key survives' \
    "termux-keystore list 2>/dev/null | jq -e 'map(select(.alias == \"$TEST_ALIAS\")) | length > 0' >/dev/null"
}

# A refresh that lands while a resolve is in flight must not be undone by it.
# The resolve read the vault before the rotation was published, so sealing its
# result would restore the stale pair -- with a fresh window, after refresh
# reported success. Driven deterministically rather than by timing: the stub
# bumps the epoch while serving the search, which is exactly the interleaving
# that matters.

test_a_refresh_landing_mid_resolve_is_not_undone() {
  cat >"$BIN/bw" <<STUB
#!/usr/bin/env bash
[ "\$1" = sync ] && exit 0
printf '%s' "\${STUB_BUMP_EPOCH:-}" >"$XDG_STATE_HOME/hass-vault/epoch"
printf '%s' "\${STUB_ITEMS:-[]}"
STUB
  chmod +x "$BIN/bw"
  mkdir -p "$XDG_STATE_HOME/hass-vault"

  env STUB_BUMP_EPOCH=a-refresh-landed STUB_ITEMS="$(items_ok)" \
    hass-vault credential >/dev/null 2>&1

  assertFalse 'the in-flight resolve must not seal what refresh just cleared' \
    "[ -s '$CACHE_FILE' ]"
}

test_refresh_advances_the_epoch_before_clearing() {
  seed_cache
  local before after
  before=$(cat "$XDG_STATE_HOME/hass-vault/epoch" 2>/dev/null)
  env STUB_ITEMS="$(items_ok)" hass-vault refresh >/dev/null 2>&1
  after=$(cat "$XDG_STATE_HOME/hass-vault/epoch" 2>/dev/null)
  assertNotEquals 'a resolve started before this must be able to notice' \
    "$before" "$after"
}

test_reset_drops_the_cache_and_the_hardware_key() {
  seed_cache
  assertContains 'reports what it removed' \
    "$(hass-vault reset 2>&1)" 'cache and hardware key removed'
  assertContains 'the cache is gone' \
    "$(hass-vault status 2>&1)" 'no cached credentials'
  assertFalse 'and the key, so any surviving cache is permanently unreadable' \
    "termux-keystore list 2>/dev/null | jq -e 'map(select(.alias == \"$TEST_ALIAS\")) | length > 0' >/dev/null"
}

# shUnit2 takes over here: it discovers the test_* functions above and prints
# the run summary.
# shellcheck source=/dev/null
. ./vendor/shunit2
