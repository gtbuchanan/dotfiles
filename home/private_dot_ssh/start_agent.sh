#!/data/data/com.termux/files/usr/bin/sh
# Overrides start_agent() so ssh-agent is seeded from the Bitwarden vault
# instead of on-disk keys.
#
# Termux's $PREFIX/libexec/source-ssh-agent.sh sources this file, if it exists,
# for exactly this purpose. The `ssha` wrapper -- which dot_gitconfig.tmpl sets
# as core.sshCommand on Android -- runs that script, so Git and manual ssh both
# pick this up with no further wiring.
#
# The key is streamed to `ssh-add -` on stdin and never written to disk; it
# exists only in the agent's memory.
#
# No key lifetime is set, deliberately. source-ssh-agent.sh calls start_agent
# only when no agent is reachable; when the agent is up but holds no
# identities it runs a bare `ssh-add` instead, which this file cannot
# override. Expiring keys would land on that path and look for on-disk keys
# that don't exist. The agent's own lifetime bounds exposure instead. For
# per-use confirmation, add -c to the ssh-add call below -- SSH_ASKPASS
# already points at a Termux popup, so each signature would prompt.
#
# This is sourced by sh, so it must stay POSIX -- no bashisms.

# Loads every vault item holding an SSH private key. Non-zero unless at least
# one key reached the agent.
_bw_ssh_add() {
  command -v bw >/dev/null || return 1
  command -v bw-session-termux >/dev/null || return 1
  command -v jq >/dev/null || return 1

  BW_SESSION=$(bw-session-termux get) || return 1
  export BW_SESSION

  # The CLI serves a local copy of the vault and refreshes it only on an
  # explicit sync -- not on unlock, and not on list. Without this, a key added
  # from another device stays invisible here indefinitely. Best-effort, so an
  # offline cold start still proceeds against the cached copy.
  bw sync >/dev/null 2>&1 || true

  # Ids rather than names: item names are neither unique nor shell-safe.
  _bw_ids=$(bw list items |
    jq -r '.[] | select((.sshKey.privateKey // "") != "") | .id') || return 1

  _bw_added=0
  for _bw_id in $_bw_ids; do
    if bw get item "$_bw_id" | jq -r '.sshKey.privateKey' | ssh-add -; then
      _bw_added=$((_bw_added + 1))
    fi
  done

  _bw_rc=1
  [ "$_bw_added" -gt 0 ] && _bw_rc=0
  unset _bw_ids _bw_id _bw_added
  return "$_bw_rc"
}

start_agent() {
  ssh-agent -a "$1" >/dev/null

  # Falls back to stock behavior so a locked or unreachable vault degrades to
  # on-disk keys rather than breaking ssh outright.
  _bw_ssh_add || ssh-add
}
