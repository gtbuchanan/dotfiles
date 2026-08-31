#!/usr/bin/env bash
#
# Container-side half of the test:termux task: make a fresh termux/termux-docker
# enough like a device to run the checks, then hand off to mise. Runs INSIDE the
# container (or on a real Termux device, where all three steps below are already
# true and each is a no-op).
#
# It runs `mise run test:fast` -- the same aggregate every other leg runs -- so
# a leaf added there is picked up here with no second edit. Anything that named
# the leaves itself, or parsed them out of the task file, would be a second
# copy of the membership free to drift from the first.
#
# Three things differ from a device, and each is restored rather than worked
# around:
#
#   - mise is not installed. It is packaged by Termux, so the container gets the
#     real thing rather than a stand-in.
#   - $LD_PRELOAD is not set. termux-exec ships in the image but its postinst
#     cannot arm it, because that reads an Android build property `getprop`
#     does not answer in a container. Without it, `#!/usr/bin/env bash` finds no
#     interpreter -- Termux has no /usr/bin -- so mise fails to exec its own
#     task files. A device has this shim; setting it here means repo scripts can
#     keep the portable shebang every other platform needs.
#   - mise's config is not trusted. The bind mount is read-only and outside any
#     path mise trusts by default.
#
# --skip-tools because the checks want Termux's own binaries, not mise's: most
# of what mise.toml pins has no Android target at all (which is what
# conf.d/termux.toml documents for a device), and mise's npm backend panics
# outright here -- `Expect rustls-platform-verifier to be initialized`. A device
# never notices, having installed those once long ago; a container is always
# fresh. Nothing under test needs them.
#
# The run is git-free -- the read-only bind mount's .git may be an unmounted
# host path -- so nothing here reaches for it.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)

if ! command -v mise >/dev/null || ! command -v chezmoi >/dev/null; then
  pkg update -y >/dev/null # seed the apt mirror on a fresh image
  pkg install -y chezmoi mise >/dev/null
fi

export LD_PRELOAD="${LD_PRELOAD:-$PREFIX/lib/libtermux-exec.so}"
export MISE_TRUSTED_CONFIG_PATHS=$root

cd "$root"
exec mise run --skip-tools test:fast
