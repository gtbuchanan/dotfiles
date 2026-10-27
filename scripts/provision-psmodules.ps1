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
# is cheap. Transient gallery failures are retried with backoff.
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

  # PSResourceGet rather than PowerShellGet's Save-Module, which cannot run
  # under globalization-invariant mode -- it resolves an en-us culture and
  # fails ("en-us is an invalid culture identifier"). Termux runs pwsh that way
  # by necessity, since no ICU its runtime accepts is packaged there (see
  # dot_config/mise/conf.d/termux.toml), so Save-Module makes .psmodules
  # unprovisionable on that host and takes the psscriptanalyzer hk step with
  # it. Both write the same $dest/<name>/<version> layout, so the idempotency
  # check above and PSModulePath resolution are unaffected.
  #
  # The version is a bracketed NuGet range, which is how PSResourceGet spells
  # "exactly this one" -- a bare version is a minimum.
  #
  # Retried because the gallery intermittently answers 404 for packages it does
  # publish, and a single miss fails every CI leg that provisions. A failed
  # attempt's version folder is removed before the next, and for good after the
  # last: left behind, it satisfies the idempotency check above and the next run
  # skips a module that was never saved. For the same reason a folder that
  # cannot be removed stops the run instead of being retried over.
  $partial = Join-Path $dest "$name/$version"
  $attempts = 3
  for ($attempt = 1; ; $attempt++) {
    try {
      Save-PSResource -Name $name -Version "[$version]" -Repository PSGallery `
        -TrustRepository -Path $dest
      break
    }
    catch {
      if (Test-Path -LiteralPath $partial) {
        Remove-Item -LiteralPath $partial -Recurse -Force -ErrorAction Stop
      }
      if ($attempt -ge $attempts) { throw }
      $delay = [Math]::Pow(2, $attempt)
      [Console]::Error.WriteLine(
        "Attempt $attempt of $attempts failed: $($_.Exception.Message) Retrying in ${delay}s")
      Start-Sleep -Seconds $delay
    }
  }
}
