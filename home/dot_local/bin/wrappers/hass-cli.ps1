# Hands hass-cli.cmd its arguments escaped for the binary rather than for cmd.
#
# PowerShell quotes a native argument the way the callee parses it, and for a
# .cmd it picks cmd's convention: inner quotes go across bare. cmd passes that
# text on to hass-cli.exe, whose own parser then eats them, so
# `--json '{"entity_id": "switch.x"}'` arrives as `{entity_id: switch.x}` and
# hass-cli reports a JSONDecodeError about property names. `Standard` passing
# escapes them as \" instead, which survives both parsers; the variable is
# scoped to this script, so no other command's quoting changes.
#
# pwsh resolves this ahead of the .cmd beside it, so PowerShell callers land
# here while cmd and Git Bash keep reaching the .cmd directly. It delegates
# rather than running hass-cli itself, which keeps one wrapper responsible for
# the credentials and this one responsible for the quoting.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
  'PSUseDeclaredVarsMoreThanAssignments', 'PSNativeCommandArgumentPassing',
  Justification = 'A preference variable, read by PowerShell rather than by this script'
)]
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments)] [string[]] $Arguments)

$PSNativeCommandArgumentPassing = 'Standard'

& (Join-Path $PSScriptRoot 'hass-cli.cmd') @Arguments
exit $LASTEXITCODE
