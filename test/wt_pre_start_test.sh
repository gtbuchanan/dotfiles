#!/usr/bin/env bash
#
# Tests for wt-pre-start, the worktrunk hook that prepares a freshly created
# worktree. These cover one of its three jobs: deciding whether the worktree
# carries a mise config at all, which gates both the `gh` fork lookup and the
# `mise trust` that keeps the post-start bootstrap off an interactive prompt.
#
# The hook is read straight from home/, not rendered through `chezmoi cat` as
# the hass-vault suite does: it is a plain file rather than a template, so the
# rendered output would be byte-identical, and reading it directly keeps this
# suite free of the config-and-hosttype dance CI would otherwise need.
#
#   mise run test:shunit2 [-- shUnit2 args, e.g. a test_* name filter]
#
# Built on the vendored shUnit2 (vendor/shunit2): each behavior is a `test_*`
# function, discovered and summarized by the framework. Deliberately no `set -e`
# -- errexit fights shUnit2.
#
# What makes this worth a suite: the gate is a list of filenames that has to
# track mise's config discovery, and mise has grown that list over time. A path
# missing from it fails silently and asymmetrically -- the worktree is created,
# the hook exits 0, and the omission only surfaces later as a bootstrap sitting
# on a trust prompt nobody is watching. So each supported path is asserted
# individually rather than through one representative.

cd "$(dirname "$0")/.." || exit 1

readonly HOOK="$PWD/home/dot_local/bin/executable_wt-pre-start"

if [ ! -f "$HOOK" ]; then
  echo "SKIP: $HOOK not found"
  exit 0
fi

# --- harness ----------------------------------------------------------------

# `mise`, `git` and `gh` are all stubbed: the hook's decision is a function of
# the files on disk plus the origin URL, and reaching the real tools would mean
# building a git repo with a remote per case and mutating the developer's own
# mise trust store. The stubs shadow whatever is installed via PATH.
setUp() {
  STUB_DIR=$(mktemp -d) || fail 'could not create stub dir'
  WT_PATH=$(mktemp -d) || fail 'could not create worktree dir'
  WT_MAIN=$(mktemp -d) || fail 'could not create primary worktree dir'
  MISE_LOG="$STUB_DIR/mise.log"
  : >"$MISE_LOG"

  cat >"$STUB_DIR/mise" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>'$MISE_LOG'
EOF

  # Only the two subcommands the hook runs. Everything else is a no-op so a
  # future call cannot fail the suite for the wrong reason.
  cat >"$STUB_DIR/git" <<'EOF'
#!/bin/sh
case "$*" in
*"remote get-url origin"*) printf '%s\n' "${STUB_ORIGIN-}" ;;
esac
EOF

  # `false` is "not a fork"; the fork path is exercised by overriding
  # STUB_IS_FORK. Only reached when the hook was given a PR number.
  cat >"$STUB_DIR/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "${STUB_IS_FORK:-false}"
EOF

  chmod +x "$STUB_DIR/mise" "$STUB_DIR/git" "$STUB_DIR/gh"

  STUB_ORIGIN='https://github.com/gtbuchanan/example.git'
  export STUB_ORIGIN
}

tearDown() {
  rm -rf "$STUB_DIR" "$WT_PATH" "$WT_MAIN"
  unset STUB_ORIGIN STUB_IS_FORK
}

# Runs the hook against the temp worktree. $1 is the PR number, empty for a
# plain `wt switch`.
run_hook() { # $1 = pr_number
  PATH="$STUB_DIR:$PATH" sh "$HOOK" "$WT_PATH" "$WT_MAIN" "${1-}" >/dev/null 2>&1
}

# Creates an empty config file at $1, relative to the worktree root.
seed_config() { # $1 = relative path
  mkdir -p "$WT_PATH/$(dirname "$1")"
  : >"$WT_PATH/$1"
}

# Trust is identified by the subcommand reaching the mise stub, not by any
# message the hook prints -- it silences mise entirely, so its output says
# nothing about whether the call happened.
assert_trusted() { # $1 = why
  assertContains "$1" "$(cat "$MISE_LOG")" 'trust'
}

assert_not_trusted() { # $1 = why
  assertEquals "$1" '' "$(cat "$MISE_LOG")"
}

# Asserts that a config at $1 is recognized as a mise config.
assert_path_trusted() { # $1 = relative config path
  seed_config "$1"
  run_hook
  assert_trusted "$1 is a mise config path"
}

# --- the config paths mise discovers ----------------------------------------
#
# Source: https://mise.jdx.dev/configuration.html. Each `mise`-prefixed form
# also has a dotfile spelling, may carry a `.<env>` segment, and may be
# `.local`; the directory forms additionally take a `conf.d/`.

test_a_bare_mise_toml_is_trusted() {
  assert_path_trusted 'mise.toml'
}

test_a_dotted_mise_toml_is_trusted() {
  assert_path_trusted '.mise.toml'
}

test_a_local_mise_toml_is_trusted() {
  assert_path_trusted 'mise.local.toml'
}

test_a_dotted_local_mise_toml_is_trusted() {
  assert_path_trusted '.mise.local.toml'
}

test_an_env_specific_mise_toml_is_trusted() {
  assert_path_trusted 'mise.development.toml'
}

test_an_env_specific_local_mise_toml_is_trusted() {
  assert_path_trusted 'mise.development.local.toml'
}

test_a_mise_directory_config_is_trusted() {
  assert_path_trusted 'mise/config.toml'
}

test_a_dotted_mise_directory_config_is_trusted() {
  assert_path_trusted '.mise/config.toml'
}

test_a_mise_directory_conf_d_drop_in_is_trusted() {
  assert_path_trusted 'mise/conf.d/tools.toml'
}

test_a_dotted_mise_directory_conf_d_drop_in_is_trusted() {
  assert_path_trusted '.mise/conf.d/tools.toml'
}

test_a_config_dir_mise_toml_is_trusted() {
  assert_path_trusted '.config/mise.toml'
}

test_an_env_specific_config_dir_mise_toml_is_trusted() {
  assert_path_trusted '.config/mise.development.toml'
}

test_a_config_dir_mise_config_is_trusted() {
  assert_path_trusted '.config/mise/config.toml'
}

test_an_env_specific_config_dir_mise_config_is_trusted() {
  assert_path_trusted '.config/mise/config.development.toml'
}

test_a_config_dir_conf_d_drop_in_is_trusted() {
  assert_path_trusted '.config/mise/conf.d/tools.toml'
}

test_a_tool_versions_file_is_trusted() {
  # The asdf format mise still reads. It carries no tasks or env, so trusting
  # it changes nothing on its own -- but a project pinning tools this way and
  # keeping tasks in a conf.d drop-in is one `mise run` away from a prompt.
  assert_path_trusted '.tool-versions'
}

# --- what the gate still holds back -----------------------------------------

test_a_worktree_with_no_mise_config_is_left_alone() {
  # The gate's whole purpose: a non-mise project should cost neither a mise
  # call nor, on a PR checkout, a network round trip to resolve the fork.
  run_hook
  assert_not_trusted 'no config means no trust'
}

test_a_nested_mise_config_does_not_trust_the_worktree_root() {
  # Discovery walks up from the cwd, not down from the root, so a config under
  # a subdirectory is not the worktree's config. Trusting on one would hand
  # blanket trust to any repo carrying a mise.toml in a fixture directory.
  seed_config 'test/fixtures/mise.toml'
  run_hook
  assert_not_trusted 'a config below the root is not the root config'
}

test_a_third_party_origin_is_not_trusted() {
  seed_config 'mise.toml'
  STUB_ORIGIN='https://github.com/someone-else/example.git'
  run_hook
  assert_not_trusted 'trust is limited to known owners'
}

test_a_fork_pull_request_is_not_trusted() {
  seed_config 'mise.toml'
  STUB_IS_FORK=true
  export STUB_IS_FORK
  run_hook 42
  assert_not_trusted 'a fork PR checks out attacker-controllable content'
}

# shUnit2 takes over here: it discovers the test_* functions above and prints
# the run summary.
# shellcheck source=/dev/null
. ./vendor/shunit2
