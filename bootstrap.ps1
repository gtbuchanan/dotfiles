#Requires -Version 5.1
<#
.SYNOPSIS
  Provision a fresh Windows host far enough to run `chezmoi init --apply --ssh`.

.DESCRIPTION
  Everything this repo deploys arrives through chezmoi, but chezmoi itself can't
  bootstrap the host: `--ssh` clones over SSH, and the git-repo externals
  authenticate over SSH mid-apply, so a usable SSH key must exist before chezmoi
  runs at all. The Windows OpenSSH client and agent are installed and configured
  *by* the winget manifest during that same apply, which is too late. See
  https://github.com/gtbuchanan/dotfiles/issues/4.

  This script closes that gap: it installs the handful of prerequisites winget
  can provide, gets an SSH key in front of git, then hands off to chezmoi, which
  owns everything from there.

  Deliberately standalone -- it is fetched over HTTPS before the repo exists
  locally, so it cannot be a chezmoi template, cannot read `.chezmoidata`, and
  must run under Windows PowerShell 5.1 (pwsh is one of the things it installs).
  Keep it free of pwsh-7-only syntax: no ternary, no null-coalescing, no `&&`.

  Idempotent -- safe to re-run after a partial failure.

.PARAMETER HostType
  Which vault backs this host. Prompted when omitted. Passed through to chezmoi
  so its own hosttype prompt isn't asked twice.

.PARAMETER SshKeyNote
  Name of the Dashlane note holding the private key (work hosts only).

.PARAMETER ResetWinGet
  Apply the Reset-AppxPackage workaround for winget's intermittent RPC errors.
  https://github.com/microsoft/winget-cli/issues/5626#issuecomment-3264037684

.EXAMPLE
  irm https://raw.githubusercontent.com/gtbuchanan/dotfiles/main/bootstrap.ps1 | iex

.EXAMPLE
  # `iex` can't forward parameters; use a scriptblock when you need them.
  $s = irm https://raw.githubusercontent.com/gtbuchanan/dotfiles/main/bootstrap.ps1
  & ([scriptblock]::Create($s)) -HostType ewn
#>
[CmdletBinding()]
param(
  [ValidateSet('personal', 'ewn')]
  [string]$HostType,

  [string]$SshKeyNote = 'SSH Private Key',

  [switch]$ResetWinGet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# Windows PowerShell 5.1 can still negotiate down to TLS 1.0/1.1 depending on
# the host's .NET defaults, which GitHub refuses. pwsh doesn't need this, but
# this script runs under 5.1 by definition.
[Net.ServicePointManager]::SecurityProtocol =
[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$GitHubUser = 'gtbuchanan'
$ModifyManagerRepo = 'VorpalBlade/chezmoi_modify_manager'

function Write-Step {
  param([Parameter(Mandatory = $true)][string]$Message)
  Write-Information "==> $Message"
}

function Write-Note {
  param([Parameter(Mandatory = $true)][string]$Message)
  Write-Information "    $Message"
}

# Re-read PATH from the registry into this process. winget updates the
# persisted environment but not an already-running shell, so without this the
# tools installed below aren't callable until the user opens a new window.
function Initialize-ProcessPath {
  $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $user = [Environment]::GetEnvironmentVariable('Path', 'User')
  $env:Path = ($machine, $user | Where-Object { $_ }) -join ';'
}

function Test-CommandAvailable {
  param([Parameter(Mandatory = $true)][string]$Name)
  $found = Get-Command $Name -ErrorAction SilentlyContinue
  return $null -ne $found
}

# The Microsoft-native OpenSSH client is the canonical one on every Windows host
# here (the winget manifest later removes the OS capability in favor of the
# preview package). Pre-apply only the capability build exists, so resolve
# whichever is present -- Program Files wins once the manifest has run.
function Get-OpenSshPath {
  param([Parameter(Mandatory = $true)][string]$Executable)
  $candidates = @(
    (Join-Path $env:ProgramFiles "OpenSSH\$Executable"),
    (Join-Path $env:SystemRoot "System32\OpenSSH\$Executable")
  )
  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) { return $candidate }
  }
  throw "Could not locate $Executable. Install the Windows OpenSSH client and re-run."
}

function Install-WinGetPackage {
  param(
    [Parameter(Mandatory = $true)][string]$Id,
    [Parameter(Mandatory = $true)][string]$DisplayName
  )

  winget list --exact --id $Id --accept-source-agreements | Out-Null
  if ($LASTEXITCODE -eq 0) {
    Write-Note "$DisplayName already installed"
    return
  }

  Write-Step "Installing $DisplayName"
  winget install --exact --id $Id --source winget --disable-interactivity `
    --accept-package-agreements --accept-source-agreements
  if ($LASTEXITCODE -ne 0) {
    throw "winget failed to install $DisplayName ($Id), exit code $LASTEXITCODE."
  }
}

# Not in winget, so pull the release archive directly. The GitHub API exposes a
# per-asset digest; verify against it rather than trusting the download blindly.
function Install-ChezmoiModifyManager {
  $installDir = Join-Path $HOME '.local\bin'
  $binary = Join-Path $installDir 'chezmoi_modify_manager.exe'

  if (Test-Path $binary) {
    Write-Note 'chezmoi_modify_manager already installed'
  }
  else {
    Write-Step 'Installing chezmoi_modify_manager'
    $release = Invoke-RestMethod "https://api.github.com/repos/$ModifyManagerRepo/releases/latest"
    $asset = $release.assets | Where-Object { $_.name -like '*x86_64-pc-windows-msvc.zip' }
    if (-not $asset) {
      throw "No Windows asset in the latest $ModifyManagerRepo release."
    }

    $temp = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $temp | Out-Null
    try {
      $archive = Join-Path $temp $asset.name
      Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $archive -UseBasicParsing

      # `digest` is "sha256:<hex>". Older releases may predate the field; warn
      # rather than fail so a missing digest doesn't block provisioning.
      $digest = $null
      if ($asset.PSObject.Properties.Name -contains 'digest') { $digest = $asset.digest }
      if ($digest) {
        $expected = $digest -replace '^sha256:', ''
        $actual = (Get-FileHash -Path $archive -Algorithm SHA256).Hash
        if ($actual -ne $expected) {
          throw "Checksum mismatch for $($asset.name): expected $expected, got $actual."
        }
      }
      else {
        Write-Warning "No digest published for $($asset.name); skipping verification."
      }

      New-Item -ItemType Directory -Path $installDir -Force | Out-Null
      Expand-Archive -Path $archive -DestinationPath $temp -Force
      $extracted = Get-ChildItem -Path $temp -Recurse -Filter 'chezmoi_modify_manager.exe' |
        Select-Object -First 1
      if (-not $extracted) {
        throw 'chezmoi_modify_manager.exe not found in the downloaded archive.'
      }
      Move-Item -Path $extracted.FullName -Destination $binary -Force
    }
    finally {
      Remove-Item -Path $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  # chezmoi resolves the binary from PATH when running modify_ scripts, and the
  # chezmoi process launched below inherits this environment. Persisting the
  # entry is the winget manifest's job (the localBinPath resource), which runs
  # during that same apply -- so only this process needs patching, and the two
  # don't compete over the registry value.
  $entries = $env:Path -split ';' | Where-Object { $_ }
  if ($entries -notcontains $installDir) {
    $env:Path = (@($entries) + $installDir) -join ';'
  }
}

# Seed github.com's host keys from GitHub's published set so the init clone and
# the SSH externals don't stall on an interactive trust prompt. Fetched over
# HTTPS (cert-validated) rather than ssh-keyscan, which is trust-on-first-use.
# gist.github.com rides along via the HostKeyAlias in the deployed ssh_config.
function Initialize-KnownHostsFile {
  $sshDir = Join-Path $HOME '.ssh'
  $knownHosts = Join-Path $sshDir 'known_hosts'
  New-Item -ItemType Directory -Path $sshDir -Force | Out-Null

  $existing = @()
  if (Test-Path $knownHosts) {
    $existing = @(Get-Content -Path $knownHosts)
  }

  $meta = Invoke-RestMethod 'https://api.github.com/meta'
  $added = @()
  foreach ($key in $meta.ssh_keys) {
    $line = "github.com $key"
    if ($existing -notcontains $line) { $added += $line }
  }

  if ($added.Count -eq 0) {
    Write-Note 'github.com host keys already trusted'
    return
  }

  Write-Step "Trusting $($added.Count) github.com host key(s)"
  $all = @($existing) + $added
  $content = ($all -join "`n") + "`n"
  [IO.File]::WriteAllText($knownHosts, $content, (New-Object Text.UTF8Encoding $false))
}

# Work hosts: Dashlane has no SSH agent, so materialize the key at the default
# identity path. `ssh` picks it up without an agent, which matters because the
# agent service isn't running yet. The post-apply import script loads it into
# the agent and removes the file.
function Initialize-EwnSshKey {
  param([Parameter(Mandatory = $true)][string]$NoteName)

  $sshDir = Join-Path $HOME '.ssh'
  $keyPath = Join-Path $sshDir 'id_ed25519'

  if (Test-Path $keyPath) {
    Write-Note 'SSH private key already present'
    return
  }

  if (-not (Test-CommandAvailable 'dcli')) {
    throw 'dcli not found on PATH after install. Open a new shell and re-run.'
  }

  Write-Step 'Syncing the Dashlane vault'
  dcli sync
  if ($LASTEXITCODE -ne 0) { throw "dcli sync failed, exit code $LASTEXITCODE." }

  Write-Step "Writing the SSH private key from the '$NoteName' note"
  $key = dcli note $NoteName
  if ($LASTEXITCODE -ne 0) { throw "dcli note failed, exit code $LASTEXITCODE." }
  if (-not $key) { throw "The '$NoteName' note is empty." }

  # OpenSSH rejects a key whose PEM has CRLF line endings or lacks a trailing
  # newline, and PowerShell's own redirection would introduce both plus a BOM.
  $text = ($key -join "`n") -replace "`r`n", "`n"
  if (-not $text.EndsWith("`n")) { $text += "`n" }
  New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
  [IO.File]::WriteAllText($keyPath, $text, (New-Object Text.UTF8Encoding $false))

  # OpenSSH refuses to use a key readable by anyone but its owner.
  icacls $keyPath /inheritance:r /grant:r "$($env:USERNAME):(F)" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Failed to restrict permissions on $keyPath." }
}

# Personal hosts: Bitwarden's desktop agent serves the key straight from the
# vault, so there is no key file to provision -- only a running, unlocked
# Bitwarden to verify. Its agent claims the same named pipe the Windows
# ssh-agent service uses, which is why the manifest disables that service.
function Assert-BitwardenAgent {
  $sshAdd = Get-OpenSshPath -Executable 'ssh-add.exe'
  & $sshAdd -l | Out-Null
  $code = $LASTEXITCODE

  if ($code -eq 0) {
    Write-Note 'Bitwarden SSH agent is serving a key'
    return
  }

  $guidance = @(
    'The SSH agent is not serving a key yet. In Bitwarden Desktop:',
    '  1. Sign in and unlock the vault.',
    '  2. Settings -> enable the SSH agent.',
    '  3. Confirm an SSH key item exists in the vault.',
    'Then re-run this script.'
  )
  if ($code -eq 2) {
    $guidance = @(
      'No SSH agent is reachable. Install Bitwarden Desktop, sign in, unlock the',
      'vault, and enable the SSH agent in Settings, then re-run this script.',
      'If the Windows ssh-agent service is running it will claim the same named',
      'pipe -- disable it (the winget manifest does this on personal hosts).'
    ) + $guidance
  }
  throw ($guidance -join [Environment]::NewLine)
}

if ($env:OS -ne 'Windows_NT') {
  throw 'This bootstrap is Windows-only. See the README for macOS and Linux prerequisites.'
}

if (-not $HostType) {
  $choice = Read-Host 'What type of host are you on? (personal/ewn)'
  $HostType = $choice.Trim().ToLowerInvariant()
}
if ($HostType -ne 'personal' -and $HostType -ne 'ewn') {
  throw "Unknown host type '$HostType'. Expected 'personal' or 'ewn'."
}
Write-Step "Bootstrapping a '$HostType' host"

if ($ResetWinGet) {
  Write-Step 'Resetting the WinGet app package'
  Reset-AppxPackage -Package 'Microsoft.DesktopAppInstaller_1.26.430.0_x64__8wekyb3d8bbwe'
}

if (-not (Test-CommandAvailable 'winget')) {
  throw 'winget not found. Install "App Installer" from the Microsoft Store and re-run.'
}

Install-WinGetPackage -Id 'twpayne.chezmoi' -DisplayName 'chezmoi'
Install-WinGetPackage -Id 'Microsoft.PowerShell' -DisplayName 'PowerShell'
if ($HostType -eq 'ewn') {
  Install-WinGetPackage -Id 'Dashlane.CLI' -DisplayName 'Dashlane CLI'
}
else {
  Install-WinGetPackage -Id 'Bitwarden.Bitwarden' -DisplayName 'Bitwarden'
}
Initialize-ProcessPath

Install-ChezmoiModifyManager
Initialize-KnownHostsFile

if ($HostType -eq 'ewn') {
  Initialize-EwnSshKey -NoteName $SshKeyNote
}
else {
  Assert-BitwardenAgent
}

# Git for Windows prefers its bundled MSYS2 ssh.exe, which can't reach the
# Windows agent's named pipe. The winget manifest sets GIT_SSH machine-wide, but
# that only happens during the apply below -- so point this process at the
# native client for the clone that gets us there.
$env:GIT_SSH = Get-OpenSshPath -Executable 'ssh.exe'

if (-not (Test-CommandAvailable 'chezmoi')) {
  throw 'chezmoi not found on PATH after install. Open a new shell and re-run.'
}

Write-Step 'Running chezmoi init --apply'
chezmoi init --apply --ssh $GitHubUser --promptChoice "What type of host are you on=$HostType"
if ($LASTEXITCODE -ne 0) { throw "chezmoi init failed, exit code $LASTEXITCODE." }

Write-Step 'Bootstrap complete'
Write-Note 'Open a new shell to pick up the deployed profile.'
if ($HostType -eq 'ewn') {
  Write-Note 'Sign in to the Microsoft 365 CLI -- see docs/m365.md.'
}
