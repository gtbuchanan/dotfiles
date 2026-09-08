# Tests for the mise activation in profile.d/15-mise.ps1, specifically which
# shells may put its init script in the cache from 05-init-cache.ps1.
#
# `mise activate` is a static script only in a shell mise has not already
# activated. In one it has -- any nested shell, which inherits MISE_SHELL --
# mise prepends `hook-env` output, and that output hard-codes the PATH of the
# session generating it. Cached, one nested shell's PATH is then replayed into
# every later shell on the host.
#
# mise is stubbed, so nothing is activated and no real PATH is touched; the
# cache directory and its files are real, since which entry gets written is the
# whole question. The part runs as a child process rather than being
# dot-sourced, because what is under test is what a fresh shell does with the
# environment it inherits.
#
#   mise run test:pester [-- -FilterName '*mise activation*']

Describe 'mise activation' {

  BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent

    # Dot-sources the cache part and then the mise part, exactly as the profile
    # does. Nothing is asserted from in here: the observable results are the
    # stub's log and the cache directory, both of which outlive the child.
    $script:probeSource = @'
param([string] $Root)
. (Join-Path $Root 'home/dot_config/powershell/profile.d/05-init-cache.ps1')
. (Join-Path $Root 'home/dot_config/powershell/profile.d/15-mise.ps1')
'@
  }

  BeforeEach {
    $script:sandbox = Join-Path ([IO.Path]::GetTempPath()) "mise-activate-test-$PID-$(New-Guid)"
    $bin = Join-Path $script:sandbox 'bin'
    $script:cacheRoot = Join-Path $script:sandbox 'cache'
    New-Item -ItemType Directory -Path $bin, $script:cacheRoot -Force | Out-Null

    $script:probe = Join-Path $script:sandbox 'probe.ps1'
    Set-Content -LiteralPath $script:probe -Value $script:probeSource -Encoding utf8

    $script:stubLog = Join-Path $script:sandbox 'mise.log'
    # Where Get-InitCacheDirectory lands once LOCALAPPDATA / XDG_CACHE_HOME
    # point at the sandbox.
    $script:entry = Join-Path $script:cacheRoot 'powershell/init-cache/mise'

    # Emits a comment: the part Invoke-Expression's whatever comes back, so the
    # payload has to be valid PowerShell, and a comment activates nothing. Each
    # call is logged, which is how a cache hit shows up as an absent spawn
    # rather than merely as equal output.
    if ($IsWindows) {
      Set-Content -LiteralPath (Join-Path $bin 'mise.cmd') -Encoding ascii -Value @'
@echo off
echo call>>"%MISE_STUB_LOG%"
echo # stub mise init
'@
    }
    else {
      $stub = Join-Path $bin 'mise'
      Set-Content -LiteralPath $stub -Encoding ascii -Value @'
#!/usr/bin/env bash
echo call >>"$MISE_STUB_LOG"
echo '# stub mise init'
'@
      & chmod +x $stub
    }

    # MISE_SHELL is cleared unless a case sets it, because the session running
    # Pester plausibly has it exported -- an activated shell is where anyone
    # would be working -- and inheriting that would silently invert every case.
    function script:Invoke-Profile ([switch] $Activated) {
      $vars = @{
        LOCALAPPDATA = $script:cacheRoot
        MISE_SHELL = if ($Activated) { 'pwsh' } else { $null }
        MISE_STUB_LOG = $script:stubLog
        PATH = "$bin$([IO.Path]::PathSeparator)$env:PATH"
        XDG_CACHE_HOME = $script:cacheRoot
      }

      $saved = @{}
      foreach ($name in $vars.Keys) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name)
        [Environment]::SetEnvironmentVariable($name, $vars[$name])
      }
      try {
        & pwsh -NoLogo -NoProfile -File $script:probe -Root $script:root | Out-Null
      }
      finally {
        foreach ($name in $saved.Keys) {
          [Environment]::SetEnvironmentVariable($name, $saved[$name])
        }
      }
    }

    function script:Get-StubCallCount {
      if (-not (Test-Path -LiteralPath $script:stubLog)) { return 0 }
      @(Get-Content -LiteralPath $script:stubLog).Count
    }
  }

  AfterEach {
    Remove-Item $script:sandbox -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'caches the init script for a shell mise has not activated' {
    Invoke-Profile
    Invoke-Profile

    Get-StubCallCount | Should -Be 1
    $script:entry | Should -Exist
  }

  It 'writes no cache entry from a shell mise has already activated' {
    Invoke-Profile -Activated

    $script:entry | Should -Not -Exist
  }

  It 'runs mise rather than reading the cache when already activated' {
    Invoke-Profile
    Invoke-Profile -Activated

    Get-StubCallCount | Should -Be 2
  }
}
