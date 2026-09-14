#!/usr/bin/env bash
#
# Tests for wt-post-start, the worktrunk hook that runs a fresh worktree's
# project setup: a mise `prepare` task where one exists, otherwise a
# package-manager install.
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
# What this suite is really holding in place is one distinction. `mise tasks
# info <name>` exits non-zero both when the task does not exist and when the
# config could not be read, and those want opposite responses: the first is an
# ordinary project without a prepare task, the second is a worktree wt-pre-start
# refused to trust. Collapsing them is silent in both directions -- a prepare
# task that never runs, or a fork PR's setup that runs when it was meant not to
# -- so each is asserted separately below.

cd "$(dirname "$0")/.." || exit 1

readonly HOOK="$PWD/home/dot_local/bin/executable_wt-post-start"

if [ ! -f "$HOOK" ]; then
  echo "SKIP: $HOOK not found"
  exit 0
fi

# --- harness ----------------------------------------------------------------

# The hook reaches for exactly three externals -- mise, pnpm and npm -- so the
# stub directory can be the whole PATH. That is what lets the "mise is not
# installed" case be tested honestly: omitting the stub genuinely removes mise,
# rather than shadowing the real one with something pretending to be absent.
setUp() {
  STUB_DIR=$(mktemp -d) || fail 'could not create stub dir'
  WT_PATH=$(mktemp -d) || fail 'could not create worktree dir'
  MISE_LOG="$STUB_DIR/mise.log"
  PM_LOG="$STUB_DIR/pm.log"
  : >"$MISE_LOG"
  : >"$PM_LOG"

  # `tasks ls` stands for "the config is readable": mise exits 0 for a readable
  # config and for no config at all, and non-zero only when one exists and
  # cannot be read. STUB_READABLE picks which. STUB_TASKS is the set of tasks
  # that exist.
  cat >"$STUB_DIR/mise" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>'$MISE_LOG'
case "\$3" in
tasks)
  [ "\${STUB_READABLE:-true}" = true ] || exit 1
  case "\$4" in
  ls) exit 0 ;;
  info)
    case " \${STUB_TASKS:-} " in
    *" \$5 "*) exit 0 ;;
    *) exit 1 ;;
    esac
    ;;
  esac
  ;;
esac
exit 0
EOF

  for pm in pnpm npm; do
    cat >"$STUB_DIR/$pm" <<EOF
#!/bin/sh
printf '$pm %s\n' "\$*" >>'$PM_LOG'
EOF
  done

  chmod +x "$STUB_DIR/mise" "$STUB_DIR/pnpm" "$STUB_DIR/npm"
}

tearDown() {
  rm -rf "$STUB_DIR" "$WT_PATH"
  unset STUB_READABLE STUB_TASKS
}

# PATH is the stub directory alone -- see setUp. The interpreter is named
# absolutely because the stripped PATH is in force for this command's own
# lookup too, and `sh` would not survive it.
run_hook() {
  PATH="$STUB_DIR" /bin/sh "$HOOK" "$WT_PATH" >"$STUB_DIR/out" 2>"$STUB_DIR/err"
}

# Identified by the subcommand reaching the stub rather than by anything the
# hook prints, so wording changes do not fail the suite.
assert_ran_task() { # $1 = why, $2 = task name
  assertContains "$1" "$(cat "$MISE_LOG")" "run $2"
}

assert_ran_no_task() { # $1 = why
  local ran
  ran=$(grep -c ' run ' "$MISE_LOG")
  assertEquals "$1" '0' "$ran"
}

assert_installed() { # $1 = why, $2 = expected command line
  assertContains "$1" "$(cat "$PM_LOG")" "$2"
}

assert_installed_nothing() { # $1 = why
  assertEquals "$1" '' "$(cat "$PM_LOG")"
}

# --- a readable config: the task gate means what it says --------------------

test_a_prepare_task_is_run() {
  STUB_TASKS='prepare'
  export STUB_TASKS
  run_hook
  assert_ran_task 'prepare is the project setup entry point' 'prepare'
  assert_installed_nothing 'the task owns setup, so no fallback'
}

test_prepare_wins_over_bootstrap() {
  STUB_TASKS='prepare bootstrap'
  export STUB_TASKS
  run_hook
  assert_ran_task 'prepare is preferred' 'prepare'
  assertNotContains 'bootstrap is the deprecated spelling' \
    "$(cat "$MISE_LOG")" 'run bootstrap'
}

test_bootstrap_is_run_when_prepare_is_absent() {
  STUB_TASKS='bootstrap'
  export STUB_TASKS
  run_hook
  assert_ran_task 'bootstrap still works for unmigrated projects' 'bootstrap'
}

test_pnpm_is_the_fallback_for_a_project_with_no_task() {
  : >"$WT_PATH/pnpm-lock.yaml"
  run_hook
  assert_ran_no_task 'there is no task to run'
  assert_installed 'a lockfile is the fallback signal' 'install --frozen-lockfile'
}

test_npm_is_the_fallback_for_a_non_pnpm_project() {
  : >"$WT_PATH/package-lock.json"
  run_hook
  assert_installed 'npm ci is the npm equivalent' 'ci'
}

test_a_project_with_neither_task_nor_lockfile_is_left_alone() {
  run_hook
  assert_ran_no_task 'nothing to run'
  assert_installed_nothing 'nothing to install'
}

# --- an unreadable config: a refusal, not an empty task list ----------------

test_an_untrusted_config_does_not_run_a_task() {
  # The regression this suite exists for. `mise run` trusts the config of any
  # task it is asked to run, so reaching it at all would execute setup that
  # wt-pre-start declined to trust -- a fork PR, or a clone whose origin is not
  # ours.
  STUB_READABLE=false
  STUB_TASKS='prepare'
  export STUB_READABLE STUB_TASKS
  run_hook
  assert_ran_no_task 'an untrusted config must not reach mise run'
}

test_an_untrusted_config_does_not_fall_through_to_a_package_manager() {
  # The same arbitrary code by another route: install lifecycle scripts come
  # from the same untrusted checkout.
  STUB_READABLE=false
  export STUB_READABLE
  : >"$WT_PATH/pnpm-lock.yaml"
  run_hook
  assert_installed_nothing 'the fallback is not a way around the refusal'
}

test_an_untrusted_config_says_so() {
  # Silence here is indistinguishable from a project that needed no setup,
  # which is how the old conflation hid: the worktree looked ready and was not.
  STUB_READABLE=false
  export STUB_READABLE
  run_hook
  assertNotEquals 'the skip is reported' '' "$(cat "$STUB_DIR/err")"
}

test_an_untrusted_config_is_not_an_error_exit() {
  # worktrunk surfaces a failing post-start hook as a failed worktree creation.
  # Declining to run setup is a decision, not a failure.
  STUB_READABLE=false
  export STUB_READABLE
  run_hook
  assertEquals 'the hook still succeeds' '0' "$?"
}

# --- mise absent entirely ---------------------------------------------------

test_a_missing_mise_still_falls_back_to_the_package_manager() {
  # Not every host with a worktree has mise. An absent mise is not an untrusted
  # config, and must not be read as one -- these projects are exactly the ones
  # the package-manager fallback is for.
  rm -f "$STUB_DIR/mise"
  : >"$WT_PATH/pnpm-lock.yaml"
  run_hook
  assert_installed 'the fallback still runs without mise' 'install --frozen-lockfile'
}

# shUnit2 takes over here: it discovers the test_* functions above and prints
# the run summary.
# shellcheck source=/dev/null
. ./vendor/shunit2
