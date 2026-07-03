#!/usr/bin/env pwsh
# Lint PowerShell sources with PSScriptAnalyzer, mirroring
# scripts/lint-templates.sh: hk passes the changed files as positional args and
# this wraps the module so the hk step stays a one-liner. Rules live in
# PSScriptAnalyzerSettings.psd1 at the repo root (also honored by the VS Code
# PowerShell extension).
#
# Check-only: PSScriptAnalyzer's -Fix rewrites files in place and throws on some
# valid inputs (e.g. NullReferenceException on scripts with backtick line
# continuations), so autofix is left to the editor, which applies the same psd1.
[CmdletBinding()]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Path = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Path.Count -eq 0) { exit 0 }

# Prefer the repo-local, pinned module provisioned by provision-psmodules.ps1;
# fall back to whatever PSScriptAnalyzer is already on PSModulePath.
$root = Join-Path $PSScriptRoot '..'
$repoModules = Join-Path $root '.psmodules'
if (Test-Path $repoModules) {
  $env:PSModulePath = $repoModules + [IO.Path]::PathSeparator + $env:PSModulePath
}

$settings = Join-Path $root 'PSScriptAnalyzerSettings.psd1'

# Invoke-ScriptAnalyzer -Path is single-valued, so analyze each file in turn.
$findings = foreach ($file in $Path) {
  Invoke-ScriptAnalyzer -Path $file -Settings $settings
}

if ($findings) {
  $report = $findings |
    Format-Table -AutoSize -Wrap -Property Severity, RuleName,
    @{ Label = 'Location'; Expression = { '{0}:{1}' -f $_.ScriptPath, $_.Line } },
    Message |
    Out-String
  [Console]::Error.WriteLine($report)
  exit 1
}
exit 0
