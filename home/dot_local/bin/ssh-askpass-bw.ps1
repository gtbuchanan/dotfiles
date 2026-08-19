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

# Bitwarden's --url filter uses each item's own match-detection setting, which
# defaults to fuzzy. Fuzzy is fine for autofill and dangerous here: a near match
# would hand a different host's password to whatever is asking. So the filter is
# treated as a prefilter only, and the URI is re-checked exactly.
function Get-VaultPassword {
  param([string]$TargetHost)
  $uri = "ssh://$TargetHost"

  # Session comes from the cache beside this script, which prompts for biometrics
  # only when its idle window has lapsed -- otherwise every connection would cost
  # an unlock.
  $session = (& (Join-Path $PSScriptRoot 'bw-session-windows.ps1') get 2>$null | Out-String).Trim()
  if (-not $session) { return $null }

  # Plain bw, since the session is already in hand; and by environment rather
  # than --session, which would put the key in the process command line.
  $bw = (Get-Command bw.cmd -ErrorAction SilentlyContinue).Source
  if (-not $bw) { return $null }

  # --nointeraction so a session the vault has since invalidated errors out
  # instead of prompting into a stdout ssh is reading as the secret.
  $json = $null
  try {
    $env:BW_SESSION = $session
    $json = & $bw list items --url $uri --nointeraction --raw 2>$null
  }
  finally {
    Remove-Item Env:BW_SESSION -ErrorAction SilentlyContinue
  }
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json)) { return $null }

  $items = @($json | ConvertFrom-Json | Where-Object {
      $_.login -and $_.login.uris -and ($_.login.uris.uri -contains $uri)
    })

  # Ambiguity is refused rather than guessed: picking one of several would send
  # a credential the user never chose.
  if ($items.Count -ne 1) {
    if ($items.Count -gt 1) {
      Write-Error "ssh-askpass-bw: $($items.Count) items carry $uri; refusing to guess"
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
    Write-Error "ssh-askpass-bw: no vault item with URI ssh://$targetHost; prompting"
  }
  catch {
    Write-Error "ssh-askpass-bw: vault lookup failed ($($_.Exception.Message)); prompting"
  }
}

$typed = Read-SecretDialog -Message $(if ($Prompt) { $Prompt } else { 'Password:' })
if ($null -eq $typed) { exit 1 }
Write-Output $typed
