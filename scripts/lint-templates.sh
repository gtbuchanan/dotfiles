#!/bin/sh
# Prove every source template renders. chezmoi's funcMap (include, sprig,
# .chezmoi.*, .chezmoidata) means a bare text/template parse is insufficient, so
# each template is rendered through `chezmoi execute-template`, which fails on
# syntax errors and undefined refs. This validates that templates render; it is
# not a lint of the rendered output.
#
# `chezmoi init` normally writes a config whose data section (hosttype and the
# values derived from it) most templates read; that config doesn't exist in CI.
# Regenerate it from the config template into a throwaway file and render every
# content template against it, so the check behaves the same locally and in CI.
#
# The config template answers a hosttype prompt via promptChoiceOnce, whose
# --promptChoice simulation is keyed by the prompt text (not the data key), so
# the text is derived from the template below rather than hardcoded, to avoid
# drift. On a machine that already ran `chezmoi init`, the cached answer wins
# and this is ignored; CI has no cache, so this default applies. Only one
# representative hosttype/OS variation is exercised — conditional branches for
# other hosttypes/OSes are not covered.
set -u

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# chezmoi source root. hk runs from the repo root, but a CI checkout isn't at
# chezmoi's default source dir, so pass --source explicitly.
src_root=$PWD

config_tmpl=home/.chezmoi.yaml.tmpl
hosttype=${LINT_HOSTTYPE:-personal}
hosttype_prompt=$(sed -n 's/.*promptChoiceOnce \. "hosttype" "\([^"]*\)".*/\1/p' "$config_tmpl")
if [ -z "$hosttype_prompt" ]; then
  printf 'could not find the hosttype prompt in %s\n' "$config_tmpl" >&2
  exit 1
fi

chezmoi_config=$work/chezmoi-config.yaml
if ! err=$(chezmoi execute-template --init --no-tty --promptChoice "$hosttype_prompt=$hosttype" \
  --source "$src_root" <"$config_tmpl" 2>&1 >"$chezmoi_config"); then
  printf 'config generation failed (%s):\n%s\n' "$config_tmpl" "$err" >&2
  exit 1
fi

rc=0

# Render one template, reporting a chezmoi failure. Args after the source path
# are passed to chezmoi execute-template.
render() {
  src=$1
  shift
  if ! err=$(chezmoi execute-template "$@" --source "$src_root" <"$src" 2>&1 >/dev/null); then
    printf 'render failed: %s\n%s\n' "$src" "$err" >&2
    rc=1
  fi
}

# Skip templates chezmoi ignores for the lint hosttype/OS: they aren't deployed
# here and may call host-specific tools (e.g. the ewn profile part shells out to
# dcli). `chezmoi ignored` prints home-relative targets; prefix the home dir to
# match `chezmoi target-path` below.
home_dir=$(chezmoi execute-template --config "$chezmoi_config" '{{ .chezmoi.homeDir }}')
ignored=$(chezmoi ignored --config "$chezmoi_config" --source "$src_root" |
  sed "s|^|$home_dir/|")

# Resolve each source to its target in one call; output order matches the args,
# so pair them line by line via paste.
printf '%s\n' "$@" >"$work/sources"
chezmoi target-path --source "$src_root" "$@" >"$work/targets"
paste "$work/sources" "$work/targets" >"$work/map"

while IFS="$(printf '\t')" read -r src target; do
  if printf '%s\n' "$ignored" | grep -Fxq "$target"; then
    printf 'skip (ignored for this hosttype/OS): %s\n' "$src" >&2
    continue
  fi

  # The config template (.chezmoi.<format>.tmpl) uses init-only prompt functions
  # and renders without .chezmoidata/.chezmoitemplates, so it renders in --init
  # mode with the hosttype above. Every other template renders against the
  # generated config.
  case "$src" in
  */.chezmoi.*.tmpl | .chezmoi.*.tmpl)
    render "$src" --init --no-tty --promptChoice "$hosttype_prompt=$hosttype"
    ;;
  *)
    render "$src" --config "$chezmoi_config"
    ;;
  esac
done <"$work/map"

exit "$rc"
