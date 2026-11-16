# Tests for Clear-PsmuxLayoutOnExit, defined in profile.d/25-psmux.ps1. When
# the last psmux pane's own shell exits by hand, it deletes the layout
# psmux-snapshot saved, so the next server boot restores nothing. A reboot
# kills the shell without running its exit handler, which leaves the layout
# for psmux-restore to rebuild.
#
# Each case runs in a child pwsh: the function reads $env:TMUX, $PID and $HOME,
# and the part registers an exit handler whenever $env:TMUX is set, neither of
# which belongs in Pester's own session. A `psmux` function shadowing the
# executable answers `list-panes` with the pane pids the case chose, and logs
# its argv so a case can tell which server was asked.
#
#   mise run test:pester [-- -FilterName '*psmux layout*']

Describe 'psmux layout forgotten on exit' {

  BeforeAll {
    $script:part = Join-Path (Split-Path $PSScriptRoot -Parent) `
      'home/dot_config/powershell/profile.d/25-psmux.ps1'

    # {PID} in -PanePids stands for the probe's own pid, so a case can make the
    # probe the pane's shell or a shell nested inside it. The pids arrive
    # comma-joined because `pwsh -File` cannot bind an array parameter.
    $script:probeSource = @'
param(
  [string] $Part,
  [string] $Sandbox,
  [string] $Tmux,
  [string] $PanePids
)
function psmux {
  Add-Content -LiteralPath (Join-Path $Sandbox 'psmux-argv') -Value ($args -join ' ')
  $PanePids -split ',' | ForEach-Object { $_ -replace '\{PID\}', $PID }
}
Set-Variable -Name HOME -Value $Sandbox -Force
$env:TMUX = $Tmux
. $Part
Clear-PsmuxLayoutOnExit
'@
  }

  BeforeEach {
    $script:sandbox = Join-Path ([IO.Path]::GetTempPath()) "psmux-layout-test-$PID-$(New-Guid)"
    New-Item -ItemType Directory -Path (Join-Path $script:sandbox '.psmux') -Force | Out-Null
    $script:layout = Join-Path $script:sandbox '.psmux/layout.json'
    $script:probe = Join-Path $script:sandbox 'probe.ps1'
    Set-Content -LiteralPath $script:probe -Value $script:probeSource -Encoding utf8

    function script:Set-Layout {
      param([string] $Namespace)
      Set-Content -LiteralPath $script:layout -Encoding utf8 `
        -Value "{`"namespace`": `"$Namespace`", `"sessions`": []}"
    }

    function script:Invoke-Exit {
      param(
        [string[]] $PanePids,
        [string] $Tmux = '/tmp/psmux-1/default,100,0'
      )
      & pwsh -NoProfile -File $script:probe -Part $script:part `
        -Sandbox $script:sandbox -Tmux $Tmux -PanePids ($PanePids -join ',') | Out-Null
    }
  }

  AfterEach {
    Remove-Item -LiteralPath $script:sandbox -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'deletes the layout when the last pane''s shell exits' {
    Set-Layout 'default'

    Invoke-Exit -PanePids '{PID}'

    Test-Path -LiteralPath $script:layout | Should -BeFalse
  }

  It 'keeps the layout while other panes remain' {
    Set-Layout 'default'

    Invoke-Exit -PanePids '{PID}', '424242'

    Test-Path -LiteralPath $script:layout | Should -BeTrue
  }

  It 'keeps the layout when a shell nested in the last pane exits' {
    Set-Layout 'default'

    Invoke-Exit -PanePids '424242'

    Test-Path -LiteralPath $script:layout | Should -BeTrue
  }

  It 'keeps a layout another server saved' {
    Set-Layout 'default'

    Invoke-Exit -PanePids '{PID}' -Tmux '/tmp/psmux-1/scratch,100,0'

    Test-Path -LiteralPath $script:layout | Should -BeTrue
  }

  It 'asks a named server for its panes by name' {
    Set-Layout 'scratch'

    Invoke-Exit -PanePids '{PID}' -Tmux '/tmp/psmux-1/scratch,100,0'

    Get-Content -LiteralPath (Join-Path $script:sandbox 'psmux-argv') |
      Should -Be '-L scratch list-panes -a -F #{pane_pid}'
  }

  It 'asks psmux nothing outside psmux' {
    Set-Layout 'default'

    Invoke-Exit -PanePids '{PID}' -Tmux ''

    Test-Path -LiteralPath (Join-Path $script:sandbox 'psmux-argv') | Should -BeFalse
  }
}
