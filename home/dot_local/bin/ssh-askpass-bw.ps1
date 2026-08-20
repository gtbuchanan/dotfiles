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

# SSH_ASKPASS_REQUIRE is `force`, so ssh routes *every* prompt here, not just
# requests for a secret. Host key verification is the notable other one: its text
# spans several lines, carries the fingerprint the user is being asked to check,
# and wants a literal yes/no rather than a password. Rendering that in a
# single-line masked box shows neither the fingerprint nor what you typed.
#
# ssh gives no machine-readable hint about which kind of prompt this is --
# SSH_ASKPASS_PROMPT is unset on this build -- so classify on the text.
#
# Only the first line is available to classify on. SSH_ASKPASS names a bare
# executable with no arguments, so reaching PowerShell requires a .cmd shim, and
# cmd.exe ends its command line at the first newline: the fingerprint and the
# yes/no question are gone before this script starts. Matching the authenticity
# line is therefore the only handle, and it is also why these prompts are
# declined rather than answered -- approving a host key whose fingerprint cannot
# be displayed defeats the point of being asked.
function Test-HostKeyPrompt {
  param([string]$Text)
  $Text -match "authenticity of host"
}

function Get-HostKeyHost {
  param([string]$Text)
  if ($Text -match "authenticity of host '(?<h>[^' ]+)") { return $Matches.h }
  $null
}

function Test-SecretPrompt {
  param([string]$Text)
  $Text -match 'password:\s*$' -or $Text -match 'passphrase'
}

# A native dialog rather than Read-Host: ssh owns this process's stdout and may
# redirect stdin, so console input can't be relied on. Same reasoning as
# ssh-askpass-termux's termux-dialog popup.
function Read-PromptDialog {
  param(
    [string]$Message,
    [switch]$Mask,
    [switch]$Notice
  )
  Add-Type -AssemblyName System.Windows.Forms, System.Drawing

  # A multiline TextBox renders only CRLF; a bare LF is dropped silently, running
  # the surrounding words together. This file is LF, as is anything ssh passes in,
  # so normalize rather than rely on the source's line endings.
  $Message = ($Message -replace "`r`n", "`n") -replace "`n", "`r`n"

  # Multiline and read-only rather than a Label so the full prompt is visible and
  # selectable -- a host key prompt is several lines and the fingerprint in it is
  # the entire point of asking.
  $text = New-Object System.Windows.Forms.TextBox -Property @{
    Text = $Message; Multiline = $true; ReadOnly = $true; WordWrap = $true
    ScrollBars = 'Vertical'; BackColor = [System.Drawing.SystemColors]::Control
    BorderStyle = 'None'; Width = 440; Height = 96; Left = 12; Top = 12
    TabStop = $false
  }
  $form = New-Object System.Windows.Forms.Form -Property @{
    Text = 'SSH'; Width = 480; StartPosition = 'CenterScreen'
    FormBorderStyle = 'FixedDialog'; MaximizeBox = $false; MinimizeBox = $false
    TopMost = $true
  }
  $form.Controls.Add($text)

  if ($Notice) {
    # No input: the caller has already decided the answer, and this only explains
    # why and how to proceed. Height follows the text so the commands aren't
    # buried in whitespace or hidden behind a scrollbar.
    # Wider than the prompt case so the suggested commands sit on one line --
    # wrapping them mid-argument makes them awkward to read and to copy.
    $form.Width = 660
    $text.Width = 620
    $text.Font = New-Object System.Drawing.Font('Consolas', 9)

    # Allow for wrapping: a long line occupies more than one row, and
    # underestimating leaves a scrollbar over content that had room to show.
    $wrapAt = 74
    $rows = 0
    foreach ($line in ($Message -split "`r`n")) {
      $rows += [Math]::Max(1, [Math]::Ceiling($line.Length / $wrapAt))
    }
    $text.Height = [Math]::Min(420, [Math]::Max(120, $rows * 15))
    $form.Height = $text.Height + 110
    $ok = New-Object System.Windows.Forms.Button -Property @{
      Text = 'OK'; DialogResult = 'OK'; Width = 90; Left = 540; Top = $text.Height + 24
    }
    $form.Controls.Add($ok)
    $form.AcceptButton = $ok
    $form.CancelButton = $ok
    $form.Add_Shown({ $form.Activate(); $ok.Focus() })
    $form.ShowDialog() | Out-Null
    return $null
  }

  $form.Height = 240
  $box = New-Object System.Windows.Forms.TextBox -Property @{
    UseSystemPasswordChar = [bool]$Mask; Width = 440; Left = 12; Top = 118
  }
  $ok = New-Object System.Windows.Forms.Button -Property @{
    Text = 'OK'; DialogResult = 'OK'; Width = 90; Left = 258; Top = 154
  }
  $cancel = New-Object System.Windows.Forms.Button -Property @{
    Text = 'Cancel'; DialogResult = 'Cancel'; Width = 90; Left = 360; Top = 154
  }
  $form.Controls.AddRange(@($box, $ok, $cancel))
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

  # The prompt may name a host either way -- `ssh sw01` gives the alias while the
  # vault entry may hold the FQDN, or the reverse -- so ask ssh to resolve its own
  # config and accept every spelling. Most specific first, so a full name wins over
  # a bare short name another network might reuse. `ssh -G` only parses config; it
  # does not connect, and ssh is necessarily present, having invoked this script.
  $shortName = $TargetHost.Split('.')[0]
  $resolved = $null
  $line = & ssh -G $TargetHost 2>$null | Where-Object { $_ -match '^hostname ' }
  if ($line) { $resolved = ($line -split ' ', 2)[1].Trim() }

  $candidates = @("ssh://$TargetHost")
  foreach ($alt in @($resolved, $shortName)) {
    if ($alt -and ("ssh://$alt" -notin $candidates)) { $candidates += "ssh://$alt" }
  }

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

# Handled before any vault work: there is nothing to look up, and answering
# would mean vouching for a key whose fingerprint was truncated away.
if (Test-HostKeyPrompt -Text $Prompt) {
  $unknownHost = Get-HostKeyHost -Text $Prompt
  $target = if ($unknownHost) { $unknownHost } else { 'the host' }
  $guidance = @"
$target is not in known_hosts, and its fingerprint cannot be shown here --
Windows truncates the prompt before this helper sees it.

Declining, rather than vouch for a key you have not seen.

Accept it once, in a terminal:

    `$env:SSH_ASKPASS_REQUIRE = 'never'; ssh $target

That gives ssh's own prompt, fingerprint included.

To check that fingerprint against the device first:

    ssh-keyscan $target | ssh-keygen -lf -
"@
  Read-PromptDialog -Message $guidance -Notice | Out-Null
  Write-Diag "declined host key prompt for $target; see the dialog for how to accept it"
  Write-Output 'no'
  exit 0
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

$message = if ($Prompt) { $Prompt } else { 'Password:' }
$typed = Read-PromptDialog -Message $message -Mask:(Test-SecretPrompt -Text $message)
if ($null -eq $typed) { exit 1 }
Write-Output $typed
