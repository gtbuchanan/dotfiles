#!/usr/bin/env bash
#
# Tests for the Git Bash hass-cli wrapper (home/.chezmoitemplates/
# hass-cli-gitbash), which resolves credentials and runs hass-cli.exe itself
# so that an argument typed in Git Bash reaches the binary as typed.
#
# The partial is plain shell, so it runs here as written with no rendering.
# Each test lays out a sandbox the way the deployed tree is: the wrapper in
# wrappers/, a stub hass-vault.cmd beside that, and a stub hass-cli.exe under
# what LOCALAPPDATA names. The stub resolver ends its lines in CRLF, as cmd
# does. On Windows the stub binary is a real .NET Framework executable, so it
# splits its command line by the same C runtime rules hass-cli.exe does --
# what reaches the binary is the whole question. Elsewhere it is a shell
# script and cygpath is stubbed, which still exercises the credential
# handling.
#
#   mise run test:shunit2 [-- shUnit2 args, e.g. a test_* name filter]
#
# Built on the vendored shUnit2 (vendor/shunit2): each behavior is a `test_*`
# function, discovered and summarized by the framework. Deliberately no `set -e`
# -- errexit fights shUnit2.

cd "$(dirname "$0")/.." || exit 1

readonly ROOT="$PWD"
readonly SOURCE="$ROOT/home/.chezmoitemplates/hass-cli-gitbash"

is_windows() {
  case "$(uname -o 2>/dev/null)" in Msys | Cygwin) return 0 ;; esac
  return 1
}

if is_windows && ! command -v powershell.exe >/dev/null 2>&1; then
  echo "SKIP: powershell.exe not available to compile the stub hass-cli.exe"
  exit 0
fi

# --- harness ----------------------------------------------------------------

oneTimeSetUp() {
  WORK=$(mktemp -d)

  if is_windows; then
    # Compiled once: starting Windows PowerShell to drive csc costs seconds,
    # and every sandbox can copy the same binary.
    cat >"$WORK/stub.cs" <<'CS'
using System;
using System.IO;

static class Program {
  static int Main(string[] args) {
    // LF, not WriteAllLines' CRLF, so a CR that leaked into a value shows.
    var dir = AppDomain.CurrentDomain.BaseDirectory;
    File.WriteAllText(Path.Combine(dir, "args.txt"), string.Join("\n", args) + "\n");
    File.WriteAllText(Path.Combine(dir, "env.txt"),
      Environment.GetEnvironmentVariable("HASS_SERVER") + "\n" +
      Environment.GetEnvironmentVariable("HASS_TOKEN") + "\n");
    return args.Length;
  }
}
CS
    powershell.exe -NoProfile -NonInteractive -Command \
      "Add-Type -TypeDefinition (Get-Content -Raw '$(cygpath -w "$WORK/stub.cs")') -OutputAssembly '$(cygpath -w "$WORK/stub.exe")' -OutputType ConsoleApplication" ||
      fail 'could not compile the stub hass-cli.exe'
  else
    # Git for Windows ships cygpath; here the sandbox paths are already POSIX.
    mkdir -p "$WORK/bin"
    cat >"$WORK/bin/cygpath" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "${@: -1}"
STUB
    chmod +x "$WORK/bin/cygpath"
    PATH="$WORK/bin:$PATH"
  fi
}

oneTimeTearDown() {
  [ -n "${WORK:-}" ] && rm -rf "$WORK"
}

# Echoes a fresh sandbox directory. STUB_VAULT=fails makes the resolver fail;
# STUB_SHIM=none leaves the binary out.
new_sandbox() {
  local box
  box=$(mktemp -d "$WORK/sandbox.XXXXXX")
  mkdir -p "$box/wrappers" "$box/appdata/mise/shims"
  cp "$SOURCE" "$box/wrappers/hass-cli"
  chmod +x "$box/wrappers/hass-cli"

  if [ "${STUB_VAULT:-}" = fails ]; then
    write_resolver "$box" 'echo hass-vault: the vault is locked>&2' 'exit /b 1' \
      <<'STUB'
#!/usr/bin/env bash
echo 'hass-vault: the vault is locked' >&2
exit 1
STUB
  else
    write_resolver "$box" \
      'if not "%~1"=="credential" exit /b 2' \
      'echo https://ha.example' \
      'echo token-from-vault' <<'STUB'
#!/usr/bin/env bash
[ "$1" = credential ] || exit 2
printf 'https://ha.example\r\ntoken-from-vault\r\n'
STUB
  fi

  if [ "${STUB_SHIM:-}" != none ]; then
    if is_windows; then
      cp "$WORK/stub.exe" "$box/appdata/mise/shims/hass-cli.exe"
    else
      cat >"$box/appdata/mise/shims/hass-cli.exe" <<'STUB'
#!/usr/bin/env bash
dir=$(dirname "$0")
printf '%s\n' "$@" >"$dir/args.txt"
printf '%s\n%s\n' "${HASS_SERVER-}" "${HASS_TOKEN-}" >"$dir/env.txt"
exit $#
STUB
      chmod +x "$box/appdata/mise/shims/hass-cli.exe"
    fi
  fi

  printf '%s' "$box"
}

# hass-vault.cmd as cmd sees it on Windows (the arguments, one line each), or
# as a script with the same behavior elsewhere (stdin).
write_resolver() {
  local box=$1
  shift
  if is_windows; then
    printf '%s\r\n' '@echo off' "$@" >"$box/hass-vault.cmd"
  else
    cat >"$box/hass-vault.cmd"
    chmod +x "$box/hass-vault.cmd"
  fi
}

run_wrapper() {
  local box=$1 appdata
  shift
  appdata="$box/appdata"
  is_windows && appdata=$(cygpath -w "$appdata")
  LOCALAPPDATA="$appdata" "$box/wrappers/hass-cli" "$@" >"$box/wrapper.out" 2>&1
}

# What the stub binary recorded, CRs and all.
received() {
  cat "$1/appdata/mise/shims/$2" 2>/dev/null
}

said() {
  printf '; wrapper said:\n%s' "$(cat "$1/wrapper.out" 2>/dev/null)"
}

# --- argument passing -------------------------------------------------------

test_delivers_a_json_payload_with_its_quotes_intact() {
  local box
  box=$(new_sandbox)
  run_wrapper "$box" --json '{"entity_id": "switch.x"}'
  assertEquals "argv$(said "$box")" \
    $'--json\n{"entity_id": "switch.x"}' "$(received "$box" args.txt)"
}

test_delivers_an_argument_containing_spaces_as_one_argument() {
  local box
  box=$(new_sandbox)
  run_wrapper "$box" --name 'Living Room Lamp'
  assertEquals "argv$(said "$box")" \
    $'--name\nLiving Room Lamp' "$(received "$box" args.txt)"
}

test_delivers_a_template_filter_pipe_inside_a_json_payload() {
  local box
  box=$(new_sandbox)
  run_wrapper "$box" --json '{"template": "{{ 2.6 | round }}"}'
  assertEquals "argv$(said "$box")" \
    $'--json\n{"template": "{{ 2.6 | round }}"}' "$(received "$box" args.txt)"
}

test_delivers_cmd_redirection_and_chaining_characters_literally() {
  local box
  box=$(new_sandbox)
  run_wrapper "$box" --json '{"a": "x & y < z > w"}'
  assertEquals "argv$(said "$box")" \
    $'--json\n{"a": "x & y < z > w"}' "$(received "$box" args.txt)"
}

test_propagates_the_exit_code() {
  local box rc
  box=$(new_sandbox)
  run_wrapper "$box" state get light.kitchen
  rc=$?
  assertEquals "exit status$(said "$box")" 3 "$rc"
}

# --- credentials ------------------------------------------------------------

test_hands_hass_cli_the_resolved_server_and_token() {
  local box
  box=$(new_sandbox)
  run_wrapper "$box" state list
  assertEquals "environment$(said "$box")" \
    $'https://ha.example\ntoken-from-vault' "$(received "$box" env.txt)"
}

test_exits_1_when_credentials_do_not_resolve() {
  local box rc
  box=$(STUB_VAULT=fails new_sandbox)
  run_wrapper "$box" state list
  rc=$?
  assertEquals "exit status$(said "$box")" 1 "$rc"
}

test_does_not_run_hass_cli_when_credentials_do_not_resolve() {
  local box
  box=$(STUB_VAULT=fails new_sandbox)
  run_wrapper "$box" state list
  assertFalse "hass-cli ran$(said "$box")" \
    "[ -e '$box/appdata/mise/shims/args.txt' ]"
}

test_exits_127_when_the_mise_shim_is_missing() {
  local box rc
  box=$(STUB_SHIM=none new_sandbox)
  run_wrapper "$box" state list
  rc=$?
  assertEquals "exit status$(said "$box")" 127 "$rc"
}

# An exec of a missing file exits 127 as well, so only the message shows the
# wrapper checked rather than failing over to bash's own error.
test_names_the_missing_mise_shim_and_how_to_install_it() {
  local box
  box=$(STUB_SHIM=none new_sandbox)
  run_wrapper "$box" state list
  assertContains 'diagnostic' "$(cat "$box/wrapper.out")" "run 'mise install'"
}

# shellcheck source=/dev/null
. ./vendor/shunit2
