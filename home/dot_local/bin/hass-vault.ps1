# Resolves the Home Assistant CLI's server and token from the Bitwarden vault,
# for the hass-cli wrapper in ~/.local/bin/wrappers to put in that one process's
# environment.
#
# Both values in one call, because that is one vault round trip rather than two.
# The pair used to be fetched separately, a variable per `exec()`, back when
# mise's `[env]` set them -- the cache below exists because that path re-ran the
# resolver on every command. The wrapper runs it once per hass-cli invocation
# instead, but the cache still earns its place: a lookup costs several seconds,
# roughly four of them Node starting up before the vault is even touched.
#
# One resolver per platform rather than one ported around, and the wrapping
# below is why: it is bound to DPAPI. The Termux counterpart is `hass-vault`,
# which wraps against the Android hardware keystore instead and diverges on the
# points that follow from it. Linux and macOS are simply not built yet -- on
# those hosts hass-cli installs but has no credentials, and no wrapper is
# deployed to supply them.
#
# The at-rest wrapping is DPAPI, matching bw-session-windows.ps1 -- see that
# file for why Windows Hello for Business isn't available here and what DPAPI
# does and does not protect. The same caveat applies: DPAPI binds to the user
# identity, not to presence, so what bounds exposure is the idle window, which
# is kept short and slides on use. The expiry, the item query and the epoch are
# bound as the DPAPI entropy, so editing the expiry in the file makes decryption
# fail rather than extending the window, and a cache filled for one vault item
# is never served for another.
#
# This caches the credential itself rather than a key that unlocks a vault, so
# it is deliberately shorter-lived than the bw session cache beneath it.
#
# `credential` exists to be read by the wrapper, not by a human: it prints the
# token to stdout, so running it to "see if it works" puts a long-lived
# credential into a terminal, a shell history, a log, or an agent transcript.
# Use `check` to diagnose instead -- it resolves the same way and reports the
# outcome without emitting either value. It is the only subcommand that emits
# one, matching Termux, so the rule agents are given is the same on both.
#
# Commands: credential (default) | check | refresh | status
[CmdletBinding()]
param(
  [ValidateSet('credential', 'check', 'refresh', 'status')]
  [string]$Command = 'credential'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue

$script:CachePath = Join-Path $env:LOCALAPPDATA 'hass-vault\cache'
# Bumped by `refresh`. A resolve reads it before touching the vault and again
# before sealing, and declines to seal if it moved -- see Write-Cache.
$script:EpochPath = Join-Path $env:LOCALAPPDATA 'hass-vault\epoch'
$script:IdleWindow = [TimeSpan]::FromHours(4)

# The vault is searched by name rather than opened by a fixed item id, so the
# item stays renameable and this file holds no vault-specific identifier. The
# search is a prefilter only -- bw matches names and URIs loosely -- so the
# result is then narrowed to items actually carrying the token field, and an
# ambiguous result is refused rather than guessed.
$script:ItemQuery = if ($env:HASS_VAULT_ITEM) { $env:HASS_VAULT_ITEM } else { 'Home Assistant' }
$script:TokenField = 'CLI Token'

function Read-Epoch {
  if (-not (Test-Path -LiteralPath $script:EpochPath)) { return '' }
  $raw = Get-Content -LiteralPath $script:EpochPath -Raw -ErrorAction SilentlyContinue
  if ($null -eq $raw) { '' } else { $raw.Trim() }
}

function Write-Diag {
  param([string]$Message)
  [Console]::Error.WriteLine("hass-vault: $Message")
}

# The DPAPI entropy, binding the expiry, the item query and the epoch together.
#
# The expiry so editing it in the file breaks decryption rather than extending
# the window. The query so a cache filled for one vault item is never served for
# another: the read consults the cache before it ever reaches the vault, so
# without it HASS_VAULT_ITEM=Other hands back the previous item's credentials
# for the rest of the idle window, and nothing downstream can catch that. The
# epoch for the refresh race described in Write-Cache.
#
# NUL-separated so no part can be crafted to collide with another, and in the
# same order as the Termux AAD so the two platforms can be read side by side.
function Get-CacheEntropy {
  param([string]$Expiry, [string]$Epoch)
  [Text.Encoding]::UTF8.GetBytes("$Expiry`0$($script:ItemQuery)`0$Epoch")
}

function Write-Cache {
  param([string]$Server, [string]$Token, [string]$Epoch)

  # Ordering in `refresh` stops a resolve that starts after it from sealing a
  # stale pair, but not one already in flight: that resolve can read the vault
  # before the sync and land here after the delete, resurrecting the revoked
  # pair with a fresh window while reset reports success. The epoch is captured
  # before the read and re-checked here, so such a write is dropped instead.
  #
  # A generation check rather than a mutex because the resolve it guards spans
  # a `bw` call: holding a lock across that would let a hung or slow vault
  # block every hass-cli invocation, which is a worse failure than the race.
  # This only discards a cache write -- the caller still gets the pair it
  # resolved, and the next invocation resolves afresh.
  # A fast path, not the guarantee: it skips work and leaves a diagnosable line
  # when a refresh has already landed. What makes the write safe is binding the
  # epoch into the DPAPI entropy below, which a later read will refuse.
  if ((Read-Epoch) -ne $Epoch) {
    Write-Diag 'a refresh landed mid-resolve; not caching this result'
    return
  }
  $expiry = (Get-Date).ToUniversalTime().Add($script:IdleWindow).ToString('o')

  # Checking the epoch before writing narrows the race but cannot close it: the
  # check and the write are separate steps, so a refresh landing between them
  # would still repopulate the cache it just cleared. Binding the epoch into the
  # entropy moves the check to read time, where it is inherently atomic -- a
  # cache sealed under a superseded epoch fails to unprotect and is treated as
  # the miss it is. No lock, and nothing held across the vault call.
  $entropy = Get-CacheEntropy -Expiry $expiry -Epoch $Epoch
  $payload = "$Server`n$Token"
  $blob = [Security.Cryptography.ProtectedData]::Protect(
    [Text.Encoding]::UTF8.GetBytes($payload), $entropy, 'CurrentUser')
  $dir = Split-Path $script:CachePath -Parent
  if (-not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
  $lines = @($expiry, [Convert]::ToBase64String($blob))
  Set-Content -Path $script:CachePath -Value $lines -Encoding ascii
}

function Read-Cache {
  if (-not (Test-Path $script:CachePath)) { return $null }
  $lines = @(Get-Content -Path $script:CachePath -ErrorAction SilentlyContinue)
  if ($lines.Count -lt 2) { return $null }

  $expiry = [datetime]::Parse($lines[0]).ToUniversalTime()
  if ($expiry -le (Get-Date).ToUniversalTime()) { return $null }

  try {
    $entropy = Get-CacheEntropy -Expiry $lines[0] -Epoch (Read-Epoch)
    $plain = [Security.Cryptography.ProtectedData]::Unprotect(
      [Convert]::FromBase64String($lines[1]), $entropy, 'CurrentUser')
    $parts = [Text.Encoding]::UTF8.GetString($plain) -split "`n", 2
    if ($parts.Count -lt 2) { return $null }
    [pscustomobject]@{ Server = $parts[0]; Token = $parts[1] }
  }
  catch {
    # Wrong user, another machine, an edited expiry, a cache sealed for a
    # different item query, or one superseded by a refresh. Indistinguishable
    # and all equally unusable, so treat as a miss.
    $null
  }
}

# --nointeraction so a session the vault has since invalidated errors out
# instead of prompting into the stdout the caller parses; --raw likewise keeps
# bw's descriptive chatter out of that stream. The session travels by
# environment rather than --session, which would put the key in the process
# command line, and is cleared again however the call ends.
function Invoke-Bw {
  param([string]$Bw, [string]$Session, [string[]]$Arguments)
  try {
    $env:BW_SESSION = $Session
    & $Bw @Arguments --nointeraction --raw 2>$null
  }
  finally {
    Remove-Item Env:BW_SESSION -ErrorAction SilentlyContinue
  }
}

function Find-VaultItem {
  param([string]$Bw, [string]$Session)
  $search = @('list', 'items', '--search', $script:ItemQuery)
  $json = Invoke-Bw -Bw $Bw -Session $Session -Arguments $search
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json)) { return @() }

  @($json | ConvertFrom-Json | Where-Object {
      $_.fields -and ($_.fields.name -contains $script:TokenField)
    })
}

function Get-VaultCredential {
  $epoch = Read-Epoch
  $cached = Read-Cache
  if ($cached) {
    # Slide the window on use, matching the bw session cache's idle semantics.
    Write-Cache -Server $cached.Server -Token $cached.Token -Epoch $epoch
    return $cached
  }

  $bw = (Get-Command bw.cmd -ErrorAction SilentlyContinue).Source
  if (-not $bw) { throw 'bw not found on PATH' }

  $sessionScript = Join-Path $PSScriptRoot 'bw-session-windows.ps1'
  $session = (& $sessionScript get 2>$null | Out-String).Trim()
  if (-not $session) { throw 'could not unlock the vault' }

  # Sync before searching, not only when the item is missing. The CLI serves a
  # local copy of the vault and refreshes it only on an explicit sync -- not on
  # unlock, and not on list -- so a *rotated* token is invisible here until
  # something else happens to sync. That failure is silent and misleading:
  # hass-cli gets 401 while `check` reports a perfectly good credential, because
  # the stale token is still a valid, unexpired JWT.
  #
  # Syncing only on a miss caught an item that was newly added and nothing else.
  # This costs a network round trip, but only on the cold path -- a cache lapse
  # or a reset -- which already costs a vault unlock and possibly a prompt.
  #
  # Failure is ignored rather than fatal, so an offline resolve still serves the
  # local copy instead of refusing outright. The try/catch is what makes that
  # true rather than incidental: $ErrorActionPreference is Stop, so a non-zero
  # native exit becomes terminating wherever
  # $PSNativeCommandUseErrorActionPreference is $true. It defaults to $false on
  # the pinned PowerShell, which is exactly the kind of thing not to depend on.
  try {
    Invoke-Bw -Bw $bw -Session $session -Arguments @('sync') | Out-Null
  }
  catch {
    Write-Diag "vault sync failed, using the local copy: $($_.Exception.Message)"
  }

  $items = Find-VaultItem -Bw $bw -Session $session

  # Ambiguity is refused rather than guessed: picking one of several would hand
  # over a credential the user never chose.
  if ($items.Count -gt 1) {
    throw "$($items.Count) vault items match '$($script:ItemQuery)'; refusing to guess"
  }
  if ($items.Count -eq 0) {
    throw ("no vault item matching '$($script:ItemQuery)' has a " +
      "'$($script:TokenField)' field; set HASS_VAULT_ITEM to search another name")
  }

  $item = $items[0]
  $server = $item.login.uris | Select-Object -First 1 -ExpandProperty uri
  $field = $item.fields | Where-Object { $_.name -eq $script:TokenField } | Select-Object -First 1

  if (-not $server) {
    throw "vault item '$($item.name)' has no URI to use as the server"
  }
  if (-not $field.value) {
    throw "vault item '$($item.name)' has an empty '$($script:TokenField)' field"
  }

  Write-Cache -Server $server -Token $field.value -Epoch $epoch
  [pscustomobject]@{ Server = $server; Token = $field.value }
}

switch ($Command) {
  'refresh' {
    # Drops the sealed cache so the next resolve fetches afresh. That is the
    # answer to a rotated token: the resolve path syncs bw's local copy before
    # searching, but never reaches it while a valid cache holds, so the stale
    # pair is served until something clears it.
    #
    # No sync here. This used to do one, back when the resolve path synced only
    # on a miss and a rotated item therefore stayed invisible; now that every
    # cold resolve syncs first, doing it again would be a second round trip for
    # a value the next resolve refreshes anyway.
    #
    # The epoch moves FIRST, before the cache is removed. A resolve already in
    # flight captured the old epoch and re-checks it before sealing, so
    # advancing it here makes that write drop. Removing the cache first would
    # leave a window between the delete and the bump in which such a write
    # still passes the check -- restoring the stale pair, with a fresh window,
    # after this command reported success.
    $dir = Split-Path $script:EpochPath -Parent
    if (-not (Test-Path -LiteralPath $dir)) {
      $null = New-Item -ItemType Directory -Path $dir -Force
    }
    Set-Content -LiteralPath $script:EpochPath -Value ([guid]::NewGuid().ToString()) -Encoding ascii

    # A cache that survives is a failed refresh, not a partial one, so this
    # exits non-zero and says so rather than reporting success and sending the
    # next resolve at the same stale copy.
    try {
      if (Test-Path -LiteralPath $script:CachePath) {
        Remove-Item -LiteralPath $script:CachePath -Force -ErrorAction Stop
      }
    }
    catch {
      Write-Diag "could not clear the cache: $($_.Exception.Message)"
      exit 1
    }

    # Resolve on the spot rather than leaving it to the next hass-cli call, so
    # this reports whether the new credential actually resolves and matches what
    # `hass-vault refresh` does on Termux. Same non-secret shape as `check`.
    try {
      $creds = Get-VaultCredential
    }
    catch {
      Write-Diag $_.Exception.Message
      Write-Output 'credentials did not resolve'
      exit 1
    }
    "credentials resolved (server set, token $($creds.Token.Length) chars)"
    break
  }

  'check' {
    # Reports shape, never values: the whole point is that a failure can be
    # diagnosed without printing a secret somewhere it will persist.
    try {
      $creds = Get-VaultCredential
    }
    catch {
      Write-Diag $_.Exception.Message
      Write-Output 'credentials did not resolve'
      exit 1
    }
    "credentials resolved (server set, token $($creds.Token.Length) chars)"
    break
  }
  'status' {
    $cached = Read-Cache
    if ($cached) {
      $expiry = [datetime]::Parse((Get-Content $script:CachePath)[0]).ToUniversalTime()
      "cached credentials valid for {0:hh\:mm\:ss}" -f ($expiry - (Get-Date).ToUniversalTime())
    }
    else { 'no cached credentials' }
    break
  }
  default {
    # Server first, then token, one per line -- the order the wrapper reads
    # them in. Diagnostics go to stderr and the exit code carries the failure,
    # so a bad lookup can never put an error message on stdout where the
    # wrapper would read it as a credential.
    try {
      $creds = Get-VaultCredential
    }
    catch {
      Write-Diag $_.Exception.Message
      exit 1
    }
    Write-Output $creds.Server
    Write-Output $creds.Token
  }
}

# Explicit, so the caller's $LASTEXITCODE reflects this run rather than whatever
# native command preceded it -- falling off the end of a script leaves it
# untouched, and the failure path above sets it.
exit 0
