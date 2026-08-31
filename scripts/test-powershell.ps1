#!/usr/bin/env pwsh
# Run the Pester suites under test/, mirroring scripts/lint-powershell.ps1: the
# mise task stays a one-liner and the module wrangling lives here. Invoked by
# `mise run test:pester`, which runs every suite under test/.
#
# Suites that cannot apply to the host skip themselves rather than failing, so
# this is safe to run anywhere -- on a non-Windows host the DPAPI-backed
# hass-vault suite reports as skipped and the run still passes.
#
# Filters are declared parameters rather than a raw passthrough to Invoke-Pester.
# Splatting a [string[]] binds its elements positionally, so `-FilterName x`
# arrives as Pester's second and third positional parameters -- Path and
# EnableExit -- and fails on the type rather than filtering anything.
[CmdletBinding()]
param(
  # Wildcard match against the full test name, e.g. '*cache*'.
  [string[]]$FilterName,
  [string[]]$FilterTag
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Join-Path $PSScriptRoot '..'
$suites = Join-Path $root 'test'

# Pester throws when it finds no *.Tests.ps1 rather than reporting an empty run,
# so a repo with none would fail here for having nothing to do. That is a
# legitimate state; say so and stop.
$found = Get-ChildItem -Path $suites -Filter '*.Tests.ps1' -Recurse -File `
  -ErrorAction SilentlyContinue
if (-not $found) {
  Write-Output 'SKIP: no Pester suites under test/'
  exit 0
}

# The repo-local pinned module from provision-psmodules.ps1, as
# lint-powershell.ps1 does. No ambient fallback here, though: Windows ships
# Pester 3 in the box, which cannot parse a v5 suite and fails obscurely rather
# than reporting a missing pin.
#
# Provisioned on demand rather than relied on. mise runs the provisioner from
# the powershell tool's postinstall, which fires only when that tool is
# installed -- so a host that had pwsh before Pester was pinned, or a CI run
# whose mise cache is warm enough that `mise install` reports everything
# present, never gets it. The provisioner is idempotent, so this costs nothing
# once the module is there.
$repoModules = Join-Path $root '.psmodules'
if (-not (Test-Path (Join-Path $repoModules 'Pester'))) {
  & (Join-Path $PSScriptRoot 'provision-psmodules.ps1')
}
if (-not (Test-Path (Join-Path $repoModules 'Pester'))) {
  throw "Pester could not be provisioned into $repoModules"
}
$env:PSModulePath = $repoModules + [IO.Path]::PathSeparator + $env:PSModulePath
Import-Module Pester -MinimumVersion 5.0 -Force

$config = New-PesterConfiguration
$config.Run.Path = $suites
$config.Run.Exit = $true
$config.Output.Verbosity = 'Detailed'
if ($FilterName) { $config.Filter.FullName = $FilterName }
if ($FilterTag) { $config.Filter.Tag = $FilterTag }
Invoke-Pester -Configuration $config
