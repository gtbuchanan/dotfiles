#!/usr/bin/env bash
#
# Container-side half of the test:termux task: provision what the checks need on
# a fresh termux/termux-docker, then run them. Runs INSIDE the container (or on
# a real Termux device, where the packages already exist and the install is a
# no-op).
#
# The leaves are invoked directly rather than through `mise run test:fast`,
# because mise is not installed in the container and installing it to resolve a
# dependency list would cost more than naming them. The membership is duplicated
# from mise-tasks/test/fast; keep them in step.
#
# The run is git-free -- the read-only bind mount's .git may be an unmounted
# host path -- so only what the checks use is installed.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)

if ! command -v chezmoi >/dev/null; then
  pkg update -y >/dev/null # seed the apt mirror on a fresh image
  pkg install -y chezmoi >/dev/null
fi

exec bash "$root/mise-tasks/test/templates"
