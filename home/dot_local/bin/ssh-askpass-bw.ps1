# SSH_ASKPASS helper backed by the Bitwarden vault, for hosts that can't do key
# auth. OpenSSH passes the prompt as the sole argument and reads the secret from
# stdout, so nothing else may be written there -- diagnostics go to stderr.
#
# Invoked through ssh-askpass-bw.cmd: SSH_ASKPASS must name an executable, and a
# .ps1 isn't one.
#
# SSH_ASKPASS_REQUIRE is set to `force`, which routes *every* prompt here --
# including git's and hosts with no vault entry. `prefer` isn't an option: it
# only consults an askpass when DISPLAY is set, which it never is on Windows.
# So this must always yield something, and falls back to asking directly rather
# than failing, which would abort the connection.
[CmdletBinding()]
param([Parameter(Position = 0)][string]$Prompt = '')

$ErrorActionPreference = 'Stop'

# Diagnostics go to stderr directly rather than through Write-Error, which
# $ErrorActionPreference = 'Stop' turns into a terminating error -- that would
# abort before the dialog below, defeating the guarantee that this always
# answers. ssh discards our stderr, so these are for a human running it by hand.
function Write-Diag {
  param([string]$Message)
  [Console]::Error.WriteLine("ssh-askpass-bw: $Message")
}

# A native dialog rather than Read-Host: ssh owns this process's stdout and may
# redirect stdin, so console input can't be relied on. Same reasoning as
# ssh-askpass-termux's termux-dialog popup.
function Read-SecretDialog {
  param([string]$Message)
  Add-Type -AssemblyName System.Windows.Forms, System.Drawing
  $form = New-Object System.Windows.Forms.Form -Property @{
    Text = 'SSH'; Width = 460; Height = 190; StartPosition = 'CenterScreen'
    FormBorderStyle = 'FixedDialog'; MaximizeBox = $false; MinimizeBox = $false; TopMost = $true
  }
  $label = New-Object System.Windows.Forms.Label -Property @{
    Text = $Message; AutoSize = $false; Width = 420; Height = 40; Left = 12; Top = 12
  }
  $box = New-Object System.Windows.Forms.TextBox -Property @{
    UseSystemPasswordChar = $true; Width = 420; Left = 12; Top = 60
  }
  $ok = New-Object System.Windows.Forms.Button -Property @{
    Text = 'OK'; DialogResult = 'OK'; Width = 90; Left = 240; Top = 100
  }
  $cancel = New-Object System.Windows.Forms.Button -Property @{
    Text = 'Cancel'; DialogResult = 'Cancel'; Width = 90; Left = 342; Top = 100
  }
  $form.Controls.AddRange(@($label, $box, $ok, $cancel))
  $form.AcceptButton = $ok
  $form.CancelButton = $cancel
  $form.Add_Shown({ $form.Activate(); $box.Focus() })
  if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
  $box.Text
}

# `user@host's password:` covers password auth; keyboard-interactive words it as
# `(user@host) Password:`. Anything else -- notably `Enter passphrase for <key>`
# -- has no host to key on and falls through to the dialog.
function Get-PromptHost {
  param([string]$Text)
  if ($Text -match "^[^@]+@(?<h>[^']+)'s password:") { return $Matches.h }
  if ($Text -match '^\((?:[^@)]+@)?(?<h>[^)]+)\)\s*Password:') { return $Matches.h }
  return $null
}

# Matching happens here rather than via `bw list --url`, which honours each item's
# own URI match detection. That defaults to base domain, so ssh://sw01.example.com
# also returns every unrelated item under example.com -- observed returning five
# items, four of them different hosts. Handing a near miss to a password prompt
# means giving one host's credential to another, so --url cannot be trusted even
# as a filter; making it safe would require Exact on every item in the vault, and
# one future item added with defaults would silently undo that.
#
# --search is a prefilter only. It is issued once and both plausible spellings of
# the host are compared against the result in memory, because each bw invocation
# costs several seconds -- roughly four of which are Node startup before the vault
# is even touched. The comparison is an exact string match on the full URI, and an
# ambiguous result is refused rather than guessed.
# The session travels by environment rather than --session, which would put the
# key in the process command line, and is cleared again however the call ends.
# --nointeraction is applied to every call so a session the vault has since
# invalidated errors out instead of prompting into a stdout ssh reads as the
# secret; --raw likewise keeps bw's descriptive chatter out of that stream.
function Invoke-Bw {
  param(
    [string]$Bw,
    [string]$Session,
    [string[]]$Arguments
  )
  try {
    $env:BW_SESSION = $Session
    & $Bw @Arguments --nointeraction --raw 2>$null
  }
  finally {
    Remove-Item Env:BW_SESSION -ErrorAction SilentlyContinue
  }
}

function Find-VaultItem {
  param(
    [string]$Bw,
    [string]$Session,
    [string]$SearchTerm,
    [string[]]$Candidates
  )

  $json = Invoke-Bw -Bw $Bw -Session $Session -Arguments @('list', 'items', '--search', $SearchTerm)
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json)) { return @() }

  $found = @($json | ConvertFrom-Json)
  foreach ($uri in $Candidates) {
    $matched = @($found | Where-Object {
        $_.login -and $_.login.uris -and ($_.login.uris.uri -contains $uri)
      })
    if ($matched.Count -gt 0) { return $matched }
  }
  @()
}

function Get-VaultPassword {
  param([string]$TargetHost)

  # Session comes from the cache beside this script, which prompts for biometrics
  # only when its idle window has lapsed -- otherwise every connection would cost
  # an unlock.
  $sessionScript = Join-Path $PSScriptRoot 'bw-session-windows.ps1'
  $session = (& $sessionScript get 2>$null | Out-String).Trim()
  if (-not $session) { return $null }

  # Plain bw, since the session is already in hand.
  $bw = (Get-Command bw.cmd -ErrorAction SilentlyContinue).Source
  if (-not $bw) { return $null }

  # Whether ssh names the host by its config alias or its resolved HostName isn't
  # something this can know, so both are accepted -- longest first, so a specific
  # entry wins over a bare short name that another network might also use.
  $shortName = $TargetHost.Split('.')[0]
  $candidates = @("ssh://$TargetHost")
  if ($shortName -ne $TargetHost) { $candidates += "ssh://$shortName" }

  $query = @{
    Bw = $bw
    Session = $session
    SearchTerm = $shortName
    Candidates = $candidates
  }
  $items = Find-VaultItem @query

  # The CLI serves a local copy of the vault and refreshes it only on an explicit
  # sync -- not on unlock, and not on list -- so a URI added from another device
  # stays invisible here indefinitely. Syncing only on a miss keeps the cost off
  # the common path: a hit already costs several seconds, and a miss would
  # otherwise have fallen through to prompting by hand anyway. Failure is ignored
  # so an offline lookup still proceeds against the cached copy.
  if ($items.Count -eq 0) {
    Invoke-Bw -Bw $bw -Session $session -Arguments @('sync') | Out-Null
    $items = Find-VaultItem @query
  }

  # Ambiguity is refused rather than guessed: picking one of several would send
  # a credential the user never chose.
  if ($items.Count -ne 1) {
    if ($items.Count -gt 1) {
      Write-Diag "$($items.Count) items match $TargetHost; refusing to guess"
    }
    return $null
  }
  $items[0].login.password
}

$targetHost = Get-PromptHost -Text $Prompt
if ($targetHost) {
  try {
    $password = Get-VaultPassword -TargetHost $targetHost
    if ($password) { Write-Output $password; exit 0 }
    Write-Diag "no vault item for $targetHost; prompting"
  }
  catch {
    Write-Diag "vault lookup failed ($($_.Exception.Message)); prompting"
  }
}

$typed = Read-SecretDialog -Message $(if ($Prompt) { $Prompt } else { 'Password:' })
if ($null -eq $typed) { exit 1 }
Write-Output $typed
