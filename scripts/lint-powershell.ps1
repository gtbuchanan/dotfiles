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
# PSScriptAnalyzer intermittently fails on the first analysis in a fresh
# process, while its own initialization is still cold. hk spawns a new pwsh per
# run, so it always takes that path and hits the fault a good fraction of the
# time. A later call in the same process reliably succeeds -- the failed attempt
# still warms the type init -- so retry before surfacing it.
#
# Two shapes have been seen, and they share nothing textually:
#
#   - a NullReferenceException ("Object reference not set to an instance of an
#     object"), from the correction engine dereferencing a null token when the
#     formatting rules run against backtick line continuations
#   - "The term 'Get-Command' is not recognized...", from its runspace failing
#     to resolve built-in cmdlets during initialization
#
# This used to match the first message and rethrow anything else, which meant
# the second shape went straight through and failed the Pre-Commit check the
# branch ruleset requires. Matching on message text is whack-a-mole for a fault
# whose surface keeps changing, so retry everything instead: a genuine analysis
# problem reproduces on every attempt and still throws once the retries are
# exhausted, which is what the narrow match was really relying on anyway.
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
      # Report what was retried, so a fault that becomes permanent is visible in
      # the log rather than hidden behind a later success.
      if ($attempt -ge $maxAttempts) { throw }
      [Console]::Error.WriteLine(
        "lint-powershell: retrying $file after: $($_.Exception.Message)")
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
