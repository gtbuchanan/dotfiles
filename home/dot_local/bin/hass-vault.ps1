# Resolves one Home Assistant CLI credential from the Bitwarden vault and prints
# it, for the `[env]` entries in mise's home-assistant.toml fragment to capture.
#
# One value per call because mise `[env]` templating sets a single variable per
# `exec()`, so HASS_SERVER and HASS_TOKEN are two separate invocations. A vault
# lookup costs several seconds -- roughly four of which are Node starting up
# before the vault is even touched -- and mise's computed-env cache does not
# engage on the shims-only path that non-interactive callers take, so an
# uncached resolver would pay that on every command. Hence the cache below: the
# first call fetches both values and wraps them, the second reads them back.
#
# Windows-only so far, and the wrapping below is why: it is bound to DPAPI, so
# each platform needs its own resolver rather than a port of this one. The
# others are simply not built yet -- on those hosts hass-cli installs but has no
# credentials, and the mise fragment that sets them is not deployed.
#
# The at-rest wrapping is DPAPI, matching bw-session-windows.ps1 -- see that
# file for why Windows Hello for Business isn't available here and what DPAPI
# does and does not protect. The same caveat applies: DPAPI binds to the user
# identity, not to presence, so what bounds exposure is the idle window, which
# is kept short and slides on use. The expiry is bound as the DPAPI entropy, so
# editing it in the file makes decryption fail rather than extending the window.
#
# This caches the credential itself rather than a key that unlocks a vault, so
# it is deliberately shorter-lived than the bw session cache beneath it.
#
# `token` and `server` exist to be captured by mise, not to be read by a human:
# they print a credential to stdout, so running one to "see if it works" puts a
# long-lived token into a terminal, a shell history, a log, or an agent
# transcript. Use `check` to diagnose instead -- it resolves the same way and
# reports the outcome without emitting either value.
#
# Commands: token (default) | server | check | reset | status
[CmdletBinding()]
param(
  [ValidateSet('token', 'server', 'check', 'reset', 'status')]
  [string]$Command = 'token'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue

$script:CachePath = Join-Path $env:LOCALAPPDATA 'hass-vault\cache'
$script:IdleWindow = [TimeSpan]::FromHours(4)

# The vault is searched by name rather than opened by a fixed item id, so the
# item stays renameable and this file holds no vault-specific identifier. The
# search is a prefilter only -- bw matches names and URIs loosely -- so the
# result is then narrowed to items actually carrying the token field, and an
# ambiguous result is refused rather than guessed.
$script:ItemQuery = if ($env:HASS_VAULT_ITEM) { $env:HASS_VAULT_ITEM } else { 'Home Assistant' }
$script:TokenField = 'CLI Token'

function Write-Diag {
  param([string]$Message)
  [Console]::Error.WriteLine("hass-vault: $Message")
}

function Write-Cache {
  param([string]$Server, [string]$Token)
  $expiry = (Get-Date).ToUniversalTime().Add($script:IdleWindow).ToString('o')
  $entropy = [Text.Encoding]::UTF8.GetBytes($expiry)
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
    $entropy = [Text.Encoding]::UTF8.GetBytes($lines[0])
    $plain = [Security.Cryptography.ProtectedData]::Unprotect(
      [Convert]::FromBase64String($lines[1]), $entropy, 'CurrentUser')
    $parts = [Text.Encoding]::UTF8.GetString($plain) -split "`n", 2
    if ($parts.Count -lt 2) { return $null }
    [pscustomobject]@{ Server = $parts[0]; Token = $parts[1] }
  }
  catch {
    # Wrong user, another machine, or an edited expiry. Indistinguishable and
    # all equally unusable, so treat as a miss.
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
  $cached = Read-Cache
  if ($cached) {
    # Slide the window on use, matching the bw session cache's idle semantics.
    Write-Cache -Server $cached.Server -Token $cached.Token
    return $cached
  }

  $bw = (Get-Command bw.cmd -ErrorAction SilentlyContinue).Source
  if (-not $bw) { throw 'bw not found on PATH' }

  $sessionScript = Join-Path $PSScriptRoot 'bw-session-windows.ps1'
  $session = (& $sessionScript get 2>$null | Out-String).Trim()
  if (-not $session) { throw 'could not unlock the vault' }

  $items = Find-VaultItem -Bw $bw -Session $session

  # The CLI serves a local copy of the vault and refreshes it only on an
  # explicit sync -- not on unlock, and not on list -- so an item added from
  # another device stays invisible here indefinitely. Syncing only on a miss
  # keeps the cost off the common path.
  if ($items.Count -eq 0) {
    Invoke-Bw -Bw $bw -Session $session -Arguments @('sync') | Out-Null
    $items = Find-VaultItem -Bw $bw -Session $session
  }

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

  Write-Cache -Server $server -Token $field.value
  [pscustomobject]@{ Server = $server; Token = $field.value }
}

switch ($Command) {
  'reset' {
    Remove-Item -Path $script:CachePath -Force -ErrorAction SilentlyContinue
    break
  }
  'check' {
    # Reports shape, never values: the whole point is that a failure can be
    # diagnosed without printing a secret somewhere it will persist. The error
    # goes to stderr, where mise would have swallowed it.
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
    # Diagnostics go to stderr and the exit code carries the failure: mise
    # swallows an `[env]` exec's stderr, so a bad lookup must not put an error
    # message on stdout where it would be captured as the credential.
    try {
      $creds = Get-VaultCredential
    }
    catch {
      Write-Diag $_.Exception.Message
      exit 1
    }
    if ($Command -eq 'server') { Write-Output $creds.Server } else { Write-Output $creds.Token }
  }
}

# Explicit, so the caller's $LASTEXITCODE reflects this run rather than whatever
# native command preceded it -- falling off the end of a script leaves it
# untouched, and the failure path above sets it.
exit 0
