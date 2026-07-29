#!/usr/bin/env pwsh
# Lint PowerShell sources with PSScriptAnalyzer, mirroring
# scripts/lint-templates.sh: hk passes the changed files as positional args and
# this wraps the module so the hk step stays a one-liner. Rules live in
# PSScriptAnalyzerSettings.psd1 at the repo root (also honored by the VS Code
# PowerShell extension).
#
# Check-only: PSScriptAnalyzer's -Fix rewrites files in place, so autofix is
# left to the editor, which applies the same psd1. (-Fix also amplifies the
# cold-start crash worked around below.)
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
#
# PSScriptAnalyzer intermittently throws a NullReferenceException ("Object
# reference not set to an instance of an object") on the first analysis in a
# fresh process when the formatting rules run against a file containing backtick
# line continuations -- its correction engine dereferences a null token during
# cold initialization. hk spawns a new pwsh per run, so it always takes this
# cold path and hits the crash roughly half the time. A later call in the same
# process reliably succeeds (the failed attempt still warms the type init), so
# retry the transient fault before surfacing it. Genuine analysis problems
# reproduce on every attempt and still throw once the retries are exhausted.
$maxAttempts = 3
$findings = foreach ($file in $Path) {
  for ($attempt = 1; ; $attempt++) {
    try {
      # Capture then emit so a crash mid-analysis can't leak partial findings
      # into the pipeline ahead of a successful retry.
      $result = Invoke-ScriptAnalyzer -Path $file -Settings $settings
      $result
      break
    }
    catch {
      # The cold-start fault surfaces with the NullReferenceException message
      # ("Object reference not set..."); match it so a wrapped rethrow is caught
      # too. Any other failure is real -- rethrow it without retrying.
      $transient = $_.Exception.Message -match 'Object reference not set'
      if (-not $transient -or $attempt -ge $maxAttempts) { throw }
    }
  }
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
