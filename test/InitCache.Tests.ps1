# Tests for profile.d/05-init-cache.ps1, which caches the shell-init scripts
# emitted by mise, starship, wt and delta so each shell reads a file instead of
# spawning the tool.
#
# The part is dot-sourced rather than run as a child process: it only defines
# functions and has no side effects, so they can be exercised directly. That is
# the opposite of test/HassVault.Tests.ps1, which spawns its subject because the
# whole point there is which stream a value reaches.
#
# Every case drives a real cache directory under the temp sandbox and a real
# stand-in "binary" file, because the cache key is derived from the binary's
# identity on disk -- stubbing that away would leave the invalidation logic,
# which is the only interesting part, untested.
#
#   mise run test:pester [-- -FilterName '*init cache*']

Describe 'init cache' {

  BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    . (Join-Path $root 'home/dot_config/powershell/profile.d/05-init-cache.ps1')
  }

  BeforeEach {
    $script:sandbox = Join-Path ([IO.Path]::GetTempPath()) "init-cache-test-$PID-$(New-Guid)"
    $script:cacheDir = Join-Path $script:sandbox 'cache'
    New-Item -ItemType Directory -Path $script:sandbox, $script:cacheDir -Force | Out-Null

    # Stand-in for a tool binary. Only its path, size and mtime matter.
    $script:binary = Join-Path $script:sandbox 'tool.exe'
    'binary-v1' | Out-File -LiteralPath $script:binary -Encoding utf8 -NoNewline

    # Generator that records how often it ran, so a cache hit is observable as
    # the absence of a call rather than merely equal output.
    $script:calls = 0
    $script:payload = "line one`nline two`n`nline four"
    $script:generate = { $script:calls++; $script:payload }

    $script:call = @{
      BinaryPath = $script:binary
      CacheDirectory = $script:cacheDir
      Generate = $script:generate
      Name = 'tool'
    }
  }

  AfterEach {
    Remove-Item $script:sandbox -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'returns the generated script on a cache miss' {
    Get-CachedInitScript @script:call | Should -BeExactly $script:payload
    $script:calls | Should -Be 1
  }

  It 'writes a cache file on a miss' {
    Get-CachedInitScript @script:call | Out-Null
    Join-Path $script:cacheDir 'tool' | Should -Exist
  }

  It 'serves a second call from cache without running the generator' {
    Get-CachedInitScript @script:call | Out-Null
    Get-CachedInitScript @script:call | Should -BeExactly $script:payload
    $script:calls | Should -Be 1
  }

  It 'round-trips a payload with blank and trailing lines exactly' {
    # The payload is a script that gets Invoke-Expression'd, so a dropped blank
    # line or an added trailing newline is a correctness bug, not cosmetics.
    $script:payload = "first`n`n`nlast`n"
    Get-CachedInitScript @script:call | Out-Null
    Get-CachedInitScript @script:call | Should -BeExactly $script:payload
  }

  It 'regenerates when the binary is modified' {
    Get-CachedInitScript @script:call | Out-Null

    # Same size, later mtime: catches an in-place upgrade that length alone misses.
    $later = (Get-Date).ToUniversalTime().AddMinutes(5)
    (Get-Item -LiteralPath $script:binary).LastWriteTimeUtc = $later

    Get-CachedInitScript @script:call | Out-Null
    $script:calls | Should -Be 2
  }

  It 'regenerates when the binary changes size' {
    Get-CachedInitScript @script:call | Out-Null

    $stamp = (Get-Item -LiteralPath $script:binary).LastWriteTimeUtc
    'binary-v2-which-is-longer' | Out-File -LiteralPath $script:binary -Encoding utf8 -NoNewline
    # Pin mtime back so size is the only thing that changed.
    (Get-Item -LiteralPath $script:binary).LastWriteTimeUtc = $stamp

    Get-CachedInitScript @script:call | Out-Null
    $script:calls | Should -Be 2
  }

  It 'regenerates when the binary behind a symlink is replaced' {
    # winget publishes mise as a symlink under Links\, whose own length is 0
    # and whose mtime tracks the link rather than the binary. Keyed on the link,
    # an upgrade would leave the cache pinned to the old init script forever.
    $target = Join-Path $script:sandbox 'real-tool.exe'
    'v1' | Out-File -LiteralPath $target -Encoding utf8 -NoNewline
    $link = Join-Path $script:sandbox 'linked-tool.exe'
    New-Item -ItemType SymbolicLink -Path $link -Target $target | Out-Null

    $linked = $script:call.Clone()
    $linked.BinaryPath = $link

    Get-CachedInitScript @linked | Out-Null
    'v2-which-is-longer' | Out-File -LiteralPath $target -Encoding utf8 -NoNewline

    Get-CachedInitScript @linked | Out-Null
    $script:calls | Should -Be 2
  }

  It 'regenerates when the cache file holds a different key' {
    $cacheFile = Join-Path $script:cacheDir 'tool'
    Set-Content -LiteralPath $cacheFile -Value "wrong-key`nstale payload" -NoNewline

    Get-CachedInitScript @script:call | Should -BeExactly $script:payload
    $script:calls | Should -Be 1
  }

  It 'keeps separate entries per name' {
    Get-CachedInitScript @script:call -Name 'alpha' | Out-Null
    Get-CachedInitScript @script:call -Name 'beta' | Out-Null

    $script:calls | Should -Be 2
    Join-Path $script:cacheDir 'alpha' | Should -Exist
    Join-Path $script:cacheDir 'beta' | Should -Exist
  }

  It 'creates the cache directory when it does not exist' {
    $fresh = Join-Path $script:sandbox 'not-yet'
    Get-CachedInitScript @script:call -CacheDirectory $fresh | Should -BeExactly $script:payload
    Join-Path $fresh 'tool' | Should -Exist
  }

  It 'still returns the script when the cache cannot be written' {
    # Fail open: a broken cache must never cost the caller its init script.
    $blocked = Join-Path $script:sandbox 'blocked'
    'not a directory' | Out-File -LiteralPath $blocked -Encoding utf8

    Get-CachedInitScript @script:call -CacheDirectory $blocked |
      Should -BeExactly $script:payload
    $script:calls | Should -Be 1
  }

  It 'regenerates rather than throwing when the binary is missing' {
    Remove-Item -LiteralPath $script:binary -Force

    Get-CachedInitScript @script:call | Should -BeExactly $script:payload
    $script:calls | Should -Be 1
  }

  It 'defaults the cache directory to a per-user location' {
    $expectedRoot = if ($IsWindows) {
      $env:LOCALAPPDATA
    }
    else {
      if ($env:XDG_CACHE_HOME) { $env:XDG_CACHE_HOME } else { Join-Path $HOME '.cache' }
    }

    Get-InitCacheDirectory | Should -BeLike "$expectedRoot*"
  }
}
