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

# chezmoi renders the sources under test; jq and node back the shell suites'
# resolver. All are disable_tools entries on a device, resolved from PATH.
missing=
for tool in chezmoi jq mise node; do
  command -v "$tool" >/dev/null || missing="$missing $tool"
done
if [ -n "$missing" ]; then
  pkg update -y >/dev/null # seed the apt mirror on a fresh image
  # `node` is the binary; `nodejs` is the package that provides it.
  pkg install -y chezmoi jq mise nodejs >/dev/null
fi

export LD_PRELOAD="${LD_PRELOAD:-$PREFIX/lib/libtermux-exec.so}"
export MISE_TRUSTED_CONFIG_PATHS=$root

# A device has the real termux-keystore and it must win: the stub is a model
# (see test/stubs/termux-keystore), and a device run is what re-checks the
# claims it makes. Only prepended where there is nothing to shadow.
if ! command -v termux-keystore >/dev/null; then
  echo '==> no termux-keystore; using the stub (see test/stubs/termux-keystore)'
  stub_bin=$(mktemp -d)
  install -m 755 "$root/test/stubs/termux-keystore" "$stub_bin/termux-keystore"
  PATH="$stub_bin:$PATH"
  export PATH
fi

# hass_vault_test.sh resolves its subjects with a bare `chezmoi cat`, which needs
# a config to answer the hosttype prompt -- without one it fails under --no-tty
# and the suite skips as "not managed for this host". Written to the default path
# rather than passed with --config, so the suite needs no flag of its own.
#
# The prompt string is read out of the template, matching scripts/lint-templates.sh:
# hardcoding it here would drift silently the day it is reworded.
#
# lintSkipExternals is spliced into the data map because `chezmoi cat` realizes
# every .chezmoiexternal entry just to enumerate targets -- it downloads archives
# and SSH-clones repos, which offline fails on certificate verification long
# before it reaches the file being asked for. The guard already exists in
# .chezmoiexternal.yaml.tmpl for the template lint, which trips it with
# --override-data on its one call; setting it in the config covers every chezmoi
# invocation here instead.
config_tmpl=$root/home/.chezmoi.yaml.tmpl
if [ ! -s "$HOME/.config/chezmoi/chezmoi.yaml" ]; then
  hosttype_prompt=$(sed -n 's/.*promptChoiceOnce \. "hosttype" "\([^"]*\)".*/\1/p' "$config_tmpl")
  if [ -z "$hosttype_prompt" ]; then
    printf 'could not find the hosttype prompt in %s\n' "$config_tmpl" >&2
    exit 1
  fi
  mkdir -p "$HOME/.config/chezmoi"
  # personal, because hass-cli and its resolver are deployed on personal hosts
  # only -- an ewn config would make the suite skip as unmanaged.
  chezmoi execute-template --init --no-tty \
    --promptChoice "$hosttype_prompt=personal" --source "$root" \
    <"$config_tmpl" |
    sed '0,/^data:/s//data:\n  lintSkipExternals: true/' \
      >"$HOME/.config/chezmoi/chezmoi.yaml"
fi

cd "$root"
exec mise run --skip-tools test:fast
