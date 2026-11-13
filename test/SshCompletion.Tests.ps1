# Tests for the ssh host completion registered by profile.d/45-remote.ps1,
# which offers the Host aliases that ~/.ssh/config defines, following its
# Include directives the way ssh does.
#
# Each case runs in a child pwsh against a sandboxed $HOME, as in
# RdpCommand.Tests.ps1, so neither the host's real ssh config nor Pester's own
# session is touched. Completion is driven through
# [CommandCompletion]::CompleteInput, the API PSFzf's Tab handler calls.
#
# The part renders as an ewn host, which leaves out the personal-only rdp block
# and with it every key a `chezmoi init` config would supply; CI has none.
#
#   mise run test:pester [-- -FilterName '*ssh host completion*']

BeforeDiscovery {
  $script:ChezmoiAvailable = [bool](Get-Command chezmoi -ErrorAction SilentlyContinue)
}

Describe 'ssh host completion' -Skip:(-not $script:ChezmoiAvailable) {

  BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    $script:source = Join-Path $script:root `
      'home/dot_config/powershell/profile.d/45-remote.ps1.tmpl'

    $script:rendered = Join-Path ([IO.Path]::GetTempPath()) "ssh-part-$PID.ps1"
    Get-Content -LiteralPath $script:source -Raw |
      chezmoi execute-template --source (Join-Path $script:root 'home') --no-tty `
        --override-data '{"hosttype":"ewn"}' |
      Set-Content -LiteralPath $script:rendered -Encoding utf8

    $script:probeSource = @'
param([string] $Rendered, [string] $Sandbox, [string] $Line)
$ErrorActionPreference = 'Stop'
Set-Variable -Name HOME -Value $Sandbox -Force
. $Rendered
$ps = [System.Management.Automation.PowerShell]::Create('CurrentRunspace')
try {
  $c = [System.Management.Automation.CommandCompletion]::CompleteInput(
    $Line, $Line.Length, @{}, $ps)
  $c.CompletionMatches | ForEach-Object { $_.CompletionText }
}
finally { $ps.Dispose() }
'@

    function script:Complete([string] $Line) {
      @(& pwsh -NoLogo -NoProfile -NonInteractive -File $script:probe `
          -Rendered $script:rendered -Sandbox $script:sandbox -Line $Line)
    }

    function script:Set-SshFile([string] $RelativePath, [string[]] $Lines) {
      $path = Join-Path $script:sandbox ".ssh/$RelativePath"
      New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
      Set-Content -LiteralPath $path -Value $Lines -Encoding utf8
    }
  }

  AfterAll {
    if ($script:rendered) {
      Remove-Item -LiteralPath $script:rendered -Force -ErrorAction SilentlyContinue
    }
  }

  BeforeEach {
    $script:sandbox = Join-Path ([IO.Path]::GetTempPath()) "ssh-test-$PID-$(New-Guid)"
    New-Item -ItemType Directory -Path (Join-Path $script:sandbox '.ssh') -Force | Out-Null
    $script:probe = Join-Path $script:sandbox 'probe.ps1'
    Set-Content -LiteralPath $script:probe -Value $script:probeSource -Encoding utf8
  }

  AfterEach {
    Remove-Item -LiteralPath $script:sandbox -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'completes aliases from the config and every file it includes' {
    Set-SshFile 'config' @(
      'Include ./*.conf'
      'Include ~/inventory/ssh/*.conf'
      'Host dev01'
    )
    Set-SshFile 'local.conf' 'Host dc01'
    New-Item -ItemType Directory -Path (Join-Path $script:sandbox 'inventory/ssh') -Force |
      Out-Null
    Set-Content -LiteralPath (Join-Path $script:sandbox 'inventory/ssh/lab.conf') `
      -Value @('Host docker01', '  HostName docker01.example', 'Host docker02 d2') -Encoding utf8

    Complete 'ssh d' | Should -Be @('d2', 'dc01', 'dev01', 'docker01', 'docker02')
  }

  It 'leaves out wildcard and negated patterns' {
    Set-SshFile 'config' @('Host *.example !bastion db01', 'Host d?')

    Complete 'ssh ' | Should -Be @('db01')
  }

  It 'keeps a user@ prefix on the completed host' {
    Set-SshFile 'config' 'Host docker01'

    Complete 'ssh taylor@do' | Should -Be @('taylor@docker01')
  }

  It 'offers no hosts for an option that takes an argument' {
    Set-SshFile 'config' 'Host docker01'

    Complete 'ssh -l d' | Should -Not -Contain 'docker01'
  }
}
