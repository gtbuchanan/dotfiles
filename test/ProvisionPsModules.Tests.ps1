# Tests for scripts/provision-psmodules.ps1, which saves the pinned PowerShell
# Gallery modules into a repo-local .psmodules.
#
# The gallery intermittently answers 404 for packages it does publish, so these
# cases pin how the provisioner rides that out: retry a failed save, and never
# leave behind a partial module folder that its idempotency check would mistake
# for a finished one.
#
# The script resolves its manifest and destination from $PSScriptRoot, so each
# case runs a copy of it inside a sandboxed repo layout rather than the real one.
# Save-PSResource and Start-Sleep are mocked: the gallery is the thing being
# simulated, and the backoff would only slow the suite down.
#
#   mise run test:pester [-- -FilterName '*provision*']

Describe 'provision psmodules' {

  BeforeAll {
    $script:source = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/provision-psmodules.ps1'
  }

  BeforeEach {
    $script:sandbox = Join-Path ([IO.Path]::GetTempPath()) `
      "provision-psmodules-test-$PID-$(New-Guid)"
    $scripts = Join-Path $script:sandbox 'scripts'
    New-Item -ItemType Directory -Path $scripts -Force | Out-Null
    Copy-Item -LiteralPath $script:source -Destination $scripts
    $manifest = Join-Path $script:sandbox 'powershell-modules.psd1'
    "@{ Fake = '1.2.3' }" | Set-Content -LiteralPath $manifest

    $script:provision = Join-Path $scripts 'provision-psmodules.ps1'
    $script:installed = Join-Path $script:sandbox '.psmodules/Fake/1.2.3'

    # A gallery that fails the first $gallery.Failures saves, each after leaving
    # a partial module folder behind, as an interrupted download can.
    #
    # A hashtable rather than $script: counters: the mock runs inside the
    # provisioner, where $script: is that script's scope, not this file's.
    $gallery = @{ Failures = 0; Saves = 0 }
    Mock Start-Sleep {}
    Mock Save-PSResource {
      $gallery.Saves++
      $folder = Join-Path $Path "$Name/1.2.3"
      # A retry must start clean. Reusing the last attempt's folder would let a
      # module that never finished saving pass for one that did.
      if ($gallery.Saves -gt 1) { $folder | Should -Not -Exist }
      New-Item -ItemType Directory -Path $folder -Force | Out-Null
      if ($gallery.Saves -le $gallery.Failures) {
        throw "Response status code does not indicate success: 404 (Not Found)."
      }
      'module' | Set-Content -LiteralPath (Join-Path $folder 'Fake.psd1')
    }
  }

  AfterEach {
    Remove-Item $script:sandbox -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'saves a module on the first attempt when the gallery answers' {
    & $script:provision 2>$null

    $gallery.Saves | Should -Be 1
    Join-Path $script:installed 'Fake.psd1' | Should -Exist
  }

  It 'retries a save the gallery fails transiently' {
    $gallery.Failures = 2

    & $script:provision 2>$null

    $gallery.Saves | Should -Be 3
    Join-Path $script:installed 'Fake.psd1' | Should -Exist
  }

  It 'gives up after the last attempt and reports the gallery error' {
    $gallery.Failures = 100

    { & $script:provision 2>$null } | Should -Throw '*404*'
    $gallery.Saves | Should -Be 3
  }

  It 'removes the partial module folder when every attempt fails' {
    # Left in place, the next run's idempotency check would see the version
    # folder and skip a module that was never saved.
    $gallery.Failures = 100

    { & $script:provision 2>$null } | Should -Throw
    $script:installed | Should -Not -Exist
  }

  It 'stops rather than retrying when the partial folder cannot be removed' {
    # A folder that survives cleanup -- a locked file, a permissions fault --
    # is the stale state the cleanup exists to prevent, so it must fail loudly.
    # Write-Error rather than throw: Remove-Item reports these non-terminating.
    $gallery.Failures = 100
    Mock Remove-Item { Write-Error 'Access to the path is denied.' } `
      -ParameterFilter { $LiteralPath -like '*.psmodules*' }

    { & $script:provision 2>$null } | Should -Throw '*denied*'
    $gallery.Saves | Should -Be 1
  }
}
