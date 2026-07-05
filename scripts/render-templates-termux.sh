#!/usr/bin/env bash
#
# Container-side half of the test:templates-android task: provision chezmoi on a
# fresh termux/termux-docker, then hand off to the shared render engine
# (mise-tasks/test/templates), so the android leg renders through exactly the
# same path as every other platform. Runs INSIDE the container (or on a real
# Termux device, where chezmoi already exists and the install is a no-op). The
# render is git-free — the read-only bind mount's .git may be an unmounted host
# path — so only chezmoi is installed.
set -euo pipefail

if ! command -v chezmoi >/dev/null; then
  pkg update -y >/dev/null # seed the apt mirror on a fresh image
  pkg install -y chezmoi >/dev/null
fi

exec bash "$(cd "$(dirname "$0")/.." && pwd)/mise-tasks/test/templates"
