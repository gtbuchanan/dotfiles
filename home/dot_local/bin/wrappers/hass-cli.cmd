@echo off
rem Runs hass-cli with credentials in its environment and nowhere else.
rem
rem hass-cli reads its server and token from the environment on every invocation
rem and has no config file, so something must put them there. This used to be
rem mise's `[env]`, which exported them to every process mise spawns through a
rem shim and to every child of an activated shell -- and `redact` hid them from
rem `mise doctor` but not from `mise env`, which prints both in full. This
rem wrapper narrows all of that to the one process that needs them.
rem
rem It works because PATH puts %USERPROFILE%\.local\bin\wrappers ahead of mise's
rem shims: on the user PATH via the winget config for non-interactive callers,
rem and again after `mise activate` in the PowerShell profile, which prepends
rem mise's real tool paths and would otherwise bury this. So agents, scripts,
rem Git Bash, and interactive shells all reach this rather than the binary --
rem which is what a shell function could never do, and why `[env]` was the
rem original answer.
rem
rem Two things follow from only running when someone asked for hass-cli. It may
rem prompt, where an `[env]` resolver had to stay silent rather than raise a
rem dialog on an unrelated command. And a failure is this command's failure
rem alone, so it exits non-zero and says why, rather than the `|| exit 0` the
rem fragment needed to keep a locked vault from breaking every mise command.
rem
rem One `hass-vault` call, not two: resolving costs a vault round trip, and
rem splitting it across two subcommands would pay that twice.
rem
rem cmd rather than a .ps1 behind a shim: `hass-vault` is already a .cmd that
rem starts pwsh, and routing this through pwsh as well would put a second
rem interpreter startup in front of every hass-cli call.
setlocal EnableExtensions

rem The real binary, not the shim beside it on PATH -- invoking `hass-cli` here
rem would find this wrapper again and recurse. mise's shim is the stable path;
rem the versioned install directory is not.
set "SHIM=%LOCALAPPDATA%\mise\shims\hass-cli.exe"
if not exist "%SHIM%" (
  echo hass-cli: mise shim not found at %SHIM%>&2
  echo hass-cli: run 'mise install' to install the pinned CLI>&2
  exit /b 127
)

rem Read the pair over a pipe rather than through argv, which any process
rem listing can read. `defined` is evaluated per iteration, so the first line
rem lands in HASS_SERVER and the second in HASS_TOKEN without delayed expansion.
rem
rem Resolved by path, not by name: cmd.exe searches the caller's current
rem directory before PATH, so a stray hass-vault.cmd in whatever directory
rem hass-cli happened to be run from would be executed here and its output
rem taken as the credentials. The Termux wrapper needs no equivalent -- a
rem POSIX PATH does not include the current directory.
set "HASS_SERVER="
set "HASS_TOKEN="
for /f "usebackq delims=" %%L in (`"%~dp0..\hass-vault.cmd" credential`) do (
  if not defined HASS_SERVER (
    set "HASS_SERVER=%%L"
  ) else if not defined HASS_TOKEN (
    set "HASS_TOKEN=%%L"
  )
)

if not defined HASS_TOKEN (
  echo hass-cli: could not resolve credentials; run 'hass-vault check'>&2
  exit /b 1
)

rem setlocal scopes both variables to this process and its children, so they are
rem gone when it exits. cmd has no exec, so unlike the Termux wrapper this stays
rem as a parent holding the same values -- no wider exposure, since reading them
rem there needs the access that reading the child's environment already needs.
"%SHIM%" %*
exit /b %ERRORLEVEL%
