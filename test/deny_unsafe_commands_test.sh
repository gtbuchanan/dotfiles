#!/usr/bin/env bash
#
# Tests for deny-unsafe-commands, the PreToolUse hook that refuses agent
# commands which would print a vault secret into the transcript, or which would
# terminate PowerShell processes by name.
#
# The hook is read straight from home/, not rendered through `chezmoi cat` as
# the hass-vault suite does: it is a plain file rather than a template, so the
# rendered output would be byte-identical, and reading it directly keeps this
# suite free of the config-and-hosttype dance CI would otherwise need. That is
# also what lets it run on every leg rather than only the android one.
#
# Nothing is stubbed and nothing is reached: the hook is a pure function from a
# JSON payload on stdin to a decision on stdout, so these tests are the whole
# behavior. No vault is contacted because the hook never contacts one -- it
# decides on the command string alone, before the command would have run.
#
#   mise run test:shunit2 [-- shUnit2 args, e.g. a test_* name filter]
#
# Built on the vendored shUnit2 (vendor/shunit2): each behavior is a `test_*`
# function, discovered and summarized by the framework. Deliberately no `set -e`
# -- errexit fights shUnit2.
#
# The two halves this suite has to hold apart: every command that emits a
# credential is refused, AND the diagnostic subcommands the agent is told to
# reach for instead stay allowed. A guard that blocked `hass-vault check` would
# push the agent toward the one command that prints the token.
#
# The termination rules ported here from the PowerShell guard that used to run
# beside this one have the same shape: a name-targeted kill is refused and a
# PID-targeted one is not, because reaping a job you started is legitimate and
# that escape hatch has to keep working.

cd "$(dirname "$0")/.." || exit 1

readonly HOOK="$PWD/home/dot_claude/deny-unsafe-commands"

if [ ! -f "$HOOK" ]; then
  echo "SKIP: $HOOK not found"
  exit 0
fi

# --- harness ----------------------------------------------------------------

# A PreToolUse payload carrying $1 as the command. `description` is included
# because the real Bash tool sends one, and it is the field most likely to
# mention a vault command in prose -- see the extraction tests below.
payload() { # $1 = command, $2 = description
  local cmd=${1//\\/\\\\} desc=${2:-run a command}
  cmd=${cmd//\"/\\\"}
  cmd=${cmd//$'\n'/\\n}
  desc=${desc//\"/\\\"}
  printf '{"session_id":"t","hook_event_name":"PreToolUse","tool_name":"Bash",'
  printf '"tool_input":{"command":"%s","description":"%s"}}' "$cmd" "$desc"
}

decide() { payload "$@" | bash "$HOOK"; }

# A deny is identified by the decision field rather than by the reason text, so
# rewording a message does not fail the suite.
assert_denied() { # $1 = why, $2 = command, $3 = description
  assertContains "$1" "$(decide "$2" "$3")" '"permissionDecision": "deny"'
}

# Silence is the allow: the hook stays out of the way so normal permission
# handling continues. An empty stdout is therefore the assertion, not merely the
# absence of a deny.
assert_allowed() { # $1 = why, $2 = command, $3 = description
  assertEquals "$1" '' "$(decide "$2" "$3")"
}

# --- hass-vault -------------------------------------------------------------

test_hass_vault_bare_is_refused() {
  # The sharp edge: the default subcommand is `credential` on both platforms,
  # so a bare invocation prints the token without ever naming it.
  assert_denied 'a bare hass-vault defaults to credential' 'hass-vault'
}

test_hass_vault_credential_is_refused() {
  assert_denied 'names the credential subcommand' 'hass-vault credential'
}

test_hass_vault_diagnostics_are_allowed() {
  assert_allowed 'check reports shape, never values' 'hass-vault check'
  assert_allowed 'status reports cache state only' 'hass-vault status'
  assert_allowed 'refresh reports the same shape as check' 'hass-vault refresh'
  assert_allowed 'reset removes rather than prints' 'hass-vault reset'
}

test_an_instance_prefix_does_not_smuggle_the_credential_through() {
  # The documented way to reach another instance, so it is the form most likely
  # to be typed -- and an env assignment is not a command, so a matcher that
  # only looked at the first word would miss the hass-vault behind it.
  assert_denied 'env assignment then the command' \
    'HASS_VAULT_INSTANCE=parents hass-vault'
  assert_denied 'env assignment then the explicit subcommand' \
    'HASS_VAULT_INSTANCE=parents hass-vault credential'
  assert_allowed 'the same prefix on a diagnostic stays allowed' \
    'HASS_VAULT_INSTANCE=parents hass-vault check'
}

# The command strings below are fixtures, not commands this suite runs: an
# unexpanded ~ and an unexpanded $HOME are the literal text a hook receives, and
# expanding either here would test a different input than the one intended.
# shellcheck disable=SC2016,SC2088
test_a_path_qualified_invocation_is_refused() {
  assert_denied 'a tilde path' '~/.local/bin/hass-vault credential'
  assert_denied 'an absolute path' '/data/data/com.termux/files/home/.local/bin/hass-vault'
  assert_denied 'the PowerShell entry point' '& $HOME/.local/bin/hass-vault.ps1'
  assert_denied 'the cmd shim' 'C:\Users\me\.local\bin\hass-vault.cmd credential'
}

# Fixtures again: the substitution below is the literal text under test, so it
# must reach the hook unexpanded.
# shellcheck disable=SC2016
test_a_command_after_a_separator_is_refused() {
  # A matcher anchored only at the start of the string would let every one of
  # these through.
  assert_denied 'after &&' 'cd /tmp && hass-vault'
  assert_denied 'after a semicolon' 'echo hi; hass-vault credential'
  assert_denied 'after a pipe' 'true | hass-vault'
  assert_denied 'inside a substitution' 'TOKEN=$(hass-vault credential)'
  assert_denied 'inside a quoted -c string' 'pwsh -c "hass-vault credential"'
}

# --- the sanctioned path ----------------------------------------------------

test_hass_cli_is_left_alone() {
  # The wrapper resolves the credential in a subprocess the hook never sees.
  # Blocking it would defeat the point: this guard exists so the agent uses
  # hass-cli, not so it stops.
  assert_allowed 'the intended entry point' 'hass-cli state get sun.sun'
  assert_allowed 'with an instance prefix' \
    'HASS_VAULT_INSTANCE=parents hass-cli state list'
}

# --- reading the files is not running them ----------------------------------

test_reading_or_searching_these_files_is_not_denied() {
  # The failure mode this suite exists to prevent as much as any bypass: the
  # sibling deny-pwsh-kill hook blocks `cat` of its own source, because it
  # matches its trigger words anywhere in the string. Matching in command
  # position instead keeps the repo readable.
  assert_allowed 'cat the hook' 'cat home/dot_claude/deny-unsafe-commands'
  assert_allowed 'cat the resolver' 'cat home/dot_local/bin/hass-vault.ps1'
  assert_allowed 'grep for the subcommand' \
    'grep -n credential home/dot_local/bin/hass-vault.ps1'
  assert_allowed 'a path in an argument, not in command position' \
    'chezmoi apply --no-tty ~/.local/bin/hass-vault'
  assert_allowed 'the test suite itself' 'bash test/deny_unsafe_commands_test.sh'
}

test_a_description_mentioning_a_vault_command_does_not_deny() {
  # The description is model-authored prose sent alongside every Bash call. It
  # is not executed, so it must not decide.
  assert_allowed 'prose naming the command' \
    "$(printf 'hass-cli state get sun.sun')" \
    'Run hass-vault credential to get the token'
}

# --- bw-session -------------------------------------------------------------

# Fixture: the unexpanded $HOME is the literal text the hook has to cope with.
# shellcheck disable=SC2016
test_bw_session_get_is_refused() {
  assert_denied 'termux, bare, defaults to get' 'bw-session-termux'
  assert_denied 'termux, explicit' 'bw-session-termux get'
  assert_denied 'windows, bare' '& $HOME/.local/bin/bw-session-windows.ps1'
  assert_denied 'windows, explicit' 'bw-session-windows.ps1 get'
}

test_bw_session_diagnostics_are_allowed() {
  assert_allowed 'check is an exit code, not a key' 'bw-session-termux check'
  assert_allowed 'status reports the window' 'bw-session-windows.ps1 status'
  assert_allowed 'lock removes rather than prints' 'bw-session-termux lock'
  assert_allowed 'reset removes rather than prints' 'bw-session-termux reset'
}

# --- always-secret helpers --------------------------------------------------

test_helpers_that_only_ever_print_a_secret_are_refused() {
  # No safe subcommand to carve out: emitting the secret is the whole contract
  # these are invoked under.
  assert_denied 'the biometric unlock prints the session key' 'bwbio'
  assert_denied 'askpass prints the passphrase' 'ssh-askpass-bw'
  assert_denied 'the termux askpass' 'ssh-askpass-termux'
  assert_denied 'the askpass cmd shim' 'ssh-askpass-bw.cmd'
}

# --- the bw CLI itself ------------------------------------------------------

test_bw_subcommands_that_emit_secrets_are_refused() {
  # Blocking only the wrappers would leave the level beneath them open, which
  # is where an agent would go next once a wrapper refused.
  assert_denied 'a password' 'bw get password "Home Assistant"'
  assert_denied 'item json carries the token field' 'bw list items --search ha'
  assert_denied 'a whole vault' 'bw export --format json'
  assert_denied 'unlock prints the session key' 'bw unlock --raw'
  assert_denied 'so does login' 'bw login --apikey'
}

test_bw_subcommands_that_do_not_emit_secrets_are_allowed() {
  # An allowlist here would block `bw edit`, `bw create` and the rest with no
  # secrecy payoff, so this half is a denylist and these must stay untouched.
  assert_allowed 'status is vault state' 'bw status'
  assert_allowed 'sync moves no secret to stdout' 'bw sync'
  assert_allowed 'lock removes rather than prints' 'bw lock'
  assert_allowed 'bare bw prints help' 'bw'
}

test_a_binary_is_matched_whole_not_by_prefix() {
  # `bw` and `bwbio` differ by a suffix and by their entire decision table, so
  # a prefix match would either free bwbio or trap every bw subcommand.
  assert_allowed 'bwbio is not bw status' 'bw status'
  assert_denied 'bw is not bwbio' 'bwbio'
  assert_allowed 'an unrelated command sharing a prefix' 'bwrap --version'
}

# --- payload handling -------------------------------------------------------

test_a_payload_without_a_command_is_ignored() {
  assertEquals 'no command field, no opinion' '' \
    "$(printf '{"tool_name":"Read","tool_input":{"file_path":"/x"}}' | bash "$HOOK")"
}

test_malformed_or_empty_input_is_ignored() {
  assertEquals 'empty stdin' '' "$(printf '' | bash "$HOOK")"
  assertEquals 'not json' '' "$(printf 'not json at all' | bash "$HOOK")"
}

test_the_hook_always_exits_zero() {
  # A non-zero exit is how a hook reports that it broke. The decision travels in
  # the JSON, so exiting non-zero on a deny would report a broken hook instead.
  decide 'hass-vault credential' >/dev/null
  assertEquals 'a deny still exits 0' 0 $?
  decide 'hass-vault check' >/dev/null
  assertEquals 'an allow exits 0' 0 $?
}

test_a_deny_names_the_diagnostic_to_use_instead() {
  # A refusal that does not say what to run instead invites the agent to work
  # around it, which is the failure this whole guard is trying to avoid.
  local out
  out=$(decide 'hass-vault credential')
  assertContains 'points at check' "$out" 'check'
  assertContains 'points at status' "$out" 'status'
}

test_the_decision_is_well_formed_json() {
  # Claude Code parses this; a malformed payload is silently no guard at all.
  local out
  out=$(decide 'hass-vault credential')
  assertContains 'the event name' "$out" '"hookEventName": "PreToolUse"'
  assertContains 'the decision' "$out" '"permissionDecision": "deny"'
  assertContains 'the reason' "$out" '"permissionDecisionReason"'
}

# --- process termination ----------------------------------------------------

test_a_name_targeted_powershell_kill_is_refused() {
  # A name or image kill hits every matching process on the machine: other
  # agent sessions, the user's own terminals, and the harness's shell host.
  assert_denied 'by name' 'Stop-Process -Name pwsh'
  assert_denied 'by image' 'taskkill /IM pwsh.exe /F'
  assert_denied 'piped from Get-Process' 'Get-Process pwsh | Stop-Process'
  assert_denied 'the alias' 'spps -Name powershell'
  assert_denied 'the unix spelling' 'pkill -f pwsh'
  assert_denied 'and its neighbour' 'killall pwsh'
}

test_termination_expressions_that_are_not_commands_are_refused() {
  # Neither of these puts the terminating verb in command position, so the
  # command-position rule that catches everything above would miss them.
  assert_denied 'the method call' '(Get-Process pwsh).Kill()'
  assert_denied 'the CIM method' \
    'Get-CimInstance Win32_Process | Invoke-CimMethod -MethodName Terminate # pwsh'
}

test_a_pid_targeted_kill_is_allowed() {
  # The escape hatch, and the reason the rule is about names rather than about
  # killing: reaping a process you started is legitimate, and a PID names no
  # PowerShell process.
  assert_allowed 'by id' 'Stop-Process -Id 4321'
  assert_allowed 'taskkill by pid' 'taskkill /PID 4321'
  assert_allowed 'unix kill by pid' 'kill 4321'
  assert_allowed 'and with a signal' 'kill -9 4321'
}

test_killing_something_other_than_powershell_is_allowed() {
  assert_allowed 'an unrelated name' 'pkill -f node'
  assert_allowed 'an unrelated image' 'taskkill /IM chrome.exe'
}

test_naming_the_guarded_verbs_without_running_them_is_allowed() {
  # The bug that motivated the port: the PowerShell guard matched its trigger
  # words anywhere in the string, so it refused reading its own source and
  # refused a commit message that merely named the file it lived in.
  assert_allowed 'grep for the verb' 'grep -rn Stop-Process home/'
  assert_allowed 'a path naming both triggers' \
    'cat home/dot_claude/deny-pwsh-kill.ps1'
  assert_allowed 'prose naming both triggers' \
    'git log --oneline --grep pwsh-kill'
}

test_case_does_not_change_the_termination_verdict() {
  # PowerShell resolves command names case-insensitively, so a case-sensitive
  # guard is a guard with a one-keystroke bypass.
  assert_denied 'lowercased' 'stop-process -name pwsh'
  assert_denied 'shouted' 'STOP-PROCESS -NAME PWSH'
}

# shUnit2 takes over here: it discovers the test_* functions above and prints
# the run summary.
# shellcheck source=/dev/null
. ./vendor/shunit2
