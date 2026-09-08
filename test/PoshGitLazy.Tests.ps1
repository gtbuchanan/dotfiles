# Tests for the lazy posh-git completion registered by profile.d/30-modules.ps1.
#
# posh-git registers its git completer as an import side effect rather than
# exporting a command, so PowerShell's module auto-loading can never trigger it
# from `git <Tab>`. The part therefore registers a stub completer that imports
# posh-git on first use and delegates; these tests pin that behaviour.
#
# Each case runs in a child pwsh, because the question is what a *pristine*
# session does -- whether posh-git is absent before the first completion and
# present after. Pester's own session has modules loaded by other suites, so
# dot-sourcing in-process could not tell the two states apart.
#
# Completion is driven through [CommandCompletion]::CompleteInput rather than
# TabExpansion2, because that is the API PSFzf's Tab handler actually calls
# (PSFzf.TabExpansion.ps1) and so is the path a real `git <Tab>` takes here.
#
# Skipped where posh-git and PSFzf are absent. The suite dot-sources the real
# part, which imports both, so it needs them installed rather than merely a git
# binary -- the hosted CI runners have git but not the modules, which the winget
# and install-ps-modules paths provision on a real host.
#
#   mise run test:pester [-- -FilterName '*lazy posh-git*']

BeforeDiscovery {
  $poshGit = [bool](Get-Module -ListAvailable posh-git)
  $psFzf = [bool](Get-Module -ListAvailable PSFzf)
  $gitBin = [bool](Get-Command git -CommandType Application -ErrorAction SilentlyContinue)
  $script:ModulesAvailable = $poshGit -and $psFzf -and $gitBin
}

Describe 'lazy posh-git completion' -Skip:(-not $script:ModulesAvailable) {

  BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $part = Join-Path $root 'home/dot_config/powershell/profile.d/30-modules.ps1'

    $script:probeDir = Join-Path ([IO.Path]::GetTempPath()) "poshgit-lazy-$PID"
    New-Item -ItemType Directory -Path $script:probeDir -Force | Out-Null
    $script:probe = Join-Path $script:probeDir 'probe.ps1'

    # Emits: a "loaded-before" line, one line per completion match, then a
    # "loaded-after" line -- enough for each case to assert on without the
    # probe needing to know which case invoked it.
    @"
param([string] `$Line, [switch] `$Twice)
Set-Alias -Name g -Value git   # mirrors profile.d/00-aliases
. '$part'
function Get-Matches([string] `$text) {
  `$ps = [System.Management.Automation.PowerShell]::Create('CurrentRunspace')
  try {
    `$c = [System.Management.Automation.CommandCompletion]::CompleteInput(
      `$text, `$text.Length, @{}, `$ps)
    `$c.CompletionMatches | ForEach-Object { `$_.CompletionText }
  }
  finally { `$ps.Dispose() }
}
"before=`$([bool](Get-Module posh-git))"
if (`$Twice) { Get-Matches `$Line | Out-Null }
Get-Matches `$Line | ForEach-Object { "match=`$_" }
"after=`$([bool](Get-Module posh-git))"
"@ | Set-Content -LiteralPath $script:probe -Encoding utf8

    function script:Complete([string] $Line, [switch] $Twice) {
      $out = & pwsh -NoLogo -NoProfile -File $script:probe -Line $Line @(if ($Twice) { '-Twice' })
      [pscustomobject]@{
        After = ($out | Where-Object { $_ -like 'after=*' }) -replace 'after=', ''
        Before = ($out | Where-Object { $_ -like 'before=*' }) -replace 'before=', ''
        Matches = @(
          $out | Where-Object { $_ -like 'match=*' } | ForEach-Object { $_ -replace 'match=', '' }
        )
      }
    }
  }

  AfterAll {
    Remove-Item $script:probeDir -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'does not load posh-git until a completion is requested' {
    $r = Complete 'git ch'
    $r.Before | Should -Be 'False'
    $r.After | Should -Be 'True'
  }

  It 'completes git subcommands through the stub' {
    (Complete 'git ch').Matches | Should -Contain 'checkout'
  }

  It 'completes refs after a subcommand, preserving the trailing space' {
    # The stub must pad the input back out to the cursor: Expand-GitCommand
    # needs the trailing space that completion strips. Without the padding this
    # returns subcommands again instead of refs, and only on the first call.
    $r = Complete 'git checkout '
    $r.Matches | Should -Contain 'main'
    $r.Matches | Should -Not -Contain 'checkout'
  }

  It 'completes flags' {
    (Complete 'git commit --no-ver').Matches | Should -Contain '--no-verify'
  }

  It 'completes through the g alias' {
    (Complete 'g ch').Matches | Should -Contain 'checkout'
  }

  It 'yields the same completions once posh-git has replaced the stub' {
    # The stub is self-evicting: importing posh-git re-registers the real
    # completer over it, so a second completion in the same session must not
    # regress.
    $first = (Complete 'git ch').Matches
    $second = (Complete 'git ch' -Twice).Matches

    # Asserted non-empty first: comparing two empty results passes for any
    # breakage that yields no completions at all, which is how this case stayed
    # green on a runner where neither module was installed.
    $first | Should -Not -BeNullOrEmpty
    $second | Should -Be $first
  }
}
