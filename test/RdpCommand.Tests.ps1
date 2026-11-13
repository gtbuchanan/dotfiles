# Tests for rdp, defined in profile.d/45-remote.ps1, which opens a host's
# connection file from the private hosts inventory in mstsc and tab-completes
# the host names that inventory holds.
#
# Each case runs in a child pwsh, as in ClaudeResume.Tests.ps1, so the part's
# functions never reach Pester's own session. $HOME points at a sandbox holding
# a fake inventory, and an `mstsc` function shadowing the executable records the
# argv it was handed, so no connection is attempted.
#
# The rdp block renders only for hosttype personal on Windows, so the suite
# skips anywhere but Windows and supplies the data itself: CI has no
# `chezmoi init` config to read hosttype or codeDir from.
#
#   mise run test:pester [-- -FilterName '*rdp*']

BeforeDiscovery {
  $script:Applicable = $IsWindows -and [bool](Get-Command chezmoi -ErrorAction SilentlyContinue)
}

Describe 'rdp command' -Skip:(-not $script:Applicable) {

  BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    $script:source = Join-Path $script:root `
      'home/dot_config/powershell/profile.d/45-remote.ps1.tmpl'

    $script:rendered = Join-Path ([IO.Path]::GetTempPath()) "rdp-part-$PID.ps1"
    Get-Content -LiteralPath $script:source -Raw |
      chezmoi execute-template --source (Join-Path $script:root 'home') --no-tty `
        --override-data '{"hosttype":"personal","codeDir":"Code"}' |
      Set-Content -LiteralPath $script:rendered -Encoding utf8

    # Positional binding is off so a bare host name reaches $Rest instead of
    # landing in $Complete.
    $script:probeSource = @'
[CmdletBinding(PositionalBinding = $false)]
param(
  [string] $Rendered,
  [string] $Sandbox,
  [string] $Log,
  [string] $Complete,
  [Parameter(ValueFromRemainingArguments)] [string[]] $Rest
)
$ErrorActionPreference = 'Stop'
function mstsc { Set-Content -LiteralPath $Log -Value $args -Encoding utf8 }
Set-Variable -Name HOME -Value $Sandbox -Force
. $Rendered
if ($Complete) {
  $ps = [System.Management.Automation.PowerShell]::Create('CurrentRunspace')
  try {
    $c = [System.Management.Automation.CommandCompletion]::CompleteInput(
      $Complete, $Complete.Length, @{}, $ps)
    $c.CompletionMatches | ForEach-Object { $_.CompletionText }
  }
  finally { $ps.Dispose() }
}
else { rdp @Rest }
'@

    function script:Invoke-Probe([string[]] $Arguments) {
      $out = & pwsh -NoLogo -NoProfile -NonInteractive -File $script:probe `
        -Rendered $script:rendered -Sandbox $script:sandbox -Log $script:log `
        @Arguments 2>&1
      [pscustomobject]@{ Output = @($out | ForEach-Object ToString); ExitCode = $LASTEXITCODE }
    }

    function script:New-RdpFile([string] $Site, [string] $Name) {
      $dir = Join-Path $script:inventory $Site
      New-Item -ItemType Directory -Path $dir -Force | Out-Null
      $path = Join-Path $dir "$Name.rdp"
      Set-Content -LiteralPath $path -Value "full address:s:$Name.example" -Encoding utf8
      $path
    }
  }

  AfterAll {
    if ($script:rendered) {
      Remove-Item -LiteralPath $script:rendered -Force -ErrorAction SilentlyContinue
    }
  }

  BeforeEach {
    $script:sandbox = Join-Path ([IO.Path]::GetTempPath()) "rdp-test-$PID-$(New-Guid)"
    $script:inventory = Join-Path $script:sandbox 'Code/gtbuchanan/hosts/rdp'
    New-Item -ItemType Directory -Path $script:inventory -Force | Out-Null
    $script:log = Join-Path $script:sandbox 'mstsc-argv'
    $script:probe = Join-Path $script:sandbox 'probe.ps1'
    Set-Content -LiteralPath $script:probe -Value $script:probeSource -Encoding utf8
  }

  AfterEach {
    Remove-Item -LiteralPath $script:sandbox -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'completes host names from every site in the inventory' {
    New-RdpFile 'homelab' 'dc01' | Out-Null
    New-RdpFile 'homelab' 'fs02' | Out-Null
    New-RdpFile 'parents' 'dc02' | Out-Null

    (Invoke-Probe '-Complete', 'rdp d').Output | Should -Be @('dc01', 'dc02')
  }

  It 'opens the matching file in mstsc, passing extra arguments through' {
    $file = New-RdpFile 'homelab' 'dc01'

    $result = Invoke-Probe 'dc01', '/f'

    $result.ExitCode | Should -Be 0
    Get-Content -LiteralPath $script:log | Should -Be @($file, '/f')
  }

  It 'refuses a name the inventory does not hold' {
    New-RdpFile 'homelab' 'dc01' | Out-Null

    $result = Invoke-Probe 'nope'

    $result.ExitCode | Should -Not -Be 0
    $result.Output -join "`n" | Should -BeLike "*No RDP file named 'nope'*"
    $script:log | Should -Not -Exist
  }

  It 'refuses a name two sites share rather than guessing' {
    New-RdpFile 'homelab' 'dc01' | Out-Null
    New-RdpFile 'parents' 'dc01' | Out-Null

    $result = Invoke-Probe 'dc01'

    $result.ExitCode | Should -Not -Be 0
    $result.Output -join "`n" | Should -BeLike "*matches more than one*"
    $script:log | Should -Not -Exist
  }
}
