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
    # The default instance's file. Each instance caches separately, so the name
    # carries the id -- tests that reach for a specific one build their own.
    $script:CachePath = Join-Path $cacheDir 'cache-home'
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
        [string]$Name = 'Home Assistant',
        [string]$Id = 'home',
        [switch]$OmitId
      )
      $uris = if ($Uri) { @(@{ uri = $Uri }) } else { @() }
      $fields = @()
      if (-not $OmitId) { $fields += @{ name = 'CLI ID'; value = $Id } }
      $fields += @{ name = $TokenField; value = $Token }
      @{
        name = $Name
        login = @{ uris = $uris }
        # -Depth on the writer, or ConvertTo-Json flattens these to type names.
        fields = $fields
      }
    }

    # A second instance, as a relative's would look: same search term, its own
    # URI and token, told apart only by the id field.
    $script:OtherUri = 'https://other.example.test:8123'
    $script:OtherToken = 'stub-token-other-9876'

    function Write-TwoInstanceFixture {
      Write-VaultFixture @(
        (Get-VaultItem),
        (Get-VaultItem -Uri $script:OtherUri -Token $script:OtherToken `
          -Name 'Home Assistant (Other)' -Id 'other')
      )
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

      # Cleared unless the caller set them, so no test inherits another's -- nor
      # the shell's, which for HASS_VAULT_INSTANCE is a realistic thing to have
      # exported, since setting it is what the variable is for.
      foreach ($name in 'HASS_VAULT_INSTANCE', 'HASS_VAULT_ITEM',
        'STUB_VAULT_LOCKED', 'STUB_SYNC_FAILS') {
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

    # The read consults the cache before it ever reaches the vault, so without
    # the search term bound into the entropy a cache filled for one item is
    # handed over for another -- silently talking to the wrong instance for the
    # rest of the idle window rather than failing.
    It 'does not serve a cache filled under one item query for another' {
      Initialize-Cache
      Write-VaultFixture @()
      $result = Invoke-Vault -Arguments 'credential' `
        -Environment @{ HASS_VAULT_ITEM = 'Something Else' }
      $result.Out | Should -Not -Match ([regex]::Escape($script:Token))
      $result.Err | Should -Match "matching 'Something Else'"
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

  Context 'instances' {

    # The point of the id field: both items match the same search term, so the
    # name cannot be what tells them apart.
    It 'selects the instance by the id field' {
      Write-TwoInstanceFixture
      (Invoke-Vault -Arguments 'credential').Out |
        Should -Match ([regex]::Escape($script:Uri))

      $other = Invoke-Vault -Arguments 'credential' `
        -Environment @{ HASS_VAULT_INSTANCE = 'other' }
      $other.Out | Should -Match ([regex]::Escape($script:OtherUri))
      $other.Out | Should -Match ([regex]::Escape($script:OtherToken))
    }

    # Typed into a vault UI by hand, where a stray space or capital is a typo
    # rather than a different instance.
    It 'matches the id trimmed and case-insensitively' {
      Write-VaultFixture @((Get-VaultItem -Id '  Other  ' -Uri $script:OtherUri))
      (Invoke-Vault -Arguments 'credential' `
        -Environment @{ HASS_VAULT_INSTANCE = 'OTHER' }).Out |
        Should -Match ([regex]::Escape($script:OtherUri))
    }

    # The regression the per-instance cache exists for: one shared slot hands
    # the first instance's credentials to the second, silently. The home item
    # stays in the vault, so this is the real shape -- a warm home cache and a
    # request for an instance the vault does not carry.
    It 'never serves one instance cache for another' {
      Initialize-Cache
      $result = Invoke-Vault -Arguments 'credential' `
        -Environment @{ HASS_VAULT_INSTANCE = 'other' }
      $result.Out | Should -Not -Match ([regex]::Escape($script:Token))
      $result.Err | Should -Match "'CLI ID' = 'other'"
    }

    # Separate files rather than one slot the instances evict each other from: a
    # vault lookup is seconds of bw starting Node, so a shared slot would pay it
    # on every switch.
    It 'keeps a separate cache per instance' {
      Write-TwoInstanceFixture
      Initialize-Cache
      Invoke-Vault -Arguments 'check' -Environment @{ HASS_VAULT_INSTANCE = 'other' } | Out-Null

      Write-VaultFixture @()
      (Invoke-Vault -Arguments 'credential').Out |
        Should -Match ([regex]::Escape($script:Token))
      (Invoke-Vault -Arguments 'credential' `
        -Environment @{ HASS_VAULT_INSTANCE = 'other' }).Out |
        Should -Match ([regex]::Escape($script:OtherToken))
    }

    It 'names the instance it resolved' {
      Write-TwoInstanceFixture
      (Invoke-Vault -Arguments 'check' `
        -Environment @{ HASS_VAULT_INSTANCE = 'other' }).Out |
        Should -Match "resolved for 'other'"
    }

    It 'reports the current instance and every other cached one' {
      Write-TwoInstanceFixture
      Initialize-Cache
      Invoke-Vault -Arguments 'check' -Environment @{ HASS_VAULT_INSTANCE = 'other' } | Out-Null

      $status = (Invoke-Vault -Arguments 'status').Out
      $status | Should -Match 'home \(current\): cached credentials valid for'
      $status | Should -Match 'other: cached credentials valid for'
    }

    # The epoch is shared and sealed into every cache, so refreshing one
    # instance invalidates the rest even though their files survive. Without
    # that, the instance you did not name would go on serving a pair sealed
    # under a superseded generation.
    It 'invalidates the other instances when one is refreshed' {
      Write-TwoInstanceFixture
      Invoke-Vault -Arguments 'check' -Environment @{ HASS_VAULT_INSTANCE = 'other' } | Out-Null
      Initialize-Cache
      (Invoke-Vault -Arguments 'refresh').ExitCode | Should -Be 0

      $result = Invoke-Vault -Arguments 'check' -Environment @{
        HASS_VAULT_INSTANCE = 'other'; STUB_VAULT_LOCKED = '1'
      }
      $result.ExitCode | Should -Be 1
      $result.Out | Should -Match 'credentials did not resolve'
    }

    It 'names the available ids when the requested one is absent' {
      Write-TwoInstanceFixture
      $result = Invoke-Vault -Arguments 'check' -Environment @{ HASS_VAULT_INSTANCE = 'nope' }
      $result.ExitCode | Should -Be 1
      $result.Err | Should -Match "'CLI ID' = 'nope'"
      $result.Err | Should -Match 'available: home, other'
    }

    It 'reports an item that carries no id field at all' {
      Write-VaultFixture @((Get-VaultItem -OmitId))
      (Invoke-Vault -Arguments 'check').Err | Should -Match 'available: none'
    }

    # An id names the cache file, so one that is not a plain label could
    # traverse out of the cache directory or land on a dotfile.
    It 'refuses an instance id that is not a plain label' -ForEach @(
      @{ Id = '../escape' }, @{ Id = '.hidden' }, @{ Id = 'has space' }
    ) {
      $result = Invoke-Vault -Arguments 'status' -Environment @{ HASS_VAULT_INSTANCE = $Id }
      $result.ExitCode | Should -Be 1
      $result.Err | Should -Match 'invalid HASS_VAULT_INSTANCE'
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

    # Two items claiming the same instance is a vault mistake, not a second
    # instance, and the one case selection cannot resolve: they are equally
    # valid answers, so picking either hands over a credential nobody chose.
    It 'refuses two items claiming the same instance rather than guessing' {
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

    # A long-lived token over cleartext is worth failing over. Home Assistant is
    # commonly reached at http:// on a LAN, so this is a policy rather than a
    # universal truth -- but it is the right one where the URI comes from a
    # vault item expected to be https, and it is what the Termux resolver has
    # always done.
    It 'refuses a non-https server URI rather than sending the token in clear' {
      Write-VaultFixture @((Get-VaultItem -Uri 'http://plain.test:8123'))
      $result = Invoke-Vault -Arguments 'credential'
      $result.ExitCode | Should -Be 1
      $result.Err | Should -Match 'non-https URI'
      $result.Out | Should -Not -Match ([regex]::Escape($script:Token))
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
