#!/usr/bin/env bash
#
# Tests for sops-age-key, the SOPS_AGE_KEY_CMD helper that reads the age
# identity out of the Bitwarden vault on each use so it never lands on disk.
#
# Read straight from home/ rather than rendered through `chezmoi cat`: it is a
# plain file, not a template, so rendering would change nothing but would tie
# the suite to an android personal host. Reading it directly lets every CI leg
# run it, which is affordable because nothing in it is Android-specific once
# its one Android dependency is stubbed.
#
# `bw` and `bw-session-termux` are stubbed, so no vault is contacted and no
# fingerprint is asked for. The stubs sit beside the script under test, since
# it finds the session helper by its own directory rather than by PATH.
#
#   mise run test:shunit2 [-- shUnit2 args, e.g. a test_* name filter]
#
# Built on the vendored shUnit2 (vendor/shunit2): each behavior is a `test_*`
# function, discovered and summarized by the framework. Deliberately no `set -e`
# -- errexit fights shUnit2.

cd "$(dirname "$0")/.." || exit 1

readonly ROOT=$PWD
readonly SOURCE="$ROOT/home/dot_local/bin/executable_sops-age-key"
readonly LIB="$ROOT/home/dot_local/lib/bw-vault-termux.sh"

if ! command -v jq >/dev/null; then
  echo "SKIP: jq not available"
  exit 0
fi

# --- fixtures ---------------------------------------------------------------

# Shaped like what age-keygen writes, which is what a backup of keys.txt holds.
readonly IDENTITY='AGE-SECRET-KEY-1QQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQSTUB1'
readonly OTHER_IDENTITY='AGE-SECRET-KEY-1ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZSTUB2'
readonly SESSION='c3R1Yi1zZXNzaW9uLWtleQ=='

keys_txt() { # $@ = identities
  printf '# created: 2026-01-01T00:00:00Z\n'
  printf '# public key: age1stubpublickey\n'
  printf '%s\n' "$@"
}

# A secure note as `bw list items` returns one. jq builds it so the notes'
# newlines are escaped the way the real CLI escapes them.
note_item() { # $1 = name, $2 = notes
  jq -cn --arg name "$1" --arg notes "$2" '{type: 2, name: $name, notes: $notes}'
}

items() { # $@ = items as JSON objects
  local IFS=,
  printf '[%s]' "$*"
}

items_ok() { items "$(note_item 'SOPS/AGE Key' "$(keys_txt "$IDENTITY")")"; }

# --- harness ----------------------------------------------------------------

# Rewritten before every test, so a stub one test altered cannot change the
# meaning of the next.
install_stubs() {
  cat >"$BIN/bw-session-termux" <<'STUB'
#!/usr/bin/env bash
[ -n "${STUB_VAULT_LOCKED:-}" ] && { echo "stub: vault locked" >&2; exit 1; }
printf '%s' "$STUB_SESSION"
STUB

  # Records each invocation's argv, and what BW_SESSION held, so tests can see
  # how the session travelled and whether a sync happened. A sync swaps in the
  # post-sync item list, which is how a vault that only the server has caught
  # up with is modelled.
  cat >"$BIN/bw" <<'STUB'
#!/usr/bin/env bash
printf 'argv=%s session=%s\n' "$*" "${BW_SESSION:-}" >>"$STUB_BW_LOG"
if [ "$1" = sync ]; then
  [ -n "${STUB_ITEMS_AFTER_SYNC:-}" ] && printf '%s' "$STUB_ITEMS_AFTER_SYNC" >"$STUB_STATE"
  exit 0
fi
[ -z "${BW_SESSION:-}" ] && { echo "stub: no session" >&2; exit 1; }
if [ -s "$STUB_STATE" ]; then cat "$STUB_STATE"; else printf '%s' "${STUB_ITEMS:-[]}"; fi
STUB
  chmod +x "$BIN"/*
}

oneTimeSetUp() {
  # Inherited from the developer's shell, this would point every test at
  # another item.
  unset SOPS_AGE_KEY_ITEM

  SANDBOX=$(mktemp -d)
  BIN="$SANDBOX/bin"
  mkdir -p "$BIN"
  cp "$SOURCE" "$BIN/sops-age-key"
  # Sourced from "$SCRIPT_DIR/../lib", so the sandbox mirrors ~/.local.
  mkdir -p "$SANDBOX/lib"
  cp "$LIB" "$SANDBOX/lib/bw-vault-termux.sh"

  export PATH="$BIN:$PATH"
  export STUB_SESSION=$SESSION
  export STUB_BW_LOG="$SANDBOX/bw.log"
  export STUB_STATE="$SANDBOX/state"
}

setUp() {
  install_stubs
  rm -f "$STUB_STATE"
  : >"$STUB_BW_LOG"
  return 0
}

oneTimeTearDown() {
  [ -n "${SANDBOX:-}" ] && rm -rf "$SANDBOX"
  return 0
}

# bash explicitly, not the Termux shebang, so this runs on every CI leg.
run() { # $@ = env assignments, then args
  local -a envs=()
  while [ $# -gt 0 ] && [[ $1 == *=* ]]; do
    envs+=("$1")
    shift
  done
  env ${envs[@]+"${envs[@]}"} bash "$BIN/sops-age-key" "$@"
}

# --- identity ---------------------------------------------------------------

test_identity_is_the_default_command() {
  # sops runs SOPS_AGE_KEY_CMD with no arguments.
  assertEquals 'prints the identity bare' \
    "$IDENTITY" "$(run STUB_ITEMS="$(items_ok)" 2>/dev/null)"
}

test_identity_prints_only_the_key_lines() {
  local out
  out=$(run STUB_ITEMS="$(items_ok)" identity 2>/dev/null)
  assertNotContains 'the keys.txt comments are dropped' "$out" '#'
}

test_identity_prints_every_key_in_the_note() {
  local out
  out=$(run STUB_ITEMS="$(items "$(note_item 'SOPS/AGE Key' \
    "$(keys_txt "$IDENTITY" "$OTHER_IDENTITY")")")" identity 2>/dev/null)
  assertEquals 'one identity per line' "$IDENTITY"$'\n'"$OTHER_IDENTITY" "$out"
}

test_identity_ignores_matches_without_a_key() {
  # The search is a loose prefilter, so an unrelated note sharing the words is
  # an ordinary hit, not an ambiguity.
  local out
  out=$(run STUB_ITEMS="$(items \
    "$(note_item 'SOPS/AGE Key' "$(keys_txt "$IDENTITY")")" \
    "$(note_item 'SOPS/AGE Key rotation notes' 'rotate yearly')")" \
    identity 2>/dev/null)
  assertEquals 'the item carrying a key wins' "$IDENTITY" "$out"
}

test_identity_refuses_two_items_carrying_keys() {
  local out
  out=$(run STUB_ITEMS="$(items \
    "$(note_item 'SOPS/AGE Key' "$(keys_txt "$IDENTITY")")" \
    "$(note_item 'SOPS/AGE Key (old)' "$(keys_txt "$OTHER_IDENTITY")")")" \
    identity 2>/dev/null)
  assertNotEquals 'exits non-zero' 0 $?
  assertEquals 'prints neither key' '' "$out"
}

test_identity_fails_without_a_matching_item() {
  local out
  out=$(run STUB_ITEMS='[]' identity 2>/dev/null)
  assertNotEquals 'exits non-zero' 0 $?
  assertEquals 'prints nothing' '' "$out"
}

test_identity_sees_a_key_added_since_the_last_sync() {
  # The CLI serves a local copy and refreshes it only on an explicit sync, so a
  # key added from another device is invisible until one happens.
  assertEquals 'found after the sync' "$IDENTITY" \
    "$(run STUB_ITEMS='[]' STUB_ITEMS_AFTER_SYNC="$(items_ok)" identity 2>/dev/null)"
}

test_identity_syncs_before_searching_on_a_hit() {
  # A rotated key is still found in a stale copy, so syncing only on a miss
  # would keep serving the old identity.
  run STUB_ITEMS="$(items_ok)" identity >/dev/null 2>&1
  assertEquals 'sync, then search' 'sync list' \
    "$(sed -E 's/^argv=([a-z]+).*/\1/' "$STUB_BW_LOG" | tr '\n' ' ' | sed 's/ $//')"
}

test_identity_fails_when_the_vault_will_not_unlock() {
  local out
  out=$(run STUB_VAULT_LOCKED=1 STUB_ITEMS="$(items_ok)" identity 2>/dev/null)
  assertNotEquals 'exits non-zero' 0 $?
  assertEquals 'prints nothing' '' "$out"
}

test_session_reaches_bw_through_the_environment() {
  run STUB_ITEMS="$(items_ok)" identity >/dev/null 2>&1
  assertContains 'BW_SESSION carries it' "$(cat "$STUB_BW_LOG")" "session=$SESSION"
}

test_session_stays_out_of_bw_argv() {
  # argv is visible in any process listing.
  run STUB_ITEMS="$(items_ok)" identity >/dev/null 2>&1
  assertNotContains 'never --session' \
    "$(grep -o 'argv=[^ ]*.* session=' "$STUB_BW_LOG")" "$SESSION"
}

test_item_search_defaults_to_the_vault_item_name() {
  run STUB_ITEMS="$(items_ok)" identity >/dev/null 2>&1
  assertContains 'searches the item name' \
    "$(cat "$STUB_BW_LOG")" 'argv=list items --search SOPS/AGE Key'
}

test_item_search_follows_the_override() {
  run SOPS_AGE_KEY_ITEM='Other Key' STUB_ITEMS="$(items_ok)" identity >/dev/null 2>&1
  assertContains 'searches the overridden name' \
    "$(cat "$STUB_BW_LOG")" 'argv=list items --search Other Key'
}

# --- check ------------------------------------------------------------------

test_check_reports_how_many_identities_resolved() {
  assertContains 'reports the shape' \
    "$(run STUB_ITEMS="$(items_ok)" check 2>&1)" '1 age identity resolved'
}

test_check_never_emits_the_identity() {
  # check is the command an agent is pointed at precisely because of this.
  assertNotContains 'no key in the output' \
    "$(run STUB_ITEMS="$(items_ok)" check 2>&1)" 'AGE-SECRET-KEY-1'
}

test_check_fails_when_nothing_resolves() {
  run STUB_ITEMS='[]' check >/dev/null 2>&1
  assertNotEquals 'exits non-zero' 0 $?
}

test_unknown_command_is_rejected() {
  local out
  out=$(run STUB_ITEMS="$(items_ok)" frobnicate 2>/dev/null)
  assertNotEquals 'exits non-zero' 0 $?
  assertEquals 'and prints no key' '' "$out"
}

# shellcheck source=/dev/null
. ./vendor/shunit2
