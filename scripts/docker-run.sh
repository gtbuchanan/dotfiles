#!/usr/bin/env bash
#
# Run a Termux-side script inside termux/termux-docker on a non-Termux host —
# the dev-host / CI entrypoint the `test:templates-android` mise task dispatches
# to (on a Termux device that task runs natively). The image arch is matched to
# the host so it runs natively — no QEMU — on both x86_64 CI runners and Apple
# Silicon. chezmoi reports `.chezmoi.os == android` from any Termux arch, so
# unlike claude-code-termux (which forces aarch64 for its .deb) we never need a
# fixed arch or binfmt emulation. Requires Docker (Docker Desktop on
# Windows/macOS, or dockerd).
#
#   scripts/docker-run.sh <script-path-relative-to-repo-root>
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: scripts/docker-run.sh <script>" >&2
  exit 2
fi
script="$1"
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)

case "$(uname -m)" in
aarch64 | arm64) tag=aarch64 ;;
*) tag=x86_64 ;;
esac

echo "==> Running $script in termux-docker:$tag…"
# --privileged: termux-docker's entrypoint does namespace/mount setup and the
# image expects Android-runtime syscalls. MSYS_NO_PATHCONV stops Git Bash on
# Windows mangling the bind-mount path. The source is mounted read-only — the
# render only reads it and writes to the container's own tmp.
MSYS_NO_PATHCONV=1 docker run --rm --privileged \
  -v "$root:/src:ro" \
  "termux/termux-docker:$tag" \
  bash "/src/$script"
