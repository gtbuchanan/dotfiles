# Tests for the PowerShell half of the hass-cli wrapper,
# dot_local/bin/wrappers/hass-cli.ps1, which exists so an argument typed in
# PowerShell reaches the binary as it was typed.
#
# The chain is modelled rather than mocked: a stub .cmd standing in for the
# credential wrapper forwards `%*` to pwsh, which parses a command line by the
# same rules hass-cli.exe does. What each stage passes on is the whole
# question, so nothing here is stubbed at the argument boundary itself.
#
#   mise run test:pester [-- -FilterName '*hass-cli wrapper*']

Describe 'hass-cli wrapper argument passing' {

  BeforeAll {
    $script:wrapper = Join-Path (Split-Path $PSScriptRoot -Parent) `
      'home/dot_local/bin/wrappers/hass-cli.ps1'
  }

  BeforeEach {
    $script:sandbox = Join-Path ([IO.Path]::GetTempPath()) "hass-cli-wrapper-test-$PID-$(New-Guid)"
    New-Item -ItemType Directory -Path $script:sandbox | Out-Null
    $script:argLog = Join-Path $script:sandbox 'args.txt'

    Copy-Item -LiteralPath $script:wrapper -Destination (Join-Path $script:sandbox 'hass-cli.ps1')

    # Stands in for the credential wrapper: same `%*` hand-off to a program
    # that parses its own command line, so an argument mangled between
    # PowerShell and cmd is mangled here too.
    Set-Content -LiteralPath (Join-Path $script:sandbox 'hass-cli.cmd') -Encoding ascii -Value @'
@echo off
pwsh -NoLogo -NoProfile -File "%~dp0printargs.ps1" %*
exit /b %ERRORLEVEL%
'@

    Set-Content -LiteralPath (Join-Path $script:sandbox 'printargs.ps1') -Encoding utf8 -Value @'
param([Parameter(ValueFromRemainingArguments)] [string[]] $Arguments)
Set-Content -LiteralPath (Join-Path $PSScriptRoot 'args.txt') -Value $Arguments -Encoding utf8
exit $Arguments.Count
'@

    function script:Invoke-Wrapper {
      & (Join-Path $script:sandbox 'hass-cli.ps1') @args
    }

    function script:Get-ReceivedArgv {
      @(Get-Content -LiteralPath $script:argLog)
    }
  }

  AfterEach {
    Remove-Item $script:sandbox -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'delivers a JSON payload with its quotes intact' {
    Invoke-Wrapper --json '{"entity_id": "switch.x"}'

    Get-ReceivedArgv | Should -Be @('--json', '{"entity_id": "switch.x"}')
  }

  It 'delivers an argument containing spaces as one argument' {
    Invoke-Wrapper --name 'Living Room Lamp'

    Get-ReceivedArgv | Should -Be @('--name', 'Living Room Lamp')
  }

  It 'propagates the exit code' {
    Invoke-Wrapper state get light.kitchen

    $LASTEXITCODE | Should -Be 3
  }
}
