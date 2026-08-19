# Session cache for the Bitwarden CLI, so a biometric unlock is amortized across
# invocations instead of demanded by every one.
#
# Windows-only. The Bitwarden CLI deliberately never persists the symmetric key
# that decrypts vault items -- `bw unlock` hands it back and expects the caller
# to carry it in BW_SESSION -- so without a cache each lookup means another
# unlock, and with SSH_ASKPASS that means a prompt per connection.
#
# HOW THIS DIFFERS FROM bw-session-termux, deliberately:
#
# The Termux cache derives its key-encryption key from a signature made inside
# the Android hardware keystore, so reading it requires a fingerprint and the
# file is inert on any other device. The Windows equivalent would be
# KeyCredentialManager, whose key lives in the TPM and signs only after a Hello
# gesture -- but that is the Windows Hello *for Business* API, and this host runs
# a convenience PIN on a domain-joined account with WHfB not deployed
# (`NgcSet: NO`). There is no container for it to open, so it is unavailable
# here rather than merely inconvenient.
#
# So this wraps with DPAPI instead, and the difference is worth being explicit
# about: DPAPI binds to the *user identity*, not to presence. Any process running
# as this user can unseal the cache with no prompt. It protects a copied cache
# file, another account on the machine, and offline disk access -- and nothing at
# all against code already running as you. Gating reads behind a consent prompt
# would not change that, since DPAPI would still unseal for anything that skipped
# the prompt and called Unprotect directly.
#
# What bounds real exposure is therefore the idle window, not the wrapping. It is
# kept short for that reason, and it slides on use. The expiry is bound as the
# DPAPI entropy, so editing it in the file makes decryption fail rather than
# extending the window -- the same trick the Termux cache plays with GCM
# additional authenticated data.
#
# Commands: get (default) | check | lock | reset | status
[CmdletBinding()]
param(
  [ValidateSet('get', 'check', 'lock', 'reset', 'status')]
  [string]$Command = 'get'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue

$script:CachePath = Join-Path $env:LOCALAPPDATA 'bw-session\cache'
$script:IdleWindow = [TimeSpan]::FromHours(4)

function Get-BwbioPath {
  # The .cmd shim, not the .ps1 one pnpm also installs: through the .ps1 shim
  # PowerShell folds bwbio's stderr into stdout, so its "Authenticate with
  # Windows Hello" chatter would be parsed as the session key.
  (Get-Command bwbio.cmd -ErrorAction SilentlyContinue).Source
}

function Test-SessionKey {
  param([string]$Value)
  $Value.Length -ge 40 -and $Value -match '^[A-Za-z0-9+/=]+$'
}

function Write-Cache {
  param([string]$Key)
  $expiry = (Get-Date).ToUniversalTime().Add($script:IdleWindow).ToString('o')
  $entropy = [Text.Encoding]::UTF8.GetBytes($expiry)
  $blob = [Security.Cryptography.ProtectedData]::Protect(
    [Text.Encoding]::UTF8.GetBytes($Key), $entropy, 'CurrentUser')
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
    [Text.Encoding]::UTF8.GetString($plain)
  }
  catch {
    # Wrong user, another machine, or an edited expiry. Indistinguishable and
    # all equally unusable, so treat as a miss.
    $null
  }
}

function Remove-Cache {
  [CmdletBinding(SupportsShouldProcess)]
  param()
  if ($PSCmdlet.ShouldProcess($script:CachePath, 'Remove cached session')) {
    Remove-Item -Path $script:CachePath -Force -ErrorAction SilentlyContinue
  }
}

function Get-Session {
  $cached = Read-Cache
  if ($cached) {
    # Slide the window on use, matching the Termux cache's idle semantics.
    Write-Cache -Key $cached
    return $cached
  }

  $bwbio = Get-BwbioPath
  if (-not $bwbio) { throw 'bwbio.cmd not found on PATH' }

  # No --nointeraction: it suppresses the biometric prompt as well as the
  # master-password one, leaving no way to unlock at all. The exit code is
  # unreliable here -- a denied prompt falls through to a master-password prompt
  # that dies on closed stdin and still exits 0 -- so judge by the output shape.
  $key = (& $bwbio unlock --raw 2>$null | Out-String).Trim()
  if (-not (Test-SessionKey -Value $key)) { throw 'biometric unlock produced no session key' }

  Write-Cache -Key $key
  $key
}

switch ($Command) {
  'get' { Get-Session; break }
  'check' { if (Read-Cache) { exit 0 } else { exit 1 } }
  'reset' { Remove-Cache; break }
  'lock' {
    Remove-Cache
    $bw = (Get-Command bw.cmd -ErrorAction SilentlyContinue).Source
    if ($bw) { & $bw lock | Out-Null }
    break
  }
  'status' {
    if (-not (Test-Path $script:CachePath)) { 'no cached session'; break }
    $lines = @(Get-Content -Path $script:CachePath)
    $expiry = [datetime]::Parse($lines[0]).ToUniversalTime()
    $left = $expiry - (Get-Date).ToUniversalTime()
    if ($left -le [TimeSpan]::Zero) { 'cached session expired' }
    else { "cached session valid for {0:hh\:mm\:ss}" -f $left }
    break
  }
}
