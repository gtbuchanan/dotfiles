# Runs hass-cli with credentials in its environment, for PowerShell callers.
#
# hass-cli.cmd beside this file does the same job for cmd, and PowerShell
# could reach it too, but not with arbitrary arguments intact. cmd parses the
# `"%SHIM%" %*` line again after expanding it and does not honour the \"
# escapes a JSON argument needs, so each one toggles its quote state and a `|`,
# `&`, `<` or `>` left outside a quoted span becomes an operator:
# `--json '{"template": "{{ 2.6 | round }}"}'` runs `round` as a command. A
# batch file cannot forward arbitrary arguments safely, so this resolves the
# credentials itself and starts hass-cli.exe directly, leaving cmd out of the
# argument path. pwsh resolves a .ps1 ahead of a .cmd of the same name, so
# PowerShell callers land here and cmd callers, who already escape for cmd,
# keep the .cmd.
#
# `Standard` passing guards against a caller who set `Legacy`, which drops the
# inner quotes of a JSON argument. The variable is scoped to this script.
#
# See docs/home-assistant.md for the rest of the design, which this shares
# with the .cmd and the Termux wrapper.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
  'PSUseDeclaredVarsMoreThanAssignments', 'PSNativeCommandArgumentPassing',
  Justification = 'A preference variable, read by PowerShell rather than by this script'
)]
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments)] [string[]] $Arguments)

$PSNativeCommandArgumentPassing = 'Standard'

# The real binary, not the shim beside it on PATH: invoking `hass-cli` here
# would find this wrapper again and recurse.
$shim = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'mise' `
  -AdditionalChildPath 'shims', 'hass-cli.exe'
if (-not (Test-Path -LiteralPath $shim -PathType Leaf)) {
  [Console]::Error.WriteLine("hass-cli: mise shim not found at $shim")
  [Console]::Error.WriteLine("hass-cli: run 'mise install' to install the pinned CLI")
  exit 127
}

# In-process rather than through hass-vault.cmd, which would start a second
# pwsh to run the same script. By path, so nothing in the caller's directory
# or PATH can stand in for the resolver. It exits non-zero on every failure
# and writes its reason to stderr, keeping the success stream for the pair.
$resolver = Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'hass-vault.ps1'
$credential = @(& $resolver credential)
if ($LASTEXITCODE -ne 0 -or $credential.Count -ne 2) {
  [Console]::Error.WriteLine("hass-cli: could not resolve credentials; run 'hass-vault check'")
  exit 1
}

# PowerShell has no per-process environment for a child, so the pair goes into
# this process's environment for the duration of the call, and whatever the
# caller had there is put back however the call ends.
$saved = @{ HASS_SERVER = $env:HASS_SERVER; HASS_TOKEN = $env:HASS_TOKEN }
try {
  $env:HASS_SERVER, $env:HASS_TOKEN = $credential
  Remove-Variable credential
  & $shim @Arguments
}
finally {
  $env:HASS_SERVER = $saved.HASS_SERVER
  $env:HASS_TOKEN = $saved.HASS_TOKEN
}
exit $LASTEXITCODE
