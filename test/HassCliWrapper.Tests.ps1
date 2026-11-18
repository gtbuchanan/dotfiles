# Tests for the PowerShell hass-cli wrapper,
# dot_local/bin/wrappers/hass-cli.ps1, which resolves credentials and runs the
# binary itself so that an argument typed in PowerShell reaches it as typed.
#
# The chain is modelled rather than mocked: a stub resolver stands in for
# hass-vault.ps1, and a stub hass-cli.exe records the argv and environment it
# received. On Windows the stub is a real .NET Framework executable, so it
# splits its command line by the same C runtime rules hass-cli.exe does --
# what reaches the binary is the whole question, so nothing is stubbed at the
# argument boundary itself. Elsewhere it is a shell script, which still
# exercises the credential handling.
#
#   mise run test:pester [-- -FilterName '*hass-cli wrapper*']

BeforeAll {
  $script:wrapper = Join-Path (Split-Path $PSScriptRoot -Parent) `
    'home/dot_local/bin/wrappers/hass-cli.ps1'

  $script:stubSource = @'
using System;
using System.IO;

static class Program {
  static int Main(string[] args) {
    var dir = AppDomain.CurrentDomain.BaseDirectory;
    File.WriteAllLines(Path.Combine(dir, "args.txt"), args);
    File.WriteAllLines(Path.Combine(dir, "env.txt"), new[] {
      Environment.GetEnvironmentVariable("HASS_SERVER") ?? "",
      Environment.GetEnvironmentVariable("HASS_TOKEN") ?? "",
    });
    return args.Length;
  }
}
'@

  $script:stubScript = @'
#!/bin/sh
dir=$(dirname "$0")
printf '%s\n' "$@" >"$dir/args.txt"
printf '%s\n%s\n' "${HASS_SERVER-}" "${HASS_TOKEN-}" >"$dir/env.txt"
exit $#
'@

  # Compiled once per Describe: starting Windows PowerShell to drive csc costs
  # seconds, and every sandbox in a block can copy the same binary. Pester
  # removes $TestDrive when a Describe ends, so the cache is the file itself
  # rather than a remembered path. pwsh's own Add-Type can no longer emit an
  # executable, hence the detour.
  $script:compiledStub = $null
  function script:Get-CompiledStub {
    if (-not ($script:compiledStub -and (Test-Path -LiteralPath $script:compiledStub))) {
      $out = Join-Path $TestDrive 'hass-cli-stub.exe'
      powershell.exe -NoProfile -NonInteractive -Command {
        param($Source, $Out)
        Add-Type -TypeDefinition $Source -OutputAssembly $Out -OutputType ConsoleApplication
      } -args $script:stubSource, $out
      $script:compiledStub = $out
    }
    $script:compiledStub
  }

  # One disposable directory per test, laid out as the deployed tree is:
  # the wrapper in wrappers/, the resolver beside that, and mise's shim under
  # what LOCALAPPDATA will name. $TestDrive is removed by Pester.
  function script:New-WrapperSandbox {
    param(
      [ValidateSet('Resolves', 'Fails')] [string] $Vault = 'Resolves',
      [switch] $NoShim
    )

    $root = Join-Path $TestDrive (New-Guid)
    $wrappers = New-Item -ItemType Directory -Path (Join-Path $root 'wrappers')
    $shims = New-Item -ItemType Directory -Path (Join-Path $root 'appdata/mise/shims')
    Copy-Item -LiteralPath $script:wrapper -Destination $wrappers

    $resolver = switch ($Vault) {
      'Resolves' {
        @'
param([string] $Command = 'credential')
if ($Command -ne 'credential') { exit 2 }
'https://ha.example'
'token-from-vault'
exit 0
'@
      }
      'Fails' {
        @'
[Console]::Error.WriteLine('hass-vault: the vault is locked')
exit 1
'@
      }
    }
    Set-Content -LiteralPath (Join-Path $root 'hass-vault.ps1') -Value $resolver

    $shim = Join-Path $shims 'hass-cli.exe'
    if (-not $NoShim) {
      if ($IsWindows) {
        Copy-Item -LiteralPath (Get-CompiledStub) -Destination $shim
      }
      else {
        Set-Content -LiteralPath $shim -Value $script:stubScript
        chmod +x $shim
      }
    }

    [pscustomobject]@{
      Wrapper = Join-Path $wrappers 'hass-cli.ps1'
      LocalAppData = Join-Path $root 'appdata'
      ArgLog = Join-Path $shims 'args.txt'
      EnvLog = Join-Path $shims 'env.txt'
    }
  }

  function script:Invoke-Wrapper {
    param([object] $Sandbox, [string[]] $Arguments)
    $saved = $env:LOCALAPPDATA
    try {
      $env:LOCALAPPDATA = $Sandbox.LocalAppData
      & $Sandbox.Wrapper @Arguments 2>$null
    }
    finally {
      $env:LOCALAPPDATA = $saved
    }
  }
}

Describe 'hass-cli wrapper argument passing' {

  It 'delivers a JSON payload with its quotes intact' {
    $sandbox = New-WrapperSandbox
    Invoke-Wrapper $sandbox '--json', '{"entity_id": "switch.x"}'

    Get-Content -LiteralPath $sandbox.ArgLog |
      Should -Be @('--json', '{"entity_id": "switch.x"}')
  }

  It 'delivers an argument containing spaces as one argument' {
    $sandbox = New-WrapperSandbox
    Invoke-Wrapper $sandbox '--name', 'Living Room Lamp'

    Get-Content -LiteralPath $sandbox.ArgLog | Should -Be @('--name', 'Living Room Lamp')
  }

  It 'delivers a template filter pipe inside a JSON payload' {
    $sandbox = New-WrapperSandbox
    Invoke-Wrapper $sandbox '--json', '{"template": "{{ 2.6 | round }}"}'

    Get-Content -LiteralPath $sandbox.ArgLog |
      Should -Be @('--json', '{"template": "{{ 2.6 | round }}"}')
  }

  It 'delivers cmd redirection and chaining characters literally' {
    $sandbox = New-WrapperSandbox
    Invoke-Wrapper $sandbox '--json', '{"a": "x & y < z > w"}'

    Get-Content -LiteralPath $sandbox.ArgLog |
      Should -Be @('--json', '{"a": "x & y < z > w"}')
  }

  It 'propagates the exit code' {
    $sandbox = New-WrapperSandbox
    Invoke-Wrapper $sandbox 'state', 'get', 'light.kitchen'

    $LASTEXITCODE | Should -Be 3
  }
}

Describe 'hass-cli wrapper credentials' {

  It 'hands hass-cli the resolved server and token' {
    $sandbox = New-WrapperSandbox
    Invoke-Wrapper $sandbox 'state', 'list'

    Get-Content -LiteralPath $sandbox.EnvLog |
      Should -Be @('https://ha.example', 'token-from-vault')
  }

  It "removes the token from the caller's environment afterwards" {
    $sandbox = New-WrapperSandbox
    $saved = $env:HASS_TOKEN
    try {
      $env:HASS_TOKEN = $null
      Invoke-Wrapper $sandbox 'state', 'list'

      Test-Path Env:HASS_TOKEN | Should -BeFalse
    }
    finally { $env:HASS_TOKEN = $saved }
  }

  It 'restores a token the caller had already set' {
    $sandbox = New-WrapperSandbox
    $saved = $env:HASS_TOKEN
    try {
      $env:HASS_TOKEN = 'callers-own'
      Invoke-Wrapper $sandbox 'state', 'list'

      $env:HASS_TOKEN | Should -Be 'callers-own'
    }
    finally { $env:HASS_TOKEN = $saved }
  }

  It 'exits 1 when credentials do not resolve' {
    $sandbox = New-WrapperSandbox -Vault Fails
    Invoke-Wrapper $sandbox 'state', 'list'

    $LASTEXITCODE | Should -Be 1
  }

  It 'does not run hass-cli when credentials do not resolve' {
    $sandbox = New-WrapperSandbox -Vault Fails
    Invoke-Wrapper $sandbox 'state', 'list'

    Test-Path -LiteralPath $sandbox.ArgLog | Should -BeFalse
  }

  It 'exits 127 when the mise shim is missing' {
    $sandbox = New-WrapperSandbox -NoShim
    Invoke-Wrapper $sandbox 'state', 'list'

    $LASTEXITCODE | Should -Be 127
  }
}
