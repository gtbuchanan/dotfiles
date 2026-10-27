# Tests for the mise tab completion registered by profile.d/15-mise.ps1, under
# both its own name and the `m` alias from profile.d/00-aliases.
#
# A native completer is looked up by the name typed, not the command it
# resolves to, so one registered for `mise` never fires for `m`; the part has to
# register both names. These cases pin that.
#
# Each case runs in a child pwsh against the real mise, because the completer
# shells out to `mise __complete_word__` and what is under test is that a
# pristine session ends up with it wired to both names. The cache directory is
# sandboxed so the run neither reads nor writes the host's entries.
#
# Completion is driven through [CommandCompletion]::CompleteInput, the API
# PSFzf's Tab handler calls, as in PoshGitLazy.Tests.ps1.
#
# Skipped where mise is absent.
#
#   mise run test:pester [-- -FilterName '*mise completion*']

BeforeDiscovery {
  $script:MiseAvailable = [bool](
    Get-Command mise -CommandType Application -ErrorAction SilentlyContinue
  )
}

Describe 'mise completion' -Skip:(-not $script:MiseAvailable) {

  BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $parts = Join-Path $root 'home/dot_config/powershell/profile.d'

    $script:sandbox = Join-Path ([IO.Path]::GetTempPath()) "mise-completion-$PID-$(New-Guid)"
    New-Item -ItemType Directory -Path $script:sandbox -Force | Out-Null
    $script:probe = Join-Path $script:sandbox 'probe.ps1'

    @"
param([string] `$Line)
Set-Alias -Name m -Value mise   # mirrors profile.d/00-aliases
. '$(Join-Path $parts '05-init-cache.ps1')'
. '$(Join-Path $parts '15-mise.ps1')'
`$ps = [System.Management.Automation.PowerShell]::Create('CurrentRunspace')
try {
  `$c = [System.Management.Automation.CommandCompletion]::CompleteInput(
    `$Line, `$Line.Length, @{}, `$ps)
  `$c.CompletionMatches | ForEach-Object { `$_.CompletionText }
}
finally { `$ps.Dispose() }
"@ | Set-Content -LiteralPath $script:probe -Encoding utf8

    function script:Complete([string] $Line) {
      $vars = @{
        LOCALAPPDATA = $script:sandbox
        XDG_CACHE_HOME = $script:sandbox
      }
      $saved = @{}
      foreach ($name in $vars.Keys) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name)
        [Environment]::SetEnvironmentVariable($name, $vars[$name])
      }
      try {
        @(& pwsh -NoLogo -NoProfile -File $script:probe -Line $Line)
      }
      finally {
        foreach ($name in $saved.Keys) {
          [Environment]::SetEnvironmentVariable($name, $saved[$name])
        }
      }
    }
  }

  AfterAll {
    Remove-Item $script:sandbox -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'completes mise subcommands' {
    Complete 'mise ru' | Should -Contain 'run'
  }

  It 'completes through the m alias' {
    Complete 'm ru' | Should -Contain 'run'
  }
}
