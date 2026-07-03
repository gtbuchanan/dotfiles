#!/usr/bin/env pwsh
# Provision pinned PowerShell Gallery modules into a repo-local, gitignored
# .psmodules so PowerShell-backed hk steps (e.g. psscriptanalyzer) are
# reproducible across dev machines and CI. mise has no PowerShell Gallery
# backend (and none is tracked upstream), so this bootstrap is the durable way
# to pin PS modules alongside the aqua-managed pwsh in mise.toml.
#
# Generic and data-driven: the module -> version map lives in
# powershell-modules.psd1 at the repo root. Idempotent -- a module already
# present at its pinned version is skipped, so re-running the postinstall hook
# is cheap.
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Join-Path $PSScriptRoot '..'
$manifest = Join-Path $root 'powershell-modules.psd1'
$dest = Join-Path $root '.psmodules'

$modules = Import-PowerShellDataFile -Path $manifest
if ($modules.Count -eq 0) { exit 0 }

New-Item -ItemType Directory -Force -Path $dest | Out-Null

foreach ($name in $modules.Keys) {
  $version = $modules[$name]
  if (Test-Path (Join-Path $dest "$name/$version")) { continue }

  [Console]::Error.WriteLine("Provisioning $name $version into .psmodules")
  Save-Module -Name $name -RequiredVersion $version -Repository PSGallery -Path $dest
}
