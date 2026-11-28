# shellcheck shell=bash
# Bitwarden vault access, sourced by the Termux scripts that read an item out of
# the vault so they reach it the same way: one session source, one way of
# handing it to bw, one sync policy.
#
# A sourced file rather than a chezmoi template partial so each script stays a
# plain file: hk drops .tmpl from shellcheck and shfmt, and these scripts carry
# credentials. The caller defines die() and SCRIPT_DIR before sourcing it, and
# finds this at "$SCRIPT_DIR/../lib", so a test sandbox mirrors that layout.

# Prints the session key from bw-session-termux, or fails. Call it as
# `session=$(vault_session) || exit 1`: die exits only the substitution.
#
# May raise a fingerprint dialog, and a master-password one past the session
# cache's idle window -- native Android dialogs, so they reach the user though
# the caller may have no terminal. Its stderr passes through rather than being
# suppressed: it is all diagnosis, and only the key reaches stdout.
vault_session() {
  local session
  command -v bw >/dev/null || die 'bw not found'
  session=$("$SCRIPT_DIR/bw-session-termux" get) || session=''
  [[ -n "$session" ]] || die 'could not unlock the vault'
  printf '%s' "$session"
}

# Runs bw with the session in its environment alone. Never --session, which
# would put the key in the process command line. --nointeraction so a session
# the vault has since invalidated errors out instead of prompting into the
# stdout the caller parses; --raw keeps bw's chatter out of that stream.
vault_bw() { # $1 = session, $@ = bw args
  local session=$1
  shift
  BW_SESSION="$session" bw "$@" --nointeraction --raw
}

# Prints the items matching $2 as bw's JSON array, or `[]`. bw matches names
# and URIs loosely, so this is a prefilter: the caller narrows the result to the
# items it can use, and refuses rather than guesses when more than one remains.
#
# Syncs first, every time. The CLI serves a local copy of the vault and
# refreshes it only on an explicit sync -- not on unlock, and not on list. A
# sync only on a miss catches an item added elsewhere but never a rotated one:
# the stale value is still found, and the caller fails downstream with nothing
# pointing at the vault. The cost is a network round trip per search. Failure
# is ignored, so an offline search still serves the local copy.
vault_search() { # $1 = session, $2 = query
  vault_bw "$1" sync >/dev/null 2>&1 || true
  vault_bw "$1" list items --search "$2" 2>/dev/null || printf '[]'
}
