# Tests for hass-vault.ps1, the Windows Home Assistant credential resolver, and
# the Termux suite's counterpart -- see test/hass_vault_test.sh, whose structure
# this mirrors so the two platforms read alike.
#
# `bw` and bw-session-windows.ps1 are stubbed, so no vault is contacted and no
# prompt is raised. Everything else is real: DPAPI, the cache files on disk, the
# split between stdout and stderr, and the exit codes. The resolver runs as a
# child process rather than being dot-sourced, because the whole design turns on
# what reaches which stream -- a credential on stdout is the wrapper's input,
# and an error there would be consumed as one.
#
# WINDOWS-ONLY. The cache is sealed with DPAPI, which has no implementation off
# Windows, so this skips rather than fails elsewhere.
#
#   mise run test:pester [-- -FilterName '*cache*']
#
# The resolver is read straight from home/, not rendered through `chezmoi cat`
# as the Termux suite does: it is a plain file rather than a template, so the
# rendered output would be byte-identical, and reading it directly keeps the
# suite free of the config-and-hosttype dance CI would otherwise need.

BeforeDiscovery {
  $script:IsWindowsHost = $IsWindows
}

Describe 'hass-vault' -Skip:(-not $script:IsWindowsHost) {

  BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $source = Join-Path $root 'home/dot_local/bin/hass-vault.ps1'

    $sandbox = Join-Path ([IO.Path]::GetTempPath()) "hass-vault-test-$PID"
    $bin = Join-Path $sandbox 'bin'
    $state = Join-Path $sandbox 'state'
    New-Item -ItemType Directory -Path $bin, $state -Force | Out-Null

    Copy-Item $source (Join-Path $bin 'hass-vault.ps1')
    $resolver = Join-Path $bin 'hass-vault.ps1'
    $itemsFile = Join-Path $sandbox 'items.json'
    $bwLog = Join-Path $sandbox 'bw.log'
    $cacheDir = Join-Path $state 'hass-vault'
    $script:CachePath = Join-Path $cacheDir 'cache'
    $script:EpochPath = Join-Path $cacheDir 'epoch'

    # `throw`, because that is how the real bw-session-windows.ps1 reports a
    # failure -- a terminating error that propagates into whatever called it,
    # rather than an exit code. A stub that merely exited non-zero would test a
    # path the resolver never takes.
    Set-Content -Path (Join-Path $bin 'bw-session-windows.ps1') -Value @'
if ($env:STUB_VAULT_LOCKED) { throw 'stub: vault locked' }
Write-Output 'c3R1Yi1zZXNzaW9uLWtleQ=='
'@

    # A .cmd because the resolver resolves `bw.cmd` by name. Items come from a
    # file rather than an argument, so JSON quoting never reaches cmd. Each
    # subcommand is logged so a test can assert the vault was refreshed before
    # it was searched, which is invisible from the returned credential alone.
    Set-Content -Path (Join-Path $bin 'bw.cmd') -Value @'
@echo off
if defined STUB_BW_LOG echo %1>>"%STUB_BW_LOG%"
if "%1"=="sync" if defined STUB_SYNC_FAILS exit /b 1
if "%1"=="sync" exit /b 0
if not exist "%STUB_ITEMS_FILE%" (echo []) else (type "%STUB_ITEMS_FILE%")
'@

    # --- fixtures ---------------------------------------------------------

    $script:Uri = 'https://ha.example.test:8123'
    $script:Token = 'stub-token-0123456789'

    # A vault item as `bw list items` returns it. Callers vary one part at a
    # time, so a test names the thing it is actually about.
    function Get-VaultItem {
      param(
        [string]$Uri = $script:Uri,
        [string]$TokenField = 'CLI Token',
        [string]$Token = $script:Token,
        [string]$Name = 'Home Assistant'
      )
      $uris = if ($Uri) { @(@{ uri = $Uri }) } else { @() }
      @{
        name = $Name
        login = @{ uris = $uris }
        # -Depth on the writer, or ConvertTo-Json flattens these to type names.
        fields = @(@{ name = $TokenField; value = $Token })
      }
    }

    function Write-VaultFixture {
      param([object[]]$Items = @())
      Set-Content -LiteralPath $itemsFile -Encoding utf8 `
        -Value (ConvertTo-Json -InputObject @($Items) -Depth 10)
    }

    # --- driver -----------------------------------------------------------

    # ProcessStartInfo rather than Start-Process, because Start-Process joins
    # -ArgumentList into one space-separated string and leaves the quoting to
    # the caller. The resolver's path runs through the system temp directory, so
    # a profile with a space in it -- C:\Users\Firstname Lastname\... -- splits
    # `-File <path>` in two and every test fails at once. ArgumentList here is a
    # collection the runtime escapes per argument, so no path can come apart.
    #
    # Reading both streams before waiting, since a child that fills a redirected
    # pipe blocks until it is drained; waiting first would deadlock on output
    # larger than the buffer.
    function Invoke-Vault {
      param([string[]]$Arguments = @(), [hashtable]$Environment = @{})

      $vars = @{
        LOCALAPPDATA = $state
        STUB_ITEMS_FILE = $itemsFile
        STUB_BW_LOG = $bwLog
        PATH = "$bin$([IO.Path]::PathSeparator)$env:PATH"
      } + $Environment

      # Cleared unless the caller set them, so no test inherits another's.
      foreach ($name in 'HASS_VAULT_ITEM', 'STUB_VAULT_LOCKED', 'STUB_SYNC_FAILS') {
        if (-not $vars.ContainsKey($name)) { $vars[$name] = $null }
      }

      $saved = @{}
      foreach ($name in $vars.Keys) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name)
        [Environment]::SetEnvironmentVariable($name, $vars[$name])
      }
      try {
        $psi = [Diagnostics.ProcessStartInfo]@{
          FileName = 'pwsh'
          RedirectStandardOutput = $true
          RedirectStandardError = $true
          UseShellExecute = $false
        }
        foreach ($argument in @('-NoLogo', '-NoProfile', '-File', $resolver) + $Arguments) {
          $psi.ArgumentList.Add($argument)
        }

        $proc = [Diagnostics.Process]::Start($psi)
        $stdout = $proc.StandardOutput.ReadToEndAsync()
        $stderr = $proc.StandardError.ReadToEndAsync()
        $proc.WaitForExit()
        [pscustomobject]@{
          Out = $stdout.Result
          Err = $stderr.Result
          ExitCode = $proc.ExitCode
        }
      }
      finally {
        foreach ($name in $saved.Keys) {
          [Environment]::SetEnvironmentVariable($name, $saved[$name])
        }
      }
    }

    # Resolves through the stub vault to populate the cache.
    function Initialize-Cache {
      Invoke-Vault -Arguments 'check' | Out-Null
    }

    function Get-BwCallLog {
      (Get-Content -LiteralPath $bwLog -ErrorAction SilentlyContinue) -join ','
    }

    function Clear-BwLog {
      Remove-Item -LiteralPath $bwLog -Force -ErrorAction SilentlyContinue
    }
  }

  # No test inherits another's cache, or another's epoch -- it lives in the same
  # directory, and a generation left over from a preceding `refresh` would
  # silently invalidate the next test's cache before it read it.
  BeforeEach {
    Remove-Item -LiteralPath $cacheDir -Recurse -Force -ErrorAction SilentlyContinue
    Clear-BwLog
    Write-VaultFixture @((Get-VaultItem))
  }

  AfterAll {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
  }

  Context 'resolution' {

    It 'resolves on a miss and caches the result' {
      $result = Invoke-Vault -Arguments 'credential'
      $result.ExitCode | Should -Be 0
      $result.Out | Should -Match ([regex]::Escape($script:Uri))
      $result.Out | Should -Match ([regex]::Escape($script:Token))
      Test-Path $script:CachePath | Should -BeTrue
    }

    It 'returns the server first and the token second' {
      $lines = (Invoke-Vault -Arguments 'credential').Out -split '\r?\n'
      $lines[0] | Should -BeExactly $script:Uri
      $lines[1] | Should -BeExactly $script:Token
    }

    It 'treats credential as the default command, as the wrapper invokes it' {
      (Invoke-Vault).Out | Should -Match ([regex]::Escape($script:Token))
    }

    # One call returns both, so a hass-cli invocation costs one vault round trip
    # rather than two.
    It 'serves a warm cache without reaching the vault' {
      Initialize-Cache
      $result = Invoke-Vault -Arguments 'credential' -Environment @{ STUB_VAULT_LOCKED = '1' }
      $result.ExitCode | Should -Be 0
      $result.Out | Should -Match ([regex]::Escape($script:Token))
    }

    It 'reports the shape through check, never the value' {
      $result = Invoke-Vault -Arguments 'check'
      $result.Out | Should -Match 'credentials resolved'
      $result.Out | Should -Match "token $($script:Token.Length) chars"
      "$($result.Out)$($result.Err)" | Should -Not -Match ([regex]::Escape($script:Token))
    }
  }

  Context 'the binding' {

    It 'does not leave the token readable in the cache file' {
      Initialize-Cache
      (Get-Content -Raw -LiteralPath $script:CachePath) |
        Should -Not -Match ([regex]::Escape($script:Token))
    }

    # The expiry is part of the DPAPI entropy, so editing it breaks the open
    # rather than extending the window.
    It 'refuses an edited expiry rather than honouring it' {
      Initialize-Cache
      $lines = @(Get-Content -LiteralPath $script:CachePath)
      $lines[0] = (Get-Date).ToUniversalTime().AddDays(30).ToString('o')
      Set-Content -LiteralPath $script:CachePath -Value $lines -Encoding ascii

      (Invoke-Vault -Arguments 'check' -Environment @{ STUB_VAULT_LOCKED = '1' }).Out |
        Should -Match 'credentials did not resolve'
    }

    # The check-then-write window the epoch guard alone cannot close: a resolver
    # passes the check, `refresh` advances the epoch, and the resolver publishes
    # afterwards. Sealing under the epoch is what makes that publication
    # harmless -- driven here by writing a cache and then superseding the epoch,
    # which is the exact state such a resolver leaves behind.
    It 'refuses a cache sealed under a superseded epoch' {
      Initialize-Cache
      Set-Content -LiteralPath $script:EpochPath -Value 'superseded-by-a-refresh' -Encoding ascii

      (Invoke-Vault -Arguments 'check' -Environment @{ STUB_VAULT_LOCKED = '1' }).Out |
        Should -Match 'credentials did not resolve'
    }
  }

  Context 'the vault sync' {

    # A rotated token is invisible until an explicit sync: bw serves a local
    # copy that refreshes on nothing else. Syncing only on a miss caught an item
    # newly added and nothing else, and the failure was silent -- check reported
    # a good credential while hass-cli got 401.
    It 'syncs the local copy before searching it' {
      Invoke-Vault -Arguments 'check' | Out-Null
      Get-BwCallLog | Should -Match '^sync,list'
    }

    # The cost belongs on the cold path only.
    It 'does not sync when the cache is warm' {
      Initialize-Cache
      Clear-BwLog
      Invoke-Vault -Arguments 'credential' | Out-Null
      Get-BwCallLog | Should -BeNullOrEmpty
    }

    It 'still resolves from the local copy when the sync fails' {
      $result = Invoke-Vault -Arguments 'check' -Environment @{ STUB_SYNC_FAILS = '1' }
      $result.ExitCode | Should -Be 0
      $result.Out | Should -Match 'credentials resolved'
    }
  }

  Context 'refusals' {

    It 'refuses an ambiguous match rather than guessing' {
      Write-VaultFixture @((Get-VaultItem), (Get-VaultItem -Name 'Home Assistant (old)'))
      $result = Invoke-Vault -Arguments 'check'
      $result.ExitCode | Should -Be 1
      $result.Err | Should -Match 'refusing to guess'
    }

    It 'reports an item with no token field' {
      Write-VaultFixture @((Get-VaultItem -TokenField 'Other'))
      (Invoke-Vault -Arguments 'check').Err | Should -Match "'CLI Token' field"
    }

    It 'reports an item with no URI to use as the server' {
      Write-VaultFixture @((Get-VaultItem -Uri ''))
      (Invoke-Vault -Arguments 'check').Err | Should -Match 'no URI to use as the server'
    }

    It 'reports an item whose token field is empty' {
      Write-VaultFixture @((Get-VaultItem -Token ''))
      (Invoke-Vault -Arguments 'check').Err | Should -Match "empty 'CLI Token' field"
    }

    It 'keeps the vault item renameable through HASS_VAULT_ITEM' {
      Write-VaultFixture @()
      (Invoke-Vault -Arguments 'check' -Environment @{ HASS_VAULT_ITEM = 'Nope' }).Err |
        Should -Match "matching 'Nope'"
    }

    It 'rejects an unknown command' {
      (Invoke-Vault -Arguments 'bogus').ExitCode | Should -Not -Be 0
    }
  }

  Context 'failing loudly' {

    # Where the retired mise [env] path had to fail soft, the wrapper makes this
    # failure hass-cli's alone, so it can say why and exit non-zero.
    #
    # The reason itself is the session script's, not a generic stand-in: it
    # throws, and the resolver reports the thrown message rather than flattening
    # every unlock failure to one string. So these assert that a reason reached
    # stderr, not which one -- pinning the text would be pinning the stub's.
    It 'surfaces a locked vault through check' {
      $result = Invoke-Vault -Arguments 'check' -Environment @{ STUB_VAULT_LOCKED = '1' }
      $result.ExitCode | Should -Be 1
      $result.Out | Should -Match 'credentials did not resolve'
      $result.Err | Should -Match 'hass-vault:'
    }

    # stdout carries the credential, so a diagnostic there would be read as one.
    It 'keeps diagnostics off the stream the wrapper parses' {
      $result = Invoke-Vault -Arguments 'credential' -Environment @{ STUB_VAULT_LOCKED = '1' }
      $result.ExitCode | Should -Be 1
      $result.Out | Should -BeNullOrEmpty
      $result.Err | Should -Match 'hass-vault:'
    }
  }

  Context 'refresh' {

    It 'drops the cached pair and resolves again' {
      Initialize-Cache
      $result = Invoke-Vault -Arguments 'refresh'
      $result.ExitCode | Should -Be 0
      $result.Out | Should -Match 'credentials resolved'
      Test-Path $script:CachePath | Should -BeTrue
    }

    # The epoch moves before the cache is removed. A resolve already in flight
    # captured the old one and re-checks it before sealing, so advancing first
    # makes that write drop; removing first would leave a window in which it
    # still passes the check and restores the stale pair.
    It 'advances the epoch' {
      Initialize-Cache
      $before = Get-Content -Raw -LiteralPath $script:EpochPath -ErrorAction SilentlyContinue
      Invoke-Vault -Arguments 'refresh' | Out-Null
      (Get-Content -Raw -LiteralPath $script:EpochPath) | Should -Not -Be $before
    }

    # A refresh that cannot resolve is a failed refresh: it reports the failure
    # rather than reporting success over a cache it just emptied.
    It 'fails loudly when the vault cannot answer' {
      Initialize-Cache
      $result = Invoke-Vault -Arguments 'refresh' -Environment @{ STUB_VAULT_LOCKED = '1' }
      $result.ExitCode | Should -Be 1
      $result.Out | Should -Match 'credentials did not resolve'
    }
  }

  Context 'status' {

    It 'reports an empty cache without reaching the vault' {
      (Invoke-Vault -Arguments 'status').Out | Should -Match 'no cached credentials'
      Get-BwCallLog | Should -BeNullOrEmpty
    }

    It 'reports a warm cache with its remaining window' {
      Initialize-Cache
      (Invoke-Vault -Arguments 'status').Out | Should -Match 'cached credentials valid for'
    }
  }
}
