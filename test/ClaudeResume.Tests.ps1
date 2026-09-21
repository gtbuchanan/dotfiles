# Tests for ccr, the PowerShell half of the resume shortcut, defined in
# profile.d/10-functions.ps1. It asks pane-session which conversation belongs
# to this pane and hands the id to `claude --resume`, falling back to
# `--continue` where the pane has no record.
#
# This is the half that matters most on Windows: psmux runs there, and the
# bash half is unreachable from a pwsh pane. test/claude_resume_test.sh makes
# the same assertions of the bash function, so the two stay in step.
#
# Each case runs in a child pwsh rather than dot-sourcing in-process: the part
# defines `ls` as eza and `copilot` as a wrapper, and installing either into
# Pester's own session would reach the suites that run after this one.
#
# Nothing real is reached. $HOME points at a sandbox holding a stub
# pane-session, so the function's own lookup path runs without a production
# seam, and a `claude` function shadowing the executable records the argv it
# was handed -- which is the whole claim these tests make.
#
#   mise run test:pester [-- -FilterName '*ccr*']

BeforeDiscovery {
  # Skipping is decided here because Pester evaluates -Skip while discovering,
  # before any BeforeAll has run.
  $script:ChezmoiAvailable = [bool](Get-Command chezmoi -ErrorAction SilentlyContinue)
}

Describe 'ccr session resume' -Skip:(-not $script:ChezmoiAvailable) {

  BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    $script:source = Join-Path $script:root `
      'home/dot_config/powershell/profile.d/10-functions.ps1.tmpl'

    $script:rendered = Join-Path ([IO.Path]::GetTempPath()) "ccr-part-$PID.ps1"
    Get-Content -LiteralPath $script:source -Raw |
      chezmoi execute-template --source (Join-Path $script:root 'home') --no-tty |
      Set-Content -LiteralPath $script:rendered -Encoding utf8

    # Shadows `claude` and `clear` before the part is dot-sourced, so ccr's own
    # call lands on the recorder rather than on a real session.
    $script:probeSource = @'
param(
  [string] $Rendered,
  [string] $Log,
  [string] $Sandbox,
  [Parameter(ValueFromRemainingArguments)] [string[]] $Rest
)
# `clear` is an alias for Clear-Host, and an alias outranks a function, so the
# stub has to replace the alias or the real one runs and fails for want of a
# console handle.
function Invoke-NoOp { }
Set-Alias -Name clear -Value Invoke-NoOp -Force
function claude { Set-Content -LiteralPath $Log -Value $args -Encoding utf8 }
# $HOME is read-only rather than constant, so -Force redirects the lookup
# without the part needing a path seam of its own.
Set-Variable -Name HOME -Value $Sandbox -Force
. $Rendered
if ($Rest) { ccr @Rest } else { ccr }
'@
  }

  AfterAll {
    if ($script:rendered) {
      Remove-Item -LiteralPath $script:rendered -Force -ErrorAction SilentlyContinue
    }
  }

  BeforeEach {
    $script:sandbox = Join-Path ([IO.Path]::GetTempPath()) "ccr-test-$PID-$(New-Guid)"
    New-Item -ItemType Directory -Path (Join-Path $script:sandbox '.claude') -Force | Out-Null
    $script:log = Join-Path $script:sandbox 'claude-argv'
    $script:probe = Join-Path $script:sandbox 'probe.ps1'
    Set-Content -LiteralPath $script:probe -Value $script:probeSource -Encoding utf8

    # Stands in for the recorded pane, printing $SessionId as the id it
    # resolves to. Left unwritten, the lookup finds no script at all.
    function script:Set-PaneRecord {
      param([string] $SessionId)
      $stub = Join-Path $script:sandbox '.claude/pane-session'
      Set-Content -LiteralPath $stub -Encoding ascii -Value @"
#!/usr/bin/env bash
printf '%s' '$SessionId'
"@
    }

    function script:Invoke-Ccr {
      & pwsh -NoProfile -File $script:probe `
        -Rendered $script:rendered -Log $script:log -Sandbox $script:sandbox @args |
        Out-Null
      if (Test-Path -LiteralPath $script:log) {
        @(Get-Content -LiteralPath $script:log)
      }
      else { @() }
    }
  }

  AfterEach {
    Remove-Item -LiteralPath $script:sandbox -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'resumes the session recorded for this pane' {
    Set-PaneRecord '11111111-2222-3333-4444-555555555555'

    Invoke-Ccr | Should -Be @('--resume', '11111111-2222-3333-4444-555555555555')
  }

  It 'continues the newest session when the pane has no record' {
    Set-PaneRecord ''

    Invoke-Ccr | Should -Be @('--continue')
  }

  It 'forwards its own arguments to claude' {
    Set-PaneRecord '11111111-2222-3333-4444-555555555555'

    Invoke-Ccr '--model' 'opus' |
      Should -Be @('--resume', '11111111-2222-3333-4444-555555555555', '--model', 'opus')
  }

  It 'starts claude even where no pane-session script is installed' {
    Invoke-Ccr | Should -Be @('--continue')
  }
}
