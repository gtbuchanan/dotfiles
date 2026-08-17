#!/data/data/com.termux/files/usr/bin/bash
# Links the ssh-agent start hook into Termux's prefix.
#
# Termux's $PREFIX/libexec/source-ssh-agent.sh sources
# $PREFIX/etc/ssh/start_agent.sh when present, to let the agent's key-loading
# step be overridden. That path is outside $HOME, which is all chezmoi manages,
# so the hook is deployed to ~/.ssh/start_agent.sh and symlinked here. The
# symlink also keeps this repo authoritative across `pkg upgrade openssh` --
# that directory is dpkg-owned, since it ships sshd_config.
#
# This runs on every apply rather than on change: the link carries none of the
# hook's content, so a content change needs no re-link, while $PREFIX can be
# wiped by a Termux reinstall independently of $HOME. An idempotent `ln -sfn`
# restores the link in that case, where a run_onchange_ script would not.

set -euo pipefail

HOOK="$HOME/.ssh/start_agent.sh"
TARGET="${TERMUX__PREFIX:-${PREFIX:-/data/data/com.termux/files/usr}}/etc/ssh/start_agent.sh"

if [ ! -r "$HOOK" ]; then
  echo "ssh-agent hook missing at $HOOK" >&2
  exit 1
fi

mkdir -p "$(dirname "$TARGET")"
ln -sfn "$HOOK" "$TARGET"
